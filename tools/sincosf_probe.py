#!/usr/bin/env python3
"""Compare Jonlib's glibc sinf/cosf kernel (src/sincosf.bend) with the glibc model.

The reference is tools/reference/glibc_sinf/model.c (the glibc 2.39/2.41
x86_64 __sinf_fma/__cosf_fma variants, tools/glibc_sinf.py), which equals the
native functions on every binary32 argument (docs/SINCOSF.md). Arguments:
random binary32 words of every exponent and sign, the boundaries of the four
regions (|y| < 0x1p-12f, < pio4, < 120, finite), the arguments where the FMA
and SSE2 variants differ, the smallest reduced arguments of reduce_fast and
reduce_large, the binary32 neighbours of k*pi/4 below 120 (quadrant
changes), whole degrees through DEG2RAD, signed zeros, subnormals, the
largest finite values, infinities and NaN (None). On a host whose own
sinf/cosf pass the controls (glibc on an FMA/AVX2 CPU) the native functions
are compared too. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import math
import random
import struct

import glibc_sinf
import probekit
from probekit import ProbeFailure

BATCH = 1024
LINE = 32
DEG2RAD = 0x3c8efa35


def f32(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def arguments():
    rng = random.Random(0x51CF)
    words = {}
    for exponent in range(255):
        for sign in (0, 1 << 31):
            for _ in range(2):
                words.setdefault(sign | (exponent << 23) | rng.getrandbits(23), 'random')
    for top in (0x398, 0x3f4, 0x42f, 0x7f8):
        for delta in (-1, 0, 1):
            for sign in (0, 1 << 31):
                words.setdefault(sign | ((top << 20) + delta), 'region-boundary')
    for x, _, _ in glibc_sinf.CONTROLS:
        for sign in (0, 1 << 31):
            words.setdefault(sign | x, 'variant-difference')
    # The smallest |r| of reduce_fast and reduce_large; 0.75 <= y < pio4 reduces with n = 0.
    for x in (0x4096cbe4, 0x6f79be45, 0x3f400000, 0x3f480000, 0x3f490fda, 0x3f490fdb):
        for sign in (0, 1 << 31):
            words.setdefault(sign | x, 'reduction')
    for k in range(1, 153):
        centre = word(k * math.pi / 4)
        for delta in (-1, 0, 1):
            for sign in (0, 1 << 31):
                words.setdefault(sign | (centre + delta), 'quadrant')
    for degree in range(-1440, 1441, 9):
        words.setdefault(word(f32(word(float(degree))) * f32(DEG2RAD)), 'degrees')
    for special in (0, 1 << 31, 1, 0x80000001, 0x007fffff, 0x00800000, 0x7f7fffff, 0xff7fffff,
                    0x7f800000, 0xff800000, 0x7fc00000, 0xffc00001):
        words.setdefault(special, 'special')
    return sorted(words.items())


REFERENCE = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
float SINF(float), COSF(float);
static float (*volatile host_sinf)(float) = sinf, (*volatile host_cosf)(float) = cosf;
static uint32_t bits(float v) { uint32_t b; memcpy(&b, &v, 4); return b; }
int main(int argc, char **argv) {
  FILE *in = fopen(argv[1], "r");
  unsigned word;
  while (fscanf(in, "%x", &word) == 1) {
    float x;
    memcpy(&x, &word, 4);
    printf("%08x %08x %08x %08x\n", bits(SINF(x)), bits(COSF(x)), bits(host_sinf(x)), bits(host_cosf(x)));
  }
  return 0;
}
'''

PROGRAM = '''import Base
import ../../src/sincosf.bend as K
def show(value: Maybe<F32>) -> List<U32>:
  match value:
    case None{}: [0, 0]
    case Some{v}: [1, F32.bits(v)]
def both(+word: U32) -> List<U32>:
  U32{w} = word
  List.append(&1, U32, show(K.sinf(F32{w})), show(K.cosf(F32{w})))
def calculate(words: List<U32>) -> List<U32>:
  match words:
    case Con{word, rest}: List.append(&1, U32, both(word), calculate(rest))
    case Nil{}: Nil{}
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('glibc-sinf', args)
    cases = arguments()
    objects = glibc_sinf.objects(probe)
    native = glibc_sinf.host_is_model(probe)
    source, binary, inputs = probe.work / 'reference.c', probe.work / 'reference', probe.work / 'arguments.txt'
    source.write_text(REFERENCE.replace('SINF', glibc_sinf.SINF).replace('COSF', glibc_sinf.COSF))
    inputs.write_text(''.join(f'{x:08x}\n' for x, _ in cases))
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin', source, *objects, '-lm', '-o', binary])
    lines = probekit.run([binary, inputs]).splitlines()
    if len(lines) != len(cases):
        raise ProbeFailure('glibc-sinf: incomplete reference output')
    expected = []
    for (x, label), line in zip(cases, lines):
        sine, cosine, host_sine, host_cosine = (int(part, 16) for part in line.split())
        finite = (x >> 23) & 255 != 255
        if native and finite and (sine, cosine) != (host_sine, host_cosine):
            raise ProbeFailure(f'glibc-sinf: the host sinf/cosf differ from the model at {x:08x} ({label})')
        expected.append([1, sine, 1, cosine] if finite else [0, 0, 0, 0])

    def render(chosen, gpu):
        call = 'calculate!' if gpu else 'calculate'
        return PROGRAM + ''.join(f'    IO.print(List.show(~&1, ~U32, ~U32.show, {call}(['
                                 + ', '.join(str(x) for x, _ in chosen[start:start + LINE]) + '])))\n'
                                 for start in range(0, len(chosen), LINE))

    def parse(text, chosen):
        values = [value for line in text.splitlines() for value in json.loads(line)]
        if len(values) != 4 * len(chosen):
            raise ProbeFailure('glibc-sinf: wrong candidate output size')
        return [values[4 * i:4 * i + 4] for i in range(len(chosen))]

    lanes = probe.candidates(render, cases, batch=BATCH, parse=parse)
    probe.compare(expected, lanes, describe=lambda i: f'argument {cases[i][0]:08x} ({cases[i][1]})')
    labels = {}
    for _, label in cases:
        labels[label] = labels.get(label, 0) + 1
    probe.finish(arguments=len(cases), labels=labels, native_compared=native)


if __name__ == '__main__':
    main()
