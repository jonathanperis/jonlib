# Owned Radiance RGBE float images

| API | Contract |
|---|---|
| `Surface.decode_hdr(bytes: +List<U32>)` | Returns `Result<&1, &1, Surface.Error, Surface>`. Owned pixels are `Quads` holding the native `PIXELFORMAT_UNCOMPRESSED_R32G32B32` (format 9) sample bits. |
| `Surface.export(image)` | Consumes the image and returns its dimensions, format 9 and the little-endian F32 sample bytes in top-down row-major order. |
| `Surface.load_hdr(path)` | Returns `IO(Result<&1, &1, Surface.IOError, Surface>)`; see [file loading](#file-loading). |

## Supported profile

- `#?RADIANCE` or `#?RGBE` identifier, followed by LF-delimited header lines.
- Exact `FORMAT=32-bit_rle_rgbe` metadata line, blank separator and
  `-Y height +X width` layout. Decimal dimensions are 1..4096; repeated spaces
  and leading zeroes are accepted. Other metadata lines are ignored.
- Header lines contain at most 1,023 bytes without embedded NUL. Complete line
  terminators and all required RGBE samples are required.
- Widths below eight decode raw data directly. Wider images accept native raw
  fallback when the first sample is not the `2,2,high,low` RLE marker with
  `high < 128`. Otherwise native scanline RLE is decoded as described below.
- Valid trailing bytes are ignored, while every supplied element must be a byte.

Exponent zero produces black regardless of stored RGB. Otherwise each component
is exactly `channel * 2^(exponent - 136)`. This product fits F32 exactly
throughout the byte domain, including subnormal results. The Bend implementation
constructs the declared F32/Word carrier bits from integers, retaining native
subnormals on all checked backends without floating-point underflow arithmetic.

Invalid/incomplete headers and unsupported encodings return `InvalidImageHeader`;
invalid dimensions return `UnsupportedImageSize`; missing raw samples return
`TruncatedImageData`; non-byte values return `InvalidImageByte`. Dimensions and
complete raw sample length are checked before output allocation; compressed
packet availability/counts are checked before output writes.

## Scanline RLE

For widths 8..4096, encoded rows begin with `2,2` and the big-endian row width.
Four component planes follow in R/G/B/exponent order. Controls 1..128 copy that
many literal bytes; controls 129..255 repeat the next byte `control-128` times.
Each count must fit the remaining plane. A bounded packed scanline is reused
between rows, then converted to exact float pixels.

Zero controls, row-width mismatches and packet overruns return
`InvalidImageStream`. Missing packet/count/header bytes return
`TruncatedImageData`. Every write is bounded by its row and image dimensions. If
a later row lacks the native RLE marker, native decoding resets to the canvas
origin: its first four bytes become pixel zero, and a complete raw canvas
replaces all earlier RLE output. Jonlib preserves that behavior while requiring
the entire replacement payload. It does not expose native uninitialized samples
from truncated raw recovery.

## File loading

`Surface.load_hdr(path)` explicitly selects the Radiance decoder
regardless of filename, reads at most 1 MiB, requires the complete reported byte
count and closes the handle before decoding. Open/size/read errors retain
`FileError`; decode/size errors are wrapped as `DataError`. The
supported IO domain is ordinary non-changing files, using the same byte-file
boundary as Surface and animation loading ([IMAGE-FILES.md](IMAGE-FILES.md)).

Checked [RGB float/RGBA8 conversion](FLOAT-RGB.md) is available for samples in
`[0,1]`, returning the original owner when outside that domain.
`Surface.decode_hdr` and `Surface.load_hdr` stay on that Radiance-only path.
Shared `.hdr` selection is below.

## Shared suffix and content dispatch

`LoadImage` and `LoadImageFromMemory` recognize `.hdr` and `.HDR` only. Mixed
case stays unsupported, the same as `.Hdr` against `strcmp`. The file cap is
1,048,576 bytes.

- A `#?RADIANCE\n` or `#?RGBE\n` prefix (the newline is required) decodes with
  `Surface.decode_hdr` and stays format 9.
- Any other admitted raster is decoded first, then promoted the way
  `stbi_loadf_from_memory` calls `stbi__ldr_to_hdr` (gamma 2.2, scale 1). Format
  1 becomes format 8, one `pow(byte/255, 2.2)` per gray byte. Format 4 becomes
  format 9 (R, G and B, fourth channel 0). Format 7 becomes format 10 (R, G and
  B from the canonical word, alpha `byte/255` with no power). Bytes 0 and 255
  are 0 and 1.0 and do not call `powf`.
- Format 2 and every other decoded format return `InvalidImageHeader`. raylib's
  `comp == 2` branch calls `UnloadImage` on a by-value copy, so the caller's
  `image.data` is left dangling and the format stays 0. That undefined state is
  refused. The dispatch gate checks the dangling condition without reading or
  unloading it, and checks that Jonlib returns the header error.

A raster token (`.png`, `.bmp`, `.tga`, `.jpg`, `.jpeg`, `.gif`, `.pic`,
`.psd`, `.pgm`, `.ppm`, and the uppercase forms) that begins with the Radiance
signature uses `stbi__hdr_to_ldr` into format 4. A zero sample stays byte 0, a
sample greater than or equal to 1 becomes 255, and every other sample is
`floor` of `pow(sample, 1/2.2) * 255 + 0.5` after clamping into `[0, 256)`.
The signature does not fall through to TGA when the Radiance decode fails.
Jonlib still tries PNG, BMP, PNM, PSD, PIC and GIF before JPEG, then Radiance,
then TGA. Those signatures do not overlap `#?`.

`powf` is `M.Libm.powf(M.Glibc239Libm{}, ...)`. `None` becomes 0 on the way to
float and byte 0 on the way to 8-bit. The samples in the dispatch gate are in
the profile's `Some` domain.

## How it is verified

- **Decoding** (`tools/hdr_probe.py`, gate `hdr`): native images, typed-error
  controls and all 65,536 channel/exponent pairs, with every component compared
  as exact F32 bits on the CPU-1, CPU-2 and JavaScript lanes (`--gpu` adds a
  forced-GPU lane, local only). It exercises normal/subnormal/extreme exponents,
  zero-exponent black, raw-marker boundaries, metadata/decimal parsing and
  4,096-pixel axes; consuming entries and unload are also checked. RLE cases
  cover row/plane transitions, literals/repeats at packet limits, widths
  8/9/127/128/129/256/4096 and zero/subnormal/extreme exponents. Later-row
  fallback cases replace one or two prior encoded rows and include the high-bit
  marker variant.
- **Files** (`tools/hdr_file_probe.py`, gate `hdr-file`): exact file samples on
  CPU/JavaScript, including uppercase `.HDR` and explicit-selection cases with
  mixed/absent/other suffixes. Native `LoadImage` observes ordinary HDR suffixes;
  explicit cases use native `LoadFileData` plus `LoadImageFromMemory(".hdr", ...)`.
  Boundary/error controls and a low-descriptor success/decode/read/size closure
  loop are included.
- **Shared dispatch** (`tools/hdr_dispatch_probe.py`, gate `hdr-dispatch`):
  `LoadImageFromMemory` and `LoadImage` on CPU-1, CPU-2 and JavaScript against
  the pinned library. Radiance under `.hdr`/`.HDR` is format 9; the same bytes
  under raster tokens are tone-mapped R8G8B8. PNG gray, RGB and RGBA and a BMP
  under `.hdr` promote to formats 8, 9 and 10. A `.png` path whose bytes are
  Radiance still returns format 9 through `load_hdr`. Gray-alpha under `.hdr`
  is the refusal sentinel on both sides. Garbage and `.Hdr` fail on both sides.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only hdr
```

## Known gaps

Gray-alpha under shared `.hdr` (refused), glibc 2.39 `powf` where the profile
returns no value, broader header/permissive recovery, GPU filesystem
IO, callbacks, concurrent/special files, macOS/Metal and performance.

## Provenance

The altered stb reader retains its MIT notice and upstream Nicolas Schulz credit;
see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
