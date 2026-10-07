# PSD memory decoding and alpha profiles

| API | Contract |
|---|---|
| `Surface.decode_psd(bytes: +List<U32>)` | Returns `Result<&1, &1, Surface.Error, Surface>` with an owned R8G8B8A8 image, using `M.Uncontracted{}` matte arithmetic. |
| `Surface.decode_psd_for(reference, bytes)` | Same, with an explicit `M.Contraction` matte profile. |

Shared memory/file dispatch recognizes the exact `8BPS` signature; see
[IMAGE-FILES.md](IMAGE-FILES.md).

## Supported profile

- PSD version 1, RGB color mode 3, dimensions 1..4096.
- Raw and PackBits RLE data with 0..16 declared channels and 8/16-bit depth
  headers.
- Channels are read in R/G/B order. Missing color channels default to zero and
  alpha defaults to 255 when absent. Four-plus-channel data supplies actual alpha,
  including zero; only the first four planes are decoded. Extra pixel planes are
  ignored. Zero-channel input produces opaque black, matching the pinned reader.
- Six reserved header bytes are ignored. Three length-prefixed
  mode/resource/layer sections are skipped after checking availability; their
  contents are not interpreted.
- Raw sixteen-bit samples are big-endian and retain their **high byte**, matching
  native `stbi_load` normalization. This differs from the pinned PNM reader's
  unswapped little-endian sample behavior.
- Complete raw plane data is checked before output allocation. RLE packets are
  checked against input availability and remaining output before writes. Valid
  trailing bytes are ignored; every supplied element must still be a byte.

Invalid bytes return `InvalidImageByte`; unsupported/incomplete header fields
return `InvalidImageHeader`; unsupported dimensions return `UnsupportedImageSize`.
Missing section payload or pixel samples return `TruncatedImageData`. RLE packets
that exceed the remaining plane return `InvalidImageStream`.

## Native PackBits behavior

Compression 1 skips a two-byte count for every declared row/channel. Native
decoding ignores those count values and decodes each channel as one continuous
stream, so packets may cross rows.

- Controls 0..127 copy the next `control + 1` bytes.
- Controls 129..255 repeat the next byte `257 - control` times.
- Control 128 is a no-op. Input-byte fuel bounds no-op processing.
- RLE produces **one byte per output sample even with a depth-16 header**,
  matching the pinned reader. It does not use raw sixteen-bit sample narrowing.

## White-matte arithmetic

With actual alpha, values 0 and 255 preserve RGB unchanged. Intermediate alpha
uses the native F32 sequence `a = alpha/255`, `ra = 1/a`, `inv = 255*(1-ra)`,
then `channel*ra + inv`, truncating to a byte. Supported prematted channels are
`channel >= 255-alpha`; values outside that domain return `InvalidImageStream`
rather than relying on native out-of-range float-to-byte conversion.

Import Jonmath as `M` and choose an `M.Contraction` explicitly:

- `M.Uncontracted{}` rounds the final multiplication and addition separately.
- `M.Fused{}` uses one correctly rounded fused multiply-add.

The default is uncontracted, consistent with the other image arithmetic APIs. Use
`_for` on `Surface.decode_psd`, `Surface.decode_image` and `Surface.load_image`
(and the animation `_for` variants) to select a profile. Decoder code does not
inspect the operating system; a profile is a numerical contract, not host
detection.

Across all 32,639 valid intermediate-alpha/channel pairs, the two models differ
in 130 byte outputs. For example, channel 255 with alpha 11 becomes 254 under the
fused model (the native macOS arm64 build) and 255 under the uncontracted model
(the native Linux x86-64 build).

## How it is verified

- **Matte models** (`tools/psd_matte_probe.py`, gate `psd-matte`): a C reference
  computes both models (built with `-ffp-contract=off`, explicit `fmaf` for the
  fused model) and the linked native PSD result for every valid intermediate pair
  plus all alpha-0/255 boundary pairs. The linked native result must equal the
  model declared for the host (fused on macOS arm64, uncontracted on Linux
  x86-64, selected by `tools/conformance.py`; other hosts must be declared before
  the gate runs). Both Jonlib profiles are then compared exactly with their C
  models on the CPU-1, CPU-2 and JavaScript lanes.
- **Decoding** (`tools/psd_probe.py`, gate `psd`): native opaque raw PSD images
  and typed-error controls, compared exactly with `LoadImageFromMemory`. Cases
  cover representative channel counts and both depths, reserved/section data,
  trailing bytes, 4096-pixel axes and header/size/truncation boundaries. RLE cases
  add literal/repeat limits, no-ops, cross-row/channel decoding, ignored row
  lengths, depth-16 behavior and truncated/overrunning packets. Extra-channel
  cases declare five or sixteen planes while supplying only the four observed
  pixel planes.
- Shared memory/file dispatch (`image-memory`, `image-file`) includes both PSD
  encodings, alpha and cross-extension detection.

Both probes accept `--gpu` for a forced-GPU lane (local only).

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only psd-matte
```

## Known gaps

- Original-format metadata (the result is composited RGBA8), native
  malformed-stream recovery and full resource/platform/performance coverage.
- Matte profiles for hosts other than macOS arm64 and Linux x86-64 are not
  declared.
- Layer editing and PSD export are outside the API.

## Provenance

The altered stb reader retains its MIT notice in
[LICENSES/stb-image.txt](../LICENSES/stb-image.txt).
