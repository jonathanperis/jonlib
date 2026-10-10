# raylib [models] example - orthographic projection, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_orthographic_projection.c
# (zlib/libpng, Copyright (c) 2018-2025 Max Danielsson (@autious) and Ramon
# Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The geometric shapes scene; SPACE switches the camera between perspective
# (fovy 45) and orthographic (width 10). The perspective needs the libm
# profile's binary64 tan (docs/PERSPECTIVE.md), and DrawSphereWires' ring
# angles (up to 450 degrees) its sinf/cosf (docs/SINCOSF.md). See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{ortho: Bool}

def camera(ortho: Bool) -> J.Camera3D:
  match ortho:
    case True{}: J.Camera3D{M.Vector3{0.0, 10.0, 10.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 10.0, J.CameraProjection.CAMERA_ORTHOGRAPHIC()}
    case False{}: J.Camera3D{M.Vector3{0.0, 10.0, 10.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+ortho} = state
  (core, State{Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), Bool.not(ortho), ortho)})

def shapes(+libm: M.Libm, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.cube(frame, M.Vector3{F32.neg(4.0), 0.0, 2.0}, 2.0, 5.0, 2.0, J.Color.RED())
  f2 = J.Draw.cube_wires(f1, M.Vector3{F32.neg(4.0), 0.0, 2.0}, 2.0, 5.0, 2.0, J.Color.GOLD())
  f3 = J.Draw.cube_wires(f2, M.Vector3{F32.neg(4.0), 0.0, F32.neg(2.0)}, 3.0, 6.0, 2.0, J.Color.MAROON())
  f4 = J.Draw.sphere_for(libm, f3, M.Vector3{F32.neg(1.0), 0.0, F32.neg(2.0)}, 1.0, J.Color.GREEN())
  f5 = J.Draw.sphere_wires_for(libm, f4, M.Vector3{1.0, 0.0, 2.0}, 2.0, 16.0, 16.0, J.Color.LIME())
  f6 = J.Draw.cylinder_for(libm, f5, M.Vector3{4.0, 0.0, F32.neg(2.0)}, 1.0, 2.0, 3.0, 4.0, J.Color.SKYBLUE())
  f7 = J.Draw.cylinder_wires_for(libm, f6, M.Vector3{4.0, 0.0, F32.neg(2.0)}, 1.0, 2.0, 3.0, 4.0, J.Color.DARKBLUE())
  f8 = J.Draw.cylinder_wires_for(libm, f7, M.Vector3{4.5, F32.neg(1.0), 2.0}, 1.0, 1.0, 2.0, 6.0, J.Color.BROWN())
  f9 = J.Draw.cylinder_for(libm, f8, M.Vector3{1.0, 0.0, F32.neg(4.0)}, 0.0, 1.5, 3.0, 8.0, J.Color.GOLD())
  f10 = J.Draw.cylinder_wires_for(libm, f9, M.Vector3{1.0, 0.0, F32.neg(4.0)}, 0.0, 1.5, 3.0, 8.0, J.Color.PINK())
  J.Draw.grid(f10, 10.0, 1.0)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def label(ortho: Bool) -> String:
  match ortho:
    case True{}: "ORTHOGRAPHIC"
    case False{}: "PERSPECTIVE"

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+ortho} = state
  f1 = J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera(ortho))
  f2 = J.Frame.end_mode_3d(shapes(libm, f1))
  f3 = J.Draw.text(f2, "Press Spacebar to switch camera type", 10.0, (450.0 - 30.0 : F32), 20.0, J.Color.DARKGRAY())
  f4 = J.Draw.text(f3, label(ortho), 10.0, 40.0, 20.0, J.Color.BLACK())
  draw.fps.done(state, f4, J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the profile of the perspective tan and the shapes' sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): the perspective camera, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{False{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - orthographic projection", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
