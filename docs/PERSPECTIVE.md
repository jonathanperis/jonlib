# Perspective projection blocker

`MatrixPerspective` is **blocked**, with no implemented mapping, and so are the
perspective paths that call it or the same tangent: `BeginMode3D` with
`CAMERA_PERSPECTIVE`, and `GetCameraProjectionMatrix`, `GetWorldToScreenEx` and
`GetScreenToWorldRayEx` for perspective cameras (`None` in Jonlib). The
reference computes `nearPlane*tan(fovY*0.5)` in binary64 before rounding the
vertical and horizontal spans to F32, so the native binary64 `tan` rounding
reaches the final matrix, even when another tangent is closer to the
mathematical value.

## Which tangent arguments raylib passes

Every caller derives the tangent argument from a binary32 `fovy`
(`DEG2RAD` is the binary32 `PI/180.0f`, word `3c8efa35`):

| Caller | Expression reaching `tan` | Argument set |
|---|---|---|
| `GetCameraProjectionMatrix` (rcamera.h), `GetWorldToScreenEx`, `GetScreenToWorldRayEx` (rcore.c) | `MatrixPerspective(camera.fovy*DEG2RAD, ...)`: a binary32 product, then `tan(fovY*0.5)` | **perspective**: `(double)g * 0.5` for every finite binary32 `g` |
| VR `LoadVrStereoConfig` (rcore.c) | `MatrixPerspective(fovy, ...)` with a binary32 `fovy` | the same set |
| `BeginMode3D` (rcore.c) | `tan(camera.fovy*0.5*DEG2RAD)`: `((double)fovy*0.5)*(double)DEG2RAD` rounded once in binary64 | **begin3d**: one binary64 value per finite binary32 `fovy` |

Both sets have 4,278,190,080 elements, so they were compared exhaustively.

## Exhaustive comparison with correct rounding

`tools/libm_survey.py --stride 1` (October 2026) evaluated the native `tan`
(through a volatile function pointer) on every argument of both sets and
compared it with CORE-MATH's correctly rounded `cr_tan` (MIT, unmodified in
`tools/reference/core_math`, commit `a6509c5b`). The smallest differing input
of every exponent and its native and correct words were recomputed with the
independent exact oracle `tools/cr_libm_oracle.py` (Machin pi, fixed-point
series, Ziv loop), which agreed with CORE-MATH every time (308, 298, 276 and
266 inputs).

| Native libm | Set | Differences | Smallest differing input | Example |
|---|---|---:|---|---|
| macOS 27.0.1 arm64 | perspective | 1,012,998,028 (23.7%) | `g = 32b504f4` (0x1.6a09e8p-26) | `tan(0x1.6a09e8p-27)`: native `3e46a09e80000001`, correct `...80000000` |
| macOS 27.0.1 arm64 | begin3d | 972,290,352 (22.7%) | `fovy = 35a20e94` | `fovy = 45`: argument `3fd921fb51000000`, native `3fda827996294b07`, correct `...94b06` |
| glibc 2.39 x86_64 (Ubuntu 24.04 amd64 container, FMA variant) | perspective | 5,592,284 (0.13%) | `g = 3ac8d571` (about 0.0015 rad) | argument `3f491aae20000000`: native `3f491aae7266f97c`, correct `...f97d` |
| glibc 2.39 x86_64 (FMA variant) | begin3d | 5,336,390 (0.12%) | `fovy = 3d47bfb0` (about 0.049 degrees) | argument `3f3be3e38b23dc00`: native `3f3be3e3a76370a4`, correct `...70a3` |
| glibc 2.39 x86_64 (SSE2 variant, `GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4`) | perspective | 5,596,838 | `g = 3ac8d571` | differs from the FMA variant too |
| glibc 2.39 x86_64 (SSE2 variant) | begin3d | 5,340,536 | `fovy = 3d47bfb0` | |

