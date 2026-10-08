# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rmodels.c's 3D shape drawing
# (DrawLine3D ... DrawGrid; zlib, LICENSES/raylib.txt). Each shape becomes the
# rlPushMatrix/rlTranslatef/rlRotatef/rlScalef/rlBegin/rlColor4ub/
# rlVertex3f/rlEnd/rlPopMatrix stream rmodels.c issues, with its F32 vertex
# arithmetic in source order (uncontracted, as the reference renderer is
# built); src/frame.bend renders it through rlsw's 3D path. sinf/cosf
# arguments must lie in the M.Libm profile's verified set (src/shapes.bend
# trig.ok) and loops are bounded (rings, slices and sides up to 4096); an
# invalid plan marks the frame undefined. See docs/MODELS.md.
import Base
import ./../jonmath.bend as M
import ./frame.bend as F
import ./shapes.bend as S
import ./textures.bend as T
import ./trig.bend as Trig

# cosf and sinf of one argument and whether the profile reproduces them.
type SC is Data:
  SC{c: F32, s: F32, ok: Bool}

def SC.with(ok: Bool, values: F32 & F32) -> SC:
  (c, s) = values
  SC{c, s, ok}

def sc(+gnu: Bool, +arg: F32) -> SC:
  SC.with(S.trig.ok(gnu, arg), Trig.sincos_for(gnu, arg))

def SC.cos(+v: SC) -> F32:
  SC{c, _, _} = v
  c

def SC.sin(+v: SC) -> F32:
  SC{_, s, _} = v
  s

def SC.ok(+v: SC) -> Bool:
  SC{_, _, ok} = v
  ok

def v3(+x: F32, +y: F32, +z: F32) -> F.Command:
  F.Vertex3{x, y, z}

def vec(+v: M.Vector3) -> F.Command:
  M.Vector3{x, y, z} = v
  F.Vertex3{x, y, z}

def pi2() -> F32:
  F.float(1086918619)

# rlPushMatrix, the matrix calls, the drawing, rlPopMatrix.
def pushed(matrix: S.Plan, plan: S.Plan) -> S.Plan:
  S.Plan.prefix(F.Push{}, S.Plan.join(matrix, S.Plan.join(plan, S.Plan.only(True{}, [F.Pop{}]))))

# rlPushMatrix, rlTranslatef(position), the extra matrix calls, the drawing,
# rlPopMatrix.
def placed(position: M.Vector3, extra: S.Plan, plan: S.Plan) -> S.Plan:
  M.Vector3{x, y, z} = position
  pushed(S.Plan.join(T.translate(x, y, z), extra), plan)

def translated(position: M.Vector3, plan: S.Plan) -> S.Plan:
  placed(position, S.Plan.empty(), plan)

# A C int parameter in 0..limit after the conversion, or a defined value
# whose loop does not run (negative).
def count.valid(+x: F32, +limit: F32) -> Bool:
  S.int.valid(x) && (S.int.of(x) <= limit : F32)

def count.nat(+x: F32) -> Nat:
  Bool.pick(Nat, (x >= 1.0 : F32) && (x <= 16777216.0 : F32), U32.to_nat(F32.to_u32(x)), 0n)

# -----------------------------------------------------------------------------
# Lines, points, circles and triangles

# DrawLine3D
def line(+a: M.Vector3, +b: M.Vector3, +color: U32) -> S.Plan:
  S.Plan.plain(2, S.Plan.only(True{}, [F.Color{color}, vec(a), vec(b)]))

# DrawPoint3D: a line from the translated origin to z = 0.1f.
def point(position: M.Vector3, +color: U32) -> S.Plan:
  translated(position, S.Plan.plain(2, S.Plan.only(True{}, [F.Color{color}, v3(0.0, 0.0, 0.0), v3(0.0, 0.0, F.float(1036831949))])))

def circle.loop(n: Nat, +gnu: Bool, +r: F32, +degrees: F32, +color: U32) -> S.Plan:
  match n:
    case 0n: S.Plan.empty()
    case 1n+k:
      +next = (degrees + 10.0 : F32)
      +a = sc(gnu, (S.deg2rad() * degrees : F32))
      +b = sc(gnu, (S.deg2rad() * next : F32))
      S.Plan.with(SC.ok(a) && SC.ok(b), [F.Color{color}, v3((SC.sin(a) * r : F32), (SC.cos(a) * r : F32), 0.0),
        v3((SC.sin(b) * r : F32), (SC.cos(b) * r : F32), 0.0)], circle.loop(k, gnu, r, next, color))

# DrawCircle3D: translate, rlRotatef(angle, axis), 36 lines every 10 degrees
# (the color set before each).
def circle(+gnu: Bool, center: M.Vector3, +radius: F32, axis: M.Vector3, +angle: F32, +color: U32) -> S.Plan:
  M.Vector3{ax, ay, az} = axis
  placed(center, T.rotate(gnu, angle, ax, ay, az), S.Plan.plain(2, circle.loop(36n, gnu, radius, 0.0, color)))

