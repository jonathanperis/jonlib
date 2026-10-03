# Verification record

Latest additional host check: 2026-10-02, Debian x86-64 / glibc 2.41, Clang
19.1.7 (reference drivers and Bend CPU output), GCC 14.2.0 (CMake's raylib
library compiler), Bun 1.3.12. See the suffix-export, R32 and native-profile records
below; after explicit extrema qualification, aggregate parity on this host
remains blocked by the GNU/Sun versus glibc 2.41 angle scenario.

Latest expansion: 2026-09-29. Host: Apple M1 / macOS 27.0. Bun 1.3.12 and Apple clang 21.0.0.
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

- Eleven harness/planning test methods pass, including changed pixels, empty/missing results,
  invalid fixtures, Boolean/floating-point dimensions masquerading as integers,
  and compiler source/patch tampering or unexpected tracked changes.
- 261 scenarios / 40,101 output words match pinned raylib exactly on each
  of native CPU one-thread, native CPU two-thread, emitted JavaScript, and forced
  Metal with the declared compiler overlay.
- The word count includes 1,878 exact numeric/collision result-bit probe cells.
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
- The pinned core header inventory contains 600 unique public functions; 117 have
  explicitly scoped Jonlib mappings. The raymath ledger additionally maps 142
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
| A1: nonempty, full-pixel differential suite | Pass | 261 scenarios per execution lane; strict comparison |
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

Hosted confirmation for `18a507b`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36217181133)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36217181159)
both completed successfully, including the native gradient and rotation trigonometry gates.

## Collision/channel increment

The six new mappings add rectangle/circle predicates, rectangle overlap,
profiled Vector2 minima/maxima and source-preserving RGBA8 channel extraction.
[Evidence](evidence/collision-channel.json) records full CPU-1/CPU-2/JavaScript/
forced-Metal results. The native oracle checks all 256 values for each of four
channels; the image corpus and ownership contracts verify normalized grayscale
pixels, opaque alpha, original-source retention and independent output ownership.
Geometry results retain strict rectangle edges, inclusive circle tangency,
signed-zero selection and the reference's degenerate-extent behavior.

A26 passes for these scoped contracts; A3/A4/A5/A6/A7 pass the exercised ownership,
source-boundary, forced-device, documentation and negative-control gates.
Full format/numerical/target/performance parity remains a gap.

Reviewed helper/wrapper calls, all color-transform consumers, shared fixture
generation, the resize/Metal diagnostic callers, 32 new differential operations,
three malformed-fixture assertions and the paired-owner contract.

Regression scan: 37 callers checked, 36 assertions checked, 0 flagged/fixed.

Hosted confirmation for `4873d19`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36217794657)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36217794468)
completed successfully.

## Remaining 2D queries and segment contraction

All eleven public 2D collision queries now have scoped mappings. The eight-query
increment adds point, line, triangle and polygon predicates with reference
boundary/degenerate rules and exact optional hit coordinates. The main suite is
163 scenarios / 32,660 words on CPU-1, CPU-2, JavaScript and forced Metal.

The non-dyadic segment fixture exposed a real one-bit mismatch: the pragma in
the generated C caller does not control FP contraction in linked raylib objects.
Disassembly confirmed `fmadd` in the macOS reference. `Collision.lines_for` now
selects explicit fused/uncontracted behavior; the oracle and fixture remain
unchanged. The internal Bend FMA passes 2,056 native-`fmaf` comparisons on CPU,
JavaScript and forced Metal, including cancellation, signed-zero and tiny-addend
double-rounding counterexamples. See [evidence/collision-2d.json](evidence/collision-2d.json).

Scoped drift review: I42/I43 match the collision entry points, explicit arithmetic
selector and `src/fused.bend`; A26/V2 hold for the exercised profiles. C1/C3 hold
through the Bend-only source gate, and A5 passes the forced Metal lane. Other
contracted predicates, exceptional/subnormal domains and full targets/resources/
performance remain gaps. Eight harness tests and the complete pinned proof
verdict pass. No expected output or tolerance was loosened.

Reviewed the collision and fused helpers, shared serializers/validators and
diagnostic callers, 45 differential operations, three invalid fixtures and the
fused-probe assertion. Corrected one documentation statement that no longer
accounted for the explicit fused profile.

Regression scan: 44 callers checked, 49 assertions checked, 1 flagged/fixed.

Hosted confirmation for `1e3a764`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36218678462)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36218678470)
completed successfully, including both hosts' native `fmaf` probes.

## Vector3 and bounded 3D queries

The next batch adds nine Vector3 functions, shared Vector3/BoundingBox type
mappings and two 3D collision predicates. All three components are serialized
and compared bit-for-bit. Fixtures cover cross-product handedness, non-dyadic
products, accumulation order, signed zero, sphere tangency and box separation
on each relevant axis. [Evidence](evidence/vector3-foundation.json) records
168 scenarios / 32,715 words per CPU-1/CPU-2/JavaScript/forced-Metal lane.

A26/A4/A5 pass the scoped numerical/source/backend gates, the eight harness
tests pass, and the pinned proof entry point reports `All terms check.` The
49 constructor/caller contexts include the generalized two/three-component
serializer and its existing diagnostic consumers; 29 differential operations
and two malformed-vector assertions were inspected. Complete 3D integration,
other numerical profiles and full target/performance gates remain gaps.

Regression scan: 49 callers checked, 31 assertions checked, 0 flagged/fixed.

Hosted confirmation for `4730ba7`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36219135235)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36219135257)
completed successfully.

## Vector3 metrics and box/sphere follow-up

Eight further Vector3 functions and `Collision.box_sphere` pass exact native
comparisons in the 171-scenario CPU-1/CPU-2/JavaScript/forced-Metal corpus.
The new normalization fixture preserves all signed-zero components of a zero
Vector3; the existing Vector2 zero contract remains distinct. Division fixtures
validate every F32 divisor, including a third component that underflows to zero.
See [evidence/vector3-metrics.json](evidence/vector3-metrics.json).

A26 passes for the selected component/metric/contact contracts; eight harness
tests, project checks and the complete pinned proof verdict pass. Inspected
eight numerical helper callers, eight vector/collision registry consumers,
17 differential operations and the third-divisor negative control. Other
numerical profiles, remaining integrations and full target/performance gates
remain gaps.

Regression scan: 16 callers checked, 18 assertions checked, 0 flagged/fixed.

Hosted confirmation for `8853f98`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36219429846)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36219429809)
completed successfully.

## Vector3 projection, direction and constraints

Eleven additional Vector3 functions pass exact component/Boolean comparisons
within the 178-scenario CPU-1/CPU-2/JavaScript/forced-Metal corpus. Fixtures retain
projection/rejection arithmetic, cardinal-axis ties, extrapolation, non-unit
reflection normals, negative-step movement, target signed zeros, explicit clamp
profiles, reversed magnitude bounds and total internal reflection. Both an
actually zero target and a target whose squared length underflows to zero are
rejected by the fixture validator before calling the undefined reference path.
See [evidence/vector3-geometry.json](evidence/vector3-geometry.json).

A26 passes these scoped contracts; the eight harness tests, project metadata
checks and complete pinned proof verdict pass. The scan covered 57 numerical/
generator/diagnostic caller contexts, 26 differential operations and two
projection-domain assertions. Undefined/exceptional/subnormal and contracted
domains, other platforms and full performance/resource gates remain gaps.

Regression scan: 57 callers checked, 28 assertions checked, 0 flagged/fixed.

Hosted confirmation for `c5c2f0d`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36219894223)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36219894222)
completed successfully.

## Matrix foundation and paired-vector interpolation

Nine new function mappings cover profiled Vector3 extrema, barycentric and
cubic Hermite interpolation, paired-result orthonormalization, Matrix identity/
transpose and Vector2/Vector3 matrix transforms. The matrix type retains the
reference's row-wise declaration order and column-index field names. The oracle
checks every one of 16 matrix fields, all six orthonormalized-vector components
and every transformed component. No zero-Z term or accumulation step is dropped.
[Evidence](evidence/matrix-foundation.json) records 184 scenarios / 32,909 words
per CPU-1/CPU-2/JavaScript/forced-Metal lane.

The pinned `PROOF.bend` entry point reports `All terms check.` for both clearing
dimension preservation and the new structural transpose-involution law. A26
passes the scoped matrix/vector contracts; A4/A5 pass the source/device gates,
and eight harness tests plus project checks pass. Pointer aliasing, degenerate
barycentric denominators and other numerical/target/performance domains remain
gaps. Existing dedicated resize/trig/fmaf code and inputs are unchanged; hosted
CI additionally runs those independent gates for each published revision.

Reviewed 66 numerical, generator, serializer, proof and diagnostic caller contexts,
20 differential operations, three malformed/domain fixtures and the new law.

Regression scan: 66 callers checked, 24 assertions checked, 0 flagged/fixed.

Hosted confirmation for `5ccf660`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36220733696)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36220733683)
completed successfully.

## Matrix arithmetic, inversion and affine constructors

Eight further matrix functions pass the 189-scenario CPU-1/CPU-2/JavaScript/
forced-Metal gate. Every matrix result field is compared, with explicit reversed
multiplication order, dense products, trace cancellation, singular/negative
determinants, identity/affine/dense/near-singular inverses and signed-zero
constructors. The public Laplace determinant and inversion-minor denominator
retain their separate reference operation orders. See
[evidence/matrix-arithmetic.json](evidence/matrix-arithmetic.json).

The shared `invert` fixture name required a namespace-specific validation fix:
vector reciprocals need nonzero components, while matrices can contain zeros
and instead require a nonzero reference inversion denominator. The valid sparse
inverse fixtures and singular-matrix negative control verify that distinction.
A26/A4/A5 pass the scoped numerical/source/backend contracts; eight harness
tests, project checks and both pinned proofs pass. Singular inverse results,
exceptional/subnormal and contracted profiles, and complete target/performance
coverage remain gaps. Reviewed 16 product-helper calls, 24 harness/diagnostic
caller contexts, 16 differential operations and the new domain assertion.
Scoped drift review: I48 matches the separate determinant/inversion code paths
and namespaced fixture validation; A26/V2 hold for the exercised finite profile.

Regression scan: 40 callers checked, 17 assertions checked, 1 flagged/fixed.

Hosted confirmation for `6d97915`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36221315026)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36221315029)
completed successfully.

## View and rotation matrices

Eight new matrix functions pass all 195 scenarios / 33,554 words on CPU-1,
CPU-2, JavaScript and forced Metal. Matrix rotation fields expose raw cosine
and sine bits directly: fixtures cover signed zero, adjacent π/4 values,
quadrants/full cycles, distinct Euler formulas and non-unit/zero axes. Look-at
fixtures retain coincident eye/target and parallel-up behavior. The zero-axis
rotation matches the reference cosine diagonal rather than substituting identity.
See [evidence/matrix-view-rotation.json](evidence/matrix-view-rotation.json).

The rotation validator now distinguishes Vector2's third argument from the
matrix axis-angle operation's fourth argument. A large valid axis component
and two invalid-angle fixtures verify that only the actual angles receive the
one-cycle bound. A26/A4/A5 pass the scoped numerical/source/backend gates;
eight harness tests, project checks and both pinned proofs pass. Wider angles,
other numerical/libm profiles and full target/performance gates remain gaps.
The existing trigonometric implementation is reused without changing reference
outputs or comparison tolerances.

Reviewed 71 numerical/helper/wrapper/generator/diagnostic caller contexts,
29 differential matrix operations and two malformed-angle assertions.

Regression scan: 71 callers checked, 31 assertions checked, 1 flagged/fixed.

Hosted confirmation for `91e76b9`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36222199916)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36222199907)
completed successfully, including the new raw matrix-trigonometry fields.

## Float exports and Vector4 foundation

The Vector3/Matrix float exports and six Vector4 operations pass 198 scenarios /
33,605 words per CPU-1/CPU-2/JavaScript/forced-Metal lane. Export fixtures compare
XYZ order and numeric matrix field order `m0..m15`, while the verification writer
rejects both short and overlong lists. Vector4 fixtures compare every component,
including W and signed-zero products. See
[evidence/float-exports-vector4.json](evidence/float-exports-vector4.json).

Two new structural laws establish the exact export lengths. The complete pinned
proof verdict reports `All terms check.` for all four laws. A26/A4/A5 pass the
scoped data/source/backend contracts, and eight harness tests plus project checks
pass. Native contiguous-array ABI/mutability, exceptional/subnormal domains and
full integration/target/performance evidence remain gaps. Reviewed 47 constructor,
proof, generator and diagnostic caller contexts, ten differential operations,
two output-bound assertions and the two new laws.

Regression scan: 47 callers checked, 14 assertions checked, 0 flagged/fixed.

Hosted confirmation for `8809f19`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36223156675)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36223156701)
completed successfully.

## Remaining Vector4 arithmetic and metrics

All 22 pinned Vector4 functions now have scoped mappings. Sixteen new functions
pass the 203-scenario CPU-1/CPU-2/JavaScript/forced-Metal corpus, including exact
four-term accumulation, W-only distances/equality, positive-zero normalization,
profiled extrema, extrapolation, negative movement and exact signed-zero target
snapping. [Evidence](evidence/vector4-metrics.json) records all 33,677 words per
lane. Fourth-component zero/underflow divisors are rejected before reference calls.

A26/A4/A5 pass the scoped numerical/source/backend contracts; eight harness
tests, project checks and all four pinned laws pass. The scoped specification
review aligns the numerical acceptance wording with the implemented vector and
matrix families; I51 matches the distinct Vector4 zero-normalization behavior.
Exceptional/subnormal and contracted domains plus complete integration/target/
performance evidence remain gaps. Reviewed 51 numerical/registry/generator/
diagnostic caller contexts, 27 differential operations and two divisor controls.

Regression scan: 51 callers checked, 29 assertions checked, 0 flagged/fixed.

Hosted confirmation for `7696141`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36224050657)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36224050665)
completed successfully.

## Normalized/HSV colors and quaternion foundation

Four core color functions and four quaternion functions pass 208 scenarios /
33,761 words per CPU-1/CPU-2/JavaScript/forced-Metal lane. The linked raylib oracle
checks normalized/HSV float bits, channel/sector boundaries, hidden RGB under
zero alpha, opaque HSV output and byte truncation. The bounded HSV remainder
uses at most one exact subtraction. Inspection of the linked macOS implementation
confirmed separate multiply/subtract instructions; reference flags were not changed.
Quaternion values share Vector4 representation, while Hamilton multiplication
retains its noncommuting reference order. See
[evidence/colors-quaternion-foundation.json](evidence/colors-quaternion-foundation.json).

A26/A4/A5 pass the scoped numerical/source/backend contracts; eight harness
tests, project checks and all four pinned laws pass. Wider hue/numerical domains,
remaining quaternion operations and complete ABI/integration/target/performance
evidence remain gaps. Reviewed 37 helper, byte-conversion, registry, serializer
and diagnostic caller contexts, 36 differential operations and four malformed
color-domain assertions. Packed color results remain ordinary RGBA output words;
only actual float/Boolean results contribute to the numeric-probe count.

Regression scan: 37 callers checked, 40 assertions checked, 0 flagged/fixed.

Hosted confirmation for `478460e`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36225344756)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36225344626)
completed successfully.

## Quaternion metrics, inversion and interpolation

Ten further quaternion functions pass 212 scenarios / 33,818 words on CPU-1,
CPU-2, JavaScript and forced Metal. The fixtures check zero quaternion signs,
identity/non-unit inversion, component division, extrapolation, antipodal NLERP
collapse and all-component `q`/`-q` epsilon equivalence. Quaternion zero behavior
is retained explicitly instead of reusing Vector4's positive-zero normalization.
See [evidence/quaternion-metrics.json](evidence/quaternion-metrics.json).

The inverse fixture guard is restricted to actual vector reciprocals, permitting
identity and zero quaternion inversion while component quaternion division still
rejects zero divisors. A26/A4/A5 pass the scoped numerical/source/backend gates;
eight harness tests, project checks and all four pinned laws pass. Exceptional/
subnormal and contracted domains, remaining operations and full target/integration/
performance gates remain gaps. Reviewed 43 helper/registry/generator/diagnostic
caller contexts, 18 differential operations and one division-domain assertion.

Regression scan: 43 callers checked, 19 assertions checked, 1 flagged/fixed.

Hosted confirmation for `eaa2f5f`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36226323577)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36226323548)
completed successfully.

## Quaternion/matrix conversions and composition

Five further functions pass 217 scenarios / 33,959 words per CPU-1/CPU-2/
JavaScript/forced-Metal lane. Fixtures cover all largest-component winners,
strict ties, nonsymmetric matrices, projective fourth-row transforms, non-unit
and zero quaternions, and scale-before-rotation composition with signed zero.
The direct reference formulas remain separate: zero-quaternion `to_matrix`
returns identity while `compose` produces a zero basis. See
[evidence/quaternion-matrix-conversions.json](evidence/quaternion-matrix-conversions.json).

Matrix output size and C type now come from the declared result shape, independently
of the quaternion input family's four components. A short-output negative control
prevents silently comparing only four fields of `QuaternionToMatrix`. Scoped
review confirms I55's input/output distinction and A26/V2's complete exact-bit
comparison. A4/A5, eight harness tests, project checks and all four pinned laws
pass. Other numerical/ABI/integration/target/performance domains remain gaps.
Reviewed 36 helper, registry, serializer and diagnostic caller contexts,
18 differential operations and one result-shape assertion.

Regression scan: 36 callers checked, 19 assertions checked, 1 flagged/fixed.

Hosted confirmation for `ac7589c`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36227536158)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36227536166)
completed successfully.

## Decomposition, 3D constructors and unprojection

Seven new functions pass 224 scenarios / 34,111 words per CPU-1/CPU-2/JavaScript/
forced-Metal lane. Decomposition compares all ten outputs across reflection,
shear, tiny matrices, zero matrices and adjacent 1e-9 guard values. Quaternion
and axis constructors retain zero/opposite-vector behavior and half-angle order;
the cubic Hermite result uses reference quaternion normalization. Unprojection
preserves both transposed intermediate initializers rather than replacing them
with a differently rounded inverse. See
[evidence/decomposition-unprojection.json](evidence/decomposition-unprojection.json).

The actual native oracle checks inverse, homogeneous and result finiteness plus
nonzero W. Two additional generated reference programs must fail with the
expected invalid-domain exit for singular and zero-W inputs. No output is skipped
or accepted under a widened tolerance. A26/A4/A5 pass the scoped contracts;
eight harness tests, project checks and all four pinned laws pass. I56/I57 match
the ten-field result, bounded angle selectors and inverse ordering. Pointer
aliasing, wider angles, unsupported numerical domains and complete target/
integration/performance coverage remain gaps. Reviewed 58 helper/profile/
generator/oracle/diagnostic caller contexts, 29 differential operations, two
malformed fixtures and two native invalid-domain controls.

Regression scan: 58 callers checked, 33 assertions checked, 0 flagged/fixed.

Hosted confirmation for `10e27b9`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36229933755)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36229933753)
completed successfully.

## Binary64 inputs for frustum and orthographic matrices

The new Float64 carrier preserves both IEEE words through projection interval
subtraction. Native C arguments use exact hexadecimal double literals; candidate
arguments use the matching word pairs. Fixtures include 16777216/16777217 bounds,
one-double-ULP spans near 0.1, large translated intervals, signed zero, finite F32
promotion extremes/subnormals and normal narrowing ties. All 228 scenarios /
34,271 words pass on CPU-1, CPU-2, JavaScript and forced Metal. See
[evidence/binary64-projections.json](evidence/binary64-projections.json).

Projection validation requires supported normal/zero casts/intermediates and
nonzero spans; the native matrix-result gate rejects non-finite or subnormal
outputs. A generated subnormal-result oracle control fails with the expected
exit, and both existing unprojection controls still fail closed after sharing
the native-control runner. A26/A4/A5, eight harness tests, project checks and all
four pinned laws pass. I58 retains original input precision without changing the
compiler or shared resize arithmetic. Exceptional/subnormal projection arithmetic,
unverified non-finite promotion payloads and complete integration/target/performance
coverage remain gaps. Reviewed 67 helper, codec, validator, generator and diagnostic
caller contexts, 28 differential operations, five malformed/domain fixtures and
three native invalid-domain controls.

Regression scan: 67 callers checked, 36 assertions checked, 0 flagged/fixed.

Hosted confirmation for `b15779e`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36232241255)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36232241293)
completed successfully.

## Perspective rounding investigation

The new diagnostic executes actual native `MatrixPerspective` and retains a
counterexample where a one-ULP binary64 tangent difference changes m5 by two F32
steps. A published Sun/FreeBSD kernel control also fails to match the current
macOS implementation under off/on/fast contraction settings. The API remains
blocked and contributes no implemented mapping. Exact inputs, outputs, sources
and reproduction commands are in [PERSPECTIVE.md](PERSPECTIVE.md) and
[evidence/perspective-rounding-blocker.json](evidence/perspective-rounding-blocker.json).

The diagnostic completes and records the mismatch; it is explicitly separate
from a passing candidate gate. Hosted CI will retain per-host evidence. Eight
harness tests and project checks pass. The unchanged 228-scenario library corpus
and four proofs reuse the prior current-source evidence. A26 remains a gap for
MatrixPerspective, with the established implemented profiles still passing.
The CLI entry point, numerical evaluator, workflow invocation and documented
command were inspected, together with the retained result comparison.

Regression scan: 4 callers checked, 1 assertions checked, 0 flagged/fixed.

Hosted confirmation for `c223135`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36233833593)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36233833564)
completed successfully, including the explicitly diagnostic perspective record.

## Vector angle numerical profiles

The pinned Base atan2 primitive differed from native macOS on 14/128 CPU/JS and
68/128 forced-Metal inputs. Independent Bend evaluation of the documented Apple
mathematical profile and a permitted Sun float-kernel adaptation now support
Vector2 angle/line-angle and Vector3 angle with explicit reference selection.
The Apple profile retains π rounded toward zero near the negative X axis.
[Evidence](evidence/vector-angle-profiles.json) records the 231-scenario corpus,
1,086 exact angle probes per profile/lane, and 512 native-bit binary64 arithmetic
operations per lane. GNU local evidence uses the independent Sun control; hosted
Ubuntu checks the actual native GNU function.

Probe execution uses bounded runtime batches and one compilation per lane. This
addresses the initial device-stack failure of an oversized result batch and the
cost of compiling each small batch independently. A subnormal-angle native control
fails closed. A26/A4/A5, eight harness tests, project checks and all four pinned laws
pass; other numerical/libm/target/performance domains remain gaps. The compiler and
existing library comparisons retain their declared boundaries and exact values.
Reviewed 85 arithmetic/profile/wrapper/generator/diagnostic caller contexts,
19 differential angle operations, the native invalid-result control and two
independent probe comparisons.

Regression scan: 85 callers checked, 22 assertions checked, 1 flagged/fixed.

### Hosted angle dispatch follow-up

`bafb5b8` failed hosted angle comparisons at π on macOS and a near-π/2 input on
Ubuntu. The retained outputs are `40490fdb` versus the Apple-profile `40490fda`,
and `3fc90fdb` versus the Sun-control `3fc90fda`, respectively. These failures
remain evidence; the local results above are scoped to their recorded host.

The reference compilation now explicitly inhibits builtin `atan2f` folding;
the dedicated probe uses a volatile native pointer and records literal/native
endpoint results plus host/compiler metadata. Native probes run before the full
hosted corpus, and conformance metadata is persisted before the first comparison.
The original inputs, raymath header and exact-bit comparator are retained.
Local full CPU-1/CPU-2/JS/Metal conformance and the 1,086 native angle probes pass;
hosted native-profile confirmation remains pending for this follow-up.

Regression scan: 8 callers checked, 4 assertions checked, 1 flagged/fixed.

The next hosted run, `9f3ac95`, confirmed the dispatch distinction: Apple clang 17
folded literal π to `40490fdb` while the actual native function returned
`40490fda`; Ubuntu clang 18 folded the near-π/2 input to `3fc90fdb` while native
glibc 2.39 returned `3fc90fda`. Both native angle probes passed, and Ubuntu's full
conformance passed. macOS's remaining failure was the existing 240-second limit
on its monolithic candidate build, not a numeric mismatch. Exact artifact values
are retained in [evidence/angle-native-dispatch.json](evidence/angle-native-dispatch.json).

Candidate compilation now uses the established 64-case batching approach, with
all ordered outputs concatenated before the unchanged complete-corpus comparison.
Local batches of 64/64/64/39 scenarios compiled their CPU/JS runners in
28.178/4.512/5.739/3.556 seconds, respectively. All 231 scenarios / 34,290 words
still pass on CPU-1/CPU-2/JavaScript/forced Metal; eight harness tests and project
checks pass. No command timeout, scenario, expected value or tolerance was relaxed.

Regression scan: 12 callers checked, 4 assertions checked, 1 flagged/fixed.

Hosted confirmation for `7a09b91`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36239017971)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36239017967)
completed successfully. This closes the native-dispatch/build-scaling follow-up.

## Remaining inverse-trig dependencies

The native inverse-trig diagnostic retains 286 unique F32 inputs and 572 result
words. Base primitives differ in ten CPU/JavaScript words and 286 forced-Metal
words, including endpoint rounding and negative-zero preservation. Investigated
legacy mathematical models and endpoint-adjusted double functions also retain
mismatches. `QuaternionSlerp`, `QuaternionToAxisAngle` and `QuaternionToEuler`
remain explicitly blocked, with no implementation count added. See
[INVERSE-TRIG.md](INVERSE-TRIG.md) and
[evidence/inverse-trig-blocker.json](evidence/inverse-trig-blocker.json).

The diagnostic completed on CPU/JS/Metal; its mismatch record is not a parity
pass. The unchanged library/proof corpus reuses its passing current-source
evidence. Harness tests and project checks pass. Reviewed the diagnostic entry
point, lane generator, native pointer calls and workflow/artifact consumers.

Regression scan: 6 callers checked, 2 assertions checked, 0 flagged/fixed.

`2550b35` passed Ubuntu but a later macOS runner again exceeded 240 seconds on
the unchanged first 64-case candidate build. Candidate compilation now has an
explicit bounded 600-second budget recorded in the report; execution retains
the 240-second default. Batching, scenarios and exact comparisons are retained.
This allowance addresses observed compiler-resource variability and establishes
no performance-parity claim. The current-source runtime/proof evidence is reused;
eight harness tests and project checks pass for the scoped timeout change.

Regression scan: 3 callers checked, 0 assertions checked, 1 flagged/fixed.

Hosted confirmation for `092cb0a`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36241027496)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36241027497)
completed successfully with the separate candidate-build budget.

## Owned random streams and white noise

Pinned rprand seeding/stepping is now implemented in Bend with an owned stream.
The dedicated probe compares 960 native random values across six seeds and three
post-noise stream observations on CPU, JavaScript and forced Metal. The main
corpus passes 236 scenarios / 34,353 words on CPU-1/CPU-2/JavaScript/forced Metal,
including every white-noise pixel. Rejected dimensions/factors preserve the
original stream, while constant ranges and density endpoints still consume the
reference draws. See [evidence/random-white-noise.json](evidence/random-white-noise.json).

A26/A3/A4/A5 pass the scoped state/image/source/backend contracts; eight harness
tests, project checks and all four pinned laws pass. The reference configuration
explicitly enables rprand. Implicit globals, libc fallback, wider ranges, sequence
APIs and complete integration/target/performance coverage remain gaps. Reviewed
44 helper, owner, fixture, generator and diagnostic caller contexts, five image
scenarios, two rejected-owner checks, two malformed sources and the stream probe.

Regression scan: 44 callers checked, 10 assertions checked, 0 flagged/fixed.

Hosted confirmation for `3a97be5`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36242292011)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36242292009)
completed successfully.

## Owned unique random sequences

Seven complete sequence/following-stream results match actual `LoadRandomSequence`
on CPU, JavaScript and forced Metal, alongside the existing 960 random draws and
three post-noise observations. The sequence reference retains reversed endpoints
without swapping, unlike `GetRandomValue`. Duplicate rejection, exact acceptance
order, empty requests and excessive counts are covered. Four ownership controls
check invalid endpoints/counts, explicit draw exhaustion and empty disposal.
[Evidence](evidence/random-sequences.json) records the source and probe inputs.

The draw budget is explicit because safe Bend recursion must structurally descend.
Exhaustion returns an incomplete ordered sequence and the stream after consumed
draws; it does not report a successful native sequence. All 236 image/numeric
scenarios still pass CPU-1/CPU-2/JavaScript/forced Metal, eight harness tests pass,
and the pinned proof verdict is `All terms check.` A26/A3/A4/A5 hold for the scoped
sequence/state/source/backend contracts. I67 matches `Random.load_sequence` and
the `SequenceDrawLimit` owner path. Native unbounded retries, global state,
allocator/null correspondence and complete target/performance evidence remain gaps.

Regression scan: 16 callers checked, 11 assertions checked, 0 flagged/fixed.

Hosted confirmation for `85066d4`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36243383436)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36243383429)
completed successfully.

## Cellular image generation

`Surface.create_cellular` passes all six new image fixtures and the complete
242-scenario / 39,623-word CPU-1/CPU-2/JavaScript/forced-Metal corpus. The native
preflight checks 13,180,825 coordinate-difference pairs against actual `hypot`;
the candidate caps the minimum integer square at tile size squared before one
square root and the original F32 quantization. Fixtures cover floor-sized grids,
partial edge tiles, saturation, unit tiles, empty seed grids and the maximum
tile size. Three additional native post-cellular stream observations and two
rejected-owner controls pass. See [evidence/cellular-generation.json](evidence/cellular-generation.json).

A26/A3/A4/A5 pass the scoped pixel/state/bounds/source/backend contracts. Eight
harness tests, project checks and all four pinned laws pass. I68 matches the
1..4096 size/tile domain, seed order and capped-distance reduction. Implicit
globals/libc random variants, broader size domains and complete target/resource/
performance coverage remain gaps.

Regression scan: 38 callers checked, 14 assertions checked, 0 flagged/fixed.

Hosted confirmation for `411398b`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36244010118)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36244010066)
completed successfully, including the exhaustive cellular-distance gate.

## Profiled Perlin image generation

The linked native `GenImagePerlinNoise` matches all seven new fixtures in the
249-scenario / 40,024-word CPU-1/CPU-2/JavaScript/forced-Metal corpus. The new
module preserves the pinned MIT-licensed stb tables, octave seeds, aspect
compensation and intensity arithmetic. Inspection of the actual Apple arm64
reference confirmed fused easing/interpolation/accumulation; explicit
`Noise.Reference` variants retain that difference. The convenience API uses the
uncontracted variant. [Evidence](evidence/perlin-generation.json) records both
profiles passing all 1,024 table cells and 222 raw octave results on CPU/JS/Metal.

A26/A4/A5 pass the scoped pixel/source/backend contracts. Eight harness tests,
project checks and all four pinned laws pass. I69 matches the declared domains,
rejection behavior and arithmetic selection. The unchanged numeric/resize/trig
dependencies reuse their passing evidence; the new raw-octave probe independently
checks their relevant FMA composition. Broader numerical/size domains, other
compiler contraction patterns and full target/resource/performance coverage
remain gaps. The original tables and expected output pixels are retained.

Regression scan: 71 callers checked, 14 assertions checked, 0 flagged/fixed.

Hosted confirmation for `18f113e`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36244858413)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36244858336)
completed successfully, including the new table/octave gate.

## Text-byte images, grayscale and palettes

Four additional core mappings pass 258 scenarios / 40,069 words per CPU-1/CPU-2/
JavaScript/forced-Metal lane. The native luminance gate verifies every RGB byte
triple (16,777,216 combinations). Nine new fixtures cover text truncation/NUL/
padding, grayscale alpha discard and five complete palette observations. Palette
count, all capacity entries including padding, and original image pixels are
compared. The combined alpha-border/QOI/palette fixture verifies serialization
and ownership across simultaneous observations. See
[evidence/text-grayscale-palettes.json](evidence/text-grayscale-palettes.json).

A26/A3/A4/A5 pass the scoped byte/pixel/palette/ownership/source/backend contracts.
Eight harness tests, project checks and all four pinned laws pass. I70/I71 match
the declared byte-list and RGBA8-normalized profiles, capacity rejection and
owned disposal. Native storage/pointer/allocator correspondence, other image
formats/mipmaps and complete target/resource/performance coverage remain gaps.

