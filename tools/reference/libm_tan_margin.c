/* Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
 *
 * How far from a binary64 rounding boundary the exact tangent lies where the
 * host tan differs from correct rounding (CORE-MATH cr_tan), over the
 * argument sets of tools/reference/libm_survey.c:
 *
 *   libm_tan_margin perspective|begin3d THREADS [LIMIT]
 *
 * The margin of an argument is the distance, in ulps of the correctly rounded
 * result, from tan(x) (binary128 tanq) to the nearest rounding boundary. The
 * report gives the largest margin of any difference and, per binade of the
 * margin, the differences and a 1/1024 sample of agreeing arguments. LIMIT
 * (default 1e30) skips |x| >= LIMIT. Needs GCC's libquadmath (Linux):
 *
 *   gcc -std=gnu11 -O2 -ffp-contract=off tools/reference/libm_tan_margin.c \
 *       tools/reference/core_math/tan.c -lquadmath -lm -lpthread
 */
#include <math.h>
#include <pthread.h>
#include <quadmath.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

double cr_tan(double);
static double (*volatile native_tan)(double) = tan;
static float u2f(uint32_t u) { float x; memcpy(&x, &u, 4); return x; }

static int begin3d;
static float deg2rad;
static double limit = 1e30;
static atomic_uint_fast64_t next_chunk;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
#define CHUNK (1u << 20)
static double largest;
static uint32_t largest_input;
static uint64_t differences, histogram[64], sample[64], sampled;

static double margin(double x, double r) {
  __float128 t = tanq((__float128)x);
  double up = nextafter(r, INFINITY), down = nextafter(r, -INFINITY);
  __float128 high = ((__float128)r + up) / 2, low = ((__float128)r + down) / 2;
  __float128 dh = fabsq(t - high) / ((__float128)up - r), dl = fabsq(t - low) / ((__float128)r - down);
  return (double)(dh < dl ? dh : dl);
}

static int binade(double m) {
  int b = m <= 0 ? 63 : (int)(-log2(m));
  return b < 0 ? 0 : b > 63 ? 63 : b;
}

static void *work(void *unused) {
  (void)unused;
  for (;;) {
    uint64_t c = atomic_fetch_add(&next_chunk, 1);
    if (c >= (1ull << 32) / CHUNK) break;
    for (uint64_t k = 0; k < CHUNK; k++) {
      uint32_t u = (uint32_t)(c * CHUNK + k);
      float g = u2f(u);
      if (!isfinite(g)) continue;
      volatile double half = (double)g * 0.5, d = deg2rad;
      double x = begin3d ? half * d : half;
      if (!(fabs(x) < limit)) continue;
      double n = native_tan(x), r = cr_tan(x);
      if (n != r) {
        double m = margin(x, r);
        pthread_mutex_lock(&lock);
        differences++; histogram[binade(m)]++;
        if (m > largest) { largest = m; largest_input = u; }
        pthread_mutex_unlock(&lock);
      } else if ((u & 1023) == 0) {
        double m = margin(x, r);
        pthread_mutex_lock(&lock);
        sample[binade(m)]++; sampled++;
        pthread_mutex_unlock(&lock);
      }
    }
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "usage: libm_tan_margin perspective|begin3d THREADS [LIMIT]\n"); return 2; }
  begin3d = !strcmp(argv[1], "begin3d");
  int threads = atoi(argv[2]);
  if (argc > 3) limit = strtod(argv[3], 0);
  if (threads < 1 || threads > 64) return 2;
  volatile float pi = 3.14159265358979323846f, degrees = 180.0f;
  deg2rad = pi / degrees;
  pthread_t pool[64];
  for (int i = 0; i < threads; i++) pthread_create(&pool[i], 0, work, 0);
  for (int i = 0; i < threads; i++) pthread_join(pool[i], 0);
  printf("%s |x| < %g: differences %llu, largest margin %.6g ulp at input %08x\n", argv[1], limit,
         (unsigned long long)differences, largest, largest_input);
  for (int b = 0; b < 64; b++)
    if (histogram[b] || sample[b])
      printf("  margin in [2^-%d, 2^-%d): differences %llu, agreeing sample %llu\n", b + 1, b,
             (unsigned long long)histogram[b], (unsigned long long)sample[b]);
  printf("agreeing sample size %llu\n", (unsigned long long)sampled);
  return 0;
}
