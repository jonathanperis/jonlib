# raylib [models] example - decals, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_decals.c (zlib/libpng,
# Copyright (c) 2025 JP Mortiboys (@themushroompirates) and Ramon Santamaria
# (@raysan5)); see LICENSES/raylib.txt.
#
# A character model on which a click splats a decal: the model's triangles
# near the hit point, in the space of a box looking along the surface
# normal and turned by a random angle, clipped against the box's six planes
# and textured with the raylib logo (the example's GenMeshDecal, its mesh
# builders as lists). A translucent cube shows where the next decal would
# go; the table counts the vertices and triangles; RMB moves the camera.
# LoadOBJ's meshes are not indexed, so GenMeshDecal's branch for indexed
# meshes is not ported (such a mesh makes no decal here). The example's
# first button is drawn at screenHeight - 1000, above the screen, where the
# mouse cannot reach it: it is kept there. The perspective needs the libm
# profile's binary64 tan (docs/PERSPECTIVE.md); UpdateCamera's and
# MatrixRotateZ's sinf/cosf follow the profile (docs/SINCOSF.md). raylib
# seeds the generator from time(NULL) in InitWindow; here the seed is a
# setup argument.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# A triangle of a mesh builder.
type Tri is Data:
  Tri{a: M.Vector3, b: M.Vector3, c: M.Vector3}

# The character, its mesh's bounding box, decalSize, the placement cube and
# decalMaterial.maps[0] (the logo texture in RAYWHITE).
type Scene is Data:
  Scene{model: J.Model, bounds: J.BoundingBox, size: F32, cube: J.Model, paint: J.MaterialMap}

# valid: everything loaded and no refusal so far. show is showModel, decals
# decalModels and hit the closest collision of the mouse ray this frame.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, rng: J.Random.State, scene: Scene, textures: List<J.Texture>, show: Bool, decals: +List<J.Model>, hit: J.RayCollision}

def map.first(maps: +List<J.MaterialMap>) -> J.MaterialMap:
  match maps:
    case Nil{}: J.MaterialMap.none()
    case Con{+map, _}: map

def material.first(materials: +List<J.Material>) -> J.Material:
  match materials:
    case Nil{}: J.Material.load_default()
    case Con{+material, _}: material

def material.mapped(+material: J.Material, +map: J.MaterialMap) -> J.Material:
  J.Material{+maps, +params} = material
  J.Material{Con{map, List.drop(&2, J.MaterialMap, maps, 1n)}, params}

# material.maps[0].
def material.map(+material: J.Material) -> J.MaterialMap:
  J.Material{+maps, _} = material
  map.first(maps)

# model.materials[0].maps[0].
def map.of(+model: J.Model) -> J.MaterialMap:
  J.Model{_, _, +materials, _} = model
  material.map(material.first(materials))

# model.materials[0].maps[0] = map.
def mapped(+model: J.Model, +map: J.MaterialMap) -> J.Model:
  J.Model{+transform, +meshes, +materials, +mesh_material} = model
  J.Model{transform, meshes, Con{material.mapped(material.first(materials), map), List.drop(&2, J.Material, materials, 1n)}, mesh_material}

def absolute(+x: F32) -> F32:
  Bool.pick(F32, (x < 0.0 : F32), F32.neg(x), x)

def points(values: +List<F32>) -> +List<M.Vector3>:
  match values:
    case Con{+x, Con{+y, Con{+z, rest}}}: Con{M.Vector3{x, y, z}, points(rest)}
    case _: Nil{}

def kept(keep: Bool, +tri: Tri, +rest: +List<Tri>) -> +List<Tri>:
  match keep:
    case True{}: Con{tri, rest}
    case False{}: rest

# (fabsf(v.x) < decalSize) || (fabsf(v.y) <= decalSize) || (fabsf(v.z) <= decalSize).
def near(+v: M.Vector3, +size: F32) -> Bool:
  M.Vector3{+x, +y, +z} = v
  (absolute(x) < size : F32) || (absolute(y) <= size : F32) || (absolute(z) <= size : F32)

# First pass: the triangles in projection space with a vertex inside the decal box.
def gathered(list: +List<M.Vector3>, +projection: M.Matrix, +size: F32) -> +List<Tri>:
  match list:
    case Con{+p0, Con{+p1, Con{+p2, rest}}}: kept(near(M.Vector3.transform(p0, projection), size) || near(M.Vector3.transform(p1, projection), size) || near(M.Vector3.transform(p2, projection), size),
      Tri{M.Vector3.transform(p0, projection), M.Vector3.transform(p1, projection), M.Vector3.transform(p2, projection)}, gathered(rest, projection, size))
    case _: Nil{}

