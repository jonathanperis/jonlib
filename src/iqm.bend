# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.2 rmodels.c LoadIQM and
# LoadModelAnimationsIQM (zlib, LICENSES/raylib.txt) for Inter-Quake Model
# files, version 2: the header and the arrays it points at, copied as the
# loaders copy them. A mesh has its vertices, normals and texcoords (zeros
# without the vertex array), its colors when the file has them, and its
# triangles with their corners reversed, less the mesh's first vertex, as
# unsigned shorts; the blend indexes and weights are read and not kept
# (Jonlib's Mesh has no bone data). The skeleton is the joints with
# BuildPoseFromParentJoints (src/gltf_anim.bend). An animation's keyframes
# are each pose's ten channels (the offset, plus the frame's next unsigned
# short times the scale where the mask says so), the rotation normalized,
# then composed along the parents in the bones' order, in place, as the
# loader does (a parent that comes later is taken as read; a pose that is
# its own parent composes with what it has become). F32 arithmetic in the
# loaders' order, uncontracted.
#
# Refused (the loaders read outside the file or their arrays, or leave the
# result to the allocator): an array, a name's 32 bytes or a mesh's range of
# vertices or triangles outside what the file holds; a material, bone or
# animation name without its NUL in 32 bytes; a mesh without vertices or
# triangles; a material name that starts with a slash; frame data that ends
# early; a pose whose parent is not a pose. An empty material name loads no
# texture (raylib 6.2 asks for one only when TextLength(material) > 0). The
# profile ends at files of 2 MiB, 65535 frames or channels and 262144 poses
# in an animation's keyframes. See docs/MODELS.md.
import Base
import ./../jonmath.bend as M
import ./gltf_anim.bend as GA

# A mesh: its material's name (the texture LoadIQM asks for, none when
# empty), vertexCount, triangleCount, the attributes and the indices.
type Part is Data:
  Part{material: +List<U32>, vertex_count: U32, triangle_count: U32, vertices: +List<F32>, normals: +List<F32>, texcoords: +List<F32>, colors: Maybe<&2, +List<U32>>, indices: +List<U32>}

# Unread: refused. Foreign: another magic or version (the empty model).
type Loaded is Data:
  Unread{}
  Foreign{}
  Model{parts: +List<Part>, skeleton: GA.Skeleton}

# Unanimated: refused. A file with another magic or version has no animations.
type Animated is Data:
  Unanimated{}
  Animations{items: +List<GA.Animation>}

type Words is Data:
  Words{ok: Bool, values: +List<U32>}

# The header's counts and offsets.
type Head is Data:
  Head{size: U32, text: U32, meshes: U32, at_meshes: U32, arrays: U32, vertexes: U32, at_arrays: U32, triangles: U32, at_triangles: U32, joints: U32, at_joints: U32, poses: U32, at_poses: U32,
    anims: U32, at_anims: U32, frames: U32, channels: U32, at_frames: U32}

# The vertex arrays read: ok (each inside the file), any (one of the kinds the loader copies), and their words.
type Arrays is Data:
  Arrays{ok: Bool, any: Bool, positions: Maybe<&2, +List<U32>>, normals: Maybe<&2, +List<U32>>, texcoords: Maybe<&2, +List<U32>>, colors: Maybe<&2, +List<U32>>}

type Named is Data:
  Named{ok: Bool, name: +List<U32>}

# A channel of a pose: its offset, its scale and whether the frame data has a value for it.
type Channel is Data:
  Channel{offset: F32, scale: F32, masked: Bool}

type Values is Data:
  Values{ok: Bool, values: +List<F32>}

type Meshed is Data:
  Meshed{ok: Bool, parts: +List<Part>}

type Boned is Data:
  Boned{ok: Bool, bones: +List<GA.Bone>, bind: +List<GA.Transform>}

type Listed is Data:
  Listed{ok: Bool, items: +List<GA.Animation>}

type Cut is Data:
  Cut{head: +List<GA.Transform>, rest: +List<GA.Transform>}

def Words.values(w: Words) -> +List<U32>:
  Words{_, values} = w
  values

def Values.ok(v: Values) -> Bool:
  Values{ok, _} = v
  ok

def Values.values(v: Values) -> +List<F32>:
  Values{_, values} = v
  values

def Named.ok(n: Named) -> Bool:
  Named{ok, _} = n
  ok

def Named.name(n: Named) -> +List<U32>:
  Named{_, name} = n
  name

def Arrays.ok(a: Arrays) -> Bool:
  Arrays{ok, _, _, _, _, _} = a
  ok

