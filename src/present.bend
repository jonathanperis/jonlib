# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Presentation for the desktop driver: a color buffer (raylib's R8G8B8A8 words,
# 0xRRGGBBAA, rows bottom-up as rlsw stores them) as Base's quadtree Image.
#
# Base's Window.frame draws the Image whose depth k is the least with
# 2^k >= width and 2^k >= height: Qua{tl, tr, bl, br} halves a square, a Pix
# covers its whole square, and a pixel's color is 0x00RRGGBB (Metal and X11
# both ignore the top byte). The tree is built bottom-up a level at a time:
# rows of images are paired (two rows, two columns each) into quads. Squares past
# the right or bottom edge are Pix{0} (never shown), and a quad whose four
# children are the same Pix collapses into that Pix, so uniform areas cost
# one node. Level 1 is read from the color buffer with one Array.get per
# pixel; loops are tail-recursive (rows of up to 2048 quads). See
# docs/DRIVER.md.
import Base

# Two leading images of a row (Pix{0} past its end) and the rest.
type Two is Type:
  Two{a: Image, b: Image, rest: List<Image>}

# Two leading rows (empty past the last one) and the rest.
type Rows is Type:
  Rows{top: List<Image>, bottom: List<Image>, rest: List<List<Image>>}

def next(xs: List<Image>) -> Image & List<Image>:
  match xs:
    case Nil{}: (Pix{0}, Nil{})
    case Con{x, rest}: (x, rest)

def two.second(+a: Image, r: Image & List<Image>) -> Two:
  (b, rest) = r
  Two{a, b, rest}

def two.first(r: Image & List<Image>) -> Two:
  (a, rest) = r
  two.second(a, next(rest))

def two(xs: List<Image>) -> Two:
  two.first(next(xs))

def rows.second(top: List<Image>, grid: List<List<Image>>) -> Rows:
  match grid:
    case Nil{}: Rows{top, Nil{}, Nil{}}
    case Con{bottom, rest}: Rows{top, bottom, rest}

def rows.split(grid: List<List<Image>>) -> Rows:
  match grid:
    case Nil{}: Rows{Nil{}, Nil{}, Nil{}}
    case Con{top, rest}: rows.second(top, rest)

def quad.made(same: Bool, +c: U32, +b: U32, +l: U32, +r: U32) -> Image:
  match same:
    case True{}: Pix{c}
    case False{}: Qua{Pix{c}, Pix{b}, Pix{l}, Pix{r}}

def quad.d(+ca: U32, +cb: U32, +cc: U32, d: Image) -> Image:
  match d:
    case Pix{+cd}: quad.made(U32.is_eq(ca, cb) && U32.is_eq(ca, cc) && U32.is_eq(ca, cd), ca, cb, cc, cd)
    case Qua{a, b, c, e}: Qua{Pix{ca}, Pix{cb}, Pix{cc}, Qua{a, b, c, e}}

def quad.c(+ca: U32, +cb: U32, c: Image, d: Image) -> Image:
  match c:
    case Pix{+cc}: quad.d(ca, cb, cc, d)
    case Qua{a, b, e, f}: Qua{Pix{ca}, Pix{cb}, Qua{a, b, e, f}, d}

def quad.b(+ca: U32, b: Image, c: Image, d: Image) -> Image:
  match b:
    case Pix{+cb}: quad.c(ca, cb, c, d)
    case Qua{a, e, f, g}: Qua{Pix{ca}, Qua{a, e, f, g}, c, d}

# Qua{a, b, c, d}, or the Pix all four are.
def quad(a: Image, b: Image, c: Image, d: Image) -> Image:
  match a:
    case Pix{+ca}: quad.b(ca, b, c, d)
    case Qua{e, f, g, h}: Qua{Qua{e, f, g, h}, b, c, d}

# n quads from two rows: images 2i, 2i+1 of the top and bottom rows.
def pair(n: Nat, top: Two, bottom: Two, acc: List<Image>) -> List<Image>:
  match n top bottom:
    case 0n _ _: List.reverse(&1, Image, acc)
    case 1n+k Two{a, b, trest} Two{c, d, brest}: pair(k, two(trest), two(brest), Con{quad(a, b, c, d), acc})

# The next level: h rows of w quads from the rows of this one.
def level(h: Nat, +w: Nat, pairs: Rows, acc: List<List<Image>>) -> List<List<Image>>:
  match h pairs:
    case 0n _: List.reverse(&1, List<Image>, acc)
    case 1n+k Rows{top, bottom, rest}: level(k, w, rows.split(rest), Con{pair(w, two(top), two(bottom), Nil{}), acc})

def half(+n: U32) -> U32:
  ((n + 1) / 2 : U32)

def root.row(row: List<Image>) -> Image:
  match row:
    case Nil{}: Pix{0}
    case Con{x, _}: x

def root(rows: List<List<Image>>) -> Image:
  match rows:
    case Nil{}: Pix{0}
    case Con{row, _}: root.row(row)

