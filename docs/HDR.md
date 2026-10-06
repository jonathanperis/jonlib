# Owned Radiance RGBE float images

| API | Contract |
|---|---|
| `Image.FloatRGB.decode_hdr(bytes: +List<U32>)` | Returns `Result<&1, &1, Image.DecodeError, Image.FloatRGB>`. Owned pixels are `Array<M.Vector3>` (Jonmath's shared vector type) preserving native `PIXELFORMAT_UNCOMPRESSED_R32G32B32` (format 9) sample bits. |
| `Image.FloatRGB.entries(image)` | Consumes the image and returns `(width, height, List<M.Vector3>)` in top-down row-major order. |
| `Image.FloatRGB.unload(image)` | Consumes the owner and returns `Unit`. |
| `Image.FloatRGB.load_hdr(path)` | Returns `IO(Result<&1, &1, Image.LoadError, Image.FloatRGB>)`; see [file loading](#file-loading). |

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

`Image.FloatRGB.load_hdr(path)` explicitly selects the Radiance decoder
regardless of filename, reads at most 1 MiB, requires the complete reported byte
count and closes the handle before decoding. Open/size/read errors retain
`ImageFileError`; decode/size errors are wrapped as `ImageDecodeError`. The
supported IO domain is ordinary non-changing files, using the same byte-file
boundary as Surface and animation loading ([IMAGE-FILES.md](IMAGE-FILES.md)).

Checked [RGB float/RGBA8 conversion](FLOAT-RGB.md) is available for samples in
`[0,1]`, returning the original owner when outside that domain.
`Surface.decode_image` retains its RGBA8 profiles; use the typed float API to
preserve HDR samples.

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

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only hdr
```

## Known gaps

Shared float-format dispatch, broader header/permissive recovery, GPU filesystem
IO, callbacks, concurrent/special files and complete
metadata/resource/platform/performance coverage.

## Provenance

The altered stb reader retains its MIT notice and upstream Nicolas Schulz credit;
see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
