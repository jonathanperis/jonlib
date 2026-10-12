# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of how raylib 6.0's raudio.c reads a static audio
# buffer for the device (ReadAudioBufferFramesInInternalFormat,
# ReadAudioBufferFramesInMixingFormat and the buffer loop of
# OnSendAudioDataToDevice, and SetAudioBufferPitch's rate change; raylib:
# zlib/libpng, Copyright (c) 2013-2025 Ramon Santamaria (@raysan5), see
# LICENSES/raylib.txt) through miniaudio v0.11.24's linear resampler as a
# stream with its first-order low-pass filter
# (ma_linear_resampler_process_pcm_frames_f32, ma_linear_resampler_set_rate
# and ma_lpf1_process_pcm_frame_f32; src/resampler.bend, src/lowpass.bend).
# miniaudio: David Reid, public domain or MIT No Attribution; see
# THIRD_PARTY_NOTICES.md and LICENSES/miniaudio.txt.
#
# The buffer is in the device's format: frames of two f32 samples (U32 bits)
# at 48000 Hz. Arithmetic is uncontracted binary32.
import Base
import ./resampler.bend as R
import ./lowpass.bend as L
import ./convert.bend as C

# -----------------------------------------------------------------------------
# Values the hosts' miniaudio builds do not treat alike inside the device
# callback (x86 builds flush subnormals to zero there, others do not) or whose
# bits depend on the host (NaN).

def odd(+word: U32) -> Bool:
  +exponent = (word .&. 2139095040 : U32)
  U32.is_ne((word .&. 8388607 : U32), 0) && (U32.is_eq(exponent, 0) || U32.is_eq(exponent, 2139095040))

def oddf(value: F32) -> Bool:
  odd(F32.bits(value))

# ma_lpf1_process_pcm_frame_f32: y = (1 - a)*x + a*r1, and y is the next r1.
def lpf1.sample(+a: U32, +x: U32, +r1: U32) -> U32:
  F32.bits((((1.0 - R.float(a)) * R.float(x)) + (R.float(a) * R.float(r1)) : F32))

def lpf1.sample.fine(+a: U32, +x: U32, +r1: U32) -> Bool:
  Bool.not(odd(a) || odd(x) || odd(r1) || oddf((1.0 - R.float(a) : F32)) || oddf(((1.0 - R.float(a)) * R.float(x) : F32)) || oddf((R.float(a) * R.float(r1) : F32)) || odd(lpf1.sample(a, x, r1)))

def Chan.r1(chan: R.Chan) -> U32:
  R.Chan{r1, _, _, _} = chan
  r1

def lpf1.join(+y: U32, rest: R.Filtered) -> R.Filtered:
  R.Filtered{frame, chans, ok} = rest
  R.Filtered{Con{y, frame}, Con{R.Chan{y, 0, 0, 0}, chans}, ok}

# A frame through the filter; each channel's register is the first of its
# resampler registers.
def lpf1(frame: +List<U32>, chans: +List<R.Chan>, +a: U32) -> R.Filtered:
  match frame chans:
    case Con{+x, xs} Con{+chan, cs}: lpf1.join(lpf1.sample(a, x, Chan.r1(chan)), lpf1(xs, cs, a))
    case _ _: R.Filtered{Nil{}, Nil{}, True{}}

def lpf1.if(apply: Bool, +frame: +List<U32>, +chans: +List<R.Chan>, +a: U32) -> R.Filtered:
  match apply:
    case True{}: lpf1(frame, chans, a)
    case False{}: R.Filtered{frame, chans, True{}}

def frame.fine(frame: +List<U32>, chans: +List<R.Chan>, +a: U32) -> Bool:
  match frame chans:
    case Con{+x, xs} Con{+chan, cs}: lpf1.sample.fine(a, x, Chan.r1(chan)) && frame.fine(xs, cs, a)
    case _ _: True{}

def lerp.fine(a: +List<U32>, b: +List<U32>, +t: F32) -> Bool:
  match a b:
    case Con{+x, xs} Con{+y, ys}:
      Bool.not(odd(x) || odd(y) || oddf((R.float(y) - R.float(x) : F32)) || oddf(((R.float(y) - R.float(x)) * t : F32)) || oddf((R.float(x) + ((R.float(y) - R.float(x)) * t) : F32))) && lerp.fine(xs, ys, t)
    case _ _: True{}

def plain.fine(frame: +List<U32>) -> Bool:
  match frame:
    case Nil{}: True{}
    case Con{+x, rest}: Bool.not(odd(x)) && plain.fine(rest)

# -----------------------------------------------------------------------------
# The resampler as a stream. `plain` is a rate of 1:1, where miniaudio does not
# filter; otherwise the input is filtered when downsampling and the output
# when upsampling, by the first-order filter of coefficient `a` (a data
# converter's resampler has a filter of order 1, not the order 4 of
# ma_convert_frames).

