# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# binary64 time values for the explicit clock of rcore.c's frame timing and
# rgestures.h: canonical IEEE words, operated through the checked binary64
# helpers (src/binary64_*.bend, docs/BINARY64.md). Every operation is None
# outside those helpers' domains (sums/differences of zero or normal operands
# with exponents in [-900, 130]); see docs/INPUT.md.
import Base
import ./binary64_fma.bend as W
import ./binary64_add_sub.bend as AddSub
import ./binary64_ops.bend as Ops
import ./binary64_narrow.bend as Narrow

def zero() -> W.Words:
  W.Words{0, 0}

def high(+value: W.Words) -> U32:
  W.Words{high, _} = value
  high

def low(+value: W.Words) -> U32:
  W.Words{_, low} = value
  low

def finite(+value: W.Words) -> Bool:
  Ops.is_finite(high(value))

def is_zero(+value: W.Words) -> Bool:
  Ops.is_zero(high(value), low(value))

def add(+a: W.Words, +b: W.Words) -> Maybe<W.Words>:
  AddSub.checked_add(high(a), low(a), high(b), low(b))

def sub(+a: W.Words, +b: W.Words) -> Maybe<W.Words>:
  AddSub.checked_sub(high(a), low(a), high(b), low(b))

def divide(+a: W.Words, +b: W.Words) -> Maybe<W.Words>:
  Ops.checked_divide(high(a), low(a), high(b), low(b))

def multiply(+a: W.Words, +b: W.Words) -> Maybe<W.Words>:
  Ops.checked_multiply(high(a), low(a), high(b), low(b))

def from_bits(+bits: U32) -> F32:
  U32{b} = bits
  F32{b}

def narrow.word(word: Maybe<U32>) -> Maybe<F32>:
  match word:
    case None{}: None{}
    case Some{bits}: Some{from_bits(bits)}

# (float)value, round to nearest even; None for infinities and NaN.
def narrow(+value: W.Words) -> Maybe<F32>:
  narrow.word(Narrow.checked(high(value), low(value)))

# (double)value; None for infinities and NaN.
def promote(+value: F32) -> Maybe<W.Words>:
  Ops.checked_promote(F32.bits(value))

# Order of finite values: 0 equal (including +0 and -0), 1 less, 2 greater.
def order.signed(+negative: Bool, +magnitude: U32) -> U32:
  match negative:
    case False{}: magnitude
    case True{}: Bool.pick(U32, U32.is_eq(magnitude, 0), 0, (3 - magnitude : U32))

def sign(+value: W.Words) -> U32:
  Bool.pick(U32, is_zero(value), 0, (high(value) >> 31n : U32))

def order(+a: W.Words, +b: W.Words) -> U32:
  +sa = sign(a)
  +sb = sign(b)
  Bool.pick(U32, U32.is_eq(sa, sb),
    order.signed(U32.is_eq(sa, 1), Ops.magnitude_order(Bool.pick(U32, is_zero(a), 0, high(a)), low(a), Bool.pick(U32, is_zero(b), 0, high(b)), low(b))),
    Bool.pick(U32, U32.is_eq(sa, 1), 1, 2))

def less(+a: W.Words, +b: W.Words) -> Bool:
  U32.is_eq(order(a, b), 1)

def greater(+a: W.Words, +b: W.Words) -> Bool:
  U32.is_eq(order(a, b), 2)

# Exact (double)n of a positive C int (1..2^31-1): significand bits split at
# the word boundary by the shift 52 - floor(log2 n) (22..52).
def from_positive.words(wide: Bool, +n: U32, +shift: U32) -> U32 & U32:
  match wide:
    case True{}: ((n << U32.to_nat((shift - 32 : U32)) : U32), 0)
    case False{}: ((n >> U32.to_nat((32 - shift : U32)) : U32), (n << U32.to_nat(shift) : U32))

def from_positive.pack(+top: U32, parts: U32 & U32) -> W.Words:
  (fraction_high, fraction_low) = parts
  W.Words{(((top + 1023) << 20n) .|. (fraction_high .&. 1048575) : U32), fraction_low}

def from_positive.top(+n: U32, +top: U32) -> W.Words:
  from_positive.pack(top, from_positive.words(((52 - top) >= 32 : U32), n, (52 - top : U32)))

def from_positive(+n: U32) -> W.Words:
  from_positive.top(n, U32.from_nat(U32.log2(n)))

def one() -> W.Words:
  W.Words{1072693248, 0}
