# Pinned atan2f arithmetic-domain derivation

Written domain analysis of the pinned glibc 2.41 `e_atan2f.c`, independent of the
Bend kernel ([MODERN-ANGLE.md](MODERN-ANGLE.md)). It justifies the domains of the
private binary64 helpers ([BINARY64.md](BINARY64.md)) for every finite-input
kernel call. The exact finite coefficient checker is `tools/modern_angle_bounds.py`
(gate `modern-angle-bounds`). Its finite checks and the algebraic arguments below
are separate from implementation and differential-test evidence. Line numbers
refer to the pinned source.

## Result and qualification

The explicit binary64 FMA/add/sub operations, including the compensated polynomial,
can be bounded to normal-or-exact-zero results for finite binary32 inputs under
round-to-nearest-even. A coefficient-specific finite check is needed to bound the
polynomial's low-component cancellation chain; the script here reproduces that
check with exact rationals. The algebraic error-envelope argument below is a
written proof, not a machine-checked proof or an exhaustive input-pair test.

The literal whole kernel does **not** have a normal-only multiplication domain:
line 83's `z*e > 0` really produces binary64 subnormals and negative zero. A
bit-faithful intermediate port must support those products (Jonlib does, through
the gradual-output product). A result-bit-only port could replace this particular
comparison by a separately justified sign/nonzero predicate; see section 8.

## 1. Source and reproducibility

Source: https://github.com/bminor/glibc/blob/74f59e9271cbb4071671e5a474e7d4f1622b186f/sysdeps/ieee754/flt-32/e_atan2f.c

- Git blob: `82a0151293cda9cf89d6a18b6f8b35d4fdaeddd4`
- File SHA-256: `96f9c81b6e870c256cc0757f6d88f5290ed35db8d5b640b9e757d6feca96ae38`
- The complete unmodified source, including its notice, is `tools/reference/modern_atan2f_glibc241.c`
- Canonical coefficient-token SHA-256: `125552fc2f4c6662ff983ff94095f6c77984dad60d66b2bc1a52da1d29b93c44`
- Canonicalization: each original c[32][2] hex pair, `high,low\n`, in index order
- Run: `python3 tools/modern_angle_bounds.py`

The script validates both source hashes, parses just c[32][2], decodes its hex
literals by integer arithmetic, enumerates a conservative necessary set for a
low-component reset to vanish, and checks every pair in neighboring sets.
All PASS predicates use Fraction/integer arithmetic. Native float is only used
for a redundant check that each hex literal has the same exact rational value.
The script does not compile or run C or Bend.

Assumptions: finite binary32 inputs, exact bit-preserving promotion, correctly
rounded binary64 division/multiply/add/sub and explicit FMA, RN-even, and the
written source's operation order. This does not establish exception, errno,
other-rounding-mode, FTZ/DAZ, compiler-contraction, or device behavior.

## 2. Notation and two useful facts

E(v)=floor(log2(abs(v))) for v!=0. A binary64 normal v has a dyadic quantum no
finer than 2^(E(v)-52). If operand quantum exponents are q_a and q_b, their
exact sum is an integer multiple of 2^min(q_a,q_b); cancellation can make its
actual least nonzero quantum coarser, or give exact zero. Their exact product
is an integer multiple of 2^(q_a+q_b). RN cannot introduce a finer quantum
when the exact nonzero result is already on a normal dyadic lattice.

Anchor lemma: if binary64 a!=0 and abs(a)>=2^L, RN(a+b) is either exact zero or
has magnitude >=2^(L-54), provided this lower bound is normal. For operands
far apart, cancellation cannot reduce the larger by more than a factor two.
For comparable opposite-signed operands, both operand binades are >=L-1 and
their exact difference has quantum >=2^(L-53). The extra factor two is slack.

u=2^-53. Multiplication/division roundings of a normal result satisfy the usual
relative-error bound u. Exact-zero cases must be retained, not replaced by a
strictly-positive lower bound.

## 3. Reachable ratio bounds, including the full fallback

