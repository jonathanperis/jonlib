/* Every binary32 argument of each domain: the models against the host's expf
   (a finite x with |x| < 87) and logf (a positive normal x), and, for FUSED,
   every binary64 intermediate inside the domain of Jonlib's exact scaled
   helpers (zero or normal operands and results, FMA addend exponent within
   [-554, 255] of the product's, sum operands within 900 binades); for the
   unfused model the same value and sum conditions. Arguments: first, end
   (hexadecimal words). Prints: expf arguments, expf differences, logf
   arguments, logf differences, domain violations.
   The two variants of expf differ at x = 0x4202422f and x = 0xc27c65d9 only
   (variants.c); logf's never do. */
#define _GNU_SOURCE
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
float model_expf (float), model_logf (float);
static float (*volatile host_expf) (float) = expf;
static float (*volatile host_logf) (float) = logf;
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
static void exp_intermediates (float x)
{
  static const double INVLN2N = 0x1.71547652b82fep+0 * 32, SHIFT = 0x1.8p+52;
  static const double C0 = 0x1.c6af84b912394p-5 / 32 / 32 / 32, C1 = 0x1.ebfce50fac4f3p-3 / 32 / 32, C2 = 0x1.62e42ff0c52d6p-1 / 32;
  double z = mul (INVLN2N, x), kd = add (z, SHIFT), r, r2, y;
  kd = add (kd, -SHIFT);
#if FUSED
  r = madd (INVLN2N, x, -kd);
#else
  r = add (z, -kd);
#endif
  z = madd (C0, r, C1);
  r2 = mul (r, r);
  y = madd (C2, r, 1.0);
  y = madd (z, r2, y);
  value (y);
}
static void log_intermediates (float x)
{
  static const double INVC[16] = {0x1.661ec79f8f3bep+0, 0x1.571ed4aaf883dp+0, 0x1.49539f0f010bp+0, 0x1.3c995b0b80385p+0, 0x1.30d190c8864a5p+0, 0x1.25e227b0b8eap+0, 0x1.1bb4a4a1a343fp+0, 0x1.12358f08ae5bap+0, 0x1.0953f419900a7p+0, 0x1p+0, 0x1.e608cfd9a47acp-1, 0x1.ca4b31f026aap-1, 0x1.b2036576afce6p-1, 0x1.9c2d163a1aa2dp-1, 0x1.886e6037841edp-1, 0x1.767dcf5534862p-1};
  static const double LOGC[16] = {-0x1.57bf7808caadep-2, -0x1.2bef0a7c06ddbp-2, -0x1.01eae7f513a67p-2, -0x1.b31d8a68224e9p-3, -0x1.6574f0ac07758p-3, -0x1.1aa2bc79c81p-3, -0x1.a4e76ce8c0e5ep-4, -0x1.1973c5a611cccp-4, -0x1.252f438e10c1ep-5, 0x0p+0, 0x1.aa5aa5df25984p-5, 0x1.c5e53aa362eb4p-4, 0x1.526e57720db08p-3, 0x1.bc2860d22477p-3, 0x1.1058bc8a07ee1p-2, 0x1.4043057b6ee09p-2};
  static const double LN2 = 0x1.62e42fefa39efp-1, A0 = -0x1.00ea348b88334p-2, A1 = 0x1.5575b0be00b6ap-2, A2 = -0x1.ffffef20a4123p-2;
  uint32_t ix, iz, tmp;
  int k, i;
  float zf;
  double r, r2, y, y0;
  memcpy (&ix, &x, 4);
  if (ix == 0x3f800000) return;
  tmp = ix - 0x3f330000; i = (tmp >> 19) % 16; k = (int32_t) tmp >> 23; iz = ix - (tmp & 0xff800000);
  memcpy (&zf, &iz, 4);
  r = madd (zf, INVC[i], -1.0);
  y0 = madd ((double) k, LN2, LOGC[i]);
  r2 = mul (r, r);
  y = madd (A1, r, A2);
  y = madd (A0, r2, y);
  y = madd (y, r2, add (y0, r));
  value (y);
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
  unsigned long long exps = 0, exp_diff = 0, logs = 0, log_diff = 0;
  (void) argc;
  for (u = first; u < end; u++)
    {
      uint32_t w = (uint32_t) u;
      float x;
      memcpy (&x, &w, 4);
      if (fabsf (x) < 87.0f)
        {
          exps++;
          if (!same (model_expf (x), host_expf (x))) exp_diff++;
          exp_intermediates (x);
        }
      if (w >= 0x00800000 && w < 0x7f800000)
        {
          logs++;
          if (!same (model_logf (x), host_logf (x))) log_diff++;
          log_intermediates (x);
        }
    }
  printf ("%llu %llu %llu %llu %llu\n", exps, exp_diff, logs, log_diff, domain);
  return 0;
}
