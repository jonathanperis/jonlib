# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of dr_wav (David Reid; public domain or MIT-0, as
# pinned raylib 6.0 vendors it in src/external/dr_wav.h): drwav_init_memory's
# container detection and chunk walk (RIFF, RIFX, Wave64, RF64, AIFF and AIFC,
# with drwav_aiff_extented_to_s64) and drwav_read_pcm_frames_s16 for PCM, IEEE
# float (32- and 64-bit, drwav_f64_to_s16 through the checked binary64
# helpers), a-law, mu-law and (src/wav_adpcm.bend) MS and IMA ADPCM data. C
# ints are U32 two's-complement words; 64-bit values are two U32 words. See
# THIRD_PARTY_NOTICES.md.
import Base
import ./codec.bend as C
import ./binary64_fma.bend as F
import ./binary64_add_sub.bend as A
import ./binary64_ops.bend as O
import ./wav_adpcm.bend as P

# Samples are signed 16-bit values stored as their 16-bit pattern.
type Outcome is Type:
  Decoded{rate: U32, channels: U32, frames: U32, samples: +List<U32>}
  Unsupported{}
  Invalid{error: C.Error}

def head(rest: +List<U32>) -> U32:
  match rest:
    case Con{value, _}: value
    case Nil{}: 0

def at(+bytes: +List<U32>, +index: U32) -> U32:
  head(List.drop(&2, U32, bytes, U32.to_nat(index)))

def u16(+bytes: +List<U32>, +index: U32) -> U32:
  (at(bytes, index) .|. (at(bytes, (index + 1 : U32)) << 8n) : U32)

def u32(+bytes: +List<U32>, +index: U32) -> U32:
  (u16(bytes, index) .|. (u16(bytes, (index + 2 : U32)) << 16n) : U32)

def b16(+bytes: +List<U32>, +index: U32) -> U32:
  ((at(bytes, index) << 8n) .|. at(bytes, (index + 1 : U32)) : U32)

def b32(+bytes: +List<U32>, +index: U32) -> U32:
  ((b16(bytes, index) << 16n) .|. b16(bytes, (index + 2 : U32)) : U32)

# drwav_bytes_to_u16_ex / _u32_ex: big-endian for RIFX and AIFF.
def e16(+be: Bool, +bytes: +List<U32>, +index: U32) -> U32:
  Bool.pick(U32, be, b16(bytes, index), u16(bytes, index))

def e32(+be: Bool, +bytes: +List<U32>, +index: U32) -> U32:
  Bool.pick(U32, be, b32(bytes, index), u32(bytes, index))

def tag(+bytes: +List<U32>, +index: U32, +a: U32, +b: U32, +c: U32, +d: U32) -> Bool:
  U32.is_eq(at(bytes, index), a) && U32.is_eq(at(bytes, (index + 1 : U32)), b)
    && U32.is_eq(at(bytes, (index + 2 : U32)), c) && U32.is_eq(at(bytes, (index + 3 : U32)), d)

def negative(+x: U32) -> Bool:
  (x >= 2147483648 : U32)

def nonzero(+x: U32) -> U32:
  Bool.pick(U32, U32.is_eq(x, 0), 1, x)

# Bool.pick(Bool, c, a, b) as its own def: the pinned compiler's native
# lanes can lose a Bool.pick(Bool, ...) result that feeds || in the same def
# (reproduced in pure Base; JavaScript is unaffected), so Bools are never
# chosen inline here.
def either(c: Bool, a: Bool, b: Bool) -> Bool:
  match c:
    case True{}: a
    case False{}: b

# -----------------------------------------------------------------------------
# drwav_uint64 values (sizes, positions, sample counts) as two words, wrapping
# like C. Division and remainder take divisors below 2^16 (frame sizes, block
# alignments and channel counts).

type W is Data:
  W{hi: U32, lo: U32}

def W.hi(+w: W) -> U32:
  W{hi, _} = w
  hi

def W.lo(+w: W) -> U32:
  W{_, lo} = w
  lo

def W.small(+x: U32) -> W:
  W{0, x}

def W.add(+a: W, +b: W) -> W:
  +lo = (W.lo(a) + W.lo(b) : U32)
  W{(W.hi(a) + W.hi(b) + Bool.to_u32((lo < W.lo(a) : U32)) : U32), lo}

def W.sub(+a: W, +b: W) -> W:
  W{(W.hi(a) - W.hi(b) - Bool.to_u32((W.lo(a) < W.lo(b) : U32)) : U32), (W.lo(a) - W.lo(b) : U32)}

def W.less(+a: W, +b: W) -> Bool:
  (W.hi(a) < W.hi(b) : U32) || (U32.is_eq(W.hi(a), W.hi(b)) && (W.lo(a) < W.lo(b) : U32))

def W.is_zero(+a: W) -> Bool:
  U32.is_eq((W.hi(a) .|. W.lo(a) : U32), 0)

def W.is(+a: W, +x: U32) -> Bool:
  U32.is_eq(W.hi(a), 0) && U32.is_eq(W.lo(a), x)

# a * m (mod 2^64) for m < 2^16.
def W.mul(+a: W, +m: U32) -> W:
  +p0 = ((W.lo(a) .&. 65535) * m : U32)
  +p1 = ((W.lo(a) >> 16n) * m : U32)
  +lo = (p0 + (p1 << 16n) : U32)
  W{(W.hi(a) * m + (p1 >> 16n) + Bool.to_u32((lo < p0 : U32)) : U32), lo}

# Long division by 16-bit limbs; the partial remainders stay below 2^32.
def W.div(+a: W, +d: U32) -> W:
  +c3 = (W.hi(a) >> 16n : U32)
  +c2 = (((c3 % d) << 16n) .|. (W.hi(a) .&. 65535) : U32)
  +c1 = (((c2 % d) << 16n) .|. (W.lo(a) >> 16n) : U32)
  +c0 = (((c1 % d) << 16n) .|. (W.lo(a) .&. 65535) : U32)
  W{(((c3 / d) << 16n) .|. (c2 / d) : U32), (((c1 / d) << 16n) .|. (c0 / d) : U32)}

