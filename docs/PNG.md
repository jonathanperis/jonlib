# PNG decoding

`Surface.decode_png(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with owned normalized RGBA8 pixels.
The dedicated `Image.Formatted.decode_png` memory factory preserves the native
8-bit output format and bytes instead; its contract and local qualification
are [specified below](#format-preserving-png-memory-loading). The dedicated
`Image.Formatted.load_png(path)` file adapter preserves the same native formats
through the shared bounded, exact-read, close-before-decode IO boundary; its
[separate file contract](IMAGE-FILES.md#format-preserving-png-file-loading)
does not enlarge this memory domain.

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

Nondefault external stb decoder flags and broader malformed-input recovery
remain gaps. Shared normalized memory/file dispatch is documented
in [IMAGE-FILES.md](IMAGE-FILES.md). Exact default byte-format export is
documented in [PNG-EXPORT.md](PNG-EXPORT.md).

## Format-preserving PNG memory loading

`Image.Formatted.decode_png(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Image.Formatted>`. It accepts the same checked
PNG domain as `Surface.decode_png`: the color/depth combinations, Adam7 passes,
filter arithmetic, CgBI defaults, chunk ordering, palette/key behavior and
inclusive limits above are unchanged. It takes no format, channel or reference
argument. Success creates one affine owner with the decoded width/height and
an implicit single mip level; failure returns only the existing typed error.
The immutable encoded list can be reused for independent decodes.

Native output channels follow image structure rather than observed opacity:

| PNG structure | Format | Row-major exported components |
|---|---|---|
| Grayscale (color 0), no tRNS | **1 (grayscale)** | G |
| Grayscale with tRNS, or gray-alpha (color 4) | **2 (gray-alpha)** | G,A |
| RGB (color 2) or palette (color 3), no tRNS | **4 (RGB888)** | R,G,B |
| RGB/palette with tRNS, or RGBA (color 6) | **7 (RGBA8888)** | R,G,B,A |

A valid tRNS key promotes grayscale/RGB even when no pixel matches. Palette
tRNS promotes to RGBA even when its payload is empty, all supplied alphas are
255, or only unused entries have nonopaque alpha. That promotion remains set
across a later accepted PLTE, although PLTE replaces palette colors and resets
their alpha bytes to 255. Repeated accepted tRNS chunks retain promotion. There
is no opacity scan or inference from normalized pixels to choose the format.
Existing-alpha color types retain their channels even if every alpha is 255;
tRNS on those types remains invalid under the checked parser.

Packed grayscale expands to 8-bit G values; indexed PNG exports palette colors,
not indices. All 16-bit input is reduced to the high byte of each reconstructed
sample after full-width tRNS comparison. This preserves the native 8-bit
`LoadImageFromMemory` result, not source bit depth. CgBI uses raw DEFLATE with
the pinned default conversion flags unchanged: no added BGR swap or
unpremultiplication, including hidden color at zero alpha.

`Image.Formatted.export` consumes the owner and returns
`((width, height), (format, bytes))`, with exactly
`width*height*channels` component bytes and no storage padding. Logical packed
words use G, G/A, R/G/B or R/G/B/A in successive low bytes; unused upper bytes
are zero. Integer packing avoids an F32 conversion or a grayscale luminance
round trip. The consuming `Image.Formatted.to_surface` bridge produces the
same normalized RGBA8 values as the existing Surface decoder.

### Unchanged limits and error ordering

Dimensions remain 1..4096 on each axis. The complete encoded list, including
bytes after IEND, has the same **inclusive 1,048,576-byte cap**; the filtered
scanline/pass stream has the same **inclusive 67,108,864-byte cap**. These are
admission bounds, not a maximum-area allocation or runtime-memory guarantee.

The input walk runs before signature/chunk parsing and stops at its first
error. An out-of-range value gives `InvalidImageByte`; a valid byte at the first
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
IEND remains ignored after whole-input validation. Existing checked rules can
be stricter than native malformed-stream recovery; this factory changes none
of those admissions or error precedences.

### Local qualification

The [focused evidence](evidence/png-formatted-memory.json) records a fresh local
Linux x86-64 pass on CPU-one-thread, CPU-two-thread and JavaScript. The dedicated
gate covers **230 accepted images / 85,979 pixels and 208 typed controls**,
retaining all **193 historical accepted streams / 31,677 pixels and 39 typed
controls** unchanged. Structural cases distinguish absent, empty, opaque,
unused-entry and nonmatching tRNS, including later-PLTE resets. All four output
layouts include single, padded, 4096-axis, moderate and byte-ramp images. The
encoded-cap endpoint and byte/size precedence are checked without expanding
the existing domain.

Actual native dimensions, format, `image.mipmaps == 1` and every raw byte are
captured before separate normalization. There are **485 native observations**,
with **206,667 raw bytes and 343,916 normalized bytes** before the selected
uppercase alias observations. Candidate mipmaps remain an implicit type
contract, not a stored or independently measured field. Each lane passes
**1,896 complete observations / 1,532,452 compared bytes** in 60 ordered
partitions. Raw exports, checked factories, export/import round trips,
retained point-read owners, logical high-bit checks, consuming Surface bridges
and existing normalized/dispatch paths are observed separately. Malformed
controls run only in checked Jonlib.

```sh
python3 tools/png_format_probe.py --reference-env clean-loader \
  --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 -m unittest discover -s tests -p test_png_format_harness.py -v
```

The fresh PNG-enabled Memory oracle verifies source/tool/compiler/archive
identities, actual build configuration, clean-loader child receipts and tiny
structural-channel/full-width-key/CgBI qualification vectors. Its 16 native
partitions and 60 candidate partitions are ordered and exhaustive. Independent
complete-output replay verifies **279 command receipts and 1,599 artifact
seals** and rejects **21 adversarial mutations**, without executing the
compiler, native reference or candidate again. The focused gate takes
**1,310.912 seconds** on this host; this is a verification duration, not an
application benchmark.

The completed 2026-10-04 [serial verification record](VERIFICATION.md#format-preserving-png-memory-loading-2026-10-04)
records 27 ordered stages, 866 Python tests without skips and 177 scoped laws.
Its independent regression audit verifies 467 frozen sources and 9,015 evidence
hashes. It distinguishes complete retained-record replay from nine older
report/source/artifact-only harnesses and unrecorded QOI closure iterations.
A separate integrated metadata/CI source snapshot passes 871 Python tests
without skips, all 177 laws, syntax/project/API checks, CI preservation and
whitespace checks. Final-tree review is recorded separately from runtime
evidence. New PNG 84-gate/eight-worker hosted qualification remains pending.

Only partial `raylib:function:LoadImageFromMemory` scope expands in this memory
increment; API completion counts do not change. Its evidence does not qualify
the separately added [formatted PNG file loader](IMAGE-FILES.md#format-preserving-png-file-loading),
generic formatted dispatch, another codec, a new input domain or nondefault stb flag.
Historical Surface CPU/JavaScript/Metal results do not qualify the new formatted
path. Native pointer/allocation ABI, allocation-failure parity, maximum-area
success and representative performance remain unqualified, as do new hosted,
GPU/Metal, macOS/Windows/browser and big-endian results for this path.

### Native source contract

The pinned `rtextures.c` lines 461–471 use `stbi_load_from_memory` with requested
channels zero, set one mip and map returned components to formats 1/2/4/7.
`stb_image.h` lines 5119–5234 and 5284–5286 retain tRNS-derived components,
including palette promotion independently of alpha values or later PLTE.
Lines 1190–1203 and 1260–1273 apply the final high-byte reduction to 16-bit
results; lines 4993–4994 and 5222–5223 retain disabled CgBI conversion defaults.
These source-derived rules define the contract; the separately linked runtime
evidence establishes only the exercised local profile.

## Separate formatted PNG file qualification

`Image.Formatted.load_png(path)` adds exactly a wrapper and result continuation
around the shared `RasterFile` reader and unchanged formatted decoder. Its
[separate file evidence](evidence/png-formatted-files.json) passes on local Linux
x86-64 CPU-one-thread, CPU-two-thread and server-side JavaScript: **370 files /
86,119 pixels**, **143 file plus 76 continuation controls**, and **2,846 primary
observations / 1,531,636 bytes per lane**. All 230 memory streams, 208 controls and
the nested 193-stream/39-control legacy corpus remain exact. The shared inclusive
1 MiB file cap, complete reads and close-before-decode calls neither enlarge nor
replace the unchanged encoded/filtered memory limits.

Actual native file routes measure format, mipmaps and raw bytes before separate
normalization. Candidate mipmaps remain an implicit type contract. Native-byte
factory reconstruction is gated by a separate public reopen; reopened loader
exports supply the distinct raw-roundtrip observations. Complete independent
replay covers every primary, closure, sparse and exact-cap frame; malformed and
foreign-codec controls remain checked-only. See the full
[file contract and resource limits](IMAGE-FILES.md#format-preserving-png-file-loading)
and [28-stage runtime matrix](VERIFICATION.md#format-preserving-png-file-loading-2026-10-04).

The historical memory evidence above is unchanged. Its earlier eight-worker
hosted run timed out on macOS; the CI-only repaired 84-gate/ten-worker predecessor
at `9cb5a7e7` passes [Conformance](https://github.com/jonathanperis/jonlib/actions/runs/37179587107).
This later predecessor result does not qualify PNG-file IO. Final metadata/CI-tree
checks remain separately recorded, and **85-gate/twelve-worker exact-tip PNG-file
hosted qualification remains pending**. Only partial `LoadImage` scope expands;
`LoadImageFromMemory`, API completion counts, pins and laws remain unchanged.

## Historical Surface verification

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
