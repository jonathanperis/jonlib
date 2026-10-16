# Jongui's GuiColorPicker, GuiColorPickerHSV, GuiColorPanel, GuiColorBarAlpha
# and GuiColorBarHue, ported from tools/reference/gui/gui_color_pickers.c (a
# probe-only raygui program, not a raylib example) and replayed against it by
# tools/examples_probe.py (category gui). raygui's drag (guiControlExclusive*)
# is in the Gui, which each control passes on to the next.
import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../jongui.bend as G

type State is Data:
  State{gui: G.Gui, color: U32, hsv: M.Vector3, panel: U32, alpha: F32, hue: F32}

def shown(found: Maybe<String>) -> String:
  match found:
    case None{}: ""
    case Some{+t}: t

def first(r: J.Frame & (G.Gui & F32)) -> J.Frame:
  (frame, _) = r
  frame

def first.color(r: J.Frame & (G.Gui & U32)) -> J.Frame:
  (frame, _) = r
  frame

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def counters(+color: U32, +panel: U32, hsv: M.Vector3, +alpha: F32, +hue: F32) -> String:
  M.Vector3{+h, +s, +v} = hsv
  shown(J.Text.format("%d %d %d %d %d %d %d %.3f %.3f %.3f %.3f %.3f", [J.TextInt{J.Color.red(color)}, J.TextInt{J.Color.green(color)}, J.TextInt{J.Color.blue(color)},
    J.TextInt{J.Color.red(panel)}, J.TextInt{J.Color.green(panel)}, J.TextInt{J.Color.blue(panel)}, J.TextInt{J.Color.alpha(panel)},
    J.TextFloat{h}, J.TextFloat{s}, J.TextFloat{v}, J.TextFloat{alpha}, J.TextFloat{hue}]))

def draw.hued.rest(+core: J.Core, +color: U32, +hsv: M.Vector3, +panel: U32, +alpha: F32, frame: J.Frame, rest: G.Gui & F32) -> J.Core & (State & J.Frame):
  (+gui, +hue) = rest
  +off = G.Gui.disable(gui)
  f1 = first.color(G.Gui.color_panel(off, core, frame, J.Rectangle{400.0, 10.0, 80.0, 80.0}, None{}, J.Color.rgba(30, 60, 90, 255)))
  f2 = first(G.Gui.color_bar_alpha(off, core, f1, J.Rectangle{400.0, 110.0, 80.0, 16.0}, None{}, 0.25))
  f3 = first(G.Gui.color_bar_hue(off, core, f2, J.Rectangle{400.0, 140.0, 16.0, 80.0}, None{}, 200.0))
  f4 = J.Draw.text(f3, counters(color, panel, hsv, alpha, hue), 10.0, 300.0, 10.0, J.Color.BLACK())
  (core, (State{gui, color, hsv, panel, alpha, hue}, f4))

def draw.hued(+core: J.Core, +color: U32, +hsv: M.Vector3, +panel: U32, +alpha: F32, r: J.Frame & (G.Gui & F32)) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.hued.rest(core, color, hsv, panel, alpha, frame, rest)

def draw.alphaed.rest(+core: J.Core, +color: U32, +hsv: M.Vector3, +panel: U32, +hue: F32, frame: J.Frame, rest: G.Gui & F32) -> J.Core & (State & J.Frame):
  (+gui, +alpha) = rest
  draw.hued(core, color, hsv, panel, alpha, G.Gui.color_bar_hue(gui, core, frame, J.Rectangle{320.0, 180.0, 20.0, 110.0}, None{}, hue))

def draw.alphaed(+core: J.Core, +color: U32, +hsv: M.Vector3, +panel: U32, +hue: F32, r: J.Frame & (G.Gui & F32)) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.alphaed.rest(core, color, hsv, panel, hue, frame, rest)

def draw.paneled.rest(+core: J.Core, +color: U32, +hsv: M.Vector3, +alpha: F32, +hue: F32, frame: J.Frame, rest: G.Gui & U32) -> J.Core & (State & J.Frame):
  (+gui, +panel) = rest
  draw.alphaed(core, color, hsv, panel, hue, G.Gui.color_bar_alpha(gui, core, frame, J.Rectangle{150.0, 200.0, 150.0, 20.0}, None{}, alpha))

def draw.paneled(+core: J.Core, +color: U32, +hsv: M.Vector3, +alpha: F32, +hue: F32, r: J.Frame & (G.Gui & U32)) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.paneled.rest(core, color, hsv, alpha, hue, frame, rest)

def draw.hsved.rest(+core: J.Core, +color: U32, +panel: U32, +alpha: F32, +hue: F32, frame: J.Frame, rest: G.Gui & M.Vector3) -> J.Core & (State & J.Frame):
  (+gui, +hsv) = rest
  draw.paneled(core, color, hsv, alpha, hue, G.Gui.color_panel(gui, core, frame, J.Rectangle{10.0, 180.0, 120.0, 100.0}, None{}, panel))

def draw.hsved(+core: J.Core, +color: U32, +panel: U32, +alpha: F32, +hue: F32, r: J.Frame & (G.Gui & M.Vector3)) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.hsved.rest(core, color, panel, alpha, hue, frame, rest)

def draw.picked.rest(+core: J.Core, +hsv: M.Vector3, +panel: U32, +alpha: F32, +hue: F32, frame: J.Frame, rest: G.Gui & U32) -> J.Core & (State & J.Frame):
  (+gui, +color) = rest
  draw.hsved(core, color, panel, alpha, hue, G.Gui.color_picker_hsv(gui, core, frame, J.Rectangle{200.0, 10.0, 150.0, 150.0}, None{}, hsv))

def draw.picked(+core: J.Core, +hsv: M.Vector3, +panel: U32, +alpha: F32, +hue: F32, r: J.Frame & (G.Gui & U32)) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.picked.rest(core, hsv, panel, alpha, hue, frame, rest)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +color, +hsv, +panel, +alpha, +hue} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  draw.picked(core, hsv, panel, alpha, hue, G.Gui.color_picker(gui, core, f1, J.Rectangle{10.0, 10.0, 150.0, 150.0}, None{}, color))

def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(500, 320): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), J.Color.rgba(200, 0, 0, 255), M.Vector3{120.0, 0.5, 0.8}, J.Color.rgba(10, 200, 100, 128), 0.5, 90.0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "jonlib gui - color pickers", 500, 320, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
