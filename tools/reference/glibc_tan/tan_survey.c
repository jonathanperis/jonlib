/* Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
 *
 * Exhaustive comparison of glibc 2.39's binary64 tan models over the argument
 * sets raylib passes (see tools/reference/libm_survey.c):
 *
 *   perspective  x = (double)g * 0.5 for every finite binary32 g
 *                (MatrixPerspective's tan(fovY*0.5) with a binary32 fovY);
 *   begin3d      x = ((double)f * 0.5) * (double)DEG2RAD for every finite
 *                binary32 f (BeginMode3D's tan(camera.fovy*0.5*DEG2RAD)).
 *
 * Functions (each called through a volatile function pointer):
 *   native       the host tan;
 *   model_fma    tools/reference/glibc_tan/model.c with FUSED=1 (the
 *                __tan_fma ifunc variant), contraction off;
 *   model_sse2   the same with FUSED=0 (__tan_sse2/__tan_avx);
 *   pinned_fma   (HAVE_PINNED, x86_64 GCC only) the unmodified pinned
 *                s_tan.c built like glibc's s_tan-fma.c (-mfma -mavx2);
 *   pinned_sse2  (HAVE_PINNED) the same built like s_tan.c (no FMA);
 *   cr_tan       CORE-MATH's correctly rounded tan (tools/reference/core_math).
 *
 * Every pair below is counted on every evaluated input; the first differing
 * input words are listed. For the Bend kernel's verification the program also
 * keeps, per binary64 exponent of x, the HARD smallest-magnitude input words
 * where model_fma differs from model_sse2 (inputs that observe the FMA
 * contraction) and where model_fma differs from cr_tan (misrounded inputs).
 * "eval SET WORD..." prints the argument and every function's result word.
 * A stride argument evaluates every stride-th input word only.
 */
#include <fenv.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

double cr_tan (double);
double model_tan_fma (double);
double model_tan_sse2 (double);
#if HAVE_PINNED
double pinned_tan_fma (double);
double pinned_tan_sse2 (double);
#endif

static double (*volatile native_fn) (double) = tan;
static double (*volatile fma_fn) (double) = model_tan_fma;
static double (*volatile sse2_fn) (double) = model_tan_sse2;
static double (*volatile cr_fn) (double) = cr_tan;
#if HAVE_PINNED
static double (*volatile pinned_fma_fn) (double) = pinned_tan_fma;
static double (*volatile pinned_sse2_fn) (double) = pinned_tan_sse2;
#endif

static uint64_t d2u (double x) { uint64_t u; memcpy (&u, &x, 8); return u; }
static uint32_t f2u (float x) { uint32_t u; memcpy (&u, &x, 4); return u; }
static float u2f (uint32_t u) { float x; memcpy (&x, &u, 4); return x; }

enum { PERSPECTIVE, BEGIN3D };
enum { NATIVE_FMA, NATIVE_SSE2, FMA_SSE2, FMA_CR, PINNED_FMA_MODEL, PINNED_SSE2_MODEL, NATIVE_PINNED_FMA, PAIRS };
static const char *pair_names[PAIRS] = { "native_vs_model_fma", "native_vs_model_sse2", "model_fma_vs_model_sse2",
                                         "model_fma_vs_correctly_rounded", "pinned_fma_vs_model_fma",
                                         "pinned_sse2_vs_model_sse2", "native_vs_pinned_fma" };
static int set;
static uint64_t stride = 1;
static float deg2rad;

#define CHUNK (1u << 20)
#define BUCKETS 2048
#define FIRST 16
#define HARD 8
static atomic_uint_fast64_t next_chunk;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

typedef struct {
  uint64_t evaluated, skipped, pairs[PAIRS];
  uint32_t first[PAIRS][FIRST]; int first_count[PAIRS];
  uint32_t contraction[BUCKETS][HARD]; int contraction_count[BUCKETS];
  uint32_t misrounded[BUCKETS][HARD]; int misrounded_count[BUCKETS];
} Totals;
static Totals totals;

static double argument (uint32_t u) {
  volatile double half = (double) u2f (u) * 0.5;
  if (set == PERSPECTIVE) return half;
  volatile double d = deg2rad;
  return half * d;
}

/* Keep the HARD smallest magnitudes (then words) in ascending order. */
static void keep (uint32_t *list, int *count, int limit, uint32_t u) {
  uint64_t key = ((uint64_t) (u & 0x7fffffffu) << 1) | (u >> 31);
  int i = *count;
  if (i == limit) {
    uint32_t last = list[limit - 1];
    if (key >= (((uint64_t) (last & 0x7fffffffu) << 1) | (last >> 31))) return;
    i = limit - 1;
  } else (*count)++;
  while (i > 0 && key < (((uint64_t) (list[i - 1] & 0x7fffffffu) << 1) | (list[i - 1] >> 31))) {
    list[i] = list[i - 1];
    i--;
  }
  list[i] = u;
}

