# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the correctly rounded binary32 asinf of glibc
# 2.41 (release commit 74f59e9271cbb4071671e5a474e7d4f1622b186f,
# sysdeps/ieee754/flt-32/e_asinf.c, SHA-256
# 8b34f085bb2a64a15c75212ec4a0cc3a2eddc7d35583bf2c5921257158339061): the same
# constants, branches, rounding test and binary64 operation order,
# uncontracted. Every binary64 operation goes through the checked helpers
# (each rounds once, to nearest even); notice in LICENSES/core-math-asinf.txt.
#
# Copyright (c) 2023-2024 Alexei Sibidanov.
#
# The original version of this file was copied from the CORE-MATH
# project (file src/binary32/asin/asinf.c, revision bc385c2).
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
import Base
import ./fma.bend as Fma
import ./binary64_fma.bend as F
import ./binary64_add_sub.bend as A
import ./binary64_ops.bend as O
import ./binary64_narrow.bend as N
import ./binary64_sqrt.bend as S

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

def sqrt(a: V) -> V:
  match a:
    case Ok{+high, +low}: lift(S.checked(high, low))
    case Bad{}: Bad{}

# fabs and copysign act on the sign bit only.
def magnitude(a: V) -> V:
  match a:
    case Ok{high, low}: Ok{(high .&. 2147483647 : U32), low}
    case Bad{}: Bad{}

def with_sign(+sign: U32, a: V) -> V:
  match a:
    case Ok{high, low}: Ok{((high .&. 2147483647) .|. sign : U32), low}
    case Bad{}: Bad{}

def promote(+bits: U32) -> V:
  lift(O.checked_promote(bits))

def narrow(value: V) -> Maybe<U32>:
  match value:
    case Ok{high, low}: N.checked(high, low)
    case Bad{}: None{}

def float(+word: U32) -> F32:
  U32{bits} = word
  F32{bits}

def head(values: +List<U32>) -> U32:
  match values:
    case Con{value, _}: value
    case Nil{}: 0

def at(+table: +List<U32>, +i: U32) -> U32:
  head(List.drop(&2, U32, table, U32.to_nat(i)))

def pair(+table: +List<U32>, +i: U32) -> V:
  Ok{at(table, (2 * i : U32)), at(table, (2 * i + 1 : U32))}

# b[16]: the |x| < 0x1.c29p-1 fast polynomial.
def fast_table() -> +List<U32>:
  [1072693248, 5, 1069897047, 2932478045, 1068708174, 3285941522, 1067939187, 2321182610, 1064687095, 3457975608, 1070990790, 3582410992, 3221582475, 1932358598, 1076827425, 1894863339, 3226441262, 2747963694, 1080498545, 3782440352, 3229114449, 726377008, 1082288699, 2370558740, 3229839150, 2775157585, 1081818482, 720108078, 3227963273, 1882919561, 1078022538, 4138098221]

# c[12] of the |x| < 0.5 branch.
def small_table() -> +List<U32>:
  [1069897045, 1431655068, 1068708659, 859300061, 1067899757, 3014936158, 1067392114, 3778724614, 1066854556, 3957353412, 1066518236, 4113076372, 1066167739, 3430703893, 1065941212, 638970262, 1064982579, 3082753512, 1066680132, 2900452956, 3213949719, 3750239347, 1067480352, 3223761622]

# c[12] of the |x| >= 0.5 branch.
def large_table() -> +List<U32>:
  [1073127582, 1719614411, 1069427581, 3724488121, 1067132708, 2058628540, 1065363861, 3427665732, 1063649200, 661571818, 1062220680, 1519554028, 1060704754, 3190028487, 1059374021, 1562654717, 1057682551, 3789010017, 1057668459, 3757473227, 3203494270, 2261842472, 1056374610, 1843683363]

def one() -> V:
  Ok{1072693248, 0}

# pi2 = 0x1.921fb54442d18p+0.
def half_pi() -> V:
  Ok{1073291771, 1413754136}

# poly12(z, c): c0 + z*c1, ..., then c0 += c2*z2; c4 += c6*z2; c8 += z2*c10;
# c0 += z4*(c4 + z4*c8).
def poly12(+z: V, +c: +List<U32>) -> V:
  +z2 = mul(z, z)
  +z4 = mul(z2, z2)
  +c0 = add(pair(c, 0), mul(z, pair(c, 1)))
  +c2 = add(pair(c, 2), mul(z, pair(c, 3)))
  +c4 = add(pair(c, 4), mul(z, pair(c, 5)))
  +c6 = add(pair(c, 6), mul(z, pair(c, 7)))
  +c8 = add(pair(c, 8), mul(z, pair(c, 9)))
  +c10 = add(pair(c, 10), mul(z, pair(c, 11)))
  +d0 = add(c0, mul(c2, z2))
  +d4 = add(c4, mul(c6, z2))
  +d8 = add(c8, mul(z2, c10))
  add(d0, mul(z4, add(d4, mul(z4, d8))))

