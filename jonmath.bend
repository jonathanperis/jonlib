# Jonmath - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raymath.h from pinned raylib 6.0.
# See THIRD_PARTY_NOTICES.md and LICENSES/raylib.txt.
#
# Sections, in order (each starts with a "# ----" banner):
#   1. Shared types: vectors, matrix, binary64 words
#   2. Numerical profiles: M.Libm and M.Contraction
#   3. Scalars (Clamp, Lerp, Normalize, Remap, Wrap, FloatEquals)
#   4. Vector2
#   5. Matrices, Vector3 and Vector4
#   6. Quaternions, decomposition and projection
#   7. Operator sugar (raymath's optional C++ operators)
# raymath groups by type; Bend needs definitions before use, so later
# sections may extend an earlier type (e.g. Vector3 helpers after Matrix).
import Base
import ./src/trig.bend as Trig
import ./src/sincosf.bend as Sincosf
import ./src/inverse_trig.bend as InverseTrig
import ./src/asin.bend as Asin
import ./src/power.bend as Power
import ./src/float64.bend as Float64Numeric
import ./src/angle.bend as LegacyAngle
import ./src/checked_angle.bend as CheckedAngle
import ./src/binary64_fma.bend as Binary64Fma
import ./src/binary64_scaled.bend as Binary64Scaled
import ./src/binary64_narrow.bend as Binary64Narrow
import ./src/lgpl/tan.bend as GlibcTan
import ./src/lgpl/asin.bend as GlibcAsin

# -----------------------------------------------------------------------------
# Shared types: vectors, matrix, binary64 words

type Vector2 is Data:
  Vector2{x: F32, y: F32}

type Vector3 is Data:
  Vector3{x: F32, y: F32, z: F32}

type Vector4 is Data:
  Vector4{x: F32, y: F32, z: F32, w: F32}

type Matrix is Data:
  Matrix{m0: F32, m4: F32, m8: F32, m12: F32,
    m1: F32, m5: F32, m9: F32, m13: F32,
    m2: F32, m6: F32, m10: F32, m14: F32,
    m3: F32, m7: F32, m11: F32, m15: F32}

type Matrix.Decomposition is Data:
  Decomposed{translation: Vector3, rotation: Vector4, scale: Vector3}

type Float64 is Data:
  Float64{high: U32, low: U32}

def Float64.promoted(words: U32 & U32) -> Float64:
  (high, low) = words
  Float64{high, low}

def Float64.from_f32(value: F32) -> Float64:
  Float64.promoted(Float64Numeric.promote(value))

def Float64.to_f32.word(word: Maybe<U32>) -> Maybe<F32>:
  match word:
    case None{}: None{}
    case Some{+bits}:
      U32{b} = bits
      Some{F32{b}}

# (float)value: rounded to nearest even, with gradual underflow and overflow
# to infinity. None for infinities and NaN.
def Float64.to_f32(value: Float64) -> Maybe<F32>:
  Float64{high, low} = value
  Float64.to_f32.word(Binary64Narrow.checked(high, low))

# (int)value for |value| < 2^31: truncation toward zero, as a two's-complement
# word. None outside that range (the C conversion is undefined there, -2^31
# itself included here), for infinities and NaN.
def Float64.to_int(value: Float64) -> Maybe<U32>:
  Float64{+high, +low} = value
  Bool.pick(Maybe<U32>, (((high >> 20n) .&. 2047) < 1054 : U32), Some{Sincosf.truncate(Sincosf.Ok{high, low})}, None{})

def Float64.internal.f32(value: Float64) -> F32:
  Float64{high, low} = value
  Float64Numeric.to_f32(high, low)

def Float64.internal.difference(left: Float64, right: Float64) -> F32:
  Float64{ah, al} = left
  Float64{bh, bl} = right
  Float64Numeric.difference(ah, al, bh, bl)

# -----------------------------------------------------------------------------
# Numerical profiles: M.Libm and M.Contraction

# Which C math library a reference result depends on (sin/cos/atan2 rounding,
# fminf/fmaxf signed-zero ties). AppleLibm: macOS. Glibc239Libm: glibc before
# 2.41 (Sun atan2f). Glibc241Libm: glibc 2.41 and later. See docs/ANGLES.md.
type Libm is Data:
  AppleLibm{}
  Glibc239Libm{}
  Glibc241Libm{}

# Whether the reference build contracts a*b + c into one fused multiply-add.
type Contraction is Data:
  Uncontracted{}
  Fused{}

def Libm.gnu(libm: Libm) -> Bool:
  match libm:
    case AppleLibm{}: False{}
    case _: True{}

def Libm.angle(libm: Libm) -> U32:
  match libm:
    case AppleLibm{}: 0
    case Glibc239Libm{}: 1
    case Glibc241Libm{}: 2

def Contraction.fused(contraction: Contraction) -> Bool:
  match contraction:
    case Uncontracted{}: False{}
    case Fused{}: True{}

# -----------------------------------------------------------------------------
# Scalars (Clamp, Lerp, Normalize, Remap, Wrap, FloatEquals)

# raymath/raylib PI, DEG2RAD, RAD2DEG and EPSILON: F32 literals and F32 quotients.
def Math.PI() -> F32:
  3.14159265358979323846

def Math.DEG2RAD() -> F32:
  (3.14159265358979323846 / 180.0 : F32)

def Math.RAD2DEG() -> F32:
  (180.0 / 3.14159265358979323846 : F32)

def Math.EPSILON() -> F32:
  0.000001

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

# -----------------------------------------------------------------------------
# Vector2

def Vector2.zero() -> Vector2:
  Vector2{0.0, 0.0}

def Vector2.one() -> Vector2:
  Vector2{1.0, 1.0}

# raymath's C++ constants: Vector2Zeros/Ones are Vector2.zero/one.
def Vector2.unit_x() -> Vector2:
  Vector2{1.0, 0.0}

def Vector2.unit_y() -> Vector2:
  Vector2{0.0, 1.0}

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

# Convenience angles keep the unchecked Apple (macOS libm) behavior.
def Vector2.angle(+left: Vector2, +right: Vector2) -> F32:
  LegacyAngle.atan2(False{}, Vector2.cross_product(left, right), Vector2.dot_product(left, right))

def Vector2.line_angle(start: Vector2, end: Vector2) -> F32:
  Vector2{x, y} = start
  Vector2{u, v} = end
  F32.neg(LegacyAngle.atan2(False{}, (v - y : F32), (u - x : F32)))

# Checked angles for an explicit libm: finite components and zero-or-normal
# staged intermediates and result, otherwise None (docs/ANGLES.md).
def Vector2.angle_for(libm: Libm, left: Vector2, right: Vector2) -> Maybe<F32>:
  Vector2{x, y} = left
  Vector2{u, v} = right
  CheckedAngle.maybe(CheckedAngle.vector2(Libm.angle(libm), x, y, u, v))

