# raylib [shaders] example - texture rendering, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_texture_rendering.c
# (zlib/libpng, Copyright (c) 2019-2025 Michał Ciesielski (@ciessielski) and
# Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A blank 1024x1024 texture drawn through the cubes-panning shader, animated
# by its uTime uniform. On the software renderer shaders do not exist
# (docs/SHADERS.md): the shader loads with id 0, the uniform is ignored and
# the blank texture leaves the background as it is, which is what the
# reference draws too. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{texture: Maybe<J.Texture>, shader: J.Shader}

# The per-frame uTime = (float)GetTime() only reaches the ignored uniform.
def update(+core: J.Core, state: State) -> J.Core & State:
  (core, state)

def draw.kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

def draw.texture(frame: J.Frame, texture: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: draw.kept(J.Draw.texture(frame, t, 0.0, 0.0, J.Color.WHITE()))

def draw.done(+core: J.Core, +shader: J.Shader, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{texture, shader}, J.Draw.text(J.Frame.end_shader_mode(frame), "BACKGROUND is PAINTED and ANIMATED on SHADER!", 10.0, 10.0, 20.0, J.Color.MAROON())))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{texture, +shader} = state
  draw.done(core, shader, draw.texture(J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader), texture))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.uploaded(+core: J.Core, +shader: J.Shader, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{texture, shader}))

def setup.image(+core: J.Core, +shader: J.Shader, frame: J.Frame, image: Maybe<J.Surface>) -> J.Core & (J.Frame & State):
  match image:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, shader}))
    case Some{i}: setup.uploaded(core, shader, J.Texture.load_from_image(frame, i))

# After InitWindow(800, 450): a texture from GenImageColor(1024, 1024, BLANK),
# LoadShader(0, cubes_panning.fs) with uTime 0, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  +s0 = J.Shader.load(None{}, Some{"resources/shaders/glsl330/cubes_panning.fs"})
  +shader = J.Shader.set_value(s0, J.Shader.get_location(s0, "uTime"), [F32.bits(0.0)], 0)
  setup.image(core, shader, frame, J.Surface.create(1024, 1024, J.Color.BLANK()))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - texture rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