def mesh.points(vertices: Maybe<&2, +List<F32>>, indices: Maybe<&2, +List<U32>>) -> +List<M.Vector3>:
  match vertices indices:
    case Some{+values} None{}: points(values)
    case _ _: Nil{}

# The meshes' triangles, in order.
def gathered.all(meshes: +List<J.Mesh>, +projection: M.Matrix, +size: F32) -> +List<Tri>:
  match meshes:
    case Nil{}: Nil{}
    case Con{J.Mesh{_, _, vertices, _, _, _, _, _, indices}, rest}: List.append(&2, Tri, gathered(mesh.points(vertices, indices), projection, size), gathered.all(rest, projection, size))

# ClipSegment(v0, v1, p, s).
def segment(+v0: M.Vector3, +v1: M.Vector3, +plane: M.Vector3, +s: F32) -> M.Vector3:
  +d0 = (M.Vector3.dot_product(v0, plane) - s : F32)
  +d1 = (M.Vector3.dot_product(v1, plane) - s : F32)
  M.Vector3.lerp(v0, v1, (d0 / (d0 - d1) : F32))

# A triangle against a plane. kind 0: inside; 1, 2, 3: that vertex alone outside (two triangles); 4, 5, 6: that
# vertex alone inside (one triangle); 7: outside.
def clipped(kind: U32, +a: M.Vector3, +b: M.Vector3, +c: M.Vector3, +plane: M.Vector3, +s: F32, +rest: +List<Tri>) -> +List<Tri>:
  match kind:
    case 0: Con{Tri{a, b, c}, rest}
    case 1: Con{Tri{b, c, segment(a, b, plane, s)}, Con{Tri{segment(a, c, plane, s), segment(a, b, plane, s), c}, rest}}
    case 2: Con{Tri{segment(b, a, plane, s), c, a}, Con{Tri{c, segment(b, a, plane, s), segment(b, c, plane, s)}, rest}}
    case 3: Con{Tri{a, b, segment(c, a, plane, s)}, Con{Tri{segment(c, b, plane, s), segment(c, a, plane, s), b}, rest}}
    case 4: Con{Tri{a, segment(a, b, plane, s), segment(a, c, plane, s)}, rest}
    case 5: Con{Tri{b, segment(b, c, plane, s), segment(b, a, plane, s)}, rest}
    case 6: Con{Tri{c, segment(c, a, plane, s), segment(c, b, plane, s)}, rest}
    case _: rest

def clip.kind(+o1: Bool, +o2: Bool, +o3: Bool) -> U32:
  Bool.pick(U32, o1, Bool.pick(U32, o2, Bool.pick(U32, o3, 7, 6), Bool.pick(U32, o3, 5, 1)), Bool.pick(U32, o2, Bool.pick(U32, o3, 4, 2), Bool.pick(U32, o3, 3, 0)))

def clip.one(+tri: Tri, +plane: M.Vector3, +s: F32, +rest: +List<Tri>) -> +List<Tri>:
  Tri{+a, +b, +c} = tri
  clipped(clip.kind(((M.Vector3.dot_product(a, plane) - s) > 0.0 : F32), ((M.Vector3.dot_product(b, plane) - s) > 0.0 : F32), ((M.Vector3.dot_product(c, plane) - s) > 0.0 : F32)), a, b, c, plane, s, rest)

# The builder's triangles against one plane, s = 0.5f*decalSize.
def clip(list: +List<Tri>, +plane: M.Vector3, +s: F32) -> +List<Tri>:
  match list:
    case Nil{}: Nil{}
    case Con{+tri, rest}: clip.one(tri, plane, s, clip(rest, plane, s))

# The six planes of the box, in the example's order.
def clip.all(+list: +List<Tri>, +s: F32) -> +List<Tri>:
  clip(clip(clip(clip(clip(clip(list, M.Vector3{1.0, 0.0, 0.0}, s), M.Vector3{F32.neg(1.0), 0.0, 0.0}, s), M.Vector3{0.0, 1.0, 0.0}, s), M.Vector3{0.0, F32.neg(1.0), 0.0}, s), M.Vector3{0.0, 0.0, 1.0}, s),
    M.Vector3{0.0, 0.0, F32.neg(1.0)}, s)

