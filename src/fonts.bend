# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rtext.c (Copyright (c) 2013-2026
# Ramon Santamaria; zlib, LICENSES/raylib.txt): LoadFontDefault's glyph table
# (charsWidth, the rectangle walk) and the expansion of its 1-bit atlas
# (src/frame_font.bend), GetGlyphIndex, MeasureTextEx/MeasureTextCodepoints,
# the DrawTextEx/DrawTextCodepoint(s)/DrawTextPro streams (each glyph is
# rtextures.c's DrawTexturePro, src/textures.bend), LoadFontFromImage's
# key-color scan, and rtextures.c ImageTextEx's integer glyph placement.
# F32 arithmetic follows the C source order, uncontracted. C ints are U32
# two's-complement words. See docs/FONTS.md.
import Base
import ./frame.bend as F
import ./frame_font.bend as Atlas
import ./shapes.bend as S
import ./textures.bend as TD
import ./text.bend as TextCore

# -----------------------------------------------------------------------------
# C int helpers

def negative(+x: U32) -> Bool:
  (x >= 2147483648 : U32)

# (float) of a C int held as a two's-complement word.
def int.f32(+x: U32) -> F32:
  Bool.pick(F32, negative(x), F32.neg(U32.to_f32((0 - x : U32))), U32.to_f32(x))

# C's (int) of a float: defined for [-2^31, 2^31).
def int.valid(+x: F32) -> Bool:
  S.int.valid(x)

# The two's-complement word of (int)x (x must be valid).
def int.of(+x: F32) -> U32:
  +t = F32.trunc(x)
  Bool.pick(U32, (t < 0.0 : F32), (0 - F32.to_u32(F32.neg(Bool.pick(F32, (t < 0.0 : F32), t, 0.0))) : U32),
    F32.to_u32(Bool.pick(F32, (t < 0.0 : F32), 0.0, t)))

# a + b as C ints, and whether the sum overflows (undefined in C).
def add.ok(+a: U32, +b: U32) -> Bool:
  +s = (a + b : U32)
  Bool.not(U32.is_eq(Bool.pick(U32, negative(a), 1, 0), Bool.pick(U32, negative(b), 1, 0))) || U32.is_eq(Bool.pick(U32, negative(a), 1, 0), Bool.pick(U32, negative(s), 1, 0))

# a < b as C ints.
def less(+a: U32, +b: U32) -> Bool:
  ((a + 2147483648 : U32) < (b + 2147483648 : U32) : U32)

# -----------------------------------------------------------------------------
# Glyphs: GlyphInfo's value, offsets and advance with the glyph's atlas
# rectangle (Font.recs).

type Glyph is Data:
  Glyph{value: U32, offset_x: U32, offset_y: U32, advance_x: U32, x: F32, y: F32, width: F32, height: F32}

def Glyph.value(+g: Glyph) -> U32:
  Glyph{value, _, _, _, _, _, _, _} = g
  value

def Glyph.offset_x(+g: Glyph) -> U32:
  Glyph{_, offset_x, _, _, _, _, _, _} = g
  offset_x

def Glyph.offset_y(+g: Glyph) -> U32:
  Glyph{_, _, offset_y, _, _, _, _, _} = g
  offset_y

def Glyph.advance_x(+g: Glyph) -> U32:
  Glyph{_, _, _, advance_x, _, _, _, _} = g
  advance_x

def Glyph.width(+g: Glyph) -> F32:
  Glyph{_, _, _, _, _, _, width, _} = g
  width

def Glyph.zero() -> Glyph:
  Glyph{0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0}

# A font's glyph data: glyphs, baseSize, glyphPadding and IsFontValid.
type Face is Data:
  Face{glyphs: +List<Glyph>, base: U32, padding: U32, valid: Bool}

def nonempty(+glyphs: +List<Glyph>) -> Bool:
  match glyphs:
    case Nil{}: False{}
    case Con{_, _}: True{}

# IsFontValid: baseSize > 0 and glyphs (and recs) present.
def valid(+base: U32, +glyphs: +List<Glyph>) -> Bool:
  Bool.not(negative(base)) && Bool.not(U32.is_eq(base, 0)) && nonempty(glyphs)

def Face.new(+glyphs: +List<Glyph>, +base: U32, +padding: U32) -> Face:
  Face{glyphs, base, padding, valid(base, glyphs)}

