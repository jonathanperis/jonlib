# raylib [models] example - mesh uv painting, ported to Jonlib.
# Adapted from raylib 6.2 examples/models/models_mesh_uv_painting.c
# (zlib/libpng, Copyright (c) 2025 PanicTitan (@PanicTitan)); see
# LICENSES/raylib.txt.
#
# Painting on a mesh's texture: the mouse ray (GetScreenToWorldRay) is
# tested against the model's transformed bounding box, then against each of
# its transformed triangles (GetRayCollisionTriangle); the closest hit's
# Vector3Barycenter weights its corners' texture coordinates, wrapped into
# [0, 1) by floorf, and a brush stroke is drawn there into a 512x512 canvas
# image (ImageDrawCircle, the circles of a stroke placed with Lerp) whose
# texture is updated (UpdateTexture). The picker reads the canvas
# (GetImageColor; a pixel past the image is its zero color, as raylib
# answers). A raygui panel (Jongui: GuiToggle, GuiButton) switches the tool
# and the mesh (GenMeshSphere, GenMeshCube, GenMeshCylinder shifted down by
# MatrixTranslate, GenMeshTorus), sets the brush size, clears or fills the
# canvas; the swatches take a press; RMB turns the camera
# (CAMERA_THIRD_PERSON). The curved meshes need the glibc profile's sinf/
# cosf, qsort weld and (the cylinder) binary64 cos and sin (docs/MODELS.md),
# the perspective its binary64 tan (docs/PERSPECTIVE.md); a mesh, camera,
# ray or box step Jonlib refuses refuses that frame and every later one.
# See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# currentTool (0 paint, 1 picker), activeColor, brushRadius, lastHitUV and hasLastHit.
type Brush is Data:
  Brush{tool: U32, color: U32, radius: U32, last: M.Vector2, has: Bool}

# valid: everything made and no refusal so far. shape is currentShape (0 sphere, 1 cube, 2 cylinder, 3 torus), bounds
# modelBBox (transformed by the model's transform) and info the canvas texture the model's material holds.
type Scene is Data:
  Scene{valid: Bool, camera: J.Camera3D, gui: G.Gui, model: J.Model, bounds: J.BoundingBox, shape: U32, info: J.TextureInfo, brush: Brush}

# canvas is canvasImage, textures [canvasTexture].
type State is Type:
  State{scene: Scene, canvas: Maybe<J.Surface>, textures: List<J.Texture>}

# GetMeshHitUV's closest hit so far: found, closestDistance and hitUV.
type Hit is Data:
  Hit{found: Bool, distance: F32, uv: M.Vector2}

# What the panel did this frame: the scene after its toggles, swatches and size buttons, and the CLEAR and FILL buttons.
type Controls is Data:
  Controls{scene: Scene, clear: Bool, fill: Bool}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.0, 3.5, 6.5}, M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# uiPanelRec.
def panel() -> J.Rectangle:
  J.Rectangle{10.0, 10.0, 230.0, 490.0}

def palette(i: U32) -> U32:
  match i:
    case 0: J.Color.RED()
    case 1: J.Color.ORANGE()
    case 2: J.Color.GOLD()
    case 3: J.Color.LIME()
    case 4: J.Color.SKYBLUE()
    case 5: J.Color.PURPLE()
    case 6: J.Color.DARKGRAY()
    case _: J.Color.WHITE()

# swatchRec = (25.0f + (i%4)*48, 245.0f + (i/4)*45, 40, 38).
def swatch(+i: U32) -> J.Rectangle:
  J.Rectangle{(25.0 + U32.to_f32(((i % 4) * 48 : U32)) : F32), (245.0 + U32.to_f32(((i / 4) * 45 : U32)) : F32), 40.0, 38.0}

def Brush.start() -> Brush:
  Brush{0, J.Color.RED(), 12, M.Vector2{0.0, 0.0}, False{}}

def Brush.tool(+brush: Brush) -> U32:
  Brush{+tool, _, _, _, _} = brush
  tool

def Brush.color(+brush: Brush) -> U32:
  Brush{_, +color, _, _, _} = brush
  color

def Brush.radius(+brush: Brush) -> U32:
  Brush{_, _, +radius, _, _} = brush
  radius

# hasLastHit = false.
def Brush.unhit(+brush: Brush) -> Brush:
  Brush{+tool, +color, +radius, +last, _} = brush
  Brush{tool, color, radius, last, False{}}

# lastHitUV = hitUV; hasLastHit = true.
def Brush.painted(+brush: Brush, +uv: M.Vector2) -> Brush:
  Brush{+tool, +color, +radius, _, _} = brush
  Brush{tool, color, radius, uv, True{}}

# activeColor = GetImageColor(...); currentTool = TOOL_PAINT; hasLastHit = false.
def Brush.picked(+brush: Brush, +color: U32) -> Brush:
  Brush{_, _, +radius, +last, _} = brush
  Brush{0, color, radius, last, False{}}

def Brush.with_tool(+brush: Brush, +tool: U32) -> Brush:
  Brush{_, +color, +radius, +last, +has} = brush
  Brush{tool, color, radius, last, has}

def Brush.with_color(+brush: Brush, +color: U32) -> Brush:
  Brush{+tool, _, +radius, +last, +has} = brush
  Brush{tool, color, radius, last, has}

