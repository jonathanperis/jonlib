# raylib [core] example - input virtual controls, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_input_virtual_controls.c
# (zlib/libpng, Copyright (c) 2024-2025 GreenSnakeLinux (@GreenSnakeLinux)
# and Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A four-button pad drawn on screen moves a circle: the button nearest the
# touch point (or the mouse while its left button is down) within the
# button's radius, by taxicab distance, is the pressed one. DrawCircleV's
# sinf/cosf follow the libm profile (whole degrees only). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# pressed: 0 up, 1 left, 2 right, 3 down, 4 none.
type State is Data:
  State{valid: Bool, pressed: U32, player: M.Vector2}

# buttonPositions[]: buttonRadius*1.5f from the pad's center (100, 350).
def button(index: U32) -> M.Vector2:
  match index:
    case 0: M.Vector2{100.0, (350.0 - 30.0 * 1.5 : F32)}
    case 1: M.Vector2{(100.0 - 30.0 * 1.5 : F32), 350.0}
    case 2: M.Vector2{(100.0 + 30.0 * 1.5 : F32), 350.0}
    case _: M.Vector2{100.0, (350.0 + 30.0 * 1.5 : F32)}

def label(index: U32) -> U32:
  match index:
    case 0: J.Color.YELLOW()
    case 1: J.Color.BLUE()
    case 2: J.Color.RED()
    case _: J.Color.GREEN()

# fabsf(button.x - input.x) + fabsf(button.y - input.y) < buttonRadius.
def near(+at: M.Vector2, +input: M.Vector2) -> Bool:
  M.Vector2{+bx, +by} = at
  M.Vector2{+ix, +iy} = input
  (F32.abs((bx - ix : F32)) + F32.abs((by - iy : F32)) < 30.0 : F32)

# The first button near the input, else none.
def pressed(n: Nat, +i: U32, +input: M.Vector2) -> U32:
  match n:
    case 0n: 4
    case 1n+p: Bool.pick(U32, near(button(i), input), i, pressed(p, (i + 1 : U32), input))

# playerPosition moves playerSpeed*GetFrameTime() the pressed button's way.
def moved(+pressed: U32, +player: M.Vector2, +step: F32, button: U32) -> State:
  M.Vector2{+x, +y} = player
  match button:
    case 0: State{True{}, pressed, M.Vector2{x, (y - step : F32)}}
    case 1: State{True{}, pressed, M.Vector2{(x - step : F32), y}}
    case 2: State{True{}, pressed, M.Vector2{(x + step : F32), y}}
    case 3: State{True{}, pressed, M.Vector2{x, (y + step : F32)}}
    case _: State{True{}, pressed, player}

def moved.by(+button: U32, +player: M.Vector2, +step: F32) -> State:
  moved(button, player, step, button)

def update.at(+core: J.Core, +player: M.Vector2, +active: Bool, input: Maybe<M.Vector2>) -> State:
  match input:
    case None{}: State{False{}, 4, player}
    case Some{+position}: moved.by(Bool.pick(U32, active, pressed(4n, 0, position), 4), player, (75.0 * J.Core.get_frame_time(core) : F32))

# GetTouchPosition(0) with a touch point, else GetMousePosition().
def input(touching: Bool, +core: J.Core) -> Maybe<M.Vector2>:
  match touching:
    case True{}: J.Input.get_touch_position(core, 0)
    case False{}: Some{J.Input.get_mouse_position(core)}

# A touch presses; without one the left mouse button must be down.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{_, _, +player} = state
  +touching = (J.Input.get_touch_point_count(core) > 0 : U32)
  (core, update.at(core, player, touching || J.Input.is_mouse_button_down(core, 0), input(touching, core)))

# arrowTris[i]: the arrow on its button.
def arrow(+at: M.Vector2, +color: U32, frame: J.Frame, index: U32) -> J.Frame:
  M.Vector2{+x, +y} = at
  match index:
    case 0: J.Draw.triangle(frame, M.Vector2{x, (y - 12.0 : F32)}, M.Vector2{(x - 9.0 : F32), (y + 9.0 : F32)}, M.Vector2{(x + 9.0 : F32), (y + 9.0 : F32)}, color)
    case 1: J.Draw.triangle(frame, M.Vector2{(x + 9.0 : F32), (y - 9.0 : F32)}, M.Vector2{(x - 12.0 : F32), y}, M.Vector2{(x + 9.0 : F32), (y + 9.0 : F32)}, color)
    case 2: J.Draw.triangle(frame, M.Vector2{(x + 12.0 : F32), y}, M.Vector2{(x - 9.0 : F32), (y - 9.0 : F32)}, M.Vector2{(x - 9.0 : F32), (y + 9.0 : F32)}, color)
    case _: J.Draw.triangle(frame, M.Vector2{(x - 9.0 : F32), (y - 9.0 : F32)}, M.Vector2{x, (y + 12.0 : F32)}, M.Vector2{(x + 9.0 : F32), (y - 9.0 : F32)}, color)

# DrawCircleV(buttonPositions[i], buttonRadius, pressed? DARKGRAY : BLACK) and its arrow.
def pad(n: Nat, +libm: M.Libm, +i: U32, +pressed: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: pad(p, libm, (i + 1 : U32), pressed,
      arrow(button(i), label(i), J.Draw.circle_v_for(libm, frame, button(i), 30.0, Bool.pick(U32, U32.is_eq(i, pressed), J.Color.DARKGRAY(), J.Color.BLACK())), i))

def draw.valid(valid: Bool, +libm: M.Libm, +state: State, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}:
      State{_, +pressed, +player} = state
      f1 = J.Draw.circle_v_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), player, 50.0, J.Color.MAROON())
      J.Draw.text(pad(4n, libm, 0, pressed, f1), "move the player with D-Pad buttons", 10.0, 10.0, 20.0, J.Color.DARKGRAY())

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _} = state
  (core, (state, draw.valid(valid, libm, state, frame)))

# The main loop's body; libm is the profile of DrawCircleV's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): the player at the center, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{True{}, 4, M.Vector2{(800.0 / 2.0 : F32), (450.0 / 2.0 : F32)}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - input virtual controls", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
