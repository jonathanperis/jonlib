# First-frame GIF decoding

`Surface.decode_gif(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with owned RGBA8 pixels. Shared
memory/file dispatch recognizes `GIF87a` and `GIF89a` signatures.

## Current profile

- Logical dimensions 1..4096. Positive first-image rectangles may be offset
  within the canvas; returned dimensions are the logical canvas dimensions.
- Both sequential rows and four-pass interlacing are supported. Interlace row
  origins are 0/4/2/1 with steps 8/8/4/2, relative to the image rectangle.
- Global or local RGB palettes; local palettes override the global table.
- Graphic Control transparency, including repeated control changes. Transparent
  first-frame pixels become transparent black, matching the native zeroed canvas.
- Untouched canvas pixels remain transparent black when the background index is
  zero. A positive index uses the global palette with native first-frame byte
  copying: red and blue are swapped and alpha is forced to 255. Transparent
  decoded pixels stay black/transparent even when surrounding canvas pixels get
  that background. A required missing/out-of-table background entry is rejected.
- Other extension sub-blocks are consumed with availability checks. Delay and
  disposal metadata are not exposed in this first-frame API.
- LSB-first GIF LZW with minimum code sizes 2..8, required initial clear, clear
  resets, dictionary growth/width changes and next-code self-reference.
- Owned storage is bounded to the image and an 8,192-entry native-sized dictionary.
  Code widths stop at 12 bits. Bit and prefix-chain fuel ensures structural
  termination; dictionary and output bounds are checked before writes.
- Exactly the rectangle's number of pixels and valid palette references are required.
  The first completed raster is returned; later frames/trailing data are ignored.

Invalid bytes return `InvalidImageByte`; incomplete/unsupported headers, missing
tables, invalid backgrounds or out-of-canvas/empty rectangles return `InvalidImageHeader`; dimensions
outside the profile return `UnsupportedImageSize`. Incomplete palettes/sub-blocks
return `TruncatedImageData`. Invalid LZW, missing/extra pixels or palette indices
outside the selected table return `InvalidImageStream`.

Bounded owned animations with retain/restore disposal are documented in
[GIF-ANIMATION.md](GIF-ANIMATION.md). Original metadata, zero-area/native malformed
malformed recovery and full resource/platform/performance coverage remain gaps.

## Verification

```sh
python3 tools/gif_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares 41 native images / 5,410 pixels and 23 error controls on CPU,
JavaScript and forced Metal. Cases cover versions, palettes, transparency,
extensions, one-byte sub-blocks, self-reference, resets, every supported minimum
code size and a 4,096-pixel stream that reaches 12-bit codes and clears its table.
An independent malformed stream fits the image but exceeds dictionary capacity,
checking dictionary rejection separately from output bounds.
Geometry cases cover edge-aligned/offset rectangles, native background byte order,
transparent-vs-untouched pixels, global/local palettes and thin/interlaced pass
boundaries through seventeen rows.
Shared memory/file gates include actual GIF payloads and cross-extension loading.
Hashes and outcomes are in [evidence/gif-geometry.json](evidence/gif-geometry.json).

The altered stb reader retains its MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt), including upstream GIF credit
to Jean-Marc Lienher and stb.
