# raylib [core] example - input gestures testbed, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_input_gestures_testbed.c (zlib/libpng,
# Copyright (c) 2023-2025 ubkp (@ubkp)); see LICENSES/raylib.txt.
#
# The last gesture shown on a pad of swipes, taps, pinches and touch points,
# a log of the gestures (two buttons hide the repeated ones and the holds),
# a protractor for the drag or pinch angle, and the touch or mouse points.
# The example starts its log index at GESTURE_LOG_SIZE and draws
# gestureLog[index] first: until a gesture is logged that is a read past
# the array (undefined in C), so those frames are refused. The circles'
# and the protractor line's sinf/cosf follow the libm profile
# (docs/SINCOSF.md). See docs/INPUT.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# lastGesture, gestureLog (20 strings), gestureLogIndex, previousGesture, logMode, gestureColor, currentAngleDegrees.
type State is Data:
  State{last: U32, log: +List<String>, index: U32, previous: U32, mode: U32, color: U32, angle: F32}

# GetGestureName.
def name(gesture: U32) -> String:
  match gesture:
    case 0: "None"
    case 1: "Tap"
    case 2: "Double Tap"
    case 4: "Hold"
    case 8: "Drag"
    case 16: "Swipe Right"
    case 32: "Swipe Left"
    case 64: "Swipe Up"
    case 128: "Swipe Down"
    case 256: "Pinch In"
    case 512: "Pinch Out"
    case _: "Unknown"

# GetGestureColor.
def tone(gesture: U32) -> U32:
  match gesture:
    case 1: J.Color.BLUE()
    case 2: J.Color.SKYBLUE()
    case 8: J.Color.LIME()
    case 16: J.Color.RED()
    case 32: J.Color.RED()
    case 64: J.Color.RED()
    case 128: J.Color.RED()
    case 256: J.Color.VIOLET()
    case 512: J.Color.ORANGE()
    case _: J.Color.BLACK()

# The "Hide Repeat" button.
def repeat(mode: U32) -> U32:
  match mode:
    case 3: 2
    case 2: 3
    case 1: 0
    case _: 1

# The "Hide Hold" button.
def hold(mode: U32) -> U32:
  match mode:
    case 3: 1
    case 2: 0
    case 1: 3
    case _: 2

def put(strings: +List<String>, index: Nat, +text: String) -> +List<String>:
  match strings index:
    case Nil{} _: Nil{}
    case Con{_, rest} 0n: Con{text, rest}
    case Con{+first, rest} 1n+p: Con{first, put(rest, p, text)}

def head(strings: +List<String>) -> String:
  match strings:
    case Nil{}: ""
    case Con{+text, _}: text

# fillLog: by logMode, 3 hides repeated events and holds, 2 the holds, 1 the repeated events, 0 nothing.
def fills(mode: U32, +current: U32, +previous: U32) -> Bool:
  match mode:
    case 3: (Bool.not(U32.is_eq(current, 4)) && Bool.not(U32.is_eq(current, previous))) || (current < 3 : U32)
    case 2: Bool.not(U32.is_eq(current, 4))
    case 1: Bool.not(U32.is_eq(current, previous))
    case _: True{}

def update.at(+core: J.Core, +state: State, +current: U32, +mouse: M.Vector2) -> State:
  State{+last, +log, +index, +previous, +mode, +color, +angle} = state
  +released = J.Input.is_mouse_button_released(core, J.MouseButton.MOUSE_BUTTON_LEFT())
  +first = released && J.Collision.point_rec(mouse, J.Rectangle{53.0, 7.0, 48.0, 26.0})
  +second = released && Bool.not(first) && J.Collision.point_rec(mouse, J.Rectangle{108.0, 7.0, 36.0, 26.0})
  +next = Bool.pick(U32, first, repeat(mode), Bool.pick(U32, second, hold(mode), mode))
  +fill = Bool.not(U32.is_eq(current, 0)) && fills(next, current, previous)
  +slot = (Bool.pick(U32, U32.is_eq(index, 0), 20, index) - 1 : U32)
  State{Bool.pick(U32, Bool.not(U32.is_eq(current, 0)) && Bool.not(U32.is_eq(current, 4)) && Bool.not(U32.is_eq(current, previous)), current, last),
    Bool.pick(+List<String>, fill, put(log, U32.to_nat(slot), name(current)), log), Bool.pick(U32, fill, slot, index), Bool.pick(U32, fill, current, previous), next,
    Bool.pick(U32, fill, tone(current), color),
    Bool.pick(F32, (current > 255 : U32), J.Gestures.get_pinch_angle(core), Bool.pick(F32, (current > 15 : U32), J.Gestures.get_drag_angle(core), Bool.pick(F32, (current > 0 : U32), 0.0, angle)))}

