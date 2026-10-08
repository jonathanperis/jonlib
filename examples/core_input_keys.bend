# raylib [core] example - input keys, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_input_keys.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Move the ball with the arrow keys. Build and run as
# examples/core_basic_window.bend; see docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{ball: M.Vector2}

def step(+down: Bool, +value: F32, +delta: F32) -> F32:
  Bool.pick(F32, down, (value + delta : F32), value)

def update.moved(+core: J.Core, +x: F32, +y: F32) -> J.Core & State:
  +x1 = step(J.Input.is_key_down(core, J.KeyboardKey.KEY_RIGHT()), x, 2.0)
  +x2 = step(J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT()), x1, F32.neg(2.0))
  +y1 = step(J.Input.is_key_down(core, J.KeyboardKey.KEY_UP()), y, F32.neg(2.0))
  +y2 = step(J.Input.is_key_down(core, J.KeyboardKey.KEY_DOWN()), y1, 2.0)
  (core, State{M.Vector2{x2, y2}})

def update.ball(+core: J.Core, +ball: M.Vector2) -> J.Core & State:
  M.Vector2{x, y} = ball
  update.moved(core, x, y)

# Each arrow key moves the ball 2 units (raylib's four independent ifs).
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+ball} = state
  update.ball(core, ball)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+ball} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.text(f1, "move the ball with arrow keys", 10.0, 10.0, 20.0, J.Color.DARKGRAY())
  f3 = J.Draw.circle_v_for(libm, f2, ball, 50.0, J.Color.MAROON())
  (core, (State{ball}, f3))

# The main loop's body; libm is the sinf/cosf profile of DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): the ball at the screen's center, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{M.Vector2{400.0, 225.0}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - input keys", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
