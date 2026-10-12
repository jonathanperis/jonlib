# raylib [audio] example - stream effects, ported to Jonlib.
# Adapted from raylib 6.0 examples/audio/audio_stream_effects.c (zlib/libpng,
# Copyright (c) 2022-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# resources/country.mp3 plays as a music stream; F puts a low-pass filter on
# the stream and takes it off, D a delay of a second; space restarts the
# music, P pauses and resumes it, and a bar shows how much of it was played.
#
# The effects are stream processors: raylib calls them from the device's
# callback with the stream's frames as the device takes them (stereo floats
# at 48000 Hz). Here they are functions of the program's own state
# (J.AudioClock.advance_processing, docs/AUDIO.md): `effect` below, by the
# tag each was attached with. The callback's arithmetic takes subnormals
# for zeros (docs/AUDIO.md), so the effects compute with src/mixer.bend's
# operations, as the device's mix does.
#
# The delay is the example's ring of 96000 floats, read two entries ahead
# of where it is written: a frame comes out 47999 frames after it went in,
# and zeros before that. Here it is a queue of that length.
#
# The device has a clock (J.AudioClock): every pass of the loop first makes
# the callbacks that were due by the frame's time, one each 10 ms, then
# updates the music, as the example calls UpdateMusicStream first. The
# samples go nowhere: there is no host device. Loads resources/country.mp3
# from raylib's examples/audio directory: run from that directory, or pass
# `--resources <dir/>`. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../src/mixer.bend as Mixer

# The effects' own state: the filter's two lows (its statics), and the delay
# line: the frames of silence it still has to give, then the frames that
# went in, the oldest first (`front`), and the newest first (`back`).
type Effects is Data:
  Effects{low0: F32, low1: F32, silence: U32, front: +List<U32>, back: +List<U32>}

# valid: the music was loaded and every callback was answered. `played` is
# timePlayed, None where GetMusicTimePlayed has no answer.
type State is Data:
  State{valid: Bool, audio: J.AudioDevice, clock: J.AudioClock, music: J.Music, processors: J.AudioProcessors, pause: Bool, lpf: Bool, delay: Bool, played: +Maybe<F32>, effects: Effects}

# What the filter leaves: its two lows and the frames filtered.
type Lows is Data:
  Lows{low0: F32, low1: F32, samples: +List<U32>}

# AudioProcessEffectLPF: low += k*(sample - low) for each channel, with
# cutoff = 70.0f/44100.0f and k = cutoff/(cutoff + 0.1591549431f).
def lowpass(samples: +List<U32>, +k: F32, +low0: F32, +low1: F32, acc: +List<U32>) -> Lows:
  match samples:
    case Con{+l, Con{+r, rest}}:
      +a = Mixer.fadd(low0, Mixer.fmul(k, Mixer.fsub(J.Wave.float_bits(l), low0)))
      +b = Mixer.fadd(low1, Mixer.fmul(k, Mixer.fsub(J.Wave.float_bits(r), low1)))
      lowpass(rest, k, a, b, Con{F32.bits(b), Con{F32.bits(a), acc}})
    case +odd: Lows{low0, low1, List.reverse.go(&2, U32, acc, odd)}

def lowpass.kept(done: Lows, +silence: U32, +front: +List<U32>, +back: +List<U32>) -> Effects & +List<U32>:
  Lows{low0, low1, samples} = done
  (Effects{low0, low1, silence, front, back}, samples)

# The delay line gives a frame and takes one. While it has silence to give,
# that; else its oldest frame, the frames that went in turned over when the
# oldest are used up.
type Line is Data:
  Line{left: U32, right: U32, silence: U32, front: +List<U32>, back: +List<U32>}

def Line.l(line: Line) -> U32:
  Line{left, _, _, _, _} = line
  left

def Line.r(line: Line) -> U32:
  Line{_, right, _, _, _} = line
  right

def Line.quiet(line: Line) -> U32:
  Line{_, _, silence, _, _} = line
  silence

def Line.older(line: Line) -> +List<U32>:
  Line{_, _, _, front, _} = line
  front

def Line.newer(line: Line) -> +List<U32>:
  Line{_, _, _, _, back} = line
  back

def line.front(front: +List<U32>, +back: +List<U32>) -> Line:
  match front:
    case Con{+l, Con{+r, rest}}: Line{l, r, 0, rest, back}
    case _: Line{0, 0, 0, Nil{}, back}

def line.turned(front: +List<U32>, +back: +List<U32>) -> Line:
  match front:
    case Nil{}: line.front(List.reverse(&2, U32, back), Nil{})
    case Con{+l, rest}: line.front(Con{l, rest}, back)

def line.next(quiet: Bool, +silence: U32, +front: +List<U32>, +back: +List<U32>) -> Line:
  match quiet:
    case True{}: Line{0, 0, (silence - 1 : U32), front, back}
    case False{}: line.turned(front, back)

