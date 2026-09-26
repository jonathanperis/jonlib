# Bounded raw DEFLATE decompression

`Compression.decompress(bytes: +List<U32>, maximum: U32) -> Maybe<List<U32>>`
adapts the pinned `DecompressData` API to an immutable compressed input and owned
decompressed output. The returned list contains exactly the resulting bytes.

- Compressed inputs contain at most **1 MiB**, with every value in 0..255.
- The caller's output capacity is **0..64 MiB**. Capacity zero accepts a valid
  empty result. Output allocation is bounded by this capacity.
- Stored, fixed-Huffman and dynamic-Huffman blocks are supported, including
  code-length repeat commands, multiple blocks, 32-KiB distances and overlapping
  back-references. Complete valid output is compared with the native API.
- Invalid requests, malformed/truncated streams, invalid trees/codes/distances
  and output-capacity overflow return `None`; partial output is discarded.
- Valid trailing bytes after completion are ignored, though every supplied byte
  still participates in input-range/size validation.

This operation accepts **raw DEFLATE**, not a zlib or gzip wrapper. Native
pointer/allocation semantics, larger compressed inputs, other permissive
malformed/partial-output recovery and complete resource/performance parity remain gaps.

## Native empty-block distinction

Raylib's `DecompressData` uses sinfl, whose pinned stored-block path returns
immediately when its length is zero—even if that block is not final. The public
operation preserves this rule. A retained stream created with zlib's sync flush
therefore returns a 300-byte prefix through `DecompressData`, while PNG's native
stb inflater returns the complete 3,300 bytes.

The internal implementation has an explicit empty-block policy so the
[PNG boundary](PNG.md) follows stb's behavior. Both paths are compared against their
actual linked native entry points. This is a behavioral distinction between
reference APIs, not a tolerance or substitute expected result. PNG chunk parsing,
zlib framing, filtering and image normalization live in the separate PNG module.

## Implementation and verification

The Bend-only decoder uses canonical Huffman levels and checked output indices.
Structural step fuel comes from compressed bit count; callers do not supply a
retry budget. Stored/literal/match output checks precede array writes, and
back-reference reads require an existing output position. Result extraction is
tail-recursive after a forced-Metal test exposed stack growth in generic list
prefix extraction.

```sh
python3 tools/inflate_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The probe checks 24 streams, including actual native `CompressData` results and
independently generated zlib/RFC-shaped streams. It compares 122,651 bytes for
the public native profile and 125,651 bytes for the PNG-oriented profile on
CPU, JavaScript and forced Metal. Sixteen rejection controls cover malformed
blocks/trees/distances, truncation, input-byte/range bounds and output limits.
Explicit fixtures exercise all three code-length repeats, an empty distance
tree for a literal-only block, exact distance 32,768, overlap and the 1-MiB input
boundary. Original payloads are independently checked through zlib and native stb.
Probe results use chunks of at most 256 bytes with an explicit completion marker;
the harness reassembles all bytes before comparison. This bounds the generic
list formatter's recursion on hosted JavaScript and retains empty-result/failure
distinctions. Malformed or unfinished chunk sequences are rejected.

The altered canonical decoding implementation retains stb's MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt).
