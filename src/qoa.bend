# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of qoa.h (Dominic Szablewski, MIT) as pinned raylib
# 6.0 vendors it in src/external/qoa.h: qoa_decode and qoa_encode. C ints are
# U32 two's-complement words; 64-bit values are two U32 words. See
# THIRD_PARTY_NOTICES.md and LICENSES/qoa.txt.
import Base

# -----------------------------------------------------------------------------
# Two's-complement and 64-bit helpers

def negative(+x: U32) -> Bool:
  (x >= 2147483648 : U32)

def asr(+x: U32, +n: Nat) -> U32:
  Bool.pick(U32, negative(x), (((x .^. 4294967295) >> n) .^. 4294967295 : U32), (x >> n : U32))

def less(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) < (b .^. 2147483648) : U32)

def clamp(+v: U32, +lo: U32, +hi: U32) -> U32:
  Bool.pick(U32, less(v, lo), lo, Bool.pick(U32, less(hi, v), hi, v))

def clamp16(+v: U32) -> U32:
  clamp(v, 4294934528, 32767)

def short(+x: U32) -> U32:
  Bool.pick(U32, ((x .&. 65535) >= 32768 : U32), ((x .&. 65535) .|. 4294901760 : U32), (x .&. 65535 : U32))

type W is Data:
  W{hi: U32, lo: U32}

def W.hi(+w: W) -> U32:
  W{hi, _} = w
  hi

def W.lo(+w: W) -> U32:
  W{_, lo} = w
  lo

def W.add(+a: W, +b: W) -> W:
  +lo = (W.lo(a) + W.lo(b) : U32)
  W{(W.hi(a) + W.hi(b) + Bool.pick(U32, (lo < W.lo(a) : U32), 1, 0) : U32), lo}

def W.greater(+a: W, +b: W) -> Bool:
  (W.hi(a) > W.hi(b) : U32) || (U32.is_eq(W.hi(a), W.hi(b)) && (W.lo(a) > W.lo(b) : U32))

# Signed 32-bit value widened to 64 bits.
def W.signed(+x: U32) -> W:
  W{Bool.pick(U32, negative(x), 4294967295, 0), x}

# Square of |e| < 2^17 as 64 bits.
def W.square(+e: U32) -> W:
  +m = Bool.pick(U32, negative(e), (0 - e : U32), e)
  +a = (m >> 16n : U32)
  +b = (m .&. 65535 : U32)
  +cross = (2 * a * b : U32)
  +low = (b * b : U32)
  W.add(W.add(W{(a * a + (cross >> 16n) : U32), 0}, W{0, (cross << 16n : U32)}), W{0, low})

def W.shl3(+w: W, +bits: U32) -> W:
  W{((W.hi(w) << 3n) .|. (W.lo(w) >> 29n) : U32), ((W.lo(w) << 3n) .|. bits : U32)}

def W.shl(+w: W, +n: U32) -> W:
  Bool.pick(W, U32.is_eq(n, 0), w, Bool.pick(W, (n >= 32 : U32), W{(W.lo(w) << U32.to_nat((n - 32 : U32)) : U32), 0},
    W{((W.hi(w) << U32.to_nat(n)) .|. (W.lo(w) >> U32.to_nat((32 - n : U32))) : U32), (W.lo(w) << U32.to_nat(n) : U32)}))

def head(rest: +List<U32>) -> U32:
  match rest:
    case Con{value, _}: value
    case Nil{}: 0

def at(+bytes: +List<U32>, +i: U32) -> U32:
  head(List.drop(&2, U32, bytes, U32.to_nat(i)))

def be32(+bytes: +List<U32>, +i: U32) -> U32:
  ((at(bytes, i) << 24n) .|. (at(bytes, (i + 1 : U32)) << 16n) .|. (at(bytes, (i + 2 : U32)) << 8n) .|. at(bytes, (i + 3 : U32)) : U32)

def be64(+bytes: +List<U32>, +i: U32) -> W:
  W{be32(bytes, i), be32(bytes, (i + 4 : U32))}

