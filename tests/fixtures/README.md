# Shared image fixtures (schema 1)

`images.json` is the common input to both raylib and Bend code generation.
Each case has a unique lowercase/hyphenated `id`, `width`, `height`, a four-byte
RGBA `background`, and an ordered `operations` array.

Supported operations:

- `pixel`: integral `x`, `y`, RGBA `color`.
- `rectangle`: integral `x`, `y`, `width`, `height`, RGBA `color`.
- `circle`: integral `x`, `y`, U32 `radius`, RGBA `color`.
- `clear`: RGBA `color`.
- `flip_horizontal`, `flip_vertical`: no other fields required.
- `blend_color`: integral `x`, `y`, and RGBA `destination`, `color` (source),
  `tint`. The independently computed blend result is written at that pixel.
- `line`: integral `x0`, `y0`, `x1`, `y1`, RGBA `color`.
- `line_v`: the same fields with finite fractional coordinates permitted.
- `triangle`: integral `x0`, `y0`, `x1`, `y1`, `x2`, `y2`, RGBA `color`.
- `triangle_lines`: the same vertex fields with finite fractional coordinates.
- `blit`: integral destination `x`, `y`, RGBA `tint`, and `source` containing
  positive `width`/`height` and exactly width × height row-major RGBA `pixels`.
  The source rectangle is the whole image, without resizing. Optional Boolean
  `observe_source` returns the source image for comparison instead of the
  destination, including its own dimensions. The runner derives the final result
  size from this observation sequence, so different-sized owners are checked.
- `blit_region`: the same source/placement fields plus an integral `source_rect`
  (`x`, `y`, `width`, `height`) that fits the source and requires no resizing.
- `crop`: integral rectangle fields, with reference clipping to a positive result
  or the reference outside-origin no-op.
- `extract`: an integral in-bounds rectangle; optional `observe_source` selects
  the retained original rather than the extracted region.
- `resize_nn`: positive `width` and `height`; the +1 fixed-point mapping must
  stay inside logical source storage. Unsafe cases belong to error-contract tests.

The domains are the same as [the initial public API](../../docs/API.md). The
optional `random` section adds mixed-operation scenarios using a fixed Python
PRNG seed. The exact expanded cases, not just the seed, are persisted and hashed
in `.build/scenarios.json`; this records the actual inputs on any Python version.

`radius-12-regression`, `composite-example` and `transform-example` are also the
references for the three headless examples. An alternate `--fixtures` file must retain them for the
example checks.

Explicit fixtures cover clipping, padded non-square storage, degenerate
rectangles, small circles, line octants/endpoints/vector rounding, triangle
winding/degeneracy/clipping, source-preserving composition, byte replacement,
flip ordering and alpha/tint rounding. Seeded scenarios broaden interactions.
Source buffers are initialized from the same validated raw pixels in both runners.
Result dimensions are tracked through crop, extraction, resize and source observation.
Fallible Bend operations propagate failures to the IO entry point, where they
fail the test; returning an unchanged image cannot conceal a rejected transform.
This is a finite conformance
corpus, not exhaustive mathematical proof of the coordinate/size domain.
