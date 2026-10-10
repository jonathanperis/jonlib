# raylib [core] example - window web, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_window_web.c (zlib/libpng,
# Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The example's point is its structure for the web (one UpdateDrawFrame
# function handed to emscripten's main loop); on the desktop it is the usual
# loop calling that function, which a J.Program's update and draw already
# are. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.text(f1, "Welcome to raylib web structure!", 220.0, 200.0, 20.0, J.Color.SKYBLUE())
  (core, (state, f2))

# The main loop's body; libm is the sinf/cosf profile (unused here).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - window web", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
