/* The FUSED=1 model against the FUSED=0 model of model.c for every float x
   and the exponent (double) (1.0f/3.0f) (arguments as exhaustive.c's).
   Prints the words compared, the doubles that differ, the floats that
   differ, the refusals and the last word whose floats differ. Build:
     cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=1 -DMODEL_POW=fused_pow -c model.c -o fused.o
     cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=0 -DMODEL_POW=plain_pow -c model.c -o plain.o
     cc -std=gnu11 -O2 variants.c fused.o plain.o -lm -o variants */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
double fused_pow (double, double, int *), plain_pow (double, double, int *);
int main (int argc, char **argv)
{
  uint64_t first = strtoull (argv[1], 0, 0), count = strtoull (argv[2], 0, 0), n, doubles = 0, floats = 0, refusals = 0;
  uint32_t last = 0;
  const double third = (double) (1.0f / 3.0f);
  (void) argc;
  for (n = 0; n < count; n++)
    {
      uint32_t w = (uint32_t) (first + n);
      float x, ff, pf;
      double f, p;
      uint64_t a, b;
      int r1, r2;
      memcpy (&x, &w, 4);
      f = fused_pow ((double) x, third, &r1);
      p = plain_pow ((double) x, third, &r2);
      if (r1 || r2) { refusals++; continue; }
      memcpy (&a, &f, 8); memcpy (&b, &p, 8);
      if (a != b && !(f != f && p != p)) doubles++;
      ff = (float) f; pf = (float) p;
      if (memcmp (&ff, &pf, 4) != 0 && !(ff != ff && pf != pf)) { floats++; last = w; }
    }
  printf ("%llu %llu %llu %llu %08x\n", (unsigned long long) count, (unsigned long long) doubles, (unsigned long long) floats, (unsigned long long) refusals, last);
  return 0;
}
