#!/usr/bin/env python3
"""Compare Jonlib's loading of Model 3D files with the pinned raylib.

The probe writes .m3d files (the binary variant) under its work directory
and loads each one, and the three files of the models examples
(cesium_man.m3d, suzanne.m3d and seagull.m3d, read in place from the pinned
raylib checkout), natively (InitWindow on PLATFORM=Memory, then LoadModel
and LoadModelAnimations) and with Jonlib (Model.load_for,
Model.load_skeleton and Model.load_animations). A case has three rows, as
in tools/iqm_probe.py: the model (mesh and material counts, IsModelValid,
every mesh's counts, material and hashes of its vertex, normal and texcoord
words and color bytes, then every material map), the skeleton (every bone's
parent, name and bind pose words) and the animations (each one's name, bone
and keyframe counts and a hash of every keyframe's pose).

The files cover: coordinates as floats, signed bytes and signed shorts;
indices of one, two and four bytes; a scale, and one that is not positive;
faces with and without texture coordinates; vertex colors through a color
map, as words and absent; one material, two materials whose faces
alternate (a mesh a run), a material no face uses (an empty mesh), faces
without a material; every property LoadM3D reads and some it does not; a
map property without a name; bones with a chain of parents, a parent that
comes later, a bone that is its own parent, one bone and four bones a
vertex; actions whose keyframes fall on frames and between them (the
approximated NLERP and its factor carried from bone to bone), a last frame
before the duration (the pose turns back towards the first), two actions, a
duration under one keyframe; the zlib container and the plain one, a
preview chunk, unknown chunks, a second color map, a mesh chunk before its
material; a file without faces, another magic, an empty file, a missing one.

The reference is the raylib built with -ffp-contract=off. Contracts (Jonlib
must answer null for the rows whose native call is not run): a header, a
chunk or a record cut short; an index past the vertices, the texture map,
the color map, the bones or the skins; faces without normals (the importer
generates them: outside the profile); a map property that names a texture
(seagull.m3d's inlined one among them) and procedural, shape, voxel and
label chunks (outside the profile); coordinates as doubles; a material
without a name after another; an action whose frames the chunk does not
hold; a stream the decoder does not finish; a file over 2 MiB. CPU-1, CPU-2
and JavaScript lanes.
"""
import hashlib
import struct
import zlib

import frame_probe as fp
import iqm_probe as ip
import probekit
from probekit import ProbeFailure

UNDEF = -1


