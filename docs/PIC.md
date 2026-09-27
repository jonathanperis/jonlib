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

Original metadata, native malformed recovery and full
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
