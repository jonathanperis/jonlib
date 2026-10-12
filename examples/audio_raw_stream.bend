# raylib [audio] example - raw stream, ported to Jonlib.
# Adapted from raylib 6.0 examples/audio/audio_raw_stream.c (zlib/libpng,
# Copyright (c) 2015-2026 Ramon Santamaria (@raysan5) and James Hofmann
# (@triplefox)); see LICENSES/raylib.txt.
#
# A 44100 Hz mono float stream of 4096-frame halves plays a sine wave that
# the program writes whenever the device has read a half through; up and
# down change its frequency (at the wave's next period), left and right its
# pan, and the same wave is drawn from the time its last period began.
#
# raylib's device reads the stream on a thread of its own. Here the device
# has a clock (J.AudioClock, docs/AUDIO.md): every pass of the loop first
# makes the callbacks that were due by the frame's time, one each 10 ms, so
# the halves are processed when the script's clock says. The samples go
# nowhere: there is no host device. sin takes a double: the libm profile's
# binary64 sin (M.Libm.sin64, docs/MATH.md); a frame is refused where it
# gives no answer, and every later one. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: every callback and libm call was answered. frequency, wanted, index
# and started are sineFrequency, newSineFrequency, sineIndex and
# sineStartTime.
type State is Data:
  State{valid: Bool, audio: J.AudioDevice, clock: J.AudioClock, stream: J.AudioStream, pan: F32, frequency: U32, wanted: U32, index: U32, started: M.Float64}

# What a filled buffer leaves: whether every sample was answered, the three
# counters and the samples (F32 bits).
type Fill is Data:
  Fill{fine: Bool, frequency: U32, index: U32, started: M.Float64, data: +List<U32>}

# sin(2*PI*n/wavelength): the argument is a float, the sine a double.
def wave(+libm: M.Libm, +n: U32, +wavelength: U32) -> Maybe<M.Float64>:
  M.Libm.sin64(libm, M.Float64.from_f32((((2.0 * M.Math.PI()) * U32.to_f32(n)) / U32.to_f32(wavelength) : F32)))

def narrowed(value: Maybe<M.Float64>) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{v}: M.Float64.to_f32(v)

# buffer[i] = sin(2*PI*sineIndex/wavelength) with wavelength =
# SAMPLE_RATE/sineFrequency, for BUFFER_SIZE samples: after its last sample a
# period gives way to the new frequency, and its start is the frame's time.
# `sample` is the sample of the counters given.
def fill(n: Nat, sample: Maybe<F32>, +libm: M.Libm, +wanted: U32, +now: M.Float64, +frequency: U32, +index: U32, +started: M.Float64, +acc: +List<U32>) -> Fill:
  match n:
    case 0n: Fill{True{}, frequency, index, started, List.reverse(&2, U32, acc)}
    case 1n+rest:
      match sample:
        case None{}: Fill{False{}, frequency, index, started, Nil{}}
        case Some{+value}:
          +over = ((index + 1) >= (44100 / frequency) : U32)
          +next = Bool.pick(U32, over, wanted, frequency)
          +at = Bool.pick(U32, over, 0, (index + 1 : U32))
          fill(rest, narrowed(wave(libm, at, (44100 / next : U32))), libm, wanted, now, next, at, Bool.pick(M.Float64, over, now, started), Con{F32.bits(value), acc})

# UpdateAudioStream(stream, buffer, BUFFER_SIZE).
def update.fed(filled: Fill, +valid: Bool, +audio: J.AudioDevice, +clock: J.AudioClock, +stream: J.AudioStream, +pan: F32, +wanted: U32) -> State:
  Fill{+fine, +frequency, +index, +started, +data} = filled
  State{valid && fine, Bool.pick(J.AudioDevice, fine, J.AudioStream.update(audio, stream, data, 4096), audio), clock, stream, pan, frequency, wanted, index, started}

# if (IsAudioStreamProcessed(stream)): a half is free for the next samples.
def update.stream(processed: Bool, +libm: M.Libm, +now: M.Float64, +valid: Bool, +audio: J.AudioDevice, +clock: J.AudioClock, +stream: J.AudioStream, +pan: F32, +frequency: U32,
    +wanted: U32, +index: U32, +started: M.Float64) -> State:
  match processed:
    case False{}: State{valid, audio, clock, stream, pan, frequency, wanted, index, started}
    case True{}: update.fed(fill(4096n, narrowed(wave(libm, index, (44100 / frequency : U32))), libm, wanted, now, frequency, index, started, Nil{}), valid, audio, clock, stream, pan, wanted)

# The keys: up and down move newSineFrequency by 10 within 20..12500, left
# and right the pan by 0.01f within -1..1 (SetAudioStreamPan).
def update.keys(step: J.AudioClock.Step, +libm: M.Libm, +core: J.Core, +valid: Bool, +stream: J.AudioStream, +pan: F32, +frequency: U32, +wanted: U32, +index: U32, +started: M.Float64) -> State:
  J.AudioStep{+clock, +audio, +fine} = step
  +left = J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT())
  +right = J.Input.is_key_down(core, J.KeyboardKey.KEY_RIGHT())
  +raised = Bool.pick(U32, J.Input.is_key_down(core, J.KeyboardKey.KEY_UP()), U32.min((wanted + 10 : U32), 12500), wanted)
  +lowered = Bool.pick(U32, J.Input.is_key_down(core, J.KeyboardKey.KEY_DOWN()), U32.max((raised - 10 : U32), 20), raised)
  +lefted = Bool.pick(F32, left, F32.max((pan - 0.01 : F32), F32.neg(1.0)), pan)
  +panned = Bool.pick(F32, right, F32.min((lefted + 0.01 : F32), 1.0), lefted)
  +moved = Bool.pick(J.AudioDevice, left || right, J.AudioStream.set_pan(audio, stream, panned), audio)
  update.stream(J.AudioStream.is_processed(moved, stream), libm, J.Core.get_time(core), valid && fine, moved, clock, stream, panned, frequency, lowered, index, started)

