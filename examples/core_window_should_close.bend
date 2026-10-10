# raylib [core] example - window should close, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_window_should_close.c (zlib/libpng,
# Copyright (c) 2013-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The window's close button or ESC (the exit key is disabled) only asks for
# confirmation: Y ends the program, N goes back. The example's loop is
# `while (!exitWindow)`, not `while (!WindowShouldClose())`: a J.Until
# program, whose update reads the close request as a value
# (J.Core.window_should_close). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# exitWindowRequested and exitWindow.
type State is Data:
  State{requested: Bool, exit: Bool}

# A close request or ESC asks; while asked, Y exits, else N cancels.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+requested, +exit} = state
  +asked = requested || J.Core.window_should_close(core) || J.Input.is_key_pressed(core, J.KeyboardKey.KEY_ESCAPE())
  +yes = asked && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_Y())
  (core, State{asked && (yes || Bool.not(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_N()))), exit || yes})

def message(requested: Bool, frame: J.Frame) -> J.Frame:
  match requested:
    case True{}: J.Draw.text(J.Draw.rectangle(frame, 0.0, 100.0, 800.0, 200.0, J.Color.BLACK()), "Are you sure you want to exit program? [Y/N]", 40.0, 180.0, 30.0, J.Color.WHITE())
    case False{}: J.Draw.text(frame, "Try to close the window to get confirmation message!", 120.0, 200.0, 20.0, J.Color.LIGHTGRAY())

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+requested, _} = state
  (core, (state, message(requested, J.Frame.clear_background(frame, J.Color.RAYWHITE()))))

# while (!exitWindow).
def done(+state: State) -> State & Bool:
  State{_, +exit} = state
  (state, exit)

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Until{core => state => update(core, state), core => state => frame => draw(core, state, frame), state => done(state)}

# After InitWindow(800, 450): SetExitKey(KEY_NULL), no request, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(J.Input.set_exit_key(core, J.KeyboardKey.KEY_NULL()), 60), (frame, State{False{}, False{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - window should close", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
