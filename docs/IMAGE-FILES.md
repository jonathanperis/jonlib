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
