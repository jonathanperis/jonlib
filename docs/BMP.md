# BMP memory decoding and RGBA8 export

| API | Contract |
|---|---|
| `Surface.decode_bmp(bytes: +List<U32>)` | Returns `Result<&1, &1, Image.DecodeError, Surface>` with normalized RGBA8 pixels. |
| `Surface.to_bmp(surface) -> +List<U32>` | Consumes RGBA8 ownership and emits exact native V4/32-bit BMP bytes. |
| `Surface.write_bmp(surface, path)` | Consumes ownership and returns `IO(Result<&1, &1, U32 & String, Unit>)` through the established Base byte-write/close path. |

## Supported decoding profile

- Width and absolute height are 1..4096; positive height is bottom-up and negative
  height is top-down. Output is always top-down row-major RGBA8.
- A 40-byte INFO header supports uncompressed (`BI_RGB`) 24/32-bit pixels.
- A 108-byte V4 header supports 24-bit `BI_RGB`, or 32-bit `BI_RGB`/`BI_BITFIELDS`.
  Explicit bitfields must be canonical RGBA masks: `00ff0000`, `0000ff00`,
  `000000ff`, `ff000000`. Uncompressed V4 input ignores its stored masks.
- Row padding is retained in the input stride and excluded from output pixels.
- `BI_RGB` 32-bit images whose alpha bytes are **all zero** become opaque, matching
  stb's reference behavior. If any alpha byte is nonzero, all input alpha bytes
  are preserved. Explicit V4 bitfields preserve all-zero alpha too.
- The declared pixel offset may lie 0..1024 bytes past the header end. The pinned
  reader skips this gap **twice** for true-color images, so the effective payload
  starts at `header_end + 2*gap`. Jonlib preserves this observed behavior.

All supplied byte values must be 0..255. Unsupported header layouts, bit depths,
planes, masks, compression or offsets return `InvalidImageHeader`. Unsupported
dimensions return `UnsupportedImageSize`; incomplete effective pixel data,
including row padding, returns `TruncatedImageData`. Invalid bytes return
`InvalidImageByte`. Header/payload validation precedes output allocation.
File-size/reserved header fields do not override actual input availability.

Palette/16-bit images, other headers/masks/compression, original-format metadata
and the native decoder's permissive recovery of truncated input remain gaps.
No generic extension dispatch or BMP-specific file loader is added by this profile.

## Export

RGBA8 export follows the actual native `ExportImage(..., ".bmp")` path: a
122-byte file/V4 header, canonical masks, bottom-up BGRA rows and no row padding
for 32-bit pixels. All header fields and pixels are compared byte-for-byte.
The explicit BMP writer selects the format independently of the path extension.
Other source-format export profiles and native callbacks/allocation ABI remain gaps.

## Verification

```sh
python3 tools/bmp_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The probe checks 24 native decode cases (131 pixels), 17 typed-error controls and
three complete exports (410 bytes) on CPU, JavaScript and forced Metal. CPU/JS
also write a real BMP file and compare it with the native export. Input construction
uses bounded literal chunks for the maximum-gap case, avoiding JavaScript stack
growth from a deeply nested generated list literal.

The codec is an altered Bend implementation of the pinned stb BMP paths; its MIT
notice is retained in [LICENSES/stb-image.txt](../LICENSES/stb-image.txt). Full
format/platform/resource/performance parity remains open.
