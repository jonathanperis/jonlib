# raylib [shaders] example - multi sample2d, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_multi_sample2d.c
# (zlib/libpng, Copyright (c) 2020-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A red texture drawn through the color-mix shader with a blue texture as its
# second sampler; LEFT/RIGHT move the mixing divider (clamped to [0, 1]). On
# the software renderer shaders do not exist (docs/SHADERS.md): the shader
# loads with id 0, the divider and the sampler are ignored and the red
# texture draws as in the default mode, which is what the reference draws
# too. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{red: Maybe<J.Texture>, blue: Maybe<J.Texture>, shader: J.Shader, divider: F32}

def clamp(+v: F32) -> F32:
  Bool.pick(F32, (v < 0.0 : F32), 0.0, Bool.pick(F32, (v > 1.0 : F32), 1.0, v))

# RIGHT (else LEFT) moves the divider by 0.01, clamped; SetShaderValue(divider).
def update(+core: J.Core, state: State) -> J.Core & State:
  State{red, blue, +shader, +divider} = state
  +right = J.Input.is_key_down(core, J.KeyboardKey.KEY_RIGHT())
  +left = Bool.not(right) && J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT())
  +next = clamp(Bool.pick(F32, right, (divider + 0.01 : F32), Bool.pick(F32, left, (divider - 0.01 : F32), divider)))
  (core, State{red, blue, J.Shader.set_value(shader, J.Shader.get_location(shader, "divider"), [F32.bits(next)], 0), next})

def draw.kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

def draw.texture(frame: J.Frame, texture: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: draw.kept(J.Draw.texture(frame, t, 0.0, 0.0, J.Color.WHITE()))

def draw.done(+core: J.Core, blue: Maybe<J.Texture>, +shader: J.Shader, +divider: F32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, red) = r
  (core, (State{red, blue, shader, divider}, J.Draw.text(J.Frame.end_shader_mode(frame), "Use KEY_LEFT/KEY_RIGHT to move texture mixing in shader!", 80.0, (450.0 - 40.0 : F32), 20.0, J.Color.RAYWHITE())))

# SetShaderValueTexture(shader, texBlueLoc, texBlue) inside the mode is
# ignored with the shader; the red texture draws.
def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{red, blue, +shader, +divider} = state
  draw.done(core, blue, shader, divider, draw.texture(J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader), red))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def upload(frame: J.Frame, image: Maybe<J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match image:
    case None{}: (frame, None{})
    case Some{i}: J.Texture.load_from_image(frame, i)

def setup.blue(+core: J.Core, red: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, blue) = r
  (J.Core.set_target_fps(core, 60), (frame, State{red, blue, J.Shader.load(None{}, Some{"resources/shaders/glsl330/color_mix.fs"}), 0.5}))

def setup.red(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, red) = r
  setup.blue(core, red, upload(frame, J.Surface.create(800, 450, J.Color.rgba(0, 0, 255, 255))))

# After InitWindow(800, 450): the red and blue 800x450 textures
# (GenImageColor), LoadShader(0, color_mix.fs), divider 0.5, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.red(core, upload(frame, J.Surface.create(800, 450, J.Color.rgba(255, 0, 0, 255))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - multi sample2d", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
