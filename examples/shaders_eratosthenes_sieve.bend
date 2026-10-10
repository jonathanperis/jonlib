# raylib [shaders] example - eratosthenes sieve, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_eratosthenes_sieve.c
# (zlib/libpng, Copyright (c) 2019-2025 ProfJski (@ProfJski) and Ramon Santamaria
# (@raysan5)); see LICENSES/raylib.txt.
#
# A black 800x450 render texture drawn (flipped) through the sieve shader. On
# the software renderer shaders do not exist (docs/SHADERS.md): the shader
# loads with id 0 and the texture draws as in the default mode, black, which
# is what the reference draws too. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{target: Maybe<J.RenderTexture>, shader: J.Shader}

def update(+core: J.Core, state: State) -> J.Core & State:
  (core, state)

def shown(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (frame, Some{J.RenderTexture{id, texture, depth}})

# DrawTextureRec(target.texture, (0, 0, width, -height), (0, 0), WHITE).
def show(frame: J.Frame, target: J.RenderTexture) -> J.Frame & Maybe<J.RenderTexture>:
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  shown(id, depth, J.Draw.texture_rec(frame, J.Texture{tid, w, h, format, linear, alpha, texels},
    J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))}, M.Vector2.zero(), J.Color.WHITE()))

def shown.done(+core: J.Core, +shader: J.Shader, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  (core, (State{target, shader}, J.Frame.end_shader_mode(frame)))

def displayed(+core: J.Core, +shader: J.Shader, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{None{}, shader}, frame))
    case Some{t}: shown.done(core, shader, show(J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader), t))

# The texture pass (raylib draws it before BeginDrawing; here the draw does
# that first, the same pixels), then the screen.
def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{target, +shader} = state
  match target:
    case None{}: (core, (State{None{}, shader}, J.Frame.clear_background(frame, J.Color.RAYWHITE())))
    case Some{t}:
      painted = J.Draw.rectangle(J.Frame.clear_background(J.Frame.begin_texture_mode(frame, t), J.Color.BLACK()), 0.0, 0.0, 800.0, 450.0, J.Color.BLACK())
      displayed(core, shader, J.Frame.end_texture_mode(painted))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.loaded(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, State{target, J.Shader.load(None{}, Some{"resources/shaders/glsl330/eratosthenes.fs"})}))

# After InitWindow(800, 450): the 800x450 render texture, the shader, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(core, J.RenderTexture.load(frame, 800, 450))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - eratosthenes sieve", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
