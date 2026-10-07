# Jonlib and Jonmath full-parity master plan

## Destination and completion rule

The goal is **100% raylib 6.0 capability and observable-behavior parity in Bend
2**, including the platform support and public companion-header capabilities
that form that release. The version is frozen so the destination is measurable;
later raylib releases become separately tracked targets.

Jonlib's algorithms remain Bend. Generic compiler/runtime/platform development
is part of the project where Bend lacks a required facility. The public API uses
Bend ownership and types, with an explicit mapping to the raylib operation.

For each capability we must establish:

1. **Availability:** the Bend equivalent and its types/constants/resources exist.
2. **Semantics:** results, edge conventions, errors and resource lifetimes match
   the reference contract, with explicit language-level adaptations.
3. **Integration:** the capability works in real applications, including the
   relevant examples, event sequences and resource combinations.
4. **Platforms/backends:** it passes on the targets that the reference supports.
5. **Operational quality:** representative performance, memory and latency
   requirements are met and documented.

A function implemented only for RGBA8 or integer coordinates remains **partial**.
A wrapper name, a skipped test, a platform stub, or a successful build does not
complete that capability. Undefined C behavior is investigated and documented;
it is not automatically a requirement to reproduce crashes or memory corruption.

## Where we are

The working foundation includes one owned image type (`Surface`, raylib pixel
formats 1..13) whose drawing, composition, transforms, resizing, mipmaps,
blur/convolution, color/alpha operations and conversions follow raylib's
per-format behavior; image codecs (including default-enabled DDS) and file
exports; bounded compression/data utilities; and extensive Jonmath profiles. They
are compared exactly with the pinned raylib reference on CPU and JavaScript lanes
(Linux and macOS in CI; forced Metal locally), with an explicit compiler overlay
fixing the observed Metal dispatch failure ([VERIFICATION.md](VERIFICATION.md)).

**We are in Phase 1. Full raylib parity has not been reached.** The
[API progression dashboard](PROGRESS.md) inventories every public declaration
in the five release headers plus `config.h`: functions, types, enum values,
macros, conditional controls and C++ conveniences. Every entry has a work package,
current/proposed Bend mapping, verification recipe, dependencies and next action.
The [compatibility ledger](COMPATIBILITY.md) holds current behavioral evidence.
The source-surface inventory task is complete; implementation and the complete
format/platform/integration/performance matrix still need to be closed.

## Ordered delivery plan

| Phase | Deliverable | Exit gate |
|---|---|---|
| 0 — Reference and toolchain | Pinned raylib/Bend, source provenance, differential runners, CI, capability inventory | Reproducible nonempty tests, trustworthy failure detection, documented complete target surface |
| 1 — Math and CPU images | Numeric helpers, vectors/matrices/collisions, every image primitive, transformations, composition, formats/codecs | Exact/tolerance-defined API comparisons, boundary inputs, ownership and malformed-asset evidence |
| 2 — Interactive 2D | Window/event lifecycle, timing, input state, sprites/textures, cameras, render targets, batching | Deterministic input replay plus real desktop integration; representative raylib 2D examples work |
| 3 — Text and fonts | Bitmap, TTF/OTF/FNT handling, codepoints, measurement, drawing and font resources | Matching layout/raster contracts and resource lifecycle across supported formats |
| 4 — Audio | Decode/load, sound/music, mixing, pitch/pan, streaming, device lifecycle and callbacks | Offline PCM comparisons, streaming/device tests, underrun and latency budgets |
| 5 — 3D and assets | Meshes, models, materials, cameras, lighting, animation, collisions, import/export | Controlled scene comparisons, importer fixtures and representative model/animation examples |
| 6 — Graphics pipeline and low-level compatibility | Programmable effects, shader loading, render state, rlgl-equivalent behavior and interop | Declared shader/graphics-state contracts and examples pass on each required backend |
| 7 — Platform completion | Native Windows, Linux variants, macOS, web, Android and the remaining reference targets | Real platform lifecycle/input/audio/graphics/package checks; compilation alone is insufficient |
| 8 — Parity release | Close every required inventory gap and sustain compatibility | All required matrix entries complete; performance/resource gates met; versioned compatibility report |

Phases express dependency order, not isolated silos. Platform and performance
checks run from the first usable implementation. A vertical slice can bring a
small part of a later phase forward when needed by an example or a runtime gap.

## Phase 1: status and remaining work

Delivered Phase 1 slices: the image module (`images`, `resampling`,
`image-codecs` work packages: every API mapped and compared with raylib on
formats 1..13 where raylib supports them), `random`, most of `jonmath` and the
2D/sphere/box `collision` queries. What remains in Phase 1, in the recommended
order (`docs/PROGRESS.md` lists every ID):

1. **`types`** — raylib's enums, enumerators, constants and struct types as Bend
   constants/types (531 catalog entries, mostly mechanical). Low risk, and it
   makes the language mapping that every later API reuses explicit.