# -----------------------------------------------------------------------------
# LMS filter and tables

def dequant(+scale: U32, +q: U32) -> U32:
  at([1, 4294967295, 3, 4294967293, 5, 4294967291, 7, 4294967289, 5, 4294967291, 18, 4294967278, 32, 4294967264, 49, 4294967247, 16, 4294967280, 53, 4294967243, 95, 4294967201, 147, 4294967149, 34, 4294967262, 113, 4294967183, 203, 4294967093, 315, 4294966981, 63, 4294967233, 210, 4294967086, 378, 4294966918, 588, 4294966708, 104, 4294967192, 345, 4294966951, 621, 4294966675, 966, 4294966330, 158, 4294967138, 528, 4294966768, 950, 4294966346, 1477, 4294965819, 228, 4294967068, 760, 4294966536, 1368, 4294965928, 2128, 4294965168, 316, 4294966980, 1053, 4294966243, 1895, 4294965401, 2947, 4294964349, 422, 4294966874, 1405, 4294965891, 2529, 4294964767, 3934, 4294963362, 548, 4294966748, 1828, 4294965468, 3290, 4294964006, 5117, 4294962179, 696, 4294966600, 2320, 4294964976, 4176, 4294963120, 6496, 4294960800, 868, 4294966428, 2893, 4294964403, 5207, 4294962089, 8099, 4294959197, 1064, 4294966232, 3548, 4294963748, 6386, 4294960910, 9933, 4294957363, 1286, 4294966010, 4288, 4294963008, 7718, 4294959578, 12005, 4294955291, 1536, 4294965760, 5120, 4294962176, 9216, 4294958080, 14336, 4294952960], (scale * 8 + q : U32))

def quant(+clamped: U32) -> U32:
  at([7, 7, 7, 5, 5, 3, 3, 1, 0, 0, 2, 2, 4, 4, 6, 6, 6], (clamped + 8 : U32))

def reciprocal(+scale: U32) -> U32:
  at([65536, 9363, 3121, 1457, 781, 475, 311, 216, 156, 117, 90, 71, 57, 47, 39, 32], scale)

type Lms is Data:
  Lms{h0: U32, h1: U32, h2: U32, h3: U32, w0: U32, w1: U32, w2: U32, w3: U32}

def Lms.predict(+lms: Lms) -> U32:
  Lms{h0, h1, h2, h3, w0, w1, w2, w3} = lms
  asr((w0 * h0 + w1 * h1 + w2 * h2 + w3 * h3 : U32), 13n)

def Lms.step(+h: U32, +w: U32, +delta: U32) -> U32:
  Bool.pick(U32, negative(h), (w - delta : U32), (w + delta : U32))

def Lms.update(+lms: Lms, +sample: U32, +residual: U32) -> Lms:
  Lms{h0, h1, h2, h3, w0, w1, w2, w3} = lms
  +delta = asr(residual, 4n)
  Lms{h1, h2, h3, sample, Lms.step(h0, w0, delta), Lms.step(h1, w1, delta), Lms.step(h2, w2, delta), Lms.step(h3, w3, delta)}

def Lms.penalty(+lms: Lms) -> U32:
  Lms{_, _, _, _, w0, w1, w2, w3} = lms
  +p = (asr((w0 * w0 + w1 * w1 + w2 * w2 + w3 * w3 : U32), 18n) - 2303 : U32)
  Bool.pick(U32, negative(p), 0, p)

def Lms.initial() -> Lms:
  Lms{0, 0, 0, 0, 0, 0, 4294959104, 16384}

# qoa_div: rounding division by a scalefactor, away from zero for small values.
def sign(+v: U32) -> U32:
  Bool.pick(U32, negative(v), 4294967295, Bool.pick(U32, U32.is_eq(v, 0), 0, 1))

def div(+v: U32, +scale: U32) -> U32:
  +n = asr((v * reciprocal(scale) + 32768 : U32), 16n)
  (n + sign(v) - sign(n) : U32)

