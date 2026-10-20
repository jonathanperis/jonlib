# raylib [shapes] example - easings testbed, ported to Jonlib.
# Adapted from raylib 6.2 examples/shapes/shapes_easings_testbed.c
# (zlib/libpng, Copyright (c) 2019-2025 Juan Miguel López (@flashback-fx) and
# Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt. The 28 easings are
# Joneasings' (docs/EASINGS.md).
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
import ../joneasings.bend as E

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

# easings[kind].func(t, b, c, d).
def ease(kind: U32, +libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  match kind:
    case 0: Some{E.Ease.linear_none(t, b, c, d)}
    case 1: Some{E.Ease.linear_in(t, b, c, d)}
    case 2: Some{E.Ease.linear_out(t, b, c, d)}
    case 3: Some{E.Ease.linear_in_out(t, b, c, d)}
    case 4: E.Ease.sine_in_for(libm, t, b, c, d)
    case 5: E.Ease.sine_out_for(libm, t, b, c, d)
    case 6: E.Ease.sine_in_out_for(libm, t, b, c, d)
    case 7: Some{E.Ease.circ_in(t, b, c, d)}
    case 8: Some{E.Ease.circ_out(t, b, c, d)}
    case 9: Some{E.Ease.circ_in_out(t, b, c, d)}
    case 10: Some{E.Ease.cubic_in(t, b, c, d)}
    case 11: Some{E.Ease.cubic_out(t, b, c, d)}
    case 12: Some{E.Ease.cubic_in_out(t, b, c, d)}
    case 13: Some{E.Ease.quad_in(t, b, c, d)}
    case 14: Some{E.Ease.quad_out(t, b, c, d)}
    case 15: Some{E.Ease.quad_in_out(t, b, c, d)}
    case 16: E.Ease.expo_in_for(libm, t, b, c, d)
    case 17: E.Ease.expo_out_for(libm, t, b, c, d)
    case 18: E.Ease.expo_in_out_for(libm, t, b, c, d)
    case 19: Some{E.Ease.back_in(t, b, c, d)}
    case 20: Some{E.Ease.back_out(t, b, c, d)}
    case 21: Some{E.Ease.back_in_out(t, b, c, d)}
    case 22: Some{E.Ease.bounce_out(t, b, c, d)}
    case 23: Some{E.Ease.bounce_in(t, b, c, d)}
    case 24: Some{E.Ease.bounce_in_out(t, b, c, d)}
    case 25: E.Ease.elastic_in_for(libm, t, b, c, d)
    case 26: E.Ease.elastic_out_for(libm, t, b, c, d)
    case 27: E.Ease.elastic_in_out_for(libm, t, b, c, d)
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
