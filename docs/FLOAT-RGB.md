# RGB float images

`Image.FloatRGB` is an owned raylib format-9 image (`PIXELFORMAT_UNCOMPRESSED_R32G32B32`):
row-major RGB F32 samples with logical dimensions. It is produced by the
[HDR decoder](HDR.md), the RGBA8 bridge, raw bytes/files and format conversion,
and its operations reproduce what raylib 6.0 does to format-9 images. Many
native format-9 operations go through RGBA8, so they **quantize** even when
nominally lossless; Jonlib keeps that behavior instead of treating them as float
remaps.

## Sample domains

Two domains recur below:

- **Non-NaN words**: every F32 bit pattern except NaN (signed zero, subnormals,
  infinities, values outside `[0,1]`). Used by lossless movement and raw-byte
  operations. NaN is excluded because the pinned JavaScript representation
  canonicalizes NaN payloads and signs.
- **Finite `[0,1]`**: signed zero and positive subnormals are accepted; negative
  subnormals, values above one, infinities and NaNs are rejected. Used by every
  operation that converts to bytes. Validation uses float-bit ordering, so a
  GPU's denormal mode cannot turn a negative subnormal into an accepted zero.

Rejection always returns the original owner with every sample bit intact.
Dimensions and storage must satisfy the image-owner invariant; create owners
through the APIs on this page or the HDR/raw loaders, since manually
inconsistent owner records are outside the contract.

## RGBA8 bridge

| API | Contract |
|---|---|
| `Surface.to_float_rgb(surface) -> Image.FloatRGB` | Consumes RGBA8, normalizes each RGB byte with native F32 `byte/255` and discards alpha, as format 9 does |
| `Image.FloatRGB.to_surface(image) -> Result<&1, &1, Image.FloatRGB, Surface>` | Finite `[0,1]` samples become opaque RGBA8 through native F32 `component*255` truncation; otherwise `Fail` with the original owner |

This is the native `ImageFormat` format-7/format-9 bridge: logical dimensions
and row order are kept, with no gamma, clamping or tone mapping. HDR values
outside `[0,1]` remain available through `Image.FloatRGB.entries` after rejection.

## Raw bytes

```bend
Image.FloatRGB.from_bytes(width, height, bytes: +List<U32>) -> Maybe<Image.FloatRGB>
Image.FloatRGB.to_bytes(image) -> Result<&1, &1, Image.FloatRGB, +List<U32>>
```

`from_bytes` checks dimensions 1..4096 and exactly `width*height*12` byte
values, reading three little-endian F32 words per pixel. `to_bytes` consumes the
image and emits the exact format-9 words without storage padding. Both support
the non-NaN domain: import rejects NaN words before constructing floats, and
export rejects NaN samples while returning the owner. No normalization, gamma or
tone mapping is applied. Exact raw NaN-word interoperability is outside the
profile. The `Image.Formatted` byte factory keeps its own format domain.

## Lossless copy and orientation

`Image.FloatRGB.copy(image)` returns `(original, copy)` with independent storage.
`flip_horizontal`, `flip_vertical`, `rotate_cw` and `rotate_ccw` consume the
image and preserve every non-NaN sample word: flips keep dimensions, quarter
turns swap them. RGB vectors move without normalization, matching native
format-9 byte movement.

## Extraction and crop

- `extract(image, rectangle) -> Image.FloatRGB & Maybe<Image.FloatRGB>` keeps the
  source and returns an independent region for a positive, integral, in-bounds
  rectangle; otherwise `None`.
- `crop(image, rectangle) -> Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>`
  clips integral rectangles with the Surface rules. Positive clipped regions keep
  exact sample words. An origin strictly beyond the image returns the unchanged
  owner, as native does; other unsupported rectangles return the owner with
  `InvalidRectangle`. Fractional or native-invalid geometry is outside the profile.

## Resizing

`resize_nn(image, width, height)` and `resize(image, width, height)` return
`Result<&1, &1, Image.FloatRGB, Image.FloatRGB>`. Destination dimensions are
1..4096 and samples must be finite `[0,1]`; unsupported inputs and unsafe
fixed-point nearest mappings return the original, unquantized owner.

The native format-9 path converts to RGBA8, resizes (nearest: the plus-one 16.16
mapping; filtered: four-channel Catmull-Rom/Mitchell, see
[RESAMPLING.md](RESAMPLING.md)), then normalizes RGB back to floats. **Even
unchanged dimensions quantize**: `0.5` becomes `127/255`. The original float
storage is retained through fallible stages without cloning it for recovery.

## Canvas and POT

`resize_canvas(image, width, height, x, y, fill)` and `to_pot(image, fill)` return
`Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>`. Dimensions are
1..4096; offsets follow the bounded integral Surface profile, with positive
overlap required when dimensions change. Invalid requests return the owner.

Moved non-NaN words stay exact. Native format 9 **ignores the fill color**
because `SetPixelColor` has no float case, so exposed pixels remain positive RGB
zero. Same-size requests with in-profile offsets preserve the source. POT uses
the established next-power-of-two calculation.

## Color transforms

`color_tint`, `color_invert`, `color_contrast`, `color_brightness` and
`color_replace` return `Result<&1, &1, Image.FloatRGB, Image.FloatRGB>`. They
truncate finite `[0,1]` samples to RGBA8, apply the byte operation, then
normalize RGB back; nominal no-ops still quantize. Unsupported samples or
parameters return the owner.

