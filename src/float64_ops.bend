# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Internal normal finite binary64 multiplication/division with direct limb rounding.
import Base
import ./resize_numeric.bend as N
import ./float64.bend as F

def from_words(words: U32 & U32) -> N.Double:
  (high, low) = words
  F.number(high, low)

def from_f32(value: F32) -> N.Double:
  from_words(F.promote(value))

type Product is Data:
  Product{high: N.Wide, low: N.Wide}

def Product.add(a: Product, b: Product) -> Product:
  Product{ah, +al} = a
  Product{bh, bl} = b
  +low = N.Wide.add(al, bl)
  carry = Bool.to_u32(Bool.not(N.Wide.ge(low, al)))
  Product{N.Wide.add(N.Wide.add(ah, bh), N.Wide{0, carry}), low}

def Product.shl(value: Product) -> Product:
  Product{high, N.Wide{+h, l}} = value
  Product{N.Wide.add(N.Wide.shl1(high), N.Wide{0, (h >> 31n : U32)}), N.Wide.shl1(N.Wide{h, l})}

def Product.jam1(value: Product) -> Product:
  Product{N.Wide{+a, +b}, N.Wide{+c, +d}} = value
  Product{N.Wide{(a >> 1n : U32), ((b >> 1n) .|. (a << 31n) : U32)},
    N.Wide{((c >> 1n) .|. (b << 31n) : U32), ((d >> 1n) .|. (c << 31n) .|. (d .&. 1) : U32)}}

def Product.jam(n: Nat, value: Product) -> Product:
  match n:
    case 0n: value
    case 1n+k: Product.jam(k, Product.jam1(value))

def Product.mul(n: Nat, +bits: N.Wide, +value: Product, +acc: Product) -> Product:
  match n:
    case 0n: acc
    case 1n+k:
      Product.mul(k, N.Wide.shr1(bits), Product.shl(value), Bool.pick(Product, N.Wide.odd(bits), Product.add(acc, value), acc))

def Product.finish(sign: Bool, exponent: F32, value: Product) -> N.Double:
  Product{_, low} = value
  N.Double.round(sign, exponent, low)

def Product.round(sign: Bool, exponent: F32, +value: Product) -> N.Double:
  Product{high, _} = value
  +top = (64.0 + N.Wide.top(high) : F32)
  Product.finish(sign, (exponent + top - 104.0 : F32), Product.jam(F32.to_nat((top - 55.0 : F32)), value))

def multiply.ready(zero: Bool, sign: Bool, exponent: F32, a: N.Wide, b: N.Wide) -> N.Double:
  match zero:
    case True{}: N.Double{sign, 0.0, N.Wide.zero()}
    case False{}:
      Product.round(sign, exponent, Product.mul(53n, b, Product{N.Wide.zero(), a}, Product{N.Wide.zero(), N.Wide.zero()}))

def multiply(a: N.Double, b: N.Double) -> N.Double:
  N.Double{as, ae, +am} = a
  N.Double{bs, be, +bm} = b
  multiply.ready(N.Wide.is_zero(am) || N.Wide.is_zero(bm), Bool.xor(as, bs), (ae + be : F32), am, bm)

def signed(sign: Bool, value: N.Double) -> N.Double:
  N.Double{_, exponent, mantissa} = value
  N.Double{sign, exponent, mantissa}

def divide.ready(zero: Bool, sign: Bool, exponent: F32, +a: N.Wide, +b: N.Wide) -> N.Double:
  match zero:
    case True{}: N.Double{sign, 0.0, N.Wide.zero()}
    case False{}:
      +above = N.Wide.ge(a, b)
      numerator = Bool.pick(N.Wide, above, a, N.Wide.shl1(a))
      signed(sign, N.Double.recip.round((exponent - Bool.pick(F32, above, 0.0, 1.0) : F32), b,
        N.Double.divide.loop(52n, b, (N.Wide.sub(numerator, b), N.Wide{0, 1}))))

def divide(a: N.Double, b: N.Double) -> N.Double:
  N.Double{as, ae, +am} = a
  N.Double{bs, be, bm} = b
  divide.ready(N.Wide.is_zero(am), Bool.xor(as, bs), (ae - be : F32), am, bm)
