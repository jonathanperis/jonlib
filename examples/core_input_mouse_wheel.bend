# raylib [core] example - input mouse wheel, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_input_mouse_wheel.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The mouse wheel moves the box up and down. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# boxPositionY as a C int (two's complement in a U32).
type State is Data:
  State{y: U32}

# (int) of an F32: truncation toward zero, two's complement.
def int(+x: F32) -> U32:
  Bool.pick(U32, (x < 0.0 : F32), (0 - F32.to_u32(F32.neg(F32.trunc(x))) : U32), F32.to_u32(F32.trunc(x)))

def signed(+value: U32) -> F32:
  Bool.pick(F32, (value >= 2147483648 : U32), F32.neg(U32.to_f32((0 - value : U32))), U32.to_f32(value))

# boxPositionY -= (int)(GetMouseWheelMove()*scrollSpeed), scrollSpeed 4.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+y} = state
  (core, State{(y - int((J.Input.get_mouse_wheel_move(core) * 4.0 : F32)) : U32)})

def draw.position(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 40.0, 20.0, J.Color.LIGHTGRAY())

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+y} = state
  f1 = J.Draw.rectangle(J.Frame.clear_background(frame, J.Color.RAYWHITE()), 360.0, signed(y), 80.0, 80.0, J.Color.MAROON())
  f2 = J.Draw.text(f1, "Use mouse wheel to move the cube up and down!", 10.0, 10.0, 20.0, J.Color.GRAY())
  (core, (state, draw.position(J.Text.format("Box position Y: %03i", [J.TextInt{y}]), f2)))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): boxPositionY = 450/2 - 40, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{185}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - input mouse wheel", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
