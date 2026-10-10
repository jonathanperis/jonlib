# raylib [textures] example - textured curve, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_textured_curve.c (zlib/libpng,
# Copyright (c) 2022-2025 Jeffery Myers (@JeffM2501) and Ramon Santamaria (@raysan5));
# see LICENSES/raylib.txt.
#
# A road texture drawn along a cubic Bezier curve as rlgl quads, a quad per
# segment between the curve's normals; the four control points are dragged
# with the mouse, SPACE shows the base curve, + and - change the width, LEFT
# and RIGHT the segments. The example never unbinds the road texture, so the
# reference curve, the control lines and the control points are drawn with
# it bound, up to the first text; the texture is taken back from the frame
# after the texts. The weights' powf(x, 3) follows the libm profile
# (M.Libm.pow); the reference compilers turn powf(x, 2) into x*x, as here.
# The reference curve's atan2f and DrawCircleV's sinf/cosf follow the
# profile too (docs/SPLINES.md, docs/SINCOSF.md); a value outside it refuses
# the frame. MSAA and VSync do not change the software renderer. LoadTexture
# of a .png is the PNG loader (Surface.load_png). See docs/RLGL.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# showCurve, curveWidth, curveSegments, the four points and curveSelectedPoint (0 none, 1 start, 2 its tangent, 3 end, 4 its tangent).
type Curve is Data:
  Curve{show: Bool, width: F32, segments: U32, start: M.Vector2, start_tangent: M.Vector2, end: M.Vector2, end_tangent: M.Vector2, selected: U32}

type State is Type:
  State{road: Maybe<J.Texture>, curve: Curve}

# DrawTexturedCurve's loop variables: previous, previousTangent, previousV and tangentSet.
type Run is Type:
  Run{frame: J.Frame, previous: M.Vector2, tangent: M.Vector2, v: F32, set: Bool}

def near(mouse: M.Vector2, point: M.Vector2) -> Bool:
  J.Collision.point_circle_for(M.Uncontracted{}, mouse, point, 6.0)

def moved(+on: Bool, +point: M.Vector2, +delta: M.Vector2) -> M.Vector2:
  Bool.pick(M.Vector2, on, M.Vector2.add(point, delta), point)

# A point under the mouse becomes the selected one (the first of start, its tangent, end, its tangent).
def picked(+mouse: M.Vector2, +a: M.Vector2, +b: M.Vector2, +c: M.Vector2, +d: M.Vector2, +selected: U32) -> U32:
  Bool.pick(U32, near(mouse, a), 1, Bool.pick(U32, near(mouse, b), 2, Bool.pick(U32, near(mouse, c), 3, Bool.pick(U32, near(mouse, d), 4, selected))))

# SPACE, the width (at least 2) and the segments (at least 2); without the left button nothing is selected; the selected
# point moves by the mouse delta; then the point under the mouse is selected.
def update.curve(+core: J.Core, curve: Curve) -> Curve:
  Curve{+show, +width, +segments, +start, +start_tangent, +end, +end_tangent, +selected} = curve
  +wider = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_EQUAL()), (width + 2.0 : F32), width)
  +narrower = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_MINUS()), (wider - 2.0 : F32), wider)
  +fewer = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT()), Bool.pick(U32, (segments < 4 : U32), 0, (segments - 2 : U32)), segments)
  +more = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT()), (fewer + 2 : U32), fewer)
  +held = Bool.pick(U32, J.Input.is_mouse_button_down(core, J.MouseButton.MOUSE_BUTTON_LEFT()), selected, 0)
  +delta = J.Input.get_mouse_delta(core)
  +a = moved(U32.is_eq(held, 1), start, delta)
  +b = moved(U32.is_eq(held, 2), start_tangent, delta)
  +c = moved(U32.is_eq(held, 3), end, delta)
  +d = moved(U32.is_eq(held, 4), end_tangent, delta)
  Curve{Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), Bool.not(show), show), Bool.pick(F32, (narrower < 2.0 : F32), 2.0, narrower),
    Bool.pick(U32, (more < 2 : U32), 2, more), a, b, c, d, picked(J.Input.get_mouse_position(core), a, b, c, d, held)}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{road, +curve} = state
  (core, State{road, update.curve(core, curve)})

