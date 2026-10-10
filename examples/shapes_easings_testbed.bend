# raylib [shapes] example - easings testbed, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_easings_testbed.c and the
# easing functions of examples/shapes/reasings.h (zlib/libpng, Copyright (c)
# 2019-2025 Juan Miguel López (@flashback-fx) and Ramon Santamaria (@raysan5);
# reasings.h Copyright (c) 2015-2024 Ramon Santamaria (@raysan5), after
# Robert Penner's easing equations, BSD); see LICENSES/raylib.txt.
#
# A ball moved by an easing chosen for each axis (LEFT/RIGHT and UP/DOWN
# through the 28 easings and "None"), over a duration changed with Q/W and
# A/S; ENTER plays or pauses, SPACE restarts, T lets the time run past the
# duration. The sine, exponential and elastic easings' sinf, cosf and
# powf(2, x), and DrawCircleV's sinf/cosf, follow the libm profile
# (docs/SINCOSF.md; M.Libm.pow2, docs/MATH.md): a value outside it refuses
# that frame and every later one. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# t, d, paused, boundedT, easingX, easingY and ballPosition; ok: no refusal so far.
type State is Data:
  State{t: F32, d: F32, paused: Bool, bounded: Bool, x: U32, y: U32, ball: M.Vector2, ok: Bool}

# easings[kind].name.
def name(kind: U32) -> String:
  match kind:
    case 0: "EaseLinearNone"
    case 1: "EaseLinearIn"
    case 2: "EaseLinearOut"
    case 3: "EaseLinearInOut"
    case 4: "EaseSineIn"
    case 5: "EaseSineOut"
    case 6: "EaseSineInOut"
    case 7: "EaseCircIn"
    case 8: "EaseCircOut"
    case 9: "EaseCircInOut"
    case 10: "EaseCubicIn"
    case 11: "EaseCubicOut"
    case 12: "EaseCubicInOut"
    case 13: "EaseQuadIn"
    case 14: "EaseQuadOut"
    case 15: "EaseQuadInOut"
    case 16: "EaseExpoIn"
    case 17: "EaseExpoOut"
    case 18: "EaseExpoInOut"
    case 19: "EaseBackIn"
    case 20: "EaseBackOut"
    case 21: "EaseBackInOut"
    case 22: "EaseBounceOut"
    case 23: "EaseBounceIn"
    case 24: "EaseBounceInOut"
    case 25: "EaseElasticIn"
    case 26: "EaseElasticOut"
    case 27: "EaseElasticInOut"
    case _: "None"

# c*value + b for an optional value.
def scaled(+b: F32, +c: F32, value: Maybe<F32>) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{+v}: Some{(c * v + b : F32)}

# EaseSineIn: -c*cosf(t/d*(PI/2)) + c + b.
def sine_in.at(+b: F32, +c: F32, cosine: Maybe<F32>) -> Maybe<F32>:
  match cosine:
    case None{}: None{}
    case Some{+v}: Some{(F32.neg(c) * v + c + b : F32)}

# EaseSineInOut: -c/2*(cosf(PI*t/d) - 1) + b.
def sine_in_out.at(+b: F32, +c: F32, cosine: Maybe<F32>) -> Maybe<F32>:
  match cosine:
    case None{}: None{}
    case Some{+v}: Some{(F32.neg(c) / 2.0 * (v - 1.0) + b : F32)}

# EaseCircInOut: by t/(d/2) below 1 or not.
def circ_in_out(+u: F32, +b: F32, +c: F32) -> F32:
  Bool.pick(F32, (u < 1.0 : F32), (F32.neg(c) / 2.0 * (F32.sqrt((1.0 - u * u : F32)) - 1.0) + b : F32), (c / 2.0 * (F32.sqrt((1.0 - (u - 2.0) * (u - 2.0) : F32)) + 1.0) + b : F32))

# EaseCubicInOut.
def cubic_in_out(+u: F32, +b: F32, +c: F32) -> F32:
  Bool.pick(F32, (u < 1.0 : F32), (c / 2.0 * u * u * u + b : F32), (c / 2.0 * ((u - 2.0) * (u - 2.0) * (u - 2.0) + 2.0) + b : F32))

