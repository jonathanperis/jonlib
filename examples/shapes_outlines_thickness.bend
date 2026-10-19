# raylib [shapes] example - outlines thickness, ported to Jonlib.
# Adapted from raylib 6.2 examples/shapes/shapes_outlines_thickness.c
# (zlib/libpng, Copyright (c) 2026 Matthew Roush (@MatthewRoush)); see
# LICENSES/raylib.txt.
#
# A rectangle, a rounded rectangle and a circle, each filled and outlined
# with its Draw*LinesEx at the thickness of a raygui slider bar (Jongui,
# -30 to 30: a negative thickness draws the outline outside the shape). The
# slider runs before the shapes, as in the example: a changed thickness shows
# in the same frame. The rounded rectangle's and the circle's sinf/cosf
# follow the libm profile; under the Apple profile a frame Jonlib cannot
# reproduce is refused. See docs/GUI.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

type State is Data:
  State{gui: G.Gui, thick: F32}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

# A slider's outcome: the frame, the Gui and the value.
type Slid is Type:
  Slid{frame: J.Frame, gui: G.Gui, value: F32}

def slid.value(gui: G.Gui, frame: J.Frame, pair: F32 & Bool) -> Slid:
  (value, _) = pair
  Slid{frame, gui, value}

def slid.gui(frame: J.Frame, rest: G.Gui & (F32 & Bool)) -> Slid:
  (gui, pair) = rest
  slid.value(gui, frame, pair)

def slid.done(r: J.Frame & (G.Gui & (F32 & Bool))) -> Slid:
  (frame, rest) = r
  slid.gui(frame, rest)

def slid.text(text: Maybe<String>, +gui: G.Gui, +core: J.Core, frame: J.Frame, +value: F32) -> Slid:
  match text:
    case None{}: Slid{J.Frame.refuse(frame), gui, value}
    case Some{t}: slid.done(G.Gui.slider_bar(gui, core, frame, J.Rectangle{290.0, 50.0, 220.0, 24.0}, Some{"Thickness"}, Some{t}, value, F32.neg(30.0), 30.0))

# GuiSliderBar((Rectangle){ 290, 50, 220, 24 }, "Thickness", TextFormat("%.2f", thick), &thick, -30.0f, 30.0f).
def slide(+gui: G.Gui, +core: J.Core, frame: J.Frame, +value: F32) -> Slid:
  slid.text(J.Text.format("%.2f", [J.TextFloat{value}]), gui, core, frame, value)

# The three shapes with the thickness the slider left in this frame.
def shapes(+libm: M.Libm, +core: J.Core, r: Slid) -> J.Core & (State & J.Frame):
  Slid{frame, +gui, +thick} = r
  f1 = J.Draw.rectangle(frame, 35.0, 180.0, 220.0, 220.0, J.Color.LIGHTGRAY())
  f2 = J.Draw.rectangle_lines_ex(f1, J.Rectangle{35.0, 180.0, 220.0, 220.0}, thick, J.Color.BLUE())
  f3 = J.Draw.text(f2, "DrawRectangleLinesEx()", 35.0, 160.0, 10.0, J.Color.BLACK())
  f4 = J.Draw.rectangle_rounded_for(libm, f3, J.Rectangle{290.0, 180.0, 220.0, 220.0}, 0.2, 9.0, J.Color.LIGHTGRAY())
  f5 = J.Draw.rectangle_rounded_lines_ex_for(libm, f4, J.Rectangle{290.0, 180.0, 220.0, 220.0}, 0.2, 9.0, thick, J.Color.BLUE())
  f6 = J.Draw.text(f5, "DrawRectangleRoundedLinesEx()", 290.0, 160.0, 10.0, J.Color.BLACK())
  f7 = J.Draw.circle_for(libm, f6, 655.0, 290.0, 110.0, J.Color.LIGHTGRAY())
  f8 = J.Draw.circle_lines_ex_for(libm, f7, M.Vector2{655.0, 290.0}, 110.0, thick, J.Color.BLUE())
  (core, (State{gui, thick}, J.Draw.text(f8, "DrawCircleLinesEx()", 545.0, 160.0, 10.0, J.Color.BLACK())))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +thick} = state
  shapes(libm, core, slide(gui, core, J.Frame.clear_background(frame, J.Color.RAYWHITE()), thick))

# The main loop's body; libm is the sinf/cosf profile of the rounded rectangle and the circle.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): thick = 5, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), 5.0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - outlines thickness", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
