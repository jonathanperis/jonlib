# SPDX-License-Identifier: LGPL-2.1-or-later
# Jonlib LGPL module (see THIRD_PARTY_NOTICES.md, LICENSES/lgpl-2.1.txt).
# Altered Bend adaptation of glibc 2.39's binary32 tanf,
# sysdeps/ieee754/flt-32/s_tanf.c and k_tanf.c (pinned copies in
# tools/reference/glibc239).
#
# s_tanf.c -- float version of s_tan.c.
# k_tanf.c -- float version of k_tan.c
# Conversion to float by Ian Lance Taylor, Cygnus Support, ian@cygnus.com.
#
# ====================================================
# Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
#
# Developed at SunPro, a Sun Microsystems, Inc. business.
# Permission to use, copy, modify, and distribute this
# software is freely granted, provided that this notice
# is preserved.
# ====================================================
#
# glibc's rem_pio2f (the reduction of s_sincosf.h, then the reduced binary64
# value split into two binary32 parts) is part of the GNU C Library, which is
# free software under the GNU Lesser General Public License, version 2.1 or
# later. The reduction itself (reduce_fast, reduce_large and the 4/pi table)
# is the one of src/sincosf.bend (Arm optimized-routines, MIT alternative,
# LICENSES/arm-math.txt), here without the fused step: glibc 2.39 has one
# scalar tanf on x86_64, compiled without FMA.
#
#   This library is free software; you can redistribute it and/or
#   modify it under the terms of the GNU Lesser General Public
#   License as published by the Free Software Foundation; either
#   version 2.1 of the License, or (at your option) any later version.
#
#   This library is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#   Lesser General Public License for more details.
#
#   You should have received a copy of the GNU Lesser General Public
#   License along with this library; if not, see
#   <https://www.gnu.org/licenses/>.
#
# Altered by Jonathan Peris, 2026: written in Bend with the source's
# constants (as binary32 words), branches and F32 operation order, one
# rounding per operation as glibc 2.39's x86_64 build runs it (its one scalar
# tanf, without FMA); the reduction's binary64 steps go through Jonlib's
# checked helpers; infinities and NaN, where the source returns a NaN and
# sets errno, are refused with None; errno and the floating-point flags are
# not modelled. tools/reference/glibc_tanf/model.c is this arithmetic in C;
# it equals glibc 2.39's tanf on every binary32 argument.
import Base
import ../sincosf.bend as S

