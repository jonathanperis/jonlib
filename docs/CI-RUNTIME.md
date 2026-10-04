# Conformance runtime and gate preservation

The runtime split reviewed on 2026-10-02 preserves the workflow at checkpoint
`36f5d0b5a811297b349c45aa6ddc3a9a067ac8d3`. It changes scheduling and artifact
package names only; no library, probe, numeric fixture, tolerance, compiler,
qualification, loader policy or resource ceiling changes are involved in that split.
The later reviewed TGA-memory, TGA-file, BMP-memory, BMP-file, PNG-memory and
PNG-file and PIC-memory additions are described separately below. The later scheduling-only TGA split
starts from exact 84-gate checkpoint `7dcfdb98a51af5dc0aa28f3affb060f185762a52`
after the observed macOS formatted-worker budget cancellation. It moves only
the two existing TGA gates and their six upload patterns into independent workers.
No gate, setup, loader flag, artifact evidence or 120-minute budget is weakened.

## Worker ownership

Each of Ubuntu 24.04 and macOS 15 runs six independent workers:

- **Core CPU and JavaScript:** the other 72 verification/diagnostic steps in
  their original order, including canonical conformance and all angle checks.
- **Formatted images CPU and JavaScript:** the seven original steps, in order:
  formatted BMP export, formatted TGA export, formatted QOI export, QOI memory,
  PNM memory, PNM files, and QOI files, followed by native PIC memory. PIC builds
  and qualifies its own PIC-enabled native archive and runs its complete
  CPU-one-thread, CPU-two-thread and JavaScript comparisons. The visible worker
  names are unchanged.
- **TGA memory and files CPU and JavaScript:** the existing mandatory native-format
  TGA-memory gate immediately followed by the existing format-preserving TGA-file
  gate. Both complete gate payloads move unchanged out of formatted workers.
- **BMP memory CPU and JavaScript:** the mandatory native-format BMP memory
  qualification gate immediately followed by format-preserving BMP file loading.
  Each gate has its own fresh native build and complete CPU-one-thread,
  CPU-two-thread and JavaScript comparisons. The existing worker names stay exact.
- **PNG memory CPU and JavaScript:** the mandatory native-format PNG memory
  qualification gate, with its own fresh native build, qualification and complete
  CPU-one-thread, CPU-two-thread and JavaScript comparisons.
- **PNG files CPU and JavaScript:** the mandatory format-preserving PNG-file
  gate in its own independent worker, with its own fresh native build,
  qualification and complete CPU-one-thread, CPU-two-thread and JavaScript
  comparisons. It does not share the PNG-memory worker's budget or receipts.

All 79 original gate step payloads still occur once per OS, byte-exact. The new
TGA-memory and TGA-file gates brought each OS to 81 gates: 72 core and nine
formatted. The new BMP-memory worker brings each OS to 82 gates: 72 core, nine
formatted and one BMP. The BMP-file addition brings each OS to 83 gates: 72 core,
nine formatted and two BMP. PNG memory brings each OS to **84 gates**: 72 core,
nine formatted, two BMP and one PNG before the TGA scheduling split. The
84-gate layout after that split is 72 core, seven formatted, two BMP, one PNG
and two TGA. The separate PNG-file workers bring each OS to **85 gates**:
**72 core, seven formatted, two BMP, one PNG memory, two TGA and one PNG file**.
At the PNG-file increment, all ten existing worker bodies, their names, setup,
84 gate payloads and artifact settings/paths remained byte-identical to the
ten-worker 84-gate checkpoint. Native PIC memory then brings each OS to
**86 gates: 72 core, eight formatted, two BMP, one PNG memory, two TGA and one
PNG file**. Both formatted workers append only the PIC gate and one upload
line; all 85 predecessor gate payloads, setup, settings, names and existing
paths remain exact. The other ten worker bodies and both all-twelve aggregate
bodies remain byte-identical to the 85-gate predecessor.
At the PNG-memory checkpoint, the four core/formatted worker jobs remained
byte-identical to the 81-gate checkpoint. All six pre-PNG worker jobs, including
IDs, names, settings, setup, existing 83 gate payloads and artifacts, remained
byte-identical to the 83-gate checkpoint at that increment. The TGA split keeps
all six core/BMP/PNG jobs byte-exact against the 84-gate predecessor. Each
formatted job changes only by removing the exact two TGA gates and six paths.
The BMP-file increment had preserved
both all-six compatibility aggregates; PNG extends those same named aggregates
to require all eight workers; the TGA scheduling split extends them to ten,
and standalone PNG files extend them to twelve.
Original Linux-only conditions, profile guards, legacy historical assertions
and clean-loader flags remain exact. Each worker independently repeats all seven original setup steps:
pinned repository/Python/Bun actions, dependency pin extraction, fresh exact Bend
and raylib checkouts, and hash-checked compiler overlay application. Environments and
120-minute timeouts are unchanged. Twelve explicit jobs (`coreUbuntu`, `coreMac`,
`formattedUbuntu`, `formattedMac`, `bmpUbuntu`, `bmpMac`, `pngUbuntu`, `pngMac`,
`tgaUbuntu`, `tgaMac`, `pngFileUbuntu`, `pngFileMac`) run without matrices,
so one worker failure does not cancel another worker. No cache or result
receipt replaces execution. Probes remain sequential within each workspace.

