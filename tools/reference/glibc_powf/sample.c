/* A seeded sample of the model against the host's powf, through a volatile
   pointer: `count` pairs of words drawn as given by `mode` (0: any two
   words; 1: x in [0, 2) and y one of the example's exponents, 0.5 to 3 by
   0.05f as float sums; 2: positive finite x and y within 8 of 0). Prints
   the pairs compared, the differences and the last differing pair. */
#define _GNU_SOURCE
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
float model_powf (float, float);
static float (*volatile host_powf) (float, float) = powf;
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
      uint32_t wx = next (), wy = next (), a, b; float x, y, h, m;
      if (mode == 1) { wx %= 0x40000000u; memcpy (&x, &wx, 4); y = exponents[wy % ne]; }
      else if (mode == 2) { wx %= 0x7f800000u; memcpy (&x, &wx, 4); y = ((int32_t) wy) / 268435456.0f; }
      else { memcpy (&x, &wx, 4); memcpy (&y, &wy, 4); }
      h = host_powf (x, y); m = model_powf (x, y);
      memcpy (&a, &h, 4); memcpy (&b, &m, 4);
      if (a != b && !(h != h && m != m)) { differ++; memcpy (&lx, &x, 4); memcpy (&ly, &y, 4); }
    }
  printf ("%llu %llu %08x %08x %d\n", count, differ, lx, ly, ne);
  return 0;
}
