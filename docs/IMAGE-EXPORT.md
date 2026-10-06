# Image export

Jonlib adapts raylib 6.0 `ExportImage` and `ExportImageToMemory` for three image
owners: canonical RGBA8 `Surface`, checked `Image.Formatted` (formats 1..8) and
`Image.FloatRGB` (format 9). Every encoder is pure Bend and reproduces the
complete native file bytes, not just the decoded pixels. `ExportImage` remains a
**partial** mapping: only the slices below are covered.

| API | Result |
|---|---|
| `Surface.write_image(surface, path)` | `IO(Result<&1, &1, Image.ExportError, Unit>)`; codec chosen by filename suffix |
| `Surface.to_png` / `to_bmp` / `to_tga` / `to_qoi(surface)` | `+List<U32>` (complete file bytes) |
| `Surface.write_png` / `write_bmp` / `write_tga` / `write_qoi(surface, path)` | `IO(Result<&1, &1, U32 & String, Unit>)` |
| `Image.Formatted.to_png(image)` | `Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>` |
| `Image.Formatted.to_bmp` / `to_tga(image)` | `+List<U32>` |
| `Image.Formatted.to_qoi(image)` | `Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>` |
| `Image.Formatted.write_png` / `write_bmp` / `write_tga` / `write_raw(image, path)` | `IO(Result<&1, &1, U32 & String, Unit>)` |
| `Image.Formatted.write_qoi(image, path)` | `IO(Result<&1, &1, Image.Formatted.QoiWriteError, Unit>)` |
| `Image.FloatRGB.to_png` / `to_bmp` / `to_tga(image)` | `Result<&1, &1, Image.FloatRGB, +List<U32>>` |
| `Image.FloatRGB.write_png` / `write_bmp` / `write_tga` / `write_raw(image, path)` | `IO(Result<&1, &1, Image.FloatRGB.WriteError, Unit>)` |

Every `write_<codec>` selects its codec explicitly, independently of the path
extension (`.dat`, suffixless names and a misleading `.png` all work). Only
`Surface.write_image` dispatches on the filename. `to_png` corresponds to
`ExportImageToMemory(image, ".png")`; the pure BMP/TGA/QOI byte conveniences
adapt `ExportImage` file output, because native `ExportImageToMemory` implements
PNG only.

## Filename-suffix dispatch

`Surface.write_image` selects PNG, BMP, TGA, QOI or RAW from the filename and
reuses the corresponding Surface encoder (RAW goes through
`Surface.to_formatted` and `Image.Formatted.write_raw`).

- Suffix matching is ASCII case-insensitive: `.png`, `.PNG` and `.PnG` select
  the same encoder. The filename itself is never lowercased.
- The last dot in the **whole path** determines the suffix, matching
  `GetFileExtension`. A dot at position zero is not an extension: the path
  `.png` is rejected, while `images/.png` is accepted.
- A suffix must match completely; `image.png-tail` and
  `directory.png/no-extension` are rejected.
- This differs from the exact lowercase/all-uppercase memory-loading tokens in
  [IMAGE-FILES.md](IMAGE-FILES.md).

```bend
type Image.ExportError is Type:
  UnsupportedImageExport{surface: Surface}
  ImageExportFileError{code: U32, message: String}
```

`UnsupportedImageExport` returns the unchanged owned Surface before any file is
opened, so unsupported paths cannot truncate existing files.
`ImageExportFileError` preserves the Base file error. A selected encoder
consumes its Surface, including on open or write failure. Inputs are checked
Surface owners and ordinary non-NUL paths.

RAW output is native RGBA byte order, not the host byte order of Surface's
packed `0xRRGGBBAA` words. Dimensions and format are not stored in RAW files
and must be tracked separately.

## Source domains

- **Surface**: dimensions 1..4096 and row-major packed `0xRRGGBBAA` words. Only
  logical pixels are encoded; array-capacity padding is excluded. Every export
  consumes the Surface; use `Surface.copy` first when a separate owner is needed.
- **Image.Formatted**: dimensions **1..4096** on each axis, format codes **1..8**,
  one mip level and complete native-order samples, from `Image.Formatted.from_bytes`,
  the format-preserving loaders, the Surface bridge or supported conversions.
  R32 (format 8) samples are finite `[0,1]`, including both signed zeros and
  positive subnormals. Manually inconsistent `FormattedImage` constructors are
  outside the contract.
