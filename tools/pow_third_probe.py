#!/usr/bin/env python3
"""Compare src/power64.bend's `third` with the glibc pow model.

`third(bits)` is (float) pow((double) x, (double) (1.0f/3.0f)), the cube
root stb_truetype's cubic solver takes of a float. The reference is
tools/reference/glibc_pow/model.c (the glibc 2.39 x86_64 __pow_fma variant,
tools/glibc_pow.py), narrowed to float as the C cast narrows it. Arguments:
random floats of every exponent, the subnormal ones too; a float in each of
the 128 intervals of the logarithm's table at three exponents; 1 and its
neighbours (below 2^-54 the exponential answers 1 + x); the cubes of 1 to
40 and the powers of two; the smallest and the largest floats; the model's
controls, where the FMA and SSE2 variants' doubles differ; the zeros (+0);
and what is None: negative floats, the infinities and NaN. On a host whose
own pow reproduces the controls (glibc 2.39 on an FMA/AVX2 CPU) the native
function is compared too. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import random
import struct

import glibc_pow
import probekit
from probekit import ProbeFailure

BATCH = 256
LINE = 16
ONE = 0x3f800000
INFINITY = 0x7f800000


def bits(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def arguments():
    rng = random.Random(0x3D)
    words = {}
    for exponent in range(0, 255):
        for _ in range(8):
            words.setdefault((exponent << 23) | rng.getrandbits(23), 'random')
    words.pop(0, None)
    for exponent in (1, 127, 200):
        for interval in range(128):
            words.setdefault((exponent << 23) | (interval << 16) | rng.getrandbits(16), 'table-interval')
    for delta in range(-8, 9):
        words.setdefault(ONE + delta, 'near-one')
    for n in range(1, 41):
        words.setdefault(bits(float(n ** 3)), 'cube')
    for exponent in range(-149, 128):
        words.setdefault(bits(2.0 ** exponent), 'power-of-two')
    for extreme in (1, 2, 0x007fffff, 0x00800000, 0x00800001, 0x7f7fffff, 0x7f7ffffe):
        words.setdefault(extreme, 'extreme')
    for x, _, _ in glibc_pow.CONTROLS:
        words.setdefault(x, 'variant-control')
    for zero in (0, 0x80000000):
        words[zero] = 'zero'
    for refused in (0x80000001, bits(-1.0), bits(-8.0), 0xff7fffff, INFINITY, 0xff800000, 0x7fc00000, 0x7f800001, 0xffc00000):
        words[refused] = 'refused'
    return sorted(words.items())


REFERENCE = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
double MODEL_POW(double, double, int *);
static double (*volatile host_pow)(double, double) = pow;
static unsigned word(float value) { uint32_t w; memcpy(&w, &value, 4); return (unsigned) w; }
int main(int argc, char **argv) {
  FILE *in = fopen(argv[1], "r");
  unsigned w;
  const double third = (double) (1.0f/3.0f);
  (void) argc;
  while (fscanf(in, "%x", &w) == 1) {
    uint32_t bits = (uint32_t) w;
    float x;
    int refused;
    double m;
    memcpy(&x, &bits, 4);
    m = MODEL_POW((double) x, third, &refused);
    printf("%08x %08x %d\n", word((float) m), word((float) host_pow((double) x, third)), refused);
  }
  return 0;
}
'''

PROGRAM = '''import Base
import ../../src/power64.bend as P
def show(value: Maybe<U32>) -> List<U32>:
  match value:
    case None{}: [0, 0]
    case Some{bits}: [1, bits]
def calculate(words: +List<U32>) -> List<U32>:
  match words:
    case Con{+bits, rest}: List.append(&1, U32, show(P.third(bits)), calculate(rest))
    case Nil{}: Nil{}
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('pow-third', args)
    cases = arguments()
    objects = glibc_pow.objects(probe)
    native = glibc_pow.host_is_model(probe)
    source, binary, inputs = probe.work / 'reference.c', probe.work / 'reference', probe.work / 'arguments.txt'
    source.write_text(REFERENCE.replace('MODEL_POW', glibc_pow.POW))
    inputs.write_text(''.join(f'{x:08x}\n' for x, _ in cases))
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin', source, *objects, '-lm', '-o', binary])
    lines = probekit.run([binary, inputs]).splitlines()
    if len(lines) != len(cases):
        raise ProbeFailure('pow-third: incomplete reference output')
    expected, answered = [], 0
    for (x, label), line in zip(cases, lines):
        model, host, refused = (int(part, 16) for part in line.split())
        inside = x & 0x7fffffff == 0 or x < INFINITY
        if refused:
            raise ProbeFailure(f'pow-third: the model has no answer at {x:08x} ({label})')
        if (label in ('zero', 'refused')) != (not inside or x & 0x7fffffff == 0):
            raise ProbeFailure(f'pow-third: {x:08x} is not {label}')
        if native and inside and model != host:
            raise ProbeFailure(f'pow-third: the host differs from the model at {x:08x} ({label})')
        if label == 'zero' and model != 0:
            raise ProbeFailure(f'pow-third: the model answers {model:08x} for a zero')
        expected.append([1, model] if inside else [0, 0])
        answered += inside
    controls = {x: narrowed for x, _, narrowed in glibc_pow.CONTROLS}
    if any(row[1] != controls[x] for (x, _), row in zip(cases, expected) if x in controls):
        raise ProbeFailure('pow-third: the model does not narrow a control to its recorded float')

    def render(chosen, gpu):
        call = 'calculate!' if gpu else 'calculate'
        return PROGRAM + ''.join(f'    IO.print(List.show(~&1, ~U32, ~U32.show, {call}([{", ".join(str(x) for x, _ in chosen[start:start + LINE])}])))\n'
                                 for start in range(0, len(chosen), LINE))

    def parse(text, chosen):
        values = [value for line in text.splitlines() for value in json.loads(line)]
        if len(values) != 2 * len(chosen):
            raise ProbeFailure('pow-third: wrong candidate output size')
        return [values[2 * i:2 * i + 2] for i in range(len(chosen))]

    lanes = probe.candidates(render, cases, batch=BATCH, parse=parse)
    probe.compare(expected, lanes, describe=lambda i: f'float {cases[i][0]:08x} ({cases[i][1]})')
    labels = {}
    for _, label in cases:
        labels[label] = labels.get(label, 0) + 1
    probe.finish(arguments=len(cases), answered=answered, labels=labels, native_compared=native)


if __name__ == '__main__':
    main()
