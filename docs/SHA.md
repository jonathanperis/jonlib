# Native SHA-1 and SHA-256 values

Jonlib ports raylib's `ComputeSHA1` and `ComputeSHA256` as `Checksum.sha1` and
`Checksum.sha256`: standard SHA-1 and SHA-256 digests.

## API

`Checksum.sha1(bytes)` and `Checksum.sha256(bytes)` return
`Maybe<&2, +List<U32>>` with exactly five and eight words, respectively, in native
array order. Inputs are immutable byte lists of length 0..1,048,576, including
empty input; invalid values or lengths return `None` before allocation.
Serialize each returned word big-endian to obtain the native digest bytes.

Both operations preserve the pinned reference's message schedules, constants,
rotations and modulo-2^32 rounds. Results are immutable values rather than
pointers to mutable native static buffers.

## Padding

Both pad the message to whole 64-byte blocks with `0x80`, zeros and the 8-byte
bit length (`Sha.padded_words`). raylib 6.0 sized the SHA-256 buffer with
`dataSize + sizeof(int)` and so differed from standard SHA-256 at input lengths
56..59 modulo 64; raylib 6.2 uses `sizeof(bitLen)` (8), and so does Jonlib.

## How it is verified

`tools/sha_probe.py` (gate `sha`) compares every actual native word on CPU-1,
CPU-2 and JavaScript (plus forced GPU with `--gpu`), including every
length 0..127 (the old padding edges included) and invalid-input controls.
Independent standard SHA-1 and SHA-256 digests confirm the native oracle; the
candidate comparison always uses the actual linked native output.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only sha
```

## Known gaps

Larger domains, other native compiler/integer-width profiles, static-pointer ABI
and complete resource/platform/performance parity.
