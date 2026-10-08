# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of miniaudio v0.11.24's linear resampler
# (ma_linear_resampler: rate reduction, time advance, s16 and f32
# interpolation, ma_linear_resampler_get_expected_output_frame_count) and its
# order-4 low-pass filter (ma_lpf of two ma_lpf2/ma_biquad sections in direct
# form 2 transposed, s16 in 2.14 fixed point), as raylib 6.0 vendors it in
# src/external/miniaudio.h. miniaudio: David Reid, public domain or MIT No
# Attribution; see THIRD_PARTY_NOTICES.md and LICENSES/miniaudio.txt.
#
# Samples are U32 words: s16 values as sign-extended two's-complement ints,
# f32 values as their bits. C ints are U32 two's-complement words; signed
# overflow in the fixed-point filter (undefined in C) clears the run's ok flag.
import Base
import ./fma.bend as Fma

# -----------------------------------------------------------------------------
# Two's-complement helpers

def negative(+x: U32) -> Bool:
  (x >= 2147483648 : U32)

def asr(+x: U32, +n: Nat) -> U32:
  Bool.pick(U32, negative(x), (((x .^. 4294967295) >> n) .^. 4294967295 : U32), (x >> n : U32))

# The low 16 bits as a sign-extended int16 ((ma_int16) cast).
def short(+x: U32) -> U32:
  Bool.pick(U32, ((x .&. 65535) >= 32768 : U32), ((x .&. 65535) .|. 4294901760 : U32), (x .&. 65535 : U32))

def less(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) < (b .^. 2147483648) : U32)

def clamp16(+v: U32) -> U32:
  Bool.pick(U32, less(v, 4294934528), 4294934528, Bool.pick(U32, less(32767, v), 32767, v))

def float(word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# int32 a + b, a - b and a * b, with whether C's signed result is defined.
def add_ok(+a: U32, +b: U32) -> Bool:
  +s = (a + b : U32)
  Bool.not(negative(((a .^. s) .&. (b .^. s) : U32)))

def sub_ok(+a: U32, +b: U32) -> Bool:
  +d = (a - b : U32)
  Bool.not(negative(((a .^. b) .&. (a .^. d) : U32)))

def magnitude(+x: U32) -> U32:
  Bool.pick(U32, negative(x), (0 - x : U32), x)

def mul_ok(+a: U32, +b: U32) -> Bool:
  +limit = Bool.pick(U32, negative((a .^. b : U32)), 2147483648, 2147483647)
  U32.is_eq(magnitude(a), 0) || (magnitude(b) <= (limit / magnitude(a)) : U32)

def at.go(xs: +List<U32>, +i: U32) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+x, rest}: Bool.pick(U32, U32.is_eq(i, 0), x, at.go(rest, (i - 1 : U32)))

def at(+xs: +List<U32>, +i: U32) -> U32:
  at.go(xs, i)

# -----------------------------------------------------------------------------
# Expected output frames: ceil(n * rout / rin) for the reduced rates, which is
# what ma_linear_resampler_get_expected_output_frame_count gives from the
# initial state (one whole input frame, no fraction) without 64-bit overflow.

type Long is Data:
  Long{high: U32, low: U32}

# a * b for a, b < 2^32, from 16-bit halves.
def Long.product(+a: U32, +b: U32) -> Long:
  +a1 = (a >> 16n : U32)
  +a0 = (a .&. 65535 : U32)
  +b1 = (b >> 16n : U32)
  +b0 = (b .&. 65535 : U32)
  +middle = (a1 * b0 + a0 * b1 : U32)
  +carry = Bool.to_u32((middle < (a1 * b0) : U32))
  +low0 = (a0 * b0 : U32)
  +low = (low0 + (middle << 16n) : U32)
  Long{(a1 * b1 + (middle >> 16n) + (carry << 16n) + Bool.to_u32((low < low0 : U32)) : U32), low}

type Division is Data:
  Division{high: U32, low: U32, rem: U32}

def Long.bit(+value: Long, +i: U32) -> U32:
  Long{+high, +low} = value
  Bool.pick(U32, (i >= 32 : U32), ((high >> U32.to_nat((i - 32 : U32))) .&. 1 : U32), ((low >> U32.to_nat(U32.min(i, 31))) .&. 1 : U32))

# Bit-serial long division by 0 < d < 2^31 (the remainder stays below 2^32).
def Long.divide.go(n: Nat, +value: Long, +d: U32, +i: U32, +state: Division) -> Division:
  match n:
    case 0n: state
    case 1n+k:
      Division{+qh, +ql, +rem} = state
      +r = ((rem << 1n) .|. Long.bit(value, i) : U32)
      +take = (r >= d : U32)
      +q = Bool.to_u32(take)
      Long.divide.go(k, value, d, (i - 1 : U32), Division{((qh << 1n) .|. (ql >> 31n) : U32), ((ql << 1n) .|. q : U32), Bool.pick(U32, take, (r - d : U32), r)})

