# raylib [textures] example - npatch drawing, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_npatch_drawing.c (zlib/libpng,
# Copyright (c) 2018-2025 Jorge A. Gomes (@overdev) and Ramon Santamaria
# (@raysan5)); see LICENSES/raylib.txt.
#
# Nine-patch and three-patch buttons stretched to the mouse. LoadTexture of
# a .png file is LoadImage (raylib's PNG loader, Surface.load_png here) and
# LoadTextureFromImage. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{texture: Maybe<J.Texture>, mouse: M.Vector2}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{texture, _} = state
  (core, State{texture, J.Input.get_mouse_position(core)})

def at_least(+value: F32, +low: F32) -> F32:
  Bool.pick(F32, (value < low : F32), low, value)

def at_most(+value: F32, +high: F32) -> F32:
  Bool.pick(F32, (value > high : F32), high, value)

def patch(+x: F32, +y: F32, +left: F32, +top: F32, +right: F32, +bottom: F32, +layout: F32) -> J.NPatchInfo:
  J.NPatchInfo{J.Rectangle{x, y, 64.0, 64.0}, left, top, right, bottom, layout}

def npatch(frame: J.Frame, texture: J.Texture, +info: J.NPatchInfo, +dest: J.Rectangle) -> J.Frame & J.Texture:
  J.Draw.texture_npatch(frame, texture, info, dest, M.Vector2.zero(), 0.0, J.Color.WHITE())

def draw.patches.d(+rv: J.Rectangle, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  (frame, texture) = r
  npatch(frame, texture, patch(0.0, 192.0, 6.0, 6.0, 6.0, 6.0, 1.0), rv)

def draw.patches.c(+rh: J.Rectangle, +rv: J.Rectangle, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  (frame, texture) = r
  draw.patches.d(rv, npatch(frame, texture, patch(0.0, 64.0, 8.0, 8.0, 8.0, 8.0, 2.0), rh))

def draw.patches.b(+r1: J.Rectangle, +rh: J.Rectangle, +rv: J.Rectangle, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  (frame, texture) = r
  draw.patches.c(rh, rv, npatch(frame, texture, patch(0.0, 0.0, 12.0, 40.0, 12.0, 12.0, 0.0), r1))

def draw.kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

# DrawRectangleLines(5, 88, 74, 266, BLUE) and the whole texture at (10, 93).
def draw.box(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  draw.kept(J.Draw.texture(J.Draw.rectangle_lines(frame, 5.0, 88.0, 74.0, 266.0, J.Color.BLUE()), texture, 10.0, 93.0, J.Color.WHITE()))

# The destination sizes follow the mouse, clamped as the example does
# (widths 1..300 for the nine-patches, at least 1 elsewhere).
def draw.loaded(frame: J.Frame, texture: J.Texture, +mouse: M.Vector2) -> J.Frame & Maybe<J.Texture>:
  M.Vector2{+mx, +my} = mouse
  +r1 = {J.Rectangle{480.0, 160.0, at_most(at_least((mx - 480.0 : F32), 1.0), 300.0), at_least((my - 160.0 : F32), 1.0)} : J.Rectangle}
  +r2 = {J.Rectangle{160.0, 160.0, at_most(at_least((mx - 160.0 : F32), 1.0), 300.0), at_least((my - 160.0 : F32), 1.0)} : J.Rectangle}
  +rh = {J.Rectangle{160.0, 93.0, at_least((mx - 160.0 : F32), 1.0), 32.0} : J.Rectangle}
  +rv = {J.Rectangle{92.0, 160.0, 32.0, at_least((my - 160.0 : F32), 1.0)} : J.Rectangle}
  draw.box(draw.patches.b(r1, rh, rv, npatch(frame, texture, patch(0.0, 128.0, 16.0, 16.0, 16.0, 16.0, 0.0), r2)))

def draw.texture(frame: J.Frame, texture: Maybe<J.Texture>, +mouse: M.Vector2) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: draw.loaded(frame, t, mouse)

def draw.done(+core: J.Core, +mouse: M.Vector2, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  f1 = J.Draw.text(frame, "TEXTURE", 15.0, 360.0, 10.0, J.Color.DARKGRAY())
  (core, (State{texture, mouse}, J.Draw.text(f1, "Move the mouse to stretch or shrink the n-patches", 10.0, 20.0, 20.0, J.Color.DARKGRAY())))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{texture, +mouse} = state
  draw.done(core, mouse, draw.texture(J.Frame.clear_background(frame, J.Color.RAYWHITE()), texture, mouse))

# No libm call beyond rotation 0: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{texture, M.Vector2.zero()}))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, M.Vector2.zero()}))
    case Done{image}: setup.uploaded(core, J.Texture.load_from_image(frame, image))

# After InitWindow(800, 450): LoadTexture("resources/ninepatch_button.png"), SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/ninepatch_button.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - npatch drawing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
