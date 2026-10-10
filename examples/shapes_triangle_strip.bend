# raylib [shapes] example - triangle strip, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_triangle_strip.c (zlib/libpng,
# Copyright (c) 2025 Jopestpe (@jopestpe)); see LICENSES/raylib.txt.
#
# A star-shaped ring of triangles between an inner and an outer circle, each
# colored by its angle's hue, with a raygui slider bar for the segment count
# and a check box for the outlines (Jongui). The points come from the
# example's own sinf/cosf, which follow the libm profile: an argument outside
# it refuses the frame (docs/SINCOSF.md). See docs/GUI.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

type State is Data:
  State{gui: G.Gui, segments: F32, outline: Bool}

# The points so far and whether every sinf/cosf was inside the profile.
type Points is Data:
  Points{valid: Bool, list: +List<M.Vector2>}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def point.at(+radius: F32, cosine: Maybe<F32>, sine: Maybe<F32>) -> Maybe<M.Vector2>:
  match cosine sine:
    case Some{c} Some{s}: Some{M.Vector2{((800.0 / 2.0 - 125.0) + c * radius : F32), (450.0 / 2.0 + s * radius : F32)}}
    case _ _: None{}

# center + (cosf(angle)*radius, sinf(angle)*radius).
def point(+libm: M.Libm, +angle: F32, +radius: F32) -> Maybe<M.Vector2>:
  point.at(radius, M.Libm.cos(libm, angle), M.Libm.sin(libm, angle))

def points.pair(a: M.Vector2, b: M.Vector2, rest: Points) -> Points:
  Points{valid, list} = rest
  Points{valid, Con{a, Con{b, list}}}

def points.refused(rest: Points) -> Points:
  Points{_, list} = rest
  Points{False{}, list}

def points.cons(inner: Maybe<M.Vector2>, outer: Maybe<M.Vector2>, rest: Points) -> Points:
  match inner outer:
    case Some{a} Some{b}: points.pair(a, b, rest)
    case _ _: points.refused(rest)

# points[2i] on the inner circle at i*angleStep, points[2i + 1] on the outer one half a step later.
def points.go(n: Nat, +libm: M.Libm, +i: U32, +step: F32) -> Points:
  match n:
    case 0n: Points{True{}, Nil{}}
    case 1n+p:
      +angle = (U32.to_f32(i) * step : F32)
      points.cons(point(libm, angle, 100.0), point(libm, (angle + step / 2.0 : F32), 150.0), points.go(p, libm, (i + 1 : U32), step))

# points[pointCount*2] = points[0]; points[pointCount*2 + 1] = points[1].
def points.closed(+list: +List<M.Vector2>) -> +List<M.Vector2>:
  List.append(&2, M.Vector2, list, List.take(&2, M.Vector2, list, 2n))

def outlined(visible: Bool, +a: M.Vector2, +b: M.Vector2, +c: M.Vector2, +d: M.Vector2, frame: J.Frame) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: J.Draw.triangle_lines(J.Draw.triangle_lines(frame, a, b, c, J.Color.BLACK()), c, b, d, J.Color.BLACK())

def hue(+angle: F32) -> U32:
  J.Color.from_hsv((angle * (180.0 / 3.14159265358979323846) : F32), 1.0, 1.0)

# DrawTriangle(c, b, a, hue(angle1)), DrawTriangle(d, b, c, hue(angle1 + angleStep/2)) and the outlines.
def quad(+a: M.Vector2, +b: M.Vector2, +c: M.Vector2, +d: M.Vector2, +angle: F32, +step: F32, +outline: Bool, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.triangle(frame, c, b, a, hue(angle))
  outlined(outline, a, b, c, d, J.Draw.triangle(f1, d, b, c, hue((angle + step / 2.0 : F32))))

def strip(n: Nat, points: +List<M.Vector2>, +i: U32, +step: F32, +outline: Bool, frame: J.Frame) -> J.Frame:
  match n points:
    case 1n+p Con{+a, Con{+b, Con{+c, Con{+d, +rest}}}}: strip(p, Con{c, Con{d, rest}}, (i + 1 : U32), step, outline, quad(a, b, c, d, (U32.to_f32(i) * step : F32), step, outline, frame))
    case _ _: frame

def star.at(valid: Bool, +list: +List<M.Vector2>, +count: U32, +step: F32, +outline: Bool, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}: strip(U32.to_nat(count), points.closed(list), 0, step, outline, frame)

def star(points: Points, +count: U32, +step: F32, +outline: Bool, frame: J.Frame) -> J.Frame:
  Points{valid, +list} = points
  star.at(valid, list, count, step, outline, frame)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.checked(+core: J.Core, +gui: G.Gui, +segments: F32, frame: J.Frame, pair: Bool & Bool) -> J.Core & (State & J.Frame):
  (outline, _) = pair
  draw.fps.done(State{gui, segments, outline}, frame, J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.box(+core: J.Core, +gui: G.Gui, +segments: F32, r: J.Frame & (Bool & Bool)) -> J.Core & (State & J.Frame):
  (frame, pair) = r
  draw.checked(core, gui, segments, frame, pair)

def draw.slid(+core: J.Core, +outline: Bool, frame: J.Frame, +gui: G.Gui, pair: F32 & Bool) -> J.Core & (State & J.Frame):
  (+segments, _) = pair
  draw.box(core, gui, segments, G.Gui.check_box(gui, core, frame, J.Rectangle{640.0, 70.0, 20.0, 20.0}, "Outline", outline))

def draw.bar.rest(+core: J.Core, +outline: Bool, frame: J.Frame, rest: G.Gui & (F32 & Bool)) -> J.Core & (State & J.Frame):
  (+gui, pair) = rest
  draw.slid(core, outline, frame, gui, pair)

def draw.bar(+core: J.Core, +outline: Bool, r: J.Frame & (G.Gui & (F32 & Bool))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.bar.rest(core, outline, frame, rest)

def draw.text(text: Maybe<String>, +core: J.Core, +gui: G.Gui, +segments: F32, +outline: Bool, frame: J.Frame) -> J.Core & (State & J.Frame):
  match text:
    case None{}: (core, (State{gui, segments, outline}, J.Frame.refuse(frame)))
    case Some{t}: draw.bar(core, outline, G.Gui.slider_bar(gui, core, frame, J.Rectangle{640.0, 40.0, 120.0, 20.0}, Some{"Segments"}, Some{t}, segments, 6.0, 60.0))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +segments, +outline} = state
  +count = F32.to_u32(F32.trunc(segments))
  +step = ((360.0 / U32.to_f32(count)) * (3.14159265358979323846 / 180.0) : F32)
  f1 = star(points.go(U32.to_nat(count), libm, 0, step), count, step, outline, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = J.Draw.line(f1, 580.0, 0.0, 580.0, 450.0, J.Color.rgba(218, 218, 218, 255))
  f3 = J.Draw.rectangle(f2, 580.0, 0.0, 800.0, 450.0, J.Color.rgba(232, 232, 232, 255))
  draw.text(J.Text.format("%.0f", [J.TextFloat{segments}]), core, gui, segments, outline, f3)

# The main loop's body; libm is the profile of the example's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): 6 segments, the outlines on, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), 6.0, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - triangle strip", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
