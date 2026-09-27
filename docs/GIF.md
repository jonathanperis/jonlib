# First-frame GIF decoding

`Surface.decode_gif(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with owned RGBA8 pixels. Shared
memory/file dispatch recognizes `GIF87a` and `GIF89a` signatures.

## Current profile

- Logical dimensions 1..4096. The first image must cover the full canvas at
  origin zero and be non-interlaced.
- Global or local RGB palettes; local palettes override the global table.
- Graphic Control transparency, including repeated control changes. Transparent
  first-frame pixels become transparent black, matching the native zeroed canvas.
- Other extension sub-blocks are consumed with availability checks. Delay and
  disposal metadata are not exposed in this first-frame API.
- LSB-first GIF LZW with minimum code sizes 2..8, required initial clear, clear
  resets, dictionary growth/width changes and next-code self-reference.
- Owned storage is bounded to the image and an 8,192-entry native-sized dictionary.
  Code widths stop at 12 bits. Bit and prefix-chain fuel ensures structural
  termination; dictionary and output bounds are checked before writes.
- Exactly the required number of pixels and valid palette references are required.
  The first completed raster is returned; later frames/trailing data are ignored.

Invalid bytes return `InvalidImageByte`; incomplete/unsupported headers, missing
tables or unsupported frame geometry return `InvalidImageHeader`; dimensions
outside the profile return `UnsupportedImageSize`. Incomplete palettes/sub-blocks
return `TruncatedImageData`. Invalid LZW, missing/extra pixels or palette indices
outside the selected table return `InvalidImageStream`.

Offset/interlaced frames, animation/disposal/timing, original metadata, native
malformed recovery and full resource/platform/performance coverage remain gaps.

## Verification

```sh
python3 tools/gif_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares 19 native images / 4,738 pixels and 20 error controls on CPU,
JavaScript and forced Metal. Cases cover versions, palettes, transparency,
extensions, one-byte sub-blocks, self-reference, resets, every supported minimum
code size and a 4,096-pixel stream that reaches 12-bit codes and clears its table.
An independent malformed stream fits the image but exceeds dictionary capacity,
checking dictionary rejection separately from output bounds.
Shared memory/file gates include actual GIF payloads and cross-extension loading.
Hashes and outcomes are in [evidence/gif-first-frame.json](evidence/gif-first-frame.json).

The altered stb reader retains its MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt), including upstream GIF credit
to Jean-Marc Lienher and stb.
