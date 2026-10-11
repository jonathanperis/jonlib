# SPDX-License-Identifier: LGPL-2.1-or-later
# Jonlib LGPL module (see THIRD_PARTY_NOTICES.md, LICENSES/lgpl-2.1.txt).
# Altered Bend adaptation of glibc 2.39's binary64 sin and cos as the x86_64
# library executes them in its __sin_fma and __cos_fma ifunc variants:
# sysdeps/ieee754/dbl-64/s_sin.c with usncs.h, sincostab.c (./sin_table.bend)
# and branred.c/branred.h (pinned copies in tools/reference/glibc239).
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
#   binary64 helpers (through ./tan.bend's checked values), each rounding
#   once to nearest even, in the source's order;
# - the FMA contraction of glibc's s_sin-fma.c build (-mfma -mavx2, GCC
#   contracting a*b+c) is written out as explicit fused operations, as in the
#   C model tools/reference/glibc_sin/model.c (FUSED=1), which equals the
#   native glibc 2.39 x86_64 sin and cos (docs/MATH.md);
# - branred.c (built once by glibc, without FMA) is unfused: its parts are
#   ./tan.bend's, joined here as the source returns them (a, aa and the
#   quadrant (int) sum & 3);
# - errno, exception flags and the rounding-mode guard are not modelled, and
#   infinities and NaN (where the source returns x/x) are refused with None.
import Base
import ../binary64_fma.bend as F
import ./tan.bend as T
import ./sin_table.bend as Table

# ---------------------------------------------------------------------------
# Constants (usncs.h and s_sin.c, as binary64 words)

def s1() -> T.V:
  T.Ok{3217380693, 1431655765}

def s2() -> T.V:
  T.Ok{1065423121, 286330574}

def s3() -> T.V:
  T.Ok{3207201184, 433785016}

def s4() -> T.V:
  T.Ok{1053236706, 2073722585}

def s5() -> T.V:
  T.Ok{3193626111, 3271352153}

def big() -> T.V:
  T.Ok{1120403456, 0}

def hp0() -> T.V:
  T.Ok{1073291771, 1413754136}

def hp1() -> T.V:
  T.Ok{1016178214, 856972295}

def mp1() -> T.V:
  T.Ok{1073291771, 1476395008}

def mp2() -> T.V:
  T.Ok{3192774295, 1006632960}

def pp3() -> T.V:
  T.Ok{3163337651, 2550136832}

def pp4() -> T.V:
  T.Ok{3134026879, 602091223}

def hpinv() -> T.V:
  T.Ok{1071931184, 1841940611}

def toint() -> T.V:
  T.Ok{1127743488, 0}

def sn3() -> T.V:
  T.Ok{3217380693, 1431655701}

def sn5() -> T.V:
  T.Ok{1065423120, 3895035695}

def cs2() -> T.V:
  T.Ok{1071644672, 0}

def cs4() -> T.V:
  T.Ok{3215283541, 1431655733}

def cs6() -> T.V:
  T.Ok{1062650219, 3990479417}

# 0.126
def taylor.limit() -> T.V:
  T.Ok{1069555908, 2611340116}

def half() -> T.V:
  T.Ok{1071644672, 0}

# ---------------------------------------------------------------------------
# Signs

def fabs(a: T.V) -> T.V:
  match a:
    case T.Ok{high, low}: T.Ok{(high .&. 2147483647 : U32), low}
    case T.Bad{}: T.Bad{}

def sign(a: T.V) -> U32:
  match a:
    case T.Ok{high, _}: (high .&. 2147483648 : U32)
    case T.Bad{}: 0

# copysign(a, b)
def copysign(a: T.V, +b: T.V) -> T.V:
  match a:
    case T.Ok{high, low}: T.Ok{((high .&. 2147483647) .|. sign(b) : U32), low}
    case T.Bad{}: T.Bad{}

# a <= 0.0 (true for both zeros)
def nonpositive(a: T.V) -> Bool:
  match a:
    case T.Ok{+high, +low}: (high >= 2147483648 : U32) || U32.is_eq((high .|. low : U32), 0)
    case T.Bad{}: False{}

