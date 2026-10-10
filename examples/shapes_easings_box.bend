# raylib [shapes] example - easings box, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_easings_box.c and the
# EaseElasticOut/EaseBounceOut/EaseQuadOut/EaseCircOut/EaseSineOut of
# examples/shapes/reasings.h (zlib/libpng, Copyright (c) 2014-2025 Ramon
# Santamaria (@raysan5); reasings.h after Robert Penner's easing equations,
# BSD); see LICENSES/raylib.txt.
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

# rec (its x stays GetScreenWidth()/2), rotation, alpha, state and framesCounter; ok: no refusal so far.
type State is Data:
  State{y: F32, width: F32, height: F32, rotation: F32, alpha: F32, phase: U32, frames: U32, ok: Bool}

def elastic_out.at(+b: F32, +c: F32, power: Maybe<F32>, sine: Maybe<F32>) -> Maybe<F32>:
  match power sine:
    case Some{+p} Some{+s}: Some{(c * p * s + c + b : F32)}
    case _ _: None{}

# p = d*0.3f, a = c, s = p/4: a*powf(2, -10*t)*sinf((t*d - s)*(2*PI)/p) + c + b, t being t/d.
def elastic_out.moving(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  +p = (d * 0.3 : F32)
  +s = (p / 4.0 : F32)
  elastic_out.at(b, c, M.Libm.pow2(libm, (F32.neg(10.0) * t : F32)), M.Libm.sin(libm, ((t * d - s) * (2.0 * M.Math.PI()) / p : F32)))

# EaseElasticOut(t, b, c, d): b at t == 0, b + c where t/d == 1.
def elastic_out(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, F32.is_eq(t, 0.0), Some{b}, Bool.pick(Maybe<F32>, F32.is_eq((t / d : F32), 1.0), Some{(b + c : F32)}, elastic_out.moving(libm, (t / d : F32), b, c, d)))

# The later arcs: postFix = t -= offset; c*(7.5625f*postFix*t + rise) + b.
def bounce.arc(+t: F32, +b: F32, +c: F32, +offset: F32, +rise: F32) -> F32:
  (c * (7.5625 * (t - offset) * (t - offset) + rise) + b : F32)

# EaseBounceOut(t, b, c, d). The example's third bound is the double 2.5/2.75; a float is below it exactly when it is
# below the float 2.5f/2.75f (the nearest float, which is above the double).
def bounce_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  +u = (t / d : F32)
  Bool.pick(F32, (u < (1.0 / 2.75) : F32), (c * (7.5625 * u * u) + b : F32),
    Bool.pick(F32, (u < (2.0 / 2.75) : F32), bounce.arc(u, b, c, (1.5 / 2.75 : F32), 0.75),
      Bool.pick(F32, (u < (2.5 / 2.75) : F32), bounce.arc(u, b, c, (2.25 / 2.75 : F32), 0.9375), bounce.arc(u, b, c, (2.625 / 2.75 : F32), 0.984375))))

# EaseQuadOut(t, b, c, d): t /= d; -c*t*(t - 2) + b.
def quad_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  +u = (t / d : F32)
  (F32.neg(c) * u * (u - 2.0) + b : F32)

# EaseCircOut(t, b, c, d): t = t/d - 1; c*sqrtf(1 - t*t) + b.
def circ_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  +u = (t / d - 1.0 : F32)
  (c * F32.sqrt((1.0 - u * u : F32)) + b : F32)

def sine_out.at(+b: F32, +c: F32, sine: Maybe<F32>) -> Maybe<F32>:
  match sine:
    case None{}: None{}
    case Some{+s}: Some{(c * s + b : F32)}

# EaseSineOut(t, b, c, d): c*sinf(t/d*(PI/2)) + b.
def sine_out(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  sine_out.at(b, c, M.Libm.sin(libm, (t / d * (M.Math.PI() / 2.0) : F32)))

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
    case 0: dropped(state, n, elastic_out(libm, U32.to_f32(n), F32.neg(100.0), (450.0 / 2.0 + 100.0 : F32), 120.0))
    case 1: State{y, bounce_out(U32.to_f32(n), 100.0, 800.0, 120.0), bounce_out(U32.to_f32(n), 100.0, F32.neg(90.0), 120.0), rotation, alpha, next((n >= 120 : U32), 1), count((n >= 120 : U32), n), ok}
    case 2: State{y, width, height, quad_out(U32.to_f32(n), 0.0, 270.0, 240.0), alpha, next((n >= 240 : U32), 2), count((n >= 240 : U32), n), ok}
    case 3: State{y, width, circ_out(U32.to_f32(n), 10.0, 800.0, 120.0), rotation, alpha, next((n >= 120 : U32), 3), count((n >= 120 : U32), n), ok}
    case 4: faded(state, n, sine_out(libm, U32.to_f32(n), 1.0, F32.neg(1.0), 160.0))
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
