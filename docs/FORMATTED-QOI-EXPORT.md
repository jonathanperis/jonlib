# Checked formatted QOI export

`Image.Formatted.to_qoi(image)` returns
`Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>`.
`Image.Formatted.write_qoi(image, path)` returns
`IO(Result<&1, &1, Image.Formatted.QoiWriteError, Unit>)`.
Both explicitly select QOI and adapt raylib 6.0 **`ExportImage`**. The pure
convenience returns complete immutable file bytes; it does not map to native
`ExportImageToMemory`, which implements PNG only.

## Original-format routing

The checked source domain is dimensions **1..4096** on each axis, one mip level
and complete native-order samples in formats **1..8** from the checked factory,
QOI memory/file loaders, Surface bridge or supported conversions. R32 samples
are finite `[0,1]`, including signed zero and positive subnormals. Inconsistent
manual `FormattedImage` constructors are outside this contract.

| Original format | Result | Output channels and source interpretation |
|---|---|---|
| 1 grayscale | Reject and retain owner | No grayscale replication |
| 2 gray-alpha | Reject and retain owner | No gray/alpha conversion |
| 3 RGB565 | Reject and retain owner | No packed-color expansion |
| 4 RGB888 | Accept and consume owner | Header 3; exact R,G,B with internal alpha 255 |
| 5 RGB5A1 | Reject and retain owner | No packed-color expansion |
| 6 RGBA4 | Reject and retain owner | No packed-color expansion |
| 7 RGBA8888 | Accept and consume owner | Header 4; exact R,G,B,A, including hidden RGB at alpha 0 |
| 8 R32 | Reject and retain owner | Neither raw-byte PNG interpretation nor red-only normalization |

Pinned `rtextures.c` performs a second format check inside the QOI export branch:
only the **original** RGB888/RGBA8888 formats reach `qoi_write`. Its generic
`LoadImageColors` preparation for other formats does not make them eligible.
Jonlib rejects them before conversion or file IO. Native temporary allocations,
logging and allocation-failure behavior are outside this adapter's contract.
Rejection of formats 1/2/3/5/6/8 is native QOI behavior, not a missing conversion
feature.

Accepted conversion is integer-only through `Formats.packed_colors`:
format 4 logical `0x00BBGGRR` becomes canonical `0xRRGGBBFF`; format 7
`0xAABBGGRR` becomes `0xRRGGBBAA`. It never uses normalized `Formats.decode`,
`Formats.encode`, `Image.Formatted.convert` or `to_surface` as preparation.
Only `width*height` samples are traversed, excluding padded Array capacity.

## Exact encoded bytes

The file begins with `qoif`, big-endian width/height, channels **3 or 4** as
above, and colorspace **0** (`QOI_SRGB`). Pixels retain top-down, row-major order
without padding, row flips or state resets. The standard eight-byte marker
`00 00 00 00 00 00 00 01` is followed immediately by EOF.

The shared encoder starts with opaque black as its previous pixel and 64
transparent-black cache entries. Equal pixels accumulate RUN; runs cap at 62,
cross rows and flush before a changed pixel or at EOF. Runs do not populate the
cache. Changed pixels first try INDEX, otherwise update the cache and select
RGBA on alpha change, then DIFF, LUMA or RGB in that order. DIFF accepts signed
wrapped channel deltas -2..1; LUMA accepts green -32..31 and red/blue-minus-green
residuals -8..7. The cache hash is `(r*3 + g*5 + b*7 + a*11) & 63`.
Alpha and hidden RGB participate in equality and hashing.

The native encoder narrows differences through `signed char`. Matching its
wrap-boundary bytes requires an eight-bit-byte, two's-complement signed-char
narrowing profile; local native controls do not qualify unrun host profiles.

The private `Qoi.encode.channels` entry accepts only channels 3/4 and canonical
RGBA words, with every alpha exactly 255 for channel 3. It is not a public
arbitrary-RGBA alpha-discard encoder. A format-4 source and an equivalent opaque
format-7 source have identical payload and marker, differing only at header
byte 12. Format 7 always keeps header 4, even if every pixel is opaque.
`Qoi.encode` remains the channel-4 wrapper, preserving existing Surface bytes.

