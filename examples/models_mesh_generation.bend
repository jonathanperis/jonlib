# raylib [models] example - mesh generation, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_mesh_generation.c
# (zlib/libpng, Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# Nine models from generated meshes (plane, cube, sphere, hemisphere,
# cylinder, torus, knot, polygon and a triangle built by hand) with a 2x2
# red and green checked texture, one drawn at a time under an orbital
# camera; a left click or RIGHT shows the next one, LEFT the one before. The
# sphere is generated before the hemisphere, so the hemisphere takes
# par_shapes' degenerate-triangle area as GenMeshSphere leaves it. The
# curved meshes need the libm profile's sinf/cosf, the cylinder's disks and
# the knot its binary64 cos and sin, and the weld glibc's qsort
# (docs/MODELS.md); the perspective needs its binary64 tan
# (docs/PERSPECTIVE.md). A frame is refused where a mesh was not generated.
# See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: the texture and the nine meshes were made and no refusal so far.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, models: +List<J.Model>, textures: List<J.Texture>, current: U32}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{5.0, 5.0, 5.0}, M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# currentModel after a left click ((current + 1)%9), then RIGHT (the next, 0
# after the last) or else LEFT (the one before, the last before the first).
def chosen(+core: J.Core, +current: U32) -> U32:
  +clicked = Bool.pick(U32, J.Input.is_mouse_button_pressed(core, 0), ((current + 1) % 9 : U32), current)
  Bool.pick(U32, J.Input.is_key_pressed(core, 262), Bool.pick(U32, (clicked >= 8 : U32), 0, (clicked + 1 : U32)),
    Bool.pick(U32, J.Input.is_key_pressed(core, 263), Bool.pick(U32, U32.is_eq(clicked, 0), 8, (clicked - 1 : U32)), clicked))

def update.moved(updated: Maybe<J.Camera3D>, +core: J.Core, +models: +List<J.Model>, textures: List<J.Texture>, +current: U32) -> State:
  match updated:
    case None{}: State{False{}, None{}, models, textures, current}
    case Some{+c}: State{True{}, Some{c}, models, textures, chosen(core, current)}

# UpdateCamera(&camera, CAMERA_ORBITAL), then the click and the keys.
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +models: +List<J.Model>, textures: List<J.Texture>, +current: U32) -> State:
  match valid camera:
    case True{} Some{+c}: update.moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()), core, models, textures, current)
    case _ None{}: State{False{}, None{}, models, textures, current}
    case False{} Some{+c}: State{False{}, Some{c}, models, textures, current}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +models, textures, +current} = state
  (core, update.live(valid, camera, libm, core, models, textures, current))

def model.first(models: +List<J.Model>) -> J.Model:
  match models:
    case Con{model, _}: model
    case Nil{}: J.Model.empty()

# models[currentModel].
def model.at(models: +List<J.Model>, +index: U32) -> J.Model:
  model.first(List.drop(&2, J.Model, models, U32.to_nat(index)))

def label(current: U32, frame: J.Frame) -> J.Frame:
  match current:
    case 0: J.Draw.text(frame, "PLANE", 680.0, 10.0, 20.0, J.Color.DARKBLUE())
    case 1: J.Draw.text(frame, "CUBE", 680.0, 10.0, 20.0, J.Color.DARKBLUE())
    case 2: J.Draw.text(frame, "SPHERE", 680.0, 10.0, 20.0, J.Color.DARKBLUE())
    case 3: J.Draw.text(frame, "HEMISPHERE", 640.0, 10.0, 20.0, J.Color.DARKBLUE())
    case 4: J.Draw.text(frame, "CYLINDER", 680.0, 10.0, 20.0, J.Color.DARKBLUE())
    case 5: J.Draw.text(frame, "TORUS", 680.0, 10.0, 20.0, J.Color.DARKBLUE())
    case 6: J.Draw.text(frame, "KNOT", 680.0, 10.0, 20.0, J.Color.DARKBLUE())
    case 7: J.Draw.text(frame, "POLY", 680.0, 10.0, 20.0, J.Color.DARKBLUE())
    case 8: J.Draw.text(frame, "Custom (triangle)", 580.0, 10.0, 20.0, J.Color.DARKBLUE())
    case _: frame

# DrawGrid(10, 1.0); EndMode3D(); the box, its outline, the help and the model's name.
def draw.model(+core: J.Core, +camera: J.Camera3D, +models: +List<J.Model>, +current: U32, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = J.Draw.rectangle(J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0)), 30.0, 400.0, 310.0, 30.0, J.Color.with_alpha(J.Color.SKYBLUE(), 0.5))
  f2 = J.Draw.rectangle_lines(f1, 30.0, 400.0, 310.0, 30.0, J.Color.with_alpha(J.Color.DARKBLUE(), 0.5))
  (core, (State{True{}, Some{camera}, models, textures, current}, label(current, J.Draw.text(f2, "MOUSE LEFT BUTTON to CYCLE PROCEDURAL MODELS", 40.0, 410.0, 10.0, J.Color.BLUE()))))

