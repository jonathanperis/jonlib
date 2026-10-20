# raylib [textures] example - sprite button, ported to Jonlib.
# Adapted from raylib 6.2 examples/textures/textures_sprite_button.c
# (zlib/libpng, Copyright (c) 2019-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# The button follows the mouse: hovered, pressed, and released over it, which
# plays its sound. The sound is loaded and its buffer plays, but nothing is
# mixed (docs/AUDIO.md). Loads resources/button.png and
# resources/buttonfx.wav from raylib's examples/textures (not copied into
# this repository): run it from that directory, or pass `--resources <dir/>`.
# See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The texture (None when it did not load) and its size, the audio device, the
# button's sound and the button state: 0 NORMAL, 1 MOUSE_HOVER, 2 PRESSED.
type State is Type:
  State{button: Maybe<J.Texture>, w: U32, h: U32, audio: J.AudioDevice, fx: J.Sound, pressed: U32}

# frameHeight = (float)button.height/NUM_FRAMES.
def frame_height(+h: U32) -> F32:
  (U32.to_f32(h) / 3.0 : F32)

# btnBounds: the button's frame centered on the screen, from
# screenWidth/2.0f - button.width/2.0f and
# screenHeight/2.0f - (float)button.height/NUM_FRAMES/2.0f.
def left(+w: U32) -> F32:
  (400.0 - (U32.to_f32(w) / 2.0) : F32)

def top(+h: U32) -> F32:
  (225.0 - (frame_height(h) / 2.0) : F32)

def bounds(+w: U32, +h: U32) -> J.Rectangle:
  J.Rectangle{left(w), top(h), U32.to_f32(w), frame_height(h)}

def played(action: Bool, +audio: J.AudioDevice, +fx: J.Sound) -> J.AudioDevice:
  match action:
    case True{}: J.Sound.play(audio, fx)
    case False{}: audio

# Over the button: PRESSED while the left button is down, else MOUSE_HOVER,
# and the action when it is released; NORMAL elsewhere.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{button, +w, +h, +audio, +fx, _} = state
  +over = J.Collision.point_rec(J.Input.get_mouse_position(core), bounds(w, h))
  +down = J.Input.is_mouse_button_down(core, J.MouseButton.MOUSE_BUTTON_LEFT())
  +action = over && J.Input.is_mouse_button_released(core, J.MouseButton.MOUSE_BUTTON_LEFT())
  (core, State{button, w, h, played(action, audio, fx), fx, Bool.pick(U32, over, Bool.pick(U32, down, 2, 1), 0)})

def drawn(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

# DrawTextureRec(button, sourceRec, (btnBounds.x, btnBounds.y), WHITE) with
# sourceRec.y = btnState*frameHeight.
def draw.button(frame: J.Frame, texture: Maybe<J.Texture>, +w: U32, +h: U32, +pressed: U32) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}:
      drawn(J.Draw.texture_rec(frame, t, J.Rectangle{0.0, (U32.to_f32(pressed) * frame_height(h) : F32), U32.to_f32(w), frame_height(h)}, M.Vector2{left(w), top(h)}, J.Color.WHITE()))

def draw.end(+core: J.Core, +w: U32, +h: U32, +audio: J.AudioDevice, +fx: J.Sound, +pressed: U32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{texture, w, h, audio, fx, pressed}, frame))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{button, +w, +h, +audio, +fx, +pressed} = state
  draw.end(core, w, h, audio, fx, pressed, draw.button(J.Frame.clear_background(frame, J.Color.RAYWHITE()), button, w, h, pressed))

# The main loop's body; libm is the sinf/cosf profile (unused: no rotation).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.sized(+core: J.Core, frame: J.Frame, texture: J.Texture, +audio: J.AudioDevice, +fx: J.Sound) -> J.Core & (J.Frame & State):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  (J.Core.set_target_fps(core, 60), (frame, State{Some{J.Texture{id, w, h, format, linear, alpha, texels}}, w, h, audio, fx, 0}))

def setup.texture(+core: J.Core, frame: J.Frame, texture: Maybe<J.Texture>, +audio: J.AudioDevice, +fx: J.Sound) -> J.Core & (J.Frame & State):
  match texture:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, 0, 0, audio, fx, 0}))
    case Some{t}: setup.sized(core, frame, t, audio, fx)

def setup.loaded(+core: J.Core, +audio: J.AudioDevice, +fx: J.Sound, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  setup.texture(core, frame, texture, audio, fx)

# LoadSound gives the zero sound for a file it cannot load.
def setup.sound(dir: String, +core: J.Core, frame: J.Frame, r: J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>) -> IO(J.Core & (J.Frame & State)):
  match r:
    case Tuple{+audio, Done{+fx}}:
      IO.bind(J.Frame & Maybe<J.Texture>, J.Core & (J.Frame & State), J.Texture.load(frame, dir ++ "resources/button.png"),
        loaded => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, audio, fx, loaded)))
    case Tuple{+audio, Fail{_}}:
      IO.bind(J.Frame & Maybe<J.Texture>, J.Core & (J.Frame & State), J.Texture.load(frame, dir ++ "resources/button.png"),
        loaded => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, audio, J.Sound.none(), loaded)))

# After InitWindow(800, 450): InitAudioDevice, LoadSound(dir ++
# "resources/buttonfx.wav"), LoadTexture(dir ++ "resources/button.png"),
# btnState 0, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>, J.Core & (J.Frame & State), J.Sound.load(J.AudioDevice.init(J.AudioDevice.none()), dir ++ "resources/buttonfx.wav"),
    r => setup.sound(dir, core, frame, r))

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
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - sprite button", 800, 450, limit,
    core => frame => setup(dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
