#!/usr/bin/env python3
"""Private finite binary64 narrowing: exact rational oracle, qualified C, CPU-1/2/JS."""
import random
import struct

from binary64_harness import FLAGS, run
from binary64_narrow_oracle import decode64, nearest, positive32, word

CHUNK = 512
LINE = 32
SEED = 0x6432E
HAND = (
    (0x36900000, 0x00000000, 0x00000000),
    (0x36900000, 0x00000001, 0x00000001),
    (0x36a7ffff, 0xffffffff, 0x00000001),
    (0x36a80000, 0x00000000, 0x00000002),
    (0x380fffff, 0xdfffffff, 0x007fffff),
    (0x380fffff, 0xe0000000, 0x00800000),
    (0x47efffff, 0xefffffff, 0x7f7fffff),
    (0x47efffff, 0xf0000000, 0x7f800000),
)


def rational64(value):
    bits = struct.unpack('>Q', struct.pack('>d', float(value)))[0]
    if decode64(bits >> 32, bits & 0xffffffff) != value:
        raise ValueError('Corpus rational is not exactly representable in binary64')
    return bits


def samples():
    """Fixed full corpus. Deduplication preserves all coverage labels."""
    rows, seen = [], {}
    def add(bits, label, promoted=None):
        word(bits, 64)
        if bits not in seen:
            row = dict(kind='narrow', high=bits >> 32, low=bits & 0xffffffff, labels=[])
            seen[bits] = row
            rows.append(row)
        row = seen[bits]
        if label not in row['labels']:
            row['labels'].append(label)
        if promoted is not None:
            row['promoted32'] = promoted
    def signs(bits, label):
        for sign in (0, 1 << 63):
            add(bits | sign, label)
    for high, low, expected in HAND:
        if nearest(high, low) != expected:
            raise ValueError('Exact rational oracle disagrees with a fixed hand vector')
        signs((high << 32) | low, 'hand-boundaries')
    rng = random.Random(SEED)
    for exponent in range(2047):
        for fraction in (0, 1, (1 << 52) - 1):
            signs((exponent << 52) | fraction, 'every-finite-exponent-transition')
        for _ in range(2):
            signs((exponent << 52) | rng.getrandbits(52), 'exponent-stratified-random')
    # All binary64 subnormal binades and both sides of each limb carry.
    for bit in range(52):
        for delta in (-1, 0, 1):
            signs((1 << bit) + delta, 'binary64-subnormal-binades')
    for exponent in (873, 874, 895, 896, 897, 898, 1023, 1150):
        for fraction_high in (0, 1, 0x7ffff, 0xfffff):
            for low in (0, 1, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff):
                signs((exponent << 52) | (fraction_high << 32) | low, 'limb-carries')
    # Midpoints have <=25 significant bits, hence are exact binary64 values.
    lower_words = { (e << 23) | f for e in range(255)
                    for f in (0, 1, 2, 0x3ffffe, 0x3fffff, 0x7ffffe, 0x7fffff) }
    lower_words |= { (1 << bit) + delta for bit in range(23) for delta in (-1, 0, 1) }
    for lower in sorted(lower_words):
        midpoint = (positive32(lower) + positive32(lower + 1)) / 2
        bits = rational64(midpoint)
        for delta in (-1, 0, 1):
            signs(bits + delta, 'even-odd-ties-and-adjacent64')
    # Sample every finite binary32 exponent and all subnormal binades exactly.
    roundtrip = { (e << 23) | f for e in range(255)
                  for f in (0, 1, 2, 0x3fffff, 0x400000, 0x7ffffe, 0x7fffff) }
    roundtrip |= { (1 << bit) + delta for bit in range(23) for delta in (-1, 0, 1) }
    for bits32 in sorted(roundtrip):
        bits64 = rational64(positive32(bits32))
        for sign in (0, 1):
            add(bits64 | (sign << 63), 'finite32-promote-narrow', bits32 | (sign << 31))
    for row in list(rows):
        if 'promoted32' in row:
            rows.append(dict(kind='promote', value=row['promoted32'], labels=['existing-promote-roundtrip']))
    for fraction in (0, 1, (1 << 51)-1, 1 << 51, (1 << 51)+1, (1 << 52)-1):
        signs((2047 << 52) | fraction, 'reject-infinity-and-nan')
    # Independent integer invariants exercise jam through and beyond 64 bits.
    limb_values = [0, 1, 2, 3, 0x7fffffff, 0x80000000, 0xffffffff,
                   0x100000000, 0x100000001, 0x8000000000000000, (1 << 64)-1]
    limb_values += [rng.getrandbits(64) for _ in range(7)]
    for count in range(66):
        for value in limb_values:
            rows.append(dict(kind='jam', count=count, high=value >> 32,
                             low=value & 0xffffffff, labels=['jam-invariant']))
    for quotient in (0, 1, 2, 3, 0x7ffffe, 0x7fffff, 0x800000, 0xfffffe, 0xffffff):
        for tail in range(8):
            rows.append(dict(kind='round', value=(quotient << 3) | tail,
                             labels=['guard-round-sticky-even-odd']))
    for index, row in enumerate(rows):
        row['id'] = index
    return rows


