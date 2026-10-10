#!/usr/bin/env python3
"""Compare Jonlib's remaining rshapes.c shapes, the shapes texture and the
rlgl immediate-mode API with raylib's software renderer.

Same reference as tools/frame_probe.py and tools/texture_probe.py: pinned
raylib on PLATFORM=Memory (rlgl.h's OpenGL 1.1 path into src/external/rlsw.h)
built with CMAKE_C_FLAGS=-ffp-contract=off, read back with rlCopyFramebuffer.
Each scene runs InitWindow and a sequence of operations: the texture probe's
shapes, textures and render textures, plus DrawLineBezier, DrawLineDashed,
DrawRingLines, DrawPolyLinesEx, DrawRectangleRounded(Lines)(Ex), every
DrawSpline* function, DrawCircleSector(Lines)/DrawRing with segment
estimation, SetShapesTexture/GetShapesTexture(Rectangle), and rlBegin/rlEnd,
rlVertex2i/2f/3f, rlTexCoord2f, rlNormal3f, rlColor4ub/3f/4f, rlSetTexture,
rlMatrixMode with the projection and texture stacks, rlOrtho, rlFrustum,
rlViewport, the blend/depth/cull/scissor/wire/point toggles, rlSetCullFace,
rlScissor, rlSetLineWidth/rlGetLineWidth, rlSetPointSize/rlGetPointSize,
rlClearColor/rlClearScreenBuffers, the matrix and state getters and the
OpenGL 3.3-only calls that do nothing on the software renderer. Getter
results (F32 bits, ids) are appended to the scene's row.

Three tables check the numerical profiles the shapes rely on: the host
powf(x, 3) against Jonlib's glibc 2.39 powf on the 48 arguments
DrawSplineSegmentBezierCubic uses (t = i/24 and 1 - t); the host cosf
against Jonlib's sine/cosine kernel on the 4094 DrawPolyLinesEx inner-radius
arguments (sides 3..4096); and rshapes.c's segment estimate (acosf from the
unmodified glibc 2.39 e_acosf.c, tools/reference/acos_sources, with
powf(x, 2) compiled as x*x: compilers fold that call, and the probe checks
with objdump that the reference rshapes.o functions estimating segments call
acosf and never powf) against Jonlib's Glibc239Libm estimate for arcs and
rounded-rectangle corners.

Contracts (Jonlib must answer null): segment estimates outside the glibc 2.39
profile, an infinite DrawLineDashed loop, rlOrtho/rlFrustum arguments
outside the exact binary32 domain, popping the last projection or texture
matrix, line widths above 4096 and NaN point sizes, and thick lines or points
reaching outside the color buffer. CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import math
import random
import struct
from fractions import Fraction

from conformance import gradient_reference
import frame_probe as fp
import probekit
import quaternion_angle_probe as qa
import texture_probe as tp
from probekit import ProbeFailure

C = fp.C
f32 = fp.f32
cf = fp.cf
cc = fp.cc
bf = fp.bf
DEG2RAD = fp.DEG2RAD

RED, GREEN, BLUE, WHITE, BLACK = C(230, 41, 55), C(0, 228, 48), C(0, 121, 241), C(255, 255, 255), C(0, 0, 0)
HALF = [C(255, 0, 0, 128), C(0, 255, 0, 64), C(0, 0, 255, 200), C(255, 255, 0, 1), C(17, 34, 51, 254)]
TRANS_BG = C(255, 128, 128, 100)
NONE = 9

TOGGLES = {'blend': 0, 'depth': 1, 'cull': 2, 'scissor': 3, 'wire': 4, 'point': 5, 'smooth': 6, 'depth_mask': 7, 'stereo': 8}
C_TOGGLES = {0: ('rlEnableColorBlend', 'rlDisableColorBlend'), 1: ('rlEnableDepthTest', 'rlDisableDepthTest'),
             2: ('rlEnableBackfaceCulling', 'rlDisableBackfaceCulling'), 3: ('rlEnableScissorTest', 'rlDisableScissorTest'),
             4: ('rlEnableWireMode', 'rlDisableWireMode'), 5: ('rlEnablePointMode', 'rlDisablePointMode'),
             6: ('rlEnableSmoothLines', 'rlDisableSmoothLines'), 7: ('rlEnableDepthMask', 'rlDisableDepthMask'),
             8: ('rlEnableStereoRender', 'rlDisableStereoRender')}
GETTERS = ('line_width', 'point_size', 'modelview', 'projection', 'framebuffer', 'version', 'misc')


# -----------------------------------------------------------------------------
# Contract rules (mirror docs/RLGL.md and src/shapes.bend)

def rad(angle):
    return f32(DEG2RAD * angle)


def corner_args(segments, quads):
    """Rounded-rectangle corner arguments: sector quads (DrawRectangleRounded) or one quad/line per segment."""
    step = f32(90.0 / segments)
    out = []
    for start in (180.0, 270.0, 0.0, 90.0):
        angle = start
        if quads:
            for _ in range(segments // 2):
                out += [rad(f32(angle + f32(step * 2.0))), rad(f32(angle + step)), rad(angle)]
                angle = f32(angle + f32(step * 2.0))
            if segments % 2:
                out += [rad(f32(angle + step)), rad(angle)]
        else:
            for _ in range(segments):
                out += [rad(angle), rad(f32(angle + step))]
                angle = f32(angle + step)
    return out


def arc_segments(start, end, segments, libm):
    """(start, end, segments) of an arc, [] when empty, None when refused for this host."""
    if start == end:
        return []
    if end < start:
        start, end = end, start
    span = f32(end - start)
    minimum = math.ceil(f32(span / 90.0)) if math.isfinite(span) else None
    if minimum is None or fp.c_int(segments) is None:
        return None
    n = fp.c_int(segments)
    if n < minimum:
        return None if libm != 'Glibc239Libm' else 'estimated'
    if n > 4096:
        return None
    return start, end, n


def stepped(start, end, n):
    step = f32(f32(end - start) / n)
    angle, args = start, [rad(start)]
    for _ in range(n):
        args += [rad(angle), rad(f32(angle + step))]
        angle = f32(angle + step)
    return args + [rad(angle)]


def dashed_count(x0, y0, x1, y1, dash, space):
    """Iterations of DrawLineDashed's loop (None when it does not end within 4096)."""
    dx, dy = f32(x1 - x0), f32(y1 - y0)
    length = f32(math.sqrt(f32(f32(dx * dx) + f32(dy * dy))))
    d, s = int(dash), int(space)
    if length < f32(d + s) or d <= 0 or math.isnan(length):
        return 0
    done, count = 0.0, 0
    while done < length:
        count += 1
        if count > 4096:
            return None
        stop = f32(done + d)
        stop = length if stop > length else stop
        done = f32(stop + s)
    return count


def exact_difference(a, b):
    return math.isfinite(a) and math.isfinite(b) and math.isfinite(f32(a - b)) and Fraction(a) - Fraction(b) == Fraction(f32(a - b))


def exact_product(a, b):
    p = f32(a * b)
    return (abs(a) < 2.0 ** 100 and abs(b) < 2.0 ** 100 and (p == 0 or abs(p) >= 2.0 ** -100)
            and Fraction(a) * Fraction(b) == Fraction(p))


def projection_ok(name, l, r, b, t, n, f):
    ok = exact_difference(r, l) and exact_difference(t, b) and exact_difference(f, n)
    if name == 'frustum':
        ok = ok and exact_product(f, n) and math.isfinite(f32(n * 2.0)) and math.isfinite(f32(f32(f * n) * 2.0))
    return ok


def op_refused(op, libm):
    """Whether Jonlib refuses this operation on this host (declared contracts and libm profile)."""
    name, a = op[0], op[1:]
    args = []
    if name == 'ring_lines':
        inner, outer, start, end, segments = a[2:7]
        if outer < inner:
            inner, outer = outer, (0.1 if inner <= 0.0 else inner)
        plan = arc_segments(start, end, segments, libm)
        if plan is None:
            return True
        if plan and plan != 'estimated':
            args = fp.sector_args(*plan) if False else (stepped(*plan) if inner > 0.0 else fp.stepped_args(start, end, segments))
    elif name in ('sector2', 'sector_lines2', 'ring2'):
        start, end, segments = (a[3], a[4], a[5]) if name != 'ring2' else (a[4], a[5], a[6])
        plan = arc_segments(start, end, segments, libm)
        if plan is None:
            return True
        if plan and plan != 'estimated':
            if name == 'sector2':
                args = fp.sector_args(start, end, segments)
            elif name == 'sector_lines2':
                args = fp.stepped_args(start, end, segments)
            else:
                inner, outer = (a[3], a[2]) if a[3] < a[2] else (a[2], a[3])
                args = fp.sector_args(start, end, segments) if inner <= 0.0 else fp.stepped_args(start, end, segments)
    elif name == 'poly_ex':
        sides = fp.c_int(a[2])
        if sides is None or max(sides, 3) > 4096:
            return True
        args = fp.poly_args(a[2], a[4])
    elif name in ('rounded', 'rounded_lines', 'rounded_lines_ex'):
        x, y, w, h, roundness, segments = a[:6]
        thick = a[6] if name == 'rounded_lines_ex' else 1.0
        if roundness <= 0.0:
            return False
        roundness = 1.0 if roundness >= 1.0 else roundness
        radius = f32(f32(h * roundness) / 2.0) if w > h else f32(f32(w * roundness) / 2.0)
        if radius <= 0.0:
            return False
        n = fp.c_int(segments)
        if n is None:
            return True
        if n < 4:
            return libm != 'Glibc239Libm'
        if n > 4096:
            return True
        args = corner_args(n, name == 'rounded')
    elif name in ('spline', 'segment'):
        if a[0] == 4 and libm == 'Glibc241Libm':
            return True
        if name == 'spline' and a[0] in (1, 2):
            args = fp.circle_args()
    elif name == 'dashed':
        if dashed_count(*a[:6]) is None:
            return True
    elif name in ('ortho', 'frustum'):
        return not projection_ok(name, *a)
    elif name == 'line_width':
        return fp.f32(math.floor(abs(a[0]) + 0.5) * (1 if a[0] >= 0 else -1)) > 4096
    elif name == 'point_size':
        r = math.floor(f32(a[0] * 0.5)) if math.isfinite(a[0]) else float('nan')
        return math.isnan(r) or abs(r) > 4096
    elif name in ('poly2',):
        args = fp.poly_args(a[2], a[4])
    if args is None:
        return True
    return not all(fp.accepted(libm, x) for x in args)


def refused(scene, libm):
    if scene.get('contract'):
        return True
    if any(op[0] in tp.SHAPE_OPS + ('mode2d', 'rotate') and tp.refused(dict(ops=[op], contract=False), libm) for op in scene['ops']):
        return True
    return any(op_refused(op, libm) for op in scene['ops'])


# -----------------------------------------------------------------------------
# Scenes