On macOS, 79 of the integer `fovy` values 1..179 degrees reach `BeginMode3D`
with an incorrectly rounded tangent, 45 included (raylib's examples use 45);
glibc 2.39 rounds all 179 correctly but misrounds about one argument in 770
overall. glibc 2.41 ships the same `sysdeps/ieee754/dbl-64/s_tan.c` as 2.39
(only the copyright year differs; its comment states a maximum error of about
0.619 ulp), so it is not correctly rounded either. Neither native `tan` equals
correct rounding on either set, and below the smallest counterexamples
(|fovY| < 0x1.6a09e8p-26 rad on macOS, about 0.0015 rad on glibc) no camera is
usable, so a correctly rounded kernel would not reproduce either reference. The
LGPL-2.1+ IBM `s_tan.c` of glibc is not adapted.

### A subdomain by distance from the rounding boundary (rejected)

glibc's differences are confined to arguments whose exact tangent lies close
to a binary64 rounding boundary, so the other characterization considered was
"correct rounding wherever tan(x) is at least θ ulp from a boundary" (a
correctly rounded kernel that certifies the distance and refuses the rest).
`tools/reference/libm_tan_margin.c` (GCC with libquadmath; binary128 `tanq`
measures the distance) gives, for glibc 2.39 x86_64 (FMA variant), the largest
distance of any difference:

| Set | Arguments | Differences | Largest distance of a difference |
|---|---|---:|---|
| perspective | \|x\| < 1e30 | 4,441,868 | 0.0865 ulp (input `45da0aca`) |
| begin3d | \|x\| < 1e30 | 4,431,534 | 0.0977 ulp (input `589e5143`) |
| perspective | \|x\| < pi/2 (fovY below pi) | 283,488 | 0.0632 ulp (input `3df925cd`) |
| begin3d | \|x\| < pi/2 (fovy below 180 degrees) | 282,162 | 0.0688 ulp (input `432c35e1`) |

The differences thin out towards that bound (2 and 4 of them at 2^-4..2^-3 ulp
for \|x\| < pi/2) but reach it, so θ must be at least 0.069 ulp. Because the
distance of a typical tangent is uniform on [0, 0.5] ulp, such a profile would
refuse about 2θ of all perspective cameras: 13.7% of 1,500 random `fovy` in
[10, 120] degrees (recomputed with the exact oracle), at unpredictable angles.
That is not a usable `CAMERA_PERSPECTIVE` contract, so no tangent kernel was
added; for macOS, with 23% of arguments misrounded, no such bound helps.

## Earlier counterexample (Apple arm64)

With a binary64 `fovY` that no binary32 caller produces:

| Value | Exact encoding |
|---|---|
| FOV | `0x1.caac02dacfefep+0` |
| Near | `0x1.99c7240652e10p-2` |
| Aspect / far | `1.0` / `1000.0` |
| Native tangent bits | `3ff3fdc710f27cee` |
| Correctly rounded tangent (also the 90-digit series) | `3ff3fdc710f27cef` |
| Actual `MatrixPerspective` m5 bits | `3f4ce392` |
| Substituted correctly rounded tangent m5 bits | `3f4ce390` |

The one-ulp tangent difference crosses an F32 span rounding boundary and changes
m5 by two F32 steps.

Apple's published
[Sun/FreeBSD tangent kernel](https://github.com/apple-oss-distributions/Libm/blob/17a5f9daa3f5679f7536b26f133b40cc078753c3/Source/ARM/k_tan_freeBSD.c)
has a permissive retained-notice grant, but the corresponding `tan.s` in that
snapshot is empty, and a first-quadrant adaptation using the published range
reduction differs from native macOS `tan` (with and without contraction) and
keeps the counterexample above. That snapshot does not establish the shipped
algorithm; no kernel from it is included in Jonlib.

Closing this entry requires a licensed, verified reference-compatible tangent
path per declared profile and complete native matrix comparisons.

## Diagnostic gates

`tools/libm_survey.py` (diagnostic gate `libm-survey`; every 64th input by
default, `--stride 1` for the exhaustive run above, `--modes` to select
`tan-perspective`, `tan-begin3d`, `asinf`) builds
`tools/reference/libm_survey.c` with the pinned CORE-MATH sources and writes
`.build/libm-survey-probe/results.json`: per exponent bucket the evaluated
inputs, differences and smallest counterexample, all oracle-confirmed.

`tools/perspective_probe.py` (diagnostic gate `perspective`; native only, never
counted as parity) compiles the pinned header-only `raymath.h` with
`FP_CONTRACT OFF`, calls `MatrixPerspective` on volatile copies of the
counterexample inputs above (an actual native `tan` call) and records the
native tangent and m5 bits next to those obtained from a 90-digit sine/cosine
series tangent. Results are written to `.build/perspective-probe/results.json`
with the host system and machine.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only libm-survey --only perspective
python3 tools/libm_survey.py --stride 1 --threads 4
```

The glibc rows above were produced in a throwaway Ubuntu 24.04 amd64 container
(`docker run --platform linux/amd64 ubuntu:24.04`, glibc 2.39-0ubuntu8.9, with
`clang`, `gcc` and `python3` installed in the container only), running the
same `tools/libm_survey.py`; the CI Linux runner is the same distribution.

The related projection APIs `MatrixFrustum` and `MatrixOrtho` are implemented
with binary64 inputs; see [MATH.md](MATH.md).
