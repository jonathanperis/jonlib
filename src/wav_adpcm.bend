# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of dr_wav (David Reid; public domain or MIT-0, as
# pinned raylib 6.0 vendors it in src/external/dr_wav.h):
# drwav_read_pcm_frames_s16__msadpcm and drwav_read_pcm_frames_s16__ima, with
# their adaptation, coefficient, index and step tables. C ints are U32
# two's-complement words. See THIRD_PARTY_NOTICES.md.
import Base

def head(rest: +List<U32>) -> U32:
  match rest:
    case Con{value, _}: value
    case Nil{}: 0

def at(+bytes: +List<U32>, +index: U32) -> U32:
  head(List.drop(&2, U32, bytes, U32.to_nat(index)))

def negative(+x: U32) -> Bool:
  (x >= 2147483648 : U32)

# drwav_bytes_to_s16: a little-endian 16-bit value, sign-extended.
def s16(+bytes: +List<U32>, +index: U32) -> U32:
  +v = (at(bytes, index) .|. (at(bytes, (index + 1 : U32)) << 8n) : U32)
  Bool.pick(U32, (v >= 32768 : U32), (v .|. 4294901760 : U32), v)

# Arithmetic shift right by 8 (clang's >> on negative ints).
def asr8(+x: U32) -> U32:
  Bool.pick(U32, negative(x), (((x .^. 4294967295) >> 8n) .^. 4294967295 : U32), (x >> 8n : U32))

def less(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) < (b .^. 2147483648) : U32)

def clamp(+v: U32, +lo: U32, +hi: U32) -> U32:
  Bool.pick(U32, less(v, lo), lo, Bool.pick(U32, less(hi, v), hi, v))

def clamp16(+v: U32) -> U32:
  clamp(v, 4294934528, 32767)

def min(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a < b : U32), a, b)

def magnitude(+x: U32) -> U32:
  Bool.pick(U32, negative(x), (0 - x : U32), x)

# Decoder state: MS ADPCM predictors p, deltas d and the two previous samples
# of each channel (a0/a1 left, b0/b1 right, older first); IMA ADPCM keeps its
# predictors in p0/p1 and step indices in d0/d1.
type St is Data:
  St{p0: U32, p1: U32, d0: U32, d1: U32, a0: U32, a1: U32, b0: U32, b1: U32}

# One step of the read loop: whether the stream allowed it, the bytes it read,
# the bytes left in the block, the state, the reversed output, frames output
# and whether a signed int overflowed (undefined in C).
type Step is Data:
  Step{ok: Bool, used: U32, rem: U32, st: St, acc: +List<U32>, out: U32, bad: Bool}

def Step.ok(+s: Step) -> Bool:
  Step{ok, _, _, _, _, _, _} = s
  ok

def Step.used(+s: Step) -> U32:
  Step{_, used, _, _, _, _, _} = s
  used

def Step.rem(+s: Step) -> U32:
  Step{_, _, rem, _, _, _, _} = s
  rem

def Step.st(+s: Step) -> St:
  Step{_, _, _, st, _, _, _} = s
  st

def Step.acc(+s: Step) -> +List<U32>:
  Step{_, _, _, _, acc, _, _} = s
  acc

def Step.out(+s: Step) -> U32:
  Step{_, _, _, _, _, out, _} = s
  out

def Step.bad(+s: Step) -> Bool:
  Step{_, _, _, _, _, _, bad} = s
  bad

