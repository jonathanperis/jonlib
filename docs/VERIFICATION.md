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
- 228 scenarios / 34,271 output words match pinned raylib exactly on each
  of native CPU one-thread, native CPU two-thread, emitted JavaScript, and forced
  Metal with the declared compiler overlay.
- The word count includes 1,827 exact numeric/collision result-bit probe cells.
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
- The pinned core header inventory contains 600 unique public functions; 81 have
  explicitly scoped Jonlib mappings. The raymath ledger additionally maps 139
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
| A1: nonempty, full-pixel differential suite | Pass | 228 scenarios per execution lane; strict comparison |
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
