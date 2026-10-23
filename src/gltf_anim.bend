# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.2 rmodels.c (zlib, LICENSES/raylib.txt):
# LoadBoneInfoGLTF (a joint's parent is its nearest ancestor among the
# joints) and the skeleton LoadGLTF builds from a file's first skin (the bind
# pose is MatrixDecompose of MatrixInvert of each joint's inverse bind
# matrix, or of its world matrix without enough of them), and
# LoadModelAnimationsGLTF with GetPoseAtTimeGLTF and
# BuildPoseFromParentJoints (each channel with its own sampler's
# interpolation, a time past the last key on the last pair, and each joint's
# pose under the non-joint nodes between it and its parent bone), over
# src/gltf.bend's container, accessor and node helpers (cgltf 1.15, MIT,
# LICENSES/cgltf.txt). A .glb file with its buffer in the BIN chunk;
# samplers with float inputs and outputs and STEP or LINEAR interpolation;
# inverse bind matrices as float MAT4 elements. None (refused) for what the
# reference would read outside that: CUBICSPLINE samplers, other accessor
# layouts, a sampler without keys, a read past an accessor or the buffer, a
# skin without joints, a cycle of nodes above a joint, and a rotation
# QuaternionSlerp does not answer under the libm profile. The arithmetic is
# uncontracted. See docs/MODELS.md.
import Base
import ./../jonmath.bend as M
import ./json.bend as JS
import ./gltf.bend as G
import ./text.bend as T

# raylib's Transform.
type Transform is Data:
  Transform{translation: M.Vector3, rotation: M.Vector4, scale: M.Vector3}

# BoneInfo: the name's first 31 bytes and the parent's index among the bones
# (4294967295 for -1).
type Bone is Data:
  Bone{name: +List<U32>, parent: U32}

# ModelSkeleton: the bones and their bind pose.
type Skeleton is Data:
  Skeleton{bones: +List<Bone>, bind: +List<Transform>}

# ModelAnimation: keyframe poses, one list of bone transforms a frame.
type Animation is Data:
  Animation{name: +List<U32>, bones: U32, frames: U32, poses: +List<+List<Transform>>}

# A file's JSON, its BIN chunk and that chunk's length.
type Bundle is Data:
  Bundle{root: JS.Json, bin: +List<U32>, limit: U32}

def none() -> U32:
  4294967295

# A walk up the nodes that does not end (a cycle): not a bone index.
def unended() -> U32:
  4294967294

def file.json(root: +Maybe<JS.Json>, +bin: +List<U32>, +limit: U32) -> Maybe<Bundle>:
  match root:
    case None{}: None{}
    case Some{+value}: Bool.pick(Maybe<Bundle>, G.fixup(value) && G.buffers.ok(G.list(value, "buffers"), limit), Some{Bundle{value, bin, limit}}, None{})

# The container, as src/gltf.bend reads it: "glTF", version 2, the total
# length, a JSON chunk and a BIN chunk; the indices cgltf checks.
def file(+bytes: +List<U32>) -> Maybe<Bundle>:
  +size = G.length(bytes, 0)
  +json_length = G.u32(List.drop(&2, U32, bytes, 12n))
  +after = List.drop(&2, U32, bytes, U32.to_nat((20 + json_length : U32)))
  +bin_length = G.u32(after)
  +valid = (size >= 28 : U32) && U32.is_eq(G.u32(bytes), 1179937895) && U32.is_eq(G.u32(List.drop(&2, U32, bytes, 4n)), 2) && U32.is_eq(G.u32(List.drop(&2, U32, bytes, 8n)), size) &&
    U32.is_eq(G.u32(List.drop(&2, U32, bytes, 16n)), 1313821514) && G.good(json_length) && ((28 + json_length : U32) <= size : U32) &&
    U32.is_eq(G.u32(List.drop(&2, U32, after, 4n)), 5130562) && G.good(bin_length) && U32.is_eq((28 + json_length + bin_length : U32), size)
  Bool.pick(Maybe<Bundle>, valid, file.json(JS.parse(G.take(U32.to_nat(json_length), List.drop(&2, U32, bytes, 20n))), List.drop(&2, U32, after, 8n), bin_length), None{})

# -----------------------------------------------------------------------------
# The BIN chunk in blocks

# The chunk cut in blocks of 4096 bytes: an accessor is reached through its
# block, not by walking every byte before it (a model's animations read
# thousands of accessors).
def blocks(n: Nat, +bin: +List<U32>) -> +List<+List<U32>>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{G.take(4096n, bin), blocks(p, List.drop(&2, U32, bin, 4096n))}

def joined(n: Nat, blocks: +List<+List<U32>>) -> +List<U32>:
  match n blocks:
    case 1n+p Con{+block, rest}: List.append(&2, U32, block, joined(p, rest))
    case _ _: Nil{}

# The chunk's bytes from `start` on: `length` of them at least, when the
# chunk has that many.
def window(+blocks: +List<+List<U32>>, +start: U32, +length: U32) -> +List<U32>:
  List.drop(&2, U32, joined(U32.to_nat(((((start % 4096) + length) / 4096) + 1 : U32)), List.drop(&2, +List<U32>, blocks, U32.to_nat((start / 4096 : U32)))), U32.to_nat((start % 4096 : U32)))

