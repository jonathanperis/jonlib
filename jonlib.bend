# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Image/color algorithms adapted from raylib 6.0 rtextures.c; math from raymath.h.
# Collision queries adapted from the same release's rshapes.c.
# 3D collision queries adapted from rmodels.c.
# Altered Bend implementations; see THIRD_PARTY_NOTICES.md and LICENSES/raylib.txt.
import Base
import ./src/resample.bend as Resample
import ./src/qoi.bend as Qoi
import ./src/gradients.bend as Gradients
import ./src/trig.bend as Trig
import ./src/rotation.bend as Rotation
import ./src/fused.bend as Fused

type Vector2 is Data:
  Vector2{x: F32, y: F32}

type Vector3 is Data:
  Vector3{x: F32, y: F32, z: F32}

type Vector4 is Data:
  Vector4{x: F32, y: F32, z: F32, w: F32}

type BoundingBox is Data:
  BoundingBox{min: Vector3, max: Vector3}

type Matrix is Data:
  Matrix{m0: F32, m4: F32, m8: F32, m12: F32,
    m1: F32, m5: F32, m9: F32, m13: F32,
    m2: F32, m6: F32, m10: F32, m14: F32,
    m3: F32, m7: F32, m11: F32, m15: F32}

type Rectangle is Data:
  Rectangle{x: F32, y: F32, width: F32, height: F32}

type Gradient.Reference is Data:
  AccurateGradient{}
  GnuGradient{}

type Collision.Arithmetic is Data:
  UncontractedCollision{}
  FusedCollision{}

def Collision.multiply_add(arithmetic: Collision.Arithmetic, a: F32, b: F32, c: F32) -> F32:
  match arithmetic:
    case UncontractedCollision{}: (a * b + c : F32)
    case FusedCollision{}: Fused.multiply_add(a, b, c)

def Gradient.gnu(reference: Gradient.Reference) -> Bool:
  match reference:
    case AccurateGradient{}: False{}
    case GnuGradient{}: True{}

def Math.clamp(+value: F32, +lower: F32, +upper: F32) -> F32:
  +first = Bool.pick(F32, (value < lower : F32), lower, value)
  Bool.pick(F32, (first > upper : F32), upper, first)

def Math.lerp(+start: F32, end: F32, amount: F32) -> F32:
  (start + amount * (end - start) : F32)

def Math.normalize(value: F32, +start: F32, end: F32) -> F32:
  ((value - start) / (end - start) : F32)

def Math.remap(value: F32, +input_start: F32, input_end: F32, +output_start: F32, output_end: F32) -> F32:
  ((value - input_start) / (input_end - input_start) * (output_end - output_start) + output_start : F32)

def Math.wrap(+value: F32, +lower: F32, +upper: F32) -> F32:
  (value - (upper - lower) * F32.floor(((value - lower) / (upper - lower) : F32)) : F32)

def Math.float_equals(+left: F32, +right: F32) -> Bool:
  (F32.abs((left - right : F32)) <= 0.000001 * F32.max(1.0, F32.max(F32.abs(left), F32.abs(right))) : F32)

def Vector2.zero() -> Vector2:
  Vector2{0.0, 0.0}

def Vector2.one() -> Vector2:
  Vector2{1.0, 1.0}

def Vector2.add(left: Vector2, right: Vector2) -> Vector2:
  Vector2{x, y} = left
  Vector2{u, v} = right
  Vector2{(x + u : F32), (y + v : F32)}

def Vector2.add_value(vector: Vector2, +value: F32) -> Vector2:
  Vector2{x, y} = vector
  Vector2{(x + value : F32), (y + value : F32)}

def Vector2.subtract(left: Vector2, right: Vector2) -> Vector2:
  Vector2{x, y} = left
  Vector2{u, v} = right
  Vector2{(x - u : F32), (y - v : F32)}

def Vector2.subtract_value(vector: Vector2, +value: F32) -> Vector2:
  Vector2{x, y} = vector
  Vector2{(x - value : F32), (y - value : F32)}

def Vector2.scale(vector: Vector2, +value: F32) -> Vector2:
  Vector2{x, y} = vector
  Vector2{(x * value : F32), (y * value : F32)}

def Vector2.multiply(left: Vector2, right: Vector2) -> Vector2:
  Vector2{x, y} = left
  Vector2{u, v} = right
  Vector2{(x * u : F32), (y * v : F32)}

def Vector2.negate(vector: Vector2) -> Vector2:
  Vector2{x, y} = vector
  Vector2{F32.neg(x), F32.neg(y)}

def Vector2.divide(left: Vector2, right: Vector2) -> Vector2:
  Vector2{x, y} = left
  Vector2{u, v} = right
  Vector2{(x / u : F32), (y / v : F32)}

def Vector2.invert(vector: Vector2) -> Vector2:
  Vector2{x, y} = vector
  Vector2{(1.0 / x : F32), (1.0 / y : F32)}

def Vector2.length_sqr(vector: Vector2) -> F32:
  Vector2{+x, +y} = vector
  (x * x + y * y : F32)

def Vector2.length(vector: Vector2) -> F32:
  F32.sqrt(Vector2.length_sqr(vector))

def Vector2.normalized(nonzero: Bool, x: F32, y: F32, length: F32) -> Vector2:
  match nonzero:
    case False{}: Vector2.zero()
    case True{}:
      +inverse = (1.0 / length : F32)
      Vector2{(x * inverse : F32), (y * inverse : F32)}

def Vector2.normalize(vector: Vector2) -> Vector2:
  Vector2{+x, +y} = vector
  +length = F32.sqrt((x * x + y * y : F32))
  Vector2.normalized((length > 0.0 : F32), x, y, length)

def Vector2.distance_sqr(left: Vector2, right: Vector2) -> F32:
  Vector2.length_sqr(Vector2.subtract(left, right))

def Vector2.distance(left: Vector2, right: Vector2) -> F32:
  F32.sqrt(Vector2.distance_sqr(left, right))

def Vector2.move.route(snap: Bool, x: F32, y: F32, dx: F32, dy: F32, square: F32, +distance: F32, target: Vector2) -> Vector2:
  match snap:
    case True{}: target
    case False{}:
      +length = F32.sqrt(square)
      Vector2{(x + dx / length * distance : F32), (y + dy / length * distance : F32)}

def Vector2.move_towards(vector: Vector2, target: Vector2, +distance: F32) -> Vector2:
  Vector2{+x, +y} = vector
  Vector2{+tx, +ty} = target
  +dx = (tx - x : F32)
  +dy = (ty - y : F32)
  +square = (dx * dx + dy * dy : F32)
  Vector2.move.route(F32.is_eq(square, 0.0) || ((distance >= 0.0) && (square <= distance * distance) : F32),
    x, y, dx, dy, square, distance, Vector2{tx, ty})

def Vector2.dot_product(left: Vector2, right: Vector2) -> F32:
  Vector2{x, y} = left
  Vector2{u, v} = right
  (x * u + y * v : F32)

def Vector2.cross_product(left: Vector2, right: Vector2) -> F32:
  Vector2{x, y} = left
  Vector2{u, v} = right
  (x * v - y * u : F32)

def Vector2.lerp(left: Vector2, right: Vector2, +amount: F32) -> Vector2:
  Vector2{x, y} = left
  Vector2{u, v} = right
  Vector2{Math.lerp(x, u, amount), Math.lerp(y, v, amount)}

def Vector2.reflect(vector: Vector2, normal: Vector2) -> Vector2:
  Vector2{+x, +y} = vector
  Vector2{+u, +v} = normal
  +dot = (x * u + y * v : F32)
  Vector2{(x - (2.0 * u) * dot : F32), (y - (2.0 * v) * dot : F32)}

def Vector2.equals(left: Vector2, right: Vector2) -> Bool:
  Vector2{x, y} = left
  Vector2{u, v} = right
  Math.float_equals(x, u) && Math.float_equals(y, v)

def Vector2.clamp.minimum(gnu: Bool, +left: F32, +right: F32) -> F32:
  zero = Bool.pick(F32, U32.is_ne(((F32.bits(left) .|. F32.bits(right)) .&. 2147483648 : U32), 0), F32.neg(0.0), 0.0)
  Bool.pick(F32, F32.is_eq(left, 0.0) && F32.is_eq(right, 0.0), Bool.pick(F32, gnu, left, zero), Bool.pick(F32, (left < right : F32), left, right))

def Vector2.clamp.maximum(gnu: Bool, +left: F32, +right: F32) -> F32:
  zero = Bool.pick(F32, U32.is_ne(((F32.bits(left) .&. F32.bits(right)) .&. 2147483648 : U32), 0), F32.neg(0.0), 0.0)
  Bool.pick(F32, F32.is_eq(left, 0.0) && F32.is_eq(right, 0.0), Bool.pick(F32, gnu, left, zero), Bool.pick(F32, (left > right : F32), left, right))

def Vector2.clamp_for(reference: Gradient.Reference, vector: Vector2, lower: Vector2, upper: Vector2) -> Vector2:
  Vector2{x, y} = vector
  Vector2{lx, ly} = lower
  Vector2{ux, uy} = upper
  +gnu = Gradient.gnu(reference)
  Vector2{Vector2.clamp.minimum(gnu, ux, Vector2.clamp.maximum(gnu, lx, x)), Vector2.clamp.minimum(gnu, uy, Vector2.clamp.maximum(gnu, ly, y))}

def Vector2.clamp(vector: Vector2, lower: Vector2, upper: Vector2) -> Vector2:
  Vector2.clamp_for(AccurateGradient{}, vector, lower, upper)

def Vector2.min_for(reference: Gradient.Reference, left: Vector2, right: Vector2) -> Vector2:
  Vector2{x, y} = left
  Vector2{u, v} = right
  +gnu = Gradient.gnu(reference)
  Vector2{Vector2.clamp.minimum(gnu, x, u), Vector2.clamp.minimum(gnu, y, v)}

def Vector2.max_for(reference: Gradient.Reference, left: Vector2, right: Vector2) -> Vector2:
  Vector2{x, y} = left
  Vector2{u, v} = right
  +gnu = Gradient.gnu(reference)
  Vector2{Vector2.clamp.maximum(gnu, x, u), Vector2.clamp.maximum(gnu, y, v)}

def Vector2.min(left: Vector2, right: Vector2) -> Vector2:
  Vector2.min_for(AccurateGradient{}, left, right)

def Vector2.max(left: Vector2, right: Vector2) -> Vector2:
  Vector2.max_for(AccurateGradient{}, left, right)

def Vector2.clamp.magnitude(nonzero: Bool, +x: F32, +y: F32, square: F32, +lower: F32, +upper: F32) -> Vector2:
  match nonzero:
    case False{}: Vector2{x, y}
    case True{}:
      +length = F32.sqrt(square)
      +scale = Bool.pick(F32, (length < lower : F32), (lower / length : F32),
        Bool.pick(F32, (length > upper : F32), (upper / length : F32), 1.0))
      Vector2{(x * scale : F32), (y * scale : F32)}

def Vector2.clamp_value(vector: Vector2, lower: F32, upper: F32) -> Vector2:
  Vector2{+x, +y} = vector
  +square = (x * x + y * y : F32)
  Vector2.clamp.magnitude((square > 0.0 : F32), x, y, square, lower, upper)

def Vector2.refraction(valid: Bool, x: F32, y: F32, +nx: F32, +ny: F32, +ratio: F32, dot: F32, determinant: F32) -> Vector2:
  match valid:
    case False{}: Vector2.zero()
    case True{}:
      +gain = (ratio * dot + F32.sqrt(determinant) : F32)
      Vector2{(ratio * x - gain * nx : F32), (ratio * y - gain * ny : F32)}

def Vector2.refract(vector: Vector2, normal: Vector2, +ratio: F32) -> Vector2:
  Vector2{+x, +y} = vector
  Vector2{+nx, +ny} = normal
  +dot = (x * nx + y * ny : F32)
  +determinant = (1.0 - ratio * ratio * (1.0 - dot * dot) : F32)
  Vector2.refraction((determinant >= 0.0 : F32), x, y, nx, ny, ratio, dot, determinant)

def Vector2.rotation(vector: Vector2, values: F32 & F32) -> Vector2:
  Vector2{+x, +y} = vector
  (+cosine, +sine) = values
  Vector2{(x * cosine - y * sine : F32), (x * sine + y * cosine : F32)}

def Vector2.rotate_for(reference: Gradient.Reference, vector: Vector2, angle: F32) -> Vector2:
  Vector2.rotation(vector, Trig.sincos_for(Gradient.gnu(reference), angle))

def Vector2.rotate(vector: Vector2, angle: F32) -> Vector2:
  Vector2.rotate_for(AccurateGradient{}, vector, angle)

def Matrix.identity() -> Matrix:
  Matrix{1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0}

def Matrix.transpose(matrix: Matrix) -> Matrix:
  Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = matrix
  Matrix{m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15}

def Matrix.to_float_v(matrix: Matrix) -> +List<F32>:
  Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = matrix
  [m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15]

def Matrix.add(left: Matrix, right: Matrix) -> Matrix:
  Matrix{a0, a4, a8, a12, a1, a5, a9, a13, a2, a6, a10, a14, a3, a7, a11, a15} = left
  Matrix{b0, b4, b8, b12, b1, b5, b9, b13, b2, b6, b10, b14, b3, b7, b11, b15} = right
  Matrix{(a0 + b0 : F32), (a4 + b4 : F32), (a8 + b8 : F32), (a12 + b12 : F32),
    (a1 + b1 : F32), (a5 + b5 : F32), (a9 + b9 : F32), (a13 + b13 : F32),
    (a2 + b2 : F32), (a6 + b6 : F32), (a10 + b10 : F32), (a14 + b14 : F32),
    (a3 + b3 : F32), (a7 + b7 : F32), (a11 + b11 : F32), (a15 + b15 : F32)}

def Matrix.subtract(left: Matrix, right: Matrix) -> Matrix:
  Matrix{a0, a4, a8, a12, a1, a5, a9, a13, a2, a6, a10, a14, a3, a7, a11, a15} = left
  Matrix{b0, b4, b8, b12, b1, b5, b9, b13, b2, b6, b10, b14, b3, b7, b11, b15} = right
  Matrix{(a0 - b0 : F32), (a4 - b4 : F32), (a8 - b8 : F32), (a12 - b12 : F32),
    (a1 - b1 : F32), (a5 - b5 : F32), (a9 - b9 : F32), (a13 - b13 : F32),
    (a2 - b2 : F32), (a6 - b6 : F32), (a10 - b10 : F32), (a14 - b14 : F32),
    (a3 - b3 : F32), (a7 - b7 : F32), (a11 - b11 : F32), (a15 - b15 : F32)}

def Matrix.product.cell(a: F32, b: F32, c: F32, d: F32, e: F32, f: F32, g: F32, h: F32) -> F32:
  (a * e + b * f + c * g + d * h : F32)

def Matrix.multiply(left: Matrix, right: Matrix) -> Matrix:
  Matrix{+a0, +a4, +a8, +a12, +a1, +a5, +a9, +a13, +a2, +a6, +a10, +a14, +a3, +a7, +a11, +a15} = left
  Matrix{+b0, +b4, +b8, +b12, +b1, +b5, +b9, +b13, +b2, +b6, +b10, +b14, +b3, +b7, +b11, +b15} = right
  Matrix{
    Matrix.product.cell(a0, a1, a2, a3, b0, b4, b8, b12),
    Matrix.product.cell(a4, a5, a6, a7, b0, b4, b8, b12),
    Matrix.product.cell(a8, a9, a10, a11, b0, b4, b8, b12),
    Matrix.product.cell(a12, a13, a14, a15, b0, b4, b8, b12),
    Matrix.product.cell(a0, a1, a2, a3, b1, b5, b9, b13),
    Matrix.product.cell(a4, a5, a6, a7, b1, b5, b9, b13),
    Matrix.product.cell(a8, a9, a10, a11, b1, b5, b9, b13),
    Matrix.product.cell(a12, a13, a14, a15, b1, b5, b9, b13),
    Matrix.product.cell(a0, a1, a2, a3, b2, b6, b10, b14),
    Matrix.product.cell(a4, a5, a6, a7, b2, b6, b10, b14),
    Matrix.product.cell(a8, a9, a10, a11, b2, b6, b10, b14),
    Matrix.product.cell(a12, a13, a14, a15, b2, b6, b10, b14),
    Matrix.product.cell(a0, a1, a2, a3, b3, b7, b11, b15),
    Matrix.product.cell(a4, a5, a6, a7, b3, b7, b11, b15),
    Matrix.product.cell(a8, a9, a10, a11, b3, b7, b11, b15),
    Matrix.product.cell(a12, a13, a14, a15, b3, b7, b11, b15)}

def Matrix.trace(matrix: Matrix) -> F32:
  Matrix{m0, _, _, _, _, m5, _, _, _, _, m10, _, _, _, _, m15} = matrix
  (m0 + m5 + m10 + m15 : F32)

