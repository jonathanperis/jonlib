# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of Arm optimized-routines math/powf.c (log2_inline
# and exp2_inline, with the powf_log2_data and exp2f_data tables), as glibc
# 2.39 ships it on x86_64 (TOINT_INTRINSICS 0, POWF_SCALE 1). Copyright (c)
# 2017-2026 Arm Limited; MIT alternative, see LICENSES/arm-math.txt.
# Restricted to powf(x, 2) and powf(x, 3) for x in [-0, 1], every binary64
# operation through the checked helpers (each rounds once, to nearest even).
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

# The word of x normalized as powf does for subnormals (x * 2^23, minus 23 in
# the exponent), in integer arithmetic.
def normalize.steps(n: Nat, +m: U32, +s: U32) -> U32 & U32:
  match n:
    case 0n: (m, s)
    case 1n+k: Bool.pick(U32 & U32, (m >= 8388608 : U32), (m, s), normalize.steps(k, (m << 1n : U32), (s + 1 : U32)))

def normalize.word(pair: U32 & U32) -> U32:
  (+m, +s) = pair
  ((((1 - s) << 23n) : U32) + (m .&. 8388607) : U32)

def normalize(+ix: U32) -> U32:
  Bool.pick(U32, (ix < 8388608 : U32), normalize.word(normalize.steps(24n, ix, 0)), ix)

def general(+ix: U32, +y: V) -> Maybe<F32>:
  exp2.checked(mul(y, log2(normalize(ix))))

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