2. **`files` and `memory`** — the path utilities and file data/text/code IO are
   delivered ([FILES.md](FILES.md)); directories, rename/remove, modification
   times and the working directory are blocked on OS primitives Base lacks
   (runtime workstream), and the trace-log/allocation contracts remain.
3. **`pixels` macros and color utilities** — named color constants and the
   remaining color/format helpers.
4. **Blocked numerics** — `MatrixPerspective`, `QuaternionSlerp`,
   `QuaternionToAxisAngle`, `QuaternionToEuler` and the cubic Bézier spline
   need native `tanf`/`acosf`/`atan2f`/`powf` profiles. The diagnostic
   `perspective` and `inverse-trig` gates already record native behavior; the
   work is accurate per-libm kernels, as for `sinf`/`cosf`. The ray collisions
   (`GetRayCollisionSphere/Box/Triangle/Quad`) need fused-contraction variants
   of the raymath helpers `rmodels.c` inlines (arm64 builds contract them);
   the mesh/model collisions wait for the Phase 5 types.
5. **Image leftovers** — compressed formats (14+) and multi-level images (DDS
   DXT and mip chains are loaded by default raylib; PKM/KTX/PVR/ASTC are
   configuration options), which need a storage decision (below); the
   text-to-image functions (`ImageText*`, `ImageDrawText*`), which need
   raylib's default font, UTF-8 decoding and text measurement and are best done
   as the first slice of Phase 3; the configuration-gated JPEG decoder; and
   wider domains (dimensions above 4096, samples outside the defined C casts).

Undefined native behavior found on the way is refused, not reproduced: e.g.
`ImageAlphaClear` on R5G5B5A1/R4G4B4A4 casts `round(channel*31)` to a byte,
which the arm64 build evaluates without truncation, so those colors are
`InvalidRequest`.

Detailed contracts for the delivered Phase 1 profiles are in the topic pages
listed by the [API](API.md) and [compatibility](COMPATIBILITY.md) pages. Private
numerical prerequisites (the [binary64 helpers](BINARY64.md) and the
[modern angle kernel](MODERN-ANGLE.md)) back the [checked angle APIs](ANGLES.md);
device/resource and wider-domain evidence remain Phase 1 work.

## Completion and phase exit

No API is `complete` yet, and none can be during Phase 1: completion requires
all six gates **and** a verified result on every target in
`api/milestones.json` (Windows, the BSDs, Android, the browser, each GL
version...), so even a pure CPU function like `ImageResize` completes only with
Phase 7. That is intentional for the release gate, but it hides Phase 1
progress. The proposed Phase 1 exit measure, reported alongside the strict
counts by `tools/api_plan.py`, is: every Phase 1 function `partial` with
`behavior` and `ownership` verified on the CI hosts (Linux x86_64 and macOS
arm64, CPU and JavaScript lanes) and on forced Metal locally, no behavior gaps other than documented
undefined native behavior, and its remaining gaps limited to targets,
integration and performance.

Decisions for Jonathan before the next batches:

- **Compressed and multi-level images.** Proposed: a third `Surface.Pixels`
  variant holding compressed blocks, multi-level loads returned as
  `Image.Mipmaps`, and every CPU operation raylib does not support on
  compressed data returning `UnsupportedFormat` (raylib logs and leaves the
  image unchanged).
- **The Phase 1 exit measure** above, which changes how progress is reported
  (not the release definition).
- **Enum and constant mapping (`types`).** Proposed: raylib enumerators as
  zero-argument U32 functions with raylib's spelling (as `Color.RAYWHITE()`
  and `Math.PI()` now are), since raylib APIs take them as `int`; sum types
  would be safer but diverge from flag combinations such as `ConfigFlags`.
- **Global state (`memory`, file callbacks).** `SetTraceLogLevel`,
  `SetTraceLogCallback` and the `Set*FileCallback` hooks mutate process-wide
  state that Bend does not have. Proposed: explicit logger/loader values passed
  to the operations that log or load, recorded as language adaptations.
- **Order of the remaining Phase 1 packages** versus starting the Phase 2
  window/input foundation.

## Near-term sequence

The current milestone is a headless image foundation: owned images, drawing,
composition, transforms, codecs and math, verified against raylib 6.0 CPU image
operations. Next, in dependency order:

1. **2D library growth.** Complete the remaining primitive families, math and
   collision helpers; add compressed/multi-level images and close gaps in the
   [image codec profiles](CODECS.md), including remaining codecs and
   original-format metadata; add text/fonts and PCM WAV
   with their own reference gates; port selected upstream examples and compare
   deterministic outputs. Efficient command buffers and tiled rendering must be
   measured against equivalent raylib scenes; the current correctness-oriented
   image loops are not an assumed high-performance architecture.
2. **Interactive platform foundation.** Use existing Base windows/audio where
   sufficient; add generic Bend facilities for event polling, sizing/DPI/
   fullscreen, cursor/clipboard, text entry, high-resolution timing, presentation
   pacing, audio backpressure and gamepad/touch input. Rendering, decoding and
   mixing algorithms stay in Bend.
