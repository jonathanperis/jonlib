# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.2 rmodels.c LoadVOX (zlib,
# LICENSES/raylib.txt) and of vox_loader 1.04 as raylib 6.2 vendors it
# (src/external/vox_loader.h, with raylib 6.2's bounds checks,
# Copyright (c) 2021 Johann Nadalutti, MIT; LICENSES/vox_loader.txt):
# Vox_LoadFromMemory's reading of a MagicaVoxel file (the "VOX " magic,
# versions 150 and 200, the SIZE, XYZI and RGBA chunks, every other chunk
# skipped by its size) and its mesh (a quad for every face of a voxel whose
# neighbor is empty, in the loader's order: x, then z, then y, the faces -X,
# +X, -Y, +Y, -Z, +Z), then LoadVOX's split into meshes of 65532 vertices.
# The loader's quirks are kept: an RGBA chunk gives 255 colors (palette 1 to
# 255) and leaves the reading four bytes before the chunk's end, so what
# follows a palette is read as a chunk named by its last color and sized by
# the next chunk's name; a SIZE chunk starts an empty array again. Since
# raylib 6.2 the reading ends (what was read is kept) where fewer than 12
# bytes are left for a chunk header or a SIZE, 4 for a voxel count or 1020
# for a palette, or where a skipped chunk's size passes the end; a voxel
# count is cut to the voxels the file holds, and a voxel outside the padded
# sizes is not set. The voxel array is one array here (the loader's
# 16x16x16 chunks only store it). Refused: a magic or a version cut short
# (a read past the file), a file over 2 MiB, a size over 1024 or an array
# over 2^21 cells (the profile), and a file without a visible voxel
# (LoadVOX allocates zero bytes for its mesh). See docs/MODELS.md.
import Base

# A mesh LoadVOX builds: vertexCount, triangleCount, the vertices and the
# normals (3 floats a vertex), the colors (4 bytes a vertex) and the indices
# of its triangles (two a quad: 0 2 1 and 0 3 2).
type Part is Data:
  Part{vertex_count: U32, triangle_count: U32, vertices: +List<F32>, normals: +List<F32>, colors: +List<U32>, indices: +List<U32>}

# Unread: the reference reads outside the file or the profile ends. Foreign:
# Vox_LoadFromMemory fails (another magic or version) and LoadVOX gives the
# empty model.
type Loaded is Data:
  Unread{}
  Foreign{}
  Meshes{parts: +List<Part>}

type Word is Data:
  Word{value: U32, rest: +List<U32>}

# What the chunks read so far give: the array's sizes (0 before a SIZE
# chunk), the voxels set since (cell*256 + id, the last one first) and the
# palette's 256 colors.
type Read is Data:
  Read{sx: U32, sy: U32, sz: U32, sets: +List<U32>, palette: +List<U32>}

type Step is Data:
  Halt{}
  Next{bytes: +List<U32>, read: Read}

type Sets is Data:
  Sets{sets: +List<U32>, rest: +List<U32>}

# The quads built so far, their values last first.
type Out is Data:
  Out{vertices: +List<F32>, normals: +List<F32>, colors: +List<U32>, quads: U32}

type Work is Type:
  Work{grid: Array<U32>, palette: Array<U32>, out: Out}

type CutF is Data:
  CutF{head: +List<F32>, rest: +List<F32>}

type CutU is Data:
  CutU{head: +List<U32>, rest: +List<U32>}

