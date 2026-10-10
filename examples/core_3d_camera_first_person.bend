# raylib [core] example - 3d camera first person, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_3d_camera_first_person.c
# (zlib/libpng, Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A walled plane with twenty random columns seen through UpdateCamera's four
# modes (keys 1 to 4); P switches to an orthographic view set up with
# CameraYaw and CameraPitch, and back. raylib seeds GetRandomValue from
# time(NULL) in InitWindow; here the seed is a setup argument
# (docs/DRIVER.md). The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md) and the camera its sinf/cosf (docs/SINCOSF.md,
# docs/CAMERA.md); a camera step Jonlib refuses refuses the frame and every
# later one.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Column is Data:
  Column{position: M.Vector3, height: F32, color: U32}

type Cam is Data:
  Cam{valid: Bool, camera: J.Camera3D, mode: U32}

type State is Data:
  State{cam: Cam, columns: +List<Column>}

def up() -> M.Vector3:
  M.Vector3{0.0, 1.0, 0.0}

# A mode key: cameraMode = mode; camera.up = (0, 1, 0).
def moded(+pressed: Bool, +to: U32, +cam: Cam) -> Cam:
  Cam{+valid, +camera, _} = cam
  J.Camera3D{+position, +target, _, +fovy, +projection} = camera
  Bool.pick(Cam, pressed, Cam{valid, J.Camera3D{position, target, up(), fovy, projection}, to}, cam)

def tilted.done(+valid: Bool, camera: Maybe<J.Camera3D>) -> Cam:
  match camera:
    case None{}: Cam{False{}, J.Camera3D{M.Vector3{0.0, 2.0, F32.neg(100.0)}, M.Vector3{0.0, 2.0, 0.0}, up(), 20.0, J.CameraProjection.CAMERA_ORTHOGRAPHIC()}, J.CameraMode.CAMERA_THIRD_PERSON()}
    case Some{+c}: Cam{valid, c, J.CameraMode.CAMERA_THIRD_PERSON()}

# CameraPitch(&camera, -45*DEG2RAD, true, true, false).
def tilted(+libm: M.Libm, yawed: Maybe<J.Camera3D>) -> Maybe<J.Camera3D>:
  match yawed:
    case None{}: None{}
    case Some{+c}: J.Camera.pitch_for(M.Uncontracted{}, libm, c, (F32.neg(45.0) * M.Math.DEG2RAD() : F32), True{}, True{}, False{})

# P from perspective: the orthographic third-person view from (0, 2, -100) with fovy 20, after
# CameraYaw(&camera, -135*DEG2RAD, true) and the pitch; from orthographic: back to perspective at (0, 2, 10).
def switched.to(+libm: M.Libm, +valid: Bool, +cam: Cam, projection: U32) -> Cam:
  match projection:
    case 0: tilted.done(valid, tilted(libm, J.Camera.yaw_for(M.Uncontracted{}, libm,
      J.Camera3D{M.Vector3{0.0, 2.0, F32.neg(100.0)}, M.Vector3{0.0, 2.0, 0.0}, up(), 20.0, J.CameraProjection.CAMERA_ORTHOGRAPHIC()}, (F32.neg(135.0) * M.Math.DEG2RAD() : F32), True{})))
    case 1: Cam{valid, J.Camera3D{M.Vector3{0.0, 2.0, 10.0}, M.Vector3{0.0, 2.0, 0.0}, up(), 60.0, J.CameraProjection.CAMERA_PERSPECTIVE()}, J.CameraMode.CAMERA_THIRD_PERSON()}
    case _: cam

def switched(pressed: Bool, +libm: M.Libm, +cam: Cam) -> Cam:
  match pressed:
    case False{}: cam
    case True{}:
      Cam{+valid, +camera, _} = cam
      J.Camera3D{_, _, _, _, +projection} = camera
      switched.to(libm, valid, cam, projection)

def moved.done(+cam: Cam, updated: Maybe<J.Camera3D>) -> Cam:
  Cam{+valid, +camera, +mode} = cam
  match updated:
    case None{}: Cam{False{}, camera, mode}
    case Some{+c}: Cam{valid, c, mode}

# UpdateCamera(&camera, cameraMode).
def moved(+libm: M.Libm, +core: J.Core, +cam: Cam) -> Cam:
  Cam{_, +camera, +mode} = cam
  moved.done(cam, J.Camera.update_for(M.Uncontracted{}, libm, core, camera, mode))

