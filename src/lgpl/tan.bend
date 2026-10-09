# SPDX-License-Identifier: LGPL-2.1-or-later
# Jonlib LGPL module (see THIRD_PARTY_NOTICES.md, LICENSES/lgpl-2.1.txt).
# Altered Bend adaptation of glibc 2.39's binary64 tan as the x86_64 library
# executes it in its __tan_fma ifunc variant: sysdeps/ieee754/dbl-64/s_tan.c
# with utan.h, utan.tbl (./tan_table.bend), dla.h and branred.c/branred.h
# (pinned copies in tools/reference/glibc239; glibc 2.41 ships the same files).
#
# IBM Accurate Mathematical Library
# written by International Business Machines Corp.
# Copyright (C) 2001-2024 Free Software Foundation, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation; either version 2.1 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program; if not, see <https://www.gnu.org/licenses/>.
#
# Altered by Jonathan Peris, 2026:
# - written in Bend; every double operation goes through Jonlib's exact
#   binary64 helpers (../binary64_scaled.bend), each rounding once to nearest
#   even, in the source's order;
# - the FMA contraction of glibc's s_tan-fma.c build (-mfma -mavx2, GCC
#   contracting a*b+c across statements, dla.h's EMULV/MUL12 through fma) is
#   written out as explicit fused operations, as in the C model
#   tools/reference/glibc_tan/model.c (FUSED=1), which equals the native glibc
#   2.39 x86_64 tan on every argument raylib can pass (docs/PERSPECTIVE.md);
# - branred.c (built once by glibc, without FMA) is unfused;
# - errno, exception flags and the rounding-mode guard are not modelled, and
#   infinities and NaN (where the source returns x - x) are refused with None.
import Base
import ../binary64_fma.bend as F
import ../binary64_scaled.bend as S
import ./tan_table.bend as Table

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

def div(a: V, b: V) -> V:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: lift(S.divide(ah, al, bh, bl))
    case _ _: Bad{}

def add(a: V, b: V) -> V:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: lift(S.add(ah, al, bh, bl))
    case _ _: Bad{}

def sub(a: V, b: V) -> V:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: lift(S.subtract(ah, al, bh, bl))
    case _ _: Bad{}

def neg(a: V) -> V:
  match a:
    case Ok{high, low}: Ok{(high .^. 2147483648 : U32), low}
    case Bad{}: Bad{}

