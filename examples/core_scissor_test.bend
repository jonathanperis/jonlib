# raylib [core] example - scissor test, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_scissor_test.c (zlib/libpng,
# Copyright (c) 2019-2025 Chris Dill (@MysteriousSpace) and Ramon Santamaria
# (@raysan5)); see LICENSES/raylib.txt.
#
# A 300x300 scissor window follows the mouse; S toggles it. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{area: J.Rectangle, scissor: Bool}

def signed(+value: U32) -> F32:
  Bool.pick(F32, (value >= 2147483648 : U32), F32.neg(U32.to_f32((0 - value : U32))), U32.to_f32(value))

def mouse(value: Maybe<U32>) -> F32:
  match value:
    case None{}: 0.0
    case Some{+v}: signed(v)

# scissorArea.x = GetMouseX() - width/2 (an int minus an F32), the same for y.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{_, +scissor} = state
  +s = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_S()), Bool.not(scissor), scissor)
  +x = (mouse(J.Input.get_mouse_x(core)) - 300.0 / 2.0 : F32)
  +y = (mouse(J.Input.get_mouse_y(core)) - 300.0 / 2.0 : F32)
  (core, State{J.Rectangle{x, y, 300.0, 300.0}, s})

def scissor.begin(on: Bool, +area: J.Rectangle, frame: J.Frame) -> J.Frame:
  match on:
    case False{}: frame
    case True{}:
      J.Rectangle{+x, +y, +w, +h} = area
      J.Frame.begin_scissor_mode(frame, x, y, w, h)

def scissor.end(on: Bool, frame: J.Frame) -> J.Frame:
  match on:
    case False{}: frame
    case True{}: J.Frame.end_scissor_mode(frame)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+area, +on} = state
  f1 = scissor.begin(on, area, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = J.Draw.rectangle(f1, 0.0, 0.0, U32.to_f32(J.Core.get_screen_width(core)), U32.to_f32(J.Core.get_screen_height(core)), J.Color.RED())
  f3 = scissor.end(on, J.Draw.text(f2, "Move the mouse around to reveal this text!", 190.0, 200.0, 20.0, J.Color.LIGHTGRAY()))
  f4 = J.Draw.rectangle_lines_ex(f3, area, 1.0, J.Color.BLACK())
  (core, (state, J.Draw.text(f4, "Press S to toggle scissor test", 10.0, 10.0, 20.0, J.Color.BLACK())))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): the area (0, 0, 300, 300), scissor on, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Rectangle{0.0, 0.0, 300.0, 300.0}, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - scissor test", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
