# Third-party notices

Jonlib is an independent library written in Bend 2, inspired by raylib's design.
It is not affiliated with or endorsed by raylib or Bend's maintainers.

## raylib

- Author: Ramon Santamaria (@raysan5) and contributors.
- Version: 6.0, commit `dbc56a87da87d973a9c5baa4e7438a9d20121d28`.
- Source: <https://github.com/raysan5/raylib>.
- License: zlib; retained verbatim in [LICENSES/raylib.txt](LICENSES/raylib.txt).
- Adaptations: the rectangle clipping/degenerate behavior, midpoint-circle
  rasterization and integer alpha-blending algorithms in `jonlib.bend` are
  translated/adapted from `src/rtextures.c`, with Bend ownership and bounded
  recursion. These are modified implementations, not original raylib source.
- Reference testing: `tools/conformance.py` builds a separate raylib executable
  from a locally supplied checkout. Raylib is not linked into the Jonlib runner.

## Bend

Jonlib uses the Bend language and Base library, provided by HigherOrderCO and
contributors under Apache-2.0. The toolchain is an external development/runtime
dependency. No Bend3D implementation or demo assets are vendored here.
Distributions containing Bend runtime artifacts must carry its applicable
license/notices: <https://github.com/bendlang/bend/blob/ac0ddb7bf9b3255b23126886698b43a176eed8ca/LICENSE>.
