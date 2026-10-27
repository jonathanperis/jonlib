# Native SHA-1 and SHA-256 values

Jonlib adapts raylib's `ComputeSHA1` and `ComputeSHA256` as `Checksum.sha1_wide`
and `Checksum.sha256_wide`: standard SHA-1 and SHA-256 digests.
`Checksum.sha1` and `Checksum.sha256` are the same functions limited to
1,048,576 bytes.

## API

`Checksum.sha1_wide(bytes)` returns five native-order words for a list of
0..2,147,483,575 bytes. That is every length whose signed
`newDataSize = ((((dataSize + 8)/64) + 1)*64)` still fits in a C int.
`Checksum.sha256_wide(bytes)` returns eight native-order words for a list of
0..2,147,483,647 bytes, raylib's nonnegative `int` domain. Empty input is
included. Values above 255, or a longer list, return `None` before allocation.
Serialize each returned word big-endian to obtain the native digest bytes.

Both operations preserve the pinned reference's message schedules, constants,
rotations and modulo-2^32 rounds. Results are immutable values rather than
pointers to mutable native static buffers.

## Padding

Both pad the message to whole 64-byte blocks with `0x80`, zeros and the 8-byte
bit length (`Sha.padded_words`), as raylib sizes the buffer with
`sizeof(unsigned long long)` equal to 8. The stored length is `8*length` in
big-endian halves (`Sha.bit_length.words`): the high word is zero below
536,870,912 and carries from there. Digests are standard at every length,
including 56..59 modulo 64.

## How it is verified

`tools/sha_probe.py` (gate `sha`) compares every actual native word on CPU-1,
CPU-2 and JavaScript (plus forced GPU with `--gpu`), including every
length 0..127 (every padding edge included), the shared checksum lengths
through 1,048,577 bytes, and invalid-input controls. The two bit-length words
are compared with `8ULL*length` at the carry and at both signed ends.
Independent standard SHA-1 and SHA-256 digests confirm the native oracle; the
candidate comparison always uses the actual linked native output.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only sha
```

## Known gaps

A SHA-1 `dataSize` above 2,147,483,575 overflows signed `newDataSize`.
Static-pointer ABI and complete resource/platform/performance parity remain open.
