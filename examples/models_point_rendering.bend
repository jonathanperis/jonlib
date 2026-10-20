# raylib [models] example - point rendering, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_point_rendering.c
# (zlib/libpng, Copyright (c) 2024-2025 Reese Gallagher (@satchelfrost)); see
# LICENSES/raylib.txt.
#
# A thousand colored points inside a sphere of radius 10 under an orbital
# camera, drawn as a model in point mode or one DrawPoint3D each (SPACE); UP
# and DOWN multiply and divide the count by 10 between 1000 and 10 million
# and generate the points again. The points come from the C library's rand()
# (never seeded: the seed 1, M.Libc) and sinf/cosf (M.Libm): a profile
# without them refuses every frame. The mesh has the example's counts (every
# point a vertex, one triangle declared); UploadMesh has no buffer to fill on
# the software renderer (Mesh.upload). The perspective needs the profile's
# binary64 tan (docs/PERSPECTIVE.md); a refused UpdateCamera refuses the
# frame and every later one. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The generator's state and what it made so far: vertices and color bytes
# in reverse (the last value first); ok is False once a sine was refused.
type Points is Data:
  Points{rand: M.Libc.Rand, ok: Bool, vertices: +List<F32>, colors: +List<U32>}

type State is Data:
  State{camera: +Maybe<J.Camera3D>, rand: +Maybe<M.Libc.Rand>, mesh: +Maybe<J.Mesh>, count: U32, model_points: Bool}

type Trig is Data:
  Trig{ok: Bool, value: F32}

