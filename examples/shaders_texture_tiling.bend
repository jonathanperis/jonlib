# raylib [shaders] example - texture tiling, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_texture_tiling.c
# (zlib/libpng, Copyright (c) 2023-2025 Luis Almeida (@luis605)); see
# LICENSES/raylib.txt.
#
# A cube model with the cubicmap atlas, drawn at scale 2 through the tiling
# shader under a free camera (the mouse turns it, Z looks back at (0, 0.5,
# 0)). On the software renderer shaders do not exist (docs/SHADERS.md): the
# shader loads with id 0, the tiling uniform is ignored and the texture maps
# once per face, which is what the reference draws too. The perspective
# needs the libm profile's binary64 tan (docs/PERSPECTIVE.md); a refused
# UpdateCamera refuses the frame and every later one. LoadTexture of a .png
# is the PNG loader (Surface.load_png). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>, shader: J.Shader}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{4.0, 4.0, 4.0}, M.Vector3{0.0, 0.5, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# Z: camera.target = (0, 0.5, 0).
def targeted(+core: J.Core, updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}:
      J.Camera3D{+p, _, +u, +f, +k} = c
      Bool.pick(+Maybe<J.Camera3D>, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_Z()), Some{J.Camera3D{p, M.Vector3{0.0, 0.5, 0.0}, u, f, k}}, Some{c})

def update.camera(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: targeted(core, J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_FREE()))

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+camera, +model, textures, +shader} = state
  (core, State{update.camera(libm, core, camera), model, textures, shader})

def scene.done(+camera: J.Camera3D, +model: J.Model, +shader: J.Shader, r: J.Frame & List<J.Texture>) -> State & J.Frame:
  (frame, textures) = r
  (State{Some{camera}, model, textures, shader}, J.Frame.end_mode_3d(J.Draw.grid(J.Frame.end_shader_mode(frame), 10.0, 1.0)))

def scene(+libm: M.Libm, camera: +Maybe<J.Camera3D>, +model: J.Model, textures: List<J.Texture>, +shader: J.Shader, frame: J.Frame) -> State & J.Frame:
  match camera:
    case None{}: (State{None{}, model, textures, shader}, J.Frame.refuse(frame))
    case Some{+c}:
      f1 = J.Frame.begin_shader_mode(J.Frame.begin_mode_3d_for(libm, frame, c), shader)
      scene.done(c, model, shader, J.Draw.model(f1, textures, model, M.Vector3.zero(), 2.0, J.Color.WHITE()))

def draw.text(+core: J.Core, r: State & J.Frame) -> J.Core & (State & J.Frame):
  (state, frame) = r
  (core, (state, J.Draw.text(frame, "Use mouse to rotate the camera", 10.0, 10.0, 20.0, J.Color.DARKGRAY())))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +model, textures, +shader} = state
  draw.text(core, scene(libm, camera, model, textures, shader, J.Frame.clear_background(frame, J.Color.RAYWHITE())))

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf/atan2f and BeginMode3D's tan.
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

# LoadShader(0, tiling.fs) with tiling (3, 3) (ignored here, as on the software renderer).
def shader() -> J.Shader:
  +s0 = J.Shader.load(None{}, Some{"resources/shaders/glsl330/tiling.fs"})
  J.Shader.set_value(s0, J.Shader.get_location(s0, "tiling"), [F32.bits(3.0), F32.bits(3.0)], 1)

def setup.done(+core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{Some{start()}, model, textures, shader()}))

# SetTextureWrap(texture, TEXTURE_WRAP_REPEAT) after the assignment.
def setup.texture(+core: J.Core, frame: J.Frame, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  setup.done(core, frame, textured(J.Model.from_mesh(J.Mesh.gen_cube(1.0, 1.0, 1.0)), info), [J.Texture.set_wrap(texture, 0)])

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: setup.done(core, frame, J.Model.from_mesh(J.Mesh.gen_cube(1.0, 1.0, 1.0)), Nil{})
    case Some{t}: setup.texture(core, frame, J.Texture.info(t))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: setup.done(core, frame, J.Model.from_mesh(J.Mesh.gen_cube(1.0, 1.0, 1.0)), Nil{})
    case Done{image}: setup.uploaded(core, J.Texture.load_from_image(frame, image))

# After InitWindow(800, 450): the cube model with the cubicmap atlas as its
# diffuse texture, the shader, DisableCursor(), SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cubicmap_atlas.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - texture tiling", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
