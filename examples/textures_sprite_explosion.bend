# raylib [textures] example - sprite explosion, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_sprite_explosion.c
# (zlib/libpng, Copyright (c) 2019-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A left click starts an explosion at the mouse: 25 sprite frames, one every
# three frames, and its sound. The sound is loaded and its buffer plays, but
# nothing is mixed (docs/AUDIO.md). Loads resources/explosion.png and
# resources/boom.wav from raylib's examples/textures (not copied into this
# repository): run it from that directory, or pass `--resources <dir/>`. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The explosion's place and animation: position, active, currentFrame,
# currentLine and framesCounter (C ints).
type Boom is Data:
  Boom{x: F32, y: F32, active: Bool, current: U32, line: U32, counter: U32}

# The texture (None when it did not load) and its size, the audio device, the
# explosion's sound and the explosion.
type State is Type:
  State{explosion: Maybe<J.Texture>, w: U32, h: U32, audio: J.AudioDevice, fx: J.Sound, boom: Boom}

# frameWidth = (float)explosion.width/NUM_FRAMES_PER_LINE and frameHeight =
# (float)explosion.height/NUM_LINES (5 each).
def fifth(+size: U32) -> F32:
  (U32.to_f32(size) / 5.0 : F32)

# A left click while no explosion is active: it starts centered on the mouse.
def start(started: Bool, +mouse: M.Vector2, +w: U32, +h: U32, +boom: Boom) -> Boom:
  match started:
    case False{}: boom
    case True{}:
      M.Vector2{+mx, +my} = mouse
      Boom{_, _, _, +current, +line, +counter} = boom
      Boom{(mx - (fifth(w) / 2.0) : F32), (my - (fifth(h) / 2.0) : F32), True{}, current, line, counter}

# Every third frame of an active explosion the next sprite frame, the next
# line after the fifth frame and the end after the fifth line.
def advance(+boom: Boom) -> Boom:
  Boom{+x, +y, +active, +current, +line, +counter} = boom
  +due = active && ((counter + 1) > 2 : U32)
  +wrapped = due && ((current + 1) >= 5 : U32)
  +ended = wrapped && ((line + 1) >= 5 : U32)
  Boom{x, y, active && Bool.not(ended), Bool.pick(U32, due, Bool.pick(U32, wrapped, 0, (current + 1 : U32)), current),
    Bool.pick(U32, wrapped, Bool.pick(U32, ended, 0, (line + 1 : U32)), line), Bool.pick(U32, active, Bool.pick(U32, due, 0, (counter + 1 : U32)), counter)}

def Boom.active(+boom: Boom) -> Bool:
  Boom{_, _, active, _, _, _} = boom
  active

def played(started: Bool, +audio: J.AudioDevice, +fx: J.Sound) -> J.AudioDevice:
  match started:
    case True{}: J.Sound.play(audio, fx)
    case False{}: audio

def update(+core: J.Core, state: State) -> J.Core & State:
  State{explosion, +w, +h, +audio, +fx, +boom} = state
  +started = J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_LEFT()) && Bool.not(Boom.active(boom))
  (core, State{explosion, w, h, played(started, audio, fx), fx, advance(start(started, J.Input.get_mouse_position(core), w, h, boom))})

def drawn(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

# if (active) DrawTextureRec(explosion, frameRec, position, WHITE) with
# frameRec.x = frameWidth*currentFrame and frameRec.y = frameHeight*currentLine.
def draw.sprite(active: Bool, frame: J.Frame, texture: Maybe<J.Texture>, +w: U32, +h: U32, +boom: Boom) -> J.Frame & Maybe<J.Texture>:
  match active:
    case False{}: (frame, texture)
    case True{}:
      match texture:
        case None{}: (frame, None{})
        case Some{t}:
          Boom{+x, +y, _, +current, +line, _} = boom
          drawn(J.Draw.texture_rec(frame, t, J.Rectangle{(fifth(w) * U32.to_f32(current) : F32), (fifth(h) * U32.to_f32(line) : F32), fifth(w), fifth(h)}, M.Vector2{x, y}, J.Color.WHITE()))

def draw.end(+core: J.Core, +w: U32, +h: U32, +audio: J.AudioDevice, +fx: J.Sound, +boom: Boom, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{texture, w, h, audio, fx, boom}, frame))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{explosion, +w, +h, +audio, +fx, +boom} = state
  draw.end(core, w, h, audio, fx, boom, draw.sprite(Boom.active(boom), J.Frame.clear_background(frame, J.Color.RAYWHITE()), explosion, w, h, boom))

# The main loop's body; libm is the sinf/cosf profile (unused: no rotation).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.sized(+core: J.Core, frame: J.Frame, texture: J.Texture, +audio: J.AudioDevice, +fx: J.Sound) -> J.Core & (J.Frame & State):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  (J.Core.set_target_fps(core, 60), (frame, State{Some{J.Texture{id, w, h, format, linear, alpha, texels}}, w, h, audio, fx, Boom{0.0, 0.0, False{}, 0, 0, 0}}))

def setup.texture(+core: J.Core, frame: J.Frame, texture: Maybe<J.Texture>, +audio: J.AudioDevice, +fx: J.Sound) -> J.Core & (J.Frame & State):
  match texture:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, 0, 0, audio, fx, Boom{0.0, 0.0, False{}, 0, 0, 0}}))
    case Some{t}: setup.sized(core, frame, t, audio, fx)

def setup.loaded(+core: J.Core, +audio: J.AudioDevice, +fx: J.Sound, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  setup.texture(core, frame, texture, audio, fx)

# LoadSound gives the zero sound for a file it cannot load.
def setup.sound(dir: String, +core: J.Core, frame: J.Frame, r: J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>) -> IO(J.Core & (J.Frame & State)):
  match r:
    case Tuple{+audio, Done{+fx}}:
      IO.bind(J.Frame & Maybe<J.Texture>, J.Core & (J.Frame & State), J.Texture.load(frame, dir ++ "resources/explosion.png"),
        loaded => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, audio, fx, loaded)))
    case Tuple{+audio, Fail{_}}:
      IO.bind(J.Frame & Maybe<J.Texture>, J.Core & (J.Frame & State), J.Texture.load(frame, dir ++ "resources/explosion.png"),
        loaded => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, audio, J.Sound.none(), loaded)))

# After InitWindow(800, 450): InitAudioDevice, LoadSound(dir ++
# "resources/boom.wav"), LoadTexture(dir ++ "resources/explosion.png"), no
# explosion, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>, J.Core & (J.Frame & State), J.Sound.load(J.AudioDevice.init(J.AudioDevice.none()), dir ++ "resources/boom.wav"),
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
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - sprite explosion", 800, 450, limit,
    core => frame => setup(dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
