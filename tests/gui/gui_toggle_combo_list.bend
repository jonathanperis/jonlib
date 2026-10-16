# Jongui's GuiToggleSlider, GuiComboBox and GuiListView, ported from
# tools/reference/gui/gui_toggle_combo_list.c (a probe-only raygui program,
# not a raylib example) and replayed against it by tools/examples_probe.py
# (category gui).
import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../jongui.bend as G

# The enabled controls' values; the disabled ones' never change.
type Values is Data:
  Values{toggle: U32, toggles: U32, combo: U32, scroll: U32, active: U32}

type State is Data:
  State{gui: G.Gui, values: Values, off: Values}

# TextFormat's "%d" of an int given as its bits.
def int(+v: U32) -> String:
  Bool.pick(String, (v >= 2147483648 : U32), "-" ++ U32.show((0 - v : U32)), U32.show(v))

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def first(r: J.Frame & (U32 & Bool)) -> J.Frame:
  (frame, _) = r
  frame

def first.combo(r: J.Frame & U32) -> J.Frame:
  (frame, _) = r
  frame

def first.list(r: J.Frame & (G.Gui & (U32 & U32))) -> J.Frame:
  (frame, _) = r
  frame

# The disabled controls, then GuiEnable.
def draw.off(+core: J.Core, +gui: G.Gui, +values: Values, +off: Values, frame: J.Frame) -> J.Core & (State & J.Frame):
  Values{+t, _, +c, +s, +a} = off
  +disabled = G.Gui.disable(gui)
  f1 = first(G.Gui.toggle_slider(disabled, core, frame, J.Rectangle{10.0, 140.0, 120.0, 24.0}, "A;B", t))
  f2 = first.combo(G.Gui.combo_box(disabled, core, f1, J.Rectangle{10.0, 180.0, 120.0, 24.0}, "Only;Two", c))
  f3 = first.list(G.Gui.list_view(disabled, core, f2, J.Rectangle{220.0, 150.0, 170.0, 60.0}, None{}, s, a))
  (core, (State{G.Gui.enable(disabled), values, off}, f3))

def draw.listed.values(+core: J.Core, +gui: G.Gui, +toggle: U32, +toggles: U32, +combo: U32, +off: Values, frame: J.Frame, list: U32 & U32) -> J.Core & (State & J.Frame):
  (+scroll, +active) = list
  f1 = J.Draw.text(frame, int(toggles) ++ " " ++ int(toggle) ++ " " ++ int(combo) ++ " " ++ int(scroll) ++ " " ++ int(active), 10.0, 110.0, 10.0, J.Color.BLACK())
  draw.off(core, gui, Values{toggle, toggles, combo, scroll, active}, off, f1)

def draw.listed.rest(+core: J.Core, +toggle: U32, +toggles: U32, +combo: U32, +off: Values, frame: J.Frame, rest: G.Gui & (U32 & U32)) -> J.Core & (State & J.Frame):
  (gui, list) = rest
  draw.listed.values(core, gui, toggle, toggles, combo, off, frame, list)

def draw.listed(+core: J.Core, +toggle: U32, +toggles: U32, +combo: U32, +off: Values, r: J.Frame & (G.Gui & (U32 & U32))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.listed.rest(core, toggle, toggles, combo, off, frame, rest)

def draw.combo(+core: J.Core, +gui: G.Gui, +toggle: U32, +toggles: U32, +scroll: U32, +active: U32, +off: Values, r: J.Frame & U32) -> J.Core & (State & J.Frame):
  (frame, +combo) = r
  draw.listed(core, toggle, toggles, combo, off, G.Gui.list_view(gui, core, frame, J.Rectangle{220.0, 10.0, 170.0, 120.0}, Some{"Alpha;Beta;Gamma;Delta;Epsilon;Zeta;Eta;Theta;Iota"}, scroll, active))

def draw.toggled.moved(+core: J.Core, +gui: G.Gui, +toggles: U32, +combo: U32, +scroll: U32, +active: U32, +off: Values, frame: J.Frame, moved: U32 & Bool) -> J.Core & (State & J.Frame):
  (+toggle, +clicked) = moved
  draw.combo(core, gui, toggle, Bool.pick(U32, clicked, (toggles + 1 : U32), toggles), scroll, active, off,
    G.Gui.combo_box(gui, core, frame, J.Rectangle{10.0, 60.0, 200.0, 30.0}, "Red;Green;Blue;White", combo))

def draw.toggled(+core: J.Core, +gui: G.Gui, +toggles: U32, +combo: U32, +scroll: U32, +active: U32, +off: Values, r: J.Frame & (U32 & Bool)) -> J.Core & (State & J.Frame):
  (frame, moved) = r
  draw.toggled.moved(core, gui, toggles, combo, scroll, active, off, frame, moved)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +values, +off} = state
  Values{+toggle, +toggles, +combo, +scroll, +active} = values
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  draw.toggled(core, gui, toggles, combo, scroll, active, off, G.Gui.toggle_slider(gui, core, f1, J.Rectangle{10.0, 10.0, 200.0, 30.0}, "One;Two;Three", toggle))

def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(400, 300): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), Values{0, 0, 0, 0, 4294967295}, Values{1, 0, 3, 0, 0}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "jonlib gui - toggle slider, combo box, list view", 400, 300, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