Regression scan: 71 callers checked, 20 assertions checked, 0 flagged/fixed.

Hosted confirmation for `d034501`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36245932944)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36245932900)
completed successfully, including the exhaustive grayscale gate and palette observations.

## Spline-point profiles

Four point-query APIs pass the 261-scenario / 40,101-word CPU-1/CPU-2/JavaScript/
forced-Metal corpus. The linked Apple reference and independent uncontracted
source control each pass 512 complete points on CPU/JS/Metal. Original weighted
products, B-spline divisions/Horner order, Catmull-Rom coefficients and quadratic
Bezier weights are retained. Explicit `Spline.Reference` variants select the
arithmetic, with uncontracted convenience wrappers. See
[evidence/spline-points.json](evidence/spline-points.json).

The fifth queued API, cubic Bezier, remains blocked: actual native `powf(t,3)`
differs from a double-cube substitute on 6,670/1,048,576 investigated inputs, and
the retained t value changes an actual `GetSplinePointBezierCubic` X coordinate.
No implementation is counted for that entry. A26/A4/A5 pass the four implemented
profiles; eight harness tests, project checks and all four pinned laws pass.
I72 matches the coefficient order and explicit numerical limits. Other contraction,
exceptional/subnormal/extrapolation domains and full target/performance coverage
remain gaps.

Regression scan: 61 callers checked, 20 assertions checked, 0 flagged/fixed.

Hosted confirmation for `5c2b6a8`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36247485444)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36247485460)
completed successfully, including the new linked spline-point gate.

## Pixel sizing and raw dithering

The dedicated pixel probe passes 4,563 all-format size results and 42 complete
dithered images (406 packed words) on CPU, JavaScript and forced Metal. Exact
metadata includes known 16-bit formats and format zero for custom layouts.
Sizing retains the unusual both-small-axes minimums, zero dimensions and the
ASTC 8×8 exception. Dithering retains row-order diffusion, truncation, saturation
and undiffused alpha. [Evidence](evidence/pixel-sizing-dither.json) records the
inputs and source hashes. No RGBA conversion hides raw packing or format details.

The unchanged 261-scenario image/numeric corpus still passes every CPU-1/CPU-2/
JavaScript/forced-Metal word. Four new contracts verify rejected dither owners
and out-of-profile size requests. A26/A3/A4/A5, eight harness tests, project checks
and all four pinned laws pass. I73/I74 match the bounded sizing and owned raw
format contracts. Wider/signed size domains, other input formats/mipmaps, native
allocation ABI and complete target/resource/performance evidence remain gaps.

Regression scan: 23 callers checked, 6 assertions checked, 0 flagged/fixed.

Hosted confirmation for `9cf17d4`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36249122243)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36249122346)
completed successfully, including the new raw dithering and size gate.

## Raw byte/integer pixel access

Both byte-list APIs pass 262,144 exhaustive two-byte reads and 1,792 complete
write/readback buffers on CPU, JavaScript and forced Metal. Native grayscale
writes match all 16,777,216 RGB triples, and all 768 packed-channel quantizers
match the integer reduction. Six typed-failure contracts and the full existing
261-scenario / 40,101-word corpus pass all four execution lanes. Eight harness
tests, project checks and all four pinned laws also pass. See
[evidence/raw-pixel-access.json](evidence/raw-pixel-access.json).

The exhaustive read gate caught the native RGB5A1 quirk: `GetPixelColor` does not
shift alpha out of its blue mask, so word 0x0001 returns RGBA 0x000008ff. The
candidate now preserves that API-specific rule. I75/I76 match the byte-validation,
prefix-write and mask contracts; A26/A4/A5 pass in the little-endian formats-1..7
profile. Other formats, configured thresholds, native pointer mutation/ABI and
complete integration/target/performance coverage remain gaps. The reference and
expected values were retained throughout the correction.

Regression scan: 38 callers checked, 10 assertions checked, 1 flagged/fixed.

### Hosted candidate-build isolation

`f5d6c73` passed Ubuntu, including raw pixel access, but macOS 15 exceeded the
600-second CLI build budget on its first 64-case candidate. The retained failure
was a compilation timeout, not a numerical mismatch. Generated local C grew to
2,265,210 bytes for that batch, versus 515,842 bytes for the 16-case prefix.
[Evidence](evidence/candidate-build-isolation.json) records the measurements.

The deterministic batch bound is now 16. Each batch first emits its C artifact,
then builds through the unchanged pinned CLI; reports persist emit/CPU-JS/GPU/
complete phases and timings before each stage. CI retains the generated C for
subsequent diagnosis. Compiler flags and the 600-second budget are unchanged.
All 261 ordered cases / 40,101 words still pass CPU-1/CPU-2/JavaScript/forced Metal
over 17 contiguous batches. Eight harness tests and project checks pass; unchanged
library/proof evidence is reused. Hosted follow-up confirmation remains pending.

Regression scan: 7 callers checked, 4 assertions checked, 1 flagged/fixed.

Hosted confirmation for `77b9ab7`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36253357894)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36253357944)
completed successfully with the smaller measured candidate batches.

## Owned image-format conversion

`Image.Formatted` supports all seven byte/integer formats with checked byte
construction, native-order export, in-place owned conversion and RGBA8 Surface
bridges. The dedicated probe passes every one of 49 format pairs, no-op requests,
chain prefixes and bridges: 109 complete results / 3,192 native bytes on CPU,
JavaScript and forced Metal. The normalized F32 path retains reciprocal expansion
and avoids routing through raw `GetPixelColor`, whose RGB5A1 blue behavior differs.
See [evidence/image-format-conversion.json](evidence/image-format-conversion.json).

The full 261-scenario / 40,101-word corpus still passes all four lanes. Seven
new contracts check invalid sizes/formats/byte counts/byte values, retained owners
and the Surface round trip. A26/A3/A4/A5, eight harness tests, project checks and
all four pinned laws pass. I78 matches the single-mip, little-endian byte/integer
profile. Float/half/compressed formats, mipmaps, other thresholds/endianness,
native allocation ABI and full integration/target/resource/performance coverage
remain gaps.

Regression scan: 52 callers checked, 9 assertions checked, 0 flagged/fixed.

### Angle branch compilation footprint

`72faf74` passed Ubuntu, including image-format conversion. macOS reached the
20-minute job limit: staged artifacts showed 217.175 seconds spent emitting C
for the second batch before its native/JS build. A local CPU profile identified
Bend's literal-word matcher key construction and term traversal as the dominant
cost, with an 11.28 GB peak footprint. This was not solely Clang optimization.

The private Apple/GNU axis helpers now match equivalent Boolean classifications
instead of nested literal U32 zero patterns. Public signatures and all numerical
choices are retained. On the same generated Bend input, profiled C emission fell
from 43.80 to 2.31 seconds and peak footprint from 11.28 to 1.14 GB. Both 1,086-case
angle probes pass CPU/JS/forced Metal, and all 261 scenarios / 40,101 words still
match on CPU-1/CPU-2/JavaScript/forced Metal. The full local run took 235.792 seconds.
[Evidence](evidence/angle-branch-compilation.json) records scope and source hash.

Eight harness tests, project checks and all four pinned proofs pass. The pinned
compiler, build flags and job/command budgets are unchanged. I79 matches the
measured source-level correction; A26/V2 retain exact native/control results.
Hosted follow-up confirmation remains pending, and no runtime performance-parity
claim follows from these compile-resource measurements.

Regression scan: 8 callers checked, 5 assertions checked, 1 flagged/fixed.

Hosted confirmation for `2ec4131`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36259006133)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36259006097)
completed successfully after the private angle branch rewrite.

## Raw image-file boundaries

The raw-file probe passes 25 native load/export cases, a native export failure,
five typed boundary controls and 100 low-descriptor closure iterations on both
CPU and JavaScript. Native tests cover all seven byte/integer formats, exact-fit
headers, non-fitting headers, the largest permitted header, ignored file tails
and missing/empty/truncated inputs. Each successful candidate export is compared
byte-for-byte with actual raylib `ExportImage`. Metadata is checked before the
round trip to prevent a compensating loader/exporter error from hiding it.
See [evidence/raw-image-files.json](evidence/raw-image-files.json).

The loader uses bounded positional reads and closes opened handles on every
observed outcome. Unsupported requests are rejected before opening; the native
header-does-not-fit behavior is preserved as an explicit selection of offset zero.
The shared byte producer now supports the output quantities required by Base IO;
all 109 format-pair/chain/bridge results and the full 261-scenario / 40,101-word
CPU-1/CPU-2/JavaScript/forced-Metal corpus still pass. Eight harness tests, project
checks and all four pinned laws pass. A26/A28 and I80 hold for the declared raw
file profile. GPU filesystem IO, other formats/parameters, concurrent/special-file
semantics, native callbacks/allocation ABI and full target/performance coverage
remain gaps.

Regression scan: 30 callers checked, 11 assertions checked, 1 flagged/fixed.

Hosted confirmation for `8ec0a18`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36261897675)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36261897667)
completed successfully, including raw-file bytes and descriptor-closure checks.

## BMP memory codec and RGBA8 export

The bounded INFO/V4 24/32-bit decoder passes 24 native images (131 complete
pixels), 17 typed-error controls and three byte-exact RGBA8 V4 exports (410 bytes)
on CPU, JavaScript and forced Metal. CPU/JS additionally write a real file and
compare every byte with native `ExportImage`. Row orientation/padding, native
all-zero-alpha promotion, explicit bitfield alpha and the observed double-skip
post-header gap are retained. The maximum-gap fixture is built from bounded
literal chunks after a deeply nested generated JavaScript literal exceeded its
stack; the fixture bytes and native expectations are unchanged. See
[evidence/bmp-codec.json](evidence/bmp-codec.json).

The full 261-scenario / 40,101-word corpus, eight harness tests, project checks
and all four pinned laws pass. I81 and A4/A5/A6 pass within the declared profile.
The two existing partial mappings (`LoadImageFromMemory`, `ExportImage`) gain
BMP coverage; the ledger remains 102 core and 142 raymath partial functions,
with zero full-parity completions. Other BMP variants, original-format metadata,
permissive malformed-input recovery and full target/resource/performance evidence
remain gaps. The selected stb MIT notice is retained with the adaptation.

Regression scan: 35 callers checked, 21 assertions checked, 1 flagged/fixed.

Hosted confirmation for `b15af4b`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36263721767)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36263721856)
completed successfully, including BMP decode and exact export bytes.

## TGA raw/RLE decoding and export

The true-color/grayscale decoder passes 19 native images (358 pixels), 14 typed
errors and 11 complete default RLE exports (3,447 bytes) on CPU, JavaScript and
forced Metal. Export fixtures retain the native two-position raw-run comparison,
128/129/130-pixel boundaries and per-row packet restart. Decode fixtures cover
ID fields, both vertical orientations, ignored descriptor/origin fields,
gray-alpha values and packets spanning row boundaries. Real CPU/JS files match
native bytes. See [evidence/tga-codec.json](evidence/tga-codec.json).

The shared bitmap harness also reruns the complete BMP profile successfully.
The 261-scenario / 40,101-word full corpus, eight harness tests, project checks
and four pinned laws pass. I82 and A4/A5/A6 pass within the declared profile.
The existing partial load/export mappings gain another codec; complete API
counts do not increase. Paletted/15-bit/16-bit true-color variants, original
metadata, nondefault export flags, malformed-data recovery and full target/
resource/performance evidence remain gaps.

Regression scan: 39 callers checked, 35 assertions checked, 0 flagged/fixed.

Hosted confirmation for `a8efe9e`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36264484902)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36264484915)
completed successfully, including exact native TGA RLE exports.

## Binary PGM/PPM decoding

The P5/P6 byte-sample decoder passes 21 native images / 8,294 pixels and 13
typed-error controls on CPU, JavaScript and forced Metal. Native comparisons
retain unscaled samples for maxval below 255, comments/whitespace between fields,
exactly one consumed maxval separator, and 4096×1/1×4096 dimension boundaries.
The reference is dispatched through raylib's supported `.ppm` extension; it
detects both P5 and P6 magic. See [evidence/pnm-codec.json](evidence/pnm-codec.json).

The shared bitmap gate now supports decode-only profiles. Both complete BMP/TGA
decode/export suites pass again, as do the 261-scenario / 40,101-word full corpus,
eight harness tests, project checks and all four pinned laws. I83 and A4/A5/A6
pass within the declared 8-bit profile. The existing partial memory-loader mapping
gains PNM coverage; 16-bit PNM, original-format metadata, permissive malformed
header recovery and full target/resource/performance evidence remain gaps.

Regression scan: 30 callers checked, 48 assertions checked, 0 flagged/fixed.

Hosted confirmation for `78ea12b`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36265201324)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36265201350)
completed successfully, including binary PGM/PPM boundaries.

## Raw DEFLATE and PNG-oriented dependency

The bounded decoder passes 24 streams against actual `DecompressData` and linked
stb raw inflation on CPU, JavaScript and forced Metal. Full outputs total 122,651
bytes for the public native profile and 125,651 for the PNG-oriented path.
The difference is retained explicitly: a non-final empty stored block terminates
native `DecompressData` after 300 bytes, while stb and zlib return the full 3,300.
Stored/fixed/dynamic blocks, all three code-length repeat commands, literal-only
trees without distance codes, exact distance 32,768, overlap, multiple blocks
and the 1-MiB compressed-input boundary are covered. Sixteen invalid/limit controls
pass for both paths. See [evidence/raw-deflate.json](evidence/raw-deflate.json).

Forced Metal exposed stack growth when exporting a larger output through generic
list prefix extraction. Tail-recursive owned-array extraction fixes that failure;
all original streams and native expected bytes are retained. The full 261-scenario
/ 40,101-word corpus, eight harness tests, project checks and four pinned laws pass.
The scoped drift review confirms I84, C3/C6, A4/A5/A6 and V2/V3 for the exercised
profile. The ledger gains one partial `DecompressData` mapping, reaching 103 core
and 142 raymath partial functions. No API has passed every full-parity gate.

Zlib/gzip framing, PNG chunk/filter integration, larger inputs, other native
malformed/partial-output recovery, allocation ABI and full target/resource/
performance evidence remain gaps.

Regression scan: 61 callers checked, 21 assertions checked, 2 flagged/fixed.

### Hosted DEFLATE result serialization

`12f507c` passed [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36267191527)
and the macOS conformance job. Ubuntu's native DEFLATE lane passed, but its
JavaScript lane overflowed while formatting the larger byte lists. The emitted
JavaScript showed non-tail recursive calls in generic `List.show.go`, matching
the failure after the smaller results had been emitted.

The probe now groups bytes through a tail-recursive traversal and formats at
most 256 per chunk. An explicit end marker separates successful results, including
empty output; null retains failed-result meaning. The parser validates framing
and byte ranges, then compares the same complete ordered arrays with the original
native expectations. All 24 streams / 16 controls still pass CPU/JS/forced Metal,
and nine harness tests pass. Decoder sources, fixtures, native hashes and compiler
settings are unchanged; existing full-corpus/proof evidence remains applicable.
[Evidence](evidence/deflate-result-chunks.json) records the scoped correction.
Hosted Ubuntu follow-up remains pending.

Regression scan: 10 callers checked, 10 assertions checked, 1 flagged/fixed.

Hosted confirmation for `ec54445`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36267964218)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36267964256)
completed successfully with bounded DEFLATE result serialization.

## PNG non-interlaced 8-bit decoding

The PNG profile passes 38 native images / 8,987 complete pixels and 26 typed-error
controls on CPU, JavaScript and forced Metal. Every color type 0/2/3/4/6 is crossed
with all five scanline filters. Cases include palette/default alpha, low-byte tRNS
keys, 4096-wide/tall images, split/empty IDAT chunks, the native empty-stored-block
rule for PNG and ignored CRC/Adler checks. A grayscale late-tRNS control isolates
the ordering rule from the separate rejection of tRNS on existing alpha formats.
See [evidence/png-8bit.json](evidence/png-8bit.json).

An initial Metal compiler interruption persisted in a single-image program.
Stage isolation narrowed it to an 88-KiB generated chunk-reader probe; inflation,
filtering and chunk dispatch built independently. Separating payload collection
from subsequent CRC parsing resolved the minimized and full decoder failures.
Unhelpful intermediate parser rewrites were removed. The pinned compiler and
native expected pixels remain unchanged.

The full 261-scenario / 40,101-word corpus, nine harness tests, project checks and
all four pinned laws pass. The scoped drift review confirms I86, C3/C6, A4/A5/A6
and V2/V3 for this profile. Existing memory-loader coverage expands; counts remain
103 core and 142 raymath partial mappings, with no full-parity completions.
Other depths, Adam7/CgBI, PNG export, broader malformed recovery and complete
target/resource/performance evidence remain gaps.

Regression scan: 52 callers checked, 28 assertions checked, 2 flagged/fixed.

Hosted confirmation for `2e022c2`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36270386724)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36270386729)
completed successfully, including the initial PNG profile.

## Packed PNG grayscale and palette depths

PNG now supports non-interlaced 1/2/4-bit grayscale/palette input alongside the
existing 8-bit families. All 70 native images / 13,839 pixels and 30 typed-error
controls pass CPU, JavaScript and forced Metal. New cases cover odd widths,
partial bytes with nonzero padding, all packed-byte filters, opaque/translucent
palettes, grayscale sample/key scaling and byte-wrapped oversized transparency
keys. A 1×4096 packed image checks row-reset behavior. All previous 8-bit fixture
inputs and error expectations are retained. See [evidence/png-packed.json](evidence/png-packed.json).

The logical pixel index is mapped to a bounded packed row byte before MSB-first
extraction; filtering still sees the complete stored bytes. Rounded-up row sizes
also govern decompression limits, with a short partial-row negative control.
I87 and A4/A5 pass the declared packed profile. Full 261-scenario / 40,101-word
conformance, nine harness tests, project checks and all four pinned laws pass.
16-bit samples, Adam7/CgBI, PNG export and broader recovery/resource/platform
coverage remain gaps. API completion counts are unchanged.

Regression scan: 45 callers checked, 32 assertions checked, 1 flagged/fixed.

Hosted confirmation for `ec2f708`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36271921257)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36271921256)
completed successfully, including packed PNG depths and transparency wrapping.

## PNG 16-bit samples and transparency

Non-interlaced grayscale/RGB/gray-alpha/RGBA input now supports 16-bit samples.
The complete PNG gate passes 97 native images / 18,585 pixels and 32 typed-error
controls on CPU, JavaScript and forced Metal. Samples are filtered as bytes,
reconstructed big-endian and narrowed through the native high-byte rule. Full
16-bit tRNS comparisons distinguish close keys whose RGBA8 RGB values coincide;
alpha boundary cases include 255→0 and 256→1. See
[evidence/png-16bit.json](evidence/png-16bit.json).

All previous valid packed/8-bit inputs are retained. The old unsupported-depth
control uses 12 bits now; its original 16-bit header/data bytes remain as a
truncated-raster control, correctly returning stream rather than header failure
after the new header support. Invalid 16-bit palette input remains rejected.
The full 261-scenario / 40,101-word corpus, nine harness tests, project checks and
four pinned laws pass. I88 and A4/A5 hold for the exercised normalization profile.
The stale DEFLATE documentation describing PNG integration as future work was
updated to point to the implemented decoder. Adam7/CgBI, PNG export, original
format metadata and broader recovery/resource/platform coverage remain gaps.

Regression scan: 64 callers checked, 34 assertions checked, 1 flagged/fixed.

Hosted confirmation for `a97b3dd`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36273595808)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36273595825)
completed successfully, including full-width PNG transparency and narrowing.

## PNG Adam7 reconstruction

PNG decoding now supports Adam7 across every declared color/depth combination.
All 175 native images / 31,593 pixels and 36 typed-error controls pass CPU,
JavaScript and forced Metal. Tests cross 1×1, thin, odd and multi-pass geometries,
plus 4096-axis boundaries, palette/transparency and packed/16-bit samples. Empty
passes consume no data; each nonempty pass resets filtering and scatters its
normalized pixels through the pinned origin/stride tuples. Later-pass filter
errors, truncated final passes, excess data and filtered-capacity limits are
rejected. See [evidence/png-adam7.json](evidence/png-adam7.json).

All prior valid non-interlaced inputs are retained. The former Adam7 rejection
bytes are now a native-verified valid-image case; reserved interlace method 2
continues the invalid-header control. I89 and A4/A5 hold for the exercised profile.
Full 261-scenario / 40,101-word conformance, nine harness tests, project checks and
four pinned laws pass. Existing loader coverage expands without increasing full
API completion counts. CgBI, PNG export, original-format metadata and broader
recovery/resource/platform evidence remain gaps.

Regression scan: 67 callers checked, 38 assertions checked, 0 flagged/fixed.

Hosted confirmation for `6a803d4`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36275515537)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36275515532)
completed successfully, including all supported Adam7 color/depth combinations.

## Native-default CgBI PNG framing

CgBI markers now select raw DEFLATE while retaining the pinned native defaults:
iPhone channel conversion and unpremultiplication are both disabled. Stored
channel/alpha values therefore follow ordinary sample normalization with no
extra swap/division. All 193 native images / 31,677 pixels and 39 typed-error
controls pass CPU, JavaScript and forced Metal. New cases cover distinct RGB/A
channels, premultiplied-looking and hidden zero-alpha values, ignored marker
payloads, repeated/late markers, split IDATs, empty stored blocks and representative
packed/16-bit/Adam7 input. See [evidence/png-cgbi.json](evidence/png-cgbi.json).

Every previous PNG input and error expectation is retained. Framing is carried
independently through header, palette and transparency parsing; mismatched framing
and a CgBI stream without IHDR are rejected. I90 and A4/A5 hold for the native
default profile. Full 261-scenario / 40,101-word conformance, nine harness tests,
project checks and four pinned laws pass. Nondefault external stb flags, PNG
export, original-format metadata and broader recovery/resource/platform coverage
remain gaps. API completion counts are unchanged.

Regression scan: 61 callers checked, 41 assertions checked, 0 flagged/fixed.

Hosted confirmation for `cb24c9c`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36277197043)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36277197045)
completed successfully, including native-default CgBI framing and channels.

## Exact default PNG memory and file export

The quality-8 compressor matches 17 linked-stb comparisons / 170,780 encoded
bytes on CPU, JavaScript and forced Metal. Complete native memory/file exports
agree for 12 PNG images / 166,087 bytes; candidate encoders match every byte and
candidate decoders recover all 166,980 original RGBA bytes on each lane. Native
inspection confirms coverage of all five selected filters and both fixed/stored
DEFLATE output. CPU/JS additionally verify public mixed-alpha/noise file exports.
See [evidence/png-export.json](evidence/png-export.json).

The implementation preserves signed-byte filter scoring and strict ties, newest
equal matches, bucket eviction, lazy lookahead, strict window limits, bit packing,
stored fallback, native 5,552-byte Adler boundaries and all PNG CRC/header fields.
Review aligned Adler reduction boundaries with the reference order; encoded
expectations remained unchanged. The byte-result serializer is shared with the
inflater probe, whose original 24 streams / 16 controls still pass every lane.

Full 261-scenario / 40,101-word conformance, nine harness tests, project checks and
four pinned laws pass. I91 and A4/A5/A6 hold for default RGBA8 export. The ledger
adds partial `ExportImageToMemory` coverage and extends `ExportImage`, reaching
104 core plus 142 raymath partial functions with zero full-parity completions.
Other source formats, nondefault writer settings, pointer/buffer ownership ABI,
generic dispatch and complete resource/performance/platform evidence remain gaps.

Regression scan: 90 callers checked, 26 assertions checked, 1 flagged/fixed.

Hosted confirmation for `777c6d7`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36280418576)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36280418580)
completed successfully, including exact default PNG memory/file export.

## Byte-format PNG memory export

`Image.Formatted.to_png` now accepts native grayscale, gray-alpha, RGB888 and
RGBA8888 byte formats without RGBA normalization before encoding. Native channel
counts, color types and filter byte distances are preserved. All 28 native PNGs
/ 170,383 bytes and 171,716 normalized round-trip bytes pass CPU, JavaScript and
forced Metal. Native inspection confirms that every byte-format family selects
all five filters in the corpus. The original Surface RGBA8 fixtures and its two
public CPU/JS file exports remain covered. See
[evidence/png-export-formats.json](evidence/png-export-formats.json).

Packed memory-source formats 3/5/6 return the original image with
`UnsupportedPixelFormat`; one shared ownership check compares dimensions, format
and every retained byte for each rejected format. The full 261-scenario /
40,101-word corpus, nine harness tests, project checks and all four pinned laws
pass. I92 and A3/A4/A5 hold within the declared byte-format profile. Native buffer/
ownership ABI, other sources/settings, formatted-image file wrappers and full
resource/performance/platform coverage remain gaps. API completion counts are
unchanged.

Regression scan: 32 callers checked, 12 assertions checked, 0 flagged/fixed.

Hosted confirmation for `1750352`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36281862208)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36281862204)
completed successfully, including native byte-format PNG memory export.

## Formatted-image PNG file export

`Image.Formatted.write_png` covers all seven checked source formats. Byte formats
retain native channels; RGB565/RGB5A1/RGBA4 use the native file API's
`LoadImageColors` expansion. Exact 5/6-bit integer scale factors and shifted RGB5A1
blue extraction are retained independently of raw pixel getters and ImageFormat.
All 37 PNGs / 171,574 bytes and 172,340 normalized round-trip bytes pass CPU,
JavaScript and forced Metal. CPU/JS each write 27 public Surface/formatted files
and compare every byte. See [evidence/png-export-files.json](evidence/png-export-files.json).

Packed file cases use the actual file oracle; the native memory oracle remains
limited to its declared byte-source profile. Existing byte-format and Surface
fixtures are retained, as are the packed memory-rejection ownership checks.
I93 and A4/A5 hold for pure encoding, with file IO evidence scoped to CPU/JS.
Full 261-scenario / 40,101-word conformance, nine harness tests, project checks and
four pinned laws pass. Other formats/settings, generic dispatch, native ABI and
complete resource/performance/platform coverage remain gaps. API completion counts
are unchanged.

Regression scan: 18 callers checked, 12 assertions checked, 0 flagged/fixed.

Hosted confirmation for `37e1740`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36283236538)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36283236530)
completed successfully, including all formatted PNG file sources.

## Bounded image-file loading

`Surface.load_image` now selects supported lower/upper-case suffixes and detects
implemented raster contents as the native loader does. The file probe passes
24 native cases (23 LoadImage calls plus an explicit QOI-selection check), three
size/read boundaries and 100 repeated success/decode/read/size-error cycles under
a 64-descriptor limit on CPU and JavaScript. Cross-extension PNG/BMP/TGA/PNM data,
mixed/unsupported suffixes, invalid/empty/missing files and explicit QOI loading
are covered. See [evidence/image-file-loading.json](evidence/image-file-loading.json).

QOI loading shares the refactored IO boundary and retains its original cap and
explicit decoder choice. Handles close before decode and on size/read errors;
the complete reported byte count is required. Pure controls check suffix-only
and mixed-case names plus short reads. I94 and A4/A6 hold within the declared
ordinary-file profile. Full 261-scenario / 40,101-word conformance, nine harness
tests, project checks and four pinned laws pass. File IO claims remain CPU/JS;
other aliases/codecs, larger raster files, concurrent/special-file semantics,
native callbacks and full target/resource/performance coverage remain gaps.

Regression scan: 32 callers checked, 14 assertions checked, 0 flagged/fixed.

Hosted confirmation for `c3cd498`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36285392857)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36285392861)
completed successfully, including file dispatch and descriptor closure.

## Jonlib / Jonmath module ownership and naming

The raymath port is now `jonmath.bend`; core geometry/image/IO code remains in
`jonlib.bend`. Jonmath owns the shared vector/matrix/Float64 carriers and numerical
reference profile. Jonlib, generated runners, examples and proofs import those
same types. All 211 extracted declarations are byte-identical to the published
math implementation, and 156 implementation mappings now identify Jonmath.
See [MODULES.md](MODULES.md) for the `ray*` → `jon*` convention and required import
migration, and [evidence/jonmath-module.json](evidence/jonmath-module.json) for hashes.

The full 261-scenario / 40,101-word corpus passes CPU-1/CPU-2/JavaScript/forced
Metal. The standalone Jonmath example returns 5 on native CPU, JavaScript and
forced Metal; 512 native spline points and 529 resize images / 46,474 pixels
also pass their affected caller gates. All four proof propositions check with
the new imports. Ten harness/planning tests pass, including source-gate rejection
of unsafe/foreign Jonmath code and actual/proposed module-qualified mappings.

Source/symbol inventories cover both public modules. Project-side branded
configuration proposals use `JONLIB_*`/`JONMATH_*`; source headers, IDs, URLs and
notices continue to identify the actual upstream reference. The scoped review
confirms C16/C17, I95, A4/A5/A6 and V2. Every one of 1,884 inventory IDs retains
its status: 104 Jonlib core and 142 Jonmath functions remain partial, with zero
full-parity completions. Existing numerical/target/resource/performance gaps and
the documented import migration remain explicit.

Regression scan: 402 callers checked, 20 assertions checked, 3 flagged/fixed.

Hosted confirmation for `06f82c9`: [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36287555153)
completed successfully with the standalone Jonmath imports and shared types.

## Shared image memory and file dispatch

`Surface.decode_image(file_type, bytes)` selects the supported native token family
and content decoder. Raster tokens include lower/upper-case PNG/BMP/TGA/PGM/PPM
and JPG/JPEG/GIF/PIC/PSD aliases; QOI remains separately selected. File loading
shares that resolver after native-style last-dot suffix extraction. Actual
JPEG/GIF/PIC/PSD payloads and HDR's float path remain gaps. See
[IMAGE-FILES.md](IMAGE-FILES.md) and [evidence/image-dispatch.json](evidence/image-dispatch.json).

The native memory gate passes 138 token/content pairs (102 accepted images with
all dimensions/pixels checked) and five typed failure controls on CPU/JavaScript/
forced Metal. File loading passes 38 native cases, three size/read controls and
100 low-descriptor cycles per CPU/JavaScript lane. Suffix-only `.jpeg` is rejected,
directory-qualified dotfiles work, and mixed-case/unsupported tokens preserve
their native rejection. Open/size/read failures and explicit QOI loading retain
their previous ownership/error behavior.

The scoped review finds I96 MATCH (`jonlib.bend`, shared selector and decoder);
A4/A5 HOLD (source gate and forced native-comparison lanes); V2 HOLD (actual
linked `LoadImageFromMemory`/`LoadImage` expectations); V3 HOLD (existing checked
decoders and bounded complete file reads). The ledger expands the two existing
partial mappings without adding completed APIs. Four stale codec-documentation
dispatch gaps were corrected during the regression review.

The full 261-scenario / 40,101-word corpus passes CPU-1, CPU-2, JavaScript and
forced Metal, including the updated decoding contracts. All four proofs and ten
harness/planning tests pass. Project metadata, links and generated ledgers check.
GPU filesystem IO, CUDA and the remaining documented codec/resource/platform
domains were not verified by this increment.

Regression scan: 23 callers checked, 19 assertions checked, 4 flagged/fixed.

## Native 16-bit PGM/PPM normalization

The P5/P6 decoder now accepts maxval through 65535, retaining two bytes per sample
when maxval exceeds 255. The pinned little-endian native reader copies those bytes
without swapping, then narrows its U16 values by shifting right eight. Jonlib
therefore keeps the second stored byte, including values above maxval, with no
rescaling. For example, stored RGB samples `12 34 ab cd 01 fe` normalize to
`34 cd fe ff`. This behavior differs from standard big-endian PNM interpretation
and is explicitly part of the current reference profile.

The native PNM gate passes 30 images / 8,844 pixels and 16 typed-error controls on
CPU, JavaScript and forced Metal. It retains all earlier 8-bit inputs and adds
16-bit maxval boundaries, all 256 output byte values, channel ordering, CRLF and
trailing-data behavior. The old unsupported-16-bit rejection is replaced by a
real native-supported fixture and an above-65535 rejection. Truncated samples,
incomplete RGB channels and invalid bytes in discarded positions remain failures.

Shared dispatch passes 160 memory token/content pairs and five controls across
CPU/JS/Metal; file dispatch passes 39 cases, three boundaries and 100 low-descriptor
cycles per CPU/JS lane. Both now exercise a 16-bit PPM stream. Source/input/native
hashes are retained in [evidence/pnm-16bit.json](evidence/pnm-16bit.json).

