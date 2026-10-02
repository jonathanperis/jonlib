/* Jonlib loaded-code identity, independent of numeric expressions.
 * Public Apple interfaces (no private dyld SPI):
 * https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/dyld.h
 * https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/dyld_images.h
 * https://github.com/apple-oss-distributions/xnu/blob/xnu-10063.121.3/osfmk/mach/task_info.h
 * https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/mach_vm.defs
 * https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_region.h
 * https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/CC_SHA256.3cc.html
 *
 * Every foreign-memory read is a checked mach_vm_read_overwrite into owned
 * storage, never a raw load from a dladdr/header/section address. Header/code
 * mappings must be readable, non-writable even at maximum protection, and code
 * must be executable. Checks bracket reads. This is a fail-closed provenance
 * snapshot in the qualification process, not synchronization against hostile
 * concurrent unmapping/remapping or an arbitrary in-process attacker.
 */
#if defined(__APPLE__)
#define _DARWIN_C_SOURCE 1
#endif
#include "runtime_image.h"
#include "runtime_image_macho.h"
#include <stdlib.h>
/* JSON text must preserve UTF-8 rather than reinterpret individual high bytes
 * as Latin-1. Non-UTF-8 paths/environment values are unsupported, fail closed. */
static int ri_utf8(const char *s) {
  const unsigned char *p=(const unsigned char *)s;
  while (*p) {
    unsigned char c=*p++;
    unsigned need;
    unsigned long value, minimum;
    if (c<128) continue;
    if (c>=0xc2 && c<=0xdf) { need=1; value=c&31u; minimum=0x80; }
    else if (c>=0xe0 && c<=0xef) { need=2; value=c&15u; minimum=0x800; }
    else if (c>=0xf0 && c<=0xf4) { need=3; value=c&7u; minimum=0x10000; }
    else return 0;
    for (unsigned i=0;i<need;i++) {
      if ((*p&0xc0u)!=0x80u) return 0;
      value=(value<<6)|(*p++&63u);
    }
    if (value<minimum || value>0x10ffff || (value>=0xd800 && value<=0xdfff)) return 0;
  }
  return 1;
}
static void ri_string(FILE *out, const char *s) {
  fputc('"',out);
  for (;*s;s++) {
    unsigned char c=(unsigned char)*s;
    if (c=='"' || c=='\\') { fputc('\\',out); fputc(c,out); }
    else if (c<32) fprintf(out,"\\u%04x",(unsigned)c);
    else fputc(c,out);
  }
  fputc('"',out);
}
int jon_runtime_loader_write_json(FILE *out) {
  static const char *const names[]={
    "DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "DYLD_FRAMEWORK_PATH",
    "DYLD_FALLBACK_LIBRARY_PATH", "DYLD_FALLBACK_FRAMEWORK_PATH",
    "DYLD_VERSIONED_LIBRARY_PATH", "DYLD_VERSIONED_FRAMEWORK_PATH",
    "DYLD_ROOT_PATH", "DYLD_IMAGE_SUFFIX", "DYLD_SHARED_REGION",
    "DYLD_SHARED_CACHE_DIR", "DYLD_SHARED_CACHE_DONT_VALIDATE",
    "DYLD_FORCE_FLAT_NAMESPACE", "DYLD_BIND_AT_LAUNCH"
  };
  const char *values[sizeof names/sizeof *names];
  if (!out) return 0;
  for (size_t i=0;i<sizeof names/sizeof *names;i++) {
    values[i]=getenv(names[i]);
    if (values[i] && !ri_utf8(values[i])) return 0;
  }
  fputc('{',out);
  for (size_t i=0;i<sizeof names/sizeof *names;i++) {
    const char *value=values[i];
    if (i) fputc(',',out);
    ri_string(out,names[i]); fputc(':',out);
    if (value) ri_string(out,value); else fputs("null",out);
  }
  fputc('}',out);
  return !ferror(out);
}
#if defined(__APPLE__) && defined(__LP64__)
#include <CommonCrypto/CommonDigest.h>
#include <AvailabilityMacros.h>
#include <dlfcn.h>
#include <inttypes.h>
#include <limits.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/task_info.h>
#include <mach/vm_region.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#ifndef __has_feature
#define __has_feature(x) 0
#endif
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 110000
#error Darwin runtime provenance requires a macOS 11 or newer SDK
#endif
#define RI_PATH_LIMIT 4096u
#define RI_CHUNK_SIZE 65536u
struct ri_cache {
  unsigned char uuid[16];
  uint64_t base, slide;
  uint32_t version;
};
struct ri_live {
  struct ri_macho macho;
  struct ri_cache cache;
  char path[RI_PATH_LIMIT], realpath[PATH_MAX];
  struct stat stat;
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  uint64_t image, text, symbol;
  int cached;
};
static uint32_t ri_le32(const unsigned char *p) {
  return (uint32_t)p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24;
}
/* Walk leaf mappings; a request beginning in a gap must not accept the next
 * region returned by Mach. A bounded depth also rejects malformed submaps. */
