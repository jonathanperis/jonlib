/* The FUSED=1 model against the FUSED=0 model of model.c on a seeded sample
   (arguments as sample.c's). Prints the arguments, the doubles that differ,
   the floats they narrow to that differ, and the last word whose floats
   differ. Build:
     cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=1 -DMODEL_ACOS=fused_acos -c model.c -o fused.o
     cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=0 -DMODEL_ACOS=plain_acos -c model.c -o plain.o
     cc -std=gnu11 -O2 variants.c fused.o plain.o -lm -o variants */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
double fused_acos (double), plain_acos (double);
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
  unsigned long long count = strtoull (argv[1], 0, 10), doubles = 0, floats = 0, n;
  int mode = atoi (argv[2]);
  uint64_t last = 0;
  (void) argc;
  state = strtoull (argv[3], 0, 10);
  for (n = 0; n < count; n++)
    {
      uint64_t w = next (), a, b;
      double x, f, p;
      float ff, pf;
      if (mode == 1) w = (w & 0x800fffffffffffffULL) | ((0x3c3ULL + (w >> 52 & 0x7ff) % 61) << 52);
      else if (mode == 2) { uint32_t g = (uint32_t) w % 0x3f800001u | (uint32_t) (w >> 32 & 0x80000000u); float y; memcpy (&y, &g, 4); x = (double) y; memcpy (&w, &x, 8); }
      else if (mode == 3) w = (bounds[(w >> 8) % 9] + (int64_t) ((w >> 16) % 4097) - 2048) | (w & 0x8000000000000000ULL);
      else if (mode == 4) w = (0x3fc0000000000000ULL + (w & 0x7fffffffffffffffULL) % 0x0030000000000000ULL) | (w & 0x8000000000000000ULL);
      memcpy (&x, &w, 8);
      f = fused_acos (x); p = plain_acos (x);
      memcpy (&a, &f, 8); memcpy (&b, &p, 8);
      if (a != b && !(f != f && p != p)) doubles++;
      ff = (float) f; pf = (float) p;
      if (memcmp (&ff, &pf, 4) != 0 && !(ff != ff && pf != pf)) { floats++; last = w; }
    }
  printf ("%llu %llu %llu %016llx\n", count, doubles, floats, (unsigned long long) last);
  return 0;
}