def Face.base(+face: Face) -> U32:
  Face{_, base, _, _} = face
  base

def count(glyphs: +List<Glyph>) -> U32:
  match glyphs:
    case Nil{}: 0
    case Con{_, rest}: (1 + count(rest) : U32)

# GetGlyphIndex (SUPPORT_UNORDERED_CHARSET): the first glyph whose value is
# the codepoint; otherwise the last '?' (63) glyph, or 0. 0 for an invalid font.
def index.go(glyphs: +List<Glyph>, +cp: U32, +i: U32, +fallback: U32, +found: Bool, +at: U32) -> U32:
  match glyphs:
    case Nil{}: Bool.pick(U32, found, at, fallback)
    case Con{+g, rest}:
      +hit = Bool.not(found) && U32.is_eq(Glyph.value(g), cp)
      index.go(rest, cp, (i + 1 : U32), Bool.pick(U32, U32.is_eq(Glyph.value(g), 63), i, fallback), found || hit, Bool.pick(U32, hit, i, at))

def index(+face: Face, +cp: U32) -> U32:
  Face{glyphs, _, _, valid} = face
  Bool.pick(U32, valid, index.go(glyphs, cp, 0, 0, False{}, 0), 0)

def glyph.head(glyphs: +List<Glyph>) -> Glyph:
  match glyphs:
    case Nil{}: Glyph.zero()
    case Con{g, _}: g

def glyph.at(+glyphs: +List<Glyph>, +n: U32) -> Glyph:
  glyph.head(List.drop(&2, Glyph, glyphs, U32.to_nat(n)))

# font.glyphs[GetGlyphIndex(font, codepoint)] with its rectangle.
def Face.glyph(+face: Face, +cp: U32) -> Glyph:
  Face{glyphs, _, _, _} = face
  glyph.at(glyphs, index(face, cp))

# -----------------------------------------------------------------------------
# LoadFontDefault: 224 glyphs (codepoints 32..255) of charsWidth[i] x 10
# pixels, separated by one pixel and wrapped at 128; offsets and advance 0;
# baseSize 10, glyphPadding 0.

def default.widths.chunk(index: U32) -> +List<U32>:
  match index:
    case 0: [3, 1, 4, 6, 5, 7, 6, 2, 3, 3, 5, 5, 2, 4, 1, 7, 5, 2, 5, 5, 5, 5, 5, 5, 5, 5, 1, 1, 3, 4, 3, 6]
    case 1: [7, 6, 6, 6, 6, 6, 6, 6, 6, 3, 5, 6, 5, 7, 6, 6, 6, 6, 6, 6, 7, 6, 7, 7, 6, 6, 6, 2, 7, 2, 3, 5]
    case 2: [2, 5, 5, 5, 5, 5, 4, 5, 5, 1, 2, 5, 2, 5, 5, 5, 5, 5, 5, 5, 4, 5, 5, 5, 5, 5, 5, 3, 1, 3, 4, 4]
    case 3: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    case 4: [1, 1, 5, 5, 5, 7, 1, 5, 3, 7, 3, 5, 4, 1, 7, 4, 3, 5, 3, 3, 2, 5, 6, 1, 2, 2, 3, 5, 6, 6, 6, 6]
    case 5: [6, 6, 6, 6, 6, 6, 7, 6, 6, 6, 6, 6, 3, 3, 3, 3, 7, 6, 6, 6, 6, 6, 6, 5, 6, 6, 6, 6, 6, 6, 4, 6]
    case _: [5, 5, 5, 5, 5, 5, 9, 5, 5, 5, 5, 5, 2, 2, 3, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5]

# charsWidth, in order.
def default.widths.go(n: Nat, +index: U32) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+k: List.append(&2, U32, default.widths.chunk(index), default.widths.go(k, (index + 1 : U32)))

def default.widths() -> +List<U32>:
  default.widths.go(7n, 0)

