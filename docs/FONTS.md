# Fonts and text drawing

Phase 3 ([MASTER-PLAN.md](MASTER-PLAN.md)): raylib 6.0's default font,
fonts loaded from XNA-style images, TrueType/BDF/BMFont files and memory,
glyph data and atlases, glyph queries, text measurement, text drawn into the
[Frame](FRAME.md), image text and fonts exported as code. Altered
Bend adaptations of `rtext.c` and of `rtextures.c`'s `ImageText*` functions
(zlib, [LICENSES/raylib.txt](../LICENSES/raylib.txt)); drawing goes through
the `rlsw.h` port of [FRAME.md](FRAME.md) and [TEXTURES.md](TEXTURES.md)
(MIT, [LICENSES/rlsw.txt](../LICENSES/rlsw.txt)). Code: the section "Fonts
and text drawing" of `jonlib.bend` and `src/fonts.bend` (glyph table, atlas
expansion, `GetGlyphIndex`, measurement, the `DrawTextEx` streams,
`ImageTextEx`'s placement and `LoadFontFromImage`'s scan); the default font
bitmap is `src/frame_font.bend`. TrueType rasterization is an altered Bend
adaptation of `stb_truetype.h` 1.26 (`src/truetype.bend`) and atlas packing
of `stb_rect_pack.h` 1.01 (`src/font_data.bend`), both public domain / MIT
([LICENSES/stb_truetype.txt](../LICENSES/stb_truetype.txt)); see
[TrueType, BDF and BMFont fonts](#truetype-bdf-and-bmfont-fonts).

## Reference and profile

The same reference as the Frame: pinned raylib on `PLATFORM=Memory`, scalar
`rlsw`, compiled with `-ffp-contract=off` (the probe checks the objects for
fused multiply-adds). Measurement and glyph placement are uncontracted F32 in
`rtext.c`'s order. A contracted arm64 build fuses `width*scale + spacing` and
`tempTextWidth*scaleFactor + (count - 1)*spacing`; that build is a separate
contract (not provided). `DrawTextPro` rotates with `rlRotatef`, whose
`sinf`/`cosf` take the `M.Libm` profile (`_for` functions; the others use
`M.AppleLibm{}`) and are reproduced only for the profile's verified arguments
([FRAME.md](FRAME.md#reference-and-profile)).

## Types and state

- `Font{base_size, glyph_padding, glyphs, texture, atlas}`: raylib's `Font`.
  `glyphs` holds every glyph's `GlyphInfo` fields (value, offsets, advance as
  two's-complement `U32` C ints) with its atlas rectangle (`recs`); `texture`
  is an owned [Texture](TEXTURES.md); `atlas` is the image every glyph image
  is cut from (raylib's loaders always set `glyphs[i].image` to
  `ImageFromImage(atlas, recs[i])`). Build fonts with `Font.default` and
  `Font.load_from_image`; a hand-built font without glyphs is outside the
  contract (raylib reads `glyphs[0]`).
- `GlyphInfo{value, offset_x, offset_y, advance_x, image}` with `image` a
  `GlyphImage`: `GlyphPixels{image}` (an owned Surface) or `GlyphEmpty{width,
  height}` (raylib's image without pixels: no data, or 0 wide or high, with its
  C int size), and `FontInfo{base_size, glyph_count, glyph_padding, texture}`
  (the texture id).
- **textLineSpacing.** raylib's global `textLineSpacing` (set by
  `SetTextLineSpacing`, initially 2) is an explicit argument: every function
  it affects has a `_spaced` form taking `line_spacing` (the C int, a
  two's-complement `U32`) first; the plain form uses 2. `MeasureText` only
  returns the width and needs none.
- C ints that are positions and sizes (`DrawText`, `MeasureText`,
  `ImageText`, `ImageDrawText`) are F32 values converted as C does
  (truncation; NaN or beyond `[-2^31, 2^31)` is undefined), as in the Frame;
  codepoints, `firstChar`, line spacing and FPS are `U32` words.

## The default font

`Font.default()` is the font `InitWindow` loads (`LoadFontDefault`): 224
glyphs for codepoints 32..255, `charsWidth[i]` x 10 pixels laid out left to
right with one-pixel separators and wrapped when `testPosX` reaches 128,
baseSize 10, padding 0, offsets and advance 0. Its texture has id 1 and its
atlas is the 128x128 GRAY_ALPHA image expanded from `defaultFontData` (bit
`j` of word `n` is pixel `32n + j`: gray 255 with alpha 255 where set, alpha
0 elsewhere). The probe compares the font fields and the whole glyph table
(rectangles and every glyph image) with `GetFontDefault()`.

**Texture 1 is shared.** In raylib the default font's texture is also the
shapes texture, so `SetTextureFilter(GetFontDefault().texture, ...)` (or
`UpdateTexture` on it) changes text and shapes alike. A Jonlib `Font` value
owns its copy: `Font.set_filter` changes how text drawn with that value
samples, while the frame keeps its own atlas, which shapes and `Draw.text`
(`DrawText`, which needs no Font) always sample with NEAREST. Programs that
filter the default font and then draw shapes or `DrawText` before resetting
it to POINT differ from raylib; the probe checks the filtered value and the
reset.

## API

| raylib | Jonlib |
|---|---|
| `GetFontDefault` | `Font.default() -> Font` |
| `LoadFontFromImage` | `Font.load_from_image(frame, image, key, first_char) -> Frame & (Surface & Maybe<Font>)` (the image is handed back) |
| `IsFontValid` / `UnloadFont` | `Font.is_valid(font) -> Font & Bool`, `Font.unload(frame, font) -> Frame` |
| font fields, `SetTextureFilter(font.texture, f)` | `Font.info(font) -> Font & FontInfo`, `Font.set_filter(font, filter)` |
| `font.texture.width`/`.height`, `DrawTexture(font.texture, x, y, tint)` | `Font.texture_size(font) -> Font & (U32 & U32)`, `Draw.font_texture(frame, font, x, y, tint) -> Frame & Font` |
| `GetGlyphIndex` / `GetGlyphInfo` / `GetGlyphAtlasRec` | `Font.glyph_index`, `Font.glyph_info -> Font & Maybe<GlyphInfo>` (a rectangle 0 wide or high gives `GlyphEmpty`), `Font.glyph_atlas_rec` |
| `MeasureText` | `Font.measure_text(text, size) -> Maybe<U32>` |
| `MeasureTextEx` / `MeasureTextCodepoints` | `Font.measure_text_ex(_spaced)`, `Font.measure_text_codepoints(_spaced)` `-> Font & M.Vector2` |
| `DrawText` | `Draw.text(frame, text, x, y, size, color)`, `Draw.text_spaced` |
| `DrawTextEx` | `Draw.text_ex(frame, font, text, position, size, spacing, tint) -> Frame & Font`, `_spaced` |
| `DrawTextPro` | `Draw.text_pro_for(libm, ...)`, `Draw.text_pro`, `Draw.text_pro_spaced_for`, `Draw.text_pro_spaced` |
| `DrawTextCodepoint` / `DrawTextCodepoints` | `Draw.text_codepoint`, `Draw.text_codepoints(_spaced)` |
| `DrawFPS` | `Draw.fps(frame, x, y, fps)`: the `GetFPS` value is an argument (`Core.get_fps`, [INPUT.md](INPUT.md)) |
| `SetTextLineSpacing` | the `line_spacing` argument of the `_spaced` functions |
| `ImageText` / `ImageTextEx` | `Font.image_text(text, size, color) -> Maybe<Surface>`, `Font.image_text_ex(font, ...) -> Font & Maybe<Surface>`, `_spaced` |
| `ImageDrawText` / `ImageDrawTextEx` | `Font.image_draw_text(destination, text, x, y, size, color)`, `Font.image_draw_text_ex(destination, font, text, position, size, spacing, tint)`, `_spaced` |

Texts are raylib byte strings (`String`s of characters 0..255 read up to
the first NUL) decoded with `GetCodepointNext` ([TEXT.md](TEXT.md)).

### Glyphs and measurement

- `GetGlyphIndex` (`SUPPORT_UNORDERED_CHARSET`): the first glyph whose value is
  the codepoint, otherwise the **last** `'?'` glyph (or 0 without one); 0 for an
  invalid font. Unknown codepoints, invalid UTF-8 and codepoints above 255
  therefore measure and draw as `'?'` with the default font.
- `MeasureTextEx`: per line, the sum of `advanceX` (when positive) or
  `recs.width + offsetX`; the widest line times `fontSize/baseSize` plus
  `(glyphs on the line with the most glyphs - 1)*spacing` (the counts and
  widths are tracked separately, so the two can come from different lines);
  height `fontSize` plus `fontSize + textLineSpacing` per `'\n'`. An empty
  text is (0, 0); a text of newlines has width `-spacing`.
- `MeasureText` truncates the default font's width with `fontSize` raised to
  10 and spacing `fontSize/10`: a text of newlines gives -1 (as a word).

### Drawing

- `DrawTextEx`: every codepoint except `' '`, `'\t'` and `'\n'` is a
  `DrawTextCodepoint` at the position plus the running offsets; the x offset
  grows by `recs.width*scale + spacing` (or `advanceX*scale + spacing`), and
  `'\n'` moves down by `fontSize + textLineSpacing`.
- `DrawTextCodepoint`: `DrawTexturePro` of the glyph rectangle grown by the
  padding to `position + offset*scale - padding*scale`, size
  `(rect + 2*padding)*scale`, rotation 0, with the font's texture (its filter
  included); textured quads blend as in [TEXTURES.md](TEXTURES.md).
- `DrawText`: `DrawTextEx` with the default font from the frame's atlas,
  `fontSize` raised to 10 and spacing `fontSize/10`.
- `DrawTextPro`: `rlPushMatrix`, `rlTranslatef(position)`, `rlRotatef(rotation,
  0, 0, 1)`, `rlTranslatef(-origin)`, `DrawTextEx` at (0, 0), `rlPopMatrix`; the
  rotation's `sinf`/`cosf` are always evaluated.
- `DrawFPS`: `DrawText(TextFormat("%2i FPS", fps), x, y, 20, color)` with
  LIME from 30, ORANGE from 15 and RED below (negative values included).

### Image text

- `ImageTextEx`: `MeasureTextEx` at `baseSize` sizes a BLANK R8G8B8A8 image;
  each glyph image (from the atlas) is `ImageDraw`n with the tint at integer
  offsets, which advance by `(int)(recs.width + spacing)` (or `advanceX +
  (int)spacing`) and move down by `baseSize + baseSize/2` per `'\n'` (not by
  `textLineSpacing`, which only sizes the image, so later lines can fall
  outside it); when `MeasureTextEx` at `fontSize` has a different height, the
  image is resized to `(int)(imSize*textSize.y/imSize.y)`: nearest-neighbor
  for the default font (texture id 1), `ImageResize` otherwise. Jonlib reuses
  `Surface.draw_image`, `Surface.resize_nn` and `Surface.resize`.
- `ImageText`: the default font, `fontSize` raised to 10, spacing
  `fontSize/10`.
- `ImageDrawTextEx`: `ImageDraw` of that image at the position with WHITE
  (source-over into any destination format); `ImageDrawText` uses the default
  font, `(float)fontSize` as given (no minimum) and spacing 1.

### LoadFontFromImage

`charSpacing` and `lineSpacing` are the column and row of the first pixel,
row by row, that is not the key color; `charHeight` is the run of non-key
pixels below it in that column; each line (rows `lineSpacing + L*(charHeight
+ lineSpacing)`) yields glyphs from `charSpacing` on, each the run of
non-key pixels on the line's first row, the next starting `charSpacing`
after it. Values are `firstChar + i`, offsets, advance and padding 0,
baseSize `charHeight`; key pixels become BLANK in the R8G8B8A8 atlas, which
is loaded as the texture (`LoadImageColors` reads any format). When
`charSpacing` or `lineSpacing` is 0, raylib's security check returns the
default font, and so does Jonlib.

## TrueType, BDF and BMFont fonts

| raylib | Jonlib |
|---|---|
| `LoadFontData` | `Font.load_data(bytes, size, codepoints, count, type) -> Font.Data` (`FontDataNull{}` for raylib's NULL, `FontDataGlyphs{glyphs}`, `FontDataRefused{}`) |
| `UnloadFontData` | `Font.unload_data(glyphs) -> Unit` |
| `GenImageFontAtlas` | `Font.gen_image_atlas_for(libm, glyphs, count, size, padding, method) -> List<GlyphInfo> & Maybe<(Surface & +List<Rectangle>)>`, `Font.gen_image_atlas` (Apple) |
| `LoadFontFromMemory` | `Font.load_from_memory(frame, file_type, bytes, size, codepoints, count) -> Frame & Maybe<Font>` |
| `LoadFontEx` | `Font.load_ex(frame, path, size, codepoints, count) -> IO(Frame & Result<&1, &1, Surface.IOError, Maybe<Font>>)` |
| `LoadFont` | `Font.load(frame, path)` (same result); `.fnt` files go through `Font.load_bmfont(frame, path)` |
| `ExportFontAsCode` | `Font.as_code(font, file_name) -> Font & Maybe<String>`, `Font.export_as_code(font, path) -> IO(Font & Result<&1, &1, Surface.IOError, Unit>)` |

Sizes, counts and codepoints are C ints (two's-complement `U32` words). An
empty `codepoints` list is raylib's NULL (`count` consecutive codepoints from
32, 95 when `count` is not positive); otherwise its first `count` entries are
used. Font bytes are `+List<U32>` (as `Files.load_data` returns them).

### stb_truetype as raylib uses it

`LoadFontData` runs `stbtt_InitFont` at offset 0 (TrueType outlines: `glyf`
and `loca`), `stbtt_ScaleForPixelHeight(fontSize)` and
`stbtt_GetFontVMetrics`; each requested codepoint that `stbtt_FindGlyphIndex`
maps to an index above 0 (cmap formats 0, 4, 6, 12 and 13; the last Microsoft
Unicode BMP/full or Unicode-platform subtable wins; format 2 and unknown
formats map nothing) gives a glyph:

- FONT_DEFAULT / FONT_BITMAP: `stbtt_GetCodepointBitmap` at the scale for
  both axes: the glyph shape (simple contours with their flags and
  coordinates, contours starting off the curve, composites with byte or short
  offsets, scale, x/y scale or 2x2 transforms, the point-matching form leaving
  its offsets 0 and its arguments unread), the integral box (floor/ceil of the
  scaled `glyf` box), the outline flattened with flatness 0.35/scale, edges
  sorted by stb's quicksort and insertion sort, and the version-2 rasterizer
  (`stbtt__fill_active_edges_new` with its one-pixel, span and brute-force
  clipping paths, `|coverage|*255 + 0.5` truncated and capped at 255). The
  offsets are the box's, offsetY plus `(int)(ascent*scale)`; advanceX is
  `(int)(advance*scale)`. FONT_BITMAP maps bytes below 80 to 0, others to 255.
- FONT_SDF: `stbtt_GetCodepointSDF` (padding 4, on-edge 128, distance scale
  64) for every codepoint but the space: crossings counted with
  `stbtt__compute_crossings_x` and `stbtt__ray_intersect_bezier`, distances to
  lines and to quadratic curves whose quadratic term vanishes. A pixel whose
  search reaches a curve with a nonzero quadratic term needs
  `stbtt__solve_cubic`, which calls the C library's double `pow`, `acos` and
  `cos`: the whole load is refused (outside the profile). Fonts made of lines
  (pixel fonts such as DotGothic16 and the generated box fonts) are
  reproduced.
- The space and U+3000 always get an empty `advanceX x fontSize` image (data
  when advanceX > 0; a negative advance keeps its width and advanceX 0).
- A glyph whose box is empty (or whose `w*h` is negative, which `malloc`
  refuses) has no image and keeps the box offsets; a zero scale leaves them 0.

All arithmetic is F32 in stb's order, uncontracted (the reference is built
with `-ffp-contract=off`); the only libm function on this path is `sqrt`
(exact). `STBTT_assert` is compiled out (release build), here too.

### GenImageFontAtlas

The atlas side is `(int)powf(2, ceilf(logf(sqrtf(totalArea))/logf(2)))` with
`totalArea = totalWidth*(fontSize + 2*padding)*1.2f`, halved in height when
`totalArea` is under half its square. Jonlib computes it exactly: a power of
two gives itself (the probe checks the host `logf` there) and other sizes the
next power, except the 64 floats just above a power of two, where the
quotient's rounding depends on the C library's `logf`: refused. Method 0
places glyphs left to right, starting a row when `offsetX >= width -
glyphWidth - 2*padding` and doubling the height (once per row) when the row
passes `height - fontSize - padding`; each glyph is copied clipped to the
atlas size at that moment. Method 1 is `stb_rect_pack`'s skyline
(bottom-left, `glyphCount` nodes, the width aligned to
`ceil(width/glyphCount)` for the search); the rectangles are first sorted by
`qsort` (taller, then wider), whose order of equal rectangles is the C
library's: `M.Libm` selects glibc's stable merge sort (`Glibc239Libm{}`,
`Glibc241Libm{}`) or Apple Libc's FreeBSD introsort with its depth limit and
heapsort fallback (`AppleLibm{}`,
[LICENSES/freebsd-sort.txt](../LICENSES/freebsd-sort.txt)). Unpacked
rectangles are at `(float)INT_MAX + padding`. A 3x3 white corner is written
at the bottom right, then the GRAYSCALE atlas becomes GRAY_ALPHA (gray 255,
alpha the byte). raylib reads every glyph image as `width*height` GRAYSCALE
bytes whatever its format, and so does Jonlib (the raw bytes).

### LoadFontFromMemory, LoadFontEx, LoadFont

`LoadFontFromMemory` lower-cases the file type: `.ttf`/`.otf` load with
`LoadFontData(FONT_DEFAULT)`, `.bdf` with `LoadFontDataBDF`, then
`GenImageFontAtlas(glyphs, glyphCount, baseSize, 4, 0)` becomes the texture
and each glyph image is its atlas region; anything else, or a font
`stbtt_InitFont` rejects, is the default font. `LoadFontEx` loads the file
(`Fail` when it does not load or is empty: raylib returns an empty Font) and
uses its extension. `LoadFont` picks by extension (`.ttf`, `.otf`, `.bdf`:
size 32, 95 codepoints; `.fnt`: `LoadBMFont`; otherwise `LoadImage` then
`LoadFontFromImage(image, MAGENTA, 32)`, the default font when the image
does not load) and sets the POINT filter.

**BDF.** raylib 6.0's `LoadFontDataBDF` reuses the glyph array pointer as the
current glyph: `STARTCHAR` sets it to NULL, so a font with characters returns
NULL (the default font) and a `BITMAP` whose `ENCODING` is a requested
codepoint other than the first writes through a pointer derived from NULL
(refused). A font without characters returns `count` zeroed glyphs (an atlas
of empty rectangles), sized by the last `SIZE` line (`sscanf %i`: decimal,
octal and hex). Lines come from `GetLine` (255 bytes or a newline, no
terminator check), so a file without `ENDFONT` reads past its data
(refused).

**BMFont.** `LoadBMFont` reads `lineHeight`, `scaleW`, `scaleH` and `pages`
from the second line, the page file name and the glyph count, then `count`
lines of nine values (`char id x y width height xoffset yoffset xadvance
page`): each rectangle is `(x, y + scaleH*page, width, height)` in the page
image (next to the `.fnt`; GRAYSCALE pages become GRAY_ALPHA), padding 0,
baseSize lineHeight. Fewer than four header values or no file name or count
give raylib's empty Font (`Fail`); a page that does not load gives the
default font when no glyph has pixels.

### ExportFontAsCode

`Font.as_code` builds raylib's file text byte for byte: the banner,
`COMPRESSED_DATA_SIZE_FONT_<NAME>` and the DEFLATE (`CompressData`, the
`sdefl` port) of `LoadImageFromTexture`'s data, which rlsw returns as zero
bytes ([TEXTURES.md](TEXTURES.md)), 20 bytes per line; the rectangles
(`%1.0f`) and GlyphInfo values; the `LoadFont_<Name>` function. The name is
`TextToPascal` of the file name without extension (`TextToUpper` for the
macro).

### Input domain

stb_truetype does no bounds checking. Jonlib checks every byte stb_truetype
would read against the font data and refuses (`FontDataRefused`, `None`) a
read outside it; it also refuses signed int overflows, float-to-int
conversions out of range, glyphs whose outline has no contour under a
non-empty box (raylib returns an uninitialized bitmap), an off-curve point
ending a glyph (stb reads past its points), CFF (OpenType) outlines,
composites nested deeper than 6, glyph bitmaps and atlases beyond 4096 and
more than 65536 codepoints.

## Refusals and None

- **Frame:** as in [FRAME.md](FRAME.md), a draw Jonlib does not reproduce marks
  the frame undefined: undefined C int conversions in `DrawText`/`DrawFPS`
  (`x`, `y`, `fontSize`), an unverified `DrawTextPro` rotation, and the
  rasterizer's own rules (NaN or out-of-range coordinates).
- `Font.measure_text`: `None` when `fontSize` or the width's `(int)` is
  undefined.
- `Font.image_text*`: `None` when raylib's image would be 0-sized (an empty
  text, or a width or height that truncates to 0: raylib returns a 0x0 image,
  which is not a `Surface`) and when the C code is undefined or outside this
  profile: an `(int)` of a size, advance or scaled size that is NaN or out of
  range, an int overflow in the offsets, a negative image size (raylib's
  `calloc` of a negative size), a resize to 0 (division by zero in
  `ImageResizeNN`) and sizes beyond 4096 (the Surface limit).
- `Font.image_draw_text*`: `Fail{OutOfDomain}` with the destination (and font)
  handed back for those refusals and for positions that are NaN or beyond
  32767 in magnitude (`ImageDraw`'s `(int)` and `int` products); an empty
  text image leaves the destination unchanged, as `ImageDraw` does.
- `Font.load_from_image`: `None` when raylib reads past the image (a row of key
  colors with nothing below, or a key-colored column ending at the last row),
  finds no glyph (it reads `recs[0]`), would record more than 256 glyphs
  (`MAX_GLYPHS_FROM_IMAGE`), when `firstChar + glyphCount - 1` overflows an
  int, when `LoadImageColors` is out of domain, or when the 127 texture ids
  are in use (raylib returns a font whose texture id is 0).
- `Font.glyph_info`: `None` only for a glyph rectangle that is not an
  integral region of the atlas, which the loaders never build.
- `Font.load_data` / `gen_image_atlas*` / `load_from_memory` / `load_ex` /
  `load` / `load_bmfont` / `as_code`: the cases listed in
  [TrueType, BDF and BMFont fonts](#truetype-bdf-and-bmfont-fonts); also
  `LoadFontFromMemory` fonts where no requested glyph is found (raylib then
  reads 95 glyphs from an empty array), glyph rectangles outside the atlas or
  BMFont page (`ImageFromImage` reads past it), negative image sizes, BMFont
  files with another page count than 1 (raylib frees the extra pages before
  drawing them), BMFont glyph lines without nine values and header lines
  without their field (raylib passes NULL to `sscanf`).

## Verification

| Gate | Tool | Compares |
|---|---|---|
| `font` | `tools/font_probe.py` | 69 scenes (855 operations, 19 of them seeded random scenes): default-font fields and glyph table, glyph queries, `MeasureText`/`MeasureTextEx`/`MeasureTextCodepoints` bits, framebuffers with `DrawText`/`DrawTextEx`/`DrawTextPro`/`DrawTextCodepoint(s)`/`DrawFPS`, `LoadFontFromImage` fonts, `ImageText*` and `ImageDrawText*` bytes against the uncontracted memory-platform raylib on CPU-1, CPU-2 and JavaScript; refusal contracts |

| `ttf` | `tools/ttf_probe.py` | 45 scenes (218 operations, 15 refusal contracts): `LoadFontData` glyphs (fields and every image byte) for FONT_DEFAULT, FONT_BITMAP and FONT_SDF, `GenImageFontAtlas` images and rectangle bits for both packing methods, fonts from `LoadFontFromMemory`, `LoadFontEx` and `LoadFont` (fields, whole glyph tables with every glyph image, `GetGlyphInfo`), `MeasureTextEx` bits, `ImageTextEx` bytes, `ExportFontAsCode` file bytes and `DrawTextEx` framebuffers, against the same reference on CPU-1, CPU-2 and JavaScript |

```sh
python3 tools/font_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --jobs 3
python3 tools/ttf_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --jobs 1
```

The probe also checks that `src/fonts.bend`'s `charsWidth` and
`src/frame_font.bend`'s bitmap equal the pinned `rtext.c`. Texts cover
ASCII, Latin-1 and multi-byte UTF-8, invalid and truncated sequences,
unknown codepoints, tabs, spaces, newlines (single, repeated, leading and
trailing), embedded NULs, 280-byte texts and the empty text; sizes and
spacings cover integral, fractional, zero, negative, tiny, huge and nonfinite
values; line spacings 2, 0, -5, 7, 100, 6, -4, 9, -30 and random ones; the
random scenes add texts mixing ASCII, newlines, tabs and multi-byte or
invalid UTF-8 for measurement, drawing and image text. Frames cover
positions inside, across and outside the screen, fractional positions and
sizes, tints over opaque and translucent backgrounds, overlapping text and
shapes, a 2D camera (zoom and rotation) and a scissor, 8 `DrawTextPro`
rotations with origins, codepoint lists, ten FPS values, and image fonts
drawn with POINT and BILINEAR filters. `GetFPS` is 0 in the reference build
(which defines `SUPPORT_CUSTOM_FRAME_CONTROL`, see
[VERIFICATION.md](VERIFICATION.md#reference-build-configuration)), so
`DrawFPS` is compared directly for 0 and, for other values, through its body
extracted from the pinned `rtext.c` with `GetFPS()` replaced by the value.
`LoadFontFromImage` runs on generated images (opaque and translucent glyphs,
R8G8B8A8, R8G8B8, R5G5B5A1 and GRAY_ALPHA sources, irregular gaps, exactly
256 glyphs, images that return the default font) and the refusals above; a
model of its scan in the probe decides which images raylib reads past.

The `ttf` probe's fonts are generated by `tools/ttf_fonts.py` (no third-party
glyph data): cmap formats 0, 4 (delta and range offsets), 6, 12, 13 and 2;
short and long `loca`; quadratic contours mixing on- and off-curve points,
repeated and short-vector flags and uncompressed coordinates, contours
starting off the curve, single-point contours; composites with byte and short
offsets, scale, x/y scale, 2x2, negative scale, nesting and the
point-matching form; glyph boxes smaller than their outlines (the
rasterizer's clipping path); line-only box fonts for SDF; a space with an
outline, a negative space advance, a 2048-unit font at 64 and 120 pixels, no
cmap, a CFF table and a truncated file. Two OFL fonts are read in place from
the pinned raylib checkout (`examples/text/resources/anonymous_pro_bold.ttf`,
`DotGothic16-Regular.ttf`, SIL Open Font License; not redistributed). The
probe also writes BDF files (without characters, with a space only, with
`SIZE` in hex and octal, the NULL-pointer write, no `ENDFONT`), AngelCode
BMFont files with RGBA and GRAYSCALE PNG pages (and the refused shapes) and
an XNA-style PNG for `LoadFont`. Atlases come from loaded glyphs and from
synthetic glyph sets with many equal sizes (ties in the rectangle sort),
heights built with McIlroy's quicksort adversary so Apple's introsort depth
limit falls back to heapsort, atlas growth and clipping, glyphs wider than
the atlas and unpacked rectangles. A native control checks that the host
`logf` gives `GenImageFontAtlas` the power itself at powers of two. The probe
selects the rectangle sort by the host's `M.Libm` profile; this host
(macOS) verifies the Apple sort, CI's Linux hosts the glibc one.

## Gaps

- CFF (OpenType `CFF ` outlines, stb's Type 2 charstring interpreter) is not
  ported: such fonts are refused.
- FONT_SDF glyphs with curves need `stbtt__solve_cubic` (the C library's
  double `pow`, `acos` and `cos`): refused; only line outlines (and degenerate
  curves) are reproduced.
- BMFont files with other than one page, atlas sizes in the 64 floats above a
  power of two (host `logf` rounding), composites nested deeper than 6,
  bitmaps and atlases beyond 4096 and more than 65536 codepoints are refused;
  BDF fonts behave as raylib 6.0's reader (characters give the default font).
- The rectangle sort of `GenImageFontAtlas` method 1 follows glibc's stable
  `qsort` or Apple Libc's; other C libraries are not modeled.
- The default font's texture is not shared with the frame's shapes atlas
  (see above): filtering or updating it does not reach shapes or `Draw.text`.
- Measurement is the uncontracted profile; contracted arm64 builds of raylib
  can differ in the last bit.
- `ImageText*` results beyond 4096 pixels and resizes to 0 are refused; the
  GPU (OpenGL 3.3) rendering of text is a separate contract.
