# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the miniaudio v0.11.24 paths raylib 6.0's
# WaveFormat reaches through ma_convert_frames: ma_data_converter (mid format
# and execution path selection), the u8/s16/f32 sample conversions
# (ma_pcm_*_to_*, no dither), ma_channel_converter with the default
# (Microsoft) channel maps and rectangular mixing, and the linear resampler
# (src/resampler.bend, src/lowpass.bend), as raylib vendors it in
# src/external/miniaudio.h. miniaudio: David Reid, public domain or MIT No
# Attribution; see THIRD_PARTY_NOTICES.md and LICENSES/miniaudio.txt.
#
# Samples are U32 words as in a Jonlib Wave: u8 values, s16 bit patterns and
# f32 bits. Inside the converter, s16 values are sign-extended ints.
import Base
import ./fma.bend as Fma
import ./resampler.bend as R
import ./lowpass.bend as L

# -----------------------------------------------------------------------------
# Sample formats: 0 u8, 1 s16, 2 f32.

def format(+size: U32) -> U32:
  Bool.pick(U32, U32.is_eq(size, 8), 0, Bool.pick(U32, U32.is_eq(size, 16), 1, 2))

def is_nan(+bits: U32) -> Bool:
  ((bits .&. 2147483647) > 2139095040 : U32)

def signed_f32(+v: U32) -> F32:
  Bool.pick(F32, R.negative(v), F32.neg(U32.to_f32((0 - v : U32))), U32.to_f32(v))

# The clip of ma_pcm_f32_to_u8 and ma_pcm_f32_to_s16 (after adding a zero
# dither, which turns -0 into +0).
def clip(+x: F32) -> F32:
  Bool.pick(F32, (x < F32.neg(1.0) : F32), F32.neg(1.0), Bool.pick(F32, (x > 1.0 : F32), 1.0, x))

# (ma_int16) of a value in [-32767, 32767]: truncation toward zero.
def truncate16(+y: F32) -> U32:
  +t = F32.to_u32(F32.abs(y))
  Bool.pick(U32, (y < 0.0 : F32), (0 - t : U32), t)

# One sample from format `from` to format `to` (kind = 3*from + to).
def sample(kind: U32, +v: U32) -> U32:
  match kind:
    case 1: ((v - 128) << 8n : U32)
    case 2: F32.bits((((U32.to_f32(v) * R.float(1006665857)) : F32) - 1.0 : F32))
    case 3: ((R.asr(v, 8n) + 128) .&. 255 : U32)
    case 5: F32.bits((signed_f32(v) * R.float(939524096) : F32))
    case 6: F32.to_u32((((clip((R.float(v) + 0.0 : F32)) + 1.0) : F32) * 127.5 : F32))
    case 7: truncate16((clip((R.float(v) + 0.0 : F32)) * 32767.0 : F32))
    case _: v

# ma_pcm_f32_to_s16's NEON/SSE2 blocks skip the clip, so values whose product
# with 32767 is at most -32768 or at least 2^31 (and NaN) convert differently
# there than in its scalar tail: which samples take which path depends on
# buffer alignment.
def ambiguous16(+v: U32) -> Bool:
  +p = ((R.float(v) + 0.0 : F32) * 32767.0 : F32)
  Bool.not((p > F32.neg(32768.0) : F32)) || (p >= 2147483648.0 : F32)

