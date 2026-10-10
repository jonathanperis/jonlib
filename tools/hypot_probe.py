#!/usr/bin/env python3
"""Compare M.Libm.hypot_within with its model and the host's hypot.

M.Libm.hypot_within(x, y, r) says whether C's hypot(x, y) <= r for binary32
values promoted to binary64, wherever every faithful hypot (a result that is
one of the two doubles around the exact value) gives the same answer:

- `exact` is that contract in rational arithmetic: True for an exact
  x*x + y*y <= r*r, False from the square of the double after r on, None
  between them and for a NaN or an infinity;
- `kernel` is what src/hypot.bend computes with one rounding per operation
  (Python's floats are binary64): its None band is a little wider (up to
  r*r*(1 + 2^-50)), and it refuses magnitudes from 2^64 on.

The candidate must equal `kernel` on every case; `kernel` must never
contradict `exact`; and the host's hypot(x, y) <= r (the arguments read
through volatile floats, so nothing is folded) must agree wherever the kernel
answers. The cases cover exact Pythagorean triples and their neighbours, sums
that round onto r*r from either side (found by a deterministic search), the
band, zeros and signs, the refused magnitudes and non-finite values, and
points around circles of the radii the examples use. CPU-1, CPU-2 and
JavaScript lanes.
"""
from fractions import Fraction
import json
import math
import struct

import probekit
from probekit import ProbeFailure

LIMIT = 2.0 ** 64
MARGIN = 2.0 ** -50

NATIVE = r'''#include <math.h>
#include <stdio.h>
#include <string.h>
static const unsigned words[][3] = {WORDS};
int main(void) {
  for (unsigned i = 0; i < sizeof words / sizeof words[0]; i++) {
    volatile float x, y, r;
    float a, b, c;
    memcpy(&a, &words[i][0], 4); memcpy(&b, &words[i][1], 4); memcpy(&c, &words[i][2], 4);
    x = a; y = b; r = c;
    printf("%d\n", hypot(x, y) <= r);
  }
  return 0;
}
'''

PROGRAM = '''import Base
import ../../jonmath.bend as M
def show(value: Maybe<Bool>) -> U32:
  match value:
    case None{}: 0
    case Some{inside}: Bool.pick(U32, inside, 2, 1)
def one(+x: U32, +y: U32, +r: U32) -> U32:
  U32{a} = x
  U32{b} = y
  U32{c} = r
  show(M.Libm.hypot_within(F32{a}, F32{b}, F32{c}))
def main() -> IO(Unit):
  IO.print(List.show(~&1, ~U32, ~U32.show, [CALLS]))
'''


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def number(bits):
    return struct.unpack('<f', struct.pack('<I', bits))[0]


def finite(bits):
    return (bits >> 23) & 0xFF != 0xFF


def exact(x, y, r):
    """The contract for three binary32 words: True or False where every faithful hypot agrees, else None."""
    if not (finite(x) and finite(y) and finite(r)):
        return None
    fx, fy, fr = (Fraction(number(bits)) for bits in (x, y, r))
    if fr < 0:
        return False
    total = fx * fx + fy * fy
    if total <= fr * fr:
        return True
    after = Fraction(math.nextafter(number(r), math.inf))
    return False if total >= after * after else None


def kernel(x, y, r):
    """What src/hypot.bend answers: each operation one binary64 rounding."""
    if not (finite(x) and finite(y) and finite(r)):
        return None
    if r > 0x80000000:
        return False
    a, b, c = (abs(number(bits)) for bits in (x, y, r))
    if max(a, b, c) >= LIMIT:
        return None
    x2, y2, r2 = a * a, b * b, c * c
    total = x2 + y2
    if total < r2:
        return True
    if total == r2:
        return True if min(x2, y2) - (total - max(x2, y2)) <= 0 else None
    return False if total >= r2 + r2 * MARGIN else None


def stepped(bits, steps):
    """The binary32 word `steps` values after a positive one."""
    return bits + steps


def rounded_onto():
    """Triples whose rounded sum of squares equals r*r: four below it, four above (the band), by a fixed search."""
    below, above = [], []
    state = 20240607
    while len(below) < 4 or len(above) < 4:
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        r = word(20.0 + (state >> 8) % 4096 / 128.0) + (state & 0xFF)
        y = r - 1 - (state >> 28)
        fr, fy = Fraction(number(r)), Fraction(number(y))
        x = word(math.sqrt(float(fr * fr - fy * fy)))
        for candidate in (x - 1, x, x + 1):
            a, b, c = number(candidate), number(y), number(r)
            if a * a + b * b == c * c:
                side = Fraction(a) ** 2 + Fraction(b) ** 2 - Fraction(c) ** 2
                if side < 0 and len(below) < 4:
                    below.append((candidate, y, r))
                if side > 0 and len(above) < 4:
                    above.append((candidate, y, r))
    return below + above


