# BMP memory decoding and RGBA8 export

| API | Contract |
|---|---|
| `Surface.decode_bmp(bytes: +List<U32>)` | Returns `Result<&1, &1, Image.DecodeError, Surface>` with normalized RGBA8 pixels. |
| `Surface.to_bmp(surface) -> +List<U32>` | Consumes RGBA8 ownership and emits exact native V4/32-bit BMP bytes. |
| `Surface.write_bmp(surface, path)` | Consumes ownership and returns `IO(Result<&1, &1, U32 & String, Unit>)` through the established Base byte-write/close path. |

## Supported decoding profile

- A 12-byte CORE header supports 24-bit RGB. Its complete file/DIB header is
  26 bytes; width and height are unsigned 16-bit fields, bounded to 1..4096.
  Rows are bottom-up padded BGR and output alpha is opaque. Indexed CORE is not
  part of this profile.
- Width and absolute height are 1..4096; positive height is bottom-up and negative
  height is top-down. Output is always top-down row-major RGBA8.
- A 40-byte INFO header supports uncompressed (`BI_RGB`) 1/4/8-bit indexed and
  16/24/32-bit true-color pixels, plus 16/32-bit `BI_BITFIELDS`. INFO bitfields
  read three RGB masks immediately after the DIB; those 12 bytes count toward the
  effective header end. INFO rejects three identical RGB masks, matching native.
- A 56-byte header uses the INFO profiles but discards its four embedded mask
  words. Bitfield images then read three RGB masks **after** the DIB. Embedded
  alpha is ignored, including for uncompressed 16-bit input.
- A 108-byte V4 header supports the same `BI_RGB` depths and 16/32-bit
  `BI_BITFIELDS`, with four RGBA masks inside the header. Uncompressed V4 replaces
  its stored RGB masks with native defaults; 16-bit input retains its alpha mask.
- A 124-byte V5 header follows V4's masks/alpha rules and consumes four additional
  intent/profile words. Their values are ignored; profile offsets are not followed.
- Explicit RGB masks must be nonzero with 1..8 set bits. Alpha may be absent
  (opaque) or contain 1..8 set bits. Reordered, overlapping and noncontiguous masks
  follow native highest-bit/population alignment and bit replication. Holes are
  not compacted: masks `5`, `0a`, `50` decode word `005f` as `aaaaaaff`.
- Row padding is retained in the input stride and excluded from output pixels.
- Indexed palettes contain 1..256 BGR/reserved entries. Native palette count is
  `floor((pixel_offset - 14 - DIB_size)/4)`; `clrUsed` and palette alpha/reserved
  bytes are ignored. Output is opaque. Remaining offset bytes (0..3) are skipped
  once after the table. Packed indices are MSB-first; unused final-byte bits are
  discarded, and each input row is padded to a multiple of four bytes.
- `BI_RGB` 32-bit images whose alpha bytes are **all zero** become opaque, matching
  stb's reference behavior. If any alpha byte is nonzero, all input alpha bytes
  are preserved. Bitfields and V4/V5 `BI_RGB` 16-bit preserve all-zero explicit alpha.
- `BI_RGB` 16-bit samples use two little-endian bytes with RGB fields at shifts
  10, 5 and 0. Each five-bit value expands with `(value*33)>>2`; RGB ignores bit 15.
  INFO/56-byte output is opaque; V4/V5 use their alpha mask, or opaque alpha when absent.
  Native BMP bit replication differs from TGA's
  `value*255/31` integer scaling: channel value 4 becomes 33 in BMP and 32 in TGA.
- For true-color input, the pixel offset may lie 0..1024 bytes past the header end. The pinned
  reader skips this gap **twice** for true-color images, so the effective payload
  starts at `effective_header_end + 2*gap`, including INFO/56-byte extra mask words when
  present. Jonlib preserves this observed behavior.

All supplied byte values must be 0..255. Unsupported header layouts, bit depths,
planes, masks, compression or offsets return `InvalidImageHeader`. Unsupported
dimensions return `UnsupportedImageSize`; incomplete effective pixel data,
including row padding, returns `TruncatedImageData`. Invalid bytes return
`InvalidImageByte`. Header/payload validation precedes output allocation.
An index beyond the loaded palette returns `InvalidImageStream`; the native
reader's uninitialized palette reads are outside the supported profile.
File-size/reserved header fields do not override actual input availability.

Indexed CORE headers, original-format metadata
and the native decoder's permissive recovery of truncated input remain gaps.
Shared memory/file dispatch uses this profile through `Surface.decode_image`
and `Surface.load_image`; see [IMAGE-FILES.md](IMAGE-FILES.md).

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
The probe checks 87 native decode cases (9,979 pixels), 41 typed-error controls and
three complete exports (410 bytes) on CPU, JavaScript and forced Metal. CPU/JS
also write a real BMP file and compare it with the native export. Input construction
uses bounded literal chunks for the maximum-gap case, avoiding JavaScript stack
growth from a deeply nested generated list literal. Indexed cases cover INFO/V4,
all three depths, both orientations, partial-byte rows, padding, offset residuals,
ignored `clrUsed`/alpha, reduced/full palettes and a 4096-pixel row. RGB555 cases
cover each five-bit channel range, both high-bit states, INFO/V4, orientation,
odd row padding and a double-skipped offset gap. Bitfield cases cover every mask
population from 1..8, RGB565/ARGB1555/RGBA4444, reordered/overlapping/noncontiguous
masks, high bits, INFO's mask extension, and native V4 16-bit alpha behavior.
Missing/oversized RGB or alpha masks, INFO's equal-mask rejection and incomplete
mask headers are checked. The 56-byte/V5 cases cover indexed, byte-color, RGB555
and bitfield data, contradictory embedded masks, ignored profile words and
truncated/invalid effective headers. CORE cases cover short complete headers,
all row-padding widths, a 4096-pixel row, the maximum post-header gap and rejected
planes/depths/dimensions/offsets. Hashes and lane results are in
[evidence/bmp-core.json](evidence/bmp-core.json).

The codec is an altered Bend implementation of the pinned stb BMP paths; its MIT
notice is retained in [LICENSES/stb-image.txt](../LICENSES/stb-image.txt). Full
format/platform/resource/performance parity remains open.
