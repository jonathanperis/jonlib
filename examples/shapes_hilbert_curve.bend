# raylib [shapes] example - hilbert curve, ported to Jonlib.
# Adapted from raylib 6.2 examples/shapes/shapes_hilbert_curve.c (zlib/libpng,
# Copyright (c) 2025 Hamza RAHAL (@hmz-rhl)); see LICENSES/raylib.txt.
#
# The Hilbert curve of an order, drawn a stroke a frame after every change
# (or at once), each stroke colored by its place along the path. raygui
# controls (Jongui): a check box for the animation, a spinner for the order
# and sliders for the thickness and the size. See docs/GUI.md and
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# prev_size is (int)size at the last generation; counter the strokes drawn so far.
type State is Data:
  State{gui: G.Gui, order: U32, size: F32, strokes: U32, path: +List<M.Vector2>, prev_order: U32, prev_size: U32, counter: U32, thick: F32, animate: Bool}

# 1 << order.
def side(n: Nat) -> U32:
  match n:
    case 0n: 1
    case 1n+p: (2 * side(p) : U32)

# One level of ComputeHilbertStep's switch: the quadrant's base pattern is
# swapped (0), moved up (1), moved up and right (2) or mirrored (3).
def turn.x(kind: U32, +x: F32, +y: F32, +len: F32) -> F32:
  match kind:
    case 0: y
    case 1: x
    case 2: (x + len : F32)
    case _: ((2.0 * len - 1.0) - y : F32)

def turn.y(kind: U32, +x: F32, +y: F32, +len: F32) -> F32:
  match kind:
    case 0: x
    case 3: ((len - 1.0) - x : F32)
    case _: (y + len : F32)

# for (j = 1; j < order; j++): index >>= 2, len = 1 << j.
def step.go(n: Nat, +index: U32, +len: F32, +x: F32, +y: F32) -> M.Vector2:
  match n:
    case 0n: M.Vector2{x, y}
    case 1n+p:
      +next = (index >> 2n : U32)
      +kind = (next .&. 3 : U32)
      step.go(p, next, (len * 2.0 : F32), turn.x(kind, x, y, len), turn.y(kind, x, y, len))

# ComputeHilbertStep(order, index), from hilbertPoints (0,0), (0,1), (1,1), (1,0).
def step(+order: U32, +index: U32) -> M.Vector2:
  +kind = (index .&. 3 : U32)
  step.go(U32.to_nat((order - 1 : U32)), index, 2.0, Bool.pick(F32, (kind >= 2 : U32), 1.0, 0.0), Bool.pick(F32, U32.is_eq(kind, 1) || U32.is_eq(kind, 2), 1.0, 0.0))

# x*len + len/2.0f, y*len + len/2.0f.
def scaled(v: M.Vector2, +len: F32) -> M.Vector2:
  M.Vector2{+x, +y} = v
  M.Vector2{(x * len + len / 2.0 : F32), (y * len + len / 2.0 : F32)}

# The points from index i down to 0, in front of acc.
def path.go(n: Nat, +i: U32, +order: U32, +len: F32, acc: +List<M.Vector2>) -> +List<M.Vector2>:
  match n:
    case 0n: acc
    case 1n+p: path.go(p, (i - 1 : U32), order, len, Con{scaled(step(order, i), len), acc})

# LoadHilbertPath(order, size): N*N points, len = size/N apart.
def path(+order: U32, +size: F32) -> +List<M.Vector2>:
  +n = side(U32.to_nat(order))
  +count = (n * n : U32)
  path.go(U32.to_nat(count), (count - 1 : U32), order, (size / U32.to_f32(n) : F32), Nil{})

def strokes(+order: U32) -> U32:
  (side(U32.to_nat(order)) * side(U32.to_nat(order)) : U32)

# A change of order or of (int)size regenerates the path; the drawing starts
# over when animating.
def update.at(changed: Bool, +state: State) -> State:
  match changed:
    case False{}: state
    case True{}:
      State{+gui, +order, +size, _, _, _, _, _, +thick, +animate} = state
      State{gui, order, size, strokes(order), path(order, size), order, F32.to_u32(F32.trunc(size)), Bool.pick(U32, animate, 0, strokes(order)), thick, animate}

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{_, +order, +size, _, _, +prev_order, +prev_size, _, _, _} = state
  (core, update.at(U32.is_ne(prev_order, order) || U32.is_ne(prev_size, F32.to_u32(F32.trunc(size))), state))

# DrawLineEx(path[i], path[i - 1], thick, ColorFromHSV(((float)i/strokeCount)*360.0f, 1.0f, 1.0f)) for n strokes from i.
def lines(n: Nat, points: +List<M.Vector2>, +i: U32, +count: F32, +thick: F32, frame: J.Frame) -> J.Frame:
  match n points:
    case 1n+p Con{+a, Con{+b, +rest}}:
      lines(p, Con{b, rest}, (i + 1 : U32), count, thick, J.Draw.line_ex(frame, b, a, thick, J.Color.from_hsv(((U32.to_f32(i) / count) * 360.0 : F32), 1.0, 1.0)))
    case _ _: frame

def first(pair: F32 & Bool) -> F32:
  (value, _) = pair
  value

