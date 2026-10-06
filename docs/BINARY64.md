# Private binary64 emulation

The `M.Glibc241Libm{}` angle profile (see [ANGLES.md](ANGLES.md)) reproduces the
pinned glibc 2.41 `e_atan2f.c`, which evaluates in binary64 with explicit FMA,
compensated double-double arithmetic, a product that genuinely underflows to
binary64 subnormals, unsigned raw-word stepping and a single final narrowing to
binary32. Five private Bend modules supply that arithmetic on canonical IEEE
binary64 words, using only `Base` integer/Nat/Bool operations: no host F32/F64
arithmetic (except the exact exponent bookkeeping noted under
[normal operations](#checked-normal-operations-and-word-adapters)), native FMA,
FFI or compiler hook. Each computes the exact real result and rounds it
**once**, to nearest with ties to even.

| Module | Entry points | Purpose |
|---|---|---|
| `src/binary64_narrow.bend` | `checked` | binary64 → binary32 word |
| `src/binary64_fma.bend` | `checked`, `Words` | bounded fused multiply-add |
| `src/binary64_add_sub.bend` | `checked_add`, `checked_sub` | bounded addition/subtraction |
| `src/binary64_ops.bend` | `checked_multiply`, `checked_divide`, word adapters | normal-result multiply/divide, promotion, decoding, raw stepping |
| `src/binary64_gradual_multiply.bend` | `checked` | product with gradual (subnormal/zero) output |

**Consumers.** The only library consumer is the private glibc 2.41 kernel
`src/modern_angle.bend` ([MODERN-ANGLE.md](MODERN-ANGLE.md)), which feeds the
public checked angle wrappers in `src/checked_angle.bend`. `LAWS.bend` imports the
modules for their laws. Nothing is re-exported from `jonlib.bend` or
`jonmath.bend`. The older `float64.bend`, `float64_ops.bend` and
`resize_numeric.bend` arithmetic (projection, resize, legacy angle profiles) and
the F32 multiply-add in `fused.bend` are separate and keep their own contracts;
these helpers must not be wired into those consumers as a side effect.

## Shared contract

- Arguments and results are canonical IEEE binary64 words as high/low `U32`
  pairs; results use `binary64_fma.Words{high, low}` inside `Maybe`.
- Each `checked*` entry point validates **every** operand before any arithmetic
  or zero shortcut. A rejected operand (nonzero subnormal where not allowed,
  infinity, NaN, or a normal outside the helper's exponent interval) or a
  violated pair guard returns `None`; nothing is flushed, clamped or rerouted
  to another profile.
- Exponents below are unbiased (`E` for a value `M*2^(E-52)`, `2^52 <= M < 2^53`)
  unless called *stored*.
- Zero signs are part of the contract: products and quotients take the sign XOR;
  the sum of two zeros keeps their common sign or gives +0 for mixed signs; exact
  cancellation of nonzero values gives +0.
- Domains are rectangles chosen so that the exact result fits the helper's
  integer accumulator and its rounded result cannot overflow (and, except for
  narrowing and the gradual product, cannot underflow). They are **not closed
  under chaining**: a result can fall outside the next call's domain, so each
  call validates its own inputs. The bounds that make every call in the pinned
  kernel fit are derived in [MODERN-ANGLE-BOUNDS.md](MODERN-ANGLE-BOUNDS.md).
- Out of contract: other rounding modes, ambient rounding state, floating-point
  exception flags, errno and NaN payloads.
- Internal helpers (list/limb/window/pack functions) are visible because of
  Bend's module model; only the `checked*` entry points and the listed word
  adapters establish a contract.

## How it is verified

Each helper has a probe built on `tools/binary64_harness.py` (on top of
`tools/probekit.py`) and an independent exact rational oracle:

| Gate id | Probe | Oracle |
|---|---|---|
| `binary64-narrow` | `tools/binary64_narrow_probe.py` | `tools/binary64_narrow_oracle.py` |
| `binary64-fma` | `tools/binary64_fma_probe.py` | `tools/binary64_fma_oracle.py` |
| `binary64-add-sub` | `tools/binary64_add_sub_probe.py` | `tools/binary64_add_sub_oracle.py` |
| `binary64-ops` | `tools/binary64_ops_probe.py` | `tools/binary64_ops_oracle.py` |
| `binary64-gradual-multiply` | `tools/binary64_gradual_multiply_probe.py` | `tools/binary64_gradual_multiply_oracle.py` |

For every observation of a deterministic, labelled corpus the driver:

1. derives the expected row from the rational oracle: operands are decoded to
   Python `Fraction`s, the exact result is computed, adjacent binary64 (or
   binary32) values are found by binary search, exact distances are compared and
   ties go to the even encoding. Zero signs are decided explicitly because a
   rational zero has no sign. The oracle never reuses the candidate's limbs,
   shifts, windows or packing;
2. compiles a native C program with `-frounding-math -fno-fast-math
   -ffp-contract=off -fno-lto`, volatile operands and `memcpy` word conversion.
   It must report `FE_TONEAREST`, IEEE layout and clear FTZ/DAZ/directed-rounding
   bits in x86 MXCSR or AArch64 FPCR (other architectures fail closed), and must
   pass fixed runtime preflight controls. Its rows for natively expressible
   observations must equal the rational oracle; the rational oracle stays
   authoritative;
3. runs the Bend candidate on CPU-1, CPU-2 and JavaScript (plus a forced-GPU
   lane with `--gpu`) and requires every lane to equal the oracle row for row,
   with strict id/kind/tag/word framing.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only binary64-fma
```

Oracle and harness behaviour is unit-tested in `tests/test_binary64.py`.
`LAWS.bend` adds structural laws (rejection branches, shift structure) and
concrete equalities (ties, carries, zero signs, lattice floors) for each helper;
`PROOF.bend` is checked by the `conformance` gate. These are scoped proofs, not
universal IEEE rounding theorems: the written bounds below, the laws and the
exact differential corpora are complementary evidence.

**Gaps common to all helpers.** Coverage is a stratified corpus, not exhaustive
execution. CI runs CPU/JavaScript lanes only; forced-GPU evidence is local (see
[CI.md](CI.md)). No performance claim is made.

## Narrowing to binary32

`binary64_narrow.checked(high: U32, low: U32) -> Maybe<U32>` returns the binary32
**word** nearest to the binary64 input, ties to even.

**Domain.** Every finite binary64 input, including signed zero and binary64
subnormals. Binary32 underflow is gradual; overflow returns the correctly signed
infinity word. Stored exponent 2047 (both infinities and all NaNs) returns `None`.

**Algorithm and rounding.** Let `s = high & 0x80000000`,
`E = (high >> 20) & 2047` (stored) and
`M = ((high & 0xfffff) | 0x100000) * 2^32 + low`.

- `E = 2047` is rejected before finite classification.
- `E < 873`: magnitude strictly below `2^-150`, rounds to signed zero. This
  includes every binary64 subnormal without normalizing it.
- `E > 1150`: magnitude at least `2^128`, rounds to signed infinity.
- `897 <= E <= 1150` uses `k = 29`; `873 <= E <= 896` uses `k = 926 - E`
  (`30..53`). `Q = RN_even(M / 2^k)`. The normal magnitude is
  `((E - 897) << 23) + Q`; the subnormal magnitude is `Q`.

The normal addition lets `Q = 2^24` carry into the next exponent, including
infinity; a subnormal `Q = 2^23` is already the minimum normal word.
`E = 873, M = 2^52` is the exact half-minimum-subnormal tie and rounds to zero;
any larger significand at that exponent rounds up.

`Wide.jam(n, V)` shifts two U32 limbs one bit at a time, keeping
`floor(V/2^n) OR [V mod 2^n != 0]`. Narrowing jams by `k - 3` (`26..50`); since
`M < 2^53` the result is below `2^27`. The low three bits are guard/round/sticky:
`q = low >> 3` is incremented exactly when `tail > 4`, or `tail = 4` and `q` is
odd. No F32 operation, normal-only decoder or round-then-scale path is used.

**Verification.** Gate `binary64-narrow`. Fixed hand vectors pin the critical
underflow, minimum-normal and overflow ties and their neighbours: input
`36900000 00000000` → `00000000`, `36900000 00000001` → `00000001`,
`36a7ffff ffffffff` → `00000001`, `36a80000 00000000` → `00000002`,
`380fffff dfffffff` → `007fffff`, `380fffff e0000000` → `00800000`,
`47efffff efffffff` → `7f7fffff`, `47efffff f0000000` → `7f800000`. The corpus
covers every finite binary64 exponent in both signs, transition neighbours, all
subnormal binades, limb carries, both parity choices at binary32 ties through
gradual underflow, minimum normal and overflow, nonfinite rejections and
exponent-stratified seeded words. It also checks `float64.promote` followed by
`checked` round trips for every finite binary32 exponent, zero sign and subnormal
binade; `Wide.jam` against its integer invariant for shifts `0..65`; and every
three-bit guard/round/sticky tail with both parities. The rational oracle
supplies the expected word; the native oracle casts a volatile runtime double to
volatile float.

## Bounded fused multiply-add

`binary64_fma.checked(ah, al, bh, bl, ch, cl) -> Maybe<Words>` rounds the exact
real `a*b+c` once.

**Domain (asymmetric).**

- `a`, `b`: signed zero or normal with `E` in `[-277, 127]`.
- `c`: signed zero or normal with `E` in `[-554, 255]`.
- Anything else, including any nonzero subnormal, returns `None`; all three
  inputs are validated first.

A zero product plus a zero `c` keeps their common sign or returns +0 when the
signs differ; exact cancellation of nonzero values returns +0. This is not
general gradual-underflow FMA.

**Bounds.** The exact product has at most 106 significand bits and finest quantum
`2^-658`; the finest addend quantum `2^-606` is a multiple of it.
`|a*b| < 2^256` and `|c| < 2^256`, so `|a*b+c| < 2^257`. The exact sum is
therefore an integer multiple of `2^-658`, every nonzero sum has magnitude at
least `2^-658` and its integer magnitude is below `2^915`. A 29-limb (928-bit)
magnitude holds both aligned terms and the sum; cancellation is exact and cannot
produce a nonzero subnormal, and final rounding cannot underflow or overflow.

**Algorithm and rounding.**

- A 53-step shift/add computes the exact 106-bit significand product in four
  U32 limbs (working value within 128 bits).
- Magnitudes are little-endian immutable 29-limb lists in units of `2^-658`.
  The product shift is `Ea+Eb+554` (`0..808`); the addend shift is `Ec+606`
  (`52..861`); signed zeros use shift and significand zero.
- Alignment uses whole-limb zero prefixes and a residual shift of `1..31` bits
  (shift zero handled explicitly). Carry and borrow are detected across two
  wrapping U32 operations. Equal signs add; opposite signs compare from the
  high limb and subtract the smaller magnitude; equal magnitudes give +0.
- No alignment or cancellation step compresses bits into a sticky bit. With `t`
  the index of the leading one, the unrounded stored exponent is `t+365`. The
  value is normalized to a 56-bit window (53 significand + 3 rounding bits);
  discarded limbs and low bits become sticky **only at this final step**
  (`t < 55` normalizes left exactly). The significand is incremented when the
  tail exceeds 4, or equals 4 with an odd significand; a carry shifts right and
  increments the exponent. Words are packed directly.

**Verification.** Gate `binary64-fma`. Retained exact controls include
`(1+2^-52)*(1-2^-52)-1 = -2^-104` (`3ff0000000000001 * 3feffffffffffffe +
bff0000000000000 = b970000000000000`, which multiply-then-add gets wrong), both
tie parities (`1*1+2^-53 = 1`, `(1+2^-52)*1+2^-53 = 1+2^-51`), and the domain
floor `((1+2^-52)*2^-277)^2 - (1+2^-51)*2^-554 = 2^-658` in both signs. The
corpus covers all zero-sign triples, nonzero cancellation, long carry/borrow,
exponent gaps, extrema, every allowed exponent in both signs for each operand,
rejection boundaries in every operand, all 55 left-normalization shifts, all 32
residual right-shift counts, significand rounding carry and bit-stratified
words. The native oracle calls runtime libm `fma`.

## Bounded addition and subtraction

`binary64_add_sub.checked_add(ah, al, bh, bl)` and `checked_sub(...)` return
`Maybe<binary64_fma.Words>`, the exact sum or difference rounded once.

**Domain.** Both operands are signed zero or normal with `E` in `[-900, 130]`
(stored exponent `[123, 1153]`). A zero operand does not bypass validation of the
other. Subtraction flips the right operand's sign bit and then performs the same
checked addition. Hence `-0 - +0 = -0` and `-0 - -0 = +0`.

**Bounds.** Every accepted operand is an integer multiple of `2^-952`, with
lattice shift `E+900` in `0..1030`. Operands are below `2^131`, so every result
is below `2^132` (integer magnitude below `2^1084`), and every nonzero exact
result is at least `2^-952`; adjacent normals at the lowest exponent attain that
floor. Thirty-four U32 limbs (1088 bits) hold each term and the sum with its
carry, so cancellation is exact and rounding cannot underflow or overflow.

**Algorithm and rounding.** The module reuses width-independent primitives of
`binary64_fma.bend` under these invariants: `fit`, `prefix` and `shift_ready`
work on arbitrary lists (the bounded shift fits 1083 bits, so fitting to 1088
loses nothing); `add`, `sub` and `order` traverse equal-length lists with
two-step carry/borrow detection, and the final carry/borrow is zero because the
sum fits and subtraction orders magnitudes first; `top`, `first3`, `window` and
`normalize` are independent of width and scale (leading index at most 1083;
below 55 left normalization is exact, otherwise only the final 56-bit window
compresses bits into sticky); `pack` expects 53 significand bits plus three
rounding bits and a normal stored exponent and rounds as for FMA. The module
fixes its own 34-limb alignment and lattice exponent offset `1023-952 = 71`;
FMA's 29-limb alignment and `t+365` finish are not used.

**Verification.** Gate `binary64-add-sub`. Retained controls include even/odd
ties (`3ff0000000000000 + 3ca0000000000000 = 3ff0000000000000`,
`3ff0000000000001 + 3ca0000000000000 = 3ff0000000000002`), below/above-tie
neighbours, binade carry (`3fffffffffffffff + 3ca0000000000000 =
4000000000000000`), the lattice floor (`07b0000000000001 - 07b0000000000000 =
0470000000000000` and its negative), the largest sums
(`481fffffffffffff + 481fffffffffffff = 482fffffffffffff`), deep cancellation
and long borrow. The corpus covers every accepted exponent in each sign, operand
position and operation; all zero-sign pairs and operand orders; exact nonzero
cancellation; doubleword carries; extreme gaps; every significand bit and bit
hole; all 55 left-normalization shifts and 32 right-window residuals; and every
rejected class and normal boundary in either operand with positive-zero,
negative-zero and nonzero counterparts. The native oracle performs runtime
addition/subtraction.

**Known gap.** The legacy `resize_numeric.bend` addition returns `b` whenever
`a` is zero, so `+0 + -0` gives `-0` instead of RN `+0`. It is intentionally
left unchanged for its existing consumers; correct zero semantics live here.

## Checked normal operations and word adapters

`src/binary64_ops.bend` wraps the legacy `float64_ops.bend` multiplication and
division with checked word boundaries. Results are `Maybe<binary64_fma.Words>`,
rounded once. It is a conservative **normal-result** contract, not general
binary64 arithmetic.

**Arithmetic domains.**

- `checked_multiply(ah, al, bh, bl)`: each operand is signed zero or normal with
  `E` in `[-554, 127]` (stored `[469, 1150]`); when both are nonzero,
  `Ea+Eb` must be in `[-833, 127]` (stored sum `[1213, 2173]`).
- `checked_divide(ah, al, bh, bl)`: numerator signed zero or normal with `E` in
  `[-225, 127]` (stored `[798, 1150]`); denominator **nonzero normal** with `E`
  in `[-149, 127]` (stored `[874, 1150]`); a nonzero numerator also needs
  `Ea <= Eb`. Every zero divisor returns `None`, including all signs of `0/0`.

Both inputs are validated before any zero shortcut; zero results take the sign
XOR. The pair guards are not closure guarantees.

**Bounds.** Multiplication keeps the exact 106-bit product in four limbs (leading
bit at index 104 or 105); only final normalization jams into the three rounding
bits, and the existing nearest-even round and carry run once. Every nonzero
rounded product has `E` in `[-833, 128]`; at the upper edge the significand
product is at most `4-2^-50+2^-104`, too far below 4 to round across that binade,
so there is no underflow or overflow. Division compares normalized mantissas
(doubling a smaller numerator once, since their ratio is strictly between 1/2
and 2), keeps the remainder in `[0, N)` through 52 quotient steps (intermediates
below `2^54`), and compares the exact `2*R` with `N` with odd-quotient tie
resolution. Every nonzero quotient has `E` in `[-353, 0]`; the largest ratio
`(2^53-1)/2^52` is representable below 2. Within this range an exact quotient
midpoint is unreachable: a reduced normal midpoint has an odd numerator of at
least 54 bits, a reduced `M/N` ratio at most 53, and powers of two do not change
that.

The legacy representation stores exponents (not significands) in F32. All
exponents, sums/differences, leading indices, shifts and biased exponents here
are small integers far below `2^24`, so those F32 operations are exact. The
internal `encode` packs the canonical normalized integer significand directly
(no scaling, narrowing or rounding) and requires canonical signed zero
(`M=0, E=0`) or `2^52 <= M < 2^53` with integral `E` in `[-1022, 1023]`; direct
calls with arbitrary `resize_numeric.Double` values have no contract.

**Word adapters.**

- `checked_decode(high, low)`: signed zero or any normal → canonical
  `resize_numeric.Double`; `checked_identity` decodes then encodes. Nonzero
  subnormals and specials are rejected.
- `checked_finite(high, low)`: constructs finite words, including subnormals
  (this does not make subnormals valid arithmetic operands).
- `checked_promote(bits)`: exact binary64 words for every finite raw F32
  encoding, including subnormals and both zeros, via `float64.promote` (never
  `Double.from_f32`); exponent 255 is rejected.
- `negate` XORs the sign bit. `magnitude_order` compares sign-cleared encodings
  (`0` equal, `1` less, `2` greater); for finite values this is absolute
  numerical order.
- `numerical_equal`: finite numerical equality, all zero signs equal; `False` if
  either input is nonfinite, even for identical encodings.
- `increment` / `decrement`: wrapping **unsigned encoding** steps with low-word
  carry/borrow. They are not `nextafter`: incrementing a negative encoding
  increases its magnitude, and all-ones/zero wrap modulo `2^64`.
- `checked_power(stored)`: stored exponent `1..2046` → exact `2^(stored-1023)`;
  other arguments are rejected.

**Verification.** Gate `binary64-ops`. Retained controls include product ties
of both parities (`3ff0000000000001 * 3ff8000000000000 = 3ff8000000000002`,
`3ff0000000000003 * 3ff8000000000000 = 3ff8000000000004`), product rounding
carry (`3ff0000000000001 * 3ffffffffffffffe = 4000000000000000`), repeating
quotients (`1/3 = 3fd5555555555555`) and quotient near-midpoints. The corpus
covers every permitted exponent, sign and operand position; all zero signs and
operand orders; both division normalization branches; significand/limb
boundaries; product ties, carries and sticky tails; pair-guard boundaries; every
finite F32 exponent and each subnormal leading bit for promotion; and normal,
subnormal and sign transitions for the adapters. Directed division
near-midpoints cover both sides and both lower-neighbour parities at several
exponent gaps (exact distance `1/(2*N)` ulps); synthetic oracle ties are internal
controls, not reachable division cases. Promotion is checked against the
independently decoded exact value and native casts. The native oracle uses
runtime multiply/divide and promotion.

## Product with gradual output

`binary64_gradual_multiply.checked(ah, al, bh, bl) -> Maybe<binary64_fma.Words>`
rounds the exact product once, with normal, subnormal or zero results. It covers
the kernel's tiny-branch `z*e`, which genuinely reaches binary64 subnormals and
negative zero and which the normal-result multiply rejects.

**Domain (asymmetric).**

- `a`: signed zero or normal with `E` in `[-277, 0]`.
- `b`: signed zero or normal with `E` in `[-885, 0]`.
- Both are validated before any zero shortcut, so invalid-with-zero pairs are
  rejected. Every result sign, including exact and underflowed zero, is the
  operand-sign XOR. Subnormal inputs are not accepted.

**Bounds and single rounding.** For nonzero operands let `L = 2^52`,
`L <= Ma, Mb < 2L`, `P = Ma*Mb`, `S = Ea+Eb` and `B = S+2046`. Then
`2^104 <= P < 2^106`, `S` in `[-1162, 0]` and `|a*b| = P*2^(S-104) < 4`. The
FMA module's four-limb `Product.mul` keeps all 106 bits; nothing is rounded early.

- `S >= -1022` (`B >= 1024`): the product is normal. With its top bit at
  `104+h` (`h` in `{0,1}`), a right shift/jam by `49+h` gives a 56-bit window and
  `F.pack(sign, B-1023+h, window)` rounds once. Maximum significands give
  `4-2^-50+2^-104`, so there is no overflow.
- `S <= -1023`: in minimum-subnormal quanta,
  `|a*b|/2^-1074 = P/2^k` with `k = -S-970 = 1076-B` in `[53, 192]`.
  - `k >= 107` (`B <= 969`): `P < 2^106 <= 2^(k-1)` is strictly below half the
    minimum subnormal; the XOR-signed zero is returned directly.
  - Otherwise `P` is shifted/jammed by `k-3` (`50..103`) into a window `W`;
    `W/8` is incremented exactly when the three-bit tail exceeds 4, or equals 4
    with an odd retained bit.
  - The rounded integer `Q <= 2^53-2` **is the unsigned raw result encoding**:
    below `2^52` subnormal or zero, from `2^52` stored exponent 1. The sign is
    ORed into the high word; `F.Words.add` handles the low-word carry.

The gradual encoder never masks bit 52 or predicts an exponent before rounding:
`S = -1023` may already be normal or round across the max-subnormal/min-normal
boundary, while at `S = -1024` maximum significands round to maximum subnormal,
never minimum normal. `F.Magnitude.window` is width-independent: it drops whole
limbs into a Boolean sticky, takes at most three following limbs (zero-padding
missing ones), merges the `0..31` residual shift (shift zero handled explicitly)
and jams only at this final step; four input limbs suffice. At `k = 105`,
`P = 2^104` is a reachable half-minimum-subnormal tie; at `k = 106` a tie needs
`P = 2^105`, impossible for two accepted significands (both would have to be
`2^52`), so tests of that tie are labelled internal controls.

**Retained controls.** With `a = 2ea0000000000001`, three witnesses expose a
53-bit-round-then-subnormal (double-rounding) implementation:

| b | Correct result | Double-rounded result |
|---|---|---|
| `1150000000000004` | `0008000000000003` | `0008000000000002` |
| `115ffffffffffffd` | `000fffffffffffff` | `0010000000000000` |
| `0e0fffffffffffff` | `0000000000000001` | `0000000000000000` |

Their negative mirrors are also controls. Four literal tiny-kernel products from
the `y32 = 00000001` cases (see
[MODERN-ANGLE-BOUNDS.md](MODERN-ANGLE-BOUNDS.md#8-tiny-branch-and-its-real-gradual-underflow-multiplication))
are retained by exact operands:

| x32 | a = z | b = e | RN(z*e) |
|---|---|---|---|
| `75000000` | `2ff0000000000000` | `8fd5555555555555` | `8001555555555555` |
| `7b000000` | `2f30000000000000` | `8d95555555555555` | `8000000000000001` |
| `7b800000` | `2f20000000000000` | `8d65555555555555` | `8000000000000000` |
| `7f000000` | `2eb0000000000000` | `8c15555555555555` | `8000000000000000` |

**Verification.** Gate `binary64-gradual-multiply`. The corpus covers all
accepted exponents, signs and operand positions; both product-top bits; every
gradual shift `k = 53..192` (`53..106` exercise the retained window, `107..192`
the zero fast path); all 52 significand bit and bit-hole positions; shift-limb
boundaries `66/67/68` and `98/99/100`; normal/gradual/zero transitions; tie
parities and neighbouring inputs; zero signs; invalid classes; and seeded random
word pairs. The native oracle multiplies through a volatile function pointer
(not `fma(a,b,0)`) and additionally requires `DBL_HAS_SUBNORM == 1` and
`FLT_EVAL_METHOD == 0`; its preflight controls include signed zeros, both tie
parities, the double-rounding witnesses and DAZ/FTZ detection
(subnormal-input-to-normal and normal-input-to-subnormal products). Some
preflights lie outside the candidate rectangle solely to qualify native
behaviour; the candidate must still reject those inputs.
