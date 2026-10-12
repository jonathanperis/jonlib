# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of dr_mp3 v0.7.4 (David Reid; public domain or MIT
# No Attribution; its decoder is minimp3, by lieff, CC0), as raylib 6.0
# vendors it in src/external/dr_mp3.h: Layer III's scalefactors
# (drmp3_L3_read_scalefactors, drmp3_L3_ldexp_q2,
# drmp3_L3_decode_scalefactors), its Huffman-coded values (drmp3_L3_pow_43,
# drmp3_L3_huffman), its stereo step (drmp3_L3_midside_stereo,
# drmp3_L3_intensity_stereo, drmp3_L3_stereo_process) and the frame around
# them (drmp3_L3_restore_reservoir, drmp3_L3_save_reservoir,
# drmp3dec_decode_frame). See THIRD_PARTY_NOTICES.md and LICENSES/dr_mp3.txt.
#
# Floats are binary32, computed in dr_mp3's order, and kept in lists as
# their bits. C ints are U32 two's-complement words. The tables are
# src/mp3_tables.bend, generated from the header (tools/mp3_tables.py); a
# table is a list built where it is named, so one that a loop reads is named
# once, outside the loop.
import Base
import ./mp3.bend as H
import ./mp3_tables.bend as T

def float(value: U32) -> F32:
  U32{word} = value
  F32{word}

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
        Read{Con{s, scf}, Con{Bool.pick(U32, limited && U32.is_eq(s, ((1 << U32.to_nat(size)) - 1 : U32)), 255, s), ist}, List.drop(&2, U32, old, 1n), (pos + size : U32)})

# A group kept from the granule before (scfsi): the positions as they were.
def read.kept(n: Nat, read: Read) -> Read:
  match n:
    case 0n: read
    case 1n+rest:
      Read{+scf, +ist, +old, pos} = read
      read.kept(rest, Read{Con{H.first(old), scf}, Con{H.first(old), ist}, List.drop(&2, U32, old, 1n), pos})