# a*b + c rounded once (fma).
def madd.words(a: V, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> V:
  match a:
    case Ok{+ah, +al}: lift(S.fma(ah, al, bh, bl, ch, cl))
    case Bad{}: Bad{}

def madd(a: V, b: V, c: V) -> V:
  match b c:
    case Ok{+bh, +bl} Ok{+ch, +cl}: madd.words(a, bh, bl, ch, cl)
    case _ _: Bad{}

# c - a*b rounded once (fma(-a, b, c)).
def nmadd(a: V, b: V, c: V) -> V:
  madd(neg(a), b, c)

# ---------------------------------------------------------------------------
# Comparisons of finite values (a Bad operand compares false; its result is
# Bad whichever branch is taken).

def magnitude.gt(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Bool:
  +am = (ah .&. 2147483647 : U32)
  +bm = (bh .&. 2147483647 : U32)
  (am > bm : U32) || (U32.is_eq(am, bm) && (al > bl : U32))

# fabs(a) > fabs(b)
def abs_gt(a: V, b: V) -> Bool:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: magnitude.gt(ah, al, bh, bl)
    case _ _: False{}

# a < 0.0 (false for -0.0)
def negative(a: V) -> Bool:
  match a:
    case Ok{+high, +low}: (high >= 2147483648 : U32) && U32.is_ne(((high .&. 2147483647) .|. low : U32), 0)
    case Bad{}: False{}

# a > b for a nonnegative b (a's sign decides first).
def greater(a: V, b: V) -> Bool:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: (ah < 2147483648 : U32) && magnitude.gt(ah, al, bh, bl)
    case _ _: False{}

# a < b for a nonpositive nonzero b.
def less(a: V, b: V) -> Bool:
  match a b:
    case Ok{+ah, +al} Ok{+bh, +bl}: (ah >= 2147483648 : U32) && magnitude.gt(ah, al, bh, bl)
    case _ _: False{}

# ---------------------------------------------------------------------------
# Constants (utan.h and branred.h, as binary64 words)

def zero() -> V:
  Ok{0, 0}

def one() -> V:
  Ok{1072693248, 0}

def minus_one() -> V:
  Ok{3220176896, 0}

def d3() -> V:
  Ok{1070945621, 1431655765}

def d5() -> V:
  Ok{1069617425, 286328774}

def d7() -> V:
  Ok{1068212666, 484149061}

def d9() -> V:
  Ok{1066820845, 1238353510}

def d11() -> V:
  Ok{1065498714, 1022551274}

def e0() -> V:
  Ok{1070945621, 1431653821}

def e1() -> V:
  Ok{1069617426, 3769021535}

# -15.5 and 256.0
def mfftnhf() -> V:
  Ok{3224305664, 0}

def scale256() -> V:
  Ok{1081081856, 0}

def mp1() -> V:
  Ok{1073291771, 1476395008}

def mp2() -> V:
  Ok{3192774295, 1006632960}

def mp3() -> V:
  Ok{3163337651, 2581022706}

def pp3() -> V:
  Ok{3163337651, 2550136832}

def pp4() -> V:
  Ok{3134026879, 602091223}

def hpinv() -> V:
  Ok{1071931184, 1841940611}

def toint() -> V:
  Ok{1127743488, 0}

# ---------------------------------------------------------------------------
# Table rows and integer conversions

type Row is Data:
  Row{x: V, f: V, g: V}

def row.words(values: +List<U32>) -> Row:
  match values:
    case Con{+a, Con{+b, Con{+c, Con{+d, Con{+e, Con{+f, _}}}}}}: Row{Ok{a, b}, Ok{c, d}, Ok{e, f}}
    case _: Row{Bad{}, Bad{}, Bad{}}

def row.at(valid: Bool, +i: U32) -> Row:
  match valid:
    case True{}: row.words(List.drop(&2, U32, Table.xfg(), U32.to_nat((6 * i : U32))))
    case False{}: Row{Bad{}, Bad{}, Bad{}}

# xfg[i][0..2] (i = 0..185; other indices give a Bad row).
def row(+i: U32) -> Row:
  row.at((i <= 185 : U32), i)

def Row.x(r: Row) -> V:
  Row{x, _, _} = r
  x

def Row.f(r: Row) -> V:
  Row{_, f, _} = r
  f

def Row.g(r: Row) -> V:
  Row{_, _, g} = r
  g

# (int) of a value in [0, 2^20): truncation toward zero. Values below 1
# (including zero) give 0; an index past the table makes the row Bad.
def truncate.range(code: U32, +e: U32, +high: U32) -> U32:
  match code:
    case 0: 0
    case 1: (((high .&. 1048575) .|. 1048576) >> U32.to_nat((1043 - e : U32)) : U32)
    case _: 4294967295

def truncate.words(+high: U32) -> U32:
  +e = ((high >> 20n) .&. 2047 : U32)
  truncate.range(Bool.pick(U32, (e < 1023 : U32), 0, Bool.pick(U32, (e > 1042 : U32), 2, 1)), e, high)

def truncate(a: V) -> U32:
  match a:
    case Ok{+high, _}: Bool.pick(U32, (high >= 2147483648 : U32), 4294967295, truncate.words(high))
    case Bad{}: 4294967295

# The low word of t (v.i[LOW_HALF]).
def low(a: V) -> U32:
  match a:
    case Ok{_, low}: low
    case Bad{}: 0

# ---------------------------------------------------------------------------
# The polynomials

# d3 + a2*(d5 + a2*(d7 + a2*(d9 + a2*d11))), each step fused.
def poly(+a2: V) -> V:
  madd(a2, madd(a2, madd(a2, madd(a2, d11(), d9()), d7()), d5()), d3())

# z + z*z2*(e0 + z2*e1): fma(z*z2, fma(z2, e1, e0), z).
def pz(+z: V) -> V:
  +z2 = mul(z, z)
  madd(mul(z, z2), madd(z2, e1(), e0()), z)

# i = (int) (mfftnhf + 256*w), fused.
def index(+w: V) -> U32:
  truncate(madd(scale256(), w, mfftnhf()))

# ---------------------------------------------------------------------------
# (II) 1.259e-8 < |x| <= 0.0608: x + (x*x2)*poly(x2), fused.
def small(+x: V) -> V:
  +x2 = mul(x, x)
  madd(mul(x, x2), poly(x2), x)

# fi + pz*(gi + fi)/(gi - pz)
def tangent(+p: V, +fi: V, +gi: V) -> V:
  add(fi, div(mul(p, add(gi, fi)), sub(gi, p)))

# gi - pz*(fi + gi)/(fi + pz)
def cotangent(+p: V, +fi: V, +gi: V) -> V:
  sub(gi, div(mul(p, add(fi, gi)), add(fi, p)))

# (III) 0.0608 < |x| <= 0.787: s*(fi + t2) with s = -1 for x < 0.
def table(+x: V, +w: V) -> V:
  +r = row(index(w))
  +y = tangent(pz(sub(w, Row.x(r))), Row.f(r), Row.g(r))
  mul(Bool.pick(V, negative(x), minus_one(), one()), y)

# ---------------------------------------------------------------------------
# After range reduction: x = n*pi/2 + (a + da).

type Reduced is Data:
  Reduced{a: V, da: V, n: U32}

# EADD(a, da) of dla.h: (a + da, the exact error).
def eadd(+a: V, +da: V) -> Reduced:
  +z = add(a, da)
  Reduced{z, Bool.pick(V, abs_gt(a, da), add(sub(a, z), da), add(sub(da, z), a)), 0}

def Reduced.with(r: Reduced, n: U32) -> Reduced:
  Reduced{z, zz, _} = r
  Reduced{z, zz, n}

def Reduced.renormalized(r: Reduced) -> Reduced:
  Reduced{+a, +da, n} = r
  Reduced.with(eadd(a, da), n)

# -1/(b + db) through DIV2(1.0, 0.0, b, db, c, dc, ...) with the fused MUL12,
# returning -(c + dc).
def minus_cot.div2(+b: V, +db: V) -> V:
  +c = div(one(), b)
  +u = mul(c, b)
  +uu = madd(c, b, neg(u))
  +cc = div(nmadd(c, db, add(sub(sub(one(), u), uu), zero())), b)
  +z = add(c, cc)
  neg(add(z, add(sub(c, z), cc)))

def minus_cot.sum(r: Reduced) -> V:
  Reduced{b, db, _} = r
  minus_cot.div2(b, db)

def minus_cot(+a: V, +t2: V) -> V:
  minus_cot.sum(eadd(a, t2))

# (VI), (VIII), (X): |a| <= 0.0608.
def near.parity(odd: Bool, +a: V, +t2: V) -> V:
  match odd:
    case True{}: minus_cot(a, t2)
    case False{}: add(a, t2)

def near(+a: V, +da: V, +n: U32) -> V:
  +a2 = mul(a, a)
  near.parity(U32.is_ne(n, 0), a, madd(mul(a, a2), poly(a2), da))

# (VII), (IX), (XI): 0.0608 < |a| <= 0.787.
def far.parity(odd: Bool, +p: V, +r: Row, +sy: V) -> V:
  match odd:
    case True{}: mul(neg(sy), cotangent(p, Row.f(r), Row.g(r)))
    case False{}: mul(sy, tangent(p, Row.f(r), Row.g(r)))

def far(+ya: V, +yya: V, +sy: V, +n: U32) -> V:
  +r = row(index(ya))
  far.parity(U32.is_ne(n, 0), pz(add(sub(ya, Row.x(r)), yya)), r, sy)

def gy2() -> V:
  Ok{1068441901, 0}

def reduced.signed(close: Bool, +a: V, +da: V, +ya: V, +yya: V, +sy: V, +n: U32) -> V:
  match close:
    case True{}: near(a, da, n)
    case False{}: far(ya, yya, sy, n)

def reduced.split(below: Bool, +a: V, +da: V, +n: U32) -> V:
  match below:
    case True{}: reduced.signed(Bool.not(greater(neg(a), gy2())), a, da, neg(a), neg(da), minus_one(), n)
    case False{}: reduced.signed(Bool.not(greater(a, gy2())), a, da, a, da, one(), n)

def reduced(r: Reduced) -> V:
  Reduced{+a, +da, +n} = r
  reduced.split(negative(a), a, da, (n .&. 1 : U32))

# Algorithm i: 0.787 < |x| <= 25.
def first.parts(+x: V, +t: V) -> Reduced:
  +xn = sub(t, toint())
  +t1 = nmadd(xn, mp2(), nmadd(xn, mp1(), x))
  +a = nmadd(xn, mp3(), t1)
  Reduced{a, nmadd(xn, mp3(), sub(t1, a)), (low(t) .&. 1 : U32)}

def first(+x: V) -> Reduced:
  first.parts(x, madd(x, hpinv(), toint()))

# Algorithm ii: 25 < |x| <= 1e8.
def second.parts(+x: V, +t0: V) -> Reduced:
  +xn = sub(t0, toint())
  +t1 = nmadd(xn, mp2(), nmadd(xn, mp1(), x))
  +t = nmadd(xn, pp3(), t1)
  +da = nmadd(xn, pp3(), sub(t1, t))
  +a = nmadd(xn, pp4(), t)
  Reduced.renormalized(Reduced{a, add(nmadd(xn, pp4(), sub(t, a)), da), (low(t0) .&. 1 : U32)})

def second(+x: V) -> Reduced:
  second.parts(x, madd(x, hpinv(), toint()))

# ---------------------------------------------------------------------------
# branred.c: x = n*pi/2 + (a + aa) for |x| > 1e8 (no FMA in glibc's build).

def tm24() -> V:
  Ok{1047527424, 0}

def big() -> V:
  Ok{1127743488, 0}

def big1() -> V:
  Ok{1129840640, 0}

def split() -> V:
  Ok{1101004800, 33554432}

def hp0() -> V:
  Ok{1073291771, 1413754136}

def hp1() -> V:
  Ok{1016178214, 856972295}

def bmp1() -> V:
  Ok{1073291771, 1476395008}

def bmp2() -> V:
  Ok{3192774295, 1073741824}

# toverp[75], 2/pi in base 2^24, as binary64 words.
def toverp_table() -> +List<U32>:
  [1097097008, 1610612736, 1096520593, 0, 1094003196, 0, 1094953960, 2147483648, 1097770651, 2684354560,
    1097341804, 1073741824, 1096987431, 2147483648, 1095820304, 1073741824, 1097845292, 1610612736, 1097169879, 1610612736,
    1097378870, 3758096384, 1094858525, 0, 1095799668, 2147483648, 1097597129, 536870912, 1095202052, 2147483648,
    1097478723, 2147483648, 1097843645, 1610612736, 1094496553, 0, 1097131997, 0, 1096828606, 2684354560,
    1095196066, 0, 1096850739, 2147483648, 1096550829, 0, 1096277904, 1073741824, 1095551211, 0,
    1095549353, 2147483648, 1095563854, 0, 1096846321, 1610612736, 1097318181, 0, 1095602172, 0,
    1097007099, 3221225472, 1091985468, 0, 1097721314, 536870912, 1096903489, 1073741824, 1096501211, 1073741824,
    1095450471, 2147483648, 1094968708, 2147483648, 1097263592, 3221225472, 1095742287, 0, 1096284811, 1073741824,
    1096632814, 2147483648, 1097399676, 2684354560, 1097740135, 2684354560, 1092413404, 0, 1096895058, 1073741824,
    1097682303, 1610612736, 1096281159, 3221225472, 1096919969, 0, 1096122572, 0, 1095876382, 3221225472,
    1096477436, 0, 1097463684, 0, 1097031302, 3221225472, 1094560227, 0, 1096952875, 3221225472,
    1097646945, 0, 1096377953, 1073741824, 1096271144, 0, 1096421411, 1073741824, 1097857808, 0,
    1095982281, 3221225472, 1095271171, 0, 1094014666, 0, 1096608306, 1073741824, 1096300702, 3221225472,
    1097339277, 1610612736, 1095889158, 1073741824, 1097362681, 2684354560, 1097571585, 536870912, 1095057836, 2147483648,
    1097371345, 1610612736, 1096991636, 3221225472, 1097577960, 2147483648, 1097476835, 536870912, 1091893908, 0]

def pair.words(values: +List<U32>) -> V:
  match values:
    case Con{+a, Con{+b, _}}: Ok{a, b}
    case _: Bad{}

def toverp(+i: U32) -> V:
  pair.words(List.drop(&2, U32, toverp_table(), U32.to_nat((2 * i : U32))))

# k = (stored exponent - 450)/24, truncated toward zero, and 0 if negative.
def branred.k(x: V) -> U32:
  match x:
    case Ok{+high, _}:
      +e = ((high >> 20n) .&. 2047 : U32)
      Bool.pick(U32, (e < 450 : U32), 0, ((e - 450 : U32) / 24 : U32))
    case Bad{}: 0

type Part is Data:
  Part{b: V, bb: V, sum: V}

# s = (r + big) - big; sum += s; r -= s.
def round.step(+r: V) -> V:
  sub(add(r, big()), big())

# The half of branred for one Veltkamp part, from r[i] = x*toverp[k+i]*gor.
def branred.tail(+r0: V, +r1: V, +r2: V, +r3: V, +r4: V, +r5: V, +sum: V) -> Part:
  +t = add(add(add(add(add(add(zero(), r5), r4), r3), r2), r1), r0)
  +bb = add(add(add(add(add(sub(r0, t), r1), r2), r3), r4), r5)
  +s = round.step(t)
  +sum1 = add(sum, s)
  +t1 = sub(t, s)
  +b = add(t1, bb)
  +bb1 = add(sub(t1, b), bb)
  Part{b, bb1, sub(sum1, sub(add(sum1, big1()), big1()))}

def branred.reduce(+r0: V, +r1: V, +r2: V, +r3: V, +r4: V, +r5: V) -> Part:
  +s0 = round.step(r0)
  +s1 = round.step(r1)
  +s2 = round.step(r2)
  branred.tail(sub(r0, s0), sub(r1, s1), sub(r2, s2), r3, r4, r5, add(add(add(zero(), s0), s1), s2))

def branred.part.at(+x: V, +k: U32) -> Part:
  +gor0 = Ok{(1676673024 - ((24 * k) << 20n) : U32), 0}
  +gor1 = mul(gor0, tm24())
  +gor2 = mul(gor1, tm24())
  +gor3 = mul(gor2, tm24())
  +gor4 = mul(gor3, tm24())
  +gor5 = mul(gor4, tm24())
  branred.reduce(mul(mul(x, toverp(k)), gor0), mul(mul(x, toverp((k + 1 : U32))), gor1), mul(mul(x, toverp((k + 2 : U32))), gor2),
    mul(mul(x, toverp((k + 3 : U32))), gor3), mul(mul(x, toverp((k + 4 : U32))), gor4), mul(mul(x, toverp((k + 5 : U32))), gor5))

def branred.part(+x: V) -> Part:
  branred.part.at(x, branred.k(x))

# The parity of an integral |value| below 2^20 ((int) sum & 1).
def parity(a: V) -> U32:
  (truncate(Bool.pick(V, negative(a), neg(a), a)) .&. 1 : U32)

type Fold is Data:
  Fold{b: V, sum: V}

# if (b > 0.5) {b -= 1; sum += 1} else if (b < -0.5) {b += 1; sum -= 1}
def branred.fold(+b: V, +sum: V) -> Fold:
  +half = Ok{1071644672, 0}
  Bool.pick(Fold, greater(b, half), Fold{sub(b, one()), add(sum, one())},
    Bool.pick(Fold, less(b, neg(half)), Fold{add(b, one()), sub(sum, one())}, Fold{b, sum}))

def branred.finish(f: Fold, +bb: V, +bb1: V, +bb2: V) -> Reduced:
  Fold{+b, +sum} = f
  +s = add(b, add(add(bb, bb1), bb2))
  +t = add(add(sub(b, s), bb), add(bb1, bb2))
  +c = mul(s, split())
  +t1 = sub(c, sub(c, s))
  +t2 = sub(s, t1)
  +b2 = mul(s, hp0())
  +bb3 = add(add(add(sub(mul(t1, bmp1()), b2), mul(t1, bmp2())), mul(t2, bmp1())), add(add(mul(t2, bmp2()), mul(s, hp1())), mul(t, hp0())))
  +s2 = add(b2, bb3)
  Reduced{s2, add(sub(b2, s2), bb3), parity(sum)}

def branred.combine(p1: Part, p2: Part) -> Reduced:
  Part{+b1, +bb1, +sum1} = p1
  Part{+b2, +bb2, +sum2} = p2
  +b = add(b1, b2)
  +bb = Bool.pick(V, abs_gt(b1, b2), add(sub(b1, b), b2), add(sub(b2, b), b1))
  branred.finish(branred.fold(b, add(sum1, sum2)), bb, bb1, bb2)

def branred.split(+x: V) -> Reduced:
  +t = mul(x, split())
  +x1 = sub(t, sub(t, x))
  branred.combine(branred.part(x1), branred.part(sub(x, x1)))

def branred(+x: V) -> Reduced:
  Reduced.renormalized(branred.split(mul(x, Ok{443547648, 0})))

# ---------------------------------------------------------------------------
# tan

# |x| <= g for g with a zero low word.
def within(+mh: U32, +ml: U32, +g: U32) -> Bool:
  (mh < g : U32) || (U32.is_eq(mh, g) && U32.is_eq(ml, 0))

# 0: infinity or NaN; 1: |x| <= g1 (1.259e-8); 2: <= g2 (0.0608); 3: <= g3
# (0.787); 4: <= g4 (25); 5: <= g5 (1e8); 6: larger.
def region(+high: U32, +low: U32) -> U32:
  +mh = (high .&. 2147483647 : U32)
  Bool.pick(U32, (mh >= 2146435072 : U32), 0, Bool.pick(U32, within(mh, low, 1045105004), 1,
    Bool.pick(U32, within(mh, low, 1068441901), 2, Bool.pick(U32, within(mh, low, 1072246554), 3,
      Bool.pick(U32, within(mh, low, 1077477376), 4, Bool.pick(U32, within(mh, low, 1100470148), 5, 6))))))

def result(value: V) -> Maybe<F.Words>:
  match value:
    case Ok{high, low}: Some{F.Words{high, low}}
    case Bad{}: None{}

def tan.at(region: U32, +high: U32, +low: U32) -> Maybe<F.Words>:
  match region:
    case 0: None{}
    case 1: Some{F.Words{high, low}}
    case 2: result(small(Ok{high, low}))
    case 3: result(table(Ok{high, low}, Ok{(high .&. 2147483647 : U32), low}))
    case 4: result(reduced(first(Ok{high, low})))
    case 5: result(reduced(second(Ok{high, low})))
    case _: result(reduced(branred(Ok{high, low})))

# glibc 2.39/2.41 x86_64 tan (the FMA ifunc variant) of a finite binary64
# word pair; None for infinities and NaN, and if a checked helper refused an
# operand (never observed on raylib's arguments; see docs/PERSPECTIVE.md).
def tan(+high: U32, +low: U32) -> Maybe<F.Words>:
  tan.at(region(high, low), high, low)