class Writer:
    """A Model 3D file in its binary variant. Sizes are bytes per value (0 for an index the file does not have)."""

    def __init__(self, vc=4, vi=2, si=2, ci=0, ti=2, bi=1, nb=1, sk=1, fc=1, scale=1.0):
        self.vc, self.vi, self.si, self.ci, self.ti, self.bi, self.nb, self.sk, self.fc, self.scale = vc, vi, si, ci, ti, bi, nb, sk, fc, scale
        self.strings = b'model\x00license\x00author\x00\x00'
        self.chunks = b''

    def string(self, text):
        """The offset of a string among the header's (0 is the NULL string)."""
        offset = len(self.strings)
        self.strings += text.encode() + b'\x00'
        return offset

    def index(self, size, value):
        if size == 0:
            return b''
        return struct.pack({1: '<b', 2: '<h', 4: '<i'}[size], value) if value < 0 else struct.pack({1: '<B', 2: '<H', 4: '<I'}[size], value)

    def coordinate(self, value):
        if self.vc == 1:
            return struct.pack('<b', round(value * 127))
        if self.vc == 2:
            return struct.pack('<h', round(value * 32767))
        return struct.pack('<f' if self.vc == 4 else '<d', value)

    def chunk(self, name, content):
        self.chunks += name + struct.pack('<I', 8 + len(content)) + content
        return self

    def cmap(self, colors):
        return self.chunk(b'CMAP', b''.join(struct.pack('<I', c) for c in colors))

    def tmap(self, pairs):
        if self.vc == 1:
            body = b''.join(struct.pack('<BB', round(u * 255), round(v * 255)) for u, v in pairs)
        elif self.vc == 2:
            body = b''.join(struct.pack('<HH', round(u * 65535), round(v * 65535)) for u, v in pairs)
        else:
            body = b''.join(struct.pack('<ff', u, v) for u, v in pairs)
        return self.chunk(b'TMAP', body)

    def vertices(self, rows):
        """rows: (x, y, z, w, color, skin); the color is an index or a word by the file's color size."""
        body = b''
        for x, y, z, w, color, skin in rows:
            body += b''.join(self.coordinate(v) for v in (x, y, z, w)) + (self.index(self.ci, color) if self.ci in (1, 2) else struct.pack('<I', color) if self.ci == 4 else b'') + self.index(self.sk, skin)
        return self.chunk(b'VRTS', body)

    def bones(self, bones, skins=(), declared=None, declared_skins=None):
        """bones: (parent, name, pos, ori); skins: lists of (weight byte, bone)."""
        body = self.index(self.bi, len(bones) if declared is None else declared) + self.index(self.sk, len(skins) if declared_skins is None else declared_skins)
        for parent, name, pos, ori in bones:
            body += self.index(self.bi, parent) + self.index(self.si, self.string(name) if isinstance(name, str) else name) + self.index(self.vi, pos) + self.index(self.vi, ori)
        for skin in skins:
            if self.nb > 1:
                body += bytes(weight for weight, _ in skin) + bytes(self.nb - len(skin))
            body += b''.join(self.index(self.bi, bone) for weight, bone in skin if weight)
        return self.chunk(b'BONE', body)

    def material(self, name, props):
        """props: (type, value) with a color as an index or a word, a float, a byte, or a string for a map."""
        body = self.index(self.si, self.string(name) if isinstance(name, str) else name)
        for kind, value in props:
            body += bytes([kind])
            if kind >= 128:
                body += self.index(self.si, self.string(value) if isinstance(value, str) else value)
            elif kind in (0, 1, 2, 4, 5):
                body += self.index(self.ci, value) if self.ci in (1, 2) else struct.pack('<I', value) if self.ci == 4 else b''
            elif kind == 8:
                body += bytes([value])
            else:
                body += struct.pack('<f', value)
        return self.chunk(b'MTRL', body)

    def mesh(self, records):
        """records: ('use', name or 0) or (flags, [(vertex, texcoord, normal), ...])."""
        body = b''
        for record in records:
            if record[0] == 'use':
                body += b'\x00' + self.index(self.si, self.string(record[1]) if isinstance(record[1], str) else record[1])
                continue
            flags, corners = record
            body += bytes([(len(corners) << 4) | flags])
            for vertex, texcoord, normal in corners:
                body += self.index(self.vi, vertex) + (self.index(self.ti, texcoord) if flags & 1 else b'') + (self.index(self.vi, normal) if flags & 2 else b'')
        return self.chunk(b'MESH', body)

    def action(self, name, duration, frames, declared=None):
        """frames: (msec, [(bone, pos, ori), ...])."""
        body = self.index(self.si, self.string(name) if isinstance(name, str) else name) + struct.pack('<HI', len(frames) if declared is None else declared, duration)
        for msec, moves in frames:
            body += struct.pack('<I', msec) + self.index(self.fc, len(moves)) + b''.join(self.index(self.bi, b) + self.index(self.vi, p) + self.index(self.vi, o) for b, p, o in moves)
        return self.chunk(b'ACTN', body)

    def types(self):
        code = lambda size: {1: 0, 2: 1, 4: 2, 8: 3, 0: 3}[size]
        return (code(self.vc) | code(self.vi) << 2 | code(self.si) << 4 | code(self.ci) << 6 | code(self.ti) << 8 | code(self.bi) << 10 | code(self.nb) << 12 | code(self.sk) << 14
                | code(self.fc) << 16 | 3 << 18 | 3 << 20)

    def model(self):
        """HEAD, the chunks and the end mark, before the container."""
        return b'HEAD' + struct.pack('<IfI', 16 + len(self.strings), self.scale, self.types()) + self.strings + self.chunks + b'OMD3'

    def file(self, compressed=False, preview=None, magic=b'3DMO'):
        body = self.model()
        payload = (b'PRVW' + struct.pack('<I', 8 + len(preview)) + preview if preview is not None else b'') + (zlib.compress(body) if compressed else body)
        return magic + struct.pack('<I', 8 + len(payload)) + payload


