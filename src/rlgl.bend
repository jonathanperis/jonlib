# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the OpenGL 1.1 rlgl.h functions (zlib;
# LICENSES/raylib.txt) as rlsw.h 1.5 implements them (src/external/rlsw.h,
# Copyright (c) 2025-2026 Le Juez Victor, MIT; LICENSES/rlsw.txt): swOrtho and
# swFrustum (rlOrtho, rlFrustum), swLineWidth's roundf and swPointSize's
# floorf. src/frame.bend renders.
#
# swOrtho and swFrustum take doubles and mix binary64 and binary32 steps. For
# F32 arguments whose differences right - left, top - bottom and far - near
# are exact in binary32 (and, for swFrustum, whose product far*near is exact
# in binary32), every binary64 step either is exact or is a single rounding of
# an operation on binary32 values that the binary32 rounding of its binary64
# result reproduces (binary64 has at least 2*24 + 2 bits), so the entries are
# computed in F32. Other arguments are refused (docs/RLGL.md).
import Base
import ./frame.bend as F

# The rounding error of a + b (TwoSum; exact for finite values without
# overflow).
def two_sum.error(+a: F32, +b: F32) -> F32:
  +s = (a + b : F32)
  +bb = (s - a : F32)
  ((a - (s - bb : F32) : F32) + (b - bb : F32) : F32)

def finite(+x: F32) -> Bool:
  (F32.abs(x) < F.float(2139095040) : F32)

# a - b is exact in binary32 (and finite).
def exact.difference(+a: F32, +b: F32) -> Bool:
  finite(a) && finite(b) && finite((a - b : F32)) && F32.is_eq(two_sum.error(a, F32.neg(b)), 0.0)

# Dekker's split with 2^12 + 1.
def split.high(+a: F32) -> F32:
  +c = (4097.0 * a : F32)
  (c - (c - a : F32) : F32)

# a*b is exact in binary32: no overflow in the split or the product, a normal
# or zero product, and a zero Dekker error.
def exact.product(+a: F32, +b: F32) -> Bool:
  +p = (a * b : F32)
  +ah = split.high(a)
  +bh = split.high(b)
  +al = (a - ah : F32)
  +bl = (b - bh : F32)
  +error = (((((ah * bh : F32) - p : F32) + (ah * bl : F32) : F32) + (al * bh : F32) : F32) + (al * bl : F32) : F32)
  +small = F.float(226492416)
  +large = F.float(1904214016)
  (F32.abs(a) < large : F32) && (F32.abs(b) < large : F32) && (F32.is_eq(p, 0.0) || (F32.abs(p) >= small : F32)) && F32.is_eq(error, 0.0)

# swOrtho(left, right, bottom, top, near, far)'s matrix, or None outside the
# exact domain.
def ortho(+left: F32, +right: F32, +bottom: F32, +top: F32, +near: F32, +far: F32) -> Maybe<F.Matrix4>:
  +rl = (right - left : F32)
  +tb = (top - bottom : F32)
  +fn = (far - near : F32)
  +valid = exact.difference(right, left) && exact.difference(top, bottom) && exact.difference(far, near)
  Bool.pick(Maybe<F.Matrix4>, valid, Some{F.Matrix4{(2.0 / rl : F32), 0.0, 0.0, 0.0, 0.0, (2.0 / tb : F32), 0.0, 0.0, 0.0, 0.0, (F32.neg(2.0) / fn : F32), 0.0,
    (F32.neg((left + right : F32)) / rl : F32), (F32.neg((top + bottom : F32)) / tb : F32), (F32.neg((far + near : F32)) / fn : F32), 1.0}}, None{})

# swFrustum(left, right, bottom, top, near, far)'s matrix, or None outside the
# exact domain.
def frustum(+left: F32, +right: F32, +bottom: F32, +top: F32, +near: F32, +far: F32) -> Maybe<F.Matrix4>:
  +rl = (right - left : F32)
  +tb = (top - bottom : F32)
  +fn = (far - near : F32)
  +twice = (near * 2.0 : F32)
  +product = ((far * near : F32) * 2.0 : F32)
  +valid = exact.difference(right, left) && exact.difference(top, bottom) && exact.difference(far, near) && exact.product(far, near)
    && finite(twice) && finite(product)
  Bool.pick(Maybe<F.Matrix4>, valid, Some{F.Matrix4{(twice / rl : F32), 0.0, 0.0, 0.0, 0.0, (twice / tb : F32), 0.0, 0.0,
    ((right + left : F32) / rl : F32), ((top + bottom : F32) / tb : F32), (F32.neg((far + near : F32)) / fn : F32), F32.neg(1.0),
    0.0, 0.0, (F32.neg(product) / fn : F32), 0.0}}, None{})

# roundf: halfway cases away from zero.
def roundf(+x: F32) -> F32:
  +t = F32.trunc(x)
  Bool.pick(F32, (F32.abs((x - t : F32)) >= 0.5 : F32), (t + Bool.pick(F32, (x < 0.0 : F32), F32.neg(1.0), 1.0) : F32), t)