def scenes():
    rng = random.Random(0x41617)
    out = []

    def add(name, width, height, ops, screen=False, contract=False):
        out.append(dict(id=name, width=width, height=height, ops=ops, screen=screen, contract=contract))

    pts = lambda *xy: [(f32(xy[i]), f32(xy[i + 1])) for i in range(0, len(xy), 2)]

    # DrawLineBezier and DrawLineDashed.
    add('line-bezier', 32, 24, [('begin',), ('clear', C(20, 20, 30)), ('bezier', 2.0, 3.0, 29.0, 20.0, 3.0, RED),
                                ('bezier', 30.0, 2.0, 1.5, 21.5, 1.0, HALF[2]), ('bezier', 4.0, 12.0, 4.0, 12.0, 2.0, WHITE),
                                ('bezier', 5.25, 20.75, 26.5, 20.75, 4.5, HALF[0]), ('end',)])
    add('line-dashed', 32, 24, [('begin',), ('clear', BLACK), ('dashed', 1.0, 1.0, 30.0, 22.0, 3.0, 2.0, WHITE),
                                ('dashed', 2.5, 20.5, 29.5, 3.25, 1.0, 1.0, HALF[0]), ('dashed', 3.0, 5.0, 8.0, 5.0, 4.0, 4.0, GREEN),
                                ('dashed', 1.0, 12.0, 30.0, 12.0, 0.0, 3.0, BLUE), ('dashed', 1.0, 14.0, 30.0, 14.0, 5.0, 1.0, RED),
                                ('dashed', 28.0, 18.0, 2.0, 18.0, 7.0, 0.0, HALF[2]), ('end',)])
    add('line-dashed-endless', 16, 12, [('dashed', 1.0, 1.0, 14.0, 10.0, 2.0, -2.0, WHITE)])
    add('line-dashed-nan', 16, 12, [('begin',), ('clear', BLACK), ('dashed', float('nan'), 1.0, 14.0, 10.0, 2.0, 1.0, WHITE), ('end',)])

    # Ring outlines, polygon outlines with thickness, sectors with estimated segments.
    add('ring-lines', 33, 25, [('begin',), ('clear', C(240, 240, 240)), ('ring_lines', 16.0, 12.0, 4.0, 9.0, 0.0, 360.0, 12.0, RED),
                               ('ring_lines', 8.0, 8.0, 6.0, 3.0, 90.0, 270.0, 6.0, HALF[2]), ('ring_lines', 24.0, 16.0, 0.0, 6.0, 30.0, 150.0, 4.0, BLUE),
                               ('ring_lines', 25.0, 6.0, -2.0, -1.0, 0.0, 90.0, 3.0, GREEN), ('ring_lines', 12.0, 18.0, 2.0, 5.0, 10.0, 10.0, 4.0, BLACK),
                               ('ring_lines', 6.5, 19.5, 1.5, 4.5, 200.0, 20.0, 9.0, HALF[0]), ('end',)])
    add('poly-lines-ex', 40, 30, [('begin',), ('clear', C(30, 30, 30)), ('poly_ex', 10.0, 10.0, 6.0, 8.0, -30.0, 2.0, RED),
                                  ('poly_ex', 28.0, 10.0, 3.0, 7.0, -120.0, 3.5, HALF[2]), ('poly_ex', 10.0, 22.0, 5.0, 6.0, -120.0, 1.0, GREEN),
                                  ('poly_ex', 30.0, 22.0, 4.0, 7.5, -90.0, 10.0, HALF[0]), ('poly_ex', 20.0, 15.0, 2.0, 4.0, -180.0, -1.0, WHITE),
                                  ('poly_ex', 20.0, 15.0, 6.0, 3.0, -360.0, 1.0, BLUE), ('end',)])
    add('poly-lines-ex-sides', 16, 12, [('poly_ex', 8.0, 6.0, 5000.0, 3.0, 0.0, 1.0, WHITE)])
    add('arc-estimate', 40, 30, [('begin',), ('clear', BLACK), ('sector2', 12.0, 12.0, 8.0, 0.0, 300.0, 1.0, RED),
                                 ('sector_lines2', 28.0, 12.0, 7.0, 45.0, 315.0, 0.0, WHITE), ('ring2', 12.0, 24.0, 2.0, 5.0, 0.0, 360.0, 2.0, HALF[2]),
                                 ('ring_lines', 28.0, 24.0, 2.5, 5.5, 10.0, 350.0, -4.0, GREEN), ('sector2', 20.0, 15.0, 0.6, 0.0, 180.0, 1.0, BLUE),
                                 ('end',)])
    add('arc-estimate-small-radius', 16, 12, [('sector2', 8.0, 6.0, -1.0, 0.0, 360.0, 0.0, RED)], contract=True)

    # Rounded rectangles.
    for k, segs in enumerate((5.0, 6.0, 9.0, 10.0, 18.0, 2.0)):
        ops = [('begin',), ('clear', (C(250, 250, 250), TRANS_BG)[k % 2]),
               ('rounded', 2.0, 2.0, 20.0, 12.0, 0.5, segs, RED), ('rounded', 24.5, 2.5, 13.0, 18.0, 1.0, segs, HALF[2]),
               ('rounded', 3.0, 17.0, 16.0, 10.0, 0.0, segs, GREEN), ('rounded', 2.0, 30.0, 12.0, 6.0, 0.25, segs, HALF[0]),
               ('rounded_lines', 20.0, 24.0, 18.0, 12.0, 0.6, segs, BLUE), ('rounded_lines_ex', 4.0, 40.0, 30.0, 10.0, 0.8, segs, 3.0, HALF[1]),
               ('rounded_lines_ex', 26.0, 2.0, 12.0, 0.0, 0.5, segs, 2.0, WHITE), ('rounded_lines_ex', 6.0, 30.5, 8.0, 5.0, 0.0, segs, 1.5, RED),
               ('rounded_lines_ex', 20.0, 40.0, 16.0, 9.0, 0.5, segs, -1.0, BLACK), ('end',)]
        add(f'rounded-{int(segs)}', 40, 52, ops)

    # Splines.
    zig = pts(2, 20, 6, 4, 12, 22, 18, 3, 24, 21, 30, 6, 36, 18)
    add('spline-linear', 40, 26, [('begin',), ('clear', BLACK), ('spline', 0, zig, 2.0, HALF[0]), ('spline', 0, pts(3, 3, 3, 3, 20, 10), 3.0, WHITE),
                                  ('spline', 0, pts(5, 23), 2.0, RED), ('spline', 0, pts(30, 2, 38, 2, 38, 10, 30, 10), 1.0, GREEN), ('end',)])
    add('spline-basis', 40, 26, [('begin',), ('clear', C(10, 20, 30)), ('spline', 1, zig, 3.0, HALF[2]),
                                 ('spline', 1, pts(4, 4, 10, 10, 16, 4, 22, 10, 28, 4), 1.0, WHITE), ('spline', 1, pts(1, 1, 2, 2, 3, 3), 2.0, RED), ('end',)])
    add('spline-catmull', 40, 26, [('begin',), ('clear', C(10, 20, 30)), ('spline', 2, zig, 2.0, HALF[0]),
                                   ('spline', 2, pts(4, 22, 12, 6, 20, 22, 28, 6), 1.0, GREEN), ('end',)])
    add('spline-quadratic', 40, 26, [('begin',), ('clear', BLACK), ('spline', 3, zig, 2.5, HALF[1]), ('spline', 3, pts(3, 3, 20, 25, 37, 3, 37, 3), 1.0, WHITE),
                                     ('end',)])
    add('spline-cubic', 40, 26, [('begin',), ('clear', BLACK), ('spline', 4, zig, 2.0, HALF[2]),
                                 ('spline', 4, pts(2, 2, 2, 24, 38, 2, 38, 24, 20, 13, 5, 13, 20, 1), 1.5, RED), ('end',)])
    add('spline-segments', 40, 30, [('begin',), ('clear', C(240, 240, 240)), ('segment', 0, pts(2, 2, 37, 6), 3.0, RED),
                                    ('segment', 1, pts(2, 26, 10, 6, 28, 26, 38, 10), 2.0, BLUE), ('segment', 2, pts(2, 14, 8, 2, 30, 28, 38, 14), 1.5, HALF[0]),
                                    ('segment', 3, pts(4, 26, 20, -6, 36, 26), 2.0, GREEN), ('segment', 4, pts(3, 10, 12, 28, 26, 0, 37, 18), 2.5, HALF[2]),
                                    ('segment', 0, pts(5, 5, 5, 5), 2.0, BLACK), ('end',)])

    # The shapes texture.
    spec = tp.image(8, 8, 7, 1201)
    shapes = [('rect', 2.0, 2.0, 10.0, 6.0, WHITE), ('circle_v', 20.0, 8.0, 5.0, HALF[0]), ('tri', 3.0, 12.0, 3.0, 22.0, 14.0, 22.0, C(200, 255, 200)),
              ('pixel_v', 26.5, 18.5, RED), ('poly2', 24.0, 20.0, 6.0, 4.0, -30.0, WHITE), ('rounded', 15.0, 14.0, 8.0, 8.0, 0.5, 6.0, HALF[2])]
    add('shapes-texture-user', 32, 26, [('begin',), ('clear', C(40, 40, 60)), ('load', 0, spec), ('shapes_info',),
                                        ('shapes_tex', 0, (1.0, 2.0, 4.0, 5.0), NONE), ('shapes_info',)] + shapes + [('end',)])
    add('shapes-texture-reset', 32, 26, [('begin',), ('clear', C(40, 40, 60)), ('load', 0, spec), ('shapes_tex', 0, (0.0, 0.0, 8.0, 8.0), NONE),
                                         ('shapes_tex', NONE, (0.0, 0.0, 1.0, 1.0), 1), ('shapes_info',)] + shapes
            + [('load', 2, tp.image(4, 4, 7, 77, True)), ('filter', 2, 1), ('shapes_tex', 2, (0.0, 0.0, 0.0, 4.0), NONE), ('shapes_info',),
               ('shapes_tex', 2, (0.5, 0.5, 3.0, 3.0), 3), ('shapes_info',), ('rect', 1.0, 20.0, 30.0, 5.0, WHITE), ('end',)])
    add('shapes-texture-opaque', 24, 16, [('begin',), ('clear', TRANS_BG), ('load', 1, tp.image(4, 4, 4, 55)), ('shapes_tex', 1, (0.0, 0.0, 4.0, 4.0), NONE),
                                          ('rect', 1.0, 1.0, 10.0, 10.0, WHITE), ('rect', 12.0, 2.0, 10.0, 10.0, HALF[0]),
                                          ('circle_v', 17.0, 10.0, 4.0, C(255, 255, 255, 250)), ('end',)])

    # rlgl immediate mode.
    add('rl-immediate', 32, 24, [('begin',), ('clear', BLACK),
                                 ('rl_begin', 4), ('c4ub', 255, 0, 0, 255), ('v2f', 2.0, 2.0), ('c4ub', 0, 255, 0, 255), ('v2f', 2.0, 20.0),
                                 ('c4ub', 0, 0, 255, 255), ('v2f', 20.0, 20.0), ('c3f', 1.0, 1.0, 0.0), ('v2i', 22.0, 2.0), ('v2i', 22.0, 12.0),
                                 ('v2i', 30.0, 12.0), ('rl_end',),
                                 ('rl_begin', 1), ('c4f', 1.0, 1.0, 1.0, 0.5), ('v2f', 1.0, 22.0), ('v2f', 30.0, 15.0), ('normal', 0.0, 0.0, 1.0),
                                 ('c4ub', 300, 128, 64, 255), ('v2f', 25.0, 2.0), ('v2f', 25.0, 22.0), ('rl_end',),
                                 ('rl_begin', 7), ('c4ub', 255, 255, 255, 128), ('v2f', 10.0, 4.0), ('v2f', 10.0, 10.0), ('v2f', 16.0, 10.0), ('v2f', 16.0, 4.0),
                                 ('rl_end',), ('rl_begin', 2), ('v2f', 1.0, 1.0), ('rl_end',), ('v2f', 5.0, 5.0), ('rl_end',),
                                 ('rl_begin', 4), ('rl_begin', 1), ('c4f', 0.0, 1.0, 1.0, 1.0), ('v2f', 4.0, 14.0), ('v2f', 8.0, 14.0), ('v2f', 4.0, 18.0),
                                 ('v2f', 9.0, 9.0), ('rl_end',), ('end',)])
    tex = tp.image(4, 4, 7, 900)
    add('rl-textured', 32, 24, [('begin',), ('clear', C(50, 60, 70)), ('load', 0, tex), ('load', 1, tp.image(3, 3, 4, 901)),
                                ('set_texture', 0, NONE), ('rl_begin', 7), ('c4ub', 255, 255, 255, 255), ('tc', 0.0, 0.0), ('v2f', 2.0, 2.0),
                                ('tc', 0.0, 1.0), ('v2f', 2.0, 14.0), ('tc', 1.0, 1.0), ('v2f', 14.0, 14.0), ('tc', 1.0, 0.0), ('v2f', 14.0, 2.0), ('rl_end',),
                                ('rl_begin', 4), ('tc', 0.25, 0.25), ('v2f', 16.0, 2.0), ('tc', 0.5, 2.0), ('v2f', 18.0, 20.0), ('tc', 1.75, 1.5), ('v2f', 30.0, 16.0),
                                ('rl_end',), ('set_texture', 1, 0), ('rl_begin', 7), ('c4ub', 255, 200, 200, 200), ('tc', 0.0, 0.0), ('v2f', 3.0, 16.0),
                                ('tc', 0.0, 1.0), ('v2f', 3.0, 22.0), ('tc', 1.0, 1.0), ('v2f', 12.0, 22.0), ('tc', 1.0, 0.0), ('v2f', 12.0, 16.0), ('rl_end',),
                                ('rl_begin', 1), ('v2f', 20.0, 20.0), ('v2f', 30.0, 22.0), ('rl_end',), ('rect', 26.0, 2.0, 4.0, 4.0, GREEN),
                                ('rl_begin', 4), ('tc', 0.0, 0.0), ('v2f', 22.0, 4.0), ('v2f', 22.0, 10.0), ('v2f', 28.0, 10.0), ('rl_end',),
                                ('set_texture', 0, 1), ('rl_begin', 4), ('c4ub', 255, 255, 255, 255), ('tc', 0.0, 0.0), ('v2f', 22.0, 12.0),
                                ('set_texture_null', 0), ('tc', 0.0, 1.0), ('v2f', 22.0, 18.0), ('tc', 1.0, 1.0), ('v2f', 28.0, 18.0), ('rl_end',),
                                ('rl_begin', 4), ('v2f', 1.0, 21.0), ('v2f', 1.0, 23.0), ('v2f', 4.0, 23.0), ('rl_end',),
                                ('set_texture_null', 0), ('draw', 1, 28.0, 19.0, WHITE), ('end',)])
    add('rl-matrix-modes', 32, 24, [('begin',), ('clear', BLACK), ('load', 0, tex), ('matrix_mode', 0x1701), ('push',), ('identity',),
                                    ('ortho', 0.0, 16.0, 12.0, 0.0, 0.0, 1.0), ('matrix_mode', 0x1700), ('rect', 1.0, 1.0, 4.0, 4.0, RED),
                                    ('matrix_mode', 0x1701), ('pop',), ('push',), ('push',), ('translate', 0.25, 0.0, 0.0), ('matrix_mode', 0x1700),
                                    ('rect', 12.0, 12.0, 4.0, 4.0, GREEN), ('matrix_mode', 0x1701), ('pop',), ('matrix_mode', 0x1702),
                                    ('translate', 0.5, 0.25, 0.0), ('scale', 2.0, 2.0, 1.0), ('set_texture', 0, NONE), ('rl_begin', 7),
                                    ('c4ub', 255, 255, 255, 255), ('tc', 0.0, 0.0), ('v2f', 18.0, 2.0), ('tc', 0.0, 1.0), ('v2f', 18.0, 10.0),
                                    ('tc', 1.0, 1.0), ('v2f', 26.0, 10.0), ('tc', 1.0, 0.0), ('v2f', 26.0, 2.0), ('rl_end',), ('push',), ('identity',),
                                    ('rotate', 90.0, 0.0, 0.0, 1.0), ('pop',), ('push',), ('push',), ('set_texture_null', 0), ('matrix_mode', 0x1700),
                                    ('matrix_mode', 77), ('translate', 2.0, 0.0, 0.0), ('rect', 2.0, 18.0, 4.0, 4.0, BLUE), ('get', 'modelview'),
                                    ('get', 'projection'), ('end',)])
    add('rl-ortho-viewport', 32, 24, [('begin',), ('clear', C(10, 10, 10)), ('viewport', 4.0, 2.0, 16.0, 12.0), ('rect', 0.0, 0.0, 32.0, 24.0, HALF[2]),
                                      ('line', 0.0, 0.0, 31.0, 23.0, WHITE), ('matrix_mode', 0x1701), ('identity',),
                                      ('ortho', -2.0, 2.0, -1.5, 1.5, -1.0, 1.0), ('matrix_mode', 0x1700), ('identity',), ('viewport', 16.0, 10.0, 16.0, 12.0),
                                      ('rl_begin', 4), ('c4ub', 255, 128, 0, 255), ('v2f', -1.0, -1.0), ('v2f', 1.0, -1.0), ('v2f', 0.0, 1.0), ('rl_end',),
                                      ('viewport', 0.0, 0.0, -4.0, 8.0), ('rl_begin', 1), ('v2f', -2.0, 0.0), ('v2f', 2.0, 0.5), ('rl_end',),
                                      ('viewport', 0.0, 0.0, 32.0, 24.0), ('scissor', 2.0, 2.0, 10.0, 8.0), ('rl_begin', 7), ('c4ub', 0, 255, 0, 120),
                                      ('v2f', -2.0, -1.5), ('v2f', 2.0, -1.5), ('v2f', 2.0, 1.5), ('v2f', -2.0, 1.5), ('rl_end',), ('toggle', 'scissor', True),
                                      ('rl_begin', 7), ('v2f', -2.0, -1.5), ('v2f', 2.0, -1.5), ('v2f', 2.0, 1.5), ('v2f', -2.0, 1.5), ('rl_end',),
                                      ('scissor', 20.0, 4.0, -1.0, 3.0), ('rect_rec', 0.0, 0.0, 0.5, 0.5, WHITE), ('toggle', 'scissor', False),
                                      ('get', 'projection'), ('end',)])
    add('rl-cull-blend', 32, 24, [('begin',), ('clear', TRANS_BG), ('toggle', 'cull', False), ('tri', 2.0, 2.0, 12.0, 10.0, 2.0, 10.0, RED),
                                  ('toggle', 'cull', True), ('tri', 14.0, 2.0, 24.0, 10.0, 14.0, 10.0, GREEN), ('cull_face', 0),
                                  ('tri', 2.0, 12.0, 12.0, 22.0, 2.0, 22.0, BLUE), ('tri', 14.0, 12.0, 14.0, 22.0, 24.0, 22.0, WHITE), ('cull_face', 5),
                                  ('tri', 26.0, 2.0, 30.0, 10.0, 26.0, 10.0, WHITE), ('cull_face', 1), ('toggle', 'blend', False),
                                  ('rect', 25.0, 12.0, 6.0, 6.0, HALF[0]), ('circle_v', 8.0, 6.0, 3.0, HALF[2]), ('line', 0.0, 23.0, 31.0, 20.0, HALF[1]),
                                  ('toggle', 'blend', True), ('rect', 25.0, 18.0, 6.0, 5.0, HALF[0]), ('end',)])
    cube = []
    for z, color, quad in ((0.5, RED, (2.0, 2.0, 20.0, 16.0)), (-0.25, GREEN, (8.0, 6.0, 26.0, 20.0)), (0.0, HALF[2], (14.0, 1.0, 30.0, 12.0))):
        x0, y0, x1, y1 = quad
        cube += [('rl_begin', 7), ('c4ub', *[(color >> s) & 255 for s in (24, 16, 8, 0)]), ('v3f', x0, y0, z), ('v3f', x0, y1, z),
                 ('v3f', x1, y1, f32(z - 0.25)), ('v3f', x1, y0, f32(z - 0.25)), ('rl_end',)]
    add('rl-depth', 32, 24, [('begin',), ('clear', C(5, 5, 5)), ('matrix_mode', 0x1701), ('identity',), ('ortho', 0.0, 32.0, 24.0, 0.0, -1.0, 1.0),
                             ('matrix_mode', 0x1700), ('toggle', 'depth', True), ('toggle', 'depth_mask', False)] + cube
            + [('rl_begin', 4), ('c4ub', 255, 255, 255, 255), ('v3f', 4.0, 20.0, -0.75), ('v3f', 28.0, 22.0, 0.75), ('v3f', 28.0, 14.0, 0.0), ('rl_end',),
               ('rl_begin', 1), ('c4ub', 255, 0, 255, 255), ('v3f', 0.0, 12.0, -1.0), ('v3f', 31.0, 12.0, 1.0), ('rl_end',),
               ('clear_color', 0, 0, 40, 255), ('scissor', 4.0, 4.0, 6.0, 6.0), ('toggle', 'scissor', True), ('clear_buffers',),
               ('toggle', 'scissor', False), ('rl_begin', 7), ('c4ub', 255, 255, 0, 255), ('v3f', 0.0, 0.0, 0.9), ('v3f', 0.0, 24.0, 0.9),
               ('v3f', 32.0, 24.0, 0.9), ('v3f', 32.0, 0.0, 0.9), ('rl_end',), ('toggle', 'depth', False), ('end',)])
    # A render texture's depth renderbuffer starts zeroed (depth 0.0): before any clear only fragments at
    # depth 0 pass (the rectangle at z = 0 does, the quad behind it does not).
    add('rl-depth-render-texture', 24, 18, [('begin',), ('clear', C(5, 5, 5)), ('load_rt', 0, 16, 12), ('begin_rt', 0), ('toggle', 'depth', True),
                                            ('rect', 0.0, 0.0, 6.0, 6.0, RED), ('rl_begin', 7), ('c4ub', 0, 255, 0, 255), ('v3f', 4.0, 2.0, -0.5), ('v3f', 4.0, 10.0, -0.5),
                                            ('v3f', 14.0, 10.0, -0.5), ('v3f', 14.0, 2.0, -0.5), ('rl_end',), ('toggle', 'depth', False), ('end_rt', 0),
                                            ('draw_rt', 0, 4.0, 3.0, WHITE), ('end',)], screen=True)
    # The depth buffer is kept between texture modes: a second mode without a clear still tests against
    # what the first one stored.
    add('rl-depth-render-texture-kept', 40, 30, [('begin',), ('clear', C(5, 5, 5)), ('load_rt', 0, 32, 24), ('begin_rt', 0), ('clear_color', 0, 0, 40, 255),
                                                 ('clear_buffers',), ('matrix_mode', 0x1701), ('identity',), ('ortho', 0.0, 32.0, 24.0, 0.0, -1.0, 1.0),
                                                 ('matrix_mode', 0x1700), ('toggle', 'depth', True)] + cube[:7]
        + [('toggle', 'depth', False), ('end_rt', 0), ('begin_rt', 0), ('matrix_mode', 0x1701), ('identity',), ('ortho', 0.0, 32.0, 24.0, 0.0, -1.0, 1.0),
           ('matrix_mode', 0x1700), ('toggle', 'depth', True)] + cube[7:]
        + [('rl_begin', 7), ('c4ub', 255, 255, 0, 255), ('v3f', 0.0, 0.0, 0.9), ('v3f', 0.0, 24.0, 0.9), ('v3f', 32.0, 24.0, 0.9), ('v3f', 32.0, 0.0, 0.9), ('rl_end',),
           ('toggle', 'depth', False), ('end_rt', 0), ('draw_rt', 0, 4.0, 3.0, WHITE), ('end',)], screen=True)
    # The same depth-tested quads into a render texture after a clear, with a scissored clear and a far quad,
    # then the texture on the screen.
    add('rl-depth-render-texture-cleared', 40, 30, [('begin',), ('clear', C(5, 5, 5)), ('load_rt', 0, 32, 24), ('begin_rt', 0), ('clear_color', 0, 0, 40, 255),
                                                    ('clear_buffers',), ('matrix_mode', 0x1701), ('identity',), ('ortho', 0.0, 32.0, 24.0, 0.0, -1.0, 1.0),
                                                    ('matrix_mode', 0x1700), ('toggle', 'depth', True)] + cube
        + [('rl_begin', 4), ('c4ub', 255, 255, 255, 255), ('v3f', 4.0, 20.0, -0.75), ('v3f', 28.0, 22.0, 0.75), ('v3f', 28.0, 14.0, 0.0), ('rl_end',),
           ('clear_color', 40, 0, 0, 255), ('scissor', 4.0, 4.0, 6.0, 6.0), ('toggle', 'scissor', True), ('clear_buffers',), ('toggle', 'scissor', False),
           ('rl_begin', 7), ('c4ub', 255, 255, 0, 255), ('v3f', 0.0, 0.0, 0.9), ('v3f', 0.0, 24.0, 0.9), ('v3f', 32.0, 24.0, 0.9), ('v3f', 32.0, 0.0, 0.9), ('rl_end',),
           ('toggle', 'depth', False), ('end_rt', 0), ('draw_rt', 0, 4.0, 3.0, WHITE), ('end',)], screen=True)
    add('rl-frustum', 32, 24, [('begin',), ('clear', BLACK), ('matrix_mode', 0x1701), ('push',), ('identity',),
                               ('frustum', -0.5, 0.5, -0.375, 0.375, 1.0, 16.0), ('matrix_mode', 0x1700), ('push',), ('identity',),
                               ('toggle', 'depth', True), ('toggle', 'cull', False),
                               ('rl_begin', 4), ('c4ub', 255, 0, 0, 255), ('v3f', -2.0, -1.0, -3.0), ('c4ub', 0, 255, 0, 255), ('v3f', 2.0, -1.0, -6.0),
                               ('c4ub', 0, 0, 255, 255), ('v3f', 0.0, 2.0, -4.0), ('rl_end',), ('load', 0, tex), ('set_texture', 0, NONE),
                               ('rl_begin', 7), ('c4ub', 255, 255, 255, 255), ('tc', 0.0, 0.0), ('v3f', -3.0, -2.0, -8.0), ('tc', 0.0, 1.0), ('v3f', -3.0, 2.0, -8.0),
                               ('tc', 1.0, 1.0), ('v3f', 3.0, 2.0, -2.0), ('tc', 1.0, 0.0), ('v3f', 3.0, -2.0, -2.0), ('rl_end',), ('set_texture_null', 0),
                               ('rl_begin', 1), ('c4ub', 255, 255, 0, 255), ('v3f', -1.5, 0.0, -0.5), ('v3f', 1.5, 0.5, -10.0), ('rl_end',),
                               ('get', 'projection'), ('pop',), ('matrix_mode', 0x1701), ('pop',), ('matrix_mode', 0x1700), ('toggle', 'depth', False),
                               ('toggle', 'cull', True), ('rect', 1.0, 1.0, 3.0, 3.0, WHITE), ('end',)])
    add('rl-wire-point', 40, 30, [('begin',), ('clear', C(20, 20, 20)), ('toggle', 'wire', True), ('rect', 3.0, 3.0, 10.0, 8.0, RED),
                                  ('tri', 16.0, 3.0, 16.0, 12.0, 26.0, 12.0, GREEN), ('tri', 30.0, 3.0, 38.0, 12.0, 30.0, 12.0, WHITE),
                                  ('line', 2.0, 15.0, 20.0, 18.0, HALF[0]), ('circle_v', 30.0, 20.0, 5.0, BLUE), ('toggle', 'wire', False),
                                  ('toggle', 'point', True), ('point_size', 1.0), ('rect', 3.0, 20.0, 8.0, 6.0, WHITE), ('point_size', 3.0),
                                  ('tri', 14.0, 20.0, 14.0, 26.0, 22.0, 26.0, HALF[2]), ('point_size', 4.9), ('line', 25.0, 26.0, 27.0, 27.0, RED),
                                  ('point_size', -2.0), ('rect', 30.0, 2.0, 3.0, 3.0, RED), ('get', 'point_size'), ('toggle', 'point', False),
                                  ('toggle', 'smooth', True), ('line', 1.0, 28.0, 38.0, 28.0, WHITE), ('toggle', 'smooth', False), ('end',)])
    add('rl-line-width', 40, 30, [('begin',), ('clear', BLACK), ('get', 'line_width'), ('line_width', 3.0), ('get', 'line_width'),
                                  ('line', 4.0, 5.0, 35.0, 9.0, RED), ('line', 6.0, 8.0, 9.0, 25.0, GREEN), ('line_width', 6.4),
                                  ('line', 12.0, 15.0, 33.0, 16.0, HALF[2]), ('line_width', 1.5), ('get', 'line_width'), ('line', 15.0, 22.0, 30.0, 26.0, WHITE),
                                  ('line_width', 2.5), ('get', 'line_width'), ('rect_lines', 18.0, 3.0, 12.0, 5.0, HALF[0]), ('line_width', -7.0),
                                  ('get', 'line_width'), ('line', 2.0, 28.0, 38.0, 28.0, WHITE), ('end',)])
    add('rl-clear-getters', 24, 16, [('begin',), ('clear_color', 10, 20, 30, 40), ('clear_buffers',), ('clear_color', 255, 0, 0, 255),
                                     ('scissor', 2.0, 3.0, 4.0, 5.0), ('toggle', 'scissor', True), ('clear_buffers',), ('toggle', 'scissor', False),
                                     ('get', 'framebuffer'), ('get', 'version'), ('get', 'misc'), ('noops',), ('get', 'modelview'), ('get', 'projection'),
                                     ('load_rt', 0, 6, 5), ('begin_rt', 0), ('get', 'framebuffer'), ('clear_color', 0, 0, 255, 255), ('clear_buffers',),
                                     ('rl_begin', 4), ('v2f', 0.0, 0.0), ('v2f', 0.0, 5.0), ('v2f', 6.0, 5.0), ('rl_end',), ('end_rt', 0),
                                     ('draw_rt', 0, 12.0, 8.0, WHITE), ('end',)], screen=True)

    # Contracts.
    add('rl-pop-projection', 16, 12, [('matrix_mode', 0x1701), ('pop',)], contract=True)
    add('rl-pop-texture', 16, 12, [('matrix_mode', 0x1702), ('pop',)], contract=True)
    add('rl-ortho-inexact', 16, 12, [('ortho', 0.0, 16.0, 12.0, f32(0.1), 0.0, 1.0)])
    add('rl-frustum-inexact', 16, 12, [('frustum', -1.0, 1.0, -1.0, 1.0, f32(0.1), 100.0)])
    add('rl-line-width-huge', 16, 12, [('line_width', 5000.0)])
    add('rl-point-size-nan', 16, 12, [('point_size', float('nan'))])
    add('rl-thick-line-edge', 16, 12, [('line_width', 6.0), ('line', 0.0, 1.0, 15.0, 1.0, RED)], contract=True)
    add('rl-point-edge', 16, 12, [('toggle', 'point', True), ('point_size', 6.0), ('rect', 0.0, 0.0, 2.0, 2.0, RED)], contract=True)

    # Random immediate-mode scenes.
    for index in range(6):
        w, h = rng.choice(((32, 24), (24, 32)))
        ops = [('begin',), ('clear', C(rng.randrange(256), rng.randrange(256), rng.randrange(256), rng.choice((255, 100))))]
        if rng.random() < 0.5:
            ops.append(('toggle', 'cull', False))
        for _ in range(rng.randint(4, 8)):
            mode = rng.choice((1, 4, 7))
            count = {1: 2, 4: 3, 7: 4}[mode] * rng.randint(1, 2)
            ops.append(('rl_begin', mode))
            for _ in range(count):
                if rng.random() < 0.4:
                    ops.append(('c4ub', rng.randrange(256), rng.randrange(256), rng.randrange(256), rng.choice((255, 255, 128, 30))))
                ops.append(('v2f', f32(rng.uniform(-4, w + 4)), f32(rng.uniform(-4, h + 4))))
            ops.append(('rl_end',))
        ops.append(('end',))
        add(f'rl-random-{index}', w, h, ops)
    return out


