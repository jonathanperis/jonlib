# raylib [shaders] example - simple mask, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_simple_mask.c
# (zlib/libpng, Copyright (c) 2019-2025 Chris Camacho (@chriscamacho) and
# Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A turning torus, a cube and a sphere under a first-person camera. The
# example masks the torus and the cube with a second texture through a
# fragment shader; a shader changes nothing on raylib's software renderer
# (docs/SHADERS.md), so they draw with their diffuse texture alone there and
# here (the mask texture stays in the emission map). The frame counter's box
# and text sit below the 450-pixel window, as in the example. The
# perspective needs the libm profile's binary64 tan (docs/PERSPECTIVE.md);
# UpdateCamera, the mesh generators, MatrixRotateXYZ and DrawModelEx its
# sinf/cosf (docs/SINCOSF.md). LoadTexture of a .png is the PNG loader
# (Surface.load_png). See docs/MODELS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Models is Data:
  Models{torus: J.Model, cube: J.Model, sphere: J.Model}

# valid: the meshes and the textures exist; textures: plasma and mask.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, models: Models, textures: List<J.Texture>, frames: U32, rotation: M.Vector3}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.0, 1.0, 2.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def camera.updated(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def camera.update(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: camera.updated(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_FIRST_PERSON()))

# model1.transform = MatrixRotateXYZ(rotation).
def turned(+libm: M.Libm, +models: Models, +rotation: M.Vector3) -> Models:
  Models{+torus, +cube, +sphere} = models
  J.Model{_, +meshes, +materials, +ids} = torus
  Models{J.Model{M.Matrix.rotate_xyz_for(libm, rotation), meshes, materials, ids}, cube, sphere}

# UpdateCamera(CAMERA_FIRST_PERSON); framesCounter++; rotation += (0.01, 0.005, -0.0025).
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +models, textures, +frames, +rotation} = state
  M.Vector3{+x, +y, +z} = rotation
  +next = {M.Vector3{(x + 0.01 : F32), (y + 0.005 : F32), (z - 0.0025 : F32)} : M.Vector3}
  (core, State{valid, camera.update(libm, core, camera), turned(libm, models, next), textures, (frames + 1 : U32), next})

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# DrawRectangle(16, 698, MeasureText("Frame: %i", 20) + 8, 42, BLUE); DrawText("Frame: %i", 20, 700, 20, WHITE).
def counter.box(width: Maybe<U32>, +text: String, frame: J.Frame) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{w}: J.Draw.text(J.Draw.rectangle(frame, 16.0, 698.0, U32.to_f32((w + 8 : U32)), 42.0, J.Color.BLUE()), text, 20.0, 700.0, 20.0, J.Color.WHITE())

def counter(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{+t}: counter.box(J.Font.measure_text(t, 20.0), t, frame)

# DrawGrid(10, 1.0f); EndMode3D(); the frame counter and the frame rate.
def draw.done(+core: J.Core, +camera: J.Camera3D, +models: Models, +frames: U32, +rotation: M.Vector3, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  draw.fps.done(State{True{}, Some{camera}, models, textures, frames, rotation},
    counter(J.Text.format("Frame: %i", [J.TextInt{frames}]), J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0))), J.Core.get_fps(core, J.Core.get_time(core)), core)

