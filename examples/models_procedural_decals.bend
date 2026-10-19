# raylib [models] example - procedural decals, ported to Jonlib.
# Adapted from raylib 6.2 examples/models/models_procedural_decals.c
# (zlib/libpng, Copyright (c) 2025 PanicTitan (@PanicTitan)); see
# LICENSES/raylib.txt.
#
# A generated torus (GenMeshTorus) with a checked texture (GenImageChecked)
# on which a click splats a decal: the model's triangles, in the space of a
# box looking along the surface normal (MatrixLookAt) and turned by a random
# angle (GetRandomValue, MatrixRotateZ), kept by the example's loose
# prefilter and clipped against the box's six planes, then textured with a
# bullseye drawn with ImageDrawCircle (the example's GenMeshDecal, its mesh
# builders as lists; its branch for indexed meshes too, though GenMeshTorus
# makes none). The mouse ray (GetScreenToWorldRay) is tested against the
# mesh's bounding box, then its triangles (GetRayCollisionMesh); a
# translucent cube shows where the next decal would go; the table counts
# the vertices and triangles; RMB turns the camera (CAMERA_THIRD_PERSON);
# two raygui buttons (Jongui) hide the model and clear the decals. The torus
# needs the glibc profile's sinf/cosf and qsort weld (docs/MODELS.md), the
# perspective its binary64 tan (docs/PERSPECTIVE.md); UpdateCamera's and
# MatrixRotateZ's sinf/cosf follow the profile (docs/SINCOSF.md). raylib
# seeds the generator from time(NULL) in InitWindow; here the seed is a
# setup argument. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# A triangle of a mesh builder.
type Tri is Data:
  Tri{a: M.Vector3, b: M.Vector3, c: M.Vector3}

# The torus, its mesh's bounding box, decalSize, the placement cube and decalMaterial.maps[0] (the bullseye in RAYWHITE).
type Scene is Data:
  Scene{model: J.Model, bounds: J.BoundingBox, size: F32, cube: J.Model, paint: J.MaterialMap}

# valid: everything made and no refusal so far. show is showModel, decals the decal models and hit the collision of
# the mouse ray this frame.
type View is Data:
  View{valid: Bool, camera: J.Camera3D, gui: G.Gui, scene: Scene, show: Bool, decals: +List<J.Model>, hit: J.RayCollision}

# textures: the checked texture and the bullseye.
type State is Type:
  State{view: View, rng: J.Random.State, textures: List<J.Texture>}

def Scene.model(+scene: Scene) -> J.Model:
  Scene{+model, _, _, _, _} = scene
  model

def Scene.bounds(+scene: Scene) -> J.BoundingBox:
  Scene{_, +bounds, _, _, _} = scene
  bounds

def Scene.size(+scene: Scene) -> F32:
  Scene{_, _, +size, _, _} = scene
  size

def Scene.cube(+scene: Scene) -> J.Model:
  Scene{_, _, _, +cube, _} = scene
  cube

def Scene.paint(+scene: Scene) -> J.MaterialMap:
  Scene{_, _, _, _, +paint} = scene
  paint

def View.valid(+view: View) -> Bool:
  View{+valid, _, _, _, _, _, _} = view
  valid

def View.camera(+view: View) -> J.Camera3D:
  View{_, +camera, _, _, _, _, _} = view
  camera

def View.gui(+view: View) -> G.Gui:
  View{_, _, +gui, _, _, _, _} = view
  gui

def View.scene(+view: View) -> Scene:
  View{_, _, _, +scene, _, _, _} = view
  scene

def View.show(+view: View) -> Bool:
  View{_, _, _, _, +show, _, _} = view
  show

def View.decals(+view: View) -> +List<J.Model>:
  View{_, _, _, _, _, +decals, _} = view
  decals

def View.hit(+view: View) -> J.RayCollision:
  View{_, _, _, _, _, _, +hit} = view
  hit

def View.invalid(+view: View) -> View:
  View{_, +camera, +gui, +scene, +show, +decals, +hit} = view
  View{False{}, camera, gui, scene, show, decals, hit}

def View.with_camera(+view: View, +camera: J.Camera3D) -> View:
  View{+valid, _, +gui, +scene, +show, +decals, +hit} = view
  View{valid, camera, gui, scene, show, decals, hit}

