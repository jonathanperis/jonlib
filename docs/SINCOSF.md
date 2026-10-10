# glibc sinf/cosf profile

Under both glibc profiles (`M.Glibc239Libm{}`, `M.Glibc241Libm{}`), Jonlib's
`sinf`/`cosf` are glibc's own x86_64 functions on **every finite binary32
argument**, bit for bit. Before this kernel, the profile was a one-turn
approximation (`|x| <= 6.283186f`).

## API

- `M.Libm.sin(libm, x) -> Maybe<F32>` / `M.Libm.cos(libm, x) -> Maybe<F32>`:
  - Under the glibc profiles, `None` only for infinities and NaN.
  - Under `M.AppleLibm{}`, the bounded Apple kernel for `|x| <= 6.283186`
    ([ROTATION.md](ROTATION.md)); `None` otherwise.
- `Trig.sincos_for(gnu, x)` (`src/trig.bend`) uses the kernel for its GNU
  branch. That branch serves Jonmath's rotation constructors (`Matrix.rotate*`,
  `Vector2.rotate_for`, `Vector3.rotate_by_axis_angle_for`,
  `Quaternion.from_axis_angle_for`, `Quaternion.from_euler_for`), the camera
  functions, gradients, `ImageRotate` and every rshapes/rmodels path that
  evaluates `sinf`/`cosf`.
- Where a drawing or camera call accepts glibc arguments, the accepted set is
  now every normal-or-zero argument (`Shapes.trig.gnu`, `Camera.turnable`),
  no longer `|x| <= 6.283186f`. Subnormal arguments are still refused there:
  - glibc's own result is defined for them (`sinf(y) = y`, `cosf(y) = 1`);
  - the subnormal arithmetic around those calls is not part of the frame
    contract.
- `src/sincosf.bend`: `sinf.word`/`cosf.word` map a binary32 word to the result
  word; `sinf`/`cosf` are the F32 forms.

## What glibc runs

glibc 2.39 and 2.41 build `sysdeps/ieee754/flt-32/s_sinf.c` and `s_cosf.c`.
This is Arm optimized-routines' `sinf.c`/`cosf.c`, with `sincosf.h`'s
`reduce_fast`/`reduce_large`, `sincosf_poly.h` and the tables of
`s_sincosf_data.c`. On x86_64 the build uses `TOINT_INTRINSICS 0`. The x86_64
multiarch build compiles the same sources twice:

- `s_sinf-fma.c`/`s_cosf-fma.c` with `-mfma -mavx2`;
- the SSE2 default.

The ifunc picks the FMA variant when the CPU has FMA and AVX2. This is true of
the CI runners and current desktop CPUs.

The FMA variant's disassembly (Ubuntu's glibc 2.39 `libm.so.6`) contracts every
`a + b*c` of `reduce_fast` and `sinf_poly` into one `vfmadd`/`vfnmadd`:

- `r = fma(-n, hpi, x)`;
- the sine terms `fma(x2, s3, s2)`, `fma(x3, s1, x)` and `fma(s1', x7, s)`;
- the cosine terms `fma(x2, c1, c0)`, `fma(x2, c4, c3)`, `fma(x4, c2, c1')` and
  `fma(c2', x6, c)`.

Products such as `x2*x`, `x2*x3`, `x2*x2`, `x*hpi_inv`, `res*pi63` and the
sign multiply stay separate roundings.

The model and the kernel follow the source's evaluation exactly:

- **Squares and quadrants.** `x2` is the square of the *unsigned* reduced
  argument, and the sign `sign[k & 3]` multiplies only the sine's `x`. For
  `reduce_large`, `k` is the quadrant plus the input's sign bit, but the
  polynomial choice uses the quadrant alone (plus one for `cosf`).
- **Quadrant index.** `reduce_fast`'s quadrant is
  `((int32_t)(x*hpi_inv) + 0x800000) >> 24`, so the truncation of negative
  products and the arithmetic shift decide ties.
- **Tiny path.** Below `0x1p-12f`, `sinf` returns its argument and `cosf`
  returns 1.

### Reference sources

Unmodified glibc 2.39 files in `tools/reference/glibc239`, identical to release
commit `ef321e23c20eebc6d6fb4044425c00e6df27b05f`
(`sysdeps/ieee754/flt-32/`; LGPL-2.1-or-later, notices in
[THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md)):

| File | SHA-256 |
|---|---|
| `s_sinf.c` | `5038e926aa6b9e414807bf0fd932efa89ad62d4b0e1c9586d0db222d8f040bf2` |
| `s_cosf.c` | `47075db253ad7ce172fa7eee0e14512c2d0123af7e5f197f086388ba2213ad41` |
| `s_sincosf.h` | `fcfeb879dc630126d5d7b0d98ed31a272a5ee8825047530edba4379bbf99336a` |
| `sincosf_poly.h` | `fd5a5817420cb9dc0d7a72284501045bdf937177e2dccf448f569c3010a9f214` |
| `s_sincosf_data.c` | `1dbfa95cd540a13ea39eca3f7d84103eee56af39602dd1e6864d8da42ccac60b` |

glibc 2.41 (commit `74f59e9271cbb4071671e5a474e7d4f1622b186f`) ships the
following files identical to 2.39 apart from copyright years:

- these five files;
- `s_sinf-fma.c`, `s_cosf-fma.c` and `ifunc-fma.h`;
- the Makefile's `CFLAGS-s_sinf-fma.c = -mfma -mavx2`.

