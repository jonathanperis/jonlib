# raylib [models] example - yaw pitch roll, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_yaw_pitch_roll.c
# (zlib/libpng, Copyright (c) 2017-2025 Berni (@Berni8k) and Ramon
# Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# An OBJ plane model whose transform is MatrixRotateXYZ of a pitch (UP and
# DOWN), a yaw (A and S) and a roll (LEFT and RIGHT) that ease back when the
# keys are released. The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md) and the rotation its sinf/cosf (docs/SINCOSF.md).
# LoadTexture of a .png is the PNG loader (Surface.load_png). See
# docs/MODELS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: the model and its texture loaded; textures: the model's own and the diffuse texture.
type State is Type:
  State{valid: Bool, model: J.Model, textures: List<J.Texture>, pitch: F32, roll: F32, yaw: F32}

def camera() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.0, 50.0, F32.neg(120.0)}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 30.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# A key adds or subtracts its step; without one the angle eases back by ease while beyond band.
def steered(+more: Bool, +less: Bool, +step: F32, +ease: F32, +band: F32, +angle: F32) -> F32:
  Bool.pick(F32, more, (angle + step : F32), Bool.pick(F32, less, (angle - step : F32),
    Bool.pick(F32, (angle > band : F32), (angle - ease : F32), Bool.pick(F32, (angle < F32.neg(band) : F32), (angle + ease : F32), angle))))

# model.transform = MatrixRotateXYZ((DEG2RAD*pitch, DEG2RAD*yaw, DEG2RAD*roll)).
def turned(+libm: M.Libm, +model: J.Model, +pitch: F32, +yaw: F32, +roll: F32) -> J.Model:
  J.Model{_, +meshes, +materials, +ids} = model
  J.Model{M.Matrix.rotate_xyz_for(libm, M.Vector3{(M.Math.DEG2RAD() * pitch : F32), (M.Math.DEG2RAD() * yaw : F32), (M.Math.DEG2RAD() * roll : F32)}), meshes, materials, ids}

# DOWN/UP pitch by 0.6 (easing 0.3 beyond 0.3); S/A yaw and LEFT/RIGHT roll by 1 (easing 0.5).
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +model, textures, +pitch, +roll, +yaw} = state
  +p = steered(J.Input.is_key_down(core, J.KeyboardKey.KEY_DOWN()), Bool.not(J.Input.is_key_down(core, J.KeyboardKey.KEY_DOWN())) && J.Input.is_key_down(core, J.KeyboardKey.KEY_UP()), 0.6, 0.3, 0.3, pitch)
  +y = steered(Bool.not(J.Input.is_key_down(core, J.KeyboardKey.KEY_S())) && J.Input.is_key_down(core, J.KeyboardKey.KEY_A()), J.Input.is_key_down(core, J.KeyboardKey.KEY_S()), 1.0, 0.5, 0.0, yaw)
  +r = steered(Bool.not(J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT())) && J.Input.is_key_down(core, J.KeyboardKey.KEY_RIGHT()), J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT()), 1.0, 0.5, 0.0, roll)
  (core, State{valid, turned(libm, model, p, y, r), textures, p, r, y})

def panel(frame: J.Frame) -> J.Frame:
  f1 = J.Draw.rectangle(frame, 30.0, 370.0, 260.0, 70.0, J.Color.with_alpha(J.Color.GREEN(), 0.5))
  f2 = J.Draw.rectangle_lines(f1, 30.0, 370.0, 260.0, 70.0, J.Color.with_alpha(J.Color.DARKGREEN(), 0.5))
  f3 = J.Draw.text(f2, "Pitch controlled with: KEY_UP / KEY_DOWN", 40.0, 380.0, 10.0, J.Color.DARKGRAY())
  f4 = J.Draw.text(f3, "Roll controlled with: KEY_LEFT / KEY_RIGHT", 40.0, 400.0, 10.0, J.Color.DARKGRAY())
  f5 = J.Draw.text(f4, "Yaw controlled with: KEY_A / KEY_S", 40.0, 420.0, 10.0, J.Color.DARKGRAY())
  J.Draw.text(f5, "(c) WWI Plane Model created by GiaHanLam", (800.0 - 240.0 : F32), (450.0 - 20.0 : F32), 10.0, J.Color.DARKGRAY())

# DrawGrid(10, 10.0f); EndMode3D(); the help panel.
def draw.model(+core: J.Core, +model: J.Model, +pitch: F32, +roll: F32, +yaw: F32, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  (core, (State{True{}, model, textures, pitch, roll, yaw}, panel(J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 10.0)))))

# DrawModel(model, (0, -8, 0), 1.0f, WHITE).
def draw.at(valid: Bool, +libm: M.Libm, +core: J.Core, +model: J.Model, +pitch: F32, +roll: F32, +yaw: F32, frame: J.Frame, textures: List<J.Texture>) -> J.Core & (State & J.Frame):
  match valid:
    case False{}: (core, (State{False{}, model, textures, pitch, roll, yaw}, J.Frame.refuse(frame)))
    case True{}: draw.model(core, model, pitch, roll, yaw, J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera()), textures, model,
      M.Vector3{0.0, F32.neg(8.0), 0.0}, 1.0, J.Color.WHITE()))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +model, textures, +pitch, +roll, +yaw} = state
  draw.at(valid, libm, core, model, pitch, roll, yaw, frame, textures)

# The main loop's body; libm is the profile of MatrixRotateXYZ's sinf/cosf and the perspective tan.
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

def setup.done(+core: J.Core, frame: J.Frame, +valid: Bool, +model: J.Model, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{valid, model, textures, 0.0, 0.0, 0.0}))

# SetTextureWrap(texture, TEXTURE_WRAP_REPEAT) before the assignment.
def setup.texture(+core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  setup.done(core, frame, True{}, textured(model, info), List.append(&1, J.Texture, textures, [J.Texture.set_wrap(texture, J.TextureWrap.TEXTURE_WRAP_REPEAT())]))

def setup.uploaded(+core: J.Core, +model: J.Model, textures: List<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: setup.done(core, frame, False{}, model, textures)
    case Some{t}: setup.texture(core, frame, model, textures, J.Texture.info(t))

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# texture = LoadTexture("resources/models/obj/plane_diffuse.png").
def setup.model(+dir: String, +core: J.Core, frame: J.Frame, loaded: J.LoadedModel) -> IO(J.Core & (J.Frame & State)):
  J.LoadedModel{+model, textures} = loaded
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/models/obj/plane_diffuse.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.uploaded(core, model, textures, upload(frame, result))))

def setup.loaded(+dir: String, +core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), setup.done(core, frame, False{}, J.Model.empty(), Nil{}))
    case Done{loaded}: setup.model(dir, core, frame, loaded)

# After InitWindow(800, 450): LoadModel("resources/models/obj/plane.obj"), its texture, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ "resources/models/obj/plane.obj"),
    r => setup.loaded(dir, core, r))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - yaw pitch roll", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
