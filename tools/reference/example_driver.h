/*
 * Probe-only frame driver for tools/examples_probe.py; not part of raylib.
 *
 * tools/examples_probe.py compiles each unmodified raylib example source
 * (examples/<module>/<name>.c of the pinned checkout) with
 * "-include tools/reference/example_driver.h" and links it with the probe's
 * driver translation unit and the clock-injected memory-platform raylib of
 * tools/input_probe.py (tools/reference/input_clock.h). The macros below only
 * rename identifiers in the example's translation unit; raylib.h's
 * declarations become declarations of the hooks, which have the same
 * signatures. The driver's hooks call the real functions:
 *
 * - InitWindow: reads the script named by JONLIB_EXAMPLE_SCRIPT, sets the
 *   scripted clock, silences logging, calls InitWindow, then
 *   SetRandomSeed(script seed) (raylib seeds from time(NULL)).
 * - WindowShouldClose: ends the loop after the script's last frame; otherwise
 *   plays the next frame's automation events (PlayAutomationEvent) and
 *   answers the real WindowShouldClose().
 * - BeginDrawing / EndDrawing: set the frame's scripted clocks (EndDrawing's
 *   SetTargetFPS wait ends at the scripted `after`), call the real function,
 *   and after EndDrawing print the color buffer (rlCopyFramebuffer).
 * - GetTime: an example's own GetTime() calls read the scripted clock, as
 *   raylib's do in this build (tools/reference/input_clock.h: the platform's
 *   definition is renamed rlPlatformGetTime, which nothing calls).
 */
#ifndef JONLIB_EXAMPLE_DRIVER_H
#define JONLIB_EXAMPLE_DRIVER_H

#define InitWindow JonlibExampleInitWindow
#define WindowShouldClose JonlibExampleWindowShouldClose
#define BeginDrawing JonlibExampleBeginDrawing
#define EndDrawing JonlibExampleEndDrawing

double JonlibProbeTime(void);
#define JONLIB_EXAMPLE_CLOCK_CAT(a, b) a ## b
#define JONLIB_EXAMPLE_CLOCK_PICK(x) JONLIB_EXAMPLE_CLOCK_CAT(JONLIB_EXAMPLE_CLOCK_, x)
#define JONLIB_EXAMPLE_CLOCK_void rlPlatformGetTime(void)
#define JONLIB_EXAMPLE_CLOCK_ JonlibProbeTime()
#define GetTime(...) JONLIB_EXAMPLE_CLOCK_PICK(__VA_ARGS__)

#endif