Scoped review: I97 MATCH (`src/pnm.bend:47-144`); A4/A5 HOLD under the source and
native-comparison gates; A6 HOLD in [PNM.md](PNM.md); V2 HOLD through linked native
expectations; V3 HOLD through validated dimensions and required two-byte payload
length before output allocation. Original metadata, big-endian reference profiles,
permissive malformed recovery and full resource/platform/performance parity remain
gaps. API counts remain 104 core and 142 math partial mappings, zero complete.

The full 261-scenario / 40,101-word CPU-1/CPU-2/JavaScript/forced-Metal corpus
passes, as do all four proofs, ten harness/planning tests and project checks.
No GPU filesystem IO or big-endian host behavior was exercised.

Regression scan: 24 callers checked, 19 assertions checked, 1 flagged/fixed.

## Packed 15/16-bit TGA true color

Non-paletted type-2/type-10 images now accept 15/16-bit RGB555 samples. Each pixel
consumes two little-endian bytes; the five-bit RGB fields expand with integer
`channel*255/31`. Native packed alpha/high bits are ignored and output is opaque.
Gray-alpha 16-bit images retain their separate gray/alpha-byte contract.

The TGA gate passes 27 native images / 998 pixels, 16 typed-error controls and
11 unchanged complete exports / 3,447 bytes on CPU/JavaScript/forced Metal, with
real file-export comparison on CPU/JS. Packed cases cover every five-bit value,
both high-bit states and vertical orientations, image IDs, raw/RLE transitions
and partial samples. The former unsupported-depth-16 control is now native-supported;
depth 17 retains the unsupported-format rejection.

Shared dispatch passes 182 native memory pairs plus five typed controls on
CPU/JS/Metal and 40 file cases plus three boundaries and 100 low-descriptor cycles
on CPU/JS. Both include a packed TGA stream. See [TGA.md](TGA.md) and
[evidence/tga-packed.json](evidence/tga-packed.json) for the profile and hashes.

Scoped review: I98 MATCH (`src/tga.bend:18-119`); A4/A5 HOLD through source checks
and native CPU/JS/Metal results; A6 HOLD in [TGA.md](TGA.md); V2 HOLD through
linked native pixel/export expectations; V3 HOLD through existing dimension,
packet-count and sample-availability guards. Paletted/remaining TGA variants,
original metadata and full resource/platform/performance parity remain gaps.
The two image-loading mappings remain partial; no completed APIs are added.

The full 261-scenario / 40,101-word CPU-1/CPU-2/JavaScript/forced-Metal corpus
passes. All four proofs, ten harness/planning tests and project checks pass.
GPU file IO and the remaining platform/resource/performance domains were not
exercised by this increment.

Regression scan: 41 callers checked, 20 assertions checked, 0 flagged/fixed.

Hosted confirmation for `42392a2`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36289416753)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36289416808)
passed, including shared dispatch and 16-bit PNM. The packed-TGA commit `5df21d1`
was published through merge `fe4fd44`, preserving the independently updated
`# Jonlib` README title from `96a61b9`.

## Indexed TGA palettes

The decoder now supports indexed types 1/9 with 8/16-bit indices and
8/15/16/24/32-bit palette encodings. Palette-start follows the observed native
byte skip after the image ID; out-of-range indices select palette entry zero.
RGB555 palettes remain opaque, while 32-bit entries retain their supplied alpha.
Empty/unsupported palettes and incomplete palette/index/packet data return typed
errors. Output dimensions and packet limits retain their previous bounds.

The TGA gate passes 48 native images / 1,123 pixels, 23 typed-error controls and
all 11 exact exports / 3,447 bytes on CPU, JavaScript and forced Metal. New inputs
cover every palette format/index width, raw/RLE transitions, ID and offset skips,
index recovery, alpha and a 257-entry palette with values above the 8-bit range.
All earlier direct-color/grayscale/packed fixtures remain in the gate.

Shared dispatch passes 204 memory token/content pairs plus five controls on
CPU/JS/Metal; file dispatch passes 41 cases, three boundaries and 100 low-descriptor
cycles on CPU/JS. Both include an indexed stream. Source/input/native hashes are
in [evidence/tga-palettes.json](evidence/tga-palettes.json).

Scoped review: I99 MATCH (`src/tga.bend`, checked palette loading and sample
selection); A4/A5 HOLD through source/native lane gates; A6 HOLD in [TGA.md](TGA.md);
V2 HOLD through actual linked pixel/export output, including explicit native index
recovery; V3 HOLD through checked dimensions, finite palette reads, bounded packets
and existing output indexing. Original metadata, remaining variants and full
resource/platform/performance parity remain gaps. The API ledger broadens the
same two partial loading mappings and records zero full-parity completions.

The full 261-scenario / 40,101-word CPU-1/CPU-2/JavaScript/forced-Metal corpus
passes, with all four proofs, ten harness/planning tests and project checks.
GPU file IO and broader resource/platform/performance coverage remain unverified.

Regression scan: 53 callers checked, 27 assertions checked, 0 flagged/fixed.

Hosted confirmation for `fe4fd44`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36290080551)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36290080552)
passed. Indexed TGA was subsequently published as `9e7b9fa`.

## Indexed BMP palettes

INFO/V4 `BI_RGB` now supports 1/4/8-bit indexed images. Palette length comes from
the pixel offset rather than `clrUsed`; BGR entries discard their reserved/alpha
byte and become opaque. Packed samples are MSB-first, unused row-end bits are
ignored, and input rows keep four-byte alignment. Residual palette-offset bytes
are skipped once; the existing true-color double-gap behavior stays distinct.

The BMP gate passes 38 native images / 4,345 pixels, 22 typed-error controls and
three unchanged complete exports / 410 bytes on CPU/JavaScript/forced Metal.
Cases cover INFO/V4, depths/orientations, full/reduced palettes, ignored metadata,
partial-byte rows, maximum palette offset and a 4096-pixel row. Missing palette
entries return `InvalidImageStream`, with a dedicated public-error control; native
uninitialized palette reads remain outside the supported domain. Empty/oversized
palettes and missing palette/row-padding bytes are rejected.

Shared dispatch passes 226 memory pairs plus five controls on CPU/JS/Metal and
42 file cases plus three boundaries and 100 low-descriptor cycles on CPU/JS.
Both include an indexed BMP. Current hashes and results are recorded in
[evidence/bmp-palettes.json](evidence/bmp-palettes.json).

Scoped review: I100 MATCH (`src/bmp.bend`, offset-derived palette and indexed
scanlines); A4/A5 HOLD through source/native lane gates; A6 HOLD in [BMP.md](BMP.md);
V2 HOLD through complete linked native pixels/export bytes; V3 HOLD through
validated dimensions, palette and payload bounds, checked indices and guarded
output addressing. Original metadata, 16-bit/other header/mask/compression profiles
and full resource/platform/performance coverage remain gaps. The ledger keeps
104 core and 142 math partial mappings, zero full-parity completions.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, ten harness/planning tests and project checks pass. GPU filesystem IO and
the remaining platform/resource/performance domains were not exercised.

Regression scan: 51 callers checked, 26 assertions checked, 0 flagged/fixed.

Hosted confirmation for `9e7b9fa`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36290735613)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36290735621)
passed. Indexed BMP was subsequently published as `c2cf7b2`.

## Opaque RGB555 BMP

The BMP decoder now accepts uncompressed 16-bit INFO/V4 images, with zero stored
alpha masks required for V4 in this profile. Each five-bit RGB field uses native
bit replication `(value*33)>>2`; bit 15 is ignored and pixels are opaque.
This deliberately differs from packed TGA's integer `value*255/31` expansion:
the retained native `0x1000`/`0x9000` BMP samples both become `0x210000ff`.

The BMP gate passes 43 images / 4,607 pixels, 25 typed-error controls and three
complete exports / 410 bytes on CPU/JavaScript/forced Metal, with real file-export
checks on CPU/JS. New cases cover every five-bit channel value, both high-bit
states, INFO/V4, ignored stored RGB masks, both orientations, odd row padding and
double-skipped gap bytes. Nonzero 16-bit V4 alpha masks and truncated words/padding
are rejected. All indexed and 24/32-bit cases and exact export bytes remain checked.

Shared dispatch passes 248 native memory pairs plus five controls on CPU/JS/Metal,
and 43 native file cases plus three boundaries and 100 low-descriptor cycles on
CPU/JS. Both include an RGB555 BMP stream. Hashes and lane outcomes are recorded in
[evidence/bmp-rgb555.json](evidence/bmp-rgb555.json).

Scoped review: I101 MATCH (`src/bmp.bend`, depth-aware true-color reader and mask
restriction); A4/A5 HOLD through source/native lane checks; A6 HOLD in [BMP.md](BMP.md);
V2 HOLD through actual native pixels/export bytes; V3 HOLD through checked
dimensions, byte-depth-aware payload/padding bounds and guarded output addressing.
Nonzero V4 alpha masks, other header/mask/compression profiles, original metadata
and full platform/resource/performance remain gaps. API mappings remain partial;
no completed APIs are added.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, ten harness/planning tests and project checks pass. GPU filesystem IO and
the remaining platform/resource/performance domains were not exercised.

Regression scan: 31 callers checked, 29 assertions checked, 0 flagged/fixed.

Hosted confirmation for `6a55a9a`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36291967317)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36291967309)
passed, including opaque RGB555 BMP and the preceding indexed profiles.

## Native BMP bitfields and V4 alpha

The 16/32-bit INFO/V4 bitfield paths now retain native population-count/highest-bit
alignment and per-width replication for masks with 1..8 set bits. Reordered,
overlapping and noncontiguous masks are supported. Native extraction does not
compact holes: RGB masks `5/0a/50` decode word `005f` as `aaaaaaff`.

INFO bitfields consume three additional mask words, include them in the effective
header length and reject three identical RGB masks. V4 keeps its four masks
inside the DIB and permits equal RGB masks. Absent alpha is opaque; explicit
bitfield alpha preserves zero. Uncompressed V4 16-bit now retains its stored
alpha mask while using native RGB555 defaults, including all-zero alpha. The
32-bit uncompressed all-zero-alpha repair remains a distinct profile.

The BMP gate passes 66 native images / 5,777 pixels, 29 typed-error controls and
three exact exports / 410 bytes on CPU/JavaScript/forced Metal. Fixtures cover
every mask population 1..8, RGB565/ARGB1555/RGBA4444, reordered/overlapping/gapped
masks, high bits, INFO mask offsets and V4 alpha below/above the stored word.
Zero RGB masks, populations above eight, incomplete masks and invalid effective
offsets reject. All prior indexed, byte-color, RGB555 and export cases remain.

Shared dispatch passes 270 memory pairs plus five controls on CPU/JS/Metal and
44 file cases plus three boundaries and 100 low-descriptor cycles on CPU/JS.
The current source/native/input hashes are in
[evidence/bmp-bitfields.json](evidence/bmp-bitfields.json).

Scoped drift review: C2/C3 HOLD under pinned-checkout/source gates; I102 MATCH
(`src/bmp.bend`, channels/modes/header parsing); A4/A5 HOLD under native backend
gates; A6 HOLD in [BMP.md](BMP.md); V2 HOLD through full linked native pixels and
exports; V3 HOLD through checked fields, effective header lengths, dimensions and
payload/output bounds. The planned scope was expanded to match observed gapped-mask
alignment before implementation. Original metadata, remaining header/compression
profiles and full resource/platform/performance parity remain gaps.

The scan removed an unnecessary scale carrier and clarified the compatibility
table's 16/32-bit bitfield wording. Affected native and full-corpus gates were
rerun after the source simplification. All 261 scenarios / 40,101 words pass
CPU-1/CPU-2/JavaScript/forced Metal; all four proofs, ten harness/planning tests and
project checks pass. GPU filesystem IO and remaining targets were not exercised.
The API ledger retains 104 core and 142 math partial mappings, zero complete.

Regression scan: 68 callers checked, 33 assertions checked, 2 flagged/fixed.

Hosted confirmation for `c4cca6f`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36293774991)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36293775065)
passed, including native bitfield alignment and V4 alpha preservation.

## 56-byte and V5 BMP headers

The existing BMP profiles now accept 56-byte and 124-byte DIBs. Native 56-byte
loading discards the embedded four mask words; bitfield images read three further
RGB masks after the DIB and include them in the effective header length. Its
uncompressed 16-bit path ignores embedded alpha and remains opaque. V5 follows
V4 mask/alpha behavior and consumes four ignored intent/profile words without
following profile offsets.

The BMP gate passes 80 native images / 5,861 pixels, 33 typed-error controls and
three exact exports / 410 bytes on CPU/JavaScript/forced Metal. Added profiles
cover indexed, 16/24/32-bit and bitfield images, contradictory embedded masks,
zero/mixed alpha, ignored V5 profile fields and double-skipped gap bytes. Missing
embedded/external/profile words and offsets inside the 56-byte mask extension
reject with typed header errors. All prior profiles remain in the same gate.

Shared dispatch passes 314 memory pairs plus five controls on CPU/JS/Metal and
46 file cases plus three boundaries and 100 low-descriptor cycles on CPU/JS.
Both exercise 56-byte and V5 streams. Source/input/native hashes are in
[evidence/bmp-headers.json](evidence/bmp-headers.json).

Scoped review: I103 MATCH (`src/bmp.bend:117-162`); A4/A5 HOLD through source and
native backend gates; A6 HOLD in [BMP.md](BMP.md); V2 HOLD through complete native
pixel/export comparisons; V3 HOLD through header-prefix/effective-offset bounds
and unchanged checked pixel addressing. CORE headers, original metadata, native
malformed recovery and full resource/platform/performance remain gaps.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, ten harness/planning tests and project checks pass. GPU filesystem IO and
remaining targets were not exercised. The two loading mappings remain partial,
with zero full-parity completions.

Regression scan: 40 callers checked, 37 assertions checked, 0 flagged/fixed.

Hosted confirmation for `7dfa6d1`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36295142709)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36295142716)
passed, including 56-byte/V5 headers and the preceding BMP profiles.

## CORE RGB24 and bounded memory-probe runners

The BMP reader now selects its layout after the common file/DIB prefix. A CORE
RGB24 file can therefore use its complete 26-byte header without being mistaken
for a truncated larger header. Unsigned 16-bit dimensions retain the 1..4096
profile, planes must equal one, rows are bottom-up padded BGR, and output is opaque.
The native true-color double-gap behavior is preserved relative to the shorter
header end.

The BMP gate passes 87 images / 9,979 pixels, 41 typed-error controls and three
exact exports / 410 bytes on CPU/JavaScript/forced Metal. CORE inputs include a
30-byte complete image, all row-padding widths, a 4096-pixel row and the maximum
gap. Planes/depth/dimensions/offsets and truncated headers/padding reject correctly.
All larger-header cases remain in the gate.

The expanded 336-case memory matrix initially overflowed Bun's stack before any
result was printed. Its final 64 unchanged actions, including the reported failure
location, passed alone. The gate now compiles at most 64 observation/control
actions per runner on each lane and concatenates every result before the unchanged
whole-result comparator. All 341 original actions are byte-identical and ordered
across six runners. Batch stages/counts persist before compilation/execution; a
new failure-detection test rejects missing/extra identical results that could
otherwise cancel across batches and confirms stale success is cleared.

The final memory gate passes all 336 native pairs plus five typed controls on
CPU/JS/Metal. File loading passes 47 cases, three boundaries and 100 low-descriptor
cycles on CPU/JS. Hashes and batch coverage are in
[evidence/bmp-core.json](evidence/bmp-core.json). Decoder semantics, native inputs,
runtime flags and timeouts were retained while fixing the runner structure.

Scoped drift review: I104/I105 MATCH (CORE prefix reader and bounded probe); A4/A5
HOLD through source/native lane gates; A6 HOLD in [BMP.md](BMP.md) and
[IMAGE-FILES.md](IMAGE-FILES.md); V2 HOLD through all unchanged ordered native
expectations; V3 HOLD through checked dimensions/offsets/payloads and existing
bounded addressing. Indexed CORE palettes, original metadata, native malformed
recovery and complete resource/platform/performance parity remain gaps.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, eleven harness/planning tests and project checks pass. GPU filesystem IO
and remaining targets were not exercised. API mappings remain partial.

Regression scan: 33 callers checked, 54 assertions checked, 1 flagged/fixed.

Hosted confirmation for `a22a539`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36296958027)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36296958033)
passed, including CORE RGB24 and the bounded memory-probe runners.

## Indexed CORE BMP palettes

CORE 1/4/8-bit decoding now follows the pinned palette rule:
`count = floor((pixel_offset - 38)/3)`. The reader consumes BGR triples after the
26-byte header, then skips twelve plus the division remainder bytes. It retains
bottom-up MSB-first indices, four-byte row padding and opaque colors. Palette
count is constrained to 1..256 and every index is checked; native uninitialized
palette access remains outside the supported domain.

The BMP gate passes 98 images / 10,076 pixels, 46 typed-error controls and three
exact exports / 410 bytes on CPU/JavaScript/forced Metal. CORE palette cases cover
all depths, minimum/reduced/full tables, every skip remainder and byte/row
boundaries. Empty/oversized tables, incomplete triples/padding and invalid indices
reject. The shared word reader now accepts the entry width explicitly; all
existing four-byte headers/palettes remain verified alongside three-byte CORE
entries.

Shared dispatch passes 358 native memory pairs plus five controls on CPU/JS/Metal
and 48 file cases plus three boundaries and 100 low-descriptor cycles on CPU/JS.
Source/input/native hashes are in
[evidence/bmp-core-indexed.json](evidence/bmp-core-indexed.json).

Scoped review: I106 MATCH (`src/bmp.bend`, CORE range/count/skip and indexed mode);
A4/A5 HOLD through source/native lane gates; A6 HOLD in [BMP.md](BMP.md); V2 HOLD
through complete native pixels and exports; V3 HOLD through bounded palette
counts, checked indices, payload bounds and existing output addressing. Original
metadata, malformed/undefined recovery and full resource/platform/performance
coverage remain gaps. The two loading mappings remain partial.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, as do all
four proofs, eleven harness/planning tests and project checks. GPU filesystem IO
and remaining targets were not exercised.

Regression scan: 35 callers checked, 50 assertions checked, 0 flagged/fixed.

Hosted confirmation for `2c784a0`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36298421342)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36298421340)
passed, including indexed CORE palettes and bounded dispatch runners.

## Native TGA type/depth selection

Non-paletted types 2/3/10/11 now accept every native depth 8/15/16/24/32. Eight-bit
data is grayscale and 15-bit data is opaque RGB555 regardless of nominal type.
Only 16-bit input distinguishes grayscale types 3/11 (gray-alpha) from types 2/10
(RGB555). Depths 24/32 use BGR/BGRA for either type. Existing palette selection,
alpha, row orientation, RLE and strict malformed-input behavior remain in place.

The TGA gate passes 64 native images / 1,219 pixels, 23 error controls and all
11 exact exports / 3,447 bytes on CPU/JavaScript/forced Metal. Added cross-type
cases cover all four new combinations in raw/RLE and both orientations. Shared
dispatch passes 380 memory pairs plus five controls and 49 file cases plus three
boundaries/100 low-descriptor cycles. File IO evidence is CPU/JS only; pure memory
decoding also passes forced Metal. See
[evidence/tga-depths.json](evidence/tga-depths.json).

Scoped review: I107 MATCH (`src/tga.bend:86-100`); A4/A5 HOLD through source/native
lane gates; A6 HOLD in [TGA.md](TGA.md); V2 HOLD through full native pixels/exports;
V3 HOLD through the existing dimensions, packets and sample bounds. Original
metadata, native malformed recovery and full resource/platform/performance remain
gaps. API mappings remain partial with zero full-parity completions.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, as do all
four proofs, eleven harness/planning tests and project checks. GPU filesystem IO
and remaining targets were not exercised.

Regression scan: 45 callers checked, 27 assertions checked, 0 flagged/fixed.

Hosted confirmation for `13e5688`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36299854244)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36299854259)
passed, including native TGA type/depth selection.

## Opaque raw PSD decoding

`Surface.decode_psd` adds version-1 RGB PSD decoding for raw 8/16-bit planes and
0..3 channels. RGB planes preserve order, absent channels default to zero, and
alpha is opaque. Sixteen-bit big-endian samples retain their high byte. Reserved
bytes and three mode/resource/layer sections are ignored after availability
checks; dimensions and complete required samples are validated before allocating
output. Shared raster dispatch recognizes the exact `8BPS` signature.

The PSD gate passes 12 native images / 8,247 pixels and 16 typed-error controls on
CPU/JavaScript/forced Metal. Cases cover every supported channel count/depth,
reserved/metadata/trailing data, 4096-pixel axes, unsupported headers and incomplete
samples/sections, including a declared section length of `0xffffffff` with a short
actual input. Native inputs and output pixels are retained unchanged.

Shared dispatch passes 402 memory pairs plus five controls on CPU/JS/Metal and
51 file cases plus three boundaries and 100 low-descriptor cycles on CPU/JS.
Both include actual PSD data, with lowercase/uppercase PSD files and cross-extension
content detection. Evidence is in [evidence/psd-raw.json](evidence/psd-raw.json),
and the retained stb MIT attribution covers the new Bend module.

Scoped review: I108 MATCH (`src/psd.bend` and `jonlib.bend` adapters/dispatch);
A4/A5 HOLD through source/native backend gates; A6 HOLD in [PSD.md](PSD.md) and
the notices; V2 HOLD through complete linked native pixels; V3 HOLD through
validated dimensions/sections/required plane bytes and bounded output indices.
RLE, four-plus-channel white-matte correction, original metadata, malformed
recovery and full resource/platform/performance remain gaps. The two loading
mappings remain partial; no completed APIs are added.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, as do all
four proofs, eleven harness/planning tests and project checks. GPU filesystem IO
and remaining targets were not exercised.

Regression scan: 50 callers checked, 24 assertions checked, 0 flagged/fixed.

Hosted confirmation for `3c9e7ff`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36301500331)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36301500317)
passed, including opaque raw PSD and its shared dispatch.

## Opaque PSD PackBits

PSD compression 1 now decodes bounded literal/repeat/no-op packets per channel.
The native row-count table is consumed but its values are ignored; packets can
cross rows. A structural input-byte budget bounds no-op processing. Every packet
count is checked against the remaining plane before output writes. The native
RLE path emits byte samples even under a depth-16 header, distinct from raw
big-endian sixteen-bit narrowing.

The PSD gate passes 24 native images / 12,657 pixels and 23 error controls on
CPU/JavaScript/forced Metal. It covers all channel/depth profiles, packet lengths
1/2/128, no-ops, channel transitions, deliberately incorrect row lengths, a
4096-pixel repeated plane, truncated tables/packets and overruns. All raw inputs
remain in the gate. Shared dispatch passes 424 memory pairs plus five controls
and 52 file cases plus three boundaries/100 low-descriptor cycles. Pure memory
lanes include forced Metal; file IO remains CPU/JS evidence.

Scoped review: I109 MATCH (`src/psd.bend`, PackBits cursor/fuel/packet bounds);
A4/A5 HOLD through source/native lane gates; A6 HOLD in [PSD.md](PSD.md); V2 HOLD
through complete linked native pixels; V3 HOLD through validated dimensions,
table availability, remaining-plane checks and bounded output indices. Four-plus-
channel matte correction, original metadata, malformed recovery and full
resource/platform/performance remain gaps. Hashes are in
[evidence/psd-rle.json](evidence/psd-rle.json); API mappings remain partial.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, as do all
four proofs, eleven harness/planning tests and project checks. GPU filesystem IO
and remaining targets were not exercised.

Regression scan: 47 callers checked, 31 assertions checked, 0 flagged/fixed.

Hosted confirmation for `5f9ec65`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36303276810)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36303276840)
passed, including PSD PackBits boundaries and native depth behavior.

## Profiled PSD alpha and white-matte correction

PSD now accepts 0..16 declared channels, observes only the first four pixel planes
and preserves actual alpha, including zero. Extra pixel planes are ignored;
RLE still consumes row-count entries for all declared channels. The native
white-matte formula retains alpha-0/255 RGB directly and handles supported
prematted intermediate-alpha RGB with explicit arithmetic selection.

The independent gate compares all 33,151 supported channel/alpha pairs against
both uncontracted and fused C models on CPU/JavaScript/forced Metal. Of 32,639
intermediate-alpha pairs, 130 produce different bytes between models. Actual
linked macOS PSD decoding matches the fused model throughout. The gate records
both native mismatch counts before checking the declared host profile; hosted
Linux validation checks the uncontracted selection independently.

`Image.Decode.Reference` exposes `UncontractedDecode` and `FusedDecode` through
`Surface.decode_psd_for`, `Surface.decode_image_for` and `Surface.load_image_for`.
Convenience operations select uncontracted, with an exact default/profile contract
test using the alpha-11 white pixel (255 uncontracted, 254 fused). Reference values
flow through existing file complete-read/error/closure callbacks. Repeated file
closure tests now load a real alpha PSD.

The PSD gate passes 36 native images / 12,729 pixels and 25 typed-error controls
on CPU/JS/Metal, covering raw/RLE, 8/16-bit data, zero/opaque/intermediate alpha,
five/sixteen declared channels with only four pixel planes, invalid matte domains
and missing alpha. Profiled shared dispatch passes 446 native memory pairs plus
five controls and 53 file cases plus three boundaries/100 low-descriptor cycles.
File IO evidence remains CPU/JS. See [evidence/psd-alpha.json](evidence/psd-alpha.json).

Scoped drift review: I110 MATCH (PSD channels/matte and profiled adapters); A3 HOLD
through affine results and retained file-owner closure; A4/A5 HOLD through source
and native/model backend gates; A6 HOLD in [PSD.md](PSD.md), [API.md](API.md) and
[IMAGE-FILES.md](IMAGE-FILES.md); V2 HOLD through exact models/native pixels and
unchanged prior fixtures; V3 HOLD through dimensions, first-four-plane bounds,
packet checks and supported matte-domain validation. Original metadata, out-of-
range native casts, further arithmetic hosts and full resource/platform/performance
coverage remain gaps. The loading mappings remain partial, with zero complete APIs.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, eleven harness/planning tests and project checks pass. The scan corrected
stale PSD scope wording and made native-profile failure diagnostics durable; the
affected matte gate was rerun. GPU filesystem IO and remaining targets were not
exercised.

Regression scan: 62 callers checked, 43 assertions checked, 2 flagged/fixed.

Hosted confirmation for `baa4e37`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36305911994)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36305912080)
passed. The hosted native matte gate confirmed the declared arithmetic profiles
alongside profiled PSD memory/file interoperability.

## Raw Softimage PIC decoding

`Surface.decode_pic` recognizes the native magic/PICT markers and reads bounded
eight-bit raw channel packets. All components start white; packets run in order
within each row and later selected channels overwrite earlier values, including
zero alpha. Low mask bits and reserved/ratio/field header values are ignored.
One to ten chained descriptors and complete required samples are checked before
output allocation. Shared raster dispatch recognizes PIC content across its
supported extension family.

The PIC gate passes 20 native images / 4,208 pixels and 14 error controls on
CPU/JavaScript/forced Metal. Cases cover all high-bit masks, ignored low bits,
white defaults, overlapping channel packets, alpha, nonunit chain flags,
ten-packet/row boundaries and a 4096-pixel row. Invalid signatures/markers/depths,
unsupported compression, incomplete descriptors/samples, excess chains and bad
dimensions reject. Shared dispatch passes 468 native memory pairs plus five
controls and 55 file cases plus three boundaries/100 low-descriptor cycles.
File evidence is CPU/JS; pure decoding also runs forced Metal.

Scoped review: I111 MATCH (`src/pic.bend` and Jonlib dispatch); A4/A5 HOLD through
source/native lane gates; A6 HOLD in [PIC.md](PIC.md) and retained MIT/Tom Seddon
attribution; V2 HOLD through complete linked native pixels; V3 HOLD through
dimensions, descriptor limits, checked sample totals and bounded row/pixel writes.
Pure/mixed RLE, original metadata, malformed recovery and full resource/platform/
performance remain gaps. Hashes are in [evidence/pic-raw.json](evidence/pic-raw.json).

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, eleven harness/planning tests and project checks pass. GPU filesystem IO
and remaining targets were not exercised. Loading mappings remain partial.

Regression scan: 48 callers checked, 22 assertions checked, 0 flagged/fixed.

Hosted confirmation for `afc05c9`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36307771529)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36307771591)
passed, including raw PIC packets and shared dispatch.

## Pure and mixed Softimage PIC RLE

PIC descriptors now support all three native packet types. Pure RLE clips counts
to the remaining row; mixed RLE rejects overruns and preserves literal, short-
repeat and big-endian extended counts. Zero-count runs consume selected samples
without output progress. Both modes retain the native post-control availability
check, including empty masks, and use structural input-byte fuel. Raw and RLE
packets preserve their ordered per-row channel overwrites.

The PIC gate passes 33 native images / 8,867 pixels and 24 error controls on
CPU/JavaScript/forced Metal. Cases cover channel masks, clipped/zero runs, mode
mixtures, alpha overwrites, 128/255 boundaries, 4096-pixel extended repeats and
strict count/sample/row bounds. No-progress streams terminate with typed errors.
All raw cases remain in the same gate. Shared dispatch passes 490 native memory
pairs plus five controls and 56 file cases plus three boundaries/100 low-descriptor
cycles. Pure memory evidence includes Metal; file IO remains CPU/JS.

Scoped review: I112 MATCH (`src/pic.bend`, packet kinds/RLE cursor/row bounds);
A4/A5 HOLD through source/native lane gates; A6 HOLD in [PIC.md](PIC.md); V2 HOLD
through full linked native pixels; V3 HOLD through dimensions, descriptor limits,
sample checks, clipped/validated counts and bounded output addressing. Original
metadata, malformed recovery and full resource/platform/performance remain gaps.
Hashes are in [evidence/pic-rle.json](evidence/pic-rle.json); loading mappings remain
partial with zero completed APIs.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, as do all
four proofs, eleven harness/planning tests and project checks. GPU filesystem IO
and remaining targets were not exercised.

Regression scan: 58 callers checked, 32 assertions checked, 0 flagged/fixed.

Hosted confirmation for `8f3a17c`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36309784250)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36309784217)
passed, including both PIC RLE modes and boundary controls.

## Full-canvas first-frame GIF

`Surface.decode_gif` adds GIF87a/GIF89a first-frame decoding with global/local
palettes, Graphic Control transparency and extension sub-block handling. The
current image descriptor covers the full logical canvas at origin zero without
interlacing. Transparent pixels remain transparent black, matching the native
initial canvas. Later frames are ignored after the first complete raster.

The Bend LZW path uses owned 8,192-entry dictionary storage, LSB-first codes,
clear/reset state, width growth through 12 bits and next-code self-reference.
Structural bit/prefix fuel and independent dictionary/output bounds prevent
unchecked array access. Complete pixel output and valid palette references are
required; permissive malformed/incomplete recovery remains outside this profile.

The gate passes 19 native images / 4,738 pixels and 20 error controls on CPU,
JavaScript and forced Metal. It covers versions, palette selection, transparent
black, control resets, comments/application blocks, small sub-blocks, self-reference,
every minimum code size 2..8 and a 4,096-pixel stream reaching 12-bit codes and a
dictionary reset. The scan added a separate dictionary-capacity control whose
pixels fit the canvas but whose code additions exceed dictionary storage; the
affected native/backend gate was rerun.

Shared dispatch passes 512 memory pairs plus five controls and 58 file cases plus
three boundaries/100 low-descriptor cycles. Memory decoding includes forced
Metal; file IO remains CPU/JS. Source/input/native hashes are in
[evidence/gif-first-frame.json](evidence/gif-first-frame.json).

Scoped review: I113 MATCH (`src/gif.bend`, `src/gif_lzw.bend` and public dispatch);
A4/A5 HOLD through source/native lane gates; A6 HOLD in [GIF.md](GIF.md) and MIT/
Jean-Marc Lienher/stb attribution; V2 HOLD through complete native pixels; V3 HOLD
through dimensions, palettes, sub-blocks, dictionary and output checks. Offset/
interlaced frames, animation/disposal/timing, original metadata and full resource/
platform/performance remain gaps. Loading mappings remain partial.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, as do all
four proofs, eleven harness/planning tests and project checks. GPU filesystem IO
and remaining targets were not exercised.

