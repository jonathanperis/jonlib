# Perspective projection

`MatrixPerspective` (`M.Matrix.perspective_for`), `BeginMode3D` with
`CAMERA_PERSPECTIVE` (`J.Frame.begin_mode_3d_for`), `GetCameraProjectionMatrix`
(`J.Camera.projection_matrix_for`) and `GetWorldToScreen(Ex)` /
`GetScreenToWorldRay(Ex)` for perspective cameras (`J.Camera.*_for(arithmetic,
libm, ...)`) are delivered under the glibc profiles (`M.Glibc239Libm{}`,
`M.Glibc241Libm{}`) and refused (`None`, or an undefined frame) under
`M.AppleLibm{}`. The forms without a profile argument use `AppleLibm`.

The reference computes `nearPlane*tan(fovY*0.5)` in binary64 before rounding
the spans to F32, so the native binary64 `tan` rounding reaches the final
matrix: a one-ulp tangent difference can move m5 by two F32 steps (see the
Apple counterexample below). Neither native `tan` is correctly rounded on
raylib's arguments, so Jonlib reproduces the native function of a profile
instead of computing an accurate tangent.

## The tangent: `M.Libm.tan`

`M.Libm.tan(libm, x: M.Float64) -> Maybe<M.Float64>` is glibc's x86_64
binary64 `tan` as its `__tan_fma` ifunc variant runs on CPUs with FMA and AVX2
(the CI runners and current desktop CPUs), for both glibc profiles; `None` for
`AppleLibm`, infinities and NaN. glibc builds `s_tan.c` four times (`-mfma
-mavx2`, `-mfma4`, AVX and SSE2) and selects one at load time; the FMA build
contracts `a*b + c` across statements and uses `fma` in `dla.h`'s `MUL12`, so
its results differ from the SSE2 build's.

The kernel is `src/lgpl/tan.bend` with its table `src/lgpl/tan_table.bend`,
an altered Bend adaptation of IBM's `s_tan.c` licensed **LGPL-2.1-or-later**
(the only LGPL files of Jonlib; see [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md)).
Every double operation of the source runs through Jonlib's exact binary64
helpers in the source's order, with each contracted `a*b + c` of the FMA
build written as one fused operation. `src/binary64_scaled.bend` (zlib)
extends the bounded helpers to every normal exponent by exact power-of-two
scaling. The kernel refuses (`None`) where a helper would see a nonfinite or
subnormal value; that never happens on raylib's arguments.

### Reference sources

Unmodified glibc 2.39 files in `tools/reference/glibc239`, identical to release
commit `ef321e23c20eebc6d6fb4044425c00e6df27b05f`
(`sysdeps/ieee754/dbl-64/`, `e_asinf.c` from `flt-32/`):

| File | SHA-256 |
|---|---|
| `s_tan.c` | `8e02f594c1cde592b6997e6c88be2090a16c23f940fdffc93348ab0dd1b06174` |
| `utan.h` | `1e1f5458a04576d3ab84b78fa09af5818531e8995a6661185ae3b48624a566c5` |
| `utan.tbl` | `0c8b795eff2c650d6ffd1ce9480b335dda87554bd535f95281f9dbeb9bbea95c` |
| `dla.h` | `ea81d5abbc49e592d09d1f08ff29bfd2928f4c9102bc80b1345046ded7c16a6f` |
| `mydefs.h` | `61467ec67b82e151d741add0e63a7372443f8d769e952305346ef0063e5386b6` |
| `branred.c` | `e697adc29fed48602ffd3c790f90bda8da1db7bc5e135d39f9880a0f7480d6ad` |
| `branred.h` | `ac2285d857dc04ef833f53a6cf97457359b803cb97477885544ff724ff54363d` |
| `e_asinf.c` | `bb3e68b0ae3736d4c4f41c9e8d11416d8423ab8577696a33dade0b5afd402ffd` |

glibc 2.41 (commit `74f59e9271cbb4071671e5a474e7d4f1622b186f`) ships the same
seven tangent files and the same `CFLAGS-s_tan-fma.c = -mfma -mavx2`; only the
copyright years differ.

`tools/reference/glibc_tan/model.c` (LGPL-2.1+) is an explicit-operation C
model of the same function, `FUSED=1` for the FMA variant and `FUSED=0` for
SSE2/AVX, compiled with contraction off around the pinned `branred.c`.
`tools/glibc_tan.py` builds it for the probes and requires it to reproduce
32 control arguments before use.

## Which tangent arguments raylib passes

Every caller derives the tangent argument from a binary32 `fovy`
(`DEG2RAD` is the binary32 `PI/180.0f`, word `3c8efa35`):

| Caller | Expression reaching `tan` | Argument set |
|---|---|---|
| `GetCameraProjectionMatrix` (rcamera.h), `GetWorldToScreenEx`, `GetScreenToWorldRayEx` (rcore.c) | `MatrixPerspective(camera.fovy*DEG2RAD, ...)`: a binary32 product, then `tan(fovY*0.5)` | **perspective**: `(double)g * 0.5` for every finite binary32 `g` |
| VR `LoadVrStereoConfig` (rcore.c) | `MatrixPerspective(fovy, ...)` with a binary32 `fovy` | the same set |
| `BeginMode3D` (rcore.c) | `tan(camera.fovy*0.5*DEG2RAD)`: `((double)fovy*0.5)*(double)DEG2RAD` rounded once in binary64 | **begin3d**: one binary64 value per finite binary32 `fovy` |

Both sets have 4,278,190,080 elements, so they were compared exhaustively.

## Exhaustive verification

