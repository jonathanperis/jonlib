# raylib [models] example - basic voxel, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_basic_voxel.c (zlib/libpng,
# Copyright (c) 2025 Tim Little (@timlittle)); see LICENSES/raylib.txt.
#
# An 8x8x8 block of cubes seen from a first-person camera; a left click
# removes the voxel the screen center points at. The perspective needs the
# libm profile's binary64 tan (docs/PERSPECTIVE.md); a refused camera update,
# ray or box test refuses that frame and every later one. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# voxels[x][y][z] as 512 flags in x, y, z order.
type State is Data:
  State{camera: J.Camera3D, voxels: +List<Bool>, model: J.Model, ok: Bool}

def full(n: Nat) -> +List<Bool>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{True{}, full(p)}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{F32.neg(2.0), 0.0, F32.neg(2.0)}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# cubeModel.materials[0].maps[MATERIAL_MAP_DIFFUSE].color = BEIGE.
def beige.maps(maps: +List<J.MaterialMap>) -> +List<J.MaterialMap>:
  match maps:
    case Con{J.MaterialMap{+texture, _, +value}, rest}: Con{J.MaterialMap{texture, J.Color.BEIGE(), value}, rest}
    case Nil{}: Nil{}

def beige.materials(materials: +List<J.Material>) -> +List<J.Material>:
  match materials:
    case Con{J.Material{+maps, +params}, rest}: Con{J.Material{beige.maps(maps), params}, rest}
    case Nil{}: Nil{}

def beige(+model: J.Model) -> J.Model:
  J.Model{+transform, +meshes, +materials, +ids} = model
  J.Model{transform, meshes, beige.materials(materials), ids}

def position(+i: U32) -> M.Vector3:
  M.Vector3{U32.to_f32((i / 64 : U32)), U32.to_f32(((i / 8) % 8 : U32)), U32.to_f32((i % 8 : U32))}

def voxel.box(+p: M.Vector3) -> J.BoundingBox:
  M.Vector3{+x, +y, +z} = p
  J.BoundingBox{M.Vector3{(x - 0.5 : F32), (y - 0.5 : F32), (z - 0.5 : F32)}, M.Vector3{(x + 0.5 : F32), (y + 0.5 : F32), (z + 0.5 : F32)}}

# The closest hit so far: (distance, index), 512 for none; None once a box
# test is refused.
type Closest is Data:
  Closest{distance: F32, index: U32}

def closest.hit(+i: U32, +bd: F32, +bi: U32, collision: Maybe<J.RayCollision>) -> Maybe<Closest>:
  match collision:
    case None{}: None{}
    case Some{J.RayCollision{+hit, +d, _, _}}: Bool.pick(Maybe<Closest>, hit && (d < bd : F32), Some{Closest{d, i}}, Some{Closest{bd, bi}})

def closest.step(+libm: M.Libm, +ray: J.Ray, +i: U32, +on: Bool, best: Maybe<Closest>) -> Maybe<Closest>:
  match best:
    case None{}: None{}
    case Some{Closest{+bd, +bi}}: Bool.pick(Maybe<Closest>, on, closest.hit(i, bd, bi, J.Collision.ray_box_for(M.Uncontracted{}, libm, ray, voxel.box(position(i)))), Some{Closest{bd, bi}})

def closest(voxels: +List<Bool>, +libm: M.Libm, +ray: J.Ray, +i: U32, best: Maybe<Closest>) -> Maybe<Closest>:
  match voxels:
    case Nil{}: best
    case Con{+on, rest}: closest(rest, libm, ray, (i + 1 : U32), closest.step(libm, ray, i, on, best))

def removed(voxels: +List<Bool>, +target: U32, +i: U32) -> +List<Bool>:
  match voxels:
    case Nil{}: Nil{}
    case Con{+on, rest}: Con{on && U32.is_ne(i, target), removed(rest, target, (i + 1 : U32))}

