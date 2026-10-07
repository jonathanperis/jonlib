# Float and half-float formats

Formats 9..13 hold float samples. Their storage keeps the stored sample bits,
so every backend (including JavaScript, which canonicalizes NaN payloads in
float arithmetic) returns exactly what was stored:

| Format | Name | Storage | Owner domain |
|---|---|---|---|
| 8 | R32 | `Words`, F32 bits | finite `[0,1]`, both zero signs |
| 9 | R32G32B32 | `Quads`, F32 bits in `a..c` | no NaN |
| 10 | R32G32B32A32 | `Quads`, F32 bits in `a..d` | no NaN |
| 11 | R16 | `Words`, half-float bits | finite `[0,1]`, both zero signs |
| 12 | R16G16B16 | `Quads`, half-float bits in `a..c` | any half |
| 13 | R16G16B16A16 | `Quads`, half-float bits in `a..d` | any half |

Format 9 is described in detail in [RGB float images](FLOAT-RGB.md); R32 in
[R32.md](R32.md). Formats 10..13 follow the same raylib 6.0 rules:

- **Half floats** use raylib's own `HalfToFloat` and `FloatToHalf` bit
  arithmetic (`src/formats.bend`), checked against the C code on all 65536
  halves and 200000 floats. `HalfToFloat` maps exponent-31 halves (raylib's
  infinities and NaNs) to large finite floats, so half samples are never NaN;
  `FloatToHalf` saturates to `0x7fff`.
- **`ImageFormat`** goes through `LoadImageDataNormalized`: R16 and
  R32G32B32A32/R16G16B16A16 read their channels (R16 as red, alpha 1), and
  writes use `FloatToHalf` of the channel, R16 of the F32 luminance
  `(r*0.299 + g*0.587) + b*0.114`. Float sources must be in `[0,1]`.
- **Color operations** (`LoadImageColors`, `GetImageColor`, `GetPixelColor`)
  cast `v*255` to a byte: R16 fills red (`GetPixelColor` replicates it), the
  wide formats map each channel, formats without alpha read 255. Samples
  outside `[0,1]` return `OutOfDomain` (or `None`) with the owner.
- **Drawing** stores `channel/255` as F32 or half floats (`ImageDrawPixel`);
  `SetPixelColor` does not write formats 8..13, so `ImageDraw` only changes
  them through an unblended same-format copy, and `resize_canvas` fills them
  with zero.
- **`alpha_clear`** compares the float alpha of R32G32B32A32 and R16G16B16A16
  with the threshold; **`rotate_degrees`** blends every stored byte, refusing
  R16 results outside `[0,1]` and NaN F32 results.
- **Raw bytes** (`from_bytes`, `load_raw`, `write_raw`, `to_code`) are 16, 2,
  6 and 8 bytes per pixel for formats 10..13; PNG memory export reads the first
  four bytes per pixel of formats 9, 10, 12 and 13 as RGBA, while R16 (two
  bytes per pixel) is `UnsupportedFormat`, as the native read would overrun.

## How it is verified

`tools/surface_format_probe.py` (gate `surface-format`) runs every operation,
and `ImageFormat` to every target, on formats 1..13 against raylib, comparing
complete stored bytes; `tools/mipmap_probe.py` (gate `mipmap`) compares mipmap
chains in formats 1..13.

## Known gaps

Compressed formats (14+), samples outside the owner/conversion domains and
complete target/performance coverage.