# A group of no bits: zeros.
def read.zeros(n: Nat, read: Read) -> Read:
  match n:
    case 0n: read
    case 1n+rest:
      Read{+scf, +ist, +old, pos} = read
      read.zeros(rest, Read{Con{0, scf}, Con{0, ist}, List.drop(&2, U32, old, 1n), pos})

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
              big.bands(k, (big > half : U32), rest, List.drop(&2, U32, scf, 1n), (big - pairs : U32), after, Bool.pick(U32, turn, pick3(after, 0, region1, region2), (cnt - 1 : U32)), turn, codes, gr,
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
        case Con{+width, rest}: Band{rest, List.drop(&2, U32, scf, 1n), (width / 2 : U32), Bool.pick(U32, (width < 2 : U32), one, H.first(scf)), (width < 2 : U32)}

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
# Frames (drmp3dec_decode_frame with its samples wanted), as far as the
# granules' values after the stereo step.

# The decoder between frames: drmp3dec's header, free format size and
# reservoir (H.Dec), and what its scratch keeps from a frame to the next:
# the main data's array (2815 bytes: a frame's main data is written over the
# start of what was there, and the values are read from it however far they
# go), the 40 scales (a granule writes its bands'; a table of more bands
# reads what is past them), the channels' intensity positions (39 each) and
# scalefac_compress of the second slot of the granule information, which a
# mono frame does not write and whose stereo step reads (stereo.shift).
type Decoder is Data:
  Decoder{dec: H.Dec, main: +List<U32>, scf: +List<U32>, ist0: +List<U32>, ist1: +List<U32>, compress: U32}

# A decoder zeroed: what drmp3dec_decode_frame makes of it before it
# searches for a frame.
def Decoder.zero() -> Decoder:
  Decoder{H.Dec.zero(), zeros.onto(2815n, Nil{}), zeros.onto(40n, Nil{}), zeros.onto(39n, Nil{}), zeros.onto(39n, Nil{}), 0}

# What a frame gives: the decoder after it, its samples for a channel (0:
# none decoded), the bytes it used, the granules' values after the stereo
# step (576 float bits for a channel of a granule, in the frame's order) and
# `status`: 0, or why the
# frame is refused. 1: dr_mp3 leaves one of its arrays, which is undefined:
# a granule's values were read past the main data's (it reads whatever
# follows in its struct), or a granule is a mixed block at 8000 Hz
# (reorder.inside). 2: a Layer I or II frame, which this port does not
# decode yet.
type Decoded is Data:
  Decoded{decoder: Decoder, samples: U32, bytes: U32, status: U32, spectra: +List<+List<U32>>}

def total(xs: +List<U32>, +sum: U32) -> U32:
  match xs:
    case Nil{}: sum
    case Con{+x, rest}: total(rest, (sum + x : U32))

# Whether drmp3_L3_reorder stays inside a granule's 576 values. It moves a
# granule's short bands, which begin after the long part: 18 values for each
# of a mixed block's long subbands, two of them, or four at 8000 Hz. There
# the mixed table's long bands are 48 values and its short bands 528, which
# from value 72 end 24 past the granule: dr_mp3 writes them over the other
# channel's values or over the scales (undefined), and the granule is
# refused. Every other table ends at 576.
def reorder.inside(+h: U32, +gr: H.Gr) -> Bool:
  H.Gr{_, _, _, _, _, +mixed, _, _, _, _, _, _, _, _, _, _, _, _, _, +kind, +long, +short} = gr
  +subbands = Bool.pick(U32, U32.is_eq(mixed, 0), 0, Bool.pick(U32, U32.is_eq(rate.index(h), 2), 4, 2))
  U32.is_eq(short, 0) || (((subbands * 18) + total(List.drop(&2, U32, bands(h, kind), U32.to_nat(long)), 0)) <= 576 : U32)

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
        case Con{+a, rest}: pair.kept(k, rest, List.drop(&2, U32, right, 1n), Con{a, al}, Con{H.first(right), ar})

# drmp3_L3_midside_stereo on `n` values: left a + b, right a - b.
def pair.midside(n: Nat, left: +List<U32>, +right: +List<U32>, al: +List<U32>, ar: +List<U32>) -> Both:
  match n:
    case 0n: Both{left, right, al, ar}
    case 1n+k:
      match left:
        case Nil{}: Both{Nil{}, right, al, ar}
        case Con{+a, rest}:
          pair.midside(k, rest, List.drop(&2, U32, right, 1n), Con{F32.bits((float(a) + float(H.first(right)) : F32)), al}, Con{F32.bits((float(a) - float(H.first(right)) : F32)), ar})

# drmp3_L3_intensity_stereo_band on `n` values: right is left times kr, then
# left is left times kl.
def pair.intensity(n: Nat, left: +List<U32>, +right: +List<U32>, +kl: F32, +kr: F32, al: +List<U32>, ar: +List<U32>) -> Both:
  match n:
    case 0n: Both{left, right, al, ar}
    case 1n+k:
      match left:
        case Nil{}: Both{Nil{}, right, al, ar}
        case Con{+a, rest}: pair.intensity(k, rest, List.drop(&2, U32, right, 1n), kl, kr, Con{F32.bits((float(a) * kl : F32)), al}, Con{F32.bits((float(a) * kr : F32)), ar})

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
              stereo.bands(k, U32.is_eq(H.first(rest), 0), rest, List.drop(&2, U32, ist, 1n), (i + 1 : U32), tops, mpeg1, sh, ms, table,
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

def Gr.first(grs: +List<H.Gr>, +or: H.Gr) -> H.Gr:
  match grs:
    case Nil{}: or
    case Con{gr, _}: gr

# Every granule of a frame: the bit after the last, the channels' intensity
# positions, the scales, whether every read was inside the array, and the
# values, a channel after a channel (the last first).
type Granules is Data:
  Granules{pos: U32, ist0: +List<U32>, ist1: +List<U32>, scf: +List<U32>, fine: Bool, spectra: +List<+List<U32>>}

def granules.pushed(mono: Bool, +left: +List<U32>, +right: +List<U32>, +out: +List<+List<U32>>) -> +List<+List<U32>>:
  match mono:
    case True{}: Con{left, out}
    case False{}: Con{right, Con{left, out}}

# `grs` is the side information's granules, a channel after a channel: one
# or two granules of one or two channels. `limit` is the main data's bits
# and `pos` the granule's first.
def granules(n: Nat, grs: +List<H.Gr>, +mono: Bool, +main: +List<U32>, +limit: U32, +pos: U32, +h: U32, +ist0: +List<U32>, +ist1: +List<U32>, +scf: +List<U32>, +sh: U32, +fine: Bool,
    +out: +List<+List<U32>>) -> Granules:
  match n:
    case 0n: Granules{pos, ist0, ist1, scf, fine, out}
    case 1n+k:
      match grs:
        case Nil{}: Granules{pos, ist0, ist1, scf, fine, out}
        case Con{+gr0, +rest}:
          +done = granule(mono, gr0, Gr.first(rest, gr0), main, limit, pos, h, ist0, ist1, scf, sh)
          granules(k, Bool.pick(+List<H.Gr>, mono, rest, List.drop(&2, H.Gr, rest, 1n)), mono, main, limit, Channels.pos(done), h, Channels.ist0(done), Channels.ist1(done), Channels.scf(done),
            sh, fine && Channels.fine(done), granules.pushed(mono, Channels.left(done), Channels.right(done), out))

# drmp3_L3_save_reservoir after the granules: what was not read of the main
# data is the next frames' reservoir.
def decoded.granules(grans: Granules, +h: U32, +free: U32, +main: +List<U32>, +len: U32, +array: +List<U32>, +bytes: U32, +compress: U32) -> Decoded:
  Granules{+pos, ist0, ist1, scf, +fine, spectra} = grans
  Decoded{Decoder{H.Dec{h, free, H.layer3.kept(main, len, ((pos + 7) / 8 : U32))}, array, scf, ist0, ist1, compress}, H.hdr.samples(h), bytes, Bool.pick(U32, fine, 0, 1),
    List.reverse(&2, +List<U32>, spectra)}

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
  Decoder{H.Dec{_, _, reserv}, _, _, _, _, _} = decoder
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
  Decoder{dec, main, scf, ist0, ist1, +compress} = decoder
  Decoder{dec, main, scf, ist0, ist1, slot.compress(List.drop(&2, H.Gr, Side.grs(side), 1n), compress)}

# A frame whose reservoir is short of main_data_begin: its main data is
# written and kept for the next frames, and nothing is decoded.
def frame.short(mained: +List<U32> & U32, +h: U32, +free: U32, +bytes: U32, decoder: Decoder) -> Decoded:
  (+main, +len) = mained
  Decoder{_, +array, scf, ist0, ist1, +compress} = decoder
  Decoded{Decoder{H.Dec{h, free, H.layer3.kept(main, len, 0)}, frame.array(main, len, array), scf, ist0, ist1, compress}, 0, bytes, 0, Nil{}}

def frame.full(mained: +List<U32> & U32, +grs: +List<H.Gr>, +h: U32, +free: U32, +bytes: U32, decoder: Decoder) -> Decoded:
  (+main, +len) = mained
  Decoder{_, +array, +scf, +ist0, +ist1, +compress} = decoder
  +whole = frame.array(main, len, array)
  decoded.granules(granules(2n, grs, H.hdr.mono(h), whole, (len * 8 : U32), 0, h, ist0, ist1, scf, (compress .&. 1 : U32), True{}, Nil{}), h, free, main, len, whole, bytes, compress)

# A Layer III frame by what its side information allows. 0: the side
# information failed or the frame is too short for it, which clears the
# decoder's header (drmp3dec_init) and nothing else; 1: the reservoir is
# short; 2: the granules are decoded.
def frame.side(state: U32, +side: H.Side, +h: U32, +free: U32, +payload: +List<U32>, +limit: U32, +bytes: U32, +decoder: Decoder) -> Decoded:
  match state:
    case 0:
      Decoder{H.Dec{_, _, +reserv}, +array, +scf, +ist0, +ist1, +compress} = decoder
      Decoded{Decoder{H.Dec{(h .&. 16777215 : U32), free, reserv}, array, scf, ist0, ist1, compress}, 0, bytes, 0, Nil{}}
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

# The frame whose header is at `at`, `size` bytes with its padding, after
# `skip` bytes.
def frame.at(layer3: Bool, +at: +List<U32>, +size: U32, +skip: U32, +free: U32, +decoder: Decoder) -> Decoded:
  match layer3:
    case True{}: frame.layer3(at, size, skip, free, decoder)
    case False{}:
      Decoder{H.Dec{_, _, +reserv}, +array, +scf, +ist0, +ist1, +compress} = decoder
      Decoded{Decoder{H.Dec{H.word(at), free, reserv}, array, scf, ist0, ist1, compress}, 0, (skip + size : U32), 2, Nil{}}

# The frame the search found in a zeroed decoder, or none: every byte
# searched is used.
def frame.found(found: H.Found, +window: +List<U32>) -> Decoded:
  match found:
    case H.Found{+skip, 0, +free}: Decoded{Decoder{H.Dec{0, free, Nil{}}, zeros.onto(2815n, Nil{}), zeros.onto(40n, Nil{}), zeros.onto(39n, Nil{}), zeros.onto(39n, Nil{}), 0}, 0, skip, 0, Nil{}}
    case H.Found{+skip, +size, +free}:
      +at = List.drop(&2, U32, window, U32.to_nat(skip))
      frame.at(U32.is_eq(H.hdr.layer(H.word(at)), 1), at, size, skip, free, Decoder.zero())

def frame.next(follows: Bool, +decoder: Decoder, +window: +List<U32>, +bytes: U32) -> Decoded:
  match follows:
    case False{}: frame.found(H.find(window, bytes, 0), window)
    case True{}:
      Decoder{H.Dec{_, +free, _}, _, _, _, _, _} = decoder
      frame.at(U32.is_eq(H.hdr.layer(H.word(window)), 1), window, (H.hdr.bytes(H.word(window), free) + H.hdr.padding(H.word(window)) : U32), 0, free, decoder)

# drmp3dec_decode_frame on `bytes` bytes, as far as this module goes: the
# granules' values after the stereo step. A frame that follows the last
# one's header is taken
# where it stands (H.decode.follows); otherwise the decoder is zeroed, its
# scratch too, and a frame is searched for.
def decode(+decoder: Decoder, +window: +List<U32>, +bytes: U32) -> Decoded:
  Decoder{H.Dec{+header, +free, _}, _, _, _, _, _} = decoder
  frame.next(H.decode.follows(header, free, window, bytes), decoder, window, bytes)
