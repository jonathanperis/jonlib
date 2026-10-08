# Input, automation events, gestures and timing

Phase 2, delivery slice 4 ([PHASE2-DESIGN.md](PHASE2-DESIGN.md)): a `Core`
value holds the state raylib keeps in its `CORE` globals between frames
(`CORE.Input`, `CORE.Time`, the window close request), plus rgestures.h's
`GESTURES`, `GetFPS`'s averaging state, the screenshot counter and the
automation event recorder. Altered Bend adaptations of pinned raylib 6.0
`src/rcore.c`, `src/platforms/rcore_memory.c` and `src/rgestures.h` (zlib,
[LICENSES/raylib.txt](../LICENSES/raylib.txt)); the key and char callbacks
follow `src/platforms/rcore_desktop_glfw.c`. Code: the public section
"Input, gestures and timing" of `jonlib.bend`, `src/input.bend` (keyboard,
mouse, touch, gamepads), `src/gestures.bend`, `src/automation.bend` (event
lists and their text format), `src/core_state.bend` (timing, FPS, recording,
event playback) and `src/clock.bend` (binary64 time values).

## Reference and the explicit clock

The reference is raylib's memory platform (`PLATFORM=Memory`), the platform
the frame slice compares against. It has no input system of its own: input
reaches `CORE.Input` only through `PlayAutomationEvent`, `SetMousePosition`
and the cursor functions, and gestures only through `ProcessGestureEvent` and
`INPUT_GESTURE` events.

**Time is an input.** Every function whose raylib code calls `GetTime()`
takes `now: M.Float64`, the binary64 seconds `GetTime()` would return at that
call: `Core.init_window` (InitTimer), `Core.begin_drawing`,
`Core.end_drawing`, `Core.get_fps`, `Gestures.process_event`,
`Gestures.update`, `Gestures.get_hold_duration`. A driver passes its clock;
the verification passes scripted times. Time arithmetic is done as raylib does
it, in binary64 (`src/binary64_*.bend`, [BINARY64.md](BINARY64.md)), and is
`None` outside those helpers' domains (sums and differences of zero or normal
values with exponents in [-900, 130]; any realistic clock qualifies).

**Controlling the native clock.** On macOS `rcore_memory.c`'s `GetTime`
returns 0.0 (it has Windows and Linux branches only), so frame times, gesture
timeouts and `GetFPS` samples are always 0 there and `SetTargetFPS` hangs in
`WaitTime`'s busy loop. The probe therefore builds its raylib variant with
`CMAKE_C_FLAGS="-ffp-contract=off -include tools/reference/input_clock.h"`.
The shim renames identifiers only: `GetTime()` calls read the script's clock
(the platform's own definition becomes an unused `rlPlatformGetTime`), and
`WaitTime`'s `usleep`/`nanosleep` record the request and move the clock to the
script's end-of-wait time. No raylib source is changed. The same pinned code
paths run (`PlayAutomationEvent`, `PollInputEvents`, `EndDrawing`, `GetFPS`,
`WaitTime`, rgestures.h inside rcore.c), so this is not a standalone control.

**Build configuration.** probekit's raylib builds use `CUSTOMIZE_BUILD=ON`,
and raylib 6.0's `cmake/ParseConfigHeader.cmake` turns every
`#define SUPPORT_X <value>` of `config.h` into an ON option, including the
ones defined as 0. Such builds compile `SUPPORT_CUSTOM_FRAME_CONTROL` (so
`EndDrawing` neither times frames nor polls input, and `GetFPS` returns 0),
`SUPPORT_BUSY_WAIT_LOOP` and the file formats `config.h` disables (TGA, JPG,
PSD, HDR, PIC, PNM, KTX, ASTC, PKM, PVR, BDF, FLAC, GPU skinning). The input
probe restores `config.h`'s frame control (`SUPPORT_CUSTOM_FRAME_CONTROL=OFF`,
`SUPPORT_BUSY_WAIT_LOOP=OFF`, leaving `SUPPORT_PARTIALBUSY_WAIT_LOOP`) and
checks the variant's compile definitions.

## State and API

