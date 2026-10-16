# rlgl immediate mode and the remaining shapes

Phase 2: the public rlgl immediate-mode API on the software renderer, and the
`rshapes.c` drawing functions slice 1 left out (rounded rectangles, ring
outlines, thick polygon outlines, Bezier and dashed lines, splines, the
shapes texture and segment estimation). Both render exactly as pinned raylib
6.0 renders them on its memory platform. Altered Bend adaptations of
`rlgl.h`'s OpenGL 1.1 path, `rshapes.c` (zlib,
[LICENSES/raylib.txt](../LICENSES/raylib.txt)) and `src/external/rlsw.h` 1.5
(Copyright (c) 2025-2026 Le Juez Victor, MIT,
[LICENSES/rlsw.txt](../LICENSES/rlsw.txt)). Code: the sections "Remaining
shapes, shapes texture and splines" and "rlgl immediate mode and render state"
of `jonlib.bend`, `src/frame.bend` (rlsw pipeline state, depth buffer, thick
lines, points, polygon modes), `src/shapes.bend` (vertex streams and segment
estimates) and `src/rlgl.bend` (`swOrtho`/`swFrustum`).

The reference, the uncontracted F32 profile and the `M.Libm` sine/cosine
sets are those of [FRAME.md](FRAME.md#reference-and-profile); cameras, the
modelview stack, scissor mode and textures are in [TEXTURES.md](TEXTURES.md).

## What the software renderer does

Traced in the pinned `rlgl.h` (OpenGL 1.1 branch, `GRAPHICS_API_OPENGL_SOFTWARE`)
and `rlsw.h`, and checked by the probe:

- **No render batch.** `rlBegin`, `rlColor*`, `rlTexCoord2f`, `rlVertex*`,
  `rlEnd` and `rlSetTexture` call `swBegin`, `swColor*`, ... directly. A
  primitive renders when its last vertex arrives (2 for `RL_LINES`, 3 for
  `RL_TRIANGLES`, 4 for `RL_QUADS`); the color and texture coordinate persist.
  `rlBegin` with another mode does nothing; `rlBegin` while a primitive is
  active is an rlsw error that changes nothing (Jonlib keeps the active one).
- **Latched at `swBegin`:** the MVP (`modelview*projection`), the texture
  (when `GL_TEXTURE_2D` is enabled and the bound texture has pixels), and the
  blend and depth-test states. **Read when a primitive completes:** face
  culling, the scissor, the polygon mode, line width, point radius and the
  viewport. A primitive blends when blending was latched and its texture has
  alpha or a color with alpha below 1 was set since the previous primitive.
- **Matrix modes.** `rlMatrixMode` selects rlsw's modelview (8 entries),
  projection (2) or texture (2) stack; other values change nothing. Push,
  pop, identity, `rlMultMatrixf`, translate/rotate/scale, `rlOrtho` and
  `rlFrustum` act on the selected stack (`M = mul(M, T)`). A push beyond a
  stack's capacity is ignored; popping its last entry is undefined (refused).
  The texture matrix transforms every texture coordinate, shapes included.
  `rlGetMatrixModelview`/`rlGetMatrixProjection` return the stack tops.
- **`rlOrtho`/`rlFrustum`.** rlsw computes them in `double` from F32
  arguments and stores floats. Jonlib reproduces them on the domain where
  every difference (`right - left`, ...) and, for the frustum, `far*near` is
  an exact binary32 value (Dekker's two-sum and splitting check it); then each
  stored entry is one or two correctly rounded operations on exact values and
  double rounding through binary64 is innocuous (Figueroa). Other arguments
  are refused.
- **Viewport.** `rlViewport(x, y, w, h)` with C ints; negative sizes are
  rejected by `swViewport`. Projection uses `center + ndc*half + 0.5` with
  `half = size/2.0f`, clipping uses the frustum, so a viewport smaller than the
  buffer still clips to itself while the scissor's clip bounds are those of the
  viewport current at `rlScissor`.
- **Depth.** rlsw has a D32 float depth buffer for the screen. With the test
  enabled a fragment is discarded when its z exceeds the stored depth,
  otherwise z is stored and the color written; `glDepthFunc` and
  `glDepthMask` are no-ops. `rlClearScreenBuffers` and `ClearBackground`
  clear it to 1.0 (within the scissor rectangle when the test is on). A
  render texture has its own D32 depth renderbuffer, which rlsw allocates
  zeroed (depth 0.0, so before a clear only fragments at depth 0 pass) and
  keeps between texture modes; the frame holds it by framebuffer id until
  `UnloadRenderTexture`.
- **Culling.** On by default (back faces). `rlSetCullFace(RL_CULL_FACE_FRONT)`
  culls front faces. `sw_triangle_face_culling` uses the `(x, y, w)`
  determinant of the first three clip-space vertices: back-face culling keeps
  a positive determinant (counter-clockwise on screen with raylib's
  y-down ortho), so zero-area and NaN primitives are dropped.
- **Polygon modes.** `rlEnableWireMode` draws a triangle's or quad's edges as
  lines (unclipped as polygons, unculled; each edge through the line
  clipper), `rlEnablePointMode` its vertices as points; a line primitive in
  line mode is drawn both ways. `rlDisable*` returns to filling.
- **Line width.** rlsw stores `roundf(width)`; 2 or more selects
  `SW_RASTER_LINE_THICK`: the line plus copies shifted by -i and +i pixels
  across its major axis, `i = 1..((int)((w - 1)*|d|/len) >> 1)`. The copies
  are not clipped; one reaching outside the color buffer is refused.
  `rlGetLineWidth` returns the stored value (0 until set).
- **Points.** `rlSetPointSize` stores `floorf(size*0.5f)` as a radius; a
  point is the `(2r + 1)^2` square around `(int)x, (int)y`, accepted when the
  center lies within the radius of the buffer (or the clamped scissor). The
  square is not bounds-checked: a pixel outside the buffer is refused.
  `rlGetPointSize` returns `2*radius`.
- **Clears.** `rlClearColor` takes bytes; `rlClearScreenBuffers` clears color
  and depth (the current target's: the screen's or the render texture's).
- **OpenGL 3.3-only calls.** Blend modes and factors, shaders, vertex arrays
  and buffers, stereo rendering, cubemaps, framebuffer blits, draw buffers,
  `rlLoadDrawCube`/`rlLoadDrawQuad`, render-batch control, `rlCheckErrors`,
  smooth lines and color masks do nothing; `rlGetVersion` is
  `RL_OPENGL_SOFTWARE` (0), framebuffer width/height and the default texture
  and shader ids are 0, `rlEnableVertexArray` and `rlCheckRenderBatchLimit`
  are false, `rlGetMatrixTransform` and the stereo matrices are the identity.
  `rlGetActiveFramebuffer` is the render texture's id in texture mode, else 0.

Remaining shapes (`rshapes.c`):

- **Segment estimation.** `DrawCircleSector(Lines)`, `DrawRing(Lines)` and
  the rounded rectangles estimate segments as
  `th = acosf(2*powf(1 - 0.5f/r, 2) - 1)`, then `(int)(span*ceilf(2*PI/th)/360)`
  for arcs (minimum when non-positive) and `(int)(ceilf(2*PI/th)/4)` or `/2`
  for corners (4 when non-positive). Compilers fold `powf(x, 2)` to `x*x` (the
  probe checks with `objdump` that the reference functions call `acosf` and no
  `powf`). `acosf` is reproduced for `M.Glibc239Libm{}` (glibc 2.39's
  `e_acosf.c`, [INVERSE-TRIG.md](INVERSE-TRIG.md)); an estimate under another
  profile is refused, as is a count above 4096.
- **Shapes texture.** `SetShapesTexture(texture, source)` makes textured
  shapes sample it with `source/size` coordinates (F32, as `rshapes.c` divides
  by the int size). Id 0 or an empty source resets to
  `(Texture2D){ 1, 1, 1, 1, 7 }` and `(0, 0, 1, 1)`, which samples rlsw's
  texture 1, the whole default font atlas.
- **`DrawPolyLinesEx`** evaluates `cosf(DEG2RAD*(360/sides*DEG2RAD)/2)`
  (raylib's double `DEG2RAD`); the Apple host's `cosf` is correctly rounded on
  every such argument for 3..4096 sides (checked by the probe), so this
  profile accepts them all.
- **Splines.** `DrawSplineBezierCubic` and its segment use `powf(x, 3)` of the
  48 arguments `t = i/24`, `1 - t`; Jonlib's value equals the host's on all of
  them for Apple and glibc 2.39 (checked); glibc 2.41 is refused.
  Basis and Catmull-Rom splines draw circle caps with the sine/cosine profile.
- **`DrawLineDashed`** takes int dash and space sizes (`|v| <= 2^24`); a
  sequence of more than 4096 dashes (or one that never reaches the end) is
  refused.

## API

| raylib | Jonlib |
|---|---|
| `DrawLineBezier` / `DrawLineDashed` | `Draw.line_bezier(frame, start, end, thick, color)`, `Draw.line_dashed(frame, start, end, dash, space, color)` |
| `DrawRingLines` / `DrawPolyLinesEx` | `Draw.ring_lines_for`/`ring_lines`, `Draw.poly_lines_ex_for`/`poly_lines_ex` |
| `DrawRectangleRounded` / `Lines` / `LinesEx` | `Draw.rectangle_rounded_for`, `rectangle_rounded_lines_for`, `rectangle_rounded_lines_ex_for` (and without `_for`) |
| `DrawSplineLinear` / `Basis` / `CatmullRom` / `BezierQuadratic` / `BezierCubic` | `Draw.spline_linear`, `spline_basis_for`, `spline_catmull_rom_for`, `spline_bezier_quadratic`, `spline_bezier_cubic_for` (points as `+List<M.Vector2>`) |
| `DrawSplineSegment*` | `Draw.spline_segment_linear`, `_basis`, `_catmull_rom`, `_bezier_quadratic`, `_bezier_cubic_for` |
| `SetShapesTexture` | `Frame.set_shapes_texture(frame, Maybe<Texture>, source) -> Frame & (Maybe<Texture> & Maybe<Texture>)` (previous, not taken) |
| `GetShapesTexture` / `Rectangle` | `Frame.get_shapes_texture -> Frame & TextureInfo`, `Frame.get_shapes_texture_rectangle -> Frame & Rectangle` |
| `rlBegin` / `rlEnd` | `Rlgl.begin(frame, mode)`, `Rlgl.end` |
| `rlVertex2i` / `2f` / `3f`, `rlTexCoord2f`, `rlNormal3f` | `Rlgl.vertex2i`, `vertex2f`, `vertex3f`, `tex_coord2f`, `normal3f` |
| `rlColor4ub` / `rlColor3f` / `rlColor4f` | `Rlgl.color4ub`, `color3f`, `color4f` |
| `rlSetTexture` / `rlEnableTexture` / `rlDisableTexture` | `Rlgl.set_texture(frame, Maybe<Texture>) -> Frame & Maybe<Texture>`, `enable_texture`, `disable_texture` |
| `rlMatrixMode`, `rlOrtho`, `rlFrustum`, `rlViewport` | `Rlgl.matrix_mode`, `ortho`, `frustum`, `viewport` |
| `rlGetMatrixModelview` / `Projection` / `Transform`, stereo matrices, `rlSetMatrix*` | `Rlgl.get_matrix_*` (`-> Frame & M.Matrix` or `M.Matrix`), `Rlgl.set_matrix_*` (no effect) |
| `rlEnable`/`rlDisable` `ColorBlend`, `DepthTest`, `DepthMask`, `BackfaceCulling`, `ScissorTest`, `WireMode`, `PointMode`, `SmoothLines`, `StereoRender` | `Rlgl.enable_*` / `Rlgl.disable_*` |
| `rlSetCullFace`, `rlScissor`, `rlColorMask` | `Rlgl.set_cull_face`, `scissor`, `color_mask` |
| `rlSetLineWidth` / `rlGetLineWidth`, `rlSetPointSize` / `rlGetPointSize` | `Rlgl.set_line_width`, `get_line_width`, `set_point_size`, `get_point_size` |
| `rlClearColor` / `rlClearScreenBuffers` | `Rlgl.clear_color(frame, r, g, b, a)`, `clear_screen_buffers` |
| `rlGetVersion`, `rlGetFramebufferWidth/Height`, `rlGetTextureIdDefault`, `rlGetShaderIdDefault`, `rlIsStereoRenderEnabled`, `rlCheckRenderBatchLimit`, `rlGetActiveFramebuffer` | `Rlgl.get_version`, ... (values above) |
| `rlLoadVertexArray`, `rlLoadVertexBuffer(Element)`, `rlLoadShader`, `rlLoadShaderProgram(Ex)`, `rlLoadShaderProgramCompute`, `rlLoadShaderBuffer`, `rlGetShaderBufferSize` | `Rlgl.load_vertex_array(frame)`, `load_vertex_buffer(frame, size, dynamic)`, `load_vertex_buffer_element`, `load_shader(frame, code, kind)`, `load_shader_program(frame, vs, fs)`, `load_shader_program_ex`, `load_shader_program_compute`, `load_shader_buffer(frame, size, usage)` (`-> Frame & U32`), `get_shader_buffer_size(id)`: 0 |
| `rlGetLocationUniform` / `rlGetLocationAttrib`, `rlGetShaderLocsDefault` | `Rlgl.get_location_uniform(id, name)` / `get_location_attrib`: -1 (`4294967295`); `Rlgl.get_shader_locs_default()`: `None` |
| `rlGetPixelFormatName` | `Rlgl.get_pixel_format_name(format)`: the 24 names, `"UNKNOWN"` otherwise |
| `rlGetGlTextureFormats` | `Rlgl.get_gl_texture_formats(format) -> Rlgl.GlFormats{internal, format, kind}`: OpenGL 1.1's answer, rlsw's `GL_LUMINANCE`, `GL_LUMINANCE_ALPHA`, `GL_RGB` or `GL_RGBA` with `GL_UNSIGNED_BYTE` or a packed 16-bit type for the seven uncompressed formats of 8-bit channels or packed pixels; 0, 0, 0 for every other format (float and compressed ones too) |
| `rlLoadRenderBatch`, `rlUnloadRenderBatch`, `rlDrawRenderBatch`, `rlSetRenderBatchActive` (types `rlVertexBuffer`, `rlDrawCall`, `rlRenderBatch`) | `Rlgl.load_render_batch(frame, buffers, elements) -> Frame & Rlgl.RenderBatch` and the rest: the batch is OpenGL 3.3/ES2's, so the software renderer's is zeroed (no buffers or draws, depth 0) and drawing, activating or unloading it changes nothing |
| `rlCopyFramebuffer` | `Rlgl.copy_framebuffer(frame, x, y, w, h, format) -> Frame & Maybe<+List<U32>>`: `swReadPixels` through OpenGL 1.1's formats: for raylib formats 1..7, `w` and `h` cut to the buffer, `x` and `y` clamped to `[0, w]` and `[0, h]`, then `w` x `h` pixels from rlsw's bottom-up buffer, the region's top row first, each row of `w` pixels running on into the next one past the right edge as the memory does; RGB and RGBA come out as BGR and BGRA, grayscale is `(77 r + 150 g + 29 b) >> 8`, packed 16-bit pixels are truncated bits, little-endian. The bytes written at the buffer's start; none for another format or an empty region; `None`, and the frame undefined, where rlsw would read past its buffer (or a draw was refused). Ints are their U32 bits |
| `rlReadScreenPixels` | `Rlgl.read_screen_pixels(frame, width, height) -> Frame & Maybe<+List<U32>>`: a zeroed `width * height * 4` buffer, `rlCopyFramebuffer`'s RGBA read of the whole size at its start (cut to the screen, rows packed), then rows swapped end for end with every alpha 255: on the memory platform, the screen bottom-up with red and blue swapped |
| `rlReadTexturePixels` | `Rlgl.read_texture_pixels(width, height, format) -> Maybe<+List<U32>>`: `glGetTexImage` does nothing in rlsw, so formats 1..7 give `rlGetPixelDataSize` zero bytes and other formats `NULL` (`None`) |
| `rlLoadExtensions`, `rlGetProcAddress` | `Rlgl.load_extensions(frame)`, `Rlgl.get_proc_address(name) -> U32`: OpenGL 3.3/ES2 extension loading does nothing here and the address is NULL (0) |
| `rlGenTextureMipmaps` | `Rlgl.gen_texture_mipmaps(frame, id, width, height, format, mipmaps) -> Frame & U32`: GPU mipmaps are OpenGL 3.3/ES2's; the count given is the count left |
| no-ops (buffers, shader objects, compute) | `Rlgl.update_vertex_buffer(_elements)`, `unload_vertex_array`, `unload_vertex_buffer`, `set_vertex_attribute`, `set_vertex_attribute_divisor`, `set_vertex_attribute_default`, `draw_vertex_array_instanced`, `draw_vertex_array_elements_instanced`, `unload_shader`, `unload_shader_program`, `compute_shader_dispatch`, `unload_shader_buffer`, `update_shader_buffer`, `bind_shader_buffer`, `read_shader_buffer`, `copy_shader_buffer`, `bind_image_texture` (buffer contents are never read: the functions take sizes only) |
| no-ops | `Rlgl.check_errors`, `set_blend_mode`, `set_blend_factors(_separate)`, `set_framebuffer_width/height`, `draw_render_batch_active`, `active_texture_slot`, `enable/disable_texture_cubemap`, `cubemap_parameters`, `enable/disable_shader`, `set_shader`, `set_uniform`, `set_uniform_matrix`, `set_uniform_matrices`, `set_uniform_sampler`, `enable/disable_vertex_array`, `_vertex_buffer`, `_vertex_buffer_element`, `_vertex_attribute`, `blit_framebuffer`, `active_draw_buffers`, `load_draw_cube`, `load_draw_quad` |

`Rlgl.set_texture(frame, Some{texture})` moves the texture into the frame
until `Rlgl.set_texture(frame, None)` hands it back (the result is the
texture the frame held before, or the given one when a primitive is being
recorded and `swBindTexture` refuses the bind). A `Draw*` call that binds its
own texture leaves the held one unbound afterwards, as `rlSetTexture(0)` does
in raylib. Int parameters are F32 values converted as C converts them.

## Refusals

A refused call marks the frame undefined (readbacks are `None`), as in
[FRAME.md](FRAME.md#state-and-api):

- undefined behavior in the reference: popping the last projection or
  texture matrix; thick-line copies or point squares outside the color buffer
  (rlsw writes out of bounds); NaN or out-of-range int conversions;
- outside this contract's numeric domain: `rlOrtho`/`rlFrustum` arguments
  whose differences (or `far*near`) are not exact in binary32, rounded line
  widths above 4096, NaN point sizes or radii beyond 4096, `rlScissor` values
  beyond `2^22`, segment estimates under a profile other than glibc 2.39,
  `DrawSplineBezierCubic` under glibc 2.41, more than 4096 dashes, segments or
  polygon sides.

## Verification

| Gate | Tool | Compares |
|---|---|---|
| `rlgl` | `tools/rlgl_probe.py` | 49 scenes (928 operations, sizes 16x12 to 40x52, 6 random immediate-mode scenes) byte for byte against the uncontracted memory-platform raylib on CPU-1, CPU-2 and JavaScript, with getter results; on macOS 14 of them are contracts that must be refused (the segment-estimate scenes are compared on glibc 2.39 hosts); tables of the host `powf(x, 3)` (48 arguments) and `cosf` (4094 `DrawPolyLinesEx` arguments), and 408 segment estimates (arcs and corners, radii 0.3 to 50000) against glibc 2.39's `e_acosf.c` compiled by the probe |

```sh
python3 tools/rlgl_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --jobs 3
```

Scenes are data run by one interpreter def ([VERIFICATION.md](VERIFICATION.md#known-toolchain-defects)).
They cover each new shape (several sizes, translucent colors, degenerate and
huge parameters), the shapes texture set, reset and opaque, immediate
lines/triangles/quads with per-vertex colors and textures, all three matrix
modes, ortho and frustum projections, viewports, culling of both faces,
blending toggled, depth-tested overlaps, wire and point modes, thick lines,
clears and getters, and random immediate scenes.

## Framebuffer objects

rlsw keeps one color and one depth attachment a framebuffer and decides
completeness from them; a renderbuffer is a texture with depth storage there.
Jonlib's canvas has no such table (a texture's pixels live in its `Texture`
value), so the framebuffer object is a value the caller threads, as the
examples keep the ids in a `RenderTexture2D` they fill by hand.

| rlgl | Jonlib | Result |
|---|---|---|
| `rlLoadFramebuffer()` | `Rlgl.load_framebuffer(frame)` | `Frame & Rlgl.Framebuffer` (id 0 when the 7 are in use) |
| `rlLoadTexture(NULL, w, h, format, 1)` | `Rlgl.load_texture(frame, w, h, format, mipmaps)` | `Frame & Maybe<Texture>`: R8G8B8A8 zeroed, alpha assumed; formats 8 to 13 without storage |
| `rlLoadTextureDepth(w, h, useRenderBuffer)` | `Rlgl.load_texture_depth(frame, w, h, use_render_buffer)` | `Frame & Maybe<Texture>`: format 19, no texels |
| `rlFramebufferAttach(id, texId, attachType, texType, mip)` | `Rlgl.framebuffer_attach(frame, fb, texture, attach_type, tex_type, mip)` | `Frame & (Rlgl.Framebuffer & Texture)` |
| `rlFramebufferComplete(id)` | `Rlgl.framebuffer_complete(frame, fb)`, `Rlgl.Framebuffer.complete(fb)` | `Frame & Bool`, `Bool` |
| `rlEnableFramebuffer(id)` | `Rlgl.enable_framebuffer(frame, fb)` | `Rlgl.Bound` |
| `rlEnableFramebuffer(id)`, to draw | `Rlgl.enable_framebuffer_incomplete(frame, fb)` | `Frame` (an incomplete framebuffer: draws dropped) |
| `rlBindFramebuffer(target, id)` | `Rlgl.bind_framebuffer(frame, target, fb)` | `Frame` |
| `rlDisableFramebuffer()` | `Rlgl.disable_framebuffer(frame)`, `Rlgl.Bound.disable(bound)` | `Frame` |
| `rlUnloadFramebuffer(id)` | `Rlgl.unload_framebuffer(frame, fb, depth)` | `Frame` |
| `rlUnloadTexture(id)` | `Rlgl.unload_texture(frame, texture)` | `Frame` |
| the struct filled by hand | `Rlgl.render_texture(fb, texture, depth_id)` | `Maybe<RenderTexture>` for `BeginTextureMode` |
| the same without a color texture | `Rlgl.render_texture_depth(fb, width, height, depth_id)` | `Maybe<RenderTexture>` whose texture mode draws nothing |

- **Attachments.** `attachType` 0 with any `texType` of 0 and above (a 2D
  texture, a renderbuffer or a cubemap face: rlsw ignores the difference)
  sets the color attachment; `RL_ATTACHMENT_COLOR_CHANNEL1` to 7 and the
  stencil are an invalid enum for rlsw and change nothing; `attachType` 100
  with `texType` 100 or 200 sets the depth attachment. Nothing attaches to
  framebuffer 0.
- **Completeness.** Framebuffer 0 is complete. Another one needs a color
  attachment in R8G8B8A8; a depth attachment, if any, must have the depth
  format and the color attachment's size. A framebuffer with only a depth
  attachment is incomplete.
- **Binding.** `rlFramebufferAttach` and `rlFramebufferComplete` bind the
  framebuffer and then framebuffer 0, so during texture mode they are
  refused (the render texture would stop being the target), as are
  `rlLoadFramebuffer` and `rlDisableFramebuffer`. `rlEnableFramebuffer`
  outside texture mode gives an `Rlgl.Bound`: only `Rlgl.Bound.load_texture`,
  `load_texture_depth`, `attach`, `complete` and `disable` take it (rlsw would
  draw into the attachments, which Jonlib reaches through `BeginTextureMode`
  only), and the last three give the frame back.
- **A render texture.** `Rlgl.render_texture(fb, texture, depth_id)` is the
  `RenderTexture` of a complete framebuffer whose attachments are that
  texture and that depth id; None otherwise, because rlsw draws into what is
  attached whatever the struct says. The depth values are kept by
  framebuffer id, as for `LoadRenderTexture`.
- **Without a color attachment.** A shadow map's framebuffer has a depth
  attachment alone, so rlsw finds it incomplete and, while it is bound,
  refuses `swBegin` (the vertices after it are dropped), `swClear` and
  `swDrawArrays`: nothing is drawn or cleared, not even its depth.
  `Rlgl.render_texture_depth(fb, width, height, depth_id)` is that
  `RenderTexture` (texture id 0 with the size the struct says, 1 to 4096;
  None for framebuffer 0, for one with a color attachment and for another
  depth id). `BeginTextureMode` with it sets the viewport, the projection of
  that size, the modelview and every state as usual (the clear color of a
  `ClearBackground` too) and drops the draws and the clears until
  `EndTextureMode`, which hands it back.
- **Bound to draw.** A deferred renderer binds its G-buffer with
  `rlEnableFramebuffer` and draws. Its position and normal textures have a
  float format (`R16G16B16`), which rlgl does not support under OpenGL 1.1:
  `rlLoadTexture` warns and answers the id of a texture without storage, the
  framebuffer colored by it is incomplete (channels 1 and 2 never attach),
  and rlsw drops every draw and clear while it is bound.
  `Rlgl.enable_framebuffer_incomplete(frame, fb)` is that binding: unlike
  `BeginTextureMode` the viewport and the projection stay the screen's, the
  states are set as usual (`rlClearColor` there is the clear color of the
  screen's next `rlClearScreenBuffers`), and `Rlgl.disable_framebuffer`
  gives the screen back. `Rlgl.bind_framebuffer(frame, target, fb)` is
  `swBindFramebuffer` whatever the target: `Rlgl.Framebuffer.none()` is
  `rlDisableFramebuffer`. A complete framebuffer is refused in both (rlsw
  would draw into its attachments with the screen's viewport: use
  `BeginTextureMode`). A texture without storage draws like a depth one: its
  rectangle in the tint alone.
- **Cubemaps and clip planes.** `rlLoadTextureCubemap` has no body under
  OpenGL 1.1: `Rlgl.load_texture_cubemap(frame, data, size, format, mipmaps)`
  answers id 0 (as `LoadTextureCubemap` keeps), so a skybox's cube is drawn
  with its material's diffuse map alone (`models_skybox_rendering`).
  `Rlgl.get_cull_distance_near()` and `Rlgl.get_cull_distance_far()` are
  rlgl's defaults (0.05 and 4000.0) as binary64 values; `rlSetClipPlanes` is
  not exposed.
- **Unloading.** `rlUnloadFramebuffer` deletes the depth attachment with the
  framebuffer: pass its `Texture`, or None when it was unloaded before.
- **A depth attachment as a texture.** rlsw binds it but turns texturing
  off for a texture of a depth format, so `DrawTexture(target.depth, ...)`
  draws its rectangle in the tint alone; the `Texture` without texels that
  `Rlgl.load_texture_depth` gives draws the same way
  (`shaders_depth_rendering`).

Gate `rlgl-framebuffer` (`tools/rlgl_framebuffer_probe.py`) compares the ids
and the completeness answers of sixteen scenarios with the reference: the
examples' loader with and without `rlEnableFramebuffer`, a depth attachment
of another size, the ignored channels, texture types, the color texture as
the depth attachment, framebuffer 0, the ids after an unload, two
framebuffers, `LoadRenderTexture` after a hand-built one, and the float
texture formats. Five of them compare the screen's pixels too: around a
texture mode on a framebuffer without a color attachment (a clear and a
rectangle that are dropped, the projection and the active framebuffer inside
it, the clear color it leaves, a framebuffer without any attachment,
`LoadRenderTexture` reusing the id afterwards) and around a G-buffer bound
with `rlEnableFramebuffer` and `rlBindFramebuffer` (what is dropped, the
clear color, its float texture drawn). Sixteen contracts cover the refusals.
The ports `shaders_depth_writing`, `shaders_hybrid_rendering` and
`shaders_depth_rendering` draw through a framebuffer built this way and
compare every frame with the native example.
The port `shaders_shadowmap_rendering` builds its shadow map with a depth
attachment alone (`Rlgl.render_texture_depth`): its first pass reaches no
buffer and the scene on the screen is the reference's, unshadowed.
The port `shaders_deferred_rendering` binds its G-buffer to draw
(`Rlgl.enable_framebuffer_incomplete`): nothing reaches it, and the screen
shows the lights alone, or a G-buffer texture as rlsw draws it.

## Gaps

- `rlTextureParameters`, `rlEnableStatePointer`/`rlDisableStatePointer`,
  `rlDrawVertexArray`/`rlDrawVertexArrayElements` (rlsw's client arrays) and
  `rlBindFramebuffer` are not exposed. The vertex array, buffer, shader
  object, compute and storage buffer functions are, as what the software path
  leaves of them: ids 0, locations -1, nothing else. Their trace-log warnings
  are not reproduced.
- Framebuffer objects (below): `rlLoadTexture` with pixel data or another
  format than R8G8B8A8, more than one color attachment, cubemap faces as
  separate attachments, and drawing into a framebuffer bound with
  `rlEnableFramebuffer` (the type `Rlgl.Bound` has no draw function; use
  `BeginTextureMode`).
- `BeginMode3D` and the
  `rmodels.c` 3D shapes, and meshes and models drawn with
  `DrawMesh`/`DrawModel` (rlgl's vertex arrays into rlsw's
  `swDrawArrays`/`swDrawElements`), are in [MODELS.md](MODELS.md);
  `rlEnableStatePointer` and the vertex-array calls are not exposed.
- Segment estimation under the Apple and glibc 2.41 profiles and
  `DrawSplineBezierCubic` under glibc 2.41 are refused, not approximated.
- `rlOrtho`/`rlFrustum` outside the exact binary32 domain need a binary64
  evaluation of rlsw's `double` arithmetic.
