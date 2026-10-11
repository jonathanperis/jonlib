#!/usr/bin/env python3
"""Compare Jonlib's model skeletons and animations of .glb files with the pinned raylib.

Each file is loaded natively (InitWindow on PLATFORM=Memory, LoadModel and
LoadModelAnimations) and with Jonlib (Model.load_skeleton and
Model.load_animations_for). A row has the skeleton (every bone's parent, name
and bind pose words) and every animation: its name, bone count, keyframe
count and, for each keyframe, an FNV-1a hash of the pose's words (ten a bone:
translation, rotation, scale).

The files: the models the examples animate (greenman.glb and robot.glb, read
in place from the pinned raylib checkout) and a model without a skin, and
generated ones: two bones under an armature node with LINEAR rotation,
translation and scale channels (the rotation keys a quarter turn apart, so
QuaternionSlerp takes its acosf and sinf), STEP channels, a single key, an
animation without channels, a channel for a node outside the skeleton, a
time past the last key (the reference then reads key 0 with t = 1), names
longer than 31 bytes, bones listed before their parents.

The reference is the raylib built with -ffp-contract=off. QuaternionSlerp's
acosf and sinf are the host's: the rows are compared under M.Glibc239Libm
(glibc before 2.41); under another profile the files whose rotations need
them are contracts (Jonlib must answer null). Contracts on every profile, the
reference not run: a CUBICSPLINE sampler, a first joint without a parent node
(cgltf reads through a null pointer), an output accessor shorter than its
keys, integer key times. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

import frame_probe as fp
import probekit
from conformance import gradient_reference
from gltf_probe import Builder, glb, quad, raw
from probekit import ProbeFailure

C_PREFIX = r'''#include "raylib.h"
#include <stdio.h>
#include <string.h>
static unsigned fb(float v) { unsigned b; memcpy(&b, &v, 4); return b; }
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
static void run(const char *path)
{
    Model m = LoadModel(path);
    printf("k%d", m.skeleton.boneCount);
    for (int i = 0; i < m.skeleton.boneCount; i++)
    {
        Transform t = m.skeleton.bindPose[i];
        printf(" b%d,", m.skeleton.bones[i].parent); name(m.skeleton.bones[i].name);
        printf(",%08x%08x%08x%08x%08x%08x%08x%08x%08x%08x", fb(t.translation.x), fb(t.translation.y), fb(t.translation.z), fb(t.rotation.x), fb(t.rotation.y),
               fb(t.rotation.z), fb(t.rotation.w), fb(t.scale.x), fb(t.scale.y), fb(t.scale.z));
    }
    int count = 0;
    ModelAnimation *animations = LoadModelAnimations(path, &count);
    printf(" a%d", (animations != NULL)? count : 0);
    for (int a = 0; (animations != NULL) && (a < count); a++)
    {
        printf(" A"); name(animations[a].name);
        printf(",%d,%d", animations[a].boneCount, animations[a].keyframeCount);
        for (int k = 0; k < animations[a].keyframeCount; k++) printf(",%08x", hash(animations[a].keyframePoses[k], animations[a].boneCount));
    }
    printf("\n");
}
int main(void)
{
    SetTraceLogLevel(LOG_NONE);
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M

def libm() -> M.Libm:
  M.LIBM{}

def hex.digit(+d: U32) -> Char:
  Chr{Bool.pick(U32, (d < 10 : U32), (d + 48 : U32), (d + 87 : U32))}

def hex.word(+w: U32) -> String:
  SCon{hex.digit(((w >> 28n) .&. 15 : U32)), SCon{hex.digit(((w >> 24n) .&. 15 : U32)), SCon{hex.digit(((w >> 20n) .&. 15 : U32)), SCon{hex.digit(((w >> 16n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 12n) .&. 15 : U32)), SCon{hex.digit(((w >> 8n) .&. 15 : U32)), SCon{hex.digit(((w >> 4n) .&. 15 : U32)), SCon{hex.digit((w .&. 15 : U32)), SNil{}}}}}}}}}

def hex.byte(+b: U32) -> String:
  SCon{hex.digit(((b >> 4n) .&. 15 : U32)), SCon{hex.digit((b .&. 15 : U32)), SNil{}}}

def hex.name(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{c, rest}: hex.byte(Char.to_u32(c)) ++ hex.name(rest)

def int.text(+v: U32) -> String:
  Bool.pick(String, (v >= 2147483648 : U32), "-" ++ U32.show((0 - v : U32)), U32.show(v))

def mix(+h: U32, +v: F32) -> U32:
  ((h .^. F32.bits(v)) * 16777619 : U32)

def transform.hash(t: J.Transform, +h: U32) -> U32:
  J.Transform{translation, rotation, scale} = t
  M.Vector3{+tx, +ty, +tz} = translation
  M.Vector4{+rx, +ry, +rz, +rw} = rotation
  M.Vector3{+sx, +sy, +sz} = scale
  mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(h, tx), ty), tz), rx), ry), rz), rw), sx), sy), sz)

def pose.hash(pose: +List<J.Transform>, +h: U32) -> U32:
  match pose:
    case Nil{}: h
    case Con{t, rest}: pose.hash(rest, transform.hash(t, h))

def transform.text(t: J.Transform) -> String:
  J.Transform{translation, rotation, scale} = t
  M.Vector3{+tx, +ty, +tz} = translation
  M.Vector4{+rx, +ry, +rz, +rw} = rotation
  M.Vector3{+sx, +sy, +sz} = scale
  hex.word(F32.bits(tx)) ++ hex.word(F32.bits(ty)) ++ hex.word(F32.bits(tz)) ++ hex.word(F32.bits(rx)) ++ hex.word(F32.bits(ry)) ++ hex.word(F32.bits(rz)) ++ hex.word(F32.bits(rw))
    ++ hex.word(F32.bits(sx)) ++ hex.word(F32.bits(sy)) ++ hex.word(F32.bits(sz))

def bones.text(bones: +List<J.BoneInfo>, poses: +List<J.Transform>) -> String:
  match bones poses:
    case Con{J.BoneInfo{name, +parent}, rest} Con{pose, more}: " b" ++ int.text(parent) ++ "," ++ hex.name(name) ++ "," ++ transform.text(pose) ++ bones.text(rest, more)
    case _ _: ""

def count.bones(bones: +List<J.BoneInfo>, +n: U32) -> U32:
  match bones:
    case Nil{}: n
    case Con{_, rest}: count.bones(rest, (n + 1 : U32))

def frames.text(poses: +List<+List<J.Transform>>) -> String:
  match poses:
    case Nil{}: ""
    case Con{pose, rest}: "," ++ hex.word(pose.hash(pose, 2166136261)) ++ frames.text(rest)

def animations.text(items: +List<J.ModelAnimation>) -> String:
  match items:
    case Nil{}: ""
    case Con{J.ModelAnimation{name, +bones, +frames, poses}, rest}: " A" ++ hex.name(name) ++ "," ++ U32.show(bones) ++ "," ++ U32.show(frames) ++ frames.text(poses) ++ animations.text(rest)

def count.animations(items: +List<J.ModelAnimation>, +n: U32) -> U32:
  match items:
    case Nil{}: n
    case Con{_, rest}: count.animations(rest, (n + 1 : U32))

def animated.text(text: String, r: Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>) -> String:
  match r:
    case Fail{_}: "null"
    case Done{+items}: text ++ " a" ++ U32.show(count.animations(items, 0)) ++ animations.text(items)

def skeleton.text(skeleton: J.ModelSkeleton) -> String:
  J.ModelSkeleton{+bones, poses} = skeleton
  "k" ++ U32.show(count.bones(bones, 0)) ++ bones.text(bones, poses)

def run.animations(r: Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, +path: String) -> IO(String):
  match r:
    case Fail{_}: IO.pure(String, "null")
    case Done{skeleton}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, String, J.Model.load_animations_for(libm(), path), a => IO.pure(String, animated.text(skeleton.text(skeleton), a)))

def run(+path: String) -> IO(String):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, String, J.Model.load_skeleton(path), r => run.animations(r, path))
'''

QUARTER = [raw('0.7071067690849304'), raw('0.7071067690849304')]


def armature(animations, joints=(1, 2), nodes=None, **extra):
    """A quad skinned to two bones under an armature node; `animations` builds the animations from the Builder."""
    b = Builder()
    weights = b.accessor(b.view(struct.pack('<16f', *([1.0, 0.0, 0.0, 0.0] * 4))), 5126, 'VEC4', 4)
    bones = b.accessor(b.view(struct.pack('<16B', *([0, 0, 0, 0] * 4))), 5121, 'VEC4', 4)
    prim = quad(b, JOINTS_0=bones, WEIGHTS_0=weights)
    tree = nodes or [dict(name='armature', children=[1], translation=[0, raw('0.5'), 0], scale=[2, 2, 2]),
                     dict(name='bone_a', children=[2], translation=[raw('0.25'), 0, 0], rotation=[0, 0, QUARTER[0], QUARTER[1]]),
                     dict(name='bone_b', translation=[0, 1, 0], scale=[1, raw('0.5'), 1]), dict(name='body', mesh=0, skin=0)]
    return glb(b.document(nodes=tree, meshes=[dict(primitives=[prim])], skins=[dict(joints=list(joints))], animations=animations(b), **extra), b.data)


def times(b, values, component=5126):
    code = {5126: 'f', 5123: 'H'}[component]
    return b.accessor(b.view(struct.pack(f'<{len(values)}{code}', *values)), component, 'SCALAR', len(values))


def keys(b, values, kind):
    return b.floats([float(v) for v in values], kind)


def turn(angle):
    """A rotation about Z as a quaternion, in binary32."""
    import math
    half = math.radians(angle) / 2
    return [0.0, 0.0, struct.unpack('<f', struct.pack('<f', math.sin(half)))[0], struct.unpack('<f', struct.pack('<f', math.cos(half)))[0]]


def channel(sampler, node, path):
    return dict(sampler=sampler, target=dict(node=node, path=path))


def linear(b):
    rotation = dict(input=times(b, [0.0, 0.5, 1.0]), output=keys(b, turn(0) + turn(90) + turn(180), 'VEC4'))
    translation = dict(input=times(b, [0.0, 0.25, 0.75]), output=keys(b, [0, 0, 0, 1, 2, 3, -1, 0.5, 0.25], 'VEC3'), interpolation='LINEAR')
    scale = dict(input=times(b, [0.0, 1.0]), output=keys(b, [1, 1, 1, 2, 0.5, 1.5], 'VEC3'))
    return [dict(name='turn', samplers=[rotation, translation, scale], channels=[channel(0, 1, 'rotation'), channel(1, 2, 'translation'), channel(2, 2, 'scale')])]


def stepped(b):
    rotation = dict(input=times(b, [0.0, 0.5, 1.0]), output=keys(b, turn(0) + turn(90) + turn(180), 'VEC4'), interpolation='STEP')
    translation = dict(input=times(b, [0.1, 0.4]), output=keys(b, [1, 2, 3, 4, 5, 6], 'VEC3'), interpolation='STEP')
    return [dict(name='steps', samplers=[rotation, translation], channels=[channel(0, 1, 'rotation'), channel(1, 2, 'translation')]),
            dict(name='empty', samplers=[], channels=[]),
            dict(name='a name of more than thirty-one bytes for the animation', samplers=[translation], channels=[channel(0, 1, 'translation')])]


def constant(b):
    single = dict(input=times(b, [0.5]), output=keys(b, [3, 2, 1], 'VEC3'))
    outside = dict(input=times(b, [0.0, 2.0]), output=keys(b, [0, 0, 0, 9, 9, 9], 'VEC3'))
    weights = dict(input=times(b, [0.0, 0.3]), output=b.accessor(b.view(struct.pack('<2f', 0.0, 1.0)), 5126, 'SCALAR', 2))
    return [dict(samplers=[single, outside, weights], channels=[channel(0, 2, 'translation'), channel(1, 3, 'translation'), channel(2, 1, 'weights')])]


def gentle(b):
    """Rotations a few degrees apart: QuaternionSlerp's nlerp branch, which needs no libm."""
    rotation = dict(input=times(b, [0.0, 0.2]), output=keys(b, turn(0) + turn(10), 'VEC4'))
    return [dict(name='nod', samplers=[rotation], channels=[channel(0, 1, 'rotation')])]


