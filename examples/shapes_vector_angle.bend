# raylib [shapes] example - vector angle, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_vector_angle.c (zlib/libpng,
# Copyright (c) 2023-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The angle between two vectors from the screen center (mode 0: V1 moves with
# the right mouse button, V2 follows the mouse) or of the line to the mouse
# against the horizontal (mode 1), shown as a green sector. SPACE switches
# the mode; the sector's start angle is the one of the mode and V1 the frame
# began with, as in the example. Vector2Angle's and Vector2LineAngle's
# atan2f (docs/ANGLES.md) and DrawCircleSector's sinf/cosf (docs/SINCOSF.md)
# follow the libm profile; an angle outside it refuses the frame. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# start: the sector's start angle; angle: the measured one, both in degrees.
type State is Data:
  State{valid: Bool, v1: M.Vector2, v2: M.Vector2, start: F32, angle: F32, mode: U32}

def v0() -> M.Vector2:
  M.Vector2{(800.0 / 2.0 : F32), (450.0 / 2.0 : F32)}

# -Vector2LineAngle(v0, v1)*RAD2DEG.
def start.scaled(angle: Maybe<F32>) -> Maybe<F32>:
  match angle:
    case None{}: None{}
    case Some{+a}: Some{(F32.neg(a) * M.Math.RAD2DEG() : F32)}

# The start angle of the mode the frame began with.
def start(+libm: M.Libm, mode: U32, +v1: M.Vector2) -> Maybe<F32>:
  match mode:
    case 0: start.scaled(M.Vector2.line_angle_for(libm, v0(), v1))
    case _: Some{0.0}

def degrees(angle: Maybe<F32>) -> Maybe<F32>:
  match angle:
    case None{}: None{}
    case Some{+a}: Some{(a * M.Math.RAD2DEG() : F32)}

# Mode 0: Vector2Angle of the two normalized vectors from v0; mode 1:
# Vector2LineAngle(v0, v2).
def angle(+libm: M.Libm, mode: U32, +v1: M.Vector2, +v2: M.Vector2) -> Maybe<F32>:
  match mode:
    case 0: degrees(M.Vector2.angle_for(libm, M.Vector2.normalize(M.Vector2.subtract(v1, v0())), M.Vector2.normalize(M.Vector2.subtract(v2, v0()))))
    case _: degrees(M.Vector2.line_angle_for(libm, v0(), v2))

def measured(+mode: U32, +v1: M.Vector2, +v2: M.Vector2, start: Maybe<F32>, angle: Maybe<F32>) -> State:
  match start angle:
    case Some{+s} Some{+a}: State{True{}, v1, v2, s, a, mode}
    case _ _: State{False{}, v1, v2, 0.0, 0.0, mode}

# v2 = GetMousePosition(); SPACE flips the mode; in mode 0 the right button moves v1.
def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{_, +v1, _, _, _, +mode} = state
  +mouse = J.Input.get_mouse_position(core)
  +next = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), (1 - mode : U32), mode)
  +moved = Bool.pick(M.Vector2, U32.is_eq(next, 0) && J.Input.is_mouse_button_down(core, 1), mouse, v1)
  (core, measured(next, moved, mouse, start(libm, mode, v1), angle(libm, next, moved, mouse)))

def v1.label.at(shown: Bool, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: J.Draw.text(frame, "v1", x, y, 10.0, J.Color.DARKGRAY())

# The v1 label, moved up 10 when the line from v0 would overlap it (no label
# when v1 is on v0's row).
def v1.label(+v1: M.Vector2, frame: J.Frame) -> J.Frame:
  M.Vector2{+x, +y} = v1
  +dy = ((450.0 / 2.0) - y : F32)
  v1.label.at((dy > 0.0 : F32) || (dy < 0.0 : F32), F32.trunc(x), (F32.trunc(y) - Bool.pick(F32, (dy > 0.0 : F32), 10.0, 0.0) : F32), frame)

def scene(+libm: M.Libm, mode: U32, +v1: M.Vector2, +v2: M.Vector2, +start: F32, +angle: F32, frame: J.Frame) -> J.Frame:
  match mode:
    case 0:
      f1 = J.Draw.text(frame, "MODE 0: Angle between V1 and V2", 10.0, 10.0, 20.0, J.Color.BLACK())
      f2 = J.Draw.text(f1, "Right Click to Move V2", 10.0, 30.0, 20.0, J.Color.DARKGRAY())
      f3 = J.Draw.line_ex(J.Draw.line_ex(f2, v0(), v1, 2.0, J.Color.BLACK()), v0(), v2, 2.0, J.Color.RED())
      f4 = J.Draw.circle_sector_for(libm, f3, v0(), 40.0, start, (start + angle : F32), 32.0, J.Color.with_alpha(J.Color.GREEN(), 0.6))
      v1.label(v1, J.Draw.text(f4, "v0", (800.0 / 2.0 : F32), (450.0 / 2.0 : F32), 10.0, J.Color.DARKGRAY()))
    case _:
      f1 = J.Draw.text(frame, "MODE 1: Angle formed by line V1 to V2", 10.0, 10.0, 20.0, J.Color.BLACK())
      f2 = J.Draw.line(f1, 0.0, 225.0, 800.0, 225.0, J.Color.LIGHTGRAY())
      f3 = J.Draw.line_ex(f2, v0(), v2, 2.0, J.Color.RED())
      f4 = J.Draw.circle_sector_for(libm, f3, v0(), 40.0, start, (start - angle : F32), 32.0, J.Color.with_alpha(J.Color.GREEN(), 0.6))
      f5 = J.Draw.text(f4, "v0", (800.0 / 2.0 : F32), (450.0 / 2.0 : F32), 10.0, J.Color.DARKGRAY())
      J.Draw.text(f5, "v1", (800.0 / 2.0 + 40.0 : F32), (450.0 / 2.0 : F32), 10.0, J.Color.DARKGRAY())

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 70.0, 20.0, J.Color.LIME())

def draw.valid(valid: Bool, +libm: M.Libm, +state: State, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}:
      State{_, +v1, +v2, +start, +angle, +mode} = state
      M.Vector2{+x, +y} = v2
      f1 = scene(libm, mode, v1, v2, start, angle, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
      f2 = J.Draw.text(f1, "v2", (F32.trunc(x) - 10.0 : F32), (F32.trunc(y) - 10.0 : F32), 10.0, J.Color.DARKGRAY())
      f3 = J.Draw.text(f2, "Press SPACE to change MODE", 460.0, 10.0, 20.0, J.Color.DARKGRAY())
      label(J.Text.format("ANGLE: %2.2f", [J.TextFloat{angle}]), f3)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, _, _} = state
  (core, (state, draw.valid(valid, libm, state, frame)))

# The main loop's body; libm is the profile of the angles' atan2f and DrawCircleSector's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): v1 = v0 + (100, 80), mode 0, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{True{}, M.Vector2.add(v0(), M.Vector2{100.0, 80.0}), M.Vector2.zero(), 0.0, 0.0, 0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - vector angle", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
