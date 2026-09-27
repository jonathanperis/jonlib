# Owned byte/integer image formats

`Image.Formatted` stores an owned single-mip image in native format codes 1..7:
grayscale, gray-alpha, RGB565, RGB888, RGB5A1, RGBA4 and RGBA8888. Dimensions are
1..4096. Internal storage has one logical packed U32 per pixel; exported bytes
follow the native little-endian layout. Allocation size and C pointer ABI are
separate compatibility gaps.

| API | Contract |
|---|---|
| `Image.Formatted.from_bytes(width, height, format, bytes) -> Maybe<Image.Formatted>` | Checks supported dimensions/format, byte values 0..255 and the exact required byte count before allocation. |
| `Surface.to_formatted(surface) -> Image.Formatted` | Consumes canonical RGBA8 Surface storage and produces format 7 with exact byte order. |
| `Image.Formatted.convert(image, target)` | Returns `Result<&1, &1, Image.Formatted & Pixel.Error, Image.Formatted>`. Same-format and target-zero requests return the original image. Unsupported targets return the original owner with `UnsupportedPixelFormat`. |
| `Image.Formatted.to_surface(image) -> Surface` | Consumes the image and performs the reference conversion to RGBA8, then adapts byte order to Surface's `0xRRGGBBAA` words. |
| `Image.Formatted.export(image)` | Consumes ownership and returns `((width, height), (format, bytes))`, with every native-order byte and no storage padding. |
| `Image.Formatted.to_png(image)` | Default PNG memory export for byte formats 1/2/4/7; unsupported packed formats retain their owner in `Fail`. See [PNG-EXPORT.md](PNG-EXPORT.md). |
| `Image.Formatted.write_png(image, path)` | Default PNG file export for all seven checked formats, preserving native packed-color expansion. See [PNG-EXPORT.md](PNG-EXPORT.md). |

Create owners with the checked factory or Surface bridge. Manually inconsistent
`FormattedImage{width, height, format, pixels}` values are outside the contract.
`Image.Formatted.load_raw` and `write_raw` provide file boundaries with explicit
header/error/closure behavior, documented in [RAW-FILES.md](RAW-FILES.md).

## Conversion arithmetic

The implementation follows `ImageFormat` through its normalized F32 channel
representation. Packed source channels multiply by the reference reciprocal
of 31/63/15. Destination formats retain their original luminance, rounding,
truncation and strict RGB5A1 alpha threshold. Conversion does not first reduce
the source to RGBA8, which could discard precision before the next quantization.

This path is intentionally separate from `GetPixelColor`. In particular,
RGB5A1 blue is extracted from bits 1..5 during `ImageFormat`, whereas the pinned
raw pixel getter uses the low five bits including alpha. The formatted-image
converter follows the former. Same-format conversions preserve bytes directly
instead of applying an unnecessary normalization round trip.

## Evidence

```sh
python3 tools/image_format_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The probe compares all 49 source/destination pairs, target-zero no-ops, conversion
chain prefixes and Surface bridges: 109 complete images / 3,192 bytes per lane.
Exact dimensions, format and complete byte arrays must match native raylib on
CPU, JavaScript and forced Metal. Seven additional contracts cover invalid
factory inputs, retained owners and the RGBA8 bridge.

The separate [RGB float bridge](FLOAT-RGB.md) supports owned format-9 conversion
to/from Surface without changing the `Image.Formatted` format-1..7 domain.
Its [raw-byte interface](FLOAT-RGB-BYTES.md) preserves non-NaN format-9 words.
Other float/half/compressed formats, mipmaps, other configured alpha thresholds,
big-endian/native pointer layouts and full target/resource/performance evidence
remain open.
