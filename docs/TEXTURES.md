# 2D camera, render state, render textures and textures

Phase 2, delivery slices 2 and 3 ([PHASE2-DESIGN.md](PHASE2-DESIGN.md)), on
top of the headless frame of [FRAME.md](FRAME.md): `BeginMode2D`, rlgl's
matrix stack, scissor and blend modes, render textures, and textures drawn as
pinned raylib 6.0 draws them on its memory platform. Same reference and
profile as slice 1: `rlsw.h` scalar and uncontracted (the probe's raylib build
uses `-ffp-contract=off`), the host `M.Libm` profile for `sinf`/`cosf`.
Altered Bend adaptations of `rcore.c`, `rtextures.c` and `rlgl.h` (zlib,
[LICENSES/raylib.txt](../LICENSES/raylib.txt)) and of `rlsw.h` 1.5 (MIT,
[LICENSES/rlsw.txt](../LICENSES/rlsw.txt)). Code: the "Frame and shapes"
section of `jonlib.bend` (slice 2 and slice 3 parts), `src/frame.bend`
(matrices, scissor, samplers, targets, id pools) and `src/textures.bend`
(the `DrawTexturePro`/`DrawTextureNPatch` vertex streams and rlgl's
translate/rotate/scale matrices).

## What the software renderer does

Traced in the pinned sources and checked by the probe:

- **Blend modes do nothing.** `rlSetBlendMode` is compiled only for OpenGL 3.3
  and ES2; under `GRAPHICS_API_OPENGL_SOFTWARE` (which defines OpenGL 1.1) it
  is empty, so every `BeginBlendMode` keeps rlglInit's
  `SRC_ALPHA, ONE_MINUS_SRC_ALPHA`. rlsw implements all 121 factor pairs, but
  nothing in raylib reaches them.
- **Wrap modes do nothing.** `SetTextureWrap(CLAMP)` passes
  `RL_TEXTURE_WRAP_CLAMP` (`GL_CLAMP_TO_EDGE`, 0x812F), which rlsw's
  `swTexParameteri` rejects (it accepts `GL_REPEAT` and `GL_CLAMP` only); the
  mirror modes are rejected too. Every texture samples with REPEAT.
- **Filters.** `TEXTURE_FILTER_POINT` sets NEAREST for minification and
  magnification, `BILINEAR` and `TRILINEAR` (a texture always has one level
  here) set LINEAR; the anisotropic modes change nothing under OpenGL 1.1.
  Minification and magnification are always equal, so rlsw's derivative test
  never matters.
- **Mipmaps.** `rlGenTextureMipmaps` only warns under OpenGL 1.1:
  `GenTextureMipmaps` leaves one level. (`rlLoadTexture` would upload extra
  levels over the base one, since `swTexImage2D` ignores the level; Jonlib
  loads single-level `Surface`s only.)
- **Formats.** rlgl's OpenGL 1.1 table maps formats 1..7 (GRAYSCALE,
  GRAY_ALPHA, R5G6B5, R8G8B8, R5G5B5A1, R4G4B4A4, R8G8B8A8) to rlsw formats;
  the float formats 8..13 get no internal format, so the texture gets an id
  but no pixels and rlsw draws it untextured (the tint alone); compressed
  formats fail with id 0. rlsw reads texels through `readColor8` (bit
  replication for 5- and 6-bit channels, `v*17` for 4-bit ones, 255 or 0 for
  the 1-bit alpha) and `byte*SW_INV_255`.
- **Alpha mode.** At load, rlsw marks a texture of a format with alpha as
  transparent when a texel's alpha is below 255; opaque textures drawn with an
  opaque tint are stored without blending. `UpdateTexture` and
  `UpdateTextureRec` pass the texture's own format, which rlsw copies as raw
  bytes without recomputing the mode: an opaque texture updated with
  translucent texels keeps drawing unblended.
- **LoadImageFromTexture.** `rlReadTexturePixels` allocates a zeroed buffer
  and calls `glGetTexImage`, which rlsw defines as a no-op: the image is all
  zero bytes in the texture's format and size (float formats: no image).
