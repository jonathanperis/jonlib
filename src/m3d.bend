# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.2 rmodels.c LoadM3D and
# LoadModelAnimationsM3D (zlib, LICENSES/raylib.txt) and of the binary
# importer of Model 3D (src/external/m3d.h, Copyright (C) 2020 bzt
# (bztsrc@gitlab), MIT; LICENSES/m3d.txt): m3d_load's container (the 3DMO
# magic and length, an optional preview chunk, then HEAD or a zlib stream
# that inflates to it), its header (the scale, the size of every index from
# the types word, the OMD3 end mark) and its chunks.
#
# Then LoadM3D's meshes (three vertices a face, a mesh a run of faces of one
# material), materials and skeleton, and LoadModelAnimationsM3D's keyframes
# through m3d_pose (the frames up to a time, then an interpolation to the
# next one with the importer's approximated NLERP and inverse square root,
# whose factor carries from a bone to the next as upstream's does).
# Refused: reads outside a chunk, the file or an array; procedural, voxel,
# shape and label chunks; faces without normals (the importer generates
# them); a map property that names a texture (an inlined asset or a file);
# coordinates as doubles; the profile's sizes. See docs/MODELS.md.
import Base
import ./../jonmath.bend as M
import ./gltf_anim.bend as GA
import ./png.bend as Png

# The file after its container: the bytes from HEAD on (raw) and their count,
# the scale, the index sizes (0 for an index the file does not have) and the
# bytes from the first chunk after HEAD with their offset in raw.
type File is Data:
  File{raw: +List<U32>, size: U32, scale: F32, vc: U32, vi: U32, si: U32, ci: U32, ti: U32, bi: U32, nb: U32, sk: U32, fc: U32, first: U32}

# Unread: the importer reads outside its buffers or the profile ends.
# Foreign: m3d_load gives no model (LoadM3D returns the empty model).
type Opened is Data:
  Unread{}
  Foreign{}
  Open{file: File}

# An index read from the stream and the bytes after it; ok: the bytes were there.
type Index is Data:
  Index{ok: Bool, value: U32, rest: +List<U32>}

# Eight words by index: a balanced tree, for the arrays the chunks index
# into (vertices, texture coordinates, colors, skins).
type Row is Data:
  Row{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32}

type Tree is Data:
  Tip{}
  Leaf{row: Row}
  Node{left: Tree, right: Tree}

# A store: its tree, its depth and how many rows it holds.
type Store is Data:
  Store{tree: Tree, depth: Nat, count: U32}

def length(values: +List<U32>, +acc: U32) -> U32:
  match values:
    case Nil{}: acc
    case Con{_, rest}: length(rest, (acc + 1 : U32))

