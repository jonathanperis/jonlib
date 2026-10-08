# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rcore.c (zlib, LICENSES/raylib.txt) as
# pinned raylib runs it on PLATFORM=Memory: the CORE state an application
# observes between frames (window close and screenshot requests, input,
# gestures, frame timing and the frame counter, GetFPS's averaging state,
# automation event recording) as one explicit value, with GetTime() replaced
# by explicit binary64 clock arguments. See docs/INPUT.md.
import Base
import ./binary64_fma.bend as W
import ./clock.bend as Clock
import ./input.bend as In
import ./gestures.bend as G
import ./automation.bend as A

# CORE.Time (seconds as binary64 words) and the frame counter.
type Time is Data:
  Time{current: W.Words, previous: W.Words, update: W.Words, draw: W.Words, frame: W.Words, target: W.Words, counter: U32}

# GetFPS's static state: index, 30-entry history, average and last time.
type Fps is Data:
  Fps{index: U32, history: +List<F32>, average: F32, last: F32}

# The screen size, CORE.Window.shouldClose and the screenshot counter.
type Screen is Data:
  Screen{width: U32, height: U32, should_close: Bool, screenshots: U32}

type Core is Data:
  Core{window: Screen, input: In.Input, gestures: G.Gestures, time: Time, fps: Fps, recording: Bool, list: Maybe<&2, A.AutoList>}

def Fps.new() -> Fps:
  Fps{0, List.replicate(F32, 30n, 0.0), 0.0, 0.0}

# InitWindow(width, height) at time now (InitTimer sets CORE.Time.previous).
def Core.new(+width: U32, +height: U32, +now: W.Words) -> Core:
  Core{Screen{width, height, False{}, 0}, In.Input.new(), G.Gestures.new(),
    Time{Clock.zero(), now, Clock.zero(), Clock.zero(), Clock.zero(), Clock.zero(), 0}, Fps.new(), False{}, None{}}

def Core.window(+core: Core) -> Screen:
  Core{window, _, _, _, _, _, _} = core
  window

def Core.input(+core: Core) -> In.Input:
  Core{_, input, _, _, _, _, _} = core
  input

def Core.gestures(+core: Core) -> G.Gestures:
  Core{_, _, gestures, _, _, _, _} = core
  gestures

def Core.time(+core: Core) -> Time:
  Core{_, _, _, time, _, _, _} = core
  time

def Core.recording(+core: Core) -> Bool:
  Core{_, _, _, _, _, recording, _} = core
  recording

def Core.list(+core: Core) -> Maybe<&2, A.AutoList>:
  Core{_, _, _, _, _, _, list} = core
  list

def Core.with_window(core: Core, window: Screen) -> Core:
  Core{_, input, gestures, time, fps, recording, list} = core
  Core{window, input, gestures, time, fps, recording, list}

def Core.with_input(core: Core, input: In.Input) -> Core:
  Core{window, _, gestures, time, fps, recording, list} = core
  Core{window, input, gestures, time, fps, recording, list}

def Core.with_gestures(core: Core, gestures: G.Gestures) -> Core:
  Core{window, input, _, time, fps, recording, list} = core
  Core{window, input, gestures, time, fps, recording, list}

def Core.with_time(core: Core, time: Time) -> Core:
  Core{window, input, gestures, _, fps, recording, list} = core
  Core{window, input, gestures, time, fps, recording, list}

def Core.with_fps(core: Core, fps: Fps) -> Core:
  Core{window, input, gestures, time, _, recording, list} = core
  Core{window, input, gestures, time, fps, recording, list}

def Core.with_recording(core: Core, recording: Bool) -> Core:
  Core{window, input, gestures, time, fps, _, list} = core
  Core{window, input, gestures, time, fps, recording, list}

def Core.with_list(core: Core, list: Maybe<&2, A.AutoList>) -> Core:
  Core{window, input, gestures, time, fps, recording, _} = core
  Core{window, input, gestures, time, fps, recording, list}

def Screen.should_close(+w: Screen) -> Bool:
  Screen{_, _, close, _} = w
  close

def Screen.width(+w: Screen) -> U32:
  Screen{width, _, _, _} = w
  width

def Screen.height(+w: Screen) -> U32:
  Screen{_, height, _, _} = w
  height

def Screen.screenshots(+w: Screen) -> U32:
  Screen{_, _, _, shots} = w
  shots

