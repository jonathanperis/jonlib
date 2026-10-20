# raylib [audio] example - music stream, ported to Jonlib.
# Adapted from raylib 6.2 examples/audio/audio_music_stream.c (zlib/libpng,
# Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# resources/country.mp3 plays as a music stream: space restarts it, P pauses
# and resumes it, left and right move its pan, down and up its volume, and a
# bar shows how much of it was played. The file is decoded as it plays
# (src/mp3_stream.bend: dr_mp3's decoder, frame by frame).
#
# raylib's device reads the stream on a thread of its own. Here the device
# has a clock (J.AudioClock, docs/AUDIO.md): every pass of the loop first
# makes the callbacks that were due by the frame's time, one each 10 ms, and
# then updates the music, as the example calls UpdateMusicStream first. The
# samples go nowhere: there is no host device. Loads resources/country.mp3
# from raylib's examples/audio directory: run from that directory, or pass
# `--resources <dir/>`. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: the music was loaded and every callback was answered. `played` is
# timePlayed, None where GetMusicTimePlayed has no answer.
type State is Data:
  State{valid: Bool, audio: J.AudioDevice, clock: J.AudioClock, music: J.Music, pause: Bool, pan: F32, volume: F32, played: +Maybe<F32>}

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

# The keys after the restart: P, then left or right (pan by 0.05f within
# -1..1, SetMusicPan), then down or up (volume by 0.05f within 0..1,
# SetMusicVolume), then timePlayed.
def update.keys(restarted: J.AudioDevice & J.Music, +core: J.Core, +valid: Bool, +clock: J.AudioClock, +pause: Bool, +pan: F32, +volume: F32) -> State:
  (+audio, +music) = restarted
  +pressed = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_P())
  +left = J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT())
  +right = J.Input.is_key_down(core, J.KeyboardKey.KEY_RIGHT()) && Bool.not(left)
  +down = J.Input.is_key_down(core, J.KeyboardKey.KEY_DOWN())
  +up = J.Input.is_key_down(core, J.KeyboardKey.KEY_UP()) && Bool.not(down)
  +panned = Bool.pick(F32, left, F32.max((pan - 0.05 : F32), F32.neg(1.0)), Bool.pick(F32, right, F32.min((pan + 0.05 : F32), 1.0), pan))
  +level = Bool.pick(F32, down, F32.max((volume - 0.05 : F32), 0.0), Bool.pick(F32, up, F32.min((volume + 0.05 : F32), 1.0), volume))
  +held = paused(pressed, pause, audio, music)
  +moved = Bool.pick(J.AudioDevice, left || right, J.Music.set_pan(held, music, panned), held)
  +set = Bool.pick(J.AudioDevice, down || up, J.Music.set_volume(moved, music, level), moved)
  State{valid, set, clock, music, (pressed && Bool.not(pause)) || (Bool.not(pressed) && pause), panned, level, played(J.Music.time_played(set, music), J.Music.time_length(music))}

# UpdateMusicStream(music), then the space key.
def update.music(updated: J.AudioDevice & J.Music, +core: J.Core, +valid: Bool, +clock: J.AudioClock, +pause: Bool, +pan: F32, +volume: F32) -> State:
  (+audio, +music) = updated
  update.keys(restart(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), audio, music), core, valid, clock, pause, pan, volume)

def update.clocked(step: J.AudioClock.Step, +core: J.Core, +valid: Bool, +music: J.Music, +pause: Bool, +pan: F32, +volume: F32) -> State:
  J.AudioStep{+clock, +audio, +fine} = step
  update.music(J.Music.update(audio, music), core, valid && fine, clock, pause, pan, volume)

# The device's callbacks up to this pass's time come first.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{+valid, +audio, +clock, +music, +pause, +pan, +volume, _} = state
  (core, update.clocked(J.AudioClock.advance(clock, audio, J.Core.get_time(core)), core, valid, music, pause, pan, volume))