# -----------------------------------------------------------------------------
# C reference

C_PREFIX = tp.C_PREFIX.replace('static void dump(int w, int h, int screen)', r'''static unsigned fb(float x) { unsigned b; memcpy(&b, &x, 4); return b; }
static void note_f(const char *tag, float v) { char s[48]; snprintf(s, sizeof s, " %s%u", tag, fb(v)); note(s); }
static void note_m(const char *tag, Matrix m)
{
    char s[256];
    snprintf(s, sizeof s, " %s%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u", tag, fb(m.m0), fb(m.m1), fb(m.m2), fb(m.m3), fb(m.m4), fb(m.m5),
             fb(m.m6), fb(m.m7), fb(m.m8), fb(m.m9), fb(m.m10), fb(m.m11), fb(m.m12), fb(m.m13), fb(m.m14), fb(m.m15));
    note(s);
}
static void shapes_info(void)
{
    char s[160];
    Texture2D t = GetShapesTexture(); Rectangle r = GetShapesTextureRectangle();
    snprintf(s, sizeof s, " s%u,%d,%d,%d,%d,%u,%u,%u,%u", t.id, t.width, t.height, t.mipmaps, t.format, fb(r.x), fb(r.y), fb(r.width), fb(r.height));
    note(s);
}
static void noops(void)
{
    rlActiveTextureSlot(1); rlEnableTextureCubemap(3); rlDisableTextureCubemap(); rlCubemapParameters(1, RL_TEXTURE_MAG_FILTER, RL_TEXTURE_FILTER_LINEAR);
    rlEnableShader(5); rlDisableShader(); rlEnableVertexBuffer(1); rlDisableVertexBuffer(); rlEnableVertexBufferElement(1); rlDisableVertexBufferElement();
    rlEnableVertexAttribute(0); rlDisableVertexAttribute(0); rlDisableVertexArray(); rlBlitFramebuffer(0, 0, 4, 4, 0, 0, 8, 8, 0x4000);
    rlActiveDrawBuffers(2); rlLoadDrawCube(); rlLoadDrawQuad(); rlColorMask(false, true, false, true); rlCheckErrors();
    rlSetBlendMode(RL_BLEND_ADDITIVE); rlSetBlendFactors(RL_ONE, RL_ONE, RL_FUNC_ADD); rlSetBlendFactorsSeparate(RL_ONE, RL_ZERO, RL_ONE, RL_ZERO, RL_FUNC_ADD, RL_FUNC_ADD);
    rlSetFramebufferWidth(77); rlSetFramebufferHeight(66); rlDrawRenderBatchActive(); rlSetMatrixModelview(MatrixTranslate(3, 4, 5));
    rlSetMatrixProjection(MatrixScale(2, 2, 2)); rlSetMatrixProjectionStereo(MatrixIdentity(), MatrixIdentity()); rlSetMatrixViewOffsetStereo(MatrixIdentity(), MatrixIdentity());
    rlEnableStereoRender(); rlDisableStereoRender(); rlEnableDepthMask(); rlDisableDepthMask(); rlNormal3f(1, 2, 3);
}
static void misc(void)
{
    char s[160];
    snprintf(s, sizeof s, " x%d,%d,%d,%u,%u,%d,%d", (int)rlIsStereoRenderEnabled(), rlGetFramebufferWidth(), rlGetFramebufferHeight(), rlGetTextureIdDefault(),
             rlGetShaderIdDefault(), (int)rlCheckRenderBatchLimit(1000000), (int)rlEnableVertexArray(3));
    note(s);
    Matrix t = rlGetMatrixTransform(); note_m("t", t); note_m("e", rlGetMatrixProjectionStereo(1)); note_m("o", rlGetMatrixViewOffsetStereo(0));
}
static void dump(int w, int h, int screen)''')
if 'static void noops(void)' not in C_PREFIX:
    raise ProbeFailure('rlgl: tools/texture_probe.py C_PREFIX changed; update the rlgl probe hooks')
