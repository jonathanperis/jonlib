# Math profiles

The current math implementation is Bend source in `jonlib.bend`. It begins the
`raymath.h` work package with six scalar, thirty-one Vector2, thirty-nine Vector3,
twenty-two Vector4, twenty-three Matrix and twenty-one Quaternion functions.

## Scalar API

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

`rotate_for(reference, vector, radians)` uses the explicit trigonometric reference
profile; `rotate` selects the accurate profile. The current profile covers finite
radians within one cycle and preserves reference operation order. See
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
pinned Vector4 functions now have scoped mappings:

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
the existing `Gradient.Reference`; convenience calls select `AccurateGradient{}`.
The initial profile bounds every angle component to absolute value ≤ 6.283186,
matching the existing one-cycle F32 rotation profile. Wider angles remain gaps.

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

`MatrixPerspective` remains blocked by an observed native binary64 tangent
rounding difference that survives into F32 matrix fields. The exact counterexample
and reproducible diagnostic are recorded in [PERSPECTIVE.md](PERSPECTIVE.md).

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
select `AccurateGradient{}`, with each input angle bounded to absolute value
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
Spherical interpolation and axis/Euler extraction currently depend on an
unresolved native inverse-trig profile; retained failures and the diagnostic
are documented in [INVERSE-TRIG.md](INVERSE-TRIG.md).

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

`Vector2.angle(left, right)` returns the reference signed cross/dot angle.
`Vector2.line_angle(start, end)` negates the endpoint-difference angle.
`Vector3.angle(left, right)` uses the reference cross-product length and dot
product. Each has an `_for(reference, ...)` variant; convenience calls use the
existing `AccurateGradient{}` Apple selection, while `GnuGradient{}` selects the
GNU float profile.

The Apple numerical specification rounds π toward zero near the negative X axis;
the GNU profile retains its own float polynomial and quadrant corrections.
The implementations preserve those observable differences. An independent Bend
polynomial evaluation and licensed Sun-kernel adaptation replace backend-native
atan2 primitives that failed exact probes. Supporting binary64 multiplication
and division round directly from integer limbs.

The angle oracle explicitly disables builtin `atan2f` folding, and the standalone
probe calls the native function through a volatile pointer. This distinguishes
actual libm behavior from compiler-folded literal calls. Probe artifacts retain
both endpoint variants and host/compiler information.

```sh
python3 tools/float64_ops_probe.py --bend-source "$BEND_SOURCE" --gpu
python3 tools/angle_probe.py --bend-source "$BEND_SOURCE" --gpu
python3 tools/angle_probe.py --bend-source "$BEND_SOURCE" --gnu-control --gpu
```

The current angle profile covers finite inputs with normal/zero intermediates
and outputs. Exceptional/subnormal arithmetic and other libm/contracted variants
remain gaps. Runtime probe batches are bounded while each lane is compiled once.

## Floating-point contract and evidence

The initial profile is **uncontracted F32**, matching the primitive arithmetic
contract of the pinned Bend compiler. The independent C reference includes the
unmodified pinned `raymath.h` with `FP_CONTRACT OFF`. This choice is explicit:
fused multiply-add/contracted build variants are separate, unverified contracts.

The shared fixtures compare exact returned F32 bit patterns and Boolean values.
Vector-returning operations write every component to adjacent verification cells;
the validator requires all cells to fit. Signed zero is retained in generated
Bend literals. There is no tolerance added to make mismatches pass.

Current evidence uses finite inputs, nonzero normalized ranges, and nonzero
component divisors. Exceptional/subnormal behavior, contracted builds, remaining
raymath functions and the full target/performance matrix remain open. These
are partial mappings, not completed raymath APIs. See the
[progress dashboard](PROGRESS.md) and [verification record](VERIFICATION.md).