def View.with_show(+view: View, +show: Bool) -> View:
  View{+valid, +camera, +gui, +scene, _, +decals, +hit} = view
  View{valid, camera, gui, scene, show, decals, hit}

def View.with_decals(+view: View, +decals: +List<J.Model>) -> View:
  View{+valid, +camera, +gui, +scene, +show, _, +hit} = view
  View{valid, camera, gui, scene, show, decals, hit}

def View.with_hit(+view: View, +hit: J.RayCollision) -> View:
  View{+valid, +camera, +gui, +scene, +show, +decals, _} = view
  View{valid, camera, gui, scene, show, decals, hit}

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

def collided(+found: J.RayCollision) -> Bool:
  J.RayCollision{+yes, _, _, _} = found
  yes

# ---------------------------------------------------------------------------
# GenMeshDecal

def points(values: +List<F32>) -> +List<M.Vector3>:
  match values:
    case Con{+x, Con{+y, Con{+z, rest}}}: Con{M.Vector3{x, y, z}, points(rest)}
    case _: Nil{}

def vec3.head(list: +List<M.Vector3>) -> M.Vector3:
  match list:
    case Nil{}: M.Vector3{0.0, 0.0, 0.0}
    case Con{+v, _}: v

# mesh.vertices[3*idx + 0..2].
def vec3.at(+ps: +List<M.Vector3>, +i: U32) -> M.Vector3:
  vec3.head(List.drop(&2, M.Vector3, ps, U32.to_nat(i)))

def kept(keep: Bool, +tri: Tri, +rest: +List<Tri>) -> +List<Tri>:
  match keep:
    case True{}: Con{tri, rest}
    case False{}: rest

# (fabsf(v.x) < decalSize) || (fabsf(v.y) <= decalSize) || (fabsf(v.z) <= decalSize).
def near(+v: M.Vector3, +size: F32) -> Bool:
  M.Vector3{+x, +y, +z} = v
  (absolute(x) < size : F32) || (absolute(y) <= size : F32) || (absolute(z) <= size : F32)

# The triangle's vertices through the projection; it goes to the builder when insideCount > 0.
def gather.tri(+a: M.Vector3, +b: M.Vector3, +c: M.Vector3, +projection: M.Matrix, +size: F32, +acc: +List<Tri>) -> +List<Tri>:
  +pa = M.Vector3.transform(a, projection)
  +pb = M.Vector3.transform(b, projection)
  +pc = M.Vector3.transform(c, projection)
  kept(near(pa, size) || near(pb, size) || near(pc, size), Tri{pa, pb, pc}, acc)

# mesh.indices == NULL: vertices[v] = mesh.vertices[3*3*tri + 3*v + 0..2] (the builder reversed in acc).
def gather.flat(vs: +List<F32>, +projection: M.Matrix, +size: F32, +acc: +List<Tri>) -> +List<Tri>:
  match vs:
    case Con{+x0, Con{+y0, Con{+z0, Con{+x1, Con{+y1, Con{+z1, Con{+x2, Con{+y2, Con{+z2, rest}}}}}}}}}:
      gather.flat(rest, projection, size, gather.tri(M.Vector3{x0, y0, z0}, M.Vector3{x1, y1, z1}, M.Vector3{x2, y2, z2}, projection, size, acc))
    case _: acc

# Indexed: vertices[v] = mesh.vertices[3*idx + 0..2], idx = mesh.indices[3*tri + v].
def gather.indexed(ids: +List<U32>, +ps: +List<M.Vector3>, +projection: M.Matrix, +size: F32, +acc: +List<Tri>) -> +List<Tri>:
  match ids:
    case Con{+i0, Con{+i1, Con{+i2, rest}}}: gather.indexed(rest, ps, projection, size, gather.tri(vec3.at(ps, i0), vec3.at(ps, i1), vec3.at(ps, i2), projection, size, acc))
    case _: acc

def gather.mesh(vertices: Maybe<&2, +List<F32>>, indices: Maybe<&2, +List<U32>>, +projection: M.Matrix, +size: F32, +acc: +List<Tri>) -> +List<Tri>:
  match vertices indices:
    case Some{+vs} None{}: gather.flat(vs, projection, size, acc)
    case Some{+vs} Some{+ids}: gather.indexed(ids, points(vs), projection, size, acc)
    case None{} _: acc

