# raylib [core] example - basic window, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_basic_window.c (zlib/libpng,
# Copyright (c) 2013-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Build: bun main.ts examples/core_basic_window.bend -o core_basic_window, then
# run ./core_basic_window (`--frames N` stops after N frames). The headless
# replay against raylib is tools/examples_probe.py; see docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.text(f1, "Congrats! You created your first window!", 190.0, 200.0, 20.0, J.Color.LIGHTGRAY())
  (core, (state, f2))

# The main loop's body; libm is the sinf/cosf profile (unused here).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - basic window", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