All nonzero reduced ratios satisfy 2^-277 <=abs(z)<=1 (lines 163-166). For
positive finite raw words A<=B and B-A<k*2^23, abs(small/large)>=2^(-k-22).
For normal small inputs the stronger bound >=2^-k holds. For subnormal A,
the worst case is A=1, B=k*2^23, giving exactly 2^(-k-22).

Thus the rational guard at lines 168-171 gives abs(z)>=2^-49, so z2/z4/z8
are normal. The full compensated fallback has the stronger abs(zh)>=2^-47:

- If gt=0 and the tiny test at 198 is rejected, either magnitudes are equal or
  ax-ay<25*2^23, giving 2^-47
- Any nonzero offset cannot pass the ambiguity test if abs(z)<=2^-27. Every
  numerator coefficient is <= its denominator counterpart; monotonic RN in
  the identical positive expression trees gives 0<cn0/cd0<=1. Hence the
  perturbation of the offset is at most 2^-27. The low 28 bits of pi/2 and pi
  are 0x4442d18, more than 2^26 word steps from the lower ambiguity window.
  Adding this perturbation moves pi/2 by at most 2^25+1 binary64 word steps
  (pi by fewer). Negative offsets have the same distance. Therefore no hit
- This also excludes axes/zero reduced ratios from the compensated fallback

Reachable minimum-ratio fallback test: (y,x) binary32 words
`(00000001,0c800000)` gives zh=2^-47. Its raw distance is 25*2^23-1, its
first-pass r equals z and passes the ambiguity test, and it rejects the tiny
test. Its negative-y counterpart is useful too.

## 4. Quotient residual and squared double-double input

For a promoted binary32 denominator d, its quantum is >=2^(E(d)-23), even
when its original representation was subnormal. With q=RN(n/d), the residual
fma(q,-d,n) is on the lattice 2^(E(q)+E(d)-75). Its magnitude is <=about one
division-rounding ulp times abs(d); the cancellation leaves at most 25 bits,
so the FMA residual is exact and normal or zero. Correlation with n gives a
global nonzero residual lower bound 2^-225. Dividing it by d gives either zero
or magnitude >=2^(E(q)-76), hence:

- Tiny branch correction e/x: zero or >=2^-353
- General fallback zl: zero or >=2^-123; abs(zl)<=2^-51*abs(zh)
- Exact zero occurs when the quotient is exactly representable (e.g. powers
  of two, equal magnitudes); it is RN cancellation +0 before later sign flips

For the call muldd(zh,zl,zh,zl) at 213:

- ahhh=RN(zh^2) >=2^-94; the exact product residual is zero or >=2^-198
- Each equal cross product is zero or >=2^-170, with quantum >=2^-222
- Their sum is exactly twice that product, with quantum >=2^-221
- Adding the residual and final renormalization preserve that lattice
- Therefore xh=z2h is in [2^-96,1], and xl=z2l is zero or >=2^-224 in
  magnitude; abs(xl)<=2^-50*xh. The powers here deliberately include slack

Why xh<=1: equal input magnitudes give zh=+/-1,zl=0 exactly. Unequal finite
binary32 magnitudes have relative separation at least 2^-24; binary64 quotient
and double-double errors cannot bridge that gap. No low-result underflow was
assumed in deriving these bounds: the displayed exact lattices are normal.

## 5. Polynomial upper bounds and exact finite reset check

The finite script checks all these facts about the pinned coefficients:

- High coefficients alternate signs with strictly decreasing magnitudes a_i
- Every a_i>=2^-23 and every a_i-a_(i+1)>=2^-23
- Every low coefficient has magnitude in [2^-87,2^-55)
- q_i, its least nonzero dyadic bit exponent, is <E(c_i_high)-53
- max_i<31 2^(q_i+53)<=2^-54

For xh in [0,1], the exact high-only Horner polynomial H_i has sign c_i_high
and magnitude in [a_i-a_(i+1),a_i], with the obvious final-coefficient case.
The following loose inductive floating invariants suffice:

  abs(ch-H_i)<2^-34,  2^-24<=abs(ch)<2,  abs(cl)<=2^-45

