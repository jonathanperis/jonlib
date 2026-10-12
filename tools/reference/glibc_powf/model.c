/* Explicit-operation model of glibc 2.39's x86_64 powf (x, y): Arm
   optimized-routines' math/powf.c with powf_log2_data.c and exp2f_data.c
   (Copyright (c) 2017-2024 Arm Limited, MIT alternative, see
   LICENSES/arm-math.txt), as glibc builds it (POWF_LOG2_TABLE_BITS 4,
   EXP2F_TABLE_BITS 5, TOINT_INTRINSICS 0, POWF_SCALE 1, WANT_ROUNDING and
   WANT_ERRNO_UFLOW 1). FUSED=1 is the __powf_fma ifunc variant (-mfma
   -mavx2): each a*b + c of the two polynomials is one fma, and so is
   z*invc - 1; y*log2(x), the add of the shift and the remainder are not
   fused (read from the host library's code). FUSED=0 is the SSE2 default.
   The tables and the polynomials are the words of the host's libm.so.6.
   The rounding mode is to nearest and no flag or errno is modelled: an
   overflow is an infinity, an underflow a zero or the smallest subnormal.
   Compile with -ffp-contract=off. */
#include <math.h>
#include <stdint.h>
#include <string.h>
#if FUSED
#define MADD(a, b, c) fma ((a), (b), (c))
#else
#define MADD(a, b, c) ((a) * (b) + (c))
#endif
/* invc and logc of the sixteen intervals. */
static const uint64_t L[32] = {
  0x3ff661ec79f8f3beULL, 0xbfdefec65b963019ULL, 0x3ff571ed4aaf883dULL, 0xbfdb0b6832d4fca4ULL,
  0x3ff49539f0f010b0ULL, 0xbfd7418b0a1fb77bULL, 0x3ff3c995b0b80385ULL, 0xbfd39de91a6dcf7bULL,
  0x3ff30d190c8864a5ULL, 0xbfd01d9bf3f2b631ULL, 0x3ff25e227b0b8ea0ULL, 0xbfc97c1d1b3b7af0ULL,
  0x3ff1bb4a4a1a343fULL, 0xbfc2f9e393af3c9fULL, 0x3ff12358f08ae5baULL, 0xbfb960cbbf788d5cULL,
  0x3ff0953f419900a7ULL, 0xbfaa6f9db6475fceULL, 0x3ff0000000000000ULL, 0x0000000000000000ULL,
  0x3fee608cfd9a47acULL, 0x3fb338ca9f24f53dULL, 0x3feca4b31f026aa0ULL, 0x3fc476a9543891baULL,
  0x3feb2036576afce6ULL, 0x3fce840b4ac4e4d2ULL, 0x3fe9c2d163a1aa2dULL, 0x3fd40645f0c6651cULL,
  0x3fe886e6037841edULL, 0x3fd88e9c2c1b9ff8ULL, 0x3fe767dcf5534862ULL, 0x3fdce0a44eb17bccULL};
static const uint64_t A[5] = {0x3fd27616c9496e0bULL, 0xbfd71969a075c67aULL, 0x3fdec70a6ca7baddULL, 0xbfe7154748bef6c8ULL, 0x3ff71547652ab82bULL};
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
static double word (uint64_t w) { double d; memcpy (&d, &w, 8); return d; }
static uint32_t asuint (float f) { uint32_t u; memcpy (&u, &f, 4); return u; }
static float asfloat (uint32_t u) { float f; memcpy (&f, &u, 4); return f; }
/* 0: y is not an integer; 1: an odd one; 2: an even one. */
static int checkint (uint32_t iy)
{
  int e = iy >> 23 & 0xff;
  if (e < 0x7f) return 0;
  if (e > 0x7f + 23) return 2;
  if (iy & ((1 << (0x7f + 23 - e)) - 1)) return 0;
  if (iy & (1 << (0x7f + 23 - e))) return 1;
  return 2;
}
static int zeroinfnan (uint32_t ix) { return 2 * ix - 1 >= 2u * 0x7f800000 - 1; }
static double log2_inline (uint32_t ix)
{
  uint32_t tmp = ix - 0x3f330000, top = tmp & 0xff800000, iz = ix - top;
  int i = (tmp >> 19) % 16, k = (int32_t) top >> 23;
  double invc = word (L[2 * i]), logc = word (L[2 * i + 1]), z = (double) asfloat (iz);
  double r = MADD (z, invc, -1.0), y0 = logc + (double) k, r2 = r * r;
  double y = MADD (word (A[0]), r, word (A[1])), p = MADD (word (A[2]), r, word (A[3])), r4 = r2 * r2;
  double q = MADD (word (A[4]), r, y0);
  q = MADD (p, r2, q);
  return MADD (y, r4, q);
}
static float exp2_inline (double xd, uint32_t sign_bias)
{
  double kd = xd + SHIFT, r, s, z, r2, y;
  uint64_t ki, t;
  memcpy (&ki, &kd, 8);
  kd -= SHIFT;
  r = xd - kd;
  t = T[ki % 32] + ((ki + sign_bias) << 47);
  memcpy (&s, &t, 8);
  z = MADD (C0, r, C1);
  r2 = r * r;
  y = MADD (C2, r, 1.0);
  y = MADD (z, r2, y);
  return (float) (y * s);
}
float MODEL_POWF (float x, float y)
{
  uint32_t sign_bias = 0, ix = asuint (x), iy = asuint (y);
  double logx, ylogx;
  uint64_t bits;
  if (ix - 0x00800000 >= 0x7f800000 - 0x00800000 || zeroinfnan (iy))
    {
      if (zeroinfnan (iy))
        {
          if (2 * iy == 0) return 1.0f;                       /* a signaling NaN x is not modelled */
          if (ix == 0x3f800000) return 1.0f;
          if (2 * ix > 2u * 0x7f800000 || 2 * iy > 2u * 0x7f800000) return x + y;
          if (2 * ix == 2 * 0x3f800000) return 1.0f;
          if ((2 * ix < 2 * 0x3f800000) == !(iy & 0x80000000)) return 0.0f;
          return y * y;
        }
      if (zeroinfnan (ix))
        {
          float x2 = x * x;
          if (ix & 0x80000000 && checkint (iy) == 1) x2 = -x2;
          return iy & 0x80000000 ? 1 / x2 : x2;
        }
      if (ix & 0x80000000)
        {
          int yint = checkint (iy);
          if (yint == 0) return (x - x) / (x - x);
          if (yint == 1) sign_bias = 0x10000;                  /* SIGN_BIAS: 1 << (EXP2F_TABLE_BITS + 11) */
          ix &= 0x7fffffff;
        }
      if (ix < 0x00800000)
        {
          ix = asuint (asfloat (ix) * 0x1p23f);
          ix &= 0x7fffffff;
          ix -= 23 << 23;
        }
    }
  logx = log2_inline (ix);
  ylogx = y * logx;
  memcpy (&bits, &ylogx, 8);
  if ((bits >> 47 & 0xffff) >= 0x80bf)
    {
      if (ylogx > 0x1.fffffffd1d571p+6) return sign_bias ? -INFINITY : INFINITY;
      /* WANT_ROUNDING's check of the directed modes does nothing to nearest. */
      if (ylogx <= -150.0) return sign_bias ? -0.0f : 0.0f;
      if (ylogx < -149.0) return sign_bias ? -0x1p-149f : 0x1p-149f;
    }
  return exp2_inline (ylogx, sign_bias);
}