# None when the count reaches 2^32.
def expected.count(+division: Division) -> Maybe<U32>:
  Division{+qh, +ql, +rem} = division
  +up = U32.is_ne(rem, 0)
  Bool.pick(Maybe<U32>, U32.is_ne(qh, 0) || (up && U32.is_eq(ql, 4294967295)), None{}, Some{(ql + Bool.to_u32(up) : U32)})

def expected(+frames: U32, +rin: U32, +rout: U32) -> Maybe<U32>:
  expected.count(Long.divide.go(64n, Long.product(frames, rout), rin, 63, Division{0, 0, 0}))

# -----------------------------------------------------------------------------
# Low-pass filter: two biquad sections per channel, direct form 2 transposed.

type Coefs is Data:
  Coefs{b0: U32, b1: U32, b2: U32, a1: U32, a2: U32}

type Chan is Data:
  Chan{r1a: U32, r2a: U32, r1b: U32, r2b: U32}

type Step is Data:
  Step{y: U32, r1: U32, r2: U32, ok: Bool}

def Step.y(+step: Step) -> U32:
  Step{y, _, _, _} = step
  y

def Step.r1(+step: Step) -> U32:
  Step{_, r1, _, _} = step
  r1

def Step.r2(+step: Step) -> U32:
  Step{_, _, r2, _} = step
  r2

def Step.ok(+step: Step) -> Bool:
  Step{_, _, _, ok} = step
  ok

# f32: y = b0*x + r1; r1 = b1*x - a1*y + r2; r2 = b2*x - a2*y. Compiled with
# contraction (clang -ffp-contract=on) each statement's leading product is
# fused: fma(b0, x, r1), fma(b1, x, -(a1*y)) + r2 and fma(b2, x, -(a2*y)).
def biquad.y(fused: Bool, +b0: F32, +x: F32, +r1: F32) -> F32:
  match fused:
    case True{}: Fma.multiply_add(b0, x, r1)
    case False{}: ((b0 * x) + r1 : F32)

def biquad.r1(fused: Bool, +b1: F32, +x: F32, +ay: F32, +r2: F32) -> F32:
  match fused:
    case True{}: (Fma.multiply_add(b1, x, F32.neg(ay)) + r2 : F32)
    case False{}: (((b1 * x) - ay) + r2 : F32)

def biquad.r2(fused: Bool, +b2: F32, +x: F32, +by: F32) -> F32:
  match fused:
    case True{}: Fma.multiply_add(b2, x, F32.neg(by))
    case False{}: ((b2 * x) - by : F32)

def biquad.f32(+fused: Bool, +k: Coefs, +x: U32, +r1: U32, +r2: U32) -> Step:
  Coefs{+b0, +b1, +b2, +a1, +a2} = k
  +y = biquad.y(fused, float(b0), float(x), float(r1))
  Step{F32.bits(y), F32.bits(biquad.r1(fused, float(b1), float(x), (float(a1) * y : F32), float(r2))),
    F32.bits(biquad.r2(fused, float(b2), float(x), (float(a2) * y : F32))), True{}}

# s16: y = (b0*x + r1) >> 14; r1 = b1*x - a1*y + r2; r2 = b2*x - a2*y in
# int32, every intermediate checked for overflow.
def biquad.s16(+k: Coefs, +x: U32, +r1: U32, +r2: U32) -> Step:
  Coefs{+b0, +b1, +b2, +a1, +a2} = k
  +p0 = (b0 * x : U32)
  +s0 = (p0 + r1 : U32)
  +y = asr(s0, 14n)
  +p1 = (b1 * x : U32)
  +q1 = (a1 * y : U32)
  +d1 = (p1 - q1 : U32)
  +p2 = (b2 * x : U32)
  +q2 = (a2 * y : U32)
  +ok = mul_ok(b0, x) && add_ok(p0, r1) && mul_ok(b1, x) && mul_ok(a1, y) && sub_ok(p1, q1) && add_ok(d1, r2) && mul_ok(b2, x) && mul_ok(a2, y) && sub_ok(p2, q2)
  Step{y, (d1 + r2 : U32), (p2 - q2 : U32), ok}

def biquad(f32: Bool, +fused: Bool, +k: Coefs, +x: U32, +r1: U32, +r2: U32) -> Step:
  match f32:
    case True{}: biquad.f32(fused, k, x, r1, r2)
    case False{}: biquad.s16(k, x, r1, r2)

