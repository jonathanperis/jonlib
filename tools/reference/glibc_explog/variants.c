/* The FUSED=1 models against the FUSED=0 models of model.c on every argument
   of the two domains (arguments: first, end, hexadecimal words). Prints the
   expf and the logf differences, and the differing expf words on stderr.
   Build:
     cc -O2 -ffp-contract=off -mfma -DFUSED=1 -DMODEL_EXPF=fused_expf -DMODEL_LOGF=fused_logf -c model.c -o fused.o
     cc -O2 -ffp-contract=off -mfma -DFUSED=0 -DMODEL_EXPF=plain_expf -DMODEL_LOGF=plain_logf -c model.c -o plain.o
     cc -O2 variants.c fused.o plain.o -lm -o variants */
#define _GNU_SOURCE
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
float fused_expf (float), plain_expf (float), fused_logf (float), plain_logf (float);
static uint32_t bits (float v) { uint32_t b; memcpy (&b, &v, 4); return b; }
int main (int argc, char **argv)
{
  uint64_t first = strtoull (argv[1], 0, 16), end = strtoull (argv[2], 0, 16), u;
  unsigned long long ev = 0, lv = 0, shown = 0;
  (void) argc;
  for (u = first; u < end; u++)
    {
      uint32_t w = (uint32_t) u; float x; memcpy (&x, &w, 4);
      if (fabsf (x) < 87.0f)
        {
          if (bits (fused_expf (x)) != bits (plain_expf (x))) ev++;
          if (bits (fused_expf (x)) != bits (plain_expf (x)) && shown++ < 8) fprintf (stderr, "expf variants differ at %08x: fused %08x plain %08x\n", w, bits (fused_expf (x)), bits (plain_expf (x)));
        }
      if (w >= 0x00800000 && w < 0x7f800000 && bits (fused_logf (x)) != bits (plain_logf (x))) lv++;
    }
  printf ("%llu %llu\n", ev, lv);
  return 0;
}
