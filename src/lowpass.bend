# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the low-pass filter coefficients of miniaudio
# v0.11.24's linear resampler (ma_linear_resampler_set_rate_internal,
# ma_lpf_reinit__internal with order 4, ma_lpf2__get_biquad_config and
# ma_biquad_reinit), as raylib 6.0 vendors it in src/external/miniaudio.h.
# miniaudio: David Reid, public domain or MIT No Attribution; see
# THIRD_PARTY_NOTICES.md and LICENSES/miniaudio.txt.
#
# miniaudio computes the coefficients in binary64 with libm sin(). Every
# binary64 operation here goes through the checked helpers (each rounds once,
# to nearest even). sin() is not reproduced bit for bit: a 128-bit fixed-point
# series brackets it by the two binary64 neighbours of the nearest double, which
# contain every faithfully rounded libm result, and each coefficient is
# evaluated at the corners of those brackets (it is monotone in each). A
# coefficient is certified only when every corner gives the same binary32 word
# (or 2.14 fixed-point integer); otherwise there is no result.
import Base
import ./binary64_fma.bend as F
import ./binary64_add_sub.bend as A
import ./binary64_ops.bend as O
import ./binary64_narrow.bend as N

# -----------------------------------------------------------------------------
# Fixed-point reals: 16-bit limbs, least significant first, value = limbs/2^128.
# Nine limbs hold every value below 2^16.

def fx.sum(a: +List<U32>, b: +List<U32>, +carry: U32) -> +List<U32>:
  match a b:
    case Con{+x, xs} Con{+y, ys}:
      +s = (x + y + carry : U32)
      Con{(s .&. 65535 : U32), fx.sum(xs, ys, (s >> 16n : U32))}
    case Con{+x, xs} Nil{}:
      +s = (x + carry : U32)
      Con{(s .&. 65535 : U32), fx.sum(xs, Nil{}, (s >> 16n : U32))}
    case Nil{} _: Nil{}

# a - b for a >= b of equal length.
def fx.difference(a: +List<U32>, b: +List<U32>, +borrow: U32) -> +List<U32>:
  match a b:
    case Con{+x, xs} Con{+y, ys}:
      +d = (x - y - borrow : U32)
      Con{(d .&. 65535 : U32), fx.difference(xs, ys, Bool.to_u32((d > 65535 : U32)))}
    case _ _: Nil{}

# a * m (m < 2^16): one limb longer than a.
def fx.scale(a: +List<U32>, +m: U32, +carry: U32) -> +List<U32>:
  match a:
    case Nil{}: [carry]
    case Con{+x, xs}:
      +p = (x * m + carry : U32)
      Con{(p .&. 65535 : U32), fx.scale(xs, m, (p >> 16n : U32))}

# The exact product a * b, with as many limbs as both together.
def fx.product(b: +List<U32>, +a: +List<U32>) -> +List<U32>:
  match b:
    case Con{+limb, Nil{}}: fx.scale(a, limb, 0)
    case Con{+limb, rest}: fx.sum(Con{0, fx.product(rest, a)}, fx.scale(a, limb, 0), 0)
    case Nil{}: Nil{}

# Truncated fixed-point product.
def fx.mul(+a: +List<U32>, +b: +List<U32>) -> +List<U32>:
  List.take(&2, U32, List.drop(&2, U32, fx.product(b, a), 8n), 9n)

def fx.divide.go(xs: +List<U32>, +d: U32, +rem: U32, +acc: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}: acc
    case Con{+x, rest}:
      +current = ((rem << 16n) + x : U32)
      fx.divide.go(rest, d, (current % d : U32), Con{(current / d : U32), acc})

# Truncated quotient by 0 < d < 2^16.
def fx.divide(+a: +List<U32>, +d: U32) -> +List<U32>:
  fx.divide.go(List.reverse(&2, U32, a), d, 0, Nil{})

# Most significant limbs first: a > b.
def fx.greater.go(a: +List<U32>, b: +List<U32>) -> Bool:
  match a b:
    case Con{+x, xs} Con{+y, ys}: (x > y : U32) || (U32.is_eq(x, y) && fx.greater.go(xs, ys))
    case _ _: False{}

def fx.greater(+a: +List<U32>, +b: +List<U32>) -> Bool:
  fx.greater.go(List.reverse(&2, U32, a), List.reverse(&2, U32, b))

