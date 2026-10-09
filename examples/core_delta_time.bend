# raylib [core] example - delta time, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_delta_time.c (zlib/libpng,
# Copyright (c) 2025 Robin (@RobinsAviary)); see LICENSES/raylib.txt.
#
# One circle moves by GetFrameTime(), the other a fixed step per frame; the
# wheel changes the FPS target, R resets. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# currentFps is a C int (two's complement in a U32).
type State is Data:
  State{fps: U32, delta: F32, fixed: F32}

def int(+x: F32) -> U32:
  Bool.pick(U32, (x < 0.0 : F32), (0 - F32.to_u32(F32.neg(F32.trunc(x))) : U32), F32.to_u32(F32.trunc(x)))

def negative(+value: U32) -> Bool:
  (value >= 2147483648 : U32)

# The wheel adds (int)move to currentFps (not below 0) and sets the target.
def target(moved: Bool, +core: J.Core, +fps: U32, +move: F32) -> J.Core & U32:
  match moved:
    case False{}: (core, fps)
    case True{}:
      +f = (fps + int(move) : U32)
      +c = Bool.pick(U32, negative(f), 0, f)
      (J.Core.set_target_fps(core, c), c)

# deltaCircle.x += GetFrameTime()*6*speed and frameCircle.x += 0.1*speed
# (speed 10), each back to 0 past the screen width; R resets both.
def update.moved(+delta: F32, +fixed: F32, r: J.Core & U32) -> J.Core & State:
  (+core, +fps) = r
  +d1 = (delta + J.Core.get_frame_time(core) * 6.0 * 10.0 : F32)
  +f1 = (fixed + 0.1 * 10.0 : F32)
  +d2 = Bool.pick(F32, (d1 > 800.0 : F32), 0.0, d1)
  +f2 = Bool.pick(F32, (f1 > 800.0 : F32), 0.0, f1)
  +reset = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_R())
  (core, State{fps, Bool.pick(F32, reset, 0.0, d2), Bool.pick(F32, reset, 0.0, f2)})

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+fps, +delta, +fixed} = state
  +move = J.Input.get_mouse_wheel_move(core)
  update.moved(delta, fixed, target(F32.is_ne(move, 0.0), core, fps, move))

def draw.line(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 20.0, J.Color.DARKGRAY())

def draw.rest(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  f1 = draw.line(J.Text.format("Frame time: %02.02f ms", [J.TextFloat{J.Core.get_frame_time(core)}]), 30.0, frame)
  f2 = J.Draw.text(f1, "Use the scroll wheel to change the fps limit, r to reset", 10.0, 50.0, 20.0, J.Color.DARKGRAY())
  f3 = J.Draw.text(f2, "FUNC: x += GetFrameTime()*speed", 10.0, 90.0, 20.0, J.Color.RED())
  (core, (state, J.Draw.text(f3, "FUNC: x += speed", 10.0, 240.0, 20.0, J.Color.BLUE())))

# "FPS: unlimited (%i)" while currentFps <= 0, else "FPS: %i (target: %i)".
def draw.fps.text(unlimited: Bool, +now: U32, +fps: U32) -> Maybe<String>:
  match unlimited:
    case True{}: J.Text.format("FPS: unlimited (%i)", [J.TextInt{now}])
    case False{}: J.Text.format("FPS: %i (target: %i)", [J.TextInt{now}, J.TextInt{fps}])

def draw.fps(+state: State, frame: J.Frame, r: J.Core & U32) -> J.Core & (State & J.Frame):
  State{+fps, _, _} = state
  (+core, +now) = r
  +unlimited = negative(fps) || U32.is_eq(fps, 0)
  draw.rest(core, state, draw.line(draw.fps.text(unlimited, now, fps), 10.0, frame))

def draw.fps.done(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps(state, frame, pair)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{_, +delta, +fixed} = state
  f1 = J.Draw.circle_v_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), M.Vector2{delta, (450.0 / 3.0 : F32)}, 32.0, J.Color.RED())
  f2 = J.Draw.circle_v_for(libm, f1, M.Vector2{fixed, (450.0 * (2.0 / 3.0) : F32)}, 32.0, J.Color.BLUE())
  draw.fps.done(state, f2, J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the sinf/cosf profile of DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): currentFps 60, both circles at x 0, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{60, 0.0, 0.0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - delta time", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