def Brush.with_radius(+brush: Brush, +radius: U32) -> Brush:
  Brush{+tool, +color, _, +last, +has} = brush
  Brush{tool, color, radius, last, has}

def Scene.valid(+scene: Scene) -> Bool:
  Scene{+valid, _, _, _, _, _, _, _} = scene
  valid

def Scene.camera(+scene: Scene) -> J.Camera3D:
  Scene{_, +camera, _, _, _, _, _, _} = scene
  camera

def Scene.gui(+scene: Scene) -> G.Gui:
  Scene{_, _, +gui, _, _, _, _, _} = scene
  gui

def Scene.model(+scene: Scene) -> J.Model:
  Scene{_, _, _, +model, _, _, _, _} = scene
  model

def Scene.bounds(+scene: Scene) -> J.BoundingBox:
  Scene{_, _, _, _, +bounds, _, _, _} = scene
  bounds

def Scene.shape(+scene: Scene) -> U32:
  Scene{_, _, _, _, _, +shape, _, _} = scene
  shape

def Scene.info(+scene: Scene) -> J.TextureInfo:
  Scene{_, _, _, _, _, _, +info, _} = scene
  info

def Scene.brush(+scene: Scene) -> Brush:
  Scene{_, _, _, _, _, _, _, +brush} = scene
  brush

def Scene.invalid(+scene: Scene) -> Scene:
  Scene{_, +camera, +gui, +model, +bounds, +shape, +info, +brush} = scene
  Scene{False{}, camera, gui, model, bounds, shape, info, brush}

def Scene.with_camera(+scene: Scene, +camera: J.Camera3D) -> Scene:
  Scene{+valid, _, +gui, +model, +bounds, +shape, +info, +brush} = scene
  Scene{valid, camera, gui, model, bounds, shape, info, brush}

def Scene.with_brush(+scene: Scene, +brush: Brush) -> Scene:
  Scene{+valid, +camera, +gui, +model, +bounds, +shape, +info, _} = scene
  Scene{valid, camera, gui, model, bounds, shape, info, brush}

# *model, *bbox and *currentShape after ChangeShape.
def Scene.shaped(+scene: Scene, +model: J.Model, +bounds: J.BoundingBox, +shape: U32) -> Scene:
  Scene{+valid, +camera, +gui, _, _, _, +info, +brush} = scene
  Scene{valid, camera, gui, model, bounds, shape, info, brush}

def Scene.with_tool(+scene: Scene, +tool: U32) -> Scene:
  Scene.with_brush(scene, Brush.with_tool(Scene.brush(scene), tool))

def Scene.with_color(+scene: Scene, +color: U32) -> Scene:
  Scene.with_brush(scene, Brush.with_color(Scene.brush(scene), color))

def Scene.with_radius(+scene: Scene, +radius: U32) -> Scene:
  Scene.with_brush(scene, Brush.with_radius(Scene.brush(scene), radius))

def bbox.zero() -> J.BoundingBox:
  J.BoundingBox{M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 0.0, 0.0}}

# ---------------------------------------------------------------------------
# ChangeShape

# GenMeshSphere(1.5f, 32, 32), GenMeshCube(2.2f, 2.2f, 2.2f), GenMeshCylinder(1.2f, 2.5f, 24), GenMeshTorus(0.6f, 1.6f, 24, 36).
def form.mesh(+libm: M.Libm, shape: U32) -> Maybe<J.Mesh>:
  match shape:
    case 0: J.Mesh.gen_sphere_for(M.Uncontracted{}, libm, 1.5, 32, 32)
    case 1: Some{J.Mesh.gen_cube(2.2, 2.2, 2.2)}
    case 2: J.Mesh.gen_cylinder_for(M.Uncontracted{}, libm, 1.2, 2.5, 24)
    case _: J.Mesh.gen_torus_for(M.Uncontracted{}, libm, 0.6, 1.6, 24, 36)

# The cylinder's model->transform = MatrixTranslate(0.0f, -1.25f, 0.0f); LoadModelFromMesh's identity otherwise.
def form.transform(shape: U32) -> M.Matrix:
  match shape:
    case 0: M.Matrix.identity()
    case 1: M.Matrix.identity()
    case 2: M.Matrix.translate(0.0, F32.neg(1.25), 0.0)
    case _: M.Matrix.identity()

def form.textured(+info: J.TextureInfo, materials: +List<J.Material>) -> +List<J.Material>:
  match materials:
    case Con{+m, rest}: Con{Maybe.default(&1, J.Material, J.Material.set_texture(m, 0, info), m), rest}
    case Nil{}: Nil{}

# model->transform and model->materials[0].maps[MATERIAL_MAP_DIFFUSE].texture = canvasTexture.
def form.model(+model: J.Model, +transform: M.Matrix, +info: J.TextureInfo) -> J.Model:
  J.Model{_, +meshes, +materials, +ids} = model
  J.Model{transform, meshes, form.textured(info, materials), ids}

# box.min = Vector3Transform(box.min, model->transform); box.max likewise.
def form.box(+box: J.BoundingBox, +transform: M.Matrix) -> J.BoundingBox:
  J.BoundingBox{+low, +high} = box
  J.BoundingBox{M.Vector3.transform(low, transform), M.Vector3.transform(high, transform)}

