# raylib [textures] example - framebuffer rendering, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_framebuffer_rendering.c
# (zlib/libpng, Copyright (c) 2026 Jack Boakes (@jackboakes)); see
# LICENSES/raylib.txt.
#
# A cube seen by two cameras, each into its own render texture: a free
# observer that also draws the orbiting subject camera's view volume
# (DrawCameraPrism: the far plane's corners through the inverse of view
# times MatrixPerspective), and the subject, whose central square is shown
# again as a capture. Each render texture has its own depth buffer
# (docs/RLGL.md). The perspectives need the libm profile's binary64 tan
# (docs/PERSPECTIVE.md) and UpdateCamera its sinf/cosf (docs/SINCOSF.md); a
# camera or matrix Jonlib refuses refuses the frame. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Cameras is Data:
  Cameras{valid: Bool, observer: J.Camera3D, subject: J.Camera3D}

type State is Type:
  State{cameras: Cameras, first: Maybe<J.RenderTexture>, second: Maybe<J.RenderTexture>}

def retargeted(+reset: Bool, +camera: J.Camera3D) -> J.Camera3D:
  J.Camera3D{+position, _, +up, +fovy, +projection} = camera
  Bool.pick(J.Camera3D, reset, J.Camera3D{position, M.Vector3.zero(), up, fovy, projection}, camera)

# A refusal stays: once invalid, the cameras no longer move.
def kept(+valid: Bool, +cameras: Cameras) -> Cameras:
  Cameras{+ok, +observer, +subject} = cameras
  Cameras{valid && ok, observer, subject}

def moved(+observer: J.Camera3D, +subject: J.Camera3D, +reset: Bool, a: Maybe<J.Camera3D>, b: Maybe<J.Camera3D>) -> Cameras:
  match a b:
    case Some{+o} Some{+s}: Cameras{True{}, retargeted(reset, o), s}
    case _ _: Cameras{False{}, observer, subject}

# UpdateCamera(&observerCamera, CAMERA_FREE); UpdateCamera(&subjectCamera, CAMERA_ORBITAL); R: observerCamera.target = (0, 0, 0).
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+cameras, first, second} = state
  Cameras{+valid, +observer, +subject} = cameras
  (core, State{kept(valid, moved(observer, subject, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_R()),
    J.Camera.update_for(M.Uncontracted{}, libm, core, observer, J.CameraMode.CAMERA_FREE()),
    J.Camera.update_for(M.Uncontracted{}, libm, core, subject, J.CameraMode.CAMERA_ORBITAL()))), first, second})

def cube(frame: J.Frame) -> J.Frame:
  J.Draw.cube_wires(J.Draw.cube(frame, M.Vector3.zero(), 2.0, 2.0, 2.0, J.Color.GOLD()), M.Vector3.zero(), 2.0, 2.0, 2.0, J.Color.PINK())

# A far-plane corner: the inverse view-projection applied to (x, y, 1, 1), divided by w.
def corner(+m: M.Matrix, +x: F32, +y: F32) -> M.Vector3:
  M.Matrix{+m0, +m4, +m8, +m12, +m1, +m5, +m9, +m13, +m2, +m6, +m10, +m14, +m3, +m7, +m11, +m15} = m
  +w = (((m3 * x + m7 * y) + m11 * 1.0) + m15 : F32)
  M.Vector3{((((m0 * x + m4 * y) + m8 * 1.0) + m12) / w : F32), ((((m1 * x + m5 * y) + m9 * 1.0) + m13) / w : F32), ((((m2 * x + m6 * y) + m10 * 1.0) + m14) / w : F32)}

