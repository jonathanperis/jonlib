# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of par_shapes (https://github.com/prideout/par,
# Copyright (c) 2019 Philip Rideout, MIT; LICENSES/par_shapes.txt) as raylib
# 6.0 vendors it in src/external/par_shapes.h, for GenMeshSphere,
# GenMeshHemiSphere and GenMeshTorus (rmodels.c, zlib; LICENSES/raylib.txt):
# par_shapes_create_parametric with the sphere, hemisphere and torus
# functions, par_shapes__compute_welded_normals (par_shapes_weld's grid sort,
# point welding and condensing, then par_shapes_compute_normals on the welded
# mesh) and par_shapes_remove_degenerate. The weld sorts points with the C
# library's qsort, whose order of equal keys is the library's: only glibc's
# stable merge sort (a stable counting sort here, same order) is modeled, so
# these generators need a glibc M.Libm profile. Arithmetic keeps
# par_shapes' F32 order; its products, dot products and cross products are
# fused (fma) when the reference contracts them. uv*PAR_PI is a binary64
# product rounded to F32 (src/binary64_ops.bend). See docs/MODELS.md.
import Base
import ./../jonmath.bend as M
import ./frame.bend as F
import ./shapes3d.bend as S3
import ./mesh.bend as Mesh
import ./binary64_fma.bend as W
import ./binary64_ops.bend as O
import ./binary64_narrow.bend as Narrow

# -----------------------------------------------------------------------------
# Parametric points

# (float)((double)u*PAR_PI) with PAR_PI = 3.14159265359 (0x400921FB54442EEA).
def pi.bits(m: Maybe<U32>) -> Maybe<&2, F32>:
  match m:
    case None{}: None{}
    case Some{+b}: Some{F.float(b)}

def pi.product(w: Maybe<W.Words>) -> Maybe<&2, F32>:
  match w:
    case None{}: None{}
    case Some{W.Words{+h, l}}: pi.bits(Narrow.checked(h, l))

def pi.promoted(w: Maybe<W.Words>) -> Maybe<&2, F32>:
  match w:
    case None{}: None{}
    case Some{W.Words{+h, +l}}: pi.product(O.checked_multiply(h, l, 1074340347, 1413754602))

def pi.times(+u: F32) -> Maybe<&2, F32>:
  pi.promoted(O.checked_promote(F32.bits(u)))

# One parameter value: u, and cosf/sinf of its angle (ok when reproduced).
type Ent is Data:
  Ent{u: F32, c: F32, s: F32, ok: Bool}

def Ent.with(+u: F32, +v: S3.SC) -> Ent:
  Ent{u, S3.SC.cos(v), S3.SC.sin(v), S3.SC.ok(v)}

def Ent.angle(+gnu: Bool, +u: F32, a: Maybe<&2, F32>) -> Ent:
  match a:
    case None{}: Ent{u, 0.0, 0.0, False{}}
    case Some{+x}: Ent.with(u, S3.sc(gnu, x))

def Ent.u(+e: Ent) -> F32:
  Ent{u, _, _, _} = e
  u

def Ent.c(+e: Ent) -> F32:
  Ent{_, c, _, _} = e
  c

def Ent.s(+e: Ent) -> F32:
  Ent{_, _, s, _} = e
  s

def Ent.ok(+e: Ent) -> Bool:
  Ent{_, _, _, ok} = e
  ok

# Entries i = count .. 0 prepended (ascending result): u = (float)i/count, the
# angle (float)(u*PAR_PI), or (float)((u*2)*PAR_PI) when doubled.
def table.go(n: Nat, +gnu: Bool, +doubled: Bool, +i: F32, +count: F32, acc: +List<Ent>) -> +List<Ent>:
  match n:
    case 0n: acc
    case 1n+k:
      +u = (i / count : F32)
      table.go(k, gnu, doubled, (i - 1.0 : F32), count, Con{Ent.angle(gnu, u, pi.times(Bool.pick(F32, doubled, (u * 2.0 : F32), u))), acc})

def table(+gnu: Bool, +doubled: Bool, +count: U32) -> +List<Ent>:
  table.go(U32.to_nat((count + 1 : U32)), gnu, doubled, U32.to_f32(count), U32.to_f32(count), Nil{})

def table.ok(es: +List<Ent>, +ok: Bool) -> Bool:
  match es:
    case Nil{}: ok
    case Con{+e, rest}: table.ok(rest, ok && Ent.ok(e))

def ents.reverse(xs: +List<Ent>, acc: +List<Ent>) -> +List<Ent>:
  match xs:
    case Nil{}: acc
    case Con{+e, rest}: ents.reverse(rest, Con{e, acc})

