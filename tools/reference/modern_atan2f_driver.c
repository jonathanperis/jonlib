/* Jonlib native oracle driver for the pinned atan2f kernels. Not a production
 * angle implementation. The instrumented glibc-2.41 adaptation, the unmodified
 * glibc-2.41 source, the pinned Sun 2.39 source and host libm remain distinct
 * call paths; rows are read from a file of "id y x" hexadecimal words. */
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <fenv.h>
#include "modern_atan2f_shim.h"
#include "modern_atan2f_trace.h"
#if defined(__x86_64__) || defined(__i386__)
#include <xmmintrin.h>
#endif
struct ma_trace_state ma_trace;
float modern_atan2f_adapted(float,float);
float glibc241_atan2f(float,float);
float sun239_atan2f(float,float);
static float (*volatile native_atan2)(float,float) = atan2f;
static float (*volatile original_atan2)(float,float) = glibc241_atan2f;
static float (*volatile adapted_atan2)(float,float) = modern_atan2f_adapted;
static float (*volatile sun_atan2)(float,float) = sun239_atan2f;

/* Oracle sanity: round-to-nearest, no FTZ/DAZ, true FMA, exact narrowing and
 * gradual underflow. Any failure invalidates every pinned-source observation. */
static int context_ok(void) {
  if (fegetround()!=FE_TONEAREST) return 0;
#if defined(__x86_64__) || defined(__i386__)
  return !(_mm_getcsr() & ((1u<<15)|(1u<<6)|(3u<<13)));
#elif defined(__aarch64__)
  uint64_t c; __asm__ volatile("mrs %0, fpcr" : "=r"(c));
  return !(c & ((1ull<<24)|(1ull<<19)|(3ull<<22)|3ull));
#else
  return 1;
#endif
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
  } else if(argc==2) {
    FILE *in=fopen(argv[1],"r"); if(!in) return 10;
    unsigned id; uint32_t y,x; int read;
    while((read=fscanf(in,"%u %" SCNx32 " %" SCNx32,&id,&y,&x))==3) emit(id,y,x);
    if(read!=EOF || ferror(in))return 10;
    fclose(in);
  } else return 11;
  return context_ok() ? 0 : 12;
}
