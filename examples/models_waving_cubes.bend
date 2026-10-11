# raylib [models] example - waving cubes, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_waving_cubes.c (zlib/libpng,
# Copyright (c) 2019-2025 Codecat (@codecat) and Ramon Santamaria (@raysan5));
# see LICENSES/raylib.txt.
#
# A grid of 15x15x15 cubes whose spacing and size breathe with sin(GetTime())
# while each cube is offset by sinf of its place and the time, colored by
# ColorFromHSV, under a camera circling with cos and sin of 0.3 times the
# time. sin and cos take the double: the libm profile's binary64 functions
# (M.Libm.sin64/cos64, docs/MATH.md), with its sinf (docs/SINCOSF.md) and the
# perspective's binary64 tan (docs/PERSPECTIVE.md). A frame is refused where
# the profile answers none of them. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# scale is (2.0f + (float)sin(time))*0.7f and wave (float)(time*4.0f) of the
# frame's GetTime(); valid: every libm call was answered.
type State is Type:
  State{valid: Bool, camera: J.Camera3D, scale: F32, wave: F32}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{30.0, 20.0, 30.0}, M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 70.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def narrowed(value: Maybe<M.Float64>) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{v}: M.Float64.to_f32(v)

# (float)sin(x) of a double.
def sine(value: Maybe<M.Float64>, +libm: M.Libm) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{v}: narrowed(M.Libm.sin64(libm, v))

# (float)cos(x) of a double.
def cosine(value: Maybe<M.Float64>, +libm: M.Libm) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{v}: narrowed(M.Libm.cos64(libm, v))

# camera.position.x = (float)cos(cameraTime)*40.0f; camera.position.z = (float)sin(cameraTime)*40.0f.
def circled(camera: J.Camera3D, +x: F32, +z: F32) -> J.Camera3D:
  J.Camera3D{_, target, up, fovy, projection} = camera
  J.Camera3D{M.Vector3{(x * 40.0 : F32), 20.0, (z * 40.0 : F32)}, target, up, fovy, projection}

def timed(swing: Maybe<F32>, x: Maybe<F32>, z: Maybe<F32>, wave: Maybe<F32>, +camera: J.Camera3D, +scale: F32, +old: F32) -> State:
  match swing x z wave:
    case Some{s} Some{cx} Some{cz} Some{w}: State{True{}, circled(camera, cx, cz), ((2.0 + s) * 0.7 : F32), w}
    case _ _ _ _: State{False{}, camera, scale, old}

def update.around(around: Maybe<M.Float64>, +libm: M.Libm, +time: M.Float64, +camera: J.Camera3D, +scale: F32, +wave: F32) -> State:
  match around:
    case None{}: State{False{}, camera, scale, wave}
    case Some{+a}: timed(sine(Some{time}, libm), cosine(Some{a}, libm), sine(Some{a}, libm), narrowed(M.Float64.internal.multiply(time, M.Float64{1074790400, 0})), camera, scale, wave)

# time = GetTime(); cameraTime = time*0.3 (0.3 and 4.0f as doubles).
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{_, +camera, +scale, +wave} = state
  (core, update.around(M.Float64.internal.multiply(J.Core.get_time(core), M.Float64{1070805811, 858993459}), libm, J.Core.get_time(core), camera, scale, wave))

# One cube: its place from its indices less half the blocks, spread by the
# scale and moved by its scatter; its size (2.4f - scale)*blockScale; its hue
# 18 degrees an index step.
def cube(scatter: Maybe<F32>, +x: U32, +y: U32, +z: U32, +scale: F32, frame: J.Frame) -> J.Frame:
  match scatter:
    case None{}: J.Frame.refuse(frame)
    case Some{+s}:
      J.Draw.cube(frame, M.Vector3{(((U32.to_f32(x) - 7.5) * (scale * 3.0)) + s : F32), (((U32.to_f32(y) - 7.5) * (scale * 2.0)) + s : F32), (((U32.to_f32(z) - 7.5) * (scale * 3.0)) + s : F32)},
        ((2.4 - scale) * (U32.to_f32((x + y + z : U32)) / 30.0) : F32), ((2.4 - scale) * (U32.to_f32((x + y + z : U32)) / 30.0) : F32), ((2.4 - scale) * (U32.to_f32((x + y + z : U32)) / 30.0) : F32),
        J.Color.from_hsv(U32.to_f32((((x + y + z) * 18) % 360 : U32)), 0.75, 0.9))

# scatter = sinf(blockScale*20.0f + (float)(time*4.0f)) with blockScale = (x + y + z)/30.0f, for x, y and z of 0..14 (z fastest).
def cubes(n: Nat, +i: U32, +libm: M.Libm, +scale: F32, +wave: F32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: cubes(p, (i + 1 : U32), libm, scale, wave, cube(M.Libm.sin(libm, (((U32.to_f32((((i / 225) + ((i / 15) % 15)) + (i % 15) : U32)) / 30.0) * 20.0) + wave : F32)),
      (i / 225 : U32), ((i / 15) % 15 : U32), (i % 15 : U32), scale, frame))

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps(result: Maybe<(J.Core & U32)>, state: State, frame: J.Frame, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# DrawGrid(10, 5.0f), the cubes, EndMode3D(), DrawFPS(10, 10).
def draw.at(valid: Bool, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +scale: F32, +wave: F32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid:
    case False{}: (core, (State{False{}, camera, scale, wave}, J.Frame.refuse(frame)))
    case True{}: draw.fps(J.Core.get_fps(core, J.Core.get_time(core)), State{True{}, camera, scale, wave},
      J.Frame.end_mode_3d(cubes(3375n, 0, libm, scale, wave, J.Draw.grid(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera), 10.0, 5.0))), core)

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +scale, +wave} = state
  draw.at(valid, libm, core, camera, scale, wave, frame)

# The main loop's body; libm is the profile of sin, cos, sinf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{True{}, start(), 0.0, 0.0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - waving cubes", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