# First pass over the model's meshes, in order (reversed in acc).
def gather.all(meshes: +List<J.Mesh>, +projection: M.Matrix, +size: F32, +acc: +List<Tri>) -> +List<Tri>:
  match meshes:
    case Nil{}: acc
    case Con{J.Mesh{_, _, vertices, _, _, _, _, _, indices}, rest}: gather.all(rest, projection, size, gather.mesh(vertices, indices, projection, size, acc))

# ClipSegment(v0, v1, p, s): Vector3Lerp(v0, v1, d0/(d0 - d1)).
def segment(+v0: M.Vector3, +v1: M.Vector3, +plane: M.Vector3, +s: F32) -> M.Vector3:
  +d0 = (M.Vector3.dot_product(v0, plane) - s : F32)
  +d1 = (M.Vector3.dot_product(v1, plane) - s : F32)
  M.Vector3.lerp(v0, v1, (d0 / (d0 - d1) : F32))

# A triangle against a plane, its output pushed on acc (reversed). kind 0: inside; 1, 2, 3: that vertex alone outside
# (two triangles: case 1 of the switch, the second vertex's branch adding its own pair); 4, 5, 6: that vertex alone
# inside (one triangle); 7: outside.
def clip.push(kind: U32, +a: M.Vector3, +b: M.Vector3, +c: M.Vector3, +plane: M.Vector3, +s: F32, +acc: +List<Tri>) -> +List<Tri>:
  match kind:
    case 0: Con{Tri{a, b, c}, acc}
    case 1: Con{Tri{segment(a, c, plane, s), segment(a, b, plane, s), c}, Con{Tri{b, c, segment(a, b, plane, s)}, acc}}
    case 2: Con{Tri{c, segment(b, a, plane, s), segment(b, c, plane, s)}, Con{Tri{segment(b, a, plane, s), c, a}, acc}}
    case 3: Con{Tri{segment(c, b, plane, s), segment(c, a, plane, s), b}, Con{Tri{a, b, segment(c, a, plane, s)}, acc}}
    case 4: Con{Tri{a, segment(a, b, plane, s), segment(a, c, plane, s)}, acc}
    case 5: Con{Tri{b, segment(b, c, plane, s), segment(b, a, plane, s)}, acc}
    case 6: Con{Tri{c, segment(c, a, plane, s), segment(c, b, plane, s)}, acc}
    case _: acc

def clip.kind(+o1: Bool, +o2: Bool, +o3: Bool) -> U32:
  Bool.pick(U32, o1, Bool.pick(U32, o2, Bool.pick(U32, o3, 7, 6), Bool.pick(U32, o3, 5, 1)), Bool.pick(U32, o2, Bool.pick(U32, o3, 4, 2), Bool.pick(U32, o3, 3, 0)))

# vNOut = (Vector3DotProduct(vertex, plane) - s > 0).
def clip.one(+tri: Tri, +plane: M.Vector3, +s: F32, +acc: +List<Tri>) -> +List<Tri>:
  Tri{+a, +b, +c} = tri
  clip.push(clip.kind(((M.Vector3.dot_product(a, plane) - s) > 0.0 : F32), ((M.Vector3.dot_product(b, plane) - s) > 0.0 : F32), ((M.Vector3.dot_product(c, plane) - s) > 0.0 : F32)), a, b, c, plane, s,
    acc)

# The input builder's triangles against one plane into the output builder, s = 0.5f*decalSize.
def clip.pass(list: +List<Tri>, +plane: M.Vector3, +s: F32, +acc: +List<Tri>) -> +List<Tri>:
  match list:
    case Nil{}: List.reverse(&2, Tri, acc)
    case Con{+tri, rest}: clip.pass(rest, plane, s, clip.one(tri, plane, s, acc))

# The six planes of the box, in the example's order.
def clip.all(+list: +List<Tri>, +s: F32) -> +List<Tri>:
  clip.pass(clip.pass(clip.pass(clip.pass(clip.pass(clip.pass(list, M.Vector3{1.0, 0.0, 0.0}, s, Nil{}), M.Vector3{F32.neg(1.0), 0.0, 0.0}, s, Nil{}), M.Vector3{0.0, 1.0, 0.0}, s, Nil{}),
    M.Vector3{0.0, F32.neg(1.0), 0.0}, s, Nil{}), M.Vector3{0.0, 0.0, 1.0}, s, Nil{}), M.Vector3{0.0, 0.0, F32.neg(1.0)}, s, Nil{})

