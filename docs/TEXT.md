# Text and codepoints

Jonlib adapts raylib 6.2's `rtext.c` text strings management and UTF-8
codepoint functions as `Text.*`, `Codepoint.*` and `UTF8.*` in `jonlib.bend`;
the algorithms are in `src/text.bend` (an altered Bend adaptation of rtext.c,
LICENSES/raylib.txt). Texts are raylib byte strings, as in
[FILES.md](FILES.md): one character 0..255 per byte, read like a C string up
to the first NUL. C `int` values are U32 two's-complement words. Characters
above 255 are not bytes and are outside every contract on this page.

## Language adaptations

- **Static buffers** (`MAX_TEXT_BUFFER_LENGTH` 1024, `TextFormat`'s four
  rotating buffers, `TextSplit`'s pointer array, `CodepointToUTF8`'s 6 bytes)
  become returned values: results never alias or expire. Their size limits and
  truncation are kept exactly.
- **Load/Unload pairs** (`LoadTextLines`, `LoadUTF8`, `LoadCodepoints` and the
  `*Alloc` functions) return owned values; `Text.unload_lines`, `UTF8.unload`
  and `Codepoint.unload` consume them.
- **Output parameters** (`count`, `codepointSize`, `position`) are returned with
  the result: list lengths, `(codepoint, size)` tuples, `(buffer, position)`.
- **Destination buffers** (`TextCopy`, `TextAppend`) are Strings of the buffer's
  size; the result is the whole buffer after the write.
- **NULL**: Bend has no NULL inputs. The `*Alloc` functions' NULL results are
  `None` (`TextReplaceAlloc` with an empty search, `TextReplaceBetweenAlloc`
  with a missing marker, `TextInsertAlloc` at a negative position);
  `LoadUTF8` of no codepoints is `""`.
- **Varargs**: `TextFormat` takes a typed `List<Text.Arg>`
  (`TextInt{word}`, `TextString{text}`, `TextFloat{f32}`).

## Functions