def lms.word(+word: W, +i: Nat) -> U32:
  short(Bool.pick(U32, Nat.is_lt(i, 2n), (W.hi(word) >> U32.to_nat((16 - 16 * U32.from_nat(i) : U32)) : U32), (W.lo(word) >> U32.to_nat((48 - 16 * U32.from_nat(i) : U32)) : U32)))

def lms.read(+history: W, +weights: W) -> Lms:
  Lms{lms.word(history, 0n), lms.word(history, 1n), lms.word(history, 2n), lms.word(history, 3n),
    lms.word(weights, 0n), lms.word(weights, 1n), lms.word(weights, 2n), lms.word(weights, 3n)}

def lms.write(+lms: Lms) -> +List<W>:
  Lms{h0, h1, h2, h3, w0, w1, w2, w3} = lms
  [W{(((h0 .&. 65535) << 16n) .|. (h1 .&. 65535) : U32), (((h2 .&. 65535) << 16n) .|. (h3 .&. 65535) : U32)},
   W{(((w0 .&. 65535) << 16n) .|. (w1 .&. 65535) : U32), (((w2 .&. 65535) << 16n) .|. (w3 .&. 65535) : U32)}]

def pick.lms(+states: +List<Lms>, +i: U32) -> Lms:
  match states:
    case Nil{}: Lms.initial()
    case Con{first, rest}: Bool.pick(Lms, U32.is_eq(i, 0), first, pick.lms(rest, (i - 1 : U32)))

def put.lms(+states: +List<Lms>, +i: U32, +value: Lms) -> +List<Lms>:
  match states:
    case Nil{}: Nil{}
    case Con{first, rest}: Bool.pick(+List<Lms>, U32.is_eq(i, 0), Con{value, rest}, Con{first, put.lms(rest, (i - 1 : U32), value)})

# -----------------------------------------------------------------------------
# Decoder (qoa_decode)

type Slice is Type:
  Slice{lms: Lms, out: Array<U32>}

# One slice of `count` samples of channel c from frame sample `base`.
def slice.decode(n: Nat, +j: U32, +base: U32, +c: U32, +channels: U32, +scale: U32, +word: W, +lms: Lms, out: Array<U32>) -> Slice:
  match n:
    case 0n: Slice{lms, out}
    case 1n+k:
      +predicted = Lms.predict(lms)
      +q = ((W.hi(word) >> 29n) .&. 7 : U32)
      +dq = dequant(scale, q)
      +sample = clamp16((predicted + dq : U32))
      slice.decode(k, (j + 1 : U32), base, c, channels, scale, W.shl3(word, 0), Lms.update(lms, sample, dq),
        Array.set(U32, out, ((base + j) * channels + c : U32), (sample .&. 65535 : U32)))

# A frame's slices in file order: sample offset and channel.
type Unit is Data:
  Unit{base: U32, channel: U32}

def Unit.base(+unit: Unit) -> U32:
  Unit{base, _} = unit
  base

def Unit.channel(+unit: Unit) -> U32:
  Unit{_, channel} = unit
  channel

def units.channels(n: Nat, +base: U32, +c: U32, +acc: +List<Unit>) -> +List<Unit>:
  match n:
    case 0n: acc
    case 1n+k: units.channels(k, base, (c + 1 : U32), Con{Unit{base, c}, acc})

def units(n: Nat, +base: U32, +channels: U32, +acc: +List<Unit>) -> +List<Unit>:
  match n:
    case 0n: List.reverse(&2, Unit, acc)
    case 1n+k: units(k, (base + 20 : U32), channels, units.channels(U32.to_nat(channels), base, 0, acc))

type Frame is Type:
  Frame{p: U32, states: +List<Lms>, out: Array<U32>, beyond: Bool}

def frame.slice(slice: Slice, +p: U32, +states: +List<Lms>, +c: U32) -> Frame:
  match slice:
    case Slice{lms, out}: Frame{(p + 8 : U32), put.lms(states, c, lms), out, False{}}