3. **Assets and 3D.** General clipping/depth, textured meshes, cameras, lighting,
   animation, model importers, richer fonts and compressed image/audio formats.
   Programmable effects are defined in Bend; the compatibility contract for
   arbitrary GLSL and low-level rlgl interoperability is decided separately.
4. **Platform expansion.** Native Windows, browser and Android need runtime,
   compiler and platform work. Each platform needs lifecycle, input, audio,
   graphics and packaging evidence; unsupported targets are tracked openly.

## Compiler and runtime workstream

Keep generic OS/device mechanisms in Bend's platform boundary and the game
library's algorithms in Jonlib. Likely runtime tasks include:

- Window resize/fullscreen/DPI, event polling, clipboard and cursor modes.
- High-resolution clocks and presentation/frame pacing.
- Text entry, gamepad axes/buttons, touch and device connection events.
- Audio queue/backpressure, device enumeration and streaming lifecycle.
- Native resource/buffer interoperability where a reference API needs it.
- Native Windows/browser/Android and the other required host backends.
- Required numeric representations and compiler/runtime correctness fixes.

Each change needs a small independent runtime/compiler regression plus the
affected Jonlib scenarios. The Metal work demonstrated why: one candidate
passed Jonlib but broke another Bend workload, and was rejected. Preserve that
cross-workload gate for future compiler changes.

The Metal dispatch defect is resolved for the declared profile by the explicit,
hash-checked compiler overlay in `toolchain.json`
([METAL-INVESTIGATION.md](METAL-INVESTIGATION.md)): dispatcher-only boundaries,
no source-specific rule and no altered expected output. The overlay is a
checked-in Apache-2.0 patch until upstream integration; CUDA and the upstream
cluster/site gates remain unverified. Retain the exact-source checks when
updating Bend.

## The parity loop for every batch

1. Read the pinned implementation, declaration, examples and known edge cases.
2. Define the observable contract and list the currently unsupported domains.
3. Build a deterministic shared fixture and run the real raylib reference.
4. Implement the Bend operation with explicit ownership and device boundaries.
5. Compare actual outputs; diagnose differences rather than modifying expected
   values or increasing tolerances until the test passes.
6. Check laws where they express useful invariants, then CPU/JS/Metal as relevant.
7. Expand platform, integration and performance evidence for the affected scope.
8. Update the API ledger, examples, provenance, docs and CI before closing work.

We reuse upstream tests where applicable and port upstream examples into bounded
scenarios. Raylib's existing smoke tests and screenshots are useful inputs, but
we must supply the behavioral assertions they do not contain. In addition:

- Control random seeds, clocks, assets, quality settings, backends and capture frames.
- Use exact assertions for deterministic integer/image behavior; define any
  numeric or rendering tolerance before accepting a mismatch.
- Add small regressions for independently meaningful failure boundaries.
- Measure resource growth, frame-time distributions and audio underruns as
  requirements separate from correctness.
- Record unimplemented, runtime-blocked, passing and intentionally divergent behavior.

Passing Jonlib's suite means the declared, exercised profile passes; it is not
proof about every raylib program. See [VERIFICATION.md](VERIFICATION.md).

## Tracking progress honestly

The authoritative [ledger](../api/ledger.json) is generated from the pinned
reference catalog, [work packages](../api/milestones.json) and editable
[progress records](../api/progress.json). Statuses are `not-started`,
`in-progress`, `partial`, `blocked` and `complete`. The legacy core map retains
`profile-covered` and `contract-checked`; both mean **partial**.

Each entry carries its reference symbol, current/proposed Bend equivalent,
domains/formats, platform policy, fixtures/evidence and open gaps.
Report API availability, behavioral coverage, platform coverage and performance
separately. Never turn a count of mapped functions into a “percent complete”
claim for the entire library.

The final denominator includes all required public `raylib.h` APIs and the
release's companion surfaces (including raymath, rlgl, camera/gesture helpers,
constants and supported configurations). Nothing can be dropped as “not
applicable” merely because it is difficult in Bend. Any proposed scope change
must be brought back to Jonathan explicitly.

## How each delivery will guide the project

Each implementation report will state:

- What can now be done with Jonlib that could not be done before.
- Stable API IDs changed, before/after scope and status, and milestone totals
  generated by `python3 tools/api_plan.py report --since BASE_COMMIT`.
- Which raylib contracts are exercised and on which targets.
- The important mismatches or runtime discoveries and their resolutions.
- Remaining limits and the next dependency to implement.

Follow the [API tracking procedure](API-TRACKING.md) to select work, update
evidence, regenerate checklists and pass the drift/completion gates.

The immediate product milestone is a real 2D application built from the image,
texture, text, input and audio foundations. That is an intermediate milestone;
the destination remains the full, versioned parity matrix.
