# Continuous integration

Two workflows run on pushes to `main` and `feature/**` and on pull requests.

**Checks** (Ubuntu and macOS) runs the Python unit tests, byte-compiles the
tools and runs `tools/check_project.py` (library source boundary, fixtures,
API ledger and documentation links).

**Conformance** starts with a `Scope` job: [`tools/ci_scope.py`](../tools/ci_scope.py)
compares the push with its base (the previous head of `main`, or the merge
base with `main` for a branch or a pull request) and picks one of three scopes.

| Scope | Changed files | What runs |
| --- | --- | --- |
| `full` | the library, `src/`, `LAWS.bend`/`PROOF.bend`, `toolchain.json`, a probe or another tool a gate runs, fixtures, API ledgers, the pinned setup action, the examples probe from its native driver (`C_DRIVER`) down, an example without a replay, any path the tool does not know | every gate, both hosts |
| `examples` | only `examples/<name>.bend` ports, the tables and scripts of `tools/examples_probe.py`, `api/examples.json` and documentation | `Changed examples`: the changed ports, the examples the probe's changed lines name and three canaries (`core_basic_window`, `core_2d_camera`, `textures_logo_raylib`), replayed against the native examples on both hosts |
| `none` | only workflows, unit tests, `tools/ci_scope.py`, `tools/check_project.py`, `tools/examples_plan.py`, `tools/example_tables.py` and documentation | nothing here (Checks covers them) |

Scheduled (nightly, on `main`) and manual runs are always `full`, and so is a
run whose base cannot be found. Two runs are skipped as redundant: a push to
`main` of a commit whose run already succeeded on its branch (a fast-forward
merge, the same tree against an ancestor of the same base), and a nightly run
of a commit that a scheduled or manual run already passed. An `examples` run
is weaker evidence than the full matrix: it shows the changed examples still
equal raylib, and relies on the classification above for everything else. The
nightly run is the complete check of what reached `main` that way, and has its
own concurrency group so that pushes do not cancel it.

A `full` run executes every gate in [`tools/gates.json`](../tools/gates.json) on
`ubuntu-24.04` and `macos-15`. `tools/run_gates.py` splits the manifest into
ten duration-balanced shards per host. Hosted macOS allows five concurrent
jobs, so five macOS shards wait for a free runner; eight shards approached
the 210-minute limit per shard once the examples gates (`examples-core`,
`-models`, `-shaders`, `-shapes`, `-text`, `-textures`) and one compile batch at a time landed. The
`minutes` estimates in `gates.json` are the observed macOS durations (the
slower host; gates not yet measured there use 2.7 times their Linux time),
which keeps shards near 135 minutes. The two aggregate jobs (`CPU and
JavaScript (ubuntu-24.04)` / `(macos-15)`) pass only when everything the scope
asked for passed (every shard, or the changed examples on both hosts).
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
runner). Hosted Linux and macOS runners therefore run one batch at a time, and
each candidate's native binary and JavaScript are compiled by separate compiler
processes (`probekit.compile_outputs`): one process emitting both peaked near
8.5 GB with the C compiler, against 6.5 and 4 GB separately.
`--jobs N` (or `PROBEKIT_JOBS`) overrides.

Run the same gates locally (`python3 tools/ci_scope.py --base origin/main`
prints the scope of the current branch):

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --plan
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only bmp-format
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --shard 1/1
```

Hosted runners have no GPU; forced-Metal evidence (`--gpu` on the probes and
`tools/metal_probe.py`) comes from local runs on Apple hardware.
