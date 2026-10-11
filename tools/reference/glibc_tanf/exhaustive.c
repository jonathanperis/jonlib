/* Every binary32 argument in [first, end): the model against the host's
   tanf (NaN results compared as NaN). Arguments: first, end (hexadecimal
   words). Prints the count of arguments and of differences, and the first
   differing words. */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
float model_tanf (float);
static float (*volatile host_tanf) (float) = tanf;
int main (int argc, char **argv)
{
  uint64_t first = strtoull (argv[1], NULL, 16), end = strtoull (argv[2], NULL, 16), different = 0;
  (void) argc;
  for (uint64_t u = first; u < end; u++)
    {
      uint32_t w = (uint32_t) u, a, b;
      float x, m, h;
      memcpy (&x, &w, 4);
      m = model_tanf (x); h = host_tanf (x);
      memcpy (&a, &m, 4); memcpy (&b, &h, 4);
      if (a != b && !(m != m && h != h))
        if (different++ < 4) fprintf (stderr, "%08x: model %08x host %08x\n", w, a, b);
    }
  printf ("%llu %llu\n", (unsigned long long) (end - first), (unsigned long long) different);
  return 0;
}
