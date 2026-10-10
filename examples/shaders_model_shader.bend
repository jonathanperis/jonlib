# raylib [shaders] example - model shader, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_model_shader.c
# (zlib/libpng, Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# An OBJ model (LoadModel) with its diffuse texture under a free camera.
# The example gives the model's material a grayscale fragment shader; a
# shader changes nothing on raylib's software renderer (docs/SHADERS.md), so
# the model draws with its texture's colors there and here, and a Jonlib
# material carries no shader. The perspective needs the libm profile's
# binary64 tan (docs/PERSPECTIVE.md) and UpdateCamera its sinf/cosf
# (docs/SINCOSF.md); a refused UpdateCamera refuses the frame and every
# later one. LoadTexture of a .png is the PNG loader (Surface.load_png). See
# docs/MODELS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: the model loaded; textures: the model's own and the diffuse texture.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>, shader: J.Shader}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{4.0, 4.0, 4.0}, M.Vector3{0.0, 1.0, F32.neg(1.0)}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def camera.updated(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def camera.update(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: camera.updated(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_FREE()))

# UpdateCamera(CAMERA_FREE).
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +model, textures, +shader} = state
  (core, State{valid, camera.update(libm, core, camera), model, textures, shader})

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# DrawGrid(10, 1.0f); EndMode3D(); the credit line and the frame rate.
def draw.model(+core: J.Core, +camera: J.Camera3D, +model: J.Model, +shader: J.Shader, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0))
  draw.fps.done(State{True{}, Some{camera}, model, textures, shader},
    J.Draw.text(f1, "(c) Watermill 3D model by Alberto Cano", (800.0 - 210.0 : F32), (450.0 - 20.0 : F32), 10.0, J.Color.GRAY()), J.Core.get_fps(core, J.Core.get_time(core)), core)

# DrawModel(model, (0, 0, 0), 0.2f, WHITE).
def draw.at(valid: Bool, +libm: M.Libm, +core: J.Core, +model: J.Model, +shader: J.Shader, frame: J.Frame, textures: List<J.Texture>, camera: +Maybe<J.Camera3D>) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.model(core, c, model, shader, J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures, model,
      M.Vector3.zero(), 0.2, J.Color.WHITE()))
    case _ None{}: (core, (State{False{}, None{}, model, textures, shader}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, model, textures, shader}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +model, textures, +shader} = state
  draw.at(valid, libm, core, model, shader, frame, textures, camera)

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

# LoadShader(0, "resources/shaders/glsl330/grayscale.fs").
def shader() -> J.Shader:
  J.Shader.load(None{}, Some{"resources/shaders/glsl330/grayscale.fs"})

def setup.done(+core: J.Core, frame: J.Frame, +valid: Bool, +model: J.Model, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{valid, Some{start()}, model, textures, shader()}))

def setup.texture(+core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  setup.done(core, frame, True{}, textured(model, info), List.append(&1, J.Texture, textures, [texture]))

def setup.uploaded(+core: J.Core, +model: J.Model, textures: List<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: setup.done(core, frame, False{}, model, textures)
    case Some{t}: setup.texture(core, frame, model, textures, J.Texture.info(t))

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# texture = LoadTexture("resources/models/watermill_diffuse.png").
def setup.model(+dir: String, +core: J.Core, frame: J.Frame, loaded: J.LoadedModel) -> IO(J.Core & (J.Frame & State)):
  J.LoadedModel{+model, textures} = loaded
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/models/watermill_diffuse.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.uploaded(core, model, textures, upload(frame, result))))

def setup.loaded(+dir: String, +core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), setup.done(core, frame, False{}, J.Model.empty(), Nil{}))
    case Done{loaded}: setup.model(dir, core, frame, loaded)

# After SetConfigFlags(FLAG_MSAA_4X_HINT) and InitWindow(800, 450):
# LoadModel("resources/models/watermill.obj"), its texture, the shader,
# DisableCursor(), SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ "resources/models/watermill.obj"),
    r => setup.loaded(dir, core, r))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - model shader", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