def W.mod(+a: W, +d: U32) -> U32:
  +c3 = (W.hi(a) >> 16n : U32)
  +c2 = (((c3 % d) << 16n) .|. (W.hi(a) .&. 65535) : U32)
  +c1 = (((c2 % d) << 16n) .|. (W.lo(a) >> 16n) : U32)
  +c0 = (((c1 % d) << 16n) .|. (W.lo(a) .&. 65535) : U32)
  (c0 % d : U32)

# a >> n for n in 0..63.
def W.shr(+a: W, +n: U32) -> W:
  +m = (n .&. 31 : U32)
  +high = (W.hi(a) >> U32.to_nat(m) : U32)
  +low = Bool.pick(U32, U32.is_eq(m, 0), W.lo(a), ((W.lo(a) >> U32.to_nat(m)) .|. (W.hi(a) << U32.to_nat(((32 - m) .&. 31 : U32))) : U32))
  Bool.pick(W, (n >= 32 : U32), W{0, high}, W{high, low})

def W.u64(+bytes: +List<U32>, +index: U32) -> W:
  W{u32(bytes, (index + 4 : U32)), u32(bytes, index)}

def W.be64(+bytes: +List<U32>, +index: U32) -> W:
  W{b32(bytes, index), b32(bytes, (index + 4 : U32))}

# drwav__seek_forward from `at` (at most `len`): it succeeds when the whole
# 64-bit offset fits before the end of the memory stream.
def fits(+len: U32, +at: U32, +offset: W) -> Bool:
  U32.is_eq(W.hi(offset), 0) && (W.lo(offset) <= (len - at) : U32)

# -----------------------------------------------------------------------------
# Container and chunk walk (drwav_init__internal). The memory stream position
# `pos` is what reads and seeks use; dr_wav's 64-bit `cursor` always agrees
# with it in the low word, and `chi` is its high word (a "fmt " chunk's
# leftover seek is an int while the cursor adds the 64-bit difference).

type Fmt is Data:
  Fmt{tag: U32, channels: U32, rate: U32, align: U32, bits: U32, sub: U32}

def Fmt.empty() -> Fmt:
  Fmt{0, 0, 0, 0, 0, 0}

# state: 0 walking, 1 stopped (the loop's break), 2 failed (init returns
# false), 3 undefined behavior in C. flags: 1 AIFC "sowt" (little-endian
# samples), 2 AIFC "raw " with 8-bit samples (unsigned); both are sticky.
type Scan is Data:
  Scan{pos: U32, chi: U32, has_fmt: Bool, fmt: Fmt, has_data: Bool, dpos: W, dsize: W, fact: W, frames: U32, flags: U32, state: U32}

def Scan.pos(+scan: Scan) -> U32:
  Scan{pos, _, _, _, _, _, _, _, _, _, _} = scan
  pos

def Scan.state(+scan: Scan) -> U32:
  Scan{_, _, _, _, _, _, _, _, _, _, state} = scan
  state

def Scan.with(+scan: Scan, +pos: U32, +state: U32) -> Scan:
  Scan{_, chi, has_fmt, fmt, has_data, dpos, dsize, fact, frames, flags, _} = scan
  Scan{pos, chi, has_fmt, fmt, has_data, dpos, dsize, fact, frames, flags, state}

def Scan.initial(+pos: U32, +dsize: W, +fact: W, +state: U32) -> Scan:
  Scan{pos, 0, False{}, Fmt.empty(), False{}, W{0, 0}, dsize, fact, 0, 0, state}

# The Wave64 GUID suffix shared by the "wave", "fmt ", "fact" and "data" ids.
def guid.tail(+bytes: +List<U32>, +index: U32) -> Bool:
  tag(bytes, index, 243, 172, 211, 17) && tag(bytes, (index + 4 : U32), 140, 209, 0, 192) && tag(bytes, (index + 8 : U32), 79, 142, 219, 138)

# Skip a chunk's content (and padding); a failed seek ends the walk.
def chunk.skip(+len: U32, +c: U32, +offset: W, +scan: Scan) -> Scan:
  Scan.with(scan, (c + W.lo(offset) : U32), Bool.pick(U32, fits(len, c, offset), 0, 1))

# "fmt " at `c` (after its header; `here` holds the bytes from `c`): 16 bytes,
# then for larger chunks the extension size, a WAVE_FORMAT_EXTENSIBLE
# extension (exactly 22 bytes) or skipped extension bytes, then an int seek
# of the remaining declared size (which may move backwards), then padding.
def fmt.chunk(+here: +List<U32>, +len: U32, +be: Bool, +c: U32, +size: W, +pad: U32, +scan: Scan) -> Scan:
  Scan{_, chi, _, _, has_data, dpos, dsize, fact, frames, flags, _} = scan
  +ftag = e16(be, here, 0)
  +c2 = (c + 16 : U32)
  +longer = W.less(W{0, 16}, size)
  +ext = e16(be, here, 16)
  +c3 = (c2 + 2 : U32)
  +extensible = U32.is_eq(ftag, 65534)
  +ext_ok = U32.is_eq(ext, 0) || Bool.not(extensible) || U32.is_eq(ext, 22)
  +ext_fits = either(extensible, ((len - c3) >= 22 : U32), (ext <= (len - c3) : U32))
  +c4 = (c3 + ext : U32)
  +delta = W.sub(size, W{0, (18 + ext : U32)})
  +offset = W.lo(delta)
  +seek_ok = either(negative(offset), ((0 - offset) <= c4 : U32), (offset <= (len - c4) : U32))
  +sub = Bool.pick(U32, extensible && U32.is_eq(ext, 22), e16(be, here, 24), 0)
  +final = Bool.pick(U32, longer, (c4 + offset : U32), c2)
  +high = Bool.pick(U32, longer, W.hi(W.add(W{chi, c4}, delta)), chi)
  +failed = ((len - c) < 16 : U32) || (longer && (((len - c2) < 2 : U32) || Bool.not(ext_ok) || (U32.is_ne(ext, 0) && Bool.not(ext_fits)) || Bool.not(seek_ok)))
  +padded = (pad <= (len - final) : U32)
  Scan{(final + pad : U32), high, True{}, Fmt{ftag, e16(be, here, 2), e32(be, here, 4), e16(be, here, 12), e16(be, here, 14), sub}, has_data, dpos, dsize, fact, frames, flags,
    Bool.pick(U32, failed, 2, Bool.pick(U32, padded, 0, 1))}

