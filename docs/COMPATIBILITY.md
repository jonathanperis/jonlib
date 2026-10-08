# Compatibility ledger

Reference: raylib **6.0** at `dbc56a87da87d973a9c5baa4e7438a9d20121d28`.
Candidate: Bend **2.0.27+jonlib-metal.1**, base
`b7ebee9217c8813067e200b0c0c9153a3be31c5e` plus the exact
[compiler overlay](../patches/README.md) declared in `toolchain.json`.
Profile: **rgba8-cpu-images-v1**, with domains defined in [API.md](API.md).

This page lists the verified capability profiles and known divergences. The
authoritative per-API status is the [API dashboard](PROGRESS.md), generated from
the ledger described in [API-TRACKING.md](API-TRACKING.md). Every mapped
capability below is **partial** (the legacy `profile-covered` and
`contract-checked` labels both mean partial) and must not be reported as a fully
completed raylib API. Mapped counts are an inventory, not a parity percentage.
The [master plan](MASTER-PLAN.md) defines the full-capability completion gates.

## Lanes and host profiles

- Every gate compares Jonlib on CPU one-thread, CPU two-thread and JavaScript
  exactly against native raylib built from the pinned source. CI runs all gates
  in [`tools/gates.json`](../tools/gates.json) on Ubuntu 24.04 (x86-64) and
  macOS 15 (arm64); see [CI.md](CI.md) and [VERIFICATION.md](VERIFICATION.md).
- Forced-GPU (Metal) execution is a separate local lane (`--gpu`) on Apple
  hardware, valid only with the declared compiler overlay; stock Bend fails the
  full corpus on Metal ([METAL-INVESTIGATION.md](METAL-INVESTIGATION.md)). A CPU
  fallback is not GPU evidence. CUDA was not verified.
- Host-dependent numerical behavior is an explicit, named profile, never an
  implicit host guess:
  - checked vector angles: the `M.Libm` profile whose frozen native
    `atan2f` controls match the host ([ANGLES.md](ANGLES.md));
  - literal extrema and Vector min/max/clamp signed zeros: native qualification
    in `tools/native_profiles.py`;
  - gradient, image-rotation and profiled math trigonometry (`*_for` with
    `M.Libm`): `AppleLibm` on Darwin, `Glibc239Libm` on
    glibc Linux;
  - linked collision/noise/spline/decode/camera multiply-add contraction: fused on
    Darwin arm64, uncontracted on Linux x86-64.

  Other hosts must declare a verified profile before conformance runs. Libm
  records for open gaps are diagnostic gates (`native-math-profiles`,
  `inverse-trig`, `perspective`, `filter-precision`); see
  [NATIVE-MATH-PROFILES.md](NATIVE-MATH-PROFILES.md).
- The main corpus (gate `conformance`, `tools/conformance.py` with
  `tests/fixtures/images.json`) compares complete RGBA pixel arrays and
  dimensions, numeric/collision result bits, QOI export bytes and palette
  observations; it also runs the ownership, bounds, color and Base.Image adapter
  contracts, the PPM examples (every RGB pixel against the raylib scene) and
  `PROOF.bend` (dimension preservation, transpose involution, float-export lengths).

## Capability profiles

Gate IDs refer to `tools/gates.json`; `conformance` is the main corpus.

