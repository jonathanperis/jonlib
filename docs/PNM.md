# Binary PGM/PPM memory decoding

`Surface.decode_pnm(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with owned opaque RGBA8 output.

The current profile supports binary P5 grayscale and P6 RGB images, dimensions
1..4096, and a declared maximum sample value (`maxval`) in 1..65535. Decimal header
values are bounded before arithmetic. Input byte values must be 0..255.

## Native parsing and sample rules

- Whitespace and `#` comments are handled between numeric header fields. Comments
  terminate at CR or LF; all six native whitespace characters are recognized.
- After `maxval`, exactly **one whitespace byte** is consumed. Additional bytes
  belong to the raster, even if they are whitespace or `#`. A CRLF separator
  therefore leaves LF (`10`) as the first raster byte, matching the pinned reader.
- Samples are retained **without rescaling**, including when `maxval` is below
  255 or a sample exceeds that declared value. P5 samples are replicated into RGB;
  all output alpha values are 255.
- `maxval` 1..255 selects one byte per sample; 256..65535 selects two. For the
  pinned **little-endian native profile**, two-byte samples retain their **second
  stored byte**. Native stb copies the PNM bytes into host U16 values without
  swapping and later shifts those values right by eight during 8-bit conversion.
  Thus stored bytes `12 34` produce `34`, not `12`. Jonlib deliberately preserves
  this observed raylib behavior rather than standard big-endian PNM interpretation.
- Complete row-major sample data is required. Valid trailing bytes are ignored.

Invalid bytes return `InvalidImageByte`. Unsupported magic/depth, invalid numeric
fields, decimal overflow, missing header fields or an unsupported maxval
separator return `InvalidImageHeader`. Invalid dimensions return
`UnsupportedImageSize`; too few raster bytes return `TruncatedImageData`.
Dimensions and payload availability are checked before output allocation.

The native API is invoked through its supported `.ppm` dispatch, which detects
both P5 and P6 magic. This API is separate from `Surface.to_ppm`'s inspectable P3
text exporter: the pinned native PNM loader also does not accept ASCII P1..P4.
Original-format metadata, big-endian native profiles and permissive malformed
header recovery remain gaps. Shared memory/file dispatch is documented in
[IMAGE-FILES.md](IMAGE-FILES.md).

## Verification

```sh
python3 tools/pnm_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The shared bitmap gate compares 30 native images / 8,844 pixels and 16 typed-error
controls on CPU, JavaScript and forced Metal, including 4096×1 and 1×4096 images.
The 16-bit cases exercise maxval boundaries, all 256 retained byte values,
channel ordering, CRLF consumption, trailing data and incomplete samples/channels.
Invalid discarded bytes are still rejected. Shared memory/file gates include a
16-bit PPM payload. Hashes and lane results are in
[evidence/pnm-16bit.json](evidence/pnm-16bit.json). The altered stb reader retains the MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt). Full target/resource/performance
parity remains open.
