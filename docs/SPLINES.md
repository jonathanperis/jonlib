# Spline point profiles

Pure point queries return `Vector2` values:

| API | Reference behavior |
|---|---|
| `Spline.linear(start, end, t)` | `start*(1-t)+end*t` in the original order. |
| `Spline.basis(first, second, third, fourth, t)` | B-spline coefficients divided by six, then the reference Horner evaluation. |
| `Spline.catmull_rom(first, second, third, fourth, t)` | Original four Catmull-Rom weights and final half-scale. |
| `Spline.bezier_quad(start, control, end, t)` | Quadratic weights and reference three-term accumulation. |

Each API has an `_for(reference, ...)` variant accepting `Spline.Reference`:
`FusedSpline{}` or `UncontractedSpline{}`. Convenience calls select uncontracted
arithmetic. The exercised linked macOS arm64 reference uses fused multiply-add;
hosted Linux/x86_64 uses the uncontracted profile. The exact formulas remain
separate from algebraically equivalent vector interpolation helpers.

The initial profile covers coordinates in -32767..32767 and t in 0..1, with
finite normal/zero intermediate values. Exceptional/subnormal inputs,
extrapolation, other compiler contraction choices and full integration/target/
performance coverage remain gaps.

Both output components are compared with the actual linked reference in the
shared corpus. A dedicated probe checks 512 complete points per arithmetic
profile, including endpoints, non-dyadic coefficients, signed zero and seeded
inputs. The uncontracted control compiles the unchanged pinned spline functions
with explicit contraction disabled:

```sh
python3 tools/spline_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/spline_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --uncontracted-control --gpu
```

Configure checkouts as described in [README.md](../README.md#requirements).

## Cubic Bezier blocker

The pinned [cubic Bezier implementation](https://github.com/raysan5/raylib/blob/dbc56a87da87d973a9c5baa4e7438a9d20121d28/src/rshapes.c#L2232)
uses native `powf(t,3)`. Replacing it with a binary64 cube rounded to F32 differed
on 6,670 of 1,048,576 finite sampled inputs on the local Apple host. This difference
is observable through the actual point API: set the first three control points
to `(0,0)`, the final point to `(1,0)` and t to `0x1.940af8p-2`.

- Native point X bits: `3d7b9e4d`.
- Double-cube substitute bits: `3d7b9e4e`.

The dedicated probe retains this diagnostic alongside the implemented function
gates. Cubic Bezier remains blocked and is not counted as an implementation.
No output expectation or comparison tolerance is relaxed.