# a*b - c rounded once (fma(a, b, -c)).
def msub(a: T.V, b: T.V, c: T.V) -> T.V:
  T.madd(a, b, T.neg(c))

# ---------------------------------------------------------------------------
# The table: __sincostab.x[k .. k + 3] for k = u.i[LOW_HALF] << 2

type Row is Data:
  Row{sn: T.V, ssn: T.V, cs: T.V, ccs: T.V}

def row.words(values: +List<U32>) -> Row:
  match values:
    case Con{+a, Con{+b, Con{+c, Con{+d, Con{+e, Con{+f, Con{+g, Con{+h, _}}}}}}}}: Row{T.Ok{a, b}, T.Ok{c, d}, T.Ok{e, f}, T.Ok{g, h}}
    case _: Row{T.Bad{}, T.Bad{}, T.Bad{}, T.Bad{}}

def row.at(valid: Bool, +i: U32) -> Row:
  match valid:
    case True{}: row.words(List.drop(&2, U32, Table.sincos(), U32.to_nat((8 * i : U32))))
    case False{}: Row{T.Bad{}, T.Bad{}, T.Bad{}, T.Bad{}}

# The row of u = big + |x|: its low word counts 128ths (0..109; another
# count gives a Bad row).
def row(+u: T.V) -> Row:
  row.at((T.low(u) <= 109 : U32), T.low(u))

# ---------------------------------------------------------------------------
# do_cos and do_sin

def cos.cor(r: Row, +s: T.V, +c: T.V) -> T.V:
  Row{+sn, +ssn, +cs, +ccs} = r
  T.add(cs, T.nmadd(s, sn, T.nmadd(c, cs, T.nmadd(s, ssn, ccs))))

def cos.table(+x: T.V, +u: T.V) -> T.V:
  +xx = T.mul(x, x)
  cos.cor(row(u), T.madd(T.mul(x, xx), T.madd(xx, sn5(), sn3()), x), T.mul(xx, T.madd(xx, T.madd(xx, cs6(), cs4()), cs2())))

def cos.split(+x: T.V, +dx: T.V, +u: T.V) -> T.V:
  cos.table(T.add(T.sub(fabs(x), T.sub(u, big())), dx), u)

# do_cos(x, dx): the cosine of x + dx from the table row of |x| and the
# polynomials of the remainder.
def do_cos(+x: T.V, +dx: T.V) -> T.V:
  cos.split(x, Bool.pick(T.V, T.negative(x), T.neg(dx), dx), T.add(big(), fabs(x)))

# TAYLOR_SIN(x*x, x, dx) for |x| < 0.126.
def taylor(+x: T.V, +dx: T.V) -> T.V:
  +xx = T.mul(x, x)
  +p = T.madd(T.madd(T.madd(T.madd(s5(), xx, s4()), xx, s3()), xx, s2()), xx, s1())
  T.add(x, T.madd(xx, msub(p, x, T.mul(half(), dx)), dx))

def sin.cor(r: Row, +s: T.V, +c: T.V) -> T.V:
  Row{+sn, +ssn, +cs, +ccs} = r
  T.add(sn, T.madd(s, cs, T.nmadd(c, sn, T.madd(s, ccs, ssn))))

def sin.table(+x: T.V, +dx: T.V, +u: T.V) -> T.V:
  +xx = T.mul(x, x)
  sin.cor(row(u), T.add(x, T.madd(T.mul(x, xx), T.madd(xx, sn5(), sn3()), dx)), T.madd(x, dx, T.mul(xx, T.madd(xx, T.madd(xx, cs6(), cs4()), cs2()))))

def sin.split(+x: T.V, +dx: T.V, +u: T.V) -> T.V:
  copysign(sin.table(T.sub(fabs(x), T.sub(u, big())), dx, u), x)

