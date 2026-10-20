#!/usr/bin/env python3
"""Compare Jonlib's model pose updates with the pinned raylib.

A case is a model file and an animations file. Natively: LoadModel of the
first, LoadModelAnimations of the second, then one sequence of
UpdateModelAnimation and UpdateModelAnimationEx calls on the model (the
animation indices wrap by the file's animation count; nothing is called for a
file without animations). With Jonlib: Model.load_for, Model.load_skeleton,
Model.load_animations_for, Model.pose and the same sequence of
Model.update_animation_for and Model.update_animation_ex_for calls, each on
the model and pose the one before left. A row has the bone count and, for
the loaded model and after every call, an FNV-1a hash of model.currentPose
(ten words a bone), one of model.boneMatrices (sixteen words a bone) and one
of every mesh's animVertices (whether there are any, then vertexCount*3
words: raylib 6.2's CPU skinning), then IsModelAnimationValid of the first
animation (Model.is_animation_valid).

The sequence: whole and fractional frames, a frame past the keyframe count
(wrapped), the last keyframe (the next one wraps to the first), a frame
between -1 and 0, blends of two animations at 0, 1 and between, a blend
above 1 (nothing changes), and a frame that is minus the keyframe count
(its remainder is 0). The cases: greenman.glb and robot.glb (nineteen
skinned meshes, 7218 vertices), the generated two-bone files of the
gltf-anim gate (LINEAR, STEP, a single key, rotations a few degrees apart,
bones listed before their parents, no animations; a quad on the first
bone), a quad whose vertices blend two bones (weights 0.25 and 0.75, a
vertex on three slots, one whose weights are all 0 and goes to the origin),
a quad without JOINTS_0 under a joint (attached to that bone), a model
without bones given another file's animations, and a two-bone model given
greenman's twelve-bone animations.

The reference is the raylib built with -ffp-contract=off. QuaternionSlerp's
acosf and sinf are the host's: every case is compared under M.Glibc239Libm
(glibc before 2.41); under another profile only the cases whose rotations
never need them are. One contract on every profile, the reference not run:
frames whose int conversion or keyframe index is undefined (-1, 2147483648,
not a number, a negative remainder) and an animation with fewer bones than
the skeleton answer None, and a blend that is not a number leaves the pose.
CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

import frame_probe as fp
import gltf_anim_probe as anim
import probekit
from conformance import gradient_reference
from probekit import ProbeFailure

# ('u', animation, frame) is UpdateModelAnimation, ('x', animation, frame,
# animation, frame, blend) UpdateModelAnimationEx. 'N' is minus the first
# animation's keyframe count.
OPS = [('u', 0, '0.0'), ('u', 0, '0.5'), ('u', 0, '3.25'), ('u', 1, '7.75'), ('u', 0, '1000.5'), ('u', 2, '60.0'), ('u', 0, '-0.5'), ('u', 3, '12.0'),
       ('x', 0, '1.5', 1, '2.25', '0.5'), ('x', 0, '0.0', 0, '0.0', '0.0'), ('x', 0, '100.5', 1, '3.0', '1.0'), ('x', 1, '1.0', 0, '1.0', '1.5'),
       ('x', 0, '-0.5', 1, '2.0', '0.25'), ('x', 0, 'N', 2, '5.5', '0.75'), ('x', 2, '59.5', 3, '150.0', '0.125')]
UNCHANGED = 11
MISMATCHED = ('boneless', 'more-bones')
LIBM_FREE = ('constant', 'gentle', 'no-animations', 'boneless', 'weighted', 'parented')
# The cases whose meshes the first update skins (the reference must show animVertices change).
SKINNED = ('greenman', 'robot', 'weighted', 'parented')
CONTRACT = 'c null null null null null null null same'

C_PREFIX = r'''#include "raylib.h"
#include <stdio.h>
#include <string.h>
static unsigned fb(float v) { unsigned b; memcpy(&b, &v, 4); return b; }
static unsigned mix(unsigned h, float v) { return (h ^ fb(v))*16777619u; }
static void show(Model m)
{
    unsigned pose = 2166136261u, matrices = 2166136261u;
    for (int i = 0; (m.currentPose != NULL) && (i < m.skeleton.boneCount); i++)
    {
        Transform t = m.currentPose[i];
        pose = mix(pose, t.translation.x); pose = mix(pose, t.translation.y); pose = mix(pose, t.translation.z);
        pose = mix(pose, t.rotation.x); pose = mix(pose, t.rotation.y); pose = mix(pose, t.rotation.z); pose = mix(pose, t.rotation.w);
        pose = mix(pose, t.scale.x); pose = mix(pose, t.scale.y); pose = mix(pose, t.scale.z);
    }
    for (int i = 0; (m.boneMatrices != NULL) && (i < m.skeleton.boneCount); i++)
    {
        float words[16];
        memcpy(words, &m.boneMatrices[i], sizeof(words));
        for (int k = 0; k < 16; k++) matrices = mix(matrices, words[k]);
    }
    unsigned anim = 2166136261u;
    for (int i = 0; i < m.meshCount; i++)
    {
        float *v = m.meshes[i].animVertices;
        anim = (anim ^ (v != NULL))*16777619u;
        for (int k = 0; (v != NULL) && (k < m.meshes[i].vertexCount*3); k++) anim = mix(anim, v[k]);
    }
    printf(" %08x:%08x:%08x", pose, matrices, anim);
}
static void run(const char *model, const char *animations)
{
    Model m = LoadModel(model);
    int count = 0;
    ModelAnimation *a = LoadModelAnimations(animations, &count);
    if (a == NULL) count = 0;
    printf("p%d", m.skeleton.boneCount);
    show(m);
    if (count > 0)
    {
OPS
        printf(" v%d", IsModelAnimationValid(m, a[0])? 1 : 0);
    }
    printf("\n");
}
int main(void)
{
    SetTraceLogLevel(LOG_NONE);
'''

PROGRAM_TAIL = '''
def matrix.hash(m: M.Matrix, +h: U32) -> U32:
  M.Matrix{+m0, +m4, +m8, +m12, +m1, +m5, +m9, +m13, +m2, +m6, +m10, +m14, +m3, +m7, +m11, +m15} = m
  mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(h, m0), m4), m8), m12), m1), m5), m9), m13), m2), m6), m10), m14), m3), m7), m11), m15)

def matrices.hash(items: +List<M.Matrix>, +h: U32) -> U32:
  match items:
    case Nil{}: h
    case Con{m, rest}: matrices.hash(rest, matrix.hash(m, h))

def word.mix(+h: U32, +w: U32) -> U32:
  ((h .^. w) * 16777619 : U32)

def floats.hash(xs: +List<F32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: floats.hash(rest, mix(h, x))

# A mesh's animVertices: whether there are any, then their words.
def mesh.anim(bones: Maybe<&2, J.MeshBones>, +h: U32) -> U32:
  match bones:
    case Some{J.MeshBones{_, _, Some{+vs}}}: floats.hash(vs, word.mix(h, 1))
    case _: word.mix(h, 0)

def meshes.hash(meshes: +List<J.Mesh>, +h: U32) -> U32:
  match meshes:
    case Nil{}: h
    case Con{J.Mesh{_, _, _, _, _, _, _, _, _, bones}, rest}: meshes.hash(rest, mesh.anim(bones, h))

def model.hash(model: J.Model) -> U32:
  J.Model{_, +meshes, _, _} = model
  meshes.hash(meshes, 2166136261)

def shown.text(+model: J.Model, pose: J.ModelPose) -> String:
  J.ModelPose{current, matrices} = pose
  hex.word(pose.hash(current, 2166136261)) ++ ":" ++ hex.word(matrices.hash(matrices, 2166136261)) ++ ":" ++ hex.word(model.hash(model))

def pose.sum(pose: J.ModelPose) -> U32:
  J.ModelPose{current, matrices} = pose
  matrices.hash(matrices, pose.hash(current, 2166136261))

type State is Data:
  State{model: J.Model, pose: J.ModelPose, text: String}

def shown(result: Maybe<J.AnimatedModel>, +model: J.Model, +previous: J.ModelPose, text: String) -> State:
  match result:
    case None{}: State{model, previous, text ++ " null"}
    case Some{J.AnimatedModel{+m, +pose}}: State{m, pose, text ++ " " ++ shown.text(m, pose)}

def pick.go(items: +List<J.ModelAnimation>) -> J.ModelAnimation:
  match items:
    case Con{item, _}: item
    case Nil{}: J.ModelAnimation{"", 0, 0, Nil{}}

def pick(items: +List<J.ModelAnimation>, +index: U32, +count: U32) -> J.ModelAnimation:
  pick.go(List.drop(&2, J.ModelAnimation, items, U32.to_nat((index % count : U32))))

def frames(animation: J.ModelAnimation) -> F32:
  J.ModelAnimation{_, _, count, _} = animation
  U32.to_f32(count)

def u(state: State, +skeleton: J.ModelSkeleton, +animation: J.ModelAnimation, +frame: F32) -> State:
  State{+model, +pose, text} = state
  shown(J.Model.update_animation_for(libm(), model, skeleton, animation, frame, pose), model, pose, text)

def x(state: State, +skeleton: J.ModelSkeleton, +first: J.ModelAnimation, +first_frame: F32, +second: J.ModelAnimation, +second_frame: F32, +blend: F32) -> State:
  State{+model, +pose, text} = state
  shown(J.Model.update_animation_ex_for(libm(), model, skeleton, first, first_frame, second, second_frame, blend, pose), model, pose, text)

def flagged(state: State, +skeleton: J.ModelSkeleton, +animation: J.ModelAnimation) -> State:
  State{model, pose, text} = state
  State{model, pose, text ++ Bool.pick(String, J.Model.is_animation_valid(skeleton, animation), " v1", " v0")}

def ops(valid: Bool, +skeleton: J.ModelSkeleton, +items: +List<J.ModelAnimation>, +count: U32, state: State) -> State:
  match valid:
    case False{}: state
    case True{}:
OPS

def count.items(items: +List<J.ModelAnimation>, +n: U32) -> U32:
  match items:
    case Nil{}: n
    case Con{_, rest}: count.items(rest, (n + 1 : U32))

def count.bones(bones: +List<J.BoneInfo>, +n: U32) -> U32:
  match bones:
    case Nil{}: n
    case Con{_, rest}: count.bones(rest, (n + 1 : U32))

def bone.count(skeleton: J.ModelSkeleton) -> U32:
  J.ModelSkeleton{+items, _} = skeleton
  count.bones(items, 0)

def text.of(state: State) -> String:
  State{_, _, text} = state
  text

def run.loaded(r: Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, +skeleton: J.ModelSkeleton, +model: J.Model) -> String:
  match r:
    case Fail{_}: "null"
    case Done{+items}:
      text.of(ops((count.items(items, 0) > 0 : U32), skeleton, items, count.items(items, 0),
        State{model, J.Model.pose(skeleton), "p" ++ U32.show(bone.count(skeleton)) ++ " " ++ shown.text(model, J.Model.pose(skeleton))}))

def run.skeleton(r: Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, +animations: String, +model: J.Model) -> IO(String):
  match r:
    case Fail{_}: IO.pure(String, "null")
    case Done{+skeleton}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, String, J.Model.load_animations_for(libm(), animations), a => IO.pure(String, run.loaded(a, skeleton, model)))

def run.model(r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, +path: String, +animations: String) -> IO(String):
  match r:
    case Tuple{_, Fail{_}}: IO.pure(String, "null")
    case Tuple{_, Done{J.LoadedModel{+m, _}}}: IO.bind(Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, String, J.Model.load_skeleton(path), s => run.skeleton(s, animations, m))

def run.framed(frame: Maybe<J.Frame>, +path: String, +animations: String) -> IO(String):
  match frame:
    case None{}: IO.pure(String, "no frame")
    case Some{f}: IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, String, J.Model.load_for(M.Uncontracted{}, f, path), r => run.model(r, path, animations))

def run(+model: String, +animations: String) -> IO(String):
  run.framed(J.Frame.init_window(16, 16), model, animations)

def nan() -> F32:
  (0.0 / 0.0 : F32)

def refused(result: Maybe<J.ModelPose>) -> String:
  match result:
    case None{}: " null"
    case Some{_}: " some"

def kept(result: Maybe<J.ModelPose>, previous: J.ModelPose) -> String:
  match result:
    case None{}: " null"
    case Some{pose}: Bool.pick(String, U32.is_eq(pose.sum(pose), pose.sum(previous)), " same", " changed")

# What must not be answered, from a pose a defined call left.
def contract.from(start: Maybe<J.ModelPose>, +skeleton: J.ModelSkeleton, +nod: J.ModelAnimation, +other: J.ModelSkeleton) -> String:
  match start:
    case None{}: "c bad"
    case Some{+pose}:
      "c" ++ refused(J.Model.update_animation_bones_for(libm(), skeleton, nod, F32.neg(1.0), pose)) ++ refused(J.Model.update_animation_bones_for(libm(), skeleton, nod, 2147483648.0, pose))
        ++ refused(J.Model.update_animation_bones_for(libm(), skeleton, nod, nan(), pose)) ++ refused(J.Model.update_animation_bones_ex_for(libm(), skeleton, nod, F32.neg(1.0), nod, 1.0, 0.5, pose))
        ++ refused(J.Model.update_animation_bones_ex_for(libm(), skeleton, nod, 1.0, nod, F32.neg(2147483904.0), 0.5, pose)) ++ refused(J.Model.update_animation_bones_ex_for(libm(), skeleton, nod, 2.0, nod, nan(), 0.5, pose))
        ++ refused(J.Model.update_animation_bones_for(libm(), other, nod, 1.0, J.Model.pose(other))) ++ kept(J.Model.update_animation_bones_ex_for(libm(), skeleton, nod, 1.0, nod, 1.0, nan(), pose), pose)

def contract.other(r: Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, +skeleton: J.ModelSkeleton, +items: +List<J.ModelAnimation>) -> String:
  match r:
    case Fail{_}: "c unloaded"
    case Done{+other}: contract.from(J.Model.update_animation_bones_for(libm(), skeleton, pick(items, 0, 1), 2.5, J.Model.pose(skeleton)), skeleton, pick(items, 0, 1), other)

def contract.animations(r: Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, +skeleton: J.ModelSkeleton, +other: String) -> IO(String):
  match r:
    case Fail{_}: IO.pure(String, "c unloaded")
    case Done{+items}: IO.bind(Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, String, J.Model.load_skeleton(other), o => IO.pure(String, contract.other(o, skeleton, items)))

def contract.skeleton(r: Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, +path: String, +other: String) -> IO(String):
  match r:
    case Fail{_}: IO.pure(String, "c unloaded")
    case Done{+skeleton}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, String, J.Model.load_animations_for(libm(), path), a => contract.animations(a, skeleton, other))

def contract(+path: String, +other: String) -> IO(String):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, String, J.Model.load_skeleton(path), r => contract.skeleton(r, path, other))
'''


def c_float(text):
    return text + 'f'


def c_ops():
    lines = []
    for op in OPS:
        if op[0] == 'u':
            lines.append(f'        UpdateModelAnimation(m, a[{op[1]}%count], {c_float(op[2])}); show(m);')
        else:
            first = f'-(float)a[{op[1]}%count].keyframeCount' if op[2] == 'N' else c_float(op[2])
            lines.append(f'        UpdateModelAnimationEx(m, a[{op[1]}%count], {first}, a[{op[3]}%count], {c_float(op[4])}, {c_float(op[5])}); show(m);')
    return '\n'.join(lines)


def bend_float(text):
    return f'F32.neg({text[1:]})' if text[:1] == '-' else text


def bend_ops():
    lines, state = [], 'state'
    for index, op in enumerate(OPS):
        if op[0] == 'u':
            call = f'u({state}, skeleton, pick(items, {op[1]}, count), {bend_float(op[2])})'
        else:
            first = f'F32.neg(frames(pick(items, {op[1]}, count)))' if op[2] == 'N' else bend_float(op[2])
            call = f'x({state}, skeleton, pick(items, {op[1]}, count), {first}, pick(items, {op[3]}, count), {bend_float(op[4])}, {bend_float(op[5])})'
        state = f's{index}'
        lines.append(f'      {state} = {call}')
    return '\n'.join(lines + [f'      flagged({state}, skeleton, pick(items, 0, count))'])


def program(libm):
    head = anim.PROGRAM[:anim.PROGRAM.index('def transform.text(')]
    return head.replace('M.LIBM{}', f'M.{libm}{{}}') + PROGRAM_TAIL.lstrip('\n').replace('OPS', bend_ops())


def skinned_files():
    """The quads that test the CPU skinning: blended weights (one vertex of all-zero weights) and a mesh without
    JOINTS_0 under a joint."""
    weights = [0.25, 0.75, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.5, 0.25, 0.25, 0.0, 0.0, 0.0, 0.0, 0.0]
    bones = [0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0]
    nodes = [dict(name='armature', children=[1], translation=[0, anim.raw('0.5'), 0], scale=[2, 2, 2]),
             dict(name='bone_a', children=[2], translation=[anim.raw('0.25'), 0, 0], rotation=[0, 0, anim.QUARTER[0], anim.QUARTER[1]]),
             dict(name='bone_b', children=[3], translation=[0, 1, 0], scale=[1, anim.raw('0.5'), 1]), dict(name='body', mesh=0)]
    return {'weighted': anim.armature(anim.gentle, weights=weights, bones=bones), 'parented': anim.armature(anim.gentle, nodes=nodes, bones=False)}


def cases(work, raylib, libm):
    """The compared cases (model file, animations file) and the contract; the generated files are the gltf-anim gate's."""
    items, files = anim.cases(work, raylib, 'Glibc239Libm')
    paths = {item['id']: item['path'] for item in items}
    for name, data in skinned_files().items():
        path = work / f'{name}.glb'
        files[path] = data
        paths[name] = str(path)
    pairs = [(name, name, name) for name in ('greenman', 'robot', 'linear', 'steps', 'constant', 'gentle', 'no-animations', 'unsorted-bones', 'weighted', 'parented')]
    pairs += [('boneless', 'greenman_hat', 'gentle'), ('more-bones', 'linear', 'greenman')]
    out = [dict(id=name, model=paths[model], animations=paths[animations], contract=False) for name, model, animations in pairs
           if libm == 'Glibc239Libm' or name in LIBM_FREE]
    out.append(dict(id='undefined-calls', model=paths['gentle'], animations=paths['greenman'], contract=True))
    return out, files


