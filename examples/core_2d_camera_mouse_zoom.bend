# raylib [core] example - 2d camera mouse zoom, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_2d_camera_mouse_zoom.c (zlib/libpng,
# Copyright (c) 2022-2025 Jeffery Myers (@JeffM2501)); see LICENSES/raylib.txt.
#
# A 2D camera dragged with the left button and zoomed around the mouse: by
# the wheel (mode 1) or by moving with the right button held (mode 2), in
# log scale, zoom = Clamp(expf(logf(zoom) + scale), 0.125, 64). expf and
# logf follow the libm profile (M.Libm.exp, M.Libm.log, docs/MATH.md), as
# do rlRotatef's and the circles' sinf/cosf (docs/SINCOSF.md); a value
# outside the profile, or a mouse position GetScreenToWorld2D or GetMouseX
# does not answer, refuses that frame and every later one. See
# docs/CAMERA.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# camera, zoomMode; ok: no refusal so far.
type State is Data:
  State{camera: J.Camera2D, mode: U32, ok: Bool}

def zoomed.exp(value: Maybe<F32>) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{+z}: Some{M.Math.clamp(z, 0.125, 64.0)}

def zoomed.log(+libm: M.Libm, +scale: F32, value: Maybe<F32>) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{+l}: zoomed.exp(M.Libm.exp(libm, (l + scale : F32)))

# Clamp(expf(logf(camera.zoom) + scale), 0.125f, 64.0f).
def zoomed(+libm: M.Libm, +zoom: F32, +scale: F32) -> Maybe<F32>:
  zoomed.log(libm, scale, M.Libm.log(libm, zoom))

def rezoomed.at(camera: J.Camera2D, zoom: Maybe<F32>) -> Maybe<J.Camera2D>:
  J.Camera2D{+offset, +target, +rotation, _} = camera
  match zoom:
    case None{}: None{}
    case Some{+z}: Some{J.Camera2D{offset, target, rotation, z}}

def zoom.of(camera: J.Camera2D) -> F32:
  J.Camera2D{_, _, _, +zoom} = camera
  zoom

def rezoomed.on(on: Bool, +libm: M.Libm, +scale: F32, +camera: J.Camera2D) -> Maybe<J.Camera2D>:
  match on:
    case False{}: Some{camera}
    case True{}: rezoomed.at(camera, zoomed(libm, zoom.of(camera), scale))

def rezoomed(+libm: M.Libm, +scale: F32, +on: Bool, camera: Maybe<J.Camera2D>) -> Maybe<J.Camera2D>:
  match camera:
    case None{}: None{}
    case Some{+c}: rezoomed.on(on, libm, scale, c)

# camera.offset = GetMousePosition(); camera.target = the world point under the mouse.
def anchored(+mouse: M.Vector2, camera: J.Camera2D, world: Maybe<M.Vector2>) -> Maybe<J.Camera2D>:
  J.Camera2D{_, _, +rotation, +zoom} = camera
  match world:
    case None{}: None{}
    case Some{+w}: Some{J.Camera2D{mouse, w, rotation, zoom}}

def anchor(on: Bool, +libm: M.Libm, +mouse: M.Vector2, +camera: J.Camera2D) -> Maybe<J.Camera2D>:
  match on:
    case False{}: Some{camera}
    case True{}: anchored(mouse, camera, J.Camera.screen_to_world_2d_for(M.Uncontracted{}, libm, mouse, camera))

# The left button drags the target by the mouse delta scaled by -1/zoom.
def panned(+on: Bool, camera: J.Camera2D, delta: M.Vector2) -> J.Camera2D:
  J.Camera2D{+offset, +target, +rotation, +zoom} = camera
  Bool.pick(J.Camera2D, on, J.Camera2D{offset, M.Vector2.add(target, M.Vector2.scale(delta, (F32.neg(1.0) / zoom : F32))), rotation, zoom}, J.Camera2D{offset, target, rotation, zoom})

def x.of(vector: M.Vector2) -> F32:
  M.Vector2{+x, _} = vector
  x

def update.done(+mode: U32, +ok: Bool, +old: J.Camera2D, camera: Maybe<J.Camera2D>) -> State:
  match camera:
    case None{}: State{old, mode, False{}}
    case Some{+c}: State{c, mode, ok}

