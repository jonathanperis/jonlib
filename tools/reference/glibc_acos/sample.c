/* model.c against this host's acos on seeded samples. Arguments: how many,
   the mode and the seed. Modes: 0 any double word; 1 a double in [-1, 1]
   with a uniform exponent from 2^-60 up; 2 a float in [-1, 1] widened; 3 a
   double a few units from an interval's bound; 4 a double of magnitude
   in [1/8, 1), any of them as likely. Prints the arguments, the
   differences and the last differing word. Build (FUSED=1 for a host whose
   acos is the FMA variant; FUSED=0 with
   GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4):
     cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=1 -DMODEL_ACOS=model_acos -c model.c -o model.o
     cc -std=gnu11 -O2 -ffp-contract=off sample.c model.o -lm -o sample */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
double model_acos (double);
static double (*volatile host) (double) = acos;
static uint64_t state;
static uint64_t next (void)
{
  uint64_t a, b;
  state = state * 6364136223846793005ULL + 1442695040888963407ULL; a = state >> 32;
  state = state * 6364136223846793005ULL + 1442695040888963407ULL; b = state >> 32;
  return a << 32 | b;
}
static const uint64_t bounds[] = {0x3c88000000000000ULL, 0x3fc0000000000000ULL, 0x3fd0000000000000ULL, 0x3fe0000000000000ULL, 0x3fe8000000000000ULL,
                                  0x3fed800000000000ULL, 0x3fee800000000000ULL, 0x3fef000000000000ULL, 0x3ff0000000000000ULL};
int main (int argc, char **argv)
{
  unsigned long long count = strtoull (argv[1], 0, 10), differ = 0, n;
  int mode = atoi (argv[2]);
  uint64_t last = 0;
  (void) argc;
  state = strtoull (argv[3], 0, 10);
  for (n = 0; n < count; n++)
    {
      uint64_t w = next (), a, b;
      double x, h, m;
      if (mode == 1) w = (w & 0x800fffffffffffffULL) | ((0x3c3ULL + (w >> 52 & 0x7ff) % 61) << 52);
      else if (mode == 2) { uint32_t f = (uint32_t) w % 0x3f800001u | (uint32_t) (w >> 32 & 0x80000000u); float y; memcpy (&y, &f, 4); x = (double) y; memcpy (&w, &x, 8); }
      else if (mode == 3) w = (bounds[(w >> 8) % 9] + (int64_t) ((w >> 16) % 4097) - 2048) | (w & 0x8000000000000000ULL);
      else if (mode == 4) w = (0x3fc0000000000000ULL + (w & 0x7fffffffffffffffULL) % 0x0030000000000000ULL) | (w & 0x8000000000000000ULL);
      memcpy (&x, &w, 8);
      h = host (x); m = model_acos (x);
      memcpy (&a, &h, 8); memcpy (&b, &m, 8);
      if (a != b && !(h != h && m != m)) { differ++; last = w; }
    }
  printf ("%llu %llu %016llx\n", count, differ, (unsigned long long) last);
  return 0;
}
