#!/usr/bin/env python3
"""Compare M.Libm.sin64 and M.Libm.cos64 (src/lgpl/sin.bend) with the glibc sin/cos model.

The reference is tools/reference/glibc_sin/model.c (the glibc 2.39 x86_64
__sin_fma and __cos_fma variants, tools/glibc_sin.py). Arguments: random
binary64 words of every exponent and sign; binary32 values promoted, as a
float argument reaches sin(); every region boundary of s_sin.c with its
neighbours (2^-27, 2^-26, 0.126, 0.855469, 2.426265, 105414350, the largest
finite value); multiples of pi/2 and their neighbours; the model's controls,
where the FMA and SSE2 variants differ; signed zeros, subnormals, infinities
and NaN (None). On a host whose own sin and cos reproduce the controls (glibc
2.39 on an FMA/AVX2 CPU) the native functions are compared too. The other
profiles answer None. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import math
import random
import struct

import glibc_sin
import probekit
from probekit import ProbeFailure

BATCH = 256
LINE = 16

# |x| bounds of s_sin.c's regions as high words (the low word is 0), and 0.126.
BOUNDS = (0x3e40000000000000, 0x3e50000000000000, 0x3fc020c49ba5e354, 0x3feb600000000000, 0x400368fd00000000, 0x419921fb00000000,
          0x7fefffffffffffff, 0x0010000000000000)


def bits(value):
    return struct.unpack('<Q', struct.pack('<d', value))[0]


def f32(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]


def arguments():
    rng = random.Random(0x51E)
    words = {}
    for exponent in range(1, 2047):
        for _ in range(2 if exponent < 0x3e0 or exponent > 0x440 else 12):
            words.setdefault((rng.getrandbits(1) << 63) | (exponent << 52) | rng.getrandbits(52), 'random')
    for exponent in range(90, 170):
        for _ in range(6):
            word = (rng.getrandbits(1) << 31) | (exponent << 23) | rng.getrandbits(23)
            words.setdefault(bits(f32(word)), 'promoted-binary32')
    for bound in BOUNDS:
        for delta in (-1, 0, 1):
            for sign in (0, 1 << 63):
                words.setdefault(((bound + delta) & 0x7fffffffffffffff) | sign, 'region-boundary')
    for k in range(1, 41):
        nearest = bits(k * math.pi / 2)
        for delta in (-2, -1, 0, 1, 2):
            words.setdefault(nearest + delta, 'quarter-turn')
            words.setdefault((nearest + delta) | (1 << 63), 'quarter-turn')
    for index in range(110):
        for delta in (-1, 0, 1):
            words.setdefault(bits(index / 128.0) + delta if index else delta & 1, 'table-row')
    for x, _ in glibc_sin.SIN_CONTROLS + glibc_sin.COS_CONTROLS:
        words.setdefault(x, 'variant-control')
    for special in (0, 1 << 63, 1, 0x000fffffffffffff, 0x8000000000000001, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000000,
                    0x7ff0000000000001):
        words.setdefault(special, 'special')
    return sorted(words.items())


REFERENCE = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
double MODEL_SIN(double);
double MODEL_COS(double);
static double (*volatile host_sin)(double) = sin;
static double (*volatile host_cos)(double) = cos;
static unsigned long long word(double value) { uint64_t w; memcpy(&w, &value, 8); return (unsigned long long) w; }
int main(int argc, char **argv) {
  FILE *in = fopen(argv[1], "r");
  unsigned long long w;
  while (fscanf(in, "%llx", &w) == 1) {
    double x;
    memcpy(&x, &w, 8);
    printf("%016llx %016llx %016llx %016llx\n", word(MODEL_SIN(x)), word(MODEL_COS(x)), word(host_sin(x)), word(host_cos(x)));
  }
  return 0;
}
'''

PROGRAM = '''import Base
import ../../jonmath.bend as M
def show(value: Maybe<M.Float64>) -> List<U32>:
  match value:
    case None{}: [0, 0, 0]
    case Some{M.Float64{high, low}}: [1, high, low]
def calculate(words: +List<U32>) -> List<U32>:
  match words:
    case Con{+high, Con{+low, rest}}: List.append(&1, U32, show(M.Libm.sin64(M.Glibc239Libm{}, M.Float64{high, low})),
      List.append(&1, U32, show(M.Libm.cos64(M.Glibc239Libm{}, M.Float64{high, low})), calculate(rest)))
    case _: Nil{}
def refused(words: +List<U32>) -> List<U32>:
  match words:
    case Con{+high, Con{+low, rest}}: List.append(&1, U32, show(M.Libm.sin64(M.AppleLibm{}, M.Float64{high, low})),
      List.append(&1, U32, show(M.Libm.cos64(M.Glibc241Libm{}, M.Float64{high, low})), refused(rest)))
    case _: Nil{}
def main() -> IO(Unit):
  do IO<Unit>:
'''

# Arguments the other profiles must answer None for (the first of each batch).
OTHERS = 2


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('glibc-sin', args)
    cases = arguments()
    objects = glibc_sin.objects(probe)
    native = glibc_sin.host_is_model(probe)
    source, binary, inputs = probe.work / 'reference.c', probe.work / 'reference', probe.work / 'arguments.txt'
    source.write_text(REFERENCE.replace('MODEL_SIN', glibc_sin.SIN).replace('MODEL_COS', glibc_sin.COS))
    inputs.write_text(''.join(f'{x:016x}\n' for x, _ in cases))
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin', source, *objects, '-lm', '-o', binary])
    lines = probekit.run([binary, inputs]).splitlines()
    if len(lines) != len(cases):
        raise ProbeFailure('glibc-sin: incomplete reference output')
    expected = []
    for (x, label), line in zip(cases, lines):
        sine, cosine, host_sine, host_cosine = (int(part, 16) for part in line.split())
        finite = (x >> 52) & 2047 != 2047
        if native and finite and (sine != host_sine or cosine != host_cosine):
            raise ProbeFailure(f'glibc-sin: the host differs from the model at {x:016x} ({label})')
        expected.append([1, sine >> 32, sine & 0xffffffff, 1, cosine >> 32, cosine & 0xffffffff] if finite else [0, 0, 0, 0, 0, 0])

    def words(chosen):
        return ', '.join(f'{x >> 32}, {x & 0xffffffff}' for x, _ in chosen)

    def render(chosen, gpu):
        call = 'calculate!' if gpu else 'calculate'
        return (PROGRAM + ''.join(f'    IO.print(List.show(~&1, ~U32, ~U32.show, {call}([{words(chosen[start:start + LINE])}])))\n'
                                  for start in range(0, len(chosen), LINE))
                + f'    IO.print(List.show(~&1, ~U32, ~U32.show, refused([{words(chosen[:OTHERS])}])))\n')

    def parse(text, chosen):
        values = [value for line in text.splitlines() for value in json.loads(line)]
        if len(values) != 6 * (len(chosen) + min(OTHERS, len(chosen))):
            raise ProbeFailure('glibc-sin: wrong candidate output size')
        if any(values[6 * len(chosen):]):
            raise ProbeFailure('glibc-sin: a profile without a verified binary64 sin answered')
        return [values[6 * i:6 * i + 6] for i in range(len(chosen))]

    lanes = probe.candidates(render, cases, batch=BATCH, parse=parse)
    probe.compare(expected, lanes, describe=lambda i: f'argument {cases[i][0]:016x} ({cases[i][1]})')
    labels = {}
    for _, label in cases:
        labels[label] = labels.get(label, 0) + 1
    probe.finish(arguments=len(cases), labels=labels, native_compared=native)


if __name__ == '__main__':
    main()
