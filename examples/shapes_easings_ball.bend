# raylib [shapes] example - easings ball, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_easings_ball.c and the
# EaseElasticOut/EaseElasticIn/EaseCubicOut of examples/shapes/reasings.h
# (zlib/libpng, Copyright (c) 2014-2025 Ramon Santamaria (@raysan5);
# reasings.h after Robert Penner's easing equations, BSD); see
# LICENSES/raylib.txt.
#
# A ball eased across the screen (elastic out, 120 frames), grown (elastic
# in, 200 frames) and faded over a green background (cubic out, 200
# frames); ENTER plays it again and R restarts the current step. The
# elastic easings' powf(2, x) and sinf, and DrawCircle's sinf/cosf, follow
# the libm profile (M.Libm.pow2, docs/MATH.md; docs/SINCOSF.md): a value
# outside it refuses that frame and every later one. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# ballPositionX, ballRadius (both C ints), ballAlpha, state and framesCounter; ok: no refusal so far.
type State is Data:
  State{x: F32, radius: F32, alpha: F32, phase: U32, frames: U32, ok: Bool}

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

def elastic_in.at(+b: F32, +c: F32, power: Maybe<F32>, sine: Maybe<F32>) -> Maybe<F32>:
  match power sine:
    case Some{+p} Some{+s}: Some{(F32.neg((c * p * s : F32)) + b : F32)}
    case _ _: None{}

# postFix = a*powf(2, 10*(t -= 1)): -(postFix*sinf((t*d - s)*(2*PI)/p)) + b, t being t/d - 1.
def elastic_in.moving(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  +p = (d * 0.3 : F32)
  +s = (p / 4.0 : F32)
  elastic_in.at(b, c, M.Libm.pow2(libm, (10.0 * t : F32)), M.Libm.sin(libm, ((t * d - s) * (2.0 * M.Math.PI()) / p : F32)))

# EaseElasticIn(t, b, c, d): b at t == 0, b + c where t/d == 1.
def elastic_in(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, F32.is_eq(t, 0.0), Some{b}, Bool.pick(Maybe<F32>, F32.is_eq((t / d : F32), 1.0), Some{(b + c : F32)}, elastic_in.moving(libm, (t / d - 1.0 : F32), b, c, d)))

# EaseCubicOut(t, b, c, d): t = t/d - 1; c*(t*t*t + 1) + b.
def cubic_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  +u = (t / d - 1.0 : F32)
  (c * (u * u * u + 1.0) + b : F32)

# state 0: ballPositionX = (int)EaseElasticOut(framesCounter, -100, screenWidth/2.0f + 100, 120), then state 1 at 120 frames.
def moved(+radius: F32, +alpha: F32, +n: U32, +ok: Bool, +x: F32, value: Maybe<F32>) -> State:
  match value:
    case None{}: State{x, radius, alpha, 0, n, False{}}
    case Some{+v}: State{F32.trunc(v), radius, alpha, Bool.pick(U32, (n >= 120 : U32), 1, 0), Bool.pick(U32, (n >= 120 : U32), 0, n), ok}

# state 1: ballRadius = (int)EaseElasticIn(framesCounter, 20, 500, 200), then state 2 at 200 frames.
def grown(+x: F32, +alpha: F32, +n: U32, +ok: Bool, +radius: F32, value: Maybe<F32>) -> State:
  match value:
    case None{}: State{x, radius, alpha, 1, n, False{}}
    case Some{+v}: State{x, F32.trunc(v), alpha, Bool.pick(U32, (n >= 200 : U32), 2, 1), Bool.pick(U32, (n >= 200 : U32), 0, n), ok}

# state 2: ballAlpha = EaseCubicOut(framesCounter, 0, 1, 200), then state 3; state 3: ENTER plays again.
def stepped(phase: U32, +libm: M.Libm, +core: J.Core, +x: F32, +radius: F32, +alpha: F32, +n: U32, +frames: U32, +ok: Bool) -> State:
  match phase:
    case 0: moved(radius, alpha, n, ok, x, elastic_out(libm, U32.to_f32(n), F32.neg(100.0), (800.0 / 2.0 + 100.0 : F32), 120.0))
    case 1: grown(x, alpha, n, ok, radius, elastic_in(libm, U32.to_f32(n), 20.0, 500.0, 200.0))
    case 2: State{x, radius, cubic_out(U32.to_f32(n), 0.0, 1.0, 200.0), Bool.pick(U32, (n >= 200 : U32), 3, 2), Bool.pick(U32, (n >= 200 : U32), 0, n), ok}
    case _: Bool.pick(State, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_ENTER()), State{F32.neg(100.0), 20.0, 0.0, 0, frames, ok}, State{x, radius, alpha, 3, frames, ok})

# if (IsKeyPressed(KEY_R)) framesCounter = 0.
def restarted(+restart: Bool, +state: State) -> State:
  State{+x, +radius, +alpha, +phase, +frames, +ok} = state
  State{x, radius, alpha, phase, Bool.pick(U32, restart, 0, frames), ok}

def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+x, +radius, +alpha, +phase, +frames, +ok} = state
  (core, restarted(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_R()), stepped(phase, libm, core, x, radius, alpha, (frames + 1 : U32), frames, ok)))

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

# if (state >= 2) DrawRectangle(0, 0, screenWidth, screenHeight, GREEN).
def backed(green: Bool, frame: J.Frame) -> J.Frame:
  match green:
    case False{}: frame
    case True{}: J.Draw.rectangle(frame, 0.0, 0.0, 800.0, 450.0, J.Color.GREEN())

# if (state == 3) DrawText("PRESS [ENTER] TO PLAY AGAIN!", 240, 200, 20, BLACK).
def prompted(done: Bool, frame: J.Frame) -> J.Frame:
  match done:
    case False{}: frame
    case True{}: J.Draw.text(frame, "PRESS [ENTER] TO PLAY AGAIN!", 240.0, 200.0, 20.0, J.Color.BLACK())

# DrawCircle(ballPositionX, 200, (float)ballRadius, Fade(RED, 1.0f - ballAlpha)).
def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+x, +radius, +alpha, +phase, _, +ok} = state
  f1 = backed((phase >= 2 : U32), J.Frame.clear_background(checked(ok, frame), J.Color.RAYWHITE()))
  (core, (state, prompted(U32.is_eq(phase, 3), J.Draw.circle_for(libm, f1, x, 200.0, radius, J.Color.with_alpha(J.Color.RED(), (1.0 - alpha : F32))))))

# The main loop's body; libm is the profile of the easings' powf(2, x) and sinf and of DrawCircle's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): the ball at x = -100 with radius 20 and alpha 0, state 0, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{F32.neg(100.0), 20.0, 0.0, 0, 0, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - easings ball", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
