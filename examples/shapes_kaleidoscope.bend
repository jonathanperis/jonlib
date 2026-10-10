# raylib [shapes] example - kaleidoscope, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_kaleidoscope.c (zlib/libpng,
# Copyright (c) 2025 Hugo ARNAL (@hugoarnal) and Ramon Santamaria (@raysan5));
# see LICENSES/raylib.txt.
#
# Dragging the mouse draws a line mirrored through six rotations and their
# reflections around the screen center; raygui buttons (Jongui) step back and
# forward through the lines and reset them, disabled when there is nothing to
# step to. The buttons' clicks act on the next frame, as in the example.
# Vector2Rotate's sinf/cosf of 60 degrees follow the libm profile. The
# example runs at 20 frames a second. See docs/GUI.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

type Line is Data:
  Line{start: M.Vector2, end: M.Vector2}

# clicks: the back, next and reset buttons of the last frame.
type Clicks is Data:
  Clicks{back: Bool, next: Bool, reset: Bool}

type State is Data:
  State{gui: G.Gui, lines: +List<Line>, current: U32, total: U32, mouse: M.Vector2, clicks: Clicks}

type Added is Data:
  Added{lines: +List<Line>, total: U32}

def reset_rec() -> J.Rectangle:
  J.Rectangle{(800.0 - 55.0 : F32), 5.0, 50.0, 25.0}

def back_rec() -> J.Rectangle:
  J.Rectangle{(800.0 - 55.0 : F32), (450.0 - 30.0 : F32), 25.0, 25.0}

def next_rec() -> J.Rectangle:
  J.Rectangle{(800.0 - 30.0 : F32), (450.0 - 30.0 : F32), 25.0, 25.0}

def offset() -> M.Vector2:
  M.Vector2{(800.0 / 2.0 : F32), (450.0 / 2.0 : F32)}

def spokes.pushed(room: Bool, +a: M.Vector2, +b: M.Vector2, rest: Added) -> Added:
  match room:
    case False{}: rest
    case True{}:
      Added{lines, total} = rest
      Added{Con{Line{a, b}, Con{Line{M.Vector2.multiply(a, M.Vector2{1.0, F32.neg(1.0)}), M.Vector2.multiply(b, M.Vector2{1.0, F32.neg(1.0)})}, lines}}, total}

# for (s = 0; (s < symmetry) && (totalLineCounter < MAX_DRAW_LINES - 1); s++):
# the line turned 60 degrees more each time, and its reflection.
def spokes(n: Nat, +libm: M.Libm, +start: M.Vector2, +end: M.Vector2, +total: U32) -> Added:
  match n:
    case 0n: Added{Nil{}, total}
    case 1n+p:
      +turn = ((360.0 / 6.0) * (3.14159265358979323846 / 180.0) : F32)
      +a = M.Vector2.rotate_for(libm, start, turn)
      +b = M.Vector2.rotate_for(libm, end, turn)
      +room = (total < 8191 : U32)
      spokes.pushed(room, a, b, spokes(p, libm, a, b, Bool.pick(U32, room, (total + 2 : U32), total)))

def update.counted(+gui: G.Gui, +lines: +List<Line>, +current: U32, +total: U32, +mouse: M.Vector2, +clicks: Clicks) -> State:
  Clicks{+back, +next, +reset} = clicks
  +kept = Bool.pick(U32, reset, 0, current)
  +count = Bool.pick(U32, reset, 0, total)
  +stepped = Bool.pick(U32, back && (kept > 0 : U32), (kept - 1 : U32), kept)
  +forward = Bool.pick(U32, next && (stepped < 8192 : U32) && ((stepped + 1) <= count : U32), (stepped + 1 : U32), stepped)
  State{gui, Bool.pick(+List<Line>, reset, Nil{}, lines), forward, count, mouse, clicks}

def update.added(+gui: G.Gui, +lines: +List<Line>, +current: U32, +total: U32, +mouse: M.Vector2, +clicks: Clicks, added: Added) -> State:
  Added{+fresh, +count} = added
  update.counted(gui, List.append(&2, Line, lines, fresh), Bool.pick(U32, U32.is_eq(count, total), current, count), count, mouse, clicks)

# The mouse draws while its left button is down outside the three buttons.
def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+gui, +lines, +current, +total, +mouse, +clicks} = state
  +now = J.Input.get_mouse_position(core)
  +drawing = J.Input.is_mouse_button_down(core, 0) && Bool.not(J.Collision.point_rec(now, reset_rec()))
    && Bool.not(J.Collision.point_rec(now, back_rec())) && Bool.not(J.Collision.point_rec(now, next_rec()))
  (core, update.added(gui, lines, current, total, now, clicks,
    Bool.pick(Added, drawing, spokes(6n, libm, M.Vector2.subtract(now, offset()), M.Vector2.subtract(mouse, offset()), total), Added{Nil{}, total})))

def stroke(+line: Line, frame: J.Frame) -> J.Frame:
  Line{start, end} = line
  J.Draw.line_ex(frame, start, end, 3.0, J.Color.BLACK())

def strokes(lines: +List<Line>, frame: J.Frame) -> J.Frame:
  match lines:
    case Nil{}: frame
    case Con{+line, rest}: strokes(rest, stroke(line, frame))

# The lines drawn once per symmetry (six times over).
def passes(n: Nat, +lines: +List<Line>, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: passes(p, lines, strokes(lines, frame))

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, (450.0 - 30.0 : F32), 20.0, J.Color.MAROON())

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.reset(+core: J.Core, +state: State, +back: Bool, +next: Bool, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  State{+gui, +lines, +current, +total, +mouse, _} = state
  (frame, +reset) = r
  draw.fps.done(State{gui, lines, current, total, mouse, Clicks{back, next, reset}},
    label(J.Text.format("LINES: %i/%i", [J.TextInt{current}, J.TextInt{8192}]), frame), J.Core.get_fps(core, J.Core.get_time(core)), core)

# GuiEnable(); the reset button.
def draw.next(+core: J.Core, +state: State, +gui: G.Gui, +back: Bool, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +next) = r
  draw.reset(core, state, back, next, G.Gui.button(G.Gui.enable(gui), core, frame, reset_rec(), "Reset"))

# GuiEnable(); the next button, disabled when no line follows.
def draw.back(+core: J.Core, +state: State, +gui: G.Gui, +current: U32, +total: U32, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +back) = r
  +enabled = G.Gui.enable(gui)
  +forward = Bool.pick(G.Gui, ((current + 1) > total : U32), G.Gui.disable(enabled), enabled)
  draw.next(core, state, forward, back, G.Gui.button(forward, core, frame, next_rec(), ">"))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +lines, +current, +total, _, _} = state
  +camera = {J.Camera2D{offset(), M.Vector2.zero(), 0.0, 1.0} : J.Camera2D}
  +shown = List.take(&2, Line, lines, U32.to_nat((current + current % 2 : U32)))
  f1 = J.Frame.end_mode_2d(passes(6n, shown, J.Frame.begin_mode_2d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera)))
  +backward = Bool.pick(G.Gui, U32.is_eq(current, 0), G.Gui.disable(gui), gui)
  draw.back(core, state, backward, current, total, G.Gui.button(backward, core, f1, back_rec(), "<"))

# The main loop's body; libm is the sinf/cosf profile of Vector2Rotate and BeginMode2D (rotation 0).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): no lines, the mouse at (0, 0), SetTargetFPS(20).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 20), (frame, State{G.Gui.new(), Nil{}, 0, 0, M.Vector2.zero(), Clicks{False{}, False{}, False{}}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - kaleidoscope", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
