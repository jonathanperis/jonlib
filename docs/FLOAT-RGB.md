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

## Large owned exports

Surface colors, FloatRGB entries and packed/formatted image exports use a shared
tail-recursive logical-prefix operation. This replaces pinned Base `List.take`
at those large-image sites, whose generated JavaScript recursed once per pixel.
The observed 33,024-pixel stack overflow is covered without shrinking the input
or changing the compiler/runtime. Output lengths, order and ownership are retained.

## Verification

```sh
python3 tools/float_rgb_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares actual native `ImageFormat` results for all 256 byte values,
769 float-boundary pixels and 33,024 in-range HDR pixels on CPU, JavaScript and
forced Metal. Float normalization and large vector exports use exact F32 words;
RGBA conversion uses complete bytes. Seven rejection controls verify preserved
owners across all three components, including negative subnormal, out-of-range,
infinite and NaN samples. Native round trips produce opaque alpha.

All 109 byte/integer format cases, 42 complete packed-dither outputs and raw-file
load/export/closure checks retain their existing results after prefix extraction
changes. See [evidence/float-rgb.json](evidence/float-rgb.json).

Other float/half/compressed formats, mipmaps, unrestricted HDR-to-byte conversion
and complete resource/platform/performance coverage remain gaps.