def Vector2.line_angle_for(libm: Libm, start: Vector2, end: Vector2) -> Maybe<F32>:
  Vector2{x, y} = start
  Vector2{u, v} = end
  CheckedAngle.maybe(CheckedAngle.line(Libm.angle(libm), x, y, u, v))

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

def Vector2.clamp_for(reference: Libm, vector: Vector2, lower: Vector2, upper: Vector2) -> Vector2:
  Vector2{x, y} = vector
  Vector2{lx, ly} = lower
  Vector2{ux, uy} = upper
  +gnu = Libm.gnu(reference)
  Vector2{Vector2.clamp.minimum(gnu, ux, Vector2.clamp.maximum(gnu, lx, x)), Vector2.clamp.minimum(gnu, uy, Vector2.clamp.maximum(gnu, ly, y))}

def Vector2.clamp(vector: Vector2, lower: Vector2, upper: Vector2) -> Vector2:
  Vector2.clamp_for(AppleLibm{}, vector, lower, upper)

def Vector2.min_for(reference: Libm, left: Vector2, right: Vector2) -> Vector2:
  Vector2{x, y} = left
  Vector2{u, v} = right
  +gnu = Libm.gnu(reference)
  Vector2{Vector2.clamp.minimum(gnu, x, u), Vector2.clamp.minimum(gnu, y, v)}

def Vector2.max_for(reference: Libm, left: Vector2, right: Vector2) -> Vector2:
  Vector2{x, y} = left
  Vector2{u, v} = right
  +gnu = Libm.gnu(reference)
  Vector2{Vector2.clamp.maximum(gnu, x, u), Vector2.clamp.maximum(gnu, y, v)}

def Vector2.min(left: Vector2, right: Vector2) -> Vector2:
  Vector2.min_for(AppleLibm{}, left, right)

def Vector2.max(left: Vector2, right: Vector2) -> Vector2:
  Vector2.max_for(AppleLibm{}, left, right)

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

def Vector2.rotate_for(reference: Libm, vector: Vector2, angle: F32) -> Vector2:
  Vector2.rotation(vector, Trig.sincos_for(Libm.gnu(reference), angle))

def Vector2.rotate(vector: Vector2, angle: F32) -> Vector2:
  Vector2.rotate_for(AppleLibm{}, vector, angle)

# -----------------------------------------------------------------------------
# Matrices, Vector3 and Vector4

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

def Matrix.frustum(+left: Float64, +right: Float64, +bottom: Float64, +top: Float64, +near: Float64, +far: Float64) -> Matrix:
  +rl = Float64.internal.difference(right, left)
  +tb = Float64.internal.difference(top, bottom)
  +fn = Float64.internal.difference(far, near)
  lf = Float64.internal.f32(left)
  rf = Float64.internal.f32(right)
  bf = Float64.internal.f32(bottom)
  tf = Float64.internal.f32(top)
  +nf = Float64.internal.f32(near)
  +ff = Float64.internal.f32(far)
  Matrix{(nf * 2.0 / rl : F32), 0.0, ((rf + lf) / rl : F32), 0.0,
    0.0, (nf * 2.0 / tb : F32), ((tf + bf) / tb : F32), 0.0,
    0.0, 0.0, (F32.neg((ff + nf : F32)) / fn : F32), (F32.neg((ff * nf * 2.0 : F32)) / fn : F32),
    0.0, 0.0, F32.neg(1.0), 0.0}

def Matrix.ortho(+left: Float64, +right: Float64, +bottom: Float64, +top: Float64, +near: Float64, +far: Float64) -> Matrix:
  +rl = Float64.internal.difference(right, left)
  +tb = Float64.internal.difference(top, bottom)
  +fn = Float64.internal.difference(far, near)
  lf = Float64.internal.f32(left)
  rf = Float64.internal.f32(right)
  bf = Float64.internal.f32(bottom)
  tf = Float64.internal.f32(top)
  nf = Float64.internal.f32(near)
  ff = Float64.internal.f32(far)
  Matrix{(2.0 / rl : F32), 0.0, 0.0, (F32.neg((lf + rf : F32)) / rl : F32),
    0.0, (2.0 / tb : F32), 0.0, (F32.neg((tf + bf : F32)) / tb : F32),
    0.0, 0.0, (F32.neg(2.0) / fn : F32), (F32.neg((ff + nf : F32)) / fn : F32), 0.0, 0.0, 0.0, 1.0}

# -----------------------------------------------------------------------------
# Binary64 tangent and MatrixPerspective (docs/PERSPECTIVE.md)

def Float64.internal.lift(result: Maybe<Binary64Fma.Words>) -> Maybe<Float64>:
  match result:
    case None{}: None{}
    case Some{Binary64Fma.Words{high, low}}: Some{Float64{high, low}}

# a*b rounded once to binary64; None for nonfinite or subnormal operands and
# results (the exact scaled helper's domain, src/binary64_scaled.bend).
def Float64.internal.multiply(left: Float64, right: Float64) -> Maybe<Float64>:
  Float64{ah, al} = left
  Float64{bh, bl} = right
  Float64.internal.lift(Binary64Scaled.multiply(ah, al, bh, bl))

def Float64.internal.negate(value: Float64) -> Float64:
  Float64{high, low} = value
  Float64{(high .^. 2147483648 : U32), low}

def Libm.tan.words(value: Float64) -> Maybe<Float64>:
  Float64{high, low} = value
  Float64.internal.lift(GlibcTan.tan(high, low))

# tan under a reference profile. Glibc239Libm and Glibc241Libm (whose s_tan.c
# is the same source): glibc's x86_64 tan as its FMA ifunc variant runs it on
# CPUs with FMA and AVX2, through the LGPL-2.1+ module src/lgpl/tan.bend; equal
# to the native function on every argument raylib passes (exhaustive). None
# for AppleLibm (Apple's tan is unpublished), infinities and NaN.
def Libm.tan(libm: Libm, value: Float64) -> Maybe<Float64>:
  match libm:
    case AppleLibm{}: None{}
    case _: Libm.tan.words(value)

def Matrix.perspective.frustum(right: Maybe<Float64>, +top: Float64, +near: Float64, +far: Float64) -> Maybe<Matrix>:
  match right:
    case None{}: None{}
    case Some{+r}: Some{Matrix.frustum(Float64.internal.negate(r), r, Float64.internal.negate(top), top, near, far)}

def Matrix.perspective.top(top: Maybe<Float64>, +aspect: Float64, +near: Float64, +far: Float64) -> Maybe<Matrix>:
  match top:
    case None{}: None{}
    case Some{+t}: Matrix.perspective.frustum(Float64.internal.multiply(t, aspect), t, near, far)

