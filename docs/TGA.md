# TGA memory decoding and default RLE export

| API | Contract |
|---|---|
| `Image.Formatted.decode_tga(bytes: +List<U32>)` | Returns `Result<&1, &1, Image.DecodeError, Image.Formatted>` with owned native format-1/2/4/7 pixels and an implicit single mip. |
| `Surface.decode_tga(bytes: +List<U32>)` | Returns `Result<&1, &1, Image.DecodeError, Surface>` containing owned normalized RGBA8 pixels. |
| `Surface.to_tga(surface) -> +List<U32>` | Consumes RGBA8 and emits the pinned exporter's exact default RLE bytes. |
| `Surface.write_tga(surface, path)` | Consumes RGBA8 and returns `IO(Result<&1, &1, U32 & String, Unit>)` through Base byte-file writing and closure. |

## Decoding profile

- Non-paletted types 2/3/10/11 accept depths 8/15/16/24/32 with the native
  depth-selection rules below. Types 10/11 are RLE.
- Indexed images, types 1 and 9, with 8/16-bit indices and 1..65535 palette entries
  encoded at 8/15/16/24/32 bits. Palette 8-bit values are opaque grayscale;
  palette 15/16-bit values use opaque RGB555; 32-bit entries retain alpha.
- Dimensions 1..4096; ID fields up to 255 bytes are skipped.
- Descriptor bit 5 selects top-down or bottom-up storage; output is row-major
  top-down. Origin coordinates, horizontal-origin and other descriptor bits are
  ignored by the pinned reader and this profile.
- RLE packets may cross rows. Raw/repeated packet counts are 1..128; counts
  extending beyond the remaining image are rejected as `InvalidImageStream`.
- Gray-alpha and 32-bit true-color retain zero alpha, unlike uncompressed BMP's
  alpha repair rule.
- All 15-bit samples and type-2/type-10 16-bit samples consume two little-endian bytes per pixel.
  RGB fields are the five bits at shifts 10, 5 and 0, expanded with integer
  `channel*255/31`. The native decoder ignores bit 15 and the descriptor's alpha
  count for these packed formats: output alpha is always 255. This is distinct
  from 16-bit grayscale's two independent gray/alpha bytes.
- The pinned palette-start field skips that many **bytes after the image ID**,
  rather than shifting logical indices. Indices at or beyond the palette count
  select entry zero. Both behaviors are reproduced from actual native execution.

| Depth | Types 2/10 | Types 3/11 |
|---|---|---|
| 8 | Opaque grayscale | Opaque grayscale |
| 15 | Opaque RGB555 | Opaque RGB555 |
| 16 | Opaque RGB555 | Gray + alpha bytes |
| 24 | Opaque BGR | Opaque BGR |
| 32 | BGRA, alpha retained | BGRA, alpha retained |

The nominal true-color/grayscale type changes only the 16-bit interpretation.
These cross-type combinations follow actual pinned native loading.

Every supplied value must be a byte, otherwise decoding returns `InvalidImageByte`.
Unsupported fields or incomplete headers return `InvalidImageHeader`; dimensions
outside the profile return `UnsupportedImageSize`. Missing ID/pixel/packet data
returns `TruncatedImageData`. Valid trailing bytes are ignored after the image.

Native permissive malformed-data recovery remains outside this checked profile.
The dedicated formatted-memory factory preserves native output formats below. Shared memory/file dispatch is
documented in [IMAGE-FILES.md](IMAGE-FILES.md).

## Format-preserving TGA memory loading

`Image.Formatted.decode_tga(bytes)` keeps the existing checked byte/header/size/
stream contract while preserving the actual pinned `LoadImageFromMemory` output.
Raylib requests stb channels zero, maps output channels 1/2/3/4 to formats
1/2/4/7, and supplies one mip level. Native output channels are carried separately
from input sample/index byte width; canonical RGBA decoding remains unchanged.

| Input | Native output |
|---|---|
| Direct 8-bit, either nominal type | Grayscale (1), G |
| Direct 16-bit type 3/11 | Gray-alpha (2), G,A |
| Direct 15-bit or type-2/10 16-bit | Expanded RGB888 (4), R,G,B |
| Direct 24-bit, either nominal type | RGB888 (4), R,G,B |
| Direct 32-bit, either nominal type | RGBA8888 (7), R,G,B,A |
| Indexed palette depth 8 | Grayscale (1), independent of index width |
| Indexed palette depth 15/16/24 | Expanded RGB888 (4), independent of index width |
| Indexed palette depth 32 | RGBA8888 (7), independent of index width |

The adapter extracts gray R and gray-alpha R,A or packs RGB/RGBA in native byte
order with integer operations. No luminance round trip is introduced. RGB555
retains integer `value*255/31` expansion and ignores bit 15; it produces expanded
RGB888 rather than a packed pixel format. Descriptor alpha-count bits do not
change the channel count or repair zero alpha. Palette-start byte skipping,
entry-zero fallback, vertical orientation, ignored horizontal-origin bits,
raw/RLE stepping and valid trailing data retain the existing decoder semantics.
`Surface.decode_tga` ignores the extra metadata and stays RGBA8-normalized.

The immutable input list can be reused, while success returns one affine pixel
owner. Point reads return that owner alongside their `Maybe` result, including
out-of-bounds reads. Byte export and the Surface bridge consume it. Raw export
contains exactly `width*height*channels` bytes, excluding backing-array padding.
Logical grayscale words have zero high 24 bits; gray-alpha has zero high 16 bits;
RGB888 has a zero high byte. Failure returns only its typed error.

