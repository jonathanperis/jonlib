# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rmodels.c DrawMesh and DrawBillboardPro
# (zlib, LICENSES/raylib.txt) as the software renderer runs them: DrawMesh's
# OpenGL 1.1 branch (rlEnableStatePointer, rlDrawVertexArray or
# rlDrawVertexArrayElements) reaches rlsw.h's swDrawArrays/swDrawElements
# (src/external/rlsw.h, MIT, LICENSES/rlsw.txt), which push each vertex
# through the immediate path: texcoord (texture matrix applied), color
# (byte*SW_INV_255), position. Each draw becomes that command stream, which
# src/frame.bend renders; F32 arithmetic keeps rmodels.c's order
# (uncontracted, as the reference renderer is built). See docs/MODELS.md.
import Base
import ./../jonmath.bend as M
import ./frame.bend as F
import ./shapes.bend as S
import ./trig.bend as Trig

type Group is Data:
  Group{commands: +List<F.Command>}

def groups.reverse(xs: +List<Group>, acc: +List<Group>) -> +List<Group>:
  match xs:
    case Nil{}: acc
    case Con{+g, rest}: groups.reverse(rest, Con{g, acc})

# One Vertex3 group per vertex (swDrawArrays reads p[0], p[1], p[2]).
def positions(xs: +List<F32>, acc: +List<Group>) -> +List<Group>:
  match xs:
    case Con{+x, Con{+y, Con{+z, rest}}}: positions(rest, Con{Group{[F.Vertex3{x, y, z}]}, acc})
    case _: groups.reverse(acc, Nil{})

def Group.prefix(+command: F.Command, +g: Group) -> Group:
  Group{commands} = g
  Group{Con{command, commands}}

def color.word(+r: U32, +g: U32, +b: U32, +a: U32) -> U32:
  ((r << 24n) .|. (g << 16n) .|. (b << 8n) .|. a : U32)

# The color set before the position (sw_immediate_set_color).
def with_colors(gs: +List<Group>, cs: +List<U32>, acc: +List<Group>) -> +List<Group>:
  match gs cs:
    case Con{+g, rest} Con{+r, Con{+gg, Con{+b, Con{+a, more}}}}: with_colors(rest, more, Con{Group.prefix(F.Color{color.word(r, gg, b, a)}, g), acc})
    case _ _: groups.reverse(acc, Nil{})

# The texcoord set first (sw_immediate_set_texcoord).
def with_texcoords(gs: +List<Group>, ts: +List<F32>, acc: +List<Group>) -> +List<Group>:
  match gs ts:
    case Con{+g, rest} Con{+u, Con{+v, more}}: with_texcoords(rest, more, Con{Group.prefix(F.TexCoord{u, v}, g), acc})
    case _ _: groups.reverse(acc, Nil{})

def colored(gs: +List<Group>, cs: Maybe<&2, +List<U32>>) -> +List<Group>:
  match cs:
    case None{}: gs
    case Some{+values}: with_colors(gs, values, Nil{})

def textured(gs: +List<Group>, ts: Maybe<&2, +List<F32>>) -> +List<Group>:
  match ts:
    case None{}: gs
    case Some{+values}: with_texcoords(gs, values, Nil{})

# The vertex groups of a mesh, in vertex order.
def vertex.groups(+vertices: +List<F32>, texcoords: Maybe<&2, +List<F32>>, colors: Maybe<&2, +List<U32>>) -> +List<Group>:
  textured(colored(positions(vertices, Nil{}), colors), texcoords)

# Random access by index (swDrawElements): a balanced tree of the groups.
type Tree is Data:
  Tip{}
  Leaf{value: Group}
  Node{left: Tree, right: Tree}

def trees.reverse(xs: +List<Tree>, acc: +List<Tree>) -> +List<Tree>:
  match xs:
    case Nil{}: acc
    case Con{+t, rest}: trees.reverse(rest, Con{t, acc})

def leaves(xs: +List<Group>, acc: +List<Tree>) -> +List<Tree>:
  match xs:
    case Nil{}: trees.reverse(acc, Nil{})
    case Con{+g, rest}: leaves(rest, Con{Leaf{g}, acc})

def pairs(xs: +List<Tree>, acc: +List<Tree>) -> +List<Tree>:
  match xs:
    case Con{+a, Con{+b, rest}}: pairs(rest, Con{Node{a, b}, acc})
    case Con{+a, Nil{}}: trees.reverse(Con{Node{a, Tip{}}, acc}, Nil{})
    case _: trees.reverse(acc, Nil{})