# "data": the walk stops here (no metadata processing). RF64 keeps the ds64 size.
def data.chunk(+rf64: Bool, +c: U32, +size: W, +scan: Scan) -> Scan:
  Scan{_, chi, has_fmt, fmt, _, _, dsize, fact, frames, flags, _} = scan
  Scan{c, chi, has_fmt, fmt, True{}, W{chi, c}, Bool.pick(W, rf64, dsize, size), fact, frames, flags, 1}

# "fact": RIFF/RIFX read 4 bytes and keep no count (dr_wav tests the format
# tag before it is known), Wave64 reads an 8-byte count, RF64 reads nothing.
def fact.chunk(+here: +List<U32>, +len: U32, +cont: U32, +c: U32, +size: W, +pad: U32, +scan: Scan) -> Scan:
  Scan{_, chi, has_fmt, fmt, has_data, dpos, dsize, fact, frames, flags, _} = scan
  +w64 = U32.is_eq(cont, 2)
  +rf64 = U32.is_eq(cont, 3)
  +read = Bool.pick(U32, w64, 8, Bool.pick(U32, rf64, 0, 4))
  +at = (c + read : U32)
  +rest = W.add(W.sub(size, W{0, read}), W{0, pad})
  +count = Bool.pick(W, w64, W.u64(here, 0), Bool.pick(W, rf64, fact, W{0, 0}))
  Scan{(at + W.lo(rest) : U32), chi, has_fmt, fmt, has_data, dpos, dsize, count, frames, flags,
    Bool.pick(U32, ((len - c) < read : U32), 2, Bool.pick(U32, fits(len, at, rest), 0, 1))}

type Rate is Data:
  Rate{state: U32, value: U32}

def Rate.state(+r: Rate) -> U32:
  Rate{state, _} = r
  state

def Rate.value(+r: Rate) -> U32:
  Rate{_, value} = r
  value

def rate.positive(+v: W) -> Rate:
  Rate{Bool.pick(U32, U32.is_eq(W.hi(v), 0), 0, 2), W.lo(v)}

# -(int64)v: negative for 0 < v < 2^63, undefined for v = 2^63, and 2^64 - v
# (a valid rate when at most 0xFFFFFFFF) above it.
def rate.negated(+v: W) -> Rate:
  +minimum = U32.is_eq(W.hi(v), 2147483648) && U32.is_eq(W.lo(v), 0)
  +small = U32.is_eq(W.hi(v), 4294967295) && U32.is_ne(W.lo(v), 0)
  Rate{Bool.pick(U32, W.is_zero(v), 0, Bool.pick(U32, minimum, 3, Bool.pick(U32, small, 0, 2))), (0 - W.lo(v) : U32)}

def rate.zero() -> Rate:
  Rate{0, 0}

def rate.failed() -> Rate:
  Rate{2, 0}

# drwav_aiff_extented_to_s64 on the 80-bit extended rate, then the COMM
# check that it lies in 0..0xFFFFFFFF. Exponents below 16383 wrap the
# unsigned exponent past 63 (INT64_MIN/MAX); 16383 itself gives 0.
def aiff.rate(+here: +List<U32>, +index: U32) -> Rate:
  +e = b16(here, index)
  +ex = (e .&. 32767 : U32)
  +sig = W.be64(here, (index + 2 : U32))
  +x = (ex - 16383 : U32)
  +v = W.shr(sig, ((63 - x) .&. 63 : U32))
  Bool.pick(Rate, U32.is_eq(ex, 0) && W.is_zero(sig), rate.zero(),
  Bool.pick(Rate, U32.is_eq(ex, 32767) || (x > 63 : U32), rate.failed(),
  Bool.pick(Rate, U32.is_eq(x, 0), rate.zero(),
    Bool.pick(Rate, (e >= 32768 : U32), rate.negated(v), rate.positive(v)))))

# AIFC compression: 0 unknown (and "ima4", which dr_wav refuses), 1 "NONE",
# 2 "raw ", 3 IEEE float, 4 "sowt", 6 a-law, 7 mu-law.
def aifc.kind(+here: +List<U32>, +i: U32) -> U32:
  Bool.pick(U32, tag(here, i, 78, 79, 78, 69), 1,
  Bool.pick(U32, tag(here, i, 114, 97, 119, 32), 2,
  Bool.pick(U32, tag(here, i, 115, 111, 119, 116), 4,
  Bool.pick(U32, tag(here, i, 102, 108, 51, 50) || tag(here, i, 102, 108, 54, 52) || tag(here, i, 70, 76, 51, 50) || tag(here, i, 70, 76, 54, 52), 3,
  Bool.pick(U32, tag(here, i, 97, 108, 97, 119) || tag(here, i, 65, 76, 65, 87), 6,
  Bool.pick(U32, tag(here, i, 117, 108, 97, 119) || tag(here, i, 85, 76, 65, 87), 7, 0))))))

