# Pixel sizing and raw dithering

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
```

Configure checkouts as described in [README.md](../README.md#requirements).
The probe compares 4,563 size results across all 24 declared formats and selected
unknown codes, plus 42 complete dithered images (406 packed words). Thin images,
alpha thresholds, saturation, custom layouts and zero-width channels are covered
on CPU, JavaScript and forced Metal. Rejected requests retain their original owners.
Other source formats/mipmaps and complete target/resource/performance coverage
remain open.
