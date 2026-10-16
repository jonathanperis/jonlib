# Jongui's GuiTabBar and GuiMessageBox, ported from
# tools/reference/gui/gui_message_tabs.c (a probe-only raygui program, not a
# raylib example) and replayed against it by tools/examples_probe.py
# (category gui).
import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../jongui.bend as G

type State is Data:
  State{gui: G.Gui, active: U32, tab: U32, box: U32}

# TextFormat's "%d" of an int given as its bits.
def int(+v: U32) -> String:
  Bool.pick(String, (v >= 2147483648 : U32), "-" ++ U32.show((0 - v : U32)), U32.show(v))

# A result kept when it is 0 or more.
def kept(+got: U32, +old: U32) -> U32:
  Bool.pick(U32, (got >= 2147483648 : U32), old, got)

def first(r: J.Frame & U32) -> J.Frame:
  (frame, _) = r
  frame

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def draw.boxed(+core: J.Core, +gui: G.Gui, +active: U32, +tab: U32, +box: U32, r: J.Frame & U32) -> J.Core & (State & J.Frame):
  (frame, +got) = r
  +now = kept(got, box)
  f1 = J.Draw.text(frame, int(active) ++ " " ++ int(tab) ++ " " ++ int(now), 380.0, 250.0, 10.0, J.Color.BLACK())
  +off = G.Gui.disable(gui)
  f2 = first(G.Gui.message_box(off, core, f1, J.Rectangle{380.0, 60.0, 110.0, 100.0}, None{}, "Off", "Ok"))
  (core, (State{G.Gui.enable(off), active, tab, now}, f2))

def draw.tabbed.of(+core: J.Core, +gui: G.Gui, +tab: U32, +box: U32, frame: J.Frame, tabs: U32 & U32) -> J.Core & (State & J.Frame):
  (+active, +got) = tabs
  draw.boxed(core, gui, active, kept(got, tab), box,
    G.Gui.message_box(gui, core, frame, J.Rectangle{60.0, 60.0, 300.0, 160.0}, Some{"#191#Message"}, "Hello there!\nSecond line", "Yes;No;Cancel"))

def draw.tabbed(+core: J.Core, +gui: G.Gui, +tab: U32, +box: U32, r: J.Frame & (U32 & U32)) -> J.Core & (State & J.Frame):
  (frame, tabs) = r
  draw.tabbed.of(core, gui, tab, box, frame, tabs)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +active, +tab, +box} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  draw.tabbed(core, gui, tab, box, G.Gui.tab_bar(gui, core, f1, J.Rectangle{0.0, 0.0, 500.0, 24.0}, ["First", "Second", "Third", "Fourth"], active))

def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(500, 300): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), 1, 4294967294, 4294967294}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "jonlib gui - tab bar, message box", 500, 300, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
