# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rtext.c (Copyright (c) 2013-2026 Ramon
# Santamaria; zlib, LICENSES/raylib.txt): LoadFontData (FONT_DEFAULT,
# FONT_BITMAP, FONT_SDF), GenImageFontAtlas (the default row packing and the
# skyline packing of stb_rect_pack.h v1.01, Sean Barrett, public domain / MIT,
# LICENSES/stb_truetype.txt, sorted by the host C library's qsort: FreeBSD's
# introsort as Apple's Libc ships it, or glibc's stable merge sort) and the
# BDF reader LoadFontDataBDF. Glyph rasterization is src/truetype.bend. C ints
# are U32 two's-complement words; F32 arithmetic is uncontracted, in the C
# order. Undefined C behavior (reads past an array, int overflow, invalid
# float to int conversions) is refused. See docs/FONTS.md.
import Base
import ./truetype.bend as TT

# -----------------------------------------------------------------------------
# Helpers

def neg(+x: U32) -> Bool:
  TT.neg(x)

def slt(+a: U32, +b: U32) -> Bool:
  TT.slt(a, b)

def mul.ok(+a: U32, +b: U32) -> Bool:
  +aa = Bool.pick(U32, neg(a), (0 - a : U32), a)
  +bb = Bool.pick(U32, neg(b), (0 - b : U32), b)
  (aa <= 46340 : U32) && (bb <= 46340 : U32)

