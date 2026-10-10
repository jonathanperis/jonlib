# raylib [models] example - billboard rendering, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_billboard_rendering.c
# (zlib/libpng, Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A static billboard and one turning 0.4 degrees a frame under an orbital
# camera, the farther one drawn first. The perspective needs the libm
# profile's binary64 tan (docs/PERSPECTIVE.md), UpdateCamera and
# DrawBillboardPro its sinf/cosf (docs/SINCOSF.md); a refused UpdateCamera
# refuses the frame and every later one. LoadTexture of a .png is the PNG
# loader (Surface.load_png). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{camera: +Maybe<J.Camera3D>, bill: Maybe<J.Texture>, rotation: F32}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{5.0, 4.0, 5.0}, M.Vector3{0.0, 2.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def camera.updated(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def camera.update(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: camera.updated(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()))

# UpdateCamera(CAMERA_ORBITAL); rotation += 0.4.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+camera, bill, +rotation} = state
  (core, State{camera.update(libm, core, camera), bill, (rotation + 0.4 : F32)})

# DrawBillboard(camera, bill, (0, 2, 0), 2, WHITE).
def fixed(+camera: J.Camera3D, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  (frame, bill) = r
  J.Draw.billboard(frame, camera, bill, M.Vector3{0.0, 2.0, 0.0}, 2.0, J.Color.WHITE())

# DrawBillboardPro(camera, bill, the whole texture, (1, 2, 1), up, (width/height, 1), its half, rotation, WHITE).
def turning(+libm: M.Libm, +camera: J.Camera3D, +rotation: F32, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  (frame, bill) = r
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = bill
  +ratio = (U32.to_f32(w) / U32.to_f32(h) : F32)
  J.Draw.billboard_pro_for(libm, frame, camera, J.Texture{id, w, h, format, linear, alpha, texels}, J.Rectangle{0.0, 0.0, U32.to_f32(w), U32.to_f32(h)},
    M.Vector3{1.0, 2.0, 1.0}, M.Vector3{0.0, 1.0, 0.0}, M.Vector2{ratio, 1.0}, M.Vector2{(ratio * 0.5 : F32), (1.0 * 0.5 : F32)}, rotation, J.Color.WHITE())

# The farther billboard first.
def billboards(static_first: Bool, +libm: M.Libm, +camera: J.Camera3D, +rotation: F32, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  match static_first:
    case True{}: turning(libm, camera, rotation, fixed(camera, r))
    case False{}: fixed(camera, turning(libm, camera, rotation, r))

def scene.kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, bill) = r
  (J.Frame.end_mode_3d(frame), Some{bill})

# distanceStatic > distanceRotating.
def static_first(+camera: J.Camera3D) -> Bool:
  J.Camera3D{+position, _, _, _, _} = camera
  (M.Vector3.distance(position, M.Vector3{0.0, 2.0, 0.0}) > M.Vector3.distance(position, M.Vector3{1.0, 2.0, 1.0}) : F32)

def scene.at(+libm: M.Libm, +camera: J.Camera3D, +rotation: F32, frame: J.Frame, bill: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match bill:
    case None{}: (J.Frame.end_mode_3d(J.Draw.grid(J.Frame.begin_mode_3d_for(libm, frame, camera), 10.0, 1.0)), None{})
    case Some{t}: scene.kept(billboards(static_first(camera), libm, camera, rotation, (J.Draw.grid(J.Frame.begin_mode_3d_for(libm, frame, camera), 10.0, 1.0), t)))

def scene(+libm: M.Libm, camera: +Maybe<J.Camera3D>, +rotation: F32, frame: J.Frame, bill: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match camera:
    case None{}: (J.Frame.refuse(frame), bill)
    case Some{+c}: scene.at(libm, c, rotation, frame, bill)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.done(+core: J.Core, camera: +Maybe<J.Camera3D>, +rotation: F32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, bill) = r
  draw.fps.done(State{camera, bill, rotation}, frame, J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, bill, +rotation} = state
  draw.done(core, camera, rotation, scene(libm, camera, rotation, J.Frame.clear_background(frame, J.Color.RAYWHITE()), bill))

# The main loop's body; libm is the profile of UpdateCamera's and DrawBillboardPro's sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, bill) = r
  (J.Core.set_target_fps(core, 60), (frame, State{Some{start()}, bill, 0.0}))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{Some{start()}, None{}, 0.0}))
    case Done{image}: setup.uploaded(core, J.Texture.load_from_image(frame, image))

# After InitWindow(800, 450): LoadTexture("resources/billboard.png"), SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/billboard.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - billboard rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
