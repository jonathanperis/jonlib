# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rmodels.c mesh generation and mesh
# utilities (zlib, LICENSES/raylib.txt): GenMeshPoly, GenMeshPlane (its
# CUSTOM_MESH_GEN_PLANE path), GenMeshCube (CUSTOM_MESH_GEN_CUBE),
# GenMeshHeightmap, GenMeshCubicmap, GenMeshTangents, GetMeshBoundingBox and
# the text of ExportMesh (OBJ) and ExportMeshAsCode. Attribute arrays are F32
# lists in raylib's order; F32 arithmetic keeps rmodels.c's order, with the
# inlined raymath helpers fused (fma) when the reference contracts them.
# jonlib.bend wraps these kernels in the public Mesh API; see docs/MODELS.md.
import Base
import ./../jonmath.bend as M
import ./frame.bend as F
import ./shapes.bend as S
import ./shapes3d.bend as S3
import ./fma.bend as Fma
import ./decimal.bend as Decimal

# A generated attribute list and whether every step was reproduced.
type Built is Data:
  Built{ok: Bool, values: +List<F32>}

def Built.with(ok: Bool, values: +List<F32>, rest: Built) -> Built:
  Built{rest_ok, more} = rest
  Built{ok && rest_ok, List.append(&2, F32, values, more)}

def Built.ok(+b: Built) -> Bool:
  Built{ok, _} = b
  ok

def Built.values(+b: Built) -> +List<F32>:
  Built{_, values} = b
  values

# Lists scale with the mesh: builders that reach vertex-count depth are
# tail-recursive (accumulated, reversed where order matters), so the
# JavaScript lane's stack stays shallow.

def constant.go(n: Nat, +values: +List<F32>, acc: +List<F32>) -> +List<F32>:
  match n:
    case 0n: acc
    case 1n+k: constant.go(k, values, List.append(&2, F32, values, acc))

# n copies of values.
def constant(+n: Nat, +values: +List<F32>) -> +List<F32>:
  constant.go(n, values, Nil{})

def reverse(xs: +List<F32>) -> +List<F32>:
  List.reverse(&2, F32, xs)

