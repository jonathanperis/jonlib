#!/usr/bin/env python3
"""Compare ImageDrawTriangleGradient where the integer raster is defined.

Vertices may lie outside -32767..32767. A case is kept only when every (int)
cast of a bound, edge step and barycentric seed fits in a C int, negating a
step does not overflow, the three seed words sum to a nonzero int, every
in-loop increment fits, and every byte weight's product lies in [0, 256).
The area sign and the seeds must agree uncontracted and as an fma, so a
contracted build of the same expression does not change the ints. A zero
weight sum divides by zero and then casts a non-finite weight; that is
undefined in C and is not a case. Formats 1..13 stay on the surface-format
profile; this probe compares the shared raster on format 7.
"""
import ctypes
import hashlib
import json
import math
import struct

import probekit
from probekit import ProbeFailure

_fmaf = ctypes.CDLL('libm.so.6').fmaf
_fmaf.argtypes = (ctypes.c_float, ctypes.c_float, ctypes.c_float)
_fmaf.restype = ctypes.c_float


def fmaf(a, b, c):
    """float fma, the contraction a C compiler may use for a*b+c."""
    return f32(_fmaf(ctypes.c_float(a), ctypes.c_float(b), ctypes.c_float(c)))

WIDTH, HEIGHT = 6, 4
INT_MIN, INT_MAX = -2147483648, 2147483647


def f32(value):
    return struct.unpack('<f', struct.pack('<f', float(value)))[0]


def bits(value):
    return struct.unpack('<I', struct.pack('<f', f32(value)))[0]


def to_int(value):
    value = f32(value)
    if not math.isfinite(value) or value >= 2147483648.0 or value < -2147483648.0:
        return None
    truncated = math.trunc(value)
    if truncated > INT_MAX or truncated < INT_MIN:
        return None
    return int(truncated)


def iadd(left, right):
    total = left + right
    if total > INT_MAX or total < INT_MIN:
        return None
    return total


def ineg(value):
    if value == INT_MIN:
        return None
    return -value


def c_min3(a, b, c):
    return (a if a < c else c) if a < b else (b if b < c else c)


def c_max3(a, b, c):
    return (a if a > c else c) if a > b else (b if b > c else c)


def area_back(ax, ay, bx, by, cx, cy):
    """True when signedArea > 0, if uncontracted and fma agree."""
    dx1, dy2 = f32(bx - ax), f32(cy - ay)
    dx2, dy1 = f32(cx - ax), f32(by - ay)
    separate = f32(f32(dx1 * dy2) - f32(dx2 * dy1))
    fused = fmaf(dx1, dy2, f32(-f32(dx2 * dy1)))
    if not (math.isfinite(separate) and math.isfinite(fused)):
        return None
    if (separate > 0.0) != (fused > 0.0):
        return None
    return separate > 0.0


def seed_int(xmin, vx, sx, ymin, vy, sy):
    """(int)((xMin - vx)*sx + sy*(yMin - vy)), stable under one fma."""
    left_f = f32(f32(float(xmin) - vx) * float(sx))
    right_f = f32(float(sy) * f32(float(ymin) - vy))
    separate = to_int(f32(left_f + right_f))
    fused_a = to_int(fmaf(f32(float(xmin) - vx), float(sx), right_f))
    fused_b = to_int(fmaf(float(sy), f32(float(ymin) - vy), left_f))
    if separate is None or separate != fused_a or separate != fused_b:
        return None
    return separate


def step_pair(start, end, back):
    value = to_int(f32(end - start))
    if value is None:
        return None
    if back:
        value = ineg(value)
    return value


def defined(ax, ay, bx, by, cx, cy, width, height):
    """The reference raster's int operations are defined. None otherwise."""
    back = area_back(ax, ay, bx, by, cx, cy)
    if back is None:
        return False
    x_min = to_int(c_min3(ax, bx, cx))
    y_min = to_int(c_min3(ay, by, cy))
    x_max = to_int(c_max3(ax, bx, cx))
    y_max = to_int(c_max3(ay, by, cy))
    if None in (x_min, y_min, x_max, y_max):
        return False
    if x_min < 0:
        x_min = 0
    if y_min < 0:
        y_min = 0
    if x_max > width:
        x_max = width
    if y_max > height:
        y_max = height
    # Steps are (int) of the vertex differences, negated on a back face.
    # Order matches w1 = v3-v2, w2 = v1-v3, w3 = v2-v1.
    steps = (
        step_pair(by, cy, back), step_pair(cx, bx, back),
        step_pair(cy, ay, back), step_pair(ax, cx, back),
        step_pair(ay, by, back), step_pair(bx, ax, back),
    )
    if any(step is None for step in steps):
        return False
    w1sx, w1sy, w2sx, w2sy, w3sx, w3sy = steps
    seeds = (
        seed_int(x_min, bx, w1sx, y_min, by, w1sy),
        seed_int(x_min, cx, w2sx, y_min, cy, w2sy),
        seed_int(x_min, ax, w3sx, y_min, ay, w3sy),
    )
    if any(seed is None for seed in seeds):
        return False
    total = seeds[0]
    for seed in seeds[1:]:
        total = iadd(total, seed)
        if total is None:
            return False
    if total == 0:
        return False
    inverse = f32(255.0 / f32(float(total)))
    if not math.isfinite(inverse):
        return False
    row = list(seeds)
    y = y_min
    while y <= y_max:
        weights = list(row)
        x = x_min
        while x <= x_max:
            if weights[0] >= 0 and weights[1] >= 0 and weights[2] >= 0:
                for weight in weights:
                    product = f32(f32(float(weight)) * inverse)
                    if not (math.isfinite(product) and 0.0 <= product < 256.0):
                        return False
            nxt = []
            for weight, step in zip(weights, (w1sx, w2sx, w3sx)):
                updated = iadd(weight, step)
                if updated is None:
                    return False
                nxt.append(updated)
            weights = nxt
            x += 1
        nxt = []
        for weight, step in zip(row, (w1sy, w2sy, w3sy)):
            updated = iadd(weight, step)
            if updated is None:
                return False
            nxt.append(updated)
        row = nxt
        y += 1
    return True