def corners(list: +List<Tri>) -> +List<M.Vector3>:
  match list:
    case Nil{}: Nil{}
    case Con{Tri{+a, +b, +c}, rest}: Con{a, Con{b, Con{c, corners(rest)}}}

# uvs[i] = (x/decalSize + 0.5f, y/decalSize + 0.5f).
def uvs(list: +List<M.Vector3>, +size: F32) -> +List<F32>:
  match list:
    case Nil{}: Nil{}
    case Con{M.Vector3{+x, +y, _}, rest}: Con{(x / size + 0.5 : F32), Con{(y / size + 0.5 : F32), uvs(rest, size)}}

def flat(+v: M.Vector3, +rest: +List<F32>) -> +List<F32>:
  M.Vector3{+x, +y, +z} = v
  Con{x, Con{y, Con{z, rest}}}

# vertices[i].z -= decalOffset; vertices[i] = Vector3Transform(vertices[i], invProj).
def placed(list: +List<M.Vector3>, +inverse: M.Matrix, +offset: F32) -> +List<F32>:
  match list:
    case Nil{}: Nil{}
    case Con{M.Vector3{+x, +y, +z}, rest}: flat(M.Vector3.transform(M.Vector3{x, y, (z - offset : F32)}, inverse), placed(rest, inverse, offset))

def count(list: +List<M.Vector3>, +n: U32) -> U32:
  match list:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

# BuildMesh: the vertices and their texture coordinates; UploadMesh(&outMesh, false).
def decal.built(+list: +List<M.Vector3>, +inverse: M.Matrix, +size: F32, +offset: F32) -> J.Mesh:
  J.Mesh.upload(J.Mesh{count(list, 0), (count(list, 0) / 3 : U32), Some{placed(list, inverse, offset)}, Some{uvs(list, size)}, None{}, None{}, None{}, None{}, None{}}, False{})

# GenMeshDecal(model, projection, decalSize, decalOffset): a mesh without vertices when nothing is left.
def decal(+model: J.Model, +projection: M.Matrix, +size: F32, +offset: F32) -> J.Mesh:
  J.Model{_, +meshes, _, _} = model
  decal.built(corners(clip.all(gathered.all(meshes, projection, size), (0.5 * size : F32))), M.Matrix.invert(projection), size, offset)

def vertices.of(+mesh: J.Mesh) -> U32:
  J.Mesh{total, _, _, _, _, _, _, _, _} = mesh
  total

def triangles.of(+mesh: J.Mesh) -> U32:
  J.Mesh{_, total, _, _, _, _, _, _, _} = mesh
  total

def length(list: +List<J.Model>, +n: U32) -> U32:
  match list:
    case Nil{}: n
    case Con{_, rest}: length(rest, (n + 1 : U32))

def mesh.first(meshes: +List<J.Mesh>) -> J.Mesh:
  match meshes:
    case Nil{}: J.Mesh.empty()
    case Con{+mesh, _}: mesh

def model.mesh(+model: J.Model) -> J.Mesh:
  J.Model{_, +meshes, _, _} = model
  mesh.first(meshes)

# splat = MatrixLookAt(collision.point, collision.point + collision.normal, (0, 1, 0)).
def splat(+hit: J.RayCollision) -> M.Matrix:
  J.RayCollision{_, _, +point, +normal} = hit
  M.Matrix.look_at(point, M.Vector3.add(point, M.Vector3.scale(normal, 1.0)), M.Vector3{0.0, 1.0, 0.0})

# decalModels[decalCount++] = LoadModelFromMesh(decalMesh) with decalMaterial.maps[0], when the mesh has vertices.
def decal.kept(some: Bool, +mesh: J.Mesh, +decals: +List<J.Model>, +paint: J.MaterialMap) -> +List<J.Model>:
  match some:
    case False{}: decals
    case True{}: List.append(&2, J.Model, decals, [mapped(J.Model.from_mesh(mesh), paint)])

def decal.added(+mesh: J.Mesh, +decals: +List<J.Model>, +paint: J.MaterialMap) -> +List<J.Model>:
  decal.kept((vertices.of(mesh) > 0 : U32), mesh, decals, paint)

