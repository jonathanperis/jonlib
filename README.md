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

The first implementation is a headless, owned RGBA8 image library. Its drawing
algorithms are Bend source. A separate C executable runs pinned raylib as a
differential test reference.

## Modules

- **Jonlib** (`jonlib.bend`) ports raylib's core geometry/image/runtime surface.
- **Jonmath** (`jonmath.bend`) ports raymath and owns shared vector/matrix types.

Port names follow `ray<suffix>` → `jon<suffix>` (for example, a future raygui port
is Jongui). See [module names and import migration](docs/MODULES.md).

```bend
import Base
import ./jonlib.bend as J
import ./jonmath.bend as M
```

## What works today

Everything below is a **partial, scoped profile** compared exactly with pinned
raylib; each API's domain and gaps are in [`api/progress.json`](api/progress.json)
and the [progress dashboard](docs/PROGRESS.md). At the time of writing the ledger
marks 117 of raylib.h's 600 functions and 142 of raymath.h's 146 as partial and
none as complete; the dashboard always has the current counts.

- **Images** ([API](docs/API.md)): owned RGBA8 `Surface` creation, pixel access and
  copies; clipped pixels, rectangles, circles, lines, triangles, fans/strips and
  outlines; image composition with tint/alpha and source/destination clipping;
  crop, extract, nearest and [filtered resize](docs/RESAMPLING.md), canvas/POT,
  flips and rotations; color/alpha transforms, palettes and channels;
  gradients, checkerboards, noise, cellular and Perlin generation;
  [mipmaps](docs/MIPMAPS.md), [Gaussian blur](docs/BLUR.md) and
  [kernel convolution](docs/CONVOLUTION.md).
- **Pixel formats**: byte/integer formats 1..8 as `Image.Formatted`
  ([FORMATS.md](docs/FORMATS.md), [R32.md](docs/R32.md)), packed pixel access and
  dithering ([PIXELS.md](docs/PIXELS.md)) and RGB float images
  ([FLOAT-RGB.md](docs/FLOAT-RGB.md)).
- **Codecs and files** ([CODECS.md](docs/CODECS.md)): decoding QOI, BMP, TGA,
  PGM/PPM, PNG, PSD, Softimage PIC, GIF (first frame and animations) and Radiance
  HDR from memory or bounded files, with format-preserving variants
  ([IMAGE-FILES.md](docs/IMAGE-FILES.md)); export to QOI, BMP, TGA, PNG, RAW and C
  source ([IMAGE-EXPORT.md](docs/IMAGE-EXPORT.md), [IMAGE-CODE.md](docs/IMAGE-CODE.md)),
  with typed errors and owner-preserving rejection before a file is opened.
- **Data utilities**: raw DEFLATE decoding and quality-8 compression
  ([DEFLATE.md](docs/DEFLATE.md), [COMPRESSION.md](docs/COMPRESSION.md)),
  [Base64](docs/BASE64.md), [CRC32/MD5](docs/CHECKSUMS.md) and [SHA-1/SHA-256](docs/SHA.md).
- **Jonmath** ([MATH.md](docs/MATH.md)): scalar helpers, Vector2/3/4, matrices and
  quaternions with exact reference arithmetic order, explicit numerical profiles
  for libm-dependent results ([ANGLES.md](docs/ANGLES.md)), 2D/3D
  [collisions](docs/COLLISION.md), [splines](docs/SPLINES.md) and owned
  [random streams](docs/RANDOM.md).
- **Execution**: native CPU, JavaScript and (with the declared compiler overlay)
  forced Metal; see [VERIFICATION.md](docs/VERIFICATION.md).

Not yet started: windows and input, textures and fonts, audio, 3D, shaders and
platforms beyond headless CPU/JS/Metal. The [master plan](docs/MASTER-PLAN.md)
orders that work.

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

## Ownership and compatibility

Drawing returns the updated `Surface`; the old value is consumed. Reads return
the surface alongside an optional pixel. The initial profile uses RGBA8 images
up to 4096×4096 and bounded integral coordinates represented as F32. See the API
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
