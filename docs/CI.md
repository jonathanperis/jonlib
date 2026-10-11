# Continuous integration

Two workflows run on pushes to `main` and `feature/**` and on pull requests.

## macOS is off the merge path for now

Since 2026-10-10, **pushes and pull requests run on Linux only**; the nightly
and the manual (`workflow_dispatch`) runs of both workflows still use every
host. Hosted macOS runs five jobs at a time across the whole account, and a
complete Conformance run needs about twenty runner-hours there: every merge
waited hours for it while the Linux half had long finished. Jonathan's
decision: finish the port first, then turn macOS back on and validate
everything that was merged against it.

What this means until then:

- A green run on a branch says the change is right on Linux (glibc profiles,
  uncontracted x86-64). It says nothing about the Apple profile or fused
  arm64. Before pushing, `--assume-libm AppleLibm` on the examples and models
  probes still runs Jonlib and the refusal oracle under the Apple profile on
  Linux.
- The nightly complete run on `main` (06:17 UTC) is where macOS is checked.
  A red macOS job there is a debt to record and fix, not a blocked merge.
- To turn macOS back on: add `('macos', 'macos-15')` to `MERGE_HOSTS` in
  [`tools/ci_scope.py`](../tools/ci_scope.py) and drop the event test from the
  `os:` line of `.github/workflows/checks.yml`. Then run both workflows
  manually on `main` and fix what they find before calling the port done.

**Checks** (Ubuntu; macOS in nightly and manual runs) runs the Python unit tests, byte-compiles the
tools and runs `tools/check_project.py` (library source boundary, fixtures,
API ledger and documentation links).

**Conformance** starts with a `Scope` job: [`tools/ci_scope.py`](../tools/ci_scope.py)
compares the push with its base (the previous head of `main`, or the merge
base with `main` for a branch or a pull request) and picks one of three scopes.

| Scope | Changed files | What runs |
| --- | --- | --- |
| `full` | a library definition that changed or was removed, `toolchain.json`, `tools/run_gates.py`, the pinned setup action, fixtures, a tool no gate reaches, any path the tool cannot place, or more gates than six jobs per host hold | every gate, in fifteen shards per host |
| `scoped` | see below | `Scoped <host> gates N` / `examples`: only the affected gates and examples |
| `none` | only workflows, unit tests, `tools/ci_scope.py`, `tools/check_project.py`, `tools/examples_plan.py`, `tools/example_tables.py` and documentation | nothing here (Checks covers them) |

What a `scoped` run selects, per changed file:

| Changed file | Gates and examples |
| --- | --- |
| `jonlib.bend`, `jonmath.bend`, `jongui.bend`, `src/*.bend`, when the file only gained whole top-level definitions (every existing definition byte for byte where it was) | `conformance` (the main corpus with `PROOF.bend`) and `examples-core` |
| `LAWS.bend`, `PROOF.bend` | the gates whose tool names them (`conformance`) |
| `api/*.json` ledgers | the gates that run `tools/api_plan.py` (`api-audit`, `conformance`) |
| a tool under `tools/` | the gates that reach it: the tool a gate runs, the tools that tool's source names, and what those import, transitively |
| `tools/gates.json` | the gates whose command or hosts changed (new gates included) |
| `tools/reference/**` | every gate that can reach a tool naming that entry of `tools/reference/` |
| `examples/<name>.bend`, and the tables and scripts of `tools/examples_probe.py` above its native driver | the changed ports, the examples whose registration, table entry, prediction or script changed (a script line belongs to the script it continues) and three canaries (`core_basic_window`, `core_2d_camera`, `textures_logo_raylib`), replayed against the native examples |
| code the examples share in their probe (its native driver `C_DRIVER` and everything below, or a line above it that names no example and is not a new constant or a comment) | every `examples-*` gate |

The affected gates are packed into jobs of about 50 estimated minutes, so the
corpus and the core examples of an additive library change run side by side
(a gate of at most 5 minutes that fits in no job joins the lightest one); past
six jobs per host the run is `full`. `python3 tools/ci_scope.py --base
origin/main` prints the scope of the current branch and, for a `full` one, the
reason.

Scheduled (nightly, on `main`) and manual runs are always `full`, and so is a
run whose base cannot be found. A push to `main` is compared with the nearest
commit whose run already passed: a fast-forward merge of a passing branch
pushes that same commit, so nothing is left to run, and a merge commit is
compared with the merged branch's head, so only what `main` had gained since
the branch started is checked against the merged tree. A nightly run of a
commit that a scheduled or manual run already passed is skipped. A `scoped`
run is weaker evidence than the full matrix: it shows that what the change
touches still equals raylib and that the proofs still check, and relies on the
classification above for everything else (a new definition cannot alter an
existing one; Bend rejects a duplicate name). The nightly run is the complete
check of what reached `main` that way. A push to a branch cancels that
branch's run; each push to `main` and the nightly run keep their own.

A `full` run executes every gate in [`tools/gates.json`](../tools/gates.json) on
each host of the run (`ubuntu-24.04`; also `macos-15` in nightly and manual
runs). `tools/run_gates.py` splits the manifest into fifteen
duration-balanced shards per host: on Linux they all start at once and a
complete run takes about an hour and a half, leaving runners for the scoped
runs of other branches. On macOS, five at a time, the fifteen take several
hours, which is why macOS is nightly for now. The `minutes` estimates in
`gates.json` are the observed macOS durations (the slower host; gates not yet
measured there use 2.7 times their Linux time). The aggregate job `CPU and
JavaScript (ubuntu-24.04)` passes only when everything the scope asked for
passed (every shard on every host of the run, or every scoped job);
`CPU and JavaScript (macos-15)` exists in the runs that include macOS.
The workflow has no path filter (GitHub evaluates one on the commits a push
adds to the repository, so a branch created at a commit another ref already
holds would start no run): a documentation-only change is a `none` scope,
answered in seconds. The pinned Bend checkout, its
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

Run the same gates locally:

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --plan
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only bmp-format
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --shard 1/1
```

Hosted runners have no GPU; forced-Metal evidence (`--gpu` on the probes and
`tools/metal_probe.py`) comes from local runs on Apple hardware.