SQUARE = [(0.0, 0.0, 0.0, 1.0), (1.0, 0.0, 0.0, 1.0), (1.0, 1.0, 0.0, 1.0), (0.0, 1.0, 0.5, 1.0), (0.0, 0.0, 1.0, 0.0), (0.6, 0.0, 0.8, 0.0), (0.0, 0.6, 0.8, 0.0)]
FACES = [(2, [(0, UNDEF, 4), (1, UNDEF, 5), (2, UNDEF, 6)]), (2, [(0, UNDEF, 4), (2, UNDEF, 6), (3, UNDEF, 5)])]
TEXTURED = [(3, [(0, 0, 4), (1, 1, 5), (2, 2, 6)]), (3, [(0, 0, 4), (2, 2, 6), (3, 3, 5)])]
UVS = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.25, 0.75)]


def plain(writer, colors=None, skins=None, vertices=SQUARE):
    """The square's vertices with a color and a skin each."""
    return writer.vertices([(x, y, z, w, (colors or [0] * len(vertices))[i], (skins or [UNDEF] * len(vertices))[i]) for i, (x, y, z, w) in enumerate(vertices)])


# A rig on the square's vertices: positions 0..3, orientations 4..6 and two more (a half turn and an unnormalized one).
RIG_VERTICES = SQUARE + [(0.0, 1.0, 0.0, 0.0), (0.5, 0.5, 0.5, 0.5), (0.3, -0.2, 0.9, 0.4), (-0.6, 0.0, 0.8, 0.0), (0.2, 0.4, 0.4, 0.8), (0.5, 0.25, -0.125, 1.0), (-0.75, 0.5, 0.25, 1.0)]
BONES = [(UNDEF, 'root', 0, 4), (0, 'spine', 1, 5), (1, 'arm', 2, 6), (4, 'late', 3, 7), (4, 'self', 1, 8), (2, 'tip', 12, 9)]
SKINS1 = [[(255, 0)], [(255, 2)], [(255, 5)]]
ACTION = [(0, [(1, 13, 10), (2, 2, 11)]), (40, [(1, 12, 9), (5, 13, 7)]), (95, [(0, 3, 8), (1, 13, 10), (2, 12, 6)]), (130, [(5, 0, 4)])]
# Skins for a rig cut to its first three bones.
SKINS3 = [[(255, 0)], [(255, 2)], [(255, 1)]]


def rigged(**sizes):
    writer = Writer(**sizes)
    plain(writer, skins=[0, 1, 2, 0, UNDEF, UNDEF, UNDEF] + [UNDEF] * 7, vertices=RIG_VERTICES)
    return writer