| Function | raylib | Contract |
|---|---|---|
| `Text.load_lines(text)` / `unload_lines` | `LoadTextLines` / `UnloadTextLines` | The text cut at every `\n` (`\r` kept): newlines + 1 lines. |
| `Text.copy(buffer, text) -> Maybe<(String & U32)>` | `TextCopy` | text and its NUL written at the start of buffer, and the bytes copied. |
| `Text.append(buffer, text, position) -> Maybe<(String & U32)>` | `TextAppend` | text and its NUL written at position, and position + its length. |
| `Text.is_equal(a, b) -> Bool` | `TextIsEqual` | `strcmp` equality. |
| `Text.length(text) -> U32` | `TextLength` | Bytes before the NUL. |
| `Text.format(format, args) -> Maybe<String>` | `TextFormat` | The subset below; output of 1024+ bytes keeps 1020 and appends `...`; a `%c` of 0 ends the result. |
| `Text.subtext(text, position, length) -> Maybe<String>` | `TextSubtext` | `length` bytes from `position`, clamped to the text and to 1023 bytes; `""` for a negative position, a length below 1 or a position at or past the end. Always `Some`. |
| `Text.remove_spaces(text) -> Maybe<String>` | `TextRemoveSpaces` | The bytes other than `' '` among the first 1023. Always `Some`. |
| `Text.between(text, begin, end) -> String` | `GetTextBetween` | The bytes (at most 1023) between the first `begin` and the first `end` after it; `""` when either is missing (an empty marker matches at once). |
| `Text.replace(text, search, replacement) -> Maybe<String>` | `TextReplace` | Non-overlapping occurrences, left to right; `""` for an empty search or a result of 1023+ bytes. |
| `Text.replace_alloc(...)` | `TextReplaceAlloc` | The same without the limit; `None` (NULL) for an empty search. |
| `Text.replace_between(text, begin, end, replacement) -> Maybe<String>` | `TextReplaceBetween` | The text through `begin`, the replacement, the text from `end`; `""` when a marker is missing or the result needs 1023+ bytes. Always `Some`. |
| `Text.replace_between_alloc(...)` | `TextReplaceBetweenAlloc` | The same without the limit; `None` (NULL) when a marker is missing. |
| `Text.insert(text, insert, position) -> Maybe<String>` | `TextInsert` | `insert` placed before the byte at `position`, a position past the end clamped to the text's length; `""` for a negative position or when text + insert need 1023+ bytes. Always `Some`. |
| `Text.insert_alloc(...)` | `TextInsertAlloc` | The same without the limit; `None` (NULL) for a negative position. |
| `Text.join(texts, delimiter) -> Maybe<String>` | `TextJoin` | Each text that fits with a delimiter (`total + length + delimiterLen < 1024`, the last item included; others skipped with their delimiter), the delimiter after each copied text but the last item. Always `Some`. |
| `Text.split(text, delimiter: Char) -> Maybe<List<String>>` | `TextSplit` | The substrings between delimiter bytes among the first 1023 bytes (a longer text's last substring ends at byte 1022); at the 127th delimiter raylib stops and the 128th substring is `""`. A NUL delimiter never splits. Always `Some`. |
| `Text.find_index(text, search) -> Maybe<U32>` | `TextFindIndex` | `strstr`'s index; `None` for -1. An empty search is at 0. |
| `Text.to_upper` / `to_lower(text) -> String` | `TextToUpper` / `TextToLower` | ASCII letters converted, at most 1023 bytes. |
| `Text.to_pascal(text) -> Maybe<String>` | `TextToPascal` | The first byte upper-cased; a run of `_` and the byte after it become that byte, upper-cased for a-z and copied otherwise; a run of `_` at the end is dropped. `""` for an empty text; at most 1023 output bytes. Always `Some`. |
| `Text.to_camel(text) -> Maybe<String>` | `TextToCamel` | The same with the first byte lower-cased. |
| `Text.to_snake(text) -> Maybe<String>` | `TextToSnake` | See below; at most 1023 bytes. Always `Some`. |
| `Text.to_integer(text) -> Maybe<U32>` | `TextToInteger` | An optional sign and the leading digits (0 without digits; no whitespace skipping). |
| `Text.to_float_for(contraction, text) -> F32`, `Text.to_float` | `TextToFloat` | An optional sign, digits as `value*10 + d` in F32, then after `.` each `d/divisor` added and the divisor multiplied by 10; the sign multiplied last (`-0` for `"-"`). `to_float` is the uncontracted profile. |
| `UTF8.load(codepoints) -> String` / `unload` | `LoadUTF8` / `UnloadUTF8` | Every `CodepointToUTF8` encoding, concatenated (a codepoint 0 encodes a NUL byte, which ends raylib's C string). |
| `Codepoint.load(text) -> List<U32>` / `unload` | `LoadCodepoints` / `UnloadCodepoints` | `GetCodepointNext` codepoints up to the NUL. |
| `Codepoint.count(text) -> U32` | `GetCodepointCount` | The `GetCodepointNext` steps up to the NUL. |
| `Codepoint.get(text) -> U32 & U32` | `GetCodepoint` | RFC 3629 decoding (overlong forms, surrogates, F5..FF and values above U+10FFFF rejected) with raylib's error sizes: `?` (63) with size 2 for a bad second byte, 3 or 4 for a later one, 2 for E0/ED/F0/F4 range errors, 1 for C0/C1 and F5..F7 leads and continuation bytes. |
| `Codepoint.next(text) -> U32 & U32` | `GetCodepointNext` | Lead-byte class and continuation bytes only: overlong, surrogate and up to 0x1FFFFF values decode; otherwise `?` with size 1. |
| `Codepoint.previous(text, position) -> Maybe<(U32 & U32)>` | `GetCodepointPrevious` | `GetCodepointPrevious(text + position)`: steps back over continuation bytes and returns `GetCodepointNext` there (its size, not the distance). Position length + 1 reads the NUL: `(0, 1)`. |
| `Codepoint.to_utf8(codepoint) -> String` | `CodepointToUTF8` | 1..4 bytes; a negative codepoint is one byte (its low byte), above 0x10FFFF none. |

### TextToSnake

raylib 6.2 walks the text up to output byte 1023: a `' '` becomes `_` unless
the output is empty or ends with `_` (runs of spaces collapse, leading ones
vanish); an upper-case letter is lower-cased, preceded by `_` when the output
does not end with `_` and the letter starts a word (the input byte before it
is a-z, or it is A-Z and the byte after it a-z: `HTTPRequest` is
`http_request`), unless that `_` would take output byte 1022; other bytes are
copied (`_` included).

### TextFormat subset

Literal bytes and `%%`, and `%[flags][width][.precision]conversion` with:

| Conversion | Argument | Flags | Precision |
|---|---|---|---|
| `d`, `i` | `TextInt` as int | `-` `+` space `0` | minimum digits |
| `u` | `TextInt` as unsigned | `-` `0` | minimum digits |
| `x`, `X`, `o` | `TextInt` as unsigned | `-` `0` `#` | minimum digits |
| `c` | `TextInt` converted to unsigned char | `-` | none |
| `s` | `TextString` (up to its NUL) | `-` | maximum bytes |
| `f`, `F` | `TextFloat` promoted to double | `-` `+` space `0` | 0..9 (default 6) |

Widths and precisions are decimal digits up to 4096. Integer padding follows C
(`0` ignored with a precision, `-` over `0`, `+` over space, `#` adds `0x`/`0X`
for nonzero hex and a leading `0` for octal, precision 0 prints no digits for
0). `%f` text is the exact binary value rounded half to even
([src/decimal.bend](../src/decimal.bend), as glibc and Apple libc print it);
infinities print `inf`/`INF` and are padded with spaces. Extra arguments are
ignored, as in C.

## Undefined native behavior: None

raylib 6.2 defines `TextSubtext`, `TextRemoveSpaces`, `TextReplaceBetween`,
`TextInsert`/`TextInsertAlloc`, `TextJoin`, `TextSplit` and the case
conversions for every text, so those are never `None` (but
`TextInsertAlloc`'s NULL). What remains:

Where raylib's C code reads or writes outside a string or buffer, or
overflows an `int`, Jonlib returns `None` instead of running it:

- `TextCopy`/`TextAppend`: the text and its NUL do not fit in the buffer, or
  the position is negative.
- `TextFormat`: a missing or mismatched argument, an incomplete or unsupported
  specification (C leaves `#` with `d`/`i`/`u`/`c`/`s`, `0` with `c`/`s` and a
  precision with `c` undefined); NaN floats (spelled differently by C
  libraries). Other conversions (`e`, `g`, `a`, `p`, `n`), length modifiers,
  `*`, `+`/space with unsigned conversions and `%f` precisions above 9 are
  outside the subset and also `None`.
- `TextReplace`/`TextReplaceAlloc`: `textLen + count*(replaceLen - searchLen)`
  (plus one for the allocation) overflowing an `int`.
- `TextToInteger`: digits beyond `INT_MAX` (including `-2147483648`).
- `GetCodepointPrevious`: stepping before the text, or a position more than one
  byte past its NUL.

### `text_codepoints_loading`

raylib 6.0's `CodepointRemoveDuplicates` (the example's own) copied the
codepoints into `codepointCount` ints and, at the first repeated one,
shifted the tail down with `codepointsNoDups[k] = codepointsNoDups[k + 1]`
up to `k = count - 1`: one int read past the allocation (AddressSanitizer: a
heap-buffer-overflow read of 4 bytes, 0 bytes after the region), before the
first frame, since the text repeats the ideographic space and the line
break. The 6.0 port refused every frame. raylib 6.2 stops the shift at
`count - 2`, and `examples/text_codepoints_loading.bend` is the whole
example: the 54 codepoints, the 49 left (each at its first place), the
font loaded from `DotGothic16-Regular.ttf` at size 36 with them and
filtered bilinearly, the text drawn with line spacing 20 or the atlas, and
the RIGHT and LEFT pointer steps (`GetCodepointNext` and
`GetCodepointPrevious`, which draw nothing). A step before the text is
undefined in C: the probe's `before` script takes LEFT at the start and is
compared up to that frame (`UNDEFINED_FROM`), the port refusing from it.

## TextToFloat and contraction

`TextToFloat`'s integer loop `value = value*10.0f + digit` is contracted into a
fused multiply-add by raylib's arm64 build (`fmadd`) and not on x86-64, which
changes results once the value passes 2^24. `Text.to_float_for` takes the
`M.Contraction` profile ([COLLISION.md](COLLISION.md)); the fused profile
rounds `value*10 + digit` once (exactly, in integer arithmetic, since `value`
is always an integral F32 or infinity). The fraction loop has no multiply-add.

## How it is verified

`tools/text_probe.py` (gate `text`) writes every case to a binary file that a C
interpreter linked against the pinned raylib and a Bend interpreter both read,
and compares one row per case (bytes as hex) on CPU-1, CPU-2 and JavaScript.
The corpus covers every function above over ASCII, multi-byte, invalid and
truncated UTF-8 (every suffix and position of each decoding text), embedded
NULs, empty texts, texts of 1019..2100 bytes around each static limit, 126..300
delimiters, overlapping search patterns, buffer sizes around each write, all
insert positions, every `TextSubtext` boundary including `INT_MIN`/`INT_MAX`,
signed integer limits, raylib 6.2's new limits (`TextReplaceBetween`
results of 1021..1024 bytes, `TextJoin` fits around 1023, `TextSplit` texts
around byte 1022, `TextToSnake` word boundaries at output bytes 1019..1023,
runs of `_` before and at the end of a text), long and fractional float texts, and 273 random and
targeted `TextFormat` formats (96 of them refused) (including outputs of 1023, 1024 and more
bytes and a `%c` NUL before and after the truncation point).

Undefined cases are never run against the linked library. The probe compiles
the pinned rtext.c text functions on their own with AddressSanitizer and
UndefinedBehaviorSanitizer: that build must reproduce the linked rows for every
defined case and must report an error for every case Jonlib answers `None`
(except `TextFormat`, whose refusals are checked against the subset grammar).
`TextToFloat` rows carry both profiles: the extracted function compiled without
contraction and with its multiply-add written as `fmaf`, and the linked result
must equal the host's profile.

## Gaps

- `TextFormat` conversions outside the subset (`e`, `g`, `a`, `p`), length
  modifiers, `*` widths and `%f` precisions above 9.
- `TextFormat` NaN arguments (C library spellings differ).
- Pointer/allocator ABI: results are values, not char buffers shared between
  calls.