def Screen.close(w: Screen) -> Screen:
  Screen{width, height, _, shots} = w
  Screen{width, height, True{}, shots}

def Screen.screenshot(w: Screen) -> Screen:
  Screen{width, height, close, +shots} = w
  Screen{width, height, close, (shots + 1 : U32)}

def Time.counter(+t: Time) -> U32:
  Time{_, _, _, _, _, _, counter} = t
  counter

def Time.frame(+t: Time) -> W.Words:
  Time{_, _, _, _, frame, _, _} = t
  frame

def Time.target(+t: Time) -> W.Words:
  Time{_, _, _, _, _, target, _} = t
  target

def Time.with_target(t: Time, target: W.Words) -> Time:
  Time{current, previous, update, draw, frame, _, counter} = t
  Time{current, previous, update, draw, frame, target, counter}

def Time.with_counter(t: Time, +counter: U32) -> Time:
  Time{current, previous, update, draw, frame, target, _} = t
  Time{current, previous, update, draw, frame, target, counter}

def Time.next_frame(t: Time) -> Time:
  Time{current, previous, update, draw, frame, target, +counter} = t
  Time{current, previous, update, draw, frame, target, (counter + 1 : U32)}

# -----------------------------------------------------------------------------
# Timing

def target.of(fps: Maybe<W.Words>) -> W.Words:
  match fps:
    case None{}: Clock.zero()
    case Some{t}: t

# SetTargetFPS: 0 below 1 FPS, else 1.0/(double)fps (always inside the
# division helper's domain).
def target(+fps: U32) -> W.Words:
  Bool.pick(W.Words, In.signed_less(fps, 1), Clock.zero(), target.of(Clock.divide(Clock.one(), Clock.from_positive(fps))))

def Core.set_target_fps(core: Core, +fps: U32) -> Core:
  +c = core
  Core.with_time(c, Time.with_target(Core.time(c), target(fps)))

# BeginDrawing: current = now, update = current - previous, previous = current.
def begin.update(update: Maybe<W.Words>, t: Time, +now: W.Words) -> Maybe<Time>:
  match update:
    case None{}: None{}
    case Some{u}:
      Time{_, _, _, draw, frame, target, counter} = t
      Some{Time{now, now, u, draw, frame, target, counter}}

def Time.begin(+t: Time, +now: W.Words) -> Maybe<Time>:
  Time{_, +previous, _, _, _, _, _} = t
  begin.update(Clock.sub(now, previous), t, now)

def begin.done(+core: Core, time: Maybe<Time>) -> Maybe<Core>:
  match time:
    case None{}: None{}
    case Some{t}: Some{Core.with_time(core, t)}

def Core.begin_drawing(+core: Core, +now: W.Words) -> Maybe<Core>:
  begin.done(core, Time.begin(Core.time(core), now))

# EndDrawing's timing at time now (after SwapScreenBuffer): draw = now -
# previous, frame = update + draw. When frame < target, WaitTime(target - frame)
# waits until the clock reaches now + (target - frame); `after` is the clock
# when the wait ends (it must have reached that destination), and the wait is
# added to the frame time. Answers the new Time and the clock PollInputEvents
# reads.
def reached(ok: Bool, +after: W.Words) -> Maybe<W.Words>:
  match ok:
    case False{}: None{}
    case True{}: Some{after}

def end.waited(+now: W.Words, +after: W.Words, +update: W.Words, +draw: W.Words, +frame: W.Words, +target: W.Words, +counter: U32) -> Maybe<(Time & W.Words)>:
  do Maybe<&1, (Time & W.Words)>:
    seconds : W.Words <- Clock.sub(target, frame)
    destination : W.Words <- Clock.add(now, seconds)
    ended : W.Words <- reached(Bool.not(Clock.less(after, destination)), after)
    wait : W.Words <- Clock.sub(ended, now)
    total : W.Words <- Clock.add(frame, wait)
    return (Time{after, after, update, draw, total, target, counter}, after)

def end.wait(waiting: Bool, +now: W.Words, +after: W.Words, +update: W.Words, +draw: W.Words, +frame: W.Words, +target: W.Words, +counter: U32) -> Maybe<(Time & W.Words)>:
  match waiting:
    case False{}: Some{(Time{now, now, update, draw, frame, target, counter}, now)}
    case True{}: end.waited(now, after, update, draw, frame, target, counter)

