# API inventory and progression policy

Start with the [progress dashboard](PROGRESS.md) and its six per-header checklists.
The [roadmap](ROADMAP.md) states what remains. The ledger is
the source of API-level progress for every future implementation batch.

## Frozen scope

The target is raylib 6.2 at the revision in `toolchain.json`. The catalog retains:

- Every public C function in `raylib.h`, `raymath.h`, `rlgl.h`, `rcamera.h` and
  `rgestures.h`, including standalone and conditional declarations.
- Types and their fields, aliases, opaque resources, callbacks, enums and each
  enum value, numeric/color macros, and source-package/preprocessor controls.
- Optional raymath C++ operator overloads and constants. Bend equivalents may
  use named functions; the behavior still needs coverage.
- Active and documented commented-out `config.h` defaults/overrides. Private
  implementation constants below companion-header implementation boundaries
  are implementation details, not additional public API rows.

Stable IDs use `header:kind:name`; overload IDs include parameter types. Duplicate
declarations across headers stay visible through `related_declarations`; they
are counted as declarations, with a separate unique-C-function-name total.
Conditional alternatives of one declaration live in `variants`, retaining
signatures, value expressions, member declarations, conditions and source lines.
Implicit enum values reference the previous enumerator rather than guessing a
host-dependent numeric interpretation.

Header guards, export macros and C compatibility glue remain support entries.
Their Bend mapping may be a documented package/language adaptation. They are
never counted as implemented rendering functions. Internal dependencies such as
stb and miniaudio are used to derive raylib behavior; their private APIs are not
additional Jonlib public APIs. Separate projects such as raygui and third-party
bindings/homebrew ports are not public headers of this pinned raylib release.

The target matrix comes from the pinned [FAQ](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/FAQ.md)
and [CMake options](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/CMakeOptions.txt).
Each target's evidence must enumerate applicable OS/device/backend combinations.
CPU/JS/Metal execution of headless algorithms does not verify window, browser,
graphics-pipeline or audio-device behavior on those platforms.

## Files and authority

| File | Role |
|---|---|
| `api/reference.json` | Generated source catalog, immutable revision, per-header SHA-256 and source links |
| `api/milestones.json` | Editable work packages, prerequisites, verification recipes, target policy and priority overrides |
| `api/progress.json` | Editable item-level implementation, status, scope, gaps, language adaptations and evidence; omitted entries mean `not-started` |
| `api/ledger.json` | Generated join: one complete planning record per catalog ID |
| `api/summary.json` | Generated counts, milestone progress and next-work queue |
| `docs/PROGRESS.md`, `docs/api/*.md` | Generated human-readable dashboard and complete checklists |
| `docs/api-map.json` | Generated legacy view of implemented core mappings consumed by conformance |

Every record has a current or proposed Bend surface, milestone, source contract,
type/API/work-package dependencies, a verification recipe and next action.
Proposed names are planning targets, not approved or implemented Bend interfaces.
The first action for an unstarted API is to derive detailed acceptance from its
implementation and examples; declaration enumeration alone cannot settle its
edge semantics. Known API prerequisites are explicit; dependency lists may grow
as each contract is investigated. Work packages are displayed in topological
order. Phase labels indicate the full delivery phase; foundational slices of
rlgl/shaders are required earlier by 2D/3D work.

## Status and completion

- `not-started`: catalogued and assigned work, no implementation established.
- `in-progress`: active work, with scope/evidence recorded as available.
- `partial`: a usable mapped subset with evidence and open domains/gates.
- `blocked`: a concrete blocker prevents the planned implementation.
- `complete`: the entire reference contract meets every completion gate.

Six completion gates are tracked per entry: **availability, behavior,
ownership, integration, targets, performance**. Ownership is tracked separately
from behavior because Bend resource adaptations need their own review.
`complete` requires all six verified, evidence for every gate, no gaps/blocker,
actual Bend symbols for functions/operators, and a result for every target ID.
A `reference-not-supported` target requires a reason and reference evidence.
Language adaptations still need behavior/ownership/integration justification.

