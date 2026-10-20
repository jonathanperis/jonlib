#!/usr/bin/env python3
"""Compare Jonlib's GenMeshCylinder, GenMeshCone and GenMeshKnot with the pinned raylib.

Each case is generated natively (GenMeshCylinder, GenMeshCone or GenMeshKnot
of the raylib built with -ffp-contract=off) and with Jonlib
(Mesh.gen_cylinder_for, Mesh.gen_cone_for and Mesh.gen_knot_for under
M.Uncontracted{}). A row has the vertex and triangle
counts and an FNV-1a hash of the words of the vertices, of the texture
coordinates and of the normals, in the mesh's order.

The cases: 3 to 40 slices; radii and heights that differ (the normals are
rescaled and normalized) and that are equal (they are not); a zero radius, a
zero height and both (par_shapes' zero-scale rules); negative ones. Knots:
the one models_mesh_generation makes (16 x 128), the smallest (3 x 3), radii
below and above the clamp, a zero and a negative size. The disks and the
trefoil take the binary64 cos and sin: the rows are compared on a host whose
own functions reproduce the glibc 2.39 controls (tools/glibc_sin.py), under
M.Glibc239Libm. On another host or profile every case is a contract (Jonlib
must answer None). Contracts on every host, the reference not run: fewer
than 3 slices (the empty mesh), M.Fused{}, M.AppleLibm{}, M.Glibc241Libm{}, a
nonfinite radius or height. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

import frame_probe as fp
import glibc_sin
import probekit
from conformance import gradient_reference
from probekit import ProbeFailure

SIZES = ((1.0, 2.0), (0.5, 1.25), (2.5, 0.75), (1.0, 1.0), (1.5, 1.5))
SLICES = (3, 4, 5, 8, 13, 16, 32, 40)
EDGES = ((0.0, 1.5), (1.0, 0.0), (0.0, 0.0), (-1.0, 2.0), (1.0, -2.0), (0.1, 30.0))
KNOTS = ((1.0, 2.0, 16, 128), (0.5, 1.0, 3, 3), (3.0, 1.0, 5, 7), (0.2, 1.5, 8, 16), (5.0, 0.5, 6, 9), (1.25, 0.0, 4, 6), (1.0, -1.0, 4, 12), (2.0, 3.5, 24, 40))
EMPTY = 'M0 0 811c9dc5 811c9dc5 811c9dc5'
NAN = 0x7fc00000


def bits(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def cases():
    out = []
    for cone in (False, True):
        name = 'cone' if cone else 'cylinder'
        for slices in SLICES:
            for radius, height in SIZES[:2] if slices > 16 else SIZES:
                out.append(dict(id=f'{name}-{slices}-{radius}-{height}', cone=cone, radius=bits(radius), height=bits(height), slices=slices, profile='host', contract=None))
        for radius, height in EDGES:
            out.append(dict(id=f'{name}-edge-{radius}-{height}', cone=cone, radius=bits(radius), height=bits(height), slices=6, profile='host', contract=None))
        for slices in (0, 1, 2):
            out.append(dict(id=f'{name}-empty-{slices}', cone=cone, radius=bits(1.0), height=bits(2.0), slices=slices, profile='host', contract=EMPTY))
        out.append(dict(id=f'{name}-fused', cone=cone, radius=bits(1.0), height=bits(2.0), slices=8, profile='fused', contract='null'))
        out.append(dict(id=f'{name}-apple', cone=cone, radius=bits(1.0), height=bits(2.0), slices=8, profile='AppleLibm', contract='null'))
        out.append(dict(id=f'{name}-glibc241', cone=cone, radius=bits(1.0), height=bits(2.0), slices=8, profile='Glibc241Libm', contract='null'))
        out.append(dict(id=f'{name}-infinite-radius', cone=cone, radius=0x7f800000, height=bits(2.0), slices=8, profile='host', contract='null'))
        out.append(dict(id=f'{name}-nan-height', cone=cone, radius=bits(1.0), height=NAN, slices=8, profile='host', contract='null'))
    for item in out:
        item['kind'] = 'cone' if item['cone'] else 'cylinder'
    for radius, size, rad_seg, sides in KNOTS:
        out.append(dict(id=f'knot-{rad_seg}x{sides}-{radius}-{size}', kind='knot', cone=False, radius=bits(radius), height=bits(size), slices=rad_seg, sides=sides, profile='host', contract=None))
    for rad_seg, sides in ((2, 8), (8, 2), (0, 0)):
        out.append(dict(id=f'knot-empty-{rad_seg}x{sides}', kind='knot', cone=False, radius=bits(1.0), height=bits(2.0), slices=rad_seg, sides=sides, profile='host', contract=EMPTY))
    for name, profile, radius in (('fused', 'fused', bits(1.0)), ('apple', 'AppleLibm', bits(1.0)), ('glibc241', 'Glibc241Libm', bits(1.0)), ('infinite-radius', 'host', 0x7f800000)):
        out.append(dict(id=f'knot-{name}', kind='knot', cone=False, radius=radius, height=bits(2.0), slices=6, sides=9, profile=profile, contract='null'))
    return out


C_PREFIX = r'''#include "raylib.h"
#include <stdio.h>
#include <string.h>
static float bf(unsigned b) { float v; memcpy(&v, &b, 4); return v; }
static unsigned hash(const float *values, int count)
{
    unsigned h = 2166136261u;
    for (int i = 0; (values != NULL) && (i < count); i++) { unsigned b; memcpy(&b, &values[i], 4); h = (h ^ b)*16777619u; }
    return h;
}
static void show(Mesh m)
{
    printf("M%d %d %08x %08x %08x\n", m.vertexCount, m.triangleCount, hash(m.vertices, m.vertexCount*3), hash(m.texcoords, m.vertexCount*2), hash(m.normals, m.vertexCount*3));
}
int main(void)
{
    SetTraceLogLevel(LOG_NONE);
    InitWindow(16, 16, "");
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M

def hex.digit(+d: U32) -> Char:
  Chr{Bool.pick(U32, (d < 10 : U32), (d + 48 : U32), (d + 87 : U32))}

def hex.word(+w: U32) -> String:
  SCon{hex.digit(((w >> 28n) .&. 15 : U32)), SCon{hex.digit(((w >> 24n) .&. 15 : U32)), SCon{hex.digit(((w >> 20n) .&. 15 : U32)), SCon{hex.digit(((w >> 16n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 12n) .&. 15 : U32)), SCon{hex.digit(((w >> 8n) .&. 15 : U32)), SCon{hex.digit(((w >> 4n) .&. 15 : U32)), SCon{hex.digit((w .&. 15 : U32)), SNil{}}}}}}}}}

def hash.go(values: +List<F32>, +h: U32) -> U32:
  match values:
    case Nil{}: h
    case Con{+v, rest}: hash.go(rest, ((h .^. F32.bits(v)) * 16777619 : U32))

def hash(values: Maybe<&2, +List<F32>>) -> String:
  match values:
    case None{}: hex.word(2166136261)
    case Some{+items}: hex.word(hash.go(items, 2166136261))

def float(+bits: U32) -> F32:
  U32{b} = bits
  F32{b}

def shown(mesh: Maybe<J.Mesh>) -> String:
  match mesh:
    case None{}: "null"
    case Some{J.Mesh{vertices, triangles, points, texcoords, _, normals, _, _, _, _}}: "M" ++ U32.show(vertices) ++ " " ++ U32.show(triangles) ++ " " ++ hash(points) ++ " " ++ hash(texcoords) ++ " " ++ hash(normals)

def main() -> IO(Unit):
  do IO<Unit>:
'''


def call(case, host):
    arithmetic = 'M.Fused{}' if case['profile'] == 'fused' else 'M.Uncontracted{}'
    libm = host if case['profile'] in ('host', 'fused') else case['profile']
    tail = f', {case["sides"]})' if case['kind'] == 'knot' else ')'
    return f'J.Mesh.gen_{case["kind"]}_for({arithmetic}, M.{libm}{{}}, float({case["radius"]}), float({case["height"]}), {case["slices"]}{tail}'


def native_call(case):
    if case['kind'] == 'knot':
        return f'GenMeshKnot(bf({case["radius"]}u), bf({case["height"]}u), {case["slices"]}, {case["sides"]})'
    return f'{"GenMeshCone" if case["cone"] else "GenMeshCylinder"}(bf({case["radius"]}u), bf({case["height"]}u), {case["slices"]})'


def render(host):
    def build(selected, gpu):
        return PROGRAM + ''.join(f'    IO.print(shown({call(case, host)}))\n' for _, case in selected)
    return build


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('mesh-tube', args, raylib_options=fp.OPTIONS)
    fused = fp.fused_instructions(probe.library)
    if any(fused.values()):
        raise ProbeFailure(f'mesh-tube: the uncontracted reference build contains fused multiply-adds: {fused}')
    host = gradient_reference()
    glibc_sin.objects(probe)
    native = host == 'Glibc239Libm' and glibc_sin.host_is_model(probe)
    items = cases()
    compared = [c for c in items if c['contract'] is None] if native else []
    rows = {}
    if compared:
        source = C_PREFIX + ''.join(f'    show({native_call(c)});\n' for c in compared) + '    return 0;\n}\n'
        output = [line.rstrip() for line in probe.native(source, 'reference').splitlines() if line[:1] == 'M']
        if len(output) != len(compared):
            raise ProbeFailure(f'mesh-tube: reference printed {len(output)} rows for {len(compared)} cases')
        rows = {c['id']: line for c, line in zip(compared, output)}
        first = rows['cylinder-8-1.0-2.0'].split()
        knot = rows['knot-16x128-1.0-2.0'].split()
        if first[0] != f'M{(8 * 8 * 2 + 2 * 8) * 3}' or first[1] != str(8 * 8 * 2 + 2 * 8) or knot[1] != str(16 * 128 * 2) or len(set(rows.values())) < len(rows) - 2:
            raise ProbeFailure('mesh-tube: the reference did not generate the meshes as expected')
    expected = [c['contract'] if c['contract'] is not None else rows.get(c['id'], 'null') for c in items]
    lanes = probe.candidates(render(host), list(enumerate(items)), batch=32, parse=lambda text, selected: [line.rstrip() for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda index: items[index]['id'])
    probe.finish(cases=len(items), compared=len(compared), contracts=len(items) - len(compared), libm=host, native_compared=native)


if __name__ == '__main__':
    main()
