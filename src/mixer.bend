# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of how raylib 6.0's raudio.c reads an audio buffer
# for the device (ReadAudioBufferFramesInInternalFormat,
# ReadAudioBufferFramesInMixingFormat and the buffer loop of
# OnSendAudioDataToDevice, SetAudioBufferPitch's rate change and
# UpdateAudioStreamInLockedState; raylib: zlib/libpng, Copyright (c)
# 2013-2025 Ramon Santamaria (@raysan5), see LICENSES/raylib.txt) through
# miniaudio v0.11.24's data converter: its linear resampler as a stream with
# its first-order low-pass filter, and for an audio stream its sample and
# channel conversions and its passes (ma_data_converter_process_pcm_frames,
# ma_linear_resampler_process_pcm_frames_f32, ma_linear_resampler_set_rate,
# ma_linear_resampler_get_required_input_frame_count and
# ma_lpf1_process_pcm_frame_f32; src/resampler.bend, src/lowpass.bend,
# src/convert.bend).
# miniaudio: David Reid, public domain or MIT No Attribution; see
# THIRD_PARTY_NOTICES.md and LICENSES/miniaudio.txt.
#
# A sound's buffer is in the device's format: frames of two f32 samples (U32
# bits) at 48000 Hz; a stream's is in its own. Arithmetic is uncontracted
# binary32, with x86-64's denormal handling inside the callback (below).
import Base
import ./resampler.bend as R
import ./lowpass.bend as L
import ./convert.bend as C

# -----------------------------------------------------------------------------
# miniaudio runs the device callback with denormals disabled
# (ma_device_disable_denormals): on x86 with SSE2, the reference here, that is
# MXCSR's denormals-are-zero and flush-to-zero. Every operation of the
# callback takes a subnormal operand for a zero of its sign and gives a zero
# for a result that would be subnormal. (Other hosts keep subnormals: not
# ported.) A NaN's bits are the host's: a callback that makes one is refused.

def nan(+word: U32) -> Bool:
  U32.is_ne((word .&. 8388607 : U32), 0) && U32.is_eq((word .&. 2139095040 : U32), 2139095040)

def nanf(value: F32) -> Bool:
  nan(F32.bits(value))

def any.nan(values: +List<U32>, +found: Bool) -> Bool:
  match values:
    case Nil{}: found
    case Con{+v, rest}: any.nan(rest, found || nan(v))

# A subnormal as the zero of its sign.
def zero.word(+word: U32) -> U32:
  Bool.pick(U32, U32.is_ne((word .&. 8388607 : U32), 0) && U32.is_eq((word .&. 2139095040 : U32), 0), (word .&. 2147483648 : U32), word)

def zero(value: F32) -> F32:
  R.float(zero.word(F32.bits(value)))

def fadd(x: F32, y: F32) -> F32:
  zero((zero(x) + zero(y) : F32))

def fsub(x: F32, y: F32) -> F32:
  zero((zero(x) - zero(y) : F32))

def fmul(x: F32, y: F32) -> F32:
  zero((zero(x) * zero(y) : F32))

def fdiv(x: F32, y: F32) -> F32:
  zero((zero(x) / zero(y) : F32))

# ma_lpf1_process_pcm_frame_f32: y = (1 - a)*x + a*r1, and y is the next r1.
def lpf1.sample(+a: U32, +x: U32, +r1: U32) -> U32:
  F32.bits(fadd(fmul(fsub(1.0, R.float(a)), R.float(x)), fmul(R.float(a), R.float(r1))))

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

# ma_linear_resampler_interpolate_frame_f32: x0 + (x1 - x0)*t for each channel.
def lerp(a: +List<U32>, b: +List<U32>, +t: F32) -> +List<U32>:
  match a b:
    case Con{+x, xs} Con{+y, ys}: Con{F32.bits(fadd(R.float(x), fmul(fsub(R.float(y), R.float(x)), t))), lerp(xs, ys, t)}
    case _ _: Nil{}

# -----------------------------------------------------------------------------
# The resampler as a stream. `plain` is a rate of 1:1, where miniaudio does not
# filter; otherwise the input is filtered when downsampling and the output
# when upsampling, by the first-order filter of coefficient `a` (a data
# converter's resampler has a filter of order 1, not the order 4 of
# ma_convert_frames).

