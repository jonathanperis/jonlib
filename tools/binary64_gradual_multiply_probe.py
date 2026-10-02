#!/usr/bin/env python3
"""Private gradual-output binary64 multiply: rational/native and CPU-1/2/JS gates.

Subprocess retention, fresh compilation and drift checks follow the existing
private FMA harness. The arithmetic oracle and corpus are independent of the
candidate. Every reported observation includes its operation kind.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import re
import shutil
import subprocess
import time

from binary64_gradual_multiply_oracle import (BOUNDS, FRACTION, KINDS, SIGN, checked,
                                    decode64, in_domain, nearest64, power2, word)
from conformance import BUILD, ROOT, checkout, source_gate

CHUNK = 256
LINE = 16
WIDTH = 5
SEED = 0x64A6D00D
FIELDS = ('ah', 'al', 'bh', 'bl')
FLAGS = ['-std=c11', '-O2', '-frounding-math', '-fno-fast-math',
         '-ffp-contract=off', '-fno-lto']
DEPENDENCIES = ('src/binary64_gradual_multiply.bend', 'src/binary64_fma.bend',
                'tools/binary64_gradual_multiply_probe.py', 'tools/binary64_gradual_multiply_oracle.py',
                'tools/binary64_fma_oracle.py', 'tests/test_binary64_gradual_multiply.py',
                'tools/conformance.py', 'LAWS.bend', 'PROOF.bend', 'toolchain.json')


def normal(exponent, fraction=0, sign=0):
    if (type(exponent) is not int or type(fraction) is not int or type(sign) is not int
            or not -1022 <= exponent <= 1023 or not 0 <= fraction <= FRACTION or sign not in (0, 1)):
        raise ValueError('Invalid normal binary64 parameters')
    return (sign << 63) | ((exponent + 1023) << 52) | fraction


# Fixed IEEE encodings make these controls independent of both rounding paths.
HAND = (
    (0x2ea0000000000000, 0x0e0fffffffffffff, 0x0000000000000000, 'half_min_subnormal_below'),
    (0xaea0000000000000, 0x0e0fffffffffffff, 0x8000000000000000, 'negative_half_min_subnormal_below'),
    (0x2ea0000000000000, 0x0e10000000000000, 0x0000000000000000, 'half_min_subnormal_tie'),
    (0xaea0000000000000, 0x0e10000000000000, 0x8000000000000000, 'negative_half_min_subnormal_tie'),
    (0x2ea0000000000000, 0x0e10000000000001, 0x0000000000000001, 'half_min_subnormal_above'),
    (0xaea0000000000000, 0x0e10000000000001, 0x8000000000000001, 'negative_half_min_subnormal_above'),
    (0x2ea0000000000000, 0x0e27ffffffffffff, 0x0000000000000001, 'subnormal_tie_odd_lower_neighbor_-1'),
    (0x2ea0000000000000, 0x0e28000000000000, 0x0000000000000002, 'subnormal_tie_odd_lower_neighbor_+0'),
    (0x2ea0000000000000, 0x0e28000000000001, 0x0000000000000002, 'subnormal_tie_odd_lower_neighbor_+1'),
    (0x2ea0000000000000, 0x0e33ffffffffffff, 0x0000000000000002, 'subnormal_tie_even_lower_neighbor_-1'),
    (0x2ea0000000000000, 0x0e34000000000000, 0x0000000000000002, 'subnormal_tie_even_lower_neighbor_+0'),
    (0x2ea0000000000000, 0x0e34000000000001, 0x0000000000000003, 'subnormal_tie_even_lower_neighbor_+1'),
    (0x2ea0000000000000, 0x115ffffffffffffe, 0x000fffffffffffff, 'maximum_subnormal_exact'),
    (0x2ea0000000000000, 0x115fffffffffffff, 0x0010000000000000, 'minimum_normal_half_tie'),
    (0x2ea0000000000000, 0x1160000000000000, 0x0010000000000000, 'minimum_normal_exact'),
    (0x2eafffffffffffff, 0x114fffffffffffff, 0x000fffffffffffff, 'sum_minus1024_maximum_product'),
    (0x2ea8000000000000, 0x1158000000000000, 0x0012000000000000, 'sum_minus1023_already_normal'),
    (0x2eafffffffffffff, 0x115fffffffffffff, 0x001ffffffffffffe, 'sum_minus1023_maximum_product'),
    (0x2ea0000000000000, 0x1160000000000000, 0x0010000000000000, 'sum_minus1022_minimum_product'),
    (0x2ea0000000000000, 0x0e00000000000000, 0x0000000000000000, 'k106_below_half'),
    (0x2eafffffffffffff, 0x0e0fffffffffffff, 0x0000000000000001, 'k106_above_half'),
    (0x2eafffffffffffff, 0x0dffffffffffffff, 0x0000000000000000, 'k107_largest_product_zero'),
    (0x2ea0000000000000, 0x08a0000000000000, 0x0000000000000000, 'k192_smallest_product_zero'),
    (0x2eafffffffffffff, 0x88afffffffffffff, 0x8000000000000000, 'k192_largest_negative_product_zero'),
    (0x2ea0000000000001, 0x1150000000000004, 0x0008000000000003, 'double_round_above_even_subnormal_tie'),
    (0xaea0000000000001, 0x1150000000000004, 0x8008000000000003, 'double_round_above_even_subnormal_tie_negative'),
    (0x2ea0000000000001, 0x115ffffffffffffd, 0x000fffffffffffff, 'double_round_below_minimum_normal_tie'),
    (0xaea0000000000001, 0x115ffffffffffffd, 0x800fffffffffffff, 'double_round_below_minimum_normal_tie_negative'),
    (0x2ea0000000000001, 0x0e0fffffffffffff, 0x0000000000000001, 'double_round_above_half_minimum_subnormal'),
    (0xaea0000000000001, 0x0e0fffffffffffff, 0x8000000000000001, 'double_round_above_half_minimum_subnormal_negative'),
    (0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 'zero_pair_00'),
    (0x0000000000000000, 0x08a0000000000000, 0x0000000000000000, 'zero_first_00'),
    (0x2ea0000000000000, 0x0000000000000000, 0x0000000000000000, 'zero_second_00'),
    (0x0000000000000000, 0x8000000000000000, 0x8000000000000000, 'zero_pair_01'),
    (0x0000000000000000, 0x88a0000000000000, 0x8000000000000000, 'zero_first_01'),
    (0x2ea0000000000000, 0x8000000000000000, 0x8000000000000000, 'zero_second_01'),
    (0x8000000000000000, 0x0000000000000000, 0x8000000000000000, 'zero_pair_10'),
    (0x8000000000000000, 0x08a0000000000000, 0x8000000000000000, 'zero_first_10'),
    (0xaea0000000000000, 0x0000000000000000, 0x8000000000000000, 'zero_second_10'),
    (0x8000000000000000, 0x8000000000000000, 0x0000000000000000, 'zero_pair_11'),
    (0x8000000000000000, 0x88a0000000000000, 0x0000000000000000, 'zero_first_11'),
    (0xaea0000000000000, 0x8000000000000000, 0x0000000000000000, 'zero_second_11'),
    (0x2ff0000000000000, 0x8fd5555555555555, 0x8001555555555555, 'reachable_tiny_z_exp_-256'),
    (0x2f30000000000000, 0x8d95555555555555, 0x8000000000000001, 'reachable_tiny_z_exp_-268'),
    (0x2f20000000000000, 0x8d65555555555555, 0x8000000000000000, 'reachable_tiny_z_exp_-269'),
    (0x2eb0000000000000, 0x8c15555555555555, 0x8000000000000000, 'reachable_tiny_z_exp_-276'),
    (0x3ff8000000000000, 0x3ff5555555555555, 0x4000000000000000, 'normal_rounding_carry'),
    (0x3ff8000000000000, 0x3ff0000000000001, 0x3ff8000000000002, 'normal_odd_lower_tie'),
    (0x3ff8000000000000, 0x3ff0000000000003, 0x3ff8000000000004, 'normal_even_lower_tie'),
    (0x3fffffffffffffff, 0x3fffffffffffffff, 0x400ffffffffffffe, 'maximum_contract_product'),
    (0x2ea0000000000000, 0x3ff0000000000000, 0x2ea0000000000000, 'lowest_first_exponent_normal_second'),
    (0x3ff0000000000000, 0x08a0000000000000, 0x08a0000000000000, 'lowest_second_exponent_normal_first'),
    (0x0000000000000001, 0x3ff0000000000000, None, 'reject_first_0_0'),
    (0x0000000000000001, 0x8000000000000000, None, 'reject_first_even_with_zero_0_0'),
    (0x8000000000000001, 0x3ff0000000000000, None, 'reject_first_0_1'),
    (0x8000000000000001, 0x8000000000000000, None, 'reject_first_even_with_zero_0_1'),
    (0x000fffffffffffff, 0x3ff0000000000000, None, 'reject_first_1_0'),
    (0x000fffffffffffff, 0x8000000000000000, None, 'reject_first_even_with_zero_1_0'),
    (0x800fffffffffffff, 0x3ff0000000000000, None, 'reject_first_1_1'),
    (0x800fffffffffffff, 0x8000000000000000, None, 'reject_first_even_with_zero_1_1'),
    (0x0010000000000000, 0x3ff0000000000000, None, 'reject_first_2_0'),
    (0x0010000000000000, 0x8000000000000000, None, 'reject_first_even_with_zero_2_0'),
    (0x8010000000000000, 0x3ff0000000000000, None, 'reject_first_2_1'),
    (0x8010000000000000, 0x8000000000000000, None, 'reject_first_even_with_zero_2_1'),
    (0x7ff0000000000000, 0x3ff0000000000000, None, 'reject_first_3_0'),
    (0x7ff0000000000000, 0x8000000000000000, None, 'reject_first_even_with_zero_3_0'),
    (0xfff0000000000000, 0x3ff0000000000000, None, 'reject_first_3_1'),
    (0xfff0000000000000, 0x8000000000000000, None, 'reject_first_even_with_zero_3_1'),
    (0x7ff8000000000000, 0x3ff0000000000000, None, 'reject_first_4_0'),
    (0x7ff8000000000000, 0x8000000000000000, None, 'reject_first_even_with_zero_4_0'),
    (0xfff8000000000000, 0x3ff0000000000000, None, 'reject_first_4_1'),
    (0xfff8000000000000, 0x8000000000000000, None, 'reject_first_even_with_zero_4_1'),
    (0x7ff0000000000001, 0x3ff0000000000000, None, 'reject_first_5_0'),
    (0x7ff0000000000001, 0x8000000000000000, None, 'reject_first_even_with_zero_5_0'),
    (0xfff0000000000001, 0x3ff0000000000000, None, 'reject_first_5_1'),
    (0xfff0000000000001, 0x8000000000000000, None, 'reject_first_even_with_zero_5_1'),
    (0x4000000000000000, 0x3ff0000000000000, None, 'reject_first_6_0'),
    (0x4000000000000000, 0x8000000000000000, None, 'reject_first_even_with_zero_6_0'),
    (0xc000000000000000, 0x3ff0000000000000, None, 'reject_first_6_1'),
    (0xc000000000000000, 0x8000000000000000, None, 'reject_first_even_with_zero_6_1'),
    (0x2e90000000000000, 0x3ff0000000000000, None, 'reject_first_7_0'),
    (0x2e90000000000000, 0x8000000000000000, None, 'reject_first_even_with_zero_7_0'),
    (0xae90000000000000, 0x3ff0000000000000, None, 'reject_first_7_1'),
    (0xae90000000000000, 0x8000000000000000, None, 'reject_first_even_with_zero_7_1'),
    (0x3ff0000000000000, 0x0000000000000001, None, 'reject_second_0_0'),
    (0x0000000000000000, 0x0000000000000001, None, 'reject_second_even_with_zero_0_0'),
    (0x3ff0000000000000, 0x8000000000000001, None, 'reject_second_0_1'),
    (0x0000000000000000, 0x8000000000000001, None, 'reject_second_even_with_zero_0_1'),
    (0x3ff0000000000000, 0x000fffffffffffff, None, 'reject_second_1_0'),
    (0x0000000000000000, 0x000fffffffffffff, None, 'reject_second_even_with_zero_1_0'),
    (0x3ff0000000000000, 0x800fffffffffffff, None, 'reject_second_1_1'),
    (0x0000000000000000, 0x800fffffffffffff, None, 'reject_second_even_with_zero_1_1'),
    (0x3ff0000000000000, 0x0010000000000000, None, 'reject_second_2_0'),
    (0x0000000000000000, 0x0010000000000000, None, 'reject_second_even_with_zero_2_0'),
    (0x3ff0000000000000, 0x8010000000000000, None, 'reject_second_2_1'),
    (0x0000000000000000, 0x8010000000000000, None, 'reject_second_even_with_zero_2_1'),
    (0x3ff0000000000000, 0x7ff0000000000000, None, 'reject_second_3_0'),
    (0x0000000000000000, 0x7ff0000000000000, None, 'reject_second_even_with_zero_3_0'),
    (0x3ff0000000000000, 0xfff0000000000000, None, 'reject_second_3_1'),
    (0x0000000000000000, 0xfff0000000000000, None, 'reject_second_even_with_zero_3_1'),
    (0x3ff0000000000000, 0x7ff8000000000000, None, 'reject_second_4_0'),
    (0x0000000000000000, 0x7ff8000000000000, None, 'reject_second_even_with_zero_4_0'),
    (0x3ff0000000000000, 0xfff8000000000000, None, 'reject_second_4_1'),
    (0x0000000000000000, 0xfff8000000000000, None, 'reject_second_even_with_zero_4_1'),
    (0x3ff0000000000000, 0x7ff0000000000001, None, 'reject_second_5_0'),
    (0x0000000000000000, 0x7ff0000000000001, None, 'reject_second_even_with_zero_5_0'),
    (0x3ff0000000000000, 0xfff0000000000001, None, 'reject_second_5_1'),
    (0x0000000000000000, 0xfff0000000000001, None, 'reject_second_even_with_zero_5_1'),
    (0x3ff0000000000000, 0x4000000000000000, None, 'reject_second_6_0'),
    (0x0000000000000000, 0x4000000000000000, None, 'reject_second_even_with_zero_6_0'),
    (0x3ff0000000000000, 0xc000000000000000, None, 'reject_second_6_1'),
    (0x0000000000000000, 0xc000000000000000, None, 'reject_second_even_with_zero_6_1'),
    (0x3ff0000000000000, 0x0890000000000000, None, 'reject_second_7_0'),
    (0x0000000000000000, 0x0890000000000000, None, 'reject_second_even_with_zero_7_0'),
    (0x3ff0000000000000, 0x8890000000000000, None, 'reject_second_7_1'),
    (0x0000000000000000, 0x8890000000000000, None, 'reject_second_even_with_zero_7_1'),
)


def samples():
    """Deterministic asymmetric-domain and significand stratification."""
    rows, seen = [], {}
    def add(a, b, label):
        key = (word(a, 64), word(b, 64))
        if key not in seen:
            row = dict(kind='multiply', labels=[])
            row.update(zip(FIELDS, [part for value in (a, b) for part in (value >> 32, value & 0xffffffff)]))
            rows.append(row); seen[key] = row
        if label not in seen[key]['labels']: seen[key]['labels'].append(label)
    def signs(a, b, label):
        for sa in (0, SIGN):
            for sb in (0, SIGN): add(a ^ sa, b ^ sb, label)
    for a, b, expected, label in HAND:
        result = checked('multiply', a >> 32, a & 0xffffffff, b >> 32, b & 0xffffffff)
        bits = None if result is None else (result[0] << 32) | result[1]
        if bits != expected: raise ValueError('Rational oracle disagrees with fixed hand vector')
        add(a, b, label)
    signs(0, 0, 'all-zero-sign-combinations')
    for operand, (minimum, maximum) in enumerate(BOUNDS):
        for exponent in (minimum, minimum+1, -1, maximum):
            for fraction in (0, 1, FRACTION):
                pair = [0, 0]; pair[operand] = normal(exponent, fraction)
                signs(*pair, f'zero-and-nonzero-operand-{operand}')
    rng = random.Random(SEED)
    # Every permitted exponent, both signs and both exact product top bits.
    for operand, (minimum, maximum) in enumerate(BOUNDS):
        for exponent in range(minimum, maximum+1):
            for top in (0, 1):
                pair = [normal(0, FRACTION if top else 0)]*2
                pair[operand] = normal(exponent, FRACTION if top else 1)
                signs(*pair, f'every-exponent-operand-{operand}-top-{top}')
    # Every possible gradual shift, not just underflow-transition neighborhoods.
    patterns = (0, 1, 2, (1<<31)-1, 1<<32, 1<<51, FRACTION-1, FRACTION)
    for k in range(53, 193):
        for i, fraction in enumerate(patterns):
            signs(normal(-277, fraction), normal(-k-693, patterns[-1-i]), f'gradual-shift-k-{k}')
            signs(normal(-277, fraction), normal(-k-693, fraction), f'gradual-shift-both-tops-k-{k}')
    # Exponent sums surrounding normal/gradual and half-minsubnormal transitions.
    for total in (-1162, -1077, -1076, -1075, -1074, -1073, -1024, -1023, -1022, -1021, -1, 0):
        aexp = max(-277, total)
        bexp = total-aexp
        for af in patterns:
            for bf in patterns:
                signs(normal(aexp, af), normal(bexp, bf), f'exponent-sum-{total}')
    # Each significand bit and bit hole, including sticky contributions across
    # two-word boundaries and both retained-product leading-bit branches.
    for bit in range(52):
        for fraction in (1<<bit, FRACTION^(1<<bit)):
            for k in (53, 54, 66, 67, 68, 98, 99, 100, 104, 105, 106, 107, 192):
                signs(normal(-277, fraction), normal(-k-693, FRACTION), f'significand-bit-{bit}')
    # Reachable exact ties with even/odd lower neighbor and adjacent input words.
    for total in (-1075, -1074, -1073, -1055, -1043, -1023, -1022, -277, 0):
        for af, bf in ((0, 0), (0, 1<<51), (1<<51, 1), (1<<51, 3), (0, FRACTION)):
            ae=max(-277,total); b=normal(total-ae,bf)
            for delta in (-1,0,1):
                if in_domain(b+delta,*BOUNDS[1]): signs(normal(ae,af),b+delta,'tie-parities-and-adjacent-inputs')
    for index in range(4096):
        signs_a=normal(rng.randint(*BOUNDS[0]),rng.getrandbits(52),rng.getrandbits(1))
        signs_b=normal(rng.randint(*BOUNDS[1]),rng.getrandbits(52),rng.getrandbits(1))
        add(signs_a,signs_b,'seeded-bit-stratified-random')
    for operand,(minimum,maximum) in enumerate(BOUNDS):
        invalid=[normal(e,f,s) for e in (-1022,minimum-1,maximum+1,1023)
                 for f in (0,1,FRACTION) for s in (0,1)]
        invalid += [(s<<63)|f for f in (1,1<<31,1<<32,1<<51,FRACTION) for s in (0,1)]
        invalid += [(s<<63)|(2047<<52)|f for f in (0,1,1<<32,1<<51,FRACTION) for s in (0,1)]
        for bad in invalid:
            for other in (0,SIGN,normal(0),normal(0,FRACTION,1)):
                pair=[other,other]; pair[operand]=bad
                add(*pair,f'reject-invalid-operand-{operand}')
    for index,row in enumerate(rows): row['id']=index
    validate_rows(rows)
    return rows


def validate_row(row):
    required = {'id', 'kind', *FIELDS}
    if type(row) is not dict or not required <= set(row) or set(row) - required - {'labels'}:
        raise ValueError('Malformed input record shape')
    word(row['id'], 32)
    if type(row['kind']) is not str or row['kind'] not in KINDS:
        raise ValueError('Unknown observation kind')
    for field in FIELDS:
        word(row[field], 32)
    if 'labels' in row and (type(row['labels']) is not list or
            any(type(label) is not str or not label for label in row['labels']) or
            len(set(row['labels'])) != len(row['labels'])):
        raise ValueError('Malformed input labels')


def validate_rows(rows):
    if type(rows) is not list:
        raise ValueError('Expected input record list')
    ids = set()
    for row in rows:
        validate_row(row)
        if row['id'] in ids:
            raise ValueError('Duplicate input observation ID')
        ids.add(row['id'])


def expected_row(row):
    validate_row(row)
    result = checked(row['kind'], *(row[field] for field in FIELDS))
    prefix = [row['id'], KINDS[row['kind']]]
    return [*prefix, 0, 0, 0] if result is None else [*prefix, 1, *result]


def strict_json(text):
    if type(text) is not str:
        raise ValueError('Expected JSON text')
    def pairs(items):
        value = {}
        for key, item in items:
            if key in value:
                raise ValueError('Duplicate JSON key')
            value[key] = item
        return value
    def constant(value):
        raise ValueError('Nonfinite JSON constant')
    return json.loads(text, object_pairs_hook=pairs, parse_constant=constant)


def parse_output(text, selected):
    validate_rows(selected)
    if type(text) is not str:
        raise ValueError('Expected output text')
    lines = text.splitlines()
    groups = [selected[start:start+LINE] for start in range(0, len(selected), LINE)]
    if len(lines) != len(groups):
        raise ValueError('Wrong output line count/framing')
    actual = []
    for line, group in zip(lines, groups):
        values = strict_json(line)
        if type(values) is not list or len(values) != WIDTH * len(group):
            raise ValueError('Wrong output shape/count')
        for value in values:
            word(value, 32)
        for offset, row in enumerate(group):
            result = values[WIDTH*offset:WIDTH*(offset+1)]
            if result[0] != row['id'] or result[1] != KINDS[row['kind']] or result[2] not in (0, 1):
                raise ValueError('Wrong output ID, operation kind or tag')
            if result[2] == 0 and result[3:] != [0, 0]:
                raise ValueError('Noncanonical rejected payload')
            actual.append(result)
    return actual


def validate_observations(rows):
    if type(rows) is not list:
        raise ValueError('Expected observation list')
    ids = set()
    for row in rows:
        if type(row) is not list or len(row) != WIDTH:
            raise ValueError('Wrong observation shape')
        for value in row:
            word(value, 32)
        if row[0] in ids or row[1] not in KINDS.values() or row[2] not in (0, 1):
            raise ValueError('Wrong observation ID, operation kind or tag')
        if row[2] == 0 and row[3:] != [0, 0]:
            raise ValueError('Noncanonical rejected payload')
        ids.add(row[0])


def compare(expected, actual):
    validate_observations(expected)
    validate_observations(actual)
    if len(expected) != len(actual):
        raise ValueError('Incomplete comparison')
    differences = [dict(id=a[0], expected=a, actual=b) for a, b in zip(expected, actual) if a != b]
    if differences:
        raise ValueError(f'Exact mismatch: {differences[:8]} (total {len(differences)})')


def program(selected):
    validate_rows(selected)
    if not 1 <= len(selected) <= CHUNK:
        raise ValueError('Candidate program must contain 1..256 operations')
    source = '''import Base
import ../../src/binary64_fma.bend as F
import ../../src/binary64_gradual_multiply.bend as G
type Task is Data:
  Multiply{index: U32, ah: U32, al: U32, bh: U32, bl: U32}
def observe(index: U32, kind: U32, value: Maybe<F.Words>, rest: List<U32>) -> List<U32>:
  match value:
    case None{}: Con{index, Con{kind, Con{0, Con{0, Con{0, rest}}}}}
    case Some{pair}:
      F.Words{high, low} = pair
      Con{index, Con{kind, Con{1, Con{high, Con{low, rest}}}}}
def one(task: Task, rest: List<U32>) -> List<U32>:
  match task:
    case Multiply{index, ah, al, bh, bl}: observe(index, 0, G.checked(ah, al, bh, bl), rest)
def calculate(values: +List<Task>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{task, rest}: one(task, calculate(rest))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for start in range(0, len(selected), LINE):
        values = [row['kind'].title() + '{' + ','.join(str(value) for value in (row['id'], *(row[f] for f in FIELDS))) + '}'
                  for row in selected[start:start+LINE]]
        source += '    IO.print(List.show(~&1, ~U32, ~U32.show, calculate([' + ','.join(values) + '])))\n'
    return source

# These runtime controls deliberately include subnormal inputs and outputs,
# outside the candidate's domain, to detect FTZ/DAZ or nonbinary64 evaluation.
NATIVE_CONTROLS = (
    (0x2ea0000000000000, 0x0e0fffffffffffff, 0x0000000000000000),  # half_min_subnormal_below
    (0xaea0000000000000, 0x0e0fffffffffffff, 0x8000000000000000),  # negative_half_min_subnormal_below
    (0x2ea0000000000000, 0x0e10000000000000, 0x0000000000000000),  # half_min_subnormal_tie
    (0xaea0000000000000, 0x0e10000000000000, 0x8000000000000000),  # negative_half_min_subnormal_tie
    (0x2ea0000000000000, 0x0e10000000000001, 0x0000000000000001),  # half_min_subnormal_above
    (0xaea0000000000000, 0x0e10000000000001, 0x8000000000000001),  # negative_half_min_subnormal_above
    (0x2ea0000000000000, 0x0e27ffffffffffff, 0x0000000000000001),  # subnormal_tie_odd_lower_neighbor_-1
    (0x2ea0000000000000, 0x0e28000000000000, 0x0000000000000002),  # subnormal_tie_odd_lower_neighbor_+0
    (0x2ea0000000000000, 0x0e28000000000001, 0x0000000000000002),  # subnormal_tie_odd_lower_neighbor_+1
    (0x2ea0000000000000, 0x0e33ffffffffffff, 0x0000000000000002),  # subnormal_tie_even_lower_neighbor_-1
    (0x2ea0000000000000, 0x0e34000000000000, 0x0000000000000002),  # subnormal_tie_even_lower_neighbor_+0
    (0x2ea0000000000000, 0x0e34000000000001, 0x0000000000000003),  # subnormal_tie_even_lower_neighbor_+1
    (0x2ea0000000000000, 0x115ffffffffffffe, 0x000fffffffffffff),  # maximum_subnormal_exact
    (0x2ea0000000000000, 0x115fffffffffffff, 0x0010000000000000),  # minimum_normal_half_tie
    (0x2ea0000000000000, 0x1160000000000000, 0x0010000000000000),  # minimum_normal_exact
    (0x2eafffffffffffff, 0x114fffffffffffff, 0x000fffffffffffff),  # sum_minus1024_maximum_product
    (0x2ea8000000000000, 0x1158000000000000, 0x0012000000000000),  # sum_minus1023_already_normal
    (0x2eafffffffffffff, 0x115fffffffffffff, 0x001ffffffffffffe),  # sum_minus1023_maximum_product
    (0x2ea0000000000000, 0x1160000000000000, 0x0010000000000000),  # sum_minus1022_minimum_product
    (0x2ea0000000000000, 0x0e00000000000000, 0x0000000000000000),  # k106_below_half
    (0x2eafffffffffffff, 0x0e0fffffffffffff, 0x0000000000000001),  # k106_above_half
    (0x2eafffffffffffff, 0x0dffffffffffffff, 0x0000000000000000),  # k107_largest_product_zero
    (0x2ea0000000000000, 0x08a0000000000000, 0x0000000000000000),  # k192_smallest_product_zero
    (0x2eafffffffffffff, 0x88afffffffffffff, 0x8000000000000000),  # k192_largest_negative_product_zero
    (0x2ea0000000000001, 0x1150000000000004, 0x0008000000000003),  # double_round_above_even_subnormal_tie
    (0xaea0000000000001, 0x1150000000000004, 0x8008000000000003),  # double_round_above_even_subnormal_tie_negative
    (0x2ea0000000000001, 0x115ffffffffffffd, 0x000fffffffffffff),  # double_round_below_minimum_normal_tie
    (0xaea0000000000001, 0x115ffffffffffffd, 0x800fffffffffffff),  # double_round_below_minimum_normal_tie_negative
    (0x2ea0000000000001, 0x0e0fffffffffffff, 0x0000000000000001),  # double_round_above_half_minimum_subnormal
    (0xaea0000000000001, 0x0e0fffffffffffff, 0x8000000000000001),  # double_round_above_half_minimum_subnormal_negative
    (0x0000000000000000, 0x0000000000000000, 0x0000000000000000),  # zero_pair_00
    (0x0000000000000000, 0x08a0000000000000, 0x0000000000000000),  # zero_first_00
    (0x2ea0000000000000, 0x0000000000000000, 0x0000000000000000),  # zero_second_00
    (0x0000000000000000, 0x8000000000000000, 0x8000000000000000),  # zero_pair_01
    (0x0000000000000000, 0x88a0000000000000, 0x8000000000000000),  # zero_first_01
    (0x2ea0000000000000, 0x8000000000000000, 0x8000000000000000),  # zero_second_01
    (0x8000000000000000, 0x0000000000000000, 0x8000000000000000),  # zero_pair_10
    (0x8000000000000000, 0x08a0000000000000, 0x8000000000000000),  # zero_first_10
    (0xaea0000000000000, 0x0000000000000000, 0x8000000000000000),  # zero_second_10
    (0x8000000000000000, 0x8000000000000000, 0x0000000000000000),  # zero_pair_11
    (0x8000000000000000, 0x88a0000000000000, 0x0000000000000000),  # zero_first_11
    (0xaea0000000000000, 0x8000000000000000, 0x0000000000000000),  # zero_second_11
    (0x2ff0000000000000, 0x8fd5555555555555, 0x8001555555555555),  # reachable_tiny_z_exp_-256
    (0x2f30000000000000, 0x8d95555555555555, 0x8000000000000001),  # reachable_tiny_z_exp_-268
    (0x2f20000000000000, 0x8d65555555555555, 0x8000000000000000),  # reachable_tiny_z_exp_-269
    (0x2eb0000000000000, 0x8c15555555555555, 0x8000000000000000),  # reachable_tiny_z_exp_-276
    (0x3ff8000000000000, 0x3ff5555555555555, 0x4000000000000000),  # normal_rounding_carry
    (0x3ff8000000000000, 0x3ff0000000000001, 0x3ff8000000000002),  # normal_odd_lower_tie
    (0x3ff8000000000000, 0x3ff0000000000003, 0x3ff8000000000004),  # normal_even_lower_tie
    (0x3fffffffffffffff, 0x3fffffffffffffff, 0x400ffffffffffffe),  # maximum_contract_product
    (0x2ea0000000000000, 0x3ff0000000000000, 0x2ea0000000000000),  # lowest_first_exponent_normal_second
    (0x3ff0000000000000, 0x08a0000000000000, 0x08a0000000000000),  # lowest_second_exponent_normal_first
    (0x0000000000000001, 0x4330000000000000, 0x0010000000000000),  # native_daz_min_subnormal_to_normal
    (0x8000000000000001, 0x4330000000000000, 0x8010000000000000),  # native_daz_negative_min_subnormal_to_normal
    (0x0010000000000000, 0x3fe0000000000000, 0x0008000000000000),  # native_ftz_normal_times_half
    (0x0000000000000001, 0x3ff0000000000000, 0x0000000000000001),  # native_min_subnormal_times_one
    (0x000fffffffffffff, 0x4000000000000000, 0x001ffffffffffffe),  # native_max_subnormal_to_normal
    (0x0000000000000001, 0x3fe0000000000000, 0x0000000000000000),  # native_half_min_subnormal_tie
    (0x8000000000000001, 0x3fe0000000000000, 0x8000000000000000),  # native_negative_half_min_subnormal_tie
    (0x0000000000000003, 0x3fe0000000000000, 0x0000000000000002),  # native_odd_lower_subnormal_tie
    (0x0000000000000005, 0x3fe0000000000000, 0x0000000000000002),  # native_even_lower_subnormal_tie
    (0x0010000000000000, 0x3fefffffffffffff, 0x0010000000000000),  # native_min_normal_boundary_tie
    (0x0010000000000000, 0x3feffffffffffffe, 0x000fffffffffffff),  # native_max_subnormal_exact
)
PREFLIGHT_COUNT = len(NATIVE_CONTROLS)
NATIVE = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <float.h>
#include <limits.h>
#include <fenv.h>
#include <inttypes.h>
#if defined(__x86_64__) || defined(__i386__)
#include <xmmintrin.h>
#elif !defined(__aarch64__)
#error Unsupported floating point control-register qualification
#endif
#ifdef __FAST_MATH__
#error Fast math invalidates this oracle
#endif
#pragma STDC FENV_ACCESS ON
#pragma STDC FP_CONTRACT OFF
_Static_assert(CHAR_BIT == 8 && sizeof(double) == 8, "word layout");
_Static_assert(FLT_RADIX == 2 && DBL_MANT_DIG == 53 && DBL_MIN_EXP == -1021 && DBL_MAX_EXP == 1024, "binary64");
_Static_assert(DBL_HAS_SUBNORM == 1, "gradual underflow supported");
_Static_assert(FLT_EVAL_METHOD == 0, "binary64 evaluation without excess precision");
static double mul_values(double a, double b) {
  volatile double va=a, vb=b; volatile double result=va*vb; return result;
}
static double (* volatile runtime_mul)(double, double) = mul_values;
static uint64_t evaluate(uint64_t a, uint64_t b) {
  double da,db; memcpy(&da,&a,8); memcpy(&db,&b,8);
  volatile double computed=runtime_mul(da,db);
  double result=computed; uint64_t bits; memcpy(&bits,&result,8); return bits;
}
static uint64_t get_control(void) {
#if defined(__x86_64__) || defined(__i386__)
  return _mm_getcsr();
#else
  uint64_t control; __asm__ volatile("mrs %0, fpcr" : "=r"(control)); return control;
#endif
}
static int allowed(uint64_t value, int minimum) {
  unsigned exponent=(unsigned)((value>>52)&2047);
  if (!exponent) return (value & UINT64_C(0x7fffffffffffffff)) == 0;
  return (int)exponent-1023 >= minimum && exponent <= 1023;
}
int main(int argc, char **argv) {
  int initial=fegetround();
  if (argc != 2 || initial < 0 || fesetround(FE_TONEAREST) || fegetround() != FE_TONEAREST) return 2;
  uint64_t control=get_control(), forbidden; const char *control_name;
#if defined(__x86_64__) || defined(__i386__)
  control_name="mxcsr"; forbidden=(1u<<15) | (1u<<6) | (3u<<13);
#else
  control_name="fpcr"; forbidden=(1ull<<24) | (1ull<<19) | (3ull<<22) | 3ull;
#endif
  if (control & forbidden) return 3;
  double one=1.0; uint64_t one_bits; memcpy(&one_bits,&one,8);
  if (one_bits != UINT64_C(0x3ff0000000000000)) return 4;
  static const uint64_t controls[][3] = {
@CONTROLS@
  };
  unsigned preflights=(unsigned)(sizeof controls/sizeof controls[0]);
  for (unsigned i=0;i<preflights;i++) {
    if (evaluate(controls[i][0],controls[i][1]) != controls[i][2]) {
      fprintf(stderr,"Runtime multiply preflight %u failed\n",i); return 7;
    }
  }
  uint64_t after=get_control();
  if (fegetround()!=FE_TONEAREST || (after & forbidden)) return 9;
  printf("{\"rounding\":\"FE_TONEAREST\",\"initial_rounding\":%d,\"selected_rounding\":%d,\"control_name\":\"%s\",\"control\":%" PRIu64 ",\"control_after\":%" PRIu64 ",\"ftz\":false,\"daz\":false,\"runtime_mul\":true,\"binary64_evaluation\":true,\"preflight_count\":%u}\n",initial,fegetround(),control_name,control,after,preflights);
  FILE *in=fopen(argv[1],"r"); if (!in) return 5;
  uint32_t index,kind,ah,al,bh,bl; int count;
  while ((count=fscanf(in,"%" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32,&index,&kind,&ah,&al,&bh,&bl)) == 6) {
    if (kind != 0) { fclose(in); return 8; }
    uint64_t a=((uint64_t)ah<<32)|al,b=((uint64_t)bh<<32)|bl;
    if (!allowed(a,-277) || !allowed(b,-885)) {
      printf("[%" PRIu32 ",%" PRIu32 ",0,0,0]\n",index,kind); continue;
    }
    uint64_t bits=evaluate(a,b);
    printf("[%" PRIu32 ",%" PRIu32 ",1,%" PRIu32 ",%" PRIu32 "]\n",index,kind,(uint32_t)(bits>>32),(uint32_t)bits);
  }
  if (count != EOF || ferror(in) || fclose(in)) return 6;
  if (fegetround()!=FE_TONEAREST || (get_control() & forbidden)) return 9;
  return 0;
}
'''.replace('@CONTROLS@', ',\n'.join('    {' + ','.join(f'UINT64_C(0x{value:016x})' for value in row) + '}'
                                        for row in NATIVE_CONTROLS))


def parse_native(text, rows):
    validate_rows(rows)
    if type(text) is not str:
        raise ValueError('Expected native output text')
    lines = text.splitlines()
    if len(lines) != len(rows) + 1:
        raise ValueError('Wrong native line count')
    metadata = strict_json(lines[0])
    keys = {'rounding', 'initial_rounding', 'selected_rounding', 'control_name',
            'control', 'control_after', 'ftz', 'daz', 'runtime_mul', 'binary64_evaluation', 'preflight_count'}
    if type(metadata) is not dict or set(metadata) != keys:
        raise ValueError('Malformed native environment metadata')
    if (metadata['rounding'] != 'FE_TONEAREST' or metadata['ftz'] is not False or
            metadata['daz'] is not False or metadata['runtime_mul'] is not True or metadata['binary64_evaluation'] is not True or
            metadata['control_name'] not in ('mxcsr', 'fpcr')):
        raise ValueError('Unsupported native rounding/denormal/runtime environment')
    for key in ('initial_rounding', 'selected_rounding', 'control', 'control_after', 'preflight_count'):
        if type(metadata[key]) is not int or metadata[key] < 0:
            raise ValueError('Invalid native control metadata')
    for field in ('control', 'control_after'):
        word(metadata[field], 32 if metadata['control_name'] == 'mxcsr' else 64)
    for key in ('initial_rounding', 'selected_rounding', 'preflight_count'):
        word(metadata[key], 32)
    if metadata['selected_rounding'] != 0 or metadata['preflight_count'] != PREFLIGHT_COUNT:
        raise ValueError('Unsupported native rounding or incomplete preflight')
    mask = ((1 << 15) | (1 << 6) | (3 << 13) if metadata['control_name'] == 'mxcsr'
            else (1 << 24) | (1 << 19) | (3 << 22) | 3)
    if (metadata['control'] | metadata['control_after']) & mask:
        raise ValueError('Native rounding/denormal mode does not match metadata')
    groups = []
    for start in range(0, len(rows), LINE):
        combined = []
        for line in lines[1+start:1+min(start+LINE, len(rows))]:
            values = strict_json(line)
            if type(values) is not list or len(values) != WIDTH:
                raise ValueError('Malformed native record')
            combined.extend(values)
        groups.append(json.dumps(combined))
    return metadata, parse_output('\n'.join(groups), rows)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def execute(command, work, name, timeout=600, env=None):
    command = [str(part) for part in command]
    for suffix in ('stdout', 'stderr'):
        (work/(name+'.'+suffix)).unlink(missing_ok=True)
    try:
        process = subprocess.run(command, cwd=ROOT, env=dict(os.environ, BEND_NO_TELEMETRY='1', **(env or {})),
                                 text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        for suffix, data in (('stdout', error.stdout), ('stderr', error.stderr)):
            (work/(name+'.'+suffix)).write_text(data.decode() if isinstance(data, bytes) else data or '')
        raise
    (work/(name+'.stdout')).write_text(process.stdout)
    (work/(name+'.stderr')).write_text(process.stderr)
    if process.returncode:
        raise ValueError(f'{name} exited {process.returncode}; retained stdout/stderr')
    return process.stdout


def compile_fresh(command, outputs, work, name, env=None):
    for path in outputs:
        path.unlink(missing_ok=True)
    execute(command, work, name, env=env)
    if any(not path.is_file() or path.stat().st_size == 0 for path in outputs):
        raise ValueError('Compiler succeeded without all fresh nonempty outputs')


def compiler_identity(command, work, name):
    resolved = shutil.which(str(command))
    if resolved is None:
        raise ValueError(f'Missing compiler/runtime: {command}')
    path = Path(resolved).resolve()
    return dict(path=str(path), sha256=digest(path), version=execute([command, '--version'], work, name).strip())


def candidate_environment(compiler):
    # Match the pinned Bend CLI's supported CPU compiler predicate.  An unsupported
    # CC would silently fall back to another clang, invalidating compiler evidence.
    match = re.search(r'^(Apple )?(?:\w+ )?clang version (\d+)', compiler['version'], re.M)
    if match is None or int(match[2]) < 14:
        raise ValueError('Recorded compiler is not a supported Bend CPU clang')
    return {'CC': compiler['path']}


def assert_unchanged(before):
    after = {path: digest(ROOT/path) for path in before}
    if after != before:
        raise ValueError('Source/harness/toolchain drift during probe')


def final_source_gate(hashes, bend_source, lock, compilers=None, work=None):
    assert_unchanged(hashes)
    checkout(bend_source, lock['bend']['revision'], lock['bend'].get('patch'))
    for name, (command, expected) in (compilers or {}).items():
        if compiler_identity(command, work, name+'-final-version') != expected:
            raise ValueError('Compiler/runtime executable drift during probe')


def retain_artifacts(report, work, names):
    """Pin evidence as it is consumed; do not bless later artifact changes."""
    retained = report.setdefault('artifacts', {})
    for name in names:
        current = digest(work/name)
        if name in retained and retained[name] != current:
            raise ValueError('Input/program/output artifact drift during probe: ' + name)
        retained[name] = current


def assert_artifacts_unchanged(report, work):
    for name, expected in report.get('artifacts', {}).items():
        if digest(work/name) != expected:
            raise ValueError('Input/program/output artifact drift during probe: ' + name)


def native_reference(rows, expected, work, clang):
    validate_rows(rows)
    source = work/'reference.c'; source.write_text(NATIVE)
    inputs = work/'native-input.txt'
    inputs.write_text(''.join(' '.join(str(v) for v in (r['id'], KINDS[r['kind']], *(r[f] for f in FIELDS)))+'\n' for r in rows))
    compiler = compiler_identity(clang, work, 'compiler-version')
    compile_fresh([clang, *FLAGS, source, '-lm', '-o', work/'reference'], [work/'reference'], work, 'native-compile')
    evidence = {'artifacts': {}}
    retain_artifacts(evidence, work, ['reference.c', 'reference', 'native-input.txt'])
    output = execute([work/'reference', inputs], work, 'native-run')
    environment, actual = parse_native(output, rows)
    compare(expected, actual)
    assert_artifacts_unchanged(evidence, work)
    retain_artifacts(evidence, work, ['native-run.stdout', 'native-run.stderr'])
    return dict(passed=True, observations=len(actual), compiler=compiler, flags=FLAGS, environment=environment,
                artifacts=evidence['artifacts'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, required=True)
    parser.add_argument('--clang', default='clang')
    parser.add_argument('--native-only', action='store_true', help='qualify oracle/native only; never reports candidate pass')
    args = parser.parse_args()
    work = BUILD/'binary64-gradual-multiply-probe'; work.mkdir(parents=True, exist_ok=True)
    report_path = work/'results.json'
    report = dict(schema=1, passed=False, lanes={}, phase='initializing')
    write_json(report_path, report)
    start = time.monotonic()
    try:
        lock = json.loads((ROOT/'toolchain.json').read_text())
        checkout(args.bend_source, lock['bend']['revision'], lock['bend'].get('patch'))
        hashes = source_gate()
        dependencies = (*DEPENDENCIES, lock['bend']['patch']['path']) if lock['bend'].get('patch') else DEPENDENCIES
        for path in dependencies:
            hashes[path] = digest(ROOT/path)
        bun = compiler_identity('bun', work, 'bun-version')
        if bun['version'] != lock['bun']['version']:
            raise ValueError('Bun version does not match pinned toolchain')
        rows = samples()
        expected = [expected_row(row) for row in rows]
        write_json(work/'inputs.json', rows)
        write_json(work/'expected.json', expected)
        report.update(phase='native-qualification', observations=len(rows),
                      accepted=sum(row[2] for row in expected), rejected=sum(row[2] == 0 for row in expected),
                      coverage=dict(Counter(label for row in rows for label in row['labels'])),
                      seed=SEED, bun=bun, chunk_limit=CHUNK, output_line_limit=LINE,
                      sources=hashes, inputs_sha256=digest(work/'inputs.json'), oracle_sha256=digest(work/'expected.json'),
                      scope='private RN-even multiply; a zero/normal [-277,0], b zero/normal [-885,0]; gradual output',
                      gpu='not run; no device claim', host=dict(platform=platform.platform(), machine=platform.machine(),
                      libc=platform.libc_ver(), python=platform.python_version()), chunks=[], artifacts={})
        retain_artifacts(report, work, ['inputs.json', 'expected.json'])
        write_json(report_path, report)
        report['native'] = native_reference(rows, expected, work, args.clang)
        for name, value in report['native']['artifacts'].items():
            report['artifacts'][name] = value
        assert_artifacts_unchanged(report, work)
        candidate_env = candidate_environment(report['native']['compiler'])
        report['candidate_compiler'] = dict(compiler=report['native']['compiler'], environment=candidate_env,
                                            flags_source='pinned bend2/main.ts cli_build CPU flags')
        write_json(work/'native-metadata.json', report['native'])
        report['native_metadata_sha256'] = digest(work/'native-metadata.json')
        compilers = {'compiler': (args.clang, report['native']['compiler']), 'bun': ('bun', bun)}
        names = ['inputs.json', 'expected.json', 'native-input.txt', 'reference.c', 'reference', 'native-metadata.json']
        names += [f'{prefix}.{suffix}' for prefix in ('compiler-version', 'bun-version', 'native-compile', 'native-run') for suffix in ('stdout', 'stderr')]
        retain_artifacts(report, work, names)
        print(f'Exact rational/volatile-runtime oracle agreement: {len(rows)} checked inputs', flush=True)
        if args.native_only:
            final_source_gate(hashes, args.bend_source, lock, compilers, work)
            names += [f'{prefix}-final-version.{suffix}' for prefix in ('compiler', 'bun') for suffix in ('stdout', 'stderr')]
            assert_artifacts_unchanged(report, work)
            retain_artifacts(report, work, names)
            report.update(phase='native-only-complete',
                          elapsed_seconds=round(time.monotonic()-start, 3))
            write_json(report_path, report)
            print('Native qualification complete; candidate lanes not run and overall passed remains false', flush=True)
            return
        report['phase'] = 'candidate'
        write_json(report_path, report)
        cli = ['bun', args.bend_source/'bend2/main.ts']
        proof = execute([*cli, ROOT/'PROOF.bend', '--check-only'], work, 'proof')
        if proof.strip() != 'All terms check.':
            raise ValueError('Incomplete proof verdict')
        report['proof'] = proof.strip()
        retain_artifacts(report, work, ['proof.stdout', 'proof.stderr'])
        totals = Counter()
        for batch, offset in enumerate(range(0, len(rows), CHUNK)):
            selected = rows[offset:offset+CHUNK]
            source = work/f'candidate-{batch:03}.bend'; source.write_text(program(selected))
            retain_artifacts(report, work, [source.name])
            binary, js = work/f'candidate-{batch:03}', work/f'candidate-{batch:03}.js'
            compile_fresh([*cli, source, '-o', binary, '-o', js], [binary, js], work, f'compile-{batch:03}', env=candidate_env)
            retain_artifacts(report, work, [binary.name, js.name, f'compile-{batch:03}.stdout', f'compile-{batch:03}.stderr'])
            for lane, command in (('cpu-1', [binary, '--gpu', 'off', '--threads', '1']),
                                  ('cpu-2', [binary, '--gpu', 'off', '--threads', '2']), ('javascript', ['bun', js])):
                actual = parse_output(execute(command, work, f'{lane}-{batch:03}'), selected)
                compare(expected[offset:offset+len(selected)], actual)
                retain_artifacts(report, work, [f'{lane}-{batch:03}.stdout', f'{lane}-{batch:03}.stderr'])
                totals[lane] += len(actual)
                report['lanes'][lane] = dict(passed=False, checked=totals[lane])
            report['chunks'].append(dict(index=batch, offset=offset, count=len(selected), passed=True))
            write_json(report_path, report)
            print(f'chunk {batch+1}: {len(selected)} observations match CPU-1/CPU-2/JS', flush=True)
        if set(totals) != {'cpu-1', 'cpu-2', 'javascript'} or any(value != len(rows) for value in totals.values()):
            raise ValueError('Incomplete lane coverage')
        final_source_gate(hashes, args.bend_source, lock, compilers, work)
        names += ['proof.stdout', 'proof.stderr']
        names += [f'{prefix}-final-version.{suffix}' for prefix in ('compiler', 'bun') for suffix in ('stdout', 'stderr')]
        for batch in range(len(report['chunks'])):
            names += [f'candidate-{batch:03}{suffix}' for suffix in ('.bend', '', '.js')]
            names += [f'{prefix}-{batch:03}.{suffix}' for prefix in ('compile', 'cpu-1', 'cpu-2', 'javascript') for suffix in ('stdout', 'stderr')]
        assert_artifacts_unchanged(report, work)
        retain_artifacts(report, work, names)
        report.update(passed=True, phase='complete',
                      elapsed_seconds=round(time.monotonic()-start, 3))
        for lane in report['lanes'].values():
            lane['passed'] = True
        write_json(report_path, report)
        print(f'PASS: {len(rows)} complete exact observations on each of three lanes', flush=True)
    except Exception as error:
        report.update(passed=False, error=str(error), elapsed_seconds=round(time.monotonic()-start, 3))
        write_json(report_path, report)
        raise


if __name__ == '__main__':
    main()
