# Roadmap

Jonlib aims to offer raylib 6.2's whole public surface (raylib.h, raymath.h,
rlgl.h, rcamera.h, rgestures.h and config.h's options) in Bend 2, with
behavior that is verified against the pinned raylib rather than assumed. This
page states where that stands and what remains. Per-API status is the
[progress dashboard](PROGRESS.md); the rules for recording it are in
[API-TRACKING.md](API-TRACKING.md).

## Where Jonlib is

- **API coverage** (`python3 tools/api_plan.py check`): 1906 catalogued
  declarations and support entries, 1900 of them at least partial. Every
  function of raylib.h (619), raymath.h (146), rlgl.h (163), rcamera.h (12)
  and rgestures.h (10) is partial; six entries are not started (raymath's
  `float * Vector` C++ operators, the `RL_BOOL_TYPE` macros of rlgl.h and
  rgestures.h, and config.h's `SUPPORT_FILEFORMAT_PEP`). No entry is `complete`: completion
  requires every target of [`api/milestones.json`](../api/milestones.json).
- **Modules**: Jonlib, Jonmath, Jongui (raygui), Joneasings, Jonlights and
  the generated Jonlgl, Joncamera and Jongestures ([MODULES.md](MODULES.md)).
- **Examples** (`python3 tools/examples_plan.py check`): all 223 examples of
  raylib 6.2 have a Bend version that the `examples-*` gates replay frame by
  frame against the native example ([EXAMPLES.md](EXAMPLES.md)).
- **Headless by design**: windows, input, frames and audio are values a
  program threads through its loop; drawing goes through a Bend adaptation of
  raylib's software renderer. A Base window driver presents frames on a
  desktop ([DRIVER.md](DRIVER.md)).

## How behavior is verified

Each gate in [`tools/gates.json`](../tools/gates.json) runs the pinned raylib
natively (`PLATFORM=Memory`) and the Bend candidate on native CPU (one and
two threads) and JavaScript, and compares results exactly: pixels, bytes,
float bit patterns, typed errors and returned owners. Host-dependent results
(libm, multiply-add contraction) are explicit, named profiles. Undefined C
behavior is refused, not reproduced. Laws in `LAWS.bend` are proved by
`PROOF.bend`. Expectations are never loosened to make a mismatch pass. What a
passing gate does and does not establish is in
[VERIFICATION.md](VERIFICATION.md); how CI runs the gates in [CI.md](CI.md).

## What remains

1. **The macOS validation** ([MACOS-VALIDATION.md](MACOS-VALIDATION.md)):
   turn macOS back on in CI and run every gate on a Mac against raylib 6.2.
2. **Wider domains and gaps** recorded per API in
   [`api/progress.json`](../api/progress.json): 2284 open gaps on 1309
   entries. C-to-Bend mappings with no observable difference (enums as U32
   constants, macros as functions, pointer ABI, explicit state) are recorded
   apart as [language adaptations](API-TRACKING.md#language-adaptations)
   and are not gaps. By theme (keyword-grouped, approximate):

   | Theme | Gaps | Example |
   |---|---:|---|
   | `Targets:` lanes not verified | 829 | the Metal lane; macOS for OS-effect functions |
   | Libm and contraction profiles | 351 | AppleLibm `sinf`/`cosf` outside whole degrees; fused (FMA) builds |
   | Untagged "full target/performance coverage" | 324 | `Full target/performance coverage` |
   | `Undefined native behavior:` (documented contract) | 116 | NaN or out-of-range C int conversions mark the frame undefined |
   | `Integration:` facilities missing from Base | 107 | window state, monitors, clipboard, cursor, gamepad, touch |
   | `Performance:` | 96 | renderer about 23x slower than native rlsw; not measured |
   | Refusals of raylib's out-of-bounds or freed-memory reads | 86 | an unready audio device leaves the state as it is |
   | Renderer state not modeled | 79 | shaders, GPU buffers, bones, scissor slices |
   | Audio device model | 70 | no device thread or host device |
   | Exceptional/subnormal/NaN domains | 64 | NaN sign and payload are not reproduced |
   | Formats and size limits | 96 | FLAC, glTF/M3D subsets, mipmaps, images beyond 4096 |
   | Files, runtime wiring, trace log, other | 66 | non-ASCII byte paths; gestures from the driver |

   Libm profiles that cannot be reproduced from published sources (Apple's
   `tan`, `asinf`, `acosf`) stay refusals.
3. **Platforms**: Jonlib targets Linux and macOS (decided 2026-10-21): the
   headless memory platform with the software renderer on both, and their
   desktops through Bend Base ([`api/milestones.json`](../api/milestones.json)
   `targets`). raylib's other platforms (Windows, the BSDs, Raspberry Pi and
   DRM, Android, the browser, Haiku, SDL/RGFW) and its OpenGL/GLES backends
   are out of scope and recorded as such (`out_of_scope_targets`).
4. **Runtime facilities** that Bend's Base lacks today, added to Bend's
   platform boundary rather than to Jonlib: window state, resize,
   fullscreen and DPI, monitors, clipboard and cursor modes, text input,
   gamepad and touch events, a sub-millisecond clock, audio output with
   backpressure. Until each lands, the matching functions stay partial with
   that gap. Each compiler or runtime change needs its own regression plus
   the affected Jonlib scenarios, as the declared compiler overlay's do
   ([METAL-INVESTIGATION.md](METAL-INVESTIGATION.md),
   [patches/README.md](../patches/README.md)).
5. **Performance**: the renderer and decoders are correctness-first and
   single-threaded in places; representative frame-time, memory and audio
   latency measurements against raylib are still to be made.

## Delivery phases

The work packages of [`api/milestones.json`](../api/milestones.json) carry a
phase number, shown on the [dashboard](PROGRESS.md). The phases express
dependency order, not separate stages:

| Phase | Scope |
|---|---|
| 0 | Reference, toolchain, types and language mappings |
| 1 | Numerics, Jonmath, files and memory, pixels, CPU images, codecs, collisions |
| 2 | Window, input, timing, 2D shapes, textures and render targets |
| 3 | Text utilities and fonts |
| 4 | Audio formats, devices and streams |
| 5 | Models, materials, animation, cameras and VR |
| 6 | rlgl, shaders and low-level graphics compatibility |
| 7 | Configuration and complete platform/backend validation |

## Design decisions

- **Explicit state.** raylib's globals (`CORE`, `RLGL`, the audio device, the
  trace log and file callbacks) are values passed to and returned from the
  operations that use them, recorded as language adaptations
  ([API.md](API.md)).
- **Enumerations** are zero-argument U32 functions with raylib's spelling
  under the enum's name (`PixelFormat.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8()`).
- **Compressed and multi-level images** are `Image.Stored` (raylib's Image
  fields with the complete level chain), separate from `Surface`, so Surface
  operations reject them statically ([IMAGE-FILES.md](IMAGE-FILES.md)).
- **Host math libraries.** Results that depend on libm follow glibc 2.39
  (fdlibm-derived) or 2.41 (CORE-MATH) profiles, compared on Linux; Apple's
  libm is not reproducible from published sources, so Apple profiles refuse
  where they cannot be reproduced ([ANGLES.md](ANGLES.md)).
- **LGPL isolation.** glibc's LGPL-2.1+ `tan` and `asinf` are adapted only in
  `src/lgpl/`, with their full notices
  ([THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)); every other Jonlib
  file is zlib.
- **Scope changes** (dropping an API as not applicable) are not made merely
  because something is hard in Bend; they are an explicit maintainer decision.
