# Opaque PSD memory decoding

`Surface.decode_psd(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with owned RGBA8 output.
Shared memory/file dispatch recognizes the exact `8BPS` signature; see
[IMAGE-FILES.md](IMAGE-FILES.md).

## Current profile

- PSD version 1, RGB color mode 3, dimensions 1..4096.
- Raw and PackBits RLE data with 0..3 declared channels and 8/16-bit depth headers.
- Channels are read in R/G/B order. Missing color channels default to zero and
  alpha defaults to 255. Zero-channel input therefore produces opaque black,
  matching the pinned reader.
- Six reserved header bytes are ignored. Three length-prefixed mode/resource/layer
  sections are skipped after checking availability; their contents are not interpreted.
- Raw sixteen-bit samples are big-endian and retain their **high byte**, matching
  native `stbi_load` normalization. This differs from the pinned PNM reader's
  unswapped little-endian sample behavior.
- Complete raw plane data is checked before output allocation. RLE packets are
  checked against input availability and remaining output before writes. Valid
  trailing bytes are ignored; every supplied element must still be a byte.

Invalid bytes return `InvalidImageByte`; unsupported/incomplete header fields
return `InvalidImageHeader`; unsupported dimensions return `UnsupportedImageSize`.
Missing section payload or pixel samples return `TruncatedImageData`.
RLE packets that exceed the remaining plane return `InvalidImageStream`.

## Native PackBits behavior

Compression 1 skips a two-byte count for every declared row/channel. Native
decoding ignores those count values and decodes each channel as one continuous
stream, so packets may cross rows.

- Controls 0..127 copy the next `control + 1` bytes.
- Controls 129..255 repeat the next byte `257 - control` times.
- Control 128 is a no-op. Input-byte fuel bounds no-op processing.
- RLE produces **one byte per output sample even with a depth-16 header**,
  matching the pinned reader. It does not use raw sixteen-bit sample narrowing.

Four-plus-channel white-matte correction, original metadata,
native malformed-stream recovery and full resource/platform/performance coverage
remain gaps. This profile adds opaque composited image pixels, not layer editing
or a PSD exporter.

## Verification

```sh
python3 tools/psd_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares 24 native images / 12,657 pixels and 23 typed-error controls on
CPU, JavaScript and forced Metal. Cases cover all supported channel counts/depths,
reserved/section data, trailing bytes, 4096-pixel axes and header/size/truncation
boundaries. RLE cases add literal/repeat limits, no-ops, cross-row/channel decoding,
ignored row lengths, depth-16 behavior and truncated/overrunning packets. Shared
memory/file gates include both PSD encodings and cross-extension detection.
Evidence is in [evidence/psd-rle.json](evidence/psd-rle.json).

The altered stb reader retains its MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt).
