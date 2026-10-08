# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_truetype.h v1.26 as pinned raylib 6.0 vendors
# it (src/external/stb_truetype.h, Sean Barrett, public domain / MIT;
# LICENSES/stb_truetype.txt): stbtt_InitFont (TrueType `glyf` fonts),
# stbtt_FindGlyphIndex (cmap formats 0, 4, 6, 12 and 13), stbtt_GetFontVMetrics,
# stbtt_ScaleForPixelHeight, stbtt_GetGlyphHMetrics, stbtt_GetGlyphBox,
# stbtt__GetGlyphShapeTT (simple and composite glyphs), stbtt_FlattenCurves,
# the version-2 antialiasing rasterizer (stbtt__rasterize, its quicksort and
# insertion sort of edges, stbtt__rasterize_sorted_edges,
# stbtt__fill_active_edges_new, stbtt__handle_clipped_edge),
# stbtt_GetGlyphBitmapSubpixel and stbtt_GetGlyphSDF for glyphs whose distance
# search never reaches the cubic solver. F32 arithmetic follows the C source
# order, uncontracted (raylib built with -ffp-contract=off); release build, so
# STBTT_assert is a no-op. C ints are U32 two's-complement words.
#
# stb_truetype does no bounds checking. Every byte it reads is checked here
# against the font data; a read outside it, a signed int overflow, a float to
# int conversion out of range, an uninitialized bitmap, a CFF (OpenType)
# outline, composite nesting deeper than 6 and an SDF needing the cubic solver
# (which uses double pow/acos/cos from the C library) are refused instead of
# reproduced. See docs/FONTS.md.
import Base

# -----------------------------------------------------------------------------
# C int helpers

def neg(+x: U32) -> Bool:
  (x >= 2147483648 : U32)

# a < b as C ints.
def slt(+a: U32, +b: U32) -> Bool:
  ((a + 2147483648 : U32) < (b + 2147483648 : U32) : U32)

def sext16(+x: U32) -> U32:
  +v = (x .&. 65535 : U32)
  Bool.pick(U32, (v >= 32768 : U32), (v .|. 4294901760 : U32), v)

def sext8(+x: U32) -> U32:
  +v = (x .&. 255 : U32)
  Bool.pick(U32, (v >= 128 : U32), (v .|. 4294967040 : U32), v)

# x >> 1 on a C int (arithmetic).
def asr1(+x: U32) -> U32:
  ((x >> 1n) .|. (x .&. 2147483648) : U32)

# (float) of a C int.
def i2f(+x: U32) -> F32:
  Bool.pick(F32, neg(x), F32.neg(U32.to_f32((0 - x : U32))), U32.to_f32(x))

