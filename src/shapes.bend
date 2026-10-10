# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rshapes.c (SUPPORT_QUADS_DRAW_MODE,
# SPLINE_SEGMENT_DIVISIONS 24, no SUPPORT_SPLINE_MITERS); LICENSES/raylib.txt.
# Each shape becomes the rlBegin/rlColor4ub/rlTexCoord2f/rlVertex2f/rlEnd
# sequence rshapes.c issues (src/frame.bend renders it), with rshapes.c's F32
# vertex arithmetic in its order. Textured shapes bind the shapes texture and
# use its rectangle (F.ShapeTexture, F.ShapeUV): by default the 2x8 white block
# (41, 46, 2, 8) of the default font atlas that rcore.c InitWindow selects
# with SetShapesTexture.
#
# A Plan also says whether Jonlib reproduces the draw: sinf/cosf, acosf and
# powf arguments must be verified for the libm profile, C int conversions must
# be defined, and loops are bounded (segments, sides and dashes 1..4096). An
# invalid plan marks the frame undefined; see docs/FRAME.md and docs/RLGL.md.
import Base
import ./frame.bend as F
import ./trig.bend as Trig
import ./checked_angle.bend as CheckedAngle
import ./inverse_trig.bend as InverseTrig
import ./power.bend as Power

type P2 is Data:
  P2{x: F32, y: F32}

type Plan is Data:
  Plan{valid: Bool, commands: +List<F.Command>}

# A point with whether its sinf/cosf argument is reproduced.
type Pt is Data:
  Pt{x: F32, y: F32, ok: Bool}

def Plan.empty() -> Plan:
  Plan{True{}, Nil{}}

def Plan.refused() -> Plan:
  Plan{False{}, Nil{}}

def Plan.with(valid: Bool, commands: +List<F.Command>, plan: Plan) -> Plan:
  Plan{rest_valid, rest} = plan
  Plan{valid && rest_valid, List.append(&2, F.Command, commands, rest)}

def Plan.only(valid: Bool, commands: +List<F.Command>) -> Plan:
  Plan{valid, commands}

def Plan.require(valid: Bool, plan: Plan) -> Plan:
  Plan{rest_valid, commands} = plan
  Plan{valid && rest_valid, commands}

# Draws the plan, or marks the canvas undefined when it is not reproduced.
def Plan.draw(plan: Plan, canvas: F.Canvas) -> F.Canvas:
  Plan{valid, commands} = plan
  F.Canvas.draw(valid, commands, canvas)

# rlSetTexture(shapes) ... rlSetTexture(0) around a textured rlBegin block.
def Plan.textured(+count: U32, plan: Plan) -> Plan:
  Plan{valid, commands} = plan
  Plan{valid, Con{F.ShapeTexture{}, Con{F.Begin{count}, List.append(&2, F.Command, commands, [F.End{}, F.Texture{0}])}}}

def Plan.plain(+count: U32, plan: Plan) -> Plan:
  Plan{valid, commands} = plan
  Plan{valid, Con{F.Begin{count}, List.append(&2, F.Command, commands, [F.End{}])}}

# -----------------------------------------------------------------------------
# Constants, C conversions and the libm contract

# DEG2RAD: (PI/180.0f) with PI = 3.14159265358979323846f.
def deg2rad() -> F32:
  F.float(1016003125)

# C's implicit float-to-int conversion: defined below 2^31 in magnitude.
def int.valid(+x: F32) -> Bool:
  (x >= F32.neg(2147483648.0) : F32) && (x < 2147483648.0 : F32)

def int.of(+x: F32) -> F32:
  F32.trunc(x)

# Apple: fl(DEG2RAD*d) for integral |d| <= 360 except the degrees where
# macOS arm64 sinf/cosf are not correctly rounded (tools/frame_probe.py
# re-verifies every accepted argument against the host).
def trig.apple.degree(+d: F32) -> Bool:
  Bool.not(F32.is_eq(d, 13.0) || F32.is_eq(d, 19.0) || F32.is_eq(d, 22.0) || F32.is_eq(d, 103.0) || F32.is_eq(d, 188.0))

def trig.apple(+arg: F32) -> Bool:
  +d = F32.round((arg / deg2rad() : F32))
  (F32.abs(d) <= 360.0 : F32) && F32.is_eq((deg2rad() * d : F32), arg) && trig.apple.degree(F32.abs(d))

# glibc: normal or zero arguments (glibc's own sinf/cosf, docs/SINCOSF.md).
def trig.gnu(+arg: F32) -> Bool:
  CheckedAngle.normal_or_zero(arg)

def trig.ok(gnu: Bool, +arg: F32) -> Bool:
  match gnu:
    case True{}: trig.gnu(arg)
    case False{}: trig.apple(arg)

def Pt.with(+cx: F32, +cy: F32, +rx: F32, +ry: F32, ok: Bool, values: F32 & F32) -> Pt:
  (cosine, sine) = values
  Pt{(cx + cosine * rx : F32), (cy + sine * ry : F32), ok}

# (center.x + cosf(arg)*rx, center.y + sinf(arg)*ry)
def Pt.at(+gnu: Bool, +cx: F32, +cy: F32, +rx: F32, +ry: F32, +arg: F32) -> Pt:
  Pt.with(cx, cy, rx, ry, trig.ok(gnu, arg), Trig.sincos_for(gnu, arg))

def Pt.ok(+p: Pt) -> Bool:
  Pt{_, _, ok} = p
  ok

def Pt.point(+p: Pt) -> F.Command:
  Pt{x, y, _} = p
  F.Point{x, y}

def P2.of(+x: F32, +y: F32) -> P2:
  P2{x, y}

def P2.point(+p: P2) -> F.Command:
  P2{x, y} = p
  F.Point{x, y}

# -----------------------------------------------------------------------------
# Pixels, lines and rectangles

# DrawPixelV: a 1x1 quad at the position.
def pixel(+x: F32, +y: F32, +color: U32) -> Plan:
  Plan.textured(4, Plan.only(True{}, [F.Color{color}, F.ShapeUV{0}, F.Point{x, y}, F.ShapeUV{2}, F.Point{x, (y + 1.0 : F32)},
    F.ShapeUV{3}, F.Point{(x + 1.0 : F32), (y + 1.0 : F32)}, F.ShapeUV{1}, F.Point{(x + 1.0 : F32), y}]))

# DrawLineV: one RL_LINES segment (untextured).
def line(+x0: F32, +y0: F32, +x1: F32, +y1: F32, +color: U32) -> Plan:
  Plan.plain(2, Plan.only(True{}, [F.Color{color}, F.Point{x0, y0}, F.Point{x1, y1}]))

# The quad of DrawRectanglePro/DrawTriangle: corners a..d with texcoords
# (u0, v0), (u0, v1), (u1, v1), (u1, v0).
def quad(valid: Bool, +color: U32, +a: P2, +b: P2, +c: P2, +d: P2) -> Plan:
  Plan.textured(4, Plan.only(valid, [F.Color{color}, F.ShapeUV{0}, P2.point(a), F.ShapeUV{2}, P2.point(b),
    F.ShapeUV{3}, P2.point(c), F.ShapeUV{1}, P2.point(d)]))

def rectangle.unrotated(+x: F32, +y: F32, +width: F32, +height: F32, +color: U32) -> Plan:
  quad(True{}, color, P2{x, y}, P2{x, (y + height : F32)}, P2{(x + width : F32), (y + height : F32)}, P2{(x + width : F32), y})

def rectangle.rotated(ok: Bool, +x: F32, +y: F32, +width: F32, +height: F32, +dx: F32, +dy: F32, +color: U32, values: F32 & F32) -> Plan:
  (+c, +s) = values
  quad(ok, color, P2{((x + dx * c : F32) - dy * s : F32), ((y + dx * s : F32) + dy * c : F32)},
    P2{((x + dx * c : F32) - (dy + height : F32) * s : F32), ((y + dx * s : F32) + (dy + height : F32) * c : F32)},
    P2{((x + (dx + width : F32) * c : F32) - (dy + height : F32) * s : F32), ((y + (dx + width : F32) * s : F32) + (dy + height : F32) * c : F32)},
    P2{((x + (dx + width : F32) * c : F32) - dy * s : F32), ((y + (dx + width : F32) * s : F32) + dy * c : F32)})

def rectangle.pro.select(flat: Bool, +gnu: Bool, +x: F32, +y: F32, +width: F32, +height: F32, +ox: F32, +oy: F32, +rotation: F32, +color: U32) -> Plan:
  match flat:
    case True{}: rectangle.unrotated((x - ox : F32), (y - oy : F32), width, height, color)
    case False{}:
      +arg = (rotation * deg2rad() : F32)
      rectangle.rotated(trig.ok(gnu, arg), x, y, width, height, F32.neg(ox), F32.neg(oy), color, Trig.sincos_for(gnu, arg))

# DrawRectanglePro: rotation 0.0f (either sign) skips sinf/cosf.
def rectangle.pro(+gnu: Bool, +x: F32, +y: F32, +width: F32, +height: F32, +ox: F32, +oy: F32, +rotation: F32, +color: U32) -> Plan:
  rectangle.pro.select(F32.is_eq(rotation, 0.0), gnu, x, y, width, height, ox, oy, rotation, color)

# DrawRectangleRec / DrawRectangleV: DrawRectanglePro with origin (0, 0), rotation 0.
def rectangle(+x: F32, +y: F32, +width: F32, +height: F32, +color: U32) -> Plan:
  rectangle.unrotated((x - 0.0 : F32), (y - 0.0 : F32), width, height, color)

