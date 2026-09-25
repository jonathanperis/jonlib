# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Bounded trigonometry for image-generation angles. Range reduction and Taylor
# evaluation use software extended precision; only the final result becomes F32.
# GNU-profile coefficients/evaluation adapted from Arm optimized-routines,
# Copyright (c) 2018-2024 Arm Limited; MIT alternative, see LICENSES/arm-math.txt.
import Base
import ./resize_numeric.bend as N

def negate(value: N.Double) -> N.Double:
  N.Double{sign, exponent, mantissa} = value
  N.Double{Bool.not(sign), exponent, mantissa}

def piece(sign: Bool, +power: F32, value: U32) -> F32:
  +scaled = N.scale2(F32.to_nat(F32.abs(power)), Bool.pick(F32, (power < 0.0 : F32), 0.5, 2.0), U32.to_f32(value))
  Bool.pick(F32, sign, F32.neg(scaled), scaled)

def multiply.nonzero(zero: Bool, +a: N.Double, b: N.Double) -> N.Double:
  match zero:
    case True{}: N.Double.zero()
    case False{}:
      N.Double{+sign, +exponent, N.Wide{high, +low}} = b
      upper = N.Double.mul_f32(piece(sign, (exponent - 23.0 : F32), ((high << 3n) .|. (low >> 29n) : U32)), a)
      middle = N.Double.mul_f32(piece(sign, (exponent - 47.0 : F32), ((low >> 5n) .&. 16777215 : U32)), a)
      lower = N.Double.mul_f32(piece(sign, (exponent - 52.0 : F32), (low .&. 31 : U32)), a)
      N.Double.add(upper, N.Double.add(middle, lower))

def multiply(+a: N.Double, +b: N.Double) -> N.Double:
  N.Double{_, _, am} = a
  N.Double{_, _, bm} = b
  multiply.nonzero(N.Wide.is_zero(am) || N.Wide.is_zero(bm), a, b)

def polynomial(coefficients: +List<N.Double>, +square: N.Double, value: N.Double) -> N.Double:
  match coefficients:
    case Nil{}: value
    case Con{coefficient, rest}:
      polynomial(rest, square, N.Double.add(multiply(value, square), coefficient))

# Rounded binary64 values of (-1)^k/(2k+1)! and (-1)^k/(2k)!, highest first.
def sine_coefficients() -> +List<N.Double>:
  [N.Double{False{}, F32.neg(49.0), N.Wide{1659591, 1882238282}},
   N.Double{True{}, F32.neg(41.0), N.Wide{1763315, 3878926367}},
   N.Double{False{}, F32.neg(33.0), N.Wide{1446470, 329805065}},
   N.Double{True{}, F32.neg(26.0), N.Wide{1762885, 1744127204}},
   N.Double{False{}, F32.neg(19.0), N.Wide{1514979, 2773927732}},
   N.Double{True{}, F32.neg(13.0), N.Wide{1704352, 436314138}},
   N.Double{False{}, F32.neg(7.0), N.Wide{1118481, 286331153}},
   N.Double{True{}, F32.neg(3.0), N.Wide{1398101, 1431655765}},
   N.Double{False{}, 0.0, N.Wide{1048576, 0}}]

def cosine_coefficients() -> +List<N.Double>:
  [N.Double{True{}, F32.neg(53.0), N.Wide{1475192, 1673100695}},
   N.Double{False{}, F32.neg(45.0), N.Wide{1763315, 3878926367}},
   N.Double{True{}, F32.neg(37.0), N.Wide{1653108, 2831187101}},
   N.Double{False{}, F32.neg(29.0), N.Wide{1175256, 4026063000}},
   N.Double{True{}, F32.neg(22.0), N.Wide{1211983, 3078135644}},
   N.Double{False{}, F32.neg(16.0), N.Wide{1704352, 436314138}},
   N.Double{True{}, F32.neg(10.0), N.Wide{1491308, 381774871}},
   N.Double{False{}, F32.neg(5.0), N.Wide{1398101, 1431655765}},
   N.Double{True{}, F32.neg(1.0), N.Wide{1048576, 0}},
   N.Double{False{}, 0.0, N.Wide{1048576, 0}}]

