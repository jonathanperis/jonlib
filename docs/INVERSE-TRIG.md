# Inverse trigonometry profiles

raymath's `QuaternionSlerp` and `QuaternionToAxisAngle` call native float
`acosf`, and `QuaternionToEuler` calls `asinf`. Their last bits depend on the C
library and on how it was compiled, so Jonmath reproduces a declared profile
instead of computing an idealized value; where a native `asinf` is correctly
rounded on a characterized set of inputs, the profile reproduces it there with
a correctly rounded kernel. (The `atan2f` dependency of the angle
APIs is handled by explicit profiles; see [ANGLES.md](ANGLES.md).)

## Glibc239Libm acosf

`src/inverse_trig.bend` adapts glibc 2.39's Sun float `acosf`
(`sysdeps/ieee754/flt-32/e_acosf.c`, kept unmodified in
`tools/reference/acos_sources/sun_e_acosf.c`): the same constants, branches
(|x| = 1, |x| <= 2^-26, |x| < 0.5, x <= -0.5, x >= 0.5 with the truncated
square root) and F32 operation order, uncontracted. `M.Libm.acos(libm, x)`
returns it for `Glibc239Libm{}` on [-1, 1]; |x| > 1 and NaN, where the source
returns a NaN whose bits depend on the host, are `None`.

Which hosts this matches was checked exhaustively, on all 2,130,706,434 inputs
in [-1, 1]:

| Host | Result |
|---|---|
| Ubuntu 24.04 x86_64, glibc 2.39 (the CI Linux runner) | equal to the pinned source compiled with contraction off |
| Ubuntu 24.04 aarch64, glibc 2.39 | differs on 218,096 inputs; equal to the source compiled with FMA contraction, so a different (fused) profile, not covered |

`AppleLibm{}` and `Glibc241Libm{}` have no `acosf` kernel yet and return
`None` (glibc 2.41's correctly rounded `acosf` is a possible later profile).
Apple's `asinf`/`acosf` match neither its published Libm sources nor correctly
rounded results (examples below), so a complete Apple profile would have to be
derived from the proprietary binary.

## asinf: a correctly rounded kernel and where each libm matches it

`src/asin.bend` adapts glibc 2.41's `e_asinf.c` (Alexei Sibidanov's CORE-MATH
`asinf`, MIT; pinned and unmodified in `tools/reference/core_math`, notice in
[LICENSES/core-math-asinf.txt](../LICENSES/core-math-asinf.txt)): the same
constants, branches (|x| < 2^-12 through `fmaf(x, 0x1p-25, x)`, the degree-31
fast polynomial with its `ub == lb` rounding test, the |x| < 0.5 and |x| >= 0.5
fallbacks with the two exceptional words) and binary64 operation order,
uncontracted. Each binary64 operation goes through the checked helpers of
[BINARY64.md](BINARY64.md) (one rounding to nearest even each; a new private
`src/binary64_sqrt.bend` supplies the square root, an exact restoring integer
square root of the scaled significand); `fmaf` is the total binary32 FMA of
`src/fma.bend`. No host F32/F64 transcendental is used. The kernel is
correctly rounded: the pinned C source equals CORE-MATH's `cr_asinf` on every
input of [-1, 1], and CORE-MATH agrees with the independent exact oracle
`tools/cr_libm_oracle.py` on every checked input (below).

`M.Libm.asin(libm, x) -> Maybe<F32>` exposes it per profile, on the inputs
where that profile's native `asinf` was found equal to correct rounding by an
**exhaustive** comparison over all 2,130,706,434 binary32 values in [-1, 1]
(`tools/libm_survey.py --stride 1 --modes asinf`, October 2026):

| Profile | Native libm compared | Differences from correct rounding | Smallest differing input | `Libm.asin` returns `Some` for |
|---|---|---:|---|---|
| `Glibc241Libm{}` | glibc 2.41 `e_asinf.c` source (CORE-MATH), and native Debian trixie glibc 2.41-12 x86_64 (container), equal to that source on every input | 0 | none | every x in [-1, 1] |
| `Glibc239Libm{}` | Ubuntu 24.04 amd64 glibc 2.39 (container) | 4,581,700 | `0x39e8974f` (0x1.d12e9ep-12): native `39e89750`, correct `39e8974f` | every x in [-1, 1], from glibc 2.39's own kernel (below) |
| `AppleLibm{}` | macOS 27.0.1 arm64 libm | 581,248 | `0x39e89768` (0x1.d12edp-12): native `39e89768`, correct `39e89769` | \|x\| < 0x1.d12edp-12 (words below `0x39e89768`) |

