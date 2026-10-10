# raylib [models] example - mesh picking, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_mesh_picking.c (zlib/libpng,
# Copyright (c) 2017-2025 Joel Davis (@joeld42) and Ramon Santamaria (@raysan5));
# see LICENSES/raylib.txt.
#
# The mouse ray (GetScreenToWorldRay) against a ground quad, a triangle, a
# sphere and an OBJ turret: its first mesh's bounding box, then the meshes
# themselves (GetRayCollisionQuad, GetRayCollisionTriangle,
# GetRayCollisionSphere, GetRayCollisionBox, GetRayCollisionMesh). The
# closest hit gets a cursor cube with its normal, and its distance, point,
# normal and (for the triangle) Vector3Barycenter are printed. The right
# button toggles first-person camera controls. The perspective needs the
# libm profile's binary64 tan (docs/PERSPECTIVE.md) and UpdateCamera its
# sinf/cosf (docs/SINCOSF.md); a refused camera update, ray, box or mesh
# test refuses that frame and every later one. LoadTexture of a .png is the
# PNG loader (Surface.load_png). See docs/MODELS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The closest hit, hitObjectName (0 none, 1 ground, 2 triangle, 3 sphere, 4 box, 5 mesh) and cursorColor.
type Best is Data:
  Best{collision: J.RayCollision, object: U32, cursor: U32}

# inbox: boxHitInfo.hit; triangle: triHitInfo.hit.
type Pick is Data:
  Pick{ray: J.Ray, best: Best, inbox: Bool, triangle: Bool}

# ok: no refusal so far.
type Scene is Data:
  Scene{camera: J.Camera3D, pick: Pick, bary: M.Vector3, ok: Bool}

# textures: the model's own and the diffuse texture; bounds: towerBBox.
type State is Type:
  State{scene: Scene, model: J.Model, textures: List<J.Texture>, bounds: J.BoundingBox}

