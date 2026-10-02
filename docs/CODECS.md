# Image codec profiles

Supported image-file suffix/content selection and bounded IO are documented in
[IMAGE-FILES.md](IMAGE-FILES.md), including the explicit QOI loader contract.

Headerless byte/integer image files are supported through the owned formatted
image APIs; see [RAW-FILES.md](RAW-FILES.md) for exact loading/export contracts.
Native image-as-code headers are documented in [IMAGE-CODE.md](IMAGE-CODE.md),
including the exact text format, naming rules and bounded owned file export.

BMP memory decoding and exact RGBA8 V4 export are documented in [BMP.md](BMP.md),
including supported headers, native alpha/offset rules and rejected variants.
TGA true-color/grayscale/indexed raw/RLE decoding and exact default RLE export are
documented in [TGA.md](TGA.md).
Binary 8/16-bit P5/P6 decoding and native sample/maxval/separator rules are documented in
[PNM.md](PNM.md).
Raw/PackBits RGB/alpha PSD planes, explicit matte profiles and metadata bounds are documented in
[PSD.md](PSD.md).
Raw/pure-RLE/mixed-RLE Softimage PIC packets, white defaults and channel overwrite order are
documented in [PIC.md](PIC.md).
First-frame GIF rectangles, interlacing, palettes, transparency and bounded LZW are documented
in [GIF.md](GIF.md).
Owned GIF animation frames and retain/restore disposal are documented in
[GIF-ANIMATION.md](GIF-ANIMATION.md).
Owned raw/RLE Radiance RGBE float images, including exact subnormal samples, are
documented in [HDR.md](HDR.md).

The raw [DEFLATE dependency](DEFLATE.md) is verified separately. Non-interlaced and
Adam7 packed/8/16-bit PNG decoding, native-default CgBI, filters, transparency rules and limits are documented
in [PNG.md](PNG.md).

## QOI

The QOI implementation is entirely Bend, in `src/qoi.bend`. Its error and
ownership adapters are exposed through `jonlib.bend`:

| API | Contract |
|---|---|
| `Image.Formatted.decode_qoi(bytes: +List<U32>)` | Returns `Result<&1, &1, Image.DecodeError, Image.Formatted>` with original RGB888 (4) or RGBA8888 (7) storage and one mip level. Dimensions 1..4096; strict checked bytes/streams. |
| `Image.Formatted.load_qoi(path: String)` | Returns `IO(Result<&1, &1, Image.LoadError, Image.Formatted>)`; explicit QOI selection regardless of suffix, preserving the memory decoder's format 4/7 owner. See [file loading](#format-preserving-qoi-file-loading). |
| `Image.Formatted.to_qoi(image)` / `write_qoi(image, path)` | Explicit QOI export accepts original formats 4/7 only, with header channels 3/4; unsupported checked owners return unchanged before file IO. Accepted writes consume and close acquired handles. See the [formatted export contract and local CPU/JavaScript evidence](FORMATTED-QOI-EXPORT.md). |
| `Surface.decode_qoi(bytes: +List<U32>)` | Returns `Result<Image.DecodeError, Surface>`; byte values must be 0..255. Accepts valid RGB/RGBA QOI, dimensions 1..4096. |
| `Surface.to_qoi(surface)` | Consumes the Surface and returns immutable encoded bytes. Header channels are 4 and colorspace is 0. |
| `Surface.load_qoi(path)` | Base byte-file IO returning `IO(Result<Image.LoadError, Surface>)`. |
| `Surface.write_qoi(surface, path)` | Consumes the Surface, writes QOI through Base byte IO, and returns the same file-error contract as `write_ppm`. |