- **Image.FloatRGB**: see the per-codec rules below; file-style paths accept
  finite `[0,1]` samples only.

### Packed, R32 and float color expansion

Native file export prepares non-RGBA8 sources with `LoadImageColors`, which
differs from normalized `ImageFormat`. Jonlib follows it and therefore never
routes these sources through `Image.Formatted.to_surface`:

| Source | RGBA8 used by file export |
|---|---|
| 3: RGB565 | 5-bit channels ×8, 6-bit channel ×4, alpha 255; `0xffff` gives **(248,252,248,255)**, not the (255,255,255,255) of `ImageFormat` |
| 5: RGB5A1 | 5-bit channels ×8, alpha bit ×255; blue comes from bits 1..5, excluding alpha (unlike the pinned raw `GetPixelColor` quirk) |
| 6: RGBA4 | Every nibble ×17 |
| 8: R32 | Red is truncated F32 `sample*255`; green/blue 0; alpha 255 |
| 9: FloatRGB | Each finite `[0,1]` channel truncated from F32 `component*255`; alpha 255. No tone mapping or clamping |

## PNG

`Surface.to_png` and `Surface.write_png` produce non-interlaced 8-bit RGBA with
one IHDR, one IDAT and IEND, matching native `ExportImageToMemory(image, ".png")`
under the default writer settings.

**Formatted memory export** (`Image.Formatted.to_png`) encodes byte formats
directly, retaining native channels and byte order instead of normalizing
through RGBA8:

| Source format | Channels | PNG color type |
|---|---:|---:|
| 1: grayscale | 1 | 0 |
| 2: gray-alpha | 2 | 4 |
| 4: RGB888 | 3 | 2 |
| 7: RGBA8888 | 4 | 6 |
| 8: R32 | 4 | 6 (raw sample bytes) |

Filtering uses the channel count as its left-neighbor distance. R32 memory
export feeds each stored four-byte word directly to the four-channel encoder,
as native `ExportImageToMemory` does: it is an 8-bit RGBA PNG of those bytes,
not a float PNG. Packed formats 3/5/6 return the original image with
`UnsupportedPixelFormat`, dimensions, format and pixels intact (their native
default four-channel reads would exceed two-byte-per-pixel storage). Success
consumes the owner.

**Formatted file export** (`Image.Formatted.write_png`) accepts every checked
format 1..8. Byte formats keep their channels; packed and R32 sources use the
`LoadImageColors` expansion above and are encoded as RGBA8. Memory and file
channel selection are deliberately separate: an R32 sample `0.5` decodes to
`0000003f` from memory export and `7f0000ff` from file export.

**FloatRGB** follows the same native split:

- `Image.FloatRGB.to_png` treats float storage as four byte channels and encodes
  the first `width*height*4` little-endian bytes without converting float values.
  This is a contiguous prefix of the RGB sample words, not one component per
  pixel. Non-NaN sample words, including infinities and subnormals, are
  supported; rejection returns the owner.
- `Image.FloatRGB.write_png` uses the normalized `LoadImageColors` path. For
  one RGB pixel `(0.5, 0.25, 0.75)` memory PNG decodes to **`0000003f`** and file
  PNG to **`7f3fbfff`**.

### Reference writer profile

The pinned stb writer uses compression quality **8**, automatic filtering (`-1`)
and no vertical flip. The Bend encoder retains:

- All five filter candidates, scored by the sum of absolute **signed-byte**
  residuals; strict less-than selection keeps the earliest filter on ties.
- The stb three-byte hash, 16,384 buckets, newest equal-length match selection,
  32,767-byte maximum match distance and 258-byte maximum length.
- Quality-8 bucket eviction (discard the oldest half at 16 entries), insertion
  before lazy next-position comparison, and the exact match/literal decisions.
- Fixed Huffman packing, byte-boundary padding and the reference threshold for
  replacing an oversized compressed stream with 32,767-byte stored blocks.
- The `78 5e` zlib header, native 5,552-byte Adler reduction boundaries and
  exact big-endian PNG chunk lengths/CRCs.

