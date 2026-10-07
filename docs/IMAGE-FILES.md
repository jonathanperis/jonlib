# Image memory and file loading

Jonlib mirrors raylib's `LoadImageFromMemory`/`LoadImage` dispatch for its
implemented codecs, plus dedicated per-codec loaders. Every decoder returns the
native pixel format raylib produces (GRAYSCALE, GRAY_ALPHA, R8G8B8 or R8G8B8A8;
PSD and GIF are R8G8B8A8; HDR is R32G32B32). All file loading goes through one
bounded byte-file boundary.

| API | Result |
|---|---|
| `Surface.decode_image(file_type, bytes)` | `Result<&1, &1, Surface.Error, Surface>`, native format |
| `Surface.decode_image_for(reference, file_type, bytes)` | same, with an explicit `M.Contraction` |
| `Surface.load_image(path)` | `IO(Result<&1, &1, Surface.IOError, Surface>)`, native format |
| `Surface.load_image_for(reference, path)` | same, with an explicit `M.Contraction` |
| `Surface.load_qoi/load_png/load_pnm/load_tga/load_bmp/load_pic/load_hdr(path)` | `IO(Result<&1, &1, Surface.IOError, Surface>)`, explicit codec, native format |

`file_type` is an extension token such as `.png`, not a filename. The
`M.Contraction` choices are `M.Fused{}` and
`M.Uncontracted{}`; they affect only PSD white-matte arithmetic (see
[PSD.md](PSD.md)), and the convenience calls select uncontracted. The same
boundary also serves [owned animation loading](GIF-ANIMATION.md), whose GIF
suffix selection additionally accepts mixed letter case, and
`Surface.load_hdr(path)` ([HDR.md](HDR.md)), which selects the HDR float
decoder explicitly with a 1 MiB cap. Raw files use positional reads instead; see
[RAW-FILES.md](RAW-FILES.md).

`Surface.IOError` is `FileError{code, message}` (a Base open/size/read
error, preserved exactly) or `DataError{error}` (a `Surface.Error`,
wrapped exactly once).

## Suffix and content selection

Recognized tokens are `.png`, `.bmp`, `.tga`, `.pgm`, `.ppm`, `.jpg`, `.jpeg`,
`.gif`, `.pic`, `.psd`, `.qoi` and `.dds`, plus their entirely uppercase forms.
Mixed-case forms and `.pnm` are unsupported, matching native dispatch.

- **Memory** calls require the complete token: `image.png` and `.png-tail` are
  rejected. An unsupported token returns `InvalidImageHeader` before any byte
  decoding; recognized tokens keep the selected decoder's byte validation and
  typed errors.
- **File** calls use the last dot of the whole path, as native
  `GetFileExtension` does. A dot at position zero (the whole path `.png` or
  `.jpeg`) yields no suffix; a directory-qualified path such as `images/.png` is
  classified normally. Unsupported suffixes are still opened and read under the
  1 MiB cap, then fail with `DataError{InvalidImageHeader}`.
- `.qoi`/`.QOI` select QOI directly. Every other recognized token selects the
  stb-style raster family, which detects content: PNG, BMP, P5/P6, PSD, PIC and
  GIF signatures are tried in that order, otherwise the TGA profile. PNG bytes
  named `image.bmp` therefore load as PNG, matching native content detection.
  QOI bytes under a raster token and raster bytes under a QOI token are
  rejected. The `.jpg/.jpeg/.gif/.pic/.psd` aliases accept any implemented
  raster payload, as the native shared decoder does; actual JPEG decoding is
  not implemented.
- Codec profiles: [PNG](PNG.md), [BMP](BMP.md), [TGA](TGA.md), [PNM](PNM.md),
  [PSD](PSD.md), [PIC](PIC.md), [GIF](GIF.md) (first frame), QOI in
  [CODECS.md](CODECS.md). HDR is selected only explicitly (`load_hdr`,
  `decode_hdr`); the shared dispatch does not recognize `.hdr`.

Strings are ordinary extension/path text without embedded NULs.

## File IO model

`Image.file.bytes(path, limit)` performs, in order:

1. **Open.** Failure returns `FileError{code, message}`; no suffix check
   precedes opening, so a missing path with a misleading suffix still reports
   the open error. A failed open acquires no handle.
2. **Size.** A reported size above `limit` (through 4,294,967,295) returns
   `DataError{UnsupportedImageSize}` before any payload read. Pinned Base
   rejects sizes above U32_MAX with its host overflow file error, which stays an
   `FileError`. Size failures and size rejections close the file first.
3. **Read.** One bounded read of the reported size, then `File.close` **before**
   the read result is processed. Read errors keep Base's code/message. The
   returned list must have exactly the reported length; short or long results
   return `DataError{TruncatedImageData}`. There is no retry or
   streaming. A physically short file whose reported size is read in full
   reaches the decoder instead.
4. **Decode** the complete bytes with the selected decoder; its error is wrapped
   once as `DataError{error}`.

The decoding continuation receives only bytes or an error, never an open File.
These are close-*call* guarantees: pinned `Base.File.close` returns `IO(Unit)`,
its C implementation discards `close()`'s result and its JavaScript
implementation catches close exceptions, so there is no close-error variant and
no guarantee of reported OS-close success. Ordinary byte files contain only
0..255, so `InvalidImageByte` can occur only through internal-stage controls.

### Bounds

| Selection | Inclusive encoded-file cap |
|---|---|
| Raster tokens, unsupported suffixes, `load_png/pnm/tga/bmp/pic`, `load_hdr` | 1,048,576 bytes (`RasterFile`) |
| QOI tokens, `Surface.load_qoi` | 83,886,102 bytes = `14 + 5*(4096*4096) + 8` (`QoiFile`) |
| DDS tokens, `Surface.load_dds` | 67,109,000 bytes, above `128 + 4*(4096*4096)` (`DdsFile`) |

Caps bound admitted encoded input only, not decoded area, total heap,
allocation success or throughput; compressed input can describe far more pixel
storage. File bounds never enlarge a memory decoder's own domain.

## Format-preserving file loaders

Each `Surface.load_<codec>(path)` calls `Surface.load_with(~decode, limit, path)`,
which reads with `Image.file.bytes` and adapts the given decoder through
`Image.file.decoded`; passing the decoder as a parameter keeps each program to
the one codec it uses. Common contract:

- **Explicit selection.** The suffix is never consulted: lower/upper/mixed
  case, misleading (e.g. `.qoi` for PNG), arbitrary or absent suffixes, spaces,
  multiple dots and directory-qualified dotfiles all select the named codec.
  There is no content sniffing, codec fallback or caller-supplied cap. A misleading `.qoi` name still gets the 1 MiB raster cap.
- **Success** returns one affine `Surface` owner with width/height
  1..4096, one implicit mip level and the codec's native format. Export
  consumes it and returns exactly `width*height*channels` row-major bytes
  without padding; unused high bits of logical words are zero. Point reads
  return the owner for accepted and rejected coordinates; export and conversion
  consume it (see [FORMATS.md](FORMATS.md)).
- **Failure** returns no partial image and no open File.

The memory decoder contract of each codec applies unchanged; only the
differences and error orderings that matter for files are listed below.

### Format-preserving QOI file loading

Cap 83,886,102 bytes. Formats **4 (RGB888)** for channels 3 and **7
(RGBA8888)** for channels 4; both colorspaces are metadata-only and the
alpha-sensitive previous-pixel/cache behavior is inherited. Empty files, header
prefixes and invalid magic/channels/colorspace return `InvalidImageHeader`;
structurally valid zero or >4096 dimensions `UnsupportedImageSize`; missing
chunk operands `TruncatedImageData`; missing/corrupt end markers, extra tails,
run overflow and marker bytes absorbed as operands `InvalidImageStream`. A valid
non-QOI raster named `.qoi` fails header validation. Memory profile:
[CODECS.md](CODECS.md).

### Format-preserving PNG file loading

| PNG structure | Format | Components |
|---|---|---|
| Grayscale without tRNS | 1 | G |
| Grayscale with tRNS, or gray-alpha | 2 | G,A |
| RGB or palette without tRNS | 4 | R,G,B |
| RGB or palette with tRNS, or RGBA | 7 | R,G,B,A |