def zeros(n: Nat, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: zeros(k, Con{0, acc})

def count(+xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def range(n: Nat, +from: U32, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k: range(k, (from + 1 : U32), Con{from, acc})

def take(n: Nat, +xs: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match n xs:
    case 1n+k Con{+x, rest}: take(k, rest, Con{x, acc})
    case _ _: List.reverse(&2, U32, acc)

# -----------------------------------------------------------------------------
# LoadFontData: one GlyphInfo per requested codepoint found in the font.
# width and height are the image's C ints; has is image.data != NULL; pixels
# are GRAYSCALE bytes (width*height of them when has).

type Glyph is Data:
  Glyph{value: U32, offset_x: U32, offset_y: U32, advance_x: U32, width: U32, height: U32, has: Bool, pixels: +List<U32>}

# status: 0 NULL (stbtt_InitFont failed), 1 glyphs, 2 refused.
type Loaded is Data:
  Loaded{status: U32, glyphs: +List<Glyph>}

type Made is Data:
  Made{ok: Bool, glyph: Glyph}

# FONT_BITMAP: bytes below 80 become 0, the others 255.
def threshold(+px: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match px:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+p, rest}: threshold(rest, Con{Bool.pick(U32, (p < 80 : U32), 0, 255), acc})

def glyph.made(+b: TT.Blob, +info: TT.Info, +s: F32, +size: U32, +ascent: U32, +kind: U32, +cp: U32, +idx: U32, +bm: TT.Bitmap) -> Made:
  TT.Bitmap{status, w, h, xoff, yoff, px} = bm
  +written = U32.is_eq(status, 1) || U32.is_eq(status, 2)
  +data = U32.is_eq(status, 2)
  +cw = Bool.pick(U32, written, w, 0)
  +ch = Bool.pick(U32, written, h, 0)
  +adv = TT.advance(b, info, idx)
  +fadv = (TT.i2f(TT.Got.value(adv)) * s : F32)
  +advx = TT.f2i(Bool.pick(F32, TT.f2i.valid(fadv), fadv, 0.0))
  +fasc = (TT.i2f(ascent) * s : F32)
  +asc = TT.f2i(Bool.pick(F32, TT.f2i.valid(fasc), fasc, 0.0))
  +oy = Bool.pick(U32, written, yoff, 0)
  +space = U32.is_eq(cp, 32) || U32.is_eq(cp, 12288)
  +sized = Bool.not(neg(advx)) && Bool.not(U32.is_eq(advx, 0))
  +area = (advx * size : U32)
  +has_space = sized && mul.ok(advx, size) && Bool.not(neg(area))
  +n = (cw * ch : U32)
  +threshold_ok = Bool.not(U32.is_eq(kind, 1)) || neg(n) || U32.is_eq(n, 0) || Bool.not(space) || (has_space && Bool.not(slt(area, n)))
  +ok = Bool.not(U32.is_eq(status, 3)) && (Bool.not(data || space) || (TT.Got.ok(adv) && TT.f2i.valid(fadv))) &&
    (Bool.not(data) || (TT.f2i.valid(fasc) && TT.add.ok(oy, asc))) && (Bool.not(space) || Bool.not(sized) || mul.ok(advx, size)) && threshold_ok
  +pixels = Bool.pick(+List<U32>, U32.is_eq(kind, 1), threshold(px, Nil{}), px)
  Made{ok, Bool.pick(Glyph, space,
    Glyph{cp, Bool.pick(U32, written, xoff, 0), Bool.pick(U32, data, (oy + asc : U32), oy), Bool.pick(U32, sized, advx, 0), advx, size, has_space,
      Bool.pick(+List<U32>, has_space, zeros(U32.to_nat(area), Nil{}), Nil{})},
    Glyph{cp, Bool.pick(U32, written, xoff, 0), Bool.pick(U32, data, (oy + asc : U32), oy), Bool.pick(U32, data, advx, 0),
      Bool.pick(U32, data, cw, 0), Bool.pick(U32, data, ch, 0), data, Bool.pick(+List<U32>, data, pixels, Nil{})})}

# The glyph's image: stbtt_GetCodepointBitmap, or stbtt_GetCodepointSDF
# (padding 4, on-edge 128, distance scale 64) except for the space.
def glyph.image(+b: TT.Blob, +info: TT.Info, +s: F32, +kind: U32, +cp: U32, +idx: U32) -> TT.Bitmap:
  Bool.pick(TT.Bitmap, U32.is_eq(kind, 2), Bool.pick(TT.Bitmap, U32.is_eq(cp, 32), TT.Bitmap{0, 0, 0, 0, 0, Nil{}}, TT.sdf(b, info, idx, s, 4, 128, 64.0)),
    TT.bitmap(b, info, idx, s))

def glyph.load(+b: TT.Blob, +info: TT.Info, +s: F32, +size: U32, +ascent: U32, +kind: U32, +cp: U32, +idx: U32) -> Made:
  glyph.made(b, info, s, size, ascent, kind, cp, idx, glyph.image(b, info, s, kind, cp, idx))

type Gathered is Data:
  Gathered{ok: Bool, glyphs: +List<Glyph>}

def gather.add(+ok: Bool, +acc: +List<Glyph>, +m: Made) -> Gathered:
  Made{mok, g} = m
  Gathered{ok && mok, Con{g, acc}}

def gather.found(+found: Bool, +b: TT.Blob, +info: TT.Info, +s: F32, +size: U32, +ascent: U32, +kind: U32, +cp: U32, +idx: U32, +ok: Bool, +acc: +List<Glyph>) -> Gathered:
  Bool.pick(Gathered, found, gather.add(ok, acc, glyph.load(b, info, s, size, ascent, kind, cp, idx)), Gathered{ok, acc})

def Gathered.ok(+g: Gathered) -> Bool:
  Gathered{ok, _} = g
  ok

def Gathered.glyphs(+g: Gathered) -> +List<Glyph>:
  Gathered{_, glyphs} = g
  glyphs

def gather(+cps: +List<U32>, +b: TT.Blob, +info: TT.Info, +s: F32, +size: U32, +ascent: U32, +kind: U32, +g: Gathered) -> Gathered:
  match cps:
    case Nil{}: Gathered{Gathered.ok(g), List.reverse(&2, Glyph, Gathered.glyphs(g))}
    case Con{+cp, rest}:
      +idx = TT.index(b, info, cp)
      +i = TT.Got.value(idx)
      +found = Bool.not(neg(i)) && Bool.not(U32.is_eq(i, 0))
      gather(rest, b, info, s, size, ascent, kind, gather.found(found, b, info, s, size, ascent, kind, cp, i, Gathered.ok(g) && TT.Got.ok(idx), Gathered.glyphs(g)))

def load.gathered(+g: Gathered) -> Loaded:
  Gathered{ok, glyphs} = g
  Loaded{Bool.pick(U32, ok, 1, 2), glyphs}

def load.metrics(+b: TT.Blob, +size: U32, +cps: +List<U32>, +kind: U32, +info: TT.Info, +vm: TT.VMetrics) -> Loaded:
  TT.VMetrics{vok, ascent, _, _} = vm
  +h = TT.Info.hhea(info)
  +s = TT.scale_for_pixel_height(b, info, TT.i2f(size))
  +status = TT.Info.status(info)
  Bool.pick(Loaded, U32.is_eq(status, 1), Bool.pick(Loaded, vok && TT.in(b, (h + 4 : U32), 4),
    load.gathered(gather(cps, b, info, s, size, ascent, kind, Gathered{True{}, Nil{}})), Loaded{2, Nil{}}),
    Loaded{Bool.pick(U32, U32.is_eq(status, 0), 0, 2), Nil{}})

def load.init(+b: TT.Blob, +size: U32, +cps: +List<U32>, +kind: U32, +info: TT.Info) -> Loaded:
  load.metrics(b, size, cps, kind, info, TT.vmetrics(b, info))

# LoadFontData(fileData, dataSize, fontSize, codepoints, codepointCount, type):
# `codepoints` empty is NULL (codepointCount consecutive codepoints from 32,
# 95 when not positive); a list shorter than the count is refused (raylib
# reads past it). type 0 FONT_DEFAULT, 1 FONT_BITMAP, 2 FONT_SDF.
def load(+bytes: +List<U32>, +size: U32, +cps: +List<U32>, +n: U32, +kind: U32) -> Loaded:
  +total = Bool.pick(U32, neg(n) || U32.is_eq(n, 0), 95, n)
  +given = Bool.not(U32.is_eq(count(cps, 0), 0))
  +required = Bool.pick(+List<U32>, given, take(U32.to_nat(total), cps, Nil{}), range(U32.to_nat(total), 32, Nil{}))
  +b = TT.Blob.new(bytes)
  +valid = (total <= 65536 : U32) && (kind <= 2 : U32) && (Bool.not(given) || Bool.not((count(cps, 0) < total : U32)))
  Bool.pick(Loaded, valid, load.init(b, size, required, kind, TT.init(b)), Loaded{2, Nil{}})

# -----------------------------------------------------------------------------
# GenImageFontAtlas

type Rec is Data:
  Rec{x: F32, y: F32, w: F32, h: F32}

# A glyph's place in the atlas: where its pixels go and the atlas size when
# they are copied (raylib clips to it; a later doubling keeps the clip).
type Place is Data:
  Place{x: U32, y: U32, cw: U32, ch: U32, copy: Bool}

# status 1 an atlas (GRAYSCALE bytes, w x h), 2 refused.
type Atlas is Data:
  Atlas{status: U32, width: U32, height: U32, bytes: +List<U32>, recs: +List<Rec>}

def Glyph.width(+g: Glyph) -> U32:
  Glyph{_, _, _, _, width, _, _, _} = g
  width

def Glyph.height(+g: Glyph) -> U32:
  Glyph{_, _, _, _, _, height, _, _} = g
  height

# totalWidth: the sum of width + 2*padding (with the int overflow check).
type Sum is Data:
  Sum{ok: Bool, value: U32}

def total.width(+gs: +List<Glyph>, +pad: U32, +s: Sum) -> Sum:
  match gs:
    case Nil{}: s
    case Con{+g, rest}:
      Sum{ok, v} = s
      +step = (Glyph.width(g) + 2 * pad : U32)
      total.width(rest, pad, Sum{ok && TT.add.ok(Glyph.width(g), (2 * pad : U32)) && TT.add.ok(v, step), (v + step : U32)})

# (int)powf(2, ceilf(logf(x)/logf(2))) for x = sqrtf(totalArea) > 1: exact
# for a power of two (the quotient of the two correctly rounded logarithms is
# k, verified against the reference) and above the 64 floats after one;
# those 64 depend on the C library's logf rounding and are refused.
def atlas.size(+x: F32) -> Sum:
  +bits = F32.bits(x)
  +e = ((bits >> 23n) .&. 255 : U32)
  +m = (bits .&. 8388607 : U32)
  +k = (e - 127 : U32)
  +exact = U32.is_eq(m, 0)
  +ok = (x >= 1.0 : F32) && (x < 32768.0 : F32) && (exact || (m > 64 : U32))
  Sum{ok, Bool.pick(U32, ok, (1 << U32.to_nat(Bool.pick(U32, exact, k, (k + 1 : U32))) : U32), 0)}

# The default packing: one glyph after another, a new row when the glyph
# does not fit, the atlas height doubled when the row passes it.
type Pack is Data:
  Pack{ok: Bool, x: U32, y: U32, height: U32, places: +List<Place>, recs: +List<Rec>}

def pack.row.step(+g: Glyph, +width: U32, +size: U32, +pad: U32, +p: Pack) -> Pack:
  Pack{ok, x, y, height, places, recs} = p
  +gw = Glyph.width(g)
  +gh = Glyph.height(g)
  +wrap = Bool.not(slt(x, (width - gw - 2 * pad : U32)))
  +ny = Bool.pick(U32, wrap, (y + size + 2 * pad : U32), y)
  +grow = wrap && slt((height - size - pad : U32), ny)
  +nh = Bool.pick(U32, grow, (height * 2 : U32), height)
  +nx = Bool.pick(U32, wrap, pad, x)
  +sane = (nh <= 4096 : U32) && slt(ny, 16384) && slt(4294950912, ny) && slt(nx, 16384) && slt(4294950912, nx) && slt(gw, 16384) && slt(gh, 16384)
  Pack{ok && sane, (nx + gw + 2 * pad : U32), ny, nh, Con{Place{nx, ny, width, nh, True{}}, places},
    Con{Rec{TT.i2f(nx), TT.i2f(ny), TT.i2f(gw), TT.i2f(gh)}, recs}}

def pack.row(+gs: +List<Glyph>, +width: U32, +size: U32, +pad: U32, +p: Pack) -> Pack:
  match gs:
    case Nil{}: p
    case Con{+g, rest}: pack.row(rest, width, size, pad, pack.row.step(g, width, size, pad, p))

def blit.put(inside: Bool, +i: U32, +v: U32, a: Array<U32>) -> Array<U32>:
  match inside:
    case True{}: Array.set(U32, a, i, v)
    case False{}: a

# Glyph pixels into the atlas bytes (index y*width + x), clipped to the
# atlas size when they are copied (cw x ch).
def blit.go(+px: +List<U32>, +x: U32, +y: U32, +gw: U32, +x0: U32, +y0: U32, +cw: U32, +ch: U32, +width: U32, a: Array<U32>) -> Array<U32>:
  match px:
    case Nil{}: a
    case Con{+v, rest}:
      +dx = (x0 + x : U32)
      +dy = (y0 + y : U32)
      +inside = Bool.not(neg(dx)) && slt(dx, cw) && Bool.not(neg(dy)) && slt(dy, ch)
      +wrap = U32.is_eq((x + 1 : U32), gw)
      blit.go(rest, Bool.pick(U32, wrap, 0, (x + 1 : U32)), Bool.pick(U32, wrap, (y + 1 : U32), y), gw, x0, y0, cw, ch, width,
        blit.put(inside, (dy * width + dx : U32), v, a))

def Glyph.pixels(+g: Glyph) -> +List<U32>:
  Glyph{_, _, _, _, _, _, _, pixels} = g
  pixels

def blit.one(copy: Bool, +g: Glyph, +x0: U32, +y0: U32, +cw: U32, +ch: U32, +width: U32, a: Array<U32>) -> Array<U32>:
  match copy:
    case True{}: blit.go(Glyph.pixels(g), 0, 0, Glyph.width(g), x0, y0, cw, ch, width, a)
    case False{}: a

def blit.place(+g: Glyph, +p: Place, +width: U32, a: Array<U32>) -> Array<U32>:
  Place{x0, y0, cw, ch, copy} = p
  blit.one(copy, g, x0, y0, cw, ch, width, a)

def blit(+gs: +List<Glyph>, +ps: +List<Place>, +width: U32, a: Array<U32>) -> Array<U32>:
  match gs ps:
    case Con{+g, gr} Con{+p, pr}: blit(gr, pr, width, blit.place(g, p, width, a))
    case _ _: a

# -----------------------------------------------------------------------------
# stb_rect_pack: the rectangles' sort (rect_height_compare: taller first, then
# wider) with the host qsort, then the skyline bottom-left packing.

type Rect is Data:
  Rect{id: U32, w: U32, h: U32}

def Rect.id(+r: Rect) -> U32:
  Rect{id, _, _} = r
  id

# rect_height_compare as a C int (-1, 0, 1).
def rect.cmp(+p: Rect, +q: Rect) -> U32:
  Rect{_, pw, ph} = p
  Rect{_, qw, qh} = q
  Bool.pick(U32, slt(qh, ph), 4294967295, Bool.pick(U32, slt(ph, qh), 1, Bool.pick(U32, slt(qw, pw), 4294967295, Bool.pick(U32, slt(pw, qw), 1, 0))))

def rect.le(+p: Rect, +q: Rect) -> Bool:
  Bool.not(U32.is_eq(rect.cmp(p, q), 1))

def rect.zero() -> Rect:
  Rect{0, 0, 0}

def rget(a: Array<Rect>, +i: U32) -> Array<Rect> & Rect:
  Array.get(Rect, a, i)

def rswap.set(+j: U32, +x: Rect, +i: U32, r: Array<Rect> & Rect) -> Array<Rect>:
  (a, +y) = r
  Array.set(Rect, Array.set(Rect, a, i, y), j, x)

def rswap.first(+i: U32, +j: U32, r: Array<Rect> & Rect) -> Array<Rect>:
  (a, +x) = r
  rswap.set(j, x, i, Array.get(Rect, a, j))

def rswap(a: Array<Rect>, +i: U32, +j: U32) -> Array<Rect>:
  rswap.first(i, j, Array.get(Rect, a, i))

# The C int comparison of a[i] with a[j].
type Cmp3 is Type:
  Cmp3{a: Array<Rect>, value: U32}

def cmp.second(+x: Rect, r: Array<Rect> & Rect) -> Cmp3:
  (a, +y) = r
  Cmp3{a, rect.cmp(x, y)}

def cmp.first(+j: U32, r: Array<Rect> & Rect) -> Cmp3:
  (a, +x) = r
  cmp.second(x, Array.get(Rect, a, j))

def cmp.at(a: Array<Rect>, +i: U32, +j: U32) -> Cmp3:
  cmp.first(j, Array.get(Rect, a, i))

# med3: the index of the median of three (FreeBSD's comparison order).
def med3.pick(+i: U32, +j: U32, +k: U32, +x: Rect, +y: Rect, +z: Rect) -> U32:
  +ab = neg(rect.cmp(x, y))
  +bc = rect.cmp(y, z)
  +ac = neg(rect.cmp(x, z))
  Bool.pick(U32, ab, Bool.pick(U32, neg(bc), j, Bool.pick(U32, ac, k, i)),
    Bool.pick(U32, Bool.not(neg(bc)) && Bool.not(U32.is_eq(bc, 0)), j, Bool.pick(U32, ac, i, k)))

def med3.c(+i: U32, +j: U32, +k: U32, +x: Rect, +y: Rect, r: Array<Rect> & Rect) -> Cmp3:
  (a, +z) = r
  Cmp3{a, med3.pick(i, j, k, x, y, z)}

def med3.b(+i: U32, +j: U32, +k: U32, +x: Rect, r: Array<Rect> & Rect) -> Cmp3:
  (a, +y) = r
  med3.c(i, j, k, x, y, Array.get(Rect, a, k))

def med3.a(+i: U32, +j: U32, +k: U32, r: Array<Rect> & Rect) -> Cmp3:
  (a, +x) = r
  med3.b(i, j, k, x, Array.get(Rect, a, j))

def med3(a: Array<Rect>, +i: U32, +j: U32, +k: U32) -> Cmp3:
  med3.a(i, j, k, Array.get(Rect, a, i))

# Insertion sort of [lo, lo + n), stopping after `limit` swaps (0: none).
type ISort is Type:
  ISort{a: Array<Rect>, i: U32, j: U32, swaps: U32, state: U32}

def isort.moved(swap: Bool, +lo: U32, +n: U32, +limit: U32, +i: U32, +j: U32, +swaps: U32, a: Array<Rect>) -> ISort:
  match swap:
    case True{}:
      +s = (swaps + 1 : U32)
      ISort{rswap(a, j, (j - 1 : U32)), i, (j - 1 : U32), s, Bool.pick(U32, Bool.not(U32.is_eq(limit, 0)) && (s > limit : U32), 2, 0)}
    case False{}: ISort{a, (i + 1 : U32), (i + 1 : U32), swaps, Bool.pick(U32, ((i + 1 : U32) >= (lo + n : U32) : U32), 1, 0)}

def isort.compared(+lo: U32, +n: U32, +limit: U32, +i: U32, +j: U32, +swaps: U32, c: Cmp3) -> ISort:
  Cmp3{a, +v} = c
  isort.moved(Bool.not(neg(v)) && Bool.not(U32.is_eq(v, 0)), lo, n, limit, i, j, swaps, a)

def isort.step(inner: Bool, +lo: U32, +n: U32, +limit: U32, +i: U32, +j: U32, +swaps: U32, a: Array<Rect>) -> ISort:
  match inner:
    case True{}: isort.compared(lo, n, limit, i, j, swaps, cmp.at(a, (j - 1 : U32), j))
    case False{}: ISort{a, (i + 1 : U32), (i + 1 : U32), swaps, Bool.pick(U32, ((i + 1 : U32) >= (lo + n : U32) : U32), 1, 0)}

def isort.go(f: Nat, +lo: U32, +n: U32, +limit: U32, s: ISort) -> ISort:
  match f s:
    case 1n+k ISort{a, +i, +j, +swaps, 0}: isort.go(k, lo, n, limit, isort.step((j > lo : U32), lo, n, limit, i, j, swaps, a))
    case _ s2: s2

# state 1 sorted, 2 stopped at the limit.
def isort(a: Array<Rect>, +lo: U32, +n: U32, +limit: U32) -> ISort:
  isort.go(U32.to_nat((n * n + 4 * n + 4 : U32)), lo, n, limit, ISort{a, (lo + 1 : U32), (lo + 1 : U32), 0, Bool.pick(U32, (n <= 1 : U32), 1, 0)})

def ISort.array(s: ISort) -> Array<Rect>:
  ISort{a, _, _, _, _} = s
  a

# FreeBSD heapsort of [lo, lo + n) (1-based heap over base lo - 1).
# phase 0 next build root, 1 sift down, 2 select, 3 select down, 4 select up.
type Heap is Type:
  Heap{a: Array<Rect>, phase: U32, l: U32, m: U32, par: U32, k: Rect, done: Bool}

def heap.child.b(+c: U32, +m: U32, +b0: U32, +x: Rect, r: Array<Rect> & Rect) -> Cmp3:
  (a, +y) = r
  Cmp3{a, Bool.pick(U32, (c < m : U32) && neg(rect.cmp(x, y)), (c + 1 : U32), c)}

def heap.child.a(+c: U32, +m: U32, +b0: U32, r: Array<Rect> & Rect) -> Cmp3:
  (a, +x) = r
  heap.child.b(c, m, b0, x, Array.get(Rect, a, (b0 + c + 1 : U32)))

# The larger child of par (child_i + 1 when it compares greater).
def heap.child(a: Array<Rect>, +par: U32, +m: U32, +b0: U32) -> Cmp3:
  +c = (par * 2 : U32)
  heap.child.a(c, m, b0, Array.get(Rect, a, (b0 + c : U32)))

def heap.sift.swap(stop: Bool, +l: U32, +m: U32, +par: U32, +c: U32, +b0: U32, +k: Rect, a: Array<Rect>) -> Heap:
  match stop:
    case True{}: Heap{a, 0, l, m, par, k, False{}}
    case False{}: Heap{rswap(a, (b0 + par : U32), (b0 + c : U32)), 1, l, m, c, k, False{}}

def heap.sift.cmp(+l: U32, +m: U32, +par: U32, +c: U32, +b0: U32, +k: Rect, d: Cmp3) -> Heap:
  Cmp3{a, +v} = d
  heap.sift.swap(neg(v) || U32.is_eq(v, 0), l, m, par, c, b0, k, a)

def heap.sift.child(+l: U32, +m: U32, +par: U32, +b0: U32, +k: Rect, d: Cmp3) -> Heap:
  Cmp3{a, +c} = d
  heap.sift.cmp(l, m, par, c, b0, k, cmp.at(a, (b0 + c : U32), (b0 + par : U32)))

def heap.sift(leaf: Bool, +l: U32, +m: U32, +par: U32, +b0: U32, +k: Rect, a: Array<Rect>) -> Heap:
  match leaf:
    case True{}: Heap{a, 0, l, m, par, k, False{}}
    case False{}: heap.sift.child(l, m, par, b0, k, heap.child(a, par, m, b0))

def heap.select.top(+m: U32, +b0: U32, +k: Rect, r: Array<Rect> & Rect) -> Heap:
  (a, +top) = r
  Heap{Array.set(Rect, a, (b0 + m : U32), top), 3, 0, (m - 1 : U32), 1, k, False{}}

def heap.select.read(+m: U32, +b0: U32, r: Array<Rect> & Rect) -> Heap:
  (a, +k) = r
  heap.select.top(m, b0, k, Array.get(Rect, a, (b0 + 1 : U32)))

def heap.select(more: Bool, +m: U32, +b0: U32, +k: Rect, a: Array<Rect>) -> Heap:
  match more:
    case True{}: heap.select.read(m, b0, Array.get(Rect, a, (b0 + m : U32)))
    case False{}: Heap{a, 5, 0, m, 0, k, True{}}

def heap.down.set(+m: U32, +par: U32, +c: U32, +b0: U32, +k: Rect, r: Array<Rect> & Rect) -> Heap:
  (a, +v) = r
  Heap{Array.set(Rect, a, (b0 + par : U32), v), 3, 0, m, c, k, False{}}

def heap.down.copy(+m: U32, +par: U32, +b0: U32, +k: Rect, d: Cmp3) -> Heap:
  Cmp3{a, +c} = d
  heap.down.set(m, par, c, b0, k, Array.get(Rect, a, (b0 + c : U32)))

def heap.down(leaf: Bool, +m: U32, +par: U32, +b0: U32, +k: Rect, a: Array<Rect>) -> Heap:
  match leaf:
    case True{}: Heap{a, 4, 0, m, par, k, False{}}
    case False{}: heap.down.copy(m, par, b0, k, heap.child(a, par, m, b0))

def heap.up.place(here: Bool, +m: U32, +child: U32, +b0: U32, +k: Rect, +p: Rect, a: Array<Rect>) -> Heap:
  match here:
    case True{}: Heap{Array.set(Rect, a, (b0 + child : U32), k), 2, 0, m, 0, k, False{}}
    case False{}: Heap{Array.set(Rect, a, (b0 + child : U32), p), 4, 0, m, (child >> 1n : U32), k, False{}}

def heap.up.cmp(+m: U32, +child: U32, +b0: U32, +k: Rect, r: Array<Rect> & Rect) -> Heap:
  (a, +p) = r
  heap.up.place(U32.is_eq(child, 1) || neg(rect.cmp(k, p)), m, child, b0, k, p, a)

def heap.step(phase: U32, a: Array<Rect>, +l: U32, +m: U32, +par: U32, +b0: U32, +k: Rect) -> Heap:
  match phase:
    case 0: Heap{a, Bool.pick(U32, U32.is_eq((l - 1 : U32), 0), 2, 1), (l - 1 : U32), m, (l - 1 : U32), k, False{}}
    case 1: heap.sift(((par * 2 : U32) > m : U32), l, m, par, b0, k, a)
    case 2: heap.select((m > 1 : U32), m, b0, k, a)
    case 3: heap.down(((par * 2 : U32) > m : U32), m, par, b0, k, a)
    case _: heap.up.cmp(m, par, b0, k, Array.get(Rect, a, (b0 + (par >> 1n) : U32)))

def heap.go(f: Nat, +b0: U32, h: Heap) -> Heap:
  match f h:
    case 1n+k Heap{a, +phase, +l, +m, +par, +key, False{}}: heap.go(k, b0, heap.step(phase, a, l, m, par, b0, key))
    case _ h2: h2

def Heap.array(h: Heap) -> Array<Rect>:
  Heap{a, _, _, _, _, _, _} = h
  a

def heapsort(a: Array<Rect>, +lo: U32, +n: U32) -> Array<Rect>:
  Heap.array(heap.go(U32.to_nat((40 * n * n + 40 : U32)), (lo - 1 : U32), Heap{a, 0, ((n >> 1n) + 1 : U32), n, 0, rect.zero(), (n <= 1 : U32)}))

def vecswap(n: Nat, +i: U32, +j: U32, a: Array<Rect>) -> Array<Rect>:
  match n:
    case 0n: a
    case 1n+k: vecswap(k, (i + 1 : U32), (j + 1 : U32), rswap(a, i, j))

# Apple Libc's qsort (FreeBSD's, with the introsort depth limit 2*(fls(n)-1)
# and heapsort beyond it): pending ranges (lo, n, depth) are independent, so
# they are kept on a stack in any order. phase 0 take a range, 1 scan b,
# 2 scan c, 3 swap b and c, 4 move the equal runs and split.
type QA is Type:
  QA{a: Array<Rect>, stack: +List<U32>, phase: U32, lo: U32, n: U32, depth: U32, pa: U32, pb: U32, pc: U32, pd: U32, swapped: Bool, done: Bool}

def QA.next(a: Array<Rect>, +stack: +List<U32>) -> QA:
  QA{a, stack, 0, 0, 0, 0, 0, 0, 0, 0, False{}, False{}}

def qa.start(+lo: U32, +n: U32, +depth: U32, +stack: +List<U32>, c: Cmp3) -> QA:
  Cmp3{a, +pm} = c
  QA{rswap(a, lo, pm), stack, 1, lo, n, depth, (lo + 1 : U32), (lo + 1 : U32), (lo + n - 1 : U32), (lo + n - 1 : U32), False{}, False{}}

def qa.nine.c(+lo: U32, +n: U32, +depth: U32, +stack: +List<U32>, +pl: U32, +pm: U32, c: Cmp3) -> QA:
  Cmp3{a, +pn} = c
  qa.start(lo, n, depth, stack, med3(a, pl, pm, pn))

def qa.nine.b(+lo: U32, +n: U32, +depth: U32, +stack: +List<U32>, +d: U32, +pl: U32, c: Cmp3) -> QA:
  Cmp3{a, +pm} = c
  +pn = (lo + n - 1 : U32)
  qa.nine.c(lo, n, depth, stack, pl, pm, med3(a, (pn - 2 * d : U32), (pn - d : U32), pn))

def qa.nine.a(+lo: U32, +n: U32, +depth: U32, +stack: +List<U32>, +d: U32, c: Cmp3) -> QA:
  Cmp3{a, +pl} = c
  +pm = (lo + (n >> 1n) : U32)
  qa.nine.b(lo, n, depth, stack, d, pl, med3(a, (pm - d : U32), pm, (pm + d : U32)))

# The pseudomedian: of 3, or of 3 medians of 3 above 40 entries.
def qa.median(big: Bool, +lo: U32, +n: U32, +depth: U32, +stack: +List<U32>, a: Array<Rect>) -> QA:
  match big:
    case False{}: qa.start(lo, n, depth, stack, med3(a, lo, (lo + (n >> 1n) : U32), (lo + n - 1 : U32)))
    case True{}:
      +d = (n >> 3n : U32)
      qa.nine.a(lo, n, depth, stack, d, med3(a, lo, (lo + d : U32), (lo + 2 * d : U32)))

def qa.range(kind: U32, +lo: U32, +n: U32, +depth: U32, +stack: +List<U32>, a: Array<Rect>) -> QA:
  match kind:
    case 0: QA.next(heapsort(a, lo, n), stack)
    case 1: QA.next(ISort.array(isort(a, lo, n, 0)), stack)
    case _: qa.median((n > 40 : U32), lo, n, (depth - 1 : U32), stack, a)

def qa.pop(+stack: +List<U32>, a: Array<Rect>) -> QA:
  match stack:
    case Con{+lo, Con{+n, Con{+depth, rest}}}: qa.range(Bool.pick(U32, slt(depth, 1), 0, Bool.pick(U32, (n <= 7 : U32), 1, 2)), lo, n, depth, rest, a)
    case _: QA{a, Nil{}, 0, 0, 0, 0, 0, 0, 0, 0, False{}, True{}}

def qa.scan_b.go(above: Bool, equal: Bool, +stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, +swapped: Bool, a: Array<Rect>) -> QA:
  match above equal:
    case True{} _: QA{a, stack, 2, lo, n, depth, pa, pb, pc, pd, swapped, False{}}
    case False{} True{}: QA{rswap(a, pa, pb), stack, 1, lo, n, depth, (pa + 1 : U32), (pb + 1 : U32), pc, pd, True{}, False{}}
    case False{} False{}: QA{a, stack, 1, lo, n, depth, pa, (pb + 1 : U32), pc, pd, swapped, False{}}

# b moves forward over entries not above the pivot (equal ones to the front).
def qa.scan_b(+stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, +swapped: Bool, c: Cmp3) -> QA:
  Cmp3{a, +r} = c
  +above = Bool.not(neg(r)) && Bool.not(U32.is_eq(r, 0))
  +equal = U32.is_eq(r, 0)
  qa.scan_b.go(above, equal, stack, lo, n, depth, pa, pb, pc, pd, swapped, a)

def qa.scan_c.go(below: Bool, equal: Bool, +stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, +swapped: Bool, a: Array<Rect>) -> QA:
  match below equal:
    case True{} _: QA{a, stack, 3, lo, n, depth, pa, pb, pc, pd, swapped, False{}}
    case False{} True{}: QA{rswap(a, pc, pd), stack, 2, lo, n, depth, pa, pb, (pc - 1 : U32), (pd - 1 : U32), True{}, False{}}
    case False{} False{}: QA{a, stack, 2, lo, n, depth, pa, pb, (pc - 1 : U32), pd, swapped, False{}}

def qa.scan_c(+stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, +swapped: Bool, c: Cmp3) -> QA:
  Cmp3{a, +r} = c
  qa.scan_c.go(neg(r), U32.is_eq(r, 0), stack, lo, n, depth, pa, pb, pc, pd, swapped, a)

def min.u(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a < b : U32), a, b)

# The '<' and '>' parts recurse (with this depth) unless shorter than 2.
def qa.split(+stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, a: Array<Rect>) -> QA:
  +d1 = (pb - pa : U32)
  +d2 = (pd - pc : U32)
  +pn = (lo + n : U32)
  +right = Bool.pick(+List<U32>, (d2 > 1 : U32), Con{(pn - d2 : U32), Con{d2, Con{depth, stack}}}, stack)
  QA.next(a, Bool.pick(+List<U32>, (d1 > 1 : U32), Con{lo, Con{d1, Con{depth, right}}}, right))

def qa.sorted.go(complete: Bool, +stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, a: Array<Rect>) -> QA:
  match complete:
    case True{}: QA.next(a, stack)
    case False{}: qa.split(stack, lo, n, depth, pa, pb, pc, pd, a)

def qa.sorted(+stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, s: ISort) -> QA:
  ISort{a, _, _, _, +state} = s
  qa.sorted.go(U32.is_eq(state, 1), stack, lo, n, depth, pa, pb, pc, pd, a)

def qa.finish.go(swapped: Bool, +stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, a: Array<Rect>) -> QA:
  match swapped:
    case True{}: qa.split(stack, lo, n, depth, pa, pb, pc, pd, a)
    case False{}: qa.sorted(stack, lo, n, depth, pa, pb, pc, pd, isort(a, lo, n, (1 + n / 4 : U32)))

def qa.finish(+stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, +swapped: Bool, a: Array<Rect>) -> QA:
  +pn = (lo + n : U32)
  +d1 = min.u((pa - lo : U32), (pb - pa : U32))
  +d2 = min.u((pd - pc : U32), (pn - pd - 1 : U32))
  qa.finish.go(swapped, stack, lo, n, depth, pa, pb, pc, pd, vecswap(U32.to_nat(d2), pb, (pn - d2 : U32), vecswap(U32.to_nat(d1), lo, (pb - d1 : U32), a)))

def qa.swap(cross: Bool, +stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, +swapped: Bool, a: Array<Rect>) -> QA:
  match cross:
    case True{}: QA{a, stack, 4, lo, n, depth, pa, pb, pc, pd, swapped, False{}}
    case False{}: QA{rswap(a, pb, pc), stack, 1, lo, n, depth, pa, (pb + 1 : U32), (pc - 1 : U32), pd, True{}, False{}}

def qa.scan(phase: U32, +stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, +swapped: Bool, a: Array<Rect>) -> QA:
  match phase:
    case 1: qa.scan_b(stack, lo, n, depth, pa, pb, pc, pd, swapped, cmp.at(a, pb, lo))
    case _: qa.scan_c(stack, lo, n, depth, pa, pb, pc, pd, swapped, cmp.at(a, pc, lo))

def qa.scan_or(cross: Bool, +phase: U32, +next: U32, +stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, +swapped: Bool, a: Array<Rect>) -> QA:
  match cross:
    case True{}: QA{a, stack, next, lo, n, depth, pa, pb, pc, pd, swapped, False{}}
    case False{}: qa.scan(phase, stack, lo, n, depth, pa, pb, pc, pd, swapped, a)

def qa.step(phase: U32, a: Array<Rect>, +stack: +List<U32>, +lo: U32, +n: U32, +depth: U32, +pa: U32, +pb: U32, +pc: U32, +pd: U32, +swapped: Bool) -> QA:
  match phase:
    case 0: qa.pop(stack, a)
    case 1: qa.scan_or((pb > pc : U32), 1, 2, stack, lo, n, depth, pa, pb, pc, pd, swapped, a)
    case 2: qa.scan_or((pb > pc : U32), 2, 3, stack, lo, n, depth, pa, pb, pc, pd, swapped, a)
    case 3: qa.swap((pb > pc : U32), stack, lo, n, depth, pa, pb, pc, pd, swapped, a)
    case _: qa.finish(stack, lo, n, depth, pa, pb, pc, pd, swapped, a)

def qa.go(f: Nat, s: QA) -> QA:
  match f s:
    case 1n+k QA{a, +stack, +phase, +lo, +n, +depth, +pa, +pb, +pc, +pd, +swapped, False{}}: qa.go(k, qa.step(phase, a, stack, lo, n, depth, pa, pb, pc, pd, swapped))
    case _ s2: s2

def QA.array(s: QA) -> Array<Rect>:
  QA{a, _, _, _, _, _, _, _, _, _, _, _} = s
  a

def fls.go(f: Nat, +n: U32, +k: U32) -> U32:
  match f:
    case 0n: k
    case 1n+r: fls.go(r, (n >> 1n : U32), Bool.pick(U32, U32.is_eq(n, 0), k, (k + 1 : U32)))

def apple.qsort(a: Array<Rect>, +n: U32) -> Array<Rect>:
  QA.array(qa.go(U32.to_nat((60 * n * n + 200 : U32)), QA.next(a, [0, n, (2 * (fls.go(32n, n, 0) - 1) : U32)])))

# The skyline (stbrp_init_target with glyphCount nodes, bottom-left
# heuristic): nodes sorted by x, the last one at the atlas width; `free`
# counts the unused nodes.
type Node is Data:
  Node{x: U32, y: U32}

def Node.x(+n: Node) -> U32:
  Node{x, _} = n
  x

def Node.y(+n: Node) -> U32:
  Node{_, y} = n
  y

type Sky is Data:
  Sky{nodes: +List<Node>, free: U32}

# stbrp__skyline_find_min_y: the highest node under [x0, x1).
def sky.min_y(+nodes: +List<Node>, +x1: U32, +m: U32) -> U32:
  match nodes:
    case Nil{}: m
    case Con{+nd, rest}: sky.min_y(rest, x1, Bool.pick(U32, slt(Node.x(nd), x1) && slt(m, Node.y(nd)), Node.y(nd), m))

type Best is Data:
  Best{found: Bool, index: U32, x: U32, y: U32}

# stbrp__skyline_find_best_pos (bottom-left): the first lowest position.
def sky.best(+nodes: +List<Node>, +i: U32, +width: U32, +limit: U32, +found: Bool, +index: U32, +bx: U32, +by: U32) -> Best:
  match nodes:
    case Nil{}: Best{found, index, bx, by}
    case Con{+nd, rest}:
      +x = Node.x(nd)
      +y = sky.min_y(Con{nd, rest}, (x + width : U32), 0)
      +take = Bool.not(slt(limit, (x + width : U32))) && slt(y, by)
      sky.best(rest, (i + 1 : U32), width, limit, found || take, Bool.pick(U32, take, i, index), Bool.pick(U32, take, x, bx), Bool.pick(U32, take, y, by))

type Dropped is Data:
  Dropped{cur: Node, rest: +List<Node>, freed: U32}

def sky.more(+rest: +List<Node>, +limit: U32) -> Bool:
  match rest:
    case Con{+nx, _}: Bool.not(slt(limit, Node.x(nx)))
    case Nil{}: False{}

# Nodes now under the new one return to the free list.
def sky.drop(+rest: +List<Node>, go: Bool, +cur: Node, +limit: U32, +freed: U32) -> Dropped:
  match rest go:
    case Con{+nx, more} True{}: sky.drop(more, sky.more(more, limit), nx, limit, (freed + 1 : U32))
    case _ _: Dropped{cur, rest, freed}

def drop.nodes(n: Nat, +xs: +List<Node>) -> +List<Node>:
  match n xs:
    case 1n+k Con{_, rest}: drop.nodes(k, rest)
    case _ _: xs

def take.nodes(n: Nat, +xs: +List<Node>, +acc: +List<Node>) -> +List<Node>:
  match n xs:
    case 1n+k Con{+x, rest}: take.nodes(k, rest, Con{x, acc})
    case _ _: List.reverse(&2, Node, acc)

def head.node(+xs: +List<Node>) -> Node:
  match xs:
    case Con{+x, _}: x
    case Nil{}: Node{0, 0}

def tail.nodes(+xs: +List<Node>) -> +List<Node>:
  match xs:
    case Con{_, rest}: rest
    case Nil{}: Nil{}

def sky.insert(+nodes: +List<Node>, +free: U32, +b: Best, +w: U32, +h: U32, +d: Dropped) -> Sky:
  Best{_, index, x, y} = b
  Dropped{cur, rest, freed} = d
  +cx = Node.x(cur)
  +right = (x + w : U32)
  Sky{List.append(&2, Node, take.nodes(U32.to_nat(index), nodes, Nil{}),
    Con{Node{x, (y + h : U32)}, Con{Node{Bool.pick(U32, slt(cx, right), right, cx), Node.y(cur)}, rest}}), (free - 1 + freed : U32)}

type Packed is Data:
  Packed{sky: Sky, ok: Bool, x: U32, y: U32}

# stbrp__skyline_pack_rectangle (width rounded up to the alignment for the
# search).
def sky.pack.at(+s: Sky, +sw: U32, +sh: U32, +w: U32, +h: U32, +width: U32, +b: Best) -> Packed:
  Sky{nodes, free} = s
  Best{found, index, bx, by} = b
  +fits = Bool.not(slt(sw, width)) && Bool.not(slt(sh, h)) && found && Bool.not(slt(sh, (by + h : U32))) && Bool.not(U32.is_eq(free, 0))
  +from = drop.nodes(U32.to_nat(index), nodes)
  +right = (bx + w : U32)
  Bool.pick(Packed, fits,
    Packed{sky.insert(nodes, free, b, w, h, sky.drop(tail.nodes(from), sky.more(tail.nodes(from), right), head.node(from), right, 0)), True{}, bx, by},
    Packed{s, False{}, 2147483647, 2147483647})

def sky.pack(+s: Sky, +sw: U32, +sh: U32, +align: U32, +w: U32, +h: U32) -> Packed:
  Sky{nodes, _} = s
  +wa = (w + align - 1 : U32)
  +width = (wa - (wa % align) : U32)
  sky.pack.at(s, sw, sh, w, h, width, sky.best(nodes, 0, width, sw, False{}, 0, 0, 1073741824))

type Placed is Data:
  Placed{id: U32, x: U32, y: U32}

type SkyState is Data:
  SkyState{sky: Sky, placed: +List<Placed>}

def sky.packed(+id: U32, +empty: Bool, +s: Sky, +acc: +List<Placed>, +p: Packed) -> SkyState:
  Packed{ns, _, px, py} = p
  SkyState{Bool.pick(Sky, empty, s, ns), Con{Placed{id, Bool.pick(U32, empty, 0, px), Bool.pick(U32, empty, 0, py)}, acc}}

def sky.step(+r: Rect, +sw: U32, +sh: U32, +align: U32, +s: Sky, +acc: +List<Placed>) -> SkyState:
  Rect{id, w, h} = r
  sky.packed(id, U32.is_eq(w, 0) || U32.is_eq(h, 0), s, acc, sky.pack(s, sw, sh, align, w, h))

def sky.go(+rs: +List<Rect>, +sw: U32, +sh: U32, +align: U32, +st: SkyState) -> +List<Placed>:
  match rs st:
    case Con{+r, rest} SkyState{+s, +acc}: sky.go(rest, sw, sh, align, sky.step(r, sw, sh, align, s, acc))
    case _ SkyState{_, acc}: acc

def rects(+gs: +List<Glyph>, +pad: U32, +i: U32, +acc: +List<Rect>) -> +List<Rect>:
  match gs:
    case Nil{}: List.reverse(&2, Rect, acc)
    case Con{+g, rest}: rects(rest, pad, (i + 1 : U32), Con{Rect{i, (Glyph.width(g) + 2 * pad : U32), (Glyph.height(g) + 2 * pad : U32)}, acc})

def rect.array(+rs: +List<Rect>, +i: U32, a: Array<Rect>) -> Array<Rect>:
  match rs:
    case Nil{}: a
    case Con{+r, rest}: rect.array(rest, (i + 1 : U32), Array.set(Rect, a, i, r))

def rect.list(n: Nat, +i: U32, r: Array<Rect> & Rect, +acc: +List<Rect>) -> +List<Rect>:
  match n r:
    case 0n _: List.reverse(&2, Rect, acc)
    case 1n+k Tuple{a, +x}: rect.list(k, (i + 1 : U32), Array.get(Rect, a, (i + 1 : U32)), Con{x, acc})

# The sort the host qsort makes: glibc's is stable; Apple's is FreeBSD's.
def rect.sort(gnu: Bool, +rs: +List<Rect>, +n: U32) -> +List<Rect>:
  match gnu:
    case True{}: List.sort(~Rect, ~(p => q => rect.le(p, q)), rs)
    case False{}: rect.list(U32.to_nat(n), 0, Array.get(Rect, apple.qsort(rect.array(rs, 0, Array.new(Rect, TT.Blob.depth(n), rect.zero())), n), 0), Nil{})

# Back to glyph order (rect_original_order): x and y per id.
def Placed.id(+p: Placed) -> U32:
  Placed{id, _, _} = p
  id

def Placed.x(+p: Placed) -> U32:
  Placed{_, x, _} = p
  x

def Placed.y(+p: Placed) -> U32:
  Placed{_, _, y} = p
  y

def placed.set(+ps: +List<Placed>, xs: Array<U32>, ys: Array<U32>) -> Array<U32> & Array<U32>:
  match ps:
    case Nil{}: (xs, ys)
    case Con{+p, rest}: placed.set(rest, Array.set(U32, xs, Placed.id(p), Placed.x(p)), Array.set(U32, ys, Placed.id(p), Placed.y(p)))

def take.u(n: Nat, xs: List<U32>, +acc: +List<U32>) -> +List<U32>:
  match n xs:
    case 1n+k Con{+x, rest}: take.u(k, rest, Con{x, acc})
    case _ _: List.reverse(&2, U32, acc)

def placed.places(+gs: +List<Glyph>, +pad: U32, +sw: U32, +sh: U32, +xs: +List<U32>, +ys: +List<U32>, +places: +List<Place>, +recs: +List<Rec>) -> Pack:
  match gs xs ys:
    case Con{+g, gr} Con{+x, xr} Con{+y, yr}:
      +packed = Bool.not(U32.is_eq(x, 2147483647) && U32.is_eq(y, 2147483647))
      placed.places(gr, pad, sw, sh, xr, yr, Con{Place{(x + pad : U32), (y + pad : U32), sw, sh, packed}, places},
        Con{Rec{(TT.i2f(x) + TT.i2f(pad) : F32), (TT.i2f(y) + TT.i2f(pad) : F32), TT.i2f(Glyph.width(g)), TT.i2f(Glyph.height(g))}, recs})
    case _ _ _: Pack{True{}, 0, 0, sh, List.reverse(&2, Place, places), List.reverse(&2, Rec, recs)}

def placed.lists(+gs: +List<Glyph>, +pad: U32, +sw: U32, +sh: U32, +n: U32, r: Array<U32> & Array<U32>) -> Pack:
  (xs, ys) = r
  placed.places(gs, pad, sw, sh, take.u(U32.to_nat(n), Array.to_list(~U32, xs), Nil{}), take.u(U32.to_nat(n), Array.to_list(~U32, ys), Nil{}), Nil{}, Nil{})

# GenImageFontAtlas, packing method 1.
def pack.skyline(gnu: Bool, +gs: +List<Glyph>, +n: U32, +pad: U32, +sw: U32, +sh: U32) -> Pack:
  +rs = rect.sort(gnu, rects(gs, pad, 0, Nil{}), n)
  +align = ((sw + n - 1 : U32) / n : U32)
  +placed = sky.go(rs, sw, sh, align, SkyState{Sky{[Node{0, 0}, Node{sw, 1073741824}], n}, Nil{}})
  +d = TT.Blob.depth(n)
  placed.lists(gs, pad, sw, sh, n, placed.set(placed, Array.new(U32, d, 0), Array.new(U32, d, 0)))

# -----------------------------------------------------------------------------
# GenImageFontAtlas(glyphs, &recs, glyphCount, fontSize, padding, packMethod)

def corner.rows(n: Nat, +w: U32, +k: U32, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n: a
    case 1n+r: corner.rows(r, w, (k - w : U32), Array.set(U32, Array.set(U32, Array.set(U32, a, k, 255), (k - 1 : U32), 255), (k - 2 : U32), 255))

def corner.go(draw: Bool, +w: U32, +k: U32, a: Array<U32>) -> Array<U32>:
  match draw:
    case False{}: a
    case True{}: corner.rows(3n, w, k, a)

def corner(+w: U32, +h: U32, a: Array<U32>) -> Array<U32>:
  +k = (w * h - 1 : U32)
  corner.go(Bool.not(slt(w, 3)) && Bool.not(slt(h, 3)), w, k, a)

def atlas.done(+gs: +List<Glyph>, +w: U32, +p: Pack) -> Atlas:
  Pack{ok, _, _, h, places, recs} = p
  +size = (w * h : U32)
  Bool.pick(Atlas, ok && (h <= 4096 : U32) && (w <= 4096 : U32), Atlas{1, w, h,
    take.u(U32.to_nat(size), Array.to_list(~U32, corner(w, h, blit(gs, places, w, Array.new(U32, TT.Blob.depth(size), 0)))), Nil{}), recs},
    Atlas{2, 0, 0, Nil{}, Nil{}})

def atlas.rows(+gs: +List<Glyph>, +w: U32, +p: Pack) -> Atlas:
  Pack{ok, x, y, ph, places, recs} = p
  atlas.done(gs, w, Pack{ok, x, y, ph, List.reverse(&2, Place, places), List.reverse(&2, Rec, recs)})

def atlas.pack(method: U32, gnu: Bool, +gs: +List<Glyph>, +n: U32, +size: U32, +pad: U32, +w: U32, +h: U32) -> Atlas:
  match method:
    case 0: atlas.rows(gs, w, pack.row(gs, w, size, pad, Pack{True{}, pad, pad, h, Nil{}, Nil{}}))
    case 1: atlas.done(gs, w, pack.skyline(gnu, gs, n, pad, w, h))
    case _: Atlas{2, 0, 0, Nil{}, Nil{}}

def take.glyphs(n: Nat, +xs: +List<Glyph>, +acc: +List<Glyph>) -> +List<Glyph>:
  match n xs:
    case 1n+k Con{+x, rest}: take.glyphs(k, rest, Con{x, acc})
    case _ _: List.reverse(&2, Glyph, acc)

def count.glyphs(+xs: +List<Glyph>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, rest}: count.glyphs(rest, (n + 1 : U32))

# Each glyph image must hold width*height bytes when it has data (raylib
# copies them) and none may be missing.
def glyph.valid(+g: Glyph) -> Bool:
  Glyph{_, _, _, _, w, h, has, px} = g
  +n = (w * h : U32)
  +empty = neg(w) || neg(h) || U32.is_eq(n, 0)
  empty || (has && Bool.not((count(px, 0) < n : U32)))

def glyphs.valid(+gs: +List<Glyph>) -> Bool:
  match gs:
    case Nil{}: True{}
    case Con{+g, rest}: glyph.valid(g) && glyphs.valid(rest)

def atlas.sided(+method: U32, gnu: Bool, +gs: +List<Glyph>, +n: U32, +size: U32, +pad: U32, +ok: Bool, +farea: F32, +side: Sum) -> Atlas:
  Sum{sok, w} = side
  +half = (farea < TT.i2f(((w * w : U32) / 2 : U32)) : F32)
  +valid = ok && sok && (w <= 4096 : U32)
  Bool.pick(Atlas, valid, atlas.pack(method, gnu, gs, n, size, pad, w, Bool.pick(U32, half, (w >> 1n : U32), w)), Atlas{2, 0, 0, Nil{}, Nil{}})

def atlas.sized(+method: U32, gnu: Bool, +gs: +List<Glyph>, +n: U32, +size: U32, +pad: U32, +total: Sum) -> Atlas:
  Sum{tok, tw} = total
  +padded = (size + 2 * pad : U32)
  +area = (tw * padded : U32)
  +farea = (TT.i2f(area) * TT.flt(1067030938) : F32)
  atlas.sided(method, gnu, gs, n, size, pad, tok && TT.add.ok(size, (2 * pad : U32)) && mul.ok(tw, padded) && (farea > 0.0 : F32), farea,
    atlas.size(F32.sqrt(farea)))

# glyphCount below 1 means 95 (raylib then reads 95 glyphs); a list shorter
# than the count, invalid glyph images and unknown methods are refused.
def atlas(gnu: Bool, +glyphs: +List<Glyph>, +count: U32, +size: U32, +pad: U32, +method: U32) -> Atlas:
  +n = Bool.pick(U32, neg(count) || U32.is_eq(count, 0), 95, count)
  +gs = take.glyphs(U32.to_nat(n), glyphs, Nil{})
  +valid = Bool.not((count.glyphs(glyphs, 0) < n : U32)) && (n <= 4096 : U32) && glyphs.valid(gs) && (method <= 1 : U32) &&
    slt(pad, 4096) && slt(4294963200, pad) && slt(size, 4096) && slt(4294963200, size)
  Bool.pick(Atlas, valid, atlas.sized(method, gnu, gs, n, size, pad, total.width(gs, pad, Sum{True{}, 0})), Atlas{2, 0, 0, Nil{}, Nil{}})

# -----------------------------------------------------------------------------
# LoadFontDataBDF as raylib 6.0 runs it. STARTCHAR clears the glyphs pointer
# (the same variable as the array), so a font with characters returns NULL
# (LoadFontFromMemory then gives the default font) and a BITMAP whose
# ENCODING is a requested codepoint other than the first writes through a
# pointer derived from NULL (refused). Only SIZE (the font size) and whether
# a character started survive; lines come from GetLine (up to 255 bytes, no
# terminator check: a read past the data is refused).

# status 0 NULL, 1 the zeroed glyph array, 2 refused; size is *outFontSize.
type Bdf is Data:
  Bdf{status: U32, size: U32}

def is.space(+c: U32) -> Bool:
  U32.is_eq(c, 32) || ((c >= 9 : U32) && (c <= 13 : U32))

# The line at p: GetLine's count (the bytes read must exist).
def line.count(n: Nat, +b: TT.Blob, +p: U32, +k: U32) -> TT.Got:
  match n:
    case 0n: TT.Got{True{}, k}
    case 1n+r:
      +inside = TT.in(b, (p + k : U32), 1)
      Bool.pick(TT.Got, inside && U32.is_eq(TT.u8(b, (p + k : U32)), 10), TT.Got{True{}, k},
        Bool.pick(TT.Got, inside, line.count(r, b, p, (k + 1 : U32)), TT.Got{False{}, k}))

# The C string length of the buffer (up to the first NUL).
def line.text(n: Nat, +b: TT.Blob, +p: U32, +k: U32) -> U32:
  match n:
    case 0n: k
    case 1n+r: Bool.pick(U32, U32.is_eq(TT.u8(b, (p + k : U32)), 0), k, line.text(r, b, p, (k + 1 : U32)))

def starts(+b: TT.Blob, +p: U32, +len: U32, +pat: +List<U32>, +k: U32) -> Bool:
  match pat:
    case Nil{}: True{}
    case Con{+c, rest}: (k < len : U32) && U32.is_eq(TT.u8(b, (p + k : U32)), c) && starts(b, p, len, rest, (k + 1 : U32))

# strstr(buffer, pattern) != NULL
def contains(n: Nat, +b: TT.Blob, +p: U32, +len: U32, +pat: +List<U32>) -> Bool:
  match n:
    case 0n: False{}
    case 1n+r: starts(b, p, len, pat, 0) || contains(r, b, (p + 1 : U32), (len - 1 : U32), pat)

def has(+b: TT.Blob, +p: U32, +len: U32, +pat: +List<U32>) -> Bool:
  contains(U32.to_nat((len + 1 : U32)), b, p, len, pat)

# sscanf's %i after a literal prefix: 0 no conversion, 1 a value, 2 refused
# (an int overflow, or "0x" without a hex digit).
type Scanned is Data:
  Scanned{status: U32, value: U32}

def digit(+c: U32, +base: U32) -> U32:
  +d = Bool.pick(U32, (c >= 48 : U32) && (c <= 57 : U32), (c - 48 : U32), Bool.pick(U32, (c >= 97 : U32) && (c <= 102 : U32), (c - 87 : U32),
    Bool.pick(U32, (c >= 65 : U32) && (c <= 70 : U32), (c - 55 : U32), 99)))
  Bool.pick(U32, (d < base : U32), d, 99)

# Digits in `base` from k: the magnitude, refused past 2^31.
def digits(n: Nat, +b: TT.Blob, +p: U32, +len: U32, +k: U32, +base: U32, +v: U32, +big: Bool) -> Scanned:
  match n:
    case 0n: Scanned{Bool.pick(U32, big, 2, 1), v}
    case 1n+r:
      +d = digit(TT.u8(b, (p + k : U32)), base)
      +more = (k < len : U32) && (d < 99 : U32)
      +nv = (v * base + d : U32)
      +over = big || (v > (2147483648 / base : U32) : U32) || (nv > 2147483648 : U32)
      Bool.pick(Scanned, more, digits(r, b, p, len, (k + 1 : U32), base, Bool.pick(U32, over, 0, nv), over), Scanned{Bool.pick(U32, big, 2, 1), v})

def skip.space(n: Nat, +b: TT.Blob, +p: U32, +len: U32, +k: U32) -> U32:
  match n:
    case 0n: k
    case 1n+r: Bool.pick(U32, (k < len : U32) && is.space(TT.u8(b, (p + k : U32))), skip.space(r, b, p, len, (k + 1 : U32)), k)

def scan.signed(+negative: Bool, +s: Scanned) -> Scanned:
  Scanned{status, v} = s
  +limit = Bool.pick(U32, negative, 2147483648, 2147483647)
  Bool.pick(Scanned, U32.is_eq(status, 1), Bool.pick(Scanned, (v > limit : U32), Scanned{2, 0}, Scanned{1, Bool.pick(U32, negative, (0 - v : U32), v)}), s)

def scan.int(+b: TT.Blob, +p: U32, +len: U32, +k0: U32) -> Scanned:
  +k = skip.space(U32.to_nat(len), b, p, len, k0)
  +c = TT.u8(b, (p + k : U32))
  +signed = (k < len : U32) && (U32.is_eq(c, 43) || U32.is_eq(c, 45))
  +j = Bool.pick(U32, signed, (k + 1 : U32), k)
  +d0 = TT.u8(b, (p + j : U32))
  +d1 = TT.u8(b, (p + j + 1 : U32))
  +zero = (j < len : U32) && U32.is_eq(d0, 48)
  +hex = zero && ((j + 1 : U32) < len : U32) && (U32.is_eq(d1, 120) || U32.is_eq(d1, 88))
  +hex_ok = ((j + 2 : U32) < len : U32) && (digit(TT.u8(b, (p + j + 2 : U32)), 16) < 99 : U32)
  +any = (j < len : U32) && (digit(d0, 10) < 99 : U32)
  +n = U32.to_nat((len + 1 : U32))
  Bool.pick(Scanned, hex, Bool.pick(Scanned, hex_ok, scan.signed(signed && U32.is_eq(c, 45), digits(n, b, p, len, (j + 2 : U32), 16, 0, False{})), Scanned{2, 0}),
    Bool.pick(Scanned, any, scan.signed(signed && U32.is_eq(c, 45), digits(n, b, p, len, j, Bool.pick(U32, zero, 8, 10), 0, False{})), Scanned{0, 0}))

# sscanf(buffer, "<prefix> %i", &v)
def scan(+b: TT.Blob, +p: U32, +len: U32, +prefix: +List<U32>) -> Scanned:
  +plen = count(prefix, 0)
  Bool.pick(Scanned, starts(b, p, len, prefix, 0), scan.int(b, p, len, plen), Scanned{0, 0})

def str.COMMENT() -> +List<U32>:
  [67, 79, 77, 77, 69, 78, 84]

def str.ENDCHAR() -> +List<U32>:
  [69, 78, 68, 67, 72, 65, 82]

def str.ENCODING() -> +List<U32>:
  [69, 78, 67, 79, 68, 73, 78, 71]

def str.BITMAP() -> +List<U32>:
  [66, 73, 84, 77, 65, 80]

def str.ENDFONT() -> +List<U32>:
  [69, 78, 68, 70, 79, 78, 84]

def str.BBX() -> +List<U32>:
  [66, 66, 88]

def str.DWIDTH() -> +List<U32>:
  [68, 87, 73, 68, 84, 72]

def str.FONTBOUNDINGBOX() -> +List<U32>:
  [70, 79, 78, 84, 66, 79, 85, 78, 68, 73, 78, 71, 66, 79, 88]

def str.FONT_ASCENT() -> +List<U32>:
  [70, 79, 78, 84, 95, 65, 83, 67, 69, 78, 84]

def str.SIZE() -> +List<U32>:
  [83, 73, 90, 69]

def str.STARTCHAR() -> +List<U32>:
  [83, 84, 65, 82, 84, 67, 72, 65, 82]

def str.STARTFONT() -> +List<U32>:
  [83, 84, 65, 82, 84, 70, 79, 78, 84]

# The index of the first requested codepoint equal to v (or the count).
def first.index(+cps: +List<U32>, +v: U32, +i: U32) -> U32:
  match cps:
    case Nil{}: i
    case Con{+c, rest}: Bool.pick(U32, U32.is_eq(c, v), i, first.index(rest, v, (i + 1 : U32)))

# The parser state: phase 0 reading, 1 done (loop ended), 2 refused.
type BdfState is Data:
  BdfState{phase: U32, total: U32, started: Bool, chr: Bool, bitmap: Bool, any: Bool, encoding: U32, size: U32}

def Scanned.status(+s: Scanned) -> U32:
  Scanned{status, _} = s
  status

def Scanned.value(+s: Scanned) -> U32:
  Scanned{_, value} = s
  value

def bdf.line(+b: TT.Blob, +cps: +List<U32>, +s: BdfState, +p: U32, +len: U32, +nread: U32) -> BdfState:
  BdfState{_, total, started, chr, bitmap, any, encoding, size} = s
  +next = (total + nread + 1 : U32)
  +comment = has(b, p, len, str.COMMENT())
  +endchar = has(b, p, len, str.ENDCHAR())
  +enc = has(b, p, len, str.ENCODING())
  +encoded = scan(b, p, len, str.ENCODING())
  +bm = has(b, p, len, str.BITMAP())
  +index = first.index(cps, encoding, 0)
  +endfont = has(b, p, len, str.ENDFONT())
  +sized = has(b, p, len, str.SIZE())
  +size_value = scan(b, p, len, str.SIZE())
  +startchar = has(b, p, len, str.STARTCHAR())
  +startfont = has(b, p, len, str.STARTFONT())
  +in_char = Bool.not(comment) && chr
  +in_font = Bool.not(comment) && Bool.not(chr) && started
  +outside = Bool.not(comment) && Bool.not(chr) && Bool.not(started)
  +c_end = in_char && endchar
  +c_body = in_char && Bool.not(endchar) && Bool.not(bitmap)
  +c_enc = c_body && enc
  +c_bitmap = c_body && Bool.not(enc) && Bool.not(has(b, p, len, str.BBX())) && Bool.not(has(b, p, len, str.DWIDTH())) && bm
  +f_end = in_font && endfont
  +f_size = in_font && Bool.not(endfont) && sized
  +f_char = in_font && Bool.not(endfont) && Bool.not(sized) && Bool.not(has(b, p, len, str.FONTBOUNDINGBOX())) &&
    Bool.not(has(b, p, len, str.FONT_ASCENT())) && startchar
  +o_start = outside && startfont
  +enc_scan = Bool.pick(U32, c_enc, Scanned.status(encoded), 0)
  +size_scan = Bool.pick(U32, f_size, Scanned.status(size_value), 0)
  +crash = c_bitmap && (index > 0 : U32) && (index < count(cps, 0) : U32)
  +refused = U32.is_eq(enc_scan, 2) || U32.is_eq(size_scan, 2) || crash
  BdfState{Bool.pick(U32, refused, 2, Bool.pick(U32, f_end, 1, 0)), next, started || o_start, Bool.pick(Bool, c_end, False{}, chr || f_char),
    Bool.pick(Bool, f_char, False{}, bitmap || c_bitmap), any || f_char,
    Bool.pick(U32, f_char, 4294967295, Bool.pick(U32, U32.is_eq(enc_scan, 1), Scanned.value(encoded), encoding)),
    Bool.pick(U32, U32.is_eq(size_scan, 1), Scanned.value(size_value), size)}

def bdf.read(+b: TT.Blob, +cps: +List<U32>, +s: BdfState, +line: TT.Got) -> BdfState:
  BdfState{_, total, started, chr, bitmap, any, encoding, size} = s
  TT.Got{ok, n} = line
  Bool.pick(BdfState, ok, bdf.line(b, cps, s, total, line.text(U32.to_nat(n), b, total, 0), n), BdfState{2, total, started, chr, bitmap, any, encoding, size})

def bdf.step(+b: TT.Blob, +cps: +List<U32>, +s: BdfState) -> BdfState:
  BdfState{_, total, started, chr, bitmap, any, encoding, size} = s
  Bool.pick(BdfState, slt(TT.Blob.size(b), total), BdfState{1, total, started, chr, bitmap, any, encoding, size},
    bdf.read(b, cps, s, line.count(255n, b, total, 0)))

def bdf.go(f: Nat, +b: TT.Blob, +cps: +List<U32>, s: BdfState) -> BdfState:
  match f s:
    case 1n+k BdfState{0, +total, +started, +chr, +bitmap, +any, +encoding, +size}:
      bdf.go(k, b, cps, bdf.step(b, cps, BdfState{0, total, started, chr, bitmap, any, encoding, size}))
    case _ s2: s2

def bdf.done(+s: BdfState) -> Bdf:
  BdfState{phase, _, _, _, _, any, _, size} = s
  Bdf{Bool.pick(U32, U32.is_eq(phase, 2), 2, Bool.pick(U32, any, 0, 1)), size}

# LoadFontDataBDF(fileData, dataSize, codepoints, codepointCount, &fontSize)
# with the requested codepoints (already count long) and the initial size.
def bdf(+bytes: +List<U32>, +cps: +List<U32>, +size: U32) -> Bdf:
  +b = TT.Blob.new(bytes)
  bdf.done(bdf.go(U32.to_nat((TT.Blob.size(b) + 2 : U32)), b, cps, BdfState{0, 0, False{}, False{}, False{}, False{}, 4294967295, size}))

# -----------------------------------------------------------------------------
# LoadBMFont's text: GetLine over the LoadFileText buffer (its bytes and the
# terminating NUL; reading past it is refused) and sscanf's literal,
# whitespace, %i and %128[^"] directives.

type Fmt is Data:
  FLit{c: U32}
  FSpace{}
  FInt{}
  FName{}

# A format string: ' ' a whitespace directive, '%' %i, '@' %128[^"].
def fmt(+cs: +List<U32>) -> +List<Fmt>:
  match cs:
    case Nil{}: Nil{}
    case Con{+c, rest}: Con{Bool.pick(Fmt, U32.is_eq(c, 32), FSpace{}, Bool.pick(Fmt, U32.is_eq(c, 37), FInt{}, Bool.pick(Fmt, U32.is_eq(c, 64), FName{}, FLit{c}))), fmt(rest)}

# The sscanf state: refused (an int overflow or an ambiguous "0x"), stopped,
# the input position, the assignments and their values.
type Scanf is Data:
  Scanf{ok: Bool, stopped: Bool, k: U32, count: U32, values: +List<U32>, name: +List<U32>}

# %i at k (after whitespace): (status, value, end).
type IntAt is Data:
  IntAt{status: U32, value: U32, end: U32}

def digits.at(n: Nat, +b: TT.Blob, +p: U32, +len: U32, +k: U32, +base: U32, +v: U32, +big: Bool) -> IntAt:
  match n:
    case 0n: IntAt{Bool.pick(U32, big, 2, 1), v, k}
    case 1n+r:
      +d = digit(TT.u8(b, (p + k : U32)), base)
      +more = (k < len : U32) && (d < 99 : U32)
      +nv = (v * base + d : U32)
      +over = big || (v > (2147483648 / base : U32) : U32) || (nv > 2147483648 : U32)
      Bool.pick(IntAt, more, digits.at(r, b, p, len, (k + 1 : U32), base, Bool.pick(U32, over, 0, nv), over), IntAt{Bool.pick(U32, big, 2, 1), v, k})

def int.signed(+negative: Bool, +s: IntAt) -> IntAt:
  IntAt{status, v, end} = s
  +limit = Bool.pick(U32, negative, 2147483648, 2147483647)
  Bool.pick(IntAt, U32.is_eq(status, 1), Bool.pick(IntAt, (v > limit : U32), IntAt{2, 0, end}, IntAt{1, Bool.pick(U32, negative, (0 - v : U32), v), end}), s)

def int.at(+b: TT.Blob, +p: U32, +len: U32, +k0: U32) -> IntAt:
  +k = skip.space(U32.to_nat(len), b, p, len, k0)
  +c = TT.u8(b, (p + k : U32))
  +signed = (k < len : U32) && (U32.is_eq(c, 43) || U32.is_eq(c, 45))
  +j = Bool.pick(U32, signed, (k + 1 : U32), k)
  +d0 = TT.u8(b, (p + j : U32))
  +d1 = TT.u8(b, (p + j + 1 : U32))
  +zero = (j < len : U32) && U32.is_eq(d0, 48)
  +hex = zero && ((j + 1 : U32) < len : U32) && (U32.is_eq(d1, 120) || U32.is_eq(d1, 88))
  +hex_ok = ((j + 2 : U32) < len : U32) && (digit(TT.u8(b, (p + j + 2 : U32)), 16) < 99 : U32)
  +any = (j < len : U32) && (digit(d0, 10) < 99 : U32)
  +n = U32.to_nat((len + 1 : U32))
  +negative = signed && U32.is_eq(c, 45)
  Bool.pick(IntAt, hex, Bool.pick(IntAt, hex_ok, int.signed(negative, digits.at(n, b, p, len, (j + 2 : U32), 16, 0, False{})), IntAt{2, 0, j}),
    Bool.pick(IntAt, any, int.signed(negative, digits.at(n, b, p, len, j, Bool.pick(U32, zero, 8, 10), 0, False{})), IntAt{0, 0, j}))

def name.at(n: Nat, +b: TT.Blob, +p: U32, +len: U32, +k: U32, +acc: +List<U32>) -> Scanf:
  match n:
    case 0n: Scanf{True{}, False{}, k, 0, Nil{}, List.reverse(&2, U32, acc)}
    case 1n+r:
      +c = TT.u8(b, (p + k : U32))
      Bool.pick(Scanf, (k < len : U32) && Bool.not(U32.is_eq(c, 34)), name.at(r, b, p, len, (k + 1 : U32), Con{c, acc}),
        Scanf{True{}, False{}, k, 0, Nil{}, List.reverse(&2, U32, acc)})

def scanf.int(+ok: Bool, +k: U32, +count: U32, +values: +List<U32>, +name: +List<U32>, +r: IntAt) -> Scanf:
  IntAt{status, v, end} = r
  Scanf{ok && Bool.not(U32.is_eq(status, 2)), Bool.not(U32.is_eq(status, 1)), Bool.pick(U32, U32.is_eq(status, 1), end, k),
    Bool.pick(U32, U32.is_eq(status, 1), (count + 1 : U32), count), Bool.pick(+List<U32>, U32.is_eq(status, 1), List.append(&2, U32, values, [v]), values), name}

def scanf.name(+ok: Bool, +k: U32, +count: U32, +values: +List<U32>, +r: Scanf) -> Scanf:
  Scanf{_, _, end, _, _, name} = r
  +got = (end > k : U32)
  Scanf{ok, Bool.not(got), end, Bool.pick(U32, got, (count + 1 : U32), count), values, name}

def scanf.item.go(+f: Fmt, +b: TT.Blob, +p: U32, +len: U32, +ok: Bool, +k: U32, +count: U32, +values: +List<U32>, +name: +List<U32>, +c: U32) -> Scanf:
  match f:
    case FSpace{}: Scanf{ok, False{}, skip.space(U32.to_nat(len), b, p, len, k), count, values, name}
    case FLit{+lit}:
      +hit = (k < len : U32) && U32.is_eq(c, lit)
      Scanf{ok, Bool.not(hit), Bool.pick(U32, hit, (k + 1 : U32), k), count, values, name}
    case FInt{}: scanf.int(ok, k, count, values, name, int.at(b, p, len, k))
    case FName{}: scanf.name(ok, k, count, values, name.at(128n, b, p, len, k, Nil{}))

def scanf.item(+f: Fmt, +b: TT.Blob, +p: U32, +len: U32, +s: Scanf) -> Scanf:
  Scanf{ok, stopped, k, count, values, name} = s
  +c = TT.u8(b, (p + k : U32))
  Bool.pick(Scanf, stopped, s, scanf.item.go(f, b, p, len, ok, k, count, values, name, c))

def scanf.go(+fs: +List<Fmt>, +b: TT.Blob, +p: U32, +len: U32, +s: Scanf) -> Scanf:
  match fs:
    case Nil{}: s
    case Con{+f, rest}: scanf.go(rest, b, p, len, scanf.item(f, b, p, len, s))

# sscanf(p, format) over a C string of `len` bytes.
def sscanf(+b: TT.Blob, +p: U32, +len: U32, +format: +List<U32>) -> Scanf:
  scanf.go(fmt(format), b, p, len, Scanf{True{}, False{}, 0, 0, Nil{}, Nil{}})

# The position of the first occurrence of pat in [p, p + len) (len when none).
def find(n: Nat, +b: TT.Blob, +p: U32, +len: U32, +pat: +List<U32>, +k: U32) -> U32:
  match n:
    case 0n: len
    case 1n+r: Bool.pick(U32, starts(b, (p + k : U32), (len - k : U32), pat, 0), k, find(r, b, p, len, pat, (k + 1 : U32)))

def find.in(+b: TT.Blob, +p: U32, +len: U32, +pat: +List<U32>) -> U32:
  find(U32.to_nat((len + 1 : U32)), b, p, len, pat, 0)

# A GetLine: the line's start, its byte count and its C string length.
type Line is Data:
  Line{ok: Bool, p: U32, count: U32, len: U32}

def getline.made(+b: TT.Blob, +p: U32, +c: TT.Got) -> Line:
  TT.Got{ok, n} = c
  Line{ok, p, n, line.text(U32.to_nat(n), b, p, 0)}

def getline(+b: TT.Blob, +p: U32) -> Line:
  getline.made(b, p, line.count(255n, b, p, 0))

# The BMFont header: status 0 raylib's empty Font, 1 parsed, 2 refused.
type BmHeader is Data:
  BmHeader{status: U32, size: U32, scale_h: U32, pages: U32, name: +List<U32>, count: U32, at: U32}

def str.lineHeight() -> +List<U32>:
  [108, 105, 110, 101, 72, 101, 105, 103, 104, 116]

def str.file() -> +List<U32>:
  [102, 105, 108, 101]

def str.count() -> +List<U32>:
  [99, 111, 117, 110, 116]

# "lineHeight=% base=% scaleW=% scaleH=% pages=%"
def fmt.common() -> +List<U32>:
  [108, 105, 110, 101, 72, 101, 105, 103, 104, 116, 61, 37, 32, 98, 97, 115, 101, 61, 37, 32, 115, 99, 97, 108, 101, 87, 61, 37, 32,
    115, 99, 97, 108, 101, 72, 61, 37, 32, 112, 97, 103, 101, 115, 61, 37]

# 'file="@"'
def fmt.file() -> +List<U32>:
  [102, 105, 108, 101, 61, 34, 64, 34]

# "count=%"
def fmt.count() -> +List<U32>:
  [99, 111, 117, 110, 116, 61, 37]

# "char id=% x=% y=% width=% height=% xoffset=% yoffset=% xadvance=% page=%"
def fmt.char() -> +List<U32>:
  [99, 104, 97, 114, 32, 105, 100, 61, 37, 32, 120, 61, 37, 32, 121, 61, 37, 32, 119, 105, 100, 116, 104, 61, 37, 32, 104, 101, 105, 103,
    104, 116, 61, 37, 32, 120, 111, 102, 102, 115, 101, 116, 61, 37, 32, 121, 111, 102, 102, 115, 101, 116, 61, 37, 32, 120, 97, 100, 118,
    97, 110, 99, 101, 61, 37, 32, 112, 97, 103, 101, 61, 37]

def nth(n: Nat, +xs: +List<U32>) -> U32:
  match n xs:
    case 0n Con{+x, _}: x
    case 1n+k Con{_, rest}: nth(k, rest)
    case _ _: 0

def Line.ok(+l: Line) -> Bool:
  Line{ok, _, _, _} = l
  ok

def Line.next(+l: Line) -> U32:
  Line{_, p, count, _} = l
  (p + count + 1 : U32)

def Scanf.ok(+s: Scanf) -> Bool:
  Scanf{ok, _, _, _, _, _} = s
  ok

def Scanf.stopped(+s: Scanf) -> Bool:
  Scanf{_, stopped, _, _, _, _} = s
  stopped

def Scanf.k(+s: Scanf) -> U32:
  Scanf{_, _, k, _, _, _} = s
  k

def Scanf.count(+s: Scanf) -> U32:
  Scanf{_, _, _, count, _, _} = s
  count

def Scanf.values(+s: Scanf) -> +List<U32>:
  Scanf{_, _, _, _, values, _} = s
  values

def Scanf.name(+s: Scanf) -> +List<U32>:
  Scanf{_, _, _, _, _, name} = s
  name

# The searched field on a line: refused when strstr finds nothing (raylib
# passes NULL to sscanf).
def field(+b: TT.Blob, +l: Line, +pat: +List<U32>, +format: +List<U32>) -> Scanf:
  Line{ok, p, _, len} = l
  +at = find.in(b, p, len, pat)
  +found = (at < len : U32) || U32.is_eq(count(pat, 0), 0)
  +s = sscanf(b, (p + at : U32), (len - at : U32), format)
  Scanf{ok && found && Scanf.ok(s), Scanf.stopped(s), Scanf.k(s), Scanf.count(s), Scanf.values(s), Scanf.name(s)}

def bm.header(+b: TT.Blob) -> BmHeader:
  +l1 = getline(b, 0)
  +l2 = getline(b, Line.next(l1))
  +common = field(b, l2, str.lineHeight(), fmt.common())
  +l3 = getline(b, Line.next(l2))
  +file = field(b, l3, str.file(), fmt.file())
  +l4 = getline(b, Line.next(l3))
  +counted = field(b, l4, str.count(), fmt.count())
  +vs = Scanf.values(common)
  +pages = Bool.pick(U32, (Scanf.count(common) >= 5 : U32), nth(4n, vs), 1)
  +enough = (Scanf.count(common) >= 4 : U32) && Bool.not(neg(Scanf.count(common)))
  +named = (Scanf.count(file) >= 1 : U32)
  +counts = (Scanf.count(counted) >= 1 : U32)
  +single = U32.is_eq(pages, 1)
  +refused = Bool.not(Line.ok(l1) && Line.ok(l2) && Scanf.ok(common)) || (enough && Bool.not(single)) ||
    (enough && single && Bool.not(Line.ok(l3) && Scanf.ok(file))) || (enough && single && named && Bool.not(Line.ok(l4) && Scanf.ok(counted)))
  BmHeader{Bool.pick(U32, refused, 2, Bool.pick(U32, enough && named && counts, 1, 0)), nth(0n, vs), nth(3n, vs), pages,
    Scanf.name(file), nth(0n, Scanf.values(counted)), Line.next(l4)}

# One glyph line: the nine values, or refused (raylib then reads uninitialized
# rectangles).
type BmGlyph is Data:
  BmGlyph{ok: Bool, values: +List<U32>}

type BmGlyphs is Data:
  BmGlyphs{ok: Bool, at: U32, glyphs: +List<+List<U32>>}

def bm.glyph(+b: TT.Blob, +l: Line) -> BmGlyph:
  Line{ok, p, _, len} = l
  +s = sscanf(b, p, len, fmt.char())
  BmGlyph{ok && Scanf.ok(s) && U32.is_eq(Scanf.count(s), 9), Scanf.values(s)}

def BmGlyph.ok(+g: BmGlyph) -> Bool:
  BmGlyph{ok, _} = g
  ok

def BmGlyph.values(+g: BmGlyph) -> +List<U32>:
  BmGlyph{_, values} = g
  values

def bm.glyphs(n: Nat, +b: TT.Blob, +g: BmGlyphs) -> BmGlyphs:
  match n:
    case 0n: g
    case 1n+k:
      BmGlyphs{ok, at, glyphs} = g
      +l = getline(b, at)
      +one = bm.glyph(b, l)
      bm.glyphs(k, b, BmGlyphs{ok && BmGlyph.ok(one), Line.next(l), Con{BmGlyph.values(one), glyphs}})

def BmGlyphs.ok(+g: BmGlyphs) -> Bool:
  BmGlyphs{ok, _, _} = g
  ok

def BmGlyphs.glyphs(+g: BmGlyphs) -> +List<+List<U32>>:
  BmGlyphs{_, _, glyphs} = g
  glyphs

# The glyph lines after the header (count of them).
def bm.lines(+b: TT.Blob, +h: BmHeader) -> BmGlyphs:
  BmHeader{_, _, _, _, _, n, at} = h
  +g = bm.glyphs(U32.to_nat(Bool.pick(U32, neg(n), 0, n)), b, BmGlyphs{True{}, at, Nil{}})
  BmGlyphs{BmGlyphs.ok(g) && Bool.not(neg(n)) && (n <= 65536 : U32), 0, List.reverse(&2, +List<U32>, BmGlyphs.glyphs(g))}
