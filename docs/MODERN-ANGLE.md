# Private pinned finite binary32 atan2 kernel

The private `src/modern_angle.bend` implements the complete finite-input scalar
expression tree from the pinned glibc 2.41 `e_atan2f.c`. Its entry point is
`checked(y_word: U32, x_word: U32) -> Maybe<U32>`. The inputs and result are raw
IEEE binary32 encodings, in that argument order. The intended numerical contract
is the pinned source's round-to-nearest-even result for every finite input pair,
including both signed zeros, every subnormal and extreme finite ratios. Any
NaN or infinity is rejected before promotion or reduction.

This implementation is **private, with exact scoped CPU/JavaScript evidence**. No existing
image/math API imports it. Apple and GNU/Sun kernels, public defaults, selectors,
fixtures, expected words and tolerances are unchanged. The canonical native-angle
failure remains a failure. This is not an `Angle.Reference` introduction or a
public-profile promotion. Exceptions, errno, NaN payloads, other rounding modes,
GPU execution, performance and vector-wrapper domain expansion are excluded.

## Source identity and adaptation

The definition is the [immutable glibc 2.41 source](https://github.com/bminor/glibc/blob/74f59e9271cbb4071671e5a474e7d4f1622b186f/sysdeps/ieee754/flt-32/e_atan2f.c):

- Release commit `74f59e9271cbb4071671e5a474e7d4f1622b186f`
- Git blob `82a0151293cda9cf89d6a18b6f8b35d4fdaeddd4`
- SHA-256 `96f9c81b6e870c256cc0757f6d88f5290ed35db8d5b640b9e757d6feca96ae38`
- Copyright (c) 2022–2024 Alexei Sibidanov and Paul Zimmermann; complete MIT
  permission/disclaimer retained in the candidate, reference files and
  [license notice](../LICENSES/core-math-atan2f.txt)

The candidate uses canonical binary64 words and explicit checked Bend arithmetic.
No coefficient approximation, native atan2 hook, native FMA hook or result
correction table is used. The exact seven numerator/seven denominator constants,
all 32 compensated high/low pairs and every offset/scaling constant are retained
as integer words. A separately frozen reference constant manifest is checked
against the candidate; it is not generated from candidate values.

The following source behavior remains explicit:

1. Input classification and the source's early-zero handling
2. Literal reduction products, including the unused operand multiplied by zero
   before each sum, so signed-zero effects are preserved
3. The two-sided exponent-distance rational guard and `z2`, `z4`, `z8` evaluation
4. Each uncontracted rational multiply/add and final numerator/denominator divide
5. Quadrant sign multiplication, high offset and low-bit ambiguity predicate
6. Tiny FMA quotient residual, cubic correction, literal gradual `z*e` and
   unsigned raw64 increment/decrement; these steps are not `nextafter`
7. General compensated quotient, squared double-double input, every Horner
   iteration, compensated final product and high/low quadrant reconstruction
8. Direct binary32 narrowing, exact re-promotion, the final correction test,
   exact exponent-only threshold, 1.25/0.75 scaling and final single narrowing

## Checked arithmetic and failure semantics

The existing private helpers are imported unchanged under their own contracts:
[narrowing](BINARY64-NARROW.md), [FMA](BINARY64-FMA.md),
[addition/subtraction](BINARY64-ADD-SUB.md), [normal operations](BINARY64-OPS.md)
and [gradual product](BINARY64-GRADUAL-MULTIPLY.md).

`Value` is either `Good{binary64_words}` or `Failed{operation,operands}`. Every
primitive checks its domain and preserves a failing operation ID and its exact input words,
using deterministic dependency-left precedence rather than a claim about
temporal C evaluation order. No failed calculation is replaced by zero, an old angle
profile or a clamped operand. The private `traced` diagnostic returns the final
value, branch mask, reduction index and ordered intermediate events; `checked`
returns `None` for an input or arithmetic rejection. Internal constructors and
helpers are visible because of Bend's module model; that visibility does not
make arbitrary constructed states a supported public API.

The [written domain analysis](MODERN-ANGLE-BOUNDS.md) establishes operand bounds
for the actual expression tree. Its exact finite coefficient check is retained
as `tools/modern_angle_bounds.py`. The analysis distinguishes exact-zero cases,
low-component cancellation and the gradual tiny product. It is a handwritten
algebraic argument with exact finite checks, not a machine-checked universal
reachability theorem. In particular the standalone helper domains are not
arbitrary chaining guarantees. Any observed finite-kernel rejection is a gate
failure requiring diagnosis before a helper contract could be reconsidered.

## Independent reference and traces

`tools/reference/modern_atan2f_glibc241.c` is the exact original file. It is
compiled independently through a compatibility shim. The separately marked
`modern_atan2f_adapted.c` adds finite-input rejection and observation-only tracing.
Original/adapted/shim hashes, compiler identity, flags, binaries and complete
outputs are retained. The adapter's results must equal the separately compiled
original for every accepted corpus pair. Explicit `fma` remains fused and all
ordinary expressions use disabled contraction/fast-math/LTO.

Native preflight verifies IEEE binary32/binary64 layout/evaluation, nearest-even,
subnormal support and architecture control state, including FTZ/DAZ. Unsupported
or inconsistent contexts fail closed. The actual installed `atan2f` is called
through a separate runtime function pointer and recorded independently. Its
agreement or disagreement does not select a profile and does not redefine the
pinned-source expectation.

The candidate and pinned adapter compare complete output words, branch masks,
quadrant/reduction metadata and ordered binary64 checkpoints. The general path
includes both high/low results after every one of the 31 Horner iterations.
The tiny trace includes literal `z*e` even when it is subnormal or signed zero.
These checks can reveal operation-order or branch defects hidden by the final
binary32 rounding. They are deliberately scoped checkpoints, not an event for
every primitive operation or exception flag.

## Coverage and proof boundary

The focused gate retains all 1,086 prior native-angle inputs in their original
order and the previously observed 178 native/Sun differences. Independent
controls add zero signs, axes, quadrants, equal magnitudes, subnormal/normal and
extreme-finite values, exponent-distance neighbors, common-scale families and
deterministic stratified words. General minimum-ratio controls include
`(y,x)=(00000001,0c800000)` and its negative-Y mirror. Tiny controls retain
`y=00000001` with `x=75000000,7b000000,7b800000,7f000000`.

Native-only bounded generators search additional rare general-fallback inputs,
including final correction-up/down cases. Retained input witnesses are branch
controls, never per-input result patches. Search bounds and achieved source
branches are recorded, without an exhaustive claim. Synthetic internal controls
for otherwise unhit paths are labelled separately and do not count as reachable
kernel branch coverage.

The tiny increment and tiny nonboundary paths are retained. There are separate
[written RN reachability arguments](MODERN-ANGLE-BOUNDS.md#12-retained-branches-with-no-finite-input-rn-witness),
independently reviewed against the exact source constants. At the tiny boundary,
the binary64 quotient has at most 25 significant bits, so multiplication by a binary32 denominator has at most 49. A nonzero
quotient residual cannot fit the binary64 division rounding-error bound; the
boundary quotient is exact. The cubic correction then makes `z*e` nonpositive,
including negative zero. The final correction guard's false side likewise has
no intended RN witness: re-promoted nonzero normal binary32 `th` times `2^-60`
is smaller than half a binary64 ulp. The first-pass ambiguity window and rational
perturbation bounds also exclude tiny nonboundary: its distance would be less than 15 binary64 ulps from a
25-significant-bit grid point, while a nonexact binary32 ratio requires more than
16. These are written RN arguments, not conclusions from empty branch counters
or mechanically checked universal theorems.

`LAWS.bend`/`PROOF.bend` include structural rejection/propagation laws and concrete
special/zero results. They do not prove universal arithmetic, all finite atan2
values or the entire transcendental error analysis. Source parity, native
qualification, written bounds, scoped proofs and exact finite differential
coverage are separate evidence.


## Verified focused result

All **8,317 complete observations** match the independently compiled pinned
source on CPU-one-thread, CPU-two-thread and JavaScript: 8,263 finite results
and 54 nonfinite rejections. There are no arithmetic-domain rejections among the
finite cases. Result classes are 8,065 normal F32 values, 78 subnormals and 120
signed zeros. Each lane checks 567,870 framed U32 words and 121,148 ordered
binary64 trace events, in 33 serial programs of at most 256 inputs.

Actual source coverage includes 6,077 rational paths, 2,156 exponent-distance
shortcuts, 30 early-zero returns, 987 ambiguity hits, 718 tiny decrements and
269 general fallbacks. General corrections include 16 upward and 253 downward
scalings. Tiny literal products include 710 normals, four subnormals and four
negative zeros. All eight reduction indices, both magnitude orders and all four
sign quadrants occur. The three written RN exclusions above remain separate
from actual-hit counters.

A separate **28-control** internal gate also passes all three lanes: ten
successful helper values and eighteen explicit rejection/propagation records,
including raw increment/decrement, carry/borrow, negative encodings, invalid
primitive operands, dependency-left error precedence and the excluded branch
helpers. Its 379 framed U32 words per lane do not count as reachable scalar cases.

All **271 Python tests** pass, including 32 new focused methods covering strict
framing, malformed/missing/reordered data, exact constant mutations, required
coverage, native qualification/final context, stale outputs and source drift.
Complete `PROOF.bend` checks **84 laws**: 71 existing, five new structural
failure/rejection laws and eight concrete exceptional/zero controls. These are
scoped proofs, not universal atan2 or arithmetic theorems.

The qualified source, instrumented adaptation and runtime glibc 2.41 agree on
all finite corpus outputs. Separately compiled Clang 19.1.7 and GCC 14.2.0
reference processes agree on every result, branch, final64 and checkpoint.
RN/FTZ/DAZ checks pass with final MXCSR 8114; the low status bits are not an
exception-flag contract. Libc package-manager identity was unavailable and is
recorded as such; the runtime version and loaded atan2/FMA library hashes are
retained. The focused report revalidates 66 source/dependency hashes and 408
artifact hashes.

The retained nineteen rare-path seeds regenerate from a bounded native-only
100-million-trial uniform search (three hits) and 100,000 midpoint proposals
(17,809 general hits, 541 upward corrections; sixteen retained seeds). A separate
50-million-trial tiny search observes 6,250,036 tiny hits, all boundary. These are
input-discovery diagnostics, not additional Bend parity observations or a proof
from absence. Exact source snapshots and command/output hashes are retained.

A measured 256-case generic serial program compiled in 15.06 seconds with
approximately 971 MiB peak child RSS; the complete focused gate took 562.703
seconds. These are local harness/resource observations, not library or device
performance parity. Final regression/review status is in
[durable evidence](evidence/modern-angle.json).

## Reproduction and remaining integration

Use the existing pinned toolchain without updating or altering it:

```sh
python3 tools/modern_angle_bounds.py
python3 tools/modern_angle_probe.py --bend-source "$BEND_SOURCE"
python3 -m unittest discover -s tests -v
bun "$BEND_SOURCE/bend2/main.ts" PROOF.bend --check-only
python3 tools/conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 tools/check_project.py
```

The focused runner invalidates old success, removes stale compiler outputs,
checks strict IDs/types/counts/shapes/trace order, retains all stdout and hashes
source/toolchain/input/program/native/build/output artifacts when consumed and
again at acceptance. Programs are generated and run in bounded serial chunks
on CPU-one-thread, CPU-two-thread and JavaScript.

A finite scalar kernel does not establish vector dot/cross/subtraction/length
intermediate domains, wrapper output profiles, public native-profile selection,
forced-device resource behavior or performance. `ANGLE_QUERIES` continues its
existing routing until a separate independently qualified angle-selector slice.
See [ANGLE-PLAN.md](ANGLE-PLAN.md) for the remaining integration and device work.
