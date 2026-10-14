# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of dr_mp3 v0.7.4 (David Reid; public domain or MIT
# No Attribution; its decoder is minimp3, by lieff, CC0), as raylib 6.0
# vendors it in src/external/dr_mp3.h: Layer III's scalefactors
# (drmp3_L3_read_scalefactors, drmp3_L3_ldexp_q2,
# drmp3_L3_decode_scalefactors), its Huffman-coded values (drmp3_L3_pow_43,
# drmp3_L3_huffman), its stereo step (drmp3_L3_midside_stereo,
# drmp3_L3_intensity_stereo, drmp3_L3_stereo_process), its filter bank's
# first half (drmp3_L3_reorder, drmp3_L3_antialias, drmp3_L3_imdct_gr with
# drmp3_L3_imdct36, drmp3_L3_dct3_9, drmp3_L3_imdct_short, drmp3_L3_imdct12,
# drmp3_L3_idct3, and drmp3_L3_change_sign), its synthesis filter
# (drmp3d_DCT_II, drmp3d_synth_pair, drmp3d_synth, drmp3d_synth_granule,
# drmp3d_scale_pcm) and the frame around them (drmp3_L3_restore_reservoir,
# drmp3_L3_save_reservoir, drmp3dec_decode_frame). See
# THIRD_PARTY_NOTICES.md and LICENSES/dr_mp3.txt.
#
# Floats are binary32, computed in dr_mp3's order, and kept in lists as
# their bits. C ints are U32 two's-complement words. The tables are
# src/mp3_tables.bend, generated from the header (tools/mp3_tables.py); a
# table is a list built where it is named, so one that a loop reads is named
# once, outside the loop.
import Base
import ./mp3.bend as H
import ./mp3_tables.bend as T
import ./mp3_layer12.bend as L12

# A float from its bits. The constructor's way (U32{word} to F32{word})
# goes through a list of 32 bits on the JavaScript target, and this module
# converts tens of thousands of floats a frame; so a finite float is made by
# arithmetic instead, which is exact: its significand as an integer (below
# 2^24) times the power of two of its exponent, a factor for each bit of the
# power, every partial product being a multiple of 2^-149 below 2^128.
# Infinities and NaNs, which the decoder does not produce, go the first way.
def float.exact(value: U32) -> F32:
  U32{word} = value
  F32{word}

# 2^k or 2^-k for k below 256, as the product of the factors of k's bits
# (2^1, 2^2, 2^4 ... or their inverses), times `x`.
def float.scaled(+x: F32, +k: U32, +down: Bool) -> F32:
  +f4 = Bool.pick(F32, down, (1.0 / 65536.0 : F32), 65536.0)
  +f5 = (f4 * f4 : F32)
  +f6 = (f5 * f5 : F32)
  +f7 = (f6 * f6 : F32)
  +x0 = (x * Bool.pick(F32, U32.is_ne((k .&. 1 : U32), 0), Bool.pick(F32, down, 0.5, 2.0), 1.0) : F32)
  +x1 = (x0 * Bool.pick(F32, U32.is_ne((k .&. 2 : U32), 0), Bool.pick(F32, down, 0.25, 4.0), 1.0) : F32)
  +x2 = (x1 * Bool.pick(F32, U32.is_ne((k .&. 4 : U32), 0), Bool.pick(F32, down, 0.0625, 16.0), 1.0) : F32)
  +x3 = (x2 * Bool.pick(F32, U32.is_ne((k .&. 8 : U32), 0), Bool.pick(F32, down, 0.00390625, 256.0), 1.0) : F32)
  +x4 = (x3 * Bool.pick(F32, U32.is_ne((k .&. 16 : U32), 0), f4, 1.0) : F32)
  +x5 = (x4 * Bool.pick(F32, U32.is_ne((k .&. 32 : U32), 0), f5, 1.0) : F32)
  +x6 = (x5 * Bool.pick(F32, U32.is_ne((k .&. 64 : U32), 0), f6, 1.0) : F32)
  (x6 * Bool.pick(F32, U32.is_ne((k .&. 128 : U32), 0), f7, 1.0) : F32)

# A float's significand with its hidden bit (a subnormal has none).
def float.significand(+bits: U32) -> U32:
  ((bits .&. 8388607) .|. Bool.pick(U32, U32.is_eq(((bits >> 23n) .&. 255 : U32), 0), 0, 8388608) : U32)

# The power of two the significand is multiplied by is its exponent field
# less 150 (a subnormal's field counts as 1): whether that is below zero,
# and how far from zero it is.
def float.down(+bits: U32) -> Bool:
  (((bits >> 23n) .&. 255) < 150 : U32)

def float.power(+bits: U32) -> U32:
  +p = U32.max(((bits >> 23n) .&. 255 : U32), 1)
  Bool.pick(U32, (p >= 150 : U32), (p - 150 : U32), (150 - p : U32))

def float.finite(special: Bool, +value: U32) -> F32:
  match special:
    case True{}: float.exact(value)
    case False{}:
      +x = float.scaled(U32.to_f32(float.significand(value)), float.power(value), float.down(value))
      Bool.pick(F32, (value >= 2147483648 : U32), F32.neg(x), x)

def float(+value: U32) -> F32:
  float.finite(U32.is_eq(((value >> 23n) .&. 255 : U32), 255), value)

# A list after its first element. (List.drop counts with a Nat, which the
# JavaScript target makes a big integer: this is the loops' step.)
def tail(xs: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}: Nil{}
    case Con{_, rest}: rest

def row.first(rows: +List<+List<U32>>) -> +List<U32>:
  match rows:
    case Nil{}: Nil{}
    case Con{r, _}: r

def row(+rows: +List<+List<U32>>, +i: U32) -> +List<U32>:
  row.first(List.drop(&2, +List<U32>, rows, U32.to_nat(i)))

# -----------------------------------------------------------------------------
# Scalefactors

# drmp3_L3_ldexp_q2: y times 2^(-exp_q2/4), 120 quarter steps at a time; each
# step multiplies by g_expfrac[e & 3]*(1 << 30 >> (e >> 2)), a float.
def ldexp.steps(n: Nat, done: Bool, +y: F32, +exp: U32) -> F32:
  match n:
    case 0n: y
    case 1n+rest:
      match done:
        case True{}: y
        case False{}:
          +e = U32.min(120, exp)
          ldexp.steps(rest, U32.is_eq(exp, e), (y * (float(H.nth(T.expfrac(), (e .&. 3 : U32))) * U32.to_f32((1073741824 >> U32.to_nat((e >> 2n : U32)) : U32))) : F32), (exp - e : U32))

def ldexp.q2(+y: F32, +exp: U32) -> F32:
  ldexp.steps(U32.to_nat(((exp / 120) + 2 : U32)), False{}, y, exp)

# What drmp3_L3_read_scalefactors leaves: the scalefactors (last first), the
# intensity positions of the channel after it (those of before it where it
# wrote none, last first), the positions of before not yet passed, and the
# bit after what it read.
type Read is Data:
  Read{scf: +List<U32>, ist: +List<U32>, old: +List<U32>, pos: U32}

# One scalefactor band group read: `count` values of `size` bits. An
# intensity position of all ones is -1 (255) when `limited` (MPEG-2).
def read.values(n: Nat, +bytes: +List<U32>, +limit: U32, +size: U32, +limited: Bool, read: Read) -> Read:
  match n:
    case 0n: read
    case 1n+rest:
      Read{+scf, +ist, old, +pos} = read
      +s = H.bits(bytes, limit, pos, size)
      read.values(rest, bytes, limit, size, limited,
        Read{Con{s, scf}, Con{Bool.pick(U32, limited && U32.is_eq(s, ((1 << U32.to_nat(size)) - 1 : U32)), 255, s), ist}, tail(old), (pos + size : U32)})

# A group kept from the granule before (scfsi): the positions as they were.
def read.kept(n: Nat, read: Read) -> Read:
  match n:
    case 0n: read
    case 1n+rest:
      Read{+scf, +ist, +old, pos} = read
      read.kept(rest, Read{Con{H.first(old), scf}, Con{H.first(old), ist}, tail(old), pos})

# A group of no bits: zeros.
def read.zeros(n: Nat, read: Read) -> Read:
  match n:
    case 0n: read
    case 1n+rest:
      Read{+scf, +ist, +old, pos} = read
      read.zeros(rest, Read{Con{0, scf}, Con{0, ist}, tail(old), pos})

def read.group(kept: Bool, empty: Bool, +count: U32, +bytes: +List<U32>, +limit: U32, +size: U32, +limited: Bool, read: Read) -> Read:
  match kept empty:
    case True{} _: read.kept(U32.to_nat(count), read)
    case False{} True{}: read.zeros(U32.to_nat(count), read)
    case False{} False{}: read.values(U32.to_nat(count), bytes, limit, size, limited, read)

# The four groups in turn, until one of no bands. `scfsi` is the word whose
# bit 3 keeps a group (it doubles each group; negative for MPEG-2, where it
# keeps none and limits the intensity positions).
def read.groups(n: Nat, stop: Bool, sizes: +List<U32>, counts: +List<U32>, +bytes: +List<U32>, +limit: U32, +scfsi: U32, +read: Read) -> Read:
  match n:
    case 0n: read
    case 1n+rest:
      match stop sizes counts:
        case False{} Con{+size, +more} Con{+count, +next}:
          read.groups(rest, U32.is_eq(H.first(next), 0), more, next, bytes, limit, (scfsi * 2 : U32),
            read.group(U32.is_ne((scfsi .&. 8 : U32), 0), U32.is_eq(size, 0), count, bytes, limit, size, (scfsi >= 2147483648 : U32), read))
        case _ _ _: read

# MPEG-2's scalefactor sizes: scalefac_compress in the mixed radix of g_mod's
# row, the first row whose product it is below (`k` is that row's place in
# g_mod; the partition's counts are four entries past it).
type Sizes is Data:
  Sizes{sizes: +List<U32>, k: U32}

def nz(+x: U32) -> U32:
  U32.max(x, 1)

def sizes.row(+sfc: U32, +m: +List<U32>) -> +List<U32>:
  [((sfc / nz(((H.nth(m, 3) * H.nth(m, 2)) * H.nth(m, 1) : U32))) % nz(H.nth(m, 0)) : U32), ((sfc / nz((H.nth(m, 3) * H.nth(m, 2) : U32))) % nz(H.nth(m, 1)) : U32),
    ((sfc / nz(H.nth(m, 3))) % nz(H.nth(m, 2)) : U32), (sfc % nz(H.nth(m, 3)) : U32)]

def sizes.mpeg2(n: Nat, +sfc: U32, +k: U32) -> Sizes:
  match n:
    case 0n: Sizes{[0, 0, 0, 0], k}
    case 1n+rest:
      +m = List.drop(&2, U32, T.mod(), U32.to_nat(k))
      +product = (((H.nth(m, 0) * H.nth(m, 1)) * H.nth(m, 2)) * H.nth(m, 3) : U32)
      Bool.pick(Sizes, (sfc < product : U32), Sizes{sizes.row(sfc, m), (k + 4 : U32)}, sizes.mpeg2(rest, (sfc - U32.min(product, sfc) : U32), (k + 4 : U32)))

# The sizes of the four groups and where the granule's counts are in its
# partition: MPEG-1 from g_scfc_decode (two sizes, each for two groups),
# MPEG-2 from g_mod's rows (the three after the first three for the second
# channel of an intensity stereo frame, whose scalefac_compress is halved).
def sizes.of(mpeg1: Bool, +compress: U32, +ist: Bool) -> Sizes:
  match mpeg1:
    case True{}:
      +part = H.nth(T.scfc.decode(), compress)
      Sizes{[(part >> 2n : U32), (part >> 2n : U32), (part .&. 3 : U32), (part .&. 3 : U32)], 0}
    case False{}: sizes.mpeg2(3n, Bool.pick(U32, ist, (compress >> 1n : U32), compress), Bool.pick(U32, ist, 12, 0))

# The short blocks' scalefactors take their subblock's gain (as bytes).
def scf.gained(scf: +List<U32>, +g0: U32, +g1: U32, +g2: U32, acc: +List<U32>) -> +List<U32>:
  match scf:
    case Con{+a, Con{+b, Con{+c, rest}}}: scf.gained(rest, g0, g1, g2, Con{((c + g2) .&. 255 : U32), Con{((b + g1) .&. 255 : U32), Con{((a + g0) .&. 255 : U32), acc}}})
    case +tail: List.reverse.go(&2, U32, acc, tail)

