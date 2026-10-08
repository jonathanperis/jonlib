# Phase 2 design: interactive 2D

Status: design note, written before any Phase 2 code (decision recorded in
[MASTER-PLAN.md](MASTER-PLAN.md)). It fixes the reference strategy, the state
model and the delivery order for `rcore` windowing, input and timing, the
`rshapes`/`rtextures` drawing paths, `Camera2D` modes and render targets.
Everything here is revisable on review; the decisions marked **(open)** need
Jonathan's call before the slice that depends on them.

## Exit gate (from the master plan)

Deterministic input replay plus real desktop integration; representative
raylib 2D examples work.

## 1. References

**Drawing: raylib's memory platform with its software renderer.** Pinned
raylib 6.0 ships `PLATFORM=Memory` (`src/platforms/rcore_memory.c`), which
renders every draw call through `rlgl` into `src/external/rlsw.h`, a CPU
rasterizer, and copies the result to a memory framebuffer in
`SwapScreenBuffer`. The probes already build that platform. GPU (OpenGL)
output is not a reference: rasterization and blending vary by driver.

- Jonlib's renderer is a Bend port of the path a draw call takes there:
  the vertex generation in `rshapes.c`/`rtextures.c`, `rlgl`'s immediate-mode
  batch (matrix stack, texture/mode switches, `rlCheckRenderBatchLimit`
  flushes) and `rlsw`'s rasterization, sampling and blending. Results compare
  byte for byte with the framebuffer (`rlCopyFramebuffer`) or
  `LoadImageFromScreen`.
- `rlsw`'s SSE/AVX/NEON paths, including FMA, are opt-in
  (`RLSW_USE_SIMD_INTRINSICS`, off by default, which also selects its
  uint8-to-float lookup table). The reference build keeps them off and
  compiles with contraction off, so the declared profile is scalar `rlsw`,
  uncontracted F32, as for Jonmath. A SIMD profile is a later, separate
  contract.
- `rlsw` is zlib-licensed raylib code; adapted functions get the usual
  "altered" marking and raylib notice.

**Input: automation events.** The memory platform has no input system, but
`SUPPORT_AUTOMATION_EVENTS` (on by default) lets a native harness inject
`INPUT_KEY_DOWN/UP`, mouse button/position/wheel, gamepad, touch, gesture and
window events with `PlayAutomationEvent` between frames. The harness replays
an event script frame by frame and records `IsKeyPressed`, `GetKeyPressed`,
mouse/wheel/touch/gesture queries after each `EndDrawing`; Jonlib replays the
same script through its pure state machine and must give the same answers.
There is no character event, so `GetCharPressed`'s queue is specified from
`rcore.c` and checked by Jonlib's own replay tests, not by injection.

