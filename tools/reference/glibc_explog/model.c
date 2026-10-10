/* Explicit-operation models of glibc 2.39's x86_64 expf and logf: Arm
   optimized-routines' math/expf.c (exp2f_data.c) and math/logf.c
   (logf_data.c) at 47597821aaa52e9c055caf1ecf8f3aecfd751cd9 (Copyright (c)
   2017-2024 Arm Limited, MIT alternative, see LICENSES/arm-math.txt), with
   EXP2F_0x3ff0000000000000ULL, 0x3fefd9b0d3158574ULL, 0x3fefb5586cf9890fULL, 0x3fef9301d0125b51ULL,
  0x3fef72b83c7d517bULL, 0x3fef54873168b9aaULL, 0x3fef387a6e756238ULL, 0x3fef1e9df51fdee1ULL,
  0x3fef06fe0a31b715ULL, 0x3feef1a7373aa9cbULL, 0x3feedea64c123422ULL, 0x3feece086061892dULL,
  0x3feebfdad5362a27ULL, 0x3feeb42b569d4f82ULL, 0x3feeab07dd485429ULL, 0x3feea47eb03a5585ULL,
  0x3feea09e667f3bcdULL, 0x3fee9f75e8ec5f74ULL, 0x3feea11473eb0187ULL, 0x3feea589994cce13ULL,
  0x3feeace5422aa0dbULL, 0x3feeb737b0cdc5e5ULL, 0x3feec49182a3f090ULL, 0x3feed503b23e255dULL,
  0x3feee89f995ad3adULL, 0x3feeff76f2fb5e47ULL, 0x3fef199bdd85529cULL, 0x3fef3720dcef9069ULL,
  0x3fef5818dcfba487ULL, 0x3fef7c97337b9b5fULL, 0x3fefa4afa2a490daULL, 0x3fefd0765b6e4540ULL_BITS 5, LOGF_0x3ff0000000000000ULL, 0x3fefd9b0d3158574ULL, 0x3fefb5586cf9890fULL, 0x3fef9301d0125b51ULL,
  0x3fef72b83c7d517bULL, 0x3fef54873168b9aaULL, 0x3fef387a6e756238ULL, 0x3fef1e9df51fdee1ULL,
  0x3fef06fe0a31b715ULL, 0x3feef1a7373aa9cbULL, 0x3feedea64c123422ULL, 0x3feece086061892dULL,
  0x3feebfdad5362a27ULL, 0x3feeb42b569d4f82ULL, 0x3feeab07dd485429ULL, 0x3feea47eb03a5585ULL,
  0x3feea09e667f3bcdULL, 0x3fee9f75e8ec5f74ULL, 0x3feea11473eb0187ULL, 0x3feea589994cce13ULL,
  0x3feeace5422aa0dbULL, 0x3feeb737b0cdc5e5ULL, 0x3feec49182a3f090ULL, 0x3feed503b23e255dULL,
  0x3feee89f995ad3adULL, 0x3feeff76f2fb5e47ULL, 0x3fef199bdd85529cULL, 0x3fef3720dcef9069ULL,
  0x3fef5818dcfba487ULL, 0x3fef7c97337b9b5fULL, 0x3fefa4afa2a490daULL, 0x3fefd0765b6e4540ULL_BITS 4 and TOINT_INTRINSICS 0.
   MODEL_EXPF: a finite x with |x| < 87 (a normal result, no special case).
   MODEL_LOGF: a positive normal x.
   FUSED=1 is the __expf_fma/__logf_fma ifunc variant (-mfma -mavx2): every
   a*b + c of the source is one fma, and in expf GCC also contracts
   r = z - kd over z = InvLn2N*xd into fma (InvLn2N, xd, -kd), which is what
   changes a result (at two arguments, see exhaustive.c); FUSED=0 is the
   SSE2 default. Compile with -ffp-contract=off. */
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
static const double INVLN2N = 0x1.71547652b82fep+0 * 32, SHIFT = 0x1.8p+52;
static const double C0 = 0x1.c6af84b912394p-5 / 32 / 32 / 32, C1 = 0x1.ebfce50fac4f3p-3 / 32 / 32, C2 = 0x1.62e42ff0c52d6p-1 / 32;
float MODEL_EXPF (float x)
{
  double xd = x, z = INVLN2N * xd, kd = z + SHIFT, r, s, r2, y;
  uint64_t ki, t;
  memcpy (&ki, &kd, 8);
  kd -= SHIFT;
#if FUSED
  r = fma (INVLN2N, xd, -kd);
#else
  r = z - kd;
#endif
  t = T[ki % 32] + (ki << 47);
  memcpy (&s, &t, 8);
  z = MADD (C0, r, C1);
  r2 = r * r;
  y = MADD (C2, r, 1.0);
  y = MADD (z, r2, y);
  return (float) (y * s);
}
static const double INVC[16] = {0x1.661ec79f8f3bep+0, 0x1.571ed4aaf883dp+0, 0x1.49539f0f010bp+0, 0x1.3c995b0b80385p+0, 0x1.30d190c8864a5p+0, 0x1.25e227b0b8eap+0, 0x1.1bb4a4a1a343fp+0, 0x1.12358f08ae5bap+0, 0x1.0953f419900a7p+0, 0x1p+0, 0x1.e608cfd9a47acp-1, 0x1.ca4b31f026aap-1, 0x1.b2036576afce6p-1, 0x1.9c2d163a1aa2dp-1, 0x1.886e6037841edp-1, 0x1.767dcf5534862p-1};
static const double LOGC[16] = {-0x1.57bf7808caadep-2, -0x1.2bef0a7c06ddbp-2, -0x1.01eae7f513a67p-2, -0x1.b31d8a68224e9p-3, -0x1.6574f0ac07758p-3, -0x1.1aa2bc79c81p-3, -0x1.a4e76ce8c0e5ep-4, -0x1.1973c5a611cccp-4, -0x1.252f438e10c1ep-5, 0x0p+0, 0x1.aa5aa5df25984p-5, 0x1.c5e53aa362eb4p-4, 0x1.526e57720db08p-3, 0x1.bc2860d22477p-3, 0x1.1058bc8a07ee1p-2, 0x1.4043057b6ee09p-2};
static const double LN2 = 0x1.62e42fefa39efp-1;
static const double A0 = -0x1.00ea348b88334p-2, A1 = 0x1.5575b0be00b6ap-2, A2 = -0x1.ffffef20a4123p-2;
float MODEL_LOGF (float x)
{
  uint32_t ix, iz, tmp;
  int k, i;
  float zf;
  double z, r, r2, y, y0;
  memcpy (&ix, &x, 4);
  if (ix == 0x3f800000)
    return 0;
  tmp = ix - 0x3f330000;
  i = (tmp >> 19) % 16;
  k = (int32_t) tmp >> 23;
  iz = ix - (tmp & 0xff800000);
  memcpy (&zf, &iz, 4);
  z = zf;
  r = MADD (z, INVC[i], -1.0);
  y0 = MADD ((double) k, LN2, LOGC[i]);
  r2 = r * r;
  y = MADD (A1, r, A2);
  y = MADD (A0, r2, y);
  y = MADD (y, r2, y0 + r);
  return (float) y;
}
