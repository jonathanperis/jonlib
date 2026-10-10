# raylib [models] example - loading, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_loading.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# An OBJ castle (LoadModel) with its diffuse texture under an orbital
# camera; a left click selects it when the mouse ray hits the first mesh's
# bounding box (GetMeshBoundingBox, GetScreenToWorldRay, GetRayCollisionBox)
# and draws the box. The example also loads a dropped model or texture;
# J.Program's update cannot load files, so a frame with dropped files is
# refused, as is one whose ray or collision Jonlib refuses. The perspective
# needs the libm profile's binary64 tan (docs/PERSPECTIVE.md) and
# UpdateCamera its sinf/cosf (docs/SINCOSF.md). LoadTexture of a .png is the
# PNG loader (Surface.load_png). See docs/MODELS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: everything loaded and no refusal so far; textures: the model's own and the diffuse texture.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>, bounds: J.BoundingBox, selected: Bool}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{50.0, 50.0, 50.0}, M.Vector3{0.0, 12.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def hit.at(collision: Maybe<J.RayCollision>) -> Maybe<Bool>:
  match collision:
    case None{}: None{}
    case Some{J.RayCollision{+hit, _, _, _}}: Some{hit}

# GetRayCollisionBox(GetScreenToWorldRay(GetMousePosition(), camera), bounds).hit.
def hit(+libm: M.Libm, +bounds: J.BoundingBox, ray: Maybe<J.Ray>) -> Maybe<Bool>:
  match ray:
    case None{}: None{}
    case Some{+r}: hit.at(J.Collision.ray_box_for(M.Uncontracted{}, libm, r, bounds))

# A hit toggles the selection, a miss clears it.
def update.picked(+valid: Bool, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +bounds: J.BoundingBox, +selected: Bool, hit: Maybe<Bool>) -> State:
  match hit:
    case None{}: State{False{}, Some{camera}, model, textures, bounds, selected}
    case Some{+h}: State{valid, Some{camera}, model, textures, bounds, h && Bool.not(selected)}

def update.clicked(click: Bool, +libm: M.Libm, +core: J.Core, +valid: Bool, +model: J.Model, textures: List<J.Texture>, +bounds: J.BoundingBox, +selected: Bool, +camera: J.Camera3D) -> State:
  match click:
    case False{}: State{valid, Some{camera}, model, textures, bounds, selected}
    case True{}: update.picked(valid, camera, model, textures, bounds, selected,
      hit(libm, bounds, J.Camera.screen_to_world_ray_for(M.Uncontracted{}, libm, J.Input.get_mouse_position(core), camera, core)))

def update.moved(+libm: M.Libm, +core: J.Core, +valid: Bool, +model: J.Model, textures: List<J.Texture>, +bounds: J.BoundingBox, +selected: Bool, updated: Maybe<J.Camera3D>) -> State:
  match updated:
    case None{}: State{False{}, None{}, model, textures, bounds, selected}
    case Some{+c}: update.clicked(J.Input.is_mouse_button_pressed(core, 0), libm, core, valid, model, textures, bounds, selected, c)

def update.camera(+libm: M.Libm, +core: J.Core, +valid: Bool, +model: J.Model, textures: List<J.Texture>, +bounds: J.BoundingBox, +selected: Bool, camera: +Maybe<J.Camera3D>) -> State:
  match camera:
    case None{}: State{False{}, None{}, model, textures, bounds, selected}
    case Some{+c}: update.moved(libm, core, valid, model, textures, bounds, selected, J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()))

# UpdateCamera(CAMERA_ORBITAL); dropped files refuse; a left click picks.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +model, textures, +bounds, +selected} = state
  (core, update.camera(libm, core, valid && Bool.not(J.Core.is_file_dropped(core)), model, textures, bounds, selected, camera))

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# if (selected) DrawBoundingBox(bounds, GREEN).
def boxed(selected: Bool, +bounds: J.BoundingBox, frame: J.Frame) -> J.Frame:
  match selected:
    case False{}: frame
    case True{}: J.Draw.bounding_box(frame, bounds, J.Color.GREEN())

# if (selected) DrawText("MODEL SELECTED", GetScreenWidth() - 110, 10, 10, GREEN).
def labeled(selected: Bool, frame: J.Frame) -> J.Frame:
  match selected:
    case False{}: frame
    case True{}: J.Draw.text(frame, "MODEL SELECTED", (800.0 - 110.0 : F32), 10.0, 10.0, J.Color.GREEN())

# DrawGrid(20, 10.0f); the selection box; EndMode3D(); the texts and the frame rate.
def draw.model(+core: J.Core, +camera: J.Camera3D, +model: J.Model, +bounds: J.BoundingBox, +selected: Bool, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = J.Frame.end_mode_3d(boxed(selected, bounds, J.Draw.grid(frame, 20.0, 10.0)))
  f2 = labeled(selected, J.Draw.text(f1, "Drag & drop model to load mesh/texture.", 10.0, (450.0 - 20.0 : F32), 10.0, J.Color.DARKGRAY()))
  draw.fps.done(State{True{}, Some{camera}, model, textures, bounds, selected},
    J.Draw.text(f2, "(c) Castle 3D model by Alberto Cano", (800.0 - 200.0 : F32), (450.0 - 20.0 : F32), 10.0, J.Color.GRAY()), J.Core.get_fps(core, J.Core.get_time(core)), core)

# DrawModel(model, (0, 0, 0), 1.0f, WHITE).
def draw.at(valid: Bool, +libm: M.Libm, +core: J.Core, +model: J.Model, +bounds: J.BoundingBox, +selected: Bool, frame: J.Frame, textures: List<J.Texture>, camera: +Maybe<J.Camera3D>) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.model(core, c, model, bounds, selected, J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures, model,
      M.Vector3.zero(), 1.0, J.Color.WHITE()))
    case _ None{}: (core, (State{False{}, None{}, model, textures, bounds, selected}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, model, textures, bounds, selected}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +model, textures, +bounds, +selected} = state
  draw.at(valid, libm, core, model, bounds, selected, frame, textures, camera)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf, the ray's and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# model.materials[0].maps[MATERIAL_MAP_DIFFUSE].texture = texture.
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
  (J.Core.set_target_fps(core, 60), (frame, State{valid, Some{start()}, model, textures, bounds, False{}}))

def setup.bounded(+core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, bounds: Maybe<J.BoundingBox>) -> J.Core & (J.Frame & State):
  match bounds:
    case None{}: setup.done(core, frame, False{}, model, textures, empty())
    case Some{+b}: setup.done(core, frame, True{}, model, textures, b)

# bounds = GetMeshBoundingBox(model.meshes[0]).
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

# texture = LoadTexture("resources/models/obj/castle_diffuse.png").
def setup.model(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame, loaded: J.LoadedModel) -> IO(J.Core & (J.Frame & State)):
  J.LoadedModel{+model, textures} = loaded
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/models/obj/castle_diffuse.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.uploaded(libm, core, model, textures, upload(frame, result))))

def setup.loaded(+libm: M.Libm, +dir: String, +core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), setup.done(core, frame, False{}, J.Model.empty(), Nil{}, empty()))
    case Done{loaded}: setup.model(libm, dir, core, frame, loaded)

# After InitWindow(800, 450): LoadModel("resources/models/obj/castle.obj"), its texture and bounds, SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ "resources/models/obj/castle.obj"),
    r => setup.loaded(libm, dir, core, r))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - loading", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