def placed(+model: J.Model, +position: M.Vector3, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  (frame, textures) = r
  J.Draw.model(frame, textures, model, position, 1.0, J.Color.WHITE())

# DrawModelEx(model2, (-0.5, 0, 0), (1, 1, 0), 50, (1, 1, 1), WHITE).
def tilted(+libm: M.Libm, +model: J.Model, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  (frame, textures) = r
  J.Draw.model_ex_for(libm, frame, textures, model, M.Vector3{F32.neg(0.5), 0.0, 0.0}, M.Vector3{1.0, 1.0, 0.0}, 50.0, M.Vector3{1.0, 1.0, 1.0}, J.Color.WHITE())

def scene(+libm: M.Libm, +models: Models, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  Models{+torus, +cube, +sphere} = models
  placed(sphere, M.Vector3{0.0, 0.0, F32.neg(1.5)}, tilted(libm, cube, placed(torus, M.Vector3{0.5, 0.0, 0.0}, r)))

def draw.at(valid: Bool, +libm: M.Libm, +core: J.Core, +models: Models, +frames: U32, +rotation: M.Vector3, frame: J.Frame, textures: List<J.Texture>, camera: +Maybe<J.Camera3D>) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.done(core, c, models, frames, rotation,
      scene(libm, models, (J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.DARKBLUE()), c), textures)))
    case _ None{}: (core, (State{False{}, None{}, models, textures, frames, rotation}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, models, textures, frames, rotation}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +models, textures, +frames, +rotation} = state
  draw.at(valid, libm, core, models, frames, rotation, frame, textures, camera)

# The main loop's body; libm is the profile of UpdateCamera's and the rotations' sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def mapped(+map: U32, +info: J.TextureInfo, +material: J.Material) -> J.Material:
  Maybe.default(&1, J.Material, J.Material.set_texture(material, map, info), material)

# materials[0].maps[MATERIAL_MAP_DIFFUSE].texture = texDiffuse; materials[0].maps[MATERIAL_MAP_EMISSION].texture = texMask.
def textured.material(+diffuse: J.TextureInfo, +mask: J.TextureInfo, materials: +List<J.Material>) -> +List<J.Material>:
  match materials:
    case Con{+m, rest}: Con{mapped(J.MaterialMapIndex.MATERIAL_MAP_EMISSION(), mask, mapped(0, diffuse, m)), rest}
    case Nil{}: Nil{}

def textured(+model: J.Model, +diffuse: J.TextureInfo, +mask: J.TextureInfo) -> J.Model:
  J.Model{+transform, +meshes, +materials, +ids} = model
  J.Model{transform, meshes, textured.material(diffuse, mask, materials), ids}

def blank() -> Models:
  Models{J.Model.empty(), J.Model.empty(), J.Model.empty()}

# GenMeshTorus(0.3f, 1, 16, 32) and GenMeshCube(0.8f, 0.8f, 0.8f) with both textures, GenMeshSphere(1, 16, 16) plain.
def models(+diffuse: J.TextureInfo, +mask: J.TextureInfo, torus: Maybe<J.Mesh>, sphere: Maybe<J.Mesh>) -> Maybe<Models>:
  match torus sphere:
    case Some{+t} Some{+s}: Some{Models{textured(J.Model.from_mesh(t), diffuse, mask), textured(J.Model.from_mesh(J.Mesh.gen_cube(0.8, 0.8, 0.8)), diffuse, mask), J.Model.from_mesh(s)}}
    case _ _: None{}

def setup.done(+core: J.Core, frame: J.Frame, textures: List<J.Texture>, models: Maybe<Models>) -> J.Core & (J.Frame & State):
  match models:
    case None{}: (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{False{}, Some{start()}, blank(), textures, 0, M.Vector3.zero()}))
    case Some{+m}: (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{True{}, Some{start()}, m, textures, 0, M.Vector3.zero()}))

def setup.infos(+libm: M.Libm, +core: J.Core, frame: J.Frame, plasma: J.Texture, +diffuse: J.TextureInfo, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (mask, +info) = r
  setup.done(core, frame, [plasma, mask], models(diffuse, info, J.Mesh.gen_torus_for(M.Uncontracted{}, libm, 0.3, 1.0, 16, 32), J.Mesh.gen_sphere_for(M.Uncontracted{}, libm, 1.0, 16, 16)))

def setup.plasma(+libm: M.Libm, +core: J.Core, frame: J.Frame, mask: J.Texture, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (plasma, +diffuse) = r
  setup.infos(libm, core, frame, plasma, diffuse, J.Texture.info(mask))

def setup.both(+libm: M.Libm, +core: J.Core, frame: J.Frame, plasma: Maybe<J.Texture>, mask: Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  match plasma mask:
    case Some{p} Some{m}: setup.plasma(libm, core, frame, m, J.Texture.info(p))
    case _ _: setup.done(core, frame, Nil{}, None{})

def setup.mask(+libm: M.Libm, +core: J.Core, plasma: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, mask) = r
  setup.both(libm, core, frame, plasma, mask)

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# texMask = LoadTexture("resources/mask.png").
def setup.diffuse(+libm: M.Libm, +dir: String, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, plasma) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/mask.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.mask(libm, core, plasma, upload(frame, result))))

# After InitWindow(800, 450): the models, LoadTexture("resources/plasma.png"), the mask, DisableCursor(), SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/plasma.png"),
    result => setup.diffuse(libm, dir, core, upload(frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - simple mask", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