def cubic(b):
    rotation = dict(input=times(b, [0.0, 1.0]), output=keys(b, [0.0] * 24, 'VEC4'), interpolation='CUBICSPLINE')
    return [dict(samplers=[rotation], channels=[channel(0, 1, 'rotation')])]


def short(b):
    translation = dict(input=times(b, [0.0, 1.0]), output=keys(b, [1, 2, 3], 'VEC3'))
    return [dict(samplers=[translation], channels=[channel(0, 1, 'translation')])]


def integer_times(b):
    translation = dict(input=times(b, [0, 1], 5123), output=keys(b, [1, 2, 3, 4, 5, 6], 'VEC3'))
    return [dict(samplers=[translation], channels=[channel(0, 1, 'translation')])]


def cases(work, raylib, libm):
    out, files = [], {}
    slerp = libm != 'Glibc239Libm'

    def add(name, data, contract=False):
        path = work / f'{name}.glb'
        files[path] = data
        out.append(dict(id=name, path=str(path), contract=contract))

    models = raylib / 'examples/models/resources/models/gltf'
    for name in ('greenman', 'robot'):
        out.append(dict(id=name, path=str(models / f'{name}.glb'), contract=slerp))
    out.append(dict(id='greenman_hat', path=str(models / 'greenman_hat.glb'), contract=False))
    out.append(dict(id='missing', path=str(work / 'missing.glb'), contract=False))
    add('linear', armature(linear), contract=slerp)
    add('steps', armature(stepped))
    add('constant', armature(constant))
    add('gentle', armature(gentle))
    add('no-animations', armature(lambda b: []))
    long_names = [dict(name='armature', children=[2]), dict(name='a bone whose name is longer than thirty-one bytes', translation=[1, 2, 3]),
                  dict(name='parent listed after its child', children=[1], rotation=[0, 0, QUARTER[0], QUARTER[1]], translation=[0, 0, 1]), dict(mesh=0, skin=0)]
    add('unsorted-bones', armature(stepped, nodes=long_names))
    add('cubic-spline', armature(cubic), contract=True)
    add('short-output', armature(short), contract=True)
    add('integer-times', armature(integer_times), contract=True)
    rootless = [dict(name='bone_a', children=[1]), dict(name='bone_b'), dict(name='spare'), dict(mesh=0, skin=0)]
    add('root-joint-without-parent', armature(stepped, joints=(0, 1), nodes=rootless), contract=True)
    return out, files


