# Jonlib

[![Checks](https://github.com/jonathanperis/jonlib/actions/workflows/checks.yml/badge.svg)](https://github.com/jonathanperis/jonlib/actions/workflows/checks.yml)
[![Conformance](https://github.com/jonathanperis/jonlib/actions/workflows/conformance.yml/badge.svg)](https://github.com/jonathanperis/jonlib/actions/workflows/conformance.yml)
[![License: zlib](https://img.shields.io/badge/license-zlib-blue.svg)](LICENSE)

**An independent graphics and game-programming library written in Bend 2,
working toward raylib compatibility.**

The first implementation is a headless, owned RGBA8 image library. Its drawing
algorithms are Bend source. A separate C executable runs pinned raylib as a
differential test reference.

## Implemented

- Packed RGBA colors and integer alpha blending.
- Image creation, clear, pixel access and independent copies.
- Clipped pixel/rectangle drawing and raylib-compatible midpoint circles.
- Horizontal and vertical flips.
- Conversion to Bend's `Base.Image` quadtree.
- P3 PPM encoding and file export through Base IO.
- Exact full-pixel differential testing, deterministic seeded scenarios, a
  dimension-preservation law, and ownership/adapter contract checks.

See the [API](docs/API.md), [compatibility ledger](docs/COMPATIBILITY.md),
[verification record](docs/VERIFICATION.md), and [roadmap](docs/ROADMAP.md).
This is an early library: desktop interaction,
textures/fonts/codecs, audio, 3D, and broader platform support remain future work.

## Requirements

Use existing installations of Python 3.12+, Bun 1.3.12, CMake (3.25+), and clang.
The local verification commands below do not install tools or download dependencies.
GitHub Actions provisions its own pinned dependencies on hosted runners.

The harness requires clean local checkouts at these pinned revisions:

| Dependency | Revision |
|---|---|
| Bend 2.0.27 | `ac0ddb7bf9b3255b23126886698b43a176eed8ca` |
| raylib 6.0 | `dbc56a87da87d973a9c5baa4e7438a9d20121d28` |

Defaults are `~/Projetos/bendlang/bend` and `~/Projetos/raysan5/raylib`; override
them with `--bend-source` and `--raylib-source`. The toolchain is recorded in
[`toolchain.json`](toolchain.json). A locally installed compatible `bend` can be
used for manual examples; the reproducible harness uses Bun and the pinned source.

## Verify

From the repository root:

```sh
python3 -m unittest discover -s tests -v
python3 tools/conformance.py
```

The harness builds raylib's headless Memory backend under `.build/`, generates
both runners from [`tests/fixtures/images.json`](tests/fixtures/images.json),
and compares every packed RGBA pixel on native CPU (one/two threads) and JS.
It also checks the proof, owned copies, bounds, Base.Image conversion, and the
headless PPM example. Empty suites, missing outputs and mismatches fail.

```sh
python3 tools/conformance.py --gpu
```

The optional GPU command forces device execution and fails if the device or
results are unavailable. **The complete Metal suite currently exposes an
unresolved failure on the tested M1/toolchain combination.** See
[the investigation](docs/METAL-INVESTIGATION.md). Successful smaller GPU probes
do not count as a passing complete GPU gate.

Evidence is written to `.build/conformance.json`, with source/input hashes,
toolchain, host and per-lane results. Generated programs and complete reference/
candidate pixel outputs remain beside it. Each run initially marks the report
failed, so an unsuccessful rerun cannot leave an old success as its result.
The run also inventories all **600 public raylib.h functions** into
`.build/api-inventory.json`, combining their pinned signatures with
[`docs/api-map.json`](docs/api-map.json). Mapped image operations cover only the
declared profile; the remaining APIs are explicitly marked not implemented.

## Run the headless example

```sh
mkdir -p .build
BEND_NO_TELEMETRY=1 bun ~/Projetos/bendlang/bend/bend2/main.ts examples/headless.bend -o .build/headless
./.build/headless
```

This writes `.build/headless.ppm`: the rectangle/circle regression scene, rendered
by Jonlib. It opens no window. The conformance command checks its RGB values
against raylib's actual image output.

## Ownership and compatibility

Drawing returns the updated `Surface`; the old value is consumed. Reads return
the surface alongside an optional pixel. The initial profile uses RGBA8 images
up to 4096×4096 and bounded integral coordinates represented as F32. See the API
document for exact domains and raylib's degenerate-rectangle behavior.

Matching CPU `ImageDraw*` operations does not establish GPU `Draw*` behavior,
performance parity, platform parity, or full raylib compatibility.

## License and credits

Jonlib's original code uses the [zlib license](LICENSE). Adapted raylib algorithms
retain their notices in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[LICENSES/raylib.txt](LICENSES/raylib.txt).

Inspired by raylib, created by Ramon Santamaria and contributors. Uses Bend 2,
created by HigherOrderCO and contributors. Jonlib is not affiliated with or
endorsed by either project.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, test expectations, CI and bug reports.