def Arrays.any(a: Arrays) -> Bool:
  Arrays{_, any, _, _, _, _} = a
  any

def Meshed.ok(m: Meshed) -> Bool:
  Meshed{ok, _} = m
  ok

def Meshed.parts(m: Meshed) -> +List<Part>:
  Meshed{_, parts} = m
  parts

def Boned.ok(b: Boned) -> Bool:
  Boned{ok, _, _} = b
  ok

def Head.size(h: Head) -> U32:
  Head{size, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = h
  size

def Head.text(h: Head) -> U32:
  Head{_, text, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = h
  text

def Head.vertexes(h: Head) -> U32:
  Head{_, _, _, _, _, vertexes, _, _, _, _, _, _, _, _, _, _, _, _} = h
  vertexes

def Head.triangles(h: Head) -> U32:
  Head{_, _, _, _, _, _, _, triangles, _, _, _, _, _, _, _, _, _, _} = h
  triangles

def Head.poses(h: Head) -> U32:
  Head{_, _, _, _, _, _, _, _, _, _, _, poses, _, _, _, _, _, _} = h
  poses

def Head.channels(h: Head) -> U32:
  Head{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, channels, _} = h
  channels

def turned(values: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: turned(rest, Con{v, acc})

def turned.f(values: +List<F32>, acc: +List<F32>) -> +List<F32>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: turned.f(rest, Con{v, acc})

def length(values: +List<U32>, +acc: U32) -> U32:
  match values:
    case Nil{}: acc
    case Con{_, rest}: length(rest, (acc + 1 : U32))

def float(+word: U32) -> F32:
  U32{bits} = word
  F32{bits}

def first(values: +List<U32>) -> U32:
  match values:
    case Nil{}: 0
    case Con{+v, _}: v

def nth(+values: +List<U32>, +index: U32) -> U32:
  first(List.drop(&2, U32, values, U32.to_nat(index)))

# The bytes from an offset inside the file.
def at(+bytes: +List<U32>, +offset: U32) -> +List<U32>:
  List.drop(&2, U32, bytes, U32.to_nat(U32.min(offset, 2097152)))

# n little-endian unsigned ints.
def words(n: Nat, bytes: +List<U32>, +acc: +List<U32>) -> Words:
  match n bytes:
    case 0n _: Words{True{}, turned(acc, Nil{})}
    case 1n+k Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}: words(k, rest, Con{(a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32), acc})
    case 1n+_ _: Words{False{}, Nil{}}

# n little-endian unsigned shorts.
def shorts(n: Nat, bytes: +List<U32>, +acc: +List<U32>) -> Words:
  match n bytes:
    case 0n _: Words{True{}, turned(acc, Nil{})}
    case 1n+k Con{+a, Con{+b, rest}}: shorts(k, rest, Con{(a .|. (b << 8n) : U32), acc})
    case 1n+_ _: Words{False{}, Nil{}}

def taken(n: Nat, values: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match n values:
    case 1n+k Con{+v, rest}: taken(k, rest, Con{v, acc})
    case _ _: turned(acc, Nil{})

def floats(n: Nat, values: +List<U32>, +acc: +List<F32>) -> +List<F32>:
  match n values:
    case 1n+k Con{+v, rest}: floats(k, rest, Con{float(v), acc})
    case _ _: turned.f(acc, Nil{})

def zeros(n: Nat, +acc: +List<F32>) -> +List<F32>:
  match n:
    case 0n: acc
    case 1n+k: zeros(k, Con{0.0, acc})

# Whether count elements of `each` bytes from offset lie inside a file of `size` bytes.
def inside(+offset: U32, +count: U32, +each: U32, +size: U32) -> Bool:
  (count <= 2097152 : U32) && (offset <= size : U32) && ((count * each) <= (size - offset) : U32)

# The 32 bytes memcpy takes at ofs_text + name lie inside the file.
def held(+text: U32, +name: U32, +size: U32) -> Bool:
  (text <= size : U32) && (name <= size : U32) && inside((text + name : U32), 32, 1, size)

def named.go(n: Nat, bytes: +List<U32>, +acc: +List<U32>) -> Named:
  match n bytes:
    case 1n+k Con{+b, rest}: Bool.pick(Named, U32.is_eq(b, 0), Named{True{}, turned(acc, Nil{})}, named.go(k, rest, Con{b, acc}))
    case _ _: Named{False{}, Nil{}}

# A name: its bytes before the NUL, which must be among the 32 copied.
def named(+bytes: +List<U32>, +text: U32, +name: U32, +size: U32) -> Named:
  Bool.pick(Named, held(text, name, size), named.go(32n, at(bytes, (text + name : U32)), Nil{}), Named{False{}, Nil{}})

def head.of(+h: +List<U32>, +size: U32) -> Head:
  Head{size, nth(h, 4), nth(h, 5), nth(h, 6), nth(h, 7), nth(h, 8), nth(h, 9), nth(h, 10), nth(h, 11), nth(h, 13), nth(h, 14), nth(h, 15), nth(h, 16), nth(h, 17), nth(h, 18), nth(h, 19), nth(h, 20), nth(h, 21)}

def same(bytes: +List<U32>, expected: +List<U32>) -> Bool:
  match bytes expected:
    case _ Nil{}: True{}
    case Con{+b, rest} Con{+e, more}: U32.is_eq(b, e) && same(rest, more)
    case Nil{} Con{_, _}: False{}

# memcmp(magic, "INTERQUAKEMODEL", 16) and the version of a file with bytes.
def kind.read(+bytes: +List<U32>, +size: U32) -> U32:
  Bool.pick(U32, (size < 16 : U32) || (size > 2097152 : U32), 0, Bool.pick(U32, Bool.not(same(bytes, [73, 78, 84, 69, 82, 81, 85, 65, 75, 69, 77, 79, 68, 69, 76, 0])), 1,
    Bool.pick(U32, (size < 20 : U32), 0, Bool.pick(U32, U32.is_ne(first(Words.values(words(1n, at(bytes, 16), Nil{}))), 2), 1, Bool.pick(U32, (size < 124 : U32), 0, 2)))))

# memcmp(magic, "INTERQUAKEMODEL", 16) and the version: 0 a file of fewer
# bytes than the loader reads (or over the profile's 2 MiB), 1 another magic
# or version, or an empty file (LoadFileData gives none), 2 a version 2 file
# with its whole header.
def kind(+bytes: +List<U32>, +size: U32) -> U32:
  Bool.pick(U32, U32.is_eq(size, 0), 1, kind.read(bytes, size))

# One vertex array: positions (0), texcoords (1) and normals (2) as floats,
# blend indexes (4) and weights (5) read and left, colors (6) as bytes; the
# other kinds are not read.
def array(+offset: U32, +bytes: +List<U32>, +vertexes: U32, +size: U32, +acc: Arrays, kind: U32) -> Arrays:
  Arrays{+ok, +any, +positions, +normals, +texcoords, +colors} = acc
  match kind:
    case 0: Arrays{ok && inside(offset, (vertexes * 3 : U32), 4, size), True{}, Some{Words.values(words(U32.to_nat((vertexes * 3 : U32)), at(bytes, offset), Nil{}))}, normals, texcoords, colors}
    case 1: Arrays{ok && inside(offset, (vertexes * 2 : U32), 4, size), True{}, positions, normals, Some{Words.values(words(U32.to_nat((vertexes * 2 : U32)), at(bytes, offset), Nil{}))}, colors}
    case 2: Arrays{ok && inside(offset, (vertexes * 3 : U32), 4, size), True{}, positions, Some{Words.values(words(U32.to_nat((vertexes * 3 : U32)), at(bytes, offset), Nil{}))}, texcoords, colors}
    case 4: Arrays{ok && inside(offset, (vertexes * 4 : U32), 1, size), True{}, positions, normals, texcoords, colors}
    case 5: Arrays{ok && inside(offset, (vertexes * 4 : U32), 1, size), True{}, positions, normals, texcoords, colors}
    case 6: Arrays{ok && inside(offset, (vertexes * 4 : U32), 1, size), True{}, positions, normals, texcoords, Some{taken(U32.to_nat((vertexes * 4 : U32)), at(bytes, offset), Nil{})}}
    case _: Arrays{ok, any, positions, normals, texcoords, colors}

# The vertex arrays in the file's order (a later one of a kind replaces the earlier): type, flags, format, size, offset.
def arrays(list: +List<U32>, +bytes: +List<U32>, +vertexes: U32, +size: U32, +acc: Arrays) -> Arrays:
  match list:
    case Con{+code, Con{_, Con{_, Con{_, Con{+offset, rest}}}}}: arrays(rest, bytes, vertexes, size, array(offset, bytes, vertexes, size, acc, code))
    case _: acc

# A mesh's part of an array of floats: `per` a vertex from its first vertex, zeros without the array.
def slice(values: Maybe<&2, +List<U32>>, +from: U32, +count: U32, +per: U32) -> +List<F32>:
  match values:
    case None{}: zeros(U32.to_nat((count * per : U32)), Nil{})
    case Some{+v}: floats(U32.to_nat((count * per : U32)), List.drop(&2, U32, v, U32.to_nat((from * per : U32))), Nil{})

def colored(values: Maybe<&2, +List<U32>>, +from: U32, +count: U32) -> Maybe<&2, +List<U32>>:
  match values:
    case None{}: None{}
    case Some{+v}: Some{taken(U32.to_nat((count * 4 : U32)), List.drop(&2, U32, v, U32.to_nat((from * 4 : U32))), Nil{})}

# indices[t + 2] = vertex[0] - first_vertex, indices[t + 1] = vertex[1] - first_vertex, indices[t] = vertex[2] - first_vertex, as unsigned shorts.
def indices(n: Nat, list: +List<U32>, +base: U32, +acc: +List<U32>) -> +List<U32>:
  match n list:
    case 1n+k Con{+a, Con{+b, Con{+c, rest}}}: indices(k, rest, base, Con{((a - base) .&. 65535 : U32), Con{((b - base) .&. 65535 : U32), Con{((c - base) .&. 65535 : U32), acc}}})
    case _ _: turned(acc, Nil{})

# Whether `count` elements from `from` lie among `total`.
def among(+from: U32, +count: U32, +total: U32) -> Bool:
  (from <= total : U32) && (count <= (total - from) : U32)

def printable(values: +List<U32>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+c, rest}: (c >= 32 : U32) && (c <= 126 : U32) && printable(rest)

# A material's name as the texture's file name: not from the root,
# printable; or empty (raylib 6.2 then loads no texture).
def texture.named(+name: +List<U32>) -> Bool:
  U32.is_ne(first(name), 47) && printable(name)

def mesh.made(ok: Bool, +material: Named, +start: U32, +count: U32, +from: U32, +triangles: U32, +all: +List<U32>, +found: Arrays, +rest: Meshed) -> Meshed:
  match ok:
    case False{}: Meshed{False{}, Nil{}}
    case True{}:
      Named{_, +name} = material
      Arrays{_, _, +positions, +normals, +texcoords, +colors} = found
      Meshed{_, +parts} = rest
      Meshed{True{}, Con{Part{name, count, triangles, slice(positions, start, count, 3), slice(normals, start, count, 3), slice(texcoords, start, count, 2), colored(colors, start, count),
        indices(U32.to_nat(triangles), List.drop(&2, U32, all, U32.to_nat((from * 3 : U32))), start, Nil{})}, parts}}

def mesh.checked(+fits: Bool, +material: Named, +start: U32, +count: U32, +from: U32, +triangles: U32, +all: +List<U32>, +found: Arrays, +rest: Meshed) -> Meshed:
  mesh.made(fits && Named.ok(material) && texture.named(Named.name(material)) && Meshed.ok(rest), material, start, count, from, triangles, all, found, rest)

# The meshes in the file's order: name, material, first_vertex, num_vertexes, first_triangle, num_triangles.
def meshes(list: +List<U32>, +bytes: +List<U32>, +head: Head, +all: +List<U32>, +found: Arrays) -> Meshed:
  match list:
    case Con{+name, Con{+material, Con{+start, Con{+count, Con{+from, Con{+triangles, rest}}}}}}:
      mesh.checked(held(Head.text(head), name, Head.size(head)) && (count > 0 : U32) && (count <= 524288 : U32) && (triangles > 0 : U32) && among(from, triangles, Head.triangles(head)) &&
        (Bool.not(Arrays.any(found)) || among(start, count, Head.vertexes(head))), named(bytes, Head.text(head), material, Head.size(head)), start, count, from, triangles, all, found, meshes(rest, bytes, head, all, found))
    case _: Meshed{True{}, Nil{}}

def joint.made(+name: Named, +parent: U32, +transform: GA.Transform, +rest: Boned) -> Boned:
  Named{+found, +bytes} = name
  Boned{+ok, +bones, +bind} = rest
  Boned{ok && found, Con{GA.Bone{bytes, parent}, bones}, Con{transform, bind}}

# The joints: name, parent, translate[3], rotate[4], scale[3].
def joints(list: +List<U32>, +bytes: +List<U32>, +text: U32, +size: U32) -> Boned:
  match list:
    case Con{+name, Con{+parent, Con{+tx, Con{+ty, Con{+tz, Con{+rx, Con{+ry, Con{+rz, Con{+rw, Con{+sx, Con{+sy, Con{+sz, rest}}}}}}}}}}}}:
      joint.made(named(bytes, text, name, size), parent, GA.Transform{M.Vector3{float(tx), float(ty), float(tz)}, M.Vector4{float(rx), float(ry), float(rz), float(rw)}, M.Vector3{float(sx), float(sy), float(sz)}},
        joints(rest, bytes, text, size))
    case _: Boned{True{}, Nil{}, Nil{}}

# A joint that is its own parent in BuildPoseFromParentJoints: each statement
# reads what the one before wrote (the rotation squared, the scale squared,
# the translation scaled by that scale, turned by that rotation and doubled).
def bound.self.moved(+moved: M.Vector3, +rotation: M.Vector4, +scale: M.Vector3) -> GA.Transform:
  GA.Transform{M.Vector3.add(moved, moved), rotation, scale}

def bound.self.scaled(+translation: M.Vector3, +rotation: M.Vector4, +scale: M.Vector3) -> GA.Transform:
  bound.self.moved(M.Vector3.rotate_by_quaternion(M.Vector3.multiply(translation, scale), rotation), rotation, scale)

def bound.self(+item: GA.Transform) -> GA.Transform:
  GA.Transform{+translation, +rotation, +scale} = item
  bound.self.scaled(translation, M.Quaternion.multiply(rotation, rotation), M.Vector3.multiply(scale, scale))

def bound.pick(items: +List<GA.Transform>, +fallback: GA.Transform) -> GA.Transform:
  match items:
    case Con{+item, _}: item
    case Nil{}: fallback

# BuildPoseFromParentJoints: each joint after its parent, in order; a joint
# whose parent comes later (or is negative) is left as read. done holds the
# joints before it, last first.
def bound(bones: +List<GA.Bone>, items: +List<GA.Transform>, +index: U32, +done: +List<GA.Transform>) -> +List<GA.Transform>:
  match bones items:
    case Con{GA.Bone{_, +parent}, rest} Con{+item, more}:
      bound(rest, more, (index + 1 : U32), Con{Bool.pick(GA.Transform, (parent > index : U32), item, Bool.pick(GA.Transform, U32.is_eq(parent, index), bound.self(item),
        GA.under(item, bound.pick(List.drop(&2, GA.Transform, done, U32.to_nat(U32.min(((index - 1 : U32) - parent : U32), index))), item)))), done})
    case _ _: List.reverse(&2, GA.Transform, done)

# model.skeleton: the bones and BuildPoseFromParentJoints of their bind pose.
def skeleton.of(+boned: Boned) -> GA.Skeleton:
  Boned{_, +bones, +bind} = boned
  GA.Skeleton{bones, bound(bones, bind, 0, Nil{})}

def model.built(+meshed: Meshed, +found: Arrays, +boned: Boned) -> Loaded:
  Bool.pick(Loaded, Meshed.ok(meshed) && Arrays.ok(found) && Boned.ok(boned), Model{Meshed.parts(meshed), skeleton.of(boned)}, Unread{})

def model.arrayed(+bytes: +List<U32>, +head: Head, +found: Arrays) -> Loaded:
  Head{+size, +text, +number, +at_meshes, _, _, _, +corners, +at_triangles, +bones, +at_joints, _, _, _, _, _, _, _} = head
  model.built(meshes(Words.values(words(U32.to_nat((number * 6 : U32)), at(bytes, at_meshes), Nil{})), bytes, head, Words.values(words(U32.to_nat((corners * 3 : U32)), at(bytes, at_triangles), Nil{})), found), found,
    joints(Words.values(words(U32.to_nat((bones * 12 : U32)), at(bytes, at_joints), Nil{})), bytes, text, size))

def model.checked(fits: Bool, +bytes: +List<U32>, +head: Head) -> Loaded:
  match fits:
    case False{}: Unread{}
    case True{}:
      Head{+size, _, _, _, +number, +vertexes, +at_arrays, _, _, _, _, _, _, _, _, _, _, _} = head
      model.arrayed(bytes, head, arrays(Words.values(words(U32.to_nat((number * 5 : U32)), at(bytes, at_arrays), Nil{})), bytes, vertexes, size, Arrays{True{}, False{}, None{}, None{}, None{}, None{}}))

# LoadIQM after the header: the meshes, the triangles, the vertex arrays and the joints, each inside the file.
def model.read(+bytes: +List<U32>, +head: Head) -> Loaded:
  Head{+size, _, +number, +at_meshes, +lists, +vertexes, +at_arrays, +corners, +at_triangles, +bones, +at_joints, _, _, _, _, _, _, _} = head
  model.checked(inside(at_meshes, number, 24, size) && inside(at_triangles, corners, 12, size) && inside(at_arrays, lists, 20, size) && inside(at_joints, bones, 48, size) && (vertexes <= 524288 : U32), bytes, head)

def channels.turned(values: +List<Channel>, acc: +List<Channel>) -> +List<Channel>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: channels.turned(rest, Con{v, acc})

# The ten channels of the poses, pose after pose: parent, mask, channeloffset[10], channelscale[10].
def program(list: +List<U32>, +acc: +List<Channel>) -> +List<Channel>:
  match list:
    case Con{_, Con{+mask, Con{+o0, Con{+o1, Con{+o2, Con{+o3, Con{+o4, Con{+o5, Con{+o6, Con{+o7, Con{+o8, Con{+o9, Con{+s0, Con{+s1, Con{+s2, Con{+s3, Con{+s4, Con{+s5, Con{+s6, Con{+s7, Con{+s8, Con{+s9, rest}}}}}}}}}}}}}}}}}}}}}}:
      program(rest, Con{Channel{float(o9), float(s9), U32.is_ne((mask .&. 512 : U32), 0)}, Con{Channel{float(o8), float(s8), U32.is_ne((mask .&. 256 : U32), 0)},
        Con{Channel{float(o7), float(s7), U32.is_ne((mask .&. 128 : U32), 0)}, Con{Channel{float(o6), float(s6), U32.is_ne((mask .&. 64 : U32), 0)},
        Con{Channel{float(o5), float(s5), U32.is_ne((mask .&. 32 : U32), 0)}, Con{Channel{float(o4), float(s4), U32.is_ne((mask .&. 16 : U32), 0)},
        Con{Channel{float(o3), float(s3), U32.is_ne((mask .&. 8 : U32), 0)}, Con{Channel{float(o2), float(s2), U32.is_ne((mask .&. 4 : U32), 0)},
        Con{Channel{float(o1), float(s1), U32.is_ne((mask .&. 2 : U32), 0)}, Con{Channel{float(o0), float(s0), U32.is_ne((mask .&. 1 : U32), 0)}, acc}}}}}}}}}})
    case _: channels.turned(acc, Nil{})

# The poses' parents.
def parents(list: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match list:
    case Con{+parent, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, rest}}}}}}}}}}}}}}}}}}}}}}: parents(rest, Con{parent, acc})
    case _: turned(acc, Nil{})