Regression scan: 98 callers checked, 28 assertions checked, 1 flagged/fixed.

Hosted confirmation for `ff24329`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36312479210)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36312479228)
passed, including first-frame GIF palettes and bounded LZW.

## GIF first-frame offsets and interlacing

First-frame GIF now accepts positive in-canvas image rectangles and all four
interlace passes, returning the logical canvas dimensions. Untouched pixels use
transparent black for background index zero. For a positive index, the native
first-frame memcpy retains global-palette BGR byte order and forces alpha 255;
Jonlib preserves that red/blue swap. Decoded transparent pixels remain black/
transparent even when untouched surrounding pixels receive the background.
Required missing/out-of-table background entries reject instead of accessing
undefined native palette data.

The gate passes 41 native images / 5,410 pixels and 23 error controls on CPU,
JavaScript and forced Metal. New cases cover offset/edge-aligned rectangles,
global/local palettes, transparency versus untouched pixels, background selection,
unused invalid background indices and thin/interlaced pass boundaries. All LZW,
palette and full-canvas cases remain. Shared dispatch passes 534 memory pairs plus
five controls and 59 file cases plus three boundaries/100 low-descriptor cycles.
Memory lanes include forced Metal; file IO remains CPU/JS evidence. Hashes are in
[evidence/gif-geometry.json](evidence/gif-geometry.json).

Scoped review: I114 MATCH (`src/gif.bend`, rectangle/background/pass mapping);
A4/A5 HOLD through source/native lane gates; A6 HOLD in [GIF.md](GIF.md); V2 HOLD
through complete linked native pixels, including the observed background quirk;
V3 HOLD through positive rectangle/canvas bounds, palette checks, rectangle-sized
LZW output and bounded source/destination indices. Animation/disposal/timing,
zero-area/malformed recovery, metadata and full resource/platform/performance
remain gaps. Loading mappings remain partial.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, as do all
four proofs, eleven harness/planning tests and project checks. GPU filesystem IO
and remaining targets were not exercised.

Regression scan: 80 callers checked, 31 assertions checked, 0 flagged/fixed.

Hosted confirmation for `3a9bbe6`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36314847272)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36314847235)
passed, including GIF geometry/interlacing and native background fills.

## Bounded owned GIF animation memory decoding

`Image.Animation.decode_gif` returns ordered, independently owned RGBA8 Surfaces
with logical canvas dimensions and a frame count. Caller frame/pixel budgets are
checked before retaining each frame. `entries` consumes the animation to expose
its frames; `unload` consumes it for disposal. Native delays are discarded by the
reference API and are not added to this mapping.

Disposal 0/1 retains the canvas; disposal 2 restores the affected rectangle from
its pre-frame snapshot. Transparent pixels preserve prior canvas content on later
frames. The implementation retains global/local palette and control persistence,
including native background fill restoring a global entry's opacity for a later
frame without a new control extension. That state distinction was identified in
review and is covered by an actual native multi-frame fixture.

The animation gate passes 9 native animations / 24 frames / 382 pixels on CPU,
JavaScript and forced Metal, checking every frame/count/dimension. Ten error/budget
controls cover exact limits, exhaustion, zero/oversized requests, invalid later
frames and termination. Two ownership controls verify independent frame mutation
and consuming disposal. First-frame GIF retains all 41 images / 5,410 pixels and
23 controls; shared dispatch retains 534 memory and 59 file cases, including the
existing descriptor-closure cycles. See
[evidence/gif-animation.json](evidence/gif-animation.json).

Scoped drift review: I115 MATCH (owned animation, budgets and retain/restore);
A3 HOLD through native sequence checks and independent frame mutation; A4/A5 HOLD
through source/native backend gates; A6 HOLD in [GIF-ANIMATION.md](GIF-ANIMATION.md);
V2 HOLD through complete `LoadImageAnimFromMemory` output; V3 HOLD through validated
frame geometry, budgets and bounded snapshot/render indices. Disposal 3 remains
excluded because the pinned native path computes a pointer preceding its output
allocation. Generic non-GIF fallback, file animation loading, metadata/native ABI,
malformed recovery and complete resource/platform/performance remain gaps.

The ledger adds one partial mapping for `raylib:function:LoadImageAnimFromMemory`:
**105 core + 142 math partial functions**, still zero complete. All 261 scenarios /
40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal with current ledger metadata.
All four proofs, eleven harness/planning tests and project checks pass. GPU file
IO and remaining targets were not exercised.

Regression scan: 101 callers checked, 47 assertions checked, 1 flagged/fixed.

Hosted confirmation for `ea0b76b`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36318182028)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36318181912)
passed, including owned GIF frames and budget/ownership controls.

## Generic animation memory dispatch

`Image.Animation.decode_image` and `decode_image_for` select complete GIF frame
sequences only for exact `.gif`/`.GIF` tokens. Other supported tokens decode one
owned RGBA8 frame through the existing image decoder. GIF content under `.png`
therefore yields its first frame, matching native fallback behavior. PSD fallback
uses the explicit reference or the uncontracted convenience default.

The gate passes 20 native inputs / 37 frames / 460 pixels on CPU/JavaScript/forced
Metal, plus fifteen token/budget/error controls, two ownership controls and a
default-arithmetic check. Static native fallback images are normalized to RGBA8
before reading their pixels; the reference initially retained grayscale/RGB
storage, and that oracle interpretation was corrected before accepting results.
Source/input/native hashes are in
[evidence/animation-memory.json](evidence/animation-memory.json).

Scoped review: I116 MATCH (exact token selection and single-frame fallback);
A3 HOLD through consuming ownership and independent frames; A4/A5 HOLD through
source/native backend gates; A6 HOLD in [GIF-ANIMATION.md](GIF-ANIMATION.md);
V2 HOLD through complete normalized native frames; V3 HOLD through retained GIF
bounds and validated fallback retention budgets. Disposal 3, remaining codec
profiles, animation file loading and native ABI/resource/platform/performance
coverage remain gaps. The existing partial memory-animation mapping expands;
counts remain 105 core and 142 math partial functions, zero complete.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, eleven harness/planning tests and project checks pass. GPU filesystem IO
and remaining targets were not exercised.

Regression scan: 9 callers checked, 19 assertions checked, 1 flagged/fixed.

## Owned animation file loading

`Image.Animation.load_image` and `load_image_for` add ordinary-file loading with
case-insensitive GIF suffix selection. All other suffixes retain single-image
token/content dispatch. The implementation shares one complete-read/closed-handle
byte boundary with Surface loaders, retaining raster/QOI byte caps and typed
file/decode failures. Animation budgets apply before retaining frames; convenience
PSD arithmetic remains uncontracted.

The file gate passes 34 native cases / 61 frames / 604 pixels on CPU/JavaScript,
with seven boundary controls, an exact default-reference check and 100 cycles
under a 64-descriptor limit. Cases cover all GIF letter-case combinations,
directory-qualified dotfiles, multiple dots, static and cross-extension fallback,
native failures and frame/pixel exhaustion. Closure cycles exercise success,
budget, decode, read and byte-size failures. Existing Surface file loading retains
59 native cases, three boundaries and its 100 low-descriptor cycles; the shared
pure contract retains incomplete-read rejection. Evidence is in
[evidence/animation-files.json](evidence/animation-files.json).

Scoped review: I117 MATCH (suffix normalization and shared byte-file boundary);
A3 HOLD through consuming results/closed handles; A4/A6 HOLD through source checks
and documented contracts; V2 HOLD through every native frame/count/dimension;
V3 HOLD through complete bounded reads and retained image/animation budgets.
Disposal 3, other codec profiles, original metadata/ABI, callbacks and concurrent/
special-file behavior remain gaps. GPU filesystem IO and complete resource/
platform/performance coverage were not exercised.

The ledger adds one partial mapping for `raylib:function:LoadImageAnim`, bringing
the count to **106 core + 142 math partial functions**, with zero complete APIs.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. The
updated byte-read contract, all four proofs, eleven harness/planning tests and
project checks pass.

Regression scan: 33 callers checked, 24 assertions checked, 0 flagged/fixed.

Hosted confirmation for `504b450`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36320180961)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36320180953)
passed. The verified animation-file batch was subsequently published as `d28023f`.

## Owned raw Radiance RGBE float images

`Image.FloatRGB.decode_hdr` adds raw Radiance RGBE decoding into independently
owned Jonmath-vector storage. `entries` consumes the image to expose dimensions
and row-major vectors; `unload` consumes the owner. The typed path preserves native
format-9 RGB F32 samples instead of normalizing to RGBA8.

RGBE exponent zero becomes black; otherwise `channel*2^(exponent-136)` is exactly
representable across the byte domain. The decoder constructs F32/Word carrier
bits from integers, preserving subnormals without backend underflow arithmetic.
The gate compares **all 65,536 channel/exponent pairs** with actual native HDR
float storage on CPU/JavaScript/forced Metal, plus 10 images / 8,225 RGB pixels,
thirteen typed-error controls and consuming ownership. Header signatures,
metadata, decimal/layout parsing, raw-marker boundaries and 4,096-pixel axes are
covered. Every returned component is compared as an exact F32 word.

Scoped review: I118 MATCH (`src/hdr.bend` and `Image.FloatRGB`); A3 HOLD through
owned entries/unload; A4/A5 HOLD through source/native bitwise backend gates;
A6 HOLD in [HDR.md](HDR.md) and retained Nicolas Schulz/stb attribution; V2 HOLD
through complete native samples and exhaustive conversion; V3 HOLD through
bounded lines, validated dimensions and complete required samples before output
allocation. RLE, shared float/file dispatch, RGBA8 conversion, broader headers/
recovery and complete resource/platform/performance remain gaps. Evidence is in
[evidence/hdr-raw.json](evidence/hdr-raw.json). Existing mapping scope expands;
counts remain 106 core and 142 math partial functions, zero complete.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, as do all
four proofs, eleven harness/planning tests and project checks. Float file IO,
remaining targets and broader resource/performance behavior were not exercised.

Regression scan: 50 callers checked, 20 assertions checked, 1 flagged/fixed.

## Radiance RGBE scanline RLE

`Image.FloatRGB.decode_hdr` now accepts native four-plane scanline RLE for widths
8..4096, retaining raw fallback at the first row. Literal/repeat counts are checked
against the remaining plane; row headers must carry the declared width. A bounded
packed scanline is reused and converted to exact float pixels after each row.
Zero counts, overruns and mismatched widths reject before output writes.

The gate passes 18 native images / 17,859 RGB pixels, twenty-one error controls,
consuming ownership and the retained exhaustive 65,536 channel/exponent comparison
on CPU/JavaScript/forced Metal. Cases cover literal/repeat mixtures, packet lengths
through 128, row/plane transitions, widths 8/9/127/128/129/256/4096 and extreme
exponents. The previous unsupported-RLE control now exercises truncated encoded
input; valid RLE rows are compared with native float storage. Hashes are in
[evidence/hdr-rle.json](evidence/hdr-rle.json).

Scoped review: I119 MATCH (scanline/plane parsing and exact conversion); A3 HOLD
through owned output; A4/A5 HOLD through source/native backend gates; A6 HOLD in
[HDR.md](HDR.md); V2 HOLD through complete float bits and unchanged scalar-domain
expectations; V3 HOLD through row/packet bounds and bounded packed/output arrays.
The scan clarified raw preallocation checks versus compressed per-packet checks.
Later-row fallback, shared float dispatch/file loading, RGBA8 conversion and full
resource/platform/performance remain gaps. API statuses remain partial.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, as do all
four proofs, eleven harness/planning tests and project checks. Float file IO,
remaining targets and broader resource/performance behavior were not exercised.

Regression scan: 36 callers checked, 28 assertions checked, 1 flagged/fixed.

## Native later-row HDR raw reset

When a later HDR scanline lacks the native RLE marker, decoding now restarts at
pixel zero using a complete raw canvas from that point. The existing output owner
is overwritten, including previously decoded RLE rows. The four marker-candidate
bytes become the first raw pixel. Replacement data must cover the full canvas;
short native recovery is rejected rather than exposing uninitialized samples.

The gate passes 22 native images / 17,939 RGB pixels, twenty-one error controls,
consuming ownership and all 65,536 channel/exponent pairs on CPU/JS/Metal. Added
cases replace one or two encoded rows and exercise high-bit marker rejection.
The earlier unsupported-fallback control now checks the required replacement
length. All valid raw/RLE cases retain complete native float-bit comparison. See
[evidence/hdr-fallback.json](evidence/hdr-fallback.json).

Scoped review: I120 MATCH (reset state and complete canvas replacement); A3 HOLD
through reused owned output; A4/A5 HOLD through native/source backend gates;
A6 HOLD in [HDR.md](HDR.md); V2 HOLD through actual native reset behavior and exact
float words; V3 HOLD through full replacement-length validation and bounded
origin-based writes. Broader headers/recovery, float file/dispatch/conversion and
complete resource/platform/performance remain gaps. API statuses remain partial.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, as do all
four proofs, eleven harness/planning tests and project checks. Float file IO and
remaining targets/resource/performance profiles were not exercised.

Regression scan: 26 callers checked, 28 assertions checked, 0 flagged/fixed.

## Explicit HDR float file loading

`Image.FloatRGB.load_hdr` selects the Radiance decoder independently of filename,
using the shared complete-read/closed-handle file boundary with a 1 MiB byte cap.
It returns owned RGB float storage and preserves typed file/decode/size errors.

The file gate passes 26 native cases / 18,035 pixels on CPU/JavaScript, including
three explicit-selection cases. Ordinary `.hdr`/`.HDR` files use native
`LoadImage`; mixed/absent/other suffixes use native file bytes and explicit `.hdr`
memory selection. Five error/size controls and 100 success/decode/read/size cycles
under a 64-descriptor limit pass. Every channel is compared as its exact native
F32 word. Evidence is in [evidence/hdr-files.json](evidence/hdr-files.json).

Scoped review: I121 MATCH (explicit codec, byte cap and shared IO); A3 HOLD through
owned returns/closed handles; A4/A6 HOLD through source checks and [HDR.md](HDR.md);
V2 HOLD through exact native file samples; V3 HOLD through the established byte
boundary and decoder bounds. The scan removed stale file-loader gap wording that
belonged to the separate animation API. Shared float dispatch/conversion, GPU file
IO, callbacks and concurrent/special-file/native-ABI/resource/platform behavior
remain gaps. Existing loading scope expands without changing API statuses.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, as do all
four proofs, eleven harness/planning tests and project checks.

Regression scan: 14 callers checked, 15 assertions checked, 2 flagged/fixed.

## Hosted aggregate budget

The [raw-HDR run for e6bceeb](https://github.com/jonathanperis/jonlib/actions/runs/36322504936)
was cancelled at the 20-minute job deadline on both Ubuntu and macOS. HDR itself
passed in 52/54 seconds, followed by the complete image-memory gate; cancellation
occurred during the existing filtered-resize gate, with later steps skipped.
This is partial hosted evidence, not a successful full workflow.

The aggregate budget is now 30 minutes for the expanded serial suite. Individual
compiler/runtime limits, native comparisons, expected results and all workflow
steps are retained. The next published checkpoint must complete both hosted jobs
before full hosted success is recorded.

## RGB float conversion and stack-bounded image exports

`Surface.to_float_rgb` preserves native format-7/9 byte normalization and drops
alpha. `Image.FloatRGB.to_surface` accepts finite `[0,1]` RGB, including signed
zero/subnormals, then uses native F32 multiply-and-truncate conversion with opaque
alpha. Failed conversion returns the original float owner. Bit-domain validation
rejects negative subnormals even on a flushing GPU backend.

The gate passes every byte normalization, 769 quantization-boundary pixels,
33,024 HDR-derived pixels and seven rejected-owner cases on CPU/JS/Metal. Native
`ImageFormat` supplies exact float words and complete RGBA output. The large
float and Surface exports are both observed in full. See
[evidence/float-rgb.json](evidence/float-rgb.json).

The initial JS run overflowed in pinned Base `List.take` inside Surface colors,
after conversion succeeded. A diagnostic stack trace identified the actual call.
Five image-owned prefix sites now use a shared tail-recursive implementation;
the original large input, native comparisons and runtime limits were retained.
Affected format regressions pass: 109 complete format cases / 3,192 bytes,
42 packed-dither outputs, 4,563 pixel-size observations and 25 raw-file cases with
five boundaries/100 closure cycles. Small bounded codec-table uses of Base's
Data-list prefix operation are unchanged.

Scoped drift review: I122/I124 MATCH (native conversion, owner return and bounded
exports); A3 HOLD through rejected-owner checks; A4/A5 HOLD through native/source
backend gates; A6 HOLD in [FLOAT-RGB.md](FLOAT-RGB.md); V2 HOLD through exact
`ImageFormat` results; V3 HOLD through bit-domain and logical-length bounds.
Other float/half/compressed formats, unrestricted HDR-to-byte conversion, mipmaps
and complete resource/platform/performance remain gaps. API counts stay 106 core
and 142 math partial functions, zero complete.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, eleven harness/planning tests and project checks pass. Remaining targets,
unrestricted float casts and full resource/performance coverage were not exercised.

Regression scan: 52 callers checked, 19 assertions checked, 1 flagged/fixed.

Hosted confirmation for `a2de7d6`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36323996244)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36323996215)
passed. The complete jobs took 25m01s on Ubuntu and 22m35s on macOS, validating the
30-minute aggregate budget with all individual checks retained. This checkpoint
also includes HDR RLE, native canvas-reset behavior and float file loading.

## RGB float raw-byte interoperability

`Image.FloatRGB.from_bytes` and `to_bytes` add exact little-endian format-9 storage
for every non-NaN F32 class. Import checks dimensions, exact length, byte ranges
and each raw word before constructing floats. Export shares the owned validation
traversal with normalized conversion and returns the original image on NaN
rejection. Signed zero, negative/positive finite values, subnormals and infinities
preserve their bits. Pinned JS canonicalizes NaN signs/payloads, so those raw words
are explicitly outside this profile.

The gate passes 1,539 native format-9 raw pixels, exact byte round trips, 3,072
defined normalized native RAW export bytes, eight malformed/NaN controls and
retained-owner checks on CPU/JS/Metal. The existing byte normalization, 769 float
boundaries, 33,024 HDR pixels and seven conversion rejections also pass after
sharing validation. See [evidence/float-rgb-bytes.json](evidence/float-rgb-bytes.json).

Scoped review: I125 MATCH (raw word validation, exact layout and owner return);
A3 HOLD through rejected-owner checks; A4/A5 HOLD through source/native backend
gates; A6 HOLD in [FLOAT-RGB-BYTES.md](FLOAT-RGB-BYTES.md); V2 HOLD through actual
`LoadImageRaw` storage and defined native RAW export; V3 HOLD through checked
dimensions/lengths/bytes, pre-construction NaN rejection and bounded indexing.
Float raw-file APIs, NaN payload parity, other layouts and complete native ABI/
resource/platform/performance remain gaps. API statuses remain partial.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, eleven harness/planning tests and project checks pass. Remaining targets,
raw NaN parity and complete resource/performance coverage were not exercised.

Regression scan: 23 callers checked, 29 assertions checked, 0 flagged/fixed.

Hosted confirmation for `00933a4`: [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36325566236)
passed, including native float conversion and stack-bounded large exports. The
verified raw-byte interoperability batch was subsequently published as `f369aee`.

## RGB float RAW file interoperability

`Image.FloatRGB.load_raw` and `write_raw` add format-9 file IO. The load path shares
bounded positional byte reads with the formatted loader, retaining native
fitting-header/fallback-to-zero behavior and signed-int request/file bounds.
Handles close before decoding; short reads retain `TruncatedRawImage`, while
unsupported NaN payloads return `InvalidRawRequest` after closure.

Writes consume valid owners into exact little-endian words. `FloatRGBSampleError`
returns a rejected NaN owner before opening the path; `FloatRGBFileError` preserves
Base file errors. The gate checks an existing sentinel file remains unchanged on
sample rejection, alongside the returned owner and a directory write failure.

Sixteen native RAW load/header cases, nine controls and 100 low-descriptor cycles
pass on CPU/JS. Every output file matches native loaded storage; four normalized
cases additionally use actual native `ExportImage(.raw)` where its auxiliary color
casts are defined. Previous byte/integer RAW loading/export retains all 25 cases,
five controls and 100 closure cycles. A pure short-read contract covers the shared
byte-result boundary. See
[evidence/float-rgb-raw-files.json](evidence/float-rgb-raw-files.json).

Scoped review: I126 MATCH (shared RAW reads, exact float writes and typed owners);
A3 HOLD through rejection/sentinel/closure checks; A4/A6 HOLD through source gates
and [RAW-FILES.md](RAW-FILES.md); V2 HOLD through native loaded words and defined
export bytes; V3 HOLD through request arithmetic, selected payload lengths and
existing sample validation. NaN raw-bit parity, native auxiliary out-of-range
casts, GPU file IO, callbacks/special files and complete resource/platform/native-
ABI/performance coverage remain gaps. API statuses remain partial.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, including
the updated pure RAW short-read contract. All four proofs, eleven harness/planning
tests and project checks pass. GPU file IO and remaining targets/resource profiles
were not exercised.

Regression scan: 38 callers checked, 27 assertions checked, 0 flagged/fixed.

## RGB float copying and lossless orientation

`Image.FloatRGB.copy`, horizontal/vertical flips and clockwise/counterclockwise
quarter-turns preserve native format-9 sample words. Copy returns independent
owned storage; flips retain dimensions and quarter-turns swap them. The sampling
loop now accepts Data elements, sharing established indices between U32 Surface
pixels and Jonmath RGB vectors. Existing Surface sampling calls retain their
interface and index arithmetic.

The gate passes 43 native cases / 14,953 pixels and independent-copy mutation on
CPU/JS/Metal. It covers rectangular/thin/single-pixel shapes, signed zero,
subnormal/extreme/non-NaN values, repeated quarter-turns and operation chains.
Each complete native word stream and output dimensions are compared. See
[evidence/float-rgb-transforms.json](evidence/float-rgb-transforms.json).

Scoped review: I127 MATCH (copy ownership and lossless orientation); A3 HOLD through
independent mutation; A4/A5 HOLD through source/native backend gates; A6 HOLD in
[FLOAT-RGB.md](FLOAT-RGB.md); V2 HOLD through actual native format-9 copy/flip/rotate
output; V3 HOLD through existing logical-size invariants and established mapped
indices. NaN payload parity, mipmaps/other formats and complete resource/platform/
performance remain gaps. Five existing partial mappings expand; statuses stay
106 core and 142 math partial functions, zero complete.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, including
the existing Surface sampling/orientation contracts. All four proofs, eleven
harness/planning tests and project checks pass. Remaining targets, NaN payload
parity and complete resource/performance coverage were not exercised.

Regression scan: 26 callers checked, 8 assertions checked, 0 flagged/fixed.

## RGB float rectangular extraction and crop

`Image.FloatRGB.extract` retains its source and returns an independent positive
integral in-bounds region. `crop` uses the established clipped integral profile,
preserving native unchanged-source behavior for origins strictly beyond the
image. Unsupported rectangles return their source owners. Surface and FloatRGB
now share the same clipping arithmetic before their typed sampling paths.

The gate passes 15 native rectangles / 167 pixels, eight complete retained-owner
cases and independent extracted-region mutation on CPU/JS/Metal. It covers full,
inner, edge and thin regions, clipped negative origins, oversized extents and
strictly-outside no-ops. All returned metadata and sample words match actual
`ImageFromImage`/`ImageCrop` format-9 output. See
[evidence/float-rgb-crop.json](evidence/float-rgb-crop.json).

Scoped review: I128 MATCH (regions, clipping and retained failures); A3 HOLD through
source/region checks; A4/A5 HOLD through source/native backend gates; A6 HOLD in
[FLOAT-RGB.md](FLOAT-RGB.md); V2 HOLD through complete native rectangle output;
V3 HOLD through integral/in-bounds validation and established Region indices.
Fractional/native-invalid geometry, NaN payload parity, mipmaps and full resource/
platform/performance remain gaps. Two existing partial mappings expand without
changing completion counts.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, including
retained Surface crop/region contracts. All four proofs, eleven harness/planning
tests and project checks pass. Remaining targets and broader geometry/resource/
performance domains were not exercised.

Regression scan: 13 callers checked, 14 assertions checked, 0 flagged/fixed.

## Native quantized RGB float nearest resizing

`Image.FloatRGB.resize_nn` follows native format-9 behavior through RGBA8
truncation, plus-one 16.16 nearest mapping and float normalization. Same-size
requests retain that quantization: a native `0.5` channel becomes `127/255`.
Finite `[0,1]` source samples and bounded safe target mappings are supported;
failures return the original unquantized float owner.

The conversion traversal now retains its read-only source beside the byte output
until the resize completes. This preserves failure ownership without cloning the
source solely for recovery. Existing `to_surface` drops that source only on its
successful consuming path.

The gate passes 24 native cases / 1,854 pixels and five complete retained-owner
checks on CPU/JS/Metal, covering up/down/same-size/thin cases, byte-boundary floats,
invalid sizes, unsafe mapping axes and unsupported source values. The native
conversion/large-export gate retains all prior results after the traversal change.
See [evidence/float-rgb-nearest.json](evidence/float-rgb-nearest.json).

Scoped review: I129 MATCH (native quantization and owner recovery); A3 HOLD through
complete source comparisons, including failures after byte conversion; A4/A5 HOLD
through source/native backend gates; A6 HOLD in [FLOAT-RGB.md](FLOAT-RGB.md);
V2 HOLD through complete native format-9 words; V3 HOLD through bit-domain, size
and existing nearest-index checks. Out-of-range casts, unsafe native mappings,
other formats/mipmaps and complete resource/platform/performance remain gaps.
API statuses remain partial.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, including
the existing Surface nearest and conversion contracts. All four proofs, eleven
harness/planning tests and project checks pass. Remaining targets and unrestricted
numeric/resource/performance domains were not exercised.

Regression scan: 17 callers checked, 21 assertions checked, 0 flagged/fixed.

## Native quantized RGB float filtered resizing

`Image.FloatRGB.resize` follows the format-9 reference fallback through RGBA8
truncation, default four-channel filtering and float normalization. Same-size
calls still quantize. The filtered and nearest APIs share source-retaining
dispatch, preserving the original owner on unsupported samples or dimensions.

The filtered gate passes 26 native cases / 2,878 pixels and three complete
retained owners on CPU/JS/Metal. Nearest retains all 24 cases / 1,854 pixels and
five owner controls. The underlying Surface filter gate passes 529 images /
46,474 pixels, 2,601 exact kernels and 1,059 normalization vectors / 6,470 exact
coefficient bits across the same lanes. See
[evidence/float-rgb-filtered.json](evidence/float-rgb-filtered.json).

Scoped review: I130 MATCH (native quantized filtering and shared recovery);
A3 HOLD through complete owner comparisons; A4/A5 HOLD through source/native
backend gates; A6 HOLD in [FLOAT-RGB.md](FLOAT-RGB.md); V2 HOLD through actual
`ImageResize` words and retained coefficient/pixel oracles; V3 HOLD through
existing sample-domain, dimension and filter bounds. The planning test's exact
legacy `ImageResize` mapping assertion was updated to include the verified float
API and the suite rerun. Other domains/formats/mipmaps and complete resource/
platform/performance remain gaps. Completion counts remain unchanged.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, eleven harness/planning tests and project checks pass. Remaining targets
and unrestricted numerical/resource/performance domains were not exercised.

Regression scan: 16 callers checked, 20 assertions checked, 1 flagged/fixed.

## Native RGB float canvas and POT behavior

`Image.FloatRGB.resize_canvas` and `to_pot` preserve non-NaN sample words during
bounded region moves. Native format 9 leaves newly allocated fill pixels at zero:
`SetPixelColor` has no float-format case. Same-size requests retain the original
image for in-profile offsets. Surface and FloatRGB share Data-typed copying and
overlap geometry; RGBA8 keeps its existing fill semantics.

The gate passes 18 native cases / 4,277 pixels and six complete retained-owner
controls on CPU/JS/Metal. Cases cover signed-zero/subnormal/extreme values,
positive/negative/clipped offsets, ignored fill colors, unchanged-size offsets
and thin/POT dimensions. A local native probe also confirmed the existing
next-power-of-two calculation over all 4,096 supported axis sizes. Evidence is in
[evidence/float-rgb-canvas.json](evidence/float-rgb-canvas.json).

Scoped review: I131 MATCH (lossless moves, zero fill and POT); A3 HOLD through
retained owners; A4/A5 HOLD through source/native backend gates; A6 HOLD in
[FLOAT-RGB.md](FLOAT-RGB.md); V2 HOLD through actual format-9 canvas/POT words;
V3 HOLD through bounded sizes/offsets, positive overlap and shared copy indices.
Empty/unsafe native overlap domains, NaN payload parity, other formats/mipmaps
and complete resource/platform/performance remain gaps. API statuses remain partial.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, including
the existing RGBA8 canvas/POT contracts. All four proofs, eleven harness/planning
tests and project checks pass. Remaining targets and broader geometry/resource/
performance domains were not exercised.

Regression scan: 19 callers checked, 12 assertions checked, 0 flagged/fixed.

## Native RGB float color transforms

Float tint/invert/contrast/brightness/replacement now follow native format-9
paths through RGBA8 truncation, existing Surface operations and RGB normalization.
Nominal no-ops still quantize. Contrast is finite/clamped; brightness is finite
integral/clamped, including native negative-underflow-to-one behavior. Replacement
matches alpha 255 from float input, while replacement/tint alpha is discarded on
conversion back to RGB. Unsupported values/parameters retain original owners.

The gate passes 44 native cases / 17,050 pixels and six complete retained-owner
controls on CPU/JS/Metal, covering clamping, byte boundaries, alpha distinctions,
operation chains and nonfinite/fractional/subnormal parameter rejection. Surface
contrast/brightness use the same transform construction, preserving arithmetic
order. See [evidence/float-rgb-color.json](evidence/float-rgb-color.json).

Scoped review: I132 MATCH (native quantized color paths and rejection); A3 HOLD
through complete source comparisons; A4/A5 HOLD through source/native backend
gates; A6 HOLD in [FLOAT-RGB.md](FLOAT-RGB.md); V2 HOLD through actual format-9
color-operation words; V3 HOLD through existing image bounds and bit-checked
numeric domains. Direct grayscale conversion, other formats/mipmaps and complete
resource/platform/performance remain gaps. Five existing partial mappings expand;
completion counts remain unchanged.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, including
existing Surface color contracts. All four proofs, eleven harness/planning tests
and project checks pass. Remaining targets and broader numeric/resource/
performance domains were not exercised.

Regression scan: 15 callers checked, 9 assertions checked, 0 flagged/fixed.

## Direct RGB float formats and grayscale

`Image.FloatRGB.to_formatted` converts finite `[0,1]` RGB directly to native
formats 1..7 with alpha one. `color_grayscale` returns format-1 storage. Both
retain the original float owner on unsupported targets or samples. The direct
path preserves float precision until final encoding rather than first producing
RGBA8 bytes.

The gate passes nine native cases / 5,758 pixels and four retained-owner controls
on CPU/JavaScript/forced Metal. It covers 530 packed-boundary values and 1,024
targeted grayscale-boundary pixels. Two explicit counterexamples require zero
where F32 add-half/floor gives one; shared packed-channel rounding now rounds the
already-rounded product, matching native `round`. All 109 existing format cases /
3,192 bytes retain their exact results. Evidence is in
[evidence/float-rgb-formats.json](evidence/float-rgb-formats.json).

Scoped review: I133 MATCH (direct formats, grayscale storage and rounding);
A3 HOLD through complete retained-owner comparisons; A4/A5 HOLD through native
and source gates on all three lanes; A6 HOLD in [FLOAT-RGB.md](FLOAT-RGB.md);
V2 HOLD through actual `ImageFormat`/`ImageColorGrayscale` outputs and distinguishing
rounding controls; V3 HOLD through validated target/sample domains and existing
logical pixel bounds. Other float/half/compressed targets, unrestricted casts,
mipmaps and complete resource/platform/performance remain gaps. Two existing
partial mappings expand; completion counts remain unchanged.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, eleven harness/planning tests and project checks pass. Remaining targets,
unrestricted float casts and full resource/performance coverage were not exercised.

Regression scan: 15 callers checked, 16 assertions checked, 1 flagged/fixed.

