# Exact default byte-format PNG export

| API | Contract |
|---|---|
| `Surface.to_png(surface) -> +List<U32>` | Consumes canonical RGBA8 ownership and returns every PNG byte, matching native `ExportImageToMemory(image, ".png")` under the default writer settings. |
| `Surface.write_png(surface, path)` | Consumes ownership and returns `IO(Result<&1, &1, U32 & String, Unit>)` through the established Base byte-write/close path. PNG is selected explicitly, independently of the path extension. |
| `Image.Formatted.to_png(image)` | Returns `Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>` for native byte formats 1/2/4/7. Success consumes ownership; unsupported packed formats return the original image with `UnsupportedPixelFormat`. |

The source Surface contract remains dimensions 1..4096 and row-major packed
`0xRRGGBBAA` words. Only logical pixels are encoded; array-capacity padding is
excluded. Surface output is non-interlaced 8-bit RGBA, with one IHDR, one IDAT and
IEND. Use `Surface.copy` first when a separately owned Surface is needed.

Formatted-image memory export retains native source channels and byte order:

| Source format | Channels | PNG color type |
|---|---:|---:|
| 1: grayscale | 1 | 0 |
| 2: gray-alpha | 2 | 4 |
| 4: RGB888 | 3 | 2 |
| 7: RGBA8888 | 4 | 6 |

Filtering uses that channel count as its left-neighbor distance. Inputs are
encoded directly rather than normalized through RGBA8, preserving exact headers
and compressed bytes. Packed formats 3/5/6 are rejected with their dimensions,
format and pixels intact. Other source formats and native pointer/output-size/
allocator correspondence remain gaps. The dedicated file helper takes a Surface.

## Reference defaults and byte-level rules

The pinned writer uses compression quality **8**, automatic filtering (`-1`)
and no vertical flip. The Bend implementation retains:

- All five filter candidates, scored by the sum of absolute **signed-byte**
  residuals; strict less-than selection keeps the earliest filter on ties.
- The stb three-byte hash, 16,384 buckets, newest equal-length match selection,
  32,767-byte maximum match distance and 258-byte maximum length.
- Quality-8 bucket eviction (discard the oldest half at 16 entries), insertion
  before lazy next-position comparison, and the exact match/literal decisions.
- Fixed Huffman packing, byte-boundary padding and the reference threshold for
  replacing an oversized compressed stream with 32,767-byte stored blocks.
- The `78 5e` zlib header, native 5,552-byte Adler reduction boundaries and
  exact big-endian PNG chunk lengths/CRCs.

`src/deflate.bend` is specifically the stb PNG compressor. Raylib's separate
`CompressData` uses sdefl; this implementation is not mapped to that API.
Nondefault compression/filter/flip settings and full resource/performance parity
are not covered. Large allocations retain the existing runtime failure boundary.

The encoder and decoder have different size profiles: a valid large image may
encode beyond `decode_png`'s 1-MiB encoded-input bound. Round-trip evidence below
uses inputs inside both profiles; it does not enlarge the decoder limit.

## Verification

```sh
python3 tools/deflate_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/png_export_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The private compressor matches 17 native comparisons / 170,780 encoded bytes,
including eviction, lazy matching, strict window edges, Adler boundaries and
stored-block sizes. Its empty-input result is compared as emitted by stb; PNG's
filtered image input is always nonempty.

Complete native memory and file exports agree for 28 PNG images / 170,383 bytes.
Every candidate byte matches on CPU, JavaScript and forced Metal, and complete
candidate decode round trips reproduce 171,716 normalized RGBA bytes. Native inspection
confirms that all five filters are selected for each supported byte format, and
both fixed/stored DEFLATE paths are exercised. Original RGBA8 fixtures remain covered.
CPU/JS also write mixed-alpha and noise images through the public file API and
compare them byte-for-byte. Shared 256-byte result framing preserves large outputs
without recursive whole-list formatting.

The altered stb algorithms retain [the selected MIT notice](../LICENSES/stb-image.txt).
See the original [RGBA8 evidence](evidence/png-export.json) and
[byte-format increment](evidence/png-export-formats.json) for hashes and lane scope.
