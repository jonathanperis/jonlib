# Bend compiler overlay

`bend-metal-dispatch.patch` is a reviewed, explicit compiler overlay for the exact
Bend revision in `toolchain.json`. It changes **compiler-generated Metal call
boundaries**; Jonlib's library algorithms remain `.bend` source.

## Why this patch exists

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
set the absolute paths to your dependency checkouts and apply the overlay once:

```sh
export BEND_SOURCE="/path/to/bend"
export RAYLIB_SOURCE="/path/to/raylib"
git -C "$BEND_SOURCE" apply --check "$PWD/patches/bend-metal-dispatch.patch"
git -C "$BEND_SOURCE" apply "$PWD/patches/bend-metal-dispatch.patch"
python3 tools/conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

The verifier does not apply patches, repair files, or update a checkout. It
requires the declared base commit, patch SHA-256, resulting file hashes, and no
unexpected tracked changes. CI applies the same patch explicitly to a fresh
checkout before running verification. Reapplying an already applied patch is
unnecessary; run verification directly instead.

The overlay contains the compiler change, a small runtime regression, and a
`.specs/` ignore entry used by local compiler development. The compiler file
carries a prominent modification notice. The language parser/checker is untouched.

## Evidence and scope

- Compiler-adoption corpus: 26 scenarios / 6,682 pixels matched on CPU/JS/Metal.
  The expanded image suite is recorded in [VERIFICATION.md](../docs/VERIFICATION.md).
- 16 selected Bend regressions pass; 7 include forced Metal execution.
- CPU/CUDA generated code matches baseline after resolving Metal-only wrappers.
- Raytrace, Mandelbrot and symbolic regression retain their checksums on CPU
  and Metal; warmed process-time medians were within about 1% of baseline on M1.
- CUDA execution and the upstream cluster/site gates were not run. The local
  repository token-cap gate also requires the unavailable `ttok` tool.

This is a Jonlib-maintained compiler overlay, not an upstream Bend release or
an upstream-approved change. Its tests and source hashes support the recorded
scope; they are not a guarantee for all Bend programs or graphics hardware.

## License

The patch and its modifications are provided under **Apache-2.0**, as is the
Bend code they modify. Copyright 2026 HigherOrderCO for the original Bend work;
modifications authored for Jonathan Peris's Jonlib project in 2026. Retain
[`LICENSES/bend.txt`](../LICENSES/bend.txt) and
[`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) when distributing it.
