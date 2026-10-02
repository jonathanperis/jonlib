/* Jonlib native-only qualification/trace driver. Independent controls are fixed
 * IEEE words. The pinned scalar source, native pointer and Sun comparator remain
 * distinct call paths. This file is not a production angle implementation. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <fenv.h>
#include <dlfcn.h>
#ifdef __APPLE__
#include "runtime_image.h"
#endif
#include "modern_atan2f_shim.h"
#include "modern_atan2f_trace.h"
#ifdef __GLIBC__
#include <gnu/libc-version.h>
#endif
#if defined(__x86_64__) || defined(__i386__)
#include <xmmintrin.h>
#elif !defined(__aarch64__)
#error Floating point control register qualification is unavailable
#endif
#include "modern_atan2f_sun.h"
struct ma_trace_state ma_trace;
float modern_atan2f_adapted(float,float);
float modern_atan2f_original(float,float);
static float (*volatile native_atan2)(float,float) = atan2f;
static float (*volatile original_atan2)(float,float) = modern_atan2f_original;
static float (*volatile adapted_atan2)(float,float) = modern_atan2f_adapted;
static float (*volatile sun_atan2)(float,float) = gnu_atan2;

static uint64_t control_word(void) {
#if defined(__x86_64__) || defined(__i386__)
  return _mm_getcsr();
#else
  uint64_t value; __asm__ volatile("mrs %0, fpcr" : "=r"(value)); return value;
#endif
}
static int context_ok(void) {
  if (fegetround()!=FE_TONEAREST) return 0;
  uint64_t c=control_word();
#if defined(__x86_64__) || defined(__i386__)
  return !(c & ((1u<<15)|(1u<<6)|(3u<<13)));
#else
  return !(c & ((1ull<<24)|(1ull<<19)|(3ull<<22)|3ull));
#endif
}
#ifdef __APPLE__
static unsigned short x87_control(void) {
#if defined(__x86_64__)
  unsigned short value; __asm__ volatile("fnstcw %0":"=m"(value)); return value;
#else
  return 0;
#endif
}
static int runtime_images(FILE *out) {
  if (dlsym(RTLD_DEFAULT,"atan2f")!=(void *)native_atan2 ||
      dlsym(RTLD_DEFAULT,"fma")!=(void *)ma_runtime_fma) return 0;
  fprintf(out,",\"x87_control\":%u,\"symbol_path\":\"volatile-pointers-equal-dlsym-default\",\"loader_overrides\":",x87_control());
  if (!jon_runtime_loader_write_json(out)) return 0;
  fputs(",\"runtime_images\":{\"atan2_library\":",out);
  if (!jon_runtime_image_write_json(out,(void *)native_atan2)) return 0;
  fputs(",\"fma_library\":",out);
  if (!jon_runtime_image_write_json(out,(void *)ma_runtime_fma)) return 0;
  fputc('}',out);
  return 1;
}
#endif
static int finish_context(void) {
  if (!context_ok()) return 12;
  fprintf(stderr,"{\"kind\":\"final-context\",\"rounding\":\"FE_TONEAREST\",\"rounding_code\":%d,\"control\":%" PRIu64 ",\"ftz\":false,\"daz\":false",fegetround(),control_word());
#ifdef __APPLE__
  if (!runtime_images(stderr)) return 13;
#endif
  fputs("}\n",stderr);
  return 0;
}
static int qualify(void) {
  if (!context_ok()) return 2;
  if (asuint(1.0f)!=UINT32_C(0x3f800000) || asuint(-0.0f)!=UINT32_C(0x80000000)
      || asuint64(1.0)!=UINT64_C(0x3ff0000000000000)
      || asuint64(-0.0)!=UINT64_C(0x8000000000000000)) return 3;
  static const uint64_t controls[][4] = {
    {0x3ff0000000000001,0x3feffffffffffffe,0xbff0000000000000,0xb970000000000000},
    {0x2ea0000000000001,0x2ea0000000000001,0x9d50000000000002,0x16d0000000000000},
    {0x3ff0000000000000,0x3ff0000000000000,0x3ca0000000000000,0x3ff0000000000000},
    {0x3ff0000000000001,0x3ff0000000000000,0x3ca0000000000000,0x3ff0000000000002},
    {0,0xbff0000000000000,0x8000000000000000,0x8000000000000000},
    {0,0xbff0000000000000,0,0},
    {0x3ff0000000000000,0x3ff0000000000000,0xbff0000000000000,0},
    {0x0010000000000000,0x3fe0000000000000,0,0x0008000000000000},
    {1,0x3ff0000000000000,0,1}
  };
  for (unsigned i=0;i<sizeof controls/sizeof controls[0];i++)
    if (asuint64(ma_runtime_fma(asdouble(controls[i][0]),asdouble(controls[i][1]),asdouble(controls[i][2])))!=controls[i][3]) return 4;
  static const uint64_t narrow[][2] = {
    {0x3ff0000010000000,0x3f800000}, {0x3ff0000030000000,0x3f800002},
    {0x3690000000000000,0}, {0x3690000000000001,1},
    {0xb690000000000000,0x80000000}, {0x36a0000000000000,1},
    {0x380fffffe0000000,0x00800000}
  };
  for (unsigned i=0;i<sizeof narrow/sizeof narrow[0];i++) {
    volatile double value=asdouble(narrow[i][0]);
    volatile float result=value;
    if (asuint(result)!=(uint32_t)narrow[i][1]) return 5;
  }
  volatile float fs=ma_asfloat(1),ft=ma_asfloat(0x00800000),half=0.5f,onef=1.0f;
  volatile double ds=asdouble(1),dt=asdouble(0x0010000000000000),one=1.0;
  if (asuint(fs*onef)!=1 || asuint(ft*half)!=0x00400000 ||
      asuint64(ds*one)!=1 || asuint64(dt*0.5)!=0x0008000000000000) return 6;
  Dl_info ai={0},fi={0};
  if (!dladdr((void *)native_atan2,&ai) || !dladdr((void *)ma_runtime_fma,&fi) || !ai.dli_fname || !fi.dli_fname) return 7;
  /* Separate literal and volatile-pointer diagnostic paths, never selectors. */
  volatile float y=1.0f,x=ma_asfloat(0x9e3ce508);
  printf("{\"kind\":\"qualification\",\"rounding\":\"FE_TONEAREST\",\"initial_rounding\":%d,\"control\":%" PRIu64 ",\"ftz\":false,\"daz\":false,\"binary32\":true,\"binary64\":true,\"excess_precision\":false,\"fma_controls\":9,\"narrow_controls\":7,\"gradual_controls\":4,\"atan2_library\":\"%s\",\"fma_library\":\"%s\",\"literal_atan2\":%u,\"pointer_atan2\":%u,\"original_atan2\":%u",
    fegetround(),control_word(),ai.dli_fname,fi.dli_fname,asuint(atan2f(1.0f,-1e-20f)),asuint(native_atan2(y,x)),asuint(original_atan2(y,x)));