def corners(list: +List<Tri>) -> +List<M.Vector3>:
  match list:
    case Nil{}: Nil{}
    case Con{Tri{+a, +b, +c}, rest}: Con{a, Con{b, Con{c, corners(rest)}}}

# uvs[i] = (vertices[i].x/decalSize + 0.5f, vertices[i].y/decalSize + 0.5f).
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
  decal.built(corners(clip.all(List.reverse(&2, Tri, gather.all(meshes, projection, size, Nil{})), (0.5 * size : F32))), M.Matrix.invert(projection), size, offset)

# ---------------------------------------------------------------------------
# Update

def first.mesh.of(meshes: +List<J.Mesh>) -> J.Mesh:
  match meshes:
    case Nil{}: J.Mesh.empty()
    case Con{+mesh, _}: mesh

def first.mesh(+model: J.Model) -> J.Mesh:
  J.Model{_, +meshes, _, _} = model
  first.mesh.of(meshes)

def length(list: +List<J.Model>, +n: U32) -> U32:
  match list:
    case Nil{}: n
    case Con{_, rest}: length(rest, (n + 1 : U32))

# splat = MatrixLookAt(collision.point, Vector3Add(collision.point, collision.normal), (0, 1, 0)).
def splat(+found: J.RayCollision) -> M.Matrix:
  J.RayCollision{_, _, +point, +normal} = found
  M.Matrix.look_at(point, M.Vector3.add(point, normal), M.Vector3{0.0, 1.0, 0.0})

# decals[decalCount++] = LoadModelFromMesh(decalMesh) with decalMaterial.maps[0], when it has vertices.
def decal.kept(some: Bool, +mesh: J.Mesh, +decals: +List<J.Model>, +paint: J.MaterialMap) -> +List<J.Model>:
  match some:
    case False{}: decals
    case True{}: List.append(&2, J.Model, decals, [mapped(J.Model.from_mesh(mesh), paint)])

def decal.added(+mesh: J.Mesh, +decals: +List<J.Model>, +paint: J.MaterialMap) -> +List<J.Model>:
  decal.kept((J.Mesh.vertex_count(mesh) > 0 : U32), mesh, decals, paint)

# A decal at the hit, splat turned by MatrixRotateZ(DEG2RAD*(float)GetRandomValue(-180, 180)), decalOffset 0.01f.
def update.splat(+libm: M.Libm, +view: View, textures: List<J.Texture>, r: J.Random.State & F32) -> State:
  (rng, +degrees) = r
  +scene = View.scene(view)
  +projection = M.Matrix.multiply(splat(View.hit(view)), M.Matrix.rotate_z_for(libm, (M.Math.DEG2RAD() * degrees : F32)))
  State{View.with_decals(view, decal.added(decal(Scene.model(scene), projection, Scene.size(scene), 0.01), View.decals(view), Scene.paint(scene))), rng, textures}

# if (collision.hit && IsMouseButtonPressed(MOUSE_BUTTON_LEFT) && (decalCount < MAX_DECALS)).
def update.clicked(click: Bool, +libm: M.Libm, +view: View, rng: J.Random.State, textures: List<J.Texture>) -> State:
  match click:
    case False{}: State{view, rng, textures}
    case True{}: update.splat(libm, view, textures, J.Random.value(rng, F32.neg(180.0), 180.0))

# if (meshHit.hit && (!collision.hit || (meshHit.distance < collision.distance))) collision = meshHit.
def closer(+best: J.RayCollision, +found: J.RayCollision) -> J.RayCollision:
  J.RayCollision{+yes, +distance, _, _} = best
  J.RayCollision{+other, +reach, _, _} = found
  Bool.pick(J.RayCollision, other && (Bool.not(yes) || (reach < distance : F32)), found, best)

