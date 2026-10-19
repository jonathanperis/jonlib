# raylib [audio] example - mixed processor, ported to Jonlib.
# Adapted from raylib 6.2 examples/audio/audio_mixed_processor.c
# (zlib/libpng, Copyright (c) 2023-2025 hkc (@hatkidchan)); see LICENSES/raylib.txt.
#
# resources/country.mp3 plays as a music stream and space plays
# resources/coin.wav over it. A processor on the device's mix raises every
# sample's magnitude to a power, powf(fabsf(x), exponent) with the sample's
# sign, which left and right move by 0.05 between 0.5 and 3; it also keeps
# the average magnitude of each of its last 400 calls, which the frame
# draws as bars.
#
# raylib calls the processor from the device's callback. Here it is a
# function of the program's own state (J.AudioClock.advance_processing,
# docs/AUDIO.md): `distort` below. The callback's arithmetic takes
# subnormals for zeros (docs/AUDIO.md): the sums and the quotient use
# src/mixer.bend's operations, and a subnormal power is 0. powf is the libm
# profile's (M.Libm.powf, docs/MATH.md: glibc 2.39's, where its two builds
# agree); a frame is refused where it gives no answer, and every later one.
#
# The device has a clock (J.AudioClock): every pass of the loop first makes
# the callbacks that were due by the frame's time, one each 10 ms, then
# updates the music. The samples go nowhere: there is no host device. Loads
# resources/country.mp3 and resources/coin.wav from raylib's examples/audio
# directory: run from that directory, or pass `--resources <dir/>`. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../src/mixer.bend as Mixer

# What the processor reads and writes: the libm profile (its function is a
# template that closes over nothing), whether every powf was answered,
# `exponent`, and averageVolume: the averages of its last 400 calls, the
# oldest first (float bits).
type Voice is Data:
  Voice{libm: M.Libm, fine: Bool, exponent: F32, averages: +List<U32>}

# valid: the files were loaded and every callback was answered.
type State is Data:
  State{valid: Bool, audio: J.AudioDevice, clock: J.AudioClock, music: J.Music, sound: J.Sound, processors: J.AudioProcessors, voice: Voice}

# powf(fabsf(x), exponent)*((x < 0.0f)? -1.0f : 1.0f) for the bits of x, in
# the callback: a subnormal power is 0.
def power.signed(power: Maybe<F32>, +negative: Bool) -> Maybe<F32>:
  match power:
    case None{}: None{}
    case Some{+p}: Some{Mixer.fmul(p, Bool.pick(F32, negative, F32.neg(1.0), 1.0))}

def power.of(+libm: M.Libm, +bits: U32, +exponent: F32) -> Maybe<F32>:
  +x = J.Wave.float_bits(bits)
  power.signed(M.Libm.powf(libm, J.Wave.float_bits((bits .&. 2147483647 : U32)), exponent), (x < 0.0 : F32))

