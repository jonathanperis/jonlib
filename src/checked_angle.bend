# Jonmath - zlib license, Copyright (c) 2026 Jonathan Peris.
# Checked source-order adapters for pinned raymath angle expressions.
# Scalar algorithms and their original notices remain in angle/modern_angle.
import Base
import ./angle.bend as Legacy
import ./modern_angle.bend as Modern

# Internal stage IDs are diagnostics, not an additional public error API.
# Every bind branches on the preceding check before evaluating dependent work.
def finite(value: F32) -> Bool:
  ((F32.bits(value) .&. 2147483647) < 2139095040 : U32)

def normal_or_zero(value: F32) -> Bool:
  +magnitude = (F32.bits(value) .&. 2147483647 : U32)
  U32.is_eq(magnitude, 0) || ((magnitude >= 8388608) && (magnitude < 2139095040) : U32)

def normal.route(valid: Bool, stage: U32, value: F32) -> Result<&2, &2, U32, F32>:
  match valid:
    case False{}: Fail{stage}
    case True{}: Done{value}

def normal(stage: U32, +value: F32) -> Result<&2, &2, U32, F32>:
  normal.route(normal_or_zero(value), stage, value)

def from_word(value: U32) -> F32:
  U32{bits} = value
  F32{bits}

# A successful scalar value must still satisfy the narrower wrapper domain.
# None is propagated as a distinct failure, never a legacy fallback or zero.
def scalar_result(result: Maybe<U32>) -> Result<&2, &2, U32, F32>:
  match result:
    case None{}: Fail{31}
    case Some{word}: normal(32, from_word(word))

def scalar(profile: U32, y: F32, x: F32) -> Result<&2, &2, U32, F32>:
  match profile:
    case 0: normal(32, Legacy.atan2(False{}, y, x))
    case 1: normal(32, Legacy.atan2(True{}, y, x))
    case 2: scalar_result(Modern.checked(F32.bits(y), F32.bits(x)))
    case _: Fail{2}

def maybe(result: Result<&2, &2, U32, F32>) -> Maybe<F32>:
  match result:
    case Fail{_}: None{}
    case Done{value}: Some{value}

def vector2.valid(valid: Bool, profile: U32, +x: F32, +y: F32, +u: F32, +v: F32) -> Result<&2, &2, U32, F32>:
  match valid:
    case False{}: Fail{1}
    case True{}:
      do Result<&2, &2, U32, F32>:
        p0 : F32 <- normal(10, (x * u : F32))
        p1 : F32 <- normal(11, (y * v : F32))
        dot : F32 <- normal(12, (p0 + p1 : F32))
        q0 : F32 <- normal(13, (x * v : F32))
        q1 : F32 <- normal(14, (y * u : F32))
        det : F32 <- normal(15, (q0 - q1 : F32))
        result : F32 <- scalar(profile, det, dot)
        return result

def vector2(profile: U32, +x: F32, +y: F32, +u: F32, +v: F32) -> Result<&2, &2, U32, F32>:
  vector2.valid(finite(x) && finite(y) && finite(u) && finite(v), profile, x, y, u, v)

def line.valid(valid: Bool, profile: U32, x: F32, y: F32, u: F32, v: F32) -> Result<&2, &2, U32, F32>:
  match valid:
    case False{}: Fail{1}
    case True{}:
      do Result<&2, &2, U32, F32>:
        dy : F32 <- normal(10, (v - y : F32))
        dx : F32 <- normal(11, (u - x : F32))
        value : F32 <- scalar(profile, dy, dx)
        result : F32 <- normal(33, F32.neg(value))
        return result

def line(profile: U32, +x: F32, +y: F32, +u: F32, +v: F32) -> Result<&2, &2, U32, F32>:
  line.valid(finite(x) && finite(y) && finite(u) && finite(v), profile, x, y, u, v)

# Synthetic negative/special square controls exercise this private guard only.
# Such squares cannot arise from accepted squares and sums of valid vectors.
def sqrt.valid(valid: Bool, square: F32) -> Result<&2, &2, U32, F32>:
  match valid:
    case False{}: Fail{24}
    case True{}: normal(25, F32.sqrt(square))

def sqrt(+square: F32) -> Result<&2, &2, U32, F32>:
  sqrt.valid(normal_or_zero(square) && (square >= 0.0 : F32), square)

def vector3.valid(valid: Bool, profile: U32, +x: F32, +y: F32, +z: F32, +u: F32, +v: F32, +w: F32) -> Result<&2, &2, U32, F32>:
  match valid:
    case False{}: Fail{1}
    case True{}:
      do Result<&2, &2, U32, F32>:
        a0 : F32 <- normal(10, (y * w : F32))
        a1 : F32 <- normal(11, (z * v : F32))
        b0 : F32 <- normal(12, (z * u : F32))
        b1 : F32 <- normal(13, (x * w : F32))
        c0 : F32 <- normal(14, (x * v : F32))
        c1 : F32 <- normal(15, (y * u : F32))
        +cx : F32 <- normal(16, (a0 - a1 : F32))
        +cy : F32 <- normal(17, (b0 - b1 : F32))
        +cz : F32 <- normal(18, (c0 - c1 : F32))
        sx : F32 <- normal(19, (cx * cx : F32))
        sy : F32 <- normal(20, (cy * cy : F32))
        sz : F32 <- normal(21, (cz * cz : F32))
        sxy : F32 <- normal(22, (sx + sy : F32))
        square : F32 <- normal(23, (sxy + sz : F32))
        length : F32 <- sqrt(square)
        p0 : F32 <- normal(26, (x * u : F32))
        p1 : F32 <- normal(27, (y * v : F32))
        p2 : F32 <- normal(28, (z * w : F32))
        dxy : F32 <- normal(29, (p0 + p1 : F32))
        dot : F32 <- normal(30, (dxy + p2 : F32))
        result : F32 <- scalar(profile, length, dot)
        return result

def vector3(profile: U32, +x: F32, +y: F32, +z: F32, +u: F32, +v: F32, +w: F32) -> Result<&2, &2, U32, F32>:
  vector3.valid(finite(x) && finite(y) && finite(z) && finite(u) && finite(v) && finite(w), profile, x, y, z, u, v, w)