# The bytes a span's elements take, or the whole chunk when that count of
# steps passes its end.
def needed(+step: U32, +count: U32, +comps: U32, +limit: U32) -> U32:
  Bool.pick(U32, U32.is_eq(count, 0), 0, Bool.pick(U32, ((count - 1 : U32) > (limit / Bool.pick(U32, U32.is_eq(step, 0), 1, step) : U32) : U32), limit, (step * (count - 1) + 4 * comps : U32)))

# G.read32 of a span over the blocks; nothing for a span that is not valid.
def read(valid: Bool, span: G.Span, +blocks: +List<+List<U32>>, +comps: U32, +limit: U32) -> +List<U32>:
  match valid:
    case False{}: Nil{}
    case True{}:
      G.Span{_, +start, +step, +count} = span
      G.words32(U32.to_nat(count), window(blocks, start, needed(step, count, comps, limit)), U32.to_nat(comps), U32.to_nat(step))

# -----------------------------------------------------------------------------
# The skeleton

def joints.go(items: +List<JS.Json>) -> +List<U32>:
  match items:
    case Nil{}: Nil{}
    case Con{+item, rest}: Con{G.int.of(Some{item}, G.bad()), joints.go(rest)}

# The first skin's joints, as node indices.
def joints(+root: JS.Json) -> +List<U32>:
  joints.go(G.list(G.nth(G.list(root, "skins"), 0), "joints"))

# A node's place among the joints, or -1.
def find(joints: +List<U32>, +wanted: U32, +index: U32) -> U32:
  match joints:
    case Nil{}: none()
    case Con{+joint, rest}: Bool.pick(U32, U32.is_eq(joint, wanted), index, find(rest, wanted, (index + 1 : U32)))

# strncpy(name, object.name, 31): the first 31 bytes, none without a name.
def name(+object: JS.Json) -> +List<U32>:
  G.take(31n, T.until(G.text.of(JS.get(object, T.bytes("name")))))

# LoadBoneInfoGLTF's parent (raylib 6.2): from the node `at`, up its
# ancestors past every node that is not a joint, to the first joint (its
# place) or the root (-1). more: the walk goes on from `at`; answer: what it
# found when it stops. unended() when the fuel runs out (a cycle) or a node
# has two parents.
def parent.walk(n: Nat, +nodes: +List<JS.Json>, +total: U32, +all: +List<U32>, +at: U32, +answer: U32, more: Bool) -> U32:
  match n more:
    case 1n+p True{}:
      +up = G.parent(nodes, at, 0, total, total)
      +place = find(all, up, 0)
      parent.walk(p, nodes, total, all, up, Bool.pick(U32, U32.is_eq(up, total), none(), Bool.pick(U32, G.good(up), place, unended())), (up < total : U32) && U32.is_eq(place, none()))
    case _ True{}: unended()
    case _ False{}: answer

# LoadBoneInfoGLTF: each joint's name and its nearest joint ancestor's place among the joints.
def bones(items: +List<U32>, +nodes: +List<JS.Json>, +total: U32, +all: +List<U32>) -> +List<Bone>:
  match items:
    case Nil{}: Nil{}
    case Con{+joint, rest}: Con{Bone{name(G.nth(nodes, joint)), parent.walk(U32.to_nat((total + 1 : U32)), nodes, total, all, joint, none(), True{})}, bones(rest, nodes, total, all)}

# Every bone's parent walk ended.
def bones.ok(items: +List<Bone>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{Bone{_, +parent}, rest}: U32.is_ne(parent, unended()) && bones.ok(rest)

# A node with two parents fails cgltf's parse.
def parents.ok(items: +List<U32>, +nodes: +List<JS.Json>, +total: U32) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+joint, rest}: (G.parent(nodes, joint, 0, total, total) <= total : U32) && parents.ok(rest, nodes, total)

def transform.of(parts: M.Matrix.Decomposition) -> Transform:
  M.Decomposed{translation, rotation, scale} = parts
  Transform{translation, rotation, scale}

def lm.ok(lm: G.Lm) -> Bool:
  G.Lm{ok, _} = lm
  ok

def lm.transform(lm: G.Lm) -> Transform:
  G.Lm{_, +v} = lm
  transform.of(M.Matrix.decompose(G.matrix(v)))

# cgltf_node_transform_world of a node.
def world(+nodes: +List<JS.Json>, +total: U32, +node: U32) -> G.Lm:
  G.world(U32.to_nat((total + 1 : U32)), nodes, total, node, G.local(G.nth(nodes, node)))

# The skin's inverseBindMatrices (raylib 6.2's LoadGLTF): mode 0 without
# them or with fewer than the joints (the bind pose is then each joint's
# world matrix), 1 with float MAT4 elements in the buffer (values: 16
# floats a joint, column-major as cgltf reads them), 2 any other accessor
# (refused: cgltf converts other component types, reads zeros without a
# buffer view and nothing from a sparse accessor).
type Inverses is Data:
  Inverses{mode: U32, values: +List<F32>}