`Core.init_window(width, height, now) -> Maybe<Core>` is `InitWindow`'s input
and timing state for sizes 1..4096 (as `Frame.init_window`): `CORE.Input`
zeroed with exit key `KEY_ESCAPE` (256) and mouse scale (1, 1), every gesture
enabled, `CORE.Time.previous = now`, no target FPS, frame counter 0. A Core is
a fresh process: raylib keeps `GESTURES`, the target FPS, `GetFPS`'s history
and the screenshot counter across a second `InitWindow`, which is not modeled.
The drawing state is the `Frame`'s (see [FRAME.md](FRAME.md)); a program calls
both `Frame.begin_drawing`/`Frame.end_drawing` and
`Core.begin_drawing`/`Core.end_drawing`.

C ints are `U32` two's-complement words, keys and buttons are raylib's enum
values (`KeyboardKey.*`, `Gesture.*` constants of the last section). Functions
that change the state return the new `Core`; `Maybe` results are `None` where
raylib's C is undefined (see [Refusals](#refusals)).

| raylib | Jonlib |
|---|---|
| `InitWindow` / `CloseWindow` | `Core.init_window(w, h, now)` / `Core.close_window(core)` |
| `WindowShouldClose` | `Core.window_should_close(core) -> Bool` |
| `BeginDrawing` / `EndDrawing` (timing, recording, polling) | `Core.begin_drawing(core, now)`, `Core.end_drawing(core, now, after) -> Maybe<Core>`; `Core.frame_wait(core, now) -> Maybe<M.Float64>` |
| `PollInputEvents` | `Core.poll_input_events(core, now) -> Core` |
| `SetTargetFPS` / `GetFrameTime` / `GetFPS` | `Core.set_target_fps(core, fps)`, `Core.get_frame_time(core) -> F32`, `Core.get_fps(core, now) -> Maybe<(Core & U32)>` |
| screenshot requests (F12, `ACTION_TAKE_SCREENSHOT`) | `Core.screenshot_count(core) -> U32` |
| `PlayAutomationEvent` | `Core.play_automation_event(core, event) -> Maybe<Core>` |
| `LoadAutomationEventList` | `AutomationEventList.new()` (NULL), `AutomationEventList.parse(bytes)`, `AutomationEventList.load(path) -> IO(Maybe<...>)` |
| `ExportAutomationEventList` | `AutomationEventList.export_text(list) -> Maybe<String>`, `AutomationEventList.export(list, path)` |
| `UnloadAutomationEventList` | `AutomationEventList.unload(list)` |
| `SetAutomationEventList` / `SetAutomationEventBaseFrame` | `Core.set_automation_event_list`, `Core.set_automation_event_base_frame`; `Core.automation_event_list(core)` reads it back |
| `Start/StopAutomationEventRecording` | `Core.start_automation_event_recording -> Maybe<Core>`, `Core.stop_automation_event_recording` |
| `IsKeyPressed/PressedRepeat/Down/Released/Up` | `Input.is_key_pressed`, `_pressed_repeat`, `_down`, `_released`, `_up` |
| `GetKeyPressed` / `GetCharPressed` / `SetExitKey` | `Input.get_key_pressed(core) -> Core & U32`, `Input.get_char_pressed`, `Input.set_exit_key` |
| GLFW key/char callbacks (desktop) | `Input.key_callback(core, key, action, mods) -> Maybe<Core>`, `Input.char_callback(core, codepoint)` |
| `IsMouseButtonPressed/Down/Released/Up` | `Input.is_mouse_button_pressed`, `_down`, `_released`, `_up` |
| `GetMouseX/Y`, `GetMousePosition`, `GetMouseDelta` | `Input.get_mouse_x/_y -> Maybe<U32>`, `Input.get_mouse_position`, `Input.get_mouse_delta` |
| `SetMousePosition/Offset/Scale` | `Input.set_mouse_position`, `Input.set_mouse_offset`, `Input.set_mouse_scale` |
| `GetMouseWheelMove(V)` | `Input.get_mouse_wheel_move -> F32`, `Input.get_mouse_wheel_move_v` |
| `Show/HideCursor`, `Enable/DisableCursor`, `IsCursorHidden/OnScreen` | `Input.show_cursor`, `hide_cursor`, `enable_cursor`, `disable_cursor`, `is_cursor_hidden`, `is_cursor_on_screen` |
| `GetTouchX/Y`, `GetTouchPosition`, `GetTouchPointId`, `GetTouchPointCount` | `Input.get_touch_x/_y -> Maybe<U32>`, `Input.get_touch_position -> Maybe<M.Vector2>`, `Input.get_touch_point_id -> Maybe<U32>`, `Input.get_touch_point_count` |
| `IsGamepadAvailable`, `IsGamepadButton*`, `GetGamepadName` | `Input.is_gamepad_available -> Maybe<Bool>`, `Input.is_gamepad_button_pressed/down/released/up -> Maybe<Bool>`, `Input.get_gamepad_name -> Maybe<String>` |
| `GetGamepadButtonPressed`, `GetGamepadAxisCount`, `GetGamepadAxisMovement` | `Input.get_gamepad_button_pressed`, `Input.get_gamepad_axis_count -> Maybe<U32>`, `Input.get_gamepad_axis_movement -> Maybe<F32>` |
| `ProcessGestureEvent` / `UpdateGestures` | `Gestures.process_event_for(libm, core, event, now)` (`process_event`: Apple), `Gestures.update(core, now)` |
| `SetGesturesEnabled`, `IsGestureDetected`, `GetGestureDetected` | `Gestures.set_enabled`, `Gestures.is_detected`, `Gestures.get_detected` |
| `GetGestureHoldDuration`, `GetGestureDrag*`, `GetGesturePinch*` | `Gestures.get_hold_duration(core, now) -> Maybe<F32>`, `get_drag_vector`, `get_drag_angle`, `get_pinch_vector`, `get_pinch_angle` |

