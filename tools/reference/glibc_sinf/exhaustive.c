/* Every binary32 argument: the model against the host's sinf, cosf and
   sincosf (NaN results compared as NaN), and, for FUSED, every binary64
   intermediate inside the domain of Jonlib's exact scaled helpers (zero or
   normal operands and results, FMA addend exponent within [-554, 255] of
   the product's, sum operands within 900 binades). Arguments: first, end
   (hexadecimal words). Prints the counts. */
#define _GNU_SOURCE
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
float model_sinf (float), model_cosf (float);
static float (*volatile host_sinf) (float) = sinf, (*volatile host_cosf) (float) = cosf;
static void (*volatile host_sincosf) (float, float *, float *) = sincosf;
static unsigned long long domain;
static int stored (double v) { uint64_t b; memcpy (&b, &v, 8); return (int) ((b >> 52) & 2047); }
static void value (double v) { int e = stored (v); if (v != 0 && (e == 0 || e == 2047)) domain++; }
static double mul (double a, double b) { value (a); value (b); value (a * b); return a * b; }
static double add (double a, double b)
{
  value (a); value (b);
  if (a != 0 && b != 0 && abs (stored (a) - stored (b)) > 900) domain++;
  value (a + b);
  return a + b;
}
static double madd (double a, double b, double c)
{
  value (a); value (b); value (c);
  if (a != 0 && b != 0 && c != 0)
    {
      int gap = (stored (c) - 1023) - (stored (a) - 1023) - (stored (b) - 1023);
      if (gap < -554 || gap > 255) domain++;
    }
  value (fma (a, b, c));
  return fma (a, b, c);
}
static const double HPI_INV = 0x1.45F306DC9C883p+23, HPI = 0x1.921FB54442D18p0, PI63 = 0x1.921FB54442D18p-62;
static const double C[5] = {0x1p0, -0x1.ffffffd0c621cp-2, 0x1.55553e1068f19p-5, -0x1.6c087e89a359dp-10, 0x1.99343027bf8c3p-16};
static const double S1 = -0x1.555545995a603p-3, S2 = 0x1.1107605230bc4p-7, S3 = -0x1.994eb3774cf24p-13;
static const uint32_t INV_PIO4[24] = {
  0xa2, 0xa2f9, 0xa2f983, 0xa2f9836e, 0xf9836e4e, 0x836e4e44, 0x6e4e4415, 0x4e441529,
  0x441529fc, 0x1529fc27, 0x29fc2757, 0xfc2757d1, 0x2757d1f5, 0x57d1f534, 0xd1f534dd, 0xf534ddc0,
  0x34ddc0db, 0xddc0db62, 0xc0db6295, 0xdb629599, 0x6295993c, 0x95993c43, 0x993c4390, 0x3c439041};
/* Both polynomials on the unsigned reduced argument (signs and the negated
   table change no exponent). */
static void polynomials (double r)
{
  double x2 = mul (r, r), x3 = mul (x2, r), s1 = madd (x2, S3, S2), x7 = mul (x2, x3), s = madd (x3, S1, r);
  madd (s1, x7, s);
  double x4 = mul (x2, x2), c1 = madd (x2, C[1], C[0]), c2 = madd (x2, C[4], C[3]), x6 = mul (x2, x4);
  madd (c2, x6, madd (x4, C[2], c1));
}
static void intermediates (uint32_t u, float y)
{
  uint32_t top = (u >> 20) & 0x7ff;
  double x = y;
  if (top < 0x398 || top >= 0x7f8)
    return;
  if (top < 0x3f4)
    polynomials (x);
  else if (top < 0x42f)
    {
      int n = ((int32_t) mul (x, HPI_INV) + 0x800000) >> 24;
      polynomials (fabs (madd (-(double) n, HPI, x)));
    }
  else
    {
      const uint32_t *arr = &INV_PIO4[(u >> 26) & 15];
      uint32_t m = ((u & 0xffffff) | 0x800000) << ((u >> 23) & 7);
      uint64_t res0 = m * arr[0], res1 = (uint64_t) m * arr[4], res2 = (uint64_t) m * arr[8];
      res0 = (res2 >> 32) | (res0 << 32);
      res0 += res1;
      res0 -= ((res0 + (1ULL << 61)) >> 62) << 62;
      int64_t v = (int64_t) res0;
      /* Jonlib converts as the exact high half plus the low word, rounded once. */
      double converted = add ((double) (v >> 32) * 0x1p32, (double) (uint32_t) v);
      polynomials (fabs (mul (converted, PI63)));
    }
}
static int same (float a, float b) { return memcmp (&a, &b, 4) == 0 || (isnan (a) && isnan (b)); }
int main (int argc, char **argv)
{
  uint64_t first = strtoull (argv[1], 0, 16), end = strtoull (argv[2], 0, 16);
  unsigned long long sine = 0, cosine = 0, both = 0;
  for (uint64_t i = first; i < end; i++)
    {
      uint32_t u = (uint32_t) i;
      float y, s, c, ms, mc;
      memcpy (&y, &u, 4);
      ms = model_sinf (y); mc = model_cosf (y);
      sine += !same (host_sinf (y), ms);
      cosine += !same (host_cosf (y), mc);
      host_sincosf (y, &s, &c);
      both += !same (s, ms) || !same (c, mc);
#if FUSED
      intermediates (u, y);
#endif
    }
  printf ("%llu %llu %llu %llu\n", sine, cosine, both, domain);
  return 0;
}