def inverses.read(present: Bool, +root: JS.Json, +bin: +List<+List<U32>>, +limit: U32, +joints: U32) -> Inverses:
  match present:
    case False{}: Inverses{0, Nil{}}
    case True{}:
      +index = G.int(G.nth(G.list(root, "skins"), 0), "inverseBindMatrices", G.bad())
      +count = G.int(G.nth(G.list(root, "accessors"), index), "count", G.bad())
      +matrices = G.span(root, index, 5126, "MAT4", 4, 16, limit)
      +valid = G.span.ok(matrices)
      Bool.pick(Inverses, G.good(count) && (count < joints : U32), Inverses{0, Nil{}},
        Bool.pick(Inverses, valid, Inverses{1, G.words.floats(read(valid, matrices, bin, 16, limit))}, Inverses{2, Nil{}}))

# (Named inverses.kind and inverses.list: the C target mangles the
# accessors Inverses.mode and Inverses.values like inverses.mode.)
def inverses.kind(ibm: Inverses) -> U32:
  Inverses{mode, _} = ibm
  mode

def inverses.list(ibm: Inverses) -> +List<F32>:
  Inverses{_, +values} = ibm
  values

# The bind pose without inverse bind matrices: MatrixDecompose of each joint's world matrix.
def bind.world(items: +List<U32>, +nodes: +List<JS.Json>, +total: U32) -> +List<Transform>:
  match items:
    case Nil{}: Nil{}
    case Con{+joint, rest}: Con{lm.transform(world(nodes, total, joint)), bind.world(rest, nodes, total)}

def bind.world.ok(items: +List<U32>, +nodes: +List<JS.Json>, +total: U32) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+joint, rest}: lm.ok(world(nodes, total, joint)) && bind.world.ok(rest, nodes, total)

# The bind pose from the inverse bind matrices: MatrixDecompose(MatrixInvert(inverseBindMatrices[i])).
def bind.inverse(items: +List<U32>, +values: +List<F32>) -> +List<Transform>:
  match items:
    case Nil{}: Nil{}
    case Con{_, rest}: Con{transform.of(M.Matrix.decompose(M.Matrix.invert(G.matrix(values)))), bind.inverse(rest, List.drop(&2, F32, values, 16n))}

# The bind pose of the inverses' mode.
def bind(mode: U32, +values: +List<F32>, +items: +List<U32>, +nodes: +List<JS.Json>, +total: U32) -> +List<Transform>:
  match mode:
    case 1: bind.inverse(items, values)
    case _: bind.world(items, nodes, total)

def bind.ok(mode: U32, +items: +List<U32>, +nodes: +List<JS.Json>, +total: U32) -> Bool:
  match mode:
    case 0: bind.world.ok(items, nodes, total)
    case 1: True{}
    case _: False{}

# model.skeleton of LoadGLTF: empty without a skin.
def skeleton.of(+root: JS.Json, +bin: +List<+List<U32>>, +limit: U32) -> Maybe<Skeleton>:
  +nodes = G.list(root, "nodes")
  +total = G.count(nodes, 0)
  +all = joints(root)
  +made = bones(all, nodes, total, all)
  +ibm = inverses.read(G.has(G.nth(G.list(root, "skins"), 0), "inverseBindMatrices"), root, bin, limit, G.length(all, 0))
  +source = inverses.kind(ibm)
  Bool.pick(Maybe<Skeleton>, G.good(total) && parents.ok(all, nodes, total) && bones.ok(made) && bind.ok(source, all, nodes, total),
    Some{Skeleton{made, bind(source, inverses.list(ibm), all, nodes, total)}}, None{})

def skeleton.file(file: Maybe<Bundle>) -> Maybe<Skeleton>:
  match file:
    case None{}: None{}
    case Some{Bundle{+root, +bin, +limit}}: skeleton.of(root, blocks(U32.to_nat(((limit / 4096) + 1 : U32)), bin), limit)

# The skeleton of a .glb file's bytes.
def skeleton(+bytes: +List<U32>) -> Maybe<Skeleton>:
  skeleton.file(file(bytes))

# -----------------------------------------------------------------------------
# Animation channels

# A sampler's keys for one path of a bone: present False for none. Its own
# interpolation (0 LINEAR, 1 STEP, 2 CUBICSPLINE: raylib 6.2 reads each
# channel's sampler); times are the input accessor's floats, values the
# output's (width floats an element).
type Track is Data:
  Track{present: Bool, ok: Bool, interpolation: U32, times: +List<F32>, values: +List<F32>, count: U32}

def track.none() -> Track:
  Track{False{}, True{}, 0, Nil{}, Nil{}, 0}

# A bone's channels.
type Tracks is Data:
  Tracks{translate: Track, rotate: Track, scale: Track}

def span.count(span: G.Span) -> U32:
  G.Span{_, _, _, count} = span
  count