C_PREFIX = C_PREFIX.replace('#include "rlgl.h"\n', '#include "rlgl.h"\n#include "raymath.h"\n')


def cpoints(points):
    return '(Vector2[]){ ' + ', '.join(fp.cv(x, y) for x, y in points) + ' }'


def c_op(op):
    name, a = op[0], op[1:]
    if name in tp.SHAPE_OPS or name in ('mode2d', 'end2d', 'push', 'pop', 'identity', 'translate', 'scale', 'rotate', 'mult', 'load', 'unload',
                                        'filter', 'load_rt', 'begin_rt', 'end_rt', 'draw_rt', 'draw', 'info', 'image'):
        return tp.c_op(op)
    v = fp.cv
    calls = {
        'bezier': lambda: f'DrawLineBezier({v(a[0], a[1])}, {v(a[2], a[3])}, {cf(a[4])}, {cc(a[5])});',
        'dashed': lambda: f'DrawLineDashed({v(a[0], a[1])}, {v(a[2], a[3])}, {fp.ci(a[4])}, {fp.ci(a[5])}, {cc(a[6])});',
        'ring_lines': lambda: f'DrawRingLines({v(a[0], a[1])}, {cf(a[2])}, {cf(a[3])}, {cf(a[4])}, {cf(a[5])}, {fp.ci(a[6])}, {cc(a[7])});',
        'poly_ex': lambda: f'DrawPolyLinesEx({v(a[0], a[1])}, {fp.ci(a[2])}, {cf(a[3])}, {cf(a[4])}, {cf(a[5])}, {cc(a[6])});',
        'poly2': lambda: f'DrawPoly({v(a[0], a[1])}, {fp.ci(a[2])}, {cf(a[3])}, {cf(a[4])}, {cc(a[5])});',
        'sector2': lambda: f'DrawCircleSector({v(a[0], a[1])}, {cf(a[2])}, {cf(a[3])}, {cf(a[4])}, {fp.ci(a[5])}, {cc(a[6])});',
        'sector_lines2': lambda: f'DrawCircleSectorLines({v(a[0], a[1])}, {cf(a[2])}, {cf(a[3])}, {cf(a[4])}, {fp.ci(a[5])}, {cc(a[6])});',
        'ring2': lambda: f'DrawRing({v(a[0], a[1])}, {cf(a[2])}, {cf(a[3])}, {cf(a[4])}, {cf(a[5])}, {fp.ci(a[6])}, {cc(a[7])});',
        'rounded': lambda: f'DrawRectangleRounded({fp.crec(*a[:4])}, {cf(a[4])}, {fp.ci(a[5])}, {cc(a[6])});',
        'rounded_lines': lambda: f'DrawRectangleRoundedLines({fp.crec(*a[:4])}, {cf(a[4])}, {fp.ci(a[5])}, {cc(a[6])});',
        'rounded_lines_ex': lambda: f'DrawRectangleRoundedLinesEx({fp.crec(*a[:4])}, {cf(a[4])}, {fp.ci(a[5])}, {cf(a[6])}, {cc(a[7])});',
        'spline': lambda: (f'DrawSpline{("Linear", "Basis", "CatmullRom", "BezierQuadratic", "BezierCubic")[a[0]]}'
                           f'({cpoints(a[1])}, {len(a[1])}, {cf(a[2])}, {cc(a[3])});'),
        'segment': lambda: (f'DrawSplineSegment{("Linear", "Basis", "CatmullRom", "BezierQuadratic", "BezierCubic")[a[0]]}'
                            f'({", ".join(v(x, y) for x, y in a[1])}, {cf(a[2])}, {cc(a[3])});'),
        'shapes_tex': lambda: f'SetShapesTexture({"(Texture2D){ 0 }" if a[0] == NONE else f"t[{a[0]}]"}, {fp.crec(*a[1])});',
        'shapes_info': lambda: 'shapes_info();',
        'rl_begin': lambda: f'rlBegin({a[0]});', 'rl_end': lambda: 'rlEnd();',
        'v2i': lambda: f'rlVertex2i({fp.ci(a[0])}, {fp.ci(a[1])});', 'v2f': lambda: f'rlVertex2f({cf(a[0])}, {cf(a[1])});',
        'v3f': lambda: f'rlVertex3f({cf(a[0])}, {cf(a[1])}, {cf(a[2])});', 'tc': lambda: f'rlTexCoord2f({cf(a[0])}, {cf(a[1])});',
        'normal': lambda: f'rlNormal3f({cf(a[0])}, {cf(a[1])}, {cf(a[2])});',
        'c4ub': lambda: f'rlColor4ub({a[0]}, {a[1]}, {a[2]}, {a[3]});', 'c3f': lambda: f'rlColor3f({cf(a[0])}, {cf(a[1])}, {cf(a[2])});',
        'c4f': lambda: f'rlColor4f({cf(a[0])}, {cf(a[1])}, {cf(a[2])}, {cf(a[3])});',
        'set_texture': lambda: f'rlSetTexture(t[{a[0]}].id);', 'set_texture_null': lambda: 'rlSetTexture(0);',
        'matrix_mode': lambda: f'rlMatrixMode({a[0]});',
        'ortho': lambda: 'rlOrtho(' + ', '.join(f'(double){cf(x)}' for x in a) + ');',
        'frustum': lambda: 'rlFrustum(' + ', '.join(f'(double){cf(x)}' for x in a) + ');',
        'viewport': lambda: f'rlViewport({", ".join(fp.ci(x) for x in a)});',
        'toggle': lambda: f'{C_TOGGLES[TOGGLES[a[0]]][0 if a[1] else 1]}();',
        'cull_face': lambda: f'rlSetCullFace({a[0]});', 'scissor': lambda: f'rlScissor({", ".join(fp.ci(x) for x in a)});',
        'line_width': lambda: f'rlSetLineWidth({cf(a[0])});', 'point_size': lambda: f'rlSetPointSize({cf(a[0])});',
        'clear_color': lambda: f'rlClearColor({a[0]}, {a[1]}, {a[2]}, {a[3]});', 'clear_buffers': lambda: 'rlClearScreenBuffers();',
        'noops': lambda: 'noops();',
        'get': lambda: {'line_width': 'note_f("w", rlGetLineWidth());', 'point_size': 'note_f("p", rlGetPointSize());',
                        'modelview': 'note_m("m", rlGetMatrixModelview());', 'projection': 'note_m("j", rlGetMatrixProjection());',
                        'framebuffer': '{ char s[32]; snprintf(s, sizeof s, " a%u", rlGetActiveFramebuffer()); note(s); }',
                        'version': '{ char s[32]; snprintf(s, sizeof s, " v%d", rlGetVersion()); note(s); }', 'misc': 'misc();'}[a[0]],
    }
    return '    ' + calls[name]()


