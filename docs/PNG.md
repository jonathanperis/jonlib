# PNG non-interlaced decoding

`Surface.decode_png(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with owned normalized RGBA8 pixels.

## Current profile

- Non-interlaced, 8-bit PNG color types **0, 2, 3, 4 and 6**: grayscale, RGB,
  palette, gray-alpha and RGBA.
- Packed **1/2/4-bit grayscale and palette** images (color types 0 and 3).
- **16-bit grayscale, RGB, gray-alpha and RGBA** images (color types 0/2/4/6).
  Samples are reconstructed big-endian and normalized through high-byte
  truncation, matching the native `stbi_load` path used by `LoadImageFromMemory`.
- Dimensions 1..4096, complete encoded input at most 1 MiB, and filtered scanline
  output `(ceil(width*channels*depth/8) + 1)*height` at most 64 MiB. The filtered byte count must
  match exactly; native recovery of excess inflated bytes is outside this profile.
- IHDR is first and unique; PLTE/tRNS precede IDAT. Multiple/split/empty IDAT
  chunks are combined in order. Unknown ancillary chunks are skipped; unknown
  critical chunks, CgBI and unsupported header fields are rejected.
- All five filters are reconstructed with exact byte arithmetic, including
  first-row/left-edge rules, Average truncation and Paeth ties.
- Packed samples are filtered as bytes with a one-byte neighbor distance, then
  extracted MSB-first within each row. Unused row-end bits are retained during
  filtering and excluded from output pixels. Grayscale samples expand by
  `255/((1<<depth)-1)`; palette indices remain unscaled.
- Palette entries default to alpha 255; tRNS replaces the supplied prefix.
  Missing palettes and indices beyond their actual entry count are rejected.
- For depths up to eight, grayscale/RGB tRNS keys use the low byte of each 16-bit field. Packed grayscale
  keys use the same scale as samples, then wrap to a byte, matching the native
  reader even for oversized key values. Exact key matches become transparent.
- For 16-bit input, tRNS compares the **full sample values** before RGBA8 narrowing.
  Two samples with equal high bytes can therefore have different output alpha.
  Existing 16-bit alpha is also narrowed by taking its high byte: 255 becomes 0,
  while 256 becomes 1. Existing 8-bit alpha retains its bytes, including zero.

## Native checksum and framing behavior

The pinned reader consumes chunk CRC fields but does not validate them. It also
does not validate Adler-32, and accepts a completed DEFLATE stream without that
trailer. Jonlib preserves these observed behaviors and checks them against native
execution. Zlib method, header checksum and preset-dictionary checks are retained.
The PNG-oriented inflater continues empty non-final stored blocks, as required
by the native PNG path; see [DEFLATE.md](DEFLATE.md).

Every supplied value must be a byte. Invalid bytes return `InvalidImageByte`;
unsupported/truncated chunk structures return `InvalidImageHeader`. Size-limit
violations return `UnsupportedImageSize`. Invalid zlib/DEFLATE data, filter modes,
raster lengths or palette indices return `InvalidImageStream`. Bounds are checked
before array indexing, and dimensions/filtered capacity before allocation.

Adam7 interlacing, CgBI, original-format metadata, generic dispatch
and broader malformed-input recovery remain gaps. PNG export is not implemented.

## Verification

```sh
python3 tools/png_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The probe checks 97 native images / 18,585 pixels and 32 typed-error controls on
CPU, JavaScript and forced Metal. Cases cross every supported color/filter family,
odd widths, packed-byte boundaries/nonzero padding, 4096-wide/tall dimensions,
transparency scaling/wrapping, close full-width transparency keys, 16-bit alpha
truncation, ancillary chunks, split IDATs, empty stored blocks
and ignored checksums. Expected pixels always come from actual `LoadImageFromMemory`.
The [initial 8-bit evidence](evidence/png-8bit.json) is retained alongside the
[packed-depth increment](evidence/png-packed.json) and
[16-bit normalization](evidence/png-16bit.json).

A minimized Metal compile failure isolated to chunk extraction was resolved by
collecting payload bytes first, then parsing the CRC field outside that tail loop.
The compiler overlay and native expectations were retained. The altered stb PNG
implementation retains [its MIT notice](../LICENSES/stb-image.txt). Complete
platform/resource/performance parity remains open.
