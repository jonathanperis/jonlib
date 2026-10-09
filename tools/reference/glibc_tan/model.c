/*
 * IBM Accurate Mathematical Library
 * written by International Business Machines Corp.
 * Copyright (C) 2001-2024 Free Software Foundation, Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, see <https://www.gnu.org/licenses/>.
 */
/*
 * LGPL-2.1-or-later. Altered by Jonathan Peris (2026) for Jonlib's reference
 * tooling: an explicit-operation model of glibc 2.39's
 * sysdeps/ieee754/dbl-64/s_tan.c (unmodified copy in tools/reference/glibc239,
 * SHA-256 8e02f594c1cde592b6997e6c88be2090a16c23f940fdffc93348ab0dd1b06174)
 * as the x86_64 multiarch library executes it. glibc builds s_tan.c four
 * times (sysdeps/x86_64/fpu/multiarch/s_tan*.c) and selects one by ifunc:
 *
 *   FUSED=1  __tan_fma, built with -mfma -mavx2 (CPUs with FMA and AVX2, the
 *            CI runners). GCC contracts a*b+c across statements into FMA and
 *            dla.h defines EMULV/MUL12 with __builtin_fma.
 *   FUSED=0  __tan_sse2 (and __tan_avx, the same arithmetic VEX-encoded):
 *            no contraction, Dekker's MUL12 with CN = 2^27+1.
 *
 * Every double operation of the source is written out here in the order the
 * glibc 2.39 binary of Ubuntu 24.04 (libm.so.6, build ID
 * d53fcbff9f855463606b25cfbe2a2e10856ea3a7) performs it; MADD(a, b, c) is
 * a*b + c and NMADD(a, b, c) is c - a*b, each rounded once when FUSED and
 * twice otherwise. Compile with contraction off. __branred is the pinned
 * branred.c, which glibc builds once, without FMA. Out of contract: errno,
 * exception flags and non-nearest rounding modes.
 */
#include <math.h>
#include <string.h>
#include "endian.h"
#include "mydefs.h"

#ifndef FUSED
# error "define FUSED to 1 (the __tan_fma variant) or 0 (__tan_sse2/__tan_avx)"
#endif
#ifndef MODEL_TAN
# define MODEL_TAN model_tan
#endif
#ifndef MODEL_BRANRED
# define MODEL_BRANRED __branred
#endif

#if FUSED
# define MADD(a, b, c) fma ((a), (b), (c))
# define NMADD(a, b, c) fma (-(a), (b), (c))
#else
# define MADD(a, b, c) ((a) * (b) + (c))
# define NMADD(a, b, c) ((c) - (a) * (b))
#endif

#define CN 134217729.0

/* EADD of dla.h: z + zz = x + y exactly.  */
#define EADD(x, y, z, zz) \
  z = (x) + (y);  zz = (fabs (x) > fabs (y)) ? (((x) - (z)) + (y)) : (((y) - (z)) + (x));

int MODEL_BRANRED (double, double *, double *);

/* MUL12 of dla.h: the FMA form when FUSED, Dekker's otherwise.  */
static void
mul12 (double x, double y, double *z, double *zz)
{
#if FUSED
  *z = x * y;
  *zz = fma (x, y, -*z);
#else
  double p, hx, tx, hy, ty, q;
  p = CN * x;  hx = (x - p) + p;  tx = x - hx;
  p = CN * y;  hy = (y - p) + p;  ty = y - hy;
  p = hx * hy;  q = hx * ty + tx * hy;  *z = p + q;  *zz = ((p - *z) + q) + tx * ty;
#endif
}

/* -1/(b + db) as DIV2 (1.0, 0.0, b, db, c, dc, ...) and y = c + dc.  */
static double
minus_cot (double a, double t2)
{
  double b, db, c, cc, u, uu, z, zz;
  EADD (a, t2, b, db);
  c = 1.0 / b;
  mul12 (c, b, &u, &uu);
  cc = NMADD (c, db, ((1.0 - u) - uu) + 0.0) / b;
  z = c + cc;
  zz = (c - z) + cc;
  return -(z + zz);
}

