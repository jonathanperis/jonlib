# Models: meshes, BeginMode3D and 3D shapes

Phase 5, first slice: raylib's CPU mesh data, the mesh generators (the
`par_shapes` sphere, hemisphere and torus included, under the glibc
profiles), mesh utilities and export, mesh/model
collision queries, `BeginMode3D`/`EndMode3D` for orthographic cameras and
every `rmodels.c` 3D shape, all reproducing pinned raylib 6.0 exactly.
Altered Bend adaptations of `rmodels.c` and of `rcore.c`'s
`BeginMode3D`/`EndMode3D` (zlib, [LICENSES/raylib.txt](../LICENSES/raylib.txt));
3D drawing renders through the Bend port of `rlsw.h` 1.5 (MIT,
[LICENSES/rlsw.txt](../LICENSES/rlsw.txt)) described in [FRAME.md](FRAME.md)
and [RLGL.md](RLGL.md). Code: the section "Models" of `jonlib.bend`,
`src/mesh.bend` (attribute generation, tangents, bounding boxes, OBJ and
code text), `src/par_shapes.bend` (the `par_shapes` adaptation, MIT,
[LICENSES/par_shapes.txt](../LICENSES/par_shapes.txt)) and
`src/shapes3d.bend` (the rlgl streams of the 3D shapes).

## Mesh and Model

```
type Mesh is Data:
  Mesh{vertex_count: U32, triangle_count: U32, vertices: Maybe<&2, +List<F32>>, texcoords: Maybe<&2, +List<F32>>,
    texcoords2: Maybe<&2, +List<F32>>, normals: Maybe<&2, +List<F32>>, tangents: Maybe<&2, +List<F32>>,
    colors: Maybe<&2, +List<U32>>, indices: Maybe<&2, +List<U32>>}

type Model is Data:
  Model{transform: M.Matrix, meshes: +List<Mesh>}
```

A `Mesh` holds raylib's CPU attribute arrays as F32 (or byte/index) lists in
raylib's order, `None` where raylib's pointer is `NULL`. Indices are the
unsigned short values (generators take them modulo 2^16, as C converts).
Vertex arrays raylib allocates with zero elements (`malloc(0)`) are
`Some{Nil}`. GPU buffer ids (`vaoId`, `vboId`), animation data
(`animVertices`, bones) and materials are not modeled; `UnloadMesh` and
`UnloadModel` consume the value. A `Model` keeps its meshes and transform;
`LoadModelFromMesh` is `Model.from_mesh` (identity transform, the default
material not modeled).

