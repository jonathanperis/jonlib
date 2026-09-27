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
- The pinned core header inventory contains 600 unique public functions; 104 have
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