def form.bounded(box: Maybe<J.BoundingBox>, +model: J.Model, +transform: M.Matrix, +scene: Scene, +shape: U32) -> Scene:
  match box:
    case None{}: Scene.invalid(scene)
    case Some{+b}: Scene.shaped(scene, model, form.box(b, transform), shape)

# LoadModelFromMesh(mesh) and GetMeshBoundingBox(model->meshes[0]).
def form.built(mesh: Maybe<J.Mesh>, +libm: M.Libm, +scene: Scene, +shape: U32) -> Scene:
  match mesh:
    case None{}: Scene.invalid(scene)
    case Some{+m}: form.bounded(J.Mesh.bounding_box_for(libm, m), form.model(J.Model.from_mesh(m), form.transform(shape), Scene.info(scene)), form.transform(shape), scene, shape)

# ChangeShape(&model, &modelBBox, &currentShape, shape, canvasTexture).
def form.make(+libm: M.Libm, +scene: Scene, +shape: U32) -> Scene:
  form.built(form.mesh(libm, shape), libm, scene, shape)

# ---------------------------------------------------------------------------
# GetMeshHitUV

def Hit.miss() -> Hit:
  Hit{False{}, 1000000000.0, M.Vector2{0.0, 0.0}}

def Hit.found(+found: Hit) -> Bool:
  Hit{+yes, _, _} = found
  yes

def Hit.distance(+found: Hit) -> F32:
  Hit{_, +distance, _} = found
  distance

def Hit.uv(+found: Hit) -> M.Vector2:
  Hit{_, _, +uv} = found
  uv

def collided(+c: J.RayCollision) -> Bool:
  J.RayCollision{+yes, _, _, _} = c
  yes

# hitUV = w.x*uvA + w.y*uvB + w.z*uvC per coordinate, then hitUV -= floorf(hitUV).
def texel.at(+w: M.Vector3, +ta: M.Vector2, +tb: M.Vector2, +tc: M.Vector2) -> M.Vector2:
  M.Vector3{+wx, +wy, +wz} = w
  M.Vector2{+ax, +ay} = ta
  M.Vector2{+bx, +by} = tb
  M.Vector2{+cx, +cy} = tc
  +u = (wx * ax + wy * bx + wz * cx : F32)
  +v = (wx * ay + wy * by + wz * cy : F32)
  M.Vector2{(u - F32.floor(u) : F32), (v - F32.floor(v) : F32)}

# if (hit.hit && (hit.distance < closestDistance)): the hit, with w = Vector3Barycenter(hit.point, a, b, c).
def tri.taken(take: Bool, +distance: F32, +point: M.Vector3, +a: M.Vector3, +b: M.Vector3, +c: M.Vector3, +ta: M.Vector2, +tb: M.Vector2, +tc: M.Vector2, +best: Hit) -> Hit:
  match take:
    case False{}: best
    case True{}: Hit{True{}, distance, texel.at(M.Vector3.barycenter(point, a, b, c), ta, tb, tc)}

def tri.hit(+found: J.RayCollision, +a: M.Vector3, +b: M.Vector3, +c: M.Vector3, +ta: M.Vector2, +tb: M.Vector2, +tc: M.Vector2, +best: Hit) -> Hit:
  J.RayCollision{+yes, +distance, +point, _} = found
  tri.taken(yes && (distance < Hit.distance(best) : F32), distance, point, a, b, c, ta, tb, tc, best)

# a, b and c = Vector3Transform(vertex, model.transform); GetRayCollisionTriangle(ray, a, b, c).
def tri.test(+ray: J.Ray, +transform: M.Matrix, +p0: M.Vector3, +p1: M.Vector3, +p2: M.Vector3, +ta: M.Vector2, +tb: M.Vector2, +tc: M.Vector2, +best: Hit) -> Hit:
  +a = M.Vector3.transform(p0, transform)
  +b = M.Vector3.transform(p1, transform)
  +c = M.Vector3.transform(p2, transform)
  tri.hit(J.Collision.ray_triangle_for(M.Uncontracted{}, ray, a, b, c), a, b, c, ta, tb, tc, best)

# Without indices: triangle tri has the vertices 3*tri, 3*tri + 1 and 3*tri + 2.
def tris.flat(vs: +List<F32>, ts: +List<F32>, +ray: J.Ray, +transform: M.Matrix, +best: Hit) -> Hit:
  match vs ts:
    case Con{+x0, Con{+y0, Con{+z0, Con{+x1, Con{+y1, Con{+z1, Con{+x2, Con{+y2, Con{+z2, vrest}}}}}}}}} Con{+u0, Con{+v0, Con{+u1, Con{+v1, Con{+u2, Con{+v2, trest}}}}}}:
      tris.flat(vrest, trest, ray, transform, tri.test(ray, transform, M.Vector3{x0, y0, z0}, M.Vector3{x1, y1, z1}, M.Vector3{x2, y2, z2}, M.Vector2{u0, v0}, M.Vector2{u1, v1},
        M.Vector2{u2, v2}, best))
    case _ _: best

