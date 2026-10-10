# raylib [shapes] example - ring drawing, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_ring_drawing.c (zlib/libpng,
# Copyright (c) 2018-2025 Vlad Adrian (@demizdor) and Ramon Santamaria
# (@raysan5)); see LICENSES/raylib.txt.
#
# A ring, its outline and its sector outline, with five raygui slider bars
# (the angles, the radii and the segment count) and three check boxes
# (Jongui). The controls run inside the frame, after the shapes are drawn,
# as in the example: a changed value shows from the next frame on. The
# shapes' sinf/cosf and the segment estimate (0 segments at the start)
# follow the libm profile. See docs/GUI.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# values: startAngle, endAngle, innerRadius, outerRadius, segments;
# checks: drawRing, drawRingLines, drawCircleLines.
type State is Data:
  State{gui: G.Gui, values: +List<F32>, checks: +List<Bool>}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def first(values: +List<F32>) -> F32:
  match values:
    case Con{v, _}: v
    case Nil{}: 0.0

def at(+values: +List<F32>, n: Nat) -> F32:
  first(List.drop(&2, F32, values, n))

def flag(values: +List<Bool>) -> Bool:
  match values:
    case Con{v, _}: v
    case Nil{}: False{}

def on(+checks: +List<Bool>, n: Nat) -> Bool:
  flag(List.drop(&2, Bool, checks, n))

def center() -> M.Vector2:
  M.Vector2{((800.0 - 300.0) / 2.0 : F32), (450.0 / 2.0 : F32)}

def ring(visible: Bool, +libm: M.Libm, +v: +List<F32>, frame: J.Frame) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: J.Draw.ring_for(libm, frame, center(), at(v, 2n), at(v, 3n), at(v, 0n), at(v, 1n), F32.trunc(at(v, 4n)), J.Color.with_alpha(J.Color.MAROON(), 0.3))

def ring_lines(visible: Bool, +libm: M.Libm, +v: +List<F32>, frame: J.Frame) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: J.Draw.ring_lines_for(libm, frame, center(), at(v, 2n), at(v, 3n), at(v, 0n), at(v, 1n), F32.trunc(at(v, 4n)), J.Color.with_alpha(J.Color.BLACK(), 0.4))

def circle_lines(visible: Bool, +libm: M.Libm, +v: +List<F32>, frame: J.Frame) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: J.Draw.circle_sector_lines_for(libm, frame, center(), at(v, 3n), at(v, 0n), at(v, 1n), F32.trunc(at(v, 4n)), J.Color.with_alpha(J.Color.BLACK(), 0.4))

def bars() -> +List<G.Gui.Bar>:
  [G.GuiBar{J.Rectangle{600.0, 40.0, 120.0, 20.0}, "StartAngle", "%.2f", F32.neg(450.0), 450.0},
   G.GuiBar{J.Rectangle{600.0, 70.0, 120.0, 20.0}, "EndAngle", "%.2f", F32.neg(450.0), 450.0},
   G.GuiBar{J.Rectangle{600.0, 140.0, 120.0, 20.0}, "InnerRadius", "%.2f", 0.0, 100.0},
   G.GuiBar{J.Rectangle{600.0, 170.0, 120.0, 20.0}, "OuterRadius", "%.2f", 0.0, 200.0},
   G.GuiBar{J.Rectangle{600.0, 240.0, 120.0, 20.0}, "Segments", "%.2f", 0.0, 100.0}]

def boxes() -> +List<G.Gui.Box>:
  [G.GuiBox{J.Rectangle{600.0, 320.0, 20.0, 20.0}, "Draw Ring"},
   G.GuiBox{J.Rectangle{600.0, 350.0, 20.0, 20.0}, "Draw RingLines"},
   G.GuiBox{J.Rectangle{600.0, 380.0, 20.0, 20.0}, "Draw CircleLines"}]

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# minSegments = (int)ceilf((endAngle - startAngle)/90); "MODE: MANUAL" when segments reach it.
def mode(manual: Bool, frame: J.Frame) -> J.Frame:
  match manual:
    case True{}: J.Draw.text(frame, "MODE: MANUAL", 600.0, 270.0, 10.0, J.Color.MAROON())
    case False{}: J.Draw.text(frame, "MODE: AUTO", 600.0, 270.0, 10.0, J.Color.DARKGRAY())

def draw.boxes(+core: J.Core, +gui: G.Gui, +v: +List<F32>, r: J.Frame & +List<Bool>) -> J.Core & (State & J.Frame):
  (frame, +checks) = r
  +minimum = F32.trunc(F32.ceil(((at(v, 1n) - at(v, 0n)) / 90.0 : F32)))
  draw.fps.done(State{gui, v, checks}, mode((at(v, 4n) >= minimum : F32), frame), J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.values(+core: J.Core, +checks: +List<Bool>, frame: J.Frame, rest: G.Gui & +List<F32>) -> J.Core & (State & J.Frame):
  (+gui, +values) = rest
  draw.boxes(core, gui, values, G.Gui.check_boxes(gui, core, frame, boxes(), checks))

def draw.bars(+core: J.Core, +checks: +List<Bool>, r: J.Frame & (G.Gui & +List<F32>)) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.values(core, checks, frame, rest)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +values, +checks} = state
  f1 = J.Draw.line(J.Frame.clear_background(frame, J.Color.RAYWHITE()), 500.0, 0.0, 500.0, 450.0, J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.6))
  f2 = J.Draw.rectangle(f1, 500.0, 0.0, (800.0 - 500.0 : F32), 450.0, J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.3))
  f3 = circle_lines(on(checks, 2n), libm, values, ring_lines(on(checks, 1n), libm, values, ring(on(checks, 0n), libm, values, f2)))
  draw.bars(core, checks, G.Gui.slider_bars(gui, core, f3, bars(), values))

# The main loop's body; libm is the profile of the shapes' sinf/cosf and segment estimate.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): angles 0 to 360, radii 80 and 190, 0 segments,
# the ring drawn, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), [0.0, 360.0, 80.0, 190.0, 0.0], [True{}, False{}, False{}]}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - ring drawing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
