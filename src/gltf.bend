# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rmodels.c LoadGLTF (zlib,
# LICENSES/raylib.txt) and of what it uses from cgltf 1.15
# (src/external/cgltf.h, MIT, LICENSES/cgltf.txt): the binary container
# (cgltf_parse), the node transforms (cgltf_node_transform_local and
# cgltf_node_transform_world, in their F32 order) and the accessor layout
# (stride, offsets). A first slice of the format: a .glb file with its
# buffer in the BIN chunk, every node's triangle primitives as meshes with
# float POSITION, NORMAL, TANGENT and TEXCOORD_0/1 attributes, indices of 8,
# 16 or 32 bits (kept as 16, as raylib does), node transforms applied to the
# vertices as LoadGLTF applies them, and each material's base color factor
# and base color texture (a PNG image in a buffer view; the caller decodes
# and uploads it). A file with skins loads too: its meshes are what LoadGLTF
# makes of them, and the bone data it would add (JOINTS_n, WEIGHTS_n, the
# skeleton) is checked and not kept, as Jonlib's Mesh and Model have none.
# None (the loader refuses) for everything else the reference would read:
# the other texture kinds, images given by a uri or in another format,
# sparse or missing buffer views, COLOR attributes, other component types,
# required extensions, a number src/strtod.bend does not answer, a read past
# the buffer, or JSON that is not well formed. The arithmetic is
# uncontracted. See docs/MODELS.md.
import Base
import ./../jonmath.bend as M
import ./json.bend as JS
import ./strtod.bend as Strtod
import ./text.bend as T

# An integer that could not be read; every good one is below 2^24.
def bad() -> U32:
  4294967295

def good(+value: U32) -> Bool:
  (value < 16777216 : U32)

