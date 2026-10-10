# raylib [shapes] example - math angle rotation, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_math_angle_rotation.c
# (zlib/libpng, Copyright (c) 2025 Kris (@krispy-snacc)); see
# LICENSES/raylib.txt.
#
# Four fixed lines at 0, 30, 60 and 90 degrees with their labels and a line
# turning one degree a frame, colored by its hue, in a 720x400 window. The
# example's own sinf/cosf follow the libm profile: under M.AppleLibm{} (whole
# degrees except 13, 19, 22, 103 and 188) the 13th frame is refused
# (docs/SINCOSF.md). Jonlib strings are C byte strings, so the degree sign is
# written as its two UTF-8 bytes. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{total: F32}

# totalAngle += 1, wrapping at 360.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+total} = state
  +next = (total + 1.0 : F32)
  (core, State{Bool.pick(F32, (next >= 360.0 : F32), (next - 360.0 : F32), next)})

def point.at(+length: F32, cosine: Maybe<F32>, sine: Maybe<F32>) -> Maybe<M.Vector2>:
  match cosine sine:
    case Some{c} Some{s}: Some{M.Vector2{(360.0 + c * length : F32), (200.0 + s * length : F32)}}
    case _ _: None{}

# center + (cosf(rad)*length, sinf(rad)*length), None outside the profile.
def point(+libm: M.Libm, +rad: F32, +length: F32) -> Maybe<M.Vector2>:
  point.at(length, M.Libm.cos(libm, rad), M.Libm.sin(libm, rad))

def color(index: U32) -> U32:
  match index:
    case 0: J.Color.GREEN()
    case 1: J.Color.ORANGE()
    case 2: J.Color.BLUE()
    case _: J.Color.MAGENTA()

def fixed.text.at(text: String, position: M.Vector2, +col: U32, frame: J.Frame) -> J.Frame:
  M.Vector2{x, y} = position
  J.Draw.text(frame, text, F32.trunc(x), F32.trunc(y), 20.0, col)

def fixed.text(text: Maybe<String>, position: M.Vector2, +col: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: fixed.text.at(t, position, col, frame)

def fixed.drawn(+angle: U32, +col: U32, end: Maybe<M.Vector2>, text: Maybe<M.Vector2>, frame: J.Frame) -> J.Frame:
  match end text:
    case Some{e} Some{t}: fixed.text(J.Text.format("%d\u{c2}\u{b0}", [J.TextInt{angle}]), t, col, J.Draw.line_ex(frame, M.Vector2{360.0, 200.0}, e, 5.0, col))
    case _ _: J.Frame.refuse(frame)

# DrawLineEx to the angle's end and its label 20 pixels further.
def fixed(n: Nat, +libm: M.Libm, +i: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p:
      +rad = (U32.to_f32((30 * i : U32)) * (3.14159265358979323846 / 180.0) : F32)
      fixed(p, libm, (i + 1 : U32), fixed.drawn((30 * i : U32), color(i), point(libm, rad, 150.0), point(libm, rad, (150.0 + 20.0 : F32)), frame))

def turning(+total: F32, end: Maybe<M.Vector2>, frame: J.Frame) -> J.Frame:
  match end:
    case None{}: J.Frame.refuse(frame)
    case Some{e}: J.Draw.line_ex(frame, M.Vector2{360.0, 200.0}, e, 5.0, J.Color.from_hsv(total, 0.8, 0.9))

# fmodf(totalAngle, 360.0f) is totalAngle itself (0 <= totalAngle < 360).
def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+total} = state
  f1 = J.Draw.text(J.Frame.clear_background(frame, J.Color.WHITE()), "Fixed angles + rotating line", 10.0, 10.0, 20.0, J.Color.LIGHTGRAY())
  (core, (state, turning(total, point(libm, (total * (3.14159265358979323846 / 180.0) : F32), 150.0), fixed(4n, libm, 0, f1))))

# The main loop's body; libm is the profile of the example's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(720, 400): SetTargetFPS(60), totalAngle 0.
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{0.0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - math angle rotation", 720, 400, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
