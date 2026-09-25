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
python3 tools/conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 tools/verify_bend.py --bend-source "$BEND_SOURCE"
python3 tools/resize_conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

Native Metal verification requires a real supported Mac/GPU and a suitable Apple
clang version. `--gpu` forces device execution; it must fail rather than silently
use CPU results. The complete Metal gate passes on the tested M1 with the overlay.
Run both `tools/conformance.py --gpu` and `tools/verify_bend.py --gpu` for changes
affecting the device path. See [the investigation](docs/METAL-INVESTIGATION.md)
for the historical failure, rejected candidates and remaining verification limits.

## Changes and evidence

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

- **Checks** validates the test harness, fixtures, source boundary, metadata and
  generated API progression files/dependencies/completion claims.
- **Conformance** builds and tests CPU/JavaScript on Ubuntu 24.04 and macOS 15,
  explicitly applies the hash-checked compiler patch, checks the law/contracts/
  examples and 16 upstream compiler regressions, records the default-filter
  precision diagnostic, and uploads evidence for 14 days. Diagnostic variants
  are not treated as passing Bend implementations. Both jobs re-extract the
  complete API catalog and independently audit C functions/C++ overloads with Clang.
  The filtered-resize gate also checks exact normalization/kernel bits and
  529 real raylib image outputs, including the retained precision counterexamples.
  The main corpus also checks QOI export bytes, codec failures, real byte-file IO
  and exact scalar/Vector2 results under the declared uncontracted-F32 profile.
- Actions are pinned to immutable commits; dependency revisions come from
  `toolchain.json`. Workflows use read-only repository permissions.
- Hosted conformance does not claim Metal/CUDA or live window/audio validation.

For a bug report, include the smallest reproducer, operating system/architecture,
the lockfile revisions, command, expected result and actual output. Hardware-specific
GPU failures also need the device and compiler version.