def corner(frame: J.Frame, +u: F32, +v: F32, point: M.Vector2) -> J.Frame:
  M.Vector2{+x, +y} = point
  J.Rlgl.vertex2f(J.Rlgl.tex_coord2f(frame, u, v), x, y)

# The segment's quad between the previous and the current normals; v += the segment's length/(texRoad.height*2), the road being 64 high.
def segment.quad(+width: F32, +current: M.Vector2, run: Run) -> Run:
  M.Vector2{+cx, +cy} = current
  Run{frame, +previous, +tangent, +v0, +set} = run
  M.Vector2{+px, +py} = previous
  +delta = {M.Vector2{(cx - px : F32), (cy - py : F32)} : M.Vector2}
  +normal = M.Vector2.normalize(M.Vector2{F32.neg((cy - py : F32)), (cx - px : F32)})
  +v = (v0 + M.Vector2.length(delta) / (64.0 * 2.0) : F32)
  +from = Bool.pick(M.Vector2, set, tangent, normal)
  f1 = J.Rlgl.normal3f(J.Rlgl.color4ub(J.Rlgl.begin(frame, 7), 255, 255, 255, 255), 0.0, 0.0, 1.0)
  f2 = corner(corner(f1, 0.0, v0, M.Vector2.add(previous, M.Vector2.scale(from, F32.neg(width)))), 1.0, v0, M.Vector2.add(previous, M.Vector2.scale(from, width)))
  f3 = corner(corner(f2, 1.0, v, M.Vector2.add(current, M.Vector2.scale(normal, width))), 0.0, v, M.Vector2.add(current, M.Vector2.scale(normal, F32.neg(width))))
  Run{J.Rlgl.end(f3), current, normal, v, True{}}

def refused(run: Run) -> Run:
  Run{frame, +previous, +tangent, +v, +set} = run
  Run{J.Frame.refuse(frame), previous, tangent, v, set}

# current = a*start + b*startTangent + c*endTangent + d*end with a = powf(1 - t, 3), b = 3*powf(1 - t, 2)*t,
# c = 3*(1 - t)*powf(t, 2) and d = powf(t, 3).
def segment.at(+t: F32, +curve: Curve, run: Run, cube: Maybe<F32>, rest: Maybe<F32>) -> Run:
  Curve{_, +width, _, +start, +start_tangent, +end, +end_tangent, _} = curve
  M.Vector2{+sx, +sy} = start
  M.Vector2{+tx, +ty} = start_tangent
  M.Vector2{+ex, +ey} = end
  M.Vector2{+ux, +uy} = end_tangent
  match cube rest:
    case Some{+a} Some{+d}: segment.quad(width, M.Vector2{(a * sx + 3.0 * ((1.0 - t) * (1.0 - t)) * t * tx + 3.0 * (1.0 - t) * (t * t) * ux + d * ex : F32),
      (a * sy + 3.0 * ((1.0 - t) * (1.0 - t)) * t * ty + 3.0 * (1.0 - t) * (t * t) * uy + d * ey : F32)}, run)
    case _ _: refused(run)

def segment(+libm: M.Libm, +i: U32, +step: F32, +curve: Curve, run: Run) -> Run:
  segment.at((step * U32.to_f32(i) : F32), curve, run, M.Libm.pow(libm, (1.0 - step * U32.to_f32(i) : F32), 3), M.Libm.pow(libm, (step * U32.to_f32(i) : F32), 3))

# for (i = 1; i <= curveSegments; i++).
def quads(n: Nat, +libm: M.Libm, +i: U32, +step: F32, +curve: Curve, run: Run) -> Run:
  match n:
    case 0n: run
    case 1n+p: quads(p, libm, (i + 1 : U32), step, curve, segment(libm, i, step, curve, run))

# if (CheckCollisionPointCircle(mouse, point, 6)) DrawCircleV(point, 7, YELLOW); DrawCircleV(point, 5, color).
def handle.lit(lit: Bool, +libm: M.Libm, +point: M.Vector2, frame: J.Frame) -> J.Frame:
  match lit:
    case False{}: frame
    case True{}: J.Draw.circle_v_for(libm, frame, point, 7.0, J.Color.YELLOW())

def handle(+libm: M.Libm, +mouse: M.Vector2, +point: M.Vector2, +color: U32, frame: J.Frame) -> J.Frame:
  J.Draw.circle_v_for(libm, handle.lit(near(mouse, point), libm, point, frame), point, 5.0, color)

