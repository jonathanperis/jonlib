# Image memory and file dispatch

`Surface.decode_image(file_type, bytes)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with normalized RGBA8 pixels.
The file-type argument is an extension token such as `.png`, not a filename.
It selects the same implemented decoder family as file loading, without IO.

`Surface.load_image(path)` returns
`IO(Result<&1, &1, Image.LoadError, Surface>)` with normalized RGBA8 pixels.
It reads ordinary, non-changing files using Base IO and the implemented memory
codec profiles.

`Surface.decode_image_for(reference, file_type, bytes)` and
`Surface.load_image_for(reference, path)` select `J.Image.Decode.Reference` for
PSD white-matte arithmetic. Choices are `J.FusedDecode{}` and
`J.UncontractedDecode{}`; convenience calls select uncontracted. Other current
codec profiles retain their byte-exact behavior. See [PSD.md](PSD.md).

## Suffix and content selection

Recognized tokens are `.png`, `.bmp`, `.tga`, `.pgm`, `.ppm`, `.jpg`, `.jpeg`,
`.gif`, `.pic`, `.psd` and `.qoi`, plus their entirely uppercase equivalents.
Mixed-case forms and `.pnm` return a decode error, matching native dispatch.
Memory calls require the complete token: `image.png` and `.png-tail` are rejected.
File calls use the last dot in the path, as native `GetFileExtension` does. A dot
at position zero, such as the whole path `.png` or `.jpeg`, is rejected; a
directory-qualified path such as `images/.png` is classified normally.

QOI suffixes select QOI directly. The other recognized suffixes select the
implemented stb-style family: PNG, BMP, P5/P6, PSD, PIC and GIF signatures are recognized before
trying the supported TGA profile. Consequently, PNG bytes named `image.bmp`
load as PNG, matching actual native content detection. QOI bytes with a raster
suffix and raster bytes with a QOI suffix are rejected. The `.jpg/.jpeg/.gif/.pic/.psd`
aliases accept the implemented raster payloads, just as the native shared decoder
does. PSD payloads have the [raw/PackBits and matte profiles](PSD.md), and PIC has
[raw and RLE channel-packet decoding](PIC.md). GIF has a bounded
[first-frame profile](GIF.md). Actual JPEG decoding remains unimplemented. HDR's
native float path is exposed separately through [Image.FloatRGB](HDR.md), outside
this RGBA8 dispatch profile.

`Surface.load_qoi(path)` remains an explicit QOI loader and does not consult the
suffix. `Image.Formatted.load_qoi(path)` selects QOI the same way and preserves
native RGB888/RGBA8888 storage instead of returning a normalized Surface; its
[dedicated contract](#format-preserving-qoi-file-loading) is below. These
operations share the checked IO boundary.
`Image.Formatted.load_png(path)`, `Image.Formatted.load_pnm(path)`,
`Image.Formatted.load_tga(path)` and `Image.Formatted.load_bmp(path)` likewise
select their named codecs independently
of suffixes, preserving the respective native output formats with the inclusive
1 MiB raster-file cap. Their dedicated [PNG](#format-preserving-png-file-loading),
[PNM](#format-preserving-pnm-file-loading),
[TGA](#format-preserving-tga-file-loading) and
[BMP](#format-preserving-bmp-file-loading) contracts are below.
The same byte-file boundary serves [owned animation loading](GIF-ANIMATION.md#file-loading),
whose native GIF suffix selection additionally accepts mixed letter case.
`Image.FloatRGB.load_hdr(path)` also shares that boundary, selecting the
[HDR float decoder](HDR.md) explicitly with a 1 MiB encoded-input cap.

## Bounds, ownership and errors

- Raster and unknown-suffix files are capped at **1 MiB** before reading.
- QOI selection retains its inclusive **83,886,102-byte** encoded-size cap.
- The read must return exactly the complete reported size. Short or long results return
  `ImageDecodeError{TruncatedImageData}`.
- Open/size/read errors retain `ImageFileError{code, message}`.
- Unsupported suffixes and decoder errors are wrapped as `ImageDecodeError`;
  successfully reported oversize files use `UnsupportedImageSize`. The pinned
  Base size call rejects sizes above **4,294,967,295** with an overflow file error.
- The shared reader calls `File.close` before processing read results or decoding,
  including on size/read failure and size rejection. Pinned Base discards close
  errors. Surface loaders return an owned Surface on success.

Memory codec APIs retain their own documented profiles; file bounds do not
enlarge those domains. Concurrent changes, special-file behavior, native callbacks,
original-format metadata for the remaining normalized codec paths, generic
formatted/float dispatch and full resource/platform coverage remain gaps.
Memory dispatch rejects unsupported tokens with `InvalidImageHeader` before byte
decoding; recognized tokens retain the selected decoder's byte validation and
typed errors. Strings use ordinary extension/path text without embedded NULs.

## Format-preserving QOI file loading

`Image.Formatted.load_qoi(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)`
is a dedicated ordinary-file wrapper around the existing checked formatted QOI
decoder. It does not inspect filename suffixes: `.qoi`, `.QOI`, `.QoI`, suffixless
names, `.png`, paths with spaces/multiple dots and directory-qualified dotfiles
all select the same QOI decoder. It does not sniff or retry another codec. No
reference-profile, channel, dimension or caller-supplied cap argument is needed.
Surface QOI/file/memory APIs and generic suffix/content dispatch are unchanged.

The operation and error order are:

1. Open the path through the shared byte-file reader. An open failure returns
   `ImageFileError{code, message}`, including a missing path with a misleading
   suffix; there is no pre-open suffix rejection and no handle to close.
2. Obtain the size. The shared QOI cap is **83,886,102 bytes**, inclusive,
   equal to `14 + 5*(4096*4096) + 8`. A successfully reported larger size through
   U32_MAX returns `ImageDecodeError{UnsupportedImageSize{}}` without a payload
   read. Pinned Base rejects sizes above **4,294,967,295** with host `EOVERFLOW`;
   this remains `ImageFileError{code, message}`. Size failures and size rejections
   both call `File.close` before returning.
3. For an admitted size, perform the existing single bounded byte read. Read
   failures preserve the original file-error code/message. `File.close` is called
   before the read result is processed. The returned list must have exactly the
   reported length: short and synthetic long results yield
   `ImageDecodeError{TruncatedImageData{}}`. There is no retry or streaming loop.
   A physically short file whose actual reported size is fully read instead
   reaches the decoder.
4. Decode the complete bytes with `Image.Formatted.decode_qoi`, wrapping each
   exact decoder error once as `ImageDecodeError{error}`. Empty files, header
   prefixes and invalid magic/channels/colorspace fail with `InvalidImageHeader`;
   structurally valid zero or >4096
   dimensions fail with `UnsupportedImageSize`; missing chunk operands fail
   with `TruncatedImageData`. Missing/corrupt markers, extra tails, run overflow
   and marker bytes absorbed as operands use `InvalidImageStream` according to
   the existing parser stage. A valid non-QOI raster named `.qoi` fails header
   validation. File byte readers return only 0..255, so `InvalidImageByte` remains
   a decoder/error-propagation value but is not an ordinary-file byte fixture.

Success returns one affine `Image.Formatted` owner, with width/height 1..4096,
one implicit mip level, format **4 (RGB888)** for QOI channels 3 or format
**7 (RGBA8888)** for channels 4. Export consumes it and returns exactly
`width*height*channels` row-major R,G,B[,A] bytes, excluding padding. RGB logical
words have a zero high byte. Both colorspaces are metadata-only; the decoder's
alpha-sensitive previous-pixel/cache behavior is inherited unchanged. There is
no input, partial-image or encoded-file owner to return on failure. Conversion
and disposal use the existing [formatted owner API](FORMATS.md).

The continuation receives only bytes or an error, never an open File. These are
close-call ordering guarantees: pinned `Base.File.close` returns `IO(Unit)`, its
C implementation discards `close()`'s result and its JavaScript implementation
catches close exceptions. There is no new close-error variant or guarantee of
reported OS-close success. Low-descriptor repetition can detect accumulated
ordinary leaks in exercised runs; it cannot prove every close succeeded.

The cap governs encoded bytes admitted for reading, not total runtime heap,
allocation success, throughput or a verified maximum-area image. Native partial
reads, callbacks, allocation ABI and concurrently changing/special files remain
outside this profile. The dedicated helper adds no generic formatted dispatcher
or new native API ID; `LoadImage` remains partial.

## Format-preserving PNG file loading

`Image.Formatted.load_png(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)`
is an explicit PNG loader for ordinary, non-changing files. It does not inspect
the filename suffix: `.png`, `.PNG`, mixed case, arbitrary or misleading `.qoi`
names, suffixless paths, spaces, multiple dots and directory-qualified dotfiles
all select the same PNG decoder. No content-based codec fallback, generic
formatted dispatcher or caller-supplied cap is added. Existing Surface dispatch,
other formatted loaders and every memory decoder remain unchanged.

The adapter consists of exactly a dedicated result continuation and the public
wrapper. `Image.file.bytes(path, Image.file.limit(RasterFile{}))` supplies the
continuation with bytes or a load error, never an open File. Load errors are
preserved; complete bytes go to unchanged `Image.Formatted.decode_png`, whose
result is wrapped once by `Image.file.decoded`. PNG file selection is explicit,
even though the native `.png` dispatch belongs to stb's shared content-sniffing
family and can decode non-PNG payloads. Those native successes do not enlarge
this dedicated PNG contract.

### Bounds, sequencing and typed errors

The shared raster-file cap is **1,048,576 encoded bytes, inclusive**, independent
of the filename. PNG's unchanged memory decoder separately enforces the same
encoded cap, including ignored tails after IEND, and an inclusive
**67,108,864-byte filtered-stream cap**. File admission is an earlier IO check;
it neither introduces nor enlarges either memory limit. These are encoded and
filtered-size bounds, not total-heap, maximum-area or allocation-success guarantees.

1. Open the path before interpreting its contents. Open errors retain exact
   `ImageFileError{code, message}` even for misleading or unsupported suffixes.
   An open failure acquires no handle to close.
2. Obtain its size. Successfully reported sizes above the raster cap through
   **4,294,967,295** return `ImageDecodeError{UnsupportedImageSize{}}` before any
   payload read. Pinned Base rejects larger host sizes with the overflow file
   error, preserving its code and message. Size failures and size rejection
   call `File.close` before returning. Exact-cap files are admitted for reading;
   their contents must still satisfy the PNG decoder.
3. Perform the existing single bounded read of the reported size, then call
   `File.close` before processing its result. Read errors preserve Base's exact
   code/message. Short or long returned lists yield
   `ImageDecodeError{TruncatedImageData{}}` before decoding. There is no retry or
   streaming loop. A physically truncated file whose reported size is read in
   full instead reaches PNG decoding: truncated PNG structures produce
   `InvalidImageHeader`, rather than the file reader's `TruncatedImageData`.
4. Decode complete bytes through the unchanged checked PNG adapter and wrap its
   typed error exactly once. The whole-input byte/count walk precedes header
   parsing. An invalid U32 value yields `InvalidImageByte`; a valid first value
   beyond the encoded cap yields `UnsupportedImageSize`. An invalid value at
   that same excess position takes precedence, while values after an already
   detected cap error are not inspected. Ordinary files contain only bytes;
   nonbyte U32 values are continuation-only test controls.
5. Invalid signatures, chunk structures and unsupported IHDR fields yield
   `InvalidImageHeader`. Structurally accepted zero/oversized dimensions and
   excessive filtered capacity yield `UnsupportedImageSize`, before inflation.
   Invalid framing/DEFLATE, filters, exact raster lengths and palette indices
   yield `InvalidImageStream`. Complete, byte-valued tails after IEND remain
   ignored after whole-input validation.

Close ordering describes calls, not OS-close success: Base's C implementation
discards the close result and JavaScript catches close exceptions. No new
close-error variant or universal closure guarantee is provided. Injected
size/read/short/long controls acquire real handles but inject a stage result;
they are not actual concurrent-short-read demonstrations.

### Preserved native storage and ownership

Success returns one affine `Image.Formatted` owner with dimensions **1..4096**,
one implicit mip level and exact native reduced 8-bit storage:

| PNG structure | Native format | Component order |
|---|---|---|
| Grayscale without tRNS | **1** | G |
| Grayscale with tRNS, or gray-alpha | **2** | G,A |
| RGB or palette without tRNS | **4** | R,G,B |
| RGB or palette with tRNS, or RGBA | **7** | R,G,B,A |

Channel promotion follows accepted PNG structure, independently of opacity or
whether a transparency key matches. Empty, all-opaque and unused-entry palette
tRNS still promote to RGBA. Promotion remains sticky through a later accepted
PLTE, though that PLTE replaces colors and resets palette alpha. Existing-alpha
images retain alpha channels even when opaque. Full 16-bit tRNS comparisons
precede high-byte reduction; packed grayscale and indexed samples retain their
existing expansion rules. All checked filter/Adam7/chunk rules and native-default
CgBI raw DEFLATE without additional BGR conversion or unpremultiplication are
inherited from the [memory contract](PNG.md#format-preserving-png-memory-loading).
CRC and Adler quirks are unchanged, including completed streams without Adler.

Export consumes the owner and returns exactly `width*height*channels` row-major
component bytes, with no storage padding. Logical packed words have zero unused
high bits for formats 1/2/4. Point reads retain ownership for accepted and rejected
coordinates. The consuming Surface bridge matches existing normalized RGBA8 PNG
output. Failure returns no partial image or open File. Native mipmaps are measured
as one by the reference; candidate mipmaps are an implicit type contract.

### PNG file verification boundary

The [source-scoped PNG-file evidence](evidence/png-formatted-files.json) passes
on local Linux x86-64 CPU-one-thread, CPU-two-thread and server-side JavaScript.
The fresh isolated native archive explicitly enables PNG and all eight required
raster-alias macros, with checked CMake/compiled definitions and pinned source,
compiler/archive and clean-loader child receipts. Tiny structural-channel,
full-width-transparency and native-default CgBI vectors qualify the reference
before broad input execution. Native admission independently scans actual PNG
signature/chunks, bounded DEFLATE, filters and palette indices. Malformed,
oversized, foreign-codec and special-file controls remain candidate-only.

The corpus contains **370 accepted files / 86,119 pixels**, retaining all
**230 PNG memory streams / 85,979 pixels** byte-for-byte plus **140 one-pixel
filename variants** across all four native output layouts. It retains all
**208 memory controls** unchanged: **132 byte-valued** controls become files and
**76 nonbyte U32** controls remain continuation-only. The nested historical
**193 accepted streams / 31,677 pixels and 39 controls** also remain unchanged.
The resulting **143 file controls plus 76 continuation controls** are distinct
from replay-parser mutation tests. Lower/upper raster aliases, mixed/unsupported
suffixes, suffixless/trailing-dot names, spaces, multiple dots, directory-qualified
dotfiles and dotted parents exercise independent file selection.

The native oracle uses **326 actual `LoadImage` calls** and **44 explicit
`LoadFileData` plus `LoadImageFromMemory(".png")` calls**. Its **740 primary
observations** capture **207,017 native raw bytes** before **344,476 separately
normalized bytes**. The reference measures dimensions, format and
`image.mipmaps == 1`; candidate mipmaps remain an implicit owner-type contract.
Native `.png` dispatch belongs to stb's shared sniffing family, so native success
on another codec would not establish this dedicated PNG contract.

Each candidate lane checks **2,846 primary observations / 1,531,636 bytes**,
including **828,068 raw and 703,568 normalized bytes**. Raw export, retained
point/high-bit ownership checks, consuming Surface bridges, and applicable
normalized/generic routes use distinct public reopens. Factory observations
reconstruct the native byte vector after a separate successful public reopen;
they are **not a second direct comparison of loader-exported bytes**. Raw
export/import round trips instead reconstruct the reopened loader's exported
bytes. All **24 native and 90 candidate partitions** are ordered and exhaustive,
with at most **32 actions / 196,608 generated UTF-8 bytes** per partition. The
largest candidate source is **138,804 bytes**; the largest native source is
**12,533 bytes**.

The boundary gate emits **1,209 records / 1,003 compared bytes** per lane:
eight synthetic checks, **100 cycles over twelve acquired-handle paths** under
`RLIMIT_NOFILE=64`, then a final valid load. The paths include all four native
formats, checked decode failure, populated-directory/read failure, cap rejection,
U32-size overflow and injected size/read/short/long-result stages. Exact Base
code/messages survive the injected failures. The local directory failure occurs
at read with code 21 (`Is a directory`). Every boundary frame and terminal is
retained and independently replayed. This is finite leak detection and
source-ordered close-call evidence, not proof of OS-close success or actual
concurrent short-read behavior.

Four separate sparse records cover **1,048,577 bytes** with ordinary/misleading
suffixes, **268,435,456 bytes**, and **4,294,967,296-byte** Base-size overflow.
Sparse holes are never loaded or hashed. An accepted **1,048,576-byte** PNG has
its own raw/normalized native observation and a fully checked ignored byte tail.
Its format-4 pixel is `[13, 74, 135]`; each candidate lane emits **six exact-cap
records / 20 compared bytes**. These resource records are separate from the
primary totals above.

Compilation is excluded from runtime RSS measurement. Post-run acceptance
ceilings are **256 MiB** for boundary/sparse runs and **1 GiB** for exact-cap
reads. These are measured acceptance criteria, not live allocation limits:

| Lane | Boundary RSS / seconds | Sparse RSS / seconds | Exact-cap RSS / seconds |
|---|---:|---:|---:|
| CPU-one-thread | 9,830,400 / 0.581 | 9,830,400 / 0.436 | 27,299,840 / 0.722 |
| CPU-two-thread | 9,830,400 / 0.597 | 9,830,400 / 0.448 | 27,303,936 / 0.696 |
| JavaScript | 112,336,896 / 0.837 | 52,514,816 / 0.509 | 247,644,160 / 1.549 |

RSS units are bytes. The **2,708.808-second** focused gate is a verification
duration, not a performance benchmark. Independent complete-record replay
verifies **429 command receipts and 2,699 source/artifact seals**, every primary
and resource frame, exact scalar/framing/partition/lane presence, and all nine
fd64/RSS receipts. It rejects **121 adversarial replay mutations**. Replay uses
sealed source/fixture recipes without harness comparators and does not rerun
native, compiler or candidate processes.

The separate same-source regression matrix passes **28 ordered serial stages**,
**966 Python tests without skips** and all **177 scoped laws** with the complete
`All terms check.` verdict, plus syntax/project/API/whitespace checks. Independent
regression replay verifies **45,105 formatted records / 19,789,812 bytes across
three lanes**, **33 resource runs**, **1,603 inner and 28 terminal outer command
receipts**, and **11,177 distinct artifact hashes**. These totals exclude the
focused PNG-file gate. Canonical replay covers every **261 scenarios / 40,101
words, 333 QOI bytes and 23 palette words per lane**, including optional palette
counts and alpha borders. Nine older gates and canonical ancillary checks retain
report/source/artifact evidence rather than complete raw runtime replay. QOI
closure retains its final image and terminal only; internal iterations were not
emitted and are not independently replayed. See the detailed
[verification boundary](VERIFICATION.md#format-preserving-png-file-loading-2026-10-04).

These results bind the frozen runtime snapshot based on `7dcfdb98`; all **470
frozen source files** were checked unchanged during the independent audit.
Later documentation/CI-tree validation is recorded separately, without rewriting
runtime receipts or claiming an unrun integrated test count. The predecessor's
84-gate/eight-worker run did not fully qualify because its macOS formatted worker
hit the 120-minute limit. The repaired **84-gate/ten-worker** predecessor at
`9cb5a7e7cabdb76005a76119616e33ca9516d73b` passes
[Checks](https://github.com/jonathanperis/jonlib/actions/runs/37179587100) and
[Conformance](https://github.com/jonathanperis/jonlib/actions/runs/37179587107).
That CI-only change preserves runtime sources and does not qualify this PNG-file
increment. New **85-gate/twelve-worker exact-tip hosted qualification remains
pending**.

```sh
python3 tools/png_file_probe.py --reference-env clean-loader \
  --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 -m unittest discover -s tests -p test_png_file_harness.py -v
