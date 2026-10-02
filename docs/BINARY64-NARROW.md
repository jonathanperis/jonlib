# Private directly rounded binary64-to-binary32 words

`src/binary64_narrow.bend` is an isolated prerequisite for the future modern
angle profile. `checked(high: U32, low: U32) -> Maybe<U32>` consumes the canonical
IEEE binary64 encoding and returns the binary32 **word**, rounded once to nearest,
ties to even. Every finite binary64 input is accepted, including signed zero and
binary64 subnormals. Binary32 underflow is gradual; overflow returns the correctly
signed infinity word. Exponent 2047, including both infinities and all NaNs,
returns `None`. There are no claims about other rounding modes, errno, floating
exceptions or NaN payloads.

This is private numerical support, with no library consumers or public API
promotion. In particular `float64.bend/to_f32`, `resize_numeric.bend`, projection,
angle and extrema code/selectors remain unchanged. The old normal-only conversion
contract has not been expanded. A successful gate here does not fix the existing
GNU/Sun versus glibc 2.41 angle mismatch.

## Integer derivation and bounds

Let `s = high & 0x80000000`, `E = (high >> 20) & 2047` and, for the middle
partition, `M = ((high & 0xfffff) | 0x100000) * 2^32 + low`.

- Reject `E = 2047` before finite classification
- `E < 873` has magnitude strictly below `2^-150`, so rounds to signed zero;
  this includes every binary64 subnormal without trying to normalize it
- `E > 1150` has magnitude at least `2^128`, so rounds to signed infinity
- For `897 <= E <= 1150`, let `k = 29`; otherwise `873 <= E <= 896` and
  `k = 926 - E`, giving `30 <= k <= 53`
- `Q = RN_even(M / 2^k)`. Normal output magnitude is
  `((E - 897) << 23) + Q`; subnormal output magnitude is `Q`

The normal addition deliberately allows `Q = 2^24` to carry into the next
exponent, including infinity. Subnormal `Q = 2^23` is already the minimum normal
word. `E = 873, M = 2^52` is the exact half-minimum-subnormal tie and rounds to
zero; any larger significand at that exponent rounds up.

`Wide.jam(n,V)` uses one-bit shifts of two U32 limbs, with the invariant
`floor(V/2^n) OR [V mod 2^n != 0]`. For this conversion it shifts by `k - 3`,
which lies in `26..50`. Since `M < 2^53`, the result is below `2^27` and its high
limb is zero. The low three bits retain guard/round/sticky information. Increment
`q = low >> 3` exactly when `tail > 4`, or `tail = 4` and `q` is odd. No F32
operation, normal-only decoder or round-then-scale path appears in the helper.

## Evidence and proof boundary

Run with the existing pinned toolchain, without installing or altering it:

```sh
python3 tools/binary64_narrow_probe.py --bend-source "$BEND_SOURCE"
python3 -m unittest discover -s tests -v
bun "$BEND_SOURCE/bend2/main.ts" PROOF.bend --check-only
```

The primary oracle independently decodes binary64 as a Python `Fraction`, binary
searches ordered positive binary32 neighbors, compares exact rational distances,
and resolves ties by even encoding. A conceptual `2^128` endpoint gives the
correct maximum-finite/infinity midpoint. It does not reuse candidate shifts,
packing or rounding. Fixed hand vectors pin the critical underflow, min-normal
and overflow ties and neighboring binary64 words before generated tests run.

The secondary C oracle loads raw words with `memcpy` into a volatile runtime
double and casts to volatile float. It checks IEEE layouts, selects and verifies
`FE_TONEAREST`, records compiler/flags/control registers, and rejects FTZ/DAZ or
directed rounding. Qualification supports x86 MXCSR and AArch64 FPCR; other
architectures fail closed. The independent rational oracle remains authoritative.

The deterministic corpus has **40,276 observations per CPU-one-thread,
CPU-two-thread and JavaScript lane**:

- 35,324 directly checked binary64 inputs, including 12 nonfinite rejections
- Every finite binary64 exponent in both signs, transition neighbors, all
  subnormal binades, limb carries and exponent-stratified seeded random words
- Both parity choices at binary32 ties and adjacent binary64 words, through
  gradual underflow, minimum normal and overflow
- 3,692 separate existing `float64.promote` then new `checked` roundtrips, covering
  every finite binary32 exponent, zero signs and subnormal binades
- 1,188 independent integer jam-invariant observations for shifts `0..65`
- 72 guard/round/sticky observations covering every three-bit tail and both parity
  choices, including carry boundaries

The runner emits at most 512 operations per program and 32 per output line,
checks every ID/tag/word/count/type/shape, retains stdout/stderr and hashes inputs,
oracle outputs, sources, harnesses, native metadata and generated programs and
binaries. It invalidates stale success first, removes old compiler outputs before
building, verifies fresh nonempty outputs and revalidates source and compiler
pins at final acceptance. Fourteen Python tests cover exact controls, malformed,
missing, extra, reordered and wrong-type observations, inconsistent native mode
metadata, stale outputs and source/toolchain drift.

`LAWS.bend`/`PROOF.bend` additionally check jam's zero/successor structure and the
special rejection branch, plus six concrete arithmetic equalities for half-minimum,
above-half-minimum, min-normal carry, overflow carry, negative zero and an odd tie.
The recorded narrowing checkpoint's complete verdict includes all four
pre-existing laws. These structural and
concrete proofs are **not** a universal IEEE rounding theorem. Rational tests and
the mathematical bounds above supply complementary evidence, not exhaustive
execution of all finite64 words. No GPU, hosted execution, timing guarantee or
performance parity is claimed. The full current-host canonical suite remains
strictly failed at the separately documented angle scenario.

## Remaining modern-angle prerequisites

See [ANGLE-PLAN.md](ANGLE-PLAN.md). A
[private bounded binary64 FMA](BINARY64-FMA.md) is now implemented separately.
A [private bounded add/subtract helper](BINARY64-ADD-SUB.md) now supplies audited
signed-zero arithmetic separately. General packing/stepping and full kernel
integration of reachable compensated-cancellation bounds remain open. Four product
limbs retain 106 bits but do not by themselves
solve arbitrary FMA alignment/cancellation. The entire pinned modern scalar kernel,
its two fallbacks, a separate qualified angle selector, wrapper domains and
forced-device evidence are still required. This helper must not be wired into
existing projection/resize paths as a side effect of that work.

The checked checkpoint and strict regression outcome are recorded in
[durable evidence](evidence/binary64-narrow.json).