# EaseQuadInOut.
def quad_in_out(+u: F32, +b: F32, +c: F32) -> F32:
  Bool.pick(F32, (u < 1.0 : F32), ((c / 2.0) * (u * u) + b : F32), (F32.neg(c) / 2.0 * (((u - 1.0) * (u - 3.0)) - 1.0) + b : F32))

# EaseExpoOut away from t == d: c*(-powf(2, -10*t/d) + 1) + b.
def expo_out.at(+b: F32, +c: F32, power: Maybe<F32>) -> Maybe<F32>:
  match power:
    case None{}: None{}
    case Some{+p}: Some{(c * (F32.neg(p) + 1.0) + b : F32)}

# EaseExpoInOut's second half: c/2*(-powf(2, -10*(t - 1)) + 2) + b.
def expo_in_out.late(+b: F32, +c: F32, power: Maybe<F32>) -> Maybe<F32>:
  match power:
    case None{}: None{}
    case Some{+p}: Some{(c / 2.0 * (F32.neg(p) + 2.0) + b : F32)}

def expo_in_out.half(early: Bool, +libm: M.Libm, +u: F32, +b: F32, +c: F32) -> Maybe<F32>:
  match early:
    case True{}: scaled(b, (c / 2.0 : F32), M.Libm.pow2(libm, (10.0 * (u - 1.0) : F32)))
    case False{}: expo_in_out.late(b, c, M.Libm.pow2(libm, (F32.neg(10.0) * (u - 1.0) : F32)))

