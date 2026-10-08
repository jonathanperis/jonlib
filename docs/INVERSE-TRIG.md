# Inverse trigonometry profiles

raymath's `QuaternionSlerp` and `QuaternionToAxisAngle` call native float
`acosf`, and `QuaternionToEuler` calls `asinf`. Their last bits depend on the C
library and on how it was compiled, so Jonmath reproduces a declared profile
instead of computing an idealized value. (The `atan2f` dependency of the angle
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
`None`. Apple's `asinf`/`acosf` match neither its published Libm sources nor
correctly rounded results (examples below), so an Apple profile would have to
be derived from the proprietary binary; glibc 2.41's correctly rounded
CORE-MATH `acosf` (MIT) is a possible later profile.

## Quaternion functions

- `Quaternion.slerp_for(libm, q1, q2, amount) -> Maybe<Vector4>` keeps
  raymath's hemisphere flip, the copy branch (|cos| >= 1) and the nlerp branch
  (cos > 0.95), which need no libm and return `Some` for every profile.
  Otherwise it uses `acosf(cos)`, `sqrtf(1 - cos*cos)` and two `sinf` weights
  from the profile (the GNU sinf kernel of [ROTATION.md](ROTATION.md) for
  glibc). `None` when that branch needs an `acosf` the profile lacks, for a NaN
  cosine, or when a `sinf` argument is outside |x| <= 6.283186, the verified
  kernel domain.
- `Quaternion.to_axis_angle_for(libm, q) -> Maybe<(Vector3 & F32)>`
  normalizes quaternions with |w| > 1 as raymath does, then returns the axis
  `(x, y, z)/sqrt(1 - w*w)` (or `(1, 0, 0)` when that is at most 1e-6) and the
  angle `2*acosf(w)`; the pointers of the C API become the returned pair.
  `None` when the profile lacks `acosf`, or when w is outside [-1, 1] or NaN
  after normalization.

`QuaternionToEuler` stays **blocked**: it needs `asinf`, and glibc 2.39's
`e_asinf.c` carries Stephen Moshier's single-precision modifications under
LGPL-2.1+, which Jonlib (zlib) does not adapt without a project licensing
decision.

## Verification

`tools/quaternion_angle_probe.py` (gate `quaternion-angle`) compiles the
pinned `raymath.h` with contraction off, with `acosf` from the unmodified
glibc 2.39 source and `sinf` from the Arm sincosf model of
`tools/trig_probe.py`, and compares on CPU-1, CPU-2 and JavaScript:

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