# A mesh test's result: ok is False when Jonlib refused it.
type Found is Data:
  Found{ok: Bool, collision: J.RayCollision}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{20.0, 20.0, 20.0}, M.Vector3{0.0, 8.0, 0.0}, M.Vector3{0.0, 1.6, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def float(word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# collision = { 0 } with distance = FLT_MAX (bits 0x7F7FFFFF), "None" and WHITE.
def none() -> Best:
  Best{J.RayCollision{False{}, float(2139095039), M.Vector3.zero(), M.Vector3.zero()}, 0, J.Color.WHITE()}

def idle() -> Pick:
  Pick{J.Ray{M.Vector3.zero(), M.Vector3.zero()}, none(), False{}, False{}}

# The test triangle.
def ta() -> M.Vector3:
  M.Vector3{F32.neg(25.0), 0.5, 0.0}

def tb() -> M.Vector3:
  M.Vector3{F32.neg(4.0), 2.5, 1.0}

def tc() -> M.Vector3:
  M.Vector3{F32.neg(8.0), 6.5, 0.0}

def struck(collision: J.RayCollision) -> Bool:
  J.RayCollision{+hit, _, _, _} = collision
  hit

def reach(collision: J.RayCollision) -> F32:
  J.RayCollision{_, +far, _, _} = collision
  far

def spot(collision: J.RayCollision) -> M.Vector3:
  J.RayCollision{_, _, +point, _} = collision
  point

# (info.hit) && (info.distance < collision.distance).
def nearer(+info: J.RayCollision, best: Best) -> Bool:
  Best{+collision, _, _} = best
  struck(info) && (reach(info) < reach(collision) : F32)

def taken(+take: Bool, +info: J.RayCollision, +object: U32, +color: U32, +best: Best) -> Best:
  Bool.pick(Best, take, Best{info, object, color}, best)

def mesh.tested(result: Maybe<J.RayCollision>) -> Found:
  match result:
    case None{}: Found{False{}, J.RayCollision.none()}
    case Some{+c}: Found{True{}, c}

def mesh.step(skip: Bool, +ray: J.Ray, +transform: M.Matrix, +mesh: J.Mesh, +found: Found) -> Found:
  match skip:
    case True{}: found
    case False{}: mesh.tested(J.Collision.ray_mesh_for(M.Uncontracted{}, ray, mesh, transform))

def mesh.settled(found: Found) -> Bool:
  Found{+ok, +collision} = found
  Bool.not(ok) || struck(collision)

# GetRayCollisionMesh(ray, tower.meshes[m], tower.transform) for each mesh, stopping at the first one hit.
def meshes.hit(meshes: +List<J.Mesh>, +ray: J.Ray, +transform: M.Matrix, +found: Found) -> Found:
  match meshes:
    case Nil{}: found
    case Con{+mesh, rest}: meshes.hit(rest, ray, transform, mesh.step(mesh.settled(found), ray, transform, mesh, found))

def tower.hit(model: J.Model, +ray: J.Ray) -> Found:
  J.Model{+transform, +meshes, _, _} = model
  meshes.hit(meshes, ray, transform, Found{True{}, J.RayCollision.none()})

# A mesh hit replaces the box hit ("Mesh", ORANGE).
def picked.mesh(+camera: J.Camera3D, +ray: J.Ray, +bary: M.Vector3, +triangle: Bool, +box: J.RayCollision, found: Found) -> Scene:
  Found{+ok, +collision} = found
  Scene{camera, Pick{ray, Bool.pick(Best, struck(collision), Best{collision, 5, J.Color.ORANGE()}, Best{box, 4, J.Color.ORANGE()}), True{}, triangle}, bary, ok}

# The meshes are tested only behind a box hit closer than the other objects.
def picked.box(take: Bool, +camera: J.Camera3D, +model: J.Model, +ray: J.Ray, +bary: M.Vector3, +triangle: Bool, +best: Best, +box: J.RayCollision) -> Scene:
  match take:
    case False{}: Scene{camera, Pick{ray, best, struck(box), triangle}, bary, True{}}
    case True{}: picked.mesh(camera, ray, bary, triangle, box, tower.hit(model, ray))

def picked.boxed(+camera: J.Camera3D, +model: J.Model, +ray: J.Ray, +bary: M.Vector3, +triangle: Bool, +best: Best, box: Maybe<J.RayCollision>) -> Scene:
  match box:
    case None{}: Scene{camera, Pick{ray, best, False{}, triangle}, bary, False{}}
    case Some{+b}: picked.box(nearer(b, best), camera, model, ray, bary, triangle, best, b)

# The ground quad, the triangle (its barycenter kept when it is the closest so far), the sphere, then the tower.
def picked(+libm: M.Libm, +camera: J.Camera3D, +model: J.Model, +bounds: J.BoundingBox, +bary: M.Vector3, +ray: J.Ray) -> Scene:
  +ground = J.Collision.ray_quad_for(M.Uncontracted{}, ray, M.Vector3{F32.neg(50.0), 0.0, F32.neg(50.0)}, M.Vector3{F32.neg(50.0), 0.0, 50.0}, M.Vector3{50.0, 0.0, 50.0},
    M.Vector3{50.0, 0.0, F32.neg(50.0)})
  +b1 = taken(nearer(ground, none()), ground, 1, J.Color.GREEN(), none())
  +tri = J.Collision.ray_triangle_for(M.Uncontracted{}, ray, ta(), tb(), tc())
  +closer = nearer(tri, b1)
  +b2 = taken(closer, tri, 2, J.Color.PURPLE(), b1)
  +sphere = J.Collision.ray_sphere_for(M.Uncontracted{}, ray, M.Vector3{F32.neg(30.0), 5.0, 5.0}, 4.0)
  picked.boxed(camera, model, ray, Bool.pick(M.Vector3, closer, M.Vector3.barycenter(spot(tri), ta(), tb(), tc()), bary), struck(tri),
    taken(nearer(sphere, b2), sphere, 3, J.Color.ORANGE(), b2), J.Collision.ray_box_for(M.Uncontracted{}, libm, ray, bounds))

def kept(+ok: Bool, scene: Scene) -> Scene:
  Scene{+camera, +pick, +bary, +fine} = scene
  Scene{camera, pick, bary, ok && fine}

# ray = GetScreenToWorldRay(GetMousePosition(), camera) and the tests.
def cast(+libm: M.Libm, +camera: J.Camera3D, +model: J.Model, +bounds: J.BoundingBox, +bary: M.Vector3, +pick: Pick, ray: Maybe<J.Ray>) -> Scene:
  match ray:
    case None{}: Scene{camera, pick, bary, False{}}
    case Some{+r}: picked(libm, camera, model, bounds, bary, r)

# The right button toggles the cursor (after the camera update, before the ray).
def camera.updated(+libm: M.Libm, +core: J.Core, +model: J.Model, +bounds: J.BoundingBox, +camera: J.Camera3D, +pick: Pick, +bary: M.Vector3, +ok: Bool,
    updated: Maybe<J.Camera3D>) -> J.Core & Scene:
  match updated:
    case None{}: (core, Scene{camera, pick, bary, False{}})
    case Some{+c}:
      +pressed = J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_RIGHT())
      +hidden = J.Input.is_cursor_hidden(core)
      +core2 = Bool.pick(J.Core, pressed, Bool.pick(J.Core, hidden, J.Input.enable_cursor(core), J.Input.disable_cursor(core)), core)
      (core2, kept(ok, cast(libm, c, model, bounds, bary, pick, J.Camera.screen_to_world_ray_for(M.Uncontracted{}, libm, J.Input.get_mouse_position(core2), c, core2))))

# if (IsCursorHidden()) UpdateCamera(&camera, CAMERA_FIRST_PERSON).
def camera.update(hidden: Bool, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D) -> Maybe<J.Camera3D>:
  match hidden:
    case False{}: Some{camera}
    case True{}: J.Camera.update_for(M.Uncontracted{}, libm, core, camera, J.CameraMode.CAMERA_FIRST_PERSON())

def update.scene(+libm: M.Libm, +core: J.Core, +model: J.Model, +bounds: J.BoundingBox, scene: Scene) -> J.Core & Scene:
  Scene{+camera, +pick, +bary, +ok} = scene
  camera.updated(libm, core, model, bounds, camera, pick, bary, ok, camera.update(J.Input.is_cursor_hidden(core), libm, core, camera))

def update.done(+model: J.Model, textures: List<J.Texture>, +bounds: J.BoundingBox, r: J.Core & Scene) -> J.Core & State:
  (core, +scene) = r
  (core, State{scene, model, textures, bounds})

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+scene, +model, textures, +bounds} = state
  update.done(model, textures, bounds, update.scene(libm, core, model, bounds, scene))

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# if (boxHitInfo.hit) DrawBoundingBox(towerBBox, LIME).
def box.drawn(inbox: Bool, +bounds: J.BoundingBox, frame: J.Frame) -> J.Frame:
  match inbox:
    case False{}: frame
    case True{}: J.Draw.bounding_box(frame, bounds, J.Color.LIME())

