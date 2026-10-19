# Jongui's tooltips (GuiEnableTooltip, GuiDisableTooltip, GuiSetTooltip),
# GuiDrawIcon and GuiIconText, ported from
# tools/reference/gui/gui_tooltip_icons.c (a probe-only raygui program, not a
# raylib example) and replayed against it by tools/examples_probe.py
# (category gui). raygui's text box globals are passed from frame to frame.
import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../jongui.bend as G

type State is Data:
  State{gui: G.Gui, clicks: U32, on: Bool, text: String, editing: G.Gui.Editing}

def shown(found: Maybe<String>) -> String:
  match found:
    case None{}: ""
    case Some{+t}: t

def first(r: J.Frame & Bool) -> J.Frame:
  (frame, _) = r
  frame

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def draw.done(+core: J.Core, +gui: G.Gui, +clicks: U32, +on: Bool, +text: String, frame: J.Frame, rest: G.Gui.Editing & Bool) -> J.Core & (State & J.Frame):
  (+editing, _) = rest
  f1 = first(G.Gui.button(G.Gui.set_tooltip(gui, None{}), core, frame, J.Rectangle{10.0, 60.0, 120.0, 30.0}, "No tooltip"))
  +off = G.Gui.disable_tooltip(G.Gui.set_tooltip(gui, Some{"Hidden"}))
  f2 = first(G.Gui.button(off, core, f1, J.Rectangle{10.0, 110.0, 120.0, 30.0}, "Tooltips off"))
  f3 = G.Gui.draw_icon(off, f2, 6, 200, 60, 1, J.Color.BLACK())
  f4 = G.Gui.draw_icon(off, f3, 121, 230, 60, 2, J.Color.RED())
  f5 = G.Gui.draw_icon(G.Gui.set_alpha(off, 0.5), f4, 200, 280, 60, 3, J.Color.BLUE())
  f6 = G.Gui.draw_icon(off, f5, 1, 400, 150, 4294967294, J.Color.DARKGREEN())
  f7 = G.Gui.label(off, f6, J.Rectangle{200.0, 160.0, 150.0, 20.0}, shown(G.Gui.icon_text(4294967291, Some{"negative"})))
  f8 = G.Gui.label(off, f7, J.Rectangle{200.0, 190.0, 150.0, 20.0}, shown(G.Gui.icon_text(1000, Some{"four digits"})))
  f9 = G.Gui.label(off, f8, J.Rectangle{200.0, 220.0, 150.0, 20.0}, shown(G.Gui.icon_text(121, None{})))
  f10 = G.Gui.draw_icon(off, f9, 256, 330, 60, 1, J.Color.BLACK())
  f11 = G.Gui.draw_icon(off, f10, 511, 350, 60, 1, J.Color.BLACK())
  f12 = first(G.Gui.button(off, core, f11, J.Rectangle{330.0, 245.0, 160.0, 20.0}, "#600#Six"))
  f13 = first(G.Gui.button(off, core, f12, J.Rectangle{330.0, 270.0, 100.0, 20.0}, "#250##5#Two"))
  f14 = J.Draw.text(f13, U32.show(clicks) ++ " " ++ Bool.pick(String, on, "1", "0"), 440.0, 285.0, 10.0, J.Color.BLACK())
  (core, (State{off, clicks, on, text, editing}, f14))

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
  draw.boxed(gui, clicks, on, G.Gui.text_box(G.Gui.set_tooltip(gui, Some{"two\nlines"}), core, frame, J.Rectangle{10.0, 255.0, 150.0, 30.0}, text, 64, False{}, editing))

def draw.saved(+core: J.Core, +gui: G.Gui, +clicks: U32, +on: Bool, +text: String, +editing: G.Gui.Editing, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +clicked) = r
  draw.toggled(core, gui, Bool.pick(U32, clicked, (clicks + 1 : U32), clicks), text, editing,
    G.Gui.toggle(G.Gui.set_tooltip(gui, Some{"A tooltip longer than the space left"}), core, frame, J.Rectangle{380.0, 10.0, 110.0, 30.0}, "Toggle", on))

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +clicks, +on, +text, +editing} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  +tipped = G.Gui.set_tooltip(G.Gui.enable_tooltip(gui), Some{"Saves the file"})
  draw.saved(core, tipped, clicks, on, text, editing, G.Gui.button(tipped, core, f1, J.Rectangle{10.0, 10.0, 120.0, 30.0}, shown(G.Gui.icon_text(6, Some{"Save"}))))

def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(500, 300): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), 0, False{}, "box", G.Gui.editing()}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "jonlib gui - tooltips and icons", 500, 300, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
