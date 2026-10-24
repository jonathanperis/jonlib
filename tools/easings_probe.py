#!/usr/bin/env python3
"""Compare Joneasings with reasings.h.

The native reference compiles raylib's examples/shapes/reasings.h with
-ffp-contract=off against the host libm and prints the 28 Ease* functions'
words for each (t, b, c, d) of the corpus: durations from 0.001 to 1000,
times at, inside and outside [0, d] (the edges the functions test, t == 0,
t == d and t == d/2, and floats on either side of EaseBounceOut's bounds),
and positive, negative and zero changes. Joneasings runs the `_for` forms
under the host's libm profile (tools/conformance.py gradient_reference): a
sine, exponential or elastic easing whose sinf/cosf argument or powf(2, x)
exponent the profile does not verify must answer None (the expected value is
computed from the same F32 steps here), and every other value must have the
reference's bits. A NaN result (sqrtf of a negative, 0/0) is compared as
NaN: its sign and payload are the platform's. CPU-1, CPU-2 and JavaScript
lanes.
"""
import math
import random
import struct

from conformance import gradient_reference
import frame_probe as fp
import pow2_probe
import probekit
from probekit import ProbeFailure

NAMES = ['LinearNone', 'LinearIn', 'LinearOut', 'LinearInOut', 'SineIn', 'SineOut', 'SineInOut', 'CircIn', 'CircOut',
         'CircInOut', 'CubicIn', 'CubicOut', 'CubicInOut', 'QuadIn', 'QuadOut', 'QuadInOut', 'ExpoIn', 'ExpoOut',
         'ExpoInOut', 'BackIn', 'BackOut', 'BackInOut', 'BounceOut', 'BounceIn', 'BounceInOut', 'ElasticIn',
         'ElasticOut', 'ElasticInOut']
PROFILED = {'SineIn', 'SineOut', 'SineInOut', 'ExpoIn', 'ExpoOut', 'ExpoInOut', 'ElasticIn', 'ElasticOut', 'ElasticInOut'}


def bend_name(name):
    """EaseSineInOut -> Ease.sine_in_out(_for)."""
    snake = ''.join('_' + ch.lower() if ch.isupper() else ch for ch in name).lstrip('_')
    return f'Ease.{snake}_for' if name in PROFILED else f'Ease.{snake}'


f32 = fp.f32
PI = fp.f32(math.pi)


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def from_word(bits):
    return struct.unpack('<f', struct.pack('<I', bits))[0]


def next_float(value, up):
    bits = word(value)
    if value == 0.0:
        return from_word(1) if up else -from_word(1)
    return from_word(bits + 1 if (value > 0) == up else bits - 1)


def trig_ok(libm, arg):
    return fp.accepted(libm, arg)


def pow_ok(libm, y):
    bits = word(y)
    if libm == 'AppleLibm':
        return bits in pow2_probe.apple_answers()
    return pow2_probe.inside(bits)


def accepted(libm, name, t, b, c, d):
    """Whether the profile verifies every sinf/cosf/powf(2, x) the easing reaches (C's F32 steps)."""
    half_pi = f32(PI / 2.0)
    if name == 'SineIn' or name == 'SineOut':
        return trig_ok(libm, f32(f32(t / d) * half_pi))
    if name == 'SineInOut':
        return trig_ok(libm, f32(f32(PI * t) / d))
    if name == 'ExpoIn':
        return t == 0.0 or pow_ok(libm, f32(10.0 * f32(f32(t / d) - 1.0)))
    if name == 'ExpoOut':
        return t == d or pow_ok(libm, f32(f32(-10.0 * t) / d))
    if name == 'ExpoInOut':
        if t == 0.0 or t == d:
            return True
        u = f32(t / f32(d / 2.0))
        return pow_ok(libm, f32(10.0 * f32(u - 1.0)) if u < 1.0 else f32(-10.0 * f32(u - 1.0)))
    if name in ('ElasticIn', 'ElasticOut', 'ElasticInOut'):
        if t == 0.0:
            return True
        if name == 'ElasticInOut':
            u = f32(t / f32(d / 2.0))
            if u == 2.0:
                return True
            # 0.3f*1.5f is two F32 literals. A binary64 product rounds one ulp away.
            p = f32(d * f32(f32(0.3) * f32(1.5)))
            v = f32(u - 1.0)
            exponent = f32(10.0 * v) if u < 1.0 else f32(-10.0 * v)
        else:
            u = f32(t / d)
            if u == 1.0:
                return True
            p = f32(d * f32(0.3))
            v = f32(u - 1.0) if name == 'ElasticIn' else u
            exponent = f32(10.0 * v) if name == 'ElasticIn' else f32(-10.0 * v)
        arg = f32(f32(f32(f32(v * d) - f32(p / 4.0)) * f32(2.0 * PI)) / p)
        return pow_ok(libm, exponent) and trig_ok(libm, arg)
    return True


