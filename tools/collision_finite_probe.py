#!/usr/bin/env python3
"""Compare finite collision predicates with the host contraction profile.

CheckCollisionCircles, CheckCollisionCircleRec, CheckCollisionCircleLine,
CheckCollisionPointCircle, CheckCollisionPointTriangle, CheckCollisionPointLine,
CheckCollisionSpheres and CheckCollisionBoxSphere on finite normals. The Bend
call uses Collision.*_for with M.Fused on Darwin arm64 and M.Uncontracted on
Linux x86_64, matching the linked raylib build. CPU-1, CPU-2 and JavaScript.
"""
import struct

import probekit
from conformance import contraction

# Ordinary finite values: zeros, a half, small integers and a negative.
NUMBERS = (0.0, 0.5, 1.0, 2.0, -1.0, 3.0)


def bits(value):
    return struct.unpack('<I', struct.pack('<f', float(value)))[0]


def grid(axes):
    rows = [()]
    for axis in axes:
        rows = [row + (value,) for row in rows for value in axis]
    return rows


def cases():
    rows = []
    pair = (0.0, 1.0, 2.0)
    radius = (0.0, 1.0, 2.0)
    for nums in grid((pair, pair, radius, pair, pair, radius)):
        rows.append(('circles', tuple(bits(n) for n in nums)))
    for nums in grid((pair, pair, pair, pair, radius)):
        rows.append(('point_circle', tuple(bits(n) for n in nums)))
    for nums in grid(((0.0, 1.0), (0.0, 1.0), radius, (0.0,), (0.0,), (1.0, 2.0), (1.0, 2.0))):
        rows.append(('circle_rec', tuple(bits(n) for n in nums)))
    for nums in grid(((0.0, 0.5, 1.0, 3.0), (0.0, 0.5, 1.0), (0.0,), (0.0,), (2.0,), (0.0,), (1.0,), (2.0,))):
        rows.append(('point_triangle', tuple(bits(n) for n in nums)))
    for nums in grid(((0.0, 1.0), (0.0, 1.0), (0.0,), (0.0,), (2.0,), (2.0,), (0.0, 1.0, 2.0, -1.0))):
        rows.append(('point_line', tuple(bits(n) for n in nums)))
    for nums in grid(((0.0, 1.0), (1.0,), radius, (0.0,), (0.0,), (2.0,), (2.0,))):
        rows.append(('circle_line', tuple(bits(n) for n in nums)))
    for nums in grid(((0.0, 1.0), (0.0,), (0.0,), radius, (0.0, 2.0), (0.0,), (0.0,), radius)):
        rows.append(('spheres', tuple(bits(n) for n in nums)))
    for nums in (
        (0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 1.0, 1.0, 1.0, 1.0),
        (0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 3.0, 1.0, 1.0, 0.5),
        (0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 3.0, 1.0, 1.0, 2.0),
        (0.0, 0.0, 0.0, 1.0, 1.0, 1.0, -1.0, 0.5, 0.5, 0.0),
        (1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0),
        (0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 0.0, 3.0, 0.0, 1.0),
    ):
        rows.append(('box_sphere', tuple(bits(n) for n in nums)))
    return rows


def c_f(word):
    return f'load({word})'


def c_v2(words):
    return '(Vector2){{{0},{1}}}'.format(*(c_f(w) for w in words))


def c_v3(words):
    return '(Vector3){{{0},{1},{2}}}'.format(*(c_f(w) for w in words))


def c_rect(words):
    return '(Rectangle){{{0},{1},{2},{3}}}'.format(*(c_f(w) for w in words))


def c_box(words):
    return '(BoundingBox){{{0},{1}}}'.format(c_v3(words[:3]), c_v3(words[3:]))


def c_call(name, args):
    if name == 'circles':
        return f'CheckCollisionCircles({c_v2(args[:2])}, {c_f(args[2])}, {c_v2(args[3:5])}, {c_f(args[5])})'
    if name == 'point_circle':
        return f'CheckCollisionPointCircle({c_v2(args[:2])}, {c_v2(args[2:4])}, {c_f(args[4])})'
    if name == 'circle_rec':
        return f'CheckCollisionCircleRec({c_v2(args[:2])}, {c_f(args[2])}, {c_rect(args[3:])})'
    if name == 'point_triangle':
        return f'CheckCollisionPointTriangle({c_v2(args[:2])}, {c_v2(args[2:4])}, {c_v2(args[4:6])}, {c_v2(args[6:])})'
    if name == 'point_line':
        return f'CheckCollisionPointLine({c_v2(args[:2])}, {c_v2(args[2:4])}, {c_v2(args[4:6])}, (int){c_f(args[6])})'
    if name == 'circle_line':
        return f'CheckCollisionCircleLine({c_v2(args[:2])}, {c_f(args[2])}, {c_v2(args[3:5])}, {c_v2(args[5:])})'
    if name == 'spheres':
        return f'CheckCollisionSpheres({c_v3(args[:3])}, {c_f(args[3])}, {c_v3(args[4:7])}, {c_f(args[7])})'
    return f'CheckCollisionBoxSphere({c_box(args[:6])}, {c_v3(args[6:9])}, {c_f(args[9])})'


