# Cropping and resampling status

## Implemented in Bend

- `Surface.extract`: an independently owned positive, integral, in-bounds region;
  the original image owner is returned too (`ImageFromImage` profile).
- `Surface.crop`: raylib's integral clipping and outside-origin no-op behavior
  when the resulting image remains nonempty (`ImageCrop` profile).
- `Surface.resize_nn`: raylib's **16.16 ratios with the +1 correction**, preserving
  every RGBA byte (`ImageResizeNN` profile).
- `Surface.resize`: default filtered RGBA8 resizing with Catmull-Rom upsampling,
  Mitchell downsampling and alpha-aware filtering (`ImageResize` profile).
- `Surface.draw_image_region`: unscaled, in-bounds integral source rectangles,
  destination clipping, tint and alpha, returning both image owners.

The explicit transform errors retain the original owners. Empty crop results,
invalid dimensions and nearest mappings that would read beyond logical source
storage are rejected rather than repaired or silently accepted.

### A nearest-neighbor edge case

Raylib's +1 ratio can cross a source row at extreme upscales. A 2×2 image resized
to 512×1 can read the first pixel of the second row at the right edge; that is
still inside the flat source allocation, and the fixture preserves that result.
A 2×1 source resized to 512×1 would read outside its allocation. Jonlib rejects
that request with `UnsafeNearestMapping` and returns the original image.

## Default filtered RGBA8 resize

`ImageResize` and the scaling path of `ImageDraw` use **stb_image_resize2**:

- Catmull-Rom for upsampling and Mitchell for downsampling; point sampling on
  an unchanged axis.
- Double-precision coefficient normalization and rational-phase reuse.
- Edge coefficient folding and dimension-dependent horizontal/vertical ordering.
- Seven-channel filtering for ordinary RGBA: unweighted RGB, alpha and weighted
  RGB, so fully transparent colors are handled deliberately.
- Output clamping/rounding and architecture-dependent SIMD execution details.

`Surface.resize` implements this path in Bend for owned RGBA8 images with one
mip level and dimensions 1..4096. Invalid sizes preserve the original surface
with `InvalidSize`. `ImageResizeNN` remains a separate operation.
`Surface.draw_image_rect` integrates the default resizer into source-clipped,
scaled `ImageDraw`, including bounded fractional rectangle fields and both owners.

`src/resize_numeric.bend` uses integer limbs for the finite-normal binary64
addition, reciprocal and multiplication required by coefficient normalization,
including nearest/even rounding before conversion back to F32. It is an
internal, bounded numerical contract rather than a general IEEE-754 API.
`src/resample.bend` implements the filters, phase reuse, clamp folding, horizontal
coefficient packing, seven-channel RGBA pipeline and reference operation order.

## Exact verification

```sh
python3 tools/resize_conformance.py
python3 tools/resize_conformance.py --gpu
```

The gate compares 1,059 normalization vectors / 6,470 coefficient bit patterns,
2,601 packed horizontal kernels (first index and every coefficient bit), and 529 images /
46,474 output pixels per lane. The image corpus includes the original 512 seeded
cases and 17 boundary cases: transparent/opaque colors, identity, anisotropic
scales, large filter supports and both 4096-to-1 and 1-to-4096 axes.
The four retained counterexamples also run in the normal conformance corpus,
alongside a filtered-resize/crop sequence and invalid-size ownership checks.

Results are in `.build/resize/results.json` and `images-results.json`, including
scope, source hashes, toolchain, host and exact image-input hashes. `--images-only`,
`--lane` and `--case-prefix` permit focused diagnosis; a selected subset is
reported with its own case/lane counts. The whole-image reference is unmodified
raylib; coefficient observation logging affects only a task-local diagnostic
copy of the pinned stb header. No tolerance is applied to pixels or coefficients.
The final local CPU/JavaScript/forced-Metal runs pass all three stages; the
durable summary is [evidence/default-resize.json](evidence/default-resize.json).

The implementation retains a full seven-channel intermediate buffer. Memory
and speed parity, additional formats/mipmaps, dimensions beyond the Surface
profile, other GPU models and complete platform integration remain unverified.

## Reproducible precision experiment

```sh
python3 tools/conformance.py
python3 tools/filter_probe.py
```

The probe uses 512 deterministic raw RGBA inputs. For each one it compares the
actual raylib `ImageResize` output with a standalone copy of the exact pinned
stb core, first unmodified, then with **only** `STBIR_RENORMALIZE_IN_FLOAT` enabled.
Neither diagnostic variant changes the production reference or its expected pixels.

On the local Apple M1 / Apple clang 21.0.0 run:

| Variant | Mismatching cases | Different channels |
|---|---:|---:|
| Unmodified stock core | 0 / 512 | 0 |
| Float-only normalization | 4 / 512 | 7 |

Examples include an alpha value of **124 becoming 125**, and **192 becoming 191**.
These are small but real exact-output failures. Changing the image tolerance to
accept them would conceal missing arithmetic fidelity.

Results, source-header/input hashes and compact counterexamples are written to
`.build/filter-probe/results.json`. CI records the same experiment per platform.
The local reference record is retained in
[evidence/filter-normalization.json](evidence/filter-normalization.json).
The diagnostic command succeeds when its stock control is valid; a diagnostic
variant's mismatch is reported, not mistaken for passing Bend conformance.

## Precision findings and next step

The original F32-only normalization experiment remains a negative control.
During implementation, Metal's approximate `pow(2, exponent)` changed coefficient
bits; exact power-of-two scaling resolved that discrepancy. Large support widths
also exposed non-tail list construction/counting limits on JS and the device VM;
bounded-stack traversals preserve the same coefficient and accumulation order.

The cropped/scaled integration now passes the shared reference fixtures.
Further work includes formats/mipmaps, additional numerical domains and
performance/resource parity. The current queue is in [PROGRESS.md](PROGRESS.md).

Source: [raylib 6.0 resizer core](https://github.com/raysan5/raylib/blob/dbc56a87da87d973a9c5baa4e7438a9d20121d28/src/external/stb_image_resize2.h).
The probe compiles that external header as reference tooling; no stb implementation
is linked into Jonlib's Bend library.