```

Only partial `raylib:function:LoadImage` scope expands; no API completes and the
`LoadImageFromMemory` domain does not change. Generic formatted/float dispatch,
additional codecs, nondefault stb flags, callbacks, concurrent/special files,
native pointer/allocation ABI and OOM parity, OS-close failure reporting,
maximum-area allocation, representative performance and full integration remain
open. GPU/Metal file IO, Windows/browser/big-endian and every platform without
fresh file-specific execution remain unqualified.


## Format-preserving PNM file loading

`Image.Formatted.load_pnm(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)`
is an explicit binary P5/P6 loader. It does not inspect or interpret the suffix:
`.pgm`, `.ppm`, uppercase/mixed-case names, `.pnm`, `.qoi`, arbitrary suffixes,
suffixless names, spaces, multiple dots and directory-qualified dotfiles all
select the same PNM codec. It neither sniffs another codec nor falls back to the
generic Surface dispatcher. Existing generic suffix/content rules are unchanged.

The wrapper consists of a dedicated continuation around the existing
`Image.file.bytes` boundary and `Image.Formatted.decode_pnm` adapter. It shares
`Image.file.limit(RasterFile{})`: **1,048,576 encoded bytes, inclusive**. The cap
is independent of the filename, including misleading `.qoi` names. It is an
encoded-input bound, not a heap, image-area or allocation-success guarantee.

Operation/error precedence is fixed:

1. Open the path. Missing paths, including unsupported or misleading suffixes,
   retain `ImageFileError{code, message}`; no suffix rejection precedes opening.
2. Obtain size. Successfully reported sizes greater than the raster cap through
   U32_MAX return `ImageDecodeError{UnsupportedImageSize{}}` before any payload
   read. Pinned Base size rejects files above 4,294,967,295 bytes with the host
   overflow file error. Both size failures and size rejections close the handle.
3. Perform the existing single bounded read. Call `File.close` before processing
   its result. Read errors preserve the original code/message. Short or long
   returned lists relative to the reported size yield
   `ImageDecodeError{TruncatedImageData{}}`, without decoding or retrying.
4. Decode complete bytes using the unchanged formatted PNM adapter, wrapping its
   exact error once as `ImageDecodeError{error}`. Empty/bad headers, invalid
   maxval or malformed delimiters return `InvalidImageHeader`; valid-header
   unsupported dimensions return `UnsupportedImageSize`; incomplete raster
   returns `TruncatedImageData`. Invalid U32 byte values are only internal-stage
   controls, because ordinary byte files cannot contain them. PNM does not emit
   `InvalidImageStream`, although the shared wrapper preserves that error.

Success returns one affine owner: native P5 grayscale **1** or P6 RGB888 **4**,
width/height 1..4096 and one implicit mip level. Export yields exactly
`width*height*channels` row-major bytes, without padding. Logical grayscale
words have zero high 24 bits; RGB words have a zero high byte. Threaded point
reads preserve ownership on accepted and rejected coordinates. Conversion and
export consume the owner. Failure returns no partial image or open file.

The existing [PNM parsing and sample profile](PNM.md) is unchanged: P5/P6 magic
determines channels, maxval 1..65535 selects sample width, samples are unscaled,
exactly one whitespace delimiter is consumed and complete raster plus valid
ignored tails is required. Wide samples retain the second stored byte in this
pinned little-endian native profile. Output is always reduced 8-bit storage,
never source 16-bit depth. ASCII P1..P3 and binary PBM P4 remain unsupported.

Close calls are ordered, not promises of OS-close success: Base ignores close
errors and exposes no new error variant. Synthetic size/read controls acquire
real handles but inject the stage result; they are not actual concurrent
short-read demonstrations. Ordinary low-descriptor repetition detects leaks in
those exercised paths without proving universal closure. Concurrent/changing or
special files, callbacks, original native allocation ABI, big-endian behavior,
OOM parity, other platforms and full integration/performance remain gaps.

### PNM file reconstruction verification

The [reconstructed report](evidence/pnm-formatted-files.json) is a
fresh run against this exact local source, distinct from the unavailable old
PNM-file run. The matching recovered proof/README texts are historical source
recovery, not runtime evidence. The primary matrix preserves all 96 prior
accepted PNM streams and adds 60 one-pixel suffix/channel/depth combinations:
**156 accepted files / 64,542 pixels**, with **132 actual LoadImage paths** and
**24 explicit LoadFileData + LoadImageFromMemory(".ppm") paths**. Only complete,
independently safety-checked assets reach native. All **74 malformed, size and
file-error controls** remain candidate-only.

Every native observation checks actual dimensions, mipmaps, format and raw byte
count before a separate RGBA8 normalization. Candidate metadata uses its implicit
single-mip contract. Additional reopened observations check high-bit invariants,
threaded point ownership, the Surface bridge, explicit normalized PNM and generic
Surface/profile regressions. Strict framing requires complete ordered records,
exact fields/types, 0..255 byte chunks and exact lengths; extra/truncated output
fails. No expected bytes are computed by the Python safety parser.

A separate accepted **exact-cap** P5 file has one pixel plus a fully validated
ignored tail. It receives its own native raw observation and public file load.
Sparse cap+1, misleading-suffix cap+1, 256 MiB and U32-overflow controls distinguish
pre-read rejection and file overflow. Each CPU-one-thread, CPU-two-thread and
JavaScript lane performs **100 cycles at RLIMIT_NOFILE=64** across ten acquired
handle paths. Eight synthetic checks plus the final independently verified valid
load make **1,009 individually framed records per lane**, followed by a strict
terminal. Sparse/closure RSS must stay below 256 MiB and exact-cap full-read RSS
below 1 GiB; these are post-run acceptance ceilings, not live heap limits or
performance claims. Compilation is measured separately from runtime RSS.

The gate builds a fresh isolated native archive, explicitly enables PNM and
verifies actual CMake/compile definitions. Native endian/format qualification,
compiler/archive hashes, clean-loader child receipts and source/output sealing
are required. The Python parent loader context is preserved. No stale archive
or previous passed report can establish success. The exact-commit hosted CI and
GPU/Metal file IO remain unqualified.


The fresh final-source run passes all three lanes: **626 observations / 129,072
bytes per lane**, including **120,634 primary native-format bytes** observed
before normalization. Native normalized outputs separately total 258,168 bytes.
The whole focused gate took **642.935 seconds**. Runtime measurements (separate
from compilation) are:

| Lane | Closure RSS / seconds | All-sparse RSS / seconds | Exact-cap RSS / seconds |
|---|---:|---:|---:|
| cpu-1 | 9,568,256 / 0.410 | 9,568,256 / 0.265 | 27,156,480 / 0.342 |
| cpu-2 | 9,568,256 / 0.322 | 9,568,256 / 0.254 | 27,144,192 / 0.337 |
| javascript | 96,501,760 / 0.379 | 51,593,216 / 0.284 | 166,961,152 / 0.505 |

RSS units are bytes. These results qualify the measured ordinary-file cases only.
The [obligation matrix](PNM-FILE-RECONSTRUCTION.md) records recovered versus
reconstructed source, the different test organization and explicit remaining
limits; no equivalence to lost test source is inferred from test counts.

```sh
python3 tools/pnm_file_probe.py --reference-env clean-loader --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 -m unittest discover -s tests -p test_pnm_file_harness.py -v
```

## Format-preserving TGA file loading

`Image.Formatted.load_tga(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)`
is an explicit TGA loader for ordinary, non-changing files. Filename suffixes
are not inspected: `.tga`, `.TGA`, `.TgA`, arbitrary or misleading suffixes such
as `.qoi`, suffixless names, spaces, multiple dots and directory-qualified
dotfiles all select the same TGA decoder. No content-based codec dispatch,
fallback or caller-supplied cap is added. Generic Surface suffix/content
selection and all existing PNM, QOI and TGA memory APIs remain unchanged.

The wrapper has the same two-function IO shape as `Image.Formatted.load_pnm`:
`Image.file.bytes(path, Image.file.limit(RasterFile{}))` supplies a dedicated
continuation with bytes or a load error, never an open File. The continuation
preserves load errors or calls `Image.Formatted.decode_tga`, adapting its result
through `Image.file.decoded`. The shared cap is **1,048,576 encoded bytes,
inclusive**, regardless of filename. No shared reader or decoder contract is
enlarged.

Operation/error precedence is fixed:

1. Open the path. Failures retain `ImageFileError{code, message}`; even missing
   paths with unsupported or misleading suffixes reach this stage without
   prior suffix rejection. An open failure acquires no handle to close.
2. Obtain size. A successfully reported size above the raster cap through
   **4,294,967,295** returns `ImageDecodeError{UnsupportedImageSize{}}` before any
   payload read. Sizes above U32_MAX retain the pinned Base overflow
   `ImageFileError{code, message}` instead. Size failures and size rejections
   call `File.close` before returning. The exact cap is admitted for reading;
   acceptance of the bytes still depends on the TGA decoder.
3. Perform the existing single bounded read for the reported size. Call
   `File.close` before processing its result. Read errors preserve Base's code
   and message. Short or synthetic long returned lists relative to the reported
   size return `ImageDecodeError{TruncatedImageData{}}` before decoding. There
   is no retry or streaming loop. A physically truncated file whose actual
   reported size is fully read reaches the decoder instead.
4. Decode the complete bytes using `Image.Formatted.decode_tga`, wrapping the
   exact decoder error once as `ImageDecodeError{error}`. Empty, incomplete or
   unsupported headers return `InvalidImageHeader`; otherwise unsupported
   dimensions return `UnsupportedImageSize`; missing required ID/palette/
   sample/packet data returns `TruncatedImageData`; an RLE packet count that
   exceeds the remaining image returns `InvalidImageStream`. Header validation
   precedes size, then palette loading and pixel allocation. The memory
   decoder checks every supplied value, including ignored tails, as a byte
   before header validation. `InvalidImageByte` is retained by the adapter but
   requires an internal-stage control, because ordinary files supply only
   0..255 values.

Success returns one affine `Image.Formatted` owner with width/height **1..4096**,
one implicit mip level and native grayscale **1**, gray-alpha **2**, expanded
RGB888 **4** or RGBA8888 **7** storage. Export contains exactly
`width*height*channels` top-down row-major bytes, excluding backing-array padding.
Grayscale words have zero high 24 bits, gray-alpha zero high 16 bits and RGB888 a
zero high byte. Point reads preserve ownership for accepted and rejected
coordinates; export and the Surface bridge consume the owner. Failure returns
no partial image or open File. Conversion and disposal use the existing
[formatted owner API](FORMATS.md).

The complete [TGA parsing and output profile](TGA.md) is inherited unchanged.
Direct raw/RLE types 2/3/10/11 use their checked 8/15/16/24/32-bit sample rules;
indexed types 1/9 use 8/16-bit indices and output channels selected from palette
depth, independently of index width. RGB555 expands through integer arithmetic
into format 4. Gray-alpha and BGRA keep zero alpha. ID skipping, vertical
orientation, ignored horizontal-origin/alpha-count bits, palette-start byte
skipping, entry-zero fallback, cross-row RLE and valid ignored tails retain the
memory decoder's behavior. Explicit TGA selection never redirects a non-TGA
payload to another codec based on its signature.

Close ordering describes calls, not OS-close success: pinned `Base.File.close`
returns `IO(Unit)`, its C implementation discards the close result and its
JavaScript implementation catches exceptions. No close-error variant is added.
Synthetic size/read controls can exercise stages using real acquired handles,
but are not observations of actual concurrent short reads. Low-descriptor
repetition can detect leaks in exercised paths without proving universal
closure.

The encoded cap is not a maximum decoded-area, total-heap, allocation-success or
performance guarantee; compressed RLE input can represent substantially more
pixel storage. Concurrent/changing or special files, callbacks, native pointer/
allocation ABI and OOM parity, additional platforms and full integration/
resource/performance coverage remain gaps. This dedicated helper expands only
the existing partial `LoadImage` mapping, adds no generic formatted dispatcher
and completes no native API.

### TGA file verification

The [new source-scoped report](evidence/tga-formatted-files.json) records a passing
local Linux x86-64 CPU-one-thread/CPU-two-thread/JavaScript gate: **225 accepted
files / 61,913 pixels**, including all 169 unchanged memory streams and 56 tiny
filename variants. The native oracle uses **197 actual `LoadImage` calls** and
**28 `LoadFileData` plus `LoadImageFromMemory(".tga")` explicit-selection calls**.
Its **450 primary records** retain **155,740 raw format-1/2/4/7 bytes** before
**247,652 separately normalized bytes**. A separate valid exact-cap 1 MiB file
has its own native raw/normalized observation; its complete ignored byte tail
is validated. Qualified dotfiles and parent-directory dots obey pinned native
whole-path last-dot rules; a literal whole-path `.tga` remains distinct.

Each lane checks **1,283 primary observations / 854,352 bytes** in 41 complete
ordered partitions. Every accepted public formatted load is independently
reopened for raw export, point/high-bit ownership checks and the consuming
Surface bridge. Explicit normalized byte loading and applicable generic Surface
routes are separate observations, not an invented `Surface.load_tga` API.
**154 candidate-only controls** preserve all 144 byte-safe memory controls and
add other-codec, missing, directory, sparse-cap and U32-overflow cases. No
malformed, oversized or special control enters the accepted native TGA oracle.

The boundary gate emits **1,209 strict records**: eight synthetic checks, 100
cycles over 12 real acquired-handle paths, then an independently checked final
valid load. All four successful layouts are covered. Injected read/size errors
and short/long results use actual opened handles and check exact code/message
preservation; these are internal-stage controls, not observed concurrent reads.
Four separate sparse controls and four exact-cap load/owner/bridge/normalized
observations also pass per lane. Process-group cleanup prevents timed-out
compiler/runtime descendants from surviving, without increasing work timeouts.

Compilation is separate from runtime RSS measurement. Fixed acceptance ceilings
are 256 MiB for sparse/closure and 1 GiB for exact-cap reads; these are post-run
measurements, not live allocation bounds or performance guarantees:

| Lane | Closure peak RSS bytes | Sparse peak RSS bytes | Exact-cap peak RSS bytes |
|---|---:|---:|---:|
| CPU-one-thread | 9,568,256 | 9,568,256 | 27,246,592 |
| CPU-two-thread | 9,568,256 | 9,568,256 | 27,275,264 |
| JavaScript | 106,627,072 | 46,215,168 | 268,668,928 |

Independent complete-byte replay verifies every primary/resource/closure frame,
all 1,643 seals, 187 successful owned/reaped command receipts, native compiler/
alias/clean-loader provenance and all nine fd64/RSS receipts. Sixteen adversarial
parser replays are rejected. Source-order evidence records the unchanged
pre-read rejection and close-before-decode calls without claiming OS-close
success or an IO theorem.

All affected formatted and canonical regressions pass on the same unchanged
library source. Historical memory and PNM evidence is preserved separately.
Inherited Surface TGA and generic dispatch harnesses have fresh source/report/
exit checks, but do not retain full stdout for independent full-record replay.
The [81-gate hosted run](https://github.com/jonathanperis/jonlib/actions/runs/37145573468)
for exact published TGA-file commit `08dd860ebd24c8d1f49eb130d848764723e1f5c7`
passes Checks, all four workers, both aggregates and all four distinct nonempty
artifacts. This historical result does not qualify the subsequent BMP memory
increment; there is no new GPU/Metal, Windows/browser, big-endian or maximum-area result.
The BMP-memory increment now has its own passing
[82-gate hosted run](https://github.com/jonathanperis/jonlib/actions/runs/37152040429)
at `82a81b12e61ede4ec2d9901baddd4bf773651a5d`, including Checks, all six workers,
both aggregates and six distinct nonempty artifacts. Neither historical result
qualifies the new BMP-file increment; its exact-tip 83-gate hosted qualification
remains pending.

```sh
python3 tools/tga_file_probe.py --reference-env clean-loader --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 -m unittest discover -s tests -p test_tga_file_harness.py -v
```

## Format-preserving BMP file loading

`Image.Formatted.load_bmp(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)`
is an explicit BMP loader for ordinary, non-changing files. It ignores filename
suffixes: `.bmp`, `.BMP`, `.BmP`, arbitrary or misleading suffixes such as `.qoi`,
suffixless names, spaces, multiple dots and directory-qualified dotfiles all
select BMP. It does not sniff or retry another codec. Generic Surface
suffix/content dispatch and every existing memory decoder retain their contracts.

Like the dedicated PNM/TGA loaders, it has exactly two IO functions. The public
entry passes `Image.file.bytes(path, Image.file.limit(RasterFile{}))` to
`Image.Formatted.bmp.file.loaded`. That continuation receives bytes or a load
error, never an open File. It propagates failures unchanged or adapts
`Image.Formatted.decode_bmp` through `Image.file.decoded`. The shared raster cap
is **1,048,576 encoded bytes, inclusive**, regardless of filename. No shared
reader, decoder or format-conversion implementation changes are required.

Operation/error precedence is fixed:

1. Open the path. Failures preserve `ImageFileError{code, message}`. Even missing
   paths with unsupported or misleading suffixes reach opening without prior
   suffix rejection. No handle is acquired on open failure.
2. Obtain size. A successfully reported size above the raster cap through
   **4,294,967,295** returns `ImageDecodeError{UnsupportedImageSize{}}` before any
   payload read. Pinned Base reports a host overflow file error for sizes above
   U32_MAX; this remains `ImageFileError{code, message}`. Size failures and size
   rejection both call `File.close` before returning. The exact cap is admitted
   for reading, but the bytes must still satisfy the unchanged BMP decoder.
3. Perform the existing single bounded read of the reported size. Call
   `File.close` before processing the read result. A read failure retains Base's
   code/message; short or synthetic long returned lists relative to the reported
   size yield `ImageDecodeError{TruncatedImageData{}}` before decoding. There is
   no retry or streaming loop. A physically truncated file whose actual reported
   length is read completely instead reaches the decoder.
4. Decode with the unchanged `Image.Formatted.decode_bmp`, wrapping each exact
   error once as `ImageDecodeError{error}`. Full-list byte validation comes first,
   including ignored fields, gaps, padding and tails. Next, incomplete base
   headers or unsupported base fields, planes, bit depth, compression or offset
   return `InvalidImageHeader`. Once those checks pass, unsupported width or
   height returns `UnsupportedImageSize` **before extended-header completion or
   effective-mask validation**. With supported dimensions, incomplete extended
   headers or invalid effective masks return `InvalidImageHeader`. Required
   palette and effective-raster completeness then precede index decoding:
   incomplete required data returns `TruncatedImageData`, and an index outside
   the loaded palette returns `InvalidImageStream`. Thus unsupported dimensions
   take precedence over incomplete or invalid masks; the controls
   `bad-size-before-incomplete-masks` and `bad-size-before-invalid-mask` both
   return `UnsupportedImageSize`. Ordinary files supply only 0..255 bytes, so
   `InvalidImageByte` is an internal-stage control rather than an ordinary-file
   payload case.

Success returns one affine owner with width and height **1..4096**, one implicit
mip and native RGB888 **4** or RGBA8888 **7**. Export consumes it and returns
exactly `width*height*channels` top-down row-major R,G,B[,A] bytes, excluding
backing-array padding. RGB888 logical words have a zero high byte. Point reads
retain the exact owner on accepted and rejected coordinates; export and the
Surface bridge consume it. Failure returns no partial image or File owner.
Conversion and disposal use the existing [formatted owner API](FORMATS.md).

The complete [BMP memory profile](BMP.md#format-preserving-bmp-memory-loading)
is inherited unchanged: CORE indexed/RGB24 and INFO/56/V4/V5 headers;
1/4/8-bit indexed, RGB555/24/32 and checked 16/32-bit bitfields; native palette
counts and CORE bias/remainders; ignored palette/embedded masks; external-mask
placement; V4/V5 defaults; native highest-bit/population mask alignment and
replication; bottom-up/top-down orientation; doubled true-color gaps, row
padding and valid ignored tails. Effective alpha layout determines channels
before pixel decoding and alpha repair. `BI_RGB` 32-bit all-zero alpha repair
preserves RGBA metadata, while explicit alpha masks retain zero alpha. The
native 24-bit/`0xff000000` special case remains unreachable under this domain.
No floating `ImageFormat` conversion or observed-opacity heuristic is added.

Close ordering concerns calls, not OS-close success: pinned `Base.File.close`
returns `IO(Unit)`, its C implementation discards the close result and its
JavaScript implementation catches close exceptions. There is no close-error
variant or successful-close guarantee. Synthetic size/read controls may use
real acquired handles but cannot establish actual concurrent short-read behavior;
low-descriptor repetition can detect leaks only in the paths it exercises.

The encoded cap is not a maximum decoded-area, total-heap, allocation-success or
performance guarantee. Concurrent/changing or special files, callbacks, native
pointer/allocation ABI and OOM parity, GPU/Metal file IO, additional platforms
and full integration/resource/performance remain open. This adds no generic
formatted dispatcher and broadens only partial `raylib:function:LoadImage`;
`LoadImageFromMemory` and all completed API counts are unchanged.

### BMP file verification

The [new source-scoped report](evidence/bmp-formatted-files.json) records a passing
local Linux x86-64 CPU-one-thread/CPU-two-thread/JavaScript gate: **294 accepted
files / 39,259 pixels**. All **224 prior accepted memory streams** remain
byte-for-byte unchanged, with **70** additional one-pixel filename variants
covering both native output layouts. The native oracle uses **272 actual
`LoadImage` calls** and **22 `LoadFileData` plus `LoadImageFromMemory(".bmp")`
explicit-selection calls**. Its **588 primary records** capture **132,612 raw
format-4/7 bytes** before **157,036 separately normalized bytes**. Native success
checks actual dimensions, `mipmaps==1`, format and raw byte length; candidate
single-mip metadata follows the owner's implicit type contract rather than a
stored or measured mip-count field.

The fresh isolated native archive qualifies little-endian storage and all
**12 tiny RGB/RGBA/effective-alpha routing vectors** before the broad oracle.
Its actual CMake cache and compiled definitions enable all **eight** required
raster alias macros: BMP, PNG, TGA, JPG, GIF, PIC, PNM and PSD. Whole-path last-dot
qualification independently distinguishes a literal `.bmp`, `dir/.bmp` and
`dir.bmp/leaf`; filename routing is checked against those native rules. The
alias build does not expand Jonlib's supported payload codecs. Only complete,
independently safety-checked BMP assets enter the accepted native oracle.

Each candidate lane checks **2,184 primary observations / 602,588 bytes** in
**69 complete ordered partitions**, at most **32 actions** and **196,608 generated
UTF-8 bytes** each; the largest generated partition is **26,853 bytes**. Every
accepted public formatted load is independently reopened for raw export,
point/high-bit ownership checks and the consuming Surface bridge. Explicit
normalized byte loading and applicable generic Surface/profile routes remain
separate observations. **229 file controls plus 379 synthetic/internal controls
make 608 candidate-only controls**; malformed, oversized and special controls
never enter the accepted native oracle. The synthetic controls include values
that ordinary byte files cannot contain and do not broaden the public contract.

The boundary gate emits **1,009 strict records / 703 compared bytes** per lane:
eight synthetic checks, **100 cycles over ten acquired-handle paths** under
`RLIMIT_NOFILE=64`, then an independently checked final valid load. The repeated
paths include RGB and RGBA success, decode failure, directory/read failure,
pre-read cap rejection, U32-size overflow and injected short/read-error/
size-error/long-result stages. Injected stages use real acquired handles and
check exact error code/message preservation; they are not observations of
actual concurrent short reads. The observed local populated-directory failure
occurs at read with code 21 (`Is a directory`). Every boundary frame and the
strict terminal are retained and independently replayed.

Four separate sparse controls cover cap+1, misleading-suffix cap+1, a larger
sparse file and Base U32-size overflow. Each lane additionally passes four
exact-cap raw/owner/bridge/normalized-Surface records totaling **14 bytes**. The
accepted **1,048,576-byte** BMP has its own native raw/normalized reference and a
fully validated ignored byte tail; its format-4 pixel is `[13, 92, 171]`. These
observations establish exact-cap admission for the exercised file, without
turning the encoded cap into a maximum-area or heap guarantee.

Compilation is separate from runtime RSS measurement. Fixed post-run acceptance
ceilings are **256 MiB** for boundary/sparse runs and **1 GiB** for exact-cap
reads. They are measured acceptance criteria, not live allocation limits,
maximum-area results or performance guarantees:

| Lane | Boundary RSS / seconds | Sparse RSS / seconds | Exact-cap RSS / seconds |
|---|---:|---:|---:|
| CPU-one-thread | 9,699,328 / 0.389 | 9,699,328 / 0.341 | 27,250,688 / 0.576 |
| CPU-two-thread | 9,699,328 / 0.398 | 9,699,328 / 0.340 | 27,262,976 / 0.563 |
| JavaScript | 101,462,016 / 0.451 | 50,315,264 / 0.370 | 270,422,016 / 1.057 |

RSS units are bytes. The complete focused gate took **1,658.848 seconds**;
that is gate elapsed time, not an application benchmark. Independent full-byte
replay verifies all primary, boundary, sparse and exact-cap records, **2,210
source/artifact seals**, **299 exact successful inner command receipts**,
fresh native compiler/archive/alias provenance and all nine fd64/RSS receipts.
The separate outer audit verifies the complete progress/terminal output, exit
status and owned/reaped process group. The replay does not rerun the runtime or
read/hash sparse holes. Nineteen synthetic parser mutation controls are rejected;
these remain separate from the 608 candidate runtime controls.

All affected formatted and canonical regressions also pass against the same
frozen library source. The independent regression audit verifies **5,204
artifacts** and rejects **61 main adversarial controls** plus **16 TGA parser
controls**. It replays complete BMP-memory/export and canonical output, every
TGA/PNM file primary/resource/closure frame, and QOI file primary/retained-resource
frames. Individual repeated QOI closure-loop checks have source/report/exit
evidence only; the older Surface BMP, generic dispatch, FloatRGB raster export,
image-format and color/owner harnesses likewise lack complete retained stdout
for independent full-output replay. Exact boundaries are recorded in
[VERIFICATION.md](VERIFICATION.md#format-preserving-bmp-file-loading-2026-10-03).

The frozen matrix passes **21 serial stages** plus the focused BMP-file gate,
**794 Python tests without skips**, all **158 scoped laws** with the complete
`All terms check.` verdict, and syntax/project/API checks. The separately sealed
final CI/documentation snapshot passes **798 Python tests without skips**, all
158 laws and project/API/syntax checks. Compiled library, probe and oracle
identities remain unchanged. Its independent workflow-preservation check retains
all 82 prior gates and the six-worker aggregates, adding only the new file gate
and precise sparse-artifact exclusions. Final evidence/prose summaries are
checked separately against retained tested metadata to avoid self-referential
receipt hashes. These scoped laws do not establish universal decoder or IO
correctness.

The exact-tip hosted **83-gate** qualification remains pending. Historical TGA
file and BMP memory checkpoints do not qualify this file increment. No new
GPU/Metal IO, macOS/Windows/browser, big-endian, maximum decoded-area/heap,
concurrent/special-file, OS-close-error, native pointer/allocation/OOM or full
integration/performance result is established by this local run.

```sh
python3 tools/bmp_file_probe.py --reference-env clean-loader --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 -m unittest discover -s tests -p test_bmp_file_harness.py -v
```

## Verification

```sh
python3 tools/image_memory_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/image_file_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The memory probe compares 534 native token/content pairs, including 462 successful
images with every dimension and pixel checked, plus five typed invalid controls
on CPU, JavaScript and forced Metal. Runners contain at most 64 observation/control
actions to bound generated IO-chain depth. All batch outputs are concatenated in
order before the complete comparison; each batch's result count is checked too.

