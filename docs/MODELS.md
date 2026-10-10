# Models: meshes, materials, BeginMode3D, 3D shapes and model files

Phase 5: raylib's CPU mesh data, the mesh generators (the
`par_shapes` sphere, hemisphere and torus included, under the glibc
profiles), mesh utilities and export, mesh/model
collision queries, `BeginMode3D`/`EndMode3D` for orthographic cameras,
every `rmodels.c` 3D shape, materials, `DrawMesh`/`DrawModel*`/billboards and
OBJ (with MTL) loading, all reproducing pinned raylib 6.0 exactly.
Altered Bend adaptations of `rmodels.c` and of `rcore.c`'s
`BeginMode3D`/`EndMode3D` (zlib, [LICENSES/raylib.txt](../LICENSES/raylib.txt));
3D drawing renders through the Bend port of `rlsw.h` 1.5 (MIT,
[LICENSES/rlsw.txt](../LICENSES/rlsw.txt)) described in [FRAME.md](FRAME.md)
and [RLGL.md](RLGL.md). Code: the section "Models" of `jonlib.bend`,
`src/mesh.bend` (attribute generation, tangents, bounding boxes, OBJ and
code text), `src/par_shapes.bend` (the `par_shapes` adaptation, MIT,
[LICENSES/par_shapes.txt](../LICENSES/par_shapes.txt)),
`src/shapes3d.bend` (the rlgl streams of the 3D shapes),
`src/mesh_draw.bend` (the `DrawMesh` and `DrawBillboardPro` streams) and
`src/obj.bend` (the `tinyobj_loader_c` adaptation raylib vendors, MIT,
[LICENSES/tinyobj_loader_c.txt](../LICENSES/tinyobj_loader_c.txt)).

## Mesh and Model

```
type Mesh is Data:
  Mesh{vertex_count: U32, triangle_count: U32, vertices: Maybe<&2, +List<F32>>, texcoords: Maybe<&2, +List<F32>>,
    texcoords2: Maybe<&2, +List<F32>>, normals: Maybe<&2, +List<F32>>, tangents: Maybe<&2, +List<F32>>,
    colors: Maybe<&2, +List<U32>>, indices: Maybe<&2, +List<U32>>}

type MaterialMap is Data:
  MaterialMap{texture: TextureInfo, color: U32, value: F32}

type Material is Data:
  Material{maps: +List<MaterialMap>, params: +List<F32>}

type Model is Data:
  Model{transform: M.Matrix, meshes: +List<Mesh>, materials: +List<Material>, mesh_material: +List<U32>}
```

A `Mesh` holds raylib's CPU attribute arrays as F32 (or byte/index) lists in
raylib's order, `None` where raylib's pointer is `NULL`. Indices are the
unsigned short values (generators take them modulo 2^16, as C converts).
Vertex arrays raylib allocates with zero elements (`malloc(0)`) are
`Some{Nil}`. GPU buffer ids (`vaoId`, `vboId`, all 0 on the software
renderer) and animation data (`animVertices`, bones) are not modeled;
`UnloadMesh` and `UnloadModel` consume the value. A `Model` keeps its
transform, meshes, materials and the material index of each mesh
(`meshMaterial`, C ints as U32 words); `LoadModelFromMesh` is
`Model.from_mesh` (identity transform, `Material.load_default()`, mesh
material 0).

