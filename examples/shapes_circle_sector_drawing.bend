# raylib [shapes] example - circle sector drawing, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_circle_sector_drawing.c
# (zlib/libpng, Copyright (c) 2018-2025 Vlad Adrian (@demizdor) and Ramon
# Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A circle sector and its outline, with four raygui slider bars (Jongui) for
# the start and end angles, the radius and the segment count. The sliders run
# inside the frame, after the sector is drawn, as in the example: a value a
# slider changes shows from the next frame on. DrawCircleSector's sinf/cosf
# follow the libm profile. See docs/GUI.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

type State is Data:
  State{gui: G.Gui, radius: F32, start: F32, end: F32, segments: F32}

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

def slid.text(text: Maybe<String>, +gui: G.Gui, +core: J.Core, frame: J.Frame, +y: F32, label: String, +value: F32, +max: F32) -> Slid:
  match text:
    case None{}: Slid{J.Frame.refuse(frame), gui, value}
    case Some{t}: slid.done(G.Gui.slider_bar(gui, core, frame, J.Rectangle{600.0, y, 120.0, 20.0}, Some{label}, Some{t}, value, 0.0, max))

# GuiSliderBar((600, y, 120, 20), label, TextFormat("%.2f", value), &value, 0, max).
def slid(+gui: G.Gui, +core: J.Core, frame: J.Frame, +y: F32, label: String, +value: F32, +max: F32) -> Slid:
  slid.text(J.Text.format("%.2f", [J.TextFloat{value}]), gui, core, frame, y, label, value, max)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# minSegments = truncf(ceilf((endAngle - startAngle)/90)); "MODE: MANUAL" when segments reach it.
def mode(manual: Bool, frame: J.Frame) -> J.Frame:
  match manual:
    case True{}: J.Draw.text(frame, "MODE: MANUAL", 600.0, 200.0, 10.0, J.Color.MAROON())
    case False{}: J.Draw.text(frame, "MODE: AUTO", 600.0, 200.0, 10.0, J.Color.DARKGRAY())

def draw.segments(+core: J.Core, +radius: F32, +start: F32, +end: F32, r: Slid) -> J.Core & (State & J.Frame):
  Slid{frame, +gui, +segments} = r
  +minimum = F32.trunc(F32.ceil(((end - start) / 90.0 : F32)))
  draw.fps.done(State{gui, radius, start, end, segments}, mode((segments >= minimum : F32), frame), J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.radius(+core: J.Core, +start: F32, +end: F32, +segments: F32, r: Slid) -> J.Core & (State & J.Frame):
  Slid{frame, +gui, +radius} = r
  draw.segments(core, radius, start, end, slid(gui, core, frame, 170.0, "Segments", segments, 100.0))

def draw.end(+core: J.Core, +radius: F32, +start: F32, +segments: F32, r: Slid) -> J.Core & (State & J.Frame):
  Slid{frame, +gui, +end} = r
  draw.radius(core, start, end, segments, slid(gui, core, frame, 140.0, "Radius", radius, 200.0))

def draw.start(+core: J.Core, +radius: F32, +end: F32, +segments: F32, r: Slid) -> J.Core & (State & J.Frame):
  Slid{frame, +gui, +start} = r
  draw.end(core, radius, start, segments, slid(gui, core, frame, 70.0, "EndAngle", end, 720.0))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +radius, +start, +end, +segments} = state
  +center = {M.Vector2{((800.0 - 300.0) / 2.0 : F32), (450.0 / 2.0 : F32)} : M.Vector2}
  f1 = J.Draw.line(J.Frame.clear_background(frame, J.Color.RAYWHITE()), 500.0, 0.0, 500.0, 450.0, J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.6))
  f2 = J.Draw.rectangle(f1, 500.0, 0.0, (800.0 - 500.0 : F32), 450.0, J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.3))
  f3 = J.Draw.circle_sector_for(libm, f2, center, radius, start, end, F32.trunc(segments), J.Color.with_alpha(J.Color.MAROON(), 0.3))
  f4 = J.Draw.circle_sector_lines_for(libm, f3, center, radius, start, end, F32.trunc(segments), J.Color.with_alpha(J.Color.MAROON(), 0.6))
  draw.start(core, radius, end, segments, slid(gui, core, f4, 40.0, "StartAngle", start, 720.0))

# The main loop's body; libm is the sinf/cosf profile of the sector.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): radius 180, angles 0 to 180, 10 segments, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), 180.0, 0.0, 180.0, 10.0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - circle sector drawing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
