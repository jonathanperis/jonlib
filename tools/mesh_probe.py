#!/usr/bin/env python3
"""Compare Jonlib's rmodels.c meshes with the pinned raylib.

GenMeshPoly, GenMeshPlane, GenMeshCube, GenMeshHeightmap, GenMeshCubicmap,
GenMeshTangents, GetMeshBoundingBox, the ExportMesh (OBJ) and
ExportMeshAsCode file bytes, GetRayCollisionMesh and GetModelBoundingBox:
every vertex, texcoord, normal, tangent, color and index word, each
bounding-box and collision result bit, and every exported byte (meshes above
3000 words of an attribute are compared through an FNV-1a hash of all their
words and the count).

The reference is the linked raylib with the host contraction and libm
profiles (conformance.contraction, conformance.gradient_reference);
--uncontracted-control links the raylib built with -ffp-contract=off (the
frame probes' build) for M.Uncontracted{}; --gnu-libm links the build whose
sinf/cosf are the Arm optimized-routines model (tools/models_probe.py) with
M.Uncontracted{} and M.Glibc239Libm{}, leaving out the fminf/fmaxf-based
bounding boxes (the host's). Contracts (Jonlib must answer null): GenMeshPoly
arguments outside the profile's verified sinf/cosf set or above 4096 sides,
GenMeshPlane resolutions of 0 (0/0 NaN of platform-defined sign),
GetMeshBoundingBox of a zero-count mesh with vertices, OBJ export of a mesh
without normals, ExportMeshAsCode of an empty array, and triangle indices
beyond the vertex count. CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import math
import random

from conformance import contraction, gradient_reference
import frame_probe as fp
import models_probe as mp
import probekit
from probekit import ProbeFailure

f32 = fp.f32
W = fp.word
DEG2RAD = fp.DEG2RAD
LIMIT = 3000

MESHES = {'poly': 1, 'plane': 2, 'cube': 3, 'heightmap': 4, 'cubicmap': 5, 'custom': 6, 'sphere': 7, 'hemisphere': 8, 'torus': 9}
ACTIONS = {'show': 0, 'tangents': 1, 'bbox': 2, 'obj': 3, 'code': 4, 'ray': 5, 'model': 6}


# -----------------------------------------------------------------------------
# Cases: (mesh spec, action, action words)

def rgba(width, height, seed, palette=None):
    rng = random.Random(seed)
    out = []
    for _ in range(width * height):
        if palette:
            out += list(rng.choice(palette))
        else:
            out += [rng.randrange(256) for _ in range(4)]
    return out


def poly_refused(sides, radius, libm):
    if sides < 3:
        return False
    if sides > 4096:
        return True
    step = f32(360.0 / sides)
    d, args = 0.0, []
    for _ in range(sides):
        nxt = f32(d + step)
        args += [f32(DEG2RAD * d), f32(DEG2RAD * nxt)]
        d = nxt
    return not all(fp.accepted(libm, a) for a in args)


def matrix(values):
    return [f32(v) for v in values]


IDENTITY = matrix([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])


def par_small(spec):
    """Fewer than 3 slices or stacks: raylib's empty mesh."""
    if spec[0] == 'torus':
        return spec[3] < 3 or spec[4] < 3
    return spec[2] < 3 or spec[3] < 3


def par_points(spec):
    slices, stacks = (spec[3], spec[4]) if spec[0] == 'torus' else (spec[3], spec[2])
    return (slices + 1)*(stacks + 1)


def par_state(out, gnu):
    """GenMeshSphere sets par_shapes' degenerate-triangle area to 0 for the rest of the process: each hemisphere
    case gets the state its native predecessors leave (cases run in order in one reference process)."""
    after = False
    for case in out:
        spec = case['mesh']
        if case['contract'] or spec[0] not in ('sphere', 'hemisphere'):
            continue
        if spec[0] == 'hemisphere':
            case['mesh'] = spec[:4] + (after,)
        elif not par_small(spec):
            after = True


