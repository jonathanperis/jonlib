# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Independent Bend evaluation of the mathematical factored atan approximation
# and boundary values documented by Eric Postpischil, Apple Libm (July 2007).
# Mathematical provenance is recorded in THIRD_PARTY_NOTICES.md; no assembly is included.
# GNU float kernels adapted from Sun's atan/atan2 algorithms, Copyright (C) 1993
# Sun Microsystems, Inc.; retained permission notice in LICENSES/sun-math.txt.
import Base
import ./resize_numeric.bend as N
import ./float64.bend as F
import ./float64_ops.bend as O

def signed(negative: Bool, +value: F32) -> F32:
  Bool.pick(F32, negative, F32.neg(value), value)

def apple.factor(+square: N.Double, linear: N.Double, constant: N.Double) -> N.Double:
  N.Double.add(O.multiply(N.Double.add(square, linear), square), constant)

def apple.polynomial(+value: N.Double, base: N.Double) -> F32:
  +square = O.multiply(value, value)
  a = apple.factor(square, F.number(1073897619, 1913089580), F.number(1073975116, 118186945))
  b = apple.factor(square, F.number(3221721813, 3206004924), F.number(1075176497, 1758970550))
  c = apple.factor(square, F.number(1066745268, 2610941803), F.number(1074679716, 2037551170))
  d = apple.factor(square, F.number(3222528880, 342304435), F.number(1075503355, 150133760))
  left = O.multiply(O.multiply(a, b), F.number(1063783360, 4263714877))
  right = O.multiply(O.multiply(c, d), value)
  N.Double.to_f32(N.Double.add(O.multiply(left, right), base))

def apple.small_ratio(value: N.Double) -> Bool:
  N.Double{_, +exponent, mantissa} = value
  (exponent < F32.neg(22.0) : F32)
    || (F32.is_eq(exponent, F32.neg(22.0)) && N.Wide.eq(mantissa, N.Wide{1048576, 0}))

def apple.horizontal(negative_x: Bool, +negative_y: Bool, +ratio: N.Double) -> F32:
  match negative_x:
    case False{}: apple.polynomial(ratio, N.Double{True{}, 0.0, N.Wide.zero()})
    case True{}:
      Bool.pick(F32, apple.small_ratio(ratio), signed(negative_y, 3.141592502593994),
        apple.polynomial(ratio, O.signed(negative_y, F.number(1074340347, 1413754136))))

def apple.reduced(equal: Bool, vertical: Bool, negative_x: Bool, negative_y: Bool, y: F32, x: F32) -> F32:
  match equal vertical:
    case True{} _: signed(negative_y, Bool.pick(F32, negative_x, 2.356194490192345, 0.7853981633974483))
    case False{} True{}:
      apple.polynomial(O.divide(O.from_f32(F32.neg(x)), O.from_f32(y)), O.signed(negative_y, F.number(1073291771, 1413754136)))
    case False{} False{}:
      apple.horizontal(negative_x, negative_y, O.divide(O.from_f32(y), O.from_f32(x)))

def apple.axes(+ay: U32, +ax: U32, negative_x: Bool, negative_y: Bool, +y: F32, x: F32) -> F32:
  match ay ax:
    case 0 _: Bool.pick(F32, negative_x, signed(negative_y, 3.141592502593994), y)
    case _ 0: signed(negative_y, 1.5707963267948966)
    case _ _: apple.reduced(U32.is_eq(ay, ax), (ay > ax : U32), negative_x, negative_y, y, x)

def apple(+y: F32, +x: F32) -> F32:
  +yb = F32.bits(y)
  +xb = F32.bits(x)
  apple.axes((yb .&. 2147483647 : U32), (xb .&. 2147483647 : U32),
    (xb >= 2147483648 : U32), (yb >= 2147483648 : U32), y, x)