def load(+plain: Bool, +st: R.St, +frame: +List<U32>, +p: R.Params, +a: U32) -> R.St:
  R.load.filtered(lpf1.if(Bool.not(plain) && R.Params.down(p), frame, R.St.chans(st), a), st)

def load.fine(+plain: Bool, +st: R.St, +frame: +List<U32>, +p: R.Params, +a: U32) -> Bool:
  plain.fine(frame) && (plain || Bool.not(R.Params.down(p)) || frame.fine(frame, R.St.chans(st), a))

def produce(+plain: Bool, +st: R.St, +p: R.Params, +a: U32) -> R.Produced:
  R.produce.advance(lpf1.if(Bool.not(plain) && Bool.not(R.Params.down(p)), R.interpolate(True{}, st, R.Params.rout(p)), R.St.chans(st), a), st, p)

def fraction(+st: R.St, +rout: U32) -> F32:
  R.St{_, t_frac, _, _, _, _} = st
  (U32.to_f32(t_frac) / U32.to_f32(rout) : F32)

def St.x0(+st: R.St) -> +List<U32>:
  R.St{_, _, x0, _, _, _} = st
  x0

def St.x1(+st: R.St) -> +List<U32>:
  R.St{_, _, _, x1, _, _} = st
  x1

def produce.fine(+plain: Bool, +st: R.St, +p: R.Params, +a: U32) -> Bool:
  +t = fraction(st, R.Params.rout(p))
  Bool.not(oddf(t)) && lerp.fine(St.x0(st), St.x1(st), t) && (plain || R.Params.down(p) || frame.fine(R.interpolate(True{}, st, R.Params.rout(p)), R.St.chans(st), a))

# What ma_linear_resampler_process_pcm_frames_f32 did with an input: its
# state, the frames made so far (last first), the input it left, the number of
# frames it made, and whether every value was one the hosts agree on.
type Flow is Data:
  Flow{st: R.St, acc: +List<+List<U32>>, rest: +List<+List<U32>>, count: U32, fine: Bool}

# Phases as in the resampler: 1 loads an input frame that is due, 2 makes an
# output frame; it ends with `remaining` frames made or the input used up.
def flow(fuel: Nat, phase: U32, input: +List<+List<U32>>, +st: R.St, +acc: +List<+List<U32>>, +count: U32, +remaining: U32, +plain: Bool, +p: R.Params, +a: U32, +fine: Bool) -> Flow:
  match fuel:
    case 0n: Flow{st, acc, input, count, False{}}
    case 1n+k:
      match phase:
        case 1:
          match input:
            case Con{+frame, rest}:
              +loaded = load(plain, st, frame, p, a)
              flow(k, R.next_phase(loaded, remaining), rest, loaded, acc, count, remaining, plain, p, a, fine && load.fine(plain, st, frame, p, a))
            case Nil{}: Flow{st, acc, Nil{}, count, fine}
        case 2:
          +made = produce(plain, st, p, a)
          +next = R.Produced.st(made)
          flow(k, R.next_phase(next, (remaining - 1 : U32)), input, next, Con{R.Produced.frame(made), acc}, (count + 1 : U32), (remaining - 1 : U32), plain, p, a, fine && produce.fine(plain, st, p, a))
        case _: Flow{st, acc, input, count, fine}

# -----------------------------------------------------------------------------
# A buffer's place: its converter's output rate (the device's 48000 Hz until
# SetAudioBufferPitch changes it), how that rate is resampled (0: 1:1, no
# filter; 1: with the filter's coefficient; 2: not reproduced), its cursor,
# the resampler's state and raudio's residual input frames (at most 8).

type Head is Data:
  Head{rate: U32, mode: U32, coef: U32, cursor: U32, st: R.St, residual: +List<+List<U32>>}

def Head.new() -> Head:
  Head{48000, 0, 0, 0, R.start(2), Nil{}}

# The cursor back at the first frame (PlayAudioBuffer, and a buffer that
# stops); what the converter holds stays.
def Head.rewound(head: Head) -> Head:
  Head{rate, mode, coef, _, st, residual} = head
  Head{rate, mode, coef, 0, st, residual}

# ma_linear_resampler_adjust_timer_for_new_rate: the fraction of an input
# frame, counted in the old reduced output rate, in the new one (unsigned int
# arithmetic).
def retimed(st: R.St, +old: U32, +new: U32) -> R.St:
  R.St{+t_int, +t_frac, x0, x1, chans, ok} = st
  +frac = (((t_frac / old) * new) + (((t_frac % old) * new) / old) : U32)
  R.St{(t_int + (frac / new) : U32), (frac % new : U32), x0, x1, chans, ok}

