/* Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
 *
 * Exhaustive comparison of the host libm's binary64 tan and binary32 asinf
 * with correctly rounded results (CORE-MATH cr_tan / cr_asinf, MIT, in
 * tools/reference/core_math) over the argument sets raylib actually passes:
 *
 *   tan-perspective  x = (double)g * 0.5 for every finite binary32 g:
 *                    MatrixPerspective(fovY, ...) computes tan(fovY*0.5) and
 *                    every float-typed caller (camera.fovy*DEG2RAD in rcore.c
 *                    and rcamera.h, the VR fovy) passes a binary32 fovY.
 *   tan-begin3d      x = ((double)f * 0.5) * (double)DEG2RAD for every finite
 *                    binary32 f: BeginMode3D's tan(camera.fovy*0.5*DEG2RAD),
 *                    with raylib's binary32 DEG2RAD (PI/180.0f).
 *   asinf            every binary32 x in [-1, 1]: QuaternionToEuler clamps
 *                    its float argument to [-1, 1] (a NaN passes unclamped
 *                    and is not compared). The glibc 2.41 e_asinf.c source is
 *                    compared too, and every cr_asinf result is checked
 *                    against the host binary64 asin with an 8-ulp margin from
 *                    the binary32 rounding midpoints; inputs inside the
 *                    margin are listed as "ambiguous" for the exact oracle.
 *
 * Native functions are called through volatile function pointers. A stride
 * argument evaluates every stride-th input word only (diagnostic gates);
 * stride 1 is exhaustive. Output is one JSON object. "eval MODE WORD..."
 * prints the argument, native and correctly rounded words for given inputs.
 */
#include <fenv.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

double cr_tan(double);
float cr_asinf(float);
float glibc241_asinf(float);

static double (*volatile native_tan)(double) = tan;
static float (*volatile native_asinf)(float) = asinf;
static double (*volatile native_asin)(double) = asin;

static uint64_t d2u(double x) { uint64_t u; memcpy(&u, &x, 8); return u; }
static uint32_t f2u(float x) { uint32_t u; memcpy(&u, &x, 4); return u; }
static float u2f(uint32_t u) { float x; memcpy(&x, &u, 4); return x; }

enum { TAN_PERSPECTIVE, TAN_BEGIN3D, ASINF };
static int mode;
static uint64_t stride = 1;
static float deg2rad;

#define CHUNK (1u << 20)
#define BUCKETS 2048
#define LIST 64
static atomic_uint_fast64_t next_chunk;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

typedef struct {
  uint64_t evaluated, skipped, native_mismatch, source_mismatch, ambiguous;
  uint64_t bucket_evaluated[BUCKETS], bucket_mismatch[BUCKETS];
  uint32_t bucket_first[BUCKETS]; /* smallest magnitude word with a native mismatch */
} Totals;
static Totals totals;
static uint32_t ambiguous_words[LIST]; static int ambiguous_count;
static uint32_t source_words[LIST]; static int source_count;

static double tan_argument(uint32_t u) {
  volatile double half = (double)u2f(u) * 0.5;
  if (mode == TAN_PERSPECTIVE) return half;
  volatile double d = deg2rad;
  return half * d;
}

static void record(uint32_t *list, int *count, uint32_t u) {
  pthread_mutex_lock(&lock);
  if (*count < LIST) list[(*count)++] = u;
  pthread_mutex_unlock(&lock);
}

static void *work(void *unused) {
  (void)unused;
  Totals *t = calloc(1, sizeof *t);
  for (int i = 0; i < BUCKETS; i++) t->bucket_first[i] = UINT32_MAX;
  for (;;) {
    uint64_t c = atomic_fetch_add(&next_chunk, 1);
    if (c >= (1ull << 32) / CHUNK) break;
    for (uint64_t k = 0; k < CHUNK; k++) {
      uint32_t u = (uint32_t)(c * CHUNK + k);
      if (stride > 1 && u % stride) continue;
      float g = u2f(u);
      uint32_t magnitude = u & 0x7fffffffu;
      if (mode != ASINF) {
        if (!isfinite(g)) { t->skipped++; continue; }
        double x = tan_argument(u);
        int bucket = (int)((d2u(x) >> 52) & 2047);
        t->evaluated++; t->bucket_evaluated[bucket]++;
        if (d2u(native_tan(x)) != d2u(cr_tan(x))) {
          t->native_mismatch++; t->bucket_mismatch[bucket]++;
          if (magnitude < t->bucket_first[bucket]) t->bucket_first[bucket] = magnitude;
        }
      } else {
        if (!(g >= -1.0f && g <= 1.0f)) { t->skipped++; continue; }
        int bucket = (int)((u >> 23) & 255);
        t->evaluated++; t->bucket_evaluated[bucket]++;
        float r = cr_asinf(g);
        if (f2u(native_asinf(g)) != f2u(r)) {
          t->native_mismatch++; t->bucket_mismatch[bucket]++;
          if (magnitude < t->bucket_first[bucket]) t->bucket_first[bucket] = magnitude;
        }
        if (f2u(glibc241_asinf(g)) != f2u(r)) { t->source_mismatch++; record(source_words, &source_count, u); }
        double d = native_asin((double)g);
        float ar = fabsf(r);
        double ad = fabs(d), lower = ((double)ar + (double)nextafterf(ar, 0.0f)) * 0.5,
               upper = ((double)ar + (double)nextafterf(ar, INFINITY)) * 0.5,
               margin = 8.0 * (nextafter(ad, INFINITY) - ad);
        int ambiguous = (signbit(d) != 0) != (signbit(r) != 0);
        if (ar == 0.0f) ambiguous |= d != 0.0;
        else ambiguous |= !(ad > lower + margin && ad < upper - margin);
        if (ambiguous) { t->ambiguous++; record(ambiguous_words, &ambiguous_count, u); }
      }
    }
  }
  pthread_mutex_lock(&lock);
  totals.evaluated += t->evaluated; totals.skipped += t->skipped;
  totals.native_mismatch += t->native_mismatch; totals.source_mismatch += t->source_mismatch;
  totals.ambiguous += t->ambiguous;
  for (int i = 0; i < BUCKETS; i++) {
    totals.bucket_evaluated[i] += t->bucket_evaluated[i];
    totals.bucket_mismatch[i] += t->bucket_mismatch[i];
    if (t->bucket_first[i] < totals.bucket_first[i]) totals.bucket_first[i] = t->bucket_first[i];
  }
  pthread_mutex_unlock(&lock);
  free(t);
  return 0;
}