def flt(word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# (int)x is defined: -2^31 <= x < 2^31 (NaN fails).
def f2i.valid(+x: F32) -> Bool:
  (x >= F32.neg(2147483648.0) : F32) && (x < 2147483648.0 : F32)

# (int)x for a valid x (truncation).
def f2i(+x: F32) -> U32:
  +t = F32.trunc(x)
  Bool.pick(U32, (t < 0.0 : F32), (0 - F32.to_u32(F32.neg(Bool.pick(F32, (t < 0.0 : F32), t, 0.0))) : U32),
    F32.to_u32(Bool.pick(F32, (t < 0.0 : F32), 0.0, t)))

# (short)x: defined when the truncation fits in [-32768, 32767].
def f2s.valid(+x: F32) -> Bool:
  (x > F32.neg(32769.0) : F32) && (x < 32768.0 : F32)

# a + b as C ints does not overflow.
def add.ok(+a: U32, +b: U32) -> Bool:
  +s = (a + b : U32)
  Bool.not(U32.is_eq(Bool.to_u32(neg(a)), Bool.to_u32(neg(b)))) || U32.is_eq(Bool.to_u32(neg(a)), Bool.to_u32(neg(s)))

def sub.ok(+a: U32, +b: U32) -> Bool:
  +s = (a - b : U32)
  U32.is_eq(Bool.to_u32(neg(a)), Bool.to_u32(neg(b))) || U32.is_eq(Bool.to_u32(neg(a)), Bool.to_u32(neg(s)))

# -----------------------------------------------------------------------------
# Font data: a balanced tree of bytes, shared read-only.

type Bytes is Data:
  BLeaf{value: U32}
  BNode{lo: Bytes, hi: Bytes}

def leaves(n: Nat, +bytes: +List<U32>, +acc: +List<Bytes>) -> +List<Bytes>:
  match n bytes:
    case 0n _: List.reverse(&2, Bytes, acc)
    case 1n+k Nil{}: leaves(k, Nil{}, Con{BLeaf{0}, acc})
    case 1n+k Con{+b, rest}: leaves(k, rest, Con{BLeaf{b}, acc})

def pairs(+xs: +List<Bytes>, +acc: +List<Bytes>) -> +List<Bytes>:
  match xs:
    case Con{+a, Con{+b, rest}}: pairs(rest, Con{BNode{a, b}, acc})
    case _: List.reverse(&2, Bytes, acc)

def levels(d: Nat, +xs: +List<Bytes>) -> +List<Bytes>:
  match d:
    case 0n: xs
    case 1n+k: levels(k, pairs(xs, Nil{}))

def first(xs: +List<Bytes>) -> Bytes:
  match xs:
    case Con{+t, _}: t
    case Nil{}: BLeaf{0}

def Bytes.get(+d: Nat, +t: Bytes, +i: U32) -> U32:
  match d t:
    case 0n BLeaf{+v}: v
    case 1n+k BNode{+lo, +hi}: Bytes.get(k, Bool.pick(Bytes, U32.is_eq(((i >> k) .&. 1 : U32), 1), hi, lo), i)
    case _ _: 0

type Blob is Data:
  Blob{tree: Bytes, depth: Nat, size: U32}

def Blob.depth(+count: U32) -> Nat:
  Bool.pick(Nat, (count <= 1 : U32), 0n, 1n+U32.log2((count - 1 : U32)))

def Blob.sized(+size: U32, +bytes: +List<U32>) -> Blob:
  +d = Blob.depth(size)
  Blob{first(levels(d, leaves(U32.to_nat((1 << d : U32)), bytes, Nil{}))), d, size}

def length(+xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, rest}: length(rest, (n + 1 : U32))

def Blob.new(+bytes: +List<U32>) -> Blob:
  Blob.sized(length(bytes, 0), bytes)

def Blob.size(+b: Blob) -> U32:
  Blob{_, _, size} = b
  size

# Bytes [i, i + n) lie inside the data.
def in(+b: Blob, +i: U32, +n: U32) -> Bool:
  Blob{_, _, size} = b
  (i < size : U32) && (n <= (size - i : U32) : U32)

def u8(+b: Blob, +i: U32) -> U32:
  Blob{tree, depth, _} = b
  Bytes.get(depth, tree, i)

def u16(+b: Blob, +i: U32) -> U32:
  ((u8(b, i) << 8n) .|. u8(b, (i + 1 : U32)) : U32)

def s16(+b: Blob, +i: U32) -> U32:
  sext16(u16(b, i))

def s8(+b: Blob, +i: U32) -> U32:
  sext8(u8(b, i))

def u32(+b: Blob, +i: U32) -> U32:
  ((u16(b, i) << 16n) .|. u16(b, (i + 2 : U32)) : U32)

# A value and whether every read behind it stayed inside the data.
type Got is Data:
  Got{ok: Bool, value: U32}

def Got.ok(+g: Got) -> Bool:
  Got{ok, _} = g
  ok

def Got.value(+g: Got) -> U32:
  Got{_, value} = g
  value

# -----------------------------------------------------------------------------
# stbtt__find_table (fontstart 0): the first table record with the tag; the
# tag comparison reads its bytes until the first difference.

def tag.byte(+tag: U32, +k: U32) -> U32:
  ((tag >> U32.to_nat((24 - 8 * k : U32))) .&. 255 : U32)

def tag.reads(+b: Blob, +loc: U32, +tag: U32) -> Bool:
  in(b, loc, 1) && (Bool.not(U32.is_eq(u8(b, loc), tag.byte(tag, 0))) || (in(b, (loc + 1 : U32), 1) &&
    (Bool.not(U32.is_eq(u8(b, (loc + 1 : U32)), tag.byte(tag, 1))) || (in(b, (loc + 2 : U32), 1) &&
    (Bool.not(U32.is_eq(u8(b, (loc + 2 : U32)), tag.byte(tag, 2))) || in(b, (loc + 3 : U32), 1))))))

def tag.hit(+b: Blob, +loc: U32, +tag: U32) -> Bool:
  U32.is_eq(u8(b, loc), tag.byte(tag, 0)) && U32.is_eq(u8(b, (loc + 1 : U32)), tag.byte(tag, 1)) &&
    U32.is_eq(u8(b, (loc + 2 : U32)), tag.byte(tag, 2)) && U32.is_eq(u8(b, (loc + 3 : U32)), tag.byte(tag, 3))

def find.go(n: Nat, +b: Blob, +tag: U32, +loc: U32, +ok: Bool, +found: Bool, +value: U32) -> Got:
  match n:
    case 0n: Got{ok, value}
    case 1n+k:
      +hit = Bool.not(found) && tag.hit(b, loc, tag)
      +reads = found || (tag.reads(b, loc, tag) && (Bool.not(hit) || in(b, (loc + 8 : U32), 4)))
      find.go(k, b, tag, (loc + 16 : U32), ok && reads, found || hit, Bool.pick(U32, hit, u32(b, (loc + 8 : U32)), value))

def find(+b: Blob, +tag: U32) -> Got:
  +g = find.go(U32.to_nat(u16(b, 4)), b, tag, 12, True{}, False{}, 0)
  Got{in(b, 4, 2) && Got.ok(g), Got.value(g)}

# -----------------------------------------------------------------------------
# stbtt_InitFont(info, data, 0). status: 0 InitFont returns 0, 1 initialized,
# 2 refused (a read outside the data, or a CFF font).

type Info is Data:
  Info{status: U32, loca: U32, head: U32, glyf: U32, hhea: U32, hmtx: U32, glyphs: U32, map: U32, format: U32}

def Info.status(+i: Info) -> U32:
  Info{status, _, _, _, _, _, _, _, _} = i
  status

def Info.hhea(+i: Info) -> U32:
  Info{_, _, _, _, hhea, _, _, _, _} = i
  hhea

def Info.failed(+status: U32) -> Info:
  Info{status, 0, 0, 0, 0, 0, 0, 0, 0}

# The encoding records: the last Microsoft Unicode (BMP or full) or Unicode
# platform subtable wins.
def cmap.go(n: Nat, +b: Blob, +cmap: U32, +rec: U32, +ok: Bool, +map: U32) -> Got:
  match n:
    case 0n: Got{ok, map}
    case 1n+k:
      +platform = u16(b, rec)
      +ms = U32.is_eq(platform, 3)
      +eid = u16(b, (rec + 2 : U32))
      +uni = U32.is_eq(platform, 0) || (ms && (U32.is_eq(eid, 1) || U32.is_eq(eid, 10)))
      +reads = in(b, rec, 2) && (Bool.not(ms) || in(b, (rec + 2 : U32), 2)) && (Bool.not(uni) || in(b, (rec + 4 : U32), 4))
      cmap.go(k, b, cmap, (rec + 8 : U32), ok && reads, Bool.pick(U32, uni, (cmap + u32(b, (rec + 4 : U32)) : U32), map))

def init.mapped(+b: Blob, +loca: U32, +head: U32, +glyf: U32, +hhea: U32, +hmtx: U32, +glyphs: U32, +ok: Bool, +map: Got) -> Info:
  Got{+mok, +m} = map
  +reads = ok && mok && (U32.is_eq(m, 0) || in(b, (head + 50 : U32), 2))
  Bool.pick(Info, reads, Bool.pick(Info, U32.is_eq(m, 0), Info.failed(0), Info{1, loca, head, glyf, hhea, hmtx, glyphs, m, u16(b, (head + 50 : U32))}),
    Info.failed(2))

def init.glyf(+b: Blob, +cmap: U32, +loca: U32, +head: U32, +glyf: U32, +hhea: U32, +hmtx: U32) -> Info:
  +maxp = find(b, 1835104368)
  +t = Got.value(maxp)
  +reads = Got.ok(maxp) && (U32.is_eq(t, 0) || in(b, (t + 4 : U32), 2)) && in(b, (cmap + 2 : U32), 2)
  init.mapped(b, loca, head, glyf, hhea, hmtx, Bool.pick(U32, U32.is_eq(t, 0), 65535, u16(b, (t + 4 : U32))), reads,
    cmap.go(U32.to_nat(u16(b, (cmap + 2 : U32))), b, cmap, (cmap + 4 : U32), True{}, 0))

# Without a glyf table stb_truetype reads a CFF font (not supported here).
def init.cff(+b: Blob) -> Info:
  +cff = find(b, 1128678944)
  Bool.pick(Info, Got.ok(cff), Info.failed(Bool.pick(U32, U32.is_eq(Got.value(cff), 0), 0, 2)), Info.failed(2))

def init.kind(kind: U32, +b: Blob, +cmap: U32, +loca: U32, +head: U32, +glyf: U32, +hhea: U32, +hmtx: U32) -> Info:
  match kind:
    case 0: Info.failed(0)
    case 1: init.glyf(b, cmap, loca, head, glyf, hhea, hmtx)
    case 2: init.cff(b)
    case _: Info.failed(2)

def init(+b: Blob) -> Info:
  +cmap = find(b, 1668112752)
  +loca = find(b, 1819239265)
  +head = find(b, 1751474532)
  +glyf = find(b, 1735162214)
  +hhea = find(b, 1751672161)
  +hmtx = find(b, 1752003704)
  +kern = find(b, 1801810542)
  +gpos = find(b, 1196445523)
  +reads = Got.ok(cmap) && Got.ok(loca) && Got.ok(head) && Got.ok(glyf) && Got.ok(hhea) && Got.ok(hmtx) && Got.ok(kern) && Got.ok(gpos)
  +required = Bool.not(U32.is_eq(Got.value(cmap), 0)) && Bool.not(U32.is_eq(Got.value(head), 0)) &&
    Bool.not(U32.is_eq(Got.value(hhea), 0)) && Bool.not(U32.is_eq(Got.value(hmtx), 0))
  +has_glyf = Bool.not(U32.is_eq(Got.value(glyf), 0))
  +kind = Bool.pick(U32, reads, Bool.pick(U32, required, Bool.pick(U32, has_glyf, Bool.pick(U32, U32.is_eq(Got.value(loca), 0), 0, 1), 2), 0), 3)
  init.kind(kind, b, Got.value(cmap), Got.value(loca), Got.value(head), Got.value(glyf), Got.value(hhea), Got.value(hmtx))

# -----------------------------------------------------------------------------
# Metrics

# stbtt_GetFontVMetrics: ascent, descent, lineGap.
type VMetrics is Data:
  VMetrics{ok: Bool, ascent: U32, descent: U32, line_gap: U32}

def vmetrics(+b: Blob, +info: Info) -> VMetrics:
  +h = Info.hhea(info)
  VMetrics{in(b, (h + 4 : U32), 6), s16(b, (h + 4 : U32)), s16(b, (h + 6 : U32)), s16(b, (h + 8 : U32))}

# stbtt_ScaleForPixelHeight: height / (ascent - descent).
def scale_for_pixel_height(+b: Blob, +info: Info, +height: F32) -> F32:
  +h = Info.hhea(info)
  (height / i2f((s16(b, (h + 4 : U32)) - s16(b, (h + 6 : U32)) : U32)) : F32)

# stbtt_GetGlyphHMetrics: the advance width (left side bearing not read).
def advance(+b: Blob, +info: Info, +g: U32) -> Got:
  Info{_, _, _, _, hhea, hmtx, _, _, _} = info
  +long = u16(b, (hhea + 34 : U32))
  +at = Bool.pick(U32, slt(g, long), (hmtx + 4 * g : U32), (hmtx + 4 * (long - 1) : U32))
  Got{in(b, (hhea + 34 : U32), 2) && in(b, at, 2), s16(b, at)}

# -----------------------------------------------------------------------------
# stbtt_FindGlyphIndex

def index.f0(+b: Blob, +map: U32, +cp: U32) -> Got:
  +inside = slt(cp, (u16(b, (map + 2 : U32)) - 6 : U32))
  Got{in(b, (map + 2 : U32), 2) && (Bool.not(inside) || in(b, (map + 6 + cp : U32), 1)), Bool.pick(U32, inside, u8(b, (map + 6 + cp : U32)), 0)}

def index.f6(+b: Blob, +map: U32, +cp: U32) -> Got:
  +start = u16(b, (map + 6 : U32))
  +count = u16(b, (map + 8 : U32))
  +inside = (cp >= start : U32) && (cp < (start + count : U32) : U32)
  +at = (map + 10 + (cp - start) * 2 : U32)
  Got{in(b, (map + 6 : U32), 4) && (Bool.not(inside) || in(b, at, 2)), Bool.pick(U32, inside, u16(b, at), 0)}

def f4.search(n: Nat, +b: Blob, +cp: U32, +range: U32, +search: U32, +ok: Bool) -> Got:
  match n:
    case 0n: Got{ok, search}
    case 1n+k:
      +r = (range >> 1n : U32)
      +at = (search + r * 2 : U32)
      f4.search(k, b, cp, r, Bool.pick(U32, slt(u16(b, at), cp), at, search), ok && in(b, at, 2))

def index.f4.item(+b: Blob, +map: U32, +cp: U32, +segcount: U32, +end_count: U32, +found: Got) -> Got:
  Got{+ok, +search0} = found
  +search = (search0 + 2 : U32)
  +item = (((search - end_count : U32) >> 1n) .&. 65535 : U32)
  +start_at = (map + 14 + segcount * 2 + 2 + 2 * item : U32)
  +last_at = (end_count + 2 * item : U32)
  +start = u16(b, start_at)
  +inside = Bool.not(slt(cp, start)) && Bool.not(slt(u16(b, last_at), cp))
  +offset_at = (map + 14 + segcount * 6 + 2 + 2 * item : U32)
  +offset = u16(b, offset_at)
  +delta_at = (map + 14 + segcount * 4 + 2 + 2 * item : U32)
  +glyph_at = (offset + (cp - start) * 2 + map + 14 + segcount * 6 + 2 + 2 * item : U32)
  +direct = U32.is_eq(offset, 0)
  +reads = ok && in(b, start_at, 2) && in(b, last_at, 2) && (Bool.not(inside) || (in(b, offset_at, 2) &&
    Bool.pick(Bool, direct, in(b, delta_at, 2), in(b, glyph_at, 2))))
  Got{reads, Bool.pick(U32, inside, Bool.pick(U32, direct, ((cp + s16(b, delta_at)) .&. 65535 : U32), u16(b, glyph_at)), 0)}

def index.f4(+b: Blob, +map: U32, +cp: U32) -> Got:
  +segcount = (u16(b, (map + 6 : U32)) >> 1n : U32)
  +range = (u16(b, (map + 8 : U32)) >> 1n : U32)
  +selector = u16(b, (map + 10 : U32))
  +shift = (u16(b, (map + 12 : U32)) >> 1n : U32)
  +end_count = (map + 14 : U32)
  +reads = in(b, (map + 6 : U32), 8)
  +big = slt(65535, cp)
  +first_at = (end_count + shift * 2 : U32)
  +start = (Bool.pick(U32, Bool.not(slt(cp, u16(b, first_at))), first_at, end_count) - 2 : U32)
  +item = index.f4.item(b, map, cp, segcount, end_count, f4.search(U32.to_nat(selector), b, cp, range, start, reads && in(b, first_at, 2)))
  Bool.pick(Got, big, Got{reads, 0}, item)

# Formats 12 and 13: binary search of the groups.
type Search is Data:
  Search{ok: Bool, active: Bool, low: U32, high: U32, value: U32}

def f12.step(+b: Blob, +map: U32, +cp: U32, +f13: Bool, +ok: Bool, +low: U32, +high: U32, +value: U32) -> Search:
  +running = slt(low, high)
  +mid = (low + ((high - low : U32) >> 1n) : U32)
  +fits = Bool.not(running) || (mid <= 178956970 : U32)
  +at = (map + 16 + mid * 12 : U32)
  +start = u32(b, at)
  +below = (cp < start : U32)
  +above = (cp > u32(b, (at + 4 : U32)) : U32)
  +hit = running && Bool.not(below) && Bool.not(above)
  +reads = Bool.not(running) || (in(b, at, 8) && (Bool.not(hit) || in(b, (at + 8 : U32), 4)))
  +glyph = u32(b, (at + 8 : U32))
  Search{ok && fits && reads, running && Bool.not(hit), Bool.pick(U32, running && Bool.not(below) && above, (mid + 1 : U32), low),
    Bool.pick(U32, running && below, mid, high), Bool.pick(U32, hit, Bool.pick(U32, f13, glyph, (glyph + cp - start : U32)), value)}

def f12.go(n: Nat, +b: Blob, +map: U32, +cp: U32, +f13: Bool, s: Search) -> Search:
  match n s:
    case 1n+k Search{+ok, True{}, +low, +high, +value}: f12.go(k, b, map, cp, f13, f12.step(b, map, cp, f13, ok, low, high, value))
    case _ s2: s2

def index.f12.done(s: Search) -> Got:
  Search{ok, active, _, _, value} = s
  Got{ok && Bool.not(active), value}

def index.f12(+b: Blob, +map: U32, +cp: U32, +f13: Bool) -> Got:
  index.f12.done(f12.go(40n, b, map, cp, f13, Search{in(b, (map + 12 : U32), 4), True{}, 0, u32(b, (map + 12 : U32)), 0}))

def index.format(format: U32, +b: Blob, +map: U32, +cp: U32) -> Got:
  match format:
    case 0: index.f0(b, map, cp)
    case 4: index.f4(b, map, cp)
    case 6: index.f6(b, map, cp)
    case 12: index.f12(b, map, cp, False{})
    case 13: index.f12(b, map, cp, True{})
    case _: Got{True{}, 0}

# The glyph index of a codepoint (a C int), 0 when absent.
def index(+b: Blob, +info: Info, +cp: U32) -> Got:
  Info{_, _, _, _, _, _, _, map, _} = info
  +r = index.format(u16(b, map), b, map, cp)
  Got{in(b, map, 2) && Got.ok(r), Got.value(r)}

# -----------------------------------------------------------------------------
# Glyph locations and boxes

# stbtt__GetGlyfOffset: the glyph's offset, or -1 (out of range, unknown loca
# format or empty); a negative int offset also reads as no glyph.
def glyf.offset(+b: Blob, +info: Info, +g: U32) -> Got:
  Info{_, loca, _, glyf, _, _, glyphs, _, format} = info
  +range = slt(g, glyphs) && slt(format, 2)
  +short = U32.is_eq(format, 0)
  +a = Bool.pick(U32, short, (loca + g * 2 : U32), (loca + g * 4 : U32))
  +o1 = Bool.pick(U32, short, (u16(b, a) * 2 : U32), u32(b, a))
  +o2 = Bool.pick(U32, short, (u16(b, (a + 2 : U32)) * 2 : U32), u32(b, (a + 4 : U32)))
  +g1 = (glyf + o1 : U32)
  +g2 = (glyf + o2 : U32)
  +reads = Bool.not(range) || in(b, a, Bool.pick(U32, short, 4, 8))
  +overflow = range && short && (Bool.not(add.ok(glyf, o1)) || Bool.not(add.ok(glyf, o2)))
  Got{reads && Bool.not(overflow), Bool.pick(U32, range && Bool.not(U32.is_eq(g1, g2)), g1, 4294967295)}

type Box is Data:
  Box{ok: Bool, has: Bool, x0: U32, y0: U32, x1: U32, y1: U32}

# stbtt_GetGlyphBox
def box(+b: Blob, +info: Info, +g: U32) -> Box:
  +o = glyf.offset(b, info, g)
  +at = Got.value(o)
  +has = Bool.not(neg(at))
  Box{Got.ok(o) && (Bool.not(has) || in(b, (at + 2 : U32), 8)), has, s16(b, (at + 2 : U32)), s16(b, (at + 4 : U32)),
    s16(b, (at + 6 : U32)), s16(b, (at + 8 : U32))}

# -----------------------------------------------------------------------------
# Glyph shapes: stbtt_vertex lists (kind 1 move, 2 line, 3 curve; values are
# shorts held as sign-extended words).

type Vertex is Data:
  Vertex{kind: U32, x: U32, y: U32, cx: U32, cy: U32}

type Shape is Data:
  Shape{ok: Bool, vertices: +List<Vertex>}

def Vertex.at(+kind: U32, +x: U32, +y: U32, +cx: U32, +cy: U32) -> Vertex:
  Vertex{kind, sext16(x), sext16(y), sext16(cx), sext16(cy)}

# One point of a simple glyph: flags and coordinates (shorts).
type Raw is Data:
  Raw{flags: U32, x: U32, y: U32}

type Cursor is Data:
  Cursor{ok: Bool, at: U32, values: +List<U32>}

def Cursor.ok(+c: Cursor) -> Bool:
  Cursor{ok, _, _} = c
  ok

def Cursor.at(+c: Cursor) -> U32:
  Cursor{_, at, _} = c
  at

def Cursor.values(+c: Cursor) -> +List<U32>:
  Cursor{_, _, values} = c
  values

# The flags pass: a flag byte, its repeat count when bit 3 is set.
def flags.go(n: Nat, +b: Blob, +at: U32, +count: U32, +flags: U32, +ok: Bool, +acc: +List<U32>) -> Cursor:
  match n:
    case 0n: Cursor{ok, at, List.reverse(&2, U32, acc)}
    case 1n+k:
      +fresh = U32.is_eq(count, 0)
      +f = Bool.pick(U32, fresh, u8(b, at), flags)
      +repeat = fresh && U32.is_eq((f .&. 8 : U32), 8)
      +reads = Bool.not(fresh) || (in(b, at, 1) && (Bool.not(repeat) || in(b, (at + 1 : U32), 1)))
      flags.go(k, b, (at + Bool.pick(U32, fresh, Bool.pick(U32, repeat, 2, 1), 0) : U32),
        Bool.pick(U32, fresh, Bool.pick(U32, repeat, u8(b, (at + 1 : U32)), 0), (count - 1 : U32)), f, ok && reads, Con{f, acc})

# The x (short_bit 2, same_bit 16) or y (4, 32) pass.
def coords.go(flags: +List<U32>, +b: Blob, +short_bit: U32, +same_bit: U32, +at: U32, +v: U32, +ok: Bool, +acc: +List<U32>) -> Cursor:
  match flags:
    case Nil{}: Cursor{ok, at, List.reverse(&2, U32, acc)}
    case Con{+f, rest}:
      +short = Bool.not(U32.is_eq((f .&. short_bit : U32), 0))
      +same = Bool.not(U32.is_eq((f .&. same_bit : U32), 0))
      +d = u8(b, at)
      +next = Bool.pick(U32, short, Bool.pick(U32, same, (v + d : U32), (v - d : U32)), Bool.pick(U32, same, v, (v + s16(b, at) : U32)))
      +reads = Bool.pick(Bool, short, in(b, at, 1), same || in(b, at, 2))
      coords.go(rest, b, short_bit, same_bit, (at + Bool.pick(U32, short, 1, Bool.pick(U32, same, 0, 2)) : U32), next, ok && reads, Con{sext16(next), acc})

def raws(fs: +List<U32>, +xs: +List<U32>, +ys: +List<U32>) -> +List<Raw>:
  match fs xs ys:
    case Con{+f, fr} Con{+x, xr} Con{+y, yr}: Con{Raw{f, x, y}, raws(fr, xr, yr)}
    case _ _ _: Nil{}

# The conversion pass (state of stbtt__GetGlyphShapeTT's last loop).
type Conv is Data:
  Conv{ok: Bool, i: U32, next_move: U32, j: U32, was_off: Bool, start_off: Bool, sx: U32, sy: U32, scx: U32, scy: U32, cx: U32, cy: U32, out: +List<Vertex>}

type Next is Data:
  Next{state: Conv, rest: +List<Raw>}

# stbtt__close_shape (vertices pushed on the reversed list).
def close(+was_off: Bool, +start_off: Bool, +sx: U32, +sy: U32, +scx: U32, +scy: U32, +cx: U32, +cy: U32, +out: +List<Vertex>) -> +List<Vertex>:
  +mid = Bool.pick(+List<Vertex>, was_off, Con{Vertex.at(3, asr1((cx + scx : U32)), asr1((cy + scy : U32)), cx, cy), out}, out)
  Bool.pick(+List<Vertex>, start_off, Con{Vertex.at(3, sx, sy, scx, scy), mid},
    Con{Bool.pick(Vertex, was_off, Vertex.at(3, sx, sy, cx, cy), Vertex.at(2, sx, sy, 0, 0)), out})

def Raw.flags(+r: Raw) -> U32:
  Raw{f, _, _} = r
  f

def Raw.x(+r: Raw) -> U32:
  Raw{_, x, _} = r
  x

def Raw.y(+r: Raw) -> U32:
  Raw{_, _, y} = r
  y

def head.raw(rest: +List<Raw>) -> Raw:
  match rest:
    case Con{+r, _}: r
    case Nil{}: Raw{1, 0, 0}

def tail.raw(rest: +List<Raw>) -> +List<Raw>:
  match rest:
    case Con{_, r}: r
    case Nil{}: Nil{}

def nonempty.raw(rest: +List<Raw>) -> Bool:
  match rest:
    case Con{_, _}: True{}
    case Nil{}: False{}

def conv.move(+p: Raw, +rest: +List<Raw>, +b: Blob, +end_pts: U32, +st: Conv) -> Next:
  Raw{f, x, y} = p
  Conv{ok, i, _, j, was_off, start_off, sx, sy, scx, scy, cx, cy, out} = st
  +closed = Bool.pick(+List<Vertex>, U32.is_eq(i, 0), out, close(was_off, start_off, sx, sy, scx, scy, cx, cy, out))
  +off = U32.is_eq((f .&. 1 : U32), 0)
  +nx = head.raw(rest)
  +next_off = U32.is_eq((Raw.flags(nx) .&. 1 : U32), 0)
  +skip = off && Bool.not(next_off)
  +nsx = Bool.pick(U32, off, Bool.pick(U32, next_off, asr1((x + Raw.x(nx) : U32)), Raw.x(nx)), x)
  +nsy = Bool.pick(U32, off, Bool.pick(U32, next_off, asr1((y + Raw.y(nx) : U32)), Raw.y(nx)), y)
  +at = (end_pts + j * 2 : U32)
  +reads = (Bool.not(off) || nonempty.raw(rest)) && in(b, at, 2)
  Next{Conv{ok && reads, (i + Bool.pick(U32, skip, 2, 1) : U32), (1 + u16(b, at) : U32), (j + 1 : U32), False{}, off, nsx, nsy,
    Bool.pick(U32, off, x, scx), Bool.pick(U32, off, y, scy), cx, cy, Con{Vertex.at(1, nsx, nsy, 0, 0), closed}},
    Bool.pick(+List<Raw>, skip, tail.raw(rest), rest)}

def conv.point(+p: Raw, +rest: +List<Raw>, +st: Conv) -> Next:
  Raw{f, x, y} = p
  Conv{ok, i, next_move, j, was_off, start_off, sx, sy, scx, scy, cx, cy, out} = st
  +off = U32.is_eq((f .&. 1 : U32), 0)
  +curve_mid = Bool.pick(+List<Vertex>, was_off, Con{Vertex.at(3, asr1((cx + x : U32)), asr1((cy + y : U32)), cx, cy), out}, out)
  +on = {Con{Bool.pick(Vertex, was_off, Vertex.at(3, x, y, cx, cy), Vertex.at(2, x, y, 0, 0)), out} : +List<Vertex>}
  Next{Conv{ok, (i + 1 : U32), next_move, j, off, start_off, sx, sy, scx, scy, Bool.pick(U32, off, x, cx), Bool.pick(U32, off, y, cy),
    Bool.pick(+List<Vertex>, off, curve_mid, on)}, rest}

def Conv.i(+st: Conv) -> U32:
  Conv{_, i, _, _, _, _, _, _, _, _, _, _, _} = st
  i

def Conv.next_move(+st: Conv) -> U32:
  Conv{_, _, next_move, _, _, _, _, _, _, _, _, _, _} = st
  next_move

def conv.step(+p: Raw, +rest: +List<Raw>, +b: Blob, +end_pts: U32, +st: Conv) -> Next:
  Bool.pick(Next, U32.is_eq(Conv.i(st), Conv.next_move(st)), conv.move(p, rest, b, end_pts, st), conv.point(p, rest, st))

def conv.go(n: Nat, +b: Blob, +end_pts: U32, nx: Next) -> Conv:
  match n nx:
    case 1n+k Next{+st, Con{+p, rest}}: conv.go(k, b, end_pts, conv.step(p, rest, b, end_pts, st))
    case _ Next{st, _}: st

def conv.done(+st: Conv) -> Shape:
  Conv{ok, _, _, _, was_off, start_off, sx, sy, scx, scy, cx, cy, out} = st
  Shape{ok, List.reverse(&2, Vertex, close(was_off, start_off, sx, sy, scx, scy, cx, cy, out))}

def simple.points(+b: Blob, +g: U32, +n: U32, +end_pts: U32, +ok: Bool, +fl: Cursor) -> Shape:
  +xs = coords.go(Cursor.values(fl), b, 2, 16, Cursor.at(fl), 0, Cursor.ok(fl), Nil{})
  +ys = coords.go(Cursor.values(fl), b, 4, 32, Cursor.at(xs), 0, Cursor.ok(xs), Nil{})
  +pts = raws(Cursor.values(fl), Cursor.values(xs), Cursor.values(ys))
  conv.done(conv.go(1n+U32.to_nat(n), b, end_pts, Next{Conv{ok && Cursor.ok(ys), 0, 0, 0, False{}, False{}, 0, 0, 0, 0, 0, 0, Nil{}}, pts}))

def simple(+b: Blob, +g: U32, +nc: U32) -> Shape:
  +end_pts = (g + 10 : U32)
  +ins_at = (g + 10 + nc * 2 : U32)
  +last_at = (end_pts + nc * 2 - 2 : U32)
  +points = (g + 10 + nc * 2 + 2 + u16(b, ins_at) : U32)
  +n = (1 + u16(b, last_at) : U32)
  +ok = in(b, ins_at, 2) && in(b, last_at, 2)
  simple.points(b, g, n, end_pts, ok, flags.go(U32.to_nat(n), b, points, 0, 0, ok, Nil{}))

# Composite glyphs: each component's shape, transformed to shorts.
type Matrix is Data:
  Matrix{a: F32, b: F32, c: F32, d: F32, e: F32, f: F32, m: F32, n: F32}

type Xformed is Data:
  Xformed{ok: Bool, vertices: +List<Vertex>}

def xform.one(+mx: Matrix, +x: U32, +y: U32) -> F32 & F32:
  Matrix{a, b, c, d, e, f, m, n} = mx
  +fx = i2f(x)
  +fy = i2f(y)
  (((a * fx : F32) + (c * fy : F32) + (e * m : F32) : F32), ((b * fx : F32) + (d * fy : F32) + (f * n : F32) : F32))

def xform.short(+v: F32) -> U32:
  Bool.pick(U32, f2s.valid(v), sext16(f2i(v)), 0)

def xform.vertex(+kind: U32, p: F32 & F32, q: F32 & F32) -> Xformed:
  (+x, +y) = p
  (+cx, +cy) = q
  Xformed{f2s.valid(x) && f2s.valid(y) && f2s.valid(cx) && f2s.valid(cy), [Vertex{kind, xform.short(x), xform.short(y), xform.short(cx), xform.short(cy)}]}

def xform.cat(a: Xformed, r: Xformed) -> Xformed:
  Xformed{ok, vs} = a
  Xformed{rok, rest} = r
  Xformed{ok && rok, List.append(&2, Vertex, vs, rest)}

def xform.go(vs: +List<Vertex>, +mx: Matrix) -> Xformed:
  match vs:
    case Nil{}: Xformed{True{}, Nil{}}
    case Con{+v, rest}:
      Vertex{kind, x, y, cx, cy} = v
      xform.cat(xform.vertex(kind, xform.one(mx, x, y), xform.one(mx, cx, cy)), xform.go(rest, mx))

type Comp is Data:
  Comp{ok: Bool, at: U32, more: Bool, out: +List<Vertex>}

def comp.append(+ok: Bool, +at: U32, +more: Bool, +out: +List<Vertex>, x: Xformed) -> Comp:
  Xformed{xok, vs} = x
  Comp{ok && xok, at, more, List.append(&2, Vertex, out, vs)}

def comp.apply(+ok: Bool, +at: U32, +more: Bool, +out: +List<Vertex>, +mx: Matrix, s: Shape) -> Comp:
  Shape{sok, vs} = s
  comp.append(ok && sok, at, more, out, xform.go(vs, mx))

# One component: flags, glyph, offsets (only with ARGS_ARE_XY_VALUES; the
# point-matching form leaves them 0 and its arguments unread), the scale.
def comp.step(~sub: @+b:Blob -> @+i:Info -> @+g:U32 -> Shape, +b: Blob, +info: Info, +ok: Bool, +at: U32, +out: +List<Vertex>) -> Comp:
  +flags = u16(b, at)
  +gidx = u16(b, (at + 2 : U32))
  +xy = Bool.not(U32.is_eq((flags .&. 2 : U32), 0))
  +words = Bool.not(U32.is_eq((flags .&. 1 : U32), 0))
  +p = (at + 4 : U32)
  +e = Bool.pick(F32, xy, i2f(Bool.pick(U32, words, s16(b, p), s8(b, p))), 0.0)
  +f = Bool.pick(F32, xy, i2f(Bool.pick(U32, words, s16(b, (p + 2 : U32)), s8(b, (p + 1 : U32)))), 0.0)
  +q = (p + Bool.pick(U32, xy, Bool.pick(U32, words, 4, 2), 0) : U32)
  +one = Bool.not(U32.is_eq((flags .&. 8 : U32), 0))
  +two = Bool.not(U32.is_eq((flags .&. 64 : U32), 0))
  +four = Bool.not(U32.is_eq((flags .&. 128 : U32), 0))
  +s0 = (i2f(s16(b, q)) / 16384.0 : F32)
  +s1 = (i2f(s16(b, (q + 2 : U32))) / 16384.0 : F32)
  +s2 = (i2f(s16(b, (q + 4 : U32))) / 16384.0 : F32)
  +s3 = (i2f(s16(b, (q + 6 : U32))) / 16384.0 : F32)
  +ma = Bool.pick(F32, one || two || four, s0, 1.0)
  +mb = Bool.pick(F32, Bool.not(one) && Bool.not(two) && four, s1, 0.0)
  +mc = Bool.pick(F32, Bool.not(one) && Bool.not(two) && four, s2, 0.0)
  +md = Bool.pick(F32, one, s0, Bool.pick(F32, two, s1, Bool.pick(F32, four, s3, 1.0)))
  +scale_bytes = Bool.pick(U32, one, 2, Bool.pick(U32, two, 4, Bool.pick(U32, four, 8, 0)))
  +reads = in(b, at, 4) && (Bool.not(xy) || in(b, p, Bool.pick(U32, words, 4, 2))) && (U32.is_eq(scale_bytes, 0) || in(b, q, scale_bytes))
  +m = F32.sqrt(((ma * ma : F32) + (mb * mb : F32) : F32))
  +n = F32.sqrt(((mc * mc : F32) + (md * md : F32) : F32))
  comp.apply(ok && reads, (q + scale_bytes : U32), Bool.not(U32.is_eq((flags .&. 32 : U32), 0)), out, Matrix{ma, mb, mc, md, e, f, m, n},
    Bool.pick(Shape, reads, sub(b, info, gidx), Shape{False{}, Nil{}}))

def comp.go(~sub: @+b:Blob -> @+i:Info -> @+g:U32 -> Shape, n: Nat, +b: Blob, +info: Info, c: Comp) -> Comp:
  match n c:
    case 1n+k Comp{+ok, +at, True{}, out}: comp.go(~sub, k, b, info, comp.step(~sub, b, info, ok, at, out))
    case _ c2: c2

def comp.done(c: Comp) -> Shape:
  Comp{ok, _, more, out} = c
  Shape{ok && Bool.not(more), out}

def shape.kind(~sub: @+b:Blob -> @+i:Info -> @+g:U32 -> Shape, kind: U32, +b: Blob, +info: Info, +g: U32, +nc: U32) -> Shape:
  match kind:
    case 0: Shape{True{}, Nil{}}
    case 1: simple(b, g, nc)
    case 2: comp.done(comp.go(~sub, 1n+U32.to_nat((Blob.size(b) / 4 : U32)), b, info, Comp{True{}, (g + 10 : U32), True{}, Nil{}}))
    case _: Shape{False{}, Nil{}}

# stbtt__GetGlyphShapeTT with components from `sub`.
def shape.with(~sub: @+b:Blob -> @+i:Info -> @+g:U32 -> Shape, +b: Blob, +info: Info, +g: U32) -> Shape:
  +o = glyf.offset(b, info, g)
  +at = Got.value(o)
  +nc = s16(b, at)
  +none = neg(at)
  +kind = Bool.pick(U32, Got.ok(o) && (none || in(b, at, 2)), Bool.pick(U32, none || U32.is_eq(nc, 0), 0, Bool.pick(U32, neg(nc), 2, 1)), 3)
  shape.kind(~sub, kind, b, info, at, nc)

def shape.deep(+b: Blob, +info: Info, +g: U32) -> Shape:
  Shape{False{}, Nil{}}

def shape.1(+b: Blob, +info: Info, +g: U32) -> Shape:
  shape.with(~shape.deep, b, info, g)

def shape.2(+b: Blob, +info: Info, +g: U32) -> Shape:
  shape.with(~shape.1, b, info, g)

def shape.3(+b: Blob, +info: Info, +g: U32) -> Shape:
  shape.with(~shape.2, b, info, g)

def shape.4(+b: Blob, +info: Info, +g: U32) -> Shape:
  shape.with(~shape.3, b, info, g)

def shape.5(+b: Blob, +info: Info, +g: U32) -> Shape:
  shape.with(~shape.4, b, info, g)

# stbtt_GetGlyphShape (composites nest at most 6 deep here).
def shape(+b: Blob, +info: Info, +g: U32) -> Shape:
  shape.with(~shape.5, b, info, g)

# -----------------------------------------------------------------------------
# stbtt_FlattenCurves: contours of points.

type Point is Data:
  Point{x: F32, y: F32}

def tess.split(+x0: F32, +y0: F32, +x1: F32, +y1: F32, +x2: F32, +y2: F32, +fsq: F32) -> Bool:
  +mx = ((x0 + (2.0 * x1 : F32) + x2 : F32) / 4.0 : F32)
  +my = ((y0 + (2.0 * y1 : F32) + y2 : F32) / 4.0 : F32)
  +dx = (((x0 + x2 : F32) / 2.0 : F32) - mx : F32)
  +dy = (((y0 + y2 : F32) / 2.0 : F32) - my : F32)
  ((dx * dx : F32) + (dy * dy : F32) > fsq : F32)

# stbtt__tesselate_curve: f is 17 - n (nothing is added past n = 16).
def tess(+f: Nat, split: Bool, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +x2: F32, +y2: F32, +fsq: F32, +acc: +List<Point>) -> +List<Point>:
  match f split:
    case 0n _: acc
    case 1n+k True{}:
      +mx = ((x0 + (2.0 * x1 : F32) + x2 : F32) / 4.0 : F32)
      +my = ((y0 + (2.0 * y1 : F32) + y2 : F32) / 4.0 : F32)
      +ax = ((x0 + x1 : F32) / 2.0 : F32)
      +ay = ((y0 + y1 : F32) / 2.0 : F32)
      +bx = ((x1 + x2 : F32) / 2.0 : F32)
      +by = ((y1 + y2 : F32) / 2.0 : F32)
      tess(k, tess.split(mx, my, bx, by, x2, y2, fsq), mx, my, bx, by, x2, y2, fsq,
        tess(k, tess.split(x0, y0, ax, ay, mx, my, fsq), x0, y0, ax, ay, mx, my, fsq, acc))
    case 1n+_ False{}: Con{Point{x2, y2}, acc}

type Flat is Data:
  Flat{ok: Bool, started: Bool, x: F32, y: F32, current: +List<Point>, contours: +List<+List<Point>>}

def flat.close(+started: Bool, +current: +List<Point>, +contours: +List<+List<Point>>) -> +List<+List<Point>>:
  Bool.pick(+List<+List<Point>>, started, Con{List.reverse(&2, Point, current), contours}, contours)

def flat.step(+v: Vertex, +fsq: F32, +st: Flat) -> Flat:
  Vertex{kind, vx, vy, cx, cy} = v
  Flat{ok, started, x, y, current, contours} = st
  +px = i2f(vx)
  +py = i2f(vy)
  +move = U32.is_eq(kind, 1)
  +curve = U32.is_eq(kind, 3)
  +line = U32.is_eq(kind, 2)
  +fcx = i2f(cx)
  +fcy = i2f(cy)
  +added = Bool.pick(+List<Point>, curve, tess(17n, tess.split(x, y, fcx, fcy, px, py, fsq), x, y, fcx, fcy, px, py, fsq, current),
    Bool.pick(+List<Point>, line, Con{Point{px, py}, current}, current))
  Flat{ok && (started || move), started || move, px, py, Bool.pick(+List<Point>, move, [Point{px, py}], added),
    Bool.pick(+List<+List<Point>>, move, flat.close(started, current, contours), contours)}

def flat.go(vs: +List<Vertex>, +fsq: F32, st: Flat) -> Flat:
  match vs:
    case Nil{}: st
    case Con{+v, rest}: flat.go(rest, fsq, flat.step(v, fsq, st))

type Contours is Data:
  Contours{ok: Bool, any: Bool, list: +List<+List<Point>>}

def flat.done(st: Flat) -> Contours:
  Flat{ok, +started, _, _, current, contours} = st
  Contours{ok, started, List.reverse(&2, +List<Point>, flat.close(started, current, contours))}

def flatten(vs: +List<Vertex>, +flatness: F32) -> Contours:
  flat.done(flat.go(vs, (flatness * flatness : F32), Flat{True{}, False{}, 0.0, 0.0, Nil{}, Nil{}}))

# -----------------------------------------------------------------------------
# Edges and their sort (stbtt__sort_edges: quicksort to runs of 12, then an
# insertion sort, by y0).

type Edge is Data:
  Edge{x0: F32, y0: F32, x1: F32, y1: F32, invert: Bool}

def Edge.y0(+e: Edge) -> F32:
  Edge{_, y0, _, _, _} = e
  y0

def edge.make(+p: Point, +q: Point, +sx: F32, +sy: F32, +acc: +List<Edge>) -> +List<Edge>:
  Point{jx, jy} = p
  Point{kx, ky} = q
  +inv = (jy > ky : F32)
  +ax = Bool.pick(F32, inv, jx, kx)
  +ay = Bool.pick(F32, inv, jy, ky)
  +bx = Bool.pick(F32, inv, kx, jx)
  +by = Bool.pick(F32, inv, ky, jy)
  Bool.pick(+List<Edge>, F32.is_eq(jy, ky), acc,
    Con{Edge{((ax * sx : F32) + 0.0 : F32), ((ay * F32.neg(sy) : F32) + 0.0 : F32), ((bx * sx : F32) + 0.0 : F32), ((by * F32.neg(sy) : F32) + 0.0 : F32), inv}, acc})

def edges.contour(pts: +List<Point>, +prev: Point, +sx: F32, +sy: F32, +acc: +List<Edge>) -> +List<Edge>:
  match pts:
    case Nil{}: acc
    case Con{+p, rest}: edges.contour(rest, p, sx, sy, edge.make(prev, p, sx, sy, acc))

def last.point(pts: +List<Point>, +d: Point) -> Point:
  match pts:
    case Nil{}: d
    case Con{+p, rest}: last.point(rest, p)

def edges.go(cs: +List<+List<Point>>, +sx: F32, +sy: F32, +acc: +List<Edge>) -> +List<Edge>:
  match cs:
    case Nil{}: List.reverse(&2, Edge, acc)
    case Con{+c, rest}: edges.go(rest, sx, sy, edges.contour(c, last.point(c, Point{0.0, 0.0}), sx, sy, acc))

def fill.array(es: +List<Edge>, +i: U32, a: Array<Edge>) -> Array<Edge>:
  match es:
    case Nil{}: a
    case Con{+e, rest}: fill.array(rest, (i + 1 : U32), Array.set(Edge, a, i, e))

def edge.zero() -> Edge:
  Edge{0.0, 0.0, 0.0, 0.0, False{}}

def read.edge(a: Array<Edge>, +i: U32) -> Array<Edge> & Edge:
  Array.get(Edge, a, i)

def swap.set(+j: U32, +x: Edge, +i: U32, r: Array<Edge> & Edge) -> Array<Edge>:
  (a, +y) = r
  Array.set(Edge, Array.set(Edge, a, i, y), j, x)

# Swap entries i and j.
def swap.first(+i: U32, +j: U32, r: Array<Edge> & Edge) -> Array<Edge>:
  (a, +x) = r
  swap.set(j, x, i, Array.get(Edge, a, j))

def swap(a: Array<Edge>, +i: U32, +j: U32) -> Array<Edge>:
  swap.first(i, j, Array.get(Edge, a, i))

# The quicksort as a machine: a stack of (offset, count) ranges (independent,
# so their order does not matter) and the partition of the current one.
# phase 0 pick a range, 1 scan i, 2 scan j, 3 swap or split.
type QS is Type:
  QS{a: Array<Edge>, stack: +List<U32>, phase: U32, lo: U32, n: U32, i: U32, j: U32, pivot: F32, done: Bool}

def lt3(+x: Edge, +y: Edge) -> Bool:
  (Edge.y0(x) < Edge.y0(y) : F32)

def qs.median.swap(same: Bool, +lo: U32, +z: U32, +m: U32, a: Array<Edge>) -> Array<Edge>:
  match same:
    case True{}: swap(a, lo, (lo + m : U32))
    case False{}: swap(swap(a, (lo + z : U32), (lo + m : U32)), lo, (lo + m : U32))

# The median of three into position m, then into position 0 (stb's order).
def qs.median.c(+lo: U32, +n: U32, +p0: Edge, +pm: Edge, r: Array<Edge> & Edge) -> Array<Edge>:
  (a, +pn) = r
  +m = (n >> 1n : U32)
  +c01 = lt3(p0, pm)
  +c12 = lt3(pm, pn)
  +c = lt3(p0, pn)
  +z = Bool.pick(U32, U32.is_eq(Bool.to_u32(c), Bool.to_u32(c12)), 0, (n - 1 : U32))
  qs.median.swap(U32.is_eq(Bool.to_u32(c01), Bool.to_u32(c12)), lo, z, m, a)

def qs.median.b(+lo: U32, +n: U32, +p0: Edge, r: Array<Edge> & Edge) -> Array<Edge>:
  (a, +pm) = r
  qs.median.c(lo, n, p0, pm, Array.get(Edge, a, (lo + n - 1 : U32)))

def qs.median.a(+lo: U32, +n: U32, r: Array<Edge> & Edge) -> Array<Edge>:
  (a, +p0) = r
  qs.median.b(lo, n, p0, Array.get(Edge, a, (lo + (n >> 1n) : U32)))

def qs.pivot(+lo: U32, +n: U32, +stack: +List<U32>, r: Array<Edge> & Edge) -> QS:
  (a, +p) = r
  QS{a, stack, 1, lo, n, 1, (n - 1 : U32), Edge.y0(p), False{}}

def qs.start(+lo: U32, +n: U32, +stack: +List<U32>, a: Array<Edge>) -> QS:
  qs.pivot(lo, n, stack, Array.get(Edge, qs.median.a(lo, n, Array.get(Edge, a, lo)), lo))

def qs.pick.big(big: Bool, +lo: U32, +n: U32, +stack: +List<U32>, a: Array<Edge>) -> QS:
  match big:
    case True{}: qs.start(lo, n, stack, a)
    case False{}: QS{a, stack, 0, 0, 0, 0, 0, 0.0, False{}}

def qs.pick(stack: +List<U32>, a: Array<Edge>) -> QS:
  match stack:
    case Con{+lo, Con{+n, rest}}: qs.pick.big((n > 12 : U32), lo, n, rest, a)
    case _: QS{a, Nil{}, 0, 0, 0, 0, 0, 0.0, True{}}

def qs.scan_i(+stack: +List<U32>, +lo: U32, +n: U32, +i: U32, +j: U32, +pivot: F32, r: Array<Edge> & Edge) -> QS:
  (a, +e) = r
  +less = (Edge.y0(e) < pivot : F32)
  QS{a, stack, Bool.pick(U32, less, 1, 2), lo, n, Bool.pick(U32, less, (i + 1 : U32), i), j, pivot, False{}}

def qs.scan_j(+stack: +List<U32>, +lo: U32, +n: U32, +i: U32, +j: U32, +pivot: F32, r: Array<Edge> & Edge) -> QS:
  (a, +e) = r
  +more = (pivot < Edge.y0(e) : F32)
  QS{a, stack, Bool.pick(U32, more, 2, 3), lo, n, i, Bool.pick(U32, more, (j - 1 : U32), j), pivot, False{}}

def qs.split(crossed: Bool, +stack: +List<U32>, +lo: U32, +n: U32, +i: U32, +j: U32, +pivot: F32, a: Array<Edge>) -> QS:
  match crossed:
    case True{}: QS{a, Con{lo, Con{j, Con{(lo + i : U32), Con{(n - i : U32), stack}}}}, 0, 0, 0, 0, 0, 0.0, False{}}
    case False{}: QS{swap(a, (lo + i : U32), (lo + j : U32)), stack, 1, lo, n, (i + 1 : U32), (j - 1 : U32), pivot, False{}}

def qs.step(phase: U32, a: Array<Edge>, +stack: +List<U32>, +lo: U32, +n: U32, +i: U32, +j: U32, +pivot: F32) -> QS:
  match phase:
    case 0: qs.pick(stack, a)
    case 1: qs.scan_i(stack, lo, n, i, j, pivot, Array.get(Edge, a, (lo + i : U32)))
    case 2: qs.scan_j(stack, lo, n, i, j, pivot, Array.get(Edge, a, (lo + j : U32)))
    case _: qs.split(Bool.not(slt(i, j)), stack, lo, n, i, j, pivot, a)

def qs.go(f: Nat, s: QS) -> QS:
  match f s:
    case 1n+k QS{a, +stack, +phase, +lo, +n, +i, +j, +pivot, False{}}: qs.go(k, qs.step(phase, a, stack, lo, n, i, j, pivot))
    case _ s2: s2

def QS.array(s: QS) -> Array<Edge>:
  QS{a, _, _, _, _, _, _, _, _} = s
  a

# The insertion sort: t = p[i] moves down while t.y0 < p[j-1].y0.
type IS is Type:
  IS{a: Array<Edge>, i: U32, j: U32, t: Edge, phase: U32, done: Bool}

def is.load(+n: U32, +i: U32, r: Array<Edge> & Edge) -> IS:
  (a, +t) = r
  IS{a, i, i, t, 1, False{}}

def is.next.go(more: Bool, +n: U32, +i: U32, a: Array<Edge>) -> IS:
  match more:
    case True{}: is.load(n, i, Array.get(Edge, a, i))
    case False{}: IS{a, i, i, edge.zero(), 0, True{}}

def is.next(+n: U32, +i: U32, a: Array<Edge>) -> IS:
  is.next.go((i < n : U32), n, i, a)

# p[j] = t (when i == j, t is already there).
def is.place(+n: U32, +i: U32, +j: U32, +t: Edge, a: Array<Edge>) -> IS:
  is.next(n, (i + 1 : U32), Array.set(Edge, a, j, t))

def is.compare.go(less: Bool, +n: U32, +i: U32, +j: U32, +t: Edge, +b: Edge, a: Array<Edge>) -> IS:
  match less:
    case True{}: IS{Array.set(Edge, a, j, b), i, (j - 1 : U32), t, 1, False{}}
    case False{}: is.place(n, i, j, t, a)

def is.compare(+n: U32, +i: U32, +j: U32, +t: Edge, r: Array<Edge> & Edge) -> IS:
  (a, +b) = r
  is.compare.go(lt3(t, b), n, i, j, t, b, a)

def is.step.go(bottom: Bool, +n: U32, a: Array<Edge>, +i: U32, +j: U32, +t: Edge) -> IS:
  match bottom:
    case True{}: is.place(n, i, j, t, a)
    case False{}: is.compare(n, i, j, t, Array.get(Edge, a, (j - 1 : U32)))

def is.step(+n: U32, a: Array<Edge>, +i: U32, +j: U32, +t: Edge) -> IS:
  is.step.go(U32.is_eq(j, 0), n, a, i, j, t)

def is.go(f: Nat, +n: U32, s: IS) -> IS:
  match f s:
    case 1n+k IS{a, +i, +j, +t, _, False{}}: is.go(k, n, is.step(n, a, i, j, t))
    case _ s2: s2

def IS.array(s: IS) -> Array<Edge>:
  IS{a, _, _, _, _, _} = s
  a

def to_list.edges(n: Nat, +i: U32, r: Array<Edge> & Edge, +acc: +List<Edge>) -> +List<Edge>:
  match n r:
    case 0n _: List.reverse(&2, Edge, acc)
    case 1n+k Tuple{a, +e}: to_list.edges(k, (i + 1 : U32), Array.get(Edge, a, (i + 1 : U32)), Con{e, acc})

def sort.edges(es: +List<Edge>, +n: U32) -> +List<Edge>:
  +d = Blob.depth((n + 1 : U32))
  qs = QS.array(qs.go(U32.to_nat((n * n + 8 * n + 8 : U32)), QS{fill.array(es, 0, Array.new(Edge, d, edge.zero())), [0, n], 0, 0, 0, 0, 0, 0.0, False{}}))
  to_list.edges(U32.to_nat(n), 0, Array.get(Edge, IS.array(is.go(U32.to_nat((n * n + 4 * n + 4 : U32)), n, is.next(n, 1, qs))), 0), Nil{})

# -----------------------------------------------------------------------------
# The version-2 rasterizer (stbtt__rasterize_sorted_edges).

# stbtt__active_edge: fx, fdx, fdy, direction, sy, ey.
type Active is Data:
  Active{fx: F32, fdx: F32, fdy: F32, dir: F32, sy: F32, ey: F32}

# stbtt__new_active at start_point (the scanline top), off_x subtracted.
def active.new(+e: Edge, +off_x: U32, +start: F32, +clamp: Bool) -> Active:
  Edge{x0, y0, x1, y1, inv} = e
  +dxdy = ((x1 - x0 : F32) / (y1 - y0 : F32) : F32)
  +fx = ((x0 + (dxdy * (start - y0 : F32) : F32) : F32) - i2f(off_x) : F32)
  Active{fx, dxdy, Bool.pick(F32, F32.is_ne(dxdy, 0.0), (1.0 / dxdy : F32), 0.0), Bool.pick(F32, inv, 1.0, F32.neg(1.0)), y0,
    Bool.pick(F32, clamp && (y1 < start : F32), start, y1)}

def Active.ey(+z: Active) -> F32:
  Active{_, _, _, _, _, ey} = z
  ey

# Active edges ending at or above the scanline top are removed.
def active.keep(+zs: +List<Active>, +top: F32) -> +List<Active>:
  match zs:
    case Nil{}: Nil{}
    case Con{+z, rest}:
      +r = active.keep(rest, top)
      Bool.pick(+List<Active>, (Active.ey(z) <= top : F32), r, Con{z, r})

# Edges starting before the scanline bottom (a prefix of the sorted edges)
# are inserted at the front, in order; horizontal ones are skipped.
def active.insert(+es: +List<Edge>, +bottom: F32, +top: F32, +off_x: U32, +clamp: Bool, +acc: +List<Active>) -> +List<Active>:
  match es:
    case Nil{}: acc
    case Con{+e, rest}:
      Edge{_, y0, _, y1, _} = e
      +take = (y0 <= bottom : F32)
      active.insert(rest, bottom, top, off_x, clamp, Bool.pick(+List<Active>, take && F32.is_ne(y0, y1), Con{active.new(e, off_x, top, clamp), acc}, acc))

def edges.after(+es: +List<Edge>, +bottom: F32) -> +List<Edge>:
  match es:
    case Nil{}: Nil{}
    case Con{+e, rest}:
      +r = edges.after(rest, bottom)
      Bool.pick(+List<Edge>, (Edge.y0(e) <= bottom : F32), r, Con{e, r})

def active.advance(+zs: +List<Active>) -> +List<Active>:
  match zs:
    case Nil{}: Nil{}
    case Con{+z, rest}:
      Active{fx, fdx, fdy, dir, sy, ey} = z
      Con{Active{(fx + fdx : F32), fdx, fdy, dir, sy, ey}, active.advance(rest)}

# scanline[i] += v
def add.at.go(+v: F32, +i: U32, r: Array<F32> & F32) -> Array<F32>:
  (a, +old) = r
  Array.set(F32, a, i, (old + v : F32))

def add.at(a: Array<F32>, +i: U32, +v: F32) -> Array<F32>:
  add.at.go(v, i, Array.get(F32, a, i))

def clip.put(skip: Bool, +x: U32, +v: F32, line: Array<F32>) -> Array<F32>:
  match skip:
    case True{}: line
    case False{}: add.at(line, x, v)

# stbtt__handle_clipped_edge into scanline[x].
def clip.add(+x: U32, +dir: F32, +sy: F32, +ey: F32, +x0: F32, +y0: F32, +x1: F32, +y1: F32, line: Array<F32>) -> Array<F32>:
  +top = (y0 < sy : F32)
  +xa = Bool.pick(F32, top, (x0 + (((x1 - x0 : F32) * (sy - y0 : F32) : F32) / (y1 - y0 : F32) : F32) : F32), x0)
  +ya = Bool.pick(F32, top, sy, y0)
  +bottom = (y1 > ey : F32)
  +xb = Bool.pick(F32, bottom, (x1 + (((x1 - xa : F32) * (ey - y1 : F32) : F32) / (y1 - ya : F32) : F32) : F32), x1)
  +yb = Bool.pick(F32, bottom, ey, y1)
  +fx = i2f(x)
  +fx1 = i2f((x + 1 : U32))
  +left = (xa <= fx : F32) && (xb <= fx : F32)
  +right = (xa >= fx1 : F32) && (xb >= fx1 : F32)
  +height = (dir * (yb - ya : F32) : F32)
  clip.put(right, x, Bool.pick(F32, left, height, (height * (1.0 - (((xa - fx : F32) + (xb - fx : F32) : F32) / 2.0 : F32) : F32) : F32)), line)

def clip.go(skip: Bool, +x: U32, +dir: F32, +sy: F32, +ey: F32, +x0: F32, +y0: F32, +x1: F32, +y1: F32, line: Array<F32>) -> Array<F32>:
  match skip:
    case True{}: line
    case False{}: clip.add(x, dir, sy, ey, x0, y0, x1, y1, line)

def clip(+x: U32, +z: Active, +x0: F32, +y0: F32, +x1: F32, +y1: F32, line: Array<F32>) -> Array<F32>:
  Active{_, _, _, dir, sy, ey} = z
  clip.go(F32.is_eq(y0, y1) || (y0 > ey : F32) || (y1 < sy : F32), x, dir, sy, ey, x0, y0, x1, y1, line)

type Lines is Type:
  Lines{a: Array<F32>, b: Array<F32>}

def fill.vertical.go(kind: U32, +z: Active, +x0: F32, +top: F32, +bottom: F32, a: Array<F32>, b: Array<F32>) -> Lines:
  match kind:
    case 1: Lines{clip(f2i(x0), z, x0, top, x0, bottom, a), clip((f2i(x0) + 1 : U32), z, x0, top, x0, bottom, b)}
    case 2: Lines{a, clip(0, z, x0, top, x0, bottom, b)}
    case _: Lines{a, b}

# An edge with fdx == 0: x0 < 0 adds only to scanline_fill[-1] (b[0]).
def fill.vertical(kind: U32, +z: Active, +x0: F32, +top: F32, +bottom: F32, lines: Lines) -> Lines:
  Lines{a, b} = lines
  fill.vertical.go(kind, z, x0, top, bottom, a, b)

# The middle pixels of a span: scanline[x] += area + step/2; area += step.
def span.go(n: Nat, +x: U32, +area: F32, +step: F32, a: Array<F32>) -> Array<F32> & F32:
  match n:
    case 0n: (a, area)
    case 1n+k: span.go(k, (x + 1 : U32), (area + step : F32), step, add.at(a, x, (area + (step / 2.0 : F32) : F32)))

def span.last(+x2: U32, +sign: F32, +sy0: F32, +sy1: F32, +y_final: F32, +x_bottom: F32, b: Array<F32>, r: Array<F32> & F32) -> Lines:
  (a, +area) = r
  +right = (i2f(x2) + 1.0 : F32)
  +trap = ((((right - i2f(x2) : F32) + (right - x_bottom : F32) : F32) / 2.0 : F32) * (sy1 - y_final : F32) : F32)
  Lines{add.at(a, x2, (area + (sign * trap : F32) : F32)), add.at(b, (x2 + 1 : U32), (sign * (sy1 - sy0 : F32) : F32))}

# Two or more pixels (after the vertical flip when x_top > x_bottom).
def span(+z: Active, +top: F32, +bottom: F32, +x0: F32, +dy0: F32, +x_top: F32, +x_bottom: F32, +sy0: F32, +sy1: F32, a: Array<F32>, b: Array<F32>) -> Lines:
  Active{_, _, _, sign, _, _} = z
  +x1 = f2i(x_top)
  +x2 = f2i(x_bottom)
  +crossing0 = (top + (dy0 * (i2f((x1 + 1 : U32)) - x0 : F32) : F32) : F32)
  +y_crossing = Bool.pick(F32, (crossing0 > bottom : F32), bottom, crossing0)
  +final0 = (top + (dy0 * (i2f(x2) - x0 : F32) : F32) : F32)
  +blown = (final0 > bottom : F32)
  +y_final = Bool.pick(F32, blown, bottom, final0)
  +dy = Bool.pick(F32, blown, ((y_final - y_crossing : F32) / i2f((x2 - (x1 + 1) : U32)) : F32), dy0)
  +area = (sign * (y_crossing - sy0 : F32) : F32)
  +step = ((sign * dy : F32) * 1.0 : F32)
  span.last(x2, sign, sy0, sy1, y_final, x_bottom, b,
    span.go(U32.to_nat((x2 - x1 - 1 : U32)), (x1 + 1 : U32), area, step, add.at(a, x1, (((area * (i2f((x1 + 1 : U32)) - x_top : F32)) : F32) / 2.0 : F32))))

# One pixel: the trapezoid in scanline[x], the height in scanline_fill[x].
def single(+z: Active, +x_top: F32, +x_bottom: F32, +sy0: F32, +sy1: F32, a: Array<F32>, b: Array<F32>) -> Lines:
  Active{_, _, _, dir, _, _} = z
  +x = f2i(x_top)
  +height = ((sy1 - sy0 : F32) * dir : F32)
  +right = (i2f(x) + 1.0 : F32)
  Lines{add.at(a, x, ((((right - x_top : F32) + (right - x_bottom : F32) : F32) / 2.0 : F32) * height : F32)), add.at(b, (x + 1 : U32), height)}

# The brute-force clipping of an edge leaving the bitmap: per pixel x, up
# to three segments split at x and x + 1.
def brute.case(kind: U32, +x: U32, +z: Active, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +x2: F32, +y2: F32, +x3: F32, +y3: F32, a: Array<F32>) -> Array<F32>:
  match kind:
    case 0: clip(x, z, x2, y2, x3, y3, clip(x, z, x1, y1, x2, y2, clip(x, z, x0, y0, x1, y1, a)))
    case 1: clip(x, z, x1, y1, x3, y3, clip(x, z, x2, y2, x1, y1, clip(x, z, x0, y0, x2, y2, a)))
    case 2: clip(x, z, x1, y1, x3, y3, clip(x, z, x0, y0, x1, y1, a))
    case 3: clip(x, z, x2, y2, x3, y3, clip(x, z, x0, y0, x2, y2, a))
    case _: clip(x, z, x0, y0, x3, y3, a)

def brute.go(n: Nat, +x: U32, +z: Active, +x0: F32, +dx: F32, +xb: F32, +top: F32, +bottom: F32, a: Array<F32>) -> Array<F32>:
  match n:
    case 0n: a
    case 1n+k:
      +x1 = i2f(x)
      +x2 = i2f((x + 1 : U32))
      +y1 = (((x1 - x0 : F32) / dx : F32) + top : F32)
      +y2 = (((x2 - x0 : F32) / dx : F32) + top : F32)
      +kind = Bool.pick(U32, (x0 < x1 : F32) && (xb > x2 : F32), 0, Bool.pick(U32, (xb < x1 : F32) && (x0 > x2 : F32), 1,
        Bool.pick(U32, (x0 < x1 : F32) && (xb > x1 : F32), 2, Bool.pick(U32, (xb < x1 : F32) && (x0 > x1 : F32), 2,
        Bool.pick(U32, (x0 < x2 : F32) && (xb > x2 : F32), 3, Bool.pick(U32, (xb < x2 : F32) && (x0 > x2 : F32), 3, 4))))))
      brute.go(k, (x + 1 : U32), z, x0, dx, xb, top, bottom, brute.case(kind, x, z, x0, top, x1, y1, x2, y2, xb, bottom, a))

def fill.sloped.go(kind: U32, +z: Active, +len: U32, +top: F32, +bottom: F32, +x0: F32, +dx: F32, +dy: F32, +xb: F32, +x_top: F32, +x_bottom: F32, +sy0: F32, +sy1: F32, a: Array<F32>, b: Array<F32>) -> Lines:
  match kind:
    case 0: single(z, x_top, x_bottom, sy0, sy1, a, b)
    case 1: span(z, top, bottom, x0, dy, x_top, x_bottom, sy0, sy1, a, b)
    case 2: span(z, top, bottom, xb, F32.neg(dy), x_bottom, x_top, (bottom - (sy1 - top : F32) : F32), (bottom - (sy0 - top : F32) : F32), a, b)
    case _: Lines{brute.go(U32.to_nat(len), 0, z, x0, dx, xb, top, bottom, a), b}

def fill.sloped(+z: Active, +len: U32, +top: F32, lines: Lines) -> Lines:
  Active{x0, dx, dy, _, sy, ey} = z
  Lines{a, b} = lines
  +bottom = (top + 1.0 : F32)
  +xb = (x0 + dx : F32)
  +x_top = Bool.pick(F32, (sy > top : F32), (x0 + (dx * (sy - top : F32) : F32) : F32), x0)
  +sy0 = Bool.pick(F32, (sy > top : F32), sy, top)
  +x_bottom = Bool.pick(F32, (ey < bottom : F32), (x0 + (dx * (ey - top : F32) : F32) : F32), xb)
  +sy1 = Bool.pick(F32, (ey < bottom : F32), ey, bottom)
  +flen = U32.to_f32(len)
  +inside = (x_top >= 0.0 : F32) && (x_bottom >= 0.0 : F32) && (x_top < flen : F32) && (x_bottom < flen : F32)
  +one = inside && U32.is_eq(f2i(Bool.pick(F32, inside, x_top, 0.0)), f2i(Bool.pick(F32, inside, x_bottom, 0.0)))
  +kind = Bool.pick(U32, inside, Bool.pick(U32, one, 0, Bool.pick(U32, (x_top > x_bottom : F32), 2, 1)), 3)
  fill.sloped.go(kind, z, len, top, bottom, x0, dx, dy, xb, x_top, x_bottom, sy0, sy1, a, b)

def fill.edge.go(vertical: Bool, +z: Active, +len: U32, +top: F32, lines: Lines) -> Lines:
  match vertical:
    case True{}:
      Active{x0, _, _, _, _, _} = z
      +kind = Bool.pick(U32, (x0 < U32.to_f32(len) : F32), Bool.pick(U32, (x0 >= 0.0 : F32), 1, 2), 0)
      fill.vertical(kind, z, x0, top, (top + 1.0 : F32), lines)
    case False{}: fill.sloped(z, len, top, lines)

def Active.fdx(+z: Active) -> F32:
  Active{_, fdx, _, _, _, _} = z
  fdx

# stbtt__fill_active_edges_new over the active list, in order.
def fill.go(+zs: +List<Active>, +len: U32, +top: F32, lines: Lines) -> Lines:
  match zs:
    case Nil{}: lines
    case Con{+z, rest}: fill.go(rest, len, top, fill.edge.go(F32.is_eq(Active.fdx(z), 0.0), z, len, top, lines))

# The scanline's pixels: sum += scanline2[i]; k = |scanline[i] + sum|*255 + 0.5.
type Row is Data:
  Row{ok: Bool, out: +List<U32>}

def row.go(n: Nat, +sum: F32, as: List<F32>, bs: List<F32>, +ok: Bool, +out: +List<U32>) -> Row:
  match n as bs:
    case 1n+k Con{+a, ar} Con{+b, br}:
      +s = (sum + b : F32)
      +v = ((F32.abs((a + s : F32)) * 255.0 : F32) + 0.5 : F32)
      +m = f2i(Bool.pick(F32, f2i.valid(v), v, 0.0))
      row.go(k, s, ar, br, ok && f2i.valid(v), Con{Bool.pick(U32, (m > 255 : U32), 255, m), out})
    case _ _ _: Row{ok, out}

def row(+w: U32, +ok: Bool, +out: +List<U32>, lines: Lines) -> Row:
  Lines{a, b} = lines
  row.go(U32.to_nat(w), 0.0, Array.to_list(~F32, a), Array.to_list(~F32, b), ok, out)

type Raster is Data:
  Raster{ok: Bool, pixels: +List<U32>}

def nonempty.active(+zs: +List<Active>) -> Bool:
  match zs:
    case Nil{}: False{}
    case Con{_, _}: True{}

def scan.row(+w: U32, +top: F32, +zs: +List<Active>, +ok: Bool, +out: +List<U32>) -> Row:
  +wd = Blob.depth(w)
  +bd = Blob.depth((w + 1 : U32))
  row(w, ok, out, fill.go(zs, w, top, Lines{Array.new(F32, wd, 0.0), Array.new(F32, bd, 0.0)}))

# One scanline per row: remove finished edges, insert new ones, fill,
# accumulate, advance.
def scan.go(n: Nat, +j: U32, +w: U32, +off_x: U32, +off_y: U32, +zs: +List<Active>, +es: +List<Edge>, r: Row) -> Raster:
  match n r:
    case 0n Row{ok, out}: Raster{ok, List.reverse(&2, U32, out)}
    case 1n+k Row{+ok, +out}:
      +top = (i2f((off_y + j : U32)) + 0.0 : F32)
      +bottom = (i2f((off_y + j : U32)) + 1.0 : F32)
      +clamp = U32.is_eq(j, 0) && Bool.not(U32.is_eq(off_y, 0))
      +live = active.insert(es, bottom, top, off_x, clamp, active.keep(zs, top))
      scan.go(k, (j + 1 : U32), w, off_x, off_y, active.advance(live), edges.after(es, bottom), scan.row(w, top, live, ok, out))

# -----------------------------------------------------------------------------
# stbtt_GetGlyphBitmapSubpixel(info, s, s, 0, 0, glyph) as stbtt_GetCodepointBitmap
# uses it. status: 0 NULL before the outputs are written (scale 0), 1 NULL
# with the outputs written (an empty box, or a negative w*h, which malloc
# refuses), 2 a bitmap, 3 refused.

type Bitmap is Data:
  Bitmap{status: U32, w: U32, h: U32, xoff: U32, yoff: U32, pixels: +List<U32>}

def ifloor.ok(+x: F32) -> Bool:
  f2i.valid(F32.floor(x))

def ifloor(+x: F32) -> U32:
  f2i(Bool.pick(F32, ifloor.ok(x), F32.floor(x), 0.0))

def iceil.ok(+x: F32) -> Bool:
  f2i.valid(F32.ceil(x))

def iceil(+x: F32) -> U32:
  f2i(Bool.pick(F32, iceil.ok(x), F32.ceil(x), 0.0))

# The integral box (stbtt_GetGlyphBitmapBoxSubpixel, shift 0): x0, y0, x1, y1.
type IBox is Data:
  IBox{ok: Bool, x0: U32, y0: U32, x1: U32, y1: U32}

def ibox(+bx: Box, +s: F32) -> IBox:
  Box{ok, has, x0, y0, x1, y1} = bx
  +fx0 = ((i2f(x0) * s : F32) + 0.0 : F32)
  +fy0 = ((i2f((0 - y1 : U32)) * s : F32) + 0.0 : F32)
  +fx1 = ((i2f(x1) * s : F32) + 0.0 : F32)
  +fy1 = ((i2f((0 - y0 : U32)) * s : F32) + 0.0 : F32)
  +valid = Bool.not(has) || (ifloor.ok(fx0) && ifloor.ok(fy0) && iceil.ok(fx1) && iceil.ok(fy1))
  IBox{ok && valid, Bool.pick(U32, has, ifloor(fx0), 0), Bool.pick(U32, has, ifloor(fy0), 0), Bool.pick(U32, has, iceil(fx1), 0),
    Bool.pick(U32, has, iceil(fy1), 0)}

def count.edges(+es: +List<Edge>) -> U32:
  match es:
    case Nil{}: 0
    case Con{_, rest}: (1 + count.edges(rest) : U32)

def raster.done(+w: U32, +h: U32, +x0: U32, +y0: U32, r: Raster) -> Bitmap:
  Raster{ok, pixels} = r
  Bitmap{Bool.pick(U32, ok, 2, 3), w, h, x0, y0, pixels}

def rasterize.run(ok: Bool, +vs: +List<Vertex>, +s: F32, +w: U32, +h: U32, +x0: U32, +y0: U32, +es: +List<Edge>) -> Bitmap:
  match ok:
    case False{}: Bitmap{3, w, h, x0, y0, Nil{}}
    case True{}: raster.done(w, h, x0, y0, scan.go(U32.to_nat(h), 0, w, x0, y0, Nil{}, sort.edges(es, count.edges(es)), Row{True{}, Nil{}}))

# stbtt_Rasterize(flatness 0.35, invert) into a w x h bitmap at (x0, y0).
def rasterize.flat(+vs: +List<Vertex>, +s: F32, +w: U32, +h: U32, +x0: U32, +y0: U32, c: Contours) -> Bitmap:
  Contours{ok, any, list} = c
  rasterize.run(ok && any, vs, s, w, h, x0, y0, edges.go(list, s, s, Nil{}))

def rasterize(+vs: +List<Vertex>, +s: F32, +w: U32, +h: U32, +x0: U32, +y0: U32) -> Bitmap:
  rasterize.flat(vs, s, w, h, x0, y0, flatten(vs, (flt(1051931443) / s : F32)))

def bitmap.sized(kind: U32, +vs: +List<Vertex>, +s: F32, +w: U32, +h: U32, +x0: U32, +y0: U32) -> Bitmap:
  match kind:
    case 0: Bitmap{1, w, h, x0, y0, Nil{}}
    case 1: rasterize(vs, s, w, h, x0, y0)
    case _: Bitmap{3, w, h, x0, y0, Nil{}}

def bitmap.boxed(+vs: +List<Vertex>, +s: F32, +ib: IBox) -> Bitmap:
  IBox{ok, x0, y0, x1, y1} = ib
  +w = (x1 - x0 : U32)
  +h = (y1 - y0 : U32)
  +defined = ok && sub.ok(x1, x0) && sub.ok(y1, y0)
  +empty = U32.is_eq(w, 0) || U32.is_eq(h, 0)
  +fits = Bool.not(neg(w)) && Bool.not(neg(h)) && (w <= 4096 : U32) && (h <= 4096 : U32)
  +aw = Bool.pick(U32, neg(w), (0 - w : U32), w)
  +ah = Bool.pick(U32, neg(h), (0 - h : U32), h)
  +failed = U32.is_eq(Bool.to_u32(neg(w)), Bool.to_u32(Bool.not(neg(h)))) && (aw <= 46340 : U32) && (ah <= 46340 : U32)
  bitmap.sized(Bool.pick(U32, defined, Bool.pick(U32, empty || failed, 0, Bool.pick(U32, fits, 1, 2)), 2), vs, s, w, h, x0, y0)

def bitmap.scaled(zero: Bool, +b: Blob, +info: Info, +g: U32, +s: F32, +vs: +List<Vertex>) -> Bitmap:
  match zero:
    case True{}: Bitmap{0, 0, 0, 0, 0, Nil{}}
    case False{}: bitmap.boxed(vs, s, ibox(box(b, info, g), s))

def bitmap.go(ok: Bool, +b: Blob, +info: Info, +g: U32, +s: F32, +vs: +List<Vertex>) -> Bitmap:
  match ok:
    case False{}: Bitmap{3, 0, 0, 0, 0, Nil{}}
    case True{}: bitmap.scaled(F32.is_eq(s, 0.0), b, info, g, s, vs)

def bitmap.shaped(+b: Blob, +info: Info, +g: U32, +s: F32, sh: Shape) -> Bitmap:
  Shape{ok, vs} = sh
  bitmap.go(ok, b, info, g, s, vs)

# The glyph's bitmap at scale s (both axes).
def bitmap(+b: Blob, +info: Info, +g: U32, +s: F32) -> Bitmap:
  bitmap.shaped(b, info, g, s, shape(b, info, g))

# -----------------------------------------------------------------------------
# stbtt_GetGlyphSDF(info, scale, glyph, padding, onedge_value,
# pixel_dist_scale). A pixel whose distance search reaches a curve with a
# non-degenerate quadratic term calls stbtt__solve_cubic (double pow, acos and
# cos from the C library): the glyph is refused. status as for bitmaps (0 NULL
# without outputs, 2 data, 3 refused).

# Each vertex after the first with its predecessor: the line or curve from
# (px, py) to (x, y) (control (cx, cy)) as integers, with stb's precompute.
type Seg is Data:
  Seg{kind: U32, px: U32, py: U32, x: U32, y: U32, cx: U32, cy: U32, pre: F32}

def sdf.eps2() -> F32:
  ((flt(981467136) * flt(981467136)) : F32)

def sdf.pre(+kind: U32, +px: U32, +py: U32, +x: U32, +y: U32, +cx: U32, +cy: U32, +sx: F32, +sy: F32) -> F32:
  +x0 = (i2f(x) * sx : F32)
  +y0 = (i2f(y) * sy : F32)
  +x1 = (i2f(px) * sx : F32)
  +y1 = (i2f(py) * sy : F32)
  +dist = F32.sqrt((((x1 - x0 : F32) * (x1 - x0 : F32) : F32) + ((y1 - y0 : F32) * (y1 - y0 : F32) : F32) : F32))
  +qx = (i2f(cx) * sx : F32)
  +qy = (i2f(cy) * sy : F32)
  +bx = ((x0 - (2.0 * qx : F32) : F32) + x1 : F32)
  +by = ((y0 - (2.0 * qy : F32) : F32) + y1 : F32)
  +len2 = ((bx * bx : F32) + (by * by : F32) : F32)
  Bool.pick(F32, U32.is_eq(kind, 2), Bool.pick(F32, (dist < flt(981467136) : F32), 0.0, (1.0 / dist : F32)),
    Bool.pick(F32, U32.is_eq(kind, 3), Bool.pick(F32, (len2 >= sdf.eps2() : F32), (1.0 / len2 : F32), 0.0), 0.0))

def sdf.seg(+prev: Vertex, +v: Vertex, +sx: F32, +sy: F32) -> Seg:
  Vertex{_, px, py, _, _} = prev
  Vertex{kind, x, y, cx, cy} = v
  Seg{kind, px, py, x, y, cx, cy, sdf.pre(kind, px, py, x, y, cx, cy, sx, sy)}

def sdf.segs(+vs: +List<Vertex>, +prev: Vertex, +sx: F32, +sy: F32, +acc: +List<Seg>) -> +List<Seg>:
  match vs:
    case Nil{}: List.reverse(&2, Seg, acc)
    case Con{+v, rest}: sdf.segs(rest, v, sx, sy, Con{sdf.seg(prev, v, sx, sy), acc})

# stbtt__ray_intersect_bezier with ray (1, 0): the winding change of hits
# left of the origin.
def bezier.hit(+s: F32, +a: F32, +b: F32, +q0rd: F32, +q10d: F32, +q20d: F32) -> U32:
  +h0 = ((q0rd + ((s * (2.0 - (2.0 * s : F32) : F32) : F32) * q10d : F32) : F32) + ((s * s : F32) * q20d : F32) : F32)
  +h1 = ((a * s : F32) + b : F32)
  Bool.pick(U32, (h0 < 0.0 : F32), Bool.pick(U32, (h1 < 0.0 : F32), 4294967295, 1), 0)

def bezier(+ox: F32, +oy: F32, +q0x: F32, +q0y: F32, +q1x: F32, +q1y: F32, +q2x: F32, +q2y: F32) -> U32:
  +q0p = ((q0y * 1.0 : F32) - (q0x * 0.0 : F32) : F32)
  +q1p = ((q1y * 1.0 : F32) - (q1x * 0.0 : F32) : F32)
  +q2p = ((q2y * 1.0 : F32) - (q2x * 0.0 : F32) : F32)
  +rop = ((oy * 1.0 : F32) - (ox * 0.0 : F32) : F32)
  +a = ((q0p - (2.0 * q1p : F32) : F32) + q2p : F32)
  +b = (q1p - q0p : F32)
  +c = (q0p - rop : F32)
  +quad = F32.is_ne(a, 0.0)
  +discr = ((b * b : F32) - (a * c : F32) : F32)
  +rcpna = (F32.neg(1.0) / a : F32)
  +d = F32.sqrt(discr)
  +r0 = ((b + d : F32) * rcpna : F32)
  +r1 = ((b - d : F32) * rcpna : F32)
  +lin = (c / (F32.neg(2.0) * b : F32) : F32)
  +in0 = (r0 >= 0.0 : F32) && (r0 <= 1.0 : F32)
  +in1 = (d > 0.0 : F32) && (r1 >= 0.0 : F32) && (r1 <= 1.0 : F32)
  +inl = (lin >= 0.0 : F32) && (lin <= 1.0 : F32)
  +pos = (discr > 0.0 : F32)
  +n = Bool.pick(U32, quad, Bool.pick(U32, pos, (Bool.to_u32(in0) + Bool.to_u32(in1) : U32), 0), Bool.to_u32(inl))
  +s0 = Bool.pick(F32, quad, Bool.pick(F32, in0, r0, r1), lin)
  +q0d = ((q0x * 1.0 : F32) + (q0y * 0.0 : F32) : F32)
  +q1d = ((q1x * 1.0 : F32) + (q1y * 0.0 : F32) : F32)
  +q2d = ((q2x * 1.0 : F32) + (q2y * 0.0 : F32) : F32)
  +rod = ((ox * 1.0 : F32) + (oy * 0.0 : F32) : F32)
  +q10d = (q1d - q0d : F32)
  +q20d = (q2d - q0d : F32)
  +q0rd = (q0d - rod : F32)
  +w0 = bezier.hit(s0, a, b, q0rd, q10d, q20d)
  +w1 = bezier.hit(r1, a, b, q0rd, q10d, q20d)
  Bool.pick(U32, (n >= 1 : U32), (w0 + Bool.pick(U32, (n >= 2 : U32), w1, 0) : U32), 0)

# The crossing of a line (x0, y0)-(x1, y1) (integers) left of (x, y).
def cross.line(+x: F32, +y: F32, +x0: U32, +y0: U32, +x1: U32, +y1: U32) -> U32:
  +fy0 = i2f(y0)
  +fy1 = i2f(y1)
  +fx0 = i2f(x0)
  +fx1 = i2f(x1)
  +lo = Bool.pick(F32, slt(y0, y1), fy0, fy1)
  +hi = Bool.pick(F32, slt(y0, y1), fy1, fy0)
  +left = Bool.pick(F32, slt(x0, x1), fx0, fx1)
  +inter = ((((y - fy0 : F32) / i2f((y1 - y0 : U32)) : F32) * i2f((x1 - x0 : U32)) : F32) + fx0 : F32)
  Bool.pick(U32, (y > lo : F32) && (y < hi : F32) && (x > left : F32) && (inter < x : F32), Bool.pick(U32, slt(y0, y1), 1, 4294967295), 0)

def min3(+a: U32, +b: U32, +c: U32) -> U32:
  +m = Bool.pick(U32, slt(b, c), b, c)
  Bool.pick(U32, slt(a, m), a, m)

def max3(+a: U32, +b: U32, +c: U32) -> U32:
  +m = Bool.pick(U32, slt(b, c), c, b)
  Bool.pick(U32, slt(a, m), m, a)

def cross.seg(+x: F32, +y: F32, +g: Seg) -> U32:
  Seg{kind, px, py, vx, vy, cx, cy, _} = g
  +inbox = (y > i2f(min3(py, cy, vy)) : F32) && (y < i2f(max3(py, cy, vy)) : F32) && (x > i2f(min3(px, cx, vx)) : F32)
  +flat = (U32.is_eq(px, cx) && U32.is_eq(py, cy)) || (U32.is_eq(cx, vx) && U32.is_eq(cy, vy))
  +curve = Bool.pick(U32, inbox, Bool.pick(U32, flat, cross.line(x, y, px, py, vx, vy),
    bezier(x, y, i2f(px), i2f(py), i2f(cx), i2f(cy), i2f(vx), i2f(vy))), 0)
  Bool.pick(U32, U32.is_eq(kind, 2), cross.line(x, y, px, py, vx, vy), Bool.pick(U32, U32.is_eq(kind, 3), curve, 0))

def cross.go(+gs: +List<Seg>, +x: F32, +y: F32, +w: U32) -> U32:
  match gs:
    case Nil{}: w
    case Con{+g, rest}: cross.go(rest, x, y, (w + cross.seg(x, y, g) : U32))

# stbtt__compute_crossings_x: y nudged off integer rows.
def crossings(+gs: +List<Seg>, +x: F32, +y0: F32) -> U32:
  +frac = (y0 - F32.trunc(y0) : F32)
  +y = Bool.pick(F32, (frac < flt(1008981770) : F32), (y0 + flt(1008981770) : F32), Bool.pick(F32, (frac > flt(1065185444) : F32), (y0 - flt(1008981770) : F32), y0))
  cross.go(gs, x, y, 0)

# The running minimum distance and whether the cubic solver was needed.
type Near is Data:
  Near{ok: Bool, min: F32}

def near.to(+min: F32, +d2: F32) -> F32:
  Bool.pick(F32, (d2 < (min * min : F32) : F32), F32.sqrt(d2), min)

def near.line(+g: Seg, +sx: F32, +sy: F32, +scx: F32, +scy: F32, +min0: F32) -> F32:
  Seg{_, px, py, vx, vy, _, _, pre} = g
  +x0 = (i2f(vx) * sx : F32)
  +y0 = (i2f(vy) * sy : F32)
  +x1 = (i2f(px) * sx : F32)
  +y1 = (i2f(py) * sy : F32)
  +min = near.to(min0, (((x0 - scx : F32) * (x0 - scx : F32) : F32) + ((y0 - scy : F32) * (y0 - scy : F32) : F32) : F32))
  +dist = (F32.abs((((x1 - x0 : F32) * (y0 - scy : F32) : F32) - ((y1 - y0 : F32) * (x0 - scx : F32) : F32) : F32)) * pre : F32)
  +dx = (x1 - x0 : F32)
  +dy = (y1 - y0 : F32)
  +num = (((x0 - scx : F32) * dx : F32) + ((y0 - scy : F32) * dy : F32) : F32)
  +t = (F32.neg(num) / ((dx * dx : F32) + (dy * dy : F32) : F32) : F32)
  Bool.pick(F32, (dist < min : F32) && (t >= 0.0 : F32) && (t <= 1.0 : F32), dist, min)

def near.root(+t: F32, +valid: Bool, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +x2: F32, +y2: F32, +scx: F32, +scy: F32, +min: F32) -> F32:
  +it = (1.0 - t : F32)
  +px = ((((it * it : F32) * x0 : F32) + (((2.0 * t : F32) * it : F32) * x1 : F32) : F32) + ((t * t : F32) * x2 : F32) : F32)
  +py = ((((it * it : F32) * y0 : F32) + (((2.0 * t : F32) * it : F32) * y1 : F32) : F32) + ((t * t : F32) * y2 : F32) : F32)
  Bool.pick(F32, valid && (t >= 0.0 : F32) && (t <= 1.0 : F32), near.to(min, (((px - scx : F32) * (px - scx : F32) : F32) + ((py - scy : F32) * (py - scy : F32) : F32) : F32)), min)

def near.curve(+g: Seg, +sx: F32, +sy: F32, +scx: F32, +scy: F32, +min0: F32) -> Near:
  Seg{_, px, py, vx, vy, cx, cy, pre} = g
  +x0 = (i2f(vx) * sx : F32)
  +y0 = (i2f(vy) * sy : F32)
  +x2 = (i2f(px) * sx : F32)
  +y2 = (i2f(py) * sy : F32)
  +x1 = (i2f(cx) * sx : F32)
  +y1 = (i2f(cy) * sy : F32)
  +bx0 = Bool.pick(F32, (Bool.pick(F32, (x0 < x1 : F32), x0, x1) < x2 : F32), Bool.pick(F32, (x0 < x1 : F32), x0, x1), x2)
  +by0 = Bool.pick(F32, (Bool.pick(F32, (y0 < y1 : F32), y0, y1) < y2 : F32), Bool.pick(F32, (y0 < y1 : F32), y0, y1), y2)
  +bx1 = Bool.pick(F32, (Bool.pick(F32, (x0 < x1 : F32), x1, x0) < x2 : F32), x2, Bool.pick(F32, (x0 < x1 : F32), x1, x0))
  +by1 = Bool.pick(F32, (Bool.pick(F32, (y0 < y1 : F32), y1, y0) < y2 : F32), y2, Bool.pick(F32, (y0 < y1 : F32), y1, y0))
  +near = (scx > (bx0 - min0 : F32) : F32) && (scx < (bx1 + min0 : F32) : F32) && (scy > (by0 - min0 : F32) : F32) && (scy < (by1 + min0 : F32) : F32)
  +ax = (x1 - x0 : F32)
  +ay = (y1 - y0 : F32)
  +bx = ((x0 - (2.0 * x1 : F32) : F32) + x2 : F32)
  +by = ((y0 - (2.0 * y1 : F32) : F32) + y2 : F32)
  +mx = (x0 - scx : F32)
  +my = (y0 - scy : F32)
  +a = (3.0 * ((ax * bx : F32) + (ay * by : F32) : F32) : F32)
  +b = ((2.0 * ((ax * ax : F32) + (ay * ay : F32) : F32) : F32) + ((mx * bx : F32) + (my * by : F32) : F32) : F32)
  +c = ((mx * ax : F32) + (my * ay : F32) : F32)
  +linear = (F32.abs(a) < sdf.eps2() : F32)
  +one = (F32.abs(b) >= sdf.eps2() : F32)
  +disc = ((b * b : F32) - ((4.0 * a : F32) * c : F32) : F32)
  +root = F32.sqrt(disc)
  +n = Bool.pick(U32, linear, Bool.pick(U32, one, 1, 0), Bool.pick(U32, (disc < 0.0 : F32), 0, 2))
  +r0 = Bool.pick(F32, linear, (F32.neg(c) / b : F32), ((F32.neg(b) - root : F32) / (2.0 * a : F32) : F32))
  +r1 = ((F32.neg(b) + root : F32) / (2.0 * a : F32) : F32)
  +m1 = near.to(min0, (((x0 - scx : F32) * (x0 - scx : F32) : F32) + ((y0 - scy : F32) * (y0 - scy : F32) : F32) : F32))
  +m2 = near.root(r0, (n >= 1 : U32), x0, y0, x1, y1, x2, y2, scx, scy, m1)
  +m3 = near.root(r1, (n >= 2 : U32), x0, y0, x1, y1, x2, y2, scx, scy, m2)
  Near{Bool.not(near) || F32.is_eq(pre, 0.0), Bool.pick(F32, near, m3, min0)}

def Near.ok(+n: Near) -> Bool:
  Near{ok, _} = n
  ok

def Near.min(+n: Near) -> F32:
  Near{_, min} = n
  min

def near.seg(+g: Seg, +sx: F32, +sy: F32, +scx: F32, +scy: F32, +st: Near) -> Near:
  Seg{kind, _, _, _, _, _, _, pre} = g
  Near{ok, min} = st
  +c = near.curve(g, sx, sy, scx, scy, min)
  Bool.pick(Near, U32.is_eq(kind, 2) && F32.is_ne(pre, 0.0), Near{ok, near.line(g, sx, sy, scx, scy, min)},
    Bool.pick(Near, U32.is_eq(kind, 3), Near{ok && Near.ok(c), Near.min(c)}, st))

def near.go(+gs: +List<Seg>, +sx: F32, +sy: F32, +scx: F32, +scy: F32, +st: Near) -> Near:
  match gs:
    case Nil{}: st
    case Con{+g, rest}: near.go(rest, sx, sy, scx, scy, near.seg(g, sx, sy, scx, scy, st))

def sdf.value(+winding: U32, +onedge: U32, +dist_scale: F32, +n: Near) -> SdfPixel:
  Near{ok, min0} = n
  +min = Bool.pick(F32, U32.is_eq(winding, 0), F32.neg(min0), min0)
  +val = (U32.to_f32(onedge) + (dist_scale * min : F32) : F32)
  SdfPixel{ok, Bool.pick(U32, (val < 0.0 : F32), 0, Bool.pick(U32, (val > 255.0 : F32), 255, F32.to_u32(Bool.pick(F32, (val < 0.0 : F32), 0.0, val))))}

type SdfPixel is Data:
  SdfPixel{ok: Bool, value: U32}

def sdf.pixel(+gs: +List<Seg>, +x: U32, +y: U32, +s: F32, +onedge: U32, +dist_scale: F32) -> SdfPixel:
  +scx = (i2f(x) + 0.5 : F32)
  +scy = (i2f(y) + 0.5 : F32)
  +sy = F32.neg(s)
  sdf.value(crossings(gs, (scx / s : F32), (scy / sy : F32)), onedge, dist_scale, near.go(gs, s, sy, scx, scy, Near{True{}, 999999.0}))

def SdfPixel.ok(+p: SdfPixel) -> Bool:
  SdfPixel{ok, _} = p
  ok

def SdfPixel.value(+p: SdfPixel) -> U32:
  SdfPixel{_, v} = p
  v

def sdf.row(n: Nat, +gs: +List<Seg>, +x: U32, +y: U32, +s: F32, +onedge: U32, +dist_scale: F32, +ok: Bool, +out: +List<U32>) -> Row:
  match n:
    case 0n: Row{ok, out}
    case 1n+k:
      +p = sdf.pixel(gs, x, y, s, onedge, dist_scale)
      sdf.row(k, gs, (x + 1 : U32), y, s, onedge, dist_scale, ok && SdfPixel.ok(p), Con{SdfPixel.value(p), out})

def sdf.rows(n: Nat, +gs: +List<Seg>, +x0: U32, +w: U32, +y: U32, +s: F32, +onedge: U32, +dist_scale: F32, r: Row) -> Row:
  match n r:
    case 0n r2: r2
    case 1n+k Row{+ok, +out}: sdf.rows(k, gs, x0, w, (y + 1 : U32), s, onedge, dist_scale, sdf.row(U32.to_nat(w), gs, x0, y, s, onedge, dist_scale, ok, out))

def sdf.done(+w: U32, +h: U32, +x0: U32, +y0: U32, r: Row) -> Bitmap:
  Row{ok, out} = r
  Bitmap{Bool.pick(U32, ok, 2, 3), w, h, x0, y0, List.reverse(&2, U32, out)}

def Vertex.kind(+v: Vertex) -> U32:
  Vertex{kind, _, _, _, _} = v
  kind

def sdf.verts(ok: Bool, +vs: +List<Vertex>, +w: U32, +h: U32, +x0: U32, +y0: U32, +s: F32, +onedge: U32, +dist_scale: F32) -> Bitmap:
  match ok vs:
    case False{} _: Bitmap{3, w, h, x0, y0, Nil{}}
    case True{} Nil{}: sdf.done(w, h, x0, y0, sdf.rows(U32.to_nat(h), Nil{}, x0, w, y0, s, onedge, dist_scale, Row{True{}, Nil{}}))
    case True{} Con{+v, rest}:
      +gs = sdf.segs(rest, v, s, F32.neg(s), Nil{})
      +moved = U32.is_eq(Vertex.kind(v), 1)
      Bool.pick(Bitmap, moved, sdf.done(w, h, x0, y0, sdf.rows(U32.to_nat(h), gs, x0, w, y0, s, onedge, dist_scale, Row{True{}, Nil{}})), Bitmap{3, w, h, x0, y0, Nil{}})

def sdf.shaped(+w: U32, +h: U32, +x0: U32, +y0: U32, +s: F32, +onedge: U32, +dist_scale: F32, sh: Shape) -> Bitmap:
  Shape{ok, vs} = sh
  sdf.verts(ok, vs, w, h, x0, y0, s, onedge, dist_scale)

def sdf.boxed(+b: Blob, +info: Info, +g: U32, +s: F32, +pad: U32, +onedge: U32, +dist_scale: F32, +ib: IBox) -> Bitmap:
  IBox{ok, bx0, by0, bx1, by1} = ib
  +x0 = (bx0 - pad : U32)
  +y0 = (by0 - pad : U32)
  +x1 = (bx1 + pad : U32)
  +y1 = (by1 + pad : U32)
  +w = (x1 - x0 : U32)
  +h = (y1 - y0 : U32)
  +empty = U32.is_eq(bx0, bx1) || U32.is_eq(by0, by1)
  +defined = sub.ok(bx0, pad) && sub.ok(by0, pad) && add.ok(bx1, pad) && add.ok(by1, pad) && sub.ok(x1, x0) && sub.ok(y1, y0) &&
    Bool.not(neg(w)) && Bool.not(neg(h)) && Bool.not(U32.is_eq(w, 0)) && Bool.not(U32.is_eq(h, 0)) && (w <= 4096 : U32) && (h <= 4096 : U32)
  Bool.pick(Bitmap, ok, Bool.pick(Bitmap, empty, Bitmap{0, 0, 0, 0, 0, Nil{}},
    Bool.pick(Bitmap, defined, sdf.shaped(w, h, x0, y0, s, onedge, dist_scale, shape(b, info, g)), Bitmap{3, 0, 0, 0, 0, Nil{}})),
    Bitmap{3, 0, 0, 0, 0, Nil{}})

def sdf.scaled(zero: Bool, +b: Blob, +info: Info, +g: U32, +s: F32, +pad: U32, +onedge: U32, +dist_scale: F32) -> Bitmap:
  match zero:
    case True{}: Bitmap{0, 0, 0, 0, 0, Nil{}}
    case False{}: sdf.boxed(b, info, g, s, pad, onedge, dist_scale, ibox(box(b, info, g), s))

# The glyph's signed distance field at scale s.
def sdf(+b: Blob, +info: Info, +g: U32, +s: F32, +pad: U32, +onedge: U32, +dist_scale: F32) -> Bitmap:
  sdf.scaled(F32.is_eq(s, 0.0), b, info, g, s, pad, onedge, dist_scale)