def cases(work, raylib):
    out, files = [], {}

    def add(name, data, model=True, anims=True):
        path = work / f'{name}.m3d'
        files[path] = data
        out.append(dict(id=name, path=str(path), model=model, anims=anims))

    models = raylib / 'examples/models/resources/models/m3d'
    for name in ('cesium_man', 'suzanne'):
        out.append(dict(id=name, path=str(models / f'{name}.m3d'), model=True, anims=True))
    out.append(dict(id='seagull', path=str(models / 'seagull.m3d'), model=False, anims=False))
    out.append(dict(id='missing', path=str(work / 'missing.m3d'), model=True, anims=True))

    add('square', plain(Writer()).mesh(FACES).file())
    add('square-compressed', plain(Writer()).mesh(FACES).file(compressed=True))
    add('square-preview', plain(Writer()).mesh(FACES).file(preview=b'\x89PNG....'))
    add('bytes', plain(Writer(vc=1, vi=1, si=1, ti=1)).tmap(UVS).mesh(TEXTURED).file())
    add('shorts', plain(Writer(vc=2, vi=4, si=4, ti=4)).tmap(UVS).mesh(TEXTURED).file())
    add('textured', plain(Writer()).tmap(UVS).mesh(TEXTURED).file())
    add('scaled', plain(Writer(scale=2.5)).mesh(FACES).file())
    add('scale-not-positive', plain(Writer(scale=-3.0)).mesh(FACES).file())
    add('color-map', plain(Writer(ci=1).cmap([0xFF112233, 0x00445566, 0x80778899, 0]), colors=[0, 1, 2, 3, 0, 0, 0]).mesh(FACES).file())
    add('color-words', plain(Writer(ci=4), colors=[0xFF0000FF, 0, 0x7F00FF00, 0x01FFFFFF, 0, 0, 0]).mesh(FACES).file())
    add('color-map-second', plain(Writer(ci=1).cmap([0xFF112233, 0xFF445566]).cmap([0xFFFFFFFF, 0xFFFFFFFF]), colors=[0, 1, 1, 0, 0, 0, 0]).mesh(FACES).file())
    w = plain(Writer(ci=1).cmap([0xFF2040C0, 0xFF80FF10, 0x00000000]), colors=[0, 0, 0, 0, 0, 0, 0])
    w.material('red', [(0, 0), (2, 1), (3, 12.5), (4, 1), (65, 0.25), (64, 0.75), (66, 0.5), (7, 1.0), (8, 9), (67, 1.45), (1, 2), (5, 0), (6, 0.125), (68, 3.0), (128, 0)])
    add('material', w.mesh([('use', 'red')] + FACES).file())
    w = plain(Writer(ci=1).cmap([0xFF2040C0, 0xFF80FF10]), colors=[0, 1, 0, 1, 0, 0, 0])
    w.material('first', [(0, 0)]).material('second', [(0, 1), (4, 0)]).material('unused', [(2, 1)])
    add('runs', w.mesh([('use', 'first'), FACES[0], ('use', 'second'), FACES[1], ('use', 'first'), FACES[0], ('use', 0), FACES[1], FACES[0]]).file())
    w = plain(Writer(ci=1).cmap([0xFF2040C0, 0xFF80FF10]), colors=[0] * 7).material('first', [(0, 0)]).material('second', [(0, 1)]).material('third', [(4, 1)])
    add('unused-materials', w.mesh([('use', 'second')] + FACES).file())
    w = plain(Writer(ci=1).cmap([0xFF2040C0]), colors=[0] * 7).material('only', [(0, 0)])
    add('material-defined-twice', w.material('only', [(4, 0)]).mesh([('use', 'only')] + FACES).file())
    add('material-after-mesh', plain(Writer(ci=1).cmap([0xFF2040C0]), colors=[0] * 7).mesh([('use', 'later')] + FACES).material('later', [(0, 0)]).file())
    add('unknown-chunks', plain(Writer().chunk(b'XTRA', b'whatever')).chunk(b'ASET', b'\x00\x00').mesh(FACES).file())
    add('two-meshes', plain(Writer()).mesh(FACES[:1]).mesh(FACES[1:]).file())
    add('rig', rigged().bones(BONES, SKINS1).mesh(FACES).file())
    add('rig-four-weights', rigged(nb=4).bones(BONES, [[(128, 0), (127, 1)], [(255, 2)], [(60, 5), (60, 4), (60, 3), (75, 0)]]).mesh(FACES).file())
    add('rig-no-skins', rigged(sk=0).bones(BONES).mesh(FACES).file())
    add('animated', rigged().bones(BONES, SKINS1).mesh(FACES).action('walk', 170, ACTION).file())
    add('animated-compressed', rigged().bones(BONES, SKINS1).mesh(FACES).action('walk', 170, ACTION).file(compressed=True))
    add('animated-scaled', rigged(scale=0.5).bones(BONES, SKINS1).mesh(FACES).action('walk', 400, ACTION).file())
    add('two-actions', rigged().bones(BONES, SKINS1).mesh(FACES).action('walk', 170, ACTION).action('wave', 68, [(0, [(2, 13, 10)]), (51, [(2, 12, 11), (0, 3, 4)])]).file())
    add('short-action', rigged().bones(BONES, SKINS1).mesh(FACES).action('blink', 16, ACTION[:1]).file())
    add('action-no-frames', rigged().bones(BONES, SKINS1).mesh(FACES).action('none', 170, []).action('walk', 51, ACTION[:2]).file())
    add('actions-without-bones', plain(Writer()).mesh(FACES).action('walk', 170, [(0, [])]).file())
    add('bones-without-faces', rigged().bones(BONES, SKINS1).action('walk', 170, ACTION).file())
    add('no-faces', plain(Writer()).file())
    add('other-magic', plain(Writer()).mesh(FACES).file(magic=b'3DMX'))
    add('ascii-magic', b'3dmo\nModel\n')
    add('empty-file', b'')

    whole = plain(Writer()).mesh(FACES).file()
    add('magic-cut', b'3DM', model=False, anims=False)
    add('header-cut', whole[:20], model=False, anims=False)
    add('length-past-the-file', whole[:4] + struct.pack('<I', len(whole) + 8) + whole[8:], model=False, anims=False)
    add('over-2-mib', plain(Writer().chunk(b'XTRA', bytes(2 * 1024 * 1024))).mesh(FACES).file(), model=False, anims=False)
    add('stream-cut', b'3DMO' + struct.pack('<I', 8 + 20) + zlib.compress(plain(Writer()).mesh(FACES).model())[:20], model=False, anims=False)
    add('doubles', plain(Writer(vc=8)).mesh(FACES).file(), model=False, anims=False)
    add('no-normals', plain(Writer()).mesh([(0, [(0, UNDEF, UNDEF), (1, UNDEF, UNDEF), (2, UNDEF, UNDEF)])]).file(), model=False, anims=False)
    add('vertex-past', plain(Writer()).mesh([(2, [(0, UNDEF, 4), (1, UNDEF, 5), (9, UNDEF, 6)])]).file(), model=False)
    add('normal-past', plain(Writer()).mesh([(2, [(0, UNDEF, 4), (1, UNDEF, 5), (2, UNDEF, 40)])]).file(), model=False)
    add('texcoord-past', plain(Writer()).tmap(UVS).mesh([(3, [(0, 0, 4), (1, 1, 5), (2, 9, 6)])]).file(), model=False)
    add('texcoord-without-map', plain(Writer()).mesh(TEXTURED).file(), model=False)
    add('color-past-the-map', plain(Writer(ci=1).cmap([0xFF112233]), colors=[0, 3, 0, 0, 0, 0, 0]).mesh(FACES).file(), model=False, anims=False)
    add('texture-map-cut', plain(Writer()).chunk(b'TMAP', struct.pack('<fff', 0.0, 1.0, 0.5)).mesh(FACES).file(), model=False, anims=False)
    add('face-cut-inside-a-corner', plain(Writer()).chunk(b'MESH', bytes([0x32]) + struct.pack('<HHH', 0, 4, 1)[:5]).file(), model=False, anims=False)
    add('map-names-a-file', plain(Writer(ci=1).cmap([0xFF2040C0]), colors=[0] * 7).material('skin', [(0, 0), (128, 'texture')]).mesh([('use', 'skin')] + FACES).file(), model=False, anims=False)
    add('procedural', plain(Writer().chunk(b'PROC', b'\x00\x00')).mesh(FACES).file(), model=False, anims=False)
    add('shape', plain(Writer().chunk(b'SHPE', b'\x00\x00')).mesh(FACES).file(), model=False, anims=False)
    add('voxel-types', plain(Writer().chunk(b'VOXT', b'')).mesh(FACES).file(), model=False, anims=False)
    add('labels', plain(Writer().chunk(b'LBLS', b'\x00\x00\x00\x00')).mesh(FACES).file(), model=False, anims=False)
    add('material-without-a-name', plain(Writer(ci=1).cmap([0xFF2040C0]), colors=[0] * 7).material('one', [(0, 0)]).material(0, [(0, 0)]).mesh(FACES).file(), model=False, anims=False)
    add('bone-vertex-past', rigged().bones(BONES[:2] + [(1, 'far', 60, 6)], SKINS3).mesh(FACES).file(), model=False, anims=False)
    add('bone-without-a-name', rigged().bones(BONES[:2] + [(1, 0, 2, 6)], SKINS3).mesh(FACES).file(), model=False)
    add('skin-bone-past', rigged().bones(BONES, [[(255, 0)], [(255, 9)], [(255, 5)]]).mesh(FACES).file(), model=False, anims=False)
    add('bone-cut', rigged().chunk(b'BONE', bytes([2, 0]) + bytes([255]) + struct.pack('<H', 0)).mesh(FACES).file(), model=False, anims=False)
    add('frames-not-held', rigged().bones(BONES, SKINS1).mesh(FACES).action('walk', 170, ACTION, declared=6).file(), model=False, anims=False)
    add('transform-bone-past', rigged().bones(BONES, SKINS1).mesh(FACES).action('walk', 170, [(0, [(9, 13, 10)])]).file(), anims=False)
    add('transform-vertex-past', rigged().bones(BONES, SKINS1).mesh(FACES).action('walk', 170, [(0, [(1, 99, 10)])]).file(), anims=False)
    add('action-without-a-name', rigged().bones(BONES, SKINS1).mesh(FACES).action(0, 170, ACTION).file(), anims=False)
    return out, files


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('m3d', args, raylib_options=fp.OPTIONS)
    fused = fp.fused_instructions(probe.library)
    if any(fused.values()):
        raise ProbeFailure(f'm3d: the uncontracted reference build contains fused multiply-adds: {fused}')
    work = (probe.work / 'files').resolve()
    work.mkdir(parents=True, exist_ok=True)
    items, files = cases(work, args.raylib_source.resolve())
    for path, data in files.items():
        path.write_bytes(data)
    compared = sum(case['model'] + case['anims'] for case in items)
    contracts = sum((not case['model']) + (not case['anims']) for case in items)
    if compared < 60 or contracts < 50:
        raise ProbeFailure(f'm3d: {compared} compared and {contracts} refused loads; the corpus lost coverage')
    source = ip.C_PREFIX + '\n'.join(ip.c_case(case) for case in items) + '\n    return 0;\n}\n'
    output = [line.rstrip() for line in probe.native(source, 'reference').splitlines() if line[:1] in ('n', 'k', 'a')]
    expected = ip.expected_rows(items, output)
    by_id = {case['id']: row for case, row in zip(items, expected)}
    if (not by_id['cesium_man'][0].startswith('n1,2,') or ' m14016,4672,1 ' not in by_id['cesium_man'][0] or not by_id['cesium_man'][1].startswith('k20 ') or not by_id['cesium_man'][2].startswith('a1 A416e696d,20,112,')
            or not by_id['suzanne'][0].startswith('n1,1,') or by_id['suzanne'][1:] != ['k0', 'a0'] or not by_id['missing'][0].startswith('n0,1,0') or not by_id['square'][0].startswith('n1,1,')
            or not by_id['runs'][0].startswith('n4,4,') or not by_id['unused-materials'][0].startswith('n3,4,') or ' m0,0,0 v- n- t- c- i-' not in by_id['unused-materials'][0] or not by_id['rig'][1].startswith('k7 ') or not by_id['animated'][2].startswith('a1 A77616c6b,7,10,')
            or not by_id['two-actions'][2].startswith('a2 ') or by_id['short-action'][2] != 'a1 A626c696e6b,7,0' or by_id['no-faces'][0][:6] != 'n0,1,0'):
        raise ProbeFailure('m3d: the reference did not load the corpus as expected')
    lanes = probe.candidates(ip.render, list(enumerate(items)), batch=30, parse=ip.grouped)
    probe.compare(expected, lanes, describe=lambda index: items[index]['id'])
    probe.finish(cases=len(items), compared=compared, contracts=contracts, refused=[case['id'] for case in items if not (case['model'] and case['anims'])],
                 files_sha256=hashlib.sha256(b''.join(str(p.name).encode() + d for p, d in sorted(files.items()))).hexdigest())


if __name__ == '__main__':
    main()
