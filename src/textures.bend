# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rtextures.c (DrawTexturePro and
# DrawTextureNPatch) and of rlgl.h's OpenGL 1.1 matrix calls as rlsw.h
# (src/external/rlsw.h, MIT, LICENSES/rlsw.txt) computes them
# (swTranslatef, swRotatef, swScalef); LICENSES/raylib.txt. Each draw is the
# rlSetTexture/rlPushMatrix/.../rlBegin/rlColor4ub/rlTexCoord2f/rlVertex2f/
# rlEnd stream rtextures.c issues, with its F32 arithmetic in source order;
# src/frame.bend renders it. Rotations take sinf/cosf of rotation*DEG2RAD
# and are reproduced only inside the M.Libm profile's verified arguments
# (src/shapes.bend trig.ok); see docs/TEXTURES.md.
import Base
import ./frame.bend as F
import ./shapes.bend as S
import ./trig.bend as Trig

# -----------------------------------------------------------------------------
# rlgl matrix calls (swTranslatef, swScalef, swRotatef)

def translate(+x: F32, +y: F32, +z: F32) -> S.Plan:
  S.Plan.only(True{}, [F.Multiply{F.Matrix4.translate(x, y, z)}])

def scale(+x: F32, +y: F32, +z: F32) -> S.Plan:
  S.Plan.only(True{}, [F.Multiply{F.Matrix4.scale(x, y, z)}])

def rotate.matrix(+x: F32, +y: F32, +z: F32, values: F32 & F32) -> F.Matrix4:
  (+c, +s) = values
  F.Matrix4.rotation(x, y, z, c, s)

def rotate.unit(+gnu: Bool, +angle: F32, +x: F32, +y: F32, +z: F32) -> S.Plan:
  S.Plan.only(S.trig.ok(gnu, angle), [F.Multiply{rotate.matrix(x, y, z, Trig.sincos_for(gnu, angle))}])

def rotate.scaled(+gnu: Bool, +angle: F32, +x: F32, +y: F32, +z: F32, +k: F32) -> S.Plan:
  rotate.unit(gnu, angle, (x * k : F32), (y * k : F32), (z * k : F32))

# swRotatef(angle, x, y, z): the angle times SW_DEG2RAD; an axis whose squared
# length is neither 1 nor 0 is scaled by 1/sqrtf of it.
def rotate(+gnu: Bool, +degrees: F32, +x: F32, +y: F32, +z: F32) -> S.Plan:
  +angle = (degrees * S.deg2rad() : F32)
  +length = (x * x + y * y + z * z : F32)
  +unit = F32.is_eq(length, 1.0) || F32.is_eq(length, 0.0)
  rotate.scaled(gnu, angle, x, y, z, Bool.pick(F32, unit, 1.0, (1.0 / F32.sqrt(length) : F32)))

# -----------------------------------------------------------------------------
# DrawTexturePro

type Quad is Data:
  Quad{tlx: F32, tly: F32, blx: F32, bly: F32, brx: F32, bry: F32, tx: F32, ty: F32}

# rotation == 0: the destination less the origin, axis-aligned.
def pro.flat(+x: F32, +y: F32, +width: F32, +height: F32) -> Quad:
  Quad{x, y, x, (y + height : F32), (x + width : F32), (y + height : F32), (x + width : F32), y}

# x + dx*cos - dy*sin, y + dx*sin + dy*cos for the four corners (dx, dy the
# corner relative to the destination, starting at -origin).
def pro.turned(+x: F32, +y: F32, +dx: F32, +dy: F32, +width: F32, +height: F32, values: F32 & F32) -> Quad:
  (+c, +s) = values
  Quad{((x + dx * c : F32) - dy * s : F32), ((y + dx * s : F32) + dy * c : F32),
    ((x + dx * c : F32) - (dy + height : F32) * s : F32), ((y + dx * s : F32) + (dy + height : F32) * c : F32),
    ((x + (dx + width : F32) * c : F32) - (dy + height : F32) * s : F32), ((y + (dx + width : F32) * s : F32) + (dy + height : F32) * c : F32),
    ((x + (dx + width : F32) * c : F32) - dy * s : F32), ((y + (dx + width : F32) * s : F32) + dy * c : F32)}