def frame.unit.read(fits: Bool, +base: U32, +c: U32, +channels: U32, +count: U32, +word: W, +p: U32, +states: +List<Lms>, out: Array<U32>) -> Frame:
  match fits:
    case False{}: Frame{p, states, out, True{}}
    case True{}:
      frame.slice(slice.decode(U32.to_nat(count), 0, base, c, channels, ((W.hi(word) >> 28n) .&. 15 : U32), W.shl(word, 4), pick.lms(states, c), out), p, states, c)

def frame.unit(+unit: Unit, +bytes: +List<U32>, +len: U32, +samples: U32, +channels: U32, frame: Frame) -> Frame:
  match frame:
    case Frame{+p, +states, out, False{}}:
      +base = Unit.base(unit)
      +c = Unit.channel(unit)
      +word = be64(bytes, p)
      +count = Bool.pick(U32, ((base + 20) <= samples : U32), 20, (samples - base : U32))
      +fits = ((p + 8) <= len : U32)
      frame.unit.read(fits, base, c, channels, count, word, p, states, out)
    case Frame{p, states, out, True{}}: Frame{p, states, out, True{}}

def frame.units(units: +List<Unit>, +bytes: +List<U32>, +len: U32, +samples: U32, +channels: U32, frame: Frame) -> Frame:
  match units:
    case Nil{}: frame
    case Con{unit, rest}: frame.units(rest, bytes, len, samples, channels, frame.unit(unit, bytes, len, samples, channels, frame))

def frame.states(n: Nat, +bytes: +List<U32>, +p: U32, +acc: +List<Lms>) -> +List<Lms>:
  match n:
    case 0n: List.reverse(&2, Lms, acc)
    case 1n+k: frame.states(k, bytes, (p + 16 : U32), Con{lms.read(be64(bytes, p), be64(bytes, (p + 8 : U32))), acc})

