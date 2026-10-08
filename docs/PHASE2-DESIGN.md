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
  the vertex generation in `rshapes.c`/`rtextures.c`, `rlgl`'s OpenGL 1.1
  immediate path (software mode has no render batch: each primitive is
  transformed and rasterized when its last vertex arrives, see the appendix)
  and `rlsw`'s clipping, rasterization, sampling and blending. Results compare
  byte for byte with the framebuffer the harness reads back.
- `rlsw`'s SSE/AVX/NEON paths, including FMA, are opt-in
  (`RLSW_USE_SIMD_INTRINSICS`, off by default, which also selects its
  uint8-to-float lookup table). The reference build keeps them off and
  compiles with contraction off, so the declared profile is scalar `rlsw`,
  uncontracted F32, as for Jonmath. A SIMD profile is a later, separate
  contract.
- `rlsw.h` is MIT-licensed (Le Juez Victor, vendored by raylib); adapted
  functions get the usual "altered" marking and its notice
  ([LICENSES/rlsw.txt](../LICENSES/rlsw.txt)). Slice 1 is implemented and
  measured in [FRAME.md](FRAME.md), slices 2 and 3 in
  [TEXTURES.md](TEXTURES.md).

**Input: automation events.** The memory platform has no input system, but
`SUPPORT_AUTOMATION_EVENTS` (on by default) lets a native harness inject
`INPUT_KEY_DOWN/UP`, mouse button/position/wheel, gamepad, touch, gesture and
window events with `PlayAutomationEvent` between frames. The harness replays
an event script frame by frame and records `IsKeyPressed`, `GetKeyPressed`,
mouse/wheel/touch/gesture queries after each `EndDrawing`; Jonlib replays the
same script through its pure state machine and must give the same answers.
There is no character event, so `GetCharPressed`'s queue is specified from
`rcore.c` and checked by Jonlib's own replay tests, not by injection.
Slice 4 is implemented in [INPUT.md](INPUT.md); its probe injects the clock
into the pinned build with an include-only shim, as `GetTime` cannot be
controlled otherwise.

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
  framebuffer `Surface`, the immediate-mode primitive under construction
  (current color, texcoord, bound texture), the matrix stack, scissor, blend
  mode, culling, active render texture and 2D camera mode.
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

## Appendix: the reference pipeline (pinned rlsw, scalar)

Traced from the pinned sources (`src/rlgl.h`, `src/external/rlsw.h`,
`src/rshapes.c`, `src/rcore.c`, `src/platforms/rcore_memory.c`); slice 1 turns
each point into a probe case before relying on it.

- **No batch.** With `GRAPHICS_API_OPENGL_SOFTWARE`, rlgl takes its GL 1.1
  path: `rlBegin`/`rlVertex*`/`rlColor*` call `swBegin`/`swVertex*`/`swColor*`
  directly and `rlDrawRenderBatch*`/`rlCheckRenderBatchLimit` do nothing.
  Draw order is call order; `ClearBackground` clears immediately.
- **Shapes are textured from the default font.** `InitWindow` points
  `SetShapesTexture` at a 2x8 opaque-white block of the default font atlas
  (128x128 gray-alpha, nearest, repeat). Because that texture has alpha, every
  textured shape (pixels, rectangles, circles, triangles) goes through
  blending; `DrawLine` is untextured and opaque lines write directly.
- **State.** `rlOrtho(0, W, H, 0, 0, 1)`, identity modelview (no half-pixel
  offset), blending `SRC_ALPHA, ONE_MINUS_SRC_ALPHA` (fixed: `rlSetBlendMode`
  is GL3-only), back-face culling on (clockwise and zero-area triangles are
  dropped), depth test off.
- **Transform.** Clip x = 2/W*x - 1, y = 2/(-H)*y + 1; screen
  X = (W/2 + ndc*W/2) + 0.5, Y likewise; the framebuffer is bottom-up.
  Sutherland-Hodgman clipping with strict x/y planes.
- **Quads.** A 4-vertex quad whose edges are all within 0.5 px of the axes is
  filled by a box rasterizer (pixel centers x in (x0, x1], y in [y0, y1),
  colors interpolated from three corners only, so a gradient rectangle's
  top-right color has no effect); other quads become a triangle fan.
- **Triangles.** Scanline DDA with per-row float accumulation of edge
  gradients, spans covering (xl, xr], colors/UVs recomputed every 16 pixels.
- **Lines.** Liang-Barsky clipping, then `sw_clamp` (which returns `int`)
  truncates endpoints and a DDA covers [min, max) on the major axis: output row
  0 and column W-1 are never drawn, and vertical lines land one column left.
- **Writes.** Colors are floats (`c * 1/255` through a LUT), blending is in
  float, and stores truncate `(uint8_t)(v*255)` (0x80 alpha over 0xff gives
  126, where a GPU gives 127).
- **Readback.** `SwapScreenBuffer`'s copy is top-down **BGRA**
  (`SW_FRAMEBUFFER_OUTPUT_BGRA`); `LoadImageFromScreen` flips it again (so it
  is bottom-up) and forces alpha 255. **(open)** Jonlib's
  `LoadImageFromScreen` should follow raylib's desktop contract (top-down
  RGBA); the harness normalizes the memory platform's output for comparison.
- **Slices 2 and 3** (checked in [TEXTURES.md](TEXTURES.md)): blend modes
  and texture wrap modes never reach rlsw (`rlSetBlendMode` is GL3-only, and
  raylib's CLAMP is `GL_CLAMP_TO_EDGE`, which `swTexParameteri` rejects), so
  every texture repeats; `GenTextureMipmaps` is a no-op and
  `LoadImageFromTexture` returns zero bytes (`glGetTexImage` is a no-op);
  matrices live in rlsw's stacks; the scissor's clip-space bounds are those
  of the viewport current when it was set.
- **Host dependence.** SIMD is opt-in and off. Clang's default contraction
  can fuse projection, interpolation and blend arithmetic on arm64, and
  circles/rotations use `sinf`/`cosf`: the reference build compiles raylib
  with `-ffp-contract=off`, and trig-dependent shapes take an `M.Libm` profile.
