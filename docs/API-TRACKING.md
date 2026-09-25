# API inventory and progression policy

Start with the [progress dashboard](PROGRESS.md) and its six per-header checklists.
The [master plan](MASTER-PLAN.md) supplies the phase exit gates. The ledger is
the source of API-level progress for every future implementation batch.

## Frozen scope

The target is raylib 6.0 at the revision in `toolchain.json`. The catalog retains:

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

The target matrix comes from the pinned [FAQ](https://github.com/raysan5/raylib/blob/dbc56a87da87d973a9c5baa4e7438a9d20121d28/FAQ.md)
and [CMake options](https://github.com/raysan5/raylib/blob/dbc56a87da87d973a9c5baa4e7438a9d20121d28/CMakeOptions.txt).
Each target's evidence must enumerate applicable OS/device/backend combinations.
CPU/JS/Metal execution of headless algorithms does not verify window, browser,
graphics-pipeline or audio-device behavior on those platforms.

## Files and authority

| File | Role |
|---|---|
| `api/reference.json` | Generated source catalog, immutable revision, per-header SHA-256 and source links |
| `api/milestones.json` | Editable work packages, prerequisites, verification recipes, target policy and priority overrides |
| `api/progress.json` | Editable item-level implementation, status, scope, gaps and evidence; omitted entries mean `not-started` |
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

Six gates make the master plan's criteria explicit: **availability, behavior,
ownership, integration, targets, performance**. Ownership is tracked separately
from behavior because Bend resource adaptations need their own review.
`complete` requires all six verified, evidence for every gate, no gaps/blocker,
actual Bend symbols for functions/operators, and a result for every target ID.
A `reference-not-supported` target requires a reason and reference evidence.
Language adaptations still need behavior/ownership/integration justification.

Validation checks structure, references and evidence presence; reviewers must
check that the evidence actually proves the claim. A URL or existing document
is not automatically proof of parity. Existing `profile-covered` and
`contract-checked` statuses survive only in the legacy conformance view; both
mean `partial` in the authoritative ledger.

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
4. Update scope, gaps, evidence and gate results. Keep exact case/lane counts
   and input hashes in the evidence documents. Then regenerate and check:

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

## Drift and extraction verification

`tools/check_project.py` runs the offline generated-file/evidence gate.
Conformance additionally re-extracts all six headers from the pinned checkout:

```sh
python3 tools/api_plan.py check --clang-audit \
  --raylib-source "$HOME/Projetos/raysan5/raylib"
```

The extractor retains conditional source alternatives. An independent Clang AST
audit compares all public C function names and exact C++ overload signatures.
Neither audit executes those APIs. Source-aware checks also compare the whole
catalog, including hashes and support entries. Extraction changes must be
reviewed and explicitly regenerated with `sync --raylib-source PATH`; checks
never repair source or generated files. Both hosted conformance jobs run this
audit. The [inventory verification record](API-INVENTORY-VERIFICATION.md)
records the initial proof and its limits.