def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+cam, +columns} = state
  +c1 = moded(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_ONE()), J.CameraMode.CAMERA_FREE(), cam)
  +c2 = moded(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_TWO()), J.CameraMode.CAMERA_FIRST_PERSON(), c1)
  +c3 = moded(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_THREE()), J.CameraMode.CAMERA_THIRD_PERSON(), c2)
  +c4 = moded(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_FOUR()), J.CameraMode.CAMERA_ORBITAL(), c3)
  (core, State{moved(libm, core, switched(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_P()), libm, c4)), columns})

# DrawCube(positions[i], 2, heights[i], 2, colors[i]) and its MAROON wires.
def pillars(columns: +List<Column>, frame: J.Frame) -> J.Frame:
  match columns:
    case Nil{}: frame
    case Con{+column, rest}:
      Column{+position, +height, +color} = column
      pillars(rest, J.Draw.cube_wires(J.Draw.cube(frame, position, 2.0, height, 2.0, color), position, 2.0, height, 2.0, J.Color.MAROON()))

# In third person the target shows as a purple cube.
def marker(third: Bool, +target: M.Vector3, frame: J.Frame) -> J.Frame:
  match third:
    case False{}: frame
    case True{}: J.Draw.cube_wires(J.Draw.cube(frame, target, 0.5, 0.5, 0.5, J.Color.PURPLE()), target, 0.5, 0.5, 0.5, J.Color.DARKPURPLE())

def scene(+libm: M.Libm, +camera: J.Camera3D, +mode: U32, +columns: +List<Column>, frame: J.Frame) -> J.Frame:
  J.Camera3D{_, +target, _, _, _} = camera
  f1 = J.Draw.plane(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera), M.Vector3.zero(), M.Vector2{32.0, 32.0}, J.Color.LIGHTGRAY())
  f2 = J.Draw.cube(f1, M.Vector3{F32.neg(16.0), 2.5, 0.0}, 1.0, 5.0, 32.0, J.Color.BLUE())
  f3 = J.Draw.cube(f2, M.Vector3{16.0, 2.5, 0.0}, 1.0, 5.0, 32.0, J.Color.LIME())
  f4 = J.Draw.cube(f3, M.Vector3{0.0, 2.5, 16.0}, 32.0, 5.0, 1.0, J.Color.GOLD())
  J.Frame.end_mode_3d(marker(U32.is_eq(mode, J.CameraMode.CAMERA_THIRD_PERSON()), target, pillars(columns, f4)))

def label(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 610.0, y, 10.0, J.Color.BLACK())

def mode.name(mode: U32) -> String:
  match mode:
    case 1: "FREE"
    case 3: "FIRST_PERSON"
    case 4: "THIRD_PERSON"
    case 2: "ORBITAL"
    case _: "CUSTOM"

def projection.name(projection: U32) -> String:
  match projection:
    case 0: "PERSPECTIVE"
    case 1: "ORTHOGRAPHIC"
    case _: "CUSTOM"

def triple(+format: String, +v: M.Vector3) -> Maybe<String>:
  M.Vector3{+x, +y, +z} = v
  J.Text.format(format, [J.TextFloat{x}, J.TextFloat{y}, J.TextFloat{z}])

def status(+camera: J.Camera3D, +mode: U32, frame: J.Frame) -> J.Frame:
  J.Camera3D{+position, +target, +upward, _, +projection} = camera
  f1 = J.Draw.rectangle_lines(J.Draw.rectangle(frame, 600.0, 5.0, 195.0, 100.0, J.Color.with_alpha(J.Color.SKYBLUE(), 0.5)), 600.0, 5.0, 195.0, 100.0, J.Color.BLUE())
  f2 = J.Draw.text(f1, "Camera status:", 610.0, 15.0, 10.0, J.Color.BLACK())
  f3 = label(J.Text.format("- Mode: %s", [J.TextString{mode.name(mode)}]), 30.0, f2)
  f4 = label(J.Text.format("- Projection: %s", [J.TextString{projection.name(projection)}]), 45.0, f3)
  f5 = label(triple("- Position: (%06.3f, %06.3f, %06.3f)", position), 60.0, f4)
  label(triple("- Up: (%06.3f, %06.3f, %06.3f)", upward), 90.0, label(triple("- Target: (%06.3f, %06.3f, %06.3f)", target), 75.0, f5))

