# Raw image-file profiles

## Loading

`Image.Formatted.load_raw(path, width, height, format, header_size)` returns
`IO(Result<&1, &1, Image.RawLoadError, Image.Formatted>)`.

The current profile supports ordinary, non-changing files and byte/integer
formats 1..7. Dimensions are 1..4096. The U32 header size plus required image
bytes must fit a nonnegative signed C int, and the file size must not exceed
2,147,483,647 bytes. Invalid request parameters are rejected before opening.

The loader follows the pinned native header rule precisely:

1. If the file is shorter than the required image bytes, fail.
2. Use a positive header offset only if `header_size + required_bytes <= file_size`.
3. Otherwise read the image from byte zero, even if a nonzero header was requested.

Only the selected payload is read, using bounded `Base.File.read_at`; ignored
headers/tails are not materialized as a whole-file list. Opened handles are
closed before constructing the result image, including size/read failure paths.
A short read is rejected rather than filled with synthetic pixels.

`Image.RawLoadError` distinguishes:

- `InvalidRawRequest`: unsupported dimensions/format or unsafe header arithmetic.
- `TruncatedRawImage`: too few file/payload bytes.
- `RawFileTooLarge`: a reported file size exceeds the profile's signed-int bound.
- `RawFileError{code, message}`: the original Base open/size/read error.

Concurrent modifications, special-file semantics, native callbacks and wider
parameter/format domains remain gaps.

## RGB float files

`Image.FloatRGB.load_raw(path, width, height, header_size)` returns
`IO(Result<&1, &1, Image.RawLoadError, Image.FloatRGB>)` for little-endian format-9
RGB words. It shares the same positional-read boundary, header-fit rule, signed-int
limits and closure behavior as the formatted loader. Required payload size is
`width*height*12`. All non-NaN samples are preserved exactly, including signed zero,
subnormals and infinities. Unsupported NaN payloads return `InvalidRawRequest`
after the file is closed; incomplete payloads return `TruncatedRawImage`.

`Image.FloatRGB.write_raw(image, path)` returns
`IO(Result<&1, &1, Image.FloatRGB.WriteError, Unit>)`:

- `FloatRGBSampleError{image}` retains the original owner for unsupported NaN
  samples, before the output file is opened or truncated.
- `FloatRGBFileError{code, message}` retains the Base open/write error. Valid
  encoded output consumes the source owner and closes its handle on completion.
- Success writes every raw word without normalization or storage padding.

See [FLOAT-RGB-BYTES.md](FLOAT-RGB-BYTES.md) for the raw sample domain and
JavaScript NaN-representation gap.

## Exporting

`Image.Formatted.write_raw(image, path)` consumes its owner and returns
`IO(Result<&1, &1, U32 & String, Unit>)`. It writes exactly the native-order
image bytes, without a header, and closes the file after the write result.
The dedicated operation selects RAW explicitly; generic extension dispatch
is not implemented. The caller retains width, height and format separately.

## Verification

```sh
python3 tools/raw_file_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 tools/float_rgb_raw_file_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

Configure checkouts as described in [README.md](../README.md#requirements).
The probe executes actual `LoadImageRaw`/`ExportImage` calls and compares complete
metadata and exported bytes across all seven formats. Cases include exact-fit
headers, non-fitting headers, the largest permitted header, ignored tails and
missing/empty/truncated inputs. A native export failure is also checked.

Five additional boundary controls exercise typed parameter, oversized-file and
read failures. Each CPU/JS candidate runs 100 success/truncation/read-error cycles
with a 64-file-descriptor limit, catching retained open handles during execution.
Sparse oversized fixtures stay task-owned under `.build/raw-file-probe/` and
are not sent to the native loader or uploaded as artifacts.

File IO evidence is CPU/JavaScript only. The pure format conversion code
has separate forced-Metal evidence; this does not claim GPU filesystem support.

The RGB float gate adds 16 native load/header cases and nine request/file/domain
controls on CPU/JS. Every output file matches native loaded storage; four
normalized cases additionally use native `ExportImage(.raw)`, keeping its
incidental color casts in their defined domain. NaN write rejection preserves
both the owner and an existing output file, while a directory write checks the
file-error variant. One hundred load/domain/truncation/read/size/write cycles run
under the same descriptor limit. Prior byte/integer raw-file gates remain passing.
See [evidence/float-rgb-raw-files.json](evidence/float-rgb-raw-files.json).