# DrawModel(models[currentModel], (0, 0, 0), 1.0f, WHITE).
def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +models: +List<J.Model>, textures: List<J.Texture>, +current: U32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.model(core, c, models, current,
      J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures, model.at(models, current), M.Vector3.zero(), 1.0, J.Color.WHITE()))
    case _ None{}: (core, (State{False{}, None{}, models, textures, current}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, models, textures, current}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +models, textures, +current} = state
  draw.at(valid, camera, libm, core, models, textures, current, frame)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# GenMeshCustom: one triangle with normals and texture coordinates, uploaded.
def custom() -> J.Mesh:
  J.Mesh.upload(J.Mesh{3, 1, Some{[0.0, 0.0, 0.0, 1.0, 0.0, 2.0, 2.0, 0.0, 0.0]}, Some{[0.0, 0.0, 0.5, 1.0, 1.0, 0.0]}, None{}, Some{[0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0]}, None{}, None{}, None{}, None{}}, False{})

# models[i].materials[0].maps[MATERIAL_MAP_DIFFUSE].texture = texture.
def textured.material(+info: J.TextureInfo, materials: +List<J.Material>) -> +List<J.Material>:
  match materials:
    case Con{+m, rest}: Con{Maybe.default(&1, J.Material, J.Material.set_texture(m, 0, info), m), rest}
    case Nil{}: Nil{}

def textured(model: J.Model, +info: J.TextureInfo) -> J.Model:
  J.Model{transform, meshes, +materials, ids} = model
  J.Model{transform, meshes, textured.material(info, materials), ids}

# The models made so far (reversed) and whether every mesh was generated.
type Built is Data:
  Built{ok: Bool, models: +List<J.Model>}

def built.with(acc: Built, +model: J.Model, +made: Bool) -> Built:
  Built{ok, models} = acc
  Built{ok && made, Con{model, models}}

# LoadModelFromMesh of a generated mesh, with the texture.
def built(mesh: Maybe<J.Mesh>, +info: J.TextureInfo, acc: Built) -> Built:
  match mesh:
    case None{}: built.with(acc, J.Model.empty(), False{})
    case Some{+m}: built.with(acc, textured(J.Model.from_mesh(m), info), True{})

# GenMeshPlane(2, 2, 4, 3), GenMeshCube(2, 1, 2), GenMeshSphere(2, 32, 32), GenMeshHemiSphere(2, 16, 16),
# GenMeshCylinder(1, 2, 16), GenMeshTorus(0.25, 4, 16, 32), GenMeshKnot(1, 2, 16, 128), GenMeshPoly(5, 2), GenMeshCustom().
def models(+libm: M.Libm, +info: J.TextureInfo) -> Built:
  b0 = built(J.Mesh.gen_plane(2.0, 2.0, 4, 3), info, Built{True{}, Nil{}})
  b1 = built(Some{J.Mesh.gen_cube(2.0, 1.0, 2.0)}, info, b0)
  b2 = built(J.Mesh.gen_sphere_for(M.Uncontracted{}, libm, 2.0, 32, 32), info, b1)
  b3 = built(J.Mesh.gen_hemi_sphere_for(M.Uncontracted{}, libm, True{}, 2.0, 16, 16), info, b2)
  b4 = built(J.Mesh.gen_cylinder_for(M.Uncontracted{}, libm, 1.0, 2.0, 16), info, b3)
  b5 = built(J.Mesh.gen_torus_for(M.Uncontracted{}, libm, 0.25, 4.0, 16, 32), info, b4)
  b6 = built(J.Mesh.gen_knot_for(M.Uncontracted{}, libm, 1.0, 2.0, 16, 128), info, b5)
  b7 = built(J.Mesh.gen_poly_for(libm, 5, 2.0), info, b6)
  built(Some{custom()}, info, b7)

def setup.models(made: Built, +core: J.Core, frame: J.Frame, texture: J.Texture) -> J.Core & (J.Frame & State):
  Built{+ok, +models} = made
  (J.Core.set_target_fps(core, 60), (frame, State{ok, Some{start()}, List.reverse(&2, J.Model, models), [texture], 0}))

def setup.texture(+libm: M.Libm, +core: J.Core, frame: J.Frame, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  setup.models(models(libm, info), core, frame, texture)

def setup.failed(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{False{}, Some{start()}, Nil{}, Nil{}, 0}))

def setup.uploaded(+libm: M.Libm, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: setup.failed(core, frame)
    case Some{t}: setup.texture(libm, core, frame, J.Texture.info(t))

def setup.image(image: Maybe<J.Surface>, +libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  match image:
    case None{}: setup.failed(core, frame)
    case Some{i}: setup.uploaded(libm, core, J.Texture.load_from_image(frame, i))

# After InitWindow(800, 450): GenImageChecked(2, 2, 1, 1, RED, GREEN) as a texture, the nine models, SetTargetFPS(60).
def setup(+libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.image(J.Surface.create_checked(2, 2, 1, 1, J.Color.RED(), J.Color.GREEN()), libm, core, frame)

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - mesh generation", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