def float(+word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# T[0..12] of k_tanf.c.
def t0() -> F32:
  float(1051372203)

def t1() -> F32:
  float(1040746633)

def t2() -> F32:
  float(1029508561)

def t3() -> F32:
  float(1018374052)

def t4() -> F32:
  float(1007761183)

def t5() -> F32:
  float(996894998)

def t6() -> F32:
  float(985587272)

def t7() -> F32:
  float(974792392)

def t8() -> F32:
  float(964769721)

def t9() -> F32:
  float(950268997)

def t10() -> F32:
  float(949338234)

def t11() -> F32:
  float(3080433247)

def t12() -> F32:
  float(936989572)

# The word with its low 12 bits cleared (SET_FLOAT_WORD(z, i & 0xfffff000)).
def trimmed(+x: F32) -> F32:
  float((F32.bits(x) .&. 4294963200 : U32))

# -1.0/(x + r) accurately, for an odd quadrant: z + v = r + x.
def reciprocal(+x: F32, +r: F32, +w: F32) -> F32:
  +z = trimmed(w)
  +v = (r - (z - x) : F32)
  +a = (F32.neg(1.0) / w : F32)
  +t = trimmed(a)
  +s = (1.0 + t * z : F32)
  (t + a * (s + t * v) : F32)

# The polynomial part: r and w = x + r for the reduced x and its tail y.
def series(+x: F32, +y: F32) -> F32:
  +z = (x * x : F32)
  +w = (z * z : F32)
  +r = (t1() + w * (t3() + w * (t5() + w * (t7() + w * (t9() + w * t11())))) : F32)
  +v = (z * (t2() + w * (t4() + w * (t6() + w * (t8() + w * (t10() + w * t12()))))) : F32)
  +s = (z * x : F32)
  +q = (y + z * (s * (r + v) + y) : F32)
  (q + t0() * s : F32)

# |x| >= 0.6744: x becomes pio4 - |x| (with the tail), and the result is
# sign*(iy - 2*(x - (w*w/(w + iy) - r))); when the new x is below 2^-13 it is
# sign*iy*(1 - 2*iy*x).
def near_pio4(+negative: Bool, +odd: Bool, +x: F32, +y: F32) -> F32:
  +ax = Bool.pick(F32, negative, F32.neg(x), x)
  +ay = Bool.pick(F32, negative, F32.neg(y), y)
  +nx = ((float(1061752794) - ax : F32) + (float(857874792) - ay : F32) : F32)
  +iy = Bool.pick(F32, odd, F32.neg(1.0), 1.0)
  +sign = Bool.pick(F32, negative, F32.neg(1.0), 1.0)
  +r = series(nx, 0.0)
  +w = (nx + r : F32)
  +tiny = (sign * iy : F32)
  Bool.pick(F32, ((F32.bits(nx) .&. 2147483647) < 956301312 : U32), (tiny * (1.0 - (2.0 * iy) * nx) : F32),
    (sign * (iy - 2.0 * (nx - (w * w / (w + iy) - r))) : F32))

def middle(+odd: Bool, +x: F32, +y: F32) -> F32:
  +r = series(x, y)
  Bool.pick(F32, odd, reciprocal(x, r, (x + r : F32)), (x + r : F32))

# Below 2^-13 tan x is x (or -1/x for an odd quadrant; 1/|x| at zero).
def smallest(+odd: Bool, +x: F32, +ix: U32) -> F32:
  Bool.pick(F32, odd, Bool.pick(F32, U32.is_eq(ix, 0), (1.0 / F32.abs(x) : F32), (F32.neg(1.0) / x : F32)), x)

# __kernel_tanf(x, y, iy): tan(x + y) for iy = 1 (odd False), -1/tan(x + y) for iy = -1.
def kernel(+x: F32, +y: F32, +odd: Bool) -> F32:
  +hx = F32.bits(x)
  +ix = (hx .&. 2147483647 : U32)
  Bool.pick(F32, (ix < 956301312 : U32), smallest(odd, x, ix),
    Bool.pick(F32, (ix >= 1059889472 : U32), near_pio4((hx >= 2147483648 : U32), odd, x, y), middle(odd, x, y)))

def word(+value: F32) -> Maybe<U32>:
  Some{F32.bits(value)}

# y[0] = (float)dx, y[1] = (float)(dx - y[0]); the quadrant's parity picks tan or -1/tan.
def split.tail(tail: Maybe<U32>, +head: U32, +odd: Bool) -> Maybe<U32>:
  match tail:
    case None{}: None{}
    case Some{+low}: word(kernel(float(head), float(low), odd))

def split(head: Maybe<U32>, +dx: S.V, +odd: Bool) -> Maybe<U32>:
  match head:
    case None{}: None{}
    case Some{+h}: split.tail(S.narrow(S.add(dx, S.neg(S.promote(h)))), h, odd)

def reduced(+dx: S.V, +n: U32) -> Maybe<U32>:
  split(S.narrow(dx), dx, U32.is_eq((n .&. 1 : U32), 1))

# reduce_fast: n = ((int32_t)(x*hpi_inv) + 0x800000) >> 24, dx = x - n*hpi (two roundings).
def fast(+x: S.V) -> Maybe<U32>:
  +u = (S.truncate(S.mul(x, S.hpi_inv())) + 8388608 : U32)
  +n = ((u >> 24n) .|. Bool.pick(U32, (u >= 2147483648 : U32), 4294967040, 0) : U32)
  reduced(S.add(x, S.neg(S.mul(S.signed(n), S.hpi()))), n)

def large.reduced(+negative: Bool, res: S.W64) -> Maybe<U32>:
  S.W64{+high, +low} = res
  +n = (S.W64.high(S.W64.add(S.W64{high, low}, S.W64{536870912, 0})) >> 30n : U32)
  +dx = S.mul(S.W64.to_double(S.W64{(high - (n << 30n) : U32), low}), S.pi63())
  reduced(Bool.pick(S.V, negative, S.neg(dx), dx), n)

def large.sum(+m: U32, +index: U32, +top: U32) -> S.W64:
  S.W64.add(S.W64{(m * S.at(index) : U32), top}, S.mul64(m, S.at((index + 4 : U32))))

# reduce_large, then the sign of x on the reduced value.
def large(+xi: U32) -> Maybe<U32>:
  +index = ((xi >> 26n) .&. 15 : U32)
  +m = U32.shln(((xi .&. 16777215) .|. 8388608 : U32), U32.to_nat(((xi >> 23n) .&. 7 : U32)))
  large.reduced((xi >= 2147483648 : U32), large.sum(m, index, S.W64.high(S.mul64(m, S.at((index + 8 : U32))))))

# tanf of a binary32 word: the kernel alone up to pi/4, reduce_fast below
# 120 (by the top 12 bits), reduce_large for the other finite values.
def tanf.word(+word: U32) -> Maybe<U32>:
  +ix = (word .&. 2147483647 : U32)
  Bool.pick(Maybe<U32>, (ix <= 1061752794 : U32), Some{F32.bits(kernel(float(word), 0.0, False{}))},
    Bool.pick(Maybe<U32>, (ix >= 2139095040 : U32), None{}, Bool.pick(Maybe<U32>, (((word >> 20n) .&. 2047) < 1071 : U32), fast(S.promote(word)), large(word))))

def tanf.float(result: Maybe<U32>) -> Maybe<F32>:
  match result:
    case None{}: None{}
    case Some{+bits}: Some{float(bits)}

def tanf(+x: F32) -> Maybe<F32>:
  tanf.float(tanf.word(F32.bits(x)))