def expected_row(row):
    """[id, tag, payload...]: tag 0 rejected, 1 binary32 word, 2 jammed 64-bit shift, 3 RN-even rounded quotient."""
    index = word(row['id'], 32)
    if row['kind'] == 'narrow':
        result = nearest(row['high'], row['low'])
        if 'promoted32' in row and result != row['promoted32']:
            raise ValueError('Oracle violates finite32 roundtrip')
        return [index, 0, 0, 0] if result is None else [index, 1, result, 0]
    if row['kind'] == 'promote':
        return [index, 1, word(row['value'], 32), 0]
    if row['kind'] == 'jam':
        value = (row['high'] << 32) | row['low']
        count = row['count']
        result = (value >> count) | int(value % (1 << count) != 0)
        return [index, 2, result >> 32, result & 0xffffffff]
    if row['kind'] == 'round':
        quotient, rest = divmod(row['value'], 8)
        result = quotient + (rest > 4 or (rest == 4 and quotient % 2 != 0))
        return [index, 3, result, 0]
    raise ValueError('Unknown observation kind')


def task(row):
    if row['kind'] == 'narrow':
        return 'Narrow{%d,%d,%d}' % (row['id'], row['high'], row['low'])
    if row['kind'] == 'jam':
        return 'Jam{%d,%dn,%d,%d}' % (row['id'], row['count'], row['high'], row['low'])
    if row['kind'] == 'promote':
        return 'Promote{%d,%d}' % (row['id'], row['value'])
    return 'Round{%d,%d}' % (row['id'], row['value'])


PROGRAM = '''import Base
import ../../src/binary64_narrow.bend as N
import ../../src/float64.bend as D
type Task is Data:
  Narrow{index: U32, high: U32, low: U32}
  Jam{index: U32, count: Nat, high: U32, low: U32}
  Round{index: U32, value: U32}
  Promote{index: U32, value: U32}
def narrow(index: U32, value: Maybe<U32>, rest: List<U32>) -> List<U32>:
  match value:
    case None{}: Con{index, Con{0, Con{0, Con{0, rest}}}}
    case Some{word}: Con{index, Con{1, Con{word, Con{0, rest}}}}
def jam(index: U32, value: N.Wide, rest: List<U32>) -> List<U32>:
  N.Wide{high, low} = value
  Con{index, Con{2, Con{high, Con{low, rest}}}}
def promote.words(index: U32, pair: U32 & U32, rest: List<U32>) -> List<U32>:
  (high, low) = pair
  narrow(index, N.checked(high, low), rest)
def promote(index: U32, value: U32, rest: List<U32>) -> List<U32>:
  U32{bits} = value
  promote.words(index, D.promote(F32{bits}), rest)
def one(task: Task, rest: List<U32>) -> List<U32>:
  match task:
    case Narrow{index, high, low}: narrow(index, N.checked(high, low), rest)
    case Jam{index, count, high, low}: jam(index, N.Wide.jam(count, N.Wide{high, low}), rest)
    case Round{index, value}: Con{index, Con{3, Con{N.round(value), Con{0, rest}}}}
    case Promote{index, value}: promote(index, value, rest)
def calculate(values: +List<Task>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{task, rest}: one(task, calculate(rest))
def main() -> IO(Unit):
  do IO<Unit>:
'''