def levels(d: Nat, +xs: +List<Tree>) -> +List<Tree>:
  match d:
    case 0n: xs
    case 1n+k: levels(k, pairs(xs, Nil{}))

def tree.first(xs: +List<Tree>) -> Tree:
  match xs:
    case Con{+t, _}: t
    case Nil{}: Tip{}

def depth(+count: U32) -> Nat:
  Bool.pick(Nat, (count <= 1 : U32), 0n, 1n+U32.log2((count - 1 : U32)))

def tree.get(+d: Nat, t: Tree, +i: U32) -> Group:
  match d t:
    case 0n Leaf{g}: g
    case 1n+k Node{l, r}: tree.get(k, Bool.pick(Tree, U32.is_eq(((i >> k) .&. 1 : U32), 1), r, l), i)
    case _ _: Group{Nil{}}

def indexed(indices: +List<U32>, +d: Nat, +t: Tree, acc: +List<Group>) -> +List<Group>:
  match indices:
    case Nil{}: groups.reverse(acc, Nil{})
    case Con{+i, rest}: indexed(rest, d, t, Con{tree.get(d, t, i), acc})

def flatten.group(cs: +List<F.Command>, acc: +List<F.Command>) -> +List<F.Command>:
  match cs:
    case Nil{}: acc
    case Con{+c, rest}: flatten.group(rest, Con{c, acc})

def flatten.one(+g: Group, acc: +List<F.Command>) -> +List<F.Command>:
  Group{+cs} = g
  flatten.group(cs, acc)

# The groups' commands followed by tail (accumulated reversed).
def flatten(gs: +List<Group>, acc: +List<F.Command>, +tail: +List<F.Command>) -> +List<F.Command>:
  match gs:
    case Nil{}: List.reverse.go(&2, F.Command, acc, tail)
    case Con{+g, rest}: flatten(rest, flatten.one(g, acc), tail)

def drawn(indices: Maybe<&2, +List<U32>>, +vc: U32, +groups: +List<Group>) -> +List<Group>:
  match indices:
    case None{}: groups
    case Some{+xs}:
      +d = depth(vc)
      indexed(xs, d, tree.first(levels(d, leaves(groups, Nil{}))), Nil{})

def triangles(vertices: Maybe<&2, +List<F32>>, texcoords: Maybe<&2, +List<F32>>, colors: Maybe<&2, +List<U32>>, indices: Maybe<&2, +List<U32>>, +vc: U32, +tail: +List<F.Command>) -> +List<F.Command>:
  match vertices:
    case None{}: tail
    case Some{+xs}: Con{F.Begin{3}, flatten(drawn(indices, vc, vertex.groups(xs, texcoords, colors)), Nil{}, Con{F.End{}, tail})}

# DrawMesh under OpenGL 1.1: rlEnableTexture(diffuse) when the mesh has
# texcoords and the diffuse id is positive (kind > 0, the bound texture's
# kind), rlPushMatrix, rlMultMatrixf(transform), rlColor4ub(diffuse color),
# the triangles (GL_TRIANGLES over the vertices, or over the indices), then
# rlPopMatrix and rlDisableTexture. Without vertices swDrawArrays draws
# nothing (an rlsw error).
def mesh.body(+color: U32, +transform: F.Matrix4, vertices: Maybe<&2, +List<F32>>, texcoords: Maybe<&2, +List<F32>>, colors: Maybe<&2, +List<U32>>, indices: Maybe<&2, +List<U32>>, +vc: U32) -> +List<F.Command>:
  Con{F.Push{}, Con{F.Multiply{transform}, Con{F.Color{color}, triangles(vertices, texcoords, colors, indices, vc, [F.Pop{}, F.Texture{0}])}}}

def mesh(+kind: U32, +color: U32, +transform: F.Matrix4, vertices: Maybe<&2, +List<F32>>, texcoords: Maybe<&2, +List<F32>>, colors: Maybe<&2, +List<U32>>, indices: Maybe<&2, +List<U32>>, +vc: U32) -> S.Plan:
  +body = mesh.body(color, transform, vertices, texcoords, colors, indices, vc)
  S.Plan.only(True{}, Bool.pick(+List<F.Command>, U32.is_eq(kind, 0), body, Con{F.Texture{kind}, body}))

# -----------------------------------------------------------------------------
# DrawBillboardPro

