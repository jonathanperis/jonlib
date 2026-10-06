# Continuous integration

Two workflows run on pushes to `main` and `feature/**` and on pull requests.

**Checks** (Ubuntu and macOS) runs the Python unit tests, byte-compiles the
tools and runs `tools/check_project.py` (library source boundary, fixtures,
API ledger and documentation links).

**Conformance** runs every gate in [`tools/gates.json`](../tools/gates.json) on
`ubuntu-24.04` and `macos-15`. `tools/run_gates.py` splits the manifest into
six duration-balanced shards per host; the two aggregate jobs (`CPU and
JavaScript (ubuntu-24.04)` / `(macos-15)`) pass only when every shard passed.
Documentation-only changes skip this workflow. The pinned Bend checkout, its
declared overlay and the pinned raylib checkout come from `toolchain.json`
through `.github/actions/setup-pinned`.

Each gate is one command. Parity gates must pass on both hosts; entries marked
`diagnostic` record evidence for open gaps (for example libm rounding) and are
never parity claims. Every run uploads `.build/gates/<id>.json` (outcome,
duration, toolchain, host and a hashed summary of each results file) plus the
full probe results as artifacts kept for 30 days.

Run the same gates locally:

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --plan
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only bmp-format
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --shard 1/1
```

Hosted runners have no GPU; forced-Metal evidence (`--gpu` on the probes and
`tools/metal_probe.py`) comes from local runs on Apple hardware.
