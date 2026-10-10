# raylib [models] example - cubicmap rendering, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_cubicmap_rendering.c
# (zlib/libpng, Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A map of cubes generated from a 32x16 image (GenMeshCubicmap) and textured
# from an atlas, under an orbital camera that P pauses, with the image
# itself enlarged four times in a corner. The perspective needs the libm
# profile's binary64 tan (docs/PERSPECTIVE.md) and UpdateCamera its
# sinf/cosf (docs/SINCOSF.md); a refused UpdateCamera refuses the frame and
# every later one. LoadImage and LoadTexture of a .png are the PNG loader
# (Surface.load_png). See docs/MODELS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# textures: the atlas (the model's diffuse map); cubicmap: the image's texture.
type State is Type:
  State{camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>, cubicmap: Maybe<J.Texture>, pause: Bool}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{16.0, 14.0, 16.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def camera.updated(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def camera.moved(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: camera.updated(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()))

def camera.update(pause: Bool, +libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match pause:
    case True{}: camera
    case False{}: camera.moved(libm, core, camera)

# P pauses; UpdateCamera(CAMERA_ORBITAL) otherwise.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+camera, +model, textures, cubicmap, +pause} = state
  +paused = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_P()), Bool.not(pause), pause)
  (core, State{camera.update(paused, libm, core, camera), model, textures, cubicmap, paused})

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.outlined(+core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +pause: Bool, +w: F32, +h: F32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, cubicmap) = r
  f1 = J.Draw.rectangle_lines(frame, (800.0 - w * 4.0 - 20.0 : F32), 20.0, (w * 4.0 : F32), (h * 4.0 : F32), J.Color.GREEN())
  f2 = J.Draw.text(f1, "cubicmap image used to", 658.0, 90.0, 10.0, J.Color.GRAY())
  draw.fps.done(State{Some{camera}, model, textures, Some{cubicmap}, pause}, J.Draw.text(f2, "generate map 3d model", 658.0, 104.0, 10.0, J.Color.GRAY()),
    J.Core.get_fps(core, J.Core.get_time(core)), core)

# DrawTextureEx(cubicmap, (screenWidth - cubicmap.width*4.0f - 20, 20), 0, 4, WHITE) and its outline.
def draw.corner(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +pause: Bool, frame: J.Frame, cubicmap: J.Texture) -> J.Core & (State & J.Frame):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = cubicmap
  draw.outlined(core, camera, model, textures, pause, U32.to_f32(w), U32.to_f32(h),
    J.Draw.texture_ex_for(libm, frame, J.Texture{id, w, h, format, linear, alpha, texels}, M.Vector2{(800.0 - U32.to_f32(w) * 4.0 - 20.0 : F32), 20.0}, 0.0, 4.0, J.Color.WHITE()))

def draw.model(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +model: J.Model, +pause: Bool, r: J.Frame & List<J.Texture>, cubicmap: Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  match cubicmap:
    case None{}: (core, (State{Some{camera}, model, textures, None{}, pause}, J.Frame.refuse(frame)))
    case Some{t}: draw.corner(libm, core, camera, model, textures, pause, J.Frame.end_mode_3d(frame), t)

# DrawModel(model, (-16, 0, -8), 1.0f, WHITE).
def draw.at(+libm: M.Libm, +core: J.Core, +model: J.Model, +pause: Bool, frame: J.Frame, textures: List<J.Texture>, cubicmap: Maybe<J.Texture>, camera: +Maybe<J.Camera3D>) -> J.Core & (State & J.Frame):
  match camera:
    case None{}: (core, (State{None{}, model, textures, cubicmap, pause}, J.Frame.refuse(frame)))
    case Some{+c}: draw.model(libm, core, c, model, pause,
      J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures, model,
        M.Vector3{F32.neg(16.0), 0.0, F32.neg(8.0)}, 1.0, J.Color.WHITE()), cubicmap)

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +model, textures, cubicmap, +pause} = state
  draw.at(libm, core, model, pause, frame, textures, cubicmap, camera)

# The main loop's body; libm is the profile of UpdateCamera's and DrawTextureEx's sinf/cosf and the perspective tan.
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

def setup.textured(+core: J.Core, frame: J.Frame, cubicmap: Maybe<J.Texture>, +model: J.Model, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  (J.Core.set_target_fps(core, 60), (frame, State{Some{start()}, textured(model, info), [texture], cubicmap, False{}}))

def setup.atlas(+core: J.Core, cubicmap: Maybe<J.Texture>, +model: J.Model, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, atlas) = r
  match atlas:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{Some{start()}, model, Nil{}, None{}, False{}}))
    case Some{t}: setup.textured(core, frame, cubicmap, model, J.Texture.info(t))

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# texture = LoadTexture("resources/cubicmap_atlas.png").
def setup.model(+dir: String, +core: J.Core, frame: J.Frame, cubicmap: Maybe<J.Texture>, +model: J.Model) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cubicmap_atlas.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.atlas(core, cubicmap, model, upload(frame, result))))

# mesh = GenMeshCubicmap(image, (1, 1, 1)); model = LoadModelFromMesh(mesh).
def setup.mesh(+dir: String, +core: J.Core, frame: J.Frame, cubicmap: Maybe<J.Texture>, mesh: Result<&1, &1, J.Surface & J.Surface.Error, J.Mesh>) -> IO(J.Core & (J.Frame & State)):
  match mesh:
    case Fail{_}: setup.model(dir, core, frame, None{}, J.Model.empty())
    case Done{+m}: setup.model(dir, core, frame, cubicmap, J.Model.from_mesh(m))

def setup.uploaded(+dir: String, +core: J.Core, image: J.Surface, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, cubicmap) = r
  setup.mesh(dir, core, frame, cubicmap, J.Mesh.gen_cubicmap(image, M.Vector3{1.0, 1.0, 1.0}))

# cubicmap = LoadTextureFromImage(image): the upload takes a copy, the mesh the image.
def setup.copied(+dir: String, +core: J.Core, frame: J.Frame, pair: J.Surface & J.Surface) -> IO(J.Core & (J.Frame & State)):
  (image, copy) = pair
  setup.uploaded(dir, core, image, J.Texture.load_from_image(frame, copy))

def setup.loaded(+dir: String, +core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(J.Core & (J.Frame & State)):
  match result:
    case Fail{_}: setup.model(dir, core, frame, None{}, J.Model.empty())
    case Done{image}: setup.copied(dir, core, frame, J.Surface.copy(image))

# After InitWindow(800, 450): LoadImage("resources/cubicmap.png"), its
# texture, the mesh and the model, the atlas texture, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cubicmap.png"),
    result => setup.loaded(dir, core, frame, result))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - cubicmap rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
