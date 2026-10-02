/* Synthetic Mach-O metadata only: this is not macOS runtime evidence. */
#include "runtime_image_macho.h"
#include "runtime_image.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define SEG 56u
#define SEC 128u
#define GOOD 208u
#define BASE UINT64_C(0x180000000)
static void w32(unsigned char *p, uint32_t n) {
  for (unsigned i=0;i<4;i++) p[i]=(unsigned char)(n>>(8*i));
}
static void w64(unsigned char *p, uint64_t n) {
  for (unsigned i=0;i<8;i++) p[i]=(unsigned char)(n>>(8*i));
}
static void valid(unsigned char *p) {
  memset(p,0,1024);
  w32(p,0xfeedfacf); w32(p+4,0x01000007); w32(p+8,3); w32(p+12,6);
  w32(p+16,2); w32(p+20,GOOD-32);
  w32(p+32,0x1b); w32(p+36,24); p[40]=1;
  w32(p+SEG,0x19); w32(p+SEG+4,152); memcpy(p+SEG+8,"__TEXT",6);
  w64(p+SEG+24,BASE); w64(p+SEG+32,0x2000); w64(p+SEG+48,0x2000);
  w32(p+SEG+56,5); w32(p+SEG+60,5); w32(p+SEG+64,1);
  memcpy(p+SEC,"__text",6); memcpy(p+SEC+16,"__TEXT",6);
  w64(p+SEC+32,BASE+0x1000); w64(p+SEC+40,0x400); w32(p+SEC+48,0x1000);
  w32(p+SEC+64,0x80000400);
}
static void reject(const unsigned char *p, size_t size) {
  struct ri_macho result, zero={0};
  memset(&result,0xa5,sizeof result);
  assert(!ri_macho_parse(p,size,&result));
  assert(!memcmp(&result,&zero,sizeof result));
}
static uint32_t rng(uint32_t *state) {
  uint32_t x=*state; x^=x<<13; x^=x>>17; x^=x<<5; return *state=x;
}
int main(int argc, char **argv) {
  unsigned char p[1024], q[1025];
  struct ri_macho result;
  if (argc==2 && !strcmp(argv[1],"loader")) return !jon_runtime_loader_write_json(stdout);
  valid(p); assert(ri_macho_parse(p,GOOD,&result));
  assert(result.cpu_type==0x01000007 && result.cpu_subtype==3 && result.uuid[0]==1);
  assert(result.image_vmaddr==BASE && result.text_vmaddr==BASE+0x1000 && result.text_size==0x400);
  memcpy(q+1,p,GOOD); assert(ri_macho_parse(q+1,GOOD,&result));
  assert(!ri_macho_parse(p,GOOD,NULL)); reject(NULL,GOOD);
  for (size_t n=0;n<GOOD;n++) {
    unsigned char *short_input=malloc(n?n:1);
    assert(short_input); memcpy(short_input,p,n); reject(short_input,n); free(short_input);
  }
#define BAD32(off,value) do { valid(p); w32(p+(off),(value)); reject(p,GOOD); } while (0)
#define BAD64(off,value) do { valid(p); w64(p+(off),(value)); reject(p,GOOD); } while (0)
  BAD32(0,0xcffaedfe); BAD32(0,0xfeedface); BAD32(4,7); BAD32(8,99);
  BAD32(12,1); BAD32(28,1); BAD32(16,0); BAD32(16,4097); BAD32(16,3);
  BAD32(20,RI_MACHO_COMMAND_LIMIT+1); BAD32(20,175); BAD32(36,0); BAD32(36,23);
  BAD32(36,32); BAD32(36,UINT32_MAX); BAD32(40,0);
  BAD32(SEG+4,144); BAD32(SEG+4,160); BAD32(SEG+64,0); BAD32(SEG+64,UINT32_MAX);
  BAD32(SEG+56,7); BAD32(SEG+60,7); BAD32(SEG+56,4); BAD32(SEG+60,1);
  BAD64(SEG+24,UINT64_MAX-1); BAD64(SEG+32,32); BAD64(SEG+48,UINT64_MAX);
  BAD64(SEG+40,1); BAD64(SEG+40,UINT64_MAX);
  BAD64(SEC+32,BASE-1); BAD64(SEC+32,BASE+0x1f00); BAD64(SEC+32,BASE+32);
  BAD64(SEC+40,0); BAD64(SEC+40,UINT64_MAX); BAD64(SEC+40,RI_MACHO_CODE_LIMIT+1);
  BAD32(SEC+48,0); BAD32(SEC+60,1); BAD32(SEC+64,0); BAD32(SEC+64,0x80000001);
  valid(p); p[SEG+8]='x'; reject(p,GOOD);
  valid(p); p[SEC+16]='x'; reject(p,GOOD);
  valid(p); p[SEC]='x'; reject(p,GOOD);
  valid(p); p[SEG+8+7]=1; reject(p,GOOD);
  valid(p); w32(p+4,0x0100000c); w32(p+8,0); assert(ri_macho_parse(p,GOOD,&result));
  w32(p+8,0x80000002); assert(ri_macho_parse(p,GOOD,&result));
  w32(p+8,3); reject(p,GOOD);
  valid(p); w32(p+8,8); assert(ri_macho_parse(p,GOOD,&result));
  valid(p); w32(p+24,RI_MACHO_CACHE_FLAG); w64(p+SEG+40,0x4000);
  w32(p+SEC+48,0x5000); assert(ri_macho_parse(p,GOOD,&result));
  w32(p+12,2); reject(p,GOOD);
  valid(p); memcpy(p+GOOD,p+32,24); w32(p+16,3); w32(p+20,GOOD-32+24); reject(p,GOOD+24);
  valid(p); memcpy(p+GOOD,p+SEG,152); w32(p+16,3); w32(p+20,GOOD-32+152); reject(p,GOOD+152);
  /* A second segment may not alias code or the header. */
  valid(p); memcpy(p+GOOD,p+SEG,72); memcpy(p+GOOD+8,"__DATA",6);
  w32(p+GOOD+4,72); w32(p+GOOD+64,0); w32(p+16,3); w32(p+20,GOOD-32+72);
  reject(p,GOOD+72);
  w64(p+GOOD+24,BASE+0x4000); assert(ri_macho_parse(p,GOOD+72,&result));
  /* Nor may a differently named section alias __text. */
  valid(p); memcpy(p+GOOD,p+SEC,80); memcpy(p+GOOD,"__alias",7);
  w32(p+SEG+4,232); w32(p+SEG+64,2); w32(p+20,GOOD-32+80); reject(p,GOOD+80);
  valid(p); w32(p+GOOD,0x123); w32(p+GOOD+4,8); w32(p+16,3); w32(p+20,GOOD-32+8);
  assert(ri_macho_parse(p,GOOD+8,&result));
  /* Deterministic bounded mutation/truncation smoke corpus, sanitizer-friendly. */
  uint32_t state=0x12fe4531;
  for (unsigned i=0;i<20000;i++) {
    valid(p);
    unsigned edits=1+rng(&state)%8;
    for (unsigned j=0;j<edits;j++) p[rng(&state)%GOOD]=(unsigned char)rng(&state);
    size_t n=rng(&state)%(GOOD+1);
    unsigned char *input=malloc(n?n:1); assert(input); memcpy(input,p,n);
    if (ri_macho_parse(input,n,&result)) {
      assert(result.text_size && result.text_size<=RI_MACHO_CODE_LIMIT);
      assert(result.text_vmaddr>=result.image_vmaddr);
    }
    free(input);
  }
#if !defined(__APPLE__)
  FILE *file=tmpfile(); assert(file);
  assert(!jon_runtime_image_write_json(file,p)); assert(ftell(file)==0); fclose(file);
#endif
  puts("Mach-O parser synthetic checks passed");
  return 0;
}
