#!/usr/bin/env python3
"""Compare comparison-only collision queries on exceptional and subnormal inputs.

CheckCollisionPointRec, CheckCollisionRecs, CheckCollisionBoxes and
GetCollisionRec are additions and comparisons. The pinned libraylib is the
oracle. Every Boolean and every GetCollisionRec field bit is compared on
CPU-1, CPU-2 and JavaScript.
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
NEG, SUB, MAXF, INF = 0xbf800000, 0x00000001, 0x7f7fffff, 0x7f800000

# (raylib call shape, Bend call, result kind). Shapes: point-rect, two rects, two boxes.
FUNCTIONS = {
    'point_rec': ('point', 'J.Collision.point_rec({0}, {1})', 'bool'),
    'recs': ('rects', 'J.Collision.recs({0}, {1})', 'bool'),
    'boxes': ('boxes', 'J.Collision.boxes({0}, {1})', 'bool'),
    'rectangle': ('rects', 'J.Collision.rectangle({0}, {1})', 'rect'),
}


def anchors(name):
    if name == 'point_rec':
        return (
            (ONE, ONE, ZERO, ZERO, TWO, TWO),
            (ZERO, ZERO, ZERO, ZERO, ZERO, ZERO),
            (ONE, ONE, ZERO, ZERO, SUB, TWO),
            (MAXF, ONE, MAXF, ZERO, MAXF, TWO),
        )
    if name == 'boxes':
        return (
            (ZERO, ZERO, ZERO, TWO, TWO, TWO, ONE, ONE, ONE, 0x40400000, 0x40400000, 0x40400000),
            (ZERO, ZERO, ZERO, ONE, ONE, ONE, TWO, TWO, TWO, 0x40400000, 0x40400000, 0x40400000),
            (ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO),
            (MAXF, ZERO, ZERO, INF, ONE, ONE, MAXF, ZERO, ZERO, MAXF, ONE, ONE),
        )
    return (
        (ZERO, ZERO, TWO, TWO, ONE, ONE, TWO, TWO),
        (ZERO, ZERO, ONE, ONE, TWO, TWO, ONE, ONE),
        (ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO),
        (MAXF, ZERO, MAXF, ONE, MAXF, ZERO, ONE, ONE),
    )


def cases():
    rows = []
    seen = set()
    for name in FUNCTIONS:
        width = len(anchors(name)[0])
        for anchor in anchors(name):
            candidates = [tuple(anchor)]
            for index in range(width):
                for word in EDGE:
                    args = list(anchor)
                    args[index] = word
                    candidates.append(tuple(args))
            for word in EDGE:
                candidates.append((word,) * width)
            for args in candidates:
                key = (name, args)
                if key not in seen:
                    seen.add(key)
                    rows.append(key)
    return rows


def c_vector2(words):
    return '(Vector2){{load({0}),load({1})}}'.format(*words)


def c_vector3(words):
    return '(Vector3){{load({0}),load({1}),load({2})}}'.format(*words)


def c_rect(words):
    return '(Rectangle){{load({0}),load({1}),load({2}),load({3})}}'.format(*words)


def c_box(words):
    return '(BoundingBox){{{0},{1}}}'.format(c_vector3(words[:3]), c_vector3(words[3:]))


def c_call(name, args):
    shape = FUNCTIONS[name][0]
    if shape == 'point':
        return f'CheckCollisionPointRec({c_vector2(args[:2])}, {c_rect(args[2:])})'
    if shape == 'boxes':
        return f'CheckCollisionBoxes({c_box(args[:6])}, {c_box(args[6:])})'
    call = 'CheckCollisionRecs' if name == 'recs' else 'GetCollisionRec'
    return f'{call}({c_rect(args[:4])}, {c_rect(args[4:])})'


def native(probe, rows):
    lines = [
        '#include "raylib.h"', '#include <stdio.h>', '#include <string.h>',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        'int main(void){SetTraceLogLevel(LOG_NONE);',
    ]
    for name, args in rows:
        call = c_call(name, args)
        if FUNCTIONS[name][2] == 'bool':
            lines.append(f'printf("%d\\n", {call} ? 1 : 0);')
        else:
            lines.append('{Rectangle r=' + call + ';printf("[%u,%u,%u,%u]\\n",bits(r.x),bits(r.y),bits(r.width),bits(r.height));}')
    lines.append('(void)sink; return 0;}')
    return probe.native('\n'.join(lines) + '\n')


def bend_vector2(words):
    return 'M.Vector2{{{0}, {1}}}'.format(*(f'word({word})' for word in words))


def bend_vector3(words):
    return 'M.Vector3{{{0}, {1}, {2}}}'.format(*(f'word({word})' for word in words))


def bend_rect(words):
    return 'J.Rectangle{{{0}, {1}, {2}, {3}}}'.format(*(f'word({word})' for word in words))


def bend_box(words):
    return 'J.BoundingBox{{{0}, {1}}}'.format(bend_vector3(words[:3]), bend_vector3(words[3:]))


def bend_call(name, args):
    shape = FUNCTIONS[name][0]
    template = FUNCTIONS[name][1]
    if shape == 'point':
        return template.format(bend_vector2(args[:2]), bend_rect(args[2:]))
    if shape == 'boxes':
        return template.format(bend_box(args[:6]), bend_box(args[6:]))
    return template.format(bend_rect(args[:4]), bend_rect(args[4:]))


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
def rect(value: J.Rectangle) -> IO(Unit):
  J.Rectangle{+x, +y, +w, +h} = value
  IO.print("[" ++ U32.show(F32.bits(x)) ++ "," ++ U32.show(F32.bits(y)) ++ "," ++ U32.show(F32.bits(w)) ++ "," ++ U32.show(F32.bits(h)) ++ "]")
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    body = PROGRAM
    for name, args in selected:
        emitter = 'rect' if FUNCTIONS[name][2] == 'rect' else 'flag'
        body += f'    {emitter}({bend_call(name, args)})\n'
    return body


def main():
    probe = probekit.Probe('collision-domain', probekit.arguments(__doc__))
    rows = cases()
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'collision-domain: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render, rows, batch=300)
    probe.compare(expected, lanes, describe=lambda index: rows[index][0])
    probe.finish(cases=len(rows), functions=len(FUNCTIONS),
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
