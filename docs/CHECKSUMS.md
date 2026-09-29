# Native checksum values

`Checksum.crc32(bytes: +List<U32>) -> Maybe<&2, U32>` returns the native CRC32
value. It uses the existing PNG CRC recurrence with the reference initial/final
complements. Empty input returns CRC32 zero.

`Checksum.md5(bytes: +List<U32>) -> Maybe<&2, +List<U32>>` returns exactly four
U32 words in native `ComputeMD5` array order. Serialize each word little-endian
to obtain the conventional 16 digest bytes; this API does not return a hex string.
The initial native profile uses little-endian message-word/length loading.

Both functions accept immutable byte lists of length 0..1,048,576 with values
0..255. Unsupported values or lengths return `None`; MD5 validates before
allocating its padded word buffer. Arithmetic wraps modulo 2^32, and each result
is an immutable value rather than a mutable pointer to native static storage.

Larger domains, big-endian native MD5 behavior, native pointer/allocator/static
buffer semantics and complete resource/platform/performance remain gaps.
Native SHA-1/SHA-256 values and the reference's SHA-256 padding quirk are
documented separately in [SHA.md](SHA.md).

## Verification

```sh
python3 tools/checksum_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The probe compares actual native CRC32 and all four MD5 words, also checking the
native output against Python's standard `zlib`/`hashlib` results. It covers every
single byte, empty/standard messages, 55/56/63/64-byte padding boundaries, multiple
blocks, deterministic random inputs and the 1 MiB limit. Invalid values and the
first unsupported length are candidate rejection controls. Generated programs
use at most 64 observations per batch and retain one complete ordered comparison
on CPU/JavaScript/forced Metal.
The gate passes **281 native/standard vectors** covering 1,194,258 input bytes,
plus three invalid controls on each lane. See
[evidence/checksums.json](evidence/checksums.json).