def float(+word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# Lists are built reversed and turned once: a file's buffers are long, and
# the JavaScript lane's stack is not.
def turned(values: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: turned(rest, Con{v, acc})

def turned.f(values: +List<F32>, acc: +List<F32>) -> +List<F32>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: turned.f(rest, Con{v, acc})

def take.go(n: Nat, values: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match n values:
    case 1n+p Con{+v, rest}: take.go(p, rest, Con{v, acc})
    case _ _: turned(acc, Nil{})

def take(n: Nat, values: +List<U32>) -> +List<U32>:
  take.go(n, values, Nil{})

def length(values: +List<U32>, +acc: U32) -> U32:
  match values:
    case Nil{}: acc
    case Con{_, rest}: length(rest, (acc + 1 : U32))

def u16(data: +List<U32>) -> U32:
  match data:
    case Con{+a, Con{+b, _}}: (a .|. (b << 8n) : U32)
    case _: 0

def u32(data: +List<U32>) -> U32:
  match data:
    case Con{+a, Con{+b, Con{+c, Con{+d, _}}}}: (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)
    case _: 0

def first(data: +List<U32>) -> U32:
  match data:
    case Con{+a, _}: a
    case Nil{}: 0

# Plain decimal digits, at most eight.
def digits(text: +List<U32>, +acc: U32, +seen: U32) -> U32:
  match text:
    case Nil{}: Bool.pick(U32, (seen >= 1 : U32) && (seen <= 8 : U32), acc, bad())
    case Con{+c, rest}: Bool.pick(U32, (c >= 48 : U32) && (c <= 57 : U32) && (seen < 8 : U32), digits(rest, (acc * 10 + (c - 48) : U32), (seen + 1 : U32)), bad())

# An integer member: the default when absent, bad() when it is not one.
def int.of(value: Maybe<JS.Json>, +default: U32) -> U32:
  match value:
    case None{}: default
    case Some{JS.JNumber{+text}}: digits(text, 0, 0)
    case Some{_}: bad()

def int(+object: JS.Json, name: String, +default: U32) -> U32:
  int.of(JS.get(object, T.bytes(name)), default)

def has.of(value: Maybe<JS.Json>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

def has(+object: JS.Json, name: String) -> Bool:
  has.of(JS.get(object, T.bytes(name)))

# An array member's items: none when absent.
def list.of(value: Maybe<JS.Json>) -> +List<JS.Json>:
  match value:
    case Some{JS.JArray{+items}}: items
    case _: Nil{}

def list(+object: JS.Json, name: String) -> +List<JS.Json>:
  list.of(JS.get(object, T.bytes(name)))

# Absent, or an array.
def listed.of(value: Maybe<JS.Json>) -> Bool:
  match value:
    case None{}: True{}
    case Some{JS.JArray{_}}: True{}
    case Some{_}: False{}

def listed(+object: JS.Json, name: String) -> Bool:
  listed.of(JS.get(object, T.bytes(name)))

def object.of(value: Maybe<JS.Json>) -> JS.Json:
  match value:
    case Some{+v}: v
    case None{}: JS.JNull{}

def child(+object: JS.Json, name: String) -> JS.Json:
  object.of(JS.get(object, T.bytes(name)))

def nth.head(items: +List<JS.Json>) -> JS.Json:
  match items:
    case Con{+item, _}: item
    case Nil{}: JS.JNull{}

def nth(items: +List<JS.Json>, +index: U32) -> JS.Json:
  nth.head(List.drop(&2, JS.Json, items, U32.to_nat(index)))

def count(items: +List<JS.Json>, +acc: U32) -> U32:
  match items:
    case Nil{}: acc
    case Con{_, rest}: count(rest, (acc + 1 : U32))

# The text of a string member, or one byte 0 when it is not a string.
def text.of(value: Maybe<JS.Json>) -> +List<U32>:
  match value:
    case Some{JS.JString{+text}}: text
    case _: [0]

# Numbers as binary32 words through (float)atof; ok is False when one is not answered.
type Words is Data:
  Words{ok: Bool, values: +List<U32>}

def number(value: JS.Json) -> Maybe<U32>:
  match value:
    case JS.JNumber{+text}: Strtod.float(text)
    case _: None{}

def numbers.failed(+rest: Words) -> Words:
  Words{_, +values} = rest
  Words{False{}, values}

def numbers.more(+word: U32, +rest: Words) -> Words:
  Words{+ok, +values} = rest
  Words{ok, Con{word, values}}

def numbers.joined(value: Maybe<U32>, +rest: Words) -> Words:
  match value:
    case None{}: numbers.failed(rest)
    case Some{+word}: numbers.more(word, rest)

def numbers(items: +List<JS.Json>) -> Words:
  match items:
    case Nil{}: Words{True{}, Nil{}}
    case Con{+item, rest}: numbers.joined(number(item), numbers(rest))

def at(values: +List<U32>, +index: U32) -> F32:
  float(first(List.drop(&2, U32, values, U32.to_nat(index))))

def floats.sized(+words: Words, +size: U32) -> Words:
  Words{+ok, +values} = words
  Words{ok && U32.is_eq(U32.from_nat(List.length(&2, U32, values)), size), values}

# A node's numbers: the member's, when it is an array of exactly that many, or the defaults.
def floats.of(value: Maybe<JS.Json>, +size: U32, +default: +List<U32>) -> Words:
  match value:
    case None{}: Words{True{}, default}
    case Some{JS.JArray{+items}}: floats.sized(numbers(items), size)
    case Some{_}: Words{False{}, default}

# cgltf's column-major float[16].
type Lm is Data:
  Lm{ok: Bool, v: +List<F32>}

def lm.value(values: +List<F32>) -> F32:
  match values:
    case Con{v, _}: v
    case Nil{}: 0.0

def lm.get(+lm: +List<F32>, +index: U32) -> F32:
  lm.value(List.drop(&2, F32, lm, U32.to_nat(index)))

def words.floats.go(values: +List<U32>, +acc: +List<F32>) -> +List<F32>:
  match values:
    case Nil{}: turned.f(acc, Nil{})
    case Con{+w, rest}: words.floats.go(rest, Con{float(w), acc})

def words.floats(values: +List<U32>) -> +List<F32>:
  words.floats.go(values, Nil{})

# cgltf_node_transform_local without a matrix: rotation, scale, translation.
def local.trs(+t: +List<U32>, +q: +List<U32>, +s: +List<U32>) -> +List<F32>:
  +qx = at(q, 0)
  +qy = at(q, 1)
  +qz = at(q, 2)
  +qw = at(q, 3)
  +sx = at(s, 0)
  +sy = at(s, 1)
  +sz = at(s, 2)
  [(((1.0 - ((2.0 * qy) * qy)) - ((2.0 * qz) * qz)) * sx : F32), ((((2.0 * qx) * qy) + ((2.0 * qz) * qw)) * sx : F32), ((((2.0 * qx) * qz) - ((2.0 * qy) * qw)) * sx : F32), 0.0,
    ((((2.0 * qx) * qy) - ((2.0 * qz) * qw)) * sy : F32), (((1.0 - ((2.0 * qx) * qx)) - ((2.0 * qz) * qz)) * sy : F32), ((((2.0 * qy) * qz) + ((2.0 * qx) * qw)) * sy : F32), 0.0,
    ((((2.0 * qx) * qz) + ((2.0 * qy) * qw)) * sz : F32), ((((2.0 * qy) * qz) - ((2.0 * qx) * qw)) * sz : F32), (((1.0 - ((2.0 * qx) * qx)) - ((2.0 * qy) * qy)) * sz : F32), 0.0,
    at(t, 0), at(t, 1), at(t, 2), 1.0]

def local.built(+matrix: Bool, +m: Words, +t: Words, +q: Words, +s: Words) -> Lm:
  Words{+mo, +mv} = m
  Words{+to, +tv} = t
  Words{+qo, +qv} = q
  Words{+so, +sv} = s
  Bool.pick(Lm, matrix, Lm{mo, words.floats(mv)}, Lm{to && qo && so, local.trs(tv, qv, sv)})

def one() -> U32:
  1065353216

def local(+node: JS.Json) -> Lm:
  local.built(has(node, "matrix"), floats.of(JS.get(node, T.bytes("matrix")), 16, Nil{}), floats.of(JS.get(node, T.bytes("translation")), 3, [0, 0, 0]),
    floats.of(JS.get(node, T.bytes("rotation")), 4, [0, 0, 0, one()]), floats.of(JS.get(node, T.bytes("scale")), 3, [one(), one(), one()]))

# One row of the child's matrix through the parent's 3x3 part.
def row(+l0: F32, +l1: F32, +l2: F32, +l3: F32, +p: +List<F32>, +tail: +List<F32>) -> +List<F32>:
  Con{(((l0 * lm.get(p, 0)) + (l1 * lm.get(p, 4))) + (l2 * lm.get(p, 8)) : F32), Con{(((l0 * lm.get(p, 1)) + (l1 * lm.get(p, 5))) + (l2 * lm.get(p, 9)) : F32),
    Con{(((l0 * lm.get(p, 2)) + (l1 * lm.get(p, 6))) + (l2 * lm.get(p, 10)) : F32), Con{l3, tail}}}}

# cgltf_node_transform_world's step: the four rows, then the parent's translation added.
def above(+l: +List<F32>, +p: +List<F32>) -> +List<F32>:
  +last = row(lm.get(l, 12), lm.get(l, 13), lm.get(l, 14), lm.get(l, 15), p, Nil{})
  row(lm.get(l, 0), lm.get(l, 1), lm.get(l, 2), lm.get(l, 3), p, row(lm.get(l, 4), lm.get(l, 5), lm.get(l, 6), lm.get(l, 7), p,
    row(lm.get(l, 8), lm.get(l, 9), lm.get(l, 10), lm.get(l, 11), p,
      [(lm.get(last, 0) + lm.get(p, 12) : F32), (lm.get(last, 1) + lm.get(p, 13) : F32), (lm.get(last, 2) + lm.get(p, 14) : F32), lm.get(last, 3)])))

def member.index(items: +List<JS.Json>, +wanted: U32) -> Bool:
  match items:
    case Nil{}: False{}
    case Con{+item, rest}: U32.is_eq(int.of(Some{item}, bad()), wanted) || member.index(rest, wanted)

# The node whose children hold the wanted one: its index, the node count when none, bad() when two do.
def parent(nodes: +List<JS.Json>, +wanted: U32, +index: U32, +found: U32, +total: U32) -> U32:
  match nodes:
    case Nil{}: found
    case Con{+node, rest}:
      +holds = member.index(list(node, "children"), wanted)
      parent(rest, wanted, (index + 1 : U32), Bool.pick(U32, holds, Bool.pick(U32, U32.is_eq(found, total), index, bad()), found), total)

def world.joined(+lm: Lm, +parent: Lm) -> Lm:
  Lm{+ok, +v} = lm
  Lm{+pok, +pv} = parent
  Lm{ok && pok, above(v, pv)}

def world.step(+nodes: +List<JS.Json>, +total: U32, +up: U32, +lm: Lm) -> Lm:
  world.joined(lm, local(nth(nodes, up)))

# The world matrix: the local one, then each ancestor's (at most as many as there are nodes).
def world(n: Nat, +nodes: +List<JS.Json>, +total: U32, +current: U32, +lm: Lm) -> Lm:
  match n:
    case 0n: Lm{False{}, Nil{}}
    case 1n+p:
      +up = parent(nodes, current, 0, total, total)
      Bool.pick(Lm, U32.is_eq(up, total), lm, Bool.pick(Lm, good(up), world(p, nodes, total, up, world.step(nodes, total, up, lm)), Lm{False{}, Nil{}}))

def matrix(+v: +List<F32>) -> M.Matrix:
  M.Matrix{lm.get(v, 0), lm.get(v, 4), lm.get(v, 8), lm.get(v, 12), lm.get(v, 1), lm.get(v, 5), lm.get(v, 9), lm.get(v, 13),
    lm.get(v, 2), lm.get(v, 6), lm.get(v, 10), lm.get(v, 14), lm.get(v, 3), lm.get(v, 7), lm.get(v, 11), lm.get(v, 15)}

# Where an accessor's elements are in the buffer: the first byte, the bytes
# from one element to the next and the element count, as LOAD_ATTRIBUTE
# walks them (offsets and stride divided by the component size).
type Span is Data:
  Span{ok: Bool, start: U32, step: U32, count: U32}

def span.view(+view: JS.Json, +offset: U32, +count: U32, +size: U32, +comps: U32, +limit: U32) -> Span:
  +at = int(view, "byteOffset", 0)
  +given = int(view, "byteStride", 0)
  +stride = Bool.pick(U32, U32.is_eq(given, 0), (size * comps : U32), given)
  +start = (size * ((at / size) + (offset / size)) : U32)
  +step = (size * (stride / size) : U32)
  +valid = good(at) && good(given) && U32.is_eq(int(view, "buffer", bad()), 0) && Bool.not(has(view, "extensions"))
  +inside = U32.is_eq(count, 0) || ((start + step * (count - 1) + size * comps : U32) <= limit : U32)
  Span{valid && good(start) && good(step) && good(count) && inside, start, step, count}

# The accessor must have this component type and element type, a buffer view and no sparse storage.
def span(+root: JS.Json, +index: U32, +component: U32, kind: String, +size: U32, +comps: U32, +limit: U32) -> Span:
  +accessor = nth(list(root, "accessors"), index)
  +view = int(accessor, "bufferView", bad())
  +offset = int(accessor, "byteOffset", 0)
  +count = int(accessor, "count", bad())
  +typed = U32.is_eq(int(accessor, "componentType", bad()), component) && JS.same(text.of(JS.get(accessor, T.bytes("type"))), T.bytes(kind))
  Bool.pick(Span, good(index) && good(view) && good(offset) && good(count) && typed && Bool.not(has(accessor, "sparse")),
    span.view(nth(list(root, "bufferViews"), view), offset, count, size, comps, limit), Span{False{}, 0, 0, 0})

# One element's words, pushed onto the reversed list.
def element32(n: Nat, +data: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+p: element32(p, List.drop(&2, U32, data, 4n), Con{u32(data), acc})

# count elements of comps 32-bit words each.
def words32.go(n: Nat, +data: +List<U32>, +comps: Nat, +step: Nat, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: turned(acc, Nil{})
    case 1n+p: words32.go(p, List.drop(&2, U32, data, step), comps, step, element32(comps, data, acc))

def words32(n: Nat, +data: +List<U32>, +comps: Nat, +step: Nat) -> +List<U32>:
  words32.go(n, data, comps, step, Nil{})

def index.value(+size: U32, +data: +List<U32>) -> U32:
  Bool.pick(U32, U32.is_eq(size, 1), first(data), Bool.pick(U32, U32.is_eq(size, 2), u16(data), (u32(data) .&. 65535 : U32)))

def indices.go(n: Nat, +data: +List<U32>, +size: U32, +step: Nat, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: turned(acc, Nil{})
    case 1n+p: indices.go(p, List.drop(&2, U32, data, step), size, step, Con{index.value(size, data), acc})

def indices(n: Nat, +data: +List<U32>, +size: U32, +step: Nat) -> +List<U32>:
  indices.go(n, data, size, step, Nil{})

def read32(+span: Span, +bin: +List<U32>, +comps: U32) -> +List<U32>:
  Span{_, +start, +step, +count} = span
  words32(U32.to_nat(count), List.drop(&2, U32, bin, U32.to_nat(start)), U32.to_nat(comps), U32.to_nat(step))

# A vector pushed onto the reversed list.
def emit(v: M.Vector3, +acc: +List<F32>) -> +List<F32>:
  M.Vector3{x, y, z} = v
  Con{z, Con{y, Con{x, acc}}}

def transformed3.go(values: +List<U32>, +matrix: M.Matrix, +acc: +List<F32>) -> +List<F32>:
  match values:
    case Con{+x, Con{+y, Con{+z, rest}}}: transformed3.go(rest, matrix, emit(M.Vector3.transform(M.Vector3{float(x), float(y), float(z)}, matrix), acc))
    case _: turned.f(acc, Nil{})

# Vector3Transform of each position or normal.
def transformed3(values: +List<U32>, +matrix: M.Matrix) -> +List<F32>:
  transformed3.go(values, matrix, Nil{})

def transformed4.go(values: +List<U32>, +matrix: M.Matrix, +acc: +List<F32>) -> +List<F32>:
  match values:
    case Con{+x, Con{+y, Con{+z, Con{+w, rest}}}}: transformed4.go(rest, matrix, Con{float(w), emit(M.Vector3.transform(M.Vector3{float(x), float(y), float(z)}, matrix), acc)})
    case _: turned.f(acc, Nil{})

# A tangent's xyz transformed, its w kept.
def transformed4(values: +List<U32>, +matrix: M.Matrix) -> +List<F32>:
  transformed4.go(values, matrix, Nil{})

# A primitive as the Mesh it becomes; ok is False when something is refused.
type Prim is Data:
  Prim{ok: Bool, vertex_count: U32, triangle_count: U32, vertices: Maybe<&2, +List<F32>>, texcoords: Maybe<&2, +List<F32>>, texcoords2: Maybe<&2, +List<F32>>,
    normals: Maybe<&2, +List<F32>>, tangents: Maybe<&2, +List<F32>>, indices: Maybe<&2, +List<U32>>, material: U32}

# An empty mesh; a primitive with compression or morph targets is refused.
def fresh(+ok: Bool) -> Prim:
  Prim{ok, 0, 0, None{}, None{}, None{}, None{}, None{}, None{}, 0}

def refused() -> Prim:
  Prim{False{}, 0, 0, None{}, None{}, None{}, None{}, None{}, None{}, 0}

# cgltf_parse_attribute_type: the name before its first underscore (0 other, 1 POSITION, 2 NORMAL, 3 TANGENT, 4 TEXCOORD, 5 COLOR, 6 JOINTS, 7 WEIGHTS).
def before(name: +List<U32>) -> +List<U32>:
  match name:
    case Nil{}: Nil{}
    case Con{+c, rest}: Bool.pick(+List<U32>, U32.is_eq(c, 95), Nil{}, Con{c, before(rest)})

def after(name: +List<U32>) -> +List<U32>:
  match name:
    case Nil{}: Nil{}
    case Con{+c, +rest}: Bool.pick(+List<U32>, U32.is_eq(c, 95), rest, after(rest))

def attribute.kind(+name: +List<U32>) -> U32:
  +base = before(name)
  Bool.pick(U32, U32.is_eq(first(name), 95), 0, Bool.pick(U32, JS.same(base, T.bytes("POSITION")), 1, Bool.pick(U32, JS.same(base, T.bytes("NORMAL")), 2,
    Bool.pick(U32, JS.same(base, T.bytes("TANGENT")), 3, Bool.pick(U32, JS.same(base, T.bytes("TEXCOORD")), 4,
      Bool.pick(U32, JS.same(base, T.bytes("COLOR")), 5, Bool.pick(U32, JS.same(base, T.bytes("JOINTS")), 6, Bool.pick(U32, JS.same(base, T.bytes("WEIGHTS")), 7, 0))))))))

# The index after the underscore, as atoi reads it: 0 without one or without digits.
def attribute.index(text: +List<U32>, +acc: U32) -> U32:
  match text:
    case Nil{}: acc
    case Con{+c, rest}: Bool.pick(U32, (c >= 48 : U32) && (c <= 57 : U32) && (acc < 1000 : U32), attribute.index(rest, (acc * 10 + (c - 48) : U32)), acc)

def with_positions(+prim: Prim, +s: Span, +bin: +List<U32>, +world: M.Matrix) -> Prim:
  Prim{+ok, _, +tc, _, +texcoords, +texcoords2, +normals, +tangents, +indices, +material} = prim
  Span{+valid, _, _, +count} = s
  Prim{ok && valid, count, tc, Some{transformed3(read32(s, bin, 3), world)}, texcoords, texcoords2, normals, tangents, indices, material}

def with_normals(+prim: Prim, +s: Span, +bin: +List<U32>, +normal: M.Matrix) -> Prim:
  Prim{+ok, +vc, +tc, +vertices, +texcoords, +texcoords2, _, +tangents, +indices, +material} = prim
  Span{+valid, _, _, _} = s
  Prim{ok && valid, vc, tc, vertices, texcoords, texcoords2, Some{transformed3(read32(s, bin, 3), normal)}, tangents, indices, material}

def with_tangents(+prim: Prim, +s: Span, +bin: +List<U32>, +world: M.Matrix) -> Prim:
  Prim{+ok, +vc, +tc, +vertices, +texcoords, +texcoords2, +normals, _, +indices, +material} = prim
  Span{+valid, _, _, _} = s
  Prim{ok && valid, vc, tc, vertices, texcoords, texcoords2, normals, Some{transformed4(read32(s, bin, 4), world)}, indices, material}

# TEXCOORD_0 and TEXCOORD_1; a higher set is ignored.
def with_texcoords(+prim: Prim, +s: Span, +bin: +List<U32>, +slot: U32) -> Prim:
  Prim{+ok, +vc, +tc, +vertices, +texcoords, +texcoords2, +normals, +tangents, +indices, +material} = prim
  Span{+valid, _, _, _} = s
  +values = words.floats(read32(s, bin, 2))
  Prim{ok && valid, vc, tc, vertices, Bool.pick(Maybe<&2, +List<F32>>, U32.is_eq(slot, 0), Some{values}, texcoords),
    Bool.pick(Maybe<&2, +List<F32>>, U32.is_eq(slot, 1), Some{values}, texcoords2), normals, tangents, indices, material}

def span.ok(s: Span) -> Bool:
  Span{ok, _, _, _} = s
  ok

# JOINTS_n (a VEC4 of u8 or u16) and WEIGHTS_n (also of float): LoadGLTF
# reads them into the mesh's bone data, which Jonlib's Mesh does not have,
# so the accessor is checked and its values are not kept. Another layout
# only warns there; here it refuses.
def with_bones(+prim: Prim, +root: JS.Json, +accessor: U32, +limit: U32, +weights: Bool) -> Prim:
  +valid = span.ok(span(root, accessor, 5121, "VEC4", 1, 4, limit)) || span.ok(span(root, accessor, 5123, "VEC4", 2, 4, limit)) || (weights && span.ok(span(root, accessor, 5126, "VEC4", 4, 4, limit)))
  Bool.pick(Prim, valid, prim, refused())

def attribute(kind: U32, +slot: U32, +prim: Prim, +root: JS.Json, +accessor: U32, +bin: +List<U32>, +limit: U32, +world: M.Matrix, +normal: M.Matrix) -> Prim:
  match kind:
    case 0: prim
    case 1: with_positions(prim, span(root, accessor, 5126, "VEC3", 4, 3, limit), bin, world)
    case 2: with_normals(prim, span(root, accessor, 5126, "VEC3", 4, 3, limit), bin, normal)
    case 3: with_tangents(prim, span(root, accessor, 5126, "VEC4", 4, 4, limit), bin, world)
    case 4: with_texcoords(prim, span(root, accessor, 5126, "VEC2", 4, 2, limit), bin, slot)
    case 6: with_bones(prim, root, accessor, limit, False{})
    case 7: with_bones(prim, root, accessor, limit, True{})
    case _: refused()

def attributes(members: +List<JS.Json.Member>, +prim: Prim, +root: JS.Json, +bin: +List<U32>, +limit: U32, +world: M.Matrix, +normal: M.Matrix) -> Prim:
  match members:
    case Nil{}: prim
    case Con{JS.JMember{+name, +value}, rest}:
      attributes(rest, attribute(attribute.kind(name), attribute.index(after(name), 0), prim, root, int.of(Some{value}, bad()), bin, limit, world, normal), root, bin, limit, world, normal)

def members.of(value: JS.Json) -> +List<JS.Json.Member>:
  match value:
    case JS.JObject{+members}: members
    case _: Nil{}

# The indices: unsigned bytes, shorts or ints (kept as shorts); triangleCount is count/3, or vertexCount/3 without indices.
def with_indices(+prim: Prim, +s: Span, +bin: +List<U32>, +size: U32, +known: Bool) -> Prim:
  Prim{+ok, +vc, _, +vertices, +texcoords, +texcoords2, +normals, +tangents, _, +material} = prim
  Span{+valid, +start, +step, +count} = s
  Prim{ok && valid && known, vc, (count / 3 : U32), vertices, texcoords, texcoords2, normals, tangents,
    Some{indices(U32.to_nat(count), List.drop(&2, U32, bin, U32.to_nat(start)), size, U32.to_nat(step))}, material}

def indexed.sized(+component: U32, +prim: Prim, +root: JS.Json, +accessor: U32, +bin: +List<U32>, +limit: U32) -> Prim:
  +size = Bool.pick(U32, U32.is_eq(component, 5121), 1, Bool.pick(U32, U32.is_eq(component, 5123), 2, 4))
  with_indices(prim, span(root, accessor, component, "SCALAR", size, 1, limit), bin, size, U32.is_eq(component, 5121) || U32.is_eq(component, 5123) || U32.is_eq(component, 5125))

def unindexed(+prim: Prim) -> Prim:
  Prim{+ok, +vc, _, +vertices, +texcoords, +texcoords2, +normals, +tangents, +indices, +material} = prim
  Prim{ok, vc, (vc / 3 : U32), vertices, texcoords, texcoords2, normals, tangents, indices, material}

def indexed(present: Bool, +prim: Prim, +root: JS.Json, +primitive: JS.Json, +bin: +List<U32>, +limit: U32) -> Prim:
  match present:
    case False{}: unindexed(prim)
    case True{}:
      +accessor = int(primitive, "indices", bad())
      indexed.sized(int(nth(list(root, "accessors"), accessor), "componentType", bad()), prim, root, accessor, bin, limit)

# meshMaterial: the material's index + 1, or the default material 0.
def with_material(+prim: Prim, +primitive: JS.Json, +materials: U32) -> Prim:
  Prim{+ok, +vc, +tc, +vertices, +texcoords, +texcoords2, +normals, +tangents, +indices, _} = prim
  +index = int(primitive, "material", materials)
  Prim{ok && (index <= materials : U32), vc, tc, vertices, texcoords, texcoords2, normals, tangents, indices, Bool.pick(U32, (index < materials : U32), (index + 1 : U32), 0)}

# LoadGLTF copies every element of a JOINTS_n or WEIGHTS_n accessor into
# buffers of vertexCount elements: an accessor with more would write past them.
def bones.fit(members: +List<JS.Json.Member>, +root: JS.Json, +vertices: U32) -> Bool:
  match members:
    case Nil{}: True{}
    case Con{JS.JMember{+name, +value}, rest}:
      (Bool.not(U32.is_eq(attribute.kind(name), 6) || U32.is_eq(attribute.kind(name), 7)) || (int(nth(list(root, "accessors"), int.of(Some{value}, bad())), "count", bad()) <= vertices : U32)) && bones.fit(rest, root, vertices)

def fitted(+prim: Prim, +members: +List<JS.Json.Member>, +root: JS.Json) -> Prim:
  Prim{+ok, +vc, +tc, +vertices, +texcoords, +texcoords2, +normals, +tangents, +indices, +material} = prim
  Prim{ok && bones.fit(members, root, vc), vc, tc, vertices, texcoords, texcoords2, normals, tangents, indices, material}

def primitive(+primitive: JS.Json, +root: JS.Json, +bin: +List<U32>, +limit: U32, +world: M.Matrix, +normal: M.Matrix, +materials: U32) -> Prim:
  +start = fresh(Bool.not(has(primitive, "extensions")) && Bool.not(has(primitive, "targets")))
  +members = members.of(child(primitive, "attributes"))
  with_material(indexed(has(primitive, "indices"), fitted(attributes(members, start, root, bin, limit, world, normal), members, root), root, primitive, bin, limit), primitive, materials)

# Triangle primitives only (mode 4, the default): the others are skipped.
def primitives(items: +List<JS.Json>, +root: JS.Json, +bin: +List<U32>, +limit: U32, +world: M.Matrix, +normal: M.Matrix, +materials: U32, +tail: +List<Prim>) -> +List<Prim>:
  match items:
    case Nil{}: tail
    case Con{+item, rest}:
      +more = primitives(rest, root, bin, limit, world, normal, materials, tail)
      +mode = int(item, "mode", 4)
      Bool.pick(+List<Prim>, U32.is_eq(mode, 4), Con{primitive(item, root, bin, limit, world, normal, materials), more}, Bool.pick(+List<Prim>, good(mode), more, Con{refused(), more}))

def node.placed(+lm: Lm, +node: JS.Json, +root: JS.Json, +bin: +List<U32>, +limit: U32, +materials: U32, +tail: +List<Prim>) -> +List<Prim>:
  Lm{+ok, +v} = lm
  +m = matrix(v)
  +mesh = nth(list(root, "meshes"), int(node, "mesh", bad()))
  Bool.pick(+List<Prim>, ok && good(int(node, "mesh", bad())), primitives(list(mesh, "primitives"), root, bin, limit, m, M.Matrix.transpose(M.Matrix.invert(m)), materials, tail), Con{refused(), tail})

def node.meshes(present: Bool, +node: JS.Json, +index: U32, +root: JS.Json, +nodes: +List<JS.Json>, +total: U32, +bin: +List<U32>, +limit: U32, +materials: U32, +tail: +List<Prim>) -> +List<Prim>:
  match present:
    case False{}: tail
    case True{}: node.placed(world(U32.to_nat((total + 1 : U32)), nodes, total, index, local(node)), node, root, bin, limit, materials, tail)

# Every node with a mesh, in node order.
def scene(items: +List<JS.Json>, +index: U32, +root: JS.Json, +nodes: +List<JS.Json>, +total: U32, +bin: +List<U32>, +limit: U32, +materials: U32) -> +List<Prim>:
  match items:
    case Nil{}: Nil{}
    case Con{+node, rest}: node.meshes(has(node, "mesh"), node, index, root, nodes, total, bin, limit, materials, scene(rest, (index + 1 : U32), root, nodes, total, bin, limit, materials))

# A material's albedo color: (unsigned char)(baseColorFactor*255) per channel
# (1, 1, 1, 1 without the factor); None for a texture or a factor outside
# 0..1 (bad() for such a channel).
def channel(+word: U32) -> U32:
  +scaled = (float(word) * 255.0 : F32)
  Bool.pick(U32, (scaled >= 0.0 : F32) && (scaled < 256.0 : F32), F32.to_u32(F32.trunc(scaled)), bad())

def color.of(+factor: Words) -> Maybe<U32>:
  Words{+ok, +v} = factor
  +r = channel(first(v))
  +g = channel(first(List.drop(&2, U32, v, 1n)))
  +b = channel(first(List.drop(&2, U32, v, 2n)))
  +a = channel(first(List.drop(&2, U32, v, 3n)))
  Bool.pick(Maybe<U32>, ok && good(r) && good(g) && good(b) && good(a), Some{((r << 24n) .|. (g << 16n) .|. (b << 8n) .|. a : U32)}, None{})

# A buffer view's bytes for an image: in the BIN chunk, without a stride
# (LoadImageFromCgltfImage would then skip bytes) and inside the buffer.
def view.bytes(+view: JS.Json, +bin: +List<U32>, +limit: U32) -> Words:
  +offset = int(view, "byteOffset", 0)
  +size = int(view, "byteLength", bad())
  +valid = good(offset) && good(size) && U32.is_eq(int(view, "buffer", bad()), 0) && Bool.not(has(view, "byteStride")) && Bool.not(has(view, "extensions")) && ((offset + size : U32) <= limit : U32)
  Words{valid, Bool.pick(+List<U32>, valid, take(U32.to_nat(size), List.drop(&2, U32, bin, U32.to_nat(offset))), Nil{})}

# cgltfImage->mime_type is "image/png" (or, as some files write it, "image\/png" with the backslash).
def png(+mime: +List<U32>) -> Bool:
  JS.same(mime, T.bytes("image/png")) || JS.same(mime, [105, 109, 97, 103, 101, 92, 47, 112, 110, 103])

# An image's PNG bytes: from a buffer view with a PNG mime type. An image
# with neither a uri nor a buffer view gives no texture; a uri, another mime
# type (JPEG included) or none refuses.
def image.bytes(+image: JS.Json, +root: JS.Json, +bin: +List<U32>, +limit: U32) -> Words:
  +view = int(image, "bufferView", bad())
  Bool.pick(Words, has(image, "uri") || has(image, "extensions"), Words{False{}, Nil{}},
    Bool.pick(Words, has(image, "bufferView"), Bool.pick(Words, good(view) && png(text.of(JS.get(image, T.bytes("mimeType")))), view.bytes(nth(list(root, "bufferViews"), view), bin, limit), Words{False{}, Nil{}}),
      Words{True{}, Nil{}}))

# texture->image: the texture's source (no image without one).
def texture.image(+texture: JS.Json, +root: JS.Json, +bin: +List<U32>, +limit: U32) -> Words:
  +source = int(texture, "source", bad())
  Bool.pick(Words, has(texture, "extensions"), Words{False{}, Nil{}},
    Bool.pick(Words, has(texture, "source"), Bool.pick(Words, good(source) && (source < count(list(root, "images"), 0) : U32), image.bytes(nth(list(root, "images"), source), root, bin, limit), Words{False{}, Nil{}}),
      Words{True{}, Nil{}}))

# baseColorTexture: the PNG bytes of its texture's image (ok and empty for none).
def albedo(+info: JS.Json, +root: JS.Json, +bin: +List<U32>, +limit: U32) -> Words:
  +index = int(info, "index", bad())
  Bool.pick(Words, good(index) && (index < count(list(root, "textures"), 0) : U32) && Bool.not(has(info, "extensions")), texture.image(nth(list(root, "textures"), index), root, bin, limit), Words{False{}, Nil{}})

# A material's albedo: its color (0xRRGGBBAA) and its base color texture's
# PNG bytes (empty for none).
type Look is Data:
  Look{ok: Bool, color: U32, image: +List<U32>}

def look.with(color: U32, +other: Bool, image: Words) -> Look:
  Words{ok, values} = image
  Look{Bool.not(other) && ok, color, values}

def look(color: Maybe<U32>, +other: Bool, +image: Words) -> Look:
  match color:
    case None{}: Look{False{}, 0, Nil{}}
    case Some{c}: look.with(c, other, image)

# White (the default material's color) and no texture without
# pbrMetallicRoughness; the other texture kinds and extensions refuse.
def material(+item: JS.Json, +root: JS.Json, +bin: +List<U32>, +limit: U32) -> Look:
  +pbr = child(item, "pbrMetallicRoughness")
  +other = has(pbr, "metallicRoughnessTexture") || has(item, "normalTexture") || has(item, "occlusionTexture") || has(item, "emissiveTexture") || has(item, "extensions")
  look(Bool.pick(Maybe<U32>, has(item, "pbrMetallicRoughness"), color.of(floats.of(JS.get(pbr, T.bytes("baseColorFactor")), 4, [one(), one(), one(), one()])), Some{4294967295}), other,
    Bool.pick(Words, has(item, "pbrMetallicRoughness") && has(pbr, "baseColorTexture"), albedo(child(pbr, "baseColorTexture"), root, bin, limit), Words{True{}, Nil{}}))

def materials(items: +List<JS.Json>, +root: JS.Json, +bin: +List<U32>, +limit: U32) -> +List<Look>:
  match items:
    case Nil{}: Nil{}
    case Con{+item, rest}: Con{material(item, root, bin, limit), materials(rest, root, bin, limit)}

def looks.ok(looks: +List<Look>) -> Bool:
  match looks:
    case Nil{}: True{}
    case Con{Look{+ok, _, _}, rest}: ok && looks.ok(rest)

def looks.colors(looks: +List<Look>) -> +List<U32>:
  match looks:
    case Nil{}: Nil{}
    case Con{Look{_, +color, _}, rest}: Con{color, looks.colors(rest)}

def looks.images(looks: +List<Look>) -> +List<+List<U32>>:
  match looks:
    case Nil{}: Nil{}
    case Con{Look{_, _, +image}, rest}: Con{image, looks.images(rest)}

# The meshes, and for each material its albedo color (0xRRGGBBAA) and its
# base color texture's PNG bytes (empty for none).
type Parts is Data:
  Parts{prims: +List<Prim>, colors: +List<U32>, images: +List<+List<U32>>}

def prims.ok(prims: +List<Prim>) -> Bool:
  match prims:
    case Nil{}: True{}
    case Con{Prim{+ok, _, _, _, _, _, _, _, _, _}, rest}: ok && prims.ok(rest)

# One buffer, in the BIN chunk (no uri), at most as long as the chunk.
def buffers.ok(items: +List<JS.Json>, +limit: U32) -> Bool:
  match items:
    case Con{+buffer, Nil{}}: Bool.not(has(buffer, "uri")) && (int(buffer, "byteLength", bad()) <= limit : U32)
    case _: False{}

# cgltf_fixup_pointers fails the parse for an index past its array (and for
# a required one that is missing): the indices of the sections this loader
# does not otherwise read.
def index.ok(+object: JS.Json, +name: String, +size: U32) -> Bool:
  Bool.not(has(object, name)) || (int(object, name, bad()) < size : U32)

def index.req(+object: JS.Json, name: String, +size: U32) -> Bool:
  (int(object, name, bad()) < size : U32)

def each.below(items: +List<JS.Json>, +size: U32) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}: (int.of(Some{item}, bad()) < size : U32) && each.below(rest, size)

# A texture with extensions (a Basis or WebP source) refuses.
def textures.fixed(items: +List<JS.Json>, +images: U32, +samplers: U32) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}: index.ok(item, "source", images) && index.ok(item, "sampler", samplers) && Bool.not(has(item, "extensions")) && textures.fixed(rest, images, samplers)

def images.fixed(items: +List<JS.Json>, +views: U32) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}: index.ok(item, "bufferView", views) && images.fixed(rest, views)

def info.fixed(+object: JS.Json, name: String, +textures: U32) -> Bool:
  index.ok(child(object, name), "index", textures)

def materials.fixed(items: +List<JS.Json>, +textures: U32) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}:
      info.fixed(child(item, "pbrMetallicRoughness"), "baseColorTexture", textures) && info.fixed(child(item, "pbrMetallicRoughness"), "metallicRoughnessTexture", textures) &&
        info.fixed(item, "normalTexture", textures) && info.fixed(item, "occlusionTexture", textures) && info.fixed(item, "emissiveTexture", textures) && materials.fixed(rest, textures)

def skins.fixed(items: +List<JS.Json>, +nodes: U32, +accessors: U32) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}: each.below(list(item, "joints"), nodes) && index.ok(item, "skeleton", nodes) && index.ok(item, "inverseBindMatrices", accessors) && skins.fixed(rest, nodes, accessors)

def nodes.fixed(items: +List<JS.Json>, +nodes: U32, +meshes: U32, +skins: U32, +cameras: U32) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}:
      each.below(list(item, "children"), nodes) && index.ok(item, "mesh", meshes) && index.ok(item, "skin", skins) && index.ok(item, "camera", cameras) && nodes.fixed(rest, nodes, meshes, skins, cameras)

def scenes.fixed(items: +List<JS.Json>, +nodes: U32) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}: each.below(list(item, "nodes"), nodes) && scenes.fixed(rest, nodes)

