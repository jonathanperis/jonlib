# Jongui's GuiTabBar, GuiTabBarEx and GuiMessageBox (raygui 5.1-dev's
# signatures), ported from tools/reference/gui/gui_message_tabs.c (a
# probe-only raygui program, not a raylib example) and replayed against it by
# tools/examples_probe.py (category gui).
import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../jongui.bend as G

type State is Data:
  State{gui: G.Gui, active: U32, tab: U32, active_ex: U32, ex: U32, box_active: U32, box: U32}

# TextFormat's "%d" of an int given as its bits.
def int(+v: U32) -> String:
  Bool.pick(String, (v >= 2147483648 : U32), "-" ++ U32.show((0 - v : U32)), U32.show(v))

# A result kept when it is not 0.
def kept(+got: U32, +old: U32) -> U32:
  Bool.pick(U32, U32.is_eq(got, 0), old, got)

def first(r: J.Frame & G.Gui.Reply) -> J.Frame:
  (frame, _) = r
  frame

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def draw.boxed.reply(+core: J.Core, +gui: G.Gui, +active: U32, +tab: U32, +active_ex: U32, +ex: U32, +box: U32, frame: J.Frame, reply: G.Gui.Reply) -> J.Core & (State & J.Frame):
  G.GuiReply{+box_active, +got} = reply
  +now = kept(got, box)
  f1 = J.Draw.text(frame, int(active) ++ " " ++ int(tab) ++ " " ++ int(active_ex) ++ " " ++ int(ex) ++ " " ++ int(box_active) ++ " " ++ int(now), 330.0, 250.0, 10.0, J.Color.BLACK())
  +off = G.Gui.disable(gui)
  f2 = first(G.Gui.message_box(off, core, f1, J.Rectangle{380.0, 60.0, 110.0, 100.0}, None{}, "Off", "Ok", box_active))
  (core, (State{G.Gui.enable(off), active, tab, active_ex, ex, box_active, now}, f2))

def draw.boxed(+core: J.Core, +gui: G.Gui, +active: U32, +tab: U32, +active_ex: U32, +ex: U32, +box: U32, r: J.Frame & G.Gui.Reply) -> J.Core & (State & J.Frame):
  (frame, reply) = r
  draw.boxed.reply(core, gui, active, tab, active_ex, ex, box, frame, reply)

# After GuiTabBarEx: TABBAR's properties put back, then the message box.
def draw.tabbed.ex(+core: J.Core, +gui: G.Gui, +active: U32, +tab: U32, +ex: U32, +box_active: U32, +box: U32, frame: J.Frame, tabs: U32 & U32) -> J.Core & (State & J.Frame):
  (+active_ex, +got) = tabs
  draw.boxed(core, gui, active, tab, active_ex, kept(got, ex), box,
    G.Gui.message_box(gui, core, frame, J.Rectangle{60.0, 60.0, 300.0, 160.0}, Some{"#191#Message"}, "Hello there!\nSecond line", "Yes;No;Cancel", box_active))

def draw.ex(+core: J.Core, +gui: G.Gui, +active: U32, +tab: U32, +ex: U32, +box_active: U32, +box: U32, r: J.Frame & (U32 & U32)) -> J.Core & (State & J.Frame):
  (frame, tabs) = r
  draw.tabbed.ex(core, gui, active, tab, ex, box_active, box, frame, tabs)

# After GuiTabBar: GuiTabBarEx with TAB_ITEMS_WIDTH 100, close buttons and
# the line on top (set for it alone, as the C program puts them back).
def draw.tabbed.of(+core: J.Core, +gui: G.Gui, +tab: U32, +active_ex: U32, +ex: U32, +box_active: U32, +box: U32, frame: J.Frame, tabs: U32 & U32) -> J.Core & (State & J.Frame):
  (+active, +got) = tabs
  +styled = G.Gui.set_style(G.Gui.set_style(G.Gui.set_style(gui, 11, 16, 100), 11, 17, 1), 11, 18, 1)
  draw.ex(core, gui, active, kept(got, tab), ex, box_active, box,
    G.Gui.tab_bar_ex(styled, core, frame, J.Rectangle{0.0, 30.0, 500.0, 24.0}, ["First", "Second", "Third", "Fourth"], 0, active_ex, 4294967295))

def draw.tabbed(+core: J.Core, +gui: G.Gui, +tab: U32, +active_ex: U32, +ex: U32, +box_active: U32, +box: U32, r: J.Frame & (U32 & U32)) -> J.Core & (State & J.Frame):
  (frame, tabs) = r
  draw.tabbed.of(core, gui, tab, active_ex, ex, box_active, box, frame, tabs)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +active, +tab, +active_ex, +ex, +box_active, +box} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  draw.tabbed(core, gui, tab, active_ex, ex, box_active, box, G.Gui.tab_bar(gui, core, f1, J.Rectangle{0.0, 0.0, 500.0, 24.0}, Some{"One;Two;Three;Four;Five;Six"}, 0, active))

def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(500, 300): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), 5, 4294967294, 9, 4294967294, 4294967294, 4294967294}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "jonlib gui - tab bar, message box", 500, 300, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