# A decal at the hit, turned by MatrixRotateZ(DEG2RAD*((float)GetRandomValue(-180, 180))).
def update.splat(+libm: M.Libm, +camera: J.Camera3D, +scene: Scene, textures: List<J.Texture>, +show: Bool, +decals: +List<J.Model>, +hit: J.RayCollision, r: J.Random.State & F32) -> State:
  Scene{+model, _, +size, _, +paint} = scene
  (rng, +degrees) = r
  State{True{}, Some{camera}, rng, scene, textures, show, decal.added(decal(model, M.Matrix.multiply(splat(hit), M.Matrix.rotate_z_for(libm, (M.Math.DEG2RAD() * degrees : F32))), size, 0.01), decals, paint), hit}

# if (collision.hit && IsMouseButtonPressed(MOUSE_BUTTON_LEFT) && (decalCount < MAX_DECALS)).
def update.clicked(click: Bool, +libm: M.Libm, +camera: J.Camera3D, rng: J.Random.State, +scene: Scene, textures: List<J.Texture>, +show: Bool, +decals: +List<J.Model>, +hit: J.RayCollision) -> State:
  match click:
    case False{}: State{True{}, Some{camera}, rng, scene, textures, show, decals, hit}
    case True{}: update.splat(libm, camera, scene, textures, show, decals, hit, J.Random.value(rng, F32.neg(180.0), 180.0))

def float(+bits: U32) -> F32:
  U32{b} = bits
  F32{b}

# collision.distance = FLT_MAX; collision.hit = false.
def miss() -> J.RayCollision:
  J.RayCollision{False{}, float(2139095039), M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 0.0, 0.0}}

def closer(+best: J.RayCollision, +found: J.RayCollision) -> J.RayCollision:
  J.RayCollision{+hit, +distance, _, _} = best
  J.RayCollision{+other, +reach, _, _} = found
  Bool.pick(J.RayCollision, other && (Bool.not(hit) || (distance > reach : F32)), found, best)

def struck(+found: J.RayCollision) -> Bool:
  J.RayCollision{hit, _, _, _} = found
  hit

# The meshes after the one whose collision is `found` (None: refused): each hit closer than the best one becomes
# it, and after the loop the last mesh's hit, if any, is the collision.
def meshes.hit(rest: +List<J.Mesh>, +ray: J.Ray, +transform: M.Matrix, +best: J.RayCollision, found: Maybe<J.RayCollision>) -> Maybe<J.RayCollision>:
  match rest found:
    case _ None{}: None{}
    case Nil{} Some{+f}: Some{Bool.pick(J.RayCollision, struck(f), f, best)}
    case Con{+mesh, more} Some{+f}: meshes.hit(more, ray, transform, closer(best, f), J.Collision.ray_mesh_for(M.Uncontracted{}, ray, mesh, transform))

def meshes.first(meshes: +List<J.Mesh>, +ray: J.Ray, +transform: M.Matrix) -> Maybe<J.RayCollision>:
  match meshes:
    case Nil{}: Some{miss()}
    case Con{+mesh, rest}: meshes.hit(rest, ray, transform, miss(), J.Collision.ray_mesh_for(M.Uncontracted{}, ray, mesh, transform))

# The model's meshes when the ray hits the bounding box and decals are left to make.
def update.boxed(+ray: J.Ray, +model: J.Model, inside: Bool) -> Maybe<J.RayCollision>:
  J.Model{+transform, +meshes, _, _} = model
  match inside:
    case False{}: Some{miss()}
    case True{}: meshes.first(meshes, ray, transform)

def scene.model(+scene: Scene) -> J.Model:
  Scene{model, _, _, _, _} = scene
  model

def scene.bounds(+scene: Scene) -> J.BoundingBox:
  Scene{_, bounds, _, _, _} = scene
  bounds

def update.found(found: Maybe<J.RayCollision>, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D, rng: J.Random.State, +scene: Scene, textures: List<J.Texture>, +show: Bool, +decals: +List<J.Model>) -> State:
  match found:
    case None{}: State{False{}, Some{camera}, rng, scene, textures, show, decals, miss()}
    case Some{+hit}: update.clicked(struck(hit) && J.Input.is_mouse_button_pressed(core, 0) && (length(decals, 0) < 256 : U32), libm, camera, rng, scene, textures, show, decals, hit)

# boxHitInfo = GetRayCollisionBox(ray, modelBBox).
def update.box(box: Maybe<J.RayCollision>, +ray: J.Ray, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D, rng: J.Random.State, +scene: Scene, textures: List<J.Texture>, +show: Bool,
    +decals: +List<J.Model>) -> State:
  match box:
    case None{}: State{False{}, Some{camera}, rng, scene, textures, show, decals, miss()}
    case Some{+b}: update.found(update.boxed(ray, scene.model(scene), struck(b) && (length(decals, 0) < 256 : U32)), libm, core, camera, rng, scene, textures, show, decals)

