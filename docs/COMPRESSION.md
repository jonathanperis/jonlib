# Native raw compression

The pinned `CompressData` implementation uses **sdefl quality 8**. Its raw
DEFLATE bytes differ from the stb compressor used by PNG export, so it has a
separate implementation path. (The private PNG-export compressor is compared
byte-for-byte with linked stb by `tools/deflate_probe.py`, gate `deflate`; see
[IMAGE-EXPORT.md](IMAGE-EXPORT.md).) Decompression is documented in
[DEFLATE.md](DEFLATE.md).

## Quality-8 compression

`J.Compression.compress(bytes: +List<U32>) -> Maybe<&2, +List<U32>>` accepts
immutable valid byte lists of 0..1,048,576 values and returns native raw DEFLATE
bytes. Invalid byte values, excessive size or an exhausted sequence budget return
`None`. There is no zlib/gzip wrapper and no configurable compression level.

The implementation preserves four-byte little-endian hashes, 8,192-candidate
chain searches, native window exclusion, newest equal-match selection, lazy
lookahead, insertion/tail rules and 262,144-byte block boundaries. It retains
native symbol frequencies, canonical Huffman/precode runs, dynamic-versus-stored
cost selection, 65,535-byte stored splits, alignment and final flushing. It does
not reuse PNG's distinct match finder or stored-block policy.

Native empty-input compression returns **zero bytes**, not an encoded empty
DEFLATE stream. Therefore empty compression is not passed to a DEFLATE decoder;
nonempty successful results must decompress to the complete original input.

### Sequence-capacity quirk

Each block permits at most **87,380 retained sequences**, matching the reference
debug assertion before append. A valid-byte 256-KiB dictionary/marker input
exceeds native capacity in release mode, where the native code performs an
out-of-bounds write. Jonlib rejects that input (`None`) instead of reproducing
the overflow. The reproducer is retained as the `sequence-limit` control in
`tools/sdeflate_probe.py` (seeded construction checked by SHA-256).

### Interaction with decompression

The public `Compression.decompress` compressed-input cap is 1 MiB.
Incompressible 1-MiB source data can produce a larger compressed result, which
that public entry rejects. The compression gate verifies this rejection and
separately checks the complete round trip through the internal decoder after
validating bytes against the native compressor's 1,048,679-byte output bound.
This internal check does not claim broader public decompression coverage.

## Dynamic-Huffman builder

`src/sdeflate_huffman.bend` is a private builder for the native literal,
distance and precode profiles: 288 symbols/14 bits, 32/15 and 19/7. Frequencies
are U32 values totaling at most 262,145, matching the bounded block domain. The
operation retains its frequency owner and returns owned length/code arrays.

It preserves ascending packed frequency/symbol ordering, zero/single-symbol cases
and dummy codes, leaf/queue tie selection, parent/depth construction,
length-limit redistribution and reversed canonical words. Bend's full packed-key
sort replaces the reference bucket/heap sorting; complete native table comparison
is the equivalence gate. This internal builder alone does not establish public
`CompressData` coverage.

## How it is verified

All gates compare exactly on the CPU-1, CPU-2 and JavaScript lanes; `--gpu` adds
a forced-GPU lane (local only) running the pure compressor/decoder, not file IO.

- **Huffman builder** (`tools/sdeflate_huffman_probe.py`, gate
  `sdeflate-huffman`): the unmodified pinned header is included in a separate C
  reference program; all lengths/code words plus retained frequencies are
  compared for empty, single, equal, bucket-boundary, skewed, Fibonacci and seeded
  random frequency tables.
- **LZ stage** (`tools/sdeflate_probe.py --stage lz`, gate `sdeflate-lz`): every
  native block boundary, ordered sequence and literal/distance frequency,
  including all length symbols 258..285 and distance symbols 0..29. Task-local
  observation hooks do not change the upstream checkout; the instrumented
  compressed bytes must equal the actual linked API before observations are
  trusted.
- **Compression** (`tools/sdeflate_probe.py`, gate `sdeflate`): every actual
  native `CompressData` output byte, including the maximum incompressible input
  and mixed stored/dynamic blocks. Native outputs are checked independently with
  Python zlib, and candidate nonempty streams are round-tripped through the Bend
  decoder. Rejection controls include the sequence-capacity reproducer.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only sdeflate
```

## Known gaps

Larger inputs, other levels/framing, big-endian hashes, native-overflow domains,
allocation/pointer ABI and complete integration/target/resource/performance
coverage. No compression-ratio or speed parity claim follows from the finite
exact-byte corpus.

## Provenance

The altered sdefl implementation retains Micha Mettke's MIT license in
[LICENSES/sdefl.txt](../LICENSES/sdefl.txt).
