# Native Base64 utilities

`Base64.encode(bytes: +List<U32>)` returns
`Maybe<&2, Base64.Encoded>`. `Base64Encoded{size, text}` contains the native
RFC4648 encoded text and its reported byte count. **`size` includes the trailing
C NUL; Bend `text` does not.** Empty input therefore returns size 1 and empty text.
Input is limited to 1,048,576 bytes, each in 0..255; unsupported inputs return
`None`. Padding and the `+/` alphabet match native `EncodeDataBase64`.

`Base64.decode(text: String)` returns `Maybe<&2, +List<U32>>`, containing exactly
the native logical decoded bytes. The supported input has nonempty groups of
four ASCII alphabet characters, with zero, one or two final `=` characters.
The result is limited to 1,048,576 bytes.

- The first NUL ends the native C string; any suffix after it is ignored.
- Unused low bits before padding are ignored, matching the native decoder.
  For example, `AB==` still decodes to one zero byte.
- Invalid alphabet/group/padding structure, empty input and oversized results
  return `None`.
- Empty native decoding reads before its input buffer during the padding scan.
  Jonlib rejects that case rather than relying on the undefined read.

Both algorithms use tail-recursive accumulation. Native permissive malformed
recovery, pointers/allocator ownership, larger domains and complete resource/
platform/performance parity remain gaps. Encoding an empty list succeeds, while
decoding its empty text is outside the initial native-defined decoding profile.

## Verification

```sh
python3 tools/base64_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The probe compares actual native full encoded text including its terminator and
reported size, and every decoded byte, on CPU/JavaScript/forced Metal. Cases
include every three-byte remainder, large inputs, padding/unused bits, embedded
NUL suffixes and malformed/size boundaries. Undefined native malformed cases
serve only as Jonlib rejection controls.
The current gate passes **30 native cases / 2,754,389 output bytes per lane**
and fourteen rejection controls, including the 1 MiB input/output boundary.
See [evidence/base64.json](evidence/base64.json).