def Head.filtered(found: Maybe<U32>, +rate: U32, +cursor: U32, +st: R.St, +residual: +List<+List<U32>>) -> Head:
  match found:
    case None{}: Head{rate, 2, 0, cursor, st, residual}
    case Some{+a}: Head{rate, 1, a, cursor, st, residual}

# 0: 1:1; 1: a reduced output rate of 2^31 and more; else the filter's
# coefficient, when it is certified.
def Head.rated(kind: U32, +rin: U32, +rout: U32, +rate: U32, +cursor: U32, +st: R.St, +residual: +List<+List<U32>>) -> Head:
  match kind:
    case 0: Head{rate, 0, 0, cursor, st, residual}
    case 1: Head{rate, 2, 0, cursor, st, residual}
    case _: Head.filtered(L.coefficient1(rin, rout), rate, cursor, st, residual)

# ma_data_converter_set_rate(48000, wanted) for a wanted rate that is not 0:
# the rates reduced by their divisor, the filter for them (its registers
# stay) and the timer in the new rate.
def Head.pitched(head: Head, +wanted: U32) -> Head:
  Head{+rate, _, _, cursor, +st, residual} = head
  +old = (rate / C.gcd(64n, 48000, rate) : U32)
  +g = C.gcd(64n, 48000, wanted)
  +rin = (48000 / g : U32)
  +rout = (wanted / g : U32)
  Head.rated(Bool.pick(U32, U32.is_eq(rin, rout), 0, Bool.pick(U32, (rout >= 2147483648 : U32), 1, 2)), rin, rout, wanted, cursor, retimed(st, old, rout), residual)

# -----------------------------------------------------------------------------
# ReadAudioBufferFramesInInternalFormat for a static buffer of `size` frames
# (not 0) asked for `est` frames: nothing when it is not playing, or when its
# cursor is past two halves of the buffer (size/2 frames each: the last frame
# of an odd size of 3 and more); else the frames left, at most `est`.
def read.count(+size: U32, +cursor: U32, +playing: Bool, +est: U32) -> U32:
  +half = U32.max(Bool.pick(U32, (size > 1 : U32), (size / 2 : U32), size), 1)
  Bool.pick(U32, Bool.not(playing) || ((cursor / half) > 1 : U32), 0, U32.min(est, (size - cursor : U32)))

# It stops the buffer when it gives its last frame.
def read.ends(+size: U32, +cursor: U32, +playing: Bool, +est: U32) -> Bool:
  +count = read.count(size, cursor, playing, est)
  (count > 0 : U32) && U32.is_eq(count, (size - cursor : U32))

