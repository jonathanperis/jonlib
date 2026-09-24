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
  compositing/integer alpha-blending algorithms in `jonlib.bend` are
  translated/adapted from `src/rtextures.c`, with Bend ownership and bounded
  recursion. These are modified implementations, not original raylib source.
- Reference testing: `tools/conformance.py` builds a separate raylib executable
  from a locally supplied checkout. Raylib is not linked into the Jonlib runner.

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
