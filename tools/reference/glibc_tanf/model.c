/* Explicit-operation model of glibc 2.39's x86_64 tanf
   (sysdeps/ieee754/flt-32/s_tanf.c and k_tanf.c; pinned copies in
   tools/reference/glibc239). glibc 2.39 has one scalar tanf on x86_64 (no
   ifunc variant), compiled without FMA: every operation below rounds once.

   s_tanf.c -- float version of s_tan.c.
   k_tanf.c -- float version of k_tan.c
   Conversion to float by Ian Lance Taylor, Cygnus Support, ian@cygnus.com.

   ====================================================
   Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.

   Developed at SunPro, a Sun Microsystems, Inc. business.
   Permission to use, copy, modify, and distribute this
   software is freely granted, provided that this notice
   is preserved.
   ====================================================

   The argument reduction (reduce_fast, reduce_large and the 4/pi table) is
   s_sincosf.h's, which glibc takes from Arm optimized-routines
   (math/sincosf.h, Copyright (c) 2018-2024 Arm Limited; MIT alternative, see
   LICENSES/arm-math.txt); rem_pio2f, which splits the reduced binary64 value
   into two binary32 parts, is glibc's (LGPL-2.1-or-later, LICENSES/lgpl-2.1.txt).
   Compile with -ffp-contract=off. Defines MODEL_TANF. */
#include <math.h>
#include <stdint.h>
#include <string.h>

static const double TF_HPI_INV = 0x1.45F306DC9C883p+23, TF_HPI = 0x1.921FB54442D18p0, TF_PI63 = 0x1.921FB54442D18p-62;
static const uint32_t TF_INV_PIO4[24] = {
  0xa2, 0xa2f9, 0xa2f983, 0xa2f9836e, 0xf9836e4e, 0x836e4e44, 0x6e4e4415, 0x4e441529,
  0x441529fc, 0x1529fc27, 0x29fc2757, 0xfc2757d1, 0x2757d1f5, 0x57d1f534, 0xd1f534dd, 0xf534ddc0,
  0x34ddc0db, 0xddc0db62, 0xc0db6295, 0xdb629599, 0x6295993c, 0x95993c43, 0x993c4390, 0x3c439041};
static const float TF_T[13] = {
  0x1.555556p-2f, 0x1.111112p-3f, 0x1.ba1ba2p-5f, 0x1.664f48p-6f, 0x1.226e3ep-7f, 0x1.d6d22cp-9f, 0x1.7dbc9p-10f,
  0x1.344d9p-11f, 0x1.026f72p-12f, 0x1.47e88ap-14f, 0x1.2b80f4p-14f, -0x1.375cbep-16f, 0x1.b2a708p-16f};

static uint32_t tf_word (float x) { uint32_t i; memcpy (&i, &x, 4); return i; }
static float tf_float (uint32_t i) { float x; memcpy (&x, &i, 4); return x; }

static float tf_kernel (float x, float y, int iy)
{
  float z, r, v, w, s;
  int32_t hx = (int32_t) tf_word (x), ix = hx & 0x7fffffff;
  if (ix < 0x39000000)
    {
      if ((int) x == 0)
        {
          if ((ix | (iy + 1)) == 0) return 1.0f / fabsf (x);
          else if (iy == 1) return x;
          else return -1.0f / x;
        }
    }
  if (ix >= 0x3f2ca140)
    {
      if (hx < 0) { x = -x; y = -y; }
      z = 0x1.921fb4p-1f - x;
      w = 0x1.4442dp-25f - y;
      x = z + w; y = 0.0;
      if (fabsf (x) < 0x1p-13f)
        return (1 - ((hx >> 30) & 2)) * iy * (1.0f - 2 * iy * x);
    }
  z = x * x;
  w = z * z;
  r = TF_T[1] + w * (TF_T[3] + w * (TF_T[5] + w * (TF_T[7] + w * (TF_T[9] + w * TF_T[11]))));
  v = z * (TF_T[2] + w * (TF_T[4] + w * (TF_T[6] + w * (TF_T[8] + w * (TF_T[10] + w * TF_T[12])))));
  s = z * x;
  r = y + z * (s * (r + v) + y);
  r += TF_T[0] * s;
  w = x + r;
  if (ix >= 0x3f2ca140)
    {
      v = (float) iy;
      return (float) (1 - ((hx >> 30) & 2)) * (v - (float) 2.0 * (x - (w * w / (w + v) - r)));
    }
  if (iy == 1) return w;
  else
    {
      float a, t;
      z = tf_float (tf_word (w) & 0xfffff000);
      v = r - (z - x);
      t = a = -(float) 1.0 / w;
      t = tf_float (tf_word (t) & 0xfffff000);
      s = (float) 1.0 + t * z;
      return t + a * (s + t * v);
    }
}

static double tf_reduce_large (uint32_t xi, int *np)
{
  const uint32_t *arr = &TF_INV_PIO4[(xi >> 26) & 15];
  int shift = (xi >> 23) & 7;
  uint64_t n, res0, res1, res2;
  xi = (xi & 0xffffff) | 0x800000;
  xi <<= shift;
  res0 = xi * arr[0];
  res1 = (uint64_t) xi * arr[4];
  res2 = (uint64_t) xi * arr[8];
  res0 = (res2 >> 32) | (res0 << 32);
  res0 += res1;
  n = (res0 + (1ULL << 61)) >> 62;
  res0 -= n << 62;
  *np = (int) n;
  return (double) (int64_t) res0 * TF_PI63;
}

float MODEL_TANF (float x)
{
  uint32_t xi = tf_word (x), ix = xi & 0x7fffffff;
  if (ix <= 0x3f490fda) return tf_kernel (x, 0.0f, 1);
  if (ix >= 0x7f800000) return x - x;
  double dx = x;
  int n;
  if (((xi >> 20) & 0x7ff) < 0x42f)   /* abstop12 (x) < abstop12 (120.0f) */
    {
      double r = dx * TF_HPI_INV;
      n = ((int32_t) r + 0x800000) >> 24;
      dx = dx - n * TF_HPI;
    }
  else
    {
      dx = tf_reduce_large (xi, &n);
      dx = (xi >> 31) ? -dx : dx;
    }
  float y0 = (float) dx, y1 = (float) (dx - y0);
  return tf_kernel (y0, y1, 1 - ((n & 1) << 1));
}