# "COMM": 18 bytes (AIFF, exactly) or 24 (AIFC, at least): channels, frame
# count, sample size, 80-bit rate and the AIFC compression. The block align is
# channels*bits/8 in int arithmetic (overflow is undefined), a-law/mu-law
# above 8 bits become 8-bit, and bits are rounded up by (bits & 7). AIFC
# skips the rest of the chunk; neither skips its padding.
def comm.chunk(+here: +List<U32>, +len: U32, +aifc: Bool, +c: U32, +size: W, +scan: Scan) -> Scan:
  Scan{_, chi, _, _, has_data, dpos, dsize, fact, _, flags, _} = scan
  +need = Bool.pick(U32, aifc, 24, 18)
  +bad_size = either(aifc, W.less(size, W{0, 24}), Bool.not(W.is(size, 18)))
  +channels = b16(here, 0)
  +bits0 = b16(here, 6)
  +rate = aiff.rate(here, 8)
  +kind = Bool.pick(U32, aifc, aifc.kind(here, 18), 1)
  +format = Bool.pick(U32, U32.is_eq(kind, 2) || U32.is_eq(kind, 4), 1, kind)
  +product = (channels * bits0 : U32)
  +narrowed = (U32.is_eq(format, 6) || U32.is_eq(format, 7)) && (bits0 > 8 : U32)
  +align = Bool.pick(U32, narrowed, channels, ((product >> 3n) .&. 65535 : U32))
  +bits1 = Bool.pick(U32, narrowed, 8, bits0)
  +after = (c + need : U32)
  +rest = W.sub(size, W{0, 24})
  +flagged = (flags .|. Bool.pick(U32, U32.is_eq(kind, 4), 1, 0) .|. Bool.pick(U32, U32.is_eq(kind, 2) && U32.is_eq(bits0, 8), 2, 0) : U32)
  +state = Bool.pick(U32, bad_size || ((len - c) < need : U32), 2,
    Bool.pick(U32, U32.is_ne(Rate.state(rate), 0), Rate.state(rate),
    Bool.pick(U32, U32.is_eq(kind, 0), 2,
    Bool.pick(U32, (product > 2147483647 : U32), 3,
    Bool.pick(U32, aifc && Bool.not(fits(len, after, rest)), 2, 0)))))
  Scan{Bool.pick(U32, aifc, (after + W.lo(rest) : U32), after), chi, True{}, Fmt{format, channels, Rate.value(rate), align, ((bits1 + (bits1 .&. 7)) .&. 65535 : U32), 0},
    has_data, dpos, dsize, fact, b32(here, 2), flagged, state}

# "SSND": an 8-byte offset/block size, then the data at cursor + offset. The
# data size is the chunk size less the offset (not less the 8 bytes). The
# walk continues past it.
def ssnd.chunk(+here: +List<U32>, +len: U32, +c: U32, +size: W, +pad: U32, +scan: Scan) -> Scan:
  Scan{_, chi, has_fmt, fmt, _, _, _, fact, frames, flags, _} = scan
  +offset = b32(here, 0)
  +at = (c + 8 : U32)
  +rest = W.sub(W.add(size, W{0, pad}), W{0, 8})
  Scan{(at + W.lo(rest) : U32), chi, has_fmt, fmt, True{}, W.add(W{chi, at}, W{0, offset}),
    Bool.pick(W, W.less(W{0, offset}, size), W.sub(size, W{0, offset}), W{0, 0}), fact, frames, flags,
    Bool.pick(U32, ((len - c) < 8 : U32), 2, Bool.pick(U32, fits(len, at, rest), 0, 1))}

# Containers: 0 RIFF, 1 RIFX, 2 Wave64, 3 RF64, 4 AIFF/AIFC, 5 none.
# Chunk kinds: 0 no header (end), 1 fmt, 2 data, 3 fact, 4 COMM, 5 SSND, 6 other.
def chunk.kind(+here: +List<U32>, +cont: U32) -> U32:
  +id = Bool.pick(U32, tag(here, 0, 102, 109, 116, 32), 1,
    Bool.pick(U32, tag(here, 0, 100, 97, 116, 97), 2, Bool.pick(U32, tag(here, 0, 102, 97, 99, 116), 3, 6)))
  +aiff = Bool.pick(U32, tag(here, 0, 67, 79, 77, 77), 4, Bool.pick(U32, tag(here, 0, 83, 83, 78, 68), 5, 6))
  Bool.pick(U32, U32.is_eq(cont, 4), aiff, Bool.pick(U32, U32.is_ne(cont, 2) || guid.tail(here, 4), id, 6))

# drwav__read_chunk_header: a fourcc and 32-bit size (big-endian for RIFX
# and AIFF, padding to 2 bytes), or a Wave64 GUID and 64-bit size counting
# its 24-byte header (padding: the size modulo 8, as dr_wav computes it).
def chunk.size(+here: +List<U32>, +cont: U32) -> W:
  Bool.pick(W, U32.is_eq(cont, 2), W.sub(W.u64(here, 16), W{0, 24}),
    W{0, Bool.pick(U32, U32.is_eq(cont, 1) || U32.is_eq(cont, 4), b32(here, 4), u32(here, 4))})

def chunk(kind: U32, +here: +List<U32>, +len: U32, +cont: U32, +aifc: Bool, +c: U32, +size: W, +pad: U32, +scan: Scan) -> Scan:
  match kind:
    case 0: Scan.with(scan, c, 1)
    case 1: fmt.chunk(here, len, U32.is_eq(cont, 1), c, size, pad, scan)
    case 2: data.chunk(U32.is_eq(cont, 3), c, size, scan)
    case 3: fact.chunk(here, len, cont, c, size, pad, scan)
    case 4: comm.chunk(here, len, aifc, c, size, scan)
    case 5: ssnd.chunk(here, len, c, size, pad, scan)
    case _: chunk.skip(len, c, W.add(size, W{0, pad}), scan)

