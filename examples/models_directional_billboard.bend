# raylib [models] example - directional billboard, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_directional_billboard.c
# (zlib/libpng, Copyright (c) 2025 Robin (@RobinsAviary)); see
# LICENSES/raylib.txt.
#
# A sprite sheet of four animation frames by eight directions drawn as a
# billboard under an orbital camera: the frame steps every half second and
# the row follows Vector2Angle of the camera's position around the sprite.
# The perspective needs the libm profile's binary64 tan (docs/PERSPECTIVE.md),
# UpdateCamera and DrawBillboardPro its sinf/cosf (docs/SINCOSF.md) and
# Vector2Angle its atan2f (docs/ANGLES.md); a refused UpdateCamera refuses
# the frame and every later one. LoadTexture of a .png is the PNG loader
# (Surface.load_png). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{camera: +Maybe<J.Camera3D>, bot: Maybe<J.Texture>, timer: F32, anim: U32}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{2.0, 1.0, 2.0}, M.Vector3{0.0, 0.5, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def camera.updated(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def camera.update(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: camera.updated(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()))

# UpdateCamera(CAMERA_ORBITAL); anim_timer += GetFrameTime(), a frame on
# past half a second, back to the first after the fourth.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+camera, bot, +timer, +anim} = state
  +time = (timer + J.Core.get_frame_time(core) : F32)
  +tick = (time > 0.5 : F32)
  +next = Bool.pick(U32, tick, (anim + 1 : U32), anim)
  (core, State{camera.update(libm, core, camera), bot, Bool.pick(F32, tick, 0.0, time), Bool.pick(U32, (next >= 4 : U32), 0, next)})

# floor(Vector2Angle/PI*4 + 0.25); a negative row is 8 - abs((int)dir).
def direction.row(angle: Maybe<F32>) -> Maybe<F32>:
  match angle:
    case None{}: None{}
    case Some{+a}:
      +row = F32.floor(((a / 3.14159265358979323846) * 4.0 + 0.25 : F32))
      Some{Bool.pick(F32, (row < 0.0 : F32), (8.0 - F32.neg(row) : F32), row)}

# Vector2Angle((2, 0), (camera.position.x, camera.position.z)).
def direction(+libm: M.Libm, +camera: J.Camera3D) -> Maybe<F32>:
  J.Camera3D{position, _, _, _, _} = camera
  M.Vector3{+x, _, +z} = position
  direction.row(M.Vector2.angle_for(libm, M.Vector2{2.0, 0.0}, M.Vector2{x, z}))

def scene.kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, bot) = r
  (J.Frame.end_mode_3d(frame), Some{bot})

# DrawBillboardPro(camera, skillbot, (anim*24, dir*24, 24, 24), (0, 0, 0), up, (1, 1), (0.5, 0), 0, WHITE).
def scene.drawn(+libm: M.Libm, +camera: J.Camera3D, +anim: U32, +row: F32, frame: J.Frame, bot: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match bot:
    case None{}: (J.Frame.end_mode_3d(J.Draw.grid(J.Frame.begin_mode_3d_for(libm, frame, camera), 10.0, 1.0)), None{})
    case Some{t}: scene.kept(J.Draw.billboard_pro_for(libm, J.Draw.grid(J.Frame.begin_mode_3d_for(libm, frame, camera), 10.0, 1.0), camera, t,
      J.Rectangle{(0.0 + U32.to_f32(anim) * 24.0 : F32), (0.0 + row * 24.0 : F32), 24.0, 24.0},
      M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, M.Vector2{1.0, 1.0}, M.Vector2{0.5, 0.0}, 0.0, J.Color.WHITE()))

def label(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 20.0, J.Color.DARKGRAY())

def labels(+anim: U32, +row: F32, r: J.Frame & Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  (frame, bot) = r
  (label(J.Text.format("direction frame: %.0f", [J.TextFloat{row}]), 40.0, label(J.Text.format("animation: %d", [J.TextInt{anim}]), 10.0, frame)), bot)

def scene.at(+libm: M.Libm, +camera: J.Camera3D, +anim: U32, row: Maybe<F32>, frame: J.Frame, bot: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match row:
    case None{}: (J.Frame.refuse(frame), bot)
    case Some{+d}: labels(anim, d, scene.drawn(libm, camera, anim, d, frame, bot))

def scene(+libm: M.Libm, camera: +Maybe<J.Camera3D>, +anim: U32, frame: J.Frame, bot: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match camera:
    case None{}: (J.Frame.refuse(frame), bot)
    case Some{+c}: scene.at(libm, c, anim, direction(libm, c), frame, bot)

def draw.done(+core: J.Core, camera: +Maybe<J.Camera3D>, +timer: F32, +anim: U32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, bot) = r
  (core, (State{camera, bot, timer, anim}, frame))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, bot, +timer, +anim} = state
  draw.done(core, camera, timer, anim, scene(libm, camera, anim, J.Frame.clear_background(frame, J.Color.RAYWHITE()), bot))

# The main loop's body; libm is the profile of UpdateCamera's and DrawBillboardPro's sinf/cosf, Vector2Angle's atan2f and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, bot) = r
  (J.Core.set_target_fps(core, 60), (frame, State{Some{start()}, bot, 0.0, 0}))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{Some{start()}, None{}, 0.0, 0}))
    case Done{image}: setup.uploaded(core, J.Texture.load_from_image(frame, image))

# After InitWindow(800, 450): LoadTexture("resources/skillbot.png"), SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/skillbot.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - directional billboard", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