def controls(frame: J.Frame) -> J.Frame:
  f1 = J.Draw.rectangle_lines(J.Draw.rectangle(frame, 5.0, 5.0, 330.0, 100.0, J.Color.with_alpha(J.Color.SKYBLUE(), 0.5)), 5.0, 5.0, 330.0, 100.0, J.Color.BLUE())
  f2 = J.Draw.text(f1, "Camera controls:", 15.0, 15.0, 10.0, J.Color.BLACK())
  f3 = J.Draw.text(f2, "- Move keys: W, A, S, D, Space, Left-Ctrl", 15.0, 30.0, 10.0, J.Color.BLACK())
  f4 = J.Draw.text(f3, "- Look around: arrow keys or mouse", 15.0, 45.0, 10.0, J.Color.BLACK())
  f5 = J.Draw.text(f4, "- Camera mode keys: 1, 2, 3, 4", 15.0, 60.0, 10.0, J.Color.BLACK())
  f6 = J.Draw.text(f5, "- Zoom keys: num-plus, num-minus or mouse scroll", 15.0, 75.0, 10.0, J.Color.BLACK())
  J.Draw.text(f6, "- Camera projection key: P", 15.0, 90.0, 10.0, J.Color.BLACK())

def draw.valid(valid: Bool, +libm: M.Libm, +camera: J.Camera3D, +mode: U32, +columns: +List<Column>, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}: status(camera, mode, controls(scene(libm, camera, mode, columns, frame)))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+cam, +columns} = state
  Cam{+valid, +camera, +mode} = cam
  (core, (state, draw.valid(valid, libm, camera, mode, columns, frame)))

# The main loop's body; libm is the profile of the camera's sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def column.green(+height: F32, +x: F32, +z: F32, +red: F32, done: +List<Column>, draw: J.Random.State & F32) -> J.Random.State & +List<Column>:
  (rng, +green) = draw
  (rng, Con{Column{M.Vector3{x, (height / 2.0 : F32), z}, height, J.Color.rgba(F32.to_u32(red), F32.to_u32(green), 30, 255)}, done})

def column.red(+height: F32, +x: F32, +z: F32, done: +List<Column>, draw: J.Random.State & F32) -> J.Random.State & +List<Column>:
  (rng, +red) = draw
  column.green(height, x, z, red, done, J.Random.value(rng, 10.0, 55.0))

def column.z(+height: F32, +x: F32, done: +List<Column>, draw: J.Random.State & F32) -> J.Random.State & +List<Column>:
  (rng, +z) = draw
  column.red(height, x, z, done, J.Random.value(rng, 20.0, 255.0))

def column.x(+height: F32, done: +List<Column>, draw: J.Random.State & F32) -> J.Random.State & +List<Column>:
  (rng, +x) = draw
  column.z(height, x, done, J.Random.value(rng, F32.neg(15.0), 15.0))

def column.height(done: +List<Column>, draw: J.Random.State & F32) -> J.Random.State & +List<Column>:
  (rng, +height) = draw
  column.x(height, done, J.Random.value(rng, F32.neg(15.0), 15.0))

# heights[i] = GetRandomValue(1, 12); positions[i] = (GetRandomValue(-15, 15), heights[i]/2, GetRandomValue(-15, 15));
# colors[i] = (GetRandomValue(20, 255), GetRandomValue(10, 55), 30, 255).
def column(acc: J.Random.State & +List<Column>) -> J.Random.State & +List<Column>:
  (rng, done) = acc
  column.height(done, J.Random.value(rng, 1.0, 12.0))

def columns(n: Nat, acc: J.Random.State & +List<Column>) -> J.Random.State & +List<Column>:
  match n:
    case 0n: acc
    case 1n+p: columns(p, column(acc))

def columns.made(r: J.Random.State & +List<Column>) -> +List<Column>:
  (_, reversed) = r
  List.reverse(&2, Column, reversed)

# After InitWindow(800, 450) and SetRandomSeed(seed): the camera at (0, 2, 4) in first person, the
# columns, DisableCursor(), SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{
    Cam{True{}, J.Camera3D{M.Vector3{0.0, 2.0, 4.0}, M.Vector3{0.0, 2.0, 0.0}, up(), 60.0, J.CameraProjection.CAMERA_PERSPECTIVE()}, J.CameraMode.CAMERA_FIRST_PERSON()},
    columns.made(columns(20n, (J.Random.seed(seed), Nil{})))}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - 3d camera first person", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
