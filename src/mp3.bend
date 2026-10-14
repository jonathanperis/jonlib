# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of dr_mp3 v0.7.4 (David Reid; public domain or MIT
# No Attribution), which raylib 6.0 vendors in src/external/dr_mp3.h and
# whose decoder is minimp3 (lieff; CC0): the frame header, the search for a
# frame, Layer III's side information and bit reservoir, the stream's tags
# (ID3v1, APE, ID3v2, Xing/Info with LAME's delay and padding) and the frame
# count. See THIRD_PARTY_NOTICES.md and LICENSES/dr_mp3.txt.
#
# Bytes are U32 0..255 in lists, read forward only. C ints are U32
# two's-complement words.
import Base

# -----------------------------------------------------------------------------
# Bytes

# The first four bytes as one word, the first the highest; bytes past the end
# of the list are 0 (callers check the length first, as dr_mp3 does).
def word(bytes: +List<U32>) -> U32:
  match bytes:
    case Con{+a, Con{+b, Con{+c, Con{+d, _}}}}: ((((a << 24n) .|. (b << 16n)) .|. (c << 8n)) .|. d : U32)
    case Con{+a, Con{+b, Con{+c, Nil{}}}}: (((a << 24n) .|. (b << 16n)) .|. (c << 8n) : U32)
    case Con{+a, Con{+b, Nil{}}}: ((a << 24n) .|. (b << 16n) : U32)
    case Con{+a, Nil{}}: (a << 24n : U32)
    case Nil{}: 0

def b0(+h: U32) -> U32:
  (h >> 24n : U32)

def b1(+h: U32) -> U32:
  ((h >> 16n) .&. 255 : U32)

def b2(+h: U32) -> U32:
  ((h >> 8n) .&. 255 : U32)

def b3(+h: U32) -> U32:
  (h .&. 255 : U32)

