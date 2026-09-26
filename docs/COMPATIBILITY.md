# Compatibility ledger

Reference: raylib **6.0** at `dbc56a87da87d973a9c5baa4e7438a9d20121d28`.
Candidate: Bend **2.0.27+jonlib-metal.1**, base
`b7ebee9217c8813067e200b0c0c9153a3be31c5e` plus the exact
[compiler overlay](../patches/README.md) declared in `toolchain.json`.
Profile: **rgba8-cpu-images-v1**, with domains defined in [API.md](API.md).

## Verified evidence

The current local Apple M1/macOS corpus contains **224 deterministic scenarios /
34,111 checked output words per lane**, matching native CPU (one and two threads), JavaScript
and forced Metal. Most words are RGBA pixels; 1,667 are exact numeric/collision
result-bit probe cells. QOI export bytes are compared separately. GitHub Actions
is configured to run this corpus on **Ubuntu 24.04
(x86_64)** and **macOS 15 (arm64)** for CPU/JavaScript; use the current workflow
result for the exact published commit's hosted evidence.
Ownership, bounds, color and Base.Image adapter contracts also pass on CPU/JS.
Every RGB pixel in the primitive, composite and crop/resize PPM examples matches
the corresponding raylib reference scene.
The dimension-preservation, transpose-involution and float-export-length proofs
check with `All terms check.` See the
[hosted verification record](VERIFICATION.md#github-actions).

The complete **forced Metal gate passes all current scenarios and export bytes** on the
local Apple M1 with the declared compiler overlay. Stock Bend's failure and
rejected intermediate fixes remain documented in
[METAL-INVESTIGATION.md](METAL-INVESTIGATION.md). The hosted results linked below
originally established the CPU/JS baseline; current CI applies the declared overlay.

A current run's precise inputs, source hashes and lane outcomes are in
`.build/conformance.json`. The authoritative [API dashboard](PROGRESS.md) covers
the complete release-header/support inventory. The 600-entry
`.build/api-inventory.json` is its legacy core view, mapping 81 reference APIs to
these scoped operations/contracts. The companion ledger additionally maps 137
`raymath.h` functions. Remaining functions retain explicit planned work.
These counts are an inventory, not a percentage of full parity.
Both `profile-covered` and `contract-checked` are partial-coverage statuses.
The [master plan](MASTER-PLAN.md) defines the full-capability completion gates.

| Reference capability | Jonlib operation | Status |
|---|---|---|
| `GenImageColor` | `Surface.create` | Passing valid RGBA8 fixtures |
| `ImageClearBackground` | `Surface.clear` | Passing; dimensions also covered by a checked law |
| `ImageDrawPixel` | `Surface.draw_pixel` | Passing replacement/clipping fixtures |
| `ImageDrawRectangle` | `Surface.draw_rectangle` | Passing clipping/degenerate fixtures |
| `ImageDrawCircle` | `Surface.draw_circle` | Passing midpoint/radius-12/small-radius fixtures |
| `ImageDrawLine` | `Surface.draw_line` | Exact fixed-point octants, reversal, clipping and endpoint-exclusion fixtures |
| `ImageDrawLineV` | `Surface.draw_line_v` | Reference add-half/truncate conversion, including negative/fractional inputs |
| `ImageDrawTriangle` | `Surface.draw_triangle` | Integral-vertex winding, clipping, degeneracy and signed edge stepping |
| `ImageDrawTriangleLines` | `Surface.draw_triangle_lines` | Truncated vertices and three reference-compatible segments |
| `ImageDraw` | `Surface.draw_image / draw_image_region / draw_image_rect` | Partial RGBA8: source clipping, default scaling, destination clipping and bounded fractional rectangles; both owners retained |
| `ImageFromImage` | `Surface.extract` | Positive integral in-bounds region; independent output; original retained |
| `ImageCrop` | `Surface.crop` | Integral clipping with positive result and outside-origin no-op; typed failure preserves original |
| `ImageResizeNN` | `Surface.resize_nn` | Exact +1 fixed-point ratios; valid flat source mappings; invalid/unsafe requests preserve original |
| `ImageResize` | `Surface.resize` | Partial RGBA8 profile: default filters, exact normalization, alpha-aware output and owner-preserving invalid-size errors |
| Vector wrappers, outlines, thick lines, fans/strips and vertex-colored triangles | `Surface.draw_*` families | Exact scoped pixel comparisons, including truncation, winding and quantized vertex weights |
| `LoadImageColors` / `GetImageColor` | `Surface.colors` / `Surface.get` | Full export passing; direct reads/ownership/out-of-bounds behavior contract-checked |
| `ImageCopy` | `Surface.copy` | Independent mutation and original-pixel preservation contract-checked |
| `GetColor` / `ColorToInt` | `Color.rgba` / channel extractors | Channel/packing contracts checked, including unsigned-byte truncation |
| `ColorAlphaBlend` | `Color.alpha_blend` | Exact reference vectors including transparent/opaque/tinted cases |
| Color equality, alpha/Fade, tint, brightness, contrast and lerp | `Color` value operations | Exact packed bytes/Boolean values in the documented finite-factor profiles |
| Normalized/HSV colors | `Color.normalize/from_normalized/to_hsv/from_hsv` | Exact float bits or packed bytes, including achromatic/sector boundaries; bounded HSV input profile |
| Image color/alpha operations and checkerboards | `Surface.color_*`, `alpha_*`, `create_checked` | Exact reference arithmetic, preserved mask ownership and checked generator inputs |
| Alpha bounds/cropping | `Surface.alpha_border/alpha_crop` | Exact rectangles, retained observation owner and unchanged images for empty selections |
| Canvas resizing | `Surface.resize_canvas` | Raw RGBA copy/fill, clipping and same-size no-op; rejected requests preserve the original owner |
| Square gradients | `Surface.create_gradient_square` | Exact odd/even and density-endpoint fixtures, including density one |
| Radial/linear gradients | `Surface.create_gradient_radial/linear` | Balanced generation; radial density 0..1, integral linear directions -360..360; wider-angle rounding remains a gap |
| `ImageFlipHorizontal/Vertical` | `Surface.flip_horizontal/flip_vertical` | Exact explicit and seeded full-image comparisons |
| `ImageRotateCW/CCW` | `Surface.rotate_cw/rotate_ccw` | Exact RGBA bytes, non-square dimensions and transform sequencing |
| `ImageRotate` / `ImageToPOT` | `Surface.rotate_degrees_for/to_pot` | Checked general rotation with reference bilinear sampling; exhaustive supported POT-axis reference validation and exact fill/copy fixtures |
| QOI loading/export | `Surface.decode_qoi/to_qoi/load_qoi/write_qoi` | Valid-stream RGBA8 profile, all opcodes, exact export bytes, typed malformed-input errors and real CPU/JS file round trips |
| Scalar/Vector2/Vector3/Vector4 raymath | `Math` and vector functions | Exact results for the explicit uncontracted-F32 profile; exceptional/contracted variants remain open |
| Quaternion arithmetic/metrics/interpolation | `Quaternion` functions | Shared Vector4 representation; exact Hamilton products, zero normalization/inversion, NLERP and sign-equivalent equality |
| Quaternion/matrix conversion and composition | `Quaternion.from_matrix/to_matrix/transform`, `Vector3.rotate_by_quaternion`, `Matrix.compose` | Exact branch/tie order, full matrix/four-dimensional results and non-unit/zero quaternion behavior |
| Decomposition, 3D constructors and unprojection | `Matrix.decompose`, quaternion constructors/spline, `Vector3.rotate_by_axis_angle/unproject` | Ten-field decomposition, bounded half-angle profiles, exact inverse ordering and native invalid-domain controls |
| Float-list exports | `Vector3.to_float_v`, `Matrix.to_float_v` | Exact values/order and proven 3/16-element lengths; native array ABI/mutability remain gaps |
| Matrix arithmetic/inversion, affine constructors and vector transforms | `Matrix`, `Vector2.transform`, `Vector3.transform` | All 16 fields and transformed components compared exactly, including noncommuting products and near-singular inversion; double-transpose law checked |
| View and rotation matrices | `Matrix.look_at`, `rotate_*_for`, `rotate_for` | Reference degenerate bases, explicit bounded trigonometric profiles, raw trig bits and distinct Euler orders |
| Eleven 2D collision queries | `Collision` functions | Exact Boolean/rectangle/hit-coordinate fixtures; explicit segment contraction profiles and native-fmaf verification |
| Sphere/box queries | `Collision.spheres/boxes/box_sphere` | Exact bounded Boolean fixtures, inclusive contacts, signed radii and supplied-bound ordering |
| `ImageFromChannel` | `Surface.from_channel` | Preserved RGBA8 source and independent normalized output; all reference byte/channel combinations checked |
| Base.Image conversion / PPM export | `Surface.to_image/to_ppm/write_ppm` | Adapter pixels/padding and actual file RGB output checked |
| GPU execution of image operations | Same Bend API | All fixture pixels pass on M1 Metal with the declared compiler overlay |
| GPU graphics-pipeline `Draw*` APIs | Future rasterizer | Not implemented; CPU `ImageDraw*` matches do not cover these |
| Textures, text/fonts, additional image codecs, meshes, models, animation | Future library modules | Not implemented |
| Input, window controls, audio, native Windows/browser/Android | Future library and runtime work | Not implemented in Jonlib |

No performance parity is claimed. The array-based image algorithms are an
initial correctness foundation, not the production tiled rendering pipeline.
CUDA, Windows, browser graphics, live windows and live audio were not verified
in this milestone. Source and fixture domains are finite and explicitly
bounded; passing fixtures is not exhaustive proof of every supported input.
Filled-triangle fractional vertices, other pixel formats, mipmaps, additional
codecs and the complete numerical/platform matrix remain open requirements.
The mapped APIs must not be reported as fully completed
raylib APIs. See [RESAMPLING.md](RESAMPLING.md) for the distinction between
nearest-neighbor and default-filter coverage.

The dedicated resize gate covers 529 images / 46,474 output pixels per lane,
1,059 normalization vectors and 2,601 complete kernels. Its scope includes
identity, hidden RGB/alpha, anisotropic and extreme reductions/enlargements.
See [RESAMPLING.md](RESAMPLING.md); full format/platform/performance parity remains open.

## Comparison policy

- Compare the complete ordered RGBA pixel array and actual dimensions.
- Compare every selected QOI export byte and every scalar/vector result bit.
- No image tolerance for this integer-coordinate CPU image profile.
- Require the pinned base revisions and exact declared Bend overlay; reject
  unexpected tracked changes. Raylib must remain unmodified.
- Generate both test programs from the same validated fixtures.
- Include explicit boundary regressions and deterministic seeded mixed operations.
- Reject empty fixtures, missing result rows, malformed pixels and mismatches.
- Keep blocked/skipped/unimplemented capabilities visible.

Future platform and GPU graphics profiles will specify their own controlled
inputs and comparison contracts before accepting different tolerances.
