# Image codec profiles

## QOI

The QOI implementation is entirely Bend, in `src/qoi.bend`. Its error and
ownership adapters are exposed through `jonlib.bend`:

| API | Contract |
|---|---|
| `Surface.decode_qoi(bytes: +List<U32>)` | Returns `Result<Image.DecodeError, Surface>`; byte values must be 0..255. Accepts valid RGB/RGBA QOI, dimensions 1..4096. |
| `Surface.to_qoi(surface)` | Consumes the Surface and returns immutable encoded bytes. Header channels are 4 and colorspace is 0. |
| `Surface.load_qoi(path)` | Base byte-file IO returning `IO(Result<Image.LoadError, Surface>)`. |
| `Surface.write_qoi(surface, path)` | Consumes the Surface, writes QOI through Base byte IO, and returns the same file-error contract as `write_ppm`. |

Result signatures above abbreviate the explicit affine quantities shown in the
source. Opened files are closed on success, read/write failure, decode failure
and size rejection. File loading rejects sizes greater than **83,886,102 bytes**,
the maximum QOI stream size for the current 4096×4096 Surface profile.

Decoding supports RGB, RGBA, index, difference, luma and run chunks, including
wrapping channel differences, cache collisions and run-boundary handling. RGB
headers are normalized to opaque RGBA8. The reference check performs the same
explicit `LoadImageFromMemory` followed by `ImageFormat(RGBA8)` adaptation.
Original-format metadata and other image codecs remain gaps.

`Image.DecodeError` distinguishes `InvalidImageHeader`, `InvalidImageByte`,
`UnsupportedImageSize`, `TruncatedImageData` and `InvalidImageStream`.
`Image.LoadError` wraps either `ImageFileError{code, message}` or
`ImageDecodeError{error}`. The decoder rejects truncated chunks, runs beyond the
declared pixel count and missing/invalid end markers. It does not reproduce
the C decoder's permissive recovery of some malformed streams.

## Reference and verification

The pinned raylib **`ExportImageToMemory` implements PNG only**. QOI memory
encoding is a Jonlib convenience backing the QOI `ExportImage` mapping; it is
not claimed as coverage of `ExportImageToMemory`.

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
