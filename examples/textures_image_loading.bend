# raylib [textures] example - image loading, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_image_loading.c (zlib/libpng,
# Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A PNG loaded as an image, uploaded as a texture and drawn centered. See
# docs/DRIVER.md.
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

# DrawTexture(texture, screenWidth/2 - width/2, screenHeight/2 - height/2, WHITE) in C int arithmetic.
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
  (core, (State{texture}, J.Draw.text(frame, "this IS a texture loaded from an image!", 300.0, 370.0, 10.0, J.Color.GRAY())))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{texture} = state
  draw.text(core, draw.texture(J.Frame.clear_background(frame, J.Color.RAYWHITE()), texture))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{texture}))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{None{}}))
    case Done{image}: setup.uploaded(core, J.Texture.load_from_image(frame, image))

# After InitWindow(800, 450): LoadImage, LoadTextureFromImage, SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_image(dir ++ "resources/raylib_logo.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - image loading", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
