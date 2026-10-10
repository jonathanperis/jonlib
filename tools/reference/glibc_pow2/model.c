/* Explicit-operation model of glibc 2.39's x86_64 powf (2.0f, y) and exp2f (y)
   for a finite y with |y| < 126 (a normal result): Arm optimized-routines'
   exp2_inline / exp2f core (math/powf.c, math/exp2f.c, exp2f_data.c;
   Copyright (c) 2017-2024 Arm Limited, MIT alternative, see
   LICENSES/arm-math.txt) with EXP2F_TABLE_BITS 5 and TOINT_INTRINSICS 0.
   log2_inline (2.0f) is exactly 1, so powf's y*log2(x) is y. FUSED=1 is the
   __powf_fma/__exp2f_fma ifunc variant (-mfma -mavx2): the three a*b + c of
   the polynomial are one fma each; FUSED=0 is the SSE2 default. Compile with
   -ffp-contract=off. */
#include <math.h>
#include <stdint.h>
#include <string.h>
#if FUSED
#define MADD(a, b, c) fma ((a), (b), (c))
#else
#define MADD(a, b, c) ((a) * (b) + (c))
#endif
/* 2^(i/32) as raw words minus i << 47. */
static const uint64_t T[32] = {
  0x3ff0000000000000ULL, 0x3fefd9b0d3158574ULL, 0x3fefb5586cf9890fULL, 0x3fef9301d0125b51ULL,
  0x3fef72b83c7d517bULL, 0x3fef54873168b9aaULL, 0x3fef387a6e756238ULL, 0x3fef1e9df51fdee1ULL,
  0x3fef06fe0a31b715ULL, 0x3feef1a7373aa9cbULL, 0x3feedea64c123422ULL, 0x3feece086061892dULL,
  0x3feebfdad5362a27ULL, 0x3feeb42b569d4f82ULL, 0x3feeab07dd485429ULL, 0x3feea47eb03a5585ULL,
  0x3feea09e667f3bcdULL, 0x3fee9f75e8ec5f74ULL, 0x3feea11473eb0187ULL, 0x3feea589994cce13ULL,
  0x3feeace5422aa0dbULL, 0x3feeb737b0cdc5e5ULL, 0x3feec49182a3f090ULL, 0x3feed503b23e255dULL,
  0x3feee89f995ad3adULL, 0x3feeff76f2fb5e47ULL, 0x3fef199bdd85529cULL, 0x3fef3720dcef9069ULL,
  0x3fef5818dcfba487ULL, 0x3fef7c97337b9b5fULL, 0x3fefa4afa2a490daULL, 0x3fefd0765b6e4540ULL};
static const double C0 = 0x1.c6af84b912394p-5, C1 = 0x1.ebfce50fac4f3p-3, C2 = 0x1.62e42ff0c52d6p-1;
/* 0x1.8p52 / 32. */
static const double SHIFT = 0x1.8p47;
float MODEL_POW2 (float y)
{
  double xd = y, kd = xd + SHIFT, r, s, z, r2, q;
  uint64_t ki, t;
  memcpy (&ki, &kd, 8);
  kd -= SHIFT;
  r = xd - kd;
  t = T[ki % 32] + (ki << 47);
  memcpy (&s, &t, 8);
  z = MADD (C0, r, C1);
  r2 = r * r;
  q = MADD (C2, r, 1.0);
  q = MADD (z, r2, q);
  return (float) (q * s);
}