# The quad's texcoords: u of the left and right edges (swapped when the
# source is flipped), v of the top and bottom.
def pro.stream(+kind: U32, +tint: U32, +left: F32, +right: F32, +top: F32, +bottom: F32, quad: Quad) -> +List<F.Command>:
  Quad{tlx, tly, blx, bly, brx, bry, tx, ty} = quad
  [F.Texture{kind}, F.Begin{4}, F.Color{tint}, F.TexCoord{left, top}, F.Point{tlx, tly}, F.TexCoord{left, bottom}, F.Point{blx, bly},
    F.TexCoord{right, bottom}, F.Point{brx, bry}, F.TexCoord{right, top}, F.Point{tx, ty}, F.End{}, F.Texture{0}]

def pro.drawn(valid: Bool, +kind: U32, +tint: U32, +tw: F32, +th: F32, +flip: Bool, +sx: F32, +sy: F32, +sw: F32, +sh: F32, quad: Quad) -> S.Plan:
  +low = (sx / tw : F32)
  +high = ((sx + sw : F32) / tw : F32)
  S.Plan.only(valid, pro.stream(kind, tint, Bool.pick(F32, flip, high, low), Bool.pick(F32, flip, low, high), (sy / th : F32), ((sy + sh : F32) / th : F32), quad))

def pro.select(flat: Bool, +gnu: Bool, +kind: U32, +tint: U32, +tw: F32, +th: F32, +flip: Bool, +sx: F32, +sy: F32, +sw: F32, +sh: F32, +dx: F32, +dy: F32, +dw: F32, +dh: F32, +ox: F32, +oy: F32, +rotation: F32) -> S.Plan:
  match flat:
    case True{}: pro.drawn(True{}, kind, tint, tw, th, flip, sx, sy, sw, sh, pro.flat((dx - ox : F32), (dy - oy : F32), dw, dh))
    case False{}:
      +arg = (rotation * S.deg2rad() : F32)
      pro.drawn(S.trig.ok(gnu, arg), kind, tint, tw, th, flip, sx, sy, sw, sh,
        pro.turned(dx, dy, F32.neg(ox), F32.neg(oy), dw, dh, Trig.sincos_for(gnu, arg)))

# DrawTexturePro for a texture of tw x th texels bound as kind: a negative
# source width flips u, a negative source height moves the source y by it
# (flipping v), negative destination sizes are made positive; rotation 0
# (either sign) skips sinf/cosf.
def pro(+gnu: Bool, +kind: U32, +tw: F32, +th: F32, +sx: F32, +sy: F32, +sw: F32, +sh: F32, +dx: F32, +dy: F32, +dw: F32, +dh: F32, +ox: F32, +oy: F32, +rotation: F32, +tint: U32) -> S.Plan:
  +flip = (sw < 0.0 : F32)
  pro.select(F32.is_eq(rotation, 0.0), gnu, kind, tint, tw, th, flip, sx, Bool.pick(F32, (sh < 0.0 : F32), (sy - sh : F32), sy),
    Bool.pick(F32, flip, (sw * F32.neg(1.0) : F32), sw), sh, dx, dy, Bool.pick(F32, (dw < 0.0 : F32), (dw * F32.neg(1.0) : F32), dw),
    Bool.pick(F32, (dh < 0.0 : F32), (dh * F32.neg(1.0) : F32), dh), ox, oy, rotation)

# -----------------------------------------------------------------------------
# DrawTextureNPatch

# The four columns (x and u) or rows (y and v) of a patch: outer, inner,
# inner, outer.
type Lines is Data:
  Lines{a: F32, b: F32, c: F32, d: F32}

def Lines.at(+lines: Lines, +i: U32) -> F32:
  Lines{a, b, c, d} = lines
  Bool.pick(F32, U32.is_eq(i, 0), a, Bool.pick(F32, U32.is_eq(i, 1), b, Bool.pick(F32, U32.is_eq(i, 2), c, d)))

