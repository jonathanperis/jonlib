# PSD memory decoding and alpha profiles

`Surface.decode_psd(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with owned RGBA8 output.
Shared memory/file dispatch recognizes the exact `8BPS` signature; see
[IMAGE-FILES.md](IMAGE-FILES.md).
`Surface.decode_psd_for(reference, bytes)` selects explicit matte arithmetic;
the convenience operation selects `J.UncontractedDecode{}`.

## Current profile

- PSD version 1, RGB color mode 3, dimensions 1..4096.
- Raw and PackBits RLE data with 0..16 declared channels and 8/16-bit depth headers.
- Channels are read in R/G/B order. Missing color channels default to zero and
  alpha defaults to 255 when absent. Four-plus-channel data supplies actual alpha,
  including zero; only the first four planes are decoded. Extra pixel planes are
  ignored. Zero-channel input produces opaque black, matching the pinned reader.
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

## White-matte arithmetic

With actual alpha, values 0 and 255 preserve RGB unchanged. Intermediate alpha
uses the native F32 sequence `a = alpha/255`, `ra = 1/a`, `inv = 255*(1-ra)`,
then `channel*ra + inv`, truncating to a byte. Supported prematted channels are
`channel >= 255-alpha`; values outside that domain return `InvalidImageStream`
rather than relying on native out-of-range float-to-byte conversion.

Import Jonlib as `J` and choose `J.Image.Decode.Reference` explicitly:

- `J.UncontractedDecode{}` rounds the final multiplication and addition separately.
- `J.FusedDecode{}` uses one correctly rounded fused multiply-add.

The default is uncontracted, consistent with the existing image arithmetic APIs.
Use `_for` on `Surface.decode_psd`, `Surface.decode_image` and `Surface.load_image`
to select a profile. Decoder code does not inspect the operating system. The
native probe validates the declared macOS-arm64 fused and Linux-x86_64
uncontracted selections; other host profiles require verification.

Across all 32,639 valid intermediate-alpha/channel pairs, the models differ in
130 byte outputs. For example, channel 255 with alpha 11 becomes 254 under the
native macOS fused path and 255 under the uncontracted path. The gate also checks
all 512 alpha-0/255 boundary pairs on CPU, JavaScript and forced Metal.

Original metadata, native malformed-stream recovery and full resource/platform/
performance coverage remain gaps. This profile returns composited RGBA8 pixels;
layer editing and PSD export are outside its current API.

## Verification

```sh
python3 tools/psd_matte_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/psd_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares 36 native images / 12,729 pixels and 25 typed-error controls on
CPU, JavaScript and forced Metal. Cases cover representative channel counts and both depths,
reserved/section data, trailing bytes, 4096-pixel axes and header/size/truncation
boundaries. RLE cases add literal/repeat limits, no-ops, cross-row/channel decoding,
ignored row lengths, depth-16 behavior and truncated/overrunning packets. Shared
memory/file gates include both PSD encodings, alpha and cross-extension detection.
Extra-channel cases declare five or sixteen planes while supplying only the
four observed pixel planes. Evidence is in [evidence/psd-alpha.json](evidence/psd-alpha.json).

The altered stb reader retains its MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt).
