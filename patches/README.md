# Bend compiler overlay

The overlay is two reviewed patches for the exact Bend revision in
`toolchain.json`, applied in the order it declares them:

1. `bend-metal-dispatch.patch` changes **compiler-generated Metal call
   boundaries** (below).
2. `bend-os-effects.patch` adds **path, directory and process effects** to
   Bend's base library (`Path.stat`, `Path.rename`, `Path.remove`,
   `Dir.read`, `Dir.make`, `Dir.change`, `Dir.current`, `Process.path`,
   `Process.run`), each a foreign def with a C and a JavaScript source, as
   Base's `File.*` effects are. It touches no compiler code, applies alone to
   the pinned upstream revision, and is written up as a proposal for Bend in
   [bend-os-effects.md](bend-os-effects.md). Jonlib's file-system functions
   that need the host (`LoadDirectoryFiles`, `GetFileModTime`,
   `ChangeDirectory`, `OpenURL`, ...) are built on it.

The two patches touch different files. Jonlib's library algorithms remain
`.bend` source.

## The Metal dispatch patch

### Why this patch exists

Stock Bend 2.0.27's generated Metal program fails on the full Jonlib corpus.
Large shared native helpers can expand repeatedly into the device dispatcher.
The overlay accounts for inlined callees and source call-site counts, then adds
a noinline Metal call wrapper at an oversized dispatch boundary. Helper-to-helper
INLINE/FAR decisions remain unchanged. CPU/CUDA call names alias the originals.

A broader attempt that globally outlined helper bodies was rejected: it passed
Jonlib but changed the ray-tracer checksum. The adopted dispatcher-boundary
approach passes that workload and the selected upstream regressions.

## Applying and verifying

Start with checkouts at the locked Bend/raylib revisions. From Jonlib's root,
set the absolute paths to your dependency checkouts and apply the overlay once,
its patches in order:

```sh
export BEND_SOURCE="/path/to/bend"
export RAYLIB_SOURCE="/path/to/raylib"
for patch in bend-metal-dispatch bend-os-effects; do
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

The OS effects patch: its two tests and the neighbouring upstream IO tests
(`file_*`, `path_utf8`, `nul_bytes`, `args`, the `effect_*` and `cbody_*`
ones) pass on the check, interpreted, C and JavaScript lanes on Linux; macOS
is still to be run ([bend-os-effects.md](bend-os-effects.md)).

This is a Jonlib-maintained compiler overlay, not an upstream Bend release or
an upstream-approved change. Its tests and source hashes support the recorded
scope; they are not a guarantee for all Bend programs or graphics hardware.

## License

The patch and its modifications are provided under **Apache-2.0**, as is the
Bend code they modify. Copyright 2026 HigherOrderCO for the original Bend work;
modifications authored for Jonathan Peris's Jonlib project in 2026. Retain
[`LICENSES/bend.txt`](../LICENSES/bend.txt) and
[`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) when distributing it.