def quadrant(index: U32, cosine: F32, sine: F32) -> F32 & F32:
  match index:
    case 0: (cosine, sine)
    case 1: (F32.neg(sine), cosine)
    case 2: (F32.neg(cosine), F32.neg(sine))
    case _: (sine, F32.neg(cosine))

def signed(negative: Bool, values: F32 & F32) -> F32 & F32:
  (cosine, +sine) = values
  (cosine, Bool.pick(F32, negative, F32.neg(sine), sine))

def arm_polynomial(+value: N.Double, +square: N.Double) -> F32 & F32:
  +x3 = multiply(value, square)
  +x4 = multiply(square, square)
  x5 = multiply(x3, square)
  x6 = multiply(x4, square)
  c2 = N.Double.add(N.Double{True{}, F32.neg(10.0), N.Wide{1491079, 3902420381}},
    multiply(square, N.Double{False{}, F32.neg(16.0), N.Wide{1676099, 41679043}}))
  s1 = N.Double.add(N.Double{False{}, F32.neg(7.0), N.Wide{1118326, 86182852}},
    multiply(square, N.Double{True{}, F32.neg(13.0), N.Wide{1676523, 930402084}}))
  c1 = N.Double.add(N.Double.from_f32(1.0), multiply(square, N.Double{True{}, F32.neg(2.0), N.Wide{2097151, 4245447196}}))
  s = N.Double.add(value, multiply(x3, N.Double{True{}, F32.neg(3.0), N.Wide{1398100, 1502979587}}))
  c = N.Double.add(c1, multiply(x4, N.Double{False{}, F32.neg(5.0), N.Wide{1398099, 3775303449}}))
  (N.Double.to_f32(N.Double.add(c, multiply(x6, c2))), N.Double.to_f32(N.Double.add(s, multiply(x5, s1))))

def evaluate_polynomial(gnu: Bool, +value: N.Double, +square: N.Double) -> F32 & F32:
  match gnu:
    case True{}: arm_polynomial(value, square)
    case False{}:
      sine = N.Double.to_f32(multiply(value, polynomial(sine_coefficients(), square, N.Double.zero())))
      cosine = N.Double.to_f32(polynomial(cosine_coefficients(), square, N.Double.zero()))
      (cosine, sine)

def reduced_values(index: U32, negative: Bool, values: F32 & F32) -> F32 & F32:
  (cosine, sine) = values
  signed(negative, quadrant((index .&. 3 : U32), cosine, sine))

def reduced(gnu: Bool, index: U32, negative: Bool, +value: N.Double) -> F32 & F32:
  +square = multiply(value, value)
  reduced_values(index, negative, evaluate_polynomial(gnu, value, square))

def evaluate(zero: Bool, gnu: Bool, +radians: F32) -> F32 & F32:
  match zero:
    case True{}: (1.0, radians)
    case False{}:
      +magnitude = F32.abs(radians)
      +index = F32.to_u32(F32.floor((magnitude * 0.6366197723675814 + 0.5 : F32)))
      half_pi = {N.Double{False{}, 0.0, N.Wide{1647099, 1413754136}} : N.Double}
      reduced(gnu, index, (radians < 0.0 : F32), N.Double.add(N.Double.from_f32(magnitude), negate(N.Double.mul_f32(U32.to_f32(index), half_pi))))

def sincos_for(gnu: Bool, +radians: F32) -> F32 & F32:
  evaluate(F32.is_eq(radians, 0.0), gnu, radians)

def sincos(+radians: F32) -> F32 & F32:
  sincos_for(False{}, radians)
