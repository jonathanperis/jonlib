#!/usr/bin/env python3
"""Compare contracting collision predicates on exceptional and subnormal inputs.

CheckCollisionPointCircle, CheckCollisionCircles, CheckCollisionCircleRec,
CheckCollisionPointTriangle, CheckCollisionPointLine, CheckCollisionCircleLine,
CheckCollisionSpheres and CheckCollisionBoxSphere. The uncontracted result is
the linked raylib. The fused result is the same formula with the Apple-clang
fma shapes (a*b+c*d, squared distance, and circle_line's fused p1-t*d).
Point-line rows keep a threshold whose truncation fits in a C int; a
non-finite threshold or one outside that range is undefined in C and is not
in this corpus. Every Boolean is compared on CPU-1, CPU-2 and JavaScript.
"""
import hashlib
import json
import struct

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
NEG, SUB, MAXF = 0xbf800000, 0x00000001, 0x7f7fffff
HALF = 0x3f000000

# name -> (width, bend call with {a} arithmetic and word() fields)
FUNCTIONS = (
    'point_circle', 'circles', 'circle_rec', 'point_triangle',
    'point_line', 'circle_line', 'spheres', 'box_sphere',
)


def word_float(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]


def in_int(word):
    """True when the C cast of this F32 to int is defined."""
    value = word_float(word)
    return value == value and value < 2147483648.0 and value >= -2147483648.0


