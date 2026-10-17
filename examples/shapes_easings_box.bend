# raylib [shapes] example - easings box, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_easings_box.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt. EaseElasticOut, EaseBounceOut, EaseQuadOut, EaseCircOut
# and EaseSineOut are Joneasings' (docs/EASINGS.md).
#
# A box dropped to the center (elastic out), flattened into a bar (bounce
# out), turned (quad out), grown over the screen (circ out) and faded (sine
# out); SPACE resets it. The elastic easing's powf(2, x) and sinf, the sine
# easing's sinf and DrawRectanglePro's sinf/cosf follow the libm profile
# (M.Libm.pow2, docs/MATH.md; docs/SINCOSF.md): a value outside it refuses
# that frame and every later one. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../joneasings.bend as E

# rec (its x stays GetScreenWidth()/2), rotation, alpha, state and framesCounter; ok: no refusal so far.
type State is Data:
  State{y: F32, width: F32, height: F32, rotation: F32, alpha: F32, phase: U32, frames: U32, ok: Bool}

def next(+done: Bool, +phase: U32) -> U32:
  Bool.pick(U32, done, (phase + 1 : U32), phase)

def count(+done: Bool, +n: U32) -> U32:
  Bool.pick(U32, done, 0, n)

# state 0: rec.y = EaseElasticOut(framesCounter, -100, GetScreenHeight()/2.0f + 100, 120).
def dropped(+state: State, +n: U32, value: Maybe<F32>) -> State:
  State{+y, +width, +height, +rotation, +alpha, _, _, +ok} = state
  match value:
    case None{}: State{y, width, height, rotation, alpha, 0, n, False{}}
    case Some{+v}: State{v, width, height, rotation, alpha, next((n >= 120 : U32), 0), count((n >= 120 : U32), n), ok}

# state 4: alpha = EaseSineOut(framesCounter, 1.0f, -1.0f, 160).
def faded(+state: State, +n: U32, value: Maybe<F32>) -> State:
  State{+y, +width, +height, +rotation, +alpha, _, _, +ok} = state
  match value:
    case None{}: State{y, width, height, rotation, alpha, 4, n, False{}}
    case Some{+v}: State{y, width, height, rotation, v, next((n >= 160 : U32), 4), count((n >= 160 : U32), n), ok}

# The state's easing on framesCounter + 1; state 1 flattens the box (120 frames), 2 turns it 270 degrees (240), 3 grows it (120).
def stepped(+libm: M.Libm, +state: State, +n: U32, phase: U32) -> State:
  State{+y, +width, +height, +rotation, +alpha, _, _, +ok} = state
  match phase:
    case 0: dropped(state, n, E.Ease.elastic_out_for(libm, U32.to_f32(n), F32.neg(100.0), (450.0 / 2.0 + 100.0 : F32), 120.0))
    case 1: State{y, E.Ease.bounce_out(U32.to_f32(n), 100.0, 800.0, 120.0), E.Ease.bounce_out(U32.to_f32(n), 100.0, F32.neg(90.0), 120.0), rotation, alpha, next((n >= 120 : U32), 1), count((n >= 120 : U32), n), ok}
    case 2: State{y, width, height, E.Ease.quad_out(U32.to_f32(n), 0.0, 270.0, 240.0), alpha, next((n >= 240 : U32), 2), count((n >= 240 : U32), n), ok}
    case 3: State{y, width, E.Ease.circ_out(U32.to_f32(n), 10.0, 800.0, 120.0), rotation, alpha, next((n >= 120 : U32), 3), count((n >= 120 : U32), n), ok}
    case 4: faded(state, n, E.Ease.sine_out_for(libm, U32.to_f32(n), 1.0, F32.neg(1.0), 160.0))
    case _: state

# SPACE: the box, its rotation and alpha, the state and the counter as at the start.
def reset(+pressed: Bool, +state: State) -> State:
  State{_, _, _, _, _, _, _, +ok} = state
  Bool.pick(State, pressed, State{F32.neg(100.0), 100.0, 100.0, 0.0, 1.0, 0, 0, ok}, state)

def frames.of(state: State) -> U32:
  State{_, _, _, _, _, _, +frames, _} = state
  frames

def phase.of(state: State) -> U32:
  State{_, _, _, _, _, +phase, _, _} = state
  phase

def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  (core, reset(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), stepped(libm, state, (frames.of(state) + 1 : U32), phase.of(state))))

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

# DrawRectanglePro(rec, (rec.width/2, rec.height/2), rotation, Fade(BLACK, alpha)).
def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+y, +width, +height, +rotation, +alpha, _, _, +ok} = state
  f1 = J.Draw.rectangle_pro_for(libm, J.Frame.clear_background(checked(ok, frame), J.Color.RAYWHITE()), J.Rectangle{(800.0 / 2.0 : F32), y, width, height}, M.Vector2{(width / 2.0 : F32), (height / 2.0 : F32)},
    rotation, J.Color.with_alpha(J.Color.BLACK(), alpha))
  (core, (state, J.Draw.text(f1, "PRESS [SPACE] TO RESET BOX ANIMATION!", 10.0, (450.0 - 25.0 : F32), 20.0, J.Color.LIGHTGRAY())))

# The main loop's body; libm is the profile of the easings' powf(2, x) and sinf and of DrawRectanglePro's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): rec = (400, -100, 100, 100), no rotation, alpha 1, state 0, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{F32.neg(100.0), 100.0, 100.0, 0.0, 1.0, 0, 0, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - easings box", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