def points3(values: +List<F32>) -> +List<M.Vector3>:
  match values:
    case Con{+x, Con{+y, Con{+z, rest}}}: Con{M.Vector3{x, y, z}, points3(rest)}
    case _: Nil{}

def points2(values: +List<F32>) -> +List<M.Vector2>:
  match values:
    case Con{+x, Con{+y, rest}}: Con{M.Vector2{x, y}, points2(rest)}
    case _: Nil{}

def vec3.head(list: +List<M.Vector3>) -> M.Vector3:
  match list:
    case Nil{}: M.Vector3{0.0, 0.0, 0.0}
    case Con{+v, _}: v

def vec2.head(list: +List<M.Vector2>) -> M.Vector2:
  match list:
    case Nil{}: M.Vector2{0.0, 0.0}
    case Con{+v, _}: v

def vec3.at(+ps: +List<M.Vector3>, +i: U32) -> M.Vector3:
  vec3.head(List.drop(&2, M.Vector3, ps, U32.to_nat(i)))

def vec2.at(+ts: +List<M.Vector2>, +i: U32) -> M.Vector2:
  vec2.head(List.drop(&2, M.Vector2, ts, U32.to_nat(i)))

# With indices: i0, i1 and i2 = mesh.indices[3*tri + 0..2] (the cube's 36 indices into 24 vertices).
def tris.indexed(ids: +List<U32>, +ps: +List<M.Vector3>, +ts: +List<M.Vector2>, +ray: J.Ray, +transform: M.Matrix, +best: Hit) -> Hit:
  match ids:
    case Con{+i0, Con{+i1, Con{+i2, rest}}}:
      tris.indexed(rest, ps, ts, ray, transform, tri.test(ray, transform, vec3.at(ps, i0), vec3.at(ps, i1), vec3.at(ps, i2), vec2.at(ts, i0), vec2.at(ts, i1), vec2.at(ts, i2), best))
    case _: best

def geo.hit(vertices: Maybe<&2, +List<F32>>, texcoords: Maybe<&2, +List<F32>>, indices: Maybe<&2, +List<U32>>, +ray: J.Ray, +transform: M.Matrix) -> Maybe<Hit>:
  match vertices texcoords indices:
    case Some{+vs} Some{+ts} None{}: Some{tris.flat(vs, ts, ray, transform, Hit.miss())}
    case Some{+vs} Some{+ts} Some{+ids}: Some{tris.indexed(ids, points3(vs), points2(ts), ray, transform, Hit.miss())}
    case _ _ _: None{}

def geo.mesh(+mesh: J.Mesh, +ray: J.Ray, +transform: M.Matrix) -> Maybe<Hit>:
  J.Mesh{_, _, vertices, texcoords, _, _, _, _, indices} = mesh
  geo.hit(vertices, texcoords, indices, ray, transform)

def geo.first(meshes: +List<J.Mesh>, +ray: J.Ray, +transform: M.Matrix) -> Maybe<Hit>:
  match meshes:
    case Nil{}: None{}
    case Con{+mesh, _}: geo.mesh(mesh, ray, transform)

# if (!GetRayCollisionBox(ray, bbox).hit) return false (fast reject); else the triangles of model.meshes[0].
def geo.inside(+ray: J.Ray, +model: J.Model, inside: Bool) -> Maybe<Hit>:
  J.Model{+transform, +meshes, _, _} = model
  match inside:
    case False{}: Some{Hit.miss()}
    case True{}: geo.first(meshes, ray, transform)

def geo.boxed(box: Maybe<J.RayCollision>, +ray: J.Ray, +model: J.Model) -> Maybe<Hit>:
  match box:
    case None{}: None{}
    case Some{+b}: geo.inside(ray, model, collided(b))

# ---------------------------------------------------------------------------
# Update

# (int)(v*CANVAS_SIZE), v in [0, 1].
def px.of(+v: F32) -> F32:
  F32.trunc((v * 512.0 : F32))

def coord.x(+v: M.Vector2) -> F32:
  M.Vector2{+x, _} = v
  x

def coord.y(+v: M.Vector2) -> F32:
  M.Vector2{_, +y} = v
  y

# hasLastHit && (fabsf(hitUV.x - lastHitUV.x) < 0.25f) && (fabsf(hitUV.y - lastHitUV.y) < 0.25f).
def stroke.joined(+brush: Brush, +uv: M.Vector2) -> Bool:
  Brush{_, _, _, +last, +has} = brush
  M.Vector2{+lx, +ly} = last
  M.Vector2{+x, +y} = uv
  has && (F32.abs((x - lx : F32)) < 0.25 : F32) && (F32.abs((y - ly : F32)) < 0.25 : F32)

# t = (float)i/(float)steps.
def stroke.t(+i: U32, +steps: U32) -> F32:
  (U32.to_f32(i) / U32.to_f32(steps) : F32)

# for (i = 0; i <= steps; i++) ImageDrawCircle(&canvasImage, (int)Lerp(lastPx, px, t), (int)Lerp(lastPy, py, t), brushRadius, activeColor).
def stroke.loop(n: Nat, +i: U32, +steps: U32, +lx: F32, +ly: F32, +x: F32, +y: F32, +radius: U32, +color: U32, canvas: J.Surface) -> J.Surface:
  match n:
    case 0n: canvas
    case 1n+k: stroke.loop(k, (i + 1 : U32), steps, lx, ly, x, y, radius, color, J.Surface.draw_circle(canvas, F32.trunc(M.Math.lerp(lx, x, stroke.t(i, steps))),
      F32.trunc(M.Math.lerp(ly, y, stroke.t(i, steps))), radius, color))