A `Material` holds raylib's 12 maps (`MAX_MATERIAL_MAPS`) and four params.
A map's texture is raylib's `Texture2D` struct as a `TextureInfo` (id 0: no
texture); the texels stay with the `Texture` value that owns them (Jonlib
textures are affine, [TEXTURES.md](TEXTURES.md)). Drawing a mesh whose
diffuse map names a texture therefore takes the textures as a list and hands
them back: the one with the map's id is bound, as raylib binds the id it holds.
Shaders are not modeled: on the software renderer every shader id is 0
(`rlGetShaderIdDefault`, and `LoadShader` compiles nothing under OpenGL 1.1).

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
| `UploadMesh` | `Mesh.upload(mesh, dynamic) -> Mesh` | the mesh given: vertex buffers are OpenGL 3.3/ES2's |
| `LoadModelFromMesh` / `UnloadModel` | `Model.from_mesh(mesh)`, `Model.unload(model)` | |
| `IsModelValid` | `Model.is_valid(model)` | `Bool` |
| `SetModelMeshMaterial` | `Model.set_mesh_material(model, mesh_id, material_id)` | `Maybe<Model>` |
| `LoadModel` | `Model.load_for(arithmetic, frame, path)`, `Model.load(frame, path)` | `IO(Frame & Result<&1, &1, Surface.IOError, LoadedModel>)` |
| `LoadMaterials` | `Material.load_materials_for(arithmetic, frame, path)`, `Material.load_materials` | `IO(Frame & Result<&1, &1, Surface.IOError, LoadedMaterials>)` |
| `LoadMaterialDefault` / `IsMaterialValid` | `Material.load_default()`, `Material.is_valid(material)` | `Material` / `Bool` |
| `UnloadMaterial` | `Material.unload(frame, textures, material)` | `Frame & List<Texture>` |
| `SetMaterialTexture` | `Material.set_texture(material, map_type, info)` | `Maybe<Material>` |
| `DrawMesh` / `DrawMeshInstanced` | `Draw.mesh(frame, textures, mesh, material, transform)`, `Draw.mesh_instanced(frame, textures, mesh, material, transforms)` | `Frame & List<Texture>` |
| `DrawModel` / `DrawModelEx` | `Draw.model(frame, textures, model, position, scale, tint)`, `Draw.model_ex_for(libm, frame, textures, model, position, axis, angle, scale, tint)`, `Draw.model_ex` | `Frame & List<Texture>` |
| `DrawModelWires` / `DrawModelWiresEx` | `Draw.model_wires`, `Draw.model_wires_ex_for`, `Draw.model_wires_ex` (the same parameters) | `Frame & List<Texture>` |
| `DrawBillboard` / `DrawBillboardRec` / `DrawBillboardPro` | `Draw.billboard(frame, camera, texture, position, scale, tint)`, `Draw.billboard_rec(frame, camera, texture, source, position, size, tint)`, `Draw.billboard_pro_for(libm, frame, camera, texture, source, position, up, size, origin, rotation, tint)`, `Draw.billboard_pro` | `Frame & Texture` |
| `GetModelBoundingBox` | `Model.bounding_box_for(arithmetic, libm, model)`, `Model.bounding_box` | `Maybe<BoundingBox>` |
| `GetRayCollisionMesh` | `Collision.ray_mesh_for(arithmetic, ray, mesh, transform)`, `Collision.ray_mesh` | `Maybe<RayCollision>` |
| `BeginMode3D` / `EndMode3D` | `Frame.begin_mode_3d_for(libm, frame, camera)` (`Frame.begin_mode_3d(frame, camera)`: `AppleLibm`), `Frame.end_mode_3d(frame)` | `Frame` |
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
  (except 13, 19, 22, 103, 188); under the glibc profiles every normal or
  zero argument ([SINCOSF.md](SINCOSF.md)). Other arguments refuse the call
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
([PERSPECTIVE.md](PERSPECTIVE.md) solved the same problem for `tan` by
reproducing glibc's function).

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

## Materials

- **LoadMaterialDefault** (`Material.load_default`): 12 zeroed maps; the
  diffuse map holds `(Texture2D){ rlGetTextureIdDefault(), 1, 1, 1, 7 }`, whose
  id is 0 under OpenGL 1.1, and the diffuse and specular colors are WHITE.
- **IsMaterialValid** needs `shader.id > 0`: always false on the software
  renderer (the probe checks it natively).
- **SetMaterialTexture** stores the texture struct (`TextureInfo`, from
  `Texture.info`) in the map; the previous texture is not unloaded. A map type
  of 12 or more makes raylib write past the maps: `None`.
- **UnloadMaterial** unloads, in map order, every map texture whose id is not
  0 (`rlGetTextureIdDefault()`). Those textures are taken from the list passed
  in and unloaded into the frame (their ids return to the pool, so the next
  texture reuses them); the others are handed back. A second map with an id
  already unloaded is an rlsw no-op (`swDeleteTextures` ignores invalid ids).
  Refused (the frame marked undefined): an id that is not in the list (raylib
  would unload a texture Jonlib does not hold) or a primitive being recorded.
- **SetModelMeshMaterial** with C int ids as U32 words: a mesh id at or beyond
  the mesh count, or a non-negative material id at or beyond the material
  count, changes nothing (raylib warns); a negative material id is stored as
  raylib stores it (drawing that mesh is refused); a negative mesh id makes
  raylib write before the array: `None`.
- **IsModelValid** requires meshes, materials and mesh materials, and every
  present attribute uploaded to a GPU buffer. `UploadMesh` creates no buffers
  under OpenGL 1.1, so on the software renderer only models whose meshes have
  no attributes at all (raylib's empty generated meshes) are valid. Meshes are
  assumed uploaded, as every generator and loader leaves them (raylib
  dereferences a NULL `vboId` for a mesh it never uploaded).

## Drawing meshes, models and billboards

What `rmodels.c` does under `GRAPHICS_API_OPENGL_SOFTWARE` (which defines
`GRAPHICS_API_OPENGL_11`), traced in the pinned sources and checked by the
probe:

- **DrawMesh** takes its OpenGL 1.1 branch: `rlEnableTexture(diffuse id)` when
  the mesh has texcoords and the id is positive, `rlEnableStatePointer` for
  vertices, texcoords and colors (rlsw ignores normals), `rlPushMatrix`,
  `rlMultMatrixf(transform)`, `rlColor4ub(diffuse color)`, then
  `rlDrawVertexArray(0, vertexCount)` or
  `rlDrawVertexArrayElements(0, 3*triangleCount, indices)`, `rlPopMatrix`,
  the state pointers disabled and `rlDisableTexture`. rlsw's
  `swDrawArrays`/`swDrawElements` push every vertex through the immediate
  path as `GL_TRIANGLES`: the texcoord (through the texture matrix), the
  color (`byte*SW_INV_255`) when the mesh has colors, then the position; a
  vertex count that is not a multiple of 3 leaves its last vertices pending.
  Their begin resets rlsw's per-primitive alpha flag, so a translucent
  material color alone does not blend: the triangles are stored with the
  material's alpha, unblended. A mesh without vertices draws nothing (an
  rlsw error) but still sets the color and the texture state. Inside an
  `rlBegin` primitive rlsw refuses the arrays: Jonlib refuses the call.
- **DrawMeshInstanced** is compiled only for OpenGL 3.3 and ES2: a no-op.
- **DrawModelEx** multiplies the model transform by
  `MatrixMultiply(MatrixMultiply(MatrixScale, MatrixRotate(axis,
  angle*DEG2RAD)), MatrixTranslate)` (raymath, uncontracted as the reference
  renderer is built; `sinf`/`cosf` from the `M.Libm` profile, an unverified
  argument refuses the draw), then draws each mesh with its material, whose
  diffuse color is tinted per channel as `(c*t)/255`. **DrawModel** is
  `DrawModelEx` about (0, 1, 0) by 0 degrees with a uniform scale. The
  `Wires` forms wrap them in `rlEnableWireMode`/`rlDisableWireMode` (polygons
  are filled afterwards, whatever the mode was). `DrawModelPoints(Ex)` is not
  part of raylib 6.0.
- **DrawBillboardPro** takes the first row of `MatrixLookAt(camera)` as the
  right vector (scaled by `size.x`) and `up*size.y`; a negative size flips the
  source, the vector and the origin; the corners 0, right, up + right and up,
  less `Normalize(right)*origin.x + Normalize(up)*origin.y`, are rotated with
  `Vector3RotateByAxisAngle(cross(right, up), rotation*DEG2RAD)` when the
  rotation is not 0 (`sinf`/`cosf` of half the angle, checked for the
  profile) and moved to the position; texcoords are the source over the
  texture's int size. One textured `RL_QUADS` with the tint.
  **DrawBillboardRec** uses up (0, 1, 0), origin `size*0.5` and no rotation;
  **DrawBillboard** the whole texture with size `(scale*fabsf(width/height),
  scale)`. Billboards use the camera only through `MatrixLookAt` and draw
  through the current projection (orthographic in `BeginMode3D`).

Refused draws mark the frame undefined: inconsistent attribute lists, indices
not below the vertex count, color values above 255, a diffuse id missing from
the textures, a mesh material index beyond the materials, unverified `sinf`/
`cosf` arguments, and the rules of [RLGL.md](RLGL.md#refusals).

## Loading models (OBJ and MTL)

`Model.load_for(arithmetic, frame, path)` is `LoadModel`: `.obj`
(case-insensitive, as `IsFileExtension`) through `LoadOBJ`; IQM, glTF/GLB,
VOX and M3D files (which raylib loads) are `UnsupportedFileType`; other
extensions, and OBJ files that do not open or are empty, give raylib's model
without meshes and with the default material. The result is a
`LoadedModel{model, textures}`: the textures the MTL file's materials loaded
into the frame, which raylib's `UnloadModel` leaves loaded (the caller
unloads them). `LoadModel` sets an identity transform and uploads nothing on
the software renderer. The contraction profile is the reference's for
`tryParseDouble` (below); the convenience `Model.load` uses
`M.Uncontracted{}`.

- **Text.** `LoadFileText` and `strlen`: the text ends at its first NUL. A
  text whose first byte is NUL makes `tinyobj_parse_obj` fail, after which
  `LoadOBJ` returns without restoring the working directory: refused.
- **Lines** (`tinyobj_parse_obj`). Lines end at `\n` and at a `\r` followed by
  another byte than `\n`; a line's `\r` before its `\n` is dropped. The last
  line runs to the end of the text, except that when the text has no
  terminator at all tinyobj drops its last byte. An empty line after a lone
  `\r` underflows its length, and lines of 4095 bytes or more fail
  `assert(p_len < 4095)`: refused.
- **Commands** (`parseLine`). `v`, `vn`, `vt` (`parseFloat`: spaces, then the
  token up to NUL, space, tab or `\r`), `f` (`i`, `i/j`, `i//k`, `i/j/k` with
  `my_atoi`; more than 5 vertices fail tinyobj's `assert(3*num_f < 16)`:
  refused), `usemtl` (the rest of the line, trailing spaces included; an empty
  name keeps the material), `mtllib` (the last one is loaded), `g` and `o`
  (shapes). `mtllib`, `g` or `o` with nothing after their space make tinyobj
  read past the line, and an int overflow in an index or exponent is
  undefined: refused.
- **Numbers** (`tryParseDouble`). The C grammar (`[sign] digits ['.' digits]
  [e [sign] digits]`, greedy; a failed parse leaves 0) evaluated in binary64
  as tinyobj writes it: `mantissa*10 + digit`, `frac_value = 0.1^read` by
  repeated products, `mantissa += digit*frac_value` (one rounding under
  `M.Fused{}`, as the arm64 Apple clang reference contracts it; the probe
  includes literals near binary32 midpoints that round differently in the
  two profiles), `5^e` and `2^e` by repeated products (inverted for a
  negative exponent), `mantissa*a*b` and `(float)`. The operations run
  through Jonlib's checked binary64 helpers ([BINARY64.md](BINARY64.md)); a
  value whose steps leave their domains (more than about 39 integer digits,
  about 80 fraction digits, exponents above 54) is refused when `LoadOBJ`
  reads it (unread values do not matter).
- **Indices and faces.** `fixIndex` makes indices zero-based, negative ones
  relative to the counts read so far; faces are triangulated as fans
  `(f0, f[k-1], f[k])`. Materials come from the MTL file's table (djb2
  hashes of the names, 64-bit, in tinyobj's open table of capacity 10 grown
  to `2*max(capacity, n + 1)` with quadratic probing; an insertion that finds
  no slot loops forever in C: refused); an unknown name is -1.
