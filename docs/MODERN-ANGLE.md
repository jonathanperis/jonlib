# Private glibc 2.41 atan2f kernel

`src/modern_angle.bend` is the scalar kernel behind the `Glibc241Libm{}`
angle profile. It implements the complete finite-input expression tree of the
pinned glibc 2.41 `e_atan2f.c`. Profiles, the public checked wrappers and host
profile selection are described in [ANGLES.md](ANGLES.md); this page covers the
private kernel only.

## Contract

```bend
checked(y_word: U32, x_word: U32) -> Maybe<U32>
traced(y_word: U32, x_word: U32) -> Packet
```

Inputs and result are raw IEEE binary32 encodings, in `atan2f(y, x)` argument
order. The contract is the pinned source's round-to-nearest-even result for
**every finite input pair**, including both signed zeros, every subnormal and
extreme finite ratios. Any NaN or infinity is rejected (`None`) before promotion
or reduction. Exceptions, errno, NaN payloads, other rounding modes and
performance are outside the contract.

The kernel is private: public code reaches it only through
`src/checked_angle.bend`, whose wrapper contract (finite components, zero-or-normal
intermediates and outputs) is narrower than this scalar contract. The Apple2007
and Sun 2.39 kernels and the legacy `*_for(Libm, …)` functions are
separate.

## Source identity and adaptation

The definition is the
[immutable glibc 2.41 source](https://github.com/bminor/glibc/blob/74f59e9271cbb4071671e5a474e7d4f1622b186f/sysdeps/ieee754/flt-32/e_atan2f.c):

- Release commit `74f59e9271cbb4071671e5a474e7d4f1622b186f`
- Git blob `82a0151293cda9cf89d6a18b6f8b35d4fdaeddd4`
- SHA-256 `96f9c81b6e870c256cc0757f6d88f5290ed35db8d5b640b9e757d6feca96ae38`
- Copyright (c) 2022–2024 Alexei Sibidanov and Paul Zimmermann (originally from
  the CORE-MATH project); the complete MIT permission notice and disclaimer are
  retained in `src/modern_angle.bend`, the reference files and
  [LICENSES/core-math-atan2f.txt](../LICENSES/core-math-atan2f.txt)

The Bend file is an adaptation: it computes on canonical binary64 words with the
checked private arithmetic in [BINARY64.md](BINARY64.md) and records diagnostic
traces. No coefficient approximation, native atan2 or FMA hook, or result
correction table is used. The seven numerator and seven denominator constants,
all 32 compensated high/low coefficient pairs and every offset/scaling constant
are kept as integer words.

The following source behaviour is explicit:

1. Input classification and the source's early-zero handling (a zero Y with
   negative nonzero X continues the ordinary reduction).
2. Literal reduction products, including the unused operand multiplied by zero
   before each sum, so signed-zero effects are preserved.
3. The two-sided exponent-distance rational guard and `z2`, `z4`, `z8`.
4. Each uncontracted rational multiply/add and the final numerator/denominator
   divide.
5. Quadrant sign multiplication, high offset and the low-bit ambiguity predicate.
6. Tiny fallback: FMA quotient residual, cubic correction, the literal gradual
   `z*e` product and unsigned raw binary64 increment/decrement (not `nextafter`).
7. General fallback: compensated quotient, squared double-double input, every
   Horner iteration, compensated final product and high/low quadrant
   reconstruction.
8. Direct binary32 narrowing, exact re-promotion, the final correction test, the
   exponent-only threshold, 1.25/0.75 scaling and the final single narrowing.

## Failure semantics

`Value` is `Good{binary64_words}` or `Failed{operation, operands}`. Every
primitive checks its own domain; a failure carries the failing operation id and
its exact input words and propagates with deterministic dependency-left
precedence (not a claim about C evaluation order). A failed calculation is never
replaced by zero, another profile or a clamped operand. `traced` returns the
final value, branch mask, reduction index, magnitude order and ordered
intermediate events; `checked` returns `None` for an input or arithmetic
rejection. Internal constructors and helpers are visible because of Bend's module
model; arbitrary constructed states are not a supported API.

[MODERN-ANGLE-BOUNDS.md](MODERN-ANGLE-BOUNDS.md) derives operand bounds for the
actual expression tree, showing that every finite RN input stays inside each
helper's domain (including the exact-zero cases, low-component cancellation and
the gradual tiny product). It is a written argument with exact finite coefficient
checks, not a machine-checked reachability theorem, and the standalone helper
domains are not general chaining guarantees. Any observed arithmetic rejection
for a finite input is therefore a gate failure to be diagnosed, not an accepted
result.

