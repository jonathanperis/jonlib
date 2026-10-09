# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Private binary64 square root of a signed zero or positive normal, rounded
# once to nearest even. Integer arithmetic only: an exact bit-by-bit integer
# square root of the scaled significand, then the shared binary64 pack.
import Base
import ./binary64_fma.bend as F

# A 128-bit unsigned value, most significant limb first.
type Quad is Data:
  Quad{d: U32, c: U32, b: U32, a: U32}

def Quad.add(x: Quad, y: Quad) -> Quad:
  Quad{xd, +xc, +xb, +xa} = x
  Quad{yd, yc, yb, ya} = y
  +a = (xa + ya : U32)
  +b0 = (xb + yb : U32)
  +b = (b0 + Bool.to_u32((a < xa : U32)) : U32)
  +cb = Bool.to_u32(((b0 < xb) || (b < b0) : U32))
  +c0 = (xc + yc : U32)
  +c = (c0 + cb : U32)
  +cc = Bool.to_u32(((c0 < xc) || (c < c0) : U32))
  Quad{(xd + yd + cc : U32), c, b, a}

def Quad.sub(x: Quad, y: Quad) -> Quad:
  Quad{xd, +xc, +xb, +xa} = x
  Quad{yd, +yc, +yb, +ya} = y
  +a = (xa - ya : U32)
  +ab = Bool.to_u32((xa < ya : U32))
  +b0 = (xb - yb : U32)
  +b = (b0 - ab : U32)
  +bb = Bool.to_u32(((xb < yb) || (b0 < ab) : U32))
  +c0 = (xc - yc : U32)
  +c = (c0 - bb : U32)
  +cb = Bool.to_u32(((xc < yc) || (c0 < bb) : U32))
  Quad{(xd - yd - cb : U32), c, b, a}

# x >= y, from the most significant limb down.
def Quad.ge(x: Quad, y: Quad) -> Bool:
  Quad{+xd, +xc, +xb, +xa} = x
  Quad{+yd, +yc, +yb, +ya} = y
  +low = (xb > yb : U32) || (U32.is_eq(xb, yb) && (xa >= ya : U32))
  +middle = (xc > yc : U32) || (U32.is_eq(xc, yc) && low)
  (xd > yd : U32) || (U32.is_eq(xd, yd) && middle)

def Quad.shr1(x: Quad) -> Quad:
  Quad{+d, +c, +b, a} = x
  Quad{(d >> 1n : U32), ((c >> 1n) .|. (d << 31n) : U32), ((b >> 1n) .|. (c << 31n) : U32), ((a >> 1n) .|. (b << 31n) : U32)}

def Quad.shr(count: Nat, x: Quad) -> Quad:
  match count:
    case 0n: x
    case 1n+rest: Quad.shr(rest, Quad.shr1(x))

def Quad.is_zero(x: Quad) -> Bool:
  Quad{d, c, b, a} = x
  U32.is_eq((d .|. c .|. b .|. a : U32), 0)

type Root is Data:
  Root{root: Quad, remainder: Quad}

# Restoring integer square root: with bit running over the powers of four
# from 2^108 down to 1, root ends as floor(sqrt(N)) and remainder as
# N - root^2.
def Root.step(count: Nat, +remainder: Quad, +root: Quad, +bit: Quad) -> Root:
  match count:
    case 0n: Root{root, remainder}
    case 1n+rest:
      +trial = Quad.add(root, bit)
      +take = Quad.ge(remainder, trial)
      +half = Quad.shr1(root)
      Root.step(rest, Bool.pick(Quad, take, Quad.sub(remainder, trial), remainder),
        Bool.pick(Quad, take, Quad.add(half, bit), half), Quad.shr(2n, bit))

# root is in [2^54, 2^55): its 53 leading bits, two more and the sticky
# remainder form the 56-bit window of F.pack.
def window(result: Root) -> F.Words:
  Root{Quad{_, _, +b, +a}, remainder} = result
  sticky = Bool.to_u32(Bool.not(Quad.is_zero(remainder)))
  F.Words{((b << 1n) .|. (a >> 31n) : U32), ((a << 1n) .|. sticky : U32)}

# For a positive normal M * 2^(E-52): N = M * 2^56 (E even) or M * 2^57
# (E odd), so N is in [2^108, 2^110) and sqrt(x) = sqrt(N) * 2^(floor(E/2) - 54).
# With e = E + 1023 stored, E is even exactly when e is odd, and the stored
# result exponent is floor(E/2) + 1023 = (e + 1022 + (e & 1)) / 2.
def positive(+high: U32, low: U32) -> F.Words:
  +stored = ((high >> 20n) .&. 2047 : U32)
  +odd = U32.is_eq((stored .&. 1 : U32), 1)
  +mantissa = F.significand(high, low)
  +n = Quad.shr(Bool.pick(Nat, odd, 8n, 7n), Quad{F.Words.high(mantissa), F.Words.low(mantissa), 0, 0})
  F.pack(0, ((stored + 1022 + (stored .&. 1)) >> 1n : U32),
    window(Root.step(55n, n, Quad{0, 0, 0, 0}, Quad{4096, 0, 0, 0})))

# 0 signed zero, 1 positive normal, 2 rejected (negative nonzero, subnormal,
# infinity, NaN).
def kind(+high: U32, +low: U32) -> U32:
  +stored = ((high >> 20n) .&. 2047 : U32)
  Bool.pick(U32, U32.is_eq(((high .&. 2147483647) .|. low : U32), 0), 0,
    Bool.pick(U32, ((high < 2147483648) && (stored >= 1) && (stored <= 2046) : U32), 1, 2))

def checked.at(kind: U32, +high: U32, +low: U32) -> Maybe<F.Words>:
  match kind:
    case 0: Some{F.Words{high, low}}
    case 1: Some{positive(high, low)}
    case _: None{}

# sqrt of a binary64 word pair: signed zeros are returned unchanged (IEEE
# sqrt(-0) = -0); every positive normal is accepted and its root is normal.
# Negative nonzero, subnormal and nonfinite inputs return None.
def checked(+high: U32, +low: U32) -> Maybe<F.Words>:
  checked.at(kind(high, low), high, low)
