# Native raw compression

The pinned `CompressData` implementation uses **sdefl quality 8**. Its raw
DEFLATE bytes differ from the stb compressor used by PNG export, so it has a
separate implementation path.

## Dynamic-Huffman dependency

`src/sdeflate_huffman.bend` is a private builder for the native literal,
distance and precode profiles: 288 symbols/14 bits, 32/15 and 19/7. Frequencies
are U32 values totaling at most 262,145, matching the bounded block domain.
The operation retains its frequency owner and returns owned length/code arrays.

It preserves ascending packed frequency/symbol ordering, zero/single-symbol
cases and dummy codes, leaf/queue tie selection, parent/depth construction,
length-limit redistribution and reversed canonical words. Bend's full packed-key
sort replaces the reference bucket/heap sorting; complete native table comparison
is the equivalence gate.

```sh
python3 tools/sdeflate_huffman_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The probe includes the unmodified pinned header in a separate C reference program
and compares all lengths/code words plus retained frequencies on CPU/JavaScript/
forced Metal. Empty, single, equal, bucket-boundary, skewed, Fibonacci and seeded
random frequency tables exercise ordering and length limits.
The gate passes **103 tables / 11,814 symbol entries** on all three lanes,
comparing each frequency, length and code word. See
[evidence/sdeflate-huffman.json](evidence/sdeflate-huffman.json).

This internal gate alone does not establish public `CompressData` coverage.
The public quality-8 path and its separate complete-byte gate are described below.
The existing [raw decoder](DEFLATE.md) is separately mapped.

## Native quality-8 profile

`J.Compression.compress(bytes) -> Maybe<&2, +List<U32>>` accepts immutable valid
byte lists of 0..1,048,576 values and returns native raw DEFLATE bytes. Invalid
byte values, excessive size or an exhausted sequence budget return `None`.
There is no zlib/gzip wrapper and no configurable compression level.

The implementation preserves four-byte little-endian hashes, 8,192-candidate
chain searches, native window exclusion, newest equal-match selection, lazy
lookahead, insertion/tail rules and 262,144-byte block boundaries. It retains
native symbol frequencies, canonical Huffman/precode runs, dynamic-versus-stored
cost selection, 65,535-byte stored splits, alignment and final flushing.
It does not reuse PNG's distinct match finder or stored-block policy.

Native empty-input compression returns **zero bytes**, not an encoded empty
DEFLATE stream. Therefore empty compression is not passed to a DEFLATE decoder;
nonempty successful results must decompress to the complete original input.

Each block permits at most **87,380 retained sequences**, matching the reference
debug assertion before append. A retained valid-byte 256-KiB dictionary/marker
input exceeds native capacity in release mode. Jonlib rejects that input instead
of reproducing the native out-of-bounds write. The reproducer and sanitizer
evidence are retained in
[evidence/sdeflate-sequence-overflow.json](evidence/sdeflate-sequence-overflow.json).

```sh
python3 tools/sdeflate_probe.py --stage lz --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/sdeflate_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

The LZ gate compares every native block boundary, ordered sequence and literal/
distance frequency. Its task-local observation hooks do not change the upstream
checkout; instrumented compressed bytes must equal the actual linked API before
observations are trusted. The compression gate compares every actual native
output byte, checks native outputs independently with Python zlib, and round-trips
candidate nonempty streams through the existing Bend decoder. Forced Metal runs
the pure compressor/decoder, not file IO.

Both gates pass **40 native inputs** and four rejection controls on CPU,
JavaScript and forced Metal. The LZ comparison includes **51 blocks / 12,084
sequences / 40,641 observation words** per lane, all supported length symbols
258..285 and distance symbols 0..29. Compression compares **1,931,853 complete
output bytes** per lane from 4,497,358 source bytes, including the maximum
incompressible input and mixed stored/dynamic blocks. See
[LZ evidence](evidence/sdeflate-lz.json) and
[compression evidence](evidence/sdeflate-compression.json).

The public `Compression.decompress` compressed-input cap remains 1 MiB.
Incompressible 1-MiB source data can produce a larger compressed result, which
that public entry rejects. The gate verifies this rejection and separately
checks the complete round trip through the unchanged internal decoder after
validating bytes against the native compressor's 1,048,679-byte output bound.
This internal check does not claim broader public decompression coverage.

Larger inputs, other levels/framing, big-endian hashes, native-overflow domains,
allocation/pointer ABI and complete integration/target/resource/performance
coverage remain gaps. No compression-ratio or speed parity claim follows from
the finite exact-byte corpus.

The altered sdefl implementation retains Micha Mettke's MIT license in
[LICENSES/sdefl.txt](../LICENSES/sdefl.txt).