### What verified means

`tools/gate_evidence.py` derives `behavior`, `ownership`, `integration` and
`performance` from the progress record and the repository.
`python3 tools/api_plan.py check` rejects a record whose stored gates disagree,
so a gate cannot be marked `verified` by editing `api/progress.json` alone.
`python3 tools/gate_evidence.py --apply` rewrites only the `gates` objects.
`availability` and `targets` are not derived. A stored `verified` claim for
either is rejected; any other stored value is kept, and a missing key stays
`unverified`.

**behavior = `verified`** when all of the following hold:

1. The record is implemented: `status` is `partial` or `complete` and `jonlib`
   names a mapping.
2. No gap is open behavior work. A gap is open behavior work unless it starts
   with `Targets:`, `Integration:`, `Performance:` or
   `Undefined native behavior:`. A `Libm:` gap is open behavior work: a host
   libm profile is not bit-exact parity, and a diagnostic libm gate is not a
   parity claim. Any other untagged gap is open behavior work.
3. `evidence` includes a parity probe: a non-diagnostic gate in
   `tools/gates.json` whose hosts are both `linux` and `macos`, whose command
   compares against the pinned raylib, and whose program compares exactly on
   `cpu-1`, `cpu-2` and `javascript` (`probekit.Probe.compare`, or
   `tools/conformance.py`). Hosted CI does not pass `--gpu`, so those three
   lanes are the CI lanes. The examples suite is not a behavior witness.
4. That probe covers this entry. Coverage is the Bend symbol used as a dotted
   name in the program the probe runs, or the C name as a string in that
   program (a case table). A bare C call is not coverage: generated oracles
   call raylib for setup and teardown. A probe that selects catalog rows
   covers exactly the rows its own selector returns (`enums_probe.enumerators`,
   `macros_probe.macros` and `macros_probe.shared_options`).
5. No gap says that Linux or macOS is not verified. A `Targets:` gap may
   record that, and it still blocks this gate: the probe is scheduled on both
   CI hosts, but the record has withdrawn one of them. A gap that only says
   the Metal lane is not verified does not block this gate.

IEEE 754 clause 6.3 leaves the sign of a NaN produced by an invalid operation
unspecified. Upstream builds of the pinned raymath return either quiet-NaN
sign for the same inputs (`inf - inf`, `0/0`, `0*inf`) depending on
instruction selection, so that sign is not a Jonlib behavior gap. The
component operations that hit it (`Normalize`, and Vector2/Vector3/Vector4
and Quaternion add, subtract, scale, multiply and divide, including the
`*_value` forms, and the C++ operators that call those functions or a
left-associated transform or matrix product) compare a fresh quiet NaN by
NaN-ness: any quiet NaN matches. A non-NaN result stays bit-exact. One NaN
operand is returned unchanged, which those builds do deterministically. When
both operands are NaN, which payload survives varies the same way, so that
result is also compared by NaN-ness. The gap is tagged `Undefined native
behavior: sign of a NaN from an invalid operation is unspecified (IEEE 754
6.3) and varies in upstream builds`. The rule is not used for any other
difference. Equality operators stay exact.

An implemented record that cites such a probe but fails one of those conditions
is `partial`. A record with no such probe is `unverified`.

**ownership = `verified`** when all of the following hold:

1. The record is implemented, as for behavior.
2. The scope or a language adaptation states the owner mapping. The statement
   uses owner, ownership, consume, consumed, owned, affine, retain, retained,
   unload, unloaded, dispose, disposed, clone, freed or pool. Saying that a
   function returns a number is not an owner mapping.