# Columns i..k and rows j..l: (i, l), (k, l), (k, j), (i, j).
def cell(+xs: Lines, +ys: Lines, +us: Lines, +vs: Lines, +i: U32, +k: U32, +j: U32, +l: U32) -> +List<F.Command>:
  [F.TexCoord{Lines.at(us, i), Lines.at(vs, l)}, F.Point{Lines.at(xs, i), Lines.at(ys, l)},
    F.TexCoord{Lines.at(us, k), Lines.at(vs, l)}, F.Point{Lines.at(xs, k), Lines.at(ys, l)},
    F.TexCoord{Lines.at(us, k), Lines.at(vs, j)}, F.Point{Lines.at(xs, k), Lines.at(ys, j)},
    F.TexCoord{Lines.at(us, i), Lines.at(vs, j)}, F.Point{Lines.at(xs, i), Lines.at(ys, j)}]

def cell.if(drawn: Bool, +xs: Lines, +ys: Lines, +us: Lines, +vs: Lines, +i: U32, +k: U32, +j: U32, +l: U32) -> +List<F.Command>:
  match drawn:
    case False{}: Nil{}
    case True{}: cell(xs, ys, us, vs, i, k, j, l)

def cells.nine.middle(drawn: Bool, +center: Bool, +xs: Lines, +ys: Lines, +us: Lines, +vs: Lines) -> +List<F.Command>:
  match drawn:
    case False{}: Nil{}
    case True{}:
      List.append(&2, F.Command, cell(xs, ys, us, vs, 0, 1, 1, 2), List.append(&2, F.Command, cell.if(center, xs, ys, us, vs, 1, 2, 1, 2),
        cell(xs, ys, us, vs, 2, 3, 1, 2)))

def cells.nine(+center: Bool, +middle: Bool, +xs: Lines, +ys: Lines, +us: Lines, +vs: Lines) -> +List<F.Command>:
  List.append(&2, F.Command, cell(xs, ys, us, vs, 0, 1, 0, 1), List.append(&2, F.Command, cell.if(center, xs, ys, us, vs, 1, 2, 0, 1),
    List.append(&2, F.Command, cell(xs, ys, us, vs, 2, 3, 0, 1), List.append(&2, F.Command, cells.nine.middle(middle, center, xs, ys, us, vs),
    List.append(&2, F.Command, cell(xs, ys, us, vs, 0, 1, 2, 3), List.append(&2, F.Command, cell.if(center, xs, ys, us, vs, 1, 2, 2, 3),
    cell(xs, ys, us, vs, 2, 3, 2, 3)))))))

# THREE_PATCH_VERTICAL draws its middle row when drawCenter is set (never
# cleared for this layout).
def cells.vertical(+center: Bool, +xs: Lines, +ys: Lines, +us: Lines, +vs: Lines) -> +List<F.Command>:
  List.append(&2, F.Command, cell(xs, ys, us, vs, 0, 3, 0, 1), List.append(&2, F.Command, cell.if(center, xs, ys, us, vs, 0, 3, 1, 2),
    cell(xs, ys, us, vs, 0, 3, 2, 3)))

def cells.horizontal(+center: Bool, +xs: Lines, +ys: Lines, +us: Lines, +vs: Lines) -> +List<F.Command>:
  List.append(&2, F.Command, cell(xs, ys, us, vs, 0, 1, 0, 3), List.append(&2, F.Command, cell.if(center, xs, ys, us, vs, 1, 2, 0, 3),
    cell(xs, ys, us, vs, 2, 3, 0, 3)))

# Other layout values draw no quad.
def cells(layout: U32, +center: Bool, +middle: Bool, +xs: Lines, +ys: Lines, +us: Lines, +vs: Lines) -> +List<F.Command>:
  match layout:
    case 0: cells.nine(center, middle, xs, ys, us, vs)
    case 1: cells.vertical(center, xs, ys, us, vs)
    case 2: cells.horizontal(center, xs, ys, us, vs)
    case _: Nil{}

