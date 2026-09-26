# Collision query profiles

## 3D foundation

`Collision.spheres(center, radius, other_center, other_radius)` compares the
Vector3 squared distance inclusively with the squared sum of radii.
`Collision.boxes(left, right)` accepts two `BoundingBox{min, max}` values and
includes touching faces, edges and points. Bounds are not normalized, and
negative radii retain raylib's squared-sum behavior. The same bounded finite
input and numerical/platform limitations below apply. Fixtures compare the
actual linked `rmodels.c` queries and include separation on the Z axis.

## 2D queries

Pure Bend queries in `jonlib.bend`, adapted from pinned raylib `rshapes.c`:

| Operation | Result and edge behavior |
|---|---|
| `Collision.recs(left, right)` | Boolean; four strict rectangle comparisons. Edge-only contact is false. |
| `Collision.circles(center, radius, other_center, other_radius)` | Boolean; squared distance is compared inclusively against the squared sum of radii. Tangency is true. |
| `Collision.rectangle(left, right)` | The overlapping `Rectangle`, or four positive zeros when either overlap extent is not positive. |
| `Collision.point_rec(point, rectangle)` | Includes left/top edges; excludes right/bottom edges. |
| `Collision.point_circle(point, center, radius)` | Inclusive squared-distance test. |
| `Collision.circle_rec(center, radius, rectangle)` | Reference side/corner distance test, including tangency. |
| `Collision.lines(start, end, other_start, other_end)` | `Maybe<&2, Vector2>`; inclusive segment endpoints, `None` for parallel/collinear lines or intersections outside either segment. |
| `Collision.lines_for(arithmetic, start, end, other_start, other_end)` | Explicit `Collision.Arithmetic` selection described below. |
| `Collision.point_triangle(point, first, second, third)` | Strictly positive barycentric weights; excludes edges and degenerate triangles. |
| `Collision.point_line(point, first, second, threshold)` | Strict cross-product margin and inclusive dominant-axis bounds; integral F32 threshold. |
| `Collision.circle_line(center, radius, first, second)` | Closest point on the segment; near-zero segments use the reference epsilon fallback to the first endpoint. |
| `Collision.point_poly(point, points)` | Reference odd/even ray crossings over an immutable `+List<Vector2>`; fewer than three vertices returns false. |

Inputs are F32 values with finite fields in -32767..32767. The implementation
retains the reference arithmetic and comparison order. Rectangles and radii are
not normalized: zero/negative rectangle extents can satisfy `recs` while yielding
an empty `rectangle`, and signed radii retain the reference squared-sum behavior.
Equal coordinate comparisons select the second operand in `rectangle`, including
its signed-zero bit; this differs from the profiled `Vector2.min/max` operations.

The shared conformance suite calls the actual linked raylib queries and compares
every Boolean and all four rectangle result-bit fields. Fixtures include interior,
disjoint, touching, one-ULP-inside/outside, signed-zero and degenerate inputs.
Default predicate arithmetic is uncontracted F32; segment queries additionally
expose the fused profile below. These finite-input fixtures do not establish
exceptional/subnormal or all contracted/platform variants, nor
performance parity. See [PROGRESS.md](PROGRESS.md) for remaining collision APIs.

Polygon fixtures permit up to 4096 vertices. Boundary classification follows the
actual crossing comparisons and is not replaced by a generic “edge is inside”
rule. Segment intersections reject determinants with magnitude below
`FLT_EPSILON` (2^-23). The optional result adapts raylib's Boolean/pointer pair:
`Some{point}` on success and `None{}` on failure.

## Linked-reference arithmetic

`Collision.lines` uses `UncontractedCollision{}`. Select `FusedCollision{}` through
`lines_for` for the exercised Apple clang/macOS arm64 reference, whose linked
`CheckCollisionLines` uses fused multiply-add. Hosted Linux/x86_64 uses the
uncontracted profile. These are explicit arithmetic choices, independent of
the gradient/libm profile.

The internal `src/fused.bend` retains the exact F32 product, aligns integer limbs
and rounds the sum directly to 24 bits. Rounding through a binary64 sum would
lose tiny addends at an F32 halfway boundary. `tools/fused_probe.py` compares
2,056 finite-normal cases with native `fmaf`, including those double-rounding
counterexamples, cancellation and signed zeros:

```sh
python3 tools/fused_probe.py --bend-source "$BEND_SOURCE" --gpu
```

Set `BEND_SOURCE` as documented in [README.md](../README.md#requirements).
The original segment counterexample remains in the strict native-raylib corpus.
NaN/infinity, subnormal intermediates/results, overflow, other contraction
patterns and full contracted profiles for the other predicates remain gaps.