Channel promotion follows accepted structure, not opacity: empty, all-opaque
and unused-entry palette tRNS still promote to RGBA, promotion stays sticky
through a later accepted PLTE (which replaces colors and resets palette alpha),
and existing-alpha images keep alpha even when opaque. 16-bit tRNS comparisons
precede high-byte reduction. The memory decoder separately enforces the same
1 MiB encoded cap (including ignored tails after IEND) and an inclusive
67,108,864-byte filtered-stream cap. Its whole-input byte/count walk precedes
header parsing: an invalid U32 value yields `InvalidImageByte`; a valid first
value beyond the cap `UnsupportedImageSize` (an invalid value at that same
position takes precedence; later values are not inspected). Invalid signatures,
chunk structures and IHDR fields return `InvalidImageHeader` (so a physically
truncated PNG reports that, not `TruncatedImageData`); zero/oversized
dimensions and excessive filtered capacity `UnsupportedImageSize` before
inflation; invalid framing/DEFLATE, filters, raster lengths and palette indices
`InvalidImageStream`. Byte-valued tails after IEND are ignored. CRC/Adler
quirks, Adam7 and native-default CgBI handling are as in [PNG.md](PNG.md).
Native `.png` loading belongs to stb's sniffing family and can decode non-PNG
payloads; those native successes do not widen this PNG-only contract.

### Format-preserving PNM file loading

Formats **1** (P5) and **4** (P6). Empty/bad headers, invalid `maxval` and
malformed delimiters return `InvalidImageHeader`; unsupported dimensions
`UnsupportedImageSize`; an incomplete raster `TruncatedImageData`. PNM never
emits `InvalidImageStream`, though the wrapper would preserve it. Output is
reduced 8-bit storage; wide samples keep the second stored byte in the pinned
little-endian profile; ASCII P1..P3 and PBM P4 are unsupported. Profile:
[PNM.md](PNM.md).

### Format-preserving TGA file loading

