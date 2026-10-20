# raylib [audio] example - sound loading, ported to Jonlib.
# Adapted from raylib 6.2 examples/audio/audio_sound_loading.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# SPACE plays a sound loaded from a WAV file and ENTER one loaded from an
# Ogg Vorbis file. The buffers play, but nothing is mixed (docs/AUDIO.md).
# Loads resources/sound.wav and resources/target.ogg from raylib's
# examples/audio (not copied into this repository): run it from that
# directory, or pass `--resources <dir/>`. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The audio device, fxWav and fxOgg.
type State is Data:
  State{audio: J.AudioDevice, wav: J.Sound, ogg: J.Sound}

def played(pressed: Bool, audio: J.AudioDevice, +sound: J.Sound) -> J.AudioDevice:
  match pressed:
    case True{}: J.Sound.play(audio, sound)
    case False{}: audio

# SPACE: PlaySound(fxWav); ENTER: PlaySound(fxOgg).
def update(+core: J.Core, state: State) -> J.Core & State:
  State{audio, +wav, +ogg} = state
  (core, State{played(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_ENTER()), played(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), audio, wav), ogg), wav, ogg})

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  (core, (state, J.Draw.text(J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "Press SPACE to PLAY the WAV sound!", 200.0, 180.0, 20.0, J.Color.LIGHTGRAY()),
    "Press ENTER to PLAY the OGG sound!", 200.0, 220.0, 20.0, J.Color.LIGHTGRAY())))

# The main loop's body; libm is the profile the Ogg file was decoded under.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# LoadSound gives the zero sound for a file it cannot load.
def setup.ogg(r: J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>, +wav: J.Sound) -> State:
  match r:
    case Tuple{+audio, Done{+sound}}: State{audio, wav, sound}
    case Tuple{+audio, Fail{_}}: State{audio, wav, J.Sound.none()}

def setup.loaded(+audio: J.AudioDevice, +wav: J.Sound, +libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>, J.Core & (J.Frame & State), J.Sound.load_with(M.Uncontracted{}, libm, audio, dir ++ "resources/target.ogg"),
    loaded => IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 60), (frame, setup.ogg(loaded, wav)))))

def setup.wav(r: J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>, +libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  match r:
    case Tuple{+audio, Done{+sound}}: setup.loaded(audio, sound, libm, dir, core, frame)
    case Tuple{+audio, Fail{_}}: setup.loaded(audio, J.Sound.none(), libm, dir, core, frame)

# After InitWindow(800, 450): InitAudioDevice, LoadSound(dir ++
# "resources/sound.wav"), LoadSound(dir ++ "resources/target.ogg") (its
# transform's tables under the libm profile) and SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>, J.Core & (J.Frame & State), J.Sound.load(J.AudioDevice.init(J.AudioDevice.none()), dir ++ "resources/sound.wav"),
    r => setup.wav(r, libm, dir, core, frame))

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
  (+dir, +limit) = parsed
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [audio] example - sound loading", 800, 450, limit,
    core => frame => setup(M.Glibc239Libm{}, dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
