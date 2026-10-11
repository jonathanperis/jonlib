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
 * sysdeps/ieee754/dbl-64/s_sin.c (unmodified copy in tools/reference/glibc239,
 * SHA-256 d607bcb0823bb793ecf917546266559aa6f3da6504719ecb90db8b6cb4bb8b1b)
 * as the x86_64 multiarch library executes it.
 * glibc builds s_sin.c four times (sysdeps/x86_64/fpu/multiarch/s_sin*.c) and
 * selects one by ifunc:
 *
 *   FUSED=1  __sin_fma and __cos_fma, built with -mfma -mavx2 (CPUs with FMA
 *            and AVX2, the CI runners). GCC contracts a*b+c into FMA.
 *   FUSED=0  __sin_sse2 and __cos_sse2 (and the AVX build, the same
 *            arithmetic VEX-encoded): no contraction.
 *
 * Every double operation of the source is written out here in the order the
 * glibc 2.39 binary of Ubuntu 24.04 (libm.so.6, build ID
 * d53fcbff9f855463606b25cfbe2a2e10856ea3a7) performs it; MADD(a, b, c) is
 * a*b + c, MSUB(a, b, c) is a*b - c and NMADD(a, b, c) is c - a*b, each
 * rounded once when FUSED and twice otherwise. Compile with contraction off.
 * __branred is the pinned branred.c, which glibc builds once, without FMA.
 * Out of contract: errno, exception flags and non-nearest rounding modes.
 */
#include <math.h>
#include <string.h>
#include "endian.h"
#include "mydefs.h"
#include "usncs.h"

#ifndef FUSED
# error "define FUSED to 1 (the __sin_fma/__cos_fma variants) or 0 (SSE2/AVX)"
#endif
#ifndef MODEL_SIN
# define MODEL_SIN model_sin
#endif
#ifndef MODEL_COS
# define MODEL_COS model_cos
#endif
#ifndef MODEL_BRANRED
# define MODEL_BRANRED __branred
#endif
#ifndef MODEL_TABLE
# define MODEL_TABLE __sincostab
#endif

#if FUSED
# define MADD(a, b, c) fma ((a), (b), (c))
# define MSUB(a, b, c) fma ((a), (b), -(c))
# define NMADD(a, b, c) fma (-(a), (b), (c))
#else
# define MADD(a, b, c) ((a) * (b) + (c))
# define MSUB(a, b, c) ((a) * (b) - (c))
# define NMADD(a, b, c) ((c) - (a) * (b))
#endif

extern const union
{
  int4 i[880];
  double x[440];
} MODEL_TABLE;

int MODEL_BRANRED (double, double *, double *);

static const double
  sn3 = -1.66666666666664880952546298448555E-01,
  sn5 = 8.33333214285722277379541354343671E-03,
  cs2 = 4.99999999999999999999950396842453E-01,
  cs4 = -4.16666666666664434524222570944589E-02,
  cs6 = 1.38888874007937613028114285595617E-03;

/* do_cos of s_sin.c.  */
static double
model_do_cos (double x, double dx)
{
  mynumber u;
  double xx, s, sn, ssn, c, cs, ccs, cor;
  int4 k;

  if (x < 0)
    dx = -dx;
  u.x = big + fabs (x);
  x = fabs (x) - (u.x - big) + dx;
  xx = x * x;
  s = MADD (x * xx, MADD (xx, sn5, sn3), x);
  c = xx * MADD (xx, MADD (xx, cs6, cs4), cs2);
  k = u.i[LOW_HALF] << 2;
  sn = MODEL_TABLE.x[k];
  ssn = MODEL_TABLE.x[k + 1];
  cs = MODEL_TABLE.x[k + 2];
  ccs = MODEL_TABLE.x[k + 3];
  cor = NMADD (s, sn, NMADD (c, cs, NMADD (s, ssn, ccs)));
  return cs + cor;
}

/* do_sin of s_sin.c.  */
static double
model_do_sin (double x, double dx)
{
  mynumber u;
  double xold = x, xx, s, sn, ssn, c, cs, ccs, cor, p;
  int4 k;

  if (fabs (x) < 0.126)
    {
      xx = x * x;
      p = MADD (MADD (MADD (MADD (s5, xx, s4), xx, s3), xx, s2), xx, s1);
      return x + MADD (xx, MSUB (p, x, 0.5 * dx), dx);
    }
  if (x <= 0)
    dx = -dx;
  u.x = big + fabs (x);
  x = fabs (x) - (u.x - big);
  xx = x * x;
  s = x + MADD (x * xx, MADD (xx, sn5, sn3), dx);
  c = MADD (x, dx, xx * MADD (xx, MADD (xx, cs6, cs4), cs2));
  k = u.i[LOW_HALF] << 2;
  sn = MODEL_TABLE.x[k];
  ssn = MODEL_TABLE.x[k + 1];
  cs = MODEL_TABLE.x[k + 2];
  ccs = MODEL_TABLE.x[k + 3];
  cor = MADD (s, cs, NMADD (c, sn, MADD (s, ccs, ssn)));
  return copysign (sn + cor, xold);
}

/* reduce_sincos of s_sin.c.  */
static int4
model_reduce (double x, double *a, double *da)
{
  mynumber v;
  double t, xn, y, b, db, t2;

  t = MADD (x, hpinv, toint);
  xn = t - toint;
  v.x = t;
  y = NMADD (xn, mp2, NMADD (xn, mp1, x));
  t2 = NMADD (xn, pp3, y);
  db = NMADD (xn, pp3, y - t2);
  b = NMADD (xn, pp4, t2);
  db = db + NMADD (xn, pp4, t2 - b);
  *a = b;
  *da = db;
  return v.i[LOW_HALF] & 3;
}

static double
model_do_sincos (double a, double da, int4 n)
{
  double retval = (n & 1) ? model_do_cos (a, da) : model_do_sin (a, da);
  return (n & 2) ? -retval : retval;
}

double
MODEL_SIN (double x)
{
  double t, a, da;
  mynumber u;
  int4 k, n;

  u.x = x;
  k = 0x7fffffff & u.i[HIGH_HALF];
  if (k < 0x3e500000)
    return x;
  if (k < 0x3feb6000)
    return model_do_sin (x, 0);
  if (k < 0x400368fd)
    {
      t = hp0 - fabs (x);
      return copysign (model_do_cos (t, hp1), x);
    }
  if (k < 0x419921FB)
    {
      n = model_reduce (x, &a, &da);
      return model_do_sincos (a, da, n);
    }
  if (k < 0x7ff00000)
    {
      n = MODEL_BRANRED (x, &a, &da);
      return model_do_sincos (a, da, n);
    }
  return x / x;
}

double
MODEL_COS (double x)
{
  double y, a, da;
  mynumber u;
  int4 k, n;

  u.x = x;
  k = 0x7fffffff & u.i[HIGH_HALF];
  if (k < 0x3e400000)
    return 1.0;
  if (k < 0x3feb6000)
    return model_do_cos (x, 0);
  if (k < 0x400368fd)
    {
      y = hp0 - fabs (x);
      a = y + hp1;
      da = (y - a) + hp1;
      return model_do_sin (a, da);
    }
  if (k < 0x419921FB)
    {
      n = model_reduce (x, &a, &da);
      return model_do_sincos (a, da, n + 1);
    }
  if (k < 0x7ff00000)
    {
      n = MODEL_BRANRED (x, &a, &da);
      return model_do_sincos (a, da, n + 1);
    }
  return x / x;
}