def interpolation(+sampler: JS.Json) -> U32:
  +text = G.text.of(JS.get(sampler, T.bytes("interpolation")))
  Bool.pick(U32, JS.same(text, T.bytes("STEP")), 1, Bool.pick(U32, JS.same(text, T.bytes("CUBICSPLINE")), 2, 0))

# The sampler's input (float scalars, at least one) and output (float
# elements of the path's width).
def track(+sampler: JS.Json, +root: JS.Json, +bin: +List<+List<U32>>, +limit: U32, +width: U32, kind: String) -> Track:
  +input = G.span(root, G.int(sampler, "input", G.bad()), 5126, "SCALAR", 4, 1, limit)
  +output = G.span(root, G.int(sampler, "output", G.bad()), 5126, kind, 4, width, limit)
  +valid = G.span.ok(input) && G.span.ok(output) && (span.count(input) >= 1 : U32)
  Track{True{}, valid, interpolation(sampler), G.words.floats(read(valid, input, bin, 1, limit)), G.words.floats(read(valid, output, bin, width, limit)), span.count(output)}

# 1 translation, 2 rotation, 3 scale, 0 another path (ignored with a warning).
def path(+target: JS.Json) -> U32:
  +text = G.text.of(JS.get(target, T.bytes("path")))
  Bool.pick(U32, JS.same(text, T.bytes("translation")), 1, Bool.pick(U32, JS.same(text, T.bytes("rotation")), 2, Bool.pick(U32, JS.same(text, T.bytes("scale")), 3, 0)))

def tracks.with(+tracks: Tracks, +kind: U32, +track: Track) -> Tracks:
  Tracks{+translate, +rotate, +scale} = tracks
  Tracks{Bool.pick(Track, U32.is_eq(kind, 1), track, translate), Bool.pick(Track, U32.is_eq(kind, 2), track, rotate), Bool.pick(Track, U32.is_eq(kind, 3), track, scale)}

# One channel into the bones' tracks: the bone at `index` takes it.
def tracks.put(all: +List<Tracks>, +index: U32, +kind: U32, +track: Track) -> +List<Tracks>:
  match all:
    case Nil{}: Nil{}
    case Con{+tracks, +rest}: Bool.pick(+List<Tracks>, U32.is_eq(index, 0), Con{tracks.with(tracks, kind, track), rest}, Con{tracks, tracks.put(rest, (index - 1 : U32), kind, track)})

def track.for(kind: U32, +sampler: JS.Json, +root: JS.Json, +bin: +List<+List<U32>>, +limit: U32) -> Track:
  match kind:
    case 1: track(sampler, root, bin, limit, 3, "VEC3")
    case 2: track(sampler, root, bin, limit, 4, "VEC4")
    case 3: track(sampler, root, bin, limit, 3, "VEC3")
    case _: track.none()

# The channels in order: one for a node outside the skeleton is skipped, a
# later one for the same bone and path replaces an earlier one.
def channels(items: +List<JS.Json>, +samplers: +List<JS.Json>, +joints: +List<U32>, +root: JS.Json, +bin: +List<+List<U32>>, +limit: U32, +all: +List<Tracks>) -> +List<Tracks>:
  match items:
    case Nil{}: all
    case Con{+channel, rest}:
      +bone = find(joints, G.int(G.child(channel, "target"), "node", G.bad()), 0)
      +sampler = G.nth(samplers, G.int(channel, "sampler", G.bad()))
      channels(rest, samplers, joints, root, bin, limit, Bool.pick(+List<Tracks>, U32.is_eq(bone, none()), all,
        tracks.put(all, bone, path(G.child(channel, "target")), track.for(path(G.child(channel, "target")), sampler, root, bin, limit))))

def last(values: +List<F32>, +fallback: F32) -> F32:
  match values:
    case Nil{}: fallback
    case Con{+value, rest}: last(rest, value)

# animDuration: the largest last input time over the channels of bones in
# the skeleton, whatever their path. ok: every such input is a float
# accessor with a key.
type Length is Data:
  Length{ok: Bool, duration: F32}

def duration(items: +List<JS.Json>, +samplers: +List<JS.Json>, +joints: +List<U32>, +root: JS.Json, +bin: +List<+List<U32>>, +limit: U32, +ok: Bool, +longest: F32) -> Length:
  match items:
    case Nil{}: Length{ok, longest}
    case Con{+channel, rest}:
      +bone = find(joints, G.int(G.child(channel, "target"), "node", G.bad()), 0)
      +input = G.span(root, G.int(G.nth(samplers, G.int(channel, "sampler", G.bad())), "input", G.bad()), 5126, "SCALAR", 4, 1, limit)
      +valid = G.span.ok(input) && (span.count(input) >= 1 : U32)
      +time = last(G.words.floats(read(valid, input, bin, 1, limit)), 0.0)
      duration(rest, samplers, joints, root, bin, limit, ok && (U32.is_eq(bone, none()) || valid), Bool.pick(F32, Bool.not(U32.is_eq(bone, none())) && (time > longest : F32), time, longest))

# -----------------------------------------------------------------------------
# GetPoseAtTimeGLTF

