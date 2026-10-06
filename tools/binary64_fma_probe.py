#!/usr/bin/env python3
"""Private bounded binary64 FMA: independent rational/native and CPU-1/2/JS gates."""
import random

from binary64_fma_oracle import BOUNDS, FRACTION, SIGN, checked, word
from binary64_harness import FLAGS, labelled, normal, run

CHUNK = 256
SEED = 0x64F0A
FIELDS = ('ah', 'al', 'bh', 'bl', 'ch', 'cl')
PREFLIGHT_COUNT = 9


# Hard-coded IEEE encodings, independent of both rounding implementations.
HAND = (
    (0x3ff0000000000001, 0x3feffffffffffffe, 0xbff0000000000000,
     0xb970000000000000, 'fused-not-split-control'),
    (0x2ea0000000000001, 0x2ea0000000000001, 0x9d50000000000002,
     0x16d0000000000000, 'minimum-positive-lattice-result'),
    (0xaea0000000000001, 0x2ea0000000000001, 0x1d50000000000002,
     0x96d0000000000000, 'minimum-negative-lattice-result'),
    (0x3ff0000000000000, 0x3ff0000000000000, 0x3ca0000000000000,
     0x3ff0000000000000, 'hand-even-tie'),
    (0x3ff0000000000001, 0x3ff0000000000000, 0x3ca0000000000000,
     0x3ff0000000000002, 'hand-odd-tie'),
)


