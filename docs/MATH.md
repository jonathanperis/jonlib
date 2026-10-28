# Jonmath profiles

The math implementation is Bend source in `jonmath.bend`, imported as
`import ./jonmath.bend as M`. Its `raymath.h` reference work package contains
six scalar, thirty-one Vector2, thirty-nine Vector3,
twenty-two Vector4, twenty-three Matrix and twenty-one Quaternion functions.
These remain partial profiles. Type ownership and migration from earlier imports
are documented in [MODULES.md](MODULES.md).

## Scalar API

`Math.PI()`, `Math.DEG2RAD()`, `Math.RAD2DEG()` and `Math.EPSILON()` are the
raylib/raymath macros as F32 values (`DEG2RAD`/`RAD2DEG` are the F32 quotients
the C macros evaluate). raymath's C++ constants map to `Vector2/3/4.zero()`,
`.one()`, `.unit_x()` ... `.unit_w()`, `Quaternion.identity()`
(`QuaternionUnitX`, which raymath defines as `{0,0,0,1}`) and
`Matrix.identity()` (`MatrixUnit`). Gate `constants` compares their bits with the
pinned headers.

- `Math.clamp(value, lower, upper)`: preserves the reference comparison order,
  including reversed bounds and signed zero.
- `Math.lerp(start, end, amount)`: linear interpolation/extrapolation; no factor clamp.
- `Math.normalize(value, start, end)` and `Math.remap(value, input_start, input_end, output_start, output_end)`.
- `Math.wrap(value, lower, upper)`: reference floor-based wrapping.
- `Math.float_equals(left, right)`: relative epsilon comparison with `0.000001`.

Gate `scalars` compiles the six from the pinned raymath.h with contraction off
and loads each input through a volatile. The corpus is signed zeros, one
subnormal, the least normal, the 2^24 boundary, the largest finite value, both
infinities and one quiet NaN (Remap sweeps one argument at a time and a
four-word grid, so five-argument products stay bounded). CPU-1 and CPU-2 match
every result bit, including equal bounds. JavaScript matches every non-NaN
bit. `Normalize` matches every propagated input NaN payload. A quiet NaN it
produces from an invalid operation matches by NaN-ness: IEEE 754 clause 6.3
leaves that sign unspecified, and upstream builds return either sign. The
sign of a quiet NaN `Lerp`, `Remap` or `Wrap` produces is not stable on
JavaScript, so that lane records it and does not require it. Clamp and
FloatEquals do not produce a NaN that way, so they match on JavaScript as well.

## Vector2 API

`Vector2` remains immutable `Data` with F32 `x` and `y` fields.

- Constructors: `zero()`, `one()`.
- Component operations: `add`, `add_value`, `subtract`, `subtract_value`, `scale`,
  `multiply`, `negate`, `divide`, `invert`, `min`/`min_for`, `max`/`max_for`.
- Metrics: `length`, `length_sqr`, `distance`, `distance_sqr`, `dot_product`, `cross_product`.
- Other operations: `normalize`, `lerp`, `reflect`, `equals`, `move_towards`,
  `clamp`, `clamp_value`, `rotate`/`rotate_for`, `refract`, `transform`,
  `angle`/`angle_for`, `line_angle`/`line_angle_for`.

Gate `vector2` compares `add`, `add_value`, `subtract`, `subtract_value`,
`scale`, `multiply`, `negate`, `divide`, `invert`, `length`, `length_sqr`,
`distance`, `distance_sqr`, `dot_product`, `cross_product`, `normalize`,
`reflect`, `equals` and `lerp` with contraction off. Inputs are a table, so
the C compiler emits the arithmetic instead of folding literals. The core grid
is signed zeros, one, a subnormal, positive infinity and one quiet NaN; the
wider edge (negative one, both infinities, the least normal, the 2^24 boundary,
the largest finite) is swept one component at a time. `negate`, `invert`,
`normalize`, `length`, `length_sqr` and `equals` match every result bit on
CPU-1, CPU-2 and JavaScript, including zero divisors and a zero length.
`add`, `add_value`, `subtract`, `subtract_value`, `scale`, `multiply` and
`divide` match every non-NaN bit and every propagated input NaN payload.
A quiet NaN produced by an invalid operation matches by NaN-ness: IEEE 754
clause 6.3 leaves its sign unspecified, and upstream builds return either
sign for the same inputs. The other operations match every non-NaN bit. The
sign of a quiet NaN their arithmetic produces is not reproduced. `min`,
`max` and `clamp` are compared on the glibc builtin profile by gate `extrema`.

`divide` takes two vectors; `invert` takes component reciprocals. `lerp` takes
two vectors and a scalar amount. `reflect` takes a vector and the supplied normal;
it does not normalize that normal. `equals` uses the reference epsilon on both axes.
`normalize` returns two positive zeros when the computed length is zero; otherwise
it multiplies both components by the reciprocal length in reference operation order.
`move_towards(vector, target, max_distance)` snaps to an identical target or a
target within a nonnegative step, and otherwise follows the reference direction
formula. Negative steps move away; they do not trigger the positive-distance snap.

`clamp` operates component-wise with the accurate reference profile;
`clamp_for(reference, vector, lower, upper)` selects the declared profile's
signed-zero behavior. The tested GNU reference retains the first operand on
zero ties; the accurate profile uses negative zero for minima and positive zero
for maxima. `clamp_value` clamps magnitude and preserves
zero vectors. Reversed magnitude bounds retain raylib's lower-before-upper
branch order. `refract(vector, normal, ratio)` returns positive zero components
for total internal reflection and otherwise applies the original formula.