# ray = GetScreenToWorldRay(GetMousePosition(), camera).
def update.ray(ray: Maybe<J.Ray>, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D, rng: J.Random.State, +scene: Scene, textures: List<J.Texture>, +show: Bool, +decals: +List<J.Model>) -> State:
  match ray:
    case None{}: State{False{}, Some{camera}, rng, scene, textures, show, decals, miss()}
    case Some{+r}: update.box(J.Collision.ray_box_for(M.Uncontracted{}, libm, r, scene.bounds(scene)), r, libm, core, camera, rng, scene, textures, show, decals)

def update.moved(moved: Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, rng: J.Random.State, +scene: Scene, textures: List<J.Texture>, +show: Bool, +decals: +List<J.Model>) -> State:
  match moved:
    case None{}: State{False{}, None{}, rng, scene, textures, show, decals, miss()}
    case Some{+c}: update.ray(J.Camera.screen_to_world_ray_for(M.Uncontracted{}, libm, J.Input.get_mouse_position(core), c, core), libm, core, c, rng, scene, textures, show, decals)

# if (IsMouseButtonDown(MOUSE_BUTTON_RIGHT)) UpdateCamera(&camera, CAMERA_THIRD_PERSON).
def update.camera(held: Bool, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D) -> Maybe<J.Camera3D>:
  match held:
    case False{}: Some{camera}
    case True{}: J.Camera.update_for(M.Uncontracted{}, libm, core, camera, J.CameraMode.CAMERA_THIRD_PERSON())

def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, rng: J.Random.State, +scene: Scene, textures: List<J.Texture>, +show: Bool, +decals: +List<J.Model>, +hit: J.RayCollision) -> State:
  match valid camera:
    case True{} Some{+c}: update.moved(update.camera(J.Input.is_mouse_button_down(core, 1), libm, core, c), libm, core, rng, scene, textures, show, decals)
    case _ None{}: State{False{}, None{}, rng, scene, textures, show, decals, hit}
    case False{} Some{+c}: State{False{}, Some{c}, rng, scene, textures, show, decals, hit}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, rng, +scene, textures, +show, +decals, +hit} = state
  (core, update.live(valid, camera, libm, core, rng, scene, textures, show, decals, hit))

def number(text: Maybe<String>, frame: J.Frame, +x: F32, +y: F32) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, y, 10.0, J.Color.LIME())

# A row of the table: its label at x0 and the two counts at x1 and x2.
def row(frame: J.Frame, label: Maybe<String>, +y: F32, +vertices: U32, +triangles: U32) -> J.Frame:
  number(J.Text.format("%d", [J.TextInt{triangles}]), number(J.Text.format("%d", [J.TextInt{vertices}]), number(label, frame, 500.0, y), 600.0, y), 700.0, y)

def rows.one(kind: U32, +i: U32, +y: F32, +model: J.Model, frame: J.Frame) -> J.Frame:
  match kind:
    case 0: row(frame, J.Text.format("Decal #%d", [J.TextInt{(i + 1 : U32)}]), y, vertices.of(model.mesh(model)), triangles.of(model.mesh(model)))
    case 1: J.Draw.text(frame, "...", 500.0, y, 10.0, J.Color.LIME())
    case _: frame

# The decals' rows: the first twenty, then "..." once; the totals go on counting. The last row is TOTAL.
def rows(list: +List<J.Model>, +i: U32, +y: F32, +vertices: U32, +triangles: U32, frame: J.Frame) -> J.Frame:
  match list:
    case Nil{}: row(frame, Some{"TOTAL"}, y, vertices, triangles)
    case Con{+model, rest}: rows(rest, (i + 1 : U32), Bool.pick(F32, (i <= 20 : U32), (y + 15.0 : F32), y), (vertices + vertices.of(model.mesh(model)) : U32),
      (triangles + triangles.of(model.mesh(model)) : U32), rows.one(Bool.pick(U32, (i < 20 : U32), 0, Bool.pick(U32, U32.is_eq(i, 20), 1, 2)), i, y, model, frame))

def totals(meshes: +List<J.Mesh>, +vertices: U32, +triangles: U32) -> U32 & U32:
  match meshes:
    case Nil{}: (vertices, triangles)
    case Con{+mesh, rest}: totals(rest, (vertices + vertices.of(mesh) : U32), (triangles + triangles.of(mesh) : U32))