def render(libm):
    def build(selected, gpu):
        steps = [f'    s{index} : String <- run({json.dumps(case["path"])})\n    IO.print(s{index})' for index, (_, case) in enumerate(selected)]
        return PROGRAM.replace('M.LIBM{}', f'M.{libm}{{}}') + '\ndef main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(steps) + '\n'
    return build


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('gltf-anim', args, raylib_options=fp.OPTIONS)
    fused = fp.fused_instructions(probe.library)
    if any(fused.values()):
        raise ProbeFailure(f'gltf-anim: the uncontracted reference build contains fused multiply-adds: {fused}')
    libm = gradient_reference()
    work = (probe.work / 'files').resolve()
    work.mkdir(parents=True, exist_ok=True)
    items, files = cases(work, args.raylib_source.resolve(), libm)
    for path, data in files.items():
        path.write_bytes(data)
    native = [c for c in items if not c['contract']]
    source = C_PREFIX + '\n'.join(f'    InitWindow(16, 16, ""); run({json.dumps(c["path"])}); CloseWindow();' for c in native) + '\n    return 0;\n}\n'
    output = [line for line in probe.native(source, 'reference').splitlines() if line[:1] == 'k']
    if len(output) != len(native):
        raise ProbeFailure(f'gltf-anim: reference printed {len(output)} lines for {len(native)} cases')
    expected_by_id = {c['id']: line.rstrip() for c, line in zip(native, output)}
    if libm == 'Glibc239Libm' and (expected_by_id['greenman'][:4] != 'k12 ' or ' a4 ' not in expected_by_id['greenman'] or expected_by_id['robot'][:4] != 'k43 '
                                   or ' a14 ' not in expected_by_id['robot']):
        raise ProbeFailure('gltf-anim: the reference did not load the examples\' animations as expected')
    if expected_by_id['greenman_hat'] != 'k0 a0' or expected_by_id['missing'] != 'k0 a0' or ' a1 A7475726e,2,61,' not in expected_by_id.get('linear', ' a1 A7475726e,2,61,'):
        raise ProbeFailure('gltf-anim: the reference did not answer the plain cases as expected')
    expected = [expected_by_id.get(c['id'], 'null') for c in items]
    lanes = probe.candidates(render(libm), list(enumerate(items)), batch=4, parse=lambda text, selected: [line.rstrip() for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda index: items[index]['id'])
    probe.finish(cases=len(items), compared=len(native), contracts=len(items) - len(native), libm=libm,
                 keyframes=sum(line.count(',') for line in output))


if __name__ == '__main__':
    main()
