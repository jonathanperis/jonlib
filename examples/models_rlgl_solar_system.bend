# raylib [models] example - rlgl solar system, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_rlgl_solar_system.c
# (zlib/libpng, Copyright (c) 2018-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A sun, an earth orbiting it and a moon orbiting the earth, each a unit
# sphere of rlgl triangles (DrawSphereBasic) under the rlgl matrix stack
# (rlPushMatrix, rlRotatef, rlTranslatef, rlScalef). The sphere's sinf/cosf
# and rlRotatef's follow the libm profile (docs/SINCOSF.md) and the
# perspective needs its binary64 tan (docs/PERSPECTIVE.md); an angle outside
# the profile refuses the frame. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The cosine and sine of one ring or slice angle.
type CS is Data:
  CS{c: F32, s: F32}

type Table is Data:
  Table{valid: Bool, entries: +List<CS>}

# earth, orbit, moon, around: earthRotation, earthOrbitRotation, moonRotation and moonOrbitRotation.
type State is Data:
  State{valid: Bool, rings: +List<CS>, slices: +List<CS>, earth: F32, orbit: F32, moon: F32, around: F32}

def entry(+rest: Table, cosine: Maybe<F32>, sine: Maybe<F32>) -> Table:
  Table{+valid, +entries} = rest
  match cosine sine:
    case Some{+c} Some{+s}: Table{valid, Con{CS{c, s}, entries}}
    case _ _: Table{False{}, entries}

# The ring angles DEG2RAD*(270 + (180/(rings + 1))*i) for i = 0..rings + 2.
def rings(n: Nat, +libm: M.Libm, +i: U32) -> Table:
  match n:
    case 0n: Table{True{}, Nil{}}
    case 1n+p: entry(rings(p, libm, (i + 1 : U32)), M.Libm.cos(libm, (M.Math.DEG2RAD() * (270.0 + (180.0 / 17.0) * U32.to_f32(i)) : F32)),
      M.Libm.sin(libm, (M.Math.DEG2RAD() * (270.0 + (180.0 / 17.0) * U32.to_f32(i)) : F32)))

# The slice angles DEG2RAD*(j*360/slices) for j = 0..slices.
def slices(n: Nat, +libm: M.Libm, +j: U32) -> Table:
  match n:
    case 0n: Table{True{}, Nil{}}
    case 1n+p: entry(slices(p, libm, (j + 1 : U32)), M.Libm.cos(libm, (M.Math.DEG2RAD() * ((U32.to_f32(j) * 360.0) / 16.0) : F32)),
      M.Libm.sin(libm, (M.Math.DEG2RAD() * ((U32.to_f32(j) * 360.0) / 16.0) : F32)))

# earthRotation += 5*rotationSpeed; earthOrbitRotation += 365/360.0f*(5*rotationSpeed)*rotationSpeed;
# moonRotation += 2*rotationSpeed; moonOrbitRotation += 8*rotationSpeed, with rotationSpeed 0.2f.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+valid, +rings, +slices, +earth, +orbit, +moon, +around} = state
  (core, State{valid, rings, slices, (earth + (5.0 * 0.2) : F32), (orbit + (((365.0 / 360.0) * (5.0 * 0.2)) * 0.2) : F32), (moon + (2.0 * 0.2) : F32), (around + (8.0 * 0.2) : F32)})

# rlVertex3f(cos(ring)*sin(slice), sin(ring), cos(ring)*cos(slice)).
def vertex(+ring: CS, +slice: CS, frame: J.Frame) -> J.Frame:
  CS{+rc, +rs} = ring
  CS{+sc, +ss} = slice
  J.Rlgl.vertex3f(frame, (rc * ss : F32), rs, (rc * sc : F32))

# The two triangles between rings a and b and slices previous and next.
def quads(rest: +List<CS>, +previous: CS, +a: CS, +b: CS, frame: J.Frame) -> J.Frame:
  match rest:
    case Nil{}: frame
    case Con{+next, more}: quads(more, next, a, b,
      vertex(b, next, vertex(a, next, vertex(a, previous, vertex(b, previous, vertex(b, next, vertex(a, previous, frame)))))))