def stroke.steps(+steps: U32, +lx: F32, +ly: F32, +x: F32, +y: F32, +radius: U32, +color: U32, canvas: J.Surface) -> J.Surface:
  stroke.loop(U32.to_nat((steps + 1 : U32)), 0, steps, lx, ly, x, y, radius, color, canvas)

# steps = (int)(Vector2Distance(last pixel, pixel)/2.0f) + 1 circles along the stroke, else one circle at the pixel.
def stroke.drawn(joined: Bool, +lx: F32, +ly: F32, +x: F32, +y: F32, +radius: U32, +color: U32, canvas: J.Surface) -> J.Surface:
  match joined:
    case False{}: J.Surface.draw_circle(canvas, x, y, radius, color)
    case True{}: stroke.steps((F32.to_u32((M.Vector2.distance(M.Vector2{lx, ly}, M.Vector2{x, y}) / 2.0 : F32)) + 1 : U32), lx, ly, x, y, radius, color, canvas)

# TOOL_PAINT at hitUV.
def stroke(+brush: Brush, +uv: M.Vector2, canvas: J.Surface) -> J.Surface:
  Brush{_, +color, +radius, +last, _} = brush
  stroke.drawn(stroke.joined(brush, uv), px.of(coord.x(last)), px.of(coord.y(last)), px.of(coord.x(uv)), px.of(coord.y(uv)), radius, color, canvas)

def upload.done(result: Result<&1, &1, J.Texture & J.Surface.Error, J.Texture>, rest: List<J.Texture>, +scene: Scene, canvas: J.Surface) -> State:
  match result:
    case Fail{_}: State{Scene.invalid(scene), Some{canvas}, rest}
    case Done{t}: State{scene, Some{canvas}, Con{t, rest}}

def upload.into(textures: List<J.Texture>, copy: J.Surface, +scene: Scene, canvas: J.Surface) -> State:
  match textures:
    case Nil{}: State{Scene.invalid(scene), Some{canvas}, Nil{}}
    case Con{t, rest}: upload.done(J.Texture.update(t, copy), rest, scene, canvas)

# UpdateTexture(canvasTexture, canvasImage.data).
def upload(pair: J.Surface & J.Surface, +scene: Scene, textures: List<J.Texture>) -> State:
  (canvas, copy) = pair
  upload.into(textures, copy, scene, canvas)

# GetImageColor: (Color){ 0 } for a pixel past the image.
def picked.color(got: Maybe<&2, U32>) -> U32:
  match got:
    case None{}: J.Color.BLANK()
    case Some{+c}: c

def update.picked(r: J.Surface & Maybe<&2, U32>, +scene: Scene, textures: List<J.Texture>) -> State:
  (canvas, got) = r
  State{Scene.with_brush(scene, Brush.picked(Scene.brush(scene), picked.color(got))), Some{canvas}, textures}

# The hit's pixel (px, py) = ((int)(hitUV.x*CANVAS_SIZE), (int)(hitUV.y*CANVAS_SIZE)): TOOL_PAINT paints and updates the
# texture, TOOL_PICKER takes the color there.
def update.tool(paint: Bool, +uv: M.Vector2, +scene: Scene, canvas: Maybe<J.Surface>, textures: List<J.Texture>) -> State:
  match paint canvas:
    case True{} Some{c}: upload(J.Surface.copy(stroke(Scene.brush(scene), uv, c)), Scene.with_brush(scene, Brush.painted(Scene.brush(scene), uv)), textures)
    case False{} Some{c}: update.picked(J.Surface.get(c, F32.to_u32(px.of(coord.x(uv))), F32.to_u32(px.of(coord.y(uv)))), scene, textures)
    case _ None{}: State{Scene.invalid(scene), None{}, textures}

# if (GetMeshHitUV(ray, model, modelBBox, &hitUV)), else hasLastHit = false.
def update.found(found: Bool, +uv: M.Vector2, +scene: Scene, canvas: Maybe<J.Surface>, textures: List<J.Texture>) -> State:
  match found:
    case False{}: State{Scene.with_brush(scene, Brush.unhit(Scene.brush(scene))), canvas, textures}
    case True{}: update.tool(U32.is_eq(Brush.tool(Scene.brush(scene)), 0), uv, scene, canvas, textures)

def update.hit(result: Maybe<Hit>, +scene: Scene, canvas: Maybe<J.Surface>, textures: List<J.Texture>) -> State:
  match result:
    case None{}: State{Scene.invalid(scene), canvas, textures}
    case Some{+h}: update.found(Hit.found(h), Hit.uv(h), scene, canvas, textures)

