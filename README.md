# Jonlib

[![Checks](https://github.com/jonathanperis/jonlib/actions/workflows/checks.yml/badge.svg)](https://github.com/jonathanperis/jonlib/actions/workflows/checks.yml)
[![Conformance](https://github.com/jonathanperis/jonlib/actions/workflows/conformance.yml/badge.svg)](https://github.com/jonathanperis/jonlib/actions/workflows/conformance.yml)
[![License: zlib](https://img.shields.io/badge/license-zlib-blue.svg)](LICENSE)

**An independent graphics and game-programming library written in Bend 2,
working toward 100% raylib 6.0 parity.**

The [master plan](docs/MASTER-PLAN.md) defines the full target, implementation
phases and completion gates. The [API progression dashboard](docs/PROGRESS.md)
maps every public release-header API and supporting declaration to a work
package, Bend target, dependencies and verification status. Current limited
profiles remain explicitly partial.

The library is Bend source throughout. It runs headless: windows, input,
frames and audio are values a program threads through its loop, drawn by a
port of raylib's software renderer. Pinned, unmodified raylib is the
reference: each gate runs it natively and compares results exactly, and
every ported upstream example is replayed frame by frame against the
native one.

## Modules

- **Jonlib** (`jonlib.bend`) ports raylib's core geometry/image/runtime surface.
- **Jonmath** (`jonmath.bend`) ports raymath and owns shared vector/matrix types.

Port names follow `ray<suffix>` → `jon<suffix>` (raygui's port is Jongui,
`jongui.bend`). See [module names and import migration](docs/MODULES.md).

```bend
import Base
import ./jonlib.bend as J
import ./jonmath.bend as M
```

## What works today

Everything below is a **partial, scoped profile** compared exactly with pinned
raylib; each API's domain and gaps are in [`api/progress.json`](api/progress.json)
and the [progress dashboard](docs/PROGRESS.md). At the time of writing
(2026-10-12) the ledger marks 582 of raylib.h's 600 functions, all 146 of
raymath.h's, 142 of rlgl.h's 163 and all of rcamera.h's 12 and rgestures.h's
10 as partial, and none as complete (no API is complete before the platform
phase); the dashboard always has the current counts. 202 of raylib's 212
examples are ported ([EXAMPLES.md](docs/EXAMPLES.md)); three of those ports
refuse every frame, because the native example is undefined behavior in C.

- **Images** ([API](docs/API.md)): owned `Surface` creation in any raylib pixel format, pixel access and
  copies; clipped pixels, rectangles, circles, lines, triangles, fans/strips and
  outlines; image composition with tint/alpha and source/destination clipping;
  crop, extract, nearest and [filtered resize](docs/RESAMPLING.md), canvas/POT,
  flips and rotations; color/alpha transforms, palettes and channels;
  gradients, checkerboards, noise, cellular and Perlin generation;
  [mipmaps](docs/MIPMAPS.md), [Gaussian blur](docs/BLUR.md) and
  [kernel convolution](docs/CONVOLUTION.md).
- **Pixel formats**: one `Surface` image type for raylib pixel formats 1..13
  ([FORMATS.md](docs/FORMATS.md), [R32.md](docs/R32.md),
  [FLOAT-RGB.md](docs/FLOAT-RGB.md), [FLOAT-FORMATS.md](docs/FLOAT-FORMATS.md)),
  with packed pixel access and dithering
  ([PIXELS.md](docs/PIXELS.md)).
- **Codecs and files** ([CODECS.md](docs/CODECS.md)): decoding QOI, DDS
  (uncompressed), BMP, TGA, PGM/PPM, PNG, PSD, Softimage PIC, GIF (first frame and
  animations) and Radiance HDR from memory or bounded files, with format-preserving variants
  ([IMAGE-FILES.md](docs/IMAGE-FILES.md)); export to QOI, BMP, TGA, PNG, RAW and C
  source ([IMAGE-EXPORT.md](docs/IMAGE-EXPORT.md), [IMAGE-CODE.md](docs/IMAGE-CODE.md)),
  with typed errors and owner-preserving rejection before a file is opened.
- **Data utilities**: raw DEFLATE decoding and quality-8 compression
  ([DEFLATE.md](docs/DEFLATE.md), [COMPRESSION.md](docs/COMPRESSION.md)),
  [Base64](docs/BASE64.md), [CRC32/MD5](docs/CHECKSUMS.md) and [SHA-1/SHA-256](docs/SHA.md);
  path utilities and file data/text IO ([FILES.md](docs/FILES.md)).
- **Jonmath** ([MATH.md](docs/MATH.md)): scalar helpers, Vector2/3/4, matrices and
  quaternions with exact reference arithmetic order, explicit numerical profiles
  for libm-dependent results ([ANGLES.md](docs/ANGLES.md)), 2D/3D
  [collisions](docs/COLLISION.md), [splines](docs/SPLINES.md) and owned
  [random streams](docs/RANDOM.md).
- **Window, input and frames** ([DRIVER.md](docs/DRIVER.md),
  [INPUT.md](docs/INPUT.md), [FRAME.md](docs/FRAME.md)): raylib's core state
  with an explicit clock, keyboard, mouse, gamepad, touch and gestures,
  automation events, and the frame loop on a memory platform.
- **Drawing** ([RLGL.md](docs/RLGL.md), [TEXTURES.md](docs/TEXTURES.md),
  [FONTS.md](docs/FONTS.md), [TEXT.md](docs/TEXT.md)): rlgl's matrices and
  immediate mode over a port of the software renderer; 2D shapes and
  splines, textures and render textures, bitmap and TrueType fonts, text.
- **3D** ([MODELS.md](docs/MODELS.md), [CAMERA.md](docs/CAMERA.md),
  [SHADERS.md](docs/SHADERS.md), [VR.md](docs/VR.md)): meshes and their
  generators, models and animations from OBJ, glTF/GLB, VOX, IQM and M3D
  files, materials, cameras, shader uniforms and the VR stereo
  configuration (shaders and stereo change nothing on the software
  renderer, as in raylib).
- **Audio** ([AUDIO.md](docs/AUDIO.md)): WAV and QOA waves, `WaveFormat`, the
  audio device's state, sounds, aliases and audio streams, a mixer whose
  device callbacks match raylib's sample for sample, pitched playback and
  streams of any format, stream callbacks and audio processors included,
  music streams over WAV and QOA files, and a clock that makes those
  callbacks from the program's time.
- **Jongui** ([GUI.md](docs/GUI.md)): raygui's controls.
- **Execution**: native CPU, JavaScript and (with the declared compiler overlay)
  forced Metal; see [VERIFICATION.md](docs/VERIFICATION.md).

Not yet there: music from OGG, FLAC, XM and MOD files (WAV, QOA and MP3
music plays); sounds and waves from MP3 files; a host window, input devices and audio output
(everything runs headless); images beyond 4096 pixels on a side; directory
listing. macOS is off the merge path for now and owes a full validation. The
[master plan](docs/MASTER-PLAN.md) and [HANDOFF.md](docs/HANDOFF.md) order
that work.

## Requirements

Use existing installations of Python 3.12+, Bun 1.3.12, CMake (3.25+), and clang.
The local verification commands below do not install tools or download dependencies.
GitHub Actions provisions its own pinned dependencies on hosted runners.

The harness requires these base revisions. Bend additionally needs the exact
[declared compiler overlay](patches/README.md); raylib remains unmodified:

| Dependency | Revision |
|---|---|
| Bend 2.0.27 + Jonlib Metal overlay | `b7ebee9217c8813067e200b0c0c9153a3be31c5e` |
| raylib 6.0 | `dbc56a87da87d973a9c5baa4e7438a9d20121d28` |

Keep the dependency checkouts wherever you prefer. From Jonlib's repository root,
set these variables to their absolute paths (replace the example values):

```sh
export BEND_SOURCE="/path/to/bend"
export RAYLIB_SOURCE="/path/to/raylib"
```

The commands below pass these paths explicitly. [`toolchain.json`](toolchain.json)
records the base commits, patch hash and exact resulting compiler-file hashes.
Apply the overlay once to a checkout already at the pinned Bend revision:

```sh
git -C "$BEND_SOURCE" apply --check "$PWD/patches/bend-metal-dispatch.patch"
git -C "$BEND_SOURCE" apply "$PWD/patches/bend-metal-dispatch.patch"
```

Verification never patches or updates the checkout itself. An unmodified
installed Bend 2.0.27 is not equivalent to this declared source toolchain.

## Verify

From the repository root:

```sh
python3 tools/check_project.py
python3 -m unittest discover -s tests -v
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --plan
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only conformance
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --shard 1/1
```

[`tools/gates.json`](tools/gates.json) lists every gate: the main differential
corpus (`tools/conformance.py`, which also checks contracts, examples, the proof
and the API inventory), focused probes per API family, the resize gate, the
compiler-overlay regressions and diagnostic records. Each compares Jonlib with
the pinned raylib reference on native CPU (one and two threads) and JavaScript;
empty suites, missing outputs and mismatches fail. [CI.md](docs/CI.md) describes
how GitHub Actions shards the gates on Ubuntu and macOS, and
[VERIFICATION.md](docs/VERIFICATION.md) what a pass does and does not establish.

Forced-GPU runs (`--gpu` on `tools/conformance.py`, `tools/verify_bend.py` and the
probes) fail rather than fall back to CPU. They run locally on supported Apple
hardware; hosted CI does not claim GPU validation. Stock Bend's failure and the
compiler fix are documented in [the investigation](docs/METAL-INVESTIGATION.md).

## Follow the full parity plan

- [Progress dashboard and next steps](docs/PROGRESS.md)
- [Every core API](docs/api/raylib.md), [raymath](docs/api/raymath.md),
  [rlgl](docs/api/rlgl.md), [camera](docs/api/rcamera.md),
  [gestures](docs/api/rgestures.md), [configuration](docs/api/config.md)
- [How to update and verify progress](docs/API-TRACKING.md)

```sh
python3 tools/api_plan.py report
python3 tools/api_plan.py show raylib:function:ImageResize
```

## Run the headless example

```sh
mkdir -p .build
BEND_NO_TELEMETRY=1 bun "$BEND_SOURCE/bend2/main.ts" examples/headless.bend -o .build/headless
./.build/headless
```

This writes `.build/headless.ppm`: the rectangle/circle regression scene, rendered
by Jonlib. It opens no window. The `conformance` gate checks its RGB values
against raylib's actual image output.

The second example combines filled/outlined triangles, a line and a tinted image:

```sh
BEND_NO_TELEMETRY=1 bun "$BEND_SOURCE/bend2/main.ts" examples/composite.bend -o .build/composite
./.build/composite
```

It writes `.build/composite.ppm`; all 3,072 RGB pixels are compared with raylib.

![Composite example output](docs/images/composite.png)

The PNG above is a documentation preview converted from the verified PPM output.

The transformation example crops and enlarges pixel art with `ImageResizeNN` semantics:

```sh
BEND_NO_TELEMETRY=1 bun "$BEND_SOURCE/bend2/main.ts" examples/transforms.bend -o .build/transforms
./.build/transforms
```

It writes `.build/transforms.ppm`. Default filtered resize is available separately
as `Surface.resize`: [resampling status and precision evidence](docs/RESAMPLING.md).

![Crop and nearest-neighbor example](docs/images/transforms.png)

This is a documentation PNG preview of the verified PPM output.

The QOI example performs a real file export/load round trip:

```sh
BEND_NO_TELEMETRY=1 bun "$BEND_SOURCE/bend2/main.ts" examples/qoi_roundtrip.bend -o .build/qoi-roundtrip
./.build/qoi-roundtrip
```

It writes `.build/qoi-roundtrip.qoi` and prints the loaded dimensions/pixels.
The harness checks its exact bytes against actual raylib `ExportImage` and runs
file/decode error checks. See [CODECS.md](docs/CODECS.md) and [MATH.md](docs/MATH.md).

## Run a raylib example in a window

Ported raylib examples (`core_basic_window`, `core_input_keys`,
`core_input_mouse`, `core_2d_camera`, `shapes_logo_raylib`,
`textures_logo_raylib`) open a Base window from a desktop session:

```sh
BEND_NO_TELEMETRY=1 bun "$BEND_SOURCE/bend2/main.ts" examples/core_input_keys.bend -o .build/core_input_keys
./.build/core_input_keys            # arrow keys move the ball; Escape or the close button quits
```

The `examples` gate replays the same programs headless against the unmodified
raylib example sources, frame by frame and byte for byte. See
[DRIVER.md](docs/DRIVER.md) for the driver, the key table and the gaps.

## Ownership and compatibility

Drawing returns the updated `Surface`; the old value is consumed. Reads return
the surface alongside an optional pixel. Images are up to 4096×4096 in pixel
formats 1..13 (operations follow raylib per format) and bounded integral coordinates represented as F32. See the API
document for the vector variants, exact domains, ownership returns and reference
edge behavior. Full image drawing, formats and platform coverage remain open work.

Matching CPU `ImageDraw*` operations does not establish GPU `Draw*` behavior,
performance parity, platform parity, or full raylib compatibility.

## License and credits

Jonlib's original code uses the [zlib license](LICENSE). Adapted raylib algorithms
retain their notices in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[LICENSES/raylib.txt](LICENSES/raylib.txt).
The separately identified Bend compiler patch is Apache-2.0, with the original
license retained in [LICENSES/bend.txt](LICENSES/bend.txt).

Inspired by raylib, created by Ramon Santamaria and contributors. Uses Bend 2,
created by HigherOrderCO and contributors. Jonlib is not affiliated with or
endorsed by either project.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, test expectations, CI and bug reports.
