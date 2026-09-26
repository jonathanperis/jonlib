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

## Implemented

- Packed RGBA colors and integer alpha blending.
- Image creation, clear, pixel access and independent copies.
- Clipped pixel/rectangle drawing and raylib-compatible midpoint circles.
- Fixed-point lines, vector-line rounding, filled triangles and triangle outlines.
- Unscaled image composition with clipping, tint, alpha and source preservation.
- Checked region extraction/cropping, source-rectangle drawing and exact fixed-point nearest-neighbor resizing.
- Default filtered RGBA8 resize with precision-correct coefficient normalization
  and alpha-aware Catmull-Rom/Mitchell filtering.
- Scaled/source-clipped image composition, including bounded fractional rectangles.
- Vector drawing variants, outlines, thick lines, fans/strips and vertex-colored triangles.
- RGBA8 color/alpha transforms, checkerboards and quarter-turn rotations.
- Alpha bounds/cropping, raw canvas resizing and square gradients.
- Checked general image rotation and power-of-two canvas expansion.
- Source-preserving channel extraction and eleven scoped pure 2D collision queries.
- Vector3 arithmetic, cross/dot products, and bounded sphere/box collision queries.
- Matrix arithmetic/inversion, binary64-input projections, view/rotation constructors, vector transforms and paired-vector orthonormalization.
- Four-component vector arithmetic and immutable float-list exports with checked length laws.
- Normalized/HSV color conversions and quaternion Hamilton-product foundations.
- Owned seeded random streams and reference-exact white-noise images.
- Radial and one-cycle linear gradient profiles with balanced owned-array generation.
- QOI decoding/encoding and real byte-file loading/export, with typed failures.
- BMP 24/32-bit memory decoding and exact RGBA8 V4 export; owned raw image-file IO.
- TGA raw/RLE true-color and grayscale decoding with byte-exact default RLE export.
- Binary PGM/PPM byte-sample decoding with native header and maxval behavior.
- Bounded raw DEFLATE decompression with native empty-block semantics.
- Initial scalar and Vector2 math under an explicit uncontracted-F32 profile.
- Horizontal and vertical flips.
- Conversion to Bend's `Base.Image` quadtree.
- P3 PPM encoding and file export through Base IO.
- Exact full-pixel differential testing, deterministic seeded scenarios, a
  dimension-preservation law, and ownership/adapter contract checks.
- Verified native CPU, JavaScript and Metal execution with the declared compiler overlay.

See the [master plan](docs/MASTER-PLAN.md), [API](docs/API.md), [compatibility ledger](docs/COMPATIBILITY.md),
[verification record](docs/VERIFICATION.md), and [roadmap](docs/ROADMAP.md).
This is an early library: desktop interaction,
textures/fonts, additional codecs, audio, 3D, and broader platform support remain future work.

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
python3 -m unittest discover -s tests -v
python3 tools/conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

The harness builds raylib's headless Memory backend under `.build/`, generates
both runners from [`tests/fixtures/images.json`](tests/fixtures/images.json),
and compares every packed RGBA pixel on native CPU (one/two threads) and JS.
It also checks the proof, owned copies, bounds, Base.Image conversion, and the
three headless PPM examples. Empty suites, missing outputs and mismatches fail.

```sh
python3 tools/conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

The optional GPU command forces device execution and fails if the device or
results are unavailable. **The full current corpus passes on the tested M1 with the
declared overlay**, including every RGBA pixel. Stock Bend's failure and the
compiler fix are documented in [the investigation](docs/METAL-INVESTIGATION.md).
Hosted CI validates CPU/JavaScript; it does not claim GPU validation.

Default filtered resizing also has a dedicated exact-bit/pixel gate:

```sh
python3 tools/resize_conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

It checks normalization, complete filter kernels, all four retained precision
counterexamples and a 529-image corpus including 4096-pixel axis boundaries.
See [resampling status and evidence](docs/RESAMPLING.md).

The compiler overlay also has a focused upstream regression runner:

```sh
python3 tools/verify_bend.py --bend-source "$BEND_SOURCE"
python3 tools/verify_bend.py --bend-source "$BEND_SOURCE" --gpu
```

Gradient arithmetic and measured parallel generation have separate probes:

```sh
python3 tools/trig_probe.py --bend-source "$BEND_SOURCE" --gpu
python3 tools/gradient_bench.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

See [GRADIENTS.md](docs/GRADIENTS.md) for the verified direction range, retained
wider-angle counterexamples and timing scope.

Evidence is written to `.build/conformance.json`, with source/input hashes,
toolchain, host and per-lane results. Generated programs and complete reference/
candidate pixel outputs remain beside it. Each run initially marks the report
failed, so an unsuccessful rerun cannot leave an old success as its result.
The run checks the complete [API ledger](api/ledger.json) against the pinned
headers and exports its **600 public raylib.h functions** into
`.build/api-inventory.json`. Its progress summary comes from the same ledger.
Mapped image operations cover only the declared profile.

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
by Jonlib. It opens no window. The conformance command checks its RGB values
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
