# Binary PGM/PPM memory decoding

The dedicated memory APIs accept the same checked binary P5 grayscale or P6 RGB
input, with dimensions 1..4096 and a declared maximum sample value (`maxval`) in
1..65535:

- `Surface.decode_pnm(bytes: +List<U32>)` returns
  `Result<&1, &1, Image.DecodeError, Surface>` with owned opaque RGBA8 output
- `Image.Formatted.decode_pnm(bytes: +List<U32>)` returns
  `Result<&1, &1, Image.DecodeError, Image.Formatted>` with native grayscale (1)
  or RGB888 (4) output and an implicit single mip level

Decimal header values are bounded before arithmetic. Every input byte must be
0..255, including bytes in ignored tails or discarded halves of wide samples.

## Native parsing and sample rules

- Whitespace and `#` comments are handled between numeric header fields. Comments
  terminate at CR or LF; space, HT, LF, VT, FF and CR are recognized.
- After `maxval`, exactly **one whitespace byte** is consumed. Additional bytes
  belong to the raster, even if they are whitespace or `#`. A CRLF separator
  therefore leaves LF (`10`) as the first raster byte, matching the pinned reader.
- Samples are retained **without rescaling or clamping**, including when `maxval`
  is below 255 or a sample exceeds that declared value. Surface P5 samples are
  replicated into RGB, and all Surface output alpha values are 255.
- `maxval` 1..255 selects one byte per sample; 256..65535 selects two. For the
  pinned **little-endian native profile**, two-byte samples retain their **second
  stored byte**. Native stb copies the PNM bytes into host U16 values without
  swapping and later shifts those values right by eight during 8-bit conversion.
  Thus stored bytes `12 34` produce `34`, not `12`. Jonlib deliberately preserves
  this raylib behavior rather than standard big-endian PNM interpretation.
- Both public results contain **8-bit samples**, even for 16-bit input. The actual
  pinned `LoadImageFromMemory` route calls stb's 8-bit loader; preserving its
  native output format does not preserve source sample depth or `maxval` metadata.
- Complete row-major sample data is required. Valid trailing bytes are ignored.

All bytes are validated before header parsing, so `InvalidImageByte` takes
precedence over header, size or truncation failures. Unsupported magic, invalid
numeric fields, decimal overflow, missing fields, maxval outside 1..65535 or a
non-whitespace consumed maxval delimiter return `InvalidImageHeader`. A valid
header with dimensions outside 1..4096 returns `UnsupportedImageSize`; invalid
maxval takes precedence over a bad size. Too few raster bytes return
`TruncatedImageData`. These PNM routes do not emit `InvalidImageStream`.

Header and dimension checks precede the raster-length check and output
allocation. Jonlib's positive maxval and whitespace-delimiter requirements are
checked adaptations: the native parser accepts some malformed headers that
Jonlib rejects. Checked-invalid inputs are not claimed as native rejections.
The largest derived raster requirement is 100,663,296 bytes; this is neither an
encoded-list cap nor a maximum-allocation success guarantee. Validation still
traverses the entire immutable input list.

The native supported `.ppm`, `.pgm`, `.PPM` and `.PGM` tokens select the shared
PNM-capable raster decoder. Payload magic determines channels: P5 under `.ppm`
is still grayscale and P6 under `.pgm` is still RGB. This does not add arbitrary
mixed-case memory tokens or a formatted file-dispatch contract. The explicit
memory factories have no filename or extension argument. The separate
`Surface.to_ppm` exporter writes inspectable P3 text; the native PNM loader does
not accept ASCII P1..P3 or binary PBM P4. Shared RGBA8 memory/file dispatch is documented in
[IMAGE-FILES.md](IMAGE-FILES.md).

## Format-preserving PNM memory loading

`Image.Formatted.decode_pnm` preserves width/height and native P5 format **1
(grayscale)** or P6 format **4 (RGB888)**. Export consumes the owner and returns
exactly `width*height` G bytes or `width*height*3` R,G,B bytes, row-major and
without array padding. Grayscale logical U32 words have their high 24 bits zero;
RGB888 logical words have their high byte zero. Integer extraction and packing
avoid floating-point luminance conversion, which could alter grayscale bytes.

The reusable immutable input list is separate from the single affine pixel owner
returned on success. Failure returns only the typed error, never a partial
image. Point reads return ownership alongside their `Maybe` result; callers
must thread the owner through both in-bounds and rejected reads. Export and
`Image.Formatted.to_surface` consume the owner. The existing Surface PNM APIs
and generic Surface dispatch retain their opaque RGBA8-normalized behavior.

This increment belongs only to the partial `raylib:function:LoadImageFromMemory`
entry. PNM formatted file loading, generic formatted/float dispatch, other
original codec formats and full-depth sample APIs remain open. It does not
expand `LoadImage`, `ImageFormat`, `ExportImage`, the image types or PNM
configuration-control completion. Big-endian and nondefault stb flag profiles,
permissive malformed recovery, larger dimensions, native pointer/allocation ABI,
OOM parity and complete integration/resource/performance evidence remain gaps.

