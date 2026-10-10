# raylib [models] example - heightmap rendering, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_heightmap_rendering.c
# (zlib/libpng, Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A mesh generated from a 128x128 heightmap image (GenMeshHeightmap), drawn
# red with the image as its texture under an orbital camera, and the image
# itself in a corner. The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md) and UpdateCamera its sinf/cosf (docs/SINCOSF.md); a
# refused UpdateCamera refuses the frame and every later one. LoadImage of a
# .png is the PNG loader (Surface.load_png). See docs/MODELS.md and
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# textures: the heightmap texture (the model's diffuse map), or none when it did not load.
type State is Type:
  State{camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{18.0, 21.0, 18.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

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
  State{+camera, +model, textures} = state
  (core, State{camera.update(libm, core, camera), model, textures})

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.outlined(+core: J.Core, +camera: J.Camera3D, +model: J.Model, +x: F32, +w: F32, +h: F32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  draw.fps.done(State{Some{camera}, model, [texture]}, J.Draw.rectangle_lines(frame, x, 20.0, w, h, J.Color.GREEN()), J.Core.get_fps(core, J.Core.get_time(core)), core)

# DrawTexture(texture, screenWidth - texture.width - 20, 20, WHITE) and its outline.
def draw.corner(+core: J.Core, +camera: J.Camera3D, +model: J.Model, frame: J.Frame, texture: J.Texture) -> J.Core & (State & J.Frame):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  draw.outlined(core, camera, model, (800.0 - U32.to_f32(w) - 20.0 : F32), U32.to_f32(w), U32.to_f32(h),
    J.Draw.texture(frame, J.Texture{id, w, h, format, linear, alpha, texels}, (800.0 - U32.to_f32(w) - 20.0 : F32), 20.0, J.Color.WHITE()))

# DrawGrid(20, 1.0f); EndMode3D().
def draw.model(+core: J.Core, +camera: J.Camera3D, +model: J.Model, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  match textures:
    case Con{texture, _}: draw.corner(core, camera, model, J.Frame.end_mode_3d(J.Draw.grid(frame, 20.0, 1.0)), texture)
    case Nil{}: (core, (State{Some{camera}, model, Nil{}}, J.Frame.refuse(frame)))

# DrawModel(model, (-8, 0, -8), 1.0f, RED).
def draw.at(+libm: M.Libm, +core: J.Core, +model: J.Model, frame: J.Frame, textures: List<J.Texture>, camera: +Maybe<J.Camera3D>) -> J.Core & (State & J.Frame):
  match camera:
    case None{}: (core, (State{None{}, model, textures}, J.Frame.refuse(frame)))
    case Some{+c}: draw.model(core, c, model, J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures, model,
      M.Vector3{F32.neg(8.0), 0.0, F32.neg(8.0)}, 1.0, J.Color.RED()))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +model, textures} = state
  draw.at(libm, core, model, frame, textures, camera)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf and the perspective tan.
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

def setup.none(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{Some{start()}, J.Model.empty(), Nil{}}))

def setup.textured(+core: J.Core, frame: J.Frame, +mesh: J.Mesh, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  (J.Core.set_target_fps(core, 60), (frame, State{Some{start()}, textured(J.Model.from_mesh(mesh), info), [texture]}))

# mesh = GenMeshHeightmap(image, (16, 8, 16)); model = LoadModelFromMesh(mesh).
def setup.mesh(+core: J.Core, frame: J.Frame, texture: J.Texture, mesh: Result<&1, &1, J.Surface & J.Surface.Error, J.Mesh>) -> J.Core & (J.Frame & State):
  match mesh:
    case Fail{_}: setup.none(core, frame)
    case Done{+m}: setup.textured(core, frame, m, J.Texture.info(texture))

def setup.uploaded(+core: J.Core, image: J.Surface, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: setup.none(core, frame)
    case Some{t}: setup.mesh(core, frame, t, J.Mesh.gen_heightmap(image, M.Vector3{16.0, 8.0, 16.0}))

# texture = LoadTextureFromImage(image): the upload takes a copy, the mesh the image.
def setup.copied(+core: J.Core, frame: J.Frame, pair: J.Surface & J.Surface) -> J.Core & (J.Frame & State):
  (image, copy) = pair
  setup.uploaded(core, image, J.Texture.load_from_image(frame, copy))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: setup.none(core, frame)
    case Done{image}: setup.copied(core, frame, J.Surface.copy(image))

# After InitWindow(800, 450): LoadImage("resources/heightmap.png"), its
# texture, the mesh and the model, SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/heightmap.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - heightmap rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
