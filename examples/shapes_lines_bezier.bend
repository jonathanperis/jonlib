# raylib [shapes] example - lines bezier, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_lines_bezier.c (zlib/libpng,
# Copyright (c) 2013-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Drag the line's start and end points with the left mouse button.
# SetConfigFlags(FLAG_MSAA_4X_HINT) before InitWindow: Desktop.run_flags.
# On the memory platform the previous mouse button state is never updated, so
# IsMouseButtonReleased stays false and a grabbed point follows the mouse for
# good (the replay reproduces that); the desktop driver polls buttons as GLFW
# does. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{start: M.Vector2, end: M.Vector2, move_start: Bool, move_end: Bool}

def near(+mouse: M.Vector2, +point: M.Vector2) -> Bool:
  J.Collision.point_circle(mouse, point, 10.0)

# A moving point follows the mouse until the left button is released.
def follow(+moving: Bool, +released: Bool, +mouse: M.Vector2, +point: M.Vector2) -> M.Vector2 & Bool:
  (Bool.pick(M.Vector2, moving, mouse, point), moving && Bool.not(released))

def update.points(+start: M.Vector2, +end: M.Vector2, +released: Bool, +mouse: M.Vector2, s: M.Vector2 & Bool, e: M.Vector2 & Bool) -> State:
  (+a, +ma) = s
  (+b, +mb) = e
  State{a, b, ma, mb}

def update.grabbed(+core: J.Core, +mouse: M.Vector2, +start: M.Vector2, +end: M.Vector2, +move_start: Bool, +move_end: Bool) -> J.Core & State:
  +released = J.Input.is_mouse_button_released(core, 0)
  (core, update.points(start, end, released, mouse, follow(move_start, released, mouse, start), follow(move_end, released, mouse, end)))

# Grabbing: the start point when the mouse is within 10 of it with the left
# button down, else the end point.
def update.grab(+core: J.Core, +mouse: M.Vector2, +start: M.Vector2, +end: M.Vector2, +move_start: Bool, +move_end: Bool) -> J.Core & State:
  +down = J.Input.is_mouse_button_down(core, 0)
  +grab_start = near(mouse, start) && down
  +grab_end = Bool.not(grab_start) && near(mouse, end) && down
  update.grabbed(core, mouse, start, end, move_start || grab_start, move_end || grab_end)

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+start, +end, +move_start, +move_end} = state
  update.grab(core, J.Input.get_mouse_position(core), start, end, move_start, move_end)

def color(moving: Bool) -> U32:
  Bool.pick(U32, moving, J.Color.RED(), J.Color.BLUE())

def radius(near: Bool) -> F32:
  Bool.pick(F32, near, 14.0, 8.0)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+start, +end, +move_start, +move_end} = state
  +mouse = J.Input.get_mouse_position(core)
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.text(f1, "MOVE START-END POINTS WITH MOUSE", 15.0, 20.0, 20.0, J.Color.GRAY())
  f3 = J.Draw.line_bezier(f2, start, end, 4.0, J.Color.BLUE())
  f4 = J.Draw.circle_v_for(libm, f3, start, radius(near(mouse, start)), color(move_start))
  f5 = J.Draw.circle_v_for(libm, f4, end, radius(near(mouse, end)), color(move_end))
  (core, (State{start, end, move_start, move_end}, f5))

# The main loop's body; libm is the sinf/cosf profile of DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): start (30, 30), end (770, 420), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{M.Vector2{30.0, 30.0}, M.Vector2{770.0, 420.0}, False{}, False{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, J.ConfigFlags.FLAG_MSAA_4X_HINT(), "raylib [shapes] example - lines bezier",
    800, 450, J.Desktop.frames_arg(args), core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