The core retains the R32 native archive producers before angle qualification.
The formatted worker's first BMP/TGA gates configure their own raylib build;
subsequent QOI/PNM gates make their own native builds. Both relocated TGA gates
make their own fresh native builds in their new independent workspace.
The appended PIC-memory gate independently enables `SUPPORT_FILEFORMAT_PIC`,
verifies its fresh archive configuration and qualifies that archive before
comparison. It has no dependency on another worker or preceding gate receipt.
The BMP and PNG workers likewise use fresh isolated native builds; they neither
reuse other workers' libraries nor skip qualification.
Canonical conformance continues to build and qualify its own reference.
No build or qualification receipt crosses worker machines.

## Required checks and artifacts

The old visible names, `CPU and JavaScript (ubuntu-24.04)` and
`CPU and JavaScript (macos-15)`, remain. Each is an `always()` aggregate requiring
success directly from **all twelve explicit worker IDs**. Neither aggregate uses
a matrix-family result, including on partial reruns.
The shell exits nonzero for failure, cancellation, skipped, empty, unknown or
missing dependency results. This is deliberately stricter than prior per-OS
independence: a failure on either platform fails both compatibility aggregates.
Their small validation shell runs on Ubuntu; the label identifies the preserved
check name, not where parity probes execute. Worker names identify the actual
platform and shard. There are no branch-protection or permission changes.