def f(values: +List<F32>) -> F32:
  match values:
    case Con{value, _}: value
    case Nil{}: 0.0

# The key a time falls in and its pair's times.
type Key is Data:
  Knot{index: U32, start: F32, end: F32}

def key.count(values: +List<F32>, +acc: U32) -> U32:
  match values:
    case Nil{}: acc
    case Con{_, rest}: key.count(rest, (acc + 1 : U32))

# The search: the first i with times[i] <= time < times[i + 1], or -1.
def key.search(times: +List<F32>, +time: F32, +index: U32) -> U32:
  match times:
    case Con{+a, Con{+b, +rest}}: Bool.pick(U32, (a <= time : F32) && (time < b : F32), index, key.search(Con{b, rest}, time, (index + 1 : U32)))
    case _: none()

# Without a pair that holds the time (raylib 6.2): the last pair (count -
# 2), or the first when the time is before the first key.
def key.chosen(+found: U32, +before: Bool, +count: U32) -> U32:
  Bool.pick(U32, U32.is_ne(found, none()), found, Bool.pick(U32, before, 0, (count - 2 : U32)))

# Key i with tstart = times[i] and tend = times[i + 1].
def key.at(times: +List<F32>, +index: U32) -> Key:
  +at = List.drop(&2, F32, times, U32.to_nat(index))
  Knot{index, f(at), f(List.drop(&2, F32, at, 1n))}

# The key a time falls in: with two keys or more, the search's, else the
# last pair (so t clamps to 1), or the first pair before the first key
# (t clamps to 0). Fewer than two keys: key 0 with both times 0 (the
# constant pose).
def key(times: +List<F32>, +time: F32) -> Key:
  match times:
    case Con{+a, Con{+b, +rest}}: key.at(Con{a, Con{b, rest}}, key.chosen(key.search(Con{a, Con{b, rest}}, time, 0), (time < a : F32), key.count(rest, 2)))
    case _: Knot{0, 0.0, 0.0}

# What a pose reads: 1 the key's element alone (STEP, or a constant
# animation), 0 the key's and the next one's (LINEAR), 2 CUBICSPLINE.
def mode(+interpolation: U32, +key: Key) -> U32:
  Knot{_, +start, +end} = key
  Bool.pick(U32, M.Math.float_equals(end, start), 1, interpolation)

# t = clamp((time - tstart)/fmaxf(tend - tstart, EPSILON), 0, 1).
def amount(+key: Key, +time: F32) -> F32:
  Knot{_, +start, +end} = key
  +span = (end - start : F32)
  +raw = ((time - start) / Bool.pick(F32, (span > 0.000001 : F32), span, 0.000001) : F32)
  Bool.pick(F32, (raw < 0.0 : F32), 0.0, Bool.pick(F32, (raw > 1.0 : F32), 1.0, raw))

def v3(+values: +List<F32>, +index: U32) -> M.Vector3:
  +at = List.drop(&2, F32, values, U32.to_nat((3 * index : U32)))
  M.Vector3{f(at), f(List.drop(&2, F32, at, 1n)), f(List.drop(&2, F32, at, 2n))}

def v4(+values: +List<F32>, +index: U32) -> M.Vector4:
  +at = List.drop(&2, F32, values, U32.to_nat((4 * index : U32)))
  M.Vector4{f(at), f(List.drop(&2, F32, at, 1n)), f(List.drop(&2, F32, at, 2n)), f(List.drop(&2, F32, at, 3n))}

def key.index(key: Key) -> U32:
  Knot{index, _, _} = key
  index

# Whether the pose's reads stay inside the output accessor, for STEP and LINEAR.
def reads.ok(+track: Track, +time: F32) -> Bool:
  Track{_, +ok, +interpolation, +times, _, +count} = track
  +found = key(times, time)
  +kind = mode(interpolation, found)
  ok && U32.is_ne(kind, 2) && ((key.index(found) + Bool.pick(U32, U32.is_eq(kind, 0), 1, 0) : U32) < count : U32)

# A translation or scale at a time: the key's value, or Vector3Lerp to the next one.
def vector(+track: Track, +time: F32) -> M.Vector3:
  Track{_, _, +interpolation, +times, +values, _} = track
  +found = key(times, time)
  Bool.pick(M.Vector3, U32.is_eq(mode(interpolation, found), 1), v3(values, key.index(found)), M.Vector3.lerp(v3(values, key.index(found)), v3(values, (key.index(found) + 1 : U32)), amount(found, time)))

# A rotation at a time: the key's value, or QuaternionSlerp to the next one under the libm profile.
def quaternion(+track: Track, +time: F32, +libm: M.Libm) -> Maybe<M.Vector4>:
  Track{_, _, +interpolation, +times, +values, _} = track
  +found = key(times, time)
  Bool.pick(Maybe<M.Vector4>, U32.is_eq(mode(interpolation, found), 1), Some{v4(values, key.index(found))}, M.Quaternion.slerp_for(libm, v4(values, key.index(found)), v4(values, (key.index(found) + 1 : U32)), amount(found, time)))

