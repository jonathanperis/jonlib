# Text-byte images, grayscale and palettes

Jonlib adapts raylib 6.0 `GenImageText` (data-image form), `ImageColorGrayscale`
and `LoadImagePalette` / `UnloadImagePalette` for RGBA8 `Surface` owners.

```bend
Surface.create_text_bytes(width, height, bytes: +List<U32>) -> Maybe<Surface>
Surface.color_grayscale(surface) -> Surface
Surface.load_palette(surface, maximum) -> Surface & Maybe<Image.Palette>
Image.Palette.entries(palette) -> U32 & +List<U32>
Image.Palette.unload(palette) -> Unit
```

## Text bytes as pixel data

`create_text_bytes` adapts `GenImageText`'s grayscale **data-image** operation:
each byte becomes a grayscale pixel; no glyphs are rendered. Input stops at the
first NUL byte and truncates at `width*height`; remaining pixels are black.
Output is opaque RGBA8, matching native grayscale followed by RGBA8 conversion.

Dimensions must be 1..4096 and every supplied byte value 0..255, including data
after a NUL or beyond the output capacity; otherwise the result is `None`. The
caller controls text encoding by supplying bytes.

## Grayscale conversion

`color_grayscale` keeps dimensions and converts RGB through the reference
normalized F32 luminance expression:

```text
((r/255)*0.299 + (g/255)*0.587 + (b/255)*0.114)*255
```

Each result is truncated to a byte and replicated into RGB. Alpha becomes 255,
including pixels whose input alpha was zero.

## Palettes

`load_palette` retains the source image. The maximum capacity must be 1..4096;
an invalid capacity returns the source and `None`. A valid palette:

- keeps first-occurrence order in the row-major image;
- skips alpha-zero colors, regardless of hidden RGB;
- treats different nonzero alpha values as distinct RGBA colors;
- stops when capacity is reached;
- fills the unused capacity with BLANK (`0x00000000`) entries.

`Image.Palette.entries` consumes the palette and returns the actual count plus
**all capacity entries**, including padding. `Image.Palette.unload` consumes an
unwanted palette. Create palettes only through `Surface.load_palette`; manually
inconsistent constructors are outside the contract.

## How it is verified

These operations are covered by the main corpus (`tools/conformance.py` with
`tests/fixtures/images.json`, gate `conformance`), which compares against native
`GenImageText`, `ImageColorGrayscale` (followed by explicit RGBA8 normalization)
and `LoadImagePalette`. Palette cases compare the count, every capacity entry and
the unchanged source pixels; the harness rejects malformed count/length and
changed padding. A combined fixture checks that palette observation, alpha bounds
and QOI export coexist without losing metadata or ownership. Before accepting
grayscale fixtures, the native runner checks the luminance arithmetic against
all 16,777,216 RGB triples.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only conformance
```

## Known gaps

- Native grayscale storage (results are RGBA8) and C-string pointer/null/encoding
  correspondence for text bytes.
- Other grayscale input formats and mipmaps.
- Native palette pointer/null/allocator semantics.
- Complete platform/resource/performance coverage.