Types: `AutomationEvent{frame, event_type, param0..param3}`,
`AutomationEventList{capacity, count, events}`,
`GestureEvent{touch_action, point_count, point_id, position}` (lists; the
first two positions are read).

## Semantics

**Keyboard.** Key states are 512 bits (`MAX_KEYBOARD_KEYS`); queries answer
false outside 1..511. `INPUT_KEY_DOWN` sets the key and queues it (at most 16,
`MAX_KEY_PRESSED_QUEUE`) when it was up in the previous frame, so the same key
pressed twice in a frame is queued twice. `INPUT_KEY_PRESSED`/`_RELEASED` do
nothing. `GetKeyPressed`/`GetCharPressed` pop the queue head (0 when empty).
The memory platform never fills the char queue nor sets key repeats; the
desktop callbacks do (`Input.key_callback`: release, press, repeat, the
caps/num-lock modifier rule, the queue and the exit key closing the window;
`Input.char_callback`: at most 16 codepoints).

**PollInputEvents (memory platform).** `UpdateGestures` at the given time,
then: both queues emptied, key repeats and the last gamepad button cleared,
previous touch states copied, and previous key states copied **for keys
0..259 only** (its "Android supports up to 260 keys" loop). Keys 260..511
(F1..F12, keypad, modifiers) therefore stay "pressed" while held, and mouse
and gamepad button "previous" states, the previous mouse position and the
wheel are never updated on this platform: a held mouse button stays pressed
and `GetMouseDelta` measures from the last `SetMousePosition`. Its `kbhit()`
check of the terminal's standard input for an ESC byte is not modeled. Desktop
platforms poll differently (slice 5).

**PlayAutomationEvent** (ignored while recording): key, mouse button, mouse
position/wheel (`(float)` of the ints), gamepad connect/disconnect, buttons,
axes (`(float)delta/32768.0f`), touch up/down/position, `INPUT_GESTURE` (sets
the current gesture, any value), `WINDOW_CLOSE` (sets the close request),
`ACTION_TAKE_SCREENSHOT` (counts a screenshot), `ACTION_SETTARGETFPS`
(`SetTargetFPS`). `WINDOW_MAXIMIZE`, `_MINIMIZE` and `_RESIZE` only log on the
memory platform; other types do nothing.