# -----------------------------------------------------------------------------
# Joints

def node.vector.of(words: G.Words) -> M.Vector3:
  G.Words{_, +v} = words
  v3(G.words.floats(v), 0)

def node.vector(+node: JS.Json, name: String, +fallback: U32) -> M.Vector3:
  +words = G.floats.of(JS.get(node, T.bytes(name)), 3, [fallback, fallback, fallback])
  node.vector.of(words)

def node.rotation.of(words: G.Words) -> M.Vector4:
  G.Words{_, +v} = words
  v4(G.words.floats(v), 0)

def words.ok(words: G.Words) -> Bool:
  G.Words{ok, _} = words
  ok

# The node's own translation, rotation and scale read.
def node.ok(+node: JS.Json) -> Bool:
  words.ok(G.floats.of(JS.get(node, T.bytes("translation")), 3, [0, 0, 0])) && words.ok(G.floats.of(JS.get(node, T.bytes("rotation")), 4, [0, 0, 0, G.one()])) &&
    words.ok(G.floats.of(JS.get(node, T.bytes("scale")), 3, [G.one(), G.one(), G.one()]))

# MatrixMultiply(MatrixMultiply(MatrixScale(scale), QuaternionToMatrix(rotation)), MatrixTranslate(translation)).
def composed(translation: M.Vector3, rotation: M.Vector4, scale: M.Vector3) -> M.Matrix:
  M.Vector3{+tx, +ty, +tz} = translation
  M.Vector4{+qx, +qy, +qz, +qw} = rotation
  M.Vector3{+sx, +sy, +sz} = scale
  M.Matrix.multiply(M.Matrix.multiply(M.Matrix.scale(sx, sy, sz), M.Quaternion.to_matrix(M.Vector4{qx, qy, qz, qw})), M.Matrix.translate(tx, ty, tz))

# A joint's node translation, rotation and scale as the file writes them
# (the pose of a bone without channels), read once for every keyframe, and
# the joint's extOffset (the identity for a node that is not a joint). ok:
# the three read and the offset could be made.
type Rest is Data:
  Rest{ok: Bool, translation: M.Vector3, rotation: M.Vector4, scale: M.Vector3, offset: M.Matrix}

def rest.of(+node: JS.Json) -> Rest:
  Rest{node.ok(node), node.vector(node, "translation", 0), node.rotation.of(G.floats.of(JS.get(node, T.bytes("rotation")), 4, [0, 0, 0, G.one()])), node.vector(node, "scale", G.one()), M.Matrix.identity()}

def rest.ok(base: Rest) -> Bool:
  Rest{ok, _, _, _, _} = base
  ok

# The node's own transform, scale then rotation then translation.
def rest.matrix(base: Rest) -> M.Matrix:
  Rest{_, +translation, +rotation, +scale, _} = base
  composed(translation, rotation, scale)

# extOffset (raylib 6.2's LoadModelAnimationsGLTF): the identity times each
# node from a joint's parent up to its nearest joint ancestor (or the root),
# in that order. ok: every such node's numbers read, no node with two
# parents, and an end to the walk.
type Offset is Data:
  Offset{ok: Bool, matrix: M.Matrix}

def offset.step(acc: Offset, +base: Rest, +up: U32) -> Offset:
  Offset{+ok, +matrix} = acc
  Offset{ok && rest.ok(base) && G.good(up), M.Matrix.multiply(matrix, rest.matrix(base))}

# more: `at` is a node that is not a joint, multiplied in before the walk
# goes on to its parent.
def offset.walk(n: Nat, +nodes: +List<JS.Json>, +total: U32, +all: +List<U32>, +at: U32, +acc: Offset, more: Bool) -> Offset:
  match n more:
    case 1n+p True{}:
      +base = rest.of(G.nth(nodes, at))
      +up = G.parent(nodes, at, 0, total, total)
      offset.walk(p, nodes, total, all, up, offset.step(acc, base, up), (up < total : U32) && U32.is_eq(find(all, up, 0), none()))
    case _ True{}: Offset{False{}, M.Matrix.identity()}
    case _ False{}: acc

def offset.of(+nodes: +List<JS.Json>, +total: U32, +all: +List<U32>, +joint: U32) -> Offset:
  +up = G.parent(nodes, joint, 0, total, total)
  offset.walk(U32.to_nat((total + 1 : U32)), nodes, total, all, up, Offset{G.good(up), M.Matrix.identity()}, (up < total : U32) && U32.is_eq(find(all, up, 0), none()))

def rest.placed(base: Rest, outer: Offset) -> Rest:
  Rest{+ok, +translation, +rotation, +scale, _} = base
  Offset{+good, +matrix} = outer
  Rest{ok && good, translation, rotation, scale, matrix}

# Every joint's node transform and extOffset, once for the file.
def rests(items: +List<U32>, +nodes: +List<JS.Json>, +total: U32, +all: +List<U32>) -> +List<Rest>:
  match items:
    case Nil{}: Nil{}
    case Con{+joint, more}: Con{rest.placed(rest.of(G.nth(nodes, joint)), offset.of(nodes, total, all, joint)), rests(more, nodes, total, all)}