# The long blocks' last ten of 21 take g_preamp.
def scf.preamp(scf: +List<U32>, amps: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match scf amps:
    case Con{+a, rest} Con{+amp, more}: scf.preamp(rest, more, Con{((a + amp) .&. 255 : U32), acc})
    case +tail _: List.reverse.go(&2, U32, acc, tail)

def take.rev(n: Nat, xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k:
      match xs:
        case Nil{}: acc
        case Con{+x, rest}: take.rev(k, rest, Con{x, acc})

# The first `n` scalefactors of a list, the short ones gained or the long
# ones pre-amplified.
def scf.adjusted(+iscf: +List<U32>, +long: U32, +short: U32, +preflag: Bool, +sh: U32, +g0: U32, +g1: U32, +g2: U32) -> +List<U32>:
  +head = List.reverse(&2, U32, take.rev(U32.to_nat(long), iscf, Nil{}))
  +tail = List.drop(&2, U32, iscf, U32.to_nat(long))
  Bool.pick(+List<U32>, U32.is_ne(short, 0),
    List.append(&2, U32, head, scf.gained(List.reverse(&2, U32, take.rev(U32.to_nat(short), tail, Nil{})), (g0 << U32.to_nat(sh) : U32), (g1 << U32.to_nat(sh) : U32), (g2 << U32.to_nat(sh) : U32), Nil{})),
    Bool.pick(+List<U32>, preflag, List.append(&2, U32, List.reverse(&2, U32, take.rev(11n, iscf, Nil{})), scf.preamp(List.drop(&2, U32, iscf, 11n), T.preamp(), Nil{})), iscf))

# scf[i] = ldexp_q2(gain, iscf[i] << scf_shift), as float bits, before `tail`:
# the scales past the granule's bands, which stay as they were.
def scf.floats(n: Nat, iscf: +List<U32>, +gain: F32, +shift: U32, acc: +List<U32>, +tail: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse.go(&2, U32, acc, tail)
    case 1n+rest:
      match iscf:
        case Nil{}: scf.floats(rest, Nil{}, gain, shift, Con{F32.bits(ldexp.q2(gain, 0)), acc}, tail)
        case Con{+value, more}: scf.floats(rest, more, gain, shift, Con{F32.bits(ldexp.q2(gain, (value << U32.to_nat(shift) : U32))), acc}, tail)

# What drmp3_L3_decode_scalefactors leaves: the bands' scales (float bits),
# the channel's intensity positions and the bit after the scalefactors.
type Scales is Data:
  Scales{scf: +List<U32>, ist: +List<U32>, pos: U32}

def scales.read(read: Read, +h: U32, +gr: H.Gr, +tail: +List<U32>) -> Scales:
  Read{+scf, +ist, +old, +pos} = read
  H.Gr{_, _, +gain, _, _, _, _, _, _, _, _, _, +sub0, +sub1, +sub2, +preflag, +scale, _, _, _, +long, +short} = gr
  +iscf = List.reverse.go(&2, U32, scf, [0, 0, 0])
  +exp = ((44 + 214) - (gain - Bool.pick(U32, U32.is_eq((H.b3(h) .&. 224 : U32), 96), 2, 0)) : U32)
  Scales{scf.floats(U32.to_nat((long + short : U32)), scf.adjusted(iscf, long, short, U32.is_ne(preflag, 0), (2 - scale : U32), sub0, sub1, sub2), ldexp.q2(2048.0, exp), (scale + 1 : U32), Nil{}, tail),
    List.reverse.go(&2, U32, ist, old), pos}

def scales.sized(sized: Sizes, +bytes: +List<U32>, +limit: U32, +pos: U32, +h: U32, +gr: H.Gr, +ist: +List<U32>, +partition: U32, +scfsi: U32, +tail: +List<U32>) -> Scales:
  Sizes{+sizes, +k} = sized
  +counts = List.drop(&2, U32, row(T.scf.partitions(), partition), U32.to_nat(k))
  scales.read(read.groups(4n, U32.is_eq(H.first(counts), 0), sizes, counts, bytes, limit, scfsi, Read{Nil{}, Nil{}, ist, pos}), h, gr, tail)

# drmp3_L3_decode_scalefactors for a granule of channel `ch`: `ist` is the
# channel's intensity positions (39 bytes; what the granule before left),
# `scf` the 40 scales as the granule before left them, `bytes` the main data
# and `pos` the bit the granule begins at.
def scales(+bytes: +List<U32>, +limit: U32, +pos: U32, +h: U32, +gr: H.Gr, +ist: +List<U32>, +scf: +List<U32>, +ch: U32) -> Scales:
  H.Gr{_, _, _, +compress, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +scfsi, _, +long, +short} = gr
  +sized = sizes.of(H.hdr.mpeg1(h), compress, U32.is_ne((H.b3(h) .&. 16 : U32), 0) && U32.is_ne(ch, 0))
  scales.sized(sized, bytes, limit, pos, h, gr, ist, Bool.pick(U32, U32.is_eq(short, 0), 0, Bool.pick(U32, U32.is_eq(long, 0), 2, 1)), Bool.pick(U32, H.hdr.mpeg1(h), scfsi, 4294967280),
    List.drop(&2, U32, scf, U32.to_nat((long + short : U32))))

def Scales.scf(scales: Scales) -> +List<U32>:
  Scales{scf, _, _} = scales
  scf

def Scales.ist(scales: Scales) -> +List<U32>:
  Scales{_, ist, _} = scales
  ist

def Scales.pos(scales: Scales) -> U32:
  Scales{_, _, pos} = scales
  pos

# -----------------------------------------------------------------------------
# Huffman (drmp3_L3_huffman)

# drmp3_L3_pow_43 past its table: x^(4/3) from the table's value at the
# nearest 64th (x times 8 below 1024), times a polynomial of what is left.
def pow43.far(+x: U32, +mult: F32, +pow: +List<U32>) -> F32:
  +sign = ((2 * x) .&. 64 : U32)
  +low = (x .&. 63 : U32)
  +frac = (Bool.pick(F32, U32.is_eq(sign, 0), U32.to_f32(low), F32.neg(U32.to_f32((64 - low : U32)))) / U32.to_f32(((x - low) + sign : U32)) : F32)
  +poly = (1.0 + (frac * ((4.0 / 3.0) + (frac * (2.0 / 9.0)))) : F32)
  ((float(H.nth(pow, (16 + ((x + sign) >> 6n) : U32))) * poly) * mult : F32)

def pow43.of(near: Bool, +x: U32, +pow: +List<U32>) -> F32:
  match near:
    case True{}: float(H.nth(pow, (16 + x : U32)))
    case False{}: Bool.pick(F32, (x < 1024 : U32), pow43.far((x << 3n : U32), 16.0, pow), pow43.far(x, 256.0, pow))

# drmp3_L3_pow_43(x); `pow` is g_drmp3_pow43.
def pow43(+x: U32, +pow: +List<U32>) -> F32:
  pow43.of((x < 129 : U32), x, pow)

# The reader within the main data and what it wrote: the bytes from
# bs_next_ptr on, bs_next_ptr's index, bs_cache, bs_sh + 8, and dst's values
# so far (float bits, the last first).
type Run is Data:
  Run{rest: +List<U32>, next: U32, cache: U32, sh: U32, out: +List<U32>}

# DRMP3_CHECK_BITS: bytes into the cache while there is room for one. A byte
# past the main data's array counts (the caller refuses the granule).
def run.fill(n: Nat, go: Bool, rest: +List<U32>, +next: U32, +cache: U32, +sh: U32, out: +List<U32>) -> Run:
  match n:
    case 0n: Run{rest, next, cache, sh, out}
    case 1n+k:
      match go:
        case False{}: Run{rest, next, cache, sh, out}
        case True{}:
          match rest:
            case Nil{}: run.fill(k, (sh >= 16 : U32), Nil{}, (next + 1 : U32), cache, (sh - 8 : U32), out)
            case Con{+byte, more}: run.fill(k, (sh >= 16 : U32), more, (next + 1 : U32), (cache .|. (byte << U32.to_nat((sh - 8 : U32))) : U32), (sh - 8 : U32), out)

# An escaped value after its linbits were flushed and the cache filled:
# one*pow_43(lsb), negative when the cache's first bit is set, and that bit.
def huff.escaped(run: Run, +lsb: U32, +one: F32, +pow: +List<U32>) -> Run:
  Run{rest, +next, +cache, +sh, out} = run
  Run{rest, next, (cache << 1n : U32), (sh + 1 : U32), Con{(F32.bits((one * pow43(lsb, pow) : F32)) .^. (cache .&. 2147483648) : U32), out}}

# One value of a pair: escaped (15 in a codebook with linbits), or
# g_drmp3_pow43[16 + lsb - 16*sign]*one and the sign's bit when it is not 0.
def huff.value(esc: Bool, +lsb: U32, +linbits: U32, +one: F32, +pow: +List<U32>, rest: +List<U32>, +next: U32, +cache: U32, +sh: U32, out: +List<U32>) -> Run:
  match esc:
    case True{}:
      huff.escaped(run.fill(5n, ((sh + linbits) >= 8 : U32), rest, next, (cache << U32.to_nat(linbits) : U32), (sh + linbits : U32), out), (lsb + (cache >> U32.to_nat((32 - linbits : U32))) : U32), one, pow)
    case False{}:
      +bit = U32.min(lsb, 1)
      Run{rest, next, (cache << U32.to_nat(bit) : U32), (sh + bit : U32), Con{F32.bits((float(H.nth(pow, ((16 + lsb) - (16 * (cache >> 31n)) : U32))) * one : F32)), out}}

def huff.second(run: Run, +lsb: U32, +linbits: U32, +one: F32, +pow: +List<U32>) -> Run:
  Run{rest, +next, +cache, +sh, out} = run
  huff.value(U32.is_eq(lsb, 15) && U32.is_ne(linbits, 0), lsb, linbits, one, pow, rest, next, cache, sh, out)

def huff.filled(run: Run) -> Run:
  Run{rest, +next, +cache, +sh, out} = run
  run.fill(5n, (sh >= 8 : U32), rest, next, cache, sh, out)

# A leaf: its length's bits flushed, its two values, DRMP3_CHECK_BITS.
def huff.pair(+leaf: U32, +linbits: U32, +one: F32, +pow: +List<U32>, rest: +List<U32>, +next: U32, +cache: U32, +sh: U32, out: +List<U32>) -> Run:
  +len = (leaf >> 8n : U32)
  +lsb = (leaf .&. 15 : U32)
  huff.filled(huff.second(huff.value(U32.is_eq(lsb, 15) && U32.is_ne(linbits, 0), lsb, linbits, one, pow, rest, next, (cache << U32.to_nat(len) : U32), (sh + len : U32), out),
    ((leaf >> 4n) .&. 15 : U32), linbits, one, pow))

# while (leaf < 0): w bits flushed, then the entry the next leaf & 7 bits
# choose, -(leaf >> 3) past the codebook's start (an int16 here is its 16-bit
# pattern). The codebooks' trees are at most six entries deep.
def huff.walk(n: Nat, neg: Bool, +leaf: U32, +book: +List<U32>, +w: U32, +linbits: U32, +one: F32, +pow: +List<U32>, rest: +List<U32>, +next: U32, +cache: U32, +sh: U32, out: +List<U32>) -> Run:
  match n:
    case 0n: huff.pair(leaf, linbits, one, pow, rest, next, cache, sh, out)
    case 1n+k:
      match neg:
        case False{}: huff.pair(leaf, linbits, one, pow, rest, next, cache, sh, out)
        case True{}:
          +flushed = (cache << U32.to_nat(w) : U32)
          +nw = (leaf .&. 7 : U32)
          +nleaf = H.nth(book, ((flushed >> U32.to_nat((32 - nw : U32))) + (8192 - (leaf >> 3n)) : U32))
          huff.walk(k, (nleaf >= 32768 : U32), nleaf, book, nw, linbits, one, pow, rest, next, flushed, (sh + w : U32), out)

# `n` pairs of a band from one codebook.
def huff.pairs(n: Nat, +book: +List<U32>, +linbits: U32, +one: F32, +pow: +List<U32>, run: Run) -> Run:
  match n:
    case 0n: run
    case 1n+k:
      Run{rest, +next, +cache, +sh, out} = run
      +leaf = H.nth(book, (cache >> 27n : U32))
      huff.pairs(k, book, linbits, one, pow, huff.walk(7n, (leaf >= 32768 : U32), leaf, book, 5, linbits, one, pow, rest, next, cache, sh, out))

def pick3(i: U32, +a: U32, +b: U32, +c: U32) -> U32:
  match i:
    case 0: a
    case 1: b
    case _: c

# A region's codebook when the band begins one (`turn`), or the one before.
def book.turned(turn: Bool, +tab: U32, +book: +List<U32>) -> +List<U32>:
  match turn:
    case True{}: T.book(tab)
    case False{}: book

# What the big values leave: the reader and the values, the bands and scales
# not begun, count1's np (1 and the pairs left of the last band) and the last
# band's scale.
type Big is Data:
  Big{run: Run, sfb: +List<U32>, scf: +List<U32>, np: U32, one: U32}

# while (big_val_cnt > 0): a band's pairs (as many as are left of
# big_values) from its region's codebook; a region is region_count[ireg] + 1
# bands. `fresh`: the band begins a region.
def big.bands(n: Nat, more: Bool, sfb: +List<U32>, +scf: +List<U32>, +big: U32, +ireg: U32, +cnt: U32, +fresh: Bool, +book: +List<U32>, +gr: H.Gr, +np: U32, +one: U32, +pow: +List<U32>, run: Run) -> Big:
  match n:
    case 0n: Big{run, sfb, scf, np, one}
    case 1n+k:
      match more:
        case False{}: Big{run, sfb, scf, np, one}
        case True{}:
          match sfb:
            case Nil{}: Big{run, Nil{}, scf, np, one}
            case Con{+width, rest}:
              H.Gr{_, _, _, _, _, _, +table0, +table1, +table2, _, +region1, +region2, _, _, _, _, _, _, _, _, _, _} = gr
              +half = (width / 2 : U32)
              +pairs = U32.min(big, half)
              +scale = H.first(scf)
              +tab = pick3(ireg, table0, table1, table2)
              +codes = book.turned(fresh, tab, book)
              +turn = U32.is_eq(cnt, 0)
              +after = Bool.pick(U32, turn, (ireg + 1 : U32), ireg)
              big.bands(k, (big > half : U32), rest, tail(scf), (big - pairs : U32), after, Bool.pick(U32, turn, pick3(after, 0, region1, region2), (cnt - 1 : U32)), turn, codes, gr,
                ((1 + half) - pairs : U32), scale, pow, huff.pairs(U32.to_nat(pairs), codes, H.nth(T.linbits(), tab), float(scale), pow, run))

# The band a pair of the count1 region is in: the one before while it has
# pairs (`last` false), or the next, and `ended` when there is none.
type Band is Data:
  Band{sfb: +List<U32>, scf: +List<U32>, np: U32, one: U32, ended: Bool}

# DRMP3_RELOAD_SCALEFACTOR
def band.next(last: Bool, sfb: +List<U32>, +scf: +List<U32>, +np: U32, +one: U32) -> Band:
  match last:
    case False{}: Band{sfb, scf, (np - 1 : U32), one, False{}}
    case True{}:
      match sfb:
        case Nil{}: Band{Nil{}, scf, 0, one, True{}}
        case Con{+width, rest}: Band{rest, tail(scf), (width / 2 : U32), Bool.pick(U32, (width < 2 : U32), one, H.first(scf)), (width < 2 : U32)}

# Two of a quad's values (DRMP3_DEQ_COUNT1 twice): plus or minus `one` (the
# cache's first bit, flushed) where the leaf has the value's bit (`hi`, `lo`:
# 0 or 1), or 0, which is what dst had.
def quad.pair(+hi: U32, +lo: U32, +one: U32, rest: +List<U32>, +next: U32, +cache: U32, +sh: U32, out: +List<U32>) -> Run:
  +mid = (cache << U32.to_nat(hi) : U32)
  Run{rest, next, (mid << U32.to_nat(lo) : U32), ((sh + hi) + lo : U32), Con{((one .^. (mid .&. 2147483648)) * lo : U32), Con{((one .^. (cache .&. 2147483648)) * hi : U32), out}}}

# A quad's step: the reader and the values, the bands, and `stop` when the
# loop ended in it.
type Quad is Data:
  Quad{run: Run, sfb: +List<U32>, scf: +List<U32>, np: U32, one: U32, stop: Bool}

def quad.second(band: Band, +leaf: U32, run: Run) -> Quad:
  match band:
    case Band{sfb, scf, +np, +one, True{}}: Quad{run, sfb, scf, np, one, True{}}
    case Band{sfb, scf, +np, +one, False{}}:
      Run{rest, +next, +cache, +sh, out} = run
      Quad{huff.filled(quad.pair(((leaf >> 5n) .&. 1 : U32), ((leaf >> 4n) .&. 1 : U32), one, rest, next, cache, sh, out)), sfb, scf, np, one, False{}}

def quad.first(band: Band, +leaf: U32, rest: +List<U32>, +next: U32, +cache: U32, +sh: U32, out: +List<U32>) -> Quad:
  match band:
    case Band{sfb, scf, +np, +one, True{}}: Quad{Run{rest, next, cache, sh, out}, sfb, scf, np, one, True{}}
    case Band{sfb, +scf, +np, +one, False{}}:
      quad.second(band.next(U32.is_eq(np, 1), sfb, scf, np, one), leaf, quad.pair(((leaf >> 7n) .&. 1 : U32), ((leaf >> 6n) .&. 1 : U32), one, rest, next, cache, sh, out))

# A quad whose leaf was flushed: nothing when the reader is past the
# granule's limit (`stop`); else two values of a band and two of a band.
def quad.step(stop: Bool, sfb: +List<U32>, +scf: +List<U32>, +np: U32, +one: U32, +leaf: U32, rest: +List<U32>, +next: U32, +cache: U32, +sh: U32, out: +List<U32>) -> Quad:
  match stop:
    case True{}: Quad{Run{rest, next, cache, sh, out}, sfb, scf, np, one, True{}}
    case False{}: quad.first(band.next(U32.is_eq(np, 1), sfb, scf, np, one), leaf, rest, next, cache, sh, out)

# The count1 region: quads from tab32 or tab33 (`book`) until the reader
# (DRMP3_BSPOS: bs_next_ptr*8 - 24 + bs_sh) is past the granule's limit or
# the bands end.
def count1.quads(n: Nat, state: Quad, +book: +List<U32>, +limit: U32) -> Run:
  match n:
    case 0n:
      Quad{run, _, _, _, _, _} = state
      run
    case 1n+k:
      match state:
        case Quad{run, _, _, _, _, True{}}: run
        case Quad{Run{rest, +next, +cache, +sh, out}, sfb, +scf, +np, +one, False{}}:
          +head = H.nth(book, (cache >> 28n : U32))
          +leaf = Bool.pick(U32, U32.is_ne((head .&. 8 : U32), 0), head, H.nth(book, ((head >> 3n) + ((cache << 4n) >> U32.to_nat((32 - U32.max((head .&. 3 : U32), 1) : U32))) : U32)))
          +used = (leaf .&. 7 : U32)
          count1.quads(k, quad.step((((next * 8) + (sh + used)) > (limit + 32) : U32), sfb, scf, np, one, leaf, rest, next, (cache << U32.to_nat(used) : U32), (sh + used : U32), out), book, limit)

def zeros.onto(n: Nat, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: zeros.onto(k, Con{0, acc})

# A granule's 576 values (float bits), and whether every byte read was in
# the main data's array.
type Spectrum is Data:
  Spectrum{values: +List<U32>, fine: Bool}

def spectrum.run(run: Run, +size: U32) -> Spectrum:
  Run{_, +next, _, _, +out} = run
  +count = H.count(out, 0)
  Spectrum{List.reverse.go(&2, U32, out, zeros.onto(U32.to_nat((576 - U32.min(count, 576) : U32)), Nil{})), (next <= size : U32)}

def spectrum.big(big: Big, +count1: U32, +limit: U32, +size: U32) -> Spectrum:
  Big{run, sfb, scf, +np, +one} = big
  spectrum.run(count1.quads(146n, Quad{run, sfb, scf, np, one, False{}}, Bool.pick(+List<U32>, U32.is_ne(count1, 0), T.tab33(), T.tab32()), limit), size)

# DRMP3_HDR_GET_MY_SAMPLE_RATE: the header's sample rate bits, three more
# for MPEG-2 and six for MPEG-1 (0 to 2 are MPEG-2.5's: 11025, 12000 and
# 8000 Hz).
def rate.index(+h: U32) -> U32:
  (((H.b2(h) >> 2n) .&. 3) + ((((H.b1(h) >> 3n) .&. 1) + ((H.b1(h) >> 4n) .&. 1)) * 3) : U32)

# The scalefactor band widths of a granule: the row of the frame's sample
# rate (DRMP3_HDR_GET_MY_SAMPLE_RATE, less one when it is not 0) of g_scf_long,
# g_scf_short or g_scf_mixed.
def bands(+h: U32, +kind: U32) -> +List<U32>:
  +rate = rate.index(h)
  +index = (rate - U32.min(rate, 1) : U32)
  row(Bool.pick(+List<+List<U32>>, U32.is_eq(kind, 0), T.scf.long(), Bool.pick(+List<+List<U32>>, U32.is_eq(kind, 1), T.scf.short(), T.scf.mixed())), index)

# drmp3_L3_huffman: a granule's values from the main data. `main` is the
# main data's array (the frame's bytes, then what frames before left there),
# `size` its length, `pos` the bit after the scalefactors, `limit` the bit
# the granule ends at and `scf` its scales. The big values are read however
# far they go; the quads of the count1 region stop at the limit.
def spectrum(+main: +List<U32>, +size: U32, +pos: U32, +limit: U32, +h: U32, +gr: H.Gr, +scf: +List<U32>) -> Spectrum:
  H.Gr{_, +big, _, _, _, _, _, _, _, +region0, _, _, _, _, _, _, _, +count1, _, +kind, _, _} = gr
  +at = List.drop(&2, U32, main, U32.to_nat((pos / 8 : U32)))
  spectrum.big(big.bands(40n, (big > 0 : U32), bands(h, kind), scf, big, 0, region0, True{}, Nil{}, gr, 1, 0, T.pow43(),
    Run{List.drop(&2, U32, at, 4n), ((pos / 8) + 4 : U32), (H.word(at) << U32.to_nat((pos .&. 7 : U32)) : U32), (pos .&. 7 : U32), Nil{}}), count1, limit, size)

def Spectrum.values(spectrum: Spectrum) -> +List<U32>:
  Spectrum{values, _} = spectrum
  values

def Spectrum.fine(spectrum: Spectrum) -> Bool:
  Spectrum{_, fine} = spectrum
  fine

# -----------------------------------------------------------------------------
# Frames (drmp3dec_decode_frame with its samples wanted).

# The decoder between frames: drmp3dec's header, free format size and
# reservoir (H.Dec), and what its scratch keeps from a frame to the next:
# the main data's array (2815 bytes: a frame's main data is written over the
# start of what was there, and the values are read from it however far they
# go), the 40 scales (a granule writes its bands'; a table of more bands
# reads what is past them), the channels' intensity positions (39 each) and
# scalefac_compress of the second slot of the granule information, which a
# mono frame does not write and whose stereo step reads; the IMDCT's
# overlap for each channel (mdct_overlap: nine floats a subband, 288); and
# the synthesis filter's last fifteen rows (qmf_state, the newest first).
type Decoder is Data:
  Decoder{dec: H.Dec, main: +List<U32>, scf: +List<U32>, ist0: +List<U32>, ist1: +List<U32>, compress: U32, overlap0: +List<U32>, overlap1: +List<U32>, qmf: +List<+List<U32>>}

# qmf_state zeroed: fifteen rows of 64.
def rows.zero(n: Nat, acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match n:
    case 0n: acc
    case 1n+k: rows.zero(k, Con{zeros.onto(64n, Nil{}), acc})

# A decoder zeroed: what drmp3dec_decode_frame makes of it before it
# searches for a frame.
def Decoder.zero() -> Decoder:
  Decoder{H.Dec.zero(), zeros.onto(2815n, Nil{}), zeros.onto(40n, Nil{}), zeros.onto(39n, Nil{}), zeros.onto(39n, Nil{}), 0, zeros.onto(288n, Nil{}), zeros.onto(288n, Nil{}), rows.zero(15n, Nil{})}

# What a frame gives: the decoder after it, its samples for a channel (0:
# none decoded), the bytes it used, `status`, the granules' subband samples
# (576 float bits for a channel of a granule, in the frame's order: 32
# subbands of 18 samples after the IMDCT and its sign change) and the
# frame's PCM (an int16's 16 bits a sample, a frame a channel after a
# channel). `status` is 0, or why the
# frame is refused. 1: dr_mp3 leaves one of its arrays, which is undefined:
# a granule's values were read past the main data's (it reads whatever
# follows in its struct), or a granule is a mixed block at 8000 Hz
# (reorder.inside). A Layer I or II frame (src/mp3_layer12.bend) has no
# spectra.
type Decoded is Data:
  Decoded{decoder: Decoder, samples: U32, bytes: U32, status: U32, spectra: +List<+List<U32>>, pcm: +List<U32>}

def total(xs: +List<U32>, +sum: U32) -> U32:
  match xs:
    case Nil{}: sum
    case Con{+x, rest}: total(rest, (sum + x : U32))

# n_long_bands of drmp3_L3_decode: the subbands a granule with the mixed
# block flag transforms as long ones, two, or four at 8000 Hz.
def long.subbands(+h: U32, +mixed: U32) -> U32:
  Bool.pick(U32, U32.is_eq(mixed, 0), 0, Bool.pick(U32, U32.is_eq(rate.index(h), 2), 4, 2))

# Whether drmp3_L3_reorder stays inside a granule's 576 values. It moves a
# granule's short bands, which begin after the long part: 18 values for each
# of a mixed block's long subbands, two of them, or four at 8000 Hz. There
# the mixed table's long bands are 48 values and its short bands 528, which
# from value 72 end 24 past the granule: dr_mp3 writes them over the other
# channel's values or over the scales (undefined), and the granule is
# refused. Every other table ends at 576.
def reorder.inside(+h: U32, +gr: H.Gr) -> Bool:
  H.Gr{_, _, _, _, _, +mixed, _, _, _, _, _, _, _, _, _, _, _, _, _, +kind, +long, +short} = gr
  U32.is_eq(short, 0) || (((long.subbands(h, mixed) * 18) + total(List.drop(&2, U32, bands(h, kind), U32.to_nat(long)), 0)) <= 576 : U32)

# A channel of a granule: the bit after it, the channel's intensity
# positions and the scales as its scalefactors leave them, whether dr_mp3
# stays inside its arrays for it (its values read inside the main data's,
# its short bands reordered inside the granule's), and the values.
type Channel is Data:
  Channel{pos: U32, ist: +List<U32>, scf: +List<U32>, fine: Bool, values: +List<U32>}

def channel.values(values: Spectrum, +pos: U32, +ist: +List<U32>, +scf: +List<U32>, +inside: Bool) -> Channel:
  Spectrum{values, +fine} = values
  Channel{pos, ist, scf, fine && inside, values}

# drmp3_L3_decode_scalefactors, then drmp3_L3_huffman to the granule's limit.
def channel(+main: +List<U32>, +limit: U32, +pos: U32, +h: U32, +gr: H.Gr, +ist: +List<U32>, +scf: +List<U32>, +ch: U32) -> Channel:
  +scaled = scales(main, limit, pos, h, gr, ist, scf, ch)
  +after = (pos + H.Gr.part23(gr) : U32)
  channel.values(spectrum(main, 2815, Scales.pos(scaled), after, h, gr, Scales.scf(scaled)), after, Scales.ist(scaled), Scales.scf(scaled), reorder.inside(h, gr))

# Whether any of the first `n` values is not 0 (a float: any bit but its sign).
def loud(n: Nat, xs: +List<U32>) -> Bool:
  match n:
    case 0n: False{}
    case 1n+k:
      match xs:
        case Nil{}: False{}
        case Con{+x, rest}: U32.is_ne((x .&. 2147483647 : U32), 0) || loud(k, rest)

# drmp3_L3_stereo_top_band: for each of the three windows (a band's index
# modulo 3), one more than the last of the first `n` bands in which the
# right channel has a value that is not 0, or 0 when there is none.
type Tops is Data:
  Tops{a: U32, b: U32, c: U32}

def tops(n: Nat, sfb: +List<U32>, +right: +List<U32>, +i: U32, +a: U32, +b: U32, +c: U32) -> Tops:
  match n:
    case 0n: Tops{a, b, c}
    case 1n+k:
      match sfb:
        case Nil{}: Tops{a, b, c}
        case Con{+width, rest}:
          +on = loud(U32.to_nat(width), right)
          tops(k, rest, List.drop(&2, U32, right, U32.to_nat(width)), (i + 1 : U32), Bool.pick(U32, on && U32.is_eq((i % 3 : U32), 0), (i + 1 : U32), a),
            Bool.pick(U32, on && U32.is_eq((i % 3 : U32), 1), (i + 1 : U32), b), Bool.pick(U32, on && U32.is_eq((i % 3 : U32), 2), (i + 1 : U32), c))

# A window's position: the default where the right channel has a value in
# the band before or past it (max_band[i] >= prev), else that band's.
def position(+ist: +List<U32>, +top: U32, +prev: U32, +default: U32) -> U32:
  Bool.pick(U32, (top > prev : U32), default, H.nth(ist, prev))

# The top bands as drmp3_L3_intensity_stereo uses them: a granule with long
# bands has one for its three windows, the highest.
def tops.merged(tops: Tops, +long: U32) -> Tops:
  Tops{+a, +b, +c} = tops
  +shared = U32.max(a, U32.max(b, c))
  Tops{Bool.pick(U32, U32.is_eq(long, 0), a, shared), Bool.pick(U32, U32.is_eq(long, 0), b, shared), Bool.pick(U32, U32.is_eq(long, 0), c, shared)}

# What drmp3_L3_intensity_stereo writes of the right channel's intensity
# positions before it uses them: those of the last band of each window (one
# window without short blocks), from the right channel's top bands. `n` is
# the left channel's band count and `short` its short bands; the default is
# 3 in MPEG-1 and 0 in MPEG-2.
def positions(tops: Tops, +ist: +List<U32>, +n: U32, +short: U32, +default: U32) -> +List<U32>:
  Tops{+a, +b, +c} = tops
  +blocks = Bool.pick(U32, U32.is_eq(short, 0), 1, 3)
  +prev = (n - (2 * blocks) : U32)
  +tail = List.drop(&2, U32, ist, U32.to_nat(n))
  List.append(&2, U32, H.take((n - blocks : U32), ist), Bool.pick(+List<U32>, U32.is_eq(short, 0), Con{position(ist, a, prev, default), tail},
    Con{position(ist, a, prev, default), Con{position(ist, b, (prev + 1 : U32), default), Con{position(ist, c, (prev + 2 : U32), default), tail}}}))

# -----------------------------------------------------------------------------
# Stereo (drmp3_L3_midside_stereo, drmp3_L3_stereo_process)

# Two channels' values being rewritten: what is left of each, and what is
# done of each (the last first).
type Both is Data:
  Both{left: +List<U32>, right: +List<U32>, done0: +List<U32>, done1: +List<U32>}

# `n` values as they are. A mono frame's right channel is zeros.
def pair.kept(n: Nat, left: +List<U32>, +right: +List<U32>, al: +List<U32>, ar: +List<U32>) -> Both:
  match n:
    case 0n: Both{left, right, al, ar}
    case 1n+k:
      match left:
        case Nil{}: Both{Nil{}, right, al, ar}
        case Con{+a, rest}: pair.kept(k, rest, tail(right), Con{a, al}, Con{H.first(right), ar})

# drmp3_L3_midside_stereo on `n` values: left a + b, right a - b.
def pair.midside(n: Nat, left: +List<U32>, +right: +List<U32>, al: +List<U32>, ar: +List<U32>) -> Both:
  match n:
    case 0n: Both{left, right, al, ar}
    case 1n+k:
      match left:
        case Nil{}: Both{Nil{}, right, al, ar}
        case Con{+a, rest}:
          pair.midside(k, rest, tail(right), Con{F32.bits((float(a) + float(H.first(right)) : F32)), al}, Con{F32.bits((float(a) - float(H.first(right)) : F32)), ar})

# drmp3_L3_intensity_stereo_band on `n` values: right is left times kr, then
# left is left times kl.
def pair.intensity(n: Nat, left: +List<U32>, +right: +List<U32>, +kl: F32, +kr: F32, al: +List<U32>, ar: +List<U32>) -> Both:
  match n:
    case 0n: Both{left, right, al, ar}
    case 1n+k:
      match left:
        case Nil{}: Both{Nil{}, right, al, ar}
        case Con{+a, rest}: pair.intensity(k, rest, tail(right), kl, kr, Con{F32.bits((float(a) * kl : F32)), al}, Con{F32.bits((float(a) * kr : F32)), ar})

# The channels after their bands: what is done, then what no band covered.
def pair.left(pair: Both) -> +List<U32>:
  Both{left, _, al, _} = pair
  List.reverse.go(&2, U32, al, left)

def pair.right(pair: Both) -> +List<U32>:
  Both{_, right, _, ar} = pair
  List.reverse.go(&2, U32, ar, right)

# kl of an intensity band at position `ipos`, times `s` (the square root of
# two when the header's mid/side bit is set, else 1): MPEG-1's is g_pan's;
# MPEG-2's is 1, or for an odd position 2^(-e/4) with e the position's half,
# rounded up, shifted by `sh`.
def pan.left(mpeg1: Bool, +ipos: U32, +sh: U32, +s: F32, +table: +List<U32>) -> F32:
  match mpeg1:
    case True{}: (float(H.nth(table, (2 * ipos : U32))) * s : F32)
    case False{}: (Bool.pick(F32, U32.is_eq((ipos .&. 1 : U32), 0), 1.0, ldexp.q2(1.0, (((ipos + 1) >> 1n) << U32.to_nat(sh) : U32))) * s : F32)

# kr: g_pan's, or MPEG-2's 2^(-e/4) for an even position and 1 for an odd one.
def pan.right(mpeg1: Bool, +ipos: U32, +sh: U32, +s: F32, +table: +List<U32>) -> F32:
  match mpeg1:
    case True{}: (float(H.nth(table, ((2 * ipos) + 1 : U32))) * s : F32)
    case False{}: (Bool.pick(F32, U32.is_eq((ipos .&. 1 : U32), 0), ldexp.q2(1.0, (((ipos + 1) >> 1n) << U32.to_nat(sh) : U32)), 1.0) * s : F32)

# A band of drmp3_L3_stereo_process. 0: as it is; 1: an intensity band; 2:
# mid/side.
def stereo.band(mode: U32, n: Nat, +ipos: U32, +mpeg1: Bool, +sh: U32, +s: F32, +table: +List<U32>, pair: Both) -> Both:
  match mode:
    case 0:
      Both{left, +right, al, ar} = pair
      pair.kept(n, left, right, al, ar)
    case 1:
      Both{left, +right, al, ar} = pair
      pair.intensity(n, left, right, pan.left(mpeg1, ipos, sh, s, table), pan.right(mpeg1, ipos, sh, s, table), al, ar)
    case _:
      Both{left, +right, al, ar} = pair
      pair.midside(n, left, right, al, ar)

# drmp3_L3_stereo_process: every band of the table, to its 0. A band past
# the right channel's top band of its window, with a position below 7
# (MPEG-1) or 64, is an intensity band; another is mid/side when the header's
# bit is set (`ms`), whatever the frame's mode.
def stereo.bands(n: Nat, stop: Bool, sfb: +List<U32>, +ist: +List<U32>, +i: U32, +tops: Tops, +mpeg1: Bool, +sh: U32, +ms: Bool, +table: +List<U32>, pair: Both) -> Both:
  match n:
    case 0n: pair
    case 1n+k:
      match stop:
        case True{}: pair
        case False{}:
          match sfb:
            case Nil{}: pair
            case Con{+width, +rest}:
              Tops{+a, +b, +c} = tops
              +ipos = H.first(ist)
              +intense = (i >= pick3((i % 3 : U32), a, b, c) : U32) && (ipos < Bool.pick(U32, mpeg1, 7, 64) : U32)
              stereo.bands(k, U32.is_eq(H.first(rest), 0), rest, tail(ist), (i + 1 : U32), tops, mpeg1, sh, ms, table,
                stereo.band(Bool.pick(U32, intense, 1, Bool.pick(U32, ms, 2, 0)), U32.to_nat(width), ipos, mpeg1, sh, Bool.pick(F32, ms, float(1068827891), 1.0), table, pair))

# A granule's channels (the first loop of drmp3_L3_decode, and the positions
# drmp3_L3_intensity_stereo writes): the bit after them, the channels'
# intensity positions, the scales, whether every read was inside the array,
# and the channels' values (no right channel in a mono frame).
type Channels is Data:
  Channels{pos: U32, ist0: +List<U32>, ist1: +List<U32>, scf: +List<U32>, fine: Bool, left: +List<U32>, right: +List<U32>}

def Channels.pos(channels: Channels) -> U32:
  Channels{pos, _, _, _, _, _, _} = channels
  pos

def Channels.ist0(channels: Channels) -> +List<U32>:
  Channels{_, ist0, _, _, _, _, _} = channels
  ist0

def Channels.ist1(channels: Channels) -> +List<U32>:
  Channels{_, _, ist1, _, _, _, _} = channels
  ist1

def Channels.scf(channels: Channels) -> +List<U32>:
  Channels{_, _, _, scf, _, _, _} = channels
  scf

def Channels.fine(channels: Channels) -> Bool:
  Channels{_, _, _, _, fine, _, _} = channels
  fine

def Channels.left(channels: Channels) -> +List<U32>:
  Channels{_, _, _, _, _, left, _} = channels
  left

def Channels.right(channels: Channels) -> +List<U32>:
  Channels{_, _, _, _, _, _, right} = channels
  right

def granule.second(right: Channel, +ist0: +List<U32>, +fine0: Bool, +left: +List<U32>) -> Channels:
  Channel{+pos, ist1, scf, +fine, values} = right
  Channels{pos, ist0, ist1, scf, fine0 && fine, left, values}

def granule.stereo(left: Channel, +gr1: H.Gr, +main: +List<U32>, +limit: U32, +h: U32, +ist1: +List<U32>) -> Channels:
  Channel{+pos, +ist0, +scf, +fine, +values} = left
  granule.second(channel(main, limit, pos, h, gr1, ist1, scf, 1), ist0, fine, values)

def granule.mono(left: Channel, +ist1: +List<U32>) -> Channels:
  Channel{+pos, ist0, scf, +fine, values} = left
  Channels{pos, ist0, ist1, scf, fine, values, Nil{}}

def granule.channels(mono: Bool, +gr0: H.Gr, +gr1: H.Gr, +main: +List<U32>, +limit: U32, +pos: U32, +h: U32, +ist0: +List<U32>, +ist1: +List<U32>, +scf: +List<U32>) -> Channels:
  match mono:
    case True{}: granule.mono(channel(main, limit, pos, h, gr0, ist0, scf, 0), ist1)
    case False{}: granule.stereo(channel(main, limit, pos, h, gr0, ist0, scf, 0), gr1, main, limit, h, ist1)

# drmp3_L3_intensity_stereo: the right channel's last positions, then the
# bands. `sh` is the low bit of scalefac_compress in the slot after the
# granule's first: the right channel's, or in a mono frame what an earlier
# frame left there (Decoder.compress).
def stereo.intensity(+tops: Tops, channels: Channels, +gr0: H.Gr, +h: U32, +sh: U32) -> Channels:
  Channels{+pos, ist0, +ist1, scf, +fine, +left, +right} = channels
  H.Gr{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +kind, +long, +short} = gr0
  +placed = positions(tops, ist1, (long + short : U32), short, Bool.pick(U32, H.hdr.mpeg1(h), 3, 0))
  +done = stereo.bands(40n, False{}, bands(h, kind), placed, 0, tops, H.hdr.mpeg1(h), sh, U32.is_ne((H.b3(h) .&. 32 : U32), 0), T.pan(), Both{left, right, Nil{}, Nil{}})
  Channels{pos, ist0, placed, scf, fine, pair.left(done), pair.right(done)}

def stereo.midside(channels: Channels) -> Channels:
  Channels{+pos, ist0, ist1, scf, +fine, +left, +right} = channels
  +done = pair.midside(576n, left, right, Nil{}, Nil{})
  Channels{pos, ist0, ist1, scf, fine, pair.left(done), pair.right(done)}

# The stereo step of drmp3_L3_decode. 1: the header's intensity bit, tested
# whatever the frame's mode (a mono frame's right channel is 576 zeros, and
# its values are scaled as a left channel's); 2: mid/side, in a joint stereo
# frame without that bit; 0: nothing.
def stereo(mode: U32, +channels: Channels, +gr0: H.Gr, +h: U32, +sh: U32) -> Channels:
  match mode:
    case 0: channels
    case 1:
      H.Gr{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +kind, +long, +short} = gr0
      stereo.intensity(tops.merged(tops(U32.to_nat((long + short : U32)), bands(h, kind), Channels.right(channels), 0, 0, 0, 0), long), channels, gr0, h, sh)
    case _: stereo.midside(channels)

# Which stereo step a header asks for (DRMP3_HDR_TEST_I_STEREO, then
# DRMP3_HDR_IS_MS_STEREO).
def stereo.mode(+h: U32) -> U32:
  Bool.pick(U32, U32.is_ne((H.b3(h) .&. 16 : U32), 0), 1, Bool.pick(U32, U32.is_eq((H.b3(h) .&. 224 : U32), 96), 2, 0))

def granule(mono: Bool, +gr0: H.Gr, +gr1: H.Gr, +main: +List<U32>, +limit: U32, +pos: U32, +h: U32, +ist0: +List<U32>, +ist1: +List<U32>, +scf: +List<U32>, +sh: U32) -> Channels:
  stereo(stereo.mode(h), granule.channels(mono, gr0, gr1, main, limit, pos, h, ist0, ist1, scf), gr0, h, sh)

# -----------------------------------------------------------------------------
# Reorder, alias reduction, IMDCT (drmp3_L3_reorder, drmp3_L3_antialias,
# drmp3_L3_imdct_gr, drmp3_L3_change_sign)

# -x: the sign bit turned, as C negates a float (0 - x would keep a zero's sign).
def neg(x: F32) -> F32:
  float((F32.bits(x) .^. 2147483648 : U32))

# `n` values moved from a list onto another (the last first), and the rest.
type Moved is Data:
  Moved{rest: +List<U32>, done: +List<U32>}

def moved(n: Nat, xs: +List<U32>, acc: +List<U32>) -> Moved:
  match n:
    case 0n: Moved{xs, acc}
    case 1n+k:
      match xs:
        case Nil{}: Moved{Nil{}, acc}
        case Con{+x, rest}: moved(k, rest, Con{x, acc})

# drmp3_L3_reorder for one band of three windows: the windows' values are one
# after another (a, then b, then c, `n` each) and become a0 b0 c0 a1 b1 c1...
def reorder.band(n: Nat, a: +List<U32>, +b: +List<U32>, +c: +List<U32>, acc: +List<U32>) -> Moved:
  match n:
    case 0n: Moved{c, acc}
    case 1n+k:
      match a:
        case Nil{}: Moved{Nil{}, acc}
        case Con{+x, rest}: reorder.band(k, rest, tail(b), tail(c), Con{H.first(c), Con{H.first(b), Con{x, acc}}})

# The short bands from the first on, three windows of a width at a time, to
# the table's 0. `state` is what is left and what is done.
def reorder.bands(n: Nat, stop: Bool, sfb: +List<U32>, state: Moved) -> Moved:
  match n:
    case 0n: state
    case 1n+k:
      match stop:
        case True{}: state
        case False{}:
          match sfb:
            case Con{+width, Con{_, Con{_, +rest}}}:
              Moved{+values, acc} = state
              reorder.bands(k, U32.is_eq(H.first(rest), 0), rest,
                reorder.band(U32.to_nat(width), values, List.drop(&2, U32, values, U32.to_nat(width)), List.drop(&2, U32, values, U32.to_nat((2 * width : U32))), acc))
            case _: state

def moved.whole(state: Moved) -> +List<U32>:
  Moved{rest, done} = state
  List.reverse.go(&2, U32, done, rest)

# drmp3_L3_reorder: a short or mixed granule's values with the short bands'
# windows interleaved; `start` values of long bands come first as they are.
def reorder(+values: +List<U32>, +start: U32, +sfb: +List<U32>) -> +List<U32>:
  moved.whole(reorder.bands(14n, U32.is_eq(H.first(sfb), 0), sfb, moved(U32.to_nat(start), values, Nil{})))

# One boundary of drmp3_L3_antialias: `d` is the eight values below it, the
# nearest first, and `u` the eight above it. The new values below go onto
# `down` (so the nearest ends last: the order they have in the granule) and
# those above onto `up` (the nearest first: reversed).
type Alias is Data:
  Alias{down: +List<U32>, up: +List<U32>}

def alias.pairs(d: +List<U32>, +u: +List<U32>, +c0: +List<U32>, +c1: +List<U32>, down: +List<U32>, up: +List<U32>) -> Alias:
  match d:
    case Nil{}: Alias{down, up}
    case Con{+low, rest}:
      alias.pairs(rest, tail(u), tail(c0), tail(c1),
        Con{F32.bits(((float(H.first(u)) * float(H.first(c1))) + (float(low) * float(H.first(c0))) : F32)), down},
        Con{F32.bits(((float(H.first(u)) * float(H.first(c0))) - (float(low) * float(H.first(c1))) : F32)), up})

# What a boundary leaves: the values past it and what is done, with the
# sixteen new values in their places (the list done is the last first).
def alias.joined(alias: Alias, +rest: +List<U32>, +below: +List<U32>) -> Moved:
  Alias{down, up} = alias
  Moved{rest, List.append(&2, U32, up, List.reverse.go(&2, U32, down, below))}

# The ten values after a boundary's eight: the upper subband's others.
def alias.next(state: Moved) -> Moved:
  Moved{rest, done} = state
  moved(10n, rest, done)

# drmp3_L3_antialias, a boundary between two subbands at a time: the state
# has the lower subband done, so its last eight values are the first eight
# of the list done, the nearest first; ten more values follow each boundary.
def alias.bands(n: Nat, state: Moved, +c0: +List<U32>, +c1: +List<U32>) -> Moved:
  match n:
    case 0n: state
    case 1n+k:
      Moved{+rest, +done} = state
      alias.bands(k, alias.next(alias.joined(alias.pairs(H.take(8, done), rest, c0, c1, Nil{}, Nil{}), List.drop(&2, U32, rest, 8n), List.drop(&2, U32, done, 8n))), c0, c1)

# aa_bands of drmp3_L3_decode: the boundaries the alias reduction crosses.
# All 31 without short bands; with them, those inside the long subbands.
def alias.count(+short: U32, +nlong: U32) -> U32:
  Bool.pick(U32, U32.is_eq(short, 0), 31, (nlong - U32.min(nlong, 1) : U32))

# drmp3_L3_antialias over `n` boundaries from the granule's first subband.
def antialias(+values: +List<U32>, +n: U32) -> +List<U32>:
  moved.whole(alias.bands(U32.to_nat(n), moved(18n, values, Nil{}), row(T.aa(), 0), row(T.aa(), 1)))

# Nine floats: a column of drmp3_L3_imdct36.
type Nine is Data:
  Nine{a0: F32, a1: F32, a2: F32, a3: F32, a4: F32, a5: F32, a6: F32, a7: F32, a8: F32}

# drmp3_L3_dct3_9, in its order of operations.
def dct3.nine(y: Nine) -> Nine:
  Nine{+y0, +y1, +y2, +y3, +y4, +y5, +y6, +y7, +y8} = y
  +t0 = (y0 + (y6 * 0.5) : F32)
  +s0 = (y0 - y6 : F32)
  +t4 = ((y4 + y2) * float(T.c.cos20()) : F32)
  +t2 = ((y8 + y2) * float(T.c.cos40()) : F32)
  +s6 = ((y4 - y8) * float(T.c.cos80()) : F32)
  +s4 = (y4 + (y8 - y2) : F32)
  +s2 = (s0 - (s4 * 0.5) : F32)
  +s8 = ((t0 - t2) + s6 : F32)
  +e0 = ((t0 - t4) + t2 : F32)
  +e4 = ((t0 + t4) - s6 : F32)
  +s3 = (y3 * float(T.c.cos30()) : F32)
  +u0 = ((y5 + y1) * float(T.c.cos10()) : F32)
  +u4 = ((y5 - y7) * float(T.c.cos70()) : F32)
  +u2 = ((y1 + y7) * float(T.c.cos50()) : F32)
  +s1 = (((y1 - y5) - y7) * float(T.c.cos30()) : F32)
  +s5 = ((u0 - s3) - u2 : F32)
  +s7 = ((u4 - s3) - u0 : F32)
  +e3 = ((u4 + s3) - u2 : F32)
  Nine{(e4 - s7 : F32), (s2 + s1 : F32), (e0 - e3 : F32), (s8 + s5 : F32), (s4 + s0 : F32), (s8 - s5 : F32), (e0 + e3 : F32), (s2 - s1 : F32), (e4 + s7 : F32)}

# A column as a list of float bits; the sine column's odd entries change sign.
def nine.cos(nine: Nine) -> +List<U32>:
  Nine{a0, a1, a2, a3, a4, a5, a6, a7, a8} = nine
  [F32.bits(a0), F32.bits(a1), F32.bits(a2), F32.bits(a3), F32.bits(a4), F32.bits(a5), F32.bits(a6), F32.bits(a7), F32.bits(a8)]

def nine.sin(nine: Nine) -> +List<U32>:
  Nine{a0, a1, a2, a3, a4, a5, a6, a7, a8} = nine
  [F32.bits(a0), F32.bits(neg(a1)), F32.bits(a2), F32.bits(neg(a3)), F32.bits(a4), F32.bits(neg(a5)), F32.bits(a6), F32.bits(neg(a7)), F32.bits(a8)]

# What a subband's transform leaves: the granule's values done (the last
# first) and the overlap done (the last first).
type Out is Data:
  Out{values: +List<U32>, overlap: +List<U32>}

# The nine steps that end drmp3_L3_imdct36 for a subband: with the overlap
# `ovl`, the columns co and si, g_twid9's halves and the window's,
# overlap[i] = co*twid[i] - si*twid[9 + i], and the outputs i and 17 - i
# from the old overlap and sum = co*twid[9 + i] + si*twid[i]. `back` takes
# the outputs 17 - i, which end in order.
def imdct36.steps(co: +List<U32>, +si: +List<U32>, +ovl: +List<U32>, +t0: +List<U32>, +t1: +List<U32>, +w0: +List<U32>, +w1: +List<U32>, values: +List<U32>, back: +List<U32>, over: +List<U32>) -> Out:
  match co:
    case Nil{}: Out{List.reverse.go(&2, U32, back, values), over}
    case Con{+c, rest}:
      +s = float(H.first(si))
      +sum = ((float(c) * float(H.first(t1))) + (s * float(H.first(t0))) : F32)
      +old = float(H.first(ovl))
      imdct36.steps(rest, tail(si), tail(ovl), tail(t0), tail(t1), tail(w0), tail(w1),
        Con{F32.bits(((old * float(H.first(w0))) - (sum * float(H.first(w1))) : F32)), values},
        Con{F32.bits(((old * float(H.first(w1))) + (sum * float(H.first(w0))) : F32)), back},
        Con{F32.bits(((float(c) * float(H.first(t0))) - (s * float(H.first(t1))) : F32)), over})

# drmp3_L3_imdct36 for one subband of eighteen values: `window` is a row of
# g_mdct_window and `twid` g_twid9.
def imdct36(+g0: F32, +g1: F32, +g2: F32, +g3: F32, +g4: F32, +g5: F32, +g6: F32, +g7: F32, +g8: F32, +g9: F32, +g10: F32, +g11: F32, +g12: F32, +g13: F32, +g14: F32, +g15: F32, +g16: F32, +g17: F32, +ovl: +List<U32>, +twid: +List<U32>, +window: +List<U32>, values: +List<U32>, over: +List<U32>) -> Out:
  imdct36.steps(
    nine.cos(dct3.nine(Nine{neg(g0), (g1 + g2 : F32), neg((g3 + g4 : F32)), (g5 + g6 : F32), neg((g7 + g8 : F32)), (g9 + g10 : F32), neg((g11 + g12 : F32)), (g13 + g14 : F32), neg((g15 + g16 : F32))})),
    nine.sin(dct3.nine(Nine{g17, (g16 - g15 : F32), (g13 - g14 : F32), (g12 - g11 : F32), (g9 - g10 : F32), (g8 - g7 : F32), (g5 - g6 : F32), (g4 - g3 : F32), (g1 - g2 : F32)})),
    ovl, twid, List.drop(&2, U32, twid, 9n), window, List.drop(&2, U32, window, 9n), values, Nil{}, over)

# drmp3_L3_imdct12 for a window of a short block: six outputs and the three
# values that become the overlap. x0 to x15 are the window's six values,
# v0 to v2 the overlap it reads, t0 to t5 g_twid3.
type Twelve is Data:
  Twelve{d0: F32, d1: F32, d2: F32, d3: F32, d4: F32, d5: F32, n0: F32, n1: F32, n2: F32}

def imdct12.sums(+c0: F32, +c1: F32, +c2: F32, +s0: F32, +s1: F32, +s2: F32, +v0: F32, +v1: F32, +v2: F32, +t0: F32, +t1: F32, +t2: F32, +t3: F32, +t4: F32, +t5: F32) -> Twelve:
  +sum0 = ((c0 * t3) + (s0 * t0) : F32)
  +sum1 = ((c1 * t4) + (s1 * t1) : F32)
  +sum2 = ((c2 * t5) + (s2 * t2) : F32)
  Twelve{((v0 * t2) - (sum0 * t5) : F32), ((v1 * t1) - (sum1 * t4) : F32), ((v2 * t0) - (sum2 * t3) : F32), ((v2 * t3) + (sum2 * t0) : F32), ((v1 * t4) + (sum1 * t1) : F32), ((v0 * t5) + (sum0 * t2) : F32),
    ((c0 * t0) - (s0 * t3) : F32), ((c1 * t1) - (s1 * t4) : F32), ((c2 * t2) - (s2 * t5) : F32)}

# drmp3_L3_idct3 twice: co from (-x0, x6 + x3, x12 + x9) and si from
# (x15, x12 - x9, x6 - x3), whose middle changes sign.
def imdct12(+x0: F32, +x3: F32, +x6: F32, +x9: F32, +x12: F32, +x15: F32, +v0: F32, +v1: F32, +v2: F32, +t0: F32, +t1: F32, +t2: F32, +t3: F32, +t4: F32, +t5: F32) -> Twelve:
  +cm = ((x6 + x3) * float(T.c.cos30()) : F32)
  +ca = (neg(x0) - ((x12 + x9) * 0.5) : F32)
  +sm = ((x12 - x9) * float(T.c.cos30()) : F32)
  +sa = (x15 - ((x6 - x3) * 0.5) : F32)
  imdct12.sums((ca + cm : F32), (neg(x0) + (x12 + x9) : F32), (ca - cm : F32), (sa + sm : F32), neg((x15 + (x6 - x3) : F32)), (sa - sm : F32), v0, v1, v2, t0, t1, t2, t3, t4, t5)

# drmp3_L3_imdct_short for one subband: its three windows are every third
# value. The first six outputs are the overlap's first six; the first
# window's transform reads the overlap's last three and gives the next six
# outputs, the second reads what the first left there and gives the last
# six, and the third gives the new overlap whole.
def short.last(c: Twelve, values: +List<U32>, over: +List<U32>) -> Out:
  Twelve{d0, d1, d2, d3, d4, d5, n0, n1, n2} = c
  Out{values, Con{F32.bits(n2), Con{F32.bits(n1), Con{F32.bits(n0), Con{F32.bits(d5), Con{F32.bits(d4), Con{F32.bits(d3), Con{F32.bits(d2), Con{F32.bits(d1), Con{F32.bits(d0), over}}}}}}}}}}

def short.third(b: Twelve, +g2: F32, +g5: F32, +g8: F32, +g11: F32, +g14: F32, +g17: F32, +t0: F32, +t1: F32, +t2: F32, +t3: F32, +t4: F32, +t5: F32, values: +List<U32>, over: +List<U32>) -> Out:
  Twelve{d0, d1, d2, d3, d4, d5, +n0, +n1, +n2} = b
  short.last(imdct12(g2, g5, g8, g11, g14, g17, n0, n1, n2, t0, t1, t2, t3, t4, t5), Con{F32.bits(d5), Con{F32.bits(d4), Con{F32.bits(d3), Con{F32.bits(d2), Con{F32.bits(d1), Con{F32.bits(d0), values}}}}}}, over)

def short.second(a: Twelve, +g1: F32, +g2: F32, +g4: F32, +g5: F32, +g7: F32, +g8: F32, +g10: F32, +g11: F32, +g13: F32, +g14: F32, +g16: F32, +g17: F32, +t0: F32, +t1: F32, +t2: F32, +t3: F32, +t4: F32, +t5: F32, values: +List<U32>, over: +List<U32>) -> Out:
  Twelve{d0, d1, d2, d3, d4, d5, +n0, +n1, +n2} = a
  short.third(imdct12(g1, g4, g7, g10, g13, g16, n0, n1, n2, t0, t1, t2, t3, t4, t5), g2, g5, g8, g11, g14, g17, t0, t1, t2, t3, t4, t5, Con{F32.bits(d5), Con{F32.bits(d4), Con{F32.bits(d3), Con{F32.bits(d2), Con{F32.bits(d1), Con{F32.bits(d0), values}}}}}}, over)

def imdct.short(ovl: +List<U32>, +g0: F32, +g1: F32, +g2: F32, +g3: F32, +g4: F32, +g5: F32, +g6: F32, +g7: F32, +g8: F32, +g9: F32, +g10: F32, +g11: F32, +g12: F32, +g13: F32, +g14: F32, +g15: F32, +g16: F32, +g17: F32, +t0: F32, +t1: F32, +t2: F32, +t3: F32, +t4: F32, +t5: F32, values: +List<U32>, over: +List<U32>) -> Out:
  match ovl:
    case Con{+o0, Con{+o1, Con{+o2, Con{+o3, Con{+o4, Con{+o5, Con{+o6, Con{+o7, Con{+o8, _}}}}}}}}}:
      short.second(imdct12(g0, g3, g6, g9, g12, g15, float(o6), float(o7), float(o8), t0, t1, t2, t3, t4, t5), g1, g2, g4, g5, g7, g8, g10, g11, g13, g14, g16, g17, t0, t1, t2, t3, t4, t5,
        Con{o5, Con{o4, Con{o3, Con{o2, Con{o1, Con{o0, values}}}}}}, over)
    case _: Out{values, over}

# A subband's transform. 0: drmp3_L3_imdct36 with the long window; 1: with
# the stop block's window; 2: drmp3_L3_imdct_short.
def imdct.band(mode: U32, +g0: F32, +g1: F32, +g2: F32, +g3: F32, +g4: F32, +g5: F32, +g6: F32, +g7: F32, +g8: F32, +g9: F32, +g10: F32, +g11: F32, +g12: F32, +g13: F32, +g14: F32, +g15: F32, +g16: F32, +g17: F32, +ovl: +List<U32>, +twid: +List<U32>, +w0: +List<U32>, +w1: +List<U32>, +t0: F32, +t1: F32, +t2: F32, +t3: F32, +t4: F32, +t5: F32, values: +List<U32>, over: +List<U32>) -> Out:
  match mode:
    case 0: imdct36(g0, g1, g2, g3, g4, g5, g6, g7, g8, g9, g10, g11, g12, g13, g14, g15, g16, g17, ovl, twid, w0, values, over)
    case 1: imdct36(g0, g1, g2, g3, g4, g5, g6, g7, g8, g9, g10, g11, g12, g13, g14, g15, g16, g17, ovl, twid, w1, values, over)
    case _: imdct.short(ovl, g0, g1, g2, g3, g4, g5, g6, g7, g8, g9, g10, g11, g12, g13, g14, g15, g16, g17, t0, t1, t2, t3, t4, t5, values, over)

# How subband `b` is transformed (imdct.band): the first `nlong` as long
# blocks; the others by the granule's block type, 2 short and 3 stop. A
# start block (1) has the long window.
def imdct.mode(+b: U32, +nlong: U32, +block: U32) -> U32:
  Bool.pick(U32, (b < nlong : U32), 0, Bool.pick(U32, U32.is_eq(block, 2), 2, Bool.pick(U32, U32.is_eq(block, 3), 1, 0)))

# drmp3_L3_imdct_gr, a subband of eighteen values and nine of overlap at a
# time: the first `nlong` subbands take the long window, the others their
# block type's transform (2 short, 3 stop, else long).
def imdct.bands(n: Nat, values: +List<U32>, +overlap: +List<U32>, +b: U32, +nlong: U32, +block: U32, +twid: +List<U32>, +w0: +List<U32>, +w1: +List<U32>, +t0: F32, +t1: F32, +t2: F32, +t3: F32, +t4: F32, +t5: F32, acc: Out) -> Out:
  match n:
    case 0n: acc
    case 1n+k:
      match values:
        case Con{+g0, Con{+g1, Con{+g2, Con{+g3, Con{+g4, Con{+g5, Con{+g6, Con{+g7, Con{+g8, Con{+g9, Con{+g10, Con{+g11, Con{+g12, Con{+g13, Con{+g14, Con{+g15, Con{+g16, Con{+g17, +rest}}}}}}}}}}}}}}}}}}:
          Out{done, over} = acc
          imdct.bands(k, rest, List.drop(&2, U32, overlap, 9n), (b + 1 : U32), nlong, block, twid, w0, w1, t0, t1, t2, t3, t4, t5,
            imdct.band(imdct.mode(b, nlong, block),
              float(g0), float(g1), float(g2), float(g3), float(g4), float(g5), float(g6), float(g7), float(g8), float(g9), float(g10), float(g11), float(g12), float(g13), float(g14), float(g15), float(g16), float(g17), overlap, twid, w0, w1, t0, t1, t2, t3, t4, t5, done, over))
        case _: acc

# drmp3_L3_change_sign while the values done (the last first, `i` the
# first's index) are put in order: in the odd subbands the odd values
# change sign.
def signs(xs: +List<U32>, +i: U32, acc: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}: acc
    case Con{+x, rest}: signs(rest, (i - 1 : U32), Con{(x .^. ((((i / 18) .&. (i % 18)) .&. 1) << 31n) : U32), acc})

def filter.reordered(short: Bool, +values: +List<U32>, +start: U32, +sfb: +List<U32>) -> +List<U32>:
  match short:
    case False{}: values
    case True{}: reorder(values, start, sfb)

def filter.out(out: Out) -> Out:
  Out{values, over} = out
  Out{signs(values, 575, Nil{}), List.reverse(&2, U32, over)}

# The second loop of drmp3_L3_decode for a channel: its short bands
# reordered, the alias reduction between its long subbands (all 31
# boundaries, or those of a mixed block's long part), the IMDCT over the
# channel's overlap, and the sign change. The 576 values are then 32
# subbands of 18 samples in time.
def filter(+values: +List<U32>, +overlap: +List<U32>, +h: U32, +gr: H.Gr) -> Out:
  H.Gr{_, _, _, _, +block, +mixed, _, _, _, _, _, _, _, _, _, _, _, _, _, +kind, +long, +short} = gr
  +nlong = long.subbands(h, mixed)
  +twid3 = T.twid3()
  filter.out(imdct.bands(32n, antialias(filter.reordered(U32.is_ne(short, 0), values, (nlong * 18 : U32), List.drop(&2, U32, bands(h, kind), U32.to_nat(long))), alias.count(short, nlong)),
    overlap, 0, nlong, block, T.twid9(), row(T.mdct.window(), 0), row(T.mdct.window(), 1),
    float(H.nth(twid3, 0)), float(H.nth(twid3, 1)), float(H.nth(twid3, 2)), float(H.nth(twid3, 3)), float(H.nth(twid3, 4)), float(H.nth(twid3, 5)), Out{Nil{}, Nil{}}))

def Out.values(out: Out) -> +List<U32>:
  Out{values, _} = out
  values

def Out.overlap(out: Out) -> +List<U32>:
  Out{_, overlap} = out
  overlap

# A mono frame has no right channel: its overlap stays.
def filter.right(mono: Bool, +values: +List<U32>, +overlap: +List<U32>, +h: U32, +gr: H.Gr) -> Out:
  match mono:
    case True{}: Out{Nil{}, overlap}
    case False{}: filter(values, overlap, h, gr)

# -----------------------------------------------------------------------------
# Synthesis (drmp3d_DCT_II, drmp3d_synth_pair, drmp3d_synth,
# drmp3d_synth_granule): a granule's subband samples to 16-bit PCM.
#
# raylib builds dr_mp3 with SSE and 16-bit output, and the SSE branches are
# the ones followed where they differ from the scalar code: the last sums
# of the DCT are associated otherwise, and the window's sums are rounded to
# integers by the processor's rule (to nearest, ties to even) where the two
# samples a subband pair computes alone (drmp3d_synth_pair) are rounded by
# drmp3d_scale_pcm (half added, truncated, one less below zero).

# Four floats.
type Four is Data:
  Four{a: F32, b: F32, c: F32, d: F32}

def Four.a(four: Four) -> F32:
  Four{a, _, _, _} = four
  a

def Four.b(four: Four) -> F32:
  Four{_, b, _, _} = four
  b

def Four.c(four: Four) -> F32:
  Four{_, _, c, _} = four
  c

def Four.d(four: Four) -> F32:
  Four{_, _, _, d} = four
  d

# Eight floats: a row of drmp3d_DCT_II.
type Eight is Data:
  Eight{a0: F32, a1: F32, a2: F32, a3: F32, a4: F32, a5: F32, a6: F32, a7: F32}

# The first step of drmp3d_DCT_II for one i: from the subbands i, 15 - i,
# 16 + i and 31 - i of a time slot and g_sec's three, the i-th entry of each
# of its four rows.
def dct.butterfly(+x0: F32, +x1: F32, +x2: F32, +x3: F32, +s0: F32, +s1: F32, +s2: F32) -> Four:
  +t0 = (x0 + x3 : F32)
  +t1 = (x1 + x2 : F32)
  +t2 = ((x1 - x2) * s0 : F32)
  +t3 = ((x0 - x3) * s1 : F32)
  Four{(t0 + t1 : F32), ((t0 - t1) * s2 : F32), (t3 + t2 : F32), ((t3 - t2) * s2 : F32)}

# The second step: a row's eight values, in its order of operations.
def dct.eight(x: Eight) -> Eight:
  Eight{+x0, +x1, +x2, +x3, +x4, +x5, +x6, +x7} = x
  +half = float(T.c.dct.half())
  +tan = float(T.c.dct.tan())
  +xt = (x0 - x7 : F32)
  +p0 = (x0 + x7 : F32)
  +q7 = (x1 - x6 : F32)
  +p1 = (x1 + x6 : F32)
  +q6 = (x2 - x5 : F32)
  +p2 = (x2 + x5 : F32)
  +q5 = (x3 - x4 : F32)
  +p3 = (x3 + x4 : F32)
  +q4 = (p0 - p3 : F32)
  +r0 = (p0 + p3 : F32)
  +q3 = (p1 - p2 : F32)
  +r1 = (p1 + p2 : F32)
  +s5 = (q5 + q6 : F32)
  +s6 = ((q6 + q7) * half : F32)
  +s7 = (q7 + xt : F32)
  +s3 = ((q3 + q4) * half : F32)
  +t5 = (s5 - (s7 * tan) : F32)
  +t7 = (s7 + (t5 * float(T.c.dct.sin())) : F32)
  +u5 = (t5 - (t7 * tan) : F32)
  +v0 = (xt - s6 : F32)
  +vt = (xt + s6 : F32)
  Eight{(r0 + r1 : F32), ((vt + t7) * float(T.c.dct.out1()) : F32), ((q4 + s3) * float(T.c.dct.out2()) : F32), ((v0 - u5) * float(T.c.dct.out3()) : F32), ((r0 - r1) * half : F32),
    ((v0 + u5) * float(T.c.dct.out5()) : F32), ((q4 - s3) * float(T.c.dct.out6()) : F32), ((vt - t7) * float(T.c.dct.out7()) : F32)}

# The last step, as the SSE branch adds: the 32 outputs, four for each entry
# of the rows, with d[i] + d[i + 1] added first where three values meet.
def dct.out(r0: Eight, r1: Eight, r2: Eight, r3: Eight) -> +List<U32>:
  Eight{a0, a1, a2, a3, a4, a5, a6, a7} = r0
  Eight{+b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7} = r1
  Eight{+c0, +c1, +c2, +c3, +c4, +c5, +c6, +c7} = r2
  Eight{+d0, +d1, +d2, +d3, +d4, +d5, +d6, +d7} = r3
  [F32.bits(a0), F32.bits((c0 + (d0 + d1) : F32)), F32.bits((b0 + b1 : F32)), F32.bits((c1 + (d0 + d1) : F32)), F32.bits(a1), F32.bits((c1 + (d1 + d2) : F32)), F32.bits((b1 + b2 : F32)), F32.bits((c2 + (d1 + d2) : F32)), F32.bits(a2), F32.bits((c2 + (d2 + d3) : F32)), F32.bits((b2 + b3 : F32)), F32.bits((c3 + (d2 + d3) : F32)), F32.bits(a3), F32.bits((c3 + (d3 + d4) : F32)), F32.bits((b3 + b4 : F32)), F32.bits((c4 + (d3 + d4) : F32)), F32.bits(a4), F32.bits((c4 + (d4 + d5) : F32)), F32.bits((b4 + b5 : F32)), F32.bits((c5 + (d4 + d5) : F32)), F32.bits(a5), F32.bits((c5 + (d5 + d6) : F32)), F32.bits((b5 + b6 : F32)), F32.bits((c6 + (d5 + d6) : F32)), F32.bits(a6), F32.bits((c6 + (d6 + d7) : F32)), F32.bits((b6 + b7 : F32)), F32.bits((c7 + (d6 + d7) : F32)), F32.bits(a7), F32.bits((c7 + d7 : F32)), F32.bits(b7), F32.bits(d7)]

def dct.rows(+sec: +List<U32>, +y0: U32, +y1: U32, +y2: U32, +y3: U32, +y4: U32, +y5: U32, +y6: U32, +y7: U32, +y8: U32, +y9: U32, +y10: U32, +y11: U32, +y12: U32, +y13: U32, +y14: U32, +y15: U32, +y16: U32, +y17: U32, +y18: U32, +y19: U32, +y20: U32, +y21: U32, +y22: U32, +y23: U32, +y24: U32, +y25: U32, +y26: U32, +y27: U32, +y28: U32, +y29: U32, +y30: U32, +y31: U32) -> +List<U32>:
  match sec:
    case Con{+s0, Con{+s1, Con{+s2, Con{+s3, Con{+s4, Con{+s5, Con{+s6, Con{+s7, Con{+s8, Con{+s9, Con{+s10, Con{+s11, Con{+s12, Con{+s13, Con{+s14, Con{+s15, Con{+s16, Con{+s17, Con{+s18, Con{+s19, Con{+s20, Con{+s21, Con{+s22, Con{+s23, _}}}}}}}}}}}}}}}}}}}}}}}}:
      +f0 = dct.butterfly(float(y0), float(y15), float(y16), float(y31), float(s0), float(s1), float(s2))
      +f1 = dct.butterfly(float(y1), float(y14), float(y17), float(y30), float(s3), float(s4), float(s5))
      +f2 = dct.butterfly(float(y2), float(y13), float(y18), float(y29), float(s6), float(s7), float(s8))
      +f3 = dct.butterfly(float(y3), float(y12), float(y19), float(y28), float(s9), float(s10), float(s11))
      +f4 = dct.butterfly(float(y4), float(y11), float(y20), float(y27), float(s12), float(s13), float(s14))
      +f5 = dct.butterfly(float(y5), float(y10), float(y21), float(y26), float(s15), float(s16), float(s17))
      +f6 = dct.butterfly(float(y6), float(y9), float(y22), float(y25), float(s18), float(s19), float(s20))
      +f7 = dct.butterfly(float(y7), float(y8), float(y23), float(y24), float(s21), float(s22), float(s23))
      dct.out(dct.eight(Eight{Four.a(f0), Four.a(f1), Four.a(f2), Four.a(f3), Four.a(f4), Four.a(f5), Four.a(f6), Four.a(f7)}), dct.eight(Eight{Four.b(f0), Four.b(f1), Four.b(f2), Four.b(f3), Four.b(f4), Four.b(f5), Four.b(f6), Four.b(f7)}), dct.eight(Eight{Four.c(f0), Four.c(f1), Four.c(f2), Four.c(f3), Four.c(f4), Four.c(f5), Four.c(f6), Four.c(f7)}), dct.eight(Eight{Four.d(f0), Four.d(f1), Four.d(f2), Four.d(f3), Four.d(f4), Four.d(f5), Four.d(f6), Four.d(f7)}))
    case _: Nil{}

# drmp3d_DCT_II for one time slot: its 32 subband samples to 32 values.
def dct.slot(slot: +List<U32>, +sec: +List<U32>) -> +List<U32>:
  match slot:
    case Con{+y0, Con{+y1, Con{+y2, Con{+y3, Con{+y4, Con{+y5, Con{+y6, Con{+y7, Con{+y8, Con{+y9, Con{+y10, Con{+y11, Con{+y12, Con{+y13, Con{+y14, Con{+y15, Con{+y16, Con{+y17, Con{+y18, Con{+y19, Con{+y20, Con{+y21, Con{+y22, Con{+y23, Con{+y24, Con{+y25, Con{+y26, Con{+y27, Con{+y28, Con{+y29, Con{+y30, Con{+y31, _}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}: dct.rows(sec, y0, y1, y2, y3, y4, y5, y6, y7, y8, y9, y10, y11, y12, y13, y14, y15, y16, y17, y18, y19, y20, y21, y22, y23, y24, y25, y26, y27, y28, y29, y30, y31)
    case _: Nil{}

# The subbands of a channel's samples: where each begins in the list.
def subbands(n: Nat, +values: +List<U32>, acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match n:
    case 0n: List.reverse(&2, +List<U32>, acc)
    case 1n+k: subbands(k, List.drop(&2, U32, values, 18n), Con{values, acc})

# A time slot: the next sample of each subband, and the subbands after it.
type Slot is Data:
  Slot{now: +List<U32>, later: +List<+List<U32>>}

def slot.heads(subs: +List<+List<U32>>, now: +List<U32>, later: +List<+List<U32>>) -> Slot:
  match subs:
    case Nil{}: Slot{List.reverse(&2, U32, now), List.reverse(&2, +List<U32>, later)}
    case Con{+sub, rest}: slot.heads(rest, Con{H.first(sub), now}, Con{tail(sub), later})

def Slot.now(slot: Slot) -> +List<U32>:
  Slot{now, _} = slot
  now

def Slot.later(slot: Slot) -> +List<+List<U32>>:
  Slot{_, later} = slot
  later

# drmp3d_DCT_II over a channel's granule: its 18 time slots' values, a slot
# after a slot. (dr_mp3's SSE branch loads four slots at a time and for the
# last two reads two floats past the channel's 576, which it does not use.)
def dct.slots(n: Nat, +subs: +List<+List<U32>>, +sec: +List<U32>, acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match n:
    case 0n: List.reverse(&2, +List<U32>, acc)
    case 1n+k:
      +slot = slot.heads(subs, Nil{}, Nil{})
      dct.slots(k, Slot.later(slot), sec, Con{dct.slot(Slot.now(slot), sec), acc})

# The magnitude of a float below 2^24 as an integer: `shift` bits are cut
# from its 24-bit significand `m`. Rounded to nearest, ties to even.
def int.nearest(+m: U32, +shift: U32) -> U32:
  +q = (m >> U32.to_nat(shift) : U32)
  +rem = (m - (q << U32.to_nat(shift)) : U32)
  +half = (1 << U32.to_nat((shift - 1 : U32)) : U32)
  (q + Bool.to_u32((rem > half : U32) || (U32.is_eq(rem, half) && U32.is_eq((q .&. 1 : U32), 1))) : U32)

# The bits to cut from a float's significand for its integer part (0 when
# the float is 2^23 or more, which the samples are not).
def float.cut(+bits: U32) -> U32:
  (150 - U32.min(((bits >> 23n) .&. 255 : U32), 150) : U32)

# An integer of a given sign as an int16's 16 bits.
def int16(+negative: Bool, +magnitude: U32) -> U32:
  Bool.pick(U32, negative, ((0 - magnitude) .&. 65535 : U32), magnitude)

# The SSE branch's conversion of a sum: _mm_min_ps and _mm_max_ps keep it
# within -32768 and 32767, _mm_cvtps_epi32 rounds it to nearest, ties to
# even, and the pack saturates what cannot be out of range.
def sample.packed(+x: F32) -> U32:
  +low = Bool.pick(F32, (x < 32767.0 : F32), x, 32767.0)
  +bits = F32.bits(Bool.pick(F32, (low > F32.neg(32768.0) : F32), low, F32.neg(32768.0)))
  +cut = float.cut(bits)
  int16((bits >= 2147483648 : U32), Bool.pick(U32, (cut > 24 : U32), 0, int.nearest(float.significand(bits), U32.max(U32.min(cut, 24), 1))))

# drmp3d_scale_pcm: 32767 from 32766.5 up and -32768 from -32767.5 down;
# else half added (a float sum), truncated, and one less when negative.
def sample.scaled(+x: F32) -> U32:
  +bits = F32.bits((x + 0.5 : F32))
  +cut = float.cut(bits)
  +magnitude = Bool.pick(U32, (cut > 23 : U32), 0, (float.significand(bits) >> U32.to_nat(U32.min(cut, 23)) : U32))
  +negative = (bits >= 2147483648 : U32) && U32.is_ne(magnitude, 0)
  Bool.pick(U32, (x >= 32766.5 : F32), 32767, Bool.pick(U32, (x <= F32.neg(32767.5) : F32), 32768, int16(negative, (magnitude + Bool.to_u32(negative) : U32))))

# drmp3d_synth_pair's first sum, of fifteen rows' value for a channel (the
# newest first in the list): sample 0 of a time slot.
def pair.first(z: +List<U32>) -> F32:
  match z:
    case Con{+z14, Con{+z13, Con{+z12, Con{+z11, Con{+z10, Con{+z9, Con{+z8, Con{+z7, Con{+z6, Con{+z5, Con{+z4, Con{+z3, Con{+z2, Con{+z1, Con{+z0, _}}}}}}}}}}}}}}}:
      +a0 = ((float(z14) - float(z0)) * 29.0 : F32)
      +a1 = (a0 + ((float(z1) + float(z13)) * 213.0) : F32)
      +a2 = (a1 + ((float(z12) - float(z2)) * 459.0) : F32)
      +a3 = (a2 + ((float(z3) + float(z11)) * 2037.0) : F32)
      +a4 = (a3 + ((float(z10) - float(z4)) * 5153.0) : F32)
      +a5 = (a4 + ((float(z5) + float(z9)) * 6574.0) : F32)
      +a6 = (a5 + ((float(z8) - float(z6)) * 37489.0) : F32)
      (a6 + (float(z7) * 75038.0) : F32)
    case _: 0.0

# Its second sum: sample 16.
def pair.second(z: +List<U32>) -> F32:
  match z:
    case Con{+z14, Con{+z13, Con{+z12, Con{+z11, Con{+z10, Con{+z9, Con{+z8, Con{+z7, Con{+z6, Con{+z5, Con{+z4, Con{+z3, Con{+z2, Con{+z1, Con{+z0, _}}}}}}}}}}}}}}}:
      +a0 = (float(z14) * 104.0 : F32)
      +a1 = (a0 + (float(z12) * 1567.0) : F32)
      +a2 = (a1 + (float(z10) * 9727.0) : F32)
      +a3 = (a2 + (float(z8) * 64019.0) : F32)
      +a4 = (a3 + (float(z6) * F32.neg(9975.0)) : F32)
      +a5 = (a4 + (float(z4) * F32.neg(45.0)) : F32)
      +a6 = (a5 + (float(z2) * 146.0) : F32)
      (a6 + (float(z0) * F32.neg(5.0)) : F32)
    case _: 0.0

# The sums of the window for one output pair of a subband pair, for one
# channel of one time slot: `v` is sixteen rows' value, the newest first,
# `r` the same the oldest first, `w` a row of g_win. Step k takes
# vz = v[k], vy = r[k] and two weights: b grows by vz*w1 + vy*w0 and a by
# vz*w0 - vy*w1, or by vy*w1 - vz*w0 at the odd steps. The result is the two
# samples' 16 bits, a's above b's.
def window.sums(n: Nat, v: +List<U32>, +r: +List<U32>, +w: +List<U32>, +odd: Bool, +a: F32, +b: F32) -> U32:
  match n:
    case 0n: ((sample.packed(a) << 16n) .|. sample.packed(b) : U32)
    case 1n+k:
      match v:
        case Nil{}: ((sample.packed(a) << 16n) .|. sample.packed(b) : U32)
        case Con{+z, rest}:
          +vz = float(z)
          +vy = float(H.first(r))
          +w0 = float(H.first(w))
          +w1 = float(H.first(tail(w)))
          window.sums(k, rest, tail(r), tail(tail(w)), Bool.not(odd),
            (a + Bool.pick(F32, odd, ((vy * w1) - (vz * w0) : F32), ((vz * w0) - (vy * w1) : F32)) : F32), (b + ((vz * w1) + (vy * w0)) : F32))

# The first step sets the sums; seven more follow.
def window(+v: +List<U32>, +r: +List<U32>, +w: +List<U32>) -> U32:
  +vz = float(H.first(v))
  +vy = float(H.first(r))
  +w0 = float(H.first(w))
  +w1 = float(H.first(tail(w)))
  window.sums(7n, tail(v), tail(r), tail(tail(w)), True{}, ((vz * w0) - (vy * w1) : F32), ((vz * w1) + (vy * w0) : F32))

# Rows of the synthesis buffer (zlin): 64 floats each. Entries 4i to 4i + 3,
# for i below 15, are a subband's value for the left and right channels of
# a time slot and of the next; the last four are two subbands' of one slot.

# Sixteen rows' next four entries, a list for each of the four (the oldest
# row first), and the rows after them.
type Lanes is Data:
  Lanes{l0: +List<U32>, l1: +List<U32>, l2: +List<U32>, l3: +List<U32>, rows: +List<+List<U32>>}

def lanes(rows: +List<+List<U32>>, l0: +List<U32>, l1: +List<U32>, l2: +List<U32>, l3: +List<U32>, later: +List<+List<U32>>) -> Lanes:
  match rows:
    case Nil{}: Lanes{l0, l1, l2, l3, List.reverse(&2, +List<U32>, later)}
    case Con{Con{+a, Con{+b, Con{+c, Con{+d, +rest}}}}, more}: lanes(more, Con{a, l0}, Con{b, l1}, Con{c, l2}, Con{d, l3}, Con{rest, later})
    case Con{_, more}: lanes(more, Con{0, l0}, Con{0, l1}, Con{0, l2}, Con{0, l3}, Con{Nil{}, later})

def Lanes.l0(lanes: Lanes) -> +List<U32>:
  Lanes{l0, _, _, _, _} = lanes
  l0

def Lanes.l1(lanes: Lanes) -> +List<U32>:
  Lanes{_, l1, _, _, _} = lanes
  l1

def Lanes.l2(lanes: Lanes) -> +List<U32>:
  Lanes{_, _, l2, _, _} = lanes
  l2

def Lanes.l3(lanes: Lanes) -> +List<U32>:
  Lanes{_, _, _, l3, _} = lanes
  l3

def Lanes.rows(lanes: Lanes) -> +List<+List<U32>>:
  Lanes{_, _, _, _, rows} = lanes
  rows

# What the fifteen subband pairs of a call give: samples 1 to 15 and 17 to
# 31 of its two time slots, each as it is laid in the output (a frame a
# channel after a channel; the lists of 17 to 31 the last first).
type Blocks is Data:
  Blocks{ax: +List<U32>, bx: +List<U32>, ay: +List<U32>, by: +List<U32>}

# A sample of a channel or of two onto a list: left then right as read.
def onto(mono: Bool, +left: U32, +right: U32, acc: +List<U32>) -> +List<U32>:
  match mono:
    case True{}: Con{left, acc}
    case False{}: Con{left, Con{right, acc}}

def onto.back(mono: Bool, +left: U32, +right: U32, acc: +List<U32>) -> +List<U32>:
  match mono:
    case True{}: Con{left, acc}
    case False{}: Con{right, Con{left, acc}}

# The window over the rows, four entries at a time: entry 4i's sums are
# samples 15 - i and 17 + i, with g_win's row 14 - i (`wins` is g_win the
# last row first).
def window.rows(n: Nat, wins: +List<+List<U32>>, +rows: +List<+List<U32>>, +mono: Bool, blocks: Blocks) -> Blocks:
  match n:
    case 0n: blocks
    case 1n+k:
      match wins:
        case Nil{}: blocks
        case Con{+w, more}:
          Blocks{ax, bx, ay, by} = blocks
          +now = lanes(rows, Nil{}, Nil{}, Nil{}, Nil{}, Nil{})
          +s0 = window(List.reverse(&2, U32, Lanes.l0(now)), Lanes.l0(now), w)
          +s1 = window(List.reverse(&2, U32, Lanes.l1(now)), Lanes.l1(now), w)
          +s2 = window(List.reverse(&2, U32, Lanes.l2(now)), Lanes.l2(now), w)
          +s3 = window(List.reverse(&2, U32, Lanes.l3(now)), Lanes.l3(now), w)
          window.rows(k, more, Lanes.rows(now), mono, Blocks{onto(mono, (s0 >> 16n : U32), (s1 >> 16n : U32), ax), onto.back(mono, (s0 .&. 65535 : U32), (s1 .&. 65535 : U32), bx),
            onto(mono, (s2 >> 16n : U32), (s3 >> 16n : U32), ay), onto.back(mono, (s2 .&. 65535 : U32), (s3 .&. 65535 : U32), by)})

# Fifteen groups of four entries from four lists walked together (a missing
# entry is 0), onto `acc` the last first.
def row.groups(n: Nat, +a: +List<U32>, +b: +List<U32>, +c: +List<U32>, +d: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: row.groups(k, tail(a), tail(b), tail(c), tail(d), Con{H.first(d), Con{H.first(c), Con{H.first(b), Con{H.first(a), acc}}}})

# A row: fifteen groups, then four entries.
def row.made(+a: +List<U32>, +b: +List<U32>, +c: +List<U32>, +d: +List<U32>, +e0: U32, +e1: U32, +e2: U32, +e3: U32) -> +List<U32>:
  List.reverse.go(&2, U32, row.groups(15n, a, b, c, d, Nil{}), [e0, e1, e2, e3])

# The row before the newest gets the third and fourth entry of its fifteen
# groups from the call after the one that made it.
def row.completed(n: Nat, row: +List<U32>, +l: +List<U32>, +r: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse.go(&2, U32, acc, row)
    case 1n+k:
      match row:
        case Con{+a, Con{+b, Con{_, Con{_, rest}}}}: row.completed(k, rest, tail(l), tail(r), Con{H.first(r), Con{H.first(l), Con{b, Con{a, acc}}}})
        case +short: List.reverse.go(&2, U32, acc, short)

# The four last entries of each of sixteen rows, a list for each (the
# newest row first).
def rows.ends(rows: +List<+List<U32>>, e0: +List<U32>, e1: +List<U32>, e2: +List<U32>, e3: +List<U32>) -> Lanes:
  match rows:
    case Nil{}: Lanes{List.reverse(&2, U32, e0), List.reverse(&2, U32, e1), List.reverse(&2, U32, e2), List.reverse(&2, U32, e3), Nil{}}
    case Con{+row, more}:
      +end = List.drop(&2, U32, row, 60n)
      rows.ends(more, Con{H.nth(end, 0), e0}, Con{H.nth(end, 1), e1}, Con{H.nth(end, 2), e2}, Con{H.nth(end, 3), e3})

# The first `n` rows of a list.
def rows.newest(n: Nat, rows: +List<+List<U32>>, acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match n:
    case 0n: List.reverse(&2, +List<U32>, acc)
    case 1n+k:
      match rows:
        case Nil{}: List.reverse(&2, +List<U32>, acc)
        case Con{+row, rest}: rows.newest(k, rest, Con{row, acc})

# A call's 64 samples a channel (two time slots), and the fifteen rows the
# next call begins with (the newest first; its third and fourth entries of
# each group are the next call's to write).
type Call is Data:
  Call{pcm: +List<U32>, history: +List<+List<U32>>}

def Call.pcm(call: Call) -> +List<U32>:
  Call{pcm, _} = call
  pcm

def Call.history(call: Call) -> +List<+List<U32>>:
  Call{_, history} = call
  history

# The samples of a call in order: for each of its two slots sample 0 (the
# first sum of drmp3d_synth_pair), 1 to 15, 16 (its second sum), 17 to 31.
# `e` has the rows' last four entries; the first slot's pair reads the
# fifteen rows before the newest, the second's the newest fifteen.
def call.samples(blocks: Blocks, +e: Lanes, +mono: Bool) -> +List<U32>:
  Blocks{ax, bx, ay, by} = blocks
  Lanes{+e0, +e1, +e2, +e3, _} = e
  onto(mono, sample.scaled(pair.first(tail(e0))), sample.scaled(pair.first(tail(e1))), List.append(&2, U32, ax,
    onto(mono, sample.scaled(pair.second(tail(e2))), sample.scaled(pair.second(tail(e3))), List.reverse.go(&2, U32, bx,
      onto(mono, sample.scaled(pair.first(e0)), sample.scaled(pair.first(e1)), List.append(&2, U32, ay,
        onto(mono, sample.scaled(pair.second(e2)), sample.scaled(pair.second(e3)), List.reverse(&2, U32, by))))))))

def call.rows(+rows: +List<+List<U32>>, +ly: +List<U32>, +ry: +List<U32>, +mono: Bool, +wins: +List<+List<U32>>) -> Call:
  Call{call.samples(window.rows(15n, wins, rows, mono, Blocks{Nil{}, Nil{}, Nil{}, Nil{}}), rows.ends(rows, Nil{}, Nil{}, Nil{}, Nil{}), mono),
    Con{row.made(tail(ly), tail(ry), Nil{}, Nil{}, H.nth(ly, 16), H.nth(ry, 16), H.first(ly), H.first(ry)), rows.newest(14n, rows, Nil{})}}

# drmp3d_synth for two time slots: `lx`, `rx` are the first slot's 32 values
# of each channel after the DCT, `ly`, `ry` the second's (a mono frame's
# right is its left), `history` the fifteen rows before, the newest first.
# The newest of them is completed with the first slot's subbands 1 to 15; a
# row is made of both slots' subbands 31 down to 17, with the first slot's
# 16 and 0; the window and the pairs read those sixteen rows; and a row of
# the second slot's subbands 1 to 15, with its 16 and 0, begins the next.
def synth.call(history: +List<+List<U32>>, +lx: +List<U32>, +rx: +List<U32>, +ly: +List<U32>, +ry: +List<U32>, +mono: Bool, +wins: +List<+List<U32>>) -> Call:
  match history:
    case Nil{}: Call{Nil{}, Nil{}}
    case Con{+newest, +older}:
      call.rows(Con{row.made(List.reverse(&2, U32, lx), List.reverse(&2, U32, rx), List.reverse(&2, U32, ly), List.reverse(&2, U32, ry), H.nth(lx, 16), H.nth(rx, 16), H.first(lx), H.first(rx)),
        Con{row.completed(15n, newest, tail(lx), tail(rx), Nil{}), older}}, ly, ry, mono, wins)

# The loop of drmp3d_synth_granule: nine calls over a granule's eighteen
# slots. `blocks` takes each call's samples, the last call first.
type Synth is Data:
  Synth{pcm: +List<U32>, history: +List<+List<U32>>}

def blocks.joined(blocks: +List<+List<U32>>, acc: +List<U32>) -> +List<U32>:
  match blocks:
    case Nil{}: acc
    case Con{+block, rest}: blocks.joined(rest, List.append(&2, U32, block, acc))

def synth.calls(n: Nat, left: +List<+List<U32>>, +right: +List<+List<U32>>, +mono: Bool, +wins: +List<+List<U32>>, +history: +List<+List<U32>>, +blocks: +List<+List<U32>>) -> Synth:
  match n:
    case 0n: Synth{blocks.joined(blocks, Nil{}), history}
    case 1n+k:
      match left:
        case Con{+lx, Con{+ly, +later}}:
          +done = synth.call(history, lx, row.first(right), ly, row.first(List.drop(&2, +List<U32>, right, 1n)), mono, wins)
          synth.calls(k, later, List.drop(&2, +List<U32>, right, 2n), mono, wins, Call.history(done), Con{Call.pcm(done), blocks})
        case _: Synth{blocks.joined(blocks, Nil{}), history}

# A mono frame's rows keep the entries of the right channel that the frames
# before left in the decoder (drmp3d_synth_granule copies back every other
# float): the odd entries of `old` at the same place.
def row.merged(row: +List<U32>, +old: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match row:
    case Con{+even, Con{_, rest}}: row.merged(rest, tail(tail(old)), Con{H.first(tail(old)), Con{even, acc}})
    case +short: List.reverse.go(&2, U32, acc, short)

def rows.merged(rows: +List<+List<U32>>, +old: +List<+List<U32>>, acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match rows:
    case Nil{}: List.reverse(&2, +List<U32>, acc)
    case Con{+row, rest}: rows.merged(rest, List.drop(&2, +List<U32>, old, 1n), Con{row.merged(row, row.first(old), Nil{}), acc})

def synth.kept(mono: Bool, synth: Synth, +old: +List<+List<U32>>) -> Synth:
  match mono:
    case False{}: synth
    case True{}:
      Synth{pcm, history} = synth
      Synth{pcm, rows.merged(history, old, Nil{})}

def dct.right(n: Nat, mono: Bool, +left: +List<+List<U32>>, +values: +List<U32>, +sec: +List<U32>) -> +List<+List<U32>>:
  match mono:
    case True{}: left
    case False{}: dct.slots(n, subbands(32n, values, Nil{}), sec, Nil{})

# drmp3d_synth_granule: the channels' subband samples (576 each) through
# the DCT and the window to 576 samples a channel, a frame a channel after a
# channel, each an int16's 16 bits; and the fifteen rows (qmf_state) the
# next granule begins with.
# drmp3d_synth_granule with nbands `n` (18 for Layer III, 12 for Layers I
# and II): the DCT of each subband's first n samples and n/2 calls.
def synth.granule.slots(+n: Nat, calls: Nat, +left: +List<U32>, +right: +List<U32>, +mono: Bool, +history: +List<+List<U32>>) -> Synth:
  +sec = T.sec()
  +slots = dct.slots(n, subbands(32n, left, Nil{}), sec, Nil{})
  synth.kept(mono, synth.calls(calls, slots, dct.right(n, mono, slots, right, sec), mono, List.reverse(&2, +List<U32>, T.win()), history, Nil{}), history)

def synth.granule(+left: +List<U32>, +right: +List<U32>, +mono: Bool, +history: +List<+List<U32>>) -> Synth:
  synth.granule.slots(18n, 9n, left, right, mono, history)

def Synth.pcm(synth: Synth) -> +List<U32>:
  Synth{pcm, _} = synth
  pcm

def Synth.history(synth: Synth) -> +List<+List<U32>>:
  Synth{_, history} = synth
  history

def Gr.first(grs: +List<H.Gr>, +or: H.Gr) -> H.Gr:
  match grs:
    case Nil{}: or
    case Con{gr, _}: gr

# Every granule of a frame: the bit after the last, the channels' intensity
# positions, the scales, whether every read was inside the array, and the
# values, a channel after a channel (the last first).
type Granules is Data:
  Granules{pos: U32, ist0: +List<U32>, ist1: +List<U32>, scf: +List<U32>, overlap0: +List<U32>, overlap1: +List<U32>, qmf: +List<+List<U32>>, fine: Bool, spectra: +List<+List<U32>>, pcm: +List<+List<U32>>}

def granules.pushed(mono: Bool, +left: +List<U32>, +right: +List<U32>, +out: +List<+List<U32>>) -> +List<+List<U32>>:
  match mono:
    case True{}: Con{left, out}
    case False{}: Con{right, Con{left, out}}

# `grs` is the side information's granules, a channel after a channel: one
# or two granules of one or two channels. `limit` is the main data's bits
# and `pos` the granule's first.
def granules(n: Nat, grs: +List<H.Gr>, +mono: Bool, +main: +List<U32>, +limit: U32, +pos: U32, +h: U32, +ist0: +List<U32>, +ist1: +List<U32>, +scf: +List<U32>, +sh: U32, +overlap0: +List<U32>,
    +overlap1: +List<U32>, +qmf: +List<+List<U32>>, +fine: Bool, +out: +List<+List<U32>>, +pcm: +List<+List<U32>>) -> Granules:
  match n:
    case 0n: Granules{pos, ist0, ist1, scf, overlap0, overlap1, qmf, fine, out, pcm}
    case 1n+k:
      match grs:
        case Nil{}: Granules{pos, ist0, ist1, scf, overlap0, overlap1, qmf, fine, out, pcm}
        case Con{+gr0, +rest}:
          +done = granule(mono, gr0, Gr.first(rest, gr0), main, limit, pos, h, ist0, ist1, scf, sh)
          +left = filter(Channels.left(done), overlap0, h, gr0)
          +right = filter.right(mono, Channels.right(done), overlap1, h, Gr.first(rest, gr0))
          +made = synth.granule(Out.values(left), Out.values(right), mono, qmf)
          granules(k, Bool.pick(+List<H.Gr>, mono, rest, List.drop(&2, H.Gr, rest, 1n)), mono, main, limit, Channels.pos(done), h, Channels.ist0(done), Channels.ist1(done), Channels.scf(done),
            sh, Out.overlap(left), Out.overlap(right), Synth.history(made), fine && Channels.fine(done), granules.pushed(mono, Out.values(left), Out.values(right), out), Con{Synth.pcm(made), pcm})

# drmp3_L3_save_reservoir after the granules: what was not read of the main
# data is the next frames' reservoir.
def decoded.granules(grans: Granules, +h: U32, +free: U32, +main: +List<U32>, +len: U32, +array: +List<U32>, +bytes: U32, +compress: U32) -> Decoded:
  Granules{+pos, ist0, ist1, scf, overlap0, overlap1, qmf, +fine, spectra, pcm} = grans
  Decoded{Decoder{H.Dec{h, free, H.layer3.kept(main, len, ((pos + 7) / 8 : U32))}, array, scf, ist0, ist1, compress, overlap0, overlap1, qmf}, H.hdr.samples(h), bytes, Bool.pick(U32, fine, 0, 1),
    List.reverse(&2, +List<U32>, spectra), blocks.joined(pcm, Nil{})}

# drmp3_L3_restore_reservoir: the frame's main data after the reservoir's
# last main_data_begin bytes, and how many bytes that is.
def frame.main(side: H.Side, +reserv: +List<U32>, +payload: +List<U32>, +limit: U32) -> +List<U32> & U32:
  H.Side{_, +begin, _, +pos} = side
  +have = H.count(reserv, 0)
  +room = ((limit - U32.min(pos, limit)) / 8 : U32)
  (H.layer3.main(reserv, have, begin, payload, (pos / 8 : U32), room), (U32.min(have, begin) + room : U32))

# The main data's array once a frame's main data (`len` bytes) is written.
def frame.array(+main: +List<U32>, +len: U32, +array: +List<U32>) -> +List<U32>:
  List.append(&2, U32, main, List.drop(&2, U32, array, U32.to_nat(len)))

def Side.grs(side: H.Side) -> +List<H.Gr>:
  H.Side{_, _, grs, _} = side
  grs

# The reservoir's bytes.
def Decoder.reserv(decoder: Decoder) -> +List<U32>:
  Decoder{H.Dec{_, _, reserv}, _, _, _, _, _, _, _, _} = decoder
  reserv

# scalefac_compress of the granule information's second slot once
# drmp3_L3_read_side_info has run: the second granule's when the reader came
# to it and it has no more than 288 big values (the field is read after
# that check), else what the slot had.
def slot.compress(grs: +List<H.Gr>, +old: U32) -> U32:
  match grs:
    case Nil{}: old
    case Con{H.Gr{_, +big, _, +compress, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _}: Bool.pick(U32, (big > 288 : U32), old, compress)

def Decoder.slot(decoder: Decoder, +side: H.Side) -> Decoder:
  Decoder{dec, main, scf, ist0, ist1, +compress, overlap0, overlap1, qmf} = decoder
  Decoder{dec, main, scf, ist0, ist1, slot.compress(List.drop(&2, H.Gr, Side.grs(side), 1n), compress), overlap0, overlap1, qmf}

# A frame whose reservoir is short of main_data_begin: its main data is
# written and kept for the next frames, and nothing is decoded.
def frame.short(mained: +List<U32> & U32, +h: U32, +free: U32, +bytes: U32, decoder: Decoder) -> Decoded:
  (+main, +len) = mained
  Decoder{_, +array, scf, ist0, ist1, +compress, overlap0, overlap1, qmf} = decoder
  Decoded{Decoder{H.Dec{h, free, H.layer3.kept(main, len, 0)}, frame.array(main, len, array), scf, ist0, ist1, compress, overlap0, overlap1, qmf}, 0, bytes, 0, Nil{}, Nil{}}

def frame.full(mained: +List<U32> & U32, +grs: +List<H.Gr>, +h: U32, +free: U32, +bytes: U32, decoder: Decoder) -> Decoded:
  (+main, +len) = mained
  Decoder{_, +array, +scf, +ist0, +ist1, +compress, +overlap0, +overlap1, +qmf} = decoder
  +whole = frame.array(main, len, array)
  decoded.granules(granules(2n, grs, H.hdr.mono(h), whole, (len * 8 : U32), 0, h, ist0, ist1, scf, (compress .&. 1 : U32), overlap0, overlap1, qmf, True{}, Nil{}, Nil{}), h, free, main, len, whole, bytes, compress)

# A Layer III frame by what its side information allows. 0: the side
# information failed or the frame is too short for it, which clears the
# decoder's header (drmp3dec_init) and nothing else; 1: the reservoir is
# short; 2: the granules are decoded.
def frame.side(state: U32, +side: H.Side, +h: U32, +free: U32, +payload: +List<U32>, +limit: U32, +bytes: U32, +decoder: Decoder) -> Decoded:
  match state:
    case 0:
      Decoder{H.Dec{_, _, +reserv}, +array, +scf, +ist0, +ist1, +compress, +overlap0, +overlap1, +qmf} = decoder
      Decoded{Decoder{H.Dec{(h .&. 16777215 : U32), free, reserv}, array, scf, ist0, ist1, compress, overlap0, overlap1, qmf}, 0, bytes, 0, Nil{}, Nil{}}
    case 1: frame.short(frame.main(side, Decoder.reserv(decoder), payload, limit), h, free, bytes, decoder)
    case _: frame.full(frame.main(side, Decoder.reserv(decoder), payload, limit), Side.grs(side), h, free, bytes, decoder)

def side.state(+side: H.Side, +limit: U32, +have: U32) -> U32:
  H.Side{bad, begin, _, pos} = side
  Bool.pick(U32, bad || (pos > limit : U32), 0, Bool.pick(U32, (have >= begin : U32), 2, 1))

def frame.layer3(+at: +List<U32>, +size: U32, +skip: U32, +free: U32, +decoder: Decoder) -> Decoded:
  +h = H.word(at)
  +limit = ((size - 4) * 8 : U32)
  +payload = List.drop(&2, U32, at, 4n)
  +side = H.side.read(payload, limit, Bool.pick(U32, H.hdr.crc(h), 16, 0), h)
  frame.side(side.state(side, limit, H.count(Decoder.reserv(decoder), 0)), side, h, free, payload, limit, (skip + size : U32), Decoder.slot(decoder, side))

# A Layer I or II frame's granule buffers through the synthesis, 384
# samples a channel each, in order: the samples (the last first while
# made) and the synthesis state after them.
def layer12.synth(buffers: +List<L12.Buffer>, +mono: Bool, +history: +List<+List<U32>>, +pcm: +List<+List<U32>>) -> Synth:
  match buffers:
    case Nil{}: Synth{blocks.joined(pcm, Nil{}), history}
    case Con{L12.Buffer{+left, +right}, rest}:
      +made = synth.granule.slots(12n, 6n, left, right, mono, history)
      layer12.synth(rest, mono, Synth.history(made), Con{Synth.pcm(made), pcm})

# drmp3dec_decode_frame's Layer I and II branch: the frame's samples, its
# header kept. A reader past the frame clears the header's first byte
# (drmp3dec_init) and the frame gives no samples, but what was synthesized
# before the check stays in the synthesis state and is in `pcm` (dr_mp3 has
# written it to the caller's buffer), as in dr_mp3. The
# reservoir and the Layer III state are left as they are.
def frame.layer12.done(frame: L12.Frame, +h: U32, +free: U32, +bytes: U32, +decoder: Decoder) -> Decoded:
  L12.Frame{+buffers, +fine} = frame
  Decoder{H.Dec{_, _, +reserv}, +array, +scf, +ist0, +ist1, +compress, +overlap0, +overlap1, +qmf} = decoder
  +made = layer12.synth(buffers, H.hdr.mono(h), qmf, Nil{})
  Decoded{Decoder{H.Dec{Bool.pick(U32, fine, h, (h .&. 16777215 : U32)), free, reserv}, array, scf, ist0, ist1, compress, overlap0, overlap1, Synth.history(made)},
    Bool.pick(U32, fine, H.hdr.samples(h), 0), bytes, 0, Nil{}, Synth.pcm(made)}

def frame.layer12(+at: +List<U32>, +size: U32, +skip: U32, +free: U32, +decoder: Decoder) -> Decoded:
  +h = H.word(at)
  frame.layer12.done(L12.frame.read(h, List.drop(&2, U32, at, 4n), ((size - 4) * 8 : U32), Bool.pick(U32, H.hdr.crc(h), 16, 0)), h, free, (skip + size : U32), decoder)

# The frame whose header is at `at`, `size` bytes with its padding, after
# `skip` bytes.
def frame.at(layer3: Bool, +at: +List<U32>, +size: U32, +skip: U32, +free: U32, +decoder: Decoder) -> Decoded:
  match layer3:
    case True{}: frame.layer3(at, size, skip, free, decoder)
    case False{}: frame.layer12(at, size, skip, free, decoder)

# The frame the search found in a zeroed decoder, or none: every byte
# searched is used.
def frame.found(found: H.Found, +window: +List<U32>) -> Decoded:
  match found:
    case H.Found{+skip, 0, +free}: Decoded{Decoder{H.Dec{0, free, Nil{}}, zeros.onto(2815n, Nil{}), zeros.onto(40n, Nil{}), zeros.onto(39n, Nil{}), zeros.onto(39n, Nil{}), 0, zeros.onto(288n, Nil{}), zeros.onto(288n, Nil{}), rows.zero(15n, Nil{})}, 0, skip, 0, Nil{}, Nil{}}
    case H.Found{+skip, +size, +free}:
      +at = List.drop(&2, U32, window, U32.to_nat(skip))
      frame.at(U32.is_eq(H.hdr.layer(H.word(at)), 1), at, size, skip, free, Decoder.zero())

def frame.next(follows: Bool, +decoder: Decoder, +window: +List<U32>, +bytes: U32) -> Decoded:
  match follows:
    case False{}: frame.found(H.find(window, bytes, 0), window)
    case True{}:
      Decoder{H.Dec{_, +free, _}, _, _, _, _, _, _, _, _} = decoder
      frame.at(U32.is_eq(H.hdr.layer(H.word(window)), 1), window, (H.hdr.bytes(H.word(window), free) + H.hdr.padding(H.word(window)) : U32), 0, free, decoder)

# drmp3dec_decode_frame on `bytes` bytes, its samples wanted. A frame that
# follows the last one's header is taken
# where it stands (H.decode.follows); otherwise the decoder is zeroed, its
# scratch too, and a frame is searched for.
def decode(+decoder: Decoder, +window: +List<U32>, +bytes: U32) -> Decoded:
  Decoder{H.Dec{+header, +free, _}, _, _, _, _, _, _, _, _} = decoder
  frame.next(H.decode.follows(header, free, window, bytes), decoder, window, bytes)