def cases():
    f = word
    out = [(f(3.0), f(4.0), f(5.0)), (f(3.0), f(4.0), f(5.0) - 1), (f(3.0), f(4.0), f(5.0) + 1), (f(-3.0), f(4.0), f(5.0)), (f(4.0), f(-3.0), f(5.0)),
           (f(24.0), f(32.0), f(40.0)), (f(24.0) + 1, f(32.0), f(40.0)), (f(24.0) - 1, f(32.0), f(40.0)), (f(4.0), f(4.0), f(5.0)), (f(0.5), f(0.5), f(1.0)),
           (0, 0, 0), (0, 0, 0x80000000), (0x80000000, 0, 0), (0, 0, f(1.0)), (f(1.0), 0, 0), (f(1.0), 0, 0x80000000), (1, 0, 0), (0, 1, 1), (1, 1, 1), (1, 1, 2),
           (f(1.0), f(1.0), f(-1.0)), (0, 0, f(-1.0)), (0, 0, 0x80000001), (f(1e30), f(1.0), f(-1.0)), (f(40.0), 0, f(40.0)), (0, f(40.0), f(40.0)),
           (f(1e-10), f(40.0), f(40.0)), (f(1e-3), f(40.0), f(40.0)), (f(1e-30), f(1.0), f(1.0)), (1, f(1.0), f(1.0)), (f(1e-6), f(40.0), f(40.0)),
           (f(40.0), f(1e-5), f(40.0)), (f(40.0), f(3e-6), f(40.0)), (f(40.0), f(2e-6), f(40.0)), (f(40.0), f(1e-6), f(40.0)),
           (f(2.0 ** 63), 0, f(2.0 ** 63)), (f(2.0 ** 63), f(2.0 ** 63), f(2.0 ** 63)), (f(2.0 ** 64), 0, f(2.0 ** 64)), (0, 0, f(2.0 ** 64)), (f(1e20), 0, f(1.0)),
           (f(1.0), f(1e20), f(1.0)), (0x7F7FFFFF, 0, 0x7F7FFFFF), (0x7F800000, 0, f(1.0)), (0, 0xFF800000, f(1.0)), (f(1.0), f(1.0), 0x7F800000),
           (0x7FC00000, 0, f(1.0)), (0, 0, 0x7FC00000), (0x7F800000, 0, f(-1.0)), (0, 0, 0xFF800000), (0x007FFFFF, 0x00800000, 0x00800000), (0x00800000, 0, 0x00800000)]
    out += rounded_onto()
    # A press around balls of the examples' radii: integer mouse offsets, and points on the circle moved by a few binary32 steps.
    for radius in (20.0, 37.0, 40.0, 50.0):
        for dx, dy in ((0, int(radius)), (int(radius), 0), (12, 16), (-28, 28), (29, -28), (15, 36), (-21, -34)):
            out.append((f(float(dx)), f(float(dy)), f(radius)))
    state = 977
    for index in range(120):
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        radius = 20.0 + (state >> 8) % 3000 / 100.0
        angle = (state >> 4) % 6283 / 1000.0
        x, y = f(radius * math.cos(angle)), f(radius * math.sin(angle))
        out.append((x + (index % 5 - 2 if x & 0x7FFFFFFF > 2 else 0), y, f(radius)))
    return out


CODE = {None: 0, False: 1, True: 2}


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('hypot', args)
    chosen = cases()
    expected = [CODE[kernel(*case)] for case in chosen]
    for case, value in zip(chosen, expected):
        contract = CODE[exact(*case)]
        if value and value != contract:
            raise ProbeFailure(f'hypot: the kernel answers {value} for {case} where the contract is {contract}')
    native = probe.native(NATIVE.replace('WORDS', ', '.join('{%du, %du, %du}' % case for case in chosen)), link_raylib=False).split()
    if len(native) != len(chosen):
        raise ProbeFailure('hypot: incomplete native output')
    for case, value, host in zip(chosen, expected, native):
        if value and value != int(host) + 1:
            raise ProbeFailure(f'hypot: the host answers {host} for {case}, the kernel {value}')

    def render(selected, gpu):
        return PROGRAM.replace('CALLS', ', '.join('one(%d, %d, %d)' % case for case in selected))

    def parse(text, selected):
        values = [value for line in text.splitlines() if line.strip() for value in json.loads(line)]
        if len(values) != len(selected):
            raise ProbeFailure('hypot: wrong candidate output size')
        return values

    probe.compare(expected, probe.candidates(render, chosen, batch=len(chosen), parse=parse), describe=lambda i: f'hypot{chosen[i]}')
    probe.finish(cases=len(chosen), inside=expected.count(2), outside=expected.count(1), refused=expected.count(0),
                 contract_decided=sum(1 for case in chosen if exact(*case) is not None))


if __name__ == '__main__':
    main()
