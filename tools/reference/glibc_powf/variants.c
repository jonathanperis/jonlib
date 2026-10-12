/* The FUSED=1 model against the FUSED=0 model of model.c on a seeded sample
   (arguments as sample.c's: count, mode, seed). Prints the pairs, the
   differences and the last differing pair. Build:
     cc -O2 -ffp-contract=off -mfma -DFUSED=1 -DMODEL_POWF=fused_powf -c model.c -o fused.o
     cc -O2 -ffp-contract=off -mfma -DFUSED=0 -DMODEL_POWF=plain_powf -c model.c -o plain.o
     cc -O2 variants.c fused.o plain.o -lm -o variants */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
float fused_powf (float, float), plain_powf (float, float);
static uint64_t state;
static uint32_t next (void) { state = state * 6364136223846793005ULL + 1442695040888963407ULL; return (uint32_t) (state >> 32); }
int main (int argc, char **argv)
{
  unsigned long long count = strtoull (argv[1], 0, 10), differ = 0, n;
  int mode = atoi (argv[2]);
  uint32_t lx = 0, ly = 0;
  float exponents[64]; int ne = 0;
  (void) argc;
  state = strtoull (argv[3], 0, 10);
  { float e = 1.0f; while (e > 0.5f) e -= 0.05f; if (e <= 0.5f) e = 0.5f; exponents[ne++] = e; while (e < 3.0f && ne < 63) { e += 0.05f; if (e >= 3.0f) e = 3.0f; exponents[ne++] = e; } }
  for (n = 0; n < count; n++)
    {
      uint32_t wx = next (), wy = next (), a, b; float x, y, f, p;
      if (mode == 1) { wx %= 0x40000000u; memcpy (&x, &wx, 4); y = exponents[wy % ne]; }
      else if (mode == 2) { wx %= 0x7f800000u; memcpy (&x, &wx, 4); y = ((int32_t) wy) / 268435456.0f; }
      else { memcpy (&x, &wx, 4); memcpy (&y, &wy, 4); }
      f = fused_powf (x, y); p = plain_powf (x, y);
      memcpy (&a, &f, 4); memcpy (&b, &p, 4);
      if (a != b && !(f != f && p != p)) { differ++; memcpy (&lx, &x, 4); memcpy (&ly, &y, 4); }
    }
  printf ("%llu %llu %08x %08x\n", count, differ, lx, ly);
  return 0;
}