3. An affine test or proof that a cited parity probe actually runs names the
   Bend symbol or calls the C function. The test is a definition whose name
   carries `ownership`, `owned`, `unloaded`, `disposed`, `retained`, `released`
   or `consumed`, a definition that test calls directly, or a call of
   `unload`, `unload_colors` or `free`. A law counts only when its own
   statement is about ownership. A sentence in a document is not a test.

One of those two conditions, but not both, is `partial`. Neither is
`unverified`. A behavior comparison that happens to return a value is not an
ownership test.

**integration** is `partial` when a gap starts with `Integration:` or evidence
includes an examples replay, and `unverified` otherwise. It is not `verified`:
a headless examples replay is not desktop integration.

**performance** is `partial` when a gap starts with `Performance:` or evidence
includes `docs/PERFORMANCE.md`, `tools/gradient_bench.py` or
`tools/perf_examples.py`, and `unverified` otherwise. It is not `verified`:
those benchmarks are not parity gates.

Forced Metal is not inferred from the CPU or JavaScript lanes. Hosted runners
have no GPU, and the current compiler overlay's Metal rebase has not been
re-run ([METAL-INVESTIGATION.md](METAL-INVESTIGATION.md)). A local `--gpu` pass
on the current Bend pin is recorded by a line in a file the entry lists as
evidence:

```
Metal witness: raylib:function:ImageResize a3efe8a3801f423827424227172eed9802c5e6cb pass
```

The revision is the `bend` revision in `toolchain.json`. Copying a CPU result
into that line is not a witness.

## Language adaptations

Some differences from the C declaration are permanent consequences of porting C
to Bend, not missing work. An entry records them in `adaptations`, separately
from `gaps`. Only a language-level mapping with **no behavior difference
reachable through the API** qualifies:

- C macros, compound literals and `constexpr` objects as zero-argument functions;
  enums as U32 constants; C int-compatible bool conversions.
- Include, type and redefinition guards, export/linkage macros, implementation
  switches and build options that Jonlib, a Bend package, is not configured by.
- Pointer, allocator, output-parameter and struct-layout ABI: owned values,
  lists that carry their length and Base strings instead of pointers,
  counted buffers and NUL-terminated `char` arrays; no pointer aliasing.
- Implicit globals as explicit state values; mutation in place as a returned
  value; static buffers as returned values; consuming a value to release it.
- Operator overloading by operand type as named calls; varargs as preformatted
  text; callbacks as tags or functions the program supplies.

Anything with an observable difference stays a gap: a value Jonlib refuses or
answers differently, a lost or truncated input, a capability or target that is
missing, a different error, a domain, precision or resource limit. A record
that mixes the two is split: the adaptation goes to `adaptations`, the
remainder stays a gap. When in doubt, it is a gap.

Adaptations are shown as "Language adaptations" in the generated ledger,
dashboard and per-header checklists. They are not counted as gaps, do not
affect the Phase 1 exit measure, and are never sufficient for completion:
`complete` still needs all six gates verified (including targets on Linux and
macOS), every target result, per-gate evidence and no gaps.

Validation checks structure, references, evidence presence and, for the four
derived gates, that the stored value is the one `tools/gate_evidence.py`
derives. Reviewers must still check that a probe's comparison really exercises
the contract it names. A URL or existing document is not proof of parity. Existing `profile-covered` and
`contract-checked` statuses survive only in the legacy conformance view; both
mean `partial` in the authoritative ledger.

## Phase 1 exit measure