/* d3 + a2*(d5 + a2*(d7 + a2*(d9 + a2*d11))).  */
#define POLY(a2) MADD (a2, MADD (a2, MADD (a2, MADD (a2, d11.d, d9.d), d7.d), d5.d), d3.d)

double
MODEL_TAN (double x)
{
#include "utan.h"
#include "utan.tbl"

  int ux, i, n;
  double a, da, a2, fi, gi, pz, s, sy, t, t1, t2, w, x2, xn, y, ya, yya, z, z2;
  mynumber num, v;

  num.d = x;
  ux = num.i[HIGH_HALF];
  if ((ux & 0x7ff00000) == 0x7ff00000)
    return x - x;

  w = (x < 0.0) ? -x : x;

  /* (I) abs(x) <= 1.259e-8 */
  if (w <= g1.d)
    return x;

  /* (II) 1.259e-8 < abs(x) <= 0.0608 */
  if (w <= g2.d)
    {
      x2 = x * x;
      return MADD (x * x2, POLY (x2), x);
    }

  /* (III) 0.0608 < abs(x) <= 0.787 */
  if (w <= g3.d)
    {
      i = (int) MADD (256.0, w, mfftnhf.d);
      z = w - xfg[i][0].d;
      z2 = z * z;
      s = (x < 0.0) ? -1 : 1;
      pz = MADD (z * z2, MADD (z2, e1.d, e0.d), z);
      fi = xfg[i][1].d;
      gi = xfg[i][2].d;
      t2 = pz * (gi + fi) / (gi - pz);
      y = fi + t2;
      return s * y;
    }

  if (w <= g4.d)
    {
      /* Range reduction by algorithm i: 0.787 < abs(x) <= 25 */
      t = MADD (x, hpinv.d, toint.d);
      xn = t - toint.d;
      v.d = t;
      t1 = NMADD (xn, mp2.d, NMADD (xn, mp1.d, x));
      n = v.i[LOW_HALF] & 0x00000001;
      a = NMADD (xn, mp3.d, t1);
      da = NMADD (xn, mp3.d, t1 - a);
    }
  else if (w <= g5.d)
    {
      /* Range reduction by algorithm ii: 25 < abs(x) <= 1e8 */
      t = MADD (x, hpinv.d, toint.d);
      xn = t - toint.d;
      v.d = t;
      t1 = NMADD (xn, mp2.d, NMADD (xn, mp1.d, x));
      n = v.i[LOW_HALF] & 0x00000001;
      t = NMADD (xn, pp3.d, t1);
      da = NMADD (xn, pp3.d, t1 - t);
      a = NMADD (xn, pp4.d, t);
      da = NMADD (xn, pp4.d, t - a) + da;
      EADD (a, da, t1, t2);
      a = t1;
      da = t2;
    }
  else
    {
      /* Range reduction by algorithm iii: 1e8 < abs(x) < 2**1024 */
      n = (MODEL_BRANRED (x, &a, &da)) & 0x00000001;
      EADD (a, da, t1, t2);
      a = t1;
      da = t2;
    }

  if (a < 0.0)
    {
      ya = -a;
      yya = -da;
      sy = -1;
    }
  else
    {
      ya = a;
      yya = da;
      sy = 1;
    }

  /* (VI), (VIII), (X): 0 < abs(y) <= 0.0608 */
  if (ya <= gy2.d)
    {
      a2 = a * a;
      t2 = MADD (a * a2, POLY (a2), da);
      if (n)
	return minus_cot (a, t2);
      return a + t2;
    }

  /* (VII), (IX), (XI): 0.0608 < abs(y) <= 0.787 */
  i = (int) MADD (256.0, ya, mfftnhf.d);
  z = (ya - xfg[i][0].d) + yya;
  z2 = z * z;
  pz = MADD (z * z2, MADD (z2, e1.d, e0.d), z);
  fi = xfg[i][1].d;
  gi = xfg[i][2].d;

  if (n)
    {
      /* -cot */
      t2 = pz * (fi + gi) / (fi + pz);
      y = gi - t2;
      return (-sy) * y;
    }
  /* tan */
  t2 = pz * (gi + fi) / (gi - pz);
  y = fi + t2;
  return sy * y;
}