# EaseExpoInOut: b at t == 0, b + c at t == d, else by t/(d/2) below 1 or not.
def expo_in_out(edge: U32, +libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  match edge:
    case 0: Some{b}
    case 1: Some{(b + c : F32)}
    case _: expo_in_out.half(((t / (d / 2.0)) < 1.0 : F32), libm, (t / (d / 2.0) : F32), b, c)

# EaseBackIn: postFix = t /= d; c*postFix*t*((s + 1)*t - s) + b, s = 1.70158f.
def back_in(+u: F32, +b: F32, +c: F32) -> F32:
  (c * u * u * ((1.70158 + 1.0) * u - 1.70158) + b : F32)

# EaseBackOut: t = t/d - 1; c*(t*t*((s + 1)*t + s) + 1) + b.
def back_out(+u: F32, +b: F32, +c: F32) -> F32:
  (c * (u * u * ((1.70158 + 1.0) * u + 1.70158) + 1.0) + b : F32)

# EaseBackInOut: s *= 1.525f on either side of t/(d/2) = 1.
def back_in_out(+u: F32, +b: F32, +c: F32) -> F32:
  +s = (1.70158 * 1.525 : F32)
  Bool.pick(F32, (u < 1.0 : F32), (c / 2.0 * (u * u * ((s + 1.0) * u - s)) + b : F32), (c / 2.0 * ((u - 2.0) * (u - 2.0) * ((s + 1.0) * (u - 2.0) + s) + 2.0) + b : F32))

# EaseBounceOut's later arcs: postFix = t -= offset; c*(7.5625f*postFix*t + rise) + b.
def bounce.arc(+t: F32, +b: F32, +c: F32, +offset: F32, +rise: F32) -> F32:
  (c * (7.5625 * (t - offset) * (t - offset) + rise) + b : F32)

# EaseBounceOut(t, b, c, d). The example's third bound is the double 2.5/2.75; a float is below it exactly when it is
# below the float 2.5f/2.75f (the nearest float, which is above the double).
def bounce_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  +u = (t / d : F32)
  Bool.pick(F32, (u < (1.0 / 2.75) : F32), (c * (7.5625 * u * u) + b : F32),
    Bool.pick(F32, (u < (2.0 / 2.75) : F32), bounce.arc(u, b, c, (1.5 / 2.75 : F32), 0.75),
      Bool.pick(F32, (u < (2.5 / 2.75) : F32), bounce.arc(u, b, c, (2.25 / 2.75 : F32), 0.9375), bounce.arc(u, b, c, (2.625 / 2.75 : F32), 0.984375))))

# EaseBounceIn: c - EaseBounceOut(d - t, 0, c, d) + b.
def bounce_in(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (c - bounce_out((d - t : F32), 0.0, c, d) + b : F32)

# EaseBounceInOut: the first half through EaseBounceIn(t*2), the second through EaseBounceOut(t*2 - d).
def bounce_in_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  Bool.pick(F32, (t < (d / 2.0) : F32), (bounce_in((t * 2.0 : F32), 0.0, c, d) * 0.5 + b : F32), (bounce_out((t * 2.0 - d : F32), 0.0, c, d) * 0.5 + c * 0.5 + b : F32))

# postFix*sin for the elastic easings, postFix being a*powf(2, exponent); kind 0: -(wave) + b (in), 1: wave + c + b (out),
# 2: -0.5f*wave + b (in out, first half), 3: wave*0.5f + c + b (second half).
def elastic.value(kind: U32, +b: F32, +c: F32, +wave: F32) -> F32:
  match kind:
    case 0: (F32.neg(wave) + b : F32)
    case 1: (wave + c + b : F32)
    case 2: (F32.neg(0.5) * wave + b : F32)
    case _: (wave * 0.5 + c + b : F32)

def elastic.at(+kind: U32, +b: F32, +c: F32, power: Maybe<F32>, sine: Maybe<F32>) -> Maybe<F32>:
  match power sine:
    case Some{+p} Some{+s}: Some{elastic.value(kind, b, c, (c * p * s : F32))}
    case _ _: None{}

# The wave sinf((t*d - s)*(2*PI)/p) with s = p/4 under the power's exponent.
def elastic(+kind: U32, +libm: M.Libm, +exponent: F32, +t: F32, +b: F32, +c: F32, +d: F32, +p: F32) -> Maybe<F32>:
  elastic.at(kind, b, c, M.Libm.pow2(libm, exponent), M.Libm.sin(libm, ((t * d - p / 4.0) * (2.0 * M.Math.PI()) / p : F32)))

# EaseElasticIn: b at t == 0, b + c where t/d == 1; p = d*0.3f.
def elastic_in(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, F32.is_eq(t, 0.0), Some{b}, Bool.pick(Maybe<F32>, F32.is_eq((t / d : F32), 1.0), Some{(b + c : F32)},
    elastic(0, libm, (10.0 * (t / d - 1.0) : F32), (t / d - 1.0 : F32), b, c, d, (d * 0.3 : F32))))

# EaseElasticOut.
def elastic_out(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, F32.is_eq(t, 0.0), Some{b}, Bool.pick(Maybe<F32>, F32.is_eq((t / d : F32), 1.0), Some{(b + c : F32)},
    elastic(1, libm, (F32.neg(10.0) * (t / d) : F32), (t / d : F32), b, c, d, (d * 0.3 : F32))))

# EaseElasticInOut: b at t == 0, b + c where t/(d/2) == 2; p = d*(0.3f*1.5f); by t/(d/2) below 1 or not.
def elastic_in_out(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  +u = (t / (d / 2.0) : F32)
  +p = (d * (0.3 * 1.5) : F32)
  Bool.pick(Maybe<F32>, F32.is_eq(t, 0.0), Some{b}, Bool.pick(Maybe<F32>, F32.is_eq(u, 2.0), Some{(b + c : F32)},
    Bool.pick(Maybe<F32>, (u < 1.0 : F32), elastic(2, libm, (10.0 * (u - 1.0) : F32), (u - 1.0 : F32), b, c, d, p), elastic(3, libm, (F32.neg(10.0) * (u - 1.0) : F32), (u - 1.0 : F32), b, c, d, p))))

# easings[kind].func(t, b, c, d).
def ease(kind: U32, +libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  match kind:
    case 0: Some{(c * t / d + b : F32)}
    case 1: Some{(c * t / d + b : F32)}
    case 2: Some{(c * t / d + b : F32)}
    case 3: Some{(c * t / d + b : F32)}
    case 4: sine_in.at(b, c, M.Libm.cos(libm, (t / d * (M.Math.PI() / 2.0) : F32)))
    case 5: scaled(b, c, M.Libm.sin(libm, (t / d * (M.Math.PI() / 2.0) : F32)))
    case 6: sine_in_out.at(b, c, M.Libm.cos(libm, (M.Math.PI() * t / d : F32)))
    case 7: Some{(F32.neg(c) * (F32.sqrt((1.0 - (t / d) * (t / d) : F32)) - 1.0) + b : F32)}
    case 8: Some{(c * F32.sqrt((1.0 - (t / d - 1.0) * (t / d - 1.0) : F32)) + b : F32)}
    case 9: Some{circ_in_out((t / (d / 2.0) : F32), b, c)}
    case 10: Some{(c * (t / d) * (t / d) * (t / d) + b : F32)}
    case 11: Some{(c * ((t / d - 1.0) * (t / d - 1.0) * (t / d - 1.0) + 1.0) + b : F32)}
    case 12: Some{cubic_in_out((t / (d / 2.0) : F32), b, c)}
    case 13: Some{(c * (t / d) * (t / d) + b : F32)}
    case 14: Some{(F32.neg(c) * (t / d) * ((t / d) - 2.0) + b : F32)}
    case 15: Some{quad_in_out((t / (d / 2.0) : F32), b, c)}
    case 16: Bool.pick(Maybe<F32>, F32.is_eq(t, 0.0), Some{b}, scaled(b, c, M.Libm.pow2(libm, (10.0 * (t / d - 1.0) : F32))))
    case 17: Bool.pick(Maybe<F32>, F32.is_eq(t, d), Some{(b + c : F32)}, expo_out.at(b, c, M.Libm.pow2(libm, (F32.neg(10.0) * t / d : F32))))
    case 18: expo_in_out(Bool.pick(U32, F32.is_eq(t, 0.0), 0, Bool.pick(U32, F32.is_eq(t, d), 1, 2)), libm, t, b, c, d)
    case 19: Some{back_in((t / d : F32), b, c)}
    case 20: Some{back_out((t / d - 1.0 : F32), b, c)}
    case 21: Some{back_in_out((t / (d / 2.0) : F32), b, c)}
    case 22: Some{bounce_out(t, b, c, d)}
    case 23: Some{bounce_in(t, b, c, d)}
    case 24: Some{bounce_in_out(t, b, c, d)}
    case 25: elastic_in(libm, t, b, c, d)
    case 26: elastic_out(libm, t, b, c, d)
    case 27: elastic_in_out(libm, t, b, c, d)
    case _: Some{b}

# easing++ past EASING_NONE (28) wraps to 0; easing-- below 0 wraps to EASING_NONE.
def chosen(+more: Bool, +less: Bool, +easing: U32) -> U32:
  Bool.pick(U32, more, Bool.pick(U32, (easing >= 28 : U32), 0, (easing + 1 : U32)), Bool.pick(U32, less, Bool.pick(U32, U32.is_eq(easing, 0), 28, (easing - 1 : U32)), easing))

def moved.at(+t: F32, +d: F32, +paused: Bool, +bounded: Bool, +ex: U32, +ey: U32, +ball: M.Vector2, +ok: Bool, x: Maybe<F32>, y: Maybe<F32>) -> State:
  match x y:
    case Some{+bx} Some{+by}: State{(t + 1.0 : F32), d, paused, bounded, ex, ey, M.Vector2{bx, by}, ok}
    case _ _: State{t, d, paused, bounded, ex, ey, ball, False{}}

# if (!paused && ((boundedT && t < d) || !boundedT)): the ball by both easings, t += 1.
def moved(moving: Bool, +libm: M.Libm, +t: F32, +d: F32, +paused: Bool, +bounded: Bool, +ex: U32, +ey: U32, +ball: M.Vector2, +ok: Bool) -> State:
  match moving:
    case False{}: State{t, d, paused, bounded, ex, ey, ball, ok}
    case True{}: moved.at(t, d, paused, bounded, ex, ey, ball, ok, ease(ex, libm, t, 100.0, (700.0 - 170.0 : F32), d), ease(ey, libm, t, 100.0, (400.0 - 170.0 : F32), d))

def pressed(+core: J.Core, +key: U32) -> Bool:
  J.Input.is_key_pressed(core, key)

# The duration: W/Q by 20 (pressed), S/A by 2 (held), inside (1, 10000).
def duration(+core: J.Core, +d: F32) -> F32:
  +coarse = Bool.pick(F32, pressed(core, J.KeyboardKey.KEY_W()) && (d < (10000.0 - 20.0) : F32), (d + 20.0 : F32),
    Bool.pick(F32, pressed(core, J.KeyboardKey.KEY_Q()) && (d > (1.0 + 20.0) : F32), (d - 20.0 : F32), d))
  Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_S()) && (coarse < (10000.0 - 2.0) : F32), (coarse + 2.0 : F32),
    Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_A()) && (coarse > (1.0 + 2.0) : F32), (coarse - 2.0 : F32), coarse))

