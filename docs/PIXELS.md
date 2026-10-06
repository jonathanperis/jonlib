# Pixel sizing, raw access and dithering

Jonlib adapts raylib 6.0 `GetPixelDataSize`, `GetPixelColor`, `SetPixelColor`
and `ImageDither`.

```bend
Pixel.data_size(width: U32, height: U32, format: U32) -> Maybe<&2, U32>
Pixel.get_color(bytes: +List<U32>, format: U32) -> Result<&2, &2, Surface.Error, U32>
Pixel.set_color(bytes: +List<U32>, color: U32, format: U32) -> Result<&2, &2, Surface.Error, +List<U32>>
Surface.dither(surface, r_bits, g_bits, b_bits, a_bits) -> Result<&1, &1, Surface & Surface.Error, Surface>
Surface.export(image) -> (width, height) & (format, bytes)
```

## Data sizes

`Pixel.data_size` follows the pinned `GetPixelDataSize`. Dimensions are
0..4096 and format codes 0..2147483647; outside this profile it returns `None`.
Codes are the native `PixelFormat` values listed in the
[API catalog](api/raylib.md).

Exact bit rates and truncation are retained. When **both** dimensions are below
four, native formats 14..15 return eight bytes and 16..23 return sixteen bytes,
even with a zero dimension. Format 24 (ASTC 8×8) is excluded from that minimum
and keeps its two-bits-per-pixel calculation. A narrow image whose other axis is
at least four keeps the ordinary calculation. Unknown format codes return zero.
This is reference behavior, not a general block-allocation rule, and computing a
size does not establish decoding or rendering support for that format.

## Raw pixel access

`Pixel.get_color` returns packed `0xRRGGBBAA`. `Pixel.set_color` returns the
changed byte list: it replaces only the pixel prefix and preserves every
trailing byte, adapting the C pointer mutation to an immutable value.

- Formats 1..7: grayscale, gray-alpha, RGB565, RGB888, RGB5A1, RGBA4, RGBA8888.
  Packed 16-bit words are little-endian bytes.
- Every list value must be 0..255 and the list must contain the format's
  required prefix.
- Errors are `UnsupportedFormat`, `InvalidPixelByte` and
  `TruncatedPixelData`, checked in that order (format, then byte validity, then
  length).

Reads keep the exact `GetPixelColor` rules. Pinned RGB5A1 blue is computed from
**`word & 31` without removing the alpha bit**: bytes `[1,0]` produce
`0x000008ff`. This differs from the conventional bit layout, `GetImageColor`
([IMAGE-COLORS.md](IMAGE-COLORS.md)) and `ImageFormat`. Other packed reads expand
channels with integer multiplication by 255 then division by 31/63/15.

Writes keep native grayscale luminance and nearest channel quantization. The
integer quantizer is equivalent to the reference normalized F32/round
calculation for all 768 byte-to-5/6/4-bit conversions. RGB5A1 alpha is one only
for **alpha > 50**, the pinned default threshold, unlike the top-bit truncation
used by dithering.

## Dithering

`Surface.dither` accepts the bit counts that name a 16-bit format: 5/6/5/0
(R5G6B5, format 3), 5/5/5/1 (R5G5B5A1, format 5) and 4/4/4/4 (R4G4B4A4, format
6). Other counts return the unchanged source with `InvalidDitherBits{}`: raylib
would produce an image with the invalid format 0, which no `Surface` can hold.
The source may have any format; it is read through `LoadImageColors` (an
R32G32B32 source needs samples in `[0, 1]`). Success consumes the source and
returns a Surface with one 16-bit word per pixel.

The reference truncates channel bits, then diffuses the nonnegative RGB
residuals in row-major order to right/down-left/down/down-right with weights
7/3/5/1 over 16. Each neighbor is saturated separately; alpha is quantized but
not diffused. These products and divisions are exact dyadic arithmetic before
truncation, so integer operations reproduce the reference byte updates. The
traversal is sequential because later pixels consume earlier error updates.

`Surface.export` consumes the image and returns exactly two little-endian bytes
per pixel with no RGBA reconstruction. This matters because `GetImageColor` and
`ImageFormat` use different 5/6-bit expansion expressions; normalizing early
would hide an observable format detail.

## How it is verified

| Gate | Probe | Compares |
|---|---|---|
| `pixel` | `tools/pixel_probe.py` | `GetPixelDataSize` across all declared formats and selected unknown codes; complete dithered images (thin images, alpha thresholds, saturation) and rejected bit counts and retained owners of rejected requests |
| `raw-pixel` | `tools/raw_pixel_probe.py` | Every two-byte word for each packed format against native `GetPixelColor`; complete write buffers and native readback; all RGB triples for grayscale writes; all packed-channel quantizers; typed failures for both APIs |

Both run on CPU-1, CPU-2, JavaScript and, with `--gpu`, forced GPU. Rejected
candidate reads carry status words, so they cannot match an expected zero or
white color by accident.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only raw-pixel
```

## Known gaps

- Wider or signed dimensions and native integer-overflow domains in
  `data_size`.
- Float/half/compressed formats, other configured thresholds, big-endian buffers
  and the native pointer ABI in raw access.
- Native 16-bit allocation size/ABI correspondence for dithered storage (Bend
  stores U32 array elements); other source formats and mipmaps.
- Complete target/resource/performance coverage.
