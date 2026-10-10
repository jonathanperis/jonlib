# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of Arm optimized-routines math/sinf.c, cosf.c,
# sincosf.h (reduce_fast, reduce_large, sinf_poly) and sincosf_data.c, as
# glibc 2.39/2.41 ship them on x86_64 (TOINT_INTRINSICS 0) in the
# __sinf_fma/__cosf_fma ifunc variants (-mfma -mavx2): every a + b*c that GCC
# contracts there is one fma here (docs/SINCOSF.md). Copyright (c) 2018-2024
# Arm Limited; MIT alternative, see LICENSES/arm-math.txt.
# Every binary64 operation goes through the exact scaled helpers (each rounds
# once, to nearest even); tools/reference/glibc_sinf checks that no
# intermediate of any finite binary32 argument leaves their domain.
import Base
import ./binary64_fma.bend as F
import ./binary64_scaled.bend as S
import ./binary64_narrow.bend as N
import ./float64.bend as D

type V is Data:
  Ok{high: U32, low: U32}
  Bad{}

def lift(result: Maybe<F.Words>) -> V:
  match result:
    case Some{F.Words{high, low}}: Ok{high, low}
    case None{}: Bad{}

def mul(a: V, b: V) -> V:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: lift(S.multiply(ah, al, bh, bl))
    case _ _: Bad{}

def add(a: V, b: V) -> V:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: lift(S.add(ah, al, bh, bl))
    case _ _: Bad{}

def neg(a: V) -> V:
  match a:
    case Ok{high, low}: Ok{(high .^. 2147483648 : U32), low}
    case Bad{}: Bad{}