def fx.zeros(n: Nat, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: fx.zeros(k, Con{0, acc})

def fx.shift_bits(a: +List<U32>, +s: Nat, +carry: U32) -> +List<U32>:
  match a:
    case Nil{}: [carry]
    case Con{+x, xs}:
      +v = ((x << s) .|. carry : U32)
      Con{(v .&. 65535 : U32), fx.shift_bits(xs, s, (v >> 16n : U32))}

# floor(pi * 2^128) and floor(pi * 2^127).
def fx.pi() -> +List<U32>:
  [29508, 880, 35374, 4889, 2259, 34211, 27272, 9279, 3]

def fx.pi_half() -> +List<U32>:
  [14754, 440, 50455, 35212, 33897, 17105, 46404, 37407, 1]

def fx.limbs(+low: U32, +mh: U32) -> +List<U32>:
  [(low .&. 65535 : U32), (low >> 16n : U32), (mh .&. 65535 : U32), (mh >> 16n : U32)]

# |x| for a binary64 word with stored exponent 963..1024 (2^-60 <= |x| < 4):
# its significand shifted left by E + 76 bits, exactly.
def fx.from_words(+high: U32, +low: U32) -> +List<U32>:
  +k = (((high >> 20n) .&. 2047) - 947 : U32)
  +mh = ((high .&. 1048575) .|. 1048576 : U32)
  List.take(&2, U32, fx.zeros(U32.to_nat((k / 16 : U32)), List.append(&2, U32, fx.shift_bits(fx.limbs(low, mh), U32.to_nat((k % 16 : U32)), 0), fx.zeros(9n, Nil{}))), 9n)

# sin(r) for 0 <= r <= pi/2 by its Taylor series (22 terms after r): every
# term is truncated, so the sum is within 2^-110 of sin(r).
def fx.series(n: Nat, +k: U32, +r2: +List<U32>, +term: +List<U32>, +total: +List<U32>) -> +List<U32>:
  match n:
    case 0n: total
    case 1n+m:
      +next = fx.divide(fx.mul(term, r2), (2 * k * (2 * k + 1) : U32))
      fx.series(m, (k + 1 : U32), r2, next, Bool.pick(+List<U32>, U32.is_eq((k .&. 1 : U32), 1), fx.difference(total, next, 0), fx.sum(total, next, 0)))

def fx.sin(+r: +List<U32>) -> +List<U32>:
  fx.series(22n, 1, fx.mul(r, r), r, r)

# -----------------------------------------------------------------------------
# Fixed point to the nearest binary64 (ties to even). The value is at least
# 2^-54 here, so its top bit p (counted from 2^-128) is at least 74.

def fx.head(a: +List<U32>) -> U32:
  match a:
    case Con{x, _}: x
    case Nil{}: 0

def fx.top.go(a: +List<U32>, +index: U32, +found: U32) -> U32:
  match a:
    case Nil{}: found
    case Con{+x, xs}: fx.top.go(xs, (index + 1 : U32), Bool.pick(U32, U32.is_eq(x, 0), found, (16 * index + U32.from_nat(U32.log2(x)) : U32)))

def fx.sticky(a: +List<U32>) -> Bool:
  match a:
    case Nil{}: False{}
    case Con{+x, xs}: U32.is_ne(x, 0) || fx.sticky(xs)

# a shifted right by s bits (u = 16 - s), limb by limb.
def fx.right.go(a: +List<U32>, +s: Nat, +u: Nat) -> +List<U32>:
  match a:
    case Con{+x, +xs}:
      Con{(((x >> s) .|. (fx.head(xs) << u)) .&. 65535 : U32), fx.right.go(xs, s, u)}
    case Nil{}: Nil{}

type Rounded is Data:
  Rounded{high: U32, low: U32}

def fx.rounded.finish(+mhi: U32, +mlo: U32, +p: U32) -> Rounded:
  +carried = U32.is_eq(mhi, 2097152)
  +exponent = (p + 895 + Bool.to_u32(carried) : U32)
  Rounded{((exponent << 20n) .|. (Bool.pick(U32, carried, 1048576, mhi) .&. 1048575) : U32), mlo}

# Bits p-53..p of the value (54 bits: 53 and a guard bit) and a sticky bit.
def fx.rounded.bits(+v: +List<U32>, +sticky: Bool, +p: U32) -> Rounded:
  +lo32 = ((fx.head(v) .|. (fx.head(List.drop(&2, U32, v, 1n)) << 16n)) : U32)
  +hi32 = ((fx.head(List.drop(&2, U32, v, 2n)) .|. (fx.head(List.drop(&2, U32, v, 3n)) << 16n)) : U32)
  +mlo = ((lo32 >> 1n) .|. (hi32 << 31n) : U32)
  +mhi = (hi32 >> 1n : U32)
  +up = U32.is_eq((lo32 .&. 1 : U32), 1) && (sticky || U32.is_eq((mlo .&. 1 : U32), 1))
  +nlo = (mlo + Bool.to_u32(up) : U32)
  fx.rounded.finish((mhi + Bool.to_u32(up && U32.is_eq(nlo, 0)) : U32), nlo, p)

def fx.rounded(+a: +List<U32>, +p: U32) -> Rounded:
  +n = (p - 53 : U32)
  +limbs = U32.to_nat((n / 16 : U32))
  +s = (n % 16 : U32)
  +kept = List.drop(&2, U32, a, limbs)
  +mask = ((1 << U32.to_nat(s)) - 1 : U32)
  +dropped = fx.sticky(List.take(&2, U32, a, limbs)) || U32.is_ne((fx.head(kept) .&. mask : U32), 0)
  fx.rounded.bits(fx.right.go(kept, U32.to_nat(s), U32.to_nat((16 - s : U32))), dropped, p)

# -----------------------------------------------------------------------------
# Binary64 values through the checked helpers. Bad propagates.

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

def stored(+high: U32) -> U32:
  ((high >> 20n) .&. 2047 : U32)

def zero(+high: U32, +low: U32) -> Bool:
  U32.is_eq((high .&. 2147483647 : U32), 0) && U32.is_eq(low, 0)

# x * 2^k by its exponent field (x normal, the result normal).
def rescale(result: V, +k: U32) -> V:
  match result:
    case Ok{+high, +low}: Bool.pick(V, zero(high, low), Ok{high, low}, Ok{(high + (k << 20n) : U32), low})
    case Bad{}: Bad{}

# a / b rounded once: a nonzero numerator is first scaled by 2^-k so that its
# exponent does not exceed the divisor's (checked_divide's domain); scaling by a
# power of two commutes with the rounding while every value stays normal.
def div(a: V, b: V) -> V:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}:
      +k = Bool.pick(U32, zero(ah, al) || (stored(ah) <= stored(bh) : U32), 0, (stored(ah) - stored(bh) : U32))
      rescale(lift(O.checked_divide((ah - (k << 20n) : U32), al, bh, bl)), k)
    case _ _: Bad{}

