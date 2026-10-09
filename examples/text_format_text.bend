# raylib [text] example - format text, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_format_text.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# TextFormat with zero-padded integers and the frame time. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def line(text: Maybe<String>, +y: F32, +size: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 200.0, y, size, color)

# GetFrameTime()*1000 is an F32 product passed to %f as a double.
def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  f1 = line(J.Text.format("Score: %08i", [J.TextInt{100020}]), 80.0, 20.0, J.Color.RED(), J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = line(J.Text.format("HiScore: %08i", [J.TextInt{200450}]), 120.0, 20.0, J.Color.GREEN(), f1)
  f3 = line(J.Text.format("Lives: %02i", [J.TextInt{5}]), 160.0, 40.0, J.Color.BLUE(), f2)
  f4 = line(J.Text.format("Elapsed Time: %02.02f ms", [J.TextFloat{(J.Core.get_frame_time(core) * 1000.0 : F32)}]), 220.0, 20.0, J.Color.BLACK(), f3)
  (core, (state, f4))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - format text", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