def Matrix.determinant(matrix: Matrix) -> F32:
  Matrix{m0, m4, m8, m12, +m1, +m5, +m9, +m13, +m2, +m6, +m10, +m14, +m3, +m7, +m11, +m15} = matrix
  (m0 * (m5 * (m10 * m15 - m11 * m14) - m9 * (m6 * m15 - m7 * m14) + m13 * (m6 * m11 - m7 * m10))
    - m4 * (m1 * (m10 * m15 - m11 * m14) - m9 * (m2 * m15 - m3 * m14) + m13 * (m2 * m11 - m3 * m10))
    + m8 * (m1 * (m6 * m15 - m7 * m14) - m5 * (m2 * m15 - m3 * m14) + m13 * (m2 * m7 - m3 * m6))
    - m12 * (m1 * (m6 * m11 - m7 * m10) - m5 * (m2 * m11 - m3 * m10) + m9 * (m2 * m7 - m3 * m6)) : F32)

def Matrix.invert(matrix: Matrix) -> Matrix:
  Matrix{+a00, +a10, +a20, +a30, +a01, +a11, +a21, +a31, +a02, +a12, +a22, +a32, +a03, +a13, +a23, +a33} = matrix
  +b00 = (a00 * a11 - a01 * a10 : F32)
  +b01 = (a00 * a12 - a02 * a10 : F32)
  +b02 = (a00 * a13 - a03 * a10 : F32)
  +b03 = (a01 * a12 - a02 * a11 : F32)
  +b04 = (a01 * a13 - a03 * a11 : F32)
  +b05 = (a02 * a13 - a03 * a12 : F32)
  +b06 = (a20 * a31 - a21 * a30 : F32)
  +b07 = (a20 * a32 - a22 * a30 : F32)
  +b08 = (a20 * a33 - a23 * a30 : F32)
  +b09 = (a21 * a32 - a22 * a31 : F32)
  +b10 = (a21 * a33 - a23 * a31 : F32)
  +b11 = (a22 * a33 - a23 * a32 : F32)
  +inverse = (1.0 / (b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06) : F32)
  Matrix{
    ((a11 * b11 - a12 * b10 + a13 * b09) * inverse : F32),
    ((F32.neg(a10) * b11 + a12 * b08 - a13 * b07) * inverse : F32),
    ((a10 * b10 - a11 * b08 + a13 * b06) * inverse : F32),
    ((F32.neg(a10) * b09 + a11 * b07 - a12 * b06) * inverse : F32),
    ((F32.neg(a01) * b11 + a02 * b10 - a03 * b09) * inverse : F32),
    ((a00 * b11 - a02 * b08 + a03 * b07) * inverse : F32),
    ((F32.neg(a00) * b10 + a01 * b08 - a03 * b06) * inverse : F32),
    ((a00 * b09 - a01 * b07 + a02 * b06) * inverse : F32),
    ((a31 * b05 - a32 * b04 + a33 * b03) * inverse : F32),
    ((F32.neg(a30) * b05 + a32 * b02 - a33 * b01) * inverse : F32),
    ((a30 * b04 - a31 * b02 + a33 * b00) * inverse : F32),
    ((F32.neg(a30) * b03 + a31 * b01 - a32 * b00) * inverse : F32),
    ((F32.neg(a21) * b05 + a22 * b04 - a23 * b03) * inverse : F32),
    ((a20 * b05 - a22 * b02 + a23 * b01) * inverse : F32),
    ((F32.neg(a20) * b04 + a21 * b02 - a23 * b00) * inverse : F32),
    ((a20 * b03 - a21 * b01 + a22 * b00) * inverse : F32)}

def Matrix.translate(x: F32, y: F32, z: F32) -> Matrix:
  Matrix{1.0, 0.0, 0.0, x, 0.0, 1.0, 0.0, y, 0.0, 0.0, 1.0, z, 0.0, 0.0, 0.0, 1.0}

def Matrix.scale(x: F32, y: F32, z: F32) -> Matrix:
  Matrix{x, 0.0, 0.0, 0.0, 0.0, y, 0.0, 0.0, 0.0, 0.0, z, 0.0, 0.0, 0.0, 0.0, 1.0}

def Matrix.multiply_value(matrix: Matrix, +value: F32) -> Matrix:
  Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = matrix
  Matrix{(m0 * value : F32), (m4 * value : F32), (m8 * value : F32), (m12 * value : F32),
    (m1 * value : F32), (m5 * value : F32), (m9 * value : F32), (m13 * value : F32),
    (m2 * value : F32), (m6 * value : F32), (m10 * value : F32), (m14 * value : F32),
    (m3 * value : F32), (m7 * value : F32), (m11 * value : F32), (m15 * value : F32)}

def Vector2.transform(vector: Vector2, matrix: Matrix) -> Vector2:
  Vector2{+x, +y} = vector
  Matrix{m0, m4, m8, m12, m1, m5, m9, m13, _, _, _, _, _, _, _, _} = matrix
  Vector2{(m0 * x + m4 * y + m8 * 0.0 + m12 : F32), (m1 * x + m5 * y + m9 * 0.0 + m13 : F32)}

def Vector3.zero() -> Vector3:
  Vector3{0.0, 0.0, 0.0}

def Vector3.one() -> Vector3:
  Vector3{1.0, 1.0, 1.0}

def Vector3.to_float_v(vector: Vector3) -> +List<F32>:
  Vector3{x, y, z} = vector
  [x, y, z]

def Vector3.add(left: Vector3, right: Vector3) -> Vector3:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  Vector3{(x + u : F32), (y + v : F32), (z + w : F32)}

def Vector3.subtract(left: Vector3, right: Vector3) -> Vector3:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  Vector3{(x - u : F32), (y - v : F32), (z - w : F32)}

def Vector3.scale(vector: Vector3, +scale: F32) -> Vector3:
  Vector3{x, y, z} = vector
  Vector3{(x * scale : F32), (y * scale : F32), (z * scale : F32)}

def Vector3.multiply(left: Vector3, right: Vector3) -> Vector3:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  Vector3{(x * u : F32), (y * v : F32), (z * w : F32)}

def Vector3.add_value(vector: Vector3, +value: F32) -> Vector3:
  Vector3{x, y, z} = vector
  Vector3{(x + value : F32), (y + value : F32), (z + value : F32)}

def Vector3.subtract_value(vector: Vector3, +value: F32) -> Vector3:
  Vector3{x, y, z} = vector
  Vector3{(x - value : F32), (y - value : F32), (z - value : F32)}

def Vector3.negate(vector: Vector3) -> Vector3:
  Vector3{x, y, z} = vector
  Vector3{F32.neg(x), F32.neg(y), F32.neg(z)}

def Vector3.divide(left: Vector3, right: Vector3) -> Vector3:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  Vector3{(x / u : F32), (y / v : F32), (z / w : F32)}

def Vector3.cross_product(left: Vector3, right: Vector3) -> Vector3:
  Vector3{+x, +y, +z} = left
  Vector3{+u, +v, +w} = right
  Vector3{(y * w - z * v : F32), (z * u - x * w : F32), (x * v - y * u : F32)}

def Vector3.dot_product(left: Vector3, right: Vector3) -> F32:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  (x * u + y * v + z * w : F32)

def Vector3.distance_sqr(left: Vector3, right: Vector3) -> F32:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  +dx = (u - x : F32)
  +dy = (v - y : F32)
  +dz = (w - z : F32)
  (dx * dx + dy * dy + dz * dz : F32)

def Vector3.length_sqr(+vector: Vector3) -> F32:
  Vector3.dot_product(vector, vector)

def Vector3.length(vector: Vector3) -> F32:
  F32.sqrt(Vector3.length_sqr(vector))

def Vector3.distance(left: Vector3, right: Vector3) -> F32:
  F32.sqrt(Vector3.distance_sqr(left, right))

def Vector3.normalized(nonzero: Bool, vector: Vector3, length: F32) -> Vector3:
  match nonzero:
    case False{}: vector
    case True{}: Vector3.scale(vector, (1.0 / length : F32))

def Vector3.normalize(+vector: Vector3) -> Vector3:
  +length = Vector3.length(vector)
  Vector3.normalized(F32.is_ne(length, 0.0), vector, length)

def Vector3.project(vector: Vector3, +onto: Vector3) -> Vector3:
  factor = (Vector3.dot_product(vector, onto) / Vector3.dot_product(onto, onto) : F32)
  Vector3.scale(onto, factor)

def Vector3.reject(+vector: Vector3, onto: Vector3) -> Vector3:
  Vector3.subtract(vector, Vector3.project(vector, onto))

def Vector3.perpendicular(vector: Vector3) -> Vector3:
  Vector3{+x, +y, +z} = vector
  +choose_y = (F32.abs(y) < F32.abs(x) : F32)
  minimum = Bool.pick(F32, choose_y, F32.abs(y), F32.abs(x))
  axis = Bool.pick(Vector3, (F32.abs(z) < minimum : F32), Vector3{0.0, 0.0, 1.0},
    Bool.pick(Vector3, choose_y, Vector3{0.0, 1.0, 0.0}, Vector3{1.0, 0.0, 0.0}))
  Vector3.cross_product(Vector3{x, y, z}, axis)

def Vector3.lerp(left: Vector3, right: Vector3, +amount: F32) -> Vector3:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  Vector3{Math.lerp(x, u, amount), Math.lerp(y, v, amount), Math.lerp(z, w, amount)}

def Vector3.reflect(+vector: Vector3, +normal: Vector3) -> Vector3:
  dot = Vector3.dot_product(vector, normal)
  Vector3.subtract(vector, Vector3.scale(Vector3.scale(normal, 2.0), dot))

def Vector3.invert(vector: Vector3) -> Vector3:
  Vector3{x, y, z} = vector
  Vector3{(1.0 / x : F32), (1.0 / y : F32), (1.0 / z : F32)}

def Vector3.equals(left: Vector3, right: Vector3) -> Bool:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  Math.float_equals(x, u) && Math.float_equals(y, v) && Math.float_equals(z, w)

def Vector3.move.route(snap: Bool, vector: Vector3, target: Vector3, delta: Vector3, square: F32, +distance: F32) -> Vector3:
  match snap:
    case True{}: target
    case False{}:
      Vector3{x, y, z} = vector
      Vector3{dx, dy, dz} = delta
      +length = F32.sqrt(square)
      Vector3{(x + dx / length * distance : F32), (y + dy / length * distance : F32), (z + dz / length * distance : F32)}

def Vector3.move_towards(+vector: Vector3, +target: Vector3, +distance: F32) -> Vector3:
  +delta = Vector3.subtract(target, vector)
  +square = Vector3.dot_product(delta, delta)
  Vector3.move.route(F32.is_eq(square, 0.0) || (((distance >= 0.0) && (square <= distance * distance)) : F32), vector, target, delta, square, distance)

def Vector3.clamp_for(reference: Gradient.Reference, vector: Vector3, lower: Vector3, upper: Vector3) -> Vector3:
  Vector3{x, y, z} = vector
  Vector3{lx, ly, lz} = lower
  Vector3{ux, uy, uz} = upper
  +gnu = Gradient.gnu(reference)
  Vector3{Vector2.clamp.minimum(gnu, ux, Vector2.clamp.maximum(gnu, lx, x)),
    Vector2.clamp.minimum(gnu, uy, Vector2.clamp.maximum(gnu, ly, y)),
    Vector2.clamp.minimum(gnu, uz, Vector2.clamp.maximum(gnu, lz, z))}

def Vector3.clamp(vector: Vector3, lower: Vector3, upper: Vector3) -> Vector3:
  Vector3.clamp_for(AccurateGradient{}, vector, lower, upper)

def Vector3.clamp.magnitude(nonzero: Bool, vector: Vector3, square: F32, +lower: F32, +upper: F32) -> Vector3:
  match nonzero:
    case False{}: vector
    case True{}:
      +length = F32.sqrt(square)
      scale = Bool.pick(F32, (length < lower : F32), (lower / length : F32),
        Bool.pick(F32, (length > upper : F32), (upper / length : F32), 1.0))
      Vector3.scale(vector, scale)

def Vector3.clamp_value(+vector: Vector3, lower: F32, upper: F32) -> Vector3:
  +square = Vector3.length_sqr(vector)
  Vector3.clamp.magnitude((square > 0.0 : F32), vector, square, lower, upper)

def Vector3.refraction(valid: Bool, vector: Vector3, normal: Vector3, +ratio: F32, dot: F32, determinant: F32) -> Vector3:
  match valid:
    case False{}: Vector3.zero()
    case True{}:
      gain = (ratio * dot + F32.sqrt(determinant) : F32)
      Vector3.subtract(Vector3.scale(vector, ratio), Vector3.scale(normal, gain))

def Vector3.refract(+vector: Vector3, +normal: Vector3, +ratio: F32) -> Vector3:
  +dot = Vector3.dot_product(vector, normal)
  +determinant = (1.0 - ratio * ratio * (1.0 - dot * dot) : F32)
  Vector3.refraction((determinant >= 0.0 : F32), vector, normal, ratio, dot, determinant)

def Vector3.min_for(reference: Gradient.Reference, left: Vector3, right: Vector3) -> Vector3:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  +gnu = Gradient.gnu(reference)
  Vector3{Vector2.clamp.minimum(gnu, x, u), Vector2.clamp.minimum(gnu, y, v), Vector2.clamp.minimum(gnu, z, w)}

def Vector3.max_for(reference: Gradient.Reference, left: Vector3, right: Vector3) -> Vector3:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  +gnu = Gradient.gnu(reference)
  Vector3{Vector2.clamp.maximum(gnu, x, u), Vector2.clamp.maximum(gnu, y, v), Vector2.clamp.maximum(gnu, z, w)}

def Vector3.min(left: Vector3, right: Vector3) -> Vector3:
  Vector3.min_for(AccurateGradient{}, left, right)

def Vector3.max(left: Vector3, right: Vector3) -> Vector3:
  Vector3.max_for(AccurateGradient{}, left, right)

def Vector3.barycenter(point: Vector3, +a: Vector3, b: Vector3, c: Vector3) -> Vector3:
  +v0 = Vector3.subtract(b, a)
  +v1 = Vector3.subtract(c, a)
  +v2 = Vector3.subtract(point, a)
  +d00 = Vector3.dot_product(v0, v0)
  +d01 = Vector3.dot_product(v0, v1)
  +d11 = Vector3.dot_product(v1, v1)
  +d20 = Vector3.dot_product(v2, v0)
  +d21 = Vector3.dot_product(v2, v1)
  +denominator = (d00 * d11 - d01 * d01 : F32)
  +y = ((d11 * d20 - d01 * d21) / denominator : F32)
  +z = ((d00 * d21 - d01 * d20) / denominator : F32)
  Vector3{(1.0 - (z + y) : F32), y, z}

def Vector3.cubic_hermite(first: Vector3, first_tangent: Vector3, second: Vector3, second_tangent: Vector3, +amount: F32) -> Vector3:
  +square = (amount * amount : F32)
  +cube = (amount * amount * amount : F32)
  a = Vector3.scale(first, (2.0 * cube - 3.0 * square + 1.0 : F32))
  b = Vector3.scale(first_tangent, (cube - 2.0 * square + amount : F32))
  c = Vector3.scale(second, (F32.neg(2.0) * cube + 3.0 * square : F32))
  d = Vector3.scale(second_tangent, (cube - square : F32))
  Vector3.add(Vector3.add(Vector3.add(a, b), c), d)

def Vector3.ortho_normalize(first: Vector3, second: Vector3) -> Vector3 & Vector3:
  +normalized = Vector3.normalize(first)
  perpendicular = Vector3.normalize(Vector3.cross_product(normalized, second))
  (normalized, Vector3.cross_product(perpendicular, normalized))

def Vector3.transform(vector: Vector3, matrix: Matrix) -> Vector3:
  Vector3{+x, +y, +z} = vector
  Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, _, _, _, _} = matrix
  Vector3{(m0 * x + m4 * y + m8 * z + m12 : F32),
    (m1 * x + m5 * y + m9 * z + m13 : F32), (m2 * x + m6 * y + m10 * z + m14 : F32)}

def Matrix.view.basis(eye: Vector3, right: Vector3, vertical: Vector3, forward: Vector3) -> Matrix:
  Vector3{+ex, +ey, +ez} = eye
  Vector3{+xx, +xy, +xz} = right
  Vector3{+yx, +yy, +yz} = vertical
  Vector3{+zx, +zy, +zz} = forward
  Matrix{xx, xy, xz, F32.neg((xx * ex + xy * ey + xz * ez : F32)),
    yx, yy, yz, F32.neg((yx * ex + yy * ey + yz * ez : F32)),
    zx, zy, zz, F32.neg((zx * ex + zy * ey + zz * ez : F32)), 0.0, 0.0, 0.0, 1.0}

