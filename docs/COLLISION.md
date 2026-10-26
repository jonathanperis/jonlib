# Collision query profiles

## 3D foundation

`Collision.spheres(center, radius, other_center, other_radius)` compares the
Vector3 squared distance inclusively with the squared sum of radii.
`Collision.boxes(left, right)` accepts two `BoundingBox{min, max}` values and
includes touching faces, edges and points. X overlaps with `>=` and `<=`. Y and
Z clear the hit only when a strict `<` or `>` separation is true, so a NaN on
Y or Z is not a miss. Bounds are not normalized, and negative radii retain
raylib's squared-sum behavior. Subnormal and non-finite box fields are compared
with the linked query. Fixtures also include separation on the Z axis.

`Collision.box_sphere(box, center, radius)` clamps each center component using
raylib's `Clamp` ordering, then compares the closest-point squared distance
inclusively against `radius*radius`. Reversed bounds and negative radii retain
their reference behavior; they are not repaired or normalized. Sphere and
box-sphere fields may be subnormal or non-finite. Both the uncontracted profile
and the Apple-clang FMA profile match those inputs; a non-finite fused
multiply-add uses the total fma, and finite normals keep the finite-normal
rounding.

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
| `Collision.lines(start, end, other_start, other_end)` | `Maybe<&2, Vector2>`; inclusive segment endpoints, `None` for parallel/collinear lines or intersections outside either segment. Subnormal and non-finite endpoints are included under both contraction profiles. |
| `Collision.lines_for(arithmetic, start, end, other_start, other_end)` | Explicit `M.Contraction` selection described below. |
| `Collision.point_triangle(point, first, second, third)` | Strictly positive barycentric weights; excludes edges and degenerate triangles. |
| `Collision.point_line(point, first, second, threshold)` | Strict cross-product margin and inclusive dominant-axis bounds; F32 threshold truncated toward zero like the C `int`. |
| `Collision.circle_line(center, radius, first, second)` | Closest point on the segment; near-zero segments use the reference epsilon fallback to the first endpoint. |
| `Collision.point_poly(point, points)` | Reference odd/even ray crossings over an immutable `+List<Vector2>`; fewer than three vertices returns false. Subnormal and non-finite coordinates are included. The crossing expression is a multiply, a divide and an add. |

`point_rec`, `recs` and `rectangle` take every F32 field, including subnormals
and non-finite values. `recs` is additions and comparisons, so a contracted
build does not change it. `rectangle` keeps the second operand when the two
fields compare equal, including its signed-zero bit; this differs from the
profiled `Vector2.min/max` operations. `circles`, `point_circle`, `circle_rec`,
`point_triangle`, `point_line` and `circle_line` do too, under both contraction
profiles. `point_line` takes a threshold whose truncation fits in a C `int`; a
non-finite threshold or one outside that range is undefined in C.
`point_poly` takes the same exceptional coordinates. Its crossing test multiplies,
divides, then adds; the pinned Release build keeps those three operations, so a
contracted build does not fuse it.
Rectangles and radii are not normalized: zero/negative rectangle extents can
satisfy `recs` while yielding an empty `rectangle`, and signed radii retain
the reference squared-sum behavior. The shared fixtures still use finite
fields in -32767..32767.

The shared conformance suite calls the actual linked raylib queries and compares
every Boolean and all four rectangle result-bit fields. Fixtures include interior,
disjoint, touching, one-ULP-inside/outside, signed-zero and degenerate inputs.
`tools/collision_domain_probe.py` compares `point_rec`, `recs`, `boxes` and
`rectangle` on subnormal and non-finite fields, including every result bit.
Default predicate arithmetic is uncontracted F32; every predicate whose linked
reference contracts multiply-adds also has a `_for` variant (below).
Performance parity is not established. Exceptional ray inputs are in the ray
section below. See [PROGRESS.md](PROGRESS.md) for remaining collision APIs.

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
| `Collision.ray_sphere(ray, center, radius)` | `RayCollision`; `hit` when the discriminant is not negative. From inside the sphere the distance is `v + sqrt(d)` and the normal points outwards. A miss, or a hit behind the origin (negative distance), is the zero collision. |
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
int range before the cast (undefined in C, such as degenerate boxes).