def any_nan(values: +List<U32>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{+v, rest}: is_nan(v) || any_nan(rest)

def any_ambiguous16(values: +List<U32>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{+v, rest}: ambiguous16(v) || any_ambiguous16(rest)

def map.sample(values: +List<U32>, +kind: U32) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{+v, rest}: Con{sample(kind, v), map.sample(rest, kind)}

def map.decode(values: +List<U32>, +s16: Bool) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{+v, rest}: Con{Bool.pick(U32, s16, R.short(v), v), map.decode(rest, s16)}

def map.encode(values: +List<U32>, +s16: Bool) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{+v, rest}: Con{Bool.pick(U32, s16, (v .&. 65535 : U32), v), map.encode(rest, s16)}

# -----------------------------------------------------------------------------
# Channel conversion with the default channel maps (ma_channel_converter).

def table(+count: U32) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_eq(count, 2), [2, 3], Bool.pick(+List<U32>, U32.is_eq(count, 3), [2, 3, 4],
    Bool.pick(+List<U32>, U32.is_eq(count, 4), [2, 3, 4, 10], Bool.pick(+List<U32>, U32.is_eq(count, 5), [2, 3, 4, 6, 7],
      Bool.pick(+List<U32>, U32.is_eq(count, 6), [2, 3, 4, 5, 11, 12], Bool.pick(+List<U32>, U32.is_eq(count, 7), [2, 3, 4, 5, 10, 11, 12],
        [2, 3, 4, 5, 6, 7, 11, 12]))))))

# ma_channel_map_init_standard_channel_microsoft: MONO for one channel; the
# first eight from the speaker tables; then AUX_0.. up to index 31; NONE after.
def position(+count: U32, +index: U32) -> U32:
  Bool.pick(U32, U32.is_eq(count, 1), 1, Bool.pick(U32, (index < 8 : U32), R.at(table(count), index), Bool.pick(U32, (index < 32 : U32), (12 + index : U32), 0)))

# Plane ratios (left, right, front, back) in halves, for the positions the
# default maps use: FL 2, FR 3, FC 4, BL 6, BR 7, BC 10, SL 11, SR 12.
def ratios(+pos: U32) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_eq(pos, 2), [1, 0, 1, 0], Bool.pick(+List<U32>, U32.is_eq(pos, 3), [0, 1, 1, 0],
    Bool.pick(+List<U32>, U32.is_eq(pos, 4), [0, 0, 2, 0], Bool.pick(+List<U32>, U32.is_eq(pos, 6), [1, 0, 0, 1],
      Bool.pick(+List<U32>, U32.is_eq(pos, 7), [0, 1, 0, 1], Bool.pick(+List<U32>, U32.is_eq(pos, 10), [0, 0, 0, 2],
        Bool.pick(+List<U32>, U32.is_eq(pos, 11), [2, 0, 0, 0], Bool.pick(+List<U32>, U32.is_eq(pos, 12), [0, 2, 0, 0], [0, 0, 0, 0]))))))))

def spatial(+pos: U32) -> Bool:
  U32.is_ne((R.at(ratios(pos), 0) + R.at(ratios(pos), 1) + R.at(ratios(pos), 2) + R.at(ratios(pos), 3) : U32), 0)

def dot(a: +List<U32>, b: +List<U32>) -> U32:
  match a b:
    case Con{+x, xs} Con{+y, ys}: (x * y + dot(xs, ys) : U32)
    case _ _: 0

# ma_calculate_channel_position_rectangular_weight in quarters (exact: the
# products of halves are quarters and their sums are exact in float).
def rectangular(+a: U32, +b: U32) -> U32:
  dot(ratios(a), ratios(b))

def contains.go(n: Nat, +count: U32, +index: U32, +pos: U32) -> Bool:
  match n:
    case 0n: False{}
    case 1n+k: U32.is_eq(position(count, index), pos) || contains.go(k, count, (index + 1 : U32), pos)

# Spatial positions only occur among the first eight channels.
def contains(+count: U32, +pos: U32) -> Bool:
  contains.go(U32.to_nat(U32.min(count, 8)), count, 0, pos)

# The weight of input channel i in output channel o, in quarters: 1:1 for
# equal positions (NONE matches NONE beyond 32 channels), else rectangular
# between spatial channels when either is missing from the other map.
def weight(+cin: U32, +cout: U32, +i: U32, +o: U32) -> U32:
  +pin = position(cin, i)
  +pout = position(cout, o)
  Bool.pick(U32, U32.is_eq(pin, pout), 4,
    Bool.pick(U32, spatial(pin) && spatial(pout) && (Bool.not(contains(cout, pin)) || Bool.not(contains(cin, pout))), rectangular(pin, pout), 0))

def weights.row(n: Nat, +cin: U32, +cout: U32, +i: U32, +o: U32) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{weight(cin, cout, i, o), weights.row(k, cin, cout, (i + 1 : U32), o)}

# One list of input weights per output channel.
def weights(n: Nat, +cin: U32, +cout: U32, +o: U32) -> +List<+List<U32>>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{weights.row(U32.to_nat(cin), cin, cout, 0, o), weights(k, cin, cout, (o + 1 : U32))}

