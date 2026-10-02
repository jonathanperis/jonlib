# Private bounded binary64 addition and subtraction

`src/binary64_add_sub.bend` provides the private entry points
`checked_add(ah, al, bh, bl)` and `checked_sub(ah, al, bh, bl)`, each returning
`Maybe<binary64_fma.Words>`. Arguments are canonical IEEE binary64 high/low U32
words. The exact real sum or difference is rounded **once**, to nearest with
ties to even.

Both operands must be signed zero or a normal binary64 value with unbiased
exponent in `[-900,130]`. Nonzero subnormals, infinities, NaNs and normals outside
that interval return `None`. Classification precedes arithmetic; a zero operand
does not bypass validation of the other operand. Subtraction inverts the right
operand's sign bit before the same checked addition, preserving its validity.

Addition of two zeros keeps their common sign, or gives +0 for mixed signs.
Exact cancellation of nonzero operands gives +0. Consequently `-0 - +0 = -0`,
while `-0 - -0 = +0`. No host rounding mode, floating-point exception, errno,
NaN payload, general underflow or other-rounding-mode behavior is promised.

This module has **no existing library consumers** and is not a public API.
Existing FMA, narrowing, float64, resize, projection and angle sources and their
contracts remain unchanged. The historical private resize addition's mixed-zero
behavior is not repaired or silently expanded here. Passing this independent
prerequisite does not resolve the strict native angle-profile mismatch.

## Standalone bounds

For a normal operand of unbiased exponent `E`, its magnitude is
`M*2^(E-52)`, with integer `2^52 <= M < 2^53`.

1. Every accepted operand is an integer multiple of `2^-952`
2. Its exact integer shift on that lattice is `E+900`, in `0..1030`
3. Every operand has magnitude below `2^131`, so every exact sum or difference
   has magnitude below `2^132`, or integer magnitude below `2^1084`
4. Every nonzero exact result has magnitude at least `2^-952`

Thirty-four U32 limbs provide 1088 bits, enough for each complete term and the
sum, including its carry. Exact cancellation therefore cannot overflow the
accumulator or create a nonzero binary64 subnormal. Final rounding cannot
underflow or overflow binary64. Adjacent normals at the domain's lowest exponent
attain the nonzero lattice floor, `2^-952`. Results may lie outside the input
exponent interval (for example the floor or the doubled largest input), so the
rectangle is not closed under chaining; every subsequent call must pass its own
input validation.

These are standalone handwritten integer/algebraic bounds derived from the
checked rectangle. They do not rely on, or mechanically prove, the reachability
of a future angle kernel.

## Implementation and reused invariants

The candidate imports `Base` and the unchanged private `binary64_fma.bend`.
It uses integer/Nat/Bool operations only, with no host F32/F64, FFI or native
arithmetic. Its own alignment fixes the width at 34 limbs; its own finishing
step uses lattice exponent offset `1023-952 = 71`.

The imported helpers have been inspected under these explicit invariants:

- `fit`, `prefix` and `shift_ready` operate on arbitrary lists; the bounded
  operand shift fits 1083 bits, so fitting to 1088 loses no significant bit
- `add`, `sub` and `order` traverse equal-length lists. Carry/borrow is detected
  through two wrapping U32 operations. The final carry/borrow is zero because
  the sum fits and subtraction always orders the magnitudes first
- `top`, `first3`, `window` and `normalize` are independent of accumulator
  width and scale. The leading index is at most 1083. A leading index below
  55 makes left normalization exact; otherwise only the final normalized
  56-bit window compresses discarded bits into a sticky bit
- `pack` expects 53 retained significand bits plus three rounding bits and a
  normal stored exponent. It rounds on tail greater than four, or tail equal
  to four with an odd retained significand, then handles a significand carry
- `valid` uses the new stored exponent interval `[123,1153]`; `significand`
  receives only a checked normal or signed zero