# if (collision.hit): the cursor cube at the hit point and its normal.
def cursor.drawn(hit: Bool, +point: M.Vector3, +normal: M.Vector3, +color: U32, frame: J.Frame) -> J.Frame:
  match hit:
    case False{}: frame
    case True{}: J.Draw.line_3d(J.Draw.cube_wires(J.Draw.cube(frame, point, 0.3, 0.3, 0.3, color), point, 0.3, 0.3, 0.3, J.Color.RED()), point, M.Vector3.add(point, normal),
      J.Color.RED())

def label(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 10.0, J.Color.BLACK())

def triple(+format: String, +v: M.Vector3) -> Maybe<String>:
  M.Vector3{+x, +y, +z} = v
  J.Text.format(format, [J.TextFloat{x}, J.TextFloat{y}, J.TextFloat{z}])

def object.name(object: U32) -> String:
  match object:
    case 0: "None"
    case 1: "Ground"
    case 2: "Triangle"
    case 3: "Sphere"
    case 4: "Box"
    case _: "Mesh"

# if (triHitInfo.hit && TextIsEqual(hitObjectName, "Triangle")): the barycenter.
def details.bary(shown: Bool, +bary: M.Vector3, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: label(triple("Barycenter: %3.2f %3.2f %3.2f", bary), 115.0, frame)

# if (collision.hit): the distance, the hit point and its normal from ypos = 70.
def details(hit: Bool, +far: F32, +point: M.Vector3, +normal: M.Vector3, +shown: Bool, +bary: M.Vector3, frame: J.Frame) -> J.Frame:
  match hit:
    case False{}: frame
    case True{}: details.bary(shown, bary, label(triple("Hit Norm: %3.2f %3.2f %3.2f", normal), 100.0, label(triple("Hit Pos: %3.2f %3.2f %3.2f", point), 85.0,
      label(J.Text.format("Distance: %3.2f", [J.TextFloat{far}]), 70.0, frame))))

# After DrawModel: the triangle, the sphere, the box, the cursor, DrawRay(ray, MAROON), DrawGrid(10, 10.0f); the texts.
def draw.scene(+libm: M.Libm, +core: J.Core, +scene: Scene, +model: J.Model, +bounds: J.BoundingBox, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  Scene{_, +pick, +bary, _} = scene
  Pick{+ray, +best, +inbox, +triangle} = pick
  Best{+collision, +object, +color} = best
  J.RayCollision{+hit, +far, +point, +normal} = collision
  (frame, textures) = r
  f1 = J.Draw.line_3d(J.Draw.line_3d(J.Draw.line_3d(frame, ta(), tb(), J.Color.PURPLE()), tb(), tc(), J.Color.PURPLE()), tc(), ta(), J.Color.PURPLE())
  f2 = box.drawn(inbox, bounds, J.Draw.sphere_wires_for(libm, f1, M.Vector3{F32.neg(30.0), 5.0, 5.0}, 4.0, 8.0, 8.0, J.Color.PURPLE()))
  f3 = J.Frame.end_mode_3d(J.Draw.grid(J.Draw.ray(cursor.drawn(hit, point, normal, color, f2), ray, J.Color.MAROON()), 10.0, 10.0))
  f4 = label(J.Text.format("Hit Object: %s", [J.TextString{object.name(object)}]), 50.0, f3)
  f5 = details(hit, far, point, normal, triangle && U32.is_eq(object, 2), bary, f4)
  f6 = J.Draw.text(f5, "Right click mouse to toggle camera controls", 10.0, 430.0, 10.0, J.Color.GRAY())
  draw.fps.done(State{scene, model, textures, bounds}, J.Draw.text(f6, "(c) Turret 3D model by Alberto Cano", (800.0 - 200.0 : F32), (450.0 - 20.0 : F32), 10.0, J.Color.GRAY()),
    J.Core.get_fps(core, J.Core.get_time(core)), core)

def lens(scene: Scene) -> J.Camera3D:
  Scene{+camera, _, _, _} = scene
  camera

def fine(scene: Scene) -> Bool:
  Scene{_, _, _, +ok} = scene
  ok

# DrawModel(tower, towerPos, 1.0f, WHITE).
def draw.at(ok: Bool, +libm: M.Libm, +core: J.Core, +scene: Scene, +model: J.Model, +bounds: J.BoundingBox, frame: J.Frame, textures: List<J.Texture>) -> J.Core & (State & J.Frame):
  match ok:
    case False{}: (core, (State{scene, model, textures, bounds}, J.Frame.refuse(frame)))
    case True{}: draw.scene(libm, core, scene, model, bounds, J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), lens(scene)), textures, model,
      M.Vector3.zero(), 1.0, J.Color.WHITE()))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+scene, +model, textures, +bounds} = state
  draw.at(fine(scene), libm, core, scene, model, bounds, frame, textures)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf, the ray's, the box test's and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# tower.materials[0].maps[MATERIAL_MAP_DIFFUSE].texture = texture.
