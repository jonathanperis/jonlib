/* Every binary32 exponent y with |y| < 126: the model against the host's
   powf (2.0f, y) and exp2f (y), and every binary64 intermediate inside the
   domain of Jonlib's exact helpers (zero or normal operands and results, sum
   operands within 900 binades, FMA addend exponent within [-554, 255] of the
   product's). Arguments: first, end (hexadecimal words). Prints the counts:
   arguments in the domain, powf differences, exp2f differences, domain
   violations. */
#define _GNU_SOURCE
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
float model_pow2 (float);
static float (*volatile host_powf) (float, float) = powf;
static float (*volatile host_exp2f) (float) = exp2f;
static volatile float two = 2.0f;
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
#if FUSED
  value (a); value (b); value (c);
  if (a != 0 && b != 0 && c != 0)
    {
      int gap = (stored (c) - 1023) - (stored (a) - 1023) - (stored (b) - 1023);
      if (gap < -554 || gap > 255) domain++;
    }
  value (fma (a, b, c));
  return fma (a, b, c);
#else
  return add (mul (a, b), c);
#endif
}
static void intermediates (float y)
{
  static const double C0 = 0x1.c6af84b912394p-5, C1 = 0x1.ebfce50fac4f3p-3, C2 = 0x1.62e42ff0c52d6p-1, SHIFT = 0x1.8p47;
  double xd = y, kd = add (xd, SHIFT), r, z, r2, q;
  kd = add (kd, -SHIFT);
  r = add (xd, -kd);
  z = madd (C0, r, C1);
  r2 = mul (r, r);
  q = madd (C2, r, 1.0);
  q = madd (z, r2, q);
  /* The scale 2^(k/32) is in [2^-127, 2^127) and q near 1. */
  value (q);
}
static int same (float a, float b)
{
  uint32_t x, y;
  memcpy (&x, &a, 4); memcpy (&y, &b, 4);
  return x == y;
}
int main (int argc, char **argv)
{
  uint64_t first = strtoull (argv[1], 0, 16), end = strtoull (argv[2], 0, 16), u;
  unsigned long long count = 0, power = 0, exp2 = 0;
  (void) argc;
  for (u = first; u < end; u++)
    {
      uint32_t w = (uint32_t) u;
      float y, m;
      memcpy (&y, &w, 4);
      if (!(fabsf (y) < 126.0f))
        continue;
      count++;
      m = model_pow2 (y);
      if (!same (m, host_powf (two, y))) power++;
      if (!same (m, host_exp2f (y))) exp2++;
      intermediates (y);
    }
  printf ("%llu %llu %llu %llu\n", count, power, exp2, domain);
  return 0;
}