The file probe compares 59 native file cases: 58 actual `LoadImage` calls and an
explicit QOI-selection check through the native memory entry point. Cases cover
all supported suffixes, uppercase and cross-extension content, mixed/unsupported
suffixes, aliases, multiple dots, directory-qualified dotfiles,
invalid/empty/missing files, first-frame GIF, raw/RLE PIC, RGB/alpha PSD, 16-bit PPM, packed/indexed/cross-type TGA, BMP bitfields/extended/CORE headers,
and retained explicit-QOI behavior.

Three additional size/read boundaries and 100 success/decode/read/size-error
cycles run under a 64-file-descriptor limit on CPU and JavaScript. Pure contract
checks distinguish suffix-only/mixed-case names and incomplete reads. File IO
evidence is CPU/JavaScript only; the existing memory decoder profiles have their
own forced-Metal evidence.

### Formatted QOI file evidence

The separate [formatted file report](evidence/qoi-formatted-files.json) records
a passing local **Linux x86-64** run on **CPU-one-thread, CPU-two-thread and
JavaScript**, with the pinned Bend overlay, Bun 1.3.12 and a freshly built pinned
native reference. Actual `Image.Formatted.load_qoi` calls cover **135 accepted
ordinary files / 35,657 pixels**, with **126,883 native-format bytes** compared
before normalization. Native routes are **129 actual `LoadImage(path)` calls**
for recognized `.qoi`/`.QOI` paths and **6 `LoadFileData` plus
`LoadImageFromMemory(".qoi", ...)` references** for explicit selection. Each
native success checks actual width/height, format, raw length and `mipmaps==1`;
candidate single-mip metadata follows the owner's contract. Independently
reopened Surface/bridge observations retain the RGBA8 regression boundary.
Together with **69 typed controls**, each lane checks **287 observations /
138,007 bytes** in strictly framed batches of at most 64 actions.