def samplers.fixed(items: +List<JS.Json>, +accessors: U32) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}: index.req(item, "input", accessors) && index.req(item, "output", accessors) && samplers.fixed(rest, accessors)

def channels.fixed(items: +List<JS.Json>, +samplers: U32, +nodes: U32) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}: index.req(item, "sampler", samplers) && index.ok(child(item, "target"), "node", nodes) && channels.fixed(rest, samplers, nodes)

def animations.fixed(items: +List<JS.Json>, +nodes: U32, +accessors: U32) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}:
      samplers.fixed(list(item, "samplers"), accessors) && channels.fixed(list(item, "channels"), count(list(item, "samplers"), 0), nodes) && animations.fixed(rest, nodes, accessors)

def fixup(+root: JS.Json) -> Bool:
  +nodes = count(list(root, "nodes"), 0)
  +accessors = count(list(root, "accessors"), 0)
  +textures = count(list(root, "textures"), 0)
  textures.fixed(list(root, "textures"), count(list(root, "images"), 0), count(list(root, "samplers"), 0)) && images.fixed(list(root, "images"), count(list(root, "bufferViews"), 0)) &&
    materials.fixed(list(root, "materials"), textures) && skins.fixed(list(root, "skins"), nodes, accessors) &&
    nodes.fixed(list(root, "nodes"), nodes, count(list(root, "meshes"), 0), count(list(root, "skins"), 0), count(list(root, "cameras"), 0)) &&
    scenes.fixed(list(root, "scenes"), nodes) && index.ok(root, "scene", count(list(root, "scenes"), 0)) && animations.fixed(list(root, "animations"), nodes, accessors)

