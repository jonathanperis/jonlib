# JPEG

`src/jpeg.bend` adapts pinned stb_image's JPEG decoder, which raylib uses when
built with `SUPPORT_FILEFORMAT_JPG` (off in default raylib, on in the reference
archive the codec gates use). Baseline, extended and progressive Huffman frames
decode; arithmetic coding, lossless and 12-bit frames fail, as in stb.

| Function | raylib | Contract |
|---|---|---|
| `Surface.decode_image(".jpg", bytes)` (and the other raster tokens) | `LoadImageFromMemory` | JPEG content (0xFF fill bytes then SOI) after the PNG/BMP/PNM/PSD/PIC/GIF signatures, before the TGA fallback. |
| `Surface.decode_jpeg(bytes)` / `Surface.load_jpeg(path)` | — | The JPEG decoder alone. |
| `Surface.load_image(path)` | `LoadImage` | `.jpg`/`.jpeg` names (either case) through the same dispatch. |

Results are GRAYSCALE (1) for one-component frames and R8G8B8 (4) otherwise:
YCbCr through stb's fixed-point conversion, RGB when the component ids are
`R`, `G`, `B` or an Adobe marker says transform 0 without JFIF, CMYK (Adobe
transform 0) and YCCK (transform 2) through stb's rounded products, and other
four-component frames as YCbCr. Chroma is upsampled as stb does: fancy 2x
horizontal, vertical and 2x2 filters and nearest-neighbor otherwise.

The decoder keeps stb's arithmetic and stream behavior exactly:

- the integer IDCT with stb's truncated constants (for example -7567, where
  libjpeg uses -7568), 16-bit coefficient wrapping and arithmetic shifts;
- stb's 32-bit entropy buffer: bytes past the end of the data read as 0, a
  marker inside the data stops filling and later bits are zero, codes that
  need more bits than remain are errors, and its 9-bit fast tables decide
  which short codes fail at a marker;
- streams that never define a Huffman or quantization table decode with stb's
  zeroed tables (symbol 0 with no bits, factor 0);
- restart intervals, a scan ending where no restart marker follows, junk after
  a scan, extra fill bytes, DNL markers and an unknown marker after the frame
  (which ends the image successfully) follow stb's marker loop.

Jonlib contracts where stb's result is not defined or not supported:

- dimensions above 4096 are `UnsupportedImageSize`;
- an image stb would take from uninitialized memory is `InvalidImageStream`:
  a component no scan completely wrote (baseline) or initialized with a first
  DC scan (progressive), or a progressive stream that ends before EOI, for
  which stb skips its final dequantization and transform;
- other failures are `InvalidImageHeader` (headers and markers) or
  `InvalidImageStream` (entropy-coded data); raylib returns no image.

## How it is verified

`tools/jpeg_probe.py` (gate `jpeg`) builds raylib with
`SUPPORT_FILEFORMAT_JPG=ON` and compares native `LoadImageFromMemory(".jpg")`
with Jonlib's file loading by `.jpg` names (the `Surface.decode_image`
dispatch) on every committed fixture in `tests/fixtures/jpeg` and on variants
derived from them: format, dimensions and every stored byte, or failure on both
sides. The fixtures cover 1x1 to 64x48 images; grayscale, 4:4:4, 4:2:0, 4:2:2,
4:4:0, 4:1:1, 3:1:1 and mixed sampling; baseline and progressive (including
successive-approximation refinement) frames; restart intervals per block and
per row; quality 1 (16-bit tables) and 100; optimized and arithmetic coding;
RGB and CMYK. The variants add YCCK and Adobe-RGB markers, truncated baseline
and progressive data, junk after EOI, a missing EOI, extra fill bytes, a
flipped entropy byte, removed Huffman tables, a bad SOI, lossless and 12-bit
frames and the two contracts above. `Surface.load_jpeg` and a `.JPEG` name are
checked too, on CPU-1, CPU-2 and JavaScript.

The fixtures were produced once from synthetic pixels by libjpeg-turbo's
`cjpeg` (and PIL for CMYK); `tools/jpeg_fixtures.py` records and regenerates
them, and `tests/fixtures/jpeg/manifest.json` lists each command. Native
raylib, not the encoder, is the reference.

Not covered: hosts other than the CI pair, larger images and performance, and
decoding on the GPU lane.
