# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Binary32 fused multiply-add for every input class: fmaf(a, b, c) rounded once
# to nearest even, including signed zeros, subnormal operands and results,
# overflow, infinities and NaN. Significands are exact integers (two U32 limbs);
# no host FMA, binary64 arithmetic or double rounding is used.
import Base
import ./resize_numeric.bend as N

def float(word: U32) -> F32:
  U32{bits} = word
  F32{bits}

def magnitude(+bits: U32) -> U32:
  (bits .&. 2147483647 : U32)

def stored(+bits: U32) -> U32:
  ((bits >> 23n) .&. 255 : U32)

def negative(+bits: U32) -> Bool:
  (bits >= 2147483648 : U32)

# A finite nonzero |x| is significand(x) * 2^(exponent(x) - 150).
def significand(+bits: U32) -> U32:
  +fraction = (bits .&. 8388607 : U32)
  Bool.pick(U32, U32.is_eq(stored(bits), 0), fraction, (fraction .|. 8388608 : U32))

def exponent(+bits: U32) -> U32:
  +field = stored(bits)
  Bool.pick(U32, U32.is_eq(field, 0), 1, field)

# Exact product of two significands below 2^24, from 12-bit halves.
def product(+x: U32, +y: U32) -> N.Wide:
  +x1 = (x >> 12n : U32)
  +x0 = (x .&. 4095 : U32)
  +y1 = (y >> 12n : U32)
  +y0 = (y .&. 4095 : U32)
  +high = (x1 * y1 : U32)
  +middle = (x1 * y0 + x0 * y1 : U32)
  N.Wide.add(N.Wide.add(N.Wide{(high >> 8n : U32), (high << 24n : U32)},
    N.Wide{(middle >> 20n : U32), (middle << 12n : U32)}), N.Wide{0, (x0 * y0 : U32)})

# Index of the highest set bit of a nonzero value.
def top(value: N.Wide) -> U32:
  N.Wide{+high, +low} = value
  Bool.pick(U32, U32.is_eq(high, 0), U32.from_nat(U32.log2(low)), (32 + U32.from_nat(U32.log2(high)) : U32))

# A signed term value * 2^(scale - 400) whose top bit is at index 61.
type Term is Data:
  Term{negative: Bool, value: N.Wide, scale: U32}

def term(negative: Bool, +value: N.Wide, +exponent: U32) -> Term:
  +shift = (61 - top(value) : U32)
  Term{negative, N.Wide.shl(U32.to_nat(shift), value), (exponent + 100 - shift : U32)}

# Keep two extra bits (half and sticky) below the result's last place: right
# shifts jam the discarded bits; left shifts are exact.
def shifted(right: Bool, +drop: U32, value: N.Wide) -> N.Wide:
  match right:
    case True{}: N.Wide.jam(U32.to_nat((drop - 66 : U32)), value)
    case False{}: N.Wide.shl(U32.to_nat((66 - drop : U32)), value)

def rounded(value: N.Wide) -> U32:
  N.Wide{_, +low} = value
  +kept = (low >> 2n : U32)
  +tail = (low .&. 3 : U32)
  (kept + Bool.to_u32(((tail > 2) || (U32.is_eq(tail, 2) && U32.is_ne((kept .&. 1 : U32), 0)) : U32)) : U32)

def pack(sign: Bool, +biased: U32, +significand: U32) -> F32:
  +word = Bool.pick(U32, (biased >= 255 : U32), 2139095040, U32.min(((biased << 23n) + significand : U32), 2139095040))
  float(Bool.pick(U32, sign, (word .|. 2147483648 : U32), word))

# Rounds total * 2^(scale - 400) to binary32. With t its top bit, the result is
# normal when t + scale >= 274; the last place is 2^-149 for subnormals. drop
# is the number of discarded bits plus 64 (it is negative for small totals).
def round(zero: Bool, sign: Bool, +total: N.Wide, +scale: U32) -> F32:
  match zero:
    case True{}: 0.0
    case False{}:
      +t = top(total)
      +sum = (t + scale : U32)
      +normal = (sum >= 274 : U32)
      +drop = Bool.pick(U32, normal, (t + 41 : U32), (315 - scale : U32))
      pack(sign, Bool.pick(U32, normal, (sum - 274 : U32), 0), rounded(shifted((drop >= 66 : U32), drop, total)))

# Aligns the smaller term with a sticky bit. A difference only cancels many
# leading bits when the scales differ by at most one, and then no set bit is
# discarded (each term has at least 14 low zero bits), so the sum is exact or
# keeps at least 36 bits below the result's precision.
def sum(+sign: Bool, +large: N.Wide, +scale: U32, other: Bool, small: N.Wide, +small_scale: U32) -> F32:
  +aligned = N.Wide.jam(U32.to_nat(U32.min((scale - small_scale : U32), 63)), small)
  +total = Bool.pick(N.Wide, Bool.xor(sign, other), N.Wide.sub(large, aligned), N.Wide.add(large, aligned))
  round(N.Wide.is_zero(total), sign, total, scale)

def ordered(p: Term, q: Term) -> F32:
  Term{+ps, +pv, +px} = p
  Term{+qs, +qv, +qx} = q
  +first = ((px > qx) || (U32.is_eq(px, qx) && N.Wide.ge(pv, qv)) : U32)
  sum(Bool.pick(Bool, first, ps, qs), Bool.pick(N.Wide, first, pv, qv), Bool.pick(U32, first, px, qx),
    Bool.pick(Bool, first, qs, ps), Bool.pick(N.Wide, first, qv, pv), Bool.pick(U32, first, qx, px))

# Finite nonzero a, b and c: exact product and sum, one rounding.
def exact(+a: U32, +b: U32, +c: U32) -> F32:
  ordered(term(Bool.xor(negative(a), negative(b)), product(significand(a), significand(b)), (exponent(a) + exponent(b) : U32)),
    term(negative(c), N.Wide{0, significand(c)}, (exponent(c) + 150 : U32)))

# 0: a NaN, an infinite or zero factor, or a NaN addend; the product is then
# exact (or NaN/infinite) and a*b + c rounds once. 1: finite nonzero factors
# and an infinite addend give the addend. 2: a zero addend gives the rounded
# product with its own sign. 3: everything finite and nonzero.
def kind(+x: U32, +y: U32, +z: U32) -> U32:
  +simple = ((x >= 2139095040) || (y >= 2139095040) || U32.is_eq(x, 0) || U32.is_eq(y, 0) || (z > 2139095040) : U32)
  Bool.pick(U32, simple, 0, Bool.pick(U32, U32.is_eq(z, 2139095040), 1, Bool.pick(U32, U32.is_eq(z, 0), 2, 3)))

def route(kind: U32, +a: F32, +b: F32, +c: F32) -> F32:
  match kind:
    case 0: (a * b + c : F32)
    case 1: c
    case 2: (a * b : F32)
    case _: exact(F32.bits(a), F32.bits(b), F32.bits(c))

def multiply_add(+a: F32, +b: F32, +c: F32) -> F32:
  route(kind(magnitude(F32.bits(a)), magnitude(F32.bits(b)), magnitude(F32.bits(c))), a, b, c)
