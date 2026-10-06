# PNG decoding

| API | Contract |
|---|---|
| `Surface.decode_png(bytes: +List<U32>)` | Returns `Result<&1, &1, Surface.Error, Surface>` preserving the native 8-bit output format (1/2/4/7) and bytes; see [format-preserving memory loading](#format-preserving-png-memory-loading). |
| `Surface.load_png(path: String)` | Returns `IO(Result<&1, &1, Surface.IOError, Surface>)` through the shared bounded, exact-read, close-before-decode file boundary; see [format-preserving file loading](#format-preserving-png-file-loading). |

Shared memory/file dispatch (`Surface.decode_image`,
`Surface.load_image`) uses the same profile; see [IMAGE-FILES.md](IMAGE-FILES.md).
Exact PNG export is documented in [IMAGE-EXPORT.md](IMAGE-EXPORT.md).

## Supported profile

- 8-bit PNG color types **0, 2, 3, 4 and 6**: grayscale, RGB, palette,
  gray-alpha and RGBA.
- Packed **1/2/4-bit grayscale and palette** images (color types 0 and 3).
- **16-bit grayscale, RGB, gray-alpha and RGBA** images (color types 0/2/4/6).
  Samples are reconstructed big-endian and normalized through high-byte
  truncation, matching the native `stbi_load` path used by `LoadImageFromMemory`.
- Both non-interlaced and **Adam7-interlaced** input for these combinations.
- Dimensions 1..4096, complete encoded input at most 1 MiB, and filtered scanline
  output at most 64 MiB. For non-interlaced images the size is
  `(ceil(width*channels*depth/8) + 1)*height`; for Adam7 it is the sum of that
  expression over nonempty pass dimensions. The filtered byte count must match
  exactly; native recovery of excess inflated bytes is outside this profile.
- IHDR is the first image header and unique; CgBI markers may precede it.
  PLTE/tRNS precede IDAT. Multiple/split/empty IDAT chunks are combined in order.
  Unknown ancillary chunks are skipped; unknown critical chunks and unsupported
  header fields are rejected.
- All five filters are reconstructed with exact byte arithmetic, including
  first-row/left-edge rules, Average truncation and Paeth ties.
- Packed samples are filtered as bytes with a one-byte neighbor distance, then
  extracted MSB-first within each row. Unused row-end bits are retained during
  filtering and excluded from output pixels. Grayscale samples expand by
  `255/((1<<depth)-1)`; palette indices remain unscaled.
- Palette entries default to alpha 255; tRNS replaces the supplied prefix.
  Missing palettes and indices beyond their actual entry count are rejected.
- For depths up to eight, grayscale/RGB tRNS keys use the low byte of each 16-bit
  field. Packed grayscale keys use the same scale as samples, then wrap to a byte,
  matching the native reader even for oversized key values. Exact key matches
  become transparent.
- For 16-bit input, tRNS compares the **full sample values** before RGBA8
  narrowing. Two samples with equal high bytes can therefore have different
  output alpha. Existing 16-bit alpha is also narrowed by taking its high byte:
  255 becomes 0, while 256 becomes 1. Existing 8-bit alpha retains its bytes,
  including zero.

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
normalization described above. This distinction is visible for
premultiplied-looking and zero-alpha samples. External callers changing stb's
global/thread-local conversion flags are outside the profile.

Raw CgBI uses the PNG inflater policy and continues empty non-final stored blocks.

## Native checksum and framing behavior

The pinned reader consumes chunk CRC fields but does not validate them. It also
does not validate Adler-32, and accepts a completed DEFLATE stream without that
trailer. Jonlib preserves these behaviors. Zlib method, header checksum and
preset-dictionary checks are retained for ordinary framed PNG input. The
PNG-oriented inflater continues empty non-final stored blocks, as required by the
native PNG path; see [DEFLATE.md](DEFLATE.md).

## Errors

Every supplied value must be a byte. Invalid bytes return `InvalidImageByte`;
unsupported/truncated chunk structures return `InvalidImageHeader`. Size-limit
violations return `UnsupportedImageSize`. Invalid zlib/DEFLATE data, filter modes,
raster lengths or palette indices return `InvalidImageStream`. Bounds are checked
before array indexing, and dimensions/filtered capacity before allocation.

## Format-preserving PNG memory loading

`Surface.decode_png(bytes: +List<U32>)` returns
`Result<&1, &1, Surface.Error, Surface>`. It accepts the same checked
PNG domain as `Surface.decode_png`: the color/depth combinations, Adam7 passes,
filter arithmetic, CgBI defaults, chunk ordering, palette/key behavior and
inclusive limits above are unchanged. It takes no format, channel or reference
argument. Success creates one affine owner with the decoded width/height and an
implicit single mip level; failure returns only the existing typed error. The
immutable encoded list can be reused for independent decodes.

Native output channels follow image structure rather than observed opacity:

| PNG structure | Format | Row-major exported components |
|---|---|---|
| Grayscale (color 0), no tRNS | **1 (grayscale)** | G |
| Grayscale with tRNS, or gray-alpha (color 4) | **2 (gray-alpha)** | G,A |
| RGB (color 2) or palette (color 3), no tRNS | **4 (RGB888)** | R,G,B |
| RGB/palette with tRNS, or RGBA (color 6) | **7 (RGBA8888)** | R,G,B,A |

A valid tRNS key promotes grayscale/RGB even when no pixel matches. Palette tRNS
promotes to RGBA even when its payload is empty, all supplied alphas are 255, or
only unused entries have nonopaque alpha. That promotion remains set across a
later accepted PLTE, although PLTE replaces palette colors and resets their alpha
bytes to 255. Repeated accepted tRNS chunks retain promotion. There is no opacity
scan or inference from normalized pixels to choose the format. Existing-alpha
color types retain their channels even if every alpha is 255; tRNS on those types
remains invalid under the checked parser.

Packed grayscale expands to 8-bit G values; indexed PNG exports palette colors,
not indices. All 16-bit input is reduced to the high byte of each reconstructed
sample after full-width tRNS comparison. This preserves the native 8-bit
`LoadImageFromMemory` result, not source bit depth. CgBI uses raw DEFLATE with
the pinned default conversion flags unchanged: no added BGR swap or
unpremultiplication, including hidden color at zero alpha.

`Surface.export` consumes the owner and returns
`((width, height), (format, bytes))`, with exactly `width*height*channels`
component bytes and no storage padding. Logical packed words use G, G/A, R/G/B
or R/G/B/A in successive low bytes; unused upper bytes are zero. Integer packing
avoids an F32 conversion or a grayscale luminance round trip.
`Surface.colors` reads the same RGBA8 values native `LoadImageColors` returns.
The candidate's single mip level is an implicit type
contract, not a stored field.

### Limits and error ordering

Dimensions are 1..4096 on each axis. The complete encoded list, including bytes
after IEND, has an **inclusive 1,048,576-byte cap**; the filtered scanline/pass
stream has an **inclusive 67,108,864-byte cap**. These are admission bounds, not
a maximum-area allocation or runtime-memory guarantee.

The input walk runs before signature/chunk parsing and stops at its first error.
An out-of-range value gives `InvalidImageByte`; a valid byte at the first
position beyond the encoded cap gives `UnsupportedImageSize`. If that first
excess value is itself out of range, `InvalidImageByte` wins. Values after an
already detected cap error are not inspected. Thus an invalid header does not
override an earlier input-walk byte/size error.

Invalid signatures, unsupported/truncated chunk structures and malformed IHDR
fields yield `InvalidImageHeader`; a structurally accepted IHDR with zero or
oversized dimensions yields `UnsupportedImageSize`. After chunk parsing, an
oversized filtered-stream requirement yields `UnsupportedImageSize` before
inflation. Invalid framing/DEFLATE, filters, exact raster lengths and palette
indices yield `InvalidImageStream`. Trailing byte-valued data after a complete
IEND remains ignored after whole-input validation. Checked rules can be stricter
than native malformed-stream recovery; the formatted factory changes none of the
Surface decoder's admissions or error precedences.

### Native source contract

The pinned `rtextures.c` lines 461–471 use `stbi_load_from_memory` with requested
channels zero, set one mip and map returned components to formats 1/2/4/7.
`stb_image.h` lines 5119–5234 and 5284–5286 retain tRNS-derived components,
including palette promotion independently of alpha values or later PLTE.
Lines 1190–1203 and 1260–1273 apply the final high-byte reduction to 16-bit
results; lines 4993–4994 and 5222–5223 retain disabled CgBI conversion defaults.
These source-derived rules define the contract; the probes establish the
exercised profile.

## Format-preserving PNG file loading

`Surface.load_png(path: String)` wraps the shared `RasterFile` reader
and the unchanged formatted decoder. PNG is selected explicitly, independently
of the path suffix. The shared inclusive 1 MiB file cap, one exact-length read
and close-before-decode call ordering neither enlarge nor replace the encoded and
filtered-stream memory limits above. Native formats 1/2/4/7, exact 8-bit bytes
and the implicit single mip are preserved. The full ordered file/error contract
is in [IMAGE-FILES.md](IMAGE-FILES.md).

## How it is verified

Every expected result comes from the pinned native raylib (`LoadImageFromMemory`
or `LoadImage`), compared exactly on the CPU-1, CPU-2 and JavaScript lanes.

- **Surface decoding** (`tools/png_probe.py`, gate `png`): normalized RGBA8
  pixels and typed-error controls across every supported color/filter family,
  odd widths, packed-byte boundaries with nonzero padding, 4096-wide/tall images,
  transparency scaling/wrapping, close full-width 16-bit keys, 16-bit alpha
  truncation, every supported Adam7 color/depth combination with tiny/thin/odd
  pass geometries, native-default CgBI samples/framing/markers, ancillary chunks,
  split IDATs, empty stored blocks and ignored checksums. `--gpu` adds a
  forced-GPU lane (local only).
- **Format-preserving memory loading** (`tools/png_format_probe.py` on the shared
  driver `tools/formatted_codec.py`, gate `png-format`): native dimensions,
  format, `mipmaps == 1` and every raw byte are captured before separate
  normalization, then compared with the raw export, checked factory, export/import
  round trip, retained point-read owner, consuming Surface bridge and the
  normalized/dispatch paths (including uppercase tokens). Only independently
  admitted complete fixtures reach native code; a `.png` suffix alone proves no
  PNG identity because stb sniffs content. Structural cases distinguish absent,
  empty, opaque, unused-entry and nonmatching tRNS, including later-PLTE resets;
  all four output layouts include single, padded, 4096-axis, moderate and
  byte-ramp images; the encoded-cap endpoint and byte/size precedence are checked.
  A small qualification program checks structural-channel, full-width-key and
  CgBI vectors before the broad oracle. Malformed controls run only in checked
  Jonlib.
- **Format-preserving file loading** (`tools/png_file_probe.py` on
  `tools/formatted_file.py`, gate `png-file`): every accepted memory fixture as a
  real file plus path variants (case, suffixless, misleading, multi-dot and
  other-codec content); native recognized suffixes go through `LoadImage`, others
  through `LoadFileData` plus `LoadImageFromMemory(".png")`. Also file controls
  and the shared resource runs (closure loop, sparse/oversized and exact-cap files).
- Shared dispatch is covered by `image-memory` and `image-file`
  (`tools/image_memory_probe.py`, `tools/image_file_probe.py`).

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only png-format
```

Gates run in CI on Ubuntu and macOS (CPU/JavaScript); see [CI.md](CI.md).

## Known gaps

- Nondefault external stb decoder flags and broader native malformed-input
  recovery.
- Original source bit depth (16-bit output).
- GPU for the formatted paths, Windows/browser and big-endian targets.
- Native pointer/allocation ABI, allocation-failure parity, maximum-area success
  and representative performance.
- Ledger scope: the formatted memory factory is partial
  `raylib:function:LoadImageFromMemory` scope and the formatted file loader
  partial `raylib:function:LoadImage` scope; neither completes an API.

## Provenance

The PNG reader is an altered Bend implementation of the pinned stb PNG paths; it
retains [stb's MIT notice](../LICENSES/stb-image.txt).