# The meshes after the one whose GetRayCollisionMesh is `found` (None: refused).
def scan.hit(rest: +List<J.Mesh>, +ray: J.Ray, +transform: M.Matrix, +best: J.RayCollision, found: Maybe<J.RayCollision>) -> Maybe<J.RayCollision>:
  match rest found:
    case _ None{}: None{}
    case Nil{} Some{+f}: Some{closer(best, f)}
    case Con{+mesh, more} Some{+f}: scan.hit(more, ray, transform, closer(best, f), J.Collision.ray_mesh_for(M.Uncontracted{}, ray, mesh, transform))

# collision = { 0 }, then GetRayCollisionMesh(ray, model.meshes[m], model.transform) for each mesh.
def scan.first(meshes: +List<J.Mesh>, +ray: J.Ray, +transform: M.Matrix) -> Maybe<J.RayCollision>:
  match meshes:
    case Nil{}: Some{J.RayCollision.none()}
    case Con{+mesh, rest}: scan.hit(rest, ray, transform, J.RayCollision.none(), J.Collision.ray_mesh_for(M.Uncontracted{}, ray, mesh, transform))

# if (GetRayCollisionBox(ray, modelBBox).hit && (decalCount < MAX_DECALS)): the meshes; else collision = { 0 }.
def update.meshes(+ray: J.Ray, +model: J.Model, inside: Bool) -> Maybe<J.RayCollision>:
  J.Model{+transform, +meshes, _, _} = model
  match inside:
    case False{}: Some{J.RayCollision.none()}
    case True{}: scan.first(meshes, ray, transform)

def update.found(found: Maybe<J.RayCollision>, +libm: M.Libm, +core: J.Core, +view: View, rng: J.Random.State, textures: List<J.Texture>) -> State:
  match found:
    case None{}: State{View.invalid(View.with_hit(view, J.RayCollision.none())), rng, textures}
    case Some{+h}: update.clicked(collided(h) && J.Input.is_mouse_button_pressed(core, 0) && (length(View.decals(view), 0) < 256 : U32), libm, View.with_hit(view, h), rng, textures)

def update.box(box: Maybe<J.RayCollision>, +ray: J.Ray, +libm: M.Libm, +core: J.Core, +view: View, rng: J.Random.State, textures: List<J.Texture>) -> State:
  match box:
    case None{}: State{View.invalid(View.with_hit(view, J.RayCollision.none())), rng, textures}
    case Some{+b}: update.found(update.meshes(ray, Scene.model(View.scene(view)), collided(b) && (length(View.decals(view), 0) < 256 : U32)), libm, core, view, rng, textures)

# ray = GetScreenToWorldRay(GetMousePosition(), camera).
def update.ray(ray: Maybe<J.Ray>, +libm: M.Libm, +core: J.Core, +view: View, rng: J.Random.State, textures: List<J.Texture>) -> State:
  match ray:
    case None{}: State{View.invalid(View.with_hit(view, J.RayCollision.none())), rng, textures}
    case Some{+r}: update.box(J.Collision.ray_box_for(M.Uncontracted{}, libm, r, Scene.bounds(View.scene(view))), r, libm, core, view, rng, textures)

def update.moved(moved: Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +view: View, rng: J.Random.State, textures: List<J.Texture>) -> State:
  match moved:
    case None{}: State{View.invalid(View.with_hit(view, J.RayCollision.none())), rng, textures}
    case Some{+c}: update.ray(J.Camera.screen_to_world_ray_for(M.Uncontracted{}, libm, J.Input.get_mouse_position(core), c, core), libm, core, View.with_camera(view, c), rng, textures)

# if (IsMouseButtonDown(MOUSE_BUTTON_RIGHT)) UpdateCamera(&camera, CAMERA_THIRD_PERSON).
def update.camera(held: Bool, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D) -> Maybe<J.Camera3D>:
  match held:
    case False{}: Some{camera}
    case True{}: J.Camera.update_for(M.Uncontracted{}, libm, core, camera, J.CameraMode.CAMERA_THIRD_PERSON())

def update.live(valid: Bool, +libm: M.Libm, +core: J.Core, +view: View, rng: J.Random.State, textures: List<J.Texture>) -> State:
  match valid:
    case False{}: State{view, rng, textures}
    case True{}: update.moved(update.camera(J.Input.is_mouse_button_down(core, 1), libm, core, View.camera(view)), libm, core, view, rng, textures)

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+view, rng, textures} = state
  (core, update.live(View.valid(view), libm, core, view, rng, textures))