**Time: an explicit input.** `rcore_memory.c`'s `GetTime` reads
`CLOCK_MONOTONIC` on Linux and Windows' performance counter, and returns 0 on
macOS (no branch). Frame timing (`SetTargetFPS` waits, `GetFrameTime`,
`GetFPS`'s averaging) is therefore modeled with the clock as a parameter: the
harness feeds the same timestamps to both sides. The interactive driver reads
Base's `IO.now()` (milliseconds); raylib's sub-millisecond `GetTime` needs a
finer Base clock (runtime workstream).

## 2. State model

Following the Phase 1 decision on global state (explicit values instead of
raylib's `CORE` and `RLGL` globals), Phase 2 adds one owned value threaded
through a program:

- `Core`: window configuration and flags, screen/render sizes, the input
  state (current and previous key and button arrays, the pressed-key and
  char queues, mouse position/offset/scale and wheel, touch points, gesture
  state from `rgestures.h`), timing (current/previous/target/frame times and
  the FPS history), and the frame counter.
- `Frame`: the render state between `begin_drawing` and `end_drawing`: the
  framebuffer `Surface`, the `rlgl` batch (vertex buffers, draw calls,
  current texture/mode), the matrix stack, scissor, blend mode, active render
  texture and 2D camera mode.
- Functions keep raylib names under their module: for example
  `Core.begin_drawing(core) -> Frame`, `Frame.clear_background(frame, color)`,
  `Draw.rectangle(frame, x, y, w, h, color) -> Frame`,
  `Input.is_key_pressed(core, key) -> Bool`, `Core.end_drawing(frame) -> Core`.
  Functions that only read state take it with `+` (copyable views) where Bend
  allows; mutation is a returned value, never hidden.
- `Texture2D` is an owned `Surface` (or `Image.Stored`) plus raylib's id,
  width, height, mipmaps and format; `RenderTexture2D` holds a color texture
  and a depth buffer; unloading consumes them.

## 3. Interactive driver

- Presentation converts the framebuffer `Surface` to Base's quadtree `Image`
  and calls `Window.frame`, which answers the events pumped since the last
  frame. Base's `App<S>` loop (view/tick) and `App.play` (deterministic event
  replay) fit raylib's `while (!WindowShouldClose())` loop once the `Core` is
  the app state.
- Base events are `Key{code, down}`, `Mouse{x, y, button, down}`, `Move{x, y}`
  and `Close{}`. Key codes are characters or `65536 + keycode` on macOS and
  mapped keysyms on X11; a table maps them to raylib's `KeyboardKey` values,
  and documented gaps remain where a key has no code.
- Missing in Base and therefore runtime-workstream items: mouse wheel, text
  input (characters with repeat and IME), window resize/minimize/focus/DPI
  events, fullscreen and borderless modes, cursor shape/visibility/lock,
  clipboard, monitor queries, gamepads, touch, vsync control and a
  sub-millisecond clock. Until each lands, the matching raylib functions are
  `partial` with that gap, and replay tests still cover their state logic
  through injected events.

## 4. Delivery order

1. **Headless frame and shapes.** `Core`/`Frame`, `ClearBackground`,
   `BeginDrawing`/`EndDrawing`, the `rlgl` batch and `rlsw` triangle/line/point
   rasterization, then `rshapes`: pixels, lines (including thick and strip),
   rectangles (plain, rotated, gradient, rounded, lines), circles, sectors,
   rings, ellipses, triangles (fan/strip), polygons and splines. Compared with
   `rlsw` framebuffers on CPU-1, CPU-2 and JavaScript.
2. **2D camera, render targets and state.** `BeginMode2D` (matrix stack),
   `BeginTextureMode`, `BeginScissorMode`, `BeginBlendMode`, and the
   `GetScreenToWorld2D`/`GetWorldToScreen2D` helpers.
3. **Textures.** `LoadTextureFromImage`, `UpdateTexture`, filters and wrap
   modes as `rlsw` samples them, `DrawTexture*`, `DrawTexturePro`,
   `DrawTextureNPatch`, mipmaps.
4. **Input and timing.** The `CORE.Input` state machine with automation-event
   replay, `rgestures.h` (a pure state machine; its `GetGestureDetected` etc.),
   automation event recording/export, and the timing model.
5. **Desktop integration.** The Base window driver, key mapping and the
   representative examples (`core_basic_window`, `core_input_keys`,
   `core_input_mouse`, `core_2d_camera`, `shapes_basic_shapes`,
   `textures_logo_raylib`), each run headless against the reference
   framebuffer and interactively on macOS and Linux.

Text drawing (`DrawText*`, the default font) is the first Phase 3 slice; it
reuses the texture path and also unblocks the `ImageText*` Phase 1 leftovers.

## 5. Risks and open questions

- **Performance.** A software rasterizer in Bend plus a Surface-to-quadtree
  conversion per frame must reach interactive rates for the examples. Measure
  after slice 1 against `rlsw` on the same scene; the Metal lane and the
  quadtree's parallel structure are the levers. No architecture beyond
  correctness is assumed until measured.
- **rlsw's float arithmetic** (barycentric setup, perspective division,
  color interpolation) must be reproduced in uncontracted F32, including its
  fixed-point and rounding steps; forced-Metal results need the same
  subnormal/contraction care as Jonmath.
- **(open)** Whether the interactive driver should also offer a GPU path
  (Base Metal presentation of batched triangles) with a declared,
  non-bit-exact contract, or stay software-only until Phase 6.
- **(open)** Whether `Core` is passed explicitly everywhere (the current
  decision) or hidden behind an `App` combinator that threads it for user
  code (both can coexist; the combinator is sugar over the explicit API).