# Every parent is a pose or negative (a root).
def parented(list: +List<U32>, +count: U32) -> Bool:
  match list:
    case Nil{}: True{}
    case Con{+parent, rest}: ((parent >= 2147483648 : U32) || (parent < count : U32)) && parented(rest, count)

# A keyframe after another: each channel is its offset, plus the next
# unsigned short of the frame data times its scale where the mask has it.
# The values are kept last first.
def values(fuel: Nat, cursor: +List<Channel>, data: +List<U32>, +all: +List<Channel>, +acc: +List<F32>) -> Values:
  match fuel cursor data:
    case 0n _ _: Values{True{}, acc}
    case 1n+k Con{Channel{+offset, +scale, True{}}, +rest} Con{+d, +more}: values(k, rest, more, all, Con{(offset + U32.to_f32(d) * scale : F32), acc})
    case 1n+_ Con{Channel{_, _, True{}}, _} Nil{}: Values{False{}, Nil{}}
    case 1n+k Con{Channel{+offset, _, False{}}, +rest} Nil{}: values(k, rest, Nil{}, all, Con{offset, acc})
    case 1n+k Con{Channel{+offset, _, False{}}, +rest} Con{+d, +more}: values(k, rest, Con{d, more}, all, Con{offset, acc})
    case 1n+k Nil{} Nil{}: values(k, all, Nil{}, all, acc)
    case 1n+k Nil{} Con{+d, +more}: values(k, all, Con{d, more}, all, acc)

