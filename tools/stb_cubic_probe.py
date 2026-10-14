#!/usr/bin/env python3
"""Compare src/stb_cubic.bend's `solve` with stb_truetype's stbtt__solve_cubic.

Reference. raylib's src/external/stb_truetype.h with its implementation,
compiled into the reference program (contraction off):
stbtt__solve_cubic(a, b, c, r) itself, on triples of floats, its
STBTT_pow, STBTT_acos and STBTT_cos bound to the C models of glibc 2.39's
x86_64 FMA variants (tools/reference/glibc_pow, glibc_acos and glibc_sin,
which must reproduce their controls; tools/glibc_pow.py, glibc_acos.py and
glibc_sin.py): what a glibc 2.39 host computes, on any host. For each
triple the reference prints the number of roots and
their bits, and what the port must make of them: one root (finite), three
(finite), three that are NaN because acos's argument came out above 1 with
everything before it finite (state 4: no root is used), or none to answer
(something on the way that is not finite: state 0).

Candidate. Cubic.solve(a, b, c): Roots{state, r0, r1, r2}.

The triples: those stbtt_GetGlyphSDF forms for a quadratic curve and a
pixel near it (b, c and d of its cubic, divided by the curve's leading
coefficient), from seeded curves of font units at a 16 px scale and pixels
around them; seeded triples of every magnitude; and the edges: zeros, a
discriminant of exactly 0, the roots 0 and 1, and triples whose discriminant
is just below 0 or about 0 (double roots and nearly double ones). A first
reference pass sorts a seeded pool into the four
kinds and the gate takes a share of each: the three-root kind, which the
example's font makes 15301 times, the most. CPU-1, CPU-2 and JavaScript
lanes.
"""
import json
import random
import struct

import glibc_acos
import glibc_pow
import glibc_sin
import probekit
from probekit import ProbeFailure

BATCH = 128
LINE = 8
SOURCE = 'src/external/stb_truetype.h'
# How many of each kind the gate keeps: one root, three, NaN roots, no answer.
KEEP = {1: 400, 3: 900, 4: 40, 0: 40}


def f32(x):
    try:
        return struct.unpack('<f', struct.pack('<f', x))[0]
    except OverflowError:
        return float('inf') if x > 0 else float('-inf')