def sin.large(small: Bool, +x: T.V, +dx: T.V) -> T.V:
  match small:
    case True{}: taylor(x, dx)
    case False{}: sin.split(x, Bool.pick(T.V, nonpositive(x), T.neg(dx), dx), T.add(big(), fabs(x)))

# do_sin(x, dx): the sine of x + dx.
def do_sin(+x: T.V, +dx: T.V) -> T.V:
  sin.large(T.abs_gt(taylor.limit(), x), x, dx)

# ---------------------------------------------------------------------------
# Range reduction

# x = n*pi/2 + (a + da), n modulo 4 (4 when the quadrant was not an int).
type Turn is Data:
  Turn{a: T.V, da: T.V, n: U32}

def reduce.parts(+x: T.V, +t: T.V) -> Turn:
  +xn = T.sub(t, toint())
  +y = T.nmadd(xn, mp2(), T.nmadd(xn, mp1(), x))
  +t2 = T.nmadd(xn, pp3(), y)
  +db = T.nmadd(xn, pp3(), T.sub(y, t2))
  +b = T.nmadd(xn, pp4(), t2)
  Turn{b, T.add(db, T.nmadd(xn, pp4(), T.sub(t2, b))), (T.low(t) .&. 3 : U32)}

# reduce_sincos: |x| < 105414350.
def reduce(+x: T.V) -> Turn:
  reduce.parts(x, T.madd(x, hpinv(), toint()))

# trunc(|value|) for a value below 2^31, from its exponent e (1023..1053;
# wide: above 1043, where the low word has integer bits).
def whole(wide: Bool, +high: U32, +low: U32, +e: U32) -> U32:
  match wide:
    case False{}: ((((high .&. 1048575) .|. 1048576) >> U32.to_nat((1043 - e : U32))) : U32)
    case True{}: (((((high .&. 1048575) .|. 1048576) << U32.to_nat((e - 1043 : U32))) .|. (low >> U32.to_nat((1075 - e : U32)))) : U32)

def quadrant.words(+high: U32, +low: U32) -> U32:
  +e = ((high >> 20n) .&. 2047 : U32)
  +bounded = Bool.pick(U32, (e > 1053 : U32), 1053, Bool.pick(U32, (e < 1023 : U32), 1023, e))
  +value = Bool.pick(U32, (e < 1023 : U32), 0, whole((bounded > 1043 : U32), high, low, bounded))
  Bool.pick(U32, (e > 1053 : U32), 4, Bool.pick(U32, (high >= 2147483648 : U32), ((0 - value) .&. 3 : U32), (value .&. 3 : U32)))

# ((int) sum) & 3; 4 where the conversion is undefined (|sum| of 2^31 and above).
def quadrant(sum: T.V) -> U32:
  match sum:
    case T.Ok{+high, +low}: quadrant.words(high, low)
    case T.Bad{}: 4

# The end of __branred: the two halves' sums folded into one fraction, times
# pi/2 in double-double (the arithmetic of ./tan.bend's branred.finish).
def far.finish(f: T.Fold, +bb: T.V, +bb1: T.V, +bb2: T.V) -> Turn:
  T.Fold{+b, +sum} = f
  +s = T.add(b, T.add(T.add(bb, bb1), bb2))
  +t = T.add(T.add(T.sub(b, s), bb), T.add(bb1, bb2))
  +c = T.mul(s, T.split())
  +t1 = T.sub(c, T.sub(c, s))
  +t2 = T.sub(s, t1)
  +b2 = T.mul(s, T.hp0())
  +bb3 = T.add(T.add(T.add(T.sub(T.mul(t1, T.bmp1()), b2), T.mul(t1, T.bmp2())), T.mul(t2, T.bmp1())), T.add(T.add(T.mul(t2, T.bmp2()), T.mul(s, T.hp1())), T.mul(t, T.hp0())))
  +s2 = T.add(b2, bb3)
  Turn{s2, T.add(T.sub(b2, s2), bb3), quadrant(sum)}