static void list(const char *name, uint32_t *words, int count) {
  printf(",\"%s\":[", name);
  for (int i = 0; i < count; i++) printf("%s\"%08x\"", i ? "," : "", words[i]);
  printf("]");
}

static int evaluate(int argc, char **argv) {
  for (int i = 3; i < argc; i++) {
    uint32_t u = (uint32_t)strtoul(argv[i], 0, 16);
    if (mode == ASINF) {
      float g = u2f(u);
      printf("%08x %08x %08x %08x\n", u, f2u(native_asinf(g)), f2u(cr_asinf(g)), f2u(glibc241_asinf(g)));
    } else {
      double x = tan_argument(u);
      printf("%08x %016llx %016llx %016llx\n", u, (unsigned long long)d2u(x), (unsigned long long)d2u(native_tan(x)),
             (unsigned long long)d2u(cr_tan(x)));
    }
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc >= 3 && !strcmp(argv[1], "eval")) {
    mode = !strcmp(argv[2], "tan-perspective") ? TAN_PERSPECTIVE : !strcmp(argv[2], "tan-begin3d") ? TAN_BEGIN3D :
           !strcmp(argv[2], "asinf") ? ASINF : -1;
    volatile float pi = 3.14159265358979323846f, degrees = 180.0f;
    deg2rad = pi / degrees;
    return mode < 0 ? 2 : evaluate(argc, argv);
  }
  if (argc < 3) { fprintf(stderr, "usage: libm_survey tan-perspective|tan-begin3d|asinf threads [stride]\n"); return 2; }
  mode = !strcmp(argv[1], "tan-perspective") ? TAN_PERSPECTIVE : !strcmp(argv[1], "tan-begin3d") ? TAN_BEGIN3D :
         !strcmp(argv[1], "asinf") ? ASINF : -1;
  if (mode < 0) return 2;
  int threads = atoi(argv[2]);
  if (argc > 3) stride = strtoull(argv[3], 0, 10);
  if (threads < 1 || threads > 64 || stride < 1) return 2;
  if (fegetround() != FE_TONEAREST) return 3;
  volatile float pi = 3.14159265358979323846f, degrees = 180.0f;
  deg2rad = pi / degrees;
  for (int i = 0; i < BUCKETS; i++) totals.bucket_first[i] = UINT32_MAX;
  pthread_t pool[64];
  for (int i = 0; i < threads; i++) pthread_create(&pool[i], 0, work, 0);
  for (int i = 0; i < threads; i++) pthread_join(pool[i], 0);
  printf("{\"mode\":\"%s\",\"stride\":%llu,\"deg2rad\":\"%08x\",\"evaluated\":%llu,\"skipped\":%llu,"
         "\"native_mismatches\":%llu,\"source_mismatches\":%llu,\"ambiguous\":%llu",
         argv[1], (unsigned long long)stride, f2u(deg2rad), (unsigned long long)totals.evaluated,
         (unsigned long long)totals.skipped, (unsigned long long)totals.native_mismatch,
         (unsigned long long)totals.source_mismatch, (unsigned long long)totals.ambiguous);
  printf(",\"buckets\":{");
  int first = 1;
  for (int i = 0; i < BUCKETS; i++) {
    if (!totals.bucket_evaluated[i]) continue;
    printf("%s\"%d\":[%llu,%llu", first ? "" : ",", i, (unsigned long long)totals.bucket_evaluated[i],
           (unsigned long long)totals.bucket_mismatch[i]);
    if (totals.bucket_mismatch[i]) printf(",\"%08x\"", totals.bucket_first[i]);
    printf("]");
    first = 0;
  }
  printf("}");
  list("ambiguous_words", ambiguous_words, ambiguous_count);
  list("source_mismatch_words", source_words, source_count);
  printf("}\n");
  return 0;
}
