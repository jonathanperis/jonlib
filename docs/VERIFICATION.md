# Verification

Jonlib claims raylib parity only where a gate compares Jonlib's output with the
pinned raylib reference and passes. This page states what verification means
here, how to run it, and what it does and does not establish. Per-API contracts
and gaps live in the topic pages and in [`api/progress.json`](../api/progress.json)
(rendered by [PROGRESS.md](PROGRESS.md)); how CI runs the gates is in [CI.md](CI.md).

## What a passing gate means

- **Pinned toolchain.** [`toolchain.json`](../toolchain.json) fixes the raylib 6.0
  and Bend revisions, the Bun version and the hash-checked Bend compiler overlay
  ([patches/README.md](../patches/README.md)). Every harness checks both checkouts
  against it (including the exact overlay file hashes) and fails on any mismatch;
  it never installs, updates or repairs a toolchain.
- **Differential reference.** A C program linked against the pinned raylib built
  with `PLATFORM=Memory` (headless) produces the expected output. Jonlib's Bend
  program produces the candidate. Results are compared exactly: every pixel,
  byte, F32/F64 bit pattern, typed error code and returned owner, unless a page
  names a different, pre-declared contract. Expected values are never edited or
  loosened to make a mismatch pass.
- **Lanes.** Each candidate runs as native CPU with one thread (`cpu-1`), native
  CPU with two threads (`cpu-2`) and emitted JavaScript (`javascript`); all three
  must match. `--gpu` adds a forced device lane (Metal on Apple hardware) that
  must not fall back to CPU. Hosted CI has no GPU, so GPU evidence comes only
  from local forced-GPU runs (see [METAL-INVESTIGATION.md](METAL-INVESTIGATION.md)).
- **Native profiles.** Where the reference result depends on the host C library
  (`atan2f`, `fminf`/`fmaxf` signed zeros), Jonmath exposes explicit profiles and
  the harness selects the host's profile from frozen controls; zero or several
  matching profiles fail. See [ANGLES.md](ANGLES.md) and
  [NATIVE-MATH-PROFILES.md](NATIVE-MATH-PROFILES.md).
- **Negative controls.** Malformed inputs, out-of-domain requests and
  candidate/reference mismatches must be rejected; empty suites, missing outputs
  and mismatched row counts fail the gate.
- **Proofs and laws.** [`LAWS.bend`](../LAWS.bend) states durable structural
  properties (for example, `clear` preserves dimensions and transpose is an
  involution); [`PROOF.bend`](../PROOF.bend) proves them and must report
  `All terms check.` A law covers exactly its statement, not general correctness.
- **Library boundary.** `tools/check_project.py` enforces that library code is
  Bend source without unsafe or custom foreign imports, that the API ledger and
  generated files are current, and that documentation links resolve.

## Gates

[`tools/gates.json`](../tools/gates.json) lists every gate as one command.
[`tools/run_gates.py`](../tools/run_gates.py) runs them, writes
`.build/gates/<id>.json` (outcome, duration, toolchain, host and a hashed summary
of each results file) and fails if any parity gate fails.

| Gate kind | Tools | What it compares |
|---|---|---|
| Main corpus | `tools/conformance.py`, `tests/fixtures/images.json` | Deterministic image/math/collision/codec scenarios, full RGBA pixels and result bits, contracts in `tests/*.bend`, the headless examples, `PROOF.bend`, module check verdicts and the API inventory |
| Focused probes | `tools/*_probe.py` on [`tools/probekit.py`](../tools/probekit.py) | One API family each (codecs, files, exports, float images, compression, checksums, math kernels) against native raylib |
| Shared drivers | `tools/codec_formats.py`, `tools/codec_files.py`, `tools/codec_exports.py`, `tools/binary64_harness.py` | Format-preserving decoding, file loading (with descriptor/size limits), BMP/TGA export and binary64 emulation against rational oracles |
| Probe runtime | [`tools/probekit.py`](../tools/probekit.py), `tools/byte_probe.py` | Pinned-source checks, cached native raylib builds, lanes and batching; the shared byte-result protocol (`C_EMITTER`, `BEND_EMITTER`, `parse_results`) |
| Native profile selection | `tools/native_profiles.py`, `tools/reference_environment.py`, `tools/runtime_image.py` | Host `atan2f`/`fminf`/`fmaxf` profile selection from frozen controls and loaded-runtime provenance ([ANGLES.md](ANGLES.md)) |
| Exact oracles | `tools/binary64_*_oracle.py`, `tools/modern_angle_bounds.py` | Rational-arithmetic expectations for the private binary64 helpers and the modern `atan2f` coefficient bounds |
| Benchmark | `tools/gradient_bench.py` | Serial versus balanced generation timing, checked against raylib first ([GRADIENTS.md](GRADIENTS.md)); not a gate |
| Resampling | `tools/resize_conformance.py` | Default-filter coefficients, kernels and whole-image resize outputs ([RESAMPLING.md](RESAMPLING.md)) |
| API audit | `tools/api_plan.py check` | Pinned header catalog, generated ledger files and progress-record lint ([API-TRACKING.md](API-TRACKING.md)) |
| Compiler overlay | `tools/verify_bend.py` | Selected upstream Bend regressions under the declared overlay |
| Diagnostics | gates marked `"diagnostic": true` | Records for open gaps (host libm behavior, filter precision, perspective rounding, inverse trig); never parity claims |

Probes write their full results under `.build/`; those files are local
artifacts and are not committed. [`docs/evidence/`](evidence/) keeps one compact
record per gate and host from the last full run (`run_gates.py --record`):
outcome, duration, toolchain revisions and a hashed summary of each results
file the gate wrote. Full results are uploaded by CI as artifacts.

## Running verification

Use existing installations and pinned checkouts (see [README.md](../README.md#requirements)):

```sh
python3 tools/check_project.py
python3 -m unittest discover -s tests -v
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --plan
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only conformance
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --shard 1/1
```

Forced-GPU evidence on supported hardware:

```sh
python3 tools/conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/verify_bend.py --bend-source "$BEND_SOURCE" --gpu
python3 tools/<probe>.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Before an implementation commit, also run the proof entry point and check the
complete verdict:

```sh
BEND_NO_TELEMETRY=1 bun "$BEND_SOURCE/bend2/main.ts" PROOF.bend
```

## What is claimed

- For each mapped API, the scope recorded in `api/progress.json` matches the
  pinned raylib reference on the CPU-1/CPU-2/JavaScript lanes of the hosts that
  run the gates (Ubuntu and macOS in CI), with the stated numerical profile.
- Forced-GPU equality only where a local `--gpu` run was made; it is never
  inferred from CPU results.
- Every mapped API remains **partial** until all six completion gates in
  [API-TRACKING.md](API-TRACKING.md) are verified.

## What is not claimed

- Inputs outside a recorded scope, or exhaustive coverage of a scope: gates are
  finite unless a page states an exhaustive domain.
- Desktop windows, input, audio devices, browsers, textures/fonts, 3D, Windows,
  Android, CUDA or any platform not exercised by a gate.
- Performance, latency or long-run resource parity with raylib, except where a
  page states a specific measured scope.
- Reproduction of undefined C behavior, crashes or memory corruption in the
  reference; such domains are rejected with typed errors and listed as gaps.
- Full raylib 6.0 compatibility. The [master plan](MASTER-PLAN.md) defines what
  completion requires.