def cases(libm, gnu):
    out = []

    def add(name, mesh, action='show', words=(), contract=False, fminf=False):
        if gnu and fminf:
            return
        out.append(dict(id=name, mesh=mesh, action=action, words=list(words), contract=contract))

    def par(name, mesh, action='show', words=()):
        # par_shapes generators are glibc-profile only (qsort order): refused under AppleLibm, whatever the build.
        refused = not par_small(mesh) and (libm == 'AppleLibm' or par_points(mesh) > 65535)
        add(name, mesh, action, words, contract=refused)

    # par_shapes meshes (glibc profile only): hemispheres first, before and after the first GenMeshSphere.
    for radius, rings, slices in ((1.0, 8, 8), (2.0, 3, 5), (-1.0, 6, 6), (1.0, 2, 9)):
        par(f'hemisphere-{rings}x{slices}-{radius}', ('hemisphere', f32(radius), rings, slices, False))
    for radius, rings, slices in ((1.0, 3, 3), (1.5, 4, 6), (2.0, 8, 8), (1.0, 16, 16), (0.75, 7, 13), (1.0, 32, 32), (1.0, 2, 8), (2.0, 64, 48),
                                  (1.0, 255, 255)):
        par(f'sphere-{rings}x{slices}-{radius}', ('sphere', f32(radius), rings, slices))
    for radius, rings, slices in ((1.0, 8, 8), (1.5, 16, 12), (0.5, 3, 24)):
        par(f'hemisphere-after-{rings}x{slices}-{radius}', ('hemisphere', f32(radius), rings, slices, False))
    for radius, size, rad_seg, sides in ((0.25, 2.0, 16, 8), (0.05, 1.0, 3, 3), (1.5, 3.0, 12, 24), (0.5, -2.0, 32, 16), (0.4, 1.0, 2, 8)):
        par(f'torus-{rad_seg}x{sides}-{radius}-{size}', ('torus', f32(radius), f32(size), rad_seg, sides))
    par('tangents-sphere', ('sphere', 1.0, 8, 8), 'tangents')
    par('tangents-torus', ('torus', f32(0.3), 2.0, 12, 6), 'tangents')
    par('obj-torus', ('torus', f32(0.25), 2.0, 6, 4), 'obj')
    par('code-hemisphere', ('hemisphere', 1.0, 4, 4, False), 'code')
    par('ray-sphere', ('sphere', 2.0, 12, 12), 'ray', [W(f32(v)) for v in (0.1, 0.2, 5.0, 0.0, 0.0, -1.0)] + [W(v) for v in IDENTITY])
    par('ray-torus', ('torus', f32(0.3), 4.0, 16, 8), 'ray', [W(f32(v)) for v in (1.5, 0.1, 5.0, 0.0, 0.0, -1.0)] + [W(v) for v in IDENTITY])
    if not gnu:
        add('bbox-sphere', ('sphere', 1.0, 6, 6), 'bbox', contract=(libm == 'AppleLibm'), fminf=True)

    for sides in (0, 2, 3, 4, 5, 6, 8, 9, 10, 12, 15, 18, 20, 24, 36, 7, 11, 100, 360, 5000):
        for radius in (1.0, f32(2.5), f32(-1.75)):
            mesh = ('poly', sides, f32(radius))
            add(f'poly-{sides}-{radius}', mesh, contract=poly_refused(sides, radius, libm))
    for w, l, rx, rz in ((2.0, 3.0, 1, 1), (5.0, 4.0, 3, 2), (1.5, -2.0, 7, 5), (3.0, 3.0, 20, 20), (f32(0.1), f32(7.3), 9, 4),
                         (4.0, 4.0, 255, 255), (4.0, 2.0, 300, 300)):
        add(f'plane-{rx}x{rz}', ('plane', f32(w), f32(l), rx, rz))
    add('plane-zero-res', ('plane', 2.0, 2.0, 0, 3), contract=True)
    for size in ((1.0, 1.0, 1.0), (2.0, 0.5, 3.0), (-1.0, 2.0, 0.0), (f32(1e30), f32(1e-30), 3.0)):
        add(f'cube-{size}', ('cube',) + tuple(f32(s) for s in size))
    maps = [(4, 3, 11), (1, 5, 12), (5, 1, 13), (16, 12, 14), (32, 32, 15), (2, 2, 16)]
    for w, h, seed in maps:
        for size in ((4.0, 2.0, 3.0), (f32(-2.0), f32(0.5), 10.0)):
            add(f'heightmap-{w}x{h}-{seed}-{size[0]}', ('heightmap', w, h) + tuple(f32(s) for s in size) + (rgba(w, h, seed),))
    palette = [(255, 255, 255, 255), (0, 0, 0, 255), (255, 0, 0, 255), (255, 255, 255, 254)]
    for w, h, seed in ((6, 5, 21), (8, 8, 22), (1, 1, 23), (3, 1, 24), (16, 16, 25)):
        add(f'cubicmap-{w}x{h}', ('cubicmap', w, h, f32(1.0), f32(2.0), f32(1.5), rgba(w, h, seed, palette)))
    add('cubicmap-white', ('cubicmap', 1, 1, f32(0.5), f32(1.0), f32(-2.0), [255, 255, 255, 255]))
    add('cubicmap-scaled', ('cubicmap', 4, 4, f32(2.5), f32(0.75), f32(3.0), rgba(4, 4, 26, palette[:2])))

    custom = ('custom', 4, 2, [f32(v) for v in (0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0)], [f32(v) for v in (0, 0, 1, 0, 1, 1, 0, 1)],
              [f32(v) for v in (0, 0, 1) * 4], [10, 20, 30, 255, 1, 2, 3, 4, 200, 150, 100, 50, 0, 0, 0, 0], [0, 1, 2, 0, 2, 3])
    bad = ('custom', 4, 2, custom[3], custom[4], custom[5], custom[6], [0, 1, 2, 0, 2, 7])
    # Tangents.
    for name, mesh in (('plane', ('plane', 2.0, 3.0, 2, 3)), ('cube', ('cube', 1.0, 2.0, 3.0)), ('poly', ('poly', 6, 1.0)),
                       ('heightmap', ('heightmap', 5, 4, 4.0, 2.0, 3.0, rgba(5, 4, 31))), ('cubicmap', ('cubicmap', 4, 3, 1.0, 1.0, 1.0, rgba(4, 3, 32, palette))),
                       ('custom', custom), ('big-heightmap', ('heightmap', 24, 20, 8.0, 3.0, 6.0, rgba(24, 20, 33)))):
        add(f'tangents-{name}', mesh, 'tangents', contract=(mesh[0] == 'poly' and poly_refused(6, 1.0, libm)))
    add('tangents-bad-index', bad, 'tangents', contract=True)
    # Bounding boxes.
    for name, mesh in (('plane', ('plane', 2.0, -3.0, 2, 3)), ('cube', ('cube', 1.0, 2.0, 3.0)), ('cube-zero', ('cube', 0.0, 2.0, 0.0)),
                       ('heightmap', ('heightmap', 6, 5, -4.0, 2.0, 3.0, rgba(6, 5, 41))), ('cubicmap', ('cubicmap', 5, 4, 1.0, 1.0, 1.0, rgba(5, 4, 42, palette))),
                       ('custom', custom), ('empty', ('poly', 2, 1.0))):
        add(f'bbox-{name}', mesh, 'bbox', fminf=True)
    add('bbox-zero-count', ('custom', 0, 0, [f32(1.0), f32(2.0), f32(3.0)][:0], [], [], [], []), 'bbox', contract=True, fminf=True)
    # OBJ and code export.
    for name, mesh in (('cube', ('cube', 1.0, 2.0, 3.0)), ('plane', ('plane', 2.0, 3.0, 2, 1)), ('heightmap', ('heightmap', 3, 3, 4.0, 2.0, 3.0, rgba(3, 3, 51))),
                       ('poly', ('poly', 4, f32(1.5))), ('custom', custom), ('cubicmap', ('cubicmap', 2, 2, 1.0, 1.0, 1.0, [255] * 16))):
        refusal = mesh[0] == 'poly' and poly_refused(4, 1.5, libm)
        add(f'obj-{name}', mesh, 'obj', contract=refusal)
        add(f'code-{name}', mesh, 'code', contract=refusal)
    add('obj-no-normals', ('custom', 3, 1, [f32(v) for v in (0, 0, 0, 1, 0, 0, 0, 1, 0)], [0.0] * 6, None, None, None), 'obj', contract=True)
    add('code-empty', ('custom', 0, 0, [], None, None, None, None), 'code', contract=True)
    add('code-tangents', ('cube', 2.0, 1.0, 1.0), 'code', [1])
    # Ray collisions.
    rays = [((0.0, 0.0, 5.0), (0.0, 0.0, -1.0)), ((0.2, 0.3, -5.0), (0.0, 0.0, 1.0)), ((3.0, 3.0, 3.0), (-0.577, -0.577, -0.577)),
            ((5.0, 0.1, 0.2), (-1.0, 0.0, 0.0)), ((0.0, 5.0, 0.0), (0.1, -1.0, 0.05)), ((10.0, 10.0, 10.0), (1.0, 0.0, 0.0))]
    transforms = [IDENTITY, matrix([1, 0, 0, 0.5, 0, 1, 0, -0.25, 0, 0, 1, 0.75, 0, 0, 0, 1]),
                  matrix([0.8, -0.6, 0, 0, 0.6, 0.8, 0, 0.1, 0, 0, 1.5, 0, 0, 0, 0, 1])]
    meshes = (('cube', ('cube', 2.0, 2.0, 2.0)), ('plane', ('plane', 4.0, 4.0, 3, 3)), ('poly', ('poly', 8, 2.0)),
              ('heightmap', ('heightmap', 6, 6, 4.0, 1.0, 4.0, rgba(6, 6, 61))), ('custom', custom))
    for mname, mesh in meshes:
        for ri, (position, direction) in enumerate(rays):
            for ti, transform in enumerate(transforms):
                words = [W(f32(v)) for v in position + direction] + [W(v) for v in transform]
                add(f'ray-{mname}-{ri}-{ti}', mesh, 'ray', words, contract=(mesh[0] == 'poly' and poly_refused(8, 2.0, libm)))
    add('ray-bad-index', bad, 'ray', [W(f32(v)) for v in (0, 0, 5, 0, 0, -1)] + [W(v) for v in IDENTITY], contract=True)
    # Model bounding boxes.
    for ti, transform in enumerate(transforms):
        add(f'model-{ti}', ('cube', 1.0, 2.0, 3.0), 'model', [W(v) for v in transform], fminf=True)
    par_state(out, gnu)
    return out


