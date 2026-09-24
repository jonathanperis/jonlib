# Verification record

Date: 2026-09-24. Host: Apple M1 / macOS 27.0. Bun 1.3.12 and Apple clang 21.0.0.
Revisions are pinned in `toolchain.json`.

## Executed checks

```sh
python3 -m unittest discover -s tests -v
python3 tools/conformance.py
```

- Both harness test groups pass, including changed pixels, empty/missing results,
  invalid fixtures, and Boolean/floating-point dimensions masquerading as integers.
- 26 scenarios / 6,682 complete RGBA pixels match pinned raylib exactly on each
  of native CPU one-thread, native CPU two-thread, and emitted JavaScript.
- The owned-copy, out-of-bounds read, color packing/channel and Base.Image
  pixel/padding contracts pass on native CPU and JS.
- `PROOF.bend` checks: `All terms check.` The theorem is dimension preservation
  by clear; it is not a general proof of graphics correctness.
- The actual 64×64 PPM exported by `examples/headless.bend` matches every RGB
  component of the raylib reference scene.
- The pinned header inventory contains 600 unique public functions; 13 have
  explicitly scoped Jonlib mappings. Remaining entries are not implemented.
- Library source passes the no-unsafe/no-custom-foreign-import gate.
- Relative documentation links resolve, raylib's license is retained verbatim,
  and `.specs/` is ignored. No specification files were previously tracked.
- Both upstream dependency checkouts remain clean.

Exact source/input hashes, host, lane outcomes and generated full pixel arrays
are retained under `.build/`. The latest default run is `.build/conformance.json`.

## Acceptance status

| Criterion | Result | Evidence |
|---|---|---|
| A1: nonempty, full-pixel differential suite | Pass | 26 scenarios per CPU/JS lane; strict comparison |
| A2: clear/pixel/clipped rectangle/midpoint circle parity | Pass within declared profile | Explicit and seeded reference fixtures |
| A3: dimensions, ownership and bounded indexing | Pass for checked contract | Clear law, full outputs, owned-copy/get and clipping checks |
| A4: Bend-only source, CPU/JS behavior | Pass | Source gate and three execution lanes |
| A5: complete forced-on Metal gate | **Blocked** | Full suite fails; detailed reduction in METAL-INVESTIGATION.md |
| A6: API, commands, licensing and limitations | Pass | Documentation/source review |
| A7: corrupted output and empty suite rejected | Pass | Harness negative controls |
| A8: real headless export and Base.Image adapter | Pass | Native PPM comparison and CPU/JS adapter contract |

## Limitations

The complete GPU run failed and remains failed; the reduced successful probes
do not supersede it. `docs/METAL-INVESTIGATION.md` contains the reproduction,
observed failure messages and reduction evidence. No Bend runtime fix has been
made or claimed.

No live desktop window, audio device, browser UI, CUDA, Linux, Windows, Android,
performance comparison, long-run resource soak, or complete raylib conformance
was verified. The image tests are finite, not exhaustive over the documented
input domain. The public Surface constructor must retain the API's invariant.

## Regression review

Reviewed 46 authored caller/declaration contexts across Bend and Python,
generated-call templates, all public mappings, and 20 assertion sites (six
negative-control contexts, ten Bend exact-value comparisons, three output
comparators and the law). The scan caught output-dimension validation accepting
Boolean/float values through Python numeric equality. The parser now rejects
them; negative controls and the affected full conformance run pass after the fix.

Regression scan: 46 callers checked, 20 assertions checked, 1 flagged/fixed.
