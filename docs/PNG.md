# PNG decoding

`Surface.decode_png(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with owned normalized RGBA8 pixels.

## Current profile

- 8-bit PNG color types **0, 2, 3, 4 and 6**: grayscale, RGB,
  palette, gray-alpha and RGBA.
- Packed **1/2/4-bit grayscale and palette** images (color types 0 and 3).
- **16-bit grayscale, RGB, gray-alpha and RGBA** images (color types 0/2/4/6).
  Samples are reconstructed big-endian and normalized through high-byte
  truncation, matching the native `stbi_load` path used by `LoadImageFromMemory`.
- Both non-interlaced and **Adam7-interlaced** input for these combinations.
- Dimensions 1..4096, complete encoded input at most 1 MiB, and filtered scanline
  output at most 64 MiB. For non-interlaced images the size is
  `(ceil(width*channels*depth/8) + 1)*height`; for Adam7 it is the sum of that
  expression over nonempty pass dimensions. The filtered byte count must
  match exactly; native recovery of excess inflated bytes is outside this profile.
- IHDR is the first image header and unique; CgBI markers may precede it.
  PLTE/tRNS precede IDAT. Multiple/split/empty IDAT
  chunks are combined in order. Unknown ancillary chunks are skipped; unknown
  critical chunks and unsupported header fields are rejected.
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

## Adam7 passes

The seven native origin/stride tuples determine each pass's exact width, height
and packed row size. Empty passes consume no bytes or pass storage. Filtering
starts afresh in each nonempty pass; the remaining decompressed stream is retained
for the next pass. Normalized RGBA8 pixels are scattered to their full-image
coordinates through the pass strides. Palette and transparency operations are
pointwise, so applying them before scattering preserves the native final pixels.
The complete pass stream must be consumed, including its filter bytes.

## Native-default CgBI behavior

CgBI markers select raw DEFLATE for IDAT rather than zlib framing. Marker payload
contents are ignored, matching the pinned reader; markers before/after IHDR,
after IDAT and repeated markers retain the selected framing through IEND.

The pinned native defaults disable iPhone channel conversion and
unpremultiplication. This profile therefore applies **no additional BGR swap or
alpha division**: stored channel/alpha values follow the ordinary sample-to-RGBA8
normalization described above. This distinction is visible for premultiplied-looking
and zero-alpha samples. External callers changing stb's global/thread-local
conversion flags are outside the current profile.

Raw CgBI uses the PNG inflater policy and continues empty non-final stored blocks.

## Native checksum and framing behavior

The pinned reader consumes chunk CRC fields but does not validate them. It also
does not validate Adler-32, and accepts a completed DEFLATE stream without that
trailer. Jonlib preserves these observed behaviors and checks them against native
execution. Zlib method, header checksum and preset-dictionary checks are retained
for ordinary framed PNG input.
The PNG-oriented inflater continues empty non-final stored blocks, as required
by the native PNG path; see [DEFLATE.md](DEFLATE.md).

Every supplied value must be a byte. Invalid bytes return `InvalidImageByte`;
unsupported/truncated chunk structures return `InvalidImageHeader`. Size-limit
violations return `UnsupportedImageSize`. Invalid zlib/DEFLATE data, filter modes,
raster lengths or palette indices return `InvalidImageStream`. Bounds are checked
before array indexing, and dimensions/filtered capacity before allocation.

Nondefault external stb decoder flags, original-format metadata, generic dispatch
and broader malformed-input recovery remain gaps. Exact default byte-format export is
documented in [PNG-EXPORT.md](PNG-EXPORT.md).

## Verification

```sh
python3 tools/png_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The probe checks 193 native images / 31,677 pixels and 39 typed-error controls on
CPU, JavaScript and forced Metal. Cases cross every supported color/filter family,
odd widths, packed-byte boundaries/nonzero padding, 4096-wide/tall dimensions,
transparency scaling/wrapping, close full-width transparency keys, 16-bit alpha
truncation, all supported Adam7 color/depth combinations and tiny/thin/odd pass
geometries, native-default CgBI samples/framing/markers, ancillary chunks, split IDATs, empty stored blocks
and ignored checksums. Expected pixels always come from actual `LoadImageFromMemory`.
The [initial 8-bit evidence](evidence/png-8bit.json) is retained alongside the
[packed-depth increment](evidence/png-packed.json) and
[16-bit normalization](evidence/png-16bit.json) and
[Adam7 reconstruction](evidence/png-adam7.json) and
[CgBI defaults](evidence/png-cgbi.json).

A minimized Metal compile failure isolated to chunk extraction was resolved by
collecting payload bytes first, then parsing the CRC field outside that tail loop.
The compiler overlay and native expectations were retained. The altered stb PNG
implementation retains [its MIT notice](../LICENSES/stb-image.txt). Complete
platform/resource/performance parity remains open.
