# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_vorbis v1.22 (Sean Barrett; MIT or public
# domain), as raylib 6.0 vendors it in src/external/stb_vorbis.c: a floor's
# curve multiplied into the spectrum (do_floor and draw_line, in the
# deferred-floor build raylib compiles). See THIRD_PARTY_NOTICES.md and
# LICENSES/stb_vorbis.txt.
#
# C ints are U32 two's-complement words; a floor's Y values are int16s,
# sign-extended.
import Base
import ./vorbis_codebook.bend as C
import ./vorbis_maps.bend as M
import ./vorbis_db.bend as Db
import ./store.bend as R

def floats.of(words: +List<U32>, acc: +List<F32>) -> +List<F32>:
  match words:
    case Nil{}: List.reverse(&2, F32, acc)
    case Con{+w, +rest}: floats.of(rest, Con{C.float.word(w), acc})

# inverse_db_table as a row: made once for a decoder.
def table.row() -> R.Row:
  R.Row.from(floats.of(Db.table(), Nil{}))

def head(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+x, _}: x

def nth(xs: +List<U32>, +i: U32) -> U32:
  head(List.drop(&2, U32, xs, U32.to_nat(i)))

# a < 0 as an int.
def negative(+a: U32) -> Bool:
  (a >= 2147483648 : U32)

# |a| of an int.
def magnitude(+a: U32) -> U32:
  Bool.pick(U32, negative(a), (0 - a : U32), a)

# output[x] *= inverse_db_table[y & 255] along a line, one float a step:
# err += ady; where it reaches adx, err -= adx and y += sy, else y += base.
def line.steps(n: Nat, +db: R.Row, +x: U32, +y: U32, +err: U32, +adx: U32, +ady: U32, +base: U32, +sy: U32, +row: R.Row) -> R.Row:
  match n:
    case 0n: row
    case 1n+k:
      +over = ((err + ady) >= adx : U32)
      +next = (y + Bool.pick(U32, over, sy, base) : U32)
      line.steps(k, db, (x + 1 : U32), next, Bool.pick(U32, over, ((err + ady) - adx : U32), (err + ady : U32)), adx, ady, base, sy, R.Row.set(row, x, (R.Row.get(row, x) * R.Row.get(db, (next .&. 255 : U32)) : F32)))

def line.drawn(some: Bool, +db: R.Row, +x0: U32, +y0: U32, +stop: U32, +adx: U32, +ady: U32, +base: U32, +sy: U32, +row: R.Row) -> R.Row:
  match some:
    case False{}: row
    case True{}: line.steps(U32.to_nat(((stop - x0) - 1 : U32)), db, (x0 + 1 : U32), y0, 0, adx, ady, base, sy, R.Row.set(row, x0, (R.Row.get(row, x0) * R.Row.get(db, (y0 .&. 255 : U32)) : F32)))

# dy / adx as ints (toward zero), for adx above 0.
def slope(+dy: U32, +adx: U32) -> U32:
  Bool.pick(U32, negative(dy), (0 - (magnitude(dy) / U32.max(adx, 1)) : U32), (dy / U32.max(adx, 1) : U32))

# draw_line(output, x0, y0, x1, y1, n): the floats from x0 to x1 (and no
# further than n) multiplied by the table's value at the line's height,
# which is taken modulo 256. x1 is above x0.
def line(+db: R.Row, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +n: U32, +row: R.Row) -> R.Row:
  +dy = (y1 - y0 : U32)
  +adx = (x1 - x0 : U32)
  +base = slope(dy, adx)
  line.drawn((x0 < U32.min(x1, n) : U32), db, x0, y0, U32.min(x1, n), adx, (magnitude(dy) - (magnitude(base) * adx) : U32), base, Bool.pick(U32, negative(dy), (base - 1 : U32), (base + 1 : U32)), row)

# The floor's points in the order of their places: the line from the last
# point used to each point that has a Y (0 or more), drawn where the two
# are not at one place.
type Walk is Data:
  Walk{row: R.Row, lx: U32, ly: U32}

# lx, ly = hx, hy, after the line between them.
def walk.to(+db: R.Row, +hx: U32, +hy: U32, +n: U32, walk: Walk) -> Walk:
  Walk{+row, +lx, +ly} = walk
  Walk{Bool.pick(R.Row, U32.is_ne(lx, hx), line(db, lx, ly, hx, hy, n, row), row), hx, hy}

def walk.point(used: Bool, +db: R.Row, +hx: U32, +hy: U32, +n: U32, +walk: Walk) -> Walk:
  match used:
    case False{}: walk
    case True{}: walk.to(db, hx, hy, n, walk)

def walk.each(order: +List<U32>, +db: R.Row, +xs: +List<U32>, +ys: +List<U32>, +multiplier: U32, +n: U32, +walk: Walk) -> Walk:
  match order:
    case Nil{}: walk
    case Con{+j, +rest}: walk.each(rest, db, xs, ys, multiplier, n, walk.point(Bool.not(negative(nth(ys, j))), db, nth(xs, j), (nth(ys, j) * multiplier : U32), n, walk))

# The spectrum with the floor's curve, and whether the C code stays inside
# its table.
type Curve is Data:
  Curve{row: R.Row, fine: Bool}

# target[j] *= inverse_db_table[ly] from the last point on.
def fill(n: Nat, +x: U32, +factor: F32, +row: R.Row) -> R.Row:
  match n:
    case 0n: row
    case 1n+k: fill(k, (x + 1 : U32), factor, R.Row.set(row, x, (R.Row.get(row, x) * factor : F32)))

def Curve.row(curve: Curve) -> R.Row:
  Curve{row, _} = curve
  row

def Curve.fine(curve: Curve) -> Bool:
  Curve{_, fine} = curve
  fine

# Whether the level end of a curve is read past the table: the last point
# is before the half block's end and its height, as an int, is not 0 to
# 255.
def past.table(+lx: U32, +ly: U32, +n: U32) -> Bool:
  (lx < n : U32) && (ly > 255 : U32)

# After the last point the curve is level, at the point's height: there
# stb_vorbis reads the table at the height itself, not modulo 256, and a
# height past 255 is a read past the table (refused).
def curve.ended(walk: Walk, +db: R.Row, +n: U32) -> Curve:
  Walk{+row, +lx, +ly} = walk
  Bool.pick(Curve, past.table(lx, ly, n), Curve{row, False{}}, Curve{fill(U32.to_nat((n - U32.min(lx, n) : U32)), lx, R.Row.get(db, (ly .&. 255 : U32)), row), True{}})

def order.rest(order: +List<U32>) -> +List<U32>:
  match order:
    case Nil{}: Nil{}
    case Con{_, +rest}: rest

# do_floor(f, map, i, n, target, finalY, NULL) for a floor of type 1:
# `ys` are the channel's Y values (finalY, a point without one is -1), `n`
# half the block, `db` the table's row.
def curve.of(+row: R.Row, floor: M.Floor, +ys: +List<U32>, +n: U32, +db: R.Row) -> Curve:
  M.Floor{_, _, +multiplier, _, +xs, +order, _, _} = floor
  curve.ended(walk.each(order.rest(order), db, xs, ys, multiplier, n, Walk{row, 0, (head(ys) * multiplier : U32)}), db, n)
