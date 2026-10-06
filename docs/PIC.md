# Softimage PIC decoding

| API | Contract |
|---|---|
| `Surface.decode_pic(bytes: +List<U32>)` | Returns `Result<&1, &1, Surface.Error, Surface>` preserving native RGB888 (4) or RGBA8888 (7); see [format-preserving memory loading](#format-preserving-pic-memory-loading). |
| `Surface.load_pic(path: String)` | Returns `IO(Result<&1, &1, Surface.IOError, Surface>)` through the inclusive 1 MiB raster-file boundary, selecting PIC independently of the suffix. |

Shared memory/file dispatch recognizes the native `53 80 f6 34` signature and
`PICT` marker at byte 88; see [IMAGE-FILES.md](IMAGE-FILES.md).

## Supported profile

- Dimensions 1..4096, with the complete 104-byte header present.
- One to ten chained descriptors; any nonzero chain byte continues the list.
- Eight-bit samples and raw/pure-RLE/mixed-RLE packet types 0/1/2.
- Packets run in declaration order within each top-down row. Selected channel
  bytes are read in R/G/B/A order using mask bits `80/40/20/10`; low mask bits
  are ignored.
- Every output component starts at 255. Later packets overwrite earlier values
  for the same channel, including zero alpha.
- Reserved, ratio, field and padding header values are ignored. At least one byte
  must follow the final descriptor, matching the native parser even for an empty
  channel mask. Valid trailing bytes are ignored.

Byte values are checked globally. Invalid/incomplete headers, descriptors,
unsupported packet formats and more than ten packets return `InvalidImageHeader`.
Dimensions outside the profile return `UnsupportedImageSize`; insufficient raw
sample data returns `TruncatedImageData`; non-byte elements return
`InvalidImageByte`. Header/count validation and raw sample totals precede output
allocation. Compressed packets are checked before writing their output.

## Native RLE rules

Pure RLE reads an unsigned count byte and one selected-channel sample. Counts
larger than the remaining row are **clipped**. A zero count still consumes its
sample but writes no pixels.

Mixed RLE uses three forms:

- Controls 0..127 copy `control + 1` samples.
- Controls 129..255 repeat one sample `control - 127` times.
- Control 128 reads a big-endian U16 repeat count, including zero.

Mixed counts beyond the row return `InvalidImageStream`. Both modes require data
following the control byte, matching native behavior even for empty masks;
missing count/sample data returns `TruncatedImageData`. Structural input-byte fuel
bounds zero-count runs. Raw and compressed packets can share a row and retain
their ordered channel overwrites. PSD arithmetic profiles do not affect PIC's
integer channel operations.

## Format-preserving PIC memory loading

`Surface.decode_pic(bytes: +List<U32>)` returns
`Result<&1, &1, Surface.Error, Surface>` across the complete checked
PIC domain above.

The result preserves width/height, an implicit single mip and every native
row-major byte in RGB888 (format 4) or RGBA8888 (format 7). Output channels come
from the bitwise union of **all validated packet channel masks**: any `0x10`
alpha bit selects four components; otherwise the result has three. Thus an
alpha-only first/middle packet still selects RGBA after later RGB packets, and
alpha-present images remain RGBA even if every output alpha is 255. Missing
color channels keep the white defaults; low mask bits do not select output
components. The selected-input-sample size accumulator is not an output channel
count.

The shared decoder carries this metadata in its private owned result.
`Surface.decode_pic` reuses the affine pixel array, packs bytes with integer
operations, clears RGB's unused high byte and exports only logical pixels. There
is no second parser, floating conversion, `ImageFormat` normalization or opacity
inference. Dimensions 1..4096, packet ordering, RLE rules, global byte
validation, typed errors and their precedence are unchanged. PIC memory has no
encoded-input cap. Mipmaps are implicit in the candidate type; the native
reference must separately report exactly one.

The [file loader](IMAGE-FILES.md) adds the inclusive 1 MiB bounded-IO
restriction, exact-length read and close-before-decode ordering without changing
this uncapped memory domain.

## How it is verified

Expected results come from the pinned native raylib, compared exactly on the
CPU-1, CPU-2 and JavaScript lanes.

- **Surface decoding** (`tools/pic_probe.py`, gate `pic`): normalized pixels and
  error controls covering every high-bit channel mask, ignored low bits, white
  defaults, overlapping channel packets, zero alpha, ten-packet chains, multiple
  rows and a 4096-pixel row; RLE cases add clipped/zero runs, mixed
  raw/repeated/extended counts, mode mixtures, 128/255 boundaries, 4096-pixel
  extended runs, malformed counts and bounded no-progress streams. `--gpu` adds
  a forced-GPU lane (local only).
- **Format-preserving memory loading** (`tools/pic_format_probe.py` on
  `tools/formatted_codec.py`, gate `pic-format`): the native PIC feature is
  disabled by default, so the probe builds raylib with
  `SUPPORT_FILEFORMAT_PIC=ON`. Native dimensions, format, mipmaps and raw bytes
  are observed before a separate normalized RGBA reference, then compared through
  the raw, factory, owner, round-trip, bridge, Surface and dispatch roles. Only
  complete, independently admitted streams reach the unmodified native oracle:
  its failed-PIC path can free/null the intermediate output and still enter
  4-to-3 conversion, so every malformed control is checked-only and no native
  malformed-recovery claim is made. Admission walks every descriptor, row,
  control, count and selected-sample byte without producing expected pixels; a
  `.pic` suffix alone proves no PIC identity because stb sniffs content.
- **Format-preserving file loading** (`tools/pic_file_probe.py` on
  `tools/formatted_file.py`, gate `pic-file`): memory fixtures as files with path
  variants, file controls and the shared closure, sparse/oversized and exact-cap
  resource runs.
- Shared dispatch across supported extension families and both `.pic` suffix
  cases is covered by `image-memory` and `image-file`.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only pic-format
```

## Known gaps

- Generic formatted dispatch and native malformed recovery.
- Maximum-area allocation, OOM/native pointer ABI and representative performance.
- GPU for the formatted paths, Windows/browser and big-endian targets.
- Ledger scope: formatted memory loading is partial
  `raylib:function:LoadImageFromMemory` scope and formatted file loading partial
  `raylib:function:LoadImage` scope; no API is completed.

## Provenance

The altered stb reader retains the MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt), with upstream PIC attribution
to Tom Seddon.
