# Collision query profiles

Pure Bend queries in `jonlib.bend`, adapted from pinned raylib `rshapes.c`:

| Operation | Result and edge behavior |
|---|---|
| `Collision.recs(left, right)` | Boolean; four strict rectangle comparisons. Edge-only contact is false. |
| `Collision.circles(center, radius, other_center, other_radius)` | Boolean; squared distance is compared inclusively against the squared sum of radii. Tangency is true. |
| `Collision.rectangle(left, right)` | The overlapping `Rectangle`, or four positive zeros when either overlap extent is not positive. |

Inputs are F32 values with finite fields in -32767..32767. The implementation
retains the reference arithmetic and comparison order. Rectangles and radii are
not normalized: zero/negative rectangle extents can satisfy `recs` while yielding
an empty `rectangle`, and signed radii retain the reference squared-sum behavior.
Equal coordinate comparisons select the second operand in `rectangle`, including
its signed-zero bit; this differs from the profiled `Vector2.min/max` operations.

The shared conformance suite calls the actual linked raylib queries and compares
every Boolean and all four rectangle result-bit fields. Fixtures include interior,
disjoint, touching, one-ULP-inside/outside, signed-zero and degenerate inputs.
The current Bend arithmetic is uncontracted F32. These finite-input fixtures do
not establish exceptional/subnormal or all contracted/platform variants, nor
performance parity. See [PROGRESS.md](PROGRESS.md) for remaining collision APIs.
