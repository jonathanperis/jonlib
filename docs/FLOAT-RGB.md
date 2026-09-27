# Owned RGB float and RGBA8 conversion

| API | Contract |
|---|---|
| `Surface.to_float_rgb(surface) -> Image.FloatRGB` | Consumes RGBA8, normalizes each RGB byte with native F32 `byte/255`, and discards alpha as format 9 does. |
| `Image.FloatRGB.to_surface(image)` | Returns `Result<&1, &1, Image.FloatRGB, Surface>`. Finite RGB samples in `[0,1]` become opaque RGBA8 through native F32 `component*255` truncation. Unsupported samples return the original owner in `Fail`. |

Both operations retain logical dimensions and row-major order. This is the
native `ImageFormat` format-7/format-9 bridge; no gamma adjustment, clamping or
tone mapping is applied. Signed zero and positive subnormals are accepted.
Negative subnormals, values above one, infinities and NaNs are rejected before
conversion. Domain validation uses float-bit ordering, so a GPU's denormal
arithmetic mode cannot turn a negative subnormal into an accepted zero.

Create valid dimensions/storage through the existing Surface/HDR APIs; manually
inconsistent owner records are outside the contract. Failed conversion preserves
every original sample bit and the complete owner. HDR values outside `[0,1]`
remain available through [FloatRGB entries](HDR.md) after rejection.

## Copy and lossless orientation

`Image.FloatRGB.copy(image)` returns `(original, copy)` with independent owned
storage. `flip_horizontal`, `flip_vertical`, `rotate_cw` and `rotate_ccw` consume
the float image and preserve every supported sample word. Flips keep dimensions;
quarter-turns swap them. These operations move RGB vectors without normalization
or color conversion, matching native format-9 byte movement.

Logical dimensions/storage must satisfy the existing image-owner invariant.
Non-NaN float words, including signed zero, subnormals, infinities and values
outside `[0,1]`, are supported. See
[evidence/float-rgb-transforms.json](evidence/float-rgb-transforms.json).

## Rectangular extraction and crop

`Image.FloatRGB.extract(image, rectangle)` returns `(source, Maybe<region>)`,
retaining the source and creating an independent region for a positive integral
in-bounds rectangle. Rejected rectangles return the source with `None`.

`Image.FloatRGB.crop(image, rectangle)` returns
`Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>`. Integral crops
are clipped using the existing Surface rules. Positive clipped regions preserve
exact sample words; an origin strictly beyond the image returns the unchanged
owner, matching native behavior. Other unsupported rectangles retain the owner
with `InvalidRectangle`. Fractional/native-invalid geometry remains outside this
profile. See [evidence/float-rgb-crop.json](evidence/float-rgb-crop.json).

## Native nearest-neighbor resizing

`Image.FloatRGB.resize_nn(image, width, height)` returns
`Result<&1, &1, Image.FloatRGB, Image.FloatRGB>`. Destination dimensions must be
1..4096; source samples must be finite `[0,1]`. Unsafe fixed-point mappings and
unsupported inputs return the original unquantized owner.

Native format-9 nearest resizing first converts to RGBA8, uses the plus-one
16.16 mapping, then normalizes RGB bytes back to floats. **Even unchanged
dimensions quantize samples**: `0.5` becomes `127/255`. Jonlib preserves that
sequence rather than treating the operation as a lossless float remap. Original
float storage is retained through fallible stages without cloning it for recovery.
See [evidence/float-rgb-nearest.json](evidence/float-rgb-nearest.json).

`Image.FloatRGB.resize(image, width, height)` has the same Result/owner contract
and finite `[0,1]` input domain, using native default filtered resizing instead
of nearest mapping. The format-9 reference path also goes through RGBA8:
truncate samples, apply four-channel Catmull-Rom/Mitchell filtering, then normalize
the resulting RGB bytes. Same-size calls still quantize. Both methods share the
source-retaining conversion dispatch. See
[evidence/float-rgb-filtered.json](evidence/float-rgb-filtered.json).

## Canvas resizing and POT growth

`Image.FloatRGB.resize_canvas(image, width, height, x, y, fill)` and `to_pot(image, fill)`
return `Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>`. Dimensions
are 1..4096; canvas offsets follow the existing bounded integral Surface profile,
with positive overlap required when dimensions change. Invalid requests retain
their original owners.

Moved non-NaN sample words remain exact. Native format 9 ignores the requested
fill color because `SetPixelColor` has no float case; exposed pixels therefore
remain positive RGB zero from allocation. Same-size requests preserve the source
for in-profile offsets. POT uses the established next-power-of-two calculation.
See [evidence/float-rgb-canvas.json](evidence/float-rgb-canvas.json).

## Native color transforms

`Image.FloatRGB.color_tint`, `color_invert`, `color_contrast`, `color_brightness`
and `color_replace` return `Result<&1, &1, Image.FloatRGB, Image.FloatRGB>`.
They retain native format-9 behavior: truncate finite `[0,1]` samples to RGBA8,
apply the existing byte color operation, then normalize RGB back to floats.
Nominal no-ops still quantize. Unsupported source samples/parameters return the
original owner.