def anchors(name):
    if name == 'point_circle':
        return (
            (ZERO, ZERO, ZERO, ZERO, ONE),
            (TWO, ZERO, ZERO, ZERO, ONE),
            (ONE, ZERO, ZERO, ZERO, ONE),
            (ZERO, ZERO, ZERO, ZERO, NEG),
        )
    if name == 'circles':
        return (
            (ZERO, ZERO, ONE, TWO, ZERO, ONE),
            (ZERO, ZERO, ONE, 0x40800000, ZERO, ONE),
            (ZERO, ZERO, NEG, ZERO, ZERO, ONE),
            (ZERO, ZERO, ZERO, ZERO, ZERO, ZERO),
        )
    if name == 'circle_rec':
        return (
            (ZERO, ZERO, ONE, 0xbf800000, 0xbf800000, TWO, TWO),
            (0x41200000, ZERO, ONE, ZERO, ZERO, ONE, ONE),
            (ZERO, ZERO, NEG, ZERO, ZERO, TWO, TWO),
            (ZERO, ZERO, ONE, ZERO, ZERO, ZERO, ZERO),
        )
    if name == 'point_triangle':
        return (
            (0x3e4ccccd, 0x3e4ccccd, ZERO, ZERO, ONE, ZERO, ZERO, ONE),
            (TWO, TWO, ZERO, ZERO, ONE, ZERO, ZERO, ONE),
            (ZERO, ZERO, ZERO, ZERO, ONE, ZERO, ZERO, ONE),
            (HALF, HALF, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO),
        )
    if name == 'point_line':
        return (
            (HALF, ZERO, ZERO, ZERO, ONE, ZERO, ONE),
            (ZERO, ONE, ZERO, ZERO, ONE, ZERO, ZERO),
            (HALF, ZERO, ZERO, ZERO, ONE, ZERO, TWO),
            (ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ONE),
        )
    if name == 'circle_line':
        return (
            (ZERO, ONE, ONE, ZERO, ZERO, ONE, ZERO),
            (ZERO, 0x40a00000, ONE, ZERO, ZERO, ONE, ZERO),
            (ZERO, ZERO, ONE, ONE, ONE, ONE, ONE),
            (ZERO, ZERO, NEG, ZERO, ZERO, TWO, ZERO),
        )
    if name == 'spheres':
        return (
            (ZERO, ZERO, ZERO, ONE, TWO, ZERO, ZERO, ONE),
            (ZERO, ZERO, ZERO, ONE, 0x40800000, ZERO, ZERO, ONE),
            (ZERO, ZERO, ZERO, NEG, ZERO, ZERO, ZERO, ONE),
            (ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO),
        )
    return (
        (ZERO, ZERO, ZERO, ONE, ONE, ONE, HALF, HALF, HALF, ONE),
        (ZERO, ZERO, ZERO, ONE, ONE, ONE, 0x41200000, ZERO, ZERO, ONE),
        (ONE, ONE, ONE, ZERO, ZERO, ZERO, HALF, HALF, HALF, ONE),
        (ZERO, ZERO, ZERO, ONE, ONE, ONE, ZERO, ZERO, ZERO, NEG),
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
                if name == 'point_line' and not in_int(args[-1]):
                    continue
                key = (name, args)
                if key not in seen:
                    seen.add(key)
                    rows.append(key)
    return rows


def c_vec(kind, words):
    loaded = ','.join(f'load({word})' for word in words)
    return f'({kind}){{{loaded}}}'


def c_uncontracted(name, args):
    if name == 'point_circle':
        return f'CheckCollisionPointCircle({c_vec("Vector2", args[0:2])}, {c_vec("Vector2", args[2:4])}, load({args[4]}))'
    if name == 'circles':
        return (f'CheckCollisionCircles({c_vec("Vector2", args[0:2])}, load({args[2]}), '
                f'{c_vec("Vector2", args[3:5])}, load({args[5]}))')
    if name == 'circle_rec':
        rect = ','.join(f'load({word})' for word in args[3:7])
        return f'CheckCollisionCircleRec({c_vec("Vector2", args[0:2])}, load({args[2]}), (Rectangle){{{rect}}})'
    if name == 'point_triangle':
        return (f'CheckCollisionPointTriangle({c_vec("Vector2", args[0:2])}, {c_vec("Vector2", args[2:4])}, '
                f'{c_vec("Vector2", args[4:6])}, {c_vec("Vector2", args[6:8])})')
    if name == 'point_line':
        return (f'CheckCollisionPointLine({c_vec("Vector2", args[0:2])}, {c_vec("Vector2", args[2:4])}, '
                f'{c_vec("Vector2", args[4:6])}, (int)load({args[6]}))')
    if name == 'circle_line':
        return (f'CheckCollisionCircleLine({c_vec("Vector2", args[0:2])}, load({args[2]}), '
                f'{c_vec("Vector2", args[3:5])}, {c_vec("Vector2", args[5:7])})')
    if name == 'spheres':
        return (f'CheckCollisionSpheres({c_vec("Vector3", args[0:3])}, load({args[3]}), '
                f'{c_vec("Vector3", args[4:7])}, load({args[7]}))')
    box = f'(BoundingBox){{{c_vec("Vector3", args[0:3])}, {c_vec("Vector3", args[3:6])}}}'
    return f'CheckCollisionBoxSphere({box}, {c_vec("Vector3", args[6:9])}, load({args[9]}))'


FUSED = r'''
static float square_sum(float dx, float dy){return fmaf(dx, dx, dy*dy);}
static float distance_sqr(float x, float y, float z, float u, float v, float w){
  float dz=w-z; return fmaf(dz, dz, square_sum(u-x, v-y));}
static int circles_fused(float x, float y, float radius, float u, float v, float other){
  float sum=radius+other; return square_sum(u-x, v-y)<=sum*sum;}
static int point_circle_fused(float x, float y, float cx, float cy, float radius){
  return square_sum(x-cx, y-cy)<=radius*radius;}
static int circle_rec_fused(float x, float y, float radius, float rx, float ry, float w, float h){
  float half_w=w/2.0f, half_h=h/2.0f;
  float dx=fabsf(x-(rx+half_w)), dy=fabsf(y-(ry+half_h));
  float corner=square_sum(dx-half_w, dy-half_h);
  return (dx<=half_w+radius)&&(dy<=half_h+radius)&&((dx<=half_w)||(dy<=half_h)||(corner<=radius*radius));}
static int point_triangle_fused(float x, float y, float ax, float ay, float bx, float by, float cx, float cy){
  float denominator=fmaf(by-cy, ax-cx, (cx-bx)*(ay-cy));
  float alpha=fmaf(by-cy, x-cx, (cx-bx)*(y-cy))/denominator;
  float beta=fmaf(cy-ay, x-cx, (ax-cx)*(y-cy))/denominator;
  float gamma=1.0f-alpha-beta;
  return (alpha>0.0f)&&(beta>0.0f)&&(gamma>0.0f);}
static int point_line_fused(float x, float y, float ax, float ay, float bx, float by, float threshold){
  float dx=bx-ax, dy=by-ay;
  float cross=fmaf(x-ax, dy, -((y-ay)*dx));
  float margin=truncf(threshold)*fmaxf(fabsf(dx), fabsf(dy));
  if(!(fabsf(cross)<margin))return 0;
  if(fabsf(dx)>=fabsf(dy))return dx>0.0f? (ax<=x&&x<=bx) : (bx<=x&&x<=ax);
  return dy>0.0f? (ay<=y&&y<=by) : (by<=y&&y<=ay);}
static int circle_line_fused(float x, float y, float radius, float ax, float ay, float bx, float by){
  float dx=ax-bx, dy=ay-by;
  if(fabsf(dx)+fabsf(dy)<=1.1920928955078125e-7f)return circles_fused(ax, ay, 0.0f, x, y, radius);
  float length_squared=square_sum(dx, dy);
  float dot=fmaf(x-ax, bx-ax, (y-ay)*(by-ay));
  float projection=dot/length_squared;
  if(projection>1.0f)projection=1.0f; else if(projection<0.0f)projection=0.0f;
  float distance_x=fmaf(-projection, dx, ax)-x, distance_y=fmaf(-projection, dy, ay)-y;
  return square_sum(distance_x, distance_y)<=radius*radius;}
static int spheres_fused(float x, float y, float z, float radius, float u, float v, float w, float other){
  float sum=radius+other; return distance_sqr(x, y, z, u, v, w)<=sum*sum;}
static float clamp_f(float value, float lower, float upper){
  float first=value<lower? lower : value; return first>upper? upper : first;}
static int box_sphere_fused(float lx, float ly, float lz, float ux, float uy, float uz,
    float x, float y, float z, float radius){
  float cx=clamp_f(x, lx, ux), cy=clamp_f(y, ly, uy), cz=clamp_f(z, lz, uz);
  return distance_sqr(x, y, z, cx, cy, cz)<=radius*radius;}
'''


def c_fused(name, args):
    loaded = ', '.join(f'load({word})' for word in args)
    return f'{name}_fused({loaded})'


def native(probe, rows):
    lines = [
        '#include "raylib.h"', '#include <math.h>', '#include <stdio.h>', '#include <string.h>',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,&u,4); sink+=u; return x;}',
        FUSED,
        'int main(void){SetTraceLogLevel(LOG_NONE);',
    ]
    for name, args in rows:
        lines.append(f'printf("[%d,%d]\\n", {c_uncontracted(name, args)}?1:0, {c_fused(name, args)}?1:0);')
    lines.append('(void)sink; return 0;}')
    return probe.native('\n'.join(lines) + '\n')


