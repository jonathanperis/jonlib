# raylib [audio] example - sound multi, ported to Jonlib.
# Adapted from raylib 6.2 examples/audio/audio_sound_multi.c (zlib/libpng,
# Copyright (c) 2023-2025 Jeffery Myers (@JeffM2501)); see LICENSES/raylib.txt.
#
# SPACE plays the next of ten sounds: one loaded sound and nine aliases over
# its samples, so that it can overlap itself. The buffers play, but nothing
# is mixed (docs/AUDIO.md). Loads resources/sound.wav from raylib's
# examples/audio (not copied into this repository): run it from that
# directory, or pass `--resources <dir/>`. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The audio device, soundArray (MAX_SOUNDS 10) and currentSound.
type State is Data:
  State{audio: J.AudioDevice, sounds: +List<J.Sound>, current: U32}

def sound.at(sounds: +List<J.Sound>, +index: U32) -> J.Sound:
  match sounds:
    case Nil{}: J.Sound.none()
    case Con{+sound, rest}: Bool.pick(J.Sound, U32.is_eq(index, 0), sound, sound.at(rest, (index - 1 : U32)))

# SPACE: PlaySound(soundArray[currentSound]) and the next slot, back to 0
# after the last.
def play(pressed: Bool, +audio: J.AudioDevice, +sounds: +List<J.Sound>, +current: U32) -> State:
  match pressed:
    case True{}: State{J.Sound.play(audio, sound.at(sounds, current)), sounds, Bool.pick(U32, ((current + 1) >= 10 : U32), 0, (current + 1 : U32))}
    case False{}: State{audio, sounds, current}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{+audio, +sounds, +current} = state
  (core, play(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), audio, sounds, current))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  (core, (state, J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "Press SPACE to PLAY a WAV sound!", 200.0, 180.0, 20.0, J.Color.LIGHTGRAY())))

# The main loop's body; libm is the sinf/cosf profile (unused: no rotation).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def aliases.added(r: J.AudioDevice & J.Sound, +acc: +List<J.Sound>) -> J.AudioDevice & +List<J.Sound>:
  match r:
    case Tuple{+audio, +alias}: (audio, Con{alias, acc})

def aliases.next(r: J.AudioDevice & +List<J.Sound>, +source: J.Sound) -> J.AudioDevice & +List<J.Sound>:
  match r:
    case Tuple{+audio, +acc}: aliases.added(J.Sound.load_alias(audio, source), acc)

# for (i = 1; i < MAX_SOUNDS; i++) soundArray[i] = LoadSoundAlias(soundArray[0]):
# the device and the sounds so far, last first.
def aliases(n: Nat, +source: J.Sound, r: J.AudioDevice & +List<J.Sound>) -> J.AudioDevice & +List<J.Sound>:
  match n:
    case 0n: r
    case 1n+k: aliases(k, source, aliases.next(r, source))

def setup.aliased(r: J.AudioDevice & +List<J.Sound>) -> State:
  match r:
    case Tuple{+audio, +sounds}: State{audio, List.reverse(&2, J.Sound, sounds), 0}

# LoadSound gives the zero sound for a file it cannot load, and
# LoadSoundAlias reads through its NULL buffer: ten zero sounds here.
def setup.sound(r: J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>) -> State:
  match r:
    case Tuple{+audio, Done{+sound}}: setup.aliased(aliases(9n, sound, (audio, [sound])))
    case Tuple{+audio, Fail{_}}: setup.aliased(aliases(9n, J.Sound.none(), (audio, [J.Sound.none()])))

# After InitWindow(800, 450): InitAudioDevice, LoadSound(dir ++
# "resources/sound.wav") and its nine aliases, currentSound 0,
# SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>, J.Core & (J.Frame & State), J.Sound.load(J.AudioDevice.init(J.AudioDevice.none()), dir ++ "resources/sound.wav"),
    r => IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 60), (frame, setup.sound(r)))))

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
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [audio] example - sound multi", 800, 450, limit,
    core => frame => setup(dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