# -----------------------------------------------------------------------------
# C reference

C_PREFIX = r'''#include "raylib.h"
#include "raymath.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static float bf(unsigned u) { float f; memcpy(&f, &u, 4); return f; }
static unsigned fb(float f) { unsigned u; memcpy(&u, &f, 4); return u; }
static void words(const char *tag, const unsigned *w, int n, int present)
{
    if (!present) { printf(" %s-", tag); return; }
    if (n > ''' + str(LIMIT) + r''')
    {
        unsigned h = 2166136261u;
        for (int i = 0; i < n; i++) { h ^= w[i]; h *= 16777619u; }
        printf(" %sh%u,%d", tag, h, n);
        return;
    }
    printf(" %s", tag);
    for (int i = 0; i < n; i++) printf("%08x", w[i]);
}
static void floats(const char *tag, const float *f, int n)
{
    unsigned *w = malloc((n > 0 ? n : 1)*sizeof(unsigned));
    for (int i = 0; i < n && f; i++) w[i] = fb(f[i]);
    words(tag, w, n, f != NULL);
    free(w);
}
static void shorts(const char *tag, const unsigned short *s, int n)
{
    unsigned *w = malloc((n > 0 ? n : 1)*sizeof(unsigned));
    for (int i = 0; i < n && s; i++) w[i] = s[i];
    words(tag, w, n, s != NULL);
    free(w);
}
static void bytes(const char *tag, const unsigned char *s, int n)
{
    unsigned *w = malloc((n > 0 ? n : 1)*sizeof(unsigned));
    for (int i = 0; i < n && s; i++) w[i] = s[i];
    words(tag, w, n, s != NULL);
    free(w);
}
static void show(Mesh m)
{
    printf("M %d %d", m.vertexCount, m.triangleCount);
    floats("V", m.vertices, m.vertexCount*3); floats("T", m.texcoords, m.vertexCount*2); floats("U", m.texcoords2, m.vertexCount*2);
    floats("N", m.normals, m.vertexCount*3); floats("G", m.tangents, m.vertexCount*4); bytes("C", m.colors, m.vertexCount*4);
    shorts("I", m.indices, m.triangleCount*3);
    printf("\n");
}
static void box(BoundingBox b)
{
    printf("B %08x%08x%08x%08x%08x%08x\n", fb(b.min.x), fb(b.min.y), fb(b.min.z), fb(b.max.x), fb(b.max.y), fb(b.max.z));
}
static void file(const char *path, bool ok)
{
    if (!ok) { printf("X false\n"); return; }
    int size = 0;
    unsigned char *data = LoadFileData(path, &size);
    unsigned *w = malloc((size > 0 ? size : 1)*sizeof(unsigned));
    for (int i = 0; i < size; i++) w[i] = data[i];
    printf("X %d", size);
    words("", w, size, 1);
    printf("\n");
    free(w);
    UnloadFileData(data);
}
static Image image(int w, int h, const unsigned char *data)
{
    Image im = { 0 };
    im.data = malloc(w*h*4); memcpy(im.data, data, w*h*4);
    im.width = w; im.height = h; im.mipmaps = 1; im.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
    return im;
}
static float *fcopy(const float *values, int n) { if (!values) return NULL; float *p = malloc((n > 0 ? n : 1)*sizeof(float)); memcpy(p, values, n*sizeof(float)); return p; }
int main(void)
{
    SetTraceLogLevel(LOG_NONE);
'''


