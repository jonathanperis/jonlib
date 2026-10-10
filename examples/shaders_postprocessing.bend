# raylib [shaders] example - postprocessing, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_postprocessing.c
# (zlib/libpng, Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# An OBJ church under an orbital camera drawn into a render texture, which
# the example then draws through one of twelve postprocessing fragment
# shaders picked with LEFT and RIGHT. A shader changes nothing on raylib's
# software renderer (docs/SHADERS.md), so the render texture shows as it is
# there and here, and only the shader's name follows the keys. The render
# texture has its own depth buffer (docs/RLGL.md). The perspective needs the
# libm profile's binary64 tan (docs/PERSPECTIVE.md) and UpdateCamera its
# sinf/cosf (docs/SINCOSF.md). LoadTexture of a .png is the PNG loader
# (Surface.load_png). See docs/MODELS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: the model and its texture loaded; textures: the model's own and the diffuse texture.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>, target: Maybe<J.RenderTexture>, current: U32}

def name(index: U32) -> String:
  match index:
    case 0: "GRAYSCALE"
    case 1: "POSTERIZATION"
    case 2: "DREAM_VISION"
    case 3: "PIXELIZER"
    case 4: "CROSS_HATCHING"
    case 5: "CROSS_STITCHING"
    case 6: "PREDATOR_VIEW"
    case 7: "SCANLINES"
    case 8: "FISHEYE"
    case 9: "SOBEL"
    case 10: "BLOOM"
    case _: "BLUR"

def file(index: U32) -> String:
  match index:
    case 0: "grayscale"
    case 1: "posterization"
    case 2: "dream_vision"
    case 3: "pixelizer"
    case 4: "cross_hatching"
    case 5: "cross_stitching"
    case 6: "predator"
    case 7: "scanlines"
    case 8: "fisheye"
    case 9: "sobel"
    case 10: "bloom"
    case _: "blur"

# shaders[i] = LoadShader(0, "resources/shaders/glsl330/<name>.fs").
def shader(+index: U32) -> J.Shader:
  J.Shader.load(None{}, Some{"resources/shaders/glsl330/" ++ file(index) ++ ".fs"})

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{2.0, 3.0, 2.0}, M.Vector3{0.0, 1.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def camera.updated(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def camera.update(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: camera.updated(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()))

# UpdateCamera(CAMERA_ORBITAL); RIGHT takes the next shader, otherwise LEFT the previous, around the twelve.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +model, textures, target, +current} = state
  +next = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT()), Bool.pick(U32, (current >= 11 : U32), 0, (current + 1 : U32)),
    Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT()), Bool.pick(U32, U32.is_eq(current, 0), 11, (current - 1 : U32)), current))
  (core, State{valid, camera.update(libm, core, camera), model, textures, target, next})

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 700.0, 15.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# EndShaderMode(); the title bar with the shader's name, the credit line and the frame rate.
def draw.shown(+core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +current: U32, +id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  f1 = J.Draw.rectangle(J.Frame.end_shader_mode(frame), 0.0, 9.0, 580.0, 30.0, J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.7))
  f2 = J.Draw.text(f1, "(c) Church 3D model by Alberto Cano", (800.0 - 200.0 : F32), (450.0 - 20.0 : F32), 10.0, J.Color.GRAY())
  f3 = J.Draw.text(J.Draw.text(f2, "CURRENT POSTPRO SHADER:", 10.0, 15.0, 20.0, J.Color.BLACK()), name(current), 330.0, 15.0, 20.0, J.Color.RED())
  draw.fps.done(State{True{}, Some{camera}, model, textures, Some{J.RenderTexture{id, texture, depth}}, current},
    J.Draw.text(f3, "< >", 540.0, 10.0, 30.0, J.Color.DARKBLUE()), J.Core.get_fps(core, J.Core.get_time(core)), core)

# BeginShaderMode(shaders[currentShader]); DrawTextureRec(target.texture, (0, 0, width, -height), (0, 0), WHITE).
def draw.screen(+core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +current: U32, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  draw.shown(core, camera, model, textures, current, id, depth,
    J.Draw.texture_rec(J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader(current)), J.Texture{tid, w, h, format, linear, alpha, texels},
      J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))}, M.Vector2.zero(), J.Color.WHITE()))

def draw.ended(+core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +current: U32, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{False{}, Some{camera}, model, textures, None{}, current}, J.Frame.refuse(frame)))
    case Some{t}: draw.screen(core, camera, model, textures, current, frame, t)

# DrawGrid(10, 1.0f); EndMode3D(); EndTextureMode().
def draw.model(+core: J.Core, +camera: J.Camera3D, +model: J.Model, +current: U32, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  draw.ended(core, camera, model, textures, current, J.Frame.end_texture_mode(J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0))))

# The texture pass (raylib draws it before BeginDrawing; here the draw does that first, the same pixels):
# ClearBackground(RAYWHITE); BeginMode3D(camera); DrawModel(model, (0, 0, 0), 0.1f, WHITE).
def draw.at(valid: Bool, +libm: M.Libm, +core: J.Core, +model: J.Model, +current: U32, frame: J.Frame, textures: List<J.Texture>, target: Maybe<J.RenderTexture>, camera: +Maybe<J.Camera3D>) -> J.Core & (State & J.Frame):
  match valid target camera:
    case True{} Some{t} Some{+c}: draw.model(core, c, model, current, J.Draw.model(J.Frame.begin_mode_3d_for(libm,
      J.Frame.clear_background(J.Frame.begin_texture_mode(frame, t), J.Color.RAYWHITE()), c), textures, model, M.Vector3.zero(), 0.1, J.Color.WHITE()))
    case _ Some{t} _: (core, (State{False{}, None{}, model, textures, Some{t}, current}, J.Frame.refuse(frame)))
    case _ None{} _: (core, (State{False{}, None{}, model, textures, None{}, current}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +model, textures, target, +current} = state
  draw.at(valid, libm, core, model, current, frame, textures, target, camera)

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

# target = LoadRenderTexture(800, 450).
def setup.done(+core: J.Core, +valid: Bool, +model: J.Model, textures: List<J.Texture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, State{valid, Some{start()}, model, textures, target, 0}))

def setup.texture(+core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  setup.done(core, True{}, textured(model, info), List.append(&1, J.Texture, textures, [texture]), J.RenderTexture.load(frame, 800, 450))

def setup.uploaded(+core: J.Core, +model: J.Model, textures: List<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: setup.done(core, False{}, model, textures, (frame, None{}))
    case Some{t}: setup.texture(core, frame, model, textures, J.Texture.info(t))

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# texture = LoadTexture("resources/models/church_diffuse.png").
def setup.model(+dir: String, +core: J.Core, frame: J.Frame, loaded: J.LoadedModel) -> IO(J.Core & (J.Frame & State)):
  J.LoadedModel{+model, textures} = loaded
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/models/church_diffuse.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.uploaded(core, model, textures, upload(frame, result))))

def setup.loaded(+dir: String, +core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), setup.done(core, False{}, J.Model.empty(), Nil{}, (frame, None{})))
    case Done{loaded}: setup.model(dir, core, frame, loaded)

# After SetConfigFlags(FLAG_MSAA_4X_HINT) and InitWindow(800, 450):
# LoadModel("resources/models/church.obj"), its texture, the render texture, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ "resources/models/church.obj"),
    r => setup.loaded(dir, core, r))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - postprocessing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
