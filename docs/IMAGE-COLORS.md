# Bulk and point image colors

Jonlib adapts raylib 6.0 `LoadImageColors` (bulk) and `GetImageColor` (point)
for every pixel format.

```bend
Surface.colors(image) -> Result<&1, &1, Surface & Surface.Error, List<U32>>
Surface.get(image, x: U32, y: U32) -> Surface & Maybe<&2, U32>
```

## Contract

- `Surface.colors` consumes the image and returns every pixel as packed RGBA8 in
  row-major order. Formats 1..8 always succeed. R32G32B32 truncates each finite
  `[0,1]` sample through native F32 `component*255`, with opaque alpha; other
  samples return the original owner with `OutOfDomain`.
- `get` returns the retained owner and the selected color. Bounds are checked
  before array access; out-of-bounds coordinates return `None`. Float reads also
  return `None` for an unsupported selected sample. Only the selected pixel is
  validated, so an unsupported sample elsewhere does not prevent a valid read.

## Per-format color rules

These match actual `LoadImageColors` / `GetImageColor`:

| Format | RGBA8 color |
|---|---|
| 1 grayscale, 2 gray-alpha | Byte values preserved (gray replicated into RGB) |
| 3 RGB565 | Five-bit channels ×8, six-bit channel ×4, alpha 255 |
| 5 RGB5A1 | Conventional shifted blue field; five-bit channels ×8, alpha bit 0/255 |
| 6 RGBA4 | Each nibble ×17 |
| 4 RGB888, 7 RGBA8888 | Bytes preserved (RGB888 opaque) |
| 8 R32 | Red-only color with opaque alpha (see [R32.md](R32.md)) |
| 9 R32G32B32 | Truncated `component*255` with opaque alpha |

These deliberately differ from `ImageFormat`'s normalized reciprocal
arithmetic and from the low-level `GetPixelColor` (`Pixel.get_color`, see
[PIXELS.md](PIXELS.md)), whose RGB5A1 blue reads the low five bits including
the alpha bit. The R32 rule here does not implement `GetPixelColor`'s distinct
R32 behavior. The operations keep separate mappings rather than sharing one
misleading universal color decoder.

## How it is verified

`tools/image_colors_probe.py` (gate `image-colors`) compares bulk and point
colors with native `LoadImageColors` / `GetImageColor` over every formatted
byte/packed layout and RGB float, on CPU-1, CPU-2, JavaScript and, with `--gpu`,
forced GPU. After point reads every source word is compared with native
storage. Controls cover out-of-bounds coordinates, rejected float samples, a
valid pixel beside an unsupported sample and the unchanged owner of a failed
bulk float export. R32 colors are compared in gate `r32-image`
(`tools/r32_image_probe.py`).

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only image-colors
```

## Known gaps

Other source domains, float/half/compressed formats, mipmaps and complete
native ABI/resource/platform/performance coverage.