def Time.end(+t: Time, +now: W.Words, +after: W.Words) -> Maybe<(Time & W.Words)>:
  Time{_, +previous, +update, _, _, +target, +counter} = t
  do Maybe<&1, (Time & W.Words)>:
    +draw : W.Words <- Clock.sub(now, previous)
    +frame : W.Words <- Clock.add(update, draw)
    result : (Time & W.Words) <- end.wait(Clock.less(frame, target), now, after, update, draw, frame, target, counter)
    return result

def wait.seconds(waiting: Bool, +target: W.Words, +frame: W.Words) -> Maybe<W.Words>:
  match waiting:
    case False{}: Some{Clock.zero()}
    case True{}: Clock.sub(target, frame)

# The seconds EndDrawing at time now would pass to WaitTime (+0 when it does
# not wait).
def Time.wait(+t: Time, +now: W.Words) -> Maybe<W.Words>:
  Time{_, +previous, +update, _, _, +target, _} = t
  do Maybe<&1, W.Words>:
    +draw : W.Words <- Clock.sub(now, previous)
    +frame : W.Words <- Clock.add(update, draw)
    seconds : W.Words <- wait.seconds(Clock.less(frame, target), target, frame)
    return seconds

def Core.frame_wait(+core: Core, +now: W.Words) -> Maybe<W.Words>:
  Time.wait(Core.time(core), now)

# GetFrameTime: (float)CORE.Time.frame.
def Core.frame_time(+core: Core) -> Maybe<F32>:
  Clock.narrow(Time.frame(Core.time(core)))

# -----------------------------------------------------------------------------
# GetFPS: FPS_CAPTURE_FRAMES_COUNT 30, FPS_STEP 0.5f/30; the history resets
# while the frame counter is 0.

def roundf(+x: F32) -> F32:
  +t = F32.trunc(x)
  Bool.pick(F32, (F32.abs((x - t : F32)) >= 0.5 : F32), Bool.pick(F32, (x < 0.0 : F32), (t - 1.0 : F32), (t + 1.0 : F32)), t)

def fps.answer(+average: F32) -> Maybe<U32>:
  In.f32_int(roundf((1.0 / average : F32)))

def fps.update(+fps: Fps, +frame: F32, +now: W.Words) -> Maybe<Fps>:
  Fps{+index, +history, +average, _} = fps
  +next = ((index + 1) % 30 : U32)
  +old = In.item(F32, history, U32.to_nat(next), 0.0)
  +entry = (frame / 30.0 : F32)
  do Maybe<&1, Fps>:
    last : F32 <- Clock.narrow(now)
    return Fps{next, List.set(&2, F32, history, U32.to_nat(next), entry), ((average - old) + entry : F32), last}

def fps.step() -> W.Words:
  target.of(Clock.promote((0.5 / 30.0 : F32)))

def fps.stepped(due: Bool, +fps: Fps, +frame: F32, +now: W.Words) -> Maybe<Fps>:
  match due:
    case False{}: Some{fps}
    case True{}: fps.update(fps, frame, now)

def fps.average(+fps: Fps) -> F32:
  Fps{_, _, average, _} = fps
  average

def fps.measured(+fps: Fps, +frame: F32, +now: W.Words) -> Maybe<(Fps & U32)>:
  Fps{_, _, _, +last} = fps
  do Maybe<&1, (Fps & U32)>:
    since : W.Words <- Clock.promote(last)
    elapsed : W.Words <- Clock.sub(now, since)
    +updated : Fps <- fps.stepped(Clock.greater(elapsed, fps.step()), fps, frame, now)
    value : U32 <- fps.answer(fps.average(updated))
    return (updated, value)

def fps.frame(nonzero: Bool, +fps: Fps, +frame: F32, +now: W.Words) -> Maybe<(Fps & U32)>:
  match nonzero:
    case False{}: Some{(fps, 0)}
    case True{}: fps.measured(fps, frame, now)

def fps.of(+core: Core, +frame: F32, +now: W.Words) -> Maybe<(Fps & U32)>:
  Core{_, _, _, +time, +fps, _, _} = core
  fps.frame(F32.is_ne(frame, 0.0), Bool.pick(Fps, U32.is_eq(Time.counter(time), 0), Fps.new(), fps), frame, now)

def fps.pair(+core: Core, pair: Fps & U32) -> Maybe<(Core & U32)>:
  (fps, value) = pair
  Some{(Core.with_fps(core, fps), value)}