# 0.5f*sample + 0.5f*delayed.
def half(+sample: U32, +delayed: U32) -> U32:
  F32.bits(Mixer.fadd(Mixer.fmul(0.5, J.Wave.float_bits(sample)), Mixer.fmul(0.5, J.Wave.float_bits(delayed))))

# AudioProcessEffectDelay: each sample is half itself and half the delayed
# one, and goes into the line.
def delayed(samples: +List<U32>, +silence: U32, +front: +List<U32>, +back: +List<U32>, acc: +List<U32>) -> Line & +List<U32>:
  match samples:
    case Con{+l, Con{+r, rest}}:
      +taken = line.next((silence > 0 : U32), silence, front, back)
      delayed(rest, Line.quiet(taken), Line.older(taken), Con{half(r, Line.r(taken)), Con{half(l, Line.l(taken)), Line.newer(taken)}}, Con{half(r, Line.r(taken)), Con{half(l, Line.l(taken)), acc}})
    case +odd: (Line{0, 0, silence, front, back}, List.reverse.go(&2, U32, acc, odd))

def delay.kept(done: Line & +List<U32>, +low0: F32, +low1: F32) -> Effects & +List<U32>:
  match done:
    case Tuple{Line{_, _, +silence, +front, +back}, +samples}: (Effects{low0, low1, silence, front, back}, samples)

# The stream's processors by the tags they were attached with: 1 the
# low-pass filter, 2 the delay.
def effect(tag: U32, +samples: +List<U32>, effects: Effects) -> Effects & +List<U32>:
  match tag:
    case 1:
      Effects{+low0, +low1, +silence, +front, +back} = effects
      lowpass.kept(lowpass(samples, Mixer.fdiv(Mixer.fdiv(70.0, 44100.0), Mixer.fadd(Mixer.fdiv(70.0, 44100.0), J.Wave.float_bits(1042479491))), low0, low1, Nil{}), silence, front, back)
    case 2:
      Effects{+low0, +low1, +silence, +front, +back} = effects
      delay.kept(delayed(samples, silence, front, back, Nil{}), low0, low1)
    case _: (effects, samples)

# timePlayed = GetMusicTimePlayed(music)/GetMusicTimeLength(music), no more
# than 1.
def played(time: Maybe<F32>, +length: F32) -> +Maybe<F32>:
  match time:
    case None{}: None{}
    case Some{+t}: Some{Bool.pick(F32, ((t / length) > 1.0 : F32), 1.0, (t / length : F32))}

# if (IsKeyPressed(KEY_SPACE)) { StopMusicStream(music); PlayMusicStream(music); }
def restart.play(stopped: J.AudioDevice & J.Music) -> J.AudioDevice & J.Music:
  (+audio, +music) = stopped
  (J.Music.play(audio, music), music)

def restart(space: Bool, +audio: J.AudioDevice, +music: J.Music) -> J.AudioDevice & J.Music:
  match space:
    case False{}: (audio, music)
    case True{}: restart.play(J.Music.stop(audio, music))

# P turns `pause` and pauses or resumes the music.
def paused(pressed: Bool, +pause: Bool, +audio: J.AudioDevice, +music: J.Music) -> J.AudioDevice:
  match pressed:
    case False{}: audio
    case True{}: Bool.pick(J.AudioDevice, pause, J.Music.resume(audio, music), J.Music.pause(audio, music))

# F or D turns an effect: its processor is attached to the music's stream,
# or detached from it.
def toggled(pressed: Bool, +on: Bool, +processors: J.AudioProcessors, +audio: J.AudioDevice, +stream: J.AudioStream, +tag: U32) -> J.AudioProcessors:
  match pressed:
    case False{}: processors
    case True{}: Bool.pick(J.AudioProcessors, on, J.AudioStream.detach_processor(processors, audio, stream, tag), J.AudioStream.attach_processor(processors, audio, stream, tag))

def turned(+pressed: Bool, +on: Bool) -> Bool:
  (pressed && Bool.not(on)) || (Bool.not(pressed) && on)

# The keys after the restart: P, then F, then D, then timePlayed.
def update.keys(restarted: J.AudioDevice & J.Music, +core: J.Core, +valid: Bool, +clock: J.AudioClock, +processors: J.AudioProcessors, +pause: Bool, +lpf: Bool, +delay: Bool, +effects: Effects) -> State:
  (+audio, +music) = restarted
  +p = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_P())
  +f = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_F())
  +d = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_D())
  +held = paused(p, pause, audio, music)
  +filtered = toggled(f, lpf, processors, held, J.Music.stream(music), 1)
  State{valid, held, clock, music, toggled(d, delay, filtered, held, J.Music.stream(music), 2), turned(p, pause), turned(f, lpf), turned(d, delay),
    played(J.Music.time_played(held, music), J.Music.time_length(music)), effects}

