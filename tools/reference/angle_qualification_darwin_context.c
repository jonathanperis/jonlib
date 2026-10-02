/* Jonlib read-only Darwin native-angle process metadata, independently linked.
 * Numeric code and compiler flags are unchanged. No floating-point state is set. */
#define _DARWIN_C_SOURCE
#include <dlfcn.h>
#include <fenv.h>
#include <float.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "runtime_image.h"
#if !defined(__APPLE__) || !defined(__MACH__)
#error This translation unit requires the Darwin Mach-O runtime profile
#endif
_Static_assert(CHAR_BIT == 8 && sizeof(float) == 4 && sizeof(double) == 8,
               "IEEE storage required");
_Static_assert(FLT_RADIX == 2 && FLT_MANT_DIG == 24 && DBL_MANT_DIG == 53 &&
               FLT_MIN_EXP == -125 && FLT_MAX_EXP == 128 &&
               DBL_MIN_EXP == -1021 && DBL_MAX_EXP == 1024 && FLT_EVAL_METHOD == 0,
               "IEEE binary32/64 without excess evaluation required");
#ifdef __FAST_MATH__
#error Fast math is unsupported
#endif
static float (*volatile aq_native)(float, float) = atan2f;
static void aq_metadata(const char *phase) {
  uint64_t control=0; unsigned short x87=0; const char *arch;
#if defined(__x86_64__)
  unsigned mxcsr; __asm__ volatile("stmxcsr %0":"=m"(mxcsr));
  __asm__ volatile("fnstcw %0":"=m"(x87)); control=mxcsr; arch="x86_64";
#elif defined(__aarch64__)
  __asm__ volatile("mrs %0, fpcr":"=r"(control)); arch="aarch64";
#else
#error Unsupported architecture metadata profile
#endif
  int round=fegetround(); void *symbol=dlsym(RTLD_DEFAULT,"atan2f");
  if (!symbol || symbol!=(void *)aq_native) _Exit(91);
  uint32_t one=0; uint64_t done=0; float f=1.0f; double d=1.0;
  memcpy(&one,&f,4); memcpy(&done,&d,8); uint16_t endian=1;
  fprintf(stderr,"{\"kind\":\"%s-context\",\"profile\":\"darwin-macho-runtime-image-v1\",\"architecture\":\"%s\",\"endian\":\"%s\",\"binary32\":%s,\"binary64\":%s,\"eval_method\":%d,\"rounding\":%d,\"nearest\":%s,\"control\":%llu,\"x87_control\":%u,\"symbol\":\"atan2f\",\"symbol_path\":\"volatile-pointer-equals-dlsym-default\",\"runtime_image\":",
      phase,arch,*(unsigned char *)&endian?"little":"big",one==0x3f800000u?"true":"false",done==UINT64_C(0x3ff0000000000000)?"true":"false",FLT_EVAL_METHOD,round,round==FE_TONEAREST?"true":"false",(unsigned long long)control,x87);
  if (!jon_runtime_image_write_json(stderr,symbol)) _Exit(92);
  fputs(",\"loader_overrides\":",stderr);
  if (!jon_runtime_loader_write_json(stderr)) _Exit(93);
  fputs("}\n",stderr); fflush(stderr);
}
__attribute__((constructor)) static void aq_initial(void) { aq_metadata("initial"); }
__attribute__((destructor)) static void aq_final(void) { aq_metadata("final"); }