def Matrix.perspective.tangent(tangent: Maybe<Float64>, +aspect: Float64, +near: Float64, +far: Float64) -> Maybe<Matrix>:
  match tangent:
    case None{}: None{}
    case Some{t}: Matrix.perspective.top(Float64.internal.multiply(near, t), aspect, near, far)

def Matrix.perspective.half(libm: Libm, half: Maybe<Float64>, +aspect: Float64, +near: Float64, +far: Float64) -> Maybe<Matrix>:
  match half:
    case None{}: None{}
    case Some{h}: Matrix.perspective.tangent(Libm.tan(libm, h), aspect, near, far)

# MatrixPerspective(fovY, aspect, near, far): top = near*tan(fovY*0.5) and
# right = top*aspect in binary64, then MatrixFrustum(-right, right, -top, top,
# near, far)'s cells. None where Libm.tan is None and where a binary64 product
# is not a normal number or zero.
def Matrix.perspective.glibc(libm: Libm, fovy: Float64, +aspect: Float64, +near: Float64, +far: Float64) -> Maybe<Matrix>:
  Matrix.perspective.half(libm, Float64.internal.multiply(fovy, Float64{1071644672, 0}), aspect, near, far)

def Matrix.perspective_for(libm: Libm, fovy: Float64, +aspect: Float64, +near: Float64, +far: Float64) -> Maybe<Matrix>:
  match libm:
    case AppleLibm{}: None{}
    case Glibc239Libm{}: Matrix.perspective.glibc(Glibc239Libm{}, fovy, aspect, near, far)
    case Glibc241Libm{}: Matrix.perspective.glibc(Glibc241Libm{}, fovy, aspect, near, far)

def Vector2.transform(vector: Vector2, matrix: Matrix) -> Vector2:
  Vector2{+x, +y} = vector
  Matrix{m0, m4, m8, m12, m1, m5, m9, m13, _, _, _, _, _, _, _, _} = matrix
  Vector2{(m0 * x + m4 * y + m8 * 0.0 + m12 : F32), (m1 * x + m5 * y + m9 * 0.0 + m13 : F32)}

def Vector3.zero() -> Vector3:
  Vector3{0.0, 0.0, 0.0}

def Vector3.one() -> Vector3:
  Vector3{1.0, 1.0, 1.0}

# raymath's C++ constants: Vector3Zeros/Ones are Vector3.zero/one.
def Vector3.unit_x() -> Vector3:
  Vector3{1.0, 0.0, 0.0}

def Vector3.unit_y() -> Vector3:
  Vector3{0.0, 1.0, 0.0}

def Vector3.unit_z() -> Vector3:
  Vector3{0.0, 0.0, 1.0}

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

def Vector3.angle(+left: Vector3, +right: Vector3) -> F32:
  LegacyAngle.atan2(False{}, Vector3.length(Vector3.cross_product(left, right)), Vector3.dot_product(left, right))

def Vector3.angle_for(libm: Libm, left: Vector3, right: Vector3) -> Maybe<F32>:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  CheckedAngle.maybe(CheckedAngle.vector3(Libm.angle(libm), x, y, z, u, v, w))

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

def Vector3.clamp_for(reference: Libm, vector: Vector3, lower: Vector3, upper: Vector3) -> Vector3:
  Vector3{x, y, z} = vector
  Vector3{lx, ly, lz} = lower
  Vector3{ux, uy, uz} = upper
  +gnu = Libm.gnu(reference)
  Vector3{Vector2.clamp.minimum(gnu, ux, Vector2.clamp.maximum(gnu, lx, x)),
    Vector2.clamp.minimum(gnu, uy, Vector2.clamp.maximum(gnu, ly, y)),
    Vector2.clamp.minimum(gnu, uz, Vector2.clamp.maximum(gnu, lz, z))}

def Vector3.clamp(vector: Vector3, lower: Vector3, upper: Vector3) -> Vector3:
  Vector3.clamp_for(AppleLibm{}, vector, lower, upper)

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

def Vector3.min_for(reference: Libm, left: Vector3, right: Vector3) -> Vector3:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  +gnu = Libm.gnu(reference)
  Vector3{Vector2.clamp.minimum(gnu, x, u), Vector2.clamp.minimum(gnu, y, v), Vector2.clamp.minimum(gnu, z, w)}

def Vector3.max_for(reference: Libm, left: Vector3, right: Vector3) -> Vector3:
  Vector3{x, y, z} = left
  Vector3{u, v, w} = right
  +gnu = Libm.gnu(reference)
  Vector3{Vector2.clamp.maximum(gnu, x, u), Vector2.clamp.maximum(gnu, y, v), Vector2.clamp.maximum(gnu, z, w)}

def Vector3.min(left: Vector3, right: Vector3) -> Vector3:
  Vector3.min_for(AppleLibm{}, left, right)

def Vector3.max(left: Vector3, right: Vector3) -> Vector3:
  Vector3.max_for(AppleLibm{}, left, right)

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

def Matrix.rotate_x_for(reference: Libm, angle: F32) -> Matrix:
  Matrix.rotation.x(Trig.sincos_for(Libm.gnu(reference), angle))

def Matrix.rotate_x(angle: F32) -> Matrix:
  Matrix.rotate_x_for(AppleLibm{}, angle)

def Matrix.rotation.y(values: F32 & F32) -> Matrix:
  (+cosine, +sine) = values
  Matrix{cosine, 0.0, sine, 0.0, 0.0, 1.0, 0.0, 0.0,
    F32.neg(sine), 0.0, cosine, 0.0, 0.0, 0.0, 0.0, 1.0}

def Matrix.rotate_y_for(reference: Libm, angle: F32) -> Matrix:
  Matrix.rotation.y(Trig.sincos_for(Libm.gnu(reference), angle))

def Matrix.rotate_y(angle: F32) -> Matrix:
  Matrix.rotate_y_for(AppleLibm{}, angle)

def Matrix.rotation.z(values: F32 & F32) -> Matrix:
  (+cosine, +sine) = values
  Matrix{cosine, F32.neg(sine), 0.0, 0.0, sine, cosine, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0}

def Matrix.rotate_z_for(reference: Libm, angle: F32) -> Matrix:
  Matrix.rotation.z(Trig.sincos_for(Libm.gnu(reference), angle))

def Matrix.rotate_z(angle: F32) -> Matrix:
  Matrix.rotate_z_for(AppleLibm{}, angle)

