# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Private checked normal binary64 operations and canonical-word adapters.
# No existing consumers. See docs/BINARY64-OPS.md for the bounded contract.
import Base
import ./binary64_fma.bend as W
import ./resize_numeric.bend as N
import ./float64.bend as F
import ./float64_ops.bend as O

def exponent(high: U32) -> U32:
  ((high >> 20n) .&. 2047 : U32)

def is_zero(high: U32, low: U32) -> Bool:
  U32.is_eq(((high .&. 2147483647) .|. low : U32), 0)

def is_finite(high: U32) -> Bool:
  U32.is_ne(exponent(high), 2047)

def checked_finite.valid(valid: Bool, high: U32, low: U32) -> Maybe<W.Words>:
  match valid:
    case False{}: None{}
    case True{}: Some{W.Words{high, low}}

# Finite construction admits subnormals as encodings, not arithmetic operands.
def checked_finite(+high: U32, low: U32) -> Maybe<W.Words>:
  checked_finite.valid(is_finite(high), high, low)

def checked_decode.valid(valid: Bool, high: U32, low: U32) -> Maybe<N.Double>:
  match valid:
    case False{}: None{}
    case True{}: Some{F.number(high, low)}

# The old decoder alone does not validate normalized significands. This raw-word
# boundary rejects nonzero subnormals and specials before calling it.
def checked_decode(+high: U32, +low: U32) -> Maybe<N.Double>:
  checked_decode.valid(W.valid(high, low, 1, 2046), high, low)

# Internal exact pack: requires signed zero or canonical normal Double with
# integral E in [-1022,1023] and 2^52 <= M < 2^53. It never rounds/scales M.
# F32 is used only for small integral exponent bookkeeping, which is exact.
def encode(value: N.Double) -> W.Words:
  N.Double{sign, exponent, N.Wide{+high, +low}} = value
  stored = Bool.pick(U32, U32.is_eq((high .|. low : U32), 0), 0,
    F32.to_u32((exponent + 1023.0 : F32)))
  W.Words{((Bool.to_u32(sign) << 31n) .|. (stored << 20n) .|. (high .&. 1048575) : U32), low}

def checked_identity.decoded(value: Maybe<N.Double>) -> Maybe<W.Words>:
  match value:
    case None{}: None{}
    case Some{number}: Some{encode(number)}

def checked_identity(high: U32, low: U32) -> Maybe<W.Words>:
  checked_identity.decoded(checked_decode(high, low))

def promoted_words(pair: U32 & U32) -> W.Words:
  (high, low) = pair
  W.Words{high, low}

def promote_bits(value: U32) -> W.Words:
  U32{bits} = value
  promoted_words(F.promote(F32{bits}))

def checked_promote.valid(valid: Bool, bits: U32) -> Maybe<W.Words>:
  match valid:
    case False{}: None{}
    case True{}: Some{promote_bits(bits)}

# Exact finite F32 promotion, including subnormals and both zero signs.
# Never use the old normal-only N.Double.from_f32 adapter for this boundary.
def checked_promote(+bits: U32) -> Maybe<W.Words>:
  checked_promote.valid(U32.is_ne(((bits >> 23n) .&. 255 : U32), 255), bits)

def negate(high: U32, low: U32) -> W.Words:
  W.Words{(high .^. 2147483648 : U32), low}

# Absolute raw encoding order: 0 equal, 1 less, 2 greater. For finite inputs
# this is magnitude order. Special encodings have only their raw-word meaning.
def magnitude_order(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> U32:
  +a = (ah .&. 2147483647 : U32)
  +b = (bh .&. 2147483647 : U32)
  same = U32.is_eq(a, b) && U32.is_eq(al, bl)
  less = ((a < b) || (U32.is_eq(a, b) && (al < bl)) : U32)
  Bool.pick(U32, same, 0, Bool.pick(U32, less, 1, 2))

# Finite numerical equality, with +0 == -0. Any nonfinite operand gives False.
def numerical_equal(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Bool:
  is_finite(ah) && is_finite(bh) &&
    ((U32.is_eq(ah, bh) && U32.is_eq(al, bl)) || (is_zero(ah, al) && is_zero(bh, bl)))

# Modular unsigned encoding steps, NOT numerical nextafter. In particular an
# increment of a negative finite encoding increases its magnitude.
def increment(high: U32, +low: U32) -> W.Words:
  W.Words{(high + Bool.to_u32(U32.is_eq(low, 4294967295)) : U32), (low + 1 : U32)}

def decrement(high: U32, +low: U32) -> W.Words:
  W.Words{(high - Bool.to_u32(U32.is_eq(low, 0)) : U32), (low - 1 : U32)}

# Construct positive 2^(stored-1023); the stored exponent must be 1..2046.
def checked_power(+stored: U32) -> Maybe<W.Words>:
  checked_finite.valid(((stored >= 1) && (stored <= 2046) : U32), (stored << 20n : U32), 0)

def checked_multiply.valid(valid: Bool, ah: U32, al: U32, bh: U32, bl: U32) -> Maybe<W.Words>:
  match valid:
    case False{}: None{}
    case True{}: Some{encode(O.multiply(F.number(ah, al), F.number(bh, bl)))}

# Each nonzero input E in [-554,127]; two nonzero exponents sum to [-833,127].
# Stored sum is in [1213,2173]. Both operands are validated before zero handling.
# Exact product and RN-even result are normal; result E lies in [-833,128].
def checked_multiply(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<W.Words>:
  +sum = (exponent(ah) + exponent(bh) : U32)
  pair = is_zero(ah, al) || is_zero(bh, bl) || ((sum >= 1213) && (sum <= 2173) : U32)
  checked_multiply.valid(W.valid(ah, al, 469, 1150) && W.valid(bh, bl, 469, 1150) && pair,
    ah, al, bh, bl)

def checked_divide.valid(valid: Bool, ah: U32, al: U32, bh: U32, bl: U32) -> Maybe<W.Words>:
  match valid:
    case False{}: None{}
    case True{}: Some{encode(O.divide(F.number(ah, al), F.number(bh, bl)))}

# Numerator E in [-225,127] or zero, denominator NONZERO E in [-149,127].
# Nonzero numerator requires Ea <= Eb. The normal quotient E lies in [-353,0].
# Zero denominator is rejected even for 0/0; both input domains precede arithmetic.
def checked_divide(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<W.Words>:
  pair = is_zero(ah, al) || (exponent(ah) <= exponent(bh) : U32)
  checked_divide.valid(W.valid(ah, al, 798, 1150) && W.valid(bh, bl, 874, 1150) &&
    Bool.not(is_zero(bh, bl)) && pair, ah, al, bh, bl)