def count(xs: +List<F32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def count.u32(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, rest}: count.u32(rest, (n + 1 : U32))

# -----------------------------------------------------------------------------
# Contraction: the raymath helpers rmodels.c inlines, fused (a*b + c rounded
# once) when the reference build contracts them.

def mad(fused: Bool, +a: F32, +b: F32, +c: F32) -> F32:
  match fused:
    case True{}: Fma.multiply_add(a, b, c)
    case False{}: (a * b + c : F32)

# a*b - c*d: fma(a, b, -(c*d)) when fused.
def dif(+fused: Bool, +a: F32, +b: F32, +c: F32, +d: F32) -> F32:
  mad(fused, a, b, F32.neg((c * d : F32)))

# Vector3CrossProduct
def cross(+fused: Bool, a: M.Vector3, b: M.Vector3) -> M.Vector3:
  M.Vector3{+x, +y, +z} = a
  M.Vector3{+u, +v, +w} = b
  M.Vector3{dif(fused, y, w, z, v), dif(fused, z, u, x, w), dif(fused, x, v, y, u)}

# Vector3DotProduct: fma(z, w, fma(x, u, y*v)) when fused.
def dot(+fused: Bool, a: M.Vector3, b: M.Vector3) -> F32:
  M.Vector3{+x, y, +z} = a
  M.Vector3{+u, v, +w} = b
  mad(fused, z, w, mad(fused, x, u, (y * v : F32)))

def length(+fused: Bool, +v: M.Vector3) -> F32:
  F32.sqrt(dot(fused, v, v))

def normalize.with(nonzero: Bool, v: M.Vector3, +size: F32) -> M.Vector3:
  match nonzero:
    case False{}: v
    case True{}: M.Vector3.scale(v, (1.0 / size : F32))

# Vector3Normalize: a zero length leaves the vector unchanged.
def normalize(+fused: Bool, +v: M.Vector3) -> M.Vector3:
  +size = length(fused, v)
  normalize.with(F32.is_ne(size, 0.0), v, size)

def vector.list(v: M.Vector3, rest: +List<F32>) -> +List<F32>:
  M.Vector3{x, y, z} = v
  Con{x, Con{y, Con{z, rest}}}

# -----------------------------------------------------------------------------
# GenMeshPoly: sides triangles (origin, p(d), p(d + step)), d += 360/sides.

def poly.loop(n: Nat, +gnu: Bool, +r: F32, +d: F32, +step: F32) -> Built:
  match n:
    case 0n: Built{True{}, Nil{}}
    case 1n+k:
      +next = (d + step : F32)
      +a = S3.sc(gnu, (S.deg2rad() * d : F32))
      +b = S3.sc(gnu, (S.deg2rad() * next : F32))
      Built.with(S3.SC.ok(a) && S3.SC.ok(b), [0.0, 0.0, 0.0, (S3.SC.sin(a) * r : F32), 0.0, (S3.SC.cos(a) * r : F32),
        (S3.SC.sin(b) * r : F32), 0.0, (S3.SC.cos(b) * r : F32)], poly.loop(k, gnu, r, next, step))

def poly(+gnu: Bool, +sides: U32, +radius: F32) -> Built:
  poly.loop(U32.to_nat(sides), gnu, radius, 0.0, (360.0 / U32.to_f32(sides) : F32))

# -----------------------------------------------------------------------------
# GenMeshPlane (resX and resZ already incremented): positions
# ((x/(resX - 1) - 0.5)*width, 0, (z/(resZ - 1) - 0.5)*length), texcoords
# (u/(resX - 1), v/(resZ - 1)), two triangles per face; indices are
# unsigned shorts.

# Rows are built from the last vertex backwards (x and z counting down).
def plane.row(n: Nat, +x: F32, +dx: F32, +width: F32, +z: F32, acc: +List<F32>) -> +List<F32>:
  match n:
    case 0n: acc
    case 1n+k: plane.row(k, (x - 1.0 : F32), dx, width, z, Con{(((x / dx : F32) - 0.5 : F32) * width : F32), Con{0.0, Con{z, acc}}})

def plane.vertices.go(n: Nat, +z: F32, +dz: F32, +rx: Nat, +dx: F32, +width: F32, +length: F32, acc: +List<F32>) -> +List<F32>:
  match n:
    case 0n: acc
    case 1n+k: plane.vertices.go(k, (z - 1.0 : F32), dz, rx, dx, width, length,
      plane.row(rx, dx, dx, width, (((z / dz : F32) - 0.5 : F32) * length : F32), acc))

def plane.vertices(+n: Nat, +dz: F32, +rx: Nat, +dx: F32, +width: F32, +length: F32) -> +List<F32>:
  plane.vertices.go(n, dz, dz, rx, dx, width, length, Nil{})

def plane.uv.row(n: Nat, +u: F32, +dx: F32, +v: F32, acc: +List<F32>) -> +List<F32>:
  match n:
    case 0n: acc
    case 1n+k: plane.uv.row(k, (u - 1.0 : F32), dx, v, Con{(u / dx : F32), Con{v, acc}})

def plane.texcoords.go(n: Nat, +v: F32, +dz: F32, +rx: Nat, +dx: F32, acc: +List<F32>) -> +List<F32>:
  match n:
    case 0n: acc
    case 1n+k: plane.texcoords.go(k, (v - 1.0 : F32), dz, rx, dx, plane.uv.row(rx, dx, dx, (v / dz : F32), acc))

def plane.texcoords(+n: Nat, +dz: F32, +rx: Nat, +dx: F32) -> +List<F32>:
  plane.texcoords.go(n, dz, dz, rx, dx, Nil{})

def short(+value: U32) -> U32:
  (value .&. 65535 : U32)

# Faces from the last one backwards (face counting down).
def plane.indices.go(n: Nat, +face: U32, +rx: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k:
      +i = (face + face / (rx - 1) : U32)
      plane.indices.go(k, (face - 1 : U32), rx, Con{short((i + rx : U32)), Con{short((i + 1 : U32)), Con{short(i), Con{short((i + rx : U32)),
        Con{short(((i + rx : U32) + 1 : U32)), Con{short((i + 1 : U32)), acc}}}}}})

def plane.indices(+faces: U32, +rx: U32) -> +List<U32>:
  plane.indices.go(U32.to_nat(faces), (faces - 1 : U32), rx, Nil{})

# -----------------------------------------------------------------------------
# GenMeshCube

def cube.vertices(+width: F32, +height: F32, +length: F32) -> +List<F32>:
  +l = (F32.neg(width) / 2.0 : F32)
  +r = (width / 2.0 : F32)
  +b = (F32.neg(height) / 2.0 : F32)
  +t = (height / 2.0 : F32)
  +k = (F32.neg(length) / 2.0 : F32)
  +f = (length / 2.0 : F32)
  [l, b, f, r, b, f, r, t, f, l, t, f, l, b, k, l, t, k, r, t, k, r, b, k,
   l, t, k, l, t, f, r, t, f, r, t, k, l, b, k, r, b, k, r, b, f, l, b, f,
   r, b, k, r, t, k, r, t, f, r, b, f, l, b, k, l, b, f, l, t, f, l, t, k]

def cube.texcoords() -> +List<F32>:
  [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0,
   0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0,
   1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0]

def cube.normals() -> +List<F32>:
  +m = F32.neg(1.0)
  List.append(&2, F32, constant(4n, [0.0, 0.0, 1.0]), List.append(&2, F32, constant(4n, [0.0, 0.0, m]),
    List.append(&2, F32, constant(4n, [0.0, 1.0, 0.0]), List.append(&2, F32, constant(4n, [0.0, m, 0.0]),
      List.append(&2, F32, constant(4n, [1.0, 0.0, 0.0]), constant(4n, [m, 0.0, 0.0]))))))

def cube.indices(n: Nat, +k: U32) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+m:
      +b = (4 * k : U32)
      Con{b, Con{(b + 1 : U32), Con{(b + 2 : U32), Con{b, Con{(b + 2 : U32), Con{(b + 3 : U32), cube.indices(m, (k + 1 : U32))}}}}}}

# -----------------------------------------------------------------------------
# GenMeshHeightmap: one quad per 2x2 pixel block, height GRAY_VALUE*size.y/255.

# GRAY_VALUE: (float)(r + g + b)/3.0f of a 0xRRGGBBAA color.
def gray(+c: U32) -> F32:
  (U32.to_f32(((c >> 24n) + ((c >> 16n) .&. 255) + ((c >> 8n) .&. 255) : U32)) / 3.0 : F32)

def grays.go(colors: +List<U32>, acc: +List<F32>) -> +List<F32>:
  match colors:
    case Nil{}: reverse(acc)
    case Con{+c, rest}: grays.go(rest, Con{gray(c), acc})

def grays(+colors: +List<U32>) -> +List<F32>:
  grays.go(colors, Nil{})

def rows(n: Nat, +width: Nat, +values: +List<F32>) -> +List<+List<F32>>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{List.take(&2, F32, values, width), rows(k, width, List.drop(&2, F32, values, width))}

type Scale is Data:
  Scale{x: F32, y: F32, z: F32, u: F32, v: F32}

def hm.point(+x: F32, +g: F32, +z: F32, +s: Scale) -> M.Vector3:
  Scale{sx, sy, sz, _, _} = s
  M.Vector3{(x * sx : F32), (g * sy : F32), (z * sz : F32)}

def hm.normal(+fused: Bool, +a: M.Vector3, +b: M.Vector3, +c: M.Vector3) -> M.Vector3:
  normalize(fused, cross(fused, M.Vector3.subtract(b, a), M.Vector3.subtract(c, a)))

def hm.uv(+x: F32, +z: F32, +s: Scale, rest: +List<F32>) -> +List<F32>:
  Scale{_, _, _, du, dv} = s
  +u0 = (x / du : F32)
  +u1 = ((x + 1.0 : F32) / du : F32)
  +v0 = (z / dv : F32)
  +v1 = ((z + 1.0 : F32) / dv : F32)
  Con{u0, Con{v0, Con{u0, Con{v1, Con{u1, Con{v0, Con{u1, Con{v0, Con{u0, Con{v1, Con{u1, Con{v1, rest}}}}}}}}}}}}

def hm.pick(part: U32, +fused: Bool, +x: F32, +z: F32, +s: Scale, +a: M.Vector3, +b: M.Vector3, +c: M.Vector3, +f: M.Vector3, rest: +List<F32>) -> +List<F32>:
  match part:
    case 0: vector.list(a, vector.list(b, vector.list(c, vector.list(c, vector.list(b, vector.list(f, rest))))))
    case 1: hm.uv(x, z, s, rest)
    case _:
      +n1 = hm.normal(fused, a, b, c)
      +n2 = hm.normal(fused, c, b, f)
      vector.list(n1, vector.list(n1, vector.list(n1, vector.list(n2, vector.list(n2, vector.list(n2, rest))))))

# Part 0 the vertices (A, B, C, C, B, F), 1 the texcoords, 2 the normals of
# triangles (A, B, C) and (C, B, F), for the quad at (x, z) with gray values
# g00 = (x, z), g01 = (x, z + 1), g10 = (x + 1, z), g11 = (x + 1, z + 1).
def hm.quad(+part: U32, +fused: Bool, +x: F32, +z: F32, +s: Scale, +g00: F32, +g01: F32, +g10: F32, +g11: F32, rest: +List<F32>) -> +List<F32>:
  +x1 = (x + 1.0 : F32)
  +z1 = (z + 1.0 : F32)
  hm.pick(part, fused, x, z, s, hm.point(x, g00, z, s), hm.point(x, g01, z1, s), hm.point(x1, g10, z, s), hm.point(x1, g11, z1, s), rest)

def hm.row(cur: +List<F32>, next: +List<F32>, +a: F32, +b: F32, +x: F32, +part: U32, +fused: Bool, +z: F32, +s: Scale, rest: +List<F32>) -> +List<F32>:
  match cur next:
    case Con{+c, rc} Con{+d, rd}: hm.quad(part, fused, x, z, s, a, b, c, d, hm.row(rc, rd, c, d, (x + 1.0 : F32), part, fused, z, s, rest))
    case _ _: rest

def hm.row.start(cur: +List<F32>, next: +List<F32>, +part: U32, +fused: Bool, +z: F32, +s: Scale, rest: +List<F32>) -> +List<F32>:
  match cur next:
    case Con{+a, rc} Con{+b, rd}: hm.row(rc, rd, a, b, 0.0, part, fused, z, s, rest)
    case _ _: rest

def hm.rows(lines: +List<+List<F32>>, +previous: +List<F32>, +z: F32, +part: U32, +fused: Bool, +s: Scale) -> +List<F32>:
  match lines:
    case Nil{}: Nil{}
    case Con{+cur, more}: hm.row.start(previous, cur, part, fused, z, s, hm.rows(more, cur, (z + 1.0 : F32), part, fused, s))

def hm.part(lines: +List<+List<F32>>, +part: U32, +fused: Bool, +s: Scale) -> +List<F32>:
  match lines:
    case Nil{}: Nil{}
    case Con{+first, more}: hm.rows(more, first, 0.0, part, fused, s)

# The heightmap's scale factors (size.x/(mapX - 1), size.y/255, size.z/(mapZ
# - 1)) and texcoord divisors.
def hm.scale(+width: U32, +height: U32, size: M.Vector3) -> Scale:
  M.Vector3{x, y, z} = size
  +du = U32.to_f32((width - 1 : U32))
  +dv = U32.to_f32((height - 1 : U32))
  Scale{(x / du : F32), (y / 255.0 : F32), (z / dv : F32), du, dv}

# -----------------------------------------------------------------------------
# GenMeshCubicmap: WHITE cells are cubes (faces toward non-BLACK neighbors
# are skipped), BLACK cells get a floor and a roof; other colors nothing.

type Corner is Data:
  Corner{x: F32, y: F32, z: F32, nx: F32, ny: F32, nz: F32, u: F32, v: F32}

type Cell is Data:
  Cell{x0: F32, x1: F32, z0: F32, z1: F32, h: F32}

# The cube corners v1..v8 of rmodels.c.
def cell.pick(k: U32, +x0: F32, +x1: F32, +z0: F32, +z1: F32, +h: F32) -> M.Vector3:
  match k:
    case 1: M.Vector3{x0, h, z0}
    case 2: M.Vector3{x0, h, z1}
    case 3: M.Vector3{x1, h, z1}
    case 4: M.Vector3{x1, h, z0}
    case 5: M.Vector3{x1, 0.0, z0}
    case 6: M.Vector3{x0, 0.0, z0}
    case 7: M.Vector3{x0, 0.0, z1}
    case _: M.Vector3{x1, 0.0, z1}

def cell.v(+k: U32, +c: Cell) -> M.Vector3:
  Cell{x0, x1, z0, z1, h} = c
  cell.pick(k, x0, x1, z0, z1, h)

def corner.of(+p: M.Vector3, +n: M.Vector3, +u: F32, +v: F32) -> Corner:
  M.Vector3{x, y, z} = p
  M.Vector3{nx, ny, nz} = n
  Corner{x, y, z, nx, ny, nz, u, v}

# Six corners: cube vertices k1..k6 with normal n and texcoords (u, v) pairs.
def face(+c: Cell, +n: M.Vector3, +ks: +List<U32>, +uvs: +List<F32>, rest: +List<Corner>) -> +List<Corner>:
  match ks uvs:
    case Con{+k, more} Con{+u, Con{+v, uv_more}}: Con{corner.of(cell.v(k, c), n, u, v), face(c, n, more, uv_more, rest)}
    case _ _: rest

def face.when(open: Bool, +c: Cell, +n: M.Vector3, +ks: +List<U32>, +uvs: +List<F32>, rest: +List<Corner>) -> +List<Corner>:
  match open:
    case True{}: face(c, n, ks, uvs, rest)
    case False{}: rest

def black(+color: U32) -> Bool:
  U32.is_eq(color, 255)

def white(+color: U32) -> Bool:
  U32.is_eq(color, 4294967295)

def opening(colors: +List<U32>) -> Bool:
  match colors:
    case Nil{}: True{}
    case Con{+c, _}: black(c)

def rest.of(colors: +List<U32>) -> +List<U32>:
  match colors:
    case Nil{}: Nil{}
    case Con{_, more}: more

def cube.cell(+c: Cell, +front: Bool, +back: Bool, +right: Bool, +left: Bool, rest: +List<Corner>) -> +List<Corner>:
  +m = F32.neg(1.0)
  face(c, M.Vector3{0.0, 1.0, 0.0}, [1, 2, 3, 1, 3, 4], [0.0, 0.5, 0.0, 1.0, 0.5, 1.0, 0.0, 0.5, 0.5, 1.0, 0.5, 0.5],
    face(c, M.Vector3{0.0, m, 0.0}, [6, 8, 7, 6, 5, 8], [1.0, 0.5, 0.5, 1.0, 1.0, 1.0, 1.0, 0.5, 0.5, 0.5, 0.5, 1.0],
      face.when(front, c, M.Vector3{0.0, 0.0, 1.0}, [2, 7, 3, 3, 7, 8], [0.0, 0.0, 0.0, 0.5, 0.5, 0.0, 0.5, 0.0, 0.0, 0.5, 0.5, 0.5],
        face.when(back, c, M.Vector3{0.0, 0.0, m}, [1, 5, 6, 1, 4, 5], [1.0, 0.0, 0.5, 0.5, 1.0, 0.5, 1.0, 0.0, 0.5, 0.0, 0.5, 0.5],
          face.when(right, c, M.Vector3{1.0, 0.0, 0.0}, [3, 8, 4, 4, 8, 5], [0.0, 0.0, 0.0, 0.5, 0.5, 0.0, 0.5, 0.0, 0.0, 0.5, 0.5, 0.5],
            face.when(left, c, M.Vector3{m, 0.0, 0.0}, [1, 7, 2, 1, 6, 7], [0.5, 0.0, 1.0, 0.5, 1.0, 0.0, 0.5, 0.0, 0.5, 0.5, 1.0, 0.5], rest))))))

def floor.cell(+c: Cell, rest: +List<Corner>) -> +List<Corner>:
  face(c, M.Vector3{0.0, F32.neg(1.0), 0.0}, [1, 3, 2, 1, 4, 3], [0.0, 0.5, 0.5, 1.0, 0.0, 1.0, 0.0, 0.5, 0.5, 0.5, 0.5, 1.0],
    face(c, M.Vector3{0.0, 1.0, 0.0}, [6, 7, 8, 6, 8, 5], [1.0, 0.5, 1.0, 1.0, 0.5, 1.0, 1.0, 0.5, 0.5, 1.0, 0.5, 0.5], rest))

def map.cell.kind(kind: U32, +c: Cell, +front: Bool, +back: Bool, +right: Bool, +left: Bool, rest: +List<Corner>) -> +List<Corner>:
  match kind:
    case 0: cube.cell(c, front, back, right, left, rest)
    case 1: floor.cell(c, rest)
    case _: rest

def map.cell(+color: U32, +c: Cell, +front: Bool, +back: Bool, +right: Bool, +left: Bool, rest: +List<Corner>) -> +List<Corner>:
  map.cell.kind(Bool.pick(U32, white(color), 0, Bool.pick(U32, black(color), 1, 2)), c, front, back, right, left, rest)

type Cubes is Data:
  Cubes{w: F32, h: F32, h2: F32}

def map.at(+k: Cubes, +x: F32, +z: F32) -> Cell:
  Cubes{w, h, h2} = k
  Cell{(w * (x - 0.5 : F32) : F32), (w * (x + 0.5 : F32) : F32), (h * (z - 0.5 : F32) : F32), (h * (z + 0.5 : F32) : F32), h2}

def map.row(cur: +List<U32>, +left: Bool, +ups: +List<U32>, +downs: +List<U32>, +x: F32, +z: F32, +k: Cubes, rest: +List<Corner>) -> +List<Corner>:
  match cur:
    case Nil{}: rest
    case Con{+c, +more}: map.cell(c, map.at(k, x, z), opening(downs), opening(ups), opening(more), left,
      map.row(more, black(c), rest.of(ups), rest.of(downs), (x + 1.0 : F32), z, k, rest))

def map.next(lines: +List<+List<U32>>) -> +List<U32>:
  match lines:
    case Nil{}: Nil{}
    case Con{+next, _}: next

def map.rows(lines: +List<+List<U32>>, +previous: +List<U32>, +z: F32, +k: Cubes) -> +List<Corner>:
  match lines:
    case Nil{}: Nil{}
    case Con{+cur, +more}: map.row(cur, True{}, previous, map.next(more), 0.0, z, k, map.rows(more, cur, (z + 1.0 : F32), k))

def rows.u32(n: Nat, +width: Nat, +values: +List<U32>) -> +List<+List<U32>>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{List.take(&2, U32, values, width), rows.u32(k, width, List.drop(&2, U32, values, width))}

def corners.vertices(cs: +List<Corner>, acc: +List<F32>) -> +List<F32>:
  match cs:
    case Nil{}: reverse(acc)
    case Con{Corner{x, y, z, _, _, _, _, _}, rest}: corners.vertices(rest, Con{z, Con{y, Con{x, acc}}})

def corners.normals(cs: +List<Corner>, acc: +List<F32>) -> +List<F32>:
  match cs:
    case Nil{}: reverse(acc)
    case Con{Corner{_, _, _, x, y, z, _, _}, rest}: corners.normals(rest, Con{z, Con{y, Con{x, acc}}})

def corners.texcoords(cs: +List<Corner>, acc: +List<F32>) -> +List<F32>:
  match cs:
    case Nil{}: reverse(acc)
    case Con{Corner{_, _, _, _, _, _, u, v}, rest}: corners.texcoords(rest, Con{v, Con{u, acc}})

def corners.count(cs: +List<Corner>, +n: U32) -> U32:
  match cs:
    case Nil{}: n
    case Con{_, rest}: corners.count(rest, (n + 1 : U32))

# -----------------------------------------------------------------------------
# Random access for GenMeshTangents and GetRayCollisionMesh: a balanced tree
# of Vector3 values (read-only, shared) and F32 arrays (accumulators).

type Tree is Data:
  Tip{}
  Leaf{value: M.Vector3}
  Node{left: Tree, right: Tree}

def trees.reverse(xs: +List<Tree>, acc: +List<Tree>) -> +List<Tree>:
  match xs:
    case Nil{}: acc
    case Con{+t, rest}: trees.reverse(rest, Con{t, acc})

def leaves(xs: +List<M.Vector3>, acc: +List<Tree>) -> +List<Tree>:
  match xs:
    case Nil{}: trees.reverse(acc, Nil{})
    case Con{+v, rest}: leaves(rest, Con{Leaf{v}, acc})

def pairs(xs: +List<Tree>, acc: +List<Tree>) -> +List<Tree>:
  match xs:
    case Con{+a, Con{+b, rest}}: pairs(rest, Con{Node{a, b}, acc})
    case Con{+a, Nil{}}: trees.reverse(Con{Node{a, Tip{}}, acc}, Nil{})
    case _: trees.reverse(acc, Nil{})

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

def vectors.reverse(xs: +List<M.Vector3>, acc: +List<M.Vector3>) -> +List<M.Vector3>:
  match xs:
    case Nil{}: acc
    case Con{+v, rest}: vectors.reverse(rest, Con{v, acc})

def vectors.go(xs: +List<F32>, acc: +List<M.Vector3>) -> +List<M.Vector3>:
  match xs:
    case Con{+x, Con{+y, Con{+z, rest}}}: vectors.go(rest, Con{M.Vector3{x, y, z}, acc})
    case _: vectors.reverse(acc, Nil{})

def vectors(+xs: +List<F32>) -> +List<M.Vector3>:
  vectors.go(xs, Nil{})

def pairs.uv.go(xs: +List<F32>, acc: +List<M.Vector3>) -> +List<M.Vector3>:
  match xs:
    case Con{+u, Con{+v, rest}}: pairs.uv.go(rest, Con{M.Vector3{u, v, 0.0}, acc})
    case _: vectors.reverse(acc, Nil{})

def pairs.uv(+xs: +List<F32>) -> +List<M.Vector3>:
  pairs.uv.go(xs, Nil{})

# A tree of 2^d leaves (d = depth(count)).
def tree.of(+d: Nat, +xs: +List<M.Vector3>) -> Tree:
  tree.first(levels(d, leaves(xs, Nil{})))

def tree.get(+d: Nat, t: Tree, +i: U32) -> M.Vector3:
  match d t:
    case 0n Leaf{v}: v
    case 1n+k Node{l, r}: tree.get(k, Bool.pick(Tree, U32.is_eq(((i >> k) .&. 1 : U32), 1), r, l), i)
    case _ _: M.Vector3{0.0, 0.0, 0.0}

def at3.z(r: Array<F32> & F32, +x: F32, +y: F32) -> Array<F32> & M.Vector3:
  (a, +z) = r
  (a, M.Vector3{x, y, z})

def at3.y(r: Array<F32> & F32, +base: U32, +x: F32) -> Array<F32> & M.Vector3:
  (a, +y) = r
  at3.z(Array.get(F32, a, (base + 2 : U32)), x, y)

def at3.x(r: Array<F32> & F32, +base: U32) -> Array<F32> & M.Vector3:
  (a, +x) = r
  at3.y(Array.get(F32, a, (base + 1 : U32)), base, x)

def at3(a: Array<F32>, +i: U32) -> Array<F32> & M.Vector3:
  +base = (i * 3 : U32)
  at3.x(Array.get(F32, a, base), base)

def add3.parts(a: Array<F32>, +base: U32, old: M.Vector3, v: M.Vector3) -> Array<F32>:
  M.Vector3{x, y, z} = old
  M.Vector3{p, q, r} = v
  Array.set(F32, Array.set(F32, Array.set(F32, a, base, (x + p : F32)), (base + 1 : U32), (y + q : F32)), (base + 2 : U32), (z + r : F32))

def add3.with(r: Array<F32> & M.Vector3, +i: U32, v: M.Vector3) -> Array<F32>:
  (a, old) = r
  add3.parts(a, (i * 3 : U32), old, v)

# Vector3Add(acc[i], v)
def add3(a: Array<F32>, +i: U32, v: M.Vector3) -> Array<F32>:
  add3.with(at3(a, i), i, v)

def sequence.go(n: Nat, +i: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: sequence.go(k, (i - 1 : U32), Con{i, acc})

# 0 .. count - 1
def sequence(+count: U32) -> +List<U32>:
  sequence.go(U32.to_nat(count), (count - 1 : U32), Nil{})

# -----------------------------------------------------------------------------
# GenMeshTangents: per triangle sdir/tdir (r = 0 for |div| < 0.0001f)
# accumulated per vertex, then Gram-Schmidt against the normal, with
# Vector3Normalize((-n.y, n.x, 0)) (or (1, 0, 0) when |n.z| > 0.707f) for
# tangents shorter than 0.0001f, and the handedness sign.

def small() -> F32:
  F.float(953267991)

def tan.r(+fused: Bool, +s1: F32, +t1: F32, +s2: F32, +t2: F32) -> F32:
  +div = dif(fused, s1, t2, s2, t1)
  Bool.pick(F32, (F32.abs(div) < small() : F32), 0.0, (1.0 / div : F32))

type Edges is Data:
  Edges{x1: F32, y1: F32, z1: F32, x2: F32, y2: F32, z2: F32, s1: F32, t1: F32, s2: F32, t2: F32}

def edges(v1: M.Vector3, v2: M.Vector3, v3: M.Vector3, w1: M.Vector3, w2: M.Vector3, w3: M.Vector3) -> Edges:
  M.Vector3{+ax, +ay, +az} = v1
  M.Vector3{bx, by, bz} = v2
  M.Vector3{cx, cy, cz} = v3
  M.Vector3{+u1, +q1, _} = w1
  M.Vector3{u2, q2, _} = w2
  M.Vector3{u3, q3, _} = w3
  Edges{(bx - ax : F32), (by - ay : F32), (bz - az : F32), (cx - ax : F32), (cy - ay : F32), (cz - az : F32),
    (u2 - u1 : F32), (q2 - q1 : F32), (u3 - u1 : F32), (q3 - q1 : F32)}

# sdir = ((t2*x1 - t1*x2)*r, ...)
def tan.s(+fused: Bool, +e: Edges) -> M.Vector3:
  Edges{+x1, +y1, +z1, +x2, +y2, +z2, +s1, +t1, +s2, +t2} = e
  +r = tan.r(fused, s1, t1, s2, t2)
  M.Vector3{(dif(fused, t2, x1, t1, x2) * r : F32), (dif(fused, t2, y1, t1, y2) * r : F32), (dif(fused, t2, z1, t1, z2) * r : F32)}

# tdir = ((s1*x2 - s2*x1)*r, ...)
def tan.t(+fused: Bool, +e: Edges) -> M.Vector3:
  Edges{+x1, +y1, +z1, +x2, +y2, +z2, +s1, +t1, +s2, +t2} = e
  +r = tan.r(fused, s1, t1, s2, t2)
  M.Vector3{(dif(fused, s1, x2, s2, x1) * r : F32), (dif(fused, s1, y2, s2, y1) * r : F32), (dif(fused, s1, z2, s2, z1) * r : F32)}

def tan.edges(+d: Nat, +pos: Tree, +uv: Tree, +i0: U32, +i1: U32, +i2: U32) -> Edges:
  edges(tree.get(d, pos, i0), tree.get(d, pos, i1), tree.get(d, pos, i2), tree.get(d, uv, i0), tree.get(d, uv, i1), tree.get(d, uv, i2))

def tan.loop(tris: +List<U32>, +fused: Bool, +d: Nat, +pos: Tree, +uv: Tree, t1: Array<F32>, t2: Array<F32>) -> Array<F32> & Array<F32>:
  match tris:
    case Con{+i0, Con{+i1, Con{+i2, rest}}}:
      +e = tan.edges(d, pos, uv, i0, i1, i2)
      +s = tan.s(fused, e)
      +t = tan.t(fused, e)
      tan.loop(rest, fused, d, pos, uv, add3(add3(add3(t1, i0, s), i1, s), i2, s), add3(add3(add3(t2, i0, t), i1, t), i2, t))
    case _: (t1, t2)

def tan.perpendicular(+fused: Bool, n: M.Vector3) -> M.Vector3:
  M.Vector3{x, y, z} = n
  Bool.pick(M.Vector3, (F32.abs(z) > F.float(1060437492) : F32), M.Vector3{1.0, 0.0, 0.0}, normalize(fused, M.Vector3{F32.neg(y), x, 0.0}))

# The tangent reversed (w, z, y, x) onto acc.
def tan.out(+v: M.Vector3, +w: F32, acc: +List<F32>) -> +List<F32>:
  M.Vector3{x, y, z} = v
  Con{w, Con{z, Con{y, Con{x, acc}}}}

def tan.oriented(+fused: Bool, +n: M.Vector3, +o: M.Vector3, +b: M.Vector3, acc: +List<F32>) -> +List<F32>:
  tan.out(o, Bool.pick(F32, (dot(fused, cross(fused, n, o), b) < 0.0 : F32), F32.neg(1.0), 1.0), acc)

def tan.orthogonal(+fused: Bool, +n: M.Vector3, +t: M.Vector3, +b: M.Vector3, acc: +List<F32>) -> +List<F32>:
  +o = M.Vector3.subtract(t, M.Vector3.scale(n, dot(fused, n, t)))
  tan.oriented(fused, n, Bool.pick(M.Vector3, (length(fused, o) < small() : F32), tan.perpendicular(fused, n), normalize(fused, o)), b, acc)

def tan.final.pick(short: Bool, +fused: Bool, +n: M.Vector3, +t: M.Vector3, +b: M.Vector3, acc: +List<F32>) -> +List<F32>:
  match short:
    case True{}: tan.out(tan.perpendicular(fused, n), 1.0, acc)
    case False{}: tan.orthogonal(fused, n, t, b, acc)

def tan.final(+fused: Bool, +n: M.Vector3, +t: M.Vector3, +b: M.Vector3, acc: +List<F32>) -> +List<F32>:
  tan.final.pick((length(fused, t) < small() : F32), fused, n, t, b, acc)

def tan.final.loop(n: Nat, +fused: Bool, normals: +List<F32>, t1: List<F32>, t2: List<F32>, acc: +List<F32>) -> +List<F32>:
  match n normals t1 t2:
    case 1n+k Con{+nx, Con{+ny, Con{+nz, nr}}} Con{+ax, Con{+ay, Con{+az, ar}}} Con{+bx, Con{+by, Con{+bz, br}}}:
      tan.final.loop(k, fused, nr, ar, br, tan.final(fused, M.Vector3{nx, ny, nz}, M.Vector3{ax, ay, az}, M.Vector3{bx, by, bz}, acc))
    case _ _ _ _: reverse(acc)

def tan.finish(+n: Nat, +fused: Bool, normals: +List<F32>, sums: Array<F32> & Array<F32>) -> +List<F32>:
  (t1, t2) = sums
  tan.final.loop(n, fused, normals, Array.to_list(~F32, t1), Array.to_list(~F32, t2), Nil{})

# The tangents (4 floats per vertex) of a mesh whose vertices, texcoords and
# normals hold vertex_count elements and whose triangles are tris (vertex
# indices, all below vertex_count).
def tangents(+fused: Bool, +vertex_count: U32, +vertices: +List<F32>, +texcoords: +List<F32>, +normals: +List<F32>, +tris: +List<U32>) -> +List<F32>:
  +d = depth(vertex_count)
  +cells = depth((vertex_count * 3 : U32))
  tan.finish(U32.to_nat(vertex_count), fused, normals, tan.loop(tris, fused, d, tree.of(d, vectors(vertices)), tree.of(d, pairs.uv(texcoords)),
    Array.new(F32, cells, 0.0), Array.new(F32, cells, 0.0)))

# -----------------------------------------------------------------------------
# GetMeshBoundingBox: Vector3Min/Vector3Max (fminf/fmaxf, profiled) over the
# vertices from the first.

def bbox.loop(vs: +List<F32>, +libm: M.Libm, +lo: M.Vector3, +hi: M.Vector3) -> M.Vector3 & M.Vector3:
  match vs:
    case Con{+x, Con{+y, Con{+z, rest}}}: bbox.loop(rest, libm, M.Vector3.min_for(libm, lo, M.Vector3{x, y, z}), M.Vector3.max_for(libm, hi, M.Vector3{x, y, z}))
    case _: (lo, hi)

def bbox(+libm: M.Libm, vs: +List<F32>) -> M.Vector3 & M.Vector3:
  match vs:
    case Con{+x, Con{+y, Con{+z, rest}}}: bbox.loop(rest, libm, M.Vector3{x, y, z}, M.Vector3{x, y, z})
    case _: (M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 0.0, 0.0})

# -----------------------------------------------------------------------------
# Text: ExportMesh's OBJ and ExportMeshAsCode's file. The text is built as
# reversed characters (tail-recursive, for any mesh size); ok is False when a
# value has no reproduced spelling (NaN prints differently per C library) or
# raylib would read outside an array.

type Out is Data:
  Out{ok: Bool, chars: +List<Char>}

def Out.new() -> Out:
  Out{True{}, Nil{}}

def push(s: String, acc: +List<Char>) -> +List<Char>:
  match s:
    case SNil{}: acc
    case SCon{+c, rest}: push(rest, Con{c, acc})

def Out.put(o: Out, +s: String) -> Out:
  Out{ok, chars} = o
  Out{ok, push(s, chars)}

def Out.fail(o: Out) -> Out:
  Out{_, chars} = o
  Out{False{}, chars}

def Out.maybe(o: Out, m: Maybe<String>) -> Out:
  match m:
    case None{}: Out.fail(o)
    case Some{s}: Out.put(o, s)

# "%.<places>f" of x (None for NaN, whose spelling differs between C libraries).
def Out.fixed(o: Out, +x: F32, +places: Nat) -> Out:
  Out.maybe(o, Decimal.fixed(F32.bits(x), places))

def chars.count(cs: +List<Char>, +n: U32) -> U32:
  match cs:
    case Nil{}: n
    case Con{_, rest}: chars.count(rest, (n + 1 : U32))

def chars.string(cs: +List<Char>, s: String) -> String:
  match cs:
    case Nil{}: s
    case Con{+c, rest}: chars.string(rest, SCon{c, s})

# The text when every value was reproduced and it is shorter than capacity
# (raylib's buffer, with room for the terminator).
def Out.result(o: Out, +capacity: U32) -> Maybe<String>:
  Out{ok, +chars} = o
  Bool.pick(Maybe<String>, ok && (chars.count(chars, 0) < capacity : U32), Some{chars.string(chars, SNil{})}, None{})

def length.of(+s: String, +n: U32) -> U32:
  match s:
    case SNil{}: n
    case SCon{_, rest}: length.of(rest, (n + 1 : U32))

def digits(+n: U32) -> U32:
  length.of(U32.show(n), 0)

def obj.header(+vertex_count: U32, +triangle_count: U32) -> String:
  "# //////////////////////////////////////////////////////////////////////////////////\n" ++
    "# //                                                                              //\n" ++
    "# // rMeshOBJ exporter v1.0 - Mesh exported as triangle faces and not optimized   //\n" ++
    "# //                                                                              //\n" ++
    "# // more info and bugs-report:  github.com/raysan5/raylib                        //\n" ++
    "# // feedback and support:       ray[at]raylib.com                                //\n" ++
    "# //                                                                              //\n" ++
    "# // Copyright (c) 2018-2026 Ramon Santamaria (@raysan5)                          //\n" ++
    "# //                                                                              //\n" ++
    "# //////////////////////////////////////////////////////////////////////////////////\n\n" ++
    "# Vertex Count:     " ++ U32.show(vertex_count) ++ "\n" ++
    "# Triangle Count:   " ++ U32.show(triangle_count) ++ "\n\n" ++
    "g mesh\n"

def obj.three(o: Out, +tag: String, +places: Nat, +x: F32, +y: F32, +z: F32) -> Out:
  Out.put(Out.fixed(Out.put(Out.fixed(Out.put(Out.fixed(Out.put(o, tag), x, places), " "), y, places), " "), z, places), "\n")

def obj.positions(vs: +List<F32>, +tag: String, +places: Nat, o: Out) -> Out:
  match vs:
    case Con{+x, Con{+y, Con{+z, more}}}: obj.positions(more, tag, places, obj.three(o, tag, places, x, y, z))
    case _: o

def obj.texcoords(vs: +List<F32>, o: Out) -> Out:
  match vs:
    case Con{+u, Con{+v, more}}: obj.texcoords(more, Out.put(Out.fixed(Out.put(Out.fixed(Out.put(o, "vt "), u, 6n), " "), v, 6n), "\n"))
    case _: o

def obj.face(o: Out, +a: U32, +b: U32, +c: U32) -> Out:
  +sa = U32.show(a)
  +sb = U32.show(b)
  +sc = U32.show(c)
  Out.put(o, "f " ++ sa ++ "/" ++ sa ++ "/" ++ sa ++ " " ++ sb ++ "/" ++ sb ++ "/" ++ sb ++ " " ++ sc ++ "/" ++ sc ++ "/" ++ sc ++ "\n")

def obj.indexed(xs: +List<U32>, o: Out) -> Out:
  match xs:
    case Con{+a, Con{+b, Con{+c, rest}}}: obj.indexed(rest, obj.face(o, (a + 1 : U32), (b + 1 : U32), (c + 1 : U32)))
    case _: o

def obj.sequential(n: Nat, +v: U32, o: Out) -> Out:
  match n:
    case 0n: o
    case 1n+k: obj.sequential(k, (v + 3 : U32), obj.face(o, v, (v + 1 : U32), (v + 2 : U32)))

def obj.faces(indices: Maybe<&2, +List<U32>>, +tc: U32, o: Out) -> Out:
  match indices:
    case None{}: obj.sequential(U32.to_nat(tc), 1, o)
    case Some{+xs}: obj.indexed(xs, o)

# ExportMesh's buffer: dataSize + 1000 bytes, dataSize estimated from the
# counts.
def obj.capacity(+vertex_count: U32, +triangle_count: U32) -> U32:
  ((vertex_count * 99 : U32) + (triangle_count * ((9 * digits(vertex_count) : U32) + 11 : U32) : U32) + 1000 : U32)

# ExportMesh's text for a mesh with vertices, texcoords and normals and its
# faces (indexed, or 1, 4, 7, ... without indices), None when a value is
# NaN or the text overflows raylib's buffer.
def obj(+vertex_count: U32, +triangle_count: U32, +vertices: +List<F32>, +texcoords: +List<F32>, +normals: +List<F32>, +indices: Maybe<&2, +List<U32>>) -> Maybe<String>:
  Out.result(obj.faces(indices, triangle_count, obj.positions(normals, "vn ", 4n, obj.texcoords(texcoords, obj.positions(vertices, "v ", 6n,
    Out.put(Out.new(), obj.header(vertex_count, triangle_count)))))), obj.capacity(vertex_count, triangle_count))

def code.header() -> String:
  "////////////////////////////////////////////////////////////////////////////////////////\n" ++
    "//                                                                                    //\n" ++
    "// MeshAsCode exporter v1.0 - Mesh vertex data exported as arrays                     //\n" ++
    "//                                                                                    //\n" ++
    "// more info and bugs-report:  github.com/raysan5/raylib                              //\n" ++
    "// feedback and support:       ray[at]raylib.com                                      //\n" ++
    "//                                                                                    //\n" ++
    "// Copyright (c) 2023 Ramon Santamaria (@raysan5)                                     //\n" ++
    "//                                                                                    //\n" ++
    "////////////////////////////////////////////////////////////////////////////////////////\n\n"

def separator(+i: U32) -> String:
  Bool.pick(String, U32.is_eq((i % 20 : U32), 0), ",\n", ", ")

def code.floats.loop(xs: +List<F32>, +prev: F32, +i: U32, o: Out) -> Out:
  match xs:
    case Nil{}: Out.put(Out.fixed(o, prev, 3n), "f };\n\n")
    case Con{+x, rest}: code.floats.loop(rest, x, (i + 1 : U32), Out.put(Out.fixed(o, prev, 3n), "f" ++ separator(i)))

# "static float NAME_KIND[count] = { ...%.3ff... };" (an empty array reads
# element -1).
def code.floats(values: Maybe<&2, +List<F32>>, +name: String, +kind: String, +count: U32, o: Out) -> Out:
  match values:
    case None{}: o
    case Some{Nil{}}: Out.fail(o)
    case Some{Con{+x, rest}}: code.floats.loop(rest, x, 0, Out.put(o, "static float " ++ name ++ "_" ++ kind ++ "[" ++ U32.show(count) ++ "] = { "))

def hex.digit(+d: U32) -> String:
  SCon{Char.from_u32(Bool.pick(U32, (d < 10 : U32), (d + 48 : U32), (d + 87 : U32))), SNil{}}

def hex.byte(+b: U32) -> String:
  Bool.pick(String, (b < 16 : U32), hex.digit(b), hex.digit((b >> 4n : U32)) ++ hex.digit((b .&. 15 : U32)))

def code.colors.loop(xs: +List<U32>, +prev: U32, +i: U32, o: Out) -> Out:
  match xs:
    case Nil{}: Out.put(o, "0x" ++ hex.byte(prev) ++ " };\n\n")
    case Con{+x, rest}: code.colors.loop(rest, x, (i + 1 : U32), Out.put(o, "0x" ++ hex.byte(prev) ++ separator(i)))

def code.colors(values: Maybe<&2, +List<U32>>, +name: String, +count: U32, o: Out) -> Out:
  match values:
    case None{}: o
    case Some{Nil{}}: Out.fail(o)
    case Some{Con{+x, rest}}: code.colors.loop(rest, x, 0, Out.put(o, "static unsigned char " ++ name ++ "_COLOR_DATA[" ++ U32.show(count) ++ "] = { "))

def code.indices.loop(xs: +List<U32>, +prev: U32, +i: U32, o: Out) -> Out:
  match xs:
    case Nil{}: Out.put(o, U32.show(prev) ++ " };\n")
    case Con{+x, rest}: code.indices.loop(rest, x, (i + 1 : U32), Out.put(o, U32.show(prev) ++ separator(i)))

def code.indices(values: Maybe<&2, +List<U32>>, +name: String, +count: U32, o: Out) -> Out:
  match values:
    case None{}: o
    case Some{Nil{}}: Out.fail(o)
    case Some{Con{+x, rest}}: code.indices.loop(rest, x, 0, Out.put(o, "static unsigned short " ++ name ++ "_INDEX_DATA[" ++ U32.show(count) ++ "] = { "))

# varFileName: a-z upper-cased (other characters kept).
def upper.go(s: String, acc: +List<Char>) -> String:
  match s:
    case SNil{}: chars.string(acc, SNil{})
    case SCon{+c, rest}:
      +u = Char.to_u32(c)
      upper.go(rest, Con{Bool.pick(Char, (u >= 97 : U32) && (u <= 122 : U32), Char.from_u32((u - 32 : U32)), c), acc})

def upper(s: String) -> String:
  upper.go(s, Nil{})

def code.intro(+name: String, +vertex_count: U32, +triangle_count: U32) -> String:
  code.header() ++ "// Mesh basic information\n" ++
    "#define " ++ name ++ "_VERTEX_COUNT    " ++ U32.show(vertex_count) ++ "\n" ++
    "#define " ++ name ++ "_TRIANGLE_COUNT   " ++ U32.show(triangle_count) ++ "\n\n"

type Arrays is Data:
  Arrays{vertices: Maybe<&2, +List<F32>>, texcoords: Maybe<&2, +List<F32>>, texcoords2: Maybe<&2, +List<F32>>, normals: Maybe<&2, +List<F32>>,
    tangents: Maybe<&2, +List<F32>>, colors: Maybe<&2, +List<U32>>, indices: Maybe<&2, +List<U32>>}

# ExportMeshAsCode's text (raylib's buffer is 64 MB).
def code(+name: String, +vertex_count: U32, +triangle_count: U32, arrays: Arrays) -> Maybe<String>:
  Arrays{vertices, texcoords, texcoords2, normals, tangents, colors, indices} = arrays
  +vc = vertex_count
  Out.result(code.indices(indices, name, (triangle_count * 3 : U32), code.colors(colors, name, (vc * 4 : U32),
    code.floats(tangents, name, "TANGENT_DATA", (vc * 4 : U32), code.floats(normals, name, "NORMAL_DATA", (vc * 3 : U32),
      code.floats(texcoords2, name, "TEXCOORD2_DATA", (vc * 2 : U32), code.floats(texcoords, name, "TEXCOORD_DATA", (vc * 2 : U32),
        code.floats(vertices, name, "VERTEX_DATA", (vc * 3 : U32), Out.put(Out.new(), code.intro(name, vc, triangle_count))))))))), 67108864)