# ---------------------------------------------------------------------------
# Draw

def number.text(text: Maybe<String>, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, y, 10.0, J.Color.LIME())

def number(+value: U32, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  number.text(J.Text.format("%d", [J.TextInt{value}]), x, y, frame)

def totals(meshes: +List<J.Mesh>, +vertices: U32, +triangles: U32) -> U32 & U32:
  match meshes:
    case Nil{}: (vertices, triangles)
    case Con{+mesh, rest}: totals(rest, (vertices + J.Mesh.vertex_count(mesh) : U32), (triangles + J.Mesh.triangle_count(mesh) : U32))

# totalVertices += decals[i].meshes[0].vertexCount; totalTriangles += decals[i].meshes[0].triangleCount.
def decal.totals(list: +List<J.Model>, +vertices: U32, +triangles: U32) -> U32 & U32:
  match list:
    case Nil{}: (vertices, triangles)
    case Con{+model, rest}: decal.totals(rest, (vertices + J.Mesh.vertex_count(first.mesh(model)) : U32), (triangles + J.Mesh.triangle_count(first.mesh(model)) : U32))

# The table at statX = screenWidth - 280: the header, the base model and the total.
def table.drawn(+bv: U32, +bt: U32, sums: U32 & U32, frame: J.Frame) -> J.Frame:
  (+tv, +tt) = sums
  f1 = J.Draw.text(J.Draw.text(frame, "Vertices", (520.0 + 90.0 : F32), 10.0, 10.0, J.Color.LIME()), "Triangles", (520.0 + 180.0 : F32), 10.0, 10.0, J.Color.LIME())
  f2 = number(bt, (520.0 + 180.0 : F32), 25.0, number(bv, (520.0 + 90.0 : F32), 25.0, J.Draw.text(f1, "Base Model", 520.0, 25.0, 10.0, J.Color.LIME())))
  number(tt, (520.0 + 180.0 : F32), 40.0, number(tv, (520.0 + 90.0 : F32), 40.0, J.Draw.text(f2, "TOTAL", 520.0, 40.0, 10.0, J.Color.LIME())))

def table.base(base: U32 & U32, +decals: +List<J.Model>, frame: J.Frame) -> J.Frame:
  (+bv, +bt) = base
  table.drawn(bv, bt, decal.totals(decals, bv, bt), frame)

def table(+model: J.Model, +decals: +List<J.Model>, frame: J.Frame) -> J.Frame:
  J.Model{_, +meshes, _, _} = model
  table.base(totals(meshes, 0, 0), decals, frame)

# DrawModel(model, Vector3Zero(), 1.0f, tint).
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
def preview.at(+cube: J.Model, +found: J.RayCollision) -> J.Model:
  J.Model{_, +meshes, +materials, +mesh_material} = cube
  J.Model{M.Matrix.invert(splat(found)), meshes, materials, mesh_material}

# showModel = !showModel when the button was pressed.
def differs(a: Bool, +b: Bool) -> Bool:
  match a:
    case True{}: Bool.not(b)
    case False{}: b

def toggle.text(visible: Bool) -> String:
  match visible:
    case True{}: "Hide Model"
    case False{}: "Show Model"

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# "Clear Decals" unloads the decals (decalCount = 0); the help text; DrawFPS(10, 10).
def draw.cleared(+core: J.Core, +view: View, rng: J.Random.State, textures: List<J.Texture>, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +clear) = r
  f1 = J.Draw.text(frame, "Left click: place decal   |   Right drag: orbit camera", 10.0, (450.0 - 25.0 : F32), 10.0, J.Color.DARKGRAY())
  draw.fps(State{Bool.pick(View, clear, View.with_decals(view, Nil{}), view), rng, textures}, f1, J.Core.get_fps(core, J.Core.get_time(core)), core)

# "Hide Model" / "Show Model" toggles showModel; then the "Clear Decals" button.
def draw.toggled(+core: J.Core, +view: View, rng: J.Random.State, textures: List<J.Texture>, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +pressed) = r
  draw.cleared(core, View.with_show(view, differs(pressed, View.show(view))), rng, textures, G.Gui.button(View.gui(view), core, frame, J.Rectangle{120.0, (450.0 - 80.0 : F32), 100.0, 40.0},
    "Clear Decals"))

# DrawGrid(10, 1.0f); EndMode3D(); the table; GuiButton((10, screenHeight - 80.0f, 100, 40), showModel ? "Hide Model" : "Show Model").
def draw.scene(+core: J.Core, +view: View, rng: J.Random.State, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = table(Scene.model(View.scene(view)), View.decals(view), J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0)))
  draw.toggled(core, view, rng, textures, G.Gui.button(View.gui(view), core, f1, J.Rectangle{10.0, (450.0 - 80.0 : F32), 100.0, 40.0}, toggle.text(View.show(view))))

