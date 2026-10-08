# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rshapes.c (SUPPORT_QUADS_DRAW_MODE);
# LICENSES/raylib.txt. Each shape becomes the rlBegin/rlColor4ub/
# rlTexCoord2f/rlVertex2f/rlEnd sequence rshapes.c issues (src/frame.bend
# renders it), with rshapes.c's F32 vertex arithmetic in its order. Textured
# shapes sample the 2x8 white block (41, 46, 2, 8) of the default font atlas
# that rcore.c InitWindow selects with SetShapesTexture.
#
# A Plan also says whether Jonlib reproduces the draw: sinf/cosf arguments
# must be verified for the libm profile, C int conversions must be defined,
# and loops are bounded (segments and sides 1..4096). An invalid plan marks
# the frame undefined; see docs/FRAME.md.
import Base
import ./frame.bend as F
import ./trig.bend as Trig
import ./checked_angle.bend as CheckedAngle

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
  Plan{valid, Con{F.Texture{True{}}, Con{F.Begin{count}, List.append(&2, F.Command, commands, [F.End{}, F.Texture{False{}}])}}}

def Plan.plain(+count: U32, plan: Plan) -> Plan:
  Plan{valid, commands} = plan
  Plan{valid, Con{F.Begin{count}, List.append(&2, F.Command, commands, [F.End{}])}}

# -----------------------------------------------------------------------------
# Constants, C conversions and the libm contract

# DEG2RAD: (PI/180.0f) with PI = 3.14159265358979323846f.
def deg2rad() -> F32:
  F.float(1016003125)

# Texture coordinates of the shapes rectangle: 41/128, 43/128, 46/128, 54/128.
def u0() -> F32:
  0.3203125

def u1() -> F32:
  0.3359375

def v0() -> F32:
  0.359375

def v1() -> F32:
  0.421875

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

# glibc: normal or zero arguments within one turn (docs/ROTATION.md).
def trig.gnu(+arg: F32) -> Bool:
  (F32.abs(arg) <= F.float(1086918620) : F32) && CheckedAngle.normal_or_zero(arg)

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

def P2.point(+p: P2) -> F.Command:
  P2{x, y} = p
  F.Point{x, y}

# -----------------------------------------------------------------------------
# Pixels, lines and rectangles

# DrawPixelV: a 1x1 quad at the position.
def pixel(+x: F32, +y: F32, +color: U32) -> Plan:
  Plan.textured(4, Plan.only(True{}, [F.Color{color}, F.TexCoord{u0(), v0()}, F.Point{x, y}, F.TexCoord{u0(), v1()}, F.Point{x, (y + 1.0 : F32)},
    F.TexCoord{u1(), v1()}, F.Point{(x + 1.0 : F32), (y + 1.0 : F32)}, F.TexCoord{u1(), v0()}, F.Point{(x + 1.0 : F32), y}]))

# DrawLineV: one RL_LINES segment (untextured).
def line(+x0: F32, +y0: F32, +x1: F32, +y1: F32, +color: U32) -> Plan:
  Plan.plain(2, Plan.only(True{}, [F.Color{color}, F.Point{x0, y0}, F.Point{x1, y1}]))

# The quad of DrawRectanglePro/DrawTriangle: corners a..d with texcoords
# (u0, v0), (u0, v1), (u1, v1), (u1, v0).
def quad(valid: Bool, +color: U32, +a: P2, +b: P2, +c: P2, +d: P2) -> Plan:
  Plan.textured(4, Plan.only(valid, [F.Color{color}, F.TexCoord{u0(), v0()}, P2.point(a), F.TexCoord{u0(), v1()}, P2.point(b),
    F.TexCoord{u1(), v1()}, P2.point(c), F.TexCoord{u1(), v0()}, P2.point(d)]))

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
  Plan.textured(4, Plan.only(True{}, [F.Color{top_left}, F.TexCoord{u0(), v0()}, F.Point{x, y}, F.Color{bottom_left}, F.TexCoord{u0(), v1()},
    F.Point{x, (y + height : F32)}, F.Color{bottom_right}, F.TexCoord{u1(), v1()}, F.Point{(x + width : F32), (y + height : F32)},
    F.Color{top_right}, F.TexCoord{u1(), v0()}, F.Point{(x + width : F32), y}]))

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
    case Con{+c, _}: [F.TexCoord{u0(), v0()}, P2.point(first), F.TexCoord{u0(), v1()}, P2.point(b), F.TexCoord{u1(), v1()}, P2.point(c),
      F.TexCoord{u1(), v0()}, P2.point(c)]

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
# Circles, sectors, rings, ellipses and polygons (sinf/cosf)