#ifdef __GLIBC__
  printf(",\"libc\":\"glibc\",\"libc_version\":\"%s\"",gnu_get_libc_version());
#endif
#ifdef __APPLE__
  if (!runtime_images(stdout)) return 13;
#endif
  puts("}");
  return 0;
}
static void emit(unsigned id,uint32_t yw,uint32_t xw) {
  ma_trace=(struct ma_trace_state){.enabled=1};
  if ((yw&0x7fffffff)>=0x7f800000 || (xw&0x7fffffff)>=0x7f800000) {
    printf("{\"id\":%u,\"y\":%u,\"x\":%u,\"accepted\":false,\"pinned\":null,\"original\":null,\"native\":null,\"sun\":null,\"mask\":4096,\"index\":0,\"gt\":0,\"final\":null,\"events\":[]}\n",id,yw,xw);
    return;
  }
  float y=ma_asfloat(yw),x=ma_asfloat(xw);
  uint32_t pinned=asuint(adapted_atan2(y,x));
  if (ma_trace.overflow) { fputs("Trace capacity exceeded\n",stderr); exit(8); }
  uint32_t original=asuint(original_atan2(y,x));
  uint32_t native=asuint(native_atan2(y,x));
  uint32_t sun=asuint(sun_atan2(y,x));
  printf("{\"id\":%u,\"y\":%u,\"x\":%u,\"accepted\":true,\"pinned\":%u,\"original\":%u,\"native\":%u,\"sun\":%u,\"mask\":%u,\"index\":%u,\"gt\":%u,\"final\":[%u,%u],\"events\":[",id,yw,xw,pinned,original,native,sun,ma_trace.mask,ma_trace.index,ma_trace.gt,(uint32_t)(ma_trace.final>>32),(uint32_t)ma_trace.final);
  for(unsigned i=0;i<ma_trace.count;i++) {
    struct ma_event e=ma_trace.events[i];
    printf("%s[%u,%u,%u]",i?",":"",e.tag,(uint32_t)(e.bits>>32),(uint32_t)e.bits);
  }
  puts("]}");
}
static uint64_t random_word(uint64_t *state) {
  uint64_t x=*state; x^=x>>12; x^=x<<25; x^=x>>27; *state=x;
  return x*UINT64_C(2685821657736338717);
}
/* Independent input generator: binary32 angle midpoints, long-double tangent
 * and bounded continued-fraction convergents. Host tanl only proposes inputs;
 * every retained result still comes from the pinned scalar source. */
