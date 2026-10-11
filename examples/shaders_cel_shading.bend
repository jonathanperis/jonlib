# raylib [shaders] example - cel shading, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_cel_shading.c (zlib/libpng,
# Copyright (c) 2026 Gleb A (@ggrizzly)); see LICENSES/raylib.txt.
#
# The old car model (old_car_new.glb, LoadGLTF) under an orbital camera, drawn
# through a cel shader with an outline pass (the model again with front faces
# culled); Z and C toggle them, Q and E change the band count. On the software
# renderer shaders do not exist (docs/SHADERS.md): both passes draw the model
# in its material color, the uniforms of the cel shader, the outline and the
# light (rlights.h) are ignored, and only the cull face, the light's sphere
# and the text show the state, as in the reference. The camera's turn, the
# light's position (sinf/cosf of the clock) and the sphere need the libm
# profile, the perspective its binary64 tan (docs/PERSPECTIVE.md): a refusal
# marks the frame. See docs/MODELS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>, cel: Bool, outline: Bool, bands: F32, light: +Maybe<M.Vector3>}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{9.0, 6.0, 9.0}, M.Vector3{0.0, 1.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def moved(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def update.camera(camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()))

# E (pressed or repeating) adds a band and Q takes one: Clamp(numBands +/- 1.0f, 2.0f, 20.0f), E first.
def banded(+core: J.Core, +bands: F32) -> F32:
  +e = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_E()) || J.Input.is_key_pressed_repeat(core, J.KeyboardKey.KEY_E())
  +q = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_Q()) || J.Input.is_key_pressed_repeat(core, J.KeyboardKey.KEY_Q())
  +more = Bool.pick(F32, e, M.Math.clamp((bands + 1.0 : F32), 2.0, 20.0), bands)
  Bool.pick(F32, q, M.Math.clamp((more - 1.0 : F32), 2.0, 20.0), more)

def lit.at(s: Maybe<F32>, c: Maybe<F32>) -> +Maybe<M.Vector3>:
  match s c:
    case Some{+sv} Some{+cv}: Some{M.Vector3{(sv * 5.0 : F32), 5.0, (cv * 5.0 : F32)}}
    case _ _: None{}

# lights[0].position = (sinf(-t*0.3f)*5.0f, 5.0f, cosf(-t*0.3f)*5.0f) for t = (float)GetTime().
def lit(time: Maybe<F32>, +libm: M.Libm) -> +Maybe<M.Vector3>:
  match time:
    case None{}: None{}
    case Some{+t}: lit.at(M.Libm.sin(libm, (F32.neg(t) * 0.3 : F32)), M.Libm.cos(libm, (F32.neg(t) * 0.3 : F32)))

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+camera, +model, textures, +cel, +outline, +bands, _} = state
  +z = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_Z()), Bool.not(cel), cel)
  +c = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_C()), Bool.not(outline), outline)
  (core, State{update.camera(camera, libm, core), model, textures, z, c, banded(core, bands), lit(M.Float64.to_f32(J.Core.get_time(core)), libm)})

def draw.culled(r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  (frame, textures) = r
  (J.Rlgl.set_cull_face(frame, 1), textures)

# The outline pass: rlSetCullFace(RL_CULL_FACE_FRONT), DrawModel, rlSetCullFace(RL_CULL_FACE_BACK).
def draw.outlined(+model: J.Model, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  (frame, textures) = r
  draw.culled(J.Draw.model(J.Rlgl.set_cull_face(frame, 0), textures, model, M.Vector3.zero(), 0.75, J.Color.WHITE()))

def draw.outline(outline: Bool, +model: J.Model, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  match outline:
    case False{}: r
    case True{}: draw.outlined(model, r)

def draw.model(+model: J.Model, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  (frame, textures) = r
  J.Draw.model(frame, textures, model, M.Vector3.zero(), 0.75, J.Color.WHITE())

def draw.label(text: Maybe<String>, +y: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 20.0, color)

def on(+flag: Bool) -> String:
  Bool.pick(String, flag, "ON", "OFF")

def shade(+flag: Bool) -> U32:
  Bool.pick(U32, flag, J.Color.DARKGREEN(), J.Color.DARKGRAY())

def draw.texts(+cel: Bool, +outline: Bool, +bands: F32, frame: J.Frame) -> J.Frame:
  f1 = draw.label(J.Text.format("Cel: %s  [Z]", [J.TextString{on(cel)}]), 65.0, shade(cel), frame)
  f2 = draw.label(J.Text.format("Outline: %s  [C]", [J.TextString{on(outline)}]), 90.0, shade(outline), f1)
  draw.label(J.Text.format("Bands: %.0f  [Q/E]", [J.TextFloat{bands}]), 115.0, J.Color.DARKGRAY(), f2)

def draw.fps.at(state: State, +cel: Bool, +outline: Bool, +bands: F32, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, draw.texts(cel, outline, bands, J.Draw.fps(frame, 10.0, 10.0, fps))))

def draw.fps.done(state: State, +cel: Bool, +outline: Bool, +bands: F32, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, cel, outline, bands, frame, pair)

# DrawSphereEx(lights[0].position, 0.2f, 50, 50, YELLOW), DrawGrid(10, 10.0f), EndMode3D.
def draw.light(light: +Maybe<M.Vector3>, +libm: M.Libm, frame: J.Frame) -> J.Frame:
  match light:
    case None{}: J.Frame.end_mode_3d(J.Frame.refuse(frame))
    case Some{+position}: J.Frame.end_mode_3d(J.Draw.grid(J.Draw.sphere_ex_for(libm, frame, position, 0.2, 50.0, 50.0, J.Color.YELLOW()), 10.0, 10.0))

def draw.done(+libm: M.Libm, +core: J.Core, +camera: +Maybe<J.Camera3D>, +model: J.Model, +cel: Bool, +outline: Bool, +bands: F32, +light: +Maybe<M.Vector3>, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  draw.fps.done(State{camera, model, textures, cel, outline, bands, light}, cel, outline, bands, draw.light(light, libm, frame), J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.world(camera: +Maybe<J.Camera3D>, +libm: M.Libm, frame: J.Frame) -> J.Frame:
  match camera:
    case None{}: J.Frame.refuse(frame)
    case Some{+c}: J.Frame.begin_mode_3d_for(libm, frame, c)

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +model, textures, +cel, +outline, +bands, +light} = state
  draw.done(libm, core, camera, model, cel, outline, bands, light,
    draw.model(model, draw.outline(outline, model, (draw.world(camera, libm, J.Frame.clear_background(frame, J.Color.RAYWHITE())), textures))))

# The main loop's body; libm is the profile of UpdateCamera's and the light's sinf/cosf, the sphere's and BeginMode3D's tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def started(+core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{Some{start()}, model, textures, True{}, True{}, 10.0, None{}}))

def setup.loaded(+core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>) -> J.Core & (J.Frame & State):
  (frame, result) = r
  match result:
    case Fail{_}: started(core, frame, J.Model.empty(), Nil{})
    case Done{J.LoadedModel{+model, textures}}: started(core, frame, model, textures)

# After InitWindow(800, 450): LoadModel("resources/models/old_car_new.glb"), the shaders and the light (all
# without effect here), SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load_for(M.Uncontracted{}, frame, dir ++ "resources/models/old_car_new.glb"),
    r => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, r)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, J.ConfigFlags.FLAG_MSAA_4X_HINT(), "raylib [shaders] example - cel shading", 800, 450,
    J.Desktop.frames_arg(args), core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
