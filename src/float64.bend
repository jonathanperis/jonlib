# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Binary64 encoding and finite-normal projection arithmetic using integer limbs.
import Base
import ./resize_numeric.bend as N

def promote.small(zero: Bool, sign: U32, +fraction: U32) -> U32 & U32:
  match zero:
    case True{}: (sign, 0)
    case False{}:
      +top = U32.log2(fraction)
      +mantissa = (U32.shln(fraction, (23n - top : Nat)) .&. 8388607 : U32)
      exponent = (U32.from_nat(top) + 874 : U32)
      ((sign .|. (exponent << 20n) .|. (mantissa >> 3n) : U32), (mantissa << 29n : U32))

def promote.parts(exponent: U32, sign: U32, +fraction: U32) -> U32 & U32:
  match exponent:
    case 0: promote.small(U32.is_eq(fraction, 0), sign, fraction)
    case 255:
      +payload = (fraction .|. Bool.pick(U32, U32.is_eq(fraction, 0), 0, 4194304) : U32)
      ((sign .|. 2146435072 .|. (payload >> 3n) : U32), (payload << 29n : U32))
    case _:
      ((sign .|. ((exponent + 896) << 20n) .|. (fraction >> 3n) : U32), (fraction << 29n : U32))

def promote(value: F32) -> U32 & U32:
  +bits = F32.bits(value)
  promote.parts(((bits >> 23n) .&. 255 : U32), (bits .&. 2147483648 : U32), (bits .&. 8388607 : U32))

def number(+high: U32, +low: U32) -> N.Double:
  +encoded = ((high >> 20n) .&. 2047 : U32)
  +fraction = (high .&. 1048575 : U32)
  zero = U32.is_eq(encoded, 0) && U32.is_eq((fraction .|. low : U32), 0)
  exponent = Bool.pick(F32, U32.is_eq(encoded, 0), F32.neg(1022.0), (U32.to_f32(encoded) - 1023.0 : F32))
  N.Double{(high >= 2147483648 : U32), Bool.pick(F32, zero, 0.0, exponent),
    N.Wide{(fraction .|. Bool.pick(U32, U32.is_eq(encoded, 0), 0, 1048576) : U32), low}}

def negate(value: N.Double) -> N.Double:
  N.Double{sign, exponent, mantissa} = value
  N.Double{Bool.not(sign), exponent, mantissa}

def to_f32(high: U32, low: U32) -> F32:
  N.Double.to_f32(number(high, low))

def difference(ah: U32, al: U32, bh: U32, bl: U32) -> F32:
  N.Double.to_f32(N.Double.add(number(ah, al), negate(number(bh, bl))))
