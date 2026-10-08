/*
 * Probe-only clock injection for tools/input_probe.py; not part of raylib.
 *
 * tools/input_probe.py builds its pinned raylib variant (PLATFORM=Memory) with
 * CMAKE_C_FLAGS="-ffp-contract=off -include tools/reference/input_clock.h".
 * No raylib source is modified. The macros below only rename identifiers:
 *
 * - Every call GetTime() becomes JonlibProbeTime(), which the probe program
 *   defines to return the scripted clock. The platform's own definition
 *   `double GetTime(void)` (and its declaration in raylib.h) becomes
 *   rlPlatformGetTime(void), which nothing calls. On macOS that definition
 *   returns 0.0 (rcore_memory.c has no Apple branch), so without the
 *   injection every frame time, gesture timeout and GetFPS sample is 0 and
 *   SetTargetFPS waits forever in WaitTime's busy loop.
 * - usleep (WaitTime on macOS) and nanosleep (Linux) become
 *   JonlibProbeUsleep and JonlibProbeNanosleep: the probe records the request
 *   and advances the clock to the scripted end of the wait instead of
 *   sleeping.
 */
#ifndef JONLIB_INPUT_CLOCK_H
#define JONLIB_INPUT_CLOCK_H

double JonlibProbeTime(void);

#define JONLIB_CLOCK_CAT(a, b) a ## b
#define JONLIB_CLOCK_PICK(x) JONLIB_CLOCK_CAT(JONLIB_CLOCK_, x)
#define JONLIB_CLOCK_void rlPlatformGetTime(void)
#define JONLIB_CLOCK_ JonlibProbeTime()
#define GetTime(...) JONLIB_CLOCK_PICK(__VA_ARGS__)

#define usleep JonlibProbeUsleep
#define nanosleep JonlibProbeNanosleep

#endif
