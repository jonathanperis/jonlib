# SPDX-License-Identifier: LGPL-2.1-or-later
# Jonlib LGPL module (see THIRD_PARTY_NOTICES.md, LICENSES/lgpl-2.1.txt).
# Altered Bend adaptation of glibc 2.39's binary32 asinf,
# sysdeps/ieee754/flt-32/e_asinf.c (pinned copy in tools/reference/glibc239).
#
# e_asinf.c -- float version of e_asin.c.
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
# Modifications for single precision expansion are
# Copyright (C) 2001 Stephen L. Moshier <moshier@na-net.ornl.gov>
# and are incorporated herein by permission of the author.  The author
# reserves the right to distribute this material elsewhere under different
# copying permissions.  These modifications are distributed here under
# the following terms:
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
# constants (as binary32 words), branches and F32 operation order,
# uncontracted as glibc 2.39's x86_64 build runs it; |x| > 1 and NaN, where the
# source returns a NaN whose bits depend on the host, are refused with None;
# the underflow/inexact side effects are not modelled.
import Base

def word(+value: U32) -> F32:
  U32{bits} = value
  F32{bits}

def pio2_hi() -> F32:
  word(1070141403)

def pio2_lo() -> F32:
  word(3007036718)

def pio4_hi() -> F32:
  word(1061752795)

# t*(p0 + t*(p1 + t*(p2 + t*(p3 + t*p4))))
def poly(+t: F32) -> F32:
  (t * (word(1042983652) + t * (word(1033470194) + t * (word(1027227429) + t * (word(1019614238) + t * word(1026340500))))) : F32)

# 0: |x| = 1; 1: |x| > 1 or NaN; 2: |x| < 2^-27; 3: |x| < 0.5; 4: 0.975 < |x| < 1
# (ix >= 0x3F79999A); 5: 0.5 <= |x| <= 0.975.
def region(+bits: U32) -> U32:
  +ix = (bits .&. 2147483647 : U32)
  Bool.pick(U32, U32.is_eq(ix, 1065353216), 0, Bool.pick(U32, (ix > 1065353216 : U32), 1,
    Bool.pick(U32, (ix < 1056964608 : U32), Bool.pick(U32, (ix < 838860800 : U32), 2, 3), Bool.pick(U32, (ix >= 1064933786 : U32), 4, 5))))

# 1 > |x| >= 0.5: w = 1 - |x|, t = w*0.5, s = sqrtf(t).
def large.near_one(+t: F32, +s: F32) -> F32:
  (pio2_hi() - (2.0 * (s + s * poly(t)) - pio2_lo()) : F32)

def large.middle(+t: F32, +s: F32) -> F32:
  +w = word((F32.bits(s) .&. 4294963200 : U32))
  +c = ((t - w * w) / (s + w) : F32)
  +p = (2.0 * s * poly(t) - (pio2_lo() - 2.0 * c) : F32)
  +q = (pio4_hi() - 2.0 * w : F32)
  (pio4_hi() - (p - q) : F32)

def large.at(near_one: Bool, +t: F32, +s: F32) -> F32:
  match near_one:
    case True{}: large.near_one(t, s)
    case False{}: large.middle(t, s)

def large(near_one: Bool, +t: F32) -> F32:
  large.at(near_one, t, F32.sqrt(t))

def signed(+bits: U32, +t: F32) -> F32:
  Bool.pick(F32, (bits >= 2147483648 : U32), F32.neg(t), t)

def asin.at(region: U32, +x: F32) -> Maybe<F32>:
  match region:
    case 0: Some{(x * pio2_hi() + x * pio2_lo() : F32)}
    case 1: None{}
    case 2: Some{x}
    case 3: Some{(x + x * poly((x * x : F32)) : F32)}
    case 4: Some{signed(F32.bits(x), large(True{}, ((1.0 - F32.abs(x)) * 0.5 : F32)))}
    case _: Some{signed(F32.bits(x), large(False{}, ((1.0 - F32.abs(x)) * 0.5 : F32)))}

# glibc 2.39 asinf on [-1, 1]; None for |x| > 1 and NaN.
def asin(+x: F32) -> Maybe<F32>:
  asin.at(region(F32.bits(x)), x)
