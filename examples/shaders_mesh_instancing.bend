# raylib [shaders] example - mesh instancing, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_mesh_instancing.c
# (zlib/libpng, Copyright (c) 2020-2025 seanpringle (@seanpringle), Max
# (@moliad) and Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Ten thousand cube transforms (random translations and rotations) for
# DrawMeshInstanced between two cubes drawn with DrawMesh, under an orbital
# camera. DrawMeshInstanced is compiled only for OpenGL 3.3 and ES2: on
# raylib's software renderer it draws nothing (docs/MODELS.md), so only the
# two blue cubes show, there and here; the lighting shader changes nothing
# either (docs/SHADERS.md). raylib seeds GetRandomValue from time(NULL) in
# InitWindow; here the seed is a setup argument (docs/DRIVER.md). The
# perspective needs the libm profile's binary64 tan (docs/PERSPECTIVE.md);
# UpdateCamera and MatrixRotate its sinf/cosf (docs/SINCOSF.md).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{camera: +Maybe<J.Camera3D>, cube: J.Mesh, transforms: +List<M.Matrix>}

# LoadMaterialDefault() with maps[MATERIAL_MAP_DIFFUSE].color = color.
def colored.maps(+color: U32, maps: +List<J.MaterialMap>) -> +List<J.MaterialMap>:
  match maps:
    case Con{J.MaterialMap{+texture, _, +value}, rest}: Con{J.MaterialMap{texture, color, value}, rest}
    case Nil{}: Nil{}

def colored(+color: U32, +material: J.Material) -> J.Material:
  J.Material{+maps, +params} = material
  J.Material{colored.maps(color, maps), params}

def camera.updated(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def camera.update(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: camera.updated(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()))

# UpdateCamera(CAMERA_ORBITAL).
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+camera, +cube, +transforms} = state
  (core, State{camera.update(libm, core, camera), cube, transforms})

def unused(r: J.Frame & List<J.Texture>) -> J.Frame:
  (frame, _) = r
  frame

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# DrawMesh(cube, matDefault, MatrixTranslate(-10, 0, 0)); DrawMeshInstanced(cube, matInstances, transforms, 10000);
# DrawMesh(cube, matDefault, MatrixTranslate(10, 0, 0)).
def scene(+libm: M.Libm, +cube: J.Mesh, +transforms: +List<M.Matrix>, frame: J.Frame, camera: +Maybe<J.Camera3D>) -> J.Frame:
  match camera:
    case None{}: J.Frame.refuse(frame)
    case Some{+c}:
      f1 = unused(J.Draw.mesh(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), Nil{}, cube, colored(J.Color.BLUE(), J.Material.load_default()), M.Matrix.translate(F32.neg(10.0), 0.0, 0.0)))
      f2 = unused(J.Draw.mesh_instanced(f1, Nil{}, cube, colored(J.Color.RED(), J.Material.load_default()), transforms))
      J.Frame.end_mode_3d(unused(J.Draw.mesh(f2, Nil{}, cube, colored(J.Color.BLUE(), J.Material.load_default()), M.Matrix.translate(10.0, 0.0, 0.0))))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +cube, +transforms} = state
  draw.fps.done(State{camera, cube, transforms}, scene(libm, cube, transforms, frame, camera), J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# transforms[i] = MatrixMultiply(MatrixRotate(axis, angle), MatrixTranslate(x, y, z)).
def instance.angle(+libm: M.Libm, +x: F32, +y: F32, +z: F32, +ax: F32, +ay: F32, +az: F32, done: +List<M.Matrix>, draw: J.Random.State & F32) -> J.Random.State & +List<M.Matrix>:
  (rng, +degrees) = draw
  (rng, Con{M.Matrix.multiply(M.Matrix.rotate_for(libm, M.Vector3.normalize(M.Vector3{ax, ay, az}), (degrees * M.Math.DEG2RAD() : F32)), M.Matrix.translate(x, y, z)), done})

def instance.az(+libm: M.Libm, +x: F32, +y: F32, +z: F32, +ax: F32, +ay: F32, done: +List<M.Matrix>, draw: J.Random.State & F32) -> J.Random.State & +List<M.Matrix>:
  (rng, +az) = draw
  instance.angle(libm, x, y, z, ax, ay, az, done, J.Random.value(rng, 0.0, 180.0))

def instance.ay(+libm: M.Libm, +x: F32, +y: F32, +z: F32, +ax: F32, done: +List<M.Matrix>, draw: J.Random.State & F32) -> J.Random.State & +List<M.Matrix>:
  (rng, +ay) = draw
  instance.az(libm, x, y, z, ax, ay, done, J.Random.value(rng, 0.0, 360.0))

def instance.ax(+libm: M.Libm, +x: F32, +y: F32, +z: F32, done: +List<M.Matrix>, draw: J.Random.State & F32) -> J.Random.State & +List<M.Matrix>:
  (rng, +ax) = draw
  instance.ay(libm, x, y, z, ax, done, J.Random.value(rng, 0.0, 360.0))

def instance.z(+libm: M.Libm, +x: F32, +y: F32, done: +List<M.Matrix>, draw: J.Random.State & F32) -> J.Random.State & +List<M.Matrix>:
  (rng, +z) = draw
  instance.ax(libm, x, y, z, done, J.Random.value(rng, 0.0, 360.0))

def instance.y(+libm: M.Libm, +x: F32, done: +List<M.Matrix>, draw: J.Random.State & F32) -> J.Random.State & +List<M.Matrix>:
  (rng, +y) = draw
  instance.z(libm, x, y, done, J.Random.value(rng, F32.neg(50.0), 50.0))

def instance.x(+libm: M.Libm, done: +List<M.Matrix>, draw: J.Random.State & F32) -> J.Random.State & +List<M.Matrix>:
  (rng, +x) = draw
  instance.y(libm, x, done, J.Random.value(rng, F32.neg(50.0), 50.0))

# Seven GetRandomValue calls an instance, in clang's left-to-right argument order: the translation's x, y, z (-50..50), the
# axis's x, y, z (0..360) and the angle in degrees (0..180).
def instance(+libm: M.Libm, acc: J.Random.State & +List<M.Matrix>) -> J.Random.State & +List<M.Matrix>:
  (rng, done) = acc
  instance.x(libm, done, J.Random.value(rng, F32.neg(50.0), 50.0))

def instances(n: Nat, +libm: M.Libm, acc: J.Random.State & +List<M.Matrix>) -> J.Random.State & +List<M.Matrix>:
  match n:
    case 0n: acc
    case 1n+p: instances(p, libm, instance(libm, acc))

def instances.made(r: J.Random.State & +List<M.Matrix>) -> +List<M.Matrix>:
  (_, reversed) = r
  List.reverse(&2, M.Matrix, reversed)

# After InitWindow(800, 450) and SetRandomSeed(seed): the cube mesh, the 10000 transforms, SetTargetFPS(60).
def setup(+seed: U32, +libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{Some{J.Camera3D{M.Vector3{F32.neg(125.0), 125.0, F32.neg(125.0)}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}},
    J.Mesh.gen_cube(1.0, 1.0, 1.0), instances.made(instances(U32.to_nat(10000), libm, (J.Random.seed(seed), Nil{})))}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - mesh instancing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, M.Glibc239Libm{}, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