static void boundary_search(uint64_t count,uint64_t state) {
  unsigned found=0,up=0;
  for(uint64_t i=0;i<count;i++) {
    uint32_t angle=UINT32_C(0x3e800000)+(uint32_t)(random_word(&state)%UINT32_C(0x01000000));
    long double midpoint=((long double)ma_asfloat(angle)+(long double)ma_asfloat(angle+1))*0.5L;
    long double target=tanl(midpoint),r=target;
    uint64_t p0=0,p1=1,q0=1,q1=0;
    for(unsigned step=0;step<64;step++) {
      if(!(r>0) || r>UINT32_MAX)break;
      uint64_t a=(uint64_t)r;
      if(a && (p1>UINT64_C(0xffffff)/a || q1>UINT64_C(0xffffff)/a))break;
      uint64_t p=a*p1+p0,q=a*q1+q0;
      if(p>0xffffff || q>0xffffff)break;
      if(p && q) {
        uint32_t y=asuint((float)p),x=asuint((float)q);
        ma_trace=(struct ma_trace_state){0};
        (void)adapted_atan2(ma_asfloat(y),ma_asfloat(x));
        if(ma_trace.mask&128) {
          unsigned mask=ma_trace.mask;emit((unsigned)i,y,x);found++;
          if(mask&512)up++;
        }
      }
      long double remainder=r-(long double)a;
      if(remainder==0)break;
      r=1.0L/remainder;p0=p1;p1=p;q0=q1;q1=q;
    }
  }
  fprintf(stderr,"boundary_midpoints=%" PRIu64 " general_hits=%u correction_up_hits=%u final_state=%" PRIu64 "\n",count,found,up,state);
}
/* Bounded source-only search around the tiny raw-distance transition. */
static void tiny_search(uint64_t count,uint64_t state) {
  unsigned tiny=0,boundary=0,nonboundary=0;
  for(uint64_t i=0;i<count;i++) {
    uint32_t a=(uint32_t)random_word(&state),b=(uint32_t)random_word(&state);
    uint32_t xf=a&0x7fffff,yf=b&0x7fffff;
    if((i&7)==0)yf=xf;
    if((i&7)==1)yf=xf?xf-1:1;
    if((i&7)==2) { xf=0x7fffff; yf=0x7ffffe; }
    uint32_t gap=25+(uint32_t)((i>>3)%3);
    uint32_t x=0x3f800000|xf,y=(0x3f800000-(gap<<23))|yf;
    if((i&7)==3) { y=(b&0x7fffff)|1; x=0x7f000000|xf; }
    if((i&7)==4) { y=(b&0x7fffff)|1; x=(26u<<23)|xf; }
    if(((x-y)>>23)<25)continue;
    y|=a&0x80000000;
    ma_trace=(struct ma_trace_state){0};
    (void)adapted_atan2(ma_asfloat(y),ma_asfloat(x));
    if(ma_trace.mask&8) {
      tiny++; if(ma_trace.mask&16)boundary++;
      else { emit((unsigned)i,y,x);nonboundary++; }
    }
  }
  fprintf(stderr,"tiny_trials=%" PRIu64 " tiny_hits=%u boundary_hits=%u nonboundary_hits=%u final_state=%" PRIu64 "\n",count,tiny,boundary,nonboundary,state);
}
int main(int argc,char **argv) {
  int q=qualify(); if(q) { fprintf(stderr,"Native context qualification failed: %d\n",q); return q; }
  if(argc==2 && !strcmp(argv[1],"--qualify")) return finish_context();
  if(argc==4 && !strcmp(argv[1],"--search-tiny")) {
    uint64_t count=strtoull(argv[2],0,0),state=strtoull(argv[3],0,0);
    if(!state || !count || count>UINT64_C(200000000))return 9;
    tiny_search(count,state);
  } else if(argc==4 && !strcmp(argv[1],"--search-boundary")) {
    uint64_t count=strtoull(argv[2],0,0),state=strtoull(argv[3],0,0);
    if(!state || !count || count>UINT64_C(1000000))return 9;
    boundary_search(count,state);
  } else if(argc==4 && !strcmp(argv[1],"--search")) {
    uint64_t count=strtoull(argv[2],0,0),state=strtoull(argv[3],0,0);
    if(!state || !count || count>UINT64_C(200000000))return 9;
    unsigned found=0;
    for(uint64_t i=0;i<count;i++) {
      uint32_t a=(uint32_t)random_word(&state),b=(uint32_t)random_word(&state);
      uint32_t y=0x3f000000|(a&0xffffff)|(a&0x80000000);
      uint32_t x=0x3f000000|(b&0xffffff)|(b&0x80000000);
      if((i&3)==0) y=(y&0x807fffff)|0x20000000; /* additional tiny candidates */
      ma_trace=(struct ma_trace_state){0};
      (void)adapted_atan2(ma_asfloat(y),ma_asfloat(x));
      if(ma_trace.mask&128) { emit((unsigned)i,y,x); found++; }
    }
    fprintf(stderr,"search_trials=%" PRIu64 " general_hits=%u final_state=%" PRIu64 "\n",count,found,state);
  } else if(argc==1) {
    unsigned id; uint32_t y,x; int read;
    while((read=scanf("%u %" SCNx32 " %" SCNx32,&id,&y,&x))==3) emit(id,y,x);
    if(read!=EOF || ferror(stdin))return 10;
  } else return 11;
  return finish_context();
}