def cfloats(values):
    return '(const float[]){' + ','.join(f'bf({W(v)}u)' for v in values) + ', 0}' if values else '(const float[]){0}'


def c_mesh(spec, name='m'):
    kind = spec[0]
    if kind == 'poly':
        return f'Mesh {name} = GenMeshPoly({spec[1]}, bf({W(spec[2])}u));'
    if kind == 'sphere':
        return f'Mesh {name} = GenMeshSphere(bf({W(spec[1])}u), {spec[2]}, {spec[3]});'
    if kind == 'hemisphere':
        return f'Mesh {name} = GenMeshHemiSphere(bf({W(spec[1])}u), {spec[2]}, {spec[3]});'
    if kind == 'torus':
        return f'Mesh {name} = GenMeshTorus(bf({W(spec[1])}u), bf({W(spec[2])}u), {spec[3]}, {spec[4]});'
    if kind == 'plane':
        return f'Mesh {name} = GenMeshPlane(bf({W(spec[1])}u), bf({W(spec[2])}u), {spec[3]}, {spec[4]});'
    if kind == 'cube':
        return f'Mesh {name} = GenMeshCube(bf({W(spec[1])}u), bf({W(spec[2])}u), bf({W(spec[3])}u));'
    if kind in ('heightmap', 'cubicmap'):
        w, h = spec[1], spec[2]
        data = '(const unsigned char[]){' + ','.join(map(str, spec[6])) + '}'
        call = 'GenMeshHeightmap' if kind == 'heightmap' else 'GenMeshCubicmap'
        size = f'(Vector3){{ bf({W(spec[3])}u), bf({W(spec[4])}u), bf({W(spec[5])}u) }}'
        return f'Image {name}_im = image({w}, {h}, {data}); Mesh {name} = {call}({name}_im, {size}); UnloadImage({name}_im);'
    vc, tc, vertices, texcoords, normals, colors, indices = spec[1:]
    parts = [f'Mesh {name} = {{ 0 }}; {name}.vertexCount = {vc}; {name}.triangleCount = {tc};']
    if vertices is not None:
        parts.append(f'{name}.vertices = fcopy({cfloats(vertices)}, {len(vertices)});')
    if texcoords is not None:
        parts.append(f'{name}.texcoords = fcopy({cfloats(texcoords)}, {len(texcoords)});')
    if normals is not None:
        parts.append(f'{name}.normals = fcopy({cfloats(normals)}, {len(normals)});')
    if colors is not None:
        parts.append(f'{name}.colors = malloc({max(len(colors), 1)}); memcpy({name}.colors, (const unsigned char[]){{{",".join(map(str, colors + [0]))}}}, {len(colors)});')
    if indices is not None:
        parts.append(f'{name}.indices = malloc({max(len(indices), 1)}*2); memcpy({name}.indices, (const unsigned short[]){{{",".join(map(str, indices + [0]))}}}, {len(indices)}*2);')
    return ' '.join(parts)


