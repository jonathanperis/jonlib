# Bounded raw DEFLATE decompression

`Compression.decompress(bytes: +List<U32>, maximum: U32) -> Maybe<List<U32>>`
adapts the pinned `DecompressData` API to an immutable compressed input and owned
decompressed output. The returned list contains exactly the resulting bytes. The
native compressor (`Compression.compress`) is documented in
[COMPRESSION.md](COMPRESSION.md).

## Contract

- Compressed inputs contain at most **1 MiB**, with every value in 0..255.
- The caller's output capacity is **0..64 MiB**. Capacity zero accepts a valid
  empty result. Output allocation is bounded by this capacity.
- Stored, fixed-Huffman and dynamic-Huffman blocks are supported, including
  code-length repeat commands, multiple blocks, 32-KiB distances and overlapping
  back-references.
- Invalid requests, malformed/truncated streams, invalid trees/codes/distances
  and output-capacity overflow return `None`; partial output is discarded.
- Valid trailing bytes after completion are ignored, though every supplied byte
  still participates in input-range/size validation.

This operation accepts **raw DEFLATE**, not a zlib or gzip wrapper.

## Native empty-block distinction

Raylib's `DecompressData` uses sinfl, whose pinned stored-block path returns
immediately when its length is zero, even if that block is not final. The public
operation preserves this rule. A retained stream created with zlib's sync flush
therefore returns a 300-byte prefix through `DecompressData`, while PNG's native
stb inflater returns the complete 3,300 bytes.

The internal implementation has an explicit empty-block policy so the
[PNG decoder](PNG.md) follows stb's behavior. Both paths are compared against
their actual linked native entry points. This is a behavioral distinction between
reference APIs, not a tolerance or substitute expected result. PNG chunk parsing,
zlib framing, filtering and image normalization live in the separate PNG module.

## Implementation

The Bend-only decoder uses canonical Huffman levels and checked output indices.
Structural step fuel comes from the compressed bit count; callers do not supply a
retry budget. Stored/literal/match output checks precede array writes, and
back-reference reads require an existing output position. Result extraction is
tail-recursive to bound stack growth.

## How it is verified

`tools/inflate_probe.py` (gate `inflate`) decodes actual native `CompressData`
results and independently generated zlib/RFC-shaped streams, comparing complete
output exactly for both the public native profile (against `DecompressData`) and
the PNG-oriented profile (against stb) on the CPU-1, CPU-2 and JavaScript lanes
(`--gpu` adds a forced-GPU lane, local only). Rejection controls cover malformed
blocks/trees/distances, truncation, input-byte/range bounds and output limits.
Explicit fixtures exercise all three code-length repeats, an empty distance tree
for a literal-only block, exact distance 32,768, overlap and the 1-MiB input
boundary. Original payloads are independently checked through zlib and native
stb. Results are emitted in bounded chunks with an explicit completion marker and
reassembled before comparison, preserving empty-result/failure distinctions.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only inflate
```

## Known gaps

Native pointer/allocation semantics, larger compressed inputs, other permissive
malformed/partial-output recovery and complete resource/performance parity.

## Provenance

The altered canonical decoding implementation retains stb's MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt).
