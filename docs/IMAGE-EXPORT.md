# Suffix-selected RGBA8 image export

`Surface.write_image(surface, path)` returns
`IO(Result<&1, &1, Image.ExportError, Unit>)`. It selects PNG, BMP, TGA, QOI or
RAW from the filename and reuses the corresponding native-profile encoder.
This is a scoped mapping of raylib 6.0 `ExportImage`, not a complete export API.

## Selection and ownership

Suffix selection is ASCII case-insensitive: `.png`, `.PNG` and `.PnG` select
the same encoder. The last dot in the **whole path** determines the suffix,
matching `GetFileExtension`. A dot at position zero is not an extension:
the path `.png` is rejected, while `images/.png` is accepted. A suffix must
match completely; `image.png-tail` and `directory.png/no-extension` are rejected.
This differs from the exact lowercase/all-uppercase memory-loading tokens in
[IMAGE-FILES.md](IMAGE-FILES.md). The filename itself is never lowercased.

- `UnsupportedImageExport{surface}` returns the unchanged owned Surface before
  opening any file. Unsupported paths cannot truncate existing output files
- `ImageExportFileError{code, message}` preserves the Base file error. A selected
  encoder consumes its Surface, including on file-open or file-write failure
- Every successfully opened file handle is closed after its write attempt,
  following the existing explicit writers' lifetime contract
- Successful writes replace the file contents. This is not an atomic-write or
  durable-storage guarantee; close failures cannot be observed through Base's
  current `File.close -> IO(Unit)` interface

Typed Base IO outcomes are a language-level adaptation. Native exporters differ
in how they check short writes and close failures (in particular, stb BMP/TGA
writers can ignore them); failing-device/short-write error parity is not claimed.

Inputs are checked Surface owners and ordinary non-NUL paths. RAW exports
native RGBA byte order via `Surface.to_formatted` and the format-7 RAW writer,
not the host byte order of Surface's packed `0xRRGGBBAA` words. Dimensions and
format are not stored in RAW files and must be tracked separately.

## Verification

Run after building the pinned reference with the main conformance command:

```sh
python3 tools/image_export_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

The dedicated gate uses actual native `ExportImage`, compares complete file
bytes and decoded pixels, and exercises suffix rules, rejected-owner retention,
unchanged rejection sentinels, typed IO errors and repeated handle closure on
native CPU and emitted JavaScript. Results are under
`.build/image-export-probe/results.json`. Native math-profile failures in the
aggregate gate are tracked separately in [NATIVE-MATH-PROFILES.md](NATIVE-MATH-PROFILES.md);
a focused export pass does not imply aggregate conformance.

The [checked-in evidence](evidence/image-export-dispatch.json) records 41 complete
files / 3,803 encoded bytes, 686 decoded pixels, 19 rejected owners and 10 open
errors per CPU/JS lane. Each lane additionally runs 1,600 ordinary operations
under a 64-descriptor limit, checking the final closure-file bytes. A separate
zero-file-size-limit run forces 500 post-open writes to fail specifically with
`EFBIG`, checking closure, zero-byte truncated files, and 100 owner-preserving
unsupported requests. These controls use task-owned regular files and cannot
pass merely by exhausting descriptors (`EMFILE`). This verifies Base failure
handling, not equivalence to native exporters' failing-device behavior.

Explicit [formatted BMP export](FORMATTED-BMP-EXPORT.md) separately supports
checked formats 1..8 without adding filename dispatch to those owners.

JPEG/KTX, dispatch for other image owner types, other source formats, configured
encoder options, callbacks/native allocation ABI, and complete target,
integration, resource and performance gates remain open. GPU file IO is not
claimed by CPU/JS execution.

Explicit [formatted TGA export](FORMATTED-TGA-EXPORT.md) separately supports
checked formats 1..8. It does not broaden suffix-selected `Surface.write_image`.
