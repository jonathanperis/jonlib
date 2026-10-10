# raylib [shaders] example - raymarching rendering, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_raymarching_rendering.c
# (zlib/libpng, Copyright (c) 2018-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A full-screen white rectangle drawn through the raymarching shader, with a
# credit line. On the software renderer shaders do not exist
# (docs/SHADERS.md): the shader loads with id 0 and the rectangle stays
# white, which is what the reference draws too. The first-person camera and
# the run time only reach the shader's uniforms, which nothing reads, so they
# are not tracked here. Jonlib strings are C byte strings, so the credit's
# n-tilde is written as its two UTF-8 bytes. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{shader: J.Shader}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+shader} = state
  f1 = J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader)
  f2 = J.Frame.end_shader_mode(J.Draw.rectangle(f1, 0.0, 0.0, 800.0, 450.0, J.Color.WHITE()))
  (core, (state, J.Draw.text(f2, "(c) Raymarching shader by I\u{c3}\u{b1}igo Quilez. MIT License.", (800.0 - 280.0 : F32), (450.0 - 20.0 : F32), 10.0, J.Color.BLACK())))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After SetConfigFlags(FLAG_WINDOW_RESIZABLE) and InitWindow(800, 450):
# LoadShader(0, raymarching.fs) with its resolution, DisableCursor(), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  +s0 = J.Shader.load(None{}, Some{"resources/shaders/glsl330/raymarching.fs"})
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{J.Shader.set_value(s0, J.Shader.get_location(s0, "resolution"), [F32.bits(800.0), F32.bits(450.0)], 1)}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - raymarching rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