# The frame: the pan's bar and handle, the time bar, the texts, the
# volume's bar and handle. The handles and the time bar are placed by C's
# (int) of a float.
def draw.bars(+t: F32, +pan: F32, +volume: F32, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "MUSIC SHOULD BE PLAYING!", 255.0, 150.0, 20.0, J.Color.LIGHTGRAY())
  f2 = J.Draw.text(f1, "LEFT-RIGHT for PAN CONTROL", 320.0, 74.0, 10.0, J.Color.DARKBLUE())
  f3 = J.Draw.rectangle_lines(J.Draw.rectangle(f2, 300.0, 100.0, 200.0, 12.0, J.Color.LIGHTGRAY()), 300.0, 100.0, 200.0, 12.0, J.Color.GRAY())
  f4 = J.Draw.rectangle(f3, F32.trunc(((300.0 + (((pan + 1.0) / 2.0) * 200.0)) - 5.0 : F32)), 92.0, 10.0, 28.0, J.Color.DARKGRAY())
  f5 = J.Draw.rectangle(J.Draw.rectangle(f4, 200.0, 200.0, 400.0, 12.0, J.Color.LIGHTGRAY()), 200.0, 200.0, F32.trunc((t * 400.0 : F32)), 12.0, J.Color.MAROON())
  f6 = J.Draw.rectangle_lines(f5, 200.0, 200.0, 400.0, 12.0, J.Color.GRAY())
  f7 = J.Draw.text(f6, "PRESS SPACE TO RESTART MUSIC", 215.0, 250.0, 20.0, J.Color.LIGHTGRAY())
  f8 = J.Draw.text(f7, "PRESS P TO PAUSE/RESUME MUSIC", 208.0, 280.0, 20.0, J.Color.LIGHTGRAY())
  f9 = J.Draw.text(f8, "UP-DOWN for VOLUME CONTROL", 320.0, 334.0, 10.0, J.Color.DARKGREEN())
  f10 = J.Draw.rectangle_lines(J.Draw.rectangle(f9, 300.0, 360.0, 200.0, 12.0, J.Color.LIGHTGRAY()), 300.0, 360.0, 200.0, 12.0, J.Color.GRAY())
  J.Draw.rectangle(f10, F32.trunc(((300.0 + (volume * 200.0)) - 5.0 : F32)), 352.0, 10.0, 28.0, J.Color.DARKGRAY())

# A frame is refused where the music was not loaded, a callback was not
# answered or the time played has no answer.
def draw.frame(valid: Bool, played: +Maybe<F32>, +pan: F32, +volume: F32, frame: J.Frame) -> J.Frame:
  match valid played:
    case True{} Some{+t}: draw.bars(t, pan, volume, frame)
    case _ _: J.Frame.refuse(frame)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, _, +pan, +volume, +played} = state
  (core, (state, draw.frame(valid, played, pan, volume, frame)))

# The main loop's body; libm is unused (nothing here asks it).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# PlayMusicStream, SetMusicPan(music, 0.0f), SetMusicVolume(music, 0.8f).
def setup.music(r: J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>, +now: M.Float64) -> State:
  match r:
    case Tuple{+audio, Fail{_}}: State{False{}, audio, J.AudioClock.at(now), J.Music.none(), False{}, 0.0, 0.8, None{}}
    case Tuple{+audio, Done{+music}}:
      State{True{}, J.Music.set_volume(J.Music.set_pan(J.Music.play(audio, music), music, 0.0), music, 0.8), J.AudioClock.at(now), music, False{}, 0.0, 0.8, Some{0.0}}

# After InitWindow(800, 450): InitAudioDevice, LoadMusicStream(dir ++
# "resources/country.mp3"), the music played with its pan and volume, and
# SetTargetFPS(30).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>, J.Core & (J.Frame & State), J.Music.load(J.AudioDevice.init(J.AudioDevice.none()), dir ++ "resources/country.mp3"),
    r => IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 30), (frame, setup.music(r, J.Core.get_time(core))))))

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
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [audio] example - music stream", 800, 450, limit,
    core => frame => setup(dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
