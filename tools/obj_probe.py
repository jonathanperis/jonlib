#!/usr/bin/env python3
"""Compare Jonlib's LoadModel (OBJ through tinyobj_loader_c) and LoadMaterials
with the pinned raylib.

The probe writes OBJ, MTL and PNG files under its work directory and loads
each one natively (InitWindow on PLATFORM=Memory, then LoadModel or
LoadMaterials) and with Jonlib (Model.load_for, Material.load_materials_for).
Each row has the mesh and material counts, IsModelValid, every mesh's vertex
and triangle counts, mesh material and every vertex, normal and texcoord
word, and every material map (texture id and fields, color, value bits).

The files cover: v/vn/vt with tinyobj's tryParseDouble (signs, fractions,
exponents, failed parses that leave 0, values whose binary64 fraction sum
rounds differently fused and unfused), every face form (i, i/j, i//k,
i/j/k, negative relative indices), triangulated quads and pentagons, faces
of fewer than 3 vertices, usemtl changes (unknown names, -1 to a material,
trailing spaces, empty names), 'o'/'g' shapes and the mesh splits rmodels.c
derives from their face offsets, LF, CRLF and lone CR line endings, a last
line without its terminator (tinyobj drops the text's last byte when there is
no terminator at all), NUL bytes (strlen), MTL files with colors, Ns,
textures that load, do not exist or have empty names, absolute texture
paths, properties before the first newmtl, a last line without '\\n'
(dynamic_fgets never returns it), duplicate names, 24 materials (the name
table grows twice), missing MTL files, empty and missing OBJ files and other
extensions.

The default run links the raylib built with the host contraction
(conformance.contraction: the fused fraction digits of tryParseDouble);
--uncontracted-control links the -ffp-contract=off build with
M.Uncontracted{}. Contracts (Jonlib must answer null): faces of 6 vertices
(tinyobj's assert), int overflow in an index or exponent, lines of 4095
bytes, 'g', 'o' and 'mtllib' with nothing after their space, vertex and
normal indices outside the arrays, Kd beyond the unsigned char cast, a
newmtl without a name, a CR CR line underflow, an OBJ whose first byte is
NUL (LoadOBJ returns without restoring the working directory), and IQM,
glTF, VOX and M3D files (not reproduced). CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import random
import struct
import zlib
from fractions import Fraction

from conformance import contraction
import frame_probe as fp
import probekit
from probekit import ProbeFailure


# -----------------------------------------------------------------------------
# tinyobj's tryParseDouble in Python (to show the contraction profile matters)

def f32(x):
    return struct.unpack('<f', struct.pack('<f', x))[0]


def try_parse(token, fused):
    """tryParseDouble over a token; the double, or 0.0 when the parse fails."""
    i, n = 0, len(token)
    if n == 0:
        return 0.0
    sign = 1.0
    if token[0] in '+-':
        sign = -1.0 if token[0] == '-' else 1.0
        i = 1
    elif not token[0].isdigit():
        return 0.0
    mantissa, read = 0.0, 0
    while i < n and token[i].isdigit():
        mantissa = mantissa * 10.0
        mantissa = mantissa + int(token[i])
        i += 1
        read += 1
    if read == 0:
        return 0.0
    exponent, minus = 0, False
    if i < n:
        if token[i] == '.':
            i += 1
            frac = 1.0
            while i < n and token[i].isdigit():
                frac = frac * 0.1
                d = int(token[i])
                if fused:
                    mantissa = float(Fraction(mantissa) + Fraction(d) * Fraction(frac))
                else:
                    mantissa = mantissa + d * frac
                i += 1
        if i < n and token[i] in 'eE':
            i += 1
            if i < n and token[i] in '+-':
                minus = token[i] == '-'
                i += 1
            elif not (i < n and token[i].isdigit()):
                return 0.0
            read = 0
            while i < n and token[i].isdigit():
                exponent = exponent * 10 + int(token[i])
                i += 1
                read += 1
            if read == 0:
                return 0.0
    a = b = 1.0
    for _ in range(exponent):
        a *= 5.0
    for _ in range(exponent):
        b *= 2.0
    if minus:
        a, b = 1.0 / a, 1.0 / b
    return sign * (mantissa * a * b)


def literal_differs(token):
    return struct.pack('<f', f32(try_parse(token, True))) != struct.pack('<f', f32(try_parse(token, False)))


def table_holds(names):
    """Whether tinyobj's hash table inserts every name (quadratic probing from djb2 % capacity, growth to
    2*max(capacity, n + 1)); a failed insertion makes the reference loop forever."""
    def djb2(name):
        h = 5381
        for c in name.encode():
            h = (h * 33 + c) & 0xFFFFFFFFFFFFFFFF
        return h

    def insert(slots, cap, h):
        start = index = h % cap
        i = 1
        while index in slots:
            if i >= cap:
                return None
            index = (start + i * i) % cap
            i += 1
        slots.add(index)
        return index

    cap, order, slots = 10, [], set()
    for h in map(djb2, names):
        if h in order:
            continue
        if len(order) + 1 > cap:
            cap = 2 * (cap if 2 * cap > len(order) + 1 else len(order) + 1)
            slots = set()
            if any(insert(slots, cap, old) is None for old in order):
                return False
        if insert(slots, cap, h) is None:
            return False
        order.append(h)
    return True


# -----------------------------------------------------------------------------
# Files

def png(width, height, seed):
    rng = random.Random(seed)
    rows = b''.join(b'\x00' + bytes(rng.randrange(256) for _ in range(width * 4)) for _ in range(height))

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


CUBE = '''v -1.0 -1.0 1.0
v 1.0 -1.0 1.0
v 1.0 1.0 1.0
v -1.0 1.0 1.0
v -1.0 -1.0 -1.0
v 1.0 -1.0 -1.0
v 1.0 1.0 -1.0
v -1.0 1.0 -1.0
vt 0.0 0.0
vt 1.0 0.0
vt 1.0 1.0
vt 0.0 1.0
vn 0.0 0.0 1.0
vn 0.0 0.0 -1.0
vn 0.0 1.0 0.0
vn 0.0 -1.0 0.0
vn 1.0 0.0 0.0
vn -1.0 0.0 0.0
'''


def number_literals(rng, count):
    """Literals as exporters write them, a few deliberately odd, at least a few rounding differently fused."""
    out = ['0.5', '-0.25', '+1.5', '1e2', '1.5E-3', '-2.5e+1', '7', '-0', '0.000001', '123456.789', '3.14159265358979',
           '0.1', '0.7', '1e-7', '.5', '5.', '1e', '1e+', 'x', '-', '2.5e-45', '1.000000059604644775390625', '16777217', '9.99999999e3',
           # Decimal expansions near binary32 midpoints whose fused and unfused parses round to different floats.
           '0.6904512941837310', '1.7004403471946716', '1.9417406916618347', '0.046221816912293434', '1.9783908724784851', '1.9505167603492736']
    while len(out) < count:
        kind = rng.randrange(4)
        if kind == 0:
            out.append(f'{rng.uniform(-100, 100):.6f}')
        elif kind == 1:
            out.append(f'{rng.uniform(-1, 1):.9f}')
        elif kind == 2:
            out.append(f'{rng.uniform(-1000, 1000):.6e}')
        else:
            out.append(f'{rng.uniform(-10, 10):.17g}')
    return out


def cases(work):
    rng = random.Random(0x0B1)
    out = []
    files = {}

    def add(name, kind, path, contract=False):
        out.append(dict(id=name, kind=kind, path=str(path), contract=contract))

    def obj(name, text, mtl=None, mtl_name=None, contract=False, raw=None):
        path = work / f'{name}.obj'
        files[path] = raw if raw is not None else text.encode()
        if mtl is not None:
            files[work / (mtl_name or f'{name}.mtl')] = mtl.encode() if isinstance(mtl, str) else mtl
        add(name, 'model', path, contract)

    files[work / 'tex_a.png'] = png(4, 4, 1)
    files[work / 'tex_b.png'] = png(3, 5, 2)
    files[work / 'tex_c.png'] = png(2, 2, 3)

    mtl_basic = ('# materials\nnewmtl red\nKa 0.1 0.1 0.1\nKd 1.0 0.0 0.0\nKs 0.5 0.5 0.5\nNs 32.0\nillum 2\nd 1.0\n'
                 'newmtl textured\nKd 0.2 0.4 0.6\nKs 0.0 0.25 1.0\nKe 0.1 0.2 0.3\nNs 96.078431\nmap_Kd tex_a.png\nmap_Ks tex_b.png\n'
                 'map_bump tex_c.png\ndisp missing.png\nTr 0.25\nNi 1.45\n')
    obj('basic', 'mtllib basic.mtl\n' + CUBE + 'o Cube\nusemtl red\nf 1/1/1 2/2/1 3/3/1 4/4/1\nf 6/1/2 5/2/2 8/3/2 7/4/2\nusemtl textured\n'
        'f 4/1/3 3/2/3 7/3/3 8/4/3\nf 5/1/4 6/2/4 2/3/4 1/4/4\nf 2/1/5 6/2/5 7/3/5 3/4/5\nf 5/1/6 1/2/6 4/3/6 8/4/6\n', mtl_basic)
    obj('forms', CUBE + 'g first\nf 1 2 3\nf 1/1 2/2 3/3\nf 1//1 2//2 3//3\nf -8/-4/-6 -7/-3/-6 -6/-2/-6\ng second\nf 5 6 7 8\n'
        'f 1 2 3 4 5\nf 1 2\nf\nf 3\no third\nf 2 3 4\n')
    obj('materials', 'mtllib materials.mtl\n' + CUBE + 'f 1 2 3\nusemtl b\nf 2 3 4\nf 3 4 5\nusemtl a\nf 4 5 6\nusemtl nothing\nf 5 6 7\n'
        'usemtl a  \nf 6 7 8\nusemtl \nf 1 3 5\nusemtl b\nf 2 4 6\n',
        'Kd 0.9 0.9 0.9\nnewmtl a\nKd 0.0 1.0 0.0\nnewmtl b\nKd 0.0 0.0 1.0\nKs 1 1 1\nnewmtl a\nKd 0.5 0.5 0.5\nmap_Kd   \nnewmtl last\nKd 1 1 1')
    obj('shapes', CUBE + 'o empty\ng one\nf 1 2 3\nf 2 3 4\ng two\ng three\nf 3 4 5\no four\nf 4 5 6\nf 5 6 7\nf 6 7 8\ng five\n')
    obj('shapes-late', CUBE + 'f 1 2 3\nf 2 3 4\nf 3 4 5\nf 4 5 6\ng a\nf 5 6 7\ng b\nf 6 7 8\nf 1 2 3\ng c\nf 1 3 5\n')
    obj('crlf', 'v 0 0 0\r\nv 1 0 0\r\nv 0 1 0\r\nvn 0 0 1\r\nf 1//1 2//1 3//1\r\n')
    obj('lone-cr', 'v 0 0 0\rv 1 0 0\rv 0 1 0\rv 1 1 0\rf 1 2 3\rf 2 4 3\r')
    obj('no-final-newline', 'v 0 0 0\nv 1 0 0\nv 0 1 0\nv 1 1 0\nf 1 2 3\nf 2 4 3')
    obj('no-newline-at-all', 'v 0.5 0.25 0.125', raw=None)
    obj('nul-inside', '', raw=b'v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n\x00v 9 9 9\nf 1 2 4\n')
    literals = number_literals(rng, 72)
    if not any(literal_differs(t) for t in literals):
        raise ProbeFailure('obj: no literal rounds differently fused and unfused; the contraction profile is not exercised')
    lines = [f'v {literals[i]} {literals[i + 1]} {literals[i + 2]}' for i in range(0, len(literals), 3)]
    lines += [f'vt {literals[i]} {literals[(i * 7 + 3) % len(literals)]}' for i in range(0, len(literals), 3)]
    lines += [f'vn {literals[(i * 5 + 1) % len(literals)]} {literals[i]} {literals[(i * 11) % len(literals)]}' for i in range(0, len(literals), 3)]
    count = len(literals) // 3
    faces = [f'f {i + 1}/{i + 1}/{i + 1} {(i + 1) % count + 1}/{(i + 1) % count + 1}/{i + 1} {(i + 2) % count + 1}/{i + 1}/{(i + 2) % count + 1}' for i in range(count)]
    obj('numbers', '\n'.join(lines + faces) + '\n')
    obj('partial-indices', 'v 0 0 0\nv 1 0 0\nv 0 1 0\nv 1 1 0\nvt 0.25 0.75\nvn 0 0 1\nf 1/1 2 3//1\nf 2/1/1 4 3\n')
    obj('no-texcoords', 'v 0 0 0\nv 1 0 0\nv 0 1 0\nvn 0 0 1\nf 1//1 2//1 3//1\n')
    obj('forward-index', 'f 1 2 3\nv 0 0 0\nv 1 0 0\nv 0 1 0\n')
    obj('only-vertices', 'v 0 0 0\nv 1 1 1\n# no faces\n')
    obj('comments-blank', '# header\n\n   \n\tv 0 0 0\nv 1 0 0\n  v 0 1 0\nfoo bar\nf  1  2   3  \ns off\n')
    obj('mtl-missing', 'mtllib nowhere.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl x\nf 1 2 3\n')
    obj('mtl-twice', 'mtllib first.mtl\nmtllib mtl-twice.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl two\nf 1 2 3\n',
        'newmtl one\nKd 1 0 0\nnewmtl two\nKd 0 1 0\n')
    if not table_holds([f'm{i}' for i in range(24)]):
        raise ProbeFailure('obj: tinyobj\'s material table cannot hold m0..m23 (the reference would loop forever)')
    many = ''.join(f'newmtl m{i}\nKd {i / 30:.3f} {1 - i / 30:.3f} 0.5\nKs 0.1 0.2 0.3\nNs {i}\n' for i in range(24))
    obj('mtl-many', 'mtllib mtl-many.mtl\n' + CUBE + ''.join(f'usemtl m{(i * 5) % 24}\nf {i % 8 + 1} {(i + 1) % 8 + 1} {(i + 2) % 8 + 1}\n' for i in range(30)), many)
    obj('mtl-absolute', 'mtllib mtl-absolute.mtl\n' + CUBE + 'usemtl abs\nf 1/1/1 2/2/1 3/3/1\n',
        f'newmtl abs\nKd 0.5 0.5 0.5\nmap_Kd {work / "tex_b.png"}\nmap_Ks  tex_a.png\nbump tex_a.png\nKe 1 1 1\n')
    files[work / 'empty.obj'] = b''
    add('empty', 'model', work / 'empty.obj')
    add('missing', 'model', work / 'missing.obj')
    files[work / 'model.txt'] = CUBE.encode()
    add('other-extension', 'model', work / 'model.txt')
    files[work / 'upper.OBJ'] = (CUBE + 'f 1 2 3\n').encode()
    add('upper-extension', 'model', work / 'upper.OBJ')
    files[work / 'materials-direct.mtl'] = (f'newmtl first\nKd 0.25 0.5 0.75\nKs 1 1 1\nKe 0 0 0\nmap_Kd {work / "tex_a.png"}\n'
                                            f'newmtl second\nNs 10\nmap_Ks {work / "tex_c.png"}\ndisp nowhere.png\n').encode()
    add('load-materials', 'materials', work / 'materials-direct.mtl')
    add('load-materials-missing', 'materials', work / 'nowhere.mtl')
    add('load-materials-other', 'materials', work / 'tex_a.png')

    # Contracts.
    obj('hexagon', 'v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nv -1 1 0\nv -1 0 0\nf 1 2 3 4 5 6\n', contract=True)
    obj('index-overflow', 'v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 99999999999\n', contract=True)
    obj('exponent-overflow', 'v 1e99999999999 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n', contract=True)
    obj('long-line', 'v 0 0 0\nv 1 0 0\nv 0 1 0\n# ' + 'x' * 4100 + '\nf 1 2 3\n', contract=True)
    obj('empty-group', 'v 0 0 0\nv 1 0 0\nv 0 1 0\ng \nf 1 2 3\n', contract=True)
    obj('empty-mtllib', 'mtllib \nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n', contract=True)
    obj('vertex-range', 'v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 4\n', contract=True)
    obj('normal-range', 'v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1//1 2//1 3//1\n', contract=True)
    obj('color-cast', 'mtllib color-cast.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl hot\nf 1 2 3\n', 'newmtl hot\nKd 2.0 0 0\n', contract=True)
    obj('newmtl-unnamed', 'mtllib newmtl-unnamed.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n', 'newmtl  \nKd 1 1 1\n', contract=True)
    obj('cr-underflow', '', raw=b'v 0 0 0\r\rv 1 0 0\nv 0 1 0\nf 1 2 3\n', contract=True)
    obj('nul-first', '', raw=b'\x00v 0 0 0\n', contract=True)
    files[work / 'model.iqm'] = b'INTERQUAKEMODEL\x00'
    add('iqm', 'model', work / 'model.iqm', contract=True)
    return out, files


# -----------------------------------------------------------------------------
# C reference

C_PREFIX = r'''#include "raylib.h"
#include <stdio.h>
#include <string.h>
static void words(const char *tag, const float *p, int n)
{
    printf(" %s", tag);
    if (!p) { printf("-"); return; }
    for (int i = 0; i < n; i++) { unsigned b; memcpy(&b, &p[i], 4); printf("%08x", b); }
}
static void material(Material m)
{
    printf(" M");
    for (int i = 0; i < 12; i++)
    {
        MaterialMap p = m.maps[i]; unsigned b; memcpy(&b, &p.value, 4);
        printf("%u,%d,%d,%d,%d,%02x%02x%02x%02x,%08x;", p.texture.id, p.texture.width, p.texture.height, p.texture.mipmaps, p.texture.format,
               p.color.r, p.color.g, p.color.b, p.color.a, b);
    }
}
static void model(const char *path)
{
    Model m = LoadModel(path);
    printf("n%d,%d,%d", m.meshCount, m.materialCount, (int)IsModelValid(m));
    for (int i = 0; i < m.meshCount; i++)
    {
        Mesh *e = &m.meshes[i];
        printf(" m%d,%d,%d", e->vertexCount, e->triangleCount, m.meshMaterial[i]);
        words("v", e->vertices, e->vertexCount*3); words("n", e->normals, e->vertexCount*3); words("t", e->texcoords, e->vertexCount*2);
        printf(" c%d", e->colors != NULL);
    }
    for (int i = 0; i < m.materialCount; i++) material(m.materials[i]);
    printf("\n");
}
static void materials(const char *path)
{
    int count = 0;
    Material *ms = LoadMaterials(path, &count);
    printf("L%d", count);
    for (int i = 0; i < count; i++) material(ms[i]);
    printf("\n");
}
int main(void)
{
    SetTraceLogLevel(LOG_NONE);
'''


def c_case(case):
    call = 'model' if case['kind'] == 'model' else 'materials'
    return f'    InitWindow(16, 16, ""); {call}({json.dumps(case["path"])}); CloseWindow();'


# -----------------------------------------------------------------------------
# Bend candidate

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/frame.bend as FC

def hex.digit(+d: U32) -> Char:
  Chr{Bool.pick(U32, (d < 10 : U32), (d + 48 : U32), (d + 87 : U32))}

def hex.word(+w: U32) -> String:
  SCon{hex.digit((w >> 28n : U32)), SCon{hex.digit(((w >> 24n) .&. 15 : U32)), SCon{hex.digit(((w >> 20n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 16n) .&. 15 : U32)), SCon{hex.digit(((w >> 12n) .&. 15 : U32)), SCon{hex.digit(((w >> 8n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 4n) .&. 15 : U32)), SCon{hex.digit((w .&. 15 : U32)), SNil{}}}}}}}}}

def hex.f32s(xs: +List<F32>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{+x, rest}: hex.f32s(rest, acc ++ hex.word(F32.bits(x)))

def words(tag: String, xs: Maybe<&2, +List<F32>>) -> String:
  match xs:
    case None{}: " " ++ tag ++ "-"
    case Some{+v}: " " ++ tag ++ hex.f32s(v, "")

def info.text(+info: J.TextureInfo) -> String:
  J.TextureInfo{+id, +w, +h, +m, +f} = info
  U32.show(id) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(m) ++ "," ++ U32.show(f)

def map.text(+map: J.MaterialMap) -> String:
  J.MaterialMap{+info, +color, +value} = map
  info.text(info) ++ "," ++ hex.word(color) ++ "," ++ hex.word(F32.bits(value)) ++ ";"

def maps.text(maps: +List<J.MaterialMap>) -> String:
  match maps:
    case Nil{}: ""
    case Con{+map, rest}: map.text(map) ++ maps.text(rest)

def material.text(+m: J.Material) -> String:
  J.Material{+maps, _} = m
  " M" ++ maps.text(maps)

def materials.text(ms: +List<J.Material>) -> String:
  match ms:
    case Nil{}: ""
    case Con{+m, rest}: material.text(m) ++ materials.text(rest)

def count.meshes(ms: +List<J.Mesh>, +n: U32) -> U32:
  match ms:
    case Nil{}: n
    case Con{_, rest}: count.meshes(rest, (n + 1 : U32))

def count.materials(ms: +List<J.Material>, +n: U32) -> U32:
  match ms:
    case Nil{}: n
    case Con{_, rest}: count.materials(rest, (n + 1 : U32))

def colors.flag(cs: Maybe<&2, +List<U32>>) -> String:
  match cs:
    case None{}: " c0"
    case Some{_}: " c1"

def mesh.text(+mesh: J.Mesh, +material: U32) -> String:
  J.Mesh{+vc, +tc, +vs, +ts, _, +ns, _, +cs, _} = mesh
  " m" ++ U32.show(vc) ++ "," ++ U32.show(tc) ++ "," ++ U32.show(material) ++ words("v", vs) ++ words("n", ns) ++ words("t", ts) ++ colors.flag(cs)

def meshes.text(ms: +List<J.Mesh>, mm: +List<U32>) -> String:
  match ms mm:
    case Con{+m, rest} Con{+k, more}: mesh.text(m, k) ++ meshes.text(rest, more)
    case _ _: ""

def flag(b: Bool) -> String:
  match b:
    case True{}: "1"
    case False{}: "0"

def model.text(+m: J.Model) -> String:
  J.Model{_, +meshes, +materials, +mm} = m
  "n" ++ U32.show(count.meshes(meshes, 0)) ++ "," ++ U32.show(count.materials(materials, 0)) ++ "," ++ flag(J.Model.is_valid(m))
    ++ meshes.text(meshes, mm) ++ materials.text(materials)

def loaded.text(r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>) -> String:
  match r:
    case Tuple{_, Fail{_}}: "null"
    case Tuple{_, Done{J.LoadedModel{+m, _}}}: model.text(m)

def materials.loaded(r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedMaterials>) -> String:
  match r:
    case Tuple{_, Fail{_}}: "null"
    case Tuple{_, Done{J.LoadedMaterials{+ms, _}}}: "L" ++ U32.show(count.materials(ms, 0)) ++ materials.text(ms)

def run.model(frame: Maybe<J.Frame>, +path: String) -> IO(String):
  match frame:
    case None{}: IO.pure(String, "no frame")
    case Some{f}: IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, String, J.Model.load_for(arith(), f, path), r => IO.pure(String, loaded.text(r)))

def run.materials(frame: Maybe<J.Frame>, +path: String) -> IO(String):
  match frame:
    case None{}: IO.pure(String, "no frame")
    case Some{f}: IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedMaterials>, String, J.Material.load_materials_for(arith(), f, path), r => IO.pure(String, materials.loaded(r)))
'''


def render(arith):
    def build(selected, gpu):
        body = [PROGRAM.replace('import ../../src/frame.bend as FC\n', f'import ../../src/frame.bend as FC\n\ndef arith() -> M.Contraction:\n  M.{arith}{{}}\n')]
        steps = []
        for index, (_, case) in enumerate(selected):
            call = 'run.model' if case['kind'] == 'model' else 'run.materials'
            steps.append(f'    s{index} : String <- {call}(J.Frame.init_window(16, 16), {json.dumps(case["path"])})\n    IO.print(s{index})')
        body.append('def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(steps) + '\n')
        return '\n\n'.join(body)
    return build


def configure(parser):
    parser.add_argument('--uncontracted-control', action='store_true', help='link the raylib built with -ffp-contract=off (M.Uncontracted{})')


def main():
    args = probekit.arguments(__doc__, configure)
    if args.uncontracted_control:
        options, name, arith = fp.OPTIONS, 'obj-uncontracted', 'Uncontracted'
    else:
        options, name, arith = (), 'obj', contraction()
    probe = probekit.Probe(name, args, raylib_options=options)
    if options:
        fused = fp.fused_instructions(probe.library)
        if any(fused.values()):
            raise ProbeFailure(f'{name}: the uncontracted reference build contains fused multiply-adds: {fused}')
    work = (probe.work / 'files').resolve()
    work.mkdir(parents=True, exist_ok=True)
    items, files = cases(work)
    for path, data in files.items():
        path.write_bytes(data)
    native = [c for c in items if not c['contract']]
    contracts = [c for c in items if c['contract']]
    if len(native) < 25 or len(contracts) < 12:
        raise ProbeFailure(f'{name}: {len(native)} compared and {len(contracts)} refused cases; the corpus lost coverage')
    source = C_PREFIX + '\n'.join(c_case(c) for c in native) + '\n    return 0;\n}\n'
    # rlsw prints its own initialization line; results start with 'n' (models) or 'L' (materials).
    output = [line for line in probe.native(source, 'reference').splitlines() if line[:1] in ('n', 'L')]
    if len(output) != len(native):
        raise ProbeFailure(f'{name}: reference printed {len(output)} lines for {len(native)} cases')
    expected_by_id = {c['id']: line.rstrip() for c, line in zip(native, output)}
    for c in contracts:
        expected_by_id[c['id']] = 'null'
    expected = [expected_by_id[c['id']] for c in items]
    lanes = probe.candidates(render(arith), list(enumerate(items)), batch=8,
                             parse=lambda text, selected: [line.rstrip() for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda i: f'case {items[i]["id"]}')
    probe.finish(cases=len(items), compared=len(native), contracts=len(contracts), profile=arith,
                 refused=[c['id'] for c in contracts],
                 files_sha256=hashlib.sha256(b''.join(str(p).encode() + d for p, d in sorted(files.items()))).hexdigest())


if __name__ == '__main__':
    main()