def fps.store(+core: Core, result: Maybe<(Fps & U32)>) -> Maybe<(Core & U32)>:
  match result:
    case None{}: None{}
    case Some{pair}: fps.pair(core, pair)

def fps.timed(+core: Core, frame: Maybe<F32>, +now: W.Words) -> Maybe<(Core & U32)>:
  match frame:
    case None{}: None{}
    case Some{+f}: fps.store(core, fps.of(core, f, now))

# GetFPS at time now (it reads the clock): the new state and the FPS.
def Core.get_fps(+core: Core, +now: W.Words) -> Maybe<(Core & U32)>:
  fps.timed(core, Core.frame_time(core), now)

# -----------------------------------------------------------------------------
# PlayAutomationEvent (ignored while recording)

def play.input(+core: Core, input: Maybe<In.Input>) -> Maybe<Core>:
  match input:
    case None{}: None{}
    case Some{i}: Some{Core.with_input(core, i)}

def play.event(+kind: U32, +core: Core, +p0: U32, +p1: U32, +p2: U32) -> Maybe<Core>:
  match kind:
    case 17: Some{Core.with_gestures(core, G.Gestures.with_current(Core.gestures(core), p0))}
    case 18: Some{Core.with_window(core, Screen.close(Core.window(core)))}
    case 22: Some{Core.with_window(core, Screen.screenshot(Core.window(core)))}
    case 23: Some{Core.set_target_fps(core, p0)}
    case _: play.input(core, In.play(kind, p0, p1, p2, Core.input(core)))

def play.active(recording: Bool, +core: Core, +kind: U32, +p0: U32, +p1: U32, +p2: U32) -> Maybe<Core>:
  match recording:
    case True{}: Some{core}
    case False{}: play.event(kind, core, p0, p1, p2)

# Window events: WINDOW_CLOSE sets shouldClose; WINDOW_MAXIMIZE, _MINIMIZE and
# _RESIZE only log a warning on the memory platform. ACTION_TAKE_SCREENSHOT
# counts a screenshot (TakeScreenshot writes screenshot%03i.png of the frame);
# ACTION_SETTARGETFPS calls SetTargetFPS. Other types leave the state unchanged.
def Core.play(+core: Core, +kind: U32, +p0: U32, +p1: U32, +p2: U32) -> Maybe<Core>:
  play.active(Core.recording(core), core, kind, p0, p1, p2)

# -----------------------------------------------------------------------------
# RecordAutomationEvent: EndDrawing appends the frame's events while recording,
# stopping when the list is full. Conditions with C int conversions are only
# evaluated while there is room (as raylib returns first).

type Rec is Data:
  Rec{room: U32, frame: U32, events: +List<A.AutoEvent>, bad: Bool}

def rec.add(+rec: Rec, defined: Bool, add: Bool, +kind: U32, +p0: U32, +p1: U32, +p2: U32) -> Rec:
  Rec{+room, +frame, +events, +bad} = rec
  Bool.pick(Rec, U32.is_eq(room, 0), rec,
    Bool.pick(Rec, defined, Bool.pick(Rec, add, Rec{(room - 1 : U32), frame, Con{A.AutoEvent{frame, kind, p0, p1, p2, 0}, events}, bad}, rec),
      Rec{room, frame, events, True{}}))

def rec.key(+kb: In.Keyboard, +key: U32, rec: Rec) -> Rec:
  +previous = In.bits.get(In.Keyboard.previous(kb), key)
  +current = In.bits.get(In.Keyboard.current(kb), key)
  rec.add(rec.add(rec, True{}, previous && Bool.not(current), 1, key, 0, 0), True{}, current, 2, key, 0, 0)

def rec.keys(n: Nat, +kb: In.Keyboard, +key: U32, rec: Rec) -> Rec:
  match n:
    case 0n: rec
    case 1n+k: rec.keys(k, kb, (key + 1 : U32), rec.key(kb, key, rec))

def rec.button(+mouse: In.MouseState, +button: U32, rec: Rec) -> Rec:
  +previous = In.bit.of(In.MouseState.previous_buttons(mouse), button)
  +current = In.bit.of(In.MouseState.buttons(mouse), button)
  rec.add(rec.add(rec, True{}, previous && Bool.not(current), 5, button, 0, 0), True{}, current, 6, button, 0, 0)

def rec.buttons(n: Nat, +mouse: In.MouseState, +button: U32, rec: Rec) -> Rec:
  match n:
    case 0n: rec
    case 1n+k: rec.buttons(k, mouse, (button + 1 : U32), rec.button(mouse, button, rec))

