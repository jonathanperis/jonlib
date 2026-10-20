# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.2 rshapes.c (SUPPORT_QUADS_DRAW_MODE,
# SPLINE_SEGMENT_DIVISIONS 24, no SUPPORT_SPLINE_MITERS); LICENSES/raylib.txt.
# The 6.2 thick outlines (DrawTriangleLinesEx, DrawCircleSectorLinesEx,
# DrawRingLinesEx and the rest) are adapted from rshapes.c's algorithms.
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
import ./asin.bend as Asin
import ./lgpl/asin.bend as GlibcAsin

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

def P2.x(+p: P2) -> F32:
  P2{x, _} = p
  x

def P2.y(+p: P2) -> F32:
  P2{_, y} = p
  y

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

# A thickness t (already made positive) grown outside the rectangle: top and
# bottom bands 2t wider than it, left and right bands its height.
def rectangle.lines_ex.out(+x: F32, +y: F32, +width: F32, +height: F32, +t: F32, +color: U32) -> Plan:
  Plan.join(rectangle((x - t : F32), (y - t : F32), (width + (t * 2.0 : F32) : F32), t, color),
    Plan.join(rectangle((x - t : F32), (y + height : F32), (width + (t * 2.0 : F32) : F32), t, color),
      Plan.join(rectangle((x - t : F32), y, t, height, color), rectangle((x + width : F32), y, t, height, color))))

def rectangle.lines_ex.side(inside: Bool, +x: F32, +y: F32, +width: F32, +height: F32, +thick: F32, +color: U32) -> Plan:
  match inside:
    case True{}: rectangle.lines_ex.with(x, y, width, height, thick, color)
    case False{}: rectangle.lines_ex.out(x, y, width, height, (thick * F32.neg(1.0) : F32), color)

# DrawRectangleLinesEx (raylib 6.2): a thickness above half of either side
# becomes half the smaller side; a positive one draws four DrawRectangleRec
# bands inside the rectangle, zero or a negative one four bands outside it.
def rectangle.lines_ex(+x: F32, +y: F32, +width: F32, +height: F32, +thick: F32, +color: U32) -> Plan:
  +over = (thick > (width / 2.0 : F32) : F32) || (thick > (height / 2.0 : F32) : F32)
  +wide = (width >= height : F32)
  +narrow = (width <= height : F32)
  +clamped = Bool.pick(F32, over, Bool.pick(F32, wide, (height / 2.0 : F32), Bool.pick(F32, narrow, (width / 2.0 : F32), thick)), thick)
  rectangle.lines_ex.side((clamped > 0.0 : F32), x, y, width, height, clamped, color)

# -----------------------------------------------------------------------------
# Triangles and point lists

# DrawTriangleGradient: the quad (v1, v2, v3, v3), each vertex with its
# color (the third color twice).
def triangle.gradient(+a: P2, +b: P2, +c: P2, +color_a: U32, +color_b: U32, +color_c: U32) -> Plan:
  Plan.textured(4, Plan.only(True{}, [F.Color{color_a}, F.ShapeUV{0}, P2.point(a), F.Color{color_b}, F.ShapeUV{2}, P2.point(b),
    F.Color{color_c}, F.ShapeUV{3}, P2.point(c), F.Color{color_c}, F.ShapeUV{1}, P2.point(c)]))

# DrawTriangle: DrawTriangleGradient with one color.
def triangle(+a: P2, +b: P2, +c: P2, +color: U32) -> Plan:
  triangle.gradient(a, b, c, color, color, color)

# DrawTriangleLines: three RL_LINES.
def triangle.lines(+a: P2, +b: P2, +c: P2, +color: U32) -> Plan:
  Plan.plain(2, Plan.only(True{}, [F.Color{color}, P2.point(a), P2.point(b), P2.point(b), P2.point(c), P2.point(c), P2.point(a)]))

def tri_ex.length(+x: F32, +y: F32) -> F32:
  F32.sqrt((x * x + y * y : F32))

# A vertex scaled toward the incenter: incenter + (v - incenter)*scale.
def tri_ex.scaled(+ix: F32, +iy: F32, +scale: F32, +v: P2) -> P2:
  P2{x, y} = v
  P2{(ix + ((x - ix : F32) * scale : F32) : F32), (iy + ((y - iy : F32) * scale : F32) : F32)}

# Three quads, one per edge: (v1, v2, v5, v4), (v2, v3, v6, v5), (v3, v1, v4, v6).
def tri_ex.quads(+color: U32, +v1: P2, +v2: P2, +v3: P2, +v4: P2, +v5: P2, +v6: P2) -> Plan:
  Plan.textured(4, Plan.only(True{}, [F.Color{color}, F.ShapeUV{0}, P2.point(v1), F.ShapeUV{2}, P2.point(v2), F.ShapeUV{3}, P2.point(v5),
    F.ShapeUV{1}, P2.point(v4), F.ShapeUV{0}, P2.point(v2), F.ShapeUV{2}, P2.point(v3), F.ShapeUV{3}, P2.point(v6), F.ShapeUV{1}, P2.point(v5),
    F.ShapeUV{0}, P2.point(v3), F.ShapeUV{2}, P2.point(v1), F.ShapeUV{3}, P2.point(v4), F.ShapeUV{1}, P2.point(v6)]))

# A negative thickness swaps the outer and the scaled vertices (the winding).
def tri_ex.wound(inward: Bool, +color: U32, +v1: P2, +v2: P2, +v3: P2, +v4: P2, +v5: P2, +v6: P2) -> Plan:
  match inward:
    case True{}: tri_ex.quads(color, v1, v2, v3, v4, v5, v6)
    case False{}: tri_ex.quads(color, v4, v5, v6, v1, v2, v3)

def tri_ex.filled(filled: Bool, +a: P2, +b: P2, +c: P2, +thick: F32, +ix: F32, +iy: F32, +scale: F32, +color: U32) -> Plan:
  match filled:
    case True{}: triangle(a, b, c, color)
    case False{}:
      tri_ex.wound(Bool.not((thick < 0.0 : F32)), color, a, b, c, tri_ex.scaled(ix, iy, scale, a), tri_ex.scaled(ix, iy, scale, b),
        tri_ex.scaled(ix, iy, scale, c))

# DrawTriangleLinesEx (raylib 6.2): the triangle scaled toward its incenter
# by 1 - thick/inradius (incenter and inradius from the edge lengths, sqrtf,
# in rshapes.c's order); a scale <= 0 draws DrawTriangle, otherwise quads
# between the triangle and the scaled one (outside it for a negative
# thickness).
def triangle.lines_ex(+a: P2, +b: P2, +c: P2, +thick: F32, +color: U32) -> Plan:
  P2{x1, y1} = a
  P2{x2, y2} = b
  P2{x3, y3} = c
  +l1 = tri_ex.length((x2 - x3 : F32), (y2 - y3 : F32))
  +l2 = tri_ex.length((x3 - x1 : F32), (y3 - y1 : F32))
  +l3 = tri_ex.length((x1 - x2 : F32), (y1 - y2 : F32))
  +perimeter = ((l1 + l2 : F32) + l3 : F32)
  +semi = (perimeter / 2.0 : F32)
  +ix = ((((l1 * x1 : F32) + (l2 * x2 : F32) : F32) + (l3 * x3 : F32) : F32) / perimeter : F32)
  +iy = ((((l1 * y1 : F32) + (l2 * y2 : F32) : F32) + (l3 * y3 : F32) : F32) / perimeter : F32)
  +inradius = F32.sqrt(((((semi - l1 : F32) * (semi - l2 : F32) : F32) * (semi - l3 : F32) : F32) / semi : F32))
  +scale = (1.0 - (thick / inradius : F32) : F32)
  tri_ex.filled((scale <= 0.0 : F32), P2{x1, y1}, P2{x2, y2}, P2{x3, y3}, thick, ix, iy, scale, color)

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

# (int)ceilf((endAngle - startAngle)*(2*PI/th)/360.0f) (raylib 6.2)
def estimate.arc(th: Maybe<F32>, +span: F32) -> Maybe<F32>:
  match th:
    case None{}: None{}
    case Some{+t}: int.maybe(F32.ceil(((span * (two_pi() / t : F32) : F32) / 360.0 : F32)))

# (int)ceilf((2*PI/th)/4.0f) for the rounded rectangle corners (raylib 6.2).
def estimate.corner(th: Maybe<F32>) -> Maybe<F32>:
  match th:
    case None{}: None{}
    case Some{+t}: int.maybe(F32.ceil(((two_pi() / t : F32) / 4.0 : F32)))

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

# Whether an ordered arc spans a whole turn or more (raylib 6.2).
def arc.full(+start: F32, +end: F32) -> Bool:
  ((end - start : F32) >= 360.0 : F32)

# The end angle of an ordered arc limited to one turn: startAngle + 360.0f
# when it spans 360 degrees or more (raylib 6.2).
def arc.end(+start: F32, +end: F32) -> F32:
  Bool.pick(F32, arc.full(start, end), (start + 360.0 : F32), end)

# showCapLines (raylib 6.2): a whole turn drops the caps unless the outline
# grows inward (a thickness >= 0 in the *LinesEx outlines).
def arc.caps(full: Bool, inward: Bool) -> Bool:
  match full:
    case False{}: True{}
    case True{}: inward

