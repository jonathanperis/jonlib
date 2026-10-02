# Owned byte/integer and bounded R32 image formats

`Image.Formatted` stores an owned single-mip image in native format codes 1..8:
grayscale, gray-alpha, RGB565, RGB888, RGB5A1, RGBA4, RGBA8888 and bounded R32.
R32 accepts finite `[0,1]` samples, positive subnormals and both zero signs;
see [R32.md](R32.md) for its red-only native normalization and explicit gaps. Dimensions are
1..4096. Internal storage has one logical packed U32 per pixel; exported bytes
follow the native little-endian layout. Allocation size and C pointer ABI are
separate compatibility gaps.

| API | Contract |
|---|---|
| `Image.Formatted.from_bytes(width, height, format, bytes) -> Maybe<Image.Formatted>` | Checks supported dimensions/format, byte values 0..255, exact required byte count and the R32 sample domain before allocation. |
| `Image.Formatted.decode_qoi(bytes)` | Checked QOI owner factory preserving native RGB888 (4) or RGBA8888 (7), single-mip metadata and exact bytes; existing typed decode errors. See [CODECS.md](CODECS.md#format-preserving-qoi-memory-loading). |
| `Image.Formatted.load_qoi(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)` | Checked ordinary-file QOI owner factory with explicit suffix-independent selection, native format 4/7, exact bytes and an implicit single mip level; shared inclusive 83,886,102-byte cap and typed file/decode errors. See [IMAGE-FILES.md](IMAGE-FILES.md#format-preserving-qoi-file-loading). |
| `Surface.to_formatted(surface) -> Image.Formatted` | Consumes canonical RGBA8 Surface storage and produces format 7 with exact byte order. |
| `Image.Formatted.convert(image, target)` | Returns `Result<&1, &1, Image.Formatted & Pixel.Error, Image.Formatted>`. Same-format and target-zero requests return the original image. Unsupported targets return the original owner with `UnsupportedPixelFormat`. |
| `Image.Formatted.to_surface(image) -> Surface` | Consumes the image and performs the reference conversion to RGBA8, then adapts byte order to Surface's `0xRRGGBBAA` words. |
| `Image.Formatted.to_float_rgb(image) -> Image.FloatRGB` | Consumes formats 1..8 with native F32 normalization and packed reciprocal expansion, dropping alpha without intermediate RGBA8 quantization; R32 becomes `(value,0,0)`. |
| `Image.Formatted.from_channel(image, selected)` | Retains the owner and returns `Maybe<Image.Formatted>` with an independent native grayscale channel; see [IMAGE-CHANNELS.md](IMAGE-CHANNELS.md). |
| `Image.Formatted.colors(image)` / `get(image, x, y)` | Native bulk colors consume the owner; point reads retain it with a bounded `Maybe` result. Packed expansion follows `LoadImageColors`/`GetImageColor`; see [IMAGE-COLORS.md](IMAGE-COLORS.md). |
| `Image.Formatted.export(image)` | Consumes ownership and returns `((width, height), (format, bytes))`, with every native-order byte and no storage padding. |
| `Image.Formatted.to_png(image)` | Default PNG memory export for byte formats 1/2/4/7 and raw four-byte R32 words; unsupported packed formats retain their owner in `Fail`. See [PNG-EXPORT.md](PNG-EXPORT.md). |
| `Image.Formatted.write_png(image, path)` | Default PNG file export for checked formats 1..8, preserving native packed-color expansion and R32 red-only normalization. See [PNG-EXPORT.md](PNG-EXPORT.md). |
| `Image.Formatted.to_bmp(image)` / `write_bmp(image, path)` | Exact native BMP file bytes for all checked formats 1..8, with consuming pure/typed-IO interfaces. See [FORMATTED-BMP-EXPORT.md](FORMATTED-BMP-EXPORT.md). |
| `Image.Formatted.to_qoi(image) -> Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>` / `write_qoi(image, path) -> IO(Result<&1, &1, Image.Formatted.QoiWriteError, Unit>)` | Explicit native QOI file bytes for original RGB888 (4) / RGBA8888 (7), header channels 3/4; other checked formats retain their exact owner before IO. Accepted writes consume the owner and close acquired handles. Local Linux x86-64 CPU-1/CPU-2/JavaScript evidence is recorded in [FORMATTED-QOI-EXPORT.md](FORMATTED-QOI-EXPORT.md). |
| `Image.Formatted.to_code(image, path)` / `write_code(image, path)` | Exact native image-as-code text and typed file export for bounded payloads/ASCII names. See [IMAGE-CODE.md](IMAGE-CODE.md). |

Create owners with the checked byte factory, QOI memory/file loaders or Surface bridge. Manually inconsistent
`FormattedImage{width, height, format, pixels}` values are outside the contract.
`Image.Formatted.load_raw` (formats 1..7) and `write_raw` provide file boundaries with explicit
header/error/closure behavior, documented in [RAW-FILES.md](RAW-FILES.md).

The QOI file factory has separate [local Linux x86-64 file evidence](evidence/qoi-formatted-files.json)
on CPU-one-thread, CPU-two-thread and JavaScript: native format 4/7 metadata and
every raw byte are observed before normalization. Its file-boundary, resource
and unrun-target scope is recorded in [IMAGE-FILES.md](IMAGE-FILES.md#formatted-qoi-file-evidence)
and the [verification entry](VERIFICATION.md#format-preserving-qoi-file-loading-2026-10-02);
historical formatted-memory evidence does not qualify file IO by itself.

## Conversion arithmetic

The implementation follows `ImageFormat` through its normalized F32 channel
representation. Packed source channels multiply by the reference reciprocal
of 31/63/15. Destination formats retain their original luminance, rounding,
truncation and strict RGB5A1 alpha threshold. Conversion does not first reduce
the source to RGBA8, which could discard precision before the next quantization.

This path is intentionally separate from `GetPixelColor`. In particular,
RGB5A1 blue is extracted from bits 1..5 during `ImageFormat`, whereas the pinned
raw pixel getter uses the low five bits including alpha. The formatted-image
converter follows the former. Same-format conversions preserve bytes directly
instead of applying an unnecessary normalization round trip.

## Evidence

```sh
python3 tools/image_format_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The expanded probe compares all 64 source/destination pairs, target-zero no-ops,
conversion chains and Surface bridges: 165 complete native cases / 173,303 bytes
per CPU/JavaScript lane. It covers 1,119 R32 boundary samples, 45 rejected-factory
controls and a complete 33,024-pixel signed-zero/subnormal import. Chunked test
output retains strict framing and every compared byte while avoiding a separate
Base `List.show` stack limit. `--gpu` requests an additional forced-Metal run;
the R32 expansion has not been executed on GPU.

The earlier [byte/integer evidence](evidence/image-format-conversion.json)
records 49 pairs / 109 cases / 3,192 bytes on CPU/JS/Metal, plus the existing
ownership/factory contracts. Those old target results do not establish R32
behavior on Metal or other native arithmetic profiles.

The separate [RGB float bridge](FLOAT-RGB.md) supports owned format-9 conversion
to/from Surface using its separate three-channel owner.
Its [raw-byte interface](FLOAT-RGB-BYTES.md) preserves non-NaN format-9 words.
`Image.FloatRGB.to_formatted` additionally converts finite `[0,1]` floats directly
to formats 1..7 with native luminance/packed rounding, avoiding RGBA8 pre-quantization.
Other float/half/compressed formats, mipmaps, other configured alpha thresholds,
big-endian/native pointer layouts and full target/resource/performance evidence
remain open.

The bounded [R32 extension](R32.md) additionally covers red-only image colors,
sole-channel extraction and file export, with explicit numerical/target gaps.