# par_shapes__sphere / __hemisphere (a: phi from uv[0], b: theta from uv[1])
# and __torus (a: theta from uv[0], b: phi from uv[1]; beta = 1 + minor*cosf(phi)).
def point(+kind: U32, +fused: Bool, +minor: F32, +a: Ent, +b: Ent) -> M.Vector3:
  match kind:
    case 2:
      +beta = Mesh.mad(fused, minor, Ent.c(b), 1.0)
      M.Vector3{(Ent.c(a) * beta : F32), (Ent.s(a) * beta : F32), (Ent.s(b) * minor : F32)}
    case _: M.Vector3{(Ent.c(b) * Ent.s(a) : F32), (Ent.s(b) * Ent.s(a) : F32), Ent.c(a)}

# A grid row (slices descending) prepended to the accumulators.
type Grid is Data:
  Grid{points: +List<M.Vector3>, uvs: +List<M.Vector3>}

def grid.put(+p: M.Vector3, +uv: M.Vector3, acc: Grid) -> Grid:
  Grid{points, uvs} = acc
  Grid{Con{p, points}, Con{uv, uvs}}

def grid.row(bs: +List<Ent>, +kind: U32, +fused: Bool, +minor: F32, +a: Ent, acc: Grid) -> Grid:
  match bs:
    case Nil{}: acc
    case Con{+b, rest}: grid.row(rest, kind, fused, minor, a, grid.put(point(kind, fused, minor, a, b), M.Vector3{Ent.u(a), Ent.u(b), 0.0}, acc))

# Stacks and slices descending (rows reversed), so the lists come out in
# par_shapes' order: stack-major, slice-minor.
def grid.rows(as: +List<Ent>, +bs: +List<Ent>, +kind: U32, +fused: Bool, +minor: F32, acc: Grid) -> Grid:
  match as:
    case Nil{}: acc
    case Con{+a, rest}: grid.rows(rest, bs, kind, fused, minor, grid.row(bs, kind, fused, minor, a, acc))

