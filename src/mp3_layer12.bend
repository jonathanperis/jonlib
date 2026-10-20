# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of dr_mp3 v0.7.4 (David Reid; public domain or MIT
# No Attribution; its decoder is minimp3, by lieff, CC0), as raylib 6.2
# vendors it in src/external/dr_mp3.h: a Layer I or II frame's subband
# samples (drmp3_L12_subband_alloc_table, drmp3_L12_read_scale_info,
# drmp3_L12_read_scalefactors, drmp3_L12_dequantize_granule and
# drmp3_L12_apply_scf_384, as drmp3dec_decode_frame calls them). The
# synthesis is src/mp3_layer3.bend's. See THIRD_PARTY_NOTICES.md and
# LICENSES/dr_mp3.txt.
#
# Floats are carried as their bits (U32). The reader is src/mp3.bend's: a
# read past the frame's limit gives 0 and its position moves on all the
# same, as drmp3_bs_get_bits does.
import Base
import ./mp3.bend as H

def flt(word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# g_bitalloc_code_tab
def codes() -> +List<U32>:
  [0, 17, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 0, 17, 18, 3, 19, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 16, 0, 17, 18, 3, 19, 4, 5, 16, 0, 17, 18, 16, 0, 17, 18, 19, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0, 17, 18, 3, 19, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]

# g_deq_L12: 9.53674316e-07f/x, 7.56931807e-07f/x, 6.00777173e-07f/x for x
# = 3, 7, ..., 65535, 3, 5, 9, as the compiler folds each (one rounding).
def deq() -> +List<U32>:
  [883600043, 881292622, 878118603, 873613605, 870856399, 867716855, 864585865, 861453232, 858522991, 855908616, 852606436, 849770719, 847382561, 843999643, 841208938, 838926852, 835504520, 832735788, 830505089, 827063281, 824305407, 822100000, 818648512, 815896035, 813703176, 810246862, 807497075, 805310466, 801851742, 799103299, 796919809, 793459881, 790712109, 788530176, 785069647, 782322210, 780141056, 776680226, 773932957, 771752192, 768291211, 765544027, 763363456, 759902400, 757155257, 883600043, 881292622, 878118603, 877448397, 874679492, 872481811, 870551097, 867474536, 865032668]

# -----------------------------------------------------------------------------
# drmp3_L12_subband_alloc_table

# A band's entry of the allocation table: where its codes begin in
# g_bitalloc_code_tab and how many bits pick one.
type Alloc is Data:
  Alloc{offset: U32, width: U32}

# total_bands, stereo_bands and each band's entry.
type Layout is Data:
  Layout{total: U32, stereo: U32, allocs: +List<Alloc>}

# The table's entries ({tab_offset, code_tab_width, band_count} as three
# words each) spread over `n` bands.
def allocs.expand(entries: +List<U32>, acc: +List<Alloc>) -> +List<Alloc>:
  match entries:
    case Con{+offset, Con{+width, Con{+count, +rest}}}: allocs.expand(rest, List.append(&2, Alloc, acc, List.replicate(Alloc, U32.to_nat(count), Alloc{offset, width})))
    case _: acc

def allocs.first(n: Nat, xs: +List<Alloc>, acc: +List<Alloc>) -> +List<Alloc>:
  match n:
    case 0n: List.reverse(&2, Alloc, acc)
    case 1n+k:
      match xs:
        case Nil{}: List.reverse(&2, Alloc, acc)
        case Con{+x, rest}: allocs.first(k, rest, Con{x, acc})

def layout.made(+n: U32, +stereo: U32, +entries: +List<U32>) -> Layout:
  Layout{n, U32.min(stereo, n), allocs.first(U32.to_nat(n), allocs.expand(entries, Nil{}), Nil{})}

# The table by the header: Layer I's; MPEG-2 Layer II's; MPEG-1 Layer II's
# by the bit rate a channel (192 for free format) and the sample rate.
def layout.of(+h: U32) -> Layout:
  +mode = ((h >> 6n : U32) .&. 3 : U32)
  +stereo = Bool.pick(U32, U32.is_eq(mode, 3), 0, Bool.pick(U32, U32.is_eq(mode, 1), ((((h >> 4n : U32) .&. 3 : U32) << 2n : U32) + 4 : U32), 32))
  +rate = ((h >> 10n : U32) .&. 3 : U32)
  +shared = (H.hdr.kbps(h) >> U32.to_nat(Bool.pick(U32, U32.is_ne(mode, 3), 1, 0)) : U32)
  +kbps = Bool.pick(U32, U32.is_eq(shared, 0), 192, shared)
  Bool.pick(Layout, H.hdr.layer1(h), layout.made(32, stereo, [76, 4, 32]),
    Bool.pick(Layout, Bool.not(H.hdr.mpeg1(h)), layout.made(30, stereo, [60, 4, 4, 44, 3, 7, 44, 2, 19]),
      Bool.pick(Layout, (kbps < 56 : U32), layout.made(Bool.pick(U32, U32.is_eq(rate, 2), 12, 8), stereo, [44, 4, 2, 44, 3, 10]),
        layout.made(Bool.pick(U32, (kbps >= 96 : U32) && U32.is_ne(rate, 1), 30, 27), stereo, [0, 4, 3, 16, 4, 8, 32, 3, 12, 40, 2, 7]))))

# -----------------------------------------------------------------------------
# drmp3_L12_read_scale_info

# What a read gives: the values (in order) and the reader's position.
type Reading is Data:
  Reading{values: +List<U32>, pos: U32}

# Each band's allocation: the first channel's, and the second's from its own
# code below stereo_bands (the first's again above); the second channel
# has none when there are no stereo bands.
def alloc.read(allocs: +List<Alloc>, +i: U32, +stereo: U32, +bytes: +List<U32>, +limit: U32, +pos: U32, +acc: +List<U32>) -> Reading:
  match allocs:
    case Nil{}: Reading{List.reverse(&2, U32, acc), pos}
    case Con{Alloc{+offset, +width}, rest}:
      +ba0 = H.nth(codes(), (offset + H.bits(bytes, limit, pos, width) : U32))
      +two = (i < stereo : U32)
      +after = (pos + width : U32)
      +ba1 = Bool.pick(U32, two, H.nth(codes(), (offset + H.bits(bytes, limit, after, width) : U32)), ba0)
      alloc.read(rest, (i + 1 : U32), stereo, bytes, limit, Bool.pick(U32, two, (after + width : U32), after), Con{Bool.pick(U32, U32.is_ne(stereo, 0), ba1, 0), Con{ba0, acc}})

# scfcod: 2 bits for an allocated band of Layer II, 2 for one of Layer I
# without bits, 6 for one without allocation.
def cod.read(bas: +List<U32>, +layer1: Bool, +bytes: +List<U32>, +limit: U32, +pos: U32, +acc: +List<U32>) -> Reading:
  match bas:
    case Nil{}: Reading{List.reverse(&2, U32, acc), pos}
    case Con{+ba, rest}:
      +reads = U32.is_ne(ba, 0) && Bool.not(layer1)
      cod.read(rest, layer1, bytes, limit, Bool.pick(U32, reads, (pos + 2 : U32), pos),
        Con{Bool.pick(U32, U32.is_eq(ba, 0), 6, Bool.pick(U32, layer1, 2, H.bits(bytes, limit, pos, 2))), acc})

# A scalefactor of 6 bits b: g_deq_L12[ba*3 - 6 + b % 3]*(int)(1 << 21 >> b/3).
def scale.of(+ba: U32, +b: U32) -> U32:
  +index = Bool.pick(U32, (ba >= 2 : U32), ((((ba * 3) - 6) + (b % 3)) : U32), 0)
  F32.bits((flt(H.nth(deq(), index)) * U32.to_f32((2097152 >> U32.to_nat((b / 3 : U32)) : U32)) : F32))

# The three scalefactors of a band: one read for each bit of the mask
# (4 + ((19 >> scfcod) & 3), none without allocation), each kept for the
# next until another is read.
def scf.read(bas: +List<U32>, cods: +List<U32>, +bytes: +List<U32>, +limit: U32, +pos: U32, +acc: +List<U32>) -> Reading:
  match bas cods:
    case Con{+ba, brest} Con{+cod, crest}:
      +mask = Bool.pick(U32, U32.is_eq(ba, 0), 0, (4 + ((19 >> U32.to_nat(cod) : U32) .&. 3 : U32) : U32))
      +r4 = U32.is_ne((mask .&. 4 : U32), 0)
      +r2 = U32.is_ne((mask .&. 2 : U32), 0)
      +r1 = U32.is_ne((mask .&. 1 : U32), 0)
      +p2 = Bool.pick(U32, r4, (pos + 6 : U32), pos)
      +p1 = Bool.pick(U32, r2, (p2 + 6 : U32), p2)
      +s4 = Bool.pick(U32, r4, scale.of(ba, H.bits(bytes, limit, pos, 6)), 0)
      +s2 = Bool.pick(U32, r2, scale.of(ba, H.bits(bytes, limit, p2, 6)), s4)
      +s1 = Bool.pick(U32, r1, scale.of(ba, H.bits(bytes, limit, p1, 6)), s2)
      scf.read(brest, crest, bytes, limit, Bool.pick(U32, r1, (p1 + 6 : U32), p1), Con{s1, Con{s2, Con{s4, acc}}})
    case _ _: Reading{List.reverse(&2, U32, acc), pos}

# The scale information: total_bands, stereo_bands, each band's allocation
# for each channel (2*total_bands, the second channel's 0 above
# stereo_bands once its scalefactors are read), the three scalefactors of
# each, and the reader's position after them.
type Scale is Data:
  Scale{total: U32, stereo: U32, alloc: +List<U32>, scf: +List<U32>, pos: U32}

def scale.unshared(alloc: +List<U32>, +i: U32, +stereo: U32, acc: +List<U32>) -> +List<U32>:
  match alloc:
    case Con{+a, Con{+b, rest}}: scale.unshared(rest, (i + 1 : U32), stereo, Con{Bool.pick(U32, (i < stereo : U32), b, 0), Con{a, acc}})
    case _: List.reverse(&2, U32, acc)

def scale.done(+total: U32, +stereo: U32, +alloc: +List<U32>, read: Reading) -> Scale:
  Reading{+scf, +pos} = read
  Scale{total, stereo, scale.unshared(alloc, 0, stereo, Nil{}), scf, pos}

def scale.coded(+total: U32, +stereo: U32, +alloc: +List<U32>, +bytes: +List<U32>, +limit: U32, read: Reading) -> Scale:
  Reading{+cods, +pos} = read
  scale.done(total, stereo, alloc, scf.read(alloc, cods, bytes, limit, pos, Nil{}))

def scale.allocated(+total: U32, +stereo: U32, +layer1: Bool, +bytes: +List<U32>, +limit: U32, read: Reading) -> Scale:
  Reading{+alloc, +pos} = read
  scale.coded(total, stereo, alloc, bytes, limit, cod.read(alloc, layer1, bytes, limit, pos, Nil{}))

def scale.laid(+h: U32, +bytes: +List<U32>, +limit: U32, +pos: U32, layout: Layout) -> Scale:
  Layout{+total, +stereo, +allocs} = layout
  scale.allocated(total, stereo, H.hdr.layer1(h), bytes, limit, alloc.read(allocs, 0, stereo, bytes, limit, pos, Nil{}))

def scale.info(+h: U32, +bytes: +List<U32>, +limit: U32, +pos: U32) -> Scale:
  scale.laid(h, bytes, limit, pos, layout.of(h))

# -----------------------------------------------------------------------------
# drmp3_L12_dequantize_granule

def int.float(+v: U32) -> U32:
  F32.bits(Bool.pick(F32, (v >= 2147483648 : U32), F32.neg(U32.to_f32((0 - v : U32))), U32.to_f32(v)))

# `g` samples of a band allocated `ba`: ba below 17 reads each in ba bits
# less half; above, one code of 5, 7 or 10 bits gives them in base 3, 5 or
# 9 (code % mod - mod/2, then code /= mod).
def samples.grouped(n: Nat, +code: U32, +mod: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k: samples.grouped(k, (code / mod : U32), mod, Con{int.float(((code % mod) - (mod / 2) : U32)), acc})

def samples.plain(n: Nat, +ba: U32, +bytes: +List<U32>, +limit: U32, +pos: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k: samples.plain(k, ba, bytes, limit, (pos + ba : U32), Con{int.float((H.bits(bytes, limit, pos, ba) - ((1 << U32.to_nat((ba - 1 : U32)) : U32) - 1 : U32) : U32)), acc})

def band.bits(+ba: U32, +g: U32) -> U32:
  +mod = ((2 << U32.to_nat((ba - 17 : U32)) : U32) + 1 : U32)
  Bool.pick(U32, U32.is_eq(ba, 0), 0, Bool.pick(U32, (ba < 17 : U32), (ba * g : U32), ((mod + 2) - (mod >> 3n : U32) : U32)))

def zeros(n: Nat, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: zeros(k, Con{0, acc})

def band.samples(+ba: U32, +g: U32, +bytes: +List<U32>, +limit: U32, +pos: U32) -> +List<U32>:
  +mod = ((2 << U32.to_nat((ba - 17 : U32)) : U32) + 1 : U32)
  Bool.pick(+List<U32>, U32.is_eq(ba, 0), zeros(U32.to_nat(g), Nil{}),
    Bool.pick(+List<U32>, (ba < 17 : U32), samples.plain(U32.to_nat(g), ba, bytes, limit, pos, Nil{}),
      samples.grouped(U32.to_nat(g), H.bits(bytes, limit, pos, ((mod + 2) - (mod >> 3n : U32) : U32)), mod, Nil{})))

# One of the four steps of a granule: every band of each channel in turn,
# its g samples (zeros where it has no allocation).
def step.read(alloc: +List<U32>, +g: U32, +bytes: +List<U32>, +limit: U32, +pos: U32, acc: +List<+List<U32>>) -> Rows:
  match alloc:
    case Nil{}: Rows{List.reverse(&2, +List<U32>, acc), pos}
    case Con{+ba, rest}: step.read(rest, g, bytes, limit, (pos + band.bits(ba, g) : U32), Con{band.samples(ba, g, bytes, limit, pos), acc})

# Each band's samples (a list a band, the channels in turn) and the
# reader's position.
type Rows is Data:
  Rows{rows: +List<+List<U32>>, pos: U32}

def Rows.pos(rows: Rows) -> U32:
  Rows{_, pos} = rows
  pos

def Rows.rows(rows: Rows) -> +List<+List<U32>>:
  Rows{rows, _} = rows
  rows

# A band's samples of this step after those of the steps before.
def rows.joined(before: +List<+List<U32>>, now: +List<+List<U32>>, acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match before now:
    case Con{+b, brest} Con{+n, nrest}: rows.joined(brest, nrest, Con{List.append(&2, U32, b, n), acc})
    case _ _: List.reverse(&2, +List<U32>, acc)

def empty.rows(n: Nat, acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match n:
    case 0n: acc
    case 1n+k: empty.rows(k, Con{Nil{}, acc})

# The steps after `n` more: each step's samples of a band after those of
# the steps before.
def granule.step(n: Nat, +alloc: +List<U32>, +g: U32, +bytes: +List<U32>, +limit: U32, +before: +List<+List<U32>>, +pos: U32) -> Rows:
  match n:
    case 0n: Rows{before, pos}
    case 1n+k:
      +now = step.read(alloc, g, bytes, limit, pos, Nil{})
      granule.step(k, alloc, g, bytes, limit, rows.joined(before, Rows.rows(now), Nil{}), Rows.pos(now))

# drmp3_L12_dequantize_granule with group size g (1 for Layer I, 3 for
# Layer II): four steps; a band's samples in the order they land.
def granule(+alloc: +List<U32>, +g: U32, +bytes: +List<U32>, +limit: U32, +pos: U32) -> Rows:
  granule.step(4n, alloc, g, bytes, limit, empty.rows(U32.to_nat(H.count(alloc, 0)), Nil{}), pos)

# -----------------------------------------------------------------------------
# drmp3_L12_apply_scf_384 and the granule buffer

# A band's 12 samples times its scalefactor (bits as floats), then the six
# slots that stay 0.
def band.scaled(+values: +List<U32>, +scf: U32, acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: List.reverse.go(&2, U32, acc, zeros(6n, Nil{}))
    case Con{+v, rest}: band.scaled(rest, scf, Con{F32.bits((flt(v) * flt(scf) : F32)), acc})

# A channel's 576 values: its bands (the second channel's above
# stereo_bands are the first's samples) times their scalefactor `which`
# (0 to 2), then zeros to 32 bands.
def channel.values(rows: +List<+List<U32>>, firsts: +List<+List<U32>>, +scf: +List<U32>, +which: U32, +right: Bool, +i: U32, +stereo: U32, acc: +List<U32>) -> +List<U32>:
  match rows firsts:
    case Con{+row, rest} Con{+first, frest}:
      +own = Bool.not(right) || (i < stereo : U32)
      channel.values(rest, frest, List.drop(&2, U32, scf, 6n), which, right, (i + 1 : U32), stereo,
        List.reverse.go(&2, U32, band.scaled(Bool.pick(+List<U32>, own, row, first), H.nth(scf, (which + Bool.pick(U32, right, 3, 0) : U32)), Nil{}), acc))
    case _ _: List.reverse.go(&2, U32, acc, zeros(U32.to_nat(((32 - i) * 18 : U32)), Nil{}))

# The rows at even places (0, 2, ...), the last one too when it has no pair.
def evens(xs: +List<+List<U32>>, acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match xs:
    case Con{+a, Con{_, rest}}: evens(rest, Con{a, acc})
    case Con{+a, Nil{}}: List.reverse(&2, +List<U32>, Con{a, acc})
    case Nil{}: List.reverse(&2, +List<U32>, acc)

def odds(xs: +List<+List<U32>>) -> +List<+List<U32>>:
  match xs:
    case Con{_, +rest}: evens(rest, Nil{})
    case Nil{}: Nil{}

# The two channels' granule buffers (grbuf) after drmp3_L12_apply_scf_384
# with the scalefactors at `which`.
type Buffer is Data:
  Buffer{left: +List<U32>, right: +List<U32>}

def buffer.of(+rows: +List<+List<U32>>, +scf: +List<U32>, +which: U32, +stereo: U32) -> Buffer:
  Buffer{channel.values(evens(rows, Nil{}), evens(rows, Nil{}), scf, which, False{}, 0, stereo, Nil{}),
    channel.values(odds(rows), evens(rows, Nil{}), scf, which, True{}, 0, stereo, Nil{})}

# -----------------------------------------------------------------------------
# A frame

# What a frame gives: the granule buffers to synthesize in order (each 384
# samples a channel), and whether the reader stayed within the frame
# (otherwise the last buffer is the one synthesized before the check that
# failed, and the frame gives no samples).
type Frame is Data:
  Frame{buffers: +List<Buffer>, fine: Bool}

def frame.layer1(+scale: Scale, +bytes: +List<U32>, +limit: U32) -> Frame:
  Scale{_, +stereo, +alloc, +scf, +pos} = scale
  +g0 = granule(alloc, 1, bytes, limit, pos)
  +g1 = granule(alloc, 1, bytes, limit, Rows.pos(g0))
  +g2 = granule(alloc, 1, bytes, limit, Rows.pos(g1))
  +fine = Bool.not((Rows.pos(g0) > limit : U32)) && Bool.not((Rows.pos(g1) > limit : U32))
  Frame{Bool.pick(+List<Buffer>, fine, [buffer.of(rows.joined(rows.joined(Rows.rows(g0), Rows.rows(g1), Nil{}), Rows.rows(g2), Nil{}), scf, 2, stereo)], Nil{}),
    fine && Bool.not((Rows.pos(g2) > limit : U32))}

# Layer II: each of the three granules is synthesized as it is read; the
# reader is checked after each (`over`: the last one read past the frame).
def frame.layer2(n: Nat, over: Bool, +which: U32, +scale: Scale, +bytes: +List<U32>, +limit: U32, +pos: U32, acc: +List<Buffer>) -> Frame:
  match n over:
    case _ True{}: Frame{List.reverse(&2, Buffer, acc), False{}}
    case 0n False{}: Frame{List.reverse(&2, Buffer, acc), True{}}
    case 1n+k False{}:
      Scale{+total, +stereo, +alloc, +scf, +start} = scale
      +g = granule(alloc, 3, bytes, limit, pos)
      frame.layer2(k, (Rows.pos(g) > limit : U32), (which + 1 : U32), Scale{total, stereo, alloc, scf, start}, bytes, limit, Rows.pos(g),
        Con{buffer.of(Rows.rows(g), scf, which, stereo), acc})

def Scale.pos(scale: Scale) -> U32:
  Scale{_, _, _, _, pos} = scale
  pos

def frame.of(layer1: Bool, +scale: Scale, +bytes: +List<U32>, +limit: U32) -> Frame:
  match layer1:
    case True{}: frame.layer1(scale, bytes, limit)
    case False{}: frame.layer2(3n, False{}, 0, scale, bytes, limit, Scale.pos(scale), Nil{})

# A Layer I or II frame of header h: its payload (after the header) of
# `limit` bits, read from bit `pos` (16 past a CRC).
def frame.read(+h: U32, +bytes: +List<U32>, +limit: U32, +pos: U32) -> Frame:
  frame.of(H.hdr.layer1(h), scale.info(h, bytes, limit, pos), bytes, limit)

def Layout.total(layout: Layout) -> U32:
  Layout{total, _, _} = layout
  total

def Layout.stereo(layout: Layout) -> U32:
  Layout{_, stereo, _} = layout
  stereo