# T toggles boundedT; the arrows choose the easings; any of the controls (or ENTER at the end of a bounded run) restarts and
# pauses; ENTER toggles the pause; then the movement.
def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+t, +d, +paused, +bounded, +x, +y, +ball, +ok} = state
  +limited = Bool.pick(Bool, pressed(core, J.KeyboardKey.KEY_T()), Bool.not(bounded), bounded)
  +ex = chosen(pressed(core, J.KeyboardKey.KEY_RIGHT()), pressed(core, J.KeyboardKey.KEY_LEFT()), x)
  +ey = chosen(pressed(core, J.KeyboardKey.KEY_DOWN()), pressed(core, J.KeyboardKey.KEY_UP()), y)
  +span = duration(core, d)
  +enter = pressed(core, J.KeyboardKey.KEY_ENTER())
  +restart = pressed(core, J.KeyboardKey.KEY_SPACE()) || pressed(core, J.KeyboardKey.KEY_T()) || pressed(core, J.KeyboardKey.KEY_RIGHT()) || pressed(core, J.KeyboardKey.KEY_LEFT()) ||
    pressed(core, J.KeyboardKey.KEY_DOWN()) || pressed(core, J.KeyboardKey.KEY_UP()) || pressed(core, J.KeyboardKey.KEY_W()) || pressed(core, J.KeyboardKey.KEY_Q()) ||
    J.Input.is_key_down(core, J.KeyboardKey.KEY_S()) || J.Input.is_key_down(core, J.KeyboardKey.KEY_A()) || (enter && limited && (t >= span : F32))
  +time = Bool.pick(F32, restart, 0.0, t)
  +still = Bool.pick(Bool, enter, Bool.not(paused || restart), paused || restart)
  (core, moved(Bool.not(still) && ((limited && (time < span : F32)) || Bool.not(limited)), libm, time, span, still, limited, ex, ey,
    Bool.pick(M.Vector2, restart, M.Vector2{100.0, 100.0}, ball), ok))

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def label(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 20.0, y, 20.0, J.Color.LIGHTGRAY())

