# Opaque raw PSD memory decoding

`Surface.decode_psd(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with owned RGBA8 output.
Shared memory/file dispatch recognizes the exact `8BPS` signature; see
[IMAGE-FILES.md](IMAGE-FILES.md).

## Current profile

- PSD version 1, RGB color mode 3, dimensions 1..4096.
- Uncompressed 8/16-bit planar data with 0..3 declared channels.
- Channels are read in R/G/B order. Missing color channels default to zero and
  alpha defaults to 255. Zero-channel input therefore produces opaque black,
  matching the pinned reader.
- Six reserved header bytes are ignored. Three length-prefixed mode/resource/layer
  sections are skipped after checking availability; their contents are not interpreted.
- Sixteen-bit samples are big-endian and retain their **high byte**, matching
  native `stbi_load` normalization. This differs from the pinned PNM reader's
  unswapped little-endian sample behavior.
- Complete required plane data is checked before output allocation. Valid
  trailing bytes are ignored; every supplied element must still be a byte.

Invalid bytes return `InvalidImageByte`; unsupported/incomplete header fields
return `InvalidImageHeader`; unsupported dimensions return `UnsupportedImageSize`.
Missing section payload or pixel samples return `TruncatedImageData`.

RLE compression, four-plus-channel white-matte correction, original metadata,
native malformed-stream recovery and full resource/platform/performance coverage
remain gaps. This profile adds opaque composited image pixels, not layer editing
or a PSD exporter.

## Verification

```sh
python3 tools/psd_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares 12 native images / 8,247 pixels and 16 typed-error controls on
CPU, JavaScript and forced Metal. Cases cover all supported channel counts/depths,
reserved/section data, trailing bytes, 4096-pixel axes and header/size/truncation
boundaries. Shared memory/file gates include actual PSD payloads and cross-extension
detection. Evidence is in [evidence/psd-raw.json](evidence/psd-raw.json).

The altered stb reader retains its MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt).
