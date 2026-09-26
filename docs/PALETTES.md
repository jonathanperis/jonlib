# Text-byte images, grayscale and palettes

## Text bytes as pixel data

`Surface.create_text_bytes(width, height, bytes: +List<U32>) -> Maybe<Surface>`
adapts `GenImageText`'s grayscale **data-image** operation. Each byte becomes a
grayscale pixel; this operation does not render glyphs. Input stops at the first
NUL byte, truncates at `width*height`, and the remaining pixels are black.
Output is opaque RGBA8, matching native grayscale followed by RGBA8 conversion.

Dimensions must be 1..4096 and all supplied byte values must be 0..255, including
any data after a NUL or beyond the output capacity. Invalid input returns `None`.
The caller controls text encoding by supplying bytes. Native grayscale storage
and C-string pointer/null/encoding correspondence remain gaps.

## Grayscale conversion

`Surface.color_grayscale(surface) -> Surface` retains dimensions and converts
RGBA8 RGB through the reference normalized F32 luminance expression:

```text
((r/255)*0.299 + (g/255)*0.587 + (b/255)*0.114)*255
```

Each result is truncated to a byte and replicated into RGB. Alpha becomes 255,
including pixels whose input alpha was zero. The reference check performs
`ImageColorGrayscale` followed by explicit RGBA8 normalization. Before accepting
fixtures, the native runner checks the arithmetic against all **16,777,216 RGB
triples**. Other input formats, native grayscale storage and mipmaps remain gaps.

## Owned palettes

`Surface.load_palette(surface, maximum) -> Surface & Maybe<Image.Palette>`
preserves the original image. Maximum capacity must be 1..4096; invalid capacity
returns that source and `None`. A valid palette:

- Retains first occurrence order in the row-major image.
- Skips alpha-zero colors, regardless of hidden RGB.
- Treats different nonzero alpha values as distinct RGBA colors.
- Stops when capacity is reached.
- Includes BLANK (`0x00000000`) entries through the entire unused capacity.

`Image.Palette.entries(palette) -> U32 & +List<U32>` consumes the palette and
returns the actual count plus **all capacity entries**, including padding.
`Image.Palette.unload(palette) -> Unit` consumes an unwanted palette. Create
palette owners through `Surface.load_palette`; manually inconsistent constructors
are outside the contract. Native pointer/null/allocator semantics remain gaps.

The corpus compares counts, every entry and the unchanged source pixels. A
combined fixture verifies that palette observation, alpha bounds and QOI export
coexist without losing metadata or ownership. Malformed count/length and changed
padding are rejected by the harness. Complete platform/resource/performance
coverage remains open.
