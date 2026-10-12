# raylib [core] example - vr simulator, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_vr_simulator.c (zlib/libpng,
# Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A cube on a grid under a first-person camera, drawn into a render texture of
# the VR device's resolution (2160x1200) in stereo mode and then to the screen
# through the lens distortion shader, whose uniforms come from
# LoadVrStereoConfig. raylib's software renderer does not draw in stereo and
# its shaders change nothing (docs/VR.md, docs/SHADERS.md): the scene shows
# once, scaled to the window, there and here. The stereo configuration and
# the perspective need the libm profile's atan2f and binary64 tan
# (docs/PERSPECTIVE.md), UpdateCamera its sinf/cosf (docs/SINCOSF.md); a frame
# Jonlib refuses there refuses every later one. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The camera and the stereo configuration (None once refused), the render
# texture (None when it did not load) and the distortion shader.
type State is Type:
  State{camera: +Maybe<J.Camera3D>, config: +Maybe<J.VrStereoConfig>, target: Maybe<J.RenderTexture>, shader: J.Shader}

# The VR device's parameters (Oculus Rift CV1's): its lens distortion and
# chromatic aberration values, then its screen and lenses.
def distortion() -> M.Vector4:
  M.Vector4{1.0, 0.22, 0.24, 0.0}

def chroma() -> M.Vector4:
  M.Vector4{0.996, F32.neg(0.004), 1.014, 0.0}

def device() -> J.VrDeviceInfo:
  J.VrDeviceInfo{2160, 1200, 0.133793, 0.0669, 0.041, 0.07, 0.07, distortion(), chroma()}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{5.0, 2.0, 5.0}, M.Vector3{0.0, 2.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 60.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def camera.updated(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def camera.update(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: camera.updated(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_FIRST_PERSON()))

# UpdateCamera(&camera, CAMERA_FIRST_PERSON).
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+camera, +config, target, +shader} = state
  (core, State{camera.update(libm, core, camera), config, target, shader})

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# EndShaderMode(); DrawFPS(10, 10).
def draw.shown(+core: J.Core, +camera: J.Camera3D, +config: J.VrStereoConfig, +shader: J.Shader, +id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  draw.fps.done(State{Some{camera}, Some{config}, Some{J.RenderTexture{id, texture, depth}}, shader}, J.Frame.end_shader_mode(frame), J.Core.get_fps(core, J.Core.get_time(core)), core)

# BeginShaderMode(distortion); DrawTexturePro(target.texture, (0, 0, width,
# -height), (0, 0, GetScreenWidth(), GetScreenHeight()), (0, 0), 0.0f, WHITE).
def draw.screen(+core: J.Core, +camera: J.Camera3D, +config: J.VrStereoConfig, +shader: J.Shader, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  draw.shown(core, camera, config, shader, id, depth,
    J.Draw.texture_pro(J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader), J.Texture{tid, w, h, format, linear, alpha, texels},
      J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))}, J.Rectangle{0.0, 0.0, 800.0, 450.0}, M.Vector2.zero(), 0.0, J.Color.WHITE()))

def draw.ended(+core: J.Core, +camera: J.Camera3D, +config: J.VrStereoConfig, +shader: J.Shader, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{Some{camera}, Some{config}, None{}, shader}, J.Frame.refuse(frame)))
    case Some{t}: draw.screen(core, camera, config, shader, frame, t)

# BeginMode3D(camera): DrawCube(cubePosition, 2, 2, 2, RED), DrawCubeWires(...,
# MAROON) and DrawGrid(40, 1.0f); EndMode3D(); EndVrStereoMode();
# EndTextureMode().
def draw.scene(+libm: M.Libm, +camera: J.Camera3D, frame: J.Frame) -> J.Frame & Maybe<J.RenderTexture>:
  f1 = J.Frame.begin_mode_3d_for(libm, frame, camera)
  f2 = J.Draw.cube_wires(J.Draw.cube(f1, M.Vector3.zero(), 2.0, 2.0, 2.0, J.Color.RED()), M.Vector3.zero(), 2.0, 2.0, 2.0, J.Color.MAROON())
  J.Frame.end_texture_mode(J.Frame.end_vr_stereo_mode(J.Frame.end_mode_3d(J.Draw.grid(f2, 40.0, 1.0))))

# The texture pass (raylib draws it before BeginDrawing; here the draw does
# that first, the same pixels): BeginTextureMode(target);
# ClearBackground(RAYWHITE); BeginVrStereoMode(config).
def draw.at(+libm: M.Libm, +core: J.Core, +shader: J.Shader, frame: J.Frame, target: Maybe<J.RenderTexture>, camera: +Maybe<J.Camera3D>, config: +Maybe<J.VrStereoConfig>) -> J.Core & (State & J.Frame):
  match target camera config:
    case Some{t} Some{+c} Some{+v}:
      draw.ended(core, c, v, shader, draw.scene(libm, c, J.Frame.begin_vr_stereo_mode(J.Frame.clear_background(J.Frame.begin_texture_mode(frame, t), J.Color.RAYWHITE()), v)))
    case Some{t} _ _: (core, (State{None{}, None{}, Some{t}, shader}, J.Frame.refuse(frame)))
    case None{} _ _: (core, (State{None{}, None{}, None{}, shader}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +config, target, +shader} = state
  draw.at(libm, core, shader, frame, target, camera, config)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def pair(vector: M.Vector2) -> +List<U32>:
  M.Vector2{x, y} = vector
  [F32.bits(x), F32.bits(y)]

def four(vector: M.Vector4) -> +List<U32>:
  M.Vector4{x, y, z, w} = vector
  [F32.bits(x), F32.bits(y), F32.bits(z), F32.bits(w)]

def uniform(+shader: J.Shader, +name: String, value: +List<U32>, +kind: U32) -> J.Shader:
  J.Shader.set_value(shader, J.Shader.get_location(shader, name), value, kind)

# The distortion shader's uniforms: the six pairs of the configuration
# (SHADER_UNIFORM_VEC2) and the device's lens distortion and chromatic
# aberration values (SHADER_UNIFORM_VEC4).
def uniforms(+shader: J.Shader, config: J.VrStereoConfig) -> J.Shader:
  J.VrStereoConfig{_, _, _, _, ll, rl, ls, rs, scale, scale_in} = config
  s1 = uniform(uniform(shader, "leftLensCenter", pair(ll), 1), "rightLensCenter", pair(rl), 1)
  s2 = uniform(uniform(s1, "leftScreenCenter", pair(ls), 1), "rightScreenCenter", pair(rs), 1)
  s3 = uniform(uniform(s2, "scale", pair(scale), 1), "scaleIn", pair(scale_in), 1)
  uniform(uniform(s3, "deviceWarpParam", four(distortion()), 3), "chromaAbParam", four(chroma()), 3)

def shader.for(config: +Maybe<J.VrStereoConfig>, +shader: J.Shader) -> J.Shader:
  match config:
    case None{}: shader
    case Some{+c}: uniforms(shader, c)

def setup.done(+core: J.Core, +config: +Maybe<J.VrStereoConfig>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{Some{start()}, config, target, shader.for(config, J.Shader.load(None{}, Some{"resources/shaders/glsl330/distortion.fs"}))}))

# After InitWindow(800, 450): LoadVrStereoConfig(device), the distortion
# shader and its uniforms, LoadRenderTexture(device.hResolution,
# device.vResolution), the camera, DisableCursor(), SetTargetFPS(60).
def setup(+libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.done(core, J.Vr.load_stereo_config_for(libm, device()), J.RenderTexture.load(frame, 2160, 1200))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - vr simulator", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