static int ri_span(uint64_t start, uint64_t length, int code, int immutable) {
  uint64_t end, cur;
  unsigned regions=0;
  if (!length || length>UINT64_MAX-start) return 0;
  end=start+length; cur=start;
  while (cur<end) {
    mach_vm_address_t address=cur;
    mach_vm_size_t size=0;
    natural_t depth=0;
    vm_region_submap_info_data_64_t info;
    for (;;) {
      mach_msg_type_number_t count=VM_REGION_SUBMAP_INFO_COUNT_64;
      memset(&info,0,sizeof info);
      if (++regions>65536 ||
          mach_vm_region_recurse(mach_task_self(),&address,&size,&depth,
            (vm_region_recurse_info_t)&info,&count)!=KERN_SUCCESS ||
          count<VM_REGION_SUBMAP_INFO_V0_COUNT_64 || address>cur ||
          !size || size>UINT64_MAX-address || cur>=address+size) return 0;
      if (!info.is_submap) break;
      if (depth>=32) return 0;
      ++depth; address=cur;
    }
    if (!(info.protection&VM_PROT_READ) ||
        (code && !(info.protection&VM_PROT_EXECUTE)) ||
        (immutable && ((info.protection|info.max_protection)&VM_PROT_WRITE))) return 0;
    cur=address+size<end ? address+size : end;
  }
  return 1;
}
static int ri_read(uint64_t from, void *to, size_t size, int code, int immutable) {
  mach_vm_size_t copied=0;
  if (!ri_span(from,size,code,immutable) ||
      mach_vm_read_overwrite(mach_task_self(),(mach_vm_address_t)from,
        (mach_vm_size_t)size,(mach_vm_address_t)(uintptr_t)to,&copied)!=KERN_SUCCESS ||
      copied!=size) return 0;
  return ri_span(from,size,code,immutable);
}
static int ri_path(const char *from, char *to, size_t limit) {
  uint64_t address=(uintptr_t)from;
  size_t offset=0;
  if (!from || !limit) return 0;
  while (offset<limit) {
    /* Never cross even a 4KiB page boundary while looking for a terminator. */
    size_t n=64, page=4096-(size_t)(address&4095u);
    if (n>page) n=page;
    if (n>limit-offset) n=limit-offset;
    if (!ri_read(address,to+offset,n,0,0)) return 0;
    if (memchr(to+offset,0,n)) return offset || to[0];
    if (n>UINT64_MAX-address) return 0;
    offset+=n; address+=n;
  }
  return 0;
}
static int ri_cache_info(struct ri_cache *out) {
  task_dyld_info_data_t task={0};
  mach_msg_type_number_t count=TASK_DYLD_INFO_COUNT;
  struct dyld_all_image_infos infos;
  size_t needed=offsetof(struct dyld_all_image_infos,sharedCacheBaseAddress)+
                sizeof infos.sharedCacheBaseAddress;
  uint32_t version;
  unsigned nonzero=0;
  memset(out,0,sizeof *out); memset(&infos,0,sizeof infos);
  if (task_info(mach_task_self(),TASK_DYLD_INFO,(task_info_t)&task,&count)!=KERN_SUCCESS ||
      count<TASK_DYLD_INFO_COUNT || task.all_image_info_format!=TASK_DYLD_ALL_IMAGE_INFO_64 ||
      task.all_image_info_size<needed || !task.all_image_info_addr ||
      !ri_read(task.all_image_info_addr,&version,sizeof version,0,0) || version<15 ||
      !ri_read(task.all_image_info_addr,&infos,needed,0,0) || infos.version!=version ||
      ((const unsigned char *)&infos)[offsetof(struct dyld_all_image_infos,processDetachedFromSharedRegion)]!=0 ||
      !infos.sharedCacheBaseAddress) return 0;
  for (unsigned i=0;i<16;i++) nonzero|=infos.sharedCacheUUID[i];
  if (!nonzero) return 0;
  memcpy(out->uuid,infos.sharedCacheUUID,16);
  out->base=infos.sharedCacheBaseAddress; out->slide=infos.sharedCacheSlide;
  out->version=version;
  return 1;
}
static int ri_hash(uint64_t start, uint64_t size, unsigned char *digest) {
  CC_SHA256_CTX context;
  unsigned char chunk[RI_CHUNK_SIZE];
  uint64_t offset=0;
  if (!ri_span(start,size,1,1) || !CC_SHA256_Init(&context)) return 0;
  while (offset<size) {
    size_t n=(size-offset)>sizeof chunk ? sizeof chunk : (size_t)(size-offset);
    if (!ri_read(start+offset,chunk,n,1,1) ||
        !CC_SHA256_Update(&context,chunk,(CC_LONG)n)) return 0;
    offset+=n;
  }
  return ri_span(start,size,1,1) && CC_SHA256_Final(digest,&context);
}
static int ri_same_stat(const struct stat *a, const struct stat *b) {
  return a->st_dev==b->st_dev && a->st_ino==b->st_ino && a->st_size==b->st_size &&
         a->st_mtimespec.tv_sec==b->st_mtimespec.tv_sec &&
         a->st_mtimespec.tv_nsec==b->st_mtimespec.tv_nsec;
}
static int ri_collect(const void *function, struct ri_live *out) {
  Dl_info info={0}, later={0};
  unsigned char header[RI_MACHO_HEADER_SIZE], *commands=NULL, *check=NULL;
  struct ri_cache cache_check;
  struct stat stat_check;
  char path_check[RI_PATH_LIMIT], resolved_check[PATH_MAX];
  size_t total;
  uint64_t delta;
  int ok=0, membership;
  memset(out,0,sizeof *out);
#if __has_feature(ptrauth_calls)
  function=ptrauth_strip((void *)function,ptrauth_key_function_pointer);
#endif
  if (!function || !dladdr(function,&info) || !info.dli_fbase ||
      !ri_path(info.dli_fname,out->path,sizeof out->path)) return 0;
  out->image=(uintptr_t)info.dli_fbase; out->symbol=(uintptr_t)function;
  if (!ri_read(out->image,header,sizeof header,0,1) ||
      ri_le32(header)!=UINT32_C(0xfeedfacf) ||
      ri_le32(header+20)>RI_MACHO_COMMAND_LIMIT) return 0;
  total=RI_MACHO_HEADER_SIZE+(size_t)ri_le32(header+20);
  commands=malloc(total); check=malloc(total);
  if (!commands || !check || !ri_read(out->image,commands,total,0,1) ||
      memcmp(commands,header,sizeof header) || !ri_macho_parse(commands,total,&out->macho)) goto done;
#if defined(__x86_64__)
  if (out->macho.cpu_type!=UINT32_C(0x01000007)) goto done;
#elif defined(__aarch64__) || defined(__arm64__)
  if (out->macho.cpu_type!=UINT32_C(0x0100000c)) goto done;
#else
  goto done;
#endif
  delta=out->macho.text_vmaddr-out->macho.image_vmaddr;
  if (delta>UINT64_MAX-out->image) goto done;
  out->text=out->image+delta;
  if (out->macho.text_size>UINT64_MAX-out->text || out->symbol<out->text ||
      out->symbol-out->text>=out->macho.text_size) goto done;
  if (__builtin_available(macOS 11.0, *)) {
    membership=_dyld_shared_cache_contains_path(out->path) ? 1 : 0;
  } else goto done;
  out->cached=(out->macho.flags&RI_MACHO_CACHE_FLAG) ? 1 : 0;
  if (membership!=out->cached) goto done;
  if (out->cached) {
    /* The header flag identifies THIS loaded image; the public path query
     * establishes membership in the active cache. Require the active cache's
     * observed slide to explain this image's actual mapped address as well. */
    if (!ri_cache_info(&out->cache) || out->image<out->cache.base ||
        out->text<out->cache.base || out->image<out->cache.slide ||
        out->image-out->cache.slide!=out->macho.image_vmaddr) goto done;
  } else {
    if (!realpath(out->path,out->realpath) || stat(out->realpath,&out->stat) ||
        !S_ISREG(out->stat.st_mode) || out->stat.st_size<=0 ||
        out->stat.st_mtimespec.tv_nsec<0 || out->stat.st_mtimespec.tv_nsec>=1000000000L) goto done;
  }
  if (!ri_hash(out->text,out->macho.text_size,out->digest) ||
      !ri_read(out->image,check,total,0,1) || memcmp(commands,check,total) ||
      !dladdr(function,&later) || later.dli_fbase!=info.dli_fbase ||
      !ri_path(later.dli_fname,path_check,sizeof path_check) || strcmp(path_check,out->path)) goto done;
  if (__builtin_available(macOS 11.0, *)) {
    if ((_dyld_shared_cache_contains_path(out->path) ? 1 : 0)!=membership) goto done;
  } else goto done;
  if (out->cached) {
    if (!ri_cache_info(&cache_check) || memcmp(cache_check.uuid,out->cache.uuid,16) ||
        cache_check.base!=out->cache.base || cache_check.slide!=out->cache.slide ||
        cache_check.version!=out->cache.version) goto done;
  } else if (!realpath(out->path,resolved_check) || strcmp(resolved_check,out->realpath) ||
             stat(out->realpath,&stat_check) || !ri_same_stat(&stat_check,&out->stat)) goto done;
  if (!ri_utf8(out->path) || (!out->cached && !ri_utf8(out->realpath))) goto done;
  ok=1;
done:
  free(check); free(commands);
  return ok;
}
static void ri_hex(FILE *out, const unsigned char *bytes, size_t n) {
  fputc('"',out);
  for (size_t i=0;i<n;i++) fprintf(out,"%02x",(unsigned)bytes[i]);
  fputc('"',out);
}
int jon_runtime_image_write_json(FILE *out, const void *function) {
  struct ri_live value;
  const char *arch;
  if (!out || !ri_collect(function,&value)) return 0;
  arch=value.macho.cpu_type==UINT32_C(0x01000007) ? "x86_64" : "aarch64";
  fprintf(out,"{\"profile\":\"darwin-macho-%s-v1\",\"format\":\"mach-o-64\","
    "\"architecture\":\"%s\",\"endian\":\"little\",\"cpu_type\":%" PRIu32
    ",\"cpu_subtype\":%" PRIu32 ",\"image_uuid\":",
    value.cached ? "shared-cache" : "file",arch,value.macho.cpu_type,value.macho.cpu_subtype);
  ri_hex(out,value.macho.uuid,16);
  fprintf(out,",\"storage\":\"%s\",\"cache_membership\":%s,\"cache_flag\":%s,\"path\":",
    value.cached ? "dyld-shared-cache" : "file",value.cached ? "true" : "false",value.cached ? "true" : "false");
  ri_string(out,value.path); fputs(",\"realpath\":",out);
  if (value.cached) fputs("null,\"stat\":null",out);
  else {
    ri_string(out,value.realpath);
    fprintf(out,",\"stat\":[%" PRIuMAX ",%" PRIuMAX ",%" PRIuMAX ",%" PRIdMAX ",%ld]",
      (uintmax_t)value.stat.st_dev,(uintmax_t)value.stat.st_ino,(uintmax_t)value.stat.st_size,
      (intmax_t)value.stat.st_mtimespec.tv_sec,value.stat.st_mtimespec.tv_nsec);
  }
  fputs(",\"cache_uuid\":",out);
  if (value.cached) ri_hex(out,value.cache.uuid,16); else fputs("null",out);
  fprintf(out,",\"text\":{\"segment\":\"__TEXT\",\"section\":\"__text\","
    "\"vmaddr\":%" PRIu64 ",\"size\":%" PRIu64 ",\"sha256\":",
    value.macho.text_vmaddr,value.macho.text_size);
  ri_hex(out,value.digest,sizeof value.digest);
  fprintf(out,",\"protection\":\"read-execute\"},\"symbol_offset\":%" PRIu64
    ",\"observations\":{\"image_base\":\"0x%" PRIx64 "\",\"text_address\":\"0x%" PRIx64
    "\",\"symbol_address\":\"0x%" PRIx64 "\"}}",
    value.symbol-value.text,value.image,value.text,value.symbol);
  return !ferror(out);
}
#else
int jon_runtime_image_write_json(FILE *out, const void *function) {
  (void)out; (void)function; return 0;
}
#endif
