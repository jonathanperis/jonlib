# raylib [core] example - custom frame control, ported to Jonlib.
# Adapted from raylib 6.2 examples/core/core_custom_frame_control.c
# (zlib/libpng, Copyright (c) 2021-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# The example runs its own frame: PollInputEvents before reading the keys,
# and after EndDrawing SwapScreenBuffer, two GetTime readings and a WaitTime
# to its own target of 60 frames a second, from which it measures the frame
# time that moves a circle. It is written for a raylib built with
# SUPPORT_CUSTOM_FRAME_CONTROL; the reference is the default build, whose
# EndDrawing swaps and polls already. So the example's PollInputEvents is a
# second poll, which on the memory platform makes every press an old one:
# SPACE, UP and DOWN are never seen, and the port keeps that poll
# (Core.poll_input_events). Its SwapScreenBuffer shows the buffer EndDrawing
# already showed: nothing here. The timing after EndDrawing is the program's
# `after` (J.Effects, docs/DRIVER.md), in binary64 as the example computes
# it. DrawCircle's sinf/cosf follow the libm profile (whole degrees).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: no refusal so far. previous is previousTime, delta deltaTime,
# counter timeCounter and target targetFPS.
type State is Data:
  State{valid: Bool, previous: M.Float64, delta: F32, counter: F32, position: F32, pause: Bool, target: U32}

# if (IsKeyPressed(KEY_UP)) targetFPS += 20; else if (IsKeyPressed(KEY_DOWN)) targetFPS -= 20; if (targetFPS < 0) targetFPS = 0.
def retargeted(+core: J.Core, +target: U32) -> U32:
  Bool.pick(U32, J.Input.is_key_pressed(core, 265), (target + 20 : U32), Bool.pick(U32, J.Input.is_key_pressed(core, 264), Bool.pick(U32, (target < 20 : U32), 0, (target - 20 : U32)), target))

# position += 200*deltaTime; if (position >= GetScreenWidth()) position = 0.
def moved(+position: F32, +delta: F32) -> F32:
  +next = (position + 200.0 * delta : F32)
  Bool.pick(F32, (next >= 800.0 : F32), 0.0, next)

# PollInputEvents(); the keys; the circle at 200 pixels a second unless paused.
def update.polled(+core: J.Core, +state: State) -> J.Core & State:
  State{+valid, +previous, +delta, +counter, +position, +pause, +target} = state
  +paused = Bool.pick(Bool, J.Input.is_key_pressed(core, 32), Bool.not(pause), pause)
  (core, State{valid, previous, delta, Bool.pick(F32, paused, counter, (counter + delta : F32)), Bool.pick(F32, paused, position, moved(position, delta)), paused, retargeted(core, target)})

def update(+core: J.Core, +state: State) -> J.Core & State:
  update.polled(J.Core.poll_input_events(core, J.Core.get_time(core)), state)

def label(text: Maybe<String>, frame: J.Frame, +x: F32, +y: F32, +color: U32) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, y, 20.0, color)

# for (int i = 0; i < GetScreenWidth()/200; i++) DrawRectangle(200*i, 0, 1, GetScreenHeight(), SKYBLUE).
def rules(frame: J.Frame) -> J.Frame:
  J.Draw.rectangle(J.Draw.rectangle(J.Draw.rectangle(J.Draw.rectangle(frame, 0.0, 0.0, 1.0, 450.0, J.Color.SKYBLUE()), 200.0, 0.0, 1.0, 450.0, J.Color.SKYBLUE()), 400.0, 0.0, 1.0, 450.0,
    J.Color.SKYBLUE()), 600.0, 0.0, 1.0, 450.0, J.Color.SKYBLUE())

# if (deltaTime != 0) "CURRENT FPS: %i" of (int)(1.0f/deltaTime); a quotient outside int is refused (the conversion is undefined).
def rate(kind: U32, +delta: F32, frame: J.Frame) -> J.Frame:
  match kind:
    case 0: frame
    case 1: label(J.Text.format("CURRENT FPS: %i", [J.TextInt{F32.to_u32((1.0 / delta : F32))}]), frame, 580.0, 40.0, J.Color.GREEN())
    case _: J.Frame.refuse(frame)

def draw.scene(+libm: M.Libm, +delta: F32, +counter: F32, +position: F32, +target: U32, frame: J.Frame) -> J.Frame:
  +x = U32.to_f32(F32.to_u32(position))
  f1 = J.Draw.circle_for(libm, rules(J.Frame.clear_background(frame, J.Color.RAYWHITE())), x, 200.0, 50.0, J.Color.RED())
  f2 = label(J.Text.format("%03.0f ms", [J.TextFloat{(counter * 1000.0 : F32)}]), f1, (x - 40.0 : F32), 125.0, J.Color.MAROON())
  f3 = label(J.Text.format("PosX: %03.0f", [J.TextFloat{position}]), f2, (x - 50.0 : F32), 265.0, J.Color.BLACK())
  f4 = J.Draw.text(f3, "Circle is moving at a constant 200 pixels/sec,\nindependently of the frame rate.", 10.0, 10.0, 20.0, J.Color.DARKGRAY())
  f5 = J.Draw.text(J.Draw.text(f4, "PRESS SPACE to PAUSE MOVEMENT", 10.0, 390.0, 20.0, J.Color.GRAY()), "PRESS UP | DOWN to CHANGE TARGET FPS", 10.0, 420.0, 20.0, J.Color.GRAY())
  rate(Bool.pick(U32, F32.is_eq(delta, 0.0), 0, Bool.pick(U32, ((1.0 / delta) < 2147483648.0 : F32), 1, 2)), delta, label(J.Text.format("TARGET FPS: %i", [J.TextInt{target}]), f5, 580.0, 10.0, J.Color.LIME()))

