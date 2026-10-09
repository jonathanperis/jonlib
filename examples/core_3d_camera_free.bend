# raylib [core] example - 3d camera free, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_3d_camera_free.c (zlib/libpng,
# Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# UpdateCamera(CAMERA_FREE): the mouse turns the camera, the wheel zooms, the
# middle button pans, Z looks at the origin. The perspective needs the libm
# profile's binary64 tan (docs/PERSPECTIVE.md); an UpdateCamera Jonlib
# refuses (a sinf/cosf argument outside the profile) refuses that frame and
# every later one. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{camera: +Maybe<J.Camera3D>}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{10.0, 10.0, 10.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# Z: camera.target = (0, 0, 0).
def targeted(+core: J.Core, updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}:
      J.Camera3D{+p, _, +u, +f, +k} = c
      Bool.pick(+Maybe<J.Camera3D>, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_Z()), Some{J.Camera3D{p, M.Vector3.zero(), u, f, k}}, Some{c})

def update.camera(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: targeted(core, J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_FREE()))

def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+camera} = state
  (core, State{update.camera(libm, core, camera)})

def draw.scene(+libm: M.Libm, camera: +Maybe<J.Camera3D>, frame: J.Frame) -> J.Frame:
  match camera:
    case None{}: J.Frame.refuse(frame)
    case Some{+c}:
      f1 = J.Frame.begin_mode_3d_for(libm, frame, c)
      f2 = J.Draw.cube_wires(J.Draw.cube(f1, M.Vector3.zero(), 2.0, 2.0, 2.0, J.Color.RED()), M.Vector3.zero(), 2.0, 2.0, 2.0, J.Color.MAROON())
      J.Frame.end_mode_3d(J.Draw.grid(f2, 10.0, 1.0))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera} = state
  f1 = draw.scene(libm, camera, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = J.Draw.rectangle_lines(J.Draw.rectangle(f1, 10.0, 10.0, 320.0, 93.0, J.Color.with_alpha(J.Color.SKYBLUE(), 0.5)), 10.0, 10.0, 320.0, 93.0, J.Color.BLUE())
  f3 = J.Draw.text(f2, "Free camera default controls:", 20.0, 20.0, 10.0, J.Color.BLACK())
  f4 = J.Draw.text(f3, "- Mouse Wheel to Zoom in-out", 40.0, 40.0, 10.0, J.Color.DARKGRAY())
  f5 = J.Draw.text(f4, "- Mouse Wheel Pressed to Pan", 40.0, 60.0, 10.0, J.Color.DARKGRAY())
  (core, (state, J.Draw.text(f5, "- Z to zoom to (0, 0, 0)", 40.0, 80.0, 10.0, J.Color.DARKGRAY())))

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf/atan2f and BeginMode3D's tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): DisableCursor(), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{Some{start()}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - 3d camera free", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