`src/deflate.bend` is specifically the stb PNG compressor. Raylib's separate
`CompressData` uses sdefl and is not mapped to this implementation (see
[COMPRESSION.md](COMPRESSION.md)). The encoder and decoder have different size
profiles: a valid large image may encode beyond `decode_png`'s 1-MiB
encoded-input bound; that decoder limit is unchanged. Large allocations retain
the existing runtime failure boundary.

## BMP

`Surface.to_bmp`/`write_bmp` emit the native `ExportImage(..., ".bmp")` V4 layout
(see [BMP.md](BMP.md)). Checked formatted sources select a layout by format:

| Source | Native BMP layout | Pixel rule |
|---|---|---|
| 1: grayscale | 54-byte file/INFO header, 24-bit BGR | Replicate gray into three channels |
| 2: gray-alpha | Same 24-bit layout | Replicate gray; discard alpha without compositing |
| 4: RGB888 | Same 24-bit layout | Preserve RGB bytes |
| 3, 5, 6 | 122-byte file/V4 header, 32-bit BGRA | `LoadImageColors` expansion |
| 7: RGBA8888 | Same V4 layout | Preserve all channels, including hidden RGB and zero alpha |
| 8: R32 | Same V4 layout | Red-only normalization |

Rows are bottom-up. The 24-bit layout pads each row with 0..3 zero bytes to a
four-byte boundary; V4 needs no padding. V4 uses canonical RGBA masks and
`BI_BITFIELDS=3`. Both layouts keep the native zero `biSizeImage`, reserved,
resolution and color-count fields; V4 color-space/endpoint/gamma fields are
also zero. At the checked maximum (16,777,216 pixels) the output is at most
50,331,702 bytes (24-bit) or 67,108,986 bytes (V4), keeping size/index
arithmetic within U32. This is an arithmetic bound, not a measured maximum.

`Image.FloatRGB.to_bmp`/`write_bmp` encode the normalized opaque RGBA8 through
the same V4 writer.

## TGA

| Source format | Channels | Image type | Depth | Descriptor | Pixel bytes |
|---|---:|---:|---:|---:|---|
| 1 grayscale | 1 | 11 | 8 | 0 | Gray |
| 2 gray-alpha | 2 | 11 | 16 | 8 | Gray, alpha |
| 4 RGB888 | 3 | 10 | 24 | 0 | BGR |
| 3/5/6/7/8 | 4 | 10 | 32 | 8 | BGRA |

Surface and FloatRGB sources use the 32-bit BGRA row. The header is exactly 18
bytes with little-endian dimensions and the type, depth and descriptor above;
every other field is zero. Rows are bottom-up, pixels left-to-right; no
padding, ID, color map or footer is emitted. Alpha and transparent hidden RGB
are retained and participate in equality.

Default native RLE restarts at every row and caps packets at 128 pixels. An
equal initial pair selects repetition; an unequal pair selects raw scanning.
The pinned raw scan compares the incoming pixel with the pixel **two positions
earlier** and shortens its tentative length on equality: ABA emits raw(1) then
raw(2), while ABBC emits raw(4). A trailing singleton is raw. Conventional
adjacent-pixel run detection would change the bytes while decoding identically.

The shared encoder compares canonical words after expansion. This preserves
native component equality for gray/gray-alpha/RGB and deliberately coalesces
R32 words that export the same red byte, including signed zeros and distinct
subnormals. Its internal channel-aware entry requires the unused components to
be normalized; it is not a public arbitrary-RGBA channel-discard encoder. The
bound `18 + 5*width*height` is at most **83,886,098 bytes**, within U32.

## QOI

`Surface.to_qoi`/`write_qoi` always write header channels 4 and colorspace 0.
For formatted owners, pinned `rtextures.c` performs a second format check inside
the QOI branch: only the **original** RGB888/RGBA8888 formats reach `qoi_write`,
and its generic `LoadImageColors` preparation does not make other formats
eligible. Jonlib rejects them before conversion or file IO; this is native QOI
behavior, not a missing conversion.

| Original format | Result |
|---|---|
| 1, 2, 3, 5, 6, 8 | Reject and retain the owner (no gray replication, packed expansion, or either R32 PNG interpretation) |
| 4 RGB888 | Accept; header channels 3; exact R,G,B with internal alpha 255 |
| 7 RGBA8888 | Accept; header channels 4 even when every pixel is opaque; exact R,G,B,A including hidden RGB at alpha 0 |

