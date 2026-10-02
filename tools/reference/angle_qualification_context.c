/* Jonlib native-angle qualification metadata, independently linked.
 * This translation unit never changes rounding, MXCSR, x87 or FPCR state.
 * It is not injected into canonical numeric expressions or raymath headers. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <elf.h>
#include <fenv.h>
#include <float.h>
#include <gnu/libc-version.h>
#include <limits.h>
#include <link.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#if !defined(__linux__) || !defined(__GLIBC__)
#error Only the explicit Linux ELF glibc metadata profile is supported
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
static const void *aq_base;
static char aq_build_id[129];
static int aq_notes(struct dl_phdr_info *info, size_t size, void *data) {
  (void)size; (void)data;
  if ((void *)info->dlpi_addr != aq_base) return 0;
  for (int i=0;i<info->dlpi_phnum;i++) if (info->dlpi_phdr[i].p_type==PT_NOTE) {
    const unsigned char *p=(const unsigned char *)(info->dlpi_addr+info->dlpi_phdr[i].p_vaddr);
    const unsigned char *end=p+info->dlpi_phdr[i].p_memsz;
    while ((size_t)(end-p)>=sizeof(ElfW(Nhdr))) {
      ElfW(Nhdr) n; memcpy(&n,p,sizeof(n)); p+=sizeof(n);
      size_t ns=(n.n_namesz+3u)&~3u, ds=(n.n_descsz+3u)&~3u;
      if (ns>(size_t)(end-p) || ds>(size_t)(end-p)-ns) break;
      if (n.n_type==NT_GNU_BUILD_ID && n.n_namesz==4 && !memcmp(p,"GNU",4) && n.n_descsz>0 && n.n_descsz<=64) {
        for (unsigned j=0;j<n.n_descsz;j++) sprintf(aq_build_id+2*j,"%02x",p[ns+j]);
        return 1;
      }
      p+=ns+ds;
    }
  }
  return 1;
}
static void aq_string(const char *s) {
  fputc('"',stderr);
  for (;*s;s++) { unsigned char c=*s;
    if (c=='"' || c=='\\') { fputc('\\',stderr); fputc(c,stderr); }
    else if (c<32 || c>=127) fprintf(stderr,"\\u%04x",c);
    else fputc(c,stderr);
  }
  fputc('"',stderr);
}
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
  int round=fegetround(); Dl_info info; struct stat st; char resolved[PATH_MAX];
  void *symbol=dlsym(RTLD_DEFAULT,"atan2f");
  if (!symbol || symbol!=(void *)aq_native || !dladdr(symbol,&info) || !info.dli_fname ||
      !realpath(info.dli_fname,resolved) || stat(resolved,&st)) _Exit(91);
  aq_base=info.dli_fbase; aq_build_id[0]=0; dl_iterate_phdr(aq_notes,0);
  if (!aq_build_id[0]) _Exit(92);
  uint32_t one=0; uint64_t done=0; float f=1.0f; double d=1.0;
  memcpy(&one,&f,4); memcpy(&done,&d,8); uint16_t endian=1;
  fprintf(stderr,"{\"kind\":\"%s-context\",\"profile\":\"linux-glibc-elf-runtime-image-v1\",\"architecture\":\"%s\",\"endian\":\"%s\",\"binary32\":%s,\"binary64\":%s,\"eval_method\":%d,\"rounding\":%d,\"nearest\":%s,\"control\":%llu,\"x87_control\":%u,\"libc_version\":",
      phase,arch,*(unsigned char *)&endian?"little":"big",one==0x3f800000u?"true":"false",done==UINT64_C(0x3ff0000000000000)?"true":"false",FLT_EVAL_METHOD,round,round==FE_TONEAREST?"true":"false",(unsigned long long)control,x87);
  aq_string(gnu_get_libc_version()); fprintf(stderr,",\"symbol\":\"atan2f\",\"symbol_path\":\"volatile-pointer-equals-dlsym-default\",\"library_path\":");
  aq_string(info.dli_fname); fprintf(stderr,",\"library_realpath\":"); aq_string(resolved);
  fprintf(stderr,",\"library_build_id\":\"%s\",\"library_stat\":[%llu,%llu,%llu,%lld,%ld],\"loader_overrides\":{",aq_build_id,(unsigned long long)st.st_dev,(unsigned long long)st.st_ino,(unsigned long long)st.st_size,(long long)st.st_mtim.tv_sec,st.st_mtim.tv_nsec);
  const char *names[]={"LD_PRELOAD","LD_LIBRARY_PATH","LD_AUDIT","LD_BIND_NOW","GLIBC_TUNABLES","LD_HWCAP_MASK","LD_ASSUME_KERNEL"};
  for (unsigned i=0;i<sizeof(names)/sizeof(*names);i++) {
    if (i) fputc(',',stderr); aq_string(names[i]); fputc(':',stderr);
    const char *value=getenv(names[i]); if(value) aq_string(value); else fputs("null",stderr);
  }
  fputs("}}\n",stderr); fflush(stderr);
}
__attribute__((constructor)) static void aq_initial(void) { aq_metadata("initial"); }
__attribute__((destructor)) static void aq_final(void) { aq_metadata("final"); }
