# Binary PGM/PPM decoding

Jonlib reproduces the binary PNM reader of raylib 6.0's pinned stb_image for
P5 grayscale and P6 RGB input.

| API | Contract |
|---|---|
| `Surface.decode_pnm(bytes: +List<U32>)` | `Result<&1, &1, Surface.Error, Surface>` with native grayscale (1) or RGB888 (4) pixels and an implicit single mip level. |
| `Surface.load_pnm(path: String)` | `IO(Result<&1, &1, Surface.IOError, Surface>)`; explicit P5/P6 selection independent of the suffix, inclusive 1 MiB encoded-file cap, same domain as `decode_pnm`. See [IMAGE-FILES.md](IMAGE-FILES.md#format-preserving-pnm-file-loading). |

Shared suffix/content dispatch through `Surface.decode_image`/`Surface.load_image`
is in [IMAGE-FILES.md](IMAGE-FILES.md). The separate `Surface.to_ppm` exporter
writes inspectable P3 text; the native PNM loader does not accept ASCII P1..P3
or binary PBM P4, and neither does Jonlib.

## Decoding profile

Dimensions are 1..4096 and the declared maximum sample value (`maxval`) is
1..65535. Decimal header values are bounded before arithmetic. Every input
value must be a byte 0..255, including bytes in ignored tails and discarded
halves of wide samples.

- Whitespace and `#` comments are accepted between numeric header fields.
  Comments end at CR or LF; space, HT, LF, VT, FF and CR are whitespace.
- After `maxval`, exactly **one whitespace byte** is consumed. Following bytes
  belong to the raster even if they are whitespace or `#`; a CRLF separator
  therefore leaves LF (`10`) as the first raster byte, as in the pinned reader.
- Samples are kept **without rescaling or clamping**, including when `maxval` is
  below 255 or a sample exceeds it. Surface P5 samples are replicated into RGB,
  and all Surface alpha is 255.
- `maxval` 1..255 selects one byte per sample; 256..65535 selects two. In the
  pinned **little-endian native profile**, two-byte samples keep their **second
  stored byte**: stb copies the PNM bytes into host U16 values without swapping
  and later shifts right by eight during 8-bit conversion, so stored bytes
  `12 34` produce `34`, not `12`. Jonlib deliberately reproduces this raylib
  behavior instead of standard big-endian PNM interpretation.
- Both public results hold **8-bit samples**, even for 16-bit input: the pinned
  `LoadImageFromMemory` route calls stb's 8-bit loader, so neither source sample
  depth nor `maxval` metadata is preserved.
- Payload magic determines channels: P5 under a `.ppm` token is still grayscale
  and P6 under `.pgm` is still RGB.
- Complete row-major sample data is required; valid trailing bytes are ignored.

### Errors

All bytes are validated before header parsing, so `InvalidImageByte` takes
precedence. Unsupported magic, invalid numeric fields, decimal overflow, missing
fields, `maxval` outside 1..65535 or a non-whitespace delimiter after `maxval`
return `InvalidImageHeader`. A valid header with dimensions outside 1..4096
returns `UnsupportedImageSize`; an invalid `maxval` takes precedence over a bad
size. Too few raster bytes return `TruncatedImageData`. PNM never emits
`InvalidImageStream`.

Header and dimension checks precede the raster-length check and output
allocation. The positive-`maxval` and whitespace-delimiter requirements are
checked adaptations: the native parser accepts some malformed headers that
Jonlib rejects, and checked-invalid inputs are not claimed as native
rejections. The largest derived raster requirement is 100,663,296 bytes; this is
neither an encoded-list cap nor an allocation-success guarantee. Validation
traverses the entire immutable input list.

## Format-preserving PNM memory loading

`Surface.decode_pnm` preserves width/height and native P5 format
**1 (grayscale)** or P6 format **4 (RGB888)**. Export consumes the owner and
returns exactly `width*height` G bytes or `width*height*3` R,G,B bytes,
row-major and without array padding. Grayscale logical U32 words have zero high
24 bits; RGB888 words have a zero high byte. Integer extraction and packing
avoid floating-point luminance conversion, which could alter grayscale bytes.

The immutable input list can be reused; success returns one affine pixel owner.
Failure returns only the typed error, never a partial image. Point reads return
ownership alongside their `Maybe` result, so callers thread the owner through
both in-bounds and rejected reads. Export and `Surface.format`
consume the owner; the shared dispatch returns the same native result.

## Format-preserving PNM file loading

`Surface.load_pnm(path)` applies the same format-1/4 decoder to ordinary
files without consulting the suffix (`.pgm`, `.ppm`, `.pnm`, `.qoi`, mixed
case, arbitrary or absent suffixes all select PNM). It neither sniffs another
codec nor falls back to generic dispatch. The inclusive encoded-input cap is
1,048,576 bytes (`RasterFile`). Each acquired handle is closed before the read
result is processed or decoded; Base open/size/read errors keep their code and
message, and exact-read mismatches and decoder errors are wrapped once. The
full IO contract is in
[IMAGE-FILES.md](IMAGE-FILES.md#format-preserving-pnm-file-loading).

## How it is verified

All gates compare exact output against pinned native raylib on the CPU-1,
CPU-2 and JavaScript lanes (see [VERIFICATION.md](VERIFICATION.md)). Pinned
raylib disables PNM by default; the formatted memory and file gates build their
native archive with `SUPPORT_FILEFORMAT_PNM=ON`.

- **RGBA8 decode** (`tools/pnm_probe.py`, gate `pnm`, shared bitmap harness
  `tools/bmp_probe.py`): native `LoadImageFromMemory` converted to RGBA8 is
  compared pixel for pixel with `Surface.decode_pnm`. Fixtures cover both kinds,
  `maxval` boundaries, comments and all separators, leading zeros, every
  retained wide-byte value, channel ordering, CRLF/space/`#` first raster
  bytes, trailing data and 4096×1 / 1×4096 images. Malformed controls
  (incomplete samples/channels, invalid discarded bytes, bad headers) check the
  typed error only. The optional `--gpu` lane adds forced GPU. This gate
  converts to RGBA8 before inspection, so it does not establish native
  format-1/4 metadata or raw byte lengths.
- **Format-preserving memory decode** (`tools/pnm_format_probe.py`, gate
  `pnm-format`, driver `tools/formatted_codec.py`): the native archive is first
  qualified (little-endian, PNM enabled, wide second-byte retention, formats
  1/4). For each accepted fixture, native width/height/mipmaps/format and every
  raw byte are recorded before a separate RGBA8 normalization, including the
  `.pgm`/`.PPM`/`.PGM` aliases. Jonlib's raw export, factory and retained-owner
  point reads (high-bit invariants included) are compared with the raw bytes;
  the Surface bridge, `Surface.decode_pnm` and generic dispatch with the
  normalized bytes. An independent safety parser admits only complete accepted
  streams to native and never computes expected samples. Checked-invalid
  controls run only through Jonlib and check exact typed errors.
- **Format-preserving file loading** (`tools/pnm_file_probe.py`, gate
  `pnm-file`, driver `tools/formatted_file.py`): see
  [IMAGE-FILES.md](IMAGE-FILES.md#how-it-is-verified).

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only pnm-format
```

## Known gaps

- Full-depth (16-bit) sample APIs; output is always reduced 8-bit storage.
- Big-endian hosts and nondefault stb flag profiles; native permissive
  malformed-header recovery; dimensions above 4096.
- Native pointer/allocation ABI, OOM parity, maximum-area resources and
  performance.
- ASCII P1..P3 and PBM P4 decoding.
- GPU evidence is local only (`--gpu` on the `pnm` probe); the formatted memory
  and file gates run on CPU and JavaScript.
- In the API ledger this work is part of the partial
  `raylib:function:LoadImageFromMemory` and `raylib:function:LoadImage` entries;
  it completes neither, nor `ImageFormat`, `ExportImage` or PNM configuration
  controls.

The adapted stb reader (`src/pnm.bend`) retains the MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt).
