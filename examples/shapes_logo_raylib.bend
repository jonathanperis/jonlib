# raylib [shapes] example - logo raylib, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_logo_raylib.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Build and run as examples/core_basic_window.bend; see docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

# screenWidth/2 - 128 = 272, screenHeight/2 - 128 = 97 (C int arithmetic).
def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.rectangle(f1, 272.0, 97.0, 256.0, 256.0, J.Color.BLACK())
  f3 = J.Draw.rectangle(f2, 288.0, 113.0, 224.0, 224.0, J.Color.RAYWHITE())
  f4 = J.Draw.text(f3, "raylib", 356.0, 273.0, 50.0, J.Color.BLACK())
  f5 = J.Draw.text(f4, "this is NOT a texture!", 350.0, 370.0, 10.0, J.Color.GRAY())
  (core, (state, f5))

# The main loop's body; libm is the sinf/cosf profile (unused here).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - logo raylib", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
