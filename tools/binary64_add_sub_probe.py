#!/usr/bin/env python3
"""Private bounded binary64 add/sub: rational/native and CPU-1/2/JS gates.

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

from binary64_add_sub_oracle import (BOUNDS, FRACTION, KINDS, SIGN, checked,
                                    decode64, in_domain, nearest64, power2, word)
from conformance import BUILD, ROOT, checkout, source_gate

CHUNK = 256
LINE = 16
WIDTH = 5
SEED = 0x64ADD5AB
FIELDS = ('ah', 'al', 'bh', 'bl')
FLAGS = ['-std=c11', '-O2', '-frounding-math', '-fno-fast-math',
         '-ffp-contract=off', '-fno-lto']
DEPENDENCIES = ('src/binary64_add_sub.bend', 'src/binary64_fma.bend',
                'tools/binary64_add_sub_probe.py', 'tools/binary64_add_sub_oracle.py',
                'tools/binary64_fma_oracle.py', 'tests/test_binary64_add_sub.py',
                'tools/conformance.py', 'LAWS.bend', 'PROOF.bend', 'toolchain.json')


def normal(exponent, fraction=0, sign=0):
    if (type(exponent) is not int or type(fraction) is not int or type(sign) is not int
            or not -1022 <= exponent <= 1023 or not 0 <= fraction <= FRACTION or sign not in (0, 1)):
        raise ValueError('Invalid normal binary64 parameters')
    return (sign << 63) | ((exponent + 1023) << 52) | fraction


# Fixed IEEE encodings make these controls independent of both rounding paths.
HAND = (
    ('add', 0x3ff0000000000000, 0x3ca0000000000000, 0x3ff0000000000000, 'hand-even-tie'),
    ('add', 0x3ff0000000000001, 0x3ca0000000000000, 0x3ff0000000000002, 'hand-odd-tie'),
    ('add', 0x3ff0000000000000, 0x3c9fffffffffffff, 0x3ff0000000000000, 'hand-below-tie'),
    ('add', 0x3ff0000000000000, 0x3ca0000000000001, 0x3ff0000000000001, 'hand-above-tie'),
    ('add', 0x3fffffffffffffff, 0x3ca0000000000000, 0x4000000000000000, 'hand-binade-carry'),
    ('sub', 0x3ff0000000000000, 0x3c90000000000000, 0x3ff0000000000000, 'hand-sub-lower-binade-tie'),
    ('sub', 0x07b0000000000001, 0x07b0000000000000, 0x0470000000000000, 'minimum-positive-lattice-result'),
    ('sub', 0x07b0000000000000, 0x07b0000000000001, 0x8470000000000000, 'minimum-negative-lattice-result'),
    ('add', 0x481fffffffffffff, 0x481fffffffffffff, 0x482fffffffffffff, 'maximum-positive-sum'),
    ('add', 0xc81fffffffffffff, 0xc81fffffffffffff, 0xc82fffffffffffff, 'maximum-negative-sum'),
    ('sub', 0x4810000000000001, 0x4810000000000000, 0x44d0000000000000, 'hand-deep-cancellation'),
    ('sub', 0x4810000000000000, 0x07bfffffffffffff, 0x4810000000000000, 'hand-long-borrow'),
)


def samples():
    """Deterministic operation/input deduplication, preserving all coverage labels."""
    rows, seen = [], {}
    def add(kind, a, b, label):
        if kind not in KINDS:
            raise ValueError('Unknown corpus operation')
        key = (kind, word(a, 64), word(b, 64))
        if key not in seen:
            row = dict(kind=kind, labels=[])
            row.update(zip(FIELDS, [part for value in (a, b) for part in (value >> 32, value & 0xffffffff)]))
            rows.append(row)
            seen[key] = row
        if label not in seen[key]['labels']:
            seen[key]['labels'].append(label)
    def orders(a, b, label):
        for kind in KINDS:
            add(kind, a, b, label)
            add(kind, b, a, label)
    def signs(a, b, label):
        for sa in (0, SIGN):
            for sb in (0, SIGN):
                orders(a ^ sa, b ^ sb, label)
    for kind, a, b, expected, label in HAND:
        result = checked(kind, a >> 32, a & 0xffffffff, b >> 32, b & 0xffffffff)
        if result != (expected >> 32, expected & 0xffffffff):
            raise ValueError('Rational oracle disagrees with fixed hand vector')
        add(kind, a, b, label)
    signs(0, 0, 'all-zero-sign-combinations')
    for exponent in (-900, -899, -1, 0, 1, 129, 130):
        for fraction in (0, 1, FRACTION):
            signs(0, normal(exponent, fraction), 'zero-and-nonzero-all-signs-orders')
    rng = random.Random(SEED)
    for exponent in range(-900, 131):
        for sign in (0, 1):
            fraction = (0, 1, FRACTION, rng.getrandbits(52))[exponent % 4]
            primary = normal(exponent, fraction, sign)
            other = normal(rng.randint(-900, 130), rng.getrandbits(52), rng.getrandbits(1))
            for kind in KINDS:
                add(kind, primary, other, 'every-exponent-operand-0')
                add(kind, other, primary, 'every-exponent-operand-1')
    # Midpoints and both exact neighbors at every retained-bit parity, with
    # selected binades including the smallest permitted midpoint addend.
    tie_exponents = sorted({-847, -846, -1, 0, 1, 129, 130, *range(-832, 131, 32)})
    for exponent in tie_exponents:
        for fraction in (0, 1, 2, 3, FRACTION - 1, FRACTION):
            for delta in (-1, 0, 1):
                small = normal(exponent - 53) + delta
                label = ('reject-tie-neighbor-below-domain' if exponent == -847 and delta == -1
                         else 'ties-even-odd-carry-and-adjacent')
                signs(normal(exponent, fraction), small, label)
                if fraction == FRACTION and delta >= 0:
                    signs(normal(exponent, fraction), small, 'retained-53-bit-rounding-carry')
        if exponent >= -846:
            for delta in (-1, 0, 1):
                signs(normal(exponent), normal(exponent - 54) + delta,
                      'subtraction-lower-binade-midpoint-neighbors')
    # Cancellation and each significant-bit carry/borrow boundary, including
    # adjacent values in the minimum input binade. This is a finite, declared
    # stratification, not an exhaustive claim over its 2^52 significands.
    boundaries = {0, 1, 2, 3, FRACTION - 2, FRACTION - 1}
    for bit in range(1, 53):
        boundaries.update(((1 << bit) - 2, (1 << bit) - 1))
    for fraction in sorted(boundaries):
        if fraction < FRACTION:
            signs(normal(-900, fraction), normal(-900, fraction + 1),
                  'lattice-floor-adjacent-bit-and-carry-boundaries')
    cancellation_exponents = sorted({-900, -899, -1, 0, 1, 129, 130, *range(-896, 131, 16)})
    for exponent in cancellation_exponents:
        for fraction in (0, 1, FRACTION):
            value = normal(exponent, fraction)
            signs(value, value, 'nonzero-exact-cancellation')
            for delta in (-1, 1):
                neighbor = value + delta
                if in_domain(neighbor, -900, 130):
                    signs(value, neighbor, 'deep-cancellation-and-neighbors')
    # Exact power-of-two residues cover all 55 possible left-normalization
    # shifts in the shared final window, now at this helper's distinct lattice.
    for bit in range(55):
        label = f'normalization-left-shift-{55-bit}'
        if bit <= 51:
            left, right = normal(-900, 1 << bit), normal(-900)
            signs(left, right, f'normalization-left-input-bit-{bit}')
            for kind in KINDS:
                for a, b in ((left, right), (right, left)):
                    for sign in (0, SIGN):
                        add(kind, a ^ sign, b ^ sign ^ (SIGN if kind == 'add' else 0), label)
        else:
            signs(0, normal(-952 + bit), label)
    # All 32 right-window residual counts with both a retained significand and
    # a low tail. The largest operand is well inside its binade so addition or
    # subtraction with the smaller one cannot change that binade.
    for residue in range(32):
        signs(normal(-897 + residue, 0x5555555555555), normal(-900, 1),
              f'normalization-right-residual-shift-{residue}')
    # Gaps straddle 32-bit words, guard/round/sticky positions and full extent;
    # one-bit and one-bit-hole mantissas force every significand bit position.
    gaps = sorted({0, 1, 2, 30, 31, 32, 33, 51, 52, 53, 54, 55, 63, 64, 65,
                   1028, 1029, 1030, *range(0, 1031, 32)})
    for index, gap in enumerate(gaps):
        for fraction in (0, 1, FRACTION):
            signs(normal(130, fraction), normal(130 - gap, FRACTION),
                  f'exponent-gap-{gap}')
    for bit in range(52):
        for fraction in (1 << bit, FRACTION ^ (1 << bit)):
            for gap in (0, 1, 31, 32, 52, 53, 54, 1030):
                signs(normal(130, fraction), normal(130-gap, fraction),
                      f'significand-bit-{bit}')
    for low in (-900, -899, -868, -1, 0, 1):
        for high in (low, min(130, low+1), 129, 130):
            for fraction in (0, 1, FRACTION):
                signs(normal(high, fraction), normal(low, FRACTION),
                      'extrema-long-carry-borrow')
    # Invalid encodings are placed in each operand, alongside positive/negative
    # zero as well as a nonzero input, before any zero/cancellation shortcut.
    invalid = [normal(e, f, s) for e in (-1022, -901, 131, 1023)
               for f in (0, 1, FRACTION) for s in (0, 1)]
    invalid += [(s << 63) | f for f in (1, 1 << 31, 1 << 32, 1 << 51, FRACTION) for s in (0, 1)]
    invalid += [(s << 63) | (2047 << 52) | f for f in (0, 1, 1 << 32, 1 << 51, FRACTION) for s in (0, 1)]
    for operand in (0, 1):
        for bad in invalid:
            for other in (0, SIGN, normal(0), normal(130, FRACTION, 1)):
                values = [other, other]; values[operand] = bad
                for kind in KINDS:
                    add(kind, *values, f'reject-invalid-operand-{operand}')
    for index, row in enumerate(rows):
        row['id'] = index
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
import ../../src/binary64_add_sub.bend as A
type Task is Data:
  Add{index: U32, ah: U32, al: U32, bh: U32, bl: U32}
  Sub{index: U32, ah: U32, al: U32, bh: U32, bl: U32}
def observe(index: U32, kind: U32, value: Maybe<F.Words>, rest: List<U32>) -> List<U32>:
  match value:
    case None{}: Con{index, Con{kind, Con{0, Con{0, Con{0, rest}}}}}
    case Some{pair}:
      F.Words{high, low} = pair
      Con{index, Con{kind, Con{1, Con{high, Con{low, rest}}}}}
def one(task: Task, rest: List<U32>) -> List<U32>:
  match task:
    case Add{index, ah, al, bh, bl}: observe(index, 0, A.checked_add(ah, al, bh, bl), rest)
    case Sub{index, ah, al, bh, bl}: observe(index, 1, A.checked_sub(ah, al, bh, bl), rest)
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
    (0, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000),
    (0, 0x0000000000000000, 0x8000000000000000, 0x0000000000000000),
    (0, 0x8000000000000000, 0x0000000000000000, 0x0000000000000000),
    (0, 0x8000000000000000, 0x8000000000000000, 0x8000000000000000),
    (1, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000),
    (1, 0x0000000000000000, 0x8000000000000000, 0x0000000000000000),
    (1, 0x8000000000000000, 0x0000000000000000, 0x8000000000000000),
    (1, 0x8000000000000000, 0x8000000000000000, 0x0000000000000000),
    (0, 0x3ff0000000000000, 0x3ca0000000000000, 0x3ff0000000000000),
    (0, 0x3ff0000000000001, 0x3ca0000000000000, 0x3ff0000000000002),
    (1, 0x3ff0000000000001, 0x3ca0000000000000, 0x3ff0000000000000),
    (1, 0x3ff0000000000002, 0x3ca0000000000000, 0x3ff0000000000002),
    (0, 0xbff0000000000000, 0xbca0000000000000, 0xbff0000000000000),
    (1, 0xbff0000000000001, 0xbca0000000000000, 0xbff0000000000000),
    (0, 0x3ff0000000000000, 0xbff0000000000000, 0x0000000000000000),
    (1, 0xbff0000000000000, 0xbff0000000000000, 0x0000000000000000),
    (0, 0x0000000000000001, 0x0000000000000000, 0x0000000000000001),
    (0, 0x8000000000000001, 0x0000000000000000, 0x8000000000000001),
    (1, 0x0000000000000000, 0x0000000000000001, 0x8000000000000001),
    (1, 0x0010000000000000, 0x000fffffffffffff, 0x0000000000000001),
    (0, 0x000fffffffffffff, 0x0000000000000001, 0x0010000000000000),
    (1, 0x0010000000000000, 0x0000000000000001, 0x000fffffffffffff),
    (0, 0x0000000000000001, 0x8000000000000001, 0x0000000000000000),
    (1, 0x8000000000000001, 0x8000000000000001, 0x0000000000000000),
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
_Static_assert(FLT_EVAL_METHOD == 0, "binary64 evaluation without excess precision");
static double add_values(double a, double b) {
  volatile double va=a, vb=b; volatile double result=va+vb; return result;
}
static double sub_values(double a, double b) {
  volatile double va=a, vb=b; volatile double result=va-vb; return result;
}
static double (* volatile runtime_add)(double, double) = add_values;
static double (* volatile runtime_sub)(double, double) = sub_values;
static uint64_t evaluate(unsigned kind, uint64_t a, uint64_t b) {
  double da,db; memcpy(&da,&a,8); memcpy(&db,&b,8);
  volatile double computed=kind ? runtime_sub(da,db) : runtime_add(da,db);
  double result=computed; uint64_t bits; memcpy(&bits,&result,8); return bits;
}
static int allowed(uint64_t value) {
  unsigned exponent=(unsigned)((value>>52)&2047);
  if (!exponent) return (value & UINT64_C(0x7fffffffffffffff)) == 0;
  return (int)exponent-1023 >= -900 && (int)exponent-1023 <= 130;
}
int main(int argc, char **argv) {
  int initial=fegetround();
  if (argc != 2 || initial < 0 || fesetround(FE_TONEAREST) || fegetround() != FE_TONEAREST) return 2;
  uint64_t control; const char *control_name;
#if defined(__x86_64__) || defined(__i386__)
  control=_mm_getcsr(); control_name="mxcsr";
  if (control & ((1u<<15) | (1u<<6) | (3u<<13))) return 3;
#else
  __asm__ volatile("mrs %0, fpcr" : "=r"(control)); control_name="fpcr";
  if (control & ((1ull<<24) | (1ull<<19) | (3ull<<22) | 3ull)) return 3;
#endif
  double one=1.0; uint64_t one_bits; memcpy(&one_bits,&one,8);
  if (one_bits != UINT64_C(0x3ff0000000000000)) return 4;
  static const uint64_t controls[][4] = {
@CONTROLS@
  };
  unsigned preflights=(unsigned)(sizeof controls/sizeof controls[0]);
  for (unsigned i=0;i<preflights;i++) {
    if (evaluate((unsigned)controls[i][0],controls[i][1],controls[i][2]) != controls[i][3]) {
      fprintf(stderr,"Runtime add/sub preflight %u failed\n",i); return 7;
    }
  }
  printf("{\"rounding\":\"FE_TONEAREST\",\"initial_rounding\":%d,\"selected_rounding\":%d,\"control_name\":\"%s\",\"control\":%" PRIu64 ",\"ftz\":false,\"daz\":false,\"runtime_add\":true,\"runtime_sub\":true,\"binary64_evaluation\":true,\"preflight_count\":%u}\n",initial,fegetround(),control_name,control,preflights);
  FILE *in=fopen(argv[1],"r"); if (!in) return 5;
  uint32_t index,kind,ah,al,bh,bl; int count;
  while ((count=fscanf(in,"%" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32,&index,&kind,&ah,&al,&bh,&bl)) == 6) {
    if (kind > 1) { fclose(in); return 8; }
    uint64_t a=((uint64_t)ah<<32)|al,b=((uint64_t)bh<<32)|bl;
    if (!allowed(a) || !allowed(b)) {
      printf("[%" PRIu32 ",%" PRIu32 ",0,0,0]\n",index,kind); continue;
    }
    uint64_t bits=evaluate(kind,a,b);
    printf("[%" PRIu32 ",%" PRIu32 ",1,%" PRIu32 ",%" PRIu32 "]\n",index,kind,(uint32_t)(bits>>32),(uint32_t)bits);
  }
  if (count != EOF || ferror(in) || fclose(in)) return 6;
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
            'control', 'ftz', 'daz', 'runtime_add', 'runtime_sub', 'binary64_evaluation', 'preflight_count'}
    if type(metadata) is not dict or set(metadata) != keys:
        raise ValueError('Malformed native environment metadata')
    if (metadata['rounding'] != 'FE_TONEAREST' or metadata['ftz'] is not False or
            metadata['daz'] is not False or metadata['runtime_add'] is not True or
            metadata['runtime_sub'] is not True or metadata['binary64_evaluation'] is not True or
            metadata['control_name'] not in ('mxcsr', 'fpcr')):
        raise ValueError('Unsupported native rounding/denormal/runtime environment')
    for key in ('initial_rounding', 'selected_rounding', 'control', 'preflight_count'):
        if type(metadata[key]) is not int or metadata[key] < 0:
            raise ValueError('Invalid native control metadata')
    word(metadata['control'], 32 if metadata['control_name'] == 'mxcsr' else 64)
    for key in ('initial_rounding', 'selected_rounding', 'preflight_count'):
        word(metadata[key], 32)
    if metadata['selected_rounding'] != 0 or metadata['preflight_count'] != PREFLIGHT_COUNT:
        raise ValueError('Unsupported native rounding or incomplete preflight')
    mask = ((1 << 15) | (1 << 6) | (3 << 13) if metadata['control_name'] == 'mxcsr'
            else (1 << 24) | (1 << 19) | (3 << 22) | 3)
    if metadata['control'] & mask:
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
    work = BUILD/'binary64-add-sub-probe'; work.mkdir(parents=True, exist_ok=True)
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
                      scope='private RN-even exact add/sub; each operand signed zero or normal [-900,130]',
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
