# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Internal finite-normal binary64 arithmetic for resize coefficient normalization.
# Mantissas use integer limbs: round-to-nearest/even is explicit on every operation.
# No NaN, infinity, subnormal or general-purpose floating-point API is exposed.
import Base

type Wide is Data:
  Wide{hi: U32, lo: U32}

def Wide.zero() -> Wide:
  Wide{0, 0}

def Wide.is_zero(w: Wide) -> Bool:
  Wide{h, l} = w
  U32.is_eq((h .|. l : U32), 0)

def Wide.ge(a: Wide, b: Wide) -> Bool:
  Wide{+ah, al} = a
  Wide{+bh, bl} = b
  ((ah > bh) || (U32.is_eq(ah, bh) && (al >= bl)) : U32)

def Wide.eq(a: Wide, b: Wide) -> Bool:
  Wide{ah, al} = a
  Wide{bh, bl} = b
  U32.is_eq(ah, bh) && U32.is_eq(al, bl)

def Wide.odd(w: Wide) -> Bool:
  Wide{_, lo} = w
  U32.is_ne((lo .&. 1 : U32), 0)

def Wide.add(a: Wide, b: Wide) -> Wide:
  Wide{ah, +al} = a
  Wide{bh, bl} = b
  +lo = (al + bl : U32)
  Wide{(ah + bh + Bool.to_u32((lo < al : U32)) : U32), lo}

def Wide.sub(a: Wide, b: Wide) -> Wide:
  Wide{ah, +al} = a
  Wide{bh, +bl} = b
  Wide{(ah - bh - Bool.to_u32((al < bl : U32)) : U32), (al - bl : U32)}

def Wide.shl1(w: Wide) -> Wide:
  Wide{h, +l} = w
  Wide{((h << 1n) .|. (l >> 31n) : U32), (l << 1n : U32)}

def Wide.shr1(w: Wide) -> Wide:
  Wide{+h, l} = w
  Wide{(h >> 1n : U32), ((l >> 1n) .|. (h << 31n) : U32)}

def Wide.jam1(w: Wide) -> Wide:
  Wide{+h, +l} = w
  Wide{(h >> 1n : U32), ((l >> 1n) .|. (h << 31n) .|. (l .&. 1) : U32)}

def Wide.shl(n: Nat, w: Wide) -> Wide:
  match n:
    case 0n: w
    case 1n+k: Wide.shl(k, Wide.shl1(w))

def Wide.shr(n: Nat, w: Wide) -> Wide:
  match n:
    case 0n: w
    case 1n+k: Wide.shr(k, Wide.shr1(w))

def Wide.jam(n: Nat, w: Wide) -> Wide:
  match n:
    case 0n: w
    case 1n+k: Wide.jam(k, Wide.jam1(w))

def Wide.top(w: Wide) -> F32:
  Wide{+h, l} = w
  Bool.pick(F32, U32.is_eq(h, 0), F32.from_nat(U32.log2(l)), (32.0 + F32.from_nat(U32.log2(h)) : F32))

type Double is Data:
  Double{negative: Bool, exponent: F32, mantissa: Wide}

def Double.zero() -> Double:
  Double{False{}, 0.0, Wide.zero()}

def Double.carry(sign: Bool, +exponent: F32, mantissa: Wide) -> Double:
  Wide{+h, +l} = mantissa
  +carry = (h >= 2097152 : U32)
  Double{sign, (exponent + Bool.pick(F32, carry, 1.0, 0.0) : F32),
    Bool.pick(Wide, carry, Wide.shr1(Wide{h, l}), Wide{h, l})}

def Double.round(sign: Bool, exponent: F32, mantissa: Wide) -> Double:
  Wide{+h, +l} = mantissa
  +rest = (l .&. 7 : U32)
  +up = ((rest > 4) || (U32.is_eq(rest, 4) && U32.is_ne((l .&. 8 : U32), 0)) : U32)
  Double.carry(sign, exponent, Wide.add(Wide.shr(3n, Wide{h, l}), Wide{0, Bool.to_u32(up)}))

