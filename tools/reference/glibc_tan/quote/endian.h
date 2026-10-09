/* Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
   Build shim for the pinned glibc 2.39 dbl-64 sources outside the glibc tree
   (found only through -iquote, so system headers keep <endian.h>):
   little-endian word order, as glibc's include/endian.h selects on x86_64 and
   arm64. */
#ifndef JONLIB_SHIM_ENDIAN_H
#define JONLIB_SHIM_ENDIAN_H
#define LITTLE_ENDI 1
#define HIGH_HALF 1
#define LOW_HALF 0
#endif