def load(+plain: Bool, +st: R.St, +frame: +List<U32>, +p: R.Params, +a: U32) -> R.St:
  R.load.filtered(lpf1.if(Bool.not(plain) && R.Params.down(p), frame, R.St.chans(st), a), st)

def St.x0(+st: R.St) -> +List<U32>:
  R.St{_, _, x0, _, _, _} = st
  x0

def St.x1(+st: R.St) -> +List<U32>:
  R.St{_, _, _, x1, _, _} = st
  x1

def fraction(+st: R.St, +rout: U32) -> F32:
  R.St{_, t_frac, _, _, _, _} = st
  fdiv(U32.to_f32(t_frac), U32.to_f32(rout))

def produce(+plain: Bool, +st: R.St, +p: R.Params, +a: U32) -> R.Produced:
  R.produce.advance(lpf1.if(Bool.not(plain) && Bool.not(R.Params.down(p)), lerp(St.x0(st), St.x1(st), fraction(st, R.Params.rout(p))), R.St.chans(st), a), st, p)

# No NaN in what a step keeps or gives: the frame the resampler holds last.
def held.fine(+st: R.St) -> Bool:
  Bool.not(any.nan(St.x1(st), False{}))

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
              flow(k, R.next_phase(loaded, remaining), rest, loaded, acc, count, remaining, plain, p, a, fine && held.fine(loaded))
            case Nil{}: Flow{st, acc, Nil{}, count, fine}
        case 2:
          +made = produce(plain, st, p, a)
          +next = R.Produced.st(made)
          flow(k, R.next_phase(next, (remaining - 1 : U32)), input, next, Con{R.Produced.frame(made), acc}, (count + 1 : U32), (remaining - 1 : U32), plain, p, a, fine && Bool.not(any.nan(R.Produced.frame(made), False{})))
        case _: Flow{st, acc, input, count, fine}

# -----------------------------------------------------------------------------
# What a buffer plays: a sound's frames in the device format, or an audio
# stream's two halves in the stream's own format (`size` bits a sample,
# `channels` channels), each half marked once the device has read it through
# (isSubBufferProcessed).
type Feed is Data:
  HeadStatic{}
  HeadStream{size: U32, channels: U32, first: Bool, second: Bool}

def Feed.static(kind: Feed) -> Bool:
  match kind:
    case HeadStatic{}: True{}
    case HeadStream{_, _, _, _}: False{}

# PlayAudioBuffer and a stop mark both halves processed.
def Feed.fresh(kind: Feed) -> Feed:
  match kind:
    case HeadStatic{}: HeadStatic{}
    case HeadStream{size, channels, _, _}: HeadStream{size, channels, True{}, True{}}

# A buffer's place: its converter's input rate (48000 Hz for a sound, a
# stream's own) and output rate (the device's 48000 Hz until
# SetAudioBufferPitch changes it), how those rates are resampled (0: 1:1, no
# filter; 1: with the filter's coefficient; 2: not reproduced), its cursor,
# the resampler's state, raudio's residual input frames (at most 8) and what
# it plays.

type Head is Data:
  Head{source: U32, rate: U32, mode: U32, coef: U32, cursor: U32, st: R.St, residual: +List<+List<U32>>, kind: Feed}

def Head.new() -> Head:
  Head{48000, 48000, 0, 0, 0, R.start(2), Nil{}, HeadStatic{}}

# The cursor back at the first frame (PlayAudioBuffer, and a buffer that
# stops); what the converter holds stays.
def Head.rewound(head: Head) -> Head:
  Head{source, rate, mode, coef, _, st, residual, kind} = head
  Head{source, rate, mode, coef, 0, st, residual, Feed.fresh(kind)}

# ma_linear_resampler_adjust_timer_for_new_rate: the fraction of an input
# frame, counted in the old reduced output rate, in the new one (unsigned int
# arithmetic).
def retimed(st: R.St, +old: U32, +new: U32) -> R.St:
  R.St{+t_int, +t_frac, x0, x1, chans, ok} = st
  +frac = (((t_frac / old) * new) + (((t_frac % old) * new) / old) : U32)
  R.St{(t_int + (frac / new) : U32), (frac % new : U32), x0, x1, chans, ok}

