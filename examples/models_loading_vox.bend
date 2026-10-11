# raylib [models] example - loading vox, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_loading_vox.c (zlib/libpng,
# Copyright (c) 2021-2025 Johann Nadalutti (@procfxgen) and Ramon Santamaria
# (@raysan5)); see LICENSES/raylib.txt.
#
# Four MagicaVoxel models (LoadModel of .vox files: a knight, a sword, a
# monument and a village, the last two in three meshes each), each moved by
# its transform so that its bounding box is centered on X and Z, drawn one
# at a time: a left click shows the next. The camera is UpdateCameraPro's:
# W/S or UP/DOWN move it forward and back, D/A or RIGHT/LEFT sideways, the
# middle button turns it with the mouse and the wheel zooms. The example
# lights the models with a voxel lighting shader and four point lights; the
# reference's software renderer runs no shader (docs/SHADERS.md), so the
# models are drawn in their palette colors and the lights are the four gray
# spheres that mark them (CreateLight enables each: DrawSphereEx). The
# example also logs how long each model took to load, which nothing here
# reads. The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md), UpdateCameraPro and the spheres its sinf/cosf
# (docs/SINCOSF.md), the bounding boxes its fminf/fmaxf. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: the four models loaded and no refusal so far. current is currentModel.
type State is Data:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, models: +List<J.Model>, current: U32}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{10.0, 10.0, 10.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# voxFileNames[index].
def file(index: U32) -> String:
  match index:
    case 0: "resources/models/vox/chr_knight.vox"
    case 1: "resources/models/vox/chr_sword.vox"
    case 2: "resources/models/vox/monu9.vox"
    case _: "resources/models/vox/fez.vox"

def pick.first(items: +List<J.Model>) -> J.Model:
  match items:
    case Con{+item, _}: item
    case Nil{}: J.Model.empty()

# models[index].
def pick(+items: +List<J.Model>, +index: U32) -> J.Model:
  pick.first(List.drop(&2, J.Model, items, U32.to_nat(index)))

# (IsKeyDown(a) || IsKeyDown(b))*0.1f - (IsKeyDown(c) || IsKeyDown(d))*0.1f.
def axis(+core: J.Core, +a: U32, +b: U32, +c: U32, +d: U32) -> F32:
  (Bool.pick(F32, J.Input.is_key_down(core, a) || J.Input.is_key_down(core, b), 0.1, 0.0) - Bool.pick(F32, J.Input.is_key_down(core, c) || J.Input.is_key_down(core, d), 0.1, 0.0) : F32)

# camerarot: the mouse delta times 0.05 while the middle button is down.
def turn(+held: Bool, delta: M.Vector2) -> M.Vector3:
  M.Vector2{+x, +y} = delta
  Bool.pick(M.Vector3, held, M.Vector3{(x * 0.05 : F32), (y * 0.05 : F32), 0.0}, M.Vector3.zero())

def update.moved(moved: Maybe<J.Camera3D>, +core: J.Core, +models: +List<J.Model>, +current: U32) -> State:
  match moved:
    case None{}: State{False{}, None{}, models, current}
    case Some{+c}: State{True{}, Some{c}, models, Bool.pick(U32, J.Input.is_mouse_button_pressed(core, 0), ((current + 1) % 4 : U32), current)}

# UpdateCameraPro(&camera, movement, camerarot, GetMouseWheelMove()*-2.0f), then a left click cycles the models.
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +models: +List<J.Model>, +current: U32) -> State:
  match valid camera:
    case True{} Some{+c}:
      update.moved(J.Camera.update_pro_for(M.Uncontracted{}, libm, c, M.Vector3{axis(core, 87, 265, 83, 264), axis(core, 68, 262, 65, 263), 0.0}, turn(J.Input.is_mouse_button_down(core, 2), J.Input.get_mouse_delta(core)),
        (J.Input.get_mouse_wheel_move(core) * F32.neg(2.0) : F32)), core, models, current)
    case _ _: State{False{}, None{}, models, current}

def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+valid, +camera, +models, +current} = state
  (core, update.live(valid, camera, libm, core, models, current))

def drawn(r: J.Frame & List<J.Texture>) -> J.Frame:
  (frame, _) = r
  frame

# if (lights[i].enabled) DrawSphereEx(lights[i].position, 0.2f, 8, 8, lights[i].color): the four lights are enabled.
def light(+libm: M.Libm, frame: J.Frame, +x: F32, +y: F32, +z: F32) -> J.Frame:
  J.Draw.sphere_ex_for(libm, frame, M.Vector3{x, y, z}, 0.2, 8.0, 8.0, J.Color.GRAY())

