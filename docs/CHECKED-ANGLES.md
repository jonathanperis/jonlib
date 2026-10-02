# Explicit checked angle references

Jonmath exposes a separate `Angle.Reference` with `Apple2007AngleRn{}`,
`Sun239AngleRn{}` and `Glibc241AngleRn{}`. These name versioned source/numerical
contracts, not an automatically detected host and not universal transcendental
accuracy. Native selection is an independent [qualification](ANGLE-QUALIFICATION.md).
The current metadata implementation supports Linux glibc ELF only; historical
Apple/Sun source evidence is not fresh qualification of those hosts.

The new entry points are:

```bend
M.Vector2.angle_with_reference(reference, left, right) -> Maybe<F32>
M.Vector2.line_angle_with_reference(reference, start, end) -> Maybe<F32>
M.Vector3.angle_with_reference(reference, left, right) -> Maybe<F32>
```

Each requires `M.Angle.Reference` explicitly. `Some` contains exact F32 bits;
`None` rejects the stated domain or propagates checked scalar failure. The modern
branch uses `src/modern_angle.bend` and reconstructs its word as F32 without an
arithmetic conversion. The Apple and Sun branches invoke the unchanged legacy
scalar algorithms only after wrapper checks. No failure selects another profile,
clamps a result or substitutes zero.

The old `angle`, `line_angle` and `*_for(Gradient.Reference, ...)` functions keep
their signatures, arithmetic, defaults and meaning. They are not implemented in
terms of these checked APIs. No `Gradient.Reference` conversion or implicit
`Angle.Reference` default exists. `AccurateGradient` still selects the old Apple
algorithm and `GnuGradient` still selects the old Sun algorithm.

## Precisely bounded wrapper domain

All original components must be finite. Subnormal **inputs** are allowed if every
derived operation satisfies the contract. Every derived intermediate and scalar
output must be either signed zero or normal finite binary32. Finite nonzero
subnormal intermediates and outputs are rejected. Correct underflow to signed
zero is allowed; acceptance does not authorize FTZ/DAZ arithmetic. Native
qualification separately verifies gradual arithmetic and round-to-nearest-even.

The source-order uncontracted F32 operations are checked immediately, before
any dependent operation executes:

- Vector2 angle: the two dot products, their sum, the two determinant products,
  their difference, the selected scalar output
- Line angle: `end.y-start.y`, then `end.x-start.x`, the selected scalar output,
  then true sign-preserving unary negation and its output
- Vector3 angle: six cross-product products; three ordered differences; each
  component square; the two left-associated sums; nonnegative square (either
  zero sign allowed); square root and its result; three dot products; the two
  left-associated sums; the selected scalar output

Products multiplied by zero are retained. No reassociation, fused wrapper
multiply/add, early zero-term elimination, or unconditional invalid square-root
computation is part of this profile. Internal stage IDs support diagnostic
probes; they are not a new public error API.

The checked failure is an explicit Bend adaptation. It is not a claim that native
raymath rejects invalid inputs. `src/modern_angle.bend` accepts a broader finite
scalar domain, including subnormal outputs; that does not widen this wrapper
contract. Errno, exception flags, NaN payloads, other rounding modes, contracted
variants, unqualified hosts and device/performance parity remain outside scope.

## Canonical observation and failure handling

Canonical angle generation requires an independent explicit angle selection.
The runner freshly qualifies the native pointer, original literal canonical
raymath calls and runtime original wrappers against independently frozen controls
before generating a candidate. The same choice is used for CPU, JavaScript and
forced-device source generation. Gradient, rotation, extrema and spline routing
is separate and unchanged. A supported name alone is not evidence of host
qualification; recorded results retain the complete fresh receipt.

Native prechecks enforce the domain above, then the unchanged original raymath
function supplies the observed `float_bits` value. The ordered validation mirror
is not a replacement numerical oracle or instrumentation of hidden optimizer
temporaries. The fixture data/schema, observation locations, exact comparisons,
±32767 canonical input bounds and canonical compiler flags are unchanged.

A rejected checked angle becomes a harness-local `AngleRejected` error and exits
through `IO.die`. It never writes a sentinel pixel: later clear/overwrite
operations cannot erase a prior failure. Existing public `Surface.Error` is
unchanged. A separate raw-word probe covers values outside canonical fixture
bounds, including output-only subnormal line angle `(0,0) -> (2^127,1)`.