def first(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{x, _}: x

# Byte i of a list, 0 past its end. (A Bool.pick over the recursion would
# walk the whole list, which may be the file.)
def nth(+xs: +List<U32>, +i: U32) -> U32:
  first(List.drop(&2, U32, xs, U32.to_nat(i)))

# -----------------------------------------------------------------------------
# The frame header (four bytes as a word)

def hdr.layer(+h: U32) -> U32:
  ((b1(h) >> 1n) .&. 3 : U32)

def hdr.bitrate(+h: U32) -> U32:
  (b2(h) >> 4n : U32)

def hdr.rate(+h: U32) -> U32:
  ((b2(h) >> 2n) .&. 3 : U32)

def hdr.mono(+h: U32) -> Bool:
  U32.is_eq((b3(h) .&. 192 : U32), 192)

def hdr.free(+h: U32) -> Bool:
  U32.is_eq((b2(h) .&. 240 : U32), 0)

def hdr.crc(+h: U32) -> Bool:
  U32.is_eq((b1(h) .&. 1 : U32), 0)

def hdr.mpeg1(+h: U32) -> Bool:
  U32.is_ne((b1(h) .&. 8 : U32), 0)

def hdr.not25(+h: U32) -> Bool:
  U32.is_ne((b1(h) .&. 16 : U32), 0)

def hdr.layer1(+h: U32) -> Bool:
  U32.is_eq((b1(h) .&. 6 : U32), 6)

def hdr.frame576(+h: U32) -> Bool:
  U32.is_eq((b1(h) .&. 14 : U32), 2)

# drmp3_hdr_valid.
def hdr.valid(+h: U32) -> Bool:
  U32.is_eq(b0(h), 255) && (U32.is_eq((b1(h) .&. 240 : U32), 240) || U32.is_eq((b1(h) .&. 254 : U32), 226)) && U32.is_ne(hdr.layer(h), 0) && U32.is_ne(hdr.bitrate(h), 15)
    && U32.is_ne(hdr.rate(h), 3)

# drmp3_hdr_compare: the second is a header of the same stream as the first.
def hdr.compare(+h1: U32, +h2: U32) -> Bool:
  hdr.valid(h2) && U32.is_eq(((b1(h1) .^. b1(h2)) .&. 254 : U32), 0) && U32.is_eq(((b2(h1) .^. b2(h2)) .&. 12 : U32), 0) && U32.is_eq(Bool.to_u32(hdr.free(h1)), Bool.to_u32(hdr.free(h2)))

def hdr.halfrate.v2() -> +List<+List<U32>>:
  [[0, 4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 56, 64, 72, 80], [0, 4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 56, 64, 72, 80], [0, 16, 24, 28, 32, 40, 48, 56, 64, 72, 80, 88, 96, 112, 128]]

def hdr.halfrate.v1() -> +List<+List<U32>>:
  [[0, 16, 20, 24, 28, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160], [0, 16, 24, 28, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192], [0, 16, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224]]

def row.first(rows: +List<+List<U32>>) -> +List<U32>:
  match rows:
    case Nil{}: Nil{}
    case Con{r, _}: r

def row(+rows: +List<+List<U32>>, +i: U32) -> +List<U32>:
  row.first(List.drop(&2, +List<U32>, rows, U32.to_nat(i)))

# drmp3_hdr_bitrate_kbps (the layer is 1..3; the bit rate index 0..14).
def hdr.kbps(+h: U32) -> U32:
  (2 * nth(row(Bool.pick(+List<+List<U32>>, hdr.mpeg1(h), hdr.halfrate.v1(), hdr.halfrate.v2()), (hdr.layer(h) - 1 : U32)), hdr.bitrate(h)) : U32)

# drmp3_hdr_sample_rate_hz.
def hdr.hz(+h: U32) -> U32:
  ((nth([44100, 48000, 32000], hdr.rate(h)) >> Bool.pick(Nat, hdr.mpeg1(h), 0n, 1n)) >> Bool.pick(Nat, hdr.not25(h), 0n, 1n) : U32)

# drmp3_hdr_frame_samples.
def hdr.samples(+h: U32) -> U32:
  Bool.pick(U32, hdr.layer1(h), 384, Bool.pick(U32, hdr.frame576(h), 576, 1152))

# drmp3_hdr_frame_bytes: the frame's bytes without its padding, or the free
# format size when the bit rate does not say.
def hdr.bytes(+h: U32, +free: U32) -> U32:
  +bytes = (((hdr.samples(h) * hdr.kbps(h)) * 125) / U32.max(hdr.hz(h), 1) : U32)
  +aligned = Bool.pick(U32, hdr.layer1(h), (bytes .&. 4294967292 : U32), bytes)
  Bool.pick(U32, U32.is_eq(aligned, 0), free, aligned)

# drmp3_hdr_padding.
def hdr.padding(+h: U32) -> U32:
  Bool.pick(U32, U32.is_ne((b2(h) .&. 2 : U32), 0), Bool.pick(U32, hdr.layer1(h), 4, 1), 0)

# -----------------------------------------------------------------------------
# The search for a frame

# drmp3d_match_frame: up to ten headers of the same stream follow one another
# in the `bytes` bytes from the first, each where the one before says. `at`
# is the last header reached (`i` bytes in, `matched` jumps so far); `past`:
# it would end past the bytes; `same`: it is a header of the first's stream.
def match.frame(n: Nat, past: Bool, same: Bool, +first: U32, +at: +List<U32>, +i: U32, +bytes: U32, +free: U32, +matched: U32) -> Bool:
  match n:
    case 0n:
      match past same:
        case True{} _: (matched > 1 : U32)
        case False{} +found: found
    case 1n+rest:
      match past same:
        case True{} _: (matched > 1 : U32)
        case False{} False{}: False{}
        case False{} True{}:
          +step = (hdr.bytes(word(at), free) + hdr.padding(word(at)) : U32)
          match.frame(rest, (((i + step) + 4) > bytes : U32), hdr.compare(first, word(List.drop(&2, U32, at, U32.to_nat(U32.min(step, 65536))))), first,
            List.drop(&2, U32, at, U32.to_nat(U32.min(step, 65536))), (i + step : U32), bytes, free, (matched + 1 : U32))

def matches(+at: +List<U32>, +bytes: U32, +free: U32) -> Bool:
  match.frame(10n, False{}, True{}, word(at), at, 0, bytes, free, 0)

# A free-format frame at k bytes: a header of the same stream stands k bytes
# on, and another one a frame further (`ahead` is the bytes from i + k).
def free.found(+h: U32, +ahead: +List<U32>, +i: U32, +k: U32, +bytes: U32) -> Bool:
  +nextfb = ((k - hdr.padding(h)) + hdr.padding(word(ahead)) : U32)
  hdr.compare(h, word(ahead)) && ((((i + k) + nextfb) + 4) <= bytes : U32) && hdr.compare(h, word(List.drop(&2, U32, ahead, U32.to_nat(U32.min(nextfb, 4096)))))

# The search goes on while k is below 2304 and the byte i + 2k is before the
# last four.
def free.go(+i: U32, +k: U32, +bytes: U32) -> Bool:
  (k < 2304 : U32) && (((i + (2 * k)) + 4) < bytes : U32)

# A free-format frame's bytes with its padding: the first k from 4 at which
# free.found holds, 0 when the search ends without one.
def free.size(n: Nat, go: Bool, found: Bool, +h: U32, +ahead: +List<U32>, +i: U32, +k: U32, +bytes: U32) -> U32:
  match n:
    case 0n: 0
    case 1n+rest:
      match go found:
        case False{} _: 0
        case True{} True{}: k
        case True{} False{}:
          free.size(rest, free.go(i, (k + 1 : U32), bytes), free.found(h, List.drop(&2, U32, ahead, 1n), i, (k + 1 : U32), bytes), h, List.drop(&2, U32, ahead, 1n), i, (k + 1 : U32), bytes)

def free.search(needed: Bool, +h: U32, +at: +List<U32>, +i: U32, +bytes: U32) -> U32:
  match needed:
    case False{}: 0
    case True{}: free.size(2304n, free.go(i, 4, bytes), free.found(h, List.drop(&2, U32, at, 4n), i, 4, bytes), h, List.drop(&2, U32, at, 4n), i, 4, bytes)

def matched(sized: Bool, +at: +List<U32>, +bytes: U32, +free: U32) -> Bool:
  match sized:
    case False{}: False{}
    case True{}: matches(at, bytes, free)

# One position of drmp3d_find_frame. state 2: the position is within the last
# four bytes (the search is over); 1: a frame of `size` bytes with its
# padding begins here; 0: none does. `free` is the free format size after it.
type Cand is Data:
  Cand{state: U32, size: U32, free: U32}

def candidate(+at: +List<U32>, +i: U32, +bytes: U32, +free: U32) -> Cand:
  +h = word(at)
  +inside = ((i + 4) < bytes : U32)
  +valid = inside && hdr.valid(h)
  +k = free.search(valid && U32.is_eq(hdr.bytes(h, free), 0), h, at, i, bytes)
  +fb = Bool.pick(U32, U32.is_ne(k, 0), (k - hdr.padding(h) : U32), hdr.bytes(h, free))
  +size = Bool.pick(U32, U32.is_ne(k, 0), k, (hdr.bytes(h, free) + hdr.padding(h) : U32))
  +found = matched(valid && U32.is_ne(fb, 0) && ((i + size) <= bytes : U32), at, (bytes - i : U32), fb) || (valid && U32.is_eq(i, 0) && U32.is_eq(size, bytes))
  Cand{Bool.pick(U32, inside, Bool.pick(U32, found, 1, 0), 2), size, Bool.pick(U32, valid, Bool.pick(U32, found, Bool.pick(U32, U32.is_ne(k, 0), fb, free), 0), free)}

# What drmp3d_find_frame gives: the bytes before the frame, the frame's bytes
# with its padding (0: none found), and the free format size it leaves.
type Found is Data:
  Found{skip: U32, size: U32, free: U32}

def find.frame(n: Nat, cand: Cand, +at: +List<U32>, +i: U32, +bytes: U32) -> Found:
  match n:
    case 0n: Found{bytes, 0, 0}
    case 1n+rest:
      match cand:
        case Cand{2, _, +free}: Found{bytes, 0, free}
        case Cand{1, +size, +free}: Found{i, size, free}
        case Cand{_, _, +free}: find.frame(rest, candidate(List.drop(&2, U32, at, 1n), (i + 1 : U32), bytes, free), List.drop(&2, U32, at, 1n), (i + 1 : U32), bytes)

# drmp3d_find_frame over `bytes` bytes.
def find(+at: +List<U32>, +bytes: U32, +free: U32) -> Found:
  find.frame(U32.to_nat((bytes + 1 : U32)), candidate(at, 0, bytes, free), at, 0, bytes)

# -----------------------------------------------------------------------------
# Bits (drmp3_bs_get_bits) of a short byte list, by position: n bits (at most
# 16) from bit `pos`, the first the highest; 0 when they end past `limit`
# bits, as the reader gives once its position is past its limit.
def bits(+bytes: +List<U32>, +limit: U32, +pos: U32, +n: U32) -> U32:
  +at = List.drop(&2, U32, bytes, U32.to_nat((pos / 8 : U32)))
  +three = (word(at) >> 8n : U32)
  Bool.pick(U32, ((pos + n) > limit : U32), 0, ((three >> U32.to_nat(((24 - (pos % 8)) - n : U32))) .&. ((1 << U32.to_nat(n)) - 1) : U32))

# -----------------------------------------------------------------------------
# Layer III side information (drmp3_L3_read_side_info)

# A granule of a channel: part_23_length, big_values, global_gain,
# scalefac_compress, block_type, mixed_block_flag, the three table_select,
# the three region_count (255: to the end), the three subblock_gain, preflag,
# scalefac_scale, count1_table, scfsi, and its scalefactor bands: the table
# (0 long, 1 short, 2 mixed) and the long and short band counts.
type Gr is Data:
  Gr{part23: U32, big: U32, gain: U32, compress: U32, block: U32, mixed: U32, table0: U32, table1: U32, table2: U32, region0: U32, region1: U32, region2: U32,
    sub0: U32, sub1: U32, sub2: U32, preflag: U32, scale: U32, count1: U32, scfsi: U32, bands: U32, long: U32, short: U32}

# What the reader leaves: -1 as its result (`bad`), main_data_begin, the
# granules in order and the bits read.
type Side is Data:
  Side{bad: Bool, begin: U32, grs: +List<Gr>, pos: U32}

# One granule at bit g. The reader leaves region_count[2] as it was for a
# granule that switches windows; its second region is 255 bands, which is
# every band there is, so the third is never reached: 255 here.
def side.gr(+bytes: +List<U32>, +limit: U32, +g: U32, +mpeg1: Bool, +scfsi: U32) -> Gr:
  +c = Bool.pick(U32, mpeg1, 4, 9)
  +compress = bits(bytes, limit, (g + 29 : U32), c)
  +switching = U32.is_ne(bits(bytes, limit, ((g + 29) + c : U32), 1), 0)
  +block = Bool.pick(U32, switching, bits(bytes, limit, ((g + 30) + c : U32), 2), 0)
  +mixed = Bool.pick(U32, switching, bits(bytes, limit, ((g + 32) + c : U32), 1), 0)
  +short = U32.is_eq(block, 2)
  +tables = Bool.pick(U32, switching, (bits(bytes, limit, ((g + 33) + c : U32), 10) << 5n : U32), bits(bytes, limit, ((g + 30) + c : U32), 15))
  +tail = ((g + 52) + c : U32)
  Gr{bits(bytes, limit, g, 12), bits(bytes, limit, (g + 12 : U32), 9), bits(bytes, limit, (g + 21 : U32), 8), compress, block, mixed,
    (tables >> 10n : U32), ((tables >> 5n) .&. 31 : U32), (tables .&. 31 : U32),
    Bool.pick(U32, switching, Bool.pick(U32, short && U32.is_eq(mixed, 0), 8, 7), bits(bytes, limit, ((g + 45) + c : U32), 4)),
    Bool.pick(U32, switching, 255, bits(bytes, limit, ((g + 49) + c : U32), 3)),
    255,
    Bool.pick(U32, switching, bits(bytes, limit, ((g + 43) + c : U32), 3), 0), Bool.pick(U32, switching, bits(bytes, limit, ((g + 46) + c : U32), 3), 0),
    Bool.pick(U32, switching, bits(bytes, limit, ((g + 49) + c : U32), 3), 0),
    Bool.pick(U32, mpeg1, bits(bytes, limit, tail, 1), Bool.to_u32((compress >= 500 : U32))),
    bits(bytes, limit, Bool.pick(U32, mpeg1, (tail + 1 : U32), tail), 1), bits(bytes, limit, Bool.pick(U32, mpeg1, (tail + 2 : U32), (tail + 1 : U32)), 1),
    ((scfsi >> 12n) .&. 15 : U32),
    Bool.pick(U32, short, Bool.pick(U32, U32.is_eq(mixed, 0), 1, 2), 0),
    Bool.pick(U32, short, Bool.pick(U32, U32.is_eq(mixed, 0), 0, Bool.pick(U32, mpeg1, 8, 6)), 22),
    Bool.pick(U32, short, Bool.pick(U32, U32.is_eq(mixed, 0), 39, 30), 0)}

def Gr.part23(+gr: Gr) -> U32:
  Gr{part23, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = gr
  part23

def Gr.big(+gr: Gr) -> U32:
  Gr{_, big, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = gr
  big

def Gr.block(+gr: Gr) -> U32:
  Gr{_, _, _, _, block, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = gr
  block

# The window switching flag of the granule at bit g, and its granule's bits.
def side.switching(+bytes: +List<U32>, +limit: U32, +g: U32, +mpeg1: Bool) -> Bool:
  U32.is_ne(bits(bytes, limit, ((g + 29) + Bool.pick(U32, mpeg1, 4, 9) : U32), 1), 0)

def side.width(+mpeg1: Bool) -> U32:
  Bool.pick(U32, mpeg1, 59, 63)

# The granules in turn. `scfsi` is the reader's shifting word and `sum` the
# part_23_length so far. A granule with more than 288 big values, or that
# switches windows to block type 0, ends the reading with -1.
def side.grs(n: Nat, bad: Bool, +bytes: +List<U32>, +limit: U32, +g: U32, +mpeg1: Bool, +mono: Bool, +scfsi: U32, +sum: U32, +acc: +List<Gr>) -> Side:
  match n:
    case 0n: Side{bad, sum, List.reverse(&2, Gr, acc), g}
    case 1n+rest:
      match bad:
        case True{}: Side{True{}, sum, List.reverse(&2, Gr, acc), g}
        case False{}:
          +shifted = Bool.pick(U32, mono, (scfsi << 4n : U32), scfsi)
          +short = side.switching(bytes, limit, g, mpeg1) && U32.is_eq(bits(bytes, limit, ((g + 30) + Bool.pick(U32, mpeg1, 4, 9) : U32), 2), 2)
          +masked = Bool.pick(U32, short, (shifted .&. 3855 : U32), shifted)
          +gr = side.gr(bytes, limit, g, mpeg1, masked)
          side.grs(rest, (Gr.big(gr) > 288 : U32) || (side.switching(bytes, limit, g, mpeg1) && U32.is_eq(Gr.block(gr), 0)), bytes, limit, (g + side.width(mpeg1) : U32), mpeg1, mono,
            (masked << 4n : U32), (sum + Gr.part23(gr) : U32), Con{gr, acc})

# drmp3_L3_read_side_info on the bytes after the header (and the CRC): `start`
# is the bit it begins at, `limit` the bits there are. The result's `begin` is
# main_data_begin; `bad` is the reader's -1, also when the granules' data
# would not fit (part_23_sum + pos > limit + main_data_begin*8).
def side.finish(side: Side, +limit: U32, +begin: U32) -> Side:
  Side{+bad, +sum, grs, +pos} = side
  Side{bad || ((sum + pos) > (limit + (begin * 8)) : U32), begin, grs, pos}

def side.read(+bytes: +List<U32>, +limit: U32, +start: U32, +h: U32) -> Side:
  +mpeg1 = hdr.mpeg1(h)
  +mono = hdr.mono(h)
  +count = Bool.pick(U32, mono, Bool.pick(U32, mpeg1, 2, 1), Bool.pick(U32, mpeg1, 4, 2))
  +begin = Bool.pick(U32, mpeg1, bits(bytes, limit, start, 9), (bits(bytes, limit, start, (8 + count : U32)) >> U32.to_nat(count) : U32))
  +scfsi = Bool.pick(U32, mpeg1, bits(bytes, limit, (start + 9 : U32), (7 + count : U32)), 0)
  side.finish(side.grs(U32.to_nat(count), False{}, bytes, limit, Bool.pick(U32, mpeg1, ((start + 16) + count : U32), ((start + 8) + count : U32)), mpeg1, mono, scfsi, 0, Nil{}), limit, begin)

# -----------------------------------------------------------------------------
# The decoder (drmp3dec) as far as counting frames needs it: the last
# header (0 in its first byte: none), the free format size and the bit
# reservoir (at most 511 bytes of main data that the next frames may reach
# back into).
type Dec is Data:
  Dec{header: U32, free: U32, reserv: +List<U32>}

def Dec.zero() -> Dec:
  Dec{0, 0, Nil{}}

def count(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def take.onto(n: Nat, xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k:
      match xs:
        case Nil{}: acc
        case Con{+x, rest}: take.onto(k, rest, Con{x, acc})

# The first n of a list.
def take(+n: U32, +xs: +List<U32>) -> +List<U32>:
  List.reverse(&2, U32, take.onto(U32.to_nat(n), xs, Nil{}))

# The last n of a list of `len`.
def last(+n: U32, +len: U32, +xs: +List<U32>) -> +List<U32>:
  List.drop(&2, U32, xs, U32.to_nat((len - U32.min(n, len) : U32)))

# What drmp3dec_decode_frame gives: the decoder after it, the frame's samples
# (0: none decoded), the bytes it used (the frame's and those skipped before
# it), and the frame's header and place among those bytes (when it has one).
type Frame is Data:
  Frame{dec: Dec, samples: U32, bytes: U32, header: U32, skip: U32}

# Layer III without its samples: the side information, then the reservoir.
# drmp3_L3_restore_reservoir puts the last main_data_begin bytes of the
# reservoir before the frame's main data; without them all the frame decodes
# nothing. drmp3_L3_save_reservoir keeps what was not read of both, at most
# the last 511 bytes: here nothing is read (`used` 0: the frames are only
# counted). Side information that fails, or that the frame is too short for,
# clears the decoder's header (drmp3dec_init) and decodes nothing.
def layer3.kept(+main: +List<U32>, +len: U32, +used: U32) -> +List<U32>:
  last(U32.min((len - U32.min(used, len) : U32), 511), len, main)

def layer3.main(+reserv: +List<U32>, +have: U32, +begin: U32, +payload: +List<U32>, +from: U32, +bytes: U32) -> +List<U32>:
  List.append(&2, U32, last(U32.min(have, begin), have, reserv), take(bytes, List.drop(&2, U32, payload, U32.to_nat(from))))

def layer3.count(side: Side, +h: U32, +free: U32, +reserv: +List<U32>, +payload: +List<U32>, +limit: U32, +bytes: U32, +skip: U32) -> Frame:
  Side{+bad, +begin, _, +pos} = side
  +have = count(reserv, 0)
  +room = ((limit - U32.min(pos, limit)) / 8 : U32)
  Bool.pick(Frame, bad || (pos > limit : U32), Frame{Dec{(h .&. 16777215 : U32), free, reserv}, 0, bytes, h, skip},
    Frame{Dec{h, free, layer3.kept(layer3.main(reserv, have, begin, payload, (pos / 8 : U32), room), (U32.min(have, begin) + room : U32), 0)},
      Bool.pick(U32, (have >= begin : U32), hdr.samples(h), 0), bytes, h, skip})

# The frame whose header is at `at`, `size` bytes with its padding, after
# `skip` bytes. Layers I and II have no reservoir: their samples are the
# header's.
def frame.at(+at: +List<U32>, +size: U32, +skip: U32, +free: U32, +reserv: +List<U32>) -> Frame:
  +h = word(at)
  +limit = ((size - 4) * 8 : U32)
  +payload = List.drop(&2, U32, at, 4n)
  Bool.pick(Frame, U32.is_eq(hdr.layer(h), 1),
    layer3.count(side.read(payload, limit, Bool.pick(U32, hdr.crc(h), 16, 0), h), h, free, reserv, payload, limit, (skip + size : U32), skip),
    Frame{Dec{h, free, reserv}, hdr.samples(h), (skip + size : U32), h, skip})

# The frame the search found, or none: every byte searched is used.
def frame.found(found: Found, +window: +List<U32>) -> Frame:
  match found:
    case Found{+skip, 0, +free}: Frame{Dec{0, free, Nil{}}, 0, skip, 0, skip}
    case Found{+skip, +size, +free}: frame.at(List.drop(&2, U32, window, U32.to_nat(skip)), size, skip, free, Nil{})

# drmp3dec_decode_frame without the samples, on `bytes` bytes. A frame that
# follows the last one's header is taken where it stands: when the bytes end
# with it, or a header of the same stream follows it. Otherwise the decoder
# is cleared and a frame is searched for.
def decode.next(follows: Bool, dec: Dec, +window: +List<U32>, +bytes: U32) -> Frame:
  match follows:
    case False{}: frame.found(find(window, bytes, 0), window)
    case True{}:
      Dec{_, +free, +reserv} = dec
      frame.at(window, (hdr.bytes(word(window), free) + hdr.padding(word(window)) : U32), 0, free, reserv)

def decode.follows(+header: U32, +free: U32, +window: +List<U32>, +bytes: U32) -> Bool:
  +size = (hdr.bytes(word(window), free) + hdr.padding(word(window)) : U32)
  (bytes > 4 : U32) && U32.is_eq(b0(header), 255) && hdr.compare(header, word(window)) && U32.is_ne(size, 0)
    && (U32.is_eq(size, bytes) || (((size + 4) <= bytes : U32) && hdr.compare(word(window), word(List.drop(&2, U32, window, U32.to_nat(U32.min(size, 65536)))))))

def decode(+dec: Dec, +window: +List<U32>, +bytes: U32) -> Frame:
  Dec{+header, +free, _} = dec
  decode.next(decode.follows(header, free, window, bytes), dec, window, bytes)

# -----------------------------------------------------------------------------
# The stream (drmp3): the file's bytes read through dr_mp3's buffer.
#
# `at` is the file from the first byte the buffer holds and `have` the bytes
# it holds; `pos` is the file's read position (the byte after them), and
# `cursor` what dr_mp3 takes it for (streamCursor: it goes back to the
# stream's start after an Xing/Info frame without the file's doing so, so
# the reads may then go that much past `length`). `size` is the file's bytes,
# `length` the bytes before the tags at its end, `start` where its frames
# begin, `cap` the buffer's capacity, `end` atEnd.
#
# A stream opened from memory (drmp3_init_memory) is read by another
# function, drmp3_decode_next_frame_ex__memory: there is no buffer, every
# frame is decoded from all the bytes left before the tags, and nothing is
# ever read past them. Here such a stream has a `cap` of 4294967295 and its
# "buffer" holds those bytes from the start; `end` is then that a decode
# found nothing more (dr_mp3 sets no flag and finds nothing again each time).
type Stream is Data:
  Stream{data: +List<U32>, size: U32, length: U32, start: U32, at: +List<U32>, have: U32, pos: U32, cursor: U32, cap: U32, end: Bool, dec: Dec,
    delay: U32, padding: U32, known: Bool, total: U32, channels: U32, rate: U32}

# drmp3__on_read_clamped of `want` bytes: no more than dr_mp3 thinks are left,
# and no more than the file has. The bytes read.
def stream.read(+size: U32, +length: U32, +pos: U32, +cursor: U32, +want: U32) -> U32:
  U32.min(U32.min(want, (length - U32.min(cursor, length) : U32)), (size - U32.min(pos, size) : U32))

# The buffer filled as drmp3_decode_next_frame_ex__callbacks begins a turn:
# below 16 KiB it is read up to its capacity (64 KiB at least); with nothing
# read and nothing held the stream is at its end. A memory stream has no
# buffer to fill.
def stream.fill(stream: Stream) -> Stream:
  Stream{data, +size, +length, start, at, +have, +pos, +cursor, +cap, +end, dec, delay, padding, known, total, channels, rate} = stream
  +low = (have < 16384 : U32) && Bool.not(end) && U32.is_ne(cap, 4294967295)
  +room = U32.max(cap, 65536)
  +more = Bool.pick(U32, low, stream.read(size, length, pos, cursor, (room - U32.min(have, room) : U32)), 0)
  Stream{data, size, length, start, at, (have + more : U32), (pos + more : U32), (cursor + more : U32), Bool.pick(U32, low, room, cap), end || (low && U32.is_eq((have + more : U32), 0)), dec,
    delay, padding, known, total, channels, rate}

def stream.memory(stream: Stream) -> Bool:
  Stream{_, _, _, _, _, _, _, _, cap, _, _, _, _, _, _, _, _} = stream
  U32.is_eq(cap, 4294967295)

def stream.stopped(stream: Stream, +end: Bool) -> Stream:
  Stream{data, size, length, start, at, have, pos, cursor, cap, _, dec, delay, padding, known, total, channels, rate} = stream
  Stream{data, size, length, start, at, have, pos, cursor, cap, end, dec, delay, padding, known, total, channels, rate}

# After a frame without samples took `bytes` of the buffer: the buffer is
# filled again; a memory stream goes on while bytes were passed and is over
# when none were.
def stream.refill(memory: Bool, +stream: Stream, +bytes: U32) -> Stream:
  match memory:
    case False{}: stream.fill(stream)
    case True{}: stream.stopped(stream, U32.is_eq(bytes, 0))

# The stream before its first frame: the file read from `start`, or for a
# memory stream every byte from there to `length`.
def stream.began(memory: Bool, +data: +List<U32>, +size: U32, +length: U32, +start: U32) -> Stream:
  match memory:
    case False{}: Stream{data, size, length, start, List.drop(&2, U32, data, U32.to_nat(U32.min(start, size))), 0, start, start, 0, False{}, Dec.zero(), 0, 0, False{}, 0, 0, 0}
    case True{}:
      Stream{data, size, length, start, List.drop(&2, U32, data, U32.to_nat(U32.min(start, size))), (length - U32.min(start, length) : U32), start, start, 4294967295, False{}, Dec.zero(), 0, 0, False{}, 0, 0,
        0}

# The next frame in the buffer.
def stream.frame(stream: Stream) -> Frame:
  Stream{_, _, _, _, +at, +have, _, _, _, _, +dec, _, _, _, _, _, _} = stream
  decode(dec, at, have)

# The buffer without the bytes a frame used, and the decoder after it.
def stream.used(stream: Stream, +dec: Dec, +bytes: U32) -> Stream:
  Stream{data, size, length, start, +at, +have, pos, cursor, cap, end, _, delay, padding, known, total, channels, rate} = stream
  Stream{data, size, length, start, List.drop(&2, U32, at, U32.to_nat(U32.min(bytes, have))), (have - U32.min(bytes, have) : U32), pos, cursor, cap, end, dec, delay, padding, known, total,
    channels, rate}

def stream.at(stream: Stream) -> +List<U32>:
  Stream{_, _, _, _, at, _, _, _, _, _, _, _, _, _, _, _, _} = stream
  at

def stream.ended(stream: Stream) -> Bool:
  Stream{_, _, _, _, _, _, _, _, _, end, _, _, _, _, _, _, _} = stream
  end

# What drmp3_decode_next_frame_ex gives without the samples: the stream after
# it, the frame's samples (0: the stream ended), its header, and the bytes of
# the buffer it used with those skipped before it (`region` begins there).
type Next is Data:
  Next{stream: Stream, samples: U32, header: U32, bytes: U32, region: +List<U32>}

# The loop of drmp3_decode_next_frame_ex__callbacks: a frame is decoded from
# the buffer and its bytes leave it; one with samples ends the loop, anything
# else (bytes that are no frame, a frame that decodes nothing) is passed and
# the buffer filled again. `frame` is the frame of `stream`'s buffer. For a
# memory stream it is drmp3_decode_next_frame_ex__memory's loop: the same
# without a buffer, over when a decode passes no byte.
def stream.loop(n: Nat, ended: Bool, frame: Frame, +stream: Stream) -> Next:
  match n:
    case 0n: Next{stream, 0, 0, 0, Nil{}}
    case 1n+rest:
      match ended frame:
        case True{} _: Next{stream, 0, 0, 0, Nil{}}
        case False{} Frame{+dec, 0, +bytes, _, _}:
          +next = stream.refill(stream.memory(stream), stream.used(stream, dec, bytes), bytes)
          stream.loop(rest, stream.ended(next), stream.frame(next), next)
        case False{} Frame{+dec, +samples, +bytes, +header, _}: Next{stream.used(stream, dec, bytes), samples, header, bytes, stream.at(stream)}

def stream.size(stream: Stream) -> U32:
  Stream{_, size, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = stream
  size

# drmp3_decode_next_frame_ex with no buffer for the samples.
def stream.next(+stream: Stream) -> Next:
  +filled = stream.fill(stream)
  stream.loop(U32.to_nat(((stream.size(stream) / 4) + 16 : U32)), stream.ended(filled), stream.frame(filled), filled)

# -----------------------------------------------------------------------------
# drmp3_init: the tags, then the first frame.

def begins(+bytes: +List<U32>, +a: U32, +b: U32, +c: U32) -> Bool:
  U32.is_eq(nth(bytes, 0), a) && U32.is_eq(nth(bytes, 1), b) && U32.is_eq(nth(bytes, 2), c)

# An ID3v1 tag: the last 128 bytes of a longer file begin with "TAG".
def tags.id3v1(+data: +List<U32>, +size: U32) -> U32:
  Bool.pick(U32, (size > 128 : U32) && begins(List.drop(&2, U32, data, U32.to_nat((size - U32.min(128, size) : U32))), 84, 65, 71), (size - 128 : U32), size)

# An APE tag: the 32 bytes before `len` begin with "APETAGEX", and the tag's
# size (the four bytes from the 24th, little-endian) plus 32 is less than
# the stream.
def tags.ape.size(+footer: +List<U32>) -> U32:
  ((((nth(footer, 24) .|. (nth(footer, 25) << 8n)) .|. (nth(footer, 26) << 16n)) .|. (nth(footer, 27) << 24n)) + 32 : U32)

def tags.ape.is(+f: +List<U32>) -> Bool:
  U32.is_eq(word(f), 1095779668) && U32.is_eq(word(List.drop(&2, U32, f, 4n)), 1095189848)

def tags.ape(+data: +List<U32>, +len: U32) -> U32:
  +footer = List.drop(&2, U32, data, U32.to_nat((len - U32.min(32, len) : U32)))
  Bool.pick(U32, (len > 32 : U32) && tags.ape.is(footer) && (tags.ape.size(footer) < len : U32), (len - tags.ape.size(footer) : U32), len)

# An ID3v2 tag at the start: "ID3", its size in four bytes of seven bits and
# ten more with a footer, after ten bytes of header. 0 without one.
def tags.id3v2(+data: +List<U32>) -> U32:
  +size = (((((nth(data, 6) .&. 127) << 21n) .|. ((nth(data, 7) .&. 127) << 14n)) .|. ((nth(data, 8) .&. 127) << 7n)) .|. (nth(data, 9) .&. 127) : U32)
  Bool.pick(U32, begins(data, 73, 68, 51), ((10 + size) + Bool.pick(U32, U32.is_ne((nth(data, 5) .&. 16 : U32), 0), 10, 0) : U32), 0)

# The Xing/Info frame's fields after its eight bytes of name and flags: the
# offset of what follows the frames, bytes, table and scale fields.
def info.fields(+flags: U32) -> U32:
  ((((8 + Bool.pick(U32, U32.is_ne((flags .&. 1 : U32), 0), 4, 0)) + Bool.pick(U32, U32.is_ne((flags .&. 2 : U32), 0), 4, 0)) + Bool.pick(U32, U32.is_ne((flags .&. 4 : U32), 0), 100, 0))
    + Bool.pick(U32, U32.is_ne((flags .&. 8 : U32), 0), 4, 0) : U32)

# What the first frame says of the stream when it is an Xing or Info frame:
# whether it is one, the frames it counts (4294967295: it does not say) and
# LAME's delay and padding (0 without them).
type Info is Data:
  Info{tagged: Bool, frames: U32, delay: U32, padding: U32}

# `tag` is the frame from the byte after its side information, `offset` that
# byte's place in the frame and `bytes` the frame's bytes (with those skipped
# before it, which dr_mp3 counts in). LAME's delay is twelve bits and 529
# more; its padding the next twelve less 529, not below 0.
def info.read(+tag: +List<U32>, +offset: U32, +bytes: U32) -> Info:
  +named = U32.is_eq(word(tag), 1483304551) || U32.is_eq(word(tag), 1231971951)
  +flags = nth(tag, 7)
  +p = info.fields(flags)
  +lame = named && U32.is_ne(nth(tag, p), 0) && ((((offset + p) + 21) + 14) < bytes : U32)
  +raw = (((nth(tag, (p + 22 : U32)) .&. 15) << 8n) .|. nth(tag, (p + 23 : U32)) : U32)
  Info{named, Bool.pick(U32, named && U32.is_ne((flags .&. 1 : U32), 0), word(List.drop(&2, U32, tag, 8n)), 4294967295),
    Bool.pick(U32, lame, (((nth(tag, (p + 21 : U32)) << 4n) .|. (nth(tag, (p + 22 : U32)) >> 4n)) + 529 : U32), 0),
    Bool.pick(U32, lame && (raw > 529 : U32), (raw - 529 : U32), 0)}

# The first frame read as Layer III side information, whatever its layer
# (dr_mp3 does not look): only side information that reads tells of a tag.
def info.of(side: Side, +region: +List<U32>, +bytes: U32) -> Info:
  Side{+bad, _, _, +pos} = side
  Bool.pick(Info, bad, Info{False{}, 4294967295, 0, 0}, info.read(List.drop(&2, U32, region, U32.to_nat((4 + (pos / 8) : U32))), (4 + (pos / 8) : U32), bytes))

def info.first(+region: +List<U32>, +bytes: U32) -> Info:
  info.of(side.read(List.drop(&2, U32, region, 4n), ((bytes - 4) * 8 : U32), Bool.pick(U32, hdr.crc(word(region)), 16, 0), word(region)), region, bytes)

# An open stream, and whether its first frame stays to be played (it is not
# an Xing/Info frame).
type Opened is Data:
  Opened{stream: Stream, first: Bool}

# The stream once its first frame is decoded. An Xing/Info frame is not
# played: the stream starts after it, and the decoder's header is cleared.
def open.first(info: Info, stream: Stream, +samples: U32, +header: U32, +bytes: U32) -> Stream:
  Info{+tagged, +frames, +delay, +padding} = info
  Stream{data, size, length, +start, at, have, pos, +cursor, cap, end, Dec{+last, +free, +reserv}, _, _, _, _, _, _} = stream
  Stream{data, size, length, Bool.pick(U32, tagged, (start + bytes : U32), start), at, have, pos, Bool.pick(U32, tagged, (start + bytes : U32), cursor), cap, end,
    Dec{Bool.pick(U32, tagged, (last .&. 16777215 : U32), last), free, reserv}, delay, padding, U32.is_ne(frames, 4294967295), (frames * samples : U32),
    Bool.pick(U32, hdr.mono(header), 1, 2), hdr.hz(header)}

def open.tagged(info: Info, +stream: Stream, +samples: U32, +header: U32, +bytes: U32) -> Maybe<Opened>:
  Info{+tagged, +frames, +delay, +padding} = info
  Some{Opened{open.first(Info{tagged, frames, delay, padding}, stream, samples, header, bytes), Bool.not(tagged)}}

# The stream, and whether its first frame stays to be played (it is not an
# Xing/Info frame).
def open.next(next: Next) -> Maybe<Opened>:
  match next:
    case Next{_, 0, _, _, _}: None{}
    case Next{+stream, +samples, +header, +bytes, +region}: open.tagged(info.first(region, bytes), stream, samples, header, bytes)

def open.sized(long: Bool, +memory: Bool, +data: +List<U32>, +size: U32) -> Maybe<Opened>:
  match long:
    case False{}: None{}
    case True{}:
      +length = tags.ape(data, tags.id3v1(data, size))
      +start = tags.id3v2(data)
      open.next(stream.next(stream.began(memory && U32.is_ne(length, 0), data, size, length, start)))

# drmp3_init_file on the file's bytes: None where it fails (fewer than ten
# bytes, or no frame that decodes).
def open(+data: +List<U32>) -> Maybe<Opened>:
  open.sized((count(data, 0) >= 10 : U32), False{}, data, count(data, 0))

# drmp3_init_memory on the same bytes. dr_mp3 reads a memory stream with its
# memory function while the stream has bytes before its tags, and through
# its callbacks otherwise.
def open.memory(+data: +List<U32>) -> Maybe<Opened>:
  open.sized((count(data, 0) >= 10 : U32), True{}, data, count(data, 0))

# -----------------------------------------------------------------------------
# Counting (drmp3_get_pcm_frame_count)

# drmp3_seek_to_start_of_stream: the file at the stream's start, the buffer
# empty (a memory stream has its bytes from there) and the decoder's header
# cleared.
def stream.rewound(stream: Stream) -> Stream:
  Stream{+data, +size, +length, +start, _, _, _, _, +cap, _, Dec{+last, +free, +reserv}, delay, padding, known, total, channels, rate} = stream
  Stream{data, size, length, start, List.drop(&2, U32, data, U32.to_nat(U32.min(start, size))), Bool.pick(U32, U32.is_eq(cap, 4294967295), (length - U32.min(start, length) : U32), 0), start, start, cap,
    False{}, Dec{(last .&. 16777215 : U32), free, reserv}, delay, padding, known, total, channels, rate}

# What a count gives: the frames that decode, their samples, and the header
# of the last of them (0 for none): dr_mp3 takes mp3FrameChannels from
# each frame it counts.
type Scanned is Data:
  Scanned{frames: U32, samples: U32, header: U32}

def Scanned.samples(scanned: Scanned) -> U32:
  Scanned{_, samples, _} = scanned
  samples

def Scanned.header(scanned: Scanned) -> U32:
  Scanned{_, _, header} = scanned
  header

# Every frame from here to the stream's end that decodes: how many, their
# samples and the last one's header (drmp3_get_mp3_and_pcm_frame_count's
# loop).
def count.frames(n: Nat, next: Next, +frames: U32, +samples: U32, +header: U32) -> Scanned:
  match n:
    case 0n: Scanned{frames, samples, header}
    case 1n+rest:
      match next:
        case Next{_, 0, _, _, _}: Scanned{frames, samples, header}
        case Next{+stream, +s, +h, _, _}: count.frames(rest, stream.next(stream), (frames + 1 : U32), (samples + s : U32), h)

# The MP3 frames of the stream, counted from its start.
def scan.all(+stream: Stream) -> Scanned:
  count.frames(U32.to_nat(((stream.size(stream) / 4) + 16 : U32)), stream.next(stream.rewound(stream)), 0, 0, 0)

def scan.pair(scanned: Scanned) -> U32 & U32:
  Scanned{frames, samples, _} = scanned
  (frames, samples)

# The MP3 frames of the stream and their PCM frames, counted from its start.
def scan(+stream: Stream) -> U32 & U32:
  scan.pair(scan.all(stream))

def scan.samples(counted: U32 & U32) -> U32:
  (_, samples) = counted
  samples

# The frames an Xing/Info frame counts, less LAME's delay and padding when
# they are no more than what is left.
def total.tagged(+total: U32, +delay: U32, +padding: U32) -> U32:
  +delayed = Bool.pick(U32, (total >= delay : U32), (total - delay : U32), total)
  Bool.pick(U32, (delayed >= padding : U32), (delayed - padding : U32), delayed)

def total.counted(known: Bool, +stream: Stream, +total: U32, +delay: U32, +padding: U32) -> U32:
  match known:
    case True{}: total.tagged(total, delay, padding)
    case False{}: scan.samples(scan(stream))

# drmp3_get_pcm_frame_count, as an unsigned int (raylib's music.frameCount).
def total(+stream: Stream) -> U32:
  Stream{_, _, _, _, _, _, _, _, _, _, _, +delay, +padding, +known, +total, _, _} = stream
  total.counted(known, stream, total, delay, padding)
