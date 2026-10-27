# Native checksum values

Jonlib adapts raylib's `ComputeCRC32` and `ComputeMD5` as `Checksum.crc32` and
`Checksum.md5`. SHA-1 and SHA-256 are documented separately in
[SHA.md](SHA.md).

## API

`Checksum.crc32_wide(bytes: +List<U32>) -> Maybe<&2, U32>` returns the native
CRC32 value for a list of 0..2147483647 bytes. It uses the existing PNG CRC
recurrence with the reference initial/final complements. Empty input returns
CRC32 zero. `Checksum.crc32` is the same function limited to 1,048,576 bytes.

`Checksum.md5_wide(bytes: +List<U32>) -> Maybe<&2, +List<U32>>` returns exactly
four U32 words in native `ComputeMD5` array order, for a list of 0..268435455
bytes (the lengths whose `8*dataSize` product fits in a signed int). Serialize
each word little-endian to obtain the conventional 16 digest bytes; this API
does not return a hex string. The native profile uses little-endian
message-word/length loading. `Checksum.md5` is the same function limited to
1,048,576 bytes.

Both wide functions accept values 0..255. Unsupported values or longer lists
return `None`; MD5 validates before allocating its padded word buffer.
Arithmetic wraps modulo 2^32, and each result is an immutable value rather than
a mutable pointer to native static storage.

## How it is verified

`tools/checksum_probe.py` (gate `checksum`) compares the actual native CRC32
value and all four MD5 words on CPU-1, CPU-2 and JavaScript (plus forced GPU
with `--gpu`). The native output is also checked against Python's standard
`zlib`/`hashlib` results. Cases cover every single byte, empty/standard
messages, 55/56/63/64-byte padding boundaries, multiple blocks, deterministic
random inputs, the old 1 MiB boundary and 1,048,577 bytes. Invalid byte values
are candidate rejection controls.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only checksum
```

## Known gaps

A `dataSize` whose `8*dataSize` product does not fit in a signed int is not
the reference MD5 length word (`unsigned int bitsLen = 8*dataSize` overflows).
Native pointer/allocator/static buffer semantics and complete
resource/platform/performance parity remain open.