def vec.zero() -> M.Vector3:
  M.Vector3{0.0, 0.0, 0.0}

def vec(+v: M.Vector3) -> F.Command:
  M.Vector3{x, y, z} = v
  F.Vertex3{x, y, z}

# Vector3Subtract(p, origin3D), Vector3RotateByAxisAngle when rotation != 0,
# Vector3Add(position).
def billboard.point(+p: M.Vector3, +origin: M.Vector3, +turn: Bool, +gnu: Bool, +forward: M.Vector3, +angle: F32, +position: M.Vector3) -> M.Vector3:
  +moved = M.Vector3.subtract(p, origin)
  M.Vector3.add(Bool.pick(M.Vector3, turn, M.Vector3.rotate_by_axis_angle_for(Bool.pick(M.Libm, gnu, M.Glibc239Libm{}, M.AppleLibm{}), moved, forward, angle), moved), position)

def billboard.stream(+kind: U32, +tint: U32, +u0: F32, +u1: F32, +vt: F32, +vb: F32, +p0: M.Vector3, +p1: M.Vector3, +p2: M.Vector3, +p3: M.Vector3) -> +List<F.Command>:
  [F.Texture{kind}, F.Begin{4}, F.Color{tint}, F.TexCoord{u0, vb}, vec(p0), F.TexCoord{u1, vb}, vec(p1), F.TexCoord{u1, vt}, vec(p2),
    F.TexCoord{u0, vt}, vec(p3), F.End{}, F.Texture{0}]

def billboard.flip(+negative: Bool, +v: M.Vector3) -> M.Vector3:
  Bool.pick(M.Vector3, negative, M.Vector3.negate(v), v)

# right = (view.m0, view.m4, view.m8)*size.x and up*size.y; a negative size
# flips the source (x -= size, width *= -1), the vector and the origin; the
# corners 0, right, up + right, up less origin3D (the normalized vectors
# scaled by the origin), rotated about cross(right, up) by rotation*DEG2RAD
# when rotation != 0 (sinf/cosf of half the angle, checked for the profile),
# moved to the position; texcoords source/size of the texture (int width and
# height as floats). rlSetTexture(id), RL_QUADS, rlColor4ub(tint), four
# texcoord/vertex pairs, rlSetTexture(0).
def billboard(+gnu: Bool, +kind: U32, +tw: F32, +th: F32, +right0: M.Vector3, +sx: F32, +sy: F32, +sw: F32, +sh: F32, +position: M.Vector3, +up0: M.Vector3, +size_x: F32, +size_y: F32, +ox: F32, +oy: F32, +rotation: F32, +tint: U32) -> S.Plan:
  +flip_x = (size_x < 0.0 : F32)
  +flip_y = (size_y < 0.0 : F32)
  +right = billboard.flip(flip_x, M.Vector3.scale(right0, size_x))
  +up = billboard.flip(flip_y, M.Vector3.scale(up0, size_y))
  +x0 = Bool.pick(F32, flip_x, (sx - size_x : F32), sx)
  +w = Bool.pick(F32, flip_x, F32.neg(sw), sw)
  +y0 = Bool.pick(F32, flip_y, (sy - size_y : F32), sy)
  +h = Bool.pick(F32, flip_y, F32.neg(sh), sh)
  +ax = Bool.pick(F32, flip_x, (ox * F32.neg(1.0) : F32), ox)
  +ay = Bool.pick(F32, flip_y, (oy * F32.neg(1.0) : F32), oy)
  +turn = F32.is_ne(rotation, 0.0)
  +angle = (rotation * S.deg2rad() : F32)
  +forward = M.Vector3.cross_product(right, up)
  +origin = M.Vector3.add(M.Vector3.scale(M.Vector3.normalize(right), ax), M.Vector3.scale(M.Vector3.normalize(up), ay))
  +zero = vec.zero()
  S.Plan.only(Bool.not(turn) || S.trig.ok(gnu, (angle / 2.0 : F32)),
    billboard.stream(kind, tint, (x0 / tw : F32), ((x0 + w : F32) / tw : F32), (y0 / th : F32), ((y0 + h : F32) / th : F32),
      billboard.point(zero, origin, turn, gnu, forward, angle, position), billboard.point(right, origin, turn, gnu, forward, angle, position),
      billboard.point(M.Vector3.add(up, right), origin, turn, gnu, forward, angle, position), billboard.point(up, origin, turn, gnu, forward, angle, position)))
