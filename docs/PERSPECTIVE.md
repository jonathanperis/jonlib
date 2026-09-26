# Perspective projection: retained precision blocker

`MatrixPerspective` is currently **blocked**, with no implemented mapping.
The pinned reference computes `nearPlane*tan(fovY*0.5)` in binary64 before
rounding the vertical and horizontal spans to F32. Native tangent rounding can
therefore affect the final matrix even when an alternative tangent is closer
to the mathematical value.

## Retained native counterexample

On the exercised Apple arm64 host:

| Value | Exact encoding |
|---|---|
| FOV | `0x1.caac02dacfefep+0` |
| Near | `0x1.99c7240652e10p-2` |
| Aspect / far | `1.0` / `1000.0` |
| Native tangent bits | `3ff3fdc710f27cee` |
| 90-digit-series tangent rounded to binary64 | `3ff3fdc710f27cef` |
| Actual `MatrixPerspective` m5 bits | `3f4ce392` |
| Substituted high-precision tangent m5 bits | `3f4ce390` |

The one-ULP tangent difference crosses an F32 span rounding boundary and changes
m5 by two F32 steps. The unchanged reference function is executed with volatile
inputs to retain an actual native call.

```sh
python3 tools/perspective_probe.py --raylib-source "$RAYLIB_SOURCE"
```

Set the checkout variable as described in [README.md](../README.md#requirements).
This command records a diagnostic under `.build/perspective-probe/`; it does not
establish a passing Jonlib implementation. Hosted CI records the same input on
Ubuntu/macOS, preserving host-specific results as artifacts.

## Kernel investigation

Apple's published [Sun/FreeBSD tangent kernel](https://github.com/apple-oss-distributions/Libm/blob/17a5f9daa3f5679f7536b26f133b40cc078753c3/Source/ARM/k_tan_freeBSD.c)
has a permissive retained-notice grant, but the corresponding `tan.s` file in
that snapshot is empty. A first-quadrant diagnostic adaptation using the published
range reduction differed from current native macOS tangent on 1,597/4,096 samples
with contraction off and 1,590/4,096 with contraction on/fast. All modes retained
the matrix counterexample above. That snapshot therefore does not establish the
shipped native algorithm. No kernel from this experiment is included in Jonlib.

Closing this entry requires a licensed, verified reference-compatible tangent
path and complete native matrix comparisons. The counterexample remains fixed;
no expected value or comparison tolerance has been changed. Other independent
API work continues through the [progress queue](PROGRESS.md).
