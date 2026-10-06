# Public API: current profiles

Import `jonlib.bend` as `J` for core operations and `jonmath.bend` as `M` for math
operations and shared vector/matrix types. See [MODULES.md](MODULES.md) for the
`ray*` → `jon*` naming convention and import migration.
This is a source library for the Bend 2.0.27 base plus the compiler overlay in
`toolchain.json`. Helpers with further dotted suffixes
are implementation details; only operations listed here form this initial API.

## Color

Colors are `U32` words in **0xRRGGBBAA** order, matching raylib's `GetColor` and
the unsigned bit pattern returned by `ColorToInt`.

- `Color.rgba(r, g, b, a) -> U32`: keeps the low eight bits of each U32 channel,
  equivalent to conversion to C unsigned bytes.
- `Color.red/green/blue/alpha(color) -> U32`: extract an 8-bit channel.
- `Color.alpha_blend(destination, source, tint) -> U32`: raylib's integer
  `ColorAlphaBlend`, including 256-based tint and alpha rounding.
- `Color.is_equal(left, right) -> Bool`: exact RGBA equality.
- `Color.with_alpha(color, factor) -> U32`: `ColorAlpha`/`Fade`; finite factor
  clamped to 0..1, replacing alpha with the truncated `255*factor` value.
- `Color.multiply(color, tint) -> U32`: `ColorTint`'s channel multiplication
  divided by 255, including alpha. The internal alpha-blend tint is different.
- `Color.brightness(color, factor)` and `Color.contrast(color, factor)`: finite
  factors clamped to -1..1 with reference byte truncation; alpha is retained.
- `Color.lerp(first, second, factor)`: straight RGBA interpolation with a finite
  factor clamped to 0..1; this does not perform alpha blending.
- `Color.normalize(color) -> Vector4`: exact reference RGBA normalization by 255.
- `Color.from_normalized(vector) -> U32`: finite RGBA components in 0..1,
  multiplied by 255 in F32 and truncated to bytes.
- `Color.to_hsv(color) -> Vector3`: hue in degrees, saturation and value in 0..1;
  ignores alpha and returns zero hue/saturation for achromatic colors.
- `Color.from_hsv(hue, saturation, value) -> U32`: hue 0..360 and saturation/value
  0..1; preserves reference sector arithmetic and byte truncation, with alpha 255.
  Wider hue inputs remain outside this profile. RGB→HSV→RGB is not promised to
  recover every byte, because the reference itself rounds intermediate values.

The public scalar and Vector2 operations are listed in [MATH.md](MATH.md),
including their explicit uncontracted-F32 profile and remaining numeric gaps.
The three checked `*_with_reference` angle APIs use the separate
`M.Angle.Reference` and return `Maybe<F32>`; see [CHECKED-ANGLES.md](CHECKED-ANGLES.md).
Pure geometry queries are listed in [COLLISION.md](COLLISION.md), including
strict rectangle edges and inclusive circle tangency.
Spline point queries and their explicit arithmetic profiles are listed in
[SPLINES.md](SPLINES.md).
Owned random-stream APIs and their native rprand profile are described in
[RANDOM.md](RANDOM.md).
Pixel sizing, raw byte/integer reads and writes, and packed dithering are
documented in [PIXELS.md](PIXELS.md).
Owned byte/integer image conversion and Surface bridges are documented in
[FORMATS.md](FORMATS.md).
Bounded raw DEFLATE and its reference-specific empty-block behavior are documented
in [DEFLATE.md](DEFLATE.md).
Native Base64 text, NUL-inclusive encoded sizes and bounded decoding are
documented in [BASE64.md](BASE64.md).
Bounded native CRC32 and four-word MD5 results are documented in
[CHECKSUMS.md](CHECKSUMS.md).
Native SHA-1/SHA-256 word lists, including the reference SHA-256 padding quirk,
are documented in [SHA.md](SHA.md).
Bounded quality-8 raw compression, including empty-input and native sequence-limit
behavior, is documented in [COMPRESSION.md](COMPRESSION.md).

## Owned RGBA8 surfaces

`Vector2` is immutable Jonmath `Data`, constructed as `M.Vector2{x, y}` with F32 fields.
Reusable local constructor bindings need a type annotation, for example
`+point = {M.Vector2{1.0, 2.0} : M.Vector2}`.
`Rectangle` is `Data` with F32 `x`, `y`, `width`, `height` fields. The current
crop/extraction/region-drawing profile requires integral rectangle values;
`draw_image_rect` and the documented rectangle wrappers also support fractional fields.

`M.Angle.Reference` has `M.Apple2007AngleRn{}`, `M.Sun239AngleRn{}` and
`M.Glibc241AngleRn{}` constructors. They name numerical contracts; fresh native
qualification is separate. Existing `Gradient.Reference` APIs retain their meanings.

