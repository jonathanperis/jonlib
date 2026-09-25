# Complete API inventory: verification record

Reference: raylib 6.0, `dbc56a87da87d973a9c5baa4e7438a9d20121d28`.
Local verification: Apple Silicon/macOS, Apple Clang 21, Python 3.14, 2026-09-24.
Per-header hashes and immutable declaration links are in `api/reference.json`.

## Inventory result

| Header | C functions | All declaration/support entries |
|---|---:|---:|
| `raylib.h` | 600 | 1,037 |
| `raymath.h` | 146 | 254 |
| `rlgl.h` | 163 | 403 |
| `rcamera.h` | 12 | 35 |
| `rgestures.h` | 10 | 39 |
| `config.h` | 0 | 116 |
| **Total** | **931** | **1,884** |

The 931 C declarations represent 923 unique function names; eight gesture
functions are declared in both `raylib.h` and `rgestures.h`. In addition, raymath
exposes 60 C++ overloads and 19 constexpr constants. Supporting entries include
types, enum values, aliases, callbacks, macros and configuration controls.
Conditional variants are retained under the same stable declaration ID.

The initial inventory increment's baseline was **21 partial core functions, seven
partial type declarations, one blocked core function and zero complete items**.
Remaining core functions at that baseline: 578 not started. These are status counts, not a full
parity percentage. The 31 work packages and target matrix are in the
[dashboard](PROGRESS.md); source and verification policy is in
[API-TRACKING.md](API-TRACKING.md).

## Proof performed

- `python3 tools/api_plan.py check --clang-audit --raylib-source PATH`:
  exact source re-extraction matches the complete committed catalog. Independent
  Clang ASTs match all C function names and exact C++ overload signatures.
  Active typedefs/enumerators are present, and C++ constants match. A separate
  line audit accounts for public typedef/define/constexpr alternatives,
  including ones inactive on this host.
- `python3 -m unittest discover -s tests -v`: seven test methods pass. The
  progression tests cover conditional source/line preservation, overloads and
  implementation boundaries, mapping migration, prerequisite order, evidence-only
  progression deltas, invalid IDs/dependencies/cycles, stale/source-drift failures
  and unsupported completion claims.
- `python3 tools/conformance.py`: CPU-1, CPU-2 and JavaScript match the actual
  raylib reference for all 53 scenarios / 15,733 pixels per lane. Ownership and
  transform contracts, the proof, and all three PPM examples pass. The runtime
  report now carries ledger-derived progression and hashes its planning inputs.
- `python3 tools/check_project.py`: generated artifacts, source boundary,
  metadata and recursive documentation links pass.
- `python3 -m compileall -q tools tests` and `git diff --check`: pass.

The support-line audit exposed incorrect source links for five constexpr
declarations following masked function bodies. Extraction now computes those
offsets from the masked view; the existing extraction test includes a multiline
function followed by a constant. Inventory counts were unaffected.

Regression scan: 75 callers checked, 27 assertions checked, 1 flagged/fixed.
The caller count covers 72 direct Python references plus the project-check,
conformance and workflow CLI integrations; the fixed finding is the source-link
offset issue above. Generated consumers and documentation links were also checked.

## Acceptance and limits

| Requirement | Result |
|---|---|
| Complete pinned public-header/support inventory and actionable mapping | Pass |
| Preserve existing 21 partial mappings and explicit remaining work | Pass |
| Reject stale outputs, invalid dependencies and unsupported completion | Pass |
| Derive progression dashboard, deltas and conformance summaries from the ledger | Pass locally |
| Hosted execution of the new inventory gates | Pass on both hosts for [b73c97a](evidence/hosted-b73c97a.json) |

The workflow changes add the source/Clang audit to both hosted conformance
jobs; their subsequent successful execution is recorded in the linked hosted evidence.
GPU/compiler regression
suites were not rerun for this metadata/tooling increment; earlier library and
compiler evidence remains in [VERIFICATION.md](VERIFICATION.md). This inventory
audit establishes declaration accounting, not runtime parity, exhaustive semantic
contracts, or support on untested platforms. Detailed per-API acceptance and
OS/device/backend combinations must be established during each implementation
step before completion can be claimed.
