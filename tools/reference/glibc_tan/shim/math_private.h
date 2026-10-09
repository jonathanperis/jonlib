/* Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
   Build shim for the pinned glibc sources: the float word access macros of
   glibc's math_private.h, through memcpy. */
#ifndef JONLIB_SHIM_MATH_PRIVATE_H
#define JONLIB_SHIM_MATH_PRIVATE_H
#include <stdint.h>
#include <string.h>
#define GET_FLOAT_WORD(i, d) do { float __gf = (d); uint32_t __gw; memcpy (&__gw, &__gf, 4); (i) = (int32_t) __gw; } while (0)
#define SET_FLOAT_WORD(d, i) do { uint32_t __sw = (uint32_t) (i); float __sf; memcpy (&__sf, &__sw, 4); (d) = __sf; } while (0)
#endif