The boundary lane runs **100 sequential cycles under `RLIMIT_NOFILE=64`**,
checking eight paths with acquired handles in every cycle: RGB and RGBA success,
decode failure, directory/read failure, cap rejection, U32-size overflow,
synthetic short-read and synthetic read-failure stage controls. The last two
open a real File but inject the read result, so they are internal-boundary
controls rather than public end-to-end short-read observations. Every cycle
checks its results and consumes successful owners. The lane then performs an
independently checked final valid load and emits a strict terminal marker. The local populated
directory fails at read with code 21 (`Is a directory`). Sparse cap+1 files
use both `.qoi` and misleading suffixes; the 4,294,967,296-byte sparse file
checks the distinct `EOVERFLOW` file error without payload allocation.

Runtime resource receipts are separate from compilation. Values below are
child-process peak RSS in bytes and per-invocation elapsed seconds:

| Lane | Sparse/closure RSS | Sparse/closure seconds | Full-read stress RSS | Full-read stress seconds |
|---|---:|---:|---:|---:|
| CPU-one-thread | 9,568,256 | 0.062 | 27,000,832 | 0.095 |
| CPU-two-thread | 9,568,256 | 0.102 | 27,131,904 | 0.093 |
| JavaScript | 82,685,952 | 0.146 | 161,636,352 | 0.306 |

The separate **1,048,577-byte** full-read stress file reaches
`InvalidImageHeader`, demonstrating that the dedicated wrapper does not reuse
the raster/HDR 1 MiB cap. It is a candidate-only invalid-input test, not a valid
image or native differential case. Sparse/closure runs stay below their fixed
256 MiB RSS acceptance ceiling; full-read stress stays below its separate
1 GiB ceiling. These are post-run measurements, not live memory limits or
performance guarantees; timeouts and the unchanged pre-read guard bound the
exercised workflow. The whole focused gate elapsed time was 193.281 seconds.

The [verification record](VERIFICATION.md#format-preserving-qoi-file-loading-2026-10-02)
retains the exact scoped result. Historical Surface dispatch and
[formatted QOI memory](CODECS.md#format-preserving-qoi-memory-loading) evidence
remain separate. No GPU IO, macOS/Windows/browser qualification, big-endian
target, maximum-area resource, concurrent/special-file, OS-close-error,
generic formatted/float dispatch or full integration/performance coverage is
established by this local file run.