def samples():
    """Deterministic, deduplicated and labeled; every allowed input exponent."""
    rows, record = labelled()
    def add(a, b, c, label):
        key = tuple(word(value, 64) for value in (a, b, c))
        record(key, dict(kind='fma', labels=[], **dict(zip(FIELDS, [part for value in key for part in (value >> 32, value & 0xffffffff)]))), label)
    def signed(a, b, c, label):
        add(a, b, c, label)
        add(a ^ SIGN, b, c ^ SIGN, label)
    for a, b, c, expected, label in HAND:
        result = checked(a >> 32, a & 0xffffffff, b >> 32, b & 0xffffffff, c >> 32, c & 0xffffffff)
        if result != (expected >> 32, expected & 0xffffffff):
            raise ValueError('Exact rational oracle disagrees with fixed hand vector')
        add(a, b, c, label)
    one = normal(0)
    for a in (0, SIGN):
        for b in (0, SIGN):
            for c in (0, SIGN):
                add(a, b, c, 'all-zero-sign-combinations')
    for exponent in (-277, 0, 127):
        for sign_a in (0, 1):
            for sign_b in (0, 1):
                for sign_c in (0, 1):
                    add(sign_a << 63, normal(exponent, FRACTION, sign_b), sign_c << 63, 'zero-product-signs')
                    add(normal(exponent, FRACTION, sign_a), sign_b << 63, sign_c << 63, 'zero-product-signs')
    rng = random.Random(SEED)
    for operand, (minimum, maximum) in enumerate(BOUNDS):
        for exponent in range(minimum, maximum + 1):
            for sign in (0, 1):
                values = [normal(rng.randint(*BOUNDS[i]), rng.getrandbits(52), rng.getrandbits(1)) for i in range(3)]
                values[operand] = normal(exponent, rng.getrandbits(52), sign)
                add(*values, f'every-exponent-operand-{operand}')
                # Pure powers isolate extraction/positioning independently of random fractions.
                isolated = [one, one, 0]
                isolated[operand] = normal(exponent, 0, sign)
                if operand == 2:
                    isolated[0] = 0
                add(*isolated, f'every-power-of-two-operand-{operand}')
    # Exact midpoint, either side, odd/even retained significands, binade carries.
    tie_exponents = sorted({-501, -500, -278, -277, -1, 0, 1, 126, 127, 253, 254, *range(-480, 255, 32)})
    for exponent in tie_exponents:
        ea = max(-277, min(127, exponent // 2))
        eb = exponent - ea
        for fraction in (0, 1, FRACTION):
            for delta in (-1, 0, 1):
                label = ('reject-c-below-minimum-normal' if exponent == -501 and delta == -1
                         else 'ties-even-odd-carry-and-adjacent')
                signed(normal(ea, fraction), normal(eb), normal(exponent - 53) + delta, label)
                if fraction == FRACTION and delta >= 0:
                    signed(normal(ea, fraction), normal(eb), normal(exponent - 53) + delta,
                           'retained-53-bit-rounding-carry')
    cancellation_exponents = sorted({-554, -553, -552, -277, -1, 0, 1, 127, 253, 254, *range(-544, 255, 16)})
    for exponent in cancellation_exponents:
        ea = max(-277, min(127, exponent // 2))
        eb = exponent - ea
        signed(normal(ea), normal(eb), normal(exponent, sign=1), 'nonzero-exact-cancellation')
        signed(normal(ea, 1), normal(eb, 1), normal(exponent, 2, 1), 'deep-104-bit-cancellation')
        for delta in (-1, 1):
            signed(normal(ea, 1), normal(eb, 1), normal(exponent, 2, 1) + delta,
                   'deep-cancellation-neighbors')
    # Exact residues enumerate both alignment and final normalization branches.
    for residue in range(32):
        signed(normal(-277 + residue, FRACTION), normal(-277, FRACTION),
               normal(-542 + residue, FRACTION), f'alignment-residual-shift-{residue}')
        signed(normal(-277), normal(-262 + residue), normal(-554, FRACTION),
               f'normalization-residual-shift-{residue}')
    for bit in range(55):
        exponent = -554 + bit
        ea = exponent // 2
        signed(normal(ea, 1), normal(exponent - ea, 1), normal(exponent, 2, 1),
               f'normalization-left-shift-{55-bit}')
    # Carry/borrow chains across the full bounded accumulator span; no limb algorithm is reused.
    edge_exponents = (-277, -276, -129, -128, -1, 0, 1, 126, 127)
    for ea in edge_exponents:
        for eb in edge_exponents:
            for fraction in (0, 1, FRACTION):
                for ec in (-554, min(255, max(-554, ea + eb)), 255):
                    for c_sign in (0, 1):
                        signed(normal(ea, fraction), normal(eb, FRACTION), normal(ec, FRACTION, c_sign),
                               'extreme-gaps-long-carry-borrow')
    # Do not permit a zero shortcut to evade any invalid-operand check.
    for operand, (minimum, maximum) in enumerate(BOUNDS):
        invalid = [normal(e, f, s) for e in (-1022, minimum-1, maximum+1, 1023)
                   for f in (0, FRACTION) for s in (0, 1)]
        invalid += [(s << 63) | f for f in (1, 1 << 31, 1 << 51, FRACTION) for s in (0, 1)]
        invalid += [(s << 63) | (2047 << 52) | f for f in (0, 1, 1 << 32, 1 << 51, FRACTION)
                    for s in (0, 1)]
        for bad in invalid:
            for base in ([one, one, one], [0, 0, 0], [SIGN, SIGN, SIGN]):
                values = list(base)
                values[operand] = bad
                add(*values, f'reject-invalid-operand-{operand}')
    for index, row in enumerate(rows):
        row['id'] = index
    return rows


def expected_row(row):
    index = word(row['id'], 32)
    if row['kind'] != 'fma':
        raise ValueError('Unknown observation kind')
    result = checked(*(row[field] for field in FIELDS))
    return [index, 0, 0, 0] if result is None else [index, 1, *result]


PROGRAM = '''import Base
import ../../src/binary64_fma.bend as F
type Task is Data:
  Fma{index: U32, ah: U32, al: U32, bh: U32, bl: U32, ch: U32, cl: U32}
def observe(index: U32, value: Maybe<F.Words>, rest: List<U32>) -> List<U32>:
  match value:
    case None{}: Con{index, Con{0, Con{0, Con{0, rest}}}}
    case Some{pair}:
      F.Words{high, low} = pair
      Con{index, Con{1, Con{high, Con{low, rest}}}}
def one(task: Task, rest: List<U32>) -> List<U32>:
  match task:
    case Fma{index, ah, al, bh, bl, ch, cl}: observe(index, F.checked(ah, al, bh, bl, ch, cl), rest)
def calculate(values: +List<Task>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{task, rest}: one(task, calculate(rest))
def main() -> IO(Unit):
  do IO<Unit>:
'''


# The host's runtime libm fma (not a compiler builtin) is preflighted on fixed IEEE controls.
NATIVE = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <float.h>
#include <limits.h>
#include <fenv.h>
#include <math.h>
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
static double (* volatile runtime_fma)(double, double, double) = fma;
static uint64_t evaluate(uint64_t a, uint64_t b, uint64_t c) {
  double da, db, dc; memcpy(&da,&a,8); memcpy(&db,&b,8); memcpy(&dc,&c,8);
  volatile double va=da, vb=db, vc=dc;
  volatile double computed=runtime_fma(va,vb,vc);
  double result=computed; uint64_t bits; memcpy(&bits,&result,8); return bits;
}
static int allowed(uint64_t value, int minimum, int maximum) {
  unsigned exponent=(unsigned)((value>>52)&2047);
  if (!exponent) return (value & UINT64_C(0x7fffffffffffffff)) == 0;
  return (int)exponent-1023 >= minimum && (int)exponent-1023 <= maximum;
}
int main(void) {
  int initial=fegetround();
  if (fesetround(FE_TONEAREST) || fegetround() != FE_TONEAREST) return 2;
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
    {UINT64_C(0x3ff0000000000001),UINT64_C(0x3feffffffffffffe),UINT64_C(0xbff0000000000000),UINT64_C(0xb970000000000000)},
    {UINT64_C(0x2ea0000000000001),UINT64_C(0x2ea0000000000001),UINT64_C(0x9d50000000000002),UINT64_C(0x16d0000000000000)},
    {UINT64_C(0x3ff0000000000000),UINT64_C(0x3ff0000000000000),UINT64_C(0x3ca0000000000000),UINT64_C(0x3ff0000000000000)},
    {UINT64_C(0x3ff0000000000001),UINT64_C(0x3ff0000000000000),UINT64_C(0x3ca0000000000000),UINT64_C(0x3ff0000000000002)},
    {UINT64_C(0x0000000000000000),UINT64_C(0xbff0000000000000),UINT64_C(0x8000000000000000),UINT64_C(0x8000000000000000)},
    {UINT64_C(0x0000000000000000),UINT64_C(0xbff0000000000000),UINT64_C(0x0000000000000000),UINT64_C(0x0000000000000000)},
    {UINT64_C(0x3ff0000000000000),UINT64_C(0x3ff0000000000000),UINT64_C(0xbff0000000000000),UINT64_C(0x0000000000000000)},
    {UINT64_C(0x0010000000000000),UINT64_C(0x3fe0000000000000),UINT64_C(0x0000000000000000),UINT64_C(0x0008000000000000)},
    {UINT64_C(0x0000000000000001),UINT64_C(0x3ff0000000000000),UINT64_C(0x0000000000000000),UINT64_C(0x0000000000000001)}
  };
  unsigned preflights=(unsigned)(sizeof controls/sizeof controls[0]);
  for (unsigned i=0;i<preflights;i++) {
    if (evaluate(controls[i][0],controls[i][1],controls[i][2]) != controls[i][3]) {
      fprintf(stderr,"Runtime libm fma preflight %u failed\n",i); return 7;
    }
  }
  printf("{\"rounding\":\"FE_TONEAREST\",\"initial_rounding\":%d,\"selected_rounding\":%d,\"control_name\":\"%s\",\"control\":%" PRIu64 ",\"ftz\":false,\"daz\":false,\"runtime_fma\":true,\"preflight_count\":%u}\n",initial,fegetround(),control_name,control,preflights);
  FILE *in=fopen(INPUT,"r"); if (!in) return 5;
  uint32_t index,ah,al,bh,bl,ch,cl; int count;
  while ((count=fscanf(in,"%" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32,&index,&ah,&al,&bh,&bl,&ch,&cl)) == 7) {
    uint64_t a=((uint64_t)ah<<32)|al,b=((uint64_t)bh<<32)|bl,c=((uint64_t)ch<<32)|cl;
    if (!allowed(a,-277,127) || !allowed(b,-277,127) || !allowed(c,-554,255)) {
      printf("[%" PRIu32 ",0,0,0]\n",index); continue;
    }
    uint64_t bits=evaluate(a,b,c);
    printf("[%" PRIu32 ",1,%" PRIu32 ",%" PRIu32 "]\n",index,(uint32_t)(bits>>32),(uint32_t)bits);
  }
  if (count != EOF || ferror(in) || fclose(in)) return 6;
  return 0;
}
'''


def main():
    run('binary64-fma', __doc__, rows=samples(), expected_row=expected_row, native=NATIVE,
        native_rows=lambda row: True, native_input=lambda r: ' '.join(str(v) for v in (r['id'], *(r[f] for f in FIELDS))),
        metadata=('rounding', 'initial_rounding', 'selected_rounding', 'control_name', 'control', 'ftz', 'daz',
                  'runtime_fma', 'preflight_count'),
        header=PROGRAM, task=lambda r: 'Fma{' + ','.join(str(v) for v in (r['id'], *(r[f] for f in FIELDS))) + '}',
        width=4, batch=CHUNK, flags=(*FLAGS[:3], '-fno-builtin-fma', '-fno-lto'), preflights=PREFLIGHT_COUNT)


if __name__ == '__main__':
    main()
