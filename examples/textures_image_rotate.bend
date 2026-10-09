# raylib [textures] example - image rotate, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_image_rotate.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The logo rotated by 45, 90 and -90 degrees with ImageRotate; a left click
# or RIGHT cycles them. ImageRotate's sinf/cosf follow the libm profile
# (Surface.rotate_degrees_for, docs/ROTATION.md). See docs/DRIVER.md.
# LoadImage of a .png file is raylib's PNG loader (LoadImage selects it by the
# extension), Surface.load_png here: the generic J.Surface.load_image would
# compile every image decoder into the program (about 1.5 GB more compiler
# memory).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, current: U32}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{t0, t1, t2, +current} = state
  +next = J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_LEFT()) || J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT())
  (core, State{t0, t1, t2, Bool.pick(U32, next, ((current + 1) % 3 : U32), current)})

def drawn(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

# DrawTexture(t, screenWidth/2 - t.width/2, screenHeight/2 - t.height/2, WHITE).
def draw.loaded(frame: J.Frame, texture: J.Texture) -> J.Frame & Maybe<J.Texture>:
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  drawn(J.Draw.texture(frame, J.Texture{id, w, h, format, linear, alpha, texels}, (400.0 - U32.to_f32((w / 2 : U32)) : F32), (225.0 - U32.to_f32((h / 2 : U32)) : F32), J.Color.WHITE()))

def draw.texture(frame: J.Frame, texture: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: draw.loaded(frame, t)

def draw.done(+core: J.Core, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, +current: U32) -> J.Core & (State & J.Frame):
  (core, (State{t0, t1, t2, current}, J.Draw.text(frame, "Press LEFT MOUSE BUTTON to rotate the image clockwise", 250.0, 420.0, 10.0, J.Color.DARKGRAY())))

def draw.d0(+core: J.Core, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, t0) = r
  draw.done(core, frame, t0, t1, t2, 0)

def draw.d1(+core: J.Core, t0: Maybe<J.Texture>, t2: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, t1) = r
  draw.done(core, frame, t0, t1, t2, 1)

def draw.d2(+core: J.Core, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, t2) = r
  draw.done(core, frame, t0, t1, t2, 2)

def draw.at(current: U32, +core: J.Core, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  match current:
    case 0: draw.d0(core, t1, t2, draw.texture(frame, t0))
    case 1: draw.d1(core, t0, t2, draw.texture(frame, t1))
    case _: draw.d2(core, t0, t1, draw.texture(frame, t2))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{t0, t1, t2, +current} = state
  draw.at(current, core, J.Frame.clear_background(frame, J.Color.RAYWHITE()), t0, t1, t2)

# The main loop's body; ImageRotate ran in the setup.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def rotated.upload(frame: J.Frame, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# ImageRotate of a loaded image, then LoadTextureFromImage (None when the
# file did not load or the rotation was refused).
def rotated(+libm: M.Libm, frame: J.Frame, +degrees: F32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: rotated.upload(frame, J.Surface.rotate_degrees_for(libm, image, degrees))


def setup.third(+core: J.Core, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, t2) = r
  (J.Core.set_target_fps(core, 60), (frame, State{t0, t1, t2, 0}))

def setup.second(+libm: M.Libm, +path: String, +core: J.Core, t0: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, t1) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(path),
    result => IO.pure(J.Core & (J.Frame & State), setup.third(core, t0, t1, rotated(libm, frame, F32.neg(90.0), result))))

def setup.first(+libm: M.Libm, +path: String, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, t0) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(path),
    result => setup.second(libm, path, core, t0, rotated(libm, frame, 90.0, result)))

# After InitWindow(800, 450): the logo loaded three times and rotated by 45,
# 90 and -90 degrees, uploaded as textures; SetTargetFPS(60).
def setup(+libm: M.Libm, dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  +path = dir ++ "resources/raylib_logo.png"
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(path),
    result => setup.first(libm, path, core, rotated(libm, frame, 45.0, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [textures] example - image rotate", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