def table.counted(counts: U32 & U32, +decals: +List<J.Model>, frame: J.Frame) -> J.Frame:
  (+vertices, +triangles) = counts
  rows(decals, 0, 40.0, vertices, triangles, row(frame, Some{"Main model"}, 25.0, vertices, triangles))

# The table: its header, the main model, the decals and the total.
def table(+model: J.Model, +decals: +List<J.Model>, frame: J.Frame) -> J.Frame:
  J.Model{_, +meshes, _, _} = model
  table.counted(totals(meshes, 0, 0), decals, J.Draw.text(J.Draw.text(frame, "Vertices", 600.0, 10.0, 10.0, J.Color.LIME()), "Triangles", 700.0, 10.0, 10.0, J.Color.LIME()))

# DrawModel(model, (0, 0, 0), 1.0f, tint).
def shown(+libm: M.Libm, +model: J.Model, +tint: U32, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  (frame, textures) = r
  J.Draw.model_ex_for(libm, frame, textures, model, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 0.0, M.Vector3{1.0, 1.0, 1.0}, tint)

def shown.if(show: Bool, +libm: M.Libm, +model: J.Model, +tint: U32, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  match show:
    case False{}: r
    case True{}: shown(libm, model, tint, r)

def shown.all(list: +List<J.Model>, +libm: M.Libm, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  match list:
    case Nil{}: r
    case Con{+model, rest}: shown.all(rest, libm, shown(libm, model, J.Color.WHITE(), r))

# placementCube.transform = MatrixInvert(splat).
def cube.at(+cube: J.Model, +hit: J.RayCollision) -> J.Model:
  J.Model{_, +meshes, +materials, +mesh_material} = cube
  J.Model{M.Matrix.invert(splat(hit)), meshes, materials, mesh_material}

# CheckCollisionPointRec(mouse, (x, y, 100, 60)).
def over(+mouse: M.Vector2, +x: F32, +y: F32) -> Bool:
  M.Vector2{+mx, +my} = mouse
  (mx >= x : F32) && (mx < (x + 100.0) : F32) && (my >= y : F32) && (my < (y + 60.0) : F32)

# (int)value for a float within int.
def whole(+value: F32) -> F32:
  Bool.pick(F32, (value < 0.0 : F32), F32.neg(U32.to_f32(F32.to_u32(F32.neg(value)))), U32.to_f32(F32.to_u32(value)))

# GuiButton(rec, label): whether it is pressed; the frame with the button.
def button(+core: J.Core, frame: J.Frame, +x: F32, +y: F32, +label: String, width: Maybe<U32>) -> J.Frame & Bool:
  match width:
    case None{}: (J.Frame.refuse(frame), False{})
    case Some{+w}: (J.Draw.text(J.Draw.rectangle_lines_ex(J.Draw.rectangle_rec(frame, J.Rectangle{x, y, 100.0, 60.0}, Bool.pick(U32, over(J.Input.get_mouse_position(core), x, y), J.Color.LIGHTGRAY(), J.Color.GRAY())),
      J.Rectangle{x, y, 100.0, 60.0}, 2.0, J.Color.DARKGRAY()), label, whole(((x + 100.0 * 0.5) - U32.to_f32(w) * 0.5 : F32)), whole(((y + 60.0 * 0.5) - 10.0 * 0.5 : F32)), 10.0, J.Color.DARKGRAY()),
      over(J.Input.get_mouse_position(core), x, y) && J.Input.is_mouse_button_pressed(core, 0))

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# "Clear Decals": the decal models are unloaded; DrawFPS(10, 10).
def draw.cleared(+core: J.Core, +camera: J.Camera3D, rng: J.Random.State, +scene: Scene, textures: List<J.Texture>, +show: Bool, +decals: +List<J.Model>, +hit: J.RayCollision, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, clear) = r
  match clear:
    case True{}: draw.fps(State{True{}, Some{camera}, rng, scene, textures, show, Nil{}, hit}, frame, J.Core.get_fps(core, J.Core.get_time(core)), core)
    case False{}: draw.fps(State{True{}, Some{camera}, rng, scene, textures, show, decals, hit}, frame, J.Core.get_fps(core, J.Core.get_time(core)), core)

# "Hide Model" or "Show Model" toggles showModel; then the second button.
def draw.toggled(+core: J.Core, +camera: J.Camera3D, rng: J.Random.State, +scene: Scene, textures: List<J.Texture>, +show: Bool, +decals: +List<J.Model>, +hit: J.RayCollision, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +toggle) = r
  draw.cleared(core, camera, rng, scene, textures, Bool.pick(Bool, toggle, Bool.not(show), show), decals, hit, button(core, frame, (10.0 + 110.0 : F32), (450.0 - 100.0 : F32), "Clear Decals",
    J.Font.measure_text("Clear Decals", 10.0)))

def show.label(show: Bool) -> String:
  match show:
    case True{}: "Hide Model"
    case False{}: "Show Model"

# DrawGrid(10, 10.0f); EndMode3D(); the table; the texts; the buttons.
def draw.scene(+core: J.Core, +camera: J.Camera3D, rng: J.Random.State, +scene: Scene, +show: Bool, +decals: +List<J.Model>, +hit: J.RayCollision, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  Scene{+model, _, _, _, _} = scene
  (frame, textures) = r
  f1 = table(model, decals, J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 10.0)))
  f2 = J.Draw.text(J.Draw.text(f1, "Hold RMB to move camera", 10.0, 430.0, 10.0, J.Color.GRAY()), "(c) Character model and texture from kenney.nl", 540.0, 430.0, 10.0, J.Color.GRAY())
  draw.toggled(core, camera, rng, scene, textures, show, decals, hit, button(core, f2, 10.0, (450.0 - 1000.0 : F32), show.label(show), J.Font.measure_text(show.label(show), 10.0)))

# BeginMode3D(camera); the model when shown, the decals and the placement cube at the hit in Fade(WHITE, 0.5f).
def draw.live(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, rng: J.Random.State, +scene: Scene, textures: List<J.Texture>, +show: Bool, +decals: +List<J.Model>, +hit: J.RayCollision, frame: J.Frame) -> J.Core & (State & J.Frame):
  Scene{+model, _, _, +cube, _} = scene
  draw.scene(core, camera, rng, scene, show, decals, hit, shown.if(struck(hit), libm, cube.at(cube, hit), J.Color.with_alpha(J.Color.WHITE(), 0.5),
    shown.all(decals, libm, shown.if(show, libm, model, J.Color.WHITE(), (J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera), textures)))))

def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, rng: J.Random.State, +scene: Scene, textures: List<J.Texture>, +show: Bool, +decals: +List<J.Model>, +hit: J.RayCollision,
    frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.live(libm, core, c, rng, scene, textures, show, decals, hit, frame)
    case _ None{}: (core, (State{False{}, None{}, rng, scene, textures, show, decals, hit}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, rng, scene, textures, show, decals, hit}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, rng, +scene, textures, +show, +decals, +hit} = state
  draw.at(valid, camera, libm, core, rng, scene, textures, show, decals, hit, frame)

# The main loop's body; libm is the profile of UpdateCamera's and MatrixRotateZ's sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def empty() -> J.BoundingBox:
  J.BoundingBox{M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 0.0, 0.0}}

