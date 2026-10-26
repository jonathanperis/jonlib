#!/usr/bin/env python3
"""Compare CheckCollisionPointPoly on exceptional and subnormal inputs.

The crossing test is (j - i) * (point - i) / (j - i) + i: a multiply, a
divide and an add. The pinned Release library keeps those three operations
(no fused multiply-add). Fewer than three vertices is false. Every Boolean
is compared on CPU-1, CPU-2 and JavaScript.
"""
import hashlib
import json

import probekit
from probekit import ProbeFailure

# Signed zeros, one, a fraction, the 2^24 boundary, a subnormal, the least
# normal, the largest finite value, both infinities and a quiet NaN.
EDGE = (
    0x00000000, 0x80000000,
    0x3f800000, 0xbf800000,
    0x3fc00000, 0x4b800000,
    0x00000001, 0x00800000,
    0x7f7fffff,
    0x7f800000, 0xff800000,
    0x7fc00000,
)
ZERO, ONE, TWO = 0x00000000, 0x3f800000, 0x40000000
QUARTER, HALF = 0x3e800000, 0x3f000000
NEG = 0xbf800000


def anchors():
    """(point x,y), polygon vertices) for triangles, quads and short lists."""
    unit = ((ZERO, ZERO), (ONE, ZERO), (ZERO, ONE))
    square = ((ZERO, ZERO), (ONE, ZERO), (ONE, ONE), (ZERO, ONE))
    return (
        ((QUARTER, QUARTER), unit),
        ((TWO, TWO), unit),
        ((ZERO, ZERO), unit),
        ((QUARTER, QUARTER), ((ZERO, ZERO), (ZERO, ONE), (ONE, ZERO))),
        ((ZERO, ZERO), ((ZERO, ZERO), (ZERO, ZERO), (ZERO, ZERO))),
        ((HALF, HALF), square),
        ((TWO, HALF), square),
        ((HALF, HALF), ((ZERO, ZERO), (ONE, ONE), (ONE, ZERO), (ZERO, ONE))),
        ((ZERO, ZERO), ((ZERO, ZERO), (ZERO, ZERO), (ZERO, ZERO), (ZERO, ZERO))),
        ((ONE, ONE), ()),
        ((ONE, ONE), ((ZERO, ZERO),)),
        ((ONE, ONE), ((ZERO, ZERO), (ONE, ONE))),
        ((ZERO, ZERO), ((NEG, NEG), (ONE, TWO))),
    )


def flatten(point, poly):
    return point + tuple(coord for vertex in poly for coord in vertex)


def unflatten(width, values):
    point = (values[0], values[1])
    poly = tuple((values[i], values[i + 1]) for i in range(2, width, 2))
    return point, poly


def cases():
    rows = []
    seen = set()

    def add(point, poly):
        key = (point, poly)
        if key not in seen:
            seen.add(key)
            rows.append(key)

    for point, poly in anchors():
        values = flatten(point, poly)
        width = len(values)
        add(point, poly)
        for index in range(width):
            for word in EDGE:
                changed = list(values)
                changed[index] = word
                add(*unflatten(width, tuple(changed)))
        for word in EDGE:
            add(*unflatten(width, (word,) * width))
    return rows


def c_vector(words):
    return '{{load({0}),load({1})}}'.format(*words)


def native(probe, rows):
    lines = [
        '#include "raylib.h"', '#include <stdio.h>', '#include <string.h>',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,&u,4); sink+=u; return x;}',
        'int main(void){SetTraceLogLevel(LOG_NONE); Vector2 dummy={0};',
    ]
    for point, poly in rows:
        verts = ','.join(c_vector(vertex) for vertex in poly) if poly else 'dummy'
        count = len(poly)
        lines.append(
            'printf("%d\\n", CheckCollisionPointPoly('
            f'(Vector2){c_vector(point)}, (Vector2[]){{{verts}}}, {count}) ? 1 : 0);'
        )
    lines.append('(void)sink; return 0;}')
    return probe.native('\n'.join(lines) + '\n')


def bend_vector(words):
    return 'M.Vector2{{{0}, {1}}}'.format(*(f'word({word})' for word in words))


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def flag(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.print("1")
    case False{}: IO.print("0")
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    body = PROGRAM
    for point, poly in selected:
        verts = ', '.join(bend_vector(vertex) for vertex in poly)
        body += f'    flag(J.Collision.point_poly({bend_vector(point)}, [{verts}]))\n'
    return body


def main():
    probe = probekit.Probe('collision-poly', probekit.arguments(__doc__))
    rows = cases()
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'collision-poly: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render, rows, batch=200)
    probe.compare(expected, lanes, lambda index: f'{rows[index][0]} n={len(rows[index][1])}')
    probe.finish(cases=len(rows),
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