Artifact names are `conformance-<os>-core`, `conformance-<os>-formatted`,
`conformance-<os>-bmp`, `conformance-<os>-png`, `conformance-<os>-tga` and
`conformance-<os>-png-files`. All twelve packages have unique names. The original 156
path patterns remain partitioned into 140 core and 16 formatted patterns,
with no omissions or duplicates. The
reviewed `.build/tga-format-probe/` and `.build/tga-file-probe/` additions are
moved together from formatted artifacts to TGA artifacts in that order.
Four exact exclusions follow
the TGA-file directory: `run-*/fixtures/cap-plus-one.tga`,
`run-*/fixtures/cap-plus-one.qoi`, `run-*/fixtures/larger-file.tga` and
`run-*/fixtures/host-size-overflow.tga`, each under `.build/tga-file-probe/`.
At the scheduling split, formatted artifacts returned to their original 16 patterns. TGA artifacts contain
exactly the six moved patterns, including those four exclusions.
The new BMP artifacts include the entire `.build/bmp-format-probe/` directory,
with all source, input, native-build, command, output and resource receipts.
The BMP-file addition appends `.build/bmp-file-probe/` and four exact sparse-body
exclusions: `run-*/fixtures/cap-plus-one.bmp`, `run-*/fixtures/cap-plus-one.qoi`,
`run-*/fixtures/larger-file.bmp` and `run-*/fixtures/host-size-overflow.bmp`, all
under `.build/bmp-file-probe/`. Those names are checked against the actual file
harness controls. BMP files brought the total to 168 upload patterns per OS:
140 core, 22 formatted and six BMP, up from 163 at the BMP-memory checkpoint.
PNG adds the entire `.build/png-format-probe/` directory to its own artifact,
including all source, inputs, native-build, command, output and resource receipts.
PNG memory gives **169 patterns per OS**. The scheduling-only TGA split preserves that
exact multiset: 140 core, 16 formatted, six BMP, one PNG and six TGA. Only the
six exact TGA patterns move; no upload pattern is added, dropped or altered
by that scheduling change. The separate PNG-file artifacts contain five patterns:
`.build/png-file-probe/` and four exact sparse-body exclusions,
`run-*/fixtures/cap-plus-one.png`, `run-*/fixtures/cap-plus-one.qoi`,
`run-*/fixtures/larger-file.png` and `run-*/fixtures/host-size-overflow.png`,
all under `.build/png-file-probe/`. Those names are checked against the actual
PNG-file harness controls. That brings the total to **174 patterns per OS**:
140 core, 16 formatted, six BMP, one PNG memory, six TGA and five PNG-file
patterns, in twelve artifacts. PIC then appends `.build/pic-format-probe/`
after all 16 existing formatted patterns, matching the probe default output
directory. This brings the current total to **175 patterns per OS**:
140 core, 17 formatted, six BMP, one PNG memory, six TGA and five PNG-file
patterns, still in twelve artifacts. The full PIC directory retains source,
inputs, native-build, command, output and resource evidence. No existing pattern
moves or changes. The ordinary
1 MiB `exact-cap.tga`, `exact-cap.bmp` and `exact-cap.png`,
fixture recipes in `inputs.json`, source/native-build evidence, command/output
receipts and resource receipts remain included. The memory-only probes create
no sparse fixture files.
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
runtimes are recorded below, followed by the verified 81-gate result. Those
historical measurements do not qualify the current twelve-worker 86-gate tip;
the 120-minute
worker budgets are unchanged.

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
the new formatted-TGA file gate. The local file-loader matrix is separate; its
later exact-commit hosted qualification is recorded next. No existing 120-minute
worker budget or preservation baseline has been loosened.

## Observed hosted TGA-file checkpoint

