# Headless frame and shapes

Phase 2, delivery slice 1 ([PHASE2-DESIGN.md](PHASE2-DESIGN.md)): a `Frame`
owns a raylib screen's color buffer, and the `Draw.*` functions render
`rshapes.c` shapes into it exactly as pinned raylib 6.0 renders them on its
memory platform. Altered Bend adaptations of `rcore.c`, `rlgl.h` and
`rshapes.c` (zlib, [LICENSES/raylib.txt](../LICENSES/raylib.txt)) and of
`src/external/rlsw.h` 1.5 (Copyright (c) 2025-2026 Le Juez Victor, MIT,
[LICENSES/rlsw.txt](../LICENSES/rlsw.txt)); the default font bitmap comes from
`rtext.c`. Code: the public section "Frame and shapes" of `jonlib.bend`,
`src/frame.bend` (rlgl immediate path and rlsw rasterization),
`src/shapes.bend` (rshapes.c vertex streams) and `src/frame_font.bend`
(`defaultFontData`).

## Reference and profile

The reference is `PLATFORM=Memory` (`src/platforms/rcore_memory.c`): rlgl's
OpenGL 1.1 path drives `rlsw.h`, a CPU rasterizer, and `SwapScreenBuffer`
copies its color buffer. GPU OpenGL output is not a reference.

- **Scalar rlsw.** `RLSW_USE_SIMD_INTRINSICS` is off by default, which also
  selects rlsw's uint8-to-float lookup table (`i*SW_INV_255`).
- **Uncontracted F32.** Clang's default contraction fuses multiply-adds in
  rlsw and rshapes on arm64. The probe builds its own raylib variant with
  `CMAKE_C_FLAGS=-ffp-contract=off` (probekit's `raylib_options`, cached as a
  separate build) and checks that its objects contain no fused
  multiply-add instruction (`otool -tv`/`objdump -d`). Jonlib's renderer
  therefore has a single, uncontracted profile and takes no `M.Contraction`
  argument; a contracted or SIMD reference would be a separate contract.
