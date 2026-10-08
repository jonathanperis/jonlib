# Fonts and text drawing

Phase 3, first slice ([MASTER-PLAN.md](MASTER-PLAN.md)): raylib 6.0's
default font, fonts loaded from XNA-style images, glyph queries, text
measurement, text drawn into the [Frame](FRAME.md) and image text. Altered
Bend adaptations of `rtext.c` and of `rtextures.c`'s `ImageText*` functions
(zlib, [LICENSES/raylib.txt](../LICENSES/raylib.txt)); drawing goes through
the `rlsw.h` port of [FRAME.md](FRAME.md) and [TEXTURES.md](TEXTURES.md)
(MIT, [LICENSES/rlsw.txt](../LICENSES/rlsw.txt)). Code: the section "Fonts
and text drawing" of `jonlib.bend` and `src/fonts.bend` (glyph table, atlas
expansion, `GetGlyphIndex`, measurement, the `DrawTextEx` streams,
`ImageTextEx`'s placement and `LoadFontFromImage`'s scan); the default font
bitmap is `src/frame_font.bend`.

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
- `GlyphInfo{value, offset_x, offset_y, advance_x, image}`, `FontInfo{base_size,
  glyph_count, glyph_padding, texture}` (the texture id).
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
| `GetGlyphIndex` / `GetGlyphInfo` / `GetGlyphAtlasRec` | `Font.glyph_index`, `Font.glyph_info -> Font & Maybe<GlyphInfo>`, `Font.glyph_atlas_rec` |
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
- `Font.glyph_info`: `None` only for a glyph rectangle that is not a positive
  integral region of the atlas, which the loaders never build.

## Verification

| Gate | Tool | Compares |
|---|---|---|
| `font` | `tools/font_probe.py` | 69 scenes (855 operations, 19 of them seeded random scenes): default-font fields and glyph table, glyph queries, `MeasureText`/`MeasureTextEx`/`MeasureTextCodepoints` bits, framebuffers with `DrawText`/`DrawTextEx`/`DrawTextPro`/`DrawTextCodepoint(s)`/`DrawFPS`, `LoadFontFromImage` fonts, `ImageText*` and `ImageDrawText*` bytes against the uncontracted memory-platform raylib on CPU-1, CPU-2 and JavaScript; refusal contracts |

```sh
python3 tools/font_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --jobs 3
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

## Gaps

- `LoadFont`, `LoadFontEx`, `LoadFontFromMemory`, `LoadFontData`,
  `GenImageFontAtlas`, `UnloadFontData` and `ExportFontAsCode` are not ported:
  TTF/OTF needs `stb_truetype` (rasterization with floating-point coverage and
  `stb_rect_pack`), BDF and BMFont their parsers. Fonts with offsets, advance
  or padding are therefore only reachable by building a `Font` by hand.
- The default font's texture is not shared with the frame's shapes atlas
  (see above): filtering or updating it does not reach shapes or `Draw.text`.
- Measurement is the uncontracted profile; contracted arm64 builds of raylib
  can differ in the last bit.
- `ImageText*` results beyond 4096 pixels and resizes to 0 are refused; the
  GPU (OpenGL 3.3) rendering of text is a separate contract.
