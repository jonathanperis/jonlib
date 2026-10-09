# raylib [core] example - 3d camera mode, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_3d_camera_mode.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A cube and a grid seen through a perspective camera. BeginMode3D's
# perspective needs the libm profile's binary64 tan (docs/PERSPECTIVE.md):
# under M.AppleLibm{} the frame is refused. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{}

def camera() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.0, 10.0, 10.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def draw.fps.at(+state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  f1 = J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera())
  f2 = J.Draw.cube_wires(J.Draw.cube(f1, M.Vector3.zero(), 2.0, 2.0, 2.0, J.Color.RED()), M.Vector3.zero(), 2.0, 2.0, 2.0, J.Color.MAROON())
  f3 = J.Frame.end_mode_3d(J.Draw.grid(f2, 10.0, 1.0))
  f4 = J.Draw.text(f3, "Welcome to the third dimension!", 10.0, 40.0, 20.0, J.Color.DARKGRAY())
  draw.fps.done(state, f4, J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the profile of BeginMode3D's tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - 3d camera mode", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
