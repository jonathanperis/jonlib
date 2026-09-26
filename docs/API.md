# Public API: current profiles

Import `jonlib.bend` under an alias, for example `import ./jonlib.bend as J`.
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

The public scalar and Vector2 operations are listed in [MATH.md](MATH.md),
including their explicit uncontracted-F32 profile and remaining numeric gaps.
Pure geometry queries are listed in [COLLISION.md](COLLISION.md), including
strict rectangle edges and inclusive circle tangency.

## Owned RGBA8 surfaces

`Vector2` is immutable `Data`, constructed as `J.Vector2{x, y}` with F32 fields.
Reusable local constructor bindings need a type annotation, for example
`+point = {J.Vector2{1.0, 2.0} : J.Vector2}`.
`Rectangle` is `Data` with F32 `x`, `y`, `width`, `height` fields. The current
crop/extraction/region-drawing profile requires integral rectangle values;
`draw_image_rect` and the documented rectangle wrappers also support fractional fields.

`Surface` owns its row-major pixel array. Always start with `Surface.create`:
the underlying constructor is visible because Bend does not provide the needed
opaque user-type facility, but manually constructing an inconsistent surface
is outside this API's contract.

| Operation | Contract |
|---|---|
| `Surface.create(width, height, color) -> Maybe<Surface>` | Dimensions 1..4096 on each axis; otherwise `None`. Storage is rounded up to a power of two, with padding excluded from exports. |
| `Surface.create_checked(width, height, tile_width, tile_height, first, second) -> Maybe<Surface>` | Reference checkerboard generation. Dimensions 1..4096, checker sizes 1..2147483647; invalid values return `None` before allocation/division. |
| `Surface.create_gradient_square(width, height, density, inner, outer) -> Maybe<Surface>` | Square gradient with dimensions 1..4096 and finite density 0..1. Invalid requests return `None`; density one produces the inner color, matching the reference clamp behavior. |
| `Surface.create_gradient_radial(width, height, density, inner, outer)` | Same Maybe result, dimensions 1..4096 and density 0..1; reference radial RGBA interpolation with balanced generation. |
| `Surface.create_gradient_linear(width, height, direction, start, end)` | Same Maybe result; integral directions -360..360. Rejects invalid sizes/directions and a zero reference normalization extent. Wider-angle libm parity remains open; see [GRADIENTS.md](GRADIENTS.md). |
| `Surface.create_gradient_linear_for(reference, width, height, direction, start, end)` | Explicit `Gradient.Reference`: `AccurateGradient{}` or `GnuGradient{}`. Selects the required reference's numerical behavior without hidden OS calls; see [GRADIENTS.md](GRADIENTS.md). |
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
| `Surface.draw_triangle(surface, v1, v2, v3, color) -> Surface` | Integral Vector2 vertices; matches `ImageDrawTriangle` winding, inclusive edge tests, clipping and degenerate behavior. |
| `Surface.draw_triangle_lines(surface, v1, v2, v3, color) -> Surface` | Vector2 vertices truncated toward zero, then three reference-compatible line segments. |
| `Surface.draw_triangle_ex(surface, v1, v2, v3, c1, c2, c3)` | Reference coverage and byte-quantized barycentric color weights. Requires integral vertices, defined signed arithmetic and nonzero reference weight sum. |
| `Surface.draw_triangle_fan(surface, points, color)` / `draw_triangle_strip(surface, points, color)` | Immutable `+List<Vector2>` of integral vertices; reference vertex order/winding. Fewer than three points draws nothing. |
| `Surface.draw_image(destination, source, x, y, tint) -> Surface & Surface` | Full-source, unscaled RGBA8 drawing; clips destination placement, applies integer tint/alpha blending, returns destination then unchanged source. |
| `Surface.extract(surface, rectangle) -> Surface & Maybe<Surface>` | Retains the original; returns an independent region for positive integral in-bounds rectangles, otherwise `None`. |
| `Surface.crop(surface, rectangle) -> Result<&1, &1, Surface & Surface.Error, Surface>` | Clips an integral rectangle as raylib does; returns the cropped surface or the original with an error. An origin strictly beyond the right/bottom edge is the reference no-op. |
| `Surface.resize_nn(surface, width, height) -> Result<&1, &1, Surface & Surface.Error, Surface>` | Exact fixed-point nearest mapping; positive dimensions up to 4096; refuses out-of-allocation reference mappings. |
| `Surface.resize(surface, width, height) -> Result<&1, &1, Surface & Surface.Error, Surface>` | Default filtered RGBA8 resize; dimensions 1..4096; Catmull-Rom upsampling, Mitchell downsampling, clamp edges and alpha-aware filtering. Invalid sizes return the original owner with `InvalidSize`. |
| `Surface.resize_canvas(surface, width, height, offset_x, offset_y, fill)` | Same single-owner Result. Raw RGBA copy into a filled canvas; dimensions 1..4096, bounded integral offsets. Unchanged dimensions are a no-op. Changed sizes require positive overlap; invalid sizes/rectangles return the original owner. |
| `Surface.draw_image_region(destination, source, rectangle, x, y, tint)` | Returns `Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>`; valid unscaled source subrectangles with integer placement, preserving both owners. |
| `Surface.draw_image_rect(destination, source, source_rectangle, destination_rectangle, tint)` | Same two-owner Result. Bounded finite rectangles, including fractional fields; source clipping, default filtered scaling and destination clipping follow reference order. Empty/invalid rectangles return both originals with `InvalidRectangle`. |
| `Surface.color_tint`, `color_invert`, `color_contrast`, `color_brightness`, `color_replace` | Owned RGBA8 transforms described below. |
| `Surface.alpha_clear(surface, color, threshold)` | Finite threshold 0..1, converted to an inclusive alpha-byte cutoff; replaces all RGBA bytes at matching pixels. |
| `Surface.alpha_premultiply(surface)` | Reference F32 alpha multiplication of RGB, including transparent-black conversion; retains alpha. |
| `Surface.alpha_mask(destination, mask)` | Same-size RGBA8 mask converted to reference grayscale values, replacing destination alpha while preserving the original mask. Returns the two-owner Result; mismatched dimensions return both originals with `InvalidSize`. |
| `Surface.alpha_border(surface, threshold) -> Surface & Rectangle` | Retains the original and finds pixels with alpha strictly above the truncated threshold byte. Finite threshold 0..1; empty selections return `(0,0,0,0)`. |
| `Surface.alpha_crop(surface, threshold) -> Surface` | Crops to nonempty alpha bounds; empty selections retain the original image and dimensions unchanged. |
| `Surface.colors(surface) -> List<U32>` | Consumes the image and exports exactly width × height packed pixels, row-major. |
| `Surface.copy(surface) -> Surface & Surface` | Returns the original and an independently owned pixel copy. |
| `Surface.flip_horizontal/flip_vertical(surface) -> Surface` | Reorders whole RGBA pixels; dimensions and alpha bytes are preserved. |
| `Surface.rotate_cw(surface)` / `rotate_ccw(surface)` | Quarter-turn rotations preserving exact RGBA bytes and swapping width/height. |
| `Surface.rotate_degrees(surface, degrees)` / `rotate_degrees_for(reference, surface, degrees)` | Single-owner Result; integral degrees -360..360, reference bilinear sampling and truncated output dimensions. Invalid angles/output sizes preserve the original owner. See [ROTATION.md](ROTATION.md). |
| `Surface.to_pot(surface, fill)` | Single-owner Result; raw canvas expansion to the next power-of-two dimensions, preserving the reference no-op for already-POT images. |
| `Surface.from_channel(surface, selected) -> Surface & Surface` | Returns the unchanged original, then an independent opaque grayscale RGBA8 image. Integral selectors in -32767..32767 clamp to 0..3 (RGBA). Equivalent to `ImageFromChannel` followed by RGBA8 normalization; native grayscale storage and other input formats remain gaps. |
| `Surface.to_image(surface) -> Image` | Consumes the surface and builds a Base.Image quadtree. RGB is retained, alpha discarded; padded regions are black. |
| `Surface.to_ppm(surface) -> String` | Consumes the surface and encodes P3 PPM text (RGB, alpha discarded). |
| `Surface.write_ppm(surface, path) -> IO(Result<&1, &1, U32 & String, Unit>)` | Writes P3 PPM through Base.File; returns open/write errors and closes the file after writing. |
| `Surface.decode_qoi`, `to_qoi`, `load_qoi`, `write_qoi` | QOI memory/file APIs, typed errors and RGBA8 normalization are specified in [CODECS.md](CODECS.md). |

Drawing coordinates and rectangle extents are represented as **F32 but must be
finite integers in -32767..32767**. Radius is **0..32767**. This permits negative
positions while Bend has no native signed integer type. The vector wrappers,
`draw_rectangle_rec`, `draw_rectangle_lines` and `draw_image_rect` accept bounded
finite fractional fields with the conversion rules above. Filled triangle
vertices remain integral. NaN/infinity and larger values are outside the drawing profile.
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
`color_brightness(surface, amount)` takes a finite integral F32 adjustment,
clamped to -255..255. Its negative channel underflow becomes **1**, matching
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

`Surface.Error` has `InvalidSize`, `InvalidRectangle` and `UnsafeNearestMapping`
constructors. A failed crop/resize returns `(original, error)` in `Fail`; failed
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

`LAWS.bend`/`PROOF.bend` establish that clearing preserves dimensions. Full-pixel
tests establish the exercised reference behaviors. Neither is a claim that
all rendering, allocation, hardware or compiler behavior is formally proven.

`to_image` currently builds a complete power-of-two quadtree. `to_ppm` builds
the complete output string in memory. These are correct small-image adapters;
large real-time frames and streaming encoders need later performance work.
