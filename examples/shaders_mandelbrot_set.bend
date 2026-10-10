# raylib [shaders] example - mandelbrot set, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_mandelbrot_set.c
# (zlib/libpng, Copyright (c) 2025 Jordi Santonja (@JordSant)); see
# LICENSES/raylib.txt.
#
# A black screen-sized render texture drawn through the Mandelbrot shader,
# with the controls text (F1 toggles it). On the software renderer shaders do
# not exist (docs/SHADERS.md): the shader loads with id 0 and the texture
# draws black, which is what the reference draws too. Everything the keys and
# mouse change besides F1 (the point of interest, zoom, offset and iteration
# count) only reaches the shader's uniforms, which nothing reads, so it is
# not tracked here. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{target: Maybe<J.RenderTexture>, shader: J.Shader, controls: Bool}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{target, +shader, +controls} = state
  (core, State{target, shader, Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_F1()), Bool.not(controls), controls)})

def shown(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (frame, Some{J.RenderTexture{id, texture, depth}})

# DrawTextureEx(target.texture, (0, 0), 0, 1, WHITE).
def show(frame: J.Frame, target: J.RenderTexture) -> J.Frame & Maybe<J.RenderTexture>:
  J.RenderTexture{+id, texture, +depth} = target
  shown(id, depth, J.Draw.texture_ex(frame, texture, M.Vector2.zero(), 0.0, 1.0, J.Color.WHITE()))

def controls(on: Bool, frame: J.Frame) -> J.Frame:
  match on:
    case False{}: frame
    case True{}:
      f1 = J.Draw.text(frame, "Press Mouse buttons right/left to zoom in/out and move", 10.0, 15.0, 10.0, J.Color.RAYWHITE())
      f2 = J.Draw.text(f1, "Press F1 to toggle these controls", 10.0, 30.0, 10.0, J.Color.RAYWHITE())
      f3 = J.Draw.text(f2, "Press [1 - 6] to change point of interest", 10.0, 45.0, 10.0, J.Color.RAYWHITE())
      f4 = J.Draw.text(f3, "Press UP | DOWN to change number of iterations", 10.0, 60.0, 10.0, J.Color.RAYWHITE())
      J.Draw.text(f4, "Press R to recenter the camera", 10.0, 75.0, 10.0, J.Color.RAYWHITE())

def shown.done(+core: J.Core, +shader: J.Shader, +on: Bool, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  (core, (State{target, shader, on}, controls(on, J.Frame.end_shader_mode(frame))))

def displayed(+core: J.Core, +shader: J.Shader, +on: Bool, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{None{}, shader, on}, controls(on, J.Frame.clear_background(frame, J.Color.BLACK()))))
    case Some{t}: shown.done(core, shader, on, show(J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.BLACK()), shader), t))

# The texture pass (raylib draws it before BeginDrawing; here the draw does
# that first, the same pixels), then the screen.
def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{target, +shader, +on} = state
  match target:
    case None{}: (core, (State{None{}, shader, on}, controls(on, J.Frame.clear_background(frame, J.Color.BLACK()))))
    case Some{t}:
      painted = J.Draw.rectangle(J.Frame.clear_background(J.Frame.begin_texture_mode(frame, t), J.Color.BLACK()), 0.0, 0.0, 800.0, 450.0, J.Color.BLACK())
      displayed(core, shader, on, J.Frame.end_texture_mode(painted))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.loaded(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, State{target, J.Shader.load(None{}, Some{"resources/shaders/glsl330/mandelbrot_set.fs"}), True{}}))

# After InitWindow(800, 450): LoadShader(0, mandelbrot_set.fs), the 800x450 render
# texture, the controls shown, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(core, J.RenderTexture.load(frame, 800, 450))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - mandelbrot set", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
