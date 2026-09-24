# Metal dispatch failure: resolved with the declared compiler overlay

## Current result

Jonlib's normal `python3 tools/conformance.py --gpu` now passes all **26
scenarios / 6,682 RGBA pixels** with the compiler overlay in `toolchain.json`.
The library source, fixtures and expected results were not changed to obtain
this result. CPU and JavaScript still pass.

The compiler change budgets transitive helper expansion and repeated source
call sites at the **device dispatcher boundary**. Oversized calls receive a
Metal-only noinline wrapper. Helper-to-helper INLINE/FAR choices remain as in
upstream, and CPU/CUDA wrapper names alias the original functions. Wrapper
liveness follows the compiler's existing reference graph.

The overlay is general compiler code: it does not recognize Jonlib names, shapes
or fixtures. It is a Jonlib-maintained patch, not an upstream-approved release.
See [application/provenance instructions](../patches/README.md).

### Validation and a rejected candidate

- All 16 selected Bend regressions pass on CPU/JS; 7 also pass forced Metal.
- The new small regression exercises repeated flat-helper calls and an emitted
  Metal dispatch boundary. Existing cases cover arrays, native-helper cache
  liveness, borrowing, flat results, and fork/leaf execution.
- Generated CPU/CUDA source is identical to baseline after resolving the new
  conditional wrappers; CUDA hardware execution was not performed.
- A first transitive-only budget did not fix Jonlib.
- A broader policy outlining helper bodies globally fixed Jonlib but changed
  the Metal ray-tracer checksum from `31932226` to `0`. It was rejected. Each
  new outline alone preserved the checksum; the combination did not.
- The adopted dispatcher-only boundaries preserve raytrace, Mandelbrot and
  symbolic-regression checksums on CPU and Metal.

Warmed process-time medians from three interleaved baseline/candidate samples
on the local M1 (seconds, including startup and driver overhead):

| Workload | Lane | Baseline | Candidate | Candidate/baseline |
|---|---|---:|---:|---:|
| Raytrace: 512 rows, width 800 | CPU, one thread | 0.178550 | 0.178004 | 0.997 |
| Raytrace | Metal | 0.206199 | 0.207496 | 1.006 |
| Mandelbrot: histogram depth 14, 51 iterations | CPU, one thread | 0.418081 | 0.417270 | 0.998 |
| Mandelbrot | Metal | 0.135313 | 0.136393 | 1.008 |
| Symreg: population depth 12, 64 points, 32 rounds | CPU, one thread | 0.056362 | 0.056152 | 0.996 |
| Symreg | Metal | 0.523224 | 0.519888 | 0.994 |

These results show no material slowdown in the sampled workloads; differences
this small are not a general speedup claim. The upstream cluster/site gates,
CUDA hardware, other GPUs and long-running workloads remain unverified. The
local repository token-cap gate requires the unavailable `ttok` tool.

## Historical stock-compiler investigation

Observed 2026-09-24 on Apple M1, macOS 27.0, Bun 1.3.12, Apple clang 21.0.0,
using the original unmodified Bend `ac0ddb7bf9b3255b23126886698b43a176eed8ca`.

### Original reproduction

```sh
python3 tools/conformance.py --gpu
```

The generated `.build/candidate-gpu` uses the same 26 scenarios as the CPU/JS
runners and marks every draw entry with `!`. CPU/JS comparisons pass. Running
the complete GPU binary with `--gpu on` fails before a valid first JSON row:

```text
bend: memory fault (machine stack overflow?)
```

The same GPU-capable binary with `--gpu off` exits successfully. A 24-scenario
prefix also failed with `bend: frontier drained without a result`. Observed
diagnostics differ; a root cause has not been established.

## Reduction evidence

- Standalone Base.Array set/get across a `!` call: CPU and Metal return 42.
- A 4×4 Jonlib surface rectangle update across `!`: CPU and Metal return 42.
- The full 64×64 radius-12 scenario by itself: CPU and Metal emit matching output.
- Prefixes of 2, 4, 8 and 16 scenarios exited successfully on Metal.
- The 20-scenario prefix matched every reference pixel on Metal.
- Prefixes of 24 and 26 failed on Metal.
- Twenty-six 1×1 empty scenarios passed on Metal.
- Forty independent scalar `!` calls passed on Metal.
- Metal API/shader validation enabled still terminated unsuccessfully and did
  not identify a useful shader fault in the captured output.

### Fresh outlining experiment before the compiler fix

A generated-C diagnostic localized a failing 24-scenario run to the circle path:
the rectangle completed, the call through the generated circle helpers did not
complete successfully, and the runtime's error field remained zero. This is
diagnostic evidence, not a source-level proof of the root cause.

The follow-up used **fresh, uninstrumented compiler output** for all 26 scenarios
and changed exactly one function qualifier: the generated flat circle loop
(`Surface.circle.loop`, `spin_27` in this output) from `INLINE` to `FAR`. The
pinned compiler defines `FAR` as `static __attribute__((noinline))`.

| Generated program | GPU off | GPU forced on |
|---|---|---|
| Unmodified | Every pixel matches | Fails, exit 1 |
| Only circle-loop qualifier changed to FAR | Every pixel matches | Every pixel matches |

All **26 scenarios / 6,682 pixels** matched in the outlined GPU experiment.
The reference inputs, expected outputs and image algorithms were identical.
The Bend compiler currently chooses INLINE/FAR using each helper's emitted line
count (`SPIN_FAR = 256`); this loop falls below the threshold despite calling
other helpers. Investigating generated code growth, inlining and device resource
usage is now the focused next step.

This establishes an **inlining-sensitive failure** on the tested toolchain. It
does not yet distinguish a Metal compiler defect, resource-limit interaction or
another bug exposed by the generated program. The one-line diagnostic change
was not adopted as a general runtime fix or production workaround.

The diagnostic command compares normal emitted output with an explicitly
experimental qualifier change for the currently declared compiler:

```sh
python3 tools/conformance.py
python3 tools/metal_probe.py --counts 26 --outline-circle
```

The diagnostic intentionally exits nonzero when the unmodified baseline fails,
even if the outlined variant passes. It writes `.build/metal-probe.json`, fresh
generated programs and separate stdout/stderr files. Without `--outline-circle`,
the tool only tests unmodified prefixes; its default counts are 20, 24 and 26.

The generated C and smaller diagnostic programs are retained under `.build/`;
original tiny reproducer sources are local `.specs/` artifacts. The complete
suite and outlining experiment are reproducible from tracked tools/inputs.
Neither Jonlib nor the upstream Bend checkout was modified by that experiment.
Subsequent compiler work produced the overlay described above. The normal GPU
gate now passes with that overlay. No upstream issue or PR has been published.

## Remaining work

1. Broaden hardware and workload evidence, including CUDA and upstream cluster gates.
2. Investigate the underlying Metal optimizer/resource interaction more deeply;
   the effective code-generation boundary is established, but no specific Apple
   compiler defect has been proven.
3. Pursue upstream review when authorized and replace the overlay with a verified
   upstream revision when available.