# ray = GetScreenToWorldRay(mousePos, camera).
def update.ray(ray: Maybe<J.Ray>, +libm: M.Libm, +scene: Scene, canvas: Maybe<J.Surface>, textures: List<J.Texture>) -> State:
  match ray:
    case None{}: State{Scene.invalid(scene), canvas, textures}
    case Some{+r}: update.hit(geo.boxed(J.Collision.ray_box_for(M.Uncontracted{}, libm, r, Scene.bounds(scene)), r, Scene.model(scene)), scene, canvas, textures)

# if (!isMouseOverUI && IsMouseButtonDown(MOUSE_BUTTON_LEFT)), else hasLastHit = false.
def update.click(painting: Bool, +libm: M.Libm, +core: J.Core, +scene: Scene, canvas: Maybe<J.Surface>, textures: List<J.Texture>) -> State:
  match painting:
    case False{}: State{Scene.with_brush(scene, Brush.unhit(Scene.brush(scene))), canvas, textures}
    case True{}: update.ray(J.Camera.screen_to_world_ray_for(M.Uncontracted{}, libm, J.Input.get_mouse_position(core), Scene.camera(scene), core), libm, scene, canvas, textures)

def update.moved(moved: Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +scene: Scene, canvas: Maybe<J.Surface>, textures: List<J.Texture>) -> State:
  match moved:
    case None{}: State{Scene.invalid(scene), canvas, textures}
    case Some{+c}: update.click(Bool.not(J.Collision.point_rec(J.Input.get_mouse_position(core), panel())) && J.Input.is_mouse_button_down(core, 0), libm, core,
      Scene.with_camera(scene, c), canvas, textures)

# if (IsMouseButtonDown(MOUSE_BUTTON_RIGHT)) UpdateCamera(&camera, CAMERA_THIRD_PERSON).
def update.camera(held: Bool, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D) -> Maybe<J.Camera3D>:
  match held:
    case False{}: Some{camera}
    case True{}: J.Camera.update_for(M.Uncontracted{}, libm, core, camera, J.CameraMode.CAMERA_THIRD_PERSON())

def update.live(valid: Bool, +libm: M.Libm, +core: J.Core, +scene: Scene, canvas: Maybe<J.Surface>, textures: List<J.Texture>) -> State:
  match valid:
    case False{}: State{scene, canvas, textures}
    case True{}: update.moved(update.camera(J.Input.is_mouse_button_down(core, 1), libm, core, Scene.camera(scene)), libm, core, scene, canvas, textures)

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+scene, canvas, textures} = state
  (core, update.live(Scene.valid(scene), libm, core, scene, canvas, textures))

# ---------------------------------------------------------------------------
# Draw

# GuiToggle's RESULT_CHANGED: the active flag flipped.
def differs(a: Bool, +b: Bool) -> Bool:
  match a:
    case True{}: Bool.not(b)
    case False{}: b

def ui.tool.done(+scene: Scene, +index: U32, +active: Bool, r: J.Frame & Bool) -> J.Frame & Scene:
  (frame, +now) = r
  (frame, Bool.pick(Scene, differs(now, active), Scene.with_tool(scene, index), scene))

# if (GuiToggle(bounds, text, &active)) currentTool = index; active is (currentTool == index) before the toggles.
def ui.tool(+core: J.Core, +tool: U32, +index: U32, +bounds: J.Rectangle, text: String, r: J.Frame & Scene) -> J.Frame & Scene:
  (frame, +scene) = r
  ui.tool.done(scene, index, U32.is_eq(tool, index), G.Gui.toggle(Scene.gui(scene), core, frame, bounds, text, U32.is_eq(tool, index)))

def ui.label(r: J.Frame & Scene) -> J.Frame & Scene:
  (frame, +scene) = r
  (J.Draw.text(frame, "Mesh Shape:", 25.0, 100.0, 10.0, J.Color.LIGHTGRAY()), scene)

def form.changed(changed: Bool, +libm: M.Libm, +scene: Scene, +index: U32) -> Scene:
  match changed:
    case False{}: scene
    case True{}: form.make(libm, scene, index)

def ui.shape.done(+libm: M.Libm, +scene: Scene, +index: U32, +active: Bool, r: J.Frame & Bool) -> J.Frame & Scene:
  (frame, +now) = r
  (frame, form.changed(differs(now, active), libm, scene, index))

# if (GuiToggle(bounds, text, &active)) ChangeShape(..., index, ...); active is (currentShape == index) before the toggles.
def ui.shape(+libm: M.Libm, +core: J.Core, +shape: U32, +index: U32, +bounds: J.Rectangle, text: String, r: J.Frame & Scene) -> J.Frame & Scene:
  (frame, +scene) = r
  ui.shape.done(libm, scene, index, U32.is_eq(shape, index), G.Gui.toggle(Scene.gui(scene), core, frame, bounds, text, U32.is_eq(shape, index)))

