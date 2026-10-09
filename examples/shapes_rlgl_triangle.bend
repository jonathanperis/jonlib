# raylib [shapes] example - rlgl triangle, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_rlgl_triangle.c (zlib/libpng,
# Copyright (c) 2025 Robin (@RobinsAviary)); see LICENSES/raylib.txt.
#
# A triangle drawn with rlBegin/rlVertex; drag its vertices, SPACE toggles
# lines, LEFT/RIGHT enable/disable backface culling, R resets. raylib toggles
# the culling in its update; here the update records the last toggle and the
# draw applies it first (persistent rlgl state, the same frames). See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# index 3 is raylib's triangleIndex -1 (no vertex held); cull is the
# culling state the update asks for (None: unchanged).
type State is Data:
  State{p0: M.Vector2, p1: M.Vector2, p2: M.Vector2, index: U32, lines: Bool, cull: +Maybe<Bool>}

def start0() -> M.Vector2:
  M.Vector2{400.0, 150.0}

def start1() -> M.Vector2:
  M.Vector2{300.0, 300.0}

def start2() -> M.Vector2:
  M.Vector2{500.0, 300.0}

def near(+mouse: M.Vector2, +p: M.Vector2) -> Bool:
  J.Collision.point_circle(mouse, p, 8.0)

def shifted(+held: Bool, +p: M.Vector2, +delta: M.Vector2) -> M.Vector2:
  M.Vector2{+x, +y} = p
  M.Vector2{+dx, +dy} = delta
  Bool.pick(M.Vector2, held, M.Vector2{(x + dx : F32), (y + dy : F32)}, p)

# The first vertex under the mouse while the left button is down is held
# (the loop breaks there); it moves by the mouse delta until the release.
def update.moved(+core: J.Core, +p0: M.Vector2, +p1: M.Vector2, +p2: M.Vector2, +lines: Bool, +index: U32) -> State:
  +delta = J.Input.get_mouse_delta(core)
  +q0 = shifted(U32.is_eq(index, 0), p0, delta)
  +q1 = shifted(U32.is_eq(index, 1), p1, delta)
  +q2 = shifted(U32.is_eq(index, 2), p2, delta)
  +released = Bool.pick(U32, J.Input.is_mouse_button_released(core, J.MouseButton.MOUSE_BUTTON_LEFT()), 3, index)
  +left = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT())
  +right = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT())
  +reset = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_R())
  +cull = Bool.pick(+Maybe<Bool>, reset, Some{True{}}, Bool.pick(+Maybe<Bool>, right, Some{False{}}, Bool.pick(+Maybe<Bool>, left, Some{True{}}, None{})))
  Bool.pick(State, reset, State{start0(), start1(), start2(), released, lines, cull}, State{q0, q1, q2, released, lines, cull})

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+p0, +p1, +p2, +index, +lines, _} = state
  +l = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), Bool.not(lines), lines)
  +mouse = J.Input.get_mouse_position(core)
  +down = J.Input.is_mouse_button_down(core, J.MouseButton.MOUSE_BUTTON_LEFT())
  +i = Bool.pick(U32, near(mouse, p0) && down, 0, Bool.pick(U32, near(mouse, p1) && down, 1, Bool.pick(U32, near(mouse, p2) && down, 2, index)))
  (core, update.moved(core, p0, p1, p2, l, i))

def culled(cull: +Maybe<Bool>, frame: J.Frame) -> J.Frame:
  match cull:
    case None{}: frame
    case Some{True{}}: J.Rlgl.enable_backface_culling(frame)
    case Some{False{}}: J.Rlgl.disable_backface_culling(frame)

def vertex(frame: J.Frame, +r: U32, +g: U32, +b: U32, +p: M.Vector2) -> J.Frame:
  M.Vector2{+x, +y} = p
  J.Rlgl.vertex2f(J.Rlgl.color4ub(frame, r, g, b, 255), x, y)

# rlBegin(RL_LINES) with the three colored edges, or rlBegin(RL_TRIANGLES).
def triangle(lines: Bool, +p0: M.Vector2, +p1: M.Vector2, +p2: M.Vector2, frame: J.Frame) -> J.Frame:
  match lines:
    case True{}:
      f1 = vertex(vertex(J.Rlgl.begin(frame, 1), 255, 0, 0, p0), 0, 255, 0, p1)
      f2 = vertex(vertex(f1, 0, 255, 0, p1), 0, 0, 255, p2)
      J.Rlgl.end(vertex(vertex(f2, 0, 0, 255, p2), 255, 0, 0, p0))
    case False{}: J.Rlgl.end(vertex(vertex(vertex(J.Rlgl.begin(frame, 4), 255, 0, 0, p0), 0, 255, 0, p1), 0, 0, 255, p2))

def handle.hover(hover: Bool, +libm: M.Libm, +p: M.Vector2, frame: J.Frame) -> J.Frame:
  match hover:
    case True{}: J.Draw.circle_v_for(libm, frame, p, 8.0, J.Color.with_alpha(J.Color.DARKGRAY(), 0.5))
    case False{}: frame

def handle.held(held: Bool, +libm: M.Libm, +p: M.Vector2, frame: J.Frame) -> J.Frame:
  match held:
    case True{}: J.Draw.circle_v_for(libm, frame, p, 8.0, J.Color.DARKGRAY())
    case False{}: frame

def handle(+libm: M.Libm, +mouse: M.Vector2, +index: U32, +i: U32, +p: M.Vector2, frame: J.Frame) -> J.Frame:
  f1 = handle.held(U32.is_eq(index, i), libm, p, handle.hover(near(mouse, p), libm, p, frame))
  J.Draw.circle_lines_v_for(libm, f1, p, 8.0, J.Color.BLACK())

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+p0, +p1, +p2, +index, +lines, cull} = state
  +mouse = J.Input.get_mouse_position(core)
  f1 = triangle(lines, p0, p1, p2, J.Frame.clear_background(culled(cull, frame), J.Color.RAYWHITE()))
  f2 = handle(libm, mouse, index, 2, p2, handle(libm, mouse, index, 1, p1, handle(libm, mouse, index, 0, p0, f1)))
  f3 = J.Draw.text(f2, "SPACE: Toggle lines mode", 10.0, 10.0, 20.0, J.Color.DARKGRAY())
  f4 = J.Draw.text(f3, "LEFT-RIGHT: Toggle backface culling", 10.0, 40.0, 20.0, J.Color.DARKGRAY())
  f5 = J.Draw.text(f4, "MOUSE: Click and drag vertex points", 10.0, 70.0, 20.0, J.Color.DARKGRAY())
  f6 = J.Draw.text(f5, "R: Reset triangle to start positions", 10.0, 100.0, 20.0, J.Color.DARKGRAY())
  (core, (State{p0, p1, p2, index, lines, None{}}, f6))

# The main loop's body; libm is the sinf/cosf profile of DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After SetConfigFlags(FLAG_MSAA_4X_HINT) and InitWindow(800, 450): the
# starting triangle, no held vertex, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{start0(), start1(), start2(), 3, False{}, None{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, J.ConfigFlags.FLAG_MSAA_4X_HINT(), "raylib [shapes] example - rlgl triangle",
    800, 450, J.Desktop.frames_arg(args), core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
