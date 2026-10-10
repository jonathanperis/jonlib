# raylib [shapes] example - rectangle advanced, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_rectangle_advanced.c (zlib/libpng,
# Copyright (c) 2024-2025 Everton Jr. (@evertonse) and Ramon Santamaria (@raysan5));
# see LICENSES/raylib.txt.
#
# The example's DrawRectangleRoundedGradientH: five rectangles with a
# horizontal gradient and a roundness for each side, in rlgl triangles (the
# branch the example compiles: it does not define SUPPORT_QUADS_DRAW_MODE).
# The corners' cosf/sinf follow the libm profile (docs/SINCOSF.md); an
# angle outside it refuses the frame. See docs/RLGL.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{}

def tinted(frame: J.Frame, +color: U32) -> J.Frame:
  J.Rlgl.color4ub(frame, J.Color.red(color), J.Color.green(color), J.Color.blue(color), J.Color.alpha(color))

def point(frame: J.Frame, point: M.Vector2) -> J.Frame:
  M.Vector2{+x, +y} = point
  J.Rlgl.vertex2f(frame, x, y)

def unit.at(cosine: Maybe<F32>, sine: Maybe<F32>) -> Maybe<M.Vector2>:
  match cosine sine:
    case Some{+c} Some{+s}: Some{M.Vector2{c, s}}
    case _ _: None{}

# (cosf(DEG2RAD*angle), sinf(DEG2RAD*angle)).
def unit(+libm: M.Libm, +angle: F32) -> Maybe<M.Vector2>:
  unit.at(M.Libm.cos(libm, (M.Math.DEG2RAD() * angle : F32)), M.Libm.sin(libm, (M.Math.DEG2RAD() * angle : F32)))

# The center, then the points at angle + stepLength and at angle.
def fan.drawn(+cx: F32, +cy: F32, +radius: F32, +color: U32, next: M.Vector2, here: M.Vector2, frame: J.Frame) -> J.Frame:
  M.Vector2{+nc, +ns} = next
  M.Vector2{+hc, +hs} = here
  J.Rlgl.vertex2f(J.Rlgl.vertex2f(J.Rlgl.vertex2f(tinted(frame, color), cx, cy), (cx + nc * radius : F32), (cy + ns * radius : F32)), (cx + hc * radius : F32), (cy + hs * radius : F32))

def fan.at(+cx: F32, +cy: F32, +radius: F32, +color: U32, frame: J.Frame, next: Maybe<M.Vector2>, here: Maybe<M.Vector2>) -> J.Frame:
  match next here:
    case Some{+n} Some{+h}: fan.drawn(cx, cy, radius, color, n, h, frame)
    case _ _: J.Frame.refuse(frame)

