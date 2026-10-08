# raylib [core] example - input mouse, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_input_mouse.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The ball follows the mouse; a mouse button press changes its color, H
# toggles the cursor flag (Base cannot hide the OS cursor: IsCursorHidden
# changes, the cursor stays visible; docs/DRIVER.md). Build and run as
# examples/core_basic_window.bend.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{ball: M.Vector2, color: U32}

def toggled(+pressed: Bool, +core: J.Core) -> J.Core:
  Bool.pick(J.Core, pressed, Bool.pick(J.Core, J.Input.is_cursor_hidden(core), J.Input.show_cursor(core), J.Input.hide_cursor(core)), core)

def pressed(+core: J.Core, +button: U32) -> Bool:
  J.Input.is_mouse_button_pressed(core, button)

# The if / else-if chain over the seven buttons, left first.
def color(+core: J.Core, +current: U32) -> U32:
  Bool.pick(U32, pressed(core, J.MouseButton.MOUSE_BUTTON_LEFT()), J.Color.MAROON(),
    Bool.pick(U32, pressed(core, J.MouseButton.MOUSE_BUTTON_MIDDLE()), J.Color.LIME(),
      Bool.pick(U32, pressed(core, J.MouseButton.MOUSE_BUTTON_RIGHT()), J.Color.DARKBLUE(),
        Bool.pick(U32, pressed(core, J.MouseButton.MOUSE_BUTTON_SIDE()), J.Color.PURPLE(),
          Bool.pick(U32, pressed(core, J.MouseButton.MOUSE_BUTTON_EXTRA()), J.Color.YELLOW(),
            Bool.pick(U32, pressed(core, J.MouseButton.MOUSE_BUTTON_FORWARD()), J.Color.ORANGE(),
              Bool.pick(U32, pressed(core, J.MouseButton.MOUSE_BUTTON_BACK()), J.Color.BEIGE(), current)))))))

def update.with(+core: J.Core, +current: U32) -> J.Core & State:
  (core, State{J.Input.get_mouse_position(core), color(core, current)})

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{_, +current} = state
  update.with(toggled(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_H()), core), current)

def cursor.text(+hidden: Bool, frame: J.Frame) -> J.Frame:
  match hidden:
    case True{}: J.Draw.text(frame, "CURSOR HIDDEN", 20.0, 60.0, 20.0, J.Color.RED())
    case False{}: J.Draw.text(frame, "CURSOR VISIBLE", 20.0, 60.0, 20.0, J.Color.LIME())

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+ball, +ball_color} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.circle_v_for(libm, f1, ball, 40.0, ball_color)
  f3 = J.Draw.text(f2, "move ball with mouse and click mouse button to change color", 10.0, 10.0, 20.0, J.Color.DARKGRAY())
  f4 = J.Draw.text(f3, "Press 'H' to toggle cursor visibility", 10.0, 30.0, 20.0, J.Color.DARKGRAY())
  (core, (State{ball, ball_color}, cursor.text(J.Input.is_cursor_hidden(core), f4)))

# The main loop's body; libm is the sinf/cosf profile of DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): the ball off screen in DARKBLUE, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{M.Vector2{F32.neg(100.0), F32.neg(100.0)}, J.Color.DARKBLUE()}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - input mouse", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