def Double.normalize.nonzero(zero: Bool, sign: Bool, +exponent: F32, +mantissa: Wide) -> Double:
  match zero:
    case True{}: Double.zero()
    case False{}:
      +shift = (Wide.top(mantissa) - 55.0 : F32)
      adjusted = Bool.pick(Wide, (shift >= 0.0 : F32),
        Wide.jam(F32.to_nat(F32.max(0.0, shift)), mantissa),
        Wide.shl(F32.to_nat(F32.max(0.0, F32.neg(shift))), mantissa))
      Double.round(sign, (exponent + shift : F32), adjusted)

def Double.normalize(sign: Bool, exponent: F32, +mantissa: Wide) -> Double:
  Double.normalize.nonzero(Wide.is_zero(mantissa), sign, exponent, mantissa)

def Double.from_f32(+value: F32) -> Double:
  +bits = F32.bits(value)
  +m = ((bits .&. 8388607) .|. Bool.pick(U32, F32.is_eq(value, 0.0), 0, 8388608) : U32)
  Double{(bits >= 2147483648 : U32), (U32.to_f32(((bits >> 23n) .&. 255 : U32)) - 127.0 : F32),
    Wide{(m >> 3n : U32), (m << 29n : U32)}}

def Double.add.sorted(a: Double, b: Double) -> Double:
  Double{+sign, +ae, am} = a
  Double{bs, be, bm} = b
  +big = Wide.shl(3n, am)
  +small = Wide.jam(F32.to_nat((ae - be : F32)), Wide.shl(3n, bm))
  value = Bool.pick(Wide, Bool.xor(sign, bs), Wide.sub(big, small), Wide.add(big, small))
  Double.normalize(sign, ae, value)

def Double.add.nonzero(az: Bool, bz: Bool, +a: Double, +b: Double) -> Double:
  match az bz:
    case True{} _: b
    case False{} True{}: a
    case False{} False{}:
      Double{+as, +ae, +am} = a
      Double{+bs, +be, +bm} = b
      +ordered = ((ae > be) || (F32.is_eq(ae, be) && Wide.ge(am, bm)) : F32)
      Double.add.sorted(Bool.pick(Double, ordered, Double{as, ae, am}, Double{bs, be, bm}),
        Bool.pick(Double, ordered, Double{bs, be, bm}, Double{as, ae, am}))

def Double.add(+a: Double, +b: Double) -> Double:
  Double{_, _, am} = a
  Double{_, _, bm} = b
  Double.add.nonzero(Wide.is_zero(am), Wide.is_zero(bm), a, b)

def Double.sum(values: +List<F32>, acc: Double) -> Double:
  match values:
    case Nil{}: acc
    case Con{v, rest}: Double.sum(rest, Double.add(acc, Double.from_f32(v)))

def Double.divide.step(+take: Bool, +numerator: Wide, +denominator: Wide, quotient: Wide) -> Wide & Wide:
  (Bool.pick(Wide, take, Wide.sub(numerator, denominator), numerator),
    Wide.add(Wide.shl1(quotient), Wide{0, Bool.to_u32(take)}))

def Double.divide.loop(n: Nat, +denominator: Wide, state: Wide & Wide) -> Wide & Wide:
  match n state:
    case 0n _: state
    case 1n+k Tuple{remainder, quotient}:
      +next = Wide.shl1(remainder)
      Double.divide.loop(k, denominator, Double.divide.step(Wide.ge(next, denominator), next, denominator, quotient))

def Double.recip.round(exponent: F32, +denominator: Wide, state: Wide & Wide) -> Double:
  (remainder, +quotient) = state
  +twice = Wide.shl1(remainder)
  up = Wide.ge(twice, denominator) && (Bool.not(Wide.eq(twice, denominator)) || Wide.odd(quotient))
  Double.carry(False{}, exponent, Wide.add(quotient, Wide{0, Bool.to_u32(up)}))

def Double.recip.route(power: Bool, +exponent: F32, +mantissa: Wide) -> Double:
  match power:
    case True{}: Double{False{}, F32.neg(exponent), mantissa}
    case False{}:
      Double.recip.round((0.0 - exponent - 1.0 : F32), mantissa,
        Double.divide.loop(53n, mantissa, (Wide{1048576, 0}, Wide.zero())))