# Levels until one image is left (k = ceil(log2(max(width, height)))).
def levels(k: Nat, +w: U32, +h: U32, grid: List<List<Image>>) -> Image:
  match k:
    case 0n: root(grid)
    case 1n+j: levels(j, half(w), half(h), level(U32.to_nat(half(h)), U32.to_nat(half(w)), rows.split(grid), Nil{}))

def color(+word: U32) -> U32:
  (word >> 8n : U32)

def quad.words(+a: U32, +b: U32, +c: U32, +d: U32) -> Image:
  quad.made(U32.is_eq(a, b) && U32.is_eq(a, c) && U32.is_eq(a, d), a, b, c, d)

def depth(+n: U32) -> Nat:
  Bool.pick(Nat, (n <= 1 : U32), 0n, 1n+U32.log2((n - 1 : U32)))

# -----------------------------------------------------------------------------
# Level 1 read straight from the color buffer (rows bottom-up, width words
# each): quad row q covers screen rows 2q and 2q+1, that is buffer rows
# height-1-2q and height-2-2q; quads are read right to left so each row comes
# out left to right, and rows bottom-up so the grid comes out top-down. One
# Array.get per pixel and no intermediate lists.

def get(ok: Bool, a: Array<U32>, +index: U32) -> Array<U32> & U32:
  match ok:
    case True{}: Array.get(U32, a, index)
    case False{}: (a, 0)

def at.d(+tl: U32, +tr: U32, +bl: U32, r: Array<U32> & U32) -> Array<U32> & Image:
  (a, +br) = r
  (a, quad.words(color(tl), color(tr), color(bl), color(br)))

def at.c(+tl: U32, +tr: U32, +both: Bool, +bi: U32, r: Array<U32> & U32) -> Array<U32> & Image:
  (a, +bl) = r
  at.d(tl, tr, bl, get(both, a, (bi + 1 : U32)))

def at.b(+tl: U32, +low: Bool, +right: Bool, +bi: U32, r: Array<U32> & U32) -> Array<U32> & Image:
  (a, +tr) = r
  at.c(tl, tr, low && right, bi, get(low, a, bi))

def at.a(+low: Bool, +right: Bool, +ti: U32, +bi: U32, r: Array<U32> & U32) -> Array<U32> & Image:
  (a, +tl) = r
  at.b(tl, low, right, bi, get(right, a, (ti + 1 : U32)))

# The quad whose top-left pixel is buffer index ti, bottom-left bi (when
# `low`), with a right column when `right`.
def at(a: Array<U32>, +ti: U32, +bi: U32, +low: Bool, +right: Bool) -> Array<U32> & Image:
  at.a(low, right, ti, bi, Array.get(U32, a, ti))

def row.put(acc: List<Image>, r: Array<U32> & Image) -> Array<U32> & List<Image>:
  (a, image) = r
  (a, Con{image, acc})

def row(n: Nat, +x: U32, +width: U32, +top: U32, +bottom: U32, +low: Bool, r: Array<U32> & List<Image>) -> Array<U32> & List<Image>:
  match n r:
    case 0n _: r
    case 1n+k Tuple{a, acc}: row(k, (x - 2 : U32), width, top, bottom, low, row.put(acc, at(a, (top + x : U32), (bottom + x : U32), low, ((x + 1) < width : U32))))

def grid.put(acc: List<List<Image>>, r: Array<U32> & List<Image>) -> Array<U32> & List<List<Image>>:
  (a, images) = r
  (a, Con{images, acc})

def grid.row(a: Array<U32>, +q: U32, +width: U32, +height: U32) -> Array<U32> & List<Image>:
  +quads = half(width)
  +low = ((2 * q + 1) < height : U32)
  row(U32.to_nat(quads), (2 * (quads - 1) : U32), width, ((height - 1 - 2 * q) * width : U32),
    Bool.pick(U32, low, ((height - 2 - 2 * q) * width : U32), 0), low, (a, Nil{}))

def grid(n: Nat, +q: U32, +width: U32, +height: U32, r: Array<U32> & List<List<Image>>) -> Array<U32> & List<List<Image>>:
  match n r:
    case 0n _: r
    case 1n+k Tuple{a, acc}: grid(k, (q - 1 : U32), width, height, grid.put(acc, grid.row(a, q, width, height)))

def from.levels(+k: Nat, +width: U32, +height: U32, r: Array<U32> & List<List<Image>>) -> Array<U32> & Image:
  (a, rows) = r
  (a, levels(k, half(width), half(height), rows))

def from.first(r: Array<U32> & U32) -> Array<U32> & Image:
  (a, +w) = r
  (a, Pix{color(w)})

def from.depth(k: Nat, a: Array<U32>, +width: U32, +height: U32) -> Array<U32> & Image:
  match k:
    case 0n: from.first(Array.get(U32, a, 0))
    case 1n+j: from.levels(j, width, height, grid(U32.to_nat(half(height)), (half(height) - 1 : U32), width, height, (a, Nil{})))

# The Image of a width x height color buffer (rows bottom-up), and the buffer.
def from(a: Array<U32>, +width: U32, +height: U32) -> Array<U32> & Image:
  from.depth(depth(Bool.pick(U32, (width > height : U32), width, height)), a, width, height)