`min_for(reference, left, right)` and `max_for(reference, left, right)` share the
same explicit zero-tie contract. `min` and `max` select the accurate profile.
A NaN loses to a number. Two NaNs keep the second operand under `Glibc239Libm`
(clang's builtin lowering of `fminf` and `fmaxf`) and the first under
`AppleLibm` (Apple clang's `fminf` and `fmaxf`).

The GNU label is a declared numerical profile, not a guarantee for every glibc
version/compiler evaluation path: constant folding, builtin lowering and native
glibc calls give three different zero-tie behaviours. The reference harness
selects the extrema profile from native controls instead of inferring it from the
host or the gradient/angle profile; see
[NATIVE-MATH-PROFILES.md](NATIVE-MATH-PROFILES.md).

Gate `extrema` compares Vector2, Vector3 and Vector4 `min_for` and `max_for`,
and Vector2 and Vector3 `clamp_for`, under the host's volatile `fminf`/`fmaxf`
profile with contraction off.
Inputs are a table and each word is loaded through a volatile, so clang lowers
`fminf` and `fmaxf` instead of folding the literals. CPU-1 and CPU-2 match every
bit of the 14465-case corpus, including infinities, subnormals, signed zeros and
both quiet-NaN signs. JavaScript matches those bits except where the selected
operand is a negative quiet NaN, which it returns as a positive quiet NaN.
Under `Glibc239Libm` that is Vector3 min 219 rows, max 219, clamp 448;
Vector4 min 242, max 242; Vector2 clamp 53, and Vector2 min and max had none.
Under `AppleLibm` on Apple clang 21 it is Vector2 min 1, max 1, clamp 53;
Vector3 min 219, max 219, clamp 448; Vector4 min 243, max 243. Signaling NaNs
are outside the
corpus. raymath has no Vector4 component clamp. The functions are pure: a call
consumes its arguments, a reused vector is duplicated by the caller, and there
is no allocation, pointer or effect. The corpus is the safety evidence.

A dependent chain of five million calls, one CPU thread, was timed against the
same loop compiled from the pinned `raymath.h` with `clang -O2
-ffp-contract=off`. The other operand comes from an eight-value cycle, so the
running value keeps changing. Clang emits a packed `minps` or `maxps` plus the
NaN blend. Each sample is the median of three process times after an empty
program. Bend/clang: Vector2 min 2.67, max 2.66, clamp 2.93; Vector3 min 3.56,
max 3.59, clamp 3.95; Vector4 min 2.36, max 2.37. The final bit pattern matched
on every function. This is throughput of the body, not a single call, and not
the JavaScript lane. No performance budget is set. The packed minimum is the
faster code. Removing the NaN test would disagree with `fminf`.
The 2.36x–3.95x slowdown is a candidate for a packed min/max lowering in the Jonlib Bend overlay.

`rotate_for(reference, vector, radians)` uses the explicit trigonometric reference
profile; `rotate` selects the accurate profile. The Apple profile covers finite
radians within one cycle, the glibc profiles every finite angle
([SINCOSF.md](SINCOSF.md)); both preserve reference operation order. See
[ROTATION.md](ROTATION.md) for the corresponding image operation and numerical gates.

## Vector3 API

`Vector3` is immutable `Data` with F32 `x`, `y`, `z` fields.

- Constructors: `zero()`, `one()`.
- Component operations: `add(left, right)`, `subtract(left, right)`,
  `scale(vector, scalar)`, `multiply(left, right)`, `add_value(vector, scalar)`,
  `subtract_value(vector, scalar)`, `negate(vector)`, `divide(left, right)`.
- Products and metrics: `cross_product(left, right)`, `dot_product(left, right)`,
  `distance_sqr(left, right)`, `distance(left, right)`, `length_sqr(vector)`,
  `length(vector)`, `normalize(vector)`, `angle`/`angle_for`.
- Geometric operations: `project`, `reject`, `perpendicular`, `lerp`, `reflect`,
  `invert`, `equals`, `move_towards`, `clamp`/`clamp_for`, `clamp_value`, `refract`.
- Interpolation/frame operations: `barycenter(point, a, b, c)`,
  `cubic_hermite(first, first_tangent, second, second_tangent, amount)`,
  `ortho_normalize(first, second)`, `transform(vector, matrix)`.
- Quaternion rotation: `rotate_by_quaternion(vector, quaternion)` uses the
  direct reference formula without normalizing the supplied quaternion.
- Axis rotation: `rotate_by_axis_angle(vector, axis, angle)` and its `_for`
  variant retain the reference Euler-Rodrigues two-cross-product order, including
  zero axes. Angle/profile selection follows the bounded rotation rules below.
- `unproject(source, projection, view)` retains the two intermediate constructor
  transpositions in the reference's inlined multiplication/inversion path and
  divides the transformed XYZ by W. Its profile requires finite supported inverse,
  homogeneous and result values, with W nonzero. The actual C oracle rejects
  singular/zero-W controls before comparison.
- Extrema: `min`/`min_for` and `max`/`max_for`, with the same explicit signed-zero
  reference profiles as their Vector2 counterparts.

The cross product retains raylib's handedness and XYZ field order. Dot products
and squared distance accumulate in reference left-to-right F32 order. The
fixture serializer checks all three component bits, including the Z component
and signed zero. Full transforms, remaining metrics and other numeric profiles
remain ledger gaps.

Gate `vector3` compares `add`, `add_value`, `subtract`, `subtract_value`,
`scale`, `multiply`, `negate`, `divide`, `invert`, `length`, `length_sqr`,
`distance`, `distance_sqr`, `dot_product`, `cross_product`, `normalize`,
`reflect`, `equals` and `lerp` with contraction off. Inputs are a table, so
the C compiler emits the arithmetic instead of folding literals. Two 3-word
grids cover signed zero, one, a subnormal, positive infinity and one quiet
NaN on every component; the wider edge is swept one component at a time.
`negate`, `invert`, `length`, `length_sqr` and `equals` match every result
bit on CPU-1, CPU-2 and JavaScript, including zero divisors and a zero
length, which retains the input. The other operations match every non-NaN
bit. The sign of a quiet NaN their arithmetic produces is not reproduced.
`min`, `max` and `clamp` are on gate `extrema`. `angle` stays on
atan2.

`Vector3.normalize` preserves a zero-length input, including signed-zero bits;
this differs from `Vector2.normalize`, which returns positive-zero components.
Nonzero vectors multiply by the reciprocal length in reference order.

`project(vector, onto)` and `reject(vector, onto)` require the reference F32
squared length of `onto` to be nonzero. `perpendicular(vector)` crosses against
the axis whose component has the smallest absolute magnitude; strict comparison
ties retain X before Y before Z. `lerp` permits extrapolation, and `reflect`
does not normalize the supplied normal. `divide` and `invert` include zero
divisors; `equals` applies the existing relative epsilon on all three axes.

`move_towards` divides each delta by length before multiplying by the step;
negative steps move away, and zero distance returns the exact target value.
`clamp_for(reference, vector, lower, upper)` shares the explicit signed-zero
profiles used by Vector2; `clamp` selects the accurate profile. `clamp_value`
preserves zero vectors and the lower-before-upper magnitude branch order.
`refract` returns positive zero components for total internal reflection.

`barycenter` requires a nonzero reference F32 denominator; degenerate triangles
are outside this initial profile. `cubic_hermite` retains the reference powers,
coefficient order and extrapolation behavior. `ortho_normalize` returns both
updated vectors as a pair, corresponding to two distinct pointer outputs in C.
Zero and parallel inputs retain the reference arithmetic instead of inventing
a replacement basis. Aliased C pointer behavior remains outside this mapping.

## Vector4 API

`Vector4{x, y, z, w}` is immutable `Data` with four F32 fields. All twenty-two
pinned Vector4 functions have scoped mappings:

- Constructors: `zero()`, `one()`.
- Components: `add`, `add_value`, `subtract`, `subtract_value`, `scale`,
  `multiply`, `negate`, `divide`, `invert`, `min`/`min_for`, `max`/`max_for`.
- Metrics: `length`, `length_sqr`, `dot_product`, `distance`, `distance_sqr`.
- Other operations: `normalize`, `lerp`, `move_towards`, `equals`.

Gate `vector4` compares Vector4 `add`, `add_value`, `subtract`,
`subtract_value`, `scale`, `multiply`, `negate`, `divide`, `invert`, `length`,
`length_sqr`, `dot_product`, `distance`, `distance_sqr`, `normalize`, `equals`
and `lerp`, together with Quaternion `add`, `add_value`, `subtract`,
`subtract_value`, `scale`, Hamilton `multiply`, component `divide`, conjugate
`invert`, `length`, `normalize`, `lerp`, `nlerp` and `equals`, with contraction
off. Inputs are a table, so the C compiler emits the arithmetic instead of
folding literals. Three 2-word grids cover signed zero, one, a subnormal,
positive infinity and one quiet NaN; the wider edge is swept one component at
a time. Vector4 `negate`, `invert`, `normalize`, `length`, `length_sqr` and
`equals`, and Quaternion `length` and `equals`, match every result bit on
CPU-1, CPU-2 and JavaScript, including zero divisors and a zero length.
Vector4 `normalize` returns four positive zeros when the length is not greater
than zero. The other operations match every non-NaN bit. The sign of a quiet
NaN their arithmetic produces is not reproduced. `min` and `max` are on
gate `extrema`. Quaternion slerp and the axis/Euler conversions stay on
their host libm profiles.

All four components are compared bitwise, including W and signed-zero results.
Metric accumulation remains left-to-right. `divide` and `invert` include zero
divisors. Extrema use the same explicit signed-zero profiles as Vector2/Vector3.
`normalize` returns four positive zeros for zero length, unlike Vector3's
retained input zeros. `lerp` permits extrapolation; movement retains negative
steps and division-before-step ordering, and snapping returns the exact target.
`equals` includes W in the relative epsilon comparison. These mappings remain
partial under the contracted-build and target/performance limits below.

A dependent chain of five million calls, one CPU thread, was timed against
the same loop compiled from the pinned `raymath.h` with `clang -O2
-ffp-contract=off`. The Bend program is the pinned native compiler. Each
sample is the median of three process times after subtracting an empty
program. This is throughput of the body, not a single call from a larger
program, and not the JavaScript lane. No performance budget is set.

Bend/clang time, Vector4: `negate` 0.38, `add` 0.74, `add_value` 0.73,
`subtract_value` 0.78, `subtract` 0.79, `length_sqr` 0.79, `distance_sqr`
0.82, `lerp` 0.85, `length` 0.87, `scale` 0.91, `distance` 0.91, `dot_product`
0.93, `invert` 0.97, `multiply` 0.98, `normalize` 1.01, `divide` 1.04.
Quaternion wrappers (`add`, `subtract`, `scale`, `divide`, `add_value`,
`subtract_value`, `length`, `lerp`) landed on the same ratios. Hamilton
`multiply` was 0.59, `lerp` 0.92, `nlerp` 0.96, `normalize` 0.99 and conjugate
`invert` 1.00. `divide` is the only ratio above 1, by about four percent,
inside the spread of these short runs. `equals` on both sides was deleted:
the two inputs did not change, so that row is not a throughput result.

The functions are pure. A call consumes its arguments; a reused vector is
duplicated by the caller. There is no allocation, pointer, or effect. The
exceptional corpus is the safety evidence: zero divisors, infinities and one
quiet NaN are defined and match raylib, except the quiet-NaN signs already
recorded. Adding a NaN rejection would diverge from upstream. No library
rewrite is indicated. Bend already emits a packed add for a live `Vector4`
add, which is why that chain is faster than clang's `addps` loop here.

## Matrix API

`Matrix` is immutable `Data`. Constructor fields match the reference declaration:

```text
Matrix{m0, m4, m8,  m12,
       m1, m5, m9,  m13,
       m2, m6, m10, m14,
       m3, m7, m11, m15}
```

The numeric field indices follow raylib's column-major naming; constructor
arguments follow its row-wise declaration order. `Matrix.identity()` returns
the 4×4 identity. `Matrix.transpose(matrix)` permutes fields exactly, including
signed-zero bits. `LAWS.bend`/`PROOF.bend` establish that transposing twice returns
the original Matrix; conformance separately checks the actual reference layout.

- `Matrix.add(left, right)` and `subtract(left, right)` operate component-wise.
  Gate `matrix-arith` compares them, `multiply`, `multiply_value` and `trace`
  on subnormals, infinities and quiet-NaN payloads with contraction off. One
  NaN operand keeps that payload on CPU-1 and CPU-2. An invalid operation's
  quiet NaN matches by NaN-ness. JavaScript stores every NaN as the canonical
  positive quiet NaN.
- `Matrix.multiply(left, right)` retains raylib's operand convention and exact
  four-term accumulation order. In ordinary column-vector notation its numeric
  result is `right × left`; do not reverse arguments based on another library's
  multiplication convention.
- `Matrix.trace(matrix)` sums the diagonal in reference order.
- `Matrix.determinant(matrix)` uses the pinned Laplace expansion, including
  singular matrices whose result is zero.
- `Matrix.invert(matrix)` uses the reference minor expansion and reciprocal
  denominator. Its initial profile requires a nonzero inversion denominator and
  finite supported intermediate/result values. Singular inverse results remain
  outside this profile. The public determinant and inversion denominator have
  different arithmetic orders and are not substituted for one another.
- `Matrix.translate(x, y, z)` and `scale(x, y, z)` store the supplied components
  as bits, including signed zero, subnormals, infinities and NaN payloads.
  JavaScript stores every NaN as the canonical positive quiet NaN.
- `Matrix.multiply_value(matrix, scalar)` multiplies every field independently.
- `Matrix.look_at(eye, target, up)` retains the reference basis normalization and
  negative-dot translation. Coincident eye/target and parallel up vectors keep
  their reference degenerate results instead of substituting a camera basis.
- `Matrix.compose(translation, rotation, scale)` scales each basis vector before
  applying `Vector3.rotate_by_quaternion`, then inserts translation. Replacing
  this sequence with a differently ordered matrix product can change reference
  rounding, signed zeros and non-unit quaternion behavior.
- `Matrix.decompose(matrix) -> Matrix.Decomposition` returns
  `Decomposed{translation: Vector3, rotation: Vector4, scale: Vector3}`. All ten
  fields correspond to distinct C pointer outputs. The algorithm preserves the
  reference grouping of matrix rows, max-stabilization, 1e-9 guards, shear removal
  and all-axis sign changes for reflected bases. Degenerate results are retained:
  a zero matrix produces zero scale and a quaternion W of 0.5.

### Rotation constructors

`Matrix.rotate_x/y/z(angle)`, `rotate_xyz/zyx(angles)` and `rotate(axis, angle)`
use radians. Each has a corresponding `_for(reference, ...)` entry point taking
the existing `Libm`; convenience calls select `AppleLibm{}`.
Under `AppleLibm` every angle component is bounded to absolute value ≤ 6.283186,
the one-cycle F32 rotation profile; under the glibc profiles every finite
angle uses glibc's own `sinf`/`cosf` ([SINCOSF.md](SINCOSF.md)).

XYZ and ZYX retain their distinct pinned formulas, signs and F32 accumulation
orders; they are not replaced by products of simpler rotation matrices. The
axis-angle operation skips normalization when squared axis length is zero or
exactly one. A zero axis therefore preserves raylib's cosine-diagonal result,
which is not generally an identity matrix. Fixture validation bounds the angle,
not the axis components. The exact oracle includes signed zeros, neighboring
F32 values around π/4, quadrant/full-cycle angles, non-unit and zero axes.

`Vector2.transform` and `Vector3.transform` apply the reference matrix expressions
without perspective division. The Vector2 version retains the multiplication
and addition of the zero-Z term; dropping it could change signed-zero behavior.
All 16 matrix fields and all transformed vector components are checked bitwise.

### Binary64 projection inputs

`Float64{high, low}` stores the high and low U32 words of an IEEE binary64 value.
`Float64.from_f32(value)` promotes an F32 value without decimal re-parsing;
finite normal/subnormal inputs and signed zeros have native bit-level evidence.
Promotion starts with the supplied F32 value: it cannot restore precision already
lost before the call. For a full-precision binary64 constant, use its two words;
for example, `Float64{1069128089, 2576980378}` encodes the C double value `0.1`.

`Matrix.frustum(left, right, bottom, top, near, far)` and `Matrix.ortho(...)`
take six `Float64` values. They preserve binary64 interval subtraction before
the exact reference F32 casts and subsequent arithmetic. Bounds such as
16777216 and 16777217 therefore retain a nonzero span despite sharing the same
rounded F32 value.

The initial projection profile requires finite normal/zero binary64 inputs,
normal/zero relevant F32 casts/intermediates/results and nonzero spans. The
fixture validator and actual C result gate enforce this scope. Exceptional and
subnormal projection arithmetic, and unverified non-finite promotion payloads,
remain gaps. The public carrier API provides storage and promotion; arithmetic
helpers are internal and reuse finite-normal integer-limb operations.

`Matrix.perspective_for(libm, fovy, aspect, near, far) -> Maybe<Matrix>`
(`MatrixPerspective`, binary64 `M.Float64` inputs) computes `top =
near*tan(fovY*0.5)` and `right = top*aspect` in binary64 with
`M.Libm.tan(libm, x)`, then `Matrix.frustum`'s cells. The native tangent
rounding survives into the F32 fields and neither macOS nor glibc `tan` is
correctly rounded, so `M.Libm.tan` reproduces glibc's x86_64 function exactly
for the glibc profiles (an LGPL-2.1+ module) and is `None` for `AppleLibm`;
see [PERSPECTIVE.md](PERSPECTIVE.md).

## Quaternion API

Quaternion values use `Vector4{x, y, z, w}`, mirroring raylib's `Quaternion`
typedef alias. `Quaternion.identity()` returns `(0,0,0,1)`.
`Quaternion.add(left, right)` and `subtract(left, right)` operate component-wise.
`Quaternion.multiply(left, right)` applies the reference Hamilton product in
its original uncontracted F32 order; operands are not implicitly normalized.
Multiplication is noncommutative and differs from `Vector4.multiply`.

Additional operations are `add_value`, `subtract_value`, `length`, `normalize`,
`invert`, `scale`, `divide`, `lerp`, `nlerp` and `equals`. Division remains
component-wise, including zero divisors in the vector4 corpus; inversion
instead uses conjugation and reciprocal squared length, with the original
quaternion returned at zero length. Both normalization and inversion retain
zero quaternion signs, unlike Vector4's positive-zero normalization result.
Gate `vector4` runs these operations on the same exceptional table. `length`
and `equals` match every result bit on CPU-1, CPU-2 and JavaScript. Hamilton
multiplication, component division, conjugate inversion, normalization, `lerp`
and `nlerp` match every non-NaN bit. Slerp and the axis/Euler conversions stay
on their host libm profiles. The same chain timing as Vector4 is recorded
above.

`nlerp` performs component interpolation followed by quaternion normalization.
It does not choose a common hemisphere: exactly opposite quaternions can collapse
to zero at the midpoint, as in the reference. `equals` accepts approximate `q`
or `-q` equivalence using all four components and the reference relative epsilon.

`from_vector3_to_vector3(first, second)` retains the reference cross/dot formula
and normalization, including zero output for exactly opposite directions.
`from_axis_angle(axis, angle)` returns identity for a zero axis; other axes use
the original half-angle construction and quaternion normalization.
`from_euler(pitch, yaw, roll)` preserves the reference ZYX half-angle formulas.
Both angle constructors have `_for(reference, ...)` variants; convenience calls
select `AppleLibm{}`, with each input angle bounded to absolute value
≤ 6.283186. `cubic_hermite_spline(first, first_tangent, second, second_tangent,
amount)` uses the reference four weights and then normalizes the result, retaining
zero collapse without a replacement orientation.

`Quaternion.from_matrix(matrix)` selects the largest quaternion component using
strict comparisons in W/X/Y/Z order and applies the reference off-diagonal
formulas. `Quaternion.to_matrix(quaternion)` retains the direct coefficient
formula, including its non-unit and zero-input results, and returns a complete
16-field Matrix. `Quaternion.transform(quaternion, matrix)` is a four-dimensional
linear transform: it uses the supplied W and the final matrix row without
perspective division or normalization.

These operations are intentionally distinct from `Vector3.rotate_by_quaternion`.
For example, a zero quaternion yields an identity in `to_matrix`, but zeroes the
basis used by `Matrix.compose`. Both results follow their respective reference
implementations; no implicit normalization makes them interchangeable.
The remaining quaternion operations and full integration/ABI/target/performance
coverage remain ledger gaps.
`M.Float64.to_f32(value)` is C's `(float)` of a binary64 value (round to
nearest even, gradual underflow, overflow to infinity; `None` for infinities
and NaN), for example `(float)GetTime()`. `M.Float64.to_int(value)` is `(int)`
(truncation toward zero as a two's-complement word; `None` at or beyond 2^31
in magnitude, where C's conversion is undefined, and for infinities and NaN).
`M.Libm.pow2(libm, y)` is `powf(2, y)` (and the `exp2f(y)` compilers
substitute for it) under both glibc profiles for every finite `y` below 126
in magnitude, where the result is normal (exactly `2^y` for an integral
`y`). Under `AppleLibm`, `Some` for the exponents measured in
`src/apple_exp2.bend` (the XM gates' linear frequencies; clang's `exp2f`,
which agreed with `powf` on each) and `None` for every other `y` (gate `pow2`,
[Powers of two](#powers-of-two)).
`M.Libm.exp(libm, x)` and `M.Libm.log(libm, x)` are `expf` and `logf` under
both glibc profiles: `expf` for a finite `x` below 87 in magnitude except two
arguments, `logf` for a positive finite `x` (subnormals included); `None` for `AppleLibm` and
everything else (gate `explog`, [Exponential and logarithm](#exponential-and-logarithm)).
`M.Libm.acos(libm, x)` and `M.Libm.pow(libm, x, exponent)` expose the glibc
2.39 `acosf` and `powf` (exponents 2 and 3 on [-0, 1]) kernels as `Maybe`
results; other profiles give `None` ([INVERSE-TRIG.md](INVERSE-TRIG.md),
[SPLINES.md](SPLINES.md)). `M.Libm.asin(libm, x)` is the correctly rounded
`asinf` of glibc 2.41 (CORE-MATH): on [-1, 1] for `Glibc241Libm{}`, and below
0x1.d12edp-12 (`AppleLibm{}`) and 0x1.d12e9ep-12 (`Glibc239Libm{}`), where those
native `asinf` were exhaustively found correctly rounded.
`Quaternion.slerp_for(libm, ...)` and `Quaternion.to_axis_angle_for(libm, ...)`
return `Maybe` results under the `Glibc239Libm{}` acosf profile;
`Quaternion.to_euler_for(libm, q)` (`QuaternionToEuler`) returns
`Maybe<Vector3>` with the profile's `atan2f` and `Libm.asin`. See
[INVERSE-TRIG.md](INVERSE-TRIG.md).

## Float-list exports

`Vector3.to_float_v(vector) -> +List<F32>` returns exactly `[x, y, z]`.
`Matrix.to_float_v(matrix) -> +List<F32>` returns exactly `[m0, m1, ..., m15]`.
The matrix export order differs from its row-wise constructor order.

These immutable lists adapt raymath's `float3` and `float16` return carriers.
The export lengths have structural laws checked in `PROOF.bend`; runtime
conformance verifies list length, order and every F32 bit. Native contiguous-array
ABI and mutability correspondence remain gaps, and the general list type itself
does not enforce a fixed length for arbitrary caller-created lists.

## Vector angle profiles

Angle profiles, the checked entry points and host profile selection are
specified in [ANGLES.md](ANGLES.md). In summary:

- `Vector2.angle_for`, `Vector2.line_angle_for` and
  `Vector3.angle_for` take an `M.Libm`
  (`AppleLibm{}`, `Glibc239Libm{}` or `Glibc241Libm{}`) and return
  `Maybe<F32>`; they reject nonfinite components and nonzero subnormal
  intermediates or results.
- The convenience `Vector2.angle(left, right)` (reference signed cross/dot
  angle), `Vector2.line_angle(start, end)` (negated endpoint-difference angle)
  and `Vector3.angle(left, right)` (cross-product length and dot product) keep
  their unchecked `F32` contract with the Apple algorithm, which rounds π toward
  zero near the negative X axis. The Sun float algorithm (`Glibc239Libm`), with
  its own polynomial and quadrant corrections, is reached through the checked
  `_for` forms.

Both legacy algorithms are evaluated in Bend (an independent polynomial
evaluation and a licensed Sun-kernel adaptation, see
[LICENSES/sun-math.txt](../LICENSES/sun-math.txt)) rather than with
backend-native `atan2`, with supporting binary64 multiplication/division rounded
directly from integer limbs (`src/float64_ops.bend`). Their references disable
builtin `atan2f` folding and call native libm through a volatile pointer, so
actual library behaviour is compared rather than compiler-folded literals.

| Gate | Probe | Compares |
|---|---|---|
| `float64-ops` | `tools/float64_ops_probe.py` | internal normal binary64 multiply/divide vs native C bits |
| `angle-legacy` | `tools/angle_probe.py --gnu-control` | legacy GNU angle vs the independent Sun C control |
| `angle-kernels` | `tools/angle_kernel_probe.py` | angle kernels and checked wrappers (see [ANGLES.md](ANGLES.md)) |
| `operators` | `tools/operators_probe.py` | raymath's C++ operators, compiled as C++, vs Jonmath's operator sugar and named functions |

`tools/angle_probe.py` without `--gnu-control` compares the host-declared legacy
profile with the host's native `atan2f`.

## C++ operators

raymath's optional C++ operators map to Bend by operand type. Bend's typed
operators call `T.add`, `T.sub`, `T.mul` and `T.div`, so Jonmath defines
`sub`, `mul` and `div` next to the existing `add` for `Vector2`, `Vector3`,
`Vector4` (component-wise, as `Vector*Subtract/Multiply/Divide`) and `sub`
and `mul` for `Matrix` (`MatrixSubtract`, `MatrixMultiply`):

| C++ | Bend |
|---|---|
| `a + b`, `a - b`, `a * b`, `a / b` (same vector type) | `(a + b : M.Vector3)`, `(a - b : M.Vector3)`, ... |
| `m + n`, `m - n`, `m * n` | `(m + n : M.Matrix)`, `(m - n : M.Matrix)`, `(m * n : M.Matrix)` |
| `v * s`, `s * v`, `v / s` | `M.Vector3.scale(v, s)`, `M.Vector3.scale(v, (1.0 / s : F32))` |
| `v * m` (Vector2/Vector3), `q * m` | `M.Vector3.transform(v, m)`, `M.Quaternion.transform(q, m)` |
| `q + s`, `q - s` | `M.Quaternion.add_value(q, s)`, `M.Quaternion.subtract_value(q, s)` |
| `m * s` | `M.Matrix.multiply_value(m, s)` |
| `a == b`, `a != b` | `M.Vector3.equals(a, b)`, `Bool.not(M.Vector3.equals(a, b))` |

A compound assignment (`a += b`) returns its updated left operand; Bend values
are immutable, so it is the same expression bound to a new name. raylib 6.2's
`float * vector` (Vector2, Vector3 and Vector4) calls `Vector*Scale(vector, scalar)`,
the same function as `vector * scalar`, and has no compound form. The
`operators` gate compiles the pinned raymath.h as C++ with contraction off and
compares every operator and compound assignment bit for bit, including zero
divisors and nearly equal pairs.

## Floating-point contract and evidence

The initial profile is **uncontracted F32**, matching the primitive arithmetic
contract of the pinned Bend compiler. The independent C reference includes the
unmodified pinned `raymath.h` with `FP_CONTRACT OFF`. This choice is explicit:
fused multiply-add/contracted build variants are separate, unverified contracts.

The `conformance` gate (`tools/conformance.py` over `tests/fixtures/images.json`)
compares exact returned F32 bit patterns and Boolean values with the linked
pinned raylib on CPU-1, CPU-2 and JavaScript.
Vector-returning operations write every component to adjacent verification cells;
the validator requires all cells to fit. Signed zero is retained in generated
Bend literals. There is no tolerance added to make mismatches pass.

The conformance gate uses finite inputs, nonzero normalized ranges, and nonzero
component divisors. Gate `scalars` is the exceptional/subnormal corpus for the
six scalar functions; the same domain for the remaining raymath functions,
contracted builds and the full target/performance matrix remain open. These
are partial mappings, not completed raymath APIs. See the
[progress dashboard](PROGRESS.md) and [VERIFICATION.md](VERIFICATION.md).

## Powers of two

`src/power.bend`'s `exp2` is the `exp2_inline` of glibc's `powf` (Arm
optimized-routines, MIT alternative, [LICENSES/arm-math.txt](../LICENSES/arm-math.txt))
on `y` itself: `log2_inline(2.0f)` is exactly 1, so `powf`'s `y*log2(x)` is
`y`, and `exp2f`'s core is the same table and cubic. The domain is a finite
`y` with `|y| < 126`: the result is normal and no overflow, underflow or
special case of either function is reached.

`tools/reference/glibc_pow2/model.c` is the explicit-operation C model
(`FUSED=1` for the `-mfma -mavx2` ifunc variants, where the polynomial's three
`a*b + c` are one `fma` each; `FUSED=0` for the SSE2 default), and
`exhaustive.c` evaluates it on every binary32 `y` of the domain against the
host's `powf(2.0f, y)` and `exp2f(y)`, each called through a volatile
pointer. `run_exhaustive.sh` runs both variants (the SSE2 one with
`GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4`):

| Host | Variant | Arguments | powf | exp2f | Result |
|---|---|---:|---:|---:|---|
| Ubuntu 24.04, glibc 2.39-0ubuntu8.9 | FMA | 2,247,622,656 | 0 | 0 | identical |
| Ubuntu 24.04, glibc 2.39-0ubuntu8.9 | SSE2 | 2,247,622,656 | 0 | 0 | identical |
| Debian trixie container, glibc 2.41-12+deb13u4 | FMA | 2,247,622,656 | 0 | 0 | identical |
| Debian trixie container, glibc 2.41-12+deb13u4 | SSE2 | 2,247,622,656 | 0 | 0 | identical |

`variants.c` compares the two models with each other on the same arguments:
no difference, so the kernel uses the unfused arithmetic for both (every
operation through the checked binary64 helpers, whose domain no intermediate
of the SSE2 model leaves; the fused model's `z*r2 + q` would leave the fused
helper's exponent window for subnormal `y`). The JSON results are in
`tools/reference/glibc_pow2/results`. Gate `pow2` (`tools/pow2_probe.py`)
evaluates the same arithmetic in Python's binary64 for 280 arguments, checks
the host's two functions against it on glibc hosts and Jonmath's result on
every lane. `AppleLibm` is not that kernel. It answers the 25,980 exponents
`src/apple_exp2.bend` records, measured on macOS arm64 against `exp2f`
(the call clang substitutes for `powf(2, y)`; `powf` agreed on every one).
179 of them differ from this model by one ulp. Every other argument is
`None`. On macOS the `pow2` gate checks the recorded words against the host.

## powf

`M.Libm.powf(libm, x, y)` is glibc 2.39's x86_64 `powf(x, y)` under
`Glibc239Libm` (`src/power.bend`'s `powf`: Arm optimized-routines
`math/powf.c`, MIT alternative,
[LICENSES/arm-math.txt](../LICENSES/arm-math.txt)): `log2_inline(x)`, the
product `y*log2(x)` in binary64, and `exp2_inline` of it. `M.Libm.pow`
(exponents 2 and 3 on [-0, 1]) and `M.Libm.pow2` are older, narrower uses
of the same kernel and stay as they are.

The domain: `x` is +0 or positive and finite (a subnormal `x` is normalized
as `powf` does), `y` finite and not subnormal. +0 to a positive power is
+0; anything that is not a NaN to a zero power is 1; a result that
underflows is +0 or a subnormal, as glibc returns it. `None`: a negative
`x` and -0, an infinite `x`, NaNs, an infinite or subnormal `y`, +0 to a
negative power (a division by zero), a result that overflows or is within a
64th of a binade of 2^128 (from `y*log2(x)` = 127.984375 up `exp2_inline`'s
scale is 2^128, which the exact binary64 helpers do not take), and a
binary64 step outside those helpers' domain.

**Two builds.** glibc selects `powf` at load time: an FMA build
(`-mfma -mavx2`) on hosts that have FMA, the SSE2 one elsewhere. Read from
the library's code: in the FMA build each `a*b + c` of the two polynomials
is one `fma`, and so is `z*invc - 1` (six in `log2_inline`, three in
`exp2_inline`); `y*log2(x)`, the add of the shift and the remainder are a
product, a sum and a difference in both. `powf` computes both and answers
where they give the same float, so the answer does not depend on the
host's processor; where they would differ it is `None`.

`tools/reference/glibc_powf/model.c` is the explicit-operation C model of
the whole function (`FUSED=1` and `FUSED=0`), with the tables and
polynomials as the words of the library. `powf` has two arguments, so it
is compared on seeded samples instead of every argument: `sample.c`
against the host's `powf` through a volatile pointer, the SSE2 model with
`GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4`, and `variants.c` the
two models against each other. Three ways of drawing a pair: any two
words (every special case); `x` in [0, 2) with one of the exponents
raylib's `audio_mixed_processor` reaches; a positive finite `x` with `y`
within 8 of 0. `run_sample.sh` on Ubuntu 24.04, glibc 2.39-0ubuntu8.9,
ten billion pairs each:

| Pairs drawn | FMA model and host | SSE2 model and host | The two models |
|---|---:|---:|---:|
| any two words | 0 differences | 0 | 0 |
| `x` in [0, 2), the example's exponents | 0 | 0 | 7 |
| positive `x`, `y` within 8 of 0 | 0 | 0 | 4 |

Each model is its build, on every pair. The two builds are not each
other: about 7 pairs in ten billion get floats one unit in the last place
apart (none among any two words, most of which are special cases). For
those `powf` is `None`: `powf(2.7785363e-05f, 0.9500001f)` is 0x3844EAED
in the FMA build and 0x3844EAEC in the SSE2 one. The JSON results are in
`tools/reference/glibc_powf/results`.
Gate `powf` (`tools/powf_probe.py`) computes both builds in Python's
binary64, a fused sum rounded once from the exact rational value, for 540
pairs (special values, underflows to 0 and to subnormals, overflows, the
top of the range, the 112 exponents the example's keys reach with bases
from its samples' range, six of the pairs on which the builds differ, and
a seeded sample); on a glibc 2.39 host the host's `powf` must give the
same word for each of the 416 answered, and Jonmath's result must on every
lane. glibc 2.41's and macOS's `powf` are
not modeled: `Glibc241Libm` and `AppleLibm` are `None`.

## Exponential and logarithm

`src/power.bend`'s `exp` and `log` are glibc's `expf` and `logf` (Arm
optimized-routines `math/expf.c`, `math/logf.c`, MIT alternative,
[LICENSES/arm-math.txt](../LICENSES/arm-math.txt)). The domains leave every
special case out: a finite `x` with `|x| < 87` for `expf` (a normal result),
a positive finite `x` for `logf`. A subnormal `x` is first scaled by 2^23
with 23 taken from its exponent, as `logf.c` does (`Power.normalize`, which
`powf` shares), and then goes the normal way.

`tools/reference/glibc_explog/model.c` is the explicit-operation C model of
both (`FUSED=1` for the `-mfma -mavx2` ifunc variants, `FUSED=0` for the
SSE2 default) and `exhaustive.c` evaluates it on every binary32 argument of
the two domains against the host's functions:

| Host | Variant | expf arguments | expf | logf arguments | logf |
|---|---|---:|---:|---:|---:|
| Ubuntu 24.04, glibc 2.39-0ubuntu8.9 | FMA | 2,237,399,040 | 0 | 2,130,706,432 | 0 |
| Ubuntu 24.04, glibc 2.39-0ubuntu8.9 | SSE2 | 2,237,399,040 | 0 | 2,130,706,432 | 0 |
| Debian trixie container, glibc 2.41-12+deb13u4 | FMA | 2,237,399,040 | 0 | 2,130,706,432 | 0 |
| Debian trixie container, glibc 2.41-12+deb13u4 | SSE2 | 2,237,399,040 | 0 | 2,130,706,432 | 0 |

The 8,388,607 positive subnormal arguments of `logf` were checked apart
(2026-10-13, the same files): no difference from any of the four hosts, no
intermediate outside the binary64 helpers' domain, and the two models
agree on all of them. `audio_spectrum_visualizer` needs them: it takes
`logf(fmaxf(magnitude, 1e-40f))`, and `1e-40f` is subnormal.

In the FMA variant of `expf` the compiler contracts `r = z - kd` over
`z = InvLn2N*x` into `fma(InvLn2N, x, -kd)`; without that the model differs
from an FMA host at two arguments. `variants.c` compares the two models with
each other: `logf` never differs, `expf` differs at exactly those two,
32.564632 (`0x4202422f`) and -63.099461 (`0xc27c65d9`), by one unit in the
last place. The kernel therefore uses the unfused arithmetic (through the
checked binary64 helpers, whose domain no intermediate of the SSE2 model
leaves) and refuses those two arguments, whose answer depends on the CPU.
The JSON results are in `tools/reference/glibc_explog/results`. Gate `explog`
(`tools/explog_probe.py`) evaluates the same arithmetic in Python's binary64
for 279 arguments (39 of them subnormal), checks the host's functions against it on glibc hosts and
Jonmath's results on every lane. macOS's functions are not modeled:
`AppleLibm` is `None`.

## Distance comparisons through hypot

`M.Libm.hypot_within(x, y, radius)` answers the C comparison
`hypot(x, y) <= radius` for three binary32 values promoted to binary64 (the
press test of `shapes_ball_physics`). It reproduces no particular `hypot`:
the C library's `hypot` differs between versions and CPU variants, and its
two binary64 arguments cannot be enumerated. The answer is the one every
*faithful* `hypot` gives, a result that is one of the two doubles around the
exact value (an error below one unit in the last place), on any profile.
glibc 2.39's `sysdeps/ieee754/dbl-64/e_hypot.c` states an expected error of
about 0.792 ULP, or 0.948 ULP in its FMA variant, so it is faithful and its
variants need not agree; its test tolerance (`libm-test-ulps`) is 1 ULP.

| Exact `x*x + y*y` | Answer |
|---|---|
| at most `radius*radius` | `Some{True}`: the root is at most `radius`, so both doubles around it are |
| at least `R*R`, `R` the double after `radius` | `Some{False}`: both are above `radius` |
| between them | `None`: two faithful results could disagree |

The squares of binary32 values are exact in binary64. `src/hypot.bend` rounds
their sum once: a rounded sum below or above `radius*radius` has the exact
sum on the same side (rounding is monotonic and `radius*radius` is a double),
and for an equal one the sum's rounding error (Dekker's exact
`b - (s - a)`) gives the side. `Some{False}` needs the rounded sum to reach
`radius*radius*(1 + 2^-50)`, which puts the exact sum past `R*R`; the refused
band is therefore a little wider than the contract's (about `2^-50` of
`radius*radius` instead of `2^-51`). A negative `radius` is below every
finite distance. `None` also for a NaN, an infinity and a magnitude from
`2^64` on (the checked binary64 helpers' range).

Gate `hypot` (`tools/hypot_probe.py`) holds the contract in rational
arithmetic (`exact`) and the kernel's one-rounding arithmetic (`kernel`). On
207 cases (Pythagorean triples and their binary32 neighbours, sums that round
onto `radius*radius` from either side, the band, zeros and signs, refused
magnitudes and non-finite values, points around circles of the examples'
radii) the candidate equals `kernel` on CPU-1, CPU-2 and JavaScript, `kernel`
never contradicts `exact`, and the host's `hypot(x, y) <= radius` agrees
wherever the kernel answers. The same native program agrees under glibc
2.39-0ubuntu8.9 and glibc 2.41 (Debian trixie container), in both the FMA
and the SSE2 (`GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4`) variants;
inside the refused band those hosts answer both ways.

## Decimal numbers (strtod)

`M.Float64.from_decimal(bytes)` is the binary64 value the C library's `strtod`
and `atof` give a decimal number in JSON's grammar
(`-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`), and
`M.Float64.to_f32` of it is `(float)strtod(...)`. That is how cgltf reads the
numbers of a glTF file (node transforms, material factors), which the glTF
loader needs bit for bit.

`strtod` is correctly rounded (to nearest, ties to even), so no libm profile
is involved: `src/strtod.bend` decides the value by exact integer arithmetic.
The digits `D` and the decimal exponent `e` give `N/M = D*10^e`; `N` or `M`
is scaled by a power of two so that `Q = floor(N/M)` has 54 or 55 bits; `Q`
comes from 55 steps of binary long division on lists of 16-bit limbs; its low
one or two bits and the remainder round the top 53.

`None` outside the domain: a text that is not of that grammar (a leading
plus or zero, a bare point, spaces, hexadecimal, `inf`, `nan`), more than 19
significant digits (`D` below 2^64), a decimal exponent beyond 60 in
magnitude once the fraction digits are counted, or an exponent field of more
than three digits. Inside it every result is a normal double or a signed
zero.

Gate `strtod` (`tools/strtod_probe.py`) takes the expected words from
Python's `float()`, which is correctly rounded as well, and requires the
host's `strtod` and `atof` to give the same words: 322 answered cases
(integers, the numbers of the glTF models the examples load, powers of ten,
decimals exactly halfway between two doubles and their neighbours, 17-digit
round-trip forms, 19-digit numbers, values whose narrowing overflows or is
subnormal) and 33 refused ones, on CPU-1, CPU-2 and JavaScript.


## tanf

`M.Libm.tanf(libm, x)` is glibc 2.39's `tanf` under `M.Glibc239Libm` for
every finite `x` (`src/lgpl/tanf.bend`, an LGPL module): the Sun kernel
`k_tanf.c` in binary32 arithmetic, one rounding per operation, on the
argument `s_tanf.c` reduces with `s_sincosf.h`'s `reduce_fast` and
`reduce_large` (the reduction of `sinf`/`cosf`, here without the fused step)
and splits into two binary32 parts. glibc 2.39 has one scalar `tanf` on
x86_64, compiled without FMA.

`tools/reference/glibc_tanf/model.c` is that arithmetic in C, and
`exhaustive.c` compares it with the host's `tanf` on every binary32 argument:

| Host | Variant | Arguments | Differences |
|---|---|---:|---:|
| Ubuntu 24.04, glibc 2.39-0ubuntu8.9 | default | 4,294,967,296 | 0 |
| Ubuntu 24.04, glibc 2.39-0ubuntu8.9 | FMA and AVX2 disabled | 4,294,967,296 | 0 |
| Debian trixie container, glibc 2.41 | default | 4,294,967,296 | 83,411,250 |

glibc 2.41 replaced `tanf` with a correctly rounded implementation, so
`M.Glibc241Libm` answers `None`, as `M.AppleLibm` does (macOS's function is
not modeled); infinities and NaN are `None` on every profile. The JSON
results are in `tools/reference/glibc_tanf/results`. Gate `tanf`
(`tools/tanf_probe.py`) compiles the model on the host for 741 arguments
(every exponent and both signs, the edges of the kernel's regions, the angles
`shapes_math_sine_cosine` passes), requires the host's `tanf` to equal it on
glibc 2.39 and Jonmath's results to equal it on CPU-1, CPU-2 and JavaScript.


## Binary64 sin and cos

`M.Libm.sin64(libm, x: M.Float64)` and `M.Libm.cos64` are the C `sin` and
`cos` of a `double` (`M.Libm.sin` and `M.Libm.cos` are `sinf` and `cosf`):
what an example gets from `sin(GetTime())` or from `cos` of a `float`
expression. Under `M.Glibc239Libm` they are glibc 2.39's x86_64 functions as
their FMA ifunc variants run them on CPUs with FMA and AVX2 (the CI runners
and current desktop CPUs), through the LGPL module `src/lgpl/sin.bend` with
its table `src/lgpl/sin_table.bend`. The functions are not correctly rounded
(about 0.55 ulp), and glibc builds `s_sin.c` four times (`-mfma -mavx2`,
`-mfma4`, AVX and SSE2), so the kernel reproduces the selected variant
operation by operation instead of computing an accurate sine:

- below 2^-26 (2^-27 for `cos`) the argument itself (1 for `cos`);
- below 0.126 a Taylor polynomial; below 0.855469 the table of `sin` and
  `cos` at multiples of 1/128 with two short polynomials of the remainder;
- below 2.426265 the other function of `pi/2 - |x|`;
- below 105414350 a reduction by `pi/2` in three parts (136 bits), and
  above it `__branred` (the reduction of the tangent, which glibc builds
  once, without FMA); the quadrant selects the function and the sign.

Every `a*b + c` the FMA build contracts is one fused operation, in the
positions read from the Ubuntu 24.04 library (`libm.so.6`, build ID
`d53fcbff9f855463606b25cfbe2a2e10856ea3a7`). `tools/reference/glibc_sin/model.c`
is that arithmetic in C (`FUSED=1`; `FUSED=0` is the source without
contraction), compiled with contraction off around the pinned `sincostab.c`
and `branred.c`:

| Host | Arguments (each function) | Differences from the host's `sin`/`cos` |
|---|---:|---:|
| Ubuntu 24.04, glibc 2.39-0ubuntu8.9, FMA and AVX2 | 16,000,000 random words, two million in each of eight exponent ranges from subnormal to the largest | 0 (`FUSED=1`); about 0.07% differ with `FUSED=0` |

Unmodified glibc 2.39 files in `tools/reference/glibc239`, identical to
release commit `ef321e23c20eebc6d6fb4044425c00e6df27b05f`
(`sysdeps/ieee754/dbl-64/`):

| File | SHA-256 |
|---|---|
| `s_sin.c` | `d607bcb0823bb793ecf917546266559aa6f3da6504719ecb90db8b6cb4bb8b1b` |
| `sincostab.c` | `3233d23c6085ac87d47ce1fd7471d88533213f6271ba333e664df30f3172ab85` |
| `usncs.h` | `c1c081b3f99d023f5f4093e72e81c5eabe6fa3cc7389e37f9709d6c138eaef4a` |

`M.Glibc241Libm` answers `None`: glibc 2.41 ships the same `s_sin.c` (the
copyright year differs), but where its build contracts has not been read from
a 2.41 library. `M.AppleLibm` answers `None` (macOS's functions are not
modeled), and infinities and NaN are `None` on every profile. Out of
contract: errno, exception flags and rounding modes other than to nearest.

Gate `glibc-sin` (`tools/glibc_sin_probe.py`, with `tools/glibc_sin.py`)
compiles the model on the host, requires it to reproduce 33 recorded results
where the FMA and SSE2 variants differ, compares it with the host's `sin` and
`cos` where those reproduce them too, and requires Jonmath to equal it on
6356 arguments: random words of every exponent, promoted binary32 values,
every region boundary and table row with its neighbours, multiples of `pi/2`
and theirs, signed zeros, subnormals and the largest values, on CPU-1, CPU-2
and JavaScript.

An example forms a `double` expression around these functions
(`(int)(400.0f + cos(t)*363.0f - 32)`): `M.Float64.from_f32` promotes,
`M.Float64.internal.add`, `subtract`, `multiply` and `divide` are the
operators (one rounding each through the exact helper; `None` for a
nonfinite or subnormal operand or result and a zero divisor) and
`M.Float64.to_int` or `to_f32` converts back. The same gate compares the
four operators with C's on 1206 pairs of its arguments.

## Binary64 acos

`M.Libm.acos64(libm, x: M.Float64)` is the C `acos` of a `double`
(`M.Libm.acos` is `acosf`): what stb_truetype's cubic solver calls for a
signed distance field. Under `M.Glibc239Libm` it is glibc 2.39's x86_64
function as its FMA ifunc variant runs it on CPUs with FMA and AVX2,
through the LGPL module `src/lgpl/acos.bend` with its tables
`src/lgpl/acos_table.bend`. The function is not correctly rounded (about
0.52 ulp) and glibc builds `e_asin.c` once a variant, so the kernel
reproduces the selected variant operation by operation:

- below 2^-55 (2.77556e-17) `pi/2`'s high part;
- below 1/8 `pi/2 - x` in two parts with a polynomial of `x*x`;
- below 0.96875 one of 216 entries of a table (32 from 1/8, 64 from 1/4, 64
  from 1/2, 44 from 3/4, 8 from 0.921875 and 4 from 0.953125): a polynomial
  of 5 to 9 coefficients in the distance to the entry's argument, and the
  entry's angle taken from or added to `pi/2`;
- below 1 a square root of `z = (1 - |x|)/2` made by hand (a table of 128
  reciprocal roots, a power of two, a polynomial correction and a split in
  two parts) with a polynomial of `z`, doubled;
- 1 and -1 are 0 and `2*(pi/2)`; anything else is a NaN in C and `None`
  here.

Every `a*b + c` the FMA build contracts is one fused operation, in the
positions read from the Ubuntu 24.04 library (`libm.so.6`, build ID
`d53fcbff9f855463606b25cfbe2a2e10856ea3a7`): every polynomial is a chain of
fused steps; the products that close one are fused with the sum that
follows; below 1, `1 - t*t*z`, `1.5 - 0.5*t*c`, `t27*c + c`, the split
`(t27*c + c) - t27*c`, `t + y` and `z - y*y` are one each, and `p*(y + cc)`
is a product by itself. `tools/reference/glibc_acos/model.c` is that
arithmetic in C (`FUSED=1`; `FUSED=0` is the source without contraction,
which is the SSE2 variant), with the tables as words.
`tools/reference/glibc_acos/run_sample.sh` compares each model with the
host's `acos` (the SSE2 one with
`GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4`) and the two models with
each other on seeded samples; on Ubuntu 24.04, glibc 2.39-0ubuntu8.9, a
billion arguments each (`tools/reference/glibc_acos/results`):

| Arguments drawn | FMA model and host | SSE2 model and host | Doubles on which the two models differ |
|---|---:|---:|---:|
| any binary64 word | 0 differences | 0 | 381 |
| a magnitude of any exponent from 2^-60 to 1 | 0 | 0 | 13,025 |
| a binary32 value of [-1, 1], widened | 0 | 0 | 6,095 |
| within 2048 doubles of an interval's bound | 0 | 0 | 880,469 |
| a magnitude in [1/8, 1), any double as likely | 0 | 0 | 257,660 |

Each model is its build on every argument. The builds are not each other
(a double in 4000 of [1/8, 1) differs, by a unit in the last place), which
is why the profile is one variant's and not the function's; none of the
five billion pairs narrows to two different floats.

Unmodified glibc 2.39 files in `tools/reference/glibc239`, identical to
release commit `ef321e23c20eebc6d6fb4044425c00e6df27b05f`
(`sysdeps/ieee754/dbl-64/`):

| File | SHA-256 |
|---|---|
| `e_asin.c` | `cf56fcbf627fd8d57ca280e95ec891b978c70ae54f0f5929cc017003a3256eeb` |
| `uasncs.h` | `27a627aae3639ad30b30cd77193c6e2f62ea662b24e5fc94b7617ffbaf61fff7` |
| `asincos.tbl` | `067c3b7047ab28b087262ba26a839ad23bf39236a843897306d5c828d69904f0` |
| `root.tbl` | `f3c9d14fdf380e8db2098a183266721cd800ddeb4745ef14f2a491c35b17f5eb` |
| `powtwo.tbl` | `e66e94adcd700010aa6ea5407130486ef4dba610311c1aab74bda7952bd67f53` |

The port's table lists hold, an interval a list, the doubles `acos` reads
of each entry in the order it reads them (2136 of the table's 2568; `asin`
reads the others); the unit tests hold the model's and the port's tables
and constants against the pinned files.

`M.Glibc241Libm` and `M.AppleLibm` answer `None` (a 2.41 library's
contraction has not been read; macOS's function is not modeled), as do
arguments outside [-1, 1], infinities and NaN on every profile. Out of
contract: errno, exception flags and rounding modes other than to nearest.

Gate `glibc-acos` (`tools/glibc_acos_probe.py`, with `tools/glibc_acos.py`)
compiles the model on the host, requires it to reproduce 32 recorded
results where the FMA and SSE2 variants differ (four an interval, two a
sign), compares it with the host's `acos` where that reproduces them too,
and requires Jonmath to equal it on 4062 arguments: random words of every
exponent up to 1, 48 in each interval, promoted binary32 values, every
interval's bound and every table entry's first argument with their
neighbours, arguments below 1 through all 128 reciprocal roots and every
power of two, 1 and -1, and nine that are `None`, on CPU-1, CPU-2 and
JavaScript.

## The cube root of stb_truetype's solver

`src/power64.bend`'s `third(bits)` is `(float) pow((double) x, (double)
(1.0f/3.0f))` for a float `x`: the cube root `stbtt__cuberoot` takes when
`stbtt__solve_cubic` finds one real root (its sign is the caller's). It is
Arm optimized-routines' `math/pow.c` (with `pow_log_data.c` and
`exp_data.c`, MIT alternative, [LICENSES/arm-math.txt](../LICENSES/arm-math.txt))
as glibc 2.39's x86_64 `pow` runs it in its FMA ifunc variant, restricted to
that exponent: `log_inline` of `x` in two parts (a table of 128 intervals and
a polynomial of degree 8), the product with `y` in two parts, and
`exp_inline` (a table of 2^(k/128) and a polynomial of degree 5). Where the
FMA build contracts was read from the library's code (`libm.so.6`, build ID
`d53fcbff9f855463606b25cfbe2a2e10856ea3a7`): beside the source's own fused
steps, `kd*Ln2hi + logc`, `kd*Ln2lo + logctail`, every `a + r*b` of the two
polynomials, their sums with the `ar2` and `r2` products,
`ar3*(...) + (lo1 + lo2 + lo3 + lo4)`, `y*lo + (...)`, `InvLn2N*x + Shift`,
`kd*NegLn2hiN + x`, `kd*NegLn2loN + (...)` and `scale*tmp + scale` are one
fused operation each.

`tools/reference/glibc_pow/model.c` is the whole function in C (`FUSED=1`,
and `FUSED=0` for the SSE2 build: the source's branch without `fma`), with
the tables as words; they are the words of the library.
`run_exhaustive.sh` compares the models with the host's `pow` (the SSE2 one
with `GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4`) and with each other
on every float `x` and that exponent: on Ubuntu 24.04, glibc 2.39-0ubuntu8.9
(`tools/reference/glibc_pow/results`):

| Comparison | Floats | Doubles that differ | Narrowed floats that differ |
|---|---:|---:|---:|
| FMA model and host | 4,294,967,296 | 0 | 0 |
| SSE2 model and host | 4,294,967,296 | 0 | 0 |
| the two models | 4,294,967,296 | 1,515,625 | 0 |

So the two builds give the same float for every float, and the port computes
one (the FMA one). A zero of either sign gives +0 (`pow`'s `x*x`); a
negative `x` (a NaN in C), the infinities and NaN are `None`, as is a step
the exact binary64 helpers do not take (none of the gate's positive finite
floats does).
Below 2^-54 the exponential answers `1 + x`, which only `x = 1` reaches.

Gate `pow-third` (`tools/pow_third_probe.py`, with `tools/glibc_pow.py`)
compiles the model on the host, requires it to reproduce 32 recorded
results where the two builds' doubles differ (two in each of sixteen ranges
of the exponent, with the floats they narrow to), compares it with the
host's `pow` where that reproduces them too, and requires the port to equal
it on floats of every exponent (the subnormal ones too), a float in each of
the logarithm table's 128 intervals at three exponents, 1 and its
neighbours, the cubes of 1 to 40, every power of two, the smallest and
largest floats, the zeros and what is refused, on CPU-1, CPU-2 and
JavaScript.