# The values, last first, as transforms in their order: translation, rotation (QuaternionNormalize), scale.
def transforms(list: +List<F32>, +acc: +List<GA.Transform>) -> +List<GA.Transform>:
  match list:
    case Con{+sz, Con{+sy, Con{+sx, Con{+rw, Con{+rz, Con{+ry, Con{+rx, Con{+tz, Con{+ty, Con{+tx, rest}}}}}}}}}}:
      transforms(rest, Con{GA.Transform{M.Vector3{tx, ty, tz}, M.Quaternion.normalize(M.Vector4{rx, ry, rz, rw}), M.Vector3{sx, sy, sz}}, acc})
    case _: acc

def pick(items: +List<GA.Transform>, +fallback: GA.Transform) -> GA.Transform:
  match items:
    case Con{+item, _}: item
    case Nil{}: fallback

# A pose under its parent's, as the loader composes a keyframe: the rotation, the translation rotated and moved, the scale.
def under(+child: GA.Transform, +parent: GA.Transform) -> GA.Transform:
  GA.Transform{+translation, +rotation, +scale} = child
  GA.Transform{+pt, +pr, +ps} = parent
  GA.Transform{M.Vector3.add(M.Vector3.rotate_by_quaternion(translation, pr), pt), M.Quaternion.multiply(pr, rotation), M.Vector3.multiply(scale, ps)}

