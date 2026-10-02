# Private bounded binary64 fused multiply-add

`src/binary64_fma.bend` provides the private entry point
`checked(ah, al, bh, bl, ch, cl) -> Maybe<Words>`, where every argument is a U32
and `Words{high, low}` is the canonical IEEE binary64 result encoding. The exact
real value `a*b+c` is rounded **once**, to nearest with ties to even.

The checked domain is deliberately asymmetric:

- `a` and `b`: either signed zero or a normal binary64 value with unbiased
  exponent in `[-277,127]`
- `c`: either signed zero or a normal binary64 value with unbiased exponent in
  `[-554,255]`
- Any nonzero subnormal, infinity, NaN or normal outside those intervals returns
  `None`; all three inputs are validated before arithmetic begins

Zero signs are part of the contract. The product sign is XOR. A zero product
plus zero `c` retains their common sign, or returns +0 when the signs differ.
Exact cancellation of opposite nonzero values returns +0. The entry point does
not consult the host rounding mode and makes no exception, errno, NaN-payload,
other-rounding-mode or general gradual-underflow FMA claim.

This module is not a public API and has **no existing image/math API consumers**.
The separate private [add/subtract prerequisite](BINARY64-ADD-SUB.md) now imports
its width-independent internal primitives under explicitly reviewed invariants;
the private [gradual-output product](BINARY64-GRADUAL-MULTIPLY.md) separately
reuses its exact product/window primitives. Neither use promotes those
primitives to supported entry points.
Existing `float64_ops`, `float64`, `resize_numeric`, binary64 narrowing, F32 FMA,
angle kernels, profile selectors and expected results remain unchanged. Its
successful verification does not resolve the current strict native angle failure.

## Standalone numerical bounds

These bounds follow solely from the checked rectangle. They do not depend on
an unimplemented angle kernel or a claim that all its reachable states have
already been verified.

For a normal input with unbiased exponent `E`, write its magnitude as
`M*2^(E-52)`, with integer `2^52 <= M < 2^53`.

1. The exact product has at most 106 significand bits. Its finest possible
   quantum is `2^(-277-52-277-52) = 2^-658`
2. The finest addend quantum is `2^(-554-52) = 2^-606`, itself an integer multiple
   of `2^-658`
3. `abs(a*b) < 2^256` and `abs(c) < 2^256`, so `abs(a*b+c) < 2^257`
4. Therefore the exact signed sum is an integer multiple of `2^-658`; every
   nonzero sum has magnitude at least `2^-658` and its integer magnitude is
   below `2^915`

A 29-U32 magnitude has 928 bits, so it holds both aligned terms and their sum
without overflow. Cancellation is exact and cannot produce a nonzero binary64
subnormal. Final rounding cannot underflow or overflow binary64. These are
handwritten integer/algebraic arguments, complemented by tests; they are not a
machine-checked universal arithmetic theorem.

## Implementation and rounding

The implementation imports only `Base` and uses U32/Nat/Bool operations. No F32,
host F64, native FMA, compiler hook or unsafe operation appears in the candidate.

- A 53-step shift/add computes the exact 106-bit significand product in four U32
  limbs. The working product stays within 128 bits
- Magnitudes are little-endian immutable 29-limb lists in units of `2^-658`
- The product shift is `Ea+Eb+554` in `0..808`; the addend shift is `Ec+606` in
  `52..861`. Signed zeros use shift zero and significand zero
- Alignment uses whole-limb prefix zeros and a residual shift of `1..31` bits,
  explicitly handling shift zero. At most 915 bits are needed after addition
- Carry and borrow are detected after each of two wrapping U32 operations
- Equal-sign terms add. Opposite-sign terms compare from the high limb, then
  subtract the smaller magnitude from the larger. Equal magnitudes select +0
- No alignment or cancellation step compresses discarded bits into a sticky bit