# Accumulate in input-channel order: s16 adds (x*w) >> 12 and clamps each
# step; f32 adds x*w (one fused multiply-add under contraction).
def mix.s16(xs: +List<U32>, ws: +List<U32>, +acc: U32) -> U32:
  match xs ws:
    case Con{+x, rest} Con{+w, wrest}: mix.s16(rest, wrest, R.clamp16((acc + R.asr((x * (w * 1024) : U32), 12n) : U32)))
    case _ _: acc

def mix.term(fused: Bool, +x: F32, +w: F32, +acc: F32) -> F32:
  match fused:
    case True{}: Fma.multiply_add(x, w, acc)
    case False{}: (acc + (x * w) : F32)

def mix.f32(xs: +List<U32>, ws: +List<U32>, +fused: Bool, +acc: F32) -> F32:
  match xs ws:
    case Con{+x, rest} Con{+w, wrest}: mix.f32(rest, wrest, fused, mix.term(fused, R.float(x), (U32.to_f32(w) * 0.25 : F32), acc))
    case _ _: acc

def mix.value(f32: Bool, +frame: +List<U32>, +ws: +List<U32>, +fused: Bool) -> U32:
  match f32:
    case True{}: F32.bits(mix.f32(frame, ws, fused, 0.0))
    case False{}: mix.s16(frame, ws, 0)

def mix.frame(table: +List<+List<U32>>, +frame: +List<U32>, +f32: Bool, +fused: Bool) -> +List<U32>:
  match table:
    case Nil{}: Nil{}
    case Con{+ws, rest}: Con{mix.value(f32, frame, ws, fused), mix.frame(rest, frame, f32, fused)}

