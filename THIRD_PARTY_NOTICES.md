# Third-party notices

Jonlib is an independent library written in Bend 2, inspired by raylib's design.
It is not affiliated with or endorsed by raylib or Bend's maintainers.

## raylib

- Author: Ramon Santamaria (@raysan5) and contributors.
- Version: 6.0, commit `dbc56a87da87d973a9c5baa4e7438a9d20121d28`.
- Source: <https://github.com/raysan5/raylib>.
- License: zlib; retained verbatim in [LICENSES/raylib.txt](LICENSES/raylib.txt).
- Adaptations: the rectangle clipping/degenerate behavior, midpoint-circle,
  fixed-point line and edge-stepped triangle rasterization, and image
  compositing/integer alpha-blending, crop/extraction and fixed-point nearest
  resize algorithms in `jonlib.bend` are
  translated/adapted from `src/rtextures.c`, with Bend ownership and bounded
  recursion. These are modified implementations, not original raylib source.
- Subsequent adaptations include scaled/fractional image composition, vector
  drawing wrappers, outlines, thick lines, fan/strip and vertex-colored triangles,
  color/alpha transforms, checkerboards and quarter-turn rotations from
  `rtextures.c`, plus the documented scalar/Vector2 operations from `raymath.h`.
  Their scoped contracts and reference evidence are recorded in `docs/`.
- Reference testing: `tools/conformance.py` builds a separate raylib executable
  from a locally supplied checkout. Raylib is not linked into the Jonlib runner.
- API documentation: `api/reference.json`, generated `api/ledger.json` and
  `docs/api/` contain extracted/adapted declarations, fields and constant values
  from the pinned `raylib.h`, `raymath.h`, `rlgl.h`, `rcamera.h`, `rgestures.h`
  and `config.h`. These are Jonlib planning documents, not original upstream
  headers. Upstream authorship and the zlib notice above apply to those excerpts.

## stb_image_resize2

- Version 2.18, as vendored by the pinned raylib commit above; header authors
  Jeff Roberts (v2) and Jorge L Rodriguez; MIT notice copyright Sean Barrett.
- Source: <https://github.com/nothings/stb> and raylib's
  `src/external/stb_image_resize2.h` at the pinned revision.
- Jonlib selects the MIT alternative. The complete upstream dual-license notice
  is retained in [LICENSES/stb_image_resize2.txt](LICENSES/stb_image_resize2.txt).
- `src/resample.bend` adapts the default filters, rational phases, coefficient
  normalization/folding/packing, alpha pipeline, operation order and pass-cost
  table to owned Bend values. These are altered implementations. Original
  Jonlib code, including `src/resize_numeric.bend`, remains under zlib.
- `tools/resize_conformance.py` inserts observation-only logging into a local
  diagnostic copy of the pinned header. Kernel and whole-image reference probes
  additionally execute the unmodified upstream header and raylib library.

## QOI

`src/qoi.bend` is an altered Bend adaptation of the codec in raylib's pinned
`src/external/qoi.h`, by Dominic Szablewski. It uses owned arrays and immutable
input bytes, bounds allocations to the Surface profile, normalizes RGB output
to RGBA8, implements reference QOI encoding and reports malformed streams explicitly. QOI's MIT notice and license
are retained in [LICENSES/qoi.txt](LICENSES/qoi.txt). The standalone C implementation
is used only by reference tooling; it is not linked into Jonlib's implementation.

## Arm numerical routines

The GNU-reference polynomial in `src/trig.bend` and its independent C control
in `tools/trig_probe.py` adapt `math/sincosf.h` and `math/sincosf_data.c` from
[Arm optimized-routines at 47597821aaa52e9c055caf1ecf8f3aecfd751cd9](https://github.com/ARM-software/optimized-routines/tree/47597821aaa52e9c055caf1ecf8f3aecfd751cd9).
These are altered Bend/tooling implementations, limited to the documented
gradient profile. Jonlib selects the upstream MIT alternative; source copyright
notices and the selected license are retained in [LICENSES/arm-math.txt](LICENSES/arm-math.txt).

## Bend

Jonlib uses the Bend language and Base library, provided by HigherOrderCO and
contributors under Apache-2.0. No Bend3D implementation or demo assets are vendored.

The compiler overlay in `patches/bend-metal-dispatch.patch` adapts Bend's
`bend2/comp.ts` and includes an original regression test and local-spec ignore
entry. It is based on `b7ebee9217c8813067e200b0c0c9153a3be31c5e` and is distributed
under **Apache-2.0**, including its modifications. The original copyright is
2026 HigherOrderCO; the modifications were authored for Jonathan Peris's Jonlib
project in 2026. The modified compiler carries a change notice.

The upstream license is retained verbatim in [LICENSES/bend.txt](LICENSES/bend.txt).
No upstream NOTICE file was present at the base revision. This overlay is not
an upstream-approved Bend release. See [patches/README.md](patches/README.md) for
provenance and application instructions. Distributions containing Bend runtime
artifacts must also retain their applicable Apache-2.0 notices.
