# Shared image fixtures (schema 1)

`images.json` is the common input to both raylib and Bend code generation.
Each case has a unique lowercase/hyphenated `id`, `width`, `height`, a four-byte
RGBA `background`, and an ordered `operations` array.

An optional `qoi` byte array replaces solid-color creation with actual QOI
decoding; header dimensions must match the fixture, and RGB output is explicitly
normalized to RGBA8. An optional `checked` source supplies `tile_width`,
`tile_height` and the second `color`; `background` is the first checker color.
These source modes are mutually exclusive. `export_qoi: true` additionally
requires an exact byte-array match to a real raylib file export.
`gradient_square` is another exclusive source mode with `density` in 0..1 and
RGBA `outer`; `background` supplies the inner color. A top-level `alpha_border`
threshold adds an exact final rectangle observation while retaining image pixels.
`gradient_radial` uses the same density/outer-color fields. `gradient_linear`
uses integral `direction` in -360..360 and `outer`; its fixtures use dimensions
at least two to avoid undefined reference normalization extents. Generator
failures are exercised separately in the owner/input contract tests.

Supported operations:

- `pixel`: integral `x`, `y`, RGBA `color`.
- `pixel_v`: bounded finite fractional coordinates, truncated by the reference.
- `rectangle`: integral `x`, `y`, `width`, `height`, RGBA `color`.
- `rectangle_v`, `rectangle_rec`, `rectangle_lines`: bounded finite rectangle
  fields with their distinct reference truncation order; lines also require
  `thickness` in 0..32767.
- `circle`: integral `x`, `y`, U32 `radius`, RGBA `color`.
- `circle_v`, `circle_lines`, `circle_lines_v`: corresponding vector/outline
  variants; vector centers may be fractional.
- `clear`: RGBA `color`.
- `flip_horizontal`, `flip_vertical`: no other fields required.
- `rotate_cw`, `rotate_ccw`: quarter turns; the tracked dimensions swap.
- `rotate_degrees`: integral `degrees` in -360..360 and positive `result_width`/
  `result_height` hints, checked by the actual C oracle after rotation.
- `to_pot`: RGBA fill `color`; the reference first verifies every supported axis
  size against the integer size calculation used for fixture tracking.
- `from_channel`: integral `channel`, clamped to 0..3 for RGBA8. Optional
  `observe_source` retains the original as the next fixture image. The oracle
  first checks all 256 byte values in all four channels before raw byte extraction
  is used by the candidate; grayscale output is normalized to RGBA8 explicitly.
- `collision_value`: a named `function`, flattened scalar/vector/rectangle `args`
  and output cell `x`,`y`. Boolean results use one cell; rectangle results use
  four adjacent exact F32-bit cells, all required to fit.
  Segment `lines` results use three cells (hit flag and both coordinate bits).
  `point_poly` adds a `points` array; `point_line` requires an integral threshold.
- `vector3_value` follows the numeric-probe format with flattened XYZ arguments
  and three adjacent result-bit cells for vector results. Bounding-box collision
  arguments flatten each minimum XYZ and maximum XYZ pair.
- `matrix_value` checks every matrix field in declaration order (`m0,m4,m8,m12`,
  then subsequent rows). Matrix arguments use that same order. Orthonormalization
  writes six adjacent cells for both returned vectors. Every output cell must fit;
  barycentric fixtures require a nonzero denominator after reference F32 rounding.
  Matrix inversion fixtures independently check the reference inversion-minor
  denominator; they do not substitute the public determinant's arithmetic.
- Float-list exports compare every element in native return order; the Bend
  verification writer rejects both short and overlong returned lists.
- `vector4_value` uses flattened XYZW arguments and checks all four result cells.
- `color_tint`, `color_invert`, `color_contrast`, `color_brightness`,
  `color_replace`: image transforms. Tint/replacement use RGBA `color`,
  replacement also uses `replacement`, and contrast/brightness use `amount`.