def Matrix.rotation.xyz(x_values: F32 & F32, y_values: F32 & F32, z_values: F32 & F32) -> Matrix:
  (+cx, +sx) = x_values
  (+cy, +sy) = y_values
  (+cz, +sz) = z_values
  Matrix{(cz * cy : F32), (sz * cy : F32), F32.neg(sy), 0.0,
    (cz * sy * sx - sz * cx : F32), (sz * sy * sx + cz * cx : F32), (cy * sx : F32), 0.0,
    (cz * sy * cx + sz * sx : F32), (sz * sy * cx - cz * sx : F32), (cy * cx : F32), 0.0,
    0.0, 0.0, 0.0, 1.0}

def Matrix.rotate_xyz_for(reference: Libm, angles: Vector3) -> Matrix:
  Vector3{x, y, z} = angles
  +gnu = Libm.gnu(reference)
  Matrix.rotation.xyz(Trig.sincos_for(gnu, F32.neg(x)), Trig.sincos_for(gnu, F32.neg(y)), Trig.sincos_for(gnu, F32.neg(z)))

def Matrix.rotate_xyz(angles: Vector3) -> Matrix:
  Matrix.rotate_xyz_for(AppleLibm{}, angles)

def Matrix.rotation.zyx(x_values: F32 & F32, y_values: F32 & F32, z_values: F32 & F32) -> Matrix:
  (+cx, +sx) = x_values
  (+cy, +sy) = y_values
  (+cz, +sz) = z_values
  Matrix{(cz * cy : F32), (cz * sy * sx - cx * sz : F32), (sz * sx + cz * cx * sy : F32), 0.0,
    (cy * sz : F32), (cz * cx + sz * sy * sx : F32), (cx * sz * sy - cz * sx : F32), 0.0,
    F32.neg(sy), (cy * sx : F32), (cy * cx : F32), 0.0, 0.0, 0.0, 0.0, 1.0}

def Matrix.rotate_zyx_for(reference: Libm, angles: Vector3) -> Matrix:
  Vector3{x, y, z} = angles
  +gnu = Libm.gnu(reference)
  Matrix.rotation.zyx(Trig.sincos_for(gnu, x), Trig.sincos_for(gnu, y), Trig.sincos_for(gnu, z))

def Matrix.rotate_zyx(angles: Vector3) -> Matrix:
  Matrix.rotate_zyx_for(AppleLibm{}, angles)

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

def Matrix.rotate_for(reference: Libm, +axis: Vector3, angle: F32) -> Matrix:
  +square = Vector3.length_sqr(axis)
  normalized = Matrix.rotation.normalized(F32.is_ne(square, 0.0) && F32.is_ne(square, 1.0), axis, square)
  Matrix.rotation.around(normalized, Trig.sincos_for(Libm.gnu(reference), angle))

def Matrix.rotate(axis: Vector3, angle: F32) -> Matrix:
  Matrix.rotate_for(AppleLibm{}, axis, angle)

def Vector4.zero() -> Vector4:
  Vector4{0.0, 0.0, 0.0, 0.0}

def Vector4.one() -> Vector4:
  Vector4{1.0, 1.0, 1.0, 1.0}

# raymath's C++ constants; QuaternionZeros/Ones are Vector4.zero/one,
# QuaternionUnitX is Quaternion.identity and MatrixUnit is Matrix.identity.
def Vector4.unit_x() -> Vector4:
  Vector4{1.0, 0.0, 0.0, 0.0}

def Vector4.unit_y() -> Vector4:
  Vector4{0.0, 1.0, 0.0, 0.0}

def Vector4.unit_z() -> Vector4:
  Vector4{0.0, 0.0, 1.0, 0.0}

def Vector4.unit_w() -> Vector4:
  Vector4{0.0, 0.0, 0.0, 1.0}

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

def Vector4.min_for(reference: Libm, left: Vector4, right: Vector4) -> Vector4:
  Vector4{x, y, z, w} = left
  Vector4{a, b, c, d} = right
  +gnu = Libm.gnu(reference)
  Vector4{Vector2.clamp.minimum(gnu, x, a), Vector2.clamp.minimum(gnu, y, b),
    Vector2.clamp.minimum(gnu, z, c), Vector2.clamp.minimum(gnu, w, d)}

def Vector4.max_for(reference: Libm, left: Vector4, right: Vector4) -> Vector4:
  Vector4{x, y, z, w} = left
  Vector4{a, b, c, d} = right
  +gnu = Libm.gnu(reference)
  Vector4{Vector2.clamp.maximum(gnu, x, a), Vector2.clamp.maximum(gnu, y, b),
    Vector2.clamp.maximum(gnu, z, c), Vector2.clamp.maximum(gnu, w, d)}

def Vector4.min(left: Vector4, right: Vector4) -> Vector4:
  Vector4.min_for(AppleLibm{}, left, right)

def Vector4.max(left: Vector4, right: Vector4) -> Vector4:
  Vector4.max_for(AppleLibm{}, left, right)

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

# -----------------------------------------------------------------------------
# Quaternions, decomposition and projection

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

def Quaternion.matrix.pick(index: U32, +score: F32, current: U32 & F32) -> U32 & F32:
  (previous, +best) = current
  +greater = (score > best : F32)
  (Bool.pick(U32, greater, index, previous), Bool.pick(F32, greater, score, best))

def Quaternion.matrix.result(index: U32, biggest: F32, +scale: F32, m1: F32, m2: F32, m4: F32, m6: F32, m8: F32, m9: F32) -> Vector4:
  match index:
    case 0: Vector4{((m6 - m9) * scale : F32), ((m8 - m2) * scale : F32), ((m1 - m4) * scale : F32), biggest}
    case 1: Vector4{biggest, ((m1 + m4) * scale : F32), ((m8 + m2) * scale : F32), ((m6 - m9) * scale : F32)}
    case 2: Vector4{((m1 + m4) * scale : F32), biggest, ((m6 + m9) * scale : F32), ((m8 - m2) * scale : F32)}
    case _: Vector4{((m8 + m2) * scale : F32), ((m6 + m9) * scale : F32), biggest, ((m1 - m4) * scale : F32)}

def Quaternion.matrix.finish(choice: U32 & F32, m1: F32, m2: F32, m4: F32, m6: F32, m8: F32, m9: F32) -> Vector4:
  (index, score) = choice
  +biggest = (F32.sqrt((score + 1.0 : F32)) * 0.5 : F32)
  Quaternion.matrix.result(index, biggest, (0.25 / biggest : F32), m1, m2, m4, m6, m8, m9)

def Quaternion.from_matrix(matrix: Matrix) -> Vector4:
  Matrix{+m0, m4, m8, _, m1, +m5, m9, _, m2, m6, +m10, _, _, _, _, _} = matrix
  w = (m0 + m5 + m10 : F32)
  x = (m0 - m5 - m10 : F32)
  y = (m5 - m0 - m10 : F32)
  z = (m10 - m0 - m5 : F32)
  Quaternion.matrix.finish(Quaternion.matrix.pick(3, z, Quaternion.matrix.pick(2, y,
    Quaternion.matrix.pick(1, x, (0, w)))), m1, m2, m4, m6, m8, m9)

