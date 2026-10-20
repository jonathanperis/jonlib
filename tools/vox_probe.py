#!/usr/bin/env python3
"""Compare Jonlib's LoadModel of MagicaVoxel files (LoadVOX) with the pinned raylib.

The probe writes .vox files under its work directory and loads each one, and
the four models of models_loading_vox (chr_knight, chr_sword, monu9 and fez,
read in place from the pinned raylib checkout), natively (InitWindow on
PLATFORM=Memory, then LoadModel) and with Jonlib (Model.load_for). A row has
the mesh and material counts, IsModelValid, and for every mesh its vertex and
triangle counts, its material and an FNV-1a hash of its vertex words, normal
words, texcoords (none), color bytes and the indices of its triangles; then
every material map.

The files cover: one voxel (six faces); neighbors along each axis (the faces
between them are left out); a voxel in each corner of sizes that are not
multiples of 16, and one in the padding past the sizes; sizes that differ on
every axis with voxels and colors drawn from a seeded generator (the order
of the mesh: x, then z, then y; the file's Y and Z changed over); a voxel
set twice (the last id) and one set back to 0; a file without a palette
(every color 0) and with one (255 colors: palette 1 to 255); chunks after a
palette (read four bytes early: they are not seen), a palette whose last
color spells XYZI (the next chunk is then read as its voxel count); two SIZE
chunks (the array starts again); version 200; unknown chunks and a MAIN
chunk with children; a chunk whose size passes the end of the file; an
upper-case extension; more than 65536 vertices (seven meshes), and a count
whose last mesh loses four vertices; a missing file, an empty one, another
magic and another version (the empty model).

Contracts (Jonlib must answer null, and the reference is not run): a magic,
a version, a chunk header, a SIZE, a voxel count, the voxels or a palette
cut short, and a file that ends with its palette (the loader reads a chunk
header four bytes before the end); a voxel before any SIZE and one outside the padded sizes on each
axis; a file without a visible voxel; a palette before the voxels (they are
not seen); a size over 1024, an array over 2^21 cells and a file over
2 MiB. CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import random
import struct

import frame_probe as fp
import obj_probe as op
import probekit
from probekit import ProbeFailure


def chunk(name, content=b'', children=0):
    return name + struct.pack('<II', len(content), children) + content


def size(x, y, z):
    return chunk(b'SIZE', struct.pack('<III', x, y, z))


def xyzi(voxels, count=None):
    body = b''.join(bytes(v) for v in voxels)
    return chunk(b'XYZI', struct.pack('<I', len(voxels) if count is None else count) + body)


def palette(colors=None, last=None):
    """An RGBA chunk: 256 colors, of which the loader reads 255."""
    colors = list(colors) if colors is not None else [(i, 255 - i, (i * 7) % 256, 255) for i in range(1, 256)]
    colors = colors[:255] + [last if last is not None else (1, 2, 3, 4)]
    return chunk(b'RGBA', b''.join(bytes(c) for c in colors))


def end():
    """A chunk after a palette: the loader reads its name as the size of a chunk named by the palette's last
    color, and stops. A file that ends with its palette is read four bytes past its end."""
    return chunk(b'NOTE', bytes(4))


def vox(*chunks, magic=b'VOX ', version=150, main=True):
    body = b''.join(chunks)
    return magic + struct.pack('<I', version) + ((b'MAIN' + struct.pack('<II', 0, len(body))) if main else b'') + body


def scattered(seed, dims, count):
    rng = random.Random(seed)
    return [(rng.randrange(dims[0]), rng.randrange(dims[1]), rng.randrange(dims[2]), rng.randrange(1, 256)) for _ in range(count)]


def lattice(count):
    """Voxels two apart on every axis (none touches another): six faces each."""
    out = []
    for x in range(0, 64, 2):
        for y in range(0, 64, 2):
            for z in range(0, 64, 2):
                if len(out) == count:
                    return out
                out.append((x, y, z, 1 + len(out) % 255))
    return out


EXAMPLE_MODELS = ('chr_knight', 'chr_sword', 'monu9', 'fez')


def cases(work, raylib):
    out, files = [], {}

    def add(name, data, contract=False, extension='.vox'):
        path = work / f'{name}{extension}'
        files[path] = data
        out.append(dict(id=name, kind='model', path=str(path), contract=contract))

    for name in EXAMPLE_MODELS:
        out.append(dict(id=name, kind='model', path=str(raylib / f'examples/models/resources/models/vox/{name}.vox'), contract=False))
    out.append(dict(id='missing', kind='model', path=str(work / 'missing.vox'), contract=False))

    add('one', vox(size(1, 1, 1), xyzi([(0, 0, 0, 1)]), palette(), end()))
    add('pair-x', vox(size(4, 4, 4), xyzi([(1, 1, 1, 9), (2, 1, 1, 10)]), palette(), end()))
    add('pair-y', vox(size(4, 4, 4), xyzi([(1, 1, 1, 9), (1, 2, 1, 10)]), palette(), end()))
    add('pair-z', vox(size(4, 4, 4), xyzi([(1, 1, 1, 9), (1, 1, 2, 10)]), palette(), end()))
    add('block', vox(size(3, 3, 3), xyzi([(x, y, z, 1 + x + 3 * y + 9 * z) for x in range(3) for y in range(3) for z in range(3)]), palette(), end()))
    add('corners', vox(size(20, 21, 22), xyzi([(x, y, z, 200 + (x > 0) + 2 * (y > 0) + 4 * (z > 0)) for x in (0, 19) for y in (0, 20) for z in (0, 21)]), palette(), end()))
    add('padding', vox(size(20, 21, 22), xyzi([(25, 3, 4, 7), (3, 30, 4, 8), (3, 4, 31, 9), (31, 31, 31, 10)]), palette(), end()))
    add('scattered', vox(size(5, 9, 13), xyzi(scattered(0xB0C5, (5, 9, 13), 180)),
                         palette([(random.Random(i).randrange(256), (i * 37) % 256, (i * 91) % 256, 128 + i % 128) for i in range(1, 256)]), end()))
    add('wide', vox(size(40, 17, 3), xyzi(scattered(0x51DE, (40, 17, 3), 300)), palette(), end()))
    add('twice', vox(size(4, 4, 4), xyzi([(1, 1, 1, 9), (1, 1, 1, 77)]), palette(), end()))
    add('erased', vox(size(4, 4, 4), xyzi([(1, 1, 1, 9), (2, 1, 1, 10), (1, 1, 1, 0)]), palette(), end()))
    add('two-lists', vox(size(4, 4, 4), xyzi([(1, 1, 1, 9)]), xyzi([(2, 1, 1, 10), (0, 0, 0, 11)]), palette(), end()))
    add('no-palette', vox(size(4, 4, 4), xyzi([(1, 1, 1, 9), (3, 3, 3, 255)])))
    add('after-palette', vox(size(4, 4, 4), xyzi([(1, 1, 1, 9)]), palette(), xyzi([(2, 2, 2, 10)]), chunk(b'nTRN', bytes(28))))
    add('palette-spells-xyzi', vox(size(4, 4, 4), xyzi([(1, 1, 1, 9)]), palette(last=tuple(b'XYZI')), chunk(b'PACK', b'abcd'), chunk(b'LAYR')))
    add('two-sizes', vox(size(8, 8, 8), xyzi([(7, 7, 7, 3), (0, 0, 0, 4)]), size(3, 5, 2), xyzi([(2, 4, 1, 5)]), palette(), end()))
    add('version-200', vox(size(2, 2, 2), xyzi([(0, 0, 0, 1), (1, 1, 1, 2)]), palette(), end(), version=200))
    add('unknown-chunks', vox(chunk(b'PACK', struct.pack('<I', 1)), size(2, 2, 2), chunk(b'nTRN', bytes(range(40))), xyzi([(1, 0, 1, 33)]), chunk(b'LAYR', b'xyz'), palette(), end()))
    add('no-main', vox(size(2, 2, 2), xyzi([(1, 0, 1, 33)]), palette(), end(), main=False))
    add('past-the-end', vox(size(2, 2, 2), xyzi([(1, 0, 1, 33)]), b'MATL' + struct.pack('<II', 4000, 0) + b'short'))
    add('header-then-skip', vox(size(2, 2, 2), xyzi([(1, 0, 1, 33)]), b'MATL' + struct.pack('<I', 9)))
    add('upper-case', vox(size(1, 1, 1), xyzi([(0, 0, 0, 1)]), palette(), end()), extension='.VOX')
    add('seven-meshes', vox(size(32, 32, 32), xyzi([(x, y, z, 1 + (x + y + z) % 255) for x in range(0, 32, 2) for y in range(0, 32, 2) for z in range(0, 32, 2)]
                                                    + [(x, y, z, 5) for x in range(1, 32, 2) for y in range(1, 32, 2) for z in range(0, 32, 2)]
                                                    + [(x, y, z, 6) for x in range(0, 32, 2) for y in range(1, 32, 2) for z in range(1, 32, 2)]
                                                    + [(x, y, z, 7) for x in range(1, 32, 2) for y in range(0, 32, 2) for z in range(1, 32, 2)]), palette(), end()))
    add('four-lost', vox(size(64, 64, 64), xyzi(lattice(8190) + [(63, 63, 62, 250), (63, 63, 63, 251)]), palette(), end()))
    add('empty-file', b'')
    add('other-magic', vox(size(1, 1, 1), xyzi([(0, 0, 0, 1)]), magic=b'VOXX'))
    add('short-other-magic', b'VA')
    add('other-version', vox(size(1, 1, 1), xyzi([(0, 0, 0, 1)]), version=151))

    whole = vox(size(4, 4, 4), xyzi([(1, 1, 1, 9), (2, 2, 2, 10)]), palette())
    add('palette-last', whole, contract=True)
    add('magic-cut', b'VOX', contract=True)
    add('version-cut', b'VOX \x96\x00', contract=True)
    add('header-cut', vox(size(2, 2, 2), xyzi([(1, 0, 1, 33)]), b'MATL\x00'), contract=True)
    add('size-cut', vox(size(4, 4, 4)[:-3]), contract=True)
    add('count-cut', vox(size(4, 4, 4), xyzi([])[:-2]), contract=True)
    add('voxels-cut', vox(size(4, 4, 4), xyzi([(1, 1, 1, 9)], count=3)), contract=True)
    add('palette-cut', whole[:-40], contract=True)
    add('palette-first', vox(palette(), size(4, 4, 4), xyzi([(1, 1, 1, 9)])), contract=True)
    add('voxel-before-size', vox(xyzi([(0, 0, 0, 1)]), size(4, 4, 4), palette(), end()), contract=True)
    add('voxel-past-x', vox(size(20, 4, 4), xyzi([(32, 1, 1, 9)]), palette(), end()), contract=True)
    add('voxel-past-y', vox(size(4, 20, 4), xyzi([(1, 32, 1, 9)]), palette(), end()), contract=True)
    add('voxel-past-z', vox(size(4, 4, 20), xyzi([(1, 1, 32, 9)]), palette(), end()), contract=True)
    add('no-voxels', vox(size(4, 4, 4), xyzi([]), palette(), end()), contract=True)
    add('header-only', vox(main=False), contract=True)
    add('zero-ids', vox(size(4, 4, 4), xyzi([(1, 1, 1, 0), (2, 2, 2, 0)]), palette(), end()), contract=True)
    add('zero-size', vox(size(0, 4, 4), xyzi([]), palette(), end()), contract=True)
    add('size-over-1024', vox(size(1025, 1, 1), xyzi([(0, 0, 0, 1)]), palette(), end()), contract=True)
    add('array-over-2-21', vox(size(256, 64, 256), xyzi([(0, 0, 0, 1)]), palette(), end()), contract=True)
    add('over-2-mib', vox(size(4, 4, 4), xyzi([(1, 1, 1, 9)]), chunk(b'NOTE', bytes(2 * 1024 * 1024))), contract=True)
    return out, files


C_PREFIX = r'''#include "raylib.h"
#include <stdio.h>
#include <string.h>
static unsigned fnv_words(const void *p, int n)
{
    unsigned h = 2166136261u;
    for (int i = 0; i < n; i++) { unsigned b; memcpy(&b, (const char *)p + 4*i, 4); h = (h ^ b)*16777619u; }
    return h;
}
static void floats(const char *tag, const float *p, int n)
{
    if (!p) printf(" %s-", tag);
    else printf(" %s%08x", tag, fnv_words(p, n));
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
        unsigned h = 2166136261u;
        printf(" m%d,%d,%d", e->vertexCount, e->triangleCount, m.meshMaterial[i]);
        floats("v", e->vertices, e->vertexCount*3); floats("n", e->normals, e->vertexCount*3); floats("t", e->texcoords, e->vertexCount*2);
        if (!e->colors) printf(" c-");
        else { for (int k = 0; k < e->vertexCount*4; k++) h = (h ^ e->colors[k])*16777619u; printf(" c%08x", h); }
        h = 2166136261u;
        if (!e->indices) printf(" i-");
        else { for (int k = 0; k < e->triangleCount*3; k++) h = (h ^ e->indices[k])*16777619u; printf(" i%08x", h); }
        if (!e->boneIndices || !e->boneWeights) printf(" b- w-");
        else
        {
            h = 2166136261u;
            for (int k = 0; k < e->vertexCount*4; k++) h = (h ^ e->boneIndices[k])*16777619u;
            printf(" b%08x", h);
            h = 2166136261u;
            for (int k = 0; k < e->vertexCount*4; k++) { unsigned b; memcpy(&b, &e->boneWeights[k], 4); h = (h ^ b)*16777619u; }
            printf(" w%08x", h);
        }
    }
    for (int i = 0; i < m.materialCount; i++) material(m.materials[i]);
    printf("\n");
}
int main(void)
{
    SetTraceLogLevel(LOG_NONE);
'''

PROGRAM = op.PROGRAM.replace(
    '''def mesh.text(+mesh: J.Mesh, +material: U32) -> String:
  J.Mesh{+vc, +tc, +vs, +ts, _, +ns, _, +cs, _, _} = mesh
  " m" ++ U32.show(vc) ++ "," ++ U32.show(tc) ++ "," ++ U32.show(material) ++ words("v", vs) ++ words("n", ns) ++ words("t", ts) ++ colors.flag(cs)
''', '''def fnv(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: fnv(rest, (U32.xor(h, x) * 16777619 : U32))

def fnv.f32s(xs: +List<F32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: fnv.f32s(rest, (U32.xor(h, F32.bits(x)) * 16777619 : U32))

def hashed.f32s(tag: String, xs: Maybe<&2, +List<F32>>) -> String:
  match xs:
    case None{}: " " ++ tag ++ "-"
    case Some{+v}: " " ++ tag ++ hex.word(fnv.f32s(v, 2166136261))

def hashed(tag: String, xs: Maybe<&2, +List<U32>>) -> String:
  match xs:
    case None{}: " " ++ tag ++ "-"
    case Some{+v}: " " ++ tag ++ hex.word(fnv(v, 2166136261))

# boneIndices and boneWeights (raylib 6.2's bone data): both, or neither.
def bones.hashed(bones: Maybe<&2, J.MeshBones>) -> String:
  match bones:
    case None{}: " b- w-"
    case Some{J.MeshBones{+ix, +ws, _}}: " b" ++ hex.word(fnv(ix, 2166136261)) ++ " w" ++ hex.word(fnv.f32s(ws, 2166136261))

def mesh.text(+mesh: J.Mesh, +material: U32) -> String:
  J.Mesh{+vc, +tc, +vs, +ts, _, +ns, _, +cs, +ix, +bones} = mesh
  " m" ++ U32.show(vc) ++ "," ++ U32.show(tc) ++ "," ++ U32.show(material) ++ hashed.f32s("v", vs) ++ hashed.f32s("n", ns) ++ hashed.f32s("t", ts) ++ hashed("c", cs) ++ hashed("i", ix)
    ++ bones.hashed(bones)
''')
assert PROGRAM != op.PROGRAM


def render(selected, gpu):
    body = [PROGRAM.replace('import ../../src/frame.bend as FC\n', 'import ../../src/frame.bend as FC\n\ndef arith() -> M.Contraction:\n  M.Uncontracted{}\n')]
    steps = [f'    s{index} : String <- run.model(J.Frame.init_window(16, 16), {json.dumps(case["path"])})\n    IO.print(s{index})' for index, (_, case) in enumerate(selected)]
    body.append('def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(steps) + '\n')
    return '\n\n'.join(body)


def expected_shape(expected_by_id):
    """What the reference must have made of the examples' models and of the meshes the corpus is built to split."""
    return (expected_by_id['chr_knight'].startswith('n1,1,') and ' m2920,1460,0 ' in expected_by_id['chr_knight']
            and ' m2040,1020,0 ' in expected_by_id['chr_sword']
            and expected_by_id['monu9'].startswith('n3,1,') and ' m7240,3620,0 ' in expected_by_id['monu9']
            and expected_by_id['fez'].startswith('n3,1,') and ' m58168,29084,0 ' in expected_by_id['fez']
            and expected_by_id['one'].startswith('n1,1,') and ' m24,12,0 ' in expected_by_id['one']
            and expected_by_id['seven-meshes'].startswith('n7,1,') and ' m24,12,0 ' in expected_by_id['seven-meshes']
            and expected_by_id['four-lost'].startswith('n3,1,') and expected_by_id['four-lost'].count(' m65532,32766,0 ') == 3
            and all(expected_by_id[name].startswith('n0,1,0') for name in ('missing', 'empty-file', 'other-magic', 'short-other-magic', 'other-version')))


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('vox', args, raylib_options=fp.OPTIONS)
    work = (probe.work / 'files').resolve()
    work.mkdir(parents=True, exist_ok=True)
    items, files = cases(work, args.raylib_source.resolve())
    for path, data in files.items():
        path.write_bytes(data)
    native = [c for c in items if not c['contract']]
    contracts = [c for c in items if c['contract']]
    if len(native) < 30 or len(contracts) < 15:
        raise ProbeFailure(f'vox: {len(native)} compared and {len(contracts)} refused cases; the corpus lost coverage')
    source = C_PREFIX + '\n'.join(op.c_case(c) for c in native) + '\n    return 0;\n}\n'
    output = [line for line in probe.native(source, 'reference').splitlines() if line[:1] == 'n']
    if len(output) != len(native):
        raise ProbeFailure(f'vox: reference printed {len(output)} lines for {len(native)} cases')
    expected_by_id = {c['id']: line.rstrip() for c, line in zip(native, output)}
    if not expected_shape(expected_by_id):
        raise ProbeFailure('vox: the reference did not load the corpus as expected')
    for c in contracts:
        expected_by_id[c['id']] = 'null'
    expected = [expected_by_id[c['id']] for c in items]
    lanes = probe.candidates(render, list(enumerate(items)), batch=20, parse=lambda text, selected: [line.rstrip() for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda index: items[index]['id'])
    probe.finish(cases=len(items), compared=len(native), contracts=len(contracts), refused=[c['id'] for c in contracts],
                 files_sha256=hashlib.sha256(b''.join(str(p.name).encode() + d for p, d in sorted(files.items()))).hexdigest())


if __name__ == '__main__':
    main()