# The rectangle walk: testPosX equals currentPosX at the top of each step.
def default.go(widths: +List<U32>, +i: U32, +line: U32, +current: U32) -> +List<Glyph>:
  match widths:
    case Nil{}: Nil{}
    case Con{+w, rest}:
      +wrap = ((current + w + 1 : U32) >= 128 : U32)
      +row = Bool.pick(U32, wrap, (line + 1 : U32), line)
      Con{Glyph{(32 + i : U32), 0, 0, 0, U32.to_f32(Bool.pick(U32, wrap, 1, current)), U32.to_f32((1 + row * 11 : U32)), U32.to_f32(w), 10.0},
        default.go(rest, (i + 1 : U32), row, Bool.pick(U32, wrap, (2 + w : U32), (current + w + 1 : U32)))}

def default.glyphs() -> +List<Glyph>:
  default.go(default.widths(), 0, 0, 1)

def default.face() -> Face:
  Face.new(default.glyphs(), 10, 0)

# The 128x128 atlas: pixel 32n + j takes `on` when bit j of defaultFontData[n]
# is set, `off` otherwise (GRAY_ALPHA words 0xffff and 0x00ff for the image;
# rlsw's readColor8 texels for the texture).
def expand.put(set: Bool, +at: U32, +on: U32, out: Array<U32>) -> Array<U32>:
  match set:
    case False{}: out
    case True{}: Array.set(U32, out, at, on)

def expand.bits(n: Nat, +bit: U32, +word: U32, +base: U32, +on: U32, out: Array<U32>) -> Array<U32>:
  match n:
    case 0n: out
    case 1n+k: expand.bits(k, (bit + 1 : U32), word, base, on, expand.put(U32.is_eq(((word >> U32.to_nat(bit)) .&. 1 : U32), 1), (base + bit : U32), on, out))

def expand.words(n: Nat, +index: U32, +on: U32, read: Array<U32> & U32, out: Array<U32>) -> Array<U32>:
  match n read:
    case 0n _: out
    case 1n+k Tuple{words, +word}:
      expand.words(k, (index + 1 : U32), on, Array.get(U32, words, (index + 1 : U32)), expand.bits(32n, 0, word, (index * 32 : U32), on, out))

def expand(+on: U32, +off: U32) -> Array<U32>:
  expand.words(512n, 0, on, Array.get(U32, Atlas.atlas(), 0), Array.new(U32, 14n, off))

# -----------------------------------------------------------------------------
# MeasureTextEx / MeasureTextCodepoints

type Extent is Data:
  Extent{x: F32, y: F32}

def Extent.x(+e: Extent) -> F32:
  Extent{x, _} = e
  x

def Extent.y(+e: Extent) -> F32:
  Extent{_, y} = e
  y

# textWidth, tempTextWidth, textHeight, the glyphs on the line and the most
# on any line.
type Measure is Data:
  Measure{width: F32, longest: F32, height: F32, count: U32, most: U32}

# advanceX > 0 ? advanceX : recs.width + offsetX
def measure.advance(+g: Glyph) -> F32:
  Glyph{_, offset_x, _, advance_x, _, _, width, _} = g
  Bool.pick(F32, Bool.not(negative(advance_x)) && Bool.not(U32.is_eq(advance_x, 0)), int.f32(advance_x), (width + int.f32(offset_x) : F32))

def measure.glyph(+g: Glyph, m: Measure) -> Measure:
  Measure{width, longest, height, count, +most} = m
  +n = (count + 1 : U32)
  Measure{(width + measure.advance(g) : F32), longest, height, n, Bool.pick(U32, (most < n : U32), n, most)}

def measure.line(+size: F32, +line: F32, m: Measure) -> Measure:
  Measure{+width, +longest, height, _, most} = m
  Measure{0.0, Bool.pick(F32, (longest < width : F32), width, longest), (height + (size + line : F32) : F32), 0, most}

def measure.step(newline: Bool, +face: Face, +cp: U32, +size: F32, +line: F32, m: Measure) -> Measure:
  match newline:
    case True{}: measure.line(size, line, m)
    case False{}: measure.glyph(Face.glyph(face, cp), m)

def measure.go(cps: +List<U32>, +face: Face, +size: F32, +line: F32, m: Measure) -> Measure:
  match cps:
    case Nil{}: m
    case Con{+cp, rest}: measure.go(rest, face, size, line, measure.step(U32.is_eq(cp, 10), face, cp, size, line, m))

def measure.done(+base: U32, +size: F32, +spacing: F32, m: Measure) -> Extent:
  Measure{+width, +longest, height, _, +most} = m
  +widest = Bool.pick(F32, (longest < width : F32), width, longest)
  Extent{((widest * (size / int.f32(base) : F32) : F32) + (int.f32((most - 1 : U32)) * spacing : F32) : F32), height}