## Formatted-memory verification

The [focused local Linux x86-64 evidence](evidence/pnm-formatted.json) passes
**96 native images / 64,482 pixels**, with **120,514 raw format-1/4 bytes** and
**257,928 separately normalized bytes**, excluding additional alias observations.
There are **234 native observations** including aliases. Each independent
CPU-one-thread, CPU-two-thread and JavaScript lane compares **710 records /
885,750 bytes** in 23 batches: **361,542 raw bytes** and **524,208 normalized
bytes**, with zero differences. **73 checked-invalid controls** exercise both
the new formatted and unchanged Surface decoder; none is passed to native.

The matrix retains all 30 historical accepted streams and adds both kinds/depths,
full grayscale and distinct RGB ramps, wide-byte retention/discard controls,
maxval boundaries including 255/256/257, all six separators, padded shapes, both
4096-axis endpoints and 5,103-pixel nonuniform images. Raw factory exports and
threaded in-bounds/rejected point reads retain exact bytes and logical high-bit
invariants. Payload magic, not the PGM/PPM alias, determines native channels.

The full proof verdict is `All terms check.` for **132 laws**, preserving 127
and adding five scoped channel/packing/empty-traversal laws. These are structural
facts, not a universal codec proof. All **495 Python tests**, including **23
focused harness tests**, pass without skips. The unchanged formatted QOI memory
regression also passes on CPU-one-thread/CPU-two-thread/JavaScript.

Fresh canonical clean-loader conformance passes **261 scenarios / 40,101
pixel/numeric words** on CPU-one-thread, CPU-two-thread and JavaScript. Strict
full-record replay also checks **333 QOI bytes and 23 palette words per lane**;
ownership/transform/decode contracts, PPM examples and legacy QOI file IO pass.

Fresh unchanged Surface regressions pass on CPU/JavaScript: normalized PNM has
**30 images / 8,844 pixels and 16 typed controls**; generic memory dispatch has
**534 token/content pairs (462 native loads) and five typed controls** across
nine batches per lane; generic file dispatch has **59 native file cases, three
boundary controls and 100 low-descriptor cycles at limit 64 per lane**. These
three scripts use a verified clear inherited loader context and the fresh
canonical archive, with its PNM configuration/compiler/archive hashes retained.
They establish regressions for existing Surface APIs, not PNM formatted-file
loading. Historical Surface GPU results below do not qualify the new adapter
on GPU/Metal or any unrun OS/hosted target.

```sh
python3 tools/pnm_format_probe.py --reference-env clean-loader --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 -m unittest discover -s tests -p test_pnm_format_harness.py -v
```

The dedicated gate uses actual pinned `LoadImageFromMemory`, observes actual
width/height/mipmaps/format and every raw byte before `ImageFormat(...,7)`, then
compares separate normalized regressions. Candidate mipmaps are the owner's
implicit contract, not a stored/measured field. Complete, independently
validated accepted fixtures alone may reach the native decoder; all malformed
or oversized controls stay in checked Jonlib.

The fresh isolated native archive has verified `CUSTOMIZE_BUILD=ON` and
`SUPPORT_FILEFORMAT_PNM=ON`: pinned raylib disables PNM by default. Actual native
little-endian/PNM qualification, build settings, compiler/archive/source hashes
and `clean-loader` child-environment receipts are sealed. The archive uses GNU
14.2.0, the reference uses Clang 19.1.7 and the candidate uses pinned Bun 1.3.12.
The parent loader environment is unchanged; no stale archive is borrowed. All
lanes enforce strict complete-byte framing and source/artifact drift checks.
An earlier cache-parser attempt failed before native archive build, then an
expanded parser test and a fresh full-suite/probe retry passed; both receipts
are retained. CI wiring is a future gate, not hosted verification evidence.

## Historical Surface verification

```sh
python3 tools/pnm_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The historical shared bitmap gate compares 30 native images / 8,844 pixels and
16 typed-error controls on CPU, JavaScript and forced Metal, including 4096×1
and 1×4096 images. Its native oracle converts to RGBA8 before inspection, so
it does not establish native format 1/4 metadata or original raw byte lengths.
The 16-bit cases exercise maxval boundaries, all 256 retained byte values,
channel ordering, CRLF consumption, trailing data and incomplete samples/channels.
Invalid discarded bytes are still rejected. Shared memory/file gates include a
16-bit PPM payload. Hashes and historical lane results are in
[evidence/pnm-16bit.json](evidence/pnm-16bit.json). The altered stb reader retains
the MIT notice in [LICENSES/stb-image.txt](../LICENSES/stb-image.txt).
