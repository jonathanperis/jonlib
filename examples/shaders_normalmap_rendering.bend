# raylib [shaders] example - normalmap rendering, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_normalmap_rendering.c
# (zlib/libpng, Copyright (c) 2025 Jeremy Montgomery (@Sir_Irk) and Ramon
# Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A tiled plane (plane.glb, LoadGLTF) turning about Y under a light that
# W, A, S and D move; UP and DOWN change the specular exponent and N toggles
# the normal map. On the software renderer shaders do not exist
# (docs/SHADERS.md): the plane is drawn with its diffuse texture only, the
# normal map, the light and the exponent change nothing but the text and the
# light's wire sphere, as in the reference. GenTextureMipmaps only warns
# under OpenGL 1.1 and TRILINEAR is the linear filter. The perspective needs
# the libm profile's binary64 tan (docs/PERSPECTIVE.md), the turn its
# sinf/cosf: a refusal marks the frame. LoadTexture of a .png is the PNG
# loader (Surface.load_png). See docs/MODELS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{model: J.Model, textures: List<J.Texture>, shader: J.Shader, light: M.Vector3, specular: F32, normal_map: Bool, ok: Bool}

def camera() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.0, 2.0, F32.neg(4.0)}, M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def pushed(down: Bool, +direction: M.Vector3, +x: F32, +z: F32) -> M.Vector3:
  match down:
    case True{}: M.Vector3.add(direction, M.Vector3{x, 0.0, z})
    case False{}: direction

# W, S, D and A add (0, 0, 1), (0, 0, -1), (-1, 0, 0) and (1, 0, 0), in that order.
def direction(+core: J.Core) -> M.Vector3:
  +w = pushed(J.Input.is_key_down(core, J.KeyboardKey.KEY_W()), M.Vector3.zero(), 0.0, 1.0)
  +s = pushed(J.Input.is_key_down(core, J.KeyboardKey.KEY_S()), w, 0.0, F32.neg(1.0))
  +d = pushed(J.Input.is_key_down(core, J.KeyboardKey.KEY_D()), s, F32.neg(1.0), 0.0)
  M.Vector3.normalize(pushed(J.Input.is_key_down(core, J.KeyboardKey.KEY_A()), d, 1.0, 0.0))

# Clamp(specularExponent +/- 40.0f*GetFrameTime(), 2.0f, 128.0f): UP first, then DOWN.
def exponent(+core: J.Core, +specular: F32) -> F32:
  +step = (40.0 * J.Core.get_frame_time(core) : F32)
  +up = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_UP()), M.Math.clamp((specular + step : F32), 2.0, 128.0), specular)
  Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_DOWN()), M.Math.clamp((up - step : F32), 2.0, 128.0), up)

# plane.transform = MatrixRotateY((float)GetTime()*0.5f).
def turned(time: Maybe<F32>, +libm: M.Libm, +model: J.Model) -> J.Model:
  match time:
    case None{}: model
    case Some{+t}:
      J.Model{_, +meshes, +materials, +ids} = model
      J.Model{M.Matrix.rotate_y_for(libm, (t * 0.5 : F32)), meshes, materials, ids}

def timed(time: Maybe<F32>) -> Bool:
  match time:
    case None{}: False{}
    case Some{_}: True{}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+model, textures, +shader, +light, +specular, +normal_map, +ok} = state
  +moved = M.Vector3.add(light, M.Vector3.scale(direction(core), (J.Core.get_frame_time(core) * 3.0 : F32)))
  +flipped = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_N()), Bool.not(normal_map), normal_map)
  (core, State{turned(M.Float64.to_f32(J.Core.get_time(core)), libm, model), textures, shader, moved, exponent(core, specular), flipped, ok && timed(M.Float64.to_f32(J.Core.get_time(core)))})