def turned(values: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: turned(rest, Con{v, acc})

def length(values: +List<U32>, +acc: U32) -> U32:
  match values:
    case Nil{}: acc
    case Con{_, rest}: length(rest, (acc + 1 : U32))

# A little-endian unsigned int.
def word(bytes: +List<U32>) -> Maybe<&2, Word>:
  match bytes:
    case Con{+a, Con{+b, Con{+c, Con{+d, +rest}}}}: Some{Word{(a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32), rest}}
    case _: None{}

# sx + ((CHUNKSIZE - (sx % CHUNKSIZE)) % CHUNKSIZE).
def padded(+size: U32) -> U32:
  (size + ((16 - size % 16) % 16) : U32)

# Vox_AllocArray(sizeX, sizeZ, sizeY): the file's Y and Z change places.
# The reading's end (raylib 6.2's `break`): what was read is kept.
def stop(+read: Read) -> Step:
  Next{Nil{}, read}

def size.set(valid: Bool, +x: U32, +y: U32, +z: U32, +rest: +List<U32>, +read: Read) -> Step:
  match valid:
    case False{}: Halt{}
    case True{}:
      Read{_, _, _, _, +palette} = read
      Next{rest, Read{padded(x), padded(z), padded(y), Nil{}, palette}}

def size.z(z: Maybe<&2, Word>, +x: U32, +y: U32, +read: Read) -> Step:
  match z:
    case None{}: stop(read)
    case Some{Word{+v, +rest}}:
      size.set((x <= 1024 : U32) && (y <= 1024 : U32) && (v <= 1024 : U32) && ((padded(x) * padded(y) * padded(v)) <= 2097152 : U32), x, y, v, rest, read)

def size.y(y: Maybe<&2, Word>, +x: U32, +read: Read) -> Step:
  match y:
    case None{}: stop(read)
    case Some{Word{+v, +rest}}: size.z(word(rest), x, v, read)

# A SIZE chunk: sizeX, sizeY, sizeZ; fewer than 12 bytes end the reading.
def size(x: Maybe<&2, Word>, +read: Read) -> Step:
  match x:
    case None{}: stop(read)
    case Some{Word{+v, +rest}}: size.y(word(rest), v, read)

# Vox_SetVoxel(x, z, sizeZ - y - 1, id) for each voxel: the cell is
# (x*sizeZ + z)*sizeY + y in the array's coordinates, the order the mesh is
# built in. A voxel outside the (padded) sizes is not set (raylib 6.2's
# range checks; a voxel before any SIZE is outside sizes of 0).
def voxels(n: Nat, bytes: +List<U32>, +sx: U32, +sy: U32, +sz: U32, +sets: +List<U32>) -> Sets:
  match n bytes:
    case 1n+k Con{+vx, Con{+vy, Con{+vz, Con{+vi, +more}}}}:
      voxels(k, more, sx, sy, sz, Bool.pick(+List<U32>, (vx < sx : U32) && (vz < sy : U32) && (vy < sz : U32), Con{((((vx * sz + ((sz - vy) - 1)) * sy + vz) << 8n) .|. vi : U32), sets}, sets))
    case 0n Nil{}: Sets{sets, Nil{}}
    case 0n Con{+b, +more}: Sets{sets, Con{b, more}}
    case _ _: Sets{sets, Nil{}}

def xyzi.set(+done: Sets, +read: Read) -> Step:
  Sets{+sets, +rest} = done
  Read{+sx, +sy, +sz, _, +palette} = read
  Next{rest, Read{sx, sy, sz, sets, palette}}

# An XYZI chunk: numVoxels, then x, y, z and the color index of each. A count
# past the voxels the file holds is cut to them (raylib 6.2): the voxels run
# out, and the fewer than 4 bytes left end the reading; fewer than 4 bytes
# for the count end it too.
def xyzi(count: Maybe<&2, Word>, +read: Read) -> Step:
  match count:
    case None{}: stop(read)
    case Some{Word{+n, +rest}}:
      Read{+sx, +sy, +sz, +sets, _} = read
      xyzi.set(voxels(U32.to_nat(U32.min(n, 524289)), rest, sx, sy, sz, sets), read)

type Colors is Data:
  Colors{ok: Bool, colors: +List<U32>, rest: +List<U32>}

def colors(n: Nat, bytes: +List<U32>, +acc: +List<U32>) -> Colors:
  match n bytes:
    case 1n+k Con{+r, Con{+g, Con{+b, Con{+a, +more}}}}: colors(k, more, Con{((r << 24n) .|. (g << 16n) .|. (b << 8n) .|. a : U32), acc})
    case 0n Nil{}: Colors{True{}, acc, Nil{}}
    case 0n Con{+b, +more}: Colors{True{}, acc, Con{b, more}}
    case _ _: Colors{False{}, acc, Nil{}}

def rgba.read(ok: Bool, +colors: +List<U32>, +rest: +List<U32>, +read: Read) -> Step:
  match ok:
    case False{}: stop(read)
    case True{}:
      Read{+sx, +sy, +sz, +sets, _} = read
      Next{rest, Read{sx, sy, sz, sets, Con{0, turned(colors, Nil{})}}}

# An RGBA chunk: palette[i + 1] for the 255 colors read (palette[0] keeps its
# zero); fewer than 1020 bytes end the reading, the palette as it was.
def rgba(+done: Colors, +read: Read) -> Step:
  Colors{+ok, +colors, +rest} = done
  rgba.read(ok, colors, rest, read)

# 1 SIZE, 2 XYZI, 3 RGBA, 0 any other name.
def kind(+name: U32) -> U32:
  Bool.pick(U32, U32.is_eq(name, 1163544915), 1, Bool.pick(U32, U32.is_eq(name, 1230657880), 2, Bool.pick(U32, U32.is_eq(name, 1094862674), 3, 0)))

# The chunk's contents: another chunk is skipped by its size (an unsigned
# int; past the end of a file of 2 MiB at most, the reading ends).
def chunk.body(kind: U32, +n: U32, +body: +List<U32>, +read: Read) -> Step:
  match kind:
    case 1: size(word(body), read)
    case 2: xyzi(word(body), read)
    case 3: rgba(colors(255n, body, Nil{}), read)
    case _: Next{List.drop(&2, U32, body, U32.to_nat(U32.min(n, 2097152))), read}

def chunk.children(children: Maybe<&2, Word>, +name: U32, +n: U32, +read: Read) -> Step:
  match children:
    case None{}: stop(read)
    case Some{Word{_, +rest}}: chunk.body(kind(name), n, rest, read)

def chunk.sized(size: Maybe<&2, Word>, +name: U32, +read: Read) -> Step:
  match size:
    case None{}: stop(read)
    case Some{Word{+n, +rest}}: chunk.children(word(rest), name, n, read)

def chunk.named(name: Maybe<&2, Word>, +read: Read) -> Step:
  match name:
    case None{}: stop(read)
    case Some{Word{+id, +rest}}: chunk.sized(word(rest), id, read)

# A chunk: its name, the size of its contents, the size of its children
# (not read), then its contents. Fewer than the header's 12 bytes end the
# reading (raylib 6.2).
def chunk(+bytes: +List<U32>, +read: Read) -> Step:
  chunk.named(word(bytes), read)

# while (fileDataPtr < endfileDataPtr).
def chunks(fuel: Nat, step: Step) -> Maybe<&2, Read>:
  match fuel step:
    case _ Halt{}: None{}
    case 1n+_ Next{Nil{}, +read}: Some{read}
    case 1n+f Next{Con{+b, +rest}, +read}: chunks(f, chunk(Con{b, rest}, read))
    case 0n Next{_, _}: None{}

def zeros(n: Nat, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: zeros(k, Con{0, acc})

# The array's depth: 2^depth cells hold `cells`.
def depth(+cells: U32) -> Nat:
  Bool.pick(Nat, (cells <= 1 : U32), 0n, 1n+U32.log2((cells - 1 : U32)))

def placed(sets: +List<U32>, grid: Array<U32>) -> Array<U32>:
  match sets:
    case Nil{}: grid
    case Con{+s, rest}: placed(rest, Array.set(U32, grid, (s >> 8n : U32), (s .&. 255 : U32)))

def painted(colors: +List<U32>, +i: U32, palette: Array<U32>) -> Array<U32>:
  match colors:
    case Nil{}: palette
    case Con{+c, rest}: painted(rest, (i + 1 : U32), Array.set(U32, palette, i, c))

# The cells in their order.
def cells(a: Array<U32>, acc: +List<U32>) -> +List<U32>:
  match a:
    case ALeaf{+x}: Con{x, acc}
    case ANode{xs, ys}: cells(xs, cells(ys, acc))

def seen.at(+mask: U32, +bit: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  (grid, +id) = r
  (grid, Bool.pick(U32, U32.is_eq(id, 0), (mask .|. bit : U32), mask))

# Vox_GetVoxel of a neighbor: 0 outside the array. An empty neighbor sets the face's bit.
def seen(inside: Bool, r: Array<U32> & U32, +i: U32, +bit: U32) -> Array<U32> & U32:
  match inside r:
    case False{} Tuple{grid, +mask}: (grid, (mask .|. bit : U32))
    case True{} Tuple{grid, +mask}: seen.at(mask, bit, Array.get(U32, grid, i))

# Vox_CalcFacesVisible: the bits of -X, +X, -Y, +Y, -Z and +Z.
def mask(grid: Array<U32>, +i: U32, +x: U32, +y: U32, +z: U32, +sx: U32, +sy: U32, +sz: U32) -> Array<U32> & U32:
  seen(((z + 1) < sz : U32), seen((z > 0 : U32), seen(((y + 1) < sy : U32), seen((y > 0 : U32), seen(((x + 1) < sx : U32), seen((x > 0 : U32), (grid, 0), (i - sy * sz : U32), 1),
    (i + sy * sz : U32), 2), (i - 1 : U32), 4), (i + 1 : U32), 8), (i - sy : U32), 16), (i + sy : U32), 32)

# A visible face: its four corners, its normal four times, the voxel's color four times.
def quad(visible: Bool, +ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32, +cx: F32, +cy: F32, +cz: F32, +dx: F32, +dy: F32, +dz: F32, +nx: F32, +ny: F32, +nz: F32, +color: U32, out: Out) -> Out:
  match visible:
    case False{}: out
    case True{}:
      Out{+vs, +ns, +cs, +quads} = out
      Out{Con{dz, Con{dy, Con{dx, Con{cz, Con{cy, Con{cx, Con{bz, Con{by, Con{bx, Con{az, Con{ay, Con{ax, vs}}}}}}}}}}}},
        Con{nz, Con{ny, Con{nx, Con{nz, Con{ny, Con{nx, Con{nz, Con{ny, Con{nx, Con{nz, Con{ny, Con{nx, ns}}}}}}}}}}}},
        Con{(color .&. 255 : U32), Con{((color >> 8n) .&. 255 : U32), Con{((color >> 16n) .&. 255 : U32), Con{(color >> 24n : U32),
        Con{(color .&. 255 : U32), Con{((color >> 8n) .&. 255 : U32), Con{((color >> 16n) .&. 255 : U32), Con{(color >> 24n : U32),
        Con{(color .&. 255 : U32), Con{((color >> 8n) .&. 255 : U32), Con{((color >> 16n) .&. 255 : U32), Con{(color >> 24n : U32),
        Con{(color .&. 255 : U32), Con{((color >> 8n) .&. 255 : U32), Con{((color >> 16n) .&. 255 : U32), Con{(color >> 24n : U32), cs}}}}}}}}}}}}}}}},
        (quads + 1 : U32)}

def bit(+mask: U32, +bit: U32) -> Bool:
  U32.is_ne((mask .&. bit : U32), 0)

# Vox_Build_Voxel: the corners are (SolidVertex + position)*0.25, the faces
# fv's (-X 0 2 6 4, +X 5 7 3 1, -Y 0 4 5 1, +Y 6 2 3 7, -Z 1 3 2 0, +Z 4 6 7 5).
def faces(+mask: U32, +x0: F32, +x1: F32, +y0: F32, +y1: F32, +z0: F32, +z1: F32, +color: U32, out: Out) -> Out:
  q0 = quad(bit(mask, 1), x0, y0, z0, x0, y1, z0, x0, y1, z1, x0, y0, z1, F32.neg(1.0), 0.0, 0.0, color, out)
  q1 = quad(bit(mask, 2), x1, y0, z1, x1, y1, z1, x1, y1, z0, x1, y0, z0, 1.0, 0.0, 0.0, color, q0)
  q2 = quad(bit(mask, 4), x0, y0, z0, x0, y0, z1, x1, y0, z1, x1, y0, z0, 0.0, F32.neg(1.0), 0.0, color, q1)
  q3 = quad(bit(mask, 8), x0, y1, z1, x0, y1, z0, x1, y1, z0, x1, y1, z1, 0.0, 1.0, 0.0, color, q2)
  q4 = quad(bit(mask, 16), x1, y0, z0, x1, y1, z0, x0, y1, z0, x0, y0, z0, 0.0, 0.0, F32.neg(1.0), color, q3)
  quad(bit(mask, 32), x0, y0, z1, x0, y1, z1, x1, y1, z1, x1, y0, z1, 0.0, 0.0, 1.0, color, q4)

def voxel.colored(+mask: U32, +x: U32, +y: U32, +z: U32, grid: Array<U32>, out: Out, r: Array<U32> & U32) -> Work:
  (palette, +color) = r
  Work{grid, palette, faces(mask, (U32.to_f32(x) * 0.25 : F32), ((1.0 + U32.to_f32(x)) * 0.25 : F32), (U32.to_f32(y) * 0.25 : F32), ((1.0 + U32.to_f32(y)) * 0.25 : F32), (U32.to_f32(z) * 0.25 : F32),
    ((1.0 + U32.to_f32(z)) * 0.25 : F32), color, out)}

def voxel.masked(+id: U32, +x: U32, +y: U32, +z: U32, palette: Array<U32>, out: Out, r: Array<U32> & U32) -> Work:
  (grid, +mask) = r
  voxel.colored(mask, x, y, z, grid, out, Array.get(U32, palette, id))

# A cell of the array: a voxel (matID != 0) is built in its palette color.
def voxel(empty: Bool, +id: U32, +i: U32, +x: U32, +y: U32, +z: U32, +sx: U32, +sy: U32, +sz: U32, work: Work) -> Work:
  match empty:
    case True{}: work
    case False{}:
      Work{grid, palette, out} = work
      voxel.masked(id, x, y, z, palette, out, mask(grid, i, x, y, z, sx, sy, sz))

# for x, for z, for y: the cells in the array's order (those the loops visit past the sizes are empty).
def scan(list: +List<U32>, +i: U32, +x: U32, +y: U32, +z: U32, +sx: U32, +sy: U32, +sz: U32, work: Work) -> Work:
  match list:
    case Nil{}: work
    case Con{+id, rest}:
      scan(rest, (i + 1 : U32), Bool.pick(U32, U32.is_eq((y + 1 : U32), sy) && U32.is_eq((z + 1 : U32), sz), (x + 1 : U32), x), Bool.pick(U32, U32.is_eq((y + 1 : U32), sy), 0, (y + 1 : U32)),
        Bool.pick(U32, U32.is_eq((y + 1 : U32), sy), Bool.pick(U32, U32.is_eq((z + 1 : U32), sz), 0, (z + 1 : U32)), z), sx, sy, sz, voxel(U32.is_eq(id, 0), id, i, x, y, z, sx, sy, sz, work))

def scanned(+sx: U32, +sy: U32, +sz: U32, palette: Array<U32>, r: Array<U32> & Array<U32>) -> Work:
  (grid, copy) = r
  scan(cells(copy, Nil{}), 0, 0, 0, 0, sx, sy, sz, Work{grid, palette, Out{Nil{}, Nil{}, Nil{}, 0}})

# The next n values of a list kept last first, in their order, and the values before them.
def cut.f(n: Nat, src: +List<F32>, +acc: +List<F32>) -> CutF:
  match n src:
    case 1n+k Con{+v, rest}: cut.f(k, rest, Con{v, acc})
    case 0n Nil{}: CutF{acc, Nil{}}
    case 0n Con{+v, +rest}: CutF{acc, Con{v, rest}}
    case 1n+_ Nil{}: CutF{acc, Nil{}}

def cut.u(n: Nat, src: +List<U32>, +acc: +List<U32>) -> CutU:
  match n src:
    case 1n+k Con{+v, rest}: cut.u(k, rest, Con{v, acc})
    case 0n Nil{}: CutU{acc, Nil{}}
    case 0n Con{+v, +rest}: CutU{acc, Con{v, rest}}
    case 1n+_ Nil{}: CutU{acc, Nil{}}

# The indices of q quads: idx + 0, 2, 1 and idx + 0, 3, 2 for idx = 0, 4, 8...
def indices(n: Nat, +q: U32, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k:
      indices(k, (q - 1 : U32), Con{(4 * (q - 1) : U32), Con{(4 * (q - 1) + 2 : U32), Con{(4 * (q - 1) + 1 : U32), Con{(4 * (q - 1) : U32), Con{(4 * (q - 1) + 3 : U32), Con{(4 * (q - 1) + 2 : U32), acc}}}}}})

# pmesh->vertexCount = fmin(verticesMax, verticesRemain) of mesh i: 65532 vertices a mesh.
def count.of(+i: U32, +total: U32) -> U32:
  U32.min(65532, (total - 65532 * i : U32))

# The values of the mesh before mesh i (none before the first).
def before(+i: U32, +total: U32, +per: U32) -> Nat:
  U32.to_nat(Bool.pick(U32, U32.is_eq(i, 0), 0, (count.of((i - 1 : U32), total) * per : U32)))

# The meshes from the last to the first: a, b and c hold mesh i's vertices, normals and colors.
def parts(n: Nat, a: CutF, b: CutF, c: CutU, +i: U32, +total: U32, +acc: +List<Part>) -> +List<Part>:
  match n a b c:
    case 1n+k CutF{+vs, +vrest} CutF{+ns, +nrest} CutU{+cs, +crest}:
      parts(k, cut.f(before(i, total, 3), vrest, Nil{}), cut.f(before(i, total, 3), nrest, Nil{}), cut.u(before(i, total, 4), crest, Nil{}), (i - 1 : U32), total,
        Con{Part{count.of(i, total), (count.of(i, total) / 4 * 2 : U32), vs, ns, cs, indices(U32.to_nat((count.of(i, total) / 4 : U32)), (count.of(i, total) / 4 : U32), Nil{})}, acc})
    case _ _ _ _: acc

# LoadVOX's meshes: 1 + vertices/65536 of them, 65532 vertices each and what
# remains in the last (vertices past it are left out, as upstream).
def split(+total: U32, +number: U32, +vs: +List<F32>, +ns: +List<F32>, +cs: +List<U32>) -> +List<Part>:
  +last = (number - 1 : U32)
  +left = ((total - 65532 * last) - count.of(last, total) : U32)
  parts(U32.to_nat(number), cut.f(U32.to_nat((count.of(last, total) * 3 : U32)), List.drop(&2, F32, vs, U32.to_nat((left * 3 : U32))), Nil{}),
    cut.f(U32.to_nat((count.of(last, total) * 3 : U32)), List.drop(&2, F32, ns, U32.to_nat((left * 3 : U32))), Nil{}),
    cut.u(U32.to_nat((count.of(last, total) * 4 : U32)), List.drop(&2, U32, cs, U32.to_nat((left * 4 : U32))), Nil{}), last, total, Nil{})

def meshes(+out: Out) -> Loaded:
  Out{+vs, +ns, +cs, +quads} = out
  Bool.pick(Loaded, U32.is_eq(quads, 0), Unread{}, Meshes{split((quads * 4 : U32), (1 + (quads * 4) / 65536 : U32), vs, ns, cs)})

def finished(work: Work) -> Loaded:
  Work{_, _, out} = work
  meshes(out)

# The mesh of the array: the voxels set in the file's order, then the scan.
def built.sized(some: Bool, +sx: U32, +sy: U32, +sz: U32, +sets: +List<U32>, +palette: +List<U32>) -> Loaded:
  match some:
    case False{}: Unread{}
    case True{}:
      finished(scanned(sx, sy, sz, painted(palette, 0, Array.new(U32, 8n, 0)), Array.clone(U32, placed(turned(sets, Nil{}), Array.new(U32, depth((sx * sy * sz : U32)), 0)))))

def built(read: Maybe<&2, Read>) -> Loaded:
  match read:
    case None{}: Unread{}
    case Some{Read{+sx, +sy, +sz, +sets, +palette}}: built.sized(U32.is_ne((sx * sy * sz : U32), 0), sx, sy, sz, sets, palette)

def read.checked(known: Bool, +rest: +List<U32>, +size: U32) -> Loaded:
  match known:
    case False{}: Foreign{}
    case True{}: built(chunks(U32.to_nat((size / 8 + 2 : U32)), Next{rest, Read{0, 0, 0, Nil{}, zeros(256n, Nil{})}}))

# version = ((unsigned int *)fileDataPtr)[0]: 150 or 200.
def read.version(version: Maybe<&2, Word>, +size: U32) -> Loaded:
  match version:
    case None{}: Unread{}
    case Some{Word{+v, +rest}}: read.checked(U32.is_eq(v, 150) || U32.is_eq(v, 200), rest, size)

# strncmp(data, "VOX ", 4): 0 a difference, 1 the four bytes, 2 the file ends before a difference (a read past it).
def magic(bytes: +List<U32>) -> U32:
  match bytes:
    case Con{+a, Con{+b, Con{+c, Con{+d, _}}}}: Bool.pick(U32, U32.is_eq(a, 86) && U32.is_eq(b, 79) && U32.is_eq(c, 88) && U32.is_eq(d, 32), 1, 0)
    case Con{+a, Con{+b, Con{+c, Nil{}}}}: Bool.pick(U32, U32.is_eq(a, 86) && U32.is_eq(b, 79) && U32.is_eq(c, 88), 2, 0)
    case Con{+a, Con{+b, Nil{}}}: Bool.pick(U32, U32.is_eq(a, 86) && U32.is_eq(b, 79), 2, 0)
    case Con{+a, Nil{}}: Bool.pick(U32, U32.is_eq(a, 86), 2, 0)
    case Nil{}: 0

def read.magic(kind: U32, +bytes: +List<U32>, +size: U32) -> Loaded:
  match kind:
    case 0: Foreign{}
    case 1: read.version(word(List.drop(&2, U32, bytes, 4n)), size)
    case _: Unread{}

def read.sized(+bytes: +List<U32>, +size: U32) -> Loaded:
  read.magic(Bool.pick(U32, (size > 2097152 : U32), 2, magic(bytes)), bytes, size)

# LoadVOX of a file's bytes (0..255 each). An empty file is one LoadFileData
# does not load: the empty model, like another magic.
def load(+bytes: +List<U32>) -> Loaded:
  read.sized(bytes, length(bytes, 0))
