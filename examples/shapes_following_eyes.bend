# raylib [shapes] example - following eyes, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_following_eyes.c (zlib/libpng,
# Copyright (c) 2013-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Two eyes whose irises follow the mouse, held inside the scleras: outside
# them the iris sits at the angle atan2f(dy, dx) (the negated checked
# Vector2LineAngle, the same subtractions) with the profile's sinf/cosf. A
# position the libm profile cannot reproduce refuses the frame; under
# M.AppleLibm{} that is every mouse position outside both scleras' reach
# (docs/ANGLES.md, docs/SINCOSF.md). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def held.at(+sx: F32, +sy: F32, cosine: Maybe<F32>, sine: Maybe<F32>) -> Maybe<M.Vector2>:
  match cosine sine:
    case Some{c} Some{s}: Some{M.Vector2{(sx + (80.0 - 24.0) * c : F32), (sy + (80.0 - 24.0) * s : F32)}}
    case _ _: None{}

# angle = atan2f(dy, dx); sclera + (scleraRadius - irisRadius)*(cosf(angle), sinf(angle)).
def held(+libm: M.Libm, +sx: F32, +sy: F32, angle: Maybe<F32>) -> Maybe<M.Vector2>:
  match angle:
    case None{}: None{}
    case Some{+negated}: held.at(sx, sy, M.Libm.cos(libm, F32.neg(negated)), M.Libm.sin(libm, F32.neg(negated)))

# The iris: the mouse inside the sclera's reach, else held on its edge.
def iris(inside: Bool, +libm: M.Libm, +mouse: M.Vector2, +sx: F32, +sy: F32) -> Maybe<M.Vector2>:
  match inside:
    case True{}: Some{mouse}
    case False{}: held(libm, sx, sy, M.Vector2.line_angle_for(libm, M.Vector2{sx, sy}, mouse))

def eye(+libm: M.Libm, +sx: F32, +sy: F32, +color: U32, position: Maybe<M.Vector2>, frame: J.Frame) -> J.Frame:
  match position:
    case None{}: J.Frame.refuse(frame)
    case Some{+p}:
      f1 = J.Draw.circle_v_for(libm, frame, M.Vector2{sx, sy}, 80.0, J.Color.LIGHTGRAY())
      J.Draw.circle_v_for(libm, J.Draw.circle_v_for(libm, f1, p, 24.0, color), p, 10.0, J.Color.BLACK())

def look(+libm: M.Libm, +mouse: M.Vector2, +sx: F32, +sy: F32) -> Maybe<M.Vector2>:
  iris(J.Collision.point_circle(mouse, M.Vector2{sx, sy}, (80.0 - 24.0 : F32)), libm, mouse, sx, sy)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.eyes(+libm: M.Libm, +mouse: M.Vector2, frame: J.Frame) -> J.Frame:
  f1 = eye(libm, (800.0 / 2.0 - 100.0 : F32), (450.0 / 2.0 : F32), J.Color.BROWN(), look(libm, mouse, (800.0 / 2.0 - 100.0 : F32), (450.0 / 2.0 : F32)), frame)
  eye(libm, (800.0 / 2.0 + 100.0 : F32), (450.0 / 2.0 : F32), J.Color.DARKGREEN(), look(libm, mouse, (800.0 / 2.0 + 100.0 : F32), (450.0 / 2.0 : F32)), f1)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  f1 = draw.eyes(libm, J.Input.get_mouse_position(core), J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  draw.fps.done(state, f1, J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the profile of atan2f, sinf/cosf and DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - following eyes", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
