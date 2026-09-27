# Raw Softimage PIC decoding

`Surface.decode_pic(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with owned RGBA8 output. Shared
memory/file dispatch recognizes the native `53 80 f6 34` signature and `PICT`
marker at byte 88; see [IMAGE-FILES.md](IMAGE-FILES.md).

## Current profile

- Dimensions 1..4096, with the complete 104-byte header present.
- One to ten chained descriptors; any nonzero chain byte continues the list.
- Eight-bit samples and uncompressed packet type 0.
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
Header/count/sample validation precedes output allocation.

Pure/mixed RLE packets, original metadata, native malformed recovery and full
resource/platform/performance coverage remain gaps. PSD arithmetic profiles do
not affect PIC's integer channel operations.

## Verification

```sh
python3 tools/pic_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The probe compares 20 native images / 4,208 pixels and 14 error controls on
CPU, JavaScript and forced Metal. Cases cover every high-bit channel mask,
ignored low bits, white defaults, overlapping channel packets, zero alpha,
ten-packet chains, multiple rows and a 4096-pixel row. Shared dispatch compares
actual PIC data across supported extension families and both `.pic` suffix cases.
Hashes and outcomes are in [evidence/pic-raw.json](evidence/pic-raw.json).

The altered stb reader retains the MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt), with upstream PIC attribution
to Tom Seddon.