- **Shapes and meshes** (`LoadOBJ`). tinyobj's shapes record face offsets in
  face *lines*; `LoadOBJ` compares them with triangle indices, starting a new
  mesh at each shape boundary it crosses and at each material change after a
  known material (a change from -1 does not split). A mesh holds 3 vertices
  per triangle: positions, normals ((0, 1, 0) without a valid index) and,
  when the file has texcoords, texcoords with v flipped as `1 - v` (0 without
  a valid index); colors are NULL under OpenGL 1.1. Its material is that of
  its last face (0 when that is not an MTL index). A vertex index that is
  negative or beyond the vertices, or a valid normal or texcoord index beyond
  its array, makes `LoadOBJ` read outside tinyobj's arrays: refused.
- **MTL files** (`tinyobj_parse_and_index_mtl_file`) open relative to the
  OBJ's directory: `LoadOBJ` changes the working directory to
  `GetDirectoryPath(fileName)`, and Jonlib prefixes relative names with it
  instead. Lines come from `dynamic_fgets`, so a last line without `\n` is
  never parsed. `newmtl` takes `sscanf("%s")` (a missing name, one of 4096
  bytes or more, or a longer line is refused); properties before the first
  `newmtl` are lost; `Kd`, `Ks`, `Ke`, `Ns` and the texture names `map_Kd`,
  `map_Ks`, `map_bump`/`bump` and `disp` (the rest of the line up to `\r` or
  `\n`, after one separator) are used; the other keywords are parsed (and
  checked for undefined behavior) but unused. A file that does not open
  leaves no materials; NUL bytes are refused.