def Matrix.look_at(+eye: Vector3, target: Vector3, up: Vector3) -> Matrix:
  +forward = Vector3.normalize(Vector3.subtract(eye, target))
  +right = Vector3.normalize(Vector3.cross_product(up, forward))
  vertical = Vector3.cross_product(forward, right)
  Matrix.view.basis(eye, right, vertical, forward)

def Matrix.rotation.x(values: F32 & F32) -> Matrix:
  (+cosine, +sine) = values
  Matrix{1.0, 0.0, 0.0, 0.0, 0.0, cosine, F32.neg(sine), 0.0,
    0.0, sine, cosine, 0.0, 0.0, 0.0, 0.0, 1.0}

def Matrix.rotate_x_for(reference: Gradient.Reference, angle: F32) -> Matrix:
  Matrix.rotation.x(Trig.sincos_for(Gradient.gnu(reference), angle))

def Matrix.rotate_x(angle: F32) -> Matrix:
  Matrix.rotate_x_for(AccurateGradient{}, angle)

def Matrix.rotation.y(values: F32 & F32) -> Matrix:
  (+cosine, +sine) = values
  Matrix{cosine, 0.0, sine, 0.0, 0.0, 1.0, 0.0, 0.0,
    F32.neg(sine), 0.0, cosine, 0.0, 0.0, 0.0, 0.0, 1.0}

def Matrix.rotate_y_for(reference: Gradient.Reference, angle: F32) -> Matrix:
  Matrix.rotation.y(Trig.sincos_for(Gradient.gnu(reference), angle))

def Matrix.rotate_y(angle: F32) -> Matrix:
  Matrix.rotate_y_for(AccurateGradient{}, angle)

def Matrix.rotation.z(values: F32 & F32) -> Matrix:
  (+cosine, +sine) = values
  Matrix{cosine, F32.neg(sine), 0.0, 0.0, sine, cosine, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0}

def Matrix.rotate_z_for(reference: Gradient.Reference, angle: F32) -> Matrix:
  Matrix.rotation.z(Trig.sincos_for(Gradient.gnu(reference), angle))

def Matrix.rotate_z(angle: F32) -> Matrix:
  Matrix.rotate_z_for(AccurateGradient{}, angle)

def Matrix.rotation.xyz(x_values: F32 & F32, y_values: F32 & F32, z_values: F32 & F32) -> Matrix:
  (+cx, +sx) = x_values
  (+cy, +sy) = y_values
  (+cz, +sz) = z_values
  Matrix{(cz * cy : F32), (sz * cy : F32), F32.neg(sy), 0.0,
    (cz * sy * sx - sz * cx : F32), (sz * sy * sx + cz * cx : F32), (cy * sx : F32), 0.0,
    (cz * sy * cx + sz * sx : F32), (sz * sy * cx - cz * sx : F32), (cy * cx : F32), 0.0,
    0.0, 0.0, 0.0, 1.0}

def Matrix.rotate_xyz_for(reference: Gradient.Reference, angles: Vector3) -> Matrix:
  Vector3{x, y, z} = angles
  +gnu = Gradient.gnu(reference)
  Matrix.rotation.xyz(Trig.sincos_for(gnu, F32.neg(x)), Trig.sincos_for(gnu, F32.neg(y)), Trig.sincos_for(gnu, F32.neg(z)))

def Matrix.rotate_xyz(angles: Vector3) -> Matrix:
  Matrix.rotate_xyz_for(AccurateGradient{}, angles)

def Matrix.rotation.zyx(x_values: F32 & F32, y_values: F32 & F32, z_values: F32 & F32) -> Matrix:
  (+cx, +sx) = x_values
  (+cy, +sy) = y_values
  (+cz, +sz) = z_values
  Matrix{(cz * cy : F32), (cz * sy * sx - cx * sz : F32), (sz * sx + cz * cx * sy : F32), 0.0,
    (cy * sz : F32), (cz * cx + sz * sy * sx : F32), (cx * sz * sy - cz * sx : F32), 0.0,
    F32.neg(sy), (cy * sx : F32), (cy * cx : F32), 0.0, 0.0, 0.0, 0.0, 1.0}

def Matrix.rotate_zyx_for(reference: Gradient.Reference, angles: Vector3) -> Matrix:
  Vector3{x, y, z} = angles
  +gnu = Gradient.gnu(reference)
  Matrix.rotation.zyx(Trig.sincos_for(gnu, x), Trig.sincos_for(gnu, y), Trig.sincos_for(gnu, z))

def Matrix.rotate_zyx(angles: Vector3) -> Matrix:
  Matrix.rotate_zyx_for(AccurateGradient{}, angles)

def Matrix.rotation.around(axis: Vector3, values: F32 & F32) -> Matrix:
  Vector3{+x, +y, +z} = axis
  (+cosine, +sine) = values
  +t = (1.0 - cosine : F32)
  Matrix{(x * x * t + cosine : F32), (x * y * t - z * sine : F32), (x * z * t + y * sine : F32), 0.0,
    (y * x * t + z * sine : F32), (y * y * t + cosine : F32), (y * z * t - x * sine : F32), 0.0,
    (z * x * t - y * sine : F32), (z * y * t + x * sine : F32), (z * z * t + cosine : F32), 0.0,
    0.0, 0.0, 0.0, 1.0}

def Matrix.rotation.normalized(required: Bool, axis: Vector3, square: F32) -> Vector3:
  match required:
    case False{}: axis
    case True{}: Vector3.scale(axis, (1.0 / F32.sqrt(square) : F32))

def Matrix.rotate_for(reference: Gradient.Reference, +axis: Vector3, angle: F32) -> Matrix:
  +square = Vector3.length_sqr(axis)
  normalized = Matrix.rotation.normalized(F32.is_ne(square, 0.0) && F32.is_ne(square, 1.0), axis, square)
  Matrix.rotation.around(normalized, Trig.sincos_for(Gradient.gnu(reference), angle))

def Matrix.rotate(axis: Vector3, angle: F32) -> Matrix:
  Matrix.rotate_for(AccurateGradient{}, axis, angle)

def Vector4.zero() -> Vector4:
  Vector4{0.0, 0.0, 0.0, 0.0}

def Vector4.one() -> Vector4:
  Vector4{1.0, 1.0, 1.0, 1.0}

def Vector4.add(left: Vector4, right: Vector4) -> Vector4:
  Vector4{x, y, z, w} = left
  Vector4{a, b, c, d} = right
  Vector4{(x + a : F32), (y + b : F32), (z + c : F32), (w + d : F32)}

def Vector4.subtract(left: Vector4, right: Vector4) -> Vector4:
  Vector4{x, y, z, w} = left
  Vector4{a, b, c, d} = right
  Vector4{(x - a : F32), (y - b : F32), (z - c : F32), (w - d : F32)}

def Vector4.scale(vector: Vector4, +factor: F32) -> Vector4:
  Vector4{x, y, z, w} = vector
  Vector4{(x * factor : F32), (y * factor : F32), (z * factor : F32), (w * factor : F32)}

def Vector4.multiply(left: Vector4, right: Vector4) -> Vector4:
  Vector4{x, y, z, w} = left
  Vector4{a, b, c, d} = right
  Vector4{(x * a : F32), (y * b : F32), (z * c : F32), (w * d : F32)}

def Vector4.add_value(vector: Vector4, +value: F32) -> Vector4:
  Vector4{x, y, z, w} = vector
  Vector4{(x + value : F32), (y + value : F32), (z + value : F32), (w + value : F32)}

def Vector4.subtract_value(vector: Vector4, +value: F32) -> Vector4:
  Vector4{x, y, z, w} = vector
  Vector4{(x - value : F32), (y - value : F32), (z - value : F32), (w - value : F32)}

def Vector4.negate(vector: Vector4) -> Vector4:
  Vector4{x, y, z, w} = vector
  Vector4{F32.neg(x), F32.neg(y), F32.neg(z), F32.neg(w)}

def Vector4.divide(left: Vector4, right: Vector4) -> Vector4:
  Vector4{x, y, z, w} = left
  Vector4{a, b, c, d} = right
  Vector4{(x / a : F32), (y / b : F32), (z / c : F32), (w / d : F32)}

def Vector4.invert(vector: Vector4) -> Vector4:
  Vector4{x, y, z, w} = vector
  Vector4{(1.0 / x : F32), (1.0 / y : F32), (1.0 / z : F32), (1.0 / w : F32)}

def Vector4.dot_product(left: Vector4, right: Vector4) -> F32:
  Vector4{x, y, z, w} = left
  Vector4{a, b, c, d} = right
  (x * a + y * b + z * c + w * d : F32)

def Vector4.length_sqr(+vector: Vector4) -> F32:
  Vector4.dot_product(vector, vector)

def Vector4.length(vector: Vector4) -> F32:
  F32.sqrt(Vector4.length_sqr(vector))

def Vector4.distance_sqr(left: Vector4, right: Vector4) -> F32:
  Vector4{a, b, c, d} = left
  Vector4{x, y, z, w} = right
  +dx = (a - x : F32)
  +dy = (b - y : F32)
  +dz = (c - z : F32)
  +dw = (d - w : F32)
  (dx * dx + dy * dy + dz * dz + dw * dw : F32)

def Vector4.distance(left: Vector4, right: Vector4) -> F32:
  F32.sqrt(Vector4.distance_sqr(left, right))

def Vector4.normalized(nonzero: Bool, vector: Vector4, length: F32) -> Vector4:
  match nonzero:
    case False{}: Vector4.zero()
    case True{}: Vector4.scale(vector, (1.0 / length : F32))

def Vector4.normalize(+vector: Vector4) -> Vector4:
  +length = Vector4.length(vector)
  Vector4.normalized((length > 0.0 : F32), vector, length)

def Vector4.min_for(reference: Gradient.Reference, left: Vector4, right: Vector4) -> Vector4:
  Vector4{x, y, z, w} = left
  Vector4{a, b, c, d} = right
  +gnu = Gradient.gnu(reference)
  Vector4{Vector2.clamp.minimum(gnu, x, a), Vector2.clamp.minimum(gnu, y, b),
    Vector2.clamp.minimum(gnu, z, c), Vector2.clamp.minimum(gnu, w, d)}

def Vector4.max_for(reference: Gradient.Reference, left: Vector4, right: Vector4) -> Vector4:
  Vector4{x, y, z, w} = left
  Vector4{a, b, c, d} = right
  +gnu = Gradient.gnu(reference)
  Vector4{Vector2.clamp.maximum(gnu, x, a), Vector2.clamp.maximum(gnu, y, b),
    Vector2.clamp.maximum(gnu, z, c), Vector2.clamp.maximum(gnu, w, d)}

def Vector4.min(left: Vector4, right: Vector4) -> Vector4:
  Vector4.min_for(AccurateGradient{}, left, right)

def Vector4.max(left: Vector4, right: Vector4) -> Vector4:
  Vector4.max_for(AccurateGradient{}, left, right)

def Vector4.lerp(left: Vector4, right: Vector4, +amount: F32) -> Vector4:
  Vector4{x, y, z, w} = left
  Vector4{a, b, c, d} = right
  Vector4{Math.lerp(x, a, amount), Math.lerp(y, b, amount), Math.lerp(z, c, amount), Math.lerp(w, d, amount)}

def Vector4.move.route(snap: Bool, vector: Vector4, target: Vector4, delta: Vector4, square: F32, +distance: F32) -> Vector4:
  match snap:
    case True{}: target
    case False{}:
      Vector4{x, y, z, w} = vector
      Vector4{dx, dy, dz, dw} = delta
      +length = F32.sqrt(square)
      Vector4{(x + dx / length * distance : F32), (y + dy / length * distance : F32),
        (z + dz / length * distance : F32), (w + dw / length * distance : F32)}

def Vector4.move_towards(+vector: Vector4, +target: Vector4, +distance: F32) -> Vector4:
  +delta = Vector4.subtract(target, vector)
  +square = Vector4.dot_product(delta, delta)
  Vector4.move.route(F32.is_eq(square, 0.0) || (((distance >= 0.0) && (square <= distance * distance)) : F32), vector, target, delta, square, distance)

def Vector4.equals(left: Vector4, right: Vector4) -> Bool:
  Vector4{x, y, z, w} = left
  Vector4{a, b, c, d} = right
  Math.float_equals(x, a) && Math.float_equals(y, b) && Math.float_equals(z, c) && Math.float_equals(w, d)

def Quaternion.identity() -> Vector4:
  Vector4{0.0, 0.0, 0.0, 1.0}

def Quaternion.add(left: Vector4, right: Vector4) -> Vector4:
  Vector4.add(left, right)

def Quaternion.subtract(left: Vector4, right: Vector4) -> Vector4:
  Vector4.subtract(left, right)

def Quaternion.multiply(left: Vector4, right: Vector4) -> Vector4:
  Vector4{+x, +y, +z, +w} = left
  Vector4{+a, +b, +c, +d} = right
  Vector4{(x * d + w * a + y * c - z * b : F32), (y * d + w * b + z * a - x * c : F32),
    (z * d + w * c + x * b - y * a : F32), (w * d - x * a - y * b - z * c : F32)}

def Quaternion.add_value(quaternion: Vector4, value: F32) -> Vector4:
  Vector4.add_value(quaternion, value)

def Quaternion.subtract_value(quaternion: Vector4, value: F32) -> Vector4:
  Vector4.subtract_value(quaternion, value)

def Quaternion.length(quaternion: Vector4) -> F32:
  Vector4.length(quaternion)

def Quaternion.normalize(+quaternion: Vector4) -> Vector4:
  +length = Quaternion.length(quaternion)
  inverse = (1.0 / Bool.pick(F32, F32.is_eq(length, 0.0), 1.0, length) : F32)
  Vector4.scale(quaternion, inverse)

def Quaternion.inverted(nonzero: Bool, quaternion: Vector4, square: F32) -> Vector4:
  match nonzero:
    case False{}: quaternion
    case True{}:
      Vector4{x, y, z, w} = quaternion
      +inverse = (1.0 / square : F32)
      Vector4{(x * F32.neg(inverse) : F32), (y * F32.neg(inverse) : F32), (z * F32.neg(inverse) : F32), (w * inverse : F32)}

def Quaternion.invert(+quaternion: Vector4) -> Vector4:
  +square = Vector4.length_sqr(quaternion)
  Quaternion.inverted(F32.is_ne(square, 0.0), quaternion, square)

def Quaternion.scale(quaternion: Vector4, factor: F32) -> Vector4:
  Vector4.scale(quaternion, factor)

def Quaternion.divide(left: Vector4, right: Vector4) -> Vector4:
  Vector4.divide(left, right)

def Quaternion.lerp(left: Vector4, right: Vector4, amount: F32) -> Vector4:
  Vector4.lerp(left, right, amount)

def Quaternion.nlerp(left: Vector4, right: Vector4, amount: F32) -> Vector4:
  Quaternion.normalize(Quaternion.lerp(left, right, amount))

def Quaternion.equals(+left: Vector4, +right: Vector4) -> Bool:
  Vector4.equals(left, right) || Vector4.equals(left, Vector4.negate(right))

def Collision.spheres(left: Vector3, radius: F32, right: Vector3, other_radius: F32) -> Bool:
  +sum = (radius + other_radius : F32)
  (Vector3.distance_sqr(left, right) <= sum * sum : F32)

def Collision.boxes(left: BoundingBox, right: BoundingBox) -> Bool:
  BoundingBox{Vector3{ax, ay, az}, Vector3{bx, by, bz}} = left
  BoundingBox{Vector3{cx, cy, cz}, Vector3{dx, dy, dz}} = right
  ((bx >= cx) && (ax <= dx) && (by >= cy) && (ay <= dy) && (bz >= cz) && (az <= dz) : F32)

def Collision.box_sphere(box: BoundingBox, center: Vector3, +radius: F32) -> Bool:
  BoundingBox{Vector3{lx, ly, lz}, Vector3{ux, uy, uz}} = box
  Vector3{+x, +y, +z} = center
  closest = {Vector3{Math.clamp(x, lx, ux), Math.clamp(y, ly, uy), Math.clamp(z, lz, uz)} : Vector3}
  (Vector3.distance_sqr(Vector3{x, y, z}, closest) <= radius * radius : F32)

def Collision.recs(left: Rectangle, right: Rectangle) -> Bool:
  Rectangle{+x, +y, w, h} = left
  Rectangle{+u, +v, rw, rh} = right
  ((x < u + rw) && (x + w > u) && (y < v + rh) && (y + h > v) : F32)

def Collision.circles(left: Vector2, radius: F32, right: Vector2, other_radius: F32) -> Bool:
  Vector2{x, y} = left
  Vector2{u, v} = right
  +dx = (u - x : F32)
  +dy = (v - y : F32)
  +sum = (radius + other_radius : F32)
  (dx * dx + dy * dy <= sum * sum : F32)

