# raylib [shaders] example - vertex displacement, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_vertex_displacement.c
# (zlib/libpng, Copyright (c) 2023-2025 Alex ZH (@ZzzhHe)); see
# LICENSES/raylib.txt.
#
# A 50x50 plane of 50x50 quads under a free camera, drawn through a shader
# that would displace its vertices by a Perlin noise texture over time. On
# the software renderer shaders do not exist (docs/SHADERS.md): the shader
# loads with id 0, the time uniform and the sampler are ignored
# (rlSetUniformSampler has no body there) and the plane stays flat and
# white, which is what the reference draws too. The noise texture is still
# generated, uploaded and bound with rlEnableTexture, as the example does;
# the model's material keeps no shader (materials[0].shader has no effect).
# The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md); a refused UpdateCamera refuses the frame and every
# later one. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{camera: +Maybe<J.Camera3D>, model: +Maybe<J.Model>, textures: List<J.Texture>, shader: J.Shader, time: F32}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{20.0, 5.0, F32.neg(20.0)}, M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 60.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def moved(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def update.camera(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_FREE()))

# UpdateCamera, time += GetFrameTime(), SetShaderValue(shader, "time", &time, SHADER_UNIFORM_FLOAT).
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+camera, +model, textures, +shader, +time} = state
  +t = (time + J.Core.get_frame_time(core) : F32)
  (core, State{update.camera(libm, core, camera), model, textures, J.Shader.set_value(shader, J.Shader.get_location(shader, "time"), [F32.bits(t)], 0), t})

def scene.done(+camera: J.Camera3D, +model: J.Model, +shader: J.Shader, +time: F32, r: J.Frame & List<J.Texture>) -> State & J.Frame:
  (frame, textures) = r
  (State{Some{camera}, Some{model}, textures, shader, time}, J.Frame.end_mode_3d(J.Frame.end_shader_mode(frame)))

def scene.model(model: +Maybe<J.Model>, +libm: M.Libm, +camera: J.Camera3D, textures: List<J.Texture>, +shader: J.Shader, +time: F32, frame: J.Frame) -> State & J.Frame:
  match model:
    case None{}: (State{Some{camera}, None{}, textures, shader, time}, J.Frame.refuse(frame))
    case Some{+m}:
      f1 = J.Frame.begin_shader_mode(J.Frame.begin_mode_3d_for(libm, frame, camera), shader)
      scene.done(camera, m, shader, time, J.Draw.model(f1, textures, m, M.Vector3.zero(), 1.0, J.Color.rgba(255, 255, 255, 255)))

def scene(camera: +Maybe<J.Camera3D>, +libm: M.Libm, +model: +Maybe<J.Model>, textures: List<J.Texture>, +shader: J.Shader, +time: F32, frame: J.Frame) -> State & J.Frame:
  match camera:
    case None{}: (State{None{}, model, textures, shader, time}, J.Frame.refuse(frame))
    case Some{+c}: scene.model(model, libm, c, textures, shader, time, frame)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 40.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.text(+core: J.Core, r: State & J.Frame) -> J.Core & (State & J.Frame):
  (state, frame) = r
  draw.fps.done(state, J.Draw.text(frame, "Vertex displacement", 10.0, 10.0, 20.0, J.Color.DARKGRAY()), J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +model, textures, +shader, +time} = state
  draw.text(core, scene(camera, libm, model, textures, shader, time, J.Frame.clear_background(frame, J.Color.RAYWHITE())))

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf/atan2f and BeginMode3D's tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def shader() -> J.Shader:
  J.Shader.load(Some{"resources/shaders/glsl330/vertex_displacement.vs"}, Some{"resources/shaders/glsl330/vertex_displacement.fs"})

def kept(previous: Maybe<J.Texture>) -> List<J.Texture>:
  match previous:
    case None{}: Nil{}
    case Some{t}: [t]

def plane(mesh: Maybe<J.Mesh>) -> +Maybe<J.Model>:
  match mesh:
    case None{}: None{}
    case Some{+m}: Some{J.Model.from_mesh(m)}

# GenMeshPlane(50, 50, 50, 50), LoadModelFromMesh, SetTargetFPS(60).
def setup.done(+core: J.Core, frame: J.Frame, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{Some{start()}, plane(J.Mesh.gen_plane(50.0, 50.0, 50, 50)), textures, shader(), 0.0}))

def setup.bound(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, previous) = r
  setup.done(core, J.Rlgl.set_uniform_sampler(frame, J.Shader.get_location(shader(), "perlinNoiseMap"), 1), kept(previous))

# rlEnableShader(shader.id), rlActiveTextureSlot(1), rlEnableTexture(perlinNoiseMap.id), rlSetUniformSampler(perlinNoiseMapLoc, 1).
def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: setup.done(core, frame, Nil{})
    case Some{t}: setup.bound(core, J.Rlgl.enable_texture(J.Rlgl.active_texture_slot(J.Rlgl.enable_shader(frame, 0), 1), t))

def setup.noise(+core: J.Core, frame: J.Frame, image: Maybe<J.Surface>) -> J.Core & (J.Frame & State):
  match image:
    case None{}: setup.done(core, frame, Nil{})
    case Some{i}: setup.uploaded(core, J.Texture.load_from_image(frame, i))

# After InitWindow(800, 450): the shader, GenImagePerlinNoise(512, 512, 0, 0, 1.0f) as a texture bound to the
# shader's sampler, and the plane model.
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.noise(core, frame, J.Surface.create_perlin(512, 512, 0.0, 0.0, 1.0))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - vertex displacement", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
