# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of Arm optimized-routines math/powf.c (log2_inline
# and exp2_inline, with the powf_log2_data and exp2f_data tables), as glibc
# 2.39 ships it on x86_64 (TOINT_INTRINSICS 0, POWF_SCALE 1). Copyright (c)
# 2017-2026 Arm Limited; MIT alternative, see LICENSES/arm-math.txt.
# Restricted to powf(x, 2) and powf(x, 3) for x in [-0, 1], and to powf(2, y)
# (the same as exp2f(y)) for |y| < 126, every binary64 operation through the
# checked helpers (each rounds once, to nearest even). For powf(2, y) the
# unfused arithmetic here gives the result of both the SSE2 and the FMA
# variants glibc 2.39 and 2.41 select (tools/reference/glibc_pow2).
# Also math/expf.c and math/logf.c (logf_data.c) at the same revision: expf
# for |x| < 87 and logf for positive finite x, as glibc 2.39 and 2.41 answer
# in both variants (tools/reference/glibc_explog).
import Base
import ./binary64_fma.bend as F
import ./binary64_add_sub.bend as A
import ./binary64_ops.bend as O
import ./binary64_narrow.bend as N

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

def head(values: +List<U32>) -> U32:
  match values:
    case Con{value, _}: value
    case Nil{}: 0

def at(+table: +List<U32>, +i: U32) -> U32:
  head(List.drop(&2, U32, table, U32.to_nat(i)))

def pair(+table: +List<U32>, +i: U32) -> V:
  Ok{at(table, (2 * i : U32)), at(table, (2 * i + 1 : U32))}

def invc() -> +List<U32>:
  [1073111532, 2046358462, 1073050093, 1253017661, 1072993593, 4042264752, 1072941461, 2964849541, 1072893209, 210265253, 1072848418, 2064354976, 1072806730, 1243231295, 1072767832, 4035634618, 1072731455, 1100546215, 1072693248, 0, 1072586892, 4254746540, 1072473267, 520252064, 1072373814, 1466629350, 1072284369, 1671539245, 1072203494, 58212845, 1072130012, 4115875938]

def logc() -> +List<U32>:
  [3219062470, 1536569369, 3218803560, 852819108, 3218555275, 169850747, 3218316777, 443404155, 3218087323, 4092769841, 3217652765, 456882928, 3217226211, 2477735071, 3216597195, 3212348764, 3215617949, 3058130894, 0, 0, 1068710090, 2669999421, 1069840041, 1412993466, 1070498827, 1254417618, 1070859845, 4039533852, 1071156892, 740007928, 1071440036, 1320254412]

# 2^(i/32) as raw words minus i << 47.
def exp2_table() -> +List<U32>:
  [1072693248, 0, 1072683440, 3541402996, 1072674136, 1828292879, 1072665345, 3490863953, 1072657080, 1014845819, 1072649351, 828946858, 1072642170, 1853186616, 1072635549, 4112506593, 1072629502, 171030293, 1072624039, 926591435, 1072619174, 1276261410, 1072614920, 1617004845, 1072611290, 3577096743, 1072608299, 1453150082, 1072605959, 3712504873, 1072604286, 2956612997, 1072603294, 1719614413, 1072602997, 3907805044, 1072603412, 1944781191, 1072604553, 2571947539, 1072606437, 1110089947, 1072609079, 2966275557, 1072612497, 2191782032, 1072616707, 2990417245, 1072621727, 2572866477, 1072627574, 4076559943, 1072634267, 3716502172, 1072641824, 3706687593, 1072650264, 3707479175, 1072659607, 863738719, 1072669871, 2728693978, 1072681078, 1533953344]

def one() -> V:
  Ok{1072693248, 0}

# 0x1.8p52 / 32.
def shift() -> V:
  Ok{1122500608, 0}

# The exponent k of x = 2^k z as a double (|k| < 2^24, exact through F32).
def exponent(+top: U32) -> V:
  +field = (top >> 23n : U32)
  +negative = (field >= 256 : U32)
  +magnitude = Bool.pick(U32, negative, (512 - field : U32), field)
  promote(F32.bits(Bool.pick(F32, negative, F32.neg(U32.to_f32(magnitude)), U32.to_f32(magnitude))))

