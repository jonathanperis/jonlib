# Exact default byte-format PNG export

| API | Contract |
|---|---|
| `Surface.to_png(surface) -> +List<U32>` | Consumes canonical RGBA8 ownership and returns every PNG byte, matching native `ExportImageToMemory(image, ".png")` under the default writer settings. |
| `Surface.write_png(surface, path)` | Consumes ownership and returns `IO(Result<&1, &1, U32 & String, Unit>)` through the established Base byte-write/close path. PNG is selected explicitly, independently of the path extension. |
| `Image.Formatted.to_png(image)` | Returns `Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>` for native byte formats 1/2/4/7. Success consumes ownership; unsupported packed formats return the original image with `UnsupportedPixelFormat`. |
| `Image.Formatted.write_png(image, path)` | Consumes any checked format-1..7 owner and returns the established `IO(Result<&1, &1, U32 & String, Unit>)` file contract. Byte sources retain their channels; packed sources use native file-export expansion. |
| `Image.FloatRGB.to_png(image)` | Returns `Result<&1, &1, Image.FloatRGB, +List<U32>>`, preserving native format-9 memory export's raw-storage-prefix interpretation. Non-NaN float words are supported; rejection returns the owner. |
| `Image.FloatRGB.write_png(image, path)` | Returns `IO(Result<&1, &1, Image.FloatRGB.WriteError, Unit>)`. Finite `[0,1]` samples follow native normalized file export; unsupported samples retain their owner before opening the file. |

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
and compressed bytes. Memory export rejects packed formats 3/5/6 with their
dimensions, format and pixels intact. Other source formats and native pointer/
output-size/allocator correspondence remain gaps.

## Packed sources in file export

The native file API uses `LoadImageColors` for formats 3/5/6 before encoding RGBA8.
`Image.Formatted.write_png` follows that distinct path:

- RGB565 expands 5-bit channels by 8 and its 6-bit channel by 4, giving maximum
  RGB values **248/252/248**, with alpha 255.
- RGB5A1 expands each 5-bit channel by 8 and its alpha bit by 255. Blue comes
  from bits 1..5, excluding alpha, unlike the pinned raw `GetPixelColor` quirk.
- RGBA4 expands all four 4-bit channels by 17.

These rules differ from `ImageFormat` normalization, so the file path does not
route packed inputs through `Image.Formatted.to_surface`. The resulting RGBA8
pixels and complete PNG bytes are compared with native file export. Construct
formatted owners through the checked factory/conversion APIs; manually inconsistent
storage remains outside the contract.

## RGB float memory/file distinction

The pinned native APIs take different paths for format 9. Memory export treats
float storage as four byte channels and encodes the first `width*height*4`
little-endian bytes, without converting float values. This is a contiguous prefix
of the RGB sample words, not one selected component per source pixel. Jonlib
preserves that interpretation with non-NaN sample words, including infinities and
subnormals.

File export instead uses `LoadImageColors`, truncating finite `[0,1]` channels to
RGBA8 with opaque alpha before encoding. For a one-pixel RGB source
`(0.5, 0.25, 0.75)`, native memory PNG decodes to **`0000003f`**, while file PNG
decodes to **`7f3fbfff`**. Use the file API for that normalized native export path.

`FloatRGBSampleError{image}` retains unsupported file-export owners before the
output path is opened; `FloatRGBFileError{code,message}` preserves Base open/write
errors. PNG is selected explicitly regardless of filename. Valid writes share the
closed-handle boundary with float RAW files. Exact NaN payload interoperability,
other float layouts and generic export dispatch remain gaps.

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
python3 tools/float_rgb_png_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The private compressor matches 17 native comparisons / 170,780 encoded bytes,
including eviction, lazy matching, strict window edges, Adler boundaries and
stored-block sizes. Its empty-input result is compared as emitted by stb; PNG's
filtered image input is always nonempty.

The complete export gate compares 37 PNG images / 171,574 bytes against native
output. Native memory/file agreement is required for byte formats; packed sources
use the file oracle. Every candidate byte matches on CPU, JavaScript and forced
Metal, and complete decode round trips reproduce 172,340 normalized RGBA bytes. Native inspection
confirms that all five filters are selected for each supported byte format, and
both fixed/stored DEFLATE paths are exercised. Original RGBA8 fixtures remain covered.
CPU/JS also write 27 images per lane through the public Surface/formatted file APIs
and compare them byte-for-byte. GPU evidence covers pure encoding, not filesystem IO.
Shared 256-byte result framing preserves large outputs
without recursive whole-list formatting.

The altered stb algorithms retain [the selected MIT notice](../LICENSES/stb-image.txt).
See the original [RGBA8 evidence](evidence/png-export.json) and
[byte-format increment](evidence/png-export-formats.json) and
[formatted file export](evidence/png-export-files.json) for hashes and lane scope.

The float gate adds six memory profiles and five normalized file profiles,
comparing 1,892 native encoded bytes and 2,032 decoded RGBA bytes on CPU/JS/Metal.
CPU/JS also compare actual files and run 100 success/rejection/file-error cycles
under a 64-descriptor limit. Two pure rejection checks retain source samples,
and rejected writes preserve an existing sentinel file. Metal evidence covers
pure encoding/decoding, not filesystem IO. See
[evidence/float-rgb-png.json](evidence/float-rgb-png.json).

## Bounded R32 file export

Checked format-8 owners additionally support `Image.Formatted.write_png` through
native red-only normalized colors. Memory `to_png` remains rejected with its
owner retained; it does not silently substitute normalized file colors for the
native raw-bit memory path. See [R32.md](R32.md). Earlier evidence counts on this
page do not establish R32 behavior on Metal or additional hosts.