def wide(ax, ay, bx, by, cx, cy):
    return max(abs(ax), abs(ay), abs(bx), abs(by), abs(cx), abs(cy)) > 32767.0


BASES = (
    (0.0, 0.0, 4.0, 0.0, 1.0, 3.0),
    (0.0, 0.0, 5.0, 1.0, 2.0, 3.0),
    (-1.0, -1.0, 6.0, 2.0, 2.0, 5.0),
    (0.5, 0.5, 3.5, 1.0, 1.0, 2.5),
)
FAR = (32768.0, -32768.0, 40000.0, -40000.0, 100000.0, -100000.0, 1000000.0, -1000000.0, 8000000.0, -8000000.0)


def candidates():
    rows, seen = [], set()

    def add(*coords):
        values = tuple(f32(v) for v in coords)
        if values in seen:
            return
        if not defined(*values, WIDTH, HEIGHT):
            return
        seen.add(values)
        rows.append(values)

    for base in BASES:
        add(*base)
        for index in range(6):
            for value in FAR:
                changed = list(base)
                changed[index] = value
                add(*changed)
    # Entirely to the right of the image: the box misses, the seeds still run.
    for value in (40000.0, -40000.0, 100000.0, 1000000.0):
        add(value, 0.0, value + 4.0, 1.0, value + 1.0, 3.0)
        add(0.0, value, 4.0, value + 1.0, 1.0, value + 3.0)
    return rows


def native(probe, rows):
    lines = [
        '#include "raylib.h"',
        '#include <stdio.h>',
        '#include <string.h>',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,&u,4); sink+=u; return x;}',
        'int main(void){SetTraceLogLevel(LOG_NONE);',
    ]
    for coords in rows:
        loads = ', '.join(
            f'{name}=load({bits(value)})'
            for name, value in zip(('ax', 'ay', 'bx', 'by', 'cx', 'cy'), coords)
        )
        lines.append(
            '{float %s; Image im=GenImageColor(%d,%d,(Color){1,2,3,4});'
            'ImageDrawTriangleGradient(&im,(Vector2){ax,ay},(Vector2){bx,by},(Vector2){cx,cy},'
            '(Color){255,0,0,255},(Color){0,255,0,128},(Color){0,0,255,64});'
            'printf("["); for(int i=0;i<%d;i++){Color c=GetImageColor(im,i%%%d,i/%d);'
            'if(i)printf(","); printf("%%u",(unsigned)c.r<<24|(unsigned)c.g<<16|(unsigned)c.b<<8|c.a);}'
            'printf("]\\n"); UnloadImage(im);}' % (loads, WIDTH, HEIGHT, WIDTH * HEIGHT, WIDTH, WIDTH)
        )
    lines.append('(void)sink; return 0;}')
    return probe.native('\n'.join(lines) + '\n', extra_flags=('-ffp-contract=off',))


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def fill(n: Nat, bytes: +List<U32>) -> +List<U32>:
  match n:
    case 0n: bytes
    case 1n+k: fill(k, Con{1, Con{2, Con{3, Con{4, bytes}}}})
def blank() -> Maybe<J.Surface>:
  J.Surface.from_bytes(%d, %d, 7, fill(U32.to_nat((%d * %d : U32)), Nil{}))
def shown(result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "colors")
    case Done{colors}: IO.print(List.show(~&1, ~U32, ~U32.show, colors))
def drawn(image: Maybe<J.Surface>, v1: M.Vector2, v2: M.Vector2, v3: M.Vector2) -> IO(Unit):
  match image:
    case None{}: IO.die(Unit, 1, "image")
    case Some{surface}: shown(J.Surface.colors(J.Surface.draw_triangle_gradient(surface, v1, v2, v3, 4278190335, 16711808, 65344)))
def main() -> IO(Unit):
  do IO<Unit>:
''' % (WIDTH, HEIGHT, WIDTH, HEIGHT)


def render(selected, gpu):
    body = PROGRAM
    for coords in selected:
        fields = ', '.join(f'word({bits(value)})' for value in coords)
        body += (
            f'    drawn(blank(), M.Vector2{{word({bits(coords[0])}), word({bits(coords[1])})}}, '
            f'M.Vector2{{word({bits(coords[2])}), word({bits(coords[3])})}}, '
            f'M.Vector2{{word({bits(coords[4])}), word({bits(coords[5])})}})\n'
        )
        del fields
    return body


def main():
    probe = probekit.Probe('triangle-gradient', probekit.arguments(__doc__))
    rows = candidates()
    if sum(wide(*coords) for coords in rows) < 16:
        raise ProbeFailure(f'triangle-gradient: only {sum(wide(*c) for c in rows)} wide defined rasters')
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'triangle-gradient: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render, rows, batch=24)
    probe.compare(expected, lanes, lambda index: str(tuple(rows[index])))
    probe.finish(cases=len(rows), wide=sum(wide(*coords) for coords in rows),
                 inputs_sha256=hashlib.sha256(json.dumps([[bits(v) for v in row] for row in rows]).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