## Verification boundary

The focused gate records accepted native words, adapted rejection stages,
checked-public results and unchanged legacy/default compatibility separately.
It uses bounded serial programs on CPU one/two threads and JavaScript, with
strict record tags, IDs, shape/type/count checks and fresh source/artifact hashes.
Synthetic invalid-square and injected-scalar-failure checks are labelled internal,
not counted as valid-input native raymath observations.

The eleven new laws cover structural rejection/propagation, unchanged defaults
and checked scalar result handling. Together with the prior 84 laws the complete
`PROOF.bend` checks 95 laws. This is not a universal arithmetic or transcendental
proof. The exact recorded lane/canonical results are summarized below and linked to
their separate evidence; no new GPU or hosted result is claimed here.

## Recorded Linux CPU/JavaScript result

The [raw-wrapper gate](evidence/checked-angle-wrappers.json) passes **428 raw
controls and 45 separate synthetic helpers on each of CPU-one-thread,
CPU-two-thread and JavaScript**. The raw corpus is 205 unchanged independently
frozen controls, 96 signed-zero permutations, 84 nonfinite input-field controls
and 43 directed arithmetic/domain cases. It is hash-pinned before candidate
execution. Modern outcomes are 310 accepted values (196 normal and 114 signed
zeros) and 118 checked rejections: 84 original-input, 33 intermediate and one
output-only. The 3,801 observed native stage/value pairs comprise 3,396 pre-scalar
intermediates checked against independent exact-rational rounding, 311 scalar
values cross-checked against the pinned source and 94 exact line negations.
Those mirror observations do not claim access to optimizer-internal temporaries.

Every raw case compares the modern private diagnostic and public Maybe result,
plus both historical public checked results. The 311 cases reaching scalar
inputs additionally compare unchanged Apple/Sun legacy functions and Apple
convenience defaults; this is compatibility evidence, not new Apple-host parity.
The 45 helper controls comprise four accepted square roots and 41 rejection or
propagation checks. The eight serial programs use at most 64 raw rows each.
Each lane checks 5,992 framed raw words and 180 separately framed helper words.

The FMA-sensitive determinant remains positive zero. Directed controls distinguish
both three-term association orders in the final native angle. The output-only
line control produces original native `80400000` and checked `None`; the smaller
tiny-result line is accepted with `80000000`. Hidden subnormal products,
subnormal cancellation, overflowing products/sums/differences, length-square
failures, accepted subnormal inputs and underflow to zero are covered.

The [complete canonical record](evidence/checked-angle-canonical.json) passes
261 unchanged scenarios and every one of 40,101 output words per lane, plus all
other observed fields, 333 QOI bytes and 23 palette words. Ownership,
transformation and decoding contracts, all three PPM examples, QOI file roundtrip
and missing/malformed/oversized-file controls pass. Six actual fatal-error runs
(two clear/overwrite cases on three lanes) each exit nonzero and emit no success
row. No sentinel-pixel convention is used.

All 1,086 historical scalar inputs and their complete native/Sun records remain
unchanged, including all 178 differences. The strict old native probe continues
to fail on this modern host. CI treats only its exact frozen, freshly rebuilt
historical failure as a legacy-compatibility result; crashes, stale outputs,
changed words or other failure categories fail the workflow. The mandatory new
canonical gate remains an independent fresh-qualified full comparison.

The [integration record](evidence/checked-angles.json) separates fresh checks,
prior unchanged private-arithmetic evidence, independent reviews and remaining
limits. The local focused gate took 202.412 seconds; this is harness timing,
not library/device performance parity. No hosted or forced-GPU run is claimed.

```sh
source /path/to/existing/jonlib-toolchain/activate.sh
python3 tools/angle_manifest_audit.py
python3 tools/angle_reference.py --raylib-source "$RAYLIB_SOURCE" \
  --library .build/raylib/raylib/libraylib.a
python3 tools/checked_angle_probe.py --bend-source "$BEND_SOURCE" \
  --raylib-source "$RAYLIB_SOURCE" --library .build/raylib/raylib/libraylib.a
python3 -m unittest discover -s tests -v
bun "$BEND_SOURCE/bend2/main.ts" PROOF.bend --check-only
python3 tools/conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 tools/api_plan.py check
python3 tools/check_project.py
```