def step(+bytes: +List<U32>, +len: U32, +cont: U32, +aifc: Bool, +scan: Scan) -> Scan:
  +pos = Scan.pos(scan)
  +w64 = U32.is_eq(cont, 2)
  +header = Bool.pick(U32, w64, 24, 8)
  +here = List.drop(&2, U32, bytes, U32.to_nat(pos))
  +size = chunk.size(here, cont)
  +pad = (W.lo(size) .&. Bool.pick(U32, w64, 7, 1) : U32)
  chunk(Bool.pick(U32, ((len - pos) < header : U32), 0, chunk.kind(here, cont)), List.drop(&2, U32, here, U32.to_nat(header)), len, cont, aifc, (pos + header : U32), size, pad, scan)

# The walk's next position depends only on its current one, so a walk still
# going after len+2 steps revisits a position: dr_wav never returns.
def walk(n: Nat, going: Bool, +bytes: +List<U32>, +len: U32, +cont: U32, +aifc: Bool, +scan: Scan) -> Scan:
  match n going:
    case 1n+k True{}:
      +next = step(bytes, len, cont, aifc, scan)
      walk(k, U32.is_eq(Scan.state(next), 0), bytes, len, cont, aifc, next)
    case _ _: scan

def container(+bytes: +List<U32>, +len: U32) -> U32:
  Bool.pick(U32, (len < 4 : U32), 5,
  Bool.pick(U32, tag(bytes, 0, 82, 73, 70, 70), 0,
  Bool.pick(U32, tag(bytes, 0, 82, 73, 70, 88), 1,
  Bool.pick(U32, tag(bytes, 0, 114, 105, 102, 102), 2,
  Bool.pick(U32, tag(bytes, 0, 82, 70, 54, 52), 3,
  Bool.pick(U32, tag(bytes, 0, 70, 79, 82, 77), 4, 5))))))

def wave(+bytes: +List<U32>) -> Bool:
  tag(bytes, 8, 87, 65, 86, 69)

# The RIFF chunk size is not checked; RF64's must be 0xFFFFFFFF and a ds64
# chunk must follow: 8 skipped bytes, the data size and the sample count,
# then the rest of the chunk.
def begin.rf64(+bytes: +List<U32>, +len: U32) -> Scan:
  +size = u32(bytes, 16)
  +rest = W.sub(W.add(W{0, size}, W{0, (size .&. 1 : U32)}), W{0, 24})
  +ok = (len >= 44 : U32) && U32.is_eq(u32(bytes, 4), 4294967295) && wave(bytes) && tag(bytes, 12, 100, 115, 54, 52) && fits(len, 44, rest)
  Scan.initial((44 + W.lo(rest) : U32), W.u64(bytes, 28), W.u64(bytes, 36), Bool.pick(U32, ok, 0, 2))

# The rest of the "riff" GUID, a 64-bit size of at least 80 and the "wave" GUID.
def begin.w64(+bytes: +List<U32>, +len: U32) -> Scan:
  +riff = tag(bytes, 4, 46, 145, 207, 17) && tag(bytes, 8, 165, 214, 40, 219) && tag(bytes, 12, 4, 193, 0, 0)
  +ok = (len >= 40 : U32) && riff && Bool.not(W.less(W.u64(bytes, 16), W{0, 80})) && tag(bytes, 24, 119, 97, 118, 101) && guid.tail(bytes, 28)
  Scan.initial(40, W{0, 0}, W{0, 0}, Bool.pick(U32, ok, 0, 2))

def begin.aiff(+bytes: +List<U32>, +len: U32) -> Scan:
  +ok = (len >= 12 : U32) && (b32(bytes, 4) >= 18 : U32) && (tag(bytes, 8, 65, 73, 70, 70) || tag(bytes, 8, 65, 73, 70, 67))
  Scan.initial(12, W{0, 0}, W{0, 0}, Bool.pick(U32, ok, 0, 2))

def begin(cont: U32, +bytes: +List<U32>, +len: U32) -> Scan:
  match cont:
    case 2: begin.w64(bytes, len)
    case 3: begin.rf64(bytes, len)
    case 4: begin.aiff(bytes, len)
    case 5: Scan.initial(0, W{0, 0}, W{0, 0}, 2)
    case _: Scan.initial(12, W{0, 0}, W{0, 0}, Bool.pick(U32, (len >= 12 : U32) && wave(bytes), 0, 2))

# -----------------------------------------------------------------------------
# Samples (drwav_read_pcm_frames_s16)

def alaw() -> +List<U32>:
  [60032, 60288, 59520, 59776, 61056, 61312, 60544, 60800, 57984, 58240, 57472, 57728, 59008, 59264, 58496, 58752,
   62784, 62912, 62528, 62656, 63296, 63424, 63040, 63168, 61760, 61888, 61504, 61632, 62272, 62400, 62016, 62144,
   43520, 44544, 41472, 42496, 47616, 48640, 45568, 46592, 35328, 36352, 33280, 34304, 39424, 40448, 37376, 38400,
   54528, 55040, 53504, 54016, 56576, 57088, 55552, 56064, 50432, 50944, 49408, 49920, 52480, 52992, 51456, 51968,
   65192, 65208, 65160, 65176, 65256, 65272, 65224, 65240, 65064, 65080, 65032, 65048, 65128, 65144, 65096, 65112,
   65448, 65464, 65416, 65432, 65512, 65528, 65480, 65496, 65320, 65336, 65288, 65304, 65384, 65400, 65352, 65368,
   64160, 64224, 64032, 64096, 64416, 64480, 64288, 64352, 63648, 63712, 63520, 63584, 63904, 63968, 63776, 63840,
   64848, 64880, 64784, 64816, 64976, 65008, 64912, 64944, 64592, 64624, 64528, 64560, 64720, 64752, 64656, 64688,
   5504, 5248, 6016, 5760, 4480, 4224, 4992, 4736, 7552, 7296, 8064, 7808, 6528, 6272, 7040, 6784,
   2752, 2624, 3008, 2880, 2240, 2112, 2496, 2368, 3776, 3648, 4032, 3904, 3264, 3136, 3520, 3392,
   22016, 20992, 24064, 23040, 17920, 16896, 19968, 18944, 30208, 29184, 32256, 31232, 26112, 25088, 28160, 27136,
   11008, 10496, 12032, 11520, 8960, 8448, 9984, 9472, 15104, 14592, 16128, 15616, 13056, 12544, 14080, 13568,
   344, 328, 376, 360, 280, 264, 312, 296, 472, 456, 504, 488, 408, 392, 440, 424,
   88, 72, 120, 104, 24, 8, 56, 40, 216, 200, 248, 232, 152, 136, 184, 168,
   1376, 1312, 1504, 1440, 1120, 1056, 1248, 1184, 1888, 1824, 2016, 1952, 1632, 1568, 1760, 1696,
   688, 656, 752, 720, 560, 528, 624, 592, 944, 912, 1008, 976, 816, 784, 880, 848]

