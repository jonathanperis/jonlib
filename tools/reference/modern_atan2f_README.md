# Pinned finite atan2f reference tooling

This directory does not select a public angle profile. No corpus here establishes
Bend parity, exhaustive correctness, floating-point exception/errno behavior,
other rounding modes, or device support.

## Source and adaptation

`modern_atan2f_glibc241.c` is the complete, unmodified MIT source at glibc release
commit `74f59e9271cbb4071671e5a474e7d4f1622b186f`, path
`sysdeps/ieee754/flt-32/e_atan2f.c`, blob
`82a0151293cda9cf89d6a18b6f8b35d4fdaeddd4`, SHA-256
`96f9c81b6e870c256cc0757f6d88f5290ed35db8d5b640b9e757d6feca96ae38`.
The full notice remains in both C source copies and
`LICENSES/core-math-atan2f.txt`. No glibc test file was copied.

The altered `modern_atan2f_adapted.c` removes out-of-domain nonfinite behavior,
adds non-arithmetic checkpoint instrumentation, and retains the source's finite
operation order, coefficients, explicit FMA calls and both complete fallbacks.
The tiny `z*e` expression is assigned once to a double for tracing before its
original comparison. Its actual gradual-underflow bits are retained.

The unmodified source is compiled independently with an alias/header shim.
The adaptation's result must equal that separate source result for every finite
case. Runtime native `atan2f`, called through a volatile function pointer, is a
separate diagnostic result. It never defines the expected pinned-source profile.
All explicit FMA calls use a volatile runtime libm FMA pointer. Contraction and
fast math are disabled; the driver qualifies the same process before evaluating
any supplied pair. Nonfinite raw words are rejected before conversion or any
candidate/original/native angle operation.

## Run and provenance

With the project toolchain activated:

```
python3 tools/modern_angle_reference.py
python3 tools/modern_angle_reference.py --search-trials 100000000 --work .build/angle-search
python3 tools/modern_angle_reference.py --search-boundaries 100000 --work .build/angle-boundary-search
python3 tools/modern_angle_reference.py --search-tiny 50000000 --work .build/angle-tiny-search
```

`--compiler` can explicitly select another already-installed compiler. Builds
are fresh, subprocess output survives failures/timeouts, and the module records
source/adapted/shim/compiler/binary/input/library hashes plus exact command flags.
Preflight checks cover layout, no excess precision, RN mode, FTZ/DAZ/control
register state, nine true-FMA controls, seven direct narrowing controls and four
gradual-underflow controls. The same checks run again in the corpus process; a final-context JSON record on
stderr is checked and retained after execution without changing trace framing;
library hashes must still agree with the preflight snapshot. Libc package-manager
identity is recorded when available; an absent package database is stated as a
limitation rather than invented. Runtime libc version and loaded libm hash remain
separately recorded.

The Python API supplies `samples()`, `build_native(work, compiler)`,
`native_reference(rows, work, compiler)`, `parse_native(text, rows)`,
`validate_metadata(environment)`, `source_paths()` and `assert_pins()`.
`native_reference` returns `(metadata, records)`; no Bend execution occurs.

All 1,086 historical `angle_probe.samples()` entries remain first, in original
order, including duplicates. Their original JSON hash is checked. All 178
pinned-source/Sun differences remain in that unchanged prefix. The exact 178 IDs
and native/Sun words were independently matched to the retained historical
`clang-o2-strict.tsv` diagnostic, then frozen in
`modern_atan2f_historical.json`. Separate fixed hashes cover the IDs, all 178
differing records and all 1,086 complete result records, so matching only the
count cannot pass. Additional
controls include signed zeros, axes, quadrants, equal/adjacent magnitudes, every
finite exponent, subnormal significand patterns, raw exponent-distance guard
boundaries, common power-of-two rescaling, deterministic bit-stratified samples,
minimum general ratio `00000001/0c800000` and its negative-y counterpart, and
tiny products with x words `75000000`, `7b000000`, `7b800000`, `7f000000`.

`modern_atan2f_general_cases.json` retains a bounded subset of independently
native-generated general-fallback cases. Uniform ratio sampling uses xorshift64*
with stated seeds/budgets. The targeted generator samples binary32 angle
midpoints, applies native `tanl`, and forms bounded continued-fraction convergents
with numerator/denominator at most `0xffffff`; both are exactly representable
binary32 integers. `tanl` only proposes inputs. Retained outputs/branches come
from the pinned source, with no Bend feedback. This finds both final correction
scalings efficiently without an input-specific implementation correction table.

## Trace ABI

A record contains input `id,y,x`, Boolean `accepted`, separate binary32 result
words `pinned,original,native,sun`, `mask,index,gt`, `final`, and `events`.
`final` is `[high,low]` for the binary64 value immediately before final narrowing;
rejection uses null results and no events. Each event is `[tag,high,low]` with
unsigned 32-bit words. Event order is significant.