def c_scene(scene):
    lines = ['    { Texture2D t[4] = { 0 }; RenderTexture2D r[2] = { 0 }; (void)t; (void)r;', f'    InitWindow({scene["width"]}, {scene["height"]}, "");']
    lines += [c_op(op) for op in scene['ops']]
    lines += [f'    dump({scene["width"]}, {scene["height"]}, {int(scene["screen"])});', '    CloseWindow(); }']
    return '\n'.join(lines)


TABLES_C = r'''
float sun239_acosf(float);
#define SMOOTH_CIRCLE_ERROR_RATE 0.5f
/* DrawCircleSector's segment count (pinned rshapes.c), acosf from glibc 2.39. */
static void arc(float radius, float startAngle, float endAngle, int segments)
{
    int minSegments = (int)ceilf((endAngle - startAngle)/90);
    if (segments < minSegments)
    {
        float th = sun239_acosf(2*powf(1 - SMOOTH_CIRCLE_ERROR_RATE/radius, 2) - 1);
        float value = (endAngle - startAngle)*ceilf(2*PI/th)/360;
        if (!(value > -2147483648.0f && value < 2147483648.0f)) { printf(" ub"); return; }
        segments = (int)value;
        if (segments <= 0) segments = minSegments;
    }
    printf(" %d", segments);
}
/* DrawRectangleRounded (divisor 4) and DrawRectangleRoundedLinesEx (2). */
static void corner(float radius, float divisor, int segments)
{
    if (segments < 4)
    {
        float th = sun239_acosf(2*powf(1 - SMOOTH_CIRCLE_ERROR_RATE/radius, 2) - 1);
        float value = ceilf(2*PI/th)/divisor;
        if (!(value > -2147483648.0f && value < 2147483648.0f)) { printf(" ub"); return; }
        segments = (int)value;
        if (segments <= 0) segments = 4;
    }
    printf(" %d", segments);
}
'''

ARC_RADII = [0.3, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 5.0, 7.25, 10.0, 16.0, 33.3, 64.0, 100.0, 250.5, 1000.0, 50000.0]
ARC_SPANS = [(0.0, 10.0), (30.0, 75.0), (0.0, 90.0), (-90.0, 90.0), (10.0, 280.0), (0.0, 360.0)]


def estimate_rows():
    rows = []
    for r in map(f32, ARC_RADII):
        for start, end in ARC_SPANS:
            for segments in (0, 1, -3):
                rows.append(('arc', r, start, end, segments))
        for divisor in (4.0, 2.0):
            for segments in (0, 3, -1):
                rows.append(('corner', r, divisor, segments))
    return rows


def c_tables():
    lines = ['    { float (*volatile p)(float, float) = powf; float (*volatile c)(float) = cosf; const float step = 1.0f/24;',
             '      printf("P"); for (int i = 1; i <= 24; i++) { float t = step*(float)i; printf(" %u %u", fb(p(1.0f - t, 3)), fb(p(t, 3))); } printf("\\n");',
             '      printf("Q"); for (int n = 3; n <= 4096; n++) { volatile float e = 360.0f/(float)n*DEG2RAD; volatile float a = DEG2RAD*e/2.0f; printf(" %u", fb(c(a))); } printf("\\n");',
             '      printf("E");']
    for row in estimate_rows():
        if row[0] == 'arc':
            lines.append(f'      arc({cf(row[1])}, {cf(row[2])}, {cf(row[3])}, {row[4]});')
        else:
            lines.append(f'      corner({cf(row[1])}, {cf(row[2])}, {row[3]});')
    lines.append('      printf("\\n"); }')
    return '\n'.join(lines)


# -----------------------------------------------------------------------------
# Bend candidate

