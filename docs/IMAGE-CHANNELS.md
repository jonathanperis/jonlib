# Owned grayscale channel extraction

`Image.Formatted.from_channel(image, selected)` returns
`Image.Formatted & Maybe<Image.Formatted>` for source formats 1..8, with the
checked [R32 domain](R32.md) for format 8.
`Image.FloatRGB.from_channel(image, selected)` returns
`Image.FloatRGB & Maybe<Image.Formatted>` for finite `[0,1]` RGB float sources.

The original image is retained. Success returns an independent grayscale owner
in native format 1, preserving source dimensions. Invalid selectors or unsupported
float samples return the original with `None`. Selectors are finite integral F32
values in -32767..32767.

## Native selection and arithmetic

- Negative selectors become zero.
- Grayscale and R32 always select their sole channel.
- Gray-alpha selects gray for zero and alpha for any positive selector.
- RGB565, RGB888 and RGB float select red when the selector exceeds two.
- RGBA layouts select alpha when the selector exceeds three.

The selected normalized channel is multiplied by 255 in F32 and truncated.
Packed channels retain native reciprocal-multiply expansion; raw `GetPixelColor`
integer expansion is a different contract. Alpha selection remains meaningful in
gray-alpha and RGBA images; RGB float has no alpha channel to select.

`Surface.from_channel` retains its existing normalized RGBA8 output interface.
The new operations expose native grayscale storage without changing that API.

## Verification

```sh
python3 tools/image_channel_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares 48 native cases / 15,366 grayscale pixels and every retained
source word on CPU/JavaScript/forced Metal. Inputs cover all eight source layouts,
every byte/packed channel level, float quantization boundaries and selector
redirection. Seven rejected-source/selector cases retain their owners. Separate
mutation checks establish independent grayscale output for formatted and float
sources. See [evidence/image-channels.json](evidence/image-channels.json).

Other selector/source domains, formats/mipmaps and complete native-ABI/resource/
platform/performance coverage remain gaps.
