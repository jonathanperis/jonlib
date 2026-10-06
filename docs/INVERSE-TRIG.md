# Inverse-trigonometry compatibility gap

`QuaternionSlerp`, `QuaternionToAxisAngle` and `QuaternionToEuler` are
**blocked**, with no implemented mapping. They depend on native float
`asinf`/`acosf`, and no verified reference-compatible profile for those
functions exists yet. (The `atan2f` dependency of the angle APIs is handled by
explicit profiles; see [ANGLES.md](ANGLES.md).)

## Why the blocker exists

Bend's Base `F32.asin`/`F32.acos` primitives do not reproduce native libm bits,
and on the forced-Metal lane they also differ in signed zero. Retained examples
(native values from Apple arm64 libm):

| Operation | Input | Native bits | Base bits |
|---|---:|---|---|
| `asinf` | -1 | `bfc90fda` | `bfc90fdb` |
| `acosf` | -1 | `40490fda` | `40490fdb` |
| `asinf` | +1 | `3fc90fda` | `3fc90fdb` |
| `asinf` on Metal | -0 | `80000000` | `00000000` |

Two candidate replacements were evaluated and **not** adopted because they also
differ from the current native implementation:

- the published legacy Apple
  [asin](https://github.com/apple-oss-distributions/Libm/blob/17a5f9daa3f5679f7536b26f133b40cc078753c3/Source/Intel/asinf.s)
  and
  [acos](https://github.com/apple-oss-distributions/Libm/blob/17a5f9daa3f5679f7536b26f133b40cc078753c3/Source/Intel/acosf.s)
  algorithms by Eric Postpischil;
- idealized double-precision functions rounded to F32, even with endpoint
  adjustments.

Closing the gap requires a licensed, verified reference-compatible `asinf` and
`acosf` (per declared profile) with exact native comparisons; expected values and
comparisons are not relaxed in the meantime.

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

The API ledger counts no implementation for these three functions.
