#!/usr/bin/env python3
"""Compare M.Libm.acos64 (src/lgpl/acos.bend) with the glibc acos model.

The reference is tools/reference/glibc_acos/model.c (the glibc 2.39 x86_64
__ieee754_acos_fma variant, tools/glibc_acos.py). Arguments: random binary64
words of every exponent up to 1 and both signs, and more of them in each
interval of e_asin.c's acos (below 2^-55, 1/8, 1/4, 1/2, 3/4, 0.921875,
0.953125, 0.96875 and 1); binary32 values of [-1, 1] promoted, as stb_truetype
reaches acos(); every interval's bound with its neighbours; the first
argument of every entry of the table with its neighbours (the last of the
entry before); arguments just below 1 through every entry of the root table
and every power of two it is scaled by; the model's controls, where the FMA
and SSE2 variants differ; 1 and -1; and what is None: arguments above 1,
infinities and NaN. On a host whose own acos reproduces the controls (glibc
2.39 on an FMA/AVX2 CPU) the native function is compared too. The other
profiles answer None. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import random
import struct

import glibc_acos
import probekit
from probekit import ProbeFailure

BATCH = 256
LINE = 16
ONE = 0x3ff0000000000000
# |x| bounds of the intervals as binary64 words.
BOUNDS = (0x3c88000000000000, 0x3fc0000000000000, 0x3fd0000000000000, 0x3fe0000000000000, 0x3fe8000000000000, 0x3fed800000000000,
          0x3fee800000000000, 0x3fef000000000000, ONE)
# Arguments the other profiles must answer None for (the first of each batch).
OTHERS = 2


def bits(value):
    return struct.unpack('<Q', struct.pack('<d', value))[0]


def f32(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]


def entries():
    """The first argument of every entry of the table: the high words where an interval's index changes."""
    out = [0x3fc00000 + (j << 15) for j in range(32)] + [0x3fd00000 + (j << 14) for j in range(64)] + [0x3fe00000 + (j << 13) for j in range(120)]
    return [high << 32 for high in out]


