# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Internal finite-normal F32 multiply-add. Keep the exact F32 product and round
# the aligned sum directly to 24 bits, avoiding binary64 double rounding.
import Base
import ./resize_numeric.bend as N

def finish(sign: Bool, +power: F32, value: N.Wide) -> F32:
  N.Wide{_, +low} = value
  +rest = (low .&. 7 : U32)
  up = ((rest > 4) || (U32.is_eq(rest, 4) && U32.is_ne((low .&. 8 : U32), 0)) : U32)
  +result = N.scale2(F32.to_nat(F32.abs(power)), Bool.pick(F32, (power < 0.0 : F32), 0.5, 2.0),
    U32.to_f32(((low >> 3n) + Bool.to_u32(up) : U32)))
  Bool.pick(F32, sign, F32.neg(result), result)

def rounded(zero: Bool, sign: Bool, +exponent: F32, +mantissa: N.Wide) -> F32:
  match zero:
    case True{}: 0.0
    case False{}:
      +top = N.Wide.top(mantissa)
      +shift = (top - 26.0 : F32)
      adjusted = Bool.pick(N.Wide, (shift >= 0.0 : F32),
        N.Wide.jam(F32.to_nat(F32.max(shift, 0.0)), mantissa),
        N.Wide.shl(F32.to_nat(F32.max(F32.neg(shift), 0.0)), mantissa))
      finish(sign, (exponent + top - 78.0 : F32), adjusted)

def normalize(sign: Bool, exponent: F32, +mantissa: N.Wide) -> F32:
  rounded(N.Wide.is_zero(mantissa), sign, exponent, mantissa)

def add_sorted(a: N.Double, b: N.Double) -> F32:
  N.Double{+sign, +ae, am} = a
  N.Double{bs, be, bm} = b
  +big = N.Wide.shl(3n, am)
  +small = N.Wide.jam(F32.to_nat((ae - be : F32)), N.Wide.shl(3n, bm))
  normalize(sign, ae, Bool.pick(N.Wide, Bool.xor(sign, bs), N.Wide.sub(big, small), N.Wide.add(big, small)))

def add(product: N.Double, value: N.Double) -> F32:
  N.Double{+as, +ae, +am} = product
  N.Double{+bs, +be, +bm} = value
  +ordered = ((ae > be) || (F32.is_eq(ae, be) && N.Wide.ge(am, bm)) : F32)
  add_sorted(Bool.pick(N.Double, ordered, N.Double{as, ae, am}, N.Double{bs, be, bm}),
    Bool.pick(N.Double, ordered, N.Double{bs, be, bm}, N.Double{as, ae, am}))

def calculate(simple: Bool, +a: F32, +b: F32, +c: F32) -> F32:
  match simple:
    case True{}: (a * b + c : F32)
    case False{}: add(N.Double.mul_f32(a, N.Double.from_f32(b)), N.Double.from_f32(c))

def multiply_add(+a: F32, +b: F32, +c: F32) -> F32:
  calculate(F32.is_eq(a, 0.0) || F32.is_eq(b, 0.0) || F32.is_eq(c, 0.0), a, b, c)