# DrawTriangle3D
def triangle(+a: M.Vector3, +b: M.Vector3, +c: M.Vector3, +color: U32) -> S.Plan:
  S.Plan.plain(3, S.Plan.only(True{}, [F.Color{color}, vec(a), vec(b), vec(c)]))

def at_least(n: Nat, points: +List<M.Vector3>) -> Bool:
  match n points:
    case 0n _: True{}
    case _ Nil{}: False{}
    case 1n+k Con{_, rest}: at_least(k, rest)

def strip.triangle(even: Bool, +a: M.Vector3, +b: M.Vector3, +c: M.Vector3) -> +List<F.Command>:
  match even:
    case True{}: [vec(c), vec(a), vec(b)]
    case False{}: [vec(c), vec(b), vec(a)]

def strip.loop(rest: +List<M.Vector3>, +even: Bool, +a: M.Vector3, +b: M.Vector3) -> +List<F.Command>:
  match rest:
    case Nil{}: Nil{}
    case Con{+c, more}: List.append(&2, F.Command, strip.triangle(even, a, b, c), strip.loop(more, Bool.not(even), b, c))

def strip.points(points: +List<M.Vector3>, +color: U32) -> S.Plan:
  match points:
    case Con{+a, Con{+b, rest}}: S.Plan.plain(3, S.Plan.only(True{}, Con{F.Color{color}, strip.loop(rest, True{}, a, b)}))
    case _: S.Plan.empty()

def strip.counted(enough: Bool, points: +List<M.Vector3>, +color: U32) -> S.Plan:
  match enough:
    case False{}: S.Plan.empty()
    case True{}: strip.points(points, color)

# DrawTriangleStrip3D: nothing below three points; triangles (i, i-2, i-1)
# for even i and (i, i-1, i-2) for odd i.
def strip(+points: +List<M.Vector3>, +color: U32) -> S.Plan:
  strip.counted(at_least(3n, points), points, color)

# -----------------------------------------------------------------------------
# Cubes, planes, rays, grids and boxes

def half.low(+size: F32) -> F32:
  (0.0 - (size / 2.0 : F32) : F32)

def half.high(+size: F32) -> F32:
  (0.0 + (size / 2.0 : F32) : F32)

def cube.faces(+l: F32, +r: F32, +b: F32, +t: F32, +k: F32, +f: F32) -> +List<F.Command>:
  [v3(l, b, f), v3(r, b, f), v3(l, t, f), v3(r, t, f), v3(l, t, f), v3(r, b, f),
   v3(l, b, k), v3(l, t, k), v3(r, b, k), v3(r, t, k), v3(r, b, k), v3(l, t, k),
   v3(l, t, k), v3(l, t, f), v3(r, t, f), v3(r, t, k), v3(l, t, k), v3(r, t, f),
   v3(l, b, k), v3(r, b, f), v3(l, b, f), v3(r, b, k), v3(r, b, f), v3(l, b, k),
   v3(r, b, k), v3(r, t, k), v3(r, t, f), v3(r, b, f), v3(r, b, k), v3(r, t, f),
   v3(l, b, k), v3(l, t, f), v3(l, t, k), v3(l, b, f), v3(l, t, f), v3(l, b, k)]

# DrawCube: 12 triangles around the translated origin (x - width/2 with x = 0).
def cube(position: M.Vector3, +width: F32, +height: F32, +length: F32, +color: U32) -> S.Plan:
  translated(position, S.Plan.plain(3, S.Plan.only(True{}, Con{F.Color{color}, cube.faces(half.low(width), half.high(width),
    half.low(height), half.high(height), half.low(length), half.high(length))})))

def cube.edges(+l: F32, +r: F32, +b: F32, +t: F32, +k: F32, +f: F32) -> +List<F.Command>:
  [v3(l, b, f), v3(r, b, f), v3(r, b, f), v3(r, t, f), v3(r, t, f), v3(l, t, f), v3(l, t, f), v3(l, b, f),
   v3(l, b, k), v3(r, b, k), v3(r, b, k), v3(r, t, k), v3(r, t, k), v3(l, t, k), v3(l, t, k), v3(l, b, k),
   v3(l, t, f), v3(l, t, k), v3(r, t, f), v3(r, t, k), v3(l, b, f), v3(l, b, k), v3(r, b, f), v3(r, b, k)]

# DrawCubeWires: 12 lines.
def cube_wires(position: M.Vector3, +width: F32, +height: F32, +length: F32, +color: U32) -> S.Plan:
  translated(position, S.Plan.plain(2, S.Plan.only(True{}, Con{F.Color{color}, cube.edges(half.low(width), half.high(width),
    half.low(height), half.high(height), half.low(length), half.high(length))})))

# DrawPlane: translate, rlScalef(size.x, 1, size.y), one quad on y = 0.
def plane(center: M.Vector3, size: M.Vector2, +color: U32) -> S.Plan:
  M.Vector2{sx, sz} = size
  placed(center, T.scale(sx, 1.0, sz), S.Plan.plain(4, S.Plan.only(True{}, [F.Color{color},
    v3(F32.neg(0.5), 0.0, F32.neg(0.5)), v3(F32.neg(0.5), 0.0, 0.5), v3(0.5, 0.0, 0.5), v3(0.5, 0.0, F32.neg(0.5))])))

