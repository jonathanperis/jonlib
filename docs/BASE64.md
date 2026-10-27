# Native Base64 utilities

Jonlib adapts raylib's `EncodeDataBase64` and `DecodeDataBase64` as
`Base64.encode` and `Base64.decode`, reproducing the native text, sizes and
decoded bytes.

## Encoding

`Base64.encode_wide(bytes: +List<U32>)` returns `Maybe<&2, Base64.Encoded>`.
`Base64.encode` is the same function limited to 1,048,576 bytes.
`Base64Encoded{size, text}` contains the native RFC4648 encoded text and its
reported byte count. **`size` includes the trailing C NUL; Bend `text` does
not.** Empty input therefore returns size 1 and empty text.

`encode_wide` accepts 0..1,610,612,733 bytes, each in 0..255. That is every
length whose rounded multiple of 3 keeps `4*(paddedSize/3)+1` inside a signed
int. A longer list or a byte above 255 returns `None`. Padding and the `+/`
alphabet match native `EncodeDataBase64`.

## Decoding

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
  Jonlib rejects that case rather than relying on the undefined read. Encoding
  an empty list therefore succeeds, while decoding its empty text is outside
  the profile.

Both algorithms use tail-recursive accumulation.

## How it is verified

`tools/base64_probe.py` (gate `base64`) compares the actual native encoded
text including its terminator and reported size, and every decoded byte, on
CPU-1, CPU-2 and JavaScript (plus forced GPU with `--gpu`). Cases include every
three-byte remainder, large inputs through 1,048,577 bytes, the 1 MiB decode boundary,
padding/unused bits, embedded NUL suffixes and malformed/size boundaries.
Malformed inputs whose native behavior is undefined serve only as Jonlib
rejection controls.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only base64
```

## Known gaps

Native permissive malformed-input recovery, pointer/allocator ownership, a
dataSize whose encoded size does not fit in a signed int, and complete
resource/platform/performance parity.