def render(libm):
    def build(selected, gpu):
        steps = []
        for index, (_, case) in enumerate(selected):
            call = 'contract' if case['contract'] else 'run'
            steps.append(f'    s{index} : String <- {call}({json.dumps(case["model"])}, {json.dumps(case["animations"])})\n    IO.print(s{index})')
        return program(libm) + '\ndef main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(steps) + '\n'
    return build


def fnv(words, start=2166136261):
    value = start
    for word in words:
        value = ((value ^ word) * 16777619) & 0xFFFFFFFF
    return value


def loaded(bones):
    """The entry of a model as LoadModel leaves it: zeroed transforms and identity matrices (neither without bones)."""
    one = struct.unpack('<I', struct.pack('<f', 1.0))[0]
    if bones == 0:
        return f'{2166136261:08x}:{2166136261:08x}'
    identity = [one, 0, 0, 0, 0, one, 0, 0, 0, 0, one, 0, 0, 0, 0, one]
    return f'{fnv([0] * (10 * bones)):08x}:{fnv(identity * bones):08x}'


def check_reference(rows, libm):
    """The reference rows must show the sequence did what it is there for."""
    for name, row in rows.items():
        entries = [entry for entry in row.split() if entry[:1] != 'v']
        flags = [entry for entry in row.split() if entry[:1] == 'v']
        bones = int(entries[0][1:])
        if entries[1].rsplit(':', 1)[0] != loaded(bones):
            raise ProbeFailure(f'model-pose: the reference did not load {name} with a zeroed pose and identity matrices')
        if name == 'no-animations':
            if len(entries) != 2 or flags:
                raise ProbeFailure('model-pose: the reference updated a model without animations')
            continue
        if len(entries) != 2 + len(OPS):
            raise ProbeFailure(f'model-pose: the reference printed {len(entries) - 2} updates for {name}')
        if flags != ['v0' if name in MISMATCHED else 'v1']:
            raise ProbeFailure(f'model-pose: IsModelAnimationValid of {name} is not what the case is there for')
        if entries[2 + UNCHANGED] != entries[1 + UNCHANGED]:
            raise ProbeFailure(f'model-pose: a blend above 1 changed the pose of {name} in the reference')
        if name == 'boneless':
            if len(set(entries[1:])) != 1:
                raise ProbeFailure('model-pose: the reference changed a model without bones')
        elif entries[2] == entries[1]:
            raise ProbeFailure(f'model-pose: the first update did not change the pose of {name} in the reference')
        if name in SKINNED and entries[2].rsplit(':', 1)[1] == entries[1].rsplit(':', 1)[1]:
            raise ProbeFailure(f'model-pose: the first update did not skin the meshes of {name} in the reference')
    if libm == 'Glibc239Libm' and (rows['greenman'][:4] != 'p12 ' or rows['robot'][:4] != 'p43 ' or rows['more-bones'][:3] != 'p2 '):
        raise ProbeFailure('model-pose: the reference did not load the models as expected')


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('model-pose', args, raylib_options=fp.OPTIONS)
    fused = fp.fused_instructions(probe.library)
    if any(fused.values()):
        raise ProbeFailure(f'model-pose: the uncontracted reference build contains fused multiply-adds: {fused}')
    libm = gradient_reference()
    work = (probe.work / 'files').resolve()
    work.mkdir(parents=True, exist_ok=True)
    items, files = cases(work, args.raylib_source.resolve(), libm)
    for path, data in files.items():
        path.write_bytes(data)
    native = [c for c in items if not c['contract']]
    source = C_PREFIX.replace('OPS', c_ops()) + '\n'.join(
        f'    InitWindow(16, 16, ""); run({json.dumps(c["model"])}, {json.dumps(c["animations"])}); CloseWindow();' for c in native) + '\n    return 0;\n}\n'
    output = [line.rstrip() for line in probe.native(source, 'reference').splitlines() if line[:1] == 'p']
    if len(output) != len(native):
        raise ProbeFailure(f'model-pose: reference printed {len(output)} lines for {len(native)} cases')
    rows = {c['id']: line for c, line in zip(native, output)}
    check_reference(rows, libm)
    expected = [CONTRACT if c['contract'] else rows[c['id']] for c in items]
    lanes = probe.candidates(render(libm), list(enumerate(items)), batch=16, parse=lambda text, selected: [line.rstrip() for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda index: items[index]['id'])
    probe.finish(cases=len(items), compared=len(native), contracts=len(items) - len(native), libm=libm, updates=sum(len(row.split()) - 3 for row in output if ' v' in row))


if __name__ == '__main__':
    main()