Both signs are included; below each bound every input agrees, and the bound
itself differs. glibc 2.39's `asinf` has no x86_64 multiarch variant (the
FMA-disabled run gave the same 4,581,700 differences). |x| > 1 and NaN are
`None` in every profile (the native result is a NaN whose bits depend on the
host). Further examples: Apple `asinf(0x3abffffc)` is `3ac00000`, correct
`3ac00001`; glibc 2.39 `asinf(0x3a1285ef)` is `3a1285f0`, correct `3a1285ef`.

## Glibc239Libm asinf: glibc 2.39's kernel (LGPL)

Since the LGPL decision (2026-10-09, [MASTER-PLAN](MASTER-PLAN.md)),
`Libm.asin(Glibc239Libm{}, x)` is glibc 2.39's own `e_asinf.c` on all of
[-1, 1] rather than the correctly rounded kernel below a bound.
`src/lgpl/asin.bend` adapts it (Sun's `e_asin.c` with Stephen L. Moshier's
single-precision modifications, LGPL-2.1-or-later; pinned unmodified in
`tools/reference/glibc239/e_asinf.c`, SHA-256
`bb3e68b0ae3736d4c4f41c9e8d11416d8423ab8577696a33dade0b5afd402ffd`, notices in
[THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md)): the same constants, branches
(|x| = 1, |x| < 2^-27, |x| < 0.5 with the degree-5 polynomial, 0.975 < |x| < 1
and 0.5 <= |x| <= 0.975 with the truncated square root) and F32 operation
order, uncontracted. The pinned source compiled with contraction off equals
the native glibc 2.39 x86_64 `asinf` (Ubuntu 24.04, the CI runner) on all
2,130,706,434 inputs of [-1, 1] (0 differences); the `quaternion-euler` gate
repeats that exhaustive check on such hosts and compares the Bend kernel with
the source on every lane.

## Quaternion functions

- `Quaternion.slerp_for(libm, q1, q2, amount) -> Maybe<Vector4>` keeps
  raymath's hemisphere flip, the copy branch (|cos| >= 1) and the nlerp branch
  (cos > 0.95), which need no libm and return `Some` for every profile.
  Otherwise it uses `acosf(cos)`, `sqrtf(1 - cos*cos)` and two `sinf` weights
  from the profile (glibc's own sinf, [SINCOSF.md](SINCOSF.md), for
  glibc). `None` when that branch needs an `acosf` the profile lacks, for a NaN
  cosine, or when `Libm.sin` refuses a `sinf` argument (Apple: outside
  its verified whole degrees; glibc: infinite or NaN), the verified
  kernel domain.
- `Quaternion.to_axis_angle_for(libm, q) -> Maybe<(Vector3 & F32)>`
  normalizes quaternions with |w| > 1 as raymath does, then returns the axis
  `(x, y, z)/sqrt(1 - w*w)` (or `(1, 0, 0)` when that is at most 1e-6) and the
  angle `2*acosf(w)`; the pointers of the C API become the returned pair.
  `None` when the profile lacks `acosf`, or when w is outside [-1, 1] or NaN
  after normalization.
- `Quaternion.to_euler_for(libm, q) -> Maybe<Vector3>` returns raymath's
  (roll, pitch, yaw) = (`atan2f(x0, x1)`, `asinf(clamp(y0, -1, 1))`,
  `atan2f(z0, z1)`) in the reference's uncontracted F32 order, with the
  profile's `atan2f` ([ANGLES.md](ANGLES.md)) and `Libm.asin`. `None` unless all
  four components are finite, every intermediate (the products, sums, `x0`,
  `x1`, `y0`, `z0`, `z1`) and both `atan2f` results are signed zero or normal
  (the checked angle contract), and the profile has the clamped pitch's
  `asinf` (any pitch under `Glibc241Libm{}` and `Glibc239Libm{}`; under
  `AppleLibm{}` a pitch argument below the bound above, which covers rotations
  about the x or z axis alone, where `y0` is exactly zero).

## Verification

`tools/quaternion_angle_probe.py` (gate `quaternion-angle`) compiles the
pinned `raymath.h` with contraction off, with `acosf` from the unmodified
glibc 2.39 source and `sinf` from the glibc sinf model of
`tools/trig_probe.py` ([SINCOSF.md](SINCOSF.md)), and compares on CPU-1, CPU-2 and JavaScript:

- `M.Libm.acos` on 24,059 inputs: region boundaries, signed zeros, +-1,
  subnormals, values past 1, infinities, NaN and random words and values;
- `slerp_for` under all three profiles on 1,285 pairs: random, nearby,
  opposite, non-unit, zero and nonfinite quaternions, and amounts inside and
  outside [0, 1];
