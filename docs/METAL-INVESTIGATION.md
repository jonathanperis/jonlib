# Complete Metal conformance gate: unresolved

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

This narrows the problem beyond “arrays do not work on Metal,” but does not
prove a specific Bend compiler/runtime or Metal-driver defect. Program structure,
generated code and runtime behavior need further reduction.

The generated C and smaller diagnostic programs from this investigation are
retained under `.build/`; original tiny reproducer sources are local `.specs/`
artifacts. The complete suite is reproducible from tracked inputs and is the
durable regression. No upstream source, runtime setting or expected output was
changed to conceal the failure, and no issue was published.

## Next investigation steps

1. Reduce the 20-to-24-scenario transition to a self-contained Base-only program,
   comparing actual values rather than only exit status.
2. Compare generated host/device layouts, continuations and allocation handling.
3. Identify the failing compiler/runtime operation before changing either the
   library or runtime. A successful isolated probe is not a fix for this suite.
4. Add the smallest independently meaningful regression at the responsible
   layer, then rerun the complete forced-on GPU gate.

Until resolved, the complete GPU capability remains **blocked**, and the
default CPU/JS profile must be reported separately.