PROGRAM = tp.PROGRAM + '''
def St.take.at(slot: U32, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St & Maybe<J.Texture>:
  match slot:
    case 0: (St{frame, None{}, t1, t2, t3, r0, r1, log}, t0)
    case 1: (St{frame, t0, None{}, t2, t3, r0, r1, log}, t1)
    case 2: (St{frame, t0, t1, None{}, t3, r0, r1, log}, t2)
    case 3: (St{frame, t0, t1, t2, None{}, r0, r1, log}, t3)
    case _: (St{frame, t0, t1, t2, t3, r0, r1, log}, None{})

def St.take(s: St, +slot: U32) -> St & Maybe<J.Texture>:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.take.at(slot, frame, t0, t1, t2, t3, r0, r1, log)

def St.put.at(slot: U32, tex: J.Texture, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  match slot:
    case 0: St{frame, Some{tex}, t1, t2, t3, r0, r1, log}
    case 1: St{frame, t0, Some{tex}, t2, t3, r0, r1, log}
    case 2: St{frame, t0, t1, Some{tex}, t3, r0, r1, log}
    case 3: St{frame, t0, t1, t2, Some{tex}, r0, r1, log}
    case _: St{frame, t0, t1, t2, t3, r0, r1, log}

def St.put.some(s: St, +slot: U32, tex: J.Texture) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.put.at(slot, tex, frame, t0, t1, t2, t3, r0, r1, log)

# A texture handed back goes to the slot (nothing when None).
def St.put(s: St, +slot: U32, tex: Maybe<J.Texture>) -> St:
  match tex:
    case None{}: s
    case Some{t}: St.put.some(s, slot, t)

'''