# The device's callbacks up to this pass's time come first.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +audio, +clock, +stream, +pan, +frequency, +wanted, +index, +started} = state
  (core, update.keys(J.AudioClock.advance(clock, audio, J.Core.get_time(core)), libm, core, valid, stream, pan, frequency, wanted, index, started))

def label(text: Maybe<String>, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, y, 20.0, J.Color.RED())

def height.narrow(sum: Maybe<M.Float64>) -> Maybe<F32>:
  match sum:
    case None{}: None{}
    case Some{v}: M.Float64.to_f32(v)

def height.raise(product: Maybe<M.Float64>) -> Maybe<F32>:
  match product:
    case None{}: None{}
    case Some{p}: height.narrow(M.Float64.internal.add(M.Float64{1081032704, 0}, p))

def height.scale(sine: Maybe<M.Float64>) -> Maybe<F32>:
  match sine:
    case None{}: None{}
    case Some{s}: height.raise(M.Float64.internal.multiply(M.Float64{1078525952, 0}, s))

# 250 + 50*sin(2*PI*t/wavelength) for t = windowStart + k*windowSize/screenWidth,
# with windowSize = (int)(0.1f*SAMPLE_RATE) = 4410: a double, then the float
# of a Vector2.
def height(+libm: M.Libm, +start: U32, +k: U32, +wavelength: U32) -> Maybe<F32>:
  height.scale(wave(libm, (start + ((k * 4410) / 800) : U32), wavelength))

# DrawLineV(startPos, endPos, RED) for each of the 800 columns; `from` and
# `to` are the heights at column i and the next.
def lines(n: Nat, from: Maybe<F32>, to: Maybe<F32>, +i: U32, +libm: M.Libm, +start: U32, +wavelength: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+rest:
      match from to:
        case Some{+a} Some{+b}: lines(rest, Some{b}, height(libm, start, (i + 2 : U32), wavelength), (i + 1 : U32), libm, start, wavelength,
          J.Draw.line_v(frame, M.Vector2{U32.to_f32(i), a}, M.Vector2{U32.to_f32((i + 1 : U32)), b}, J.Color.RED()))
        case _ _: J.Frame.refuse(frame)

def draw.lines(positive: Bool, +libm: M.Libm, +start: U32, +wavelength: U32, frame: J.Frame) -> J.Frame:
  match positive:
    case False{}: J.Frame.refuse(frame)
    case True{}: lines(800n, height(libm, start, 0, wavelength), height(libm, start, 1, wavelength), 0, libm, start, wavelength, frame)

def draw.wave(start: Maybe<U32>, +libm: M.Libm, +wavelength: U32, frame: J.Frame) -> J.Frame:
  match start:
    case None{}: J.Frame.refuse(frame)
    case Some{+s}: draw.lines((s < 2147483648 : U32), libm, s, wavelength, frame)

# windowStart = (int)((GetTime() - sineStartTime)*SAMPLE_RATE). The wave is
# not drawn for a start that is not an int or is negative (a period that
# began after this frame did: the integer divisions are not ported for it).
def draw.start.count(scaled: Maybe<M.Float64>) -> Maybe<U32>:
  match scaled:
    case None{}: None{}
    case Some{v}: M.Float64.to_int(v)

def draw.start(elapsed: Maybe<M.Float64>) -> Maybe<U32>:
  match elapsed:
    case None{}: None{}
    case Some{e}: draw.start.count(M.Float64.internal.multiply(e, M.Float64{1088784512, 0}))

def draw.at(valid: Bool, +libm: M.Libm, +now: M.Float64, +pan: F32, +frequency: U32, +started: M.Float64, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}:
      f1 = label(J.Text.format("sine frequency: %i", [J.TextInt{frequency}]), 580.0, 10.0, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
      f2 = label(J.Text.format("pan: %.2f", [J.TextFloat{pan}]), 580.0, 30.0, f1)
      f3 = J.Draw.text(f2, "Up/down to change frequency", 10.0, 10.0, 20.0, J.Color.DARKGRAY())
      f4 = J.Draw.text(f3, "Left/right to pan", 10.0, 30.0, 20.0, J.Color.DARKGRAY())
      draw.wave(draw.start(M.Float64.internal.subtract(now, started)), libm, (44100 / frequency : U32), f4)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, +pan, +frequency, _, _, +started} = state
  (core, (state, draw.at(valid, libm, J.Core.get_time(core), pan, frequency, started, frame)))

# The main loop's body; libm is the profile of the binary64 sin.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# PlayAudioStream after SetAudioStreamPan(stream, 0.0f).
def setup.stream(loaded: J.AudioDevice & J.AudioStream, +now: M.Float64) -> State:
  (+audio, +stream) = loaded
  State{True{}, J.AudioStream.play(J.AudioStream.set_pan(audio, stream, 0.0), stream), J.AudioClock.at(now), stream, 0.0, 440, 440, 0, M.Float64{0, 0}}

# After InitWindow(800, 450): InitAudioDevice,
# SetAudioStreamBufferSizeDefault(4096), LoadAudioStream(44100, 32, 1), the
# pan, PlayAudioStream and SetTargetFPS(30).
def setup(+core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 30),
    (frame, setup.stream(J.AudioStream.load(J.AudioDevice.set_stream_buffer_size_default(J.AudioDevice.init(J.AudioDevice.none()), 4096), 44100, 32, 1), J.Core.get_time(core)))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [audio] example - raw stream", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