# DrawRectangleGradientEx: colors per corner (the box rasterizer reads only
# top-left, top-right and bottom-left).
def rectangle.gradient(+x: F32, +y: F32, +width: F32, +height: F32, +top_left: U32, +bottom_left: U32, +bottom_right: U32, +top_right: U32) -> Plan:
  Plan.textured(4, Plan.only(True{}, [F.Color{top_left}, F.ShapeUV{0}, F.Point{x, y}, F.Color{bottom_left}, F.ShapeUV{2},
    F.Point{x, (y + height : F32)}, F.Color{bottom_right}, F.ShapeUV{3}, F.Point{(x + width : F32), (y + height : F32)},
    F.Color{top_right}, F.ShapeUV{1}, F.Point{(x + width : F32), y}]))

# DrawRectangleLines: four RL_LINES offset by 0.5/m0 (rlGetMatrixTransform is
# the identity under OpenGL 1.1, so 0.5).
def rectangle.lines(+x: F32, +y: F32, +width: F32, +height: F32, +color: U32) -> Plan:
  +left = (x + 0.5 : F32)
  +top = (y + 0.5 : F32)
  +right = ((x + width : F32) - 0.5 : F32)
  +bottom = ((y + height : F32) - 0.5 : F32)
  Plan.plain(2, Plan.only(True{}, [F.Color{color}, F.Point{left, top}, F.Point{right, top}, F.Point{right, top}, F.Point{right, bottom},
    F.Point{right, bottom}, F.Point{left, bottom}, F.Point{left, bottom}, F.Point{left, top}]))

def Plan.join(first: Plan, second: Plan) -> Plan:
  Plan{valid, commands} = first
  Plan.with(valid, commands, second)

def rectangle.lines_ex.with(+x: F32, +y: F32, +width: F32, +height: F32, +thick: F32, +color: U32) -> Plan:
  Plan.join(rectangle(x, y, width, thick, color), Plan.join(rectangle(x, ((y - thick : F32) + height : F32), width, thick, color),
    Plan.join(rectangle(x, (y + thick : F32), thick, (height - thick * 2.0 : F32), color),
      rectangle(((x - thick : F32) + width : F32), (y + thick : F32), thick, (height - thick * 2.0 : F32), color))))

# DrawRectangleLinesEx: a thickness above either side becomes half the
# smaller side, then four DrawRectangleRec bands.
def rectangle.lines_ex(+x: F32, +y: F32, +width: F32, +height: F32, +thick: F32, +color: U32) -> Plan:
  +over = (thick > width : F32) || (thick > height : F32)
  +wide = (width >= height : F32)
  +narrow = (width <= height : F32)
  +clamped = Bool.pick(F32, over, Bool.pick(F32, wide, (height / 2.0 : F32), Bool.pick(F32, narrow, (width / 2.0 : F32), thick)), thick)
  rectangle.lines_ex.with(x, y, width, height, clamped, color)

# -----------------------------------------------------------------------------
# Triangles and point lists

# DrawTriangle: the quad (v1, v2, v3, v3).
def triangle(+a: P2, +b: P2, +c: P2, +color: U32) -> Plan:
  quad(True{}, color, a, b, c, c)

# DrawTriangleLines: three RL_LINES.
def triangle.lines(+a: P2, +b: P2, +c: P2, +color: U32) -> Plan:
  Plan.plain(2, Plan.only(True{}, [F.Color{color}, P2.point(a), P2.point(b), P2.point(b), P2.point(c), P2.point(c), P2.point(a)]))

def at_least(n: Nat, points: +List<P2>) -> Bool:
  match n points:
    case 0n _: True{}
    case _ Nil{}: False{}
    case 1n+k Con{_, rest}: at_least(k, rest)

def fan.one(more: +List<P2>, +first: P2, +b: P2) -> +List<F.Command>:
  match more:
    case Nil{}: Nil{}
    case Con{+c, _}: [F.ShapeUV{0}, P2.point(first), F.ShapeUV{2}, P2.point(b), F.ShapeUV{3}, P2.point(c),
      F.ShapeUV{1}, P2.point(c)]

def fan.loop(rest: +List<P2>, +first: P2) -> +List<F.Command>:
  match rest:
    case Nil{}: Nil{}
    case Con{+b, +more}: List.append(&2, F.Command, fan.one(more, first, b), fan.loop(more, first))

def fan.points(points: +List<P2>, +color: U32) -> Plan:
  match points:
    case Con{+first, +rest}: Plan.textured(4, Plan.only(True{}, Con{F.Color{color}, fan.loop(rest, first)}))
    case Nil{}: Plan.empty()

def fan.counted(enough: Bool, points: +List<P2>, +color: U32) -> Plan:
  match enough:
    case False{}: Plan.empty()
    case True{}: fan.points(points, color)

# DrawTriangleFan: with at least three points, quads (p0, pi, pi+1, pi+1);
# the color is set once, before the first.
def fan(+points: +List<P2>, +color: U32) -> Plan:
  fan.counted(at_least(3n, points), points, color)

def strip.triangle(even: Bool, +a: P2, +b: P2, +c: P2) -> +List<F.Command>:
  match even:
    case True{}: [P2.point(c), P2.point(a), P2.point(b)]
    case False{}: [P2.point(c), P2.point(b), P2.point(a)]

def strip.loop(rest: +List<P2>, +even: Bool, +a: P2, +b: P2) -> +List<F.Command>:
  match rest:
    case Nil{}: Nil{}
    case Con{+c, more}: List.append(&2, F.Command, strip.triangle(even, a, b, c), strip.loop(more, Bool.not(even), b, c))

def strip.points(points: +List<P2>, +color: U32) -> Plan:
  match points:
    case Con{+a, Con{+b, rest}}: Plan.plain(3, Plan.only(True{}, Con{F.Color{color}, strip.loop(rest, True{}, a, b)}))
    case _: Plan.empty()

def strip.counted(enough: Bool, points: +List<P2>, +color: U32) -> Plan:
  match enough:
    case False{}: Plan.empty()
    case True{}: strip.points(points, color)

# DrawTriangleStrip: untextured RL_TRIANGLES (i, i-2, i-1) for even i and
# (i, i-1, i-2) for odd i; the color is set once, before the first.
def strip(+points: +List<P2>, +color: U32) -> Plan:
  strip.counted(at_least(3n, points), points, color)

def line_strip.loop(rest: +List<P2>, +a: P2) -> +List<F.Command>:
  match rest:
    case Nil{}: Nil{}
    case Con{+b, more}: Con{P2.point(a), Con{P2.point(b), line_strip.loop(more, b)}}

def line_strip.points(points: +List<P2>, +color: U32) -> Plan:
  match points:
    case Con{+a, rest}: Plan.plain(2, Plan.only(True{}, Con{F.Color{color}, line_strip.loop(rest, a)}))
    case Nil{}: Plan.empty()

def line_strip.counted(enough: Bool, points: +List<P2>, +color: U32) -> Plan:
  match enough:
    case False{}: Plan.empty()
    case True{}: line_strip.points(points, color)

# DrawLineStrip: RL_LINES (p0, p1), (p1, p2), ... with at least two points.
def line_strip(+points: +List<P2>, +color: U32) -> Plan:
  line_strip.counted(at_least(2n, points), points, color)

def line_ex.drawn(drawn: Bool, +sx: F32, +sy: F32, +ex: F32, +ey: F32, +dx: F32, +dy: F32, +length: F32, +thick: F32, +color: U32) -> Plan:
  match drawn:
    case False{}: Plan.empty()
    case True{}:
      +scale = (thick / (2.0 * length : F32) : F32)
      +rx = (F32.neg(scale) * dy : F32)
      +ry = (scale * dx : F32)
      strip([P2{(sx - rx : F32), (sy - ry : F32)}, P2{(sx + rx : F32), (sy + ry : F32)}, P2{(ex - rx : F32), (ey - ry : F32)},
        P2{(ex + rx : F32), (ey + ry : F32)}], color)

# DrawLineEx: a four-point DrawTriangleStrip around the segment.
def line_ex(+sx: F32, +sy: F32, +ex: F32, +ey: F32, +thick: F32, +color: U32) -> Plan:
  +dx = (ex - sx : F32)
  +dy = (ey - sy : F32)
  +length = F32.sqrt((dx * dx + dy * dy : F32))
  line_ex.drawn((length > 0.0 : F32) && (thick > 0.0 : F32), sx, sy, ex, ey, dx, dy, length, thick, color)

# -----------------------------------------------------------------------------
# Segment counts. lm is the libm profile (0 Apple, 1 glibc 2.39, 2 glibc 2.41).

def gnu.of(+lm: U32) -> Bool:
  Bool.not(U32.is_eq(lm, 0))

# 2*PI as rshapes.c evaluates it (6.2831855f).
def two_pi() -> F32:
  F.float(1086918619)

# (int)value, or None when the conversion is undefined.
def int.maybe(+value: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, int.valid(value), Some{int.of(value)}, None{})

def segments.bounded(+n: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, (n <= 4096.0 : F32), Some{n}, None{})

# rshapes.c's error-rate estimate (SMOOTH_CIRCLE_ERROR_RATE 0.5f): th =
# acosf(2*powf(1 - 0.5f/radius, 2) - 1). Clang and GCC compile powf(x, 2) as
# x*x; acosf is glibc 2.39's Sun acosf (M.Libm.acos), so only that profile
# estimates (None, refused, for the others and outside [-1, 1]).
def estimate.th(+lm: U32, +radius: F32) -> Maybe<F32>:
  +x = (1.0 - (0.5 / radius : F32) : F32)
  Bool.pick(Maybe<F32>, U32.is_eq(lm, 1), InverseTrig.acos(((2.0 * (x * x : F32) : F32) - 1.0 : F32)), None{})

# (int)((endAngle - startAngle)*ceilf(2*PI/th)/360)
def estimate.arc(th: Maybe<F32>, +span: F32) -> Maybe<F32>:
  match th:
    case None{}: None{}
    case Some{+t}: int.maybe((((span * F32.ceil((two_pi() / t : F32)) : F32) / 360.0 : F32)))