def textured.material(+info: J.TextureInfo, materials: +List<J.Material>) -> +List<J.Material>:
  match materials:
    case Con{+m, rest}: Con{Maybe.default(&1, J.Material, J.Material.set_texture(m, 0, info), m), rest}
    case Nil{}: Nil{}

def textured(+model: J.Model, +info: J.TextureInfo) -> J.Model:
  J.Model{+transform, +meshes, +materials, +ids} = model
  J.Model{transform, meshes, textured.material(info, materials), ids}

def empty() -> J.BoundingBox:
  J.BoundingBox{M.Vector3.zero(), M.Vector3.zero()}

def setup.done(+core: J.Core, frame: J.Frame, +valid: Bool, +model: J.Model, textures: List<J.Texture>, +bounds: J.BoundingBox) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{Scene{start(), idle(), M.Vector3.zero(), valid}, model, textures, bounds}))

def setup.bounded(+core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, bounds: Maybe<J.BoundingBox>) -> J.Core & (J.Frame & State):
  match bounds:
    case None{}: setup.done(core, frame, False{}, model, textures, empty())
    case Some{+b}: setup.done(core, frame, True{}, model, textures, b)

# towerBBox = GetMeshBoundingBox(tower.meshes[0]).
def bounds(+libm: M.Libm, meshes: +List<J.Mesh>) -> Maybe<J.BoundingBox>:
  match meshes:
    case Nil{}: None{}
    case Con{+mesh, _}: J.Mesh.bounding_box_for(libm, mesh)

def setup.texture(+libm: M.Libm, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  J.Model{_, +meshes, _, _} = model
  (texture, +info) = r
  setup.bounded(core, frame, textured(model, info), List.append(&1, J.Texture, textures, [texture]), bounds(libm, meshes))

def setup.uploaded(+libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: setup.done(core, frame, False{}, model, textures, empty())
    case Some{t}: setup.texture(libm, core, frame, model, textures, J.Texture.info(t))

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# texture = LoadTexture("resources/models/obj/turret_diffuse.png").
def setup.model(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame, loaded: J.LoadedModel) -> IO(J.Core & (J.Frame & State)):
  J.LoadedModel{+model, textures} = loaded
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/models/obj/turret_diffuse.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.uploaded(libm, core, model, textures, upload(frame, result))))

def setup.loaded(+libm: M.Libm, +dir: String, +core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), setup.done(core, frame, False{}, J.Model.empty(), Nil{}, empty()))
    case Done{loaded}: setup.model(libm, dir, core, frame, loaded)

# After InitWindow(800, 450): LoadModel("resources/models/obj/turret.obj"), its texture and box, SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ "resources/models/obj/turret.obj"),
    r => setup.loaded(libm, dir, core, r))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - mesh picking", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
