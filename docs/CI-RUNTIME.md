# Conformance runtime and gate preservation

The runtime split reviewed on 2026-10-02 preserves the workflow at checkpoint
`36f5d0b5a811297b349c45aa6ddc3a9a067ac8d3`. It changes scheduling and artifact
package names only; no library, probe, numeric fixture, tolerance, compiler,
qualification, loader policy or resource ceiling changes are involved in that split.
The later reviewed TGA-memory and TGA-file additions are described separately below.

## Worker ownership

Each of Ubuntu 24.04 and macOS 15 runs two independent workers:

- **Core CPU and JavaScript:** the other 72 verification/diagnostic steps in
  their original order, including canonical conformance and all angle checks.
- **Formatted images CPU and JavaScript:** these seven original steps, in order:
  formatted BMP export, formatted TGA export, formatted QOI export, QOI memory,
  PNM memory, PNM files, and QOI files. A new mandatory format-preserving
  TGA-memory gate follows those seven original gates on both platforms, then a
  mandatory format-preserving TGA-file gate follows the memory gate.

All 79 original gate step payloads still occur once per OS, byte-exact. The new
TGA-memory and TGA-file gates bring each OS to 81 gates: 72 core and nine
formatted. Original Linux-only conditions, profile guards, legacy historical
assertions and clean-loader flags
remain exact. Each worker independently repeats all seven original setup steps:
pinned repository/Python/Bun actions, dependency pin extraction, fresh exact Bend
and raylib checkouts, and hash-checked compiler overlay application. Environments,
120-minute timeouts are unchanged. Four explicit jobs (`coreUbuntu`, `coreMac`,
`formattedUbuntu`, `formattedMac`) replace the matrices, so one worker failure
does not cancel another worker. No cache or result receipt replaces execution.
Probes remain sequential within each workspace.

The core retains the R32 native archive producers before angle qualification.
The formatted worker's first BMP/TGA gates configure their own raylib build;
subsequent QOI/PNM/TGA-memory/TGA-file gates make their own native builds.
Canonical conformance continues to build and qualify its own reference. No build or qualification
receipt crosses worker machines.

## Required checks and artifacts

The old visible names, `CPU and JavaScript (ubuntu-24.04)` and
`CPU and JavaScript (macos-15)`, remain. Each is an `always()` aggregate requiring
success directly from **all four explicit worker IDs**. Neither aggregate uses
a matrix-family result, including on partial reruns.
The shell exits nonzero for failure, cancellation, skipped, empty, unknown or
missing dependency results. This is deliberately stricter than prior per-OS
independence: a failure on either platform fails both compatibility aggregates.
Their small validation shell runs on Ubuntu; the label identifies the preserved
check name, not where parity probes execute. Worker names identify the actual
platform and shard. There are no branch-protection or permission changes.

Artifact names are `conformance-<os>-core` and
`conformance-<os>-formatted`. The original 156 path patterns remain partitioned
into 140 core and 16 formatted patterns, with no omissions or duplicates. The
reviewed `.build/tga-format-probe/` and `.build/tga-file-probe/` additions are
appended to formatted artifacts in that order. Four exact exclusions follow
the TGA-file directory: `run-*/fixtures/cap-plus-one.tga`,
`run-*/fixtures/cap-plus-one.qoi`, `run-*/fixtures/larger-file.tga` and
`run-*/fixtures/host-size-overflow.tga`, each under `.build/tga-file-probe/`.
This gives 22 formatted and 162 total upload patterns per OS, including those
four exclusions. The ordinary 1 MiB `exact-cap.tga`, fixture recipes in
`inputs.json`, command receipts and resource receipts remain included. The
memory-only probe creates no sparse fixture files.
The pinned upload action, `always()`, 14-day retention, hidden-file inclusion
and missing-file warning settings are unchanged. PNM-file artifacts still
contain only results, command and resource JSON; QOI-file uploads keep their
existing scoped patterns. Huge/sparse fixtures are not uploaded. Consumers
must use the new shard-suffixed package names; no artifact merge action or
overwrite option is introduced.

## Runtime evidence and limits

