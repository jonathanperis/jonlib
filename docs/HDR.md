# Owned Radiance RGBE float images

`Image.FloatRGB.decode_hdr(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Image.FloatRGB>`. Its owned pixels are
`Array<M.Vector3>`, using Jonmath's shared vector type. Values preserve the native
`PIXELFORMAT_UNCOMPRESSED_R32G32B32` (format 9) sample bits.

`Image.FloatRGB.entries(image)` consumes the image and returns
`(width, height, List<M.Vector3>)` in top-down row-major order.
`Image.FloatRGB.unload(image)` consumes the owner and returns `Unit`.

## Current raw profile

- `#?RADIANCE` or `#?RGBE` identifier, followed by LF-delimited header lines.
- Exact `FORMAT=32-bit_rle_rgbe` metadata line, blank separator and
  `-Y height +X width` layout. Decimal dimensions are 1..4096; repeated spaces
  and leading zeroes are accepted. Other metadata lines are ignored.
- Header lines contain at most 1,023 bytes without embedded NUL. Complete line
  terminators and all raw RGBE samples are required.
- Widths below eight decode raw data directly. Wider images accept native raw
  fallback when the first sample is not the `2,2,high,low` RLE marker with
  `high < 128`. Actual scanline RLE is outside this increment.
- Valid trailing bytes are ignored, while every supplied element must be a byte.

Exponent zero produces black regardless of stored RGB. Otherwise each component
is exactly `channel * 2^(exponent - 136)`. This product fits F32 exactly throughout
the byte domain, including subnormal results. The Bend implementation constructs
the declared F32/Word carrier bits from integers, retaining native subnormals on
all checked backends without floating-point underflow arithmetic.

Invalid/incomplete headers and unsupported encodings return `InvalidImageHeader`;
invalid dimensions return `UnsupportedImageSize`; missing raw samples return
`TruncatedImageData`; non-byte values return `InvalidImageByte`. Dimensions and
complete required sample length are checked before output allocation.

RGBA8 conversion, shared float-format dispatch/file loading, scanline RLE, broader
header/permissive recovery and complete metadata/resource/platform/performance
coverage remain gaps. `Surface.decode_image` retains its RGBA8 profiles; use the
typed float API to preserve HDR samples.

## Verification

```sh
python3 tools/hdr_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares 10 native images / 8,225 RGB pixels, thirteen typed-error
controls and all **65,536 channel/exponent pairs** on CPU, JavaScript and forced
Metal. Every component is compared as exact F32 bits. It exercises normal/
subnormal/extreme exponents, zero-exponent black, raw-marker boundaries,
metadata/decimal parsing and 4,096-pixel axes. Consuming entries and unload are
also checked. Evidence is in [evidence/hdr-raw.json](evidence/hdr-raw.json).

The altered stb reader retains its MIT notice and upstream Nicolas Schulz credit;
see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
