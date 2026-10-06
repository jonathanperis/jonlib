# BMP memory/file decoding and checked image export

| API | Contract |
|---|---|
| `Surface.decode_bmp(bytes: +List<U32>)` | Returns `Result<&1, &1, Image.DecodeError, Surface>` with normalized RGBA8 pixels. |
| `Image.Formatted.decode_bmp(bytes: +List<U32>)` | Returns `Result<&1, &1, Image.DecodeError, Image.Formatted>` preserving native RGB888 (4) or RGBA8888 (7), implicit one mip and exact row-major bytes. |
| `Image.Formatted.load_bmp(path: String)` | Returns `IO(Result<&1, &1, Image.LoadError, Image.Formatted>)` through the inclusive 1 MiB raster-file boundary, selecting BMP independently of the suffix and preserving the checked native format 4/7 memory result. |
| `Surface.to_bmp(surface) -> +List<U32>` | Consumes RGBA8 ownership and emits exact native V4/32-bit BMP bytes. |
| `Surface.write_bmp(surface, path)` | Consumes ownership and returns `IO(Result<&1, &1, U32 & String, Unit>)` through the established Base byte-write/close path. |

## Supported decoding profile

- A 12-byte CORE header supports 24-bit RGB and bounded 1/4/8-bit indexed data.
  Its complete file/DIB header is 26 bytes; width and height are unsigned 16-bit
  fields, bounded to 1..4096. Rows are bottom-up and output alpha is opaque.
- Native CORE palette count is `floor((pixel_offset - 38)/3)`, despite the
  26-byte header. It reads that many BGR triples, then skips **12 plus the
  division remainder** bytes. This profile requires 1..256 loaded entries and
  indices below that count. Offsets 41..808 cover the accepted count/remainder
  range. This preserves the pinned reader's rule rather than standard CORE
  palette sizing.
- Width and absolute height are 1..4096; positive height is bottom-up and negative
  height is top-down. Output is always top-down row-major; Surface normalizes to RGBA8.
- A 40-byte INFO header supports uncompressed (`BI_RGB`) 1/4/8-bit indexed and
  16/24/32-bit true-color pixels, plus 16/32-bit `BI_BITFIELDS`. INFO bitfields
  read three RGB masks immediately after the DIB; those 12 bytes count toward the
  effective header end. INFO rejects three identical RGB masks, matching native.
- A 56-byte header uses the INFO profiles but discards its four embedded mask
  words. Bitfield images then read three RGB masks **after** the DIB. Embedded
  alpha is ignored, including for uncompressed 16-bit input.
- A 108-byte V4 header supports the same `BI_RGB` depths and 16/32-bit
  `BI_BITFIELDS`, with four RGBA masks inside the header. Uncompressed V4 replaces
  its stored RGB masks with native defaults; 16-bit input retains its alpha mask.
- A 124-byte V5 header follows V4's masks/alpha rules and consumes four additional
  intent/profile words. Their values are ignored; profile offsets are not followed.
- Explicit RGB masks must be nonzero with 1..8 set bits. Alpha may be absent
  (opaque) or contain 1..8 set bits. Reordered, overlapping and noncontiguous
  masks follow native highest-bit/population alignment and bit replication. Holes
  are not compacted: masks `5`, `0a`, `50` decode word `005f` as `aaaaaaff`.
- Row padding is retained in the input stride and excluded from output pixels.
- Larger-header indexed palettes contain 1..256 BGR/reserved entries. Native
  palette count is `floor((pixel_offset - 14 - DIB_size)/4)`; `clrUsed` and
  palette alpha/reserved bytes are ignored. Output is opaque. Remaining offset
  bytes (0..3) are skipped once after the table. Packed indices are MSB-first;
  unused final-byte bits are discarded, and each input row is padded to a
  multiple of four bytes.
- `BI_RGB` 32-bit images whose alpha bytes are **all zero** become opaque,
  matching stb's reference behavior. If any alpha byte is nonzero, all input
  alpha bytes are preserved. Bitfields and V4/V5 `BI_RGB` 16-bit preserve
  all-zero explicit alpha.
- `BI_RGB` 16-bit samples use two little-endian bytes with RGB fields at shifts
  10, 5 and 0. Each five-bit value expands with `(value*33)>>2`; RGB ignores
  bit 15. INFO/56-byte output is opaque; V4/V5 use their alpha mask, or opaque
  alpha when absent. Native BMP bit replication differs from TGA's
  `value*255/31` integer scaling: channel value 4 becomes 33 in BMP and 32 in TGA.
