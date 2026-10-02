/* Jonlib tooling-only shims for the pinned MIT atan2f source; no fast math. */
#ifndef JONLIB_MODERN_ATAN2F_SHIM_H
#define JONLIB_MODERN_ATAN2F_SHIM_H
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <float.h>
#include <limits.h>
#ifdef __FAST_MATH__
#error Fast math invalidates the pinned-source reference
#endif
#pragma STDC FENV_ACCESS ON
#pragma STDC FP_CONTRACT OFF
_Static_assert(CHAR_BIT == 8 && sizeof(float) == 4 && sizeof(double) == 8,
               "binary32/binary64 storage is required");
_Static_assert(FLT_RADIX == 2 && FLT_MANT_DIG == 24 && DBL_MANT_DIG == 53 &&
               FLT_MIN_EXP == -125 && FLT_MAX_EXP == 128 &&
               DBL_MIN_EXP == -1021 && DBL_MAX_EXP == 1024 && FLT_EVAL_METHOD == 0,
               "IEEE formats without excess precision are required");
static inline uint32_t asuint(float f) { uint32_t u; memcpy(&u,&f,4); return u; }
static inline uint64_t asuint64(double f) { uint64_t u; memcpy(&u,&f,8); return u; }
static inline double asdouble(uint64_t u) { double f; memcpy(&f,&u,8); return f; }
static inline float ma_asfloat(uint32_t u) { float f; memcpy(&f,&u,4); return f; }
#ifndef __glibc_likely
#define __glibc_likely(x) (x)
#endif
#ifndef __glibc_unlikely
#define __glibc_unlikely(x) (x)
#endif
/* A volatile runtime function pointer prevents multiply-add substitution and
 * distinguishes explicit source FMA from disallowed expression contraction. */
static double (*volatile ma_runtime_fma)(double,double,double) = fma;
static inline double ma_fma(double a,double b,double c) {
  return ma_runtime_fma(a,b,c);
}
#define fma ma_fma
#endif