A channel-3 source stream may contain RGBA opcodes that affect its decoder's
hidden cache state. The decoded format-4 owner stores RGB only; re-export uses
opaque alpha and cannot resurrect discarded alpha. Neither formatted owner
stores the input QOI colorspace: re-export of colorspace 1 writes colorspace 0.
Canonical output therefore need not reproduce the original stream; the oracle
is native `ExportImage` on the same original-format owner.

Tail-recursive traversal and conservative bounds `22 + 4*width*height` for RGB
and `22 + 5*width*height` for RGBA keep size/index arithmetic within U32 and
native int. At 4096×4096 these bounds are **67,108,886** and **83,886,102 bytes**.
They are arithmetic bounds, not maximum-area allocation or performance evidence.

## Ownership and file IO

Pure rejection returns `(original_image, UnsupportedPixelFormat{})`, retaining
the exact dimensions, format and every source byte. Pure success consumes the
owner. The scoped writer error is:

```bend
type Image.Formatted.QoiWriteError is Type:
  QoiSourceError{image: Image.Formatted}
  QoiFileError{code: U32, message: String}
```

`QoiSourceError` is solely unsupported-original-format rejection. It returns the
exact owner before `File.open`, including on missing-parent or directory paths,
and leaves existing files unchanged and absent targets absent. Rejected owners
can be reused for another checked operation. Accepted success, open failure
and write failure consume the owner. `QoiFileError` preserves Base's exact code
and message.

The codec is explicit for ordinary non-NUL paths: `.qoi`, `.QoI`, `.dat`, a
misleading `.png` suffix and suffixless names all select QOI. This does not
broaden native filename dispatch or add `Image.Formatted.write_image`.

The writer reuses `Surface.qoi.opened` and `Surface.ppm.written`, closing every
successfully acquired handle after its write attempt. Success replaces file
contents; post-open failure can truncate or partially write. No atomicity or
durability is promised. Base `File.close -> IO(Unit)` cannot report close
errors. Native QOI checks write/flush failures but ignores `fclose`'s result;
Base's typed errors are a language adaptation, not native failing-device,
short-write or close-error equivalence.

## Verification and local evidence

