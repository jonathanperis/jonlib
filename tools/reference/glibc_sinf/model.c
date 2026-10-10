/* Explicit-operation model of glibc 2.39/2.41 x86_64 sinf/cosf.
   Adapted from Arm optimized-routines math/sinf.c, math/cosf.c, math/sincosf.h
   and math/sincosf_data.c (Copyright (c) 2018-2024 Arm Limited; MIT
   alternative, see LICENSES/arm-math.txt), which glibc ships as
   sysdeps/ieee754/flt-32/s_sinf.c, s_cosf.c, s_sincosf.h, sincosf_poly.h and
   s_sincosf_data.c with TOINT_INTRINSICS 0 on x86_64.
   FUSED=1: the __sinf_fma/__cosf_fma ifunc variants (-mfma -mavx2), where GCC
   contracts every a + b*c of reduce_fast and sinf_poly into one fma (the
   disassembly of Ubuntu's glibc 2.39 libm). FUSED=0: the SSE2 variants.
   Compile with -ffp-contract=off. Defines MODEL_SINF and MODEL_COSF. */
#include <math.h>
#include <stdint.h>
#include <string.h>

#if FUSED
#define SC_MADD(a, b, c) fma (a, b, c)
#else
#define SC_MADD(a, b, c) ((a) * (b) + (c))
#endif

static const double SC_SIGN[4] = {1.0, -1.0, -1.0, 1.0};
static const double SC_HPI_INV = 0x1.45F306DC9C883p+23, SC_HPI = 0x1.921FB54442D18p0, SC_PI63 = 0x1.921FB54442D18p-62;
/* The cosine polynomial, negated in the second table. */
static const double SC_C0[2] = {0x1p0, -0x1p0}, SC_C1[2] = {-0x1.ffffffd0c621cp-2, 0x1.ffffffd0c621cp-2},
  SC_C2[2] = {0x1.55553e1068f19p-5, -0x1.55553e1068f19p-5}, SC_C3[2] = {-0x1.6c087e89a359dp-10, 0x1.6c087e89a359dp-10},
  SC_C4[2] = {0x1.99343027bf8c3p-16, -0x1.99343027bf8c3p-16};
static const double SC_S1 = -0x1.555545995a603p-3, SC_S2 = 0x1.1107605230bc4p-7, SC_S3 = -0x1.994eb3774cf24p-13;
static const uint32_t SC_INV_PIO4[24] = {
  0xa2, 0xa2f9, 0xa2f983, 0xa2f9836e, 0xf9836e4e, 0x836e4e44, 0x6e4e4415, 0x4e441529,
  0x441529fc, 0x1529fc27, 0x29fc2757, 0xfc2757d1, 0x2757d1f5, 0x57d1f534, 0xd1f534dd, 0xf534ddc0,
  0x34ddc0db, 0xddc0db62, 0xc0db6295, 0xdb629599, 0x6295993c, 0x95993c43, 0x993c4390, 0x3c439041};

static uint32_t sc_abstop12 (float y)
{
  uint32_t i;
  memcpy (&i, &y, 4);
  return (i >> 20) & 0x7ff;
}

/* sinf_poly: x the signed reduced argument, x2 the square of the unsigned one;
   t selects the negated table, odd the cosine polynomial. */
static float sc_poly (double x, double x2, int t, int odd)
{
  if (!odd)
    {
      double x3 = x2 * x, s1 = SC_MADD (x2, SC_S3, SC_S2), x7 = x2 * x3, s = SC_MADD (x3, SC_S1, x);
      return (float) SC_MADD (s1, x7, s);
    }
  double x4 = x2 * x2, c1 = SC_MADD (x2, SC_C1[t], SC_C0[t]), c2 = SC_MADD (x2, SC_C4[t], SC_C3[t]), x6 = x2 * x4;
  double c = SC_MADD (x4, SC_C2[t], c1);
  return (float) SC_MADD (c2, x6, c);
}

static float sc_evaluate (float y, int cosine)
{
  double x = y, r;
  uint32_t top = sc_abstop12 (y);
  int n, k;
  if (top < sc_abstop12 (0x1.921FB6p-1f))
    {
      if (top < sc_abstop12 (0x1p-12f))
        return cosine ? 1.0f : y;
      return sc_poly (x, x * x, 0, cosine);
    }
  if (top < sc_abstop12 (120.0f))
    {
      /* reduce_fast */
      n = ((int32_t) (x * SC_HPI_INV) + 0x800000) >> 24;
      r = SC_MADD (-(double) n, SC_HPI, x);
      k = n;
    }
  else if (top < sc_abstop12 (INFINITY))
    {
      /* reduce_large */
      uint32_t xi;
      memcpy (&xi, &y, 4);
      const uint32_t *arr = &SC_INV_PIO4[(xi >> 26) & 15];
      uint32_t m = ((xi & 0xffffff) | 0x800000) << ((xi >> 23) & 7);
      uint64_t res0 = m * arr[0], res1 = (uint64_t) m * arr[4], res2 = (uint64_t) m * arr[8];
      res0 = (res2 >> 32) | (res0 << 32);
      res0 += res1;
      uint64_t q = (res0 + (1ULL << 61)) >> 62;
      res0 -= q << 62;
      r = (double) (int64_t) res0 * SC_PI63;
      n = (int) q;
      k = n + (int) (xi >> 31);
    }
  else
    return (y - y) / (y - y);
  /* Sign and table from k; the polynomial from the quadrant (plus one for cosf). */
  return sc_poly (r * SC_SIGN[k & 3], r * r, (k & 2) != 0, (n + cosine) & 1);
}

float MODEL_SINF (float y) { return sc_evaluate (y, 0); }
float MODEL_COSF (float y) { return sc_evaluate (y, 1); }