# A pose that is its own parent: each statement reads what the one before wrote.
def under.self.moved(+moved: M.Vector3, +rotation: M.Vector4, +scale: M.Vector3) -> GA.Transform:
  GA.Transform{M.Vector3.add(moved, moved), rotation, M.Vector3.multiply(scale, scale)}

def under.self.turned(+translation: M.Vector3, +rotation: M.Vector4, +scale: M.Vector3) -> GA.Transform:
  under.self.moved(M.Vector3.rotate_by_quaternion(translation, rotation), rotation, scale)

def under.self(+item: GA.Transform) -> GA.Transform:
  GA.Transform{+translation, +rotation, +scale} = item
  under.self.turned(translation, M.Quaternion.multiply(rotation, rotation), scale)

# Build frameposes: the bones in order; a parent before the bone is taken
# composed (done, last first), one after it as read.
def composed(list: +List<U32>, raw: +List<GA.Transform>, +index: U32, +count: U32, +done: +List<GA.Transform>) -> +List<GA.Transform>:
  match list raw:
    case Con{+parent, rest} Con{+item, +more}:
      +above = Bool.pick(GA.Transform, (parent < index : U32), pick(List.drop(&2, GA.Transform, done, U32.to_nat(U32.min(((index - 1 : U32) - parent : U32), count))), item),
        pick(List.drop(&2, GA.Transform, more, U32.to_nat(U32.min(((parent - index : U32) - 1 : U32), count))), item))
      composed(rest, more, (index + 1 : U32), count, Con{Bool.pick(GA.Transform, (parent >= 2147483648 : U32), item, Bool.pick(GA.Transform, U32.is_eq(parent, index), under.self(item), under(item, above))), done})
    case _ _: List.reverse(&2, GA.Transform, done)