The FMA helper's fixed 29-limb alignment and `top+365` finish are never used.
No bit compression occurs before signed magnitude addition/subtraction and exact
cancellation. Bend visibility does not turn the internal helpers into supported
entry points. Only the two checked functions establish this contract.

## Verification and proof boundary

With the existing pinned toolchain, without installing or altering it:

```sh
python3 tools/binary64_add_sub_probe.py --bend-source "$BEND_SOURCE"
python3 -m unittest discover -s tests -v
bun "$BEND_SOURCE/bend2/main.ts" PROOF.bend --check-only
```

The primary oracle decodes exact Python `Fraction` operands, computes their sum
or difference and binary-searches adjacent binary64 values by exact rational
distance, resolving ties by encoding parity. It reuses the independently reviewed
rational decoder/neighbor search from the FMA oracle without changing its
semantics. It does not reproduce the candidate's lattice, limbs or final pack.
Signed-zero decisions are explicit because rational zero has no sign.

A separately compiled C oracle performs runtime addition/subtraction on volatile
inputs and converts words with `memcpy`. Qualification checks IEEE layout,
`FE_TONEAREST`, fixed exact controls, and control-register FTZ/DAZ/directed-rounding
bits. Compiler identity and flags are retained; unsupported contexts fail closed.

The deterministic corpus contains **47,464 observations per lane**: 23,732
addition and 23,732 subtraction cases, with 46,648 accepted results and 816
checked rejections. CPU-one-thread, CPU-two-thread and JavaScript each match the
entire exact corpus in 186 serial programs of at most 256 operations, with at
most 16 five-word records per output line. Coverage includes:

- Every accepted exponent in each sign, operand position and operation
- All zero-sign pairs and operand orders, exact nonzero cancellation and neighbors
- Even/odd ties, adjacent words, binade and doubleword carries, and long borrows
- Extreme gaps, every significand bit and bit hole, largest/smallest terms,
  and adjacent minimum-binade values across each bit/carry boundary
- All 55 left-normalization shifts and 32 right-window residual counts
- Each rejected classification and normal boundary in either operand, including
  positive-zero, negative-zero and nonzero counterpart controls

Framing checks every ID, operation kind, tag, U32 type, count and payload shape.
Old success and compiled outputs are invalidated before use. Inputs, native and
candidate sources/binaries, and lane stdout/stderr are hashed when consumed and
revalidated at acceptance, along with source/harness/compiler/overlay/runtime
identity. The checked run retains **52 source/dependency hashes and 2,066
artifact hashes**. All **169 repository Python tests** pass, including 34 focused
oracle, malformed-output, qualification, stale-output and drift tests.

The complete proof entry point includes 23 prior laws plus eleven new laws:
two structural branch/definition equalities and nine concrete zero-sign,
cancellation, tie-parity, lattice-floor and largest-carry results. These proofs
do **not** establish arbitrary accumulator or rounding correctness. Exact
differential tests and numerical bounds supply separate complementary evidence.

Independent read-only review regenerated every input and candidate program,
recomputed all rational expectations, replayed all native and candidate outputs,
and verified the source/artifact hashes, preserved regressions and unchanged API
statuses. It found no blocking findings and cleared this private checkpoint.

The checked checkpoint and regression outcomes are recorded in
[durable evidence](evidence/binary64-add-sub.json). No GPU, hosted execution,
exhaustive input coverage or performance parity is claimed.

## Remaining kernel work

See [ANGLE-PLAN.md](ANGLE-PLAN.md). Word stepping, the complete pinned modern
scalar kernel and its two fallbacks, wrapper domains, independent native-profile
qualification and forced-device/resource evidence remain open. The tiny branch's
`z*e` multiplication genuinely reaches subnormal and signed-zero results; a
literal port requires gradual underflow, or an independently justified narrower
RN result-bit predicate. This helper must not be wired into existing consumers
as a side effect of this prerequisite.