def bend_v2(words):
    return 'M.Vector2{{{0}, {1}}}'.format(*(f'word({w})' for w in words))


def bend_v3(words):
    return 'M.Vector3{{{0}, {1}, {2}}}'.format(*(f'word({w})' for w in words))


def bend_rect(words):
    return 'J.Rectangle{{{0}, {1}, {2}, {3}}}'.format(*(f'word({w})' for w in words))


def bend_box(words):
    return 'J.BoundingBox{{{0}, {1}}}'.format(bend_v3(words[:3]), bend_v3(words[3:]))


def bend_call(name, args, arithmetic):
    if name == 'circles':
        return f'J.Collision.circles_for({arithmetic}, {bend_v2(args[:2])}, word({args[2]}), {bend_v2(args[3:5])}, word({args[5]}))'
    if name == 'point_circle':
        return f'J.Collision.point_circle_for({arithmetic}, {bend_v2(args[:2])}, {bend_v2(args[2:4])}, word({args[4]}))'
    if name == 'circle_rec':
        return f'J.Collision.circle_rec_for({arithmetic}, {bend_v2(args[:2])}, word({args[2]}), {bend_rect(args[3:])})'
    if name == 'point_triangle':
        return f'J.Collision.point_triangle_for({arithmetic}, {bend_v2(args[:2])}, {bend_v2(args[2:4])}, {bend_v2(args[4:6])}, {bend_v2(args[6:])})'
    if name == 'point_line':
        return f'J.Collision.point_line_for({arithmetic}, {bend_v2(args[:2])}, {bend_v2(args[2:4])}, {bend_v2(args[4:6])}, word({args[6]}))'
    if name == 'circle_line':
        return f'J.Collision.circle_line_for({arithmetic}, {bend_v2(args[:2])}, word({args[2]}), {bend_v2(args[3:5])}, {bend_v2(args[5:])})'
    if name == 'spheres':
        return f'J.Collision.spheres_for({arithmetic}, {bend_v3(args[:3])}, word({args[3]}), {bend_v3(args[4:7])}, word({args[7]}))'
    return f'J.Collision.box_sphere_for({arithmetic}, {bend_box(args[:6])}, {bend_v3(args[6:9])}, word({args[9]}))'


def native(rows):
    lines = [
        '#include "raylib.h"', '#include <stdio.h>', '#include <string.h>',
        'static float load(unsigned bits){float x; memcpy(&x,&bits,4); return x;}',
        'int main(void){SetTraceLogLevel(LOG_NONE);',
    ]
    for name, args in rows:
        lines.append(f'printf("%d\\n", {c_call(name, args)} ? 1 : 0);')
    lines.append('return 0;}')
    return '\n'.join(lines) + '\n'


def program(rows):
    arithmetic = 'M.' + contraction() + '{}'
    body = [
        'import Base', 'import ../../jonlib.bend as J', 'import ../../jonmath.bend as M',
        'def word(bits: U32) -> F32:', '  U32{b} = bits', '  F32{b}',
        'def flag(value: Bool) -> String:', '  match value:', '    case True{}: "1"', '    case False{}: "0"',
        'def main() -> IO(Unit):', '  do IO<Unit>:',
    ]
    for name, args in rows:
        body.append(f'    IO.print(flag({bend_call(name, args, arithmetic)}))')
    return '\n'.join(body) + '\n'


def main():
    probe = probekit.Probe('collision-finite', probekit.arguments(__doc__))
    rows = cases()
    expected = [line for line in probe.native(native(rows)).splitlines() if line]
    lanes = probe.candidates(lambda selected, gpu: program(selected), rows, batch=400,
                             parse=lambda text, selected: [line for line in text.splitlines() if line and not line.startswith('INFO:')])
    probe.compare(expected, lanes, describe=lambda index: rows[index][0])
    probe.finish(cases=len(rows), functions=8)


if __name__ == '__main__':
    main()