Base case is immediate. At this point low-component normality has not been
proved: use monotonic RN against normal upper envelopes, which remains valid
even if an actual low product or sum gradually underflows. Given the invariant
and abs(xl)<=2^-50*xh, the cross terms at lines 36-37 satisfy

  abs(RN(ch*xl)) <= RN(2^-49*xh) < 2^-48*xh
  abs(RN(cl*xh)) <= RN(2^-45*xh) < 2^-44*xh

Both comparison envelopes are normal since xh>=2^-96. Applying the same
monotonic-envelope argument to the cross-term sum and residual addition gives
the bound <2^-42*xh at 39-40, without applying a relative-error model to an
unproved-normal low value. The returned high differs from ch*xh by <2^-41*xh.
Renormalization has abs(low)<2^-50*xh: ahhh and the new high are normal and
within a factor two, so their subtraction is exact (Sterbenz). Before its
final rounding, the low is the high addition's rounding error, bounded by a
normal envelope <2^-51*xh; monotonic RN gives the stated bound even if that
actual low is subnormal or zero.

The subsequent high addition contributes <2^-52 absolute error. Fewer than
32 local errors <2^-40 give <2^-35, within the chosen 2^-34 invariant.
Coefficient gaps dominate this error, retaining the signs, magnitude lower
bound and abs(product_high)<abs(c_i_high). FastTwoSum at 55-56 is consequently
exact. Monotonic RN against the normal magnitude envelopes for its residual,
c_i_low and the renormalized product low bounds the new low by <2^-48,
satisfying 2^-45. Normality of the actual low components follows only from
the separate lower-bound induction below.

Let s_i=RN(tl+c_i_low), the inner add at line 58. If nonzero, the anchor lemma
gives abs(s_i)>=2^-141, and the subsequent addition to product-low gives cl_i
either zero or >=2^-195. The danger is s_i=0, which might propagate a small
low component through repeated multiplications. We exclude adjacent zero s_i.

Necessary candidate construction for s_i=0:

1. tl and c_i_low are on normal lattices, so s_i=0 means tl=-c_i_low exactly
2. If product-high h has magnitude >=a_i/2, the opposite-signed high addition
   is exact by Sterbenz, giving tl=0, impossible. Thus abs(h)<a_i/2, and th
   and c_i_high are both multiples of Delta=2^(E(c_i_high)-53)
3. If E(h)>q_i+52, h, th, and c_i_high are all multiples of 2^(q_i+1), so
   they cannot give tl=-c_i_low, whose lowest bit is q_i. Thus abs(h)<B_i,
   where B_i=2^(q_i+53)
4. Enumerate every integer k with abs(k*Delta-c_i_low)<B_i; retain exactly
   representable binary64 h=k*Delta-c_i_low of the required opposite sign
5. Associate the positive rational r_i=h/c_(i+1)_high with each candidate

The script checks every adjacent pair of candidate sets and finds

  abs(r_i-r_(i+1)) > max(r_i,r_(i+1))/128

The minimum exact separation ratio is
15774609247875967406654182287 / 1295976736192553293463508732304,
at indices 24 and 25. This decimal-free inequality is the finite computed
part of the argument, not a random sample or an approximate numerical bound.

Algebraic link from candidates to the real xh (error envelope): s_i=0 implies
abs(h)<2^-54. The high-product bound abs(h)>=2^-25*xh gives xh<2^-29. At such
xh, the prior Horner high differs from c_(i+1)_high by <2^-27 relative:
the preceding product is at most 2*a_(i+1)*xh, plus <2u*a_(i+1) high-add error.
The muldd high error <2^-41*xh divided by a_(i+1)*xh is <=2^-18. Consequently

  abs(r_i/xh-1)<2^-17

Two zero s_i in consecutive iterations would therefore have candidate ratios
within relative 2^-15 of each other, contradicting the exact >2^-7 separation.
No approximately estimated envelope is needed; these are conservative powers
of two derived from the displayed invariants.

## 6. Polynomial lower bounds, operation by operation

Using the preceding no-adjacent-reset lemma, a nonzero incoming cl is >=2^-344
(base cl is much larger; a nonzero reset gives >=2^-195). In any muldd:

| Operation | Nonzero lower bound / quantum |
| --- | --- |
| ch*xl | magnitude >=2^-248, quantum >=2^-300 |
| cl*xh | magnitude >=2^-440, quantum >=2^-492 |
| ch*xh high | magnitude >=2^-120 |
| fma(ch,xh,-ahhh) | exact, zero or magnitude >=2^-224 |
| alhh+ahlh; residual+that | zero or >=2^-492 by lattice |
| renormalized high | >=2^-121 |
| ahhh-new_high; plus residual accumulation | zero or >=2^-492 |
| s_i=RN(tl+c_i_low), if nonzero | >=2^-141 |
| cl=RN(product_low+s_i), if s_i!=0 and result!=0 | >=2^-195 |

If s_i=0, the previous reset is nonzero (or it is the initial coefficient),
so its incoming cl is >=2^-196. Then cl*xh has magnitude >=2^-292 and quantum
>=2^-344, improving the returned low to zero or >=2^-344. That proves the
inductive incoming bound. Exact cancellation is allowed at every low result.
Every displayed lower bound is far above the binary64 normal threshold.

## 7. Last double-double product and offset/rounding cancellation

At 253, xh is signed zh (>=2^-47 in magnitude), xl is signed zl (zero or
>=2^-123), ch is the polynomial high, and cl is zero or >=2^-344.

- ch*xl: zero or magnitude >=2^-147, quantum >=2^-199
- cl*xh: zero or magnitude >=2^-391, quantum >=2^-443
- Explicit FMA residual: zero or >=2^-175
- Renormalized low pl: zero or >=2^-443; high ph is nonzero

In fact H_0 is between 2/3 and 1, so ph has magnitude at most 1+2^-33 and
has its expected reduced-angle sign. Consequently nonzero offsets cannot
cancel sh below 1/2. Zero offsets leave a nonzero high; the loose bound
abs(sh)>=2^-72 suffices. All these intermediates have magnitude <8.

Using only that loose bound gives the following conservative floors:

- ((off-sh)+ph): zero or >=2^-124
- Adding pl and then offl: sl zero or >=2^-495
- rf and th are normal binary32/re-promoted binary64, with abs(th)>=2^-73
- dh=sh-th: zero or >=2^-124
- tm=dh+sl: zero or >=2^-547
- th*2^-60 and th+/-that are normal; no zero exponent mask underflow at 263-264
- tm*{0.75,1.25}: zero or >=2^-548, quantum >=2^-600
- r=th+tm: zero or >=2^-600 even without using its stronger magnitude bound

The two zero offsets require correct zero-sign arithmetic; absence of binary64
subnormal results does not make signed-zero behavior optional.

## 8. Tiny branch and its real gradual-underflow multiplication

At lines 70-76, nonzero bounds are z>=2^-277, zz>=2^-554, abs(cz)>=2^-279,
abs(cz*zz)>=2^-833, and abs(e/x)>=2^-353 when that correction is nonzero.
The rounded cubic term's quantum is >=2^-885 and the quotient correction's
is >=2^-405. Thus their addition produces exact zero or a normal value
>=2^-885. This includes cancellation; it does not assume the two terms add
without cancellation.

Line 83 is different. For exact power-of-two quotient, e/x is zero and the
remaining e=c*z^3 is an exact normal binary64 value. The product z*e can be
subnormal or zero. With y word 00000001, these are reached through the actual
ambiguity/tiny guards (x positive, off=0, z has zero low 28 bits):

| x word | z | RN(z*e) binary64 word |
| --- | --- | --- |
| 75000000 | 2^-256 | 8001555555555555 |
| 7b000000 | 2^-268 | 8000000000000001 |
| 7b800000 | 2^-269 | 8000000000000000 |
| 7f000000 | 2^-276 | 8000000000000000 |

The exact checker reproduces these words without a native FMA/libm oracle.

If only result bits under RN matter, a narrowly documented replacement is
`e!=0 && sign(z)==sign(e)`, with the following underflow-equivalence proof:

- If signs differ, the original product is negative or -0, so both tests fail
- If abs(z)<2^-128 and signs agree, the quotient correction is nonzero and
  dominates the oppositely signed cubic term. Its magnitude is >=2^(E(z)-76),
  the cubic is <2^(3E(z)+3), and RN addition leaves at least half the former.
  Their positive product is >=2^(2E(z)-77)>=2^-631, hence normal
- If abs(z)>=2^-128, the cubic's quantum is >=2^-438 and the correction's
  is >=2^-256, so nonzero e>=2^-438 and abs(z*e)>=2^-566, also normal
- e=0 gives false in both cases

This equivalence does not preserve line 83's intermediate words, floating-point
exception flags, or every non-RN behavior. Keep it separate from a literal port.

## 9. Helper domains that cover the kernel

The bounds above select the private helper contracts in [BINARY64.md](BINARY64.md):

- FMA: a,b signed zero or normal with exponents E in [-277,127]; c signed zero
  or normal with E in [-554,255]. The exact product-plus-addend is an integer
  multiple of 2^-658 with magnitude <2^257, so its correctly rounded result is
  normal or exact zero
- Exact 106-bit product, exact signed accumulation/cancellation, then one RN
  step. A fixed 29-U32 magnitude accumulator spans this entire domain; a
  smaller jam-based implementation would require its own rounding proof
- Inputs outside the contract fail closed, never silently flush or reuse a
  different profile. This is not general binary64 FMA with gradual underflow

All explicit FMA calls in this pinned kernel fit this asymmetric contract.
A normal/zero add/sub domain with input E in [-900,130] also suffices: a nonzero
sum/difference is >=2^-952 and <2^132. This covers the actual cancellation
floors while keeping arbitrary subnormal inputs excluded. The only multiplication
that leaves the normal-result domain is line 83's `z*e` (section 8), covered by
the separate gradual-output product.

Exact controls that distinguish a correct implementation:

- fma(1+2^-52,1-2^-52,-1) = -2^-104 (multiply-then-add wrongly gives zero)
- fma(1,1,2^-53)=1 and fma(1,1+2^-52,2^-53)=1+2^-51 (both tie parities)
- a=b=2^-277*(1+2^-52), c=-2^-554*(1+2^-51): result +2^-658 (domain floor)
- Exact product cancellation, product carry, large exponent gaps, plus the
  above actual fallback/tiny controls and neighboring binary32 words
- For RN zero signs: -0+-0=-0; mixed zero addition=+0; opposite nonzero exact
  cancellation=+0. Multiplication and division use sign XOR. FMA with a zero
  product and zero addend returns their common sign if equal, otherwise +0;
  nonzero exact product cancellation is +0. Unary negation flips zero signs
- Enumerate all zero-sign triples for FMA and all zero-sign pairs for add/sub;
  include both orders (+0,-0), which exposes the legacy addition gap (section 10)

## 10. Legacy arithmetic that does not substitute

`resize_numeric.bend`'s addition returns b whenever a is zero. Thus +0 + -0
returns -0 rather than RN +0. Its exact nonzero cancellation path normalizes to
+0, which is correct for RN. Legacy consumers keep that behaviour; the audited
zero semantics live in the private binary64 layer. `float64_ops.bend` has
rounded normal multiplication/division but no binary64 FMA. `fused.bend` is an
F32 result helper and cannot supply these binary64 product residuals. Promotion
through `float64.promote` preserves binary32 subnormals; normal-only
`Double.from_f32` is not interchangeable.

## 11. Scope of this analysis

This page establishes operand domains only. It is not a proof of implementation
correctness, of full kernel intermediate/result parity or of exhaustive
input-pair coverage, and the written algebra is not mechanized; those are covered
(to the extent stated) by the `angle-kernels` gate and the helper gates described
in [MODERN-ANGLE.md](MODERN-ANGLE.md) and [BINARY64.md](BINARY64.md). The finite
coefficient check is not any of those gates.

## 12. Retained branches with no finite-input RN witness

These are written reachability arguments checked against the pinned source and
exact constant inequalities. They are not conclusions from
zero branch counts, exhaustive input execution or machine-checked theorems.
The implementation retains every source branch; synthetic helper tests are
reported separately from reachable scalar cases.