Consumers check that a mesh is *consistent*: each present attribute holds
`vertex_count` elements, indices `3*triangle_count`, counts below 2^22
(raylib's `int` size arithmetic). An inconsistent mesh, or a triangle index
not below `vertex_count`, would make raylib read outside its arrays; Jonlib
answers `None`.

## API

| raylib | Jonlib | Result |
|---|---|---|
| `GenMeshPoly` | `Mesh.gen_poly_for(libm, sides, radius)`, `Mesh.gen_poly` | `Maybe<Mesh>` |
| `GenMeshPlane` | `Mesh.gen_plane(width, length, res_x, res_z)` | `Maybe<Mesh>` |
| `GenMeshCube` | `Mesh.gen_cube(width, height, length)` | `Mesh` |
| `GenMeshSphere` | `Mesh.gen_sphere_for(arithmetic, libm, radius, rings, slices)`, `Mesh.gen_sphere` | `Maybe<Mesh>` |
| `GenMeshHemiSphere` | `Mesh.gen_hemi_sphere_for(arithmetic, libm, after_sphere, radius, rings, slices)`, `Mesh.gen_hemi_sphere` | `Maybe<Mesh>` |
| `GenMeshTorus` | `Mesh.gen_torus_for(arithmetic, libm, radius, size, rad_seg, sides)`, `Mesh.gen_torus` | `Maybe<Mesh>` |
| `GenMeshHeightmap` | `Mesh.gen_heightmap_for(arithmetic, image, size)`, `Mesh.gen_heightmap` | `Result<&1, &1, Surface & Surface.Error, Mesh>` |
| `GenMeshCubicmap` | `Mesh.gen_cubicmap(image, cube_size)` | `Result<&1, &1, Surface & Surface.Error, Mesh>` |
| `GenMeshTangents` | `Mesh.gen_tangents_for(arithmetic, mesh)`, `Mesh.gen_tangents` | `Maybe<Mesh>` |
| `GetMeshBoundingBox` | `Mesh.bounding_box_for(libm, mesh)`, `Mesh.bounding_box` | `Maybe<BoundingBox>` |
| `ExportMesh` | `Mesh.obj_text(mesh) -> Maybe<String>`, `Mesh.export(mesh, path)` | text / `IO(Result<&1, &1, Surface.IOError, Unit>)` |
| `ExportMeshAsCode` | `Mesh.code_text(mesh, path) -> Maybe<String>`, `Mesh.export_as_code(mesh, path)` | text / `IO(Result<...>)` |
| `UnloadMesh` | `Mesh.unload(mesh) -> Unit` | |
| `LoadModelFromMesh` / `UnloadModel` | `Model.from_mesh(mesh)`, `Model.unload(model)` | |
| `GetModelBoundingBox` | `Model.bounding_box_for(arithmetic, libm, model)`, `Model.bounding_box` | `Maybe<BoundingBox>` |
| `GetRayCollisionMesh` | `Collision.ray_mesh_for(arithmetic, ray, mesh, transform)`, `Collision.ray_mesh` | `Maybe<RayCollision>` |
| `BeginMode3D` / `EndMode3D` | `Frame.begin_mode_3d(frame, camera)`, `Frame.end_mode_3d(frame)` | `Frame` |
| `DrawLine3D` / `DrawPoint3D` | `Draw.line_3d(frame, start, end, color)`, `Draw.point_3d(frame, position, color)` | `Frame` |
| `DrawCircle3D` | `Draw.circle_3d_for(libm, frame, center, radius, axis, angle, color)` | `Frame` |
| `DrawTriangle3D` / `DrawTriangleStrip3D` | `Draw.triangle_3d(frame, v1, v2, v3, color)`, `Draw.triangle_strip_3d(frame, points, color)` | `Frame` |
| `DrawCube(V)` / `DrawCubeWires(V)` | `Draw.cube`, `Draw.cube_v`, `Draw.cube_wires`, `Draw.cube_wires_v` | `Frame` |
| `DrawSphere` / `DrawSphereEx` / `DrawSphereWires` | `Draw.sphere_for`, `Draw.sphere_ex_for`, `Draw.sphere_wires_for` | `Frame` |
| `DrawCylinder(Wires)` / `DrawCylinder(Wires)Ex` | `Draw.cylinder_for`, `Draw.cylinder_wires_for`, `Draw.cylinder_ex_for`, `Draw.cylinder_wires_ex_for` | `Frame` |
| `DrawCapsule` / `DrawCapsuleWires` | `Draw.capsule_for`, `Draw.capsule_wires_for` | `Frame` |
| `DrawPlane` / `DrawRay` / `DrawGrid` / `DrawBoundingBox` | `Draw.plane`, `Draw.ray`, `Draw.grid`, `Draw.bounding_box` | `Frame` |

Every `_for` function has a convenience form without the profiles
(`M.Uncontracted{}`, `M.AppleLibm{}`, as elsewhere; the `par_shapes`
generators use `M.Glibc239Libm{}`, the only profile they support). C `int` parameters of
the drawing functions (rings, slices, sides, grid slices) are F32 values
converted as C converts them; the generators take `U32` counts. Points of
`DrawTriangleStrip3D` are a `+List<M.Vector3>` (its count is the length).

## Profiles

- **Contraction (`M.Contraction`).** The raymath helpers `rmodels.c` inlines
  are contracted by the reference compiler where it contracts (Apple clang
  arm64): cross products `fma(a, b, -(c*d))`, dot products and lengths
  `fma(z, w, fma(x, u, y*v))`, `Vector3Transform` fused three-term sums plus
  the translation, and the tangent terms `(t2*x1 - t1*x2)*r` as
  `fma(t2, x1, -(t1*x2))*r`. `GenMeshHeightmap` (normals), `GenMeshTangents`,
  `GetRayCollisionMesh` and `GetModelBoundingBox` take the profile, as do the `par_shapes` generators
  (their cross and dot products, the welding distance and the torus radius
  `1 + minor*cos`); the other generators have no multiply-add. The 3D shapes are drawn as the
  frame is: uncontracted (the reference renderer is built with
  `-ffp-contract=off`, [FRAME.md](FRAME.md#reference-and-profile)).
- **libm (`M.Libm`).** `sinf`/`cosf` arguments must lie in the profile's
  verified set ([FRAME.md](FRAME.md#reference-and-profile)): under
  `M.AppleLibm{}` the integral degrees `fl(DEG2RAD*d)`, `|d| <= 360`
  (except 13, 19, 22, 103, 188); under the glibc profiles normal or zero
  arguments with `|x| <= 6.283186f`. Other arguments refuse the call
  (`None`, or an undefined frame). `GetMeshBoundingBox` uses `fminf`/`fmaxf`
  and so the profile's signed-zero ties ([NATIVE-MATH-PROFILES.md](NATIVE-MATH-PROFILES.md)).

## Generators

- **GenMeshPoly** emits `sides` triangles (origin, `p(d)`, `p(d + step)`)
  with `d` accumulating `360/sides` in F32, `p(d) = (sinf(DEG2RAD*d)*r, 0,
  cosf(DEG2RAD*d)*r)`, normals `(0, 1, 0)` and zero texcoords. Fewer than 3
  sides give the empty mesh; more than 4096 sides are `None`. Under
  `M.AppleLibm{}` the sides whose steps stay on verified degrees (3, 4, 5,
  6, 8, 9, 10, 12, 15, 18, 20, 24, 36, ...) are reproduced.
- **GenMeshPlane** follows the `CUSTOM_MESH_GEN_PLANE` path: `(resX + 1)*(resZ
  + 1)` vertices `((x/resX - 0.5)*width, 0, (z/resZ - 0.5)*length)`, texcoords
  `(x/resX, z/resZ)` and two indexed triangles per face. A resolution of 0
  divides 0 by 0 (a NaN whose sign is platform-defined) and grids above 2^20
  vertices are `None`.
- **GenMeshCube** (`CUSTOM_MESH_GEN_CUBE`): 24 vertices with `-width/2` ...
  coordinates, per-face normals and texcoords, 36 indices.
- **GenMeshHeightmap** loads the image's colors (`LoadImageColors`, any
  format Jonlib converts), heights `(r + g + b)/3*size.y/255`, one quad per
  2x2 pixels (vertices A B C C B F), per-triangle normals
  `Vector3Normalize(Vector3CrossProduct(B - A, C - A))`. Images 1 pixel wide or
  tall give `vertex_count` 0 with empty (present) arrays.
- **GenMeshCubicmap**: `WHITE` (`0xFFFFFFFF`) cells become cubes whose top and
  bottom are always emitted and whose sides are emitted toward `BLACK`
  (`0x000000FF`) neighbors or the map border; `BLACK` cells get a floor and a
  roof; other colors nothing. Texcoords are the six 0.5-wide atlas
  rectangles of `rmodels.c`.
- **GenMeshTangents** accumulates per-triangle `sdir`/`tdir` (`r = 0` when
  `|s1*t2 - s2*t1| < 0.0001f`) per vertex, then Gram-Schmidt against the
  normal, `Vector3Normalize((-n.y, n.x, 0))` (or `(1, 0, 0)` when `|n.z| >
  0.707f`) for tangents shorter than `0.0001f`, and the handedness from
  `dot(cross(n, t), bitangent) < 0`. A mesh without vertices, texcoords or
  normals is returned unchanged; existing tangents are replaced.
- **GetMeshBoundingBox**: `Vector3Min`/`Vector3Max` from the first vertex;
  a mesh without vertices has the zero box; `vertex_count` 0 with present
  vertices reads element 0 (`None`).

### par_shapes generators

`GenMeshSphere`, `GenMeshHemiSphere` and `GenMeshTorus` build a
`par_shapes` parametric mesh (Philip Rideout, MIT,
[LICENSES/par_shapes.txt](../LICENSES/par_shapes.txt)), ported in
`src/par_shapes.bend`:

- **Points.** `(slices + 1)*(stacks + 1)` points from `u = stack/stacks`,
  `v = slice/slices`; the angles are `(float)(u*PAR_PI)` (or `(u*2)*PAR_PI`)
  with `PAR_PI = 3.14159265359` multiplied in binary64 and rounded to F32
  ([BINARY64.md](BINARY64.md)), then `sinf`/`cosf`. Sphere `(cos t sin p, sin
  t sin p, cos p)` (`t` over a full turn), hemisphere the same over half a
  turn, torus `(cos t*b, sin t*b, sin p*minor)` with `b = 1 + minor*cos p`
  (fused under `M.Fused{}`). Texcoords are `(u, v)`.
- **Welded normals.** `par_shapes_weld` maps the points into a 20-cell grid
  (`(p - min)*19/(max - min)` per axis), sorts them by cell index with
  `qsort`, welds each unwelded point's neighbors in the cells within
  `0.001f` whose squared distance is below `0.001f`, condenses the points,
  drops collapsed triangles and maps the welded points back; the normals are
  `par_shapes_compute_normals` of that welded mesh (summed cross products,
  normalized), shared by every point of a weld.
- **The sort is the C library's.** `qsort` does not specify the order of
  equal keys, and the first point of a cell becomes the weld representative
  whose coordinates enter the normals: building `par_shapes.h` with the host
  `qsort`, a stable sort and a reverse-stable one changes the normals of 26
  of 27 meshes tried. Jonlib reproduces glibc's `qsort` (a stable merge sort;
  Jonlib uses a stable counting sort, the same order), so these generators
  need a glibc `M.Libm` profile; under `M.AppleLibm{}` they are `None` (macOS
  `sinf`/`cosf` is not verified on these angles either). Their convenience
  forms therefore use `M.Glibc239Libm{}`.
- **Degenerate triangles.** The sphere and hemisphere drop triangles whose
  squared cross product is below `(2*area)^2`. par_shapes keeps `area` as
  process state: `0.0001f` initially, and `GenMeshSphere` sets it to 0 for the
  rest of the process. `Mesh.gen_hemi_sphere_for` takes that state as
  `after_sphere`.
- **Refusals (`None`).** Meshes above 65535 points (par_shapes' 16-bit indices
  wrap), welds raylib leaves undefined (a point welded to a later one makes it
  read an unset map entry), nonfinite radii or sizes. Fewer than 3 slices or
  stacks give raylib's empty mesh.

The generated mesh is scaled (`radius`, or `size/2` for the torus) and unrolled
per triangle corner as raylib does (no indices). `GenMeshCylinder`,
`GenMeshCone` and `GenMeshKnot` remain refused: their disk caps and trefoil
call the binary64 `cos`/`sin`, for which no verified reproduction exists
([PERSPECTIVE.md](PERSPECTIVE.md) has the same problem with `tan`).

## Export

- **ExportMesh** writes, for a `.obj` path (ASCII case-insensitive, as
  `IsFileExtension`), raylib's banner, `# Vertex Count`/`# Triangle Count`,
  `g mesh`, `v %.6f %.6f %.6f`, `vt %.6f %.6f` and `vn %.4f %.4f %.4f` lines
  and `f a/a/a b/b/b c/c/c` faces (indices + 1, or 1, 4, 7, ... without
  indices), formatted exactly as C's `%.Nf` ([FILES.md](FILES.md); NaN, whose
  spelling differs between C libraries, is `None`). raylib dereferences the
  texcoords and normals, so a mesh without them is `None`, as is text longer
  than raylib's estimated buffer (`dataSize + 1000` bytes, `dataSize` from the
  counts) and inconsistent meshes. Other extensions write nothing (raylib
  returns false): `InvalidRequest`.
- **ExportMeshAsCode** writes the banner, `<NAME>_VERTEX_COUNT` and
  `<NAME>_TRIANGLE_COUNT` defines and one array per present attribute
  (vertices, texcoords, texcoords2, normals, tangents as `%.3ff`; colors as
  `0x%x`; indices as `%i`), 20 values per line, where NAME is
  `GetFileNameWithoutExt` with a-z upper-cased. A present empty array makes
  raylib read element -1: `None`; text beyond the 64 MB buffer is `None`.

## Collision

- **GetRayCollisionMesh** transforms each triangle's vertices with
  `Vector3Transform` (profiled), runs `GetRayCollisionTriangle`
  ([COLLISION.md](COLLISION.md#ray-queries)) and keeps the nearest hit (a later
  hit replaces it only when strictly nearer). A mesh without vertices has no
  hit.
- **GetModelBoundingBox** starts from the first mesh's box and widens it with
  each further mesh using `rmodels.c`'s strict comparisons (`a < b ? a : b`,
  so NaN and equal values pick the other mesh's), then transforms both corners
  with `Vector3Transform`. A model without meshes has the transformed zero
  box.

## BeginMode3D and the 3D shapes

`Frame.begin_mode_3d(frame, camera)` is `BeginMode3D` on the memory
platform: `rlMatrixMode(RL_PROJECTION)`, `rlPushMatrix` (ignored when the
two-entry stack is full), `rlLoadIdentity`, the projection, then
`rlMatrixMode(RL_MODELVIEW)`, `rlLoadIdentity`,
`rlMultMatrixf(MatrixLookAt(position, target, up))` (uncontracted) and
`rlEnableDepthTest`. The aspect is `(float)width/(float)height` of the
current color buffer (the render texture's in texture mode).

- **Orthographic** (`CAMERA_ORTHOGRAPHIC`): `rlOrtho(-right, right, -top, top,
  0.05, 4000.0)` with `top = fovy/2.0` and `right = top*aspect` in binary64.
  Both are exact, so swOrtho's cells are F32 operations: `2/(fovy*aspect)`,
  `2/fovy`, `-0.0f/rl` (the sign of `fovy`) for the centers, and the depth
  cells `-2/(float)(4000 - 0.05)` and `-(float)4000.05/(4000 - 0.05)` rounded
  once (`0xBA0313DA`, `0xBF8000D2`). `fovy`, the span `fovy*aspect` and both
  scales must be finite and nonzero; otherwise a cell is a NaN of
  platform-defined sign (or an infinity that makes one) and the frame is
  refused.
- **Perspective** (`CAMERA_PERSPECTIVE`) is refused: its `rlFrustum` bounds
  are `0.05*tan(fovy*0.5*DEG2RAD)` in binary64 and the native `tan` is not
  reproduced. Over every binary32 `fovy`, macOS misrounds that tangent for
  22.7% of the arguments (`fovy = 45` included) and glibc 2.39/2.41 for 0.12%,
  so neither equals a correctly rounded kernel ([PERSPECTIVE.md](PERSPECTIVE.md)).
- **Other projection values** keep the identity projection, as raylib does.

`Frame.end_mode_3d` pops the projection and resets the modelview; the depth
test stays enabled, so later 2D drawing is depth-tested as in raylib. Ending
a mode that was never begun pops the last projection (undefined in rlsw):
the frame is refused. Depth-tested drawing into a render texture is refused
([RLGL.md](RLGL.md#refusals)).

Each shape is the `rlPushMatrix`/`rlTranslatef`/`rlRotatef`/`rlScalef`/
`rlBegin`/`rlColor4ub`/`rlVertex3f`/`rlEnd`/`rlPopMatrix` stream of
`rmodels.c`, with its F32 arithmetic in source order (`x - width/2` with
`x = 0`, the sphere's incremental rotations, `Vector3Perpendicular` bases
for the `Ex` cylinders and capsules), drawn through the current matrices
(inside or outside `BeginMode3D`). `rlNormal3f` does nothing in rlsw. The
color is set exactly as often as `rmodels.c` sets it, which matters for
rlsw's per-primitive alpha flag ([FRAME.md](FRAME.md#the-rendering-path)).

- **Trigonometry.** `DrawCircle3D` uses multiples of 10 degrees and its
  `rlRotatef` angle; `DrawSphereEx` the two angles `DEG2RAD*(180/(rings +
  1))` and `DEG2RAD*(360/slices)`; `DrawCylinder(Wires)` `(DEG2RAD*i)*(360/sides)`;
  the `Ex` cylinders and capsules `((2*PI)/sides)*i` and
  `(PI*0.5/rings)*i`. Every argument must be verified for the profile.
  `DrawSphereWires`' ring angles `DEG2RAD*(270 + 180/(rings + 1)*i)` reach 450
  degrees, outside both profiles' sets, so every drawn wire sphere is refused
  today (its port is complete and waits for a wider verified domain).
- **Loops.** rings, slices and sides above 4096 (`DrawSphereWires` rings above
  4094) and grids above 4097 lines are refused, as are NaN or out-of-range C
  ints.

## Verification

| Gate | Tool | Compares |
|---|---|---|
| `models` | `tools/models_probe.py` | 25 3D scenes (192 operations, 6 random orthographic scenes) byte for byte against the uncontracted memory-platform raylib with the host libm, with the projection/modelview matrices read back; contracts and unverified arguments must be refused (on macOS 15 compared, 10 refused) |
| `models-gnu` | `tools/models_probe.py --gnu-libm` | the same scenes against the glibc-model reference: raylib built with `sinf`/`cosf` replaced by the Arm optimized-routines model (`tools/trig_probe.py`) and `qsort` by a stable merge sort (glibc's order), Jonlib with `M.Glibc239Libm{}`: spheres, cylinders and capsules (18 compared, 7 refused) |
| `mesh` | `tools/mesh_probe.py` | every attribute word, bounding box, collision and exported byte of the generators, tangents, exports, ray and model queries against the linked raylib with the host contraction and libm (on macOS arm64 `M.Fused{}`: 244 cases, 198 compared, 46 refused, the `par_shapes` ones among them) |
| `mesh-uncontracted` | `tools/mesh_probe.py --uncontracted-control` | the same cases against the raylib built with `-ffp-contract=off` (`M.Uncontracted{}`) |
| `mesh-gnu` | `tools/mesh_probe.py --gnu-libm` | the same cases plus the `par_shapes` spheres, hemispheres (before and after a GenMeshSphere) and tori with their tangents, exports and ray queries (bounding boxes left out: their `fminf` is the host's), against the glibc-model build with `M.Uncontracted{}` and `M.Glibc239Libm{}` (232 cases, 220 compared, 12 refused) |

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only models
```

Both probes run CPU-1, CPU-2 and JavaScript lanes. Attributes of more than
3000 words are compared through an FNV-1a hash of all their words plus the
count; image inputs are read from files. The largest meshes (a 256x256-vertex
plane, a 32x32 heightmap) also exercise the JavaScript lane's stack: the
attribute builders are tail-recursive.

## Gaps

- `GenMeshCylinder`, `GenMeshCone`, `GenMeshKnot` (binary64 `cos`/`sin`); the
  `par_shapes` sphere, hemisphere and torus under Apple's `qsort` and
  `sinf`/`cosf`; their fused contraction is implemented but only the
  uncontracted glibc reference is compared.
- Perspective cameras; `DrawSphereWires` (no verified argument domain);
  the Apple profile's `sinf`/`cosf` beyond the integral degrees (most curved
  shapes are verified only under the glibc profile).
- `DrawMesh`, `DrawModel*`, materials, shaders, `UploadMesh`/GPU buffers,
  billboards, model loading (OBJ, IQM, glTF, VOX, M3D) and animation.
- Metal lane and performance: not measured.