def far.combine(p1: T.Part, p2: T.Part) -> Turn:
  T.Part{+b1, +bb1, +sum1} = p1
  T.Part{+b2, +bb2, +sum2} = p2
  +b = T.add(b1, b2)
  +bb = Bool.pick(T.V, T.abs_gt(b1, b2), T.add(T.sub(b1, b), b2), T.add(T.sub(b2, b), b1))
  far.finish(T.branred.fold(b, T.add(sum1, sum2)), bb, bb1, bb2)

def far.split(+x: T.V) -> Turn:
  +t = T.mul(x, T.split())
  +x1 = T.sub(t, T.sub(t, x))
  far.combine(T.branred.part(x1), T.branred.part(T.sub(x, x1)))

# __branred: |x| of 105414350 and above.
def far(+x: T.V) -> Turn:
  far.split(T.mul(x, T.Ok{443547648, 0}))

def turned.odd(odd: Bool, +a: T.V, +da: T.V) -> T.V:
  match odd:
    case True{}: do_cos(a, da)
    case False{}: do_sin(a, da)

# do_sincos(a, da, n): the cosine in odd quadrants, negated in the third and fourth.
def turned.at(valid: Bool, +a: T.V, +da: T.V, +n: U32) -> T.V:
  match valid:
    case False{}: T.Bad{}
    case True{}: Bool.pick(T.V, U32.is_ne((n .&. 2 : U32), 0), T.neg(turned.odd(U32.is_ne((n .&. 1 : U32), 0), a, da)), turned.odd(U32.is_ne((n .&. 1 : U32), 0), a, da))

def turned(turn: Turn, +shift: U32) -> T.V:
  Turn{+a, +da, +n} = turn
  turned.at((n < 4 : U32), a, da, ((n + shift) .&. 3 : U32))

# ---------------------------------------------------------------------------
# sin and cos

def result(value: T.V) -> Maybe<F.Words>:
  match value:
    case T.Ok{high, low}: Some{F.Words{high, low}}
    case T.Bad{}: None{}

# 0: infinity or NaN; 1: |x| < 2^-26 (sin) or 2^-27 (cos); 2: < 0.855469;
# 3: < 2.426265; 4: < 105414350; 5: larger.
def region(+k: U32, +tiny: U32) -> U32:
  Bool.pick(U32, (k >= 2146435072 : U32), 0, Bool.pick(U32, (k < tiny : U32), 1, Bool.pick(U32, (k < 1072390144 : U32), 2,
    Bool.pick(U32, (k < 1073965309 : U32), 3, Bool.pick(U32, (k < 1100554747 : U32), 4, 5)))))

def sin.at(region: U32, +x: T.V) -> T.V:
  match region:
    case 0: T.Bad{}
    case 1: x
    case 2: do_sin(x, T.zero())
    case 3: copysign(do_cos(T.sub(hp0(), fabs(x)), hp1()), x)
    case 4: turned(reduce(x), 0)
    case _: turned(far(x), 0)

# glibc 2.39 x86_64 sin (the FMA ifunc variant) of a finite binary64 word
# pair; None for infinities and NaN, and if a checked helper refused an
# operand.
def sin(+high: U32, +low: U32) -> Maybe<F.Words>:
  result(sin.at(region((high .&. 2147483647 : U32), 1045430272), T.Ok{high, low}))

# y = hp0 - |x|; a = y + hp1; da = (y - a) + hp1; do_sin(a, da).
def cos.middle(+y: T.V) -> T.V:
  +a = T.add(y, hp1())
  do_sin(a, T.add(T.sub(y, a), hp1()))

def cos.at(region: U32, +x: T.V) -> T.V:
  match region:
    case 0: T.Bad{}
    case 1: T.one()
    case 2: do_cos(x, T.zero())
    case 3: cos.middle(T.sub(hp0(), fabs(x)))
    case 4: turned(reduce(x), 1)
    case _: turned(far(x), 1)

# glibc 2.39 x86_64 cos (the FMA ifunc variant), as sin.
def cos(+high: U32, +low: U32) -> Maybe<F.Words>:
  result(cos.at(region((high .&. 2147483647 : U32), 1044381696), T.Ok{high, low}))