def draw.scene(+libm: M.Libm, +camera: J.Camera3D, +model: J.Model, +current: U32, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.grid(drawn(J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera), Nil{}, model, M.Vector3.zero(), 1.0, J.Color.WHITE())), 10.0, 1.0)
  f2 = light(libm, light(libm, light(libm, light(libm, f1, F32.neg(20.0), 20.0, F32.neg(20.0)), 20.0, F32.neg(20.0), 20.0), F32.neg(20.0), 20.0, 20.0), 20.0, F32.neg(20.0), F32.neg(20.0))
  f3 = J.Draw.rectangle_lines(J.Draw.rectangle(J.Frame.end_mode_3d(f2), 10.0, 40.0, 340.0, 70.0, J.Color.with_alpha(J.Color.SKYBLUE(), 0.5)), 10.0, 40.0, 340.0, 70.0, J.Color.with_alpha(J.Color.DARKBLUE(), 0.5))
  f4 = J.Draw.text(J.Draw.text(f3, "- MOUSE LEFT BUTTON: CYCLE VOX MODELS", 20.0, 50.0, 10.0, J.Color.BLUE()), "- MOUSE MIDDLE BUTTON: ZOOM OR ROTATE CAMERA", 20.0, 70.0, 10.0, J.Color.BLUE())
  J.Draw.text(J.Draw.text(f4, "- UP-DOWN-LEFT-RIGHT KEYS: MOVE CAMERA", 20.0, 90.0, 10.0, J.Color.BLUE()), "VOX model file: " ++ J.Files.name(file(current)), 10.0, 10.0, 20.0, J.Color.GRAY())

def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +models: +List<J.Model>, +current: U32, frame: J.Frame) -> J.Frame:
  match valid camera:
    case True{} Some{+c}: draw.scene(libm, c, pick(models, current), current, frame)
    case _ _: J.Frame.refuse(frame)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +models, +current} = state
  (core, (state, draw.at(valid, camera, libm, models, current, frame)))

# The main loop's body; libm is the profile of UpdateCameraPro's and the spheres' sinf/cosf and of the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# center.x = bb.min.x + ((bb.max.x - bb.min.x)/2), center.z likewise; models[i].transform = MatrixTranslate(-center.x, 0, -center.z).
def centered(box: Maybe<J.BoundingBox>, +model: J.Model) -> Maybe<J.Model>:
  match box:
    case None{}: None{}
    case Some{J.BoundingBox{M.Vector3{+ax, _, +az}, M.Vector3{+bx, _, +bz}}}:
      J.Model{_, +meshes, +materials, +indices} = model
      Some{J.Model{M.Matrix.translate(F32.neg((ax + ((bx - ax) / 2.0) : F32)), 0.0, F32.neg((az + ((bz - az) / 2.0) : F32))), meshes, materials, indices}}

# models[i] = LoadModel(voxFileNames[i]) with its transform; None when the model does not load or has no box.
def loaded(r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, +libm: M.Libm) -> J.Frame & Maybe<J.Model>:
  match r:
    case Tuple{frame, Fail{_}}: (frame, None{})
    case Tuple{frame, Done{J.LoadedModel{+model, _}}}: (frame, centered(J.Model.bounding_box_for(M.Uncontracted{}, libm, model), model))

def setup.failed(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{False{}, None{}, Nil{}, 0}))

def setup.fourth(r: J.Frame & Maybe<J.Model>, +core: J.Core, +a: J.Model, +b: J.Model, +c: J.Model) -> J.Core & (J.Frame & State):
  match r:
    case Tuple{frame, None{}}: setup.failed(core, frame)
    case Tuple{frame, Some{+d}}: (J.Core.set_target_fps(core, 60), (frame, State{True{}, Some{start()}, [a, b, c, d], 0}))

def setup.third(r: J.Frame & Maybe<J.Model>, +libm: M.Libm, +dir: String, +core: J.Core, +a: J.Model, +b: J.Model) -> IO(J.Core & (J.Frame & State)):
  match r:
    case Tuple{frame, None{}}: IO.pure(J.Core & (J.Frame & State), setup.failed(core, frame))
    case Tuple{frame, Some{+c}}:
      IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ file(3)), x => IO.pure(J.Core & (J.Frame & State), setup.fourth(loaded(x, libm), core, a, b, c)))

def setup.second(r: J.Frame & Maybe<J.Model>, +libm: M.Libm, +dir: String, +core: J.Core, +a: J.Model) -> IO(J.Core & (J.Frame & State)):
  match r:
    case Tuple{frame, None{}}: IO.pure(J.Core & (J.Frame & State), setup.failed(core, frame))
    case Tuple{frame, Some{+b}}:
      IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ file(2)), x => setup.third(loaded(x, libm), libm, dir, core, a, b))

def setup.first(r: J.Frame & Maybe<J.Model>, +libm: M.Libm, +dir: String, +core: J.Core) -> IO(J.Core & (J.Frame & State)):
  match r:
    case Tuple{frame, None{}}: IO.pure(J.Core & (J.Frame & State), setup.failed(core, frame))
    case Tuple{frame, Some{+a}}:
      IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ file(1)), x => setup.second(loaded(x, libm), libm, dir, core, a))

# After InitWindow(800, 450): the four models and their transforms (the shader and the lights change nothing
# drawn here), SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ file(0)), x => setup.first(loaded(x, libm), libm, dir, core))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - loading vox", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