def draw.at(valid: Bool, +libm: M.Libm, +delta: F32, +counter: F32, +position: F32, +target: U32, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}: draw.scene(libm, delta, counter, position, target, frame)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, +delta, +counter, +position, _, +target} = state
  (core, (state, draw.at(valid, libm, delta, counter, position, target, frame)))

def timed(+core: J.Core, +state: State, +valid: Bool, +previous: M.Float64, +delta: F32) -> J.Core & State:
  State{+was, _, _, +counter, +position, +pause, +target} = state
  (core, State{was && valid, previous, delta, counter, position, pause, target})

# deltaTime = (float)(currentTime - previousTime) after the wait, or (float)updateDrawTime; previousTime = currentTime.
def measured(+core: J.Core, +state: State, delta: Maybe<F32>) -> J.Core & State:
  State{_, _, +old, _, _, _, _} = state
  match delta:
    case None{}: timed(core, state, False{}, J.Core.get_time(core), old)
    case Some{+d}: timed(core, state, True{}, J.Core.get_time(core), d)

def narrowed(value: Maybe<M.Float64>) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{v}: M.Float64.to_f32(v)

# WaitTime((float)waitTime); currentTime = GetTime().
def waited(+before: J.Core, +state: State, woke: Maybe<J.Core>) -> J.Core & State:
  State{_, +previous, +old, _, _, _, _} = state
  match woke:
    case None{}: timed(before, state, False{}, previous, old)
    case Some{+core}: measured(core, state, narrowed(M.Float64.internal.subtract(J.Core.get_time(core), previous)))

# Whether a binary64 value is above 0.0.
def positive(value: M.Float64) -> Bool:
  M.Float64{+high, +low} = value
  (high < 2147483648 : U32) && Bool.not(U32.is_eq((high .|. low : U32), 0))

# if (waitTime > 0.0) the wait; otherwise deltaTime keeps its value and previousTime = currentTime.
def wait.kind(+core: J.Core, +state: State, +seconds: F32, long: Bool) -> J.Core & State:
  State{_, _, +old, _, _, _, _} = state
  match long:
    case True{}: waited(core, state, J.Core.wait_time(core, M.Float64.from_f32(seconds)))
    case False{}: timed(core, state, True{}, J.Core.get_time(core), old)

def wait.long(+core: J.Core, +state: State, +long: Bool, seconds: Maybe<F32>) -> J.Core & State:
  State{_, +previous, +old, _, _, _, _} = state
  match seconds:
    case None{}: timed(core, state, False{}, previous, old)
    case Some{+s}: wait.kind(core, state, s, long)

# waitTime = (1.0f/(float)targetFPS) - updateDrawTime.
def wait.time(+core: J.Core, +state: State, wait: Maybe<M.Float64>) -> J.Core & State:
  State{_, +previous, +old, _, _, _, _} = state
  match wait:
    case None{}: timed(core, state, False{}, previous, old)
    case Some{+w}: wait.long(core, state, positive(w), M.Float64.to_f32(w))

# A fixed frame rate (targetFPS > 0), else deltaTime = (float)updateDrawTime.
def paced(+elapsed: M.Float64, +core: J.Core, +state: State, fixed: Bool) -> J.Core & State:
  State{_, _, _, _, _, _, +target} = state
  match fixed:
    case True{}: wait.time(core, state, M.Float64.internal.subtract(M.Float64.from_f32((1.0 / U32.to_f32(target) : F32)), elapsed))
    case False{}: measured(core, state, M.Float64.to_f32(elapsed))

# currentTime = GetTime(); updateDrawTime = currentTime - previousTime.
def after.spent(+core: J.Core, +state: State, elapsed: Maybe<M.Float64>) -> J.Core & State:
  State{_, +previous, +old, _, _, _, +target} = state
  match elapsed:
    case None{}: timed(core, state, False{}, previous, old)
    case Some{+e}: paced(e, core, state, (target > 0 : U32))

# After EndDrawing: SwapScreenBuffer() (the buffer EndDrawing showed), then the example's own frame time control.
def after(+core: J.Core, +state: State) -> J.Core & State:
  State{_, +previous, _, _, _, _, _} = state
  after.spent(core, state, M.Float64.internal.subtract(J.Core.get_time(core), previous))

def framed(r: J.Core & State, frame: J.Frame) -> J.Core & (State & J.Frame):
  (core, state) = r
  (core, (state, frame))

# The main loop's body; libm is the sinf/cosf profile of DrawCircle.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Effects{core => state => frame => IO.pure(J.Core & (State & J.Frame), framed(update(core, state), frame)), core => state => frame => draw(libm, core, state, frame),
    core => state => frame => IO.pure(J.Core & (State & J.Frame), framed(after(core, state), frame))}

# After InitWindow(800, 450): previousTime = GetTime(); the target of 60 frames a second (SetTargetFPS is not called).
def setup(+core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.pure(J.Core & (J.Frame & State), (core, (frame, State{True{}, J.Core.get_time(core), 0.0, 0.0, 0.0, False{}, 60})))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - custom frame control", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