Branch flags: rational=1, shortcut=2, ambiguous=4, tiny=8, tiny_boundary=16,
tiny_increment=32, tiny_decrement=64, general=128, correction=256,
correction_up=512, correction_down=1024, early_zero=2048, reject=4096.
Early-zero and rejected records use index=gt=0. A zero-y negative nonzero-x
input continues the original reduction instead of taking early_zero.

Tags, in numeric order:

1. z
2. z2
3. z4
4. z8
5. cn0 (final)
6. cn2
7. cn4 (final)
8. cd0 (final)
9. cd2
10. cd4 (final)
11. rational (also 1 on shortcut)
12. signed_z
13. initial_r
14. tiny_z
15. tiny_residual
16. tiny_zz
17. tiny_cz
18. tiny_e
19. tiny_product (boundary only)
20. tiny_adjusted
21. zh
22. zl
23. z2h
24. z2l
25. poly_ch
26. poly_cl
27. ph
28. pl
29. signed_zh
30. signed_zl
31. product_ph
32. product_pl
33. sh
34. sl
35. th
36. dh
37. tm
38. corrected_tm (correction guard only)
39. final_r

Tags 25/26 repeat for all 31 completed Horner iterations, coefficients 30 down
to 0; no seed iteration is emitted. Internal muldd operation events are omitted,
while each observable high/low result is retained. Early-zero has no events.
Tiny returns end with tag20, ordinary/general returns with tag39.

## Tiny increment reachability

The increment source path is retained and instrumented, but is not covered by
the finite RN corpus. There is a stronger reason than sampling rarity: at its
boundary test, the rounded quotient z has at most 25 significant bits. Its exact
product with a binary32 x therefore has at most 49 significant bits. If y and
z*x differ, their separation near the quotient is too large to fit inside the
binary64 division's half-ulp rounding interval. Thus a quotient landing on this
boundary is exact; the FMA residual is zero. The cubic correction has sign
opposite z, so the literal product is negative or negative zero, never positive.
The RN boundary path decrements. This is a written reachability argument, not a
machine-checked exhaustive proof; the increment code has not been dropped and
zero observations are not misreported as exercised coverage.

## Tiny nonboundary reachability

A bounded 50,000,000-trial source-only tiny search (seed `0xA74A241`) observed
6,250,036 tiny hits, all on the boundary, and no nonboundary hit. That negative
search is not a proof. The following separate RN argument explains the omission:

1. Write finite binary32 magnitudes as integers N,D of at most 24 bits times
   powers of two. A nearby low-28-zero binary64 boundary q has at most 25
   significant bits. In the quotient's binade E, q is an integer multiple of
   `2^(E-24)`. A nonzero `N/D - q` (with the powers of two restored) has magnitude
   at least `2^(E-24)/D > 2^(E-48)`. This is more than 16 binary64 ulps there.
   Correct binary64 division therefore leaves a nonboundary z at least 16
   adjacent-word steps from every such boundary. The same calculation uses the
   lower binade's spacing beside a power-of-two boundary.
2. The tiny raw-word-distance condition implies `abs(z) <= 2^-25`. On the
   shortcut, the initial result is z for positive x. On the rational path,
   `z2 <= 2^-50`. All z4/z8 additions to the leading numerator/denominator sums
   are too small to change those sums. The pinned leading coefficients are
   below 3 and their difference is between 0 and 3/8. Including both product
   and sum roundings, cd0-cn0 is less than three ulps at 1, and is an integer
   number of those ulps, hence at most two. Thus the rounded cn0/cd0 belongs to
   `[1-2^-51,1]`. Multiplication by z moves its raw word by at most five steps,
   including a possible crossing into the lower binade. A nonboundary z cannot
   reach the first-pass ambiguity window of eight steps.
3. For negative x, the offset is signed pi. A perturbation of at most `2^-25`
   changes pi by at most `2^26` binary64 words. Pi's low 28 bits are `0x4442d18`,
   leaving distance `0x442d18` from the nearest lower ambiguity boundary even
   after that maximum perturbation. Such inputs cannot enter the tiny fallback.

Consequently a finite RN invocation that enters tiny must take its boundary
path. Together with the preceding exact-quotient argument, it must decrement.
These are source-specific written bounds, not machine-checked exhaustive input
proofs. Both nonboundary and increment code paths remain present and available
for direct synthetic branch testing; their absence in real-input evidence must
not be labeled exercised coverage. The final correction guard likewise compares
th plus/minus a relative `2^-60` perturbation: promoted finite binary32 th is
unchanged by either operation under RN, so the false guard belongs to other
rounding contexts, outside this profile.
