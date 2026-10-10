#!/usr/bin/env python3
"""Compare Jonlib's headless Frame and shapes with raylib's software renderer.

The reference is pinned raylib on PLATFORM=Memory (rcore_memory.c, rlgl.h's
OpenGL 1.1 immediate path into src/external/rlsw.h), built for this probe
with CMAKE_C_FLAGS=-ffp-contract=off: scalar rlsw (SIMD intrinsics are off
by default) in uncontracted F32, the profile src/frame.bend implements. The
probe first checks that the archive objects contain no fused multiply-add
instruction and that src/frame_font.bend holds the pinned rtext.c
defaultFontData.

Each scene runs InitWindow(width, height, "") and a sequence of
BeginDrawing/ClearBackground/Draw*/EndDrawing calls, then reads the color
buffer with rlCopyFramebuffer (what SwapScreenBuffer copies): rlsw returns
it top-down in BGRA order (SW_FRAMEBUFFER_OUTPUT_BGRA), which the harness
swaps to RGBA. Jonlib's Frame.framebuffer must print the same bytes,
alpha included. "screen" scenes also compare Frame.load_image_from_screen
with LoadImageFromScreen, whose memory-platform bytes are bottom-up BGRA
with alpha 255: the harness flips and swaps them (and checks they equal the
framebuffer with alpha 255) before comparing.

Scenes cover every implemented shape with integer and fractional
coordinates, partially and fully off-screen and degenerate geometry,
clockwise (culled) and counter-clockwise triangles, translucent colors over
opaque and translucent backgrounds, overlapping draws, spans longer than
rlsw's 16-pixel blocks, lines in every octant, the per-primitive alpha
flag of single-color strips, and sizes from 1x1 to 64x48.

Contracts (Jonlib must answer null, the reference is not run): C int
conversions out of range, gradient extrapolations whose stored channel
leaves (-1, 256) (uint8 conversion undefined), segment counts below
rshapes.c's minimum (acosf/powf estimate) or above 4096, and sinf/cosf
arguments outside the host M.Libm profile's verified set (Apple: fl(DEG2RAD*d)
for integral |d| <= 360 except 13, 19, 22, 103 and 188; glibc: normal or
zero, glibc's own sinf/cosf, docs/SINCOSF.md). A trig table checks every accepted DEG2RAD*d
argument's sine and cosine bits against the host sinf/cosf. CPU-1, CPU-2
and JavaScript lanes.

--benchmark instead times a 640x480 frame (clear plus 100 rectangles and
circles) natively and on the CPU lanes; it records, never compares.
"""
import hashlib
import json
import math
import platform
import random
import re
import struct
import time

from conformance import gradient_reference
import probekit
from probekit import ROOT, ProbeFailure

OPTIONS = ('CMAKE_C_FLAGS=-ffp-contract=off',)
DEG2RAD_BITS = 1016003125
APPLE_EXCLUDED = (13, 19, 22, 103, 188)


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def from_bits(bits):
    return struct.unpack('<f', struct.pack('<I', bits))[0]


DEG2RAD = from_bits(DEG2RAD_BITS)


# -----------------------------------------------------------------------------
# The libm contract (mirrors src/shapes.bend trig.ok)

def accepted(libm, arg):
    if math.isnan(arg) or math.isinf(arg):
        return False
    if libm == 'AppleLibm':
        d = f32(arg / DEG2RAD)
        d = math.floor(abs(d) + 0.5) * (1 if d >= 0 else -1)
        return abs(d) <= 360 and f32(DEG2RAD * d) == arg and abs(d) not in APPLE_EXCLUDED
    magnitude = word(arg) & 0x7FFFFFFF
    return magnitude == 0 or 0x00800000 <= magnitude < 0x7F800000


def c_int(value):
    """C's float-to-int conversion, or None when undefined."""
    if math.isnan(value) or not -2147483648.0 <= value < 2147483648.0:
        return None
    return int(value)


def sector_plan(start, end, segments, libm=None):
    """(start, step, segments) of DrawCircleSector(Lines)/DrawRing, [] for nothing, None when refused.

    Fewer segments than rshapes.c's minimum make it estimate them with acosf: Jonlib reproduces that under
    M.Glibc239Libm only ('estimated'; its arguments stay within the verified glibc sine/cosine range, and
    tools/rlgl_probe.py checks the estimates), and refuses it elsewhere."""
    if start == end:
        return []
    if end < start:
        start, end = end, start
    span = f32(end - start)
    minimum = math.ceil(f32(span / 90.0)) if math.isfinite(span) else None
    if minimum is None or c_int(float(minimum)) is None:
        return None
    segments = c_int(segments)
    if segments is not None and segments < minimum and libm == 'Glibc239Libm':
        return 'estimated'
    if segments is None or segments < minimum or segments > 4096:
        return None
    return start, f32(span / segments), segments


def rad(angle):
    return f32(DEG2RAD * angle)


