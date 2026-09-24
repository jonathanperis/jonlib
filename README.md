# Jonlib

[![Checks](https://github.com/jonathanperis/jonlib/actions/workflows/checks.yml/badge.svg)](https://github.com/jonathanperis/jonlib/actions/workflows/checks.yml)
[![Conformance](https://github.com/jonathanperis/jonlib/actions/workflows/conformance.yml/badge.svg)](https://github.com/jonathanperis/jonlib/actions/workflows/conformance.yml)
[![License: zlib](https://img.shields.io/badge/license-zlib-blue.svg)](LICENSE)

**An independent graphics and game-programming library written in Bend 2,
working toward 100% raylib 6.0 parity.**

The [master plan](docs/MASTER-PLAN.md) defines the full target, implementation
phases and completion gates. Current limited profiles remain explicitly partial.

The first implementation is a headless, owned RGBA8 image library. Its drawing
algorithms are Bend source. A separate C executable runs pinned raylib as a
differential test reference.

## Implemented

- Packed RGBA colors and integer alpha blending.
- Image creation, clear, pixel access and independent copies.
- Clipped pixel/rectangle drawing and raylib-compatible midpoint circles.
- Fixed-point lines, vector-line rounding, filled triangles and triangle outlines.
- Unscaled image composition with clipping, tint, alpha and source preservation.
- Horizontal and vertical flips.
- Conversion to Bend's `Base.Image` quadtree.
- P3 PPM encoding and file export through Base IO.
- Exact full-pixel differential testing, deterministic seeded scenarios, a
  dimension-preservation law, and ownership/adapter contract checks.
- Verified native CPU, JavaScript and Metal execution with the declared compiler overlay.

See the [master plan](docs/MASTER-PLAN.md), [API](docs/API.md), [compatibility ledger](docs/COMPATIBILITY.md),
[verification record](docs/VERIFICATION.md), and [roadmap](docs/ROADMAP.md).
This is an early library: desktop interaction,
textures/fonts/codecs, audio, 3D, and broader platform support remain future work.

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

Defaults are `~/Projetos/bendlang/bend` and `~/Projetos/raysan5/raylib`; override
them with `--bend-source` and `--raylib-source`. [`toolchain.json`](toolchain.json)
records the base commits, patch hash and exact resulting compiler-file hashes.
Apply the overlay once to a checkout already at that Bend revision:

```sh
BEND_SOURCE="$HOME/Projetos/bendlang/bend"
git -C "$BEND_SOURCE" apply --check "$PWD/patches/bend-metal-dispatch.patch"
git -C "$BEND_SOURCE" apply "$PWD/patches/bend-metal-dispatch.patch"
```

Verification never patches or updates the checkout itself. An unmodified
installed Bend 2.0.27 is not equivalent to this declared source toolchain.

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
two headless PPM examples. Empty suites, missing outputs and mismatches fail.

```sh
python3 tools/conformance.py --gpu
```

The optional GPU command forces device execution and fails if the device or
results are unavailable. **All 40 scenarios pass on the tested M1 with the
declared overlay**, including every RGBA pixel. Stock Bend's failure and the
compiler fix are documented in [the investigation](docs/METAL-INVESTIGATION.md).
Hosted CI validates CPU/JavaScript; it does not claim GPU validation.

The compiler overlay also has a focused upstream regression runner:

```sh
python3 tools/verify_bend.py
python3 tools/verify_bend.py --gpu
```

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

The second example combines filled/outlined triangles, a line and a tinted image:

```sh
BEND_NO_TELEMETRY=1 bun ~/Projetos/bendlang/bend/bend2/main.ts examples/composite.bend -o .build/composite
./.build/composite
```

It writes `.build/composite.ppm`; all 3,072 RGB pixels are compared with raylib.

![Composite example output](docs/images/composite.png)

The PNG above is a documentation preview converted from the verified PPM output.

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