def cut(n: Nat, src: +List<GA.Transform>, +acc: +List<GA.Transform>) -> Cut:
  match n src:
    case 1n+k Con{+v, rest}: cut(k, rest, Con{v, acc})
    case 0n Nil{}: Cut{List.reverse(&2, GA.Transform, acc), Nil{}}
    case 0n Con{+v, +rest}: Cut{List.reverse(&2, GA.Transform, acc), Con{v, rest}}
    case 1n+_ Nil{}: Cut{List.reverse(&2, GA.Transform, acc), Nil{}}

def frames.turned(values: +List<+List<GA.Transform>>, acc: +List<+List<GA.Transform>>) -> +List<+List<GA.Transform>>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: frames.turned(rest, Con{v, acc})

# The keyframes: `count` transforms each, composed.
def frames(n: Nat, c: Cut, +count: U32, +list: +List<U32>, +acc: +List<+List<GA.Transform>>) -> +List<+List<GA.Transform>>:
  match n c:
    case 0n _: frames.turned(acc, Nil{})
    case 1n+k Cut{+head, +rest}: frames(k, cut(U32.to_nat(count), rest, Nil{}), count, list, Con{composed(list, head, 0, count, Nil{}), acc})

def anim.framed(+name: Named, +fine: Bool, +poses: U32, +count: U32, +list: +List<+List<GA.Transform>>, +rest: Listed) -> Listed:
  Named{+found, +bytes} = name
  Listed{+ok, +items} = rest
  Listed{ok && found && fine, Con{GA.Animation{bytes, poses, count, list}, items}}

