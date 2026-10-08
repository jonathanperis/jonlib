# Collision query profiles

## 3D foundation

`Collision.spheres(center, radius, other_center, other_radius)` compares the
Vector3 squared distance inclusively with the squared sum of radii.
`Collision.boxes(left, right)` accepts two `BoundingBox{min, max}` values and
includes touching faces, edges and points. Bounds are not normalized, and
negative radii retain raylib's squared-sum behavior. The same bounded finite
input and numerical/platform limitations below apply. Fixtures compare the
actual linked `rmodels.c` queries and include separation on the Z axis.

`Collision.box_sphere(box, center, radius)` clamps each center component using
raylib's `Clamp` ordering, then compares the closest-point squared distance
inclusively against `radius*radius`. Reversed bounds and negative radii retain
their reference behavior; they are not repaired or normalized.

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
| `Collision.lines_for(arithmetic, start, end, other_start, other_end)` | Explicit `M.Contraction` selection described below. |
| `Collision.point_triangle(point, first, second, third)` | Strictly positive barycentric weights; excludes edges and degenerate triangles. |
| `Collision.point_line(point, first, second, threshold)` | Strict cross-product margin and inclusive dominant-axis bounds; F32 threshold truncated toward zero like the C `int`. |
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
Default predicate arithmetic is uncontracted F32; every predicate whose linked
reference contracts multiply-adds also has a `_for` variant (below). These
finite-input fixtures do not establish exceptional/subnormal inputs, nor
performance parity. See [PROGRESS.md](PROGRESS.md) for remaining collision APIs.

Polygon fixtures permit up to 4096 vertices. Boundary classification follows the
actual crossing comparisons and is not replaced by a generic “edge is inside”
rule. Segment intersections reject determinants with magnitude below
`FLT_EPSILON` (2^-23). The optional result adapts raylib's Boolean/pointer pair:
`Some{point}` on success and `None{}` on failure.

## Ray queries

`Ray{position, direction}` and `RayCollision{hit, distance, point, normal}`
mirror raylib's structs; directions are not normalized. Adapted from pinned
raylib `rmodels.c`, each query has a `_for` variant taking the arithmetic
profile (below), and the convenience form uses `M.Uncontracted{}`:

| Operation | Result and edge behavior |
|---|---|
| `Collision.ray_sphere(ray, center, radius)` | `RayCollision`; `hit` when the discriminant is not negative. From inside the sphere the distance is `v + sqrt(d)` and the normal points outwards. Misses keep raylib's NaN distance, point and normal. |
| `Collision.ray_triangle(ray, p1, p2, p3)` | Moller-Trumbore with raylib's `1e-6` epsilon; parallel rays, points outside the triangle and hits not ahead of the origin are the all-zero miss. |
| `Collision.ray_quad(ray, p1, p2, p3, p4)` | Triangle `(p1, p2, p4)`, then `(p2, p3, p4)` when the first misses. |
| `Collision.ray_box(ray, box)` | `Maybe<RayCollision>`. Slab intersection; a ray starting strictly inside is traced backwards and its distance and normal negated. The normal is the hit point scaled to the unit box by `2.01` and truncated like the C `int` cast. |
| `Collision.ray_mesh_for(arithmetic, ray, mesh, transform)` | `Maybe<RayCollision>`. `GetRayCollisionMesh`: each triangle transformed, the nearest triangle hit; `None` for inconsistent meshes or indices beyond the vertex count ([MODELS.md](MODELS.md#collision)). |

`Collision.ray_box_for(arithmetic, libm, ray, box)` also takes the `M.Libm`
profile, since raylib chooses slab distances with `fmin`/`fmax`, whose
signed-zero ties differ between Apple libm and glibc (as in
`Vector2.clamp`). It returns `None` where raylib's result is not portable or
not defined: a NaN slab distance (an origin on a slab plane with a zero direction
component; the arm64 build compiles the hit test as `max(near, 0) <= far`,
which differs from the C expression for NaN) or a normal component outside the
int range before the cast (undefined in C, such as degenerate boxes). Sphere
misses compare NaN as one class, since NaN sign and payload are not portable.

The arm64 build fuses each inlined raymath helper: a dot product is
`fma(z, w, fma(x, u, y*v))`, a cross-product component `fma(a, b, -(c*d))`,
the sphere discriminant `fma(r, r, -fma(dist, dist, -(v*v)))` and the box
center lerp `fma(0.5, max - min, min)`; `position + direction*t`, the normal
scaling and divisions stay separate operations.

## Linked-reference arithmetic

The Apple clang/macOS arm64 build of raylib contracts `a*b + c` into `fmadd` in
nine collision queries and the four ray queries; the Linux x86_64 build does
not. Each therefore has an explicit `_for(arithmetic, ...)` variant taking
`M.Uncontracted{}` or `M.Fused{}`, and its convenience form uses
`M.Uncontracted{}`: `lines`, `circles`, `point_circle`, `circle_rec`,
`point_triangle`, `point_line`, `circle_line`, `spheres`, `box_sphere` and the
ray queries above. The fused shapes were read from the
disassembled linked library: every `a*b + c*d` is `fma(a, b, c*d)`, squared
3D distance is `fma(dz, dz, fma(dx, dx, dy*dy))`, and `circle_line`'s
`p1 - t*d` is a single fused subtraction. The `collision-contraction` fixtures
are non-dyadic inputs on which the two profiles disagree, so each host's suite
fails if the other profile is used. These choices are independent of the
gradient/libm profile.

The harness declares the profile per host: `M.Fused{}` for Darwin arm64,
`M.Uncontracted{}` for Linux x86_64; other hosts need their own verified
declaration. The same declaration selects the spline and Perlin noise profiles
([SPLINES.md](SPLINES.md), [PERLIN.md](PERLIN.md)).

The internal `src/fused.bend` keeps the exact F32 product, aligns integer limbs
and rounds the sum directly to 24 bits. Rounding through a binary64 sum would
lose tiny addends at an F32 halfway boundary.

## How it is verified

| Gate | Tool | Compares |
|---|---|---|
| `conformance` | `tools/conformance.py` | every Boolean and all rectangle/point result bits vs the linked raylib queries, with the host's arithmetic profile |
| `fused` | `tools/fused_probe.py` | the internal finite-normal F32 multiply-add vs native `fmaf`, including double-rounding counterexamples, cancellation and signed zeros |
| `ray` | `tools/ray_probe.py` | every ray-collision field bit vs the linked raylib with the host contraction and libm profiles; a C oracle repeating the box contract selects the expected `None` results |
| `ray-uncontracted` | `tools/ray_probe.py --uncontracted-control` | the same cases against the pinned `rmodels.c` ray functions compiled without contraction, checking `M.Uncontracted{}` on every host |
| `mesh`, `mesh-uncontracted` | `tools/mesh_probe.py` | `GetRayCollisionMesh` (`Collision.ray_mesh_for`) and `GetModelBoundingBox` on generated and hand-built meshes under three transforms, every result bit ([MODELS.md](MODELS.md#collision)) |

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only fused
```

The original segment counterexample stays in the strict native-raylib corpus.
NaN/infinity, subnormal intermediates/results, overflow, other contraction
patterns and other compilers' contraction choices remain gaps.