def swatches(n: Nat, +i: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+k: swatches(k, (i + 1 : U32), J.Draw.rectangle_lines_ex(J.Draw.rectangle_rec(frame, swatch(i), palette(i)), swatch(i), 1.0, J.Color.WHITE()))

# if (CheckCollisionPointRec(mousePos, swatchRec) && IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) activeColor = palette[i].
def swatch.pick(n: Nat, +i: U32, +mouse: M.Vector2, +pressed: Bool, +color: U32) -> U32:
  match n:
    case 0n: color
    case 1n+k: swatch.pick(k, (i + 1 : U32), mouse, pressed, Bool.pick(U32, J.Collision.point_rec(mouse, swatch(i)) && pressed, palette(i), color))

def ui.size(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 25.0, 345.0, 10.0, J.Color.LIGHTGRAY())

# The active color, the swatches and the brush size.
def ui.colors(+core: J.Core, r: J.Frame & Scene) -> J.Frame & Scene:
  (frame, +scene) = r
  +color = Brush.color(Scene.brush(scene))
  +radius = Brush.radius(Scene.brush(scene))
  f1 = J.Draw.rectangle(J.Draw.text(frame, "Active Color:", 25.0, 195.0, 10.0, J.Color.LIGHTGRAY()), 125.0, 193.0, 95.0, 20.0, color)
  f2 = J.Draw.rectangle_lines(f1, 125.0, 193.0, 95.0, 20.0, J.Color.WHITE())
  f3 = swatches(8n, 0, J.Draw.text(f2, "Palette Swatches:", 25.0, 225.0, 10.0, J.Color.LIGHTGRAY()))
  (ui.size(J.Text.format("Brush Size: %dpx", [J.TextInt{radius}]), f3),
    Scene.with_color(scene, swatch.pick(8n, 0, J.Input.get_mouse_position(core), J.Input.is_mouse_button_pressed(core, 0), color)))

# if (GuiButton(SIZE -) && (brushRadius > 2)) brushRadius -= 2.
def ui.minus.done(+scene: Scene, r: J.Frame & Bool) -> J.Frame & Scene:
  (frame, +pressed) = r
  +radius = Brush.radius(Scene.brush(scene))
  (frame, Bool.pick(Scene, pressed && (radius > 2 : U32), Scene.with_radius(scene, (radius - 2 : U32)), scene))

def ui.minus(+core: J.Core, r: J.Frame & Scene) -> J.Frame & Scene:
  (frame, +scene) = r
  ui.minus.done(scene, G.Gui.button(Scene.gui(scene), core, frame, J.Rectangle{25.0, 365.0, 95.0, 30.0}, "SIZE -"))

# if (GuiButton(SIZE +) && (brushRadius < 64)) brushRadius += 2.
def ui.plus.done(+scene: Scene, r: J.Frame & Bool) -> J.Frame & Scene:
  (frame, +pressed) = r
  +radius = Brush.radius(Scene.brush(scene))
  (frame, Bool.pick(Scene, pressed && (radius < 64 : U32), Scene.with_radius(scene, (radius + 2 : U32)), scene))

def ui.plus(+core: J.Core, r: J.Frame & Scene) -> J.Frame & Scene:
  (frame, +scene) = r
  ui.plus.done(scene, G.Gui.button(Scene.gui(scene), core, frame, J.Rectangle{125.0, 365.0, 95.0, 30.0}, "SIZE +"))

def ui.fill.done(+scene: Scene, +clear: Bool, r: J.Frame & Bool) -> J.Frame & Controls:
  (frame, +fill) = r
  (frame, Controls{scene, clear, fill})

def ui.clear.done(+core: J.Core, +scene: Scene, r: J.Frame & Bool) -> J.Frame & Controls:
  (frame, +clear) = r
  ui.fill.done(scene, clear, G.Gui.button(Scene.gui(scene), core, frame, J.Rectangle{125.0, 410.0, 95.0, 30.0}, "FILL"))

# The CLEAR and FILL buttons (their canvas updates follow the panel).
def ui.clear(+core: J.Core, r: J.Frame & Scene) -> J.Frame & Controls:
  (frame, +scene) = r
  ui.clear.done(core, scene, G.Gui.button(Scene.gui(scene), core, frame, J.Rectangle{25.0, 410.0, 95.0, 30.0}, "CLEAR"))

# The tool toggles, the shape toggles, the color display and swatches, the brush size buttons and the canvas buttons.
def ui.panel(+libm: M.Libm, +core: J.Core, +scene: Scene, frame: J.Frame) -> J.Frame & Controls:
  +tool = Brush.tool(Scene.brush(scene))
  +shape = Scene.shape(scene)
  ui.clear(core, ui.plus(core, ui.minus(core, ui.colors(core, ui.shape(libm, core, shape, 3, J.Rectangle{125.0, 153.0, 95.0, 28.0}, "TORUS",
    ui.shape(libm, core, shape, 2, J.Rectangle{25.0, 153.0, 95.0, 28.0}, "CYLINDER", ui.shape(libm, core, shape, 1, J.Rectangle{125.0, 120.0, 95.0, 28.0}, "CUBE",
    ui.shape(libm, core, shape, 0, J.Rectangle{25.0, 120.0, 95.0, 28.0}, "SPHERE", ui.label(ui.tool(core, tool, 1, J.Rectangle{125.0, 55.0, 95.0, 32.0}, "PICKER",
    ui.tool(core, tool, 0, J.Rectangle{25.0, 55.0, 95.0, 32.0}, "PAINT", (frame, scene))))))))))))

def layer.cleared(act: Bool, +color: U32, canvas: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match act canvas:
    case True{} Some{c}: Some{J.Surface.clear(c, color)}
    case False{} Some{c}: Some{c}
    case _ None{}: None{}

def layer.changed(changed: Bool, +scene: Scene, canvas: Maybe<J.Surface>, textures: List<J.Texture>) -> State:
  match changed canvas:
    case True{} Some{c}: upload(J.Surface.copy(c), scene, textures)
    case False{} Some{c}: State{scene, Some{c}, textures}
    case _ None{}: State{Scene.invalid(scene), None{}, textures}

# CLEAR: ImageClearBackground(&canvasImage, RAYWHITE); FILL: ImageClearBackground(&canvasImage, activeColor); each with
# UpdateTexture(canvasTexture, canvasImage.data).
def layer.ops(+made: Controls, canvas: Maybe<J.Surface>, textures: List<J.Texture>) -> State:
  Controls{+scene, +clear, +fill} = made
  layer.changed(clear || fill, scene, layer.cleared(fill, Brush.color(Scene.brush(scene)), layer.cleared(clear, J.Color.RAYWHITE(), canvas)), textures)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, (800.0 - 90.0 : F32), 15.0, fps)))

