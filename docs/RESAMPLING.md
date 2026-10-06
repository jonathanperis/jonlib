# Cropping and resampling

Jonlib adapts raylib 6.0's RGBA8 extraction, crop, nearest and default filtered
resize, and the scaled `ImageDraw` path, for `Surface` owners.

| API | raylib profile |
|---|---|
| `Surface.extract(surface, rect) -> Surface & Maybe<Surface>` | `ImageFromImage` |
| `Surface.crop(surface, rect) -> Result<&1, &1, Surface & Surface.Error, Surface>` | `ImageCrop` |
| `Surface.resize_nn(surface, w, h) -> Result<&1, &1, Surface & Surface.Error, Surface>` | `ImageResizeNN` |
| `Surface.resize(surface, w, h) -> Result<&1, &1, Surface & Surface.Error, Surface>` | `ImageResize` |
| `Surface.draw_image_region(destination, source, rect, x, y, tint)` | Unscaled `ImageDraw` |
| `Surface.draw_image_rect(destination, source, rect, target, tint)` | Scaled `ImageDraw` |
| `Surface.mipmaps(surface)` | `ImageMipmaps`, see [MIPMAPS.md](MIPMAPS.md) |

The [RGB float wrappers](FLOAT-RGB.md) reuse these RGBA8 filters after
native-style float-to-byte truncation, then normalize the result back to floats.

## Contract

- `extract` returns the original owner and an independently owned region for a
  positive, integral, in-bounds rectangle.
- `crop` applies raylib's integral clipping, including the outside-origin no-op,
  when the result remains nonempty.
- `resize_nn` uses raylib's **16.16 ratios with the +1 correction**, preserving
  every RGBA byte.
- `resize` accepts single-level RGBA8 images with dimensions 1..4096; invalid
  sizes return the original with `InvalidSize`.
- `draw_image_region` copies an unscaled, in-bounds integral source rectangle
  with destination clipping, tint and alpha, returning both owners.
  `draw_image_rect` integrates the default resizer into source-clipped, scaled
  drawing, including bounded fractional rectangle fields, and returns both owners.

Errors (`InvalidSize`, `InvalidRectangle`, `UnsafeNearestMapping`) return the
original owners. Empty crop results, invalid dimensions and nearest mappings
that would read beyond logical source storage are rejected rather than repaired.

### Nearest-neighbor edge case

Raylib's +1 ratio can cross a source row at extreme upscales. A 2×2 image
resized to 512×1 reads the first pixel of the second row at the right edge;
that is still inside the flat source allocation, and Jonlib reproduces it. A
2×1 source resized to 512×1 would read outside its allocation, so Jonlib
rejects it with `UnsafeNearestMapping` and returns the original image.

## Default filtered resize

`ImageResize` and the scaling path of `ImageDraw` use **stb_image_resize2**.
`src/resample.bend` reproduces, in reference operation order:

- Catmull-Rom for upsampling and Mitchell for downsampling; point sampling on an
  unchanged axis.
- Double-precision coefficient normalization and rational-phase reuse.
- Edge coefficient folding, horizontal coefficient packing and
  dimension-dependent horizontal/vertical ordering.
- Seven-channel filtering for ordinary RGBA (unweighted RGB, alpha and weighted
  RGB), so fully transparent colors are handled deliberately.
- Output clamping and rounding.

The reference build also has architecture-dependent SIMD execution details;
the gates below compare its exact output.

`src/resize_numeric.bend` uses integer limbs for the finite-normal binary64
addition, reciprocal and multiplication required by coefficient normalization,
including nearest-even rounding before conversion back to F32. It is an
internal, bounded numerical contract, not a general IEEE-754 API. Normalizing in
F32 instead is not equivalent: the stock core with only
`STBIR_RENORMALIZE_IN_FLOAT` enabled changes real outputs (for example an
alpha of **124 becoming 125**, and **192 becoming 191**), so no image tolerance
is applied. Exact power-of-two scaling is used instead of an approximate
`pow(2, exponent)`, which changed coefficient bits on Metal.

The implementation keeps a full seven-channel intermediate buffer. `resize_nn`
remains a separate operation.

## How it is verified

- **Filtered resize** (`tools/resize_conformance.py`, gate `resize`): three
  stages compare normalization vectors and coefficient bit patterns (observed
  through logging in a task-local copy of the pinned stb header), packed
  horizontal kernels (first index and every coefficient bit), and whole images
  against unmodified raylib `ImageResize`. The image corpus has seeded cases and
  boundary cases: transparent/opaque colors, identity, anisotropic scales, large
  filter supports and both 4096-to-1 and 1-to-4096 axes. Comparison is exact on
  CPU-1, CPU-2, JavaScript and, with `--gpu`, forced GPU. `--images-only`,
  `--lane` and `--case-prefix` select a focused subset for diagnosis.
- **Main corpus** (`tools/conformance.py`, gate `conformance`): extraction, crop,
  nearest resize, region/rect draws (`blit_region`, `blit_rect`), the retained filtered-resize counterexamples, a
  filtered-resize/crop sequence and invalid-size ownership checks.
- **Precision record** (`tools/filter_probe.py`, gate `filter-precision`,
  diagnostic): compares raylib `ImageResize` with standalone copies of the
  pinned stb core, unmodified and with only float normalization enabled. The
  stock control must match; the float variant's mismatches are reported as a
  record, never as parity.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only resize
```

## Known gaps

Memory and speed parity, other pixel formats, multi-level (mipmapped) inputs,
dimensions beyond the Surface profile, other GPU models and complete platform
integration.

## Provenance

`src/resample.bend` is an altered Bend adaptation of
[stb_image_resize2](https://github.com/raysan5/raylib/blob/dbc56a87da87d973a9c5baa4e7438a9d20121d28/src/external/stb_image_resize2.h)
as vendored by pinned raylib (MIT alternative selected; complete notice in
[LICENSES/stb_image_resize2.txt](../LICENSES/stb_image_resize2.txt), details in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)). No stb implementation is
linked into the Bend library; the probes compile the header only as reference
tooling.
