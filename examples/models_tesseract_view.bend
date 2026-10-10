# raylib [models] example - tesseract view, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_tesseract_view.c (zlib/libpng,
# Copyright (c) 2024-2025 Timothy van der Valk (@arceryz) and Ramon Santamaria
# (@raysan5)); see LICENSES/raylib.txt.
#
# The 16 vertices of a tesseract turning in the XW plane (45 degrees a second
# of GetTime), projected to 3D and drawn as spheres sized by their W, joined
# along the 32 edges. Vector2Rotate's sinf/cosf, DrawSphere's and the
# perspective's tan follow the libm profile; an argument outside it refuses
# the frame (docs/SINCOSF.md, docs/PERSPECTIVE.md). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Point is Data:
  Point{x: F32, y: F32, z: F32, w: F32}

# The projected vertices of this frame (in the tesseract's order), valid
# when the rotation's sinf/cosf were inside the profile.
type State is Data:
  State{valid: Bool, points: +List<Point>}

def camera() -> J.Camera3D:
  J.Camera3D{M.Vector3{4.0, 4.0, 4.0}, M.Vector3.zero(), M.Vector3{0.0, 0.0, 1.0}, 50.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def sign(bit: U32) -> F32:
  match bit:
    case 0: 1.0
    case _: F32.neg(1.0)

# tesseract[i]: (+-1, +-1, +-1, +-1), the bits of i (x highest) choosing the minus signs.
def vertex(+i: U32) -> Point:
  Point{sign(((i >> 3n) .&. 1 : U32)), sign(((i >> 2n) .&. 1 : U32)), sign(((i >> 1n) .&. 1 : U32)), sign((i .&. 1 : U32))}

# Vector2Rotate((x, w), rotation), then the projection c = 3/(3 - w).
def turned(+p: Point, +cosine: F32, +sine: F32) -> Point:
  Point{+x, +y, +z, +w} = p
  +rx = (x * cosine - w * sine : F32)
  +rw = (x * sine + w * cosine : F32)
  +c = (3.0 / (3.0 - rw) : F32)
  Point{(c * rx : F32), (c * y : F32), (c * z : F32), rw}

def turned.all(n: Nat, +i: U32, +cosine: F32, +sine: F32) -> +List<Point>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{turned(vertex(i), cosine, sine), turned.all(p, (i + 1 : U32), cosine, sine)}

def update.trig(cosine: Maybe<F32>, sine: Maybe<F32>) -> State:
  match cosine sine:
    case Some{+c} Some{+s}: State{True{}, turned.all(16n, 0, c, s)}
    case _ _: State{False{}, Nil{}}

def update.time(+libm: M.Libm, time: Maybe<F32>) -> State:
  match time:
    case None{}: State{False{}, Nil{}}
    case Some{+t}: update.trig(M.Libm.cos(libm, ((3.14159265358979323846 / 180.0) * 45.0 * t : F32)), M.Libm.sin(libm, ((3.14159265358979323846 / 180.0) * 45.0 * t : F32)))

# rotation = DEG2RAD*45.0f*(float)GetTime().
def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  (core, update.time(libm, M.Float64.to_f32(J.Core.get_time(core))))

def place(+p: Point) -> M.Vector3:
  Point{x, y, z, _} = p
  M.Vector3{x, y, z}

def first(points: +List<Point>) -> Point:
  match points:
    case Con{p, _}: p
    case Nil{}: Point{0.0, 0.0, 0.0, 0.0}

def at(+points: +List<Point>, +i: U32) -> Point:
  first(List.drop(&2, Point, points, U32.to_nat(i)))

def same(+a: F32, +b: F32) -> U32:
  Bool.to_u32(F32.is_eq(a, b))

def joined.with(+i: U32, +j: U32, +ax: F32, +ay: F32, +az: F32, +aw: F32, +b: Point) -> Bool:
  Point{+bx, +by, +bz, +bw} = b
  U32.is_eq((same(ax, bx) + same(ay, by) + same(az, bz) + same(aw, bw) : U32), 3) && (i < j : U32)

# Vertices i < j are joined when exactly three of their four coordinates are equal.
def joined.from(+i: U32, +j: U32, a: Point) -> Bool:
  Point{+ax, +ay, +az, +aw} = a
  joined.with(i, j, ax, ay, az, aw, vertex(j))

def joined(+i: U32, +j: U32) -> Bool:
  joined.from(i, j, vertex(i))

def edge(visible: Bool, +from: M.Vector3, +to: M.Vector3, frame: J.Frame) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: J.Draw.line_3d(frame, from, to, J.Color.MAROON())

def edges(n: Nat, +points: +List<Point>, +i: U32, +j: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: edges(p, points, i, (j + 1 : U32), edge(joined(i, j), place(at(points, i)), place(at(points, j)), frame))

def radius(+p: Point) -> F32:
  Point{_, _, _, w} = p
  F32.abs((w * 0.1 : F32))

# DrawSphere(transformed[i], fabsf(w*0.1f), RED), then the edges from i.
def vertices(n: Nat, +libm: M.Libm, +points: +List<Point>, +i: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: vertices(p, libm, points, (i + 1 : U32), edges(16n, points, i, 0, J.Draw.sphere_for(libm, frame, place(at(points, i)), radius(at(points, i)), J.Color.RED())))

def scene(valid: Bool, +libm: M.Libm, +points: +List<Point>, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}: J.Frame.end_mode_3d(vertices(16n, libm, points, 0, J.Frame.begin_mode_3d_for(libm, frame, camera())))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +points} = state
  (core, (state, scene(valid, libm, points, J.Frame.clear_background(frame, J.Color.RAYWHITE()))))

# The main loop's body; libm is the profile of the rotation's and the spheres' sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{False{}, Nil{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - tesseract view", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
