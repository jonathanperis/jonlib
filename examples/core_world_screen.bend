# raylib [core] example - world screen, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_world_screen.c (zlib/libpng,
# Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A third-person camera around a cube whose label follows its projection
# (GetWorldToScreen). The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md); a refused UpdateCamera or projection refuses the
# frame (and, for the camera, every later one). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{camera: +Maybe<J.Camera3D>, screen: +Maybe<M.Vector2>}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{10.0, 10.0, 10.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def projected.at(screen: Maybe<M.Vector2>) -> +Maybe<M.Vector2>:
  match screen:
    case None{}: None{}
    case Some{+p}: Some{p}

def projected(+libm: M.Libm, +core: J.Core, updated: Maybe<J.Camera3D>) -> State:
  match updated:
    case None{}: State{None{}, None{}}
    case Some{+c}: State{Some{c}, projected.at(J.Camera.world_to_screen_for(M.Uncontracted{}, libm, M.Vector3{0.0, 2.5, 0.0}, c, core))}

def update.camera(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> State:
  match camera:
    case None{}: State{None{}, None{}}
    case Some{+c}: projected(libm, core, J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_THIRD_PERSON()))

# UpdateCamera(CAMERA_THIRD_PERSON), then the screen position of (0, 2.5, 0).
def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+camera, _} = state
  (core, update.camera(libm, core, camera))

def draw.scene(+libm: M.Libm, camera: +Maybe<J.Camera3D>, frame: J.Frame) -> J.Frame:
  match camera:
    case None{}: J.Frame.refuse(frame)
    case Some{+c}:
      f1 = J.Frame.begin_mode_3d_for(libm, frame, c)
      f2 = J.Draw.cube_wires(J.Draw.cube(f1, M.Vector3.zero(), 2.0, 2.0, 2.0, J.Color.RED()), M.Vector3.zero(), 2.0, 2.0, 2.0, J.Color.MAROON())
      J.Frame.end_mode_3d(J.Draw.grid(f2, 10.0, 1.0))

# (int) of an F32, as an integral F32 and as a C int in a U32.
def int.f32(+x: F32) -> F32:
  F32.trunc(x)

def int.u32(+x: F32) -> U32:
  Bool.pick(U32, (x < 0.0 : F32), (0 - F32.to_u32(F32.neg(F32.trunc(x))) : U32), F32.to_u32(F32.trunc(x)))

def draw.coords(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 10.0, 20.0, J.Color.LIME())

def draw.enemy(width: Maybe<U32>, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{+w}: J.Draw.text(frame, "Enemy: 100/100", (int.f32(x) - U32.to_f32((w / 2 : U32)) : F32), int.f32(y), 20.0, J.Color.BLACK())

# The label at (int)x - MeasureText/2 and the coordinates as (int) values.
def draw.labels(screen: +Maybe<M.Vector2>, frame: J.Frame) -> J.Frame:
  match screen:
    case None{}: J.Frame.refuse(frame)
    case Some{+p}:
      M.Vector2{+x, +y} = p
      f1 = draw.enemy(J.Font.measure_text("Enemy: 100/100", 20.0), x, y, frame)
      draw.coords(J.Text.format("Cube position in screen space coordinates: [%i, %i]", [J.TextInt{int.u32(x)}, J.TextInt{int.u32(y)}]), f1)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +screen} = state
  f1 = draw.labels(screen, draw.scene(libm, camera, J.Frame.clear_background(frame, J.Color.RAYWHITE())))
  (core, (state, J.Draw.text(f1, "Text 2d should be always on top of the cube", 10.0, 40.0, 20.0, J.Color.GRAY())))

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf/atan2f and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): DisableCursor(), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{Some{start()}, Some{M.Vector2.zero()}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - world screen", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
