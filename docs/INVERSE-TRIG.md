# Inverse-trigonometry compatibility gap

`QuaternionSlerp`, `QuaternionToAxisAngle` and `QuaternionToEuler` remain blocked
pending verified native float `asin`/`acos` profiles. The existing atan2 profile
passes; these remaining dependencies have distinct rounding behavior.

The pinned Base primitives produced 10 mismatched CPU/JavaScript words and 286
mismatched forced-Metal words in 572 results over 286 unique finite F32 inputs.
The native oracle uses volatile function pointers, preventing builtin constant
folding from replacing actual `asinf`/`acosf` calls.

Retained Apple arm64 examples include:

| Operation | Input | Native bits | Base bits |
|---|---:|---|---|
| `asinf` | -1 | `bfc90fda` | `bfc90fdb` |
| `acosf` | -1 | `40490fda` | `40490fdb` |
| `asinf` | +1 | `3fc90fda` | `3fc90fdb` |
| `asinf` on Metal | -0 | `80000000` | `00000000` |

An independent evaluation of the published legacy Apple
[asin](https://github.com/apple-oss-distributions/Libm/blob/17a5f9daa3f5679f7536b26f133b40cc078753c3/Source/Intel/asinf.s) and
[acos](https://github.com/apple-oss-distributions/Libm/blob/17a5f9daa3f5679f7536b26f133b40cc078753c3/Source/Intel/acosf.s)
mathematical descriptions by Eric Postpischil
also differed from the current native implementation in 719 asin and 737 acos
results over a separate 4,128-input diagnostic corpus. Substituting idealized
double-precision functions, even with endpoint adjustments, still differed in
65 asin and 46 acos results. These alternatives were not adopted.

```sh
python3 tools/inverse_trig_probe.py --bend-source "$BEND_SOURCE" --gpu
```

Set the checkout variable as described in [README.md](../README.md#requirements).
The command records `.build/inverse-trig-probe/results.json`; it reports a
diagnostic result, not a passing Jonlib implementation. Hosted CI retains
per-host evidence. Exact comparisons remain in place, and the ledger counts no
implementation for these blocked APIs.
