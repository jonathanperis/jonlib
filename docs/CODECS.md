# Image codecs

Every codec is implemented in Bend and compared against the pinned raylib 6.0
reference (stb_image/stb_image_write, sinfl/sdefl, QOI). Suffix/content
selection and the shared bounded file boundary are documented in
[IMAGE-FILES.md](IMAGE-FILES.md); the owned original-format image type in
[FORMATS.md](FORMATS.md); export in [IMAGE-EXPORT.md](IMAGE-EXPORT.md).

## Codec index

| Codec | Support | Page | Gates |
|---|---|---|---|
| QOI | Decode RGB/RGBA (Surface and native format 4/7), files, exact export | [below](#qoi) | `conformance`, `qoi-format`, `qoi-file`, `formatted-qoi-export` |
| PNG | Packed/8/16-bit, Adam7, native-default CgBI; Surface and native format 1/2/4/7; files | [PNG.md](PNG.md) | `png`, `png-format`, `png-file` |
| BMP | CORE/INFO/56-byte/V4/V5, indexed/true-color/bitfields; native format 4/7; files; V4 export | [BMP.md](BMP.md) | `bmp`, `bmp-format`, `bmp-file`, `formatted-bmp-export` |
| TGA | True-color/grayscale/indexed raw/RLE; native format 1/2/4/7; files; default RLE export | [TGA.md](TGA.md) | `tga`, `tga-format`, `tga-file`, `formatted-tga-export` |
| PNM | Binary 8/16-bit P5/P6; native format 1/4 (8-bit); files | [PNM.md](PNM.md) | `pnm`, `pnm-format`, `pnm-file` |
| PSD | Raw/PackBits RGB(A) planes, explicit matte profiles; Surface only | [PSD.md](PSD.md) | `psd`, `psd-matte` |
| PIC | Softimage raw/pure-RLE/mixed-RLE packets; native format 4/7; files | [PIC.md](PIC.md) | `pic`, `pic-format`, `pic-file` |
| GIF (first frame) | Rectangles, interlacing, palettes, transparency, bounded LZW; Surface only | [GIF.md](GIF.md) | `gif` |
| GIF animation | Owned frames, retain/restore disposal, budgets; memory and files | [GIF-ANIMATION.md](GIF-ANIMATION.md) | `gif-animation`, `animation-file` |
| HDR | Raw/RLE Radiance RGBE to exact F32 (format 9); files | [HDR.md](HDR.md) | `hdr`, `hdr-file` |
| JPEG | Tokens `.jpg`/`.jpeg` route to the implemented raster decoders only; JPEG decoding is not implemented | [IMAGE-FILES.md](IMAGE-FILES.md) | `image-memory`, `image-file` |
| Raw headerless | Explicit `LoadImageRaw`/`.raw` export for formats 1..8 (checked R32) and format 9 | [RAW-FILES.md](RAW-FILES.md) | `raw-file`, `r32-raw-file`, `float-rgb-raw-file` |
| Image as code | Exact `ExportImageAsCode` text and file export | [IMAGE-CODE.md](IMAGE-CODE.md) | `image-code` |
| DEFLATE decompression | Bounded raw DEFLATE (`DecompressData`) and the PNG inflater policy | [DEFLATE.md](DEFLATE.md) | `inflate` |
| Compression | sdefl quality-8 raw DEFLATE (`CompressData`) | [COMPRESSION.md](COMPRESSION.md) | `sdeflate-huffman`, `sdeflate-lz`, `sdeflate` |

Shared normalized dispatch (`Surface.decode_image`, `Surface.load_image`) is
gated by `image-memory` and `image-file`. Run any gate with
`python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only <gate-id>`.

`Image.DecodeError` distinguishes `InvalidImageHeader`, `InvalidImageByte`,
`UnsupportedImageSize`, `TruncatedImageData` and `InvalidImageStream`.
`Image.LoadError` wraps either `ImageFileError{code, message}` or
`ImageDecodeError{error}`.

## QOI

The QOI implementation is entirely Bend, in `src/qoi.bend`. Its error and
ownership adapters are exposed through `jonlib.bend`:

| API | Contract |
|---|---|
| `Image.Formatted.decode_qoi(bytes: +List<U32>)` | Returns `Result<&1, &1, Image.DecodeError, Image.Formatted>` with original RGB888 (4) or RGBA8888 (7) storage and one mip level. Dimensions 1..4096; strict checked bytes/streams. See [format-preserving memory loading](#format-preserving-qoi-memory-loading). |
| `Image.Formatted.load_qoi(path: String)` | Returns `IO(Result<&1, &1, Image.LoadError, Image.Formatted>)`; explicit QOI selection regardless of suffix, preserving the memory decoder's format 4/7 owner. See [file loading](#format-preserving-qoi-file-loading). |
| `Image.Formatted.to_qoi(image)` / `write_qoi(image, path)` | Explicit QOI export accepts original formats 4/7 only, with header channels 3/4; unsupported checked owners return unchanged before file IO. Accepted writes consume and close acquired handles. See [checked formatted export](#checked-formatted-qoi-export). |
| `Surface.decode_qoi(bytes: +List<U32>)` | Returns `Result<&1, &1, Image.DecodeError, Surface>`; byte values must be 0..255. Accepts valid RGB/RGBA QOI, dimensions 1..4096. |
| `Surface.to_qoi(surface)` | Consumes the Surface and returns immutable encoded bytes. Header channels are 4 and colorspace is 0. |
| `Surface.load_qoi(path)` | Base byte-file IO returning `IO(Result<&1, &1, Image.LoadError, Surface>)`. |
| `Surface.write_qoi(surface, path)` | Consumes the Surface, writes QOI through Base byte IO, and returns `IO(Result<&1, &1, U32 & String, Unit>)`, the same file-error contract as `write_ppm`. |

File paths call `File.close` after read/write results and on size
failure/rejection; reads close before their results are processed or decoded.
Base returns no close error. QOI file loading admits reported sizes through
**83,886,102 bytes**, equal to `14 + 5*(4096*4096) + 8`; this is an encoded-byte
admission cap, not a runtime-memory or maximum-image success guarantee. Reported
sizes above the cap are rejected before payload reads. Sizes above U32_MAX
instead fail the pinned Base size call; see [IMAGE-FILES.md](IMAGE-FILES.md).

Decoding supports RGB, RGBA, index, difference, luma and run chunks, including
wrapping channel differences, cache collisions and run-boundary handling. RGB
headers are normalized to opaque RGBA8 by the Surface entry points; their
reference check performs the same explicit `LoadImageFromMemory` followed by
`ImageFormat(RGBA8)` adaptation. The dedicated formatted memory and file entry
points preserve native QOI formats.

The decoder rejects truncated chunks, runs beyond the declared pixel count and
missing/invalid end markers. It does not reproduce the C decoder's permissive
recovery of some malformed streams.

### Format-preserving QOI memory loading

`Image.Formatted.decode_qoi(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Image.Formatted>`. A header with channels 3
produces format **4 (RGB888)**; channels 4 produces format **7 (RGBA8888)**. Both
retain width/height in 1..4096 and the formatted owner's implicit single mip
level. Export returns exactly `width*height*channels` row-major bytes in
R,G,B[,A] order, with no array padding. RGB logical U32 words have a zero high
byte; RGBA words retain every alpha byte. The decoder uses integer byte packing,
without normalized floating-point conversion.

The immutable byte list can be reused for independent decodes. Success returns
one affine pixel owner, consumed by export or a Surface bridge; failure returns
only the typed error. Cache/output temporaries are dropped on failure.
`Surface.decode_qoi`, generic Surface memory dispatch and Surface file loaders
retain their RGBA8-normalized contracts.

Channel count affects the output only. Full alpha remains in the decoder's
previous pixel and cache hash even in channel-3 streams containing RGBA chunks;
later RGB/DIFF/LUMA/INDEX chunks retain the native state behavior. Colorspace
header values 0 and 1 are metadata-only and do not transform bytes. Initial
opaque black differs from the zero-initialized transparent cache. Consecutive
identical INDEX chunks remain accepted by both decoders, although canonical QOI
encoders prohibit them.

All byte values are checked before parsing; a value above 255 anywhere yields
`InvalidImageByte`, even alongside an invalid header. An incomplete/invalid
header, unsupported channels or colorspace yields `InvalidImageHeader`.
Structurally valid zero or >4096 dimensions yield `UnsupportedImageSize` before
allocation. Missing opcode operands yield `TruncatedImageData`; exact
classification follows the parser stage. If marker bytes are absorbed as short
operands, completion instead yields `InvalidImageStream`. Exactly the requested
pixel count, no outstanding run and precisely the eight-byte QOI end marker are
required. Trailing bytes, extra opcodes, missing/corrupt markers and run overflow
are rejected. Memory decoding adds no encoded-input cap: validation traverses the
entire supplied immutable list, including arbitrarily long rejected input.

The pinned `LoadImageFromMemory` wrapper reads `fileData[12]` before the QOI
decoder's minimum-length guard, so native invalid controls use complete
>=22-byte backing buffers and declared lengths with safe invalid headers; short
and overflow stream controls execute only in checked Jonlib.

### Format-preserving QOI file loading

`Image.Formatted.load_qoi(path: String)` returns
`IO(Result<&1, &1, Image.LoadError, Image.Formatted>)`. It reads an ordinary,
non-changing file through the shared QOI-capped boundary and passes its complete
bytes directly to `Image.Formatted.decode_qoi` after the close call. It takes no
input owner, reference profile, dimensions or channel argument. Success creates
one affine format-4 or format-7 owner with the same dimensions, exact bytes,
implicit single mip level and metadata-only colorspace handling as the memory
decoder. Failures return only `ImageFileError{code, message}` or one
`ImageDecodeError{error}` wrapper, without a partial owner.

Selection is explicit: `.qoi`, `.QOI`, `.QoI`, no suffix and a misleading `.png`
suffix all select QOI. There is no sniffing or retry with another codec, so
non-QOI raster content named `.qoi` fails QOI header validation. The inclusive
83,886,102-byte cap, U32 size-overflow distinction, exact read-length check,
decoder error ordering and close-error limitation are specified in
[IMAGE-FILES.md](IMAGE-FILES.md). Native `LoadImage` dispatches only `.qoi`/`.QOI`
suffixes to QOI; the reference for other suffixes is `LoadFileData` followed by
`LoadImageFromMemory(".qoi", ...)`, so suffix-independent selection does not
extend native `LoadImage` dispatch.

### Checked formatted QOI export

`Image.Formatted.to_qoi` and `write_qoi` preserve the native original-format
export gate: only RGB888 (4) and RGBA8888 (7) succeed. Formats 1/2/3/5/6/8 are
rejected before conversion or file IO with their exact owner. RGB uses canonical
opaque alpha and header 3; RGBA keeps all channels and header 4. Both write
colorspace 0. A decoded channel-3 source's discarded alpha and either source's
original colorspace cannot be reconstructed by re-export. Exact bytes, typed
owner/file errors and closed-handle behavior are specified in
[IMAGE-EXPORT.md](IMAGE-EXPORT.md).

The pinned raylib **`ExportImageToMemory` implements PNG only**. QOI memory
encoding is a Jonlib convenience backing the QOI `ExportImage` mapping; it is not
claimed as coverage of `ExportImageToMemory`.

### How QOI is verified

- **Surface decode/encode** (`tools/conformance.py`, gate `conformance`, fixtures
  in `tests/fixtures/images.json`): actual raylib `ExportImage` writes task-owned
  QOI files and every emitted byte is compared, together with decoded dimensions
  and every pixel, so encoding is not verified solely through a self round trip.
  Cases cover every opcode, alpha, RGB normalization, cache collisions and
  4096-pixel runs, plus malformed byte-stream contracts and missing/malformed/
  oversized-file checks. The gate also builds and runs
  `examples/qoi_roundtrip.bend`, which writes `.build/qoi-roundtrip.qoi`, loads
  it back and prints its dimensions and packed pixels; the file is compared with
  raylib's export.
- **Format-preserving memory loading** (`tools/qoi_format_probe.py` on
  `tools/formatted_codec.py`, gate `qoi-format`): native format 4/7 metadata,
  `mipmaps == 1` and every raw byte from `LoadImageFromMemory` are captured before
  separate normalization, then compared through the raw, factory, owner, bridge,
  Surface and lower/upper-case dispatch roles, with exact typed failures on
  CPU-1, CPU-2 and JavaScript. Fixtures cover all opcode families,
  hidden-alpha/cache collisions, initial/empty cache distinctions, all 64 DIFF
  encodings, LUMA boundaries, full byte/alpha ramps, run boundaries, padded
  shapes, both 4096-axis endpoints and a large nonuniform image.
- **Format-preserving file loading** (`tools/qoi_file_probe.py`, gate
  `qoi-file`): accepted fixtures as ordinary files through native `LoadImage`
  (`.qoi`/`.QOI`) and explicit-selection references for other suffixes, typed
  controls, and closure/resource runs. Because QOI has its own 83,886,102-byte
  cap rather than the 1 MiB raster cap, this probe keeps its own runner instead
  of `tools/formatted_file.py`.
- **Formatted export** (`tools/formatted_qoi_export_probe.py`, gate
  `formatted-qoi-export`); see [IMAGE-EXPORT.md](IMAGE-EXPORT.md).

### QOI known gaps

Native permissive malformed-stream recovery, native pointer/allocation ABI and
allocation-failure parity, generic formatted/float dispatch, GPU for the
formatted and file paths, Windows/browser and big-endian targets,
special/concurrently changing files, maximum-area allocation and complete
integration/resource/performance coverage.

### QOI provenance

Library algorithms never link QOI's C implementation; it is retained only in
independent reference tooling. QOI's author is Dominic Szablewski. The adapted
source retains its [MIT notices](../LICENSES/qoi.txt). See
[third-party notices](../THIRD_PARTY_NOTICES.md) and the
[API progression dashboard](PROGRESS.md) for provenance and remaining scope.
