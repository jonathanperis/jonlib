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

## Cubic Bezier

`Spline.bezier_cubic_for(contraction, libm, start, start_control, end_control,
end, t) -> Maybe<Vector2>` follows the pinned
[cubic Bezier implementation](https://github.com/raysan5/raylib/blob/dbc56a87da87d973a9c5baa4e7438a9d20121d28/src/rshapes.c#L2232):
weights `powf(1-t, 3)`, `3*powf(1-t, 2)*t`, `3*(1-t)*powf(t, 2)` and
`powf(t, 3)`, then the four-term accumulation under the given contraction.
C compilers fold `powf(x, 2)` into `x*x` (the linked arm64 object calls `powf`
only for the two cubes, and the probe checks that the host clang does the
same), so the squares are plain products; the cubes come from the libm
profile (`M.Libm.pow`):

- `Glibc239Libm{}`: glibc 2.39's x86_64 `powf` (Arm optimized-routines,
  `TOINT_INTRINSICS` 0), `src/power.bend`, for exponents 2 and 3 and x in
  [-0, 1], every binary64 step through the checked helpers of
  [BINARY64.md](BINARY64.md). Exhaustively, on all 1,065,353,217 x in [0, 1],
  the host `powf(x, 2)` and `powf(x, 3)` of Ubuntu 24.04 x86_64 (glibc 2.39,
  FMA build selected) equal this algorithm, with or without contraction; they
  differ from `x*x` on 386,499 inputs and from the rounded binary64 cube on
  238,337, so neither product is a substitute.
- `AppleLibm{}` and `Glibc241Libm{}`: no `powf` kernel (`None`). Apple's
  `powf(t, 3)` differs from the binary64 cube too (retained counterexample:
  control points `(0,0)`, `(0,0)`, `(0,0)`, `(1,0)`, t = `0x1.940af8p-2`,
  native X `3d7b9e4d`, cube `3d7b9e4e`), and its algorithm is not published.

`None` also when t is outside [-0, 1], including NaN.

`tools/spline_cubic_probe.py` (gate `spline-cubic`) compiles the unchanged
pinned function with `powf` replaced by a C model of that algorithm,
uncontracted on every host and contracted on arm64 for `M.Fused{}`, and
compares on CPU-1, CPU-2 and JavaScript: the kernel on 7,909 inputs (random,
signed zeros, subnormals, the underflow edges, 400 inputs where `powf` differs
from the products, and refused values) and 726 cubic points (random, the
counterexample, endpoints, tiny t and 1 - tiny, 200 t where `powf` differs
from the products, and refused t), plus `None`
for the other profiles. On a Linux x86_64 glibc 2.39 host the linked raylib
with the host `powf` must print the same rows. The `spline` probe still
records the counterexample (`cubic_power_diagnostic`).