# DrawRay: a line from the position to position + direction*10000 (the
# color set twice).
def ray(position: M.Vector3, direction: M.Vector3, +color: U32) -> S.Plan:
  M.Vector3{+x, +y, +z} = position
  M.Vector3{dx, dy, dz} = direction
  S.Plan.plain(2, S.Plan.only(True{}, [F.Color{color}, F.Color{color}, v3(x, y, z),
    v3((x + dx * 10000.0 : F32), (y + dy * 10000.0 : F32), (z + dz * 10000.0 : F32))]))

def grid.loop(n: Nat, +i: F32, +half: F32, +spacing: F32) -> +List<F.Command>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      +shade = Bool.pick(F32, F32.is_eq(i, 0.0), 0.5, 0.75)
      +at = (i * spacing : F32)
      +low = ((0.0 - half : F32) * spacing : F32)
      +high = (half * spacing : F32)
      Con{F.ColorF{shade, shade, shade, 1.0}, Con{v3(at, 0.0, low), Con{v3(at, 0.0, high), Con{v3(low, 0.0, at),
        Con{v3(high, 0.0, at), grid.loop(k, (i + 1.0 : F32), half, spacing)}}}}}

# DrawGrid(int slices, float spacing): lines for i = -slices/2 .. slices/2
# (C division), gray 0.5 at i = 0 and 0.75 elsewhere (rlColor3f).
def grid(+slices: F32, +spacing: F32) -> S.Plan:
  +half = F32.trunc((S.int.of(slices) / 2.0 : F32))
  S.Plan.require(S.int.valid(slices) && (F32.abs(half) <= 2048.0 : F32),
    S.Plan.plain(2, S.Plan.only(True{}, grid.loop(count.nat((half * 2.0 + 1.0 : F32)), (0.0 - half : F32), half, spacing))))

# DrawBoundingBox: DrawCubeWires around the center min + |max - min|/2.
def bounding_box(low: M.Vector3, high: M.Vector3, +color: U32) -> S.Plan:
  M.Vector3{+ax, +ay, +az} = low
  M.Vector3{bx, by, bz} = high
  +sx = F32.abs((bx - ax : F32))
  +sy = F32.abs((by - ay : F32))
  +sz = F32.abs((bz - az : F32))
  cube_wires(M.Vector3{(ax + (sx / 2.0 : F32) : F32), (ay + (sy / 2.0 : F32) : F32), (az + (sz / 2.0 : F32) : F32)}, sx, sy, sz, color)

# -----------------------------------------------------------------------------
# Angle tables: entry i is cosf/sinf of
#   kind 0: (DEG2RAD*i)*k       (DrawCylinder, DrawCylinderWires)
#   kind 1: k*i                 (DrawCylinderEx, DrawCapsule)
#   kind 2: DEG2RAD*(270 + k*i) (DrawSphereWires rings)
#   kind 3: DEG2RAD*(360*i/k)   (DrawSphereWires slices)

def angle(kind: U32, +i: F32, +k: F32) -> F32:
  match kind:
    case 0: ((S.deg2rad() * i : F32) * k : F32)
    case 1: (k * i : F32)
    case 2: (S.deg2rad() * (270.0 + (k * i : F32) : F32) : F32)
    case _: (S.deg2rad() * ((360.0 * i : F32) / k : F32) : F32)

def table(n: Nat, +gnu: Bool, +kind: U32, +i: F32, +k: F32) -> +List<SC>:
  match n:
    case 0n: Nil{}
    case 1n+m: Con{sc(gnu, angle(kind, i, k)), table(m, gnu, kind, (i + 1.0 : F32), k)}