**Mouse and touch.** Buttons 0..6 are queried; a touch point with the same
index counts as that button (`IsMouseButtonUp` is true when either is up).
Positions are `(position + offset) * scale` in F32, `GetMouseX/Y` and
`GetTouchX/Y` their C int conversions. `GetMouseWheelMove` answers x when
`|x| > |y|`, else y. `EnableCursor`/`DisableCursor` move the mouse to the
screen center (unsigned halves). Touch positions persist; the point count and
ids stay 0 on the memory platform; indexes from 8 answer (-1, -1) and -1.

**Gamepads.** Four gamepads of 32 buttons and 8 axes. A gamepad that is not
ready answers false and the rest values (-1 for the trigger axes 4 and 5, 0
otherwise); an axis value replaces the rest value when its movement (signed
for triggers, absolute otherwise) is larger. The axis count, last button and
names (empty) are never set on the memory platform.

**Timing.** `BeginDrawing`: `update = now - previous`. `EndDrawing`, after
recording: `draw = now - previous`, `frame = update + draw`; when
`frame < target` it waits `target - frame` seconds (`Core.frame_wait`), until
the clock reaches `now + (target - frame)`, then adds the time actually waited
(`after - now`) to `frame`. `PollInputEvents` (and `UpdateGestures`) read the
clock after the wait; then `IsKeyPressed(KEY_F12)` takes a screenshot (with
the 260-key quirk a held F12 shoots every frame) and the frame counter
increments. `GetFrameTime` is `(float)frame`. `GetFPS` keeps 30 samples of
`frameTime/30` taken at most every `0.5f/30` seconds, resets them while the
frame counter is 0, answers 0 while the frame time is 0 and
`(int)roundf(1.0f/average)` otherwise. `WaitTime` itself (the sleep) is the
driver's: with `SUPPORT_PARTIALBUSY_WAIT_LOOP` raylib sleeps
`seconds - seconds*0.05` and busy-waits the rest.

**Gestures.** rgestures.h's state machine with the clock as argument: taps
and double taps (within 0.3 s and 0.03 units), `UpdateGestures` turning taps
into holds and ending swipes, drags after 0.3 s of hold movement, swipes when
the release speed exceeds 0.2 units/s from a hold (direction from the drag
angle: right below 30 or above 330 degrees, up 30..150, left 150..210, down
210..330), and two-point holds/pinches (`MINIMUM_PINCH` 0.005). Arithmetic
follows the source: binary32 distances (`(float)sqrt(dx*dx + dy*dy)` is the
correctly rounded F32 square root), binary64 time differences narrowed to
float, and the angle `atan2f(dy, dx)*(180.0f/PI)` as a binary64 product
narrowed to float. `atan2f` follows the `M.Libm` profile through Jonmath's
checked angle kernels; its operands and result must be zero or normal.
`Hold.resetRequired` (never set by rgestures.h) and the unread drag and pinch
distances are not stored.

**Recording.** While recording, `EndDrawing` appends the frame's events
(before polling) in raylib's order: per key 0..511 an up event when it was
released and a down event while held, the same for mouse buttons 0..7, the
mouse position and wheel when their int values differ from the previous ones,
touch points 0..7 (up, down, position), gamepad buttons and axes (all four
gamepads, ready or not, axes whose movement is not at rest, with
`(int)(axis*32768.0f)`), and the current gesture when not none. Events carry
the frame counter (`SetAutomationEventBaseFrame` sets it); `params[3]` is 0.
Recording stops at the list's capacity (16384) mid-frame, without evaluating
later conditions.

**Event files.** `ExportAutomationEventList` writes raylib's comment header,
`c <count>` and `e <frame> <type> <p0> <p1> <p2> <p3> // Event: <name>` lines
(`%i`). `LoadAutomationEventList` reads with `fgets` into a 256-byte buffer:
lines longer than 255 bytes continue as new "lines", a NUL ends a line for
`sscanf`, a last line without a newline is never processed, `c` lines are
read with `%i` but the count always becomes the number of `e` lines, and each
`e` line fills the fields `sscanf` converts (others stay 0). The binary
`.rae` reader and writer are commented out in the pinned source; there is no
binary format to port.