- `alpha_clear`: RGBA `color` and finite `threshold` in 0..1.
- `alpha_premultiply`: no other fields.
- `alpha_crop`: threshold in 0..1 and positive `result_width`/`result_height`
  post-size hints. The C oracle checks these immediately after the real operation;
  they never control either implementation. This enables safe validation of later
  operations without duplicating the image renderer in Python.
- `alpha_mask`: a same-size raw-pixel `source`; optional `observe_source`
  checks preservation of the original mask.
- `color_value`: `function`, RGBA `color`, optional `other`/`factor` as required,
  and output cell `x`/`y`. Tests returned packed colors or encoded Boolean results.
- `number_value`: scalar math `function` and argument list `args`, writing its
  exact F32 bits or Boolean value to a verification cell.
- `vector_value`: Vector2 `function` and flattened F32 argument list. A vector
  result uses adjacent cells for both components; scalar/Boolean results use one.
  Math uses the explicit [uncontracted-F32 profile](../../docs/MATH.md).
- `blend_color`: integral `x`, `y`, and RGBA `destination`, `color` (source),
  `tint`. The independently computed blend result is written at that pixel.
- `line`: integral `x0`, `y0`, `x1`, `y1`, RGBA `color`.
- `line_v`: the same fields with finite fractional coordinates permitted.
- `line_ex`: the same vector fields plus `thickness` in 0..32767.
- `triangle`: integral `x0`, `y0`, `x1`, `y1`, `x2`, `y2`, RGBA `color`.
- `triangle_lines`: the same vertex fields with finite fractional coordinates.
- `triangle_ex`: integral vertex fields and three colors (`color`, `color2`,
  `color3`); validation rejects undefined signed arithmetic and zero weight sums.
- `triangle_fan`, `triangle_strip`: integral `[x,y]` pairs in `points`;
  fewer than three points is a reference no-op.
- `blit`: integral destination `x`, `y`, RGBA `tint`, and `source` containing
  positive `width`/`height` and exactly width × height row-major RGBA `pixels`.
  The source rectangle is the whole image, without resizing. Optional Boolean
  `observe_source` returns the source image for comparison instead of the
  destination, including its own dimensions. The runner derives the final result
  size from this observation sequence, so different-sized owners are checked.
- `blit_region`: the same source/placement fields plus an integral `source_rect`
  (`x`, `y`, `width`, `height`) that fits the source and requires no resizing.
- `blit_rect`: raw `source`, `source_rect`, `dest_rect` and `tint`; both rectangles
  can have bounded finite fractional fields. The clipped source and truncated
  output dimensions must stay nonempty. Optional `observe_source` selects the
  original source after clipping/scaling/composition.
- `crop`: integral rectangle fields, with reference clipping to a positive result
  or the reference outside-origin no-op.
- `extract`: an integral in-bounds rectangle; optional `observe_source` selects
  the retained original rather than the extracted region.
- `resize_nn`: positive `width` and `height`; the +1 fixed-point mapping must
  stay inside logical source storage. Unsafe cases belong to error-contract tests.
- `resize`: positive `width` and `height` within 1..4096; raylib's default
  filtered path. The four retained coefficient-normalization counterexamples
  and a filtered-resize/crop sequence are part of the normal corpus. The larger
  deterministic resize corpus is generated by `tools/resize_conformance.py`.
- `resize_canvas`: dimensions 1..4096, integral offsets `x`/`y` and RGBA fill
  `color`. Changed dimensions require positive source overlap in this profile;
  equal dimensions exercise the reference no-op independently of the offsets.

The domains are the same as [the initial public API](../../docs/API.md). The
optional `random` section adds mixed-operation scenarios using a fixed Python
PRNG seed. The exact expanded cases, not just the seed, are persisted and hashed
in `.build/scenarios.json`; this records the actual inputs on any Python version.

`radius-12-regression`, `composite-example` and `transform-example` are also the
references for the three headless examples. An alternate `--fixtures` file must retain them for the
example checks.
The `qoi-all-opcodes` case with `export_qoi` also supplies the independent
reference for the QOI file round-trip example.

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