def sector.distinct(skip: Bool, +lm: U32, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match skip:
    case True{}: Plan.empty()
    case False{}:
      +swap = (end < start : F32)
      +first = Bool.pick(F32, swap, end, start)
      sector.ordered(lm, cx, cy, r, first, arc.end(first, Bool.pick(F32, swap, start, end)), segments, color)

# DrawCircleSector (quads of two segments, then an odd last piece). raylib
# 6.2: a radius <= 0 draws nothing and the arc is limited to one turn.
def sector(+lm: U32, +cx: F32, +cy: F32, +radius: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  sector.distinct(F32.is_eq(start, end) || (radius <= 0.0 : F32), lm, cx, cy, radius, start, end, segments, color)

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

def ellipse_ex.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +ih: F32, +iv: F32, +oh: F32, +ov: F32, +degrees: F32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +here = (deg2rad() * degrees : F32)
      +next = (deg2rad() * (degrees + 10.0 : F32) : F32)
      +a = Pt.at(gnu, cx, cy, ih, iv, here)
      +b = Pt.at(gnu, cx, cy, ih, iv, next)
      +c = Pt.at(gnu, cx, cy, oh, ov, next)
      +d = Pt.at(gnu, cx, cy, oh, ov, here)
      Plan.with(Pt.ok(a) && Pt.ok(b) && Pt.ok(c) && Pt.ok(d), [F.ShapeUV{0}, Pt.point(a), F.ShapeUV{2}, Pt.point(b), F.ShapeUV{3}, Pt.point(c),
        F.ShapeUV{1}, Pt.point(d)], ellipse_ex.loop(k, gnu, cx, cy, ih, iv, oh, ov, (degrees + 10.0 : F32)))

def ellipse_ex.kind(filled: Bool, +gnu: Bool, +cx: F32, +cy: F32, +rx: F32, +ry: F32, +ih: F32, +iv: F32, +oh: F32, +ov: F32, +color: U32) -> Plan:
  match filled:
    case True{}: ellipse(gnu, cx, cy, rx, ry, color)
    case False{}: Plan.textured(4, Plan.prefix(F.Color{color}, ellipse_ex.loop(36n, gnu, cx, cy, ih, iv, oh, ov, 0.0)))

# DrawEllipseLinesEx (raylib 6.2): 36 quads every 10 degrees between the
# radii and the radii - thick (swapped for a negative thickness), the color
# set once; a thickness >= 0 reaching either radius draws DrawEllipseV.
def ellipse_lines_ex(+gnu: Bool, +cx: F32, +cy: F32, +rx: F32, +ry: F32, +thick: F32, +color: U32) -> Plan:
  +ih = (rx - thick : F32)
  +iv = (ry - thick : F32)
  +positive = (thick >= 0.0 : F32)
  ellipse_ex.kind(positive && ((ih <= 0.0 : F32) || (iv <= 0.0 : F32)), gnu, cx, cy, rx, ry, Bool.pick(F32, positive, ih, rx),
    Bool.pick(F32, positive, iv, ry), Bool.pick(F32, positive, rx, ih), Bool.pick(F32, positive, ry, iv), color)

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

# A cap line from the center to the arc (none for a whole turn).
def sector_lines.cap(caps: Bool, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +color: U32) -> Plan:
  match caps:
    case False{}: Plan.empty()
    case True{}:
      +p = Pt.at(gnu, cx, cy, r, r, (deg2rad() * angle : F32))
      Plan.only(Pt.ok(p), [F.Color{color}, F.Point{cx, cy}, Pt.point(p)])

def sector_lines.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +step: F32, +color: U32, +caps: Bool) -> Plan:
  match n:
    case 0n: sector_lines.cap(caps, gnu, cx, cy, r, angle, color)
    case 1n+k:
      +a = Pt.at(gnu, cx, cy, r, r, (deg2rad() * angle : F32))
      +b = Pt.at(gnu, cx, cy, r, r, (deg2rad() * (angle + step : F32) : F32))
      Plan.with(Pt.ok(a) && Pt.ok(b), [F.Color{color}, Pt.point(a), Pt.point(b)], sector_lines.loop(k, gnu, cx, cy, r, (angle + step : F32), step, color, caps))

def sector_lines.drawn(count: Maybe<F32>, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +caps: Bool, +color: U32) -> Plan:
  match count:
    case None{}: Plan.refused()
    case Some{+segments}:
      Plan.plain(2, Plan.join(sector_lines.cap(caps, gnu, cx, cy, r, start, color),
        sector_lines.loop(U32.to_nat(F32.to_u32(segments)), gnu, cx, cy, r, start, ((end - start : F32) / segments : F32), color, caps)))

def sector_lines.ordered(+lm: U32, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +segments: F32, +caps: Bool, +color: U32) -> Plan:
  sector_lines.drawn(segments.resolve(lm, r, (end - start : F32), segments), gnu.of(lm), cx, cy, r, start, end, caps, color)

def sector_lines.distinct(skip: Bool, +lm: U32, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match skip:
    case True{}: Plan.empty()
    case False{}:
      +swap = (end < start : F32)
      +first = Bool.pick(F32, swap, end, start)
      +last = Bool.pick(F32, swap, start, end)
      sector_lines.ordered(lm, cx, cy, r, first, arc.end(first, last), segments, arc.caps(arc.full(first, last), False{}), color)

# DrawCircleSectorLines: cap lines from the center plus one line per segment.
# raylib 6.2: a radius <= 0 draws nothing; a whole turn or more is limited to
# one turn and drawn without the cap lines.
def sector_lines(+lm: U32, +cx: F32, +cy: F32, +radius: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  sector_lines.distinct(F32.is_eq(start, end) || (radius <= 0.0 : F32), lm, cx, cy, radius, start, end, segments, color)

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

# The cap line between the radii at an angle (none for a whole turn).
def ring_lines.cap(caps: Bool, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +angle: F32, +color: U32) -> Plan:
  match caps:
    case False{}: Plan.empty()
    case True{}:
      +here = (deg2rad() * angle : F32)
      +a = Pt.at(gnu, cx, cy, outer, outer, here)
      +b = Pt.at(gnu, cx, cy, inner, inner, here)
      Plan.only(Pt.ok(a) && Pt.ok(b), [F.Color{color}, Pt.point(a), Pt.point(b)])

def ring_lines.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +angle: F32, +step: F32, +color: U32, +caps: Bool) -> Plan:
  match n:
    case 0n: ring_lines.cap(caps, gnu, cx, cy, inner, outer, angle, color)
    case 1n+k:
      +next = (deg2rad() * (angle + step : F32) : F32)
      +here = (deg2rad() * angle : F32)
      +a = Pt.at(gnu, cx, cy, outer, outer, here)
      +b = Pt.at(gnu, cx, cy, outer, outer, next)
      +c = Pt.at(gnu, cx, cy, inner, inner, here)
      +d = Pt.at(gnu, cx, cy, inner, inner, next)
      Plan.with(Pt.ok(a) && Pt.ok(b) && Pt.ok(c) && Pt.ok(d), [F.Color{color}, Pt.point(a), Pt.point(b), Pt.point(c), Pt.point(d)],
        ring_lines.loop(k, gnu, cx, cy, inner, outer, (angle + step : F32), step, color, caps))

def ring_lines.caps(+gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +step: F32, +segments: F32, +caps: Bool, +color: U32) -> Plan:
  Plan.plain(2, Plan.join(ring_lines.cap(caps, gnu, cx, cy, inner, outer, start, color),
    ring_lines.loop(U32.to_nat(F32.to_u32(segments)), gnu, cx, cy, inner, outer, start, step, color, caps)))

def ring_lines.kind(full: Bool, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +caps: Bool, +color: U32) -> Plan:
  match full:
    case True{}: sector_lines(lm, cx, cy, outer, start, end, segments, color)
    case False{}: ring_lines.caps(gnu.of(lm), cx, cy, inner, outer, start, ((end - start : F32) / segments : F32), segments, caps, color)

def ring_lines.drawn(count: Maybe<F32>, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +caps: Bool, +color: U32) -> Plan:
  match count:
    case None{}: Plan.refused()
    case Some{+segments}: ring_lines.kind((inner <= 0.0 : F32), lm, cx, cy, inner, outer, start, end, segments, caps, color)

def ring.select(lines: Bool, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +caps: Bool, +color: U32) -> Plan:
  match lines:
    case False{}: ring.ordered(lm, cx, cy, inner, outer, start, end, segments, color)
    case True{}: ring_lines.drawn(segments.resolve(lm, outer, (end - start : F32), segments), lm, cx, cy, inner, outer, start, end, caps, color)

def ring.sized(empty: Bool, +lines: Bool, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match empty:
    case True{}: Plan.empty()
    case False{}:
      +swap = (end < start : F32)
      +first = Bool.pick(F32, swap, end, start)
      +last = Bool.pick(F32, swap, start, end)
      ring.select(lines, lm, cx, cy, inner, outer, first, arc.end(first, last), segments, arc.caps(arc.full(first, last), False{}), color)

# DrawRing and DrawRingLines order their radii (outer below inner swaps
# them) and their angles. raylib 6.2: an outer radius <= 0 draws nothing, a
# whole turn or more is limited to one turn (DrawRingLines then draws no cap
# lines).
def ring.distinct(same: Bool, +lines: Bool, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match same:
    case True{}: Plan.empty()
    case False{}:
      +flip = (outer < inner : F32)
      +big = Bool.pick(F32, flip, inner, outer)
      ring.sized((big <= 0.0 : F32), lines, lm, cx, cy, Bool.pick(F32, flip, outer, inner), big, start, end, segments, color)

# DrawRing: quads between the radii; a non-positive inner radius draws
# DrawCircleSector with the outer one.
def ring(+lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  ring.distinct(F32.is_eq(start, end), False{}, lm, cx, cy, inner, outer, start, end, segments, color)

# DrawCircleLinesEx (raylib 6.2): DrawRing(center, radius - thick, radius,
# 0, 360, 36).
def circle_lines_ex(+lm: U32, +cx: F32, +cy: F32, +radius: F32, +thick: F32, +color: U32) -> Plan:
  ring(lm, cx, cy, (radius - thick : F32), radius, 0.0, 360.0, 36.0, color)

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

# The radii (raylib 6.2) from the apothem radius*cosf(DEG2RAD*180.0f/sides)
# (DEG2RAD*180.0f is PI in binary32): a thickness >= 0 keeps the outer
# radius and moves the inner one to fmaxf(0, radius - thick*(radius/apothem))
# (no signed zero reaches a vertex differently), a negative one keeps the
# inner radius and moves the outer one to radius - thick*(radius/apothem).
# cosf: Apple every argument of sides 3..4096 (tools/rlgl_probe.py checks
# them all against the host cosf); glibc normal arguments.
def poly_ex.drawn(valid: Bool, +gnu: Bool, +cx: F32, +cy: F32, +sides: F32, +r: F32, +rotation: F32, +thick: F32, +color: U32) -> Plan:
  match valid:
    case False{}: Plan.refused()
    case True{}:
      +exterior = ((360.0 / sides : F32) * deg2rad() : F32)
      +arg = ((deg2rad() * 180.0 : F32) / sides : F32)
      +ratio = (r / (r * cosine(Trig.sincos_for(gnu, arg)) : F32) : F32)
      +positive = (thick >= 0.0 : F32)
      +shrunk = (r - (thick * ratio : F32) : F32)
      Plan.textured(4, Plan.require(Bool.not(gnu) || trig.gnu(arg), poly_ex.loop(U32.to_nat(F32.to_u32(sides)), gnu, cx, cy,
        Bool.pick(F32, positive, r, (r + ((thick * F32.neg(1.0) : F32) * ratio : F32) : F32)), Bool.pick(F32, positive, Bool.pick(F32, (shrunk > 0.0 : F32), shrunk, 0.0), r),
        (rotation * deg2rad() : F32), exterior, color)))

# DrawPolyLinesEx: sides < 3 become 3; quads between the outer and the inner
# radius per side.
def poly_lines_ex(+gnu: Bool, +cx: F32, +cy: F32, +sides: F32, +radius: F32, +rotation: F32, +thick: F32, +color: U32) -> Plan:
  +count = poly.sides(int.of(sides))
  poly_ex.drawn(int.valid(sides) && (count <= 4096.0 : F32), gnu, cx, cy, count, radius, rotation, thick, color)

# -----------------------------------------------------------------------------
# DrawCircleSectorLinesEx and DrawRingLinesEx (raylib 6.2)
#
# Adapted from rshapes.c's algorithms: the outline is a band of quads between
# two radii (the thickness scaled by radius/apothem for the polygon the
# segments make), the caps are quads whose corners rshapes.c finds with
# asinf, atan2f and sinf/cosf of computed angles. Every value keeps the F32
# order of the C. A sinf/cosf, asinf or atan2f result the profile does not
# reproduce refuses the draw: Apple accepts sinf/cosf only at fl(DEG2RAD*d)
# for integral degrees and asinf only below 0x1.d12edp-12, so these outlines
# are in practice reproduced under the glibc profiles.

# RAD2DEG: (180.0f/PI).
def rad2deg() -> F32:
  F.float(1113927392)

# sinf/cosf of an argument, with whether the profile reproduces it.
type Turn is Data:
  Turn{c: F32, s: F32, ok: Bool}

def turn.with(ok: Bool, values: F32 & F32) -> Turn:
  (+c, +s) = values
  Turn{c, s, ok}

def turn.at(+gnu: Bool, +arg: F32) -> Turn:
  turn.with(trig.ok(gnu, arg), Trig.sincos_for(gnu, arg))

def Turn.cos(+t: Turn) -> F32:
  Turn{c, _, _} = t
  c

def Turn.sin(+t: Turn) -> F32:
  Turn{_, s, _} = t
  s

def Turn.ok(+t: Turn) -> Bool:
  Turn{_, _, ok} = t
  ok

# A scalar with whether the profile reproduces it.
type Num is Data:
  Num{v: F32, ok: Bool}

def Num.v(+n: Num) -> F32:
  Num{v, _} = n
  v

def Num.ok(+n: Num) -> Bool:
  Num{_, ok} = n
  ok

# (p1.y - offset)/(p1.y - p2.y) for p = (cosf(a)*r, sinf(a)*r): where the
# segment p1-p2 crosses the line y = offset.
def Num.cut(+a: Turn, +b: Turn, +r: F32, +offset: F32) -> Num:
  Turn{_, sa, oka} = a
  Turn{_, sb, okb} = b
  +ya = (sa * r : F32)
  +yb = (sb * r : F32)
  Num{((ya - offset : F32) / (ya - yb : F32) : F32), oka && okb}

def arcsine.small(inside: Bool, +x: F32) -> Maybe<F32>:
  match inside:
    case True{}: Asin.asin(x)
    case False{}: None{}

# asinf under the profile (as M.Libm.asin): glibc 2.39's kernel, glibc 2.41's
# correctly rounded one, Apple's below 0x1.d12edp-12 in magnitude only.
def arcsine.of(+lm: U32, +x: F32) -> Maybe<F32>:
  match lm:
    case 0: arcsine.small(((F32.bits(x) .&. 2147483647) < 971544424 : U32), x)
    case 1: GlibcAsin.asin(x)
    case _: Asin.asin(x)

def arctan2.checked(valid: Bool, +lm: U32, +y: F32, +x: F32) -> Maybe<F32>:
  match valid:
    case False{}: None{}
    case True{}: CheckedAngle.maybe(CheckedAngle.scalar(lm, y, x))

# atan2f under the profile (src/checked_angle.bend): None unless both
# arguments and the result are zero or normal.
def arctan2.of(+lm: U32, +y: F32, +x: F32) -> Maybe<F32>:
  arctan2.checked(CheckedAngle.normal_or_zero(y) && CheckedAngle.normal_or_zero(x), lm, y, x)

def Pt.x(+p: Pt) -> F32:
  Pt{x, _, _} = p
  x

def Pt.y(+p: Pt) -> F32:
  Pt{_, y, _} = p
  y

def Pt.center(+cx: F32, +cy: F32) -> Pt:
  Pt{cx, cy, True{}}

def Pt.also(+p: Pt, ok: Bool) -> Pt:
  Pt{x, y, pok} = p
  Pt{x, y, pok && ok}

# center + (cosf, sinf)(DEG2RAD*degrees)*r
def Pt.on(+gnu: Bool, +cx: F32, +cy: F32, +r: F32, +degrees: F32) -> Pt:
  Pt.at(gnu, cx, cy, r, r, (deg2rad() * degrees : F32))

# a + (b - a)*t
def Pt.lerp(+a: Pt, +b: Pt, +t: F32, ok: Bool) -> Pt:
  Pt{ax, ay, aok} = a
  Pt{bx, by, bok} = b
  Pt{(ax + ((bx - ax : F32) * t : F32) : F32), (ay + ((by - ay : F32) * t : F32) : F32), aok && bok && ok}

# p - (cosf, sinf)*length
def Pt.back(+p: Pt, +length: F32, +t: Turn) -> Pt:
  Pt{x, y, ok} = p
  Turn{c, s, tok} = t
  Pt{(x - (c * length : F32) : F32), (y - (s * length : F32) : F32), ok && tok}

def P2.minus(+a: P2, +b: P2) -> P2:
  P2{ax, ay} = a
  P2{bx, by} = b
  P2{(ax - bx : F32), (ay - by : F32)}

# raymath's Vector2Rotate with given cosf/sinf: (c*x - s*y, s*x + c*y).
def P2.rotate(+v: P2, +t: Turn) -> P2:
  P2{x, y} = v
  Turn{c, s, _} = t
  P2{((c * x : F32) - (s * y : F32) : F32), ((s * x : F32) + (c * y : F32) : F32)}

# The quads of these outlines: texcoords (u0, v1), (u0, v0), (u1, v0), (u1, v1).
def Pt.quad(+a: Pt, +b: Pt, +c: Pt, +d: Pt) -> Plan:
  Plan.only(Pt.ok(a) && Pt.ok(b) && Pt.ok(c) && Pt.ok(d), [F.ShapeUV{2}, Pt.point(a), F.ShapeUV{0}, Pt.point(b),
    F.ShapeUV{1}, Pt.point(c), F.ShapeUV{3}, Pt.point(d)])

# C int arithmetic on integral F32 counts: n/2 (toward zero), n%2 == 1 and a
# loop count (0 for a negative one).
def tally.half(+n: F32) -> F32:
  F32.trunc((n / 2.0 : F32))

def tally.odd(+n: F32) -> Bool:
  F32.is_eq((n - (tally.half(n) * 2.0 : F32) : F32), 1.0)

def tally.nat(+n: F32) -> Nat:
  U32.to_nat(F32.to_u32(Bool.pick(F32, (n > 0.0 : F32), n, 0.0)))

# The angle after n F32 increments.
def turned.after(n: Nat, +a: F32, +step: F32) -> F32:
  match n:
    case 0n: a
    case 1n+k: turned.after(k, (a + step : F32), step)

# The outline: a quad per segment between the outer and inner radii.
def band.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +outer: F32, +inner: F32, +angle: F32, +step: F32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      Plan.join(Pt.quad(Pt.on(gnu, cx, cy, outer, angle), Pt.on(gnu, cx, cy, inner, angle), Pt.on(gnu, cx, cy, inner, (angle + step : F32)),
        Pt.on(gnu, cx, cy, outer, (angle + step : F32))), band.loop(k, gnu, cx, cy, outer, inner, (angle + step : F32), step))

# The cap vertices C0..C5 of the sketch in rshapes.c, the steps before C1,
# whether S1 lies outside the circle and the steps before C0.
type Cap is Data:
  Cap{c0: Pt, c1: Pt, c2: Pt, c3: Pt, c4: Pt, c5: Pt, before: F32, outside: Bool, before0: F32}

def Cap.none() -> Cap:
  Cap{Pt{0.0, 0.0, True{}}, Pt{0.0, 0.0, True{}}, Pt{0.0, 0.0, True{}}, Pt{0.0, 0.0, True{}}, Pt{0.0, 0.0, True{}}, Pt{0.0, 0.0, True{}},
    0.0, False{}, 0.0}

# The gaps between the caps and the inner edge: pairs of steps from each end,
# then an odd last one.
def gap.odd(odd: Bool, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +c1: Pt, +c4: Pt, +angle: F32) -> Plan:
  match odd:
    case False{}: Plan.empty()
    case True{}:
      Plan.join(Pt.quad(c1, c1, Pt.on(gnu, cx, cy, r, (start + (angle + step : F32) : F32)), Pt.on(gnu, cx, cy, r, (start + angle : F32))),
        Pt.quad(c4, c4, Pt.on(gnu, cx, cy, r, (end - angle : F32)), Pt.on(gnu, cx, cy, r, (end - (angle + step : F32) : F32))))

def gap.pairs(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +c1: Pt, +c4: Pt, +odd: Bool, +angle: F32) -> Plan:
  match n:
    case 0n: gap.odd(odd, gnu, cx, cy, r, start, end, step, c1, c4, angle)
    case 1n+k:
      +twice = (step * 2.0 : F32)
      Plan.join(Pt.quad(c1, Pt.on(gnu, cx, cy, r, (start + (angle + twice : F32) : F32)), Pt.on(gnu, cx, cy, r, (start + (angle + step : F32) : F32)),
          Pt.on(gnu, cx, cy, r, (start + angle : F32))),
        Plan.join(Pt.quad(c4, Pt.on(gnu, cx, cy, r, (end - angle : F32)), Pt.on(gnu, cx, cy, r, (end - (angle + step : F32) : F32)),
          Pt.on(gnu, cx, cy, r, (end - (angle + twice : F32) : F32))), gap.pairs(k, gnu, cx, cy, r, start, end, step, c1, c4, odd, (angle + twice : F32))))

# The wedges between C0, C3 and the inner edge when S1 lies outside the circle.
def wedge.odd(odd: Bool, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +step: F32, +angle: F32) -> Plan:
  match odd:
    case False{}: Plan.empty()
    case True{}: Pt.quad(Pt.center(cx, cy), Pt.center(cx, cy), Pt.on(gnu, cx, cy, r, (angle + step : F32)), Pt.on(gnu, cx, cy, r, angle))

def wedge.pairs(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +step: F32, +odd: Bool, +angle: F32) -> Plan:
  match n:
    case 0n: wedge.odd(odd, gnu, cx, cy, r, step, angle)
    case 1n+k:
      +twice = (step * 2.0 : F32)
      Plan.join(Pt.quad(Pt.center(cx, cy), Pt.on(gnu, cx, cy, r, (angle + twice : F32)), Pt.on(gnu, cx, cy, r, (angle + step : F32)), Pt.on(gnu, cx, cy, r, angle)),
        wedge.pairs(k, gnu, cx, cy, r, step, odd, (angle + twice : F32)))

def wedge.between(closed: Bool, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +before0: F32, +between: F32, +c0: Pt, +c3: Pt) -> Plan:
  match closed:
    case True{}: Pt.quad(Pt.center(cx, cy), Pt.center(cx, cy), c3, c0)
    case False{}:
      +first = (step * (before0 + 1.0 : F32) : F32)
      +rest = (between - 1.0 : F32)
      Plan.join(Pt.quad(Pt.center(cx, cy), Pt.center(cx, cy), Pt.on(gnu, cx, cy, r, (start + first : F32)), c0),
        Plan.join(Pt.quad(Pt.center(cx, cy), Pt.center(cx, cy), c3, Pt.on(gnu, cx, cy, r, (end - first : F32))),
          wedge.pairs(tally.nat(tally.half(rest)), gnu, cx, cy, r, step, tally.odd(rest), (start + first : F32))))

def sector_ex.outside(outside: Bool, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +before0: F32, +c0: Pt, +c3: Pt) -> Plan:
  match outside:
    case False{}: Plan.empty()
    case True{}:
      +between = ((n - (before0 * 2.0 : F32) : F32) - 1.0 : F32)
      wedge.between(F32.is_eq(between, 0.0), gnu, cx, cy, r, start, end, step, before0, between, c0, c3)

def sector_ex.gap(gapped: Bool, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +before: F32, +c1: Pt, +c4: Pt) -> Plan:
  match gapped:
    case False{}: Plan.empty()
    case True{}: gap.pairs(tally.nat(tally.half(before)), gnu, cx, cy, r, start, end, step, c1, c4, tally.odd(before), 0.0)

def sector_ex.filled(positive: Bool, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +c0: Pt, +c1: Pt, +c3: Pt, +c4: Pt,
    +before: F32, +outside: Bool, +before0: F32) -> Plan:
  match positive:
    case False{}: Plan.empty()
    case True{}:
      Plan.join(sector_ex.gap((before > 0.0 : F32), gnu, cx, cy, r, start, end, step, before, c1, c4),
        sector_ex.outside(outside, gnu, cx, cy, r, start, end, step, n, before0, c0, c3))

# The two cap quads (center, C0, C1, C2) and (center, C5, C4, C3), then for
# a thickness >= 0 the gaps; r is the inner radius.
def sector_ex.capped(cap: Cap, +positive: Bool, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32) -> Plan:
  Cap{+c0, +c1, +c2, +c3, +c4, +c5, +before, +outside, +before0} = cap
  Plan.join(Pt.quad(Pt.center(cx, cy), c0, c1, c2), Plan.join(Pt.quad(Pt.center(cx, cy), c5, c4, c3),
    sector_ex.filled(positive, gnu, cx, cy, r, start, end, step, n, c0, c1, c3, c4, before, outside, before0)))

def sector_ex.drawn(caps: Bool, +gnu: Bool, +cx: F32, +cy: F32, +outer: F32, +inner: F32, +start: F32, +end: F32, +step: F32, +n: F32, +positive: Bool,
    +cap: Cap, +color: U32) -> Plan:
  match caps:
    case False{}: Plan.textured(4, Plan.prefix(F.Color{color}, band.loop(tally.nat(n), gnu, cx, cy, outer, inner, start, step)))
    case True{}:
      Plan.textured(4, Plan.prefix(F.Color{color}, Plan.join(band.loop(tally.nat(n), gnu, cx, cy, outer, inner, start, step),
        sector_ex.capped(cap, positive, gnu, cx, cy, inner, start, end, step, n))))

# A thickness >= 0: DrawCircleSector when the caps cover the sector, else the
# outline with C2 and C5 on the inner radius at the ends.
def sector_ex.fold(fill: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +inner: F32,
    +c0: Pt, +c1: Pt, +c3: Pt, +c4: Pt, +before: F32, +outside: Bool, +before0: F32, +color: U32) -> Plan:
  match fill:
    case True{}: sector(lm, cx, cy, r, start, end, n, color)
    case False{}:
      sector_ex.drawn(True{}, gnu, cx, cy, r, inner, start, end, step, n, True{},
        Cap{c0, c1, Pt.on(gnu, cx, cy, inner, start), c3, c4, Pt.on(gnu, cx, cy, inner, end), before, outside, before0}, color)

# S1 outside the circle: C0 and C3 where the cap edges meet the inner edge,
# stepsBeforeC0 = (int)((180 + RAD2DEG*asinf(thick/-inner))/stepLength).
def sector_ex.c0.at(+lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32, +inner: F32,
    +before: F32, +c1: Pt, +c4: Pt, +before0: F32, +color: U32) -> Plan:
  +vb = (step * before0 : F32)
  +va = (step * (before0 + 1.0 : F32) : F32)
  +t = Num.cut(turn.at(gnu, (deg2rad() * vb : F32)), turn.at(gnu, (deg2rad() * va : F32)), inner, thick)
  sector_ex.fold(False{}, lm, gnu, cx, cy, r, start, end, step, n, inner,
    Pt.lerp(Pt.on(gnu, cx, cy, inner, (start + vb : F32)), Pt.on(gnu, cx, cy, inner, (start + va : F32)), Num.v(t), Num.ok(t)), c1,
    Pt.lerp(Pt.on(gnu, cx, cy, inner, (end - vb : F32)), Pt.on(gnu, cx, cy, inner, (end - va : F32)), Num.v(t), Num.ok(t)), c4, before, True{}, before0, color)

def sector_ex.c0(angle: Maybe<F32>, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32,
    +inner: F32, +before: F32, +c1: Pt, +c4: Pt, +color: U32) -> Plan:
  match angle:
    case None{}: Plan.refused()
    case Some{+a}:
      +ratio = ((180.0 + (rad2deg() * a : F32) : F32) / step : F32)
      Plan.require(int.valid(ratio), sector_ex.c0.at(lm, gnu, cx, cy, r, start, end, step, n, thick, inner, before, c1, c4,
        int.of(Bool.pick(F32, int.valid(ratio), ratio, 0.0)), color))

# S1 outside the circle: a span <= 180 degrees is covered (DrawCircleSector).
def sector_ex.beyond(fill: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32,
    +inner: F32, +before: F32, +c1: Pt, +c4: Pt, +color: U32) -> Plan:
  match fill:
    case True{}: sector(lm, cx, cy, r, start, end, n, color)
    case False{}: sector_ex.c0(arcsine.of(lm, (thick / F32.neg(inner) : F32)), lm, gnu, cx, cy, r, start, end, step, n, thick, inner, before, c1, c4, color)

# atan2f(det, dot) of C1 - center against C0 - center (Vector2Angle).
def sector_ex.turning(+c0: Pt, +c1: Pt, +cx: F32, +cy: F32, +lm: U32) -> Maybe<F32>:
  Pt{x0, y0, _} = c0
  Pt{x1, y1, _} = c1
  +px = (x1 - cx : F32)
  +py = (y1 - cy : F32)
  +qx = (x0 - cx : F32)
  +qy = (y0 - cy : F32)
  arctan2.of(lm, ((px * qy : F32) - (py * qx : F32) : F32), ((px * qx : F32) + (py * qy : F32) : F32))

# S1 inside the circle: C0 = C3 = S1; a negative angle from C1 to S1 means
# the caps cover the sector.
def sector_ex.s1in(angle: Maybe<F32>, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +inner: F32,
    +before: F32, +c0: Pt, +c1: Pt, +c4: Pt, +color: U32) -> Plan:
  match angle:
    case None{}: Plan.refused()
    case Some{+a}:
      Plan.require(Pt.ok(c0) && Pt.ok(c1), sector_ex.fold((a < 0.0 : F32), lm, gnu, cx, cy, r, start, end, step, n, inner, c0, c1, c0, c4, before,
        False{}, 0.0, color))

def sector_ex.inside(inside: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32,
    +inner: F32, +before: F32, +s1: F32, +c1: Pt, +c4: Pt, +color: U32) -> Plan:
  match inside:
    case True{}:
      +c0 = Pt.at(gnu, cx, cy, s1, s1, (deg2rad() * ((end + start : F32) / 2.0 : F32) : F32))
      sector_ex.s1in(sector_ex.turning(c0, c1, cx, cy, lm), lm, gnu, cx, cy, r, start, end, step, n, inner, before, c0, c1, c4, color)
    case False{}: sector_ex.beyond(((end - start : F32) <= 180.0 : F32), lm, gnu, cx, cy, r, start, end, step, n, thick, inner, before, c1, c4, color)

# S1 (where the inner cap edges meet) is thick/cosf(DEG2RAD*a) from the
# center, a = ((end - 90) - (start + 90))/2.
def sector_ex.s1(t: Turn, +a: F32, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32,
    +inner: F32, +before: F32, +c1: Pt, +c4: Pt, +color: U32) -> Plan:
  Turn{c, _, ok} = t
  +s1 = (thick / c : F32)
  Plan.require(ok, sector_ex.inside((a < 90.0 : F32) && (s1 <= inner : F32), lm, gnu, cx, cy, r, start, end, step, n, thick, inner, before, s1, c1, c4, color))

# C1 and C4: thick away from the start and end edges on the inner edge, on
# the segment after stepsBeforeC1 steps.
def sector_ex.c1.at(+lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32, +inner: F32,
    +before: F32, +color: U32) -> Plan:
  +vb = (step * before : F32)
  +va = (step * (before + 1.0 : F32) : F32)
  +t = Num.cut(turn.at(gnu, (deg2rad() * vb : F32)), turn.at(gnu, (deg2rad() * va : F32)), inner, thick)
  +c1 = Pt.lerp(Pt.on(gnu, cx, cy, inner, (start + vb : F32)), Pt.on(gnu, cx, cy, inner, (start + va : F32)), Num.v(t), Num.ok(t))
  +c4 = Pt.lerp(Pt.on(gnu, cx, cy, inner, (end - vb : F32)), Pt.on(gnu, cx, cy, inner, (end - va : F32)), Num.v(t), Num.ok(t))
  +a = (((end - 90.0 : F32) - (start + 90.0 : F32) : F32) / 2.0 : F32)
  sector_ex.s1(turn.at(gnu, (deg2rad() * a : F32)), a, lm, gnu, cx, cy, r, start, end, step, n, thick, inner, before, c1, c4, color)

def sector_ex.steps(fill: Bool, +valid: Bool, +before: F32, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32,
    +n: F32, +thick: F32, +inner: F32, +color: U32) -> Plan:
  match fill:
    case True{}: sector(lm, cx, cy, r, start, end, n, color)
    case False{}: Plan.require(valid, sector_ex.c1.at(lm, gnu, cx, cy, r, start, end, step, n, thick, inner, before, color))

# c1Angle = RAD2DEG*asinf(thick/inner); c1Angle/stepLength >= segments covers
# the sector, otherwise stepsBeforeC1 = (int)(c1Angle/stepLength).
def sector_ex.c1(angle: Maybe<F32>, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32,
    +inner: F32, +color: U32) -> Plan:
  match angle:
    case None{}: Plan.refused()
    case Some{+a}:
      +ratio = ((rad2deg() * a : F32) / step : F32)
      sector_ex.steps((ratio >= n : F32), int.valid(ratio), int.of(Bool.pick(F32, int.valid(ratio), ratio, 0.0)), lm, gnu, cx, cy, r, start, end, step, n,
        thick, inner, color)

# A negative thickness, the caps crossing: C1 = C4 = C0 = C3 where the line
# of the end cap meets cap 1, found in a frame rotated by the atan2f of the
# first outer edge.
def sector_ex.meet.at(theta: Maybe<F32>, +gnu: Bool, +u1: P2, +v3: P2, +v4: P2, +c1t: P2, +ok: Bool) -> Num:
  match theta:
    case None{}: Num{0.0, False{}}
    case Some{+a}:
      +spin = turn.at(gnu, F32.neg(a))
      +r1 = P2.rotate(u1, spin)
      +r3 = P2.rotate(v3, spin)
      +r4 = P2.rotate(v4, spin)
      +rc = P2.rotate(c1t, spin)
      +target = (P2.x(r3) + ((F32.neg(P2.y(r3)) / (P2.y(r3) - P2.y(r4) : F32) : F32) * (P2.x(r3) - P2.x(r4) : F32) : F32) : F32)
      Num{((P2.x(rc) - target : F32) / (P2.x(rc) - P2.x(r1) : F32) : F32), ok && Turn.ok(spin)}

def sector_ex.meet(+lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +end: F32, +step: F32, +outer: F32, +c5: Pt, +c0t: P2, +v1: P2, +v2: P2, +dist: F32,
    +back: Turn) -> Num:
  +along = turn.at(gnu, (deg2rad() * (end - step : F32) : F32))
  +v3 = P2.minus(P2.rotate(P2.of((Pt.x(c5) - cx : F32), (Pt.y(c5) - cy : F32)), back), v2)
  +v4 = P2.minus(P2.rotate(P2.of((Turn.cos(along) * outer : F32), (Turn.sin(along) * outer : F32)), back), v2)
  +u1 = P2.minus(v1, v2)
  sector_ex.meet.at(arctan2.of(lm, P2.y(u1), P2.x(u1)), gnu, u1, v3, v4, P2.minus(P2.of((P2.x(c0t) + dist : F32), P2.y(c0t)), v2),
    Turn.ok(along) && Pt.ok(c5))

# A negative thickness: the caps (C0..C5 swapped for the winding) outside the
# sector.
def sector_ex.crossed(cross: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +n: F32, +outer: F32, +inner: F32,
    +c0: Pt, +c1: Pt, +c2: Pt, +c4: Pt, +c5: Pt, +c0t: P2, +v1: P2, +v2: P2, +dist: F32, +back: Turn, +color: U32) -> Plan:
  match cross:
    case False{}: sector_ex.drawn(True{}, gnu, cx, cy, outer, inner, start, end, step, n, False{}, Cap{c2, c1, c0, c5, c4, c0, 0.0, False{}, 0.0}, color)
    case True{}:
      +t = sector_ex.meet(lm, gnu, cx, cy, end, step, outer, c5, c0t, v1, v2, dist, back)
      +m = Pt.lerp(c1, c2, Num.v(t), Num.ok(t))
      sector_ex.drawn(True{}, gnu, cx, cy, outer, inner, start, end, step, n, False{}, Cap{c2, m, m, c5, m, m, 0.0, False{}, 0.0}, color)

# In the frame where the center is the origin and startAngle is 0 degrees,
# C1 is c1DistanceFromC0 from C0 along the start edge, where the horizontal
# line through C0 meets the first outer edge.
def sector_ex.rotated(+c0: Pt, +c2: Pt, +c5: Pt, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +n: F32, +outer: F32,
    +inner: F32, +color: U32) -> Plan:
  +back = turn.at(gnu, (F32.neg(deg2rad()) * start : F32))
  +along = turn.at(gnu, (deg2rad() * (start + step : F32) : F32))
  +c0t = P2.rotate(P2.of((Pt.x(c0) - cx : F32), (Pt.y(c0) - cy : F32)), back)
  +v1 = P2.rotate(P2.of((Pt.x(c2) - cx : F32), (Pt.y(c2) - cy : F32)), back)
  +v2 = P2.rotate(P2.of((Turn.cos(along) * outer : F32), (Turn.sin(along) * outer : F32)), back)
  +dist = ((P2.x(v1) + (((P2.y(c0t) - P2.y(v1) : F32) / (P2.y(v1) - P2.y(v2) : F32) : F32) * (P2.x(v1) - P2.x(v2) : F32) : F32) : F32) - P2.x(c0t) : F32)
  +c1 = Pt.also(Pt.at(gnu, Pt.x(c0), Pt.y(c0), dist, dist, (deg2rad() * start : F32)), Pt.ok(c0))
  +c4 = Pt.also(Pt.at(gnu, Pt.x(c0), Pt.y(c0), dist, dist, (deg2rad() * end : F32)), Pt.ok(c0))
  Plan.require(Turn.ok(back) && Turn.ok(along) && Pt.ok(c0) && Pt.ok(c2), sector_ex.crossed((dist < 0.0 : F32), lm, gnu, cx, cy, start, end, step, n,
    outer, inner, c0, c1, c2, c4, c5, c0t, v1, v2, dist, back, color))

# S1 = C0 = C3 on the far side: thick/cosf(DEG2RAD*a) from the center at
# 180 + (end + start)/2, a = ((end + 90) - (start - 90))/2.
def sector_ex.negative.s1(t: Turn, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32, +outer: F32,
    +inner: F32, +color: U32) -> Plan:
  Turn{c, _, ok} = t
  +s1 = (thick / c : F32)
  Plan.require(ok, sector_ex.rotated(Pt.at(gnu, cx, cy, s1, s1, (deg2rad() * (180.0 + ((end + start : F32) / 2.0 : F32) : F32) : F32)),
    Pt.on(gnu, cx, cy, outer, start), Pt.on(gnu, cx, cy, outer, end), lm, gnu, cx, cy, start, end, step, n, outer, inner, color))

def sector_ex.negative(+lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32, +outer: F32, +inner: F32,
    +color: U32) -> Plan:
  +a = (((end + 90.0 : F32) - (start - 90.0 : F32) : F32) / 2.0 : F32)
  sector_ex.negative.s1(turn.at(gnu, (deg2rad() * a : F32)), lm, gnu, cx, cy, start, end, step, n, thick, outer, inner, color)

def sector_ex.sign(positive: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32,
    +outer: F32, +inner: F32, +color: U32) -> Plan:
  match positive:
    case True{}: sector_ex.c1(arcsine.of(lm, (thick / inner : F32)), lm, gnu, cx, cy, r, start, end, step, n, thick, inner, color)
    case False{}: sector_ex.negative(lm, gnu, cx, cy, start, end, step, n, thick, outer, inner, color)

def sector_ex.shown(caps: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32,
    +positive: Bool, +outer: F32, +inner: F32, +color: U32) -> Plan:
  match caps:
    case False{}: sector_ex.drawn(False{}, gnu, cx, cy, outer, inner, start, end, step, n, positive, Cap.none(), color)
    case True{}: sector_ex.sign(positive, lm, gnu, cx, cy, r, start, end, step, n, thick, outer, inner, color)

def sector_ex.sides(fill: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32,
    +caps: Bool, +positive: Bool, +outer: F32, +inner: F32, +color: U32) -> Plan:
  match fill:
    case True{}: sector(lm, cx, cy, r, start, end, n, color)
    case False{}: sector_ex.shown(caps, lm, gnu, cx, cy, r, start, end, step, n, thick, positive, outer, inner, color)

# radiusThick = thick*(radius/apothem), apothem =
# radius*cosf(DEG2RAD*((end - start)/2)/segments); the inner radius is
# radius - radiusThick (the outer one for a negative thickness). A thickness
# >= 0 reaching the inner radius draws DrawCircleSector.
def sector_ex.apothem(t: Turn, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32,
    +caps: Bool, +color: U32) -> Plan:
  Turn{c, _, ok} = t
  +inner = (r - (thick * (r / (r * c : F32) : F32) : F32) : F32)
  +positive = (thick >= 0.0 : F32)
  Plan.require(ok, sector_ex.sides(positive && (thick >= inner : F32), lm, gnu, cx, cy, r, start, end, step, n, thick, caps, positive,
    Bool.pick(F32, positive, r, inner), Bool.pick(F32, positive, inner, r), color))

def sector_ex.counted(count: Maybe<F32>, +lm: U32, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +thick: F32, +caps: Bool, +color: U32) -> Plan:
  match count:
    case None{}: Plan.refused()
    case Some{+n}:
      sector_ex.apothem(turn.at(gnu.of(lm), ((deg2rad() * ((end - start : F32) / 2.0 : F32) : F32) / n : F32)), lm, gnu.of(lm), cx, cy, r, start, end,
        ((end - start : F32) / n : F32), n, thick, caps, color)

def sector_ex.distinct(skip: Bool, +lm: U32, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +segments: F32, +thick: F32, +color: U32) -> Plan:
  match skip:
    case True{}: Plan.empty()
    case False{}:
      +swap = (end < start : F32)
      +first = Bool.pick(F32, swap, end, start)
      +last = Bool.pick(F32, swap, start, end)
      +ending = arc.end(first, last)
      sector_ex.counted(segments.resolve(lm, r, (ending - first : F32), segments), lm, cx, cy, r, first, ending, thick,
        arc.caps(arc.full(first, last), (thick >= 0.0 : F32)), color)

# DrawCircleSectorLinesEx (raylib 6.2): as DrawCircleSectorLines (nothing
# for a radius <= 0, one turn at most, segments resolved alike), a band of
# quads between the radius and radius - radiusThick, and cap quads unless a
# negative thickness draws a whole turn. A thickness >= 0 covering the
# sector draws DrawCircleSector instead.
def sector_lines_ex(+lm: U32, +cx: F32, +cy: F32, +radius: F32, +start: F32, +end: F32, +segments: F32, +thick: F32, +color: U32) -> Plan:
  sector_ex.distinct(F32.is_eq(start, end) || (radius <= 0.0 : F32), lm, cx, cy, radius, start, end, segments, thick, color)

# DrawRingLinesEx's two outlines (the inner radius's band between ii and oi,
# the outer radius's between io and oo), a pair of quads per segment.
def rings.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +ii: F32, +oi: F32, +io: F32, +oo: F32, +angle: F32, +step: F32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +next = (angle + step : F32)
      Plan.join(Pt.quad(Pt.on(gnu, cx, cy, oi, angle), Pt.on(gnu, cx, cy, ii, angle), Pt.on(gnu, cx, cy, ii, next), Pt.on(gnu, cx, cy, oi, next)),
        Plan.join(Pt.quad(Pt.on(gnu, cx, cy, oo, angle), Pt.on(gnu, cx, cy, io, angle), Pt.on(gnu, cx, cy, io, next), Pt.on(gnu, cx, cy, oo, next)),
          rings.loop(k, gnu, cx, cy, ii, oi, io, oo, next, step)))

def ring_ex.drawn(+gnu: Bool, +cx: F32, +cy: F32, +start: F32, +step: F32, +n: F32, +ii: F32, +oi: F32, +io: F32, +oo: F32, caps: Plan, +color: U32) -> Plan:
  Plan.textured(4, Plan.prefix(F.Color{color}, Plan.join(rings.loop(tally.nat(n), gnu, cx, cy, ii, oi, io, oo, start, step), caps)))

# A thickness >= 0: the steps from each end before the outer radius's cap
# end, a quad between oi and io per step.
def ring_ex.early(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +oi: F32, +io: F32, +angle: F32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +s0 = (start + angle : F32)
      +e0 = (end - angle : F32)
      Plan.join(Pt.quad(Pt.on(gnu, cx, cy, oi, s0), Pt.on(gnu, cx, cy, oi, (s0 + step : F32)), Pt.on(gnu, cx, cy, io, (s0 + step : F32)), Pt.on(gnu, cx, cy, io, s0)),
        Plan.join(Pt.quad(Pt.on(gnu, cx, cy, oi, e0), Pt.on(gnu, cx, cy, io, e0), Pt.on(gnu, cx, cy, io, (e0 - step : F32)), Pt.on(gnu, cx, cy, oi, (e0 - step : F32))),
          ring_ex.early(k, gnu, cx, cy, start, end, step, oi, io, (angle + step : F32))))

# Each cap's vertices around its end: on the outer radius's inner edge (io)
# the vertex before the end and the end, on the inner radius's outer edge
# (oi) the end and the vertex before it.
type Ends is Data:
  Ends{ob1: Pt, ib1: Pt, ie1: Pt, oe1: Pt, ob2: Pt, ib2: Pt, ie2: Pt, oe2: Pt}

def ring_ex.ends.of(+gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +oi: F32, +io: F32, +a1: F32, +left: F32, +tin: Num, +tout: Num) -> Ends:
  +s0 = (start + a1 : F32)
  +e0 = (end - a1 : F32)
  +ob1 = Pt.on(gnu, cx, cy, io, s0)
  +ib1 = Pt.on(gnu, cx, cy, oi, (s0 + (left * step : F32) : F32))
  +ob2 = Pt.on(gnu, cx, cy, io, e0)
  +ib2 = Pt.on(gnu, cx, cy, oi, (e0 - (left * step : F32) : F32))
  Ends{ob1, ib1, Pt.lerp(ib1, Pt.on(gnu, cx, cy, oi, (s0 + ((left + 1.0 : F32) * step : F32) : F32)), Num.v(tin), Num.ok(tin)),
    Pt.lerp(ob1, Pt.on(gnu, cx, cy, io, (s0 + step : F32)), Num.v(tout), Num.ok(tout)),
    ob2, ib2, Pt.lerp(ib2, Pt.on(gnu, cx, cy, oi, (e0 - ((left + 1.0 : F32) * step : F32) : F32)), Num.v(tin), Num.ok(tin)),
    Pt.lerp(ob2, Pt.on(gnu, cx, cy, io, (e0 - step : F32)), Num.v(tout), Num.ok(tout))}

def ring_ex.odd(odd: Bool, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +oi: F32, +ob1: Pt, +ob2: Pt, +angle: F32) -> Plan:
  match odd:
    case False{}: Plan.empty()
    case True{}:
      Plan.join(Pt.quad(ob1, ob1, Pt.on(gnu, cx, cy, oi, (start + angle : F32)), Pt.on(gnu, cx, cy, oi, ((start + angle : F32) + step : F32))),
        Pt.quad(ob2, ob2, Pt.on(gnu, cx, cy, oi, ((end - angle : F32) - step : F32)), Pt.on(gnu, cx, cy, oi, (end - angle : F32))))

# Pairs of steps fanned from the vertex before each outer cap end, then an
# odd last one.
def ring_ex.pairs(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +oi: F32, +ob1: Pt, +ob2: Pt, +odd: Bool, +angle: F32) -> Plan:
  match n:
    case 0n: ring_ex.odd(odd, gnu, cx, cy, start, end, step, oi, ob1, ob2, angle)
    case 1n+k:
      +s0 = (start + angle : F32)
      +e0 = (end - angle : F32)
      +twice = (step * 2.0 : F32)
      Plan.join(Pt.quad(ob1, Pt.on(gnu, cx, cy, oi, s0), Pt.on(gnu, cx, cy, oi, (s0 + step : F32)), Pt.on(gnu, cx, cy, oi, (s0 + twice : F32))),
        Plan.join(Pt.quad(ob2, Pt.on(gnu, cx, cy, oi, (e0 - twice : F32)), Pt.on(gnu, cx, cy, oi, (e0 - step : F32)), Pt.on(gnu, cx, cy, oi, e0)),
          ring_ex.pairs(k, gnu, cx, cy, start, end, step, oi, ob1, ob2, odd, (angle + twice : F32))))

# sinf(rotateBy)*(p.x - o.x) + cosf(rotateBy)*(p.y - o.y)
def ring_ex.lift(+t: Turn, +p: Pt, +o: Pt) -> F32:
  Turn{c, s, _} = t
  ((s * (Pt.x(p) - Pt.x(o) : F32) : F32) + (c * (Pt.y(p) - Pt.y(o) : F32) : F32) : F32)

# The crossing inner angles: the caps meet at the intersection of their end
# lines; an even segment count shares the middle vertex, an odd one adds a
# quad between the two middle vertices.
def ring_ex.middle(odd: Bool, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +oi: F32, +angle: F32, +hit: Pt, +ob1: Pt, +oe1: Pt, +ob2: Pt,
    +oe2: Pt) -> Plan:
  match odd:
    case False{}:
      +mid = Pt.on(gnu, cx, cy, oi, (start + angle : F32))
      Plan.join(Pt.quad(hit, oe1, ob1, mid), Pt.quad(hit, mid, ob2, oe2))
    case True{}:
      +m1 = Pt.on(gnu, cx, cy, oi, (start + angle : F32))
      +m2 = Pt.on(gnu, cx, cy, oi, (end - angle : F32))
      Plan.join(Pt.quad(hit, oe1, ob1, m1), Plan.join(Pt.quad(hit, m2, ob2, oe2), Pt.quad(hit, hit, m1, m2)))

def ring_ex.cross(theta: Maybe<F32>, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +n: F32, +oi: F32, +angle: F32, +ob1: Pt, +ie1: Pt,
    +oe1: Pt, +ob2: Pt, +ie2: Pt, +oe2: Pt) -> Plan:
  match theta:
    case None{}: Plan.refused()
    case Some{+a}:
      +spin = turn.at(gnu, F32.neg(a))
      +s = ring_ex.lift(spin, ie2, ie1)
      +e = ring_ex.lift(spin, oe2, ie1)
      ring_ex.middle(tally.odd(n), gnu, cx, cy, start, end, oi, angle,
        Pt.lerp(ie2, oe2, (s / (s - e : F32) : F32), Turn.ok(spin) && Pt.ok(ie1) && Pt.ok(oe1)), ob1, oe1, ob2, oe2)

def ring_ex.meet(cross: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +n: F32, +oi: F32, +angle: F32, +ob1: Pt, +ib1: Pt,
    +ie1: Pt, +oe1: Pt, +ob2: Pt, +ib2: Pt, +ie2: Pt, +oe2: Pt) -> Plan:
  match cross:
    case False{}: Plan.join(Pt.quad(ob1, ib1, ie1, oe1), Pt.quad(ob2, oe2, ie2, ib2))
    case True{}:
      ring_ex.cross(arctan2.of(lm, (Pt.y(oe1) - Pt.y(ie1) : F32), (Pt.x(oe1) - Pt.x(ie1) : F32)), gnu, cx, cy, start, end, n, oi, angle, ob1, ie1, oe1,
        ob2, ie2, oe2)

def ring_ex.ends(e: Ends, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +n: F32, +oi: F32, +cross: Bool, +steps: F32,
    +a1: F32) -> Plan:
  Ends{+ob1, +ib1, +ie1, +oe1, +ob2, +ib2, +ie2, +oe2} = e
  +a2 = turned.after(tally.nat(tally.half(steps)), a1, (step * 2.0 : F32))
  +odd = tally.odd(steps)
  Plan.join(ring_ex.pairs(tally.nat(tally.half(steps)), gnu, cx, cy, start, end, step, oi, ob1, ob2, odd, a1),
    ring_ex.meet(cross, lm, gnu, cx, cy, start, end, n, oi, Bool.pick(F32, odd, (a2 + step : F32), a2), ob1, ib1, ie1, oe1, ob2, ib2, ie2, oe2))

# A thickness >= 0 with caps: stepsBeforeInner and stepsBeforeOuter whole
# steps fit in the caps' angles; where each cap end crosses its segment
# (tInner, tOuter) comes from the frame where the cap angle is 0 degrees.
def ring_ex.steps(+lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +n: F32, +ii: F32, +oi: F32, +io: F32, +oo: F32,
    +ain: F32, +aout: F32, +cross: Bool, +sbi: F32, +sbo: F32, +color: U32) -> Plan:
  +tin = Num.cut(turn.at(gnu, (deg2rad() * ((sbi * step : F32) - ain : F32) : F32)), turn.at(gnu, (deg2rad() * (((sbi + 1.0 : F32) * step : F32) - ain : F32) : F32)), oi, 0.0)
  +tout = Num.cut(turn.at(gnu, (deg2rad() * ((sbo * step : F32) - aout : F32) : F32)), turn.at(gnu, (deg2rad() * (((sbo + 1.0 : F32) * step : F32) - aout : F32) : F32)), io, 0.0)
  +a1 = turned.after(tally.nat(sbo), 0.0, step)
  +left = (sbi - sbo : F32)
  +steps = Bool.pick(F32, cross, tally.half((n - (sbo * 2.0 : F32) : F32)), left)
  Plan.require((steps <= 4096.0 : F32), ring_ex.drawn(gnu, cx, cy, start, step, n, ii, oi, io, oo,
    Plan.join(ring_ex.early(tally.nat(sbo), gnu, cx, cy, start, end, step, oi, io, 0.0),
      ring_ex.ends(ring_ex.ends.of(gnu, cx, cy, start, end, step, oi, io, a1, left, tin, tout), lm, gnu, cx, cy, start, end, step, n, oi, cross, steps, a1)), color))

# A span below twice the outer cap angle is covered (DrawRing); below twice
# the inner one the inner angles cross each other.
def ring_ex.thin(fill: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +n: F32, +ii: F32, +oi: F32, +io: F32,
    +oo: F32, +ain: F32, +aout: F32, +color: U32) -> Plan:
  match fill:
    case True{}: ring(lm, cx, cy, ii, oo, start, end, n, color)
    case False{}:
      +ri = (ain / step : F32)
      +ro = (aout / step : F32)
      Plan.require(int.valid(ri) && int.valid(ro), ring_ex.steps(lm, gnu, cx, cy, start, end, step, n, ii, oi, io, oo, ain, aout,
        ((end - start : F32) < (ain * 2.0 : F32) : F32), int.of(Bool.pick(F32, int.valid(ri), ri, 0.0)), int.of(Bool.pick(F32, int.valid(ro), ro, 0.0)), color))

# x*cosres - y*sinres
def ring_ex.xr(+x: F32, +y: F32, +t: Turn) -> F32:
  Turn{c, s, _} = t
  ((x * c : F32) - (y * s : F32) : F32)

# (a - b)/divisor, or -1 for a zero divisor.
def ring_ex.ratio(+a: F32, +b: F32, +divisor: F32) -> F32:
  Bool.pick(F32, F32.is_eq(divisor, 0.0), F32.neg(1.0), ((a - b : F32) / divisor : F32))

def ring_ex.outward.hit(inter: Bool, +si1: Pt, +so1: Pt, +si2: Pt, +so2: Pt, +hit: Pt) -> Plan:
  match inter:
    case False{}: Plan.empty()
    case True{}: Plan.join(Pt.quad(si1, si1, so1, hit), Pt.quad(si2, hit, so2, si2))

def ring_ex.outward.draw(inter: Bool, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +ii: F32, +oo: F32, +ok: Bool, +so1: Pt, +si1: Pt,
    +so2: Pt, +si2: Pt, +hit: Pt) -> Plan:
  Plan.require(ok, Plan.join(Pt.quad(Pt.on(gnu, cx, cy, ii, start), Pt.on(gnu, cx, cy, oo, start), so1, si1),
    Plan.join(Pt.quad(Pt.on(gnu, cx, cy, ii, end), si2, so2, Pt.on(gnu, cx, cy, oo, end)), ring_ex.outward.hit(inter, si1, so1, si2, so2, hit))))

# Without the long edges crossing, the outer edges crossing (tCrossOuter in
# [0, 1]) joins both caps' second vertices.
def ring_ex.outward.other(outer: Bool, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +ii: F32, +oo: F32, +ok: Bool, +so1: Pt, +si1: Pt,
    +so2: Pt, +si2: Pt, +o0: Pt, +i0: Pt, +tci: F32, +tco: F32) -> Plan:
  match outer:
    case True{}:
      +so = Pt.lerp(o0, so2, tco, True{})
      +si = Pt.lerp(i0, si2, tci, True{})
      ring_ex.outward.draw(False{}, gnu, cx, cy, start, end, ii, oo, ok, so, si, so, si, so)
    case False{}: ring_ex.outward.draw(False{}, gnu, cx, cy, start, end, ii, oo, ok, so1, si1, so2, si2, so1)

# The long edges crossing (capsIntersect): both caps end at the inner edges'
# crossing and a quad pair fills to the long edges' crossing.
def ring_ex.outward.pick(inter: Bool, +outer: Bool, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +ii: F32, +oo: F32, +ok: Bool, +so1: Pt,
    +si1: Pt, +so2: Pt, +si2: Pt, +o0: Pt, +i0: Pt, +tlong: F32, +tci: F32, +tco: F32) -> Plan:
  match inter:
    case True{}:
      +si = Pt.lerp(i0, si2, tci, True{})
      ring_ex.outward.draw(True{}, gnu, cx, cy, start, end, ii, oo, ok, so1, si, so2, si, Pt.lerp(si2, so2, tlong, True{}))
    case False{}: ring_ex.outward.other(outer, gnu, cx, cy, start, end, ii, oo, ok, so1, si1, so2, si2, o0, i0, tci, tco)

# The caps at their place: O2 = O1 + (O0 - O1)*tOuter on the outer edge one
# step in, I2 = O2 - (cosf, sinf)(end angle)*(oo - ii).
def ring_ex.outward.caps(+gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +ii: F32, +oo: F32, +edge: F32, +tout: F32, +tlong: F32,
    +tci: F32, +tco: F32, +ok: Bool) -> Plan:
  +o1 = Pt.on(gnu, cx, cy, oo, start)
  +so1 = Pt.lerp(Pt.on(gnu, cx, cy, oo, (start + step : F32)), o1, tout, True{})
  +o2 = Pt.on(gnu, cx, cy, oo, end)
  +so2 = Pt.lerp(Pt.on(gnu, cx, cy, oo, (end - step : F32)), o2, tout, True{})
  ring_ex.outward.pick((tlong >= 0.0 : F32) && (tlong <= 1.0 : F32), (tco >= 0.0 : F32) && (tco <= 1.0 : F32), gnu, cx, cy, start, end, ii, oo, ok,
    so1, Pt.back(so1, edge, turn.at(gnu, (deg2rad() * start : F32))), so2, Pt.back(so2, edge, turn.at(gnu, (deg2rad() * end : F32))), o2,
    Pt.on(gnu, cx, cy, ii, end), tlong, tci, tco)

# Cap 2 in the frame where the center is the origin and startAngle is 0
# degrees, rotated by -DEG2RAD*stepLength/2 so cap 1's inner edge is
# vertical: where the long edges (I2-O2), the inner edges and the outer edges
# cross.
def ring_ex.outward.far(far: Turn, near: Turn, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +thick: F32, +ii: F32, +oo: F32,
    +tout: F32, +o2x: F32, +edge: F32, +ok: Bool) -> Plan:
  Turn{+c, +s, okf} = far
  Turn{+cn, +sn, okn} = near
  +o0x = (c * oo : F32)
  +o0y = (s * oo : F32)
  +o1x = (cn * oo : F32)
  +o1y = (sn * oo : F32)
  +q2x = (o1x + ((o0x - o1x : F32) * tout : F32) : F32)
  +q2y = (o1y + ((o0y - o1y : F32) * tout : F32) : F32)
  +p2x = (q2x - (c * edge : F32) : F32)
  +p2y = (q2y - (s * edge : F32) : F32)
  +spin = turn.at(gnu, ((F32.neg(deg2rad()) * step : F32) / 2.0 : F32))
  +ri2 = ring_ex.xr((o2x - edge : F32), thick, spin)
  +ro2 = ring_ex.xr(o2x, thick, spin)
  +rp0 = ring_ex.xr((c * ii : F32), (s * ii : F32), spin)
  +rp2 = ring_ex.xr(p2x, p2y, spin)
  +rq0 = ring_ex.xr(o0x, o0y, spin)
  +rq2 = ring_ex.xr(q2x, q2y, spin)
  ring_ex.outward.caps(gnu, cx, cy, start, end, step, ii, oo, edge, tout, ring_ex.ratio(p2y, thick, (p2y - q2y : F32)),
    Bool.pick(F32, (ii <= 0.0 : F32), 0.0, ring_ex.ratio(rp0, ri2, (rp0 - rp2 : F32))), ring_ex.ratio(rq0, ro2, (rq0 - rq2 : F32)),
    ok && okf && okn && Turn.ok(spin))

# A negative thickness with caps: cap 1's outer edge O0-O2 runs thick from
# the start edge (tOuter on the first outer segment), its long edge I2-O2 is
# oo - ii long.
def ring_ex.outward(+gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +thick: F32, +ii: F32, +oo: F32) -> Plan:
  +first = turn.at(gnu, (deg2rad() * step : F32))
  +o1x = (Turn.cos(first) * oo : F32)
  +o1y = (Turn.sin(first) * oo : F32)
  +tout = ((o1y - thick : F32) / o1y : F32)
  +span = (end - start : F32)
  ring_ex.outward.far(turn.at(gnu, (deg2rad() * span : F32)), turn.at(gnu, (deg2rad() * (span - step : F32) : F32)), gnu, cx, cy, start, end, step, thick, ii, oo,
    tout, (o1x + ((oo - o1x : F32) * tout : F32) : F32), (oo - ii : F32), Turn.ok(first))

def ring_ex.capsign(positive: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32, +ii: F32,
    +oi: F32, +io: F32, +oo: F32, +color: U32) -> Plan:
  match positive:
    case True{}:
      +ain = (rad2deg() * (thick / oi : F32) : F32)
      +aout = (rad2deg() * (thick / io : F32) : F32)
      ring_ex.thin(((end - start : F32) < (aout * 2.0 : F32) : F32), lm, gnu, cx, cy, start, end, step, n, ii, oi, io, oo, ain, aout, color)
    case False{}: ring_ex.drawn(gnu, cx, cy, start, step, n, ii, oi, io, oo, ring_ex.outward(gnu, cx, cy, start, end, step, thick, ii, oo), color)

def ring_ex.shown(caps: Bool, +positive: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +start: F32, +end: F32, +step: F32, +n: F32, +thick: F32,
    +ii: F32, +oi: F32, +io: F32, +oo: F32, +color: U32) -> Plan:
  match caps:
    case False{}: ring_ex.drawn(gnu, cx, cy, start, step, n, ii, oi, io, oo, Plan.empty(), color)
    case True{}: ring_ex.capsign(positive, lm, gnu, cx, cy, start, end, step, n, thick, ii, oi, io, oo, color)

# A negative thickness with an inner radius <= 0 draws
# DrawCircleSectorLinesEx; otherwise ii = fmaxf(0, inner + radiusThick),
# oi = inner, io = outer, oo = outer - radiusThick.
def ring_ex.hollow(whole: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +step: F32, +n: F32,
    +thick: F32, +rt: F32, +caps: Bool, +color: U32) -> Plan:
  match whole:
    case True{}: sector_lines_ex(lm, cx, cy, outer, start, end, n, thick, color)
    case False{}:
      +low = (inner + rt : F32)
      ring_ex.shown(caps, False{}, lm, gnu, cx, cy, start, end, step, n, thick, Bool.pick(F32, (low > 0.0 : F32), low, 0.0), inner, outer,
        (outer - rt : F32), color)

# A thickness >= 0 over half the radii's distance draws DrawRing; otherwise
# ii = fmaxf(0, inner), oi = ii + radiusThick, io = outer - radiusThick,
# oo = outer.
def ring_ex.filled(fill: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +step: F32, +n: F32,
    +thick: F32, +rt: F32, +caps: Bool, +color: U32) -> Plan:
  match fill:
    case True{}: ring(lm, cx, cy, inner, outer, start, end, n, color)
    case False{}: ring_ex.shown(caps, True{}, lm, gnu, cx, cy, start, end, step, n, thick, inner, (inner + rt : F32), (outer - rt : F32), outer, color)

def ring_ex.sign(positive: Bool, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +step: F32, +n: F32,
    +thick: F32, +rt: F32, +caps: Bool, +color: U32) -> Plan:
  match positive:
    case True{}:
      +low = Bool.pick(F32, (inner > 0.0 : F32), inner, 0.0)
      ring_ex.filled((rt > ((outer - low : F32) / 2.0 : F32) : F32), lm, gnu, cx, cy, low, outer, start, end, step, n, thick, rt, caps, color)
    case False{}: ring_ex.hollow((inner <= 0.0 : F32), lm, gnu, cx, cy, inner, outer, start, end, step, n, thick, rt, caps, color)

# radiusThick = thick*(outer/apothem), apothem = outer*cosf(DEG2RAD*((end -
# start)/2)/segments).
def ring_ex.apothem(t: Turn, +lm: U32, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +step: F32, +n: F32,
    +thick: F32, +caps: Bool, +color: U32) -> Plan:
  Turn{c, _, ok} = t
  Plan.require(ok, ring_ex.sign((thick >= 0.0 : F32), lm, gnu, cx, cy, inner, outer, start, end, step, n, thick,
    (thick * (outer / (outer * c : F32) : F32) : F32), caps, color))

def ring_ex.counted(count: Maybe<F32>, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +thick: F32, +caps: Bool,
    +color: U32) -> Plan:
  match count:
    case None{}: Plan.refused()
    case Some{+n}:
      ring_ex.apothem(turn.at(gnu.of(lm), ((deg2rad() * ((end - start : F32) / 2.0 : F32) : F32) / n : F32)), lm, gnu.of(lm), cx, cy, inner, outer, start,
        end, ((end - start : F32) / n : F32), n, thick, caps, color)

def ring_ex.sized(empty: Bool, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +thick: F32,
    +color: U32) -> Plan:
  match empty:
    case True{}: Plan.empty()
    case False{}:
      +swap = (end < start : F32)
      +first = Bool.pick(F32, swap, end, start)
      +last = Bool.pick(F32, swap, start, end)
      +ending = arc.end(first, last)
      ring_ex.counted(segments.resolve(lm, outer, (ending - first : F32), segments), lm, cx, cy, inner, outer, first, ending, thick,
        arc.caps(arc.full(first, last), (thick >= 0.0 : F32)), color)

def ring_ex.distinct(same: Bool, +lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +thick: F32,
    +color: U32) -> Plan:
  match same:
    case True{}: Plan.empty()
    case False{}:
      +flip = (outer < inner : F32)
      +big = Bool.pick(F32, flip, inner, outer)
      ring_ex.sized((big <= 0.0 : F32), lm, cx, cy, Bool.pick(F32, flip, outer, inner), big, start, end, segments, thick, color)

# DrawRingLinesEx (raylib 6.2): radii and angles ordered and segments
# resolved as DrawRingLines, then the outlines of both radii (radiusThick
# thick, inward for a thickness >= 0, outward otherwise) and cap quads unless
# a negative thickness draws a whole turn. A thickness >= 0 filling the ring
# draws DrawRing; a negative one with no inner radius
# DrawCircleSectorLinesEx.
def ring_lines_ex(+lm: U32, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +thick: F32, +color: U32) -> Plan:
  ring_ex.distinct(F32.is_eq(start, end), lm, cx, cy, inner, outer, start, end, segments, thick, color)

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

# The corner segment count (raylib 6.2): the C int parameter when at least
# 1, else the estimate (int)ceilf((2*PI/th)/4.0f) with 4 for a non-positive
# one.
def corner.segments.pick(small: Bool, +lm: U32, +radius: F32, +segments: F32) -> Maybe<F32>:
  match small:
    case False{}: segments.bounded(segments)
    case True{}: estimate.floor(estimate.corner(estimate.th(lm, radius)), 4.0)

def corner.segments.valid(valid: Bool, +lm: U32, +radius: F32, +segments: F32) -> Maybe<F32>:
  match valid:
    case False{}: None{}
    case True{}: corner.segments.pick((int.of(segments) < 1.0 : F32), lm, radius, int.of(segments))

def corner.segments(+lm: U32, +radius: F32, +segments: F32) -> Maybe<F32>:
  corner.segments.valid(int.valid(segments), lm, radius, segments)

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
    case False{}: rounded.drawn(corner.segments(lm, r, segments), gnu.of(lm), x, y, w, h, r, color)

def rounded.round(flat: Bool, +lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +roundness: F32, +segments: F32, +color: U32) -> Plan:
  match flat:
    case True{}: rectangle(x, y, w, h, color)
    case False{}:
      +r = corner.radius(w, h, Bool.pick(F32, (roundness >= 1.0 : F32), 1.0, roundness))
      rounded.sized((r <= 0.0 : F32), lm, x, y, w, h, r, segments, color)

# DrawRectangleRounded: a roundness <= 0 draws DrawRectangleRec; corners as
# sector quads (segments below 1 estimated), then five rectangles.
def rounded(+lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +roundness: F32, +segments: F32, +color: U32) -> Plan:
  rounded.round((roundness <= 0.0 : F32), lm, x, y, w, h, roundness, segments, color)

# One corner's quads between the inner and outer radii, a segment each.
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

# One corner's RL_LINES along the radius, a segment each.
def rounded_lines.outline(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +a = Pt.at(gnu, cx, cy, r, r, (deg2rad() * angle : F32))
      +b = Pt.at(gnu, cx, cy, r, r, (deg2rad() * (angle + step : F32) : F32))
      Plan.with(Pt.ok(a) && Pt.ok(b), [F.Color{color}, Pt.point(a), Pt.point(b)], rounded_lines.outline(k, gnu, cx, cy, r, (angle + step : F32), step, color))

# DrawRectangleRoundedLines (raylib 6.2, its own RL_LINES): the corner arcs
# around P8..P11, half a pixel inside, then the four sides P0-P1, P2-P3, P4-P5
# and P6-P7.
def rounded_thin.drawn(count: Maybe<F32>, +gnu: Bool, +x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +color: U32) -> Plan:
  match count:
    case None{}: Plan.refused()
    case Some{+segments}:
      +n = U32.to_nat(F32.to_u32(segments))
      +step = (90.0 / segments : F32)
      +x0 = ((x + r : F32) + 0.5 : F32)
      +x1 = (((x + w : F32) - r : F32) - 0.5 : F32)
      +x2 = ((x + w : F32) - 0.5 : F32)
      +x3 = (x + 0.5 : F32)
      +y0 = (y + 0.5 : F32)
      +y1 = ((y + r : F32) + 0.5 : F32)
      +y2 = (((y + h : F32) - r : F32) - 0.5 : F32)
      +y3 = ((y + h : F32) - 0.5 : F32)
      Plan.plain(2, Plan.join(rounded_lines.outline(n, gnu, x0, y1, r, 180.0, step, color), Plan.join(rounded_lines.outline(n, gnu, x1, y1, r, 270.0, step, color),
        Plan.join(rounded_lines.outline(n, gnu, x1, y2, r, 0.0, step, color), Plan.join(rounded_lines.outline(n, gnu, x0, y2, r, 90.0, step, color),
          Plan.only(True{}, [F.Color{color}, F.Point{x0, y0}, F.Point{x1, y0}, F.Color{color}, F.Point{x2, y1}, F.Point{x2, y2},
            F.Color{color}, F.Point{x1, y3}, F.Point{x0, y3}, F.Color{color}, F.Point{x3, y2}, F.Point{x3, y1}]))))))

def rounded_thin.sized(empty: Bool, +lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +segments: F32, +color: U32) -> Plan:
  match empty:
    case True{}: Plan.empty()
    case False{}: rounded_thin.drawn(corner.segments(lm, r, segments), gnu.of(lm), x, y, w, h, r, color)

def rounded_thin.round(flat: Bool, +lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +roundness: F32, +segments: F32, +color: U32) -> Plan:
  match flat:
    case True{}: Plan.require(int.valid(x) && int.valid(y) && int.valid(w) && int.valid(h), rectangle.lines(int.of(x), int.of(y), int.of(w), int.of(h), color))
    case False{}:
      +r = corner.radius(w, h, Bool.pick(F32, (roundness >= 1.0 : F32), 1.0, roundness))
      rounded_thin.sized((r <= 0.0 : F32), lm, x, y, w, h, r, segments, color)

# DrawRectangleRoundedLines (raylib 6.2): a roundness <= 0 draws
# DrawRectangleLines((int)x, (int)y, (int)width, (int)height); corners with
# segments below 1 estimated.
def rounded_thin(+lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +roundness: F32, +segments: F32, +color: U32) -> Plan:
  rounded_thin.round((roundness <= 0.0 : F32), lm, x, y, w, h, roundness, segments, color)

type Outline is Data:
  Outline{p0: P2, p1: P2, p2: P2, p3: P2, p4: P2, p5: P2, p6: P2, p7: P2, p8: P2, p9: P2, p10: P2, p11: P2, p12: P2, p13: P2, p14: P2, p15: P2}

# P0..P15 of rshapes.c's DrawRectangleRoundedLinesEx sketch (raylib 6.2):
# x0 = x + R, x1 = (x + w) - R, x2 = x + w, x3 = x, x4 = (x + w) - T,
# x5 = x + T, and the same in y, for the outer radius R and the rounded
# outline thickness T.
def outline.points(+x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +t: F32) -> Outline:
  +x0 = (x + r : F32)
  +x1 = ((x + w : F32) - r : F32)
  +x2 = (x + w : F32)
  +x4 = ((x + w : F32) - t : F32)
  +x5 = (x + t : F32)
  +y1 = (y + r : F32)
  +y2 = ((y + h : F32) - r : F32)
  +y3 = (y + h : F32)
  +y4 = (y + t : F32)
  +y5 = ((y + h : F32) - t : F32)
  Outline{P2{x0, y}, P2{x1, y}, P2{x2, y1}, P2{x2, y2}, P2{x1, y3}, P2{x0, y3}, P2{x, y2}, P2{x, y1},
    P2{x0, y4}, P2{x1, y4}, P2{x4, y1}, P2{x4, y2}, P2{x1, y5}, P2{x0, y5}, P2{x5, y2}, P2{x5, y1}}

# The four side quads between the outer and inner edges.
def outline.quads(+color: U32, o: Outline) -> +List<F.Command>:
  Outline{+p0, +p1, +p2, +p3, +p4, +p5, +p6, +p7, +p8, +p9, +p10, +p11, +p12, +p13, +p14, +p15} = o
  List.append(&2, F.Command, quad.at(color, p0, p8, p9, p1), List.append(&2, F.Command, quad.at(color, p2, p10, p11, p3),
    List.append(&2, F.Command, quad.at(color, p13, p5, p4, p12), quad.at(color, p15, p7, p6, p14))))

# The corner quads around P16..P19 (the corners of P8..P11's rectangle).
def rounded_lines.corners(+gnu: Bool, +x: F32, +y: F32, +w: F32, +h: F32, +inner: F32, +outer: F32, +step: F32, +segments: F32, +color: U32) -> Plan:
  +n = U32.to_nat(F32.to_u32(segments))
  +left = (x + outer : F32)
  +top = (y + outer : F32)
  +right = ((x + w : F32) - outer : F32)
  +bottom = ((y + h : F32) - outer : F32)
  Plan.join(rounded_lines.arc(n, gnu, left, top, inner, outer, 180.0, step, color), Plan.join(rounded_lines.arc(n, gnu, right, top, inner, outer, 270.0, step, color),
    Plan.join(rounded_lines.arc(n, gnu, right, bottom, inner, outer, 0.0, step, color), rounded_lines.arc(n, gnu, left, bottom, inner, outer, 90.0, step, color))))

# Corners first, then the sides, as quads.
def rounded_lines.drawn(count: Maybe<F32>, +gnu: Bool, +x: F32, +y: F32, +w: F32, +h: F32, +inner: F32, +outer: F32, +t: F32, +color: U32) -> Plan:
  match count:
    case None{}: Plan.refused()
    case Some{+segments}:
      Plan.textured(4, Plan.join(rounded_lines.corners(gnu, x, y, w, h, inner, outer, (90.0 / segments : F32), segments, color),
        Plan.only(True{}, outline.quads(color, outline.points(x, y, w, h, outer, t)))))

# A thickness inside the corner radius r: an inner radius r - thick, or, when
# that is <= 0, an inner radius 0, the rounded part r thick and the rest
# drawn first by DrawRectangleLinesEx inside the rounded outline.
def rounded_lines.inward(deep: Bool, +lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +thick: F32, +segments: F32, +color: U32) -> Plan:
  match deep:
    case False{}: rounded_lines.drawn(corner.segments(lm, r, segments), gnu.of(lm), x, y, w, h, (r - thick : F32), r, thick, color)
    case True{}:
      Plan.join(rectangle.lines_ex((x + r : F32), (y + r : F32), (w - (r * 2.0 : F32) : F32), (h - (r * 2.0 : F32) : F32), (thick - r : F32), color),
        rounded_lines.drawn(corner.segments(lm, r, segments), gnu.of(lm), x, y, w, h, 0.0, r, r, color))

# A negative thickness grows the rectangle by -thick on each side: the inner
# radius is r, the outer one r - thick.
def rounded_lines.side(inward: Bool, +lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +thick: F32, +segments: F32, +color: U32) -> Plan:
  match inward:
    case True{}: rounded_lines.inward(((r - thick : F32) <= 0.0 : F32), lm, x, y, w, h, r, thick, segments, color)
    case False{}:
      rounded_lines.drawn(corner.segments(lm, r, segments), gnu.of(lm), (x + thick : F32), (y + thick : F32), (w - (thick * 2.0 : F32) : F32),
        (h - (thick * 2.0 : F32) : F32), r, (r - thick : F32), F32.neg(thick), color)

def rounded_lines.sized(empty: Bool, +lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +r: F32, +thick: F32, +segments: F32, +color: U32) -> Plan:
  match empty:
    case True{}: Plan.empty()
    case False{}: rounded_lines.side((thick >= 0.0 : F32), lm, x, y, w, h, r, thick, segments, color)

def rounded_lines.round(flat: Bool, +lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +roundness: F32, +segments: F32, +thick: F32, +color: U32) -> Plan:
  match flat:
    case True{}: rectangle.lines_ex(x, y, w, h, thick, color)
    case False{}:
      +r = corner.radius(w, h, Bool.pick(F32, (roundness >= 1.0 : F32), 1.0, roundness))
      rounded_lines.sized((r <= 0.0 : F32), lm, x, y, w, h, r, thick, segments, color)

# DrawRectangleRoundedLinesEx (raylib 6.2): roundness <= 0 draws
# DrawRectangleLinesEx(rec, thick); corners (segments below 1 estimated) and
# sides are quads between an outer and an inner edge, inside the rectangle
# for a thickness >= 0 and outside it for a negative one.
def rounded_lines(+lm: U32, +x: F32, +y: F32, +w: F32, +h: F32, +roundness: F32, +segments: F32, +thick: F32, +color: U32) -> Plan:
  rounded_lines.round((roundness <= 0.0 : F32), lm, x, y, w, h, roundness, segments, thick, color)

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