def draw.fps(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# The help text and DrawFPS(screenWidth - 90, 15).
def draw.done(+core: J.Core, canvas: Maybe<J.Surface>, textures: List<J.Texture>, r: J.Frame & Controls) -> J.Core & (State & J.Frame):
  (frame, +made) = r
  f1 = J.Draw.text(frame, "Left click: paint / pick color   |   Right drag: orbit camera", 260.0, (450.0 - 25.0 : F32), 10.0, J.Color.RAYWHITE())
  draw.fps(layer.ops(made, canvas, textures), f1, J.Core.get_fps(core, J.Core.get_time(core)), core)

# DrawGrid(10, 1.0f); EndMode3D(); the side panel (Fade(BLACK, 0.8f), DARKGRAY border) and its title.
def draw.scene(+libm: M.Libm, +core: J.Core, +scene: Scene, canvas: Maybe<J.Surface>, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0))
  f2 = J.Draw.rectangle_lines_ex(J.Draw.rectangle_rec(f1, panel(), J.Color.with_alpha(J.Color.BLACK(), 0.8)), panel(), 2.0, J.Color.DARKGRAY())
  draw.done(core, canvas, textures, ui.panel(libm, core, scene, J.Draw.text(f2, "MESH UV PAINTER", 25.0, 22.0, 20.0, J.Color.GOLD())))

# ClearBackground((Color){ 30, 32, 40, 255 }); BeginMode3D(camera); DrawModel(model, Vector3Zero(), 1.0f, WHITE).
def draw.at(valid: Bool, +libm: M.Libm, +core: J.Core, +scene: Scene, canvas: Maybe<J.Surface>, textures: List<J.Texture>, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid:
    case False{}: (core, (State{scene, canvas, textures}, J.Frame.refuse(frame)))
    case True{}: draw.scene(libm, core, scene, canvas, J.Draw.model_ex_for(libm, J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.rgba(30, 32, 40, 255)),
      Scene.camera(scene)), textures, Scene.model(scene), M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 0.0, M.Vector3{1.0, 1.0, 1.0}, J.Color.WHITE()))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+scene, canvas, textures} = state
  draw.at(Scene.valid(scene), libm, core, scene, canvas, textures, frame)

# The main loop's body; libm is the profile of the meshes, UpdateCamera's sinf/cosf, the ray, the box test and the
# perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.failed(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{Scene{False{}, start(), G.Gui.new(), J.Model.empty(), bbox.zero(), 0, J.TextureInfo.none(), Brush.start()}, None{}, Nil{}}))

# ChangeShape(&model, &modelBBox, &currentShape, SHAPE_SPHERE, canvasTexture); SetTargetFPS(60).
def setup.texture(+libm: M.Libm, +core: J.Core, frame: J.Frame, canvas: J.Surface, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  (J.Core.set_target_fps(core, 60), (frame, State{form.make(libm, Scene{True{}, start(), G.Gui.new(), J.Model.empty(), bbox.zero(), 0, info, Brush.start()}, 0), Some{canvas},
    [J.Texture.set_filter(texture, 1)]}))

def setup.loaded(+libm: M.Libm, +core: J.Core, canvas: J.Surface, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: setup.failed(core, frame)
    case Some{t}: setup.texture(libm, core, frame, canvas, J.Texture.info(t))

# canvasTexture = LoadTextureFromImage(canvasImage); SetTextureFilter(canvasTexture, TEXTURE_FILTER_BILINEAR).
def setup.copied(+libm: M.Libm, +core: J.Core, frame: J.Frame, pair: J.Surface & J.Surface) -> J.Core & (J.Frame & State):
  (canvas, copy) = pair
  setup.loaded(libm, core, canvas, J.Texture.load_from_image(frame, copy))

def setup.image(image: Maybe<J.Surface>, +libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  match image:
    case None{}: setup.failed(core, frame)
    case Some{i}: setup.copied(libm, core, frame, J.Surface.copy(i))

# After InitWindow(800, 450): canvasImage = GenImageColor(CANVAS_SIZE, CANVAS_SIZE, RAYWHITE), its texture and the sphere.
def setup(+libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.image(J.Surface.create(512, 512, J.Color.RAYWHITE()), libm, core, frame)

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - mesh uv painting", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