def count(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def first(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{x, _}: x

# What a call leaves: whether every power was answered, the samples (the
# last first) and the average so far.
type Raised is Data:
  Raised{fine: Bool, samples: +List<U32>, average: F32}

# average += fabsf(sample)/frames for the new sample.
def averaged(+average: F32, +sample: F32, +frames: F32) -> F32:
  Mixer.fadd(average, Mixer.fdiv(J.Wave.float_bits((F32.bits(sample) .&. 2147483647 : U32)), frames))

# The loop of ProcessAudio, a sample at a time (left, then right, as the
# example goes through a frame). `power` is the power of the sample at hand.
def distorted(samples: +List<U32>, power: Maybe<F32>, +libm: M.Libm, +exponent: F32, +frames: F32, +average: F32, acc: +List<U32>) -> Raised:
  match samples:
    case Nil{}: Raised{True{}, acc, average}
    case Con{_, +rest}:
      match power:
        case None{}: Raised{False{}, acc, average}
        case Some{+p}: distorted(rest, power.of(libm, first(rest), exponent), libm, exponent, frames, averaged(average, p, frames), Con{F32.bits(p), acc})

# The averages with the oldest dropped and the new one last.
def averages.pushed(averages: +List<U32>, +average: F32) -> +List<U32>:
  List.append(&2, U32, List.drop(&2, U32, averages, 1n), [F32.bits(average)])

def distort.done(done: Raised, +libm: M.Libm, +fine: Bool, +exponent: F32, +averages: +List<U32>, +given: +List<U32>) -> Voice & +List<U32>:
  Raised{+answered, +samples, +average} = done
  (Voice{libm, fine && answered, exponent, Bool.pick(+List<U32>, answered, averages.pushed(averages, average), averages)}, Bool.pick(+List<U32>, answered, List.reverse(&2, U32, samples), given))

# ProcessAudio(buffer, frames): the device's mix, stereo floats. A call that
# has a power without an answer leaves the samples as they were.
def distort(+samples: +List<U32>, voice: Voice) -> Voice & +List<U32>:
  Voice{+libm, +fine, +exponent, +averages} = voice
  distort.done(distorted(samples, power.of(libm, first(samples), exponent), libm, exponent, U32.to_f32((count(samples, 0) / 2 : U32)), 0.0, Nil{}), libm, fine, exponent, averages, samples)

# The keys after UpdateMusicStream: left and right move the exponent by
# 0.05f, kept from 0.5 to 3; space plays the other sound.
def update.music(updated: J.AudioDevice & J.Music, +core: J.Core, +valid: Bool, +clock: J.AudioClock, +sound: J.Sound, +processors: J.AudioProcessors, voice: Voice) -> State:
  (+audio, +music) = updated
  Voice{+libm, +fine, +exponent, +averages} = voice
  +lowered = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT()), (exponent - 0.05 : F32), exponent)
  +moved = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT()), (lowered + 0.05 : F32), lowered)
  +kept = Bool.pick(F32, (moved <= 0.5 : F32), 0.5, Bool.pick(F32, (moved >= 3.0 : F32), 3.0, moved))
  State{valid && fine, Bool.pick(J.AudioDevice, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), J.Sound.play(audio, sound), audio), clock, music, sound, processors,
    Voice{libm, fine, kept, averages}}

def update.clocked(stepped: J.AudioClock.Step & Voice, +core: J.Core, +valid: Bool, +music: J.Music, +sound: J.Sound, +processors: J.AudioProcessors) -> State:
  match stepped:
    case Tuple{J.AudioStep{+clock, +audio, +fine}, +voice}: update.music(J.Music.update(audio, music), core, valid && fine, clock, sound, processors, voice)

# The device's callbacks up to this pass's time come first, the mix's
# processor with them.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{+valid, +audio, +clock, +music, +sound, +processors, +voice} = state
  (core, update.clocked(J.AudioClock.advance_processing(~Voice, ~(buffer => frames => v => (v, Nil{})), ~(tag => samples => v => distort(samples, v)), clock, audio, processors,
    J.Core.get_time(core), voice), core, valid, music, sound, processors))

# DrawLine(201 + i, 232 - (int)(averageVolume[i]*32), 201 + i, 232, MAROON)
# for each of the 400 averages.
def bars(averages: +List<U32>, +i: U32, frame: J.Frame) -> J.Frame:
  match averages:
    case Nil{}: frame
    case Con{+average, rest}:
      bars(rest, (i + 1 : U32), J.Draw.line(frame, U32.to_f32((201 + i : U32)), (232.0 - F32.trunc((J.Wave.float_bits(average) * 32.0 : F32)) : F32), U32.to_f32((201 + i : U32)), 232.0, J.Color.MAROON()))

