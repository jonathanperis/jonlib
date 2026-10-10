/* The FUSED=1 model against the FUSED=0 model of model.c on every binary32 y
   with |y| < 126 (arguments: first, end, hexadecimal words). Prints the
   arguments, the differences and the last differing word. Build:
     cc -O2 -ffp-contract=off -mfma -DFUSED=1 -DMODEL_POW2=fused_pow2 -c model.c -o fused.o
     cc -O2 -ffp-contract=off -mfma -DFUSED=0 -DMODEL_POW2=plain_pow2 -c model.c -o plain.o
     cc -O2 variants.c fused.o plain.o -lm -o variants */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
float fused_pow2 (float), plain_pow2 (float);
int main (int argc, char **argv)
{
  uint64_t first = strtoull (argv[1], 0, 16), end = strtoull (argv[2], 0, 16), u;
  unsigned long long count = 0, differ = 0; uint32_t example = 0;
  (void) argc;
  for (u = first; u < end; u++)
    {
      uint32_t w = (uint32_t) u, a, b; float y, f, p;
      memcpy (&y, &w, 4);
      if (!(fabsf (y) < 126.0f)) continue;
      count++;
      f = fused_pow2 (y); p = plain_pow2 (y);
      memcpy (&a, &f, 4); memcpy (&b, &p, 4);
      if (a != b) { differ++; example = w; }
    }
  printf ("%llu %llu %08x\n", count, differ, example);
  return 0;
}