def corpus():
    rng = random.Random(0xEA5E)
    items = set()
    durations = [1.0, 2.0, 3.0, 7.0, 60.0, 100.0, 120.0, 160.0, 0.5, 0.001, 1000.0, 33.25]
    changes = [(0.0, 1.0), (100.0, 530.0), (-100.0, 340.0), (1.0, -1.0), (5.5, 0.0), (-20.0, -250.5)]
    for d in durations:
        d = f32(d)
        times = [0.0, d, f32(d / 2.0), -1.0, f32(d + 1.0), f32(d * 2.0)] + [f32(d * k / 16.0) for k in range(1, 16)]
        for t in times:
            b, c = rng.choice(changes)
            items.add((f32(t), f32(b), f32(c), d))
    # EaseBounceOut's bounds (1/2.75, 2/2.75 and the double 2.5/2.75) with d = 1, and the floats beside them.
    for bound in (f32(1.0 / 2.75), f32(2.0 / 2.75), f32(2.5 / 2.75), f32(0.5)):
        for t in (bound, next_float(bound, True), next_float(bound, False)):
            items.add((t, 0.0, 1.0, 1.0))
    for _ in range(120):
        d = f32(rng.choice((rng.uniform(0.01, 10.0), rng.uniform(10.0, 500.0))))
        t = f32(rng.uniform(-0.25, 1.25) * d)
        items.add((t, f32(rng.uniform(-500.0, 500.0)), f32(rng.uniform(-800.0, 800.0)), d))
    return sorted(items)


NATIVE = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "REASINGS"
static uint32_t bits(float v) { uint32_t b; memcpy(&b, &v, 4); return b; }
static void out(float v) { if (isnan(v)) printf(" nan"); else printf(" %u", bits(v)); }
static const uint32_t words[] = {WORDS};
int main(void) {
  for (unsigned i = 0; i < sizeof words / sizeof words[0]; i += 4) {
    float t, b, c, d;
    memcpy(&t, &words[i], 4); memcpy(&b, &words[i + 1], 4); memcpy(&c, &words[i + 2], 4); memcpy(&d, &words[i + 3], 4);
CALLS    printf("\n");
  }
  return 0;
}
'''

PROGRAM = '''import Base
import ../../jonmath.bend as M
import ../../joneasings.bend as E
def f(+w: U32) -> F32:
  U32{x} = w
  F32{x}
def word(+v: F32) -> String:
  Bool.pick(String, F32.is_ne(v, v), "nan", U32.show(F32.bits(v)))
def maybe(v: Maybe<F32>) -> String:
  match v:
    case None{}: "null"
    case Some{+x}: word(x)
def row(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> String:
  ROW
def main() -> IO(Unit):
  do IO<Unit>:
LINES    IO.print("done")
'''


def render(libm):
    def build(items, gpu):
        calls = []
        for name in NAMES:
            call = f'E.{bend_name(name)}(' + ('libm, ' if name in PROFILED else '') + 't, b, c, d)'
            calls.append(f'maybe({call})' if name in PROFILED else f'word({call})')
        row = ' ++ " " ++ '.join(calls)
        lines = ''.join(f'    IO.print(row(M.{libm}{{}}, f({word(t)}), f({word(b)}), f({word(c)}), f({word(d)})))\n' for t, b, c, d in items)
        return PROGRAM.replace('ROW', row).replace('LINES', lines)
    return build


def parse(text, items):
    lines = [line for line in text.split('\n') if line.strip()]
    if not lines or lines[-1] != 'done' or len(lines) != len(items) + 1:
        raise ProbeFailure(f'easings: the candidate printed {len(lines)} lines for {len(items)} samples: {text[-300:]!r}')
    return [line.split(' ') for line in lines[:-1]]


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('easings', args)
    libm = gradient_reference()
    items = corpus()
    header = args.raylib_source / 'examples' / 'shapes' / 'reasings.h'
    calls = ''.join(f'    out(Ease{name}(t, b, c, d));\n' for name in NAMES)
    words = ', '.join(f'{word(v)}u' for item in items for v in item)
    text = probe.native(NATIVE.replace('REASINGS', str(header)).replace('CALLS', calls).replace('WORDS', words),
                        'reference', extra_flags=('-ffp-contract=off',), link_raylib=False)
    native = [line.split() for line in text.splitlines()]
    if len(native) != len(items) or any(len(row) != len(NAMES) for row in native):
        raise ProbeFailure('easings: incomplete native output')
    expected, refused = [], 0
    for item, row in zip(items, native):
        values = []
        for name, value in zip(NAMES, row):
            if name in PROFILED and not accepted(libm, name, *item):
                values.append('null')
                refused += 1
            else:
                values.append(value)
        expected.append(values)
    lanes = probe.candidates(render(libm), items, batch=60, parse=parse)
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: f'(t, b, c, d) = {items[i]}')
    probe.finish(samples=len(items), functions=len(NAMES), values=len(items) * len(NAMES), refused=refused, libm=libm,
                 nan=sum(v == 'nan' for row in expected for v in row))


if __name__ == '__main__':
    main()