Hosted confirmation for `1df7f0b`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36334349034)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36334349047)
passed, including canvas/POT and color transforms. Ubuntu took 19m30s and macOS
29m34s. The next checkpoint's aggregate budget is 35 minutes to accommodate the
added direct-format, normalization and channel gates. Individual subprocess
limits and native comparisons are retained; that new hosted checkpoint is pending.

## Byte and packed formats to RGB floats

`Image.Formatted.to_float_rgb` consumes checked format-1..7 images and produces
native format-9 sample words directly. Grayscale replicates into RGB, alpha is
discarded, and packed channels preserve reciprocal-multiply normalization without
intermediate byte quantization.

The gate passes seven source formats / 1,792 pixels and fourteen native float/
return-chain results on CPU/JavaScript/forced Metal. Inputs span every source
channel level and alpha pattern. Return chains use the verified direct float
encoder and compare complete native bytes, including discarded alpha. See
[evidence/formatted-float.json](evidence/formatted-float.json).

Scoped review: I134 MATCH (`Image.Formatted.to_float_rgb` and existing decode
arithmetic); A3 HOLD through consuming source ownership and bounded output;
A4/A5 HOLD through source/native backend gates; A6 HOLD in [FORMATS.md](FORMATS.md);
V2 HOLD through complete native normalization and return chains; V3 HOLD through
the existing checked-owner dimensions and logical traversal. Other source
formats/mipmaps, native allocation ABI and complete resource/platform/performance
remain gaps. Existing partial mapping scope expands without changing counts.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, eleven harness/planning tests and project checks pass. Other source formats,
remaining targets and full resource/performance coverage were not exercised.

Regression scan: 5 callers checked, 8 assertions checked, 0 flagged/fixed.

## Native grayscale channels from formatted and float images

`Image.Formatted.from_channel` and `Image.FloatRGB.from_channel` retain source
ownership and return independent native grayscale storage. Selection follows each
format's actual rules: gray-alpha redirects positive selectors to alpha, while
RGB formats redirect selectors above two to red. Selected samples use normalized
F32 multiplication/truncation, preserving packed-channel precision.

The gate passes 48 native cases / 15,366 grayscale pixels on CPU/JS/Metal, with
complete source-word comparisons, seven rejected-owner controls and two independent
output mutations. Fixtures cover source channel levels, float boundaries and
selector redirection; failed selectors and float domains retain source contents.
See [evidence/image-channels.json](evidence/image-channels.json).

Scoped review: I135 MATCH (selection, native format-1 output and retained owners);
A3 HOLD through source and independent-output checks; A4/A5 HOLD through source/
native backend gates; A6 HOLD in [IMAGE-CHANNELS.md](IMAGE-CHANNELS.md); V2 HOLD
through actual `ImageFromChannel` bytes; V3 HOLD through checked selectors,
sample domains and bounded logical traversal. Other domains/formats/mipmaps and
complete native-ABI/resource/platform/performance remain gaps. Existing partial
mapping scope expands without changing counts.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal, including
existing Surface channel contracts. All four proofs, eleven harness/planning
tests and project checks pass. The 35-minute hosted budget awaits the published
run; remaining targets and broader source/resource/performance domains were not
exercised.

Regression scan: 15 callers checked, 14 assertions checked, 0 flagged/fixed.

## Native formatted and float color observations

`Image.Formatted.colors/get` and `Image.FloatRGB.colors/get` add native bulk and
point RGBA observations. Packed inputs use integer expansion and conventionally
shifted RGB5A1 blue, preserving the distinction from raw `GetPixelColor` and
normalized `ImageFormat`. Float input uses checked multiply/truncate conversion.
Point reads retain source owners and validate only the selected pixel; bulk float
failure returns its original owner.

The gate passes eight layouts / 2,561 pixels as both native bulk and point colors
on CPU/JS/Metal. Every source word is retained after complete point traversal.
Six controls cover bounds, unsupported selected samples and a valid pixel beside
an unsupported float sample; bulk failure also retains its owner. The existing
float conversion gate passes its 256 byte normalizations, 769 boundary pixels,
33,024 HDR-derived pixels and seven rejection controls after sharing the pixel
helper. Evidence is in [evidence/image-colors.json](evidence/image-colors.json).

Scoped review: I136 MATCH (bulk/point semantics and ownership); A3 HOLD through
complete retained-source checks; A4/A5 HOLD through source/native backend gates;
A6 HOLD in [IMAGE-COLORS.md](IMAGE-COLORS.md); V2 HOLD through both actual native
observation APIs; V3 HOLD through pre-access bounds and selected float-domain
checks. Other source domains/formats/mipmaps and complete native-ABI/resource/
platform/performance remain gaps. Two partial mappings expand; counts stay fixed.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, eleven harness/planning tests and project checks pass. Remaining source
domains/targets and full resource/performance coverage were not exercised.

Regression scan: 28 callers checked, 18 assertions checked, 0 flagged/fixed.

## Native RGB float PNG memory/file split

`Image.FloatRGB.to_png` preserves the pinned memory API's raw storage-prefix
interpretation: one little-endian float word becomes one encoded RGBA pixel until
the logical canvas is filled. Non-NaN source words are supported. `write_png`
instead follows native file export through finite `[0,1]` color truncation and
opaque alpha. A `(0.5,0.25,0.75)` source decodes as `0000003f` from memory PNG and
`7f3fbfff` from file PNG; the gate retains that distinction explicitly.

Six memory profiles and five file profiles match 1,892 encoded bytes and 2,032
decoded RGBA bytes on CPU/JS/Metal. CPU/JS additionally compare actual files and
pass 100 success/rejection/file-error cycles with a 64-descriptor limit. Two pure
rejection controls preserve source words, and invalid writes leave a sentinel
file intact. The shared float writer retains all sixteen RAW file cases, nine
controls and 100 closure cycles. See
[evidence/float-rgb-png.json](evidence/float-rgb-png.json).

Scoped review: I137 MATCH (distinct native storage paths and typed writes);
A3 HOLD through returned owners/sentinel/closure controls; A4/A5 HOLD through
source/native pure backend gates; A6 HOLD in [PNG-EXPORT.md](PNG-EXPORT.md);
V2 HOLD through actual memory/file exports and full decoded pixels; V3 HOLD
through checked source domains, bounded raw-prefix indices and existing PNG
encoding bounds. GPU filesystem IO, NaN parity, other float layouts/generic
dispatch and complete native-ABI/resource/platform/performance remain gaps.
Existing export mappings expand without changing completion counts.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, eleven harness/planning tests and project checks pass. GPU filesystem IO,
remaining source/target domains and full resource/performance coverage were not
exercised.

Regression scan: 22 callers checked, 20 assertions checked, 0 flagged/fixed.

