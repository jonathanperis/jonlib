# Complete Metal gate: inlining-sensitive failure

Observed 2026-09-24 on Apple M1, macOS 27.0, Bun 1.3.12, Apple clang 21.0.0,
with the source revisions in `toolchain.json`.

## Reproduction

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

## Fresh outlining experiment

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
has not been adopted as a general runtime fix or production workaround.

Reproduce both the baseline and experiment after the default conformance run:

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
Neither Jonlib nor the upstream Bend checkout was modified by the experiment.
The regular GPU gate remains unmodified and failing. No upstream issue was published.

## Next investigation steps

1. Produce a smaller Base-only reproduction preserving the inlining sensitivity.
2. Inspect transitive helper inlining and device resource/code-generation limits.
3. Evaluate a principled compiler outlining change with Bend's own runtime tests
   and performance workloads, rather than globally changing a threshold based
   on this one program.
4. Add the smallest independently meaningful regression at the responsible layer,
   then rerun the unmodified-source full GPU gate with the approved toolchain fix.

Until resolved, the complete GPU capability remains **blocked**, and the
default CPU/JS profile must be reported separately.