def float(+word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# PI, 2.0f*PI and (float)RAND_MAX (2^31) as binary32.
def pi() -> F32:
  float(1078530011)

def two_pi() -> F32:
  float(1086918619)

def rand_max() -> F32:
  float(1325400064)

def trig(value: Maybe<F32>) -> Trig:
  match value:
    case None{}: Trig{False{}, 0.0}
    case Some{v}: Trig{True{}, v}

# r*sinf(theta)*cosf(phi), r*sinf(theta)*sinf(phi), r*cosf(theta), and ColorFromHSV(r*360.0f, 1.0f, 1.0f).
def points.placed(+rand: M.Libc.Rand, +ok: Bool, +vertices: +List<F32>, +colors: +List<U32>, +radius: F32, st: Trig, ct: Trig, sp: Trig, cp: Trig) -> Points:
  Trig{+a, +sin_theta} = st
  Trig{+b, +cos_theta} = ct
  Trig{+c, +sin_phi} = sp
  Trig{+d, +cos_phi} = cp
  +color = J.Color.from_hsv((radius * 360.0 : F32), 1.0, 1.0)
  +flat = (radius * sin_theta : F32)
  Points{rand, ok && a && b && c && d, Con{(radius * cos_theta : F32), Con{(flat * sin_phi : F32), Con{(flat * cos_phi : F32), vertices}}},
    Con{J.Color.alpha(color), Con{J.Color.blue(color), Con{J.Color.green(color), Con{J.Color.red(color), colors}}}}}

# theta = (PI*rand())/RAND_MAX, phi = (2.0f*PI*rand())/RAND_MAX, r = (10.0f*rand())/RAND_MAX, in that order.
def points.radius(+libm: M.Libm, +ok: Bool, +vertices: +List<F32>, +colors: +List<U32>, +first: U32, +second: U32, r: M.Libc.Rand & U32) -> Points:
  (+rand, +third) = r
  +theta = ((pi() * U32.to_f32(first) : F32) / rand_max() : F32)
  +phi = ((two_pi() * U32.to_f32(second) : F32) / rand_max() : F32)
  points.placed(rand, ok, vertices, colors, ((10.0 * U32.to_f32(third) : F32) / rand_max() : F32),
    trig(M.Libm.sin(libm, theta)), trig(M.Libm.cos(libm, theta)), trig(M.Libm.sin(libm, phi)), trig(M.Libm.cos(libm, phi)))

def points.phi(+libm: M.Libm, +ok: Bool, +vertices: +List<F32>, +colors: +List<U32>, +first: U32, r: M.Libc.Rand & U32) -> Points:
  (+rand, +second) = r
  points.radius(libm, ok, vertices, colors, first, second, M.Libc.rand(rand))

def points.theta(+libm: M.Libm, +ok: Bool, +vertices: +List<F32>, +colors: +List<U32>, r: M.Libc.Rand & U32) -> Points:
  (+rand, +first) = r
  points.phi(libm, ok, vertices, colors, first, M.Libc.rand(rand))

def points.step(+libm: M.Libm, made: Points) -> Points:
  Points{+rand, +ok, +vertices, +colors} = made
  points.theta(libm, ok, vertices, colors, M.Libc.rand(rand))

def points(n: Nat, +libm: M.Libm, made: Points) -> Points:
  match n:
    case 0n: made
    case 1n+p: points(p, libm, points.step(libm, made))

def floats.reversed(values: +List<F32>, acc: +List<F32>) -> +List<F32>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: floats.reversed(rest, Con{v, acc})

def bytes.reversed(values: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: bytes.reversed(rest, Con{v, acc})

# GenMeshPoints(numPoints): vertexCount = numPoints, triangleCount = 1, vertices and colors; UploadMesh(&mesh, false).
def generated.mesh(+count: U32, +camera: +Maybe<J.Camera3D>, +model_points: Bool, made: Points) -> State:
  Points{+rand, +ok, +vertices, +colors} = made
  +mesh = J.Mesh.upload(J.Mesh{count, 1, Some{floats.reversed(vertices, Nil{})}, None{}, None{}, None{}, None{}, Some{bytes.reversed(colors, Nil{})}, None{}, None{}}, False{})
  State{camera, Some{rand}, Bool.pick(+Maybe<J.Mesh>, ok, Some{mesh}, None{}), count, model_points}

def generated(rand: +Maybe<M.Libc.Rand>, +libm: M.Libm, +count: U32, +camera: +Maybe<J.Camera3D>, +model_points: Bool) -> State:
  match rand:
    case None{}: State{camera, None{}, None{}, count, model_points}
    case Some{+r}: generated.mesh(count, camera, model_points, points(U32.to_nat(count), libm, Points{r, True{}, Nil{}, Nil{}}))

def moved(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def update.camera(camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()))

# UP: numPoints*10, at most 10 million; DOWN: numPoints/10, at least 1000.
def raised(+count: U32) -> U32:
  Bool.pick(U32, ((count * 10 : U32) > 10000000 : U32), 10000000, (count * 10 : U32))

def lowered(+count: U32) -> U32:
  Bool.pick(U32, ((count / 10 : U32) < 1000 : U32), 1000, (count / 10 : U32))

def update.changed(changed: Bool, +libm: M.Libm, +camera: +Maybe<J.Camera3D>, +rand: +Maybe<M.Libc.Rand>, +mesh: +Maybe<J.Mesh>, +count: U32, +model_points: Bool) -> State:
  match changed:
    case False{}: State{camera, rand, mesh, count, model_points}
    case True{}: generated(rand, libm, count, camera, model_points)

def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+camera, +rand, +mesh, +count, +model_points} = state
  +up = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_UP())
  +down = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_DOWN())
  +more = Bool.pick(U32, up, raised(count), count)
  +flipped = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), Bool.not(model_points), model_points)
  (core, update.changed(up || down, libm, update.camera(camera, libm, core), rand, mesh, Bool.pick(U32, down, lowered(more), more), flipped))

# DrawPoint3D for every vertex with its color.
def draw.each(vertices: +List<F32>, colors: +List<U32>, frame: J.Frame) -> J.Frame:
  match vertices colors:
    case Con{+x, Con{+y, Con{+z, rest}}} Con{+r, Con{+g, Con{+b, Con{+a, more}}}}: draw.each(rest, more, J.Draw.point_3d(frame, M.Vector3{x, y, z}, J.Color.rgba(r, g, b, a)))
    case _ _: frame