Hosted confirmation for `38bec12`: [Checks](https://github.com/jonathanperis/jonlib/actions/runs/36336407675)
and [Ubuntu/macOS Conformance](https://github.com/jonathanperis/jonlib/actions/runs/36336407628)
passed. Ubuntu took 29m34s and macOS 31m46s, confirming the 35-minute aggregate
budget with every verification step retained. This includes direct formats,
reverse float normalization and native grayscale channels.

## RGB float BMP and TGA file export

`Image.FloatRGB.to_bmp/to_tga` produce native file bytes through checked RGB-to-
RGBA normalization; `write_bmp/write_tga` add typed, explicit-codec file IO.
Closed encoder templates share the conversion boundary with PNG. These pure
encoders adapt native `ExportImage`, not unsupported BMP/TGA memory dispatch.

Twelve native file profiles match 3,918 encoded bytes and 4,064 decoded RGBA bytes
on CPU/JS/Metal. CPU/JS files use `.dat` names to verify explicit codec selection.
Two rejected-owner and typed file-error controls, sentinel preservation and 100
low-descriptor success/rejection/error cycles pass. Float PNG retains all six
memory/five file profiles and closure controls; float RAW retains sixteen native
cases, nine controls and 100 closure cycles. Evidence is in
[evidence/float-rgb-raster-export.json](evidence/float-rgb-raster-export.json).

Scoped review: I138 MATCH (normalized native file codecs and typed ownership);
A3 HOLD through rejected owners/sentinel/closure checks; A4/A5 HOLD through source
and pure backend gates; A6 HOLD in [FLOAT-RASTER-EXPORT.md](FLOAT-RASTER-EXPORT.md);
V2 HOLD through actual native file bytes and complete decoded pixels; V3 HOLD
through established sample and encoder bounds. GPU filesystem IO, other domains/
formats/options/generic dispatch and complete native-ABI/resource/platform/
performance remain gaps. Existing export scope expands; counts remain unchanged.

All 261 scenarios / 40,101 words pass CPU-1/CPU-2/JavaScript/forced Metal. All four
proofs, eleven harness/planning tests and project checks pass. GPU filesystem IO
and broader source/target/resource/performance domains were not exercised.

Regression scan: 17 callers checked, 19 assertions checked, 0 flagged/fixed.

## Native image-as-code export

`Image.Formatted.to_code/write_code` preserve the complete native header template,
credits, uppercase basename/extension rules, metadata and unpadded hex formatting.
The initial profile supports formats 1..7, payloads through 65,536 bytes and
non-NUL ASCII basenames through 200 characters. Rejected inputs retain their
owners before opening files; typed file errors preserve Base details and close
opened handles.

The gate passes thirteen native files / 428,861 text bytes and seven retained-owner
controls on CPU/JS/Metal, including the largest payload and accepted basename,
native first-byte/twentieth-byte line breaks, leading/multiple dots and backslash
selection. CPU/JS additionally compare every actual file, preserve a sentinel on
rejected writes and pass 100 low-descriptor success/error cycles. See
[evidence/image-code.json](evidence/image-code.json).

Regression review found the proposed 255-character name could overrun native
`ExportImageAsCode`'s `payload*6+2000` allocation for a one-byte image. An ASan-linked
native reproducer confirmed heap-buffer-overflow in the exporter. The accepted
200-character profile leaves at least 134 bytes inside that estimate; the original
255-character case is now a rejected-input regression, and the accepted reference
executable runs with ASan. The earlier full-corpus run preceded this domain fix
and does not verify the corrected source. Details are in
[evidence/image-code-native-overflow.json](evidence/image-code-native-overflow.json).

Scoped drift review: I139 MATCH (`src/image_code.bend` and formatted wrappers);
C1/C3/C6 HOLD through Bend-only source gates and preserved provenance; A3 HOLD
through complete rejected owners, file preservation and closure; A4/A5 HOLD
through exact native text on CPU/JS/Metal; A6 HOLD in [IMAGE-CODE.md](IMAGE-CODE.md);
V2 HOLD through the narrowed defined native domain and sanitizer gate; V3 HOLD
through existing checked storage and bounded payloads. The ledger adds one
partial mapping for `raylib:function:ExportImageAsCode`: **107 core + 142 math**
partial functions, still zero complete. Broader filename/payload/Unicode domains,
configured line widths, GPU file IO and complete native-ABI/resource/platform/
performance coverage remain gaps.

The [79f7220 hosted run](https://github.com/jonathanperis/jonlib/actions/runs/36340369070)
hit the 35-minute aggregate deadline on both platforms, during filtered resizing
on Ubuntu and image-memory dispatch on macOS. No step failed before cancellation;
later steps were skipped. The aggregate budget is now 45 minutes. I123 MATCH for
the configuration; full hosted acceptance remains pending on the next publication.

The corrected source passes all 261 scenarios / 40,101 words on CPU-1/CPU-2/
JavaScript/forced Metal. All four proofs, eleven harness/planning tests and project
checks pass. GPU file IO and broader path/source/target/resource/performance
domains were not exercised; the 45-minute hosted checkpoint remains pending.

Regression scan: 29 callers checked, 19 assertions checked, 2 flagged/fixed.

## RGB float image-as-code export

`Image.FloatRGB.to_code/write_code` extend the native `ExportImageAsCode` profile
to format 9. They preserve dimensions, format metadata and all twelve raw
little-endian bytes per pixel, including signed zero, subnormals and infinities.
NaN samples and unsupported path/payload requests return the original owner;
`FloatCodeSourceError` retains it before file opening, while `FloatCodeFileError`
preserves Base code/message details. The formatter now accepts either affine
formatted bytes or reusable float bytes through its quantity parameter.

The combined gate compares **17 native files / 884,733 text bytes** on CPU,
JavaScript and forced Metal. All thirteen previous formatted-image cases remain,
with four format-9 cases spanning sign/exponent classes, deterministic raw words
and the largest accepted float payload (65,532 bytes). Ten rejected-owner controls
cover paths, payloads and a NaN after a valid pixel. CPU/JS compare every actual
file, verify sentinel preservation, compare native Base file-error details and
run 100 success/source-error/file-error cycles under a 64-descriptor limit.
The accepted native oracle remains linked with AddressSanitizer.

Scoped acceptance: A3 PASS for retained owners and bounded storage; A4 PASS for
Bend-only source and exact CPU/JS output; A5 PASS for pure forced-Metal output;
A6 PASS through [IMAGE-CODE.md](IMAGE-CODE.md), public API docs and the generated
ledger. GPU file IO, NaN payload parity, larger/Unicode paths and complete
native-ABI/resource/platform/performance domains remain gaps. This extends the
existing partial `raylib:function:ExportImageAsCode` mapping; counts remain
**107 core + 142 math partial functions, zero complete**.

Regression review corrected the evidence counter to include all five IO failure
controls; the unchanged comparisons passed again on all three lanes.

The full current-source gate passes **261 scenarios / 40,101 output words per
lane** on CPU-1, CPU-2, JavaScript and forced Metal, plus ownership/transform/decode
contracts, the three native-matching PPM examples and CPU/JS QOI file round trips.
All four proofs report `All terms check.`; all eleven harness/planning tests and
project checks pass. Current source hashes and focused/full-gate summaries are
recorded in [evidence/image-code.json](evidence/image-code.json). Hosted execution
of this uncommitted batch, including the inherited 45-minute job allowance,
remains unverified.

Regression scan: 32 callers checked, 31 assertions checked, 1 flagged/fixed.

## Owned RGBA8 mipmap chains

`Surface.mipmaps` consumes a checked single-level RGBA8 surface and preserves
native `ImageMipmaps` base-to-1x1 ordering. Each level resizes the preceding level,
with floor-halved dimensions clamped to one. `Image.Mipmaps.entries/unload`
provide consuming observation/disposal of independently owned levels.

The native gate passes **14 chains / 72 levels / 61,127 pixels per lane** on CPU,
JavaScript and forced Metal. It covers 1x1, POT/NPOT, odd/thin, both 4096-pixel axes,
a 33,153-pixel base, hidden RGB/alpha and three independent-level mutation cases.
The default resizer's implementation is unchanged. See
[MIPMAPS.md](MIPMAPS.md) and [evidence/mipmaps.json](evidence/mipmaps.json).

Scoped acceptance: A3 PASS through complete counts/dimensions/pixels and independent
owners; A4/A5 PASS through exact native CPU/JS/Metal comparisons and Bend-only
source gates; A6 PASS through API/provenance/compatibility docs and the generated
ledger; A26 PASS within the declared RGBA8 profile. The function mapping raises
core partial coverage from 107 to **108**, with 142 math partial functions and
zero complete. Existing native chains, other formats, texture integration and
complete native-ABI/resource/platform/performance remain gaps.

Regression review updated the previously single-level-only Image type mapping
and qualified broader mipmap gaps without claiming downstream integration.
The full mipmap checkpoint passes all 261 scenarios / 40,101 output words per
lane on CPU-1/CPU-2/JavaScript/forced Metal, plus contracts, three PPM examples
and CPU/JS QOI file round trips. All four proofs, eleven harness/planning tests
and project checks pass. Hosted execution of the uncommitted checkpoint remains
unverified.
Regression scan: 18 callers checked, 8 assertions checked, 2 flagged/fixed.

## Native RGBA8 Gaussian blur

`Surface.blur_gaussian` preserves the pinned four-pass-pair box approximation,
byte premultiplication, remove-before-add sliding sums, horizontal F32 values,
per-vertical-pass byte truncation and reverse premultiplication. Checked U32
sizes 0..min(width,height) include the native nonidentity zero-size behavior;
larger requests retain the original with `InvalidSize` before allocation.

The native gate passes **27 cases / 117,151 pixels per lane** and three retained
owners on CPU/JavaScript/forced Metal. Regression review replaced a redundant
both-axes size rejection with a width-only rejection, complementing the existing
height-only and maximum-U32 controls. The complete gate passed again unchanged
in its valid native inputs/comparisons. See [BLUR.md](BLUR.md) and
[evidence/blur.json](evidence/blur.json).

Scoped A3/A4/A5/A6/A26 acceptance PASS within this profile through complete native
pixels, independent axis guards, retained owners, source boundaries and public
documentation. The full checkpoint also passes 261 scenarios / 40,101 output
words per lane on CPU-1/CPU-2/JavaScript/forced Metal, all contracts/examples/file
round trips, four proofs, eleven harness/planning tests and project checks.
The ledger advances to **109 core + 142 math partial functions, zero complete**.
Other source formats/mipmaps, configured iterations, undefined native requests,
hosted execution and complete native-ABI/resource/platform/performance remain gaps.

Regression scan: 28 callers checked, 7 assertions checked, 1 flagged/fixed.

## Bounded native RGBA8 kernel convolution

`Surface.kernel_convolution` retains native flat unsigned-index sampling, including
row-edge wrapping, odd/even anchors, normalized F32 products and row-major sums.
RGB clamps independently; alpha conversion is accepted only in the defined
unsigned-byte truncation domain. Unsupported kernel shapes/coefficients or late
alpha failures return the complete unchanged source with `InvalidKernel`.

The focused native gate passes **39 cases / 34,650 pixels per lane** and nine
retained-owner controls on CPU/JavaScript/forced Metal. Empty/identity/box/signed
kernels, the 225-coefficient boundary, all channel bytes, large sources and both
positive/negative alpha boundaries are compared completely. See
[CONVOLUTION.md](CONVOLUTION.md) and [evidence/convolution.json](evidence/convolution.json).

Scoped A3/A4/A5/A6/A26 acceptance PASS within the documented profile. The ledger
advances to **110 core + 142 math partial functions, zero complete**. Wider
kernels/coefficient domains, undefined native alpha casts, other formats/mipmaps,
hosted execution and complete native-ABI/resource/platform/performance remain gaps.
The exhaustive transform error consumer and public error-constructor list include
`InvalidKernel`; workflow review retains the original perspective diagnostic as
a separate step from the new convolution gate.
The full checkpoint passes 261 scenarios / 40,101 output words per lane on
CPU-1/CPU-2/JavaScript/forced Metal, including the updated exhaustive error consumer,
all contracts/examples/file round trips, four proofs, eleven harness/planning tests
and project checks. Hosted execution remains unverified.

Regression scan: 31 callers checked, 8 assertions checked, 1 flagged/fixed.

## Bounded native Base64 utilities

`Base64.encode` preserves native alphabet/padding and the NUL-inclusive output
size while returning logical Bend text without its C terminator. `Base64.decode`
preserves first-NUL termination and ignored unused padding bits for nonempty
structured inputs, rejecting malformed/empty/oversized requests. Empty native
decoding is excluded because its padding scan reads before the input buffer.

The focused gate passes **30 native cases / 2,754,389 output bytes per lane**
and fourteen rejection controls on CPU/JavaScript/forced Metal, including the
1 MiB byte/output boundary. Full native text, size and decoded bytes are compared;
the undefined malformed domains are candidate-only controls. See
[BASE64.md](BASE64.md) and [evidence/base64.json](evidence/base64.json).

Scoped A4/A5/A6 acceptance PASS for these pure profiles. The ledger advances from
110 to **112 core partial functions**, alongside 142 math partial functions and
zero complete. Native malformed recovery, larger domains, pointer/allocation ABI,
hosted execution and complete resource/platform/performance remain gaps.

Regression scan: 24 callers checked, 8 assertions checked, 0 flagged/fixed.

The Base64 checkpoint additionally passes the full 261-scenario / 40,101-word
corpus on CPU-1/CPU-2/JavaScript/forced Metal, all contracts/examples/file round
trips, four proofs, eleven harness/planning tests and project checks.

## Native CRC32 and MD5 values

`Checksum.crc32/md5` validate immutable byte inputs through 1 MiB, preserve native
CRC complements and MD5 little-endian padding/rounds, and return immutable scalar
or four-word values. The CRC recurrence is reused without changing PNG export.

The focused gate passes **281 native/standard vectors** covering 1,194,258 input
bytes and three rejected-input controls on CPU/JavaScript/forced Metal. Every
single byte, standard/empty messages, padding/block boundaries, deterministic
random data and maximum input are included. All native results independently
match standard zlib/hashlib results. Five bounded programs per lane retain the
complete ordered comparison. See [CHECKSUMS.md](CHECKSUMS.md) and
[evidence/checksums.json](evidence/checksums.json).

Scoped A4/A5/A6 acceptance PASS for these profiles. Core partial coverage advances
from 112 to **114**, with 142 math partial functions and zero complete. Larger
inputs, big-endian native MD5, static-buffer/pointer ABI, hosted execution and
complete resource/platform/performance remain gaps. Workflow YAML parses and
retains every committed verification step alongside the new utility gates.
The full checkpoint passes 261 scenarios / 40,101 output words per lane on
CPU-1/CPU-2/JavaScript/forced Metal, all contracts/examples/file round trips,
four proofs, eleven harness/planning tests and project checks.

Regression scan: 34 callers checked, 10 assertions checked, 0 flagged/fixed.

## Native SHA-1/SHA-256 values

`Checksum.sha1/sha256` return exactly five/eight native-order U32 words from
checked byte inputs through 1 MiB. The SHA-256 implementation retains the pinned
four-byte padding-size rule and its overwritten marker/data at lengths 56..59
modulo 64. Standard SHA-256 is not substituted for these native outputs.

The focused gate passes **409 vectors / 1,202,386 input bytes** and three invalid
controls on CPU/JavaScript/forced Metal. It retains eleven native-versus-standard
SHA-256 differences, including all eight 0..127-byte counterexamples. Every
candidate word is compared with actual native output; independent standard
SHA-1 and nonquirk SHA-256 checks provide additional controls. See [SHA.md](SHA.md)
and [evidence/sha.json](evidence/sha.json).

Scoped A4/A5/A6 acceptance PASS. The full checkpoint passes 261 scenarios /
40,101 output words per lane on CPU-1/CPU-2/JavaScript/forced Metal, all
contracts/examples/file round trips, four proofs, eleven harness/planning tests
and project checks. Workflow parsing confirms every committed gate is retained.
The ledger advances to **116 core + 142 math partial functions, zero complete**.
Larger domains, other native compiler/integer-width profiles, static-pointer ABI,
hosted execution and complete resource/platform/performance remain gaps.

Regression scan: 41 callers checked, 13 assertions checked, 0 flagged/fixed.

## Native sdefl Huffman dependency

The private builder matches all 103 native tables / 11,814 symbol entries on
CPU, JavaScript and forced Metal, including retained frequencies, every length
and every reversed code word. The input and implementation/probe hashes match
the retained passing report. Zero/single-symbol cases, packed ordering, queue
ties and length-limit redistribution were reviewed against the pinned header.
See [COMPRESSION.md](COMPRESSION.md) and
[evidence/sdeflate-huffman.json](evidence/sdeflate-huffman.json).

Scoped A4/A5/A6 acceptance PASS for this internal dependency. It does not expose
`Compression.compress` or add public partial/completed coverage. LZ parsing,
block emission and actual native compressed-byte comparisons remain pending.
The unchanged full-corpus and proof evidence remains applicable at this
checkpoint; hosted execution remains unverified.

Regression scan: 4 callers checked, 4 assertions checked, 0 flagged/fixed.

## Native quality-8 raw compression

`Compression.compress` preserves native quality-8 LZ parsing, Huffman/precode
runs, dynamic/stored cost selection, raw-block splitting/alignment and final
flushes. Empty input returns zero bytes. Inputs are valid byte lists through
1 MiB, with at most 87,380 retained sequences per block; sequence exhaustion
returns `None` before append instead of reproducing the retained native overflow.

Both focused gates pass 40 native inputs and four rejection controls on CPU,
JavaScript and forced Metal. The private gate compares 51 blocks, 12,084 ordered
sequences and every frequency (40,641 words per lane), exercising length symbols
258..285 and distance symbols 0..29. Instrumented native output is byte-identical
to actual linked `CompressData`. The public gate compares all 1,931,853 compressed
bytes per lane and all 4,497,358 source bytes through nonempty zlib/Bend decoder
round trips. [COMPRESSION.md](COMPRESSION.md) links both evidence records.

Maximum incompressible input produces a stream beyond the public decoder's
separate 1-MiB compressed-input cap. The gate checks that public rejection, then
uses the unchanged internal decoder with a validated native output bound. This
is not broader public decompression coverage. Empty output is not decoded as a
DEFLATE stream. Other domains, native allocation ABI, complete integration/
resource/performance/targets and hosted execution remain gaps.

Scoped review: I147/I148 MATCH; C3/C6/C19 HOLD through Bend-only source, retained
MIT provenance and local-only work; A4/A5/A6 HOLD in the exercised profiles;
V2 HOLD through unchanged actual native bytes and independent zlib; V3 HOLD
through bounded input/match/sequence accesses. The ledger advances from 116 to
117 core partial functions, with 142 math partial functions and zero complete.

Regression review inspected 92 Bend function/constructor consumer contexts,
five generated-program contexts, two workflow commands and the native diagnostic
entry, plus eighteen comparison/rejection sites. It corrected two findings:
invalid-input controls initially bypassed the public compressor, and the precode
count helper did not explicitly retain its native four-entry minimum. The final
affected focused gates pass after those corrections; no expectations/tolerances
were weakened. Four proofs and eleven harness/planning tests pass.

Regression scan: 100 callers checked, 18 assertions checked, 2 flagged/fixed.

## 2026-10-02: suffix-selected export and native host diagnosis

`Surface.write_image` adds filename-selected RGBA8 PNG/BMP/TGA/QOI/RAW export.
The dedicated CPU/JS gate passes 70 cases, including 67 actual native-oracle
cases, 41 complete files / 3,803 encoded bytes, 686 round-trip pixels, 19 retained
unsupported owners, and 10 file-open failures. JPEG/JPEG-alias/KTX are explicit
candidate-only rejection controls, not native-parity claims. Mixed-case suffixes,
whole-path last-dot behavior, exact sentinels and native RAW order are checked.

Each lane passes 100 low-descriptor cycles with 16 operations per cycle and
compares all five final closure files to native output. Additional runs with
`RLIMIT_FSIZE=0`, ignored `SIGXFSZ` and a 64-descriptor limit induce 500 post-open
`EFBIG` write errors and 100 unsupported-owner rejections per lane. The expected
specific error code rules out a false pass caused by leaked descriptors and
`EMFILE`. Failed-write files are truncated to zero; unsupported sentinels remain
unchanged. Base's typed errors remain a documented language adaptation;
native failing-device/short-write/close-error equivalence is not claimed.

The final library proof verdict is `All terms check.` Existing contracts,
transforms and decoding suites pass independently on CPU/JS. All 34 Python
harness/planning/diagnostic tests pass, as do generated-ledger and project checks.
Independent read-only review checked ownership, suffix selection, actual
persisted files, source/program hashes and false-positive controls. Its open-error
coverage observation led to the mandatory post-open error runs above.

The full corpus was rebuilt and executed on CPU one-thread, CPU two-thread and
JavaScript. All retain exactly the original six mismatching scenarios: one angle
and five signed-zero extrema/clamp scenarios. The canonical gate remains failed;
no expected results, numerical tolerances or comparator gates were changed.
The native-only diagnostic completes six compiler modes and finds 178/1,086
Sun-control/glibc angle differences per mode, plus distinct constant-folded,
runtime-builtin and native-libm zero ties. This is diagnosis, not new numerical
parity. New export behavior has no GPU or hosted execution claim.

Durable records: [export dispatch](evidence/image-export-dispatch.json) and
[native host profiles](evidence/native-math-host-profile.json), with reproducer
and interpretation in [NATIVE-MATH-PROFILES.md](NATIVE-MATH-PROFILES.md).
Ledger delta from `a25f14b`: only `raylib:function:ExportImage`, partial → partial,
with narrower dispatch gaps; totals remain 117/600 core partial, 142 math partial
and zero complete. No remote publication was performed.

## 2026-10-02: bounded R32 format and image consumers

`Image.Formatted` now accepts native format 8 within finite `[0,1]`, including
both zero signs and positive subnormals. Conversion uses native red-only
normalization and uncontracted F32 luminance; same-format and zero-target requests
preserve every word. Wider R32 samples, reverse RGB-float conversion, RAW loading
of format 8 and native raw-bit memory PNG remain unsupported. File PNG uses
red-only normalized colors, while RAW/code exports preserve exact sample bytes.

CPU/JS evidence covers all 64 format pairs, 165 native cases, 1,119 boundary
samples, 45 rejected-factory controls and 173,303 compared bytes per lane. A
33,024-pixel exact import covers signed zeros/subnormals and guards against the
non-tail validator recursion spotted during static review. The final validator is
tail-recursive. This stress case exposed Base's recursive `List.show`;
the harness now uses strictly framed 256-byte chunks while comparing the same
complete native byte arrays. Neither inputs nor expected values were reduced.

The consumer gate passes 82 pure observations and nine complete native
PNG/RAW/code files per CPU/JS lane, plus two explicit unsupported-RAW-load checks.
It checks retained words, point/bulk colors, sole-channel selection, direct RGB
float red words and unsupported-owner behavior. Independent review also added a
valid 12-byte format-9 factory control so unsupported-format rejection cannot
pass merely through a wrong payload length.

All 50 Python tests, project/ledger checks and existing structural proofs pass.
Existing contracts, transforms and decoding pass on CPU/JS. The unchanged PNG
export gate passes 37 PNGs / 171,574 encoded and 172,340 round-trip bytes per lane;
the suffix-export gate retains all 41 exact files and its open/post-open/closure
controls. One final probe compilation exited without diagnostics during
overlapping check-only work; an isolated serial rerun passed without changing
library code, profiles, inputs or comparisons. Its cause is not established.

The full 261-scenario corpus was rebuilt and run on CPU one-thread, CPU two-thread
and JavaScript. Exactly the same six host numerical-profile scenario mismatches
remain. There is no new GPU runtime or hosted evidence. The current x86 native
raylib object uses separate multiply/add instructions; fused luminance profiles
on other native targets remain explicitly open.

[Durable R32 evidence](evidence/r32-image-format.json) records final source,
input, harness and generated-program hashes. Ledger delta from `1482e1e` advances
the partial scopes of ImageFormat, LoadImageColors, GetImageColor,
ImageFromChannel, ExportImage and ExportImageAsCode. Totals stay 117/600 core
partial, 142 math partial and zero complete. No remote publication was performed.

## 2026-10-02: explicitly qualified literal-extrema reference

The remaining signed-zero investigation identified a harness configuration error:
extrema/clamps inherited the Linux/GNU gradient selection even though their
literal C evaluation followed the already-implemented accurate zero contract.
An independent native corpus now qualifies that capability explicitly before any
Bend candidate is emitted. Its 832 vectors / 2,368 component words cover all
ordered zero/finite pairs and clamp triples in uniform and mixed-lane contexts,
across Vector2/3/4 min/max and Vector2/3 component clamp.

The qualifier compares native observations with two predefined documented bit
contracts. It neither examines conformance-fixture outcomes nor tries Bend
candidates to select a passing result. This host uniquely selects
`AccurateGradient`: zero control mismatches versus 76 for `GnuGradient`. Unknown,
mixed or ambiguous behavior fails closed. Compiler commands, identities,
header/library/control/source hashes and all observations are recorded afresh.
Reports cannot reuse stale success, and stale generated executables are removed
before compilation. The declaration is contextual qualification, not parity.

The complete 261-scenario corpus was rebuilt in 17 batches and compared on CPU
one-thread, CPU two-thread and JavaScript. Each lane now matches 260 scenarios;
all five earlier extrema/clamp failures are resolved. The exact angle mismatch
remains `3fc90fdb` native versus `3fc90fda` Bend. The canonical gate correctly
continues to fail; no tolerance or expected value was changed.

Independent review verified all complete lane result objects and hashes, the
qualification run IDs and source provenance. It also confirmed that native C
generation, decimal literals, fixtures, compiler flags, parsers, comparator,
other profile selectors and every Bend source remain unchanged from `b9a3384`.
Only the eight intended extrema APIs receive the freshly qualified existing
contract. Image-only callers remain unchanged; Metal prefix diagnostics obtain
fresh qualification when they include extrema, but no Metal run is claimed.

All 73 Python tests pass, including 19 qualification and four integration tests
for both contracts, malformed/incomplete observations, mixed/unsupported behavior,
stale state, compiler failures and unchanged unrelated profile routing. The proof
CLI returns `All terms check.` Project and generated-ledger checks pass. This
does not establish arbitrary runtime/native-pointer, other compiler/architecture
or GPU behavior, nor a modern glibc angle implementation.

[Qualification and actual-lane evidence](evidence/qualified-literal-extrema.json)
records this correction. Eight existing partial Jonmath entries gain the scoped
host evidence; availability/completion totals remain unchanged. No remote
publication was performed.

## 2026-10-02: bounded R32 memory PNG

`Image.Formatted.to_png` now supports checked R32 owners through a separate
memory-channel selector. It preserves the native interpretation of each raw
little-endian sample word as four RGBA bytes. File PNG retains its previous
red-only normalization; sample `0.5` decodes as `0000003f` in memory and
`7f0000ff` in a file. Packed formats 3/5/6 still reject with unchanged owners.
The R32 sample domain and the unsupported RAW-loader/reverse-float boundaries
did not change.

CPU/JS pass 88 pure observations plus nine exact native files and two RAW-load
rejection controls: 99 results per lane over all 1,132 R32 pixels. Memory PNG
compares 1,263 encoded / 4,528 raw decoded bytes; file PNG separately compares
370 encoded / 4,528 normalized decoded bytes. The half-sample discriminator,
signed zeros, subnormals, multirow geometry, non-power-of-two widths and every
threshold sample remain covered. PNG structure, dimensions, RGBA8 profile,
chunk CRCs and complete byte arrays are checked.

A generated forward reference was corrected before candidate execution.
Subsequent monolithic emission ended with SIGKILL (`-9`) after 33.702 seconds at
6,764,868 KiB maximum RSS, without compiler diagnostics. Typechecking passed;
the exact kill cause is unproven because cgroup telemetry was not exposed.
The harness now emits eight contiguous serial batches of at most eight
operations. No library, oracle, input, domain or tolerance was changed by this
batching. Each batch is validated before advancing, and stale binaries are
removed before compilation. Exactly two RAW-load controls remain in the final
batch. Missing/extra results cannot cancel across batches.

Independent review verified all generated source/harness/library hashes and
all native/candidate file bytes. A subsequent replay of the existing native and
all 16 candidate binaries retained raw stdout and reproduced every recorded
output hash, all 99 results per lane and all exact comparisons.

All 78 Python tests pass. The existing byte/packed PNG regression passes 37 PNGs
/ 171,574 encoded and 172,340 round-trip bytes on CPU/JS. Existing RGB-float PNG
regressions pass six memory and five file profiles, including rejected-owner and
IO controls. Transform contracts and the full proof CLI pass. Project/ledger
checks and source/hash consistency checks pass. The rebuilt 261-scenario corpus
still has only the documented angle mismatch on CPU one-thread, CPU two-thread
and JavaScript; aggregate conformance remains failed. No GPU/hosted execution
or performance parity is claimed for this extension.

[Durable evidence](evidence/r32-memory-png.json) records the final reports and
limits. ExportImageToMemory gains this partial scope, and ImageFormat's tracking
removes the now-closed memory-PNG dependency gap. Counts remain 117/600 core
partial, 142 math partial and zero complete. No remote publication was performed.

## 2026-10-02: bounded RGB-float to R32 conversion

`Image.FloatRGB.to_formatted` now accepts target 8 for the existing finite
`[0,1]` RGB input domain. The sole library change is the target bound 7→8;
the bitwise validator, retained-owner failures and existing uncontracted
left-associated F32 luminance encoder are unchanged. No clamp, FMA substitution
or RGBA8 quantization was introduced. Signed zeros and positive subnormals remain
accepted, while negative nonzero, above-one and nonfinite components remain
rejected even if their weighted result could fit. Grayscale remains format 1;
targets 0 and 9 are still unsupported by this bridge.

The standalone gate rebuilds the pinned native archive and qualifies its actual
arithmetic before emitting candidates. Its 36,279 direct-input pixels have zero
uncontracted-control mismatches and 462 differences from the explicit fused
control. This qualifies the exercised host profile; it does not select a profile
by trying Bend candidates. Expected conversion bytes come only from pinned native
`ImageFormat`, including the non-identity `9→8→9` and `8→9→8` chains.

CPU/JS each pass 17 native cases / 39,481 input pixels, 75 exact retained-owner
controls and 27 same-backend direct NaN controls: 194 complete observations and
182,019 output bytes per lane. Cases include all eight zero-sign combinations,
unit corners, predecessors of one, subnormal/normal boundaries, packed/grayscale
threshold inputs, a contraction discriminator, seeded exponent-spread triples,
rectangular/thin shapes and full 33,024-pixel traversal. Every rejected non-NaN
source word and dimension is checked in both the original returned owner and an
independently used copy. Invalid values occupy each component at early, middle
and final positions; unsupported targets include U32 maximum. The NaN checks do
not claim raw-payload interoperability.

Fifteen serial batches of at most eight operations per lane retain all inputs
and observations. Strict counts, types, framing, dimensions, formats, output
domains and byte lengths prevent missing/extra/truncated results from passing.
All stdout, input manifests, source/harness/generated-program hashes and native
archive/build hashes are retained. The focused CI gate runs before the separately
known-failing canonical gate; artifact selection excludes large RAW/sparse files.

All affected regressions pass on CPU/JS: 165 image-format cases across all 64
format pairs and 45 factory controls, ten direct RGB-float format cases / 5,759
pixels with three retained owners, fourteen reverse-bridge results, and the
existing large RGB-float/byte bridge. The former valid target-8 direct-format
rejection is now a native success. The R32 consumer gate retains all 88 pure
observations, nine exact files, memory/file PNG distinctions and two unsupported
format-9 pre-open RAW controls; its former target-8 rejection now uses a genuine
negative subnormal. Independent replay reproduces every consumer output hash
and file comparison.

Independent read-only review found a C qualification portability risk from
reading a byte array through a float pointer. The final qualifier uses `memcpy`
loads into declared float locals and asserts binary32/32-bit word layout. Review
then reparsed all 30 focused candidate stdout files and checked 40 library sources,
seven harness files, the input manifest, 32 generated programs, all stdout and
native archive/cache/flags/header/textures hashes. No library arithmetic change
was needed.

All 96 Python tests pass, as do syntax, generated-ledger, Clang catalog audit and
project checks. The final proof verdict is `All terms check.` Existing contracts,
transforms, decoding and QOI file round-trip/error checks pass on CPU/JS; native
PPM examples match every reference pixel. The full 261-scenario corpus was rebuilt
in 17 batches; CPU one-thread,
CPU two-thread and JavaScript each still match 260 scenarios. The only mismatch
is the documented angle result `3fc90fdb` native versus `3fc90fda` Bend. Aggregate
conformance remains failed; no expected values, tolerances, fixtures, angle or
extrema selectors were changed.

[Durable evidence](evidence/float-rgb-r32.json) records these scoped results.
The ledger delta from `1688305` changes only `raylib:function:ImageFormat`,
partial → partial. Totals remain 117/600 core partial, 142 math partial and zero
complete. Wider HDR, other numerical/target profiles, GPU/hosted execution and
full integration/resource/performance coverage remain open. No remote
publication was performed.

## 2026-10-02: isolated exact finite binary64 narrowing prerequisite

The new private `src/binary64_narrow.bend` accepts canonical binary64 high/low
words and returns a checked nearest-even binary32 word. Every finite input is
accepted, including binary64 subnormals and signed zero; binary32 underflow is
gradual and overflow produces signed infinity. Exponent 2047 is rejected. It uses
only two integer limbs and one direct rounding decision. There are no current
library consumers, and all existing conversion, projection, angle and extrema
sources/selectors are unchanged. [BINARY64-NARROW.md](BINARY64-NARROW.md) derives the
exponent partitions, jam invariant and carries and defines the limited contract.

The primary oracle decodes exact Python Fractions and binary-searches adjacent
binary32 values, including the conceptual overflow endpoint. A separately
qualified volatile runtime C cast agrees on all 35,324 direct inputs. Its Clang
19.1.7 flags disable fast math/contraction and enable rounding-mode semantics;
FE_TONEAREST and MXCSR 8064 establish no directed rounding, FTZ or DAZ on this
Debian x86-64 run. Unsupported native contexts fail closed.

CPU-one-thread, CPU-two-thread and JavaScript each pass **40,276 complete exact
observations**, serialized in 79 programs of at most 512 operations and lines of
at most 32. Coverage includes every finite64 exponent in both signs, subnormal
binades, even/odd ties with adjacent64 words, min-normal and overflow carries,
limb boundaries, exponent-stratified random words, 12 nonfinite rejections,
3,692 separate existing-promotion roundtrips, 1,188 jam-invariant controls and
72 guard/round/sticky controls. No output cells or cases were dropped.

The runner checks framing, IDs, tags, counts, types and payloads; retains all
stdout/stderr; hashes inputs, exact expectations, source/harness files, native
metadata and generated programs/binaries; invalidates old success and compiled
outputs; and revalidates the compiler pin/overlay and source hashes at acceptance.
Independent read-only review closed stale compiled-output reuse and final compiler
revalidation gaps, then checked all 885 artifact hashes and 48 source/harness
hashes. It independently recomputed the expectations and reparsed all 120,828
candidate observations and 35,324 native observations without differences.

All **110 Python tests** pass, including 14 new oracle/malformed/stale-output/
drift tests. The complete proof CLI returns `All terms check.` for the four
pre-existing laws and nine new structural/concrete laws. These establish selected
branches, recursion equations and six concrete boundary values, **not a universal
IEEE rounding theorem**. Existing CPU/JS float64 multiply/divide (512 results),
fused F32 multiply-add (2,056 results) and GNU/Sun angle controls (1,086 inputs)
pass unchanged. The current inverse-trig diagnostic has zero differences in 572
words on each CPU/JS lane; this does not promote a general inverse-trig API.
The unchanged native-angle probe still reports 178 differences on its first CPU
lane and fails strictly.

The complete canonical corpus was rebuilt in 17 batches and explicitly audited
on CPU-one-thread, CPU-two-thread and JavaScript after its fail-fast exit. Each
lane matches 260/261 scenarios and checks all 40,101 words. Its sole mismatch is
still `vector2-angle-profiles`, pixel `(6,0)`: native `3fc90fdb`, Bend `3fc90fda`.
The aggregate gate remains failed. No expected results, tolerances, fixtures or
reference selectors were changed.

The trailing contracts, transforms and decoding checks also pass on CPU/JS.
All three PPM examples match native pixels, and QOI file bytes, roundtrips and
missing/malformed/oversized-file controls pass on CPU/JS.

Syntax, project metadata, generated-ledger and independent Clang catalog checks
pass. Three angle ledger entries gain prerequisite evidence and explicit
remaining gaps only; statuses stay partial, totals remain 117/600 core partial,
142 math partial and zero complete. The focused CI gate is placed before the
known native-angle/canonical failures. GPU, hosted execution and performance
parity are unverified. Binary64 FMA, cancellation bounds and the full modern
angle profile remain open. [Durable evidence](evidence/binary64-narrow.json)
records the scoped checkpoint; no remote publication was performed.

## 2026-10-02: isolated bounded binary64 FMA prerequisite

The new private `src/binary64_fma.bend` accepts canonical binary64 high/low
words, computes the exact product and signed sum, and rounds once to nearest,
ties to even. Multiplicands are signed zero or normal with exponents
`[-277,127]`; the addend is signed zero or normal with exponent `[-554,255]`.
Every other encoding is rejected before arithmetic. The 29-U32 accumulator keeps
all bits through cancellation in units of `2^-658`; the checked rectangle bounds
the exact integer magnitude below `2^915`. Correct zero signs and final packing
are explicit integer operations. See [BINARY64-FMA.md](BINARY64-FMA.md).

All **41 existing library source files are byte-for-byte unchanged**. The helper
has no existing consumers, no public API promotion and no effect on existing
angle/conversion/projection/resize behavior. This is not general binary64 FMA or
a modern angle-kernel implementation. The rectangular bound is a standalone
handwritten integer argument, not mechanical verification of kernel reachability.

An independent exact Python `Fraction` oracle binary-searches rational binary64
neighbors rather than reproducing the candidate's accumulator or pack. A
qualified volatile runtime libm `fma` agrees on 10,726 accepted inputs; a separate
native domain check also agrees on 312 rejections. Native Clang 19.1.7 flags
exclude fast math, contraction, builtin FMA substitution and LTO. Nine fixed
preflights, `FE_TONEAREST` and MXCSR 8064 qualify the exercised x86-64 context,
with FTZ/DAZ disabled. Candidate CPU builds explicitly select the same recorded
supported compiler; unrelated ambient `CC` values cannot silently change it.

CPU-one-thread, CPU-two-thread and JavaScript each pass all **11,038 complete
observations**. Forty-four programs contain at most 256 operations, with at most
16 records per output line. The corpus covers every allowed exponent in both
signs and each operand, exact product residuals and the `2^-658` floor, both tie
parities and neighbors, significand carries, deep/full cancellation, long
carry/borrow chains, extrema/gaps, all zero-sign combinations, all 55
left-normalization shifts and all 32 residual shift positions. Nonzero
subnormals, NaNs, infinities and just-outside normal boundaries are rejected in
every operand, including cases where a zero shortcut would otherwise hide them.

The runner retains all stdout/stderr and hashes 504 generated/input/native/build
artifacts and 50 source/harness/pin files. Framing, counts, IDs, types, tags and
payload shape are strict. Old success and compiled outputs are invalidated before
use, and source/compiler/overlay/runtime identities are rechecked at acceptance.
All **135 Python tests**, including 25 focused oracle, malformed-output,
qualification, compiler-selection, stale-output and drift tests, pass.

The complete `PROOF.bend` verdict is `All terms check.` for 23 laws: 13 existing,
three new structural laws and seven concrete FMA equalities. These are not a
universal arithmetic correctness theorem. The limited proofs, exact differential
corpus and numerical bounds are distinct kinds of evidence.

The unchanged binary64 narrowing gate again passes 40,276 observations on all
three lanes. Existing float64 multiply/divide, F32 FMA and GNU/Sun angle controls
pass; the native-angle probe still fails strictly with 178 differences on its
first CPU lane. The full canonical corpus was freshly rebuilt in 17 batches,
then explicitly replayed on CPU-one-thread, CPU-two-thread and JavaScript after
its fail-fast exit. Every lane checks all 40,101 words and matches 260/261
scenarios, solely failing at `vector2-angle-profiles`, pixel `(6,0)`: native
`3fc90fdb`, Bend `3fc90fda`. The aggregate remains failed. The trailing contracts, transforms and decoding
checks pass on CPU/JS; all three PPM examples match native pixels, and QOI file
bytes, roundtrips and missing/malformed/oversized-file controls pass on CPU/JS.

Independent read-only review recomputed all 11,038 rational expectations,
reparsed all 33,114 candidate and 11,038 native records, regenerated every input
and Bend batch, and checked all 50 source and 504 artifact hashes. Its compiler
provenance finding was corrected and retested; no correctness or harness findings
remain open.

Generated ledger, independent Clang catalog, syntax and project checks pass.
Only prerequisite evidence and gaps change in the three angle ledger entries;
statuses stay partial, totals remain 117/600 core partial, 142 math partial and
zero complete. The focused CI gate precedes the known native-angle/canonical
failures. No expected results, tolerances, reference profiles or compiler sources
were changed. GPU, hosted execution, exhaustive input coverage and performance
parity remain unverified. [Durable evidence](evidence/binary64-fma.json) records
this private checkpoint.


## 2026-10-02: isolated bounded binary64 add/subtract prerequisite

The private `src/binary64_add_sub.bend` accepts canonical high/low binary64 words
for addition and subtraction, with each operand restricted to signed zero or a
normal exponent in `[-900,130]`. All other encodings fail closed before arithmetic.
It retains exact magnitudes through cancellation on a `2^-952` lattice in 34 U32
limbs, then rounds once to nearest-even. Addition keeps a common zero sign,
mixed zeros and nonzero cancellation give +0, and subtraction inverts the right
sign. Its standalone bound is below `2^1084` lattice units, with no nonzero result
underflow or overflow. [BINARY64-ADD-SUB.md](BINARY64-ADD-SUB.md) records the bounds
and the explicitly inspected width-independent FMA helpers reused internally.

All **42 existing library sources remain byte-for-byte unchanged**. The helper
has no existing image/math API consumers, no public re-export and no API status
promotion. Existing resize zero semantics, conversion/projection contracts,
angle selectors, fixtures, expected values and tolerances are unchanged. The
checked rectangle is not closed under chaining; kernel integration must establish
every subsequent operand's domain separately.

The independent exact `Fraction` oracle computes rational sums/differences and
binary-searches binary64 neighbors; it does not mirror the candidate accumulator
or pack. A separately qualified C oracle uses volatile runtime operations and
`memcpy`, with Clang 19.1.7 flags excluding fast math, contraction and LTO and
requiring rounding semantics and no excess evaluation precision. All 24 exact
native controls pass, including subnormal controls outside the candidate domain.
`FE_TONEAREST`, MXCSR 8064 and explicit FTZ/DAZ checks qualify this x86-64 run.

CPU-one-thread, CPU-two-thread and JavaScript each pass **47,464 complete exact
observations**, comprising 23,732 add and 23,732 subtract cases, 46,648 accepted
results and 816 rejections. The 186 programs are serial and bounded to 256
operations and 16 records per line. Every input exponent/sign/position/operation,
zero order, tie parity, normalization shift, significand bit and selected
carry/borrow/cancellation/gap boundary is represented. Minimum-binade adjacency
is stratified over all significand bit/carry boundaries, not exhaustive over its
`2^52` significands. Every lane checks all 237,320 framed U32 output words.

The gate strictly checks IDs, operation kinds, tags, types, counts and shapes;
invalidates old success, logs and compiler outputs; and pins source/input/program/
binary/output artifacts as they are consumed. Final source/toolchain/runtime and
artifact revalidation passes, with 52 source/dependency and 2,066 artifact hashes.
All **169 Python tests** pass, including 34 focused malformed-output, native
qualification, compiler-selection, stale-output and drift tests.

The full `PROOF.bend` verdict is `All terms check.` for **34 laws**: 23 pre-existing,
two new structural branch/definition laws and nine concrete zero/cancellation/
tie/floor/carry equalities. These are not a universal arithmetic correctness
theorem. The standalone integer bounds, limited proofs and exact differential
corpus are separate evidence.

The unchanged narrowing and bounded FMA gates re-pass 40,276 and 11,038
observations respectively on all three lanes. Existing float64 multiply/divide,
F32 FMA and GNU/Sun angle controls pass, as does the current 572-word inverse-trig
diagnostic on CPU/JS. The native-angle gate remains strictly failed with 178
first-lane differences. Canonical conformance was freshly rebuilt in 17 batches
and audited completely after its fail-fast exit: all three lanes check 40,101
words and match 260/261 scenarios. The only mismatch remains
`vector2-angle-profiles`, pixel `(6,0)`, native `3fc90fdb` versus Bend `3fc90fda`.

Trailing ownership, transform and decoding contracts pass on CPU/JS. All three
PPM examples match reference pixels, and QOI bytes, roundtrips and file-error
controls pass. A separate replay removes previous PPM/QOI output files first,
then confirms that fresh executions recreate the exact expected outputs.

Generated-ledger, independent Clang catalog, syntax and project checks pass.
Independent read-only review regenerated all 47,464 inputs and expectations and
186 programs, replayed all native/candidate outputs, checked all source/focused
artifact hashes and 208 retained regression artifacts, and cross-checked every
accepted result with separately expressed host operations. It found no blocking
findings. All 42 prior library sources and all 1,884 API statuses are unchanged.
Three angle entries gain prerequisite evidence and updated gaps only; statuses
remain partial, with 117/600 core partial, 142 math partial and zero complete.
CI runs this focused gate before the known native-angle/canonical failure.
The modern scalar kernel, stepping, reachable-domain integration, tiny-branch
underflow handling and forced-device/resource evidence remain open. No GPU,
hosted, exhaustive or performance-parity claim is made. The
[durable evidence](evidence/binary64-add-sub.json) records this private checkpoint.


## 2026-10-02: checked normal binary64 operations and exact word adapters

The isolated `src/binary64_ops.bend` adds checked raw-word boundaries around the
unchanged normal multiply/divide implementation, exact normal/zero packing,
finite F32 promotion including subnormals, finite construction, sign negation,
magnitude comparison, finite numerical equality, modular raw-word carry/borrow
steps and checked exponent construction. [BINARY64-OPS.md](BINARY64-OPS.md) records
the contracts, invariants, bounds and independent evidence.

Multiply inputs are signed zero or normal exponents `[-554,127]`, with nonzero
pair exponent sum `[-833,127]`. Division accepts numerator zero or normal
`[-225,127]`, a nonzero normal denominator `[-149,127]`, and nonzero `Ea<=Eb`.
All other arithmetic inputs are rejected before any zero shortcut. Results are
RN-even normal words (multiply exponent `[-833,128]`, divide `[-353,0]`) or
sign-XOR zero. Small integral exponent bookkeeping is exact in F32; significands
remain integer limbs. This is a standalone bounded contract, not general
binary64 arithmetic or a mechanically verified kernel-reachability theorem.

All **43 prior library source files remain byte-for-byte unchanged**. No existing
image/math API consumer, selector, fixture, expectation, tolerance or compiler
source changed. No public API was promoted. Raw stepping is unsigned encoding
addition/subtraction, not numerical `nextafter`. Finite equality treats ±0 as
equal and rejects nonfinite equality; finite construction does not make
subnormals valid arithmetic inputs. The tiny gradual-product path and full
modern angle kernel remain open.

The independent exact `Fraction` oracle computes products/quotients and searches
rational binary64 neighbors. It does not reproduce the candidate's product,
quotient loop or pack. Direct finite F32 promotion is checked against exact
rational words and native casts rather than only narrowing roundtrips. The
separate volatile C oracle passes 32 layout/rounding/zero/subnormal/promotion
controls, with Clang 19.1.7, `FE_TONEAREST`, MXCSR 8064 and explicit FTZ/DAZ rejection.
Compiler flags prohibit fast math, contraction and LTO, require rounding semantics
and the source rejects excess evaluation precision.

CPU-one-thread, CPU-two-thread and JavaScript each pass **36,176 complete exact
observations**, 35,064 accepted and 1,112 rejected: 11,892 multiply, 6,152 divide,
4,124 normal decode/encode identities, 4,124 finite constructions, 2,852 direct
promotions, 1,914 magnitude comparisons, 1,914 finite equalities, 384 each of
negation/increment/decrement and 2,052 exponent constructions. The 142 serial
programs have at most 256 observations and 16 records per line; every lane checks
all 180,880 framed U32 output words. Every allowed exponent/sign/operand position,
zero sign/order, product tie parity and neighbors, limb/significand/carry/sticky
boundary, division normalization order, exponent/pair guard limit and rejected
class is represented. All finite F32 exponents and subnormal leading positions
are covered directly. Sixty-four directed quotient near-midpoints lie exactly
`1/(2*N)` ulps on either side, covering both neighbor parities. Exact midpoint
ties between adjacent normals cannot arise in this checked division domain; synthetic
oracle rounder ties are labeled as internal controls.

Strict framing checks counts, kinds, IDs, tags, U32 types and payload shape.
Old success and compiled outputs are invalidated. Source/compiler/runtime,
input/program/binary and retained stdout/stderr hashes are pinned when consumed
and rechecked at acceptance. The focused report retains 53 source/dependency
hashes and 1582 artifact hashes. All **209 Python tests** pass, including
40 new oracle, malformed-input/output, qualification, compiler-selection,
stale-output and drift tests.

The complete `PROOF.bend` verdict is `All terms check.` for **51 laws**, with
three new structural rejection laws and fourteen concrete rejection/zero/word
boundary equalities. F32 arithmetic/bit primitives are opaque to this checker;
nonzero arithmetic and successful promotion are exact differential evidence,
not presented as mechanically proved numeric results. There is no universal
arithmetic or kernel theorem claim.

Existing narrowing, FMA and add/subtract gates re-pass 40,276, 11,038 and 47,464
observations on all three lanes. Existing float64 multiply/divide, F32 FMA,
GNU/Sun angle and inverse-trig controls pass. Native-angle remains a strict
178-difference first-lane failure. Canonical conformance is freshly rebuilt in
17 batches and fully audited after fail-fast: every CPU-one-thread, CPU-two-thread
and JavaScript lane checks all 40,101 words, with 260/261 scenarios passing.
The sole mismatch remains `vector2-angle-profiles`, pixel `(6,0)`, native
`3fc90fdb` versus Bend `3fc90fda`. The aggregate remains failed.

Trailing ownership/transform/decoding contracts pass on CPU/JS. All three PPM
examples match reference pixels; QOI bytes, roundtrips and missing/malformed/
oversized-file controls pass. A separate replay removes existing output files
and verifies that fresh executions recreate each expected PPM/QOI result.
Generated-ledger, independent Clang catalog, syntax and project checks pass.
Only prerequisite evidence/gaps change in the three angle entries; all 1,884
API statuses remain unchanged, with 117/600 core partial, 142 math partial and
zero complete. CI runs this focused gate before the known native-angle/canonical
failure. No GPU, hosted, exhaustive or performance-parity claim is made.
Independent read-only review recomputed every expectation with separate
integer-rational rounding, regenerated all 142 programs, replayed every native
and three-lane observation, checked all focused hashes and 217 retained regression
artifacts, and verified 76 canonical audit-command input/output records. It also
replayed the preserved 98,778 narrowing/FMA/add/subtract observations per lane
and checked their 3,455 artifact hashes. No blocking findings remain.
[Durable evidence](evidence/binary64-ops.json) records this private checkpoint.


## 2026-10-02: isolated gradual-output binary64 multiplication

`src/binary64_gradual_multiply.bend` adds a private checked multiplication on
canonical high/low U32 words. Operand `a` is signed zero or normal with exponent
`[-277,0]`; `b` is signed zero or normal `[-885,0]`. Both are validated before
zero shortcuts. Nonzero subnormal inputs, specials and out-of-range normals
are rejected, including invalid-with-zero. Results are once-rounded RN-even
normal/subnormal/XOR-signed-zero words. [The contract](BINARY64-GRADUAL-MULTIPLY.md)
states standalone bounds and reuse invariants; this is not generic binary64
subnormal-input arithmetic or a full angle-kernel implementation.

The unchanged FMA helper supplies an exact 106-bit product and width-independent
window operations. Normal products use its existing normal pack. Gradual
products are rounded directly on the `2^-1074` lattice and encoded from that
integer; no preliminary 53-bit rounding or FMA substitution occurs. The branch
at exponent sum `-1023` correctly handles already-normal results and carry into
minimum normal. Below half minimum subnormal, the result retains XOR sign.

All **44 pre-existing library sources remain byte-for-byte unchanged**. No
consumer, selector, fixture, expected result, tolerance or compiler changed.
Only three angle entries receive prerequisite evidence and gap updates; all
1,884 API statuses are unchanged, including 117/600 core partial, 142 math
partial and zero complete. CI runs the isolated focused gate before the known
native-angle/canonical failure.

The independent `Fraction` product/adjacent-neighbor oracle and separately
qualified volatile C multiplication agree on **30,861 observations**: 30,509
accepted and 352 rejected. Native qualification passes 63 fixed controls,
including signed zeros, parity/transition ties, DAZ-sensitive subnormal-to-normal
and FTZ-sensitive normal-to-subnormal products, and all double-rounding witnesses.
Clang 19.1.7, explicit no-fast-math/contraction/LTO flags, IEEE layout/evaluation,
RN-even and control-register checks are retained. MXCSR is 8064 before preflight
and 8114 after it, differing only in status flags. No exception-flag contract is
claimed. Unsupported native architectures/modes fail closed.

CPU-one-thread, CPU-two-thread and JavaScript each match every observation in
121 serial programs of at most 256 operations and 16 framed records per line.
The actual output classes are 14,850 normals, 8,657 subnormals and 7,002 signed
zeros. Every allowed exponent/sign/operand position and both product-top bits
are sampled, along with all gradual shifts, significand bits/holes, limb
boundaries, tie parities and adjacent operands, zero signs and invalid classes.
`k=53..106` exercises the final window; `k=107..192` exercises the zero fast path.
The corpus includes all three double-rounding witnesses and negative mirrors,
and four exact products reached in the separate tiny-kernel bounds research.
It does not execute the full kernel. The impossible accepted-product `k=106`
exact half tie is tested only as an explicitly internal synthetic control.

Strict framing checks all IDs, kinds, tags, U32 types, counts and payloads.
Old success/compiled outputs are invalidated; consumed inputs, programs,
binaries, native/candidate stdout and source/toolchain identities are hashed
and rechecked. The focused gate retains 54 source/dependency and 1,351 artifact
hashes. All **239 Python tests** pass, including 30 new oracle, malformed-input/
output, qualification, stale-output and drift tests. Complete `PROOF.bend`
checks **71 laws**: 51 existing, two new structural branches, sixteen concrete
checked results/rejections and two internal raw-window equalities. These are
limited proofs, not a universal arithmetic or kernel-reachability theorem.

Preserved narrowing/FMA/add-subtract/normal-operation gates re-pass 40,276,
11,038, 47,464 and 36,176 observations respectively on all three lanes, totaling
134,954 per lane. Legacy binary64 multiply/divide, F32 FMA, GNU/Sun angle and
inverse-trig gates pass. Native-angle remains the documented strict first-lane
failure with 178 differences. The canonical suite is freshly rebuilt in 17
batches after removing prior generated outputs. Its supplementary audit checks
all fields and all 40,101 pixel/numeric words on CPU-one-thread, CPU-two-thread
and JavaScript, not merely the first difference per scenario. Each lane still
has exactly one unequal word: `vector2-angle-profiles` pixel `(6,0)`, native
`3fc90fdb` versus Bend `3fc90fda`; 260/261 scenarios match and aggregate
conformance remains failed.

Trailing ownership, transformation and decoding contracts pass on CPU/JS.
The three PPM examples match every reference pixel. QOI bytes, roundtrips and
missing/malformed/oversized-file controls pass; a separate replay removes prior
PPM/QOI outputs and verifies fresh files. Generated-ledger, independent Clang
catalog, syntax and project checks pass. Full modern scalar kernel/fallbacks,
checked-domain integration, native-profile qualification, wrapper domains and
forced-device/resource evidence remain open. No GPU, hosted, exhaustive-input
or performance-parity claim is made. [Durable evidence](evidence/binary64-gradual-multiply.json)
records this private checkpoint.

Independent read-only review regenerated and replayed all 30,861 focused inputs,
121 programs and three lanes, verified 1,351 focused artifact/54 source hashes,
and cross-checked expectations with separate integer-rational rounding. It also
replayed 134,954 preserved observations per lane and verified 5,037 arithmetic
artifact hashes. It verified 212 retained regression artifacts, 76 audit-command
input/output records, 68 canonical build artifacts and every canonical field,
PPM pixel and QOI byte. The gradual-division wording and first-difference-only
supplementary audit were corrected. No blocking findings remain.


## 2026-10-02: private pinned finite modern atan2 scalar kernel

`src/modern_angle.bend` is a complete finite-input RN-even adaptation of the
pinned MIT glibc 2.41 scalar source, using the five unchanged private binary64
prerequisites. The [contract](MODERN-ANGLE.md) separates raw scalar inputs from
public vector-wrapper domains. No public consumer, default, selector, fixture,
expected word, tolerance or compiler changed. All 45 pre-existing library sources
remain byte-for-byte unchanged. Three angle entries receive private evidence/gap
updates only; all 1,884 API statuses remain unchanged, with 117/600 core partial,
142 math partial and zero complete. The canonical mismatch remains a strict
failure rather than being rerouted to the new code.

The entire rational expression tree, both fallbacks, all 32 compensated
coefficient pairs, FMA residuals, literal gradual tiny product, unsigned raw-word
stepping and final narrowing/re-promotion correction are implemented. All 102
binary64 constant roles are checked against an independently frozen source table.
The full MIT notice and altered-source provenance are retained. The exact
original C file, separate instrumented adaptation and compatibility shims are
hashed independently; no LGPL testcase table is copied and no native arithmetic
hook appears in the Bend candidate.

All **8,317 source-defined observations** match CPU-one-thread, CPU-two-thread
and JavaScript, including final64/final32 words, branch masks, reduction metadata
and 121,148 ordered binary64 checkpoints per lane. Each lane checks 567,870 framed
U32 words across 33 serial programs of at most 256 inputs. All 8,263 finite cases
succeed without arithmetic-domain rejection; all 54 nonfinite pairs are rejected
before promotion. Result classes include 8,065 normals, 78 subnormals and 120
signed zeros. The complete historical 1,086-input prefix and all 178 historical
native/Sun differing ID/output records are pinned unchanged.

Actual coverage includes 6,077 rational paths, 2,156 shortcuts, 30 early-zero
returns, 718 tiny decrements and 269 compensated general fallbacks. General final
scaling takes the upward branch 16 times and downward 253 times. Tiny products
include 710 normal values, four subnormals and four negative zeros, preserving
the exact literal operation. All reduction indices, magnitude orders and sign
quadrants are covered. Independently reviewed written RN arguments exclude tiny
increment, tiny nonboundary and the final correction guard's false side for this
finite-input contract. Their code remains implemented; direct synthetic controls
exercise them without claiming actual source hits or an exhaustive theorem.

The separate **28-control** helper gate passes all three lanes: ten successful
raw/helper values and eighteen explicit primitive-rejection or propagation
records, including deterministic dependency-left failure precedence. These 379
framed U32 words per lane are not added to reachable scalar coverage. No failure
substitutes an old profile, clamped value or zero.

Pinned original/adapted/native glibc 2.41 outputs agree for every finite corpus
input. Separate Clang 19.1.7 and GCC 14.2.0 native builds agree on every full record,
including branches and checkpoints. Same-process qualification checks layouts,
no excess precision, true FMA, direct narrowing, gradual arithmetic, RN-even and
FTZ/DAZ before and after execution. Final MXCSR is 8114; exception status bits
are outside the contract. Libc package-manager identity is explicitly unavailable;
runtime version and loaded atan2/FMA library hashes are retained. Native libm
is diagnostic and never defines or selects the pinned-source expectation.

Native-only bounded input discovery reproduces all nineteen retained rare-path
seeds from 100 million uniform trials and 100,000 midpoint/continued-fraction
proposals. The latter produces 17,809 general hits, including 541 upward cases;
sixteen seeds are retained before sign/swap expansion. A separate 50-million-trial
tiny search sees 6,250,036 boundary cases and no nonboundary case. These searches
are not additional Bend parity observations; the exclusion arguments are written
bounds, not inferences from absent hits. Source snapshots and complete search
outputs survive. The unused 200-million-trial exploration is not an acceptance
dependency.

All **271 Python tests** pass, including 32 new focused methods for malformed,
missing, duplicate/reordered, wrong-type, coefficient-mutation, qualification,
coverage-loss, stale-output and source/library/compiler drift failures. Complete
`PROOF.bend` checks **84 laws**: 71 existing plus five structural failure/rejection
laws and eight concrete special/zero controls. The written coefficient/domain
checker passes its exact finite facts. None of these is a universal atan2,
arithmetic or kernel-reachability machine proof.

Every arithmetic prerequisite is freshly rerun: narrowing 40,276, FMA 11,038,
add/subtract 47,464, normal operations/adapters 36,176 and gradual multiplication
30,861, totaling **165,815 observations per lane**. Legacy binary64 operations,
F32 FMA, GNU/Sun angle and inverse-trig gates pass. The existing native-angle
probe still fails with exactly its 178 historical differences.

The canonical reference archive is clean-rebuilt with its unchanged cached
configuration; old generated reference/candidate programs and outputs are removed.
A fresh 17-batch canonical run and complete all-field/word audit again give
**260/261 scenarios per lane**, checking every one of the 40,101 words. The sole
difference remains `vector2-angle-profiles` pixel `(6,0)`, native `3fc90fdb`
versus Bend `3fc90fda`. Aggregate conformance remains failed. Trailing ownership,
transformation, decoding, all PPM example pixels, QOI bytes/roundtrips and
missing/malformed/oversized-file controls pass; fresh-file replay removes prior
PPM/QOI outputs before checking regenerated data.

The focused report rechecks 66 source/dependency and 408 artifact hashes.
Independent read-only review regenerated every focused input/program/expectation,
replayed all retained lane records and checked exact constants, written bounds,
native contexts and unchanged sources. Final regression/metadata review and
clearance are recorded in [durable evidence](evidence/modern-angle.json).
The generic 256-input serial benchmark used approximately 971 MiB peak child RSS
and 15.06 seconds compilation; the full focused gate took 562.703 seconds. These
are scoped local harness observations, not runtime/device performance parity.
The CI workflow includes the new focused gate before the still-strict public
native-angle failure; no hosted execution is claimed.

Public Angle.Reference/native qualification, vector intermediate/output domains,
forced-device/resource validation and performance remain separate work. No GPU,
all-target, full finite-pair exhaustive execution, exception/errno, other-rounding
or NaN-payload claim is made.

## 2026-10-02: historical standalone qualifier-only checkpoint

The independently frozen [native angle qualification gate](ANGLE-QUALIFICATION.md)
now verifies 76 scalar controls, 205 canonical/runtime wrapper controls and
1,654 ordered intermediate words before any future angle-candidate generation.
It uniquely observes the modern contract on the recorded Linux host; historical
source contracts are not newly host-qualified. Public routing, old algorithms,
canonical fixtures and the final-angle-only wrapper validation gap are unchanged.

## 2026-10-02: explicitly checked angle references and qualified routing

The three existing partial raymath angle entries now also map to explicit
`Angle.Reference` checked APIs. `Apple2007AngleRn`, `Sun239AngleRn` and
`Glibc241AngleRn` identify source/numerical contracts. Existing defaults and
`*_for(Gradient.Reference, ...)` meanings are unchanged. All 1,884 statuses,
117/600 core partial entries, 142 math partial entries and zero completed APIs
are unchanged. The [contract](CHECKED-ANGLES.md) specifies staged normal/zero
intermediates and output, finite original components, true line negation and
propagated checked scalar failure.

The dedicated gate passes **428 raw wrapper controls plus 45 separate synthetic
helpers per lane**, on CPU-one-thread, CPU-two-thread and JavaScript. It compares
actual original native wrapper values, an independently pinned scalar source,
exact-rational intermediates/rejection stages, all three public checked profiles
and unchanged legacy/default results. There are 310 accepted values and 118
checked rejections per profile, with 311 legacy-eligible rows; the 69 Apple/Sun
wrapper differences are distinct from the retained 178 historical scalar
native/Sun differences. All 1,086 historical scalar records remain unchanged.

Independent review reparses all 1,419 candidate records, regenerates all eight
programs, and checks 72 source hashes, 98 candidate artifacts, 15 raw-native
artifacts and 78 qualification artifacts. One generated-Bend dispatch binding
error was caught by the first execution attempt, corrected by a parameter-matched
helper without input/oracle changes, and followed by the entire passing gate.
The final focused run took 202.412 seconds; this is local harness timing only.

The full unchanged canonical corpus passes **261/261 scenarios and all 40,101
pixel/numeric words on each lane**, including the formerly unequal angle cell.
The new qualified modern route returns `3fc90fdb`; the old Sun route still
returns its historical `3fc90fda`. Every other record field also matches, including
333 QOI bytes and 23 palette words per lane. Trailing ownership, transformation,
decoding, PPM and QOI file/error controls pass. Separate rejected-angle cases
followed by clear or overwrite fail nonzero without a success row on all three
lanes. No pixel sentinel is used, and public Surface errors are unchanged.

Native qualification is fresh before candidate emission. Independent review
confirms the manifest refresh changes only the conformance source-context pin
and enclosing digest; the 76 scalar controls, 205 wrapper controls and 1,654
frozen intermediate words are unchanged. Native prechecks leave the original
raymath numeric calls, compiler flags, fixture schema/data, pixel locations and
exact comparisons untouched. CLI admission additionally clears every explicit
unambiguous output destination before parsing, including late/duplicate paths;
264 admission cases exercise the stale-report boundary.

The full Python suite passes 340 tests. The complete `PROOF.bend` checks 95 laws,
including 11 scoped structural rejection/propagation/default-preservation laws.
No universal transcendental or arithmetic proof is claimed. All 44 pre-existing
`src` Bend modules and Jonlib are unchanged. Their prior private narrowing, FMA,
add/subtract, normal-operation, gradual-multiplication and modern-scalar gates
retain their earlier evidence; those full private corpora were not rerun in this
integration. The affected legacy angle and wide-arithmetic regressions were rerun.

The [integration record](evidence/checked-angles.json) links the separate native,
wrapper, canonical and review evidence. No new GPU, hosted, all-target, exhaustive
finite-input or performance-parity claim is made. Linux glibc ELF provenance is
the currently supported qualification context; Darwin angle-bearing canonical
and Metal-prefix execution fails unsupported before candidate generation.


## 2026-10-02: checked formatted BMP file bytes and explicit writer

`Image.Formatted.to_bmp` and `write_bmp` add exact native `ExportImage` BMP
output for checked single-mip formats **1..8**, dimensions **1..4096** on each
axis. The pure API consumes its owner into immutable bytes; the explicit writer
consumes it on success and IO failure, preserves Base's exact error code/message
and uses the existing closed-handle byte writer. This is not a mapping to native
`ExportImageToMemory`, which has no BMP dispatch.

Native grayscale, gray-alpha and RGB888 use a 54-byte INFO header, bottom-up
24-bit BGR and zero row padding. Gray-alpha discards alpha without compositing.
RGB565/RGB5A1/RGBA4/RGBA8888 and checked R32 use the existing 122-byte V4 writer
with canonical masks and bottom-up BGRA. Packed expansion is `LoadImageColors`,
not `ImageFormat`; RGB565 maximum is `(248,252,248,255)`. R32 is red-only F32
truncation with opaque alpha, including both zeros and positive subnormals.
The existing Surface and FloatRGB encoders and all old public defaults remain
unchanged. [The contract](FORMATTED-BMP-EXPORT.md) states complete header,
ownership, arithmetic-bound and IO-adaptation rules.

The clean-rebuilt pinned native archive passes nine fixed layout/color controls.
Native packed/R32 inputs use aligned allocations with effective types established
by typed stores after `memcpy` into declared scalars; an exact full-payload
comparison rejects any raw-word normalization before `ExportImage`. This avoids
C aliasing assumptions and retains signed-zero/subnormal words.

The focused gate passes **78 complete images / 331,465 pixels per lane** on
CPU-one-thread, CPU-two-thread and JavaScript. Every lane compares **1,221,952
encoded bytes and 1,325,860 decoded RGBA bytes**, including an independent Python
BMP decoder and 78 actual candidate files with `.dat` suffixes. All formats cover
widths 1/2/3/4 with unequal rows, thin rectangles, 4096-pixel axes and 33,024-pixel
full traversals. Additional cases cover six alpha variants with identical gray,
packed bit boundaries/maxima/alpha-only/seeded words, R32 truncation neighbors,
signed zero/subnormal samples and fully transparent RGBA.

Each lane also passes **3,200 formatted IO checks** under a 64-descriptor limit:
800 repeated successful writes, 800 missing-parent failures, 800 directory-open
failures and 800 post-open failures under `RLIMIT_FSIZE=0` with ignored `SIGXFSZ`.
Four direct Base operations establish the lane's exact code/message baselines.
The post-open cases require **EFBIG**, so descriptor exhaustion/EMFILE cannot
masquerade as correct failure handling. Files may be truncated on failure; native
stb short-write/close-return equivalence is not claimed.

Strict metadata/chunk framing, counts, types, input dimensions, exact file sizes,
header/padding checks and fresh sentinels reject incomplete/stale output. Inputs,
generated programs, binaries, raw stdout/stderr and command receipts are sealed
when created and rechecked before commands and final success. The report retains
**603 sealed artifacts, 677 artifact hashes and 136 source/dependency hashes**.
An initial IO-harness affine annotation error was caught and corrected; review
then corrected qualifier/native-input effective types. The entire focused gate
was rerun after both fixes without changing cases or expected bytes. Its final
143.298-second runtime is a local harness observation, not performance parity.

All **359 Python tests** pass, including 19 new focused fixture/parser, malformed
metadata/chunk, stale-result/compiler-output, immutable-drift and IO guardrails.
Complete `PROOF.bend` checks **99 laws**: the prior 95 plus four structural
padding/row laws. Byte/channel arithmetic remains exact differential evidence,
not a universal codec or numeric theorem.

The unchanged canonical corpus freshly passes **261/261 scenarios and all 40,101
words on each of CPU-one-thread, CPU-two-thread and JavaScript**, with all record
fields, 333 QOI bytes and 23 palette words checked separately. Fresh native
qualification still selects `Glibc241AngleRn`; its frozen manifest/source pins,
fixtures, original raymath calls and comparisons are unchanged. Trailing
ownership/transform/decode contracts, three freshly generated PPM examples and
QOI bytes/roundtrip/file-error checks pass.

Twelve existing CPU/JS image gates also pass: BMP (98 decode cases, 46 errors and
three exports), FloatRGB BMP/TGA, formatted PNG, FloatRGB PNG, all 64 format pairs
(165 cases), R32 image consumers, colors, channels, RAW files, suffix-selected
exports, file loading and all 534 memory token/content pairs. Final source checks
retain Jonmath and all 44 existing non-BMP support modules byte-for-byte. Private
arithmetic/full scalar corpora retain their prior scoped evidence and were not
rerun for this additive codec change.

Only **`raylib:function:ExportImage`** changes mapping/scope/gaps/evidence and stays
partial. All 1,884 API statuses remain unchanged, including 117/600 core partial,
142 math partial and zero complete. `ExportImageToMemory` is unchanged. CI runs
the focused BMP gate before aggregate conformance, but no new hosted or GPU run
is claimed. Formatted TGA/QOI/JPEG/KTX, non-Surface suffix dispatch, wider float
formats, native callbacks/allocation ABI and complete platform/integration/
resource/performance coverage remain open.

Independent source/harness and retained-evidence review verifies the exact native
channel routing, ownership/error behavior, regenerated inputs/programs and
complete focused observations. The canonical audit independently replays 330
artifacts, 128 command receipts and the frozen native qualification. Final typed
focused replay rechecks all 677 artifacts and 603 seals; regression review checks
819 artifacts and 564 source-hash observations. No review blockers remain. Full retained
results and hashes are in [durable evidence](evidence/formatted-bmp-export.json).


## 2026-10-02: checked formatted TGA file bytes and explicit writer

`Image.Formatted.to_tga` and `write_tga` add exact native `ExportImage` output
for checked single-mip formats **1..8**, dimensions **1..4096** per axis and
bounded R32 samples. Both consume the source; explicit file IO retains Base's
exact error code/message and the existing close-on-write-attempt behavior. This
is not an `ExportImageToMemory` mapping or broader filename dispatch.

Native channel routing is preserved: grayscale/gray-alpha use type 11 at 8/16
bits; RGB uses type 10 at 24 bits; packed/RGBA/R32 use type 10 at 32 bits.
Headers, bottom-up row order, BGRA/BGR component order and row-reset RLE packets
match every native byte. The raw scan's two-positions-back comparison, 128 cap,
ABA/ABBC behavior, alpha equality and post-expansion R32 run collapse remain
explicit controls. Packed expansion uses `LoadImageColors`, including RGB565
maximum `(248,252,248,255)`, rather than normalized `ImageFormat` conversion.
Existing Surface/FloatRGB output and legacy decode behavior remain unchanged.
[The contract](FORMATTED-TGA-EXPORT.md) details ownership, IO adaptation and bounds.

The clean-rebuilt pinned native archive passes nine layout/color controls. Its
packed/R32 source buffers establish effective types through typed assignments
from `memcpy`-filled scalar locals, then compare every raw input byte. Actual
native `ExportImage(.tga)` defines the oracle; native decoded metadata is checked
before normalization. Independent strict Python decoding enforces exact headers,
packet payloads, row boundaries, orientation, pixel counts and complete EOF.

The focused gate passes **304 complete images / 619,451 pixels per lane** on
CPU-one-thread, CPU-two-thread and JavaScript, comparing **2,212,918 encoded
bytes and 2,477,804 decoded RGBA bytes** per lane, including pure output, actual
sentinel-replacing `.dat` files and both native/Jonlib decoding. All formats cover
widths 1..4, run/raw lengths 1/2/3/127/128/129/130/255/256/257, identical consecutive
rows, three-row orientation, 4096-pixel axes, 33,024-pixel full traversals and
seeded mixed packets. Alpha-only/hidden RGB, packed boundaries and R32 truncation
neighbors/zeros/subnormals are included. The 513×513 control exports **1,055,259
bytes**, exceeding the generic raster loader's independent 1 MiB cap.

Each lane also passes **3,200 typed formatted IO checks** under a 64-descriptor
limit: 800 successes, 800 exact ENOENT, 800 exact EISDIR, and 800 exact EFBIG
failures under `RLIMIT_FSIZE=0` with ignored `SIGXFSZ`. Four direct Base calls
supply exact code/message baselines. Open-error sentinels and post-open truncation
are checked, with per-lane final files retained. Native ignored short-write/close
failures are explicitly outside return-parity claims.

The report retains **2,298 seals, 2,462 artifact hashes and 136 source/dependency
hashes**. Independent review regenerated all fixtures/programs, replayed every
native/three-lane record, checked all 168 command receipts and all hashes, and
used a second independent strict decoder for every retained export. No builds
or candidate binaries were rerun in that replay. The measured **417.396-second**
focused duration is local harness evidence, not performance parity.

All **391 Python tests** pass, including **32 new focused tests** with malformed
headers/packets/metadata/chunks, full-tail mutations, stale outputs, exact CLI
admission ordering and mocked end-to-end evidence/provenance failures. Every
explicit unambiguous build destination is invalidated before typed/help/option
errors, while preserving argparse's negative/dash-space paths and `--` semantics.
Fresh run namespaces avoid both stale execution and arbitrary-directory deletion.
Complete `PROOF.bend` checks **105 laws**, six new scoped routing/empty-traversal
laws beyond the previous 99. This is not a universal codec or numeric proof.

The unchanged canonical corpus freshly passes **261/261 scenarios and every one
of 40,101 pixel/numeric words** on CPU-one-thread, CPU-two-thread and JavaScript.
The supplementary audit checks all field types/cardinalities and values, 333 QOI
bytes and 23 palette words per lane. Fresh native qualification still selects
`Glibc241AngleRn`; frozen source controls, fixtures, original raymath calls and
comparison tolerances are unchanged. Trailing ownership/transform/decode gates,
three fresh PPM examples, QOI roundtrip/file-error controls and per-lane generated
file snapshots pass.

Fourteen existing image gates pass against exact final library-source hashes:
legacy TGA, formatted BMP, BMP, FloatRGB raster export, formatted PNG, FloatRGB
PNG, image format conversion, R32 image consumers, colors, channels, RAW files,
suffix-selected exports, file loading and all 534 memory token/content pairs.
Independent replay checks **1,517 retained regression artifacts**. Jonmath and
all 44 non-TGA support modules remain byte-for-byte unchanged; private arithmetic
corpora retain prior scoped evidence and were not rerun for this codec addition.

Only **`raylib:function:ExportImage`** changes mapping/scope/gaps/evidence and stays
partial. All 1,884 API statuses remain unchanged: 117/600 core partial, 142 math
partial and zero complete. `ExportImageToMemory` is unchanged. CI gains the
focused TGA gate before aggregate conformance and retains its full evidence;
modern-angle evidence retention and a 120-minute timeout accommodate the existing
gates without changing any case, matrix entry or permission. No new hosted or
GPU run is claimed. Formatted QOI/JPEG/KTX, non-Surface dispatch, wider profiles,
ABI and full platform/integration/resource/performance parity remain open.

Full results, reviews and hashes are in
[durable evidence](evidence/formatted-tga-export.json).

## Format-preserving QOI memory loading (2026-10-02)

The dedicated `Image.Formatted.decode_qoi` closes the native QOI original-format
memory gap within the existing partial `LoadImageFromMemory` entry. Its owned
single-mip result is RGB888 (4) for channel-3 headers and RGBA8888 (7) for
channel-4 headers, preserving dimensions and all native-order bytes. Existing
Surface memory/file entrypoints and generic dispatch remain normalized RGBA8.
No formatted file wrapper or generic formatted dispatcher is added.

The focused probe compares **121 native images / 35,615 pixels**, with **126,736
original-format bytes** and **142,460 separately normalized bytes**. Raw format,
width, height, actual mipmap count and every byte are emitted by actual linked
pinned `LoadImageFromMemory` before any normalization. Four native uppercase
calls and eight safe invalid-header rejections bring the native output to 254
observations. Invalid native buffers and declared lengths are at least 22 bytes;
no undersized pointer access or large allocation request is used as an oracle.

Each CPU-one-thread, CPU-two-thread and JavaScript lane checks **638 observations
/ 554,344 bytes**: direct native-format export, independent Surface bridge,
legacy decoder and generic dispatch for every accepted image; uppercase,
explicit decode-reference, checked-factory and rejected-get owner observations
for the four hidden-alpha/cache discriminators; and **67 exact typed failures
through both memory entrypoints**. The probe checks RGB logical words' zero
high bytes and reuses immutable input lists for independent affine decodes.
All original five QOI fixtures are reused without post-decode mutations.

Inputs cover both header channels/colorspaces, all opcode families, cache
collisions/initial and empty slots/alpha-sensitive hashing, literal tag
precedence, all 64 DIFF encodings, LUMA boundaries and wrapping, full RGB/alpha
byte ramps, exact/overflowing runs, noncanonical repeated INDEX acceptance,
non-power-of-two shapes, both 4096-axis endpoints, seeded mixtures and a
nonuniform 5,103-pixel image. Typed failures retain byte-validation precedence,
header/size bounds, stage-dependent truncation, strict markers and run overflow.
Every chunked output is length/metadata/type/framing checked; malformed,
missing, truncated or extra output fails the gate. A fresh native build and run
namespace plus source/tool/program/output hashes prevent stale evidence reuse.

The complete proof verdict is `All terms check.` for **110 laws**, including
five scoped QOI format/packing/empty-traversal laws. This is not a universal
codec proof. All **432 Python tests** pass without skips; 11 focused
harness tests cover native observation ordering, safe rejected buffers, complete
byte/metadata/framing comparison, ownership routes and fixture discriminators.

Fresh canonical clean-loader conformance passes **261/261 scenarios and all
40,101 pixel/numeric words** on CPU-one-thread, CPU-two-thread and JavaScript.
Fresh independent native angle qualification selects `Glibc241AngleRn`; frozen
math fixtures, reference calls and tolerances remain unchanged. Ownership,
transform and decode contracts, three PPM examples and legacy QOI file
roundtrip/missing/malformed/oversize controls pass. These are regression results
for the existing APIs, not a new formatted file-loading claim.

Supplementary unchanged gates pass on CPU/JavaScript: all **534 native memory
token/content pairs plus five typed controls**; **59 native file cases, three
boundaries and 100 low-descriptor cycles**; and **165 complete native format
pair/chain/bridge cases, 45 factory controls and 173,303 exact bytes**. Each
report carries the same final library-source hashes. Two parallel supplementary
compile attempts ended nonzero without diagnostics and were not counted as
results; serial retries passed unchanged, with exact subprocess receipts and
the incomplete attempt records retained in the evidence. Their original
termination cause was not established.

Only `raylib:function:LoadImageFromMemory` changes mapping/scope/gaps/evidence,
remaining partial. Core totals remain 117 partial / zero complete; all other
API statuses and `LoadImage` stay unchanged. CI gains the memory-only QOI gate
and artifact retention while preserving all prior tests, matrix entries,
permissions and oracle settings. These local results establish Linux x86_64
CPU/JavaScript behavior; new hosted/macOS, Metal/GPU, Windows, big-endian,
maximum-area resource, pointer ABI and full performance/integration evidence
remain open. Native malformed-stream permissiveness is not claimed.

Full scoped results and regression receipts are in
[the evidence report](evidence/qoi-formatted.json).

## Format-preserving QOI file loading (2026-10-02)

`Image.Formatted.load_qoi(path)` adds a dedicated original-format ordinary-file
factory within the existing partial `LoadImage` entry. The two-function adapter
reuses `Image.file.bytes` and `Image.Formatted.decode_qoi`; it neither reparses
QOI nor changes the decoder, Surface adapters or generic dispatch. QOI is
selected explicitly regardless of filename. Success creates one affine RGB888
(4) or RGBA8888 (7) owner, preserving dimensions, the implicit one-mip contract
and every raw R,G,B[,A] byte. The previous memory-only entry remains historical;
its evidence is not repurposed as file evidence.

A fresh pinned native build compares **135 accepted ordinary files / 35,657
pixels**, preserving **126,883 original-format bytes** and independently
observing **142,628 normalized bytes**. These are the existing 121 compact
memory fixtures materialized as files plus 14 RGB/RGBA filename discriminators.
The native routes are **129 actual `LoadImage(path)` calls** for `.qoi`/`.QOI`
names and **6 explicit `LoadFileData` → `LoadImageFromMemory(".qoi", ...)` calls**
for mixed-case, suffixless and misleading suffixes. Native dimensions, actual
mipmaps, format and complete raw bytes are emitted before `ImageFormat`; no
normalization serves as the original-format oracle. Eight safe complete small
invalid-header files bring native observations to **278**. Short positive-length
or sparse-large files are never passed to native QOI or native `LoadFileData`.

Each **CPU-one-thread, CPU-two-thread and JavaScript** lane passes **287 strictly
framed observations / 138,007 compared bytes** in batches of at most 64 actions.
All accepted files use the actual new public file call and consumed formatted
export. Nineteen representative cases are independently reopened for the
Surface bridge/explicit Surface loader; recognized names additionally exercise
generic/default and both decode-reference routes. Six unsupported generic
filename selections retain their exact failure, distinct from the successful
explicit helper. RGB logical words' high bytes remain zero. Both QOI channel
counts and colorspaces, every opcode family, hidden-alpha cache behavior,
non-power-of-two shapes, 4096-axis endpoints and the nonuniform 81×63 image
remain in the file corpus without substituting expected output.

The **69 ordinary-file typed controls** include all header-prefix lengths,
header/size/operand/marker/run errors, non-QOI raster data, missing paths/parents,
a populated directory, two cap+1 sparse files (including a misleading suffix)
and one 4 GiB sparse file. The inclusive QOI encoded-byte cap remains
**83,886,102**: successfully reported cap+1 sizes yield `UnsupportedImageSize`
before reading, whereas **4,294,967,296** bytes yield the host `EOVERFLOW` file
error. Exact synthetic code/message propagation, invalid-byte wrapping and
zero/exact/short/long complete-length checks are independently exercised.
No physical byte-greater-than-255 fixture or nondeterministic short-read race
is claimed. The local directory rejection was at read, code 21.

A separate boundary program performs **100 sequential cycles under
`RLIMIT_NOFILE=64`**, checking exact outcomes for RGB/RGBA success, decoder
failure, directory/read failure, cap rejection, size overflow and two
real-opened-handle stage controls. Those stages inject short-read/read-error
results into the real shared close continuation; they are labeled internal
boundary checks. The terminal marker follows one final raw-byte-checked valid
load. The shared source establishes close-before-result-processing/decoding;
low-descriptor repetition detects accumulated ordinary leaks in these runs.
Pinned Base discards close errors, so this does not establish successful OS
close reporting, new close-error parity or a universal no-leak theorem.

Fresh-child peak RSS for sparse/closure CPU-1/CPU-2/JavaScript was
**9,568,256 / 9,568,256 / 82,685,952 bytes**, below the predeclared 256 MiB ceiling.
An isolated candidate-only **1,048,577-byte** full read reaches
`InvalidImageHeader`, discriminating the QOI cap from the 1 MiB raster/HDR cap.
Its peaks were **27,000,832 / 27,131,904 / 161,636,352 bytes**, below a separate
fixed 1 GiB ceiling. Runtime and compilation memory are not combined. These
post-run checks are not live memory limits; strict runtime timeouts and the
unchanged pre-read guard are retained. The **193.281-second** focused duration
is local harness evidence, not a throughput or maximum-area guarantee.

The run seals **433 artifacts**, including **99 dependency/tool files**,
complete fixture recipes/manifests, generated programs, outputs and **34
successful subprocess receipts**. Source/tool drift checks run throughout and
at the end; sparse holes are represented by logical sizes and tiny prefixes,
never full-file hashes. Fresh run/native-build namespaces and pre-validation
stale-pass invalidation prevent reuse of old results. CI adds the new gate and
narrow report/manifest/program/log globs, explicitly excluding sparse fixtures;
all previous lanes, matrix entries, permissions and oracle settings remain.

Complete pinned `PROOF.bend` returns `All terms check.` for **115 laws**, with
all 110 previous laws retained and five new pure cap/length facts. These laws
do not prove host IO, allocation or closure. All **443 Python tests** pass with
zero skips under the activated toolchain, including 11 new focused harness
tests. An earlier unactivated discovery skipped one clang-dependent test; the
complete activated rerun is the qualification result.

Fresh serial regressions also pass against the same final library-source
hashes: the unchanged formatted QOI memory gate checks **121 images, 67 typed
failures through both memory entrypoints, and 638 observations / 554,344 bytes
per lane**. Canonical clean-loader conformance checks **261/261 scenarios /
40,101 pixel/numeric words** on all three lanes; an additional strict replay
checks every field's type/cardinality/value, **333 QOI bytes and 23 palette
words per lane**. Fresh native qualification selects `AccurateGradient` and
`Glibc241AngleRn`, without changing frozen math calls, fixtures or tolerances.
All trailing ownership/transform/decode contracts, three PPM examples and
legacy QOI file roundtrip/missing/malformed/oversize controls pass. Existing
Surface file loading passes **59 native cases, three boundaries and 100 fd64
cycles** on CPU/JavaScript; the dedicated HDR file gate passes **26 files /
18,035 pixels, five controls and 100 closure cycles** on those lanes. Heavy
compilation was serialized. The five canonical native invalid-domain control
processes terminate with their expected rejection codes; every other recorded
regression subprocess succeeds.

Only **`raylib:function:LoadImage`** changes mapping/scope/gaps/evidence, remaining
partial; all 1,884 entry statuses and existing gate statuses are unchanged.
Core totals remain **117 partial / zero complete**, a zero-started/zero-completed
native-API delta. `LoadImageFromMemory`, RAW loading, image types and export
statuses are untouched. The implementation narrows one original-format file
gap without claiming complete `LoadImage` coverage.

These are local Linux x86-64 CPU/Bun file results. macOS/hosted qualification for
the new gate, GPU IO, Windows/browser JavaScript, big-endian/native pointer ABI,
maximum-area allocation, concurrently changing/special files, generic formatted
or float dispatch, other original codec formats and complete integration/resource/
performance coverage remain open. No new hosted or GPU result is inferred from
older Surface or memory runs. Full scoped results, hashes and regression
receipts are in [the file evidence report](evidence/qoi-formatted-files.json).


## Checked formatted QOI export (2026-10-02)

The [formatted QOI contract](FORMATTED-QOI-EXPORT.md) adds explicit
`Image.Formatted.to_qoi` and `write_qoi` adapters for the existing checked owner
domain. Original RGB888 (4) and RGBA8888 (7) select header channels 3/4; formats
1/2/3/5/6/8 retain the exact owner before conversion or IO. Integer packing
preserves source bytes, RGB internal alpha is opaque and colorspace is always
zero. `QoiSourceError{image}` retains an unsupported owner;
`QoiFileError{code,message}` preserves accepted Base failures. Every acquired
writer handle is closed after the write attempt. The legacy Surface encoder
retains header 4 and its existing opcode selection. The native QOI-specific
original-format check, rather than generic `LoadImageColors` preparation,
defines the accepted source domain.

The [focused gate](../tools/formatted_qoi_export_probe.py) passes on local
Linux x86-64 **CPU-one-thread, CPU-two-thread and JavaScript**: **295 source
cases (273 accepted / 22 rejected), 382,078 total source pixels, 1,415,214
encoded bytes and 1,373,353 decoded original-format bytes**. Each lane checks
**1,409 tagged records** in batches of at most 16 cases. Complete candidate pure
bytes and actual sentinel-replacing `.dat` files match actual native
`ExportImage(.qoi)`. Native decoded metadata and every raw byte are observed
before normalization, alongside separate Surface observations and formatted
memory/file decoding. An independent strict parser validates header/operands,
run bounds, complete pixel count, exact marker and EOF; it does not synthesize
expected bytes through a second encoder.

Parsed native output exercises **all six QOI opcode families, 63 DIFF opcodes
and all 64 INDEX slots**. Zero-delta DIFF correctly selects RUN. Twelve
isolated just-outside DIFF controls require LUMA fallback; the corpus also
covers the LUMA threshold/residual matrix, wrapping, cache collisions, alpha-
only changes, hidden RGB, initial/noninitial runs through 125 pixels, run
crossing across rows, padded capacities, both 4096-axis bounds, full 33,024-pixel
traversals and seeded mixtures. Paired RGB/opaque-RGBA files differ only at
header byte 12. Factory, Surface bridge and decoded/loaded owners preserve
original-format semantics; channel-3 hidden alpha is discarded and input
colorspace 1 canonicalizes to 0. The 513×513 changing-alpha RGBA stress file is
**1,315,867 bytes**, exceeding the generic raster-loader cap while staying in
direct-byte/QOI-specific verification.

Rejected formats use correctly typed native packed/R32 backing, preserving
all source bytes before and after native `ExportImage`. R32 native controls
stay within finite `[0,1]`, including signed zeros/subnormals and safe truncation
neighbors. No malformed backing or undefined out-of-domain casts reach native.
Pure/writer rejections retain metadata and every byte through reuse chains,
with existing sentinels unchanged and absent outputs absent.

Each lane passes **801 accepted-source and 7,200 retained-source repeated IO
calls**. The ordinary `RLIMIT_NOFILE=64` program performs 100 cycles per
accepted format for success, ENOENT and EISDIR, with interleaved exact-owner
rejections and a final successful write. A separate zero-file-size-limit run
with ignored SIGXFSZ forces 100 post-open EFBIG calls per accepted format and
checks zero-byte truncation. Exact direct-Base code/message baselines are
required; EMFILE cannot pass as EFBIG. These checks support acquired-handle
closure on the recorded lanes, without claiming native failing-device,
short-write or close-error equivalence; Base exposes no close result.

The reference uses a **fresh GNU 14.2.0 raylib archive**, **Clang 19.1.7** native
oracle and **Bun 1.3.12** tooling, with the exact pinned Bend overlay. Nine
native qualification controls include signed-char wrapping. The focused run
retains **1,979 sealed artifacts, 2,217 artifact hashes and 140 library/dependency
source hashes**, including native QOI/rtextures sources, full inputs, generated
code/binaries, logs and receipts. Strict framing/cardinalities/types, source/tool
drift checks, fresh namespaces and failed-report admission before argument
validation prevent partial or stale success. The **331.715-second** focused
duration is local harness timing, not a performance claim.

Complete pinned `PROOF.bend` reports `All terms check.` for **127 laws**, keeping
all previous 115 and adding twelve scoped export facts: routing for all eight
formats, RGB/RGBA integer sample packing, zero-length packing and equality of
the Surface encoder wrapper with channel 4. These facts do not prove universal
codec correctness, file IO, allocation or closure. All **472 Python tests**,
including **29 focused guardrail tests**, pass.

Fresh implementation regressions pass for the existing formatted QOI memory
gate (**121 images, 67 typed controls, 638 records / 554,344 compared bytes per
lane**), formatted QOI file gate (**135 files, 69 typed controls, 287 records /
138,007 compared bytes per lane**, plus fd64 closure and separate large-read
controls), and Surface suffix-export gate (**41 complete files / 3,803 encoded
bytes**, retained-source/error and repeated IO controls). The final canonical
run, bound to the measured ledger and regenerated metadata, passes **261
scenarios / 40,101 words** on CPU-1/CPU-2/JavaScript. Independent strict replay
checks every field, type and length, including **333 QOI bytes / 23 palette
words per lane**. All trailing CPU/JS contract, transform, decoding, PPM example
and QOI file-roundtrip checks complete successfully. Its **495.265-second**
duration is a local harness observation, not performance parity. Earlier runs
remain explicitly preliminary; the final aggregate receipt is complete. These
distinct receipts are retained in
[formatted-qoi-export.json](evidence/formatted-qoi-export.json).

The ledger delta against `186ba887c4bdd8a9cc672019abc1a01ac37d3b69` is confined
to **`raylib:function:ExportImage`** mapping/scope/gaps/evidence, remaining
partial. All existing entry and gate statuses are unchanged, including
`ExportImageToMemory`. Core totals remain **117 partial / zero complete**, and
Jonmath remains **142 partial / zero complete**: zero newly started or completed
native APIs. The blanket unqualified formatted-QOI gap is replaced by the
recorded checked-owner slice. CI invokes the focused gate and retains its build
artifacts without removing any existing lane, matrix, permission or oracle.

No new hosted/GPU, maximum-allocation, exhaustive-input or performance claim
is made. Non-Surface suffix dispatch, wider source owners/options, JPEG/KTX,
native ABI/callbacks, failing-device/short-write/close equivalence and complete
integration/resource/target/performance coverage remain open. Focused QOI
success does not settle unrelated native-angle or aggregate qualification.

## Format-preserving PNM memory loading (2026-10-02)

`Image.Formatted.decode_pnm` adds a dedicated P5/P6 memory factory in the partial
`raylib:function:LoadImageFromMemory` entry. It preserves native grayscale (1)
or RGB888 (4), width/height in 1..4096 and an implicit single mip level. Both
8-bit and 16-bit PNM inputs produce the actual native route's reduced **8-bit**
output: little-endian wide samples retain their second stored byte, without
rescaling to maxval. Integer repacking avoids grayscale luminance conversion.
The existing checked byte/header/size/truncation rules and Surface RGBA8
normalization remain unchanged. See [PNM.md](PNM.md) for the complete contract.

The focused local Linux x86-64 gate passes **96 native images / 64,482 pixels**,
with **120,514 raw native-format bytes** and **257,928 separately normalized
bytes** before alias totals. Actual pinned `LoadImageFromMemory` emits native
width/height/mipmaps/format and every raw byte before normalization. Selected
PGM/PPM lower/uppercase aliases bring the native output to **234 observations**.
Only independently validated, bounded, complete accepted fixtures reach native;
**73 typed controls** run through both checked candidate APIs alone.

Each CPU-one-thread, CPU-two-thread and JavaScript lane passes **710 records /
885,750 compared bytes** in **23 batches**, comprising **361,542 raw** and
**524,208 normalized bytes**, with zero differences. Independent raw output,
Surface bridges, legacy normalized decoding and dispatch, factory exports and
threaded in-bounds/rejected point-read owners are compared. Logical grayscale
high 24 bits and RGB high bytes remain zero; export excludes storage padding.
Candidate mipmaps are the owner's implicit contract, not a measured field.

Fixtures retain all 30 historical accepted streams and add both kinds/depths,
1x1 and padded shapes, both 4096-axis endpoints, 5,103-pixel nonuniform images,
full byte ramps, distinct RGB boundary values and wide-sample first/second-byte
discriminators. Maxvals 1/15/100/255/256/257/1000/65535, samples above maxval,
all six maxval separators, CRLF/raster whitespace/hash, leading zeros, comments
and ignored tails retain the native checked profile. Strict field/type/order/
byte-length framing and exact typed-error precedence fail closed.

The reference is a fresh isolated Memory/Release archive with verified
`CUSTOMIZE_BUILD=ON` and `SUPPORT_FILEFORMAT_PNM=ON`; pinned default raylib
configuration disables PNM. GNU 14.2.0 builds the archive and Clang 19.1.7
builds the reference; Bun 1.3.12 drives the pinned Bend overlay. Compiled native
qualification establishes little-endian format-1/4 and second-byte retention.
Source/toolchain/build/input/output hashes, compiler/archive identities and
clean-loader child-environment receipts are sealed and rechecked without
changing parent loader variables. An initial CMake-cache whitespace-parser
failure stopped before native archive build. Its failed report is retained;
a corrected parser, expanded guardrail and fresh full-suite/probe retry pass.

The complete proof verdict is `All terms check.` for **132 laws**: 127 preserved
plus five scoped channel/packing/empty-traversal structural laws, not a universal
codec proof. All **495 Python tests**, including **23 focused harness tests**,
pass without skips. The fresh unchanged formatted QOI memory regression passes
**121 images, 67 typed controls and 638 observations / 554,344 compared bytes**
per CPU-one-thread/CPU-two-thread/JavaScript lane.

Fresh canonical clean-loader conformance passes **261 scenarios / 40,101
pixel/numeric words** on CPU-one-thread, CPU-two-thread and JavaScript against
the frozen API metadata. Strict full-record replay also checks **333 QOI bytes
and 23 palette words per lane**. Ownership, transform and decode contracts,
three PPM examples and legacy QOI roundtrip/missing/malformed/oversize file
controls pass. The final full unit suite again passes all **495 tests**.

The unchanged normalized PNM gate passes **30 native images / 8,844 pixels and
16 typed controls** on CPU/JavaScript. The unchanged generic memory-dispatch
gate passes **534 token/content pairs (462 native loads) plus five typed
controls**, with all nine batches complete in each CPU/JavaScript lane. The
unchanged generic file-dispatch gate passes **59 native file cases, three
boundary controls and 100 low-descriptor cycles at fd limit 64 per lane** on
CPU/JavaScript. These three scripts run in a verified clear inherited loader
context using the freshly built canonical archive; its PNM configuration,
compiler and archive hashes are retained. They establish regressions for the
existing Surface APIs and do not claim PNM formatted-file loading. Historical
Surface evidence remains separate and does not qualify the new formatted
adapter on GPU/Metal.

CI invokes `tools/pnm_format_probe.py --reference-env clean-loader` beside the
QOI memory gate with the same pinned checkout paths, and retains its scoped
run artifacts. All prior steps, matrix entries, permissions, timeout and oracle
settings remain in place. This wiring does not establish an exact-commit hosted
pass. Only `LoadImageFromMemory` changes mapping/scope/gaps/evidence, remaining
partial; all other API statuses stay unchanged. PNM formatted files, generic
formatted/float dispatch, big-endian, GPU/Metal, Windows/browser and other unrun
targets, maximum-area allocation, native pointer/OOM parity and representative
integration/resource/performance qualification remain open. No API is complete.

Focused results, provenance, proof/test summaries, prior failure and final
regression receipts are in [the durable evidence](evidence/pnm-formatted.json).


## Reconstructed format-preserving PNM file loading (2026-10-03)

This is **new reconstruction evidence**, not recovery of the original
`36f5d0b5a811297b349c45aa6ddc3a9a067ac8d3` runtime report. Exact recovered law,
proof, README and ledger-scope text is kept separate from the newly reconstructed
11-line `Image.Formatted.load_pnm` wrapper and file harness. The adapter uses the
unchanged shared byte-file boundary with `RasterFile`'s inclusive 1,048,576-byte
cap, closes before read-result processing/decode, and preserves the existing
native-format PNM decoder's ownership and checked error behavior.

The final-source [focused report](evidence/pnm-formatted-files.json) passes on
local Linux x86-64 CPU-one-thread, CPU-two-thread and JavaScript. It checks
**156 accepted files / 64,542 pixels**, **132 actual LoadImage paths plus 24
explicit PNM native paths**, and **74 candidate-only controls**. Each lane
passes **626 observations / 129,072 bytes** in 20 strictly framed batches.
Native format-1/4 bytes total **120,634** before independently observed RGBA8
normalization. The exact-cap valid file is a separate native/candidate reference.

Each lane also passes **1,009 individually framed closure records**: eight
synthetic stage checks, 100 fd64 cycles over ten acquired-handle paths and one
final valid load. Separate measured sparse controls cover cap+1, misleading
`.qoi`, 256 MiB and U32-size overflow. Exact-cap acceptance is measured separately
with the unchanged 1 GiB ceiling; closure/all-sparse measurements use the unchanged
256 MiB ceiling. Measured values appear in the
[file contract](IMAGE-FILES.md#pnm-file-reconstruction-verification).
The focused run takes 642.935 seconds.

The new gate verifies a fresh isolated GNU 14.2.0 native archive with actual
PNM-enabled CMake/compile definitions; Clang 19.1.7 reference/candidate tooling,
pinned Bun 1.3.12, the declared Bend overlay, endian/raw-format qualification and
clean-loader child receipts remain explicit. There are 496 dependency hashes
and 1,179 sealed artifacts in the focused report. The local all-command recorder
owns process groups so compiler/candidate descendants are killed and reaped on
timeout/interruption; only the actual resource launcher claims fd64. Real
negative tests cover SIGTERM-ignoring candidate and compiler grandchildren,
stale or absent compiler output, failed startup and forged resource receipts.

The first new attempt failed candidate compilation on an affine harness-helper
annotation, before any candidate acceptance. A later attempt was invalidated by
source sealing while the resource-lifecycle fix was being introduced. Another
was explicitly interrupted before the bounded argument/setup/whole-process-tree
audit. Those failed/interrupted receipts remain diagnostic, never a passing
result for the changed harness. The final frozen-source run above completed
from a new isolated build directory after all confirmed fixes.

The [coverage matrix](PNM-FILE-RECONSTRUCTION.md) maps the recovered contract's
behavioral, ownership, IO, framing, source, native-profile, resource and failure
obligations to executable new/preserved checks. The lost 49-method file suite is
not available for assertion-identity comparison; the new suite is organized into
37 methods with numerous mutation subcases. Counts alone are not an equivalence
claim. The 495 published baseline Python tests and their predicates are unchanged.

The fresh full Python suite passes **532 tests** (495 preserved baseline plus
37 new file methods), without skips. `python3 tools/check_project.py` passes and
API regeneration exactly reproduces the recovered original ledger, API-map and
raylib documentation blobs. The complete independent proof check returns
`All terms check.` for **133 laws**, including the restored raster-cap law.
Canonical conformance separately requires that same full proof verdict.

`LoadImage` remains partial; no API completion count increases. GPU/Metal IO,
macOS/Windows/browser, big-endian, maximum-area/OOM parity, native callback and
allocation ABI, concurrent/special-file semantics, reported OS-close failures,
generic formatted/float dispatch and complete performance/integration remain
unqualified. Shared source/oracle/tolerance/toolchain pins and CI workflows are
unchanged by this increment.


Fresh regression results are retained in the
[reconstruction validation record](evidence/pnm-files-reconstruction-validation.json):

- Formatted PNM memory: 96 native images / 64,482 pixels, 73 candidate-only
  controls, 710 records / 885,750 bytes per CPU-1/CPU-2/JavaScript lane
- Canonical clean-loader conformance: 261 scenarios / 40,101 pixel/numeric words
  per CPU-1/CPU-2/JavaScript lane, all ownership/transform/decode contracts,
  three PPM examples and legacy QOI file round trips/errors
- Validation-only strict replay: every complete ordered record and field matches,
  including 333 QOI bytes and 23 palette words per lane. Nine negative controls
  cover framing/types/order plus validly framed altered QOI, palette and alpha
  border values. The canonical comparator/fixtures remain unchanged
- Surface PNM: 30 images / 8,844 pixels and 16 typed controls on CPU/JavaScript
- Generic memory dispatch: 534 token/content pairs (462 accepted native loads)
  and five typed controls on CPU/JavaScript
- Generic file dispatch: 59 native file cases, three boundary controls and
  100 cycles at fd64 on CPU/JavaScript

The canonical archive is freshly built in this worktree with PNM enabled;
configuration/flag/archive hashes and clean-loader orchestration receipts are
retained. Native PNM memory builds a separate fresh archive. The independent
focused audit verifies every one of 1,179 sealed artifacts, 103 successful
process-group receipts and all 626 primary + 1,009 boundary + four sparse + one
exact-cap records per lane with its own strict parser. Its script, command and
result are preserved with the validation evidence.

## Reconstructed format-preserving TGA memory loading (2026-10-03)

This batch is a new reconstruction on published baseline `d3b93896`, not a
recovery of the lost local checkpoint or its runtime receipts. It extends only
partial `raylib:function:LoadImageFromMemory` through `Image.Formatted.decode_tga`.
Native output channels are separate from input sample/index byte width; direct
type/depth or indexed palette depth selects formats 1/2/4/7. Integer packing
preserves gray, gray-alpha, expanded RGB888 and RGBA8888 bytes, while the existing
checked TGA decoder and Surface RGBA8 behavior remain unchanged. See the
[contract](TGA.md#format-preserving-tga-memory-loading) and explicit
[obligation-to-test/probe/receipt matrix](TGA-REBUILD-COVERAGE.md).

The fresh focused Linux x86-64 gate passes **169 native images / 61,857 pixels**,
**155 checked-only controls**, and **377 actual native observations**. Actual
width/height/mipmaps/format and **155,600 raw bytes** precede separate observations
of **247,428 normalized bytes**, with selected uppercase alias reloads. Every
CPU-one-thread, CPU-two-thread and JavaScript lane passes **1,311 records /
1,024,632 bytes**, split into **466,800 raw / 557,832 normalized bytes**. No
malformed control reaches native or is counted as a native rejection.

All 64 published accepted streams and 23 published controls are preserved. The
matrix covers all four layouts, gray/alpha ramps, packed16/gray-alpha16 and
palette-depth/index-width discriminators, ignored direct palette fields,
vertical orientation, ignored descriptor bits, zero alpha, RGB555 expansion,
palette byte skips/fallback, maximal IDs/tails, raw/repeat 127/128/129 packets and
cross-row runs. Every layout includes 1x1, padded 3x5, both 4096-axis boundaries
and nonuniform 81x63 images. Factory output, high-bit invariants, retained
in-bounds/out-of-bounds point-read owners, consuming bridges and unchanged
Surface/dispatch observations are independently compared. Candidate mipmaps are
an implicit owner contract, not a measured field.

The first fresh attempt stopped after 19 passing batches (**608 records per
lane**) when compiler batch 19 exited **-9** with empty output. Generated source
was 406,854 bytes, and host memory had been observed around 8.3/9.7 GiB; OOM is
not proven. No timeout or comparison mismatch occurred. Failure remained
fail-closed, its process group was gone, and the direct child was reaped.
The independent reviewer verified its **868 seals** and complete partial output.
The failed report and exact reviewed source have a separate portable archive.

The independently reviewed repair changes execution grouping only: **43 ordered
partitions**, at most **32 actions / 196,608 source bytes** each, with an observed
maximum of **185,894 bytes**. All actions, roles, fixture/control inputs, oracle,
compiler, domain limits and the **600-second timeout** remain unchanged. The
entire gate reruns from a new native build. Input/reference hashes match the
failed capture, the full action digest is preserved, and former batches 0–19
regenerate identically before regrouping. Partition schema, order, coverage,
source/action hashes and per-lane byte totals fail closed.

The reference archive is a fresh isolated Memory/Release build with verified
`SUPPORT_FILEFORMAT_TGA=ON`, `CUSTOMIZE_BUILD=ON`, `PLATFORM_MEMORY` and
`EXTERNAL_CONFIG_FLAGS`; pinned raylib disables TGA by default. Native
qualification checks actual channel/depth/index behavior before reference
capture. GNU 14.2.0 builds the archive, Clang 19.1.7 builds the reference, and
pinned Bun 1.3.12 drives the exact Bend overlay. Native child loaders are cleaned
without mutating the parent. All **1,224 seals** and **181 successful owned-process
receipts** are independently checked. A separate strict parser replays every
native/candidate record and byte. Real harmless descendant tests qualify
bounded process-group cleanup without touching an unrelated process; success,
nonzero, timeout and interruption paths preserve their receipts.

The full proof says `All terms check.` for **148 laws = 132 published + 16 scoped
TGA facts**, not a universal codec proof. The complete Python suite passes
**544 tests = 495 published + 49 newly reconstructed TGA tests**, without skips.
This count is not compared as equivalent to the lost combined tree's 582 tests:
that total also included separate PNM-file and CI work. Exact lost source/test/
fixture identity is unavailable; the coverage matrix maps its retained
obligations to fresh tests instead. All **149 published test/tool/workflow/pin/
overlay files** remain unchanged, as do Jonmath and all 44 other support modules.

Fresh canonical clean-loader conformance and independent strict replay pass
**261 scenarios / 40,101 pixel/numeric words / 333 QOI bytes / 23 palette words**
per CPU-one-thread, CPU-two-thread and JavaScript lane. All 17 compile batches,
ownership/transform/decode contracts, PPM examples and QOI file/error checks
pass against unchanged published fixtures. The independent audit and its source
are included in portable receipt backups.

Unchanged Surface TGA passes **64 images / 1,219 pixels**, **23 typed controls**,
**11 exact exports / 3,447 bytes** and actual file output on CPU/JavaScript.
Generic memory dispatch passes all **534 token/content pairs (462 native loads)
plus five controls**, with nine completed batches per CPU/JavaScript lane.
Generic file dispatch passes **59 native cases, three boundaries and 100 fd64
cycles** per lane. These legacy scripts run as clean-loader children against
the fresh canonical TGA/PNM-enabled archive and remain preservation evidence;
they do not add formatted TGA file loading.

The unchanged formatted TGA export gate passes **304 images / 619,451 pixels**,
**2,212,918 encoded / 2,477,804 decoded bytes**, all **38 batches**, and **3,200
typed IO checks** per CPU-one-thread, CPU-two-thread and JavaScript lane.
FloatRGB BMP/TGA export passes **12 files**, **3,918 encoded / 4,064 decoded
bytes**, two retained rejected-owner controls, two IO-error controls and
100 fd64 closure iterations on CPU/JavaScript. Native archive/config hashes
remain stable across the complete serial regression run. The Surface TGA,
generic memory/file and FloatRGB runners do not retain their raw result stdout;
the formatted TGA export runner does retain sealed byte streams. Its independent
review replays the full output, retained files and IO records and rehashes all
**2,298 seals**. The four older runners are explicitly limited to verified
source/report/exit/manifest evidence. This distinction is retained alongside the
independent full record/byte replays of the focused and canonical gates. No export
scope expands.

All results here qualify the isolated TGA-only source rooted at `d3b93896`.
They do not alone qualify a subsequent combined PNM/CI/TGA integration; changed
library hashes require fresh integrated focused/proof/canonical verification.

Only one API ledger entry changes scope/mapping/gaps/evidence; its status stays
partial and no complete API is claimed. The unrelated PNM-file gap is preserved
on this TGA-only branch until its separate verified integration. Generic
formatted/float dispatch, formatted TGA file IO, remaining codecs, nondefault
flags, wider dimensions, native pointer/allocation/OOM behavior, maximum-area
resources and complete integration/performance/target coverage remain open.
Workflows are unchanged. Exact-commit hosted CI, GPU/Metal, Windows/browser and
other unrun hosts are not qualified here. Full fresh receipts and the retained
first failure are in [the reconstruction evidence](evidence/tga-formatted-rebuilt.json).


## Fresh combined TGA memory and PNM file integration (2026-10-03)

The approved isolated TGA checkpoint `f6a48cd` is integrated onto published main
`0c663c9a`, preserving its PNM file wrapper and all original conformance gates.
[Fresh integrated evidence](evidence/tga-integrated-validation.json) records the
new source hashes, complete reports, independent replay and validation scripts.
[The integration record](TGA-INTEGRATION.md) states exact merge and scope limits.

The combined suite passes **585 Python tests** and all **149 proof laws** with
`All terms check.` Syntax, project/API drift and whitespace checks pass. TGA
passes **169 native images / 155 checked controls / 1,311 observations /
1,024,632 compared bytes per CPU-1/CPU-2/JavaScript lane**. All 43 source-bounded
partitions remain; the shorter worktree import path makes the fresh maximum
185,890 bytes. Independent replay validates all 1,224 seals and 181 receipts.
PNM files freshly pass **156 native files / 74 controls / 626 primary records /
129,072 bytes per lane**, plus all closure, sparse and exact-cap records and
resource ceilings; independent replay verifies 1,179 seals and 103 receipts.

Fresh canonical clean-loader conformance and strict complete-record replay pass
**261 scenarios / 40,101 words / 333 QOI bytes / 23 palette words per lane**.
Both strict replays exercise nine negative controls. Complete contracts,
transforms, decoding, examples and QOI file/error checks pass. Every reference
archive is new and the pinned toolchain/overlay is unchanged. Earlier broad
Surface/generic-memory/file/formatted-TGA/FloatRGB receipts remain scoped to
the isolated source; they are not new integrated reruns.

The mandatory TGA-memory gate follows the original seven formatted gates on
both platforms. The frozen baseline, original 79 payloads/156 paths, four
workers, setups/pins/environments/budgets and both direct-four-dependency
fail-closed aggregates remain exact. The new totals are 72/eight gates and
140/17 artifact paths per core/formatted worker; all 4,802 shell truth-table
invocations remain, with explicit added-gate/loader/artifact mutation coverage.

The [published 79-gate PNM/split run](https://github.com/jonathanperis/jonlib/actions/runs/37130692849)
at exact commit `0c663c9a85a8560199ccef89f76251ea05cfce8b` passed Checks,
all four workers and both aggregates with all four evidence artifacts. Observed
worker durations are Ubuntu core/formatted **81m53s/47m21s** and macOS
core/formatted **65m33s/52m11s**. This predates TGA memory and does not qualify
the new integrated 80-gate tip. Final exact-commit hosted checks/artifacts remain
required; no new GPU/Metal, Windows/browser, big-endian, maximum-area allocation
or representative performance qualification is claimed. No API becomes complete.

## Format-preserving TGA file loading (2026-10-03)

The [new focused evidence](evidence/tga-formatted-files.json) qualifies the
dedicated `Image.Formatted.load_tga` wrapper on local Linux x86-64 CPU-one-thread,
CPU-two-thread and JavaScript. It preserves native formats 1/2/4/7 through the
unchanged inclusive 1 MiB RasterFile boundary and checked TGA memory decoder.
Only partial `raylib:function:LoadImage` expands; no API becomes complete.

The focused gate passes 225 accepted ordinary files, 154 candidate-only controls,
1,283 primary records / 854,352 bytes per lane, plus complete 1,209-record closure,
four sparse and four exact-cap observations. All 169 accepted memory streams are
reused byte-for-byte as files. Actual raw native metadata/bytes precede separate
normalization. Fresh archive settings, tool/compiler provenance, path/input/
source/artifact identities, exact ordered partitions and all resource ceilings
are sealed and independently checked. Full contracts, metrics and limitations
are in [image file loading](IMAGE-FILES.md#tga-file-verification).

On the same unchanged runtime sources, formatted TGA memory, PNM files, QOI
files, formatted TGA export and canonical records also pass independent complete
replay. Canonical checks all 261 scenarios / 40,101 words / 333 QOI bytes / 23
palette words per lane and rejects nine mutated records. Surface TGA and generic
memory/file gates pass fresh source/report/exit/fixture checks; their inherited
full stdout was not retained, so no independent full-output replay is claimed.
The pre-CI source freeze passed 645 Python tests without skips and all 149 laws
with `All terms check.`. After the reviewed CI/docs delta, the final pinned-PATH
suite passes **647 tests with zero skips**, all 149 laws, project/API/syntax
checks and independent workflow byte/object preservation. The final checks are
recorded separately in the new evidence report. These structural laws are not a
universal codec/IO proof.

The reviewed CI addition retains the 79-gate frozen baseline and earlier TGA
memory gate, then appends TGA file loading and its precise sparse-artifact
exclusions on both OS workers. The [81-gate hosted run](https://github.com/jonathanperis/jonlib/actions/runs/37145573468)
at exact published commit `08dd860ebd24c8d1f49eb130d848764723e1f5c7` is verified
successful on 2026-10-03: Checks, all four workers, both aggregates and all four
distinct nonempty evidence artifacts pass. That result is historical to the
TGA-file checkpoint and does not qualify the subsequent BMP increment.
GPU/Metal IO, Windows/browser, big-endian,
maximum decoded-area/heap, OOM/native pointer ABI, concurrent/special files and
full performance qualification remain gaps.

## Format-preserving BMP memory loading (2026-10-03)

The dedicated `Image.Formatted.decode_bmp` source adds RGB888 (4)/RGBA8888 (7)
metadata and integer-packed raw output to the unchanged checked BMP decoder.
Only partial `raylib:function:LoadImageFromMemory` expands. The command is:

```sh
python3 tools/bmp_format_probe.py --reference-env clean-loader \
  --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

The dedicated fail-closed harness preserves all 98 accepted historical BMP
streams and 46 typed controls. Independent native admission checks complete
headers, effective masks, palette counts and indices, native double gaps,
orientation and padded rows. Actual `LoadImageFromMemory` dimensions, format,
mipmaps and every native byte are captured before separate normalization.
Candidate observations include complete raw output, checked-factory and
export/import round trips, logical high-bit invariants, valid/invalid point
reads with retained owners, consuming Surface bridges, normalized Surface
decoding and selected generic dispatch. Malformed controls stay candidate-only.

The oracle uses a fresh BMP-enabled Memory build, verified cache and compilation
definitions, tiny RGB/RGBA/mask qualification, pinned source and tool identities,
clean-loader child receipts and post-run seals. Exact generated-source partitions
must remain ordered and exhaustive, at most 196,608 UTF-8 bytes and 32 actions.
Every record has strict framing, schema, scalar types, exact lengths and order;
owned process groups are terminated and reaped on interruption or timeout.

The [focused evidence record](evidence/bmp-formatted-memory.json) records fresh
local Linux x86-64 CPU-1/CPU-2/JavaScript passes: **224 native images, 597 typed
controls, 2,850 complete records and 873,268 bytes per lane**. Actual raw metadata
and 132,367 raw bytes precede 156,756 separate normalized bytes; uppercase aliases
are separately retained. All 91 partitions pass, with a largest source of
193,198 bytes. The gate takes **1,765.059 seconds (29m25s)** on this host, with
373 successful per-command receipts retaining timings, timeouts and owned-group
cleanup. This is a gate-duration measurement, not an application benchmark.

Independent complete replay passes the new formatted BMP gate, all 78 formatted
BMP exports / 331,465 decoded pixels, and all 261 canonical records / 40,101 words /
333 QOI bytes / 23 palette words per lane, including optional alpha borders.
It checks 2,839 source/artifact identities and rejects all 61 adversarial controls;
the separate strict canonical replay rejects nine mutations. Fresh Surface BMP,
generic memory/file, FloatRGB raster export, image-format and color/owner gates
pass their unchanged complete in-process comparisons and source/report/exit/
fixture checks. These older harnesses do not retain full native/candidate stdout,
so no independent full-output replay is claimed for them. The unchanged exporter
retains full byte output and seals, but its older inner receipts lack individual
timing/cleanup fields; its reviewed outer serial receipt supplies stage timing
and owned-process-group cleanup.

The frozen matrix completes 17 serial stages plus the focused gate, **710 Python
tests without skips**, all **158 scoped laws** with the complete pinned
`All terms check.` verdict, syntax and project/API checks. Independent source,
runtime and regression reviews find no remaining defects. These structural laws
are not a universal decoder/IO proof. Historical Surface evidence alone is not
used to establish the new raw metadata behavior.

The separately sealed final CI/documentation snapshot passes **715 Python tests
without skips**, all 158 laws and project/API/syntax checks. All 462 repository
files, the checker and independent workflow validator are bound during testing;
compiled library/probe/oracle identities remain unchanged. Independent workflow
review restores the entire predecessor byte-for-byte and verifies the four
original worker bodies unchanged. Two dedicated BMP workers add the 82nd gate on
both OS platforms, each retaining the 120-minute budget and exact setup pins.
Both compatibility aggregates directly require all six workers to succeed.
Six distinct nonempty evidence artifacts are separately required when verifying
the final hosted run. All 4,802 original and 98 additional shell truth-table cases
pass; the exact six-way conjunction is checked over 235,298 assignments. Raw-byte
workflow loading also rejects line-ending-only drift. Final evidence/prose
summaries are reviewed separately against retained tested metadata, avoiding
self-referential receipt hashes. Exact-tip hosted qualification remains pending.
GPU/Metal, Windows/browser, big-endian, maximum decoded area/heap, native pointer/
allocation/OOM semantics and representative performance remain unqualified.
The memory API has no encoded-input cap; the finite oracle budgets do not
introduce the separate file layer's 1 MiB cap.
