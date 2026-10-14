# SPDX-License-Identifier: LGPL-2.1-or-later
# Jonlib LGPL module (see THIRD_PARTY_NOTICES.md, LICENSES/lgpl-2.1.txt).
# Altered Bend adaptation of glibc 2.39's binary64 acos as the x86_64 library
# executes it in its __ieee754_acos_fma ifunc variant:
# sysdeps/ieee754/dbl-64/e_asin.c with uasncs.h, asincos.tbl, root.tbl and
# powtwo.tbl (./acos_table.bend).
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
#   once to nearest even;
# - the FMA contraction of glibc's e_asin-fma.c build (-mfma -mavx2, GCC
#   contracting a*b+c) is written out as explicit fused operations, as in the
#   C model tools/reference/glibc_acos/model.c (FUSED=1), which equals the
#   native glibc 2.39 x86_64 acos (docs/MATH.md): every polynomial is a chain
#   of fused steps, the products that close them are fused with the sum that
#   follows, and in the interval below 1 so are 1 - t*t*z, 1.5 - 0.5*t*c,
#   t27*c + c, (t27*c + c) - t27*c, t + y and z - y*y; p*(y + cc) is a
#   product by itself;
# - errno and exception flags are not modelled, and arguments outside
#   [-1, 1], infinities and NaN (where the source returns (x - x)/(x - x), a
#   NaN) are refused with None.
import Base
import ../binary64_fma.bend as F
import ./tan.bend as T
import ./acos_table.bend as Table

# ---------------------------------------------------------------------------
# Constants (uasncs.h, as binary64 words)

def hp0() -> T.V:
  T.Ok{1073291771, 1413754136}

def hp1() -> T.V:
  T.Ok{1016178214, 856972295}

# 2.0*hp0
def pi() -> T.V:
  T.Ok{1074340347, 1413754136}

def f1() -> T.V:
  T.Ok{1069897045, 1431655673}

def f2() -> T.V:
  T.Ok{1068708659, 859181693}

def f3() -> T.V:
  T.Ok{1067899757, 2923610340}

def f4() -> T.V:
  T.Ok{1067392126, 83144089}

def f5() -> T.V:
  T.Ok{1066853442, 3357725721}

def f6() -> T.V:
  T.Ok{1066570456, 256195698}

def rt0() -> T.V:
  T.Ok{1072693247, 4293706205}

def rt1() -> T.V:
  T.Ok{1071644671, 4285887236}

def rt2() -> T.V:
  T.Ok{1071120457, 1734986010}

def rt3() -> T.V:
  T.Ok{1070858339, 416406201}

def t27() -> T.V:
  T.Ok{1101004800, 0}

def half() -> T.V:
  T.Ok{1071644672, 0}

def three_halves() -> T.V:
  T.Ok{1073217536, 0}

# ---------------------------------------------------------------------------
# 2.77556*10^-17 <= |x| < 2^-3

# (((((f6*x2 + f5)*x2 + f4)*x2 + f3)*x2 + f2)*x2 + f1), each step fused.
def series(+x2: T.V) -> T.V:
  T.madd(T.madd(T.madd(T.madd(T.madd(f6(), x2, f5()), x2, f4()), x2, f3()), x2, f2()), x2, f1())

# r = hp0 - x; cor = (((hp0 - r) - x) + hp1) - t with t's last product
# fused; r + cor.
def small.sum(+r: T.V, +x: T.V, +x2: T.V) -> T.V:
  T.add(r, T.nmadd(series(x2), T.mul(x2, x), T.add(T.sub(T.sub(hp0(), r), x), hp1())))

def small(+x: T.V) -> T.V:
  small.sum(T.sub(hp0(), x), x, T.mul(x, x))

# ---------------------------------------------------------------------------
# 2^-3 <= |x| < 0.96875: the table's intervals

# y = hp0 -+ the entry's angle, t = hp1 -+ t, y + t (the upper signs for a
# positive x).
def tabled.signed(positive: Bool, t: T.V, y: T.V) -> T.V:
  match positive:
    case True{}: T.add(T.sub(hp0(), y), T.sub(hp1(), t))
    case False{}: T.add(T.add(hp0(), y), T.add(hp1(), t))