The [prior successful hosted run](https://github.com/jonathanperis/jonlib/actions/runs/37056839140)
at `c88cc890001afbacbb409abeeae4e4a274bc0eb9` took 105m12s on Ubuntu and 85m45s
on macOS. Its five pre-existing formatted gates took 23m51s and 19m23s,
respectively. Sealed local Linux receipts for the new PNM memory/file gates
sum to 18m27.074s–18m53.792s; these are not hosted or macOS measurements.

Additive **planning estimates**, not observed split-run results:

| Platform | Unsplit total with both PNM gates | Split core | Split formatted |
| --- | --- | --- | --- |
| Ubuntu | 123m39s–124m06s | 81m21s | 42m18s–42m45s |
| macOS | 104m12s–104m39s | 66m22s | 37m50s–38m17s |

Formatted estimates exclude their additional setup/upload overhead. The old
setup took approximately 12–16s and upload 25–30s, but future hosted timings
must establish the actual margin. Worker timeouts stay at 120 minutes.
Neither estimates nor local structural tests establish a new hosted pass. The
estimates above predate both TGA additions and exclude their full native
builds, qualification and CPU-1/CPU-2/JavaScript comparisons, including the
TGA-memory probe's 43 source-bounded partitions. Observed 80-gate memory-checkpoint
runtimes are recorded below. The TGA-file addition's runtime and final combined
81-gate hosted result remain unverified; the 120-minute worker budgets are unchanged.

The later unsplit PNM-memory checkpoint `d3b93896` completed hosted Conformance
successfully in 111m05s on Ubuntu and 99m13s on macOS. Ubuntu had only 8m55s
of its 120-minute budget remaining. That run did not include the PNM-file gate
or this split, so it establishes neither their hosted runtime nor their parity.

## Observed hosted PNM/split checkpoint

The [verified 79-gate hosted run](https://github.com/jonathanperis/jonlib/actions/runs/37130692849)
for exact published commit `0c663c9a85a8560199ccef89f76251ea05cfce8b`
completed successfully: Checks, all four Conformance workers and both preserved
compatibility aggregates passed, with all four expected evidence artifacts.
Observed worker durations were **81m53s Ubuntu core**, **47m21s Ubuntu
formatted**, **65m33s macOS core** and **52m11s macOS formatted**. These observed
split durations supersede the earlier planning estimates for that checkpoint.

That run contains PNM files and the split, but predates the added TGA-memory
gate. Its result remains scoped to that 79-gate checkpoint.

## Observed hosted TGA-memory checkpoint

The [verified 80-gate hosted run](https://github.com/jonathanperis/jonlib/actions/runs/37137893353)
for exact published commit `abc55e2b84d6b901bf822074f18614f1260e1110`
completed successfully on 2026-10-03: Checks run `37137893336`, all four
Conformance workers and both preserved compatibility aggregates passed. All
four uniquely named, nonempty evidence artifacts were present, and published
main matched the verified commit. Observed worker durations were **79m36s Ubuntu
core**, **63m15s Ubuntu formatted**, **66m21s macOS core** and **57m13s macOS
formatted**. The verification receipt is retained with the TGA-file source/
evidence backup.

That result qualifies the integrated TGA-memory/PNM-file checkpoint, and predates
the new formatted-TGA file gate. The local file-loader matrix is separate and
does not establish the new **81-gate** tip's hosted pass or runtime. A fresh
exact-commit all-worker/all-aggregate run and all four artifacts remain required
for that tip. No existing 120-minute worker budget or preservation baseline has
been loosened.

## Executable preservation contract

`tests/test_conformance_workflow.py` runs in the existing dependency-free
Python harness. Its frozen [baseline fixture](../tests/fixtures/conformance-before-runtime-split.yml)
has SHA-256
`610acab9fa0ca7fa6c3db8b93a828693c47e8ac202d89f76f0246053c45b84f9`.
The tests recognize job/step boundaries and compare their contents exactly;
they do not pretend to be a general YAML parser. They enforce the full workflow
header, exact worker settings, independent setup, ordered gate payloads, upload
settings, disjoint artifact union and exact aggregate topology. Mutation tests
reject missing/duplicate/reordered gates, changed commands/conditions/pins,
missing/wrong-platform workers, optional/skipped workers, broader uploads and
weaker aggregates. Both actual aggregate shells from the workflow are executed
for all 2,401 four-input combinations of success, failure, cancelled, skipped,
empty, unknown and missing result values (4,802 shell invocations). Only four
explicit successes may pass. Structural checks require each result to name its
corresponding direct dependency; no matrix reduction stands in for a worker.

The TGA-memory and TGA-file additions have their own explicit gate payloads
and artifact-path contracts in that test file; the frozen baseline is unchanged.
Both formatted workers must run
`tools/tga_format_probe.py --reference-env clean-loader` after all seven original
gates, immediately followed by `tools/tga_file_probe.py --reference-env clean-loader`.
Both commands use the original pinned Bend and raylib source arguments. Mutation
coverage rejects missing, duplicate, altered, reordered or optional TGA gates,
missing/altered clean-loader flags, and missing, changed or broadened TGA artifact
paths on each platform. Additional file-gate controls reject skipped steps,
bypassed failures, changed source arguments and duplicate artifact paths.
Sparse-body exclusions must match all four exact paths; mutations reject
omitted or duplicate exclusions, accidentally included sparse files, and
over-broad exclusions that drop ordinary exact-cap evidence, fixture recipes
or command/resource receipts. The original mutation suite and all 4,802
aggregate-shell truth-table invocations
remain intact.

Future intentional CI additions require explicit review and a corresponding
update to this preservation contract; do not silently relax comparisons or
regenerate the baseline merely to make a failure disappear. Parser validation
must preserve YAML's `on` key as a string (for example, PyYAML `BaseLoader`).
Existing PNM/QOI/R32 sparse-artifact and dependency-order tests remain in place.

For the original scheduling-only checkpoint, run the full Python harness, Python syntax
check and `tools/check_project.py`, and independently compare parsed workflow
objects with the reviewed inventory. Numeric probes need not be rerun locally
when their sources, fixtures and gate payloads are unchanged. Before calling
hosted CI green, observe fresh exact-commit Checks, all four Conformance workers,
both compatibility aggregates and the distinct evidence artifacts.

The TGA integration is not a scheduling-only change. It additionally requires a
fresh combined Python suite, complete proof, project/API checks, focused TGA
and PNM-file gates, canonical clean-loader conformance and strict independent
complete-record replay against the integrated source. Isolated reconstruction
receipts remain historical to their recorded source hashes. Final exact-commit
hosted Checks, all four workers and both aggregates are required separately.
