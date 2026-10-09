#!/usr/bin/env python3
"""Compare Jonlib's BeginMode3D/EndMode3D and rmodels.c 3D shapes with
raylib's software renderer.

Same reference as tools/rlgl_probe.py: pinned raylib on PLATFORM=Memory
(rlgl.h's OpenGL 1.1 path into src/external/rlsw.h) built with
CMAKE_C_FLAGS=-ffp-contract=off, read back with rlCopyFramebuffer. Each
scene runs InitWindow and a sequence of operations: the texture and rlgl
probes' ones plus BeginMode3D/EndMode3D (perspective and orthographic
cameras, projection values other than 0 and 1, nested modes), DrawLine3D, DrawPoint3D,
DrawCircle3D, DrawTriangle3D, DrawTriangleStrip3D, DrawCube(V),
DrawCubeWires(V), DrawSphere(Ex), DrawSphereWires, DrawCylinder(Ex),
DrawCylinderWires(Ex), DrawCapsule(Wires), DrawPlane, DrawRay, DrawGrid and
DrawBoundingBox, with the projection and modelview matrices read back by
rlGetMatrixProjection/rlGetMatrixModelview.

With --gnu-libm the reference library is built with sinf/cosf replaced by
the C model of the Arm optimized-routines polynomial that glibc ships
(tools/trig_probe.py), tan by the glibc x86_64 FMA-variant model
(tools/glibc_tan.py) and qsort by a stable merge sort (glibc's msort order),
every source including <math.h> and <stdlib.h> first, and Jonlib runs with
M.Glibc239Libm{}: the glibc profile on any host. Without it the
host libm decides (M.AppleLibm{} on macOS, whose verified set is the
integral degrees of docs/FRAME.md, so most curved shapes and every
perspective camera are refused there; on glibc hosts the native tan must
pass tools/glibc_tan.py's controls).

Contracts (Jonlib must answer null): CAMERA_PERSPECTIVE under AppleLibm or
with a zero or nonfinite frustum scale, orthographic cameras with a zero or
nonfinite fovy or span, popping the last projection (nested modes ended twice),
depth-tested drawing into a render texture, sinf/cosf arguments outside the
profile's verified set (DrawSphereWires always: its ring angles reach 450
degrees) and loop counts beyond 4096. CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import math
import random

from conformance import gradient_reference
import frame_probe as fp
import glibc_tan
import probekit
import rlgl_probe as rp
import texture_probe as tp
from probekit import ROOT, ProbeFailure

C = fp.C
f32 = fp.f32
cf = fp.cf
cc = fp.cc
W = fp.word
DEG2RAD = fp.DEG2RAD
PI = fp.from_bits(1078530011)
TWO_PI = fp.from_bits(1086918619)
RED, GREEN, BLUE, WHITE, BLACK = rp.RED, rp.GREEN, rp.BLUE, rp.WHITE, rp.BLACK
HALF = rp.HALF

KINDS = {'mode3d': 300, 'end3d': 301, 'line3d': 302, 'point3d': 303, 'circle3d': 304, 'tri3d': 305, 'strip3d': 306, 'cube': 307,
         'cube_v': 308, 'cube_wires': 309, 'cube_wires_v': 310, 'sphere': 311, 'sphere_ex': 312, 'sphere_wires': 313, 'cylinder': 314,
         'cylinder_ex': 315, 'cylinder_wires': 316, 'cylinder_wires_ex': 317, 'capsule': 318, 'capsule_wires': 319, 'plane': 320,
         'ray': 321, 'grid': 322, 'bbox': 323}


# -----------------------------------------------------------------------------
# Contract rules (mirror src/shapes3d.bend and jonlib.bend Frame.begin_mode_3d)

def c_int(value):
    return fp.c_int(value)


def finite_nonzero(x):
    return math.isfinite(x) and x != 0.0


def ortho_ok(fovy, width, height):
    span = f32(fovy * f32(width / height))
    return finite_nonzero(fovy) and finite_nonzero(span) and finite_nonzero(f32(2.0 / span)) and finite_nonzero(f32(2.0 / fovy))


TENTH = f32(0.1)
NEAR = 0.05
DEG2RAD64 = float(DEG2RAD)


def perspective_ok(libm, fovy, width, height):
    """Frame.mode_3d.perspective: the profile's binary64 tan and finite, nonzero F32 scales
    (float)(0.1f/(2*right)) and (float)(0.1f/(2*top)). The host tan stands in for the profile's
    here; it only decides finiteness, which no corpus camera puts near a boundary."""
    if libm == 'AppleLibm' or not math.isfinite(fovy):
        return False
    top = NEAR * math.tan((fovy * 0.5) * DEG2RAD64)
    right = top * f32(f32(width) / f32(height))
    if top == 0.0 or right == 0.0:
        return False
    return finite_nonzero(f32(TENTH / (2.0 * right))) and finite_nonzero(f32(TENTH / (2.0 * top)))


def all_ok(libm, args):
    return all(fp.accepted(libm, x) for x in args)


def count_ok(value, limit):
    n = c_int(value)
    return n is not None and n <= limit


def op_refused(op, libm, size):
    name, a = op[0], op[1:]
    if name == 'mode3d':
        projection, fovy = a[10], a[9]
        return (projection == 0 and not perspective_ok(libm, fovy, *size)) or (projection == 1 and not ortho_ok(fovy, *size))
    if name == 'circle3d':
        return not all_ok(libm, [f32(a[7] * DEG2RAD)] + [f32(DEG2RAD * float(d)) for d in range(0, 370, 10)])
    if name in ('sphere', 'sphere_ex'):
        rings, slices = (16.0, 16.0) if name == 'sphere' else (a[4], a[5])
        if not (count_ok(rings, 4095) and count_ok(slices, 4096)):
            return True
        r, s = c_int(rings), c_int(slices)
        if r < 0 or s < 1:
            return False
        return not all_ok(libm, [f32(DEG2RAD * f32(180.0 / f32(r + 1))), f32(DEG2RAD * f32(360.0 / s))])
    if name == 'sphere_wires':
        if not (count_ok(a[4], 4094) and count_ok(a[5], 4096)):
            return True
        r, s = c_int(a[4]), c_int(a[5])
        if r < -1 or s < 1:
            return False
        k = f32(180.0 / f32(r + 1)) if r + 1 else math.inf
        rings = [f32(DEG2RAD * f32(270.0 + f32(k * i))) if not (math.isinf(k) and i == 0) else math.nan for i in range(r + 3)]
        return not all_ok(libm, rings + [f32(DEG2RAD * f32(f32(360.0 * j) / s)) for j in range(s + 1)])
    if name in ('cylinder', 'cylinder_wires'):
        if not count_ok(a[6], 4096):
            return True
        n = max(c_int(a[6]), 3)
        step = f32(360.0 / n)
        return not all_ok(libm, [f32(f32(DEG2RAD * i) * step) for i in range(n + 1)])
    if name in ('cylinder_ex', 'cylinder_wires_ex'):
        if not count_ok(a[8], 4096):
            return True
        if all(f32(a[3 + i] - a[i]) == 0.0 for i in range(3)):
            return False
        n = max(c_int(a[8]), 3)
        step = f32(TWO_PI / n)
        return not all_ok(libm, [f32(step * i) for i in range(n + 1)])
    if name in ('capsule', 'capsule_wires'):
        if not (count_ok(a[7], 4096) and count_ok(a[8], 4096)):
            return True
        n, r = max(c_int(a[7]), 3), c_int(a[8])
        sphere = all(f32(a[3 + i] - a[i]) == 0.0 for i in range(3))
        slices = [f32(f32(TWO_PI / n) * j) for j in range(n + 1)]
        rings = [f32(f32(f32(PI * 0.5) / r) * i) for i in range(r + 1)] if r >= 1 else []
        used = r >= 1 or not sphere
        return not ((not used or all_ok(libm, slices)) and all_ok(libm, rings))
    if name == 'grid':
        n = c_int(a[0])
        return n is None or abs(int(n / 2)) > 2048
    return False


def refused(scene, libm):
    if scene.get('contract'):
        return True
    plain = dict(scene, ops=[op for op in scene['ops'] if op[0] not in KINDS])
    if rp.refused(plain, libm):
        return True
    size = (scene['width'], scene['height'])
    return any(op_refused(op, libm, size) for op in scene['ops'] if op[0] in KINDS)


# -----------------------------------------------------------------------------
# Scenes

def v3(x, y, z):
    return (f32(x), f32(y), f32(z))


def camera(position, target, up=(0.0, 1.0, 0.0), fovy=8.0, projection=1):
    return ('mode3d',) + v3(*position) + v3(*target) + v3(*up) + (f32(fovy), projection)


def scenes():
    rng = random.Random(0x3D3D)
    out = []

    def add(name, width, height, ops, contract=False):
        out.append(dict(id=name, width=width, height=height, ops=ops, screen=False, contract=contract))

    front = camera((0.0, 0.0, 10.0), (0.0, 0.0, 0.0))
    angled = camera((5.0, 4.0, 6.0), (0.0, 0.5, 0.0), fovy=7.0)
    add('m3-basic', 40, 30, [('begin',), ('clear', C(30, 30, 40)), front, ('get', 'projection'), ('get', 'modelview'),
                             ('cube',) + v3(-1.5, 0.5, 0.0) + (2.0, 2.0, 2.0, RED), ('cube_wires',) + v3(-1.5, 0.5, 0.0) + (2.0, 2.0, 2.0, WHITE),
                             ('line3d',) + v3(-4.0, -3.0, 1.0) + v3(4.0, 2.5, -1.0) + (GREEN,), ('point3d',) + v3(2.5, 2.5, 0.0) + (WHITE,),
                             ('tri3d',) + v3(1.0, -3.0, 0.5) + v3(4.0, -3.0, 0.5) + v3(2.5, 0.0, -0.5) + (HALF[2],),
                             ('tri3d',) + v3(1.0, -3.0, 0.5) + v3(2.5, 0.0, -0.5) + v3(4.0, -3.0, 0.5) + (RED,),
                             ('end3d',), ('get', 'projection'), ('rect', 1.0, 1.0, 6.0, 4.0, HALF[0]), ('end',)])
    add('m3-angled', 40, 30, [('begin',), ('clear', BLACK), angled, ('get', 'modelview'), ('grid', 8.0, 1.0),
                              ('cube_v',) + v3(0.0, 0.5, 0.0) + v3(1.0, 1.0, 1.0) + (BLUE,), ('cube_wires_v',) + v3(0.0, 0.5, 0.0) + v3(1.2, 1.2, 1.2) + (WHITE,),
                              ('plane',) + v3(1.5, 0.0, -1.5) + (f32(2.0), f32(1.5)) + (GREEN,),
                              ('ray',) + v3(-2.0, 0.25, 2.0) + v3(0.5, 0.0, -0.25) + (RED,),
                              ('bbox',) + v3(-2.5, 0.0, -0.5) + v3(-1.5, 1.5, 0.5) + (HALF[1],), ('end3d',), ('end',)])
    add('m3-grid', 32, 24, [('begin',), ('clear', BLACK), camera((3.0, 6.0, 3.0), (0.0, 0.0, 0.0), fovy=9.0), ('grid', 7.0, 1.25),
                            ('grid', 2.0, 0.5), ('grid', -3.0, 1.0), ('grid', 0.0, 1.0), ('end3d',), ('end',)])
    add('m3-strip-circle', 40, 30, [('begin',), ('clear', C(10, 10, 10)), front,
                                    ('strip3d', [v3(-4, -3, 0), v3(-3, -1, 0.5), v3(-2, -3, 0), v3(-1, -1, -0.5), v3(0, -3, 0), v3(1, -1, 0.25)], HALF[0]),
                                    ('strip3d', [v3(2, 2, 0), v3(3, 3, 0)], WHITE),
                                    ('circle3d',) + v3(2.0, 1.0, 0.0) + (f32(1.5),) + v3(1.0, 0.0, 0.0) + (f32(90.0), GREEN),
                                    ('circle3d',) + v3(-2.0, 1.5, 0.0) + (f32(1.0),) + v3(0.0, 1.0, 0.0) + (f32(45.0), RED),
                                    ('circle3d',) + v3(2.5, -2.0, 0.0) + (f32(1.25),) + v3(0.0, 0.0, 2.0) + (f32(0.0), WHITE), ('end3d',), ('end',)])
    add('m3-spheres', 40, 30, [('begin',), ('clear', BLACK), angled, ('sphere_ex',) + v3(0.0, 0.5, 0.0) + (f32(1.5), 8.0, 12.0, RED),
                               ('sphere_ex',) + v3(2.0, 0.0, -1.0) + (f32(0.75), 5.0, 6.0, HALF[2]), ('sphere_ex',) + v3(-2.0, 1.0, 1.0) + (f32(0.5), -1.0, 4.0, WHITE),
                               ('end3d',), ('end',)])
    add('m3-sphere-default', 32, 24, [('begin',), ('clear', C(20, 20, 60)), angled, ('sphere',) + v3(0.0, 0.5, 0.0) + (f32(1.75), GREEN),
                                      ('sphere_ex',) + v3(1.5, 1.5, 0.0) + (f32(0.5), 3.0, 7.0, HALF[0]), ('end3d',), ('end',)])
    add('m3-cylinders', 40, 30, [('begin',), ('clear', BLACK), angled,
                                 ('cylinder',) + v3(-1.5, 0.0, 0.0) + (f32(0.75), f32(1.0), f32(2.0), 6.0, RED),
                                 ('cylinder',) + v3(1.5, 0.0, -1.0) + (f32(0.0), f32(1.0), f32(1.5), 8.0, HALF[2]),
                                 ('cylinder_wires',) + v3(0.0, 0.0, 1.5) + (f32(0.5), f32(0.5), f32(1.0), 2.0, WHITE),
                                 ('cylinder',) + v3(2.0, 0.0, 2.0) + (f32(0.5), f32(0.25), f32(0.5), 4.0, GREEN), ('end3d',), ('end',)])
    add('m3-cylinders-ex', 40, 30, [('begin',), ('clear', BLACK), front,
                                    ('cylinder_ex',) + v3(-3.0, -2.0, 0.0) + v3(-1.0, 2.0, -1.0) + (f32(0.75), f32(0.25), 8.0, RED),
                                    ('cylinder_ex',) + v3(1.0, -2.0, 0.0) + v3(3.0, 1.0, 0.0) + (f32(0.0), f32(1.0), 5.0, HALF[1]),
                                    ('cylinder_wires_ex',) + v3(0.0, 2.0, 1.0) + v3(3.0, 3.0, -1.0) + (f32(0.5), f32(0.5), 6.0, WHITE),
                                    ('cylinder_ex',) + v3(0.0, 0.0, 0.0) + v3(0.0, 0.0, 0.0) + (f32(1.0), f32(1.0), 8.0, BLUE), ('end3d',), ('end',)])
    add('m3-capsules', 40, 30, [('begin',), ('clear', C(5, 20, 5)), angled,
                                ('capsule',) + v3(-1.5, 0.0, 0.0) + v3(-1.5, 2.0, 0.0) + (f32(0.6), 8.0, 4.0, RED),
                                ('capsule_wires',) + v3(1.0, 0.5, -1.0) + v3(2.5, 1.0, 0.5) + (f32(0.5), 6.0, 3.0, WHITE),
                                ('capsule',) + v3(1.5, 0.0, 2.0) + v3(1.5, 0.0, 2.0) + (f32(0.5), 5.0, 2.0, HALF[2]), ('end3d',), ('end',)])
    add('m3-identity-projection', 32, 24, [('begin',), ('clear', BLACK), camera((0.0, 0.0, 0.5), (0.0, 0.0, 0.0), projection=2), ('get', 'projection'),
                                           ('cube',) + v3(0.0, 0.0, 0.0) + (0.5, 0.5, 0.5, RED), ('line3d',) + v3(-0.9, -0.9, 0.0) + v3(0.9, 0.8, 0.0) + (WHITE,),
                                           ('end3d',), ('end',)])
    add('m3-nested', 32, 24, [('begin',), ('clear', BLACK), front, angled, ('cube',) + v3(0.0, 0.5, 0.0) + (1.0, 1.0, 1.0, RED), ('end3d',),
                              ('get', 'projection'), ('end',)])
    add('m3-aspect', 24, 40, [('begin',), ('clear', BLACK), camera((0.0, 5.0, 0.0), (0.0, 0.0, 0.0), up=(0.0, 0.0, -1.0), fovy=-6.0),
                              ('get', 'projection'), ('plane',) + v3(0.0, 0.0, 0.0) + (f32(3.0), f32(4.0)) + (HALF[0],),
                              ('cube_wires',) + v3(0.0, 0.0, 0.0) + (2.0, 1.0, 3.0, WHITE), ('end3d',), ('end',)])

    # Perspective cameras: the profile's binary64 tan reaches the frustum's m0/m5 (refused under AppleLibm).
    classic = camera((10.0, 10.0, 10.0), (0.0, 0.0, 0.0), fovy=45.0, projection=0)
    add('m3-persp-classic', 40, 30, [('begin',), ('clear', C(245, 245, 245)), classic, ('get', 'projection'), ('get', 'modelview'),
                                     ('cube',) + v3(0.0, 0.0, 0.0) + (2.0, 2.0, 2.0, RED), ('cube_wires',) + v3(0.0, 0.0, 0.0) + (2.0, 2.0, 2.0, C(190, 33, 55)),
                                     ('grid', 10.0, 1.0), ('end3d',), ('end',)])
    add('m3-persp-wide', 32, 24, [('begin',), ('clear', BLACK), camera((0.0, 2.0, 6.0), (0.0, 0.5, 0.0), fovy=90.0, projection=0), ('get', 'projection'),
                                  ('plane',) + v3(0.0, 0.0, 0.0) + (f32(6.0), f32(6.0)) + (GREEN,),
                                  ('cube_v',) + v3(-1.0, 0.5, 0.0) + v3(1.0, 1.0, 1.0) + (BLUE,),
                                  ('line3d',) + v3(-3.0, 0.0, 2.0) + v3(3.0, 2.0, -2.0) + (WHITE,), ('point3d',) + v3(1.5, 1.5, 1.0) + (RED,),
                                  ('tri3d',) + v3(0.5, 0.0, 1.0) + v3(2.5, 0.0, 1.0) + v3(1.5, 1.5, 0.0) + (HALF[2],),
                                  ('bbox',) + v3(1.0, 0.0, -1.5) + v3(2.0, 1.0, -0.5) + (HALF[1],),
                                  ('ray',) + v3(-2.0, 0.25, 2.0) + v3(0.5, 0.0, -0.25) + (RED,), ('end3d',), ('end',)])
    add('m3-persp-portrait', 24, 40, [('begin',), ('clear', C(10, 10, 30)), camera((3.0, 4.0, 5.0), (0.0, 0.0, 0.0), fovy=20.5, projection=0),
                                      ('get', 'projection'), ('cube',) + v3(0.0, 0.5, 0.0) + (1.0, 1.0, 1.0, HALF[0]),
                                      ('cube_wires',) + v3(0.0, 0.5, 0.0) + (1.0, 1.0, 1.0, WHITE), ('grid', 6.0, 0.5), ('end3d',), ('end',)])
    add('m3-persp-negative-fovy', 32, 24, [('begin',), ('clear', BLACK), camera((4.0, 3.0, 4.0), (0.0, 0.0, 0.0), fovy=-45.0, projection=0),
                                           ('get', 'projection'), ('cube',) + v3(0.0, 0.0, 0.0) + (1.5, 1.0, 0.5, RED), ('grid', 4.0, 1.0), ('end3d',), ('end',)])
    add('m3-persp-inside', 32, 24, [('begin',), ('clear', BLACK), camera((0.0, 0.0, 0.0), (0.0, 0.0, -1.0), fovy=60.0, projection=0),
                                    ('toggle', 'cull', False), ('cube',) + v3(0.0, 0.0, 0.0) + (3.0, 2.0, 4.0, HALF[1]),
                                    ('tri3d',) + v3(-5.0, -1.0, 1.0) + v3(5.0, -1.0, 1.0) + v3(0.0, 1.0, -8.0) + (GREEN,), ('end3d',), ('end',)])
    # As m3-nested: the second push is ignored (rlsw's two-entry stack), so one EndMode3D ends both.
    add('m3-persp-nested', 32, 24, [('begin',), ('clear', BLACK), classic, front, ('cube',) + v3(0.0, 0.0, 0.0) + (1.0, 1.0, 1.0, RED), ('end3d',),
                                    ('get', 'projection'), ('end',)])

    # Contracts.
    add('m3-persp-fovy-zero', 16, 12, [camera((0.0, 0.0, 5.0), (0.0, 0.0, 0.0), fovy=0.0, projection=0)])
    add('m3-perspective', 16, 12, [camera((0.0, 0.0, 5.0), (0.0, 0.0, 0.0), fovy=45.0, projection=0)])
    add('m3-fovy-zero', 16, 12, [camera((0.0, 0.0, 5.0), (0.0, 0.0, 0.0), fovy=0.0)])
    add('m3-fovy-nan', 16, 12, [camera((0.0, 0.0, 5.0), (0.0, 0.0, 0.0), fovy=math.nan)])
    add('m3-end-twice', 16, 12, [front, ('end3d',), ('end3d',)], contract=True)
    add('m3-sphere-wires', 16, 12, [front, ('sphere_wires',) + v3(0.0, 0.0, 0.0) + (f32(1.0), 4.0, 6.0, WHITE)])
    add('m3-render-texture', 16, 12, [('load_rt', 0, 8, 8), ('begin_rt', 0), front, ('cube',) + v3(0.0, 0.0, 0.0) + (1.0, 1.0, 1.0, RED),
                                      ('end3d',), ('end_rt', 0)], contract=True)
    add('m3-cylinder-sides', 16, 12, [front, ('cylinder',) + v3(0.0, 0.0, 0.0) + (f32(1.0), f32(1.0), f32(1.0), 5000.0, RED)])

    # Random orthographic scenes of cubes, lines, triangles and points.
    for index in range(6):
        w, h = rng.choice(((32, 24), (24, 32), (40, 30)))
        position = (rng.uniform(-6, 6), rng.uniform(1, 6), rng.uniform(-6, 6))
        ops = [('begin',), ('clear', C(rng.randrange(256), rng.randrange(256), rng.randrange(256))),
               camera(position, (rng.uniform(-0.5, 0.5), 0.0, rng.uniform(-0.5, 0.5)), fovy=rng.uniform(4, 9))]
        if rng.random() < 0.3:
            ops.append(('toggle', 'cull', False))
        for _ in range(rng.randint(4, 8)):
            kind = rng.choice(('cube', 'cube_wires', 'line3d', 'tri3d', 'point3d', 'bbox'))
            color = C(rng.randrange(256), rng.randrange(256), rng.randrange(256), rng.choice((255, 255, 128)))
            p = v3(rng.uniform(-2, 2), rng.uniform(-1, 2), rng.uniform(-2, 2))
            if kind in ('cube', 'cube_wires'):
                ops.append((kind,) + p + (f32(rng.uniform(0.3, 2)), f32(rng.uniform(0.3, 2)), f32(rng.uniform(0.3, 2)), color))
            elif kind == 'line3d':
                ops.append((kind,) + p + v3(rng.uniform(-3, 3), rng.uniform(-1, 3), rng.uniform(-3, 3)) + (color,))
            elif kind == 'tri3d':
                ops.append((kind,) + p + v3(rng.uniform(-3, 3), rng.uniform(-1, 3), rng.uniform(-3, 3))
                           + v3(rng.uniform(-3, 3), rng.uniform(-1, 3), rng.uniform(-3, 3)) + (color,))
            elif kind == 'point3d':
                ops.append((kind,) + p + (color,))
            else:
                q = v3(rng.uniform(-2, 2), rng.uniform(-1, 2), rng.uniform(-2, 2))
                ops.append((kind,) + p + q + (color,))
        ops += [('end3d',), ('end',)]
        add(f'm3-random-{index}', w, h, ops)

    # Random perspective scenes, as raylib's examples use them.
    for index in range(4):
        w, h = rng.choice(((32, 24), (40, 30), (24, 32)))
        position = (rng.uniform(-12, 12), rng.uniform(1, 12), rng.uniform(-12, 12))
        ops = [('begin',), ('clear', C(rng.randrange(256), rng.randrange(256), rng.randrange(256))),
               camera(position, (rng.uniform(-1, 1), rng.uniform(0, 1), rng.uniform(-1, 1)), fovy=rng.uniform(20, 100), projection=0),
               ('get', 'projection'), ('grid', 10.0, 1.0)]
        for _ in range(rng.randint(3, 6)):
            kind = rng.choice(('cube', 'cube_wires', 'line3d', 'tri3d', 'point3d'))
            color = C(rng.randrange(256), rng.randrange(256), rng.randrange(256), rng.choice((255, 255, 128)))
            p = v3(rng.uniform(-3, 3), rng.uniform(0, 3), rng.uniform(-3, 3))
            if kind in ('cube', 'cube_wires'):
                ops.append((kind,) + p + (f32(rng.uniform(0.5, 3)), f32(rng.uniform(0.5, 3)), f32(rng.uniform(0.5, 3)), color))
            elif kind == 'line3d':
                ops.append((kind,) + p + v3(rng.uniform(-4, 4), rng.uniform(0, 4), rng.uniform(-4, 4)) + (color,))
            elif kind == 'tri3d':
                ops.append((kind,) + p + v3(rng.uniform(-4, 4), rng.uniform(0, 4), rng.uniform(-4, 4))
                           + v3(rng.uniform(-4, 4), rng.uniform(0, 4), rng.uniform(-4, 4)) + (color,))
            else:
                ops.append((kind,) + p + (color,))
        ops += [('end3d',), ('end',)]
        add(f'm3-persp-random-{index}', w, h, ops)
    return out


# -----------------------------------------------------------------------------
# C reference

def cv3(x, y, z):
    return f'(Vector3){{ {cf(x)}, {cf(y)}, {cf(z)} }}'


def c_op(op):
    name, a = op[0], op[1:]
    if name not in KINDS:
        return rp.c_op(op)
    ci = fp.ci
    calls = {
        'mode3d': lambda: f'BeginMode3D((Camera3D){{ {cv3(*a[0:3])}, {cv3(*a[3:6])}, {cv3(*a[6:9])}, {cf(a[9])}, {a[10]} }});',
        'end3d': lambda: 'EndMode3D();',
        'line3d': lambda: f'DrawLine3D({cv3(*a[0:3])}, {cv3(*a[3:6])}, {cc(a[6])});',
        'point3d': lambda: f'DrawPoint3D({cv3(*a[0:3])}, {cc(a[3])});',
        'circle3d': lambda: f'DrawCircle3D({cv3(*a[0:3])}, {cf(a[3])}, {cv3(*a[4:7])}, {cf(a[7])}, {cc(a[8])});',
        'tri3d': lambda: f'DrawTriangle3D({cv3(*a[0:3])}, {cv3(*a[3:6])}, {cv3(*a[6:9])}, {cc(a[9])});',
        'strip3d': lambda: (f'DrawTriangleStrip3D((Vector3[]){{ {", ".join(cv3(*p) for p in a[0])} }}, {len(a[0])}, {cc(a[1])});'),
        'cube': lambda: f'DrawCube({cv3(*a[0:3])}, {cf(a[3])}, {cf(a[4])}, {cf(a[5])}, {cc(a[6])});',
        'cube_v': lambda: f'DrawCubeV({cv3(*a[0:3])}, {cv3(*a[3:6])}, {cc(a[6])});',
        'cube_wires': lambda: f'DrawCubeWires({cv3(*a[0:3])}, {cf(a[3])}, {cf(a[4])}, {cf(a[5])}, {cc(a[6])});',
        'cube_wires_v': lambda: f'DrawCubeWiresV({cv3(*a[0:3])}, {cv3(*a[3:6])}, {cc(a[6])});',
        'sphere': lambda: f'DrawSphere({cv3(*a[0:3])}, {cf(a[3])}, {cc(a[4])});',
        'sphere_ex': lambda: f'DrawSphereEx({cv3(*a[0:3])}, {cf(a[3])}, {ci(a[4])}, {ci(a[5])}, {cc(a[6])});',
        'sphere_wires': lambda: f'DrawSphereWires({cv3(*a[0:3])}, {cf(a[3])}, {ci(a[4])}, {ci(a[5])}, {cc(a[6])});',
        'cylinder': lambda: f'DrawCylinder({cv3(*a[0:3])}, {cf(a[3])}, {cf(a[4])}, {cf(a[5])}, {ci(a[6])}, {cc(a[7])});',
        'cylinder_wires': lambda: f'DrawCylinderWires({cv3(*a[0:3])}, {cf(a[3])}, {cf(a[4])}, {cf(a[5])}, {ci(a[6])}, {cc(a[7])});',
        'cylinder_ex': lambda: f'DrawCylinderEx({cv3(*a[0:3])}, {cv3(*a[3:6])}, {cf(a[6])}, {cf(a[7])}, {ci(a[8])}, {cc(a[9])});',
        'cylinder_wires_ex': lambda: f'DrawCylinderWiresEx({cv3(*a[0:3])}, {cv3(*a[3:6])}, {cf(a[6])}, {cf(a[7])}, {ci(a[8])}, {cc(a[9])});',
        'capsule': lambda: f'DrawCapsule({cv3(*a[0:3])}, {cv3(*a[3:6])}, {cf(a[6])}, {ci(a[7])}, {ci(a[8])}, {cc(a[9])});',
        'capsule_wires': lambda: f'DrawCapsuleWires({cv3(*a[0:3])}, {cv3(*a[3:6])}, {cf(a[6])}, {ci(a[7])}, {ci(a[8])}, {cc(a[9])});',
        'plane': lambda: f'DrawPlane({cv3(*a[0:3])}, {fp.cv(a[3], a[4])}, {cc(a[5])});',
        'ray': lambda: f'DrawRay((Ray){{ {cv3(*a[0:3])}, {cv3(*a[3:6])} }}, {cc(a[6])});',
        'grid': lambda: f'DrawGrid({ci(a[0])}, {cf(a[1])});',
        'bbox': lambda: f'DrawBoundingBox((BoundingBox){{ {cv3(*a[0:3])}, {cv3(*a[3:6])} }}, {cc(a[6])});',
    }
    return '    ' + calls[name]()


def c_scene(scene):
    lines = ['    { Texture2D t[4] = { 0 }; RenderTexture2D r[2] = { 0 }; (void)t; (void)r;', f'    InitWindow({scene["width"]}, {scene["height"]}, "");']
    lines += [c_op(op) for op in scene['ops']]
    lines += [f'    dump({scene["width"]}, {scene["height"]}, {int(scene["screen"])});', '    CloseWindow(); }']
    return '\n'.join(lines)


# -----------------------------------------------------------------------------
# Bend candidate

MODELS_BEND = '''
def wv3(n: Nat, +ws: +List<U32>) -> M.Vector3:
  +rest = word.drop(n, ws)
  M.Vector3{wf(0n, rest), wf(1n, rest), wf(2n, rest)}

def wpoints3(n: Nat, +ws: +List<U32>) -> +List<M.Vector3>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{wv3(0n, ws), wpoints3(k, word.drop(3n, ws))}

def wcamera(+w: +List<U32>) -> J.Camera3D:
  J.Camera3D{wv3(0n, w), wv3(3n, w), wv3(6n, w), wf(9n, w), wu(10n, w)}

# 3D operations (kinds 300..).
def m3.draw(kind: U32, +w: +List<U32>, frame: J.Frame) -> J.Frame:
  match kind:
    case 300: J.Frame.begin_mode_3d_for(libm(), frame, wcamera(w))
    case 301: J.Frame.end_mode_3d(frame)
    case 302: J.Draw.line_3d(frame, wv3(0n, w), wv3(3n, w), wu(6n, w))
    case 303: J.Draw.point_3d(frame, wv3(0n, w), wu(3n, w))
    case 304: J.Draw.circle_3d_for(libm(), frame, wv3(0n, w), wf(3n, w), wv3(4n, w), wf(7n, w), wu(8n, w))
    case 305: J.Draw.triangle_3d(frame, wv3(0n, w), wv3(3n, w), wv3(6n, w), wu(9n, w))
    case 306: J.Draw.triangle_strip_3d(frame, wpoints3(U32.to_nat(wu(1n, w)), word.drop(2n, w)), wu(0n, w))
    case 307: J.Draw.cube(frame, wv3(0n, w), wf(3n, w), wf(4n, w), wf(5n, w), wu(6n, w))
    case 308: J.Draw.cube_v(frame, wv3(0n, w), wv3(3n, w), wu(6n, w))
    case 309: J.Draw.cube_wires(frame, wv3(0n, w), wf(3n, w), wf(4n, w), wf(5n, w), wu(6n, w))
    case 310: J.Draw.cube_wires_v(frame, wv3(0n, w), wv3(3n, w), wu(6n, w))
    case 311: J.Draw.sphere_for(libm(), frame, wv3(0n, w), wf(3n, w), wu(4n, w))
    case 312: J.Draw.sphere_ex_for(libm(), frame, wv3(0n, w), wf(3n, w), wf(4n, w), wf(5n, w), wu(6n, w))
    case 313: J.Draw.sphere_wires_for(libm(), frame, wv3(0n, w), wf(3n, w), wf(4n, w), wf(5n, w), wu(6n, w))
    case 314: J.Draw.cylinder_for(libm(), frame, wv3(0n, w), wf(3n, w), wf(4n, w), wf(5n, w), wf(6n, w), wu(7n, w))
    case 315: J.Draw.cylinder_ex_for(libm(), frame, wv3(0n, w), wv3(3n, w), wf(6n, w), wf(7n, w), wf(8n, w), wu(9n, w))
    case 316: J.Draw.cylinder_wires_for(libm(), frame, wv3(0n, w), wf(3n, w), wf(4n, w), wf(5n, w), wf(6n, w), wu(7n, w))
    case 317: J.Draw.cylinder_wires_ex_for(libm(), frame, wv3(0n, w), wv3(3n, w), wf(6n, w), wf(7n, w), wf(8n, w), wu(9n, w))
    case 318: J.Draw.capsule_for(libm(), frame, wv3(0n, w), wv3(3n, w), wf(6n, w), wf(7n, w), wf(8n, w), wu(9n, w))
    case 319: J.Draw.capsule_wires_for(libm(), frame, wv3(0n, w), wv3(3n, w), wf(6n, w), wf(7n, w), wf(8n, w), wu(9n, w))
    case 320: J.Draw.plane(frame, wv3(0n, w), wv(3n, w), wu(5n, w))
    case 321: J.Draw.ray(frame, J.Ray{wv3(0n, w), wv3(3n, w)}, wu(6n, w))
    case 322: J.Draw.grid(frame, wf(0n, w), wf(1n, w))
    case _: J.Draw.bounding_box(frame, J.BoundingBox{wv3(0n, w), wv3(3n, w)}, wu(6n, w))

def mstep.select(mine: Bool, +kind: U32, +w: +List<U32>, s: St) -> St:
  match mine:
    case True{}: St.frame(s, f => m3.draw(kind, w, f))
    case False{}: rstep(Op{kind, w}, s)

def mstep(op: Op, s: St) -> St:
  Op{+kind, +w} = op
  mstep.select((kind >= 300 : U32), kind, w, s)

def mexec(ops: +List<Op>, s: St) -> St:
  match ops:
    case Nil{}: s
    case Con{op, rest}: mexec(rest, mstep(op, s))

def St.mrun(ops: +List<Op>, +screen: Bool, frame: Maybe<J.Frame>) -> String:
  match frame:
    case None{}: "no frame"
    case Some{f}: St.finish(screen, mexec(ops, St.new(f)))
'''


def op_words(op):
    name, a = op[0], op[1:]
    if name not in KINDS:
        return rp.op_words(op)
    kind = KINDS[name]
    if name == 'strip3d':
        return kind, [a[1], len(a[0])] + [W(v) for p in a[0] for v in p]
    if name == 'mode3d':
        return kind, [W(x) for x in a[:10]] + [a[10]]
    if name == 'end3d':
        return kind, []
    if name == 'grid':
        return kind, [W(x) for x in a]
    return kind, [W(x) for x in a[:-1]] + [a[-1]]


def b_op(op):
    kind, words = op_words(op)
    return f'Op{{{kind}, [{", ".join(str(w) for w in words)}]}}'


def b_scene(index, scene):
    return f'def scene.{index}() -> +List<Op>:\n  [' + ',\n    '.join(b_op(op) for op in scene['ops']) + ']'


def render(libm):
    def build(selected, gpu):
        body = [rp.PROGRAM, f'def libm() -> M.Libm:\n  M.{libm}{{}}', rp.NEW_BEND, MODELS_BEND]
        prints = []
        for index, item in selected:
            body.append(b_scene(index, item))
            prints.append(f'    IO.print(St.mrun(scene.{index}(), False{{}}, J.Frame.init_window({item["width"]}, {item["height"]})))')
        body.append('def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(prints) + '\n')
        return '\n\n'.join(body)
    return build


# -----------------------------------------------------------------------------
# The Arm sinf/cosf model as the reference's libm (--gnu-libm)

GNU_DIR = ROOT / '.build' / 'arm-libm'


QSORT_MODEL = r'''
#include <stdlib.h>
#include <string.h>
/* A stable merge sort: glibc's qsort (msort) orders equal keys stably. */
void model_qsort(void *base, size_t n, size_t size, int (*cmp)(const void *, const void *))
{
    if (n < 2) return;
    char *a = base, *t = malloc(n*size);
    for (size_t width = 1; width < n; width *= 2)
    {
        for (size_t lo = 0; lo < n; lo += 2*width)
        {
            size_t mid = (lo + width < n)? lo + width : n, hi = (lo + 2*width < n)? lo + 2*width : n, i = lo, j = mid, k = lo;
            while (i < mid && j < hi) { if (cmp(a + j*size, a + i*size) < 0) memcpy(t + (k++)*size, a + (j++)*size, size); else memcpy(t + (k++)*size, a + (i++)*size, size); }
            while (i < mid) memcpy(t + (k++)*size, a + (i++)*size, size);
            while (j < hi) memcpy(t + (k++)*size, a + (j++)*size, size);
        }
        memcpy(a, t, n*size);
    }
    free(t);
}
'''


def gnu_model():
    """Write the glibc-profile model source (the Arm sinf/cosf polynomial and a stable qsort) and the header
    every reference source includes first; return their paths."""
    from trig_probe import REFERENCE as TRIG_REFERENCE
    model = TRIG_REFERENCE[TRIG_REFERENCE.index('/* Arm'):TRIG_REFERENCE.index('int main')].replace('\\\\', '\\')
    GNU_DIR.mkdir(parents=True, exist_ok=True)
    source = GNU_DIR / 'glibc_model.c'
    source.write_text(model + 'float model_sinf(float x) { float c, s; arm_model(x, &c, &s); return s; }\n'
                      'float model_cosf(float x) { float c, s; arm_model(x, &c, &s); return c; }\n' + QSORT_MODEL)
    header = GNU_DIR / 'glibc_model.h'
    # <math.h> and <stdlib.h> first: glibc's declarations expand the names, which must not be renamed yet.
    header.write_text('#include <math.h>\n#include <stdlib.h>\n#define sinf model_sinf\n#define cosf model_cosf\n#define qsort model_qsort\n'
                      f'#define tan {glibc_tan.SYMBOL}\n'
                      'float model_sinf(float);\nfloat model_cosf(float);\n'
                      f'double {glibc_tan.SYMBOL}(double);\n'
                      'void model_qsort(void *, size_t, size_t, int (*)(const void *, const void *));\n')
    return source, header


def configure(parser):
    parser.add_argument('--gnu-libm', action='store_true',
                        help='build the reference with the Arm sinf/cosf model and run Jonlib with M.Glibc239Libm{}')


def main():
    args = probekit.arguments(__doc__, configure)
    options = fp.OPTIONS
    extra = ('-ffp-contract=off',)
    if args.gnu_libm:
        source, header = gnu_model()
        options = (f'CMAKE_C_FLAGS=-ffp-contract=off -include {header}',)
    probe = probekit.Probe('models-gnu' if args.gnu_libm else 'models', args, raylib_options=options)
    libm = 'Glibc239Libm' if args.gnu_libm else gradient_reference()
    fused = fp.fused_instructions(probe.library)
    if any(fused.values()):
        raise ProbeFailure(f'models: the reference build contains fused multiply-adds: {fused}')
    if args.gnu_libm:
        model_object = GNU_DIR / 'glibc_model.o'
        probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-c', source, '-o', model_object])
        extra += (str(model_object), *map(str, glibc_tan.objects(probe)))
    elif libm != 'AppleLibm' and not glibc_tan.host_is_model(probe):
        raise ProbeFailure('models: the host tan is not the glibc x86_64 FMA-variant model of the glibc profiles')
    items = scenes()
    native_items = [s for s in items if not refused(s, libm)]
    contracts = [s for s in items if s not in native_items]
    if len(native_items) < 8 or len(contracts) < 7:
        raise ProbeFailure(f'models: {len(native_items)} compared and {len(contracts)} refused scenes; the corpus lost coverage')
    source_text = rp.C_PREFIX + '\n'.join(c_scene(s) for s in native_items) + '\n    return 0;\n}\n'
    output = probe.native(source_text, 'reference', extra_flags=extra).splitlines()
    frames = [line for line in output if line.startswith('F ')]
    if len(frames) != len(native_items):
        raise ProbeFailure(f'models: reference printed {len(frames)} frames for {len(native_items)} scenes')
    expected_by_id = {}
    for scene, line in zip(native_items, frames):
        parts = line[2:].split(' ')
        expected_by_id[scene['id']] = parts[0] + ''.join(' ' + p for p in parts[1:] if p)
    for scene in contracts:
        expected_by_id[scene['id']] = 'null'
    expected = [expected_by_id[s['id']] for s in items]
    actions = list(enumerate(items))
    lanes = probe.candidates(render(libm), actions, batch=8, parse=lambda text, selected: [line for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda i: f'scene {items[i]["id"]}')
    probe.finish(scenes=len(items), compared=len(native_items), contracts=len(contracts), libm=libm,
                 reference='Arm sinf/cosf model build' if args.gnu_libm else 'host libm build',
                 operations=sum(len(s['ops']) for s in items), fused_free_objects=len(fused),
                 refused=[s['id'] for s in contracts],
                 scenes_sha256=hashlib.sha256(json.dumps(items, default=repr).encode()).hexdigest())


if __name__ == '__main__':
    main()