def npatch.stream(+kind: U32, +tint: U32, +dx: F32, +dy: F32, +ox: F32, +oy: F32, rotation: F.Matrix4, quads: +List<F.Command>) -> +List<F.Command>:
  Con{F.Texture{kind}, Con{F.Push{}, Con{F.Multiply{F.Matrix4.translate(dx, dy, 0.0)}, Con{F.Multiply{rotation},
    Con{F.Multiply{F.Matrix4.translate(F32.neg(ox), F32.neg(oy), 0.0)}, Con{F.Begin{4}, Con{F.Color{tint},
    List.append(&2, F.Command, quads, [F.End{}, F.Pop{}, F.Texture{0}])}}}}}}}

# Borders that do not fit the patch are scaled to it (and the center column or
# middle row is skipped); A..D are the outer and inner edges.
def npatch.edges(+gnu: Bool, +kind: U32, +tint: U32, +tw: F32, +th: F32, +sx: F32, +sy: F32, +sw: F32, +sh: F32, +layout: U32, +pw: F32, +ph: F32, +left: F32, +top: F32, +right: F32, +bottom: F32, +dx: F32, +dy: F32, +ox: F32, +oy: F32, +rotation: F32) -> S.Plan:
  +center = Bool.not((pw <= (left + right : F32) : F32) && Bool.not(U32.is_eq(layout, 1)))
  +middle = Bool.not((ph <= (top + bottom : F32) : F32) && Bool.not(U32.is_eq(layout, 2)))
  +l = Bool.pick(F32, center, left, ((left / (left + right : F32) : F32) * pw : F32))
  +r = Bool.pick(F32, center, right, (pw - l : F32))
  +t = Bool.pick(F32, middle, top, ((top / (top + bottom : F32) : F32) * ph : F32))
  +b = Bool.pick(F32, middle, bottom, (ph - t : F32))
  +angle = (rotation * S.deg2rad() : F32)
  S.Plan.only(S.trig.ok(gnu, angle), npatch.stream(kind, tint, dx, dy, ox, oy, rotate.matrix(0.0, 0.0, 1.0, Trig.sincos_for(gnu, angle)),
    cells(layout, center, middle, Lines{0.0, l, (pw - r : F32), pw}, Lines{0.0, t, (ph - b : F32), ph},
      Lines{(sx / tw : F32), ((sx + l : F32) / tw : F32), (((sx + sw : F32) - r : F32) / tw : F32), ((sx + sw : F32) / tw : F32)},
      Lines{(sy / th : F32), ((sy + t : F32) / th : F32), (((sy + sh : F32) - b : F32) / th : F32), ((sy + sh : F32) / th : F32)})))

# DrawTextureNPatch for a texture of tw x th texels bound as kind. The
# borders and layout are C ints given as integral F32 values (the caller
# checks them); (int)dest.width and (int)dest.height must be defined.
# rlPushMatrix, rlTranslatef(dest), rlRotatef(rotation, 0, 0, 1),
# rlTranslatef(-origin), the quads, rlPopMatrix.
def npatch(+gnu: Bool, +kind: U32, +tw: F32, +th: F32, +sx: F32, +sy: F32, +sw: F32, +sh: F32, +left: F32, +top: F32, +right: F32, +bottom: F32, +layout: U32, +dx: F32, +dy: F32, +dw: F32, +dh: F32, +ox: F32, +oy: F32, +rotation: F32, +tint: U32) -> S.Plan:
  +pw = Bool.pick(F32, (S.int.of(dw) <= 0.0 : F32), 0.0, dw)
  +ph = Bool.pick(F32, (S.int.of(dh) <= 0.0 : F32), 0.0, dh)
  S.Plan.require(S.int.valid(dw) && S.int.valid(dh), npatch.edges(gnu, kind, tint, tw, th, Bool.pick(F32, (sw < 0.0 : F32), (sx - sw : F32), sx),
    Bool.pick(F32, (sh < 0.0 : F32), (sy - sh : F32), sy), sw, sh, layout, Bool.pick(F32, U32.is_eq(layout, 1), sw, pw),
    Bool.pick(F32, U32.is_eq(layout, 2), sh, ph), left, top, right, bottom, dx, dy, ox, oy, rotation))
