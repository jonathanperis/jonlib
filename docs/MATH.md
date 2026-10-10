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

## Vector2 API

`Vector2` remains immutable `Data` with F32 `x` and `y` fields.

- Constructors: `zero()`, `one()`.
- Component operations: `add`, `add_value`, `subtract`, `subtract_value`, `scale`,
  `multiply`, `negate`, `divide`, `invert`, `min`/`min_for`, `max`/`max_for`.
- Metrics: `length`, `length_sqr`, `distance`, `distance_sqr`, `dot_product`, `cross_product`.
- Other operations: `normalize`, `lerp`, `reflect`, `equals`, `move_towards`,
  `clamp`, `clamp_value`, `rotate`/`rotate_for`, `refract`, `transform`,
  `angle`/`angle_for`, `line_angle`/`line_angle_for`.

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

The GNU label is a declared numerical profile, not a guarantee for every glibc
version/compiler evaluation path: constant folding, builtin lowering and native
glibc calls give three different zero-tie behaviours. The reference harness
selects the extrema profile from native controls instead of inferring it from the
host or the gradient/angle profile; see
[NATIVE-MATH-PROFILES.md](NATIVE-MATH-PROFILES.md).

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

`Vector3.normalize` preserves a zero-length input, including signed-zero bits;
this differs from `Vector2.normalize`, which returns positive-zero components.
Nonzero vectors multiply by the reciprocal length in reference order. Vector3
division requires all three F32 divisors to remain nonzero.

`project(vector, onto)` and `reject(vector, onto)` require the reference F32
squared length of `onto` to be nonzero. `perpendicular(vector)` crosses against
the axis whose component has the smallest absolute magnitude; strict comparison
ties retain X before Y before Z. `lerp` permits extrapolation, and `reflect`
does not normalize the supplied normal. `invert` requires nonzero components;
`equals` applies the existing relative epsilon on all three axes.

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

All four components are compared bitwise, including W and signed-zero results.
Metric accumulation remains left-to-right. Division and reciprocals require
every converted F32 divisor to be nonzero. Extrema use the same explicit
signed-zero profiles as Vector2/Vector3. `normalize` returns four positive zeros
for zero length, unlike Vector3's retained input zeros. `lerp` permits
extrapolation; movement retains negative steps and division-before-step ordering,
and snapping returns the exact target. `equals` includes W in the relative
epsilon comparison. These mappings remain partial under the numerical and
target/performance limits below.

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
- `Matrix.translate(x, y, z)` and `scale(x, y, z)` preserve the supplied finite
  components, including negative and signed-zero values.
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
component-wise and requires nonzero divisors; inversion instead uses conjugation
and reciprocal squared length, with the original quaternion returned at zero
length. Both normalization and inversion retain zero quaternion signs, unlike
Vector4's positive-zero normalization result.

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
`M.Libm.pow2(libm, k)` is `powf(2, k)` (and the `exp2f(k)` compilers
substitute for it) for an integral `k` in [-20, 30]: exactly `2^k` under both
glibc profiles (gate `pow2`), `None` for `AppleLibm` and every other `k`.
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
| `v * s`, `v / s` | `M.Vector3.scale(v, s)`, `M.Vector3.scale(v, (1.0 / s : F32))` |
| `v * m` (Vector2/Vector3), `q * m` | `M.Vector3.transform(v, m)`, `M.Quaternion.transform(q, m)` |
| `q + s`, `q - s` | `M.Quaternion.add_value(q, s)`, `M.Quaternion.subtract_value(q, s)` |
| `m * s` | `M.Matrix.multiply_value(m, s)` |
| `a == b`, `a != b` | `M.Vector3.equals(a, b)`, `Bool.not(M.Vector3.equals(a, b))` |

A compound assignment (`a += b`) returns its updated left operand; Bend values
are immutable, so it is the same expression bound to a new name. The
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

Current evidence uses finite inputs, nonzero normalized ranges, and nonzero
component divisors. Exceptional/subnormal behavior, contracted builds, remaining
raymath functions and the full target/performance matrix remain open. These
are partial mappings, not completed raymath APIs. See the
[progress dashboard](PROGRESS.md) and [VERIFICATION.md](VERIFICATION.md).
