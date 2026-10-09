#!/usr/bin/env python3
"""Compare M.Libm.tan's glibc kernel (src/lgpl/tan.bend) with the glibc tan model.

The reference is tools/reference/glibc_tan/model.c (the glibc 2.39/2.41 x86_64
__tan_fma variant, tools/glibc_tan.py), which equals the native function on
every argument MatrixPerspective and BeginMode3D can pass (docs/PERSPECTIVE.md).
Arguments: for both of raylib's argument sets (perspective: (double)g*0.5;
begin3d: ((double)fovy*0.5)*(double)DEG2RAD, for binary32 g and fovy), random
binary32 words of every exponent and sign, every argument of the exhaustive
results where the FMA and SSE2 variants differ or glibc is not correctly
rounded, the region boundaries of s_tan.c, signed zeros, the largest finite
values and infinities and NaN (None). On a host whose own tan passes the
controls (glibc on an FMA/AVX2 CPU) the native function is compared too.
CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import random
import struct

import glibc_tan
import probekit
from probekit import ROOT, ProbeFailure

RESULTS = ROOT / 'tools/reference/glibc_tan/results'
DEG2RAD = struct.unpack('<f', struct.pack('<I', 0x3c8efa35))[0]
BATCH = 512
LINE = 32

# |x| bounds of s_tan.c's regions (g1..g5 of utan.h) and of gy2, as words.
BOUNDS = (0x3e4b096c00000000, 0x3faf212d00000000, 0x3fe92f1a00000000, 0x4039000000000000, 0x4197d78400000000)


def f32(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]


def bits(value):
    return struct.unpack('<Q', struct.pack('<d', value))[0]


def argument(kind, word):
    g = f32(word)
    return bits(g * 0.5) if kind == 'perspective' else bits((g * 0.5) * DEG2RAD)


def arguments():
    rng = random.Random(0x7A4)
    words = {}
    for kind in ('perspective', 'begin3d'):
        for exponent in range(255):
            for _ in range(3):
                word = (rng.getrandbits(1) << 31) | (exponent << 23) | rng.getrandbits(23)
                words.setdefault(argument(kind, word), f'{kind}-random')
        for name in sorted(RESULTS.glob(f'{kind}-fma.json')):
            data = json.loads(name.read_text())
            for label in ('contraction_words', 'misrounded_words'):
                for word in data[label]:
                    words.setdefault(argument(kind, int(word, 16)), f'{kind}-{label}')
        for word in (0x42340000, 0x42b40000, 0x43340000, 0x3f800000, 0x7f7fffff, 0x00000001, 0x80000001):
            words.setdefault(argument(kind, word), f'{kind}-special')
    for bound in BOUNDS:
        for delta in (-1, 0, 1):
            for sign in (0, 1 << 63):
                words.setdefault((bound + delta) | sign, 'region-boundary')
    for special in (0, 1 << 63, 0x7fefffffffffffff, 0xffefffffffffffff, 0x0010000000000000, 0x7ff0000000000000,
                    0xfff0000000000000, 0x7ff8000000000000):
        words.setdefault(special, 'special')
    return sorted(words.items())


REFERENCE = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
double SYMBOL(double);
static double (*volatile host_tan)(double) = tan;
int main(int argc, char **argv) {
  FILE *in = fopen(argv[1], "r");
  unsigned long long word;
  while (fscanf(in, "%llx", &word) == 1) {
    double x, y, z; uint64_t a, b;
    memcpy(&x, &word, 8);
    y = SYMBOL(x); z = host_tan(x);
    memcpy(&a, &y, 8); memcpy(&b, &z, 8);
    printf("%016llx %016llx\n", (unsigned long long) a, (unsigned long long) b);
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
    case Con{high, Con{low, rest}}: List.append(&1, U32, show(M.Libm.tan(M.Glibc239Libm{}, M.Float64{high, low})), calculate(rest))
    case _: Nil{}
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('glibc-tan', args)
    cases = arguments()
    objects = glibc_tan.objects(probe)
    native = glibc_tan.host_is_model(probe)
    source, binary, inputs = probe.work / 'reference.c', probe.work / 'reference', probe.work / 'arguments.txt'
    source.write_text(REFERENCE.replace('SYMBOL', glibc_tan.SYMBOL))
    inputs.write_text(''.join(f'{x:016x}\n' for x, _ in cases))
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin', source, *objects, '-lm', '-o', binary])
    lines = probekit.run([binary, inputs]).splitlines()
    if len(lines) != len(cases):
        raise ProbeFailure('glibc-tan: incomplete reference output')
    expected = []
    for (x, label), line in zip(cases, lines):
        model, host = (int(part, 16) for part in line.split())
        if native and model != host:
            raise ProbeFailure(f'glibc-tan: the host tan differs from the model at {x:016x} ({label})')
        finite = (x >> 52) & 2047 != 2047
        expected.append([1, model >> 32, model & 0xffffffff] if finite else [0, 0, 0])

    def render(chosen, gpu):
        call = 'calculate!' if gpu else 'calculate'
        return PROGRAM + ''.join(f'    IO.print(List.show(~&1, ~U32, ~U32.show, {call}(['
                                 + ', '.join(f'{x >> 32}, {x & 0xffffffff}' for x, _ in chosen[start:start + LINE]) + '])))\n'
                                 for start in range(0, len(chosen), LINE))

    def parse(text, chosen):
        values = [value for line in text.splitlines() for value in json.loads(line)]
        if len(values) != 3 * len(chosen):
            raise ProbeFailure('glibc-tan: wrong candidate output size')
        return [values[3 * i:3 * i + 3] for i in range(len(chosen))]

    lanes = probe.candidates(render, cases, batch=BATCH, parse=parse)
    probe.compare(expected, lanes, describe=lambda i: f'argument {cases[i][0]:016x} ({cases[i][1]})')
    labels = {}
    for _, label in cases:
        labels[label] = labels.get(label, 0) + 1
    probe.finish(arguments=len(cases), labels=labels, native_compared=native)


if __name__ == '__main__':
    main()