# The size of the codepoints (empty: 0, 0); line is textLineSpacing as a float.
def measure(cps: +List<U32>, +face: Face, +size: F32, +spacing: F32, +line: F32) -> Extent:
  match cps:
    case Nil{}: Extent{0.0, 0.0}
    case Con{+cp, rest}: measure.done(Face.base(face), size, spacing, measure.go(Con{cp, rest}, face, size, line, Measure{0.0, 0.0, size, 0, 0}))

# -----------------------------------------------------------------------------
# DrawTextCodepoint / DrawTextEx / DrawTextCodepoints / DrawTextPro

def plan.cat(a: S.Plan, b: S.Plan) -> S.Plan:
  S.Plan{valid, commands} = a
  S.Plan.with(valid, commands, b)

# DrawTextCodepoint: DrawTexturePro(font.texture, srcRec, dstRec, (0, 0), 0,
# tint) with the glyph padding around the atlas rectangle; the texture has tw
# x th texels and binds as kind.
def codepoint.glyph(+g: Glyph, +base: U32, +padding: U32, +kind: U32, +tw: F32, +th: F32, +px: F32, +py: F32, +size: F32, +tint: U32) -> S.Plan:
  Glyph{_, ox, oy, _, x, y, +w, +h} = g
  +scale = (size / int.f32(base) : F32)
  +pad = int.f32(padding)
  +twice = (2.0 * pad : F32)
  TD.pro(False{}, kind, tw, th, (x - pad : F32), (y - pad : F32), (w + twice : F32), (h + twice : F32),
    ((px + (int.f32(ox) * scale : F32) : F32) - (pad * scale : F32) : F32), ((py + (int.f32(oy) * scale : F32) : F32) - (pad * scale : F32) : F32),
    ((w + twice : F32) * scale : F32), ((h + twice : F32) * scale : F32), 0.0, 0.0, 0.0, tint)

def codepoint(+face: Face, +kind: U32, +tw: F32, +th: F32, +cp: U32, +px: F32, +py: F32, +size: F32, +tint: U32) -> S.Plan:
  Face{_, base, padding, _} = face
  codepoint.glyph(Face.glyph(face, cp), base, padding, kind, tw, th, px, py, size, tint)

# advanceX == 0 ? recs.width*scale + spacing : advanceX*scale + spacing
def draw.advance(+g: Glyph, +scale: F32, +spacing: F32) -> F32:
  Glyph{_, _, _, advance_x, _, _, width, _} = g
  Bool.pick(F32, U32.is_eq(advance_x, 0), ((width * scale : F32) + spacing : F32), ((int.f32(advance_x) * scale : F32) + spacing : F32))

def text.glyph(visible: Bool, +face: Face, +kind: U32, +tw: F32, +th: F32, +cp: U32, +px: F32, +py: F32, +size: F32, +tint: U32, rest: S.Plan) -> S.Plan:
  match visible:
    case False{}: rest
    case True{}: plan.cat(codepoint(face, kind, tw, th, cp, px, py, size, tint), rest)

# The DrawTextEx loop from the offsets (ox, oy): '\n' moves down by
# fontSize + textLineSpacing, ' ' and '\t' only advance.
def text.go(cps: +List<U32>, +face: Face, +kind: U32, +tw: F32, +th: F32, +px: F32, +py: F32, +size: F32, +spacing: F32, +line: F32, +tint: U32, +ox: F32, +oy: F32) -> S.Plan:
  match cps:
    case Nil{}: S.Plan.empty()
    case Con{+cp, rest}:
      +newline = U32.is_eq(cp, 10)
      +scale = (size / int.f32(Face.base(face)) : F32)
      text.glyph(Bool.not(newline) && Bool.not(U32.is_eq(cp, 32)) && Bool.not(U32.is_eq(cp, 9)), face, kind, tw, th, cp, (px + ox : F32), (py + oy : F32), size, tint,
        text.go(rest, face, kind, tw, th, px, py, size, spacing, line, tint,
          Bool.pick(F32, newline, 0.0, (ox + draw.advance(Face.glyph(face, cp), scale, spacing) : F32)),
          Bool.pick(F32, newline, (oy + (size + line : F32) : F32), oy)))