The [verified 81-gate hosted run](https://github.com/jonathanperis/jonlib/actions/runs/37145573468)
for exact published commit `08dd860ebd24c8d1f49eb130d848764723e1f5c7`
completed successfully on 2026-10-03. Checks run `37145573474`, all four workers
and both compatibility aggregates passed; all four distinct nonempty evidence
artifacts were present, and published main matched the verified commit.
Observed worker durations were **64m30s Ubuntu core**, **87m36s Ubuntu formatted**,
**48m21s macOS core** and **71m40s macOS formatted**. The raw verification receipt
is retained in the BMP source/evidence backup. This is historical evidence for
the TGA-file checkpoint, not qualification of BMP or the new six-worker topology.

## BMP-memory worker planning and evidence boundary

The BMP-memory scheduling addition starts from exact 81-gate checkpoint
`08dd860ebd24c8d1f49eb130d848764723e1f5c7`, whose completed hosted result is
recorded above.

The pre-integration focused local Linux BMP-memory run took approximately
29m25s across 91 generated-source-bounded partitions. It is neither a hosted
measurement nor a macOS measurement. Adding that local duration to the observed
87m36s Ubuntu formatted worker gives **117m01s** as an illustrative planning
sum, not an observed combined runtime or a cross-machine equivalence. Adding
that gate to the existing formatted workers would consume substantial remaining budget and leave
uncertain margin for platform variability, setup and upload. Instead, BMP runs
alone at the 82-gate checkpoint in one additional worker per platform, with the
same seven pinned setup steps, environment, permissions and 120-minute limit. No timeout, probe command,
resource ceiling, numeric tolerance or existing gate is weakened.

Both new workers run
`python3 tools/bmp_format_probe.py --reference-env clean-loader`
with the original pinned Bend and raylib checkout arguments.
All six workers must succeed directly in both compatibility aggregates. The
[historical 82-gate hosted run](https://github.com/jonathanperis/jonlib/actions/runs/37152040429)
for exact commit `82a81b12e61ede4ec2d9901baddd4bf773651a5d` was verified successful
on 2026-10-03: Checks, all six workers, both aggregates and six distinct nonempty
artifacts passed. Observed Ubuntu core/formatted/BMP durations were **80m50s /
85m03s / 27m19s**; macOS durations were **69m37s / 77m23s / 38m05s**. That result
qualifies the memory checkpoint and does not qualify the subsequent file gate.

## BMP-file addition and evidence boundary

The additive BMP-file wiring starts from published 82-gate commit
`82a81b12e61ede4ec2d9901baddd4bf773651a5d`. Both existing BMP workers run
`python3 tools/bmp_file_probe.py --reference-env clean-loader` immediately after
their unchanged BMP-memory gate, using the same pinned Bend and raylib source
arguments. The existing `BMP memory CPU and JavaScript (<os>)` visible names
and both all-six fail-closed aggregates are unchanged. Only the two file-gate
blocks and five additional upload patterns per platform change in the workflow.
The file gate performs its own qualification and CPU-1/CPU-2/JavaScript matrix;
the preceding memory gate cannot substitute for any of these operations.

The exact **83-gate** hosted run
[37161146356](https://github.com/jonathanperis/jonlib/actions/runs/37161146356)
at `1312479cf9cd8ae1acc35b17cd99d0a2be5366a8` was verified successful on
2026-10-04: Checks run `37161146340`, all six workers, both compatibility
aggregates and six distinct nonempty evidence artifacts passed; published main
matched that commit. Observed Ubuntu core/formatted/BMP durations were
**77m43s / 81m38s / 61m24s**; macOS durations were
**41m45s / 73m47s / 58m10s**. This is historical BMP-file qualification, not
qualification of the later PNG increment. Its raw verification receipt is
retained with the PNG source/evidence backup.
The prior local Linux frozen matrix measured the unchanged
BMP-memory gate at **29m06s** and the new BMP-file gate at **27m39s**. Their
**56m45s** sum is illustrative local evidence, not a hosted runtime prediction
or a cross-machine equivalence. The existing 120-minute budgets stay unchanged.
Qualification of the integrated BMP-file source requires its frozen local
matrix, independent complete-record replay, proof and project/API checks,
followed separately by fresh exact-commit hosted Checks, all six workers, both
aggregates and all six distinct nonempty artifacts.

## PNG-memory worker planning and evidence boundary

The PNG-memory scheduling addition starts from exact 83-gate checkpoint
`1312479cf9cd8ae1acc35b17cd99d0a2be5366a8`. The complete focused local Linux PNG
run measured **21m51s**. That local measurement is neither a hosted nor a macOS
measurement and is not added to another machine's timing as a prediction.
The existing core and formatted workers already have long observed runtimes,
so PNG runs independently in `pngUbuntu` and `pngMac`, with the same seven
pinned setup steps, environment, permissions and 120-minute limit. Existing
workers, all 83 prior gates and their artifact payloads are byte-preserved.

Both new workers run
`python3 tools/png_format_probe.py --reference-env clean-loader`
with the original pinned Bend and raylib checkout arguments. This gate builds
and qualifies its own native reference and performs its own CPU-1/CPU-2/JavaScript
matrix. A prior worker's result cannot substitute for qualification or execution.
Each new artifact contains the entire `.build/png-format-probe/` directory.
At the PNG-memory checkpoint, both compatibility aggregates directly required
all eight explicit worker IDs. The TGA scheduling split extends them to ten,
and standalone PNG files extend them to twelve.

The integrated **84-gate** hosted run
[37172746027](https://github.com/jonathanperis/jonlib/actions/runs/37172746027)
at `7dcfdb98a51af5dc0aa28f3affb060f185762a52` did **not** establish a complete
pass. On 2026-10-04, all seven other workers succeeded, while the macOS formatted
worker was cancelled after **120m25s**, consistent with its 120-minute budget.
Both compatibility aggregates failed closed. No explicit timeout annotation was
available, so cancellation at the worker budget is the observed evidence.

That worker started at **03:00:16 UTC**, finished its original seven formatted
gates by **04:12:46**, and finished TGA memory by **04:48:50**. The TGA-file log
records successful comparisons for batches 1–16 before cancellation at
**05:00:41**, with no reported comparison mismatch. Partial successful batches do
not qualify the complete file gate or this exact commit. These observed timings
motivate moving both unchanged TGA gates into their own workers rather than
raising a timeout or weakening execution. They do not predict hosted timings
for the new topology or guarantee its budget margin.

## Observed hosted TGA scheduling-fix checkpoint

The scheduling-only split retains **84 gates per OS** and **169 upload patterns
per OS**, distributed over ten workers and ten artifacts. Its exact commit
`9cb5a7e7cabdb76005a76119616e33ca9516d73b` was verified successful on 2026-10-04:
[Conformance run 37179587107](https://github.com/jonathanperis/jonlib/actions/runs/37179587107),
[Checks run 37179587100](https://github.com/jonathanperis/jonlib/actions/runs/37179587100),
all ten workers, both compatibility aggregates and all ten distinct nonempty
artifacts passed; published main matched that commit. Observed Ubuntu
core/formatted/BMP/PNG-memory/TGA worker durations were **79m32s / 45m22s /
61m50s / 22m36s / 37m59s**; macOS durations were **60m01s / 47m07s / 49m27s /
50m26s / 38m14s**. The raw verification receipt is retained with the
scheduling-fix source/evidence backup. This result qualifies the 84-gate split,
not the new PNG-file implementation or twelve-worker topology.

## Standalone PNG-file planning and evidence boundary

The PNG-file addition starts from that exact successful ten-worker checkpoint.
The focused local Linux file gate measured **45m09s**, while the recorded local
PNG-memory run measured **21m51s**. Those are local measurements, not hosted or
macOS predictions. The observed macOS PNG-memory worker took **50m26s**, showing
substantial cross-machine variability. Its timing ratio is not assumed to
transfer to the file gate; stacking the two gates would leave unestablished
headroom. Instead, PNG files receive separate `pngFileUbuntu` and `pngFileMac`
workers named `PNG files CPU and JavaScript (<os>)`, each with its own unchanged
120-minute limit and all seven independently repeated pinned setup steps.
All ten old worker bodies remain byte-identical, including PNG-memory jobs.

Both new workers run
`python3 tools/png_file_probe.py --reference-env clean-loader`
with the original pinned Bend and raylib source arguments. Each runs its own
fresh native build, qualification and CPU-1/CPU-2/JavaScript matrix. Prior
memory evidence does not substitute for file qualification or execution.
Both compatibility aggregates keep their exact names and five-minute limits,
and directly require all twelve workers with fail-closed straight-line tests.
Each new artifact is named `conformance-<os>-png-files` and retains ordinary
exact-cap input, fixture recipes and complete source/native-build, command,
output and resource evidence while excluding only four exact sparse bodies.

That CI-only patch changed no compiler, native probe, implementation, fixture,
numeric expectation or resource ceiling. The **85-gate** hosted run
[37187107908](https://github.com/jonathanperis/jonlib/actions/runs/37187107908)
for exact commit `e6ac05e6d1daf64d050e6da3f783ed60cc3130e1` completed
successfully on 2026-10-04, together with [Checks
37187107919](https://github.com/jonathanperis/jonlib/actions/runs/37187107919).
All twelve workers, both compatibility aggregates and all twelve unique,
nonempty evidence artifacts were independently verified for that exact main
commit. This closes the predecessor's hosted qualification; it does not qualify
the later PIC-memory source or its 86-gate workflow. The frozen local PNG-file
matrix, independent replay and separate final metadata/CI checks remain the
historical local evidence described in [VERIFICATION.md](VERIFICATION.md).

## PIC-memory planning and evidence boundary

The additive PIC-memory wiring starts from exact twelve-worker 85-gate commit
`e6ac05e6d1daf64d050e6da3f783ed60cc3130e1`. Its focused fresh local Linux
PIC gate measured **1,023.403 seconds (about 17 minutes)**. This is a local
planning measurement, neither a hosted nor macOS measurement. The historical successful `9cb5a7e7` scheduling-fix run
measured the original seven-gate formatted workers at **45m22s on Ubuntu** and
**47m07s on macOS**. The later exact green `e6ac05e6` run measured those
formatted workers at **44m04s on Ubuntu** and **25m12s on macOS**. These observed
variations support retaining explicit headroom while appending PIC in the
existing formatted workers; adding local and hosted
times does not establish a combined runtime, a hosted prediction or guaranteed
budget margin. Both workers retain their original 120-minute limit.

Both formatted workers run
`python3 tools/pic_format_probe.py --reference-env clean-loader`
with the original pinned Bend and raylib source arguments, immediately after
all seven unchanged original gates and before evidence upload. The new gate
performs its own fresh isolated native build with `SUPPORT_FILEFORMAT_PIC=ON`,
verifies the build configuration and archive, and independently qualifies that
archive before its complete CPU-1/CPU-2/JavaScript matrix. It cannot reuse
another worker's build or rely on a preceding gate's qualification.

The workflow changes only two PIC gate blocks and one full-directory upload
line per platform. No worker, dependency, artifact package or aggregate body is
added or renamed; all twelve worker IDs, both all-twelve aggregate bodies and
all existing setup, permissions, environment, pins and timeouts remain exact.
This CI-only change does not change implementation, probes, fixtures,
expectations, tolerances or resource ceilings. It yields **86 gates and 175
upload patterns per OS**, with twelve workers and twelve distinct artifacts.

PIC's frozen local source matrix and independent complete-record replay passed,
including 1,053 Python tests without skips, 190 scoped laws and project/API checks.
The later final metadata/CI-tree snapshot is validated separately; it does not
replace runtime evidence. Exact-commit hosted Checks, all twelve workers, both
compatibility aggregates and all twelve nonempty artifacts must pass separately.
No **86-gate** hosted result or combined formatted-worker runtime is claimed.
The exact green 85-gate predecessor `e6ac05e6` remains separate from this PIC
increment, as do the older incomplete `7dcfdb98` and successful `9cb5a7e7` runs.

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
for all 2,401 original four-input combinations of success, failure, cancelled,
skipped, empty, unknown and missing result values (4,802 shell invocations),
with both BMP, both PNG, both TGA and both PNG-file results explicitly set to success. The existing
98 actual-shell invocations exhaust both BMP result combinations with the
original four, both PNG, both TGA and both PNG-file results explicitly successful. Another
**98 actual-shell
invocations** exhaust both PNG result combinations with the preceding six and
both TGA and both PNG-file results explicitly successful. Those **4,998 actual Bash invocations**
remain, plus **98 actual-shell TGA-pair cases** with all preceding eight results
and both PNG-file results successful: **5,096 preserved actual Bash invocations**.
A further **98 actual-shell PNG-file-pair cases** hold all preceding ten results
successful, for **5,194 actual Bash invocations total**. The scripts are
constrained to `set -eu`, five literal diagnostic prints and twelve straight-line
success tests. That restricted grammar proves conjunction semantics. The original
117,649 six-way assignments per aggregate (235,298 total) are still evaluated
in-process with both PNG, both TGA and both PNG-file results successful. In addition, all
**5,764,801 eight-way
assignments per aggregate (11,529,602 total)** are exhaustively evaluated in-process;
both TGA and both PNG-file results are explicitly successful; these are not additional shell
invocations. The grammar factors into the old eight-result conjunction and the
two-result TGA conjunction. All 49 TGA status pairs are checked against both
possible old-eight outcomes; the checked factor counts cover **282,475,249
ten-way assignments per aggregate** without iterating the whole Cartesian product
or spawning more shells, with the new PNG-file pair successful. A separate
twelve-way proof checks the closed conjunction grammar, each prior variable
over all seven statuses, and all 49 PNG-file pairs against both possible old-ten
outcomes. Weighted outcome counts cover **13,841,287,201 twelve-way assignments
per aggregate** without iterating that Cartesian product or spawning additional
shells. These are factorized proofs, not billions of executed cases. Only twelve
explicit successes may pass. Structural checks
require each result to name its corresponding direct
dependency; no matrix reduction stands in for a worker.

The TGA-memory and TGA-file additions have their own explicit gate payloads
and artifact-path contracts in that test file; the frozen baseline is unchanged.
Both TGA workers must run
`tools/tga_format_probe.py --reference-env clean-loader` immediately after their
seven pinned setup steps, immediately followed by
`tools/tga_file_probe.py --reference-env clean-loader`. Formatted workers retain
their original seven gates and their original order, followed only by the
explicitly reviewed PIC gate.
Both commands use the original pinned Bend and raylib source arguments. Mutation
coverage rejects missing, duplicate, altered, reordered or optional TGA gates,
missing/altered clean-loader flags, and missing, changed or broadened TGA artifact
paths on each platform. Additional file-gate controls reject skipped steps,
bypassed failures, changed source arguments and duplicate artifact paths.
Sparse-body exclusions must match all four exact paths; mutations reject
omitted or duplicate exclusions, accidentally included sparse files, and
over-broad exclusions that drop ordinary exact-cap evidence, fixture recipes
or command/resource receipts. The original mutation suite and all 4,802
aggregate-shell truth-table invocations remain intact, with both BMP, both PNG
and both TGA and both PNG-file results explicitly successful.

BMP has a separate exact gate and full-receipt artifact contract. Mutations
reject changed or missing setup, platforms, commands, loader/source arguments,
budgets, environment, permissions, optional/skipped/dependent workers,
bypassed failures, artifact collisions and incomplete or broadened uploads.
Every one of the twelve dependency/result/test links is mutation-checked in both
aggregates. BMP-file mutations separately reject missing, altered, duplicate,
reordered, optional or skipped gates, bypassed failures, changed loader/source
arguments, broadened uploads and missing/altered/duplicate sparse exclusions.
Positive artifact checks retain ordinary `exact-cap.bmp`, fixture recipes,
source/native-build files, command/output and resource receipts; mutations reject
exclusions that remove them.

PNG has its own exact gate and complete-directory artifact contract. Mutations
reject missing setup steps, changed action/dependency pins or overlay checks,
platforms, source and clean-loader arguments, budgets, permissions, environment,
optional/skipped/dependent workers, missing/duplicated/reordered gates, masked
failures, artifact collisions and incomplete/broadened uploads. An independent
closed shell-grammar check rejects missing tests, default-success substitution,
OR lists, subshell masking, changed errexit, conditionals and injected commands.

The standalone PNG-file workers have explicit mandatory payload, setup,
clean-loader, pinned-source, budget, permission, ordering and upload contracts.
Mutations reject missing/duplicate/altered/optional/skipped gates and workers,
bypassed failures, changed sources or pins, artifact collisions and missing,
narrowed or broader upload roots. Sparse-body mutations reject missing,
duplicate, included or over-broad exclusions. Positive retained-file checks and
mutations protect exact-cap, ordinary inputs, fixture recipes, source/native
builds and full command, output and resource receipts. All twelve direct
worker/result/test links are checked, including cross-worker substitution and
new-pair diagnostic injection. The historical ten-way grammar mutation tests
remain active and extend to the new result variables.

PIC has a separate exact gate and complete-directory artifact contract.
Mutations reject missing, duplicate, altered, optional or skipped gates;
changed loader or pinned-source arguments; bypassed failures; placement before
any original gate; and missing, duplicate, stale, narrowed, broader or reordered
upload paths. Its upload remains after all 16 original formatted patterns.
Independent raw-byte and `BaseLoader` YAML validation rejects these mutations
separately and compares each original worker and aggregate against the exact
85-gate predecessor. The CI-only tests retain every historical actual-Bash,
six/eight-way exhaustive and ten/twelve-way factorized test body byte-for-byte.

Independently of the structural parser, removing only the two PIC gate blocks
and one new upload line per OS must restore the complete 85-gate twelve-worker
workflow at `e6ac05e6d1daf64d050e6da3f783ed60cc3130e1`, SHA-256
`3b5f0be5c6ee604316f3e9015f72d4316b9792c3949bff91698053617cc7268e`.
Both aggregate bodies are identical, and all 85 old gates and 174 old patterns
remain exact; PIC alone produces the new 86-gate/175-pattern totals.
From those restored bytes, removing only the two PNG-file worker
blocks and explicitly reviewed aggregate extensions must restore the complete
84-gate ten-worker workflow at `9cb5a7e7cabdb76005a76119616e33ca9516d73b`, SHA-256
`8bfab667d418967d2427f41079411c1ef8d2e6698068127cde4cd4a950eb6b91`.
From those restored bytes, the unchanged TGA inverse extracts the exact gate
and upload payloads from the two new TGA jobs, reinserts those bytes in their
original formatted positions, and removes only the new jobs and explicit
aggregate extensions. This restores the complete 84-gate predecessor bytes,
SHA-256 `bf6f62710566b8c186548330d18437079349e00283f6ffc3842c63bd6de98b09`.
From those restored bytes, removing only the two PNG worker blocks and the
explicitly reviewed aggregate extensions must restore the complete
83-gate workflow bytes, SHA-256
`056713e25bab0092e22a4bfb1d68b687c821dbe77b8174b2932b7db7208c082b`.
From those restored bytes, removing only the two BMP-file gates
and five added upload patterns per OS must restore the complete 82-gate workflow
bytes, SHA-256
`809c8d6c02b715b44cfa013a1c2644ac5d15cf0a8b1d8dc5d2f5745ce5c5e4f1`.
From those restored bytes, removing only the BMP worker jobs and the explicitly
reviewed aggregate additions must still restore the complete 81-gate workflow,
SHA-256
`34fa72b91f6e4ab3e7e555c51e621364bf1b68e1dba4945db2442ad8e463ce7e`.
All six predecessor raw-byte anchors remain active;
`read_bytes().decode('utf-8')` preserves line endings so a CRLF rewrite cannot evade the checks. The original baseline
fixture, all 5,096 prior Bash cases, all 235,298 six-way assignments, all
11,529,602 eight-way assignments and the factorized ten-way checks retain their
meaning with the new pair successful. The new 98 shell cases and factorized
twelve-way proof are additive. Independent raw-byte and parsed-YAML comparison
checks all ten old workers as identical objects and bytes, all existing aggregate
content after removing only explicit extensions, and new-worker setup, gate and
upload contracts. It verifies complete restored predecessor bytes and objects,
all 84 old gates and 169 old patterns, and the intermediate 85-gate/174-pattern
totals after reversing the PIC addition.


Future intentional CI additions require explicit review and a corresponding
update to this preservation contract; do not silently relax comparisons or
regenerate the baseline merely to make a failure disappear. Parser validation
must preserve YAML's `on` key as a string (for example, PyYAML `BaseLoader`).
Existing PNM/QOI/R32 sparse-artifact and dependency-order tests remain in place.

For the original scheduling-only checkpoint, run the full Python harness, Python syntax
check and `tools/check_project.py`, and independently compare parsed workflow
objects with the reviewed inventory. Numeric probes need not be rerun locally
when their sources, fixtures and gate payloads are unchanged. Before calling
hosted CI green, observe fresh exact-commit Checks, all twelve current Conformance
workers, both compatibility aggregates and the twelve distinct evidence artifacts.

The earlier TGA implementation integration was not a scheduling-only change.
Its separate requirements include a fresh combined Python suite, complete proof,
project/API checks, focused TGA and PNM-file gates, canonical clean-loader
conformance and strict independent
complete-record replay against the integrated source. Isolated reconstruction
receipts remain historical to their recorded source hashes. Final exact-commit
hosted Checks, all current workers and both aggregates are required separately.
The BMP, PNG and PIC implementations also require their own frozen-source local matrices,
complete proof, independent replay and project/API checks before integration;
CI wiring by itself does not establish library parity.
