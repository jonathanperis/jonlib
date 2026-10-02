#ifndef JONLIB_RUNTIME_IMAGE_MACHO_H
#define JONLIB_RUNTIME_IMAGE_MACHO_H
/* Bounded, allocation-free parser for a COPY of a loaded Mach-O64 header and
 * load commands. It never dereferences an address encoded in the input. */
#include <stddef.h>
#include <stdint.h>
#define RI_MACHO_HEADER_SIZE 32u
#define RI_MACHO_COMMAND_LIMIT (1024u * 1024u)
#define RI_MACHO_CODE_LIMIT (UINT64_C(256) * 1024u * 1024u)
#define RI_MACHO_CACHE_FLAG UINT32_C(0x80000000)
struct ri_macho {
  uint32_t cpu_type, cpu_subtype, flags;
  uint32_t command_bytes;
  unsigned char uuid[16];
  uint64_t image_vmaddr, text_vmaddr, text_size;
};
/* Returns 1 only on a supported, unambiguous image; zeroes *out on failure.
 * Input size need cover only the header and load commands, not code bytes.
 * Callers must separately validate live mappings and hash the code copy. */
int ri_macho_parse(const void *bytes, size_t size, struct ri_macho *out);
#endif