# DrawTextEx (and DrawTextCodepoints) at (px, py).
def text(cps: +List<U32>, +face: Face, +kind: U32, +tw: F32, +th: F32, +px: F32, +py: F32, +size: F32, +spacing: F32, +line: F32, +tint: U32) -> S.Plan:
  text.go(cps, face, kind, tw, th, px, py, size, spacing, line, tint, 0.0, 0.0)

# DrawTextPro: rlPushMatrix, rlTranslatef(position), rlRotatef(rotation, 0, 0,
# 1) (sinf/cosf always evaluated), rlTranslatef(-origin), DrawTextEx at (0, 0),
# rlPopMatrix.
def text.pro(+gnu: Bool, cps: +List<U32>, +face: Face, +kind: U32, +tw: F32, +th: F32, +px: F32, +py: F32, +ox: F32, +oy: F32, +rotation: F32, +size: F32, +spacing: F32, +line: F32, +tint: U32) -> S.Plan:
  plan.cat(S.Plan.only(True{}, [F.Push{}]), plan.cat(TD.translate(px, py, 0.0), plan.cat(TD.rotate(gnu, rotation, 0.0, 0.0, 1.0),
    plan.cat(TD.translate(F32.neg(ox), F32.neg(oy), 0.0), plan.cat(text(cps, face, kind, tw, th, 0.0, 0.0, size, spacing, line, tint),
    S.Plan.only(True{}, [F.Pop{}]))))))

# -----------------------------------------------------------------------------
# ImageTextEx's placement: integer offsets, '\n' moves down by baseSize +
# baseSize/2 (not textLineSpacing), advances (int)(recs.width + spacing) or
# advanceX + (int)spacing. None when an (int) conversion or an int sum is
# undefined.

type Place is Data:
  Place{x: U32, y: U32, glyph: Glyph}

type Pen is Data:
  Pen{ok: Bool, x: U32, y: U32, places: +List<Place>}

def image.half(+base: U32) -> U32:
  Bool.pick(U32, negative(base), (0 - ((0 - base : U32) / 2) : U32), (base / 2 : U32))

def image.newline(+base: U32, pen: Pen) -> Pen:
  Pen{ok, _, +y, places} = pen
  +step = (base + image.half(base) : U32)
  Pen{ok && add.ok(base, image.half(base)) && add.ok(y, step), 0, (y + step : U32), places}

def image.place.at(+g: Glyph, +x: U32, +y: U32, places: +List<Place>) -> +List<Place>:
  Glyph{_, ox, oy, _, _, _, _, _} = g
  Con{Place{(x + ox : U32), (y + oy : U32), g}, places}

def image.place(visible: Bool, +g: Glyph, +x: U32, +y: U32, places: +List<Place>) -> +List<Place>:
  match visible:
    case False{}: places
    case True{}: image.place.at(g, x, y, places)

def image.glyph(+visible: Bool, +g: Glyph, +spacing: F32, pen: Pen) -> Pen:
  Pen{ok, +x, +y, places} = pen
  +ox = Glyph.offset_x(g)
  +oy = Glyph.offset_y(g)
  +advance = Glyph.advance_x(g)
  +width = Glyph.width(g)
  +plain = U32.is_eq(advance, 0)
  +sum = (width + spacing : F32)
  +converted = Bool.pick(Bool, plain, int.valid(sum), int.valid(spacing))
  +step = Bool.pick(U32, plain, int.of(Bool.pick(F32, int.valid(sum), sum, 0.0)), (advance + int.of(Bool.pick(F32, int.valid(spacing), spacing, 0.0)) : U32))
  +inner = plain || add.ok(advance, int.of(Bool.pick(F32, int.valid(spacing), spacing, 0.0)))
  +placed = Bool.not(visible) || (add.ok(x, ox) && add.ok(y, oy))
  Pen{ok && converted && inner && placed && add.ok(x, step), (x + step : U32), y, image.place(visible, g, x, y, places)}

def image.step(newline: Bool, +face: Face, +cp: U32, +spacing: F32, pen: Pen) -> Pen:
  match newline:
    case True{}: image.newline(Face.base(face), pen)
    case False{}: image.glyph(Bool.not(U32.is_eq(cp, 32)) && Bool.not(U32.is_eq(cp, 9)), Face.glyph(face, cp), spacing, pen)

