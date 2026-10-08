# Public API

Import `jonlib.bend` as `J` for core operations and `jonmath.bend` as `M` for math
operations and shared vector/matrix types. See [MODULES.md](MODULES.md) for the
`ray*` → `jon*` naming convention and import migration.
This is a source library for the Bend 2.0.27 base plus the compiler overlay in
`toolchain.json`. Helpers with further dotted suffixes
are implementation details; only operations listed here form the public API.

## Color

Colors are `U32` words in **0xRRGGBBAA** order, matching raylib's `GetColor` and
the unsigned bit pattern returned by `ColorToInt`.

- `Color.rgba(r, g, b, a) -> U32`: keeps the low eight bits of each U32 channel,
  equivalent to conversion to C unsigned bytes.
- `Color.red/green/blue/alpha(color) -> U32`: extract an 8-bit channel.
- `Color.LIGHTGRAY()` ... `Color.RAYWHITE()`: raylib's 26 named colors (`LIGHTGRAY`,
  `GRAY`, ..., `BLANK`, `MAGENTA`, `RAYWHITE`), compared bit for bit by gate `constants`.
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

## API families documented elsewhere

The public scalar and Vector2 operations are listed in [MATH.md](MATH.md),
including their explicit uncontracted-F32 profile and remaining numeric gaps.
The checked angle APIs take an explicit `M.Libm` and return `Maybe<F32>`; see
[ANGLES.md](ANGLES.md).
Pure geometry queries are listed in [COLLISION.md](COLLISION.md), including
strict rectangle edges and inclusive circle tangency.
Spline point queries and their explicit arithmetic profiles are listed in
[SPLINES.md](SPLINES.md).
Owned random-stream APIs and their native rprand profile are described in
[RANDOM.md](RANDOM.md).
Pixel sizing, raw byte/integer reads and writes, and packed dithering are
documented in [PIXELS.md](PIXELS.md).
Pixel formats, raw image data and `ImageFormat` are documented in
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
Path utilities and file data/text/code IO (`Files.*`) are documented in
[FILES.md](FILES.md).
Trace logging and the memory helpers (`Log.*`, `Memory.*`) are documented in
[LOGGING.md](LOGGING.md).
Audio waves (`Wave.*`: WAV loading, crop, samples and export) are documented in
[AUDIO.md](AUDIO.md).
The enumerations of raylib.h, rlgl.h, rgestures.h and rcamera.h are U32
constants named as in their header under their enum, e.g.
`PixelFormat.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8()`, `KeyboardKey.KEY_SPACE()` or
`rlBlendMode.RL_BLEND_ALPHA()`, generated into the last section of
`jonlib.bend` by `tools/enums_probe.py --write` and checked against each
compiled header (gate `enums`). rgestures.h's and rcamera.h's standalone copies
of raylib.h enums share its constants. C's `bool` is Base's `Bool`.

## Shared types

`Vector2` is immutable Jonmath `Data`, constructed as `M.Vector2{x, y}` with F32 fields.
Reusable local constructor bindings need a type annotation, for example
`+point = {M.Vector2{1.0, 2.0} : M.Vector2}`.
`Rectangle` is `Data` with F32 `x`, `y`, `width`, `height` fields. The current
crop/extraction/region-drawing profile requires integral rectangle values;
`draw_image_rect` and the documented rectangle wrappers also support fractional fields.

`M.Libm` has `M.AppleLibm{}`, `M.Glibc239Libm{}` and
`M.Glibc241Libm{}` constructors. They name numerical contracts, not host
detection; see [ANGLES.md](ANGLES.md). Existing `Libm` APIs retain their meanings.