def mulaw() -> +List<U32>:
  [33412, 34436, 35460, 36484, 37508, 38532, 39556, 40580, 41604, 42628, 43652, 44676, 45700, 46724, 47748, 48772,
   49540, 50052, 50564, 51076, 51588, 52100, 52612, 53124, 53636, 54148, 54660, 55172, 55684, 56196, 56708, 57220,
   57604, 57860, 58116, 58372, 58628, 58884, 59140, 59396, 59652, 59908, 60164, 60420, 60676, 60932, 61188, 61444,
   61636, 61764, 61892, 62020, 62148, 62276, 62404, 62532, 62660, 62788, 62916, 63044, 63172, 63300, 63428, 63556,
   63652, 63716, 63780, 63844, 63908, 63972, 64036, 64100, 64164, 64228, 64292, 64356, 64420, 64484, 64548, 64612,
   64660, 64692, 64724, 64756, 64788, 64820, 64852, 64884, 64916, 64948, 64980, 65012, 65044, 65076, 65108, 65140,
   65164, 65180, 65196, 65212, 65228, 65244, 65260, 65276, 65292, 65308, 65324, 65340, 65356, 65372, 65388, 65404,
   65416, 65424, 65432, 65440, 65448, 65456, 65464, 65472, 65480, 65488, 65496, 65504, 65512, 65520, 65528, 0,
   32124, 31100, 30076, 29052, 28028, 27004, 25980, 24956, 23932, 22908, 21884, 20860, 19836, 18812, 17788, 16764,
   15996, 15484, 14972, 14460, 13948, 13436, 12924, 12412, 11900, 11388, 10876, 10364, 9852, 9340, 8828, 8316,
   7932, 7676, 7420, 7164, 6908, 6652, 6396, 6140, 5884, 5628, 5372, 5116, 4860, 4604, 4348, 4092,
   3900, 3772, 3644, 3516, 3388, 3260, 3132, 3004, 2876, 2748, 2620, 2492, 2364, 2236, 2108, 1980,
   1884, 1820, 1756, 1692, 1628, 1564, 1500, 1436, 1372, 1308, 1244, 1180, 1116, 1052, 988, 924,
   876, 844, 812, 780, 748, 716, 684, 652, 620, 588, 556, 524, 492, 460, 428, 396,
   372, 356, 340, 324, 308, 292, 276, 260, 244, 228, 212, 196, 180, 164, 148, 132,
   120, 112, 104, 96, 88, 80, 72, 64, 56, 48, 40, 32, 24, 16, 8, 0]

def float_bits(value: U32) -> F32:
  U32{word} = value
  F32{word}

# drwav_f32_to_s16: clamp to [-1, 1], add 1, scale by 32767.5 and truncate.
# NaN (an undefined float-to-int conversion) is the 65536 marker.
def f32.sample(+bits: U32) -> U32:
  +x = float_bits(bits)
  +c = Bool.pick(F32, (x < F32.neg(1.0) : F32), F32.neg(1.0), Bool.pick(F32, (x > 1.0 : F32), 1.0, x))
  Bool.pick(U32, ((bits .&. 2147483647) > 2139095040 : U32), 65536,
    ((F32.to_u32(F32.mul(F32.add(c, 1.0), 32767.5)) - 32768) .&. 65535 : U32))

# Binary64 values through the checked helpers (each rounds once, to nearest
# even); Bad when an operand leaves a helper's domain.
type V is Data:
  Ok{high: U32, low: U32}
  Bad{}

def lift(result: Maybe<F.Words>) -> V:
  match result:
    case Some{F.Words{high, low}}: Ok{high, low}
    case None{}: Bad{}

def add(a: V, b: V) -> V:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: lift(A.checked_add(ah, al, bh, bl))
    case _ _: Bad{}

def mul(a: V, b: V) -> V:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: lift(O.checked_multiply(ah, al, bh, bl))
    case _ _: Bad{}

def one() -> V:
  Ok{1072693248, 0}

# (int) of a product in [+0, 65535], truncated from its words, minus 32768.
def f64.finish(value: V) -> U32:
  match value:
    case Ok{+high, _}:
      +e = ((high >> 20n) .&. 2047 : U32)
      +m = ((high .&. 1048575) .|. 1048576 : U32)
      +t = Bool.pick(U32, (e < 1023 : U32), 0, (m >> U32.to_nat(((1043 - e) .&. 31 : U32)) : U32))
      ((t - 32768) .&. 65535 : U32)
    case Bad{}: 65536