# A changed (int) position: x pair first, the y pair only when x is unchanged.
def rec.moved(+rec: Rec, +kind: U32, +id: U32, +withid: Bool, +now: In.Point, +before: In.Point) -> Rec:
  In.Point{+x, +y} = now
  In.Point{+px, +py} = before
  +cx = In.f32_int.word(x)
  +cy = In.f32_int.word(y)
  +xdiff = U32.is_ne(cx, In.f32_int.word(px))
  +defined = In.f32_int.valid(x) && In.f32_int.valid(px) && In.f32_int.valid(y) && (xdiff || In.f32_int.valid(py))
  +changed = xdiff || U32.is_ne(cy, In.f32_int.word(py))
  Bool.pick(Rec, withid, rec.add(rec, defined, changed, kind, id, cx, cy), rec.add(rec, defined, changed, kind, cx, cy, 0))

def rec.touch(+touch: In.Touch, +id: U32, rec: Rec) -> Rec:
  +previous = In.bit.of(In.Touch.previous(touch), id)
  +current = In.bit.of(In.Touch.current(touch), id)
  rec.moved(rec.add(rec.add(rec, True{}, previous && Bool.not(current), 14, id, 0, 0), True{}, current, 15, id, 0, 0), 16, id, True{},
    In.vector.at(In.Touch.positions(touch), id), In.vector.at(In.Touch.previous_positions(touch), id))

def rec.touches(n: Nat, +touch: In.Touch, +id: U32, rec: Rec) -> Rec:
  match n:
    case 0n: rec
    case 1n+k: rec.touches(k, touch, (id + 1 : U32), rec.touch(touch, id, rec))

def rec.pad_button(+pads: In.Gamepads, +gamepad: U32, +button: U32, rec: Rec) -> Rec:
  +previous = In.Gamepads.button(In.Gamepads.previous(pads), gamepad, button)
  +current = In.Gamepads.button(In.Gamepads.current(pads), gamepad, button)
  rec.add(rec.add(rec, True{}, previous && Bool.not(current), 11, gamepad, button, 0), True{}, current, 12, gamepad, button, 0)

def rec.pad_buttons(n: Nat, +pads: In.Gamepads, +gamepad: U32, +button: U32, rec: Rec) -> Rec:
  match n:
    case 0n: rec
    case 1n+k: rec.pad_buttons(k, pads, gamepad, (button + 1 : U32), rec.pad_button(pads, gamepad, button, rec))

def movement(value: Maybe<F32>) -> F32:
  match value:
    case None{}: 0.0
    case Some{v}: v

# INPUT_GAMEPAD_AXIS_MOTION when GetGamepadAxisMovement differs from the rest
# value, with (int)(axisState*32768.0f).
def rec.axis(+input: In.Input, +gamepad: U32, +axis: U32, rec: Rec) -> Rec:
  +moved = F32.is_ne(movement(In.gamepad.axis_movement(input, gamepad, axis)), In.gamepad.rest(axis))
  +delta = (In.Gamepads.axis(In.Input.gamepads(input), gamepad, axis) * 32768.0 : F32)
  rec.add(rec, Bool.not(moved) || In.f32_int.valid(delta), moved, 13, gamepad, axis, In.f32_int.word(delta))

def rec.axes(n: Nat, +input: In.Input, +gamepad: U32, +axis: U32, rec: Rec) -> Rec:
  match n:
    case 0n: rec
    case 1n+k: rec.axes(k, input, gamepad, (axis + 1 : U32), rec.axis(input, gamepad, axis, rec))

def rec.gamepads(n: Nat, +input: In.Input, +gamepad: U32, rec: Rec) -> Rec:
  match n:
    case 0n: rec
    case 1n+k: rec.gamepads(k, input, (gamepad + 1 : U32), rec.axes(8n, input, gamepad, 0, rec.pad_buttons(32n, In.Input.gamepads(input), gamepad, 0, rec)))