# The qualified host cast is checked against the rational oracle on every narrow row.
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
_Static_assert(CHAR_BIT == 8 && sizeof(float) == 4 && sizeof(double) == 8, "word layout");
_Static_assert(FLT_RADIX == 2 && FLT_MANT_DIG == 24 && FLT_MIN_EXP == -125 && FLT_MAX_EXP == 128, "binary32");
_Static_assert(DBL_MANT_DIG == 53 && DBL_MIN_EXP == -1021 && DBL_MAX_EXP == 1024, "binary64");
int main(void) {
  int initial = fegetround();
  if (fesetround(FE_TONEAREST) || fegetround() != FE_TONEAREST) return 2;
  uint64_t control;
  const char *control_name;
#if defined(__x86_64__) || defined(__i386__)
  control = _mm_getcsr(); control_name = "mxcsr";
  if (control & ((1u<<15) | (1u<<6) | (3u<<13))) return 3;
#else
  __asm__ volatile("mrs %0, fpcr" : "=r"(control)); control_name = "fpcr";
  if (control & ((1ull<<24) | (1ull<<19) | (3ull<<22))) return 3;
#endif
  double one = 1.0; uint64_t one_bits; memcpy(&one_bits,&one,8);
  if (one_bits != UINT64_C(0x3ff0000000000000)) return 4;
  float one32 = 1.0f; uint32_t one32_bits; memcpy(&one32_bits,&one32,4);
  if (one32_bits != UINT32_C(0x3f800000)) return 4;
  printf("{\"rounding\":\"FE_TONEAREST\",\"initial_rounding\":%d,\"selected_rounding\":%d,\"control_name\":\"%s\",\"control\":%" PRIu64 ",\"ftz\":false,\"daz\":false}\n",initial,fegetround(),control_name,control);
  FILE *in=fopen(INPUT,"r"); if (!in) return 5;
  uint32_t index,hi,lo;
  int count;
  while ((count=fscanf(in,"%" SCNu32 " %" SCNu32 " %" SCNu32,&index,&hi,&lo)) == 3) {
    if (((hi>>20)&2047)==2047) { printf("[%" PRIu32 ",0,0,0]\n",index); continue; }
    uint64_t bits=((uint64_t)hi<<32)|lo; double stored;
    memcpy(&stored,&bits,8); volatile double input=stored;
    volatile float converted=(float)input; float output=converted; uint32_t word;
    memcpy(&word,&output,4); printf("[%" PRIu32 ",1,%" PRIu32 ",0]\n",index,word);
  }
  if (count != EOF || ferror(in) || fclose(in)) return 6;
  return 0;
}
'''


def main():
    run('binary64-narrow', __doc__, rows=samples(), expected_row=expected_row, native=NATIVE,
        native_rows=lambda row: row['kind'] == 'narrow', native_input=lambda r: f'{r["id"]} {r["high"]} {r["low"]}',
        metadata=('rounding', 'initial_rounding', 'selected_rounding', 'control_name', 'control', 'ftz', 'daz'),
        header=PROGRAM, task=task, width=4, line=LINE, batch=CHUNK, flags=FLAGS[:3])


if __name__ == '__main__':
    main()
