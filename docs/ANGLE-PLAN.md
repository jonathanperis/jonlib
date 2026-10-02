# Modern native angle profile: staged implementation plan

Status: researched design, **not implemented or passing parity**. The existing
Apple and GNU/Sun algorithms, public defaults and `_for` meanings remain unchanged.
The current glibc 2.41 angle mismatch remains a strict failure; see
[NATIVE-MATH-PROFILES.md](NATIVE-MATH-PROFILES.md).

## Immutable algorithm source and notices

Use the [glibc 2.41 release file](https://github.com/bminor/glibc/blob/74f59e9271cbb4071671e5a474e7d4f1622b186f/sysdeps/ieee754/flt-32/e_atan2f.c)
as the port source:

- Release commit: `74f59e9271cbb4071671e5a474e7d4f1622b186f`
- Path: `sysdeps/ieee754/flt-32/e_atan2f.c`
- Git blob: `82a0151293cda9cf89d6a18b6f8b35d4fdaeddd4`
- SHA-256: `96f9c81b6e870c256cc0757f6d88f5290ed35db8d5b640b9e757d6feca96ae38`
- glibc import commit: `6f9bacf36b20b1a87fa4ec24c9d67c47985fbc8b`
- The file identifies CORE-MATH revision `7835c5d`; this abbreviation is not
  treated as an independently verified full upstream commit ID

This exact file carries the MIT permission notice and copyright 2022–2024
Alexei Sibidanov and Paul Zimmermann. Before porting it, retain the complete
notice, mark the altered implementation and add the source/hash to third-party
notices. Do not assume unrelated glibc files share this license. In particular,
[glibc's atan2 test file](https://github.com/bminor/glibc/blob/74f59e9271cbb4071671e5a474e7d4f1622b186f/math/libm-test-atan2.inc)
is LGPL-2.1-or-later; use independently generated controls rather than copying
that harness without separately addressing its terms.

The [official 2.41 release announcement](https://sourceware.org/pipermail/libc-announce/2025/000045.html)
confirms the CORE-MATH integration. Direct upstream GitLab lookup was blocked by
its access protection; no attempt was made to bypass it. The complete glibc
release pin above is the verified source, not an invented upstream pin.

## Separate API and contract

Introduce an angle-specific reference type, separate from `Gradient.Reference`.
A proposed versioned constructor is `Glibc241AngleRn{}` under `Angle.Reference`;
final public names remain to be reviewed. New angle entry points can accept that
type while the existing `_for` entry points continue to mean exactly what they
mean today. Never retarget the GNU/Sun profile or the gradient selector to make
the new host pass.

The initial new contract should be explicitly round-to-nearest-even result-bit
parity. Other rounding modes, errno, floating-point exceptions and NaN payload
interoperability are separate gaps. Separate scalar-kernel capability from
vector-wrapper restrictions on finite inputs/intermediate dot and cross results.
Unknown reference contexts must fail closed before candidate execution.

## Reusable arithmetic prerequisite

The first isolated prerequisite is now implemented in
[`binary64_narrow.bend`](../src/binary64_narrow.bend): checked finite binary64
words directly narrowed once to binary32 words, including gradual underflow and
signed overflow. [Its contract and evidence](BINARY64-NARROW.md) are separate from
the old normal-only conversion paths. It has no library consumers; the modern
angle profile and strict canonical failure remain unchanged.

The pinned Bend compiler has F32 arithmetic and exact bit construction, but no
F64 or FMA primitive. Its host atan2 lowering does not establish this profile.
Existing private arithmetic is in `resize_numeric.bend`, `float64.bend`,
`float64_ops.bend` and `fused.bend`:

- `float64.bend`'s `promote`, used by `float64_ops.from_f32`, preserves finite
  subnormals and signed zeros; `resize_numeric.Double.from_f32` is normal-only
- Normal binary64 addition, multiplication and division round explicitly to
  nearest-even; multiplication retains a 106-bit product in four U32 limbs
- The existing fused helper is scoped F32 FMA, not binary64 FMA
- Existing F32 narrowing repeatedly scales in F32 and is not a general
  subnormal-safe, directly rounded binary64 conversion
- Existing arithmetic probes do not establish difficult FMA/cancellation or
  subnormal narrowing behavior

A second isolated prerequisite is the private checked
[`binary64_fma.bend`](../src/binary64_fma.bend), with an explicit asymmetric
normal/zero domain and exact signed accumulation before a single RN-even pack.
[Its independent contract and evidence](BINARY64-FMA.md) do not establish full
kernel reachability or general binary64 FMA. Audited add/subtract and word
stepping remain next arithmetic milestones. Direct F32 narrowing is available
as the isolated prerequisite above; integrating it into a modern angle kernel
remains future work. Keep old projection/resize contracts unchanged. Establish
the kernel's reachable exponent bounds; support gradual underflow wherever it is
reachable instead of assuming it away.

A pure-Bend implementation is technically possible. A compiler/runtime change
is not a prerequisite; a host-specific atan2 hook is not a portable solution.
Optional generic native F64/FMA acceleration can be evaluated later through the
separately declared Bend overlay and its cross-workload gates.

Arithmetic acceptance gates:

1. Independently generated exact-bit controls for add/subtract, multiply, divide,
   FMA, promotion, packing, stepping and narrowing
2. Halfway cases on both parity sides, deep cancellation, exponent gaps, product
   carry, signed zeros, normal/subnormal boundaries and underflow to zero
3. Native FMA controls plus an independent exact/high-precision oracle where
   available; no tolerance or candidate-derived expected bits
4. Exact CPU one-thread, CPU two-thread and JavaScript results before the angle
   kernel is ported; preserve all existing arithmetic regression checks

## Complete scalar kernel

Port the entire pinned algorithm, with exact binary64 constants, not a coefficient
substitution in the old Sun function:

1. Bit classification, signed-zero rules, magnitude ordering and quadrant index
2. Exact promotion and ratio reduction to magnitude at most one
3. Seven numerator/seven denominator coefficients, original `z²/z⁴/z⁸` operation
   order, exponent-distance shortcut and high/low quadrant offsets
4. Low-bit ambiguity detection: `((bits(r)+8)&0x0fffffff)<=16`
5. Tiny-ratio fallback with true FMA quotient residual, cubic correction and
   word adjustment that prevents double rounding
6. General fallback with double-double products, compensated quotient, all 32
   high/low polynomial coefficients and compensated quadrant reconstruction
7. Final narrowing/re-promotion and rounding-boundary correction

Ordinary multiply followed by add cannot substitute for FMA residuals. Compare
intermediate binary64 words with an instrumented copy of the pinned C source and
record branch coverage, especially both fallbacks. No observed-input correction
tables or dropped hard paths are acceptable.

## Angle and integration gates

- Preserve all 1,086 existing samples and all 178 recorded native/Sun differences
- Cover zero signs, axes, quadrants, equal magnitudes and adjacent bit patterns
- Sweep exponent-distance and F32 rounding boundaries; include minimum/maximum
  subnormals, minimum normal/neighbors, maximum finite and extreme ratios
- Include both operand orders, common power-of-two rescaling and deterministic
  bit-stratified random inputs, not only uniform values in `[-100,100]`
- Test non-finite and overflowed-wrapper cases against the explicitly declared
  exclusion or checked-failure behavior
- Independently qualify native context, recording libm path/hash and package,
  architecture, compiler/flags, rounding mode, FTZ/DAZ state, source/input hashes
  and symbol/call path. Distinguish literal, runtime-pointer and pinned-source
  controls; do not choose profiles by trying Bend candidates until one passes
- Route only angle APIs through the new qualified selector. Re-run old Apple/Sun
  probes and the unchanged complete canonical corpus

A corpus pass is evidence, not an exhaustive proof over every F32 pair. The
current strict failure remains until the new profile actually passes its gates.

## Device and operational completion

Run primitive, scalar, wrapper and full suites with forced device execution.
Verify dispatch rather than accepting CPU fallback. Exercise subnormal bit
preservation, deep fallback execution, limb carries/shifts, batching, stack bounds
and device resources. Existing Metal results for older profiles do not cover this
new arithmetic/kernel. Report correctness and performance separately: portable
limb arithmetic and the 32-term fallback can be expensive.