def built(+root: JS.Json, +bin: +List<U32>, +limit: U32) -> Maybe<Parts>:
  +nodes = list(root, "nodes")
  +total = count(nodes, 0)
  +prims = scene(nodes, 0, root, nodes, total, bin, limit, count(list(root, "materials"), 0))
  +looks = materials(list(root, "materials"), root, bin, limit)
  +plain = listed(root, "nodes") && listed(root, "meshes") && listed(root, "accessors") && listed(root, "bufferViews") && listed(root, "materials")
  Bool.pick(Maybe<Parts>, plain && Bool.not(has(root, "extensionsRequired")) && fixup(root) && buffers.ok(list(root, "buffers"), limit) && good(total) && prims.ok(prims) && looks.ok(looks),
    Some{Parts{prims, looks.colors(looks), looks.images(looks)}}, None{})

def json(root: +Maybe<JS.Json>, +bin: +List<U32>, +limit: U32) -> Maybe<Parts>:
  match root:
    case None{}: None{}
    case Some{+value}: built(value, bin, limit)

# The container: "glTF", version 2, the total length, a JSON chunk and a BIN chunk.
def chunks(+bytes: +List<U32>, +size: U32) -> Maybe<Parts>:
  +json_length = u32(List.drop(&2, U32, bytes, 12n))
  +after = List.drop(&2, U32, bytes, U32.to_nat((20 + json_length : U32)))
  +bin_length = u32(after)
  +valid = (size >= 28 : U32) && U32.is_eq(u32(bytes), 1179937895) && U32.is_eq(u32(List.drop(&2, U32, bytes, 4n)), 2) && U32.is_eq(u32(List.drop(&2, U32, bytes, 8n)), size) &&
    U32.is_eq(u32(List.drop(&2, U32, bytes, 16n)), 1313821514) && good(json_length) && ((28 + json_length : U32) <= size : U32) &&
    U32.is_eq(u32(List.drop(&2, U32, after, 4n)), 5130562) && good(bin_length) && U32.is_eq((28 + json_length + bin_length : U32), size)
  Bool.pick(Maybe<Parts>, valid, json(JS.parse(take(U32.to_nat(json_length), List.drop(&2, U32, bytes, 20n))), List.drop(&2, U32, after, 8n), bin_length), None{})

# The meshes and material looks of a .glb file's bytes.
def glb(+bytes: +List<U32>) -> Maybe<Parts>:
  chunks(bytes, length(bytes, 0))