# log2(x) for the (normalized) word ix, as log2_inline.
def log2(+ix: U32) -> V:
  +tmp = (ix - 1060306944 : U32)
  +i = ((tmp >> 19n) % 16 : U32)
  +top = (tmp .&. 4286578688 : U32)
  +invc = pair(invc(), i)
  +r = sub(mul(promote((ix - top : U32)), invc), one())
  +y0 = add(pair(logc(), i), exponent(top))
  +r2 = mul(r, r)
  +y = add(mul(Ok{1070757398, 3377032715}, r), Ok{3218545001, 2692073082})
  +p = add(mul(Ok{1071564554, 1822931677}, r), Ok{3219592519, 1220474568})
  +r4 = mul(r2, r2)
  +q = add(mul(p, r2), add(mul(Ok{1073157447, 1697298475}, r), y0))
  add(mul(y, r4), q)

def narrow.float(+value: U32) -> F32:
  U32{bits} = value
  F32{bits}

def narrow.word(bits: Maybe<U32>) -> Maybe<F32>:
  match bits:
    case Some{word}: Some{narrow.float(word)}
    case None{}: None{}

def narrow(value: V) -> Maybe<F32>:
  match value:
    case Ok{high, low}: narrow.word(N.checked(high, low))
    case Bad{}: None{}

# asdouble(T[ki % 32] + (ki << 47)): only ki's low word reaches the result.
def scale(+kl: U32) -> V:
  Ok{(at(exp2_table(), (2 * (kl .&. 31) : U32)) + (kl << 15n) : U32), at(exp2_table(), (2 * (kl .&. 31) + 1 : U32))}

# exp2_inline: 2^(k/32) from the table times a cubic in the remainder.
def exp2.at(+xd: V, +kd: V) -> Maybe<F32>:
  match kd:
    case Bad{}: None{}
    case Ok{+kh, +kl}:
      +r = sub(xd, sub(kd, shift()))
      +s = scale(kl)
      +z = add(mul(Ok{1068264184, 1267803028}, r), Ok{1070514126, 1358611699})
      +y = add(mul(z, mul(r, r)), add(mul(Ok{1072049730, 4278997718}, r), one()))
      narrow(mul(y, s))

# |xd| >= 126 and xd <= -150 underflow to +0 (xd <= 0 for x <= 1).
def exp2.checked(+xd: V) -> Maybe<F32>:
  match xd:
    case Bad{}: None{}
    case Ok{+high, +low}:
      +large = (((high >> 15n) .&. 65535) >= 32959 : U32)
      +magnitude = (high .&. 2147483647 : U32)
      +under = (high >= 2147483648 : U32) && (magnitude >= 1080213504 : U32)
      Bool.pick(Maybe<F32>, large && under, Some{0.0}, exp2.at(xd, add(xd, shift())))

def exp2.inside(inside: Bool, +bits: U32) -> Maybe<F32>:
  match inside:
    case False{}: None{}
    case True{}: exp2.at(promote(bits), add(promote(bits), shift()))

# powf(2, y) and exp2f(y) for the binary32 word of y: exp2_inline on y itself
# (log2_inline(2.0f) is exactly 1, so powf's y*log2(x) is y). A finite y with
# |y| < 126 only: the result is normal and no special case of powf or exp2f
# is reached. None otherwise.
def exp2.word(+bits: U32) -> Maybe<F32>:
  exp2.inside(((bits .&. 2147483647) < 1123811328 : U32), bits)

# glibc 2.39 and 2.41 (x86_64) powf(2, y) and exp2f(y) for a finite y with
# |y| < 126; None otherwise.
def exp2(+y: F32) -> Maybe<F32>:
  exp2.word(F32.bits(y))

# expf (math/expf.c): z = x*32/ln2 = k + r with an integral k; exp(x) is
# 2^(k/32) from the table times a cubic in r (the coefficients scaled by 32).
def exp.at(+z: V, +kd: V) -> Maybe<F32>:
  match kd:
    case Bad{}: None{}
    case Ok{+kh, +kl}:
      +r = sub(z, sub(kd, Ok{1127743488, 0}))
      +s = scale(kl)
      +zz = add(mul(Ok{1052535544, 1267803028}, r), Ok{1060028366, 1358611699})
      +y = add(mul(zz, mul(r, r)), add(mul(Ok{1066806850, 4278997718}, r), one()))
      narrow(mul(y, s))

