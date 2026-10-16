# Jongui's GuiWindowBox, GuiLabelButton, GuiDummyRec and GuiGrid, ported from
# tools/reference/gui/gui_window_grid.c (a probe-only raygui program, not a
# raylib example) and replayed against it by tools/examples_probe.py
# (category gui).
import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../jongui.bend as G

type State is Data:
  State{gui: G.Gui, closes: U32, clicks: U32, cell: M.Vector2}

# TextFormat's "%.0f" of a whole number.
def whole(+v: F32) -> String:
  Bool.pick(String, (v < 0.0 : F32), "-" ++ U32.show(F32.to_u32(F32.neg(v))), U32.show(F32.to_u32(v)))

def counters(+closes: U32, +clicks: U32, cell: M.Vector2) -> String:
  M.Vector2{+x, +y} = cell
  U32.show(closes) ++ " " ++ U32.show(clicks) ++ " " ++ whole(x) ++ " " ++ whole(y)

def first(r: J.Frame & M.Vector2) -> J.Frame:
  (frame, _) = r
  frame

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def draw.off(+core: J.Core, +gui: G.Gui, +closes: U32, +clicks: U32, r: J.Frame & M.Vector2) -> J.Core & (State & J.Frame):
  (frame, +cell) = r
  f1 = J.Draw.text(frame, counters(closes, clicks, cell), 230.0, 100.0, 10.0, J.Color.BLACK())
  +off = G.Gui.disable(gui)
  f2 = G.Gui.dummy_rec(off, f1, J.Rectangle{220.0, 75.0, 70.0, 20.0}, "Off")
  f3 = first(G.Gui.grid(off, core, f2, J.Rectangle{300.0, 75.0, 80.0, 20.0}, None{}, 10.0, 2))
  (core, (State{G.Gui.enable(off), closes, clicks, cell}, f3))

def draw.grid(+core: J.Core, +gui: G.Gui, +closes: U32, +clicks: U32, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +clicked) = r
  f1 = G.Gui.dummy_rec(gui, frame, J.Rectangle{220.0, 10.0, 160.0, 60.0}, "Dummy")
  draw.off(core, gui, closes, Bool.pick(U32, clicked, (clicks + 1 : U32), clicks), G.Gui.grid(gui, core, f1, J.Rectangle{10.0, 140.0, 380.0, 150.0}, None{}, 40.0, 4))

def draw.label(+core: J.Core, +gui: G.Gui, +closes: U32, +clicks: U32, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +closed) = r
  draw.grid(core, gui, Bool.pick(U32, closed, (closes + 1 : U32), closes), clicks, G.Gui.label_button(gui, core, frame, J.Rectangle{20.0, 50.0, 40.0, 20.0}, "Click me please"))

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +closes, +clicks, _} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  draw.label(core, gui, closes, clicks, G.Gui.window_box(gui, core, f1, J.Rectangle{10.0, 10.0, 200.0, 120.0}, Some{"#198#Window"}))

def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(400, 300): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), 0, 0, M.Vector2{0.0, 0.0}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "jonlib gui - window box, label button, dummy rec, grid", 400, 300, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