# The first `n` values (one channel's frames), reversed onto acc as 16 bits.
def pushn(n: Nat, +values: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match n values:
    case 1n+k Con{v, rest}: pushn(k, rest, Con{(v .&. 65535 : U32), acc})
    case _ _: acc

# The first `n` stereo frames of left/right values, reversed onto acc.
def interleave(n: Nat, +left: +List<U32>, +right: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match n left right:
    case 1n+k Con{x, xs} Con{y, ys}: interleave(k, xs, ys, Con{(y .&. 65535 : U32), Con{(x .&. 65535 : U32), acc}})
    case _ _ _: acc

# -----------------------------------------------------------------------------
# Microsoft ADPCM

def ms.adaptation(+nibble: U32) -> U32:
  at([230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230], nibble)

def ms.coeff1(+predictor: U32) -> U32:
  at([256, 512, 0, 192, 240, 460, 392], predictor)

def ms.coeff2(+predictor: U32) -> U32:
  at([0, 4294967040, 0, 64, 0, 4294967088, 4294967064], predictor)

# clamp(((int64)table * delta) >> 8, 16, 0x7FFFFFFF): a non-positive delta
# (only from a block header) gives 16; t*floor(d/256) + floor(t*(d%256)/256)
# is the exact quotient, compared before it can leave 32 bits.
def ms.adapt(+t: U32, +delta: U32) -> U32:
  +dh = (delta >> 8n : U32)
  +big = (dh > (2147483647 / t) : U32)
  +q = (t * dh + ((t * (delta .&. 255)) >> 8n) : U32)
  Bool.pick(U32, negative(delta) || U32.is_eq(delta, 0), 16,
    Bool.pick(U32, big || (q > 2147483647 : U32), 2147483647, Bool.pick(U32, (q < 16 : U32), 16, q)))

# Whether the int product n*d (n a sign-extended nibble) stays in range.
def ms.product_ok(+n: U32, +d: U32) -> Bool:
  +an = magnitude(n)
  +limit = Bool.pick(U32, U32.is_ne((n >> 31n : U32), (d >> 31n : U32)), 2147483648, 2147483647)
  U32.is_eq(an, 0) || (magnitude(d) <= (limit / Bool.pick(U32, U32.is_eq(an, 0), 1, an)) : U32)

type Dec is Data:
  Dec{sample: U32, delta: U32, bad: Bool}

def Dec.sample(+d: Dec) -> U32:
  Dec{sample, _, _} = d
  sample

def Dec.delta(+d: Dec) -> U32:
  Dec{_, delta, _} = d
  delta

def Dec.bad(+d: Dec) -> Bool:
  Dec{_, _, bad} = d
  bad

# One nibble of a channel with previous samples x1 (newest) and x0.
def ms.decode(+nibble: U32, +predictor: U32, +delta: U32, +x1: U32, +x0: U32) -> Dec:
  +n = Bool.pick(U32, (nibble >= 8 : U32), (nibble .|. 4294967280 : U32), nibble)
  +base = asr8((x1 * ms.coeff1(predictor) + x0 * ms.coeff2(predictor) : U32))
  +product = (n * delta : U32)
  +sum = (base + product : U32)
  +overflow = U32.is_eq((base >> 31n : U32), (product >> 31n : U32)) && U32.is_ne((sum >> 31n : U32), (base >> 31n : U32))
  Dec{clamp16(sum), ms.adapt(ms.adaptation(nibble), delta), Bool.not(ms.product_ok(n, delta)) || overflow}

# A mono block header: predictor, delta, sample 1, sample 2 (output first).
def ms.header.mono(+s: +List<U32>, +avail: U32, +align: U32, +want: U32, +st: St, +acc: +List<U32>) -> Step:
  St{_, p1, _, d1, _, _, b0, b1} = st
  +predictor = at(s, 0)
  +x1 = s16(s, 3)
  +x0 = s16(s, 5)
  +ok = (avail >= 7 : U32) && (predictor < 7 : U32)
  +out = Bool.pick(U32, ok, min(2, want), 0)
  Step{ok, 7, (align - 7 : U32), St{predictor, p1, s16(s, 1), d1, x0, x1, b0, b1}, pushn(U32.to_nat(out), [x0, x1], acc), out, False{}}

def ms.header.stereo(+s: +List<U32>, +avail: U32, +align: U32, +want: U32, +acc: +List<U32>) -> Step:
  +p0 = at(s, 0)
  +p1 = at(s, 1)
  +a1 = s16(s, 6)
  +b1 = s16(s, 8)
  +a0 = s16(s, 10)
  +b0 = s16(s, 12)
  +ok = (avail >= 14 : U32) && (p0 < 7 : U32) && (p1 < 7 : U32)
  +out = Bool.pick(U32, ok, min(2, want), 0)
  Step{ok, 14, (align - 14 : U32), St{p0, p1, s16(s, 2), s16(s, 4), a0, a1, b0, b1}, interleave(U32.to_nat(out), [a0, a1], [b0, b1], acc), out, False{}}

# A byte holds two mono frames (high nibble first).
def ms.byte.mono(+s: +List<U32>, +avail: U32, +rem: U32, +want: U32, +st: St, +acc: +List<U32>) -> Step:
  St{p0, p1, d0, d1, a0, a1, b0, b1} = st
  +byte = head(s)
  +first = ms.decode((byte >> 4n : U32), p0, d0, a1, a0)
  +x = Dec.sample(first)
  +second = ms.decode((byte .&. 15 : U32), p0, Dec.delta(first), x, a1)
  +y = Dec.sample(second)
  +ok = (avail >= 1 : U32)
  +out = Bool.pick(U32, ok, min(2, want), 0)
  Step{ok, 1, (rem - 1 : U32), St{p0, p1, Dec.delta(second), d1, x, y, b0, b1}, pushn(U32.to_nat(out), [x, y], acc), out,
    ok && (Dec.bad(first) || Dec.bad(second))}

# A byte holds one stereo frame (left in the high nibble).
def ms.byte.stereo(+s: +List<U32>, +avail: U32, +rem: U32, +st: St, +acc: +List<U32>) -> Step:
  St{p0, p1, d0, d1, a0, a1, b0, b1} = st
  +byte = head(s)
  +left = ms.decode((byte >> 4n : U32), p0, d0, a1, a0)
  +right = ms.decode((byte .&. 15 : U32), p1, d1, b1, b0)
  +x = Dec.sample(left)
  +y = Dec.sample(right)
  +ok = (avail >= 1 : U32)
  +out = Bool.pick(U32, ok, 1, 0)
  Step{ok, 1, (rem - 1 : U32), St{p0, p1, Dec.delta(left), Dec.delta(right), a1, x, b1, y}, interleave(U32.to_nat(out), [x], [y], acc), out,
    ok && (Dec.bad(left) || Dec.bad(right))}

# -----------------------------------------------------------------------------
# IMA ADPCM

def ima.steps() -> +List<U32>:
  [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
   50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
   337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
   2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
   15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]

def ima.index(+nibble: U32) -> U32:
  at([4294967295, 4294967295, 4294967295, 4294967295, 2, 4, 6, 8, 4294967295, 4294967295, 4294967295, 4294967295, 2, 4, 6, 8], nibble)

def ima.bit(+nibble: U32, +mask: U32, +value: U32) -> U32:
  Bool.pick(U32, U32.is_eq((nibble .&. mask : U32), 0), 0, value)

type Nib is Data:
  Nib{predictor: U32, index: U32}

def ima.nibble(+nibble: U32, +predictor: U32, +index: U32) -> Nib:
  +step = at(ima.steps(), index)
  +diff = ((step >> 3n) + ima.bit(nibble, 1, (step >> 2n : U32)) + ima.bit(nibble, 2, (step >> 1n : U32)) + ima.bit(nibble, 4, step) : U32)
  +signed = Bool.pick(U32, U32.is_eq((nibble .&. 8 : U32), 0), diff, (0 - diff : U32))
  Nib{clamp16((predictor + signed : U32)), clamp((index + ima.index(nibble) : U32), 0, 88)}

def Nib.predictor(+n: Nib) -> U32:
  Nib{predictor, _} = n
  predictor

def Nib.index(+n: Nib) -> U32:
  Nib{_, index} = n
  index

type Ch is Data:
  Ch{predictor: U32, index: U32, samples: +List<U32>}

def Ch.predictor(+c: Ch) -> U32:
  Ch{predictor, _, _} = c
  predictor

def Ch.index(+c: Ch) -> U32:
  Ch{_, index, _} = c
  index

def Ch.samples(+c: Ch) -> +List<U32>:
  Ch{_, _, samples} = c
  samples

# A channel's 4 bytes: 8 samples, low nibble first.
def ima.bytes(bytes: +List<U32>, +predictor: U32, +index: U32, +acc: +List<U32>) -> Ch:
  match bytes:
    case Nil{}: Ch{predictor, index, List.reverse(&2, U32, acc)}
    case Con{+b, rest}:
      +low = ima.nibble((b .&. 15 : U32), predictor, index)
      +high = ima.nibble((b >> 4n : U32), Nib.predictor(low), Nib.index(low))
      ima.bytes(rest, Nib.predictor(high), Nib.index(high), Con{Nib.predictor(high), Con{Nib.predictor(low), acc}})

# A block header per channel: predictor (16 bits), step index, reserved byte.
def ima.header(+stereo: Bool, +s: +List<U32>, +avail: U32, +align: U32, +st: St, +acc: +List<U32>) -> Step:
  St{_, _, _, _, a0, a1, b0, b1} = st
  +size = Bool.pick(U32, stereo, 8, 4)
  +i0 = at(s, 2)
  +i1 = at(s, 6)
  +q0 = s16(s, 0)
  +q1 = s16(s, 4)
  +ok = (avail >= size : U32) && (i0 < 89 : U32) && (Bool.not(stereo) || (i1 < 89 : U32))
  +out = Bool.pick(U32, ok, 1, 0)
  Step{ok, size, (align - size : U32), St{q0, q1, i0, i1, a0, a1, b0, b1},
    Bool.pick(+List<U32>, stereo, interleave(U32.to_nat(out), [q0], [q1], acc), pushn(U32.to_nat(out), [q0], acc)), out, False{}}

# Eight frames from 4 bytes per channel (left's 4 bytes, then right's).
def ima.group(+stereo: Bool, +s: +List<U32>, +avail: U32, +rem: U32, +want: U32, +st: St, +acc: +List<U32>) -> Step:
  St{q0, q1, i0, i1, a0, a1, b0, b1} = st
  +size = Bool.pick(U32, stereo, 8, 4)
  +left = ima.bytes(List.take(&2, U32, s, 4n), q0, i0, [])
  +right = ima.bytes(List.take(&2, U32, List.drop(&2, U32, s, 4n), 4n), q1, i1, [])
  +ok = (avail >= size : U32)
  +out = Bool.pick(U32, ok, min(8, want), 0)
  Step{ok, size, (rem - size : U32),
    St{Ch.predictor(left), Bool.pick(U32, stereo, Ch.predictor(right), q1), Ch.index(left), Bool.pick(U32, stereo, Ch.index(right), i1), a0, a1, b0, b1},
    Bool.pick(+List<U32>, stereo, interleave(U32.to_nat(out), Ch.samples(left), Ch.samples(right), acc), pushn(U32.to_nat(out), Ch.samples(left), acc)), out, False{}}

# -----------------------------------------------------------------------------
# The read loop shared by both decoders: a block header when no bytes remain
# in the block (bytesRemainingInBlock is an unsigned 32-bit count), otherwise
# one byte (MS) or one 8-frame group (IMA).

def step(ima: Bool, header: Bool, stereo: Bool, +s: +List<U32>, +avail: U32, +align: U32, +rem: U32, +want: U32, +st: St, +acc: +List<U32>) -> Step:
  match ima header stereo:
    case False{} True{} False{}: ms.header.mono(s, avail, align, want, st, acc)
    case False{} True{} True{}: ms.header.stereo(s, avail, align, want, acc)
    case False{} False{} False{}: ms.byte.mono(s, avail, rem, want, st, acc)
    case False{} False{} True{}: ms.byte.stereo(s, avail, rem, st, acc)
    case True{} True{} _: ima.header(stereo, s, avail, align, st, acc)
    case True{} False{} _: ima.group(stereo, s, avail, rem, want, st, acc)

type Run is Data:
  Run{samples: +List<U32>, frames: U32, undefined: Bool}

# Each step that continues reads at least one byte, so avail+2 steps suffice.
def run(n: Nat, go: Bool, +ima: Bool, +stereo: Bool, +s: +List<U32>, +avail: U32, +align: U32, +rem: U32, +want: U32, +st: St, +acc: +List<U32>, +got: U32, +bad: Bool) -> Run:
  match n go:
    case 1n+k True{}:
      +next = step(ima, U32.is_eq(rem, 0), stereo, s, avail, align, rem, want, st, acc)
      +used = Step.used(next)
      +out = Step.out(next)
      run(k, Step.ok(next) && ((want - out) > 0 : U32), ima, stereo, List.drop(&2, U32, s, U32.to_nat(used)), (avail - used : U32), align,
        Step.rem(next), (want - out : U32), Step.st(next), Step.acc(next), (got + out : U32), bad || Step.bad(next))
    case _ _: Run{List.reverse(&2, U32, acc), got, bad}

# drwav_read_pcm_frames_s16 for MS (ima False) or IMA ADPCM: up to `want`
# frames of 1 or 2 channels from the stream at the data chunk (`avail` bytes,
# to the end of the file), with blocks of `align` bytes.
def decode(+ima: Bool, +stereo: Bool, +data: +List<U32>, +avail: U32, +align: U32, +want: U32) -> Run:
  run(U32.to_nat((avail + 2 : U32)), (want > 0 : U32), ima, stereo, data, avail, align, 0, want, St{0, 0, 0, 0, 0, 0, 0, 0}, [], 0, False{})
