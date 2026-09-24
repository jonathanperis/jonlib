# Contributing to Jonlib

Jonlib is working toward raylib parity with library algorithms written in Bend
2. Read the [API](docs/API.md), [compatibility ledger](docs/COMPATIBILITY.md), and
[roadmap](docs/ROADMAP.md) before proposing a change.

## Local setup

Provide Python 3.12+, Bun as pinned in `toolchain.json`, CMake 3.25+, clang 14+,
and clean checkouts of the pinned Bend and raylib revisions. The harness accepts
explicit `--bend-source` and `--raylib-source` paths; it does not install tools.

```sh
python3 tools/check_project.py
python3 -m unittest discover -s tests -v
python3 tools/conformance.py --bend-source /path/to/bend --raylib-source /path/to/raylib
```

Native Metal verification requires a real supported Mac/GPU and a suitable Apple
clang version. `--gpu` forces device execution; it must fail rather than silently
use CPU results. The [complete Metal gate is currently blocked](docs/METAL-INVESTIGATION.md).
For the current inlining investigation, `python3 tools/metal_probe.py --counts 26
--outline-circle` compares an unmodified program with an explicitly experimental
generated-C qualifier change. Its baseline failure still produces a failing exit
status; the experiment is not part of the library or normal conformance gate.

## Changes and evidence

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

- **Checks** validates the test harness, fixtures, source boundary and metadata.
- **Conformance** builds and tests CPU/JavaScript on Ubuntu 24.04 and macOS 15,
  checks the law/contracts/example, and uploads JSON/PPM evidence for 14 days.
- Actions are pinned to immutable commits; dependency revisions come from
  `toolchain.json`. Workflows use read-only repository permissions.
- Hosted conformance does not claim Metal/CUDA or live window/audio validation.

For a bug report, include the smallest reproducer, operating system/architecture,
the lockfile revisions, command, expected result and actual output. Hardware-specific
GPU failures also need the device and compiler version.