def Quaternion.to_matrix(quaternion: Vector4) -> Matrix:
  Vector4{+x, +y, +z, +w} = quaternion
  +a2 = (x * x : F32)
  +b2 = (y * y : F32)
  +c2 = (z * z : F32)
  +ac = (x * z : F32)
  +ab = (x * y : F32)
  +bc = (y * z : F32)
  +ad = (w * x : F32)
  +bd = (w * y : F32)
  +cd = (w * z : F32)
  Matrix{(1.0 - 2.0 * (b2 + c2) : F32), (2.0 * (ab - cd) : F32), (2.0 * (ac + bd) : F32), 0.0,
    (2.0 * (ab + cd) : F32), (1.0 - 2.0 * (a2 + c2) : F32), (2.0 * (bc - ad) : F32), 0.0,
    (2.0 * (ac - bd) : F32), (2.0 * (bc + ad) : F32), (1.0 - 2.0 * (a2 + b2) : F32), 0.0,
    0.0, 0.0, 0.0, 1.0}

def Quaternion.transform(quaternion: Vector4, matrix: Matrix) -> Vector4:
  Vector4{+x, +y, +z, +w} = quaternion
  Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = matrix
  Vector4{(m0 * x + m4 * y + m8 * z + m12 * w : F32), (m1 * x + m5 * y + m9 * z + m13 * w : F32),
    (m2 * x + m6 * y + m10 * z + m14 * w : F32), (m3 * x + m7 * y + m11 * z + m15 * w : F32)}

def Vector3.rotate_by_quaternion(vector: Vector3, quaternion: Vector4) -> Vector3:
  Vector3{+vx, +vy, +vz} = vector
  Vector4{+x, +y, +z, +w} = quaternion
  Vector3{
    (vx * (x * x + w * w - y * y - z * z) + vy * (2.0 * x * y - 2.0 * w * z) + vz * (2.0 * x * z + 2.0 * w * y) : F32),
    (vx * (2.0 * w * z + 2.0 * x * y) + vy * (w * w - x * x + y * y - z * z) + vz * (F32.neg(2.0) * w * x + 2.0 * y * z) : F32),
    (vx * (F32.neg(2.0) * w * y + 2.0 * x * z) + vy * (2.0 * w * x + 2.0 * y * z) + vz * (w * w - x * x - y * y + z * z) : F32)}

def Matrix.composed(translation: Vector3, right: Vector3, up: Vector3, forward: Vector3) -> Matrix:
  Vector3{tx, ty, tz} = translation
  Vector3{rx, ry, rz} = right
  Vector3{ux, uy, uz} = up
  Vector3{fx, fy, fz} = forward
  Matrix{rx, ux, fx, tx, ry, uy, fy, ty, rz, uz, fz, tz, 0.0, 0.0, 0.0, 1.0}

def Matrix.compose(translation: Vector3, +rotation: Vector4, scale: Vector3) -> Matrix:
  Vector3{x, y, z} = scale
  right = Vector3.rotate_by_quaternion(Vector3.scale(Vector3{1.0, 0.0, 0.0}, x), rotation)
  up = Vector3.rotate_by_quaternion(Vector3.scale(Vector3{0.0, 1.0, 0.0}, y), rotation)
  forward = Vector3.rotate_by_quaternion(Vector3.scale(Vector3{0.0, 0.0, 1.0}, z), rotation)
  Matrix.composed(translation, right, up, forward)

def Matrix.decomposition.maximum(previous: F32, vector: Vector3) -> F32:
  Vector3{x, y, z} = vector
  F32.max(F32.max(F32.max(previous, F32.abs(x)), F32.abs(y)), F32.abs(z))

def Matrix.decomposition.rows(first: Vector3, second: Vector3, third: Vector3) -> Matrix:
  Vector3{a, b, c} = first
  Vector3{d, e, f} = second
  Vector3{g, h, i} = third
  Matrix{a, b, c, 0.0, d, e, f, 0.0, g, h, i, 0.0, 0.0, 0.0, 0.0, 1.0}

def Matrix.decomposition.finish(translation: Vector3, +x: Vector3, +y: Vector3, +z: Vector3, +scale: Vector3, stabilizer: F32) -> Matrix.Decomposition:
  +reflected = (Vector3.dot_product(x, Vector3.cross_product(y, z)) < 0.0 : F32)
  rx = Bool.pick(Vector3, reflected, Vector3.negate(x), x)
  ry = Bool.pick(Vector3, reflected, Vector3.negate(y), y)
  rz = Bool.pick(Vector3, reflected, Vector3.negate(z), z)
  signed_scale = Bool.pick(Vector3, reflected, Vector3.negate(scale), scale)
  Decomposed{translation, Quaternion.from_matrix(Matrix.decomposition.rows(rx, ry, rz)), Vector3.scale(signed_scale, stabilizer)}

def Matrix.decompose(matrix: Matrix) -> Matrix.Decomposition:
  Matrix{m0, m4, m8, tx, m1, m5, m9, ty, m2, m6, m10, tz, _, _, _, _} = matrix
  +first = {Vector3{m0, m4, m8} : Vector3}
  +second = {Vector3{m1, m5, m9} : Vector3}
  +third = {Vector3{m2, m6, m10} : Vector3}
  +stabilizer = Matrix.decomposition.maximum(Matrix.decomposition.maximum(Matrix.decomposition.maximum(0.000000001, first), second), third)
  +inverse = (1.0 / stabilizer : F32)
  +x0 = Vector3.scale(first, inverse)
  +y0 = Vector3.scale(second, inverse)
  +z0 = Vector3.scale(third, inverse)
  +sx = Vector3.length(x0)
  +x = Vector3.normalized((sx > 0.000000001 : F32), x0, sx)
  +y1 = Vector3.subtract(y0, Vector3.scale(x, Vector3.dot_product(x, y0)))
  +sy = Vector3.length(y1)
  +y = Vector3.normalized((sy > 0.000000001 : F32), y1, sy)
  +z1 = Vector3.subtract(z0, Vector3.scale(x, Vector3.dot_product(x, z0)))
  +z2 = Vector3.subtract(z1, Vector3.scale(y, Vector3.dot_product(y, z1)))
  +sz = Vector3.length(z2)
  z = Vector3.normalized((sz > 0.000000001 : F32), z2, sz)
  Matrix.decomposition.finish(Vector3{tx, ty, tz}, x, y, z, Vector3{sx, sy, sz}, stabilizer)

def Quaternion.vectors.result(cross: Vector3, +dot: F32) -> Vector4:
  Vector3{+x, +y, +z} = cross
  w = (F32.sqrt((x * x + y * y + z * z + dot * dot : F32)) + dot : F32)
  Quaternion.normalize(Vector4{x, y, z, w})

