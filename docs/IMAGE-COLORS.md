# Native bulk and point image colors

`Image.Formatted.colors(image)` consumes a checked format-1..8 image and returns
every packed RGBA8 color as `List<U32>`, in row-major order.
Bounded [R32](R32.md) samples produce red-only colors with opaque alpha;
this does not implement the distinct low-level `GetPixelColor` R32 behavior.
`Image.FloatRGB.colors(image)` returns
`Result<&1, &1, Image.FloatRGB, List<U32>>`: finite `[0,1]` RGB is truncated through
native F32 `component*255`, with opaque alpha; unsupported samples return the
original owner.

Both image types also expose `get(image, x: U32, y: U32)`, returning the retained
owner and `Maybe<&2, U32>`. Bounds are checked before array access. Out-of-bounds
coordinates return `None`; float reads also return `None` for unsupported selected
samples. Only the selected float pixel is validated, so another unsupported pixel
does not prevent a valid point read.

## Packed-format distinctions

These APIs reproduce actual `LoadImageColors` and `GetImageColor`:

- RGB565 expands five-bit channels by 8 and the six-bit channel by 4.
- RGB5A1 uses the conventional shifted blue field and alpha bit.
- RGBA4 expands each nibble by 17; gray and gray-alpha preserve byte values.

This differs from `ImageFormat`'s normalized reciprocal arithmetic and the
separate raw `GetPixelColor` RGB5A1 low-five-bit blue quirk. The operations retain
their distinct mappings rather than sharing a misleading universal color decoder.

## Verification

```sh
python3 tools/image_colors_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares eight layouts / 2,561 pixels as both native bulk and point
colors on CPU/JavaScript/forced Metal. Every source word after point reads is
compared with native storage. Six point controls cover bounds, rejected float
samples and a valid pixel beside an unsupported sample. A failed bulk float
export returns its unchanged owner. The existing 33,024-pixel float conversion
gate also passes after sharing its pixel conversion helper. See
[evidence/image-colors.json](evidence/image-colors.json).

Other source domains, float/half/compressed formats, mipmaps and complete native
ABI/resource/platform/performance coverage remain gaps.
