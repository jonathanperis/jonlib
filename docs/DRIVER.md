# Desktop driver and examples

Phase 2, delivery slice 5 ([PHASE2-DESIGN.md](PHASE2-DESIGN.md#3-interactive-driver)):
a `Core` ([INPUT.md](INPUT.md)) and a `Frame` ([FRAME.md](FRAME.md)) run in a
real window through Base's `Window` effects, and representative raylib
examples are ported as Bend programs that run both interactively and headless
against raylib. Altered Bend adaptations of pinned raylib 6.0
`src/platforms/rcore_desktop_glfw.c` (`PollInputEvents` and the key, mouse
button and cursor position callbacks) and `rcore.c`'s `EndDrawing` (zlib,
[LICENSES/raylib.txt](../LICENSES/raylib.txt)). Code: the "Desktop driver"
section of `jonlib.bend`, the desktop polling of `src/input.bend` and
`src/core_state.bend`, `src/present.bend` (framebuffer to quadtree) and
`Canvas.present`/`Canvas.scan` in `src/frame.bend`; the examples under
[`examples/`](../examples).

## Programs

A program is raylib's `while (!WindowShouldClose())` body over a user state
`S`, split at `BeginDrawing` because BeginDrawing reads the clock:

```bend
type Program<-S: Type> is Type:
  Program{update: Core -> S -> Core & S, draw: Core -> S -> Frame -> Core & (S & Frame)}
```

`update` is the code before `BeginDrawing` (input queries, `GetKeyPressed`,
`HideCursor`, ... return the new `Core`); `draw` runs between `BeginDrawing`
and `EndDrawing` (it may still query and change the `Core`). The same value
runs in two ways:

| | Interactive | Headless |
|---|---|---|
| Entry | `Desktop.run(~S, ~program, ~libm, title, width, height, limit, setup) -> IO(Unit)` | `Program.replay(~S, ~program, ~show, script, core, frame, state) -> List<String>` |
| Window | Base `Window.open`/`frame`/`close` through `App.run` | none (`Frame` only) |
| Clock | `IO.now`, milliseconds since InitWindow, as binary64 seconds | scripted `ReplayFrame{events, begin, end, after}` |
| Input | Base events as the GLFW callbacks of desktop `PollInputEvents` | automation events (`PlayAutomationEvent`), memory-platform `PollInputEvents` |
| SetTargetFPS wait | `IO.sleep` then a busy read of `IO.now` | ends at the scripted `after` |
| Output | `Frame.present` to `Window.frame` | `show(frame)` per frame |

`setup: Core -> Frame -> IO(Core & (Frame & S))` runs after InitWindow
(`SetTargetFPS`, `LoadTexture`, ...). `limit` stops after that many presented
frames (0: until `WindowShouldClose`); `Desktop.frames_arg(args)` reads a
`--frames N` argument for it. `libm` is the profile of mouse gestures'
`atan2f` (and examples pass their own profile for `sinf`/`cosf`). `~` marks
comptime arguments: `program` and `libm` must be closed expressions such as
`~Ex.program(M.AppleLibm{})`. At exit the driver prints
`Jonlib: N frames in T ms (F FPS); per frame: render R ms, present P ms, wait W ms`,
or the reason it stopped when a step leaves the reproduced domain (a refused
draw, a clock or event a `Core` step answers `None` for): it never presents
an undefined frame.

### One frame

`Desktop.run` builds a Base `App` whose state holds the `Core`, the `Frame`,
the user state, the start time and statistics:

1. **view**: `Frame.present` turns the frame drawn last into an `Image`;
   `App.run` presents it with `Window.frame`, which answers the events pumped
   since the previous frame (SwapScreenBuffer, then glfwPollEvents' input).
2. **tick** (EndDrawing after the swap): `now` = `IO.now`;
   `Core.frame_wait(core, now)`; when it is positive the driver sleeps its
   whole milliseconds less one with `IO.sleep`, then reads `IO.now` until it
   reaches `now + wait` (raylib's `SUPPORT_PARTIALBUSY_WAIT_LOOP` sleeps 95%
   and busy-waits); then `Core.end_drawing_desktop(libm, core, now, after,
   events)`: recording and frame timing as `Core.end_drawing`, then desktop
   `PollInputEvents` with the callbacks of the Base events, the F12 check and
   the frame counter.
3. Unless `WindowShouldClose` (or the limit): `update`, `IO.now`,
   `Core.begin_drawing` and `Frame.begin_drawing`, `draw`,
   `Frame.end_drawing`; a frame with a refused draw ends the loop.

The clock is `Desktop.seconds(ms)`: whole seconds plus the correctly rounded
remaining milliseconds over 1000, one binary64 rounding in the sum (monotone;
the binary64 division helper only takes quotients below 2). Milliseconds
below 2^31 (24 days) are supported.

### Desktop polling

`Core.end_drawing_desktop` follows `rcore_desktop_glfw.c`'s
`PollInputEvents`, which differs from the memory platform's (verified by
laws in `LAWS.bend`; there is no GLFW reference build in the gates):
`UpdateGestures`, both queues emptied, the last gamepad button cleared,
previous key states copied for **all 512 keys** and repeats cleared, previous
mouse buttons, wheel and position registered and the wheel move reset,
previous touch states copied and touch point 0 moved to the mouse position,
no gamepad ready (Base has none), then the callbacks, and the close request
read and reset: `WindowShouldClose` is true for the frame after the window's
close button or the exit key only.

### Event table

Base reports events as `Key{code, down}`, `Mouse{x, y, button, down}`,
`Move{x, y}` and `Close{}` (`effs/window_open.c`, `effs/window_frame.c`). Key
codes are the lower-case character of the key (`charactersIgnoringModifiers`
on macOS, `XLookupString` with Shift and Lock on X11), the Mac's private-use
function-key characters, or 65536 plus the Mac key code for modifiers (X11
maps its keysyms to the same codes). `Desktop.key(code)` gives the raylib
`KeyboardKey`:

| Base code | raylib key |
|---|---|
| `a`..`z` (97..122) | `KEY_A`..`KEY_Z` (65..90) |
| `0`..`9` (48..57), space, `'` `,` `-` `.` `/` `;` `=` `[` `\` `]` `` ` `` | the same code |
| `!` `@` `#` `$` `%` `^` `&` `*` `(` `)` | `KEY_ONE`..`KEY_NINE`, `KEY_ZERO` (US layout) |
| `_` `+` `{` `}` `\|` `:` `"` `<` `>` `?` `~` | `KEY_MINUS`, `KEY_EQUAL`, `KEY_LEFT_BRACKET`, `KEY_RIGHT_BRACKET`, `KEY_BACKSLASH`, `KEY_SEMICOLON`, `KEY_APOSTROPHE`, `KEY_COMMA`, `KEY_PERIOD`, `KEY_SLASH`, `KEY_GRAVE` |
| 27 | `KEY_ESCAPE` (256) |
| 13 | `KEY_ENTER` (257) |
| 3 (Mac keypad Enter) | `KEY_KP_ENTER` (335) |
| 9, 25 (Shift+Tab on macOS) | `KEY_TAB` (258) |
| 127, 8 | `KEY_BACKSPACE` (259) |
| 63232, 63233, 63234, 63235 | `KEY_UP`, `KEY_DOWN`, `KEY_LEFT`, `KEY_RIGHT` |
| 63236..63260 (F1..F25) | 290..314 (`KEY_F1`..`KEY_F12`, then GLFW's F13..F25) |
| 63271, 63272 | `KEY_INSERT`, `KEY_DELETE` |
| 63273, 63275, 63276, 63277 | `KEY_HOME`, `KEY_END`, `KEY_PAGE_UP`, `KEY_PAGE_DOWN` |
| 63278, 63279, 63280, 63285 | `KEY_PRINT_SCREEN`, `KEY_SCROLL_LOCK`, `KEY_PAUSE`, `KEY_KB_MENU` |
| 63289 (keypad Clear) | `KEY_NUM_LOCK` (as GLFW maps it on macOS) |
| 65536 + 54, 55 | `KEY_RIGHT_SUPER`, `KEY_LEFT_SUPER` |
| 65536 + 56, 60 | `KEY_LEFT_SHIFT`, `KEY_RIGHT_SHIFT` |
| 65536 + 57 | `KEY_CAPS_LOCK` |
| 65536 + 58, 61 | `KEY_LEFT_ALT`, `KEY_RIGHT_ALT` |
| 65536 + 59, 62 | `KEY_LEFT_CONTROL`, `KEY_RIGHT_CONTROL` |
| anything else | none: the event is dropped |

A key's down event is GLFW_PRESS, or GLFW_REPEAT when the key is already
down (Base repeats a held key's down event as the OS does); up is
GLFW_RELEASE. The key callback runs with mods 0. Mouse buttons 0..7 keep their
number (left 0, right 1, middle 2, then `MOUSE_BUTTON_SIDE`...; X11 reports 0..2
only); a button event first runs the cursor position callback when its
position differs from the current one, then the button callback (with its
mouse gesture, `SUPPORT_MOUSE_GESTURES`); `Move` is the cursor position
callback (with a `TOUCH_ACTION_MOVE` gesture); `Close` is the window's close
button.

**Key mapping gaps** (Base reports characters, not physical keys): the keypad
digits and operators arrive as the main-row characters (`KEY_KP_0`..`KEY_KP_9`,
`KEY_KP_DECIMAL`, `_DIVIDE`, `_MULTIPLY`, `_SUBTRACT`, `_ADD`, `_EQUAL` never
occur; keypad `*` is `KEY_EIGHT`); shifted symbols follow the US layout and
other layouts' characters (é, ß, ...) are dropped; on X11 keypad Enter is
`KEY_ENTER`, other keys without a character or table entry (Print, Pause,
Scroll Lock, Menu, F13+, keypad navigation) arrive as 65536 + an X key code and
are dropped; the Mac's Fn key and Help key have no raylib key. Caps Lock on
macOS reports down when the lock turns on and up when it turns off (as GLFW on
macOS); without modifier flags the CAPS/NUM lock rule of the key callback
never applies. X11 auto-repeat arrives as release/press pairs (GLFW uses
detectable auto-repeat), so a held key is pressed again on each repeat there.

## Presentation

`Frame.present(frame) -> Frame & Maybe<Image>` (SwapScreenBuffer) builds
Base's quadtree from the color buffer: depth k with 2^k >= width and height,
`Qua{tl, tr, bl, br}`, colors `0x00RRGGBB` (alpha ignored, as both Base
backends ignore it), squares past the right or bottom edge `Pix{0}`, and a quad
of four equal `Pix` collapsed into one. Level 1 is read straight from rlsw's
bottom-up buffer with one `Array.get` per pixel (rows paired bottom-up so the
grid comes out top-down); higher levels pair rows of images. `Frame.scan` gives
the buffer's words in storage order; `Frame.is_defined` whether every draw was
reproduced; `Frame.refuse` (Jonlib-specific) marks a frame undefined, for a
program whose own computation leaves the reproduced domain.

Measured on an Apple M1 (8 cores, macOS arm64, October 2026, other jobs on
the machine), the `core_basic_window` frame (800x450, clear and a 20-pixel
text line) costs about 1 ms to draw and 2 ms to present on CPU-1 (the
presented tree has 3441 nodes). Two earlier designs were measured and
dropped: a list of the words and rows of `Pix` paired level by level (20 ms
per frame), and the same with rows of words (15 ms).

`Frame` and `Core` are boxed (a never-used recursive `spare` field), so the
compiler passes them as one pointer: flattened, a `Core` (92 words) and a
`Frame` (94 words) held by the driver's closures made the generated work-loop
segments 205 words wide, which Apple clang 21 failed to compile
([VERIFICATION.md](VERIFICATION.md#known-toolchain-defects)); boxed, the bank
is 102 words.

## Examples

| Example | raylib source | Notes |
|---|---|---|
| [`core_basic_window`](../examples/core_basic_window.bend) | `examples/core/core_basic_window.c` | |
| [`core_input_keys`](../examples/core_input_keys.bend) | `examples/core/core_input_keys.c` | |
| [`core_input_mouse`](../examples/core_input_mouse.bend) | `examples/core/core_input_mouse.c` | `H` changes `IsCursorHidden`; Base cannot hide the OS cursor |
| [`core_2d_camera`](../examples/core_2d_camera.bend) | `examples/core/core_2d_camera.c` | seed as a setup argument (raylib seeds from `time(NULL)`); zoom only at 1 without wheel moves (no `expf`/`logf` profile; Base has no wheel); the interactive run uses the glibc 2.39 `sinf`/`cosf` profile, since the Apple one refuses rotations of 13, 19 and 22 degrees |
| [`shapes_logo_raylib`](../examples/shapes_logo_raylib.bend) | `examples/shapes/shapes_logo_raylib.c` | |
| [`textures_logo_raylib`](../examples/textures_logo_raylib.bend) | `examples/textures/textures_logo_raylib.c` | reads `raylib_logo.png` in place (run from raylib's `examples/textures`, or `--logo <path>`) |
| [`shapes_basic_shapes`](../examples/shapes_basic_shapes.bend) | `examples/shapes/shapes_basic_shapes.c` | refused: its hexagons turn by 0.2 degrees, so `DrawPoly*` evaluate `sinf`/`cosf` outside every verified profile (Apple: whole degrees; glibc: the closing vertex passes 6.283186); the interactive run stops at the first frame |

Build and run one (a native binary; Base windows need a desktop session):

```sh
bun "$BEND_SOURCE/bend2/main.ts" examples/core_input_keys.bend -o core_input_keys
./core_input_keys                       # until the window closes or Escape
./core_input_keys --threads 1 --frames 120
```

## Verification

| Gate | Tool | Compares |
|---|---|---|
| `examples` | `tools/examples_probe.py` | 12 scripts of the 7 examples (71 frames: 63 compared, 8 refusal contracts) against the **unmodified** raylib example sources on the clock-injected memory-platform raylib, every framebuffer byte and the presented quadtree, on CPU-1, CPU-2 and JavaScript |

```sh
python3 tools/examples_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --jobs 2
```

The reference compiles each pinned example `.c` file with
`-include tools/reference/example_driver.h`, which renames `InitWindow`,
`WindowShouldClose`, `BeginDrawing` and `EndDrawing` in that translation unit
to the probe's hooks; the hooks play the script's automation events before
each `WindowShouldClose`, set the scripted clocks (as
`tools/reference/input_clock.h` does for the input probe, whose raylib build
it shares), fix the random seed after InitWindow and print the color buffer
after each `EndDrawing`. No example or raylib source is changed. Scripts press
and release the examples' keys and buttons, move the mouse (also off
screen), toggle the cursor flag, close the window mid-script with
`WINDOW_CLOSE`, use two seeds, and alternate frames shorter than the 60 FPS
target (EndDrawing waits) with longer ones. Contracts: a wheel move in
`core_2d_camera` (refused from that frame on), a rotation to 13 degrees
(refused under the Apple profile, compared under glibc), and
`shapes_basic_shapes` (every frame refused).

`LAWS.bend` states the desktop parts the gate cannot reach: polling copies all
512 previous key states, a held mouse button is pressed for one frame, the
wheel move resets, and the key table's letters, Escape, arrows, function
keys, Shift, a shifted symbol and an unknown code.

### Interactive runs

`python3 tools/examples_probe.py ... --interactive 180` builds each example
and runs it in a Base window for 180 frames with `--gpu off` (the Bend program
on the CPU; Base presents through Metal) on one and two threads, recording the
driver's summary (diagnostic, not a gate: it needs a desktop session). Apple
M1, macOS arm64, October 2026, other jobs running on the machine; each window
opened, presented and closed:

| Example | CPU-1 FPS | CPU-2 FPS | per frame (CPU-1): render / present / wait |
|---|---|---|---|
| `core_basic_window` | 50.5 | 54.7 | 1 / 6 / 10 ms |
| `core_input_keys` | 53.6 | 54.6 | 3 / 5 / 9 ms |
| `core_input_mouse` | 54.8 | 54.7 | 5 / 4 / 8 ms |
| `core_2d_camera` | 36.9 | 33.1 | 20 / 6 / 0 ms |
| `shapes_logo_raylib` | 54.4 | 55.0 | 6 / 5 / 7 ms |
| `textures_logo_raylib` | 55.0 | 55.1 | 4 / 5 / 8 ms |
| `shapes_basic_shapes` | stops at frame 1 | stops at frame 1 | its first frame is refused |

Every example but `core_2d_camera` keeps up with `SetTargetFPS(60)` and waits
the rest of the frame; the 3 to 5 FPS short of 60 come from the millisecond
clock (a wait ends at the first whole millisecond past its destination) and
Base's display-synced presentation. `core_2d_camera` (100 buildings, the
ground and two lines through `BeginMode2D`, plus the overlay) renders in about
20 ms and runs at 33 to 37 FPS. "present" is the `Image` conversion plus
`Window.frame`. A second thread gains nothing: the renderer and the
conversion are sequential.

## Gaps

Window functions Base has no facility for stay `not-started` (runtime
workstream, [MASTER-PLAN.md](MASTER-PLAN.md#compiler-and-runtime-workstream)):
`SetWindowTitle` after the window opens (Base has `Window.set_title`, the
driver does not hand programs the window yet), window state and flags
(`SetConfigFlags`, fullscreen, borderless, maximize/minimize/restore,
resizable, `IsWindowResized/Focused/Hidden/Minimized/Maximized`), position,
size limits, opacity, icons, monitors, DPI (`GetWindowScaleDPI`), clipboard,
`OpenURL`, cursor shape and visibility (`SetMouseCursor`; `HideCursor`,
`DisableCursor` only set the flags), event waiting, vsync control, and a
window handle. Input without Base events: the mouse wheel, text input
(`GetCharPressed` stays empty on the desktop), cursor enter/leave
(`IsCursorOnScreen` stays false), gamepads, touch, window resize/focus
events; mouse positions are clipped to the window by Base (GLFW reports
positions outside while dragging). Timing: `IO.now` has millisecond
resolution (raylib's `GetTime` is sub-millisecond) and `Window.frame` waits for
the display on macOS (Base enables display sync), so frame rates do not
reach raylib's pacing exactly; there is no `WaitTime`/`GetTime` function apart
from the driver's clock. The JavaScript lane has no window (`Window.open`
fails there); the headless replay runs on it. Linux (X11) presentation was
not run here; only macOS was exercised interactively.