def Quaternion.from_vector3_to_vector3(+first: Vector3, +second: Vector3) -> Vector4:
  Quaternion.vectors.result(Vector3.cross_product(first, second), Vector3.dot_product(first, second))

def Quaternion.axis.values(axis: Vector3, values: F32 & F32) -> Vector4:
  Vector3{x, y, z} = axis
  (cosine, +sine) = values
  Quaternion.normalize(Vector4{(x * sine : F32), (y * sine : F32), (z * sine : F32), cosine})

def Quaternion.axis.checked(nonzero: Bool, reference: Libm, axis: Vector3, length: F32, angle: F32) -> Vector4:
  match nonzero:
    case False{}: Quaternion.identity()
    case True{}:
      normalized = Vector3.scale(axis, (1.0 / length : F32))
      Quaternion.axis.values(normalized, Trig.sincos_for(Libm.gnu(reference), (angle * 0.5 : F32)))

def Quaternion.from_axis_angle_for(reference: Libm, +axis: Vector3, angle: F32) -> Vector4:
  +length = Vector3.length(axis)
  Quaternion.axis.checked(F32.is_ne(length, 0.0), reference, axis, length, angle)

def Quaternion.from_axis_angle(axis: Vector3, angle: F32) -> Vector4:
  Quaternion.from_axis_angle_for(AppleLibm{}, axis, angle)

def Quaternion.euler.values(pitch: F32 & F32, yaw: F32 & F32, roll: F32 & F32) -> Vector4:
  (+cx, +sx) = pitch
  (+cy, +sy) = yaw
  (+cz, +sz) = roll
  Vector4{(sx * cy * cz - cx * sy * sz : F32), (cx * sy * cz + sx * cy * sz : F32),
    (cx * cy * sz - sx * sy * cz : F32), (cx * cy * cz + sx * sy * sz : F32)}

def Quaternion.from_euler_for(reference: Libm, pitch: F32, yaw: F32, roll: F32) -> Vector4:
  +gnu = Libm.gnu(reference)
  Quaternion.euler.values(Trig.sincos_for(gnu, (pitch * 0.5 : F32)), Trig.sincos_for(gnu, (yaw * 0.5 : F32)), Trig.sincos_for(gnu, (roll * 0.5 : F32)))

def Quaternion.from_euler(pitch: F32, yaw: F32, roll: F32) -> Vector4:
  Quaternion.from_euler_for(AppleLibm{}, pitch, yaw, roll)

# acosf under a reference profile: glibc 2.39's Sun acosf on [-1, 1]. None for
# AppleLibm and Glibc241Libm (no reproducible kernel yet) and for inputs the
# kernel refuses (|x| > 1, NaN).
def Libm.acos(libm: Libm, +x: F32) -> Maybe<F32>:
  match libm:
    case Glibc239Libm{}: InverseTrig.acos(x)
    case _: None{}

def Libm.sin.value(values: F32 & F32) -> F32:
  (_, sine) = values
  sine

# powf(x, exponent) under a reference profile: glibc 2.39's x86_64 powf for
# exponent 2 or 3 and x in [-0, 1]. None for AppleLibm and Glibc241Libm and
# outside that domain.
def Libm.pow(libm: Libm, +x: F32, +exponent: U32) -> Maybe<F32>:
  match libm:
    case Glibc239Libm{}: Power.power(x, exponent)
    case _: None{}

# powf(2, k), and the exp2f(k) compilers substitute for it, under a reference
# profile: glibc's (2.39 and 2.41 on x86_64, the SSE2 and the FMA variants
# alike) for a finite k with |k| < 126, where the result is normal
# (Power.exp2; exactly 2^k for an integral k). None for AppleLibm (not
# verified) and for every other k.
def Libm.pow2(libm: Libm, +k: F32) -> Maybe<F32>:
  match libm:
    case AppleLibm{}: None{}
    case _: Power.exp2(k)

# expf(x) under a reference profile: glibc's (2.39 and 2.41 on x86_64) for a
# finite x with |x| < 87, where the result is normal, except 32.564632 and
# -63.099461, the two arguments at which its SSE2 and FMA variants differ
# (Power.exp, docs/MATH.md). None for AppleLibm (not verified) and for every
# other x.
def Libm.exp(libm: Libm, +x: F32) -> Maybe<F32>:
  match libm:
    case AppleLibm{}: None{}
    case _: Power.exp(x)

# logf(x) under a reference profile: glibc's (2.39 and 2.41 on x86_64, both
# variants alike) for a positive normal x (Power.log). None for AppleLibm
# (not verified), zero, subnormals, negative values, infinities and NaN.
def Libm.log(libm: Libm, +x: F32) -> Maybe<F32>:
  match libm:
    case AppleLibm{}: None{}
    case _: Power.log(x)

def Libm.cos.value(values: F32 & F32) -> F32:
  (cosine, _) = values
  cosine

# The sinf/cosf arguments verified against macOS arm64: fl(DEG2RAD*d) for
# integral |d| <= 360 except 13, 19, 22, 103 and 188, where Apple's functions
# are not the correctly rounded values Jonmath's Apple kernel computes
# (docs/FRAME.md; the frame probe re-verifies each against the host).
def Libm.apple.verified(+x: F32) -> Bool:
  +deg2rad = (3.14159265358979323846 / 180.0 : F32)
  +d = F32.round((x / deg2rad : F32))
  +m = F32.abs(d)
  (m <= 360.0 : F32) && F32.is_eq((deg2rad * d : F32), x)
    && Bool.not(F32.is_eq(m, 13.0) || F32.is_eq(m, 19.0) || F32.is_eq(m, 22.0) || F32.is_eq(m, 103.0) || F32.is_eq(m, 188.0))

# sinf under a reference profile: glibc's x86_64 sinf for every finite x under
# both glibc profiles (docs/SINCOSF.md); under AppleLibm the verified
# whole-degree arguments (Libm.apple.verified). None otherwise.
def Libm.sin(libm: Libm, +x: F32) -> Maybe<F32>:
  match libm:
    case AppleLibm{}: Bool.pick(Maybe<F32>, Libm.apple.verified(x), Some{Libm.sin.value(Trig.sincos_for(False{}, x))}, None{})
    case _: Sincosf.sinf(x)

# cosf under a reference profile, with the domains of Libm.sin.
def Libm.cos(libm: Libm, +x: F32) -> Maybe<F32>:
  match libm:
    case AppleLibm{}: Bool.pick(Maybe<F32>, Libm.apple.verified(x), Some{Libm.cos.value(Trig.sincos_for(False{}, x))}, None{})
    case _: Sincosf.cosf(x)