def image.go(cps: +List<U32>, +face: Face, +spacing: F32, pen: Pen) -> Pen:
  match cps:
    case Nil{}: pen
    case Con{+cp, rest}: image.go(rest, face, spacing, image.step(U32.is_eq(cp, 10), face, cp, spacing, pen))

def image.done(pen: Pen) -> Maybe<+List<Place>>:
  Pen{ok, _, _, places} = pen
  Bool.pick(Maybe<+List<Place>>, ok, Some{List.reverse(&2, Place, places)}, None{})

def image.layout(cps: +List<U32>, +face: Face, +spacing: F32) -> Maybe<+List<Place>>:
  image.done(image.go(cps, face, spacing, Pen{True{}, 0, 0, Nil{}}))

# -----------------------------------------------------------------------------
# LoadFontFromImage's scan of the LoadImageColors words (row-major, width w,
# height h) against the key color. Reads raylib makes past the last pixel are
# refused; at most 256 glyphs (MAX_GLYPHS_FROM_IMAGE) are recorded.

# The scan state: the colors, status (0 searching, 1 done, 2 refused) and two
# counters.
type Scan is Type:
  Scan{colors: Array<U32>, status: U32, a: U32, b: U32}

# The first column of row `at` whose color differs from the key (or w): every
# column is read, the first hit kept.
def first(n: Nat, +x: U32, +found: Bool, +hit: U32, +key: U32, +at: U32, read: Array<U32> & U32) -> Array<U32> & U32:
  match n read:
    case 0n Tuple{colors, _}: (colors, Bool.pick(U32, found, hit, x))
    case 1n+k Tuple{colors, +c}:
      +now = Bool.not(found) && Bool.not(U32.is_eq(c, key))
      first(k, (x + 1 : U32), found || now, Bool.pick(U32, now, x, hit), key, at, Array.get(U32, colors, (at + x + 1 : U32)))

def row.first(+w: U32, +key: U32, +at: U32, colors: Array<U32>) -> Array<U32> & U32:
  first(U32.to_nat(w), 0, False{}, 0, key, at, Array.get(U32, colors, at))

# A row of key colors: raylib then tests pixels[y*w + w], the next row's first
# pixel (past the image on the last row).
def spacing.next(+w: U32, +h: U32, +key: U32, +y: U32, read: Array<U32> & U32) -> Scan:
  (colors, +c) = read
  Scan{colors, Bool.pick(U32, U32.is_eq(c, key), 0, 1), w, Bool.pick(U32, U32.is_eq(c, key), (y + 1 : U32), y)}

def spacing.edge(last: Bool, +w: U32, +h: U32, +key: U32, +y: U32, colors: Array<U32>) -> Scan:
  match last:
    case True{}: Scan{colors, 2, w, y}
    case False{}: spacing.next(w, h, key, y, Array.get(U32, colors, ((y + 1) * w : U32)))

def spacing.row(edge: Bool, +w: U32, +h: U32, +key: U32, +x: U32, +y: U32, colors: Array<U32>) -> Scan:
  match edge:
    case False{}: Scan{colors, 1, x, y}
    case True{}: spacing.edge(U32.is_eq((y + 1 : U32), h), w, h, key, y, colors)

def spacing.found(+w: U32, +h: U32, +key: U32, +y: U32, found: Array<U32> & U32) -> Scan:
  (colors, +x) = found
  spacing.row(U32.is_eq(x, w), w, h, key, x, y, colors)

def spacing.step(status: U32, +w: U32, +h: U32, +key: U32, colors: Array<U32>, +x: U32, +y: U32) -> Scan:
  match status:
    case 0: spacing.found(w, h, key, y, row.first(w, key, (y * w : U32), colors))
    case _: Scan{colors, status, x, y}

def spacing.go(n: Nat, +w: U32, +h: U32, +key: U32, scan: Scan) -> Scan:
  match n scan:
    case 0n s: s
    case 1n+k Scan{colors, status, x, y}: spacing.go(k, w, h, key, spacing.step(status, w, h, key, colors, x, y))

# charSpacing (x) and lineSpacing (y): the first pixel, row by row, that is
# not the key; status 1 found, 2 refused (the read past the last pixel).
def spacing(+w: U32, +h: U32, +key: U32, colors: Array<U32>) -> Scan:
  spacing.go(U32.to_nat(h), w, h, key, Scan{colors, 0, 0, 0})

