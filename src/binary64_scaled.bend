# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Private binary64 arithmetic over every normal exponent, by exact power-of-two
# scaling around the bounded checked helpers (docs/BINARY64.md): operands are
# moved to exponents inside the helper's domain, the helper rounds once, and
# the result is moved back. Scaling by 2^k is exact for normal values and
# commutes with rounding to nearest, so the result is the operation's single
# rounding whenever it is normal. Signed zeros follow IEEE (x + 0 = x, sign
# XOR for products and quotients). Refused with None: nonzero subnormal,
# infinite and NaN operands, zero divisors, results that would be subnormal or
# overflow, and sums/FMA addends too far below the other term for the helper
# domain (exponent gap above 900 bits for addition, FMA addend outside
# [-554, 255] relative to the product); callers must stay clear of them.
import Base
import ./binary64_fma.bend as F
import ./binary64_add_sub.bend as A
import ./binary64_ops.bend as O

def stored(+high: U32) -> U32:
  ((high >> 20n) .&. 2047 : U32)

# 0: signed zero; 1: normal; 2: nonzero subnormal, infinity or NaN.
def kind(+high: U32, +low: U32) -> U32:
  +e = stored(high)
  Bool.pick(U32, U32.is_eq(e, 0), Bool.pick(U32, U32.is_eq(((high .&. 1048575) .|. low : U32), 0), 0, 2),
    Bool.pick(U32, U32.is_eq(e, 2047), 2, 1))

# The same sign and significand with stored exponent e (1..2046).
def with_stored(+high: U32, +e: U32) -> U32:
  ((high .&. 2148532223) .|. (e << 20n) : U32)

def sign(+high: U32) -> U32:
  (high .&. 2147483648 : U32)

def zero(+sign: U32) -> Maybe<F.Words>:
  Some{F.Words{sign, 0}}

def rescale.word(valid: Bool, +high: U32, +low: U32, +e: U32) -> Maybe<F.Words>:
  match valid:
    case False{}: None{}
    case True{}: Some{F.Words{with_stored(high, e), low}}

# A normal helper result with stored exponent e, moved to e + plus - minus;
# None unless that is in 1..2046. A zero result is returned unchanged.
def rescale.at(+high: U32, +low: U32, +plus: U32, +minus: U32) -> Maybe<F.Words>:
  +total = (stored(high) + plus : U32)
  +zero = U32.is_eq(((high .&. 2147483647) .|. low : U32), 0)
  +valid = zero || ((total >= (minus + 1)) && (total <= (minus + 2046)) : U32)
  Bool.pick(Maybe<F.Words>, zero, Some{F.Words{high, low}}, rescale.word(valid, high, low, (total - minus : U32)))

def rescale(result: Maybe<F.Words>, +plus: U32, +minus: U32) -> Maybe<F.Words>:
  match result:
    case None{}: None{}
    case Some{F.Words{+high, +low}}: rescale.at(high, low, plus, minus)

# ---------------------------------------------------------------------------
# Multiplication

def multiply.normal(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<F.Words>:
  rescale(O.checked_multiply(with_stored(ah, 1023), al, with_stored(bh, 1023), bl), (stored(ah) + stored(bh) : U32), 2046)

def multiply.at(code: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<F.Words>:
  match code:
    case 0: zero(sign((ah .^. bh : U32)))
    case 1: zero(sign((ah .^. bh : U32)))
    case 3: zero(sign((ah .^. bh : U32)))
    case 4: multiply.normal(ah, al, bh, bl)
    case _: None{}

def multiply(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<F.Words>:
  multiply.at((kind(ah, al) * 3 + kind(bh, bl) : U32), ah, al, bh, bl)

# ---------------------------------------------------------------------------
# Division

def divide.normal(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<F.Words>:
  rescale(O.checked_divide(with_stored(ah, 1023), al, with_stored(bh, 1023), bl), stored(ah), stored(bh))

def divide.at(code: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<F.Words>:
  match code:
    case 1: zero(sign((ah .^. bh : U32)))
    case 4: divide.normal(ah, al, bh, bl)
    case _: None{}

def divide(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<F.Words>:
  divide.at((kind(ah, al) * 3 + kind(bh, bl) : U32), ah, al, bh, bl)

# ---------------------------------------------------------------------------
# Addition and subtraction

# Both normal: the larger exponent m moves to 1023 and the other must keep a
# stored exponent of at least 123 (the helper's E >= -900).
def add.shifted(valid: Bool, +ah: U32, +al: U32, +bh: U32, +bl: U32, +m: U32) -> Maybe<F.Words>:
  match valid:
    case False{}: None{}
    case True{}:
      rescale(A.checked_add(with_stored(ah, (stored(ah) + 1023 - m : U32)), al, with_stored(bh, (stored(bh) + 1023 - m : U32)), bl), m, 1023)

def add.normal(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<F.Words>:
  +ea = stored(ah)
  +eb = stored(bh)
  +m = U32.max(ea, eb)
  add.shifted(((ea + 900) >= m) && ((eb + 900) >= m) : U32), ah, al, bh, bl, m)

def add.at(code: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<F.Words>:
  match code:
    case 0: A.checked_add(ah, al, bh, bl)
    case 1: Some{F.Words{bh, bl}}
    case 3: Some{F.Words{ah, al}}
    case 4: add.normal(ah, al, bh, bl)
    case _: None{}

def add(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<F.Words>:
  add.at((kind(ah, al) * 3 + kind(bh, bl) : U32), ah, al, bh, bl)

def subtract(+ah: U32, +al: U32, bh: U32, +bl: U32) -> Maybe<F.Words>:
  add(ah, al, (bh .^. 2147483648 : U32), bl)

# ---------------------------------------------------------------------------
# Fused multiply-add: a*b + c rounded once.

# a, b normal at exponent 0; c at exponent Ec - Ea - Eb, which must be in the
# helper's [-554, 255] (stored 469..1278).
def fma.shifted(valid: Bool, +ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> Maybe<F.Words>:
  match valid:
    case False{}: None{}
    case True{}:
      +product = (stored(ah) + stored(bh) : U32)
      rescale(F.checked(with_stored(ah, 1023), al, with_stored(bh, 1023), bl, with_stored(ch, (stored(ch) + 2046 - product : U32)), cl), product, 2046)

def fma.normal(+ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> Maybe<F.Words>:
  +product = (stored(ah) + stored(bh) : U32)
  +total = (stored(ch) + 2046 : U32)
  fma.shifted(((total >= (product + 469)) && (total <= (product + 1278)) : U32), ah, al, bh, bl, ch, cl)

# code = 3*product_kind + kind(c), product_kind 0 (a zero product of finite
# factors), 1 (two normal factors) or 2 (refused).
def fma.at(code: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> Maybe<F.Words>:
  match code:
    case 0: add(sign((ah .^. bh : U32)), 0, ch, cl)
    case 1: Some{F.Words{ch, cl}}
    case 3: multiply(ah, al, bh, bl)
    case 4: fma.normal(ah, al, bh, bl, ch, cl)
    case _: None{}

def product.kind(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a > 1 : U32) || (b > 1 : U32), 2, Bool.pick(U32, U32.is_eq(a, 0) || U32.is_eq(b, 0), 0, 1))

def fma(+ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> Maybe<F.Words>:
  fma.at((product.kind(kind(ah, al), kind(bh, bl)) * 3 + kind(ch, cl) : U32), ah, al, bh, bl, ch, cl)
