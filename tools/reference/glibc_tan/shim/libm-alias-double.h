/* Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
   Build shim: no symbol aliases; errno as glibc's __set_errno sets it. */
#define libm_alias_double(from, to)
#ifndef __set_errno
# include <errno.h>
# define __set_errno(e) (errno = (e))
#endif