### Branches with no finite-input RN witness

Three source branches are implemented but are not reachable from finite inputs
under round-to-nearest-even, by written arguments in
[MODERN-ANGLE-BOUNDS.md](MODERN-ANGLE-BOUNDS.md#12-retained-branches-with-no-finite-input-rn-witness):

- **Tiny increment**: at the tiny boundary the quotient has at most 25
  significant bits, so the FMA residual is exactly zero; the cubic correction
  then makes `z*e` negative or negative zero.
- **Tiny non-boundary**: the ambiguity window and rational perturbation bounds
  place any non-boundary quotient too far from a 25-bit grid point.
- **Final correction guard false**: re-promoted nonzero normal `th` times
  `2^-60` is below half a binary64 ulp, so `th ± delta` rounds to `th`.

They are exercised only by synthetic helper controls, reported separately from
reachable cases.

## How it is verified

Gate `angle-kernels` (`tools/angle_kernel_probe.py`), which also checks the
Sun 2.39 kernel and the checked wrappers (see [ANGLES.md](ANGLES.md)):

- **Reference.** `tools/reference/modern_atan2f_glibc241.c` (the unmodified file)
  is compiled through small alias/header shims, and
  `tools/reference/modern_atan2f_adapted.c` (marked adaptation: finite-input
  rejection and observation-only tracing) is compiled with the trace driver
  `modern_atan2f_driver.c`. Flags are `-std=c11 -O2 -frounding-math
  -fno-fast-math -ffp-contract=off -fno-lto -fno-builtin-atan2f
  -fno-builtin-fma`; explicit `fma` calls go through a runtime libm pointer. The
  driver first qualifies the process: round-to-nearest, no FTZ/DAZ, true-FMA,
  direct-narrowing and gradual-underflow controls. The adaptation must equal the
  unmodified source for every finite input. The installed `atan2f`, called
  through a volatile pointer, is recorded but never defines the expectation.
- **Comparison.** For every corpus input the Bend `traced`/`checked` output is
  compared exactly with the reference: result word, branch mask, reduction index,
  magnitude order, the binary64 value before final narrowing and the ordered
  checkpoint trace (including both high/low results after each of the 31 Horner
  iterations and the literal tiny `z*e`, even when subnormal or signed zero).
  These checkpoints expose operation-order or branch defects that the final
  rounding could hide; they are not an event per primitive operation.
- **Corpus.** The historical `tools/angle_probe.py` sample set comes first,
  unchanged, and its pinned-source and Sun words must equal the frozen record
  `tools/reference/modern_atan2f_historical.json`. Further strata: signed zeros,
  axes, quadrants, finite boundary cross products, equal and adjacent magnitudes
  at every exponent, raw exponent-distance guard neighbours, subnormal bit
  patterns, common power-of-two rescaling, bit-stratified words, the minimum
  general ratio `(y, x) = (00000001, 0c800000)` and its negative-Y mirror, tiny
  products `y = 00000001` with `x = 75000000, 7b000000, 7b800000, 7f000000`,
  natively searched general-fallback inputs in
  `tools/reference/modern_atan2f_general_cases.json` (including both final
  correction scalings; retained as branch controls, never per-input patches),
  nonfinite rejections and the frozen scalar controls of
  [`angle_qualification_v1.json`](../tools/reference/angle_qualification_v1.json).
- **Required coverage.** Every source branch other than the three RN-unreachable
  ones must be hit, together with all eight reduction indices, both magnitude
  orders and tiny `z*e` products that are normal, subnormal and negative zero.
- **Synthetic controls.** Raw increment/decrement with carry/borrow, negative
  encodings, invalid primitive operands, dependency-left failure precedence and
  the RN-unreachable branch helpers are checked as separate internal controls.
- **Bounds.** Gate `modern-angle-bounds` runs `tools/modern_angle_bounds.py`,
  the exact finite checker for
  [MODERN-ANGLE-BOUNDS.md](MODERN-ANGLE-BOUNDS.md).

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only angle-kernels
```

`LAWS.bend` (checked through `PROOF.bend` by the `conformance` gate) adds
structural failure/rejection laws and concrete special/zero results. They do not
prove universal arithmetic, all finite atan2 values or the transcendental error
analysis.

## Known gaps

- Coverage is a stratified finite corpus plus written reachability arguments,
  not exhaustive input-pair execution.
- Forced-GPU execution and performance are not established; CI runs CPU and
  JavaScript lanes only.