def c_matrix(words):
    v = [f'bf({w}u)' for w in words]
    return f'(Matrix){{ {", ".join(v)} }}'


def c_case(case, work):
    action, words = case['action'], case['words']
    lines = ['    {', '    ' + c_mesh(case['mesh'])]
    if action == 'show':
        lines.append('    show(m);')
    elif action == 'tangents':
        lines.append('    GenMeshTangents(&m); show(m);')
    elif action == 'bbox':
        lines.append('    box(GetMeshBoundingBox(m));')
    elif action == 'obj':
        path = work / f'{case["id"]}.obj'
        lines.append(f'    file("{path}", ExportMesh(m, "{path}"));')
    elif action == 'code':
        path = work / f'{case["id"]}_mesh.h'
        if words:
            lines.append('    GenMeshTangents(&m);')
        lines.append(f'    file("{path}", ExportMeshAsCode(m, "{path}"));')
    elif action == 'ray':
        ray = f'(Ray){{ (Vector3){{ bf({words[0]}u), bf({words[1]}u), bf({words[2]}u) }}, (Vector3){{ bf({words[3]}u), bf({words[4]}u), bf({words[5]}u) }} }}'
        lines.append(f'    RayCollision c = GetRayCollisionMesh({ray}, m, {c_matrix(words[6:])});')
        lines.append('    printf("R %d %08x%08x%08x%08x%08x%08x%08x\\n", (int)c.hit, fb(c.distance), fb(c.point.x), fb(c.point.y), fb(c.point.z), '
                     'fb(c.normal.x), fb(c.normal.y), fb(c.normal.z));')
    elif action == 'model':
        lines.append('    ' + c_mesh(('plane', 2.0, f32(-3.0), 2, 2), 'p'))
        lines.append(f'    Model model = {{ 0 }}; model.transform = {c_matrix(words)}; model.meshCount = 2; model.meshes = (Mesh[]){{ m, p }};')
        lines.append('    box(GetModelBoundingBox(model)); UnloadMesh(p);')
    lines.append('    UnloadMesh(m); }')
    return '\n'.join(lines)


# -----------------------------------------------------------------------------
# Bend candidate

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/frame.bend as FC

PROFILES

def hex.digit(+d: U32) -> Char:
  Chr{Bool.pick(U32, (d < 10 : U32), (d + 48 : U32), (d + 87 : U32))}

def hex.word(+w: U32, rest: String) -> String:
  SCon{hex.digit((w >> 28n : U32)), SCon{hex.digit(((w >> 24n) .&. 15 : U32)), SCon{hex.digit(((w >> 20n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 16n) .&. 15 : U32)), SCon{hex.digit(((w >> 12n) .&. 15 : U32)), SCon{hex.digit(((w >> 8n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 4n) .&. 15 : U32)), SCon{hex.digit((w .&. 15 : U32)), rest}}}}}}}}