def listed.f(values: Maybe<&2, +List<F32>>) -> +List<F32>:
  match values:
    case None{}: Nil{}
    case Some{+v}: v

def listed.u(values: Maybe<&2, +List<U32>>) -> +List<U32>:
  match values:
    case None{}: Nil{}
    case Some{+v}: v

def draw.kept(r: J.Frame & List<J.Texture>) -> J.Frame:
  (frame, textures) = r
  frame

# DrawModelPoints: rlEnablePointMode, rlDisableBackfaceCulling, DrawModel, rlEnableBackfaceCulling, rlDisablePointMode.
def draw.points(model_points: Bool, +mesh: J.Mesh, frame: J.Frame) -> J.Frame:
  match model_points:
    case True{}:
      f1 = J.Rlgl.disable_backface_culling(J.Rlgl.enable_point_mode(frame))
      J.Rlgl.disable_point_mode(J.Rlgl.enable_backface_culling(draw.kept(J.Draw.model(f1, Nil{}, J.Model.from_mesh(mesh), M.Vector3.zero(), 1.0, J.Color.WHITE()))))
    case False{}:
      J.Mesh{_, _, vertices, _, _, _, _, colors, _, _} = mesh
      draw.each(listed.f(vertices), listed.u(colors), frame)

def draw.scene(mesh: +Maybe<J.Mesh>, +libm: M.Libm, +camera: J.Camera3D, +model_points: Bool, frame: J.Frame) -> J.Frame:
  match mesh:
    case None{}: J.Frame.refuse(frame)
    case Some{+m}: J.Frame.end_mode_3d(J.Draw.sphere_wires_for(libm, draw.points(model_points, m, J.Frame.begin_mode_3d_for(libm, frame, camera)), M.Vector3.zero(), 1.0, 10.0, 10.0, J.Color.YELLOW()))

def draw.world(camera: +Maybe<J.Camera3D>, +libm: M.Libm, +mesh: +Maybe<J.Mesh>, +model_points: Bool, frame: J.Frame) -> J.Frame:
  match camera:
    case None{}: J.Frame.refuse(frame)
    case Some{+c}: draw.scene(mesh, libm, c, model_points, frame)

def draw.count(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 400.0, 40.0, J.Color.WHITE())

def draw.using(model_points: Bool, frame: J.Frame) -> J.Frame:
  match model_points:
    case True{}: J.Draw.text(frame, "Using: DrawModelPoints()", 10.0, 130.0, 20.0, J.Color.GREEN())
    case False{}: J.Draw.text(frame, "Using: DrawPoint3D()", 10.0, 130.0, 20.0, J.Color.RED())

def draw.fps.at(+state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, _, +mesh, +count, +model_points} = state
  f1 = draw.count(J.Text.format("Point Count: %d", [J.TextInt{count}]), draw.world(camera, libm, mesh, model_points, J.Frame.clear_background(frame, J.Color.BLACK())))
  f2 = J.Draw.text(f1, "UP - Increase points", 10.0, 40.0, 20.0, J.Color.WHITE())
  f3 = J.Draw.text(f2, "DOWN - Decrease points", 10.0, 70.0, 20.0, J.Color.WHITE())
  f4 = J.Draw.text(f3, "SPACE - Drawing function", 10.0, 100.0, 20.0, J.Color.WHITE())
  draw.fps.done(state, draw.using(model_points, f4), J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the profile of rand(), sinf/cosf and BeginMode3D's tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{3.0, 3.0, 3.0}, M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def seeded(rand: Maybe<M.Libc.Rand>) -> +Maybe<M.Libc.Rand>:
  match rand:
    case None{}: None{}
    case Some{+r}: Some{r}

# After InitWindow(800, 450): GenMeshPoints(1000) from the unseeded rand() (the seed 1), SetTargetFPS(60).
def setup(+libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, generated(seeded(M.Libc.srand(libm, 1)), libm, 1000, Some{start()}, True{})))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - point rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