# A corner: a triangle per segment, the angle advancing by stepLength.
def fan(n: Nat, +libm: M.Libm, +cx: F32, +cy: F32, +radius: F32, +color: U32, +angle: F32, +step: F32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: fan(p, libm, cx, cy, radius, color, (angle + step : F32), step, fan.at(cx, cy, radius, color, frame, unit(libm, (angle + step : F32)), unit(libm, angle)))

def corner(+libm: M.Libm, +segments: U32, center: M.Vector2, +radius: F32, +color: U32, +angle: F32, frame: J.Frame) -> J.Frame:
  M.Vector2{+cx, +cy} = center
  fan(U32.to_nat(segments), libm, cx, cy, radius, color, angle, (90.0 / U32.to_f32(segments) : F32), frame)

# The 12 points of DrawRectangleRounded's diagram, the 4 corners ([1] upper left, [3] upper right, [5] lower right,
# [7] lower left) and the 5 rectangles ([2] upper, [4] right, [6] bottom, [8] left, [9] middle), two triangles each.
def rounded.drawn(+libm: M.Libm, +segments: U32, +x: F32, +y: F32, +w: F32, +h: F32, +rl: F32, +rr: F32, +left: U32, +right: U32, frame: J.Frame) -> J.Frame:
  +p0 = {M.Vector2{(x + rl : F32), y} : M.Vector2}
  +p1 = {M.Vector2{((x + w) - rr : F32), y} : M.Vector2}
  +p2 = {M.Vector2{(x + w : F32), (y + rr : F32)} : M.Vector2}
  +p3 = {M.Vector2{(x + w : F32), ((y + h) - rr : F32)} : M.Vector2}
  +p4 = {M.Vector2{((x + w) - rr : F32), (y + h : F32)} : M.Vector2}
  +p5 = {M.Vector2{(x + rl : F32), (y + h : F32)} : M.Vector2}
  +p6 = {M.Vector2{x, ((y + h) - rl : F32)} : M.Vector2}
  +p7 = {M.Vector2{x, (y + rl : F32)} : M.Vector2}
  +p8 = {M.Vector2{(x + rl : F32), (y + rl : F32)} : M.Vector2}
  +p9 = {M.Vector2{((x + w) - rr : F32), (y + rr : F32)} : M.Vector2}
  +p10 = {M.Vector2{((x + w) - rr : F32), ((y + h) - rr : F32)} : M.Vector2}
  +p11 = {M.Vector2{(x + rl : F32), ((y + h) - rl : F32)} : M.Vector2}
  f1 = corner(libm, segments, p9, rr, right, 270.0, corner(libm, segments, p8, rl, left, 180.0, J.Rlgl.begin(frame, 4)))
  f2 = corner(libm, segments, p11, rl, left, 90.0, corner(libm, segments, p10, rr, right, 0.0, f1))
  f3 = point(tinted(point(tinted(point(point(tinted(point(point(tinted(f2, left), p0), p8), right), p9), p1), left), p0), right), p9)
  f4 = point(point(point(point(point(point(tinted(f3, right), p9), p10), p3), p2), p9), p3)
  f5 = point(tinted(point(tinted(point(point(tinted(point(point(tinted(f4, left), p11), p5), right), p4), p10), left), p11), right), p4)
  f6 = point(point(point(point(point(point(tinted(f5, left), p7), p6), p11), p8), p7), p11)
  J.Rlgl.end(point(tinted(point(tinted(point(point(tinted(point(point(tinted(f6, left), p8), p11), right), p10), p9), left), p8), right), p10))

# if (radiusRight <= 0.0f && radiusLeft <= 0.0f) return.
def rounded.radii(none: Bool, +libm: M.Libm, +segments: U32, +x: F32, +y: F32, +w: F32, +h: F32, +rl: F32, +rr: F32, +left: U32, +right: U32, frame: J.Frame) -> J.Frame:
  match none:
    case True{}: frame
    case False{}: rounded.drawn(libm, segments, x, y, w, h, rl, rr, left, right, frame)

# The roundness of each side at most 1; the radii from the smaller side, at least 0.
def rounded.sized(+libm: M.Libm, +segments: U32, +x: F32, +y: F32, +w: F32, +h: F32, +roundl: F32, +roundr: F32, +left: U32, +right: U32, frame: J.Frame) -> J.Frame:
  +size = Bool.pick(F32, (w > h : F32), h, w)
  +halfl = ((size * Bool.pick(F32, (roundl >= 1.0 : F32), 1.0, roundl)) / 2.0 : F32)
  +halfr = ((size * Bool.pick(F32, (roundr >= 1.0 : F32), 1.0, roundr)) / 2.0 : F32)
  +rl = Bool.pick(F32, (halfl <= 0.0 : F32), 0.0, halfl)
  +rr = Bool.pick(F32, (halfr <= 0.0 : F32), 0.0, halfr)
  rounded.radii((rr <= 0.0 : F32) && (rl <= 0.0 : F32), libm, segments, x, y, w, h, rl, rr, left, right, frame)

# DrawRectangleRoundedGradientH(rec, roundnessLeft, roundnessRight, segments, left, right): neither side rounded or a
# rectangle below a pixel is DrawRectangleGradientEx(rec, left, left, right, right).
def rounded(plain: Bool, +libm: M.Libm, +segments: U32, +x: F32, +y: F32, +w: F32, +h: F32, +roundl: F32, +roundr: F32, +left: U32, +right: U32, frame: J.Frame) -> J.Frame:
  match plain:
    case True{}: J.Draw.rectangle_gradient_ex(frame, J.Rectangle{x, y, w, h}, left, left, right, right)
    case False{}: rounded.sized(libm, segments, x, y, w, h, roundl, roundr, left, right, frame)

def gradient(+libm: M.Libm, +y: F32, +roundl: F32, +roundr: F32, +left: U32, +right: U32, frame: J.Frame) -> J.Frame:
  +w = (800.0 / 2.0 : F32)
  +h = (450.0 / 6.0 : F32)
  rounded(((roundl <= 0.0 : F32) && (roundr <= 0.0 : F32)) || (w < 1.0 : F32) || (h < 1.0 : F32), libm, 36, (800.0 / 2.0 - w / 2.0 : F32), y, w, h, roundl, roundr, left, right, frame)

# rec = { width/2 - 200, height/2 - 5*(75/2), 400, 75 }; rec.y += rec.height + 1 between the five rectangles.
def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  +y0 = (450.0 / 2.0 - 5.0 * ((450.0 / 6.0) / 2.0) : F32)
  +y1 = (y0 + (450.0 / 6.0 + 1.0) : F32)
  +y2 = (y1 + (450.0 / 6.0 + 1.0) : F32)
  +y3 = (y2 + (450.0 / 6.0 + 1.0) : F32)
  f1 = gradient(libm, y0, 0.8, 0.8, J.Color.BLUE(), J.Color.RED(), J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = gradient(libm, y2, 1.0, 0.5, J.Color.RED(), J.Color.BLUE(), gradient(libm, y1, 0.5, 1.0, J.Color.RED(), J.Color.PINK(), f1))
  (core, (state, gradient(libm, (y3 + (450.0 / 6.0 + 1.0) : F32), 1.0, 0.0, J.Color.BLUE(), J.Color.PINK(), gradient(libm, y3, 0.0, 1.0, J.Color.BLUE(), J.Color.BLACK(), f2))))

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

# The main loop's body; libm is the profile of the corners' cosf/sinf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - rectangle advanced", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