# if (showCurve) DrawSplineSegmentBezierCubic(start, end, startTangent, endTangent, 2, BLUE), in the example's argument order.
def spline(+libm: M.Libm, +curve: Curve, frame: J.Frame, shown: Bool) -> J.Frame:
  Curve{_, _, _, +start, +start_tangent, +end, +end_tangent, _} = curve
  match shown:
    case False{}: frame
    case True{}: J.Draw.spline_segment_bezier_cubic_for(libm, frame, start, end, start_tangent, end_tangent, 2.0, J.Color.BLUE())

def label(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 10.0, J.Color.DARKGRAY())

def draw.unbound(+core: J.Core, +curve: Curve, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, road) = r
  (core, (State{road, curve}, frame))

# The reference curve, the control lines and points, the usage texts; then the texture back from the frame.
def draw.curve(+libm: M.Libm, +core: J.Core, +curve: Curve, run: Run) -> J.Core & (State & J.Frame):
  Curve{+show, +width, +segments, +start, +start_tangent, +end, +end_tangent, _} = curve
  Run{frame, _, _, _, _} = run
  +mouse = J.Input.get_mouse_position(core)
  f1 = J.Draw.line_v(J.Draw.line_v(spline(libm, curve, frame, show), start, start_tangent, J.Color.SKYBLUE()), start_tangent, end_tangent, J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.4))
  f2 = handle(libm, mouse, start_tangent, J.Color.MAROON(), handle(libm, mouse, start, J.Color.RED(), J.Draw.line_v(f1, end, end_tangent, J.Color.PURPLE())))
  f3 = handle(libm, mouse, end_tangent, J.Color.DARKGREEN(), handle(libm, mouse, end, J.Color.GREEN(), f2))
  f4 = label(J.Text.format("Curve width: %2.0f (Use + and - to adjust)", [J.TextFloat{width}]), 30.0, J.Draw.text(f3, "Drag points to move curve, press SPACE to show/hide base curve", 10.0, 10.0, 10.0, J.Color.DARKGRAY()))
  draw.unbound(core, curve, J.Rlgl.set_texture(label(J.Text.format("Curve segments: %d (Use LEFT and RIGHT to adjust)", [J.TextInt{segments}]), 50.0, f4), None{}))

def bound(r: J.Frame & Maybe<J.Texture>) -> J.Frame:
  (frame, _) = r
  frame

# step = 1.0f/curveSegments; previous = curveStartPosition, no tangent yet, v = 0.
def draw.road(+libm: M.Libm, +core: J.Core, +curve: Curve, frame: J.Frame) -> J.Core & (State & J.Frame):
  Curve{_, _, +segments, +start, _, _, _, _} = curve
  draw.curve(libm, core, curve, quads(U32.to_nat(segments), libm, 1, (1.0 / U32.to_f32(segments) : F32), curve, Run{frame, start, M.Vector2.zero(), 0.0, False{}}))

# DrawTexturedCurve: rlSetTexture(texRoad.id) and the segments' quads.
def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{road, +curve} = state
  match road:
    case None{}: (core, (State{None{}, curve}, J.Frame.refuse(frame)))
    case Some{t}: draw.road(libm, core, curve, bound(J.Rlgl.set_texture(J.Frame.clear_background(frame, J.Color.RAYWHITE()), Some{t})))

# The main loop's body; libm is the profile of the weights' powf, the reference curve and DrawCircleV's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def curve() -> Curve:
  Curve{False{}, 50.0, 24, M.Vector2{80.0, 100.0}, M.Vector2{100.0, 300.0}, M.Vector2{700.0, 350.0}, M.Vector2{600.0, 100.0}, 0}

def filtered(texture: Maybe<J.Texture>) -> Maybe<J.Texture>:
  match texture:
    case None{}: None{}
    case Some{t}: Some{J.Texture.set_filter(t, J.TextureFilter.TEXTURE_FILTER_BILINEAR())}

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{filtered(texture), curve()}))

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# After SetConfigFlags(FLAG_VSYNC_HINT | FLAG_MSAA_4X_HINT) and InitWindow(800, 450): texRoad = LoadTexture("resources/road.png")
# with TEXTURE_FILTER_BILINEAR, the curve's four points, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/road.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.uploaded(core, upload(frame, result))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [textures] example - textured curve", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