def exp.scaled(+z: V) -> Maybe<F32>:
  exp.at(z, add(z, Ok{1127743488, 0}))

def exp.inside(inside: Bool, +bits: U32) -> Maybe<F32>:
  match inside:
    case False{}: None{}
    case True{}: exp.scaled(mul(Ok{1078400327, 1697350398}, promote(bits)))

# glibc 2.39 and 2.41 (x86_64) expf(x) for the binary32 word of x: a finite x
# with |x| < 87, where the result is normal and no special case is reached.
# The FMA variant contracts r = z - kd into one fma and differs from the SSE2
# one at 32.564632 (0x4202422f) and -63.099461 (0xc27c65d9) only: those two
# are refused, every other argument has one answer (this unfused
# arithmetic). None otherwise.
def exp.word(+bits: U32) -> Maybe<F32>:
  exp.inside(((bits .&. 2147483647) < 1118699520 : U32) && Bool.not(U32.is_eq(bits, 1107444271)) && Bool.not(U32.is_eq(bits, 3262932441)), bits)

def exp(+x: F32) -> Maybe<F32>:
  exp.word(F32.bits(x))

# The word of x normalized as logf and powf do for subnormals (x * 2^23,
# minus 23 in the exponent), in integer arithmetic.
def normalize.steps(n: Nat, +m: U32, +s: U32) -> U32 & U32:
  match n:
    case 0n: (m, s)
    case 1n+k: Bool.pick(U32 & U32, (m >= 8388608 : U32), (m, s), normalize.steps(k, (m << 1n : U32), (s + 1 : U32)))

def normalize.word(pair: U32 & U32) -> U32:
  (+m, +s) = pair
  ((((1 - s) << 23n) : U32) + (m .&. 8388607) : U32)

def normalize(+ix: U32) -> U32:
  Bool.pick(U32, (ix < 8388608 : U32), normalize.word(normalize.steps(24n, ix, 0)), ix)

# log(c) for the centers of logf's 16 subintervals (logf_data.c; their 1/c is
# powf's invc table).
def log_logc() -> +List<U32>:
  [3218439159, 2156702430, 3218259696, 2814406107, 3218087598, 2136029799, 3217764824, 2793546985, 3217446735, 180385624, 3217140267, 3348922624, 3216658038, 3465285214, 3216086844, 1516313804, 3215086324, 954272798, 0, 0, 1068148138, 1576163716, 1069309523, 2855677620, 1069885157, 1998641928, 1070318214, 220350320, 1070663051, 3365961441, 1070859312, 1471606281]

# logf (math/logf.c): x = 2^k z with z in [0x1.66p-1, 0x1.66p0); log(x) =
# log1p(z/c - 1) + log(c) + k*ln2, log1p as a cubic.
def log.at(+ix: U32) -> Maybe<F32>:
  +tmp = (ix - 1060306944 : U32)
  +i = ((tmp >> 19n) % 16 : U32)
  +top = (tmp .&. 4286578688 : U32)
  +r = sub(mul(promote((ix - top : U32)), pair(invc(), i)), one())
  +y0 = add(pair(log_logc(), i), mul(exponent(top), Ok{1072049730, 4277811695}))
  +r2 = mul(r, r)
  +y = add(mul(Ok{3218083491, 1220051764}, r2), add(mul(Ok{1070946139, 199232362}, r), Ok{3219128318, 4060758307}))
  narrow(add(mul(y, r2), add(y0, r)))

def log.inside(inside: Bool, +bits: U32) -> Maybe<F32>:
  match inside:
    case False{}: None{}
    case True{}: log.at(bits)

# The words logf has an answer for here: a positive finite x, subnormal or
# normal.
def log.domain(+bits: U32) -> Bool:
  (bits >= 1 : U32) && (bits < 2139095040 : U32)