def anim.valued(+read: Values, +name: Named, +poses: U32, +count: U32, +list: +List<U32>, +rest: Listed) -> Listed:
  anim.framed(name, Values.ok(read), poses, count, frames(U32.to_nat(count), cut(U32.to_nat(poses), transforms(Values.values(read), Nil{}), Nil{}), poses, list, Nil{}), rest)

# One animation: its keyframes from first_frame*num_framechannels in the frame data.
def anim.read(valid: Bool, +name: Named, +start: U32, +count: U32, +poses: U32, +channels: U32, +data: +List<U32>, +all: +List<Channel>, +list: +List<U32>, +rest: Listed) -> Listed:
  match valid:
    case False{}: Listed{False{}, Nil{}}
    case True{}: anim.valued(values(U32.to_nat((count * (poses * 10 + 1) : U32)), all, List.drop(&2, U32, data, U32.to_nat(U32.min((start * channels : U32), 1048576))), all, Nil{}), name, poses, count, list, rest)

# The animations in the file's order: name, first_frame, num_frames, framerate, flags.
def anims(list: +List<U32>, +bytes: +List<U32>, +head: Head, +data: +List<U32>, +all: +List<Channel>, +above: +List<U32>) -> Listed:
  match list:
    case Con{+name, Con{+start, Con{+count, Con{_, Con{_, rest}}}}}:
      anim.read((start <= 65535 : U32) && (count <= 65535 : U32) && ((count * Head.poses(head)) <= 262144 : U32), named(bytes, Head.text(head), name, Head.size(head)), start, count, Head.poses(head), Head.channels(head),
        data, all, above, anims(rest, bytes, head, data, all, above))
    case _: Listed{True{}, Nil{}}

