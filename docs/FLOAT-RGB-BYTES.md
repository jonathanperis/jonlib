# RGB float raw-byte interoperability

`Image.FloatRGB.from_bytes(width, height, bytes)` returns
`Maybe<Image.FloatRGB>`. It checks dimensions 1..4096 and exactly
`width*height*12` byte values, then reads three little-endian F32 words per pixel.

`Image.FloatRGB.to_bytes(image)` returns
`Result<&1, &1, Image.FloatRGB, +List<U32>>`. Success consumes the image and emits
exact format-9 RGB words without storage padding. Failure returns the original
owner with every existing sample retained.

Both operations support every **non-NaN** F32 bit pattern: positive/negative
finite values, signed zero, subnormals and infinities. Import rejects NaN words
before constructing float values. Export rejects NaN samples while retaining the
source owner. The pinned JavaScript representation canonicalizes NaN payloads and
signs; exact raw NaN-word interoperability therefore remains outside this profile.

These byte operations perform no normalization, gamma adjustment or tone mapping.
Use the separate [RGBA8 conversion API](FLOAT-RGB.md) for native normalized image
conversion and the [HDR decoder](HDR.md) for Radiance files. The existing
`Image.Formatted` byte/integer factory retains its own format-1..7 domain.

## Verification

```sh
python3 tools/float_rgb_bytes_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares 1,539 pixels against actual native format-9 `LoadImageRaw`
storage across sign/exponent classes, infinities, subnormals and deterministic
random words. It checks both the imported float words and complete byte round
trips on CPU/JavaScript/forced Metal. Native `ExportImage(.raw)` supplies 3,072
additional bytes from normalized RGB input, where its incidental 8-bit color
conversion is defined. Eight malformed/NaN controls and a rejected-owner check
pass. The existing float/RGBA8 conversion gate is also retained after sharing its
validation traversal. See
[evidence/float-rgb-bytes.json](evidence/float-rgb-bytes.json).

Raw float file loading/writing is documented in [RAW-FILES.md](RAW-FILES.md#rgb-float-files).
NaN payload interoperability, other float/half layouts,
native pointer ABI and complete resource/platform/performance remain gaps.
