# Contributing to Jonlib

Jonlib is working toward raylib parity with library algorithms written in Bend
2. Read the [API](docs/API.md), [compatibility ledger](docs/COMPATIBILITY.md), and
[master plan](docs/MASTER-PLAN.md) before proposing a change.

## Local setup

Provide Python 3.12+, Bun as pinned in `toolchain.json`, CMake 3.25+, clang 14+,
and checkouts of the pinned Bend and raylib revisions. Apply the exact
[Bend compiler overlay](patches/README.md); keep raylib unmodified. The harness
accepts explicit `--bend-source` and `--raylib-source` paths; it does not install
tools or repair source files.

Set `BEND_SOURCE` and `RAYLIB_SOURCE` to your checkout locations as shown in the
[README setup instructions](README.md#requirements), then run:

```sh
python3 tools/check_project.py
python3 -m unittest discover -s tests -v
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only conformance
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --shard 1/1
```

Use `--only GATE_ID` (repeatable) for the gates in `tools/gates.json` that your
change affects; [VERIFICATION.md](docs/VERIFICATION.md) explains what each kind of
gate establishes.

Native Metal verification requires a real supported Mac/GPU and a suitable Apple
clang version. `--gpu` forces device execution; it must fail rather than silently
use CPU results. Run both `tools/conformance.py --gpu` and `tools/verify_bend.py --gpu` for changes
affecting the device path. See [the investigation](docs/METAL-INVESTIGATION.md)
for the historical failure, rejected candidates and remaining verification limits.

## Changes and evidence

Follow the [official Bend workflow](https://bend-lang.com/#get) using the pinned
toolchain: consult its `guide`, keep important invariants in `LAWS.bend`, and run
the real proof entry point before an implementation commit:

```sh
BEND_NO_TELEMETRY=1 bun "$BEND_SOURCE/bend2/main.ts" guide
BEND_NO_TELEMETRY=1 bun "$BEND_SOURCE/bend2/main.ts" PROOF.bend
```

Check the complete proof verdict. Prefer balanced, ownership-safe parallel work
where measurements support it; retain reference arithmetic order. Proofs establish
the stated laws, while conformance and runtime tests establish their exercised scope.

Select stable API IDs from the [progress dashboard](docs/PROGRESS.md). Update
`api/progress.json` with scope, gaps and evidence, then run
`python3 tools/api_plan.py build`. Generated ledgers/checklists must not be
edited directly. Use [the tracking procedure](docs/API-TRACKING.md) for gate
requirements and `report --since BASE_COMMIT` for a delivery's actual delta.

- Add the smallest fixture or contract check that demonstrates the behavior.
- Compare identical inputs with pinned raylib; preserve full-pixel assertions.
- Do not update expectations or loosen tolerances to conceal differences.
- Keep library algorithms in `.bend`; C belongs to the independent reference.
- Keep source revisions and successful execution evidence aligned.
- Retain notices for adapted code and document behavior differences.
- Include the relevant commands/results and unverified targets in a pull request.

An upstream raylib issue reproduction or example is useful input, but may require
a deterministic clock, input sequence, assets and bounded frame count before it
becomes a conformance test. Consult asset-specific licenses before adding files.

## GitHub Actions

- **Checks** (Ubuntu and macOS) runs the Python unit tests, byte-compiles the
  tools and runs `tools/check_project.py`: source boundary, fixtures, API ledger
  and progress-record lint, generated files and documentation links.
- **Conformance** runs every gate in `tools/gates.json` on Ubuntu and macOS in
  duration-balanced shards with the pinned toolchain and hash-checked compiler
  overlay; the aggregate `CPU and JavaScript` checks require every shard.
  Diagnostic gates record open gaps and are never treated as passing
  implementations. See [CI](docs/CI.md) for details and local equivalents.
- Actions are pinned to immutable commits; dependency revisions come from
  `toolchain.json`. Workflows use read-only repository permissions.
- Hosted conformance does not claim Metal/CUDA or live window/audio validation.

For a bug report, include the smallest reproducer, operating system/architecture,
the lockfile revisions, command, expected result and actual output. Hardware-specific
GPU failures also need the device and compiler version.