def word(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def sdf_triple(rng):
    """b, c and d of the cubic stbtt_GetGlyphSDF solves for a curve (x0, y0)-(x1, y1)-(x2, y2) and a pixel (sx, sy), in float."""
    scale = f32(16.0 / 2048.0)
    x0, y0, x1, y1, x2, y2 = (f32(rng.randrange(-200, 1400) * scale) for _ in range(6))
    sx, sy = f32(rng.uniform(-4, 20) + 0.5), f32(rng.uniform(-4, 20) + 0.5)
    ax, ay = f32(x1 - x0), f32(y1 - y0)
    bx, by = f32(f32(x0 - f32(2 * x1)) + x2), f32(f32(y0 - f32(2 * y1)) + y2)
    mx, my = f32(x0 - sx), f32(y0 - sy)
    length = f32(f32(bx * bx) + f32(by * by))
    if length == 0.0:
        return None
    inverse = f32(1.0 / length)
    b = f32(f32(3 * f32(f32(ax * bx) + f32(ay * by))) * inverse)
    c = f32(f32(f32(2 * f32(f32(ax * ax) + f32(ay * ay))) + f32(f32(mx * bx) + f32(my * by))) * inverse)
    d = f32(f32(f32(mx * ax) + f32(my * ay)) * inverse)
    return b, c, d


def pool():
    rng = random.Random(0xC0B1C)
    out = {}
    for _ in range(30000):
        triple = sdf_triple(rng)
        if triple:
            out.setdefault(tuple(word(x) for x in triple), 'sdf')
    for _ in range(6000):
        out.setdefault(tuple(word(f32(rng.choice((-1, 1)) * rng.uniform(0.5, 2.0) * 10.0 ** rng.randrange(-6, 7))) for _ in range(3)), 'random')
    for _ in range(6000):
        # a discriminant just below 0: three nearly equal roots t, t + e, t + 2e
        t, e = rng.uniform(-1.0, 2.0), rng.uniform(0.0, 1e-3)
        r = (t, t + e, t + 2 * e)
        a = -(r[0] + r[1] + r[2])
        b = r[0] * r[1] + r[1] * r[2] + r[0] * r[2]
        c = -r[0] * r[1] * r[2]
        out.setdefault((word(f32(a)), word(f32(b)), word(f32(c))), 'near-double-root')
    for _ in range(40000):
        # a double root (or two roots very near), where rounding leaves the discriminant on either side of 0 and acos's
        # argument about 1
        t, u = rng.uniform(-1.0, 2.0), rng.uniform(-1.0, 2.0)
        e = 0.0 if rng.random() < 0.5 else 10.0 ** -rng.uniform(3, 8)
        a = -(t + (t + e) + u)
        b = t * (t + e) + (t + e) * u + t * u
        c = -t * (t + e) * u
        out.setdefault((word(f32(a)), word(f32(b)), word(f32(c))), 'double-root')
    for a, b, c in ((0.0, 0.0, 0.0), (-0.0, 0.0, -0.0), (0.0, 0.0, -1.0), (0.0, 0.0, 1.0), (-3.0, 3.0, -1.0), (-1.5, 0.5, 0.0), (0.0, -1.0, 0.0),
                    (-3.0, 2.0, 0.0), (1e30, 1e30, 1e30), (-1e-30, 1e-30, 0.0), (3e38, -3e38, 1.0)):
        out[(word(a), word(b), word(c))] = 'edge'
    for special in ((0x7f800000, 0, 0), (0, 0x7fc00000, 0), (0, 0, 0xff800000), (0x00000001, 0x80000001, 0x00000001)):
        out[special] = 'edge'
    return sorted(out.items())


REFERENCE = r'''double MODEL_POW(double, double, int *);
double MODEL_ACOS(double);
double MODEL_COS(double);
static double model_pow(double x, double y) { int refused; double value = MODEL_POW(x, y, &refused); return refused ? 0.0/0.0 : value; }
#define STBTT_pow(x, y) model_pow(x, y)
#define STBTT_acos(x) MODEL_ACOS(x)
#define STBTT_cos(x) MODEL_COS(x)
#define STB_TRUETYPE_IMPLEMENTATION
#include "@SOURCE@"
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static float real(unsigned w) { float x; memcpy(&x, &w, 4); return x; }
static unsigned bits(float x) { unsigned w; memcpy(&w, &x, 4); return w; }
static int finite(float x) { return (bits(x) & 0x7f800000u) != 0x7f800000u; }
int main(int argc, char **argv) {
  FILE *in = fopen(argv[1], "r");
  unsigned wa, wb, wc;
  (void) argc;
  while (fscanf(in, "%x %x %x", &wa, &wb, &wc) == 3) {
    float a = real(wa), b = real(wb), c = real(wc), r[3] = {0.0f, 0.0f, 0.0f};
    int num = stbtt__solve_cubic(a, b, c, r), state = 0;
    /* the solver's own first steps, to tell the NaN of acos above 1 from the other ones */
    float s = -a / 3, p = b - a*a / 3, q = a * (2*a*a - 9*b) / 27 + c, p3 = p*p*p, w = -27/p3;
    if (num == 1) state = finite(r[0]) ? 1 : 0;
    else if (finite(r[0]) && finite(r[1]) && finite(r[2])) state = 3;
    else if (finite(s) && finite(p) && finite(q) && finite(p3) && p3 < 0 && finite(w) && w > 0) {
      double argument = -sqrt(w) * q / 2;
      if (isfinite(argument) && fabs(argument) > 1) state = 4;
    }
    printf("%d %d %08x %08x %08x\n", state, num, state == 1 || state == 3 ? bits(r[0]) : 0, state == 3 ? bits(r[1]) : 0, state == 3 ? bits(r[2]) : 0);
  }
  return 0;
}
'''

PROGRAM = '''import Base
import ../../src/stb_cubic.bend as Cubic
def flt(word: U32) -> F32:
  U32{bits} = word
  F32{bits}
def show(roots: Cubic.Roots) -> List<U32>:
  Cubic.Roots{state, r0, r1, r2} = roots
  [state, F32.bits(r0), F32.bits(r1), F32.bits(r2)]
def calculate(words: +List<U32>) -> List<U32>:
  match words:
    case Con{+a, Con{+b, Con{+c, rest}}}: List.append(&1, U32, show(Cubic.solve(flt(a), flt(b), flt(c))), calculate(rest))
    case _: Nil{}
def main() -> IO(Unit):
  do IO<Unit>:
'''


def reference(probe, raylib, triples, name, objects):
    source, binary, inputs = probe.work / f'{name}.c', probe.work / name, probe.work / f'{name}.txt'
    source.write_text(REFERENCE.replace('@SOURCE@', str(raylib / SOURCE)).replace('MODEL_POW', glibc_pow.POW).replace('MODEL_ACOS', glibc_acos.ACOS)
                      .replace('MODEL_COS', glibc_sin.COS))
    inputs.write_text(''.join(f'{a:08x} {b:08x} {c:08x}\n' for a, b, c in triples))
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin', '-w', source, *objects, '-lm', '-o', binary])
    rows = [[int(part, 16) for part in line.split()] for line in probekit.run([binary, inputs]).splitlines()]
    if len(rows) != len(triples):
        raise ProbeFailure(f'stb-cubic: the reference printed {len(rows)} rows for {len(triples)} triples')
    return rows


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('stb-cubic', args)
    objects = glibc_acos.objects(probe) + glibc_pow.objects(probe) + glibc_sin.objects(probe)
    everything = pool()
    rows = reference(probe, args.raylib_source.resolve(), [triple for triple, _ in everything], 'pool', objects)
    kinds = {state: [] for state in KEEP}
    for (triple, label), (state, num, r0, r1, r2) in zip(everything, rows):
        if label == 'edge' or len(kinds[state]) < KEEP[state]:
            kinds[state].append((triple, label, [state, r0, r1, r2]))
    counts = {state: len(found) for state, found in kinds.items()}
    if counts[3] < KEEP[3] or counts[1] < KEEP[1] or counts[4] < 5 or counts[0] < 5:
        raise ProbeFailure(f'stb-cubic: the pool has too few of a kind: {counts}')
    items = sorted((item for found in kinds.values() for item in found), key=lambda item: item[0])
    expected = [row for _, _, row in items]

    def render(chosen, gpu):
        call = 'calculate!' if gpu else 'calculate'
        return PROGRAM + ''.join(f'    IO.print(List.show(~&1, ~U32, ~U32.show, {call}([{", ".join(str(w) for triple, _, _ in chosen[start:start + LINE] for w in triple)}])))\n'
                                 for start in range(0, len(chosen), LINE))

    def parse(text, chosen):
        values = [value for line in text.splitlines() for value in json.loads(line)]
        if len(values) != 4 * len(chosen):
            raise ProbeFailure('stb-cubic: wrong candidate output size')
        return [values[4 * i:4 * i + 4] for i in range(len(chosen))]

    lanes = probe.candidates(render, items, batch=BATCH, parse=parse, timeout=1700)
    probe.compare(expected, lanes, describe=lambda i: '%s (%s)' % (' '.join(f'{w:08x}' for w in items[i][0]), items[i][1]))
    labels = {}
    for _, label, _ in items:
        labels[label] = labels.get(label, 0) + 1
    probe.finish(triples=len(items), pool=len(everything), kinds={str(state): count for state, count in counts.items()}, labels=labels)


if __name__ == '__main__':
    main()
