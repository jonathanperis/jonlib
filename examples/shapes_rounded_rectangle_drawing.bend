# raylib [shapes] example - rounded rectangle drawing, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_rounded_rectangle_drawing.c
# (zlib/libpng, Copyright (c) 2018-2025 Vlad Adrian (@demizdor) and Ramon
# Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A rectangle, its rounded form and its rounded outline, with five raygui
# slider bars (size, roundness, line thickness, segments) and three check
# boxes (Jongui). The controls run inside the frame, after the shapes are
# drawn, as in the example: a changed value shows from the next frame on.
# The corners' sinf/cosf and the segment estimate (0 segments at the start)
# follow the libm profile. See docs/GUI.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# values: width, height, roundness, lineThick, segments;
# checks: drawRoundedRect, drawRoundedLines, drawRect.
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

# ((screenWidth - width - 250)/2, (screenHeight - height)/2, width, height).
def rec(+v: +List<F32>) -> J.Rectangle:
  J.Rectangle{((800.0 - at(v, 0n) - 250.0) / 2.0 : F32), ((450.0 - at(v, 1n)) / 2.0 : F32), at(v, 0n), at(v, 1n)}

def plain(visible: Bool, +v: +List<F32>, frame: J.Frame) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: J.Draw.rectangle_rec(frame, rec(v), J.Color.with_alpha(J.Color.GOLD(), 0.6))

def rounded(visible: Bool, +libm: M.Libm, +v: +List<F32>, frame: J.Frame) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: J.Draw.rectangle_rounded_for(libm, frame, rec(v), at(v, 2n), F32.trunc(at(v, 4n)), J.Color.with_alpha(J.Color.MAROON(), 0.2))

def rounded_lines(visible: Bool, +libm: M.Libm, +v: +List<F32>, frame: J.Frame) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: J.Draw.rectangle_rounded_lines_ex_for(libm, frame, rec(v), at(v, 2n), F32.trunc(at(v, 4n)), at(v, 3n), J.Color.with_alpha(J.Color.MAROON(), 0.4))

def bars() -> +List<G.Gui.Bar>:
  [G.GuiBar{J.Rectangle{640.0, 40.0, 105.0, 20.0}, "Width", 0.0, (800.0 - 300.0 : F32)},
   G.GuiBar{J.Rectangle{640.0, 70.0, 105.0, 20.0}, "Height", 0.0, (450.0 - 50.0 : F32)},
   G.GuiBar{J.Rectangle{640.0, 140.0, 105.0, 20.0}, "Roundness", 0.0, 1.0},
   G.GuiBar{J.Rectangle{640.0, 170.0, 105.0, 20.0}, "Thickness", 0.0, 20.0},
   G.GuiBar{J.Rectangle{640.0, 240.0, 105.0, 20.0}, "Segments", 0.0, 60.0}]

def boxes() -> +List<G.Gui.Box>:
  [G.GuiBox{J.Rectangle{640.0, 320.0, 20.0, 20.0}, "DrawRoundedRect"},
   G.GuiBox{J.Rectangle{640.0, 350.0, 20.0, 20.0}, "DrawRoundedLines"},
   G.GuiBox{J.Rectangle{640.0, 380.0, 20.0, 20.0}, "DrawRect"}]

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# "MODE: MANUAL" from 4 segments.
def mode(manual: Bool, frame: J.Frame) -> J.Frame:
  match manual:
    case True{}: J.Draw.text(frame, "MODE: MANUAL", 640.0, 280.0, 10.0, J.Color.MAROON())
    case False{}: J.Draw.text(frame, "MODE: AUTO", 640.0, 280.0, 10.0, J.Color.DARKGRAY())

def draw.boxes(+core: J.Core, +gui: G.Gui, +v: +List<F32>, r: J.Frame & +List<Bool>) -> J.Core & (State & J.Frame):
  (frame, +checks) = r
  draw.fps.done(State{gui, v, checks}, mode((at(v, 4n) >= 4.0 : F32), frame), J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.values(+core: J.Core, +checks: +List<Bool>, frame: J.Frame, rest: G.Gui & +List<F32>) -> J.Core & (State & J.Frame):
  (+gui, +values) = rest
  draw.boxes(core, gui, values, G.Gui.check_boxes(gui, core, frame, boxes(), checks))

def draw.bars(+core: J.Core, +checks: +List<Bool>, r: J.Frame & (G.Gui & +List<F32>)) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.values(core, checks, frame, rest)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +values, +checks} = state
  f1 = J.Draw.line(J.Frame.clear_background(frame, J.Color.RAYWHITE()), 560.0, 0.0, 560.0, 450.0, J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.6))
  f2 = J.Draw.rectangle(f1, 560.0, 0.0, (800.0 - 500.0 : F32), 450.0, J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.3))
  f3 = rounded_lines(on(checks, 1n), libm, values, rounded(on(checks, 0n), libm, values, plain(on(checks, 2n), values, f2)))
  draw.bars(core, checks, G.Gui.slider_bars(gui, core, f3, bars(), values, "%.2f"))

# The main loop's body; libm is the profile of the corners' sinf/cosf and segment estimate.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): a 200x100 rectangle, roundness 0.2, thickness 1,
# 0 segments, the rounded rectangle drawn, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), [200.0, 100.0, 0.2, 1.0, 0.0], [True{}, False{}, False{}]}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - rounded rectangle drawing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
