# Native image-as-code export

`Image.Formatted.to_code(image, path)` returns
`Result<&1, &1, Image.Formatted, String>`. It consumes a checked format-1..7 image
on success and returns the complete native `ExportImageAsCode` text. `path` supplies
the exported name; the pure operation performs no file IO. Unsupported paths or
payload sizes return the original owner.

`Image.Formatted.write_code(image, path)` returns
`IO(Result<&1, &1, Image.Formatted.CodeWriteError, Unit>)`:

- `CodeSourceError{image}` retains rejected input before opening the file.
- `CodeFileError{code,message}` preserves Base open/write errors.
- Successful text writes consume the image and close the handle.

`Image.FloatRGB.to_code(image, path)` returns
`Result<&1, &1, Image.FloatRGB, String>` with the same naming and text rules.
It exports format-9 metadata and all twelve little-endian RGB bytes per pixel
directly, preserving every non-NaN sample word, including signed zero, subnormals
and infinities. It performs no color normalization. Unsupported samples, paths
or payload sizes return the original float owner.

`Image.FloatRGB.write_code(image, path)` returns
`IO(Result<&1, &1, Image.FloatRGB.CodeWriteError, Unit>)`:

- `FloatCodeSourceError{image}` retains rejected input before opening the file.
- `FloatCodeFileError{code,message}` preserves Base open/write errors.
- Successful writes consume the float image and close the handle.

## Current profile and native formatting

- Formats 1..7 and non-NaN RGB float format 9, using their existing checked
  dimensions/storage invariants.
- At most 65,536 logical payload bytes, excluding array-capacity padding.
- Nonempty non-NUL ASCII paths with final basename length 1..200 characters.
- Both `/` and backslash select the final basename. The last dot after position
  zero removes the extension; a sole leading dot remains part of the name.
- ASCII lowercase letters become uppercase. Native identifier spelling is
  preserved, including punctuation from names such as `Mixed.Asset.h`.
- The complete upstream exporter banner, credits and reference wording are retained.
- Dimensions, format and byte count use native decimal formatting. Byte literals
  use lowercase hex without zero padding (`0x0`, `0xa`, `0xff`).
- The first non-final byte and every subsequent twentieth byte are followed by
  a newline. The final byte uses the native closing delimiter and newline.

The formatter builds text with tail-recursive accumulation, including its largest
supported payload. Wider payloads, Unicode/NUL paths, overlong-basename truncation,
configured line widths and full native-ABI/resource/platform/performance remain gaps.

The 200-character limit keeps the native header inside its allocation estimate.
A one-byte image with a 255-character basename generated 2,072 text bytes plus
NUL into a 2,006-byte buffer; AddressSanitizer confirmed the native heap overflow.
That input is rejected rather than treated as defined native evidence. See
[evidence/image-code-native-overflow.json](evidence/image-code-native-overflow.json).
Within the accepted profile, the header is at most 1,863 bytes and the payload
text plus terminator is at most `6*payloadBytes + 3`, leaving at least 134 bytes
inside the native fixed allowance.

Float payloads are multiples of twelve bytes: the largest accepted payload is
65,532 bytes (5,461 pixels). NaN payload parity remains outside the profile
because the pinned JavaScript representation canonicalizes NaN words; see
[FLOAT-RGB-BYTES.md](FLOAT-RGB-BYTES.md).

## Verification

```sh
python3 tools/image_code_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The accepted native reference executable is linked with AddressSanitizer. The gate compares
17 actual native files / 884,733 text bytes on CPU/JavaScript/
forced Metal. The thirteen byte/integer cases cover all seven formats, all byte values, one-byte and
20/21/22-byte line boundaries, leading/multiple dots, backslash selection, a
200-character filename and the 65,536-byte payload boundary.

Four float cases cover signed zero, subnormals, infinities, both signs/all finite
exponents, deterministic random words and the 65,532-byte float payload boundary.

Ten rejected path/size/NaN cases preserve source owners, including complete
oversized float output and a NaN after a valid pixel. CPU/JS additionally
compare every written file, verify a rejected write preserves a sentinel, and run
100 success/source-error/file-error cycles under a 64-descriptor limit. Float file
errors are compared with the original Base error code and message. Metal covers pure text
generation; fixture file IO remains on the CPU. See
[evidence/image-code.json](evidence/image-code.json).

Checked [R32](R32.md) owners can also export their exact little-endian sample
words and native format-8 metadata through `Image.Formatted.to_code/write_code`.
The normalized R32 factory domain still applies. Earlier format/GPU evidence
on this page does not establish the new R32 profile on additional targets.
