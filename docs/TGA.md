# TGA decoding and default RLE export

Jonlib reproduces the TGA paths of raylib 6.0's pinned stb_image /
stb_image_write: a decoder that keeps raylib's native output format and the
exporter's exact default RLE bytes.

| API | Contract |
|---|---|
| `Surface.decode_tga(bytes: +List<U32>)` | `Result<&1, &1, Surface.Error, Surface>` with owned native format-1/2/4/7 pixels and an implicit single mip level. |
| `Surface.load_tga(path: String)` | `IO(Result<&1, &1, Surface.IOError, Surface>)`; explicit TGA selection, inclusive 1 MiB encoded-file cap, same domain as `decode_tga`. See [IMAGE-FILES.md](IMAGE-FILES.md#format-preserving-tga-file-loading). |
| `Surface.to_tga(surface)` | `Result<&1, &1, Surface & Surface.Error, +List<U32>>` with the pinned exporter's exact default RLE bytes; see [IMAGE-EXPORT.md](IMAGE-EXPORT.md). |
| `Surface.write_tga(surface, path)` | Consumes the owner and returns `IO(Result<&1, &1, Surface.IOError, Unit>)` through Base byte-file writing and closure. |

Checked formats 1..8 have separate consuming `Surface.to_tga/write_tga`
entry points that preserve native channel routing and packed/R32 expansion; see
[IMAGE-EXPORT.md](IMAGE-EXPORT.md). Shared suffix/content dispatch through
`Surface.decode_image`/`Surface.load_image` is in [IMAGE-FILES.md](IMAGE-FILES.md).

## Decoding profile

- Non-paletted types 2/3/10/11 accept depths 8/15/16/24/32 with the
  depth-selection rules below. Types 10/11 are RLE.
- Indexed types 1 and 9 accept 8/16-bit indices and 1..65535 palette entries
  encoded at 8/15/16/24/32 bits. 8-bit entries are opaque grayscale; 15/16-bit
  entries are opaque RGB555; 32-bit entries retain alpha.
- Dimensions 1..4096. ID fields up to 255 bytes are skipped.
- Descriptor bit 5 selects top-down or bottom-up storage; output is row-major
  top-down. Origin coordinates, the horizontal-origin bit and other descriptor
  bits are ignored by the pinned reader and by this profile. Direct images
  ignore unused color-map header fields.
- RLE packets may cross rows. Raw/repeat packet counts are 1..128; a count
  extending beyond the remaining image is rejected as `InvalidImageStream`.
- Gray-alpha and 32-bit true-color retain zero alpha, unlike uncompressed BMP's
  alpha repair rule.
- All 15-bit samples and type-2/10 16-bit samples consume two little-endian
  bytes per pixel. RGB fields are the five bits at shifts 10, 5 and 0, expanded
  with integer `channel*255/31`. The native decoder ignores bit 15 and the
  descriptor's alpha count for these packed formats: output alpha is always 255.
  This is distinct from type-3/11 16-bit grayscale's two independent gray/alpha
  bytes.
- The palette-start field skips that many **bytes after the image ID**, rather
  than shifting logical indices. Indices at or beyond the palette count select
  entry zero. Both behaviors are reproduced from actual native execution.

| Depth | Types 2/10 | Types 3/11 |
|---|---|---|
| 8 | Opaque grayscale | Opaque grayscale |
| 15 | Opaque RGB555 | Opaque RGB555 |
| 16 | Opaque RGB555 | Gray + alpha bytes |
| 24 | Opaque BGR | Opaque BGR |
| 32 | BGRA, alpha retained | BGRA, alpha retained |

The nominal true-color/grayscale type changes only the 16-bit interpretation;
these cross-type combinations follow actual pinned native loading.

### Errors

Every supplied value, including ignored tails, is checked as a byte before the
header, so `InvalidImageByte` has precedence. Incomplete or unsupported headers
return `InvalidImageHeader`; dimensions outside 1..4096 return
`UnsupportedImageSize`; missing ID/palette/pixel/packet bytes return
`TruncatedImageData`; packet counts exceeding the remaining image return
`InvalidImageStream`. Header validity precedes size, which precedes palette
loading and pixel allocation. Valid trailing bytes after the image are ignored.
These are checked adaptations: native permissive malformed-data recovery is
outside the profile, and checked-invalid inputs are not claimed as native
rejections.

## Format-preserving TGA memory loading

`Surface.decode_tga(bytes)` keeps the checked byte/header/size/stream
contract above while preserving the actual pinned `LoadImageFromMemory` output.
raylib requests stb channels zero, maps output channels 1/2/3/4 to formats
1/2/4/7 and supplies one mip level. Output channels are independent of the
input sample/index byte width.

| Input | Native output |
|---|---|
| Direct 8-bit, either nominal type | Grayscale (1), G |
| Direct 16-bit type 3/11 | Gray-alpha (2), G,A |
| Direct 15-bit or type-2/10 16-bit | Expanded RGB888 (4), R,G,B |
| Direct 24-bit, either nominal type | RGB888 (4), R,G,B |
| Direct 32-bit, either nominal type | RGBA8888 (7), R,G,B,A |
| Indexed, palette depth 8 | Grayscale (1), independent of index width |
| Indexed, palette depth 15/16/24 | Expanded RGB888 (4), independent of index width |
| Indexed, palette depth 32 | RGBA8888 (7), independent of index width |

The adapter extracts gray R and gray-alpha R,A or packs RGB/RGBA in native byte
order with integer operations; no luminance round trip is introduced. RGB555
keeps integer `value*255/31` expansion, ignores bit 15 and produces expanded
RGB888, not a packed pixel format. Descriptor alpha-count bits do not change the
channel count or repair zero alpha. Palette-start skipping, entry-zero fallback,
orientation, ignored horizontal-origin bits, raw/RLE stepping and valid trailing
data follow the decoder above.

Ownership: the immutable input list can be reused; success returns one affine
pixel owner. Point reads return that owner alongside their `Maybe` result,
including out-of-bounds reads. Byte export and the Surface bridge consume it.
Raw export contains exactly `width*height*channels` row-major bytes, excluding
backing-array padding. Logical grayscale words have zero high 24 bits,
gray-alpha zero high 16 bits and RGB888 a zero high byte. Failure returns only
the typed error, never a partial image.

File loading (`Surface.load_tga`) adds explicit, suffix-independent TGA
selection, the inclusive 1,048,576-byte raster-file cap and the shared
close-before-decode IO model; see
[IMAGE-FILES.md](IMAGE-FILES.md#format-preserving-tga-file-loading).

## Default RLE export

`Surface.to_tga` emits a type-10 header, 32-bit BGRA samples, eight alpha bits
and bottom-up rows. It reproduces native default RLE packet selection,
restarting at each row and capping each packet at 128 pixels. The native
raw-packet scan compares the next pixel with the one **two positions earlier**
and shortens the packet when those match; conventional adjacent-pixel run
detection would change the encoded bytes even though decoded pixels are
identical. `Surface.write_tga` selects TGA independently of the file extension.

## How it is verified

All gates compare exact output against pinned native raylib on the CPU-1,
CPU-2 and JavaScript lanes (see [VERIFICATION.md](VERIFICATION.md)).

- **RGBA8 decode and export** (`tools/tga_probe.py`, gate `tga`, using the shared
  bitmap harness in `tools/bmp_probe.py`): every accepted stream is decoded by
  native `LoadImageFromMemory(".tga")` converted to RGBA8 and compared pixel for
  pixel with `Surface.decode_tga`. Fixtures cover raw/RLE gray, gray-alpha,
  BGR and BGRA in both orientations, cross-row runs, 128/129/130-pixel packet
  limits, ignored descriptor bits, all five-bit RGB555 values with both
  high-bit states, every cross-type depth, every palette encoding and index
  width, palette skips, out-of-range indices and a 257-entry palette.
  Malformed controls (empty, short header/pixels/palette, bad type/depth,
  zero/oversized axes, packet overruns, non-byte values) check the typed error
  only. `Surface.to_tga` output is compared byte for byte with native
  `ExportImage(..., ".tga")` files (ABA/ABBC patterns, 128/129/130-pixel
  boundaries, cross-row runs, seeded mixed packets), and one `Surface.write_tga`
  file with the native file. The optional `--gpu` lane adds forced GPU.
- **Format-preserving memory decode** (`tools/tga_format_probe.py`, gate
  `tga-format`, driver `tools/codec_formats.py`): a native build with TGA
  explicitly enabled is first qualified (little-endian storage, distinct direct
  16-bit routing, both palette index widths, formats 1/2/4/7). For each
  accepted fixture, native width/height/mipmaps/format and every raw byte are
  recorded before a separate RGBA8 normalization, including the `.TGA` alias.
  Jonlib's raw export, factory and retained-owner point reads are compared with
  the raw bytes; the Surface bridge, `Surface.decode_tga` and (for selected
  cases) generic `Surface.decode_image` dispatch with the normalized bytes. An independent safety parser admits only complete, well-framed
  streams to native; it never computes expected pixels. Checked-invalid
  controls run only through Jonlib and check exact typed errors.
- **Format-preserving file loading** (`tools/tga_file_probe.py`, gate
  `tga-file`, driver `tools/codec_files.py`): see
  [IMAGE-FILES.md](IMAGE-FILES.md#how-it-is-verified).

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only tga-format
```

## Known gaps

- Native permissive malformed-stream recovery, nondefault stb flags and
  dimensions above 4096.
- Exporter flags other than the default RLE path; `Surface.to_tga` accepts only
  RGBA8 (wider formats go through `Surface.to_tga`).
- Native pointer/allocation ABI, OOM behavior, maximum-area resources and
  performance. The file cap bounds encoded input only; RLE input can describe
  far more pixel storage.

- GPU evidence is local only (`--gpu` on the `tga` probe); the native-format memory
  and file gates run on CPU and JavaScript. Windows, browser and big-endian
  hosts are unverified.
- In the API ledger this work is part of the partial
  `raylib:function:LoadImageFromMemory` and `raylib:function:LoadImage` entries;
  neither is complete.

The adapted stb code (`src/tga.bend`) retains the MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt).
