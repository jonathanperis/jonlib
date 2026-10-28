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

`Base64.decode_wide(text: String)` returns `Maybe<&2, Base64.Decoded>`.
`Base64Decoded{size, bytes}` is the native `*outputSize` (the `U32` bits of
that signed int, so a negative estimate keeps its high bit) and the bytes a
caller reads from the returned buffer: the positive prefix of `size`.
`Base64.decode` remains the strict 1,048,576-byte decoder.

`decode_wide` accepts a C string of 1..2,147,483,647 bytes that contains a
byte other than `=`. A code unit above 255 is `None`.

- The first NUL ends the native C string; any suffix after it is ignored.
- A byte outside the alphabet is sextet 0, which is the unset entry of
  raylib's decode table. Padding and short groups follow the native size
  formula `3*(length/4) - trailing '='`, including a negative result.
- Unused low bits before padding are ignored. For example, `AB==` still
  decodes to one zero byte.
- Empty input and a string of only `=` make the native padding scan read
  before the buffer. Jonlib returns `None` for those strings.

Both algorithms use tail-recursive accumulation.

## How it is verified

`tools/base64_probe.py` (gate `base64`) compares the actual native encoded
text including its terminator and reported size, and every decoded byte, on
CPU-1, CPU-2 and JavaScript (plus forced GPU with `--gpu`). Cases include every
three-byte remainder, large inputs through 1,048,577 bytes, a decode whose
output passes 1,048,576 bytes, padding/unused bits, embedded NUL suffixes,
unknown sextets and negative size estimates.
Empty input and strings of only `=` are Jonlib rejection controls: the native
padding scan reads before the buffer.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only base64
```

## Known gaps

Pointer/allocator ownership, a dataSize whose encoded size does not fit in a
signed int, the undefined empty and `=`-only decode scans, and complete
resource/platform/performance parity.