def arguments():
    rng = random.Random(0xAC05)
    words = {}
    for exponent in range(1, 0x3ff):
        for _ in range(2 if exponent < 0x3c0 else 6):
            words.setdefault((rng.getrandbits(1) << 63) | (exponent << 52) | rng.getrandbits(52), 'random')
    for low, high in zip(BOUNDS, BOUNDS[1:]):
        for _ in range(48):
            words.setdefault((rng.getrandbits(1) << 63) | rng.randrange(low, high), 'interval')
    for _ in range(160):
        word = (rng.getrandbits(1) << 31) | rng.randrange(0x30000000, 0x3f800001)
        words.setdefault(bits(f32(word)), 'promoted-binary32')
    for bound in BOUNDS:
        for delta in (-1, 0, 1):
            for sign in (0, 1 << 63):
                words.setdefault((bound + delta) | sign, 'interval-bound')
    for index, entry in enumerate(entries()):
        for delta in (-1, 0, 1):
            words.setdefault((entry + delta) | ((index + delta) & 1) << 63, 'table-entry')
    # x = 1 - 2z: z's exponent picks the power of two, its low exponent bit and top six mantissa bits the root
    for exponent in range(7, 54):
        for step in (0, 21, 42, 63):
            z = (1.0 + (step + rng.random()) / 64.0) * 2.0 ** -exponent
            for sign in (1.0, -1.0):
                words.setdefault(bits(sign * (1.0 - 2.0 * z)), 'below-one')
    for step in range(128):
        z = (1.0 + (step % 64 + 0.5) / 64.0) * 2.0 ** (-9 - step // 64)
        words.setdefault(bits(1.0 - 2.0 * z) | (step & 1) << 63, 'root-table')
    for x, _ in glibc_acos.CONTROLS:
        words.setdefault(x, 'variant-control')
    for special in (0, 1 << 63, 1, 0x000fffffffffffff, 0x8000000000000001, ONE, ONE | 1 << 63):
        words.setdefault(special, 'special')
    for outside in (ONE + 1, (ONE + 1) | 1 << 63, bits(1.0000001), bits(-2.0), bits(1e300), 0x7ff0000000000000, 0xfff0000000000000,
                    0x7ff8000000000000, 0x7ff0000000000001):
        words.setdefault(outside, 'outside')
    return sorted(words.items())


REFERENCE = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
double MODEL_ACOS(double);
static double (*volatile host_acos)(double) = acos;
static unsigned long long word(double value) { uint64_t w; memcpy(&w, &value, 8); return (unsigned long long) w; }
int main(int argc, char **argv) {
  FILE *in = fopen(argv[1], "r");
  unsigned long long w;
  (void) argc;
  while (fscanf(in, "%llx", &w) == 1) {
    double x, m, h;
    memcpy(&x, &w, 8);
    m = MODEL_ACOS(x); h = host_acos(x);
    printf("%016llx %016llx %d\n", word(m), word(h), (int) (m != m));
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
    case Con{+high, Con{+low, rest}}: List.append(&1, U32, show(M.Libm.acos64(M.Glibc239Libm{}, M.Float64{high, low})), calculate(rest))
    case _: Nil{}
def refused(words: +List<U32>) -> List<U32>:
  match words:
    case Con{+high, Con{+low, rest}}: List.append(&1, U32, show(M.Libm.acos64(M.AppleLibm{}, M.Float64{high, low})),
      List.append(&1, U32, show(M.Libm.acos64(M.Glibc241Libm{}, M.Float64{high, low})), refused(rest)))
    case _: Nil{}
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('glibc-acos', args)
    cases = arguments()
    objects = glibc_acos.objects(probe)
    native = glibc_acos.host_is_model(probe)
    source, binary, inputs = probe.work / 'reference.c', probe.work / 'reference', probe.work / 'arguments.txt'
    source.write_text(REFERENCE.replace('MODEL_ACOS', glibc_acos.ACOS))
    inputs.write_text(''.join(f'{x:016x}\n' for x, _ in cases))
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin', source, *objects, '-lm', '-o', binary])
    lines = probekit.run([binary, inputs]).splitlines()
    if len(lines) != len(cases):
        raise ProbeFailure('glibc-acos: incomplete reference output')
    expected, answered = [], 0
    for (x, label), line in zip(cases, lines):
        model, host, nan = (int(part, 16) for part in line.split())
        inside = (x & 0x7fffffffffffffff) <= ONE
        if nan == inside:
            raise ProbeFailure(f'glibc-acos: the model answers {model:016x} at {x:016x} ({label})')
        if native and inside and model != host:
            raise ProbeFailure(f'glibc-acos: the host differs from the model at {x:016x} ({label})')
        expected.append([1, model >> 32, model & 0xffffffff] if inside else [0, 0, 0])
        answered += inside

    def words(chosen):
        return ', '.join(f'{x >> 32}, {x & 0xffffffff}' for x, _ in chosen)

    def render(chosen, gpu):
        call = 'calculate!' if gpu else 'calculate'
        return (PROGRAM + ''.join(f'    IO.print(List.show(~&1, ~U32, ~U32.show, {call}([{words(chosen[start:start + LINE])}])))\n'
                                  for start in range(0, len(chosen), LINE))
                + f'    IO.print(List.show(~&1, ~U32, ~U32.show, refused([{words(chosen[:OTHERS])}])))\n')

    def parse(text, chosen):
        values = [value for line in text.splitlines() for value in json.loads(line)]
        if len(values) != 3 * len(chosen) + 6 * min(OTHERS, len(chosen)):
            raise ProbeFailure('glibc-acos: wrong candidate output size')
        if any(values[3 * len(chosen):]):
            raise ProbeFailure('glibc-acos: a profile without a verified binary64 acos answered')
        return [values[3 * i:3 * i + 3] for i in range(len(chosen))]

    lanes = probe.candidates(render, cases, batch=BATCH, parse=parse)
    probe.compare(expected, lanes, describe=lambda i: f'argument {cases[i][0]:016x} ({cases[i][1]})')
    labels = {}
    for _, label in cases:
        labels[label] = labels.get(label, 0) + 1
    probe.finish(arguments=len(cases), answered=answered, labels=labels, native_compared=native)


if __name__ == '__main__':
    main()
