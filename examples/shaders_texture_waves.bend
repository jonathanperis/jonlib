# raylib [shaders] example - texture waves, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_texture_waves.c (zlib/libpng,
# Copyright (c) 2019-2025 Anata (@anatagawa) and Ramon Santamaria (@raysan5));
# see LICENSES/raylib.txt.
#
# The space texture twice, side by side, inside the wave shader's mode. On the
# software renderer shaders do not exist (docs/SHADERS.md): the shader loads
# with id 0, its uniforms (the size, frequencies, amplitudes, speeds and the
# seconds advanced by the frame time) are ignored and the textures draw as in
# the default mode, which is what the reference draws too. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{texture: Maybe<J.Texture>, shader: J.Shader, seconds: F32}

def float(+value: F32) -> +List<U32>:
  [F32.bits(value)]

# seconds += GetFrameTime(); SetShaderValue(shader, secondsLoc, &seconds, SHADER_UNIFORM_FLOAT).
def update(+core: J.Core, state: State) -> J.Core & State:
  State{texture, +shader, +seconds} = state
  +next = (seconds + J.Core.get_frame_time(core) : F32)
  (core, State{texture, J.Shader.set_value(shader, J.Shader.get_location(shader, "seconds"), float(next), 0), next})

def draw.kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

# DrawTexture(texture, texture.width, 0, WHITE).
def draw.second(+w: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  draw.kept(J.Draw.texture(frame, texture, U32.to_f32(w), 0.0, J.Color.WHITE()))

def draw.twice(frame: J.Frame, texture: J.Texture) -> J.Frame & Maybe<J.Texture>:
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  draw.second(w, J.Draw.texture(frame, J.Texture{id, w, h, format, linear, alpha, texels}, 0.0, 0.0, J.Color.WHITE()))

def draw.texture(frame: J.Frame, texture: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: draw.twice(frame, t)

def draw.done(+core: J.Core, +shader: J.Shader, +seconds: F32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{texture, shader, seconds}, J.Frame.end_shader_mode(frame)))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{texture, +shader, +seconds} = state
  draw.done(core, shader, seconds, draw.texture(J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader), texture))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# LoadShader(0, wave.fs) and its uniforms: size (800, 450), freqX/freqY 25,
# ampX/ampY 5, speedX/speedY 8 (all ignored here, as on the software renderer).
def shader() -> J.Shader:
  +s0 = J.Shader.load(None{}, Some{"resources/shaders/glsl330/wave.fs"})
  +s1 = J.Shader.set_value(s0, J.Shader.get_location(s0, "size"), [F32.bits(800.0), F32.bits(450.0)], 1)
  +s2 = J.Shader.set_value(s1, J.Shader.get_location(s1, "freqX"), float(25.0), 0)
  +s3 = J.Shader.set_value(s2, J.Shader.get_location(s2, "freqY"), float(25.0), 0)
  +s4 = J.Shader.set_value(s3, J.Shader.get_location(s3, "ampX"), float(5.0), 0)
  +s5 = J.Shader.set_value(s4, J.Shader.get_location(s4, "ampY"), float(5.0), 0)
  +s6 = J.Shader.set_value(s5, J.Shader.get_location(s5, "speedX"), float(8.0), 0)
  J.Shader.set_value(s6, J.Shader.get_location(s6, "speedY"), float(8.0), 0)

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{texture, shader(), 0.0}))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, shader(), 0.0}))
    case Done{image}: setup.uploaded(core, J.Texture.load_from_image(frame, image))

# After InitWindow(800, 450): LoadTexture("resources/space.png") (the PNG
# loader, as LoadTexture selects it), the shader, SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/space.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - texture waves", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