def Collision.rectangle.result(overlap: Bool, +x: F32, +y: F32, right: F32, bottom: F32) -> Rectangle:
  match overlap:
    case False{}: Rectangle{0.0, 0.0, 0.0, 0.0}
    case True{}: Rectangle{x, y, (right - x : F32), (bottom - y : F32)}

def Collision.rectangle(left: Rectangle, right: Rectangle) -> Rectangle:
  Rectangle{+x, +y, w, h} = left
  Rectangle{+u, +v, rw, rh} = right
  +start_x = Bool.pick(F32, (x > u : F32), x, u)
  +end1 = (x + w : F32)
  +end2 = (u + rw : F32)
  +end_x = Bool.pick(F32, (end1 < end2 : F32), end1, end2)
  +start_y = Bool.pick(F32, (y > v : F32), y, v)
  +bottom1 = (y + h : F32)
  +bottom2 = (v + rh : F32)
  +end_y = Bool.pick(F32, (bottom1 < bottom2 : F32), bottom1, bottom2)
  Collision.rectangle.result(((start_x < end_x) && (start_y < end_y) : F32), start_x, start_y, end_x, end_y)

def Collision.point_rec(point: Vector2, rectangle: Rectangle) -> Bool:
  Vector2{+x, +y} = point
  Rectangle{+rx, +ry, w, h} = rectangle
  ((x >= rx) && (x < rx + w) && (y >= ry) && (y < ry + h) : F32)

def Collision.point_circle(point: Vector2, center: Vector2, +radius: F32) -> Bool:
  Vector2{x, y} = point
  Vector2{cx, cy} = center
  +dx = (x - cx : F32)
  +dy = (y - cy : F32)
  (dx * dx + dy * dy <= radius * radius : F32)

def Collision.circle_rec(center: Vector2, +radius: F32, rectangle: Rectangle) -> Bool:
  Vector2{x, y} = center
  Rectangle{rx, ry, w, h} = rectangle
  +half_w = (w / 2.0 : F32)
  +half_h = (h / 2.0 : F32)
  +dx = F32.abs((x - (rx + half_w) : F32))
  +dy = F32.abs((y - (ry + half_h) : F32))
  +corner_x = (dx - half_w : F32)
  +corner_y = (dy - half_h : F32)
  (((dx <= half_w + radius) && (dy <= half_h + radius))
    && ((dx <= half_w) || (dy <= half_h) || (corner_x * corner_x + corner_y * corner_y <= radius * radius)) : F32)

def Collision.lines.hit(inside: Bool, +arithmetic: Collision.Arithmetic, x: F32, y: F32, rx: F32, ry: F32, +t: F32) -> Maybe<&2, Vector2>:
  match inside:
    case False{}: None{}
    case True{}: Some{Vector2{Collision.multiply_add(arithmetic, t, rx, x), Collision.multiply_add(arithmetic, t, ry, y)}}

def Collision.lines.divided(nonparallel: Bool, +arithmetic: Collision.Arithmetic, +x: F32, +y: F32, +rx: F32, +ry: F32, +sx: F32, +sy: F32, u: F32, v: F32, +divisor: F32) -> Maybe<&2, Vector2>:
  match nonparallel:
    case False{}: None{}
    case True{}:
      +dx = (u - x : F32)
      +dy = (v - y : F32)
      +t = (Collision.multiply_add(arithmetic, dx, sy, F32.neg((dy * sx : F32))) / divisor : F32)
      +s = (Collision.multiply_add(arithmetic, dx, ry, F32.neg((dy * rx : F32))) / divisor : F32)
      Collision.lines.hit(((0.0 <= t) && (t <= 1.0) && (0.0 <= s) && (s <= 1.0) : F32), arithmetic, x, y, rx, ry, t)

def Collision.lines_for(+arithmetic: Collision.Arithmetic, start: Vector2, end: Vector2, other_start: Vector2, other_end: Vector2) -> Maybe<&2, Vector2>:
  Vector2{+x, +y} = start
  Vector2{ex, ey} = end
  Vector2{+u, +v} = other_start
  Vector2{eu, ev} = other_end
  +rx = (ex - x : F32)
  +ry = (ey - y : F32)
  +sx = (eu - u : F32)
  +sy = (ev - v : F32)
  +divisor = Collision.multiply_add(arithmetic, rx, sy, F32.neg((ry * sx : F32)))
  Collision.lines.divided((F32.abs(divisor) >= 0.00000011920928955078125 : F32), arithmetic, x, y, rx, ry, sx, sy, u, v, divisor)

def Collision.lines(start: Vector2, end: Vector2, other_start: Vector2, other_end: Vector2) -> Maybe<&2, Vector2>:
  Collision.lines_for(UncontractedCollision{}, start, end, other_start, other_end)

