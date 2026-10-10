# raylib [core] example - input multitouch, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_input_multitouch.c (zlib/libpng,
# Copyright (c) 2019-2025 Berni (@Berni8k) and Ramon Santamaria (@raysan5));
# see LICENSES/raylib.txt.
#
# An orange ball and its index at each touch point (up to 10). No platform
# here reports touch points (GetTouchPointCount stays 0 on the memory
# platform and in the desktop driver), so only the hint text is drawn. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def ball.label(text: Maybe<String>, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, (F32.trunc(x) - 10.0 : F32), (F32.trunc(y) - 70.0 : F32), 40.0, J.Color.BLACK())

# DrawCircleV(position, 34, ORANGE) and its index, for a position right of and below the origin.
def ball.at(visible: Bool, +libm: M.Libm, +i: U32, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: ball.label(J.Text.format("%d", [J.TextInt{i}]), x, y, J.Draw.circle_v_for(libm, frame, M.Vector2{x, y}, 34.0, J.Color.ORANGE()))

def ball.placed(+libm: M.Libm, +i: U32, position: M.Vector2, frame: J.Frame) -> J.Frame:
  M.Vector2{+x, +y} = position
  ball.at((x > 0.0 : F32) && (y > 0.0 : F32), libm, i, x, y, frame)

def ball(+libm: M.Libm, +i: U32, position: Maybe<M.Vector2>, frame: J.Frame) -> J.Frame:
  match position:
    case None{}: frame
    case Some{p}: ball.placed(libm, i, p, frame)

def balls(n: Nat, +libm: M.Libm, +core: J.Core, +i: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: balls(p, libm, core, (i + 1 : U32), ball(libm, i, J.Input.get_touch_position(core, i), frame))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  +count = U32.min(J.Input.get_touch_point_count(core), 10)
  f1 = balls(U32.to_nat(count), libm, core, 0, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  (core, (state, J.Draw.text(f1, "touch the screen at multiple locations to get multiple balls", 10.0, 10.0, 20.0, J.Color.DARKGRAY())))

# The main loop's body; libm is the sinf/cosf profile of DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - input multitouch", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