def float(+word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# A little-endian unsigned int at the head of the bytes; 0 when they are fewer than four.
def word(bytes: +List<U32>) -> U32:
  match bytes:
    case Con{+a, Con{+b, Con{+c, Con{+d, _}}}}: (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)
    case _: 0

def at(+bytes: +List<U32>, +offset: U32) -> +List<U32>:
  List.drop(&2, U32, bytes, U32.to_nat(U32.min(offset, 16777216)))

def taken.go(n: Nat, values: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match n values:
    case 1n+k Con{+v, rest}: taken.go(k, rest, Con{v, acc})
    case _ _: List.reverse(&2, U32, acc)

def taken(+values: +List<U32>, +count: U32) -> +List<U32>:
  taken.go(U32.to_nat(U32.min(count, 16777216)), values, Nil{})

# M3D_CHUNKMAGIC(m, a, b, c, d).
def magic(bytes: +List<U32>, +a: U32, +b: U32, +c: U32, +d: U32) -> Bool:
  match bytes:
    case Con{+w, Con{+x, Con{+y, Con{+z, _}}}}: U32.is_eq(w, a) && U32.is_eq(x, b) && U32.is_eq(y, c) && U32.is_eq(z, d)
    case _: False{}

# 1 << ((types >> shift) & 3), and 0 for the optional indices whose size says 8.
def sized(+types: U32, +shift: U32, +optional: Bool) -> U32:
  +size = (1 << U32.to_nat(((types >> U32.to_nat(shift)) .&. 3 : U32)) : U32)
  Bool.pick(U32, optional && U32.is_eq(size, 8), 0, size)

# _m3d_getidx(data, type, &idx): one byte (254 and 255 are -2 and -1), two
# (65534 and 65535 likewise) or four; a size of 0 or 8 reads nothing and
# leaves the index as it was.
def index(size: U32, bytes: +List<U32>, +kept: U32) -> Index:
  match size bytes:
    case 1 Con{+a, +rest}: Index{True{}, Bool.pick(U32, (a > 253 : U32), (a .|. 4294967040 : U32), a), rest}
    case 2 Con{+a, Con{+b, +rest}}: Index{True{}, Bool.pick(U32, ((a .|. (b << 8n)) > 65533 : U32), (a .|. (b << 8n) .|. 4294901760 : U32), (a .|. (b << 8n) : U32)), rest}
    case 4 Con{+a, Con{+b, Con{+c, Con{+d, +rest}}}}: Index{True{}, (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32), rest}
    case 1 Nil{}: Index{False{}, kept, Nil{}}
    case 2 _: Index{False{}, kept, Nil{}}
    case 4 _: Index{False{}, kept, Nil{}}
    case _ Nil{}: Index{True{}, kept, Nil{}}
    case _ Con{+a, +rest}: Index{True{}, kept, Con{a, rest}}

def rows.turned(xs: +List<Tree>, acc: +List<Tree>) -> +List<Tree>:
  match xs:
    case Nil{}: acc
    case Con{+t, rest}: rows.turned(rest, Con{t, acc})

def leaves(xs: +List<Row>, acc: +List<Tree>) -> +List<Tree>:
  match xs:
    case Nil{}: rows.turned(acc, Nil{})
    case Con{+r, rest}: leaves(rest, Con{Leaf{r}, acc})

def pairs(xs: +List<Tree>, acc: +List<Tree>) -> +List<Tree>:
  match xs:
    case Con{+a, Con{+b, rest}}: pairs(rest, Con{Node{a, b}, acc})
    case Con{+a, Nil{}}: rows.turned(Con{Node{a, Tip{}}, acc}, Nil{})
    case _: rows.turned(acc, Nil{})

def levels(d: Nat, +xs: +List<Tree>) -> +List<Tree>:
  match d:
    case 0n: xs
    case 1n+k: levels(k, pairs(xs, Nil{}))

def tree.first(xs: +List<Tree>) -> Tree:
  match xs:
    case Con{+t, _}: t
    case Nil{}: Tip{}

def depth(+count: U32) -> Nat:
  Bool.pick(Nat, (count <= 1 : U32), 0n, 1n+U32.log2((count - 1 : U32)))

def rows.count(xs: +List<Row>, +acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case Con{_, rest}: rows.count(rest, (acc + 1 : U32))

# The rows, in order, as a store.
def stored(+rows: +List<Row>) -> Store:
  +count = rows.count(rows, 0)
  Store{tree.first(levels(depth(count), leaves(rows, Nil{}))), depth(count), count}

def none() -> Row:
  Row{0, 0, 0, 0, 0, 0, 0, 0}

def tree.get(+d: Nat, t: Tree, +i: U32) -> Row:
  match d t:
    case 0n Leaf{+r}: r
    case 1n+k Node{+l, +r}: tree.get(k, Bool.pick(Tree, U32.is_eq(((i >> k) .&. 1 : U32), 1), r, l), i)
    case _ _: none()

# The row at an index below the store's count (zeros otherwise).
def row(+store: Store, +i: U32) -> Row:
  Store{+tree, +levels, +count} = store
  Bool.pick(Row, (i < count : U32), tree.get(levels, tree, i), none())

def Store.count(store: Store) -> U32:
  Store{_, _, count} = store
  count

def copied(xs: List<U32>, +acc: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+x, rest}: copied(rest, Con{x, acc})

# The header after HEAD's magic: its length (the first chunk follows), the
# scale (1 for a scale that is not positive) and the types word. No model
# for an index size the importer does not take (a vertex or string index
# over 4 bytes, voxel pixels of 4) or without the OMD3 mark in the last four
# bytes; coordinates as doubles are outside the profile.
def headed(+raw: +List<U32>, +size: U32) -> Opened:
  +types = word(at(raw, 12))
  +scale = float(word(at(raw, 8)))
  +vc = sized(types, 0, False{})
  +vi = sized(types, 2, False{})
  +si = sized(types, 4, False{})
  Bool.pick(Opened, (size < 16 : U32) || U32.is_eq(vc, 8), Unread{}, Bool.pick(Opened, (vi > 4 : U32) || (si > 4 : U32) || U32.is_eq(sized(types, 24, False{}), 4) || Bool.not(magic(at(raw, (size - 4 : U32)), 79, 77, 68, 51)), Foreign{},
    Open{File{raw, size, Bool.pick(F32, (scale <= 0.0 : F32), 1.0, scale), vc, vi, si, sized(types, 6, True{}), sized(types, 8, True{}), sized(types, 10, True{}), sized(types, 12, False{}), sized(types, 14, True{}),
      sized(types, 16, True{}), word(at(raw, 4))}}))

# The stream inflated: no model unless it gives bytes that start with HEAD.
def inflated.head(+raw: +List<U32>) -> Opened:
  Bool.pick(Opened, magic(raw, 72, 69, 65, 68), headed(raw, length(raw, 0)), Foreign{})

# A stream the decoder does not finish is refused (the importer gives no
# model for one stb's decoder rejects, and the two decoders are not compared
# on streams that end early).
def inflated(data: Maybe<List<U32>>) -> Opened:
  match data:
    case None{}: Unread{}
    case Some{bytes}: inflated.head(copied(bytes, Nil{}))

# What follows the container's eight bytes (and the preview chunk): HEAD as it
# is, or a zlib stream of `len` bytes that inflates to it (16 MiB at most here).
def body(plain: Bool, +data: +List<U32>, +len: U32) -> Opened:
  match plain:
    case True{}: headed(taken(data, len), len)
    case False{}: inflated(Png.zlib(taken(data, len), 16777216))

# After a preview chunk (its length is at least its header's 8 bytes and at most what is left).
def previewed(fits: Bool, +data: +List<U32>, +len: U32) -> Opened:
  match fits:
    case False{}: Unread{}
    case True{}: body(magic(data, 72, 69, 65, 68), data, len)

# The container: 3DMO, the file's length, then the model (len = length - 8 bytes of it, all inside the file).
def contained(fits: Bool, +data: +List<U32>, +len: U32) -> Opened:
  match fits:
    case False{}: Unread{}
    case True{}:
      Bool.pick(Opened, magic(data, 80, 82, 86, 87), previewed((word(at(data, 4)) >= 8 : U32) && (word(at(data, 4)) <= len : U32) && ((len - word(at(data, 4))) >= 4 : U32), at(data, word(at(data, 4))), (len - word(at(data, 4)) : U32)),
        body(magic(data, 72, 69, 65, 68), data, len))

# m3d_load's first steps on a file's bytes: an empty file is one LoadFileData
# does not load; fewer than four bytes are read past; another magic (the
# ASCII variant's too: it is not built in) gives no model.
def open.sized(+bytes: +List<U32>, +size: U32) -> Opened:
  Bool.pick(Opened, U32.is_eq(size, 0), Foreign{}, Bool.pick(Opened, (size < 4 : U32) || (size > 2097152 : U32), Unread{}, Bool.pick(Opened, Bool.not(magic(bytes, 51, 68, 77, 79)), Foreign{},
    contained((size >= 12 : U32) && (word(at(bytes, 4)) >= 12 : U32) && (word(at(bytes, 4)) <= size : U32), at(bytes, 8), (word(at(bytes, 4)) - 8 : U32)))))

def open(+bytes: +List<U32>) -> Opened:
  open.sized(bytes, length(bytes, 0))

type Rows is Data:
  Rows{ok: Bool, rows: +List<Row>}

def rows.reversed(xs: +List<Row>, acc: +List<Row>) -> +List<Row>:
  match xs:
    case Nil{}: acc
    case Con{+r, rest}: rows.reversed(rest, Con{r, acc})

# CMAP: uint32 colors.
def colors(bytes: +List<U32>, +acc: +List<Row>) -> +List<Row>:
  match bytes:
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}: colors(rest, Con{Row{(a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32), 0, 0, 0, 0, 0, 0, 0}, acc})
    case _: rows.reversed(acc, Nil{})

# A coordinate of vc bytes as the importer converts it: an unsigned byte over
# 255 or an unsigned short over 65535 for the texture map; a signed byte over
# 127 or a signed short over 32767 for vertices; a float as it is.
def unsigned(size: U32, +value: U32) -> F32:
  match size:
    case 1: (U32.to_f32(value) / 255.0 : F32)
    case 2: (U32.to_f32(value) / 65535.0 : F32)
    case _: float(value)

def signed.float(+value: U32, +bits: U32) -> F32:
  Bool.pick(F32, U32.is_ne((value .&. bits : U32), 0), F32.neg(U32.to_f32(((bits << 1n) - value : U32))), U32.to_f32(value))

def signed(size: U32, +value: U32) -> F32:
  match size:
    case 1: (signed.float(value, 128) / 127.0 : F32)
    case 2: (signed.float(value, 32768) / 32767.0 : F32)
    case _: float(value)

# A little-endian value of 1, 2 or 4 bytes; ok: the bytes were there.
def value(size: U32, bytes: +List<U32>) -> Index:
  match size bytes:
    case 1 Con{+a, +rest}: Index{True{}, a, rest}
    case 2 Con{+a, Con{+b, +rest}}: Index{True{}, (a .|. (b << 8n) : U32), rest}
    case 4 Con{+a, Con{+b, Con{+c, Con{+d, +rest}}}}: Index{True{}, (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32), rest}
    case _ _: Index{False{}, 0, Nil{}}

def Index.ok(i: Index) -> Bool:
  Index{ok, _, _} = i
  ok

def Index.value(i: Index) -> U32:
  Index{_, value, _} = i
  value

def Index.rest(i: Index) -> +List<U32>:
  Index{_, _, rest} = i
  rest

# TMAP: u and v of vc bytes each. A chunk that is not whole records makes
# the importer write past its array (ok is then false).
def texcoords(fuel: Nat, +bytes: +List<U32>, +vc: U32, +ok: Bool, +acc: +List<Row>) -> Rows:
  match fuel bytes:
    case _ Nil{}: Rows{ok, rows.reversed(acc, Nil{})}
    case 0n Con{_, _}: Rows{False{}, Nil{}}
    case 1n+k Con{+b, +rest}:
      +u = value(vc, Con{b, rest})
      +v = value(vc, Index.rest(u))
      texcoords(k, Index.rest(v), vc, ok && Index.ok(u) && Index.ok(v), Con{Row{F32.bits(unsigned(vc, Index.value(u))), F32.bits(unsigned(vc, Index.value(v))), 0, 0, 0, 0, 0, 0}, acc})

def row.first(+r: Row) -> U32:
  Row{a, _, _, _, _, _, _, _} = r
  a

# A vertex's color: the color map's entry for an index of 1 or 2 bytes (0
# without a map; an index past the map is a read outside it), the word
# itself for 4 bytes, nothing (0) without color indices.
def colored(+ci: U32, +cmapped: Bool, +cmap: Store, +read: Index) -> Index:
  Index{+ok, +value, +rest} = read
  Bool.pick(Index, U32.is_eq(ci, 4) || U32.is_eq(ci, 0), Index{ok, Bool.pick(U32, U32.is_eq(ci, 4), value, 0), rest},
    Index{ok && (Bool.not(cmapped) || (value < Store.count(cmap) : U32)), Bool.pick(U32, cmapped, row.first(row(cmap, value)), 0), rest})

# VRTS: numvertex = len/reclen records of four coordinates of vc bytes, the
# color (index or word) and the skin index (M3D_UNDEF without one).
def vertices(n: Nat, +bytes: +List<U32>, +file: File, +cmapped: Bool, +cmap: Store, +ok: Bool, +acc: +List<Row>) -> Rows:
  match n:
    case 0n: Rows{ok, rows.reversed(acc, Nil{})}
    case 1n+k:
      File{_, _, _, +vc, _, _, +ci, _, _, _, +sk, _, _} = file
      +x = value(vc, bytes)
      +y = value(vc, Index.rest(x))
      +z = value(vc, Index.rest(y))
      +w = value(vc, Index.rest(z))
      +color = colored(ci, cmapped, cmap, Bool.pick(Index, U32.is_eq(ci, 0), Index{True{}, 0, Index.rest(w)}, value(ci, Index.rest(w))))
      +skin = index(sk, Index.rest(color), 4294967295)
      vertices(k, Index.rest(skin), file, cmapped, cmap, ok && Index.ok(x) && Index.ok(y) && Index.ok(z) && Index.ok(w) && Index.ok(color) && Index.ok(skin),
        Con{Row{F32.bits(signed(vc, Index.value(x))), F32.bits(signed(vc, Index.value(y))), F32.bits(signed(vc, Index.value(z))), F32.bits(signed(vc, Index.value(w))), Index.value(color), Index.value(skin), 0, 0}, acc})

# The bones read: each one's parent, its name's offset among the strings
# and the vertices of its position and orientation; `more`: bytes were left
# when the loop ended (the bones the chunk declared were all read).
type Boned is Data:
  Boned{ok: Bool, rows: +List<Row>, count: U32, rest: +List<U32>}

# The bone hierarchy: parent (bi), name (si), position and orientation (vi
# each) of `n` bones, or of those the chunk holds (a truncated chunk keeps
# what it has; a bone cut by the chunk's end is a read outside it).
def bones(n: Nat, bytes: +List<U32>, +file: File, +ok: Bool, +count: U32, +acc: +List<Row>) -> Boned:
  match n bytes:
    case 0n Nil{}: Boned{ok, rows.reversed(acc, Nil{}), count, Nil{}}
    case 0n Con{+b, +rest}: Boned{ok, rows.reversed(acc, Nil{}), count, Con{b, rest}}
    case 1n+_ Nil{}: Boned{ok, rows.reversed(acc, Nil{}), count, Nil{}}
    case 1n+k Con{+b, +rest}:
      File{_, _, _, _, +vi, +si, _, _, +bi, _, _, _, _} = file
      +parent = index(bi, Con{b, rest}, 0)
      +name = index(si, Index.rest(parent), 0)
      +pos = index(vi, Index.rest(name), 0)
      +ori = index(vi, Index.rest(pos), 0)
      bones(k, Index.rest(ori), file, ok && Index.ok(parent) && Index.ok(name) && Index.ok(pos) && Index.ok(ori), (count + 1 : U32),
        Con{Row{Index.value(parent), Index.value(name), Index.value(pos), Index.value(ori), 0, 0, 0, 0}, acc})

# A weight of a skin: without one the bone is undefined; the fifth to the
# eighth only skip their bone index; the others read it.
def weighted(used: Bool, +extra: Bool, +bi: U32, +bytes: +List<U32>) -> Index:
  match used:
    case False{}: Index{True{}, 4294967295, bytes}
    case True{}: Bool.pick(Index, extra, Index{True{}, 4294967295, List.drop(&2, U32, bytes, U32.to_nat(bi))}, index(bi, bytes, 4294967295))

# A skin's bone ids (those of its first four weights; undefined without a
# weight) and what is left of the bytes.
type Skinned is Data:
  Skinned{ok: Bool, ids: +List<U32>, rest: +List<U32>}

def ids(weights: +List<U32>, +j: U32, +bytes: +List<U32>, +bi: U32, +ok: Bool, +acc: +List<U32>) -> Skinned:
  match weights:
    case Nil{}: Skinned{ok, List.reverse(&2, U32, acc), bytes}
    case Con{+w, rest}:
      +read = weighted(U32.is_ne(w, 0), (j >= 4 : U32), bi, bytes)
      ids(rest, (j + 1 : U32), Index.rest(read), bi, ok && Index.ok(read), Bool.pick(+List<U32>, (j < 4 : U32), Con{Index.value(read), acc}, acc))

def Skinned.ok(s: Skinned) -> Bool:
  Skinned{ok, _, _} = s
  ok

def Skinned.ids(s: Skinned) -> +List<U32>:
  Skinned{_, ids, _} = s
  ids

def Skinned.rest(s: Skinned) -> +List<U32>:
  Skinned{_, _, rest} = s
  rest

def nth.first(values: +List<U32>, +fallback: U32) -> U32:
  match values:
    case Con{+v, _}: v
    case Nil{}: fallback

def nth(+values: +List<U32>, +at: U32, +fallback: U32) -> U32:
  nth.first(List.drop(&2, U32, values, U32.to_nat(at)), fallback)

# The weights of a skin: 255 for the one bone of a file with one bone a
# vertex, else nb bytes (not there: a read outside the chunk).
def weights(+nb: U32, +bytes: +List<U32>) -> Skinned:
  Bool.pick(Skinned, U32.is_eq(nb, 1), Skinned{True{}, [255], bytes}, Skinned{(length(taken(bytes, nb), 0) >= nb : U32), taken(bytes, nb), List.drop(&2, U32, bytes, U32.to_nat(nb))})

def skin.read(+w: Skinned, +bi: U32) -> Skinned:
  Skinned{+ok, +values, +rest} = w
  ids(values, 0, rest, bi, ok, Nil{})

# A weight byte as the importer reads it: weights[j]/255 (0 stays 0).
def skin.weight(+b: U32) -> F32:
  Bool.pick(F32, U32.is_eq(b, 0), 0.0, (U32.to_f32(b) / 255.0 : F32))

def skin.divided(+ids: +List<U32>, +w0: F32, +w1: F32, +w2: F32, +w3: F32, +sum: F32) -> Row:
  +scaled = Bool.not(F32.is_eq(sum, 1.0)) && Bool.not(F32.is_eq(sum, 0.0))
  Row{nth(ids, 0, 4294967295), nth(ids, 1, 4294967295), nth(ids, 2, 4294967295), nth(ids, 3, 4294967295),
    F32.bits(Bool.pick(F32, scaled, (w0 / sum : F32), w0)), F32.bits(Bool.pick(F32, scaled, (w1 / sum : F32), w1)),
    F32.bits(Bool.pick(F32, scaled, (w2 / sum : F32), w2)), F32.bits(Bool.pick(F32, scaled, (w3 / sum : F32), w3))}

# A skin as the BONE chunk leaves it: the four bone ids (M3D_UNDEF without a
# weight) and the first four weights over 255, each divided by their sum
# (added in order) unless that is 0 or 1; e..h hold the weights' bits.
def skin.row(+ids: +List<U32>, +bytes: +List<U32>) -> Row:
  +w0 = skin.weight(nth(bytes, 0, 0))
  +w1 = skin.weight(nth(bytes, 1, 0))
  +w2 = skin.weight(nth(bytes, 2, 0))
  +w3 = skin.weight(nth(bytes, 3, 0))
  skin.divided(ids, w0, w1, w2, w3, (((w0 + w1 : F32) + w2 : F32) + w3 : F32))

# The skins: each one's bone ids and weights (skin.row). `n` skins, or
# those the chunk holds.
def skins(n: Nat, bytes: +List<U32>, +nb: U32, +bi: U32, +ok: Bool, +count: U32, +acc: +List<Row>) -> Boned:
  match n bytes:
    case 0n Nil{}: Boned{ok, rows.reversed(acc, Nil{}), count, Nil{}}
    case 0n Con{+b, +rest}: Boned{ok, rows.reversed(acc, Nil{}), count, Con{b, rest}}
    case 1n+_ Nil{}: Boned{ok, rows.reversed(acc, Nil{}), count, Nil{}}
    case 1n+k Con{+b, +rest}:
      +w = weights(nb, Con{b, rest})
      +read = skin.read(w, bi)
      skins(k, Skinned.rest(read), nb, bi, ok && Skinned.ok(read), (count + 1 : U32), Con{skin.row(Skinned.ids(read), Skinned.ids(w)), acc})

# A string of the file: the bytes at raw + 16 + offset up to its NUL. ok:
# the offset is not 0 (a NULL name) and the NUL is among the first 256 bytes
# (inside the file; longer strings are outside the profile).
type Text is Data:
  Text{ok: Bool, bytes: +List<U32>}

def text.go(n: Nat, bytes: +List<U32>, +done: Bool, +acc: +List<U32>) -> Text:
  match n bytes:
    case 1n+k Con{+b, rest}: text.go(k, rest, done || U32.is_eq(b, 0), Bool.pick(+List<U32>, done || U32.is_eq(b, 0), acc, Con{b, acc}))
    case _ _: Text{done, List.reverse(&2, U32, acc)}

def text(+raw: +List<U32>, +offset: U32) -> Text:
  Bool.pick(Text, U32.is_eq(offset, 0), Text{False{}, Nil{}}, text.go(256n, at(raw, (16 + offset : U32)), False{}, Nil{}))

def same(a: +List<U32>, b: +List<U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{+x, xs} Con{+y, ys}: U32.is_eq(x, y) && same(xs, ys)
    case _ _: False{}

# A material property: its type and its value (a color, a number, a float's
# bits; for a map the offset of the texture's name).
type Prop is Data:
  Prop{kind: U32, value: U32}

# A material: its name's offset and its properties; the maps it names
# (texture lookups, in order) are those of kind 128 and above.
type Material is Data:
  Material{name: U32, props: +List<Prop>}

type Props is Data:
  Props{ok: Bool, props: +List<Prop>}

# The format of a property type below 128: 0 a color, 1 a byte, 4 a float, 9 unknown.
def format(+kind: U32) -> U32:
  Bool.pick(U32, (kind <= 2 : U32) || U32.is_eq(kind, 4) || U32.is_eq(kind, 5), 0, Bool.pick(U32, U32.is_eq(kind, 3) || U32.is_eq(kind, 6) || U32.is_eq(kind, 7) || ((kind >= 64 : U32) && (kind <= 68 : U32)), 4,
    Bool.pick(U32, U32.is_eq(kind, 8), 1, 9)))

# One property's value after its type byte.
def prop.value(+kind: U32, +bytes: +List<U32>, +file: File, +cmapped: Bool, +cmap: Store) -> Index:
  File{_, _, _, _, _, +si, +ci, _, _, _, _, _, _} = file
  Bool.pick(Index, (kind >= 128 : U32), index(si, bytes, 0), Bool.pick(Index, U32.is_eq(format(kind), 0),
    colored(ci, cmapped, cmap, Bool.pick(Index, U32.is_eq(ci, 0), Index{True{}, 0, bytes}, value(ci, bytes))), Bool.pick(Index, U32.is_eq(format(kind), 4), value(4, bytes), value(1, bytes))))

def props.turned(xs: +List<Prop>, acc: +List<Prop>) -> +List<Prop>:
  match xs:
    case Nil{}: acc
    case Con{+p, rest}: props.turned(rest, Con{p, acc})

# The properties of a material until the chunk ends; an unknown type ends
# them (the importer leaves the rest of the chunk).
def props(fuel: Nat, bytes: +List<U32>, +file: File, +cmapped: Bool, +cmap: Store, +ok: Bool, +acc: +List<Prop>) -> Props:
  match fuel bytes:
    case _ Nil{}: Props{ok, props.turned(acc, Nil{})}
    case 0n Con{_, _}: Props{False{}, Nil{}}
    case 1n+k Con{+kind, +rest}:
      +read = prop.value(kind, rest, file, cmapped, cmap)
      props(k, Bool.pick(+List<U32>, (kind < 128 : U32) && U32.is_eq(format(kind), 9), Nil{}, Index.rest(read)), file, cmapped, cmap, ok && (Index.ok(read) || ((kind < 128 : U32) && U32.is_eq(format(kind), 9))),
        Bool.pick(+List<Prop>, (kind < 128 : U32) && U32.is_eq(format(kind), 9), acc, Con{Prop{kind, Index.value(read)}, acc}))

# A face: its material (M3D_UNDEF for none), and the indices of its three
# vertices, normals and texture coordinates (M3D_UNDEF where the file gives none).
type Face is Data:
  Face{material: U32, v0: U32, v1: U32, v2: U32, n0: U32, n1: U32, n2: U32, t0: U32, t1: U32, t2: U32}

# A corner of a face: the vertex (vi), the texture coordinate when the
# record's flags have 1 (ti), the normal when they have 2 (vi), and a
# maximum vertex that is skipped when they have 4 (vi).
type Corner is Data:
  Corner{ok: Bool, vertex: U32, texcoord: U32, normal: U32, rest: +List<U32>}

def corner(+bytes: +List<U32>, +flags: U32, +vi: U32, +ti: U32) -> Corner:
  +v = index(vi, bytes, 4294967295)
  +t = Bool.pick(Index, U32.is_ne((flags .&. 1 : U32), 0), index(ti, Index.rest(v), 4294967295), Index{True{}, 4294967295, Index.rest(v)})
  +n = Bool.pick(Index, U32.is_ne((flags .&. 2 : U32), 0), index(vi, Index.rest(t), 4294967295), Index{True{}, 4294967295, Index.rest(t)})
  Corner{Index.ok(v) && Index.ok(t) && Index.ok(n), Index.value(v), Index.value(t), Index.value(n), Bool.pick(+List<U32>, U32.is_ne((flags .&. 4 : U32), 0), List.drop(&2, U32, Index.rest(n), U32.to_nat(vi)), Index.rest(n))}

# A frame of an action: its time and its transforms (bone, position vertex, orientation vertex).
type Frame is Data:
  Frame{msec: U32, transforms: +List<Row>}

# An action: its name's offset, its duration and its frames.
type Action is Data:
  Action{name: U32, duration: U32, frames: +List<Frame>}

type Moves is Data:
  Moves{ok: Bool, rows: +List<Row>, rest: +List<U32>}

# The transforms of a frame: boneid (bi), pos and ori (vi each).
def moves(n: Nat, +bytes: +List<U32>, +bi: U32, +vi: U32, +ok: Bool, +acc: +List<Row>) -> Moves:
  match n:
    case 0n: Moves{ok, rows.reversed(acc, Nil{}), bytes}
    case 1n+k:
      +bone = index(bi, bytes, 0)
      +pos = index(vi, Index.rest(bone), 0)
      +ori = index(vi, Index.rest(pos), 0)
      moves(k, Index.rest(ori), bi, vi, ok && Index.ok(bone) && Index.ok(pos) && Index.ok(ori), Con{Row{Index.value(bone), Index.value(pos), Index.value(ori), 0, 0, 0, 0, 0}, acc})

type Faces is Data:
  Faces{ok: Bool, stop: Bool, material: U32, neednorm: Bool, faces: +List<Face>, lookups: Bool}

def Corner.ok(c: Corner) -> Bool:
  Corner{ok, _, _, _, _} = c
  ok

def Corner.vertex(c: Corner) -> U32:
  Corner{_, vertex, _, _, _} = c
  vertex

def Corner.texcoord(c: Corner) -> U32:
  Corner{_, _, texcoord, _, _} = c
  texcoord

def Corner.normal(c: Corner) -> U32:
  Corner{_, _, _, normal, _} = c
  normal

def Corner.rest(c: Corner) -> +List<U32>:
  Corner{_, _, _, _, rest} = c
  rest

def Text.ok(t: Text) -> Bool:
  Text{ok, _} = t
  ok

def Text.bytes(t: Text) -> +List<U32>:
  Text{_, bytes} = t
  bytes

# The index of the material with a name among those defined so far (their
# names resolved), M3D_UNDEF when there is none.
def material.find(names: +List<Text>, +name: +List<U32>, +at: U32) -> U32:
  match names:
    case Nil{}: 4294967295
    case Con{Text{_, +bytes}, rest}: Bool.pick(U32, same(bytes, name), at, material.find(rest, name, (at + 1 : U32)))

# A "use material" record: no name is no material; a name selects the
# material defined with it (none: M3D_UNDEF). Read as a NULL-safe string.
def used(+raw: +List<U32>, +offset: U32, +names: +List<Text>) -> U32:
  Bool.pick(U32, U32.is_eq(offset, 0), 4294967295, material.find(names, Text.bytes(text(raw, offset)), 0))

# One record of a mesh chunk after its first byte (n corners in the high
# nibble, flags in the low one): 0 corners select the material (flags 0) or
# a parameter (ignored); 3 corners are a face; another count ends the import
# with the faces read so far. kind: 0 a selection, 1 a face, 2 the end.
def record.kind(+head: U32) -> U32:
  Bool.pick(U32, U32.is_eq((head >> 4n : U32), 0), 0, Bool.pick(U32, U32.is_eq((head >> 4n : U32), 3), 1, 2))

# The faces of a mesh chunk, last first. A face cut at a corner's start
# empties the faces and ends the import; one cut inside a corner is a read
# outside the chunk; a material's name must be a string of the file.
def faces(fuel: Nat, bytes: +List<U32>, +file: File, +names: +List<Text>, +state: Faces) -> Faces:
  match fuel bytes:
    case _ Nil{}: state
    case 0n Con{_, _}: Faces{False{}, True{}, 0, False{}, Nil{}, False{}}
    case 1n+k Con{+head, +rest}:
      File{+raw, _, _, _, +vi, +si, _, +ti, _, _, _, _, _} = file
      Faces{+ok, +stop, +material, +neednorm, +list, +lookups} = state
      +kind = Bool.pick(U32, stop, 3, record.kind(head))
      +name = index(si, rest, 0)
      +a = corner(rest, (head .&. 15 : U32), vi, ti)
      +b = corner(Corner.rest(a), (head .&. 15 : U32), vi, ti)
      +c = corner(Corner.rest(b), (head .&. 15 : U32), vi, ti)
      +whole = Corner.ok(a) && Corner.ok(b) && Corner.ok(c)
      +cut = U32.is_eq(kind, 1) && (List.is_empty(&2, U32, rest) || (Corner.ok(a) && List.is_empty(&2, U32, Corner.rest(a))) || (Corner.ok(a) && Corner.ok(b) && List.is_empty(&2, U32, Corner.rest(b))))
      faces(k, Bool.pick(+List<U32>, U32.is_eq(kind, 0), Index.rest(name), Bool.pick(+List<U32>, U32.is_eq(kind, 1) && whole, Corner.rest(c), Nil{})), file, names,
        Faces{ok && (U32.is_ne(kind, 0) || (Index.ok(name) && (U32.is_ne((head .&. 15 : U32), 0) || U32.is_eq(Index.value(name), 0) || Text.ok(text(raw, Index.value(name)))))) && (U32.is_ne(kind, 1) || whole || cut),
          stop || U32.is_eq(kind, 2) || cut,
          Bool.pick(U32, U32.is_eq(kind, 0) && U32.is_eq((head .&. 15 : U32), 0), used(raw, Index.value(name), names), material),
          neednorm || (U32.is_eq(kind, 1) && whole && (U32.is_eq(Corner.normal(a), 4294967295) || U32.is_eq(Corner.normal(b), 4294967295) || U32.is_eq(Corner.normal(c), 4294967295))),
          Bool.pick(+List<Face>, cut, Nil{}, Bool.pick(+List<Face>, U32.is_eq(kind, 1) && whole,
            Con{Face{material, Corner.vertex(a), Corner.vertex(b), Corner.vertex(c), Corner.normal(a), Corner.normal(b), Corner.normal(c), Corner.texcoord(a), Corner.texcoord(b), Corner.texcoord(c)}, list}, list)),
          lookups})

type Frames is Data:
  Frames{ok: Bool, frames: +List<Frame>, count: U32}

def Moves.ok(m: Moves) -> Bool:
  Moves{ok, _, _} = m
  ok

def Moves.rows(m: Moves) -> +List<Row>:
  Moves{_, rows, _} = m
  rows

def Moves.rest(m: Moves) -> +List<U32>:
  Moves{_, _, rest} = m
  rest

def frames.turned(xs: +List<Frame>, acc: +List<Frame>) -> +List<Frame>:
  match xs:
    case Nil{}: acc
    case Con{+f, rest}: frames.turned(rest, Con{f, acc})

# The frames of an action: msec (uint32), numtransform (fc; none without the
# index) and the transforms. The action keeps its declared frame count, so
# a chunk that ends before the last frame leaves frames the importer never
# wrote (count tells how many were read); a count over the profile's 65536
# transforms a frame is refused.
def frames(n: Nat, bytes: +List<U32>, +file: File, +ok: Bool, +count: U32, +acc: +List<Frame>) -> Frames:
  match n bytes:
    case 0n _: Frames{ok, frames.turned(acc, Nil{}), count}
    case 1n+_ Nil{}: Frames{ok, frames.turned(acc, Nil{}), count}
    case 1n+k Con{+b, +rest}:
      File{_, _, _, _, +vi, _, _, _, +bi, _, _, +fc, _} = file
      +msec = value(4, Con{b, rest})
      +number = index(fc, Index.rest(msec), 0)
      +read = moves(U32.to_nat(U32.min(Index.value(number), 65537)), Index.rest(number), bi, vi, True{}, Nil{})
      frames(k, Moves.rest(read), file, ok && Index.ok(msec) && Index.ok(number) && (Index.value(number) <= 65536 : U32) && Moves.ok(read), (count + 1 : U32), Con{Frame{Index.value(msec), Moves.rows(read)}, acc})

# What the chunks give. ok: no read outside a chunk, an array or the
# profile. stop: the importer left its chunk loop.
type Maps is Data:
  Maps{cmapped: Bool, cmap: Store, tmapped: Bool, tmap: Store}

# vertexed: the file had a vertex chunk. The faces are kept last first.
type Shape is Data:
  Shape{vertexed: Bool, vertices: +List<Row>, neednorm: Bool, faces: +List<Face>}

# boned: the importer has a bone array (a chunk that declared at least one bone).
type Rig is Data:
  Rig{boned: Bool, bones: +List<Row>, skins: +List<Row>}

# The materials with their names resolved (same order), the texture names
# their map properties asked for and the names of the inlined assets.
type Looks is Data:
  Looks{materials: +List<Material>, names: +List<Text>, lookups: +List<U32>, assets: +List<U32>}

# stop: 0 while the chunk loop goes on, 1 once it is left (the importer's
# post-processing still runs), 2 once the importer has returned from inside it.
type Got is Data:
  Got{ok: Bool, stop: U32, maps: Maps, shape: Shape, rig: Rig, looks: Looks, actions: +List<Action>}

def empty.store() -> Store:
  Store{Tip{}, 0n, 0}

def got.start(+assets: +List<U32>) -> Got:
  Got{True{}, 0, Maps{False{}, empty.store(), False{}, empty.store()}, Shape{False{}, Nil{}, False{}, Nil{}}, Rig{False{}, Nil{}, Nil{}}, Looks{Nil{}, Nil{}, Nil{}, assets}, Nil{}}

def got.bad(+got: Got) -> Got:
  Got{_, +stop, +maps, +shape, +rig, +looks, +actions} = got
  Got{False{}, stop, maps, shape, rig, looks, actions}

# CMAP: one color map (a second one, or one in a file without color indices, is skipped).
def chunk.cmap(+content: +List<U32>, +file: File, +got: Got) -> Got:
  File{_, _, _, _, _, _, +ci, _, _, _, _, _, _} = file
  Got{+ok, +stop, +maps, +shape, +rig, +looks, +actions} = got
  Maps{+cmapped, +cmap, +tmapped, +tmap} = maps
  Bool.pick(Got, cmapped || U32.is_eq(ci, 0), got, Got{ok, stop, Maps{True{}, stored(colors(content, Nil{})), tmapped, tmap}, shape, rig, looks, actions})

def Rows.ok(r: Rows) -> Bool:
  Rows{ok, _} = r
  ok

def Rows.rows(r: Rows) -> +List<Row>:
  Rows{_, rows} = r
  rows

# TMAP: one texture map (a second one, or one in a file without texture indices, is skipped).
def chunk.tmap(+content: +List<U32>, +file: File, +got: Got) -> Got:
  File{_, _, _, +vc, _, _, _, +ti, _, _, _, _, _} = file
  Got{+ok, +stop, +maps, +shape, +rig, +looks, +actions} = got
  Maps{+cmapped, +cmap, +tmapped, +tmap} = maps
  +read = texcoords(U32.to_nat((length(content, 0) + 1 : U32)), content, vc, True{}, Nil{})
  Bool.pick(Got, tmapped || U32.is_eq(ti, 0), got, Got{ok && Rows.ok(read), stop, Maps{cmapped, cmap, True{}, stored(Rows.rows(read))}, shape, rig, looks, actions})

# VRTS: one vertex list of len/reclen vertices (a second chunk is skipped).
def chunk.vrts(+content: +List<U32>, +file: File, +got: Got) -> Got:
  File{_, _, _, +vc, _, _, +ci, _, _, _, +sk, _, _} = file
  Got{+ok, +stop, +maps, +shape, +rig, +looks, +actions} = got
  Maps{+cmapped, +cmap, _, _} = maps
  Shape{+vertexed, _, +neednorm, +faces} = shape
  +read = vertices(U32.to_nat((length(content, 0) / (ci + sk + 4 * vc) : U32)), content, file, cmapped, cmap, True{}, Nil{})
  Bool.pick(Got, vertexed, got, Got{ok && Rows.ok(read), stop, maps, Shape{True{}, Rows.rows(read), neednorm, faces}, rig, looks, actions})

def Boned.ok(b: Boned) -> Bool:
  Boned{ok, _, _, _} = b
  ok

def Boned.rows(b: Boned) -> +List<Row>:
  Boned{_, rows, _, _} = b
  rows

def Boned.count(b: Boned) -> U32:
  Boned{_, _, count, _} = b
  count

def Boned.rest(b: Boned) -> +List<U32>:
  Boned{_, _, _, rest} = b
  rest

# BONE: the bone count (bi) and the skin count (sk), the bones, then the
# skins. A second chunk (once bones exist) and one in a file without bone
# indices are skipped; one before the vertices ends the chunk loop. Bones
# that the chunk does not hold all of drop the skins. More than 65535 bones
# or 1048576 skins are outside the profile.
def chunk.bone(+content: +List<U32>, +file: File, +got: Got) -> Got:
  File{_, _, _, _, _, _, _, _, +bi, +nb, +sk, _, _} = file
  Got{+ok, +stop, +maps, +shape, +rig, +looks, +actions} = got
  Shape{+vertexed, _, _, _} = shape
  Rig{+boned, _, _} = rig
  +count = index(bi, content, 0)
  +skinned = index(sk, Index.rest(count), 0)
  +read = bones(U32.to_nat(U32.min(Index.value(count), 65536)), Index.rest(skinned), file, True{}, 0, Nil{})
  +whole = U32.is_eq(Boned.count(read), Index.value(count))
  +skin = skins(U32.to_nat(Bool.pick(U32, whole, U32.min(Index.value(skinned), 1048577), 0)), Boned.rest(read), nb, bi, True{}, 0, Nil{})
  Bool.pick(Got, boned || U32.is_eq(bi, 0), got, Bool.pick(Got, Bool.not(vertexed), Got{ok, 1, maps, shape, rig, looks, actions},
    Got{ok && Index.ok(count) && Index.ok(skinned) && (Index.value(count) <= 65535 : U32) && (Index.value(skinned) <= 1048576 : U32) && Boned.ok(read) && Boned.ok(skin), stop, maps, shape,
      Rig{U32.is_ne(Index.value(count), 0), Boned.rows(read), Boned.rows(skin)}, looks, actions}))

def Props.ok(p: Props) -> Bool:
  Props{ok, _} = p
  ok

def Props.props(p: Props) -> +List<Prop>:
  Props{_, props} = p
  props

# The properties that stay (those below 128), in order.
def kept(list: +List<Prop>, +acc: +List<Prop>) -> +List<Prop>:
  match list:
    case Nil{}: props.turned(acc, Nil{})
    case Con{Prop{+kind, +value}, rest}: kept(rest, Bool.pick(+List<Prop>, (kind < 128 : U32), Con{Prop{kind, value}, acc}, acc))

def kept.count(list: +List<Prop>, +acc: U32) -> U32:
  match list:
    case Nil{}: acc
    case Con{Prop{+kind, _}, rest}: kept.count(rest, Bool.pick(U32, (kind < 128 : U32), (acc + 1 : U32), acc))

def named.any(names: +List<U32>, +raw: +List<U32>, +name: +List<U32>) -> Bool:
  match names:
    case Nil{}: False{}
    case Con{+offset, rest}: same(Text.bytes(text(raw, offset)), name) || named.any(rest, raw, name)

# The texture names a material's maps ask for (_m3d_gettx): none for a
# NULL or empty name. ok: every name is a string of the file and none is an
# inlined asset's (decoding one is outside the profile).
type Asked is Data:
  Asked{ok: Bool, names: +List<U32>}

def asked(list: +List<Prop>, +raw: +List<U32>, +assets: +List<U32>, +state: Asked) -> Asked:
  match list:
    case Nil{}: state
    case Con{Prop{+kind, +value}, rest}:
      Asked{+ok, +names} = state
      +name = text(raw, value)
      +wanted = (kind >= 128 : U32) && U32.is_ne(value, 0) && Text.ok(name) && Bool.not(List.is_empty(&2, U32, Text.bytes(name)))
      asked(rest, raw, assets, Asked{ok && ((kind < 128 : U32) || U32.is_eq(value, 0) || (Text.ok(name) && Bool.not(named.any(assets, raw, Text.bytes(name))))), Bool.pick(+List<U32>, wanted, Con{value, names}, names)})

def Asked.ok(a: Asked) -> Bool:
  Asked{ok, _} = a
  ok

def Asked.names(a: Asked) -> +List<U32>:
  Asked{_, names} = a
  names

# MTRL: a material's name and its properties. A name defined before is
# skipped (errcode only); a NULL name is skipped when no material exists
# (the importer compares it with the existing ones otherwise).
def chunk.mtrl(+content: +List<U32>, +file: File, +got: Got) -> Got:
  File{+raw, _, _, _, _, +si, _, _, _, _, _, _, _} = file
  Got{+ok, +stop, +maps, +shape, +rig, +looks, +actions} = got
  Maps{+cmapped, +cmap, _, _} = maps
  Looks{+materials, +names, +lookups, +assets} = looks
  +name = index(si, content, 0)
  +named = text(raw, Index.value(name))
  +read = props(U32.to_nat((length(content, 0) + 1 : U32)), Index.rest(name), file, cmapped, cmap, True{}, Nil{})
  +wanted = asked(Props.props(read), raw, assets, Asked{True{}, Nil{}})
  +fresh = Text.ok(named) && U32.is_eq(material.find(names, Text.bytes(named), 0), 4294967295)
  Bool.pick(Got, Bool.not(Index.ok(name)) || (Bool.not(Text.ok(named)) && Bool.not(U32.is_eq(Index.value(name), 0) && List.is_empty(&2, Text, names))), got.bad(got), Bool.pick(Got, Bool.not(fresh), got,
    Got{ok && Props.ok(read) && Asked.ok(wanted) && (kept.count(Props.props(read), 0) <= (length(content, 0) / 2) : U32), stop, maps, shape, rig,
      Looks{List.append(&2, Material, materials, [Material{Index.value(name), kept(Props.props(read), Nil{})}]), List.append(&2, Text, names, [named]), List.append(&2, U32, lookups, List.reverse(&2, U32, Asked.names(wanted))), assets}, actions}))

def Faces.ok(f: Faces) -> Bool:
  Faces{ok, _, _, _, _, _} = f
  ok

def Faces.stop(f: Faces) -> Bool:
  Faces{_, stop, _, _, _, _} = f
  stop

def Faces.neednorm(f: Faces) -> Bool:
  Faces{_, _, _, neednorm, _, _} = f
  neednorm

def Faces.faces(f: Faces) -> +List<Face>:
  Faces{_, _, _, _, faces, _} = f
  faces

# MESH: faces added to those read so far; the material starts undefined in
# each chunk. A record that is not a triangle, and a face cut at a corner,
# make the importer return (without its post-processing).
def chunk.mesh(+content: +List<U32>, +file: File, +got: Got) -> Got:
  Got{+ok, +stop, +maps, +shape, +rig, +looks, +actions} = got
  Shape{+vertexed, +vertices, +neednorm, +list} = shape
  Looks{_, +names, _, _} = looks
  +read = faces(U32.to_nat((length(content, 0) + 1 : U32)), content, file, names, Faces{True{}, False{}, 4294967295, neednorm, list, False{}})
  Got{ok && Faces.ok(read), Bool.pick(U32, Faces.stop(read), 2, stop), maps, Shape{vertexed, vertices, Faces.neednorm(read), Faces.faces(read)}, rig, looks, actions}

def Frames.ok(f: Frames) -> Bool:
  Frames{ok, _, _} = f
  ok

def Frames.frames(f: Frames) -> +List<Frame>:
  Frames{_, frames, _} = f
  frames

def Frames.count(f: Frames) -> U32:
  Frames{_, _, count} = f
  count

# ACTN: an action's name (si), its frame count (uint16; none drops the
# action), its duration (uint32) and its frames, all of which the chunk must
# hold (the importer keeps the declared count and later reads frames it
# never wrote).
def chunk.actn(+content: +List<U32>, +file: File, +got: Got) -> Got:
  File{_, _, _, _, _, +si, _, _, _, _, _, _, _} = file
  Got{+ok, +stop, +maps, +shape, +rig, +looks, +actions} = got
  +name = index(si, content, 0)
  +count = value(2, Index.rest(name))
  +duration = value(4, Index.rest(count))
  +read = frames(U32.to_nat(Index.value(count)), Index.rest(duration), file, True{}, 0, Nil{})
  Bool.pick(Got, Bool.not(Index.ok(name) && Index.ok(count)), got.bad(got), Bool.pick(Got, U32.is_eq(Index.value(count), 0), got,
    Got{ok && Index.ok(duration) && Frames.ok(read) && U32.is_eq(Frames.count(read), Index.value(count)), stop, maps, shape, rig, looks, Con{Action{Index.value(name), Index.value(duration), Frames.frames(read)}, actions}}))

# A chunk by its magic: procedural surfaces, voxels, shapes and labels are
# outside the profile; inlined assets and unknown chunks are kept aside by
# the importer (nothing here).
def chunk(name: U32, +content: +List<U32>, +file: File, +got: Got) -> Got:
  match name:
    case 1346456899: chunk.cmap(content, file, got)
    case 1346456916: chunk.tmap(content, file, got)
    case 1398035030: chunk.vrts(content, file, got)
    case 1162760002: chunk.bone(content, file, got)
    case 1280463949: chunk.mtrl(content, file, got)
    case 1213416781: chunk.mesh(content, file, got)
    case 1314145089: chunk.actn(content, file, got)
    case 1129271888: got.bad(got)
    case 1415073622: got.bad(got)
    case 1146638166: got.bad(got)
    case 1162889299: got.bad(got)
    case 1397506636: got.bad(got)
    case _: got

def Got.stop(got: Got) -> U32:
  Got{_, stop, _, _, _, _, _} = got
  stop

# while (chunk < end && !OMD3): a chunk's length under its header's 8 bytes
# or reaching the end leaves the loop; `left` bytes remain to the end. The
# magic needs 4 bytes and the length 8 (fewer: a read past the buffer).
def chunks(fuel: Nat, bytes: +List<U32>, +left: U32, +file: File, +got: Got) -> Got:
  match fuel bytes:
    case _ Nil{}: got
    case 0n Con{_, _}: got.bad(got)
    case 1n+k Con{+b, +rest}:
      +name = word(Con{b, rest})
      +len = word(at(Con{b, rest}, 4))
      +last = U32.is_eq(name, 860114255) && (left >= 4 : U32)
      +read = Bool.not(last) && (left >= 8 : U32) && (len >= 8 : U32) && (len < left : U32)
      +handled = Bool.pick(Got, read, chunk(name, taken(at(Con{b, rest}, 8), (len - 8 : U32)), file, got), Bool.pick(Got, last || (left >= 8 : U32), got, got.bad(got)))
      chunks(k, Bool.pick(+List<U32>, read && U32.is_eq(Got.stop(handled), 0), at(Con{b, rest}, len), Nil{}), (left - len : U32), file, handled)

type Assets is Data:
  Assets{ok: Bool, names: +List<U32>}

# The importer's first pass: the names of the inlined assets (ASET chunks
# with contents after their name), under the same loop.
def assets(fuel: Nat, bytes: +List<U32>, +left: U32, +si: U32, +state: Assets) -> Assets:
  match fuel bytes:
    case _ Nil{}: state
    case 0n Con{_, _}: Assets{False{}, Nil{}}
    case 1n+k Con{+b, +rest}:
      Assets{+ok, +names} = state
      +name = word(Con{b, rest})
      +len = word(at(Con{b, rest}, 4))
      +last = U32.is_eq(name, 860114255) && (left >= 4 : U32)
      +read = Bool.not(last) && (left >= 8 : U32) && (len >= 8 : U32) && (len < left : U32)
      +asset = read && U32.is_eq(name, 1413829441) && U32.is_ne(len, (8 + si : U32))
      +offset = index(si, at(Con{b, rest}, 8), 0)
      assets(k, Bool.pick(+List<U32>, read, at(Con{b, rest}, len), Nil{}), (left - len : U32), si,
        Assets{ok && (last || (left >= 8 : U32)) && (Bool.not(asset) || Index.ok(offset)), Bool.pick(+List<U32>, asset, Con{Index.value(offset), names}, names)})

def parsed.with(+found: Assets, +file: File) -> Got:
  Assets{+ok, +names} = found
  File{+raw, +size, _, _, _, _, _, _, _, _, _, _, +first} = file
  Bool.pick(Got, ok, chunks(U32.to_nat((size / 8 + 2 : U32)), at(raw, first), (size - U32.min(first, size) : U32), file, got.start(names)), got.bad(got.start(Nil{})))

# The chunks of an opened file.
def parsed(+file: File) -> Got:
  File{+raw, +size, _, _, _, +si, _, _, _, _, _, _, +first} = file
  parsed.with(assets(U32.to_nat((size / 8 + 2 : U32)), at(raw, first), (size - U32.min(first, size) : U32), si, Assets{True{}, Nil{}}), file)

# A mesh LoadM3D builds for a run of faces of one material: meshMaterial
# (the material's index + 1, 0 for none), three vertices a face, texcoords
# (v turned over), normals, and colors when the run has no material or one
# of its vertices has no color.
# joints and weights: the boneIndices and boneWeights of a file with bones
# and skins, four a vertex (none otherwise).
type Mesh is Data:
  Mesh{material: U32, faces: U32, vertices: +List<F32>, texcoords: +List<F32>, normals: +List<F32>, colored: Bool, colors: +List<U32>, joints: +List<U32>, weights: +List<F32>}

# The run being built: its values last first; vcolor: a vertex without a color was seen.
type Run is Data:
  Run{ok: Bool, started: Bool, material: U32, faces: U32, vcolor: Bool, vs: +List<F32>, ts: +List<F32>, ns: +List<F32>, cs: +List<U32>, done: +List<Mesh>, bs: +List<U32>, ws: +List<F32>}

# What LoadM3D's skinning reads: whether the file has bones and skins
# (m3d->numbone && m3d->numskin), the bone count and the skins.
type SkinSet is Data:
  SkinSet{skinned: Bool, count: U32, skins: Store}

def floats.turned(xs: +List<F32>, acc: +List<F32>) -> +List<F32>:
  match xs:
    case Nil{}: acc
    case Con{+x, rest}: floats.turned(rest, Con{x, acc})

def words.turned(xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}: acc
    case Con{+x, rest}: words.turned(rest, Con{x, acc})

# The run closed: a mesh, added to those done (last first).
def run.done(+run: Run) -> +List<Mesh>:
  Run{_, +started, +material, +faces, +vcolor, +vs, +ts, +ns, +cs, +done, +bs, +ws} = run
  Bool.pick(+List<Mesh>, started, Con{Mesh{(material + 1 : U32), faces, floats.turned(vs, Nil{}), floats.turned(ts, Nil{}), floats.turned(ns, Nil{}), U32.is_eq(material, 4294967295) || vcolor, words.turned(cs, Nil{}),
    words.turned(bs, Nil{}), floats.turned(ws, Nil{})}, done}, done)

# A corner's color bytes, last first onto the colors: the vertex color's
# four bytes when its alpha is not 0, else the mesh's default (255 without
# a material, 0 with one).
def corner.color(+color: U32, +fill: U32, +cs: +List<U32>) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_ne((color .&. 4278190080 : U32), 0), Con{(color >> 24n : U32), Con{((color >> 16n) .&. 255 : U32), Con{((color >> 8n) .&. 255 : U32), Con{(color .&. 255 : U32), cs}}}},
    Con{fill, Con{fill, Con{fill, Con{fill, cs}}}})

def Row.a(r: Row) -> U32:
  Row{a, _, _, _, _, _, _, _} = r
  a

def Row.b(r: Row) -> U32:
  Row{_, b, _, _, _, _, _, _} = r
  b

def Row.c(r: Row) -> U32:
  Row{_, _, c, _, _, _, _, _} = r
  c

def Row.d(r: Row) -> U32:
  Row{_, _, _, d, _, _, _, _} = r
  d

def Row.e(r: Row) -> U32:
  Row{_, _, _, _, e, _, _, _} = r
  e

def Row.f(r: Row) -> U32:
  Row{_, _, _, _, _, f, _, _} = r
  f

# A corner's boneIndices, last first onto the list: its skin's four bone
# ids as unsigned chars, or the no-bone bone (numbone) and zeros for a
# vertex without a skin that exists; nothing without bones and skins.
def corner.ids(+set: SkinSet, +skinid: U32, +bs: +List<U32>) -> +List<U32>:
  SkinSet{+skinned, +count, +skins} = set
  +k = row(skins, skinid)
  Bool.pick(+List<U32>, skinned, Bool.pick(+List<U32>, U32.is_ne(skinid, 4294967295) && (skinid < Store.count(skins) : U32),
    Con{(Row.d(k) .&. 255 : U32), Con{(Row.c(k) .&. 255 : U32), Con{(Row.b(k) .&. 255 : U32), Con{(Row.a(k) .&. 255 : U32), bs}}}}, Con{0, Con{0, Con{0, Con{(count .&. 255 : U32), bs}}}}), bs)

def Row.g(r: Row) -> U32:
  Row{_, _, _, _, _, _, g, _} = r
  g

def Row.h(r: Row) -> U32:
  Row{_, _, _, _, _, _, _, h} = r
  h

# A corner's boneWeights, as corner.ids: the skin's weights, or 1 and zeros.
def corner.weights(+set: SkinSet, +skinid: U32, +ws: +List<F32>) -> +List<F32>:
  SkinSet{+skinned, _, +skins} = set
  +k = row(skins, skinid)
  Bool.pick(+List<F32>, skinned, Bool.pick(+List<F32>, U32.is_ne(skinid, 4294967295) && (skinid < Store.count(skins) : U32),
    Con{float(Row.h(k)), Con{float(Row.g(k)), Con{float(Row.f(k)), Con{float(Row.e(k)), ws}}}}, Con{0.0, Con{0.0, Con{0.0, Con{1.0, ws}}}}), ws)

# A face added to the run: its vertices times the scale, its colors, its
# texcoords (u and 1 - v; zeros without texture coordinates) and its normals
# (zeros without). ok: every index it reads is inside its array.
def face.added(+face: Face, +scale: F32, +vertices: Store, +tmap: Store, +set: SkinSet, +run: Run) -> Run:
  Face{_, +v0, +v1, +v2, +n0, +n1, +n2, +t0, +t1, +t2} = face
  Run{+ok, +started, +material, +faces, +vcolor, +vs, +ts, +ns, +cs, +done, +bs, +ws} = run
  +a = row(vertices, v0)
  +b = row(vertices, v1)
  +c = row(vertices, v2)
  +fill = Bool.pick(U32, U32.is_eq(material, 4294967295), 255, 0)
  +textured = U32.is_ne(t0, 4294967295)
  +shaded = U32.is_ne(n0, 4294967295)
  Run{ok && (v0 < Store.count(vertices) : U32) && (v1 < Store.count(vertices) : U32) && (v2 < Store.count(vertices) : U32) &&
      (Bool.not(textured) || ((t0 < Store.count(tmap) : U32) && (t1 < Store.count(tmap) : U32) && (t2 < Store.count(tmap) : U32))) &&
      (Bool.not(shaded) || ((n0 < Store.count(vertices) : U32) && (n1 < Store.count(vertices) : U32) && (n2 < Store.count(vertices) : U32))),
    started, material, (faces + 1 : U32), vcolor || U32.is_eq(Row.e(a), 0) || U32.is_eq(Row.e(b), 0) || U32.is_eq(Row.e(c), 0),
    Con{(float(Row.c(c)) * scale : F32), Con{(float(Row.b(c)) * scale : F32), Con{(float(Row.a(c)) * scale : F32), Con{(float(Row.c(b)) * scale : F32), Con{(float(Row.b(b)) * scale : F32), Con{(float(Row.a(b)) * scale : F32),
      Con{(float(Row.c(a)) * scale : F32), Con{(float(Row.b(a)) * scale : F32), Con{(float(Row.a(a)) * scale : F32), vs}}}}}}}}},
    Bool.pick(+List<F32>, textured, Con{(1.0 - float(Row.b(row(tmap, t2))) : F32), Con{float(Row.a(row(tmap, t2))), Con{(1.0 - float(Row.b(row(tmap, t1))) : F32), Con{float(Row.a(row(tmap, t1))), Con{(1.0 - float(Row.b(row(tmap, t0))) : F32),
      Con{float(Row.a(row(tmap, t0))), ts}}}}}}, Con{0.0, Con{0.0, Con{0.0, Con{0.0, Con{0.0, Con{0.0, ts}}}}}}),
    Bool.pick(+List<F32>, shaded, Con{float(Row.c(row(vertices, n2))), Con{float(Row.b(row(vertices, n2))), Con{float(Row.a(row(vertices, n2))), Con{float(Row.c(row(vertices, n1))), Con{float(Row.b(row(vertices, n1))), Con{float(Row.a(row(vertices, n1))),
      Con{float(Row.c(row(vertices, n0))), Con{float(Row.b(row(vertices, n0))), Con{float(Row.a(row(vertices, n0))), ns}}}}}}}}}, Con{0.0, Con{0.0, Con{0.0, Con{0.0, Con{0.0, Con{0.0, Con{0.0, Con{0.0, Con{0.0, ns}}}}}}}}}),
    corner.color(Row.e(c), fill, corner.color(Row.e(b), fill, corner.color(Row.e(a), fill, cs))), done,
    corner.ids(set, Row.f(c), corner.ids(set, Row.f(b), corner.ids(set, Row.f(a), bs))), corner.weights(set, Row.f(c), corner.weights(set, Row.f(b), corner.weights(set, Row.f(a), ws)))}

def Run.material(run: Run) -> U32:
  Run{_, _, material, _, _, _, _, _, _, _, _, _} = run
  material

def Run.started(run: Run) -> Bool:
  Run{_, started, _, _, _, _, _, _, _, _, _, _} = run
  started

def Run.ok(run: Run) -> Bool:
  Run{ok, _, _, _, _, _, _, _, _, _, _, _} = run
  ok

# A new run after the one that ends where the material changes.
def run.next(+run: Run, +material: U32) -> Run:
  Run{Run.ok(run), True{}, material, 0, False{}, Nil{}, Nil{}, Nil{}, Nil{}, run.done(run), Nil{}, Nil{}}

# The faces in order: a mesh a run of one material.
def runs(list: +List<Face>, +scale: F32, +vertices: Store, +tmap: Store, +set: SkinSet, +run: Run) -> Run:
  match list:
    case Nil{}: run
    case Con{Face{+material, +v0, +v1, +v2, +n0, +n1, +n2, +t0, +t1, +t2}, rest}:
      runs(rest, scale, vertices, tmap, set, face.added(Face{material, v0, v1, v2, n0, n1, n2, t0, t1, t2}, scale, vertices, tmap, set,
        Bool.pick(Run, Run.started(run) && U32.is_eq(Run.material(run), material), run, run.next(run, material))))

def faces.turned(xs: +List<Face>, acc: +List<Face>) -> +List<Face>:
  match xs:
    case Nil{}: acc
    case Con{+f, rest}: faces.turned(rest, Con{f, acc})

def meshes.turned(xs: +List<Mesh>, acc: +List<Mesh>) -> +List<Mesh>:
  match xs:
    case Nil{}: acc
    case Con{+m, rest}: meshes.turned(rest, Con{m, acc})

type Built is Data:
  Built{ok: Bool, meshes: +List<Mesh>}

def built.of(+run: Run) -> Built:
  Built{Run.ok(run), meshes.turned(run.done(run), Nil{})}

def skin.bumped(r: Array<U32> & U32, +i: U32) -> Array<U32>:
  (a, +n) = r
  Array.set(U32, a, i, (n + 1 : U32))

# How many of the ids name each skin (ids below the skin count only).
def skin.counted(+ids: +List<U32>, a: Array<U32>) -> Array<U32>:
  match ids:
    case Nil{}: a
    case Con{+i, rest}: skin.counted(rest, skin.bumped(Array.get(U32, a, i), i))

# The vertices' skin ids below the skin count (vertex[i].skinid < numskin).
def skin.ids(vertices: +List<Row>, +total: U32, +acc: +List<U32>) -> +List<U32>:
  match vertices:
    case Nil{}: acc
    case Con{Row{_, _, _, _, _, +skinid, _, _}, rest}: skin.ids(rest, total, Bool.pick(+List<U32>, (skinid < total : U32), Con{skinid, acc}, acc))

def skin.kept(+id: U32, +w: U32) -> Bool:
  U32.is_ne(id, 4294967295) && (float(w) > 0.0 : F32)

# The importer's post-processing for one vertex of a skin: the weights from
# the first, up to the first undefined bone or weight that is not above 0,
# each divided by their sum.
def skin.again(+row: Row) -> Row:
  Row{+a, +b, +c, +d, +e, +f, +g, +h} = row
  +k0 = skin.kept(a, e)
  +k1 = k0 && skin.kept(b, f)
  +k2 = k1 && skin.kept(c, g)
  +k3 = k2 && skin.kept(d, h)
  +sum = ((((0.0 + Bool.pick(F32, k0, float(e), 0.0) : F32) + Bool.pick(F32, k1, float(f), 0.0) : F32) + Bool.pick(F32, k2, float(g), 0.0) : F32) + Bool.pick(F32, k3, float(h), 0.0) : F32)
  Row{a, b, c, d, Bool.pick(U32, k0, F32.bits((float(e) / sum : F32)), e), Bool.pick(U32, k1, F32.bits((float(f) / sum : F32)), f),
    Bool.pick(U32, k2, F32.bits((float(g) / sum : F32)), g), Bool.pick(U32, k3, F32.bits((float(h) / sum : F32)), h)}

def skin.times(n: Nat, +row: Row) -> Row:
  match n:
    case 0n: row
    case 1n+k: skin.times(k, skin.again(row))

def skin.each(list: +List<Row>, counts: List<U32>, +acc: +List<Row>) -> +List<Row>:
  match list counts:
    case Con{+row, rest} Con{+n, more}: skin.each(rest, more, Con{skin.times(U32.to_nat(n), row), acc})
    case _ _: rows.reversed(acc, Nil{})

# m3d_load's "weight cross-reference": every vertex whose skin exists
# normalizes that skin's weights again (skin.again), so a skin is
# normalized once per vertex that names it.
def skins.normalized(+list: +List<Row>, +vertices: +List<Row>) -> +List<Row>:
  +total = rows.count(list, 0)
  skin.each(list, Array.to_list(~U32, skin.counted(skin.ids(vertices, total, Nil{}), Array.new(U32, depth(total), 0))), Nil{})

# LoadM3D's meshes from what the chunks gave: with bones and skins, each
# corner's skin (its normalized weights, the importer's post-processing
# applied unless it returned early) or the no-bone bone.
def built(+got: Got, +scale: F32) -> Built:
  Got{_, +stop, +maps, +shape, +rig, _, _} = got
  Maps{_, _, _, +tmap} = maps
  Shape{_, +vertices, _, +faces} = shape
  Rig{_, +rig_bones, +rig_skins} = rig
  +numbone = rows.count(rig_bones, 0)
  +skinned = U32.is_ne(numbone, 0) && Bool.not(List.is_empty(&2, Row, rig_skins))
  +final = Bool.pick(+List<Row>, U32.is_ne(stop, 2) && skinned && Bool.not(List.is_empty(&2, Row, vertices)), skins.normalized(rig_skins, vertices), rig_skins)
  built.of(runs(faces.turned(faces, Nil{}), scale, stored(vertices), tmap, SkinSet{skinned, numbone, stored(final)},
    Run{True{}, False{}, 0, 0, False{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}))

# A pose under its parent's, as LoadM3D composes the bind pose (and
# LoadModelAnimationsM3D a keyframe): the rotation under the parent's, the
# translation turned by it and moved, the scale multiplied.
def under(+child: GA.Transform, +parent: GA.Transform) -> GA.Transform:
  GA.Transform{+translation, +rotation, +scale} = child
  GA.Transform{+pt, +pr, +ps} = parent
  GA.Transform{M.Vector3.add(M.Vector3.rotate_by_quaternion(translation, pr), pt), M.Quaternion.multiply(pr, rotation), M.Vector3.multiply(scale, ps)}

# A bone that is its own parent: each statement reads what the one before wrote.
def under.self.moved(+moved: M.Vector3, +rotation: M.Vector4, +scale: M.Vector3) -> GA.Transform:
  GA.Transform{M.Vector3.add(moved, moved), rotation, M.Vector3.multiply(scale, scale)}

def under.self.turned(+translation: M.Vector3, +rotation: M.Vector4, +scale: M.Vector3) -> GA.Transform:
  under.self.moved(M.Vector3.rotate_by_quaternion(translation, rotation), rotation, scale)

def under.self(+item: GA.Transform) -> GA.Transform:
  GA.Transform{+translation, +rotation, +scale} = item
  under.self.turned(translation, M.Quaternion.multiply(rotation, rotation), scale)

# The zeros a pose the loader has not written yet holds (its arrays are cleared).
def unset() -> GA.Transform:
  GA.Transform{M.Vector3{0.0, 0.0, 0.0}, M.Vector4{0.0, 0.0, 0.0, 0.0}, M.Vector3{0.0, 0.0, 0.0}}

def pose.pick(items: +List<GA.Transform>, +fallback: GA.Transform) -> GA.Transform:
  match items:
    case Con{+item, _}: item
    case Nil{}: fallback

# A bone's own transform: its position vertex times the scale, its
# orientation vertex normalized, a scale of 1.
def own(+position: Row, +orientation: Row, +scale: F32) -> GA.Transform:
  GA.Transform{M.Vector3{(float(Row.a(position)) * scale : F32), (float(Row.b(position)) * scale : F32), (float(Row.c(position)) * scale : F32)},
    M.Quaternion.normalize(M.Vector4{float(Row.a(orientation)), float(Row.b(orientation)), float(Row.c(orientation)), float(Row.d(orientation))}), M.Vector3{1.0, 1.0, 1.0}}

# A bone in model space: a negative parent leaves it; a parent before it is
# taken composed (done, last first), itself as it becomes, one after it
# (the no-bone slot included) as the zeros it still is.
def placed(+item: GA.Transform, +parent: U32, +at: U32, +done: +List<GA.Transform>) -> GA.Transform:
  Bool.pick(GA.Transform, (parent >= 2147483648 : U32), item, Bool.pick(GA.Transform, U32.is_eq(parent, at), under.self(item),
    under(item, Bool.pick(GA.Transform, (parent < at : U32), pose.pick(List.drop(&2, GA.Transform, done, U32.to_nat(U32.min(((at - 1 : U32) - parent : U32), at))), unset()), unset()))))

type Skel is Data:
  Skel{ok: Bool, bones: +List<GA.Bone>, bind: +List<GA.Transform>}

def bones.turned(xs: +List<GA.Bone>, acc: +List<GA.Bone>) -> +List<GA.Bone>:
  match xs:
    case Nil{}: acc
    case Con{+b, rest}: bones.turned(rest, Con{b, acc})

# "NO BONE".
def nobone() -> +List<U32>:
  [78, 79, 32, 66, 79, 78, 69]

# The skeleton: the bones with the first 31 bytes of their names and their
# bind pose in model space, then the no-bone bone. ok: every name is a
# string of the file, every vertex a bone names exists and every parent is
# negative or a slot of the skeleton.
def skeleton(list: +List<Row>, +at: U32, +count: U32, +raw: +List<U32>, +vertices: Store, +scale: F32, +ok: Bool, +bones: +List<GA.Bone>, +done: +List<GA.Transform>) -> Skel:
  match list:
    case Nil{}: Skel{ok, bones.turned(Con{GA.Bone{nobone(), 4294967295}, bones}, Nil{}), List.reverse(&2, GA.Transform, Con{GA.Transform{M.Vector3{0.0, 0.0, 0.0}, M.Vector4{0.0, 0.0, 0.0, 1.0}, M.Vector3{1.0, 1.0, 1.0}}, done})}
    case Con{Row{+parent, +name, +pos, +ori, _, _, _, _}, rest}:
      skeleton(rest, (at + 1 : U32), count, raw, vertices, scale, ok && Text.ok(text(raw, name)) && (pos < Store.count(vertices) : U32) && (ori < Store.count(vertices) : U32) && ((parent >= 2147483648 : U32) || (parent <= count : U32)),
        Con{GA.Bone{taken(Text.bytes(text(raw, name)), 31), parent}, bones}, Con{placed(own(row(vertices, pos), row(vertices, ori), scale), parent, at, done), done})

# LoadM3D's result: Refused (a read outside a buffer, or outside the
# profile), Empty (no model or no faces: the empty model), or the meshes
# (count of them: the materials' when that is more than the runs, the rest
# empty), the materials and the skeleton (no bones without a bone chunk).
type Loaded is Data:
  Refused{}
  Empty{}
  Model{meshes: +List<Mesh>, count: U32, materials: +List<Material>, skeleton: GA.Skeleton}

def rows.length(xs: +List<Row>, +acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case Con{_, rest}: rows.length(rest, (acc + 1 : U32))

def meshes.count(xs: +List<Mesh>, +acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case Con{_, rest}: meshes.count(rest, (acc + 1 : U32))

def materials.count(xs: +List<Material>, +acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case Con{_, rest}: materials.count(rest, (acc + 1 : U32))

# Every skin's bones exist, and every bone's parent is undefined or a bone:
# what the importer's cross-reference and bone matrices index when the file
# has bones, skins and vertices.
def skins.inside(list: +List<Row>, +count: U32) -> Bool:
  match list:
    case Nil{}: True{}
    case Con{Row{+a, +b, +c, +d, _, _, _, _}, rest}:
      (U32.is_eq(a, 4294967295) || ((a < count : U32) && (U32.is_eq(b, 4294967295) || ((b < count : U32) && (U32.is_eq(c, 4294967295) || ((c < count : U32) && (U32.is_eq(d, 4294967295) || (d < count : U32)))))))) && skins.inside(rest, count)

def parents.inside(list: +List<Row>, +count: U32) -> Bool:
  match list:
    case Nil{}: True{}
    case Con{Row{+parent, _, _, _, _, _, _, _}, rest}: (U32.is_eq(parent, 4294967295) || (parent < count : U32)) && parents.inside(rest, count)

# Every bone's position and orientation vertices exist (the importer's bone matrices read them).
def bones.inside(list: +List<Row>, +count: U32) -> Bool:
  match list:
    case Nil{}: True{}
    case Con{Row{_, _, +pos, +ori, _, _, _, _}, rest}: (pos < count : U32) && (ori < count : U32) && bones.inside(rest, count)

def skel.of(+found: Skel) -> GA.Skeleton:
  Skel{_, +bones, +bind} = found
  GA.Skeleton{bones, bind}

def Skel.ok(found: Skel) -> Bool:
  Skel{ok, _, _} = found
  ok

def Built.ok(b: Built) -> Bool:
  Built{ok, _} = b
  ok

def Built.meshes(b: Built) -> +List<Mesh>:
  Built{_, meshes} = b
  meshes

def model.made(+made: Built, +found: Skel, +boned: Bool, +materials: +List<Material>) -> Loaded:
  Bool.pick(Loaded, Built.ok(made) && (Bool.not(boned) || Skel.ok(found)), Model{Built.meshes(made), U32.max(meshes.count(Built.meshes(made), 0), U32.max(materials.count(materials, 0), 1)), materials,
    Bool.pick(GA.Skeleton, boned, skel.of(found), GA.Skeleton{Nil{}, Nil{}})}, Refused{})

# What the chunks gave is inside the profile: nothing read outside, no
# texture asked for; the importer's post-processing (when it did not return
# early) needs no generated normals and, for a file with bones, skins and
# vertices, indexes only bones and vertices that exist.
def fine(+got: Got) -> Bool:
  Got{+ok, +stop, _, +shape, +rig, +looks, _} = got
  Shape{_, +vertices, +neednorm, +faces} = shape
  Rig{_, +bones, +skins} = rig
  Looks{_, _, +lookups, _} = looks
  ok && List.is_empty(&2, U32, lookups) && Bool.not(U32.is_ne(stop, 2) && neednorm && Bool.not(List.is_empty(&2, Face, faces))) &&
    Bool.not(U32.is_ne(stop, 2) && Bool.not(List.is_empty(&2, Row, bones)) && Bool.not(List.is_empty(&2, Row, skins)) && Bool.not(List.is_empty(&2, Row, vertices)) &&
      Bool.not(skins.inside(skins, rows.length(bones, 0)) && parents.inside(bones, rows.length(bones, 0)) && bones.inside(bones, rows.length(vertices, 0))))

# The model of what the chunks gave.
def model.got(+got: Got, +file: File) -> Loaded:
  Got{_, _, _, +shape, +rig, +looks, _} = got
  Shape{_, +vertices, _, +faces} = shape
  Rig{_, +bones, _} = rig
  Looks{+materials, _, _, _} = looks
  File{+raw, _, +scale, _, _, _, _, _, _, _, _, _, _} = file
  +count = rows.length(bones, 0)
  Bool.pick(Loaded, Bool.not(fine(got)), Refused{}, Bool.pick(Loaded, List.is_empty(&2, Face, faces), Empty{},
    model.made(built(got, scale), skeleton(bones, 0, count, raw, stored(vertices), scale, True{}, Nil{}, Nil{}), U32.is_ne(count, 0), materials)))

def model.opened(found: Opened) -> Loaded:
  match found:
    case Unread{}: Refused{}
    case Foreign{}: Empty{}
    case Open{+file}: model.got(parsed(file), file)

# LoadM3D of a file's bytes (0..255 each).
def model(+bytes: +List<U32>) -> Loaded:
  model.opened(open(bytes))

# ret[bone].pos = pos; ret[bone].ori = ori (rows of a bone's position and orientation vertices).
def moved(list: +List<Row>, +at: U32, +bone: U32, +pos: U32, +ori: U32) -> +List<Row>:
  match list:
    case Nil{}: Nil{}
    case Con{Row{+p, +o, _, _, _, _, _, _}, rest}: Con{Bool.pick(Row, U32.is_eq(at, bone), Row{pos, ori, 0, 0, 0, 0, 0, 0}, Row{p, o, 0, 0, 0, 0, 0, 0}), moved(rest, (at + 1 : U32), bone, pos, ori)}

# A frame's transforms applied to the bones' vertices.
def applied(transforms: +List<Row>, +list: +List<Row>) -> +List<Row>:
  match transforms:
    case Nil{}: list
    case Con{Row{+bone, +pos, +ori, _, _, _, _, _}, rest}: applied(rest, moved(list, 0, bone, pos, ori))

# The frames whose time is not past msec, applied in order: the bones'
# vertices, the last frame's time (0 without one) and how many were applied.
type Sel is Data:
  Sel{list: +List<Row>, last: U32, count: U32}

def upto(frames: +List<Frame>, +msec: U32, +list: +List<Row>, +last: U32, +count: U32) -> Sel:
  match frames:
    case Nil{}: Sel{list, last, count}
    case Con{Frame{+at, +transforms}, rest}: Bool.pick(Sel, (at <= msec : U32), upto(rest, msec, applied(transforms, list), at, (count + 1 : U32)), Sel{list, last, count})

def frame.first(frames: +List<Frame>) -> Frame:
  match frames:
    case Con{+f, _}: f
    case Nil{}: Frame{0, Nil{}}

# Carmack's inverse square root, as the importer writes it.
def rsq(+x: F32) -> F32:
  +y = float((1597463007 - (F32.bits(x) >> 1n) : U32))
  (y * (1.5 - ((x * 0.5) * y * y)) : F32)

# An orientation between two: the importer's approximated NLERP. It changes
# the factor t (the next bones use the changed one); the result is x, y, z, w
# and the new t.
type Turn is Data:
  Turn{t: F32, x: F32, y: F32, z: F32, w: F32}

def turn.scaled(+t: F32, +x: F32, +y: F32, +z: F32, +w: F32, +d: F32) -> Turn:
  Turn{t, (x * d : F32), (y * d : F32), (z * d : F32), (w * d : F32)}

def turn.mixed(+t: F32, +x: F32, +y: F32, +z: F32, +w: F32) -> Turn:
  turn.scaled(t, x, y, z, w, rsq((w * w + x * x + y * y + z * z : F32)))

def turn.timed(+t: F32, +s: F32, +p: Row, +f: Row) -> Turn:
  turn.mixed(t, (float(Row.a(p)) + t * (s * float(Row.a(f)) - float(Row.a(p))) : F32), (float(Row.b(p)) + t * (s * float(Row.b(f)) - float(Row.b(p))) : F32),
    (float(Row.c(p)) + t * (s * float(Row.c(f)) - float(Row.c(p))) : F32), (float(Row.d(p)) + t * (s * float(Row.d(f)) - float(Row.d(p))) : F32))

def turn.eased(+t: F32, +c: F32, +d: F32, +s: F32, +p: Row, +f: Row) -> Turn:
  turn.timed((t + t * c * (t - 1.0) * ((1.0904 + d * (F32.neg(3.2452) + d * (3.55645 - d * 1.43519))) * c * c + (0.848013 + d * (F32.neg(1.06021) + d * 0.215638))) : F32), s, p, f)

def turn.signed(+t: F32, +d: F32, +p: Row, +f: Row) -> Turn:
  turn.eased(t, (t - 0.5 : F32), Bool.pick(F32, (d < 0.0 : F32), F32.neg(d), d), Bool.pick(F32, (d < 0.0 : F32), F32.neg(1.0), 1.0), p, f)

def turn(+t: F32, +p: Row, +f: Row) -> Turn:
  turn.signed(t, (float(Row.d(p)) * float(Row.d(f)) + float(Row.a(p)) * float(Row.a(f)) + float(Row.b(p)) * float(Row.b(f)) + float(Row.c(p)) * float(Row.c(f)) : F32), p, f)

# The bones' poses: each one's position (x, y, z) and orientation (x, y, z, w)
# as bits; ok: every vertex they name exists.
type Lerp is Data:
  Lerp{ok: Bool, rows: +List<Row>}

def Turn.t(q: Turn) -> F32:
  Turn{t, _, _, _, _} = q
  t

def lerp.row(+position: Row, +q: Turn) -> Row:
  Turn{_, +x, +y, +z, +w} = q
  Row{Row.a(position), Row.b(position), Row.c(position), F32.bits(x), F32.bits(y), F32.bits(z), F32.bits(w), 0}

# A position between two: p + t*(f - p).
def between(+t: F32, +p: Row, +f: Row) -> Row:
  Row{F32.bits((float(Row.a(p)) + t * (float(Row.a(f)) - float(Row.a(p))) : F32)), F32.bits((float(Row.b(p)) + t * (float(Row.b(f)) - float(Row.b(p))) : F32)),
    F32.bits((float(Row.c(p)) + t * (float(Row.c(f)) - float(Row.c(p))) : F32)), 0, 0, 0, 0, 0}

def still(+p: Row, +t: F32) -> Turn:
  Turn{t, float(Row.a(p)), float(Row.b(p)), float(Row.c(p)), float(Row.d(p))}

# Each bone from its vertices now (ret) to those of the next frame (tmp): a
# position or an orientation that differs is interpolated with the factor
# as it stands, and an orientation changes the factor.
def lerped(now: +List<Row>, next: +List<Row>, +vertices: Store, +t: F32, +ok: Bool, +acc: +List<Row>) -> Lerp:
  match now next:
    case Con{Row{+rp, +ro, _, _, _, _, _, _}, rest} Con{Row{+tp, +to, _, _, _, _, _, _}, more}:
      +q = Bool.pick(Turn, U32.is_eq(ro, to), still(row(vertices, ro), t), turn(t, row(vertices, ro), row(vertices, to)))
      lerped(rest, more, vertices, Turn.t(q), ok && (rp < Store.count(vertices) : U32) && (ro < Store.count(vertices) : U32) && (tp < Store.count(vertices) : U32) && (to < Store.count(vertices) : U32),
        Con{lerp.row(Bool.pick(Row, U32.is_eq(rp, tp), row(vertices, rp), between(t, row(vertices, rp), row(vertices, tp))), q), acc})
    case _ _: Lerp{ok, rows.reversed(acc, Nil{})}

def Sel.list(sel: Sel) -> +List<Row>:
  Sel{list, _, _} = sel
  list

def Sel.last(sel: Sel) -> U32:
  Sel{_, last, _} = sel
  last

def Sel.count(sel: Sel) -> U32:
  Sel{_, _, count} = sel
  count

def Frame.msec(f: Frame) -> U32:
  Frame{msec, _} = f
  msec

def Frame.transforms(f: Frame) -> +List<Row>:
  Frame{_, transforms} = f
  transforms

def frames.length(xs: +List<Frame>, +acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case Con{_, rest}: frames.length(rest, (acc + 1 : U32))

# The bones' own vertices: position and orientation.
def base(list: +List<Row>) -> +List<Row>:
  match list:
    case Nil{}: Nil{}
    case Con{Row{_, _, +pos, +ori, _, _, _, _}, rest}: Con{Row{pos, ori, 0, 0, 0, 0, 0, 0}, base(rest)}

# t = l >= fr->msec ? 1.0 : (msec - l)/(fr->msec - l).
def factor(+last: U32, +msec: U32, +next: U32) -> F32:
  Bool.pick(F32, (last >= next : U32), 1.0, (U32.to_f32((msec - last : U32)) / U32.to_f32((next - last : U32)) : F32))

# m3d_pose(model, action, msec) for msec below the duration: the frames up
# to msec, then, when the last one is not at msec, an interpolation towards
# the frame after them (the first one after the last).
def pose.at(+sel: Sel, +frames: +List<Frame>, +msec: U32, +vertices: Store) -> Lerp:
  +next = frame.first(List.drop(&2, Frame, frames, U32.to_nat((Sel.count(sel) % frames.length(frames, 0) : U32))))
  Bool.pick(Lerp, U32.is_eq(Sel.last(sel), msec), lerped(Sel.list(sel), Sel.list(sel), vertices, 1.0, True{}, Nil{}),
    lerped(Sel.list(sel), applied(Frame.transforms(next), Sel.list(sel)), vertices, factor(Sel.last(sel), msec, Frame.msec(next)), True{}, Nil{}))

# A bone's transform from its pose row: the position times the scale, the orientation normalized, a scale of 1.
def own.of(+r: Row, +scale: F32) -> GA.Transform:
  Row{+x, +y, +z, +qx, +qy, +qz, +qw, _} = r
  GA.Transform{M.Vector3{(float(x) * scale : F32), (float(y) * scale : F32), (float(z) * scale : F32)}, M.Quaternion.normalize(M.Vector4{float(qx), float(qy), float(qz), float(qw)}), M.Vector3{1.0, 1.0, 1.0}}

# A keyframe's poses in model space, then the no-bone one.
def keyed(bones: +List<Row>, rows: +List<Row>, +at: U32, +scale: F32, +done: +List<GA.Transform>) -> +List<GA.Transform>:
  match bones rows:
    case Con{Row{+parent, _, _, _, _, _, _, _}, rest} Con{+r, more}: keyed(rest, more, (at + 1 : U32), scale, Con{placed(own.of(r, scale), parent, at, done), done})
    case _ _: List.reverse(&2, GA.Transform, Con{GA.Transform{M.Vector3{0.0, 0.0, 0.0}, M.Vector4{0.0, 0.0, 0.0, 1.0}, M.Vector3{1.0, 1.0, 1.0}}, done})

type Keys is Data:
  Keys{ok: Bool, poses: +List<+List<GA.Transform>>}

def Lerp.ok(l: Lerp) -> Bool:
  Lerp{ok, _} = l
  ok

def Lerp.rows(l: Lerp) -> +List<Row>:
  Lerp{_, rows} = l
  rows

def poses.turned(xs: +List<+List<GA.Transform>>, acc: +List<+List<GA.Transform>>) -> +List<+List<GA.Transform>>:
  match xs:
    case Nil{}: acc
    case Con{+x, rest}: poses.turned(rest, Con{x, acc})

# The keyframes of an action: keyframe i is the pose at i*17 ms (modulo the duration).
def keys(n: Nat, +index: U32, +frames: +List<Frame>, +duration: U32, +bones: +List<Row>, +vertices: Store, +scale: F32, +ok: Bool, +acc: +List<+List<GA.Transform>>) -> Keys:
  match n:
    case 0n: Keys{ok, poses.turned(acc, Nil{})}
    case 1n+k:
      +found = pose.at(upto(frames, ((index * 17) % duration : U32), base(bones), 0, 0), frames, ((index * 17) % duration : U32), vertices)
      keys(k, (index + 1 : U32), frames, duration, bones, vertices, scale, ok && Lerp.ok(found), Con{keyed(bones, Lerp.rows(found), 0, scale, Nil{}), acc})

# Every transform of the frames names a bone.
def moves.inside(list: +List<Row>, +count: U32) -> Bool:
  match list:
    case Nil{}: True{}
    case Con{Row{+bone, _, _, _, _, _, _, _}, rest}: (bone < count : U32) && moves.inside(rest, count)

def frames.inside(list: +List<Frame>, +count: U32) -> Bool:
  match list:
    case Nil{}: True{}
    case Con{Frame{_, +transforms}, rest}: moves.inside(transforms, count) && frames.inside(rest, count)

type Listed is Data:
  Listed{ok: Bool, items: +List<GA.Animation>}

def Keys.ok(k: Keys) -> Bool:
  Keys{ok, _} = k
  ok

def Keys.poses(k: Keys) -> +List<+List<GA.Transform>>:
  Keys{_, poses} = k
  poses

# An action as an animation: its name's first 31 bytes, the bones and the
# no-bone one, duration/17 keyframes. The actions are kept last first; the
# animations come out in the file's order.
def listed(actions: +List<Action>, +raw: +List<U32>, +bones: +List<Row>, +vertices: Store, +scale: F32, +state: Listed) -> Listed:
  match actions:
    case Nil{}: state
    case Con{Action{+name, +duration, +frames}, rest}:
      Listed{+ok, +items} = state
      +count = rows.length(bones, 0)
      +found = keys(U32.to_nat((duration / 17 : U32)), 0, frames, U32.max(duration, 1), bones, vertices, scale, True{}, Nil{})
      listed(rest, raw, bones, vertices, scale, Listed{ok && Text.ok(text(raw, name)) && frames.inside(frames, count) && ((duration / 17) <= 65536 : U32) && Keys.ok(found),
        Con{GA.Animation{taken(Text.bytes(text(raw, name)), 31), (count + 1 : U32), (duration / 17 : U32), Keys.poses(found)}, items}})

# Unanimated: refused. No animations for a file that gives no model, or has no action or no bone.
type Animated is Data:
  Unanimated{}
  Animations{items: +List<GA.Animation>}

def animated.listed(+found: Listed, +fits: Bool) -> Animated:
  Listed{+ok, +items} = found
  Bool.pick(Animated, ok && fits, Animations{items}, Unanimated{})

def animated.got(+got: Got, +file: File) -> Animated:
  Got{_, _, _, +shape, +rig, _, +actions} = got
  Shape{_, +vertices, _, _} = shape
  Rig{_, +bones, _} = rig
  File{+raw, _, +scale, _, _, _, _, _, _, _, _, _, _} = file
  Bool.pick(Animated, Bool.not(fine(got)), Unanimated{}, Bool.pick(Animated, List.is_empty(&2, Action, actions) || List.is_empty(&2, Row, bones), Animations{Nil{}},
    animated.listed(listed(actions, raw, bones, stored(vertices), scale, Listed{True{}, Nil{}}), Skel.ok(skeleton(bones, 0, rows.length(bones, 0), raw, stored(vertices), scale, True{}, Nil{}, Nil{})))))

def animated.opened(found: Opened) -> Animated:
  match found:
    case Unread{}: Unanimated{}
    case Foreign{}: Animations{Nil{}}
    case Open{+file}: animated.got(parsed(file), file)

# LoadModelAnimationsM3D of a file's bytes.
def animations(+bytes: +List<U32>) -> Animated:
  animated.opened(open(bytes))