def plus(values: List<U32>, acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{value, rest}: plus(rest, Con{value, acc})

def capacity(+count: U32) -> Nat:
  Bool.pick(Nat, (count <= 1 : U32), 0n, 1n+U32.log2((count - 1 : U32)))

# The file's decoding state: position, frames decoded, samples, and whether
# raylib's behavior became undefined (writes past its buffer, reads past the
# data, more than 8 channels).
type Run is Data:
  Run{p: U32, frames: U32, samples: +List<U32>, done: Bool, undefined: Bool}

def run.frame(frame: Frame, +start: U32, +decoded: U32, +samples: +List<U32>, +count: U32, +channels: U32, +total: U32) -> Run:
  match frame:
    case Frame{p, _, _, True{}}: Run{p, decoded, samples, True{}, True{}}
    case Frame{+p, _, out, False{}}:
      +more = List.append(&2, U32, samples, List.take(&2, U32, plus(Array.to_list(~U32, out), Nil{}), U32.to_nat((count * channels : U32))))
      Run{p, (decoded + count : U32), more, ((decoded + count) >= total : U32), ((decoded + count) > total : U32)}

# qoa_decode_frame at p; a failed frame ends the file with what was decoded.
def run.step(+bytes: +List<U32>, +len: U32, +channels: U32, +rate: U32, +total: U32, +p: U32, +decoded: U32, +samples: +List<U32>) -> Run:
  +size = (len - p : U32)
  +header = be64(bytes, p)
  +fch = (W.hi(header) >> 24n : U32)
  +frate = (W.hi(header) .&. 16777215 : U32)
  +count = (W.lo(header) >> 16n : U32)
  +fsize = (W.lo(header) .&. 65535 : U32)
  +slices = ((fsize - 8 - 16 * fch) / 8 : U32)
  +failed = (size < (8 + 16 * channels) : U32) || U32.is_ne(fch, channels) || U32.is_ne(frate, rate) || (fsize > size : U32) || ((count * fch) > (slices * 20) : U32)
  Bool.pick(Run, failed, Run{p, decoded, samples, True{}, False{}},
    run.frame(frame.units(units(U32.to_nat(((count + 19) / 20 : U32)), 0, channels, Nil{}), bytes, len, count, channels,
      Frame{(p + 8 + 16 * channels : U32), frame.states(U32.to_nat(channels), bytes, (p + 8 : U32), Nil{}), Array.new(U32, capacity((count * channels : U32)), 0), False{}}),
      p, decoded, samples, count, channels, total))

def run.loop(n: Nat, +bytes: +List<U32>, +len: U32, +channels: U32, +rate: U32, +total: U32, run: Run) -> Run:
  match n run:
    case 1n+k Run{p, decoded, samples, False{}, _}: run.loop(k, bytes, len, channels, rate, total, run.step(bytes, len, channels, rate, total, p, decoded, samples))
    case _ other: other

type Outcome is Type:
  Decoded{rate: U32, channels: U32, frames: U32, samples: +List<U32>}
  Invalid{undefined: Bool}

def run.result(run: Run, +rate: U32, +channels: U32) -> Outcome:
  match run:
    case Run{_, _, _, _, True{}}: Invalid{True{}}
    case Run{_, decoded, samples, _, False{}}: Decoded{rate, channels, decoded, samples}

def byte_count(data: +List<U32>, +count: U32) -> U32:
  match data:
    case Nil{}: count
    case Con{_, rest}: byte_count(rest, (count + 1 : U32))

# qoa_decode: the header, then frames until the declared samples or a frame
# that fails. Files whose samples exceed 2^24 are Invalid (undefined: Jonlib's
# bound); more than 8 channels overrun raylib's LMS state.
def decode(+bytes: +List<U32>) -> Outcome:
  +len = byte_count(bytes, 0)
  +header = be64(bytes, 0)
  +total = W.lo(header)
  +frame = be64(bytes, 8)
  +channels = (W.hi(frame) >> 24n : U32)
  +rate = (W.hi(frame) .&. 16777215 : U32)
  Bool.pick(Outcome, (len < 16 : U32) || U32.is_ne(W.hi(header), 1903124838) || U32.is_eq(total, 0) || U32.is_eq(channels, 0) || U32.is_eq(rate, 0), Invalid{False{}},
    Bool.pick(Outcome, (channels > 8 : U32) || (total > 16777216 : U32) || ((total * channels) > 16777216 : U32), Invalid{True{}},
      run.result(run.loop(U32.to_nat(((len / (8 + 16 * channels)) + 1 : U32)), bytes, len, channels, rate, total, Run{8, 0, Nil{}, False{}, False{}}), rate, channels)))

# -----------------------------------------------------------------------------
# Encoder (qoa_encode)

def W.less(+a: W, +b: W) -> Bool:
  (W.hi(a) < W.hi(b) : U32) || (U32.is_eq(W.hi(a), W.hi(b)) && (W.lo(a) < W.lo(b) : U32))

# One scalefactor's pass over a slice: the rank (squared error plus the
# weight penalty, as uint64), the encoded slice and the LMS state; it stops
# once the rank exceeds the best so far.
type Trial is Data:
  Trial{rank: W, slice: W, lms: Lms, stopped: Bool}

def trial.step(+sample: U32, +scale: U32, +best: W, trial: Trial) -> Trial:
  match trial:
    case Trial{rank, slice, lms, True{}}: Trial{rank, slice, lms, True{}}
    case Trial{+rank, +slice, +lms, False{}}:
      +s = short(sample)
      +predicted = Lms.predict(lms)
      +clamped = clamp(div((s - predicted : U32), scale), 4294967288, 8)
      +q = quant(clamped)
      +dq = dequant(scale, q)
      +rec = clamp16((predicted + dq : U32))
      +penalty = Lms.penalty(lms)
      +next = W.add(rank, W.add(W.square((s - rec : U32)), W.signed((penalty * penalty : U32))))
      Bool.pick(Trial, W.greater(next, best), Trial{next, slice, lms, True{}}, Trial{next, W.shl3(slice, q), Lms.update(lms, rec, dq), False{}})

def trial.run(samples: +List<U32>, +scale: U32, +best: W, +trial: Trial) -> Trial:
  match samples:
    case Nil{}: trial
    case Con{sample, rest}: trial.run(rest, scale, best, trial.step(sample, scale, best, trial))

type Best is Data:
  Best{rank: W, slice: W, lms: Lms, scale: U32}

def Best.of(+trial: Trial, +scale: U32) -> Best:
  Trial{rank, slice, lms, _} = trial
  Best{rank, slice, lms, scale}

def Best.slice(+best: Best) -> W:
  Best{_, slice, _, _} = best
  slice

def Best.lms(+best: Best) -> Lms:
  Best{_, _, lms, _} = best
  lms

def Best.scale(+best: Best) -> U32:
  Best{_, _, _, scale} = best
  scale

def Best.rank(+best: Best) -> W:
  Best{rank, _, _, _} = best
  rank

def Trial.rank(+trial: Trial) -> W:
  Trial{rank, _, _, _} = trial
  rank

def search(n: Nat, +sfi: U32, +prev: U32, +samples: +List<U32>, +lms: Lms, +best: Best) -> Best:
  match n:
    case 0n: best
    case 1n+k:
      +scale = ((sfi + prev) .&. 15 : U32)
      +t = trial.run(samples, scale, Best.rank(best), Trial{W{0, 0}, W{0, scale}, lms, False{}})
      search(k, (sfi + 1 : U32), prev, samples, lms, Bool.pick(Best, W.less(Trial.rank(t), Best.rank(best)), Best.of(t, scale), best))

def pick.list(+lists: +List<+List<U32>>, +i: U32) -> +List<U32>:
  match lists:
    case Nil{}: Nil{}
    case Con{first, rest}: Bool.pick(+List<U32>, U32.is_eq(i, 0), first, pick.list(rest, (i - 1 : U32)))

def pick.u32(+values: +List<U32>, +i: U32) -> U32:
  at(values, i)

def put.u32(+values: +List<U32>, +i: U32, +value: U32) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{first, rest}: Bool.pick(+List<U32>, U32.is_eq(i, 0), Con{value, rest}, Con{first, put.u32(rest, (i - 1 : U32), value)})

type Enc is Data:
  Enc{states: +List<Lms>, prevs: +List<U32>, words: +List<W>}

def enc.best(+best: Best, +c: U32, +count: U32, +enc: Enc) -> Enc:
  Enc{states, prevs, words} = enc
  Enc{put.lms(states, c, Best.lms(best)), put.u32(prevs, c, Best.scale(best)), Con{W.shl(Best.slice(best), ((20 - count) * 3 : U32)), words}}

def Enc.states(+enc: Enc) -> +List<Lms>:
  Enc{states, _, _} = enc
  states

def Enc.words(+enc: Enc) -> +List<W>:
  Enc{_, _, words} = enc
  words

def Enc.prevs(+enc: Enc) -> +List<U32>:
  Enc{_, prevs, _} = enc
  prevs

def enc.units(units: +List<Unit>, +chans: +List<+List<U32>>, +length: U32, +enc: Enc) -> Enc:
  match units:
    case Nil{}: enc
    case Con{+unit, rest}:
      +base = Unit.base(unit)
      +c = Unit.channel(unit)
      +count = Bool.pick(U32, ((base + 20) <= length : U32), 20, (length - base : U32))
      +samples = List.take(&2, U32, List.drop(&2, U32, pick.list(chans, c), U32.to_nat(base)), U32.to_nat(count))
      +lms = pick.lms(Enc.states(enc), c)
      enc.units(rest, chans, length, enc.best(search(16n, 0, pick.u32(Enc.prevs(enc), c), samples, lms, Best{W{4294967295, 4294967295}, W{0, 0}, lms, 0}), c, count, enc))

def stride(n: Nat, +values: +List<U32>, +step: U32) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{head(values), stride(k, List.drop(&2, U32, values, U32.to_nat(step)), step)}

def channels.split(n: Nat, +c: U32, +values: +List<U32>, +channels: U32, +length: U32) -> +List<+List<U32>>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{stride(U32.to_nat(length), List.drop(&2, U32, values, U32.to_nat(c)), channels), channels.split(k, (c + 1 : U32), values, channels, length)}

def zeros(n: Nat) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{0, zeros(k)}

def lms.words(states: +List<Lms>) -> +List<W>:
  match states:
    case Nil{}: Nil{}
    case Con{lms, rest}: List.append(&2, W, lms.write(lms), lms.words(rest))

def W.bytes(words: +List<W>) -> +List<U32>:
  match words:
    case Nil{}: Nil{}
    case Con{+w, rest}:
      +hi = W.hi(w)
      +lo = W.lo(w)
      Con{(hi >> 24n : U32), Con{((hi >> 16n) .&. 255 : U32), Con{((hi >> 8n) .&. 255 : U32), Con{(hi .&. 255 : U32),
        Con{(lo >> 24n : U32), Con{((lo >> 16n) .&. 255 : U32), Con{((lo >> 8n) .&. 255 : U32), Con{(lo .&. 255 : U32), W.bytes(rest)}}}}}}}}

def W.header(+channels: U32, +rate: U32, +length: U32, +size: U32) -> W:
  W{((channels << 24n) .|. rate : U32), ((length << 16n) .|. size : U32)}

type Out is Data:
  Out{states: +List<Lms>, rest: +List<U32>, index: U32, words: +List<W>}

# qoa_encode_frame for the frame starting at `index`.
def out.frame(+channels: U32, +rate: U32, +total: U32, +out: Out) -> Out:
  Out{states, rest, index, words} = out
  +length = Bool.pick(U32, ((index + 5120) <= total : U32), 5120, (total - index : U32))
  +slices = ((length + 19) / 20 : U32)
  +size = (8 + 16 * channels + 8 * slices * channels : U32)
  +samples = List.take(&2, U32, rest, U32.to_nat((length * channels : U32)))
  +enc = enc.units(units(U32.to_nat(slices), 0, channels, Nil{}), channels.split(U32.to_nat(channels), 0, samples, channels, length), length,
    Enc{states, zeros(U32.to_nat(channels)), Nil{}})
  Out{Enc.states(enc), List.drop(&2, U32, rest, U32.to_nat((length * channels : U32))), (index + length : U32),
    List.append(&2, W, words, Con{W.header(channels, rate, length, size), List.append(&2, W, lms.words(states), List.reverse(&2, W, Enc.words(enc)))})}

def out.loop(n: Nat, +channels: U32, +rate: U32, +total: U32, +out: Out) -> Out:
  match n:
    case 0n: out
    case 1n+k: out.loop(k, channels, rate, total, out.frame(channels, rate, total, out))

def states.initial(n: Nat) -> +List<Lms>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{Lms.initial(), states.initial(k)}

def Out.words(+out: Out) -> +List<W>:
  Out{_, _, _, words} = out
  words

# qoa_encode: None for zero frames, a sample rate outside 1..0xffffff or
# channels outside 1..8 (qoa_write then leaves an empty file).
def encode(+samples: +List<U32>, +total: U32, +channels: U32, +rate: U32) -> Maybe<&2, +List<U32>>:
  Bool.pick(Maybe<&2, +List<U32>>, U32.is_eq(total, 0) || U32.is_eq(rate, 0) || (rate > 16777215 : U32) || U32.is_eq(channels, 0) || (channels > 8 : U32), None{},
    Some{W.bytes(Con{W{1903124838, total}, Out.words(out.loop(U32.to_nat(((total + 5119) / 5120 : U32)), channels, rate, total,
      Out{states.initial(U32.to_nat(channels)), samples, 0, Nil{}}))})})
