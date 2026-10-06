#!/usr/bin/env python3
"""Private gradual-output binary64 multiply: rational/native and CPU-1/2/JS gates.

The arithmetic oracle and corpus are independent of the candidate. Every
reported observation includes its operation kind.
"""
import random

from binary64_gradual_multiply_oracle import BOUNDS, KINDS, SIGN, checked, in_domain, word
from binary64_harness import CALCULATE, FIELDS, FRACTION, OBSERVE, controls, kinded, labelled, normal, run

CHUNK = 256
SEED = 0x64A6D00D


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
    rows, record = labelled()
    def add(a, b, label):
        key = (word(a, 64), word(b, 64))
        record(key, dict(kind='multiply', labels=[], **dict(zip(FIELDS, [part for value in key for part in (value >> 32, value & 0xffffffff)]))), label)
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
    return rows


expected_row, task, native_input = kinded(KINDS, checked)
PROGRAM = '''import Base
import ../../src/binary64_fma.bend as F
import ../../src/binary64_gradual_multiply.bend as G
type Task is Data:
  Multiply{index: U32, ah: U32, al: U32, bh: U32, bl: U32}
''' + OBSERVE + '''def one(task: Task, rest: List<U32>) -> List<U32>:
  match task:
    case Multiply{index, ah, al, bh, bl}: observe(index, 0, G.checked(ah, al, bh, bl), rest)
''' + CALCULATE

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
int main(void) {
  int initial=fegetround();
  if (initial < 0 || fesetround(FE_TONEAREST) || fegetround() != FE_TONEAREST) return 2;
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
  FILE *in=fopen(INPUT,"r"); if (!in) return 5;
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
'''.replace('@CONTROLS@', controls(NATIVE_CONTROLS))


def main():
    run('binary64-gradual-multiply', __doc__, rows=samples(), expected_row=expected_row, native=NATIVE,
        native_rows=lambda row: True, native_input=native_input,
        metadata=('rounding', 'initial_rounding', 'selected_rounding', 'control_name', 'control', 'control_after',
                  'ftz', 'daz', 'runtime_mul', 'binary64_evaluation', 'preflight_count'),
        header=PROGRAM, task=task, width=5, batch=CHUNK, preflights=len(NATIVE_CONTROLS))


if __name__ == '__main__':
    main()