# drwav_f64_to_s16 in binary64: c = clamp(x, -1, 1), (int)((c + 1) * 32767.5)
# - 32768. |c| < 2^-900 (zeros, subnormals) adds to exactly 1, outside the
# addition helper's domain; NaN is the 65536 marker.
def f64.sample(+high: U32, +low: U32) -> U32:
  +magnitude = (high .&. 2147483647 : U32)
  +nan = (magnitude > 2146435072 : U32) || (U32.is_eq(magnitude, 2146435072) && U32.is_ne(low, 0))
  +above = (magnitude > 1072693248 : U32) || (U32.is_eq(magnitude, 1072693248) && U32.is_ne(low, 0))
  +ch = Bool.pick(U32, above, (1072693248 .|. (high .&. 2147483648) : U32), high)
  +cl = Bool.pick(U32, above, 0, low)
  +tiny = (((ch >> 20n) .&. 2047) < 123 : U32)
  Bool.pick(U32, nan, 65536, f64.finish(mul(Bool.pick(V, tiny, one(), add(Ok{ch, cl}, one())), Ok{1088421856, 0})))

# Sample conversions: 1 a-law, 2 mu-law, 3/4 f32 (little/big-endian), 5/6
# f64, 7 unsigned 8-bit, 8/9 the top two bytes of a 2..8-byte sample
# (little/big-endian), 0 silence (wider PCM, other float widths). `adjust`
# adds 128 to 8-bit AIFF bytes (dr_wav's signed-to-unsigned step).
def byte(+adjust: Bool, +value: U32) -> U32:
  Bool.pick(U32, adjust, ((value + 128) .&. 255 : U32), value)

def sample(code: U32, +adjust: Bool, +width: U32, +data: +List<U32>) -> U32:
  match code:
    case 1: at(alaw(), byte(adjust, head(data)))
    case 2: at(mulaw(), byte(adjust, head(data)))
    case 3: f32.sample(u32(data, 0))
    case 4: f32.sample(b32(data, 0))
    case 5: f64.sample(u32(data, 4), u32(data, 0))
    case 6: f64.sample(b32(data, 0), b32(data, 4))
    case 7: (((byte(adjust, head(data)) .^. 128) << 8n) .&. 65535 : U32)
    case 8: (at(data, (width - 2 : U32)) .|. (at(data, (width - 1 : U32)) << 8n) : U32)
    case 9: (at(data, 1) .|. (at(data, 0) << 8n) : U32)
    case _: 0

type Samples is Data:
  Samples{values: +List<U32>, bad: Bool}

def samples(n: Nat, +code: U32, +adjust: Bool, +width: U32, +data: +List<U32>, +acc: +List<U32>, +bad: Bool) -> Samples:
  match n:
    case 0n: Samples{List.reverse(&2, U32, acc), bad}
    case 1n+k:
      +value = sample(code, adjust, width, List.take(&2, U32, data, U32.to_nat(width)))
      samples(k, code, adjust, width, List.drop(&2, U32, data, U32.to_nat(width)), Con{(value .&. 65535 : U32), acc}, bad || (value > 65535 : U32))

# -----------------------------------------------------------------------------
# After the walk: validation, the data position and size, the frame count,
# then raylib's read of (unsigned int)totalPCMFrameCount frames.

def decoded(+rate: U32, +channels: U32, +frames: U32, converted: Samples) -> Outcome:
  match converted:
    case Samples{_, True{}}: Invalid{C.BadStream{}}
    case Samples{values, False{}}: Decoded{rate, channels, frames, values}

def adpcm.decoded(+rate: U32, +channels: U32, +frames: U32, run: P.Run) -> Outcome:
  match run:
    case P.Run{samples, got, bad}: Bool.pick(Outcome, bad || (got < frames : U32), Invalid{C.BadStream{}}, Decoded{rate, channels, frames, samples})

def pcm.read(ok: Bool, +rate: U32, +channels: U32, +frames: U32, +code: U32, +adjust: Bool, +width: U32, +data: +List<U32>) -> Outcome:
  match ok:
    case False{}: Invalid{C.BadStream{}}
    case True{}: decoded(rate, channels, frames, samples(U32.to_nat((frames * channels : U32)), code, adjust, width, data, Nil{}, False{}))

# Uncompressed reads: bytes come from the data chunk (at most its size) in
# whole frames; formats other than PCM/float/a-law/mu-law, samples that do
# not divide the frame and (outside the 16-bit PCM fast path) frames over
# 4096 bytes read nothing. Big-endian containers byte-swap 1/2/3/4/8-byte
# samples; other widths fail dr_wav's assertion.
def pcm(+bytes: +List<U32>, +len: U32, +cont: U32, +flags: U32, +kind: U32, +bits: U32, +channels: U32, +rate: U32, +frame: U32, +usable: W, +p: U32, +frames: U32) -> Outcome:
  +be = U32.is_eq(cont, 1) || (U32.is_eq(cont, 4) && U32.is_eq((flags .&. 1 : U32), 0))
  +adjust = U32.is_eq(cont, 4) && U32.is_eq(bits, 8) && U32.is_eq((flags .&. 2 : U32), 0)
  +fast = U32.is_eq(kind, 1) && U32.is_eq(bits, 16)
  +width = (frame / channels : U32)
  +known = U32.is_eq(kind, 1) || U32.is_eq(kind, 3) || U32.is_eq(kind, 6) || U32.is_eq(kind, 7)
  +readable = fast || (known && U32.is_ne(width, 0) && U32.is_eq((frame % channels : U32), 0) && (frame <= 4096 : U32))
  +swappable = Bool.not(be) || U32.is_eq(width, 1) || U32.is_eq(width, 2) || U32.is_eq(width, 3) || U32.is_eq(width, 4) || U32.is_eq(width, 8)
  +room = (len - p : U32)
  +present = Bool.pick(U32, W.less(W{0, room}, usable), room, W.lo(usable))
  +code = Bool.pick(U32, U32.is_eq(kind, 6), 1, Bool.pick(U32, U32.is_eq(kind, 7), 2,
    Bool.pick(U32, U32.is_eq(kind, 3), Bool.pick(U32, U32.is_eq(width, 4), Bool.pick(U32, be, 4, 3), Bool.pick(U32, U32.is_eq(width, 8), Bool.pick(U32, be, 6, 5), 0)),
    Bool.pick(U32, U32.is_eq(width, 1), 7, Bool.pick(U32, (width > 8 : U32), 0, Bool.pick(U32, be, 9, 8))))))
  pcm.read(readable && swappable && (frames <= (present / frame) : U32), rate, channels, frames, code, adjust, width, List.drop(&2, U32, bytes, U32.to_nat(p)))

