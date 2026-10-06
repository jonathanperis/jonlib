# Grayscale channel extraction

Jonlib adapts raylib 6.0 `ImageFromChannel`, which extracts one channel of an
image into a new grayscale image.

```bend
Image.Formatted.from_channel(image, selected: F32) -> Image.Formatted & Maybe<Image.Formatted>
Image.FloatRGB.from_channel(image, selected: F32) -> Image.FloatRGB & Maybe<Image.Formatted>
Surface.from_channel(surface, selected: F32) -> Surface & Surface
```

## Contract

- Sources: checked `Image.Formatted` formats 1..8 (format 8 within the
  [R32](R32.md) domain) and `Image.FloatRGB` with finite `[0,1]` samples.
- Selectors are finite integral F32 values in **-32767..32767**.
- The original image is always retained. Success returns an independent native
  format-1 (grayscale) owner with the source dimensions. Invalid selectors or
  unsupported float samples return the original with `None`.
- `Surface.from_channel` keeps its existing normalized RGBA8 output interface;
  the formatted/float operations expose native grayscale storage instead.

## Native selection and arithmetic

- Negative selectors become zero.
- Grayscale and R32 always select their sole channel.
- Gray-alpha selects gray for zero and alpha for any positive selector.
- RGB565, RGB888 and RGB float select red when the selector exceeds two.
- RGBA layouts select alpha when the selector exceeds three.

The selected normalized channel is multiplied by 255 in F32 and truncated.
Packed channels keep native reciprocal-multiply expansion; raw `GetPixelColor`
integer expansion ([PIXELS.md](PIXELS.md)) is a different contract. RGB float
has no alpha channel to select.

## How it is verified

`tools/image_channel_probe.py` (gate `image-channel`) compares native
`ImageFromChannel` output and every retained source word on CPU-1, CPU-2,
JavaScript and, with `--gpu`, forced GPU. Inputs cover all source layouts,
every byte/packed channel level, float quantization boundaries and selector
redirection; rejected sources and selectors must return their owners, and
mutation checks confirm the grayscale output is independent of the source.
R32 extraction is also compared in gate `r32-image`
(`tools/r32_image_probe.py`).

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only image-channel
```

## Known gaps

Other selector/source domains, other formats, mipmaps and complete native
ABI/resource/platform/performance coverage.