- For true-color input, the pixel offset may lie 0..1024 bytes past the header
  end. The pinned reader skips this gap **twice** for true-color images, so the
  effective payload starts at `effective_header_end + 2*gap`, including
  INFO/56-byte extra mask words when present. Jonlib preserves this behavior.

## Errors

All supplied byte values must be 0..255. Unsupported header layouts, bit depths,
planes, masks, compression or offsets return `InvalidImageHeader`. Unsupported
dimensions return `UnsupportedImageSize`; incomplete effective pixel data,
including row padding, returns `TruncatedImageData`. Invalid bytes return
`InvalidImageByte`. Header/payload validation precedes output allocation. An
index beyond the loaded palette returns `InvalidImageStream`; the native reader's
uninitialized palette reads are outside the supported profile. File-size/reserved
header fields do not override actual input availability.

Shared memory/file dispatch uses this profile through `Surface.decode_image` and
`Surface.load_image`; see [IMAGE-FILES.md](IMAGE-FILES.md).

## Format-preserving BMP memory loading

The dedicated `Image.Formatted.decode_bmp` factory uses the entire checked
decoding profile above without broadening accepted headers, masks, dimensions or
errors. The effective native alpha-mask layout selects the output component count
before decoding and alpha repair. This metadata passes through the owned decoder
result; integer packing emits three-byte RGB888 (format 4) or four-byte RGBA8888
(format 7), excluding backing-array padding. The owner has one implicit mip level.
Neither source bit depth, observed opacity nor an `ImageFormat` floating
conversion determines storage.

- CORE, indexed palettes, RGB555 and RGB24 normally produce RGB888. Reserved
  palette bytes do not create an alpha channel.
- INFO/56-byte `BI_BITFIELDS` produces RGB888 even for 32-bit source words,
  because the effective mask list has no alpha field. The four discarded 56-byte
  embedded masks have no metadata effect.
- `BI_RGB` 32-bit produces RGBA8888 even when all-zero source alpha is repaired
  to opaque. If any alpha sample is nonzero, the original alpha bytes survive.
- V4/V5 nonzero effective alpha masks produce RGBA8888, including 16-bit input
  with alpha masks above its input word and consequently zero decoded alpha.
  Explicit bitfield alpha never receives the `BI_RGB` 32-bit repair. Absent
  effective alpha produces RGB888.
- Ignored `BI_RGB` masks remain ignored: default 32-bit alpha is present, default
  24-bit alpha is absent, and V4/V5 16-bit retains its alpha mask.

The pinned stb 24-bit/`0xff000000` alpha special case is unreachable under this
checked domain: 24-bit bitfields are rejected and accepted 24-bit `BI_RGB`
default selection removes alpha. No new acceptance is inferred from that branch.

Byte validation retains first precedence across the whole supplied list,
including ignored fields, palette bytes, gaps, row padding and trailing data.
Header, size, truncation and invalid-index precedence is unchanged. This memory
API has no encoded-input length cap; the file layer's separate 1 MiB raster cap
is not imported. Probe fixture budgets are oracle safety limits, not API limits.

`Image.Formatted.export` consumes the result and exposes dimensions, format and
all logical native-order bytes; `get` retains the exact owner for valid and
invalid coordinates. The `from_bytes` round trip and consuming `to_surface`
bridge apply. `Surface.decode_bmp`, generic normalized memory/file dispatch and
the exporters retain their contracts; no generic formatted dispatcher is added.

## Format-preserving BMP file loading

`Image.Formatted.load_bmp(path: String)` returns
`IO(Result<&1, &1, Image.LoadError, Image.Formatted>)`. It explicitly selects BMP
for ordinary, non-changing files, independently of the path suffix. Lowercase,
uppercase, mixed-case, suffixless and misleading names all use the same checked
BMP decoder; there is no content-based fallback to another codec.

The two-function wrapper passes
`Image.file.bytes(path, Image.file.limit(RasterFile{}))` to a dedicated
continuation. It preserves file/load errors and adapts the unchanged
`Image.Formatted.decode_bmp` result through `Image.file.decoded`. The shared
**1,048,576-byte inclusive** cap governs encoded input only. Open/size/read
errors retain Base's code and message. Successfully reported sizes above the cap
through U32_MAX are rejected before reading; larger sizes retain Base's overflow
file error. One bounded read must return exactly the reported length. Close
calls precede processing read results and decoding, including size/read failures
and size rejection. Base ignores close errors, so this is call ordering rather
than a guarantee of successful OS closure. The full ordered error contract is in
[IMAGE-FILES.md](IMAGE-FILES.md).