NEW_BEND = tp.NEW_BEND + '''
def wpoints(n: Nat, +ws: +List<U32>) -> +List<M.Vector2>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{wv(0n, ws), wpoints(k, word.drop(2n, ws))}

def point.at(n: Nat, pts: +List<M.Vector2>) -> M.Vector2:
  match n pts:
    case 0n Con{p, _}: p
    case _ Nil{}: M.Vector2{0.0, 0.0}
    case 1n+k Con{_, rest}: point.at(k, rest)

def shape.segment(kind: U32, frame: J.Frame, +pts: +List<M.Vector2>, +thick: F32, +color: U32) -> J.Frame:
  match kind:
    case 0: J.Draw.spline_segment_linear(frame, point.at(0n, pts), point.at(1n, pts), thick, color)
    case 1: J.Draw.spline_segment_basis(frame, point.at(0n, pts), point.at(1n, pts), point.at(2n, pts), point.at(3n, pts), thick, color)
    case 2: J.Draw.spline_segment_catmull_rom(frame, point.at(0n, pts), point.at(1n, pts), point.at(2n, pts), point.at(3n, pts), thick, color)
    case 3: J.Draw.spline_segment_bezier_quadratic(frame, point.at(0n, pts), point.at(1n, pts), point.at(2n, pts), thick, color)
    case _: J.Draw.spline_segment_bezier_cubic_for(libm(), frame, point.at(0n, pts), point.at(1n, pts), point.at(2n, pts), point.at(3n, pts), thick, color)

def shape.spline(kind: U32, frame: J.Frame, pts: +List<M.Vector2>, +thick: F32, +color: U32) -> J.Frame:
  match kind:
    case 0: J.Draw.spline_linear(frame, pts, thick, color)
    case 1: J.Draw.spline_basis_for(libm(), frame, pts, thick, color)
    case 2: J.Draw.spline_catmull_rom_for(libm(), frame, pts, thick, color)
    case 3: J.Draw.spline_bezier_quadratic(frame, pts, thick, color)
    case _: J.Draw.spline_bezier_cubic_for(libm(), frame, pts, thick, color)

# Shapes (kinds 200..219).
def shape.draw(kind: U32, +w: +List<U32>, frame: J.Frame) -> J.Frame:
  match kind:
    case 200: J.Draw.line_bezier(frame, wv(0n, w), wv(2n, w), wf(4n, w), wu(5n, w))
    case 201: J.Draw.line_dashed(frame, wv(0n, w), wv(2n, w), wf(4n, w), wf(5n, w), wu(6n, w))
    case 202: J.Draw.ring_lines_for(libm(), frame, wv(0n, w), wf(2n, w), wf(3n, w), wf(4n, w), wf(5n, w), wf(6n, w), wu(7n, w))
    case 203: J.Draw.poly_lines_ex_for(libm(), frame, wv(0n, w), wf(2n, w), wf(3n, w), wf(4n, w), wf(5n, w), wu(6n, w))
    case 204: J.Draw.poly_for(libm(), frame, wv(0n, w), wf(2n, w), wf(3n, w), wf(4n, w), wu(5n, w))
    case 205: J.Draw.circle_sector_for(libm(), frame, wv(0n, w), wf(2n, w), wf(3n, w), wf(4n, w), wf(5n, w), wu(6n, w))
    case 206: J.Draw.circle_sector_lines_for(libm(), frame, wv(0n, w), wf(2n, w), wf(3n, w), wf(4n, w), wf(5n, w), wu(6n, w))
    case 207: J.Draw.ring_for(libm(), frame, wv(0n, w), wf(2n, w), wf(3n, w), wf(4n, w), wf(5n, w), wf(6n, w), wu(7n, w))
    case 208: J.Draw.rectangle_rounded_for(libm(), frame, wrect(0n, w), wf(4n, w), wf(5n, w), wu(6n, w))
    case 209: J.Draw.rectangle_rounded_lines_for(libm(), frame, wrect(0n, w), wf(4n, w), wf(5n, w), wu(6n, w))
    case 210: J.Draw.rectangle_rounded_lines_ex_for(libm(), frame, wrect(0n, w), wf(4n, w), wf(5n, w), wf(6n, w), wu(7n, w))
    case 211: shape.spline(wu(0n, w), frame, wpoints(U32.to_nat(wu(3n, w)), word.drop(4n, w)), wf(1n, w), wu(2n, w))
    case _: shape.segment(wu(0n, w), frame, wpoints(U32.to_nat(wu(3n, w)), word.drop(4n, w)), wf(1n, w), wu(2n, w))

def toggle.blend(on: Bool, frame: J.Frame) -> J.Frame:
  match on:
    case True{}: J.Rlgl.enable_color_blend(frame)
    case False{}: J.Rlgl.disable_color_blend(frame)

def toggle.depth(on: Bool, frame: J.Frame) -> J.Frame:
  match on:
    case True{}: J.Rlgl.enable_depth_test(frame)
    case False{}: J.Rlgl.disable_depth_test(frame)

def toggle.cull(on: Bool, frame: J.Frame) -> J.Frame:
  match on:
    case True{}: J.Rlgl.enable_backface_culling(frame)
    case False{}: J.Rlgl.disable_backface_culling(frame)

def toggle.scissor(on: Bool, frame: J.Frame) -> J.Frame:
  match on:
    case True{}: J.Rlgl.enable_scissor_test(frame)
    case False{}: J.Rlgl.disable_scissor_test(frame)

def toggle.wire(on: Bool, frame: J.Frame) -> J.Frame:
  match on:
    case True{}: J.Rlgl.enable_wire_mode(frame)
    case False{}: J.Rlgl.disable_wire_mode(frame)

def toggle.point(on: Bool, frame: J.Frame) -> J.Frame:
  match on:
    case True{}: J.Rlgl.enable_point_mode(frame)
    case False{}: J.Rlgl.disable_point_mode(frame)

def toggle.smooth(on: Bool, frame: J.Frame) -> J.Frame:
  match on:
    case True{}: J.Rlgl.enable_smooth_lines(frame)
    case False{}: J.Rlgl.disable_smooth_lines(frame)

def toggle.mask(on: Bool, frame: J.Frame) -> J.Frame:
  match on:
    case True{}: J.Rlgl.enable_depth_mask(frame)
    case False{}: J.Rlgl.disable_depth_mask(frame)

def toggle.stereo(on: Bool, frame: J.Frame) -> J.Frame:
  match on:
    case True{}: J.Rlgl.enable_stereo_render(frame)
    case False{}: J.Rlgl.disable_stereo_render(frame)

def call.toggle(what: U32, +on: Bool, frame: J.Frame) -> J.Frame:
  match what:
    case 0: toggle.blend(on, frame)
    case 1: toggle.depth(on, frame)
    case 2: toggle.cull(on, frame)
    case 3: toggle.scissor(on, frame)
    case 4: toggle.wire(on, frame)
    case 5: toggle.point(on, frame)
    case 6: toggle.smooth(on, frame)
    case 7: toggle.mask(on, frame)
    case _: toggle.stereo(on, frame)

def call.noops.second(frame: J.Frame) -> J.Frame:
  f1 = J.Rlgl.set_framebuffer_width(frame, 77.0)
  f2 = J.Rlgl.set_framebuffer_height(f1, 66.0)
  f3 = J.Rlgl.draw_render_batch_active(f2)
  f4 = J.Rlgl.set_matrix_modelview(f3, M.Matrix.translate(3.0, 4.0, 5.0))
  f5 = J.Rlgl.set_matrix_projection(f4, M.Matrix.scale(2.0, 2.0, 2.0))
  f6 = J.Rlgl.set_matrix_projection_stereo(f5, M.Matrix.identity(), M.Matrix.identity())
  f7 = J.Rlgl.set_matrix_view_offset_stereo(f6, M.Matrix.identity(), M.Matrix.identity())
  f8 = J.Rlgl.enable_stereo_render(f7)
  f9 = J.Rlgl.disable_stereo_render(f8)
  f10 = J.Rlgl.enable_depth_mask(f9)
  f11 = J.Rlgl.disable_depth_mask(f10)
  J.Rlgl.normal3f(f11, 1.0, 2.0, 3.0)

# The OpenGL 3.3-only calls noops() makes in the C reference.
def call.noops(frame: J.Frame) -> J.Frame:
  f1 = J.Rlgl.active_texture_slot(frame, 1)
  f2 = J.Rlgl.enable_texture_cubemap(f1, 3)
  f3 = J.Rlgl.disable_texture_cubemap(f2)
  f4 = J.Rlgl.cubemap_parameters(f3, 1, 10240, 9729)
  f5 = J.Rlgl.enable_shader(f4, 5)
  f6 = J.Rlgl.disable_shader(f5)
  f7 = J.Rlgl.enable_vertex_buffer(f6, 1)
  f8 = J.Rlgl.disable_vertex_buffer(f7)
  f9 = J.Rlgl.enable_vertex_buffer_element(f8, 1)
  f10 = J.Rlgl.disable_vertex_buffer_element(f9)
  f11 = J.Rlgl.enable_vertex_attribute(f10, 0)
  f12 = J.Rlgl.disable_vertex_attribute(f11, 0)
  f13 = J.Rlgl.disable_vertex_array(f12)
  f14 = J.Rlgl.blit_framebuffer(f13, 0.0, 0.0, 4.0, 4.0, 0.0, 0.0, 8.0, 8.0, 16384)
  f15 = J.Rlgl.active_draw_buffers(f14, 2.0)
  f16 = J.Rlgl.load_draw_cube(f15)
  f17 = J.Rlgl.load_draw_quad(f16)
  f18 = J.Rlgl.color_mask(f17, False{}, True{}, False{}, True{})
  f19 = J.Rlgl.check_errors(f18)
  f20 = J.Rlgl.set_blend_mode(f19, 1)
  f21 = J.Rlgl.set_blend_factors(f20, 1, 1, 32774)
  f22 = J.Rlgl.set_blend_factors_separate(f21, 1, 0, 1, 0, 32774, 32774)
  call.noops.second(f22)

# rlgl calls (kinds 220..259).
def call.apply(kind: U32, +w: +List<U32>, frame: J.Frame) -> J.Frame:
  match kind:
    case 220: J.Rlgl.begin(frame, wu(0n, w))
    case 221: J.Rlgl.end(frame)
    case 222: J.Rlgl.vertex2i(frame, wf(0n, w), wf(1n, w))
    case 223: J.Rlgl.vertex2f(frame, wf(0n, w), wf(1n, w))
    case 224: J.Rlgl.vertex3f(frame, wf(0n, w), wf(1n, w), wf(2n, w))
    case 225: J.Rlgl.tex_coord2f(frame, wf(0n, w), wf(1n, w))
    case 226: J.Rlgl.normal3f(frame, wf(0n, w), wf(1n, w), wf(2n, w))
    case 227: J.Rlgl.color4ub(frame, wu(0n, w), wu(1n, w), wu(2n, w), wu(3n, w))
    case 228: J.Rlgl.color3f(frame, wf(0n, w), wf(1n, w), wf(2n, w))
    case 229: J.Rlgl.color4f(frame, wf(0n, w), wf(1n, w), wf(2n, w), wf(3n, w))
    case 230: J.Rlgl.matrix_mode(frame, wu(0n, w))
    case 231: J.Rlgl.ortho(frame, wf(0n, w), wf(1n, w), wf(2n, w), wf(3n, w), wf(4n, w), wf(5n, w))
    case 232: J.Rlgl.frustum(frame, wf(0n, w), wf(1n, w), wf(2n, w), wf(3n, w), wf(4n, w), wf(5n, w))
    case 233: J.Rlgl.viewport(frame, wf(0n, w), wf(1n, w), wf(2n, w), wf(3n, w))
    case 234: call.toggle(wu(0n, w), wb(1n, w), frame)
    case 235: J.Rlgl.set_cull_face(frame, wu(0n, w))
    case 236: J.Rlgl.scissor(frame, wf(0n, w), wf(1n, w), wf(2n, w), wf(3n, w))
    case 237: J.Rlgl.set_line_width(frame, wf(0n, w))
    case 238: J.Rlgl.set_point_size(frame, wf(0n, w))
    case 239: J.Rlgl.clear_color(frame, wu(0n, w), wu(1n, w), wu(2n, w), wu(3n, w))
    case 240: J.Rlgl.clear_screen_buffers(frame)
    case _: call.noops(frame)

def bits.f(+x: F32) -> String:
  U32.show(F32.bits(x))

def matrix.text(m: M.Matrix) -> String:
  M.Matrix{a0, a4, a8, a12, a1, a5, a9, a13, a2, a6, a10, a14, a3, a7, a11, a15} = m
  bits.f(a0) ++ "," ++ bits.f(a1) ++ "," ++ bits.f(a2) ++ "," ++ bits.f(a3) ++ "," ++ bits.f(a4) ++ "," ++ bits.f(a5) ++ "," ++ bits.f(a6) ++ "," ++ bits.f(a7) ++ ","
    ++ bits.f(a8) ++ "," ++ bits.f(a9) ++ "," ++ bits.f(a10) ++ "," ++ bits.f(a11) ++ "," ++ bits.f(a12) ++ "," ++ bits.f(a13) ++ "," ++ bits.f(a14) ++ "," ++ bits.f(a15)

def got.f32(tag: String, r: J.Frame & F32) -> J.Frame & String:
  (frame, +v) = r
  (frame, " " ++ tag ++ bits.f(v))

def got.matrix(tag: String, r: J.Frame & M.Matrix) -> J.Frame & String:
  (frame, m) = r
  (frame, " " ++ tag ++ matrix.text(m))

def got.u32(tag: String, r: J.Frame & U32) -> J.Frame & String:
  (frame, +v) = r
  (frame, " " ++ tag ++ U32.show(v))

def bool.digit(b: Bool) -> String:
  match b:
    case True{}: "1"
    case False{}: "0"

def got.misc.e(text: String, r: J.Frame & Bool) -> J.Frame & String:
  (frame, b) = r
  (frame, text ++ "," ++ bool.digit(b) ++ " t" ++ matrix.text(J.Rlgl.get_matrix_transform()) ++ " e" ++ matrix.text(J.Rlgl.get_matrix_projection_stereo(1))
    ++ " o" ++ matrix.text(J.Rlgl.get_matrix_view_offset_stereo(0)))

def got.misc.d(text: String, r: J.Frame & Bool) -> J.Frame & String:
  (frame, b) = r
  got.misc.e(text ++ "," ++ bool.digit(b), J.Rlgl.enable_vertex_array(frame, 3))

def got.misc.c(text: String, r: J.Frame & U32) -> J.Frame & String:
  (frame, +h) = r
  got.misc.d(text ++ "," ++ U32.show(h) ++ "," ++ U32.show(J.Rlgl.get_texture_id_default()) ++ "," ++ U32.show(J.Rlgl.get_shader_id_default()),
    J.Rlgl.check_render_batch_limit(frame, 1000000.0))

def got.misc.b(text: String, r: J.Frame & U32) -> J.Frame & String:
  (frame, +w) = r
  got.misc.c(text ++ "," ++ U32.show(w), J.Rlgl.get_framebuffer_height(frame))

def got.misc(r: J.Frame & Bool) -> J.Frame & String:
  (frame, b) = r
  got.misc.b(" x" ++ bool.digit(b), J.Rlgl.get_framebuffer_width(frame))

def query(what: U32, frame: J.Frame) -> J.Frame & String:
  match what:
    case 0: got.f32("w", J.Rlgl.get_line_width(frame))
    case 1: got.f32("p", J.Rlgl.get_point_size(frame))
    case 2: got.matrix("m", J.Rlgl.get_matrix_modelview(frame))
    case 3: got.matrix("j", J.Rlgl.get_matrix_projection(frame))
    case 4: got.u32("a", J.Rlgl.get_active_framebuffer(frame))
    case 5: (frame, " v" ++ U32.show(J.Rlgl.get_version()))
    case _: got.misc(J.Rlgl.is_stereo_render_enabled(frame))

def shapes.info.text(info: J.TextureInfo, rec: J.Rectangle) -> String:
  J.TextureInfo{id, width, height, mipmaps, format} = info
  J.Rectangle{x, y, w, h} = rec
  " s" ++ U32.show(id) ++ "," ++ U32.show(width) ++ "," ++ U32.show(height) ++ "," ++ U32.show(mipmaps) ++ "," ++ U32.show(format) ++ ","
    ++ bits.f(x) ++ "," ++ bits.f(y) ++ "," ++ bits.f(w) ++ "," ++ bits.f(h)

def shapes.info.rect(info: J.TextureInfo, r: J.Frame & J.Rectangle) -> J.Frame & String:
  (frame, rec) = r
  (frame, shapes.info.text(info, rec))

def shapes.info(r: J.Frame & J.TextureInfo) -> J.Frame & String:
  (frame, info) = r
  shapes.info.rect(info, J.Frame.get_shapes_texture_rectangle(frame))


def St.rest.log(t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String, r: J.Frame & String) -> St:
  (frame, text) = r
  St{frame, t0, t1, t2, t3, r0, r1, log ++ text}

def St.rest.tex(+back: U32, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String, r: J.Frame & Maybe<J.Texture>) -> St:
  (frame, tex) = r
  St.put(St{frame, t0, t1, t2, t3, r0, r1, log}, back, tex)

def St.query(s: St, +what: U32) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.rest.log(t0, t1, t2, t3, r0, r1, log, query(what, frame))

def St.shapes.info(s: St) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.rest.log(t0, t1, t2, t3, r0, r1, log, shapes.info(J.Frame.get_shapes_texture(frame)))

def St.texture.back(s: St, +back: U32, t: J.Texture) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.rest.tex(back, t0, t1, t2, t3, r0, r1, log, J.Rlgl.set_texture(frame, Some{t}))

def St.texture.held(s: St, +back: U32, tex: Maybe<J.Texture>) -> St:
  match tex:
    case None{}: s
    case Some{t}: St.texture.back(s, back, t)

def St.texture.taken(r: St & Maybe<J.Texture>, +back: U32) -> St:
  (s, tex) = r
  St.texture.held(s, back, tex)

# rlSetTexture(t[slot].id): the frame takes the slot's texture and hands back
# the one it held (to slot back).
def St.texture.set(s: St, +slot: U32, +back: U32) -> St:
  St.texture.taken(St.take(s, slot), back)

# rlSetTexture(0): the held texture goes back to slot back.
def St.texture.unset(s: St, +back: U32) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.rest.tex(back, t0, t1, t2, t3, r0, r1, log, J.Rlgl.set_texture(frame, None{}))

def St.shapes.pair(s: St, +slot: U32, +back: U32, pair: Maybe<J.Texture> & Maybe<J.Texture>) -> St:
  (previous, kept) = pair
  St.put(St.put(s, back, previous), slot, kept)

def St.shapes.done(+slot: U32, +back: U32, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String, r: J.Frame & (Maybe<J.Texture> & Maybe<J.Texture>)) -> St:
  (frame, pair) = r
  St.shapes.pair(St{frame, t0, t1, t2, t3, r0, r1, log}, slot, back, pair)

def St.shapes.with(s: St, +slot: U32, +back: U32, rec: J.Rectangle, tex: Maybe<J.Texture>) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.shapes.done(slot, back, t0, t1, t2, t3, r0, r1, log, J.Frame.set_shapes_texture(frame, tex, rec))

def St.shapes.call(r: St & Maybe<J.Texture>, +slot: U32, +back: U32, rec: J.Rectangle) -> St:
  (s, tex) = r
  St.shapes.with(s, slot, back, rec, tex)

# SetShapesTexture(t[slot] or { 0 }, rec): the previous shapes texture goes to
# slot back, a texture not taken back to its slot.
def St.shapes.set(s: St, +slot: U32, +back: U32, rec: J.Rectangle) -> St:
  St.shapes.call(St.take(s, slot), slot, back, rec)

# Slot-level operations (kinds 260..).
def rstep.slot(kind: U32, +w: +List<U32>, s: St) -> St:
  match kind:
    case 260: St.texture.set(s, wu(0n, w), wu(1n, w))
    case 261: St.texture.unset(s, wu(0n, w))
    case 262: St.shapes.set(s, wu(0n, w), wu(5n, w), wrect(1n, w))
    case 263: St.shapes.info(s)
    case _: St.query(s, wu(0n, w))

def rstep.frame(shape: Bool, +kind: U32, +w: +List<U32>, frame: J.Frame) -> J.Frame:
  match shape:
    case True{}: shape.draw(kind, w, frame)
    case False{}: call.apply(kind, w, frame)

def rstep.mine(frame_op: Bool, +kind: U32, +w: +List<U32>, s: St) -> St:
  match frame_op:
    case True{}: St.frame(s, f => rstep.frame((kind < 220 : U32), kind, w, f))
    case False{}: rstep.slot(kind, w, s)

def rstep.select(mine: Bool, +kind: U32, +w: +List<U32>, s: St) -> St:
  match mine:
    case True{}: rstep.mine((kind < 260 : U32), kind, w, s)
    case False{}: step(Op{kind, w}, s)

def rstep(op: Op, s: St) -> St:
  Op{+kind, +w} = op
  rstep.select((kind >= 200 : U32), kind, w, s)

def rexec(ops: +List<Op>, s: St) -> St:
  match ops:
    case Nil{}: s
    case Con{op, rest}: rexec(rest, rstep(op, s))

def St.rrun(ops: +List<Op>, +screen: Bool, frame: Maybe<J.Frame>) -> String:
  match frame:
    case None{}: "no frame"
    case Some{f}: St.finish(screen, rexec(ops, St.new(f)))

def table.pow(n: Nat, +i: F32) -> String:
  match n:
    case 0n: ""
    case 1n+k:
      +t = (S.spline.step() * i : F32)
      " " ++ bits.f(S.cube.value((1.0 - t : F32))) ++ " " ++ bits.f(S.cube.value(t)) ++ table.pow(k, (i + 1.0 : F32))

def table.cos.one(+gnu: Bool, +n: F32) -> String:
  +e = ((360.0 / n : F32) * S.deg2rad() : F32)
  +a = ((S.deg2rad() * e : F32) / 2.0 : F32)
  Bool.pick(String, Bool.not(gnu) || S.trig.gnu(a), " " ++ bits.f(S.cosine(Trig.sincos_for(gnu, a))), " 0")

def table.cos(n: Nat, +gnu: Bool, +sides: F32) -> String:
  match n:
    case 0n: ""
    case 1n+k: table.cos.one(gnu, sides) ++ table.cos(k, gnu, (sides + 1.0 : F32))

def table.count(count: Maybe<F32>) -> String:
  match count:
    case None{}: " none"
    case Some{+n}: " " ++ U32.show(F32.to_u32(n))

def table.arc(+radius: F32, +start: F32, +end: F32, +segments: F32) -> String:
  table.count(S.segments.resolve(1, radius, (end - start : F32), segments))

def table.corner(+radius: F32, +divisor: F32, +segments: F32) -> String:
  table.count(S.corner.segments(1, radius, divisor, segments))

# A segment-estimate row: kind 0 an arc (radius, start, end, segments), 1 a
# corner (radius, divisor, segments). Rows are data walked by one def: a
# generated chain of calls made a segment of the generated C too wide.
type Est is Data:
  Est{kind: U32, a: F32, b: F32, c: F32, d: F32}

def table.row(+row: Est) -> String:
  Est{kind, a, b, c, d} = row
  match kind:
    case 0: table.arc(a, b, c, d)
    case _: table.corner(a, b, c)

def table.rows(rows: +List<Est>) -> String:
  match rows:
    case Nil{}: ""
    case Con{row, rest}: table.row(row) ++ table.rows(rest)
'''