# Frames: the fact (Wave64, RF64) or COMM count when nonzero, else the data
# size over the frame size, or for ADPCM from the block count (a trailing
# partial block counts), in wrapping 64-bit arithmetic.
def total(+fact: W, +aframes: U32, +usable: W, +frame: U32, +kind: U32, +align: U32, +channels: U32) -> W:
  +blocks0 = W.div(usable, nonzero(align))
  +blocks = Bool.pick(W, U32.is_eq(W.mod(usable, nonzero(align)), 0), blocks0, W.add(blocks0, W{0, 1}))
  +ms = W.div(W.mul(W.sub(usable, W.mul(blocks, (6 * channels : U32))), 2), nonzero(channels))
  +ima = W.add(W.div(W.mul(W.sub(usable, W.mul(blocks, (4 * channels : U32))), 2), nonzero(channels)), blocks)
  Bool.pick(W, Bool.not(W.is_zero(fact)), fact, Bool.pick(W, U32.is_ne(aframes, 0), W{0, aframes},
    Bool.pick(W, U32.is_eq(kind, 2), ms, Bool.pick(W, U32.is_eq(kind, 17), ima, W.div(usable, nonzero(frame))))))

# 1 failed init, 2 undefined or endless, 3 no frames, 4 ADPCM, 5 uncompressed.
def outcome(code: U32, +bytes: +List<U32>, +len: U32, +cont: U32, +flags: U32, +kind: U32, +bits: U32, +channels: U32, +rate: U32, +align: U32, +frame: U32, +usable: W, +p: U32, +frames: U32) -> Outcome:
  match code:
    case 1: Invalid{C.BadHeader{}}
    case 2: Invalid{C.BadStream{}}
    case 3: Decoded{rate, channels, 0, []}
    case 4: adpcm.decoded(rate, channels, frames, P.decode(U32.is_eq(kind, 17), U32.is_eq(channels, 2), List.drop(&2, U32, bytes, U32.to_nat(p)), (len - p : U32), align, frames))
    case _: pcm(bytes, len, cont, flags, kind, bits, channels, rate, frame, usable, p, frames)

def finished(+bytes: +List<U32>, +len: U32, +cont: U32, +scan: Scan) -> Outcome:
  Scan{_, _, has_fmt, Fmt{ftag, +channels, +rate, +align, +bits, +sub}, has_data, +dpos, +declared, +fact, +aframes, +flags, +state} = scan
  +kind = Bool.pick(U32, U32.is_eq(ftag, 65534), sub, ftag)
  +p = W.lo(dpos)
  +placed = U32.is_eq(W.hi(dpos), 0) && (p <= len : U32)
  +dsize = Bool.pick(W, W.less(W{0, len}, W.add(declared, W{0, p})), W{0, (len - p : U32)}, declared)
  +raw = Bool.pick(U32, U32.is_eq((bits .&. 7 : U32), 0), ((bits * channels) >> 3n : U32), align)
  +companded = U32.is_eq(kind, 6) || U32.is_eq(kind, 7)
  +frame = Bool.pick(U32, companded && U32.is_ne(raw, channels), 0, raw)
  +adpcm = U32.is_eq(kind, 2) || U32.is_eq(kind, 17)
  +usable = Bool.pick(W, adpcm || U32.is_eq(frame, 0), dsize, W.sub(dsize, W{0, W.mod(dsize, nonzero(frame))}))
  +frames = W.lo(total(fact, aframes, usable, frame, kind, align, channels))
  +header = Bool.not(has_fmt && has_data) || U32.is_eq(rate, 0) || (rate > 384000 : U32) || U32.is_eq(channels, 0) || (channels > 256 : U32)
    || U32.is_eq(bits, 0) || (bits > 64 : U32) || U32.is_eq(align, 0) || Bool.not(placed) || U32.is_eq(frame, 0) || (adpcm && (channels > 2 : U32))
  +code = Bool.pick(U32, U32.is_eq(state, 2), 1, Bool.pick(U32, U32.is_ne(state, 1), 2, Bool.pick(U32, header, 1,
    Bool.pick(U32, U32.is_eq(frames, 0), 3, Bool.pick(U32, adpcm, 4, 5)))))
  outcome(code, bytes, len, cont, flags, kind, bits, channels, rate, align, frame, usable, p, frames)

# LoadWaveFromMemory(".wav"): drwav_init_memory on every container dr_wav
# detects, then drwav_read_pcm_frames_s16 of (unsigned int)totalPCMFrameCount
# frames. Failed inits are BadHeader; data dr_wav leaves partly unread,
# converts from NaN, decodes with signed overflow, byte-swaps through its
# failing assertion or walks forever are BadStream.
def decode(+bytes: +List<U32>) -> Outcome:
  +len = U32.from_nat(C.byte_count(bytes, 0n))
  +cont = container(bytes, len)
  +scan = begin(cont, bytes, len)
  finished(bytes, len, cont, walk(U32.to_nat((len + 2 : U32)), U32.is_eq(Scan.state(scan), 0), bytes, len, cont, tag(bytes, 8, 65, 73, 70, 67), scan))