def Head.filtered(found: Maybe<U32>, +source: U32, +rate: U32, +cursor: U32, +st: R.St, +residual: +List<+List<U32>>, +kind: Feed) -> Head:
  match found:
    case None{}: Head{source, rate, 2, 0, cursor, st, residual, kind}
    case Some{+a}: Head{source, rate, 1, a, cursor, st, residual, kind}

# 0: 1:1; 1: a reduced rate of 2^31 and more; else the filter's coefficient,
# when it is certified.
def Head.rated(mode: U32, +rin: U32, +rout: U32, +source: U32, +rate: U32, +cursor: U32, +st: R.St, +residual: +List<+List<U32>>, +kind: Feed) -> Head:
  match mode:
    case 0: Head{source, rate, 0, 0, cursor, st, residual, kind}
    case 1: Head{source, rate, 2, 0, cursor, st, residual, kind}
    case _: Head.filtered(L.coefficient1(rin, rout), source, rate, cursor, st, residual, kind)

def rating(+rin: U32, +rout: U32) -> U32:
  Bool.pick(U32, U32.is_eq(rin, rout), 0, Bool.pick(U32, (rin >= 2147483648 : U32) || (rout >= 2147483648 : U32), 1, 2))

# ma_data_converter_set_rate(source, wanted) for a wanted rate that is not 0:
# the rates reduced by their divisor, the filter for them (its registers
# stay) and the timer in the new rate.
def Head.pitched(head: Head, +wanted: U32) -> Head:
  Head{+source, +rate, _, _, cursor, +st, residual, kind} = head
  +old = (rate / C.gcd(64n, source, rate) : U32)
  +g = C.gcd(64n, source, wanted)
  Head.rated(rating((source / g : U32), (wanted / g : U32)), (source / g : U32), (wanted / g : U32), source, wanted, cursor, retimed(st, old, (wanted / g : U32)), residual, kind)

# An audio stream's converter, from its rate (not 0) to the device's: the
# resampler runs on the stream's channels, two at most (miniaudio converts
# the channels first when there are more), and both halves are processed.
def Head.stream(+source: U32, +size: U32, +channels: U32) -> Head:
  +g = C.gcd(64n, source, 48000)
  Head.rated(rating((source / g : U32), (48000 / g : U32)), (source / g : U32), (48000 / g : U32), source, 48000, 0, R.start(U32.min(channels, 2)), Nil{}, HeadStream{size, channels, True{}, True{}})

# UpdateAudioStream's half: 0 or 1, the first that is processed; 2 when
# neither is (or for a sound).
def Feed.target(kind: Feed) -> U32:
  match kind:
    case HeadStatic{}: 2
    case HeadStream{_, _, first, second}: Bool.pick(U32, first, 0, Bool.pick(U32, second, 1, 2))

def Feed.both(kind: Feed) -> Bool:
  match kind:
    case HeadStatic{}: False{}
    case HeadStream{_, _, first, second}: first && second

# IsAudioStreamProcessed: a half is processed (a sound's always are).
def Feed.processed(kind: Feed) -> Bool:
  match kind:
    case HeadStatic{}: True{}
    case HeadStream{_, _, first, second}: first || second

def Feed.channels(kind: Feed) -> U32:
  match kind:
    case HeadStatic{}: 2
    case HeadStream{_, channels, _, _}: channels

def Feed.filled(kind: Feed, +target: U32) -> Feed:
  match kind:
    case HeadStatic{}: HeadStatic{}
    case HeadStream{size, channels, first, second}: HeadStream{size, channels, first && U32.is_ne(target, 0), second && U32.is_ne(target, 1)}

def Head.kind(head: Head) -> Feed:
  Head{_, _, _, _, _, _, _, kind} = head
  kind

# UpdateAudioStreamInLockedState on the head: with both halves processed the
# cursor goes back to the first frame; a half that was written (`wrote`) is no
# longer processed.
def Head.fed(head: Head, +wrote: Bool) -> Head:
  Head{source, rate, mode, coef, +cursor, st, residual, +kind} = head
  Head{source, rate, mode, coef, Bool.pick(U32, Feed.both(kind), 0, cursor), st, residual, Bool.pick(Feed, wrote, Feed.filled(kind, Feed.target(kind)), kind)}