# The last gesture, the log buttons and the log, then the protractor's angle (pinch, drag, or 0 for the others).
def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, update.at(core, state, J.Gestures.get_detected(core), J.Input.get_mouse_position(core)))

def lit(+on: Bool, +color: U32) -> U32:
  Bool.pick(U32, on, color, J.Color.LIGHTGRAY())

# The pad: the swipes' squares, the tap and drag, the double tap, the pinches' triangles.
def pad(+libm: M.Libm, +last: U32, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.text(J.Draw.text(frame, "Last gesture", (165.0 + 33.0 : F32), (130.0 - 47.0 : F32), 20.0, J.Color.BLACK()), "Swipe         Tap       Pinch  Touch", (165.0 + 17.0 : F32),
    (130.0 - 18.0 : F32), 10.0, J.Color.BLACK())
  f2 = J.Draw.rectangle(J.Draw.rectangle(f1, (165.0 + 20.0 : F32), 130.0, 20.0, 20.0, lit(U32.is_eq(last, 64), J.Color.RED())), 165.0, (130.0 + 20.0 : F32), 20.0, 20.0,
    lit(U32.is_eq(last, 32), J.Color.RED()))
  f3 = J.Draw.rectangle(J.Draw.rectangle(f2, (165.0 + 40.0 : F32), (130.0 + 20.0 : F32), 20.0, 20.0, lit(U32.is_eq(last, 16), J.Color.RED())), (165.0 + 20.0 : F32), (130.0 + 40.0 : F32),
    20.0, 20.0, lit(U32.is_eq(last, 128), J.Color.RED()))
  f4 = J.Draw.ring_for(libm, J.Draw.circle_for(libm, f3, (165.0 + 80.0 : F32), (130.0 + 16.0 : F32), 10.0, lit(U32.is_eq(last, 1), J.Color.BLUE())),
    M.Vector2{(165.0 + 103.0 : F32), (130.0 + 16.0 : F32)}, 6.0, 11.0, 0.0, 360.0, 0.0, lit(U32.is_eq(last, 8), J.Color.LIME()))
  f5 = J.Draw.circle_for(libm, J.Draw.circle_for(libm, f4, (165.0 + 80.0 : F32), (130.0 + 43.0 : F32), 10.0, lit(U32.is_eq(last, 2), J.Color.SKYBLUE())),
    (165.0 + 103.0 : F32), (130.0 + 43.0 : F32), 10.0, lit(U32.is_eq(last, 2), J.Color.SKYBLUE()))
  f6 = J.Draw.triangle(f5, M.Vector2{(165.0 + 122.0 : F32), (130.0 + 16.0 : F32)}, M.Vector2{(165.0 + 137.0 : F32), (130.0 + 26.0 : F32)}, M.Vector2{(165.0 + 137.0 : F32), (130.0 + 6.0 : F32)},
    lit(U32.is_eq(last, 512), J.Color.ORANGE()))
  f7 = J.Draw.triangle(f6, M.Vector2{(165.0 + 147.0 : F32), (130.0 + 6.0 : F32)}, M.Vector2{(165.0 + 147.0 : F32), (130.0 + 26.0 : F32)}, M.Vector2{(165.0 + 162.0 : F32), (130.0 + 16.0 : F32)},
    lit(U32.is_eq(last, 512), J.Color.ORANGE()))
  f8 = J.Draw.triangle(f7, M.Vector2{(165.0 + 125.0 : F32), (130.0 + 33.0 : F32)}, M.Vector2{(165.0 + 125.0 : F32), (130.0 + 53.0 : F32)}, M.Vector2{(165.0 + 140.0 : F32), (130.0 + 43.0 : F32)},
    lit(U32.is_eq(last, 256), J.Color.VIOLET()))
  J.Draw.triangle(f8, M.Vector2{(165.0 + 144.0 : F32), (130.0 + 43.0 : F32)}, M.Vector2{(165.0 + 159.0 : F32), (130.0 + 53.0 : F32)}, M.Vector2{(165.0 + 159.0 : F32), (130.0 + 33.0 : F32)},
    lit(U32.is_eq(last, 256), J.Color.VIOLET()))

# for (i = 0; i < 4; i++) DrawCircle(x + 180, y + 7 + i*15, 5, touchCount <= i? LIGHTGRAY : gestureColor).
def dots(n: Nat, +i: U32, +libm: M.Libm, +touches: U32, +color: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: dots(p, (i + 1 : U32), libm, touches, color, J.Draw.circle_for(libm, frame, (165.0 + 180.0 : F32), U32.to_f32((130 + 7 + i * 15 : U32)), 5.0, lit((touches > i : U32), color)))

# The log from gestureLogIndex around the array, the newest at the bottom in gestureColor.
def rows(n: Nat, +i: U32, +index: U32, +log: +List<String>, +color: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: rows(p, (i + 1 : U32), index, log, color, J.Draw.text(frame, head(List.drop(&2, String, log, U32.to_nat(((index + i) % 20 : U32)))), 10.0,
      U32.to_f32((10 + 410 - i * 20 : U32)), 20.0, Bool.pick(U32, U32.is_eq(i, 0), color, J.Color.LIGHTGRAY())))

def shade(+maroon: Bool) -> U32:
  Bool.pick(U32, maroon, J.Color.MAROON(), J.Color.GRAY())

# The log buttons: MAROON while they hide (mode 1 or 3 the repeated events, 2 or 3 the holds).
def buttons(+mode: U32, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.rectangle_rec(frame, J.Rectangle{53.0, 7.0, 48.0, 26.0}, shade(U32.is_eq(mode, 3) || U32.is_eq(mode, 1)))
  f2 = J.Draw.text(J.Draw.text(f1, "Hide", (53.0 + 7.0 : F32), (7.0 + 3.0 : F32), 10.0, J.Color.WHITE()), "Repeat", (53.0 + 7.0 : F32), (7.0 + 13.0 : F32), 10.0, J.Color.WHITE())
  f3 = J.Draw.rectangle_rec(f2, J.Rectangle{108.0, 7.0, 36.0, 26.0}, shade(U32.is_eq(mode, 3) || U32.is_eq(mode, 2)))
  J.Draw.text(J.Draw.text(f3, "Hide", (53.0 + 62.0 : F32), (7.0 + 3.0 : F32), 10.0, J.Color.WHITE()), "Hold", (53.0 + 62.0 : F32), (7.0 + 13.0 : F32), 10.0, J.Color.WHITE())

def trimmed.at(+text: String, dot: Maybe<U32>) -> Maybe<String>:
  match dot:
    case None{}: None{}
    case Some{+d}: J.Text.subtext(text, 0, (d + 3 : U32))

def trimmed.text(text: Maybe<String>) -> Maybe<String>:
  match text:
    case None{}: None{}
    case Some{+t}: trimmed.at(t, J.Text.find_index(t, "."))

# TextSubtext(angleString, 0, TextFindIndex(angleString, ".") + 3) of TextFormat("%f", currentAngleDegrees).
def trimmed(+angle: F32) -> Maybe<String>:
  trimmed.text(J.Text.format("%f", [J.TextFloat{angle}]))

def angle.text(text: Maybe<String>, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, (266.0 + 55.0 : F32), (315.0 + 92.0 : F32), 20.0, color)

def hand.at(+color: U32, frame: J.Frame, sine: Maybe<F32>, cosine: Maybe<F32>) -> J.Frame:
  match sine cosine:
    case Some{+s} Some{+c}: J.Draw.line_ex(frame, M.Vector2{266.0, 315.0}, M.Vector2{(90.0 * s + 266.0 : F32), (90.0 * c + 315.0 : F32)}, 3.0, color)
    case _ _: J.Frame.refuse(frame)

# if (currentAngleDegrees != 0.0f) DrawLineEx(protractorPosition, finalVector, 3.0f, gestureColor), finalVector at
# angleLength (90) along ((currentAngleDegrees + 90.0f)*PI/180).
def hand(still: Bool, +libm: M.Libm, +angle: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match still:
    case True{}: frame
    case False{}: hand.at(color, frame, M.Libm.sin(libm, ((angle + 90.0) * M.Math.PI() / 180.0 : F32)), M.Libm.cos(libm, ((angle + 90.0) * M.Math.PI() / 180.0 : F32)))

def mark(frame: J.Frame, text: String, +x: F32, +y: F32) -> J.Frame:
  J.Draw.text(frame, text, x, y, 20.0, J.Color.BLACK())

def protractor(+libm: M.Libm, +angle: F32, +color: U32, frame: J.Frame) -> J.Frame:
  f1 = angle.text(trimmed(angle), color, J.Draw.text(frame, "Angle", (266.0 + 55.0 : F32), (315.0 + 76.0 : F32), 10.0, J.Color.BLACK()))
  f2 = J.Draw.line_ex(J.Draw.circle_v_for(libm, f1, M.Vector2{266.0, 315.0}, 80.0, J.Color.WHITE()), M.Vector2{(266.0 - 90.0 : F32), 315.0}, M.Vector2{(266.0 + 90.0 : F32), 315.0}, 3.0,
    J.Color.LIGHTGRAY())
  f3 = J.Draw.line_ex(f2, M.Vector2{266.0, (315.0 - 90.0 : F32)}, M.Vector2{266.0, (315.0 + 90.0 : F32)}, 3.0, J.Color.LIGHTGRAY())
  f4 = J.Draw.line_ex(f3, M.Vector2{(266.0 - 80.0 : F32), (315.0 - 45.0 : F32)}, M.Vector2{(266.0 + 80.0 : F32), (315.0 + 45.0 : F32)}, 3.0, J.Color.GREEN())
  f5 = J.Draw.line_ex(f4, M.Vector2{(266.0 - 80.0 : F32), (315.0 + 45.0 : F32)}, M.Vector2{(266.0 + 80.0 : F32), (315.0 - 45.0 : F32)}, 3.0, J.Color.GREEN())
  f6 = mark(mark(mark(mark(f5, "0", (266.0 + 96.0 : F32), (315.0 - 9.0 : F32)), "30", (266.0 + 74.0 : F32), (315.0 - 68.0 : F32)), "90", (266.0 - 11.0 : F32), (315.0 - 110.0 : F32)), "150",
    (266.0 - 100.0 : F32), (315.0 - 68.0 : F32))
  f7 = mark(mark(mark(mark(f6, "180", (266.0 - 124.0 : F32), (315.0 - 9.0 : F32)), "210", (266.0 - 100.0 : F32), (315.0 + 50.0 : F32)), "270", (266.0 - 18.0 : F32), (315.0 + 92.0 : F32)), "330",
    (266.0 + 72.0 : F32), (315.0 + 50.0 : F32))
  hand(F32.is_eq(angle, 0.0), libm, angle, color, f7)

def touch(+libm: M.Libm, +color: U32, position: Maybe<M.Vector2>, frame: J.Frame) -> J.Frame:
  match position:
    case None{}: J.Frame.refuse(frame)
    case Some{+p}: J.Draw.circle_v_for(libm, J.Draw.circle_v_for(libm, frame, p, 50.0, J.Color.with_alpha(color, 0.5)), p, 5.0, color)

def touches(n: Nat, +i: U32, +libm: M.Libm, +core: J.Core, +color: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: touches(p, (i + 1 : U32), libm, core, color, touch(libm, color, J.Input.get_touch_position(core, i), frame))

def joined.at(+thick: F32, +color: U32, frame: J.Frame, first: Maybe<M.Vector2>, second: Maybe<M.Vector2>) -> J.Frame:
  match first second:
    case Some{+a} Some{+b}: J.Draw.line_ex(frame, a, b, thick, color)
    case _ _: J.Frame.refuse(frame)

# if (touchCount == 2) DrawLineEx(touchPosition[0], touchPosition[1], (currentGesture == 512)? 8.0f : 12.0f, gestureColor).
def joined(two: Bool, +core: J.Core, +current: U32, +color: U32, frame: J.Frame) -> J.Frame:
  match two:
    case False{}: frame
    case True{}: joined.at(Bool.pick(F32, U32.is_eq(current, 512), 8.0, 12.0), color, frame, J.Input.get_touch_position(core, 0), J.Input.get_touch_position(core, 1))

# The touch points, or without any the mouse pointer.
def points.at(touched: Bool, +libm: M.Libm, +core: J.Core, +current: U32, +count: U32, +color: U32, frame: J.Frame) -> J.Frame:
  match touched:
    case True{}: joined(U32.is_eq(count, 2), core, current, color, touches(U32.to_nat(count), 0, libm, core, color, frame))
    case False{}: J.Draw.circle_v_for(libm, J.Draw.circle_v_for(libm, frame, J.Input.get_mouse_position(core), 35.0, J.Color.with_alpha(color, 0.5)), J.Input.get_mouse_position(core), 5.0, color)

# if (currentGesture != GESTURE_NONE): the pointers.
def points(none: Bool, +libm: M.Libm, +core: J.Core, +current: U32, +count: U32, +color: U32, frame: J.Frame) -> J.Frame:
  match none:
    case True{}: frame
    case False{}: points.at(Bool.not(U32.is_eq(count, 0)), libm, core, current, count, color, frame)

# gestureLog[gestureLogIndex] with the index still GESTURE_LOG_SIZE is past the array.
def defined(unlogged: Bool, frame: J.Frame) -> J.Frame:
  match unlogged:
    case False{}: frame
    case True{}: J.Frame.refuse(frame)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+last, +log, +index, _, +mode, +color, +angle} = state
  +current = J.Gestures.get_detected(core)
  +count = J.Input.get_touch_point_count(core)
  f1 = J.Draw.text(J.Frame.clear_background(defined(U32.is_eq(index, 20), frame), J.Color.RAYWHITE()), "*", (160.0 + 5.0 : F32), (7.0 + 5.0 : F32), 10.0, J.Color.BLACK())
  f2 = J.Draw.text(f1, "Example optimized for Web/HTML5\non Smartphones with Touch Screen.", (160.0 + 15.0 : F32), (7.0 + 5.0 : F32), 10.0, J.Color.BLACK())
  f3 = J.Draw.text(J.Draw.text(f2, "*", (160.0 + 5.0 : F32), (7.0 + 35.0 : F32), 10.0, J.Color.BLACK()), "While running on Desktop Web Browsers,\ninspect and turn on Touch Emulation.",
    (160.0 + 15.0 : F32), (7.0 + 35.0 : F32), 10.0, J.Color.BLACK())
  f4 = J.Draw.text(dots(4n, 0, libm, count, color, pad(libm, last, f3)), "Log", 10.0, 10.0, 20.0, J.Color.BLACK())
  f5 = protractor(libm, angle, color, buttons(mode, rows(20n, 0, index, log, color, f4)))
  (core, (state, points(U32.is_eq(current, 0), libm, core, current, count, color, f5)))

# The main loop's body; libm is the profile of the circles' and the protractor line's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def blank(n: Nat) -> +List<String>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{"", blank(p)}

# After InitWindow(800, 450): an empty log with its index at GESTURE_LOG_SIZE, logMode 1, a black gesture color; SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{0, blank(20n), 20, 0, 1, J.Color.rgba(0, 0, 0, 255), 0.0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - input gestures testbed", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
