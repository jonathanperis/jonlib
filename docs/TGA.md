# TGA memory decoding and default RLE export

| API | Contract |
|---|---|
| `Surface.decode_tga(bytes: +List<U32>)` | Returns `Result<&1, &1, Image.DecodeError, Surface>` containing owned normalized RGBA8 pixels. |
| `Surface.to_tga(surface) -> +List<U32>` | Consumes RGBA8 and emits the pinned exporter's exact default RLE bytes. |
| `Surface.write_tga(surface, path)` | Consumes RGBA8 and returns `IO(Result<&1, &1, U32 & String, Unit>)` through Base byte-file writing and closure. |

## Decoding profile

- Non-paletted true-color 24/32-bit images, types 2 and 10 (raw and RLE).
- Non-paletted grayscale 8-bit and gray-alpha 16-bit images, types 3 and 11.
- Dimensions 1..4096; ID fields up to 255 bytes are skipped.
- Descriptor bit 5 selects top-down or bottom-up storage; output is row-major
  top-down. Origin coordinates, horizontal-origin and other descriptor bits are
  ignored by the pinned reader and this profile.
- RLE packets may cross rows. Raw/repeated packet counts are 1..128; counts
  extending beyond the remaining image are rejected as `InvalidImageStream`.
- All-zero alpha remains zero, unlike uncompressed BMP's alpha repair rule.

Every supplied value must be a byte, otherwise decoding returns `InvalidImageByte`.
Unsupported fields or incomplete headers return `InvalidImageHeader`; dimensions
outside the profile return `UnsupportedImageSize`. Missing ID/pixel/packet data
returns `TruncatedImageData`. Valid trailing bytes are ignored after the image.

Paletted and 15/16-bit true-color variants, original-format metadata, native
permissive malformed-data recovery and generic format dispatch remain gaps.

## Exact export packet selection

The exporter emits a type-10 header, 32-bit BGRA samples, eight alpha bits and
bottom-up rows. It preserves native default RLE selection, restarting at each
row and capping each packet at 128 pixels. The native raw-packet scan compares
the next pixel with the one **two positions earlier**, and shortens the packet
when those match. Conventional adjacent-pixel run detection would change the
encoded bytes even when decoded pixels remain identical.

The output is compared with real `ExportImage(..., ".tga")` files, including
ABA/ABBC patterns, 128/129/130-pixel boundaries, cross-row repeated colors and
seeded mixed packets. Nondefault exporter flags and other source formats remain gaps.
The dedicated writer selects TGA independently of the file extension.

## Verification

```sh
python3 tools/tga_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The shared bitmap comparison gate checks 19 native images (358 pixels), 14 typed
errors and 11 complete exports (3,447 bytes) on CPU, JavaScript and forced Metal.
CPU/JS additionally compare a real file export. BMP's existing fixtures run
through the same gate and retain their exact results.

The altered stb implementation retains the selected MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt). Full platform/resource/
performance parity remains open.