# A list with `data`, then `pad` zeros, in place of the `skip` elements after
# its first `offset` (the lists are long: no depth grows with them).
def take.rev(n: Nat, xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k:
      match xs:
        case Nil{}: acc
        case Con{+x, rest}: take.rev(k, rest, Con{x, acc})

def push.rev(xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}: acc
    case Con{+x, rest}: push.rev(rest, Con{x, acc})

def zeros.rev(n: Nat, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: zeros.rev(k, Con{0, acc})

def splice(+block: +List<U32>, +offset: U32, data: +List<U32>, +pad: U32, +skip: U32) -> +List<U32>:
  List.reverse.go(&2, U32, zeros.rev(U32.to_nat(pad), push.rev(data, take.rev(U32.to_nat(offset), block, Nil{}))), List.drop(&2, U32, block, U32.to_nat((offset + skip : U32))))

# -----------------------------------------------------------------------------
# What does not change in a buffer's turn: its frames and samples, its
# converter's rates, whether they are 1:1, the resampler's parameters and the
# filter's coefficient, and its format: the bits of a sample, the channels,
# and whether it is a stream.
type K is Data:
  K{size: U32, data: +List<U32>, source: U32, rate: U32, plain: Bool, p: R.Params, a: U32, bits: U32, channels: U32, stream: Bool}

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

# What a read gave: the frames (as the buffer holds them), the cursor after
# it, whether the buffer still plays, a stream's two flags, and whether it
# gave fewer frames than asked.
type Read is Data:
  Read{frames: +List<+List<U32>>, cursor: U32, playing: Bool, first: Bool, second: Bool, short: Bool}

def read.static(+k: K, +cursor: U32, +playing: Bool, +est: U32) -> Read:
  K{+size, +data, _, _, _, _, _, _, _, _} = k
  +count = read.count(size, cursor, playing, est)
  +ends = read.ends(size, cursor, playing, est)
  Read{C.split(U32.to_nat(count), 2n, List.take(&2, U32, List.drop(&2, U32, data, U32.to_nat((2 * cursor : U32))), U32.to_nat((2 * count : U32)))),
    Bool.pick(U32, ends, 0, (cursor + count : U32)), playing && Bool.not(ends), True{}, True{}, (count < est : U32)}

# Bool.pick(Bool, c, a, b) as its own def: the pinned compiler's native
# lanes lose a Bool.pick(Bool, ...) result that feeds || (as in src/wav.bend).
def either(c: Bool, +a: Bool, +b: Bool) -> Bool:
  match c:
    case True{}: a
    case False{}: b

# A stream's read never comes short: the frames left in the half its cursor
# is in while that half is not processed, then the other half's while it was
# not processed either, then zeros (as the stream's samples: an 8-bit zero is
# -1). A half read to its end is processed.
def read.left(+size: U32, +cursor: U32) -> U32:
  +sub = U32.max((size / 2 : U32), 1)
  Bool.pick(U32, (cursor >= sub : U32), (size - cursor : U32), (sub - cursor : U32))

# The frames a read of `est` takes from the half the cursor is in.
def read.here(+size: U32, +cursor: U32, +first: Bool, +second: Bool, +est: U32) -> U32:
  Bool.pick(U32, either((cursor >= U32.max((size / 2 : U32), 1) : U32), second, first), 0, U32.min(est, read.left(size, cursor)))

# The frames it then takes from the other half.
def read.there(+size: U32, +cursor: U32, +first: Bool, +second: Bool, +est: U32) -> U32:
  +sub = U32.max((size / 2 : U32), 1)
  +a = read.here(size, cursor, first, second, est)
  +ended = (a > 0 : U32) && U32.is_eq(a, read.left(size, cursor))
  Bool.pick(U32, ended && Bool.not(either((cursor >= sub : U32), first, second)), U32.min((est - a : U32), sub), 0)

def read.stream(+k: K, +cursor: U32, +first: Bool, +second: Bool, +est: U32) -> Read:
  K{+size, +data, _, _, _, _, _, _, +channels, _} = k
  +sub = U32.max((size / 2 : U32), 1)
  +upper = (cursor >= sub : U32)
  +a = read.here(size, cursor, first, second, est)
  +ended = (a > 0 : U32) && U32.is_eq(a, read.left(size, cursor))
  +b = read.there(size, cursor, first, second, est)
  +whole = (b > 0 : U32) && U32.is_eq(b, sub)
  Read{C.split(U32.to_nat(est), U32.to_nat(channels), List.reverse(&2, U32, zeros.rev(U32.to_nat((((est - a) - b) * channels : U32)),
      take.rev(U32.to_nat((b * channels : U32)), List.drop(&2, U32, data, U32.to_nat((Bool.pick(U32, upper, 0, sub) * channels : U32))),
        take.rev(U32.to_nat((a * channels : U32)), List.drop(&2, U32, data, U32.to_nat((cursor * channels : U32))), Nil{}))))),
    (((cursor + a) + b) % U32.max(size, 1) : U32), True{}, first || either(upper, whole, ended), second || either(upper, ended, whole), False{}}

def read.kind(streams: Bool, +k: K, +cursor: U32, +playing: Bool, +first: Bool, +second: Bool, +est: U32) -> Read:
  match streams:
    case True{}: read.stream(k, cursor, first, second, est)
    case False{}: read.static(k, cursor, playing, est)

def K.stream(+k: K) -> Bool:
  K{_, _, _, _, _, _, _, _, _, stream} = k
  stream

# A stream that does not play gives nothing, as a sound.
def read(+k: K, +cursor: U32, +playing: Bool, +first: Bool, +second: Bool, +est: U32) -> Read:
  read.kind(K.stream(k) && playing, k, cursor, playing && Bool.not(K.stream(k)), first, second, est)

# raudio's guess of the input frames `want` output frames need:
# (unsigned int)(((float)source/rate)*want), at least 1 and at most the
# frames its 4096-byte input buffer holds (512 of a sound's).
def read.cap(+bits: U32, +channels: U32) -> U32:
  (4096 / U32.max((channels * (bits / 8 : U32) : U32), 1) : U32)

def estimate(+source: U32, +rate: U32, +want: U32, +cap: U32) -> U32:
  U32.min(cap, U32.max(F32.to_u32(((U32.to_f32(source) / U32.to_f32(rate)) * U32.to_f32(want) : F32)), 1))

# -----------------------------------------------------------------------------
# ma_data_converter_process_pcm_frames for a buffer's converter: the frames go
# to f32 (ma_pcm_u8_to_f32, ma_pcm_s16_to_f32), more than two channels are
# mixed to stereo first (the default channel maps' weights, src/convert.bend),
# and the resampler runs on one or two channels; one channel is copied to both
# after it. A NaN made by the mixing shows in the frame the resampler holds or
# gives. miniaudio works through 4096-byte temporaries: a pass takes at
# most `in.cap` input frames and makes at most `out.cap` output frames, and
# (one channel, or more than two) no more input than the resampler needs for
# them; a pass that makes no frame ends the conversion.

def count.frames(frames: +List<+List<U32>>, +n: U32) -> U32:
  match frames:
    case Nil{}: n
    case Con{_, rest}: count.frames(rest, (n + 1 : U32))

# ma_channel_converter's weights for one output channel: the sum of each
# input sample times its weight (quarters), in input order.
def mixed(xs: +List<U32>, ws: +List<U32>, +acc: F32) -> F32:
  match xs ws:
    case Con{+x, rest} Con{+w, more}: mixed(rest, more, fadd(acc, fmul(R.float(x), (U32.to_f32(w) * 0.25 : F32))))
    case _ _: acc

def mixdown.frame(table: +List<+List<U32>>, +frame: +List<U32>) -> +List<U32>:
  match table:
    case Nil{}: Nil{}
    case Con{+ws, rest}: Con{F32.bits(mixed(frame, ws, 0.0)), mixdown.frame(rest, frame)}

def mixdown(frames: +List<+List<U32>>, +table: +List<+List<U32>>, acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match frames:
    case Nil{}: List.reverse(&2, +List<U32>, acc)
    case Con{+frame, rest}: mixdown(rest, table, Con{mixdown.frame(table, frame), acc})

# The f32 samples of raw frames, flat.
def floats(+k: K, raw: +List<+List<U32>>) -> +List<U32>:
  K{_, _, _, _, _, _, _, +bits, _, _} = k
  C.map.sample(C.map.decode(C.flat(raw), U32.is_eq(bits, 16)), (3 * C.format(bits) + 2 : U32))

def K.channels(+k: K) -> U32:
  K{_, _, _, _, _, _, _, _, channels, _} = k
  channels

def K.bits(+k: K) -> U32:
  K{_, _, _, _, _, _, _, bits, _, _} = k
  bits

def converted.mixed(many: Bool, +frames: +List<+List<U32>>, +channels: U32) -> +List<+List<U32>>:
  match many:
    case True{}: mixdown(frames, C.weights(2n, channels, 2, 0), Nil{})
    case False{}: frames

# The resampler's input for raw frames.
def converted(+k: K, +raw: +List<+List<U32>>) -> +List<+List<U32>>:
  +frames = C.split(U32.to_nat(count.frames(raw, 0)), U32.to_nat(K.channels(k)), floats(k, raw))
  converted.mixed((K.channels(k) > 2 : U32), frames, K.channels(k))

def in.cap(+k: K) -> U32:
  K{_, _, _, _, _, _, _, +bits, +channels, _} = k
  +formatted = U32.is_ne(bits, 32)
  Bool.pick(U32, U32.is_eq(channels, 2), Bool.pick(U32, formatted, 512, 4294967295),
    Bool.pick(U32, U32.is_eq(channels, 1), Bool.pick(U32, formatted, 1024, 4294967295), Bool.pick(U32, formatted, U32.min(512, (1024 / U32.max(channels, 1) : U32)), 512)))

def out.cap(+k: K) -> U32:
  Bool.pick(U32, U32.is_eq(K.channels(k), 2), 4294967295, Bool.pick(U32, U32.is_eq(K.channels(k), 1), 1024, 512))

# floor((frac + n*adv)/rout) for frac and adv below rout.
def carried(n: Nat, +frac: U32, +adv: U32, +rout: U32, +count: U32) -> U32:
  match n:
    case 0n: count
    case 1n+m: carried(m, Bool.pick(U32, ((frac + adv) >= rout : U32), ((frac + adv) - rout : U32), (frac + adv : U32)), adv, rout, (count + Bool.to_u32(((frac + adv) >= rout : U32)) : U32))

# ma_linear_resampler_get_required_input_frame_count for `out` frames (not 0).
def required(+st: R.St, +out: U32, +p: R.Params) -> U32:
  R.St{+t_int, +t_frac, _, _, _, _} = st
  R.Params{_, +rout, +adv_int, +adv_frac, _} = p
  +more = (U32.max(out, 1) - 1 : U32)
  Bool.pick(U32, (adv_int > 4194304 : U32), 4294967295, (t_int + (more * U32.min(adv_int, 4194304)) + carried(U32.to_nat(U32.min(more, 1024)), t_frac, adv_frac, U32.max(rout, 1), 0) : U32))

# A conversion so far: the resampler, the frames made for this callback (last
# first), the raw frames not taken, the frames made by this conversion,
# whether the hosts agree, and whether its last pass made none.
type Fed is Data:
  Fed{st: R.St, acc: +List<+List<U32>>, rest: +List<+List<U32>>, count: U32, fine: Bool, stalled: Bool}

def Fed.over(+fed: Fed, +want: U32) -> Bool:
  Fed{_, _, _, count, _, stalled} = fed
  stalled || (count >= want : U32)

def pass.flowed(flow: Flow, +rest: +List<+List<U32>>, +taken: U32, +count: U32) -> Fed:
  Flow{st, acc, +left, +made, fine} = flow
  Fed{st, acc, List.drop(&2, +List<U32>, rest, U32.to_nat((taken - count.frames(left, 0) : U32))), (count + made : U32), fine, U32.is_eq(made, 0)}

def pass(fed: Fed, +want: U32, +k: K) -> Fed:
  Fed{+st, +acc, +rest, +count, +fine, _} = fed
  K{_, _, _, _, +plain, +p, +a, _, +channels, _} = k
  +out = U32.min((want - count : U32), out.cap(k))
  +taken = U32.min(U32.min(count.frames(rest, 0), in.cap(k)), Bool.pick(U32, U32.is_eq(channels, 2), 4294967295, required(st, out, p)))
  +raw = List.take(&2, +List<U32>, rest, U32.to_nat(taken))
  pass.flowed(flow(U32.to_nat((taken + out + 2 : U32)), R.next_phase(st, out), converted(k, raw), st, acc, 0, out, plain, p, a, fine), rest, taken, count)

def passes(fuel: Nat, done: Bool, +fed: Fed, +want: U32, +k: K) -> Fed:
  match fuel:
    case 0n: fed
    case 1n+m:
      match done:
        case True{}: fed
        case False{}:
          +next = pass(fed, want, k)
          passes(m, Fed.over(next, want), next, want, k)

# `want` frames at most from raw frames.
def feed(+st: R.St, +acc: +List<+List<U32>>, +raw: +List<+List<U32>>, +want: U32, +fine: Bool, +k: K) -> Fed:
  passes(U32.to_nat(2048), False{}, Fed{st, acc, raw, 0, fine, False{}}, want, k)

# -----------------------------------------------------------------------------
# A buffer's turn in a callback: the frames it still owes (`need`), the run
# of at most 512 it is in (`now`) and how many of it are made (`total`), its
# cursor and whether it plays, a stream's two flags, the converter, the
# residual (raw frames), the frames made for this callback (last first),
# whether the hosts agree, and whether the run ended early (the buffer gave
# fewer frames than asked).
type S is Data:
  S{need: U32, now: U32, total: U32, cursor: U32, playing: Bool, first: Bool, second: Bool, st: R.St, residual: +List<+List<U32>>, acc: +List<+List<U32>>, fine: Bool, broke: Bool}

def S.over(+s: S) -> Bool:
  S{_, now, total, _, _, _, _, _, _, _, _, broke} = s
  broke || (total >= now : U32)

def S.finished(+s: S) -> Bool:
  S{need, _, _, _, playing, _, _, _, _, _, _, _} = s
  U32.is_eq(need, 0) || Bool.not(playing)

def step.residual(fed: Fed, +need: U32, +now: U32, +total: U32, +cursor: U32, +playing: Bool, +first: Bool, +second: Bool) -> S:
  Fed{st, acc, rest, +count, fine, _} = fed
  S{need, now, (total + count : U32), cursor, playing, first, second, st, rest, acc, fine, False{}}

# Input the converter did not take stays as the residual: 8 frames at most,
# the rest is lost.
def step.fed(fed: Fed, +need: U32, +now: U32, +total: U32, +cursor: U32, +playing: Bool, +first: Bool, +second: Bool, +short: Bool) -> S:
  Fed{st, acc, rest, +count, fine, _} = fed
  S{need, now, (total + count : U32), cursor, playing, first, second, st, List.take(&2, +List<U32>, rest, 8n), acc, fine, short}

def step.read(read: Read, +st: R.St, +acc: +List<+List<U32>>, +need: U32, +now: U32, +total: U32, +fine: Bool, +k: K) -> S:
  Read{+frames, +cursor, +playing, +first, +second, +short} = read
  step.fed(feed(st, acc, frames, (now - total : U32), fine, k), need, now, total, cursor, playing, first, second, short)

# One pass of ReadAudioBufferFramesInMixingFormat's loop: the residual goes
# through the converter first; without one, the estimated input is read from
# the buffer, and a short read ends the run.
def step(s: S, +k: K) -> S:
  S{+need, +now, +total, +cursor, +playing, +first, +second, +st, residual, +acc, +fine, _} = s
  match residual:
    case Nil{}:
      K{_, _, +source, +rate, _, _, _, +bits, +channels, _} = k
      step.read(read(k, cursor, playing, first, second, estimate(source, rate, (now - total : U32), read.cap(bits, channels))), st, acc, need, now, total, fine, k)
    case Con{+head, +more}:
      step.residual(feed(st, acc, Con{head, more}, (now - total : U32), fine, k), need, now, total, cursor, playing, first, second)

def run(fuel: Nat, done: Bool, +s: S, +k: K) -> S:
  match fuel:
    case 0n: s
    case 1n+m:
      match done:
        case True{}: s
        case False{}:
          +next = step(s, k)
          run(m, S.over(next), next, k)

def begin(s: S) -> S:
  S{+need, _, _, cursor, playing, first, second, st, residual, acc, fine, _} = s
  S{need, U32.min(need, 512), 0, cursor, playing, first, second, st, residual, acc, fine, False{}}

# After a run in OnSendAudioDataToDevice: a buffer that stopped owes nothing
# more; one that still plays but gave fewer frames than the run asked for is
# stopped, back at its first frame (a stream loops, and its runs are never
# short).
def after(s: S) -> S:
  S{+need, +now, +total, +cursor, +playing, first, second, st, residual, acc, fine, broke} = s
  +short = playing && (total < now : U32)
  S{Bool.pick(U32, playing && Bool.not(short), (need - total : U32), 0), now, total, Bool.pick(U32, short, 0, cursor), playing && Bool.not(short), first, second, st, residual, acc, fine, broke}

def runs(fuel: Nat, done: Bool, +s: S, +k: K) -> S:
  match fuel:
    case 0n: s
    case 1n+m:
      match done:
        case True{}: s
        case False{}:
          +next = after(run(U32.to_nat(2048), False{}, begin(s), k))
          runs(m, S.finished(next), next, k)

# The buffer after a callback, whether it still plays, the frames it gave (in
# order, two samples each) and whether the hosts agree on them.
type Turn is Data:
  Turn{head: Head, playing: Bool, made: +List<+List<U32>>, fine: Bool}

# One channel goes to both sides (ma_channel_converter's mono input).
def both(frames: +List<+List<U32>>, acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match frames:
    case Nil{}: acc
    case Con{Con{+m, Nil{}}, rest}: both(rest, Con{[m, m], acc})
    case Con{+frame, rest}: both(rest, Con{frame, acc})

def Feed.flagged(feed: Feed, +first: Bool, +second: Bool) -> Feed:
  match feed:
    case HeadStatic{}: HeadStatic{}
    case HeadStream{size, channels, _, _}: HeadStream{size, channels, first, second}

def turn.done(s: S, +source: U32, +rate: U32, +mode: U32, +coef: U32, feed: Feed) -> Turn:
  S{need, _, _, cursor, playing, +first, +second, st, residual, acc, fine, _} = s
  Turn{Head{source, rate, mode, coef, cursor, st, residual, Feed.flagged(feed, first, second)}, playing, both(acc, Nil{}), fine && U32.is_eq(need, 0)}

def Feed.bits(feed: Feed) -> U32:
  match feed:
    case HeadStatic{}: 32
    case HeadStream{size, _, _, _}: size

def Feed.first(feed: Feed) -> Bool:
  match feed:
    case HeadStatic{}: True{}
    case HeadStream{_, _, first, _}: first

def Feed.second(feed: Feed) -> Bool:
  match feed:
    case HeadStatic{}: True{}
    case HeadStream{_, _, _, second}: second

# A playing buffer of `size` frames in a callback of n frames. Not fine: a
# rate Jonlib does not resample (mode 2), a buffer without frames (raudio
# divides by its size) and a stream of more than 1024 channels (raudio's
# input buffer or miniaudio's temporary holds no frame of it).
def turn(head: Head, +size: U32, +data: +List<U32>, +n: U32) -> Turn:
  Head{+source, +rate, +mode, +coef, cursor, st, residual, +kind} = head
  +g = C.gcd(64n, source, rate)
  +wide = (Feed.channels(kind) > 1024 : U32)
  turn.done(runs(U32.to_nat((n + 2 : U32)), False{},
    S{n, 0, 0, cursor, True{}, Feed.first(kind), Feed.second(kind), st, residual, Nil{}, U32.is_ne(mode, 2) && (size > 0 : U32) && Bool.not(wide), False{}},
    K{size, data, source, rate, U32.is_eq(mode, 0), R.params(True{}, False{}, Nil{}, (source / g : U32), (rate / g : U32)), coef, Feed.bits(kind), Feed.channels(kind), Bool.not(Feed.static(kind))}),
    source, rate, mode, coef, kind)
