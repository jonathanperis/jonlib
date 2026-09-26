# Verification record

Latest expansion: 2026-09-26. Host: Apple M1 / macOS 27.0. Bun 1.3.12 and Apple clang 21.0.0.
The current base revision and exact compiler overlay are pinned in `toolchain.json`.

## Executed checks

Reproduce the checks using the checkout variables from
[README.md](../README.md#requirements):

```sh
python3 -m unittest discover -s tests -v
python3 tools/conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/resize_conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --images-only
python3 tools/resize_conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --images-only --gpu --lane metal
python3 tools/trig_probe.py --bend-source "$BEND_SOURCE" --gpu
python3 tools/gradient_bench.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
BEND_NO_TELEMETRY=1 bun "$BEND_SOURCE/bend2/main.ts" PROOF.bend
```

- Eight harness/planning test methods pass, including changed pixels, empty/missing results,
  invalid fixtures, Boolean/floating-point dimensions masquerading as integers,
  and compiler source/patch tampering or unexpected tracked changes.
- 149 scenarios / 32,515 output words match pinned raylib exactly on each
  of native CPU one-thread, native CPU two-thread, emitted JavaScript, and forced
  Metal with the declared compiler overlay.
- The word count includes 118 exact scalar/Vector2 result-bit probe cells.
  The math reference explicitly uses uncontracted F32; no comparison tolerance
  is applied. Both components of each vector output are checked.
- Seven QOI export scenarios compare all 299 encoded bytes per lane. Real CPU/JS
  file export/load round trips match actual raylib file bytes and decoded pixels.
  Missing, malformed and oversized file errors are checked separately.
- Typed QOI byte-stream failures, mask-size failures, invalid checker sizes and
  invalid image-rectangle failures pass, including forced Metal for the pure APIs.
- The owned-copy, out-of-bounds read, color packing/channel and Base.Image
  pixel/padding contracts pass on native CPU and JS.
- `PROOF.bend` checks: `All terms check.` The theorem is dimension preservation
  by clear; it is not a general proof of graphics correctness.
- The primitive, composite and crop/resize PPM examples match every RGB component
  of their raylib scenes.
- New fixtures cover line octants/reversal/degeneracy/clipping, vector rounding,
  triangle windings/degenerate edges, and image composition with source preservation,
  including different-sized source and destination owners.
- Crop, extraction, nearest-neighbor and region-compositing fixtures track changing
  result dimensions; transform failures retain their original owners on CPU,
  JavaScript and forced Metal.
- Default filtered resize retains its independent coefficient/kernel evidence
  for the unchanged resampling modules. The expanded harness also reruns the
  529-image / 46,474-pixel resize corpus; see the scoped records under `.build/resize/`.
- Five alpha-border observations compare exact rectangles and preserve the
  observed pixels. Alpha-crop post-size hints are checked against the actual C
  oracle; a deliberately wrong hint is rejected before candidate execution.
- The pinned core header inventory contains 600 unique public functions; 62 have
  explicitly scoped Jonlib mappings. The raymath ledger additionally maps 32
  functions. Every mapping remains partial; all six completion gates are still required.
- The bounded trigonometry gate matches all 721 integral directions in -360..360
  on CPU, JS and Metal for its declared reference profile. Ubuntu's subsequent
  native-libm mismatch required the explicit GNU/Arm polynomial profile; the
  original portable-only CI failure is preserved in the run history.
  A wider 65,535-direction diagnostic retains 52 Apple
  float-libm mismatches as an explicit open domain, not a passing gate.
- Serial and balanced gradient generation retain the reference checksum on a
  512×512 workload. CPU process-time improvement and device setup costs are
  reported with their actual scope in [GRADIENTS.md](GRADIENTS.md).
- Library source passes the no-unsafe/no-custom-foreign-import gate.
- Relative documentation links resolve, raylib's license is retained verbatim,
  and `.specs/` is ignored. No specification files were previously tracked.
- Raylib remains clean. Bend has exactly the declared compiler-overlay files;
  their hashes match the lockfile. Verification does not modify either checkout.
- The unchanged compiler overlay retains its prior evidence: 16 selected Bend
  regressions passed on CPU/JS, 7 with forced Metal. Its generic test exercises
  the added dispatch boundary; this is separate from the expanded image corpus.
- During compiler adoption, three representative CPU/Metal workloads retained their checksums; their warmed
  process-time medians remain within about 1% of baseline. See the investigation
  for parameters, measurements and the rejected broader outlining policy.

Exact source/input hashes, host, lane outcomes and generated full pixel arrays
are retained under `.build/`. The latest default run is `.build/conformance.json`.
The recorded compiler adoption evidence is also checked in at
[evidence/metal-dispatch.json](evidence/metal-dispatch.json).
The current primitive/compositing batch is recorded separately at
[evidence/image-primitives.json](evidence/image-primitives.json), including final
source hashes and the different-sized source-preservation observation.
The subsequent crop/resize batch is recorded in
[evidence/image-transforms.json](evidence/image-transforms.json). The default-filter
precision experiment and its retained inputs are in
[evidence/filter-normalization.json](evidence/filter-normalization.json).
The precision-correct Bend implementation and final four-lane library gate are
recorded in [evidence/default-resize.json](evidence/default-resize.json).
The current expansion is recorded in
[evidence/image-parity-expansion.json](evidence/image-parity-expansion.json).
The following alpha/canvas/gradient/metric batch is recorded in
[evidence/alpha-bounds-canvas.json](evidence/alpha-bounds-canvas.json).
The balanced gradient/movement batch, its timing scope and retained numerical
gap are recorded in [evidence/gradient-generation.json](evidence/gradient-generation.json).
The subsequent general rotation/POT/vector batch is recorded in
[evidence/rotation-pot.json](evidence/rotation-pot.json), including exhaustive
reference comparison of all 4096 supported POT axis sizes.

## Acceptance status

| Criterion | Result | Evidence |
|---|---|---|
| A1: nonempty, full-pixel differential suite | Pass | 149 scenarios per execution lane; strict comparison |
| A2: clear/pixel/clipped rectangle/midpoint circle parity | Pass within declared profile | Explicit and seeded reference fixtures |
| A3: dimensions, ownership and bounded indexing | Pass for checked contract | Clear law, full outputs, owned-copy/get and clipping checks |
| A4: Bend-only source, CPU/JS behavior | Pass | Source gate and three execution lanes |
| A5: complete forced-on Metal gate | Pass on local M1 with overlay | Full exact-pixel suite; detailed history in METAL-INVESTIGATION.md |
| A6: API, commands, licensing and limitations | Pass | Documentation/source review |
| A7: corrupted output and empty suite rejected | Pass | Harness negative controls |
| A8: real headless export and Base.Image adapter | Pass | Native PPM comparison and CPU/JS adapter contract |
| A12: compiler fix and broader verification | Pass in recorded scope | 16 upstream cases, three workload comparisons, full Jonlib GPU corpus |
| A13: exact compiler provenance | Pass locally | Base/patch/file hashes and negative controls; hosted clean-base application is enforced by CI |
| A14: line/triangle raster semantics | Pass within declared profiles | Exact primitive fixtures on CPU/JS/Metal |
| A15: unscaled image composition | Pass within declared profile | Clipping, mixed alpha/tint, and full source-image observation |
| A16: full-parity plan and honest coverage | Pass | MASTER-PLAN.md and explicitly partial API mappings |
| A17: crop/extract/nearest and failure ownership | Pass within declared profiles | Exact dimensions/pixels plus typed-error owner checks |
| A18: source-region composition | Pass within declared profile | In-bounds integral source regions with clipping/tint/alpha |
| A19: default-filter evidence | Pass; RGBA8 implementation verified | Original float-only negative control retained; exact Bend normalization and filtered outputs pass |
| A24: default RGBA8 resize and owner failures | Pass within declared profile | Coefficient-bit oracle, 529 images including all four retained counterexamples, and CPU/JS/forced-Metal owner checks |
| A25: scaled/fractional source-clipped composition | Pass within declared profile | Exact source/destination clipping, size-decision order, output pixels and original-owner tests |
| A26: additional drawing, color/alpha, rotations and math | Pass within declared profiles | Exact pixel/bit comparisons, signed-zero and rounding boundaries, vertex winding and alpha semantics |
| A27: QOI decoding and malformed-input handling | Pass within declared profile | All six opcodes, RGB normalization, cache/run boundaries, 4096-pixel traversal and typed failures |
| A28: exact QOI export and file IO | Pass within declared profile | Actual raylib ExportImage bytes, real CPU/JS round trip and file-error cases |

## Limitations

The unmodified stock-compiler failure is retained as historical evidence. The
complete normal GPU gate passes with the explicit compiler overlay; no emitted-C
rewriting or source-specific workaround is part of that gate. The patch has not
been accepted upstream. The original underlying Metal optimizer/resource defect
has not been isolated independently of Bend's generated code.

No live desktop window, audio device, browser UI, CUDA, Windows, Android,
raylib-versus-Jonlib performance comparison, long-run resource soak, or complete raylib conformance
was verified. The image tests are finite, not exhaustive over the documented
input domain. The public Surface constructor must retain the API's invariant.
The full upstream mini-cluster/site gates were not run, and the local repository
token-cap gate could not be run because `ttok` is unavailable. No tool was installed.

## Regression review

Reviewed 46 authored caller/declaration contexts across Bend and Python,
generated-call templates, all public mappings, and 20 assertion sites (six
negative-control contexts, ten Bend exact-value comparisons, three output
comparators and the law). The scan caught output-dimension validation accepting
Boolean/float values through Python numeric equality. The parser now rejects
them; negative controls and the affected full conformance run pass after the fix.

Regression scan: 46 callers checked, 20 assertions checked, 1 flagged/fixed.

## GitHub Actions

The public repository is <https://github.com/jonathanperis/jonlib>.
The gradient-reference follow-up `1a792f9cbba58ab0f3b19d63a47e5be3d54baf4d` passed
[Checks](https://github.com/jonathanperis/jonlib/actions/runs/36157572756) and
[Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36157572809).
Downloaded artifacts establish all 134 scenarios and the 529-image resize gate
on both hosts, plus zero mismatches for all 721 directions against each host's
actual native libm. Ubuntu uses `GnuGradient`; macOS uses `AccurateGradient`.
See [the exact hosted record](evidence/hosted-1a792f9.json).

Commit `b73c97aee2de38a2f90f22648f9925f8574ee8b2`, published to `main`, passed:

- [Checks — harness and project validation](https://github.com/jonathanperis/jonlib/actions/runs/36147174640).
- [Conformance — Ubuntu 24.04 and macOS 15](https://github.com/jonathanperis/jonlib/actions/runs/36147174605).

Downloaded artifacts confirm both hosts ran all 125 scenarios / 22,285 words
per CPU-1/CPU-2/JS lane, five alpha-border observations, seven exact QOI exports,
the 529-image resize corpus and all 16 selected compiler regressions. Source and
fixture hashes match the local verified implementation. See the
[hosted evidence record](evidence/hosted-b73c97a.json).

### Historical baseline

The first published commit, `c5418fb4cb309a233dde8cfec39fea5b07011f67`, passed:

- [Checks — harness and project validation](https://github.com/jonathanperis/jonlib/actions/runs/36033674066).
- [Conformance — Ubuntu 24.04 and macOS 15](https://github.com/jonathanperis/jonlib/actions/runs/36033674161).

Downloaded evidence confirmed each operating system ran all 26 scenarios and
6,682 pixels per CPU-1/CPU-2/JavaScript lane, plus the ownership/adapter contracts,
proof and PPM example. The Linux host was x86_64 with clang 18.1.3; the macOS host
was arm64 with Apple clang 17.0.0. Both used Bun 1.3.12.

Hosted jobs do not execute the Metal gate or claim GPU compatibility. Actions
and dependency revisions are pinned; scoped JSON/PPM artifacts are retained
for 14 days, while workflow logs/results follow repository retention settings.
Hosted status must be established from the exact published commit's Actions
results; local evidence alone does not establish a hosted pass.

## Compiler overlay regression review

The overlay review checked 21 direct caller sites for the changed compiler
helpers and checkout verifier, plus cache metadata, wrapper liveness, generated
CPU/CUDA aliases, CI patch application and its consumers. It inspected 34
upstream exact-output expectations and 10 harness negative-control assertion
sites. Additional evidence covers full-pixel comparison, the original-FAR plus
new-wrapper interaction, normalized generated code and workload checksums.

The scan corrected stale documentation that still required an entirely
unmodified Bend checkout. The contract now consistently requires the exact
declared overlay and rejects other tracked changes. The earlier, unsafe global
outlining candidate was rejected during implementation and never adopted.

Regression scan: 21 callers checked, 44 assertions checked, 1 flagged/fixed.

## Primitive/compositing regression review

Reviewed 14 Bend caller contexts and seven Python validation/generation/comparison
contexts. The assertion review covered ten harness negative-control contexts,
dimension/count/pixel comparisons, the two shared PPM checks and the existing law.
The review strengthened source observation to check different-sized owners and
corrected stale documentation that mixed the historical 26-case compiler corpus
with the expanded 40-case library corpus. The final four-lane run passed after
those changes.

Regression scan: 21 callers checked, 18 assertions checked, 2 flagged/fixed.

## Crop/resampling regression review

Reviewed 23 caller contexts across the new image operations, generated Result
pipelines, validation and diagnostics. The 21 reviewed assertion groups include
eleven harness negative controls, four transform-owner outcomes, dimension/count/
pixel comparisons, PPM checks and the stock-filter control. Both CPU/JS and forced
GPU execution prove that rejected transforms retain their original owners.

The review separated contract-test executable paths from example executable
paths so their artifacts cannot overwrite one another. All affected checks passed
after the naming correction. At that point, the default-filter precision mismatch
remained an explicit implementation requirement. The subsequent default RGBA8
resizer closes that dependency without relaxing the comparison.

Regression scan: 23 callers checked, 21 assertions checked, 1 flagged/fixed.

## Default filtered resize regression review

Reviewed the new finite binary64 helpers, kernel generation/folding/packing,
seven-channel filtering, public Result/ownership boundary, fixture validators,
both code generators, oracle reports, mappings and CI consumers. Review found
and fixed three failure classes: approximate power-of-two reconstruction on
Metal, depth-proportional list traversal on JS/device VM, and stale success
evidence when an image probe failed before execution. Fixtures/negative controls
cover the observed boundaries; the full normal and dedicated resize gates pass.

Regression scan: 137 callers checked, 47 assertions checked, 3 flagged/fixed.

The compiler overlay was not edited. Its previous selected regression evidence
remains applicable; the compiler suite was not rerun for this library-only change.

## Image, codec and math expansion regression review

The current review inspected 209 caller contexts across the new library APIs,
QOI state machines, existing raster callers, fixture validators, both generators,
output comparators, examples and diagnostic consumers. It inspected 55 assertion
contexts across Python, transform/decoder contracts and file-error checks.

Five findings were addressed: a private/public name collision in GPU identifier
mangling, Base.File's `r`/`w` mode contract, QOI's absence from the pinned PNG-only
`ExportImageToMemory`, loss of signed zero in generated F32 literals, and
non-string operation names reaching dictionary dispatch. A reference byte fixture
also exercises wrapping QOI encoder deltas. Exact comparisons remain unchanged.

Regression scan: 209 callers checked, 55 assertions checked, 5 flagged/fixed.

The scoped specification audit matches the new public interfaces in [API.md](API.md),
the codec adaptations in [CODECS.md](CODECS.md) and the explicit floating-point
profile in [MATH.md](MATH.md). Source boundaries, pinned revisions, ownership and
exact-comparison invariants hold in the recorded evidence. Hosted validation
remains a publication gap rather than an assumed pass.

The full compiler regression suite and historical manual Metal outlining probe
were not rerun locally; compiler sources remain unchanged. The selected compiler
suite later passed on both hosted runners. CUDA, live window/audio integration
and performance parity remain unrun.

## Alpha bounds, canvas, gradients and metric review

Reviewed 59 caller contexts and 29 assertion contexts: 18 Python harness assertion
sites, five new rejected-input/owner checks, five reference crop-size postconditions
and the deliberately wrong-size negative control. Raw copying is distinct from
alpha blending; empty alpha crops retain the original; unchanged-size canvas
requests remain no-ops. The scoped interfaces and acceptance remain aligned.

Regression scan: 59 callers checked, 29 assertions checked, 0 flagged/fixed.

The full local CPU-1/CPU-2/JS/forced-Metal corpus, ownership/codec contracts and
file examples pass. The compiler and resampler algorithms were not changed in
this batch; their previous focused regression evidence remains applicable.

## Balanced gradient and movement review

Reviewed 92 caller contexts and 25 assertion contexts across gradient partitions,
software trigonometry, vector motion, generator validation, probes and existing
conformance consumers. Native Metal trigonometry's byte mismatch is fixed in the
one-cycle profile. The wider-angle float-libm mismatch is explicitly retained as
an open domain and rejected by the public factory. The exact comparison gate and
the full-range diagnostic remain strict.

Regression scan: 92 callers checked, 25 assertions checked, 2 flagged/fixed.

`PROOF.bend` was executed with the pinned CLI before committing and reported
`All terms check.` The existing clear-dimension law is preserved; it does not
prove the whole numerical/rendering implementation. The new generators expose
balanced independent array partitions, and their reported timings are process
measurements on one machine rather than a blanket performance claim.

The subsequent Ubuntu finding required an explicit numerical reference profile.
The licensed GNU/Arm polynomial passes the independent C model on local CPU/JS/
Metal and actual GNU libm on hosted Ubuntu CPU/JS. The accurate profile retains
its native macOS and forced-Metal evidence. Wider-angle and other-libm contracts
remain open; the passing native-host gate was preserved rather than relaxed.

Follow-up review included the profile selector, all changed callers and both
native-host gates. The final scoped count is:

Regression scan: 108 callers checked, 25 assertions checked, 3 flagged/fixed.

## General rotation, POT and vector follow-up

Reviewed 63 caller contexts and 26 assertion contexts across general rotation,
the existing raw canvas path, scalar helpers, fixture size tracking and result
serialization. General rotation preserves reference bilinear/center behavior
rather than substituting the quarter-turn permutation. Rejected angles and
oversized output retain the original owner. The real C oracle checks all 4096
POT axis inputs before the integer size mapping is used by the fixture tracker.

Regression scan: 63 callers checked, 26 assertions checked, 0 flagged/fixed.

### Signed-zero follow-up

Commit `78f4c6f` passed hosted macOS but failed Ubuntu on two signed-zero cells
in `Vector2Clamp`. `Vector2.clamp_for` now selects the explicit numerical profile;
the convenience wrapper retains the accurate profile. No expected result or
tolerance changed. The full 149-scenario local CPU/JS/Metal gate passes, and
the GNU clamp profile matches all eight retained Ubuntu oracle words on CPU,
JavaScript and forced Metal. See [evidence/clamp-profiles.json](evidence/clamp-profiles.json).

Contract review: I38/I39 match the implementation at `jonlib.bend`'s clamp
entry points and the shared fixture generator. A26 and V2 hold for the exercised
profiles; exceptional/subnormal inputs and untested platforms remain gaps.
The six helper/wrapper/generator calls and four exact vector fixture assertions
were inspected, including the convenience API's profile selection.

Regression scan: 6 callers checked, 4 assertions checked, 0 flagged/fixed.
