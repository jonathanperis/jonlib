# raylib [audio] example - stream callback, ported to Jonlib.
# Adapted from raylib 6.2 examples/audio/audio_stream_callback.c
# (zlib/libpng, Copyright (c) 2026 Dan Hoang (@dan-hoang)); see
# LICENSES/raylib.txt.
#
# A 44100 Hz mono float stream whose frames a callback writes: a sine, a
# square, a triangle or a sawtooth wave (left and right choose), at a
# frequency up and down change at the wave's next period. raylib calls the
# function from its device thread; here the device has a clock (J.AudioClock,
# docs/AUDIO.md) and every pass of the loop first makes the callbacks due by
# the frame's time, the stream's function being `answer` below, a function of
# the program's own state (J.AudioClock.advance_answering).
#
# The example draws the last 10 ms it wrote, 441 samples of a one-second
# buffer, as 799 lines (raylib 6.2 stops at screenWidth - 1: 6.0 drew 800,
# and the end of the last read buffer[SAMPLE_RATE], one float past the
# array). The sine is sinf of a float (6.2; 6.0 took the double sin): the
# libm profile's sinf (M.Libm.sin, docs/SINCOSF.md); a frame is refused
# where it gives no answer, and every later one. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# What the callbacks read and write: the libm profile of sinf (the
# stream's function is a template that closes over nothing: all it needs is
# here), whether every sample was answered, the wave (0 sine, 1 square, 2
# triangle, 3 sawtooth), waveFrequency, newWaveFrequency, waveIndex, and the
# end of `buffer`: its last 441 samples, the newest first (F32 bits).
type Synth is Data:
  Synth{libm: M.Libm, valid: Bool, kind: U32, frequency: U32, wanted: U32, index: U32, recent: +List<U32>}

type State is Data:
  State{valid: Bool, audio: J.AudioDevice, clock: J.AudioClock, stream: J.AudioStream, synth: Synth}

# One sample of a wave at waveIndex `i` for the callback's wavelength `w`:
# sinf(2*PI*i/w); 1.0f or -1.0f; a float ramp up and down over the halves;
# a float ramp up.
def sample(kind: U32, +libm: M.Libm, +i: U32, +w: U32) -> Maybe<F32>:
  match kind:
    case 0: M.Libm.sin(libm, (((2.0 * M.Math.PI()) * U32.to_f32(i)) / U32.to_f32(w) : F32))
    case 1: Some{Bool.pick(F32, (i < (w / 2) : U32), 1.0, F32.neg(1.0))}
    case 2: Some{Bool.pick(F32, (i < (w / 2) : U32), (F32.neg(1.0) + ((2.0 * U32.to_f32(i)) / U32.to_f32((w / 2 : U32))) : F32),
      (1.0 - ((2.0 * U32.to_f32((i - (w / 2) : U32))) / U32.to_f32((w / 2 : U32))) : F32))}
    case _: Some{(F32.neg(1.0) + ((2.0 * U32.to_f32(i)) / U32.to_f32(w)) : F32)}

# What a callback's loop leaves: whether every sample was answered, the
# counters and the frames written (the newest first).
type Wrote is Data:
  Wrote{fine: Bool, frequency: U32, index: U32, frames: +List<U32>}

# for (i < frameCount): the sample, waveIndex++, and at the end of a period
# the new frequency. The wavelength is the one the callback began with.
# `value` is the sample of the counters given.
def write(n: Nat, value: Maybe<F32>, +libm: M.Libm, +kind: U32, +w: U32, +wanted: U32, +frequency: U32, +index: U32, +acc: +List<U32>) -> Wrote:
  match n:
    case 0n: Wrote{True{}, frequency, index, acc}
    case 1n+rest:
      match value:
        case None{}: Wrote{False{}, frequency, index, acc}
        case Some{+v}:
          +over = ((index + 1) >= w : U32)
          +at = Bool.pick(U32, over, 0, (index + 1 : U32))
          write(rest, sample(kind, libm, at, w), libm, kind, w, wanted, Bool.pick(U32, over, wanted, frequency), at, Con{F32.bits(v), acc})

# The last 441 samples of the buffer after the frames written are appended.
def kept(+frames: +List<U32>, +recent: +List<U32>) -> +List<U32>:
  List.take(&2, U32, List.append(&2, U32, frames, recent), 441n)

def answer.wrote(wrote: Wrote, +libm: M.Libm, +valid: Bool, +kind: U32, +wanted: U32, +recent: +List<U32>) -> Synth & +List<U32>:
  Wrote{+fine, +frequency, +index, +frames} = wrote
  (Synth{libm, valid && fine, kind, frequency, wanted, index, kept(frames, recent)}, List.reverse(&2, U32, frames))

# The stream's callback: `frames` frames of the wave, in the stream's format.
def answer(+frames: U32, synth: Synth) -> Synth & +List<U32>:
  Synth{+libm, +valid, +kind, +frequency, +wanted, +index, +recent} = synth
  answer.wrote(write(U32.to_nat(frames), sample(kind, libm, index, (44100 / frequency : U32)), libm, kind, (44100 / frequency : U32), wanted, frequency, index, Nil{}), libm, valid, kind, wanted,
    recent)