def rec.all(+core: Core, rec: Rec) -> Rec:
  +input = Core.input(core)
  +mouse = In.Input.mouse(input)
  +current = G.Gestures.current(Core.gestures(core))
  rec.add(rec.gamepads(4n, input, 0, rec.touches(8n, In.Input.touch(input), 0,
      rec.moved(rec.moved(rec.buttons(8n, mouse, 0, rec.keys(512n, In.Input.keyboard(input), 0, rec)), 7, 0, False{},
          In.MouseState.position(mouse), In.MouseState.previous(mouse)), 8, 0, False{}, In.MouseState.wheel(mouse), In.MouseState.previous_wheel(mouse)))),
    True{}, U32.is_ne(current, 0), 17, current, 0, 0)

def rec.store(+core: Core, list: A.AutoList, rec: Rec) -> Maybe<Core>:
  Rec{_, _, +events, bad} = rec
  match bad:
    case True{}: None{}
    case False{}: Some{Core.with_list(core, Some{A.AutoList.append(list, List.reverse(&2, A.AutoEvent, events), U32.from_nat(List.length(&2, A.AutoEvent, events)))})}

def rec.list(+core: Core, list: Maybe<&2, A.AutoList>) -> Maybe<Core>:
  match list:
    case None{}: None{}
    case Some{+l}: rec.store(core, l, rec.all(core, Rec{(A.AutoList.capacity(l) - A.AutoList.count(l) : U32), Time.counter(Core.time(core)), Nil{}, False{}}))

def record(recording: Bool, +core: Core) -> Maybe<Core>:
  match recording:
    case False{}: Some{core}
    case True{}: rec.list(core, Core.list(core))

# -----------------------------------------------------------------------------
# EndDrawing and PollInputEvents

# PollInputEvents (memory platform) at time now: UpdateGestures, then the input
# state (src/input.bend poll). Its kbhit() check of the terminal's standard
# input for an ESC byte is not modeled.
def Core.poll(+core: Core, +now: W.Words) -> Core:
  Core.with_input(Core.with_gestures(core, G.update(Core.gestures(core), now)), In.poll(Core.input(core)))

# After polling, EndDrawing's SUPPORT_SCREEN_CAPTURE check: IsKeyPressed(KEY_F12)
# takes a screenshot (on the memory platform key 301's previous state is never
# updated, so a held F12 shoots every frame).
def Core.f12(+core: Core) -> Core:
  Bool.pick(Core, In.Keyboard.is_pressed(In.Input.keyboard(Core.input(core)), 301), Core.with_window(core, Screen.screenshot(Core.window(core))), core)

def end.counted(+core: Core) -> Core:
  Core.with_time(core, Time.next_frame(Core.time(core)))

def end.polled(+core: Core, pair: Time & W.Words) -> Maybe<Core>:
  (time, now) = pair
  Some{end.counted(Core.f12(Core.poll(Core.with_time(core, time), now)))}

def end.timed(+core: Core, timed: Maybe<(Time & W.Words)>) -> Maybe<Core>:
  match timed:
    case None{}: None{}
    case Some{pair}: end.polled(core, pair)

def end.recorded(recorded: Maybe<Core>, +now: W.Words, +after: W.Words) -> Maybe<Core>:
  match recorded:
    case None{}: None{}
    case Some{+core}: end.timed(core, Time.end(Core.time(core), now, after))

# EndDrawing at time now (after the swap), with `after` the clock when a
# SetTargetFPS wait ends (ignored when it does not wait): automation recording,
# frame timing, PollInputEvents, the F12 screenshot check and the frame counter.
def Core.end_drawing(+core: Core, +now: W.Words, +after: W.Words) -> Maybe<Core>:
  end.recorded(record(Core.recording(core), core), now, after)

# -----------------------------------------------------------------------------
# Automation recording controls

# StartAutomationEventRecording: refused without a list (raylib would write
# through a NULL list at the next EndDrawing).
def Core.start_recording(+core: Core) -> Maybe<Core>:
  Bool.pick(Maybe<Core>, Maybe.is_some(&2, A.AutoList, Core.list(core)), Some{Core.with_recording(core, True{})}, None{})

def Core.stop_recording(core: Core) -> Core:
  Core.with_recording(core, False{})

# SetAutomationEventList: the list EndDrawing records into.
def Core.set_list(core: Core, list: A.AutoList) -> Core:
  Core.with_list(core, Some{list})

# SetAutomationEventBaseFrame: CORE.Time.frameCounter = frame.
def Core.set_base_frame(+core: Core, +frame: U32) -> Core:
  Core.with_time(core, Time.with_counter(Core.time(core), frame))

# -----------------------------------------------------------------------------
# Input functions that change the state

