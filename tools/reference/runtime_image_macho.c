/* Original parser implementation of the public Mach-O64 format documented in:
 * https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h
 * No Apple source implementation is copied. Integer loads are byte-wise so
 * tests are independent of host alignment, endianness and Darwin headers. */
#include "runtime_image_macho.h"
#include <string.h>
#define RI_CPU_X86_64 UINT32_C(0x01000007)
#define RI_CPU_ARM64 UINT32_C(0x0100000c)
static uint32_t u32(const unsigned char *p) {
  return (uint32_t)p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24;
}
static uint64_t u64(const unsigned char *p) {
  return (uint64_t)u32(p) | (uint64_t)u32(p+4)<<32;
}
static int name_is(const unsigned char *p, const char *s) {
  size_t n=strlen(s);
  return n<16 && !memcmp(p,s,n) && !memcmp(p+n,"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",16-n);
}
static int range(uint64_t start, uint64_t size) { return size<=UINT64_MAX-start; }
static int contains(uint64_t start, uint64_t size, uint64_t at, uint64_t n) {
  return range(start,size) && at>=start && at-start<=size && n<=size-(at-start);
}
int ri_macho_parse(const void *bytes, size_t size, struct ri_macho *out) {
  const unsigned char *p=(const unsigned char *)bytes;
  struct ri_macho result={0};
  uint32_t ncmds, total, subtype, filetype;
  unsigned uuids=0, texts=0, sections=0;
  size_t off=RI_MACHO_HEADER_SIZE, end;
  if (!out) return 0;
  memset(out,0,sizeof *out);
  if (!p || size<RI_MACHO_HEADER_SIZE || u32(p)!=UINT32_C(0xfeedfacf)) return 0;
  result.cpu_type=u32(p+4); result.cpu_subtype=u32(p+8);
  subtype=result.cpu_subtype & UINT32_C(0x00ffffff);
  if (result.cpu_type==RI_CPU_X86_64) {
    if (subtype!=3 && subtype!=8) return 0;
  } else if (result.cpu_type==RI_CPU_ARM64) {
    if (subtype>2) return 0;
  } else return 0;
  filetype=u32(p+12); result.flags=u32(p+24);
  if (filetype!=2 && filetype!=6 && filetype!=8) return 0;
  if ((result.flags&RI_MACHO_CACHE_FLAG) && filetype!=6) return 0;
  if (u32(p+28)!=0) return 0;
  ncmds=u32(p+16); total=u32(p+20);
  if (!ncmds || ncmds>4096 || total>RI_MACHO_COMMAND_LIMIT ||
      total>size-RI_MACHO_HEADER_SIZE || ncmds>total/8) return 0;
  end=RI_MACHO_HEADER_SIZE+(size_t)total; result.command_bytes=total;
  for (uint32_t i=0;i<ncmds;i++) {
    uint32_t cmd, len;
    if (off>end || end-off<8) return 0;
    cmd=u32(p+off); len=u32(p+off+4);
    if (len<8 || (len&7) || len>end-off) return 0;
    if (cmd==UINT32_C(0x1b)) { /* LC_UUID */
      unsigned nonzero=0;
      if (len!=24 || ++uuids!=1) return 0;
      for (unsigned j=0;j<16;j++) nonzero|=p[off+8+j];
      if (!nonzero) return 0;
      memcpy(result.uuid,p+off+8,16);
    } else if (cmd==UINT32_C(0x19)) { /* LC_SEGMENT_64 */
      const unsigned char *s=p+off;
      uint64_t vm, vs, fo, fs;
      uint32_t ns, maxp, initp;
      int text;
      if (len<72) return 0;
      vm=u64(s+24); vs=u64(s+32); fo=u64(s+40); fs=u64(s+48);
      maxp=u32(s+56); initp=u32(s+60); ns=u32(s+64);
      if (ns>4096 || ns>(len-72)/80 || len!=72+ns*80 ||
          !range(vm,vs) || !range(fo,fs) || fs>vs ||
          (maxp&~7u) || (initp&~maxp)) return 0;
      text=name_is(s+8,"__TEXT");
      if (text) {
        if (++texts!=1 || (maxp&7u)!=5 || (initp&7u)!=5 ||
            fs<end || vs<end || (!(result.flags&RI_MACHO_CACHE_FLAG) && fo!=0)) return 0;
        result.image_vmaddr=vm;
      }
      for (uint32_t j=0;j<ns;j++) {
        const unsigned char *sc=s+72+80*j;
        uint64_t addr=u64(sc+32), sz=u64(sc+40);
        uint32_t flags=u32(sc+64);
        if (memcmp(sc+16,s+8,16) || !contains(vm,vs,addr,sz)) return 0;
        if (name_is(sc,"__text")) {
          /* A __text in another segment or two named sections is ambiguous. */
          if (!text || ++sections!=1 || !sz || sz>RI_MACHO_CODE_LIMIT ||
              (flags&255u)!=0 || !(flags&UINT32_C(0x80000000)) ||
              u32(sc+60)!=0 || addr-vm<end || !contains(vm,fs,addr,sz)) return 0;
          if (!(result.flags&RI_MACHO_CACHE_FLAG) &&
              (uint64_t)u32(sc+48)!=addr-vm) return 0;
          result.text_vmaddr=addr; result.text_size=sz;
        }
      }
    } else if (cmd==1) return 0; /* A 32-bit segment in a 64-bit image. */
    off+=len;
  }
  if (off!=end || uuids!=1 || texts!=1 || sections!=1) return 0;
  /* Reject any second segment overlapping the selected __TEXT code or header.
   * This second bounded pass avoids dynamically sized interval tables. */
  off=RI_MACHO_HEADER_SIZE;
  for (uint32_t i=0;i<ncmds;i++) {
    const unsigned char *s=p+off;
    if (u32(s)==UINT32_C(0x19)) {
      uint64_t vm=u64(s+24), vs=u64(s+32);
      if (!name_is(s+8,"__TEXT") && vs &&
          ((vm<result.text_vmaddr+result.text_size && vm+vs>result.text_vmaddr) ||
           (vm<result.image_vmaddr+end && vm+vs>result.image_vmaddr))) return 0;
      for (uint32_t j=0;j<u32(s+64);j++) {
        const unsigned char *sc=s+72+80*j;
        uint64_t at=u64(sc+32), sz=u64(sc+40);
        if (!name_is(sc,"__text") && sz && at<result.text_vmaddr+result.text_size &&
            at+sz>result.text_vmaddr) return 0;
      }
    }
    off+=u32(s+4);
  }
  *out=result;
  return 1;
}
