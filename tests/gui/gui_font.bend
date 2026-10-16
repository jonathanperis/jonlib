# Jongui's GuiSetFont and GuiGetFont, ported from
# tools/reference/gui/gui_font.c (a probe-only raygui program, not a raylib
# example) and replayed against it by tools/examples_probe.py (category
# gui). The font is loaded in the setup and set into the gui, which keeps a
# copy of it; the text box globals are passed from frame to frame.
import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../jongui.bend as G

type State is Data:
  State{gui: G.Gui, clicks: U32, on: Bool, text: String, editing: G.Gui.Editing}

def first(r: J.Frame & Bool) -> J.Frame:
  (frame, _) = r
  frame

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def draw.done(+core: J.Core, +gui: G.Gui, +clicks: U32, +on: Bool, +text: String, frame: J.Frame, rest: G.Gui.Editing & Bool) -> J.Core & (State & J.Frame):
  (+editing, _) = rest
  f1 = G.Gui.label(gui, frame, J.Rectangle{10.0, 130.0, 60.0, 30.0}, "A label wider than its bounds")
  f2 = G.Gui.label(G.Gui.set_style(gui, 0, 16, 20), f1, J.Rectangle{10.0, 165.0, 300.0, 30.0}, "Twenty")
  f3 = first(G.Gui.button(G.Gui.set_tooltip(G.Gui.enable_tooltip(gui), Some{"A tip in the font"}), core, f2, J.Rectangle{220.0, 90.0, 100.0, 30.0}, "Tip"))
  f4 = J.Draw.text(f3, U32.show(clicks) ++ " " ++ Bool.pick(String, on, "1", "0") ++ " " ++ U32.show(G.Gui.font_base_size(gui)), 300.0, 240.0, 10.0, J.Color.BLACK())
  (core, (State{G.Gui.disable_tooltip(G.Gui.set_tooltip(G.Gui.enable_tooltip(gui), Some{"A tip in the font"})), clicks, on, text, editing}, f4))

def draw.texted(+core: J.Core, +gui: G.Gui, +clicks: U32, +on: Bool, frame: J.Frame, rest: String & (G.Gui.Editing & Bool)) -> J.Core & (State & J.Frame):
  (+text, more) = rest
  draw.done(core, gui, clicks, on, text, frame, more)

def draw.cored(+gui: G.Gui, +clicks: U32, +on: Bool, frame: J.Frame, rest: J.Core & (String & (G.Gui.Editing & Bool))) -> J.Core & (State & J.Frame):
  (+core, more) = rest
  draw.texted(core, gui, clicks, on, frame, more)

def draw.boxed(+gui: G.Gui, +clicks: U32, +on: Bool, r: J.Frame & (J.Core & (String & (G.Gui.Editing & Bool)))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.cored(gui, clicks, on, frame, rest)

def draw.toggled(+core: J.Core, +gui: G.Gui, +clicks: U32, +text: String, +editing: G.Gui.Editing, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +on) = r
  draw.boxed(gui, clicks, on, G.Gui.text_box(gui, core, frame, J.Rectangle{10.0, 90.0, 200.0, 30.0}, text, 32, False{}, editing))

def draw.saved(+core: J.Core, +gui: G.Gui, +clicks: U32, +on: Bool, +text: String, +editing: G.Gui.Editing, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +clicked) = r
  draw.toggled(core, gui, Bool.pick(U32, clicked, (clicks + 1 : U32), clicks), text, editing, G.Gui.toggle(gui, core, frame, J.Rectangle{160.0, 50.0, 140.0, 30.0}, "Toggle", on))

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +clicks, +on, +text, +editing} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = G.Gui.label(gui, f1, J.Rectangle{10.0, 10.0, 200.0, 30.0}, "Custom font label")
  draw.saved(core, gui, clicks, on, text, editing, G.Gui.button(gui, core, f2, J.Rectangle{10.0, 50.0, 140.0, 30.0}, "#6#Save"))

def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def font.of(result: Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> J.Font:
  match result:
    case Done{Some{font}}: font
    case _: J.Font.default()

def setup.set(+core: J.Core, frame: J.Frame, r: G.Gui & J.Font) -> J.Core & (J.Frame & State):
  (+gui, _) = r
  (J.Core.set_target_fps(core, 60), (frame, State{gui, 0, False{}, "alagard", G.Gui.editing()}))

def setup.loaded(+core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> J.Core & (J.Frame & State):
  (frame, result) = r
  setup.set(core, frame, G.Gui.set_font(G.Gui.new(), font.of(result)))

# After InitWindow(400, 260): LoadFont("resources/custom_alagard.png"),
# GuiSetFont, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Core & (J.Frame & State), J.Font.load(frame, dir ++ "resources/custom_alagard.png"),
    r => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, r)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "jonlib gui - custom font", 400, 260, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