# glibc 2.39 and 2.41 (x86_64) logf(x) for the binary32 word of x: a positive
# finite x (the SSE2 and the FMA variants agree on every one, the subnormal
# ones included, which logf first scales by 2^23). None for zero, negative
# values, infinities and NaN.
def log.word(+bits: U32) -> Maybe<F32>:
  log.inside(log.domain(bits), normalize(bits))

def log(+x: F32) -> Maybe<F32>:
  log.word(F32.bits(x))

def general(+ix: U32, +y: V) -> Maybe<F32>:
  exp2.checked(mul(y, log2(normalize(ix))))

# -----------------------------------------------------------------------------
# powf(x, y) for any finite y (math/powf.c's main path).
#
# glibc selects one of two builds of powf: the FMA one (-mfma -mavx2) on
# hosts that have FMA, where the compiler made one fma of each a*b + c of
# the two polynomials and of z*invc - 1, and the SSE2 one elsewhere, where
# each is a product and a sum. y*log2(x), the add of the shift and the
# remainder are a product, a sum and a difference in both
# (tools/reference/glibc_powf, read from the library's code). Both are
# computed here and powf answers where they agree.

def fma(a: V, b: V, c: V) -> V:
  match a b c:
    case Ok{+ah, +al} Ok{+bh, +bl} Ok{+ch, +cl}: lift(F.checked(ah, al, bh, bl, ch, cl))
    case _ _ _: Bad{}

# a*b + c as a build computes it.
def madd(fused: Bool, +a: V, +b: V, +c: V) -> V:
  match fused:
    case True{}: fma(a, b, c)
    case False{}: add(mul(a, b), c)

# log2_inline as the build computes it (log2 above is the SSE2 build's).
def log2.for(+fused: Bool, +ix: U32) -> V:
  +tmp = (ix - 1060306944 : U32)
  +i = ((tmp >> 19n) % 16 : U32)
  +top = (tmp .&. 4286578688 : U32)
  +r = madd(fused, promote((ix - top : U32)), pair(invc(), i), Ok{3220176896, 0})
  +y0 = add(pair(logc(), i), exponent(top))
  +r2 = mul(r, r)
  +y = madd(fused, Ok{1070757398, 3377032715}, r, Ok{3218545001, 2692073082})
  +p = madd(fused, Ok{1071564554, 1822931677}, r, Ok{3219592519, 1220474568})
  +r4 = mul(r2, r2)
  madd(fused, y, r4, madd(fused, p, r2, madd(fused, Ok{1073157447, 1697298475}, r, y0)))

# exp2_inline as the build computes it.
def exp2.for(+fused: Bool, +xd: V, +kd: V) -> Maybe<F32>:
  match kd:
    case Bad{}: None{}
    case Ok{+kh, +kl}:
      +r = sub(xd, sub(kd, shift()))
      +z = madd(fused, Ok{1068264184, 1267803028}, r, Ok{1070514126, 1358611699})
      narrow(mul(madd(fused, z, mul(r, r), madd(fused, Ok{1072049730, 4278997718}, r, one())), scale(kl)))

# What powf does with y*log2(x). 0: exp2_inline. 1: at -150 and below the
# result underflows to +0. 2: no answer here: from 127.984375 up. Above
# 0x1.fffffffd1d571p+6 the result overflows; below that, down to
# 127.984375, exp2_inline's scale is 2^128, which the exact binary64
# helpers do not take, so the last 64th of the last binade has no answer
# either. Between -150 and -149 glibc returns the smallest subnormal, which
# is also what exp2_inline's product rounds to.
def powf.bound(+high: U32, +low: U32) -> U32:
  +large = (((high >> 15n) .&. 65535) >= 32959 : U32)
  +negative = (high >= 2147483648 : U32)
  +magnitude = (high .&. 2147483647 : U32)
  Bool.pick(U32, large && negative && (magnitude >= 1080213504 : U32), 1, Bool.pick(U32, Bool.not(negative) && (magnitude >= 1080033024 : U32), 2, 0))

def powf.bounded(bound: U32, +fused: Bool, +xd: V) -> Maybe<F32>:
  match bound:
    case 0: exp2.for(fused, xd, add(xd, shift()))
    case 1: Some{0.0}
    case _: None{}