- **ProcessMaterialsOBJ.** Per material: `LoadMaterialDefault`, the diffuse
  texture (else the `Kd` color), the specular texture and `Ks` color, the
  bump texture as the normal map (WHITE, value `Ns`), the `Ke` emission color
  and the displacement texture as the height map. Colors are
  `(unsigned char)(x*255.0f)` with alpha 255 (a product outside (-1, 256) is
  undefined: refused). Textures load in that order with `LoadTexture`: a file
  that does not open (or an empty name) gives `(Texture2D){ 0 }`; a file
  Jonlib's `LoadImage` does not decode is refused (raylib may decode it), as
  are exhausted texture ids.
- **LoadMaterials** (`Material.load_materials_for`): a `.mtl` file's
  materials through the same parser and `ProcessMaterialsOBJ`, with texture
  names opened from the working directory as they are; other extensions and
  files that do not open give no materials.
- **Paths.** OBJ paths and MTL and texture names must be printable ASCII
  (Jonlib passes them to the file system unchanged); OBJ paths must not
  contain backslashes (`GetDirectoryPath` splits at them, `chdir` would not)
  and must fit `GetDirectoryPath`'s buffer. Paths that name directories are
  outside the contract.

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
- **Perspective** (`CAMERA_PERSPECTIVE`, `Frame.begin_mode_3d_for(libm,
  frame, camera)`): `rlFrustum(-right, right, -top, top, 0.05, 4000.0)` with
  `top = 0.05*tan(fovy*0.5*DEG2RAD)` and `right = top*aspect` in binary64,
  the tangent from the profile's `M.Libm.tan` ([PERSPECTIVE.md](PERSPECTIVE.md)).
  swFrustum divides `(float)0.1` by the binary64 spans `2*right` and `2*top`
  and narrows m0/m5 to F32; m8/m9 are `+0.0` over the spans (the sign of
  `fovy`) and m10, m11, m14 are constants (`0xBF8000D2`, `-1`, `0xBDCCCD75`).
  A zero or nonfinite m0/m5 refuses the frame. Under `AppleLibm` (and so
  `Frame.begin_mode_3d`) every perspective camera is refused: macOS misrounds
  22.7% of these tangents, `fovy = 45` included, and its `tan` is unpublished.