### Tiny increment

At the tiny boundary, `bits(z) & 0x0fffffff == 0`, so the nonzero binary64
quotient has at most 25 significant bits. The promoted binary32 denominator has
at most 24. Their exact product lies on lattice
`2^(E(z)+E(x)-47)`. Since `y` is within one binade of this product and has at most
24 bits, a nonzero `y-z*x` shares that lattice. But nearest-even quotient rounding
gives `abs(y-z*x) < 2^(E(z)+E(x)-52)`. These bounds are incompatible unless the
residual is exactly zero. The true FMA therefore returns +0 before division;
the nonzero cubic correction has the opposite sign to `z`. The literal gradual
`z*e` is negative or negative zero and cannot take the increment branch.

### Final correction guard false

The general fallback's `th` is an exactly re-promoted, nonzero normal binary32
value (the conservative lower bound is `2^-73`). Multiplication by `2^-60` is an
exact normal binary64 scaling. Its magnitude is strictly below half of even the
smaller adjacent binary64 spacing, including a binade boundary. Both `th+delta`
and `th-delta` therefore round to `th` under RN, so the source equality is true.
Both subsequent 1.25 and 0.75 choices remain reachable and separately tested.

### Tiny nonboundary

The tiny guard's raw magnitude distance at least `25*2^23` implies
`q=abs(RN(y/x)) <= 2^-25`. Its magnitude ordering forces `gt=0`, so the only
nonzero offsets are ±π. They have exponent 1 and low 28 encoding bits
`0x04442d18`. Since the positive rational numerator coefficients do not exceed
the corresponding denominator coefficients, the reduced-angle perturbation
has magnitude at most `2^-25`. It moves ±π by at most `2^26+1` encoding steps.
The remaining lower-boundary distance is exactly
`0x04442d18-(2^26+1)=4,467,991 > 8`; the upper ambiguity window is farther away.
Thus negative X and the zero/axis cases cannot enter this tiny fallback. It
suffices to consider positive X, nonzero Y and a zero offset. Write
`s=abs(y/x)` for the exact positive quotient magnitude.

In the rational path let `v=RN(q*q)<=2^-50`. The pinned constants satisfy
`0<cn[1]<cd[1]<3` and `cd[1]-cn[1]<1/2`, independently checked as exact rationals.
After the two products and their additions to 1, write the results as N and D.
Rounding-error bounds give `0<=D-N<4*2^-52`; because both are on the same
`2^-52` lattice near 1, `D-N<=3*2^-52`. The z4 contributions are `<2^-98`, and
z8 contributions are smaller still; they cannot move these rounded N,D values.
Consequently `1-3*2^-52 <= R=RN(N/D) <= 1`, using monotonic rounding at the exact
representable lower endpoint. The final product obeys
`q-abs(initial_r)<6.5*ULP(q)`. In the shortcut path the difference is zero.

Let t be the low-28-zero grid point within eight raw encoding steps of
`abs(initial_r)`, and let `U=2^(E(t)-52)`. Binade boundaries do not escape this
bound: a grid point below the next binade is at least `2^28*U` below it; the
nearby eight ambiguity steps plus at most thirteen adjacent-spacing steps force
`E(q)<=E(t)`. Combining division rounding, the rational perturbation and the
ambiguity window gives `abs(s-t)<0.5*U+6.5*U+8*U=15*U`.

The bound `abs(s-t)<15*U` makes `abs(y)` comparable to `t*x`. Because y also
has at most 24 significant bits, its quantum is no finer than the product
lattice. If `abs(y)-t*x` were nonzero, t's at most 25 significant bits and x's
at most 24 would therefore put that residual on lattice
`2^(E(t)+E(x)-47)`. Dividing by
`abs(x)<2^(E(x)+1)` would require `abs(s-t)>16*U`, a contradiction. Hence
`s=t` exactly and `q=t`. Every reachable finite-input RN tiny case therefore
has the source boundary predicate true. The retained false branch is tested
only through explicitly synthetic helper controls.