def Collision.point_triangle(point: Vector2, first: Vector2, second: Vector2, third: Vector2) -> Bool:
  Vector2{+x, +y} = point
  Vector2{+ax, +ay} = first
  Vector2{+bx, +by} = second
  Vector2{+cx, +cy} = third
  +denominator = ((by - cy) * (ax - cx) + (cx - bx) * (ay - cy) : F32)
  +alpha = (((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / denominator : F32)
  +beta = (((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / denominator : F32)
  gamma = (1.0 - alpha - beta : F32)
  ((alpha > 0.0) && (beta > 0.0) && (gamma > 0.0) : F32)

def Collision.point_line(point: Vector2, first: Vector2, second: Vector2, threshold: F32) -> Bool:
  Vector2{+x, +y} = point
  Vector2{+ax, +ay} = first
  Vector2{+bx, +by} = second
  +dx = (bx - ax : F32)
  +dy = (by - ay : F32)
  cross = ((x - ax) * dy - (y - ay) * dx : F32)
  along_x = Bool.pick(Bool, (dx > 0.0 : F32), ((ax <= x) && (x <= bx) : F32), ((bx <= x) && (x <= ax) : F32))
  along_y = Bool.pick(Bool, (dy > 0.0 : F32), ((ay <= y) && (y <= by) : F32), ((by <= y) && (y <= ay) : F32))
  (F32.abs(cross) < threshold * F32.max(F32.abs(dx), F32.abs(dy)) : F32)
    && Bool.pick(Bool, (F32.abs(dx) >= F32.abs(dy) : F32), along_x, along_y)

def Collision.circle_line.route(degenerate: Bool, +x: F32, +y: F32, +radius: F32, +ax: F32, +ay: F32, bx: F32, by: F32, +dx: F32, +dy: F32) -> Bool:
  match degenerate:
    case True{}: Collision.circles(Vector2{ax, ay}, 0.0, Vector2{x, y}, radius)
    case False{}:
      length_squared = (dx * dx + dy * dy : F32)
      +projection = Math.clamp((((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / length_squared : F32), 0.0, 1.0)
      +distance_x = ((ax - projection * dx) - x : F32)
      +distance_y = ((ay - projection * dy) - y : F32)
      (distance_x * distance_x + distance_y * distance_y <= radius * radius : F32)

def Collision.circle_line(center: Vector2, radius: F32, first: Vector2, second: Vector2) -> Bool:
  Vector2{x, y} = center
  Vector2{+ax, +ay} = first
  Vector2{+bx, +by} = second
  +dx = (ax - bx : F32)
  +dy = (ay - by : F32)
  Collision.circle_line.route((F32.abs(dx) + F32.abs(dy) <= 0.00000011920928955078125 : F32), x, y, radius, ax, ay, bx, by, dx, dy)

def Collision.polygon.last(points: +List<Vector2>, previous: Vector2) -> Vector2:
  match points:
    case Nil{}: previous
    case Con{point, rest}: Collision.polygon.last(rest, point)

def Collision.polygon.crossing(straddles: Bool, x: F32, y: F32, +ax: F32, +ay: F32, bx: F32, by: F32) -> Bool:
  match straddles:
    case False{}: False{}
    case True{}: (x < (bx - ax) * (y - ay) / (by - ay) + ax : F32)

def Collision.polygon.edge(point: Vector2, current: Vector2, previous: Vector2) -> Bool:
  Vector2{x, +y} = point
  Vector2{ax, +ay} = current
  Vector2{bx, +by} = previous
  Collision.polygon.crossing(Bool.xor((ay > y : F32), (by > y : F32)), x, y, ax, ay, bx, by)

def Collision.polygon.loop(points: +List<Vector2>, +point: Vector2, previous: Vector2, inside: Bool) -> Bool:
  match points:
    case Nil{}: inside
    case Con{+current, rest}:
      Collision.polygon.loop(rest, point, current, Bool.xor(inside, Collision.polygon.edge(point, current, previous)))

def Collision.point_poly(point: Vector2, +points: +List<Vector2>) -> Bool:
  (List.length(&2, Vector2, points) > 2n : Nat)
    && Collision.polygon.loop(points, point, Collision.polygon.last(points, Vector2.zero()), False{})

# Internal signed-word operations for raylib's integer raster stepping.
def Signed.word(+x: F32) -> U32:
  +magnitude = F32.to_u32(F32.abs(x))
  Bool.pick(U32, (x < 0.0 : F32), (0 - magnitude : U32), magnitude)

def Signed.high16(+word: U32) -> F32:
  (U32.to_f32((word >> 16n : U32))
    - Bool.pick(F32, (word >= 2147483648 : U32), 65536.0, 0.0) : F32)

def Signed.trunc(+x: F32) -> F32:
  +magnitude = F32.floor(F32.abs(x))
  Bool.pick(F32, (x < 0.0 : F32), (0.0 - magnitude : F32), magnitude)

def Signed.to_f32(+word: U32) -> F32:
  Bool.pick(F32, (word >= 2147483648 : U32), F32.neg(U32.to_f32((0 - word : U32))), U32.to_f32(word))

# A color is packed RRGGBBAA. Channel conversion follows C unsigned-byte casts.
def Color.rgba(r: U32, g: U32, b: U32, a: U32) -> U32:
  (((r .&. 255) << 24n) .|. ((g .&. 255) << 16n) .|. ((b .&. 255) << 8n) .|. (a .&. 255) : U32)

def Color.red(c: U32) -> U32:
  (c >> 24n : U32)

def Color.green(c: U32) -> U32:
  ((c >> 16n) .&. 255 : U32)

def Color.blue(c: U32) -> U32:
  ((c >> 8n) .&. 255 : U32)

def Color.alpha(c: U32) -> U32:
  (c .&. 255 : U32)

def Color.normalize(+color: U32) -> Vector4:
  Vector4{(U32.to_f32(Color.red(color)) / 255.0 : F32), (U32.to_f32(Color.green(color)) / 255.0 : F32),
    (U32.to_f32(Color.blue(color)) / 255.0 : F32), (U32.to_f32(Color.alpha(color)) / 255.0 : F32)}

def Color.from_normalized(value: Vector4) -> U32:
  Vector4{r, g, b, a} = value
  Color.rgba(F32.to_u32((r * 255.0 : F32)), F32.to_u32((g * 255.0 : F32)),
    F32.to_u32((b * 255.0 : F32)), F32.to_u32((a * 255.0 : F32)))

def Color.hsv.components(achromatic: Bool, +r: F32, +g: F32, +b: F32, +maximum: F32, +delta: F32) -> Vector3:
  match achromatic:
    case True{}: Vector3{0.0, 0.0, maximum}
    case False{}:
      sector = Bool.pick(F32, (r >= maximum : F32), ((g - b) / delta : F32),
        Bool.pick(F32, (g >= maximum : F32), (2.0 + (b - r) / delta : F32), (4.0 + (r - g) / delta : F32)))
      +hue = (sector * 60.0 : F32)
      Vector3{Bool.pick(F32, (hue < 0.0 : F32), (hue + 360.0 : F32), hue), (delta / maximum : F32), maximum}

def Color.to_hsv(+color: U32) -> Vector3:
  +r = (U32.to_f32(Color.red(color)) / 255.0 : F32)
  +g = (U32.to_f32(Color.green(color)) / 255.0 : F32)
  +b = (U32.to_f32(Color.blue(color)) / 255.0 : F32)
  minimum = F32.min(F32.min(r, g), b)
  +maximum = F32.max(F32.max(r, g), b)
  +delta = (maximum - minimum : F32)
  Color.hsv.components((delta < 0.00001 : F32), r, g, b, maximum, delta)

def Color.hsv.channel(offset: F32, hue: F32, saturation: F32, +value: F32) -> U32:
  # Hue 0..360 makes the shifted phase 1..11, requiring at most one remainder subtraction.
  +phase = (offset + hue / 60.0 : F32)
  +k = Bool.pick(F32, (phase >= 6.0 : F32), (phase - 6.0 : F32), phase)
  gain = F32.clamp(F32.min((4.0 - k : F32), k), 0.0, 1.0)
  F32.to_u32(((value - value * saturation * gain) * 255.0 : F32))

def Color.from_hsv(+hue: F32, +saturation: F32, +value: F32) -> U32:
  Color.rgba(Color.hsv.channel(5.0, hue, saturation, value), Color.hsv.channel(3.0, hue, saturation, value),
    Color.hsv.channel(1.0, hue, saturation, value), 255)

def Color.tint(+source: U32, +tint: U32) -> U32:
  Color.rgba(((Color.red(source) * (Color.red(tint) + 1)) >> 8n : U32),
    ((Color.green(source) * (Color.green(tint) + 1)) >> 8n : U32),
    ((Color.blue(source) * (Color.blue(tint) + 1)) >> 8n : U32),
    ((Color.alpha(source) * (Color.alpha(tint) + 1)) >> 8n : U32))

def Color.blend.channel(dst: U32, src: U32, da: U32, +sa: U32, out: U32) -> U32:
  (((src * sa * 256 + dst * da * (256 - sa)) / out) >> 8n : U32)

def Color.blend.with_alpha(alpha: U32, +dst: U32, +src: U32) -> U32:
  match alpha:
    case 0:
      dst
    case 255:
      src
    case a:
      +sa = (a + 1 : U32)
      +da = Color.alpha(dst)
      +out = ((sa * 256 + da * (256 - sa)) >> 8n : U32)
      Color.rgba(Color.blend.channel(Color.red(dst), Color.red(src), da, sa, out),
        Color.blend.channel(Color.green(dst), Color.green(src), da, sa, out),
        Color.blend.channel(Color.blue(dst), Color.blue(src), da, sa, out), out)

def Color.blend.tinted(dst: U32, +src: U32) -> U32:
  Color.blend.with_alpha(Color.alpha(src), dst, src)

# raylib's integer ColorAlphaBlend, including its 256-based tint/alpha rounding.
def Color.alpha_blend(dst: U32, src: U32, tint: U32) -> U32:
  Color.blend.tinted(dst, Color.tint(src, tint))

type Color.Transform is Data:
  ImageTint{color: U32}
  ImageInvert{}
  ImageContrast{factor: F32}
  ImageBrightness{amount: F32}
  ImageReplace{original: U32, replacement: U32}
  AlphaClear{threshold: U32, color: U32}
  AlphaPremultiply{}
  ImageChannel{shift: Nat}

def Color.image_contrast(channel: U32, factor: F32) -> U32:
  F32.to_u32(F32.clamp((((U32.to_f32(channel) / 255.0 - 0.5) * factor + 0.5) * 255.0 : F32), 0.0, 255.0))

def Color.image_brightness(channel: U32, amount: F32) -> U32:
  +value = (U32.to_f32(channel) + amount : F32)
  F32.to_u32(Bool.pick(F32, (value < 0.0 : F32), 1.0, F32.min(255.0, value)))

def Color.transform(transform: Color.Transform, +pixel: U32) -> U32:
  match transform:
    case ImageChannel{shift}:
      +channel = ((pixel >> shift) .&. 255 : U32)
      Color.rgba(channel, channel, channel, 255)
    case ImageTint{+color}:
      Color.rgba((Color.red(pixel) * Color.red(color) / 255 : U32), (Color.green(pixel) * Color.green(color) / 255 : U32),
        (Color.blue(pixel) * Color.blue(color) / 255 : U32), (Color.alpha(pixel) * Color.alpha(color) / 255 : U32))
    case ImageInvert{}: U32.xor(pixel, 4294967040)
    case ImageContrast{+factor}:
      Color.rgba(Color.image_contrast(Color.red(pixel), factor), Color.image_contrast(Color.green(pixel), factor),
        Color.image_contrast(Color.blue(pixel), factor), Color.alpha(pixel))
    case ImageBrightness{+amount}:
      Color.rgba(Color.image_brightness(Color.red(pixel), amount), Color.image_brightness(Color.green(pixel), amount),
        Color.image_brightness(Color.blue(pixel), amount), Color.alpha(pixel))
    case ImageReplace{original, replacement}: Bool.pick(U32, U32.is_eq(pixel, original), replacement, pixel)
    case AlphaClear{threshold, color}: Bool.pick(U32, (Color.alpha(pixel) <= threshold : U32), color, pixel)
    case AlphaPremultiply{}:
      +alpha = Color.alpha(pixel)
      +factor = (U32.to_f32(alpha) / 255.0 : F32)
      Color.rgba(F32.to_u32((U32.to_f32(Color.red(pixel)) * factor : F32)),
        F32.to_u32((U32.to_f32(Color.green(pixel)) * factor : F32)), F32.to_u32((U32.to_f32(Color.blue(pixel)) * factor : F32)), alpha)

def Color.grayscale(+pixel: U32) -> U32:
  F32.to_u32(((U32.to_f32(Color.red(pixel)) / 255.0 * 0.299
    + U32.to_f32(Color.green(pixel)) / 255.0 * 0.587
    + U32.to_f32(Color.blue(pixel)) / 255.0 * 0.114) * 255.0 : F32))

def Color.is_equal(left: U32, right: U32) -> Bool:
  U32.is_eq(left, right)

def Color.with_alpha(color: U32, alpha: F32) -> U32:
  ((color .&. 4294967040) .|. F32.to_u32((255.0 * F32.clamp(alpha, 0.0, 1.0) : F32)) : U32)

def Color.multiply(color: U32, tint: U32) -> U32:
  Color.transform(ImageTint{tint}, color)

def Color.brightness.channel(channel: U32, +factor: F32) -> U32:
  +value = U32.to_f32(channel)
  F32.to_u32(Bool.pick(F32, (factor < 0.0 : F32), (value * (1.0 + factor) : F32), ((255.0 - value) * factor + value : F32)))

def Color.brightness(+color: U32, factor: F32) -> U32:
  +bounded = F32.clamp(factor, (0.0 - 1.0 : F32), 1.0)
  Color.rgba(Color.brightness.channel(Color.red(color), bounded), Color.brightness.channel(Color.green(color), bounded),
    Color.brightness.channel(Color.blue(color), bounded), Color.alpha(color))

def Color.contrast(color: U32, factor: F32) -> U32:
  +adjusted = (1.0 + F32.clamp(factor, (0.0 - 1.0 : F32), 1.0) : F32)
  Color.transform(ImageContrast{(adjusted * adjusted : F32)}, color)

def Color.lerp.channel(left: U32, right: U32, +factor: F32) -> U32:
  F32.to_u32(((1.0 - factor) * U32.to_f32(left) + factor * U32.to_f32(right) : F32))

def Color.lerp(+left: U32, +right: U32, factor: F32) -> U32:
  +bounded = F32.clamp(factor, 0.0, 1.0)
  Color.rgba(Color.lerp.channel(Color.red(left), Color.red(right), bounded), Color.lerp.channel(Color.green(left), Color.green(right), bounded),
    Color.lerp.channel(Color.blue(left), Color.blue(right), bounded), Color.lerp.channel(Color.alpha(left), Color.alpha(right), bounded))

# Construct through Surface.create; preserve its dimensions/storage invariant.
type Surface is Type:
  Surface{width: U32, height: U32, pixels: Array<U32>}

type Surface.Error is Data:
  InvalidSize{}
  InvalidRectangle{}
  UnsafeNearestMapping{}

type Image.DecodeError is Data:
  InvalidImageHeader{}
  InvalidImageByte{}
  UnsupportedImageSize{}
  TruncatedImageData{}
  InvalidImageStream{}

type Image.LoadError is Type:
  ImageFileError{code: U32, message: String}
  ImageDecodeError{error: Image.DecodeError}

def Surface.qoi.error(error: Qoi.Error) -> Image.DecodeError:
  match error:
    case Qoi.BadHeader{}: InvalidImageHeader{}
    case Qoi.BadByte{}: InvalidImageByte{}
    case Qoi.BadSize{}: UnsupportedImageSize{}
    case Qoi.Truncated{}: TruncatedImageData{}
    case Qoi.BadStream{}: InvalidImageStream{}

def Surface.qoi.result(result: Result<&1, &1, Qoi.Error, Qoi.Image>) -> Result<&1, &1, Image.DecodeError, Surface>:
  match result:
    case Fail{error}: Fail{Surface.qoi.error(error)}
    case Done{Qoi.Image{width, height, pixels}}: Done{Surface{width, height, pixels}}

def Surface.decode_qoi(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  Surface.qoi.result(Qoi.decode(bytes))

def Surface.to_qoi(surface: Surface) -> +List<U32>:
  Surface{w, h, pixels} = surface
  Qoi.encode(w, h, pixels)

def Surface.dimensions(surface: Surface) -> U32 & U32:
  Surface{w, h, _} = surface
  (w, h)

def Surface.capacity(+count: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))

def Surface.creation.checked(ok: Bool, +w: U32, +h: U32, color: U32) -> Maybe<Surface>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{Surface{w, h, Array.new(U32, Surface.capacity((w * h : U32)), color)}}

# The initial profile supports 1..4096 pixels on each axis.
def Surface.create(+w: U32, +h: U32, color: U32) -> Maybe<Surface>:
  Surface.creation.checked(((w > 0) && (h > 0) && (w <= 4096) && (h <= 4096) : U32), w, h, color)

def Surface.checked.loop(n: Nat, +i: U32, +width: U32, +tx: U32, +ty: U32, +first: U32, +second: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+k:
      color = Bool.pick(U32, U32.is_eq((((i % width) / tx + (i / width) / ty) .&. 1 : U32), 0), first, second)
      Surface.checked.loop(k, (i + 1 : U32), width, tx, ty, first, second, Array.set(U32, pixels, i, color))

def Surface.checked.create(valid: Bool, +width: U32, +height: U32, tx: U32, ty: U32, +first: U32, second: U32) -> Maybe<Surface>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      Some{Surface{width, height, Surface.checked.loop(U32.to_nat(count), 0, width, tx, ty, first, second, Array.new(U32, Surface.capacity(count), first))}}

def Surface.create_checked(+width: U32, +height: U32, +tx: U32, +ty: U32, first: U32, second: U32) -> Maybe<Surface>:
  Surface.checked.create(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096)
    && (tx > 0) && (ty > 0) && (tx <= 2147483647) && (ty <= 2147483647) : U32), width, height, tx, ty, first, second)

def Surface.square_gradient.loop(n: Nat, +i: U32, +width: U32, +cx: F32, +cy: F32, +density: F32, +inner: U32, +outer: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+k:
      nx = (F32.abs((U32.to_f32((i % width : U32)) - cx : F32)) / cx : F32)
      ny = (F32.abs((U32.to_f32((i / width : U32)) - cy : F32)) / cy : F32)
      factor = ((F32.max(nx, ny) - density) / (1.0 - density) : F32)
      Surface.square_gradient.loop(k, (i + 1 : U32), width, cx, cy, density, inner, outer,
        Array.set(U32, pixels, i, Color.lerp(inner, outer, factor)))

def Surface.square_gradient.checked(valid: Bool, solid: Bool, +width: U32, +height: U32, density: F32, +inner: U32, outer: U32) -> Maybe<Surface>:
  match valid solid:
    case False{} _: None{}
    case True{} True{}: Surface.create(width, height, inner)
    case True{} False{}:
      +count = (width * height : U32)
      Some{Surface{width, height, Surface.square_gradient.loop(U32.to_nat(count), 0, width,
        (U32.to_f32(width) / 2.0 : F32), (U32.to_f32(height) / 2.0 : F32), density, inner, outer,
        Array.new(U32, Surface.capacity(count), inner))}}

def Surface.create_gradient_square(+width: U32, +height: U32, +density: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  Surface.square_gradient.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && ((density >= 0.0) && (density <= 1.0) : F32), F32.is_eq(density, 1.0), width, height, density, inner, outer)

def Surface.radial.checked(valid: Bool, +width: U32, +height: U32, density: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      paint = {Gradients.Radial{(U32.to_f32(width) / 2.0 : F32), (U32.to_f32(height) / 2.0 : F32),
        (U32.to_f32(U32.min(width, height)) / 2.0 : F32), density, inner, outer} : Gradients.Paint}
      Some{Surface{width, height, Gradients.generate(Surface.capacity(count), width, count, paint)}}

def Surface.create_gradient_radial(+width: U32, +height: U32, +density: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  Surface.radial.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && ((density >= 0.0) && (density <= 1.0) : F32), width, height, density, inner, outer)

def Surface.linear.ready(valid: Bool, +width: U32, +height: U32, cosine: F32, sine: F32, start: F32, extent: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      Some{Surface{width, height, Gradients.generate(Surface.capacity(count), width, count,
        Gradients.Linear{cosine, sine, start, extent, inner, outer})}}

def Surface.linear.trigonometry(+width: U32, +height: U32, inner: U32, outer: U32, values: F32 & F32) -> Maybe<Surface>:
  (+cosine, +sine) = values
  +start = (0.5 - cosine * U32.to_f32(width) / 2.0 - sine * U32.to_f32(height) / 2.0 : F32)
  same_sign = U32.is_eq((F32.bits(sine) >> 31n : U32), (F32.bits(cosine) >> 31n : U32))
  +extent = F32.abs(Bool.pick(F32, same_sign, start, (start + U32.to_f32(width) * cosine : F32)))
  Surface.linear.ready((extent > 0.0 : F32), width, height, cosine, sine, start, extent, inner, outer)

def Surface.linear.checked(valid: Bool, reference: Gradient.Reference, +width: U32, +height: U32, direction: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  match valid:
    case False{}: None{}
    case True{}:
      radians = ((90.0 - direction) / 180.0 * 3.14159 : F32)
      Surface.linear.trigonometry(width, height, inner, outer, Trig.sincos_for(Gradient.gnu(reference), radians))

def Surface.create_gradient_linear_for(reference: Gradient.Reference, +width: U32, +height: U32, +direction: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  Surface.linear.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && (F32.abs(direction) <= 360.0 : F32) && F32.is_eq(F32.floor(direction), direction), reference, width, height, direction, inner, outer)

def Surface.create_gradient_linear(width: U32, height: U32, direction: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  Surface.create_gradient_linear_for(AccurateGradient{}, width, height, direction, inner, outer)

def Surface.clear(surface: Surface, color: U32) -> Surface:
  Surface{+w, +h, _} = surface
  Surface{w, h, Array.new(U32, Surface.capacity((w * h : U32)), color)}

def Surface.color.step(i: U32, transform: Color.Transform, got: Array<U32> & U32) -> Array<U32>:
  (pixels, pixel) = got
  Array.set(U32, pixels, i, Color.transform(transform, pixel))

def Surface.color.loop(n: Nat, +i: U32, +transform: Color.Transform, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+k:
      Surface.color.loop(k, (i + 1 : U32), transform, Surface.color.step(i, transform, Array.get(U32, pixels, i)))

def Surface.color.transform(surface: Surface, transform: Color.Transform) -> Surface:
  Surface{+w, +h, pixels} = surface
  Surface{w, h, Surface.color.loop(U32.to_nat((w * h : U32)), 0, transform, pixels)}

def Surface.color_tint(surface: Surface, color: U32) -> Surface:
  Surface.color.transform(surface, ImageTint{color})

def Surface.color_invert(surface: Surface) -> Surface:
  Surface.color.transform(surface, ImageInvert{})

def Surface.color_contrast(surface: Surface, amount: F32) -> Surface:
  +contrast = ((100.0 + F32.clamp(amount, (0.0 - 100.0 : F32), 100.0)) / 100.0 : F32)
  Surface.color.transform(surface, ImageContrast{(contrast * contrast : F32)})

def Surface.color_brightness(surface: Surface, amount: F32) -> Surface:
  Surface.color.transform(surface, ImageBrightness{F32.clamp(amount, (0.0 - 255.0 : F32), 255.0)})

def Surface.color_replace(surface: Surface, original: U32, replacement: U32) -> Surface:
  Surface.color.transform(surface, ImageReplace{original, replacement})

def Surface.alpha_clear(surface: Surface, color: U32, threshold: F32) -> Surface:
  Surface.color.transform(surface, AlphaClear{F32.to_u32((threshold * 255.0 : F32)), color})

def Surface.alpha_premultiply(surface: Surface) -> Surface:
  Surface.color.transform(surface, AlphaPremultiply{})

def Surface.mask.pixel(destination: Array<U32> & U32, source: Array<U32> & U32, at: U32) -> Array<U32> & Array<U32>:
  (dst, color) = destination
  (mask, value) = source
  (Array.set(U32, dst, at, ((color .&. 4294967040) .|. Color.grayscale(value) : U32)), mask)

def Surface.mask.loop(n: Nat, +at: U32, state: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n state:
    case 0n _: state
    case 1n+k Tuple{dst, mask}:
      Surface.mask.loop(k, (at + 1 : U32), Surface.mask.pixel(Array.get(U32, dst, at), Array.get(U32, mask, at), at))

def Surface.mask.finish(+w: U32, +h: U32, state: Array<U32> & Array<U32>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  (dst, mask) = state
  Done{(Surface{w, h, dst}, Surface{w, h, mask})}

def Surface.mask.checked(valid: Bool, +w: U32, +h: U32, mw: U32, mh: U32, dst: Array<U32>, mask: Array<U32>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match valid:
    case False{}: Fail{((Surface{w, h, dst}, Surface{mw, mh, mask}), InvalidSize{})}
    case True{}: Surface.mask.finish(w, h, Surface.mask.loop(U32.to_nat((w * h : U32)), 0, (dst, mask)))

def Surface.alpha_mask(destination: Surface, source: Surface) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  Surface{+w, +h, dst} = destination
  Surface{+mw, +mh, mask} = source
  Surface.mask.checked(U32.is_eq(w, mw) && U32.is_eq(h, mh), w, h, mw, mh, dst, mask)

def Surface.get.result(w: U32, h: U32, got: Array<U32> & U32) -> Surface & Maybe<&2, U32>:
  (pixels, color) = got
  (Surface{w, h, pixels}, Some{color})

def Surface.get.checked(ok: Bool, +w: U32, h: U32, pixels: Array<U32>, x: U32, y: U32) -> Surface & Maybe<&2, U32>:
  match ok:
    case False{}:
      (Surface{w, h, pixels}, None{})
    case True{}:
      Surface.get.result(w, h, Array.get(U32, pixels, (y * w + x : U32)))

def Surface.get(surface: Surface, +x: U32, +y: U32) -> Surface & Maybe<&2, U32>:
  Surface{+w, +h, pixels} = surface
  Surface.get.checked(((x < w) && (y < h) : U32), w, h, pixels, x, y)

def Surface.pixel.checked(ok: Bool, +w: U32, h: U32, pixels: Array<U32>, x: F32, y: F32, color: U32) -> Surface:
  match ok:
    case False{}:
      Surface{w, h, pixels}
    case True{}:
      Surface{w, h, Array.set(U32, pixels, (F32.to_u32(y) * w + F32.to_u32(x) : U32), color)}

# Drawing coordinates are finite integral F32 values in the initial profile.
# ImageDrawPixel replaces RGBA bytes; it does not alpha-blend them.
def Surface.draw_pixel(surface: Surface, +x: F32, +y: F32, color: U32) -> Surface:
  Surface{+w, +h, pixels} = surface
  Surface.pixel.checked(((x >= 0.0) && (y >= 0.0) && (x < U32.to_f32(w)) && (y < U32.to_f32(h)) : F32), w, h, pixels, x, y, color)

def Surface.draw_pixel_v(surface: Surface, position: Vector2, color: U32) -> Surface:
  Vector2{x, y} = position
  Surface.draw_pixel(surface, Signed.trunc(x), Signed.trunc(y), color)

def Surface.span(n: Nat, +at: U32, +color: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      pixels
    case 1n+k:
      Surface.span(k, (at + 1 : U32), color, Array.set(U32, pixels, at, color))

def Surface.rows(n: Nat, +at: U32, +stride: U32, +cols: Nat, +color: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      pixels
    case 1n+k:
      Surface.rows(k, (at + stride : U32), stride, cols, color, Surface.span(cols, at, color, pixels))

def Surface.rectangle.fill(ok: Bool, +w: U32, h: U32, pixels: Array<U32>, x: U32, y: U32, +cols: U32, rows: U32, color: U32) -> Surface:
  match ok:
    case False{}:
      Surface{w, h, pixels}
    case True{}:
      # raylib writes the first pixel even for an accepted zero-width rectangle;
      # subsequent rows copy zero bytes. Zero height still writes the first row.
      +nr = Bool.pick(U32, U32.is_eq(cols, 0), 1, U32.max(1, rows))
      Surface{w, h, Surface.rows(U32.to_nat(nr), (y * w + x : U32), w,
        U32.to_nat(U32.max(1, cols)), color, pixels)}

def Surface.draw_rectangle(surface: Surface, +x: F32, +y: F32, width: F32, height: F32, color: U32) -> Surface:
  Surface{+w, +h, pixels} = surface
  +sx = F32.max(0.0, x)
  +sy = F32.max(0.0, y)
  +cw = F32.max(0.0, F32.min(F32.max(0.0, (width + F32.min(0.0, x) : F32)), (U32.to_f32(w) - sx : F32)))
  +ch = F32.max(0.0, F32.min(F32.max(0.0, (height + F32.min(0.0, y) : F32)), (U32.to_f32(h) - sy : F32)))
  Surface.rectangle.fill(((sx < U32.to_f32(w)) && (sy < U32.to_f32(h)) && (sx + cw > 0.0) && (sy + ch > 0.0) : F32),
    w, h, pixels, F32.to_u32(sx), F32.to_u32(sy), F32.to_u32(cw), F32.to_u32(ch), color)

def Surface.draw_rectangle_v(surface: Surface, position: Vector2, size: Vector2, color: U32) -> Surface:
  Vector2{x, y} = position
  Vector2{width, height} = size
  Surface.draw_rectangle(surface, Signed.trunc(x), Signed.trunc(y), Signed.trunc(width), Signed.trunc(height), color)

def Surface.draw_rectangle_rec(surface: Surface, rect: Rectangle, color: U32) -> Surface:
  Rectangle{x, y, width, height} = rect
  Surface.draw_rectangle(surface, x, y, width, height, color)

def Surface.draw_rectangle_lines(surface: Surface, rect: Rectangle, +thickness: U32, +color: U32) -> Surface:
  Rectangle{+x, +y, +width, +height} = rect
  +t = U32.to_f32(thickness)
  s0 = Surface.draw_rectangle(surface, Signed.trunc(x), Signed.trunc(y), Signed.trunc(width), t, color)
  s1 = Surface.draw_rectangle(s0, Signed.trunc(x), Signed.trunc((y + t : F32)), t, Signed.trunc((height - t * 2.0 : F32)), color)
  s2 = Surface.draw_rectangle(s1, Signed.trunc((x + width - t : F32)), Signed.trunc((y + t : F32)), t, Signed.trunc((height - t * 2.0 : F32)), color)
  Surface.draw_rectangle(s2, Signed.trunc(x), Signed.trunc((y + height - t : F32)), Signed.trunc(width), t, color)

def Surface.circle.plot(outline: Bool, +cx: F32, +cy: F32, +x: F32, +y: F32, +color: U32, surface: Surface) -> Surface:
  match outline:
    case False{}:
      s0 = Surface.draw_rectangle(surface, (cx - x : F32), (cy + y : F32), (x * 2.0 : F32), 1.0, color)
      s1 = Surface.draw_rectangle(s0, (cx - x : F32), (cy - y : F32), (x * 2.0 : F32), 1.0, color)
      s2 = Surface.draw_rectangle(s1, (cx - y : F32), (cy + x : F32), (y * 2.0 : F32), 1.0, color)
      Surface.draw_rectangle(s2, (cx - y : F32), (cy - x : F32), (y * 2.0 : F32), 1.0, color)
    case True{}:
      s0 = Surface.draw_pixel(surface, (cx + x : F32), (cy + y : F32), color)
      s1 = Surface.draw_pixel(s0, (cx - x : F32), (cy + y : F32), color)
      s2 = Surface.draw_pixel(s1, (cx + x : F32), (cy - y : F32), color)
      s3 = Surface.draw_pixel(s2, (cx - x : F32), (cy - y : F32), color)
      s4 = Surface.draw_pixel(s3, (cx + y : F32), (cy + x : F32), color)
      s5 = Surface.draw_pixel(s4, (cx - y : F32), (cy + x : F32), color)
      s6 = Surface.draw_pixel(s5, (cx + y : F32), (cy - x : F32), color)
      Surface.draw_pixel(s6, (cx - y : F32), (cy - x : F32), color)

def Surface.circle.loop(fuel: Nat, on: Bool, +outline: Bool, +cx: F32, +cy: F32, +x: F32, +y: F32, +error: F32, +color: U32, surface: Surface) -> Surface:
  match fuel on:
    case 0n _:
      surface
    case 1n+k False{}:
      surface
    case 1n+k True{}:
      drawn = Surface.circle.plot(outline, cx, cy, x, y, color, surface)
      +nx = (x + 1.0 : F32)
      +down = (error > 0.0 : F32)
      +ny = Bool.pick(F32, down, (y - 1.0 : F32), y)
      ne = Bool.pick(F32, down, (error + 4.0 * (nx - ny) + 10.0 : F32), (error + 4.0 * nx + 6.0 : F32))
      Surface.circle.loop(k, (ny >= nx : F32), outline, cx, cy, nx, ny, ne, color, drawn)

# Midpoint scanlines match raylib ImageDrawCircle, including its edge coverage.
def Surface.draw_circle(surface: Surface, cx: F32, cy: F32, +radius: U32, color: U32) -> Surface:
  +r = U32.to_f32(radius)
  Surface.circle.loop(1n+U32.to_nat(radius), True{}, False{}, cx, cy, 0.0, r, (3.0 - 2.0 * r : F32), color, surface)

def Surface.draw_circle_v(surface: Surface, center: Vector2, radius: U32, color: U32) -> Surface:
  Vector2{x, y} = center
  Surface.draw_circle(surface, Signed.trunc(x), Signed.trunc(y), radius, color)

def Surface.draw_circle_lines(surface: Surface, cx: F32, cy: F32, +radius: U32, color: U32) -> Surface:
  +r = U32.to_f32(radius)
  Surface.circle.loop(1n+U32.to_nat(radius), True{}, True{}, cx, cy, 0.0, r, (3.0 - 2.0 * r : F32), color, surface)

def Surface.draw_circle_lines_v(surface: Surface, center: Vector2, radius: U32, color: U32) -> Surface:
  Vector2{x, y} = center
  Surface.draw_circle_lines(surface, Signed.trunc(x), Signed.trunc(y), radius, color)

def Surface.line.loop(n: Nat, +vertical: Bool, +x: F32, +y: F32, +direction: F32, +major: F32, +minor: U32, +step: U32, +color: U32, surface: Surface) -> Surface:
  match n:
    case 0n:
      surface
    case 1n+k:
      +offset = Signed.high16(minor)
      px = (x + Bool.pick(F32, vertical, offset, major) : F32)
      py = (y + Bool.pick(F32, vertical, major, offset) : F32)
      Surface.line.loop(k, vertical, x, y, direction, (major + direction : F32),
        (minor + step : U32), step, color, Surface.draw_pixel(surface, px, py, color))

# The 16.16 short-axis accumulator and excluded final endpoint match ImageDrawLine.
def Surface.draw_line(surface: Surface, +x0: F32, +y0: F32, x1: F32, y1: F32, color: U32) -> Surface:
  +dx = (x1 - x0 : F32)
  +dy = (y1 - y0 : F32)
  +vertical = (F32.abs(dy) > F32.abs(dx) : F32)
  +long = Bool.pick(F32, vertical, dy, dx)
  +short = Bool.pick(F32, vertical, dx, dy)
  +count = F32.to_u32(F32.abs(long))
  +magnitude = ((F32.to_u32(F32.abs(short)) << 16n) / U32.max(1, count) : U32)
  step = Bool.pick(U32, (short < 0.0 : F32), (0 - magnitude : U32), magnitude)
  Surface.line.loop(U32.to_nat(count), vertical, x0, y0,
    Bool.pick(F32, (long < 0.0 : F32), (0.0 - 1.0 : F32), 1.0), 0.0, 0, step, color, surface)

def Surface.draw_line_v(surface: Surface, start: Vector2, end: Vector2, color: U32) -> Surface:
  Vector2{x0, y0} = start
  Vector2{x1, y1} = end
  Surface.draw_line(surface, Signed.trunc((x0 + 0.5 : F32)), Signed.trunc((y0 + 0.5 : F32)),
    Signed.trunc((x1 + 0.5 : F32)), Signed.trunc((y1 + 0.5 : F32)), color)

def Surface.thick_line.loop(n: Nat, +horizontal: Bool, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +offset: F32, +step: F32, +color: U32, surface: Surface) -> Surface:
  match n:
    case 0n: surface
    case 1n+k:
      +ox = Bool.pick(F32, horizontal, 0.0, offset)
      +oy = Bool.pick(F32, horizontal, offset, 0.0)
      Surface.thick_line.loop(k, horizontal, x0, y0, x1, y1, (offset + step : F32), step, color,
        Surface.draw_line(surface, (x0 + ox : F32), (y0 + oy : F32), (x1 + ox : F32), (y1 + oy : F32), color))

def Surface.draw_line_ex(surface: Surface, start: Vector2, end: Vector2, +thickness: U32, +color: U32) -> Surface:
  Vector2{x0, y0} = start
  Vector2{x1, y1} = end
  +ax = Signed.trunc((x0 + 0.5 : F32))
  +ay = Signed.trunc((y0 + 0.5 : F32))
  +bx = Signed.trunc((x1 + 0.5 : F32))
  +by = Signed.trunc((y1 + 0.5 : F32))
  +horizontal = (F32.abs((by - ay : F32)) < F32.abs((bx - ax : F32)) : F32)
  lower = Surface.thick_line.loop(U32.to_nat((thickness / 2 + 1 : U32)), horizontal, ax, ay, bx, by, 0.0, 1.0, color, surface)
  Surface.thick_line.loop(U32.to_nat(((U32.max(1, thickness) - 1) / 2 : U32)), horizontal, ax, ay, bx, by, (0.0 - 1.0 : F32), (0.0 - 1.0 : F32), color, lower)

type Raster.Edge is Data:
  Edge{value: U32, dx: U32, dy: U32}

type Raster.Paint is Data:
  FlatPaint{color: U32}
  VertexPaint{first: U32, second: U32, third: U32, inverse: F32}

def Raster.paint(paint: Raster.Paint, a: U32, b: U32, c: U32) -> U32:
  match paint:
    case FlatPaint{color}: color
    case VertexPaint{+first, +second, +third, +inverse}:
      +wa = F32.to_u32((U32.to_f32(a) * inverse : F32))
      +wb = F32.to_u32((U32.to_f32(b) * inverse : F32))
      +wc = F32.to_u32((U32.to_f32(c) * inverse : F32))
      Color.rgba(((Color.red(first) * wa + Color.red(second) * wb + Color.red(third) * wc) / 255 : U32),
        ((Color.green(first) * wa + Color.green(second) * wb + Color.green(third) * wc) / 255 : U32),
        ((Color.blue(first) * wa + Color.blue(second) * wb + Color.blue(third) * wc) / 255 : U32),
        ((Color.alpha(first) * wa + Color.alpha(second) * wb + Color.alpha(third) * wc) / 255 : U32))

def Raster.inverse(a: Raster.Edge, b: Raster.Edge, c: Raster.Edge) -> F32:
  Edge{av, _, _} = a
  Edge{bv, _, _} = b
  Edge{cv, _, _} = c
  (255.0 / Signed.to_f32((av + bv + cv : U32)) : F32)

def Raster.edge(x: F32, y: F32, vx: F32, vy: F32, +dx: F32, +dy: F32) -> Raster.Edge:
  Edge{Signed.word(((x - vx) * dx + dy * (y - vy) : F32)), Signed.word(dx), Signed.word(dy)}

def Surface.triangle.pixel(inside: Bool, pixels: Array<U32>, at: U32, paint: Raster.Paint, a: U32, b: U32, c: U32) -> Array<U32>:
  match inside:
    case False{}:
      pixels
    case True{}:
      Array.set(U32, pixels, at, Raster.paint(paint, a, b, c))

def Surface.triangle.row(n: Nat, +at: U32, +a: U32, +b: U32, +c: U32, +ax: U32, +bx: U32, +cx: U32, +paint: Raster.Paint, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      pixels
    case 1n+k:
      inside = U32.is_eq(((a .|. b .|. c) .&. 2147483648 : U32), 0)
      Surface.triangle.row(k, (at + 1 : U32), (a + ax : U32), (b + bx : U32), (c + cx : U32),
        ax, bx, cx, paint, Surface.triangle.pixel(inside, pixels, at, paint, a, b, c))

def Surface.triangle.rows(n: Nat, +at: U32, +stride: U32, +cols: Nat, ea: Raster.Edge, eb: Raster.Edge, ec: Raster.Edge, +paint: Raster.Paint, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      pixels
    case 1n+k:
      Edge{+a, +ax, +ay} = ea
      Edge{+b, +bx, +by} = eb
      Edge{+c, +cx, +cy} = ec
      Surface.triangle.rows(k, (at + stride : U32), stride, cols,
        Edge{(a + ay : U32), ax, ay}, Edge{(b + by : U32), bx, by}, Edge{(c + cy : U32), cx, cy}, paint,
        Surface.triangle.row(cols, at, a, b, c, ax, bx, cx, paint, pixels))

def Surface.triangle.fill(visible: Bool, +w: U32, h: U32, pixels: Array<U32>, +x0: F32, +y0: F32, x1: F32, y1: F32, a: Raster.Edge, b: Raster.Edge, c: Raster.Edge, paint: Raster.Paint) -> Surface:
  match visible:
    case False{}:
      Surface{w, h, pixels}
    case True{}:
      cols = U32.to_nat(F32.to_u32((x1 - x0 + 1.0 : F32)))
      rows = U32.to_nat(F32.to_u32((y1 - y0 + 1.0 : F32)))
      Surface{w, h, Surface.triangle.rows(rows, (F32.to_u32(y0) * w + F32.to_u32(x0) : U32), w,
        cols, a, b, c, paint, pixels)}

def Surface.draw_triangle(surface: Surface, v1: Vector2, v2: Vector2, v3: Vector2, color: U32) -> Surface:
  Surface{+w, +h, pixels} = surface
  Vector2{+ax, +ay} = v1
  Vector2{+bx, +by} = v2
  Vector2{+cx, +cy} = v3
  +x0 = F32.max(0.0, F32.min(ax, F32.min(bx, cx)))
  +y0 = F32.max(0.0, F32.min(ay, F32.min(by, cy)))
  +x1 = F32.min(U32.to_f32((w - 1 : U32)), F32.max(ax, F32.max(bx, cx)))
  +y1 = F32.min(U32.to_f32((h - 1 : U32)), F32.max(ay, F32.max(by, cy)))
  +sign = Bool.pick(F32, ((bx - ax) * (cy - ay) - (cx - ax) * (by - ay) > 0.0 : F32), (0.0 - 1.0 : F32), 1.0)
  Surface.triangle.fill(((x0 <= x1) && (y0 <= y1) : F32), w, h, pixels, x0, y0, x1, y1,
    Raster.edge(x0, y0, bx, by, ((cy - by) * sign : F32), ((bx - cx) * sign : F32)),
    Raster.edge(x0, y0, cx, cy, ((ay - cy) * sign : F32), ((cx - ax) * sign : F32)),
    Raster.edge(x0, y0, ax, ay, ((by - ay) * sign : F32), ((ax - bx) * sign : F32)), FlatPaint{color})

def Surface.draw_triangle_ex(surface: Surface, v1: Vector2, v2: Vector2, v3: Vector2, c1: U32, c2: U32, c3: U32) -> Surface:
  Surface{+w, +h, pixels} = surface
  Vector2{+ax, +ay} = v1
  Vector2{+bx, +by} = v2
  Vector2{+cx, +cy} = v3
  +x0 = F32.max(0.0, F32.min(ax, F32.min(bx, cx)))
  +y0 = F32.max(0.0, F32.min(ay, F32.min(by, cy)))
  +x1 = F32.min(U32.to_f32((w - 1 : U32)), F32.max(ax, F32.max(bx, cx)))
  +y1 = F32.min(U32.to_f32((h - 1 : U32)), F32.max(ay, F32.max(by, cy)))
  +sign = Bool.pick(F32, ((bx - ax) * (cy - ay) - (cx - ax) * (by - ay) > 0.0 : F32), (0.0 - 1.0 : F32), 1.0)
  +ea = Raster.edge(x0, y0, bx, by, ((cy - by) * sign : F32), ((bx - cx) * sign : F32))
  +eb = Raster.edge(x0, y0, cx, cy, ((ay - cy) * sign : F32), ((cx - ax) * sign : F32))
  +ec = Raster.edge(x0, y0, ax, ay, ((by - ay) * sign : F32), ((ax - bx) * sign : F32))
  Surface.triangle.fill(((x0 <= x1) && (y0 <= y1) : F32), w, h, pixels, x0, y0, x1, y1, ea, eb, ec,
    VertexPaint{c1, c2, c3, Raster.inverse(ea, eb, ec)})

def Surface.draw_triangle_lines(surface: Surface, v1: Vector2, v2: Vector2, v3: Vector2, +color: U32) -> Surface:
  Vector2{ax, ay} = v1
  Vector2{bx, by} = v2
  Vector2{cx, cy} = v3
  +x0 = Signed.trunc(ax)
  +y0 = Signed.trunc(ay)
  +x1 = Signed.trunc(bx)
  +y1 = Signed.trunc(by)
  +x2 = Signed.trunc(cx)
  +y2 = Signed.trunc(cy)
  a = Surface.draw_line(surface, x0, y0, x1, y1, color)
  b = Surface.draw_line(a, x1, y1, x2, y2, color)
  Surface.draw_line(b, x2, y2, x0, y0, color)

def Surface.fan.loop(points: +List<Vector2>, +center: Vector2, previous: Vector2, +color: U32, surface: Surface) -> Surface:
  match points:
    case Nil{}: surface
    case Con{+next, rest}:
      Surface.fan.loop(rest, center, next, color, Surface.draw_triangle(surface, center, previous, next, color))

def Surface.fan.start(points: +List<Vector2>, center: Vector2, color: U32, surface: Surface) -> Surface:
  match points:
    case Nil{}: surface
    case Con{previous, rest}: Surface.fan.loop(rest, center, previous, color, surface)

def Surface.draw_triangle_fan(surface: Surface, points: +List<Vector2>, color: U32) -> Surface:
  match points:
    case Nil{}: surface
    case Con{center, rest}: Surface.fan.start(rest, center, color, surface)

def Surface.strip.loop(points: +List<Vector2>, +older: Vector2, +previous: Vector2, +even: Bool, +color: U32, surface: Surface) -> Surface:
  match points:
    case Nil{}: surface
    case Con{+next, rest}:
      Surface.strip.loop(rest, previous, next, Bool.not(even), color,
        Surface.draw_triangle(surface, next, Bool.pick(Vector2, even, older, previous), Bool.pick(Vector2, even, previous, older), color))

def Surface.strip.start(points: +List<Vector2>, older: Vector2, color: U32, surface: Surface) -> Surface:
  match points:
    case Nil{}: surface
    case Con{previous, rest}: Surface.strip.loop(rest, older, previous, True{}, color, surface)

def Surface.draw_triangle_strip(surface: Surface, points: +List<Vector2>, color: U32) -> Surface:
  match points:
    case Nil{}: surface
    case Con{older, rest}: Surface.strip.start(rest, older, color, surface)

def Surface.blit.pixel(source: Array<U32> & U32, destination: Array<U32> & U32, at: U32, tint: U32) -> Array<U32> & Array<U32>:
  (src, sc) = source
  (dst, dc) = destination
  (src, Array.set(U32, dst, at, Color.alpha_blend(dc, sc, tint)))

def Surface.blit.row(n: Nat, +si: U32, +di: U32, +tint: U32, buffers: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n:
    case 0n:
      buffers
    case 1n+k:
      (src, dst) = buffers
      Surface.blit.row(k, (si + 1 : U32), (di + 1 : U32), tint,
        Surface.blit.pixel(Array.get(U32, src, si), Array.get(U32, dst, di), di, tint))

def Surface.blit.rows(n: Nat, +cols: Nat, +si: U32, +di: U32, +sw: U32, +dw: U32, +tint: U32, buffers: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n:
    case 0n:
      buffers
    case 1n+k:
      Surface.blit.rows(k, cols, (si + sw : U32), (di + dw : U32), sw, dw, tint,
        Surface.blit.row(cols, si, di, tint, buffers))

def Surface.blit.finish(dw: U32, dh: U32, sw: U32, sh: U32, buffers: Array<U32> & Array<U32>) -> Surface & Surface:
  (src, dst) = buffers
  (Surface{dw, dh, dst}, Surface{sw, sh, src})

type Raster.Mapping is Data:
  Region{stride: U32, columns: U32, x: U32, y: U32}
  Nearest{stride: U32, columns: U32, xr: U32, yr: U32}
  QuarterTurn{width: U32, height: U32, clockwise: Bool}

def Raster.index(mapping: Raster.Mapping, +i: U32) -> U32:
  match mapping:
    case Region{stride, +columns, x, y}:
      ((y + i / columns) * stride + x + i % columns : U32)
    case Nearest{stride, +columns, xr, yr}:
      ((((i / columns) * yr) >> 16n) * stride + (((i % columns) * xr) >> 16n) : U32)
    case QuarterTurn{+width, +height, clockwise}:
      Bool.pick(U32, clockwise, ((height - 1 - i % height) * width + i / height : U32),
        ((i % height) * width + width - 1 - i / height : U32))

def Surface.sample.loop(more: Nat, +i: U32, +mapping: Raster.Mapping, output: Array<U32>, got: Array<U32> & U32) -> Array<U32> & Array<U32>:
  match more got:
    case 0n Tuple{source, color}:
      (source, Array.set(U32, output, i, color))
    case 1n+k Tuple{source, color}:
      +next = (i + 1 : U32)
      Surface.sample.loop(k, next, mapping, Array.set(U32, output, i, color),
        Array.get(U32, source, Raster.index(mapping, next)))

def Surface.sample(+count: U32, +mapping: Raster.Mapping, source: Array<U32>) -> Array<U32> & Array<U32>:
  Surface.sample.loop(U32.to_nat((count - 1 : U32)), 0, mapping,
    Array.new(U32, Surface.capacity(count), 0), Array.get(U32, source, Raster.index(mapping, 0)))

type Raster.AlphaBounds is Data:
  AlphaBounds{left: U32, top: U32, right: U32, bottom: U32}

def Surface.border.expand(selected: Bool, +x: U32, +y: U32, bounds: Raster.AlphaBounds) -> Raster.AlphaBounds:
  match selected:
    case False{}: bounds
    case True{}:
      AlphaBounds{left, top, right, bottom} = bounds
      AlphaBounds{U32.min(left, x), U32.min(top, y), U32.max(right, x), U32.max(bottom, y)}

def Surface.border.pixel(+i: U32, +width: U32, threshold: U32, bounds: Raster.AlphaBounds, got: Array<U32> & U32) -> Array<U32> & Raster.AlphaBounds:
  (pixels, color) = got
  (pixels, Surface.border.expand((Color.alpha(color) > threshold : U32), (i % width : U32), (i / width : U32), bounds))

def Surface.border.scan(n: Nat, +i: U32, +width: U32, +threshold: U32, state: Array<U32> & Raster.AlphaBounds) -> Array<U32> & Raster.AlphaBounds:
  match n state:
    case 0n _: state
    case 1n+k Tuple{pixels, bounds}:
      Surface.border.scan(k, (i + 1 : U32), width, threshold, Surface.border.pixel(i, width, threshold, bounds, Array.get(U32, pixels, i)))

def Surface.border.finish(+width: U32, height: U32, result: Array<U32> & Raster.AlphaBounds) -> Surface & Rectangle:
  match result:
    case Tuple{pixels, AlphaBounds{+left, +top, right, bottom}}:
      (Surface{width, height, pixels}, Bool.pick(Rectangle, U32.is_eq(left, width), Rectangle{0.0, 0.0, 0.0, 0.0},
        Rectangle{U32.to_f32(left), U32.to_f32(top), U32.to_f32((right + 1 - left : U32)), U32.to_f32((bottom + 1 - top : U32))}))

def Surface.alpha_border(surface: Surface, threshold: F32) -> Surface & Rectangle:
  Surface{+width, +height, pixels} = surface
  Surface.border.finish(width, height, Surface.border.scan(U32.to_nat((width * height : U32)), 0, width,
    F32.to_u32((threshold * 255.0 : F32)), (pixels, AlphaBounds{width, height, 0, 0})))

def Surface.alpha_crop.pixels(width: U32, height: U32, buffers: Array<U32> & Array<U32>) -> Surface:
  (_, pixels) = buffers
  Surface{width, height, pixels}

def Surface.alpha_crop.route(empty: Bool, surface: Surface, rect: Rectangle) -> Surface:
  match empty:
    case True{}: surface
    case False{}:
      Surface{sw, _, pixels} = surface
      Rectangle{x, y, rw, rh} = rect
      +width = F32.to_u32(rw)
      +height = F32.to_u32(rh)
      Surface.alpha_crop.pixels(width, height, Surface.sample((width * height : U32),
        Region{sw, width, F32.to_u32(x), F32.to_u32(y)}, pixels))

def Surface.alpha_crop.observed(result: Surface & Rectangle) -> Surface:
  match result:
    case Tuple{surface, Rectangle{+x, +y, +width, +height}}:
      Surface.alpha_crop.route(F32.is_eq(width, 0.0), surface, Rectangle{x, y, width, height})

def Surface.alpha_crop(surface: Surface, threshold: F32) -> Surface:
  Surface.alpha_crop.observed(Surface.alpha_border(surface, threshold))

def Surface.rotate.result(width: U32, height: U32, buffers: Array<U32> & Array<U32>) -> Surface:
  (_, output) = buffers
  Surface{height, width, output}

def Surface.rotate(surface: Surface, clockwise: Bool) -> Surface:
  Surface{+width, +height, pixels} = surface
  Surface.rotate.result(width, height, Surface.sample((width * height : U32), QuarterTurn{width, height, clockwise}, pixels))

def Surface.rotate_cw(surface: Surface) -> Surface:
  Surface.rotate(surface, True{})

def Surface.rotate_ccw(surface: Surface) -> Surface:
  Surface.rotate(surface, False{})

def Surface.extract.finish(sw: U32, sh: U32, w: U32, h: U32, buffers: Array<U32> & Array<U32>) -> Surface & Maybe<Surface>:
  (source, region) = buffers
  (Surface{sw, sh, source}, Some{Surface{w, h, region}})

def Surface.extract.checked(valid: Bool, +sw: U32, sh: U32, pixels: Array<U32>, x: F32, y: F32, width: F32, height: F32) -> Surface & Maybe<Surface>:
  match valid:
    case False{}:
      (Surface{sw, sh, pixels}, None{})
    case True{}:
      +w = F32.to_u32(width)
      +h = F32.to_u32(height)
      Surface.extract.finish(sw, sh, w, h, Surface.sample((w * h : U32),
        Region{sw, w, F32.to_u32(x), F32.to_u32(y)}, pixels))

def Rectangle.integral(rect: Rectangle) -> Bool:
  Rectangle{+x, +y, +w, +h} = rect
  F32.is_eq(F32.floor(x), x) && F32.is_eq(F32.floor(y), y)
    && F32.is_eq(F32.floor(w), w) && F32.is_eq(F32.floor(h), h)

def Rectangle.inside(rect: Rectangle, sw: U32, sh: U32) -> Bool:
  Rectangle{+x, +y, +w, +h} = rect
  ((x >= 0.0) && (y >= 0.0) && (w >= 1.0) && (h >= 1.0)
    && (x + w <= U32.to_f32(sw)) && (y + h <= U32.to_f32(sh)) : F32)

# ImageFromImage profile: positive integral in-bounds rectangle; source retained.
def Surface.extract(surface: Surface, +rect: Rectangle) -> Surface & Maybe<Surface>:
  Surface{+w, +h, pixels} = surface
  Rectangle{x, y, rw, rh} = rect
  Surface.extract.checked(Rectangle.integral(rect) && Rectangle.inside(rect, w, h), w, h, pixels, x, y, rw, rh)

def Surface.crop.result(result: Surface & Maybe<Surface>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match result:
    case Tuple{original, None{}}:
      Fail{(original, InvalidRectangle{})}
    case Tuple{_, Some{region}}:
      Done{region}

def Surface.crop.route(integral: Bool, outside: Bool, original: Surface, rect: Rectangle) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match integral outside:
    case False{} _:
      Fail{(original, InvalidRectangle{})}
    case True{} True{}:
      Done{original}
    case True{} False{}:
      Surface.crop.result(Surface.extract(original, rect))

def Surface.crop(surface: Surface, +rect: Rectangle) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{+w, +h, pixels} = surface
  Rectangle{+x, +y, width, height} = rect
  +sx = F32.max(0.0, x)
  +sy = F32.max(0.0, y)
  cw = F32.min((width + F32.min(0.0, x) : F32), (U32.to_f32(w) - sx : F32))
  ch = F32.min((height + F32.min(0.0, y) : F32), (U32.to_f32(h) - sy : F32))
  Surface.crop.route(Rectangle.integral(rect), ((x > U32.to_f32(w)) || (y > U32.to_f32(h)) : F32),
    Surface{w, h, pixels}, Rectangle{sx, sy, cw, ch})

def Surface.resize.finish(w: U32, h: U32, buffers: Array<U32> & Array<U32>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  (old, pixels) = buffers
  Done{Surface{w, h, pixels}}

def Surface.nearest.mapping(safe: Bool, sw: U32, sh: U32, pixels: Array<U32>, +w: U32, +h: U32, xr: U32, yr: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match safe:
    case False{}:
      Fail{(Surface{sw, sh, pixels}, UnsafeNearestMapping{})}
    case True{}:
      Surface.resize.finish(w, h, Surface.sample((w * h : U32), Nearest{sw, w, xr, yr}, pixels))

def Surface.nearest.checked(valid: Bool, +sw: U32, +sh: U32, pixels: Array<U32>, +w: U32, +h: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}:
      Fail{(Surface{sw, sh, pixels}, InvalidSize{})}
    case True{}:
      +xr = (((sw << 16n) / w) + 1 : U32)
      +yr = (((sh << 16n) / h) + 1 : U32)
      last = (((((h - 1) * yr) >> 16n) * sw) + (((w - 1) * xr) >> 16n) : U32)
      Surface.nearest.mapping((last < sw * sh : U32), sw, sh, pixels, w, h, xr, yr)

# Preserve raylib's +1 fixed-point ratios. Refuse mappings beyond logical storage.
def Surface.resize_nn(surface: Surface, +w: U32, +h: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{sw, sh, pixels} = surface
  Surface.nearest.checked(((w > 0) && (h > 0) && (w <= 4096) && (h <= 4096) : U32), sw, sh, pixels, w, h)

def Surface.resize.checked(valid: Bool, surface: Surface, +w: U32, +h: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(surface, InvalidSize{})}
    case True{}:
      Surface{sw, sh, pixels} = surface
      Done{Surface{w, h, Resample.resize(sw, sh, w, h, pixels)}}

def Surface.resize(surface: Surface, +w: U32, +h: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.resize.checked(((w > 0) && (h > 0) && (w <= 4096) && (h <= 4096) : U32), surface, w, h)

def Surface.canvas.pixel(at: U32, output: Array<U32>, got: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (source, color) = got
  (source, Array.set(U32, output, at, color))

def Surface.canvas.copy(n: Nat, +i: U32, +cols: U32, +sw: U32, +dw: U32, +source_at: U32, +output_at: U32, buffers: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n buffers:
    case 0n _: buffers
    case 1n+k Tuple{source, output}:
      +x = (i % cols : U32)
      +y = (i / cols : U32)
      Surface.canvas.copy(k, (i + 1 : U32), cols, sw, dw, source_at, output_at,
        Surface.canvas.pixel((output_at + y * dw + x : U32), output, Array.get(U32, source, (source_at + y * sw + x : U32))))

def Surface.canvas.overlap(valid: Bool, +sw: U32, sh: U32, pixels: Array<U32>, +width: U32, +height: U32, sx: U32, sy: U32, dx: U32, dy: U32, +cols: U32, rows: U32, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(Surface{sw, sh, pixels}, InvalidRectangle{})}
    case True{}:
      Surface.resize.finish(width, height, Surface.canvas.copy(U32.to_nat((cols * rows : U32)), 0, cols, sw, width,
        (sy * sw + sx : U32), (dy * width + dx : U32), (pixels, Array.new(U32, Surface.capacity((width * height : U32)), fill))))

def Surface.canvas.route(same: Bool, +sw: U32, +sh: U32, pixels: Array<U32>, +width: U32, +height: U32, +x: F32, +y: F32, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match same:
    case True{}: Done{Surface{sw, sh, pixels}}
    case False{}:
      +sx = F32.max(0.0, F32.neg(x))
      +sy = F32.max(0.0, F32.neg(y))
      +dx = F32.max(0.0, x)
      +dy = F32.max(0.0, y)
      +cols = F32.max(0.0, F32.min((U32.to_f32(sw) - sx : F32), (U32.to_f32(width) - dx : F32)))
      +rows = F32.max(0.0, F32.min((U32.to_f32(sh) - sy : F32), (U32.to_f32(height) - dy : F32)))
      Surface.canvas.overlap(((cols >= 1.0) && (rows >= 1.0) : F32), sw, sh, pixels, width, height,
        F32.to_u32(sx), F32.to_u32(sy), F32.to_u32(dx), F32.to_u32(dy), F32.to_u32(cols), F32.to_u32(rows), fill)

def Surface.canvas.checked(size_ok: Bool, offsets_ok: Bool, surface: Surface, +width: U32, +height: U32, x: F32, y: F32, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match size_ok offsets_ok:
    case False{} _: Fail{(surface, InvalidSize{})}
    case True{} False{}: Fail{(surface, InvalidRectangle{})}
    case True{} True{}:
      Surface{+sw, +sh, pixels} = surface
      Surface.canvas.route(U32.is_eq(sw, width) && U32.is_eq(sh, height), sw, sh, pixels, width, height, x, y, fill)

def Surface.resize_canvas(surface: Surface, +width: U32, +height: U32, +x: F32, +y: F32, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.canvas.checked(((width >= 1) && (height >= 1) && (width <= 4096) && (height <= 4096) : U32),
    ((F32.abs(x) <= 32767.0) && (F32.abs(y) <= 32767.0) : F32)
      && F32.is_eq(F32.floor(x), x) && F32.is_eq(F32.floor(y), y), surface, width, height, x, y, fill)

def Surface.to_pot(surface: Surface, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{+width, +height, pixels} = surface
  Surface.resize_canvas(Surface{width, height, pixels}, U32.shln(1, Surface.capacity(width)), U32.shln(1, Surface.capacity(height)), 0.0, 0.0, fill)

def Surface.rotation.sized(valid: Bool, surface: Surface, +width: U32, +height: U32, cosine: F32, sine: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(surface, InvalidSize{})}
    case True{}:
      Surface{sw, sh, pixels} = surface
      Done{Surface{width, height, Rotation.render(sw, sh, width, height, cosine, sine, pixels)}}

def Surface.rotation.trigonometry(surface: Surface, values: F32 & F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{+sw, +sh, pixels} = surface
  (+cosine, +sine) = values
  +width = F32.to_u32((F32.abs((U32.to_f32(sw) * cosine : F32)) + F32.abs((U32.to_f32(sh) * sine : F32)) : F32))
  +height = F32.to_u32((F32.abs((U32.to_f32(sh) * cosine : F32)) + F32.abs((U32.to_f32(sw) * sine : F32)) : F32))
  Surface.rotation.sized(((width >= 1) && (height >= 1) && (width <= 4096) && (height <= 4096) : U32),
    Surface{sw, sh, pixels}, width, height, cosine, sine)

def Surface.rotation.checked(valid: Bool, reference: Gradient.Reference, surface: Surface, degrees: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(surface, InvalidRectangle{})}
    case True{}:
      radians = (degrees * 3.14159265358979323846 / 180.0 : F32)
      Surface.rotation.trigonometry(surface, Trig.sincos_for(Gradient.gnu(reference), radians))

def Surface.rotate_degrees_for(reference: Gradient.Reference, surface: Surface, +degrees: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.rotation.checked((F32.abs(degrees) <= 360.0 : F32) && F32.is_eq(F32.floor(degrees), degrees), reference, surface, degrees)

def Surface.rotate_degrees(surface: Surface, degrees: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.rotate_degrees_for(AccurateGradient{}, surface, degrees)

def Surface.blit.region(destination: Surface, source: Surface, rect: Rectangle, +x: F32, +y: F32, tint: U32) -> Surface & Surface:
  Surface{+dw, +dh, dst} = destination
  Surface{+sw, +sh, src} = source
  Rectangle{rx, ry, rw, rh} = rect
  +skipx = F32.max(0.0, (0.0 - x : F32))
  +skipy = F32.max(0.0, (0.0 - y : F32))
  +dx = F32.max(0.0, x)
  +dy = F32.max(0.0, y)
  cols = F32.to_u32(F32.max(0.0, F32.min((rw - skipx : F32), (U32.to_f32(dw) - dx : F32))))
  rows = F32.to_u32(F32.max(0.0, F32.min((rh - skipy : F32), (U32.to_f32(dh) - dy : F32))))
  Surface.blit.finish(dw, dh, sw, sh, Surface.blit.rows(U32.to_nat(rows), U32.to_nat(cols),
    (F32.to_u32((ry + skipy : F32)) * sw + F32.to_u32((rx + skipx : F32)) : U32),
    (F32.to_u32(dy) * dw + F32.to_u32(dx) : U32), sw, dw, tint, (src, dst)))

def Surface.region.checked(valid: Bool, destination: Surface, source: Surface, rect: Rectangle, x: F32, y: F32, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match valid:
    case False{}:
      Fail{((destination, source), InvalidRectangle{})}
    case True{}:
      Done{Surface.blit.region(destination, source, rect, x, y, tint)}

def Surface.draw_image_region(destination: Surface, source: Surface, +rect: Rectangle, +x: F32, +y: F32, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  Surface{+w, +h, pixels} = source
  Surface.region.checked(Rectangle.integral(rect) && Rectangle.inside(rect, w, h)
    && F32.is_eq(F32.floor(x), x) && F32.is_eq(F32.floor(y), y), destination, Surface{w, h, pixels}, rect, x, y, tint)

# Initial ImageDraw profile: full source, equal-size destination rectangle,
# RGBA8, one mip level. Both image owners are returned, destination first.
def Surface.draw_image(destination: Surface, source: Surface, +x: F32, +y: F32, tint: U32) -> Surface & Surface:
  Surface{+w, +h, pixels} = source
  Surface.blit.region(destination, Surface{w, h, pixels}, Rectangle{0.0, 0.0, U32.to_f32(w), U32.to_f32(h)}, x, y, tint)

def Surface.image_rect.finish(original: Surface, drawn: Surface & Surface) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  (destination, _) = drawn
  Done{(destination, original)}

def Surface.image_rect.resized(destination: Surface, original: Surface, x: F32, y: F32, tint: U32, resized: Result<&1, &1, Surface & Surface.Error, Surface>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match resized:
    case Fail{Tuple{_, error}}: Fail{((destination, original), error)}
    case Done{scaled}: Surface.image_rect.finish(original, Surface.draw_image(destination, scaled, x, y, tint))

def Surface.image_rect.extracted(destination: Surface, x: F32, y: F32, width: U32, height: U32, tint: U32, extracted: Surface & Maybe<Surface>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match extracted:
    case Tuple{source, None{}}: Fail{((destination, source), InvalidRectangle{})}
    case Tuple{source, Some{region}}:
      Surface.image_rect.resized(destination, source, x, y, tint, Surface.resize(region, width, height))

def Surface.image_rect.extract(source: Surface, rect: Rectangle) -> Surface & Maybe<Surface>:
  Surface{w, h, pixels} = source
  Rectangle{x, y, width, height} = rect
  Surface.extract.checked(True{}, w, h, pixels, x, y, width, height)

def Surface.image_rect.route(scaled: Bool, destination: Surface, source: Surface, rect: Rectangle, x: F32, y: F32, width: U32, height: U32, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match scaled:
    case False{}: Done{Surface.blit.region(destination, source, rect, x, y, tint)}
    case True{}: Surface.image_rect.extracted(destination, x, y, width, height, tint, Surface.image_rect.extract(source, rect))

def Surface.image_rect.checked(valid: Bool, destination: Surface, source: Surface, +rect: Rectangle, target: Rectangle, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match valid:
    case False{}: Fail{((destination, source), InvalidRectangle{})}
    case True{}:
      Rectangle{_, _, rw, rh} = rect
      Rectangle{x, y, +width, +height} = target
      Surface.image_rect.route((F32.is_ne(F32.floor(rw), F32.floor(width)) || F32.is_ne(F32.floor(rh), F32.floor(height))), destination, source, rect, x, y,
        F32.to_u32(width), F32.to_u32(height), tint)

def Rectangle.bounded(rect: Rectangle) -> Bool:
  Rectangle{x, y, w, h} = rect
  ((F32.abs(x) <= 32767.0) && (F32.abs(y) <= 32767.0) && (F32.abs(w) <= 32767.0) && (F32.abs(h) <= 32767.0) : F32)

def Surface.draw_image_rect(destination: Surface, source: Surface, +rect: Rectangle, +target: Rectangle, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  Surface{+sw, +sh, pixels} = source
  Rectangle{+x, +y, width, height} = rect
  Rectangle{_, _, +tw, +th} = target
  +sx = F32.max(0.0, x)
  +sy = F32.max(0.0, y)
  +cw = F32.min((width + F32.min(0.0, x) : F32), (U32.to_f32(sw) - sx : F32))
  +ch = F32.min((height + F32.min(0.0, y) : F32), (U32.to_f32(sh) - sy : F32))
  Surface.image_rect.checked(Rectangle.bounded(rect) && Rectangle.bounded(target)
    && ((cw >= 1.0) && (ch >= 1.0) && (tw >= 1.0) && (th >= 1.0) && (F32.floor(tw) <= 4096.0) && (F32.floor(th) <= 4096.0) : F32),
    destination, Surface{sw, sh, pixels}, Rectangle{sx, sy, cw, ch}, target, tint)

# Export consumes the surface and excludes power-of-two storage padding.
def Surface.colors(surface: Surface) -> List<U32>:
  Surface{w, h, pixels} = surface
  List.take(&1, U32, Array.to_list(~U32, pixels), U32.to_nat((w * h : U32)))

def Surface.copy.result(+w: U32, +h: U32, pair: Array<U32> & Array<U32>) -> Surface & Surface:
  (a, b) = pair
  (Surface{w, h, a}, Surface{w, h, b})

def Surface.copy(surface: Surface) -> Surface & Surface:
  Surface{w, h, pixels} = surface
  Surface.copy.result(w, h, Array.clone(U32, pixels))

def Surface.channel.copied(pair: Surface & Surface, selected: F32) -> Surface & Surface:
  (source, copy) = pair
  shift = U32.to_nat((24 - 8 * F32.to_u32(F32.clamp(selected, 0.0, 3.0)) : U32))
  (source, Surface.color.transform(copy, ImageChannel{shift}))

def Surface.from_channel(surface: Surface, selected: F32) -> Surface & Surface:
  Surface.channel.copied(Surface.copy(surface), selected)

def Surface.flip.index(horizontal: Bool, +i: U32, +w: U32, h: U32) -> U32:
  +x = (i % w : U32)
  +y = (i / w : U32)
  Bool.pick(U32, horizontal, (y * w + w - 1 - x : U32), ((h - 1 - y) * w + x : U32))

def Surface.flip.loop(more: Nat, +i: U32, +w: U32, +h: U32, +horizontal: Bool, output: Array<U32>, got: Array<U32> & U32) -> Array<U32>:
  match more got:
    case 0n Tuple{_, color}:
      Array.set(U32, output, i, color)
    case 1n+k Tuple{source, color}:
      +next = (i + 1 : U32)
      Surface.flip.loop(k, next, w, h, horizontal, Array.set(U32, output, i, color),
        Array.get(U32, source, Surface.flip.index(horizontal, next, w, h)))

def Surface.flip(surface: Surface, +horizontal: Bool) -> Surface:
  Surface{+w, +h, pixels} = surface
  +count = (w * h : U32)
  Surface{w, h, Surface.flip.loop(U32.to_nat((count - 1 : U32)), 0, w, h, horizontal,
    Array.new(U32, Surface.capacity(count), 0),
    Array.get(U32, pixels, Surface.flip.index(horizontal, 0, w, h)))}

def Surface.flip_horizontal(surface: Surface) -> Surface:
  Surface.flip(surface, True{})

def Surface.flip_vertical(surface: Surface) -> Surface:
  Surface.flip(surface, False{})

# Base.Image contains RGB colors. Alpha is discarded, not composited.
def Surface.tree.leaf(got: Array<U32> & U32) -> Array<U32> & Image:
  (pixels, color) = got
  (pixels, Pix{(color >> 8n : U32)})

def Surface.tree.pixel(inside: Bool, +w: U32, x: U32, y: U32, pixels: Array<U32>) -> Array<U32> & Image:
  match inside:
    case False{}:
      (pixels, Pix{0})
    case True{}:
      Surface.tree.leaf(Array.get(U32, pixels, (y * w + x : U32)))

def Surface.tree.bind(got: Array<U32> & Image, next: Array<U32> -> Image -> (Array<U32> & Image)) -> Array<U32> & Image:
  (pixels, image) = got
  next(pixels, image)

def Surface.tree(+depth: Nat, +size: U32, +x: U32, +y: U32, +w: U32, +h: U32, pixels: Array<U32>) -> Array<U32> & Image:
  match depth:
    case 0n:
      Surface.tree.pixel(((x < w) && (y < h) : U32), w, x, y, pixels)
    case 1n+k:
      +half = (size / 2 : U32)
      Surface.tree.bind(Surface.tree(k, half, x, y, w, h, pixels), p0 => tl =>
        Surface.tree.bind(Surface.tree(k, half, (x + half : U32), y, w, h, p0), p1 => tr =>
          Surface.tree.bind(Surface.tree(k, half, x, (y + half : U32), w, h, p1), p2 => bl =>
            Surface.tree.bind(Surface.tree(k, half, (x + half : U32), (y + half : U32), w, h, p2), p3 => br =>
              (p3, Qua{tl, tr, bl, br})))))

def Surface.to_image(surface: Surface) -> Image:
  Surface{+w, +h, pixels} = surface
  +depth = Surface.capacity(U32.max(w, h))
  Pair.snd(Array<U32>, Image, Surface.tree(depth, U32.shln(1, depth), 0, 0, w, h, pixels))

# Portable, inspectable P3 PPM output for headless programs. Alpha is discarded.
def Surface.ppm.colors(colors: List<U32>) -> String:
  match colors:
    case Nil{}:
      ""
    case Con{+color, rest}:
      U32.show(Color.red(color)) ++ " " ++ U32.show(Color.green(color)) ++ " "
        ++ U32.show(Color.blue(color)) ++ "\n" ++ Surface.ppm.colors(rest)

def Surface.to_ppm(surface: Surface) -> String:
  Surface{+w, +h, pixels} = surface
  "P3\n" ++ U32.show(w) ++ " " ++ U32.show(h) ++ "\n255\n"
    ++ Surface.ppm.colors(Surface.colors(Surface{w, h, pixels}))

def Surface.ppm.written(result: File & Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, U32 & String, Unit>):
  (file, status) = result
  do IO<Result<&1, &1, U32 & String, Unit>>:
    Unit <- File.close(file)
    IO.pure(Result<&1, &1, U32 & String, Unit>, status)

def Surface.ppm.opened(text: String, opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Result<&1, &1, U32 & String, Unit>,
        File.write(file, text), Surface.ppm.written)

def Surface.write_ppm(surface: Surface, path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>,
    File.open(path, "w"), Surface.ppm.opened(Surface.to_ppm(surface)))

def Surface.qoi.opened(bytes: +List<U32>, opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}: IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Result<&1, &1, U32 & String, Unit>,
        File.write_bytes(file, bytes), Surface.ppm.written)

def Surface.write_qoi(surface: Surface, path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>,
    File.open(path, "w"), Surface.qoi.opened(Surface.to_qoi(surface)))

def Surface.load_qoi.decoded(result: Result<&1, &1, Image.DecodeError, Surface>) -> Result<&1, &1, Image.LoadError, Surface>:
  match result:
    case Fail{error}: Fail{ImageDecodeError{error}}
    case Done{image}: Done{image}

def Surface.load_qoi.payload(result: Result<&1, &1, U32 & String, +List<U32>>) -> Result<&1, &1, Image.LoadError, Surface>:
  match result:
    case Fail{Tuple{code, message}}: Fail{ImageFileError{code, message}}
    case Done{bytes}: Surface.load_qoi.decoded(Surface.decode_qoi(bytes))

def Surface.load_qoi.read(result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Result<&1, &1, Image.LoadError, Surface>):
  (file, status) = result
  do IO<Result<&1, &1, Image.LoadError, Surface>>:
    Unit <- File.close(file)
    IO.pure(Result<&1, &1, Image.LoadError, Surface>, Surface.load_qoi.payload(status))

def Surface.load_qoi.bounded(valid: Bool, file: File, size: U32) -> IO(Result<&1, &1, Image.LoadError, Surface>):
  match valid:
    case False{}:
      do IO<Result<&1, &1, Image.LoadError, Surface>>:
        Unit <- File.close(file)
        IO.pure(Result<&1, &1, Image.LoadError, Surface>, Fail{ImageDecodeError{UnsupportedImageSize{}}})
    case True{}:
      IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Result<&1, &1, Image.LoadError, Surface>,
        File.read_bytes(file, size), Surface.load_qoi.read)

def Surface.load_qoi.sized(result: File & Result<&1, &1, U32 & String, U32>) -> IO(Result<&1, &1, Image.LoadError, Surface>):
  match result:
    case Tuple{file, Fail{error}}: Surface.load_qoi.read((file, Fail{error}))
    case Tuple{file, Done{+size}}: Surface.load_qoi.bounded((size <= 83886102 : U32), file, size)

def Surface.load_qoi.opened(opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, Image.LoadError, Surface>):
  match opened:
    case Fail{Tuple{code, message}}: IO.pure(Result<&1, &1, Image.LoadError, Surface>, Fail{ImageFileError{code, message}})
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, Result<&1, &1, Image.LoadError, Surface>, File.size(file), Surface.load_qoi.sized)

def Surface.load_qoi(path: String) -> IO(Result<&1, &1, Image.LoadError, Surface>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, Image.LoadError, Surface>, File.open(path, "r"), Surface.load_qoi.opened)