def draw.line(text: Maybe<String>, +y: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 10.0, color)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 710.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.shown(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def draw.text(+libm: M.Libm, +core: J.Core, +model: J.Model, +shader: J.Shader, +light: M.Vector3, +specular: F32, +normal_map: Bool, +ok: Bool, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = J.Frame.end_mode_3d(J.Draw.sphere_wires_for(libm, J.Frame.end_shader_mode(frame), light, 0.2, 8.0, 8.0, J.Color.ORANGE()))
  f2 = draw.line(J.Text.format("Use key [N] to toggle normal map: %s", [J.TextString{Bool.pick(String, normal_map, "On", "Off")}]), 10.0, Bool.pick(U32, normal_map, J.Color.DARKGREEN(), J.Color.RED()), f1)
  f3 = J.Draw.text(f2, "Use keys [W][A][S][D] to move the light", 10.0, 34.0, 10.0, J.Color.BLACK())
  f4 = J.Draw.text(f3, "Use keys [Up][Down] to change specular exponent", 10.0, 58.0, 10.0, J.Color.BLACK())
  f5 = draw.line(J.Text.format("Specular Exponent: %.2f", [J.TextFloat{specular}]), 82.0, J.Color.BLUE(), f4)
  draw.fps.done(State{model, textures, shader, light, specular, normal_map, ok}, f5, J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+model, textures, +shader, +light, +specular, +normal_map, +ok} = state
  f1 = J.Frame.begin_shader_mode(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(draw.shown(ok, frame), J.Color.RAYWHITE()), camera()), shader)
  draw.text(libm, core, model, shader, light, specular, normal_map, ok, J.Draw.model(f1, textures, model, M.Vector3.zero(), 2.0, J.Color.WHITE()))

# The main loop's body; libm is the profile of MatrixRotateY's sinf/cosf, the sphere's and BeginMode3D's tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def shader() -> J.Shader:
  J.Shader.load(Some{"resources/shaders/glsl330/normalmap.vs"}, Some{"resources/shaders/glsl330/normalmap.fs"})

def start(+core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, +ok: Bool) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{model, textures, shader(), M.Vector3{0.0, 1.0, 0.0}, 8.0, True{}, ok}))

# plane.materials[0].maps[map].texture = texture.
def mapped.material(+info: J.TextureInfo, +map: U32, materials: +List<J.Material>) -> +List<J.Material>:
  match materials:
    case Con{+m, rest}: Con{Maybe.default(&1, J.Material, J.Material.set_texture(m, map, info), m), rest}
    case Nil{}: Nil{}

def mapped(+model: J.Model, +info: J.TextureInfo, +map: U32) -> J.Model:
  J.Model{+transform, +meshes, +materials, +ids} = model
  J.Model{transform, meshes, mapped.material(info, map, materials), ids}

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# GenTextureMipmaps and SetTextureFilter(TEXTURE_FILTER_TRILINEAR) on the texture kept for drawing.
def kept(+core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, +map: U32, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  start(core, frame, mapped(model, info, map), List.append(&1, J.Texture, textures, [J.Texture.set_filter(J.Texture.gen_mipmaps(texture), 2)]), True{})

def normal.uploaded(+core: J.Core, +model: J.Model, textures: List<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: start(core, frame, model, textures, False{})
    case Some{t}: kept(core, frame, model, textures, 2, J.Texture.info(t))

def diffuse.kept(+dir: String, +core: J.Core, frame: J.Frame, +model: J.Model, r: J.Texture & J.TextureInfo) -> IO(J.Core & (J.Frame & State)):
  (texture, +info) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/tiles_normal.png"),
    result => IO.pure(J.Core & (J.Frame & State), normal.uploaded(core, mapped(model, info, 0), [J.Texture.set_filter(J.Texture.gen_mipmaps(texture), 2)], upload(frame, result))))

def diffuse.uploaded(+dir: String, +core: J.Core, +model: J.Model, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, texture) = r
  match texture:
    case None{}: IO.pure(J.Core & (J.Frame & State), start(core, frame, model, Nil{}, False{}))
    case Some{t}: diffuse.kept(dir, core, frame, model, J.Texture.info(t))

def setup.model(+dir: String, +core: J.Core, frame: J.Frame, loaded: J.LoadedModel) -> IO(J.Core & (J.Frame & State)):
  J.LoadedModel{+model, textures} = loaded
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/tiles_diffuse.png"),
    result => diffuse.uploaded(dir, core, model, upload(frame, result)))

def setup.loaded(+dir: String, +core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), start(core, frame, J.Model.empty(), Nil{}, False{}))
    case Done{loaded}: setup.model(dir, core, frame, loaded)

# After InitWindow(800, 450): the shader, LoadModel("resources/models/plane.glb"), its diffuse and normal
# textures, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load_for(M.Uncontracted{}, frame, dir ++ "resources/models/plane.glb"),
    r => setup.loaded(dir, core, r))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, J.ConfigFlags.FLAG_MSAA_4X_HINT(), "raylib [shaders] example - normalmap rendering", 800, 450,
    J.Desktop.frames_arg(args), core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
