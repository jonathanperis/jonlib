# raylib [shapes] example - rectangle scaling, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_rectangle_scaling.c (zlib/libpng,
# Copyright (c) 2018-2025 Vlad Adrian (@demizdor) and Ramon Santamaria
# (@raysan5)); see LICENSES/raylib.txt.
#
# Drag the bottom-right corner mark to scale the rectangle. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{rec: J.Rectangle, ready: Bool, scaling: Bool}

# MOUSE_SCALE_MARK_SIZE
def mark() -> F32:
  12.0

def corner(+rec: J.Rectangle) -> J.Rectangle:
  J.Rectangle{+x, +y, +w, +h} = rec
  J.Rectangle{(x + w - mark() : F32), (y + h - mark() : F32), mark(), mark()}

# While scaling: the size follows the mouse, at least the mark and at most
# the screen's remaining width and height (GetScreenWidth() - rec.x in F32).
def scaled(+core: J.Core, +mouse: M.Vector2, +rec: J.Rectangle) -> J.Rectangle:
  M.Vector2{+mx, +my} = mouse
  J.Rectangle{+x, +y, _, _} = rec
  +w1 = (mx - x : F32)
  +h1 = (my - y : F32)
  +w2 = Bool.pick(F32, (w1 < mark() : F32), mark(), w1)
  +h2 = Bool.pick(F32, (h1 < mark() : F32), mark(), h1)
  +sw = (U32.to_f32(J.Core.get_screen_width(core)) - x : F32)
  +sh = (U32.to_f32(J.Core.get_screen_height(core)) - y : F32)
  J.Rectangle{x, y, Bool.pick(F32, (w2 > sw : F32), sw, w2), Bool.pick(F32, (h2 > sh : F32), sh, h2)}

def update.mode(scaling: Bool, +core: J.Core, +mouse: M.Vector2, +rec: J.Rectangle, +ready: Bool) -> State:
  match scaling:
    case True{}: State{scaled(core, mouse, rec), True{}, Bool.not(J.Input.is_mouse_button_released(core, J.MouseButton.MOUSE_BUTTON_LEFT()))}
    case False{}: State{rec, ready, False{}}

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+rec, _, +scaling} = state
  +mouse = J.Input.get_mouse_position(core)
  +ready = J.Collision.point_rec(mouse, corner(rec))
  +start = ready && J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_LEFT())
  (core, update.mode(scaling || start, core, mouse, rec, ready))

def draw.mark(ready: Bool, +rec: J.Rectangle, frame: J.Frame) -> J.Frame:
  match ready:
    case False{}: frame
    case True{}:
      J.Rectangle{+x, +y, +w, +h} = rec
      f1 = J.Draw.rectangle_lines_ex(frame, rec, 1.0, J.Color.RED())
      J.Draw.triangle(f1, M.Vector2{(x + w - mark() : F32), (y + h : F32)}, M.Vector2{(x + w : F32), (y + h : F32)},
        M.Vector2{(x + w : F32), (y + h - mark() : F32)}, J.Color.RED())

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+rec, +ready, _} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.text(f1, "Scale rectangle dragging from bottom-right corner!", 10.0, 10.0, 20.0, J.Color.GRAY())
  f3 = J.Draw.rectangle_rec(f2, rec, J.Color.with_alpha(J.Color.GREEN(), 0.5))
  (core, (state, draw.mark(ready, rec, f3)))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): the rectangle (100, 100, 200, 80), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Rectangle{100.0, 100.0, 200.0, 80.0}, False{}, False{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - rectangle scaling", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
