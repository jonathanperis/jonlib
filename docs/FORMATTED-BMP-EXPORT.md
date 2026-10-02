# Checked formatted BMP export

`Image.Formatted.to_bmp(image) -> +List<U32>` consumes a checked single-mip
formatted owner and returns immutable, complete native BMP file bytes.
`Image.Formatted.write_bmp(image, path)` consumes the same owner and returns
`IO(Result<&1, &1, U32 & String, Unit>)`. Its codec is explicit, including for
filenames ending in `.dat` or another suffix.

These operations adapt raylib 6.0 **`ExportImage`**. The pure convenience does
not map to `ExportImageToMemory`, which has no native BMP dispatch. Existing
Surface and FloatRGB BMP exports keep their existing contracts and bytes.

## Checked source domain and exact layout

Inputs are owners created by `Image.Formatted.from_bytes` or supported owner
bridges/conversions: dimensions **1..4096** on each axis, format codes **1..8**,
one mip level, and complete native-order packed samples. R32 format 8 accepts
finite `[0,1]`, both signs of zero and positive subnormals. Inconsistent manual
`FormattedImage` constructors are outside the public contract.

| Source | Native BMP layout | Pixel rule |
|---|---|---|
| 1: grayscale | 54-byte file/INFO header, 24-bit BGR | Replicate gray into three channels |
| 2: gray-alpha | Same 24-bit layout | Replicate gray; discard alpha without compositing |
| 4: RGB888 | Same 24-bit layout | Preserve RGB bytes |
| 3: RGB565 | 122-byte file/V4 header, 32-bit BGRA | Expand 5/6-bit channels with integer multipliers 8/4; alpha 255 |
| 5: RGB5A1 | Same V4 layout | Expand 5-bit channels with 8; alpha 0/255; blue excludes the alpha bit |
| 6: RGBA4 | Same V4 layout | Expand each nibble with 17 |
| 7: RGBA8888 | Same V4 layout | Preserve all channels, including hidden RGB and zero alpha |
| 8: R32 | Same V4 layout | Red is truncated `sample*255` in F32, green/blue zero, alpha 255 |

Rows are bottom-up. The 24-bit layout adds 0..3 zero bytes after each row to
align to four bytes; V4 needs no padding. V4 uses canonical RGBA masks and
`BI_BITFIELDS=3`. Both layouts retain the native zero `biSizeImage`, reserved,
resolution and color-count fields; V4 color-space/endpoints/gamma fields are
also zero. Complete file bytes, not just semantic pixels, define the profile.

Packed expansion follows **`LoadImageColors`**, not normalized `ImageFormat`.
For example, RGB565 `0xffff` exports `(248,252,248,255)`, rather than the
`(255,255,255,255)` produced by conversion to RGBA8. Consequently the exporter
must not route packed owners through `Image.Formatted.to_surface`.

Every full-image traversal is tail-recursive. The checked maximum gives at
most 16,777,216 pixels, 50,331,702 bytes for 24-bit output and 67,108,986 bytes
for V4 output, keeping size/index arithmetic within U32. This is an arithmetic
bound, not an assertion that the largest square was measured on every target.

## Ownership and IO

Both operations consume the source. The file writer also consumes it on open
or write failure, like the existing formatted PNG writer. It preserves Base's
exact error code and message and closes every successfully opened handle after
the write attempt. An open/write failure does not return the image owner.

Success replaces existing contents. A post-open write failure may leave a
truncated/partial file; no atomic or durable-write guarantee is added. Base's
`File.close -> IO(Unit)` cannot report close errors. Native stb BMP output may
ignore short-write/close failures, so typed Base error handling is a deliberate
language-level adaptation, not native failure-return parity.

## Verification

```sh
python3 tools/formatted_bmp_export_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

The focused gate clean-rebuilds the pinned native archive and separately checks
native integer/float color controls before generating BMP expectations with
actual `ExportImage`. Native packed/R32 fixtures use aligned typed allocations:
raw bytes are copied into typed scalars and assigned through correctly typed
pointers, then a full byte comparison rejects any word normalization before
export. Qualifier samples also use declared typed objects.
It compares complete pure bytes, real `.dat` files,
native decoded pixels and an independent Python decoder on CPU-one-thread,
CPU-two-thread and JavaScript. Strict metadata, byte chunks, record counts,
shape/layout checks, fresh output sentinels, source/toolchain drift checks and
retained raw programs/inputs/stdout prevent incomplete or stale evidence.

The corpus includes all eight formats at widths 1, 2, 3 and 4 with unequal rows;
six identical-gray/varying-alpha images; packed boundaries and seeded words;
R32 truncation neighbors, signed zeros and subnormals; thin rectangles;
4096-pixel axes; and 33,024-pixel traversals for every format. Independent
Python tests reject malformed/reordered/duplicate/missing/extra observations.

Repeated success, missing-parent and directory-open attempts use a 64-descriptor
limit. A separate `RLIMIT_FSIZE=0` run ignores `SIGXFSZ` and requires **EFBIG**
for every post-open write, preventing leaked descriptors producing EMFILE from
passing. Every returned error must equal the direct Base call's code and message.
Four structural padding laws supplement differential byte/channel evidence;
there is no universal codec/numeric proof.

The 2026-10-02 focused run passes **78 images / 331,465 pixels** per lane,
comparing **1,221,952 encoded bytes / 1,325,860 decoded RGBA bytes**. Each lane
adds **3,200 formatted IO calls**: 800 successful repeated writes, 800 missing-parent
errors, 800 directory errors and 800 post-open EFBIG failures. Four direct Base
calls establish the per-lane baselines. Nineteen Python guardrails and the
complete 99-law proof file pass. The gate retains 603 sealed artifacts and 677
artifact hashes; its 143.298-second local harness runtime is not performance parity.

The checkpoint evidence is [formatted-bmp-export.json](evidence/formatted-bmp-export.json).
No new GPU, hosted, other-platform, exhaustive-input or performance evidence
is implied. Formatted QOI/JPEG/KTX, non-Surface suffix dispatch, broader
float/half/compressed formats, options, native callbacks/allocation ABI and
complete integration/resource/performance parity remain open.

The BMP source retains its altered stb provenance and the complete
[MIT notice](../LICENSES/stb-image.txt).

Checked formatted TGA export is now a separate bounded contract in
[FORMATTED-TGA-EXPORT.md](FORMATTED-TGA-EXPORT.md).