Contrast must be finite and is clamped to -100..100. Brightness must be finite
integral and is clamped to -255..255; native negative channel underflow becomes
one rather than zero. Tint and replacement alpha are discarded when converting
back to RGB. Replacement still matches all four RGBA bytes, with input alpha 255.
See [evidence/float-rgb-color.json](evidence/float-rgb-color.json).

## Direct byte/integer formats and grayscale

`Image.FloatRGB.to_formatted(image, target)` returns
`Result<&1, &1, Image.FloatRGB, Image.Formatted>` for targets 1..7. It uses native
normalized F32 channels directly with alpha one; it does not first truncate to
RGBA8. `Image.FloatRGB.color_grayscale(image)` selects target 1, preserving the
native change to grayscale storage. Unsupported targets or samples outside
finite `[0,1]` return the original float owner.

Packed channels round the already-rounded F32 product as native `round` does.
Adding one half in F32 first can round twice: words `0x3d088888` (limit 15) and
`0x3c020820` (limit 63) must produce zero, while add-half/floor produces one.
Grayscale retains direct uncontracted F32 luminance order and byte truncation.
See [evidence/float-rgb-formats.json](evidence/float-rgb-formats.json).

`Image.Formatted.to_float_rgb(image)` consumes any checked format-1..7 owner and
returns native format-9 RGB float storage. Grayscale replicates into RGB; alpha is
discarded. Packed channels use the native reciprocal-multiply expansion directly,
preserving float bits that an intermediate RGBA8 conversion would lose. See
[evidence/formatted-float.json](evidence/formatted-float.json).

## Large owned exports

Native grayscale channel extraction retains the float source and follows RGB
selector redirection; see [IMAGE-CHANNELS.md](IMAGE-CHANNELS.md).
Native bulk/point color observations and their owner/domain contracts are in
[IMAGE-COLORS.md](IMAGE-COLORS.md).

Surface colors, FloatRGB entries and packed/formatted image exports use a shared
tail-recursive logical-prefix operation. This replaces pinned Base `List.take`
at those large-image sites, whose generated JavaScript recursed once per pixel.
The observed 33,024-pixel stack overflow is covered without shrinking the input
or changing the compiler/runtime. Output lengths, order and ownership are retained.

## Verification

```sh
python3 tools/float_rgb_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/float_rgb_transform_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/float_rgb_crop_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/float_rgb_resize_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/float_rgb_resize_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --filtered --gpu
python3 tools/float_rgb_canvas_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/float_rgb_color_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/float_rgb_formats_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/formatted_float_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares actual native `ImageFormat` results for all 256 byte values,
769 float-boundary pixels and 33,024 in-range HDR pixels on CPU, JavaScript and
forced Metal. Float normalization and large vector exports use exact F32 words;
RGBA conversion uses complete bytes. Seven rejection controls verify preserved
owners across all three components, including negative subnormal, out-of-range,
infinite and NaN samples. Native round trips produce opaque alpha.
Exact non-NaN raw-word import/export is documented in
[FLOAT-RGB-BYTES.md](FLOAT-RGB-BYTES.md).

All 109 byte/integer format cases, 42 complete packed-dither outputs and raw-file
load/export/closure checks retain their existing results after prefix extraction
changes. See [evidence/float-rgb.json](evidence/float-rgb.json).

Other float/half/compressed formats, mipmaps, unrestricted HDR-to-byte conversion
and complete resource/platform/performance coverage remain gaps.

The orientation gate compares 43 native cases / 14,953 pixels on CPU/JS/Metal,
including rectangular/thin shapes, exact non-NaN words, repeated quarter-turns
and mixed operation chains. An independent mutation check verifies cloned owners.
The rectangle gate adds 15 native cases / 167 pixels, eight complete retained-
owner checks and independent extracted-region mutation on CPU/JS/Metal.
The nearest gate compares 24 native cases / 1,854 pixels and five retained owners,
covering up/down/same-size/thin inputs, quantization boundaries and unsafe mappings.
The filtered gate compares 26 native cases / 2,878 pixels and three retained
owners on CPU/JS/Metal. The existing Surface filter gate retains 529 images /
46,474 pixels, 2,601 kernels and 6,470 normalization coefficient bits.
The canvas/POT gate compares 18 native cases / 4,277 pixels and six retained
owners on CPU/JS/Metal, including ignored fills and same-size offset no-ops.
The color gate compares 44 native cases / 17,050 pixels and six retained-owner
controls on CPU/JS/Metal, including clamping, alpha matching, chains and nonfinite/
fractional parameter rejection.
Direct formats add nine native cases / 5,758 pixels, 530 packed-boundary values,
1,024 targeted grayscale-boundary pixels and four retained owners on CPU/JS/Metal.
The 109 byte/integer format regressions remain passing after correcting shared rounding.
The reverse bridge compares seven source formats / 1,792 pixels and fourteen
native float/return-chain results on CPU/JS/Metal, covering every channel level
and alpha pattern in the source layouts.