# The stage output fed forward: s16 sections store their output clamped.
def stored(+f32: Bool, +y: U32) -> U32:
  Bool.pick(U32, f32, y, clamp16(y))

type Filtered is Data:
  Filtered{frame: +List<U32>, chans: +List<Chan>, ok: Bool}

def Filtered.frame(+f: Filtered) -> +List<U32>:
  Filtered{frame, _, _} = f
  frame

def Filtered.chans(+f: Filtered) -> +List<Chan>:
  Filtered{_, chans, _} = f
  chans

def Filtered.ok(+f: Filtered) -> Bool:
  Filtered{_, _, ok} = f
  ok

type Lpf is Data:
  Lpf{f32: Bool, fused: Bool, first: Coefs, second: Coefs}

type Steps is Data:
  Steps{a: Step, b: Step}

def channel.step(+lpf: Lpf, +x: U32, +chan: Chan) -> Steps:
  Lpf{+f32, +fused, +first, +second} = lpf
  Chan{+r1a, +r2a, +r1b, +r2b} = chan
  +a = biquad(f32, fused, first, x, r1a, r2a)
  Steps{a, biquad(f32, fused, second, stored(f32, Step.y(a)), r1b, r2b)}

def channel.join(+f32: Bool, +steps: Steps, +rest: Filtered) -> Filtered:
  Steps{+a, +b} = steps
  Filtered{Con{stored(f32, Step.y(b)), Filtered.frame(rest)}, Con{Chan{Step.r1(a), Step.r2(a), Step.r1(b), Step.r2(b)}, Filtered.chans(rest)},
    Step.ok(a) && Step.ok(b) && Filtered.ok(rest)}

def Lpf.f32(+lpf: Lpf) -> Bool:
  Lpf{f32, _, _, _} = lpf
  f32

# ma_lpf_process_pcm_frame: each channel through both sections.
def filter(frame: +List<U32>, +chans: +List<Chan>, +lpf: Lpf) -> Filtered:
  match frame chans:
    case Con{+x, xs} Con{+chan, cs}: channel.join(Lpf.f32(lpf), channel.step(lpf, x, chan), filter(xs, cs, lpf))
    case _ _: Filtered{Nil{}, Nil{}, True{}}

def chans.zero(n: Nat, acc: +List<Chan>) -> +List<Chan>:
  match n:
    case 0n: acc
    case 1n+k: chans.zero(k, Con{Chan{0, 0, 0, 0}, acc})