def prism.lines(+eye: M.Vector3, +a: M.Vector3, +b: M.Vector3, +c: M.Vector3, +d: M.Vector3, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.line_3d(J.Draw.line_3d(J.Draw.line_3d(J.Draw.line_3d(frame, a, b, J.Color.GREEN()), b, c, J.Color.GREEN()), c, d, J.Color.GREEN()), d, a, J.Color.GREEN())
  J.Draw.line_3d(J.Draw.line_3d(J.Draw.line_3d(J.Draw.line_3d(f1, eye, a, J.Color.GREEN()), eye, b, J.Color.GREEN()), eye, c, J.Color.GREEN()), eye, d, J.Color.GREEN())

def prism.inverse(+camera: J.Camera3D, +inverse: M.Matrix, frame: J.Frame) -> J.Frame:
  J.Camera3D{+position, _, _, _, _} = camera
  prism.lines(position, corner(inverse, F32.neg(1.0), F32.neg(1.0)), corner(inverse, 1.0, F32.neg(1.0)), corner(inverse, 1.0, 1.0), corner(inverse, F32.neg(1.0), 1.0), frame)

def prism.at(+camera: J.Camera3D, projection: Maybe<M.Matrix>, frame: J.Frame) -> J.Frame:
  match projection:
    case None{}: J.Frame.refuse(frame)
    case Some{+p}: prism.inverse(camera, M.Matrix.invert(M.Matrix.multiply(J.Camera.matrix_for(M.Uncontracted{}, camera), p)), frame)

# DrawCameraPrism(subjectCamera, 400/450, GREEN): MatrixPerspective(fovy*DEG2RAD, aspect, 0.05f, the distance to the target).
def prism(+libm: M.Libm, +camera: J.Camera3D, frame: J.Frame) -> J.Frame:
  J.Camera3D{+position, +target, _, +fovy, _} = camera
  prism.at(camera, M.Matrix.perspective_for(libm, M.Float64.from_f32((fovy * M.Math.DEG2RAD() : F32)), M.Float64.from_f32((400.0 / 450.0 : F32)), M.Float64.from_f32(0.05),
    M.Float64.from_f32(M.Vector3.distance(position, target))), frame)

# The observer's view: the grid, the cube, the subject camera's prism and the help texts.
def observed(+libm: M.Libm, +cameras: Cameras, frame: J.Frame) -> J.Frame:
  Cameras{_, +observer, +subject} = cameras
  f1 = J.Frame.end_mode_3d(prism(libm, subject, cube(J.Draw.grid(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), observer), 10.0, 1.0))))
  f2 = J.Draw.text(J.Draw.text(f1, "Observer View", 10.0, (450.0 - 30.0 : F32), 20.0, J.Color.BLACK()), "WASD + Mouse to Move", 10.0, 10.0, 20.0, J.Color.DARKGRAY())
  J.Draw.text(J.Draw.text(f2, "Scroll to Zoom", 10.0, 30.0, 20.0, J.Color.DARKGRAY()), "R to Reset Observer Target", 10.0, 50.0, 20.0, J.Color.DARKGRAY())

# The subject's view: the cube, the grid and the capture square's outline.
def subjected(+libm: M.Libm, +cameras: Cameras, frame: J.Frame) -> J.Frame:
  Cameras{_, _, +subject} = cameras
  f1 = J.Frame.end_mode_3d(J.Draw.grid(cube(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), subject)), 10.0, 1.0))
  J.Draw.text(J.Draw.rectangle_lines(f1, F32.trunc(((400.0 - 128.0) / 2.0 : F32)), F32.trunc(((450.0 - 128.0) / 2.0 : F32)), 128.0, 128.0, J.Color.GREEN()),
    "Subject View", 10.0, (450.0 - 30.0 : F32), 20.0, J.Color.BLACK())

def full() -> J.Rectangle:
  J.Rectangle{0.0, 0.0, 400.0, F32.neg(450.0)}

