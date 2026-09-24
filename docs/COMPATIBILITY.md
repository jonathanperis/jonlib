# Compatibility ledger

Reference: raylib **6.0** at `dbc56a87da87d973a9c5baa4e7438a9d20121d28`.
Candidate: Bend **2.0.27+jonlib-metal.1**, base
`b7ebee9217c8813067e200b0c0c9153a3be31c5e` plus the exact
[compiler overlay](../patches/README.md) declared in `toolchain.json`.
Profile: **rgba8-cpu-images-v1**, with domains defined in [API.md](API.md).

## Verified evidence

The current local Apple M1/macOS corpus contains **53 deterministic scenarios /
15,733 pixels per lane**, matching native CPU (one and two threads), JavaScript
and forced Metal. GitHub Actions runs this same corpus on **Ubuntu 24.04
(x86_64)** and **macOS 15 (arm64)** for CPU/JavaScript; use the current workflow
result for the exact published commit's hosted evidence.
Ownership, bounds, color and Base.Image adapter contracts also pass on CPU/JS.
Every RGB pixel in the primitive, composite and crop/resize PPM examples matches
the corresponding raylib reference scene.
The dimension-preservation proof checks with `All terms check.` See the
[hosted verification record](VERIFICATION.md#github-actions).

The complete **forced Metal gate passes all 53 scenarios / 15,733 pixels** on the
local Apple M1 with the declared compiler overlay. Stock Bend's failure and
rejected intermediate fixes remain documented in
[METAL-INVESTIGATION.md](METAL-INVESTIGATION.md). The hosted results linked below
originally established the CPU/JS baseline; current CI applies the declared overlay.

A current run's precise inputs, source hashes and lane outcomes are in
`.build/conformance.json`. The 600-entry `.build/api-inventory.json` maps 21
reference APIs to these scoped operations/contracts; all other entries remain
not implemented. This count is an inventory, not a percentage of full parity.
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
| `ImageDraw` | `Surface.draw_image / draw_image_region` | Partial: unscaled full source or in-bounds integral source rectangle, RGBA8 tint/alpha/clipping, both owners preserved |
| `ImageFromImage` | `Surface.extract` | Positive integral in-bounds region; independent output; original retained |
| `ImageCrop` | `Surface.crop` | Integral clipping with positive result and outside-origin no-op; typed failure preserves original |
| `ImageResizeNN` | `Surface.resize_nn` | Exact +1 fixed-point ratios; valid flat source mappings; invalid/unsafe requests preserve original |
| `ImageResize` / scaled `ImageDraw` | Future precision-correct resampler | Not implemented; default-filter precision counterexamples retained |
| `LoadImageColors` / `GetImageColor` | `Surface.colors` / `Surface.get` | Full export passing; direct reads/ownership/out-of-bounds behavior contract-checked |
| `ImageCopy` | `Surface.copy` | Independent mutation and original-pixel preservation contract-checked |
| `GetColor` / `ColorToInt` | `Color.rgba` / channel extractors | Channel/packing contracts checked, including unsigned-byte truncation |
| `ColorAlphaBlend` | `Color.alpha_blend` | Exact reference vectors including transparent/opaque/tinted cases |
| `ImageFlipHorizontal/Vertical` | `Surface.flip_horizontal/flip_vertical` | Exact explicit and seeded full-image comparisons |
| Base.Image conversion / PPM export | `Surface.to_image/to_ppm/write_ppm` | Adapter pixels/padding and actual file RGB output checked |
| GPU execution of image operations | Same Bend API | All fixture pixels pass on M1 Metal with the declared compiler overlay |
| GPU graphics-pipeline `Draw*` APIs | Future rasterizer | Not implemented; CPU `ImageDraw*` matches do not cover these |
| Textures, text/fonts, image codecs, meshes, models, animation | Future library modules | Not implemented |
| Input, window controls, audio, native Windows/browser/Android | Future library and runtime work | Not implemented in Jonlib |

No performance parity is claimed. The array-based image algorithms are an
initial correctness foundation, not the production tiled rendering pipeline.
CUDA, Windows, browser graphics, live windows and live audio were not verified
in this milestone. Source and fixture domains are finite and explicitly
bounded; passing fixtures is not exhaustive proof of every supported input.
Filled-triangle fractional vertices, default filtered scaling, automatic
source-rectangle clipping with resampling, other pixel formats and mipmaps remain
open requirements. The 21 mapped APIs must not be reported as 21 fully completed
raylib APIs. See [RESAMPLING.md](RESAMPLING.md) for the distinction between
nearest-neighbor and default-filter coverage.

## Comparison policy

- Compare the complete ordered RGBA pixel array and actual dimensions.
- No image tolerance for this integer-coordinate CPU image profile.
- Require the pinned base revisions and exact declared Bend overlay; reject
  unexpected tracked changes. Raylib must remain unmodified.
- Generate both test programs from the same validated fixtures.
- Include explicit boundary regressions and deterministic seeded mixed operations.
- Reject empty fixtures, missing result rows, malformed pixels and mismatches.
- Keep blocked/skipped/unimplemented capabilities visible.

Future platform and GPU graphics profiles will specify their own controlled
inputs and comparison contracts before accepting different tolerances.