# (int)(ceilf(2*PI/th)/divisor) for the rounded rectangle corners.
def estimate.corner(th: Maybe<F32>, +divisor: F32) -> Maybe<F32>:
  match th:
    case None{}: None{}
    case Some{+t}: int.maybe((F32.ceil((two_pi() / t : F32)) / divisor : F32))

# An estimate of 0 or less takes the fallback; more than 4096 is refused.
def estimate.floor(value: Maybe<F32>, +fallback: F32) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{+n}: segments.bounded(Bool.pick(F32, (n <= 0.0 : F32), fallback, n))

def segments.pick(estimate: Bool, +lm: U32, +radius: F32, +span: F32, +minimum: F32, +segments: F32) -> Maybe<F32>:
  match estimate:
    case False{}: segments.bounded(segments)
    case True{}: estimate.floor(estimate.arc(estimate.th(lm, radius), span), minimum)

def segments.valid(valid: Bool, +lm: U32, +radius: F32, +span: F32, +minimum: F32, +segments: F32) -> Maybe<F32>:
  match valid:
    case False{}: None{}
    case True{}: segments.pick((int.of(segments) < int.of(minimum) : F32), lm, radius, span, int.of(minimum), int.of(segments))

# The segment count of an arc: the C int parameter when at least
# (int)ceilf(span/90), else the estimate; None (refused) for undefined int
# conversions, an estimate the profile lacks or more than 4096 segments.
def segments.resolve(+lm: U32, +radius: F32, +span: F32, +segments: F32) -> Maybe<F32>:
  +minimum = F32.ceil((span / 90.0 : F32))
  segments.valid(int.valid(minimum) && int.valid(segments), lm, radius, span, minimum, segments)

# -----------------------------------------------------------------------------
# Circles, sectors, rings, ellipses and polygons (sinf/cosf)

def sector.quad(+gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +step: F32, +color: U32, plan: Plan) -> Plan:
  +p2 = Pt.at(gnu, cx, cy, r, r, (deg2rad() * (angle + step * 2.0 : F32) : F32))
  +p1 = Pt.at(gnu, cx, cy, r, r, (deg2rad() * (angle + step : F32) : F32))
  +p0 = Pt.at(gnu, cx, cy, r, r, (deg2rad() * angle : F32))
  Plan.with(Pt.ok(p2) && Pt.ok(p1) && Pt.ok(p0), [F.Color{color}, F.ShapeUV{0}, F.Point{cx, cy}, F.ShapeUV{1}, Pt.point(p2),
    F.ShapeUV{3}, Pt.point(p1), F.ShapeUV{2}, Pt.point(p0)], plan)