Accepted conversion is integer-only through `Formats.packed_colors`: format 4
`0x00BBGGRR` becomes `0xRRGGBBFF`, format 7 `0xAABBGGRR` becomes `0xRRGGBBAA`.
It never uses normalized `Formats.decode`/`encode`, `Image.Formatted.convert`
or `to_surface`. Only `width*height` samples are traversed.

Encoded bytes: `qoif`, big-endian width/height, channels 3 or 4, colorspace
**0** (`QOI_SRGB`), top-down row-major pixels without padding, flips or state
resets, then the marker `00 00 00 00 00 00 00 01` and EOF. The encoder starts
with opaque black as the previous pixel and 64 transparent-black cache entries.
Equal pixels accumulate RUN (capped at 62, crossing rows, flushed before a
changed pixel or at EOF; runs do not populate the cache). Changed pixels try
INDEX, otherwise update the cache and select RGBA on alpha change, then DIFF,
LUMA or RGB in that order. DIFF accepts signed wrapped deltas -2..1; LUMA
accepts green -32..31 and red/blue-minus-green -8..7. The cache hash is
`(r*3 + g*5 + b*7 + a*11) & 63`; alpha and hidden RGB participate in equality
and hashing.

The native encoder narrows differences through `signed char`. Matching its
wrap-boundary bytes requires an eight-bit, two's-complement signed-char
narrowing profile; native controls do not qualify host profiles that were not
run.

The private `Qoi.encode.channels` entry accepts channels 3/4 and canonical RGBA
words, with every alpha exactly 255 for channel 3; it is not a public
alpha-discard encoder. `Qoi.encode` remains the channel-4 wrapper used by
Surface. A format-4 source and an equivalent opaque format-7 source differ
only at header byte 12.

Re-export is canonical, not a stream copy: a decoded channel-3 owner stores RGB
only, so RGBA opcodes in its input cannot resurrect alpha, and formatted owners
do not store the input colorspace (colorspace 1 re-exports as 0). The bounds
`22 + 4*width*height` (RGB) and `22 + 5*width*height` (RGBA) keep arithmetic
within U32 and native int; at 4096×4096 they are **67,108,886** and
**83,886,102** bytes.

FloatRGB has no QOI export.

## RAW

`Image.Formatted.write_raw` writes exactly the native-order image bytes without
a header; `Image.FloatRGB.write_raw` writes the format-9 sample words. Neither
stores dimensions or format. See [RAW-FILES.md](RAW-FILES.md) for the request,
error and closure contract and [FLOAT-RGB.md](FLOAT-RGB.md) for exact non-NaN
word export.

## Ownership and typed IO errors

| Operation | On rejection | On success / IO failure |
|---|---|---|
| `Surface.write_<codec>`, `Image.Formatted.write_png`/`write_bmp`/`write_tga`/`write_raw` | — | Consumes the owner; IO failure returns Base's exact `(code, message)` |
| `Surface.write_image` | `UnsupportedImageExport{surface}` before opening | Consumes; `ImageExportFileError{code, message}` |
| `Image.Formatted.to_png` / `to_qoi` | `(original_image, UnsupportedPixelFormat{})`, every byte retained | Consumes |
| `Image.Formatted.write_qoi` | `QoiSourceError{image}` before `File.open`, even for missing-parent or directory paths | Consumes; `QoiFileError{code, message}` |
| `Image.FloatRGB.to_*` | `Fail` with the original owner | Consumes |
| `Image.FloatRGB.write_*` | `FloatRGBSampleError{image}` before opening | Consumes; `FloatRGBFileError{code, message}` |

Rejections before opening leave existing files unchanged and absent targets
absent; rejected owners can be reused. Every successfully opened handle is
closed after its write attempt. Success replaces the file contents; a post-open
write failure may leave a truncated or partial file. No atomic or durable write
is promised, and Base's `File.close -> IO(Unit)` cannot report close errors.

Typed Base IO outcomes are a language-level adaptation. Native stb BMP/TGA
writers can ignore short-write and close results, and native QOI checks
write/flush failures but ignores `fclose`; failing-device, short-write and
close-error parity is not claimed.

## How it is verified