- `to_axis_angle_for` under all three profiles on 917 quaternions: unit,
  non-unit, w = +-1, near-identity, zero, huge and nonfinite.

On a Linux x86_64 glibc 2.39 host (the CI runner) the same C program is also
built against the host libm and must print identical rows; elsewhere the
report records `host_libm_checked: false`. That check was also run once in an
Ubuntu 24.04 amd64 container: identical.

## Verification of asinf and QuaternionToEuler

`tools/quaternion_euler_probe.py` (gate `quaternion-euler`, Linux and macOS)
compiles the pinned glibc 2.41 `e_asinf.c` with contraction off and compares,
on CPU-1, CPU-2 and JavaScript:

- `Libm.asin` under all three profiles on 2,965 inputs: signed zeros, +-1,
  values past 1, infinities, NaN, subnormals, the branch boundaries (2^-12,
  0.5, 0x1.c29p-1), the two exceptional words, both profile bounds and their
  neighbours, 160 inputs whose fast-path rounding test fails (found by the
  probe), random words and values; one in seven results is also recomputed
  with the exact oracle;
- `to_euler_for` under all three profiles on 665 quaternions (random unit and
  non-unit, single-axis rotations, tiny pitches on both sides of the bounds,
  gimbal-lock neighbourhoods with clamping, identity, zero, signed zeros,
  subnormal, huge and nonfinite components) against raymath's
  `QuaternionToEuler` with `asinf` routed to the profile's pinned source (glibc
  2.39's for `Glibc239Libm{}`, 2.41's otherwise) and `atan2f` to
  the profile kernel (the pinned glibc 2.41 and Sun 2.39 sources; native
  `atan2f` for `AppleLibm{}`, on Darwin only), with a C oracle repeating the
  refusal contract.

On the host a profile names (Darwin arm64: `AppleLibm{}`; Linux x86_64 glibc
2.39: `Glibc239Libm{}`) the probe also requires the native `asinf` to equal the
profile's source on its whole domain (below the bound: 1,943,088,848 inputs on
macOS 27.0.1; all 2,130,706,434 inputs of [-1, 1] for glibc 2.39), and native
raymath (host `asinf` and `atan2f`) to equal every accepted Euler row.

`tools/libm_survey.py` (diagnostic gate `libm-survey`, every 64th input;
`--stride 1` is exhaustive) records the native-versus-correct-rounding
comparison above. CORE-MATH `cr_asinf` is cross-checked on every input against
the host binary64 `asin` with an 8-ulp margin from the binary32 rounding
midpoints; the 14 inputs inside the margin, and the smallest counterexample of
every exponent, are recomputed with the exact integer oracle
`tools/cr_libm_oracle.py` (fixed-point series with Machin's pi; the arcsine
is decided by comparing sines of the rounding midpoints), which must agree.

## Native counterexamples (Apple arm64)

Bend's Base `F32.asin`/`F32.acos` primitives do not reproduce native libm bits,
and on the forced-Metal lane they also differ in signed zero:

| Operation | Input | Native bits | Base bits |
|---|---:|---|---|
| `asinf` | -1 | `bfc90fda` | `bfc90fdb` |
| `acosf` | -1 | `40490fda` | `40490fdb` |
| `asinf` | +1 | `3fc90fda` | `3fc90fdb` |
| `asinf` on Metal | -0 | `80000000` | `00000000` |

Two candidate Apple replacements were evaluated and **not** adopted because
they also differ from the current native implementation:

- the published legacy Apple
  [asin](https://github.com/apple-oss-distributions/Libm/blob/17a5f9daa3f5679f7536b26f133b40cc078753c3/Source/Intel/asinf.s)
  and
  [acos](https://github.com/apple-oss-distributions/Libm/blob/17a5f9daa3f5679f7536b26f133b40cc078753c3/Source/Intel/acosf.s)
  algorithms by Eric Postpischil;
- idealized double-precision functions rounded to F32, even with endpoint
  adjustments.

## Diagnostic gate `inverse-trig`

`tools/inverse_trig_probe.py` (diagnostic gate; never counted as parity) calls
native `asinf`/`acosf` through volatile function pointers, which prevents builtin
constant folding, and records the Base `F32.asin`/`F32.acos` results on CPU-1,
CPU-2 and JavaScript (and a forced-GPU lane with `--gpu`). Inputs are ±0, ±1,
neighbours of 0.5, 0.57, 0.62, 0.975 and 1.0 in both signs, and seeded values in
[-1, 1]. Per-lane mismatches are written to
`.build/inverse-trig-probe/results.json`; they are recorded, not asserted.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only inverse-trig
```
