# raylib [shapes] example - bouncing ball, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_bouncing_ball.c (zlib/libpng,
# Copyright (c) 2013-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# SPACE pauses the ball, G toggles gravity. SetConfigFlags(FLAG_MSAA_4X_HINT)
# before InitWindow: Desktop.run_flags and J.Frame.init_window_flags (the
# software renderer only moves the shapes texture rectangle). DrawFPS reads
# GetFPS at GetTime(), the Core's clock. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{position: M.Vector2, speed: M.Vector2, gravity: Bool, pause: Bool, frames: U32}

def float(+word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# The walls: x >= GetScreenWidth() - ballRadius or x <= ballRadius flips the
# x speed (*= -1.0f); y the same with the height flips and damps (*= -0.95f).
def bounced(+x: F32, +y: F32, +sx: F32, +sy: F32) -> M.Vector2:
  +hit_x = (x >= 780.0 : F32) || (x <= 20.0 : F32)
  +hit_y = (y >= 430.0 : F32) || (y <= 20.0 : F32)
  M.Vector2{Bool.pick(F32, hit_x, (sx * F32.neg(1.0) : F32), sx), Bool.pick(F32, hit_y, (sy * F32.neg(float(1064514355)) : F32), sy)}

# Position += speed; with gravity speed.y += 0.2f; then the wall checks.
def moved(+gravity: Bool, +position: M.Vector2, +speed: M.Vector2) -> M.Vector2 & M.Vector2:
  M.Vector2{+px, +py} = position
  M.Vector2{+sx, +sy} = speed
  +x = (px + sx : F32)
  +y = (py + sy : F32)
  (M.Vector2{x, y}, bounced(x, y, sx, Bool.pick(F32, gravity, (sy + float(1045220557) : F32), sy)))

def update.moved(+core: J.Core, +gravity: Bool, +frames: U32, result: M.Vector2 & M.Vector2) -> J.Core & State:
  (+position, +speed) = result
  (core, State{position, speed, gravity, False{}, frames})

def update.paused(+core: J.Core, +gravity: Bool, +pause: Bool, +position: M.Vector2, +speed: M.Vector2, +frames: U32) -> J.Core & State:
  match pause:
    case True{}: (core, State{position, speed, gravity, pause, (frames + 1 : U32)})
    case False{}: update.moved(core, gravity, frames, moved(gravity, position, speed))

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+position, +speed, +gravity, +pause, +frames} = state
  +g = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_G()), Bool.not(gravity), gravity)
  +p = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), Bool.not(pause), pause)
  update.paused(core, g, p, position, speed, frames)

def draw.gravity(gravity: Bool, frame: J.Frame) -> J.Frame:
  match gravity:
    case True{}: J.Draw.text(frame, "GRAVITY: ON (Press G to disable)", 10.0, 400.0, 20.0, J.Color.DARKGREEN())
    case False{}: J.Draw.text(frame, "GRAVITY: OFF (Press G to enable)", 10.0, 400.0, 20.0, J.Color.RED())

# On pause, PAUSED blinks: shown while (framesCounter/30)%2 is 1.
def draw.paused(blink: Bool, frame: J.Frame) -> J.Frame:
  match blink:
    case True{}: J.Draw.text(frame, "PAUSED", 350.0, 200.0, 30.0, J.Color.GRAY())
    case False{}: frame

def draw.fps.at(+state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+position, +speed, +gravity, +pause, +frames} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.circle_v_for(libm, f1, position, 20.0, J.Color.MAROON())
  f3 = J.Draw.text(f2, "PRESS SPACE to PAUSE BALL MOVEMENT", 10.0, 425.0, 20.0, J.Color.LIGHTGRAY())
  f4 = draw.paused(pause && U32.is_eq(((frames / 30) % 2 : U32), 1), draw.gravity(gravity, f3))
  draw.fps.done(state, f4, J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the sinf/cosf profile of DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): the ball at the screen's center, speed (5, 4),
# gravity on, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{M.Vector2{400.0, 225.0}, M.Vector2{5.0, 4.0}, True{}, False{}, 0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, J.ConfigFlags.FLAG_MSAA_4X_HINT(), "raylib [shapes] example - bouncing ball",
    800, 450, J.Desktop.frames_arg(args), core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