# (b[i] + z2*b[i+1]) for the fast polynomial.
def fast.term(+z2: V, +i: U32) -> V:
  add(pair(fast_table(), i), mul(z2, pair(fast_table(), (i + 1 : U32))))

# r = z*((((b0 + z2*b1) + z4*(b2 + z2*b3)) + z8*((b4 + z2*b5) + z4*(b6 + z2*b7)))
#   + z16*(((b8 + z2*b9) + z4*(b10 + z2*b11)) + z8*((b12 + z2*b13) + z4*(b14 + z2*b15)))).
def fast.value(+z: V) -> V:
  +z2 = mul(z, z)
  +z4 = mul(z2, z2)
  +z8 = mul(z4, z4)
  +z16 = mul(z8, z8)
  +low = add(add(fast.term(z2, 0), mul(z4, fast.term(z2, 2))), mul(z8, add(fast.term(z2, 4), mul(z4, fast.term(z2, 6)))))
  +high = add(add(fast.term(z2, 8), mul(z4, fast.term(z2, 10))), mul(z8, add(fast.term(z2, 12), mul(z4, fast.term(z2, 14)))))
  mul(z, add(low, mul(z16, high)))

# |x| < 0.5: r = z + (z*z2)*poly12(z2, c).
def small(+bits: U32) -> Maybe<U32>:
  +z = promote(bits)
  +z2 = mul(z, z)
  narrow(add(z, mul(mul(z, z2), poly12(z2, small_table()))))

# |x| >= 0.5: r = copysign(pi2 - sqrt(1 - |x|)*poly12(1 - |x|, c), x).
def large(+bits: U32) -> Maybe<U32>:
  +z = sub(one(), magnitude(promote(bits)))
  narrow(with_sign((bits .&. 2147483648 : U32), sub(half_pi(), mul(sqrt(z), poly12(z, large_table())))))

# The two exceptional |x| of the >= 0.5 branch: copysignf(h, x) + copysignf(2^-26, x).
def exception(+bits: U32, +h: U32) -> Maybe<U32>:
  +sign = (bits .&. 2147483648 : U32)
  Some{F32.bits((float((h .|. sign : U32)) + float((847249408 .|. sign : U32)) : F32))}

# 0: |x| < 0.5; 1: ax = 0x7e55688a; 2: ax = 0x7e107434; 3: |x| >= 0.5 otherwise.
def slow.region(+ax: U32) -> U32:
  Bool.pick(U32, (ax < 2113929216 : U32), 0, Bool.pick(U32, U32.is_eq(ax, 2119526538), 1, Bool.pick(U32, U32.is_eq(ax, 2115007540), 2, 3)))

def slow.at(region: U32, +bits: U32) -> Maybe<U32>:
  match region:
    case 0: small(bits)
    case 1: exception(bits, 1060822097)
    case 2: exception(bits, 1057990066)
    case _: large(bits)

def slow(+bits: U32) -> Maybe<U32>:
  slow.at(slow.region((bits << 1n : U32)), bits)

# The fast path's result when ub == lb (both rounded to binary32), else the slow path.
def fast.decide(agree: Bool, +upper: U32, +bits: U32) -> Maybe<U32>:
  match agree:
    case True{}: Some{upper}
    case False{}: slow(bits)

def fast.compare(upper: Maybe<U32>, lower: Maybe<U32>, +bits: U32) -> Maybe<U32>:
  match upper lower:
    case Some{+u} Some{+l}: fast.decide(U32.is_eq(u, l), u, bits)
    case _ _: None{}

def fast(+bits: U32) -> Maybe<U32>:
  +z = promote(bits)
  +r = fast.value(z)
  fast.compare(narrow(r), narrow(sub(r, mul(z, Ok{1041169038, 2952790016}))), bits)

# 0: |x| > 1 or NaN; 1: |x| < 2^-12; 2: |x| < 0x1.c29p-1; 3: otherwise.
def region(+ax: U32) -> U32:
  Bool.pick(U32, (ax > 2130706432 : U32), 0, Bool.pick(U32, (ax < 1929379840 : U32), 1, Bool.pick(U32, (ax < 2126680064 : U32), 2, 3)))

def word.at(region: U32, +x: F32) -> Maybe<U32>:
  match region:
    case 0: None{}
    case 1: Some{F32.bits(Fma.multiply_add(x, float(855638016), x))}
    case 2: fast(F32.bits(x))
    case _: slow(F32.bits(x))

def to_float(word: Maybe<U32>) -> Maybe<F32>:
  match word:
    case Some{bits}: Some{float(bits)}
    case None{}: None{}

# Correctly rounded asinf for x in [-1, 1] (glibc 2.41); None for |x| > 1 and
# NaN, where the source returns a NaN whose bits depend on the host, and if a
# checked helper refused an operand (not reached on [-1, 1]).
def asin(+x: F32) -> Maybe<F32>:
  to_float(word.at(region((F32.bits(x) << 1n : U32)), x))
