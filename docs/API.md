# Initial public API

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

## Owned RGBA8 surfaces

`Vector2` is immutable `Data`, constructed as `J.Vector2{x, y}` with F32 fields.
Reusable local constructor bindings need a type annotation, for example
`+point = {J.Vector2{1.0, 2.0} : J.Vector2}`.

`Surface` owns its row-major pixel array. Always start with `Surface.create`:
the underlying constructor is visible because Bend does not provide the needed
opaque user-type facility, but manually constructing an inconsistent surface
is outside this API's contract.

| Operation | Contract |
|---|---|
| `Surface.create(width, height, color) -> Maybe<Surface>` | Dimensions 1..4096 on each axis; otherwise `None`. Storage is rounded up to a power of two, with padding excluded from exports. |
| `Surface.dimensions(surface) -> U32 & U32` | Consumes a surface and returns its dimensions. |
| `Surface.clear(surface, color) -> Surface` | Replaces all pixels; preserves dimensions. |
| `Surface.get(surface, x, y) -> Surface & Maybe<&2, U32>` | Returns ownership and the pixel; out-of-bounds U32 coordinates return `None`, never wrap. |
| `Surface.draw_pixel(surface, x, y, color) -> Surface` | Replaces RGBA bytes at an in-bounds pixel; clips outside coordinates. |
| `Surface.draw_rectangle(surface, x, y, width, height, color) -> Surface` | Matches raylib 6.0 CPU `ImageDrawRectangle` for the declared integer-coordinate profile. |
| `Surface.draw_circle(surface, cx, cy, radius, color) -> Surface` | Matches raylib 6.0 CPU `ImageDrawCircle` midpoint coverage; radius is U32. |
| `Surface.draw_line(surface, x0, y0, x1, y1, color) -> Surface` | Integral F32 endpoints; matches `ImageDrawLine` fixed-point stepping and excludes the final endpoint. A zero-length line draws nothing. |
| `Surface.draw_line_v(surface, start, end, color) -> Surface` | Vector2 endpoints; applies raylib's F32 `coordinate + 0.5` followed by truncation toward zero before drawing. |
| `Surface.draw_triangle(surface, v1, v2, v3, color) -> Surface` | Integral Vector2 vertices; matches `ImageDrawTriangle` winding, inclusive edge tests, clipping and degenerate behavior. |
| `Surface.draw_triangle_lines(surface, v1, v2, v3, color) -> Surface` | Vector2 vertices truncated toward zero, then three reference-compatible line segments. |
| `Surface.draw_image(destination, source, x, y, tint) -> Surface & Surface` | Full-source, unscaled RGBA8 drawing; clips destination placement, applies integer tint/alpha blending, returns destination then unchanged source. |
| `Surface.colors(surface) -> List<U32>` | Consumes the image and exports exactly width × height packed pixels, row-major. |
| `Surface.copy(surface) -> Surface & Surface` | Returns the original and an independently owned pixel copy. |
| `Surface.flip_horizontal/flip_vertical(surface) -> Surface` | Reorders whole RGBA pixels; dimensions and alpha bytes are preserved. |
| `Surface.to_image(surface) -> Image` | Consumes the surface and builds a Base.Image quadtree. RGB is retained, alpha discarded; padded regions are black. |
| `Surface.to_ppm(surface) -> String` | Consumes the surface and encodes P3 PPM text (RGB, alpha discarded). |
| `Surface.write_ppm(surface, path) -> IO(Result<&1, &1, U32 & String, Unit>)` | Writes P3 PPM through Base.File; returns open/write errors and closes the file after writing. |

Drawing coordinates and rectangle extents are represented as **F32 but must be
finite integers in -32767..32767**. Radius is **0..32767**. This permits negative
positions while Bend has no native signed integer type. `draw_line_v` and
`draw_triangle_lines` additionally accept bounded finite fractional vertices
with the conversion rules above. Filled triangles and image placement currently
use integer coordinates. NaN/infinity and larger values remain outside the profile.
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

This is a **partial ImageDraw profile**: complete source rectangle, matching
destination size, one mip level, RGBA8 and integer placement. Source subrectangles,
resizing filters, other formats, mipmaps and fractional rectangle semantics remain
tracked gaps. Nearest-neighbor scaling must not be substituted for raylib's
different default `ImageResize` filtering behavior.

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