All supplied values, including ignored tails, are checked as bytes before the
header, so `InvalidImageByte` has precedence. Incomplete/unsupported headers
return `InvalidImageHeader`; dimensions outside 1..4096 return
`UnsupportedImageSize`; missing ID/palette/pixel/packet bytes return
`TruncatedImageData`; packet counts exceeding the remaining image return
`InvalidImageStream`. Header validity precedes size, which precedes palette
loading and pixel allocation. These checked adaptations do not claim parity
with permissive native malformed-stream recovery.

Only partial `raylib:function:LoadImageFromMemory` expands. Formatted TGA file
loading, generic formatted/float dispatch, remaining codec formats, nondefault
stb flags, dimensions above 4096, native pointer/allocation/OOM behavior and
maximum-area/resource/performance qualification remain open. CPU/JavaScript
verification cannot establish GPU/Metal, Windows/browser, other hosts or hosted
CI coverage. No API is complete.

## Reconstructed formatted-memory verification

This section records the isolated `f6a48cd` reconstruction from published
baseline `d3b93896`; the
lost local checkpoint and its runtime receipts are not represented as recovered
artifacts. Fresh verification status and provenance are recorded in
[evidence/tga-formatted-rebuilt.json](evidence/tga-formatted-rebuilt.json).
The [obligation coverage matrix](TGA-REBUILD-COVERAGE.md) separates retained
published gates, newly reconstructed tests and unavailable historical artifacts.
The first fresh attempt stopped at a compiler exit -9 after 19 passing batches;
its failure receipts are preserved. The independently reviewed execution-partition repair keeps
the full ordered workload and requires a fresh full run, as detailed in the
coverage matrix. This is not a changed oracle or a reduced corpus.
The fresh focused Linux x86-64 run passes **169 native images / 61,857 pixels**
and **155 checked-only controls**. Native observation has **155,600 raw bytes**
before **247,428 normalized bytes**, plus selected uppercase aliases, totaling
**377 native records**. Each CPU-one-thread, CPU-two-thread and JavaScript lane
passes all **1,311 observations / 1,024,632 bytes** across **43 deterministic
partitions**: **466,800 raw** and **557,832 normalized bytes**, with no differences.
All **1,224 source/build/input/output seals** pass. Input and native-reference
hashes match the failed first capture, so grouping changes neither the corpus
nor oracle output. Candidate mipmaps remain an implicit type contract rather
than a measured field. Fresh canonical and strict replay pass 261 scenarios / 40,101 words, plus
333 QOI bytes and 23 palette words per lane. Ownership/transform/decode
contracts, examples and QOI file/error checks pass. Existing Surface TGA and
generic memory/file dispatch regressions also pass; see the complete
[verification record](VERIFICATION.md#reconstructed-format-preserving-tga-memory-loading-2026-10-03).

The unchanged formatted TGA exporter also passes 304 images / 619,451 pixels
and 3,200 typed IO checks per CPU-one-thread/CPU-two-thread/JavaScript lane;
FloatRGB BMP/TGA export passes 12 files on CPU/JavaScript. These preservation
regressions add no new export or formatted-file capability. This evidence is
isolated to the TGA-only d3-based source; any later integration must be verified
afresh against its changed library hashes.

The focused gate inspects actual native format/mipmaps and every raw byte before
normalization, isolates checked-invalid controls from native, and requires
CPU-one-thread, CPU-two-thread and JavaScript full-byte comparisons. At that isolated checkpoint, workflow
files remained unchanged. The new mandatory CI gate and fresh merged-source
585-test/149-law verification are recorded separately in
[TGA integration](TGA-INTEGRATION.md); the integrated hosted result remains open.

```sh
python3 tools/tga_format_probe.py --reference-env clean-loader --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 -m unittest discover -s tests -p test_tga_format_harness.py -v
```

## Exact export packet selection

The exporter emits a type-10 header, 32-bit BGRA samples, eight alpha bits and
bottom-up rows. It preserves native default RLE selection, restarting at each
row and capping each packet at 128 pixels. The native raw-packet scan compares
the next pixel with the one **two positions earlier**, and shortens the packet
when those match. Conventional adjacent-pixel run detection would change the
encoded bytes even when decoded pixels remain identical.

The output is compared with real `ExportImage(..., ".tga")` files, including
ABA/ABBC patterns, 128/129/130-pixel boundaries, cross-row repeated colors and
seeded mixed packets. Nondefault exporter flags and wider source formats remain gaps.
The dedicated writer selects TGA independently of the file extension.

## Historical Surface verification

```sh
python3 tools/tga_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The shared bitmap comparison gate checks 64 native images (1,219 pixels), 23 typed
errors and 11 complete exports (3,447 bytes) on CPU, JavaScript and forced Metal.
CPU/JS additionally compare a real file export. Packed cases cover all five-bit
channel values, both high-bit states, both orientations and mixed raw/RLE packets;
existing gray-alpha and byte-color inputs remain in the same gate. Indexed cases
cover every palette encoding and index width, raw/RLE packets, nonzero palette
skips, out-of-range recovery, transparent entries and a 257-entry palette.
Empty/unsupported/truncated palettes and indices are rejected. Shared memory
and file dispatch exercise packed, indexed and cross-type streams. Cross-type
fixtures verify every newly accepted combination in raw/RLE and both orientations.
See [evidence/tga-depths.json](evidence/tga-depths.json) for hashes and lane outcomes.

The altered stb implementation retains the selected MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt). Full platform/resource/
performance parity remains open.

Checked formats 1..8 have separate consuming `Image.Formatted.to_tga/write_tga`
entry points preserving native channel routing and packed/R32 expansion; see
[FORMATTED-TGA-EXPORT.md](FORMATTED-TGA-EXPORT.md). Surface decoder/encoder and
FloatRGB scope are unchanged.
