#!/usr/bin/env python3
"""Private bounded binary64 add/sub: rational/native and CPU-1/2/JS gates.

The arithmetic oracle and corpus are independent of the candidate. Every
reported observation includes its operation kind.
"""
import random

from binary64_add_sub_oracle import KINDS, SIGN, checked, in_domain, word
from binary64_harness import CALCULATE, FIELDS, FRACTION, OBSERVE, controls, kinded, labelled, normal, run

CHUNK = 256
SEED = 0x64ADD5AB


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
    rows, record = labelled()
    def add(kind, a, b, label):
        if kind not in KINDS:
            raise ValueError('Unknown corpus operation')
        key = (kind, word(a, 64), word(b, 64))
        record(key, dict(kind=kind, labels=[], **dict(zip(FIELDS, [part for value in (a, b) for part in (value >> 32, value & 0xffffffff)]))), label)
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
    return rows


expected_row, task, native_input = kinded(KINDS, checked)
PROGRAM = '''import Base
import ../../src/binary64_fma.bend as F
import ../../src/binary64_add_sub.bend as A
type Task is Data:
  Add{index: U32, ah: U32, al: U32, bh: U32, bl: U32}
  Sub{index: U32, ah: U32, al: U32, bh: U32, bl: U32}
''' + OBSERVE + '''def one(task: Task, rest: List<U32>) -> List<U32>:
  match task:
    case Add{index, ah, al, bh, bl}: observe(index, 0, A.checked_add(ah, al, bh, bl), rest)
    case Sub{index, ah, al, bh, bl}: observe(index, 1, A.checked_sub(ah, al, bh, bl), rest)
''' + CALCULATE

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
int main(void) {
  int initial=fegetround();
  if (initial < 0 || fesetround(FE_TONEAREST) || fegetround() != FE_TONEAREST) return 2;
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
  FILE *in=fopen(INPUT,"r"); if (!in) return 5;
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
'''.replace('@CONTROLS@', controls(NATIVE_CONTROLS))


def main():
    run('binary64-add-sub', __doc__, rows=samples(), expected_row=expected_row, native=NATIVE,
        native_rows=lambda row: True, native_input=native_input,
        metadata=('rounding', 'initial_rounding', 'selected_rounding', 'control_name', 'control', 'ftz', 'daz',
                  'runtime_add', 'runtime_sub', 'binary64_evaluation', 'preflight_count'),
        header=PROGRAM, task=task, width=5, batch=CHUNK, preflights=len(NATIVE_CONTROLS))


if __name__ == '__main__':
    main()
