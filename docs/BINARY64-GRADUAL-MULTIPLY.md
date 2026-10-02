# Private directly rounded binary64 product with gradual output

Current integration note: the new [private modern scalar adapter](MODERN-ANGLE.md)
consumes this helper under the same checked contract. Historical “no consumer”
statements and future-kernel/remaining-work sections below describe the isolated
prerequisite checkpoint. No existing public image/math consumer, helper
implementation or public contract changes. The current scalar adapter status is
recorded separately at the link above.

`src/binary64_gradual_multiply.bend` provides private
`checked(ah,al,bh,bl) -> Maybe<binary64_fma.Words>` on canonical high/low U32
words. The exact real product is rounded **once**, nearest with ties to even.

- `a`: signed zero or normal with unbiased exponent `[-277,0]`
- `b`: signed zero or normal with unbiased exponent `[-885,0]`
- Both operands are validated before any zero shortcut. Nonzero subnormals,
  infinities, NaNs and normals outside the operand-specific interval return
  `None`, including invalid-with-zero pairs
- Results may be normal, subnormal or zero. Every result sign is operand-sign
  XOR, including exact and underflowed zero

This standalone asymmetric rectangle is not generic subnormal-input arithmetic.
It promises no other rounding mode, ambient mode, exceptions, errno or NaN
payload behavior. It has no existing library consumers, public re-export or API
status promotion. Existing arithmetic, projection/resize, angle sources, profile
selectors, fixtures, expected results and tolerances remain unchanged.

## Exact bounds and single rounding

For nonzero accepted operands, let `L=2^52`, `L<=Ma,Mb<2L`, `P=Ma*Mb`,
`S=Ea+Eb` and `B=S+2046` (the stored-exponent sum). Then
`2^104<=P<2^106`, `S in [-1162,0]` and `abs(a*b)=P*2^(S-104)<4`.
The existing FMA module's four-U32 `Product.mul` retains every one of the 106
bits. Its 53 shift/add iterations and working shifted multiplicand fit in 128
bits. No preliminary significand rounding takes place.

For `S>=-1022` (`B>=1024`), the exact product is normal. Its top bit is at
`104+h`, `h in {0,1}`. A right-shift/jam by `49+h` obtains a 56-bit normalized
window; the unchanged `F.pack(sign,B-1023+h,window)` performs one nearest-even
rounding. The maximum input significands multiply to
`4-2^-50+2^-104`, so rounding cannot reach 4 or overflow binary64.

For `S<=-1023`, measure the product in minimum-subnormal quanta:

`abs(a*b)/2^-1074 = P/2^k`, where `k=-S-970=1076-B in [53,192]`.

- If `k>=107` (`B<=969`), `P<2^106<=2^(k-1)` is strictly below half minimum
  subnormal. The helper returns XOR-signed zero directly
- Otherwise, right-shift/jam `P` by `k-3` (`50..103`) into a window `W`.
  Divide `W` by 8 and increment exactly when its three-bit tail exceeds 4,
  or equals 4 and the retained low bit is odd
- The rounded integer `Q` is at most `2^53-2`. Its bits **are the unsigned raw
  result encoding**: below `2^52` it is subnormal/zero; from `2^52` upward it
  has stored exponent 1. OR the sign into the high word directly

The local gradual round-and-encode body uses `F.Words.add` for low-word carry.
It never masks away bit 52 or predicts an exponent before rounding. In
particular `S=-1023` may already produce a normal value, or round across the
max-subnormal/min-normal boundary. At `S=-1024`, even maximum significands round
to maximum subnormal, never minimum normal.

The reused `F.Magnitude.window` is independent of the FMA accumulator width.
It discards whole limbs while retaining a Boolean sticky bit, takes at most
three following limbs (zero-padding missing limbs), and merges the residual
`0..31` shift. Its explicit zero-residual branch avoids a shift by 32.
Only discarded bits at this final step are jammed. All significant retained
windows fit within 56 bits; four input limbs suffice. FMA's fixed 29-limb
alignment/accumulation and lattice-dependent finish are not used or changed.

At `k=105`, `P=2^104` is a reachable exact half-minimum-subnormal tie. At
`k=106`, a tie would require `P=2^105`, which is impossible for two accepted
significands: both factors would have to be powers of two, and only `2^52`
is in `[2^52,2^53)`. Tests of that synthetic tie are labeled internal controls.
These are written algebraic bounds, not machine-checked universal theorems.

## Controls and independent oracles

Three explicit witnesses prevent a 53-bit-round-then-subnormal implementation.
With `a=2ea0000000000001`, the respective `b` and once-rounded results are:

| b | Correct result | Wrong double-rounded result |
|---|---|---|
| `1150000000000004` | `0008000000000003` | `0008000000000002` |
| `115ffffffffffffd` | `000fffffffffffff` | `0010000000000000` |
| `0e0fffffffffffff` | `0000000000000001` | `0000000000000000` |

Negative mirrors are also fixed controls. Four literal tiny-kernel products
from the separately derived `y32=00000001` cases are retained by exact operands:

| x32 | a=z | b=e | RN(z*e) |
|---|---|---|---|
| `75000000` | `2ff0000000000000` | `8fd5555555555555` | `8001555555555555` |
| `7b000000` | `2f30000000000000` | `8d95555555555555` | `8000000000000001` |
| `7b800000` | `2f20000000000000` | `8d65555555555555` | `8000000000000000` |
| `7f000000` | `2eb0000000000000` | `8c15555555555555` | `8000000000000000` |

Those controls establish this product's words, not execution of a full kernel.
The primary oracle decodes to exact Python `Fraction`, multiplies and searches
adjacent binary64 values by exact rational distance and parity. It reuses the
reviewed generic FMA decoder/search unchanged, not candidate limbs or packing.
Zero sign is supplied separately because rational zero has no sign.

The secondary C oracle uses ordinary runtime multiplication through a volatile
function pointer, volatile operands/result and `memcpy`. It does not substitute
`fma(a,b,0)`. Its 63 exact controls include signed zeros, both tie parities,
transition neighbors, all double-rounding witnesses, subnormal-input-to-normal
DAZ detection, and normal-input-to-subnormal FTZ detection. Qualification requires
IEEE binary64 layout, `DBL_HAS_SUBNORM==1`, `FLT_EVAL_METHOD==0`, no fast math,
`FE_TONEAREST` and checked x86 MXCSR or AArch64 FPCR. Unsupported architectures
fail closed. Control mode is checked before/after preflight and after the corpus.
Flags are `-std=c11 -O2 -frounding-math -fno-fast-math -ffp-contract=off -fno-lto`,
linked with `-lm`. Compiler/runtime identities, control state and artifacts are
retained. Some native preflights lie outside the candidate rectangle solely to
qualify native behavior; candidate rejection remains required for those inputs.

## Verification and proof boundary

Run using the already installed pinned toolchain, without changing it:

```sh
python3 tools/binary64_gradual_multiply_probe.py --bend-source "$BEND_SOURCE"
python3 -m unittest discover -s tests -v
bun "$BEND_SOURCE/bend2/main.ts" PROOF.bend --check-only
```

The deterministic corpus has **30,861 observations**, 30,509 accepted and 352
checked rejections. It includes all accepted exponents/signs/operand positions,
both product-top bits, every gradual shift `k=53..192`, all 52 significand bit
and bit-hole positions, explicit shift-limb boundaries `66/67/68` and `98/99/100`,
normal/gradual/zero transitions, tie parities and neighboring inputs, zero signs,
invalid classes and 4,096 deterministic random word pairs. Serial programs
contain at most 256 operations and 16 five-U32 framed records per output line.
Shifts `53..106` exercise retained-window execution; `107..192` exercise the
proved zero fast path. Every ID, kind, tag, type, count and payload is checked
independently per lane.
Old success and compiled outputs are invalidated; consumed input/program/build/
stdout artifacts and source/compiler/overlay/runtime identities are rechecked.

The proof entry point adds two structural branch laws, sixteen concrete checked
product/rejection results and two internal raw-window boundary equalities to
51 existing laws. These limited laws do not establish arbitrary multiplication,
window correctness, rounding or kernel reachability. Exact differential tests
and algebraic bounds are distinct complementary evidence.

CPU-one-thread, CPU-two-thread and JavaScript each match all 30,861 complete
observations in 121 programs: 14,850 normal outputs, 8,657 subnormals, 7,002
signed zeros and 352 rejections. The native oracle passes all 63 controls with
Clang 19.1.7, RN-even, MXCSR 8064 before and 8114 after preflight (only status
flags differ; FTZ/DAZ and directed-rounding bits remain clear). All 239 repository
Python tests pass, including 30 new focused tests. All 71 laws check with the
complete `All terms check.` verdict. The focused report retains 54 source/
dependency hashes and 1,351 artifact hashes.

Existing narrowing, FMA, add/subtract and normal operations re-pass all 134,954
observations per lane. Legacy arithmetic, GNU/Sun angles, inverse trig and
trailing ownership/transform/decoding, examples and QOI checks are preserved.
A fresh canonical rebuild and full all-field audit again give 260/261 scenarios
per lane: the only differing word is the existing angle pixel `(6,0)`, native
`3fc90fdb` versus Bend `3fc90fda`. Aggregate conformance remains failed.

Independent read-only review regenerated inputs/programs, recomputed all focused
expectations with a separately expressed integer-rational rounder, replayed
native/all candidate lanes and preserved regressions, and verified retained
hashes, canonical fields, fresh example/QOI outputs and unchanged API statuses.
It found no blocking findings and cleared this private checkpoint.

Final verified counts, three-lane and regression results, artifact hashes and
independent review are recorded in [durable evidence](evidence/binary64-gradual-multiply.json).
No GPU, hosted, exhaustive-input or performance-parity claim is made.

## Remaining modern-angle work

This solves the isolated literal tiny-product arithmetic prerequisite. The
entire pinned scalar angle kernel, both fallbacks, operation-by-operation domain
integration, native reference qualification, wrapper domains and forced-device/
resource evidence remain open. See [ANGLE-PLAN.md](ANGLE-PLAN.md). Nothing here
changes the existing strict canonical angle mismatch.
