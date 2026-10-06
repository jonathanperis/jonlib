# Perspective projection blocker

`MatrixPerspective` is **blocked**, with no implemented mapping. The pinned
reference computes `nearPlane*tan(fovY*0.5)` in binary64 before rounding the
vertical and horizontal spans to F32. The native binary64 `tan` rounding
therefore reaches the final matrix, even when an alternative tangent is closer to
the mathematical value.

## Retained native counterexample

On Apple arm64 native libm:

| Value | Exact encoding |
|---|---|
| FOV | `0x1.caac02dacfefep+0` |
| Near | `0x1.99c7240652e10p-2` |
| Aspect / far | `1.0` / `1000.0` |
| Native tangent bits | `3ff3fdc710f27cee` |
| 90-digit-series tangent rounded to binary64 | `3ff3fdc710f27cef` |
| Actual `MatrixPerspective` m5 bits | `3f4ce392` |
| Substituted high-precision tangent m5 bits | `3f4ce390` |

The one-ulp tangent difference crosses an F32 span rounding boundary and changes
m5 by two F32 steps. A correctly rounded tangent is therefore not a substitute:
compatibility requires reproducing the native tangent.

Apple's published
[Sun/FreeBSD tangent kernel](https://github.com/apple-oss-distributions/Libm/blob/17a5f9daa3f5679f7536b26f133b40cc078753c3/Source/ARM/k_tan_freeBSD.c)
has a permissive retained-notice grant, but the corresponding `tan.s` in that
snapshot is empty, and a first-quadrant adaptation using the published range
reduction differs from native macOS `tan` (with and without contraction) and
keeps the counterexample above. That snapshot does not establish the shipped
algorithm; no kernel from it is included in Jonlib.

Closing this entry requires a licensed, verified reference-compatible tangent
path per declared profile and complete native matrix comparisons.

## Diagnostic gate `perspective`

`tools/perspective_probe.py` (diagnostic gate; native only, never counted as
parity) compiles the pinned header-only `raymath.h` with `FP_CONTRACT OFF`, calls
`MatrixPerspective` on volatile copies of the counterexample inputs (an actual
native `tan` call) and records the native tangent and m5 bits next to those
obtained from a 90-digit sine/cosine series tangent. Results are written to
`.build/perspective-probe/results.json` with the host system and machine.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only perspective
```

The related projection APIs `MatrixFrustum` and `MatrixOrtho` are implemented
with binary64 inputs; see [MATH.md](MATH.md).