static void *work (void *unused) {
  (void) unused;
  Totals *t = calloc (1, sizeof *t);
  for (;;) {
    uint64_t c = atomic_fetch_add (&next_chunk, 1);
    if (c >= (1ull << 32) / CHUNK) break;
    for (uint64_t k = 0; k < CHUNK; k++) {
      uint32_t u = (uint32_t) (c * CHUNK + k);
      if (stride > 1 && u % stride) continue;
      if (!isfinite (u2f (u))) { t->skipped++; continue; }
      double x = argument (u);
      int bucket = (int) ((d2u (x) >> 52) & 2047);
      uint64_t native = d2u (native_fn (x)), fused = d2u (fma_fn (x)), plain = d2u (sse2_fn (x)), cr = d2u (cr_fn (x));
      int differs[PAIRS] = { native != fused, native != plain, fused != plain, fused != cr, 0, 0, 0 };
#if HAVE_PINNED
      uint64_t pinned_fused = d2u (pinned_fma_fn (x)), pinned_plain = d2u (pinned_sse2_fn (x));
      differs[PINNED_FMA_MODEL] = pinned_fused != fused;
      differs[PINNED_SSE2_MODEL] = pinned_plain != plain;
      differs[NATIVE_PINNED_FMA] = native != pinned_fused;
#endif
      t->evaluated++;
      for (int p = 0; p < PAIRS; p++)
        if (differs[p]) {
          t->pairs[p]++;
          keep (t->first[p], &t->first_count[p], FIRST, u);
        }
      if (differs[FMA_SSE2]) keep (t->contraction[bucket], &t->contraction_count[bucket], HARD, u);
      if (differs[FMA_CR]) keep (t->misrounded[bucket], &t->misrounded_count[bucket], HARD, u);
    }
  }
  pthread_mutex_lock (&lock);
  totals.evaluated += t->evaluated;
  totals.skipped += t->skipped;
  for (int p = 0; p < PAIRS; p++) {
    totals.pairs[p] += t->pairs[p];
    for (int i = 0; i < t->first_count[p]; i++) keep (totals.first[p], &totals.first_count[p], FIRST, t->first[p][i]);
  }
  for (int b = 0; b < BUCKETS; b++) {
    for (int i = 0; i < t->contraction_count[b]; i++) keep (totals.contraction[b], &totals.contraction_count[b], HARD, t->contraction[b][i]);
    for (int i = 0; i < t->misrounded_count[b]; i++) keep (totals.misrounded[b], &totals.misrounded_count[b], HARD, t->misrounded[b][i]);
  }
  pthread_mutex_unlock (&lock);
  free (t);
  return 0;
}

static void words (const char *name, uint32_t list[BUCKETS][HARD], int *count) {
  printf (",\"%s\":[", name);
  int first = 1;
  for (int b = 0; b < BUCKETS; b++)
    for (int i = 0; i < count[b]; i++) {
      printf ("%s\"%08x\"", first ? "" : ",", list[b][i]);
      first = 0;
    }
  printf ("]");
}

static int parse_set (const char *name) {
  return !strcmp (name, "perspective") ? PERSPECTIVE : !strcmp (name, "begin3d") ? BEGIN3D : -1;
}

int main (int argc, char **argv) {
  volatile float pi = 3.14159265358979323846f, degrees = 180.0f;
  deg2rad = pi / degrees;
  if (fegetround () != FE_TONEAREST) return 3;
  if (argc >= 3 && !strcmp (argv[1], "eval")) {
    if ((set = parse_set (argv[2])) < 0) return 2;
    for (int i = 3; i < argc; i++) {
      uint32_t u = (uint32_t) strtoul (argv[i], 0, 16);
      double x = argument (u);
      printf ("%08x %016llx %016llx %016llx %016llx %016llx\n", u, (unsigned long long) d2u (x),
              (unsigned long long) d2u (native_fn (x)), (unsigned long long) d2u (fma_fn (x)),
              (unsigned long long) d2u (sse2_fn (x)), (unsigned long long) d2u (cr_fn (x)));
    }
    return 0;
  }
  if (argc < 3 || (set = parse_set (argv[1])) < 0) {
    fprintf (stderr, "usage: tan_survey perspective|begin3d threads [stride] | eval SET WORD...\n");
    return 2;
  }
  int threads = atoi (argv[2]);
  if (argc > 3) stride = strtoull (argv[3], 0, 10);
  if (threads < 1 || threads > 64 || stride < 1) return 2;
  pthread_t pool[64];
  for (int i = 0; i < threads; i++) pthread_create (&pool[i], 0, work, 0);
  for (int i = 0; i < threads; i++) pthread_join (pool[i], 0);
  printf ("{\"set\":\"%s\",\"stride\":%llu,\"deg2rad\":\"%08x\",\"pinned\":%s,\"evaluated\":%llu,\"skipped\":%llu,\"pairs\":{",
          argv[1], (unsigned long long) stride, f2u (deg2rad), HAVE_PINNED ? "true" : "false",
          (unsigned long long) totals.evaluated, (unsigned long long) totals.skipped);
  for (int p = 0; p < PAIRS; p++) {
    if (!HAVE_PINNED && p >= PINNED_FMA_MODEL) continue;
    printf ("%s\"%s\":{\"differences\":%llu,\"first\":[", p ? "," : "", pair_names[p], (unsigned long long) totals.pairs[p]);
    for (int i = 0; i < totals.first_count[p]; i++) printf ("%s\"%08x\"", i ? "," : "", totals.first[p][i]);
    printf ("]}");
  }
  printf ("}");
  words ("contraction_words", totals.contraction, totals.contraction_count);
  words ("misrounded_words", totals.misrounded, totals.misrounded_count);
  printf ("}\n");
  return 0;
}