def draw.labeled(text: Maybe<String>, +averages: +List<U32>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{+t}:
      f1 = J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "MUSIC SHOULD BE PLAYING!", 255.0, 150.0, 20.0, J.Color.LIGHTGRAY())
      f2 = J.Draw.text(f1, t, 215.0, 180.0, 20.0, J.Color.LIGHTGRAY())
      f3 = bars(averages, 0, J.Draw.rectangle(f2, 199.0, 199.0, 402.0, 34.0, J.Color.LIGHTGRAY()))
      f4 = J.Draw.rectangle_lines(f3, 199.0, 199.0, 402.0, 34.0, J.Color.GRAY())
      f5 = J.Draw.text(f4, "PRESS SPACE TO PLAY OTHER SOUND", 200.0, 250.0, 20.0, J.Color.LIGHTGRAY())
      J.Draw.text(f5, "USE LEFT AND RIGHT ARROWS TO ALTER DISTORTION", 140.0, 280.0, 20.0, J.Color.LIGHTGRAY())

# A frame is refused where a file was not loaded, a callback was not
# answered or a power had no answer.
def draw.frame(valid: Bool, +exponent: F32, +averages: +List<U32>, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}: draw.labeled(J.Text.format("EXPONENT = %.2f", [J.TextFloat{exponent}]), averages, frame)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, _, _, Voice{_, +fine, +exponent, +averages}} = state
  (core, (state, draw.frame(valid && fine, exponent, averages, frame)))

# The main loop's body; the profile of powf is in the state the setup makes.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def zeros(n: Nat, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: zeros(k, Con{0, acc})

# PlayMusicStream, with the mix's processor attached before the files were
# loaded, as the example attaches it.
def setup.loaded(r: J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>, +libm: M.Libm, +music: J.Music, +now: M.Float64) -> State:
  match r:
    case Tuple{+audio, Fail{_}}: State{False{}, audio, J.AudioClock.at(now), music, J.Sound.none(), J.AudioProcessors.none(), Voice{libm, True{}, 1.0, zeros(400n, Nil{})}}
    case Tuple{+audio, Done{+sound}}:
      State{True{}, J.Music.play(audio, music), J.AudioClock.at(now), music, sound, J.AudioDevice.attach_mixed_processor(J.AudioProcessors.none(), audio, 1), Voice{libm, True{}, 1.0, zeros(400n, Nil{})}}

def setup.sound(r: J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>, +libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  match r:
    case Tuple{+audio, Fail{_}}:
      IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 60), (frame, State{False{}, audio, J.AudioClock.at(J.Core.get_time(core)), J.Music.none(), J.Sound.none(), J.AudioProcessors.none(),
        Voice{libm, True{}, 1.0, zeros(400n, Nil{})}})))
    case Tuple{+audio, Done{+music}}:
      IO.bind(J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>, J.Core & (J.Frame & State), J.Sound.load(audio, dir ++ "resources/coin.wav"),
        s => IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 60), (frame, setup.loaded(s, libm, music, J.Core.get_time(core))))))

# After InitWindow(800, 450): InitAudioDevice, AttachAudioMixedProcessor,
# LoadMusicStream(dir ++ "resources/country.mp3"), LoadSound(dir ++
# "resources/coin.wav"), the music played, and SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>, J.Core & (J.Frame & State), J.Music.load(J.AudioDevice.init(J.AudioDevice.none()), dir ++ "resources/country.mp3"),
    r => setup.sound(r, libm, dir, core, frame))

# "--resources DIR/" (default: the working directory) and "--frames N".
def options(args: List<String>, +mode: U32, dir: String, +frames: U32) -> String & U32:
  match args:
    case Nil{}: (dir, frames)
    case Con{+a, rest}:
      match mode:
        case 1: options(rest, 0, a, frames)
        case 2: options(rest, 0, dir, J.Desktop.frames_arg(["--frames", a]))
        case _: options(rest, Bool.pick(U32, String.eq(a, "--resources"), 1, Bool.pick(U32, String.eq(a, "--frames"), 2, 0)), dir, frames)

def run.with(parsed: String & U32) -> IO(Unit):
  (dir, +limit) = parsed
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [audio] example - mixed processor", 800, 450, limit,
    core => frame => setup(M.Glibc239Libm{}, dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
