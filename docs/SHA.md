# Native SHA-1 and SHA-256 values

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
for some lengths, trailing input bytes.

A linked native probe over lengths 0..127 differs from standard SHA-256 exactly
at 56..59 and 120..123. For input byte `i = (73*i + 11) % 256` and length 56:

- Native: `2c5f29559d2cfd998fa1172d913d53fb411003f9c38cf28edd78973119a264ee`
- Standard: `e5c03138cbcae90c29577557922f8779d8612f591afce5e0835b496137445117`

The implementation writes both length words after packing the message, preserving
these exact native values. SHA-1 retains its standard padding rule.

Larger domains, other native compiler/integer-width profiles, static-pointer ABI
and complete resource/platform/performance remain gaps.

## Verification

```sh
python3 tools/sha_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares every actual native word on CPU/JavaScript/forced Metal. It
passes **409 vectors** covering 1,202,386 input bytes, eleven retained native
SHA-256 differences from the standard digest, and three invalid controls.
Independent standard SHA-1 and nonquirk SHA-256 checks are additional controls;
the complete candidate comparator always uses the actual linked native output.
See [evidence/sha.json](evidence/sha.json).
