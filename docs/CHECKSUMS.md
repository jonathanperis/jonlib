# Native checksum values

Jonlib ports raylib's `ComputeCRC32` and `ComputeMD5` as `Checksum.crc32` and
`Checksum.md5`. Native SHA-1/SHA-256 values and the reference's SHA-256 padding
quirk are documented separately in [SHA.md](SHA.md).

## API

`Checksum.crc32(bytes: +List<U32>) -> Maybe<&2, U32>` returns the native CRC32
value. It uses the existing PNG CRC recurrence with the reference initial/final
complements. Empty input returns CRC32 zero.

`Checksum.md5(bytes: +List<U32>) -> Maybe<&2, +List<U32>>` returns exactly four
U32 words in native `ComputeMD5` array order. Serialize each word little-endian
to obtain the conventional 16 digest bytes; this API does not return a hex string.
The native profile uses little-endian message-word/length loading.

Both functions accept immutable byte lists of length 0..1,048,576 with values
0..255. Unsupported values or lengths return `None`; MD5 validates before
allocating its padded word buffer. Arithmetic wraps modulo 2^32, and each result
is an immutable value rather than a mutable pointer to native static storage.

## How it is verified

`tools/checksum_probe.py` (gate `checksum`) compares the actual native CRC32
value and all four MD5 words on CPU-1, CPU-2 and JavaScript (plus forced GPU
with `--gpu`). The native output is also checked against Python's standard
`zlib`/`hashlib` results. Cases cover every single byte, empty/standard
messages, 55/56/63/64-byte padding boundaries, multiple blocks, deterministic
random inputs and the 1 MiB limit. Invalid values and the first unsupported
length are candidate rejection controls.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only checksum
```

## Known gaps

Larger domains, big-endian native MD5 behavior, native pointer/allocator/static
buffer semantics and complete resource/platform/performance parity.
