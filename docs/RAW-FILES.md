# Raw image files

Jonlib reproduces raylib's `LoadImageRaw` header rule and `ExportImage(".raw")`
bytes. `Surface.write_image` also selects RAW for a `.raw` suffix; loading needs
the caller's width, height and format.

| API | Result |
|---|---|
| `Surface.load_raw(path, width, height, format, header_size)` | `IO(Result<&1, &1, Surface.IOError, Surface>)` |
| `Surface.write_raw(image, path)` | `IO(Result<&1, &1, Surface.IOError, Unit>)` |

## Loading

`Surface.load_raw` supports ordinary, non-changing files in formats 1..9.
R32 words are little-endian finite values in `[0,1]`; both zero signs and
positive subnormals are preserved exactly (see [R32.md](R32.md)). R32G32B32
payloads are three little-endian words per pixel (`width*height*12` bytes);
every non-NaN sample is preserved exactly, including signed zero, subnormals
and infinities. Dimensions are 1..4096. The U32 header size plus the required
image bytes must fit a nonnegative signed C int, and the file size must not
exceed 2,147,483,647 bytes. Invalid request parameters are rejected before
opening.

The pinned native header rule:

1. If the file is shorter than the required image bytes, fail.
2. Use a positive header offset only if `header_size + required_bytes <= file_size`.
3. Otherwise read the image from byte zero, even if a nonzero header was requested.

Only the selected payload is read, using bounded `Base.File.read_at`; ignored
headers and tails are never materialized as a whole-file list, and they may
contain arbitrary bytes. Opened handles are closed before the result image is
constructed, including on size and read failures. A short read is rejected
rather than filled with synthetic pixels.

`Surface.IOError` results:

- `DataError{InvalidRequest}`: unsupported dimensions/format or unsafe header arithmetic.
- `DataError{OutOfDomain}`: a complete selected payload contains a sample
  outside the format's domain (R32: negative nonzero, above one, infinity or
  NaN; R32G32B32: NaN); reported after closure. This is Jonlib's
  checked-storage adaptation, not a native rejection.
- `DataError{TruncatedImageData}`: too few file/payload bytes.
- `DataError{UnsupportedImageSize}`: a reported file size exceeds the signed-int bound.
- `FileError{code, message}`: the original Base open/size/read error.

## Exporting

`Surface.write_raw` consumes its owner and writes exactly the native-order
image bytes, without a header or storage padding, then closes the file after
the write result. R32 and R32G32B32 words are written unchanged; open/write
failures are `FileError{code, message}`. The raw float domain and the
JavaScript NaN-representation gap are described in [FLOAT-RGB.md](FLOAT-RGB.md).

## How it is verified

All gates compare exact output against pinned native raylib on the CPU-1,
CPU-2 and JavaScript lanes (see [VERIFICATION.md](VERIFICATION.md)). File IO is
verified on CPU and JavaScript only; no GPU filesystem claim is made.

- **Formats 1..7** (`tools/raw_file_probe.py`, gate `raw-file`): native
  `LoadImageRaw` followed by `ExportImage` is compared with `load_raw` +
  `write_raw` metadata and bytes for all seven formats: exact-fit and
  non-fitting headers, the largest permitted header, ignored tails and
  missing/empty/short inputs; a native export failure is also checked. Typed
  controls cover parameters, a sparse 2 GiB file (never sent to native) and
  read failures, and 100 success/truncation/read-error cycles run under
  `RLIMIT_NOFILE=64`.
- **R32** (`tools/r32_raw_file_probe.py`, gate `r32-raw-file`): native uses
  `LoadImageRaw` and `SaveFileData` only, avoiding incidental float-to-byte
  casts. Cases cover exact-fit headers, ignored invalid headers/tails,
  non-fitting offsets, the largest safe header, all R32 threshold words, a
  33,024-pixel signed-zero/subnormal file, truncation and out-of-domain
  payloads (including a large file whose final word is invalid, checking
  tail-recursive validation). Every successful load is written and reloaded.
  A candidate-only 64 MiB sparse file selects one word at a 32 MiB header
  offset under a 256 MiB runtime-RSS ceiling, guarding against whole-file
  materialization. 100 success/sample/truncation/read/size cycles run under the
  64-descriptor limit.
- **RGB float** (`tools/float_rgb_raw_file_probe.py`, gate `float-rgb-raw-file`):
  load/header cases compare every output file with native loaded storage
  (`SaveFileData`), and some normalized cases also with native
  `ExportImage(".raw")`. Controls cover request, file, truncation, size and NaN
  domains, and a directory write checks the file-error variant. 100
  load/domain/truncation/read/size/write cycles run under the descriptor limit.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only raw-file
```

## Known gaps

Concurrent modification, special-file semantics, native callbacks, wider
parameter/format domains (compressed and half-float layouts, NaN payload
preservation) and full platform/resource coverage.