# charHeight: rows below lineSpacing whose pixel at charSpacing is not the key.
def height.read(+key: U32, +j: U32, read: Array<U32> & U32) -> Scan:
  (colors, +c) = read
  Scan{colors, Bool.pick(U32, U32.is_eq(c, key), 1, 0), Bool.pick(U32, U32.is_eq(c, key), j, (j + 1 : U32)), 0}

def height.inside(inside: Bool, outside: Bool, +key: U32, +j: U32, +at: U32, colors: Array<U32>) -> Scan:
  match inside outside:
    case False{} _: Scan{colors, 1, j, 0}
    case True{} True{}: Scan{colors, 2, j, 0}
    case True{} False{}: height.read(key, j, Array.get(U32, colors, at))

def height.step(status: U32, +w: U32, +h: U32, +key: U32, +x: U32, +y: U32, colors: Array<U32>, +j: U32) -> Scan:
  match status:
    case 0: height.inside(((y + j) < h : U32), ((((y + j) * w + x) : U32) >= (w * h : U32) : U32), key, j, ((y + j) * w + x : U32), colors)
    case _: Scan{colors, status, j, 0}

def height.go(n: Nat, +w: U32, +h: U32, +key: U32, +x: U32, +y: U32, scan: Scan) -> Scan:
  match n scan:
    case 0n s: s
    case 1n+k Scan{colors, status, j, _}: height.go(k, w, h, key, x, y, height.step(status, w, h, key, x, y, colors, j))

def height(+w: U32, +h: U32, +key: U32, +x: U32, +y: U32, colors: Array<U32>) -> Scan:
  height.go(1n+U32.to_nat(h), w, h, key, x, y, Scan{colors, 0, 0, 0})

# A glyph's width: columns from xp on that are not the key.
def width.go(n: Nat, +k: U32, +stop: Bool, +key: U32, +at: U32, +room: U32, read: Array<U32> & U32) -> Array<U32> & U32:
  match n read:
    case 0n Tuple{colors, _}: (colors, k)
    case 1n+m Tuple{colors, +c}:
      +more = Bool.not(stop) && (k < room : U32) && Bool.not(U32.is_eq(c, key))
      width.go(m, Bool.pick(U32, more, (k + 1 : U32), k), Bool.not(more), key, at, room,
        Array.get(U32, colors, (at + Bool.pick(U32, more && ((k + 1) < room : U32), (k + 1 : U32), 0) : U32)))

def width(+w: U32, +key: U32, +at: U32, +room: U32, colors: Array<U32>) -> Array<U32> & U32:
  width.go(1n+U32.to_nat(w), 0, False{}, key, at, room, Array.get(U32, colors, at))

# One line's glyphs: (status, count, x) with status 0 scanning, 1 line done,
# 2 refused (more than 256 glyphs).
type Line is Type:
  Line{colors: Array<U32>, status: U32, count: U32, x: U32, glyphs: +List<Glyph>}

def line.glyph(+w: U32, +key: U32, +spacing: U32, +row: U32, +ch: U32, +first: U32, +count: U32, +xp: U32, glyphs: +List<Glyph>, measured: Array<U32> & U32) -> Line:
  (colors, +cw) = measured
  Line{colors, Bool.pick(U32, (count >= 256 : U32), 2, 0), (count + 1 : U32), (xp + cw + spacing : U32),
    Con{Glyph{(first + count : U32), 0, 0, 0, U32.to_f32(xp), U32.to_f32(row), U32.to_f32(cw), U32.to_f32(ch)}, glyphs}}

def line.hit(is_key: Bool, +w: U32, +key: U32, +spacing: U32, +row: U32, +ch: U32, +first: U32, +count: U32, +xp: U32, glyphs: +List<Glyph>, colors: Array<U32>) -> Line:
  match is_key:
    case True{}: Line{colors, 1, count, xp, glyphs}
    case False{}: line.glyph(w, key, spacing, row, ch, first, count, xp, glyphs, width(w, key, (row * w + xp : U32), (w - xp : U32), colors))

