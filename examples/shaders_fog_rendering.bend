# raylib [shaders] example - fog rendering, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_fog_rendering.c
# (zlib/libpng, Copyright (c) 2019-2025 Chris Camacho (@chriscamacho) and
# Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A turning torus, a cube, a sphere and a row of twenty more toruses with a
# checker texture under an orbital camera. The example lights them through
# a fog shader whose density UP and DOWN change; a shader changes nothing
# on raylib's software renderer (docs/SHADERS.md), so the models draw with
# their texture alone there and here, and only the density's text follows
# the keys. The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md); UpdateCamera, the mesh generators and the torus's
# MatrixRotateX/Z its sinf/cosf (docs/SINCOSF.md). LoadTexture of a .png is
# the PNG loader (Surface.load_png). See docs/MODELS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Models is Data:
  Models{torus: J.Model, cube: J.Model, sphere: J.Model}

# valid: the meshes and the texture exist; textures: the checker texture.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, models: Models, textures: List<J.Texture>, density: F32}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{2.0, 2.0, 6.0}, M.Vector3{0.0, 0.5, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def camera.updated(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def camera.update(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: camera.updated(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()))

# modelA.transform = MatrixMultiply(MatrixMultiply(transform, MatrixRotateX(-0.025f)), MatrixRotateZ(0.012f)).
def turned(+libm: M.Libm, +models: Models) -> Models:
  Models{+torus, +cube, +sphere} = models
  J.Model{+transform, +meshes, +materials, +ids} = torus
  Models{J.Model{M.Matrix.multiply(M.Matrix.multiply(transform, M.Matrix.rotate_x_for(libm, F32.neg(0.025))), M.Matrix.rotate_z_for(libm, 0.012)), meshes, materials, ids}, cube, sphere}

# UpdateCamera(CAMERA_ORBITAL); UP and DOWN move fogDensity by 0.001 inside [0, 1]; the torus turns.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +models, textures, +density} = state
  +up = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_UP()), F32.min((density + 0.001 : F32), 1.0), density)
  +down = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_DOWN()), F32.max((up - 0.001 : F32), 0.0), up)
  (core, State{valid, camera.update(libm, core, camera), turned(libm, models), textures, down})

# DrawModel(model, position, 1.0f, WHITE).
def placed(+model: J.Model, +position: M.Vector3, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  (frame, textures) = r
  J.Draw.model(frame, textures, model, position, 1.0, J.Color.WHITE())

# for (i = -20; i < 20; i += 2) DrawModel(modelA, (i, 0, 2), 1.0f, WHITE).
def row(n: Nat, +torus: J.Model, +x: F32, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  match n:
    case 0n: r
    case 1n+p: row(p, torus, (x + 2.0 : F32), placed(torus, M.Vector3{x, 0.0, 2.0}, r))

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 10.0, 20.0, J.Color.RAYWHITE())

def draw.done(+core: J.Core, +camera: J.Camera3D, +models: Models, +density: F32, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  (core, (State{True{}, Some{camera}, models, textures, density},
    label(J.Text.format("Use KEY_UP/KEY_DOWN to change fog density [%.2f]", [J.TextFloat{density}]), J.Frame.end_mode_3d(frame))))

def scene(+models: Models, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  Models{+torus, +cube, +sphere} = models
  row(20n, torus, F32.neg(20.0), placed(sphere, M.Vector3{2.6, 0.0, 0.0}, placed(cube, M.Vector3{F32.neg(2.6), 0.0, 0.0}, placed(torus, M.Vector3.zero(), r))))

def draw.at(valid: Bool, +libm: M.Libm, +core: J.Core, +models: Models, +density: F32, frame: J.Frame, textures: List<J.Texture>, camera: +Maybe<J.Camera3D>) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.done(core, c, models, density, scene(models, (J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.GRAY()), c), textures)))
    case _ None{}: (core, (State{False{}, None{}, models, textures, density}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, models, textures, density}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +models, textures, +density} = state
  draw.at(valid, libm, core, models, density, frame, textures, camera)

# The main loop's body; libm is the profile of UpdateCamera's and the rotations' sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# model.materials[0].maps[MATERIAL_MAP_DIFFUSE].texture = texture.
def textured.material(+info: J.TextureInfo, materials: +List<J.Material>) -> +List<J.Material>:
  match materials:
    case Con{+m, rest}: Con{Maybe.default(&1, J.Material, J.Material.set_texture(m, 0, info), m), rest}
    case Nil{}: Nil{}

def textured(+model: J.Model, +info: J.TextureInfo) -> J.Model:
  J.Model{+transform, +meshes, +materials, +ids} = model
  J.Model{transform, meshes, textured.material(info, materials), ids}

def blank() -> Models:
  Models{J.Model.empty(), J.Model.empty(), J.Model.empty()}

# GenMeshTorus(0.4f, 1.0f, 16, 32), GenMeshCube(1, 1, 1) and GenMeshSphere(0.5f, 32, 32) as models with the texture.
def models(+info: J.TextureInfo, torus: Maybe<J.Mesh>, sphere: Maybe<J.Mesh>) -> Maybe<Models>:
  match torus sphere:
    case Some{+t} Some{+s}: Some{Models{textured(J.Model.from_mesh(t), info), textured(J.Model.from_mesh(J.Mesh.gen_cube(1.0, 1.0, 1.0)), info), textured(J.Model.from_mesh(s), info)}}
    case _ _: None{}

def setup.done(+core: J.Core, frame: J.Frame, textures: List<J.Texture>, models: Maybe<Models>) -> J.Core & (J.Frame & State):
  match models:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{False{}, Some{start()}, blank(), textures, 0.15}))
    case Some{+m}: (J.Core.set_target_fps(core, 60), (frame, State{True{}, Some{start()}, m, textures, 0.15}))

def setup.texture(+libm: M.Libm, +core: J.Core, frame: J.Frame, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  setup.done(core, frame, [texture], models(info, J.Mesh.gen_torus_for(M.Uncontracted{}, libm, 0.4, 1.0, 16, 32), J.Mesh.gen_sphere_for(M.Uncontracted{}, libm, 0.5, 32, 32)))

def setup.uploaded(+libm: M.Libm, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: setup.done(core, frame, Nil{}, None{})
    case Some{t}: setup.texture(libm, core, frame, J.Texture.info(t))

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# After SetConfigFlags(FLAG_MSAA_4X_HINT) and InitWindow(800, 450): the
# models, LoadTexture("resources/texel_checker.png"), the shader, SetTargetFPS(60).
def setup(+libm: M.Libm, dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/texel_checker.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.uploaded(libm, core, upload(frame, result))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - fog rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