def gnu.correction(+x: F32) -> F32:
  +z = (x * x : F32)
  +w = (z * z : F32)
  s1 = (z * (0.33333334327 + w * (0.14285714924 + w * (0.090908870101 + w * (0.066610731184 + w * (0.049768779427 + w * 0.016285819933))))) : F32)
  s2 = (w * (F32.neg(0.20000000298) + w * (F32.neg(0.11111110449) + w * (F32.neg(0.076918758452) + w * (F32.neg(0.058335702866) + w * F32.neg(0.036531571299))))) : F32)
  (x * (s1 + s2) : F32)

def gnu.reconstructed(index: U32, x: F32, correction: F32) -> F32:
  match index:
    case 0: (0.46364760399 - ((correction - 0.0000000050121582440) - x) : F32)
    case 1: (0.78539812565 - ((correction - 0.000000037748947079) - x) : F32)
    case 2: (0.98279368877 - ((correction - 0.000000034473217170) - x) : F32)
    case 3: (1.5707962513 - ((correction - 0.000000075497894159) - x) : F32)
    case _: (x - correction : F32)

def gnu.reduced(index: U32, +x: F32) -> F32:
  gnu.reconstructed(index, x, gnu.correction(x))

def gnu.interval(region: U32, +x: F32) -> F32:
  match region:
    case 0: x
    case 1: gnu.reduced(4, x)
    case 2: gnu.reduced(0, ((2.0 * x - 1.0) / (2.0 + x) : F32))
    case 3: gnu.reduced(1, ((x - 1.0) / (x + 1.0) : F32))
    case 4: gnu.reduced(2, ((x - 1.5) / (1.0 + 1.5 * x) : F32))
    case 5: gnu.reduced(3, (F32.neg(1.0) / x : F32))
    case _: (1.5707962513 + 0.000000075497894159 : F32)

def gnu.atan(+value: F32) -> F32:
  +bits = F32.bits(value)
  region = Bool.pick(U32, (bits < 822083584 : U32), 0,
    Bool.pick(U32, (bits < 1054867456 : U32), 1,
      Bool.pick(U32, (bits < 1060110336 : U32), 2,
        Bool.pick(U32, (bits < 1066926080 : U32), 3,
          Bool.pick(U32, (bits < 1075576832 : U32), 4,
            Bool.pick(U32, (bits < 1275068416 : U32), 5, 6))))))
  gnu.interval(region, value)

def gnu.ratio(huge: Bool, tiny_negative: Bool, y: F32, x: F32) -> F32:
  match huge tiny_negative:
    case True{} _: (1.5707963705 + 0.5 * F32.neg(0.000000087422776573) : F32)
    case False{} True{}: 0.0
    case False{} False{}: gnu.atan(F32.abs((y / x : F32)))

def gnu.quadrant(negative_x: Bool, negative_y: Bool, +angle: F32) -> F32:
  match negative_x:
    case False{}: signed(negative_y, angle)
    case True{}:
      +adjusted = (angle - F32.neg(0.000000087422776573) : F32)
      Bool.pick(F32, negative_y, (adjusted - 3.1415927410 : F32), (3.1415927410 - adjusted : F32))

def gnu.axes(+ay: U32, +ax: U32, +negative_x: Bool, negative_y: Bool, +y: F32, x: F32) -> F32:
  match ay ax:
    case 0 _: Bool.pick(F32, negative_x, signed(negative_y, 3.1415927410), y)
    case _ 0: signed(negative_y, 1.5707963705)
    case _ _:
      gnu.quadrant(negative_x, negative_y, gnu.ratio((ay >= ax + 511705088 : U32),
        negative_x && (ax > ay + 503316480 : U32), y, x))

def gnu(+y: F32, +x: F32) -> F32:
  +yb = F32.bits(y)
  +xb = F32.bits(x)
  gnu.axes((yb .&. 2147483647 : U32), (xb .&. 2147483647 : U32), (xb >= 2147483648 : U32),
    (yb >= 2147483648 : U32), y, x)

def atan2(gnu_profile: Bool, y: F32, x: F32) -> F32:
  match gnu_profile:
    case False{}: apple(y, x)
    case True{}: gnu(y, x)