Formats **1**, **2**, **4** (including expanded RGB555) and **7**, selected as
in [TGA.md](TGA.md#format-preserving-tga-memory-loading). Every value is
checked as a byte before the header. Empty, incomplete or unsupported headers
return `InvalidImageHeader`; unsupported dimensions `UnsupportedImageSize`;
missing ID/palette/sample/packet data `TruncatedImageData`; an RLE count past
the remaining image `InvalidImageStream`. Header validation precedes size,
then palette loading and pixel allocation. A non-TGA payload is never
redirected to another codec by its signature.

### Format-preserving BMP file loading

Formats **4** and **7**, chosen by the effective alpha layout before pixel
decoding and alpha repair (`BI_RGB` 32-bit all-zero alpha repair keeps RGBA
metadata; explicit alpha masks keep zero alpha). Full-list byte validation
comes first, including ignored fields, gaps, padding and tails. Then incomplete
base headers or unsupported base fields, planes, bit depth, compression or
offset return `InvalidImageHeader`; unsupported width/height returns
`UnsupportedImageSize` **before** extended-header completion and effective-mask
validation (controls `bad-size-before-incomplete-masks` and
`bad-size-before-invalid-mask`); with supported dimensions, incomplete
extended headers or invalid effective masks return `InvalidImageHeader`.
Required palette and raster completeness precede index decoding: incomplete
data returns `TruncatedImageData`, an index outside the loaded palette
`InvalidImageStream`. Header variants, masks, palettes and orientation follow
[BMP.md](BMP.md).

### Format-preserving PIC file loading

Formats **4** and **7**. PIC memory decoding has no encoded-input cap; the file
loader adds the 1 MiB cap. The union of all validated packet masks selects
alpha, independently of opacity, packet order and later RGB packets; missing
components stay white, ignored low mask bits select nothing and later channel
packets overwrite earlier values. Global byte validation precedes the header.
Invalid/incomplete magic, header or descriptors return `InvalidImageHeader`;
zero/oversized dimensions `UnsupportedImageSize`; missing raw/RLE samples,
controls and counts `TruncatedImageData`; mixed-RLE row overruns
`InvalidImageStream` before samples are read. Native's failed-PIC path can
null/free output before its 4-to-3 conversion, so malformed inputs are never
sent to native. Packet rules: [PIC.md](PIC.md).

## How it is verified

All gates compare exact output against pinned native raylib on the CPU-1,
CPU-2 and JavaScript lanes (see [VERIFICATION.md](VERIFICATION.md)). File IO is
verified on CPU and JavaScript only; no GPU filesystem claim is made.

- **Memory dispatch** (`tools/image_memory_probe.py`, gate `image-memory`):
  every token/content pair, including uppercase, mixed-case and unsupported
  tokens and cross-codec payloads, is decoded by native `LoadImageFromMemory`
  and by `Surface.decode_image_for`; dimensions and every RGBA8 pixel are
  compared, plus typed errors for invalid controls. `--gpu` adds a forced-GPU
  lane for the decoders.
- **File dispatch** (`tools/image_file_probe.py`, gate `image-file`): real files
  for every recognized suffix in both cases, cross-extension content, packed,
  indexed and cross-type TGA, BMP bitfield/extended/CORE headers, 16-bit PPM,
  raw/RLE PIC, RGB/alpha PSD, first-frame GIF, aliases, multiple dots, a
  whole-path `.png`, mixed/unsupported suffixes and malformed/empty/missing
  files are loaded by native `LoadImage` and `Surface.load_image_for`; an
  explicit-QOI file uses native `LoadFileData` + `LoadImageFromMemory(".qoi")`
  against `Surface.load_qoi`. Sparse raster cap+1 and QOI cap+1 files and a
  directory check the size/file error kinds, and a 100-iteration
  success/decode/file/size loop runs under `RLIMIT_NOFILE=64`.
- **Format-preserving file loaders** (gates `png-file`, `pnm-file`, `tga-file`,
  `bmp-file`, `pic-file`: `tools/<codec>_file_probe.py` on the shared driver
  `tools/codec_files.py`; gate `qoi-file`: `tools/qoi_file_probe.py`, its
  own runner because of the QOI cap). The native archive enables the BMP, PNG,
  TGA, JPG, GIF, PIC, PNM and PSD formats; a little-endian host is required.
  Every accepted memory fixture of the codec becomes a real file, plus
  filename variants. Recognized tokens route through native `LoadImage`; other
  names through `LoadFileData` + `LoadImageFromMemory(<codec token>)`. Native
  dimensions, mipmaps, format and raw bytes are recorded before a separate
  RGBA8 normalization. Jonlib's raw export, retained owner, factory and raw
  round trip are compared with the raw bytes; the Surface bridge, normalized
  loader and generic `Surface.load_image(_for)` with the normalized bytes.
  File controls check exact typed errors (exact errno and message for missing,
  directory and overflow). Other-codec content under the codec's suffix stays
  candidate-only, since native uses content detection. Three resource runs
  follow on each lane under `RLIMIT_NOFILE=64`: a 100-cycle closure loop over
  success, decode, directory-read, cap and overflow paths plus injected
  size/read failures and short/long results on real acquired handles; sparse
  cap+1 (also under a misleading name), 2^32-byte and (1 MiB loaders) 256 MiB
  files that are rejected without reading; and an exact-cap file with a validated ignored tail
  and its own native reference (for QOI, a 1,048,577-byte file that is read in
  full and rejected as invalid instead). Runtime RSS, measured separately from
  compilation, must stay below 256 MiB (closure/sparse) and 1 GiB (exact-cap);
  these are acceptance ceilings, not allocation limits.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only tga-file
```

Injected stage controls exercise real handles but are not observations of
concurrent short reads; the descriptor-limited loops detect leaks only on the
paths they exercise.

## Known gaps

- JPEG decoding; HDR in the shared suffix dispatch; original source formats
  for PSD and GIF (decoded as R8G8B8A8).
- Concurrent or changing files, special files, native callbacks, native
  pointer/allocation ABI and OOM parity, OS-close failure reporting.
- Maximum decoded-area, heap and performance qualification; nondefault stb
  flags; native malformed-stream recovery.
- GPU file IO, Windows, browser and big-endian hosts.
- In the API ledger these loaders are part of the partial
  `raylib:function:LoadImage` and `raylib:function:LoadImageFromMemory`
  entries; neither is complete.