- **Other projection values** keep the identity projection, as raylib does.

`Frame.end_mode_3d` pops the projection and resets the modelview; the depth
test stays enabled, so later 2D drawing is depth-tested as in raylib. Ending
a mode that was never begun pops the last projection (undefined in rlsw):
the frame is refused. A render texture has its own depth buffer
([RLGL.md](RLGL.md)).

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
  degrees: the glibc profiles draw them (glibc's own `sinf`/`cosf`,
  [SINCOSF.md](SINCOSF.md)); the Apple profile refuses every drawn wire sphere.
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
| `model-draw` | `tools/model_draw_probe.py` | 27 scenes (216 operations, 6 random orthographic scenes of custom meshes) byte for byte against the uncontracted memory-platform raylib with the host libm: `DrawMesh` of generated, empty and custom meshes (indexed or not, texcoords, colors, no vertices, leftover vertices, translucent materials, textures from the scene's slots), `DrawModel(Ex)`, `DrawModelWires(Ex)` (also after point mode), two-mesh models with `SetModelMeshMaterial` and a model transform, `DrawMeshInstanced`, `DrawBillboard(Rec, Pro)` (negative sizes, origins, rotations), and logged `IsMaterialValid`, `IsModelValid`, `LoadMaterialDefault`/`SetMaterialTexture` maps and `UnloadMaterial` (its ids reused by the next texture); contracts must be refused (on macOS 20 compared, 7 refused; on glibc 22 and 5) |
| `obj` | `tools/obj_probe.py` | 40 OBJ/MTL loads (written by the probe with PNG textures) word for word against the linked raylib with the host contraction (on macOS arm64 the fused `tryParseDouble`, `M.Fused{}`): mesh and material counts, `IsModelValid`, every mesh's counts, material index and vertex, normal and texcoord word, every material map; 27 compared, 13 refused |
| `obj-uncontracted` | `tools/obj_probe.py --uncontracted-control` | the same files against the raylib built with `-ffp-contract=off` (`M.Uncontracted{}`); the corpus includes literals whose fused and unfused parses round to different floats |

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only models
```

Every probe runs CPU-1, CPU-2 and JavaScript lanes. Attributes of more than
3000 words are compared through an FNV-1a hash of all their words plus the
count; image inputs are read from files. The largest meshes (a 256x256-vertex
plane, a 32x32 heightmap) also exercise the JavaScript lane's stack: the
attribute builders are tail-recursive.

## Gaps

- `GenMeshCylinder`, `GenMeshCone`, `GenMeshKnot` (binary64 `cos`/`sin`); the
  `par_shapes` sphere, hemisphere and torus under Apple's `qsort` and
  `sinf`/`cosf`; their fused contraction is implemented but only the
  uncontracted glibc reference is compared.
- Perspective cameras and `DrawSphereWires` under the Apple profile;
  the Apple profile's `sinf`/`cosf` beyond the integral degrees (most curved
  shapes are verified only under the glibc profile).
- Shaders (no shader is compiled under OpenGL 1.1), `UploadMesh`/GPU
  buffers, `UpdateMeshBuffer`, `GenMeshCylinder`/`Cone`/`Knot` (above) and
  model animation (`LoadModelAnimations`, `UpdateModelAnimation*`).
- IQM, glTF/GLB, VOX and M3D files: `LoadModel` answers
  `UnsupportedFileType` (raylib loads them; their parsers, binary formats and
  for glTF its JSON and accessor handling are not ported).
- OBJ: faces of 6 or 7 vertices (accepted by builds without asserts, refused
  here), numbers beyond the checked binary64 domains, non-ASCII names, and
  texture files Jonlib's `LoadImage` does not decode.
- Textures shared between models: a material holds a texture's struct, but
  the drawing call needs the owning `Texture` value in its list.
- Metal lane and performance: not measured.
