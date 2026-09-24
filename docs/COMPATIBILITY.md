# Compatibility ledger

Reference: raylib **6.0** at `dbc56a87da87d973a9c5baa4e7438a9d20121d28`.
Candidate: Bend **2.0.27** at `ac0ddb7bf9b3255b23126886698b43a176eed8ca`.
Profile: **rgba8-cpu-images-v1**, with domains defined in [API.md](API.md).

## Verified evidence

On the local Apple M1/macOS host and GitHub-hosted **Ubuntu 24.04 (x86_64)** and
**macOS 15 (arm64)**, **26 deterministic scenarios / 6,682 pixels per lane**
match exactly on native CPU (one and two threads) and emitted JavaScript.
Ownership, bounds, color and Base.Image adapter contracts also pass on CPU/JS.
Every RGB pixel in the 64×64 PPM example matches the raylib reference.
The dimension-preservation proof checks with `All terms check.` See the
[hosted verification record](VERIFICATION.md#github-actions).

The complete **Metal gate is blocked by an unresolved failure**; see
[METAL-INVESTIGATION.md](METAL-INVESTIGATION.md). Isolated successes and a passing
20-scenario prefix do not establish the complete GPU profile.

A current run's precise inputs, source hashes and lane outcomes are in
`.build/conformance.json`. The 600-entry `.build/api-inventory.json` maps 13
reference APIs to these scoped operations/contracts; all other entries remain
not implemented. This count is an inventory, not a percentage of full parity.

| Reference capability | Jonlib operation | Status |
|---|---|---|
| `GenImageColor` | `Surface.create` | Passing valid RGBA8 fixtures |
| `ImageClearBackground` | `Surface.clear` | Passing; dimensions also covered by a checked law |
| `ImageDrawPixel` | `Surface.draw_pixel` | Passing replacement/clipping fixtures |
| `ImageDrawRectangle` | `Surface.draw_rectangle` | Passing clipping/degenerate fixtures |
| `ImageDrawCircle` | `Surface.draw_circle` | Passing midpoint/radius-12/small-radius fixtures |
| `LoadImageColors` / `GetImageColor` | `Surface.colors` / `Surface.get` | Full export passing; direct reads/ownership/out-of-bounds behavior contract-checked |
| `ImageCopy` | `Surface.copy` | Independent mutation and original-pixel preservation contract-checked |
| `GetColor` / `ColorToInt` | `Color.rgba` / channel extractors | Channel/packing contracts checked, including unsigned-byte truncation |
| `ColorAlphaBlend` | `Color.alpha_blend` | Exact reference vectors including transparent/opaque/tinted cases |
| `ImageFlipHorizontal/Vertical` | `Surface.flip_horizontal/flip_vertical` | Exact explicit and seeded full-image comparisons |
| Base.Image conversion / PPM export | `Surface.to_image/to_ppm/write_ppm` | Adapter pixels/padding and actual file RGB output checked |
| GPU execution of image operations | Same Bend API | Blocked: complete forced-on Metal suite fails |
| GPU graphics-pipeline `Draw*` APIs | Future rasterizer | Not implemented; CPU `ImageDraw*` matches do not cover these |
| Textures, text/fonts, image codecs, meshes, models, animation | Future library modules | Not implemented |
| Input, window controls, audio, native Windows/browser/Android | Future library and runtime work | Not implemented in Jonlib |

No performance parity is claimed. The array-based image algorithms are an
initial correctness foundation, not the production tiled rendering pipeline.
CUDA, Windows, browser graphics, live windows and live audio were not verified
in this milestone. Source and fixture domains are finite and explicitly
bounded; passing fixtures is not exhaustive proof of every supported input.

## Comparison policy

- Compare the complete ordered RGBA pixel array and actual dimensions.
- No image tolerance for this integer-coordinate CPU image profile.
- Pin source revisions and reject tracked changes in either upstream checkout.
- Generate both test programs from the same validated fixtures.
- Include explicit boundary regressions and deterministic seeded mixed operations.
- Reject empty fixtures, missing result rows, malformed pixels and mismatches.
- Keep blocked/skipped/unimplemented capabilities visible.

Future platform and GPU graphics profiles will specify their own controlled
inputs and comparison contracts before accepting different tolerances.
