# raylib [core] example - input gestures, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_input_gestures.c (zlib/libpng,
# Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Each new gesture detected inside the test area is logged by name (twenty
# at most, then the log restarts) and a circle follows touch point 0 while a
# gesture is active. A detected value that is none of the ten gestures would
# show a string the example never wrote; that frame is refused. DrawCircleV's
# sinf/cosf follow the libm profile (whole degrees only). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{valid: Bool, current: U32, touch: M.Vector2, count: U32, strings: +List<String>}

# touchArea = (220, 10, screenWidth - 230, screenHeight - 20).
def area() -> J.Rectangle:
  J.Rectangle{220.0, 10.0, (800.0 - 230.0 : F32), (450.0 - 20.0 : F32)}

def name(gesture: U32) -> String:
  match gesture:
    case 1: "GESTURE TAP"
    case 2: "GESTURE DOUBLETAP"
    case 4: "GESTURE HOLD"
    case 8: "GESTURE DRAG"
    case 16: "GESTURE SWIPE RIGHT"
    case 32: "GESTURE SWIPE LEFT"
    case 64: "GESTURE SWIPE UP"
    case 128: "GESTURE SWIPE DOWN"
    case 256: "GESTURE PINCH IN"
    case 512: "GESTURE PINCH OUT"
    case _: ""

def known(gesture: U32) -> Bool:
  match gesture:
    case 1: True{}
    case 2: True{}
    case 4: True{}
    case 8: True{}
    case 16: True{}
    case 32: True{}
    case 64: True{}
    case 128: True{}
    case 256: True{}
    case 512: True{}
    case _: False{}

# A gesture other than the last one, inside the area, is logged; the
# twentieth clears the log.
def update.at(+last: U32, +current: U32, +count: U32, +strings: +List<String>, +touch: M.Vector2) -> State:
  +fresh = J.Collision.point_rec(touch, area()) && Bool.not(U32.is_eq(current, 0)) && Bool.not(U32.is_eq(current, last))
  +next = (count + 1 : U32)
  +full = (next >= 20 : U32)
  State{Bool.not(fresh) || known(current), current, touch, Bool.pick(U32, fresh, Bool.pick(U32, full, 0, next), count),
    Bool.pick(+List<String>, fresh, Bool.pick(+List<String>, full, Nil{}, List.append(&2, String, strings, [name(current)])), strings)}

def update.touch(+last: U32, +current: U32, +count: U32, +strings: +List<String>, touch: Maybe<M.Vector2>) -> State:
  match touch:
    case None{}: State{False{}, current, M.Vector2.zero(), count, strings}
    case Some{+t}: update.at(last, current, count, strings, t)

# lastGesture = currentGesture; currentGesture = GetGestureDetected(); touchPosition = GetTouchPosition(0).
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{_, +last, _, +count, +strings} = state
  (core, update.touch(last, J.Gestures.get_detected(core), count, strings, J.Input.get_touch_position(core, 0)))

# A striped row a gesture, the newest in MAROON.
def rows(strings: +List<String>, +i: U32, +count: U32, frame: J.Frame) -> J.Frame:
  match strings:
    case Nil{}: frame
    case Con{+text, rest}:
      +y = U32.to_f32((20 * i : U32))
      f1 = J.Draw.rectangle(frame, 10.0, (30.0 + y : F32), 200.0, 20.0, J.Color.with_alpha(J.Color.LIGHTGRAY(), Bool.pick(F32, U32.is_eq((i % 2 : U32), 0), 0.5, 0.3)))
      rows(rest, (i + 1 : U32), count, J.Draw.text(f1, text, 35.0, (36.0 + y : F32), 10.0, Bool.pick(U32, ((i + 1) < count : U32), J.Color.DARKGRAY(), J.Color.MAROON())))

# if (currentGesture != GESTURE_NONE) DrawCircleV(touchPosition, 30, MAROON).
def touched(none: Bool, +libm: M.Libm, +touch: M.Vector2, frame: J.Frame) -> J.Frame:
  match none:
    case True{}: frame
    case False{}: J.Draw.circle_v_for(libm, frame, touch, 30.0, J.Color.MAROON())

def draw.valid(valid: Bool, +libm: M.Libm, +state: State, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}:
      State{_, +current, +touch, +count, +strings} = state
      f1 = J.Draw.rectangle_rec(J.Frame.clear_background(frame, J.Color.RAYWHITE()), area(), J.Color.GRAY())
      f2 = J.Draw.rectangle(f1, 225.0, 15.0, (800.0 - 240.0 : F32), (450.0 - 30.0 : F32), J.Color.RAYWHITE())
      f3 = J.Draw.text(f2, "GESTURES TEST AREA", (800.0 - 270.0 : F32), (450.0 - 40.0 : F32), 20.0, J.Color.with_alpha(J.Color.GRAY(), 0.5))
      f4 = J.Draw.rectangle_lines(rows(strings, 0, count, f3), 10.0, 29.0, 200.0, (450.0 - 50.0 : F32), J.Color.GRAY())
      touched(U32.is_eq(current, 0), libm, touch, J.Draw.text(f4, "DETECTED GESTURES", 50.0, 15.0, 10.0, J.Color.GRAY()))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, _} = state
  (core, (state, draw.valid(valid, libm, state, frame)))

# The main loop's body; libm is the profile of DrawCircleV's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): no gesture, an empty log, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{True{}, 0, M.Vector2.zero(), 0, Nil{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - input gestures", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