def madd.words(a: V, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> V:
  match a:
    case Ok{+ah, +al}: lift(S.fma(ah, al, bh, bl, ch, cl))
    case Bad{}: Bad{}

# a*b + c rounded once (fma).
def madd(a: V, b: V, c: V) -> V:
  match b c:
    case Ok{+bh, +bl} Ok{+ch, +cl}: madd.words(a, bh, bl, ch, cl)
    case _ _: Bad{}

def promote.pair(pair: U32 & U32) -> V:
  (high, low) = pair
  Ok{high, low}

# (double) of a binary32 word (exact).
def promote(+word: U32) -> V:
  promote.pair(D.promote.parts(((word >> 23n) .&. 255 : U32), (word .&. 2147483648 : U32), (word .&. 8388607 : U32)))

# (float) of a binary64 value, as a binary32 word.
def narrow(value: V) -> Maybe<U32>:
  match value:
    case Ok{high, low}: N.checked(high, low)
    case Bad{}: None{}

# ---------------------------------------------------------------------------
# sincosf_data.c: the first table (the second negates c0..c4).

def hpi_inv() -> V:
  Ok{1097097008, 1841940611}

def hpi() -> V:
  Ok{1073291771, 1413754136}

def pi63() -> V:
  Ok{1008280059, 1413754136}

def c0() -> V:
  Ok{1072693248, 0}

def c1() -> V:
  Ok{3219128319, 4245447196}

def c2() -> V:
  Ok{1067799891, 3775303449}

def c3() -> V:
  Ok{3210133639, 3902420381}

def c4() -> V:
  Ok{1056543555, 41679043}

def s1() -> V:
  Ok{3217380692, 1502979587}

def s2() -> V:
  Ok{1065422966, 86182852}

def s3() -> V:
  Ok{3207173355, 930402084}

# 4/PI to 192 bits, 8 new bits per entry (__inv_pio4).
def inv_pio4() -> +List<U32>:
  [162, 41721, 10680707, 2734261102, 4186140238, 2205044292, 1850622997, 1313084713,
   1142237692, 355073063, 704390999, 4230436817, 660066805, 1473377588, 3522507997, 4113882560,
   886948059, 3720403810, 3235603093, 3680671129, 1653971260, 2509847619, 2570863504, 1011060801]

def head(values: +List<U32>) -> U32:
  match values:
    case Con{value, _}: value
    case Nil{}: 0

def at(+i: U32) -> U32:
  head(List.drop(&2, U32, inv_pio4(), U32.to_nat(i)))

# ---------------------------------------------------------------------------
# sinf_poly: x the (signed) reduced argument, x2 the square of the unsigned
# one; the sine polynomial for an even quadrant, the cosine one (negated for
# the second table) for an odd quadrant. The contraction is the native one.

def sine(+x: V, +x2: V) -> V:
  +x3 = mul(x2, x)
  +p1 = madd(x2, s3(), s2())
  +x7 = mul(x2, x3)
  +s = madd(x3, s1(), x)
  madd(p1, x7, s)

def table(negated: Bool, +value: V) -> V:
  match negated:
    case True{}: neg(value)
    case False{}: value

def cosine(+negated: Bool, +x2: V) -> V:
  +x4 = mul(x2, x2)
  +p1 = madd(x2, table(negated, c1()), table(negated, c0()))
  +p2 = madd(x2, table(negated, c4()), table(negated, c3()))
  +x6 = mul(x2, x4)
  +c = madd(x4, table(negated, c2()), p1)
  madd(p2, x6, c)

def poly(odd: Bool, +negated: Bool, +x: V, +x2: V) -> V:
  match odd:
    case True{}: cosine(negated, x2)
    case False{}: sine(x, x2)

# The reduced r with quadrant n and sign/table index k (k = n, or n plus the
# input's sign bit for large arguments); cosine adds one to the polynomial's
# quadrant. sign[k & 3] = {1, -1, -1, 1}.
def reduced(+r: V, +n: U32, +k: U32, +cosine: U32) -> Maybe<U32>:
  +quadrant = (k .&. 3 : U32)
  +flip = U32.is_eq(quadrant, 1) || U32.is_eq(quadrant, 2)
  narrow(poly(U32.is_eq(((n + cosine) .&. 1 : U32), 1), U32.is_ne((k .&. 2 : U32), 0), table(flip, r), mul(r, r)))

# ---------------------------------------------------------------------------
# reduce_fast: n = ((int32_t)(x * hpi_inv) + 0x800000) >> 24, r = x - n*hpi.

def truncate.shifted(wide: Bool, +top: U32, +low: U32, +shift: U32) -> U32:
  match wide:
    case True{}: U32.shrn(top, U32.to_nat((shift - 32 : U32)))
    case False{}: (U32.shln(top, U32.to_nat((32 - shift : U32))) .|. U32.shrn(low, U32.to_nat(shift)) : U32)

def truncate.magnitude(small: Bool, +high: U32, +low: U32) -> U32:
  match small:
    case True{}: 0
    case False{}:
      +shift = (1075 - ((high >> 20n) .&. 2047) : U32)
      truncate.shifted((shift >= 32 : U32), ((high .&. 1048575) .|. 1048576 : U32), low, shift)

# (int32_t) v for |v| < 2^31, as a two's-complement word.
def truncate(v: V) -> U32:
  match v:
    case Bad{}: 0
    case Ok{+high, +low}:
      +magnitude = truncate.magnitude((((high >> 20n) .&. 2047) < 1023 : U32), high, low)
      Bool.pick(U32, (high >= 2147483648 : U32), (0 - magnitude : U32), magnitude)

# An integer 1 <= value < 2^32 as binary64 (exact).
def integer(+value: U32) -> V:
  +top = U32.from_nat(U32.log2(value))
  +aligned = U32.shln(value, U32.to_nat((31 - top : U32)))
  Ok{(((1023 + top) << 20n) .|. ((aligned >> 11n) .&. 1048575) : U32), (aligned << 21n : U32)}

# A two's-complement word as binary64 (exact; +0 for zero).
def signed(+word: U32) -> V:
  +negative = (word >= 2147483648 : U32)
  Bool.pick(V, U32.is_eq(word, 0), Ok{0, 0}, table(negative, integer(Bool.pick(U32, negative, (0 - word : U32), word))))

def fast(+cosine: U32, +x: V) -> Maybe<U32>:
  +u = (truncate(mul(x, hpi_inv())) + 8388608 : U32)
  +n = ((u >> 24n) .|. Bool.pick(U32, (u >= 2147483648 : U32), 4294967040, 0) : U32)
  reduced(madd(neg(signed(n)), hpi(), x), n, n, cosine)

# ---------------------------------------------------------------------------
# reduce_large: a 32x96 -> 128-bit product with 4/PI gives the 2.62-bit
# fixed-point modulo; 64-bit words as (high, low) U32 pairs.

type W64 is Data:
  W64{high: U32, low: U32}

# a*b as a 64-bit pair, through 16-bit halves.
def mul64(+a: U32, +b: U32) -> W64:
  +al = (a .&. 65535 : U32)
  +ah = (a >> 16n : U32)
  +bl = (b .&. 65535 : U32)
  +bh = (b >> 16n : U32)
  +p0 = (al * bl : U32)
  +p1 = (al * bh : U32)
  +p2 = (ah * bl : U32)
  +p3 = (ah * bh : U32)
  +mid = ((p0 >> 16n) + (p1 .&. 65535) + (p2 .&. 65535) : U32)
  W64{(p3 + (p1 >> 16n) + (p2 >> 16n) + (mid >> 16n) : U32), ((p0 .&. 65535) .|. (mid << 16n) : U32)}

def W64.add(a: W64, b: W64) -> W64:
  W64{+ah, +al} = a
  W64{+bh, +bl} = b
  +low = (al + bl : U32)
  W64{(ah + bh + Bool.to_u32((low < al : U32)) : U32), low}

def W64.high(value: W64) -> U32:
  W64{high, _} = value
  high

# value * 2^32 for a normal value.
def scale32(value: V) -> V:
  match value:
    case Ok{high, low}: Ok{(high + 33554432 : U32), low}
    case Bad{}: Bad{}

# (double)(int64_t)(high:low): the exact high half plus the low word, rounded once.
def W64.to_double(value: W64) -> V:
  W64{+high, +low} = value
  +upper = signed(high)
  +scaled = {Bool.pick(V, U32.is_eq(high, 0), upper, scale32(upper)) : V}
  add(scaled, Bool.pick(V, U32.is_eq(low, 0), Ok{0, 0}, integer(low)))

def large.reduced(+cosine: U32, +sign: U32, res: W64) -> Maybe<U32>:
  W64{+high, +low} = res
  +n = (W64.high(W64.add(W64{high, low}, W64{536870912, 0})) >> 30n : U32)
  reduced(mul(W64.to_double(W64{(high - (n << 30n) : U32), low}), pi63()), n, (n + sign : U32), cosine)

def large(+cosine: U32, +xi: U32) -> Maybe<U32>:
  +index = ((xi >> 26n) .&. 15 : U32)
  +m = U32.shln(((xi .&. 16777215) .|. 8388608 : U32), U32.to_nat(((xi >> 23n) .&. 7 : U32)))
  +res0 = {W64{(m * at(index) : U32), W64.high(mul64(m, at((index + 8 : U32))))} : W64}
  large.reduced(cosine, (xi >> 31n : U32), W64.add(res0, mul64(m, at((index + 4 : U32)))))

# ---------------------------------------------------------------------------
# sinf (cosine 0) and cosf (cosine 1) of the binary32 word y by the top 12
# bits of |y|: below 0x1p-12f y (sinf) or 1 (cosf); below pio4 the
# polynomial on y; below 120 reduce_fast; finite reduce_large. None for
# infinities and NaN.

def region(+top: U32) -> U32:
  Bool.pick(U32, (top < 920 : U32), 0, Bool.pick(U32, (top < 1012 : U32), 1, Bool.pick(U32, (top < 1071 : U32), 2, Bool.pick(U32, (top < 2040 : U32), 3, 4))))

def tiny(+cosine: U32, +word: U32) -> Maybe<U32>:
  Bool.pick(Maybe<U32>, U32.is_eq(cosine, 0), Some{word}, Some{1065353216})

def small(+cosine: U32, +word: U32) -> Maybe<U32>:
  +x = promote(word)
  narrow(poly(U32.is_eq(cosine, 1), False{}, x, mul(x, x)))

def evaluate(kind: U32, +cosine: U32, +word: U32) -> Maybe<U32>:
  match kind:
    case 0: tiny(cosine, word)
    case 1: small(cosine, word)
    case 2: fast(cosine, promote(word))
    case 3: large(cosine, word)
    case _: None{}

# The result words of sinf/cosf of a binary32 word (None: infinity or NaN).
def sinf.word(+word: U32) -> Maybe<U32>:
  evaluate(region(((word >> 20n) .&. 2047 : U32)), 0, word)

def cosf.word(+word: U32) -> Maybe<U32>:
  evaluate(region(((word >> 20n) .&. 2047 : U32)), 1, word)

def float(result: Maybe<U32>) -> Maybe<F32>:
  match result:
    case Some{+word}:
      U32{w} = word
      Some{F32{w}}
    case None{}: None{}

def sinf(+y: F32) -> Maybe<F32>:
  float(sinf.word(F32.bits(y)))

def cosf(+y: F32) -> Maybe<F32>:
  float(cosf.word(F32.bits(y)))

