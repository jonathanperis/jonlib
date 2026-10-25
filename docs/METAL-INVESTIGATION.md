# Metal dispatch failure and the declared compiler overlay

The pinned compiler is Bend 2.0.39. On the previous pin, Bend 2.0.27, the stock
generated Metal program fails on the full Jonlib image corpus, while CPU and
JavaScript lanes of the same program pass. Jonlib therefore builds against the
Bend base revision in `toolchain.json` plus the declared compiler overlay
`patches/bend-metal-dispatch.patch`. This page records the defect, the rejected
candidate fix and the adopted code-generation boundary.
Application steps are in [patches/README.md](../patches/README.md).

## Symptom

With the stock compiler, the GPU-capable conformance binary (every draw entry
marked `!`) fails under `--gpu on` before emitting a valid first result row,
with `bend: memory fault (machine stack overflow?)` or, for a shorter prefix,
`bend: frontier drained without a result`. The same binary passes with
`--gpu off`. Library source, fixtures and expected results are not involved:
the overlay alone makes the unchanged corpus pass on forced Metal.

## Findings

Reduction on stock Bend:

- Small programs pass on Metal: Base.Array set/get across a `!` call, a small
  surface rectangle update across `!`, and the radius-12 circle scenario alone.
  Many empty 1×1 scenarios and many independent scalar `!` calls also pass.
- Short scenario prefixes pass and match every reference pixel; longer prefixes
  of the same scenarios fail. Failure depends on how much code reaches the
  device dispatcher, not on any single scenario.
- Metal API/shader validation does not identify a useful shader fault.
- Generated-C instrumentation localized the failure to the circle path: the
  rectangle completed, the call through the generated circle helpers did not,
  and the runtime error field stayed zero.

The decisive experiment changed exactly one qualifier in fresh, uninstrumented
generated C: the flat circle loop (`Surface.circle.loop`) from `INLINE` to `FAR`
(`static __attribute__((noinline))`). With that single change the full corpus
matches every pixel on forced Metal; unmodified, it fails.

The compiler chooses `INLINE`/`FAR` from each helper's own emitted line count
(`SPIN_FAR = 256`). The circle loop falls below that threshold even though it
calls other large helpers, so large shared native helpers expand repeatedly into
the device dispatcher. This establishes an **inlining-sensitive failure**; it
does not prove a specific Apple Metal compiler defect versus a resource-limit
interaction.

## Rejected candidates

- A transitive-only inlining budget did not fix Jonlib.
- A broad policy that outlined helper bodies globally fixed Jonlib but changed
  the Metal ray-tracer checksum to `0` (expected `31932226`). Each new outline
  alone preserved the checksum; the combination did not. It was rejected.
- The one-qualifier generated-C edit above is a diagnostic, not a fix.

## Adopted boundary

The overlay budgets transitive helper expansion and repeated source call sites
at the **device dispatcher boundary**. Oversized calls receive a Metal-only
noinline wrapper. Helper-to-helper `INLINE`/`FAR` choices remain as upstream,
CPU/CUDA wrapper names alias the original functions, and wrapper liveness
follows the compiler's existing reference graph. Generated CPU/CUDA source is
identical to the stock compiler's after resolving the conditional wrappers.

Bend 2.0.38 counts a spin in characters (`SPIN_FAR` is 8192) and spells a
device-far spin `DFAR`. The patch written for 2.0.27 does not apply to that
emitter. The same dispatcher-boundary policy was re-ported in those units: a
helper whose own text already meets the threshold stays `DFAR` and does not
inflate the budget, and only a non-native caller receives the Metal `FAR`
wrapper. The 2.0.38 boundary was checked on CPU and JavaScript (the regression
prints 16000 and the generated C contains both `DFAR Term spin_` and
`FAR Term call_spin_`). It has not been re-run on Metal. The corpus result
above is the device evidence from the 2.0.27 pin. Upstream's fix for non-tail
recursion under `!` past 1023 frames is a different defect.

Bend 2.0.39 (`a3efe8a3`) removes the 2.0.38 Metal lane spill. The dispatch
patch was rebased onto that commit with the same inserted text. That rebase
has not been re-run on Metal or on the regression binary.

The overlay is general compiler code: it does not recognize Jonlib names, shapes
or fixtures. It modifies `bend2/comp.ts` (which carries a modification notice),
adds the regression `tests/run/metal_inline_budget.bend` (repeated flat-helper
calls across an emitted Metal dispatch boundary) and a `.specs/` ignore entry.
The language parser/checker is untouched. The raytrace, Mandelbrot and
symbolic-regression workloads keep their checksums on CPU and Metal, with no
material slowdown in sampled timings.

## Provenance and license

This is a Jonlib-maintained compiler overlay, not an upstream Bend release or an
upstream-approved change; no upstream issue or PR has been published. The patch
and its modifications are provided under **Apache-2.0**, as is the Bend code they
modify. Copyright 2026 HigherOrderCO for the original Bend work; modifications
authored for Jonathan Peris's Jonlib project. Retain
[LICENSES/bend.txt](../LICENSES/bend.txt) and
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) when distributing it.

## How it is verified

- The verifier never applies or repairs the patch: it requires the declared base
  revision, patch SHA-256, resulting file hashes and no unexpected tracked
  changes (`toolchain.json`).
- Gate `bend-overlay` (`tools/verify_bend.py`) runs a selected subset of
  upstream Bend regressions plus `metal_inline_budget` on CPU and JavaScript;
  `--gpu` adds forced device execution for tests containing `!` calls.
  `stencil3d`, `array_fork` and `array_atomic_fadd` declare `@unsafe`. Bend
  2.0.38's `--check-only` verdict fails a book whose own defs rely on that,
  so the gate compiles those three and compares their printed results.
- Forced-Metal correctness of the Jonlib corpus comes from
  `python3 tools/conformance.py --gpu` and the probes' `--gpu` lane, run locally
  (hosted runners have no GPU; see [CI.md](CI.md)).

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only bend-overlay
```

## Known gaps

- CUDA hardware execution, other GPUs, long-running workloads and the upstream
  cluster/site gates are unverified.
- The underlying Metal optimizer/resource interaction is not root-caused; the
  effective code-generation boundary is established, but no specific Apple
  compiler defect has been proven.
- The overlay should be replaced by a verified upstream revision when one is
  available (upstream review pending authorization).