- **libm.** Shapes evaluating `sinf`/`cosf` take an `M.Libm` profile
  (`_for` functions; the convenience names use `M.AppleLibm{}`, as elsewhere).
  An argument is reproduced only inside the profile's verified set:
  - `M.AppleLibm{}`: `fl(DEG2RAD*d)` for integral `d` with `|d| <= 360`, except
    `|d|` in {13, 19, 22, 103, 188}, where macOS arm64 `sinf`/`cosf` are not
    correctly rounded (Jonmath's Apple sine/cosine rounds the exact value).
    The probe re-checks all 711 accepted arguments against the host.
    `DEG2RAD` is `PI/180.0f` in F32. Circles, ellipses and the circle outline
    use multiples of 10 degrees, so they always qualify; rotations, sectors,
    rings and polygons qualify when their F32 angle sums land on these values.
  - `M.Glibc239Libm{}`/`M.Glibc241Libm{}`: normal or zero arguments with
    `|x| <= 6.283186f` ([ROTATION.md](ROTATION.md)). On macOS the frame probe
    exercises the Apple profile only; the glibc sine/cosine rests on the
    Arm-model checks of the `trig-rotation` gate.

## State and API

`Frame.init_window(width, height) -> Maybe<Frame>` is `InitWindow` on the
memory platform for sizes 1..4096: `rlglInit` clears to (0, 0, 0, 255),
`SetupViewport` sets `rlOrtho(0, width, height, 0, 0, 1)` and an identity
modelview, and the shapes texture is the default font atlas with the
rectangle `(41, 46, 2, 8)` (glyph 95 inset by one pixel). The title and the
window/platform/timing state are not modeled.

| raylib | Jonlib |
|---|---|
| `InitWindow` | `Frame.init_window(width, height) -> Maybe<Frame>` |
| `CloseWindow` | `Frame.close_window(frame) -> Unit` |
| `BeginDrawing` | `Frame.begin_drawing(frame) -> Frame` (identity modelview) |
| `EndDrawing` | `Frame.end_drawing(frame) -> Frame` (no batch to flush) |
| `ClearBackground` | `Frame.clear_background(frame, color) -> Frame` |
| `LoadImageFromScreen` | `Frame.load_image_from_screen(frame) -> Frame & Maybe<Surface>` |
| (color buffer) | `Frame.framebuffer(frame) -> Frame & Maybe<Surface>`; `Frame.dimensions(frame)` |
| `DrawPixel` / `DrawPixelV` | `Draw.pixel(frame, x, y, color)` / `Draw.pixel_v(frame, position, color)` |
| `DrawLine` / `DrawLineV` / `DrawLineEx` / `DrawLineStrip` | `Draw.line`, `Draw.line_v`, `Draw.line_ex`, `Draw.line_strip` |
| `DrawRectangle` / `V` / `Rec` / `Pro` | `Draw.rectangle`, `Draw.rectangle_v`, `Draw.rectangle_rec`, `Draw.rectangle_pro_for(libm, ...)` |
| `DrawRectangleGradientV` / `H` / `Ex` | `Draw.rectangle_gradient_v`, `_h`, `_ex` |
| `DrawRectangleLines` / `LinesEx` | `Draw.rectangle_lines`, `Draw.rectangle_lines_ex` |
| `DrawTriangle` / `Lines` / `Fan` / `Strip` | `Draw.triangle`, `Draw.triangle_lines`, `Draw.triangle_fan`, `Draw.triangle_strip` |
| `DrawCircle` / `V` / `Lines` / `LinesV` / `Gradient` | `Draw.circle_for`, `circle_v_for`, `circle_lines_for`, `circle_lines_v_for`, `circle_gradient_for` |
| `DrawCircleSector` / `SectorLines` | `Draw.circle_sector_for`, `Draw.circle_sector_lines_for` |
| `DrawEllipse` / `V` / `Lines` / `LinesV` | `Draw.ellipse_for`, `ellipse_v_for`, `ellipse_lines_for`, `ellipse_lines_v_for` |
| `DrawRing` | `Draw.ring_for` |
| `DrawPoly` / `DrawPolyLines` | `Draw.poly_for`, `Draw.poly_lines_for` |

Every `_for` function also has a convenience form without `_for` and the
profile. Colors are `0xRRGGBBAA` words, points `M.Vector2`, rectangles
`J.Rectangle`. Parameters that are C `int`s (positions and sizes of
`DrawPixel`, `DrawLine`, `DrawRectangle`, the gradients V/H,
`DrawRectangleLines`, the centers of `DrawCircle`, `DrawCircleLines`,
`DrawEllipse` and `DrawEllipseLines`, segment and side counts) are F32
values converted as C converts them (truncation toward zero).

The frame state is explicit, as the design note's state model asks: the
color buffer, the MVP matrix and the immediate-mode state (current color and
texture coordinate, the pending primitive, whether the shapes texture is
bound, and rlsw's per-primitive alpha flag). Drawing never fails; instead a
draw Jonlib does not reproduce marks the frame undefined, and both readbacks
return `None` from then on (the frame is still returned and owned):

- undefined behavior in the reference: a C `int` parameter that is NaN or
  beyond `[-2^31, 2^31)`, a float-to-int conversion of NaN inside rlsw (for
  example a line endpoint that is NaN, or infinite, which Liang-Barsky turns
  into `v0 + 0*inf`), and a `(uint8_t)(c*255.0f)` store of a channel outside
  `(-1, 256)` (a gradient whose three box corners extrapolate past 0 or 1);
- an unverified `sinf`/`cosf` argument for the profile;
- a circle sector or ring with fewer segments than `ceil((end - start)/90)`
  (rshapes.c then estimates a count with `acosf`/`powf`), or more than 4096
  segments or polygon sides (a loop bound of this profile);
- conservatively, rasterizer integers beyond `2^24` and rows or columns
  outside the color buffer. Clipping keeps every primitive inside the
  viewport, so these only arise from clipping round-off with huge inputs
  (where rlsw would write out of bounds or wrap rows).

## The rendering path

Each shape is the `rlBegin`/`rlColor4ub`/`rlTexCoord2f`/`rlVertex2f`/`rlEnd`
stream `rshapes.c` issues (`SUPPORT_QUADS_DRAW_MODE`), with its F32 vertex
arithmetic in source order, interpreted as rlgl's software path does:

- **No batch.** rlgl calls rlsw directly; a primitive renders when its last
  vertex arrives (two for lines, three for triangles, four for quads), so
  draw order is call order and `ClearBackground` clears at once.
- **Blending.** `SRC_ALPHA, ONE_MINUS_SRC_ALPHA` in float on the destination
  expanded through the LUT, stored by truncation: black at alpha 0x80 over a
  0xff channel stores 126 (126.99999...) where rounding would give 127, and
  white at alpha 0x80 over opaque black stores (128, 128, 128, 191). Textured
  shapes always blend (the atlas has transparent texels);
  untextured ones (lines, `DrawTriangleStrip`, `DrawEllipse`,
  `DrawCircleGradient`) blend only when a color with alpha below 255 was set
  since the previous primitive. rlsw clears that flag after each primitive,
  so the second and later segments of a single-color translucent line strip,
  triangle strip or circle outline are stored without blending, alpha
  included.
- **Transform and culling.** Clip coordinates come from the ortho MVP;
  triangles and quads with a non-positive `(x, y, w)` determinant of their
  first three vertices are dropped (clockwise and degenerate shapes, and
  NaN geometry).
- **Clipping.** Sutherland-Hodgman against `w >= 1e-4`, strict `x`/`y` and
  inclusive `z` planes, then division by w and the viewport map
  `center + ndc*half + 0.5`; the color buffer is bottom-up.
- **Quads.** A clipped quad with four vertices, `w == 1` and every edge within
  0.5 px of an axis is filled by the box rasterizer: corners classified by
  `x + y` and `x - y`, pixel centers in `(x0, x1] x [y0, y1)`, color and
  texture coordinates interpolated from the screen bottom-left (base),
  bottom-right and top-left corners only. The top-right color of
  `DrawRectangleGradientEx` therefore has no effect, and inconsistent corners
  extrapolate. Other quads are triangle fans.
- **Triangles.** Scanlines between edge accumulators stepped per row with a
  `1 - fract(y)` substep, spans over `(x_left, x_right]` in 16-pixel blocks
  whose ends are perspective corrected.
- **Lines.** Liang-Barsky clipping, projection, `sw_clamp` to integers (which
  truncates the endpoints), then a DDA from the pixel centers: row 0 and
  column W-1 are never drawn and vertical lines land one column left.
- **Texture.** Nearest sampling with REPEAT of the 128x128 gray-alpha atlas
  (`texcoord - floor(texcoord)`, then `(int)(u*128)`); the gray channel is
  always 255.

## Readback

`Frame.framebuffer` returns the color buffer top-down as an R8G8B8A8
`Surface` with the stored alpha: the bytes `rlCopyFramebuffer` (and so
`SwapScreenBuffer`) delivers, whose memory-platform order is BGRA
(`SW_FRAMEBUFFER_OUTPUT_BGRA`). `Frame.load_image_from_screen` follows
raylib's desktop `LoadImageFromScreen` contract: the same image with alpha
forced to 255 (`rlReadScreenPixels`). On the memory platform raylib's own
`LoadImageFromScreen` returns those bytes bottom-up with red and blue
swapped; the probe normalizes them before comparing.

## Verification

| Gate | Tool | Compares |
|---|---|---|
| `frame` | `tools/frame_probe.py` | 95 scenes (1348 operations, sizes 1x1 to 64x48, 24 random scenes) byte for byte against the uncontracted memory-platform raylib on CPU-1, CPU-2 and JavaScript; 17 contract scenes must be refused; every accepted Apple `sinf`/`cosf` argument against the host |

```sh
python3 tools/frame_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --jobs 3
```

The probe also verifies that the reference objects contain no fused
multiply-add and that `src/frame_font.bend` equals the pinned
`defaultFontData`. Scenes cover integer and fractional coordinates, shapes
partially and entirely off-screen, zero, negative and degenerate sizes,
clockwise and counter-clockwise triangles, translucent colors over opaque and
translucent backgrounds, overlapping draws, long spans, every line octant,
nonfinite and huge geometry, and draws outside `BeginDrawing`.

## Performance

`python3 tools/frame_probe.py ... --benchmark` renders a 640x480 frame
(clear plus 100 rectangles and circles, some translucent) and checks that its
checksum equals the native frame. Best of three runs on an Apple M1 (8 cores,
macOS arm64), October 2026, with other jobs running on the machine:

| Lane | Wall time | Frame alone (create + read) | Rendering |
|---|---|---|---|
| native rlsw (`-O2`, uncontracted, in-process timer) | 4.0 ms | - | 4.0 ms |
| Jonlib CPU-1 | 97.4 ms | 4.9 ms | about 92 ms |
| Jonlib CPU-2 | 96.5 ms | 4.8 ms | about 92 ms |
| Jonlib JavaScript | 4580 ms | 62 ms | about 4.5 s |

The Bend renderer is about 23 times slower than rlsw and single-threaded
(two CPU threads gain nothing): every pixel is an `Array` read and write on a
balanced tree of depth 19, and the rasterizers are sequential recursions.
That is about 10 frames per second for this scene, short of interactive rates
for the Phase 2 examples. The levers named by the design note remain: rows
or tiles rendered in parallel (balanced fork-join over independent row
ranges), a flat row-major store per tile, and the Metal lane; none is
assumed before it is measured.

## Gaps

- Not ported yet: `DrawCircleSector`/`DrawRing` segment estimation
  (`acosf`/`powf`), `DrawRingLines`, `DrawPolyLinesEx`, `DrawLineBezier`,
  `DrawLineDashed`, rounded rectangles, splines, `DrawRectangle*` with
  textures, cameras, render textures, scissor and blend modes
  (slice 2), `SetShapesTexture` and line widths.
- `M.Libm` arguments outside the verified sets above are refused rather than
  approximated; the glibc profiles are not exercised by this probe on macOS.
- Interactive presentation, input and timing belong to later slices.