def Quaternion.slerp.ratios(+left: Vector4, +right: Vector4, +sine: F32, first: Maybe<F32>, second: Maybe<F32>) -> Maybe<Vector4>:
  match first second:
    case Some{+a} Some{+b}: Some{Vector4.add(Vector4.scale(left, (a / sine : F32)), Vector4.scale(right, (b / sine : F32)))}
    case _ _: None{}

def Quaternion.slerp.angle(+libm: Libm, +left: Vector4, +right: Vector4, +cosine: F32, +amount: F32, angle: Maybe<F32>) -> Maybe<Vector4>:
  match angle:
    case None{}: None{}
    case Some{+half}:
      +sine = F32.sqrt((1.0 - cosine * cosine : F32))
      Bool.pick(Maybe<Vector4>, (F32.abs(sine) < 0.000001 : F32),
        Some{Vector4.add(Vector4.scale(left, 0.5), Vector4.scale(right, 0.5))},
        Quaternion.slerp.ratios(left, right, sine, Libm.sin(libm, ((1.0 - amount) * half : F32)), Libm.sin(libm, (amount * half : F32))))

def Quaternion.slerp.branch(kind: U32, +libm: Libm, +left: Vector4, +right: Vector4, +cosine: F32, +amount: F32) -> Maybe<Vector4>:
  match kind:
    case 0: Some{left}
    case 1: Some{Quaternion.nlerp(left, right, amount)}
    case _: Quaternion.slerp.angle(libm, left, right, cosine, amount, Libm.acos(libm, cosine))

# QuaternionSlerp under a reference libm profile: the reference hemisphere
# flip, the copy (|cos| >= 1) and nlerp (cos > 0.95) branches, and otherwise
# acosf/sinf from the profile. None when that branch needs an acosf the
# profile lacks (see Libm.acos), for a NaN cosine, or for a sinf argument
# Libm.sin refuses.
def Quaternion.slerp_for(+libm: Libm, +left: Vector4, +right: Vector4, +amount: F32) -> Maybe<Vector4>:
  +dot = Vector4.dot_product(left, right)
  +flip = (dot < 0.0 : F32)
  +other = Bool.pick(Vector4, flip, Vector4.negate(right), right)
  +cosine = Bool.pick(F32, flip, F32.neg(dot), dot)
  Quaternion.slerp.branch(Bool.pick(U32, (F32.abs(cosine) >= 1.0 : F32), 0, Bool.pick(U32, (cosine > 0.95 : F32), 1, 2)), libm, left, other, cosine, amount)

def Quaternion.axis_angle.parts(+quaternion: Vector4, +half: F32) -> Vector3 & F32:
  Vector4{x, y, z, w} = quaternion
  +den = F32.sqrt((1.0 - w * w : F32))
  (Bool.pick(Vector3, (den > 0.000001 : F32), Vector3{(x / den : F32), (y / den : F32), (z / den : F32)}, Vector3{1.0, 0.0, 0.0}), (2.0 * half : F32))

def Quaternion.axis_angle.result(+quaternion: Vector4, angle: Maybe<F32>) -> Maybe<(Vector3 & F32)>:
  match angle:
    case None{}: None{}
    case Some{half}: Some{Quaternion.axis_angle.parts(quaternion, half)}

def Quaternion.axis_angle.w(+quaternion: Vector4) -> F32:
  Vector4{_, _, _, w} = quaternion
  w

# QuaternionToAxisAngle under a reference libm profile: quaternions with
# |w| > 1 are normalized first; the angle is 2*acosf(w) and the axis
# (x, y, z)/sqrt(1 - w*w), or (1, 0, 0) when that is at most 1e-6. None when
# the profile lacks acosf or w is outside [-1, 1] (or NaN) after normalization.
def Quaternion.to_axis_angle_for(libm: Libm, +quaternion: Vector4) -> Maybe<(Vector3 & F32)>:
  +q = Bool.pick(Vector4, (F32.abs(Quaternion.axis_angle.w(quaternion)) > 1.0 : F32), Quaternion.normalize(quaternion), quaternion)
  Quaternion.axis_angle.result(q, Libm.acos(libm, Quaternion.axis_angle.w(q)))

def Libm.asin.within(inside: Bool, +x: F32) -> Maybe<F32>:
  match inside:
    case True{}: Asin.asin(x)
    case False{}: None{}

# asinf under a reference profile: for Glibc241Libm the correctly rounded
# kernel of glibc 2.41 (CORE-MATH) on [-1, 1]; for Glibc239Libm glibc 2.39's
# own kernel (the LGPL-2.1+ module src/lgpl/asin.bend) on [-1, 1]; for
# AppleLibm the correctly rounded kernel only for |x| < 0x1.d12edp-12, below
# which macOS asinf was exhaustively found equal to correct rounding (see
# docs/INVERSE-TRIG.md). None elsewhere, for |x| > 1 and for NaN.
def Libm.asin(libm: Libm, +x: F32) -> Maybe<F32>:
  match libm:
    case AppleLibm{}: Libm.asin.within(((F32.bits(x) .&. 2147483647) < 971544424 : U32), x)
    case Glibc239Libm{}: GlibcAsin.asin(x)
    case Glibc241Libm{}: Asin.asin(x)

def Quaternion.euler.pitch(value: Maybe<F32>) -> Result<&2, &2, U32, F32>:
  match value:
    case None{}: Fail{40}
    case Some{angle}: Done{angle}

def Quaternion.euler.clamp(+value: F32) -> F32:
  +upper = Bool.pick(F32, (value > 1.0 : F32), 1.0, value)
  Bool.pick(F32, (upper < F32.neg(1.0) : F32), F32.neg(1.0), upper)