`M.Vector3{x, y, z}` is immutable `Data` with three F32 fields.
`M.Vector4{x, y, z, w}` provides four immutable F32 fields.
`J.BoundingBox{min, max}` contains two `M.Vector3` values; supplied bounds are retained
without reordering. Their numeric and collision operations are documented in
[MATH.md](MATH.md) and [COLLISION.md](COLLISION.md).
`J.Ray{position, direction}` and `J.RayCollision{hit, distance, point, normal}`
are the ray-query values of [COLLISION.md](COLLISION.md).
`J.Camera3D{position, target, up, fovy, projection}` (raylib's `Camera` alias),
`J.Camera2D{offset, target, rotation, zoom}` and
`J.Transform{translation, rotation, scale}` are immutable value structs for the
later camera and model modules; `projection` is a `CameraProjection` U32 and
`rotation` a Quaternion (`M.Vector4`). `tests/test_structs.py` checks these and
the Jonmath structs field by field against the pinned headers.
Jonmath's `M.Matrix` contains 16 F32 fields in the reference declaration order; its layout,
identity/transpose operations and vector transforms are listed in [MATH.md](MATH.md).
`M.Matrix.Decomposition` contains `M.Decomposed{translation, rotation, scale}` with
Vector3/Vector4/Vector3 fields, adapting the three distinct outputs of decomposition.
`M.Float64{high, low}` retains binary64 input bits for projection matrices;
`M.Float64.from_f32` promotes existing F32 values. Precision and supported domains
are detailed in [MATH.md](MATH.md).

## Images: `Surface`

`Surface` is Jonlib's single owned image, the counterpart of raylib's `Image`
(Base already defines `Image`, so the name is not available). It holds
`width`, `height`, a raylib `PixelFormat` and the samples:

| Format | Name | Storage |
|---|---|---|
| 1 | GRAYSCALE | `Words`, one byte per word |
| 2 | GRAY_ALPHA | `Words`, gray then alpha byte |
| 3 | R5G6B5 | `Words`, 16-bit value |
| 4 | R8G8B8 | `Words`, R, G, B bytes (little-endian) |
| 5 | R5G5B5A1 | `Words`, 16-bit value |
| 6 | R4G4B4A4 | `Words`, 16-bit value |
| 7 | R8G8B8A8 | `Words`, canonical `0xRRGGBBAA` Color word |
| 8 | R32 | `Words`, F32 bits (finite 0..1, both zero signs) |
| 9 | R32G32B32 | `Quads`, F32 bits in `a..c` (no NaN) |
| 10 | R32G32B32A32 | `Quads`, F32 bits in `a..d` (no NaN) |
| 11 | R16 | `Words`, half-float bits (finite 0..1, both zero signs) |
| 12 | R16G16B16 | `Quads`, half-float bits in `a..c` |
| 13 | R16G16B16A16 | `Quads`, half-float bits in `a..d` |

`Quads` hold one `Surface.Quad{a, b, c, d}` of stored sample words per pixel
(unused words are zero), so every lane keeps float bits exactly. See
[FLOAT-FORMATS.md](FLOAT-FORMATS.md).

Dimensions are 1..4096 with one mip level; storage is rounded up to a power of
two and padding is excluded from every export. Build owners through the
factories, decoders and loaders below: the constructors are visible because
Bend has no opaque user types, but a hand-built inconsistent owner is outside
the contract.

Operations follow raylib's per-format behavior:

- **Byte-level** (flip, quarter turns, copy, `extract`, `crop`, `resize_canvas`,
  `to_pot`, `alpha_crop`) move stored samples intact in every format.
- **Color** operations (tint, invert, contrast, brightness, replace, alpha
  premultiply, blur, convolution, `resize`, `resize_nn`, `dither`) run
  `LoadImageColors`, the RGBA8 algorithm and `ImageFormat` back to the original
  format. Float owners in formats 9, 10, 12 and 13 need samples in 0..1 (the C
  casts are undefined elsewhere) and otherwise return `OutOfDomain` with the
  owner.
- **Drawing** stores each covered pixel's color as `ImageDrawPixel` encodes it
  for the format; there is no blending.
- **Composition** (`draw_image*`) reads both images with `GetPixelColor`
  (integer scaling for packed formats, unlike `LoadImageColors`), blends with
  `ColorAlphaBlend` unless the source has no alpha and the tint is opaque, and
  writes with `SetPixelColor`, which leaves float formats (8..13) unchanged. Without
  blending, equal formats copy stored samples. Scaled draws resize the source
  in its own format.
- **Per-format** operations follow raylib's switch: `alpha_clear` changes
  GRAY_ALPHA, R5G5B5A1, R4G4B4A4 and R8G8B8A8 and leaves formats without alpha
  unchanged; `alpha_mask` turns GRAYSCALE into GRAY_ALPHA and other formats into
  R8G8B8A8; `rotate_degrees` blends every stored byte (float results outside
  the owner domain are `OutOfDomain`); `mipmaps` resizes each level in the
  image's format.

Which formats each operation has reference evidence for is recorded per API in
the [compatibility ledger](COMPATIBILITY.md); `tools/surface_format_probe.py`
compares every format-generic operation on formats 1..13 with raylib.

### Construction and conversion

| Operation | Contract |
|---|---|
| `Surface.create(width, height, color) -> Maybe<Surface>` | R8G8B8A8 fill; dimensions 1..4096, otherwise `None`. |
| `Surface.create_checked(width, height, tile_width, tile_height, first, second) -> Maybe<Surface>` | Reference checkerboard generation. Dimensions 1..4096, checker sizes 1..2147483647; invalid values return `None` before allocation/division. |
| `Surface.create_white_noise(state, width, height, factor) -> Random.State & Maybe<Surface>` | Owned-stream white noise, dimensions 1..4096 and factor 0..1. Returns the advanced stream on success or the original stream with `None` on invalid input. |
| `Surface.create_cellular(state, width, height, tile_size) -> Random.State & Maybe<Surface>` | Owned-stream cellular generation; dimensions/tile size 1..4096. Rejected requests retain the original stream. See [CELLULAR.md](CELLULAR.md). |
| `Surface.create_perlin(width, height, offset_x, offset_y, scale)` / `create_perlin_for(contraction, ...)` | Six-octave Perlin noise returning Maybe; explicit `M.Contraction` and bounded inputs. See [PERLIN.md](PERLIN.md). |
| `Surface.create_text_bytes(width, height, bytes) -> Maybe<Surface>` | Grayscale data image from bytes, stopping at NUL and padding/truncating to the dimensions; opaque R8G8B8A8 output. See [PALETTES.md](PALETTES.md). |
| `Surface.create_gradient_square/radial(width, height, density, inner, outer)` | Maybe result; dimensions 1..4096 and finite density 0..1 (density one is the inner color, as the reference clamps). |
| `Surface.create_gradient_linear(width, height, direction, start, end)` / `create_gradient_linear_for(libm, ...)` | Integral directions -360..360 with an explicit `M.Libm`; rejects a zero reference normalization extent. See [GRADIENTS.md](GRADIENTS.md). |
| `Surface.from_bytes(width, height, format, bytes) -> Maybe<Surface>` | Raw image data for formats 1..13: exactly `width*height` samples in raylib byte order; R32 and R16 samples finite 0..1, F32 samples of formats 9 and 10 not NaN. See [FORMATS.md](FORMATS.md). |
| `Surface.export(surface) -> (U32 & U32) & (U32 & List<U32>)` | Consumes the owner: dimensions, format and raw sample bytes without padding. |
| `Surface.format(surface, target)` | `ImageFormat` between formats 1..13 (`HalfToFloat`/`FloatToHalf` for R16 formats); `target` 0 or the current format keeps the owner, compressed targets are `UnsupportedFormat`; float sources need samples in 0..1. See [FORMATS.md](FORMATS.md) and [FLOAT-FORMATS.md](FLOAT-FORMATS.md). |
| `Surface.dimensions(surface) -> U32 & U32` / `pixel_format(surface) -> Surface & U32` | Consume the owner for its dimensions / return it with its format. |
| `Surface.colors(surface)` | `LoadImageColors`: consumes the owner and returns `width*height` row-major Colors. |
| `Surface.is_valid(surface) -> Surface & Bool` | `IsImageValid`: returns the owner; true for every factory/decoder/loader owner, false for a hand-built record with dimensions outside 1..4096, a format outside 1..13 or the wrong storage variant. |
| `Surface.unload(surface)` / `Surface.unload_colors(colors)` | `UnloadImage` / `UnloadImageColors`: consume the owner or color list; affine ownership rules out double unloads. |
| `Surface.get(surface, x, y) -> Surface & Maybe<&2, U32>` | `GetImageColor` for one pixel; out-of-bounds U32 coordinates (no wrap) and out-of-domain float samples return `None`. See [IMAGE-COLORS.md](IMAGE-COLORS.md). |
| `Surface.from_channel(surface, selected) -> Surface & Maybe<Surface>` | `ImageFromChannel`: keeps the source, returns an independent GRAYSCALE image; integral selectors -32767..32767 with per-format redirection. See [IMAGE-CHANNELS.md](IMAGE-CHANNELS.md). |
| `Surface.load_palette(surface, maximum) -> Surface & Maybe<Image.Palette>` | Keeps the source; first-occurrence colors excluding alpha zero; capacity 1..4096. See [PALETTES.md](PALETTES.md). |
| `Surface.copy(surface) -> Surface & Surface` | The original and an independent copy. |
| `Surface.to_image(surface)` / `to_ppm(surface)` | Base.Image quadtree / P3 PPM text from the owner's colors; alpha discarded. |

### Byte-level geometry (every format)

| Operation | Contract |
|---|---|
| `Surface.flip_horizontal/flip_vertical(surface) -> Surface` | Reorders stored pixels. |
| `Surface.rotate_cw/rotate_ccw(surface) -> Surface` | Quarter turns; width and height swap. |
| `Surface.extract(surface, rectangle) -> Surface & Maybe<Surface>` | `ImageFromImage` profile: keeps the original; positive integral in-bounds rectangles, otherwise `None`. |
| `Surface.crop(surface, rectangle)` | Clips an integral rectangle as raylib does; an origin strictly beyond the right/bottom edge is the reference no-op. |
| `Surface.resize_canvas(surface, width, height, offset_x, offset_y, fill)` | Raw copy into a canvas filled with `SetPixelColor(fill)` (float canvases, formats 8..13, stay zero); dimensions 1..4096, bounded integral offsets, positive overlap for changed sizes; equal dimensions are a no-op. |
| `Surface.to_pot(surface, fill)` | Canvas expansion to the next power-of-two dimensions; already-POT images are unchanged. |
| `Surface.alpha_border(surface, threshold) -> Surface & Rectangle` / `alpha_crop(surface, threshold) -> Surface` | Bounds of pixels whose `LoadImageColors` alpha exceeds the truncated threshold byte (formats without alpha read 255); empty selections return `(0,0,0,0)` / the original. |

### Color operations (every format, via RGBA8)

| Operation | Contract |
|---|---|
| `Surface.color_tint/color_invert/color_replace(surface, ...)` | Integer tint products / RGB inversion / exact four-byte replacement. |
| `Surface.color_contrast(surface, amount)` | Finite F32 contrast clamped to -100..100; non-finite amounts are `InvalidRequest`. |
| `Surface.color_brightness(surface, amount)` | Finite amount below 2^31 in magnitude, truncated toward zero (C int) then clamped to -255..255; others are `InvalidRequest`. |
| `Surface.color_grayscale(surface)` | `ImageColorGrayscale`, i.e. `ImageFormat` to GRAYSCALE. |
| `Surface.alpha_premultiply(surface)` | Reference F32 alpha multiplication of RGB. |
| `Surface.blur_gaussian(surface, size)` | Four-iteration box approximation with premultiplied alpha; size 0..min(width, height). See [BLUR.md](BLUR.md). |
| `Surface.kernel_convolution(surface, kernel)` | Bounded square kernels; unsupported kernels/results are `InvalidKernel`. See [CONVOLUTION.md](CONVOLUTION.md). |
| `Surface.resize(surface, width, height)` | Default filtered resize (Catmull-Rom up, Mitchell down); dimensions 1..4096. R8G8B8A8 is alpha-aware; GRAYSCALE, GRAY_ALPHA and R8G8B8 filter their own channels unweighted and keep their format; other formats go through RGBA8 and back. See [RESAMPLING.md](RESAMPLING.md). |
| `Surface.resize_nn(surface, width, height)` | Exact fixed-point nearest mapping; refuses out-of-allocation reference mappings. |
| `Surface.dither(surface, r, g, b, a)` | Floyd-Steinberg into R5G6B5 (5,6,5,0), R5G5B5A1 (5,5,5,1) or R4G4B4A4 (4,4,4,4); other bit counts are `InvalidDitherBits`. See [PIXELS.md](PIXELS.md). |

All return `Result<&1, &1, Surface & Surface.Error, Surface>`; a rejected request
returns the original owner.

### Drawing (every format)

| Operation | Contract |
|---|---|
| `Surface.clear(surface, color)` | `ImageClearBackground`. |
| `Surface.draw_pixel(surface, x, y, color)` / `draw_pixel_v` | Stores one in-bounds pixel; clips outside coordinates; vectors truncate. |
| `Surface.draw_rectangle(surface, x, y, width, height, color)` / `_v` / `_rec` | `ImageDrawRectangle` for the integer profile; `_v` truncates, `_rec` clips bounded fields before conversion. |
| `Surface.draw_rectangle_lines(surface, rectangle, thickness, color)` | Four reference edge strips; thickness 0..32767. |
| `Surface.draw_circle(surface, cx, cy, radius, color)` / `_v` / `draw_circle_lines` / `_lines_v` | Midpoint coverage and outlines, radius U32; vector centers truncate. |
| `Surface.draw_line(surface, x0, y0, x1, y1, color)` / `_v` / `_ex` | Fixed-point stepping excluding the final endpoint; `_v` adds a half then truncates; `_ex` draws dominant-axis strips, thickness 0..32767. |
| `Surface.draw_triangle(surface, v1, v2, v3, color)` / `draw_triangle_lines` / `draw_triangle_fan` / `draw_triangle_strip` | Truncated bounds and edge steps, both windings, inclusive edges; fans/strips with fewer than three points draw nothing. |
| `Surface.draw_triangle_ex(surface, v1, v2, v3, c1, c2, c3)` | Byte-quantized barycentric colors, each stored as `ImageDrawPixel` encodes it. |

Every drawing call consumes the owner and returns the updated one.

### Composition, masks, rotation and mipmaps

| Operation | Contract |
|---|---|
| `Surface.draw_image(destination, source, x, y, tint)` | Full-source unscaled composition with integer `ColorAlphaBlend`, any formats; returns `Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>` with destination first and the unchanged source. A wide float source needs samples in 0..1 (`OutOfDomain`). |
| `Surface.draw_image_region(destination, source, rectangle, x, y, tint)` | Valid unscaled source subrectangles with integer placement. |
| `Surface.draw_image_rect(destination, source, source_rectangle, destination_rectangle, tint)` | Bounded finite rectangles, including fractional fields; reference clipping and default filtered scaling in the source format. |
| `Surface.alpha_mask(destination, mask)` | Same-size mask converted to GRAYSCALE becomes the alpha of a GRAY_ALPHA (from GRAYSCALE) or R8G8B8A8 destination; mismatched sizes are `InvalidSize`, conversion failures `OutOfDomain`. |
| `Surface.alpha_clear(surface, color, threshold)` | Finite threshold 0..1: an inclusive alpha cutoff in GRAY_ALPHA, R5G5B5A1, R4G4B4A4, R8G8B8A8, R32G32B32A32 and R16G16B16A16 with raylib's per-format replacement words; other formats are unchanged. raylib packs R5G5B5A1/R4G4B4A4 colors from `round(channel*31)`/`round(channel*15)` byte casts, undefined above 255, so those formats require RGB channels up to 8 (and up to 17 with alpha for R4G4B4A4). Other requests are `InvalidRequest`. |
| `Surface.mipmaps(surface) -> Image.Mipmaps` / `Image.Mipmaps.entries/unload` | Base-to-1x1 chain, each level `resize` of the previous one in the image's format. See [MIPMAPS.md](MIPMAPS.md). |
| `Surface.rotate_degrees(surface, degrees)` / `rotate_degrees_for(libm, ...)` | Integral degrees -360..360, reference bilinear sampling of every stored byte and truncated output dimensions; float results outside the owner domain are `OutOfDomain`. See [ROTATION.md](ROTATION.md). |

### Codecs and files

Decoders and loaders return the file's native format, as raylib's `LoadImage`
does (GRAYSCALE, GRAY_ALPHA, R8G8B8 or R8G8B8A8 for 8-bit codecs, R32G32B32 for
HDR); use `Surface.colors` or `Surface.format(surface, 7)` for RGBA8.

| Operation | Contract |
|---|---|
| `Surface.decode_qoi/dds/png/bmp/tga/pnm/pic/gif/psd/hdr(bytes)` / `decode_psd_for(contraction, bytes)` | Memory decoders returning `Result<&1, &1, Surface.Error, Surface>`. See [CODECS.md](CODECS.md), [PNG.md](PNG.md), [BMP.md](BMP.md), [TGA.md](TGA.md), [PNM.md](PNM.md), [PIC.md](PIC.md), [GIF.md](GIF.md), [PSD.md](PSD.md), [HDR.md](HDR.md). |
| `Surface.decode_image(file_type, bytes)` / `decode_image_for(contraction, ...)` | `LoadImageFromMemory`: exact extension tokens select QOI or the raster signatures. See [IMAGE-FILES.md](IMAGE-FILES.md). |
| `Surface.load_image(path)` / `load_image_for(contraction, path)` | `LoadImage`: bounded ordinary files, native last-dot suffix/content selection, close before decode. |
| `Surface.load_qoi/dds/png/bmp/tga/pnm/pic/hdr(path)` | Explicit codec selection independent of the suffix, with the same file boundary. |
| `Surface.load_raw(path, width, height, format, header_size)` | `LoadImageRaw` for formats 1..13 with native header selection. See [RAW-FILES.md](RAW-FILES.md). |
| `Image.Animation.decode_gif/decode_image/load_image(...)` / `entries` / `unload` | GIF frame sequences or a one-frame fallback with caller budgets. See [GIF-ANIMATION.md](GIF-ANIMATION.md). |
| `Surface.to_png/to_bmp/to_tga/to_qoi(surface)` | `ExportImage` file bytes: GRAYSCALE, GRAY_ALPHA, R8G8B8 and R8G8B8A8 write stored samples, other formats `LoadImageColors`; QOI accepts R8G8B8 and R8G8B8A8 only. See [IMAGE-EXPORT.md](IMAGE-EXPORT.md). |
| `Surface.export_to_memory(surface, file_type)` | `ExportImageToMemory` (".png"): native raw-storage interpretation, including R32/R32G32B32 bytes read as RGBA; 16-bit packed formats are rejected. |
| `Surface.to_code(surface, path)` | `ExportImageAsCode` text from raw bytes (at most 64 KiB). See [IMAGE-CODE.md](IMAGE-CODE.md). |
| `Surface.write_png/bmp/tga/qoi/raw/code/ppm(surface, path)` / `write_image(surface, path)` | Write one file and close it; `write_image` selects PNG/BMP/TGA/QOI/RAW by ASCII-case-insensitive suffix. |

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

`ImageDraw*` operations replace stored samples, including alpha. They do not
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

This is a **partial ImageDraw profile**: R8G8B8A8 and one mip level. The
`draw_image_rect` path clips source fields first, compares truncated extents to
decide whether to resize, then clips the destination before truncating pixel
indices/counts. It accepts fractional rectangles when the clipped source has at
least one pixel and truncated destination dimensions are 1..4096. The original
source remains unchanged, including when a temporary resized region is used.
Other formats, mipmaps, empty/undefined reference rectangles and full target/
performance coverage remain gaps.
Nearest-neighbor scaling is a separate API and is not substituted for raylib's
default `ImageResize` filtering behavior. See [RESAMPLING.md](RESAMPLING.md).

`Surface.resize` provides that default filtered path separately. Its RGBA8
kernel retains unweighted RGB alongside alpha-weighted RGB during filtering,
preserving the reference treatment of fully transparent colors. The numeric helpers in `src/`
are internal; they do not add a general-purpose F64 API. The implementation is
a correctness-oriented RGBA8 profile with an intermediate seven-channel image;
it does not claim the reference resizer's memory use or performance.

### Color transforms

The RGBA8 step of each color operation behaves as follows.
`color_tint(surface, color)` uses integer channel products divided by 255.
`color_invert(surface)` inverts RGB and retains alpha.
`color_contrast(surface, amount)` uses finite F32 contrast clamped to -100..100.
`color_brightness(surface, amount)` takes a finite F32 adjustment, truncated toward
zero like raylib's `int` parameter, then clamped to -255..255. Its negative channel underflow becomes **1**, matching
the pinned reference; an exact zero remains zero. Both retain alpha.
`color_replace(surface, original, replacement)` matches all four bytes.

Alpha bounds use `alpha > trunc(threshold*255)`, whereas alpha clearing uses
`alpha <= trunc(threshold*255)`. A threshold of one therefore selects no pixels
for bounds/cropping. Canvas resizing copies stored samples without blending, including
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

### Errors

`Surface.Error` names every image failure: `InvalidSize`, `InvalidRectangle`,
`InvalidRequest`, `UnsafeNearestMapping`, `InvalidDitherBits`, `InvalidKernel`,
`UnsupportedFormat`, `OutOfDomain`, `UnsupportedFileType`, the pixel-byte errors
`InvalidPixelByte`/`TruncatedPixelData` and the decode errors
`InvalidImageHeader`, `InvalidImageByte`, `UnsupportedImageSize`,
`TruncatedImageData`, `InvalidImageStream`. A failed consuming operation returns
`Fail{(original, error)}`; failed two-image operations return
`Fail{((destination, source), error)}`, so callers can recover the owners.
Decoders, which own no image yet, return `Fail{error}`.

`Surface.IOError` is shared by loaders and writers: `FileError{code, message}`
for Base file errors, `DataError{error}` for rejected file contents or requests,
and `SourceError{surface, error}` when a writer rejects its image before opening
the file (the owner comes back). Writers consume accepted owners and close the
handle before returning.

The owner invariant excludes zero-sized images, so empty crop results return an
error. `ImageFromImage` has no clipping in raylib; extraction requires an
in-bounds rectangle here. Region drawing rejects out-of-bounds source
rectangles; callers wanting clipping/scaling use `draw_image_rect`.

### Ownership and proof boundary

Every operation consumes its owner and returns the updated one (or the original
in a failure). Do not reuse the previous handle. `Surface.get` returns a pair; destructure its
computed result through a typed helper parameter, following Bend's rules.

`LAWS.bend`/`PROOF.bend` establish, among scoped codec facts, that clearing
preserves dimensions in every format, format target 0 keeps the owner,
R8G8B8A8 drawing stores the Color word unchanged, transposing a Matrix twice
returns the original value, and Vector3/Matrix float-list exports contain
exactly 3/16 elements. Full-pixel and numeric tests establish the
exercised reference behaviors. These proofs and tests do not establish that all
rendering, allocation, hardware or compiler behavior is formally proven.

`to_image` currently builds a complete power-of-two quadtree. `to_ppm` builds
the complete output string in memory. These are correct small-image adapters;
large real-time frames and streaming encoders need later performance work.

## Private arithmetic

The checked binary64 helpers (narrowing, bounded FMA, add/subtract, normal
multiply/divide with word adapters and the gradual-output product) and the
[modern finite `atan2f` adapter](MODERN-ANGLE.md) are private: they are not
re-exported and do not widen any API in this document. Their domains and proof
limits are in [BINARY64.md](BINARY64.md); the public checked angle wrappers that
consume them are in [ANGLES.md](ANGLES.md). Scalar finite-input support does not
expand vector intermediate/output domains.
