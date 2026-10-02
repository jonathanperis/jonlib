# Private checked normal binary64 operations and word adapters

`src/binary64_ops.bend` provides isolated, checked canonical high/low U32
boundaries around the unchanged `float64_ops.bend` multiplication and division.
Results are `Maybe<binary64_fma.Words>`, rounded once to nearest, ties to even.
This is a conservative standalone normal-result contract, **not general
binary64 arithmetic** and not a proof of a future kernel's reachable domains.

## Checked arithmetic domains

Let `E` be the unbiased exponent of a nonzero normal operand.

- `checked_multiply(ah, al, bh, bl)`: each operand is signed zero or normal with
  `E` in `[-554,127]`. When both are nonzero, require `Ea+Eb` in `[-833,127]`
- `checked_divide(ah, al, bh, bl)`: numerator is signed zero or normal with `E`
  in `[-225,127]`; denominator must be **nonzero normal** with `E` in
  `[-149,127]`. A nonzero numerator additionally requires `Ea <= Eb`

Both inputs are validated before any zero shortcut. All nonzero subnormals,
NaNs, infinities, out-of-range normals and violated pair guards return `None`.
A zero divisor returns `None`, including every sign of `0/0`. Signed zero
results use the operands' sign XOR. No ambient rounding mode, errno, exception
flags or NaN-payload contract is provided.

The multiplication stored-exponent interval is `[469,1150]`, with nonzero pair
sum `[1213,2173]`. Division uses `[798,1150]` and `[874,1150]`, plus a stored
exponent comparison and explicit nonzero divisor check. The two-input guards
are not rectangular arithmetic closure guarantees: validate each later operation
independently when chaining these helpers.

## Reused invariants and standalone bounds

For a canonical nonzero normal input, write its magnitude as
`M * 2^(E-52)`, with `2^52 <= M < 2^53`. `float64.number` by itself does not
validate these arithmetic requirements. The checked boundary establishes them
before calling either legacy operation. Existing implementations and consumers
are byte-for-byte preserved.

Multiplication retains the exact 106-bit product in four U32 limbs through its
53 shift/add iterations. Its leading bit is at index 104 or 105. Only final
normalization jams discarded bits into the three-bit rounding window; the
existing nearest-even round and carry are applied once. The accepted exponent
sum places every nonzero rounded result in `E in [-833,128]`. At the upper edge,
each significand is at most `2-2^-52`, so their product is at most
`4-2^-50+2^-104`, too far below 4 to round across that binade. Thus there is no
binary64 underflow or overflow, including a rounding carry.

Division compares the normalized mantissas. If the numerator is smaller it is
doubled once; this suffices because their ratio is strictly between one half
and two. After subtracting the divisor, the remainder is in `[0,N)`. Each of
52 quotient steps doubles the remainder and subtracts `N` if necessary, keeping
that invariant. The exact final remainder is compared as `2*R` with `N`, with
odd-quotient tie resolution. Intermediate remainder values fit below `2^54`.
The exponent difference is in `[-352,0]`, with at most one normalization decrease,
so every nonzero rounded result has `E in [-353,0]`. The largest mantissa ratio,
`(2^53-1)/2^52`, is already representable below 2, so rounding cannot produce 2.

Within this checked result range, an exact division midpoint between adjacent
normal values cannot arise from two normalized binary64 operands: the odd
numerator of a reduced normal midpoint has at least 54 bits,
while the odd numerator of a reduced `M/N` ratio has at most 53. Multiplying by a
power of two does not change that odd numerator. Near-midpoint tests therefore
exercise both rounding sides without claiming reachable quotient ties.

The legacy representation stores exponents in F32, but **not significands**.
All decoded exponents, sums/differences, leading indices, normalization shifts
and biased exponents here are small integers, far below `2^24`; conversion and
addition/subtraction are exact in F32. The internal `encode` adapter packs the
canonical normalized integer significand directly. It does not scale, narrow
or round it. It requires canonical signed zero (`M=0`, `E=0`), or
`2^52 <= M < 2^53` and integral `E` in
`[-1022,1023]`. These invariants follow from checked decoding or the two bounded
operations; direct calls with arbitrary `resize_numeric.Double` values have no
contract.

## Word and promotion boundaries

The following helpers remain private kernel prerequisites:

- `checked_decode(high,low)` accepts signed zero or any binary64 normal and
  returns a canonical `resize_numeric.Double`; `checked_identity` decodes then
  encodes under that invariant. Nonzero subnormals and specials are rejected
- `checked_finite(high,low)` constructs finite words, including subnormals;
  this does not make subnormals valid arithmetic operands
- `checked_promote(bits)` returns exact binary64 words for every finite raw F32
  encoding, including subnormals and both zero signs; exponent 255 is rejected.
  It uses `float64.promote`, never `resize_numeric.Double.from_f32`
- `negate` XORs the sign bit. `magnitude_order` compares sign-cleared encodings
  with result `0` equal, `1` less, `2` greater. For finite values this is absolute
  numerical order; for specials only the raw encoding interpretation applies
