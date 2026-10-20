# Contributing to Jonlib

Jonlib is working toward raylib parity with library algorithms written in Bend
2. Read the [API](docs/API.md), [compatibility ledger](docs/COMPATIBILITY.md), and
[roadmap](docs/ROADMAP.md) before proposing a change.

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

## Known pitfalls

- **Bend rules that bite.** A `match` must scrutinize a parameter or a
  pattern-bound name, and no `let` may precede a destructuring of a parameter;
  parameters are destructured in declaration order (a matched scalar parameter
  last), and the binders of a two-scrutinee `match` cannot be destructured in
  the case (use a helper def). No mutual recursion; a def must be above its
  callers. Constructors in lets need `{... : T}`; `+` only on Data.
- **`Bool.pick` is strict** and evaluates both branches: a `%` by a count that
  may be 0 traps in the C lanes even in the branch not taken (guard with a
  `match`), and pairs need a `match` helper. A `Bool.pick(Bool, …)` result
  feeding `||` in the same def is miscompiled on the native lanes (repro
  `tests/compiler/bool_pick_or.bend`, diagnostic gate `bend-defects`): choose
  Bools with a def of your own (`either` in `src/wav.bend`).
- **Long inputs on the JavaScript lane.** Base's `List.take` and `List.append`
  are not tail calls: use an accumulator for anything a file sizes. Long list
  literals in a generated program overflow the JavaScript parser's stack near
  2000 elements (pass them in chunks of 64). Heavy example scripts cost
  seconds per frame there (a lane stops after 600 s), and text-heavy scripts
  keep every frame's text in memory: keep them near 250 frames.
- **`jonlib.bend` ends with the generated enumerations** (`tools/enums_probe.py
  --write`): a section appended after them fails the `enums` gate. New
  sections go above that rule.
- **Strings are C byte strings**: write non-ASCII text as UTF-8 bytes
  (`"I\u{c3}\u{b1}igo"`).
- **Memory.** A compile of a program importing `jonlib.bend` peaks near 8 GB:
  one compile at a time on a small machine (exit -9 is the OOM killer).
  `--check-only` type-checks a file in seconds. A running probe compiles from
  the working tree, so do not edit the library or examples it will compile
  until it ends. Apple clang can crash on very large defs: keep defs small and
  probes data-driven.
- **Host-dependent expectations.** Linux uses the glibc profiles and
  uncontracted x86-64; macOS uses Apple libm and fused arm64. Compute every
  probe expectation per host profile and never run anything undefined in C
  natively. `--assume-libm AppleLibm` on the examples and models probes runs
  Jonlib and the refusal oracle under the Apple profile on Linux. An example
  that calls `sinf`/`cosf` itself must refuse where `M.Libm.sin`/`cos` return
  `None`, and its refusal predictor in `tools/examples_probe.py` must name the
  same frame. A target FPS below 60 hangs the native busy-wait under the
  scripted clock. Compilers fold `powf(x, 2)` into `x*x`: check the compiled
  reference before assuming a libm call.
- **Laws close by evaluation**, and F32 primitives do not evaluate in the
  checker: state refused cases, word-level results and decision tables.
- **Check exit statuses**, not piped tails: `check | tail && git commit`
  commits whatever the check said.

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