# An integer 1 <= n < 2^31 as binary64 (exact).
def from_u32.small(small: Bool, +n: U32, +p: U32) -> V:
  match small:
    case True{}: Ok{(((p + 1023) << 20n) + ((n << U32.to_nat((20 - p : U32))) .&. 1048575) : U32), 0}
    case False{}: Ok{(((p + 1023) << 20n) + ((n >> U32.to_nat((p - 20 : U32))) .&. 1048575) : U32), (n << U32.to_nat((52 - p : U32)) : U32)}

def from_u32(+n: U32) -> V:
  +p = U32.from_nat(U32.log2(n))
  from_u32.small((p <= 20 : U32), n, p)

def one() -> V:
  Ok{1072693248, 0}

def two() -> V:
  Ok{1073741824, 0}

def half() -> V:
  Ok{1071644672, 0}

def minus_two() -> V:
  Ok{3221225472, 0}

# MA_PI_D*2, MA_PI_D*0.5 and MA_PI_D/8.
def two_pi() -> V:
  Ok{1075388923, 1413754136}

def pi_half() -> V:
  Ok{1073291771, 1413754136}

def pi_eighth() -> V:
  Ok{1071194619, 1413754136}

def three() -> V:
  Ok{1074266112, 0}

# -----------------------------------------------------------------------------
# sin(x) brackets

type Window is Data:
  Window{lo: V, hi: V}

def word(value: F.Words) -> V:
  F.Words{high, low} = value
  Ok{high, low}

def negated(value: V) -> V:
  match value:
    case Ok{high, low}: Ok{(high .^. 2147483648 : U32), low}
    case Bad{}: Bad{}

def window.signed(negative: Bool, +nearest: Rounded) -> Window:
  Rounded{+high, +low} = nearest
  +lo = word(O.decrement(high, low))
  +hi = word(O.increment(high, low))
  Bool.pick(Window, negative, Window{negated(hi), negated(lo)}, Window{lo, hi})

def window.magnitude(+high: U32, +low: U32) -> Window:
  +x = fx.from_words(high, low)
  +r = Bool.pick(+List<U32>, fx.greater(x, fx.pi_half()), fx.difference(fx.pi(), x, 0), x)
  +s = fx.sin(r)
  window.signed((high >= 2147483648 : U32), fx.rounded(s, fx.top.go(s, 0, 0)))

def window.checked(kind: U32, +high: U32, +low: U32) -> Window:
  match kind:
    case 0: Window{Ok{high, low}, Ok{high, low}}
    case 1: window.magnitude(high, low)
    case _: Window{Bad{}, Bad{}}

# Doubles bracketing every faithful sin(x) for |x| <= pi (sin(+-0) is exact).
def window(x: V) -> Window:
  match x:
    case Ok{+high, +low}:
      +e = stored(high)
      window.checked(Bool.pick(U32, zero(high, low), 0, Bool.pick(U32, ((e >= 963) && (e <= 1024) : U32), 1, 2)), high, low)
    case Bad{}: Window{Bad{}, Bad{}}