## Refusals

`None` (or a `None` field) where raylib's C is undefined or outside the
verified domain:

- events whose index is outside raylib's arrays (keys outside 0..511, mouse
  buttons outside 0..7, gamepads outside 0..3, gamepad buttons outside 0..31,
  axes outside 0..7, touch points outside 0..7);
- a negative gamepad index in any gamepad query, a negative button or axis of
  a ready gamepad, `GetGamepadAxisCount`/`GetGamepadName` outside 0..3, a
  negative touch index;
- C int conversions out of range: `GetMouseX/Y`, `GetTouchX/Y`, `GetFPS`
  before its first sample (`1/0`), recorded positions and axes, the key callback
  for keys above 511;
- starting a recording without a list (raylib writes through NULL at the next
  `EndDrawing`); an `after` clock before the wait's destination (raylib would
  keep waiting); time values outside the binary64 helpers' domain;
- exporting an event type above 23 (its name would be read out of bounds);
  loading a file whose numbers overflow an int, whose description exceeds
  `eventDesc[64]`, with more than 16384 events, or with a `c 0x` without a hex
  digit (C libraries disagree);
- gesture angles whose `atan2f` arguments or result are subnormal or
  nonfinite for the profile.

## Verification

| Gate | Tool | Compares |
|---|---|---|
| `input` | `tools/input_probe.py` | 37 scripts (1015 operations, 381 rows, 20 refusal contracts) row for row against the shimmed memory-platform raylib on CPU-1, CPU-2 and JavaScript; on macOS the 29 scripts whose clock stays 0 also against the unshimmed build |

```sh
python3 tools/input_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

Each script runs in a fresh native process and directory (rgestures.h and
`GetFPS` keep static state; screenshots are counted as the
`screenshot%03i.png` files `TakeScreenshot` writes). Scripts cover every event
type, several events per frame, queue overflow, the 260-key quirk and F12,
mouse offsets, scales and cursor centering, touch-as-mouse buttons, gamepad
rest values and trigger axes, window and action events, target-FPS waits and
irregular frame times through `GetFPS`'s averaging, clocks near 10^6 s, taps,
double taps, holds, drags, swipes in every direction, pinches, three-point and
cancel events, gesture flags, the all-zero macOS clock, recording (including
the capacity cut mid-frame), export bytes, crafted event files and replay of a
loaded list. Queries are recorded both after playing events (before
`EndDrawing`, the order raylib's `core_automation_events` example uses) and
after `EndDrawing`'s poll. Before each `EndDrawing` Jonlib's
`Core.frame_wait` is mapped to the sleep `WaitTime` requests on the host
(`usleep` microseconds on macOS, `nanosleep` seconds and nanoseconds on Linux)
and compared with the request the shim records.

`LAWS.bend` states the parts the memory platform cannot inject: the 16-entry
queue bound, key repeats set by the key callback until the next poll, the
260-key copy and `UpdateGestures`' tap-to-hold and swipe reset.

## Gaps

- Desktop input: the key and char callbacks follow `rcore_desktop_glfw.c` but
  are checked by laws, not against a native GLFW build; desktop
  `PollInputEvents` (previous mouse/gamepad states, wheel reset, gamepad
  polling, mouse gestures) and the Base window driver are slice 5.
- `GetTime` is the driver's clock (no function), `WaitTime` the driver's sleep;
  `SwapScreenBuffer` and `TakeScreenshot`'s image belong to the Frame.
- Not modeled: `SetMouseCursor` (a warning on the memory platform),
  `GetKeyName`, `SetGamepadMappings`, `SetGamepadVibration`, window state
  functions, event waiting, and state kept across a second `InitWindow`.
- The glibc `atan2f` profiles are not exercised by this probe on macOS (the
  gate selects the host profile from native controls).
- Toolchain: Apple clang 21.0.0 crashed in its backend ("live register
  clobbered by inserted prologue instructions") on the generated C of an
  earlier version of the event dispatch (a chain of `Bool.pick` over
  `Maybe<Core>`); `src/core_state.bend` dispatches with `match` instead.