def listed(+fine: Bool, +found: Listed) -> Animated:
  Listed{+ok, +items} = found
  Bool.pick(Animated, ok && fine, Animations{items}, Unanimated{})

def animated.posed(+bytes: +List<U32>, +head: Head, +posed: +List<U32>) -> Animated:
  Head{_, _, _, _, _, _, _, _, _, _, _, +poses, _, +count, +at_anims, +total, +channels, +at_frames} = head
  listed(parented(parents(posed, Nil{}), poses), anims(Words.values(words(U32.to_nat((count * 5 : U32)), at(bytes, at_anims), Nil{})), bytes, head, Words.values(shorts(U32.to_nat((total * channels : U32)), at(bytes, at_frames), Nil{})),
    program(posed, Nil{}), parents(posed, Nil{})))

def animated.checked(fits: Bool, +bytes: +List<U32>, +head: Head) -> Animated:
  match fits:
    case False{}: Unanimated{}
    case True{}:
      Head{_, _, _, _, _, _, _, _, _, _, _, +poses, +at_poses, _, _, _, _, _} = head
      animated.posed(bytes, head, Words.values(words(U32.to_nat((poses * 22 : U32)), at(bytes, at_poses), Nil{})))

# LoadModelAnimationsIQM after the header: the poses, the animations, the frame data and the joints, each inside the file.
def animated.read(+bytes: +List<U32>, +head: Head) -> Animated:
  Head{+size, _, _, _, _, _, _, _, _, +bones, +at_joints, +poses, +at_poses, +count, +at_anims, +total, +channels, +at_frames} = head
  animated.checked(inside(at_poses, poses, 88, size) && inside(at_anims, count, 20, size) && (total <= 65535 : U32) && (channels <= 65535 : U32) && ((total * channels) <= 1048576 : U32) &&
    inside(at_frames, (total * channels : U32), 2, size) && inside(at_joints, bones, 48, size) && (poses <= 4096 : U32), bytes, head)

def header(+bytes: +List<U32>, +size: U32) -> Head:
  head.of(Words.values(words(27n, at(bytes, 16), Nil{})), size)

def model.kind(code: U32, +bytes: +List<U32>, +size: U32) -> Loaded:
  match code:
    case 0: Unread{}
    case 1: Foreign{}
    case _: model.read(bytes, header(bytes, size))

def animated.kind(code: U32, +bytes: +List<U32>, +size: U32) -> Animated:
  match code:
    case 0: Unanimated{}
    case 1: Animations{Nil{}}
    case _: animated.read(bytes, header(bytes, size))

def model.sized(+bytes: +List<U32>, +size: U32) -> Loaded:
  model.kind(kind(bytes, size), bytes, size)

def animated.sized(+bytes: +List<U32>, +size: U32) -> Animated:
  animated.kind(kind(bytes, size), bytes, size)

# LoadIQM of a file's bytes (0..255 each): the meshes with their materials' names, and the skeleton.
def model(+bytes: +List<U32>) -> Loaded:
  model.sized(bytes, length(bytes, 0))

# LoadModelAnimationsIQM of a file's bytes.
def animations(+bytes: +List<U32>) -> Animated:
  animated.sized(bytes, length(bytes, 0))