def failed(+seed: U32, +core: J.Core, frame: J.Frame, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{False{}, None{}, J.Random.seed(seed), Scene{J.Model.empty(), empty(), 0.0, J.Model.empty(), J.MaterialMap.none()}, textures, True{}, Nil{}, miss()}))

# fminf of two numbers.
def least(+a: F32, +b: F32) -> F32:
  Bool.pick(F32, (b < a : F32), b, a)

# modelSize = fminf(fminf(fabsf(max.x - min.x), fabsf(max.y - min.y)), fabsf(max.z - min.z)).
def extent(+bounds: J.BoundingBox) -> F32:
  J.BoundingBox{+low, +high} = bounds
  M.Vector3{+ax, +ay, +az} = low
  M.Vector3{+bx, +by, +bz} = high
  least(least(absolute((bx - ax : F32)), absolute((by - ay : F32))), absolute((bz - az : F32)))

# camera.target = Vector3Lerp(min, max, 0.5f); camera.position = (0, max.y*1.2f, modelSize*3.0f); up (0, 1.6, 0).
def start(+bounds: J.BoundingBox) -> J.Camera3D:
  J.BoundingBox{+low, +high} = bounds
  M.Vector3{_, +top, _} = high
  J.Camera3D{M.Vector3{0.0, (top * 1.2 : F32), (extent(bounds) * 3.0 : F32)}, M.Vector3.lerp(low, high, 0.5), M.Vector3{0.0, 1.6, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# The placement cube (LIME) and decalMaterial (the logo, RAYWHITE); SetTargetFPS(60).
def setup.done(+seed: U32, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, +bounds: J.BoundingBox, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  +size = (extent(bounds) * 0.25 : F32)
  +cube = mapped(J.Model.from_mesh(J.Mesh.gen_cube(size, size, size)), J.MaterialMap.with_color(map.of(J.Model.from_mesh(J.Mesh.gen_cube(size, size, size))), J.Color.LIME()))
  (J.Core.set_target_fps(core, 60), (frame, State{True{}, Some{start(bounds)}, J.Random.seed(seed), Scene{model, bounds, size, cube,
    J.MaterialMap.with_color(J.MaterialMap.with_texture(material.map(J.Material.load_default()), info), J.Color.RAYWHITE())}, List.append(&1, J.Texture, textures, [J.Texture.set_filter(texture, 1)]), True{},
    Nil{}, miss()}))

# decalTexture = LoadTextureFromImage(decalImage); SetTextureFilter(decalTexture, TEXTURE_FILTER_BILINEAR).
def setup.logo(+seed: U32, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +bounds: J.BoundingBox, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: failed(seed, core, frame, textures)
    case Some{t}: setup.done(seed, core, frame, model, textures, bounds, J.Texture.info(t))

# ImageResizeNN(&decalImage, decalImage.width/4, decalImage.height/4).
def resized(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>, frame: J.Frame) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# decalImage = LoadImage("resources/raylib_logo.png"), a quarter of its size.
def logo.image(image: J.Surface, frame: J.Frame) -> J.Frame & Maybe<J.Texture>:
  J.Surface{+w, +h, format, pixels} = image
  resized(J.Surface.resize_nn(J.Surface{w, h, format, pixels}, (w / 4 : U32), (h / 4 : U32)), frame)

def logo(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: logo.image(image, frame)

# modelBBox = GetMeshBoundingBox(model.meshes[0]).
def setup.bounded(bounds: Maybe<J.BoundingBox>, +seed: U32, +dir: String, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  match bounds:
    case None{}: IO.pure(J.Core & (J.Frame & State), failed(seed, core, frame, textures))
    case Some{+b}: IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/raylib_logo.png"),
      result => IO.pure(J.Core & (J.Frame & State), setup.logo(seed, core, model, textures, b, logo(frame, result))))

# SetTextureFilter(modelTexture, TEXTURE_FILTER_BILINEAR); model.materials[0].maps[MATERIAL_MAP_DIFFUSE].texture = modelTexture.
def setup.skin(+libm: M.Libm, +seed: U32, +dir: String, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, r: J.Texture & J.TextureInfo) -> IO(J.Core & (J.Frame & State)):
  (skin, +info) = r
  setup.bounded(J.Mesh.bounding_box_for(libm, model.mesh(model)), seed, dir, core, frame, mapped(model, J.MaterialMap.with_texture(map.of(model), info)),
    List.append(&1, J.Texture, textures, [J.Texture.set_filter(skin, 1)]))

def setup.textured(+libm: M.Libm, +seed: U32, +dir: String, +core: J.Core, +model: J.Model, textures: List<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, texture) = r
  match texture:
    case None{}: IO.pure(J.Core & (J.Frame & State), failed(seed, core, frame, textures))
    case Some{t}: setup.skin(libm, seed, dir, core, frame, model, textures, J.Texture.info(t))

# modelTexture = LoadTexture("resources/models/obj/character_diffuse.png").
def setup.model(+libm: M.Libm, +seed: U32, +dir: String, +core: J.Core, frame: J.Frame, loaded: J.LoadedModel) -> IO(J.Core & (J.Frame & State)):
  J.LoadedModel{+model, textures} = loaded
  IO.bind(J.Frame & Maybe<J.Texture>, J.Core & (J.Frame & State), J.Texture.load(frame, dir ++ "resources/models/obj/character_diffuse.png"), r => setup.textured(libm, seed, dir, core, model, textures, r))

def setup.loaded(+libm: M.Libm, +seed: U32, +dir: String, +core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), failed(seed, core, frame, Nil{}))
    case Done{loaded}: setup.model(libm, seed, dir, core, frame, loaded)

# After SetConfigFlags(FLAG_MSAA_4X_HINT), InitWindow(800, 450) and SetRandomSeed(seed): model = LoadModel("resources/models/obj/character.obj") and the rest.
def setup(+libm: M.Libm, +seed: U32, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ "resources/models/obj/character.obj"), r => setup.loaded(libm, seed, dir, core, r))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, 32, "raylib [models] example - decals", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, 0, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
