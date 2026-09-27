# TGA memory decoding and default RLE export

| API | Contract |
|---|---|
| `Surface.decode_tga(bytes: +List<U32>)` | Returns `Result<&1, &1, Image.DecodeError, Surface>` containing owned normalized RGBA8 pixels. |
| `Surface.to_tga(surface) -> +List<U32>` | Consumes RGBA8 and emits the pinned exporter's exact default RLE bytes. |
| `Surface.write_tga(surface, path)` | Consumes RGBA8 and returns `IO(Result<&1, &1, U32 & String, Unit>)` through Base byte-file writing and closure. |

## Decoding profile

- Non-paletted true-color 15/16/24/32-bit images, types 2 and 10 (raw and RLE).
- Non-paletted grayscale 8-bit and gray-alpha 16-bit images, types 3 and 11.
- Indexed images, types 1 and 9, with 8/16-bit indices and 1..65535 palette entries
  encoded at 8/15/16/24/32 bits. Palette 8-bit values are opaque grayscale;
  palette 15/16-bit values use opaque RGB555; 32-bit entries retain alpha.
- Dimensions 1..4096; ID fields up to 255 bytes are skipped.
- Descriptor bit 5 selects top-down or bottom-up storage; output is row-major
  top-down. Origin coordinates, horizontal-origin and other descriptor bits are
  ignored by the pinned reader and this profile.
- RLE packets may cross rows. Raw/repeated packet counts are 1..128; counts
  extending beyond the remaining image are rejected as `InvalidImageStream`.
- Gray-alpha and 32-bit true-color retain zero alpha, unlike uncompressed BMP's
  alpha repair rule.
- Both 15-bit and 16-bit true-color consume two little-endian bytes per pixel.
  RGB fields are the five bits at shifts 10, 5 and 0, expanded with integer
  `channel*255/31`. The native decoder ignores bit 15 and the descriptor's alpha
  count for these packed formats: output alpha is always 255. This is distinct
  from 16-bit grayscale's two independent gray/alpha bytes.
- The pinned palette-start field skips that many **bytes after the image ID**,
  rather than shifting logical indices. Indices at or beyond the palette count
  select entry zero. Both behaviors are reproduced from actual native execution.

Every supplied value must be a byte, otherwise decoding returns `InvalidImageByte`.
Unsupported fields or incomplete headers return `InvalidImageHeader`; dimensions
outside the profile return `UnsupportedImageSize`. Missing ID/pixel/packet data
returns `TruncatedImageData`. Valid trailing bytes are ignored after the image.

Other remaining variants, original-format metadata and native
permissive malformed-data recovery remain gaps. Shared memory/file dispatch is
documented in [IMAGE-FILES.md](IMAGE-FILES.md).

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
The shared bitmap comparison gate checks 48 native images (1,123 pixels), 23 typed
errors and 11 complete exports (3,447 bytes) on CPU, JavaScript and forced Metal.
CPU/JS additionally compare a real file export. Packed cases cover all five-bit
channel values, both high-bit states, both orientations and mixed raw/RLE packets;
existing gray-alpha and byte-color inputs remain in the same gate. Indexed cases
cover every palette encoding and index width, raw/RLE packets, nonzero palette
skips, out-of-range recovery, transparent entries and a 257-entry palette.
Empty/unsupported/truncated palettes and indices are rejected. Shared memory
and file dispatch exercise packed and indexed streams. See
[evidence/tga-palettes.json](evidence/tga-palettes.json) for hashes and lane outcomes.

The altered stb implementation retains the selected MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt). Full platform/resource/
performance parity remains open.