Every gate builds the pinned raylib and calls actual native `ExportImage` /
`ExportImageToMemory`, comparing complete encoded bytes and decoded pixels on
CPU-1, CPU-2 and JavaScript. File-writing lanes write real files (usually with
a `.dat` suffix to prove explicit codec selection) that must replace a
sentinel. IO checks run under `RLIMIT_NOFILE=64` (so leaked descriptors fail),
check exact ENOENT/EISDIR codes and messages against direct Base calls, and use
a separate `RLIMIT_FSIZE=0` run with `SIGXFSZ` ignored that must fail with
exactly EFBIG after open (EMFILE cannot substitute).

| Gate | Probe | Compares |
|---|---|---|
| `image-export` | `tools/image_export_probe.py` | `Surface.write_image` for all five codecs: suffix rules, complete files, decoded pixels, rejected-owner retention, unchanged sentinels, typed errors and handle closure |
| `png-export` | `tools/png_export_probe.py` | Surface and formatted PNG memory/file bytes (byte formats via memory and file; packed via file), complete decode round trips |
| `deflate` | `tools/deflate_probe.py` | The private quality-8 compressor against linked stb (eviction, lazy matching, window edges, Adler boundaries, stored blocks) |
| `r32-image` | `tools/r32_image_probe.py` | R32 memory PNG raw-word bytes and file PNG red-only output |
| `formatted-bmp-export` | `tools/formatted_bmp_export_probe.py` | All eight formats: 24-bit/V4 bytes, padding widths 1..4, packed/R32 boundaries, 4096-pixel axes |
| `formatted-tga-export` | `tools/formatted_tga_export_probe.py` | All eight formats: run/raw lengths around 128, ABA/ABBC sequences, packed/R32 expansion and collapse |
| `formatted-qoi-export` | `tools/formatted_qoi_export_probe.py` | Accepted formats 4/7 (every opcode family, run caps, DIFF/LUMA thresholds, all 64 INDEX slots), rejected formats 1/2/3/5/6/8 with retained owners |
| `float-rgb-png` | `tools/float_rgb_png_probe.py` | FloatRGB memory raw-prefix and normalized file PNG |
| `float-rgb-raster-export` | `tools/float_rgb_raster_export_probe.py` | FloatRGB BMP/TGA file bytes, including the TGA 128-pixel run boundary |

The three formatted gates share `tools/formatted_export.py`, which runs native
qualification controls (endianness, rounding, packed/R32 `LoadImageColors`
colors), builds native sources from correctly typed storage (a full byte
comparison rejects any word normalization before export), parses every output
with an independent strict Python decoder, and runs the typed IO checks for 100
iterations per lane. The QOI parser validates headers, operands, run bounds,
pixel count, marker and EOF without reimplementing encoder selection.

`png-export`, `deflate`, `float-rgb-png` and `float-rgb-raster-export` accept
`--gpu`; the forced-GPU lane covers pure encoding only, never filesystem IO.
The formatted gates and `image-export` have no GPU lane.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only formatted-qoi-export
```

## Known gaps

- JPEG/KTX and other native export codecs.
- Filename dispatch for owners other than Surface (no
  `Image.Formatted.write_image`); FloatRGB QOI.
- `ExportImageToMemory` beyond PNG; packed formats 3/5/6 in memory PNG.
- Nondefault PNG compression/filter/flip settings, other TGA/BMP options and
  other float/half/compressed source formats or mipmaps.
- Exact NaN payload interoperability in float exports.
- Native callbacks, pointer/output-size/allocation ABI, allocation-failure and
  logging behavior.
- Failing-device, short-write and close-error parity; GPU file IO.
- Maximum-area allocation and complete integration/resource/performance parity.

## Provenance

The PNG filter/compressor (`src/png_encode.bend`, `src/deflate.bend`) and the
BMP and TGA writers (`src/bmp.bend`, `src/tga.bend`) are altered Bend
adaptations of pinned raylib's `src/external/stb_image_write.h`, retaining the complete
[stb MIT notice](../LICENSES/stb-image.txt). The QOI encoder is an altered Bend
adaptation of Dominic Szablewski's codec in pinned raylib `src/external/qoi.h`
([QOI MIT](../LICENSES/qoi.txt)); export routing adapts raylib `src/rtextures.c`
([raylib zlib](../LICENSES/raylib.txt)). Altered-source descriptions are in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). No native codec is linked
into the candidate.