def sector.odd(odd: Bool, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match odd:
    case False{}: Plan.empty()
    case True{}:
      +p1 = Pt.at(gnu, cx, cy, r, r, (deg2rad() * (angle + step : F32) : F32))
      +p0 = Pt.at(gnu, cx, cy, r, r, (deg2rad() * angle : F32))
      Plan.only(Pt.ok(p1) && Pt.ok(p0), [F.Color{color}, F.ShapeUV{0}, F.Point{cx, cy}, F.ShapeUV{3}, Pt.point(p1),
        F.ShapeUV{2}, Pt.point(p0), F.ShapeUV{1}, F.Point{cx, cy}])

# Quads of two segments, then the odd last piece (DrawCircleSector and the
# rounded rectangle corners).
def sector.quads(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +step: F32, +color: U32, +odd: Bool) -> Plan:
  match n:
    case 0n: sector.odd(odd, gnu, cx, cy, r, angle, step, color)
    case 1n+k: sector.quad(gnu, cx, cy, r, angle, step, color, sector.quads(k, gnu, cx, cy, r, (angle + step * 2.0 : F32), step, color, odd))

def sector.pieces(+gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +step: F32, +segments: F32, +color: U32) -> Plan:
  +count = F32.to_u32(segments)
  sector.quads(U32.to_nat((count / 2 : U32)), gnu, cx, cy, r, start, step, color, U32.is_eq((count % 2 : U32), 1))

def sector.drawn(count: Maybe<F32>, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +color: U32) -> Plan:
  match count:
    case None{}: Plan.refused()
    case Some{+segments}: Plan.textured(4, sector.pieces(gnu, cx, cy, r, start, ((end - start : F32) / segments : F32), segments, color))

def sector.ordered(+lm: U32, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  sector.drawn(segments.resolve(lm, r, (end - start : F32), segments), gnu.of(lm), cx, cy, r, start, end, color)

def sector.distinct(same: Bool, +lm: U32, +cx: F32, +cy: F32, +radius: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match same:
    case True{}: Plan.empty()
    case False{}:
      +r = Bool.pick(F32, (radius <= 0.0 : F32), 0.1, radius)
      +swap = (end < start : F32)
      sector.ordered(lm, cx, cy, r, Bool.pick(F32, swap, end, start), Bool.pick(F32, swap, start, end), segments, color)

# DrawCircleSector (quads of two segments, then an odd last piece).
def sector(+lm: U32, +cx: F32, +cy: F32, +radius: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  sector.distinct(F32.is_eq(start, end), lm, cx, cy, radius, start, end, segments, color)

# A profile with the given sinf/cosf kernel that never estimates (circles use
# 36 segments, above every minimum).
def lm.of(+gnu: Bool) -> U32:
  Bool.pick(U32, gnu, 2, 0)

# DrawCircleV: DrawCircleSector(center, radius, 0, 360, 36).
def circle(+gnu: Bool, +cx: F32, +cy: F32, +radius: F32, +color: U32) -> Plan:
  sector(lm.of(gnu), cx, cy, radius, 0.0, 360.0, 36.0, color)

def circle_lines.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +degrees: F32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +a = Pt.at(gnu, cx, cy, r, r, (deg2rad() * degrees : F32))
      +b = Pt.at(gnu, cx, cy, r, r, (deg2rad() * (degrees + 10.0 : F32) : F32))
      Plan.with(Pt.ok(a) && Pt.ok(b), [Pt.point(a), Pt.point(b)], circle_lines.loop(k, gnu, cx, cy, r, (degrees + 10.0 : F32)))

def Plan.prefix(command: F.Command, plan: Plan) -> Plan:
  Plan{valid, commands} = plan
  Plan{valid, Con{command, commands}}

# DrawCircleLinesV: 36 RL_LINES every 10 degrees, the color set once.
def circle_lines(+gnu: Bool, +cx: F32, +cy: F32, +radius: F32, +color: U32) -> Plan:
  Plan.plain(2, Plan.prefix(F.Color{color}, circle_lines.loop(36n, gnu, cx, cy, radius, 0.0)))

def ellipse.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +rx: F32, +ry: F32, +degrees: F32, +color: U32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +b = Pt.at(gnu, cx, cy, rx, ry, (deg2rad() * (degrees + 10.0 : F32) : F32))
      +a = Pt.at(gnu, cx, cy, rx, ry, (deg2rad() * degrees : F32))
      Plan.with(Pt.ok(a) && Pt.ok(b), [F.Color{color}, F.Point{cx, cy}, Pt.point(b), Pt.point(a)],
        ellipse.loop(k, gnu, cx, cy, rx, ry, (degrees + 10.0 : F32), color))

# DrawEllipseV: 36 untextured triangles (center, i + 10, i).
def ellipse(+gnu: Bool, +cx: F32, +cy: F32, +rx: F32, +ry: F32, +color: U32) -> Plan:
  Plan.plain(3, ellipse.loop(36n, gnu, cx, cy, rx, ry, 0.0, color))

def ellipse_lines.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +rx: F32, +ry: F32, +degrees: F32, +color: U32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +b = Pt.at(gnu, cx, cy, rx, ry, (deg2rad() * (degrees + 10.0 : F32) : F32))
      +a = Pt.at(gnu, cx, cy, rx, ry, (deg2rad() * degrees : F32))
      Plan.with(Pt.ok(a) && Pt.ok(b), [F.Color{color}, Pt.point(b), Pt.point(a)], ellipse_lines.loop(k, gnu, cx, cy, rx, ry, (degrees + 10.0 : F32), color))

# DrawEllipseLinesV: 36 RL_LINES (i + 10, i).
def ellipse_lines(+gnu: Bool, +cx: F32, +cy: F32, +rx: F32, +ry: F32, +color: U32) -> Plan:
  Plan.plain(2, ellipse_lines.loop(36n, gnu, cx, cy, rx, ry, 0.0, color))

def gradient.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +degrees: F32, +inner: U32, +outer: U32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +b = Pt.at(gnu, cx, cy, r, r, (deg2rad() * (degrees + 10.0 : F32) : F32))
      +a = Pt.at(gnu, cx, cy, r, r, (deg2rad() * degrees : F32))
      Plan.with(Pt.ok(a) && Pt.ok(b), [F.Color{inner}, F.Point{cx, cy}, F.Color{outer}, Pt.point(b), F.Color{outer}, Pt.point(a)],
        gradient.loop(k, gnu, cx, cy, r, (degrees + 10.0 : F32), inner, outer))

# DrawCircleGradient: 36 untextured triangles, inner color at the center.
def circle_gradient(+gnu: Bool, +cx: F32, +cy: F32, +radius: F32, +inner: U32, +outer: U32) -> Plan:
  Plan.plain(3, gradient.loop(36n, gnu, cx, cy, radius, 0.0, inner, outer))

def sector_lines.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match n:
    case 0n:
      +p = Pt.at(gnu, cx, cy, r, r, (deg2rad() * angle : F32))
      Plan.only(Pt.ok(p), [F.Color{color}, F.Point{cx, cy}, Pt.point(p)])
    case 1n+k:
      +a = Pt.at(gnu, cx, cy, r, r, (deg2rad() * angle : F32))
      +b = Pt.at(gnu, cx, cy, r, r, (deg2rad() * (angle + step : F32) : F32))
      Plan.with(Pt.ok(a) && Pt.ok(b), [F.Color{color}, Pt.point(a), Pt.point(b)], sector_lines.loop(k, gnu, cx, cy, r, (angle + step : F32), step, color))

def sector_lines.drawn(count: Maybe<F32>, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +color: U32) -> Plan:
  match count:
    case None{}: Plan.refused()
    case Some{+segments}:
      +first = Pt.at(gnu, cx, cy, r, r, (deg2rad() * start : F32))
      Plan.plain(2, Plan.with(Pt.ok(first), [F.Color{color}, F.Point{cx, cy}, Pt.point(first)],
        sector_lines.loop(U32.to_nat(F32.to_u32(segments)), gnu, cx, cy, r, start, ((end - start : F32) / segments : F32), color)))

def sector_lines.ordered(+lm: U32, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  sector_lines.drawn(segments.resolve(lm, r, (end - start : F32), segments), gnu.of(lm), cx, cy, r, start, end, color)

def sector_lines.distinct(same: Bool, +lm: U32, +cx: F32, +cy: F32, +radius: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match same:
    case True{}: Plan.empty()
    case False{}:
      +r = Bool.pick(F32, (radius <= 0.0 : F32), 0.1, radius)
      +swap = (end < start : F32)
      sector_lines.ordered(lm, cx, cy, r, Bool.pick(F32, swap, end, start), Bool.pick(F32, swap, start, end), segments, color)

# DrawCircleSectorLines: cap lines from the center plus one line per segment.
def sector_lines(+lm: U32, +cx: F32, +cy: F32, +radius: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  sector_lines.distinct(F32.is_eq(start, end), lm, cx, cy, radius, start, end, segments, color)

def ring.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +next = (deg2rad() * (angle + step : F32) : F32)
      +here = (deg2rad() * angle : F32)
      +a = Pt.at(gnu, cx, cy, outer, outer, here)
      +b = Pt.at(gnu, cx, cy, inner, inner, here)
      +c = Pt.at(gnu, cx, cy, inner, inner, next)
      +d = Pt.at(gnu, cx, cy, outer, outer, next)
      Plan.with(Pt.ok(a) && Pt.ok(b) && Pt.ok(c) && Pt.ok(d), [F.Color{color}, F.ShapeUV{2}, Pt.point(a), F.ShapeUV{0}, Pt.point(b),
        F.ShapeUV{1}, Pt.point(c), F.ShapeUV{3}, Pt.point(d)], ring.loop(k, gnu, cx, cy, inner, outer, (angle + step : F32), step, color))

def ring.kind(full: Bool, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match full:
    case True{}: sector(lm, cx, cy, outer, start, end, segments, color)
    case False{}: Plan.textured(4, ring.loop(U32.to_nat(F32.to_u32(segments)), gnu.of(lm), cx, cy, inner, outer, start, ((end - start : F32) / segments : F32), color))

def ring.drawn(count: Maybe<F32>, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +color: U32) -> Plan:
  match count:
    case None{}: Plan.refused()
    case Some{+segments}: ring.kind((inner <= 0.0 : F32), lm, cx, cy, inner, outer, start, end, segments, color)

def ring.ordered(+lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  ring.drawn(segments.resolve(lm, outer, (end - start : F32), segments), lm, cx, cy, inner, outer, start, end, color)

def ring_lines.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match n:
    case 0n:
      +here = (deg2rad() * angle : F32)
      +a = Pt.at(gnu, cx, cy, outer, outer, here)
      +b = Pt.at(gnu, cx, cy, inner, inner, here)
      Plan.only(Pt.ok(a) && Pt.ok(b), [F.Color{color}, Pt.point(a), Pt.point(b)])
    case 1n+k:
      +next = (deg2rad() * (angle + step : F32) : F32)
      +here = (deg2rad() * angle : F32)
      +a = Pt.at(gnu, cx, cy, outer, outer, here)
      +b = Pt.at(gnu, cx, cy, outer, outer, next)
      +c = Pt.at(gnu, cx, cy, inner, inner, here)
      +d = Pt.at(gnu, cx, cy, inner, inner, next)
      Plan.with(Pt.ok(a) && Pt.ok(b) && Pt.ok(c) && Pt.ok(d), [F.Color{color}, Pt.point(a), Pt.point(b), Pt.point(c), Pt.point(d)],
        ring_lines.loop(k, gnu, cx, cy, inner, outer, (angle + step : F32), step, color))

def ring_lines.caps(+gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +step: F32, +segments: F32, +color: U32) -> Plan:
  +here = (deg2rad() * start : F32)
  +a = Pt.at(gnu, cx, cy, outer, outer, here)
  +b = Pt.at(gnu, cx, cy, inner, inner, here)
  Plan.plain(2, Plan.with(Pt.ok(a) && Pt.ok(b), [F.Color{color}, Pt.point(a), Pt.point(b)],
    ring_lines.loop(U32.to_nat(F32.to_u32(segments)), gnu, cx, cy, inner, outer, start, step, color)))

def ring_lines.kind(full: Bool, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match full:
    case True{}: sector_lines(lm, cx, cy, outer, start, end, segments, color)
    case False{}: ring_lines.caps(gnu.of(lm), cx, cy, inner, outer, start, ((end - start : F32) / segments : F32), segments, color)

def ring_lines.drawn(count: Maybe<F32>, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +color: U32) -> Plan:
  match count:
    case None{}: Plan.refused()
    case Some{+segments}: ring_lines.kind((inner <= 0.0 : F32), lm, cx, cy, inner, outer, start, end, segments, color)

def ring.select(lines: Bool, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match lines:
    case False{}: ring.ordered(lm, cx, cy, inner, outer, start, end, segments, color)
    case True{}: ring_lines.drawn(segments.resolve(lm, outer, (end - start : F32), segments), lm, cx, cy, inner, outer, start, end, color)

# DrawRing and DrawRingLines order their radii (outer below inner swaps them,
# a non-positive outer becoming 0.1) and their angles.
def ring.distinct(same: Bool, +lines: Bool, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match same:
    case True{}: Plan.empty()
    case False{}:
      +flip = (outer < inner : F32)
      +big = Bool.pick(F32, flip, inner, outer)
      +swap = (end < start : F32)
      ring.select(lines, lm, cx, cy, Bool.pick(F32, flip, outer, inner), Bool.pick(F32, flip && (big <= 0.0 : F32), 0.1, big),
        Bool.pick(F32, swap, end, start), Bool.pick(F32, swap, start, end), segments, color)

# DrawRing: quads between the radii; a non-positive inner radius draws
# DrawCircleSector with the outer one.
def ring(+lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  ring.distinct(F32.is_eq(start, end), False{}, lm, cx, cy, inner, outer, start, end, segments, color)

# DrawRingLines: cap lines at both ends and the outer and inner arcs; a
# non-positive inner radius draws DrawCircleSectorLines with the outer one.
def ring_lines(+lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  ring.distinct(F32.is_eq(start, end), True{}, lm, cx, cy, inner, outer, start, end, segments, color)

def poly.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +next = (angle + step : F32)
      +a = Pt.at(gnu, cx, cy, r, r, angle)
      +b = Pt.at(gnu, cx, cy, r, r, next)
      Plan.with(Pt.ok(a) && Pt.ok(b), [F.Color{color}, F.ShapeUV{0}, F.Point{cx, cy}, F.ShapeUV{2}, Pt.point(a),
        F.ShapeUV{1}, Pt.point(b), F.ShapeUV{3}, Pt.point(a)], poly.loop(k, gnu, cx, cy, r, next, step, color))

def poly.sides(+sides: F32) -> F32:
  Bool.pick(F32, (sides < 3.0 : F32), 3.0, sides)

def poly.drawn(valid: Bool, +gnu: Bool, +cx: F32, +cy: F32, +sides: F32, +r: F32, +rotation: F32, +color: U32) -> Plan:
  match valid:
    case False{}: Plan.refused()
    case True{}: Plan.textured(4, poly.loop(U32.to_nat(F32.to_u32(sides)), gnu, cx, cy, r, (rotation * deg2rad() : F32),
      ((360.0 / sides : F32) * deg2rad() : F32), color))

# DrawPoly: sides < 3 become 3; quads (center, p(a), p(a + step), p(a)).
def poly(+gnu: Bool, +cx: F32, +cy: F32, +sides: F32, +radius: F32, +rotation: F32, +color: U32) -> Plan:
  +count = poly.sides(int.of(sides))
  poly.drawn(int.valid(sides) && (count <= 4096.0 : F32), gnu, cx, cy, count, radius, rotation, color)

def poly_lines.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +a = Pt.at(gnu, cx, cy, r, r, angle)
      +b = Pt.at(gnu, cx, cy, r, r, (angle + step : F32))
      Plan.with(Pt.ok(a) && Pt.ok(b), [F.Color{color}, Pt.point(a), Pt.point(b)], poly_lines.loop(k, gnu, cx, cy, r, (angle + step : F32), step, color))

def poly_lines.drawn(valid: Bool, +gnu: Bool, +cx: F32, +cy: F32, +sides: F32, +r: F32, +rotation: F32, +color: U32) -> Plan:
  match valid:
    case False{}: Plan.refused()
    case True{}: Plan.plain(2, poly_lines.loop(U32.to_nat(F32.to_u32(sides)), gnu, cx, cy, r, (rotation * deg2rad() : F32),
      ((360.0 / sides : F32) * deg2rad() : F32), color))

# DrawPolyLines: RL_LINES (p(a), p(a + step)) per side.
def poly_lines(+gnu: Bool, +cx: F32, +cy: F32, +sides: F32, +radius: F32, +rotation: F32, +color: U32) -> Plan:
  +count = poly.sides(int.of(sides))
  poly_lines.drawn(int.valid(sides) && (count <= 4096.0 : F32), gnu, cx, cy, count, radius, rotation, color)

# -----------------------------------------------------------------------------
# DrawPolyLinesEx

def poly_ex.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +inner: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +next = (angle + step : F32)
      +a = Pt.at(gnu, cx, cy, r, r, angle)
      +b = Pt.at(gnu, cx, cy, inner, inner, angle)
      +c = Pt.at(gnu, cx, cy, inner, inner, next)
      +d = Pt.at(gnu, cx, cy, r, r, next)
      Plan.with(Pt.ok(a) && Pt.ok(b) && Pt.ok(c) && Pt.ok(d), [F.Color{color}, F.ShapeUV{2}, Pt.point(a), F.ShapeUV{0}, Pt.point(b),
        F.ShapeUV{3}, Pt.point(c), F.ShapeUV{1}, Pt.point(d)], poly_ex.loop(k, gnu, cx, cy, r, inner, next, step, color))

def cosine(values: F32 & F32) -> F32:
  (c, _) = values
  c

# The inner radius radius - lineThick*cosf(DEG2RAD*exteriorAngle/2) (the
# exterior angle is already in radians, so the argument is small). Apple:
# every argument of sides 3..4096 (tools/rlgl_probe.py checks them all
# against the host cosf); glibc: normal arguments within one turn.
def poly_ex.drawn(valid: Bool, +gnu: Bool, +cx: F32, +cy: F32, +sides: F32, +r: F32, +rotation: F32, +thick: F32, +color: U32) -> Plan:
  match valid:
    case False{}: Plan.refused()
    case True{}:
      +exterior = ((360.0 / sides : F32) * deg2rad() : F32)
      +arg = ((deg2rad() * exterior : F32) / 2.0 : F32)
      +inner = (r - (thick * cosine(Trig.sincos_for(gnu, arg)) : F32) : F32)
      Plan.textured(4, Plan.require(Bool.not(gnu) || trig.gnu(arg), poly_ex.loop(U32.to_nat(F32.to_u32(sides)), gnu, cx, cy, r, inner,
        (rotation * deg2rad() : F32), exterior, color)))

# DrawPolyLinesEx: sides < 3 become 3; quads between the radius and the inner
# radius per side.
def poly_lines_ex(+gnu: Bool, +cx: F32, +cy: F32, +sides: F32, +radius: F32, +rotation: F32, +thick: F32, +color: U32) -> Plan:
  +count = poly.sides(int.of(sides))
  poly_ex.drawn(int.valid(sides) && (count <= 4096.0 : F32), gnu, cx, cy, count, radius, rotation, thick, color)

# -----------------------------------------------------------------------------
# Ribbons: DrawTriangleStrip around a polyline, the way DrawLineBezier and the
# spline segments build it. For each next point n after the current c,
# (dx, dy) = n - c and size = 0.5*thick/sqrtf(dx*dx + dy*dy); the strip takes
# n + (dy, -dx)*size and n - (dy, -dx)*size, after the same two around the
# first current point (with the first side, or a carried one).

type Side is Data:
  Side{dx: F32, dy: F32, size: F32}

def side.of(+c: P2, +n: P2, +thick: F32) -> Side:
  P2{cx, cy} = c
  P2{nx, ny} = n
  +dy = (ny - cy : F32)
  +dx = (nx - cx : F32)
  Side{dx, dy, ((0.5 * thick : F32) / F32.sqrt((dx * dx + dy * dy : F32)) : F32)}

def side.left(+p: P2, +s: Side) -> P2:
  P2{x, y} = p
  Side{dx, dy, size} = s
  P2{(x + dy * size : F32), (y - dx * size : F32)}

def side.right(+p: P2, +s: Side) -> P2:
  P2{x, y} = p
  Side{dx, dy, size} = s
  P2{(x - dy * size : F32), (y + dx * size : F32)}

def ribbon.cons(+a: P2, +b: P2, rest: +List<P2> & Side) -> +List<P2> & Side:
  (list, side) = rest
  (Con{a, Con{b, list}}, side)

def ribbon.rest(nexts: +List<P2>, +current: P2, +thick: F32, +last: Side) -> +List<P2> & Side:
  match nexts:
    case Nil{}: (Nil{}, last)
    case Con{+n, more}:
      +s = side.of(current, n, thick)
      ribbon.cons(side.left(n, s), side.right(n, s), ribbon.rest(more, n, thick, s))

def P2.head(points: +List<P2>, +fallback: P2) -> P2:
  match points:
    case Con{+p, _}: p
    case Nil{}: fallback

# The strip around current then the next points, the first two points from the
# first next point's side; with the last side.
def ribbon(+current: P2, +nexts: +List<P2>, +thick: F32) -> +List<P2> & Side:
  +first = side.of(current, P2.head(nexts, current), thick)
  ribbon.cons(side.left(current, first), side.right(current, first), ribbon.rest(nexts, current, thick, first))

# The same with the first two points from a carried side (DrawSplineBasis and
# DrawSplineCatmullRom after their first segment).
def ribbon.carried(+current: P2, +carried: Side, nexts: +List<P2>, +thick: F32) -> +List<P2> & Side:
  ribbon.cons(side.left(current, carried), side.right(current, carried), ribbon.rest(nexts, current, thick, carried))

def ribbon.strip(result: +List<P2> & Side, +color: U32) -> Plan:
  (points, _) = result
  strip(points, color)

# -----------------------------------------------------------------------------
# DrawLineBezier

# EaseCubicInOut(t, b, c, d)
def ease(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  +q = (t / (0.5 * d : F32) : F32)
  +r = (q - 2.0 : F32)
  Bool.pick(F32, (q < 1.0 : F32), (((((0.5 * c : F32) * q : F32) * q : F32) * q : F32) + b : F32),
    (((0.5 * c : F32) * (((r * r : F32) * r : F32) + 2.0 : F32) : F32) + b : F32))

def bezier.points(n: Nat, +i: F32, +px: F32, +sx: F32, +sy: F32, +ex: F32, +ey: F32) -> +List<P2>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      +x = (px + ((ex - sx : F32) / 24.0 : F32) : F32)
      Con{P2{x, ease(i, sy, (ey - sy : F32), 24.0)}, bezier.points(k, (i + 1.0 : F32), x, sx, sy, ex, ey)}

# DrawLineBezier: 24 eased steps (x stepped by (end.x - start.x)/24, y by
# EaseCubicInOut) as a 50-point DrawTriangleStrip.
def line_bezier(+sx: F32, +sy: F32, +ex: F32, +ey: F32, +thick: F32, +color: U32) -> Plan:
  ribbon.strip(ribbon(P2{sx, sy}, bezier.points(24n, 1.0, sx, sx, sy, ex, ey), thick), color)

# -----------------------------------------------------------------------------
# DrawLineDashed

# Dashes while the distance travelled is below the length; running out of
# the 4096 steps (the C loop may not end) is refused.
def dashed.loop(n: Nat, more: Bool, +cx: F32, +cy: F32, +done: F32, +sx: F32, +sy: F32, +dirx: F32, +diry: F32, +length: F32, +dash: F32, +space: F32) -> Plan:
  match n more:
    case _ False{}: Plan.empty()
    case 0n True{}: Plan.refused()
    case 1n+k True{}:
      +reach = (done + dash : F32)
      +stop = Bool.pick(F32, (reach > length : F32), length, reach)
      +next = (stop + space : F32)
      Plan.with(True{}, [F.Point{cx, cy}, F.Point{(sx + stop * dirx : F32), (sy + stop * diry : F32)}],
        dashed.loop(k, (next < length : F32), (sx + next * dirx : F32), (sy + next * diry : F32), next, sx, sy, dirx, diry, length, dash, space))

def dashed.drawn(solid: Bool, +sx: F32, +sy: F32, +ex: F32, +ey: F32, +dx: F32, +dy: F32, +length: F32, +dash: F32, +space: F32, +color: U32) -> Plan:
  match solid:
    case True{}: line(sx, sy, ex, ey, color)
    case False{}:
      +inv = (1.0 / length : F32)
      Plan.plain(2, Plan.prefix(F.Color{color}, dashed.loop(4096n, (0.0 < length : F32), sx, sy, 0.0, sx, sy, (dx * inv : F32), (dy * inv : F32), length, dash, space)))

# DrawLineDashed: dashes of dashSize every dashSize + spaceSize along the line
# (one RL_LINES block); a line shorter than both or a dash size <= 0 draws
# DrawLineV. More than 4096 dashes (the C loop may not end) are refused, as are
# sizes beyond 2^24.
def line_dashed(+sx: F32, +sy: F32, +ex: F32, +ey: F32, +dash: F32, +space: F32, +color: U32) -> Plan:
  +dx = (ex - sx : F32)
  +dy = (ey - sy : F32)
  +length = F32.sqrt((dx * dx + dy * dy : F32))
  +ints = int.valid(dash) && int.valid(space) && (F32.abs(int.of(dash)) <= 16777216.0 : F32) && (F32.abs(int.of(space)) <= 16777216.0 : F32)
  +d = int.of(Bool.pick(F32, ints, dash, 0.0))
  +s = int.of(Bool.pick(F32, ints, space, 0.0))
  Plan.require(ints, dashed.drawn((length < (d + s : F32) : F32) || (d <= 0.0 : F32), sx, sy, ex, ey, dx, dy, length, d, s, color))

# -----------------------------------------------------------------------------
# Rounded rectangles

def corner.radius(+width: F32, +height: F32, +roundness: F32) -> F32:
  Bool.pick(F32, (width > height : F32), ((height * roundness : F32) / 2.0 : F32), ((width * roundness : F32) / 2.0 : F32))

# The corner segment count: the C int parameter when at least 4, else the
# estimate (int)(ceilf(2*PI/th)/divisor) with 4 for a non-positive one.
def corner.segments.pick(small: Bool, +lm: U32, +radius: F32, +divisor: F32, +segments: F32) -> Maybe<F32>:
  match small:
    case False{}: segments.bounded(segments)
    case True{}: estimate.floor(estimate.corner(estimate.th(lm, radius), divisor), 4.0)

def corner.segments.valid(valid: Bool, +lm: U32, +radius: F32, +divisor: F32, +segments: F32) -> Maybe<F32>:
  match valid:
    case False{}: None{}
    case True{}: corner.segments.pick((int.of(segments) < 4.0 : F32), lm, radius, divisor, int.of(segments))

def corner.segments(+lm: U32, +radius: F32, +divisor: F32, +segments: F32) -> Maybe<F32>:
  corner.segments.valid(int.valid(segments), lm, radius, divisor, segments)

def quad.at(+color: U32, +a: P2, +b: P2, +c: P2, +d: P2) -> +List<F.Command>:
  [F.Color{color}, F.ShapeUV{0}, P2.point(a), F.ShapeUV{2}, P2.point(b), F.ShapeUV{3}, P2.point(c), F.ShapeUV{1}, P2.point(d)]

def rounded.corners(+gnu: Bool, +x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +step: F32, +segments: F32, +color: U32) -> Plan:
  +right = ((x + w : F32) - r : F32)
  +bottom = ((y + h : F32) - r : F32)
  +left = (x + r : F32)
  +top = (y + r : F32)
  Plan.join(sector.pieces(gnu, left, top, r, 180.0, step, segments, color), Plan.join(sector.pieces(gnu, right, top, r, 270.0, step, segments, color),
    Plan.join(sector.pieces(gnu, right, bottom, r, 0.0, step, segments, color), sector.pieces(gnu, left, bottom, r, 90.0, step, segments, color))))

# The five rectangles [2] upper, [4] right, [6] bottom, [8] left and [9] middle
# between the corner points P0..P11 of rshapes.c's sketch.
def rounded.middle(+x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +color: U32) -> +List<F.Command>:
  +p0 = P2.of((x + r : F32), y)
  +p1 = P2.of(((x + w : F32) - r : F32), y)
  +p2 = P2.of((x + w : F32), (y + r : F32))
  +p3 = P2.of((x + w : F32), ((y + h : F32) - r : F32))
  +p4 = P2.of(((x + w : F32) - r : F32), (y + h : F32))
  +p5 = P2.of((x + r : F32), (y + h : F32))
  +p6 = P2.of(x, ((y + h : F32) - r : F32))
  +p7 = P2.of(x, (y + r : F32))
  +p8 = P2.of((x + r : F32), (y + r : F32))
  +p9 = P2.of(((x + w : F32) - r : F32), (y + r : F32))
  +p10 = P2.of(((x + w : F32) - r : F32), ((y + h : F32) - r : F32))
  +p11 = P2.of((x + r : F32), ((y + h : F32) - r : F32))
  List.append(&2, F.Command, quad.at(color, p0, p8, p9, p1), List.append(&2, F.Command, quad.at(color, p2, p9, p10, p3),
    List.append(&2, F.Command, quad.at(color, p11, p5, p4, p10), List.append(&2, F.Command, quad.at(color, p7, p6, p11, p8), quad.at(color, p8, p11, p10, p9)))))

def rounded.drawn(count: Maybe<F32>, +gnu: Bool, +x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +color: U32) -> Plan:
  match count:
    case None{}: Plan.refused()
    case Some{+segments}:
      Plan.textured(4, Plan.join(rounded.corners(gnu, x, y, w, h, r, (90.0 / segments : F32), segments, color), Plan.only(True{}, rounded.middle(x, y, w, h, r, color))))

def rounded.sized(empty: Bool, +lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +segments: F32, +color: U32) -> Plan:
  match empty:
    case True{}: Plan.empty()
    case False{}: rounded.drawn(corner.segments(lm, r, 4.0, segments), gnu.of(lm), x, y, w, h, r, color)

def rounded.round(flat: Bool, +lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +roundness: F32, +segments: F32, +color: U32) -> Plan:
  match flat:
    case True{}: rectangle(x, y, w, h, color)
    case False{}:
      +r = corner.radius(w, h, Bool.pick(F32, (roundness >= 1.0 : F32), 1.0, roundness))
      rounded.sized((r <= 0.0 : F32), lm, x, y, w, h, r, segments, color)

# DrawRectangleRounded: a roundness <= 0 draws DrawRectangleRec; corners as
# sector quads (segments below 4 estimated), then five rectangles.
def rounded(+lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +roundness: F32, +segments: F32, +color: U32) -> Plan:
  rounded.round((roundness <= 0.0 : F32), lm, x, y, w, h, roundness, segments, color)

def rounded_lines.arc(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +here = (deg2rad() * angle : F32)
      +next = (deg2rad() * (angle + step : F32) : F32)
      +a = Pt.at(gnu, cx, cy, inner, inner, here)
      +b = Pt.at(gnu, cx, cy, inner, inner, next)
      +c = Pt.at(gnu, cx, cy, outer, outer, next)
      +d = Pt.at(gnu, cx, cy, outer, outer, here)
      Plan.with(Pt.ok(a) && Pt.ok(b) && Pt.ok(c) && Pt.ok(d), [F.Color{color}, F.ShapeUV{0}, Pt.point(a), F.ShapeUV{1}, Pt.point(b),
        F.ShapeUV{3}, Pt.point(c), F.ShapeUV{2}, Pt.point(d)], rounded_lines.arc(k, gnu, cx, cy, inner, outer, (angle + step : F32), step, color))

def rounded_lines.outline(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +outer: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +a = Pt.at(gnu, cx, cy, outer, outer, (deg2rad() * angle : F32))
      +b = Pt.at(gnu, cx, cy, outer, outer, (deg2rad() * (angle + step : F32) : F32))
      Plan.with(Pt.ok(a) && Pt.ok(b), [F.Color{color}, Pt.point(a), Pt.point(b)], rounded_lines.outline(k, gnu, cx, cy, outer, (angle + step : F32), step, color))

def rounded_lines.corner(thick: Bool, n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match thick:
    case True{}: rounded_lines.arc(n, gnu, cx, cy, inner, outer, angle, step, color)
    case False{}: rounded_lines.outline(n, gnu, cx, cy, outer, angle, step, color)

# The corner centers P16..P19, half a pixel inside.
def rounded_lines.corners(+thick: Bool, +gnu: Bool, +x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +outer: F32, +step: F32, +segments: F32, +color: U32) -> Plan:
  +n = U32.to_nat(F32.to_u32(segments))
  +left = ((x + r : F32) + 0.5 : F32)
  +top = ((y + r : F32) + 0.5 : F32)
  +right = (((x + w : F32) - r : F32) - 0.5 : F32)
  +bottom = (((y + h : F32) - r : F32) - 0.5 : F32)
  Plan.join(rounded_lines.corner(thick, n, gnu, left, top, r, outer, 180.0, step, color), Plan.join(rounded_lines.corner(thick, n, gnu, right, top, r, outer, 270.0, step, color),
    Plan.join(rounded_lines.corner(thick, n, gnu, right, bottom, r, outer, 0.0, step, color), rounded_lines.corner(thick, n, gnu, left, bottom, r, outer, 90.0, step, color))))

type Outline is Data:
  Outline{p0: P2, p1: P2, p2: P2, p3: P2, p4: P2, p5: P2, p6: P2, p7: P2, p8: P2, p9: P2, p10: P2, p11: P2, p12: P2, p13: P2, p14: P2, p15: P2}

# P0..P15 of rshapes.c's DrawRectangleRoundedLinesEx sketch.
def outline.points(+x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +t: F32) -> Outline:
  +xl = ((x + r : F32) + 0.5 : F32)
  +xr = (((x + w : F32) - r : F32) - 0.5 : F32)
  +yt = ((y + r : F32) + 0.5 : F32)
  +yb = (((y + h : F32) - r : F32) - 0.5 : F32)
  Outline{P2{xl, ((y - t : F32) + 0.5 : F32)}, P2{xr, ((y - t : F32) + 0.5 : F32)}, P2{(((x + w : F32) + t : F32) - 0.5 : F32), yt},
    P2{(((x + w : F32) + t : F32) - 0.5 : F32), yb}, P2{xr, (((y + h : F32) + t : F32) - 0.5 : F32)}, P2{xl, (((y + h : F32) + t : F32) - 0.5 : F32)},
    P2{((x - t : F32) + 0.5 : F32), yb}, P2{((x - t : F32) + 0.5 : F32), yt}, P2{xl, (y + 0.5 : F32)}, P2{xr, (y + 0.5 : F32)},
    P2{((x + w : F32) - 0.5 : F32), yt}, P2{((x + w : F32) - 0.5 : F32), yb}, P2{xr, ((y + h : F32) - 0.5 : F32)}, P2{xl, ((y + h : F32) - 0.5 : F32)},
    P2{(x + 0.5 : F32), yb}, P2{(x + 0.5 : F32), yt}}

# Thick (lineThick > 1): four quads between the outer and inner edges; thin:
# four RL_LINES along the outer edge.
def outline.quads(+color: U32, o: Outline) -> +List<F.Command>:
  Outline{+p0, +p1, +p2, +p3, +p4, +p5, +p6, +p7, +p8, +p9, +p10, +p11, +p12, +p13, +p14, +p15} = o
  List.append(&2, F.Command, quad.at(color, p0, p8, p9, p1), List.append(&2, F.Command, quad.at(color, p2, p10, p11, p3),
    List.append(&2, F.Command, quad.at(color, p13, p5, p4, p12), quad.at(color, p15, p7, p6, p14))))

def outline.lines(+color: U32, o: Outline) -> +List<F.Command>:
  Outline{+p0, +p1, +p2, +p3, +p4, +p5, +p6, +p7, _, _, _, _, _, _, _, _} = o
  [F.Color{color}, P2.point(p0), P2.point(p1), F.Color{color}, P2.point(p2), P2.point(p3), F.Color{color}, P2.point(p4), P2.point(p5),
    F.Color{color}, P2.point(p6), P2.point(p7)]

def outline.sides(thick: Bool, +color: U32, o: Outline) -> +List<F.Command>:
  match thick:
    case True{}: outline.quads(color, o)
    case False{}: outline.lines(color, o)

def rounded_lines.wrap(thick: Bool, plan: Plan) -> Plan:
  match thick:
    case True{}: Plan.textured(4, plan)
    case False{}: Plan.plain(2, plan)

def rounded_lines.drawn(count: Maybe<F32>, +gnu: Bool, +x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +t: F32, +color: U32) -> Plan:
  match count:
    case None{}: Plan.refused()
    case Some{+segments}:
      +thick = (t > 1.0 : F32)
      rounded_lines.wrap(thick, Plan.join(rounded_lines.corners(thick, gnu, x, y, w, h, r, (r + t : F32), (90.0 / segments : F32), segments, color),
        Plan.only(True{}, outline.sides(thick, color, outline.points(x, y, w, h, r, t)))))

def rounded_lines.sized(empty: Bool, +lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +t: F32, +segments: F32, +color: U32) -> Plan:
  match empty:
    case True{}: Plan.empty()
    case False{}: rounded_lines.drawn(corner.segments(lm, r, 2.0, segments), gnu.of(lm), x, y, w, h, r, t, color)

def rounded_lines.round(flat: Bool, +lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +roundness: F32, +segments: F32, +t: F32, +color: U32) -> Plan:
  match flat:
    case True{}: rectangle.lines_ex((x - t : F32), (y - t : F32), (w + (2.0 * t : F32) : F32), (h + (2.0 * t : F32) : F32), t, color)
    case False{}:
      +r = corner.radius(w, h, Bool.pick(F32, (roundness >= 1.0 : F32), 1.0, roundness))
      rounded_lines.sized((r <= 0.0 : F32), lm, x, y, w, h, r, t, segments, color)

# DrawRectangleRoundedLinesEx: a negative thickness becomes 0; roundness <= 0
# draws DrawRectangleLinesEx around the rectangle; corners with segments below
# 4 estimated; thickness above 1 draws quads, otherwise RL_LINES.
def rounded_lines(+lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +roundness: F32, +segments: F32, +thick: F32, +color: U32) -> Plan:
  rounded_lines.round((roundness <= 0.0 : F32), lm, x, y, w, h, roundness, segments, Bool.pick(F32, (thick < 0.0 : F32), 0.0, thick), color)

# -----------------------------------------------------------------------------
# Splines (SPLINE_SEGMENT_DIVISIONS 24)

def spline.step() -> F32:
  (1.0 / 24.0 : F32)

# DrawSplineSegmentLinear: DrawLineEx's quad (nothing for a zero length or
# thickness).
def spline_linear_segment(+x0: F32, +y0: F32, +x1: F32, +y1: F32, +thick: F32, +color: U32) -> Plan:
  line_ex(x0, y0, x1, y1, thick, color)

def spline_linear.quad(+a: P2, +b: P2, +scale: F32, +color: U32) -> Plan:
  P2{ax, ay} = a
  P2{bx, by} = b
  +dx = (bx - ax : F32)
  +dy = (by - ay : F32)
  +rx = (F32.neg(scale) * dy : F32)
  +ry = (scale * dx : F32)
  strip([P2{(ax - rx : F32), (ay - ry : F32)}, P2{(ax + rx : F32), (ay + ry : F32)}, P2{(bx - rx : F32), (by - ry : F32)}, P2{(bx + rx : F32), (by + ry : F32)}], color)

def spline_linear.scale(+a: P2, +b: P2, +thick: F32, +scale: F32) -> F32:
  P2{ax, ay} = a
  P2{bx, by} = b
  +dx = (bx - ax : F32)
  +dy = (by - ay : F32)
  +length = F32.sqrt((dx * dx + dy * dy : F32))
  Bool.pick(F32, (length > 0.0 : F32), (thick / (2.0 * length : F32) : F32), scale)

def spline_linear.loop(rest: +List<P2>, +a: P2, +thick: F32, +scale: F32, +color: U32) -> Plan:
  match rest:
    case Nil{}: Plan.empty()
    case Con{+b, more}:
      +s = spline_linear.scale(a, b, thick, scale)
      Plan.join(spline_linear.quad(a, b, s, color), spline_linear.loop(more, b, thick, s, color))

# DrawSplineLinear (no SUPPORT_SPLINE_MITERS): a DrawTriangleStrip quad per
# pair; a zero-length pair keeps the previous scale (0 at first).
def spline_linear(points: +List<P2>, +thick: F32, +color: U32) -> Plan:
  match points:
    case Con{+a, rest}: spline_linear.loop(rest, a, thick, 0.0, color)
    case Nil{}: Plan.empty()

type Basis is Data:
  Basis{a0: F32, a1: F32, a2: F32, a3: F32}

def basis.of(+p1: F32, +p2: F32, +p3: F32, +p4: F32) -> Basis:
  Basis{((((F32.neg(p1) + (3.0 * p2 : F32) : F32) - (3.0 * p3 : F32) : F32) + p4 : F32) / 6.0 : F32),
    ((((3.0 * p1 : F32) - (6.0 * p2 : F32) : F32) + (3.0 * p3 : F32) : F32) / 6.0 : F32),
    (((F32.neg(3.0) * p1 : F32) + (3.0 * p3 : F32) : F32) / 6.0 : F32),
    (((p1 + (4.0 * p2 : F32) : F32) + p3 : F32) / 6.0 : F32)}

def basis.at(+b: Basis, +t: F32) -> F32:
  Basis{a0, a1, a2, a3} = b
  (a3 + t * (a2 + t * (a1 + t * a0 : F32) : F32) : F32)

def basis.start(+b: Basis) -> F32:
  Basis{_, _, _, a3} = b
  a3

# t = step*i (the segment functions) or i/24.0 (DrawSplineBasis and
# DrawSplineCatmullRom).
def spline.t(+divided: Bool, +i: F32) -> F32:
  Bool.pick(F32, divided, (i / 24.0 : F32), (spline.step() * i : F32))

def basis.points(n: Nat, +divided: Bool, +i: F32, +bx: Basis, +by: Basis) -> +List<P2>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      +t = spline.t(divided, i)
      Con{P2{basis.at(bx, t), basis.at(by, t)}, basis.points(k, divided, (i + 1.0 : F32), bx, by)}

def P2.x(+p: P2) -> F32:
  P2{x, _} = p
  x

def P2.y(+p: P2) -> F32:
  P2{_, y} = p
  y

# DrawSplineSegmentBasis: the B-spline coefficients divided by 6; i = 0 moves
# the current point to the curve start (its strip points are overwritten).
def spline_basis_segment(+p1: P2, +p2: P2, +p3: P2, +p4: P2, +thick: F32, +color: U32) -> Plan:
  +bx = basis.of(P2.x(p1), P2.x(p2), P2.x(p3), P2.x(p4))
  +by = basis.of(P2.y(p1), P2.y(p2), P2.y(p3), P2.y(p4))
  ribbon.strip(ribbon(P2{basis.at(bx, 0.0), basis.at(by, 0.0)}, basis.points(24n, False{}, 1.0, bx, by), thick), color)

type Weights is Data:
  Weights{q0: F32, q1: F32, q2: F32, q3: F32}

def catmull.weights(+t: F32) -> Weights:
  Weights{((((F32.neg(1.0) * t : F32) * t : F32) * t : F32) + ((2.0 * t : F32) * t : F32) + (F32.neg(1.0) * t : F32) : F32),
    ((((3.0 * t : F32) * t : F32) * t : F32) + ((F32.neg(5.0) * t : F32) * t : F32) + 2.0 : F32),
    ((((F32.neg(3.0) * t : F32) * t : F32) * t : F32) + ((4.0 * t : F32) * t : F32) + t : F32),
    (((t * t : F32) * t : F32) - (t * t : F32) : F32)}

def catmull.at(+w: Weights, +a: F32, +b: F32, +c: F32, +d: F32) -> F32:
  Weights{q0, q1, q2, q3} = w
  (0.5 * ((a * q0 : F32) + (b * q1 : F32) + (c * q2 : F32) + (d * q3 : F32) : F32) : F32)

def catmull.point(+w: Weights, +p1: P2, +p2: P2, +p3: P2, +p4: P2) -> P2:
  P2{catmull.at(w, P2.x(p1), P2.x(p2), P2.x(p3), P2.x(p4)), catmull.at(w, P2.y(p1), P2.y(p2), P2.y(p3), P2.y(p4))}

def catmull.points(n: Nat, +divided: Bool, +i: F32, +p1: P2, +p2: P2, +p3: P2, +p4: P2) -> +List<P2>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{catmull.point(catmull.weights(spline.t(divided, i)), p1, p2, p3, p4), catmull.points(k, divided, (i + 1.0 : F32), p1, p2, p3, p4)}

# DrawSplineSegmentCatmullRom: the four Catmull-Rom weights and half-scale;
# i = 0 moves the current point to the curve start.
def spline_catmull_segment(+p1: P2, +p2: P2, +p3: P2, +p4: P2, +thick: F32, +color: U32) -> Plan:
  ribbon.strip(ribbon(catmull.point(catmull.weights(0.0), p1, p2, p3, p4), catmull.points(24n, False{}, 1.0, p1, p2, p3, p4), thick), color)

def quadratic.points(n: Nat, +i: F32, +p1: P2, +c2: P2, +p3: P2) -> +List<P2>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      +t = (spline.step() * i : F32)
      +u = (1.0 - t : F32)
      +a = (u * u : F32)
      +b = ((2.0 * u : F32) * t : F32)
      +c = (t * t : F32)
      Con{P2{(((a * P2.x(p1) : F32) + (b * P2.x(c2) : F32) : F32) + (c * P2.x(p3) : F32) : F32), (((a * P2.y(p1) : F32) + (b * P2.y(c2) : F32) : F32) + (c * P2.y(p3) : F32) : F32)},
        quadratic.points(k, (i + 1.0 : F32), p1, c2, p3)}

# DrawSplineSegmentBezierQuadratic: powf(x, 2) compiled as x*x.
def spline_quadratic_segment(+p1: P2, +c2: P2, +p3: P2, +thick: F32, +color: U32) -> Plan:
  ribbon.strip(ribbon(p1, quadratic.points(24n, 1.0, p1, c2, p3), thick), color)

def cube.of(value: Maybe<F32>) -> F32 & Bool:
  match value:
    case None{}: (0.0, False{})
    case Some{+v}: (v, True{})

def cube(+x: F32) -> F32 & Bool:
  cube.of(Power.power(x, 3))

def cube.first(r: F32 & Bool) -> F32:
  (v, _) = r
  v

# powf(x, 3) as the drawing uses it (0 outside the profile's domain).
def cube.value(+x: F32) -> F32:
  cube.first(cube(x))

def cubic.weights.with(+t: F32, +u: F32, a: F32 & Bool, d: F32 & Bool) -> Weights & Bool:
  (+wa, +va) = a
  (+wd, +vd) = d
  (Weights{wa, (((3.0 * (u * u : F32) : F32) * t : F32)), ((3.0 * u : F32) * (t * t : F32) : F32), wd}, va && vd)

def cubic.point(+p1: P2, +c2: P2, +c3: P2, +p4: P2, w: Weights & Bool) -> P2 & Bool:
  (+ws, +valid) = w
  Weights{a, b, c, d} = ws
  (P2{((((a * P2.x(p1) : F32) + (b * P2.x(c2) : F32) : F32) + (c * P2.x(c3) : F32) : F32) + (d * P2.x(p4) : F32) : F32),
    ((((a * P2.y(p1) : F32) + (b * P2.y(c2) : F32) : F32) + (c * P2.y(c3) : F32) : F32) + (d * P2.y(p4) : F32) : F32)}, valid)

def cubic.cons(point: P2 & Bool, rest: +List<P2> & Bool) -> +List<P2> & Bool:
  (+p, +valid) = point
  (list, +others) = rest
  (Con{p, list}, valid && others)

def cubic.points(n: Nat, +i: F32, +p1: P2, +c2: P2, +c3: P2, +p4: P2) -> +List<P2> & Bool:
  match n:
    case 0n: (Nil{}, True{})
    case 1n+k:
      +t = (spline.step() * i : F32)
      +u = (1.0 - t : F32)
      cubic.cons(cubic.point(p1, c2, c3, p4, cubic.weights.with(t, u, cube(u), cube(t))), cubic.points(k, (i + 1.0 : F32), p1, c2, c3, p4))

def cubic.drawn(+p1: P2, +thick: F32, +color: U32, +usable: Bool, points: +List<P2> & Bool) -> Plan:
  (list, +valid) = points
  Plan.require(usable && valid, ribbon.strip(ribbon(p1, list, thick), color))

# DrawSplineSegmentBezierCubic: weights powf(1 - t, 3), 3*powf(1 - t, 2)*t,
# 3*(1 - t)*powf(t, 2) and powf(t, 3) (powf(x, 2) compiled as x*x). The 48
# powf(x, 3) arguments (t = i/24 and 1 - t) give the same bits under glibc
# 2.39 (src/power.bend) and macOS, which tools/rlgl_probe.py checks against
# the host; glibc 2.41 has no powf profile here (refused).
def spline_cubic_segment(+lm: U32, +p1: P2, +c2: P2, +c3: P2, +p4: P2, +thick: F32, +color: U32) -> Plan:
  cubic.drawn(p1, thick, color, Bool.not(U32.is_eq(lm, 2)), cubic.points(24n, 1.0, p1, c2, c3, p4))

def ribbon.list(result: +List<P2> & Side) -> +List<P2>:
  (points, _) = result
  points

def ribbon.points(first: Bool, +current: P2, +carried: Side, nexts: +List<P2>, +thick: F32) -> +List<P2>:
  match first:
    case True{}: ribbon.list(ribbon(current, nexts, thick))
    case False{}: ribbon.list(ribbon.carried(current, carried, nexts, thick))

def ribbon.side(result: +List<P2> & Side) -> Side:
  (_, side) = result
  side

def P2.last(points: +List<P2>, +fallback: P2) -> P2:
  match points:
    case Nil{}: fallback
    case Con{+p, rest}: P2.last(rest, p)

def spline.cap(+gnu: Bool, +p: P2, +thick: F32, +color: U32) -> Plan:
  circle(gnu, P2.x(p), P2.y(p), (thick / 2.0 : F32), color)

def basis.pair(+p1: P2, +p2: P2, +p3: P2, +p4: P2) -> Basis & Basis:
  (basis.of(P2.x(p1), P2.x(p2), P2.x(p3), P2.x(p4)), basis.of(P2.y(p1), P2.y(p2), P2.y(p3), P2.y(p4)))

def basis.current(pair: Basis & Basis) -> P2:
  (+bx, +by) = pair
  P2{basis.start(bx), basis.start(by)}

def basis.nexts(pair: Basis & Basis) -> +List<P2>:
  (+bx, +by) = pair
  basis.points(24n, True{}, 1.0, bx, by)

# DrawSplineBasis: per four consecutive points a B-spline strip (t = j/24)
# starting at the segment's own start point; the first strip's first side is
# its own, later strips carry the previous strip's last side; circle caps at
# the start and the end of the spline.
def spline_basis.loop(rest: +List<P2>, +p1: P2, +p2: P2, +p3: P2, +gnu: Bool, +first: Bool, +carried: Side, +end: P2, +thick: F32, +color: U32) -> Plan:
  match rest:
    case Nil{}: spline.cap(gnu, end, thick, color)
    case Con{+p4, more}:
      +bx = basis.of(P2.x(p1), P2.x(p2), P2.x(p3), P2.x(p4))
      +by = basis.of(P2.y(p1), P2.y(p2), P2.y(p3), P2.y(p4))
      +current = P2.of(basis.start(bx), basis.start(by))
      +nexts = basis.points(24n, True{}, 1.0, bx, by)
      Plan.join(strip(ribbon.points(first, current, carried, nexts, thick), color),
        spline_basis.loop(more, p2, p3, p4, gnu, False{}, ribbon.side(ribbon.carried(current, carried, nexts, thick)), P2.last(nexts, current), thick, color))

def spline_basis.start(points: +List<P2>, +gnu: Bool, +thick: F32, +color: U32) -> Plan:
  match points:
    case Con{+p1, Con{+p2, Con{+p3, Con{+p4, rest}}}}:
      +start = basis.current(basis.pair(p1, p2, p3, p4))
      Plan.join(spline.cap(gnu, start, thick, color), spline_basis.loop(Con{p4, rest}, p1, p2, p3, gnu, True{}, Side{0.0, 0.0, 0.0}, start, thick, color))
    case _: Plan.empty()

def spline_basis(+gnu: Bool, points: +List<P2>, +thick: F32, +color: U32) -> Plan:
  spline_basis.start(points, gnu, thick, color)

# DrawSplineCatmullRom: the current point starts at points[1] (circle cap)
# and runs on across segments (t = j/24); the first strip's first side is its
# own, later strips carry the previous strip's last side; a circle cap ends
# the spline.
def spline_catmull.loop(rest: +List<P2>, +p1: P2, +p2: P2, +p3: P2, +gnu: Bool, +first: Bool, +carried: Side, +current: P2, +thick: F32, +color: U32) -> Plan:
  match rest:
    case Nil{}: spline.cap(gnu, current, thick, color)
    case Con{+p4, more}:
      +nexts = catmull.points(24n, True{}, 1.0, p1, p2, p3, p4)
      Plan.join(strip(ribbon.points(first, current, carried, nexts, thick), color),
        spline_catmull.loop(more, p2, p3, p4, gnu, False{}, ribbon.side(ribbon.carried(current, carried, nexts, thick)), P2.last(nexts, current), thick, color))

def spline_catmull.start(points: +List<P2>, +gnu: Bool, +thick: F32, +color: U32) -> Plan:
  match points:
    case Con{+p1, Con{+p2, Con{+p3, Con{+p4, rest}}}}:
      Plan.join(spline.cap(gnu, p2, thick, color), spline_catmull.loop(Con{p4, rest}, p1, p2, p3, gnu, True{}, Side{0.0, 0.0, 0.0}, p2, thick, color))
    case _: Plan.empty()

def spline_catmull(+gnu: Bool, points: +List<P2>, +thick: F32, +color: U32) -> Plan:
  spline_catmull.start(points, gnu, thick, color)

def spline_quadratic.loop(rest: +List<P2>, +p1: P2, +thick: F32, +color: U32) -> Plan:
  match rest:
    case Con{+c2, Con{+p3, more}}: Plan.join(spline_quadratic_segment(p1, c2, p3, thick, color), spline_quadratic.loop(more, p3, thick, color))
    case _: Plan.empty()

# DrawSplineBezierQuadratic: segments (p[i], p[i + 1], p[i + 2]) for
# i = 0, 2, 4, ... while i < count - 2.
def spline_quadratic(points: +List<P2>, +thick: F32, +color: U32) -> Plan:
  match points:
    case Con{+p1, rest}: spline_quadratic.loop(rest, p1, thick, color)
    case Nil{}: Plan.empty()

def spline_cubic.loop(rest: +List<P2>, +p1: P2, +lm: U32, +thick: F32, +color: U32) -> Plan:
  match rest:
    case Con{+c2, Con{+c3, Con{+p4, more}}}: Plan.join(spline_cubic_segment(lm, p1, c2, c3, p4, thick, color), spline_cubic.loop(more, p4, lm, thick, color))
    case _: Plan.empty()

# DrawSplineBezierCubic: segments (p[i], .., p[i + 3]) for i = 0, 3, 6, ...
# while i < count - 3.
def spline_cubic(+lm: U32, points: +List<P2>, +thick: F32, +color: U32) -> Plan:
  match points:
    case Con{+p1, rest}: spline_cubic.loop(rest, p1, lm, thick, color)
    case Nil{}: Plan.empty()