# UpdateMusicStream(music), then the space key.
def update.music(updated: J.AudioDevice & J.Music, +core: J.Core, +valid: Bool, +clock: J.AudioClock, +processors: J.AudioProcessors, +pause: Bool, +lpf: Bool, +delay: Bool, +effects: Effects) -> State:
  (+audio, +music) = updated
  update.keys(restart(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), audio, music), core, valid, clock, processors, pause, lpf, delay, effects)

def update.clocked(stepped: J.AudioClock.Step & Effects, +core: J.Core, +valid: Bool, +music: J.Music, +processors: J.AudioProcessors, +pause: Bool, +lpf: Bool, +delay: Bool) -> State:
  match stepped:
    case Tuple{J.AudioStep{+clock, +audio, +fine}, +effects}: update.music(J.Music.update(audio, music), core, valid && fine, clock, processors, pause, lpf, delay, effects)

# The device's callbacks up to this pass's time come first, the stream's
# processors with them.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{+valid, +audio, +clock, +music, +processors, +pause, +lpf, +delay, _, +effects} = state
  (core, update.clocked(J.AudioClock.advance_processing(~Effects, ~(buffer => frames => e => (e, Nil{})), ~(tag => samples => e => effect(tag, samples, e)), clock, audio, processors,
    J.Core.get_time(core), effects), core, valid, music, processors, pause, lpf, delay))

def state.of(+on: Bool) -> String:
  Bool.pick(String, on, "ON", "OFF")

# The frame: the time bar, placed by C's (int) of a float, and the texts.
def draw.bars(+t: F32, +lpf: Bool, +delay: Bool, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "MUSIC SHOULD BE PLAYING!", 245.0, 150.0, 20.0, J.Color.LIGHTGRAY())
  f2 = J.Draw.rectangle(J.Draw.rectangle(f1, 200.0, 180.0, 400.0, 12.0, J.Color.LIGHTGRAY()), 200.0, 180.0, F32.trunc((t * 400.0 : F32)), 12.0, J.Color.MAROON())
  f3 = J.Draw.rectangle_lines(f2, 200.0, 180.0, 400.0, 12.0, J.Color.GRAY())
  f4 = J.Draw.text(f3, "PRESS SPACE TO RESTART MUSIC", 215.0, 230.0, 20.0, J.Color.LIGHTGRAY())
  f5 = J.Draw.text(f4, "PRESS P TO PAUSE/RESUME MUSIC", 208.0, 260.0, 20.0, J.Color.LIGHTGRAY())
  f6 = J.Draw.text(f5, "PRESS F TO TOGGLE LPF EFFECT: " ++ state.of(lpf), 200.0, 320.0, 20.0, J.Color.GRAY())
  J.Draw.text(f6, "PRESS D TO TOGGLE DELAY EFFECT: " ++ state.of(delay), 180.0, 350.0, 20.0, J.Color.GRAY())

# A frame is refused where the music was not loaded, a callback was not
# answered or the time played has no answer.
def draw.frame(valid: Bool, played: +Maybe<F32>, +lpf: Bool, +delay: Bool, frame: J.Frame) -> J.Frame:
  match valid played:
    case True{} Some{+t}: draw.bars(t, lpf, delay, frame)
    case _ _: J.Frame.refuse(frame)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, _, _, +lpf, +delay, +played, _} = state
  (core, (state, draw.frame(valid, played, lpf, delay, frame)))

# The main loop's body; libm is unused (nothing here asks it).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# PlayMusicStream; the delay line is a second of silence less a frame.
def setup.music(r: J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>, +now: M.Float64) -> State:
  match r:
    case Tuple{+audio, Fail{_}}: State{False{}, audio, J.AudioClock.at(now), J.Music.none(), J.AudioProcessors.none(), False{}, False{}, False{}, None{}, Effects{0.0, 0.0, 47999, Nil{}, Nil{}}}
    case Tuple{+audio, Done{+music}}:
      State{True{}, J.Music.play(audio, music), J.AudioClock.at(now), music, J.AudioProcessors.none(), False{}, False{}, False{}, Some{0.0}, Effects{0.0, 0.0, 47999, Nil{}, Nil{}}}

# After InitWindow(800, 450): InitAudioDevice, LoadMusicStream(dir ++
# "resources/country.mp3"), the music played, and SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>, J.Core & (J.Frame & State), J.Music.load(J.AudioDevice.init(J.AudioDevice.none()), dir ++ "resources/country.mp3"),
    r => IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 60), (frame, setup.music(r, J.Core.get_time(core))))))

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
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [audio] example - stream effects", 800, 450, limit,
    core => frame => setup(dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