Success preserves native RGB888 **4** or RGBA8888 **7**, width and height
**1..4096**, one implicit mip and every top-down row-major output byte. Effective
alpha-mask metadata, integer channel expansion and alpha repair are unchanged.
Byte validation precedes base-field checks, then dimensions, extended headers/
effective masks, palette/raster completeness and indices. Unsupported dimensions
therefore take precedence over incomplete or invalid effective masks. CORE
palette bias/remainders, INFO/56-byte external masks, V4/V5 defaults,
noncontiguous mask replication, doubled true-color gaps, padding and ignored
valid tails are unchanged. The native 24-bit/`0xff000000` alpha special case
remains unreachable; no new accepted BMP domain is inferred from it.

## Export

RGBA8 export follows the actual native `ExportImage(..., ".bmp")` path: a
122-byte file/V4 header, canonical masks, bottom-up BGRA rows and no row padding
for 32-bit pixels. The explicit BMP writer selects the format independently of
the path extension. Checked `Image.Formatted` formats 1..8 additionally export
native 24-bit or V4 bytes with source-specific channel rules; see
[IMAGE-EXPORT.md](IMAGE-EXPORT.md).

## How it is verified

Expected results come from the pinned native raylib, compared exactly on the
CPU-1, CPU-2 and JavaScript lanes.

- **Surface decoding and export** (`tools/bmp_probe.py`, gate `bmp`): normalized
  pixels, typed-error controls and complete export bytes; CPU/JavaScript also
  write a real BMP file and compare it with the native export. Indexed cases cover
  INFO/V4, all three depths, both orientations, partial-byte rows, padding, offset
  residuals, ignored `clrUsed`/alpha, reduced/full palettes and a 4096-pixel row.
  RGB555 cases cover each five-bit channel range, both high-bit states, INFO/V4,
  orientation, odd row padding and a double-skipped offset gap. Bitfield cases
  cover every mask population 1..8, RGB565/ARGB1555/RGBA4444,
  reordered/overlapping/noncontiguous masks, high bits, INFO's mask extension and
  native V4 16-bit alpha. Missing/oversized RGB or alpha masks, INFO's equal-mask
  rejection and incomplete mask headers are checked. 56-byte/V5 cases cover
  indexed, byte-color, RGB555 and bitfield data, contradictory embedded masks,
  ignored profile words and truncated/invalid effective headers. CORE cases cover
  short complete headers, all row-padding widths, a 4096-pixel row, the maximum
  post-header gap, rejected planes/depths/dimensions/offsets, 1..256 palette
  entries, all native skip remainders and rejected undefined index domains.
  `--gpu` adds a forced-GPU lane (local only).
- **Format-preserving memory loading** (`tools/bmp_format_probe.py` on
  `tools/formatted_codec.py`, gate `bmp-format`): accepted fixtures are admitted
  by an independent header parse before any native call; native format, mipmaps
  and raw bytes are recorded before separate normalization and compared through
  the raw, factory, owner, round-trip, bridge, Surface and dispatch roles
  (including uppercase aliases). Metadata/alpha/channel ramps, both orientations,
  odd rows, 4096-by-1, 1-by-4096 and moderate shapes supplement the inherited
  Surface corpus. A qualification program checks tiny RGB/RGBA/mask routing
  discriminators before the broad oracle. Checked-invalid controls only exercise
  Jonlib's typed errors.
- **Format-preserving file loading** (`tools/bmp_file_probe.py` on
  `tools/formatted_file.py`, gate `bmp-file`): accepted memory fixtures as files
  plus filename variants; native `LoadImage` for recognized suffixes and
  `LoadFileData` plus `LoadImageFromMemory(".bmp")` for explicit selection; file
  controls and the shared closure, sparse/oversized and exact-cap resource runs.
- Formatted BMP export is gated by `formatted-bmp-export`
  ([IMAGE-EXPORT.md](IMAGE-EXPORT.md)); shared dispatch by `image-memory` and
  `image-file`.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only bmp-format
```

## Known gaps

- The native decoder's permissive recovery of truncated input.
- Wider export source formats and native callbacks/allocation ABI.
- GPU for formatted memory/file paths and file IO, Windows/browser and big-endian
  targets, concurrent/special files.
- Native pointer/allocation/OOM behavior, maximum decoded area/heap and full
  performance.
- Ledger scope: formatted memory loading is partial
  `raylib:function:LoadImageFromMemory` scope and formatted file loading partial
  `raylib:function:LoadImage` scope.

## Provenance

The codec is an altered Bend implementation of the pinned stb BMP paths; its MIT
notice is retained in [LICENSES/stb-image.txt](../LICENSES/stb-image.txt).
