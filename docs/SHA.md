# Native SHA-1 and SHA-256 values

Jonlib ports raylib's `ComputeSHA1` and `ComputeSHA256` as `Checksum.sha1` and
`Checksum.sha256`, including the reference's nonstandard SHA-256 padding.

## API

`Checksum.sha1(bytes)` and `Checksum.sha256(bytes)` return
`Maybe<&2, +List<U32>>` with exactly five and eight words, respectively, in native
array order. Inputs are immutable byte lists of length 0..1,048,576, including
empty input; invalid values or lengths return `None` before allocation.
Serialize each returned word big-endian to obtain the native digest bytes.

Both operations preserve the pinned reference's message schedules, constants,
rotations and modulo-2^32 rounds. Results are immutable values rather than
pointers to mutable native static buffers.

## Native SHA-256 padding behavior

**`Checksum.sha256` reproduces raylib 6.0's result, including its nonstandard
padding at input lengths 56..59 modulo 64.** The native buffer size is based on
`dataSize + sizeof(int)` (four bytes in this profile), then advanced to the next
64-byte boundary. Its final eight-byte length overwrites the padding marker and,
for some lengths, trailing input bytes. Over lengths 0..127 the native result
differs from standard SHA-256 exactly at 56..59 and 120..123.

Retained counterexample: input byte `i = (73*i + 11) % 256`, length 56.

- Native: `2c5f29559d2cfd998fa1172d913d53fb411003f9c38cf28edd78973119a264ee`
- Standard: `e5c03138cbcae90c29577557922f8779d8612f591afce5e0835b496137445117`

The implementation writes both length words after packing the message, preserving
these exact native values. SHA-1 retains its standard padding rule.

## How it is verified

`tools/sha_probe.py` (gate `sha`) compares every actual native word on CPU-1,
CPU-2 and JavaScript (plus forced GPU with `--gpu`), including the retained
native SHA-256 padding differences and invalid-input controls. Independent
standard SHA-1 and non-quirk SHA-256 digests confirm the native oracle; the
candidate comparison always uses the actual linked native output.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only sha
```

## Known gaps

Larger domains, other native compiler/integer-width profiles, static-pointer ABI
and complete resource/platform/performance parity.
