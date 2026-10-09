/* Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
   Build shim: the callers run in the default round-to-nearest mode with the
   53-bit precision of SSE2/AArch64, where glibc's rounding-mode guard changes
   no result, so it is empty here. */
#ifndef JONLIB_SHIM_FENV_PRIVATE_H
#define JONLIB_SHIM_FENV_PRIVATE_H
#define SET_RESTORE_ROUND_53BIT(RM)
#endif