| Reference capability | Jonlib operation | Verified profile | Gates |
|---|---|---|---|
| `GenImageColor` | `Surface.create` | Valid RGBA8 dimensions 1..4096 | `conformance` |
| `ImageClearBackground` | `Surface.clear` | Full pixels; dimension preservation is a checked law | `conformance` |
| `ImageDrawPixel` | `Surface.draw_pixel` | Byte replacement and clipping | `conformance` |
| `ImageDrawRectangle` | `Surface.draw_rectangle` | Clipping and degenerate rectangles | `conformance` |
| `ImageDrawCircle` | `Surface.draw_circle` | Midpoint coverage, large and small radii | `conformance` |
| `ImageDrawLine` | `Surface.draw_line` | Exact fixed-point octants, reversal, clipping and endpoint exclusion | `conformance` |
| `ImageDrawLineV` | `Surface.draw_line_v` | Reference add-half/truncate conversion, including negative/fractional inputs | `conformance` |
| `ImageDrawTriangle` | `Surface.draw_triangle` | Integral-vertex winding, clipping, degeneracy and signed edge stepping | `conformance` |
| `ImageDrawTriangleLines` | `Surface.draw_triangle_lines` | Truncated vertices and three reference-compatible segments | `conformance` |
| Vector wrappers, outlines, thick lines, fans/strips, vertex-colored triangles | `Surface.draw_*` families | Truncation, winding and byte-quantized vertex weights | `conformance` |
| `ImageDraw` | `Surface.draw_image / draw_image_region / draw_image_rect` | Formats 1..13, one mip: source clipping, default scaling in the source format, destination clipping, `GetPixelColor`/`ColorAlphaBlend`/`SetPixelColor` and memcpy rows, bounded fractional rectangles; both owners retained | `conformance`, `surface-format` |
| `ImageFromImage` | `Surface.extract` | Positive integral in-bounds region; independent output; original retained | `conformance` |
| `ImageCrop` | `Surface.crop` | Integral clipping, outside-origin no-op; typed failure returns the original | `conformance` |
| `ImageResizeNN` | `Surface.resize_nn` | Exact fixed-point ratios; invalid/unsafe mappings return the original | `conformance` |
| `ImageResize` | `Surface.resize` | Default filters with exact normalization: alpha-aware RGBA8, unweighted 1..3-channel GRAYSCALE/GRAY_ALPHA/R8G8B8, owner-preserving size errors ([RESAMPLING.md](RESAMPLING.md)) | `resize`, `conformance`, `surface-format` |
| `ImageMipmaps` | `Surface.mipmaps`, `Image.Mipmaps.entries/unload` | Formats 1..13: owned base-to-1x1 levels, sequential `ImageResize` in the image's format, complete-level comparison | `mipmap` |
| `ImageBlurGaussian` | `Surface.blur_gaussian` | Four-iteration RGBA8 box approximation, premultiply/unpremultiply quantization, bounded sizes, retained rejected owners | `blur` |
| `ImageKernelConvolution` | `Surface.kernel_convolution` | Bounded square RGBA8 kernels, native flat-index row wrapping; original retained for unsupported kernels/alpha casts | `convolution` |
| `LoadImageColors` / `GetImageColor` | `Surface.colors` / `Surface.get` | Full export; direct reads, ownership and out-of-bounds `None` | `conformance` |
| `ImageCopy` | `Surface.copy` | Independent mutation; original pixels preserved | `conformance` |
| `GetColor` / `ColorToInt` | `Color.rgba` / channel extractors | Packing with unsigned-byte truncation | `conformance` |
| `ColorAlphaBlend` | `Color.alpha_blend` | Transparent/opaque/tinted reference vectors | `conformance` |
| Color equality, alpha/Fade, tint, brightness, contrast, lerp | `Color` value operations | Exact packed bytes/Booleans in the finite-factor profiles | `conformance` |
| Normalized/HSV colors | `Color.normalize/from_normalized/to_hsv/from_hsv` | Exact float bits or bytes, achromatic/sector boundaries; bounded HSV input | `conformance` |
| Image color/alpha operations, checkerboards | `Surface.color_*`, `alpha_*`, `create_checked` | Reference arithmetic, preserved mask ownership, checked generator inputs | `conformance` |
| Alpha bounds/cropping | `Surface.alpha_border/alpha_crop` | Exact rectangles; empty selections leave the image unchanged | `conformance` |
| Canvas resizing | `Surface.resize_canvas` | Raw RGBA copy/fill, clipping, same-size no-op; rejected requests return the original | `conformance` |
| Square gradients | `Surface.create_gradient_square` | Odd/even sizes and density endpoints, including density one | `conformance` |
| Radial/linear gradients | `Surface.create_gradient_radial/linear` | Radial density 0..1; integral linear directions -360..360 | `conformance`, `trig` |
| Random streams / white noise | `Random.seed/value`, `Surface.create_white_noise` | Exact rprand sequences, full pixels, fixed draw consumption, rejected-owner preservation | `random`, `conformance` |
| Unique random sequences | `Random.load_sequence/unload_sequence` | Exact acceptance order and following state; explicit draw budget; owned incomplete/error results | `random` |
| Cellular images | `Surface.create_cellular` | Seed order, full pixels, post-generation state; exhaustive integer-distance reduction | `random`, `conformance` |
| Perlin images | `Surface.create_perlin/create_perlin_for` | Six seeded octaves with explicit arithmetic profiles; tables, raw octave values and pixels | `perlin` |
| Text data / grayscale / palettes | `Surface.create_text_bytes/color_grayscale/load_palette`, `Image.Palette` | Opaque data images; exhaustive luminance; ordered/padded palettes with source preservation | `conformance` |
| Pixel sizes / raw dithering | `Pixel.data_size`, `Surface.dither`, `Surface` | All-format size boundaries; raw packed words and metadata | `pixel` |
| Byte/integer pixel access | `Pixel.get_color/set_color` | Exhaustive two-byte reads, full write buffers, strict alpha threshold, native RGB5A1 read quirk | `raw-pixel` |
| Byte/integer image-format conversion | `Surface` and Surface bridges | All 49 format pairs, no-ops and chains as native-order bytes | `image-format` |
| Bounded R32 image format | `Surface` format 8 | Finite `[0,1]` words, signed-zero/subnormal storage, uncontracted luminance, red-only normalization; raw-bit memory PNG vs normalized file PNG ([R32.md](R32.md)) | `r32-image`, `r32-raw-file`, `float-rgb-r32` |
| Raw image files | `Surface.load_raw/write_raw` | Formats 1..7 and finite `[0,1]` R32; header-offset/fallback rules, distinct sample errors, closed handles ([RAW-FILES.md](RAW-FILES.md)) | `raw-file` |
| `ImageFlipHorizontal/Vertical` | `Surface.flip_horizontal/flip_vertical` | Explicit and seeded full images | `conformance` |
| `ImageRotateCW/CCW` | `Surface.rotate_cw/rotate_ccw` | Exact bytes, non-square dimensions, sequencing | `conformance` |
| `ImageRotate` / `ImageToPOT` | `Surface.rotate_degrees_for/to_pot` | Reference bilinear sampling of every stored byte in formats 1..13 (float results outside the owner domain refused); POT fill/copy | `conformance`, `trig-rotation`, `surface-format` |
| `ImageFromChannel` | `Surface.from_channel` | All byte/channel combinations; independent GRAYSCALE output | `conformance`, `image-channel` |
| Base.Image conversion / PPM export | `Surface.to_image/to_ppm/write_ppm` | Adapter pixels/padding and actual file RGB | `conformance` |
| Image-file loading | `Surface.load_image/load_qoi` | Native suffix/content detection, complete reads, typed errors, closed handles ([IMAGE-FILES.md](IMAGE-FILES.md)) | `image-file` |
| Image memory dispatch | `Surface.decode_image` | Extension-token/content selection across implemented codecs, shared raster aliases, QOI separation, typed invalid controls (also forced Metal) | `image-memory` |
| QOI loading/export | `Surface.decode_qoi/to_qoi/load_qoi/write_qoi` | Valid streams, all opcodes, exact export bytes, typed malformed-input errors, file round trips ([CODECS.md](CODECS.md)) | `conformance`, `image-file` |
| BMP decoding/export | `Surface.decode_bmp/to_bmp/write_bmp` | CORE indexed/RGB24 and 40/56/108/124-byte headers; palette-count, mask, alpha and offset rules; exact exports ([BMP.md](BMP.md)) | `bmp` |
| TGA decoding/export | `Surface.decode_tga/to_tga/write_tga` | Raw/RLE type/depth selection, indexed, RGB555/alpha, palette skips/index recovery, exact exports ([TGA.md](TGA.md)) | `tga` |
| Binary PGM/PPM decoding | `Surface.decode_pnm` | P5/P6 8/16-bit, little-endian reduction to 8-bit samples, maxval/separator/comment rules ([PNM.md](PNM.md)) | `pnm` |
| PNG decoding | `Surface.decode_png` | Non-interlaced/Adam7 1/2/4/8/16-bit and native-default CgBI; filtering, palette/tRNS, framing, bounded errors ([PNG.md](PNG.md)) | `png` |
| PSD decoding | `Surface.decode_psd_for` and `_for` dispatch | Version-1 RGB, 0..16 channels, raw/PackBits, explicit matte profiles ([PSD.md](PSD.md)) | `psd`, `psd-matte` |
| Softimage PIC decoding | `Surface.decode_pic` | Raw/pure-RLE/mixed-RLE packets, clipping/zero-count/default/overwrite behavior, bounded errors ([PIC.md](PIC.md)) | `pic` |
| First-frame GIF decoding | `Surface.decode_gif` | GIF87a/89a in-canvas/interlaced rectangles, background fills, palettes, transparency, bounded LZW ([GIF.md](GIF.md)) | `gif` |
| Animation memory loading | `Image.Animation.decode_gif/decode_image_for/entries/unload` | Budgeted GIF sequences or one-frame static fallback; disposal/palette/control behavior ([GIF-ANIMATION.md](GIF-ANIMATION.md)) | `gif-animation` |
| Animation file loading | `Image.Animation.load_image/load_image_for` | Case-insensitive GIF suffix, static fallback, caller budgets, closed handles | `animation-file` |
| Native-format memory loading (`LoadImageFromMemory`) | `Surface.decode_bmp/decode_tga/decode_png/decode_pic/decode_pnm/decode_qoi` | Native output format, implicit single mip and exact raw bytes across each codec's checked domain; see the codec pages | `bmp-format`, `tga-format`, `png-format`, `pic-format`, `pnm-format`, `qoi-format` |
| Native-format file loading (`LoadImage`) | `Surface.load_bmp/load_tga/load_png/load_pic/load_pnm/load_qoi` | Explicit suffix-independent codec; inclusive 1 MiB pre-read cap (QOI: 83,886,102 bytes), complete reads, close-before-decode, typed errors; see [IMAGE-FILES.md](IMAGE-FILES.md) | `bmp-file`, `tga-file`, `png-file`, `pic-file`, `pnm-file`, `qoi-file` |
| PNG export | `Surface.to_png/write_png`, `Surface.export_to_memory` | Default byte-format memory and file output; packed expansion, channel/header preservation, rejection, normalized round trips ([IMAGE-EXPORT.md](IMAGE-EXPORT.md)) | `png-export`, `deflate` |
| Suffix-selected export | `Surface.write_image` | ASCII-insensitive PNG/BMP/TGA/QOI/RAW suffix selection, exact file bytes, retained unsupported owners, typed IO | `image-export` |
| BMP/TGA/QOI export | `Surface.to_bmp/write_bmp`, `to_tga/write_tga`, `to_qoi/write_qoi` | Native bytes for formats 1..8 (QOI: original formats 4/7 only, other formats retain their owner before IO); consuming typed IO, closed handles | `bmp-export`, `tga-export`, `qoi-export` |
| Image-as-code export | `Surface.to_code/write_code` | Banner/name/metadata/hex text from formats 1..9; bounded payloads ([IMAGE-CODE.md](IMAGE-CODE.md)) | `image-code` |
| HDR float decoding | `Surface.decode_hdr` | Raw/RLE RGB F32, later-row origin reset, bounded packets, exhaustive sample bits including subnormals ([HDR.md](HDR.md)) | `hdr` |
| HDR float file loading | `Surface.load_hdr` | Explicit Radiance selection, shared bounded/complete/closed-handle IO | `hdr-file` |
| RGB float/RGBA8 conversion | `Surface.format` | Byte normalization, finite `[0,1]` truncation, opaque alpha, rejected-owner preservation ([FLOAT-RGB.md](FLOAT-RGB.md)) | `float-rgb` |
| RGB float raw bytes | `Surface.from_bytes/export` | Non-NaN little-endian format-9 samples, strict size/byte checks | `float-rgb-bytes` |
| RGB float copy/orientation | `Surface.copy/flip_*/rotate_*` | Independent owners, exact sample movement (also forced Metal) | `float-rgb-transform` |
| RGB float rectangles | `Surface.extract/crop` | Integral region/crop words and clipping | `float-rgb-crop` |
| RGB float resize | `Surface.resize_nn/resize` | Native RGBA8 quantization (nearest or default filter) then float normalization | `float-rgb-resize`, `float-rgb-resize-filtered` |
| RGB float canvas/POT | `Surface.resize_canvas/to_pot` | Sample movement, ignored fill/zero background, same-size no-ops | `float-rgb-canvas` |
| RGB float color transforms | `Surface.color_*` | Native byte-quantized format-9 paths | `float-rgb-color` |
| Direct RGB float formats | `Surface.format/color_grayscale` | Finite `[0,1]` channels to formats 1..8, packed rounding, uncontracted R32 luminance | `float-rgb-formats` |
| Byte/integer to RGB float | `Surface.format` | Normalized F32 words from all seven layouts; packed precision; alpha discarded | `format-float` |
| Native grayscale channels | `Surface.from_channel` | Format-specific selection, normalized truncation ([IMAGE-CHANNELS.md](IMAGE-CHANNELS.md)) | `image-channel` |
| Color observations | `Surface.colors/get` | Packed expansion/float truncation, bounded point reads ([IMAGE-COLORS.md](IMAGE-COLORS.md)) | `image-colors` |
| RGB float PNG export | `Surface.export_to_memory/write_png` | Raw-storage memory prefix versus normalized file colors | `float-rgb-png` |
| RGB float BMP/TGA export | `Surface.to_bmp/to_tga/write_bmp/write_tga` | Normalized file bytes, explicit codec selection | `float-rgb-raster-export` |
| RGB float RAW file IO | `Surface.load_raw/write_raw` | Fitting-header/fallback selection, exact format-9 words, typed failures | `float-rgb-raw-file` |
| Float and half-float formats 9..13 | `Surface` `Quads`/`Words` storage, `ImageFormat`, color/draw/rotate/alpha operations | raylib `HalfToFloat`/`FloatToHalf` bit arithmetic, per-format owner domains ([FLOAT-FORMATS.md](FLOAT-FORMATS.md)) | `surface-format`, `mipmap` |
| Format-generic image operations | `Surface` flips, turns, crop/extract/canvas/copy, color operations, resizes, dither, drawing, channels, alpha crop, colors | Every operation and `ImageFormat` to every target on formats 1..13 against raylib after `ImageFormat`, complete stored bytes, including alpha clear/mask, rotation and composition across source formats | `surface-format` |
| Raw DEFLATE | `Compression.decompress` | Stored/fixed/dynamic blocks, bounded copies; native empty-stored-block completion differs explicitly from the internal PNG-oriented path ([DEFLATE.md](DEFLATE.md)) | `inflate` |
| Raw compression | `Compression.compress` | Quality-8 sdefl bytes, empty zero-byte output, bounded native sequence budget, also forced Metal ([COMPRESSION.md](COMPRESSION.md)) | `sdeflate`, `sdeflate-lz`, `sdeflate-huffman` |
| Base64 | `Base64.encode/decode` | Alphabet/padding, NUL-inclusive encoded size, bounded decoded bytes ([BASE64.md](BASE64.md)) | `base64` |
| CRC32 and MD5 | `Checksum.crc32/md5` | CRC value and four MD5 words, little-endian MD5 profile ([CHECKSUMS.md](CHECKSUMS.md)) | `checksum` |
| SHA-1 and SHA-256 | `Checksum.sha1/sha256` | Five/eight native words, including the SHA-256 padding quirk ([SHA.md](SHA.md)) | `sha` |
| Scalar/Vector2/Vector3/Vector4 raymath | Jonmath `Math` and vector functions | Explicit uncontracted-F32 profile ([MATH.md](MATH.md)) | `conformance`, `jonmath-example` |
| Vector angle queries | `Vector2.angle/line_angle`, `Vector3.angle` and their checked `_for` forms | Unchecked Apple profile; checked angles per selected `M.Libm` ([ANGLES.md](ANGLES.md)) | `conformance`, `angle-kernels`, `angle-legacy`, `modern-angle-bounds` |
| Quaternion arithmetic/metrics/interpolation | `Quaternion` functions | Shared Vector4 representation; Hamilton products, zero normalization/inversion, NLERP, sign-equivalent equality | `conformance` |
| Quaternion/matrix conversion and composition | `Quaternion.from_matrix/to_matrix/transform`, `Vector3.rotate_by_quaternion`, `Matrix.compose` | Branch/tie order, full matrices, non-unit/zero quaternions | `conformance` |
| Decomposition, 3D constructors, unprojection | `Matrix.decompose`, quaternion constructors/spline, `Vector3.rotate_by_axis_angle/unproject` | Ten-field decomposition, bounded half-angle profiles, inverse ordering, invalid-domain controls | `conformance` |
| Binary64-input projection matrices | `Float64`, `Matrix.frustum/ortho` | Full input bits retained before reference F32 casts; normal/zero domain controls | `conformance`, `float64-ops` |
| Float-list exports | `Vector3.to_float_v`, `Matrix.to_float_v` | Values/order; 3/16-element lengths are checked laws | `conformance` |
| raymath C++ operators | Typed operator sugar (`T.add/sub/mul/div`) and the named functions they call | All 60 operators and compound assignments, every result bit, uncontracted ([MATH.md](MATH.md#c-operators)) | `operators` |
| Matrix arithmetic/inversion, affine constructors, vector transforms | `Matrix`, `Vector2.transform`, `Vector3.transform` | All 16 fields, noncommuting products, near-singular inversion; double transpose is a checked law | `conformance` |
| View and rotation matrices | `Matrix.look_at`, `rotate_*_for`, `rotate_for` | Degenerate bases, bounded trigonometric profiles, distinct Euler orders | `conformance` |
| 2D collision queries | `Collision` functions | Boolean/rectangle/hit-coordinate results; explicit segment contraction profiles ([COLLISION.md](COLLISION.md)) | `conformance`, `fused` |
| Sphere/box queries | `Collision.spheres/boxes/box_sphere` | Inclusive contacts, signed radii, supplied-bound ordering | `conformance` |
| Ray queries | `Collision.ray_sphere/ray_box/ray_triangle/ray_quad` | Every `RayCollision` field bit; host contraction and libm profiles; non-portable box inputs are `None` | `ray`, `ray-uncontracted` |
| Cameras | `Camera.*` (rcamera.h, rcore.c camera/screen-space queries) | Every F32 result bit; host contraction and libm profiles; perspective projections, unreproduced `sinf`/`cosf` arguments (all nonzero under AppleLibm) and checked-contract misses are `None` ([CAMERA.md](CAMERA.md)) | `camera`, `camera-uncontracted`, `camera-glibc239`, `camera-fused-glibc241` |
| Linear/B-spline/Catmull-Rom/quadratic Bezier points | `Spline` functions | XY and coefficient order with explicit arithmetic profiles ([SPLINES.md](SPLINES.md)) | `spline` |
| GPU execution of image operations | Same Bend API | All corpus pixels and export bytes on forced Metal with the overlay | local `tools/conformance.py --gpu` |
| GPU graphics-pipeline `Draw*` APIs | Future rasterizer | Not implemented; CPU `ImageDraw*` matches do not cover these | — |
| Textures, text/fonts, further codecs, meshes, models, animation | Future modules | Not implemented | — |
| Input, window, audio, native Windows/browser/Android | Future library and runtime work | Not implemented | — |

## Known divergences and gaps

- **Legacy angle profiles are not retargeted.** On glibc ≥ 2.41 hosts the legacy
  Sun (`Glibc239Libm`) angle differs from native `atan2f`: fixture
  `vector2-angle-profiles` pixel `(6,0)` gives legacy `3fc90fda` versus native
  `3fc90fdb`. The checked `*_for` route with `M.Glibc241Libm{}` matches.
  The arm64 Apple subnormal difference is described in [ANGLES.md](ANGLES.md).
- Cubic Bezier spline points are blocked by native `powf` rounding.
- Linear gradients outside integral -360..360 directions (wider-angle libm
  rounding) remain open ([GRADIENTS.md](GRADIENTS.md)).
- Native byte-allocation ABI for pixel data, native array ABI/mutability for
  float-list exports, and native static/pointer buffers for checksums are adapted,
  not reproduced.
- Exceptional and contracted F32 variants of raymath remain open.
- Native-format loading covers the listed codecs; other-platform/GPU
  qualification of the native-format codec paths remains open.
- Filled-triangle fractional vertices beyond the documented truncation and
  additional codecs are open requirements.
- No performance parity is claimed. The array-based image algorithms are a
  correctness foundation, not the production tiled rendering pipeline.
- CUDA, Windows, browser graphics, live windows and live audio are unverified.
  Source and fixture domains are finite and explicitly bounded; passing fixtures
  is not exhaustive proof of every supported input.

## Comparison policy

- Compare the complete ordered RGBA pixel array and actual dimensions.
- Compare every selected export byte and every scalar/vector result bit.
- No image tolerance for this integer-coordinate CPU image profile.
- Require the pinned base revisions and exact declared Bend overlay; reject
  unexpected tracked changes. Raylib must remain unmodified.
- Generate both test programs from the same validated fixtures.
- Include explicit boundary regressions and deterministic seeded mixed operations.
- Reject empty fixtures, missing result rows, malformed pixels and mismatches.
- Keep blocked/skipped/unimplemented capabilities visible.

Future platform and GPU graphics profiles will specify their own controlled
inputs and comparison contracts before accepting different tolerances.
