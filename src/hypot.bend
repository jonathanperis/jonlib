# Original work: zlib, Copyright (c) 2026 Jonathan Peris.
# Whether the C library's hypot(x, y) <= r, for binary32 x, y and r promoted
# to binary64 as C promotes them. No hypot is reproduced: the answer is the
# one every faithful hypot gives (a result that is one of the two doubles
# around the exact value, an error below one unit in the last place; glibc
# 2.39 states about 0.792 ULP, or 0.948 with FMA), and None where two faithful
# results could disagree.
#   exact x*x + y*y <= r*r: sqrt of it is at most r, so both doubles around
#     it are: True;
#   exact x*x + y*y >= R*R for R the double after r: both are above r: False;
#   between them: None.
# The squares of binary32 values are exact in binary64 (48 bits). Their sum s
# is rounded once, so s < r*r and s > r*r decide the exact order (rounding is
# monotonic and r*r is a double); for s == r*r the rounding error of the sum
# (Dekker's b - (s - a) for |a| >= |b|, exact) gives the side. False needs
# s >= r*r*(1 + 2^-50): the exact sum is then above r*r*(1 + 2^-51 + 2^-104),
# which bounds R*R. Every operation goes through the checked helpers, so a
# magnitude from 2^64 on is None, like a NaN or an infinity.
import Base
import ./binary64_fma.bend as F
import ./binary64_add_sub.bend as A
import ./binary64_ops.bend as O

type V is Data:
  Ok{high: U32, low: U32}
  Bad{}

def lift(result: Maybe<F.Words>) -> V:
  match result:
    case Some{F.Words{high, low}}: Ok{high, low}
    case None{}: Bad{}

def mul(a: V, b: V) -> V:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: lift(O.checked_multiply(ah, al, bh, bl))
    case _ _: Bad{}

def add(a: V, b: V) -> V:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: lift(A.checked_add(ah, al, bh, bl))
    case _ _: Bad{}

def sub(a: V, b: V) -> V:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: lift(A.checked_sub(ah, al, bh, bl))
    case _ _: Bad{}

def promote(+bits: U32) -> V:
  lift(O.checked_promote(bits))

def known(value: V) -> Bool:
  match value:
    case Ok{_, _}: True{}
    case Bad{}: False{}

# The order of two non-negative values: 0 equal, 1 less, 2 greater; 3 when
# either is unknown.
def order(a: V, b: V) -> U32:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: O.magnitude_order(ah, al, bh, bl)
    case _ _: 3

# 0 for a zero or a negative value, 1 for a positive one, 3 when unknown.
def side(value: V) -> U32:
  match value:
    case Ok{+high, +low}: Bool.pick(U32, O.is_zero(high, low) || U32.is_ne((high .&. 2147483648 : U32), 0), 0, 1)
    case Bad{}: 3

# 2^-50.
def margin() -> V:
  Ok{1020264448, 0}

# s == r*r as doubles: the exact sum is on the side of its rounding error.
def within.equal(+error: U32) -> Maybe<Bool>:
  Bool.pick(Maybe<Bool>, U32.is_eq(error, 0), Some{True{}}, None{})

# s > r*r as doubles: False once s reaches r*r*(1 + 2^-50).
def within.above(+limit: U32) -> Maybe<Bool>:
  Bool.pick(Maybe<Bool>, U32.is_eq(limit, 0) || U32.is_eq(limit, 2), Some{False{}}, None{})

def within.ordered(+o: U32, +error: U32, +limit: U32) -> Maybe<Bool>:
  Bool.pick(Maybe<Bool>, U32.is_eq(o, 1), Some{True{}},
    Bool.pick(Maybe<Bool>, U32.is_eq(o, 0), within.equal(error),
      Bool.pick(Maybe<Bool>, U32.is_eq(o, 2), within.above(limit), None{})))

# a is the larger square and b the smaller one.
def within.sum(+s: V, +a: V, +b: V, +r2: V) -> Maybe<Bool>:
  within.ordered(order(s, r2), side(sub(b, sub(s, a))), order(s, add(r2, mul(r2, margin()))))

def within.squares(+x2: V, +y2: V, +r2: V) -> Maybe<Bool>:
  Bool.pick(Maybe<Bool>, U32.is_eq(order(x2, y2), 1), within.sum(add(x2, y2), y2, x2, r2), within.sum(add(x2, y2), x2, y2, r2))

# A negative r (not -0) is below every hypot of finite x and y.
def within.finite(negative: Bool, +x: V, +y: V, +r: V) -> Maybe<Bool>:
  match negative:
    case True{}: Bool.pick(Maybe<Bool>, known(x) && known(y) && known(r), Some{False{}}, None{})
    case False{}: within.squares(mul(x, x), mul(y, y), mul(r, r))

def within.word(+x: U32, +y: U32, +r: U32) -> Maybe<Bool>:
  within.finite((r > 2147483648 : U32), promote(x), promote(y), promote(r))

def within(+x: F32, +y: F32, +r: F32) -> Maybe<Bool>:
  within.word(F32.bits(x), F32.bits(y), F32.bits(r))
