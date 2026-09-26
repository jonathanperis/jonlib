# Math profiles

The current math implementation is Bend source in `jonlib.bend`. It begins the
`raymath.h` work package with six scalar, twenty-eight Vector2 and seventeen Vector3 functions.

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
  `clamp`, `clamp_value`, `rotate`/`rotate_for`, `refract`.

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
  `length(vector)`, `normalize(vector)`.

The cross product retains raylib's handedness and XYZ field order. Dot products
and squared distance accumulate in reference left-to-right F32 order. The
fixture serializer checks all three component bits, including the Z component
and signed zero. Full transforms, remaining metrics and other numeric profiles
remain ledger gaps.

`Vector3.normalize` preserves a zero-length input, including signed-zero bits;
this differs from `Vector2.normalize`, which returns positive-zero components.
Nonzero vectors multiply by the reciprocal length in reference order. Vector3
division requires all three F32 divisors to remain nonzero.

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