def count(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def fnv(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: fnv(rest, ((h .^. x) * 16777619 : U32))

# Helpers are tail-recursive: the JavaScript lane's stack holds about 20000
# frames, less than a large mesh's attribute count.
def hexes.go(reversed: +List<U32>, acc: String) -> String:
  match reversed:
    case Nil{}: acc
    case Con{+x, rest}: hexes.go(rest, hex.word(x, acc))

def hexes(+xs: +List<U32>) -> String:
  hexes.go(List.reverse(&2, U32, xs), "")

def words.text(+tag: String, +xs: +List<U32>) -> String:
  +n = count(xs, 0)
  Bool.pick(String, (n > LIMIT : U32), " " ++ tag ++ "h" ++ U32.show(fnv(xs, 2166136261)) ++ "," ++ U32.show(n), " " ++ tag ++ hexes(xs))

def bits.go(xs: +List<F32>, acc: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+x, rest}: bits.go(rest, Con{F32.bits(x), acc})

def bits(+xs: +List<F32>) -> +List<U32>:
  bits.go(xs, Nil{})

def attr.f(+tag: String, values: Maybe<&2, +List<F32>>) -> String:
  match values:
    case None{}: " " ++ tag ++ "-"
    case Some{+xs}: words.text(tag, bits(xs))

def attr.u(+tag: String, values: Maybe<&2, +List<U32>>) -> String:
  match values:
    case None{}: " " ++ tag ++ "-"
    case Some{+xs}: words.text(tag, xs)

def show(mesh: J.Mesh) -> String:
  J.Mesh{vc, tc, vertices, texcoords, texcoords2, normals, tangents, colors, indices} = mesh
  "M " ++ U32.show(vc) ++ " " ++ U32.show(tc) ++ attr.f("V", vertices) ++ attr.f("T", texcoords) ++ attr.f("U", texcoords2)
    ++ attr.f("N", normals) ++ attr.f("G", tangents) ++ attr.u("C", colors) ++ attr.u("I", indices)

def show.maybe(mesh: Maybe<J.Mesh>) -> String:
  match mesh:
    case None{}: "null"
    case Some{m}: show(m)

def v3.hex(v: M.Vector3, rest: String) -> String:
  M.Vector3{x, y, z} = v
  hex.word(F32.bits(x), hex.word(F32.bits(y), hex.word(F32.bits(z), rest)))

def box.text(b: Maybe<J.BoundingBox>) -> String:
  match b:
    case None{}: "null"
    case Some{J.BoundingBox{low, high}}: "B " ++ v3.hex(low, v3.hex(high, ""))

def chars.go(s: String, acc: +List<U32>) -> +List<U32>:
  match s:
    case SNil{}: List.reverse(&2, U32, acc)
    case SCon{+c, rest}: chars.go(rest, Con{Char.to_u32(c), acc})

def chars(s: String) -> +List<U32>:
  chars.go(s, Nil{})

def file.text(t: Maybe<String>) -> String:
  match t:
    case None{}: "null"
    case Some{s}:
      +cs = chars(s)
      "X " ++ U32.show(count(cs, 0)) ++ words.text("", cs)

def ray.text(r: Maybe<J.RayCollision>) -> String:
  match r:
    case None{}: "null"
    case Some{J.RayCollision{hit, distance, point, normal}}:
      "R " ++ Bool.pick(String, hit, "1", "0") ++ " " ++ hex.word(F32.bits(distance), v3.hex(point, v3.hex(normal, "")))

type Case is Data:
  Case{mesh: U32, mw: +List<U32>, floats: +List<F32>, bytes: +List<U32>, action: U32, aw: +List<U32>}

def word.at(n: Nat, ws: +List<U32>) -> U32:
  match n ws:
    case 0n Con{w, _}: w
    case _ Nil{}: 0
    case 1n+k Con{_, rest}: word.at(k, rest)

def word.drop(n: Nat, ws: +List<U32>) -> +List<U32>:
  match n ws:
    case 0n _: ws
    case _ Nil{}: Nil{}
    case 1n+k Con{_, rest}: word.drop(k, rest)

def wf(n: Nat, +ws: +List<U32>) -> F32:
  FC.float(word.at(n, ws))

def wu(n: Nat, +ws: +List<U32>) -> U32:
  word.at(n, ws)

def wv3(n: Nat, +ws: +List<U32>) -> M.Vector3:
  +rest = word.drop(n, ws)
  M.Vector3{wf(0n, rest), wf(1n, rest), wf(2n, rest)}

def wmatrix(+r: +List<U32>) -> M.Matrix:
  M.Matrix{wf(0n, r), wf(1n, r), wf(2n, r), wf(3n, r), wf(4n, r), wf(5n, r), wf(6n, r), wf(7n, r), wf(8n, r), wf(9n, r), wf(10n, r), wf(11n, r),
    wf(12n, r), wf(13n, r), wf(14n, r), wf(15n, r)}

def take.f(n: Nat, +xs: +List<F32>) -> +List<F32>:
  List.take(&2, F32, xs, n)

def take.u(n: Nat, +xs: +List<U32>) -> +List<U32>:
  List.take(&2, U32, xs, n)

def opt.f(present: U32, +n: Nat, +xs: +List<F32>) -> Maybe<&2, +List<F32>>:
  match present:
    case 0: None{}
    case _: Some{take.f(n, xs)}

def opt.u(present: U32, +n: Nat, +xs: +List<U32>) -> Maybe<&2, +List<U32>>:
  match present:
    case 0: None{}
    case _: Some{take.u(n, xs)}

def result.mesh(r: Result<&1, &1, J.Surface & J.Surface.Error, J.Mesh>) -> Maybe<J.Mesh>:
  match r:
    case Fail{_}: None{}
    case Done{m}: Some{m}

def map.gen(heights: Bool, +w: +List<U32>, s: J.Surface) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Mesh>:
  match heights:
    case True{}: J.Mesh.gen_heightmap_for(arith(), s, wv3(2n, w))
    case False{}: J.Mesh.gen_cubicmap(s, wv3(2n, w))

def map.mesh(+kind: U32, +w: +List<U32>, surface: Maybe<J.Surface>) -> Maybe<J.Mesh>:
  match surface:
    case None{}: None{}
    case Some{s}: result.mesh(map.gen(U32.is_eq(kind, 4), w, s))

# custom: words vc, tc, then (present, count) for vertices, texcoords, normals, colors, indices; floats and bytes hold the data.
def custom(+w: +List<U32>, +fs: +List<F32>, +bs: +List<U32>) -> J.Mesh:
  +nv = wu(3n, w)
  +nt = wu(5n, w)
  +nn = wu(7n, w)
  +nc = wu(9n, w)
  J.Mesh{wu(0n, w), wu(1n, w), opt.f(wu(2n, w), U32.to_nat(nv), fs), opt.f(wu(4n, w), U32.to_nat(nt), List.drop(&2, F32, fs, U32.to_nat(nv))), None{},
    opt.f(wu(6n, w), U32.to_nat(nn), List.drop(&2, F32, fs, U32.to_nat((nv + nt : U32)))), None{},
    opt.u(wu(8n, w), U32.to_nat(nc), bs), opt.u(wu(10n, w), U32.to_nat(wu(11n, w)), List.drop(&2, U32, bs, U32.to_nat(nc)))}

def mesh.of(kind: U32, +w: +List<U32>, +fs: +List<F32>, +bs: +List<U32>) -> Maybe<J.Mesh>:
  match kind:
    case 1: J.Mesh.gen_poly_for(libm(), wu(0n, w), wf(1n, w))
    case 2: J.Mesh.gen_plane(wf(0n, w), wf(1n, w), wu(2n, w), wu(3n, w))
    case 3: Some{J.Mesh.gen_cube(wf(0n, w), wf(1n, w), wf(2n, w))}
    case 6: Some{custom(w, fs, bs)}
    case 7: J.Mesh.gen_sphere_for(arith(), libm(), wf(0n, w), wu(1n, w), wu(2n, w))
    case 8: J.Mesh.gen_hemi_sphere_for(arith(), libm(), Bool.not(U32.is_eq(wu(3n, w), 0)), wf(0n, w), wu(1n, w), wu(2n, w))
    case 9: J.Mesh.gen_torus_for(arith(), libm(), wf(0n, w), wf(1n, w), wu(2n, w), wu(3n, w))
    case _: map.mesh(kind, w, J.Surface.from_bytes(wu(0n, w), wu(1n, w), 7, bs))

def code.tangents(m: Maybe<J.Mesh>, +path: String) -> Maybe<String>:
  match m:
    case None{}: None{}
    case Some{+mesh}: J.Mesh.code_text(mesh, path)

def code.of(+tangents: Bool, +mesh: J.Mesh, +path: String) -> Maybe<String>:
  Bool.pick(Maybe<String>, tangents, code.tangents(J.Mesh.gen_tangents_for(arith(), mesh), path), J.Mesh.code_text(mesh, path))

def model.plane.of(m: Maybe<J.Mesh>) -> J.Mesh:
  match m:
    case None{}: J.Mesh.empty()
    case Some{+mesh}: mesh

def model.plane() -> J.Mesh:
  model.plane.of(J.Mesh.gen_plane(2.0, F32.neg(3.0), 2, 2))

def act(action: U32, +aw: +List<U32>, +path: String, +mesh: J.Mesh) -> String:
  match action:
    case 0: show(mesh)
    case 1: show.maybe(J.Mesh.gen_tangents_for(arith(), mesh))
    case 2: box.text(J.Mesh.bounding_box_for(libm(), mesh))
    case 3: file.text(J.Mesh.obj_text(mesh))
    case 4: file.text(code.of(U32.is_eq(wu(0n, aw), 1), mesh, path))
    case 5: ray.text(J.Collision.ray_mesh_for(arith(), J.Ray{wv3(0n, aw), wv3(3n, aw)}, mesh, wmatrix(word.drop(6n, aw))))
    case _: box.text(J.Model.bounding_box_for(arith(), libm(), J.Model{wmatrix(aw), [mesh, model.plane()]}))

def run.with(+action: U32, +aw: +List<U32>, +path: String, m: Maybe<J.Mesh>) -> String:
  match m:
    case None{}: "null"
    case Some{+mesh}: act(action, aw, path, mesh)

def run(c: Case, +path: String) -> String:
  Case{+kind, +mw, +fs, +bs, +action, +aw} = c
  run.with(action, aw, path, mesh.of(kind, mw, fs, bs))

def Case.with_bytes(c: Case, +bytes: +List<U32>) -> Case:
  Case{kind, mw, fs, _, action, aw} = c
  Case{kind, mw, fs, bytes, action, aw}

# Image bytes are read from a file (large list literals exhaust the compiler).
def run.loaded(c: Case, +path: String, r: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match r:
    case Fail{_}: IO.print("load failed")
    case Done{+bytes}: IO.print(run(Case.with_bytes(c, bytes), path))
'''


def b_case(case, work):
    spec = case['mesh']
    kind = MESHES[spec[0]]
    floats, data = [], []
    if spec[0] == 'poly':
        mw = [spec[1], W(spec[2])]
    elif spec[0] == 'sphere':
        mw = [W(spec[1]), spec[2], spec[3]]
    elif spec[0] == 'hemisphere':
        mw = [W(spec[1]), spec[2], spec[3], int(spec[4])]
    elif spec[0] == 'torus':
        mw = [W(spec[1]), W(spec[2]), spec[3], spec[4]]
    elif spec[0] == 'plane':
        mw = [W(spec[1]), W(spec[2]), spec[3], spec[4]]
    elif spec[0] == 'cube':
        mw = [W(v) for v in spec[1:4]]
    elif spec[0] in ('heightmap', 'cubicmap'):
        mw = [spec[1], spec[2]] + [W(v) for v in spec[3:6]]
    else:
        vc, tc, vertices, texcoords, normals, colors, indices = spec[1:]
        mw = [vc, tc]
        for values in (vertices, texcoords, normals):
            mw += [int(values is not None), len(values or [])]
            floats += values or []
        mw += [int(colors is not None), len(colors or []), int(indices is not None), len(indices or [])]
        data = (colors or []) + (indices or [])
    path = work / (f'{case["id"]}_mesh.h' if case['action'] == 'code' else f'{case["id"]}.obj')
    fl = '[' + ', '.join(fp.bf(v) for v in floats) + ']'
    return (f'Case{{{kind}, [{", ".join(map(str, mw))}], {fl}, [{", ".join(map(str, data))}], {ACTIONS[case["action"]]}, '
            f'[{", ".join(map(str, case["words"]))}]}}'), str(path)


def render(arith, libm, work):
    inputs = work.parent / 'inputs'
    inputs.mkdir(parents=True, exist_ok=True)

    def build(selected, gpu):
        profiles = f'def libm() -> M.Libm:\n  M.{libm}{{}}\n\ndef arith() -> M.Contraction:\n  M.{arith}{{}}\n'
        body = [PROGRAM.replace('LIMIT', str(LIMIT)).replace('PROFILES', profiles)]
        prints = []
        for index, case in selected:
            text, path = b_case(case, work)
            body.append(f'def case.{index}() -> Case:\n  {text}')
            if case['mesh'][0] in ('heightmap', 'cubicmap'):
                data = inputs / f'{index}.bin'
                data.write_bytes(bytes(case['mesh'][6]))
                prints.append(f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data("{data}"), '
                              f'r => run.loaded(case.{index}(), "{path}", r))')
            else:
                prints.append(f'    IO.print(run(case.{index}(), "{path}"))')
        body.append('def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(prints) + '\n    return Unit{}\n')
        return '\n\n'.join(body)
    return build


def configure(parser):
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--uncontracted-control', action='store_true', help='link the raylib built with -ffp-contract=off (M.Uncontracted{})')
    modes.add_argument('--gnu-libm', action='store_true', help='link the Arm sinf/cosf model build (M.Uncontracted{}, M.Glibc239Libm{})')


def main():
    args = probekit.arguments(__doc__, configure)
    extra = ()
    if args.gnu_libm:
        source, header = mp.gnu_model()
        options, name, arith, libm = (f'CMAKE_C_FLAGS=-ffp-contract=off -include {header}',), 'mesh-gnu', 'Uncontracted', 'Glibc239Libm'
    elif args.uncontracted_control:
        options, name, arith, libm = fp.OPTIONS, 'mesh-uncontracted', 'Uncontracted', gradient_reference()
    else:
        options, name, arith, libm = (), 'mesh', contraction(), gradient_reference()
    probe = probekit.Probe(name, args, raylib_options=options)
    if args.gnu_libm:
        model_object = mp.GNU_DIR / 'glibc_model.o'
        probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-c', source, '-o', model_object])
        extra = (str(model_object),)
    if options:
        fused = fp.fused_instructions(probe.library)
        if any(fused.values()):
            raise ProbeFailure(f'{name}: the uncontracted reference build contains fused multiply-adds: {fused}')
    work = probe.work / 'files'
    work.mkdir(parents=True, exist_ok=True)
    items = cases(libm, args.gnu_libm)
    native = [c for c in items if not c['contract']]
    contracts = [c for c in items if c['contract']]
    if len(native) < 100 or len(contracts) < 6:
        raise ProbeFailure(f'{name}: {len(native)} compared and {len(contracts)} refused cases; the corpus lost coverage')
    source_text = C_PREFIX + '\n'.join(c_case(c, work) for c in native) + '\n    return 0;\n}\n'
    output = probe.native(source_text, 'reference', extra_flags=extra).splitlines()
    if len(output) != len(native):
        raise ProbeFailure(f'{name}: reference printed {len(output)} lines for {len(native)} cases')
    expected_by_id = {c['id']: line.rstrip() for c, line in zip(native, output)}
    for c in contracts:
        expected_by_id[c['id']] = 'null'
    expected = [expected_by_id[c['id']] for c in items]
    actions = list(enumerate(items))
    lanes = probe.candidates(render(arith, libm, work), actions, batch=24,
                            parse=lambda text, selected: [line.rstrip() for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda i: f'case {items[i]["id"]}')
    probe.finish(cases=len(items), compared=len(native), contracts=len(contracts), profile=arith, libm=libm,
                 reference={'mesh': 'linked raylib', 'mesh-uncontracted': 'raylib built with -ffp-contract=off',
                            'mesh-gnu': 'Arm sinf/cosf model build'}[name],
                 cases_sha256=hashlib.sha256(repr(items).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256('\n'.join(output).encode()).hexdigest())


if __name__ == '__main__':
    main()