def pairs(values: +List<U32>, acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match values:
    case Con{+l, Con{+r, rest}}: pairs(rest, Con{[l, r], acc})
    case _: List.reverse(&2, +List<U32>, acc)

def read.frames(+data: +List<U32>, +cursor: U32, +count: U32) -> +List<+List<U32>>:
  pairs(List.take(&2, U32, List.drop(&2, U32, data, U32.to_nat((2 * cursor : U32))), U32.to_nat((2 * count : U32))), Nil{})

# raudio's guess of the input frames `want` output frames need:
# (unsigned int)(((float)48000/rate)*want), at least 1 and at most the 512
# frames of its input buffer.
def estimate(+rate: U32, +want: U32) -> U32:
  U32.min(512, U32.max(F32.to_u32(((U32.to_f32(48000) / U32.to_f32(rate)) * U32.to_f32(want) : F32)), 1))

# A buffer's turn in a callback: the frames it still owes (`need`), the run
# of at most 512 it is in (`now`) and how many of it are made (`total`), its
# cursor and whether it plays, the converter, the residual, the frames made
# for this callback (last first), whether the hosts agree, and whether the
# run ended early (the buffer gave fewer frames than asked).
type S is Data:
  S{need: U32, now: U32, total: U32, cursor: U32, playing: Bool, st: R.St, residual: +List<+List<U32>>, acc: +List<+List<U32>>, fine: Bool, broke: Bool}

def S.over(+s: S) -> Bool:
  S{_, now, total, _, _, _, _, _, _, broke} = s
  broke || (total >= now : U32)

def S.finished(+s: S) -> Bool:
  S{need, _, _, _, playing, _, _, _, _, _} = s
  U32.is_eq(need, 0) || Bool.not(playing)

def step.residual(flow: Flow, +need: U32, +now: U32, +total: U32, +cursor: U32, +playing: Bool) -> S:
  Flow{st, acc, rest, +count, fine} = flow
  S{need, now, (total + count : U32), cursor, playing, st, rest, acc, fine, False{}}

# Input the converter did not take stays as the residual: 8 frames at most,
# the rest is lost.
def step.read(flow: Flow, +need: U32, +now: U32, +total: U32, +cursor: U32, +playing: Bool, +short: Bool) -> S:
  Flow{st, acc, rest, +count, fine} = flow
  S{need, now, (total + count : U32), cursor, playing, st, List.take(&2, +List<U32>, rest, 8n), acc, fine, short}

# One pass of ReadAudioBufferFramesInMixingFormat's loop: the residual goes
# through the converter first; without one, the estimated input is read from
# the buffer, and a short read ends the run.
def step(s: S, +size: U32, +data: +List<U32>, +rate: U32, +plain: Bool, +p: R.Params, +a: U32) -> S:
  S{+need, +now, +total, +cursor, +playing, +st, residual, +acc, +fine, _} = s
  match residual:
    case Nil{}:
      +est = estimate(rate, (now - total : U32))
      +count = read.count(size, cursor, playing, est)
      +ends = read.ends(size, cursor, playing, est)
      step.read(flow(U32.to_nat((count + (now - total) + 2 : U32)), R.next_phase(st, (now - total : U32)), read.frames(data, cursor, count), st, acc, 0, (now - total : U32), plain, p, a, fine),
        need, now, total, Bool.pick(U32, ends, 0, (cursor + count : U32)), playing && Bool.not(ends), (count < est : U32))
    case Con{+first, +more}:
      step.residual(flow(U32.to_nat((10 + (now - total) : U32)), R.next_phase(st, (now - total : U32)), Con{first, more}, st, acc, 0, (now - total : U32), plain, p, a, fine), need, now, total, cursor, playing)

def run(fuel: Nat, done: Bool, +s: S, +size: U32, +data: +List<U32>, +rate: U32, +plain: Bool, +p: R.Params, +a: U32) -> S:
  match fuel:
    case 0n: s
    case 1n+k:
      match done:
        case True{}: s
        case False{}:
          +next = step(s, size, data, rate, plain, p, a)
          run(k, S.over(next), next, size, data, rate, plain, p, a)

def begin(s: S) -> S:
  S{+need, _, _, cursor, playing, st, residual, acc, fine, _} = s
  S{need, U32.min(need, 512), 0, cursor, playing, st, residual, acc, fine, False{}}

# After a run in OnSendAudioDataToDevice: a buffer that stopped owes nothing
# more; one that still plays but gave fewer frames than the run asked for is
# stopped, back at its first frame.
def after(s: S) -> S:
  S{+need, +now, +total, +cursor, +playing, st, residual, acc, fine, broke} = s
  +short = playing && (total < now : U32)
  S{Bool.pick(U32, playing && Bool.not(short), (need - total : U32), 0), now, total, Bool.pick(U32, short, 0, cursor), playing && Bool.not(short), st, residual, acc, fine, broke}

def runs(fuel: Nat, done: Bool, +s: S, +size: U32, +data: +List<U32>, +rate: U32, +plain: Bool, +p: R.Params, +a: U32) -> S:
  match fuel:
    case 0n: s
    case 1n+k:
      match done:
        case True{}: s
        case False{}:
          +next = after(run(U32.to_nat(2048), False{}, begin(s), size, data, rate, plain, p, a))
          runs(k, S.finished(next), next, size, data, rate, plain, p, a)

# The buffer after a callback, whether it still plays, the frames it gave (in
# order) and whether the hosts agree on them.
type Turn is Data:
  Turn{head: Head, playing: Bool, made: +List<+List<U32>>, fine: Bool}

def turn.done(s: S, +rate: U32, +mode: U32, +coef: U32) -> Turn:
  S{need, _, _, cursor, playing, st, residual, acc, fine, _} = s
  Turn{Head{rate, mode, coef, cursor, st, residual}, playing, List.reverse(&2, +List<U32>, acc), fine && U32.is_eq(need, 0)}

# A playing buffer of `size` frames in a callback of n frames. Not fine: a
# rate Jonlib does not resample (mode 2) and a buffer without frames (raudio
# divides by its size).
def turn(head: Head, +size: U32, +data: +List<U32>, +n: U32) -> Turn:
  Head{+rate, +mode, +coef, cursor, st, residual} = head
  +g = C.gcd(64n, 48000, rate)
  turn.done(runs(U32.to_nat((n + 2 : U32)), False{}, S{n, 0, 0, cursor, True{}, st, residual, Nil{}, U32.is_ne(mode, 2) && (size > 0 : U32), False{}},
    size, data, rate, U32.is_eq(mode, 0), R.params(True{}, False{}, Nil{}, (48000 / g : U32), (rate / g : U32)), coef), rate, mode, coef)
