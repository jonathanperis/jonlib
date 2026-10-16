# Jongui's GuiLoadStyle, ported from tools/reference/gui/gui_style.c (a
# probe-only raygui program, not a raylib example) and replayed against it
# by tools/examples_probe.py (category gui) with a text or binary style.rgs
# in each script's directory. The style is loaded in the setup; the slider
# bar's drag and the text box globals are passed from frame to frame.
import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../jongui.bend as G

type State is Data:
  State{gui: G.Gui, clicks: U32, checked: Bool, value: F32, text: String, editing: G.Gui.Editing}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def counters(+gui: G.Gui, +clicks: U32, +checked: Bool) -> String:
  U32.show(clicks) ++ " " ++ Bool.pick(String, checked, "1", "0") ++ " " ++ U32.show(G.Gui.get_style(gui, 0, 16)) ++ " " ++ U32.show(G.Gui.get_style(gui, 0, 17))
    ++ " " ++ U32.show(G.Gui.get_style(gui, 2, 12)) ++ " " ++ U32.show(G.Gui.font_base_size(gui))

def draw.done(+core: J.Core, +gui: G.Gui, +clicks: U32, +checked: Bool, +value: F32, +text: String, frame: J.Frame, rest: G.Gui.Editing & Bool) -> J.Core & (State & J.Frame):
  (+editing, _) = rest
  f1 = G.Gui.line(gui, frame, J.Rectangle{10.0, 215.0, 300.0, 10.0}, Some{"Line"})
  f2 = G.Gui.status_bar(gui, f1, J.Rectangle{0.0, 270.0, 420.0, 30.0}, Some{"Status"})
  f3 = J.Draw.text(f2, counters(gui, clicks, checked), 230.0, 240.0, 10.0, J.Color.BLACK())
  (core, (State{gui, clicks, checked, value, text, editing}, f3))

def draw.texted(+core: J.Core, +gui: G.Gui, +clicks: U32, +checked: Bool, +value: F32, frame: J.Frame, rest: String & (G.Gui.Editing & Bool)) -> J.Core & (State & J.Frame):
  (+text, more) = rest
  draw.done(core, gui, clicks, checked, value, text, frame, more)

def draw.cored(+gui: G.Gui, +clicks: U32, +checked: Bool, +value: F32, frame: J.Frame, rest: J.Core & (String & (G.Gui.Editing & Bool))) -> J.Core & (State & J.Frame):
  (+core, more) = rest
  draw.texted(core, gui, clicks, checked, value, frame, more)

def draw.boxed(+gui: G.Gui, +clicks: U32, +checked: Bool, +value: F32, r: J.Frame & (J.Core & (String & (G.Gui.Editing & Bool)))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.cored(gui, clicks, checked, value, frame, rest)

def draw.slid.value(+core: J.Core, +gui: G.Gui, +clicks: U32, +checked: Bool, +text: String, +editing: G.Gui.Editing, frame: J.Frame, more: F32 & Bool) -> J.Core & (State & J.Frame):
  (+value, _) = more
  draw.boxed(gui, clicks, checked, value, G.Gui.text_box(gui, core, frame, J.Rectangle{10.0, 175.0, 200.0, 30.0}, text, 32, False{}, editing))

def draw.slid.rest(+core: J.Core, +clicks: U32, +checked: Bool, +text: String, +editing: G.Gui.Editing, frame: J.Frame, rest: G.Gui & (F32 & Bool)) -> J.Core & (State & J.Frame):
  (+gui, more) = rest
  draw.slid.value(core, gui, clicks, checked, text, editing, frame, more)

def draw.slid(+core: J.Core, +clicks: U32, +checked: Bool, +text: String, +editing: G.Gui.Editing, r: J.Frame & (G.Gui & (F32 & Bool))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.slid.rest(core, clicks, checked, text, editing, frame, rest)

def draw.checked(+core: J.Core, +gui: G.Gui, +clicks: U32, +value: F32, +text: String, +editing: G.Gui.Editing, frame: J.Frame, rest: Bool & Bool) -> J.Core & (State & J.Frame):
  (+checked, _) = rest
  draw.slid(core, clicks, checked, text, editing, G.Gui.slider_bar(gui, core, frame, J.Rectangle{60.0, 140.0, 200.0, 20.0}, Some{"Min"}, Some{"Max"}, value, 0.0, 100.0))

def draw.boxchecked(+core: J.Core, +gui: G.Gui, +clicks: U32, +value: F32, +text: String, +editing: G.Gui.Editing, r: J.Frame & (Bool & Bool)) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.checked(core, gui, clicks, value, text, editing, frame, rest)

def draw.clicked(+core: J.Core, +gui: G.Gui, +clicks: U32, +checked: Bool, +value: F32, +text: String, +editing: G.Gui.Editing, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +clicked) = r
  draw.boxchecked(core, gui, Bool.pick(U32, clicked, (clicks + 1 : U32), clicks), value, text, editing,
    G.Gui.check_box(gui, core, frame, J.Rectangle{10.0, 100.0, 24.0, 24.0}, "Check", checked))

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +clicks, +checked, +value, +text, +editing} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = G.Gui.label(gui, f1, J.Rectangle{10.0, 10.0, 300.0, 30.0}, "Styled label")
  draw.clicked(core, gui, clicks, checked, value, text, editing, G.Gui.button(gui, core, f2, J.Rectangle{10.0, 50.0, 140.0, 30.0}, "Button"))

def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.loaded(+core: J.Core, r: J.Frame & G.Gui) -> J.Core & (J.Frame & State):
  (frame, +gui) = r
  (J.Core.set_target_fps(core, 60), (frame, State{gui, 0, False{}, 40.0, "styled", G.Gui.editing()}))

# After InitWindow(420, 300): GuiLoadStyle("style.rgs"), SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & G.Gui, J.Core & (J.Frame & State), G.Gui.load_style(G.Gui.new(), frame, dir ++ "style.rgs"),
    r => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, r)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "jonlib gui - load style", 420, 300, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
