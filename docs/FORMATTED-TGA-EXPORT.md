# Checked formatted TGA export

`Image.Formatted.to_tga(image) -> +List<U32>` consumes a checked single-mip
formatted owner and returns complete immutable TGA file bytes.
`Image.Formatted.write_tga(image, path)` consumes the owner and returns
`IO(Result<&1, &1, U32 & String, Unit>)`. The codec is explicit even for `.dat`
filenames. Both adapt raylib 6.0 **`ExportImage`**; the pure convenience does not
map to `ExportImageToMemory`, which has no native TGA dispatch.

## Domain and exact bytes

The checked source domain is dimensions **1..4096** on each axis, format codes
**1..8**, one mip level and complete native-order samples from the checked
factory or supported owner bridges. R32 is finite `[0,1]`, including both signs
of zero and positive subnormals. Inconsistent manual constructors are outside
this contract. Existing Surface and FloatRGB TGA bytes remain unchanged.

| Source format | Channels | Image type | Depth | Descriptor | Pixel bytes |
|---|---:|---:|---:|---:|---|
| 1 grayscale | 1 | 11 | 8 | 0 | Gray |
| 2 gray-alpha | 2 | 11 | 16 | 8 | Gray, alpha |
| 4 RGB888 | 3 | 10 | 24 | 0 | BGR |
| 3/5/6/7/8 | 4 | 10 | 32 | 8 | BGRA |

The header is exactly 18 bytes, with little-endian dimensions and the type,
depth and descriptor shown above; every remaining field is zero. Rows are bottom-up, pixels within each row left-to-right; no padding,
ID, color map or footer is emitted. Alpha and transparent hidden RGB participate
in equality and are retained.

Packed and R32 expansion follows native **`LoadImageColors`**, never normalized
`ImageFormat` or `Image.Formatted.to_surface`: RGB565 expands with multipliers
8/4/8, RGB5A1 with 8/8/8 and alpha 0/255, RGBA4 with 17 per nibble. RGB565
`0xffff` therefore exports `(248,252,248,255)`. R32 truncates F32 `sample*255`
into red, with green/blue zero and alpha 255. Byte formats retain their channels.

Default native RLE restarts at every row and caps packets at 128 pixels. An
equal initial pair selects repetition; an unequal pair selects raw scanning.
The pinned raw scan compares the incoming pixel with the pixel two positions
earlier and shortens its tentative length on equality. Thus ABA emits raw(1)
then raw(2), while ABBC emits raw(4). A trailing singleton is raw. These exact
packet bytes, not just decoded pixels, define the profile.

The shared encoder compares canonical words after expansion. This preserves
native component equality for gray/gray-alpha/RGB and deliberately coalesces
R32 words that export the same red byte, including signed zeros and distinct
subnormals. Its internal channel-aware entry requires these normalized unused
components determined by the emitted channels; it is not a public arbitrary-RGBA channel-discard encoder.

Full traversals are tail-recursive and row lists are bounded by checked width.
The conservative bound `18 + 5*width*height` is at most **83,886,098 bytes** and
keeps all size/index arithmetic within U32. This is an arithmetic bound, not
measurement of the maximum square or a performance guarantee.

## Ownership and IO

The pure API consumes the owner. The writer consumes it on success, open error
and write error, preserving Base's exact error code and message. It uses the
existing closed-handle writer and closes every successfully opened file after
the write attempt. No failed owner is returned.

Success replaces an existing file. Post-open failure may leave a truncated or
partial file; no atomicity or durability is promised. Base `File.close -> IO(Unit)`
cannot expose close errors. Native stb ignores some short-write/close results;
typed Base error handling is a language adaptation, not native failure-return
parity.

## Verification design

```sh
python3 tools/formatted_tga_export_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

The probe clean-rebuilds the pinned raylib archive, qualifies integer/F32 native
expansion separately and calls actual `ExportImage` into `.tga` files. Packed16
and R32 inputs use aligned typed allocations, copying raw bytes into typed
scalars then assigning through matching typed pointers. A full byte comparison
rejects normalization of any input word before native export.

Each image compares complete pure bytes, actual sentinel-replacing `.dat` files,
native decoded dimensions/original formats (1/2/4, otherwise 7), native RGBA
pixels, Jonlib `Surface.decode_tga` pixels and an independent strict Python
decoder. The latter validates exact headers, row-bounded packet lengths, complete
payloads, orientation, pixel count and EOF without reusing packet selection.

All formats cover widths 1..4 with unequal rows, run/raw lengths
1/2/3/127/128/129/130/255/256/257, ABA/ABBC/AAB/ABB/mixed sequences, identical
consecutive rows, three-row orientation, both 4096-pixel axes, complete 33,024
pixel traversals and seeded 257×2 mixtures. Additional controls cover alpha-only
changes, hidden RGB, packed boundaries/seeded words and R32 truncation neighbors
and expanded run collapse. One 513×513 raw RGBA image exceeds the generic file
loader's separate 1 MiB cap and is checked through direct bytes/native/pure decode.

Each lane performs 100 IO cycles per format for success, exact ENOENT, exact
EISDIR, and a separate `RLIMIT_FSIZE=0`/ignored-SIGXFSZ run requiring exact EFBIG.
A 64-descriptor limit detects leaks; EMFILE cannot pass as expected EFBIG.
Direct Base operations provide exact per-lane code/message baselines. Sentinels
check open-error preservation and expected post-open truncation.

Strict typed framing, chunk counts, fresh per-run namespaces, sealed inputs,
programs, binaries and receipts, source/toolchain drift checks and retained raw
stdout/files reject stale or incomplete evidence. Exact `--build-dir` destinations
are pre-admitted as failed before help/type/option errors, including late and
duplicate options, while respecting `--` and argparse value classification.
Six scoped routing/empty-traversal laws supplement the differential checks;
there is no universal codec or numerical proof.

The 2026-10-02 focused run passes **304 images / 619,451 pixels** per lane,
comparing **2,212,918 encoded bytes / 2,477,804 decoded RGBA bytes**, plus
**3,200 formatted IO checks** per lane. The large 513×513 case exports
**1,055,259 bytes**, exceeding the generic raster-loader cap without
using that loader as an oracle. The run retains **2,298 sealed artifacts**,
**2,462 artifact hashes** and **136 source/dependency hashes**. Its
**417.396-second** elapsed time is a local harness observation, not performance
parity. All **391 Python tests**, including **32 new focused tests**, pass;
complete `PROOF.bend` checks **105 laws**.

The checkpoint evidence is
[formatted-tga-export.json](evidence/formatted-tga-export.json).

No new GPU, hosted, other-platform, exhaustive-input or performance claim is
made. JPEG/KTX, non-Surface suffix dispatch, wider formats/options,
native ABI and full integration/resource/platform/performance parity remain open.
The altered source retains the complete [stb MIT notice](../LICENSES/stb-image.txt)
and provenance in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

The separately qualified [checked formatted QOI export](FORMATTED-QOI-EXPORT.md)
supports original RGB888/RGBA8888 and retains the six other checked formats
before IO, matching native QOI rejection. Its local CPU/JavaScript evidence is
independent of this profile and does not add non-Surface suffix dispatch.
