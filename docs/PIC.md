# Softimage PIC decoding

`Surface.decode_pic(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with owned RGBA8 output. Shared
memory/file dispatch recognizes the native `53 80 f6 34` signature and `PICT`
marker at byte 88; see [IMAGE-FILES.md](IMAGE-FILES.md).

## Current profile

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
sample data returns `TruncatedImageData`; non-byte elements return `InvalidImageByte`.
Header/count validation and raw sample totals precede output allocation.
Compressed packets are checked before writing their output.

## Native RLE rules

Pure RLE reads an unsigned count byte and one selected-channel sample. Counts
larger than the remaining row are **clipped**. A zero count still consumes its
sample but writes no pixels.

Mixed RLE uses three forms:

- Controls 0..127 copy `control + 1` samples.
- Controls 129..255 repeat one sample `control - 127` times.
- Control 128 reads a big-endian U16 repeat count, including zero.

Mixed counts beyond the row return `InvalidImageStream`. Both modes require
data following the control byte, matching native behavior even for empty masks;
missing count/sample data returns `TruncatedImageData`. Structural input-byte fuel
bounds zero-count runs. Raw and compressed packets can share a row and retain
their ordered channel overwrites.

Format-preserving file/generic dispatch, native malformed recovery and full
resource/platform/performance coverage remain gaps. PSD arithmetic profiles do
not affect PIC's integer channel operations.

## Verification

```sh
python3 tools/pic_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The probe compares 33 native images / 8,867 pixels and 24 error controls on
CPU, JavaScript and forced Metal. Cases cover every high-bit channel mask,
ignored low bits, white defaults, overlapping channel packets, zero alpha,
ten-packet chains, multiple rows and a 4096-pixel row. RLE cases add clipped/zero
runs, mixed raw/repeated/extended counts, mode mixtures, 128/255 boundaries,
4096-pixel extended runs, malformed counts and bounded no-progress streams.
Shared dispatch compares
actual PIC data across supported extension families and both `.pic` suffix cases.
Hashes and outcomes are in [evidence/pic-rle.json](evidence/pic-rle.json).

The altered stb reader retains the MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt), with upstream PIC attribution
to Tom Seddon.

## Format-preserving PIC memory loading

`Image.Formatted.decode_pic(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Image.Formatted>` across the complete checked
PIC domain above. This expands only partial `raylib:function:LoadImageFromMemory`;
no API is completed.

The result preserves width/height, an implicit single mip and every native
row-major byte in RGB888 (format 4) or RGBA8888 (format 7). Output channels come
from the bitwise union of **all validated packet channel masks**: any `0x10`
alpha bit selects four components; otherwise the result has three. Thus an
alpha-only first/middle packet still selects RGBA after later RGB packets,
and alpha-present images remain RGBA even if every output alpha is 255.
Missing color channels keep the existing white defaults; low mask bits do not
select output components. The selected-input-sample size accumulator is not an
output channel count.

The shared decoder carries this metadata in its private owned result.
`Surface.decode_pic` discards it and retains the same canonical RGBA8 pixels.
The formatted adapter reuses the affine pixel array, swaps bytes with integer
operations, clears RGB's unused high byte and exports only logical pixels.
There is no second parser, floating conversion, `ImageFormat` normalization or
opacity inference. Dimensions 1..4096, packet ordering, RLE rules, global byte
validation, typed errors and their precedence are unchanged. PIC memory has no
new encoded-input cap. Mipmaps are implicit in the candidate type; the native
reference must separately report exactly one.

### Qualification and remaining gaps

The focused gate is:

```sh
python3 tools/pic_format_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --reference-env clean-loader
python3 tools/pic_format_audit.py .build/pic-format-probe/results.json
```

It requires three complete lanes: CPU-one-thread, CPU-two-thread and JavaScript.
The native PIC feature is disabled by default, so the gate configures a fresh
isolated Memory archive with explicit PIC support and checks both CMake cache
and effective compiler flags. Actual native dimensions, format, mipmaps,
`GetPixelDataSize` and full raw bytes are observed before a separate normalized
RGBA reference. Historical normalized Surface results do not qualify this
formatted adapter.

Only complete independently admitted streams may reach the unmodified native
oracle. Its pinned failed-PIC path can free/null the intermediate output and
still enter 4-to-3 conversion. Every malformed control is therefore checked-only;
no native malformed-recovery claim is made. Admission walks all actual descriptor,
row, control, count and selected-sample bytes without producing expected pixels.
Its finite fixture/source/partition budgets are harness resource limits, not
restrictions added to the public API.

Format-preserving PIC file loading, shared formatted dispatch, maximum-area
allocation, OOM/native pointer ABI, representative performance, GPU/Metal,
big-endian and other platform/hosted qualification remain separate gaps.
PSD arithmetic profiles and shared DEFLATE/arithmetic code are unchanged.

The [fresh local evidence](evidence/pic-formatted-memory.json) passes **101 streams /
37,306 pixels and 343 checked-only controls** on all three lanes, preserving the
33-stream / 8,867-pixel and 24-control legacy corpus exactly. Each lane compares
**1,536 complete observations / 836,048 bytes**. Independent replay verifies every
record against observed native raw bytes across 51 candidate partitions, with
231 exact command receipts and 1,417 source/artifact seals. The 1,023.403-second
focused run is verification time, not a benchmark. All 177 prior laws are retained
and 13 scoped channel/packing laws are added; these are not a universal decoder
proof. See the [matrix and audit scope](VERIFICATION.md#format-preserving-pic-memory-loading-2026-10-04).
Historical PNG-file hosted success does not qualify PIC; its new 86-gate hosted
checkpoint remains pending.
