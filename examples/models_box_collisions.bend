# raylib [models] example - box collisions, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_box_collisions.c (zlib/libpng,
# Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The arrow keys move a player box (one key a frame, as raylib's else-if); it
# turns red while it touches the enemy box or sphere. The perspective needs
# the libm profile's binary64 tan (docs/PERSPECTIVE.md), and DrawSphereWires'
# ring angles (up to 450 degrees) its sinf/cosf (docs/SINCOSF.md). See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{x: F32, y: F32, z: F32, collision: Bool}

def camera() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.0, 10.0, 10.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def key(+core: J.Core, +code: U32) -> Bool:
  J.Input.is_key_down(core, code)

# The box of a position and a size, (position - size/2, position + size/2).
def box(+x: F32, +y: F32, +z: F32, +w: F32, +h: F32, +l: F32) -> J.BoundingBox:
  J.BoundingBox{M.Vector3{(x - w / 2.0 : F32), (y - h / 2.0 : F32), (z - l / 2.0 : F32)},
    M.Vector3{(x + w / 2.0 : F32), (y + h / 2.0 : F32), (z + l / 2.0 : F32)}}

def collides(+x: F32, +y: F32, +z: F32) -> Bool:
  +player = box(x, y, z, 1.0, 2.0, 1.0)
  J.Collision.boxes(player, box(F32.neg(4.0), 1.0, 0.0, 2.0, 2.0, 2.0)) || J.Collision.box_sphere(player, M.Vector3{4.0, 0.0, 0.0}, 1.5)

def moved(+core: J.Core, +x: F32, +y: F32, +z: F32) -> State:
  +right = key(core, J.KeyboardKey.KEY_RIGHT())
  +left = Bool.not(right) && key(core, J.KeyboardKey.KEY_LEFT())
  +down = Bool.not(right || left) && key(core, J.KeyboardKey.KEY_DOWN())
  +up = Bool.not(right || left || down) && key(core, J.KeyboardKey.KEY_UP())
  +nx = Bool.pick(F32, right, (x + 0.2 : F32), Bool.pick(F32, left, (x - 0.2 : F32), x))
  +nz = Bool.pick(F32, down, (z + 0.2 : F32), Bool.pick(F32, up, (z - 0.2 : F32), z))
  State{nx, y, nz, collides(nx, y, nz)}

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+x, +y, +z, _} = state
  (core, moved(core, x, y, z))

def scene(+libm: M.Libm, +state: State, frame: J.Frame) -> J.Frame:
  State{+x, +y, +z, +collision} = state
  f1 = J.Draw.cube(frame, M.Vector3{F32.neg(4.0), 1.0, 0.0}, 2.0, 2.0, 2.0, J.Color.GRAY())
  f2 = J.Draw.cube_wires(f1, M.Vector3{F32.neg(4.0), 1.0, 0.0}, 2.0, 2.0, 2.0, J.Color.DARKGRAY())
  f3 = J.Draw.sphere_for(libm, f2, M.Vector3{4.0, 0.0, 0.0}, 1.5, J.Color.GRAY())
  f4 = J.Draw.sphere_wires_for(libm, f3, M.Vector3{4.0, 0.0, 0.0}, 1.5, 16.0, 16.0, J.Color.DARKGRAY())
  f5 = J.Draw.cube_v(f4, M.Vector3{x, y, z}, M.Vector3{1.0, 2.0, 1.0}, Bool.pick(U32, collision, J.Color.RED(), J.Color.GREEN()))
  J.Draw.grid(f5, 10.0, 1.0)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  f1 = J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera())
  f2 = J.Frame.end_mode_3d(scene(libm, state, f1))
  f3 = J.Draw.text(f2, "Move player with arrow keys to collide", 220.0, 40.0, 20.0, J.Color.GRAY())
  draw.fps.done(state, f3, J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the profile of the perspective tan and the spheres' sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): the player at (0, 1, 2), no collision, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{0.0, 1.0, 2.0, False{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - box collisions", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