# Mode 0: a wheel move anchors the camera at the mouse and zooms by 0.2*wheel. Mode 1: a right press anchors it and
# the right button held zooms by 0.005 of the mouse's horizontal move.
def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+camera, +mode, +ok} = state
  +next = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_ONE()), 0, Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_TWO()), 1, mode))
  +mouse = J.Input.get_mouse_position(core)
  +moved = panned(J.Input.is_mouse_button_down(core, J.MouseButton.MOUSE_BUTTON_LEFT()), camera, J.Input.get_mouse_delta(core))
  +wheel = J.Input.get_mouse_wheel_move(core)
  +turned = Bool.not(F32.is_eq(wheel, 0.0))
  +right = J.MouseButton.MOUSE_BUTTON_RIGHT()
  (core, update.done(next, ok, camera, Bool.pick(Maybe<J.Camera2D>, U32.is_eq(next, 0), rezoomed(libm, (0.2 * wheel : F32), turned, anchor(turned, libm, mouse, moved)),
    rezoomed(libm, (0.005 * x.of(J.Input.get_mouse_delta(core)) : F32), J.Input.is_mouse_button_down(core, right), anchor(J.Input.is_mouse_button_pressed(core, right), libm, mouse, moved)))))

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def unloaded(r: J.Frame & J.Font) -> J.Frame:
  (frame, font) = r
  J.Font.unload(frame, font)

# DrawTextEx(GetFontDefault(), TextFormat("[%i, %i]", GetMouseX(), GetMouseY()), mouse + (-44, -24), 20, 2, BLACK).
def coordinates(text: Maybe<String>, +mouse: M.Vector2, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: unloaded(J.Draw.text_ex(frame, J.Font.default(), t, M.Vector2.add(mouse, M.Vector2{F32.neg(44.0), F32.neg(24.0)}), 20.0, 2.0, J.Color.BLACK()))

def position.text(x: Maybe<U32>, y: Maybe<U32>) -> Maybe<String>:
  match x y:
    case Some{+a} Some{+b}: J.Text.format("[%i, %i]", [J.TextInt{a}, J.TextInt{b}])
    case _ _: None{}

def hint(wheel: Bool, frame: J.Frame) -> J.Frame:
  match wheel:
    case True{}: J.Draw.text(frame, "Mouse left button drag to move, mouse wheel to zoom", 20.0, 50.0, 20.0, J.Color.DARKGRAY())
    case False{}: J.Draw.text(frame, "Mouse left button drag to move, mouse press and move to zoom", 20.0, 50.0, 20.0, J.Color.DARKGRAY())

# The 3D grid turned into the XY plane (rlTranslatef(0, 25*50, 0), rlRotatef(90, 1, 0, 0), DrawGrid(100, 50)) and a
# reference circle under the camera; the mouse's circle and coordinates and the texts over it.
def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +mode, +ok} = state
  +mouse = J.Input.get_mouse_position(core)
  f1 = J.Rlgl.push_matrix(J.Frame.begin_mode_2d_for(libm, J.Frame.clear_background(checked(ok, frame), J.Color.RAYWHITE()), camera))
  f2 = J.Rlgl.pop_matrix(J.Draw.grid(J.Rlgl.rotatef_for(libm, J.Rlgl.translatef(f1, 0.0, (25.0 * 50.0 : F32), 0.0), 90.0, 1.0, 0.0, 0.0), 100.0, 50.0))
  f3 = J.Frame.end_mode_2d(J.Draw.circle_for(libm, f2, (800.0 / 2.0 : F32), F32.trunc((450.0 / 2.0 : F32)), 50.0, J.Color.MAROON()))
  f4 = coordinates(position.text(J.Input.get_mouse_x(core), J.Input.get_mouse_y(core)), mouse, J.Draw.circle_v_for(libm, f3, mouse, 4.0, J.Color.DARKGRAY()))
  (core, (state, hint(U32.is_eq(mode, 0), J.Draw.text(f4, "[1][2] Select mouse zoom mode (Wheel or Move)", 20.0, 20.0, 20.0, J.Color.DARKGRAY()))))

# The main loop's body; libm is the profile of expf, logf, rlRotatef and the circles.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): camera = { 0 } with zoom 1, zoomMode 0, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Camera2D{M.Vector2.zero(), M.Vector2.zero(), 0.0, 1.0}, 0, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - 2d camera mouse zoom", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