# Left: sine to sawtooth to triangle to square to sine; right: the other way.
def turned(+kind: U32, +left: Bool, +right: Bool) -> U32:
  +back = Bool.pick(U32, left, ((kind + 3) % 4 : U32), kind)
  Bool.pick(U32, right, ((back + 1) % 4 : U32), back)

# The keys: up and down move newWaveFrequency by 10 within 20..12500, left
# and right the wave. SetAudioStreamCallback with another function leaves
# the stream with a callback, as it is: the wave is in the program's state,
# which `answer` reads.
def update.keys(clocked: J.AudioClock.Step & Synth, +core: J.Core, +valid: Bool, +stream: J.AudioStream) -> State:
  match clocked:
    case Tuple{J.AudioStep{+clock, +audio, +fine}, Synth{+libm, +answered, +kind, +frequency, +wanted, +index, +recent}}:
      +raised = Bool.pick(U32, J.Input.is_key_down(core, J.KeyboardKey.KEY_UP()), U32.min((wanted + 10 : U32), 12500), wanted)
      +lowered = Bool.pick(U32, J.Input.is_key_down(core, J.KeyboardKey.KEY_DOWN()), U32.max((raised - 10 : U32), 20), raised)
      State{valid && fine && answered, audio, clock, stream,
        Synth{libm, answered, turned(kind, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT()), J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT())), frequency, lowered, index, recent}}

# The device's callbacks up to this pass's time come first, the stream's
# function with them.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{+valid, +audio, +clock, +stream, +synth} = state
  (core, update.keys(J.AudioClock.advance_answering(~Synth, ~(buffer => frames => s => answer(frames, s)), clock, audio, J.Core.get_time(core), synth), core, valid, stream))

def label(text: Maybe<String>, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, y, 20.0, J.Color.RED())

def named(kind: U32) -> String:
  match kind:
    case 0: "sine"
    case 1: "square"
    case 2: "triangle"
    case _: "sawtooth"

def nth(xs: +List<U32>, +i: U32) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+x, rest}: Bool.pick(U32, U32.is_eq(i, 0), x, nth(rest, (i - 1 : U32)))

# 250 - 50*buffer[SAMPLE_RATE - SAMPLE_RATE/100 + k*SAMPLE_RATE/100/screenWidth]
# for k below 800: sample (k*441)/800 of the last 441, the newest being 440
# (a float; samples never written are the array's zeros). Column 798's end
# (k = 799) is the last read: sample 440.
def height(+recent: +List<U32>, +k: U32) -> F32:
  (250.0 - (50.0 * J.Wave.float_bits(nth(recent, (440 - ((k * 441) / 800) : U32)))) : F32)

# DrawLineV(startPos, endPos, RED) for i < screenWidth - 1: 0..798.
def lines(n: Nat, +i: U32, +recent: +List<U32>, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+rest: lines(rest, (i + 1 : U32), recent, J.Draw.line_v(frame, M.Vector2{U32.to_f32(i), height(recent, i)}, M.Vector2{U32.to_f32((i + 1 : U32)), height(recent, (i + 1 : U32))}, J.Color.RED()))

# A frame after a callback or a sample without an answer is refused.
def draw.checked(valid: Bool, frame: J.Frame) -> J.Frame:
  match valid:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

# The texts and the wave.
def draw.frame(+synth: Synth, frame: J.Frame) -> J.Frame:
  Synth{_, _, +kind, _, +wanted, _, +recent} = synth
  f1 = label(J.Text.format("frequency: %i", [J.TextInt{wanted}]), 580.0, 10.0, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = label(J.Text.format("wave type: %s", [J.TextString{named(kind)}]), 580.0, 30.0, f1)
  f3 = J.Draw.text(f2, "Up/down to change frequency", 10.0, 10.0, 20.0, J.Color.DARKGRAY())
  f4 = J.Draw.text(f3, "Left/right to change wave type", 10.0, 30.0, 20.0, J.Color.DARKGRAY())
  lines(799n, 0, recent, f4)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, +synth} = state
  (core, (state, draw.checked(valid, draw.frame(synth, frame))))

# The main loop's body. The profile of sinf is in the state the
# setup makes (the probe's `program(libm)` passes the same one).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# PlayAudioStream, then SetAudioStreamCallback with the sine's function.
def setup.stream(loaded: J.AudioDevice & J.AudioStream, +now: M.Float64, +libm: M.Libm) -> State:
  (+audio, +stream) = loaded
  State{True{}, J.AudioStream.set_callback(J.AudioStream.play(audio, stream), stream, True{}), J.AudioClock.at(now), stream, Synth{libm, True{}, 0, 440, 440, 0, Nil{}}}

# After InitWindow(800, 450): InitAudioDevice,
# SetAudioStreamBufferSizeDefault(4096), LoadAudioStream(44100, 32, 1),
# PlayAudioStream, the callback and SetTargetFPS(30).
def setup(+libm: M.Libm, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 30),
    (frame, setup.stream(J.AudioStream.load(J.AudioDevice.set_stream_buffer_size_default(J.AudioDevice.init(J.AudioDevice.none()), 4096), 44100, 32, 1), J.Core.get_time(core), libm))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [audio] example - stream callback", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