def Double.recip(value: Double) -> Double:
  Double{_, exponent, +mantissa} = value
  Double.recip.route(Wide.eq(mantissa, Wide{1048576, 0}), exponent, mantissa)

type Product is Data:
  Product{hi: U32, mid: U32, lo: U32}

def Product.add(a: Product, b: Product) -> Product:
  Product{ah, +am, +al} = a
  Product{bh, bm, bl} = b
  +lo = (al + bl : U32)
  +mid0 = (am + bm : U32)
  +mid = (mid0 + Bool.to_u32((lo < al : U32)) : U32)
  Product{(ah + bh + Bool.to_u32((mid0 < am : U32)) + Bool.to_u32((mid < mid0 : U32)) : U32), mid, lo}

def Product.shl(value: Product) -> Product:
  Product{h, +m, +l} = value
  Product{((h << 1n) .|. (m >> 31n) : U32), ((m << 1n) .|. (l >> 31n) : U32), (l << 1n : U32)}

def Product.mul(n: Nat, +bits: U32, +multiplicand: Product, +acc: Product) -> Product:
  match n:
    case 0n: acc
    case 1n+k:
      Product.mul(k, (bits >> 1n : U32), Product.shl(multiplicand),
        Bool.pick(Product, U32.is_ne((bits .&. 1 : U32), 0), Product.add(acc, multiplicand), acc))

def Double.product(sign: Bool, +exponent: F32, product: Product) -> Double:
  Product{+h, +m, +l} = product
  +shift = (32n + U32.log2(h) - 23n : Nat)
  +back = (32n - shift : Nat)
  +mask = (U32.shln(1, shift) - 1 : U32)
  mantissa = {Wide{(U32.shrn(m, shift) .|. U32.shln(h, back) : U32),
    (U32.shrn(l, shift) .|. U32.shln(m, back) .|. Bool.to_u32(U32.is_ne((l .&. mask : U32), 0)) : U32)} : Wide}
  Double.round(sign, (exponent + F32.from_nat(U32.log2(h)) - 11.0 : F32), mantissa)

def Double.mul.nonzero(zero: Bool, +value: F32, multiplier: Double) -> Double:
  match zero:
    case True{}: Double.zero()
    case False{}:
      Double{sign, exponent, mantissa} = multiplier
      Wide{h, l} = mantissa
      +bits = F32.bits(value)
      significand = ((bits .&. 8388607) .|. 8388608 : U32)
      Double.product(Bool.xor(sign, (bits >= 2147483648 : U32)),
        (exponent + U32.to_f32(((bits >> 23n) .&. 255 : U32)) - 127.0 : F32),
        Product.mul(24n, significand, Product{0, h, l}, Product{0, 0, 0}))

def Double.mul_f32(+value: F32, multiplier: Double) -> Double:
  Double.mul.nonzero(F32.is_eq(value, 0.0), value, multiplier)

def scale2(n: Nat, +factor: F32, value: F32) -> F32:
  match n:
    case 0n: value
    case 1n+k: scale2(k, factor, (value * factor : F32))

def Double.to_f32(value: Double) -> F32:
  Double{sign, exponent, mantissa} = value
  Wide{h, +l} = mantissa
  +significand = ((h << 3n) .|. (l >> 29n) : U32)
  +rest = (l .&. 536870911 : U32)
  up = ((rest > 268435456) || (U32.is_eq(rest, 268435456) && U32.is_ne((significand .&. 1 : U32), 0)) : U32)
  +power = (exponent - 23.0 : F32)
  +result = scale2(F32.to_nat(F32.abs(power)), Bool.pick(F32, (power < 0.0 : F32), 0.5, 2.0),
    U32.to_f32((significand + Bool.to_u32(up) : U32)))
  Bool.pick(F32, sign, F32.neg(result), result)

def normalize.map(values: +List<F32>, +scale: Double, acc: +List<F32>) -> +List<F32>:
  match values:
    case Nil{}: List.reverse(&2, F32, acc)
    case Con{value, rest}:
      normalize.map(rest, scale, Con{Double.to_f32(Double.mul_f32(value, scale)), acc})

def normalize(+values: +List<F32>) -> +List<F32>:
  normalize.map(values, Double.recip(Double.sum(values, Double.zero())), Nil{})