def clicked.found(+voxels: +List<Bool>, best: Maybe<Closest>) -> Maybe<(+List<Bool>)>:
  match best:
    case None{}: None{}
    case Some{Closest{_, +index}}: Some{removed(voxels, index, 0)}

def clicked.ray(+libm: M.Libm, +voxels: +List<Bool>, ray: Maybe<J.Ray>) -> Maybe<(+List<Bool>)>:
  match ray:
    case None{}: None{}
    case Some{+r}: clicked.found(voxels, closest(voxels, libm, r, 0, Some{Closest{99999.0, 512}}))

# A left click casts GetMouseRay from the screen center and clears the closest hit voxel.
def clicked(click: Bool, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +voxels: +List<Bool>) -> Maybe<(+List<Bool>)>:
  match click:
    case False{}: Some{voxels}
    case True{}: clicked.ray(libm, voxels, J.Camera.screen_to_world_ray_for(M.Uncontracted{}, libm, M.Vector2{(800.0 / 2.0 : F32), (450.0 / 2.0 : F32)}, camera, core))

def update.voxels(+camera: J.Camera3D, +model: J.Model, result: Maybe<(+List<Bool>)>, +old: +List<Bool>) -> State:
  match result:
    case None{}: State{camera, old, model, False{}}
    case Some{+v}: State{camera, v, model, True{}}

def update.camera(+libm: M.Libm, +core: J.Core, +voxels: +List<Bool>, +model: J.Model, +camera: J.Camera3D, updated: Maybe<J.Camera3D>) -> State:
  match updated:
    case None{}: State{camera, voxels, model, False{}}
    case Some{+c}: update.voxels(c, model, clicked(J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_LEFT()), libm, core, c, voxels), voxels)

def update.at(ok: Bool, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +voxels: +List<Bool>, +model: J.Model) -> State:
  match ok:
    case False{}: State{camera, voxels, model, False{}}
    case True{}: update.camera(libm, core, voxels, model, camera, J.Camera.update_for(M.Uncontracted{}, libm, core, camera, J.CameraMode.CAMERA_FIRST_PERSON()))

def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+camera, +voxels, +model, +ok} = state
  (core, update.at(ok, libm, core, camera, voxels, model))

def draw.wires(+p: M.Vector3, r: J.Frame & List<J.Texture>) -> J.Frame:
  (f1, _) = r
  J.Draw.cube_wires(f1, p, 1.0, 1.0, 1.0, J.Color.BLACK())

def draw.voxel(on: Bool, +model: J.Model, +p: M.Vector3, frame: J.Frame) -> J.Frame:
  match on:
    case False{}: frame
    case True{}: draw.wires(p, J.Draw.model(frame, Nil{}, model, p, 1.0, J.Color.BEIGE()))

def draw.voxels(voxels: +List<Bool>, +model: J.Model, +i: U32, frame: J.Frame) -> J.Frame:
  match voxels:
    case Nil{}: frame
    case Con{+on, rest}: draw.voxels(rest, model, (i + 1 : U32), draw.voxel(on, model, position(i), frame))

def draw.checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +voxels, +model, +ok} = state
  f1 = J.Draw.grid(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(draw.checked(ok, frame), J.Color.RAYWHITE()), camera), 10.0, 1.0)
  f2 = J.Frame.end_mode_3d(draw.voxels(voxels, model, 0, f1))
  f3 = J.Draw.circle_for(libm, f2, 400.0, 225.0, 4.0, J.Color.RED())
  f4 = J.Draw.text(f3, "Left-click a voxel to remove it!", 10.0, 10.0, 20.0, J.Color.DARKGRAY())
  (core, (state, J.Draw.text(f4, "WASD to move, mouse to look around", 10.0, 35.0, 10.0, J.Color.GRAY())))

# The main loop's body; libm is the profile of UpdateCamera, the ray tests, DrawCircle and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): DisableCursor(), the unit cube model in BEIGE,
# every voxel set, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{start(), full(512n), beige(J.Model.from_mesh(J.Mesh.gen_cube(1.0, 1.0, 1.0))), True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - basic voxel", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