SHAPE_KINDS = {'bezier': 200, 'dashed': 201, 'ring_lines': 202, 'poly_ex': 203, 'poly2': 204, 'sector2': 205, 'sector_lines2': 206, 'ring2': 207,
               'rounded': 208, 'rounded_lines': 209, 'rounded_lines_ex': 210, 'spline': 211, 'segment': 212}
CALL_KINDS = {'rl_begin': 220, 'rl_end': 221, 'v2i': 222, 'v2f': 223, 'v3f': 224, 'tc': 225, 'normal': 226, 'c4ub': 227, 'c3f': 228, 'c4f': 229,
              'matrix_mode': 230, 'ortho': 231, 'frustum': 232, 'viewport': 233, 'toggle': 234, 'cull_face': 235, 'scissor': 236,
              'line_width': 237, 'point_size': 238, 'clear_color': 239, 'clear_buffers': 240, 'noops': 241}
OTHER_KINDS = {'set_texture': 260, 'set_texture_null': 261, 'shapes_tex': 262, 'shapes_info': 263, 'get': 264}
INT_CALLS = {'rl_begin', 'c4ub', 'matrix_mode', 'cull_face', 'clear_color'}
W = fp.word


def op_words(op):
    name, a = op[0], op[1:]
    if name in SHAPE_KINDS:
        kind = SHAPE_KINDS[name]
        if name in ('spline', 'segment'):
            return kind, [a[0], W(a[2]), a[3], len(a[1])] + [W(v) for p in a[1] for v in p]
        if name.startswith('rounded'):
            return kind, [W(x) for x in a[:-1]] + [a[-1]]
        return kind, [W(x) for x in a[:-1]] + [a[-1]]
    if name in CALL_KINDS:
        kind = CALL_KINDS[name]
        if name in INT_CALLS:
            return kind, list(a)
        if name == 'toggle':
            return kind, [TOGGLES[a[0]], int(a[1])]
        return kind, [W(x) for x in a]
    if name in OTHER_KINDS:
        kind = OTHER_KINDS[name]
        if name == 'shapes_tex':
            return kind, [a[0]] + [W(x) for x in a[1]] + [a[2]]
        if name == 'get':
            return kind, [GETTERS.index(a[0])]
        return kind, list(a)
    return tp.op_words(op)


def b_op(op):
    kind, words = op_words(op)
    return f'Op{{{kind}, [{", ".join(str(w) for w in words)}]}}'


def b_scene(index, scene):
    return f'def scene.{index}() -> +List<Op>:\n  [' + ',\n    '.join(b_op(op) for op in scene['ops']) + ']'


def render(libm):
    gnu = 'True{}' if libm != 'AppleLibm' else 'False{}'

    def build(selected, gpu):
        body = [PROGRAM, f'def libm() -> M.Libm:\n  M.{libm}{{}}', NEW_BEND]
        prints = []
        for kind, index, item in selected:
            if kind == 'tables':
                rows = []
                for row in estimate_rows():
                    if row[0] == 'arc':
                        rows.append(f'Est{{0, {bf(row[1])}, {bf(row[2])}, {bf(row[3])}, {bf(float(row[4]))}}}')
                    else:
                        rows.append(f'Est{{1, {bf(row[1])}, {bf(row[2])}, {bf(float(row[3]))}, 0.0}}')
                body.append('def table.estimates() -> String:\n  table.rows([' + ',\n    '.join(rows) + '])')
                prints.append('    IO.print("P" ++ table.pow(24n, 1.0))')
                prints.append(f'    IO.print("Q" ++ table.cos(4094n, {gnu}, 3.0))')
                prints.append('    IO.print("E" ++ table.estimates())')
                continue
            body.append(b_scene(index, item))
            screen = 'True{}' if item['screen'] else 'False{}'
            prints.append(f'    IO.print(St.rrun(scene.{index}(), {screen}, J.Frame.init_window({item["width"]}, {item["height"]})))')
        body.append('def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(prints) + '\n')
        return '\n\n'.join(body)
    return build


def table_expected(p_line, q_line, e_line, libm):
    """Jonlib's expected table rows from the reference: pow and cos bits as the host gives them, and the
    estimates with the contract (ub or above 4096: none)."""
    q = q_line.split()[1:]
    cos = []
    for n, value in zip(range(3, 4097), q):
        arg = f32(f32(DEG2RAD * f32(f32(360.0 / n) * DEG2RAD)) / 2.0)
        cos.append(value if fp.accepted(libm, arg) or libm == 'AppleLibm' else '0')
    est = []
    for value in e_line.split()[1:]:
        est.append('none' if value == 'ub' or int(value) > 4096 else value)
    return [p_line, 'Q ' + ' '.join(cos), 'E ' + ' '.join(est)]


FOLDED = ('DrawCircleSector', 'DrawCircleSectorLines', 'DrawRing', 'DrawRingLines', 'DrawRectangleRounded', 'DrawRectangleRoundedLinesEx')


def folded_powf(library):
    """The segment estimates call acosf but not powf: the reference compiler turned powf(x, 2) into x*x, as Jonlib does."""
    import os
    import re
    import tempfile
    directory = tempfile.mkdtemp(prefix='rlgl-objects-', dir=probekit.ROOT / '.build')
    probekit.run(['ar', 'x', library], cwd=directory)
    name = next(n for n in os.listdir(directory) if n.startswith('rshapes') and n.endswith('.o'))
    text = probekit.run(['objdump', '-d', '-r', name], cwd=directory)
    calls, current = {}, None
    for line in text.splitlines():
        header = re.match(r'^[0-9a-f]+ <_?(\w+)>:', line)
        if header:
            current = header.group(1)
            calls[current] = set()
        elif current and re.search(r'R_\w+|ARM64_RELOC_BRANCH26', line):
            target = re.search(r'\b_?(acosf|powf)\b', line)
            if target:
                calls[current].add(target.group(1))
    for function in FOLDED:
        if calls.get(function) != {'acosf'}:
            raise ProbeFailure(f'rlgl: {function} calls {sorted(calls.get(function, ()))} in the reference build, not acosf alone')
    return len(FOLDED)


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('rlgl', args, raylib_options=fp.OPTIONS)
    libm = gradient_reference()
    fused = fp.fused_instructions(probe.library)
    if any(fused.values()):
        raise ProbeFailure(f'rlgl: the reference build contains fused multiply-adds: {fused}')
    folded = folded_powf(probe.library)
    items = scenes()
    native_items = [s for s in items if not refused(s, libm)]
    contracts = [s for s in items if s not in native_items]
    include = probe.work / 'include'
    include.mkdir(parents=True, exist_ok=True)
    for name, text in qa.SHIMS.items():
        (include / name).write_text(text)
    acos_object = probe.work / 'sun239_acosf.o'
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-I' + str(include), '-D__ieee754_acosf=sun239_acosf',
                  '-c', qa.SOURCE, '-o', acos_object])
    source = (C_PREFIX.replace('int main(void)', TABLES_C + 'int main(void)') + '\n'.join(c_scene(s) for s in native_items)
              + '\n' + c_tables() + '\n    return 0;\n}\n')
    output = probe.native(source, 'reference', extra_flags=('-ffp-contract=off', str(acos_object))).splitlines()
    frames = [line for line in output if line.startswith('F ')]
    tables = {line[0]: line for line in output if line[:2] in ('P ', 'Q ', 'E ')}
    if len(frames) != len(native_items) or len(tables) != 3:
        raise ProbeFailure(f'rlgl: reference printed {len(frames)} frames for {len(native_items)} scenes and {len(tables)} tables')
    expected_by_id = {}
    for scene, line in zip(native_items, frames):
        parts = line[2:].split(' ')
        count = 1 + scene['screen']
        if 'MISMATCH' in parts:
            raise ProbeFailure(f'rlgl: {scene["id"]}: LoadImageFromScreen is not the flipped, swapped, opaque framebuffer')
        expected_by_id[scene['id']] = ' '.join(parts[:count]) + ''.join(' ' + p for p in parts[count:] if p)
    for scene in contracts:
        expected_by_id[scene['id']] = 'null' + (' null' if scene['screen'] else '')
    expected = [expected_by_id[s['id']] for s in items] + table_expected(tables['P'], tables['Q'], tables['E'], libm)
    actions = [('scene', i, s) for i, s in enumerate(items)] + [('tables', len(items), None)]

    def describe(i):
        return f'scene {items[i]["id"]}' if i < len(items) else ('pow table', 'cos table', 'estimate table')[i - len(items)]

    lanes = probe.candidates(render(libm), actions, batch=10, parse=lambda text, selected: parse_rows(text, selected))
    lanes = {lane: [part for row in rows for part in row.split('\n')] for lane, rows in lanes.items()}
    probe.compare(expected, lanes, describe=describe)
    probe.finish(scenes=len(items), compared=len(native_items), contracts=len(contracts), libm=libm,
                 operations=sum(len(s['ops']) for s in items), pow_arguments=48, cos_arguments=4094, estimates=len(estimate_rows()), folded_powf_functions=folded,
                 fused_free_objects=len(fused),
                 scenes_sha256=hashlib.sha256(json.dumps(items, default=repr).encode()).hexdigest())


def parse_rows(text, selected):
    """One row per scene and three per table action (candidates checks the count per action, so tables
    are joined into one row here and split again before the comparison)."""
    lines = [line for line in text.splitlines() if line.strip()]
    rows = []
    for kind, _, _ in selected:
        if kind == 'tables':
            rows.append('\n'.join(lines[:3]))
            lines = lines[3:]
        else:
            rows.append(lines[0])
            lines = lines[1:]
    return rows


if __name__ == '__main__':
    main()