`tools/reference/glibc_tan/tan_survey.c` evaluates, on every argument of a
set, the native `tan` (through a volatile function pointer), both models,
the pinned glibc sources built as glibc builds them (`-mfma -mavx2` and plain)
and CORE-MATH's correctly rounded `cr_tan`
(`tools/reference/glibc_tan/build.sh`, `run_all.sh`; the JSON results are in
`tools/reference/glibc_tan/results`). On Ubuntu 24.04 amd64 (glibc
2.39-0ubuntu8.9, an FMA/AVX2 CPU):

| Set | Native vs FMA model | Native vs SSE2 model | FMA model vs correct rounding |
|---|---:|---:|---:|
| perspective | **0** | 27,258 | 5,592,284 |
| begin3d | **0** | 25,346 | 5,336,390 |

The pinned builds equal their models on both sets (0 differences), and with
`GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4` the native function equals
the SSE2 model on every begin3d argument (`begin3d-sse2.json`), so the profile
is the CPU's ifunc variant, not the library version alone. glibc 2.41 (Debian trixie, `2.41-12+deb13u4`, the same CPU)
equals the FMA model on the 2,158 hardest perspective arguments (every
argument where the FMA and SSE2 variants differ, and every one glibc
misrounds), run in a container from the same survey binary (the exhaustive 2.41
run of both sets is in progress and will be recorded here).

The Bend kernel was compared with the FMA model on 14,488 arguments of both
sets (a stratified sample of every binary32 exponent plus the 2,158 hard
arguments), 0 differences, and is gated on every lane through the camera and
models probes below.

## How each API uses it

- `MatrixPerspective(fovY, aspect, near, far)`: `top = near*tan(fovY*0.5)` and
  `right = top*aspect` in binary64, then `MatrixFrustum(-right, right, -top,
  top, near, far)`'s F32 cells. `None` where `M.Libm.tan` is `None` or a
  binary64 product is subnormal or overflows.
- `GetCameraProjectionMatrix(camera, aspect)`: `MatrixPerspective` with the
  F32 product `fovy*DEG2RAD`, the F32 aspect and rcamera.h's cull distances
  0.05 and 4000.
- `GetWorldToScreenEx`, `GetScreenToWorldRayEx` (and the screen-size forms):
  the same with `aspect = (double)width/(double)height`; a perspective ray
  starts at the camera position.
- `BeginMode3D`: `swFrustum(-right, right, -top, top, 0.05, 4000.0)` with
  `top = 0.05*tan(((double)fovy*0.5)*DEG2RAD)` and `right = top*aspect`
  (the F32 aspect of the current color buffer). rlsw divides `(float)(0.1)`
  by the binary64 spans and narrows to F32; m8 and m9 are `+0.0` divided by
  the spans (the sign of `fovy`), m10, m11 and m14 are constants. A zero or
  nonfinite m0/m5 (`fovy` 0 among them) marks the frame undefined, as for
  orthographic cameras.

## Gates

- `camera` (linked raylib, host profiles), `camera-uncontracted` and the
  `--gnu-libm` controls (`camera-glibc239`, `camera-fused-glibc241`) compare
  `GetCameraProjectionMatrix` and the screen queries for perspective cameras;
  on Linux the native glibc `tan` is the reference, after
  `glibc_tan.host_is_model` checks it reproduces the controls (a host without
  FMA fails the gate rather than choosing a profile), and the controls link
  the model as `tan`.
- `models` and `models-gnu` render perspective scenes (`m3-persp-*`) byte for
  byte; macOS hosts check the refusals.
- `libm-survey` (diagnostic) and `perspective` (diagnostic, native only)
  record the host `tan` against correct rounding.

## History: why no other tangent

Before the LGPL decision (2026-10-09) every perspective path was `None`.
`tools/libm_survey.py --stride 1` compared the native `tan` with CORE-MATH's
correctly rounded `cr_tan` on both argument sets (smallest differing input of
every exponent recomputed with the exact oracle `tools/cr_libm_oracle.py`):

| Native libm | Set | Differences from correct rounding | Smallest differing input |
|---|---|---:|---|
| macOS 27.0.1 arm64 | perspective | 1,012,998,028 (23.7%) | `g = 32b504f4` |
| macOS 27.0.1 arm64 | begin3d | 972,290,352 (22.7%) | `fovy = 35a20e94` (45 degrees too) |
| glibc 2.39 x86_64 (FMA variant) | perspective | 5,592,284 (0.13%) | `g = 3ac8d571` |
| glibc 2.39 x86_64 (FMA variant) | begin3d | 5,336,390 (0.12%) | `fovy = 3d47bfb0` |

A correctly rounded kernel would therefore reproduce neither reference, and a
"correct wherever tan(x) is at least θ ulp from a rounding boundary" profile
needs θ ≥ 0.069 ulp for glibc (`tools/reference/libm_tan_margin.c`), refusing
about 14% of ordinary cameras; both were rejected.

Apple arm64 counterexample with a binary64 `fovY`: FOV
`0x1.caac02dacfefep+0`, near `0x1.99c7240652e10p-2`, aspect 1, far 1000;
native tangent `3ff3fdc710f27cee`, correctly rounded `...cef`; m5 `3f4ce392`
natively, `3f4ce390` with the correct tangent. Apple's published
[Sun/FreeBSD tangent kernel](https://github.com/apple-oss-distributions/Libm/blob/17a5f9daa3f5679f7536b26f133b40cc078753c3/Source/ARM/k_tan_freeBSD.c)
does not match the shipped function, so no Apple profile exists.

The related projection APIs `MatrixFrustum` and `MatrixOrtho` take binary64
inputs directly; see [MATH.md](MATH.md).
