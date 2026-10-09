# Continuous integration

Two workflows run on pushes to `main` and `feature/**` and on pull requests.

**Checks** (Ubuntu and macOS) runs the Python unit tests, byte-compiles the
tools and runs `tools/check_project.py` (library source boundary, fixtures,
API ledger and documentation links).

**Conformance** runs every gate in [`tools/gates.json`](../tools/gates.json) on
`ubuntu-24.04` and `macos-15`. `tools/run_gates.py` splits the manifest into
eight duration-balanced shards per host. Hosted macOS allows five concurrent
jobs, so three macOS shards wait for a free runner; five shards no longer fit
the 210-minute limit per shard once the Phase 2-5 gates landed. The `minutes`
estimates in `gates.json` are the observed macOS durations (the slower host;
gates not yet measured there use 2.7 times their Linux time), which keeps
shards near 140 minutes. The two aggregate jobs (`CPU and
JavaScript (ubuntu-24.04)` / `(macos-15)`) pass only when every shard passed.
Documentation-only changes skip this workflow. The pinned Bend checkout, its
declared overlay and the pinned raylib checkout come from `toolchain.json`
through `.github/actions/setup-pinned`.

Each gate is one command. Parity gates must pass on both hosts; entries marked
`diagnostic` record evidence for open gaps (for example libm rounding) and are
never parity claims. Every run uploads `.build/gates/<id>.json` (outcome,
duration, toolchain, host and a hashed summary of each results file) plus the
full probe results as artifacts kept for 30 days. The compact records of a
full local run (`--record docs/evidence`) are committed in
[`docs/evidence/`](evidence/); the full dumps are not.

Probes compile and run independent batches concurrently, bounded by CPUs (at
most four) and by 9 GB of memory per batch (physical memory, or a lower cgroup v2
limit): compiling a candidate that imports `jonlib.bend` peaks near 8 GB in the
Bend compiler (measured October 2026; two concurrent compiles exhausted a Linux
runner). Hosted Linux and macOS runners therefore run one batch at a time.
`--jobs N` (or `PROBEKIT_JOBS`) overrides.

Run the same gates locally:

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --plan
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only bmp-format
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --shard 1/1
```

Hosted runners have no GPU; forced-Metal evidence (`--gpu` on the probes and
`tools/metal_probe.py`) comes from local runs on Apple hardware.
