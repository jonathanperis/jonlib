# Image-as-code export

Jonlib adapts raylib 6.0 `ExportImageAsCode`, which renders an image as a C
header containing its metadata and every storage byte.

```bend
Image.Formatted.to_code(image, path) -> Result<&1, &1, Image.Formatted, String>
Image.Formatted.write_code(image, path) -> IO(Result<&1, &1, Image.Formatted.CodeWriteError, Unit>)
Image.FloatRGB.to_code(image, path) -> Result<&1, &1, Image.FloatRGB, String>
Image.FloatRGB.write_code(image, path) -> IO(Result<&1, &1, Image.FloatRGB.CodeWriteError, Unit>)
```

`to_code` returns the complete native text; `path` only supplies the exported
name and the pure operation performs no file IO. Success consumes the owner;
an unsupported path, payload size or sample returns the original owner.

```bend
type Image.Formatted.CodeWriteError is Type:
  CodeSourceError{image: Image.Formatted}
  CodeFileError{code: U32, message: String}

type Image.FloatRGB.CodeWriteError is Type:
  FloatCodeSourceError{image: Image.FloatRGB}
  FloatCodeFileError{code: U32, message: String}
```

The source errors return the rejected owner before the file is opened. The file
errors preserve Base's exact open/write code and message. Successful writes
consume the owner and close the handle.

## Contract

- **Sources**: checked `Image.Formatted` formats 1..8 (format 8 within the
  [R32](R32.md) domain, exporting its exact little-endian sample words and native
  format-8 metadata) and `Image.FloatRGB` format 9, under their existing
  dimension/storage invariants.
- **Float payload**: format-9 metadata and all twelve little-endian RGB bytes per
  pixel, preserving every non-NaN sample word (signed zero, subnormals,
  infinities). No color normalization. NaN samples are rejected; the pinned
  JavaScript representation canonicalizes NaN words, so NaN payload parity is
  outside the profile (see [FLOAT-RGB.md](FLOAT-RGB.md)).
- **Payload size**: at most **65,536** logical payload bytes, excluding
  array-capacity padding. Float payloads are multiples of twelve, so the largest
  accepted float payload is 65,532 bytes (5,461 pixels).
- **Paths**: nonempty, non-NUL ASCII, with final basename length **1..200**
  characters.

## Native formatting

- Both `/` and backslash select the final basename. The last dot after position
  zero removes the extension; a sole leading dot remains part of the name.
- ASCII lowercase letters become uppercase. Native identifier spelling is
  preserved, including punctuation from names such as `Mixed.Asset.h`.
- The complete upstream exporter banner, credits and reference wording are
  retained.
- Dimensions, format and byte count use native decimal formatting. Byte literals
  use lowercase hex without zero padding (`0x0`, `0xa`, `0xff`).
- The first non-final byte and every subsequent twentieth byte are followed by a
  newline. The final byte uses the native closing delimiter and newline.

The formatter builds text with tail-recursive accumulation, including at the
largest supported payload.

## Native overflow and the basename limit

The 200-character limit keeps the native header inside its allocation estimate.
A one-byte image with a 255-character basename makes native raylib write 2,072
text bytes plus NUL into a 2,006-byte buffer (a heap overflow confirmed with
AddressSanitizer). Such input is rejected rather than treated as defined native
behavior. Within the accepted profile the header is at most 1,863 bytes and the
payload text plus terminator is at most `6*payloadBytes + 3`, leaving at least
134 bytes inside the native fixed allowance.

## How it is verified

`tools/image_code_probe.py` (gate `image-code`) links the native
`ExportImageAsCode` reference with AddressSanitizer and compares complete text
files byte-for-byte on CPU-1, CPU-2, JavaScript and, with `--gpu`, forced GPU
(pure text generation only). Cases cover all byte/integer formats, all byte
values, one-byte and 20/21/22-byte line boundaries, leading/multiple dots,
backslash selection, a long filename, the 65,536-byte payload boundary, and float
signed zeros, subnormals, infinities, all finite exponents and the 65,532-byte
float boundary. Rejected path/size/NaN cases must return their owners (including
a NaN after a valid pixel). On CPU/JS lanes every written file is compared, a
rejected write must leave a sentinel unchanged, file errors must equal the
direct Base code and message, and 100 success/source-error/file-error cycles run
under a 64-descriptor limit. R32 code export is compared in gate `r32-image`
(`tools/r32_image_probe.py`).

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only image-code
```

## Known gaps

Wider payloads, Unicode/NUL paths, overlong-basename truncation, configured line
widths, NaN payloads and complete native ABI/resource/platform/performance
parity.
