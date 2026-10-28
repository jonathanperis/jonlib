# Pixel sizing, raw access and dithering

Jonlib adapts raylib 6.2 `GetPixelDataSize`, `GetPixelColor`, `SetPixelColor`
and `ImageDither`.

```bend
Pixel.data_size(width: U32, height: U32, format: U32) -> Maybe<&2, U32>
Pixel.get_color(bytes: +List<U32>, format: U32) -> Result<&2, &2, Surface.Error, U32>
Pixel.set_color(bytes: +List<U32>, color: U32, format: U32) -> Result<&2, &2, Surface.Error, +List<U32>>
Surface.dither(surface, r_bits, g_bits, b_bits, a_bits) -> Result<&1, &1, Surface & Surface.Error, Surface>
Surface.export(image) -> (width, height) & (format, bytes)
```

## Data sizes

`Pixel.data_size_wide` follows the pinned `GetPixelDataSize` for every
nonnegative int dimension and format code, `0..2147483647`. A larger word is
`None`. `Pixel.data_size` is the same function limited to dimensions 0..4096.
Codes are the native `PixelFormat` values listed in the
[API catalog](api/raylib.md).

The byte count is `((unsigned long long)width*height*bpp) >> 3`, wrapped at
2^64. A result that is not strictly below 2^31-1 is 0, which is the path
raylib takes when the image would be 2 GiB or larger.

Exact bit rates and truncation are retained. A zero dimension returns zero
(raylib 6.2 returns before any other rule). When **both** dimensions are below
four, native formats 14..15 return eight bytes and 16..23 return sixteen bytes. Format 24 (ASTC 8×8) is excluded from that minimum
and keeps its two-bits-per-pixel calculation. A narrow image whose other axis is
at least four keeps the ordinary calculation. Unknown format codes return zero.
This is reference behavior, not a general block-allocation rule, and computing a
size does not establish decoding or rendering support for that format.

## Raw pixel access

`Pixel.get_color` returns packed `0xRRGGBBAA`. `Pixel.set_color` returns the
changed byte list: it replaces only the pixel prefix and preserves every
trailing byte, adapting the C pointer mutation to an immutable value.

- Formats 1..7: grayscale, gray-alpha, RGB565, RGB888, RGB5A1, RGBA4, RGBA8888.
  Packed 16-bit words are little-endian bytes. Every list value must be 0..255
  and the list must contain the format's prefix. `InvalidPixelByte` is checked
  before `TruncatedPixelData`.
- Formats 8..13: little-endian F32 or half-float channels. R32 and R16 replicate
  the sample across RGB; a missing alpha is 255. Each channel uses
  `(unsigned char)(sample*255)` when that product lies in `(-1, 256)`, the same
  interval as `LoadImageColors`. A product outside the interval is
  `OutOfDomain` (native undefined behavior). Invalid bytes and a short prefix
  are the same typed failures as formats 1..7; a short native buffer would
  overread.
- Format 0 and every code outside 1..13, including compressed formats and the
  bit patterns of negative C codes, return color 0 and do not read the list.

Reads keep the exact `GetPixelColor` rules. Pinned RGB5A1 blue is computed from
**`word & 31` without removing the alpha bit**: bytes `[1,0]` produce
`0x000008ff`. This differs from the conventional bit layout, `GetImageColor`
([IMAGE-COLORS.md](IMAGE-COLORS.md)) and `ImageFormat`. Other packed reads expand
channels with integer multiplication by 255 then division by 31/63/15.
Format 8 replicates the sample, unlike `LoadImageColors`, which is red-only.

Writes keep native grayscale luminance and nearest channel quantization. The
integer quantizer is equivalent to the reference normalized F32/round
calculation for all 768 byte-to-5/6/4-bit conversions. RGB5A1 alpha is one only
for **alpha > 50**, the pinned default
`PIXELFORMAT_UNCOMPRESSED_R5G5B5A1_ALPHA_THRESHOLD`, unlike the top-bit
truncation used by dithering. Every format outside 1..7 leaves the list
unchanged and does not read it, matching `SetPixelColor`'s default.

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
| `raw-pixel` | `tools/raw_pixel_probe.py` | Every two-byte word for each packed format against native `GetPixelColor`; every R16 word; R32 bands around 0, 0.5, 1 and both cast boundaries; wide, default and short reads; complete write buffers and native readback; no-op writes outside formats 1..7; all RGB triples for grayscale writes; all packed-channel quantizers |

Both run on CPU-1, CPU-2, JavaScript and, with `--gpu`, forced GPU. Rejected
candidate reads carry status words, so they cannot match an expected zero or
white color by accident.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only raw-pixel
```

## Known gaps

- Wider or signed dimensions and native integer-overflow domains in
  `data_size`.
- A float or half channel whose `component*255` lies outside `(-1, 256)` is
  `OutOfDomain` (native undefined behavior). Big-endian buffers and the native
  pointer ABI remain outside raw access. The R5G5B5A1 alpha threshold stays at
  the pinned default of 50.
- Native 16-bit allocation size/ABI correspondence for dithered storage (Bend
  stores U32 array elements); other source formats and mipmaps.
- Complete target/resource/performance coverage.