def table.ok(entries: +List<SC>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{+e, rest}: SC.ok(e) && table.ok(rest)

# -----------------------------------------------------------------------------
# Spheres

def turn.y(+c: F32, +s: F32, v: M.Vector3) -> M.Vector3:
  M.Vector3{+x, y, +z} = v
  M.Vector3{(c * x - s * z : F32), y, (s * x + c * z : F32)}

def turn.z(+c: F32, +s: F32, v: M.Vector3) -> M.Vector3:
  M.Vector3{+x, +y, z} = v
  M.Vector3{(c * x + s * y : F32), (F32.neg(s) * x + c * y : F32), z}

def sphere.turned(n: Nat, +c: F32, +s: F32, +v: M.Vector3) -> M.Vector3:
  match n:
    case 0n: v
    case 1n+k: sphere.turned(k, c, s, turn.y(c, s, v))

def sphere.slices(n: Nat, +c: F32, +s: F32, +a: M.Vector3, +b: M.Vector3, rest: +List<F.Command>) -> +List<F.Command>:
  match n:
    case 0n: rest
    case 1n+k:
      +na = turn.y(c, s, a)
      +nb = turn.y(c, s, b)
      Con{vec(a), Con{vec(nb), Con{vec(b), Con{vec(a), Con{vec(na), Con{vec(nb), sphere.slices(k, c, s, na, nb, rest)}}}}}}

def sphere.rings(n: Nat, +slices: Nat, +ring: SC, +slice: SC, +a: M.Vector3, +b: M.Vector3) -> +List<F.Command>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      +last = sphere.turned(slices, SC.cos(slice), SC.sin(slice), b)
      sphere.slices(slices, SC.cos(slice), SC.sin(slice), a, b,
        sphere.rings(k, slices, ring, slice, last, turn.z(SC.cos(ring), SC.sin(ring), last)))

def sphere.drawn(valid: Bool, +rings: Nat, +slices: Nat, +ring: SC, +slice: SC, center: M.Vector3, +radius: F32, +color: U32) -> S.Plan:
  match valid:
    case False{}: S.Plan.refused()
    case True{}:
      placed(center, T.scale(radius, radius, radius), S.Plan.plain(3, S.Plan.only(True{},
        Con{F.Color{color}, sphere.rings(rings, slices, ring, slice, M.Vector3{0.0, 1.0, 0.0}, M.Vector3{SC.sin(ring), SC.cos(ring), 0.0})})))

# DrawSphereEx(center, radius, int rings, int slices): the vertices rotated by
# cosf/sinf of DEG2RAD*(180/(rings + 1)) and DEG2RAD*(360/slices).
def sphere(+gnu: Bool, center: M.Vector3, +radius: F32, +rings: F32, +slices: F32, +color: U32) -> S.Plan:
  +r = S.int.of(rings)
  +l = S.int.of(slices)
  +ring = sc(gnu, (S.deg2rad() * (180.0 / (r + 1.0 : F32) : F32) : F32))
  +slice = sc(gnu, (S.deg2rad() * (360.0 / l : F32) : F32))
  +drawn = (r >= 0.0 : F32) && (l >= 1.0 : F32)
  sphere.drawn(count.valid(rings, 4095.0) && count.valid(slices, 4096.0) && (Bool.not(drawn) || (SC.ok(ring) && SC.ok(slice))),
    count.nat((r + 1.0 : F32)), count.nat(l), ring, slice, center, radius, color)

def wire.point(+ring: SC, +slice: SC) -> F.Command:
  v3((SC.cos(ring) * SC.sin(slice) : F32), SC.sin(ring), (SC.cos(ring) * SC.cos(slice) : F32))

def wire.slices(slices: +List<SC>, +a: SC, +b: SC, +s: SC, rest: +List<F.Command>) -> +List<F.Command>:
  match slices:
    case Nil{}: rest
    case Con{+t, more}: Con{wire.point(a, s), Con{wire.point(b, t), Con{wire.point(b, t), Con{wire.point(b, s), Con{wire.point(b, s),
      Con{wire.point(a, s), wire.slices(more, a, b, t, rest)}}}}}}

def wire.slices.start(slices: +List<SC>, +a: SC, +b: SC, rest: +List<F.Command>) -> +List<F.Command>:
  match slices:
    case Nil{}: rest
    case Con{+s, more}: wire.slices(more, a, b, s, rest)

def wire.rings(rings: +List<SC>, +a: SC, +slices: +List<SC>) -> +List<F.Command>:
  match rings:
    case Nil{}: Nil{}
    case Con{+b, more}: wire.slices.start(slices, a, b, wire.rings(more, b, slices))

def wire.rings.start(rings: +List<SC>, +slices: +List<SC>) -> +List<F.Command>:
  match rings:
    case Nil{}: Nil{}
    case Con{+a, more}: wire.rings(more, a, slices)

def sphere_wires.drawn(valid: Bool, +rings: +List<SC>, +slices: +List<SC>, center: M.Vector3, +radius: F32, +color: U32) -> S.Plan:
  match valid:
    case False{}: S.Plan.refused()
    case True{}:
      placed(center, T.scale(radius, radius, radius),
        S.Plan.plain(2, S.Plan.only(True{}, Con{F.Color{color}, wire.rings.start(rings, slices)})))

def sphere_wires.tables(+gnu: Bool, +r: F32, +l: F32, center: M.Vector3, +radius: F32, +color: U32) -> S.Plan:
  +drawn = (r >= F32.neg(1.0) : F32) && (l >= 1.0 : F32)
  +rings = Bool.pick(+List<SC>, drawn, table(count.nat((r + 3.0 : F32)), gnu, 2, 0.0, (180.0 / (r + 1.0 : F32) : F32)), Nil{})
  +slices = Bool.pick(+List<SC>, drawn, table(count.nat((l + 1.0 : F32)), gnu, 3, 0.0, l), Nil{})
  sphere_wires.drawn(table.ok(rings) && table.ok(slices), rings, slices, center, radius, color)

def sphere_wires.counted(valid: Bool, +gnu: Bool, +r: F32, +l: F32, center: M.Vector3, +radius: F32, +color: U32) -> S.Plan:
  match valid:
    case False{}: S.Plan.refused()
    case True{}: sphere_wires.tables(gnu, r, l, center, radius, color)

# DrawSphereWires(center, radius, int rings, int slices): for i < rings + 2
# and j < slices, three lines between the points at DEG2RAD*(270 +
# 180/(rings + 1)*i) and DEG2RAD*(360*j/slices). The ring angles reach 450
# degrees, outside every verified profile set, so every drawn sphere is
# refused today.
def sphere_wires(+gnu: Bool, center: M.Vector3, +radius: F32, +rings: F32, +slices: F32, +color: U32) -> S.Plan:
  sphere_wires.counted(count.valid(rings, 4094.0) && count.valid(slices, 4096.0), gnu, S.int.of(rings), S.int.of(slices), center, radius, color)

# -----------------------------------------------------------------------------
# Cylinders (DrawCylinder, DrawCylinderWires)

def cyl.pick(kind: U32, +sa: F32, +ca: F32, +sb: F32, +cb: F32, +top: F32, +bottom: F32, +h: F32) -> +List<F.Command>:
  match kind:
    case 0: [v3((sa * bottom : F32), 0.0, (ca * bottom : F32)), v3((sb * bottom : F32), 0.0, (cb * bottom : F32)),
      v3((sb * top : F32), h, (cb * top : F32)), v3((sa * top : F32), h, (ca * top : F32)),
      v3((sa * bottom : F32), 0.0, (ca * bottom : F32)), v3((sb * top : F32), h, (cb * top : F32))]
    case 1: [v3(0.0, h, 0.0), v3((sa * top : F32), h, (ca * top : F32)), v3((sb * top : F32), h, (cb * top : F32))]
    case 2: [v3(0.0, h, 0.0), v3((sa * bottom : F32), 0.0, (ca * bottom : F32)), v3((sb * bottom : F32), 0.0, (cb * bottom : F32))]
    case 3: [v3(0.0, 0.0, 0.0), v3((sb * bottom : F32), 0.0, (cb * bottom : F32)), v3((sa * bottom : F32), 0.0, (ca * bottom : F32))]
    case _: [v3((sa * bottom : F32), 0.0, (ca * bottom : F32)), v3((sb * bottom : F32), 0.0, (cb * bottom : F32)),
      v3((sb * bottom : F32), 0.0, (cb * bottom : F32)), v3((sb * top : F32), h, (cb * top : F32)),
      v3((sb * top : F32), h, (cb * top : F32)), v3((sa * top : F32), h, (ca * top : F32)),
      v3((sa * top : F32), h, (ca * top : F32)), v3((sa * bottom : F32), 0.0, (ca * bottom : F32))]

def cyl.verts(+kind: U32, +a: SC, +b: SC, +top: F32, +bottom: F32, +h: F32) -> +List<F.Command>:
  cyl.pick(kind, SC.sin(a), SC.cos(a), SC.sin(b), SC.cos(b), top, bottom, h)

def cyl.pairs(entries: +List<SC>, +a: SC, +kind: U32, +top: F32, +bottom: F32, +h: F32, rest: +List<F.Command>) -> +List<F.Command>:
  match entries:
    case Nil{}: rest
    case Con{+b, more}: List.append(&2, F.Command, cyl.verts(kind, a, b, top, bottom, h), cyl.pairs(more, b, kind, top, bottom, h, rest))

# Loop kind (0 body, 1 cap, 2 cone, 3 base, 4 wires) over i = 0 .. sides - 1.
def cyl.loop(entries: +List<SC>, +kind: U32, +top: F32, +bottom: F32, +h: F32, rest: +List<F.Command>) -> +List<F.Command>:
  match entries:
    case Nil{}: rest
    case Con{+a, more}: cyl.pairs(more, a, kind, top, bottom, h, rest)

def cyl.solid(capped: Bool, +entries: +List<SC>, +top: F32, +bottom: F32, +h: F32) -> +List<F.Command>:
  match capped:
    case True{}: cyl.loop(entries, 0, top, bottom, h, cyl.loop(entries, 1, top, bottom, h, cyl.loop(entries, 3, top, bottom, h, Nil{})))
    case False{}: cyl.loop(entries, 2, top, bottom, h, cyl.loop(entries, 3, top, bottom, h, Nil{}))

def cyl.sides(+sides: F32) -> F32:
  +n = S.int.of(sides)
  Bool.pick(F32, (n < 3.0 : F32), 3.0, n)

def cyl.drawn(valid: Bool, +wires: Bool, +entries: +List<SC>, position: M.Vector3, +top: F32, +bottom: F32, +h: F32, +color: U32) -> S.Plan:
  match valid:
    case False{}: S.Plan.refused()
    case True{}: translated(position, S.Plan.plain(Bool.pick(U32, wires, 2, 3), S.Plan.only(True{},
      Con{F.Color{color}, Bool.pick(+List<F.Command>, wires, cyl.loop(entries, 4, top, bottom, h, Nil{}), cyl.solid((top > 0.0 : F32), entries, top, bottom, h))})))

def cyl.counted(valid: Bool, +gnu: Bool, +wires: Bool, +n: F32, position: M.Vector3, +top: F32, +bottom: F32, +h: F32, +color: U32) -> S.Plan:
  match valid:
    case False{}: S.Plan.refused()
    case True{}:
      +entries = table(count.nat((n + 1.0 : F32)), gnu, 0, 0.0, (360.0 / n : F32))
      cyl.drawn(table.ok(entries), wires, entries, position, top, bottom, h, color)

# DrawCylinder / DrawCylinderWires(position, radiusTop, radiusBottom, height,
# int sides): sides below 3 become 3; angles (DEG2RAD*i)*(360/sides).
def cylinder(+gnu: Bool, +wires: Bool, position: M.Vector3, +top: F32, +bottom: F32, +h: F32, +sides: F32, +color: U32) -> S.Plan:
  cyl.counted(count.valid(sides, 4096.0), gnu, wires, cyl.sides(sides), position, top, bottom, h, color)

# -----------------------------------------------------------------------------
# Cylinders between points and capsules

def frame.point(+p: M.Vector3, +b1: M.Vector3, +b2: M.Vector3, +s: F32, +c: F32) -> M.Vector3:
  M.Vector3{px, py, pz} = p
  M.Vector3{ux, uy, uz} = b1
  M.Vector3{vx, vy, vz} = b2
  M.Vector3{((px + s * ux : F32) + c * vx : F32), ((py + s * uy : F32) + c * vy : F32), ((pz + s * uz : F32) + c * vz : F32)}

def ex.at(+p: M.Vector3, +b1: M.Vector3, +b2: M.Vector3, +r: F32, +e: SC) -> M.Vector3:
  frame.point(p, b1, b2, (SC.sin(e) * r : F32), (SC.cos(e) * r : F32))

type Ends is Data:
  Ends{start: M.Vector3, end: M.Vector3, b1: M.Vector3, b2: M.Vector3, sr: F32, er: F32}

def ex.pick(wires: Bool, +start: M.Vector3, +end: M.Vector3, +sr: F32, +er: F32, +w1: M.Vector3, +w2: M.Vector3, +w3: M.Vector3, +w4: M.Vector3) -> +List<F.Command>:
  match wires:
    case True{}: [vec(w1), vec(w2), vec(w1), vec(w3), vec(w3), vec(w4)]
    case False{}: List.append(&2, F.Command, Bool.pick(+List<F.Command>, (sr > 0.0 : F32), [vec(start), vec(w2), vec(w1)], Nil{}),
      List.append(&2, F.Command, [vec(w1), vec(w2), vec(w3), vec(w2), vec(w4), vec(w3)],
        Bool.pick(+List<F.Command>, (er > 0.0 : F32), [vec(end), vec(w3), vec(w4)], Nil{})))

def ex.verts(+wires: Bool, +ends: Ends, +a: SC, +b: SC) -> +List<F.Command>:
  Ends{+start, +end, +b1, +b2, +sr, +er} = ends
  ex.pick(wires, start, end, sr, er, ex.at(start, b1, b2, sr, a), ex.at(start, b1, b2, sr, b), ex.at(end, b1, b2, er, a), ex.at(end, b1, b2, er, b))

def ex.pairs(entries: +List<SC>, +a: SC, +wires: Bool, +ends: Ends) -> +List<F.Command>:
  match entries:
    case Nil{}: Nil{}
    case Con{+b, more}: List.append(&2, F.Command, ex.verts(wires, ends, a, b), ex.pairs(more, b, wires, ends))

def ex.loop(entries: +List<SC>, +wires: Bool, +ends: Ends) -> +List<F.Command>:
  match entries:
    case Nil{}: Nil{}
    case Con{+a, more}: ex.pairs(more, a, wires, ends)

# The basis of DrawCylinderEx and DrawCapsule: normalize(perpendicular(d)) and
# normalize(cross(b1, d)).
def basis.first(+direction: M.Vector3) -> M.Vector3:
  M.Vector3.normalize(M.Vector3.perpendicular(direction))

def basis.second(+first: M.Vector3, +direction: M.Vector3) -> M.Vector3:
  M.Vector3.normalize(M.Vector3.cross_product(first, direction))

def ex.drawn(valid: Bool, +wires: Bool, +entries: +List<SC>, +ends: Ends, +color: U32) -> S.Plan:
  match valid:
    case False{}: S.Plan.refused()
    case True{}: S.Plan.plain(Bool.pick(U32, wires, 2, 3), S.Plan.only(True{}, Con{F.Color{color}, ex.loop(entries, wires, ends)}))

def ex.counted(valid: Bool, +gnu: Bool, +wires: Bool, +n: F32, +start: M.Vector3, +end: M.Vector3, +direction: M.Vector3, +sr: F32, +er: F32, +color: U32) -> S.Plan:
  match valid:
    case False{}: S.Plan.refused()
    case True{}:
      +entries = table(count.nat((n + 1.0 : F32)), gnu, 1, 0.0, (pi2() / n : F32))
      +b1 = basis.first(direction)
      ex.drawn(table.ok(entries), wires, entries, Ends{start, end, b1, basis.second(b1, direction), sr, er}, color)

def zero(+v: M.Vector3) -> Bool:
  M.Vector3{x, y, z} = v
  F32.is_eq(x, 0.0) && F32.is_eq(y, 0.0) && F32.is_eq(z, 0.0)

def ex.directed(empty: Bool, +valid: Bool, +gnu: Bool, +wires: Bool, +n: F32, +start: M.Vector3, +end: M.Vector3, +direction: M.Vector3, +sr: F32, +er: F32, +color: U32) -> S.Plan:
  match empty:
    case True{}: S.Plan.require(valid, S.Plan.empty())
    case False{}: ex.counted(valid, gnu, wires, n, start, end, direction, sr, er, color)

# DrawCylinderEx / DrawCylinderWiresEx(start, end, startRadius, endRadius, int
# sides): nothing when start equals end; angles ((2*PI)/sides)*i.
def cylinder_ex(+gnu: Bool, +wires: Bool, +start: M.Vector3, +end: M.Vector3, +sr: F32, +er: F32, +sides: F32, +color: U32) -> S.Plan:
  +direction = M.Vector3.subtract(end, start)
  ex.directed(zero(direction), count.valid(sides, 4096.0), gnu, wires, cyl.sides(sides), start, end, direction, sr, er, color)

type Cap is Data:
  Cap{center: M.Vector3, b0: M.Vector3, b1: M.Vector3, b2: M.Vector3, radius: F32}

def cap.point(center: M.Vector3, b0: M.Vector3, b1: M.Vector3, b2: M.Vector3, +radius: F32, +h: F32, +rs: F32, +rc: F32) -> M.Vector3:
  M.Vector3{cx, cy, cz} = center
  M.Vector3{ax, ay, az} = b0
  M.Vector3{ux, uy, uz} = b1
  M.Vector3{vx, vy, vz} = b2
  M.Vector3{(cx + ((h * ax : F32) + (rs * ux : F32) + (rc * vx : F32) : F32) * radius : F32),
    (cy + ((h * ay : F32) + (rs * uy : F32) + (rc * vy : F32) : F32) * radius : F32),
    (cz + ((h * az : F32) + (rs * uz : F32) + (rc * vz : F32) : F32) * radius : F32)}

# A hemisphere point: center + (sinf(ring)*b0 + sinf(slice)cosf(ring)*b1 +
# cosf(slice)cosf(ring)*b2)*radius.
def cap.at(+cap: Cap, +slice: SC, +ring: SC) -> M.Vector3:
  Cap{center, b0, b1, b2, +radius} = cap
  cap.point(center, b0, b1, b2, radius, SC.sin(ring), (SC.sin(slice) * SC.cos(ring) : F32), (SC.cos(slice) * SC.cos(ring) : F32))

def cap.pick(kind: U32, +w1: M.Vector3, +w2: M.Vector3, +w3: M.Vector3, +w4: M.Vector3) -> +List<F.Command>:
  match kind:
    case 0: [vec(w1), vec(w2), vec(w3), vec(w2), vec(w4), vec(w3)]
    case 1: [vec(w1), vec(w3), vec(w2), vec(w2), vec(w3), vec(w4)]
    case _: [vec(w1), vec(w2), vec(w2), vec(w3), vec(w1), vec(w3), vec(w2), vec(w4), vec(w3), vec(w4)]

def cap.verts(+kind: U32, +cap: Cap, +ra: SC, +rb: SC, +sa: SC, +sb: SC) -> +List<F.Command>:
  cap.pick(kind, cap.at(cap, sa, ra), cap.at(cap, sb, ra), cap.at(cap, sa, rb), cap.at(cap, sb, rb))

def cap.slices(slices: +List<SC>, +sa: SC, +kind: U32, +cap: Cap, +ra: SC, +rb: SC, rest: +List<F.Command>) -> +List<F.Command>:
  match slices:
    case Nil{}: rest
    case Con{+sb, more}: List.append(&2, F.Command, cap.verts(kind, cap, ra, rb, sa, sb), cap.slices(more, sb, kind, cap, ra, rb, rest))

def cap.slices.start(slices: +List<SC>, +kind: U32, +cap: Cap, +ra: SC, +rb: SC, rest: +List<F.Command>) -> +List<F.Command>:
  match slices:
    case Nil{}: rest
    case Con{+sa, more}: cap.slices(more, sa, kind, cap, ra, rb, rest)

def cap.rings(rings: +List<SC>, +ra: SC, +kind: U32, +cap: Cap, +slices: +List<SC>, rest: +List<F.Command>) -> +List<F.Command>:
  match rings:
    case Nil{}: rest
    case Con{+rb, more}: cap.slices.start(slices, kind, cap, ra, rb, cap.rings(more, rb, kind, cap, slices, rest))

def cap.rings.start(rings: +List<SC>, +kind: U32, +cap: Cap, +slices: +List<SC>, rest: +List<F.Command>) -> +List<F.Command>:
  match rings:
    case Nil{}: rest
    case Con{+ra, more}: cap.rings(more, ra, kind, cap, slices, rest)

def middle.pick(wires: Bool, +w1: M.Vector3, +w2: M.Vector3, +w3: M.Vector3, +w4: M.Vector3) -> +List<F.Command>:
  match wires:
    case True{}: [vec(w1), vec(w3), vec(w2), vec(w4), vec(w2), vec(w3)]
    case False{}: [vec(w1), vec(w2), vec(w3), vec(w2), vec(w4), vec(w3)]

def middle.verts(+wires: Bool, +start: M.Vector3, +end: M.Vector3, +b1: M.Vector3, +b2: M.Vector3, +radius: F32, +a: SC, +b: SC) -> +List<F.Command>:
  middle.pick(wires, ex.at(start, b1, b2, radius, a), ex.at(start, b1, b2, radius, b), ex.at(end, b1, b2, radius, a), ex.at(end, b1, b2, radius, b))

def middle.pairs(entries: +List<SC>, +a: SC, +wires: Bool, +start: M.Vector3, +end: M.Vector3, +b1: M.Vector3, +b2: M.Vector3, +radius: F32) -> +List<F.Command>:
  match entries:
    case Nil{}: Nil{}
    case Con{+b, more}: List.append(&2, F.Command, middle.verts(wires, start, end, b1, b2, radius, a, b), middle.pairs(more, b, wires, start, end, b1, b2, radius))

def middle.loop(drawn: Bool, entries: +List<SC>, +wires: Bool, +start: M.Vector3, +end: M.Vector3, +b1: M.Vector3, +b2: M.Vector3, +radius: F32) -> +List<F.Command>:
  match drawn entries:
    case True{} Con{+a, more}: middle.pairs(more, a, wires, start, end, b1, b2, radius)
    case _ _: Nil{}

def capsule.body(+wires: Bool, +sphere: Bool, +start: M.Vector3, +end: M.Vector3, +direction: M.Vector3, +radius: F32, +rings: +List<SC>, +slices: +List<SC>) -> +List<F.Command>:
  +b0 = M.Vector3.normalize(direction)
  +b1 = basis.first(direction)
  +b2 = basis.second(b1, direction)
  +k0 = Bool.pick(U32, wires, 2, 0)
  +k1 = Bool.pick(U32, wires, 2, 1)
  cap.rings.start(rings, k0, Cap{end, b0, b1, b2, radius}, slices,
    cap.rings.start(rings, k1, Cap{start, M.Vector3.scale(b0, F32.neg(1.0)), b1, b2, radius}, slices,
      middle.loop(Bool.not(sphere), slices, wires, start, end, b1, b2, radius)))

def capsule.drawn(valid: Bool, +wires: Bool, +sphere: Bool, +start: M.Vector3, +end: M.Vector3, +direction: M.Vector3, +radius: F32, +rings: +List<SC>, +slices: +List<SC>, +color: U32) -> S.Plan:
  match valid:
    case False{}: S.Plan.refused()
    case True{}: S.Plan.plain(Bool.pick(U32, wires, 2, 3), S.Plan.only(True{},
      Con{F.Color{color}, capsule.body(wires, sphere, start, end, direction, radius, rings, slices)}))

def capsule.counted(valid: Bool, +gnu: Bool, +wires: Bool, +n: F32, +r: F32, +start: M.Vector3, +end: M.Vector3, +radius: F32, +color: U32) -> S.Plan:
  match valid:
    case False{}: S.Plan.refused()
    case True{}:
      +difference = M.Vector3.subtract(end, start)
      +sphere = zero(difference)
      +slices = table(count.nat((n + 1.0 : F32)), gnu, 1, 0.0, (pi2() / n : F32))
      +rings = Bool.pick(+List<SC>, (r >= 1.0 : F32), table(count.nat((r + 1.0 : F32)), gnu, 1, 0.0, ((F.float(1078530011) * 0.5 : F32) / r : F32)), Nil{})
      +used = (r >= 1.0 : F32) || Bool.not(sphere)
      capsule.drawn((Bool.not(used) || table.ok(slices)) && table.ok(rings), wires, sphere, start, end,
        Bool.pick(M.Vector3, sphere, M.Vector3{0.0, 1.0, 0.0}, difference), radius, rings, slices, color)

# DrawCapsule / DrawCapsuleWires(start, end, radius, int slices, int rings):
# slices below 3 become 3 (rings are not clamped); both hemispheres, then the
# middle unless start equals end (a sphere around (0, 1, 0)-based axes).
def capsule(+gnu: Bool, +wires: Bool, +start: M.Vector3, +end: M.Vector3, +radius: F32, +slices: F32, +rings: F32, +color: U32) -> S.Plan:
  capsule.counted(count.valid(slices, 4096.0) && count.valid(rings, 4096.0), gnu, wires, cyl.sides(slices), S.int.of(rings), start, end, radius, color)