# -----------------------------------------------------------------------------
# Coefficients

# (int)(x * 16384) for |x| < 4: the significand shifted right by 38 - E.
def fixed(+high: U32, +low: U32) -> U32:
  +e = stored(high)
  +n = (1061 - e : U32)
  +magnitude = Bool.pick(U32, (e < 1008 : U32), 0, ((((high .&. 1048575) .|. 1048576) >> U32.to_nat(U32.min((n - 32 : U32), 31))) : U32))
  Bool.pick(U32, (high >= 2147483648 : U32), (0 - magnitude : U32), magnitude)

# The stored coefficient: the binary32 word (f32 filters) or the 2.14 integer.
def final(+f32: Bool, value: V) -> Maybe<U32>:
  match value:
    case Ok{+high, +low}:
      Bool.pick(Maybe<U32>, f32, N.checked(high, low), Bool.pick(Maybe<U32>, (stored(high) > 1024 : U32), None{}, Some{fixed(high, low)}))
    case Bad{}: None{}

def agree(a: Maybe<U32>, b: Maybe<U32>) -> Maybe<U32>:
  match a b:
    case Some{+x} Some{+y}: Bool.pick(Maybe<U32>, U32.is_eq(x, y), Some{x}, None{})
    case _ _: None{}

def corners(+f32: Bool, +lo: V, +hi: V, +a0lo: V, +a0hi: V) -> Maybe<U32>:
  agree(agree(final(f32, div(lo, a0lo)), final(f32, div(lo, a0hi))), agree(final(f32, div(hi, a0lo)), final(f32, div(hi, a0hi))))

def biquad.words(b0: Maybe<U32>, b1: Maybe<U32>, a1: Maybe<U32>, a2: Maybe<U32>) -> Maybe<+List<U32>>:
  match b0 b1 a1 a2:
    case Some{+x0} Some{x1} Some{x3} Some{x4}: Some{[x0, x1, x0, x3, x4]}
    case _ _ _ _: None{}

def Window.lo(+window: Window) -> V:
  Window{lo, _} = window
  lo

def Window.hi(+window: Window) -> V:
  Window{_, hi} = window
  hi

# One ma_lpf2 biquad (b0, b1, b2, a1, a2 normalized by a0) from the windows of
# s = sin(w), c = cos(w) and k, the cosine of the section angle (q = 1/(2k)).
# a = s/(2q) rises with s and falls with k; the coefficients are monotone in a
# and in c, so their extremes lie at the corners.
def biquad(+f32: Bool, +slo: V, +shi: V, +clo: V, +chi: V, +klo: V, +khi: V) -> Maybe<+List<U32>>:
  +qlo = div(one(), mul(two(), khi))
  +qhi = div(one(), mul(two(), klo))
  +alo = div(slo, mul(two(), qhi))
  +ahi = div(shi, mul(two(), qlo))
  +b1lo = sub(one(), chi)
  +b1hi = sub(one(), clo)
  +a0lo = add(one(), alo)
  +a0hi = add(one(), ahi)
  biquad.words(corners(f32, mul(b1lo, half()), mul(b1hi, half()), a0lo, a0hi), corners(f32, b1lo, b1hi, a0lo, a0hi),
    corners(f32, mul(minus_two(), chi), mul(minus_two(), clo), a0lo, a0hi),
    agree(final(f32, div(sub(one(), alo), a0lo)), final(f32, div(sub(one(), ahi), a0hi))))

def biquad.at(+f32: Bool, +s: Window, +c: Window, +k: Window) -> Maybe<+List<U32>>:
  biquad(f32, Window.lo(s), Window.hi(s), Window.lo(c), Window.hi(c), Window.lo(k), Window.hi(k))

def pair(first: Maybe<+List<U32>>, second: Maybe<+List<U32>>) -> Maybe<+List<U32>>:
  match first second:
    case Some{a} Some{b}: Some{List.append(&2, U32, a, b)}
    case _ _: None{}

# The ten coefficients (two biquads of b0, b1, b2, a1, a2) of the order-4
# low-pass filter for reduced rates rin != rout below 2^31: binary32 words for
# f32 filters, 2.14 integers for s16 ones. None when a coefficient is not
# certified.
def coefficients(+f32: Bool, +rin: U32, +rout: U32) -> Maybe<+List<U32>>:
  +w = div(mul(two_pi(), mul(from_u32(U32.min(rin, rout)), half())), from_u32(U32.max(rin, rout)))
  +s = window(w)
  +c = window(sub(pi_half(), w))
  pair(biquad.at(f32, s, c, window(sub(pi_half(), mul(one(), pi_eighth())))), biquad.at(f32, s, c, window(sub(pi_half(), mul(three(), pi_eighth())))))