# ClearBackground(RAYWHITE); BeginMode3D(camera); the model when shown, the decals and the placement cube at the hit in
# Fade(WHITE, 0.5f).
def draw.live(+libm: M.Libm, +core: J.Core, +view: View, rng: J.Random.State, textures: List<J.Texture>, frame: J.Frame) -> J.Core & (State & J.Frame):
  +scene = View.scene(view)
  +found = View.hit(view)
  draw.scene(core, view, rng, shown.if(collided(found), libm, preview.at(Scene.cube(scene), found), J.Color.with_alpha(J.Color.WHITE(), 0.5),
    shown.all(View.decals(view), libm, shown.if(View.show(view), libm, Scene.model(scene), J.Color.WHITE(),
    (J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), View.camera(view)), textures)))))

def draw.at(valid: Bool, +libm: M.Libm, +core: J.Core, +view: View, rng: J.Random.State, textures: List<J.Texture>, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid:
    case True{}: draw.live(libm, core, view, rng, textures, frame)
    case False{}: (core, (State{view, rng, textures}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+view, rng, textures} = state
  draw.at(View.valid(view), libm, core, view, rng, textures, frame)

# The main loop's body; libm is the profile of UpdateCamera's and MatrixRotateZ's sinf/cosf, the ray, the box test and
# the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# ---------------------------------------------------------------------------
# Setup

def bbox.zero() -> J.BoundingBox:
  J.BoundingBox{M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 0.0, 0.0}}

# camera.position (0, 2.5, 5), camera.target = Vector3Lerp(modelBBox.min, modelBBox.max, 0.5f), up (0, 1, 0), fovy 45.
def start(+bounds: J.BoundingBox) -> J.Camera3D:
  J.BoundingBox{+low, +high} = bounds
  J.Camera3D{M.Vector3{0.0, 2.5, 5.0}, M.Vector3.lerp(low, high, 0.5), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def failed(+seed: U32, +core: J.Core, frame: J.Frame, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{View{False{}, start(bbox.zero()), G.Gui.new(), Scene{J.Model.empty(), bbox.zero(), 0.0, J.Model.empty(), J.MaterialMap.none()}, True{}, Nil{},
    J.RayCollision.none()}, J.Random.seed(seed), textures}))

# fminf of two numbers.
def least(+a: F32, +b: F32) -> F32:
  Bool.pick(F32, (b < a : F32), b, a)

# modelSize = fminf(fminf(fabsf(max.x - min.x), fabsf(max.y - min.y)), fabsf(max.z - min.z)).
def extent(+bounds: J.BoundingBox) -> F32:
  J.BoundingBox{+low, +high} = bounds
  M.Vector3{+ax, +ay, +az} = low
  M.Vector3{+bx, +by, +bz} = high
  least(least(absolute((bx - ax : F32)), absolute((by - ay : F32))), absolute((bz - az : F32)))

# decalSize = modelSize*0.35f; placementCube = LoadModelFromMesh(GenMeshCube(decalSize, decalSize, decalSize)) in LIME;
# decalMaterial = LoadMaterialDefault() with the bullseye in RAYWHITE; SetTargetFPS(60).
def setup.done(+seed: U32, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, +bounds: J.BoundingBox, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  +size = (extent(bounds) * 0.35 : F32)
  +cube = mapped(J.Model.from_mesh(J.Mesh.gen_cube(size, size, size)), J.MaterialMap.with_color(material.map(J.Material.load_default()), J.Color.LIME()))
  +paint = J.MaterialMap.with_color(J.MaterialMap.with_texture(material.map(J.Material.load_default()), info), J.Color.RAYWHITE())
  (J.Core.set_target_fps(core, 60), (frame, State{View{True{}, start(bounds), G.Gui.new(), Scene{model, bounds, size, cube, paint}, True{}, Nil{}, J.RayCollision.none()}, J.Random.seed(seed),
    List.append(&1, J.Texture, textures, [J.Texture.set_filter(texture, 1)])}))

# decalTexture = LoadTextureFromImage(decalImage); SetTextureFilter(decalTexture, TEXTURE_FILTER_BILINEAR).
def setup.target(+seed: U32, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +bounds: J.BoundingBox, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: failed(seed, core, frame, textures)
    case Some{t}: setup.done(seed, core, frame, model, textures, bounds, J.Texture.info(t))

# ImageDrawCircle(&decalImage, 64, 64, r, color) for (60, RED), (45, WHITE), (30, RED) and (15, YELLOW).
def bullseye(image: J.Surface) -> J.Surface:
  J.Surface.draw_circle(J.Surface.draw_circle(J.Surface.draw_circle(J.Surface.draw_circle(image, 64.0, 64.0, 60, J.Color.RED()), 64.0, 64.0, 45, J.Color.WHITE()), 64.0, 64.0, 30,
    J.Color.RED()), 64.0, 64.0, 15, J.Color.YELLOW())

# decalImage = GenImageColor(128, 128, BLANK) and its bullseye.
def setup.decal(image: Maybe<J.Surface>, +seed: U32, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, +bounds: J.BoundingBox) -> J.Core & (J.Frame & State):
  match image:
    case None{}: failed(seed, core, frame, textures)
    case Some{i}: setup.target(seed, core, model, textures, bounds, J.Texture.load_from_image(frame, bullseye(i)))

# modelBBox = GetMeshBoundingBox(model.meshes[0]).
def setup.bounded(bounds: Maybe<J.BoundingBox>, +seed: U32, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  match bounds:
    case None{}: failed(seed, core, frame, textures)
    case Some{+b}: setup.decal(J.Surface.create(128, 128, J.Color.BLANK()), seed, core, frame, model, textures, b)

# SetTextureFilter(modelTexture, TEXTURE_FILTER_BILINEAR); model.materials[0].maps[MATERIAL_MAP_DIFFUSE].texture = modelTexture.
def setup.skinned(+libm: M.Libm, +seed: U32, +core: J.Core, frame: J.Frame, +model: J.Model, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (skin, +info) = r
  setup.bounded(J.Mesh.bounding_box_for(libm, first.mesh(model)), seed, core, frame, mapped(model, J.MaterialMap.with_texture(map.of(model), info)), [J.Texture.set_filter(skin, 1)])

# modelTexture = LoadTextureFromImage(checkerImage).
def setup.skin(+libm: M.Libm, +seed: U32, +core: J.Core, +model: J.Model, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: failed(seed, core, frame, Nil{})
    case Some{t}: setup.skinned(libm, seed, core, frame, model, J.Texture.info(t))

# checkerImage = GenImageChecked(512, 512, 32, 32, LIGHTGRAY, GRAY).
def setup.checker(image: Maybe<J.Surface>, +libm: M.Libm, +seed: U32, +core: J.Core, frame: J.Frame, +model: J.Model) -> J.Core & (J.Frame & State):
  match image:
    case None{}: failed(seed, core, frame, Nil{})
    case Some{i}: setup.skin(libm, seed, core, model, J.Texture.load_from_image(frame, i))

def setup.torus(mesh: Maybe<J.Mesh>, +libm: M.Libm, +seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  match mesh:
    case None{}: failed(seed, core, frame, Nil{})
    case Some{+m}: setup.checker(J.Surface.create_checked(512, 512, 32, 32, J.Color.LIGHTGRAY(), J.Color.GRAY()), libm, seed, core, frame, J.Model.from_mesh(m))

# After SetConfigFlags(FLAG_MSAA_4X_HINT), InitWindow(800, 450) and SetRandomSeed(seed): model =
# LoadModelFromMesh(GenMeshTorus(0.8f, 1.8f, 32, 64)) and the rest.
def setup(+libm: M.Libm, +seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.torus(J.Mesh.gen_torus_for(M.Uncontracted{}, libm, 0.8, 1.8, 32, 64), libm, seed, core, frame)

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, 32, "raylib [models] example - procedural decals", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, 0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