def Quaternion.euler.valid(valid: Bool, +libm: Libm, +x: F32, +y: F32, +z: F32, +w: F32) -> Result<&2, &2, U32, Vector3>:
  match valid:
    case False{}: Fail{1}
    case True{}:
      +profile = Libm.angle(libm)
      do Result<&2, &2, U32, Vector3>:
        a0 : F32 <- CheckedAngle.normal(10, (w * x : F32))
        a1 : F32 <- CheckedAngle.normal(11, (y * z : F32))
        a2 : F32 <- CheckedAngle.normal(12, (a0 + a1 : F32))
        x0 : F32 <- CheckedAngle.normal(13, (2.0 * a2 : F32))
        b0 : F32 <- CheckedAngle.normal(14, (x * x : F32))
        b1 : F32 <- CheckedAngle.normal(15, (y * y : F32))
        b2 : F32 <- CheckedAngle.normal(16, (b0 + b1 : F32))
        b3 : F32 <- CheckedAngle.normal(17, (2.0 * b2 : F32))
        x1 : F32 <- CheckedAngle.normal(18, (1.0 - b3 : F32))
        c0 : F32 <- CheckedAngle.normal(19, (w * y : F32))
        c1 : F32 <- CheckedAngle.normal(20, (z * x : F32))
        c2 : F32 <- CheckedAngle.normal(21, (c0 - c1 : F32))
        y0 : F32 <- CheckedAngle.normal(22, (2.0 * c2 : F32))
        d0 : F32 <- CheckedAngle.normal(23, (w * z : F32))
        d1 : F32 <- CheckedAngle.normal(24, (x * y : F32))
        d2 : F32 <- CheckedAngle.normal(25, (d0 + d1 : F32))
        z0 : F32 <- CheckedAngle.normal(26, (2.0 * d2 : F32))
        e0 : F32 <- CheckedAngle.normal(27, (y * y : F32))
        e1 : F32 <- CheckedAngle.normal(28, (z * z : F32))
        e2 : F32 <- CheckedAngle.normal(29, (e0 + e1 : F32))
        e3 : F32 <- CheckedAngle.normal(30, (2.0 * e2 : F32))
        z1 : F32 <- CheckedAngle.normal(31, (1.0 - e3 : F32))
        roll : F32 <- CheckedAngle.scalar(profile, x0, x1)
        pitch : F32 <- Quaternion.euler.pitch(Libm.asin(libm, Quaternion.euler.clamp(y0)))
        yaw : F32 <- CheckedAngle.scalar(profile, z0, z1)
        return Vector3{roll, pitch, yaw}

def Quaternion.euler.maybe(result: Result<&2, &2, U32, Vector3>) -> Maybe<Vector3>:
  match result:
    case Fail{_}: None{}
    case Done{angles}: Some{angles}

# QuaternionToEuler under a reference libm profile: (roll, pitch, yaw) =
# (atan2f(x0, x1), asinf(clamp(y0, -1, 1)), atan2f(z0, z1)) in raymath's
# uncontracted F32 order, with the profile's atan2f and asinf (Libm.asin).
# None unless every component is finite, every intermediate (products, sums,
# x0, x1, y0, z0, z1) and both atan2f results are signed zero or normal (the
# checked angle contract of docs/ANGLES.md), and the profile has the asinf
# result.
def Quaternion.to_euler_for(+libm: Libm, quaternion: Vector4) -> Maybe<Vector3>:
  Vector4{+x, +y, +z, +w} = quaternion
  Quaternion.euler.maybe(Quaternion.euler.valid(CheckedAngle.finite(x) && CheckedAngle.finite(y) &&
    CheckedAngle.finite(z) && CheckedAngle.finite(w), libm, x, y, z, w))

def Vector3.axis.rotated(+vector: Vector3, axis: Vector3, values: F32 & F32) -> Vector3:
  (cosine, sine) = values
  +spin = Vector3.scale(axis, sine)
  +first = Vector3.cross_product(spin, vector)
  second = Vector3.cross_product(spin, first)
  Vector3.add(Vector3.add(vector, Vector3.scale(first, (cosine * 2.0 : F32))), Vector3.scale(second, 2.0))

def Vector3.rotate_by_axis_angle_for(reference: Libm, vector: Vector3, +axis: Vector3, angle: F32) -> Vector3:
  +length = Vector3.length(axis)
  normalized = Vector3.scale(axis, (1.0 / Bool.pick(F32, F32.is_eq(length, 0.0), 1.0, length) : F32))
  Vector3.axis.rotated(vector, normalized, Trig.sincos_for(Libm.gnu(reference), (angle / 2.0 : F32)))

def Vector3.rotate_by_axis_angle(vector: Vector3, axis: Vector3, angle: F32) -> Vector3:
  Vector3.rotate_by_axis_angle_for(AppleLibm{}, vector, axis, angle)

def Quaternion.cubic_hermite_spline(first: Vector4, first_tangent: Vector4, second: Vector4, second_tangent: Vector4, +amount: F32) -> Vector4:
  +square = (amount * amount : F32)
  +cube = (square * amount : F32)
  a = Quaternion.scale(first, (2.0 * cube - 3.0 * square + 1.0 : F32))
  b = Quaternion.scale(first_tangent, (cube - 2.0 * square + amount : F32))
  c = Quaternion.scale(second, (F32.neg(2.0) * cube + 3.0 * square : F32))
  d = Quaternion.scale(second_tangent, (cube - square : F32))
  Quaternion.normalize(Quaternion.add(Quaternion.add(Quaternion.add(a, b), c), d))

def Vector3.unproject.result(value: Vector4) -> Vector3:
  Vector4{x, y, z, +w} = value
  Vector3{(x / w : F32), (y / w : F32), (z / w : F32)}

def Vector3.unproject(source: Vector3, projection: Matrix, view: Matrix) -> Vector3:
  Vector3{x, y, z} = source
  # Preserve the two transposed Matrix initializers in raymath's inlined path.
  inverse = Matrix.transpose(Matrix.invert(Matrix.transpose(Matrix.multiply(view, projection))))
  Vector3.unproject.result(Quaternion.transform(Vector4{x, y, z, 1.0}, inverse))

# -----------------------------------------------------------------------------
# Operator sugar (raymath's optional C++ operators)
#
# Bend's typed operators call T.add, T.sub, T.mul and T.div, so
# (a - b : M.Vector3) is raymath's same-type C++ operator. The scalar and
# matrix overloads (v * s, v / s, v * m, q + s, q - s, q * m, m * s) and
# ==/!= are the named functions those operators call (see docs/MATH.md).

def Vector2.sub(left: Vector2, right: Vector2) -> Vector2:
  Vector2.subtract(left, right)

def Vector2.mul(left: Vector2, right: Vector2) -> Vector2:
  Vector2.multiply(left, right)

def Vector2.div(left: Vector2, right: Vector2) -> Vector2:
  Vector2.divide(left, right)

def Vector3.sub(left: Vector3, right: Vector3) -> Vector3:
  Vector3.subtract(left, right)

def Vector3.mul(left: Vector3, right: Vector3) -> Vector3:
  Vector3.multiply(left, right)

def Vector3.div(left: Vector3, right: Vector3) -> Vector3:
  Vector3.divide(left, right)

def Vector4.sub(left: Vector4, right: Vector4) -> Vector4:
  Vector4.subtract(left, right)

def Vector4.mul(left: Vector4, right: Vector4) -> Vector4:
  Vector4.multiply(left, right)

def Vector4.div(left: Vector4, right: Vector4) -> Vector4:
  Vector4.divide(left, right)

def Matrix.sub(left: Matrix, right: Matrix) -> Matrix:
  Matrix.subtract(left, right)

def Matrix.mul(left: Matrix, right: Matrix) -> Matrix:
  Matrix.multiply(left, right)
