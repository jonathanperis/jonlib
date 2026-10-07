# Spline point profiles

Pure point queries return `Vector2` values:

| API | Reference behavior |
|---|---|
| `Spline.linear(start, end, t)` | `start*(1-t)+end*t` in the original order. |
| `Spline.basis(first, second, third, fourth, t)` | B-spline coefficients divided by six, then the reference Horner evaluation. |
| `Spline.catmull_rom(first, second, third, fourth, t)` | Original four Catmull-Rom weights and final half-scale. |
| `Spline.bezier_quad(start, control, end, t)` | Quadratic weights and reference three-term accumulation. |

Each API has an `_for(reference, ...)` variant accepting `M.Contraction`:
`M.Fused{}` or `M.Uncontracted{}`. Convenience calls select uncontracted
arithmetic. The linked macOS arm64 reference uses fused multiply-add and Linux
x86_64 the uncontracted profile; the harness selects `M.Fused{}` or
`M.Uncontracted{}` from the same host declaration as the collision
arithmetic ([COLLISION.md](COLLISION.md)). The exact formulas remain separate
from algebraically equivalent vector interpolation helpers.

The initial profile covers coordinates in -32767..32767 and t in 0..1, with
finite normal/zero intermediate values. Exceptional/subnormal inputs,
extrapolation, other compiler contraction choices and full integration/target/
performance coverage remain gaps.

## How it is verified

| Gate | Tool | Compares |
|---|---|---|
| `conformance` | `tools/conformance.py` | both output components of the spline fixtures vs the linked raylib, with the host's arithmetic profile |
| `spline` | `tools/spline_probe.py` | every point API on endpoints, non-dyadic coefficients, signed zero and seeded inputs vs linked raylib, with the host's arithmetic profile |

`tools/spline_probe.py --uncontracted-control` instead compiles the unchanged
pinned spline functions from `rshapes.c` with `FP_CONTRACT OFF` and checks
`M.Uncontracted{}` on any host:

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only spline
python3 tools/spline_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --uncontracted-control
```

## Cubic Bezier blocker

`GetSplinePointBezierCubic` is **blocked**. The pinned
[cubic Bezier implementation](https://github.com/raysan5/raylib/blob/dbc56a87da87d973a9c5baa4e7438a9d20121d28/src/rshapes.c#L2232)
uses native `powf(t,3)`, and a binary64 cube rounded to F32 is not a substitute:
it differs from Apple's native `powf` on sampled finite inputs, observably through
the point API. Retained counterexample: first three control points `(0,0)`, final
point `(1,0)`, t = `0x1.940af8p-2`:

- Native point X bits: `3d7b9e4d`
- Double-cube substitute bits: `3d7b9e4e`

The `spline` probe records this input in its results (`cubic_power_diagnostic`)
as a diagnostic alongside the implemented gates. Cubic Bezier is not counted as
an implementation; no expectation or tolerance is relaxed.
