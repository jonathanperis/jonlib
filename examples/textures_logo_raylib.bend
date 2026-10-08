# raylib [textures] example - logo raylib, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_logo_raylib.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Loads raylib_logo.png from raylib's examples/textures/resources (not copied
# into this repository): run it from that directory, or pass
# `--logo <path>`. A file that does not load draws only the text, as raylib
# draws nothing for a texture with id 0. Build and run as
# examples/core_basic_window.bend; see docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{texture: Maybe<J.Texture>}

def update(+core: J.Core, state: State) -> J.Core & State:
  (core, state)

def drawn(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

# DrawTexture(texture, screenWidth/2 - texture.width/2, screenHeight/2 -
# texture.height/2, WHITE) in C int arithmetic.
def draw.at(frame: J.Frame, +id: U32, +w: U32, +h: U32, +format: U32, +linear: Bool, +alpha: Bool, texels: Maybe<Array<U32>>) -> J.Frame & Maybe<J.Texture>:
  drawn(J.Draw.texture(frame, J.Texture{id, w, h, format, linear, alpha, texels}, (400.0 - U32.to_f32((w / 2 : U32)) : F32), (225.0 - U32.to_f32((h / 2 : U32)) : F32), J.Color.WHITE()))

def draw.loaded(frame: J.Frame, texture: J.Texture) -> J.Frame & Maybe<J.Texture>:
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  draw.at(frame, id, w, h, format, linear, alpha, texels)

def draw.texture(frame: J.Frame, texture: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: draw.loaded(frame, t)

def draw.text(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{texture}, J.Draw.text(frame, "this IS a texture!", 360.0, 370.0, 10.0, J.Color.GRAY())))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{texture} = state
  draw.text(core, draw.texture(J.Frame.clear_background(frame, J.Color.RAYWHITE()), texture))

# The main loop's body; libm is the sinf/cosf profile (unused here).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.loaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{texture}))

# After InitWindow(800, 450): LoadTexture of the decoded image (none when the
# file did not load), SetTargetFPS(60).
def setup(image: Maybe<J.Surface>, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  match image:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{None{}}))
    case Some{surface}: setup.loaded(core, J.Texture.load_from_image(frame, surface))

def image(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{surface}: Some{surface}

# "--logo PATH" (default resources/raylib_logo.png) and "--frames N".
def options(args: List<String>, +mode: U32, logo: String, +frames: U32) -> String & U32:
  match args:
    case Nil{}: (logo, frames)
    case Con{+a, rest}:
      match mode:
        case 1: options(rest, 0, a, frames)
        case 2: options(rest, 0, logo, J.Desktop.frames_arg(["--frames", a]))
        case _: options(rest, Bool.pick(U32, String.eq(a, "--logo"), 1, Bool.pick(U32, String.eq(a, "--frames"), 2, 0)), logo, frames)

def run.loaded(+limit: U32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - logo raylib", 800, 450, limit,
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(image(result), core, frame)))

def run.with(parsed: String & U32) -> IO(Unit):
  (logo, +limit) = parsed
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_png(logo), result => run.loaded(limit, result))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "resources/raylib_logo.png", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