The algorithm and constants are Arm's (MIT alternative,
[LICENSES/arm-math.txt](../LICENSES/arm-math.txt)). The C model and the Bend
kernel are written from them, so `src/sincosf.bend` is on Jonlib's zlib side
rather than in `src/lgpl/`.

## Model and exhaustive verification

`tools/reference/glibc_sinf/model.c` is an explicit-operation C model:

- `FUSED=1` for the FMA variant (explicit `fma`);
- `FUSED=0` for the SSE2 variant.

Compile it with `-ffp-contract=off`. `tools/reference/glibc_sinf/exhaustive.c`
evaluates it on every binary32 word against the host's `sinf`, `cosf` and
`sincosf`, each called through a volatile pointer. NaN results compare as NaN.
`run_exhaustive.sh` runs both variants:

- the FMA one against the host as is;
- the SSE2 one with `GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4`.

| Host | Variant | Arguments | sinf | cosf | sincosf | Result |
|---|---|---:|---:|---:|---:|---|
| Ubuntu 24.04 amd64, glibc 2.39-0ubuntu8.9 | FMA | 4,294,967,296 | 0 | 0 | 0 | `glibc239-fma.json` |
| same | SSE2 | 4,294,967,296 | 0 | 0 | 0 | `glibc239-sse2.json` |
| Debian trixie amd64 (container, same CPU), glibc 2.41-12+deb13u4 | FMA | 4,294,967,296 | 0 | 0 | 0 | `glibc241-fma.json` |
| same | SSE2 | 4,294,967,296 | 0 | 0 | 0 | `glibc241-sse2.json` |

The JSON results are in `tools/reference/glibc_sinf/results`. `sincosf`
equals the separate functions everywhere, so a compiler that merges a
`sinf`/`cosf` pair into `sincosf` changes nothing.

The FMA and SSE2 variants differ on only 34 arguments, all in `reduce_fast`'s
range: 17 magnitudes from `0x418a3adb` to `0x42e87a55`, each with both signs
(`tools/reference/glibc_sinf/variant_differences.txt`). The 17 positive ones
are `tools/glibc_sinf.py`'s controls. Before a probe uses the compiled model
it must reproduce them. A host whose own `sinf`/`cosf` reproduce them is
compared natively too.

### Helper domain

With `FUSED=1`, the same exhaustive program also checks every binary64
intermediate of every finite argument against the domain of Jonlib's exact
binary64 helpers (`src/binary64_scaled.bend`):

- zero-or-normal operands and results;
- FMA addend exponents within [-554, 255] of the product's;
- sum operands within 900 binades.

There are 0 violations on all of them. The smallest reduced arguments are about
`0x1.99bc5cp-27` (`reduce_fast`, at `0x4096cbe4`) and `0x1.bbdd52a4p-30`
(`reduce_large`, at `0x6f79be45`), so the helpers' `None` never happens for
a finite argument.

## The Bend kernel

`src/sincosf.bend` evaluates the model's operations through
`binary64_scaled`'s `multiply`, `add` and `fma`. Each rounds once to nearest
even. The conversion `(double)(int64_t)res` is the exact high half (an
integer times 2^32) plus the exact low word, with one rounded addition.
`reduce_large`'s 32x96-bit product runs on U32 pairs (16-bit-halves
multiplication). The final `(float)` is `binary64_narrow.checked`. The core
works on binary32 words (no F32 arithmetic). The two laws `glibc_sinf_negative_zero` and
`glibc_cosf_negative_zero`, and `glibc_sinf_infinity_none`, check the tiny and
nonfinite paths by evaluation. The reduced paths' helpers carry F32 exponents
that the proof checker does not evaluate, so the gates below cover them.

## Verification

| Gate | Tool | Compares |
|---|---|---|
| `glibc-sinf` | `tools/sincosf_probe.py` | the Bend kernel (CPU-1, CPU-2, JavaScript) against the FMA model on 2,252 arguments, and against the host `sinf`/`cosf` where they pass the controls. The arguments are:<br>• 2 random words per exponent and sign<br>• the four region boundaries ±1 ulp<br>• the binary32 neighbours of `k*pi/4` below 120<br>• the 34 variant differences<br>• the smallest remainders<br>• whole degrees through `DEG2RAD`<br>• zeros, subnormals, the largest finite values, infinities and NaN |
| `trig`, `trig-rotation` | `tools/trig_probe.py` | the gradient and `ImageRotate` arguments against the host's `sinf`/`cosf`. `--gnu-control` uses the model on any host, and `--full` covers every integral direction in -32767..32767 (up to ±572 radians) |

The camera, quaternion, frame, models and mesh probes use the model as
their glibc `sinf`/`cosf` (`trig_probe.REFERENCE`'s `arm_model`) on hosts
whose libm is not glibc's. Their refusal oracles accept the same argument
set as Jonlib.

## Limits

- This profile is the FMA ifunc variant. On an x86_64 CPU without FMA/AVX2,
  glibc's SSE2 variant differs from it on the 34 arguments above.
- glibc builds for other architectures (aarch64 contracts differently) are not
  verified and are not this profile.
- `M.AppleLibm{}` keeps its one-turn, whole-degree set
  ([ROTATION.md](ROTATION.md), [FRAME.md](FRAME.md)): macOS arm64 `sinf`/`cosf`
  are unpublished and not correctly rounded.