Some Result signatures above abbreviate the explicit affine quantities shown in
the source. File paths call `File.close` after read/write results and on size
failure/rejection; reads close before their results are processed or decoded.
Base returns no close error. QOI file loading admits reported sizes through
**83,886,102 bytes**, equal to `14 + 5*(4096*4096) + 8`; this is an encoded-byte
admission cap, not a runtime-memory or maximum-image success guarantee.
Reported sizes above the cap are rejected before payload reads. Sizes above
U32_MAX instead fail the pinned Base size call; see [file errors](IMAGE-FILES.md#format-preserving-qoi-file-loading).

Decoding supports RGB, RGBA, index, difference, luma and run chunks, including
wrapping channel differences, cache collisions and run-boundary handling. RGB
headers are normalized to opaque RGBA8 by the Surface entrypoints. Their reference
check performs the same explicit `LoadImageFromMemory` followed by
`ImageFormat(RGBA8)` adaptation. The dedicated formatted memory and file entrypoints
preserve native QOI formats. Original-format metadata in the other normalized
codec paths, shared formatted/float dispatch and other payload codecs remain gaps.

`Image.DecodeError` distinguishes `InvalidImageHeader`, `InvalidImageByte`,
`UnsupportedImageSize`, `TruncatedImageData` and `InvalidImageStream`.
`Image.LoadError` wraps either `ImageFileError{code, message}` or
`ImageDecodeError{error}`. The decoder rejects truncated chunks, runs beyond the
declared pixel count and missing/invalid end markers. It does not reproduce
the C decoder's permissive recovery of some malformed streams.

## Format-preserving QOI memory loading

`Image.Formatted.decode_qoi(bytes: +List<U32>)` returns
`Result<&1, &1, Image.DecodeError, Image.Formatted>`. A header with channels 3
produces format **4 (RGB888)**; channels 4 produces format **7 (RGBA8888)**.
Both retain width/height in 1..4096 and the formatted owner's implicit single
mip level. Export returns exactly `width*height*channels` row-major bytes in
R,G,B[,A] order, with no array padding. RGB logical U32 words have a zero high
byte; RGBA words retain every alpha byte. The decoder uses integer byte packing,
without normalized floating-point conversion.

The immutable byte list can be reused for independent decodes. Success returns
one affine pixel owner, consumed by export or a Surface bridge; failure returns
only the existing typed error. Cache/output temporaries are dropped on failure.
Neither native pointer/allocation ABI nor allocation-failure parity is claimed.
`Surface.decode_qoi`, generic Surface memory dispatch and Surface file loaders
retain their RGBA8-normalized contracts. The dedicated formatted file wrapper
is documented separately below; generic formatted decoder dispatch remains a gap.

Channel count affects the output only. Full alpha remains in the decoder's
previous pixel and cache hash even in channel-3 streams containing RGBA chunks;
later RGB/DIFF/LUMA/INDEX chunks retain the native state behavior. Colorspace
header values 0 and 1 are metadata-only and do not transform bytes. Initial
opaque black differs from the zero-initialized transparent cache. Consecutive
identical INDEX chunks remain accepted by both decoders, although canonical
QOI encoders prohibit them.

All byte values are checked before parsing; a value above 255 anywhere yields
`InvalidImageByte`, even alongside an invalid header. An incomplete/invalid
header, unsupported channels or colorspace yields `InvalidImageHeader`.
Structurally valid zero or >4096 dimensions yield `UnsupportedImageSize` before
allocation. Missing opcode operands yield `TruncatedImageData`; exact
classification follows the parser stage. If marker bytes are absorbed as short
operands, completion instead yields `InvalidImageStream`. Exactly the requested
pixel count, no outstanding run and precisely the eight-byte QOI end marker
are required. Trailing bytes, extra opcodes, missing/corrupt markers and run
overflow are rejected. Native permissive malformed-stream recovery remains
excluded. Memory decoding adds no encoded-file cap: validation still traverses
the entire supplied immutable list, including arbitrarily long rejected input.

The [scoped evidence](evidence/qoi-formatted.json) records complete native raw
metadata/bytes before any normalization, and independent Surface/bridge and
lower/upper-case dispatch comparisons. The probe runs CPU one-thread, CPU
two-thread and JavaScript, checks RGB high-byte ownership invariants and factory
exports, and compares exact typed failures through both entrypoints. The fixture
matrix covers all opcode families, hidden-alpha/cache collisions, initial/empty
cache distinctions, all 64 DIFF encodings, LUMA boundaries, full byte/alpha ramps,
run boundaries, padded shapes, both 4096-axis endpoints and a nonuniform
5,103-pixel image. GPU/Metal, Windows, big-endian and maximum-area allocation
are not established by these results. Earlier Surface GPU evidence does not
qualify the new formatted path.

```sh
python3 tools/qoi_format_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 -m unittest discover -s tests -p test_qoi_format_harness.py -v
```

The native gate uses actual pinned `LoadImageFromMemory`, observes `image.data`
as format 4/7 and verifies actual `image.mipmaps==1` before `ImageFormat`.
Only then does it emit separately normalized regression bytes. Native invalid
controls have complete >=22-byte backing buffers and declared lengths, safe
invalid headers and no large allocation request: the pinned wrapper reads
`fileData[12]` before the QOI decoder's minimum-length guard. Short/overflow
stream controls execute only in checked Jonlib.

## Format-preserving QOI file loading

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
[IMAGE-FILES.md](IMAGE-FILES.md#format-preserving-qoi-file-loading).

The separate [file evidence](evidence/qoi-formatted-files.json) passes on local
Linux x86-64 CPU-one-thread, CPU-two-thread and JavaScript. It compares **135
accepted ordinary files / 35,657 pixels / 126,883 native-format bytes** before
normalization: **129 actual native `LoadImage(path)` calls** for `.qoi`/`.QOI`
and **6 explicit-selection references** using `LoadFileData(path)` followed by
`LoadImageFromMemory(".qoi", ...)` under other suffixes. Those reference routes
are distinct; suffix-independent helper behavior does not extend native
`LoadImage` dispatch. Complete metadata/raw-byte observations, independent
Surface regressions and **69 typed controls** yield **287 observations / 138,007
compared bytes per lane**. The historical formatted-memory evidence remains
memory-only; this file result is independently qualified.

The [file verification record](VERIFICATION.md#format-preserving-qoi-file-loading-2026-10-02)
and [resource/closure details](IMAGE-FILES.md#formatted-qoi-file-evidence) record
100 low-descriptor cycles through eight actual-handle paths, a final successful
load, and the separately measured 1,048,577-byte full-read stress case.

```sh
python3 tools/qoi_file_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 -m unittest discover -s tests -p test_qoi_file_harness.py -v
```

Generic formatted/float dispatch and original formats for the other normalized
codecs remain open, as do GPU IO, macOS/Windows/browser file qualification,
big-endian targets, special/concurrently changing files, maximum-area allocation
and complete integration/resource/performance coverage.

## Checked formatted QOI export

`Image.Formatted.to_qoi` and `write_qoi` preserve the native original-format
export gate: only RGB888 (4) and RGBA8888 (7) succeed. Formats 1/2/3/5/6/8 are
rejected before conversion or file IO with their exact owner. RGB uses canonical
opaque alpha and header 3; RGBA keeps all channels and header 4. Both write
colorspace 0. A decoded channel-3 source's discarded alpha and either source's
original colorspace cannot be reconstructed by re-export.

The [formatted export contract](FORMATTED-QOI-EXPORT.md) specifies exact bytes,
typed owner/file errors, closed-handle behavior and the focused gate design.
The [focused report](evidence/formatted-qoi-export.json) records a local Linux
x86-64 CPU-1/CPU-2/JavaScript pass for 273 accepted and 22 rejected sources,
comparing 1,415,214 encoded bytes per lane. Original-format decode bytes,
retained owners, opcode boundaries and typed file/resource behavior have their
own complete observations; older Surface and formatted-load evidence is not
substituted for this new exporter.

## Reference and verification

The pinned raylib **`ExportImageToMemory` implements PNG only**. QOI memory
encoding is a Jonlib convenience backing the QOI `ExportImage` mapping; it is
not claimed as coverage of `ExportImageToMemory`.
`Surface.to_png` and `Image.Formatted.to_png` cover the default RGBA8 and byte-format PNG memory paths, with exact native
memory/file verification described in [PNG-EXPORT.md](PNG-EXPORT.md).

The conformance gate calls actual raylib `ExportImage` to task-owned QOI files
and compares every emitted byte. It also compares decoded dimensions and every
pixel, so encoding is not verified solely through a self round trip. Cases
cover every opcode, alpha, RGB normalization, cache collisions and 4096-pixel
runs. The current export cases compare every byte per execution lane; exact
case/byte totals are recorded in [VERIFICATION.md](VERIFICATION.md). Malformed
byte-stream contracts run on CPU, JavaScript and forced Metal.
The real file example and missing/malformed/oversized-file checks run on CPU/JS.

With the checkout variables from [README.md](../README.md#requirements) set:

```sh
python3 tools/conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
BEND_NO_TELEMETRY=1 bun "$BEND_SOURCE/bend2/main.ts" examples/qoi_roundtrip.bend -o .build/qoi-roundtrip
./.build/qoi-roundtrip
```

The example writes `.build/qoi-roundtrip.qoi`, loads it through Jonlib and prints
its dimensions and packed pixels. The harness compares the file with raylib's
actual export. Library algorithms never link QOI's C implementation; it is
retained only in independent reference tooling.

QOI's author is Dominic Szablewski. The adapted source retains its
[MIT notices](../LICENSES/qoi.txt). See [third-party notices](../THIRD_PARTY_NOTICES.md)
and the [API progression dashboard](PROGRESS.md) for provenance and remaining scope.
