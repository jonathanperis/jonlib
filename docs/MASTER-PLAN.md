# Master plan: 100% raylib on Bend 2

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

The working foundation includes owned RGBA8 surfaces, basic drawing, color
blending, image flips/copies, Base.Image conversion and headless export. It has
exact raylib-reference comparisons on CPU/JS/Metal, hosted Linux/macOS checks,
and an explicit compiler overlay fixing the observed Metal dispatch failure.

**We are in Phase 1. Full raylib parity has not been reached.** The
[compatibility ledger](COMPATIBILITY.md) and generated API inventory hold current
evidence. The first 600 declarations from `raylib.h` are inventoried; companion
headers, constants, formats and platform configurations also belong in the
completion matrix and must be inventoried before their phases close.
The companion-surface inventory remains an open Phase 0 task while Phase 1
implementation proceeds; the foundation is usable, but Phase 0 is not being
declared fully complete.

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

## Phase 1: current implementation sequence

1. **Line and triangle rasterization:** exact endpoint/edge/winding behavior,
   clipping, degenerate inputs, and vector-coordinate variants.
2. **Image composition:** full-source unscaled drawing first, then cropped and
   scaled drawing, filter behavior, formats and mipmaps. A full-source-only
   implementation stays partial for `ImageDraw`.
3. **Remaining image operations:** outlines, fans/strips, gradients, procedural
   generation, crop/resize/rotate, alpha operations, color transformations and
   pixel-format conversion.
4. **Math and collision completeness:** raymath's vectors/matrices/quaternions,
   projection and interpolation helpers, and raylib's collision operations.
5. **Asset bytes and codecs:** byte-buffer utilities, image loading/export and
   format-specific decoders. Start with simpler formats, then implement the
   remaining formats without silently delegating algorithms to native libraries.
6. **Broaden domains:** close the initial dimension, coordinate, format and
   numerical-precision gaps. F32-only convenience signatures are not a reason
   to discard required signed/wider-number behavior.

The current verified batch adds **crop/extraction, source-rectangle drawing and
fixed-point nearest-neighbor resizing**. Default filtered resizing remains open:
the [precision probe](RESAMPLING.md) demonstrates why replacing the reference's
double normalization with F32 arithmetic is insufficient. The next dependency
is precision-correct coefficient/filter evaluation before closing scaled ImageDraw.

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
we must supply the behavioral assertions they do not contain.

## Tracking progress honestly

The current map uses `profile-covered` and `contract-checked` for limited,
evidence-backed implementations; both are **partial**, not completed full APIs.
The generated inventory marks unmapped entries `not-implemented`.

As the inventory expands, each entry must carry its reference symbol, Bend
equivalent, domains/formats, platforms/backends, fixtures/evidence and open gaps.
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
- Which raylib contracts are exercised and on which targets.
- The important mismatches or runtime discoveries and their resolutions.
- Remaining limits and the next dependency to implement.

The immediate product milestone is a real 2D application built from the image,
texture, text, input and audio foundations. That is an intermediate milestone;
the destination remains the full, versioned parity matrix.