- `numerical_equal` returns finite numerical equality, treating all zero-sign
  combinations as equal. If either input is nonfinite it returns `False`, even
  for identical infinity or NaN encodings
- `increment` and `decrement` are wrapping **unsigned encoding** steps with
  low-word carry/borrow. They are not `nextafter`; incrementing a negative
  encoding increases its magnitude, and all-ones/zero wrap modulo `2^64`
- `checked_power(stored)` accepts stored exponent `1..2046` and constructs the
  positive exact power `2^(stored-1023)`. Other U32 arguments are rejected;
  callers must establish any exponent subtraction before supplying this value

No constants or angle expression tree have been ported. No existing library source
imports this module. There is no public API re-export or status promotion.

## Independent verification and proof boundary

Run with the existing pinned toolchain, without installing or changing it:

```sh
python3 tools/binary64_ops_probe.py --bend-source "$BEND_SOURCE"
python3 -m unittest discover -s tests -v
bun "$BEND_SOURCE/bend2/main.ts" PROOF.bend --check-only
```

The primary oracle computes exact Python `Fraction` products and quotients and
binary-searches rational binary64 neighbors by distance and parity. It reuses
the generic decoder and neighbor search from `binary64_fma_oracle.py` unchanged;
it does not reproduce the candidate's product limbs, division loop or pack.
Direct finite F32 promotion is compared with independently decoded exact values
and native casts, not merely promotion followed by narrowing.

A separately qualified C oracle uses volatile runtime multiply/divide and
promotion, `memcpy`, IEEE layout/evaluation checks, `FE_TONEAREST`, explicit
FTZ/DAZ rejection and fixed controls. Native disagreement with the independent
oracle fails the gate. CPU-one-thread, CPU-two-thread and JavaScript are checked
with strict IDs, kinds, tags, U32 types, lengths and payloads in bounded serial
programs. Native/candidate stdout is retained, old success and compiled outputs
are invalidated, and source/toolchain/input/artifact identities are rechecked.

The frozen corpus contains 36,176 observations: 11,892 multiply, 6,152 divide,
4,124 normal decode/encode identities, 4,124 finite constructions, 2,852 direct
F32 promotions, 1,914 magnitude comparisons, 1,914 finite equalities, 384 each
of negation/increment/decrement and 2,052 checked exponent constructions.
There are 35,064 accepted observations and 1,112 checked rejections. Coverage
includes every permitted exponent/sign/operand position, all zero signs and
multiplication orders, both normalization branches, significand/limb boundaries,
product ties/carry/sticky tails and neighboring operands, pair guard boundaries,
all finite F32 exponents, each subnormal leading bit, and normal/subnormal/sign
transitions. Sixty-four directed division near-midpoints cover both sides and
both lower-neighbor parities at several exponent gaps. Their exact rational
distance from the midpoint is `1/(2*N)` ulps, where `N` is the integer denominator
significand. Synthetic ties of the independent rounding oracle are explicitly
internal controls, not reachable checked-division cases.

CPU-one-thread, CPU-two-thread and JavaScript each match all **36,176 complete
observations** in 142 serial programs of at most 256 records and 16 records per
output line. Each lane checks 180,880 framed U32 words. The native qualification
passes all 32 runtime controls with Clang 19.1.7, `FE_TONEAREST`, MXCSR 8064 and
FTZ/DAZ disabled. All **209 repository Python tests** pass, including 40 focused
oracle, malformed-output, qualification, compiler-selection, stale-output and
drift tests. The final focused report retains 53 source/dependency
hashes and 1582 input/program/native/build/output artifact hashes.

The complete proof entry point now has 51 laws: 34 existing, three structural
rejection laws and fourteen concrete rejection/zero/word-boundary equalities.
They do not establish universal arithmetic correctness or kernel reachability.
F32 arithmetic and bit primitives are opaque to this type checker; nonzero
multiply/divide and successful promotion are tested exactly, not presented as
mechanically reduced arithmetic proofs. Numerical bounds, the limited laws and
the independent differential corpus provide distinct kinds of evidence.

Independent read-only review regenerated every input and candidate program,
recomputed all expectations with a separately expressed integer-rational rounding
method, replayed native/all three candidate lanes, verified source/toolchain and
artifact hashes, and checked preserved regressions, documentation and API status.
It found no blocking findings and cleared this private checkpoint.

Final checkpoint counts and regression outcomes are recorded in
[durable evidence](evidence/binary64-ops.json). No GPU, hosted execution,
exhaustive coverage or performance parity is claimed.

## Remaining work

The full pinned modern angle kernel, its fallbacks, integration of checked
primitive domains, native-profile qualification and wrapper/device/resource
evidence remain open. In particular tiny-branch `z*e` can underflow into binary64
subnormals and signed zero. These normal-result operations reject the relevant
out-of-domain operands/pairs; they must not silently substitute an already-rounded
product for a future directly rounded gradual-underflow implementation. Existing
angle profiles, fixtures, expectations, tolerances and their strict canonical
mismatch remain unchanged. See [ANGLE-PLAN.md](ANGLE-PLAN.md).