`M.Vector3{x, y, z}` is immutable `Data` with three F32 fields.
`M.Vector4{x, y, z, w}` provides four immutable F32 fields.
`J.BoundingBox{min, max}` contains two `M.Vector3` values; supplied bounds are retained
without reordering. Their numeric and collision operations are documented in
[MATH.md](MATH.md) and [COLLISION.md](COLLISION.md).
Jonmath's `M.Matrix` contains 16 F32 fields in the reference declaration order; its layout,
identity/transpose operations and vector transforms are listed in [MATH.md](MATH.md#matrix-api).
`M.Matrix.Decomposition` contains `M.Decomposed{translation, rotation, scale}` with
Vector3/Vector4/Vector3 fields, adapting the three distinct outputs of decomposition.
`M.Float64{high, low}` retains binary64 input bits for projection matrices;
`M.Float64.from_f32` promotes existing F32 values. Precision and supported domains
are detailed in [MATH.md](MATH.md#binary64-projection-inputs).

`Surface` owns its row-major pixel array. Always start with `Surface.create`:
the underlying constructor is visible because Bend does not provide the needed
opaque user-type facility, but manually constructing an inconsistent surface
is outside this API's contract.

| Operation | Contract |
|---|---|
| `Surface.create(width, height, color) -> Maybe<Surface>` | Dimensions 1..4096 on each axis; otherwise `None`. Storage is rounded up to a power of two, with padding excluded from exports. |
| `Surface.create_checked(width, height, tile_width, tile_height, first, second) -> Maybe<Surface>` | Reference checkerboard generation. Dimensions 1..4096, checker sizes 1..2147483647; invalid values return `None` before allocation/division. |
| `Surface.create_white_noise(state, width, height, factor) -> Random.State & Maybe<Surface>` | Owned-stream RGBA8 white noise, dimensions 1..4096 and factor 0..1. Returns the advanced stream on success or the original stream with `None` on invalid input. |
| `Surface.create_cellular(state, width, height, tile_size) -> Random.State & Maybe<Surface>` | Owned-stream cellular RGBA8 generation; dimensions/tile size 1..4096. Rejected requests retain the original stream. Exact seed/distance rules are in [CELLULAR.md](CELLULAR.md). |
| `Surface.create_perlin(width, height, offset_x, offset_y, scale)` / `create_perlin_for(reference, ...)` | Six-octave RGBA8 Perlin noise returning Maybe; explicit fused/uncontracted profiles and bounded inputs. See [PERLIN.md](PERLIN.md). |
| `Surface.create_text_bytes(width, height, bytes) -> Maybe<Surface>` | Grayscale data-image from bytes, stopping at NUL and padding/truncating to dimensions; opaque RGBA8 output. See [PALETTES.md](PALETTES.md). |
| `Surface.create_gradient_square(width, height, density, inner, outer) -> Maybe<Surface>` | Square gradient with dimensions 1..4096 and finite density 0..1. Invalid requests return `None`; density one produces the inner color, matching the reference clamp behavior. |
| `Surface.create_gradient_radial(width, height, density, inner, outer)` | Same Maybe result, dimensions 1..4096 and density 0..1; reference radial RGBA interpolation with balanced generation. |
| `Surface.create_gradient_linear(width, height, direction, start, end)` | Same Maybe result; integral directions -360..360. Rejects invalid sizes/directions and a zero reference normalization extent. Wider-angle libm parity remains open; see [GRADIENTS.md](GRADIENTS.md). |
| `Surface.create_gradient_linear_for(reference, width, height, direction, start, end)` | Jonmath's explicit `M.Gradient.Reference`: `M.AccurateGradient{}` or `M.GnuGradient{}`. Selects reference numerical behavior; see [GRADIENTS.md](GRADIENTS.md). |
| `Surface.dimensions(surface) -> U32 & U32` | Consumes a surface and returns its dimensions. |
| `Surface.clear(surface, color) -> Surface` | Replaces all pixels; preserves dimensions. |
| `Surface.get(surface, x, y) -> Surface & Maybe<&2, U32>` | Returns ownership and the pixel; out-of-bounds U32 coordinates return `None`, never wrap. |
| `Surface.draw_pixel(surface, x, y, color) -> Surface` | Replaces RGBA bytes at an in-bounds pixel; clips outside coordinates. |
| `Surface.draw_pixel_v(surface, position, color)` | Truncates bounded finite Vector2 coordinates before pixel clipping. |
| `Surface.draw_rectangle(surface, x, y, width, height, color) -> Surface` | Matches raylib 6.0 CPU `ImageDrawRectangle` for the declared integer-coordinate profile. |
| `Surface.draw_rectangle_v(surface, position, size, color)` | Truncates both vectors before drawing. |
| `Surface.draw_rectangle_rec(surface, rectangle, color)` | Clips bounded finite rectangle fields before converting pixel coordinates/extents to integers. |
| `Surface.draw_rectangle_lines(surface, rectangle, thickness, color)` | Four reference edge strips, including derived-coordinate truncation and degenerate behavior; thickness 0..32767. |
| `Surface.draw_circle(surface, cx, cy, radius, color) -> Surface` | Matches raylib 6.0 CPU `ImageDrawCircle` midpoint coverage; radius is U32. |
| `Surface.draw_circle_v(surface, center, radius, color)` | Truncates the bounded finite center before filled circle drawing. |
| `Surface.draw_circle_lines(surface, cx, cy, radius, color)` / `draw_circle_lines_v(surface, center, radius, color)` | Reference midpoint outlines, including radius zero and clipping. Vector centers are truncated. |
| `Surface.draw_line(surface, x0, y0, x1, y1, color) -> Surface` | Integral F32 endpoints; matches `ImageDrawLine` fixed-point stepping and excludes the final endpoint. A zero-length line draws nothing. |
| `Surface.draw_line_v(surface, start, end, color) -> Surface` | Vector2 endpoints; applies raylib's F32 `coordinate + 0.5` followed by truncation toward zero before drawing. |
| `Surface.draw_line_ex(surface, start, end, thickness, color)` | Reference add-half/truncate endpoints, dominant-axis strips and even-thickness bias; thickness 0..32767. |
| `Surface.draw_triangle(surface, v1, v2, v3, color) -> Surface` | Finite Vector2 vertices; bounds and edge steps are truncated to integers as in raylib. Matches `ImageDrawTriangle` winding, inclusive edge tests, clipping and degenerate behavior. |
| `Surface.draw_triangle_lines(surface, v1, v2, v3, color) -> Surface` | Vector2 vertices truncated toward zero, then three reference-compatible line segments. |
| `Surface.draw_triangle_ex(surface, v1, v2, v3, c1, c2, c3)` | Reference coverage and byte-quantized barycentric color weights. Fractional vertices follow the same truncation; requires defined signed arithmetic and nonzero reference weight sum. |
| `Surface.draw_triangle_fan(surface, points, color)` / `draw_triangle_strip(surface, points, color)` | Immutable `+List<Vector2>` of finite vertices, each triangle drawn as `draw_triangle`; reference vertex order/winding. Fewer than three points draws nothing. |
| `Surface.draw_image(destination, source, x, y, tint) -> Surface & Surface` | Full-source, unscaled RGBA8 drawing; clips destination placement, applies integer tint/alpha blending, returns destination then unchanged source. |
| `Surface.extract(surface, rectangle) -> Surface & Maybe<Surface>` | Retains the original; returns an independent region for positive integral in-bounds rectangles, otherwise `None`. |
| `Surface.crop(surface, rectangle) -> Result<&1, &1, Surface & Surface.Error, Surface>` | Clips an integral rectangle as raylib does; returns the cropped surface or the original with an error. An origin strictly beyond the right/bottom edge is the reference no-op. |
| `Surface.resize_nn(surface, width, height) -> Result<&1, &1, Surface & Surface.Error, Surface>` | Exact fixed-point nearest mapping; positive dimensions up to 4096; refuses out-of-allocation reference mappings. |
| `Surface.resize(surface, width, height) -> Result<&1, &1, Surface & Surface.Error, Surface>` | Default filtered RGBA8 resize; dimensions 1..4096; Catmull-Rom upsampling, Mitchell downsampling, clamp edges and alpha-aware filtering. Invalid sizes return the original owner with `InvalidSize`. |
| `Surface.resize_canvas(surface, width, height, offset_x, offset_y, fill)` | Same single-owner Result. Raw RGBA copy into a filled canvas; dimensions 1..4096, bounded integral offsets. Unchanged dimensions are a no-op. Changed sizes require positive overlap; invalid sizes/rectangles return the original owner. |
| `Surface.draw_image_region(destination, source, rectangle, x, y, tint)` | Returns `Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>`; valid unscaled source subrectangles with integer placement, preserving both owners. |
| `Surface.draw_image_rect(destination, source, source_rectangle, destination_rectangle, tint)` | Same two-owner Result. Bounded finite rectangles, including fractional fields; source clipping, default filtered scaling and destination clipping follow reference order. Empty/invalid rectangles return both originals with `InvalidRectangle`. |
| `Surface.color_tint`, `color_invert`, `color_contrast`, `color_brightness`, `color_replace` | Owned RGBA8 transforms described below. |
| `Surface.color_grayscale(surface) -> Surface` | Reference luminance conversion with opaque grayscale RGBA8 output; alpha is discarded. See [PALETTES.md](PALETTES.md). |
| `Surface.load_palette(surface, maximum) -> Surface & Maybe<Image.Palette>` | Preserves source; first-occurrence RGBA colors excluding alpha zero, with exact count and full padded capacity. Capacity 1..4096; access/disposal in [PALETTES.md](PALETTES.md). |
| `Surface.dither(surface, r_bits, g_bits, b_bits, a_bits)` | Returns an owned `Image.Packed16` or original source with `InvalidDitherBits`; channel widths 0..8 totaling at most 16. Exact raw format/export rules in [PIXELS.md](PIXELS.md). |
| `Surface.alpha_clear(surface, color, threshold)` | Finite threshold 0..1, converted to an inclusive alpha-byte cutoff; replaces all RGBA bytes at matching pixels. |
| `Surface.alpha_premultiply(surface)` | Reference F32 alpha multiplication of RGB, including transparent-black conversion; retains alpha. |
| `Surface.blur_gaussian(surface, size)` | Native four-iteration RGBA8 box approximation with premultiplied alpha and per-pass byte truncation. U32 size 0..min(width,height); invalid sizes retain the original with `InvalidSize`. See [BLUR.md](BLUR.md). |
| `Surface.kernel_convolution(surface, kernel)` | Native bounded RGBA8 square-kernel filtering, flat-index edge behavior and unclamped alpha. Unsupported kernels/results retain the original with `InvalidKernel`. See [CONVOLUTION.md](CONVOLUTION.md). |
| `Surface.alpha_mask(destination, mask)` | Same-size RGBA8 mask converted to reference grayscale values, replacing destination alpha while preserving the original mask. Returns the two-owner Result; mismatched dimensions return both originals with `InvalidSize`. |
| `Surface.alpha_border(surface, threshold) -> Surface & Rectangle` | Retains the original and finds pixels with alpha strictly above the truncated threshold byte. Finite threshold 0..1; empty selections return `(0,0,0,0)`. |
| `Surface.alpha_crop(surface, threshold) -> Surface` | Crops to nonempty alpha bounds; empty selections retain the original image and dimensions unchanged. |
| `Surface.colors(surface) -> List<U32>` | Consumes the image and exports exactly width × height packed pixels, row-major. |
| `Surface.copy(surface) -> Surface & Surface` | Returns the original and an independently owned pixel copy. |
| `Surface.mipmaps(surface)` / `Image.Mipmaps.entries/unload` | Consume RGBA8 into an owned base-to-1x1 chain using sequential default filtering; exact level counts, dimensions and pixels are documented in [MIPMAPS.md](MIPMAPS.md). |
| `Surface.flip_horizontal/flip_vertical(surface) -> Surface` | Reorders whole RGBA pixels; dimensions and alpha bytes are preserved. |
| `Surface.rotate_cw(surface)` / `rotate_ccw(surface)` | Quarter-turn rotations preserving exact RGBA bytes and swapping width/height. |
| `Surface.rotate_degrees(surface, degrees)` / `rotate_degrees_for(reference, surface, degrees)` | Single-owner Result; integral degrees -360..360, reference bilinear sampling and truncated output dimensions. Invalid angles/output sizes preserve the original owner. See [ROTATION.md](ROTATION.md). |
| `Surface.to_pot(surface, fill)` | Single-owner Result; raw canvas expansion to the next power-of-two dimensions, preserving the reference no-op for already-POT images. |
| `Surface.from_channel(surface, selected) -> Surface & Surface` | Returns the unchanged original, then an independent opaque grayscale RGBA8 image. Integral selectors in -32767..32767 clamp to 0..3 (RGBA). Equivalent to `ImageFromChannel` followed by RGBA8 normalization; native grayscale storage and other input formats remain gaps. |
| `Surface.to_image(surface) -> Image` | Consumes the surface and builds a Base.Image quadtree. RGB is retained, alpha discarded; padded regions are black. |
| `Surface.to_ppm(surface) -> String` | Consumes the surface and encodes P3 PPM text (RGB, alpha discarded). |
| `Surface.write_ppm(surface, path) -> IO(Result<&1, &1, U32 & String, Unit>)` | Writes P3 PPM through Base.File; returns open/write errors and closes the file after writing. |
| `Surface.decode_qoi`, `to_qoi`, `load_qoi`, `write_qoi` | QOI memory/file APIs, typed errors and RGBA8 normalization are specified in [CODECS.md](CODECS.md). |
| `Surface.load_image(path)` | Bounded PNG/BMP/TGA/PGM/PPM/QOI file loading with native supported suffix/content selection, closed handles and typed errors; see [IMAGE-FILES.md](IMAGE-FILES.md). |
| `Surface.decode_image(file_type, bytes)` | Shared native-style memory dispatch for the implemented codec profiles, exact lower/upper-case extension tokens and typed decode errors; aliases and limits in [IMAGE-FILES.md](IMAGE-FILES.md). |
| `Surface.decode_bmp`, `to_bmp`, `write_bmp` | CORE indexed/RGB24 plus 40/56/108/124-byte-header indexed, byte-color and 16/32-bit bitfield decoding; exact RGBA8 V4 export. Native rules in [BMP.md](BMP.md). |
| `Surface.decode_tga`, `to_tga`, `write_tga` | Bounded raw/RLE direct/indexed decoding with native type/depth, RGB555 and palette behavior; byte-exact default RLE export. Formats and limits in [TGA.md](TGA.md). |
| `Surface.decode_pnm` | Binary 8/16-bit P5/P6 decoding with native unscaled samples, little-endian 16-bit normalization and header parsing; see [PNM.md](PNM.md). |
| `Surface.decode_psd` | Raw/PackBits RGB/alpha PSD planes with native depth interpretation, missing-channel defaults, uncontracted matte arithmetic and typed bounds; see [PSD.md](PSD.md). |
| `Surface.decode_psd_for(reference, bytes)` | Raw/PackBits RGB/alpha PSD profiles with explicit fused/uncontracted white-matte arithmetic. `decode_psd` selects uncontracted; see [PSD.md](PSD.md). |
| `Surface.decode_pic(bytes)` | Raw/pure-RLE/mixed-RLE Softimage PIC packets, native clipping/defaults/overwrite order and checked bounds; see [PIC.md](PIC.md). |
| `Surface.decode_gif(bytes)` | First-frame GIF with in-canvas rectangles, interlacing, native background fills, palettes/transparency and bounded LZW; see [GIF.md](GIF.md). |
| `Image.Animation.decode_gif(bytes, maximum_frames, maximum_pixels)` | Owned GIF frame sequence with caller budgets and native retain/restore disposal profiles; see [GIF-ANIMATION.md](GIF-ANIMATION.md). |
| `Image.Animation.decode_image(file_type, bytes, maximum_frames, maximum_pixels)` / `decode_image_for(reference, ...)` | Exact GIF-token sequence selection or one-frame profiled image fallback, retaining owned budgets and errors; see [GIF-ANIMATION.md](GIF-ANIMATION.md). |
| `Image.Animation.load_image(path, maximum_frames, maximum_pixels)` / `load_image_for(reference, ...)` | Bounded ordinary-file animation loading with case-insensitive GIF suffixes, static fallback, closed handles and typed file/decode errors; see [GIF-ANIMATION.md](GIF-ANIMATION.md). |
| `Image.Animation.entries(animation)` / `unload(animation)` | Consume the animation to return `(width, height, count, List<Surface>)` or dispose of the owned frames. |
| `Image.FloatRGB.decode_hdr(bytes)` | Owned raw/scanline-RLE Radiance RGBE data with exact native F32 bits, including subnormals; see [HDR.md](HDR.md). |
| `Image.FloatRGB.load_hdr(path)` | Explicit HDR file selection, 1 MiB byte cap, complete reads, closed handles and typed errors; returns owned RGB float pixels. See [HDR.md](HDR.md). |
| `Image.FloatRGB.entries(image)` / `unload(image)` | Consume a float image to return `(width, height, List<M.Vector3>)` or dispose of its owned pixels. |
| `Surface.to_float_rgb(surface)` / `Image.FloatRGB.to_surface(image)` | Native format-7/9 RGB normalization and checked opaque RGBA8 conversion. Rejection returns the original float owner; see [FLOAT-RGB.md](FLOAT-RGB.md). |
| `Image.FloatRGB.from_bytes(width, height, bytes)` / `to_bytes(image)` | Exact non-NaN little-endian format-9 words, checked dimensions/lengths and rejected-owner preservation; see [FLOAT-RGB-BYTES.md](FLOAT-RGB-BYTES.md). |
| `Image.FloatRGB.copy(image)` | Returns the original float owner and an independent clone. See [FLOAT-RGB.md](FLOAT-RGB.md#copy-and-lossless-orientation). |
| `Image.FloatRGB.flip_horizontal/flip_vertical/rotate_cw/rotate_ccw` | Consume the float owner and preserve exact sample words; quarter-turns swap dimensions. See [FLOAT-RGB.md](FLOAT-RGB.md#copy-and-lossless-orientation). |
| `Image.FloatRGB.extract(image, rect)` / `crop(image, rect)` | Independent integral regions or clipped crops with exact sample words and retained rejected owners; see [FLOAT-RGB.md](FLOAT-RGB.md#rectangular-extraction-and-crop). |
| `Image.FloatRGB.resize_nn(image, width, height)` | Native format-9 RGBA8-quantized nearest resizing with retained original owners on unsupported samples/sizes/mappings; see [FLOAT-RGB.md](FLOAT-RGB.md#native-nearest-neighbor-resizing). |
| `Image.FloatRGB.resize(image, width, height)` | Native format-9 RGBA8-quantized default filtering with retained owners; see [FLOAT-RGB.md](FLOAT-RGB.md#native-nearest-neighbor-resizing). |
| `Image.FloatRGB.resize_canvas(image, width, height, x, y, fill)` / `to_pot(image, fill)` | Native lossless movement, ignored float-format fill color, bounded offsets and retained rejected owners; see [FLOAT-RGB.md](FLOAT-RGB.md#canvas-resizing-and-pot-growth). |
| `Image.FloatRGB.color_tint/color_invert/color_contrast/color_brightness/color_replace` | Native format-9 byte-quantized color paths with preserved rejected owners; see [FLOAT-RGB.md](FLOAT-RGB.md#native-color-transforms). |
| `Image.FloatRGB.to_formatted(image, target)` / `color_grayscale(image)` | Direct finite `[0,1]` native normalized conversion to formats 1..8 (R32 uses uncontracted F32 luminance), or grayscale format 1, retaining rejected float owners; see [FLOAT-RGB.md](FLOAT-RGB.md#direct-byteinteger-formats-and-grayscale). |
| `Image.Formatted.decode_bmp(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Image.Formatted>` | Entire checked BMP memory profile with native RGB888 (4) or RGBA8888 (7), implicit one mip and exact raw row-major bytes; effective alpha layout determines channels before pixel decoding or alpha repair. Existing 1..4096 bounds and typed errors apply; no encoded memory cap. See [BMP.md](BMP.md#format-preserving-bmp-memory-loading). |
| `Image.Formatted.decode_pic(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Image.Formatted>` | Entire checked PIC memory domain with native RGB888 (4) or RGBA8888 (7), implicit one mip and exact raw bytes. The union of all validated packet masks selects alpha independently of opacity, packet order and selected-sample totals. Existing 1..4096 bounds, raw/pure/mixed RLE and typed-error precedence remain unchanged; no encoded-memory cap. Fresh local Linux CPU-1/CPU-2/JavaScript qualification passes with complete raw-byte replay; the exact [86-gate e481d3c hosted memory checkpoint](https://github.com/jonathanperis/jonlib/actions/runs/37202964890) also passes its recorded Ubuntu/macOS CPU/JavaScript gates. Later PIC-file qualification is separate. See [PIC.md](PIC.md#format-preserving-pic-memory-loading). |
| `Image.Formatted.decode_png(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Image.Formatted>` | Entire checked PNG memory domain with native grayscale (1), gray-alpha (2), RGB888 (4) or RGBA8888 (7), implicit one mip and exact 8-bit component bytes. Structural tRNS promotes channels independently of opacity and remains sticky through later PLTE; 16-bit keys compare before high-byte reduction. Existing inclusive 1 MiB encoded/64 MiB filtered caps, 1..4096 dimensions, CgBI defaults and typed-error precedence are unchanged. Fresh local Linux CPU-1/CPU-2/JavaScript qualification passes; hosted qualification remains pending. See [PNG.md](PNG.md#format-preserving-png-memory-loading). |
| `Image.Formatted.decode_tga(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Image.Formatted>` | Checked TGA memory decoding preserving native grayscale (1), gray-alpha (2), expanded RGB888 (4) or RGBA8888 (7), implicit single mip and exact raw bytes; palette depth determines indexed output independently of index width. Existing 1..4096 bounds and typed errors apply. See [TGA.md](TGA.md#format-preserving-tga-memory-loading). |
| `Image.Formatted.decode_pnm(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Image.Formatted>` | Checked binary P5/P6 memory decoding preserving native grayscale (1) or RGB888 (4), single-mip dimensions and exact reduced 8-bit output; dimensions 1..4096, maxval 1..65535 and existing checked little-endian parsing/errors. See [PNM.md](PNM.md#format-preserving-pnm-memory-loading). |
| `Image.Formatted.decode_qoi(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Image.Formatted>` | Checked single-mip QOI memory decoding preserving native RGB888 (4) or RGBA8888 (7) metadata and exact raw bytes; dimensions 1..4096 and existing strict typed errors. See [CODECS.md](CODECS.md#format-preserving-qoi-memory-loading). |
| `Image.Formatted.load_pic(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)` | Explicit, suffix-independent PIC file selection preserving native RGB888 (4)/RGBA8888 (7), implicit one mip and exact raw bytes. Inclusive 1,048,576-byte RasterFile cap before one exact-length read, Base U32-size overflow, exact file/decode errors and close-before-decode calls; Base ignores close failures. PIC memory remains uncapped and unchanged. Fresh local CPU-1/CPU-2/JavaScript file qualification and complete retained-byte replay pass; exact-tip hosted qualification remains pending. See [IMAGE-FILES.md](IMAGE-FILES.md#format-preserving-pic-file-loading). |
| `Image.Formatted.load_png(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)` | Explicit, suffix-independent PNG file selection preserving native grayscale (1), gray-alpha (2), RGB888 (4) or RGBA8888 (7), implicit one mip and the unchanged checked PNG memory domain. Inclusive 1,048,576-byte RasterFile cap before one exact-length read; close-before-decode calls and unchanged Base code/message errors. The decoder retains its separate inclusive 1 MiB encoded/64 MiB filtered limits. Fresh local Linux CPU-1/CPU-2/JavaScript file qualification passes 370 accepted files, 219 checked-only controls and 2,846 primary observations / 1,531,636 bytes per lane, plus independently replayed boundary/sparse/exact-cap records; the historical [85-gate hosted checkpoint](https://github.com/jonathanperis/jonlib/actions/runs/37187107908) at `e6ac05e6` passes with twelve workers, both aggregates and twelve unique nonempty artifacts. Later increments need separate hosted qualification. See [IMAGE-FILES.md](IMAGE-FILES.md#format-preserving-png-file-loading) and [file evidence](evidence/png-formatted-files.json). |
| `Image.Formatted.load_bmp(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)` | Explicit, suffix-independent BMP file selection preserving native RGB888 (4)/RGBA8888 (7), implicit one mip and the unchanged checked 1..4096 memory domain. Inclusive 1,048,576-byte raster cap, one exact-length read, close-before-decode calls and typed errors; Base ignores close errors. Local Linux CPU-1/CPU-2/JavaScript file qualification and the historical [83-gate hosted checkpoint](https://github.com/jonathanperis/jonlib/actions/runs/37161146356) at `1312479c` pass; later increments need separate hosted qualification. See [IMAGE-FILES.md](IMAGE-FILES.md#format-preserving-bmp-file-loading). |
| `Image.Formatted.load_qoi(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)` | Explicit, suffix-independent QOI file selection preserving native format 4/7, single-mip dimensions and exact raw bytes; inclusive 83,886,102-byte cap, complete reads, close-before-decode ordering and typed errors. See [IMAGE-FILES.md](IMAGE-FILES.md#format-preserving-qoi-file-loading). |
| `Image.Formatted.load_pnm(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)` | Explicit, suffix-independent binary P5/P6 file selection preserving native grayscale (1)/RGB888 (4), implicit single-mip dimensions and exact reduced 8-bit samples; inclusive 1,048,576-byte raster cap, complete reads, close-before-decode calls and typed errors. See [IMAGE-FILES.md](IMAGE-FILES.md#format-preserving-pnm-file-loading). |
| `Image.Formatted.load_tga(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)` | Explicit, suffix-independent TGA file selection preserving native grayscale (1), gray-alpha (2), expanded RGB888 (4) or RGBA8888 (7), implicit single mip and the existing checked 1..4096 memory domain. Inclusive 1,048,576-byte raster cap, one exact-length read, close-before-decode calls and typed errors. Local Linux CPU-1/CPU-2/JavaScript file qualification and the historical 81-gate TGA-file checkpoint pass; later increments require their own exact-tip hosted qualification. See [IMAGE-FILES.md](IMAGE-FILES.md#format-preserving-tga-file-loading). |
| `Image.Formatted.to_float_rgb(image)` | Consume formats 1..8 into native normalized RGB float storage, preserving packed-channel precision and R32 red-only sample bits while dropping alpha; see [FLOAT-RGB.md](FLOAT-RGB.md#direct-byteinteger-formats-and-grayscale). |
| `Image.Formatted.from_channel(image, selected)` / `Image.FloatRGB.from_channel(image, selected)` | Retain the source and return an independent native grayscale channel with format-specific selector rules; see [IMAGE-CHANNELS.md](IMAGE-CHANNELS.md). |
| `Image.Formatted.colors/get` / `Image.FloatRGB.colors/get` | Native bulk and point RGBA observations with packed integer expansion, float truncation and retained point/error owners; see [IMAGE-COLORS.md](IMAGE-COLORS.md). |
| `Image.Formatted.load_raw(path, width, height, format, header_size)` | Native RAW header selection for formats 1..7 and checked finite `[0,1]` R32 (8); exact words and metadata, bounded reads, closed handles and distinct `InvalidRawSamples` errors. Format 9 remains unsupported here. See [RAW-FILES.md](RAW-FILES.md). |
| `Image.FloatRGB.load_raw(path, width, height, header_size)` / `write_raw(image, path)` | Native RAW header selection and exact non-NaN RGB words; typed load/write errors, closed handles and retained owners on NaN write rejection. See [RAW-FILES.md](RAW-FILES.md#rgb-float-files). |
| `Surface.decode_image_for(reference, file_type, bytes)` / `Surface.load_image_for(reference, path)` | Shared dispatch with `J.Image.Decode.Reference`; affects PSD matte arithmetic and retains existing bounds/error/closure behavior. Convenience calls select `J.UncontractedDecode{}`. |
| `Surface.decode_png` | Bounded non-interlaced/Adam7 PNG and native-default CgBI decoding at supported 1/2/4/8/16-bit combinations; filtering, transparency and normalization in [PNG.md](PNG.md). |
| `Surface.to_png`, `write_png` | Consuming RGBA8 memory/file exports with byte-exact native default filtering, quality-8 compression and checksums; see [PNG-EXPORT.md](PNG-EXPORT.md). |
| `Surface.write_image(surface, path)` | ASCII-case-insensitive PNG/BMP/TGA/QOI/RAW suffix dispatch; pre-open unsupported-suffix errors retain the owner, selected file operations consume it and return typed IO errors; see [IMAGE-EXPORT.md](IMAGE-EXPORT.md). |
| `Image.Formatted.to_png` | Consuming PNG memory export preserving byte-format 1/2/3/4-channel data and R32's native raw-byte RGBA interpretation; unsupported packed formats return the original owner. See [PNG-EXPORT.md](PNG-EXPORT.md). |
| `Image.Formatted.to_bmp` / `write_bmp` | Consuming exact native BMP file bytes and explicit typed file IO for checked formats 1..8; 24-bit grayscale/gray-alpha/RGB and V4 packed/RGBA/R32 routing. See [FORMATTED-BMP-EXPORT.md](FORMATTED-BMP-EXPORT.md). |
| `Image.Formatted.to_qoi(image) -> Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>` / `write_qoi(image, path) -> IO(Result<&1, &1, Image.Formatted.QoiWriteError, Unit>)` | Explicit native QOI file bytes for original RGB888 (4) / RGBA8888 (7), header channels 3/4; other checked formats retain their exact owner before IO. Accepted writes consume the owner and close acquired handles. Local Linux x86-64 CPU-1/CPU-2/JavaScript evidence is recorded in [FORMATTED-QOI-EXPORT.md](FORMATTED-QOI-EXPORT.md). |
| `Image.Formatted.to_tga` / `write_tga` | Consuming exact native RLE TGA file bytes and explicit typed IO for checked formats 1..8; channel-preserving gray/gray-alpha/RGB and native packed/RGBA/R32 expansion. See [FORMATTED-TGA-EXPORT.md](FORMATTED-TGA-EXPORT.md). |
| `Image.Formatted.write_png` | Consuming PNG file export for checked formats 1..8, with native byte-channel/packed-color expansion and bounded R32 red-only normalization; see [PNG-EXPORT.md](PNG-EXPORT.md). |
| `Image.FloatRGB.to_png` / `write_png` | Preserve native raw-prefix memory PNG versus normalized-color file PNG, with retained rejected owners and typed file errors; see [PNG-EXPORT.md](PNG-EXPORT.md#rgb-float-memoryfile-distinction). |
| `Image.FloatRGB.to_bmp/to_tga` / `write_bmp/write_tga` | Native normalized BMP/TGA file bytes and explicit typed writers, preserving rejected owners; see [FLOAT-RASTER-EXPORT.md](FLOAT-RASTER-EXPORT.md). |
| `Image.Formatted.to_code(image, path)` / `write_code(image, path)` | Exact native image-as-code text, basename/hex/newline rules and typed owner-preserving failures; see [IMAGE-CODE.md](IMAGE-CODE.md). |
| `Image.FloatRGB.to_code(image, path)` / `write_code(image, path)` | Native format-9 image-as-code text from exact non-NaN sample bytes, bounded paths/payloads and typed owner-preserving failures; see [IMAGE-CODE.md](IMAGE-CODE.md). |

Drawing coordinates and rectangle extents are represented as **F32 but must be
finite integers in -32767..32767**. Radius is **0..32767**. This permits negative
positions while Bend has no native signed integer type. The vector wrappers,
`draw_rectangle_rec`, `draw_rectangle_lines` and `draw_image_rect` accept bounded
finite fractional fields with the conversion rules above, as do filled triangle
vertices (truncated like raylib's `int` casts). NaN/infinity and larger values are outside the drawing profile.
Surface operations do not promise successful allocation when the process runs
out of memory; Bend's runtime treats allocation failure as fatal.

Line stepping uses a signed 16.16 short-axis increment. The short-axis endpoint
delta must fit -32767..32767 after vector conversion. Triangle stepping uses
signed 32-bit edge words, seeded with the reference F32 expressions. The supported
contract requires the reference's integer calculations/conversions to be defined;
the finite fixture suite does not establish every floating-point/compiler edge case.

`ImageDraw*` operations replace bytes, including alpha. They do not implicitly
perform source-over blending. Applying an alpha-zero pixel can therefore leave
nonzero RGB with zero alpha, exactly as in the reference image operation.

### Degenerate rectangles and tiny circles

Raylib 6.0's accepted zero-width rectangles can still write their initial pixel;
zero-height rectangles can write their first row. Position/clipping conditions
also affect this behavior. Jonlib deliberately matches these observable CPU
image semantics, including their effect on radius-zero and circle scanlines.
These rules are covered by reference fixtures and are not generic mathematical
rectangle/circle definitions.

### Lines and triangles

`draw_line` omits its final endpoint, as raylib 6.0 does. Reversing a segment can
therefore change which end pixel is written. Negative short-axis increments use
arithmetic right-shift behavior, rather than truncating the interpolated position.
The vector-line API's add-half/truncate rule also differs from ordinary rounding
for negative values.

Filled triangle edges are stepped as integer words after their initial F32
calculation. Both windings are supported. A degenerate triangle is processed by
the same edge rules as raylib; it is not automatically discarded.

### Image drawing and ownership

Unlike the byte-replacing primitive draws, `draw_image` performs source-over
composition through raylib's integer `ColorAlphaBlend` rules. Destination and
source must be separately owned surfaces. Both are returned; the source's pixels
are unchanged and can be used for another draw. Use `Surface.copy` when a distinct
copy is needed.

This is a **partial ImageDraw profile**: RGBA8 and one mip level. The
`draw_image_rect` path clips source fields first, compares truncated extents to
decide whether to resize, then clips the destination before truncating pixel
indices/counts. It accepts fractional rectangles when the clipped source has at
least one pixel and truncated destination dimensions are 1..4096. The original
source remains unchanged, including when a temporary resized region is used.
Other formats, mipmaps, empty/undefined reference rectangles and full target/
performance coverage remain gaps.
Nearest-neighbor scaling is a separate API and is not substituted for raylib's
default `ImageResize` filtering behavior. See [RESAMPLING.md](RESAMPLING.md).

`Surface.resize` provides that default filtered path separately. It retains
unweighted RGB alongside alpha-weighted RGB during filtering, preserving the
reference treatment of fully transparent colors. The numeric helpers in `src/`
are internal; they do not add a general-purpose F64 API. The implementation is
a correctness-oriented RGBA8 profile with an intermediate seven-channel image;
it does not claim the reference resizer's memory use or performance.

### RGBA8 color transforms

`color_tint(surface, color)` uses integer channel products divided by 255.
`color_invert(surface)` inverts RGB and retains alpha.
`color_contrast(surface, amount)` uses finite F32 contrast clamped to -100..100.
`color_brightness(surface, amount)` takes a finite F32 adjustment, truncated toward
zero like raylib's `int` parameter, then clamped to -255..255. Its negative channel underflow becomes **1**, matching
the pinned reference; an exact zero remains zero. Both retain alpha.
`color_replace(surface, original, replacement)` matches all four bytes.

Alpha bounds use `alpha > trunc(threshold*255)`, whereas alpha clearing uses
`alpha <= trunc(threshold*255)`. A threshold of one therefore selects no pixels
for bounds/cropping. Canvas resizing copies RGBA bytes without blending, including
hidden RGB under zero alpha. It differs from ordinary resize: equal dimensions
ignore the offset and fill, as in the reference. Changed-size requests without
positive overlap return `InvalidRectangle`; some corresponding C calls have
negative copy sizes or invalid pointer arithmetic and remain outside the profile.

Vertex-colored triangles quantize each barycentric weight to a byte before
interpolating RGBA. This can darken interior pixels even when vertex colors are
equal; use `draw_triangle` for the reference flat-color operation. Degenerate
gradient triangles are excluded because the reference divides by zero and then
converts non-finite weights to bytes. Flat triangles retain their existing
degenerate behavior.

### Transform failures

`Surface.Error` has `InvalidSize`, `InvalidRectangle`, `UnsafeNearestMapping`,
`InvalidDitherBits` and `InvalidKernel` constructors. Failed crop/resize/dither,
blur or convolution returns `(original, error)` in `Fail`; failed
region drawing returns `((destination, source), error)`. Callers can recover and
reuse these owners. `Done` carries the resulting surface or pair.

The current Surface invariant excludes zero-sized images. Empty crop results
therefore return an error. `ImageFromImage` has no clipping in raylib; extraction
requires an in-bounds rectangle here. Region drawing rejects out-of-bounds source
rectangles; callers wanting clipping/scaling use `draw_image_rect`.

### Ownership and proof boundary

Every drawing call consumes its input surface and returns the updated surface.
Do not reuse the previous handle. `Surface.get` returns a pair; destructure its
computed result through a typed helper parameter, following Bend's rules.

`LAWS.bend`/`PROOF.bend` establish that clearing preserves dimensions, transposing
a Matrix twice returns the original value, and Vector3/Matrix float-list exports
contain exactly 3/16 elements. Full-pixel and numeric tests establish the
exercised reference behaviors. These proofs and tests do not establish that all
rendering, allocation, hardware or compiler behavior is formally proven.

`to_image` currently builds a complete power-of-two quadtree. `to_ppm` builds
the complete output string in memory. These are correct small-image adapters;
large real-time frames and streaming encoders need later performance work.


### Private future-angle prerequisite

The isolated [finite binary64 narrowing helper](BINARY64-NARROW.md) accepts words
and returns checked nearest-even binary32 words with gradual underflow. It has
no current public consumer and does not extend any API in this document. Its
additional structural/concrete laws do not constitute a universal arithmetic
proof or modern-angle implementation.

The [bounded FMA](BINARY64-FMA.md) and [bounded add/subtract](BINARY64-ADD-SUB.md)
helpers have the same private status. They establish only their checked arithmetic
contracts, with no existing image/math API consumer, public API promotion or
angle-profile change. The add/subtract implementation reuses private FMA
primitives under its own reviewed bounds.

The [checked normal multiply/divide and word adapters](BINARY64-OPS.md) likewise
remain private. Their separate pair-guarded domains, exact finite F32 promotion,
normal/zero packing and unsigned raw-word steps do not widen existing APIs or
supply the tiny branch's gradual-underflow multiplication.

The separate [gradual-output product](BINARY64-GRADUAL-MULTIPLY.md) now supplies
that private arithmetic prerequisite for its asymmetric normal-input domain.
It rounds once to normal/subnormal/signed-zero words and has no existing API
consumer; it does not widen the normal helpers or implement the angle kernel.


The new [private modern finite atan2 adapter](MODERN-ANGLE.md) consumes these
helpers without introducing a public angle API or changing an existing selector.
Scalar finite-input support does not expand vector intermediate/output domains.