def help(frame: J.Frame, text: String, +y: F32) -> J.Frame:
  J.Draw.text(frame, text, 20.0, y, 20.0, J.Color.LIGHTGRAY())

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+t, +d, _, +bounded, +x, +y, +ball, +ok} = state
  f1 = label(J.Text.format("Easing x: %s", [J.TextString{name(x)}]), 20.0, J.Frame.clear_background(checked(ok, frame), J.Color.RAYWHITE()))
  f2 = label(J.Text.format("t (%c) = %.2f d = %.2f", [J.TextInt{Bool.pick(U32, bounded, 98, 117)}, J.TextFloat{t}, J.TextFloat{d}]), (20.0 * 3.0 : F32),
    label(J.Text.format("Easing y: %s", [J.TextString{name(y)}]), (20.0 * 2.0 : F32), f1))
  f3 = help(help(f2, "Use ENTER to play or pause movement, use SPACE to restart", (450.0 - 20.0 * 2.0 : F32)), "Use Q and W or A and S keys to change duration", (450.0 - 20.0 * 3.0 : F32))
  f4 = help(help(f3, "Use LEFT or RIGHT keys to choose easing for the x axis", (450.0 - 20.0 * 4.0 : F32)), "Use UP or DOWN keys to choose easing for the y axis", (450.0 - 20.0 * 5.0 : F32))
  (core, (state, J.Draw.circle_v_for(libm, f4, ball, 16.0, J.Color.MAROON())))

# The main loop's body; libm is the profile of the easings' sinf, cosf and powf(2, x) and of DrawCircleV's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): the ball at (100, 100), t = 0, d = 300, paused, bounded, no easing on either axis, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{0.0, 300.0, True{}, True{}, 28, 28, M.Vector2{100.0, 100.0}, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - easings testbed", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
