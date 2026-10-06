# Owned byte/integer and bounded R32 image formats

`Image.Formatted` stores an owned single-mip image in native format codes 1..8:
grayscale, gray-alpha, RGB565, RGB888, RGB5A1, RGBA4, RGBA8888 and bounded R32.
R32 accepts finite `[0,1]` samples, positive subnormals and both zero signs; see
[R32.md](R32.md) for its red-only native normalization and explicit gaps.
Dimensions are 1..4096. Internal storage has one logical packed U32 per pixel;
exported bytes follow the native little-endian layout. Allocation size and C
pointer ABI are separate compatibility gaps.

## Owners and factories

| API | Contract |
|---|---|
| `Image.Formatted.from_bytes(width, height, format, bytes) -> Maybe<Image.Formatted>` | Checks supported dimensions/format, byte values 0..255, exact required byte count and the R32 sample domain before allocation. |
| `Image.Formatted.decode_bmp(bytes)` | Checked BMP memory factory preserving native RGB888 (4) or RGBA8888 (7), exact bytes and implicit one mip; effective alpha layout selects channels independently of source bit depth or pixel opacity. See [BMP.md](BMP.md#format-preserving-bmp-memory-loading). |
| `Image.Formatted.decode_pic(bytes)` | Checked PIC memory factory preserving native RGB888 (4)/RGBA8888 (7), exact bytes and implicit one mip. Alpha in any validated packet selects RGBA even after later RGB-only packets or with all-opaque output. See [PIC.md](PIC.md#format-preserving-pic-memory-loading). |
| `Image.Formatted.decode_png(bytes)` | Checked PNG memory factory preserving native format 1/2/4/7, exact 8-bit component bytes and implicit one mip across the packed/8/16-bit, Adam7 and native-default CgBI domain. Structural tRNS promotes channels independently of opacity, including empty/all-opaque palette alpha and after later PLTE; full 16-bit keys are compared before high-byte narrowing. The inclusive 1 MiB encoded and 64 MiB filtered-stream caps apply. See [PNG.md](PNG.md#format-preserving-png-memory-loading). |
| `Image.Formatted.decode_tga(bytes)` | Checked TGA memory factory preserving native format 1/2/4/7, exact bytes and implicit single mip; indexed output follows palette depth independently of index width. See [TGA.md](TGA.md). |
| `Image.Formatted.decode_pnm(bytes)` | Checked P5/P6 memory factory preserving native grayscale (1) or RGB888 (4), exact reduced 8-bit samples and implicit single-mip dimensions. This does not preserve 16-bit source sample depth. See [PNM.md](PNM.md). |
| `Image.Formatted.decode_qoi(bytes)` | Checked QOI memory factory preserving native RGB888 (4) or RGBA8888 (7), single-mip metadata and exact bytes. See [CODECS.md](CODECS.md#format-preserving-qoi-memory-loading). |
| `Image.Formatted.load_png(path)` / `load_bmp(path)` / `load_pic(path)` / `load_tga(path)` / `load_pnm(path)` -> `IO(Result<&1, &1, Image.LoadError, Image.Formatted>)` | Checked ordinary-file factories with explicit suffix-independent codec selection, preserving the respective memory factory's native format and exact bytes. Shared inclusive 1 MiB pre-read cap, one exact-length read, typed file/decode errors and close-before-decode calls; the memory decoders' limits are unchanged. See [IMAGE-FILES.md](IMAGE-FILES.md). |
| `Image.Formatted.load_qoi(path) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>)` | Checked ordinary-file QOI factory with explicit suffix-independent selection, native format 4/7, exact bytes and implicit single mip; inclusive 83,886,102-byte cap. See [CODECS.md](CODECS.md#format-preserving-qoi-file-loading). |
| `Image.Formatted.load_raw` / `write_raw` | Headerless file boundaries (formats 1..7 and checked R32 format 8) with explicit header/error/closure behavior. See [RAW-FILES.md](RAW-FILES.md). |
| `Surface.to_formatted(surface) -> Image.Formatted` | Consumes canonical RGBA8 Surface storage and produces format 7 with exact byte order. |

Create owners only through these factories or the Surface bridge. Manually
inconsistent `FormattedImage{width, height, format, pixels}` values are outside
the contract.

## Operations

| API | Contract |
|---|---|
| `Image.Formatted.convert(image, target)` | Returns `Result<&1, &1, Image.Formatted & Pixel.Error, Image.Formatted>`. Same-format and target-zero requests return the original image. Unsupported targets return the original owner with `UnsupportedPixelFormat`. |
| `Image.Formatted.to_surface(image) -> Surface` | Consumes the image and performs the reference conversion to RGBA8, then adapts byte order to Surface's `0xRRGGBBAA` words. |
| `Image.Formatted.to_float_rgb(image) -> Image.FloatRGB` | Consumes formats 1..8 with native F32 normalization and packed reciprocal expansion, dropping alpha without intermediate RGBA8 quantization; R32 becomes `(value,0,0)`. See [FLOAT-RGB.md](FLOAT-RGB.md). |
| `Image.Formatted.from_channel(image, selected)` | Retains the owner and returns `Maybe<Image.Formatted>` with an independent native grayscale channel; see [IMAGE-CHANNELS.md](IMAGE-CHANNELS.md). |
| `Image.Formatted.colors(image)` / `get(image, x, y)` | Native bulk colors consume the owner; point reads retain it with a bounded `Maybe` result. Packed expansion follows `LoadImageColors`/`GetImageColor`; see [IMAGE-COLORS.md](IMAGE-COLORS.md). |
| `Image.Formatted.export(image)` | Consumes ownership and returns `((width, height), (format, bytes))`, with every native-order byte and no storage padding. |
| `Image.Formatted.to_png(image)` / `write_png(image, path)` | Default PNG memory export for byte formats 1/2/4/7 and raw four-byte R32 words (unsupported packed formats retain their owner in `Fail`); file export for checked formats 1..8, preserving native packed-color expansion and R32 red-only normalization. See [IMAGE-EXPORT.md](IMAGE-EXPORT.md). |
| `Image.Formatted.to_bmp(image)` / `write_bmp(image, path)` | Exact native BMP file bytes for all checked formats 1..8, with consuming pure/typed-IO interfaces. See [IMAGE-EXPORT.md](IMAGE-EXPORT.md). |
| `Image.Formatted.to_qoi(image) -> Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>` / `write_qoi(image, path) -> IO(Result<&1, &1, Image.Formatted.QoiWriteError, Unit>)` | Explicit native QOI bytes for RGB888 (4) / RGBA8888 (7), header channels 3/4; other checked formats retain their exact owner before IO. Accepted writes consume the owner and close acquired handles. See [IMAGE-EXPORT.md](IMAGE-EXPORT.md). |
| `Image.Formatted.to_code(image, path)` / `write_code(image, path)` | Exact native image-as-code text and typed file export for bounded payloads/ASCII names. See [IMAGE-CODE.md](IMAGE-CODE.md). |

## Conversion arithmetic

The implementation follows `ImageFormat` through its normalized F32 channel
representation. Packed source channels multiply by the reference reciprocal of
31/63/15. Destination formats retain their original luminance, rounding,
truncation and strict RGB5A1 alpha threshold. Conversion does not first reduce
the source to RGBA8, which could discard precision before the next quantization.

This path is intentionally separate from `GetPixelColor`. In particular, RGB5A1
blue is extracted from bits 1..5 during `ImageFormat`, whereas the pinned raw
pixel getter uses the low five bits including alpha. The formatted-image converter
follows the former. Same-format conversions preserve bytes directly instead of
applying an unnecessary normalization round trip.

The separate [RGB float owner](FLOAT-RGB.md) (format 9) converts to/from Surface,
preserves non-NaN format-9 words through its raw-byte interface, and
`Image.FloatRGB.to_formatted` converts finite `[0,1]` floats directly to formats
1..7 with native luminance/packed rounding, avoiding RGBA8 pre-quantization. The
bounded [R32 extension](R32.md) covers red-only image colors, sole-channel
extraction and file export.

## How it is verified

`tools/image_format_probe.py` (gate `image-format`) compares every
source/destination pair of formats 1..8, target-zero no-ops, conversion chains
and Surface bridges with native `ImageFormat`, byte-for-byte on the CPU-1, CPU-2
and JavaScript lanes. It covers R32 boundary samples, rejected-factory controls
and a complete signed-zero/subnormal R32 import. `--gpu` adds a forced-GPU lane
(local only). Each codec factory and file loader is verified by its codec's
gates (see [CODECS.md](CODECS.md)).

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only image-format
```

## Known gaps

- Generic formatted decoder/file dispatch and original-format metadata for the
  remaining normalized codecs.
- Other float/half/compressed formats, mipmaps, other configured alpha thresholds,
  big-endian/native pointer layouts and allocation size.
- R32 conversion has no GPU evidence; full target/resource/performance evidence
  is open.