def rests.ok(items: +List<Rest>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+base, more}: rest.ok(base) && rests.ok(more)

# -----------------------------------------------------------------------------
# Poses

# The transforms made so far, and whether every one could be.
type Posed is Data:
  Posed{ok: Bool, pose: +List<Transform>}

def track.present(track: Track) -> Bool:
  Track{present, _, _, _, _, _} = track
  present

# The joint's local transform composed, under its extOffset, and decomposed
# again (raylib 6.2): MatrixDecompose(MatrixMultiply(jointLocal, extOffset)).
def rotated.with(rotation: M.Vector4, translation: M.Vector3, scale: M.Vector3, outer: M.Matrix, rest: Posed) -> Posed:
  Posed{ok, pose} = rest
  Posed{ok, Con{transform.of(M.Matrix.decompose(M.Matrix.multiply(composed(translation, rotation, scale), outer))), pose}}

def rotated(rotation: Maybe<M.Vector4>, +translation: M.Vector3, +scale: M.Vector3, +outer: M.Matrix, +rest: Posed) -> Posed:
  match rotation:
    case None{}: Posed{False{}, Nil{}}
    case Some{r}: rotated.with(r, translation, scale, outer, rest)

def bone.posed(valid: Bool, base: Rest, +tracks: Tracks, +time: F32, +libm: M.Libm, +rest: Posed) -> Posed:
  match valid:
    case False{}: Posed{False{}, Nil{}}
    case True{}:
      Rest{_, +translation, +rotation, +size, +outer} = base
      Tracks{+translate, +rotate, +scale} = tracks
      rotated(Bool.pick(Maybe<M.Vector4>, track.present(rotate), quaternion(rotate, time, libm), Some{rotation}),
        Bool.pick(M.Vector3, track.present(translate), vector(translate, time), translation),
        Bool.pick(M.Vector3, track.present(scale), vector(scale, time), size), outer, rest)

# One bone at a time: the node's translation, rotation and scale, each
# replaced by its channel's pose when the bone has one.
def bone.pose(+base: Rest, +tracks: Tracks, +time: F32, +libm: M.Libm, +rest: Posed) -> Posed:
  Tracks{+translate, +rotate, +scale} = tracks
  +valid = rest.ok(base) && (Bool.not(track.present(translate)) || reads.ok(translate, time)) && (Bool.not(track.present(rotate)) || reads.ok(rotate, time)) &&
    (Bool.not(track.present(scale)) || reads.ok(scale, time))
  bone.posed(valid, base, tracks, time, libm, rest)

# Every bone's pose at a time, before the hierarchy is applied.
def local.pose(bases: +List<Rest>, all: +List<Tracks>, +time: F32, +libm: M.Libm) -> Posed:
  match bases all:
    case Con{+base, rest} Con{+tracks, more}: bone.pose(base, tracks, time, libm, local.pose(rest, more, time, libm))
    case _ _: Posed{True{}, Nil{}}

# A transform under a parent's: the rotation composed, the scale
# multiplied, the translation scaled, rotated and moved.
def under(child: Transform, +parent: Transform) -> Transform:
  Transform{translation, rotation, scale} = child
  Transform{+pt, +pr, +ps} = parent
  Transform{M.Vector3.add(M.Vector3.rotate_by_quaternion(M.Vector3.multiply(translation, ps), pr), pt), M.Quaternion.multiply(pr, rotation), M.Vector3.multiply(scale, ps)}

def nth.transform(items: +List<Transform>, +fallback: Transform) -> Transform:
  match items:
    case Con{item, _}: item
    case Nil{}: fallback

# BuildPoseFromParentJoints: each bone after its parent, in order; a bone
# whose parent comes later is left as it is (a warning), and a bone that is
# its own parent composes with itself. done holds the bones before it,
# last first.
def built(bones: +List<Bone>, items: +List<Transform>, +index: U32, +done: +List<Transform>) -> +List<Transform>:
  match bones items:
    case Con{Bone{_, +parent}, rest} Con{+item, more}:
      +moved = Bool.pick(Transform, U32.is_eq(parent, none()) || (parent > index : U32), item,
        under(item, Bool.pick(Transform, U32.is_eq(parent, index), item, nth.transform(List.drop(&2, Transform, done, U32.to_nat(((index - 1 : U32) - parent : U32))), item))))
      built(rest, more, (index + 1 : U32), Con{moved, done})
    case _ _: List.reverse(&2, Transform, done)

def frame.joined(ok: Bool, rest: Maybe<+List<+List<Transform>>>, +pose: +List<Transform>, +bones: +List<Bone>) -> Maybe<+List<+List<Transform>>>:
  match ok rest:
    case True{} Some{+frames}: Some{Con{built(bones, pose, 0, Nil{}), frames}}
    case _ _: None{}

def frame.built(local: Posed, +bones: +List<Bone>, rest: Maybe<+List<+List<Transform>>>) -> Maybe<+List<+List<Transform>>>:
  Posed{ok, +pose} = local
  frame.joined(ok, rest, pose, bones)