def with_size(state: State, gui: G.Gui, size: F32) -> State:
  State{_, order, _, strokes, path, prev_order, prev_size, counter, thick, animate} = state
  State{gui, order, size, strokes, path, prev_order, prev_size, counter, thick, animate}

def with_thick(state: State, gui: G.Gui, thick: F32) -> State:
  State{_, order, size, strokes, path, prev_order, prev_size, counter, _, animate} = state
  State{gui, order, size, strokes, path, prev_order, prev_size, counter, thick, animate}

def with_order(state: State, order: U32) -> State:
  State{gui, _, size, strokes, path, prev_order, prev_size, counter, thick, animate} = state
  State{gui, order, size, strokes, path, prev_order, prev_size, counter, thick, animate}

def with_animate(state: State, animate: Bool) -> State:
  State{gui, order, size, strokes, path, prev_order, prev_size, counter, thick, _} = state
  State{gui, order, size, strokes, path, prev_order, prev_size, counter, thick, animate}

def gui_of(state: State) -> G.Gui:
  State{gui, _, _, _, _, _, _, _, _, _} = state
  gui

def size_of(state: State) -> F32:
  State{_, _, size, _, _, _, _, _, _, _} = state
  size

def thick_of(state: State) -> F32:
  State{_, _, _, _, _, _, _, _, thick, _} = state
  thick

def order_of(state: State) -> U32:
  State{_, order, _, _, _, _, _, _, _, _} = state
  order

def ui.size.rest(+core: J.Core, +state: State, frame: J.Frame, rest: G.Gui & (F32 & Bool)) -> J.Core & (State & J.Frame):
  (gui, pair) = rest
  (core, (with_size(state, gui, first(pair)), frame))

def ui.size(+core: J.Core, +state: State, r: J.Frame & (G.Gui & (F32 & Bool))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  ui.size.rest(core, state, frame, rest)

# GuiSlider(TOTAL SIZE), from 10 to GetScreenHeight()*1.5f.
def ui.thick.to(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  ui.size(core, state, G.Gui.slider(gui_of(state), core, frame, J.Rectangle{524.0, 190.0, 240.0, 24.0}, Some{"TOTAL SIZE: "}, None{}, size_of(state), 10.0, 675.0))

def ui.thick.rest(+core: J.Core, +state: State, frame: J.Frame, rest: G.Gui & (F32 & Bool)) -> J.Core & (State & J.Frame):
  (gui, pair) = rest
  ui.thick.to(core, with_thick(state, gui, first(pair)), frame)

def ui.thick(+core: J.Core, +state: State, r: J.Frame & (G.Gui & (F32 & Bool))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  ui.thick.rest(core, state, frame, rest)

# GuiSlider(THICKNESS), from 1 to 10.
def ui.order.to(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  ui.thick(core, state, G.Gui.slider(gui_of(state), core, frame, J.Rectangle{524.0, 150.0, 240.0, 24.0}, Some{"THICKNESS:  "}, None{}, thick_of(state), 1.0, 10.0))

def ui.order.rest(+core: J.Core, +state: State, frame: J.Frame, pair: U32 & Bool) -> J.Core & (State & J.Frame):
  (order, _) = pair
  ui.order.to(core, with_order(state, order), frame)

def ui.order(+core: J.Core, +state: State, r: J.Frame & (U32 & Bool)) -> J.Core & (State & J.Frame):
  (frame, pair) = r
  ui.order.rest(core, state, frame, pair)

# GuiSpinner(HILBERT CURVE ORDER), from 2 to 8.
def ui.animate.to(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  ui.order(core, state, G.Gui.spinner(gui_of(state), core, frame, J.Rectangle{585.0, 100.0, 180.0, 30.0}, Some{"HILBERT CURVE ORDER:  "}, order_of(state), 2, 8, False{}))

def ui.animate.rest(+core: J.Core, +state: State, frame: J.Frame, pair: Bool & Bool) -> J.Core & (State & J.Frame):
  (animate, _) = pair
  ui.animate.to(core, with_animate(state, animate), frame)

def ui.animate(+core: J.Core, +state: State, r: J.Frame & (Bool & Bool)) -> J.Core & (State & J.Frame):
  (frame, pair) = r
  ui.animate.rest(core, state, frame, pair)

# The path (one more stroke a frame until it is whole), then the controls.
def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +order, +size, +strokes, +path, +prev_order, +prev_size, +counter, +thick, +animate} = state
  +moving = (counter < strokes : U32)
  f1 = lines(U32.to_nat(Bool.pick(U32, moving, counter, (strokes - 1 : U32))), path, 1, U32.to_f32(strokes), thick, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  ui.animate(core, State{gui, order, size, strokes, path, prev_order, prev_size, Bool.pick(U32, moving, (counter + 1 : U32), counter), thick, animate},
    G.Gui.check_box(gui, core, f1, J.Rectangle{450.0, 50.0, 20.0, 20.0}, "ANIMATE GENERATION ON CHANGE", animate))

# The main loop's body; nothing in it follows the libm profile.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): order 2 at the screen's height, a stroke 2
# thick, animating, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), 2, 450.0, 16, path(2, 450.0), 2, 450, 0, 2.0, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - hilbert curve", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