def Core.with_keyboard(+core: Core, keyboard: In.Keyboard) -> Core:
  Core.with_input(core, In.Input.with_keyboard(Core.input(core), keyboard))

def Core.with_mouse(+core: Core, mouse: In.MouseState) -> Core:
  Core.with_input(core, In.Input.with_mouse(Core.input(core), mouse))

def Core.keyboard(+core: Core) -> In.Keyboard:
  In.Input.keyboard(Core.input(core))

def Core.mouse(+core: Core) -> In.MouseState:
  In.Input.mouse(Core.input(core))

def popped(+core: Core, result: In.Keyboard & U32) -> Core & U32:
  (keyboard, value) = result
  (Core.with_keyboard(core, keyboard), value)

# GetKeyPressed and GetCharPressed: the queue head (0 when empty).
def Core.pop_key(+core: Core) -> Core & U32:
  popped(core, In.Keyboard.pop_key(Core.keyboard(core)))

def Core.pop_char(+core: Core) -> Core & U32:
  popped(core, In.Keyboard.pop_char(Core.keyboard(core)))

def Core.set_exit_key(+core: Core, +key: U32) -> Core:
  Core.with_keyboard(core, In.Keyboard.set_exit_key(Core.keyboard(core), key))

def Core.set_mouse_position(+core: Core, +x: U32, +y: U32) -> Core:
  Core.with_mouse(core, In.MouseState.move_to(Core.mouse(core), x, y))

def Core.set_mouse_offset(+core: Core, +x: U32, +y: U32) -> Core:
  Core.with_mouse(core, In.MouseState.set_offset(Core.mouse(core), x, y))

def Core.set_mouse_scale(+core: Core, +x: F32, +y: F32) -> Core:
  Core.with_mouse(core, In.MouseState.set_scale(Core.mouse(core), x, y))

def Core.set_cursor_hidden(+core: Core, hidden: Bool) -> Core:
  Core.with_mouse(core, In.MouseState.set_hidden(Core.mouse(core), hidden))

# EnableCursor/DisableCursor (memory platform): SetMousePosition to the screen
# center (unsigned halves), then show/hide.
def Screen.center(+w: Screen) -> U32 & U32:
  Screen{+width, +height, _, _} = w
  ((width / 2 : U32), (height / 2 : U32))

def center.moved(+core: Core, center: U32 & U32) -> Core:
  (x, y) = center
  Core.set_mouse_position(core, x, y)

def Core.center_cursor(+core: Core, hidden: Bool) -> Core:
  Core.set_cursor_hidden(center.moved(core, Screen.center(Core.window(core))), hidden)

# rcore_desktop_glfw.c KeyCallback: negative keys are ignored, other keys
# outside 0..511 are None; pressing the exit key requests closing.
def key.closing(+core: Core, close: Bool) -> Core:
  Bool.pick(Core, close, Core.with_window(core, Screen.close(Core.window(core))), core)

def key.callback(+core: Core, +key: U32, +action: U32, +mods: U32) -> Core:
  key.closing(Core.with_keyboard(core, In.Keyboard.callback(Core.keyboard(core), key, action, mods)),
    U32.is_eq(key, In.Keyboard.exit_key(Core.keyboard(core))) && U32.is_eq(action, 1))

def Core.key_callback(+core: Core, +key: U32, +action: U32, +mods: U32) -> Maybe<Core>:
  Bool.pick(Maybe<Core>, In.negative(key), Some{core}, Bool.pick(Maybe<Core>, (key < 512 : U32), Some{key.callback(core, key, action, mods)}, None{}))

def Core.char_callback(+core: Core, +codepoint: U32) -> Core:
  Core.with_keyboard(core, In.Keyboard.char_callback(Core.keyboard(core), codepoint))

# -----------------------------------------------------------------------------
# Gestures

def gesture.stored(+core: Core, gestures: Maybe<G.Gestures>) -> Maybe<Core>:
  match gestures:
    case None{}: None{}
    case Some{g}: Some{Core.with_gestures(core, g)}

# ProcessGestureEvent at time now with the atan2f profile.
def Core.process_gesture(+core: Core, +profile: U32, +action: U32, +count: U32, +p0: In.Point, +p1: In.Point, +now: W.Words) -> Maybe<Core>:
  gesture.stored(core, G.process(profile, Core.gestures(core), action, count, p0, p1, now))

def Core.set_gestures_enabled(+core: Core, +flags: U32) -> Core:
  Core.with_gestures(core, G.Gestures.with_enabled(Core.gestures(core), flags))