def powf.scaled(+fused: Bool, +xd: V) -> Maybe<F32>:
  match xd:
    case Bad{}: None{}
    case Ok{+high, +low}: powf.bounded(powf.bound(high, low), fused, Ok{high, low})

# A build's powf for the word of a positive finite x and a finite y.
def powf.build(+fused: Bool, +ix: U32, +iy: U32) -> Maybe<F32>:
  powf.scaled(fused, mul(promote(iy), log2.for(fused, normalize(ix))))

# The answer of both builds, where it is one.
def powf.same(a: Maybe<F32>, b: Maybe<F32>) -> Maybe<F32>:
  match a b:
    case Some{+x} Some{+y}: Bool.pick(Maybe<F32>, U32.is_eq(F32.bits(x), F32.bits(y)), Some{x}, None{})
    case _ _: None{}

# Which case of powf the words of x and y are. 0: x is +0 and y above 0: +0.
# 1: x is positive and finite, y finite, normal and not 0: the main path
# (a subnormal x is normalized). 2: y is 0 and x not a NaN: 1. 3: outside
# this profile: a negative x (and -0), an infinite one, NaNs, an infinite or
# subnormal y, and a negative y with x 0 (a division by zero).
def powf.region(+ix: U32, +iy: U32) -> U32:
  +ay = (iy .&. 2147483647 : U32)
  +zero = U32.is_eq(ay, 0)
  +finite = (ay >= 8388608 : U32) && (ay < 2139095040 : U32)
  Bool.pick(U32, zero, Bool.pick(U32, ((ix .&. 2147483647) <= 2139095040 : U32), 2, 3),
    Bool.pick(U32, Bool.not(finite), 3, Bool.pick(U32, U32.is_eq(ix, 0), Bool.pick(U32, (iy < 2147483648 : U32), 0, 3), Bool.pick(U32, (ix < 2139095040 : U32), 1, 3))))

def powf.at(region: U32, +ix: U32, +iy: U32) -> Maybe<F32>:
  match region:
    case 0: Some{0.0}
    case 1: powf.same(powf.build(True{}, ix, iy), powf.build(False{}, ix, iy))
    case 2: Some{1.0}
    case _: None{}

def powf.word(+ix: U32, +iy: U32) -> Maybe<F32>:
  powf.at(powf.region(ix, iy), ix, iy)

# glibc 2.39 (x86_64) powf(x, y) in round to nearest: x is +0 or positive and
# finite, y finite and not subnormal. None outside that, where the result
# overflows or is within a 64th of a binade of 2^128 (powf.bound), where a
# binary64 step is outside the exact helpers' domain, and
# where the FMA and the SSE2 builds of glibc do not give the same float
# (about 7 pairs in ten billion, one unit in the last place apart:
# docs/MATH.md). An underflow is +0 or a subnormal, as glibc returns it.
def powf(+x: F32, +y: F32) -> Maybe<F32>:
  powf.word(F32.bits(x), F32.bits(y))

# 0: +0; 1: -0; 2: (0, 1]; 3: outside the profile.
def region(+bits: U32, +exponent: U32) -> U32:
  Bool.pick(U32, Bool.not(U32.is_eq(exponent, 2) || U32.is_eq(exponent, 3)), 3,
    Bool.pick(U32, U32.is_eq(bits, 0), 0, Bool.pick(U32, U32.is_eq(bits, 2147483648), 1, Bool.pick(U32, (bits <= 1065353216 : U32), 2, 3))))

def power.at(region: U32, +x: F32, +exponent: U32) -> Maybe<F32>:
  match region:
    case 0: Some{0.0}
    case 1: Some{Bool.pick(F32, U32.is_eq(exponent, 3), F32.neg(0.0), 0.0)}
    case 2: general(F32.bits(x), Bool.pick(V, U32.is_eq(exponent, 2), Ok{1073741824, 0}, Ok{1074266112, 0}))
    case _: None{}

# glibc 2.39 (x86_64) powf(x, exponent) for exponent 2 or 3 and x in [-0, 1];
# None otherwise.
def power(+x: F32, +exponent: U32) -> Maybe<F32>:
  power.at(region(F32.bits(x), exponent), x, exponent)