# After the coefficients come the slope, the constant of p and the angle:
# p = xx*xx*q + constant and t = slope*xx + p, both fused.
def tabled.close(words: +List<U32>, +xx: T.V, q: T.V, positive: Bool) -> T.V:
  match words:
    case Con{+sh, Con{+sl, Con{+ph, Con{+pl, Con{+yh, Con{+yl, _}}}}}}:
      tabled.signed(positive, T.madd(T.Ok{sh, sl}, xx, T.madd(T.mul(xx, xx), q, T.Ok{ph, pl})), T.Ok{yh, yl})
    case _: T.Bad{}

# The polynomial's coefficients from the highest down: q = xx*q + c, fused.
def tabled.poly(n: Nat, words: +List<U32>, +xx: T.V, q: T.V, positive: Bool) -> T.V:
  match n:
    case 0n: tabled.close(words, xx, q, positive)
    case 1n+k:
      match words:
        case Con{+h, Con{+l, +rest}}: tabled.poly(k, rest, xx, T.madd(xx, q, T.Ok{h, l}), positive)
        case _: T.Bad{}

# An entry's doubles: xx = |x| - the entry's argument, then the polynomial
# of `terms` coefficients.
def tabled(words: +List<U32>, magnitude: T.V, +terms: U32, positive: Bool) -> T.V:
  match words:
    case Con{+ah, Con{+al, Con{+qh, Con{+ql, +rest}}}}: tabled.poly(U32.to_nat((terms - 1 : U32)), rest, T.sub(magnitude, T.Ok{ah, al}), T.Ok{qh, ql}, positive)
    case _: T.Bad{}

# The entry `row` of an interval's list, `width` doubles an entry.
def entry(words: +List<U32>, +row: U32, +width: U32) -> +List<U32>:
  List.drop(&2, U32, words, U32.to_nat(((row * width) * 2 : U32)))

# ---------------------------------------------------------------------------
# 0.96875 <= |x| < 1

def doubled(+v: T.V) -> T.V:
  T.add(v, v)

# A negative x: cor = (hp1 - cc) - (y + cc)*p, res = (hp0 - y) + cor. A
# positive one: cor = cc + p*(y + cc), res = y + cor. Then res + res.
def root.signed(negative: Bool, +y: T.V, +cc: T.V, product: T.V) -> T.V:
  match negative:
    case True{}: doubled(T.add(T.sub(hp0(), y), T.sub(T.sub(hp1(), cc), product)))
    case False{}: doubled(T.add(y, T.add(cc, product)))

# y = (t27*c + c) - t27*c, cc = (z - y*y)/(t + y) with t = c*(1.5 - 0.5*t*c)
# fused into the sum, and p = (...)*z.
def root.split(negative: Bool, +z: T.V, +t: T.V, +c: T.V, +y: T.V) -> T.V:
  +cc = T.div(T.nmadd(y, y, z), T.madd(T.nmadd(T.mul(half(), t), c, three_halves()), c, y))
  root.signed(negative, y, cc, T.mul(T.mul(series(z), z), T.add(y, cc)))

def root.scaled(negative: Bool, +z: T.V, +t: T.V, +c: T.V) -> T.V:
  root.split(negative, z, t, c, T.nmadd(t27(), c, T.madd(t27(), c, c)))

# t = t*(rt0 + r*(rt1 + r*(rt2 + r*rt3))) with r = 1 - t*t*z; c = t*z.
def root.refined(negative: Bool, +z: T.V, +t: T.V) -> T.V:
  root.scaled(negative, z, t, T.mul(t, z))

def root.first(negative: Bool, +z: T.V, +t: T.V, +r: T.V) -> T.V:
  root.refined(negative, z, T.mul(t, T.madd(r, T.madd(r, T.madd(r, rt3(), rt2()), rt1()), rt0())))

def root.guess(negative: Bool, +z: T.V, +t: T.V) -> T.V:
  root.first(negative, z, t, T.nmadd(T.mul(t, t), z, T.one()))

