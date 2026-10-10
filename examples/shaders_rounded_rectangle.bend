# raylib [shaders] example - rounded rectangle, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_rounded_rectangle.c
# (zlib/libpng, Copyright (c) 2025 Anstro Pleuton (@anstropleuton)); see
# LICENSES/raylib.txt.
#
# Four labelled frames, each followed by a full-screen white rectangle drawn
# through the rounded-rectangle SDF shader. On the software renderer shaders
# do not exist (docs/SHADERS.md): the shader loads with id 0, its uniforms
# (the rectangle, radii, colors, shadow and border, set before each pass) are
# ignored and each pass draws a plain white screen over what came before, so
# only the closing credit line remains visible, which is what the reference
# draws too. The uniform calls are left out here: nothing reads them. Jonlib
# strings are C byte strings, so the credit's n-tilde is written as its two
# UTF-8 bytes. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{shader: J.Shader}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

# DrawRectangleLines(x - m, y - m, w + 2m, h + 2m, DARKGRAY) and the label at
# (x - m, y - m - 15), then the shader pass.
def pass(+shader: J.Shader, +x: F32, +y: F32, +w: F32, +h: F32, +m: F32, label: String, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.rectangle_lines(frame, (x - m : F32), (y - m : F32), (w + 2.0 * m : F32), (h + 2.0 * m : F32), J.Color.DARKGRAY())
  f2 = J.Draw.text(f1, label, (x - m : F32), (y - m - 15.0 : F32), 10.0, J.Color.DARKGRAY())
  J.Frame.end_shader_mode(J.Draw.rectangle(J.Frame.begin_shader_mode(f2, shader), 0.0, 0.0, 800.0, 450.0, J.Color.WHITE()))

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+shader} = state
  f1 = pass(shader, 50.0, 70.0, 110.0, 60.0, 20.0, "Rounded rectangle", J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = pass(shader, 50.0, 200.0, 110.0, 60.0, 20.0, "Rounded rectangle shadow", f1)
  f3 = pass(shader, 50.0, 330.0, 110.0, 60.0, 20.0, "Rounded rectangle border", f2)
  f4 = pass(shader, 240.0, 80.0, 500.0, 300.0, 30.0, "Rectangle with all three combined", f3)
  (core, (state, J.Draw.text(f4, "(c) Rounded rectangle SDF by I\u{c3}\u{b1}igo Quilez. MIT License.", 500.0, 430.0, 10.0, J.Color.BLACK())))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): LoadShader(base.vs, rounded_rectangle.fs), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Shader.load(Some{"resources/shaders/glsl330/base.vs"}, Some{"resources/shaders/glsl330/rounded_rectangle.fs"})}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - rounded rectangle", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