- Contrast must be finite and is clamped to -100..100.
- Brightness must be finite and integral and is clamped to -255..255; native
  negative channel underflow becomes one rather than zero.
- Tint and replacement alpha are discarded on the way back to RGB. Replacement
  still matches all four RGBA bytes, with input alpha 255.

## Byte/integer formats and grayscale

`Image.FloatRGB.to_formatted(image, target) -> Result<&1, &1, Image.FloatRGB, Image.Formatted>`
accepts targets 1..8 and finite `[0,1]` samples. It uses native normalized F32
channels directly with alpha one; it does **not** first truncate to RGBA8.
`color_grayscale(image)` selects target 1, matching the native change to
grayscale storage. Targets 0 and 9 are unsupported.

- Packed channels round the already-rounded F32 product as native `round` does.
  Adding one half in F32 first can round twice: words `0x3d088888` (limit 15)
  and `0x3c020820` (limit 63) must produce zero, while add-half/floor gives one.
- Grayscale keeps direct, uncontracted F32 luminance order and byte truncation.
- Target 8 ([R32](R32.md)) uses the same uncontracted luminance without clamping
  or RGBA8 quantization. All three components must be finite `[0,1]`, even if
  the result would be representable. Because coefficients are positive, rounded
  operations are monotone and `(1,1,1)` gives exactly one; signed-zero and
  subnormal results are valid R32 samples. The luminance relies on separate
  multiply/add instructions; fused or contracted variants are not claimed.

`Image.Formatted.to_float_rgb(image)` consumes any checked format-1..8 owner and
returns format-9 storage. Grayscale replicates into RGB and alpha is discarded.
Packed channels use the native reciprocal-multiply expansion directly,
preserving float bits an intermediate RGBA8 conversion would lose. R32 maps its
sample to red with exact positive zeros for green/blue. The chains `9→8→9` and
`8→9→8` are not identities: R32 keeps only red, and re-encoding applies
luminance again.

## Related pages

- Colors and point reads: [IMAGE-COLORS.md](IMAGE-COLORS.md); channel extraction
  (which follows RGB selector redirection): [IMAGE-CHANNELS.md](IMAGE-CHANNELS.md).
- PNG (raw-prefix memory vs normalized file), BMP, TGA and RAW export:
  [IMAGE-EXPORT.md](IMAGE-EXPORT.md); raw file loading/writing:
  [RAW-FILES.md](RAW-FILES.md); image-as-code: [IMAGE-CODE.md](IMAGE-CODE.md).

Surface colors, FloatRGB entries and packed/formatted image exports share a
tail-recursive logical-prefix operation instead of Base `List.take`, whose
generated JavaScript recursed once per pixel and overflowed the stack on large
images. Output lengths, order and ownership are unchanged.

## How it is verified

Each gate compares against the native format-9 operation in pinned raylib with
exact F32 words or complete bytes, on CPU-1, CPU-2, JavaScript and, with
`--gpu`, forced GPU (except where noted). Every gate also checks that rejected
inputs return complete, unchanged owners.

| Gate | Probe | Compares |
|---|---|---|
| `float-rgb` | `tools/float_rgb_probe.py` | RGBA8 bridge via `ImageFormat`: every byte value, float boundaries, in-range HDR pixels, negative-subnormal/out-of-range/infinite/NaN rejection |
| `float-rgb-bytes` | `tools/float_rgb_bytes_probe.py` | Raw words vs native format-9 `LoadImageRaw` storage across sign/exponent classes, infinities, subnormals and random words; byte round trips; malformed/NaN controls |
| `float-rgb-transform` | `tools/float_rgb_transform_probe.py` | Copy, flips and quarter turns, including chains; copy independence |
| `float-rgb-crop` | `tools/float_rgb_crop_probe.py` | Extraction and crop; extracted-region independence |
| `float-rgb-resize`, `float-rgb-resize-filtered` | `tools/float_rgb_resize_probe.py` (`--filtered`) | Nearest and default filtered resizing, quantization boundaries, unsafe mappings |
| `float-rgb-canvas` | `tools/float_rgb_canvas_probe.py` | Canvas/POT movement, ignored fills, same-size no-ops |
| `float-rgb-color` | `tools/float_rgb_color_probe.py` | Color transforms, clamping, alpha matching, nonfinite/fractional parameter rejection |
| `float-rgb-formats` | `tools/float_rgb_formats_probe.py` | Direct targets 1..8 and grayscale at packed/grayscale rounding boundaries |
| `float-rgb-r32` | `tools/float_rgb_r32_probe.py` | Format 9 → R32 conversion and NaN controls; CPU/JS only, with an independent native-archive qualification |
| `formatted-float` | `tools/formatted_float_probe.py` | `Image.Formatted.to_float_rgb` for every source layout, channel level and alpha pattern, plus return chains |

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only float-rgb
```

## Known gaps

- Exact NaN payload interoperability; other float/half/compressed layouts.
- Mipmaps and unrestricted HDR-to-byte conversion.
- Fractional/native-invalid crop geometry.
- R32 conversion on numerical profiles that contract the luminance arithmetic,
  and GPU evidence for the R32 extension.
- Native pointer ABI and complete resource/platform/performance coverage.