def sector_args(start, end, segments, libm=None):
    plan = sector_plan(start, end, segments, libm)
    if plan == 'estimated':
        return []
    if not plan:
        return plan
    angle, step, segments = plan
    args = []
    for _ in range(segments // 2):
        args += [rad(f32(angle + f32(step * 2.0))), rad(f32(angle + step)), rad(angle)]
        angle = f32(angle + f32(step * 2.0))
    if segments % 2:
        args += [rad(f32(angle + step)), rad(angle)]
    return args


def stepped_args(start, end, segments, libm=None):
    """DrawCircleSectorLines and DrawRing: angle, angle + step per segment, then the final angle."""
    plan = sector_plan(start, end, segments, libm)
    if plan == 'estimated':
        return []
    if not plan:
        return plan
    angle, step, segments = plan
    args = [rad(angle)]
    for _ in range(segments):
        args += [rad(angle), rad(f32(angle + step))]
        angle = f32(angle + step)
    return args + [rad(angle)]


def poly_args(sides, rotation):
    sides = c_int(sides)
    if sides is None:
        return None
    sides = max(sides, 3)
    if sides > 4096:
        return None
    central, step = f32(rotation * DEG2RAD), f32(f32(360.0 / sides) * DEG2RAD)
    args = []
    for _ in range(sides):
        args += [central, f32(central + step)]
        central = f32(central + step)
    return args


def circle_args():
    return [rad(float(d)) for d in range(0, 361, 10)]


def trig_arguments(op, libm=None):
    """The sinf/cosf arguments an operation evaluates (None: refused regardless)."""
    name, a = op[0], op[1:]
    if name in ('circle', 'circle_v', 'circle_lines', 'circle_lines_v', 'ellipse', 'ellipse_v', 'ellipse_lines',
                'ellipse_lines_v', 'circle_gradient'):
        return circle_args()
    if name == 'rect_pro':
        return [] if a[6] == 0.0 else [f32(a[6] * DEG2RAD)]
    if name == 'sector':
        return sector_args(a[3], a[4], a[5], libm)
    if name == 'sector_lines':
        return stepped_args(a[3], a[4], a[5], libm)
    if name == 'ring':
        inner, outer = (a[3], a[2]) if a[3] < a[2] else (a[2], a[3])
        return sector_args(a[4], a[5], a[6], libm) if inner <= 0.0 else stepped_args(a[4], a[5], a[6], libm)
    if name in ('poly', 'poly_lines'):
        return poly_args(a[2], a[4])
    return []


INT_PARAMETERS = {'pixel': 2, 'line': 4, 'rect': 4, 'grad_v': 4, 'grad_h': 4, 'rect_lines': 4, 'circle': 2,
                  'circle_lines': 2, 'ellipse': 2, 'ellipse_lines': 2}


def refused(op, libm):
    """Whether Jonlib must refuse this operation (contract), from the declared rules."""
    if len(op) > 1 and op[-1] == 'undefined':
        return True
    count = INT_PARAMETERS.get(op[0], 0)
    if any(c_int(v) is None for v in op[1:1 + count]):
        return True
    args = trig_arguments(op, libm)
    return args is None or not all(accepted(libm, x) for x in args)


# -----------------------------------------------------------------------------
# Scenes

def C(r, g, b, a=255):
    return (r << 24) | (g << 16) | (b << 8) | a


def scenes():
    rng = random.Random(0xF4A3E)
    out = []

    def add(name, width, height, ops, screen=False):
        out.append(dict(id=name, width=width, height=height, ops=ops, screen=screen))

    red, green, blue, white = C(230, 41, 55), C(0, 228, 48), C(0, 121, 241), C(255, 255, 255)
    half = [C(255, 0, 0, 128), C(0, 255, 0, 64), C(0, 0, 255, 200), C(255, 255, 0, 1), C(255, 0, 255, 0), C(17, 34, 51, 254)]
    backgrounds = [C(0, 0, 0), C(255, 255, 255), C(90, 160, 200), C(255, 128, 128, 100), C(10, 20, 30, 0)]

    # Frame lifecycle and clearing.
    add('init-only-16x12', 16, 12, [])
    add('init-1x1', 1, 1, [('begin',), ('end',)], screen=True)
    for i, bg in enumerate(backgrounds):
        add(f'clear-{i}', 7, 5, [('begin',), ('clear', bg), ('end',)], screen=True)
    add('clear-twice', 9, 3, [('clear', red), ('begin',), ('clear', C(1, 2, 3, 4)), ('end',)])

    # Pixels.
    for size in ((16, 12), (33, 17)):
        w, h = size
        pts = [(0, 0), (w - 1, h - 1), (w - 1, 0), (0, h - 1), (3, 4), (-1, 2), (w, 3), (2, h), (-1, -1)]
        ops = [('begin',), ('clear', C(20, 30, 40))]
        for k, (x, y) in enumerate(pts):
            ops.append(('pixel', float(x), float(y), [red, green, blue, white, half[0], half[1], half[2], half[3], half[4]][k]))
        ops += [('pixel', 5.7, 6.2, half[5]), ('pixel', -0.5, 3.9, red), ('pixel', 4.999, 0.0001, green), ('end',)]
        add(f'pixels-int-{w}x{h}', w, h, ops)
        ops = [('begin',), ('clear', backgrounds[3])]
        for k in range(24):
            x, y = rng.uniform(-2, w + 1), rng.uniform(-2, h + 1)
            ops.append(('pixel_v', f32(x), f32(y), rng.choice(half + [red, green])))
        ops += [('pixel_v', 0.5, 0.5, red), ('pixel_v', 0.49, 0.51, green), ('pixel_v', -0.5, -0.5, blue),
                ('pixel_v', w - 0.5, h - 0.5, white), ('pixel_v', 2.0, 2.0, half[0]), ('pixel_v', 2.0, 2.0, half[0]), ('end',)]
        add(f'pixels-v-{w}x{h}', w, h, ops)

    # Lines: octants, axis-aligned, short, clipped, translucent.
    for w, h in ((16, 12), (33, 17), (64, 48)):
        ops = [('begin',), ('clear', C(0, 0, 0))]
        cx, cy = w // 2, h // 2
        for k in range(16):
            angle = k * math.pi / 8
            ops.append(('line', float(cx), float(cy), float(cx + round(math.cos(angle) * w / 3)), float(cy + round(math.sin(angle) * h / 3)),
                        [red, green, blue, white][k % 4]))
        ops += [('line', 0.0, 0.0, float(w - 1), 0.0, white), ('line', 0.0, float(h - 1), float(w - 1), float(h - 1), green),
                ('line', 0.0, 0.0, 0.0, float(h - 1), blue), ('line', float(w - 1), 0.0, float(w - 1), float(h - 1), red),
                ('line', -5.0, -3.0, float(w + 4), float(h + 6), half[0]), ('line', 3.0, 3.0, 3.0, 3.0, white),
                ('line', 2.0, 5.0, 3.0, 5.0, white), ('line', float(w + 2), 1.0, float(w + 9), 7.0, white), ('end',)]
        add(f'lines-int-{w}x{h}', w, h, ops)
        ops = [('begin',), ('clear', backgrounds[2])]
        for k in range(20):
            ops.append(('line_v', f32(rng.uniform(-4, w + 4)), f32(rng.uniform(-4, h + 4)), f32(rng.uniform(-4, w + 4)),
                        f32(rng.uniform(-4, h + 4)), rng.choice(half + [red, white])))
        ops += [('line_v', 0.5, 0.5, 0.9, 0.7, red), ('line_v', 1.25, 2.75, 1.25, 9.75, green), ('line_v', 2.5, 1.5, 12.5, 1.5, blue),
                ('line_v', 6.4, 3.3, 2.6, 8.8, half[2]), ('end',)]
        add(f'lines-v-{w}x{h}', w, h, ops)
    add('lines-fractional-int', 16, 12, [('begin',), ('line', 1.9, 2.9, 12.2, 9.99, white), ('line', -0.7, 4.0, 15.5, 4.2, red), ('end',)])

    # Rectangles.
    for w, h in ((16, 12), (33, 17), (64, 48)):
        ops = [('begin',), ('clear', C(245, 245, 245))]
        ops += [('rect', 1.0, 1.0, 5.0, 3.0, red), ('rect', -3.0, -2.0, 6.0, 5.0, blue), ('rect', float(w - 4), float(h - 3), 10.0, 10.0, green),
                ('rect', 4.0, 5.0, 0.0, 4.0, red), ('rect', 4.0, 5.0, 3.0, 0.0, red), ('rect', 8.0, 2.0, -3.0, 4.0, red),
                ('rect', 2.0, 7.0, 4.0, -2.0, red), ('rect', float(w + 1), 0.0, 3.0, 3.0, red), ('rect', -10.0, -10.0, float(w + 20), float(h + 20), half[1]),
                ('rect', 3.0, 3.0, float(w - 6), float(h - 6), half[0]), ('rect', 2.0, 2.0, 1.0, 1.0, half[5]), ('end',)]
        add(f'rect-int-{w}x{h}', w, h, ops)
        ops = [('begin',), ('clear', backgrounds[3])]
        for k in range(14):
            ops.append(('rect_rec', f32(rng.uniform(-6, w)), f32(rng.uniform(-6, h)), f32(rng.uniform(0, w / 2)), f32(rng.uniform(0, h / 2)),
                        rng.choice(half + [red, green, blue])))
        ops += [('rect_v', 0.5, 0.5, 3.0, 2.0, red), ('rect_v', 2.25, 4.75, 0.5, 0.5, green), ('rect_v', 5.4, 1.6, 0.2, 7.0, blue),
                ('rect_rec', 1.5, 6.5, 6.0, 0.4, white), ('rect_rec', 7.49, 3.51, 4.02, 3.98, half[2]), ('end',)]
        add(f'rect-v-{w}x{h}', w, h, ops)
    add('rect-wide-blocks', 64, 8, [('begin',), ('clear', C(0, 0, 40)), ('rect_rec', 0.3, 0.6, 63.4, 6.9, half[0]),
                                     ('rect_rec', -0.5, 2.0, 70.0, 2.0, half[2]), ('end',)], screen=True)

    # DrawRectanglePro: unrotated with origin, integral-degree rotations, refusals.
    for w, h in ((33, 17), (64, 48)):
        ops = [('begin',), ('clear', C(30, 30, 30))]
        for k, rot in enumerate((0.0, 30.0, 45.0, 90.0, -45.0, 180.0, 270.0, 360.0, -360.0, 1.0, 359.0, 15.0)):
            ops.append(('rect_pro', f32(w / 2 + (k % 4) - 2), f32(h / 2 + (k // 4) - 1), f32(4 + k % 5), f32(3 + k % 3),
                        f32((k % 3) * 1.5), f32((k % 2) * 2.0), rot, [red, green, blue, half[0], half[2], white][k % 6]))
        ops += [('rect_pro', 2.0, 2.0, 5.0, 3.0, 1.5, 1.5, -0.0, red), ('rect_pro', 60.0, -3.0, 9.0, 9.0, 0.0, 0.0, 45.0, green), ('end',)]
        add(f'rect-pro-{w}x{h}', w, h, ops)
    add('rect-pro-unverified-13', 16, 12, [('rect_pro', 4.0, 4.0, 5.0, 3.0, 0.0, 0.0, 13.0, red)])
    add('rect-pro-unverified-fraction', 16, 12, [('rect_pro', 4.0, 4.0, 5.0, 3.0, 0.0, 0.0, 12.5, red)])
    add('rect-pro-nan', 16, 12, [('rect_pro', 4.0, 4.0, 5.0, 3.0, 0.0, 0.0, float('nan'), red)])

    # Gradients (V/H/Ex); the box rasterizer reads three corners.
    for w, h in ((16, 12), (64, 48)):
        ops = [('begin',), ('clear', C(255, 255, 255)), ('grad_v', 1.0, 1.0, float(w - 2), float(h // 2), red, blue),
               ('grad_h', 0.0, float(h // 2), float(w), float(h // 2), half[0], half[2]),
               ('grad_v', 3.0, 3.0, 5.0, 5.0, C(0, 0, 0, 0), C(255, 255, 255, 255)), ('end',)]
        add(f'gradient-vh-{w}x{h}', w, h, ops)
        ops = [('begin',), ('clear', backgrounds[3]),
               ('grad_ex', 0.5, 0.5, f32(w - 3.0), f32(h - 2.0), C(200, 100, 50, 200), C(100, 50, 25, 100), C(0, 0, 0, 0), C(200, 100, 50, 200)),
               ('grad_ex', 2.25, 1.75, 6.5, 4.5, C(255, 0, 0, 255), C(128, 0, 64, 255), C(0, 0, 128, 255), C(255, 255, 255, 255)),
               ('grad_ex', -3.0, -2.0, f32(w / 2), f32(h / 2), C(10, 200, 30, 150), C(10, 100, 30, 150), C(9, 9, 9, 9), C(10, 200, 30, 150)), ('end',)]
        add(f'gradient-ex-{w}x{h}', w, h, ops, screen=(w == 16))
    add('gradient-ex-overflow', 16, 12, [('grad_ex', 0.0, 0.0, 16.0, 12.0, C(0, 0, 0), C(255, 255, 255), C(0, 0, 0), C(255, 255, 255), 'undefined')])
    # rlsw's box corners are the bottom-left (base), bottom-right and top-left
    # on screen: their bilinear extrapolation reaches 2.0 for red at the top right.
    add('gradient-ex-corner-overflow', 16, 12, [('grad_ex', 2.25, 1.75, 6.5, 4.5, C(255, 0, 0), C(0, 0, 0), C(255, 255, 255), C(255, 0, 0), 'undefined')])
    add('gradient-int-overflow', 16, 12, [('grad_v', 3e9, 0.0, 4.0, 4.0, red, blue)])

    # Rectangle outlines.
    for w, h in ((16, 12), (33, 17)):
        ops = [('begin',), ('clear', C(0, 0, 0)), ('rect_lines', 1.0, 1.0, 8.0, 6.0, red), ('rect_lines', 0.0, 0.0, float(w), float(h), green),
               ('rect_lines', 5.0, 5.0, 1.0, 1.0, white), ('rect_lines', 3.0, 8.0, 0.0, 3.0, blue), ('rect_lines', -2.0, -2.0, 6.0, 6.0, half[0]),
               ('rect_lines_ex', 2.0, 2.0, 10.0, 7.0, 2.0, half[2]), ('rect_lines_ex', 4.5, 3.5, 6.0, 3.0, 5.0, white),
               ('rect_lines_ex', 0.0, float(h - 4), 3.0, 4.0, 1.0, red), ('end',)]
        add(f'rect-lines-{w}x{h}', w, h, ops)

    # Triangles: CCW drawn, CW culled, degenerate, clipped, tiny, long spans.
    for w, h in ((16, 12), (33, 17), (64, 48)):
        ops = [('begin',), ('clear', C(250, 250, 250))]
        ops += [('tri', 2.0, 2.0, 2.0, 9.0, 10.0, 9.0, red), ('tri', 2.0, 2.0, 10.0, 9.0, 2.0, 9.0, blue),
                ('tri', 1.0, 1.0, 5.0, 5.0, 9.0, 9.0, green), ('tri', -4.0, 3.0, 6.0, float(h + 5), float(w + 3), -2.0, half[0]),
                ('tri', 3.3, 1.2, 1.7, 3.9, 4.1, 3.1, half[2]), ('tri', 6.0, 6.0, 6.0, 6.4, 6.3, 6.4, white),
                ('tri', 7.0, 1.0, 7.0, 9.0, 7.4, 9.0, red), ('tri', 0.0, 0.0, 0.0, float(h), float(w), float(h), half[1]),
                ('tri', float(w - 1), 0.5, 1.5, float(h - 1), float(w - 0.5), float(h - 0.5), half[5]), ('end',)]
        add(f'tri-{w}x{h}', w, h, ops)
        ops = [('begin',), ('clear', backgrounds[2])]
        for k in range(12):
            pts = [f32(rng.uniform(-8, w + 8)) if i % 2 == 0 else f32(rng.uniform(-8, h + 8)) for i in range(6)]
            ops.append(('tri', *pts, rng.choice(half + [red, green, blue])))
        ops += [('tri_lines', 1.0, 1.0, 1.0, 8.0, 9.0, 8.0, white), ('tri_lines', 3.5, 2.5, 12.5, 4.5, 6.5, 10.5, half[0]), ('end',)]
        add(f'tri-random-{w}x{h}', w, h, ops)

    # Fans, strips, line strips and thick lines (single color: only the
    # first primitive of untextured strips carries the alpha flag).
    for w, h in ((33, 17), (64, 48)):
        fan = [(f32(w / 2), f32(h / 2))] + [(f32(w / 2 + math.cos(-k * 0.6) * w / 3), f32(h / 2 + math.sin(-k * 0.6) * h / 3)) for k in range(8)]
        strip = [(f32(2 + k * 3.1), f32(3 + (k % 2) * 6.5)) for k in range(9)]
        ops = [('begin',), ('clear', C(0, 0, 0)), ('fan', fan, half[0]), ('strip', strip, half[2]), ('strip', [(1.0, 1.0), (1.0, 6.0), (6.0, 1.0), (6.0, 6.0)], red),
               ('fan', [(1.0, 1.0), (2.0, 2.0)], white), ('strip', [(1.0, 1.0), (2.0, 2.0)], white),
               ('line_strip', [(1.0, float(h - 2)), (float(w - 2), float(h - 3)), (5.0, 2.0), (5.0, 2.0), (30.5, 10.25)], half[0]),
               ('line_strip', [(3.0, 3.0)], white), ('line_ex', 2.0, 2.0, float(w - 3), float(h - 4), 3.0, half[1]),
               ('line_ex', 4.0, 10.0, 4.0, 10.0, 2.0, red), ('line_ex', 1.5, 8.25, 20.5, 8.25, 1.0, green), ('line_ex', 2.0, 2.0, 9.0, 3.0, -1.0, red),
               ('end',)]
        add(f'strips-{w}x{h}', w, h, ops)

    # Circles, sectors, rings, ellipses, polygons.
    for w, h in ((16, 12), (33, 17), (64, 48)):
        ops = [('begin',), ('clear', C(240, 240, 240)), ('circle', float(w // 2), float(h // 2), float(min(w, h) // 3), red),
               ('circle_v', 3.5, 3.25, 2.5, half[2]), ('circle_v', float(w - 1), float(h - 1), 6.0, half[0]), ('circle_v', 2.0, float(h - 2), 0.0, green),
               ('circle_v', 5.0, 5.0, -3.0, blue), ('circle_v', 8.0, 4.0, 0.5, white), ('circle_v', -20.0, -20.0, 5.0, red),
               ('circle', -1.0, float(h // 2), 4.0, half[5]), ('circle_v', f32(w / 2 + 0.3), f32(h / 2 - 0.2), f32(max(w, h) * 0.9), half[1]),
               ('circle_lines', float(w // 3), float(h // 3), 4.0, blue), ('circle_lines_v', 6.5, 6.5, 5.5, half[0]),
               ('circle_gradient', f32(w * 0.7), f32(h * 0.6), 5.0, C(255, 255, 255, 255), C(0, 0, 255, 0)), ('end',)]
        add(f'circles-{w}x{h}', w, h, ops)
        ops = [('begin',), ('clear', C(20, 20, 20)), ('sector', f32(w / 2), f32(h / 2), 7.0, 0.0, 90.0, 6.0, red),
               ('sector', f32(w / 2), f32(h / 2), 6.0, 180.0, 90.0, 5.0, half[0]), ('sector', 4.0, 4.0, 3.0, 10.0, 10.0, 8.0, white),
               ('sector', f32(w / 3), f32(h / 3), 4.5, -90.0, 0.0, 1.0, blue), ('sector', 6.0, 6.0, 5.0, 0.0, 270.0, 6.0, half[2]),
               ('sector', 3.0, 9.0, -2.0, 45.0, 315.0, 9.0, white),
               ('sector_lines', f32(w * 0.7), f32(h / 2), 5.0, 0.0, 120.0, 4.0, green), ('sector_lines', 5.0, 5.0, 0.0, 200.0, 90.0, 11.0, white),
               ('ring', f32(w / 2), f32(h / 2), 3.0, 6.0, 0.0, 360.0, 12.0, half[0]), ('ring', 5.0, 5.0, 4.0, 2.0, 45.0, 315.0, 9.0, half[2]),
               ('ring', 9.0, 7.0, 0.0, 4.0, 0.0, 180.0, 4.0, green), ('ring', 9.0, 7.0, -1.0, -2.0, 0.0, 90.0, 3.0, red),
               ('ellipse', float(w // 2), float(h // 2), float(w // 3), float(h // 4), half[1]), ('ellipse_v', 4.5, 8.5, 3.0, 1.5, red),
               ('ellipse_lines', float(w // 2), float(h // 2), float(w // 4), float(h // 3), white), ('ellipse_lines_v', 10.5, 3.5, 6.0, 2.0, half[0]),
               ('poly', f32(w / 2), f32(h / 2), 6.0, 5.0, -30.0, half[2]), ('poly', 5.0, 5.0, 2.0, 4.0, 0.0, red), ('poly', 10.0, 6.0, 4.0, 3.0, -90.0, green),
               ('poly', 8.0, 4.0, 5.0, 3.5, -120.0, half[0]),
               ('poly_lines', f32(w / 2), f32(h / 2), 6.0, 6.0, -180.0, white), ('poly_lines', 4.0, 4.0, 3.0, 3.0, -90.0, blue), ('end',)]
        add(f'arcs-{w}x{h}', w, h, ops, screen=(w == 33))
    add('sector-too-few-segments', 16, 12, [('sector', 8.0, 6.0, 5.0, 0.0, 360.0, 3.0, red)])
    add('sector-too-many-segments', 16, 12, [('sector', 8.0, 6.0, 5.0, 0.0, 360.0, 5000.0, red)])
    add('sector-unverified-step', 16, 12, [('sector', 8.0, 6.0, 5.0, 0.0, 100.0, 3.0, red)])
    add('poly-unverified', 16, 12, [('poly', 8.0, 6.0, 7.0, 5.0, 0.0, red)])
    add('poly-past-one-turn', 16, 12, [('poly_lines', 8.0, 6.0, 4.0, 5.0, 90.0, red)])
    add('ring-unverified-start', 16, 12, [('ring', 8.0, 6.0, 2.0, 5.0, 13.0, 103.0, 3.0, red)])
    add('circle-int-overflow', 16, 12, [('circle', -3e9, 4.0, 3.0, red)])
    add('pixel-int-nan', 16, 12, [('pixel', float('nan'), 4.0, red)])
    add('line-int-overflow', 16, 12, [('line', 0.0, 0.0, 2147483648.0, 4.0, red)])

    # Translucent stacks over translucent clears; nonfinite and huge geometry.
    add('stack-translucent', 16, 12, [('begin',), ('clear', C(255, 128, 128, 100)), ('rect', 0.0, 0.0, 16.0, 12.0, C(0, 0, 255, 128)),
                                      ('rect', 2.0, 2.0, 12.0, 8.0, C(0, 255, 0, 3)), ('circle_v', 8.0, 6.0, 4.0, C(255, 255, 255, 254)),
                                      ('tri', 0.0, 0.0, 0.0, 12.0, 16.0, 12.0, C(10, 20, 30, 77)), ('pixel', 5.0, 5.0, C(255, 0, 0, 255)),
                                      ('line', 0.0, 6.0, 15.0, 6.0, C(255, 255, 0, 10)), ('end',)], screen=True)
    add('nonfinite', 16, 12, [('rect_rec', float('nan'), 2.0, 4.0, 4.0, red), ('rect_rec', 2.0, 2.0, float('inf'), 4.0, green),
                              ('tri', float('-inf'), 0.0, 0.0, 12.0, 16.0, 12.0, blue),
                              ('rect_rec', 1.0, 1.0, 3.0, 3.0, white)])
    # A NaN endpoint survives Liang-Barsky (NaN ratios never clip) and reaches sw_clamp's (int)NaN.
    add('line-nan-endpoint', 16, 12, [('line_v', 1.0, 1.0, float('nan'), 5.0, white, 'undefined')])
    # An infinite endpoint clips with t1 = 0, and v0 + 0*inf is NaN at the same conversion.
    add('line-inf-endpoint', 16, 12, [('line_v', 1.0, 1.0, float('inf'), 5.0, white, 'undefined')])
    add('huge', 33, 17, [('rect_rec', -1e7, -1e7, 2e7, 2e7, half[0]), ('tri', -1e6, -1e6, -1e6, 1e6, 1e6, 1e6, half[2]),
                         ('line_v', -1e6, 3.0, 1e6, 5.0, white), ('rect_rec', 1e30, 1e30, 1.0, 1.0, red)])
    add('tall-1x9', 1, 9, [('clear', C(1, 2, 3)), ('rect_rec', 0.0, 2.0, 1.0, 3.0, red), ('line', 0.0, 0.0, 0.0, 8.0, green), ('pixel', 0.0, 8.0, blue)])
    add('wide-7x1', 7, 1, [('clear', C(1, 2, 3)), ('rect_rec', 2.0, 0.0, 3.0, 1.0, red), ('line', 0.0, 0.0, 6.0, 0.0, green), ('circle_v', 3.0, 0.5, 2.0, half[0])])
    add('draw-outside-begin', 16, 12, [('rect', 1.0, 1.0, 4.0, 4.0, red), ('begin',), ('end',), ('rect', 3.0, 3.0, 4.0, 4.0, half[0]),
                                       ('begin',), ('clear', C(9, 9, 9)), ('pixel', 1.0, 1.0, white), ('end',)])

    # Random scenes: every shape with random geometry (half the coordinates
    # fractional, some off-screen) and colors, overlapping in draw order.
    def coordinate(limit, fractional):
        value = rng.uniform(-0.3 * limit, 1.3 * limit)
        return f32(value) if fractional else float(round(value))

    def color():
        return C(rng.randrange(256), rng.randrange(256), rng.randrange(256), rng.choice((255, 255, 0, 1, 128, 200, 254, rng.randrange(256))))

    for index in range(24):
        w, h = rng.choice(((16, 12), (33, 17), (64, 48), (23, 31), (5, 40)))
        ops = [('begin',), ('clear', color())]
        for _ in range(rng.randint(12, 28)):
            frac = rng.random() < 0.5
            x, y = (lambda: coordinate(w, frac)), (lambda: coordinate(h, frac))
            kind = rng.choice(('pixel', 'pixel_v', 'line', 'line_v', 'line_ex', 'rect', 'rect_rec', 'rect_pro', 'grad_v', 'grad_h', 'rect_lines',
                               'rect_lines_ex', 'tri', 'tri_lines', 'fan', 'strip', 'line_strip', 'circle_v', 'circle', 'circle_lines_v',
                               'ellipse_v', 'circle_gradient', 'sector', 'sector_lines', 'ring', 'poly'))
            size = lambda: f32(rng.uniform(-2, max(w, h) / 2)) if frac else float(rng.randint(-2, max(w, h) // 2))
            if kind in ('pixel', 'pixel_v'):
                ops.append((kind, x(), y(), color()))
            elif kind in ('line', 'line_v'):
                ops.append((kind, x(), y(), x(), y(), color()))
            elif kind == 'line_ex':
                ops.append((kind, x(), y(), x(), y(), f32(rng.uniform(-1, 6)), color()))
            elif kind in ('rect', 'rect_rec', 'rect_lines'):
                ops.append((kind, x(), y(), size(), size(), color()))
            elif kind == 'rect_lines_ex':
                ops.append((kind, x(), y(), size(), size(), f32(rng.uniform(0, 4)), color()))
            elif kind == 'rect_pro':
                rotation = float(rng.choice((0, 0, 30, 45, -60, 90, 135, 200, -300, 359, 7)))
                ops.append((kind, x(), y(), size(), size(), f32(rng.uniform(-3, 3)), f32(rng.uniform(-3, 3)), rotation, color()))
            elif kind in ('grad_v', 'grad_h'):
                ops.append((kind, x(), y(), size(), size(), color(), color()))
            elif kind in ('tri', 'tri_lines'):
                ops.append((kind, x(), y(), x(), y(), x(), y(), color()))
            elif kind in ('fan', 'strip', 'line_strip'):
                ops.append((kind, [(f32(rng.uniform(-3, w + 3)), f32(rng.uniform(-3, h + 3))) for _ in range(rng.randint(1, 8))], color()))
            elif kind in ('circle_v', 'circle_lines_v'):
                ops.append((kind, x(), y(), size(), color()))
            elif kind == 'circle':
                ops.append((kind, float(round(rng.uniform(0, w))), float(round(rng.uniform(0, h))), size(), color()))
            elif kind == 'ellipse_v':
                ops.append((kind, x(), y(), size(), size(), color()))
            elif kind == 'circle_gradient':
                ops.append((kind, x(), y(), size(), color(), color()))
            elif kind in ('sector', 'sector_lines'):
                start, segments = float(rng.choice((0, 30, 90, -45, 180))), rng.choice((2, 3, 4, 5, 6, 9))
                step = rng.choice((10, 15, 20, 30))
                end = start + step * segments
                first, last = (end, start) if rng.random() < 0.3 else (start, end)
                ops.append((kind, x(), y(), size(), first, last, float(segments), color()))
            elif kind == 'ring':
                start, segments, step = float(rng.choice((0, 45, -90))), rng.choice((3, 4, 6, 8)), rng.choice((15, 30, 45))
                ops.append((kind, x(), y(), size(), size(), start, start + step * segments, float(segments), color()))
            else:
                sides, rotation = rng.choice(((3, 0.0), (4, -90.0), (6, -30.0), (5, -120.0), (3, -180.0), (6, -360.0)))
                ops.append((kind, x(), y(), float(sides), size(), rotation, color()))
        ops.append(('end',))
        add(f'random-{index}-{w}x{h}', w, h, ops, screen=(index % 6 == 0))
    return out


# -----------------------------------------------------------------------------
# C reference

C_PREFIX = r'''#include "raylib.h"
#include "rlgl.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static float bf(unsigned u) { float f; memcpy(&f, &u, 4); return f; }
static void hex(const unsigned char *p, int n) { for (int i = 0; i < n; i++) printf("%02x%02x%02x%02x", p[4*i], p[4*i + 1], p[4*i + 2], p[4*i + 3]); }
static void dump(int w, int h, int screen)
{
    unsigned char *p = malloc(w*h*4);
    rlCopyFramebuffer(0, 0, w, h, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, p);
    for (int i = 0; i < w*h; i++) { unsigned char t = p[4*i]; p[4*i] = p[4*i + 2]; p[4*i + 2] = t; }
    printf("F ");
    hex(p, w*h);
    if (screen)
    {
        Image image = LoadImageFromScreen();
        unsigned char *s = image.data, *q = malloc(w*h*4);
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++)
        {
            const unsigned char *src = s + ((h - 1 - y)*w + x)*4;
            unsigned char *dst = q + (y*w + x)*4;
            dst[0] = src[2]; dst[1] = src[1]; dst[2] = src[0]; dst[3] = src[3];
        }
        printf(" ");
        hex(q, w*h);
        for (int i = 0; i < w*h; i++) if (memcmp(q + 4*i, p + 4*i, 3) || q[4*i + 3] != 255) { printf(" MISMATCH"); break; }
        free(q);
        UnloadImage(image);
    }
    printf("\n");
    free(p);
}
int main(void)
{
    SetTraceLogLevel(LOG_NONE);
'''


def cf(value):
    return f'bf({word(value)}u)'


def cv(x, y):
    return f'(Vector2){{ {cf(x)}, {cf(y)} }}'


def crec(x, y, w, h):
    return f'(Rectangle){{ {cf(x)}, {cf(y)}, {cf(w)}, {cf(h)} }}'


def cc(color):
    return f'GetColor({color}u)'


def ci(value):
    return f'(int){cf(value)}'


def cpoints(points, name):
    return f'Vector2 {name}[] = {{ {", ".join(cv(x, y) for x, y in points)} }};'


def c_op(op, index):
    name, a = op[0], op[1:]
    calls = {
        'begin': lambda: 'BeginDrawing();', 'end': lambda: 'EndDrawing();', 'clear': lambda: f'ClearBackground({cc(a[0])});',
        'pixel': lambda: f'DrawPixel({ci(a[0])}, {ci(a[1])}, {cc(a[2])});',
        'pixel_v': lambda: f'DrawPixelV({cv(a[0], a[1])}, {cc(a[2])});',
        'line': lambda: f'DrawLine({ci(a[0])}, {ci(a[1])}, {ci(a[2])}, {ci(a[3])}, {cc(a[4])});',
        'line_v': lambda: f'DrawLineV({cv(a[0], a[1])}, {cv(a[2], a[3])}, {cc(a[4])});',
        'line_ex': lambda: f'DrawLineEx({cv(a[0], a[1])}, {cv(a[2], a[3])}, {cf(a[4])}, {cc(a[5])});',
        'line_strip': lambda: f'{{ {cpoints(a[0], "p")} DrawLineStrip(p, {len(a[0])}, {cc(a[1])}); }}',
        'rect': lambda: f'DrawRectangle({ci(a[0])}, {ci(a[1])}, {ci(a[2])}, {ci(a[3])}, {cc(a[4])});',
        'rect_v': lambda: f'DrawRectangleV({cv(a[0], a[1])}, {cv(a[2], a[3])}, {cc(a[4])});',
        'rect_rec': lambda: f'DrawRectangleRec({crec(*a[:4])}, {cc(a[4])});',
        'rect_pro': lambda: f'DrawRectanglePro({crec(*a[:4])}, {cv(a[4], a[5])}, {cf(a[6])}, {cc(a[7])});',
        'grad_v': lambda: f'DrawRectangleGradientV({ci(a[0])}, {ci(a[1])}, {ci(a[2])}, {ci(a[3])}, {cc(a[4])}, {cc(a[5])});',
        'grad_h': lambda: f'DrawRectangleGradientH({ci(a[0])}, {ci(a[1])}, {ci(a[2])}, {ci(a[3])}, {cc(a[4])}, {cc(a[5])});',
        'grad_ex': lambda: f'DrawRectangleGradientEx({crec(*a[:4])}, {cc(a[4])}, {cc(a[5])}, {cc(a[6])}, {cc(a[7])});',
        'rect_lines': lambda: f'DrawRectangleLines({ci(a[0])}, {ci(a[1])}, {ci(a[2])}, {ci(a[3])}, {cc(a[4])});',
        'rect_lines_ex': lambda: f'DrawRectangleLinesEx({crec(*a[:4])}, {cf(a[4])}, {cc(a[5])});',
        'tri': lambda: f'DrawTriangle({cv(a[0], a[1])}, {cv(a[2], a[3])}, {cv(a[4], a[5])}, {cc(a[6])});',
        'tri_lines': lambda: f'DrawTriangleLines({cv(a[0], a[1])}, {cv(a[2], a[3])}, {cv(a[4], a[5])}, {cc(a[6])});',
        'fan': lambda: f'{{ {cpoints(a[0], "p")} DrawTriangleFan(p, {len(a[0])}, {cc(a[1])}); }}',
        'strip': lambda: f'{{ {cpoints(a[0], "p")} DrawTriangleStrip(p, {len(a[0])}, {cc(a[1])}); }}',
        'circle': lambda: f'DrawCircle({ci(a[0])}, {ci(a[1])}, {cf(a[2])}, {cc(a[3])});',
        'circle_v': lambda: f'DrawCircleV({cv(a[0], a[1])}, {cf(a[2])}, {cc(a[3])});',
        'circle_lines': lambda: f'DrawCircleLines({ci(a[0])}, {ci(a[1])}, {cf(a[2])}, {cc(a[3])});',
        'circle_lines_v': lambda: f'DrawCircleLinesV({cv(a[0], a[1])}, {cf(a[2])}, {cc(a[3])});',
        'circle_gradient': lambda: f'DrawCircleGradient({cv(a[0], a[1])}, {cf(a[2])}, {cc(a[3])}, {cc(a[4])});',
        'sector': lambda: f'DrawCircleSector({cv(a[0], a[1])}, {cf(a[2])}, {cf(a[3])}, {cf(a[4])}, {ci(a[5])}, {cc(a[6])});',
        'sector_lines': lambda: f'DrawCircleSectorLines({cv(a[0], a[1])}, {cf(a[2])}, {cf(a[3])}, {cf(a[4])}, {ci(a[5])}, {cc(a[6])});',
        'ellipse': lambda: f'DrawEllipse({ci(a[0])}, {ci(a[1])}, {cf(a[2])}, {cf(a[3])}, {cc(a[4])});',
        'ellipse_v': lambda: f'DrawEllipseV({cv(a[0], a[1])}, {cf(a[2])}, {cf(a[3])}, {cc(a[4])});',
        'ellipse_lines': lambda: f'DrawEllipseLines({ci(a[0])}, {ci(a[1])}, {cf(a[2])}, {cf(a[3])}, {cc(a[4])});',
        'ellipse_lines_v': lambda: f'DrawEllipseLinesV({cv(a[0], a[1])}, {cf(a[2])}, {cf(a[3])}, {cc(a[4])});',
        'ring': lambda: f'DrawRing({cv(a[0], a[1])}, {cf(a[2])}, {cf(a[3])}, {cf(a[4])}, {cf(a[5])}, {ci(a[6])}, {cc(a[7])});',
        'poly': lambda: f'DrawPoly({cv(a[0], a[1])}, {ci(a[2])}, {cf(a[3])}, {cf(a[4])}, {cc(a[5])});',
        'poly_lines': lambda: f'DrawPolyLines({cv(a[0], a[1])}, {ci(a[2])}, {cf(a[3])}, {cf(a[4])}, {cc(a[5])});',
    }
    return '    ' + calls[name]()


def c_scene(scene):
    lines = [f'    InitWindow({scene["width"]}, {scene["height"]}, "");']
    lines += [c_op(op, i) for i, op in enumerate(scene['ops'])]
    lines += [f'    dump({scene["width"]}, {scene["height"]}, {int(scene["screen"])});', '    CloseWindow();']
    return '\n'.join(lines)


def c_trig():
    rows = [f'    {{ volatile float k = bf({DEG2RAD_BITS}u); for (int d = -360; d <= 360; d++) {{ volatile float a = k*(float)d; '
            'float c = cosf(a), s = sinf(a); unsigned uc, us; memcpy(&uc, &c, 4); memcpy(&us, &s, 4); printf("T %u %u\\n", uc, us); } }']
    return '\n'.join(rows)


# -----------------------------------------------------------------------------
# Bend candidate

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/frame.bend as FC
import ../../src/shapes.bend as S
import ../../src/trig.bend as Trig

def hex.digit(+d: U32) -> Char:
  Chr{Bool.pick(U32, (d < 10 : U32), (d + 48 : U32), (d + 87 : U32))}

def hex.word(+w: U32, rest: String) -> String:
  SCon{hex.digit((w >> 28n : U32)), SCon{hex.digit(((w >> 24n) .&. 15 : U32)), SCon{hex.digit(((w >> 20n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 16n) .&. 15 : U32)), SCon{hex.digit(((w >> 12n) .&. 15 : U32)), SCon{hex.digit(((w >> 8n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 4n) .&. 15 : U32)), SCon{hex.digit((w .&. 15 : U32)), rest}}}}}}}}

def hex.words(n: Nat, +i: U32, read: Array<U32> & U32, acc: String) -> String:
  match n read:
    case 0n _: acc
    case 1n+k Tuple{pixels, +w}: hex.words(k, (i - 1 : U32), Array.get(U32, pixels, (i - 1 : U32)), hex.word(w, acc))

def hex.pixels(+count: U32, pixels: J.Surface.Pixels) -> String:
  match pixels:
    case J.Words{values}: hex.words(U32.to_nat(count), (count - 1 : U32), Array.get(U32, values, (count - 1 : U32)), "")
    case J.Quads{_}: "quads"

def hex.surface(surface: J.Surface) -> String:
  J.Surface{+w, +h, _, pixels} = surface
  hex.pixels((w * h : U32), pixels)

def hex.maybe(surface: Maybe<J.Surface>) -> String:
  match surface:
    case None{}: "null"
    case Some{s}: hex.surface(s)

def screen.show(result: J.Frame & Maybe<J.Surface>) -> String:
  (_, surface) = result
  hex.maybe(surface)

def output.select(screen: Bool, +fb: String, frame: J.Frame) -> String:
  match screen:
    case False{}: fb
    case True{}: fb ++ " " ++ screen.show(J.Frame.load_image_from_screen(frame))

def output(+screen: Bool, result: J.Frame & Maybe<J.Surface>) -> String:
  (frame, surface) = result
  output.select(screen, hex.maybe(surface), frame)

def finish(+screen: Bool, frame: J.Frame) -> String:
  output(screen, J.Frame.framebuffer(frame))

def run(~scene: J.Frame -> J.Frame, +screen: Bool, frame: Maybe<J.Frame>) -> String:
  match frame:
    case None{}: "no frame"
    case Some{f}: finish(screen, scene(f))

def trig.pair(values: F32 & F32) -> String:
  (c, s) = values
  "1 " ++ U32.show(F32.bits(c)) ++ " " ++ U32.show(F32.bits(s))

def trig.bits(accepted: Bool, values: F32 & F32) -> String:
  match accepted:
    case False{}: "0"
    case True{}: trig.pair(values)

def trig.row(+gnu: Bool, +d: F32) -> String:
  +a = (S.deg2rad() * d : F32)
  trig.bits(S.trig.ok(gnu, a), Trig.sincos_for(gnu, a))

def trig.rows(n: Nat, +gnu: Bool, +d: F32) -> String:
  match n:
    case 0n: ""
    case 1n+k: trig.row(gnu, d) ++ ";" ++ trig.rows(k, gnu, (d + 1.0 : F32))
'''


def bf(value):
    return f'FC.float({word(value)})'


def bv(x, y):
    return f'M.Vector2{{{bf(x)}, {bf(y)}}}'


def brec(x, y, w, h):
    return f'J.Rectangle{{{bf(x)}, {bf(y)}, {bf(w)}, {bf(h)}}}'


def bpoints(points):
    return '[' + ', '.join(bv(x, y) for x, y in points) + ']'


def b_op(op, libm, frame):
    name, a = op[0], op[1:]
    lm = f'M.{libm}{{}}'
    calls = {
        'begin': lambda: f'J.Frame.begin_drawing({frame})', 'end': lambda: f'J.Frame.end_drawing({frame})',
        'clear': lambda: f'J.Frame.clear_background({frame}, {a[0]})',
        'pixel': lambda: f'J.Draw.pixel({frame}, {bf(a[0])}, {bf(a[1])}, {a[2]})',
        'pixel_v': lambda: f'J.Draw.pixel_v({frame}, {bv(a[0], a[1])}, {a[2]})',
        'line': lambda: f'J.Draw.line({frame}, {bf(a[0])}, {bf(a[1])}, {bf(a[2])}, {bf(a[3])}, {a[4]})',
        'line_v': lambda: f'J.Draw.line_v({frame}, {bv(a[0], a[1])}, {bv(a[2], a[3])}, {a[4]})',
        'line_ex': lambda: f'J.Draw.line_ex({frame}, {bv(a[0], a[1])}, {bv(a[2], a[3])}, {bf(a[4])}, {a[5]})',
        'line_strip': lambda: f'J.Draw.line_strip({frame}, {bpoints(a[0])}, {a[1]})',
        'rect': lambda: f'J.Draw.rectangle({frame}, {bf(a[0])}, {bf(a[1])}, {bf(a[2])}, {bf(a[3])}, {a[4]})',
        'rect_v': lambda: f'J.Draw.rectangle_v({frame}, {bv(a[0], a[1])}, {bv(a[2], a[3])}, {a[4]})',
        'rect_rec': lambda: f'J.Draw.rectangle_rec({frame}, {brec(*a[:4])}, {a[4]})',
        'rect_pro': lambda: f'J.Draw.rectangle_pro_for({lm}, {frame}, {brec(*a[:4])}, {bv(a[4], a[5])}, {bf(a[6])}, {a[7]})',
        'grad_v': lambda: f'J.Draw.rectangle_gradient_v({frame}, {bf(a[0])}, {bf(a[1])}, {bf(a[2])}, {bf(a[3])}, {a[4]}, {a[5]})',
        'grad_h': lambda: f'J.Draw.rectangle_gradient_h({frame}, {bf(a[0])}, {bf(a[1])}, {bf(a[2])}, {bf(a[3])}, {a[4]}, {a[5]})',
        'grad_ex': lambda: f'J.Draw.rectangle_gradient_ex({frame}, {brec(*a[:4])}, {a[4]}, {a[5]}, {a[6]}, {a[7]})',
        'rect_lines': lambda: f'J.Draw.rectangle_lines({frame}, {bf(a[0])}, {bf(a[1])}, {bf(a[2])}, {bf(a[3])}, {a[4]})',
        'rect_lines_ex': lambda: f'J.Draw.rectangle_lines_ex({frame}, {brec(*a[:4])}, {bf(a[4])}, {a[5]})',
        'tri': lambda: f'J.Draw.triangle({frame}, {bv(a[0], a[1])}, {bv(a[2], a[3])}, {bv(a[4], a[5])}, {a[6]})',
        'tri_lines': lambda: f'J.Draw.triangle_lines({frame}, {bv(a[0], a[1])}, {bv(a[2], a[3])}, {bv(a[4], a[5])}, {a[6]})',
        'fan': lambda: f'J.Draw.triangle_fan({frame}, {bpoints(a[0])}, {a[1]})',
        'strip': lambda: f'J.Draw.triangle_strip({frame}, {bpoints(a[0])}, {a[1]})',
        'circle': lambda: f'J.Draw.circle_for({lm}, {frame}, {bf(a[0])}, {bf(a[1])}, {bf(a[2])}, {a[3]})',
        'circle_v': lambda: f'J.Draw.circle_v_for({lm}, {frame}, {bv(a[0], a[1])}, {bf(a[2])}, {a[3]})',
        'circle_lines': lambda: f'J.Draw.circle_lines_for({lm}, {frame}, {bf(a[0])}, {bf(a[1])}, {bf(a[2])}, {a[3]})',
        'circle_lines_v': lambda: f'J.Draw.circle_lines_v_for({lm}, {frame}, {bv(a[0], a[1])}, {bf(a[2])}, {a[3]})',
        'circle_gradient': lambda: f'J.Draw.circle_gradient_for({lm}, {frame}, {bv(a[0], a[1])}, {bf(a[2])}, {a[3]}, {a[4]})',
        'sector': lambda: f'J.Draw.circle_sector_for({lm}, {frame}, {bv(a[0], a[1])}, {bf(a[2])}, {bf(a[3])}, {bf(a[4])}, {bf(a[5])}, {a[6]})',
        'sector_lines': lambda: f'J.Draw.circle_sector_lines_for({lm}, {frame}, {bv(a[0], a[1])}, {bf(a[2])}, {bf(a[3])}, {bf(a[4])}, {bf(a[5])}, {a[6]})',
        'ellipse': lambda: f'J.Draw.ellipse_for({lm}, {frame}, {bf(a[0])}, {bf(a[1])}, {bf(a[2])}, {bf(a[3])}, {a[4]})',
        'ellipse_v': lambda: f'J.Draw.ellipse_v_for({lm}, {frame}, {bv(a[0], a[1])}, {bf(a[2])}, {bf(a[3])}, {a[4]})',
        'ellipse_lines': lambda: f'J.Draw.ellipse_lines_for({lm}, {frame}, {bf(a[0])}, {bf(a[1])}, {bf(a[2])}, {bf(a[3])}, {a[4]})',
        'ellipse_lines_v': lambda: f'J.Draw.ellipse_lines_v_for({lm}, {frame}, {bv(a[0], a[1])}, {bf(a[2])}, {bf(a[3])}, {a[4]})',
        'ring': lambda: f'J.Draw.ring_for({lm}, {frame}, {bv(a[0], a[1])}, {bf(a[2])}, {bf(a[3])}, {bf(a[4])}, {bf(a[5])}, {bf(a[6])}, {a[7]})',
        'poly': lambda: f'J.Draw.poly_for({lm}, {frame}, {bv(a[0], a[1])}, {bf(a[2])}, {bf(a[3])}, {bf(a[4])}, {a[5]})',
        'poly_lines': lambda: f'J.Draw.poly_lines_for({lm}, {frame}, {bv(a[0], a[1])}, {bf(a[2])}, {bf(a[3])}, {bf(a[4])}, {a[5]})',
    }
    return calls[name]()


def b_scene(index, scene, libm):
    lines = [f'def scene.{index}(f0: J.Frame) -> J.Frame:']
    ops = [op if op[-1] != 'undefined' else op[:-1] for op in scene['ops']]
    for k, op in enumerate(ops):
        lines.append(f'  f{k + 1} = {b_op(op, libm, f"f{k}")}')
    lines.append(f'  f{len(ops)}')
    return '\n'.join(lines)


def render(libm):
    def build(selected, gpu):
        body = [PROGRAM]
        prints = []
        for kind, index, item in selected:
            if kind == 'trig':
                prints.append(f'    IO.print("T;" ++ trig.rows(721n, {"True" if libm != "AppleLibm" else "False"}{{}}, F32.neg(360.0)))')
                continue
            body.append(b_scene(index, item, libm))
            screen = 'True{}' if item['screen'] else 'False{}'
            prints.append(f'    IO.print(run(~scene.{index}, {screen}, J.Frame.init_window({item["width"]}, {item["height"]})))')
        body.append('def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(prints) + '\n')
        return '\n\n'.join(body)
    return build


# -----------------------------------------------------------------------------
# Self-checks

def fused_instructions(library):
    """Fused multiply-add instructions per archive object (the reference must have none)."""
    import tempfile
    import os
    directory = tempfile.mkdtemp(prefix='frame-objects-', dir=ROOT / '.build')
    probekit.run(['ar', 'x', library], cwd=directory)
    counts = {}
    darwin = platform.system() == 'Darwin'
    pattern = re.compile(r'\b(fmadd|fmsub|fnmadd|fnmsub|fmla|fmls)\b' if platform.machine() in ('arm64', 'aarch64')
                         else r'\bvf(n)?m(add|sub)\w*')
    for name in sorted(os.listdir(directory)):
        if not name.endswith('.o'):
            continue
        text = probekit.run(['otool', '-tv', name] if darwin else ['objdump', '-d', name], cwd=directory)
        counts[name] = len(pattern.findall(text))
    return counts


def font_words(raylib_source):
    source = (raylib_source / 'src/rtext.c').read_text()
    start = source.index('unsigned int defaultFontData[512]')
    return [int(w, 16) for w in re.findall(r'0x[0-9a-fA-F]+', source[start:source.index('};', start)])]


def bend_font_words():
    text = (ROOT / 'src/frame_font.bend').read_text()
    return [int(v) for line in re.findall(r'case \S+: \[([^\]]*)\]', text) for v in line.split(',')]


# -----------------------------------------------------------------------------
# Benchmark

BENCH_C = r'''
#include <time.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec*1e-9; }
'''


def bench_ops():
    rng = random.Random(0xBE7C)
    ops = [('begin',), ('clear', C(245, 245, 245))]
    for k in range(100):
        color = C(rng.randrange(256), rng.randrange(256), rng.randrange(256), rng.choice((255, 255, 160)))
        if k % 2 == 0:
            ops.append(('rect_rec', f32(rng.uniform(-20, 620)), f32(rng.uniform(-20, 460)), f32(rng.uniform(10, 120)), f32(rng.uniform(10, 90)), color))
        else:
            ops.append(('circle_v', f32(rng.uniform(0, 640)), f32(rng.uniform(0, 480)), f32(rng.uniform(5, 60)), color))
    ops.append(('end',))
    return ops


BENCH_BEND = '''def bench.sum(n: Nat, +i: U32, +acc: U32, read: Array<U32> & U32) -> U32:
  match n read:
    case 0n _: acc
    case 1n+k Tuple{pixels, +w}: bench.sum(k, (i + 1 : U32), (acc + w * (i + 1) : U32), Array.get(U32, pixels, (i + 1 : U32)))

def bench.pixels(pixels: J.Surface.Pixels) -> String:
  match pixels:
    case J.Words{values}: U32.show(bench.sum(307200n, 0, 0, Array.get(U32, values, 0)))
    case J.Quads{_}: "quads"

def bench.words(surface: J.Surface) -> String:
  J.Surface{_, _, _, pixels} = surface
  bench.pixels(pixels)

def bench.surface(surface: Maybe<J.Surface>) -> String:
  match surface:
    case None{}: "null"
    case Some{s}: bench.words(s)

def bench.done(result: J.Frame & Maybe<J.Surface>) -> String:
  (_, surface) = result
  bench.surface(surface)

def bench(frame: Maybe<J.Frame>) -> String:
  match frame:
    case None{}: "no frame"
    case Some{f}: bench.done(J.Frame.framebuffer(DRAW))

'''


def time_lanes(executable, script, expected):
    timings = {}
    for lane, command in (('cpu-1', [executable, '--gpu', 'off', '--threads', '1']),
                          ('cpu-2', [executable, '--gpu', 'off', '--threads', '2']),
                          ('javascript', ['bun', script])):
        best = None
        for _ in range(3):
            start = time.perf_counter()
            output = probekit.run(command).strip()
            elapsed = time.perf_counter() - start
            if output != expected:
                raise ProbeFailure(f'frame benchmark: {lane} checksum {output[:80]}, reference {expected}')
            best = elapsed if best is None else min(best, elapsed)
        timings[lane] = best
    return timings


def benchmark(probe, libm):
    """Best-of-N wall times; Jonlib's include process start, frame creation and a checksum readback,
    so a frame that is only created and read is timed too and subtracted."""
    ops = bench_ops()
    scene = dict(id='bench', width=640, height=480, ops=ops, screen=False)
    checksum = ('    { unsigned char *p = malloc(640*480*4); rlCopyFramebuffer(0, 0, 640, 480, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, p);\n'
                '      unsigned s = 0; for (unsigned i = 0; i < 640*480; i++) s += (((unsigned)p[4*i + 2] << 24) | ((unsigned)p[4*i + 1] << 16)'
                ' | ((unsigned)p[4*i] << 8) | p[4*i + 3])*(i + 1);\n      printf("%s %u\\n", LABEL, s); free(p); }\n')
    body = C_PREFIX.replace('int main(void)', BENCH_C + 'int main(void)')
    body += '    InitWindow(640, 480, "");\n' + checksum.replace('LABEL', '"E"') + '    double best = 1e9;\n'
    body += '    for (int r = 0; r < 20; r++) { double t0 = now();\n' + '\n'.join(c_op(op, i) for i, op in enumerate(ops)) + '\n'
    body += '    double t = now() - t0; if (t < best) best = t; }\n    printf("B %.9f\\n", best);\n'
    body += checksum.replace('LABEL', '"H"') + '    CloseWindow();\n    return 0;\n}\n'
    native = probe.native(body, 'bench-reference', extra_flags=('-ffp-contract=off',))
    native_seconds = float(re.search(r'^B (\S+)', native, re.M).group(1))
    drawn, empty = re.search(r'^H (\d+)', native, re.M).group(1), re.search(r'^E (\d+)', native, re.M).group(1)
    cli = ['bun', probe.args.bend_source / 'bend2/main.ts']
    timings = {}
    for name, draw, expected in (('bench', 'scene.0(f)', drawn), ('bench-empty', 'f', empty)):
        source = render(libm)([('scene', 0, scene)], False)
        source = source.replace('    IO.print(run(~scene.0, False{}, J.Frame.init_window(640, 480)))', '    IO.print(bench(J.Frame.init_window(640, 480)))')
        source = source.replace('def main()', BENCH_BEND.replace('DRAW', draw) + 'def main()')
        (probe.work / f'{name}.bend').write_text(source)
        probekit.compile_outputs(cli, probe.work / f'{name}.bend', probe.work / name, probe.work / f'{name}.js')
        timings[name] = time_lanes(probe.work / name, probe.work / f'{name}.js', expected)
    report = dict(native_rlsw_seconds=native_seconds, jonlib_seconds=timings['bench'], empty_frame_seconds=timings['bench-empty'],
                  machine=platform.machine(), system=platform.system(), shapes=100, size='640x480', checksum=drawn)
    (probe.work / 'benchmark.json').write_text(json.dumps(report, indent=2) + '\n')
    probe.diagnostic(native_ms=round(native_seconds * 1000, 3),
                     **{f'{lane}_ms': round(t * 1000, 1) for lane, t in timings['bench'].items()},
                     **{f'{lane}_empty_ms': round(t * 1000, 1) for lane, t in timings['bench-empty'].items()})


# -----------------------------------------------------------------------------

def configure(parser):
    parser.add_argument('--benchmark', action='store_true', help='time a 640x480 frame instead of comparing (diagnostic)')


def main():
    args = probekit.arguments(__doc__, configure)
    probe = probekit.Probe('frame-benchmark' if args.benchmark else 'frame', args, raylib_options=OPTIONS)
    libm = gradient_reference()
    fused = fused_instructions(probe.library)
    if any(count for name, count in fused.items()):
        raise ProbeFailure(f'frame: the reference build contains fused multiply-adds: {fused}')
    if args.benchmark:
        benchmark(probe, libm)
        return
    if font_words(args.raylib_source) != bend_font_words():
        raise ProbeFailure('frame: src/frame_font.bend differs from the pinned rtext.c defaultFontData')

    items = scenes()
    native_items = [s for s in items if not any(refused(op, libm) for op in s['ops'])]
    contracts = [s for s in items if s not in native_items]
    source = C_PREFIX + '\n'.join(c_scene(s) for s in native_items) + '\n' + c_trig() + '\n    return 0;\n}\n'
    output = [line for line in probe.native(source, 'reference', extra_flags=('-ffp-contract=off',)).splitlines() if line[:2] in ('F ', 'T ')]
    frames = [line[2:] for line in output if line.startswith('F ')]
    trig = [line[2:] for line in output if line.startswith('T ')]
    if len(frames) != len(native_items) or len(trig) != 721:
        raise ProbeFailure(f'frame: reference printed {len(frames)} frames and {len(trig)} trig rows')
    expected_by_id = {}
    for scene, line in zip(native_items, frames):
        parts = line.split()
        if 'MISMATCH' in parts or len(parts) != 1 + scene['screen']:
            raise ProbeFailure(f'frame: {scene["id"]}: LoadImageFromScreen is not the flipped, swapped, opaque framebuffer')
        expected_by_id[scene['id']] = ' '.join(parts)
    for scene in contracts:
        expected_by_id[scene['id']] = 'null' + (' null' if scene['screen'] else '')
    expected = [expected_by_id[s['id']] for s in items]
    trig_expected = 'T;' + ''.join(
        (f'1 {row}' if accepted(libm, f32(DEG2RAD * d)) else '0') + ';' for d, row in zip(range(-360, 361), trig))
    actions = [('scene', i, s) for i, s in enumerate(items)] + [('trig', len(items), None)]
    lanes = probe.candidates(render(libm), actions, batch=12, parse=lambda text, selected: [line for line in text.splitlines() if line.strip()])
    probe.compare(expected + [trig_expected], lanes,
                  describe=lambda i: f'scene {items[i]["id"]}' if i < len(items) else 'trig table')
    probe.finish(scenes=len(items), compared=len(native_items), contracts=len(contracts), libm=libm,
                 operations=sum(len(s['ops']) for s in items), trig_arguments=sum(accepted(libm, f32(DEG2RAD * d)) for d in range(-360, 361)),
                 fused_free_objects=len(fused),
                 scenes_sha256=hashlib.sha256(json.dumps(items, default=repr).encode()).hexdigest())


if __name__ == '__main__':
    main()
