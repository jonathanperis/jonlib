/* Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
   Build shim: glibc's underflow forcing only raises a floating-point
   exception flag (out of contract); it never changes a result. */
#ifndef JONLIB_SHIM_MATH_UNDERFLOW_H
#define JONLIB_SHIM_MATH_UNDERFLOW_H
#define math_check_force_underflow(x) do { } while (0)
#define math_check_force_underflow_nonneg(x) do { } while (0)
#endif