- **Sampling.** Nearest: `(int)(fract(u)*width)`, read at `y*width + x`
  (`fract` of a coordinate within 2^-25 below an integer is 1.0, and the read
  lands on the next row's first texel). Bilinear: `xf = u*width - 0.5`,
  weights `fract(xf)`, texels `(int)xf` (truncated toward zero, so
  coordinates just left of 0 blend texels 0 and 1) and the next, both wrapped
  with `((x%w)+w)%w`, interpolated per channel as rlsw writes it. Textured
  pixels multiply the interpolated tint by the texel.
- **Matrices.** rlgl's OpenGL 1.1 matrix calls go to rlsw's stacks: a
  projection stack (raylib only reloads its top) and a modelview stack of 8.
  `swTranslatef`/`swRotatef`/`swScalef`/`swMultMatrixf` replace the current
  matrix M by `T*M` in rlsw's row-major `float[16]` product, `swBegin` uses
  `modelview*projection`; all are reproduced with rlsw's summation order.
  `BeginMode2D` loads `GetCameraMatrix2D` (computed uncontracted, raymath
  order) after an identity; `EndMode2D` and `BeginDrawing` load the identity.
  A push beyond 8 entries is ignored; popping the last entry is undefined.
  These calls act on the stack `rlMatrixMode` selects; the projection and
  texture stacks and the rest of the immediate-mode API are in
  [RLGL.md](RLGL.md).
- **Scissor.** `BeginScissorMode(x, y, w, h)` calls `rlScissor(x,
  fboHeight - (y + h), w, h)` (on macOS through a float path with the memory
  platform's DPI scale 1, equal to the integer path on the accepted domain).
  `swScissor` stores the rectangle and its clip-space bounds for the viewport
  current at the call; a negative size is rejected (the previous rectangle
  stays, the test is enabled). Polygons are clipped by four more planes after
  the frustum, lines by four more Liang-Barsky terms. `ClearBackground` with
  the test enabled fills the rectangle clamped to the buffer from its minimum
  to its maximum corner inclusive: one row and column more than the scissor,
  at least one pixel even off-screen.
- **Render textures.** `LoadRenderTexture` takes a framebuffer id, a zeroed
  R8G8B8A8 color texture (loaded without data, so rlsw assumes alpha) and a
  depth renderbuffer from the texture pool. `BeginTextureMode` binds it, sets
  the viewport and `rlOrtho(0, w, h, 0, 0, 1)` and an identity modelview; the
  scissor keeps the clip-space bounds of the previous viewport until the next
  `BeginScissorMode`. `EndTextureMode` restores the screen's viewport and
  projection. The color buffer's rows are bottom-up, as the screen's: drawn
  as a texture it appears flipped unless the source height is negative
  (`DrawTextureRec(target.texture, (Rectangle){ 0, 0, w, -h }, ...)`).
- **Ids.** rlsw's pools hand out the most recently freed id first, else the
  next fresh one: textures 1..127 (the default font is 1, so the first user
  texture is 2), framebuffers 1..7.

## API

| raylib | Jonlib |
|---|---|
| `BeginMode2D` / `EndMode2D` | `Frame.begin_mode_2d_for(libm, frame, camera)`, `Frame.begin_mode_2d`, `Frame.end_mode_2d` |
| `BeginScissorMode` / `EndScissorMode` | `Frame.begin_scissor_mode(frame, x, y, w, h)`, `Frame.end_scissor_mode` |
| `BeginBlendMode` / `EndBlendMode` | `Frame.begin_blend_mode(frame, mode)`, `Frame.end_blend_mode` (no effect, see above) |
| `rlPushMatrix` / `rlPopMatrix` / `rlLoadIdentity` | `Rlgl.push_matrix`, `Rlgl.pop_matrix`, `Rlgl.load_identity` |
| `rlTranslatef` / `rlScalef` / `rlRotatef` / `rlMultMatrixf` | `Rlgl.translatef`, `Rlgl.scalef`, `Rlgl.rotatef_for(libm, ...)`, `Rlgl.rotatef`, `Rlgl.mult_matrixf(frame, M.Matrix)` |
| `LoadTextureFromImage` / `UnloadTexture` | `Texture.load_from_image(frame, surface) -> Frame & Maybe<Texture>`, `Texture.unload(frame, texture) -> Frame` |
| `IsTextureValid`, texture fields | `Texture.is_valid`, `Texture.info -> Texture & TextureInfo{id, width, height, mipmaps, format}` |
| `UpdateTexture` / `UpdateTextureRec` | `Texture.update(texture, surface)`, `Texture.update_rec(texture, rec, surface)` -> `Result<Texture & Surface.Error, Texture>` |
| `GenTextureMipmaps` / `SetTextureFilter` / `SetTextureWrap` | `Texture.gen_mipmaps`, `Texture.set_filter(texture, filter)`, `Texture.set_wrap(texture, wrap)` |
| `LoadImageFromTexture` | `Texture.load_image(texture) -> Texture & Maybe<Surface>` |
| `DrawTexture` / `V` / `Ex` / `Rec` / `Pro` | `Draw.texture`, `Draw.texture_v`, `Draw.texture_ex_for`/`texture_ex`, `Draw.texture_rec`, `Draw.texture_pro_for`/`texture_pro` -> `Frame & Texture` |
| `DrawTextureNPatch` | `Draw.texture_npatch_for(libm, frame, texture, NPatchInfo{source, left, top, right, bottom, layout}, dest, origin, rotation, tint)`, `Draw.texture_npatch` |
| `LoadRenderTexture` / `UnloadRenderTexture` / `IsRenderTextureValid` | `RenderTexture.load(frame, width, height) -> Frame & Maybe<RenderTexture>`, `RenderTexture.unload(frame, target)`, `RenderTexture.is_valid` |
| `BeginTextureMode` / `EndTextureMode` | `Frame.begin_texture_mode(frame, target) -> Frame`, `Frame.end_texture_mode(frame) -> Frame & Maybe<RenderTexture>` |
| `GetWorldToScreen2D` / `GetScreenToWorld2D` / `GetCameraMatrix2D` | `Camera.*_2d_for` ([CAMERA.md](CAMERA.md)) |

Ownership: a `Texture` (raylib's `Texture2D`) owns its texels and belongs to
the frame that loaded it; drawing hands it back; `Texture.unload` consumes it
and returns its id to the frame's pool. A `RenderTexture{id, texture, depth}`
is owned the same way; its `texture` field may be read (drawn, filtered) and
put back unchanged. `Frame.begin_texture_mode` moves the render texture into
the frame until `Frame.end_texture_mode` hands it back, so it cannot be drawn
into itself. `Texture.load_from_image`, `update` and `update_rec` consume their
`Surface`. Integer parameters of `DrawTexture` and `BeginScissorMode` are F32
values converted as C converts them; `NPatchInfo`'s borders and layout hold
integral F32 values. The `_for` functions take the `M.Libm` profile; the
others use `M.AppleLibm{}`.

## Files, cubemaps and screenshots

- **LoadTexture.** `Texture.load(frame, path) -> IO(Frame & Maybe<Texture>)` is
  `LoadImage` (`Surface.load_image`, [IMAGE-FILES.md](IMAGE-FILES.md)) and then
  `LoadTextureFromImage` of the decoded image. A file that does not load and
  an exhausted id pool are `None` with the frame unchanged (raylib returns
  texture id 0, which every draw skips).
- **LoadTextureCubemap.** rlgl's `rlLoadTextureCubemap` is compiled only for
  OpenGL 3.3 and ES2: under the software renderer it returns id 0 without
  touching rlsw, so no cubemap is ever loaded. `Texture.load_cubemap(frame,
  image, layout) -> Frame & (Surface & TextureInfo)` keeps the fields raylib
  leaves: id 0, mipmaps 0, format 0 and width = height = the face size
  `rtextures.c` derives (line layouts `height/6` or `width/6`, crosses
  `width/3` or `width/4`; `CUBEMAP_LAYOUT_AUTO_DETECT` picks one from the
  aspect, else 0; other layout values 0). The image stays the caller's.
- **TakeScreenshot.** `Frame.take_screenshot(frame, name) -> IO(Frame &
  Maybe<Bool>)`: a name containing `'` is rejected (nothing written);
  otherwise the screen image is exported with `ExportImage`'s suffix rules
  (`Surface.write_image`) to `name` in the working directory, and the answer
  is whether the file exists afterwards (raylib's log check). The image
  follows `LoadImageFromScreen`'s desktop contract (top-down R8G8B8A8, alpha
  255, [FRAME.md](FRAME.md#readback)); the memory platform writes the same
  pixels bottom-up with red and blue swapped (`rlReadScreenPixels` over rlsw's
  BGRA buffer), which the probe normalizes. raylib joins the name to
  `CORE.Storage.basePath` (the working directory at InitWindow) through
  `TextFormat`, which truncates paths of 1024 bytes or more; Jonlib writes the
  relative name. `None` (nothing written) when a draw was refused or a render
  texture is the target. The F12/`ACTION_TAKE_SCREENSHOT` captures of
  `EndDrawing` are still only counted (`Core.screenshot_count`).

## Refusals and None

As in slice 1, a draw Jonlib does not reproduce marks the frame undefined
(readbacks are `None`, the frame stays owned):

- undefined behavior in the reference: popping the last modelview matrix; C
  int conversions out of range or of NaN (`DrawTexture` positions, the
  scissor, `(int)dest.width` in `DrawTextureNPatch`); NaN or out-of-range
  texture coordinates for the bilinear `(int)` and a nearest read past the last
  texel (rlsw reads out of bounds); the slice 1 rules;
- a `sinf`/`cosf` argument outside the profile's verified set
  ([FRAME.md](FRAME.md#reference-and-profile)): the camera's
  `rotation*DEG2RAD` (always evaluated), `rlRotatef`'s angle,
  `DrawTextureNPatch`'s rotation (always evaluated) and nonzero
  `DrawTexturePro`/`DrawTextureEx` rotations. Unlike `Camera.matrix_2d` (which
  accepts only a zero Apple argument), the frame uses the verified integral
  degrees of the shapes profile;
- restrictions of this contract: `BeginScissorMode` arguments beyond `2^22` in
  magnitude; a second `BeginTextureMode` before `EndTextureMode` (the second
  target is dropped); `LoadRenderTexture`/`UnloadRenderTexture` during texture
  mode (rlgl rebinds framebuffer 0 behind raylib's back); render-texture sizes
  outside 1..4096 or fewer than two free texture ids; non-integral NPatch
  borders or layout. Every refused draw marks the frame undefined, also when
  it targets a render texture.

`None` without refusal: `Texture.load_from_image` when the 127 texture ids are
in use (raylib returns id 0, the frame is unchanged), `RenderTexture.load` when
the 7 framebuffer ids are in use, `Frame.framebuffer` and
`Frame.load_image_from_screen` while a render texture is the target,
`Frame.end_texture_mode` without one, `Texture.load_image` of a float texture.
`Texture.update`/`update_rec` fail (`InvalidRequest`, the texture handed back)
when an applied update's pixels do not have the texture's format and the
rectangle's size, and `update_rec` fails (`OutOfDomain`) on undefined `(int)`
conversions of the rectangle or sums that could reach 2^31.

## Verification

| Gate | Tool | Compares |
|---|---|---|
| `window` | `tools/window_probe.py` | `LoadTexture` of PNG fixtures (RGBA with translucent texels, RGB) drawn into the frame and of a missing file, `LoadTextureCubemap`'s fields for every layout and auto-detected aspect, and `TakeScreenshot` to `.png`, `.BMP`, a name without suffix and one with a quote: Jonlib's file must equal raylib's flipped, swapped screenshot re-exported by raylib, byte for byte ([DRIVER.md](DRIVER.md#window-state)) |
| `texture` | `tools/texture_probe.py` | 118 scenes (1410 operations, sizes 8x6 to 32x32, 10 random scenes) byte for byte against the uncontracted memory-platform raylib on CPU-1, CPU-2 and JavaScript, with texture ids, sizes, mipmaps, formats, validity and `LoadImageFromTexture` sums; 13 contract scenes (9 on glibc hosts) must be refused |
| `frame` | `tools/frame_probe.py` | slice 1, unchanged |

```sh
python3 tools/texture_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --jobs 3
```

Scenes: 14 cameras (offsets, targets, zooms 0.5..3 and 0, -1, rotations of
-90..359 degrees) over every shape kind, twice-begun cameras, the matrix stack
(nested, overflowing past 8, non-unit and x/y rotation axes, rlMultMatrixf,
inside a camera), scissors inside, across and outside the screen, negative
sizes, re-begun (nested) scissors, ClearBackground in a scissor, scissors in a
camera and set before a texture mode, all eight blend modes over a translucent
background, formats 1..7 opaque and translucent with sizes 1x1 to 16x8 and
non-powers of two, float formats, every filter and wrap value with
fractional, negative, repeating and flipped source rectangles, 8 rotations
with origins, NPatch nine- and three-patch layouts (and an invalid one) with
borders larger than the destination, negative sources and rotation, opaque
textures updated with translucent texels, `UpdateTextureRec` of every format
with clipped, out-of-range and empty rectangles, pool reuse and exhaustion of
both pools, render textures drawn flipped and not, filtered, rotated, under a
camera, a scaled modelview and a scissor, reused across several texture modes,
and textures drawn into render textures.

The texture probe runs each scene as data through one interpreter def: a
generated def per scene made Apple clang 21's arm64 backend fail on the
generated C ([VERIFICATION.md](VERIFICATION.md#known-toolchain-defects)).

## Gaps

- Multi-level `Image.Stored` textures and compressed formats (id 0 in
  raylib) are not exposed; cubemaps load nowhere under the software renderer
  (above), so their OpenGL 3.3 behavior is a separate (GPU) contract; `DrawTextureNPatch` is checked on nearest and bilinear textures
  only through the scenes above.
- `rlSetBlendFactors`, custom blend modes and shader modes have no effect on
  the software renderer (`Rlgl.set_blend_factors` and the shader calls are
  documented no-ops, [RLGL.md](RLGL.md)); the GPU (OpenGL 3.3) behavior of
  blend and wrap modes is a separate contract.
- Text drawing with the default font (`DrawText*`) is the first Phase 3 slice.
- Performance is not measured beyond slice 1's benchmark.
