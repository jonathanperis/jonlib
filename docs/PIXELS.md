# Pixel sizing, raw access and dithering

## Data sizes

`Pixel.data_size(width: U32, height: U32, format: U32) -> Maybe<&2, U32>` follows
the pinned `GetPixelDataSize`. Dimensions are 0..4096 and format codes are
0..2147483647; outside this profile it returns `None`. Codes use the native
`PixelFormat` values listed in the [API catalog](api/raylib.md).

The operation retains the exact bit rates and truncation. When **both** dimensions
are below four, native formats 14..15 return eight bytes and 16..23 return sixteen
bytes—even with a zero dimension. Format 24 (ASTC 8×8) is excluded from that
minimum and keeps its two-bits-per-pixel calculation. A narrow image with its
other axis at least four also keeps the ordinary calculation. Unknown format
codes return zero. This is reference behavior, not a general block-allocation rule.

Computing a size does not establish decoding or rendering support for that format.
Wider/signed dimension and native integer-overflow domains remain gaps.

## Raw byte/integer pixel access

`Pixel.get_color(bytes: +List<U32>, format: U32)` returns
`Result<&2, &2, Pixel.Error, U32>` containing packed `0xRRGGBBAA`.
`Pixel.set_color(bytes: +List<U32>, color: U32, format: U32)` returns
`Result<&2, &2, Pixel.Error, +List<U32>>` containing the changed byte list.
The latter replaces only the pixel prefix and preserves every trailing byte;
the immutable input remains a value, adapting the C pointer mutation explicitly.

The current formats are 1..7: grayscale, gray-alpha, RGB565, RGB888, RGB5A1,
RGBA4 and RGBA8888. Packed 16-bit words use little-endian bytes. Every supplied
list value must be 0..255, and the list must contain the format's required prefix.
Errors are `UnsupportedPixelFormat`, `InvalidPixelByte` and `TruncatedPixelData`.
Format support is checked before byte validity, then required length.

Reads retain the exact `GetPixelColor` rules. In particular, pinned RGB5A1 blue
is computed from **`word & 31` without removing the alpha bit**: bytes `[1,0]`
produce `0x000008ff`. This differs from the conventional bit-layout interpretation,
`GetImageColor` and `ImageFormat`. Other packed integer reads expand channels
using integer multiplication by 255 followed by division by 31/63/15.

Writes retain native grayscale luminance and nearest channel quantization.
All 768 byte-to-5/6/4-bit conversions are checked against the reference normalized
F32/round calculation before using the equivalent integer quantizer. RGB5A1
alpha is one only for **alpha > 50**, the pinned default threshold. This differs
from the top-bit truncation used by dithering. Float/half/compressed formats,
other configured thresholds, big-endian buffers and native pointer ABI remain gaps.

## Owned dithering

`Surface.dither(surface, r_bits, g_bits, b_bits, a_bits)` returns
`Result<&1, &1, Surface & Surface.Error, Image.Packed16>`.

Each channel width is a U32 in 0..8 and their sum must be at most 16. Invalid
requests return the unchanged source with `InvalidDitherBits{}`. Success consumes
the RGBA8 source and returns `Packed16{width, height, format, pixels}` containing
one low-16-bit U32 word per image pixel. Construct these values through `dither`;
manually inconsistent headers/storage are outside the contract.

The reference truncates channel bits, then diffuses the nonnegative RGB residuals
in row-major order to right/down-left/down/down-right with weights 7/3/5/1 over
16. Each neighbor is saturated separately; alpha is quantized but not diffused.
These small products and divisions are exact dyadic arithmetic before truncation,
so integer operations preserve the reference byte updates. The traversal remains
sequential because later pixels consume those earlier error updates.

Recognized native layouts produce format 3 for 5/6/5/0, format 5 for 5/5/5/1 and
format 6 for 4/4/4/4. Other valid bit layouts retain native format 0 and their raw
packed words. The output storage uses Bend U32 array elements; native 16-bit
allocation size/ABI correspondence remains a gap.

`Image.Packed16.export(image)` consumes the image and returns
`((width, height), (format, words))`, where `words` contains exactly width×height
U32 values. It performs no RGBA reconstruction. This distinction matters: the
reference `GetImageColor` and `ImageFormat` use different 5/6-bit expansion
expressions, so normalizing prematurely would hide an observable format detail.

## Verification

```sh
python3 tools/pixel_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/raw_pixel_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkouts as described in [README.md](../README.md#requirements).
The probe compares 4,563 size results across all 24 declared formats and selected
unknown codes, plus 42 complete dithered images (406 packed words). Thin images,
alpha thresholds, saturation, custom layouts and zero-width channels are covered
on CPU, JavaScript and forced Metal. Rejected requests retain their original owners.
Other source formats/mipmaps and complete target/resource/performance coverage
remain open.

The raw-access probe exhausts all 65,536 two-byte words for each of four formats
(262,144 reads), then compares 1,792 complete eight-byte write buffers and native
readback colors. It also checks all RGB triples against native grayscale writes
and all packed-channel quantizers. Status words make rejected candidate reads
fail the comparison even when the expected color is zero or white. Six typed
failure contracts cover both APIs.