def rebuilt(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & J.RenderTexture:
  (frame, texture) = r
  (frame, J.RenderTexture{id, texture, depth})

# DrawTexturePro(target.texture, source, dest, (0, 0), 0, WHITE).
def shown(+libm: M.Libm, +source: J.Rectangle, +dest: J.Rectangle, frame: J.Frame, target: J.RenderTexture) -> J.Frame & J.RenderTexture:
  J.RenderTexture{+id, texture, +depth} = target
  rebuilt(id, depth, J.Draw.texture_pro_for(libm, frame, texture, source, dest, M.Vector2.zero(), 0.0, J.Color.WHITE()))

def draw.done(+core: J.Core, +cameras: Cameras, first: J.RenderTexture, r: J.Frame & J.RenderTexture) -> J.Core & (State & J.Frame):
  (frame, second) = r
  (core, (State{cameras, Some{first}, Some{second}},
    J.Draw.line(J.Draw.rectangle_lines_ex(frame, J.Rectangle{(400.0 + 20.0 : F32), 20.0, 128.0, 128.0}, 2.0, J.Color.BLACK()), 400.0, 0.0, 400.0, 450.0, J.Color.BLACK())))

# The capture: the subject texture's central 128x128 square at (420, 20).
def draw.captured(+libm: M.Libm, +core: J.Core, +cameras: Cameras, first: J.RenderTexture, r: J.Frame & J.RenderTexture) -> J.Core & (State & J.Frame):
  (frame, second) = r
  draw.done(core, cameras, first, shown(libm, J.Rectangle{((400.0 - 128.0) / 2.0 : F32), ((450.0 - 128.0) / 2.0 : F32), 128.0, F32.neg(128.0)},
    J.Rectangle{(400.0 + 20.0 : F32), 20.0, 128.0, 128.0}, frame, second))

def draw.left(+libm: M.Libm, +core: J.Core, +cameras: Cameras, second: J.RenderTexture, r: J.Frame & J.RenderTexture) -> J.Core & (State & J.Frame):
  (frame, first) = r
  draw.captured(libm, core, cameras, first, shown(libm, full(), J.Rectangle{400.0, 0.0, 400.0, 450.0}, frame, second))

# ClearBackground(BLACK); the observer's texture on the left half, the subject's on the right.
def draw.both(+libm: M.Libm, +core: J.Core, +cameras: Cameras, frame: J.Frame, first: Maybe<J.RenderTexture>, second: Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  match first second:
    case Some{a} Some{b}: draw.left(libm, core, cameras, b, shown(libm, full(), J.Rectangle{0.0, 0.0, 400.0, 450.0}, frame, a))
    case _ _: (core, (State{cameras, None{}, None{}}, J.Frame.refuse(frame)))

def draw.screen(+libm: M.Libm, +core: J.Core, +cameras: Cameras, first: Maybe<J.RenderTexture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, second) = r
  draw.both(libm, core, cameras, J.Frame.clear_background(frame, J.Color.BLACK()), first, second)

def draw.second(+libm: M.Libm, +core: J.Core, +cameras: Cameras, second: J.RenderTexture, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, first) = r
  draw.screen(libm, core, cameras, first, J.Frame.end_texture_mode(subjected(libm, cameras, J.Frame.begin_texture_mode(frame, second))))

# The two texture passes (raylib draws them before BeginDrawing; here the draw does that first, the same pixels), then the screen.
def draw.valid(valid: Bool, +libm: M.Libm, +core: J.Core, +cameras: Cameras, frame: J.Frame, first: Maybe<J.RenderTexture>, second: Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  match valid first second:
    case True{} Some{a} Some{b}: draw.second(libm, core, cameras, b, J.Frame.end_texture_mode(observed(libm, cameras, J.Frame.begin_texture_mode(frame, a))))
    case True{} _ _: (core, (State{cameras, None{}, None{}}, J.Frame.refuse(frame)))
    case False{} Some{a} Some{b}: (core, (State{cameras, Some{a}, Some{b}}, J.Frame.refuse(frame)))
    case False{} _ _: (core, (State{cameras, None{}, None{}}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+cameras, first, second} = state
  Cameras{+valid, _, _} = cameras
  draw.valid(valid, libm, core, cameras, frame, first, second)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf and the perspective tans.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.second(+core: J.Core, first: Maybe<J.RenderTexture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, second) = r
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{Cameras{True{},
    J.Camera3D{M.Vector3{10.0, 10.0, 10.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()},
    J.Camera3D{M.Vector3{5.0, 5.0, 5.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}}, first, second}))

def setup.first(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, first) = r
  setup.second(core, first, J.RenderTexture.load(frame, 400, 450))

# After InitWindow(800, 450): the two cameras, the observer's and the subject's 400x450 render textures, SetTargetFPS(60), DisableCursor().
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.first(core, J.RenderTexture.load(frame, 400, 450))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [textures] example - framebuffer rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