def bend_vec(kind, words):
    return kind + '{' + ', '.join(f'word({word})' for word in words) + '}'


def bend_one(name, arithmetic, args):
    w = lambda index: f'word({args[index]})'
    v2 = lambda start: bend_vec('M.Vector2', args[start:start + 2])
    v3 = lambda start: bend_vec('M.Vector3', args[start:start + 3])
    if name == 'point_circle':
        return f'J.Collision.point_circle_for({arithmetic}, {v2(0)}, {v2(2)}, {w(4)})'
    if name == 'circles':
        return f'J.Collision.circles_for({arithmetic}, {v2(0)}, {w(2)}, {v2(3)}, {w(5)})'
    if name == 'circle_rec':
        rect = bend_vec('J.Rectangle', args[3:7])
        return f'J.Collision.circle_rec_for({arithmetic}, {v2(0)}, {w(2)}, {rect})'
    if name == 'point_triangle':
        return f'J.Collision.point_triangle_for({arithmetic}, {v2(0)}, {v2(2)}, {v2(4)}, {v2(6)})'
    if name == 'point_line':
        return f'J.Collision.point_line_for({arithmetic}, {v2(0)}, {v2(2)}, {v2(4)}, {w(6)})'
    if name == 'circle_line':
        return f'J.Collision.circle_line_for({arithmetic}, {v2(0)}, {w(2)}, {v2(3)}, {v2(5)})'
    if name == 'spheres':
        return f'J.Collision.spheres_for({arithmetic}, {v3(0)}, {w(3)}, {v3(4)}, {w(7)})'
    box = f'J.BoundingBox{{{v3(0)}, {v3(3)}}}'
    return f'J.Collision.box_sphere_for({arithmetic}, {box}, {v3(6)}, {w(9)})'


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def bit(value: Bool) -> U32:
  match value:
    case True{}: 1
    case False{}: 0
def pair(left: Bool, right: Bool) -> IO(Unit):
  IO.print("[" ++ U32.show(bit(left)) ++ "," ++ U32.show(bit(right)) ++ "]")
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    body = PROGRAM
    for name, args in selected:
        left = bend_one(name, 'M.Uncontracted{}', args)
        right = bend_one(name, 'M.Fused{}', args)
        body += f'    pair({left}, {right})\n'
    return body


def main():
    probe = probekit.Probe('collision-exceptional', probekit.arguments(__doc__))
    rows = cases()
    if not rows or len(rows) > 8000:
        raise ProbeFailure(f'collision-exceptional: {len(rows)} cases is outside the probe budget')
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'collision-exceptional: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render, rows, batch=200)
    for lane, actual in lanes.items():
        if len(actual) != len(expected):
            raise ProbeFailure(f'collision-exceptional: {lane} produced {len(actual)} rows, expected {len(expected)}')
        different = [index for index, (want, got) in enumerate(zip(expected, actual)) if want != got]
        probe.report.setdefault('lanes', {})[lane] = dict(passed=not different, rows=len(actual), different=different[:12])
        probe.save()
        if different:
            first = different[0]
            name, args = rows[first]
            want, got = expected[first], actual[first]
            profile = 'both' if want[0] != got[0] and want[1] != got[1] else ('uncontracted' if want[0] != got[0] else 'fused')
            raise ProbeFailure(
                f'collision-exceptional: {lane} differs at {len(different)} rows ({profile}); first {name} '
                f'{tuple(hex(word) for word in args)}: reference={json.dumps(want)} jonlib={json.dumps(got)}')
    counts = {name: sum(row_name == name for row_name, _ in rows) for name in FUNCTIONS}
    probe.finish(cases=len(rows), **counts,
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