# -----------------------------------------------------------------------------
# Desktop platform (src/platforms/rcore_desktop_glfw.c) for the desktop
# driver: EndDrawing split around PollInputEvents, so the driver can run the
# GLFW callbacks for the events Base pumped where glfwPollEvents runs them.

def Screen.reopen(w: Screen) -> Screen:
  Screen{width, height, _, shots} = w
  Screen{width, height, False{}, shots}

def Screen.size(+w: Screen) -> In.Point:
  Screen{+width, +height, _, _} = w
  In.Point{U32.to_f32(width), U32.to_f32(height)}

def end.timing.pair(+core: Core, pair: Time & W.Words) -> Maybe<(Core & W.Words)>:
  (time, now) = pair
  Some{(Core.with_time(core, time), now)}

def end.timing.timed(+core: Core, timed: Maybe<(Time & W.Words)>) -> Maybe<(Core & W.Words)>:
  match timed:
    case None{}: None{}
    case Some{pair}: end.timing.pair(core, pair)

def end.timing.recorded(recorded: Maybe<Core>, +now: W.Words, +after: W.Words) -> Maybe<(Core & W.Words)>:
  match recorded:
    case None{}: None{}
    case Some{+core}: end.timing.timed(core, Time.end(Core.time(core), now, after))

# EndDrawing up to PollInputEvents: recording and frame timing (as
# Core.end_drawing); also answers the clock PollInputEvents reads.
def Core.end_timing(+core: Core, +now: W.Words, +after: W.Words) -> Maybe<(Core & W.Words)>:
  end.timing.recorded(record(Core.recording(core), core), now, after)

# EndDrawing after PollInputEvents: the F12 screenshot check and the frame
# counter.
def Core.end_finish(+core: Core) -> Core:
  end.counted(Core.f12(core))

# PollInputEvents (desktop) at time now, before the callbacks: UpdateGestures,
# the input registration of src/input.bend poll_desktop, and the close request
# cleared (glfwWindowShouldClose is read after the callbacks and reset every
# poll, so WindowShouldClose answers the events of the last poll only).
def Core.poll_desktop(+core: Core, +now: W.Words) -> Core:
  Core.with_window(Core.with_input(Core.with_gestures(core, G.update(Core.gestures(core), now)), In.poll_desktop(Core.input(core))),
    Screen.reopen(Core.window(core)))

# The window's close button (glfwWindowShouldClose after the callbacks).
def Core.request_close(+core: Core) -> Core:
  Core.with_window(core, Screen.close(Core.window(core)))

def desktop.divided(+x: F32, +y: F32, +size: In.Point) -> In.Point:
  In.Point{sx, sy} = size
  In.Point{(x / sx : F32), (y / sy : F32)}

def desktop.normalized(+p: In.Point, +size: In.Point) -> In.Point:
  In.Point{x, y} = p
  desktop.divided(x, y, size)

# MouseButtonCallback (buttons 0..7) at time now: the button and touch states,
# then (SUPPORT_MOUSE_GESTURES) a one-point gesture event at
# GetMousePosition()/screen size, TOUCH_ACTION_DOWN when the button went down
# since the last poll and TOUCH_ACTION_UP (0) otherwise, as the zeroed event
# of rcore_desktop_glfw.c is.
def Core.mouse_button(+core: Core, +profile: U32, +button: U32, +down: Bool, +now: W.Words) -> Maybe<Core>:
  +previous = In.bit.of(In.MouseState.previous_buttons(Core.mouse(core)), button)
  +updated = Core.with_input(core, In.mouse_button_callback(Core.input(core), button, down))
  Core.process_gesture(updated, profile, Bool.pick(U32, down && Bool.not(previous), 1, 0), 1,
    desktop.normalized(In.MouseState.screen(Core.mouse(updated)), Screen.size(Core.window(core))), In.vector.zero(), now)

# MouseCursorPosCallback at time now: the position (and touch point 0), then a
# TOUCH_ACTION_MOVE gesture event at that position/screen size.
def Core.cursor_position(+core: Core, +profile: U32, +position: In.Point, +now: W.Words) -> Maybe<Core>:
  Core.process_gesture(Core.with_input(core, In.cursor_position_callback(Core.input(core), position)), profile, 2, 1,
    desktop.normalized(position, Screen.size(Core.window(core))), In.vector.zero(), now)