After cancellation, let `t` be the index of the magnitude's leading one. The
unrounded stored exponent is `t+365`, since the lattice scale is `2^-658`.
Normalize to a 56-bit window, retaining the 53 significand bits and three
rounding bits. Whole discarded limbs and low bits of the boundary limb become
a sticky bit **only at this final step**. If `t<55`, left normalization is exact.
Increment the retained significand exactly when the low three-bit tail exceeds
4, or equals 4 with an odd retained significand. A rounding carry shifts the
significand right and increments the exponent. Result words are packed directly.

Internal list/product/packing helpers assume these invariants. Bend does not
provide opacity here; their visibility does not make them supported entry points.
Only `checked` establishes the bounds.

## Verification and proof boundary

Run with the existing pinned toolchain; do not install or modify it:

```sh
python3 tools/binary64_fma_probe.py --bend-source "$BEND_SOURCE"
python3 -m unittest discover -s tests -v
bun "$BEND_SOURCE/bend2/main.ts" PROOF.bend --check-only
```

The primary oracle decodes canonical words as Python `Fraction`, computes the
exact rational product and sum, and binary-searches ordered binary64 neighbors.
It compares exact rational distances and resolves a tie with the even encoding.
This is structurally separate from the candidate's fixed-width accumulator,
normalization and pack. Signed-zero decisions are explicit because rational
zero itself has no sign.

A separately compiled C oracle uses runtime libm `fma`, volatile inputs and
`memcpy` word conversion. It checks IEEE layout, selects and verifies
`FE_TONEAREST`, records compiler/flags/control-register state and rejects
FTZ/DAZ or directed rounding. Known exact controls qualify the oracle before the
corpus. Native disagreement with the independent rational oracle fails the run.

The deterministic corpus has **11,038 observations per lane**: 10,726 accepted
FMA results and 312 checked rejections. It includes the exact residual
`(1+2^-52)*(1-2^-52)-1 = -2^-104`, both halfway parity choices, the reachable
rectangle floor
`((1+2^-52)*2^-277)^2 - (1+2^-51)*2^-554 = 2^-658`, all zero-sign triples,
nonzero cancellation, long carry/borrow, exponent gaps, extrema, deterministic
bit-stratified words and rejection boundaries in every operand. Every allowed
exponent is sampled in both signs, separately in each operand. Dedicated controls
exercise all 55 left-normalization shifts, all 32 residual right-shift counts,
retained-significand carry and the full cancellation/long-borrow paths. Every result is
checked on CPU one-thread, CPU two-thread and JavaScript, in 44 programs of at
most 256 operations and output lines of at most 16 records, with strict framing. Retained artifacts include source/input/oracle hashes,
all native/candidate stdout, build metadata and final source/toolchain drift
checks. Candidate CPU builds explicitly select the recorded supported Clang via
`CC`, overriding unrelated ambient compiler settings. Twenty-five focused Python
tests exercise the oracle, framing, malformed records,
qualification, compiler selection, stale compilation outputs and drift checks.
The recorded FMA checkpoint passed all 135 repository Python tests.

At the recorded FMA checkpoint, the complete `PROOF.bend` entry point checked
the 13 existing laws plus ten new laws: shift zero/successor structure, explicit rejection, and seven concrete
arithmetic equalities. These proofs do not establish arbitrary product,
accumulator or rounding correctness. The mathematical argument, independent
oracle corpus and regression evidence complement those limited proofs.

The checked checkpoint is recorded in
[durable evidence](evidence/binary64-fma.json). No GPU, hosted execution,
performance parity, exhaustive input coverage or modern angle-profile completion
is claimed.

## Remaining scope

See [ANGLE-PLAN.md](ANGLE-PLAN.md). A [private bounded add/subtract prerequisite](BINARY64-ADD-SUB.md) is now
implemented separately, as are the [checked normal operations and word adapters](BINARY64-OPS.md).
A private [gradual-output product](BINARY64-GRADUAL-MULTIPLY.md) now provides
the isolated tiny-product arithmetic. The full pinned modern scalar kernel,
its fallbacks, checked-domain integration, wrapper domains, native qualification
and forced-device/resource evidence remain future work.
This rectangle excludes arbitrary binary64 underflow and subnormal inputs; it
must not be silently widened or substituted for existing numeric contracts.