The arm64 build fuses each inlined raymath helper: a dot product is
`fma(z, w, fma(x, u, y*v))`, a cross-product component `fma(a, b, -(c*d))`,
the sphere discriminant `fma(r, r, -fma(dist, dist, -(v*v)))` and the box
center lerp `fma(0.5, max - min, min)`; `position + direction*t`, the normal
scaling and divisions stay separate operations. A non-finite fused multiply-add
uses the total fma (`Collision.fma`). Finite normals stay on the finite-normal
rounding.

Subnormal and non-finite fields are included for all four queries, under both
contraction profiles. Triangle and box match every result bit. Sphere does not
reproduce NaN signs or payloads of an uncontracted normal. A quad hit point can
differ by a quiet-NaN sign on the CPU lanes; the fused profile and JavaScript
match those bits.

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
lose tiny addends at an F32 halfway boundary. A non-finite factor or addend
does not take that path: `Collision.multiply_add` and `Collision.fma` use the
total fma (`src/fma.bend`), which matches `fmaf` on infinities and NaN. Finite
normals stay on `src/fused.bend`. The ray cross term, sphere discriminant and
box-center lerp go through `Collision.fma`.

## How it is verified

| Gate | Tool | Compares |
|---|---|---|
| `conformance` | `tools/conformance.py` | every Boolean and all rectangle/point result bits vs the linked raylib queries, with the host's arithmetic profile |
| `collision-domain` | `tools/collision_domain_probe.py` | `point_rec`, `recs`, `boxes` and `rectangle` on subnormal and non-finite fields |
| `collision-exceptional` | `tools/collision_exceptional_probe.py` | `circles`, `point_circle`, `circle_rec`, `point_triangle`, `point_line`, `circle_line`, `spheres` and `box_sphere` on subnormal and non-finite fields; uncontracted against linked raylib and fused against the Apple-clang fma shapes |
| `collision-poly` | `tools/collision_poly_probe.py` | `point_poly` on subnormal and non-finite coordinates |
| `collision-lines` | `tools/collision_lines_probe.py` | `lines` on subnormal and non-finite endpoints; uncontracted against linked raylib and fused against the Apple-clang fma shapes |
| `fused` | `tools/fused_probe.py` | the internal finite-normal F32 multiply-add vs native `fmaf`, including double-rounding counterexamples, cancellation and signed zeros |
| `ray-exceptional` | `tools/ray_exceptional_probe.py` | `ray_sphere`, `ray_triangle`, `ray_quad` and `ray_box` on subnormal and non-finite fields; uncontracted against linked raylib and fused against the Apple-clang fma shapes, allowing a quiet-NaN sign on an uncontracted sphere normal or quad hit point |
| `ray` | `tools/ray_probe.py` | every ray-collision field bit vs the linked raylib with the host contraction and libm profiles; a C oracle repeating the box contract selects the expected `None` results |
| `ray-uncontracted` | `tools/ray_probe.py --uncontracted-control` | the same cases against the pinned `rmodels.c` ray functions compiled without contraction, checking `M.Uncontracted{}` on every host |
| `mesh`, `mesh-uncontracted` | `tools/mesh_probe.py` | `GetRayCollisionMesh` (`Collision.ray_mesh_for`) and `GetModelBoundingBox` on generated and hand-built meshes under three transforms, every result bit ([MODELS.md](MODELS.md#collision)) |

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only fused
```

The original segment counterexample stays in the strict native-raylib corpus.
Triangle and box are established on exceptional inputs. Sphere and quad are
established except for the quiet-NaN signs above. A fused multiply-add whose
factors and addend are finite stays on the finite-normal rounding. Compilers
that fuse a different subset than the two declared profiles are not a selected
host.