def pair.first(words: +List<U32>) -> T.V:
  match words:
    case Con{high, Con{low, _}}: T.Ok{high, low}
    case _: T.Bad{}

def pair.at(valid: Bool, words: +List<U32>, +index: U32) -> T.V:
  match valid:
    case False{}: T.Bad{}
    case True{}: pair.first(List.drop(&2, U32, words, U32.to_nat((index * 2 : U32))))

# t = inroot[(k & 0x001fffff) >> 14]*powtwo[511 - (k >> 21)], k the high
# word of z.
def root.table(negative: Bool, z: T.V) -> T.V:
  match z:
    case T.Bad{}: T.Bad{}
    case T.Ok{+zh, +zl}:
      +power = (511 - (zh >> 21n) : U32)
      root.guess(negative, T.Ok{zh, zl}, T.mul(pair.at(True{}, Table.inroot(), (((zh .&. 2097151) >> 14n) : U32)), pair.at((power <= 27 : U32), Table.powtwo(), power)))

# z = 0.5*(1 - |x|)
def root(negative: Bool, magnitude: T.V) -> T.V:
  root.table(negative, T.mul(half(), T.sub(T.one(), magnitude)))

# ---------------------------------------------------------------------------
# |x| >= 1: acos(1) is 0 and acos(-1) is 2.0*hp0; anything else is a NaN.
def ends(+high: U32, +low: U32) -> T.V:
  Bool.pick(T.V, U32.is_eq((high .&. 2147483647 : U32), 1072693248) && U32.is_eq(low, 0), Bool.pick(T.V, (high < 2147483648 : U32), T.zero(), pi()), T.Bad{})

# The interval of |x| by its high word k.
def interval(+k: U32) -> U32:
  Bool.pick(U32, (k < 1015545856 : U32), 0, Bool.pick(U32, (k < 1069547520 : U32), 1, Bool.pick(U32, (k < 1070596096 : U32), 2, Bool.pick(U32, (k < 1071644672 : U32), 3,
    Bool.pick(U32, (k < 1072168960 : U32), 4, Bool.pick(U32, (k < 1072529408 : U32), 5, Bool.pick(U32, (k < 1072594944 : U32), 6, Bool.pick(U32, (k < 1072627712 : U32), 7,
      Bool.pick(U32, (k < 1072693248 : U32), 8, 9)))))))))

# k is the high word without its sign.
def acos.at(code: U32, +k: U32, +positive: Bool, +high: U32, +low: U32) -> T.V:
  match code:
    case 0: hp0()
    case 1: small(T.Ok{high, low})
    case 2: tabled(entry(Table.eighth(), (((k .&. 1048575) >> 15n) : U32), 9), T.Ok{k, low}, 5, positive)
    case 3: tabled(entry(Table.quarter(), (((k .&. 1048575) >> 14n) : U32), 9), T.Ok{k, low}, 5, positive)
    case 4: tabled(entry(Table.half(), (((k >> 13n) .&. 127) : U32), 10), T.Ok{k, low}, 6, positive)
    case 5: tabled(entry(Table.high(), ((((k >> 13n) .&. 127) - 64) : U32), 11), T.Ok{k, low}, 7, positive)
    case 6: tabled(entry(Table.higher(), ((((k >> 13n) .&. 127) - 108) : U32), 12), T.Ok{k, low}, 8, positive)
    case 7: tabled(entry(Table.highest(), ((((k >> 13n) .&. 127) - 116) : U32), 13), T.Ok{k, low}, 9, positive)
    case 8: root(Bool.not(positive), T.Ok{k, low})
    case _: ends(high, low)

def result(value: T.V) -> Maybe<F.Words>:
  match value:
    case T.Ok{high, low}: Some{F.Words{high, low}}
    case T.Bad{}: None{}

# glibc 2.39 x86_64 acos (the FMA ifunc variant) of a binary64 word pair in
# [-1, 1]; None outside it, for infinities and NaN, and if a checked helper
# refused an operand.
def acos(+high: U32, +low: U32) -> Maybe<F.Words>:
  result(acos.at(interval((high .&. 2147483647 : U32)), (high .&. 2147483647 : U32), (high < 2147483648 : U32), high, low))
