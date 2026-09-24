# Cropping and resampling status

## Implemented in Bend

- `Surface.extract`: an independently owned positive, integral, in-bounds region;
  the original image owner is returned too (`ImageFromImage` profile).
- `Surface.crop`: raylib's integral clipping and outside-origin no-op behavior
  when the resulting image remains nonempty (`ImageCrop` profile).
- `Surface.resize_nn`: raylib's **16.16 ratios with the +1 correction**, preserving
  every RGBA byte (`ImageResizeNN` profile).
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

## Default filtered resize is still open

`ImageResize` and the scaling path of `ImageDraw` use **stb_image_resize2**:

- Catmull-Rom for upsampling and Mitchell for downsampling; point sampling on
  an unchanged axis.
- Double-precision coefficient normalization and rational-phase reuse.
- Edge coefficient folding and dimension-dependent horizontal/vertical ordering.
- Seven-channel filtering for ordinary RGBA: unweighted RGB, alpha and weighted
  RGB, so fully transparent colors are handled deliberately.
- Output clamping/rounding and architecture-dependent SIMD execution details.

`ImageResizeNN` is not a replacement for this path. No `Surface.resize` default
filtered API or scaled `ImageDraw` is currently claimed as reference-compatible.

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

## Next implementation dependency

Implement the reference's precision-sensitive coefficient operations in Bend
(with suitable wider-number support where necessary), then complete the filter
and alpha pipeline against the retained counterexamples and broader fixtures.
Only after that passes can cropped/scaled `ImageDraw` use the default resizer.

Source: [raylib 6.0 resizer core](https://github.com/raysan5/raylib/blob/dbc56a87da87d973a9c5baa4e7438a9d20121d28/src/external/stb_image_resize2.h).
The probe compiles that external header as reference tooling; no stb implementation
is linked into Jonlib's Bend library.