# segments: a valid C int below the minimum takes rshapes.c's acosf/powf path,
# which Jonlib does not reproduce; above 4096 the loop bound is refused.
def segments.ok(+segments: F32, +minimum: F32) -> Bool:
  (segments >= minimum : F32) && (segments <= 4096.0 : F32)

def sector.quad(+gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +step: F32, +color: U32, plan: Plan) -> Plan:
  +p2 = Pt.at(gnu, cx, cy, r, r, (deg2rad() * (angle + step * 2.0 : F32) : F32))
  +p1 = Pt.at(gnu, cx, cy, r, r, (deg2rad() * (angle + step : F32) : F32))
  +p0 = Pt.at(gnu, cx, cy, r, r, (deg2rad() * angle : F32))
  Plan.with(Pt.ok(p2) && Pt.ok(p1) && Pt.ok(p0), [F.Color{color}, F.TexCoord{u0(), v0()}, F.Point{cx, cy}, F.TexCoord{u1(), v0()}, Pt.point(p2),
    F.TexCoord{u1(), v1()}, Pt.point(p1), F.TexCoord{u0(), v1()}, Pt.point(p0)], plan)

def sector.odd(odd: Bool, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match odd:
    case False{}: Plan.empty()
    case True{}:
      +p1 = Pt.at(gnu, cx, cy, r, r, (deg2rad() * (angle + step : F32) : F32))
      +p0 = Pt.at(gnu, cx, cy, r, r, (deg2rad() * angle : F32))
      Plan.only(Pt.ok(p1) && Pt.ok(p0), [F.Color{color}, F.TexCoord{u0(), v0()}, F.Point{cx, cy}, F.TexCoord{u1(), v1()}, Pt.point(p1),
        F.TexCoord{u0(), v1()}, Pt.point(p0), F.TexCoord{u1(), v0()}, F.Point{cx, cy}])

def sector.quads(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +step: F32, +color: U32, +odd: Bool) -> Plan:
  match n:
    case 0n: sector.odd(odd, gnu, cx, cy, r, angle, step, color)
    case 1n+k: sector.quad(gnu, cx, cy, r, angle, step, color, sector.quads(k, gnu, cx, cy, r, (angle + step * 2.0 : F32), step, color, odd))

def sector.drawn(valid: Bool, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match valid:
    case False{}: Plan.refused()
    case True{}:
      +count = F32.to_u32(segments)
      Plan.textured(4, sector.quads(U32.to_nat((count / 2 : U32)), gnu, cx, cy, r, start, ((end - start : F32) / segments : F32), color,
        U32.is_eq((count % 2 : U32), 1)))

def sector.ordered(+gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  +minimum = F32.ceil(((end - start : F32) / 90.0 : F32))
  sector.drawn(int.valid(minimum) && int.valid(segments) && segments.ok(int.of(segments), minimum), gnu, cx, cy, r, start, end, int.of(segments), color)

def sector.distinct(same: Bool, +gnu: Bool, +cx: F32, +cy: F32, +radius: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match same:
    case True{}: Plan.empty()
    case False{}:
      +r = Bool.pick(F32, (radius <= 0.0 : F32), 0.1, radius)
      +swap = (end < start : F32)
      sector.ordered(gnu, cx, cy, r, Bool.pick(F32, swap, end, start), Bool.pick(F32, swap, start, end), segments, color)

# DrawCircleSector (quads of two segments, then an odd last piece).
def sector(+gnu: Bool, +cx: F32, +cy: F32, +radius: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  sector.distinct(F32.is_eq(start, end), gnu, cx, cy, radius, start, end, segments, color)

# DrawCircleV: DrawCircleSector(center, radius, 0, 360, 36).
def circle(+gnu: Bool, +cx: F32, +cy: F32, +radius: F32, +color: U32) -> Plan:
  sector(gnu, cx, cy, radius, 0.0, 360.0, 36.0, color)

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

def sector_lines.drawn(valid: Bool, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match valid:
    case False{}: Plan.refused()
    case True{}:
      +first = Pt.at(gnu, cx, cy, r, r, (deg2rad() * start : F32))
      Plan.plain(2, Plan.with(Pt.ok(first), [F.Color{color}, F.Point{cx, cy}, Pt.point(first)],
        sector_lines.loop(U32.to_nat(F32.to_u32(segments)), gnu, cx, cy, r, start, ((end - start : F32) / segments : F32), color)))

def sector_lines.ordered(+gnu: Bool, +cx: F32, +cy: F32, +r: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  +minimum = F32.ceil(((end - start : F32) / 90.0 : F32))
  sector_lines.drawn(int.valid(minimum) && int.valid(segments) && segments.ok(int.of(segments), minimum), gnu, cx, cy, r, start, end, int.of(segments), color)

def sector_lines.distinct(same: Bool, +gnu: Bool, +cx: F32, +cy: F32, +radius: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match same:
    case True{}: Plan.empty()
    case False{}:
      +r = Bool.pick(F32, (radius <= 0.0 : F32), 0.1, radius)
      +swap = (end < start : F32)
      sector_lines.ordered(gnu, cx, cy, r, Bool.pick(F32, swap, end, start), Bool.pick(F32, swap, start, end), segments, color)

# DrawCircleSectorLines: cap lines from the center plus one line per segment.
def sector_lines(+gnu: Bool, +cx: F32, +cy: F32, +radius: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  sector_lines.distinct(F32.is_eq(start, end), gnu, cx, cy, radius, start, end, segments, color)

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
      Plan.with(Pt.ok(a) && Pt.ok(b) && Pt.ok(c) && Pt.ok(d), [F.Color{color}, F.TexCoord{u0(), v1()}, Pt.point(a), F.TexCoord{u0(), v0()}, Pt.point(b),
        F.TexCoord{u1(), v0()}, Pt.point(c), F.TexCoord{u1(), v1()}, Pt.point(d)], ring.loop(k, gnu, cx, cy, inner, outer, (angle + step : F32), step, color))

def ring.kind(full: Bool, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match full:
    case True{}: sector(gnu, cx, cy, outer, start, end, segments, color)
    case False{}: Plan.textured(4, ring.loop(U32.to_nat(F32.to_u32(segments)), gnu, cx, cy, inner, outer, start, ((end - start : F32) / segments : F32), color))

def ring.drawn(valid: Bool, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match valid:
    case False{}: Plan.refused()
    case True{}: ring.kind((inner <= 0.0 : F32), gnu, cx, cy, inner, outer, start, end, segments, color)

def ring.ordered(+gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  +minimum = F32.ceil(((end - start : F32) / 90.0 : F32))
  ring.drawn(int.valid(minimum) && int.valid(segments) && segments.ok(int.of(segments), minimum), gnu, cx, cy, inner, outer, start, end, int.of(segments), color)

def ring.distinct(same: Bool, +gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  match same:
    case True{}: Plan.empty()
    case False{}:
      +flip = (outer < inner : F32)
      +big = Bool.pick(F32, flip, inner, outer)
      +swap = (end < start : F32)
      ring.ordered(gnu, cx, cy, Bool.pick(F32, flip, outer, inner), Bool.pick(F32, flip && (big <= 0.0 : F32), 0.1, big),
        Bool.pick(F32, swap, end, start), Bool.pick(F32, swap, start, end), segments, color)

# DrawRing: quads between the radii; a non-positive inner radius draws
# DrawCircleSector with the outer one.
def ring(+gnu: Bool, +cx: F32, +cy: F32, +inner: F32, +outer: F32, +start: F32, +end: F32, +segments: F32, +color: U32) -> Plan:
  ring.distinct(F32.is_eq(start, end), gnu, cx, cy, inner, outer, start, end, segments, color)

def poly.loop(n: Nat, +gnu: Bool, +cx: F32, +cy: F32, +r: F32, +angle: F32, +step: F32, +color: U32) -> Plan:
  match n:
    case 0n: Plan.empty()
    case 1n+k:
      +next = (angle + step : F32)
      +a = Pt.at(gnu, cx, cy, r, r, angle)
      +b = Pt.at(gnu, cx, cy, r, r, next)
      Plan.with(Pt.ok(a) && Pt.ok(b), [F.Color{color}, F.TexCoord{u0(), v0()}, F.Point{cx, cy}, F.TexCoord{u0(), v1()}, Pt.point(a),
        F.TexCoord{u1(), v0()}, Pt.point(b), F.TexCoord{u1(), v1()}, Pt.point(a)], poly.loop(k, gnu, cx, cy, r, next, step, color))

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
