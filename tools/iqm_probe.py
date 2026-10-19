#!/usr/bin/env python3
"""Compare Jonlib's loading of Inter-Quake Model files with the pinned raylib.

The probe writes .iqm files under its work directory and loads each one, and
the two files of models_loading_iqm (guy.iqm and guyanim.iqm, read in place
from the pinned raylib checkout), natively (InitWindow on PLATFORM=Memory,
then LoadModel and LoadModelAnimations) and with Jonlib (Model.load_for,
Model.load_skeleton and Model.load_animations_for). A case has three rows:
the model (mesh and material counts, IsModelValid, every mesh's counts,
material and an FNV-1a hash of its vertex, normal and texcoord words, its
color bytes and its indices, then every material map), the skeleton (every
bone's parent, name and bind pose words) and the animations (each one's
name, bone and keyframe counts and a hash of every keyframe's pose).

The files cover: a triangle with positions, texcoords and normals; a mesh
without vertex arrays (zeros); colors, blend indexes and weights, tangents
and a custom array (the last two are not read); two meshes with their own
first vertex, triangles and materials (the corners reversed and rebased, a
corner below the mesh's first vertex wrapping to an unsigned short); two
position arrays (the last one counts); a material that names a PNG beside
the file (its texture's id, size and format are in the material's map), one
that names no file (a texture of zeros) and one with an empty name (raylib
6.2 asks for no texture: the default one stays); joints with a chain of
parents, a parent that comes later (left as read), a joint that is its own
parent and negative parents; animations whose poses have every mask, no
mask and mixed masks, a second animation that starts at a later frame, an
animation without frames, poses without a parent order (a parent read
before it is composed, a pose that is its own parent), a file with frames
and no poses; another magic, another version, an empty file, a missing one
and an upper-case extension.

The reference is the raylib built with -ffp-contract=off (the loaders'
arithmetic is uncontracted). Contracts (Jonlib must answer null for the
rows whose native call is not run): a magic or a header cut short; the
meshes, the triangles, a vertex array or the joints outside the file; a
mesh or material name whose 32 bytes pass the end of the file, a material
or bone name without its NUL, a material name from the root; a mesh whose
vertices or triangles pass the file's, and one without
vertices or without triangles; the poses, the animations, the frame data
or an animation's name outside the file; frame data that ends before the
masks do; a pose whose parent is not a pose; a file over 2 MiB. CPU-1,
CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import struct

import frame_probe as fp
import gltf_anim_probe as ga
import gltf_probe as gp
import probekit
import vox_probe as vp
from probekit import ProbeFailure

FIELDS = ('version filesize flags num_text ofs_text num_meshes ofs_meshes num_vertexarrays num_vertexes ofs_vertexarrays num_triangles ofs_triangles ofs_adjacency num_joints ofs_joints '
          'num_poses ofs_poses num_anims ofs_anims num_frames num_framechannels ofs_frames ofs_bounds num_comment ofs_comment num_extensions ofs_extensions').split()
POSITION, TEXCOORD, NORMAL, TANGENT, BLENDINDEXES, BLENDWEIGHTS, COLOR, CUSTOM = 0, 1, 2, 3, 4, 5, 6, 0x10


def floats(values):
    return struct.pack(f'<{len(values)}f', *values)


def iqm(*, names=(), meshes=(), vertexes=0, arrays=(), triangles=(), joints=(), poses=(), anims=(), frames=(), channels=0, patch=None, magic=b'INTERQUAKEMODEL\x00', tail=32, text=None):
    """An IQM file. Names are given as text and placed in the text block (offset 0 is the empty name); a mesh is
    (name, material, first_vertex, num_vertexes, first_triangle, num_triangles), an array (type, bytes), a joint
    (name, parent, translate, rotate, scale), a pose (parent, mask, offsets, scales), an animation (name,
    first_frame, num_frames); frames are the unsigned shorts of the frame data."""
    block, where = b'\x00', {'': 0}
    for name in names:
        where[name] = len(block)
        block += name.encode() + b'\x00'
    if text is not None:
        block = text
    block += b'\x00' * (-len(block) % 4)
    fields = dict.fromkeys(FIELDS, 0)
    fields['version'] = 2
    body = bytearray()

    def place(count_field, offset_field, data, count):
        fields[count_field] = count
        if offset_field:
            fields[offset_field] = 124 + len(body) if count or data else 0
        body.extend(data)

    def name_of(value):
        return where[value] if isinstance(value, str) else value

    place('num_text', 'ofs_text', block, len(block))
    place('num_meshes', 'ofs_meshes', b''.join(struct.pack('<6I', name_of(m[0]), name_of(m[1]), *m[2:]) for m in meshes), len(meshes))
    blobs = []
    table_at = 124 + len(body)
    data_at = table_at + 20 * len(arrays)
    table = b''
    for kind, data in arrays:
        table += struct.pack('<5I', kind, 0, 7 if kind in (POSITION, TEXCOORD, NORMAL, TANGENT) else 1, 0, data_at)
        blobs.append(data)
        data_at += len(data)
    place('num_vertexarrays', 'ofs_vertexarrays', table + b''.join(blobs), len(arrays))
    fields['num_vertexes'] = vertexes
    place('num_triangles', 'ofs_triangles', b''.join(struct.pack('<3I', *(v & 0xFFFFFFFF for v in t)) for t in triangles), len(triangles))
    place('num_joints', 'ofs_joints', b''.join(struct.pack('<Ii', name_of(j[0]), j[1]) + floats(list(j[2]) + list(j[3]) + list(j[4])) for j in joints), len(joints))
    place('num_poses', 'ofs_poses', b''.join(struct.pack('<iI', p[0], p[1]) + floats(list(p[2]) + list(p[3])) for p in poses), len(poses))
    place('num_anims', 'ofs_anims', b''.join(struct.pack('<IIIfI', name_of(a[0]), a[1], a[2], 24.0, 0) for a in anims), len(anims))
    fields['num_framechannels'] = channels
    place('num_frames', 'ofs_frames', struct.pack(f'<{len(frames)}H', *frames), len(frames) // channels if channels else 0)
    body.extend(bytes(tail))
    fields['filesize'] = 124 + len(body)
    fields.update(patch or {})
    return magic + struct.pack('<27I', *(fields[name] for name in FIELDS)) + bytes(body)


TRIANGLE = dict(vertexes=3, triangles=[(0, 1, 2)],
                arrays=[(POSITION, floats([0, 0, 0, 1.5, 0, 0, 0, 2.25, -0.5])), (TEXCOORD, floats([0, 0, 1, 0, 0.25, 0.75])), (NORMAL, floats([0, 0, 1, 0, 0.6, 0.8, 1, 0, 0]))])
JOINTS = [('root', -1, (0, 1, 0), (0, 0, 0, 1), (1, 1, 1)), ('spine', 0, (0, 2, 0.5), (0.5, 0.5, 0.5, 0.5), (1, 2, 1)), ('arm', 1, (1, 0, 0), (0.6, 0, 0, 0.8), (0.5, 0.5, 2)),
          ('late', 5, (3, 4, 5), (0, 0.6, 0.8, 0), (1, 1, 1)), ('self', 4, (1, 2, 3), (0.8, 0, 0.6, 0), (2, 3, 4)), ('tip', 2, (0.25, 0, 0), (0, 0, 1, 0), (1, 1, 1)), ('loose', -2, (9, 8, 7), (1, 0, 0, 0), (1, 1, 1))]
OFFSETS = (0.5, -1.25, 2, 0.1, 0.2, 0.3, 0.9, 1, 1.5, 0.75)
SCALES = (0.001, 0.002, 0.0005, 0.00001, 0.00002, 0.00003, 0.00001, 0.0001, 0.0002, 0.00015)
POSES = [(-1, 0x3FF, OFFSETS, SCALES), (0, 0, OFFSETS[::-1], SCALES), (1, 0x155, OFFSETS, SCALES[::-1]), (4, 0x78, OFFSETS, SCALES), (4, 0x7, OFFSETS[::-1], SCALES), (-3, 0x200, OFFSETS, SCALES)]
PER_FRAME = sum(bin(pose[1]).count('1') for pose in POSES)


def frame_data(count, per=PER_FRAME, seed=7):
    return [(seed + 7919 * i) % 65536 for i in range(count * per)]


def cases(work, raylib):
    out, files = [], {}

    def add(name, data, model=True, anims=True, extension='.iqm'):
        path = work / f'{name}{extension}'
        files[path] = data
        out.append(dict(id=name, path=str(path), model=model, anims=anims))

    models = raylib / 'examples/models/resources/models/iqm'
    for name in ('guy', 'guyanim'):
        out.append(dict(id=name, path=str(models / f'{name}.iqm'), model=True, anims=True))
    out.append(dict(id='missing', path=str(work / 'missing.iqm'), model=True, anims=True))
    files[work / 'skin.png'] = gp.CHECKER

    one = [('mesh', 'none', 0, 3, 0, 1)]
    add('triangle', iqm(names=['mesh', 'none'], meshes=one, **TRIANGLE))
    add('no-arrays', iqm(names=['mesh', 'none'], meshes=one, vertexes=3, triangles=[(0, 1, 2)]))
    add('colors', iqm(names=['mesh', 'none'], meshes=one, vertexes=3, triangles=[(2, 1, 0)],
                      arrays=TRIANGLE['arrays'] + [(TANGENT, floats([1] * 12)), (BLENDINDEXES, bytes(range(12))), (BLENDWEIGHTS, bytes(range(100, 112))), (COLOR, bytes(range(200, 212))),
                                                   (CUSTOM, bytes(8))]))
    add('two-meshes', iqm(names=['first', 'second', 'none', 'other'], meshes=[('first', 'none', 0, 3, 0, 1), ('second', 'other', 3, 4, 1, 2)], vertexes=7,
                          triangles=[(0, 1, 2), (3, 4, 5), (6, 5, 2)],
                          arrays=[(POSITION, floats([i * 0.5 for i in range(21)])), (NORMAL, floats([1 - i * 0.125 for i in range(21)])), (TEXCOORD, floats([i / 16 for i in range(14)])),
                                  (COLOR, bytes(range(10, 38)))]))
    add('two-positions', iqm(names=['mesh', 'none'], meshes=one, vertexes=3, triangles=[(0, 1, 2)], arrays=[(POSITION, floats([9] * 9)), (POSITION, floats([0, 0, 0, 1, 0, 0, 0, 1, 0]))]))
    add('textured', iqm(names=['mesh', 'skin.png'], meshes=[('mesh', 'skin.png', 0, 3, 0, 1)], **TRIANGLE))
    add('joints', iqm(names=['mesh', 'none'] + [j[0] for j in JOINTS], meshes=one, joints=JOINTS, **TRIANGLE))
    add('skeleton-only', iqm(names=[j[0] for j in JOINTS], joints=JOINTS))
    animated = dict(names=['walk', 'run', 'still'], poses=POSES, channels=PER_FRAME, frames=frame_data(5), anims=[('walk', 0, 3), ('run', 3, 2), ('still', 1, 0)])
    add('animated', iqm(**animated))
    add('animated-model', iqm(names=['mesh', 'none', 'walk'] + [j[0] for j in JOINTS], meshes=one, joints=JOINTS, poses=POSES, channels=PER_FRAME, frames=frame_data(4, seed=99), anims=[('walk', 1, 3)],
                              **TRIANGLE))
    add('no-poses', iqm(names=['idle'], channels=2, frames=[1, 2, 3, 4, 5, 6], anims=[('idle', 0, 3)]))
    add('no-masks', iqm(names=['idle'], poses=[(-1, 0, OFFSETS, SCALES), (0, 0, OFFSETS[::-1], SCALES)], anims=[('idle', 0, 2)]))
    add('other-magic', iqm(names=['mesh', 'none'], meshes=one, magic=b'INTERQUAKEMODEM\x00', **TRIANGLE))
    add('version-1', iqm(names=['mesh', 'none'], meshes=one, patch=dict(version=1), **TRIANGLE))
    add('short-other-magic', b'INTERQUAKEMODEX!')
    add('empty-file', b'')
    add('upper-case', iqm(names=['mesh', 'none'], meshes=one, **TRIANGLE), extension='.IQM')

    whole = iqm(names=['mesh', 'none'], meshes=one, **TRIANGLE)
    size = len(whole)
    add('magic-cut', whole[:10], model=False, anims=False)
    add('header-cut', whole[:60], model=False, anims=False)
    add('over-2-mib', iqm(names=['mesh', 'none'], meshes=one, tail=2 * 1024 * 1024, **TRIANGLE), model=False, anims=False)
    add('joints-outside', iqm(names=['mesh', 'none'], meshes=one, patch=dict(num_joints=1, ofs_joints=size - 8), **TRIANGLE), model=False, anims=False)
    add('meshes-outside', iqm(names=['mesh', 'none'], meshes=one, patch=dict(ofs_meshes=size - 8), **TRIANGLE), model=False)
    add('triangles-outside', iqm(names=['mesh', 'none'], meshes=one, patch=dict(ofs_triangles=size - 4), **TRIANGLE), model=False)
    add('array-outside', iqm(names=['mesh', 'none'], meshes=one, patch=dict(num_vertexes=100000), **TRIANGLE), model=False)
    add('arrays-outside', iqm(names=['mesh', 'none'], meshes=one, patch=dict(ofs_vertexarrays=size - 16), **TRIANGLE), model=False)
    add('mesh-name-outside', iqm(names=['mesh', 'none'], meshes=[(size - 140, 'none', 0, 3, 0, 1)], **TRIANGLE), model=False)
    add('material-name-outside', iqm(names=['mesh', 'none'], meshes=[('mesh', size - 140, 0, 3, 0, 1)], **TRIANGLE), model=False)
    add('material-unterminated', iqm(text=b'\x00mesh\x00' + b'm' * 34, meshes=[(1, 6, 0, 3, 0, 1)], **TRIANGLE), model=False)
    add('empty-material', iqm(names=['mesh'], meshes=[('mesh', '', 0, 3, 0, 1)], **TRIANGLE))
    add('material-from-root', iqm(names=['mesh', '/none'], meshes=[('mesh', '/none', 0, 3, 0, 1)], **TRIANGLE), model=False)
    add('vertices-past', iqm(names=['mesh', 'none'], meshes=[('mesh', 'none', 1, 3, 0, 1)], **TRIANGLE), model=False)
    add('triangles-past', iqm(names=['mesh', 'none'], meshes=[('mesh', 'none', 0, 3, 0, 2)], **TRIANGLE), model=False)
    add('no-vertices', iqm(names=['mesh', 'none'], meshes=[('mesh', 'none', 0, 0, 0, 1)], **TRIANGLE), model=False)
    add('no-triangles', iqm(names=['mesh', 'none'], meshes=[('mesh', 'none', 0, 3, 0, 0)], **TRIANGLE), model=False)
    add('bone-unterminated', iqm(text=b'\x00mesh\x00none\x00' + b'b' * 34, meshes=[(1, 6, 0, 3, 0, 1)], joints=[(11, -1, (0, 0, 0), (0, 0, 0, 1), (1, 1, 1))], **TRIANGLE), model=False)
    moving = iqm(**animated)
    add('poses-outside', iqm(patch=dict(ofs_poses=len(moving) - 80), **animated), anims=False)
    add('anims-outside', iqm(patch=dict(ofs_anims=len(moving) - 12), **animated), anims=False)
    add('frames-outside', iqm(patch=dict(ofs_frames=len(moving) - 6), **animated), anims=False)
    add('anim-name-outside', iqm(names=['walk'], poses=POSES, channels=PER_FRAME, frames=frame_data(3), anims=[(len(moving), 0, 3)]), anims=False)
    add('anim-unterminated', iqm(text=b'\x00' + b'a' * 34, poses=POSES, channels=PER_FRAME, frames=frame_data(3), anims=[(1, 0, 3)]), anims=False)
    add('frames-short', iqm(names=['walk'], poses=POSES, channels=PER_FRAME, frames=frame_data(2), anims=[('walk', 0, 3)], tail=0), anims=False)
    add('frames-from-past', iqm(names=['walk'], poses=POSES, channels=PER_FRAME, frames=frame_data(3), anims=[('walk', 2, 2)], tail=0), anims=False)
    add('pose-parent-outside', iqm(names=['walk'], poses=POSES + [(7, 0, OFFSETS, SCALES)], channels=PER_FRAME, frames=frame_data(3), anims=[('walk', 0, 3)]), anims=False)
    return out, files


C_PREFIX = vp.C_PREFIX.replace('''    for (int i = 0; i < m.materialCount; i++) material(m.materials[i]);
    printf("\\n");
}
''', '''    for (int i = 0; i < m.materialCount; i++) material(m.materials[i]);
    printf("\\nk%d", m.skeleton.boneCount);
    for (int i = 0; i < m.skeleton.boneCount; i++)
    {
        Transform t = m.skeleton.bindPose[i];
        printf(" b%d,", m.skeleton.bones[i].parent); name(m.skeleton.bones[i].name);
        printf(",%08x%08x%08x%08x%08x%08x%08x%08x%08x%08x", fb(t.translation.x), fb(t.translation.y), fb(t.translation.z), fb(t.rotation.x), fb(t.rotation.y),
               fb(t.rotation.z), fb(t.rotation.w), fb(t.scale.x), fb(t.scale.y), fb(t.scale.z));
    }
    printf("\\n");
}
static void anims(const char *path)
{
    int count = 0;
    ModelAnimation *animations = LoadModelAnimations(path, &count);
    printf("a%d", (animations != NULL)? count : 0);
    for (int a = 0; (animations != NULL) && (a < count); a++)
    {
        printf(" A"); name(animations[a].name);
        printf(",%d,%d", animations[a].boneCount, animations[a].keyframeCount);
        for (int k = 0; k < animations[a].keyframeCount; k++) printf(",%08x", hash(animations[a].keyframePoses[k], animations[a].boneCount));
    }
    printf("\\n");
}
''').replace('''static void material(Material m)
''', '''static unsigned fb(float v) { unsigned b; memcpy(&b, &v, 4); return b; }
static unsigned mix(unsigned h, float v) { return (h ^ fb(v))*16777619u; }
static unsigned hash(Transform *pose, int count)
{
    unsigned h = 2166136261u;
    for (int i = 0; i < count; i++)
    {
        Transform t = pose[i];
        h = mix(h, t.translation.x); h = mix(h, t.translation.y); h = mix(h, t.translation.z);
        h = mix(h, t.rotation.x); h = mix(h, t.rotation.y); h = mix(h, t.rotation.z); h = mix(h, t.rotation.w);
        h = mix(h, t.scale.x); h = mix(h, t.scale.y); h = mix(h, t.scale.z);
    }
    return h;
}
static void name(const char *text) { for (int i = 0; text[i]; i++) printf("%02x", (unsigned char)text[i]); }
static void material(Material m)
''')
assert C_PREFIX.count('static void anims(') == 1 and C_PREFIX.count('static unsigned hash(') == 1

ROWS = ga.PROGRAM[ga.PROGRAM.index('def hex.byte('):ga.PROGRAM.index('def run.animations(')]
PROGRAM = vp.PROGRAM.replace('import ../../src/frame.bend as FC\n', 'import ../../src/frame.bend as FC\n\ndef arith() -> M.Contraction:\n  M.Uncontracted{}\n') + '\n' + ROWS + '''
def skeleton.row(r: Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>) -> String:
  match r:
    case Fail{_}: "null"
    case Done{skeleton}: skeleton.text(skeleton)

def run.skeleton(+path: String) -> IO(String):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, String, J.Model.load_skeleton(path), r => IO.pure(String, skeleton.row(r)))

def run.anims(+path: String) -> IO(String):
  IO.bind(Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, String, J.Model.load_animations(path), r => IO.pure(String, animated.text("", r)))
'''


def render(selected, gpu):
    steps = []
    for index, (_, case) in enumerate(selected):
        path = json.dumps(case['path'])
        steps.append(f'    m{index} : String <- run.model(J.Frame.init_window(16, 16), {path})\n    IO.print(m{index})\n    s{index} : String <- run.skeleton({path})\n    IO.print(s{index})\n'
                     f'    a{index} : String <- run.anims({path})\n    IO.print(a{index})')
    return PROGRAM + '\ndef main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(steps) + '\n'


def c_case(case):
    calls = (f'model({json.dumps(case["path"])}); ' if case['model'] else '') + (f'anims({json.dumps(case["path"])}); ' if case['anims'] else '')
    return f'    InitWindow(16, 16, ""); {calls}CloseWindow();'


def expected_rows(items, output):
    """A case's three rows (model, skeleton, animations): the reference's, or null where its call is not run."""
    lines, rows = iter(output), []
    for case in items:
        rows.append(([next(lines), next(lines)] if case['model'] else ['null', 'null']) + [next(lines) if case['anims'] else 'null'])
    if next(lines, None) is not None:
        raise ProbeFailure('iqm: the reference printed more rows than the cases ask for')
    return rows


def grouped(text, selected):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return [lines[index:index + 3] for index in range(0, len(lines), 3)]


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('iqm', args, raylib_options=fp.OPTIONS)
    fused = fp.fused_instructions(probe.library)
    if any(fused.values()):
        raise ProbeFailure(f'iqm: the uncontracted reference build contains fused multiply-adds: {fused}')
    work = (probe.work / 'files').resolve()
    work.mkdir(parents=True, exist_ok=True)
    items, files = cases(work, args.raylib_source.resolve())
    for path, data in files.items():
        path.write_bytes(data)
    compared = sum(case['model'] + case['anims'] for case in items)
    contracts = sum((not case['model']) + (not case['anims']) for case in items)
    if compared < 40 or contracts < 29:
        raise ProbeFailure(f'iqm: {compared} compared and {contracts} refused loads; the corpus lost coverage')
    source = C_PREFIX + '\n'.join(c_case(case) for case in items) + '\n    return 0;\n}\n'
    output = [line.rstrip() for line in probe.native(source, 'reference').splitlines() if line[:1] in ('n', 'k', 'a')]
    expected = expected_rows(items, output)
    by_id = {case['id']: row for case, row in zip(items, expected)}
    if (not by_id['guy'][0].startswith('n1,1,') or ' m224,112,0 ' not in by_id['guy'][0] or not by_id['guy'][1].startswith('k14 ') or not by_id['guy'][2].startswith('a2 A6a756d70,14,61,')
            or not by_id['guyanim'][0].startswith('n0,1,0') or by_id['guyanim'][1] != 'k0' or not by_id['guyanim'][2].startswith('a2 A6a756d70,14,61,')
            or by_id['missing'] != ['n0,1,0' + by_id['missing'][0][6:], 'k0', 'a0'] or by_id['other-magic'][1:] != ['k0', 'a0'] or ',2,2,1,7,' not in by_id['textured'][0]
            or not by_id['animated'][2].startswith('a3 A77616c6b,6,3,') or not by_id['joints'][1].startswith('k7 ')):
        raise ProbeFailure('iqm: the reference did not load the corpus as expected')
    lanes = probe.candidates(render, list(enumerate(items)), batch=24, parse=grouped)
    probe.compare(expected, lanes, describe=lambda index: items[index]['id'])
    probe.finish(cases=len(items), compared=compared, contracts=contracts, refused=[case['id'] for case in items if not (case['model'] and case['anims'])],
                 files_sha256=hashlib.sha256(b''.join(str(p.name).encode() + d for p, d in sorted(files.items()))).hexdigest())


if __name__ == '__main__':
    main()
