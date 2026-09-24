# Verification record

Date: 2026-09-24. Host: Apple M1 / macOS 27.0. Bun 1.3.12 and Apple clang 21.0.0.
The current base revision and exact compiler overlay are pinned in `toolchain.json`.

## Executed checks

```sh
python3 -m unittest discover -s tests -v
python3 tools/conformance.py --gpu
python3 tools/verify_bend.py --gpu
```

- Three harness test groups pass, including changed pixels, empty/missing results,
  invalid fixtures, Boolean/floating-point dimensions masquerading as integers,
  and compiler source/patch tampering or unexpected tracked changes.
- 53 scenarios / 15,733 complete RGBA pixels match pinned raylib exactly on each
  of native CPU one-thread, native CPU two-thread, emitted JavaScript, and forced
  Metal with the declared compiler overlay.
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
- The pinned header inventory contains 600 unique public functions; 21 have
  explicitly scoped Jonlib mappings. Remaining entries are not implemented.
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

## Acceptance status

| Criterion | Result | Evidence |
|---|---|---|
| A1: nonempty, full-pixel differential suite | Pass | 53 scenarios per execution lane; strict comparison |
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
| A19: default-filter evidence | Investigation complete; implementation open | Stock control 512/512 matches; float normalization differs in 4 cases / 7 channels on M1 |

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
after the naming correction. The default-filter precision mismatch remains an
explicit open implementation requirement, not a relaxed image comparison.

Regression scan: 23 callers checked, 21 assertions checked, 1 flagged/fixed.