The strict status completes an item only with every target, which for most
Phase 1 functions means Phase 7 (the phases of `api/milestones.json` are
listed in [ROADMAP.md](ROADMAP.md#delivery-phases)). The Phase 1
exit measure is reported alongside it by `tools/api_plan.py` (dashboard,
`api/summary.json` `phase1_exit`): a Phase 1 function meets it when it is
`partial` or `complete`, its `behavior` and `ownership` gates are `verified`
under the rules above, every remaining gap starts with `Targets:`,
`Integration:`, `Performance:` or `Undefined native behavior:`, and its
evidence contains a forced-Metal witness for the current Bend pin. Untagged
gaps, including `Libm:` gaps, count as open behavior work. A CPU or JavaScript
pass does not satisfy the Metal witness.

## Work through one batch

1. Pick stable IDs from `docs/PROGRESS.md`; inspect prerequisites and source:

   ```sh
   python3 tools/api_plan.py show raylib:function:ImageResize
   ```

2. Derive domain/error/resource contracts and fixtures from the pinned source
   and upstream examples. Record scoped work in `api/progress.json`; use
   `proposed_jonlib` for a planned name and `jonlib` for an existing mapping.
3. Implement and run the applicable reference comparisons, ownership checks,
   integration examples, targets and performance measurements.
4. Update scope, gaps, evidence and gate results following the record rules
   below. `behavior`, `ownership`, `integration` and `performance` are not
   edited by hand: `python3 tools/gate_evidence.py --apply` rewrites those
   gates from the evidence. Case/lane counts, hashes and timings belong in
   gate results (`.build/gates/`), not in progress records. Then regenerate
   and check:

   ```sh
   python3 tools/api_plan.py build
   python3 tools/check_project.py
   python3 -m unittest discover -s tests -v
   ```

5. Report the actual delta against a revision containing this ledger:

   ```sh
   python3 tools/api_plan.py report --since BASE_COMMIT
   python3 tools/api_plan.py report --json
   ```

Each delivery report gives: stable IDs changed, before/after status and scope,
new user-visible behavior, commands/cases/targets verified, unresolved gaps,
milestone progress and the next dependency. New evidence counts even when an
API remains partial. Never report mapped functions divided by 600 as overall
parity. The release gate also requires formats, integration, performance and
the complete target matrix.

## Progress record rules

`api/progress.json` records state the **contract**, not the history of how it
was verified:

- `scope`: inputs, formats and bounds; the error and ownership model; notable
  reference quirks that are reproduced or deliberately rejected. No hosts, lanes,
  counts of tests/observations/bytes, timings, commit hashes, CI run IDs or
  "pending" qualification claims. Aim for 250 characters, at most 500.
- `gaps`: at most six items naming missing contract domains or target areas
  (formats, numeric domains, ABI, platforms, performance), about 160 characters each.
- `adaptations`: at most six [language adaptations](#language-adaptations),
  about 120 characters each.
- `evidence`: at most twelve repository paths, led by the probe(s) and the
  topic page; no historical pages or run records.

`python3 tools/api_plan.py check` (also run by `tools/check_project.py`) rejects a
scope over 600 characters, more than six gaps, a gap over 200 characters, more than
six adaptations, an adaptation over 200 characters or repeated (in the list or
as a gap), more than twelve evidence paths, and any 40-hex commit hash or
9+-digit run ID in a scope, gap, adaptation or blocker.

## Drift and extraction verification

`tools/check_project.py` runs the offline generated-file/evidence gate.
Conformance additionally re-extracts all six headers from the pinned checkout.
Use the checkout variables defined in [README.md](../README.md#requirements):

```sh
python3 tools/api_plan.py check --clang-audit \
  --raylib-source "$RAYLIB_SOURCE"
```

The extractor retains conditional source alternatives. An independent Clang AST
audit compares all public C function names and exact C++ overload signatures,
active typedefs/enumerators and C++ constants; a separate line audit accounts for
every public typedef/define/constexpr alternative, including ones inactive on the
auditing host. Neither audit executes those APIs: they establish declaration
accounting, not runtime parity, semantic contracts or platform support. Source-aware checks also compare the whole
catalog, including hashes and support entries. Extraction changes must be
reviewed and explicitly regenerated with `sync --raylib-source PATH`; checks
never repair source or generated files. The `api-audit` gate in `tools/gates.json` runs this
audit on both CI hosts.