# keyframePoses: frame j at time j/60.
def frames(n: Nat, +index: U32, +bases: +List<Rest>, +all: +List<Tracks>, +bones: +List<Bone>, +libm: M.Libm) -> Maybe<+List<+List<Transform>>>:
  match n:
    case 0n: Some{Nil{}}
    case 1n+p: frame.built(local.pose(bases, all, (U32.to_f32(index) / 60.0 : F32), libm), bones, frames(p, (index + 1 : U32), bases, all, bones, libm))

def blank(items: +List<U32>) -> +List<Tracks>:
  match items:
    case Nil{}: Nil{}
    case Con{_, rest}: Con{Tracks{track.none(), track.none(), track.none()}, blank(rest)}

def animation.made(poses: Maybe<+List<+List<Transform>>>, +name: +List<U32>, +bones: U32, +count: U32) -> Maybe<Animation>:
  match poses:
    case None{}: None{}
    case Some{+frames}: Some{Animation{name, bones, count, frames}}

def animation.timed(span: Length, +item: JS.Json, +samplers: +List<JS.Json>, +joints: +List<U32>, +bases: +List<Rest>, +bones: +List<Bone>, +root: JS.Json, +bin: +List<+List<U32>>, +limit: U32, +libm: M.Libm) -> Maybe<Animation>:
  Length{+ok, +longest} = span
  +scaled = (longest * 60.0 : F32)
  +count = (F32.to_u32(F32.trunc(Bool.pick(F32, (scaled >= 0.0 : F32) && (scaled < 100000.0 : F32), scaled, 0.0))) + 1 : U32)
  Bool.pick(Maybe<Animation>, ok && (scaled >= 0.0 : F32) && (scaled < 100000.0 : F32),
    animation.made(frames(U32.to_nat(count), 0, bases, channels(G.list(item, "channels"), samplers, joints, root, bin, limit, blank(joints)), bones, libm), name(item), G.length(joints, 0), count), None{})

# One animation: its channels, its duration, keyframeCount = (int)(duration*60) + 1 poses (at most 100000 here).
def animation(+item: JS.Json, +joints: +List<U32>, +bases: +List<Rest>, +bones: +List<Bone>, +root: JS.Json, +bin: +List<+List<U32>>, +limit: U32, +libm: M.Libm) -> Maybe<Animation>:
  +samplers = G.list(item, "samplers")
  +span = duration(G.list(item, "channels"), samplers, joints, root, bin, limit, True{}, 0.0)
  animation.timed(span, item, samplers, joints, bases, bones, root, bin, limit, libm)

def animations.joined(first: Maybe<Animation>, rest: Maybe<+List<Animation>>) -> Maybe<+List<Animation>>:
  match first rest:
    case Some{a} Some{b}: Some{Con{a, b}}
    case _ _: None{}

def animations.go(items: +List<JS.Json>, +joints: +List<U32>, +bases: +List<Rest>, +bones: +List<Bone>, +root: JS.Json, +bin: +List<+List<U32>>, +limit: U32, +libm: M.Libm) -> Maybe<+List<Animation>>:
  match items:
    case Nil{}: Some{Nil{}}
    case Con{+item, rest}: animations.joined(animation(item, joints, bases, bones, root, bin, limit, libm), animations.go(rest, joints, bases, bones, root, bin, limit, libm))

def first(items: +List<U32>) -> U32:
  match items:
    case Con{item, _}: item
    case Nil{}: none()

# With a skin: the joints (at least one: RL_MALLOC(0) of the offsets is the
# allocator's), their bones, node transforms and extOffsets (once for the
# file, as the reference precomputes them), and every animation.
def animations.skinned(+root: JS.Json, +bin: +List<+List<U32>>, +limit: U32, +libm: M.Libm) -> Maybe<+List<Animation>>:
  +nodes = G.list(root, "nodes")
  +total = G.count(nodes, 0)
  +all = joints(root)
  +bases = rests(all, nodes, total, all)
  +made = bones(all, nodes, total, all)
  +valid = G.good(total) && U32.is_ne(first(all), none()) && parents.ok(all, nodes, total) && bones.ok(made) && rests.ok(bases)
  Bool.pick(Maybe<+List<Animation>>, valid, animations.go(G.list(root, "animations"), all, bases, made, root, bin, limit, libm), None{})

def animations.file(file: Maybe<Bundle>, +libm: M.Libm) -> Maybe<+List<Animation>>:
  match file:
    case None{}: None{}
    case Some{Bundle{+root, +bin, +limit}}: Bool.pick(Maybe<+List<Animation>>, U32.is_eq(G.count(G.list(root, "skins"), 0), 0), Some{Nil{}}, animations.skinned(root, blocks(U32.to_nat(((limit / 4096) + 1 : U32)), bin), limit, libm))

# LoadModelAnimationsGLTF of a .glb file's bytes: none without a skin.
def animations(+bytes: +List<U32>, +libm: M.Libm) -> Maybe<+List<Animation>>:
  animations.file(file(bytes), libm)