def band(+slices: +List<CS>, +a: CS, +b: CS, frame: J.Frame) -> J.Frame:
  match slices:
    case Nil{}: frame
    case Con{+first, rest}: quads(rest, first, a, b, frame)

def bands(rest: +List<CS>, +previous: CS, +slices: +List<CS>, frame: J.Frame) -> J.Frame:
  match rest:
    case Nil{}: frame
    case Con{+next, more}: bands(more, next, slices, band(slices, previous, next, frame))

def batched(r: J.Frame & Bool) -> J.Frame:
  (frame, _) = r
  frame

# DrawSphereBasic: rlCheckRenderBatchLimit((rings + 2)*slices*6); rlBegin(RL_TRIANGLES); rlColor4ub(color); the bands; rlEnd().
def sphere(+rings: +List<CS>, +slices: +List<CS>, +color: U32, frame: J.Frame) -> J.Frame:
  match rings:
    case Nil{}: frame
    case Con{+first, rest}: J.Rlgl.end(bands(rest, first, slices,
      J.Rlgl.color4ub(J.Rlgl.begin(batched(J.Rlgl.check_render_batch_limit(frame, 1728.0)), 4), J.Color.red(color), J.Color.green(color), J.Color.blue(color), J.Color.alpha(color))))

def camera() -> J.Camera3D:
  J.Camera3D{M.Vector3{16.0, 16.0, 16.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def system(+libm: M.Libm, +state: State, frame: J.Frame) -> J.Frame:
  State{_, +rings, +slices, +earth, +orbit, +moon, +around} = state
  f1 = J.Rlgl.pop_matrix(sphere(rings, slices, J.Color.GOLD(), J.Rlgl.scalef(J.Rlgl.push_matrix(frame), 4.0, 4.0, 4.0)))
  f2 = J.Rlgl.translatef(J.Rlgl.rotatef_for(libm, J.Rlgl.push_matrix(f1), orbit, 0.0, 1.0, 0.0), 8.0, 0.0, 0.0)
  f3 = J.Rlgl.pop_matrix(sphere(rings, slices, J.Color.BLUE(), J.Rlgl.scalef(J.Rlgl.rotatef_for(libm, J.Rlgl.push_matrix(f2), earth, 0.25, 1.0, 0.0), 0.6, 0.6, 0.6)))
  f4 = J.Rlgl.rotatef_for(libm, J.Rlgl.translatef(J.Rlgl.rotatef_for(libm, f3, around, 0.0, 1.0, 0.0), 1.5, 0.0, 0.0), moon, 0.0, 1.0, 0.0)
  J.Rlgl.pop_matrix(sphere(rings, slices, J.Color.LIGHTGRAY(), J.Rlgl.scalef(f4, 0.16, 0.16, 0.16)))

def draw.fps.at(+state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.valid(valid: Bool, +libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid:
    case False{}: (core, (state, J.Frame.refuse(frame)))
    case True{}:
      f1 = system(libm, state, J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera()))
      f2 = J.Frame.end_mode_3d(J.Draw.grid(J.Draw.circle_3d_for(libm, f1, M.Vector3.zero(), 8.0, M.Vector3{1.0, 0.0, 0.0}, 90.0, J.Color.with_alpha(J.Color.RED(), 0.5)), 20.0, 1.0))
      draw.fps.done(state, J.Draw.text(f2, "EARTH ORBITING AROUND THE SUN!", 400.0, 10.0, 20.0, J.Color.MAROON()), J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, _, _, _} = state
  draw.valid(valid, libm, core, state, frame)

# The main loop's body; libm is the profile of the spheres' and rlRotatef's sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def started(+rings: Table, +slices: Table) -> State:
  Table{+ok, +r} = rings
  Table{+fine, +s} = slices
  State{ok && fine, r, s, 0.0, 0.0, 0.0, 0.0}

# After InitWindow(800, 450): the sphere's ring and slice angles (16 rings, 16 slices), SetTargetFPS(60).
def setup(+libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, started(rings(19n, libm, 0), slices(17n, libm, 0))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - rlgl solar system", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