def zeros(n: Nat, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: zeros(k, Con{0, acc})

# -----------------------------------------------------------------------------
# The resampler: from the initial state (one input frame due, no fraction),
# each output frame first loads (and, downsampling, filters) the whole input
# frames due, then interpolates x0..x1 by tFrac/rout (and, upsampling, filters
# the result), then advances time by rin/rout.

type St is Data:
  St{t_int: U32, t_frac: U32, x0: +List<U32>, x1: +List<U32>, chans: +List<Chan>, ok: Bool}

type Params is Data:
  Params{lpf: Lpf, rout: U32, adv_int: U32, adv_frac: U32, down: Bool}

def St.t_int(+st: St) -> U32:
  St{t_int, _, _, _, _, _} = st
  t_int

def St.ok(+st: St) -> Bool:
  St{_, _, _, _, _, ok} = st
  ok

def filter.if(apply: Bool, +frame: +List<U32>, +chans: +List<Chan>, +lpf: Lpf) -> Filtered:
  match apply:
    case True{}: filter(frame, chans, lpf)
    case False{}: Filtered{frame, chans, True{}}

def load.filtered(+f: Filtered, +st: St) -> St:
  St{+t_int, +t_frac, _, +x1, _, +ok} = st
  St{(t_int - 1 : U32), t_frac, x1, Filtered.frame(f), Filtered.chans(f), ok && Filtered.ok(f)}

def St.chans(+st: St) -> +List<Chan>:
  St{_, _, _, _, chans, _} = st
  chans

def Params.lpf(+p: Params) -> Lpf:
  Params{lpf, _, _, _, _} = p
  lpf

def Params.down(+p: Params) -> Bool:
  Params{_, _, _, _, down} = p
  down

def load(+st: St, +frame: +List<U32>, +p: Params) -> St:
  load.filtered(filter.if(Params.down(p), frame, St.chans(st), Params.lpf(p)), st)

def mix.f32(a: +List<U32>, b: +List<U32>, +t: F32) -> +List<U32>:
  match a b:
    case Con{+x, xs} Con{+y, ys}: Con{F32.bits((float(x) + ((float(y) - float(x)) * t) : F32)), mix.f32(xs, ys, t)}
    case _ _: Nil{}

def mix.s16(a: +List<U32>, b: +List<U32>, +t: U32) -> +List<U32>:
  match a b:
    case Con{+x, xs} Con{+y, ys}: Con{short(asr((x * (4096 - t) + y * t : U32), 12n)), mix.s16(xs, ys, t)}
    case _ _: Nil{}

# ma_linear_resampler_interpolate_frame_{f32,s16}.
def interpolate(+f32: Bool, +st: St, +rout: U32) -> +List<U32>:
  St{_, +t_frac, +x0, +x1, _, _} = st
  Bool.pick(+List<U32>, f32, mix.f32(x0, x1, (U32.to_f32(t_frac) / U32.to_f32(rout) : F32)), mix.s16(x0, x1, (((t_frac << 12n) : U32) / rout : U32)))

type Produced is Data:
  Produced{st: St, frame: +List<U32>}

def produce.advance(+f: Filtered, +st: St, +p: Params) -> Produced:
  St{+t_int, +t_frac, +x0, +x1, _, +ok} = st
  Params{_, +rout, +adv_int, +adv_frac, _} = p
  +frac = (t_frac + adv_frac : U32)
  +wrap = (frac >= rout : U32)
  Produced{St{(t_int + adv_int + Bool.to_u32(wrap) : U32), Bool.pick(U32, wrap, (frac - rout : U32), frac), x0, x1, Filtered.chans(f), ok && Filtered.ok(f)}, Filtered.frame(f)}

def Params.rout(+p: Params) -> U32:
  Params{_, rout, _, _, _} = p
  rout

def produce(+st: St, +p: Params) -> Produced:
  +lpf = Params.lpf(p)
  produce.advance(filter.if(Bool.not(Params.down(p)), interpolate(Lpf.f32(lpf), st, Params.rout(p)), St.chans(st), lpf), st, p)

def Produced.st(+pr: Produced) -> St:
  Produced{st, _} = pr
  st

def Produced.frame(+pr: Produced) -> +List<U32>:
  Produced{_, frame} = pr
  frame

# 0: done; 1: load an input frame; 2: produce an output frame.
def next_phase(+st: St, +remaining: U32) -> U32:
  Bool.pick(U32, U32.is_eq(remaining, 0), 0, Bool.pick(U32, U32.is_eq(St.t_int(st), 0), 2, 1))

type Run is Data:
  Run{frames: +List<+List<U32>>, produced: U32, ok: Bool}

def run(fuel: Nat, phase: U32, frames: +List<+List<U32>>, +st: St, +acc: +List<+List<U32>>, +produced: U32, +remaining: U32, +p: Params) -> Run:
  match fuel:
    case 0n: Run{List.reverse(&2, +List<U32>, acc), produced, St.ok(st)}
    case 1n+k:
      match phase:
        case 1:
          match frames:
            case Con{frame, rest}:
              +loaded = load(st, frame, p)
              run(k, next_phase(loaded, remaining), rest, loaded, acc, produced, remaining, p)
            case Nil{}: Run{List.reverse(&2, +List<U32>, acc), produced, St.ok(st)}
        case 2:
          +made = produce(st, p)
          +next = Produced.st(made)
          run(k, next_phase(next, (remaining - 1 : U32)), frames, next, Con{Produced.frame(made), acc}, (produced + 1 : U32), (remaining - 1 : U32), p)
        case _: Run{List.reverse(&2, +List<U32>, acc), produced, St.ok(st)}

# The resampled frames of `channels` channels (n input frames, `count`
# expected output frames) for reduced rates rin != rout and the filter's ten
# coefficients (binary32 words or 2.14 ints).
def params(+f32: Bool, +fused: Bool, +k: +List<U32>, +rin: U32, +rout: U32) -> Params:
  Params{Lpf{f32, fused, Coefs{at(k, 0), at(k, 1), at(k, 2), at(k, 3), at(k, 4)}, Coefs{at(k, 5), at(k, 6), at(k, 7), at(k, 8), at(k, 9)}},
    rout, (rin / rout : U32), (rin % rout : U32), (rin > rout : U32)}

def start(+channels: U32) -> St:
  St{1, 0, zeros(U32.to_nat(channels), Nil{}), zeros(U32.to_nat(channels), Nil{}), chans.zero(U32.to_nat(channels), Nil{}), True{}}

def resample(+f32: Bool, +fused: Bool, +k: +List<U32>, +channels: U32, +rin: U32, +rout: U32, +n: U32, +count: U32, frames: +List<+List<U32>>) -> Run:
  run(U32.to_nat((n + count + 2 : U32)), 1, frames, start(channels), Nil{}, 0, count, params(f32, fused, k, rin, rout))