```sh
python3 tools/formatted_qoi_export_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

The [focused probe](../tools/formatted_qoi_export_probe.py) compares every byte
from actual native `ExportImage(.qoi)`, candidate pure output and
sentinel-replacing explicit candidate files. Native
`LoadImageFromMemory(".qoi")` observes dimensions, mipmaps, original format and
raw bytes before normalization; formatted QOI memory/file decoding and legacy
Surface decoding provide separate observations. An independent strict Python
parser validates headers, operands, run bounds, pixel count, marker and EOF
while collecting actual opcode coverage. It decodes semantics without
reimplementing encoder selection to manufacture expected file bytes.

The 2026-10-02 focused run passes on local **Linux x86-64 CPU-one-thread,
CPU-two-thread and JavaScript**. Each lane checks **295 source cases**
(**273 accepted / 22 rejected**) covering **382,078 total source pixels**,
**1,415,214 encoded bytes**, **1,373,353 decoded original-format bytes** and
**1,409 tagged observations** in batches of at most 16 source cases. Full results
and receipts are in [formatted-qoi-export.json](evidence/formatted-qoi-export.json).

The corpus discriminates initial/noninitial run lengths
1/2/61/62/63/64/123/124/125, EOF and followed-by-change variants, row-crossing
runs, index hits/collisions, DIFF/LUMA thresholds and wrapping, alpha-only and
hidden-RGB changes, byte ramps, padded capacities, unequal rows, both 4096-axis
bounds, complete 33,024-pixel traversals and seeded mixtures. Parsed native
output covers **all six opcode families, 63 DIFF opcodes and all 64 INDEX
slots**; the missing zero-delta DIFF correctly selects RUN. **Twelve isolated
just-outside DIFF controls require LUMA fallback**, supplementing the LUMA
boundary matrix. Paired RGB/opaque-RGBA payloads, factory/Surface-bridge/decode/
load owners, colorspace-1 and channel-3 hidden-alpha input streams verify
routing and canonicalization. The separate 513×513 changing-alpha RGBA source
exports **1,315,867 bytes**, checked through direct bytes and QOI-specific
loading rather than the unrelated generic raster cap.

All six rejected formats preserve exact owners through writer-to-pure rejection
and export chains, keep existing sentinels unchanged and leave absent targets
absent. Native rejected packed/R32 fixtures use complete correctly typed storage
because raylib prepares colors before its QOI rejection. Native R32 controls
stay within the checked finite `[0,1]` domain, including signed zeros,
subnormals and truncation-neighbor samples; unsafe native casts are excluded.
The native oracle verifies raw bytes before and after `ExportImage` and never
receives short or malformed backing.

Each lane additionally performs **801 accepted-source and 7,200 retained-source
IO calls**. Under `RLIMIT_NOFILE=64`, 100 cycles per accepted format cover
success, exact ENOENT and exact EISDIR, interleaved with retained-source
rejections and followed by a final successful write. A separate
`RLIMIT_FSIZE=0`/ignored-SIGXFSZ run performs 100 forced post-open EFBIG calls
per accepted format and checks zero-byte truncation. Direct Base operations
establish exact per-lane error codes and messages; EMFILE cannot substitute for
EFBIG. These are ordinary-file leak-detection checks, not a universal closure
or native failing-device theorem.

The gate clean-builds the pinned raylib archive with **GNU 14.2.0** and uses a
**Clang 19.1.7** native reference plus pinned **Bun 1.3.12** candidate tooling.
Nine native qualification controls include the exercised signed-char wrap
profile. It retains **1,979 sealed artifacts**, **2,217 artifact hashes** and
**140 library/dependency source hashes**. Fresh namespaces, exact input/output
framing, full chunk validation, sealed programs/binaries/receipts and source/
toolchain drift checks reject stale or partial evidence. Failed-report admission
precedes argument validation, including late/duplicate build-directory options.
The **331.715-second** duration is a local harness timing, not performance parity.

All **472 Python tests**, including **29 focused guardrails**, pass. Complete
pinned `PROOF.bend` reports `All terms check.` for **127 laws**, retaining the
previous 115. Twelve new scoped facts cover all-eight-format routing, RGB/RGBA
integer sample packing, empty packing traversal and the Surface encoder's
channel-4 wrapper equality. They do not establish universal codec correctness
or host IO/allocation/closure.

Existing formatted QOI memory/file and Surface suffix-export regressions pass
against the implementation. The final-metadata-bound canonical run passes
**261 scenarios / 40,101 words** on CPU-1/CPU-2/JavaScript, including exact
all-field replay, **333 QOI bytes / 23 palette words** per lane and every trailing
contract, decoding, PPM example and QOI file-roundtrip check. See
[VERIFICATION.md](VERIFICATION.md#checked-formatted-qoi-export-2026-10-02) for
regression scope. Historical decoding/loading evidence is not substituted for
the new focused exporter pass. CI now invokes this gate and retains its artifacts;
configuration does not establish a hosted run.

## Scope and provenance

`raylib:function:ExportImage` remains **partial**, with no native-API start or
completion-count increase and no weakened completion gate.
`ExportImageToMemory` is unchanged. The focused pass qualifies this explicit
checked-owner slice on the recorded host and lanes. JPEG/KTX, non-Surface suffix
dispatch, FloatRGB QOI, other source owners/mipmaps where natively relevant,
configured options, native callbacks/allocation ABI, unrun targets/GPU,
maximum allocation and full integration/resource/performance coverage remain
outside this slice. Focused export evidence cannot establish aggregate
conformance or resolve unrelated native-angle qualification blockers.

The encoder is an altered Bend adaptation of Dominic Szablewski's QOI codec in
pinned raylib `src/external/qoi.h`; routing adapts raylib `src/rtextures.c`.
Complete [QOI MIT](../LICENSES/qoi.txt) and [raylib zlib](../LICENSES/raylib.txt)
notices are retained, with the altered-source description in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). No native codec is linked
into the candidate and no new dependency is introduced.