def sum.s16(xs: +List<U32>, +acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case Con{+x, rest}: sum.s16(rest, (acc + x : U32))

def sum.f32(xs: +List<U32>, +acc: F32) -> F32:
  match xs:
    case Nil{}: acc
    case Con{+x, rest}: sum.f32(rest, (acc + R.float(x) : F32))

# Mono output averages: s16 divides the int sum as unsigned (C's usual
# conversions make t / channelsIn unsigned) and keeps 16 bits.
def mono.out(+frame: +List<U32>, +f32: Bool, +cin: U32) -> +List<U32>:
  [Bool.pick(U32, f32, F32.bits((sum.f32(frame, 0.0) / U32.to_f32(cin) : F32)), R.short((sum.s16(frame, 0) / cin : U32)))]

def repeat(n: Nat, +v: U32) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{v, repeat(k, v)}

# 0: mono out; 1: mono in; 2: weights.
def channel.frame(path: U32, +frame: +List<U32>, +table: +List<+List<U32>>, +f32: Bool, +fused: Bool, +cin: U32, +cout: U32) -> +List<U32>:
  match path:
    case 0: mono.out(frame, f32, cin)
    case 1: repeat(U32.to_nat(cout), R.at(frame, 0))
    case _: mix.frame(table, frame, f32, fused)

def channel.frames(frames: +List<+List<U32>>, +path: U32, +table: +List<+List<U32>>, +f32: Bool, +fused: Bool, +cin: U32, +cout: U32) -> +List<+List<U32>>:
  match frames:
    case Nil{}: Nil{}
    case Con{+frame, rest}: Con{channel.frame(path, frame, table, f32, fused, cin, cout), channel.frames(rest, path, table, f32, fused, cin, cout)}

def channels.convert(+frames: +List<+List<U32>>, +f32: Bool, +fused: Bool, +cin: U32, +cout: U32) -> +List<+List<U32>>:
  +path = Bool.pick(U32, U32.is_eq(cout, 1), 0, Bool.pick(U32, U32.is_eq(cin, 1), 1, 2))
  channel.frames(frames, path, Bool.pick(+List<+List<U32>>, U32.is_eq(path, 2), weights(U32.to_nat(cout), cin, cout, 0), Nil{}), f32, fused, cin, cout)

# -----------------------------------------------------------------------------
# Frames

def split(n: Nat, +c: Nat, +values: +List<U32>) -> +List<+List<U32>>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{List.take(&2, U32, values, c), split(k, c, List.drop(&2, U32, values, c))}

def flat(frames: +List<+List<U32>>) -> +List<U32>:
  match frames:
    case Nil{}: Nil{}
    case Con{frame, rest}: List.append(&2, U32, frame, flat(rest))

def gcd(n: Nat, +a: U32, +b: U32) -> U32:
  match n:
    case 0n: a
    case 1n+k: Bool.pick(U32, U32.is_eq(b, 0), a, gcd(k, b, (a % Bool.pick(U32, U32.is_eq(b, 0), 1, b) : U32)))

# -----------------------------------------------------------------------------
# ma_convert_frames as WaveFormat calls it (no dither, linear resampling, LPF
# order 4, default channel maps and mixing).

type Outcome is Data:
  Converted{frames: U32, samples: +List<U32>}
  Unchanged{}
  Refused{kind: U32}

type Plan is Data:
  Plan{fin: U32, mid: U32, fout: U32, cin: U32, cout: U32, rin: U32, rout: U32, n: U32, count: U32, resample: Bool, fused: Bool}

def Plan.resample(+plan: Plan) -> Bool:
  Plan{_, _, _, _, _, _, _, _, _, resample, _} = plan
  resample

def Plan.cin(+plan: Plan) -> U32:
  Plan{_, _, _, cin, _, _, _, _, _, _, _} = plan
  cin

def Plan.cout(+plan: Plan) -> U32:
  Plan{_, _, _, _, cout, _, _, _, _, _, _} = plan
  cout

def Plan.f32(+plan: Plan) -> Bool:
  Plan{_, mid, _, _, _, _, _, _, _, _, _} = plan
  U32.is_eq(mid, 2)

def Plan.fused(+plan: Plan) -> Bool:
  Plan{_, _, _, _, _, _, _, _, _, _, fused} = plan
  fused

def Plan.mid(+plan: Plan) -> U32:
  Plan{_, mid, _, _, _, _, _, _, _, _, _} = plan
  mid

def Plan.fout(+plan: Plan) -> U32:
  Plan{_, _, fout, _, _, _, _, _, _, _, _} = plan
  fout

def Plan.count(+plan: Plan) -> U32:
  Plan{_, _, _, _, _, _, _, _, count, _, _} = plan
  count

def channels.if(apply: Bool, +frames: +List<+List<U32>>, +plan: Plan) -> +List<+List<U32>>:
  match apply:
    case True{}: channels.convert(frames, Plan.f32(plan), Plan.fused(plan), Plan.cin(plan), Plan.cout(plan))
    case False{}: frames

type Stream is Data:
  Stream{frames: +List<+List<U32>>, ok: Bool, complete: Bool}

def resample.done(+run: R.Run, +count: U32) -> Stream:
  R.Run{frames, produced, ok} = run
  Stream{frames, ok, U32.is_eq(produced, count)}

def resample.if(apply: Bool, +k: +List<U32>, +channels: U32, +frames: +List<+List<U32>>, +plan: Plan) -> Stream:
  match apply:
    case True{}:
      Plan{_, _, _, _, _, +rin, +rout, +n, +count, _, +fused} = plan
      resample.done(R.resample(Plan.f32(plan), fused, k, channels, rin, rout, n, count, frames), count)
    case False{}: Stream{frames, True{}, True{}}

def resample.channels(+stream: Stream, +plan: Plan) -> Stream:
  Stream{frames, ok, complete} = stream
  Stream{channels.if(True{}, frames, plan), ok, complete}

def Stream.frames(+stream: Stream) -> +List<+List<U32>>:
  Stream{frames, _, _} = stream
  frames

# ma_data_converter_process_pcm_frames__channels_first / __resample_first:
# the resampler runs where the channel count is lowest.
def stages(first: Bool, +k: +List<U32>, +frames: +List<+List<U32>>, +plan: Plan) -> Stream:
  match first:
    case True{}: resample.if(Plan.resample(plan), k, Plan.cout(plan), channels.if(U32.is_ne(Plan.cin(plan), Plan.cout(plan)), frames, plan), plan)
    case False{}: resample.channels(resample.if(Plan.resample(plan), k, Plan.cin(plan), frames, plan), plan)

def finish.checked(kind: U32, +mid: +List<U32>, +plan: Plan) -> Outcome:
  match kind:
    case 0: Converted{Plan.count(plan), map.encode(map.sample(mid, (3 * Plan.mid(plan) + Plan.fout(plan) : U32)), U32.is_eq(Plan.fout(plan), 1))}
    case _: Refused{kind}

# Undefined: int32 overflow in the s16 filter or NaN produced by f32 arithmetic
# (its bits are the host's default NaN, and converting it to an int is
# undefined). Unreproduced: a resampler that did not produce the expected count.
def finish(+stream: Stream, +plan: Plan) -> Outcome:
  Stream{+frames, +ok, +complete} = stream
  +mid = flat(frames)
  finish.checked(Bool.pick(U32, Bool.not(ok) || (U32.is_eq(Plan.mid(plan), 2) && any_nan(mid)), 1, Bool.pick(U32, Bool.not(complete), 2, 0)), mid, plan)

def pipeline.coefficients(found: Maybe<+List<U32>>, +values: +List<U32>, +plan: Plan) -> Outcome:
  match found:
    case None{}: Refused{2}
    case Some{+k}:
      Plan{+fin, +mid, _, +cin, +cout, _, _, +n, _, _, _} = plan
      finish(stages((cin >= cout : U32), k, split(U32.to_nat(n), U32.to_nat(cin), map.sample(values, (3 * fin + mid : U32))), plan), plan)

def pipeline.lowpass(apply: Bool, +plan: Plan) -> Maybe<+List<U32>>:
  match apply:
    case True{}:
      Plan{_, +mid, _, _, _, +rin, +rout, _, _, _, _} = plan
      L.coefficients(U32.is_eq(mid, 2), rin, rout)
    case False{}: Some{Nil{}}

# 0: run; else refused with that kind.
def pipeline.checked(kind: U32, +values: +List<U32>, +plan: Plan) -> Outcome:
  match kind:
    case 0: pipeline.coefficients(pipeline.lowpass(Plan.resample(plan), plan), values, plan)
    case _: Refused{kind}

# The temporary buffers of the chunked paths hold 4096 bytes: with fewer
# frames than one output frame can need (rin/rout + 1 when resampling, 1
# otherwise) a chunk ends the conversion early or never advances.
def starved(+plan: Plan) -> Bool:
  Plan{+fin, +mid, +fout, +cin, +cout, +rin, +rout, _, _, +resample, _} = plan
  +widest = U32.max(cin, cout)
  +cap = Bool.pick(U32, (widest > 4096 : U32), 0, (4096 / (Bool.pick(U32, U32.is_eq(mid, 1), 2, 4) * widest) : U32))
  +chunked = U32.is_ne(fin, mid) || U32.is_ne(fout, mid) || (resample && U32.is_ne(cin, cout))
  chunked && (cap < Bool.pick(U32, resample, ((rin / rout) + 1 : U32), 1) : U32)

def pipeline(+values: +List<U32>, +plan: Plan) -> Outcome:
  Plan{+fin, _, +fout, _, _, _, _, _, _, _, _} = plan
  pipeline.checked(Bool.pick(U32, starved(plan), 2, Bool.pick(U32, U32.is_eq(fin, 2) && U32.is_eq(fout, 1) && any_ambiguous16(values), 1, 0)), values, plan)

def direct.checked(refused: Bool, +values: +List<U32>, +fin: U32, +fout: U32, +n: U32) -> Outcome:
  match refused:
    case True{}: Refused{1}
    case False{}: Converted{n, map.encode(map.sample(values, (3 * fin + fout : U32)), U32.is_eq(fout, 1))}

def direct(+values: +List<U32>, +fin: U32, +fout: U32, +n: U32) -> Outcome:
  direct.checked(U32.is_eq(fin, 2) && U32.is_eq(fout, 1) && any_ambiguous16(values), values, fin, fout, n)

# 0: passthrough; 1: refused NaN input; 2: format only; 3: channel conversion and/or resampling.
def route(kind: U32, +data: +List<U32>, +plan: Plan) -> Outcome:
  match kind:
    case 0:
      Plan{_, _, _, _, _, _, _, +n, _, _, _} = plan
      Converted{n, data}
    case 1: Refused{1}
    case 2:
      Plan{+fin, _, +fout, _, _, _, _, +n, _, _, _} = plan
      direct(map.decode(data, U32.is_eq(fin, 1)), fin, fout, n)
    case _:
      Plan{+fin, _, _, _, _, _, _, _, _, _, _} = plan
      pipeline(map.decode(data, U32.is_eq(fin, 1)), plan)

def planned(+data: +List<U32>, +plan: Plan) -> Outcome:
  Plan{+fin, _, +fout, +cin, +cout, _, _, _, _, +resample, _} = plan
  +converting = resample || U32.is_ne(cin, cout)
  route(Bool.pick(U32, Bool.not(converting) && U32.is_eq(fin, fout), 0, Bool.pick(U32, U32.is_eq(fin, 2) && any_nan(data), 1, Bool.pick(U32, converting, 3, 2))), data, plan)

def mid(+fin: U32, +fout: U32) -> U32:
  Bool.pick(U32, U32.is_ne(fout, 0), fout, Bool.pick(U32, U32.is_ne(fin, 0), fin, 2))

def counted.checked(large: Bool, +data: +List<U32>, +plan: Plan) -> Outcome:
  match large:
    case True{}: Refused{2}
    case False{}: planned(data, plan)

def counted(found: Maybe<U32>, +data: +List<U32>, +fin: U32, +fout: U32, +cin: U32, +cout: U32, +rin: U32, +rout: U32, +n: U32, +resample: Bool, +fused: Bool) -> Outcome:
  match found:
    case None{}: Refused{2}
    case Some{+count}:
      counted.checked((count > 16777216 : U32) || (cout > (16777216 / count : U32) : U32), data,
        Plan{fin, mid(fin, fout), fout, cin, cout, rin, rout, n, count, resample, fused})

def reduced.checked(large: Bool, +data: +List<U32>, +fin: U32, +fout: U32, +cin: U32, +cout: U32, +rin: U32, +rout: U32, +n: U32, +resample: Bool, +fused: Bool) -> Outcome:
  match large:
    case True{}: Refused{2}
    case False{}: counted(Bool.pick(Maybe<U32>, resample, R.expected(n, rin, rout), Some{n}), data, fin, fout, cin, cout, rin, rout, n, resample, fused)

def reduced(+data: +List<U32>, +fin: U32, +fout: U32, +cin: U32, +cout: U32, +rate: U32, +orate: U32, +n: U32, +resample: Bool, +fused: Bool) -> Outcome:
  +g = Bool.pick(U32, resample, gcd(64n, rate, orate), 1)
  +rin = Bool.pick(U32, resample, (rate / g : U32), 1)
  +rout = Bool.pick(U32, resample, (orate / g : U32), 1)
  reduced.checked((rin >= 2147483648 : U32) || (rout >= 2147483648 : U32), data, fin, fout, cin, cout, rin, rout, n, resample, fused)

def entry(kind: U32, +data: +List<U32>, +n: U32, +rate: U32, +size: U32, +cin: U32, +orate: U32, +osize: U32, +cout: U32, +fused: Bool) -> Outcome:
  match kind:
    case 0: Refused{0}
    case 1: Unchanged{}
    case _: reduced(data, format(size), format(osize), cin, cout, rate, orate, n, U32.is_ne(rate, orate), fused)

def count(values: +List<U32>, +acc: U32) -> U32:
  match values:
    case Nil{}: acc
    case Con{_, rest}: count(rest, (acc + 1 : U32))

def sized(+size: U32) -> Bool:
  U32.is_eq(size, 8) || U32.is_eq(size, 16) || U32.is_eq(size, 32)

# WaveFormat's two ma_convert_frames calls on n frames of `size`-bit samples.
# Unchanged: ma_convert_frames returns 0 (no frames, zero channels, a zero
# rate when resampling). Refused: sample sizes other than 8, 16, 32
# (raylib reads or allocates with the wrong width), a sample list that does
# not hold n*cin samples (kind 0); undefined or alignment-dependent native
# results (kind 1); conversions Jonlib does not reproduce (kind 2).
def convert(+fused: Bool, +n: U32, +rate: U32, +size: U32, +cin: U32, +data: +List<U32>, +orate: U32, +osize: U32, +cout: U32) -> Outcome:
  +valid = sized(size) && sized(osize) && U32.is_eq(count(data, 0), (n * cin : U32)) && (U32.is_eq(cin, 0) || U32.is_eq(((n * cin) / Bool.pick(U32, U32.is_eq(cin, 0), 1, cin) : U32), n))
  +empty = U32.is_eq(n, 0) || U32.is_eq(cin, 0) || U32.is_eq(cout, 0) || (U32.is_ne(rate, orate) && (U32.is_eq(rate, 0) || U32.is_eq(orate, 0)))
  entry(Bool.pick(U32, Bool.not(valid), 0, Bool.pick(U32, empty, 1, 2)), data, n, rate, size, cin, orate, osize, cout, fused)
