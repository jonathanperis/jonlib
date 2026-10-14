/* model.c against this host's pow for every float x and the exponent of
   stb_truetype's cube root, (double) (1.0f/3.0f): the doubles and the floats
   they narrow to. Arguments: the first float word and how many. Prints the
   words compared, the doubles that differ, the floats that differ, the
   arguments the model refuses, and the last differing word. Build (FUSED=1
   for a host whose pow is the FMA variant; FUSED=0 with
   GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4):
     cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=1 -DMODEL_POW=model_pow -c model.c -o model.o
     cc -std=gnu11 -O2 -ffp-contract=off exhaustive.c model.o -lm -o exhaustive */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
double model_pow (double, double, int *);
static double (*volatile host) (double, double) = pow;
int main (int argc, char **argv)
{
  uint64_t first = strtoull (argv[1], 0, 0), count = strtoull (argv[2], 0, 0), n, doubles = 0, floats = 0, refusals = 0;
  uint32_t last = 0;
  const double third = (double) (1.0f / 3.0f);
  (void) argc;
  for (n = 0; n < count; n++)
    {
      uint32_t w = (uint32_t) (first + n);
      float x, hf, mf;
      double h, m;
      uint64_t a, b;
      int refused;
      memcpy (&x, &w, 4);
      m = model_pow ((double) x, third, &refused);
      if (refused) { refusals++; continue; }
      h = host ((double) x, third);
      memcpy (&a, &h, 8); memcpy (&b, &m, 8);
      if (a != b && !(h != h && m != m)) { doubles++; last = w; }
      hf = (float) h; mf = (float) m;
      if (memcmp (&hf, &mf, 4) != 0 && !(hf != hf && mf != mf)) { floats++; last = w; }
    }
  printf ("%llu %llu %llu %llu %08x\n", (unsigned long long) count, (unsigned long long) doubles, (unsigned long long) floats, (unsigned long long) refusals, last);
  return 0;
}
