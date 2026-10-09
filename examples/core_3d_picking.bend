# raylib [core] example - 3d picking, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_3d_picking.c (zlib/libpng,
# Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Click the cube to select it (GetScreenToWorldRay and GetRayCollisionBox);
# the right button toggles first-person camera controls. The perspective
# needs the libm profile's binary64 tan (docs/PERSPECTIVE.md); a refused
# camera update or ray refuses that frame and every later one. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{camera: J.Camera3D, ray: J.Ray, hit: Bool, ok: Bool}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{10.0, 10.0, 10.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# The cube at (0, 1, 0) of size 2: its box from position -/+ size/2.
def box() -> J.BoundingBox:
  J.BoundingBox{M.Vector3{(0.0 - 2.0 / 2.0 : F32), (1.0 - 2.0 / 2.0 : F32), (0.0 - 2.0 / 2.0 : F32)},
    M.Vector3{(0.0 + 2.0 / 2.0 : F32), (1.0 + 2.0 / 2.0 : F32), (0.0 + 2.0 / 2.0 : F32)}}

def picked.hit(collision: Maybe<J.RayCollision>) -> Maybe<Bool>:
  match collision:
    case None{}: None{}
    case Some{J.RayCollision{+hit, _, _, _}}: Some{hit}

def picked.with(+r: J.Ray, hit: Maybe<Bool>) -> Maybe<(J.Ray & Bool)>:
  match hit:
    case None{}: None{}
    case Some{+h}: Some{(r, h)}

def picked.ray(+libm: M.Libm, ray: Maybe<J.Ray>) -> Maybe<(J.Ray & Bool)>:
  match ray:
    case None{}: None{}
    case Some{+r}: picked.with(r, picked.hit(J.Collision.ray_box_for(M.Uncontracted{}, libm, r, box())))

def clicked.done(+camera: J.Camera3D, +ok: Bool, result: Maybe<(J.Ray & Bool)>) -> State:
  match result:
    case None{}: State{camera, J.Ray{M.Vector3.zero(), M.Vector3.zero()}, False{}, False{}}
    case Some{(+r, +h)}: State{camera, r, h, ok}

# A left click casts a new ray when nothing is selected, else deselects.
def clicked(click: Bool, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +ray: J.Ray, +hit: Bool, +ok: Bool) -> State:
  match click:
    case False{}: State{camera, ray, hit, ok}
    case True{}:
      Bool.pick(State, hit, State{camera, ray, False{}, ok},
        clicked.done(camera, ok, picked.ray(libm, J.Camera.screen_to_world_ray_for(M.Uncontracted{}, libm, J.Input.get_mouse_position(core), camera, core))))

def camera.updated(+libm: M.Libm, +core: J.Core, +ray: J.Ray, +hit: Bool, +ok: Bool, +camera: J.Camera3D, updated: Maybe<J.Camera3D>) -> J.Core & State:
  match updated:
    case None{}: (core, State{camera, ray, hit, False{}})
    case Some{+c}:
      +pressed = J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_RIGHT())
      +hidden = J.Input.is_cursor_hidden(core)
      +core2 = Bool.pick(J.Core, pressed, Bool.pick(J.Core, hidden, J.Input.enable_cursor(core), J.Input.disable_cursor(core)), core)
      (core2, clicked(J.Input.is_mouse_button_pressed(core2, J.MouseButton.MOUSE_BUTTON_LEFT()), libm, core2, c, ray, hit, ok))

def camera.update(hidden: Bool, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D) -> Maybe<J.Camera3D>:
  match hidden:
    case False{}: Some{camera}
    case True{}: J.Camera.update_for(M.Uncontracted{}, libm, core, camera, J.CameraMode.CAMERA_FIRST_PERSON())

def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+camera, +ray, +hit, +ok} = state
  camera.updated(libm, core, ray, hit, ok, camera, camera.update(J.Input.is_cursor_hidden(core), libm, core, camera))

def draw.cube(hit: Bool, frame: J.Frame) -> J.Frame:
  match hit:
    case True{}:
      f1 = J.Draw.cube_wires(J.Draw.cube(frame, M.Vector3{0.0, 1.0, 0.0}, 2.0, 2.0, 2.0, J.Color.RED()), M.Vector3{0.0, 1.0, 0.0}, 2.0, 2.0, 2.0, J.Color.MAROON())
      J.Draw.cube_wires(f1, M.Vector3{0.0, 1.0, 0.0}, (2.0 + 0.2 : F32), (2.0 + 0.2 : F32), (2.0 + 0.2 : F32), J.Color.GREEN())
    case False{}: J.Draw.cube_wires(J.Draw.cube(frame, M.Vector3{0.0, 1.0, 0.0}, 2.0, 2.0, 2.0, J.Color.GRAY()), M.Vector3{0.0, 1.0, 0.0}, 2.0, 2.0, 2.0, J.Color.DARKGRAY())

def draw.selected.at(width: Maybe<U32>, frame: J.Frame) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{+w}: J.Draw.text(frame, "BOX SELECTED", U32.to_f32(((800 - w) / 2 : U32)), F32.trunc((450.0 * 0.1 : F32)), 30.0, J.Color.GREEN())

def draw.selected(hit: Bool, frame: J.Frame) -> J.Frame:
  match hit:
    case False{}: frame
    case True{}: draw.selected.at(J.Font.measure_text("BOX SELECTED", 30.0), frame)

def draw.checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def draw.fps.at(+state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +ray, +hit, +ok} = state
  f1 = J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(draw.checked(ok, frame), J.Color.RAYWHITE()), camera)
  f2 = J.Frame.end_mode_3d(J.Draw.grid(J.Draw.ray(draw.cube(hit, f1), ray, J.Color.MAROON()), 10.0, 1.0))
  f3 = draw.selected(hit, J.Draw.text(f2, "Try clicking on the box with your mouse!", 240.0, 10.0, 20.0, J.Color.DARKGRAY()))
  f4 = J.Draw.text(f3, "Right click mouse to toggle camera controls", 10.0, 430.0, 10.0, J.Color.GRAY())
  draw.fps.done(state, f4, J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the profile of UpdateCamera, the ray box test and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): a zero ray and no selection, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{start(), J.Ray{M.Vector3.zero(), M.Vector3.zero()}, False{}, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - 3d picking", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