# Faces of par_shapes_create_parametric, built backwards.
def faces.row(n: Nat, +slice: U32, +v: U32, +slices: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k:
      +next = (slice + 1 : U32)
      +up = (v + slice + slices + 1 : U32)
      faces.row(k, (slice - 1 : U32), v, slices, Con{up, Con{(v + next : U32), Con{(v + slice : U32), Con{up, Con{(v + next + slices + 1 : U32), Con{(v + next : U32), acc}}}}}})

def faces(n: Nat, +stack: U32, +slices: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: faces(k, (stack - 1 : U32), slices, faces.row(U32.to_nat(slices), (slices - 1 : U32), (stack * (slices + 1) : U32), slices, acc))

# -----------------------------------------------------------------------------
# par_shapes_weld (grid of 20 cells, epsilon 0.001f) and par_shapes_compute_normals

type Box is Data:
  Box{lx: F32, ly: F32, lz: F32, hx: F32, hy: F32, hz: F32}

# PAR_MIN(p, a) = p > a ? a : p, PAR_MAX(p, a) = p > a ? p : a.
def box.add(+b: Box, p: M.Vector3) -> Box:
  Box{lx, ly, lz, hx, hy, hz} = b
  M.Vector3{+x, +y, +z} = p
  Box{Bool.pick(F32, (x > lx : F32), lx, x), Bool.pick(F32, (y > ly : F32), ly, y), Bool.pick(F32, (z > lz : F32), lz, z),
    Bool.pick(F32, (x > hx : F32), x, hx), Bool.pick(F32, (y > hy : F32), y, hy), Bool.pick(F32, (z > hz : F32), z, hz)}

def box.loop(ps: +List<M.Vector3>, +b: Box) -> Box:
  match ps:
    case Nil{}: b
    case Con{+p, rest}: box.loop(rest, box.add(b, p))

def box.of(ps: +List<M.Vector3>) -> Box:
  match ps:
    case Nil{}: Box{0.0, 0.0, 0.0, 0.0, 0.0, 0.0}
    case Con{M.Vector3{+x, +y, +z}, rest}: box.loop(rest, Box{x, y, z, x, y, z})

# maxcell/(max - min), or 1 for a flat axis.
def cell.scale(+low: F32, +high: F32) -> F32:
  Bool.pick(F32, F32.is_eq(high, low), 1.0, (19.0 / (high - low : F32) : F32))

def Box.scale(+b: Box) -> M.Vector3:
  Box{lx, ly, lz, hx, hy, hz} = b
  M.Vector3{cell.scale(lx, hx), cell.scale(ly, hy), cell.scale(lz, hz)}

def Box.low(+b: Box) -> M.Vector3:
  Box{lx, ly, lz, _, _, _} = b
  M.Vector3{lx, ly, lz}

# par_shapes_translate(-min) then par_shapes_scale(scale), per point.
def grid.cell(+low: M.Vector3, +scale: M.Vector3, p: M.Vector3) -> M.Vector3:
  M.Vector3{lx, ly, lz} = low
  M.Vector3{sx, sy, sz} = scale
  M.Vector3{x, y, z} = p
  M.Vector3{((x + F32.neg(lx) : F32) * sx : F32), ((y + F32.neg(ly) : F32) * sy : F32), ((z + F32.neg(lz) : F32) * sz : F32)}

def cells.go(ps: +List<M.Vector3>, +low: M.Vector3, +scale: M.Vector3, acc: +List<M.Vector3>) -> +List<M.Vector3>:
  match ps:
    case Nil{}: Mesh.vectors.reverse(acc, Nil{})
    case Con{+p, rest}: cells.go(rest, low, scale, Con{grid.cell(low, scale, p), acc})

# A cell coordinate as the C int conversion, valid when 0 <= int < 20.
def cell.ok(+c: F32) -> Bool:
  (c > F32.neg(1.0) : F32) && (c < 20.0 : F32)

def cell.int(+c: F32) -> U32:
  F32.to_u32(F32.trunc(c))

# The flattened grid index i + 20*j + 400*k.
def key(+p: M.Vector3) -> U32:
  M.Vector3{x, y, z} = p
  (cell.int(x) + 20 * cell.int(y) + 400 * cell.int(z) : U32)

def key.ok(+p: M.Vector3) -> Bool:
  M.Vector3{x, y, z} = p
  cell.ok(x) && cell.ok(y) && cell.ok(z)

def keys.ok(ps: +List<M.Vector3>, +ok: Bool) -> Bool:
  match ps:
    case Nil{}: ok
    case Con{+p, rest}: keys.ok(rest, ok && key.ok(p))


# -- U32 lookups: a balanced tree of words (read-only, shared).

type UT is Data:
  UTip{}
  ULeaf{value: U32}
  UNode{left: UT, right: UT}

def uts.reverse(xs: +List<UT>, acc: +List<UT>) -> +List<UT>:
  match xs:
    case Nil{}: acc
    case Con{+t, rest}: uts.reverse(rest, Con{t, acc})

def uleaves(xs: +List<U32>, acc: +List<UT>) -> +List<UT>:
  match xs:
    case Nil{}: uts.reverse(acc, Nil{})
    case Con{+v, rest}: uleaves(rest, Con{ULeaf{v}, acc})

def upairs(xs: +List<UT>, acc: +List<UT>) -> +List<UT>:
  match xs:
    case Con{+a, Con{+b, rest}}: upairs(rest, Con{UNode{a, b}, acc})
    case Con{+a, Nil{}}: uts.reverse(Con{UNode{a, UTip{}}, acc}, Nil{})
    case _: uts.reverse(acc, Nil{})

def ulevels(d: Nat, +xs: +List<UT>) -> +List<UT>:
  match d:
    case 0n: xs
    case 1n+k: ulevels(k, upairs(xs, Nil{}))

def ut.first(xs: +List<UT>) -> UT:
  match xs:
    case Con{+t, _}: t
    case Nil{}: UTip{}

def ut.of(+d: Nat, +xs: +List<U32>) -> UT:
  ut.first(ulevels(d, uleaves(xs, Nil{})))

def ut.get(+d: Nat, t: UT, +i: U32) -> U32:
  match d t:
    case 0n ULeaf{v}: v
    case 1n+k UNode{l, r}: ut.get(k, Bool.pick(UT, U32.is_eq(((i >> k) .&. 1 : U32), 1), r, l), i)
    case _ _: 0

def take.u(n: Nat, xs: List<U32>, acc: +List<U32>) -> +List<U32>:
  match n xs:
    case 1n+k Con{+x, rest}: take.u(k, rest, Con{x, acc})
    case _ _: List.reverse(&2, U32, acc)

# -- The grid sort: a stable counting sort by key (glibc's qsort, a stable
# merge sort, gives the same order).

def count.bump(r: Array<U32> & U32, +k: U32) -> Array<U32>:
  (a, +v) = r
  Array.set(U32, a, k, (v + 1 : U32))

def count.keys(ps: +List<M.Vector3>, counts: Array<U32>) -> Array<U32>:
  match ps:
    case Nil{}: counts
    case Con{+p, rest}: count.keys(rest, count.bump(Array.get(U32, counts, key(p)), key(p)))

# Prefix sums of the counts (the first sorted position of each key).
def starts(cs: +List<U32>, +total: U32, acc: +List<U32>) -> +List<U32>:
  match cs:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+c, rest}: starts(rest, (total + c : U32), Con{total, acc})

def fill.u(xs: +List<U32>, +i: U32, a: Array<U32>) -> Array<U32>:
  match xs:
    case Nil{}: a
    case Con{+x, rest}: fill.u(rest, (i + 1 : U32), Array.set(U32, a, i, x))

def place.two(r: Array<U32> & U32, out: Array<U32>, +i: U32, +k: U32) -> Array<U32> & Array<U32>:
  (s, +pos) = r
  (Array.set(U32, s, k, (pos + 1 : U32)), Array.set(U32, out, pos, i))

def place.one(pair: Array<U32> & Array<U32>, +i: U32, +k: U32) -> Array<U32> & Array<U32>:
  (s, out) = pair
  place.two(Array.get(U32, s, k), out, i, k)

def place(ps: +List<M.Vector3>, +i: U32, pair: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match ps:
    case Nil{}: pair
    case Con{+p, rest}: place(rest, (i + 1 : U32), place.one(pair, i, key(p)))

def second(pair: Array<U32> & Array<U32>) -> Array<U32>:
  (_, b) = pair
  b

# Grid cells (point counts and first sorted positions by key) and the sorted
# order (original point indices).
type Sorted is Data:
  Sorted{counts: UT, firsts: UT, order: +List<U32>}

def sorted.with(+n: U32, +counts: +List<U32>, +ps: +List<M.Vector3>) -> Sorted:
  +firsts = starts(counts, 0, Nil{})
  Sorted{ut.of(13n, counts), ut.of(13n, firsts), take.u(U32.to_nat(n), Array.to_list(~U32, second(place(ps, 0,
    (fill.u(firsts, 0, Array.new(U32, 13n, 0)), Array.new(U32, Mesh.depth(n), 0))))), Nil{})}

def sorted(+n: U32, +ps: +List<M.Vector3>) -> Sorted:
  sorted.with(n, take.u(8192n, Array.to_list(~U32, count.keys(ps, Array.new(U32, 13n, 0))), Nil{}), ps)

# -- par_shapes__weld_points on the sorted cell coordinates.

def eps() -> F32:
  F.float(981668463)

def seq.go(n: Nat, +i: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: seq.go(k, (i - 1 : U32), Con{i, acc})

def seq(+count: U32) -> +List<U32>:
  seq.go(U32.to_nat(count), (count - 1 : U32), Nil{})

# The bin rows (int)(c - epsilon) .. (int)(c + epsilon) of one axis.
def span(+c: F32) -> +List<U32>:
  +lo = cell.int((c - eps() : F32))
  +hi = cell.int((c + eps() : F32))
  Bool.pick(+List<U32>, U32.is_eq(lo, hi), [lo], [lo, hi])

def cands.k(zs: +List<U32>, +i: U32, +j: U32, rest: +List<U32>) -> +List<U32>:
  match zs:
    case Nil{}: rest
    case Con{+k, more}: Con{(i + 20 * j + 400 * k : U32), cands.k(more, i, j, rest)}

def cands.j(ys: +List<U32>, +zs: +List<U32>, +i: U32, rest: +List<U32>) -> +List<U32>:
  match ys:
    case Nil{}: rest
    case Con{+j, more}: cands.k(zs, i, j, cands.j(more, zs, i, rest))

def cands.i(xs: +List<U32>, +ys: +List<U32>, +zs: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}: Nil{}
    case Con{+i, more}: cands.j(ys, zs, i, cands.i(more, ys, zs))

# The bins intersecting the epsilon cube around p, in rmodels.c's i, j, k loop order.
def cands(p: M.Vector3) -> +List<U32>:
  M.Vector3{x, y, z} = p
  cands.i(span(x), span(y), span(z))

type Welder is Data:
  Welder{fused: Bool, d: Nat, points: Mesh.Tree, counts: UT, firsts: UT}

def weld.set(weld: Bool, +q: U32, +p: U32, w: Array<U32>) -> Array<U32>:
  match weld:
    case True{}: Array.set(U32, w, q, p)
    case False{}: w

def weld.pick(+close: Bool, +q: U32, +p: U32, r: Array<U32> & U32) -> Array<U32>:
  (w, +v) = r
  weld.set(close && U32.is_eq(v, q), q, p, w)

# The point q (in p's bin walk) is welded to p when distinct, not welded yet
# and dist2 < epsilon (par_shapes__sqrdist3, fused under contraction).
def weld.try(+k: Welder, +q: U32, +p: U32, +sp: M.Vector3, w: Array<U32>) -> Array<U32>:
  Welder{fused, d, points, _, _} = k
  +dq = M.Vector3.subtract(Mesh.tree.get(d, points, q), sp)
  weld.pick(Bool.not(U32.is_eq(q, p)) && (Mesh.dot(fused, dq, dq) < eps() : F32), q, p, Array.get(U32, w, q))

def weld.walk(n: Nat, +q: U32, +k: Welder, +p: U32, +sp: M.Vector3, w: Array<U32>) -> Array<U32>:
  match n:
    case 0n: w
    case 1n+m: weld.walk(m, (q + 1 : U32), k, p, sp, weld.try(k, q, p, sp, w))

def weld.bin(+k: Welder, +b: U32, +p: U32, +sp: M.Vector3, w: Array<U32>) -> Array<U32>:
  Welder{_, _, _, counts, firsts} = k
  weld.walk(U32.to_nat(ut.get(13n, counts, b)), ut.get(13n, firsts, b), k, p, sp, w)

def weld.bins(bins: +List<U32>, +k: Welder, +p: U32, +sp: M.Vector3, w: Array<U32>) -> Array<U32>:
  match bins:
    case Nil{}: w
    case Con{+b, rest}: weld.bins(rest, k, p, sp, weld.bin(k, b, p, sp, w))

def weld.point.free(+k: Welder, +p: U32, w: Array<U32>) -> Array<U32>:
  Welder{_, d, points, _, _} = k
  +sp = Mesh.tree.get(d, points, p)
  weld.bins(cands(sp), k, p, sp, w)

def weld.point.go(free: Bool, +k: Welder, +p: U32, w: Array<U32>) -> Array<U32>:
  match free:
    case False{}: w
    case True{}: weld.point.free(k, p, w)

def weld.point(+k: Welder, +p: U32, r: Array<U32> & U32) -> Array<U32>:
  (w, +v) = r
  weld.point.go(U32.is_eq(v, p), k, p, w)

def weld.loop(n: Nat, +p: U32, +k: Welder, w: Array<U32>) -> Array<U32>:
  match n:
    case 0n: w
    case 1n+m: weld.loop(m, (p + 1 : U32), k, weld.point(k, p, Array.get(U32, w, p)))

# -- Condensing: kept points get consecutive indices, welded ones their
# target's. A point welded to a later one makes raylib read an unset entry
# (ok becomes False).

type Cond is Type:
  Cond{w: Array<U32>, cmap: Array<U32>, ci: U32, ok: Bool, kept: +List<M.Vector3>}

def cond.target(+q: U32, +v: U32, w: Array<U32>, +ci: U32, +ok: Bool, +kept: +List<M.Vector3>, r: Array<U32> & U32) -> Cond:
  (cmap, +t) = r
  Cond{w, Array.set(U32, cmap, q, t), ci, ok && (v < q : U32), kept}

def cond.keep(same: Bool, +q: U32, +v: U32, +sq: M.Vector3, w: Array<U32>, cmap: Array<U32>, +ci: U32, +ok: Bool, +kept: +List<M.Vector3>) -> Cond:
  match same:
    case True{}: Cond{w, Array.set(U32, cmap, q, ci), (ci + 1 : U32), ok, Con{sq, kept}}
    case False{}: cond.target(q, v, w, ci, ok, kept, Array.get(U32, cmap, v))

def cond.with(+q: U32, +sq: M.Vector3, cmap: Array<U32>, +ci: U32, +ok: Bool, +kept: +List<M.Vector3>, r: Array<U32> & U32) -> Cond:
  (w, +v) = r
  cond.keep(U32.is_eq(v, q), q, v, sq, w, cmap, ci, ok, kept)

def cond.step(+q: U32, +sq: M.Vector3, c: Cond) -> Cond:
  Cond{w, cmap, +ci, +ok, +kept} = c
  cond.with(q, sq, cmap, ci, ok, kept, Array.get(U32, w, q))

def cond.loop(n: Nat, +q: U32, +d: Nat, +points: Mesh.Tree, c: Cond) -> Cond:
  match n:
    case 0n: c
    case 1n+m: cond.loop(m, (q + 1 : U32), d, points, cond.step(q, Mesh.tree.get(d, points, q), c))

# -- par_shapes_compute_normals on the welded mesh.

def subtract(+a: M.Vector3, +b: M.Vector3) -> M.Vector3:
  M.Vector3.subtract(a, b)

def corner.normal(+fused: Bool, +a: M.Vector3, +b: M.Vector3, +c: M.Vector3) -> M.Vector3:
  Mesh.cross(fused, subtract(b, a), subtract(c, a))

def normals.acc(tris: +List<U32>, +fused: Bool, +d: Nat, +points: Mesh.Tree, acc: Array<F32>) -> Array<F32>:
  match tris:
    case Con{+a, Con{+b, Con{+c, rest}}}:
      +pa = Mesh.tree.get(d, points, a)
      +pb = Mesh.tree.get(d, points, b)
      +pc = Mesh.tree.get(d, points, c)
      normals.acc(rest, fused, d, points, Mesh.add3(Mesh.add3(Mesh.add3(acc, a, corner.normal(fused, pa, pb, pc)), b, corner.normal(fused, pb, pc, pa)),
        c, corner.normal(fused, pc, pa, pb)))
    case _: acc

# par_shapes__normalize3: sqrt of the (fused) squared length, scaled by
# 1.0f/len when len > 0.
def normalize3(+fused: Bool, +v: M.Vector3) -> M.Vector3:
  +size = F32.sqrt(Mesh.dot(fused, v, v))
  Bool.pick(M.Vector3, (size > 0.0 : F32), M.Vector3.scale(v, (1.0 / size : F32)), v)

def normals.list(n: Nat, +fused: Bool, xs: List<F32>, acc: +List<M.Vector3>) -> +List<M.Vector3>:
  match n xs:
    case 1n+k Con{+x, Con{+y, Con{+z, rest}}}: normals.list(k, fused, rest, Con{normalize3(fused, M.Vector3{x, y, z}), acc})
    case _ _: Mesh.vectors.reverse(acc, Nil{})

# -- Remaining glue.

def back(+low: M.Vector3, +inverse: M.Vector3, p: M.Vector3) -> M.Vector3:
  M.Vector3{lx, ly, lz} = low
  M.Vector3{fx, fy, fz} = inverse
  M.Vector3{x, y, z} = p
  M.Vector3{((x * fx : F32) + lx : F32), ((y * fy : F32) + ly : F32), ((z * fz : F32) + lz : F32)}

def backs(ps: +List<M.Vector3>, +low: M.Vector3, +inverse: M.Vector3, acc: +List<M.Vector3>) -> +List<M.Vector3>:
  match ps:
    case Nil{}: Mesh.vectors.reverse(acc, Nil{})
    case Con{+p, rest}: backs(rest, low, inverse, Con{back(low, inverse, p), acc})

def inverse(scale: M.Vector3) -> M.Vector3:
  M.Vector3{x, y, z} = scale
  M.Vector3{(1.0 / x : F32), (1.0 / y : F32), (1.0 / z : F32)}

def by.order(order: +List<U32>, +d: Nat, +points: Mesh.Tree, acc: +List<M.Vector3>) -> +List<M.Vector3>:
  match order:
    case Nil{}: Mesh.vectors.reverse(acc, Nil{})
    case Con{+i, rest}: by.order(rest, d, points, Con{Mesh.tree.get(d, points, i), acc})

def inv.fill(order: +List<U32>, +pos: U32, a: Array<U32>) -> Array<U32>:
  match order:
    case Nil{}: a
    case Con{+i, rest}: inv.fill(rest, (pos + 1 : U32), Array.set(U32, a, i, pos))

# weldmap in original order: cmap[inv[i]].
def welded.map(n: Nat, +i: U32, +d: Nat, +inv: UT, +cmap: UT, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k: welded.map(k, (i + 1 : U32), d, inv, cmap, Con{ut.get(d, cmap, ut.get(d, inv, i)), acc})

def tri.welded(+a: U32, +b: U32, +c: U32, +acc: +List<U32>) -> +List<U32>:
  Bool.pick(+List<U32>, Bool.not(U32.is_eq(a, b)) && Bool.not(U32.is_eq(a, c)) && Bool.not(U32.is_eq(b, c)), Con{c, Con{b, Con{a, acc}}}, acc)

def tris.welded(tris: +List<U32>, +d: Nat, +wm: UT, acc: +List<U32>) -> +List<U32>:
  match tris:
    case Con{+a, Con{+b, Con{+c, rest}}}: tris.welded(rest, d, wm, tri.welded(ut.get(d, wm, a), ut.get(d, wm, b), ut.get(d, wm, c), acc))
    case _: List.reverse(&2, U32, acc)

def per.point(n: Nat, +i: U32, +d: Nat, +wm: UT, +wd: Nat, +normals: Mesh.Tree, acc: +List<M.Vector3>) -> +List<M.Vector3>:
  match n:
    case 0n: Mesh.vectors.reverse(acc, Nil{})
    case 1n+k: per.point(k, (i + 1 : U32), d, wm, wd, normals, Con{Mesh.tree.get(wd, normals, ut.get(d, wm, i)), acc})

# The welded normals for each original point, or None when the weld is
# undefined in raylib (a point welded to a later one) or a cell coordinate
# leaves the 20-cell grid.
type Welded is Data:
  Welded{ok: Bool, normals: +List<M.Vector3>}

def welded.finish(+fused: Bool, +n: U32, +order: +List<U32>, +low: M.Vector3, +scale: M.Vector3, +tris: +List<U32>, c: Cond) -> Welded:
  Cond{_, cmap, +nw, +ok, +kept} = c
  +d = Mesh.depth(n)
  +wd = Mesh.depth(nw)
  +inv = ut.of(d, take.u(U32.to_nat(n), Array.to_list(~U32, inv.fill(order, 0, Array.new(U32, d, 0))), Nil{}))
  +wm = ut.of(d, welded.map(U32.to_nat(n), 0, d, inv, ut.of(d, take.u(U32.to_nat(n), Array.to_list(~U32, cmap), Nil{})), Nil{}))
  +points = Mesh.tree.of(wd, backs(Mesh.vectors.reverse(kept, Nil{}), low, inverse(scale), Nil{}))
  sums = normals.acc(tris.welded(tris, d, wm, Nil{}), fused, wd, points, Array.new(F32, Mesh.depth((nw * 3 : U32)), 0.0))
  Welded{ok, per.point(U32.to_nat(n), 0, d, wm, wd, Mesh.tree.of(wd, normals.list(U32.to_nat(nw), fused, Array.to_list(~F32, sums), Nil{})), Nil{})}

def welded.sorted(+fused: Bool, +n: U32, +low: M.Vector3, +scale: M.Vector3, +tris: +List<U32>, +cells: Mesh.Tree, s: Sorted) -> Welded:
  Sorted{counts, firsts, +order} = s
  +d = Mesh.depth(n)
  +points = Mesh.tree.of(d, by.order(order, d, cells, Nil{}))
  welded.finish(fused, n, order, low, scale, tris, cond.loop(U32.to_nat(n), 0, d, points,
    Cond{weld.loop(U32.to_nat(n), 0, Welder{fused, d, points, counts, firsts}, fill.u(seq(n), 0, Array.new(U32, d, 0))), Array.new(U32, d, 0), 0, True{}, Nil{}}))

def welded.cells(valid: Bool, +fused: Bool, +n: U32, +low: M.Vector3, +scale: M.Vector3, +tris: +List<U32>, +cells: +List<M.Vector3>) -> Welded:
  match valid:
    case False{}: Welded{False{}, Nil{}}
    case True{}: welded.sorted(fused, n, low, scale, tris, Mesh.tree.of(Mesh.depth(n), cells), sorted(n, cells))

# par_shapes__compute_welded_normals for points ps and triangles tris.
def welded(+fused: Bool, +n: U32, +ps: +List<M.Vector3>, +tris: +List<U32>) -> Welded:
  +box = box.of(ps)
  +low = Box.low(box)
  +scale = Box.scale(box)
  +cells = cells.go(ps, low, scale, Nil{})
  welded.cells(keys.ok(cells, True{}), fused, n, low, scale, tris, cells)

# -- par_shapes_remove_degenerate: triangles with |cross|^2 below
# (minarea*2)^2 are dropped (NaN ones too).

def degenerate.keep(+minimum: F32, +fused: Bool, +a: M.Vector3, +b: M.Vector3, +c: M.Vector3) -> Bool:
  +cp = corner.normal(fused, a, b, c)
  (Mesh.dot(fused, cp, cp) >= minimum : F32)

def degenerate(tris: +List<U32>, +minimum: F32, +fused: Bool, +d: Nat, +points: Mesh.Tree, +acc: +List<U32>) -> +List<U32>:
  match tris:
    case Con{+a, Con{+b, Con{+c, rest}}}: degenerate(rest, minimum, fused, d, points, Bool.pick(+List<U32>,
      degenerate.keep(minimum, fused, Mesh.tree.get(d, points, a), Mesh.tree.get(d, points, b), Mesh.tree.get(d, points, c)), Con{c, Con{b, Con{a, acc}}}, acc))
    case _: List.reverse(&2, U32, acc)

# -----------------------------------------------------------------------------
# raylib's GenMeshSphere / GenMeshHemiSphere / GenMeshTorus: the par_shapes
# mesh scaled, then unrolled per triangle corner.

type Out is Data:
  Out{ok: Bool, vertices: +List<F32>, texcoords: +List<F32>, normals: +List<F32>, triangles: U32}

def unroll.put(p: M.Vector3, uv: M.Vector3, n: M.Vector3, +k: F32, acc: Out) -> Out:
  M.Vector3{x, y, z} = p
  M.Vector3{u, v, _} = uv
  M.Vector3{nx, ny, nz} = n
  Out{ok, vs, ts, ns, c} = acc
  Out{ok, Con{(z * k : F32), Con{(y * k : F32), Con{(x * k : F32), vs}}}, Con{v, Con{u, ts}}, Con{nz, Con{ny, Con{nx, ns}}}, c}

def unroll.done(+count: U32, acc: Out) -> Out:
  Out{ok, vs, ts, ns, _} = acc
  Out{ok, Mesh.reverse(vs), Mesh.reverse(ts), Mesh.reverse(ns), (count / 3 : U32)}

def unroll(tris: +List<U32>, +d: Nat, +points: Mesh.Tree, +uvs: Mesh.Tree, +normals: Mesh.Tree, +k: F32, +count: U32, acc: Out) -> Out:
  match tris:
    case Nil{}: unroll.done(count, acc)
    case Con{+i, rest}: unroll(rest, d, points, uvs, normals, k, (count + 1 : U32), unroll.put(Mesh.tree.get(d, points, i), Mesh.tree.get(d, uvs, i), Mesh.tree.get(d, normals, i), k, acc))


def generate.normals(w: Welded, +d: Nat, +points: Mesh.Tree, +uvs: Mesh.Tree, +k: F32, +tris: +List<U32>) -> Out:
  Welded{ok, normals} = w
  unroll(tris, d, points, uvs, Mesh.tree.of(d, normals), k, 0, Out{ok, Nil{}, Nil{}, Nil{}, 0})

# A par_shapes parametric mesh (kind 0 sphere, 1 hemisphere, 2 torus with
# minor radius) of slices x stacks, welded normals, optionally without
# degenerate triangles (|cross|^2 < minimum), its points scaled by k and
# unrolled. ok is False outside the verified sinf/cosf set, for meshes of more
# than 65535 points (par_shapes' 16-bit indices) or an undefined weld.
def generate.welded(+fused: Bool, +n: U32, +minimum: F32, +remove: Bool, +k: F32, grid: Grid, +tris: +List<U32>) -> Out:
  Grid{+points, uvs} = grid
  +d = Mesh.depth(n)
  +tree = Mesh.tree.of(d, points)
  generate.normals(welded(fused, n, points, tris), d, tree, Mesh.tree.of(d, uvs), k,
    Bool.pick(+List<U32>, remove, degenerate(tris, minimum, fused, d, tree, Nil{}), tris))

def generate.valid(valid: Bool, +kind: U32, +fused: Bool, +n: U32, +slices: U32, +stacks: U32, +minimum: F32, +remove: Bool, +k: F32, +grid: Grid) -> Out:
  match valid:
    case False{}: Out{False{}, Nil{}, Nil{}, Nil{}, 0}
    case True{}: generate.welded(fused, n, minimum, remove, k, grid, faces(U32.to_nat(stacks), (stacks - 1 : U32), slices, Nil{}))

def generate(+kind: U32, +gnu: Bool, +fused: Bool, +minor: F32, +slices: U32, +stacks: U32, +minimum: F32, +remove: Bool, +k: F32) -> Out:
  +us = table(gnu, U32.is_eq(kind, 2), stacks)
  +vs = table(gnu, Bool.not(U32.is_eq(kind, 1)), slices)
  +n = ((slices + 1 : U32) * (stacks + 1 : U32) : U32)
  generate.valid(table.ok(us, True{}) && table.ok(vs, True{}) && (slices <= 65534 : U32) && (stacks <= 65534 : U32) && (n <= 65535 : U32),
    kind, fused, n, slices, stacks, minimum, remove, k, grid.rows(ents.reverse(us, Nil{}), ents.reverse(vs, Nil{}), kind, fused, minor, Grid{Nil{}, Nil{}}))
