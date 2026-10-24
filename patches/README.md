# Bend compiler overlay

The overlay is four reviewed patches for the exact Bend revision in
`toolchain.json`, applied in the order it declares them:

1. `bend-metal-dispatch.patch` changes **compiler-generated Metal call
   boundaries** (below).
2. `bend-os-effects.patch` adds **path, directory and process effects** to
   Bend's base library (`Path.stat`, `Path.rename`, `Path.remove`,
   `Dir.read`, `Dir.make`, `Dir.change`, `Dir.current`, `Process.path`,
   `Process.shell`), each a foreign def with a C and a JavaScript source, as
   Base's `File.*` effects are. It touches no compiler code, applies alone to
   the pinned upstream revision, and is written up as a proposal for Bend in
   [bend-os-effects.md](bend-os-effects.md). Jonlib's file-system functions
   that need the host (`LoadDirectoryFiles`, `GetFileModTime`,
   `ChangeDirectory`, `OpenURL`, ...) are built on it. Bend 2.0.38 already
   ships `Process.run` (a program, arguments, captured output and a timeout);
   that def is left as upstream wrote it. `Process.shell` is the `/bin/sh -c`
   effect `OpenURL` needs.
3. `bend-apple-clang.patch` passes `-fno-stack-check` on the CPU clang
   line when the compiler is Apple clang 21 or newer. That clang's Darwin
   default `-fstack-check` probes the stack with a scratch register that
   `preserve_none` still uses for a later argument, and the backend aborts
   (`live register clobbered by inserted prologue instructions`). The host
   outline and musttail lanes use that calling convention. Linux builds are
   unchanged.
4. `bend-js-constant.patch` shares one JavaScript value for a nullary def
   whose body is a pure constructor literal. The C lane already keeps that
   tree in `STAT_IMG` and copies it once. The JavaScript lane was rebuilding
   it on every call, which made `Apple.at` (the 32,768-leaf exp2 table) take
   milliseconds per call. A body that calls anything, names a binding, or is
   not a constructor literal stays a function. Linux and macOS both emit it.

The Metal and JavaScript-constant patches both edit `bend2/comp.ts`; the
others touch different files. Jonlib's library algorithms remain `.bend`
source.

## The Metal dispatch patch

### Why this patch exists

On Bend 2.0.27, the previous pin, the stock generated Metal program fails on
the full Jonlib corpus. Large shared native helpers can expand repeatedly into
the device dispatcher. The overlay accounts for inlined callees and source
call-site counts, then adds a noinline Metal call wrapper at an oversized
dispatch boundary. Helper-to-helper INLINE/FAR decisions remain unchanged.
CPU/CUDA call names alias the originals.

A broader attempt that globally outlined helper bodies was rejected: it passed
Jonlib but changed the ray-tracer checksum. The adopted dispatcher-boundary
approach passes that workload and the selected upstream regressions on that
2.0.27 compiler.

The pinned compiler is Bend 2.0.38, which rewrote the emitter. A device-far
spin is `DFAR`, and `SPIN_FAR` is 8192 characters, so the patch written for
2.0.27 does not apply. The same policy was re-ported in those units:
helper-to-helper inlining is unchanged, and an oversized call at a non-native
(dispatcher) boundary gets a Metal-only `FAR` wrapper `call_<fid>`. CPU and
CUDA `#define` that name back to the original helper. The regression still
requires both a `DFAR` spin and a `FAR Term call_spin_` wrapper. This boundary
has not been re-run on a Metal device or on the Jonlib corpus; the Metal
result recorded above is the device evidence from the 2.0.27 pin. Upstream's
separate fix for non-tail recursion past 1023 Metal frames is a different
defect and does not replace this patch.

## Applying and verifying

Start with checkouts at the locked Bend/raylib revisions. From Jonlib's root,
set the absolute paths to your dependency checkouts and apply the overlay once,
its patches in order:

```sh
export BEND_SOURCE="/path/to/bend"
export RAYLIB_SOURCE="/path/to/raylib"
for patch in bend-metal-dispatch bend-os-effects bend-apple-clang bend-js-constant; do
  git -C "$BEND_SOURCE" apply --check "$PWD/patches/$patch.patch"
  git -C "$BEND_SOURCE" apply "$PWD/patches/$patch.patch"
done
python3 tools/conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

The verifier does not apply patches, repair files, or update a checkout. It
requires the declared base commit, each patch's SHA-256, the resulting file
hashes (`bend.overlay.files`), and no unexpected tracked changes. CI applies
the same patches explicitly, in order, to a fresh checkout before running
verification. `tools/verify_bend.py` runs a selected set of upstream
regressions and the OS effects' two tests on the CPU and JavaScript lanes. Reapplying an already applied patch is
unnecessary; run verification directly instead.

The Metal patch contains the compiler change, a small runtime regression, and a
`.specs/` ignore entry used by local compiler development. The compiler file
carries a prominent modification notice, as `bend2/base.bend` does for the OS
effects patch. The language parser/checker is untouched.

## Evidence and scope

- Compiler-adoption corpus: 26 scenarios / 6,682 pixels matched on CPU/JS/Metal.
  The expanded image suite is recorded in [VERIFICATION.md](../docs/VERIFICATION.md).
- 16 selected Bend regressions pass; 7 include forced Metal execution.
- CPU/CUDA generated code matches baseline after resolving Metal-only wrappers.
- Raytrace, Mandelbrot and symbolic regression retain their checksums on CPU
  and Metal; warmed process-time medians were within about 1% of baseline on M1.
- CUDA execution and the upstream cluster/site gates were not run. The local
  repository token-cap gate also requires the unavailable `ttok` tool.

The OS effects patch, rebased onto 2.0.38: its two tests pass on the check,
the C binary and the JavaScript lane on Linux x86_64 with Bun 1.3.12. The
neighbouring upstream IO suite and macOS were not re-run for this rebase
([bend-os-effects.md](bend-os-effects.md)).

This is a Jonlib-maintained compiler overlay, not an upstream Bend release or
an upstream-approved change. Its tests and source hashes support the recorded
scope; they are not a guarantee for all Bend programs or graphics hardware.

## License

The patch and its modifications are provided under **Apache-2.0**, as is the
Bend code they modify. Copyright 2026 HigherOrderCO for the original Bend work;
modifications authored for Jonathan Peris's Jonlib project in 2026. Retain
[`LICENSES/bend.txt`](../LICENSES/bend.txt) and
[`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) when distributing it.