def line.read(+w: U32, +key: U32, +spacing: U32, +row: U32, +ch: U32, +first: U32, +count: U32, +xp: U32, glyphs: +List<Glyph>, read: Array<U32> & U32) -> Line:
  (colors, +c) = read
  line.hit(U32.is_eq(c, key), w, key, spacing, row, ch, first, count, xp, glyphs, colors)

def line.inside(inside: Bool, +w: U32, +key: U32, +spacing: U32, +row: U32, +ch: U32, +first: U32, +count: U32, +xp: U32, glyphs: +List<Glyph>, colors: Array<U32>) -> Line:
  match inside:
    case False{}: Line{colors, 1, count, xp, glyphs}
    case True{}: line.read(w, key, spacing, row, ch, first, count, xp, glyphs, Array.get(U32, colors, (row * w + xp : U32)))

def line.step(status: U32, +w: U32, +key: U32, +spacing: U32, +row: U32, +ch: U32, +first: U32, colors: Array<U32>, +count: U32, +xp: U32, glyphs: +List<Glyph>) -> Line:
  match status:
    case 0: line.inside((xp < w : U32), w, key, spacing, row, ch, first, count, xp, glyphs, colors)
    case _: Line{colors, status, count, xp, glyphs}

def line.go(n: Nat, +w: U32, +key: U32, +spacing: U32, +row: U32, +ch: U32, +first: U32, state: Line) -> Line:
  match n state:
    case 0n s: s
    case 1n+k Line{colors, status, count, xp, glyphs}: line.go(k, w, key, spacing, row, ch, first, line.step(status, w, key, spacing, row, ch, first, colors, count, xp, glyphs))

# The lines: rows lineSpacing + L*(charHeight + lineSpacing) below h.
def lines.next(state: Line) -> Line:
  Line{colors, inner, count, x, glyphs} = state
  Line{colors, Bool.pick(U32, U32.is_eq(inner, 2), 2, 0), count, x, glyphs}

def lines.inside(inside: Bool, +w: U32, +key: U32, +spacing: U32, +row: U32, +ch: U32, +first: U32, colors: Array<U32>, +count: U32, glyphs: +List<Glyph>) -> Line:
  match inside:
    case False{}: Line{colors, 1, count, 0, glyphs}
    case True{}: lines.next(line.go(1n+U32.to_nat(w), w, key, spacing, row, ch, first, Line{colors, 0, count, spacing, glyphs}))

def lines.step(status: U32, +w: U32, +h: U32, +key: U32, +spacing: U32, +lead: U32, +ch: U32, +first: U32, +line: U32, colors: Array<U32>, +count: U32, glyphs: +List<Glyph>) -> Line:
  match status:
    case 0: lines.inside(((lead + line * (ch + lead)) < h : U32), w, key, spacing, (lead + line * (ch + lead) : U32), ch, first, colors, count, glyphs)
    case _: Line{colors, status, count, line, glyphs}

def lines.go(n: Nat, +w: U32, +h: U32, +key: U32, +spacing: U32, +lead: U32, +ch: U32, +first: U32, +line: U32, state: Line) -> Line:
  match n state:
    case 0n s: s
    case 1n+k Line{colors, status, count, _, glyphs}:
      lines.go(k, w, h, key, spacing, lead, ch, first, (line + 1 : U32), lines.step(status, w, h, key, spacing, lead, ch, first, line, colors, count, glyphs))

# The glyph rectangles in order: status 1 when the scan ended, 2 refused.
def lines(+w: U32, +h: U32, +key: U32, +spacing: U32, +lead: U32, +ch: U32, +first: U32, colors: Array<U32>) -> Line:
  lines.go(1n+U32.to_nat(h), w, h, key, spacing, lead, ch, first, 0, Line{colors, 0, 0, 0, Nil{}})

# The colors with every key pixel made BLANK (0): fontClear.
def clear.put(is_key: Bool, +i: U32, colors: Array<U32>) -> Array<U32>:
  match is_key:
    case False{}: colors
    case True{}: Array.set(U32, colors, i, 0)

def clear(n: Nat, +i: U32, +key: U32, read: Array<U32> & U32) -> Array<U32>:
  match n read:
    case 0n Tuple{colors, _}: colors
    case 1n+k Tuple{colors, +c}: clear(k, (i + 1 : U32), key, Array.get(U32, clear.put(U32.is_eq(c, key), i, colors), (i + 1 : U32)))
