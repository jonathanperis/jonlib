# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Private bounded binary64 addition/subtraction, one final RN-even pack.
# Each operand: signed zero or normal E in [-900,130]. No existing consumers.
import Base
import ./binary64_fma.bend as F

# Exact little-endian 34-U32 magnitudes in units of 2^-952. The input shift
# E+900 is in 0..1030; every term needs at most 1083 bits and the sum at most
# 1084 of the 1088 available bits. Never compress bits before cancellation.
# The imported list/word operations are width-independent; F.Magnitude.align
# and F.finish are NOT reused because their width and lattice are different.
def align(+shift: U32, values: +List<U32>) -> +List<U32>:
  +bits = (shift .&. 31 : U32)
  F.Magnitude.fit(34n, F.Magnitude.prefix(U32.to_nat((shift >> 5n : U32)),
    F.Magnitude.shift_ready(U32.is_eq(bits, 0), bits, values)))

def finish.top(info: F.Top, sign: U32, values: +List<U32>) -> F.Words:
  F.Top{found, +top} = info
  match found:
    case False{}: F.Words{sign, 0}
    case True{}: F.pack(sign, (top + 71 : U32), F.Magnitude.normalize((top >= 55 : U32), top, values))

def finish(sign: U32, +values: +List<U32>) -> F.Words:
  finish.top(F.Magnitude.top(values, 0, F.Top{False{}, 0}), sign, values)

def combine.opposite(+order: U32, sa: U32, sb: U32, +a: +List<U32>, +b: +List<U32>) -> F.Words:
  +less = U32.is_eq(order, 1)
  # Opposite signs with equal magnitudes cancel to +0, including mixed zeros.
  sign = Bool.pick(U32, U32.is_eq(order, 0), 0, Bool.pick(U32, less, sb, sa))
  finish(sign, Bool.pick(+List<U32>, less, F.Magnitude.sub(b, a, 0), F.Magnitude.sub(a, b, 0)))

def combine(same: Bool, sa: U32, sb: U32, +a: +List<U32>, +b: +List<U32>) -> F.Words:
  match same:
    case True{}: finish(sa, F.Magnitude.add(a, b, 0))
    case False{}: combine.opposite(F.Magnitude.order(a, b), sa, sb, a, b)

# Requires a checked normal or signed zero. Normal stored exponent e=E+1023
# gives lattice shift e-123; signed zero has zero significand and shift zero.
def magnitude(+high: U32, low: U32) -> +List<U32>:
  +exponent = ((high >> 20n) .&. 2047 : U32)
  shift = Bool.pick(U32, U32.is_eq(exponent, 0), 0, (exponent - 123 : U32))
  +mantissa = F.significand(high, low)
  mh = F.Words.high(mantissa)
  ml = F.Words.low(mantissa)
  align(shift, [ml, mh])

def calculate(+ah: U32, al: U32, +bh: U32, bl: U32) -> F.Words:
  +sa = (ah .&. 2147483648 : U32)
  +sb = (bh .&. 2147483648 : U32)
  combine(U32.is_eq(sa, sb), sa, sb, magnitude(ah, al), magnitude(bh, bl))

def checked.valid(accepted: Bool, ah: U32, al: U32, bh: U32, bl: U32) -> Maybe<F.Words>:
  match accepted:
    case False{}: None{}
    case True{}: Some{calculate(ah, al, bh, bl)}

# Both inputs are classified before arithmetic. Internal helpers remain private
# implementation details; their visibility does not establish a wider contract.
def checked_add(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<F.Words>:
  checked.valid(F.valid(ah, al, 123, 1153) && F.valid(bh, bl, 123, 1153), ah, al, bh, bl)

# Sign inversion preserves validity and implements subtraction, including -0.
def checked_sub(ah: U32, al: U32, bh: U32, bl: U32) -> Maybe<F.Words>:
  checked_add(ah, al, (bh .^. 2147483648 : U32), bl)
