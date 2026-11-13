# Architecture

How Jonlib is put together, and how a claim like "this function matches
raylib" is produced and checked. Each section links to the page that holds
the details; [INDEX.md](INDEX.md) maps every page.

## Two halves: the library and the evidence

The repository has two parts that never mix:

| Part | Language | What it is |
|---|---|---|
| The library | Bend 2 (`*.bend`, `src/`) | Everything a Jonlib program runs. No C, no FFI to raylib. |
| The evidence | Python + C (`tools/`, `tests/`) | Builds the pinned, unmodified raylib, runs it natively, and compares Jonlib's results with it. |

raylib is never linked into a Jonlib program. It is the *reference*: an
independent oracle whose outputs Jonlib must reproduce. `tools/check_project.py`
enforces the boundary (C belongs to the reference side only).

## The library

| File | Lines | Role |
|---|---|---|
| [`jonlib.bend`](../jonlib.bend) | ~20k | The core: raylib.h's surface (shapes, images, textures, text, models, audio, input, files, frames), with rlgl, rcamera and rgestures inside it. |
| [`jonmath.bend`](../jonmath.bend) | ~2k | raymath's surface and the shared Vector2/3/4, Matrix and Quaternion types. |
| [`jongui.bend`](../jongui.bend), [`joneasings.bend`](../joneasings.bend), [`jonlights.bend`](../jonlights.bend) | | raygui, reasings.h and rlights.h. |
| [`jonlgl.bend`](../jonlgl.bend), [`joncamera.bend`](../joncamera.bend), [`jongestures.bend`](../jongestures.bend) | | rlgl.h, rcamera.h and rgestures.h as their own modules, generated over Jonlib ([MODULES.md](MODULES.md)). |
| [`src/`](../src) | 128 files | Internal modules: codecs (PNG, JPEG, GIF, QOI, MP3, Vorbis…), DEFLATE, the software renderer (`rlgl`, `frame`, `present`), the audio mixer, float kernels (`fma`, `binary64_*`, `sincosf`…). |
| [`src/lgpl/`](../src/lgpl) | | glibc-derived math (LGPL-2.1+), isolated from the zlib code. |

Names follow `ray<suffix>` → `jon<suffix>`; upstream names stay in reference
IDs and notices.

### Design decisions that shape every API

- **Explicit state.** raylib's globals (the core state, rlgl's state, the
  audio device, the trace log, file callbacks) are values. Operations take
  them and return them updated ([API.md](API.md)).
- **Affine ownership.** A `Surface`, `Wave`, `Model`… is consumed by the call
  that changes it and returned to the caller; `+` parameters are borrowed.
  Bend's checker enforces it. Every ledger entry states its ownership
  contract, and a probe restates it (see *ownership* below).
- **Headless by default.** Windows, input, frames and audio are values a
  program threads through its loop; a memory platform renders frames, and a
  scripted clock drives time ([DRIVER.md](DRIVER.md), [FRAME.md](FRAME.md)).
- **Numerical profiles.** Where raylib's result depends on the host, the API
  takes the host's behavior as a value instead of guessing:
  - `M.Libm`: which C math library rounds `sinf`, `atan2f`, `powf`…
    (`AppleLibm`, `Glibc239Libm`, `Glibc241Libm`; [ANGLES.md](ANGLES.md)).
  - `M.Contraction`: whether the build fuses `a*b + c`
    (`Uncontracted`, `Fused`; [MATH.md](MATH.md#floating-point-contract-and-evidence)).
  The plain name is the default profile; `_for(profile, …)` selects another.
- **Reference arithmetic order.** Float code follows raylib's evaluation order
  exactly; a balanced or reassociated sum would round differently.

## Where it runs: the lanes

The pinned Bend compiler (plus a declared four-patch overlay,
[patches/README.md](../patches/README.md)) turns one program into:

| Lane | Meaning |
|---|---|
| `cpu-1` | native code, one thread |
| `cpu-2` | native code, two threads |
| `javascript` | Bend's JavaScript backend |
| `gpu` | forced Metal on Apple hardware (`--gpu`; local only) |

Every comparison runs on all CI lanes, and must give the same bits on each.
Hosted CI cannot run Metal, so Metal results are recorded as local
witnesses ([METAL-WITNESSES.md](METAL-WITNESSES.md)).

## How a probe proves parity

A *probe* (`tools/*_probe.py`, built on [`tools/probekit.py`](../tools/probekit.py))
is one family's comparison:

1. **Cases.** A corpus of inputs: exceptional values (signed zeros,
   subnormals, infinities, NaNs), boundaries, and seeded random inputs.
2. **Reference.** A C program that includes the pinned raylib source, run
   natively, prints each case's exact result bits.
3. **Candidate.** A generated Bend program calls the Jonlib API on the same
   cases, compiled for every lane.
4. **Compare.** Results must be equal bit for bit. The only normalization is
   for what the C standard leaves unspecified (for example the sign of a
   freshly created NaN, [`tools/quiet_nan.py`](../tools/quiet_nan.py)).
   Tolerances are not used to hide differences.

Ownership is restated in the probe: its Bend program calls the API through
`*_owned` defs that copy the library's signature (borrows included), so the
affine checker enforces the documented contract on every compared call.

The `conformance` gate ([`tools/conformance.py`](../tools/conformance.py))
is the main differential corpus over
[`tests/fixtures/images.json`](../tests/fixtures/images.json); the examples
gates replay all 223 raylib examples frame by frame ([EXAMPLES.md](EXAMPLES.md)).

## Gates

[`tools/gates.json`](../tools/gates.json) lists every gate (232 today): an id,
the command, the hosts (`linux`, `macos`) and whether it is diagnostic (a
recorded gap, never a pass). [`tools/run_gates.py`](../tools/run_gates.py)
runs them locally, by id or by shard; CI runs the same file
([CI.md](CI.md)). [VERIFICATION.md](VERIFICATION.md) says what a pass does
and does not establish.

## The ledger: from evidence to status

Every public declaration of raylib 6.2's headers (1,906 entries) has a record
in [`api/progress.json`](../api/progress.json): its Jonlib mapping, scope,
gaps and evidence. Six gates per entry: availability, behavior, ownership,
integration, targets, performance.

```
api/progress.json ──► tools/gate_evidence.py --apply ──► derived gates
        │                       (behavior, ownership, integration, performance)
        ▼
tools/api_plan.py build ──► api/ledger.json, api/summary.json,
                            docs/PROGRESS.md, docs/api/*.md
```

- `gate_evidence.py` derives four gates from the record and the repository: a
  gate cannot be marked verified by editing JSON. Behavior needs a parity probe
  that covers the symbol and no open behavior gap; ownership needs an ownership
  def in that probe plus a stated contract.
- `api_plan.py check` rejects a record whose stored gates disagree.
- `complete` needs all six gates verified on Linux and macOS, so nothing is
  complete yet; the **Phase 1 exit measure** tracks the first delivery phase
  ([API-TRACKING.md](API-TRACKING.md), [PROGRESS.md](PROGRESS.md)).

## Proofs

[`LAWS.bend`](../LAWS.bend) states durable properties; [`PROOF.bend`](../PROOF.bend)
is the entry point the pinned checker runs (`--check-only` before every
implementation commit). Proofs establish the stated laws; probes establish
behavior on their corpora.

## Toolchain

[`toolchain.json`](../toolchain.json) pins Bend (revision, overlay patch
hashes, resulting file hashes), raylib 6.2 and Bun. Verification never
installs, updates or patches a toolchain as a side effect.

## Performance

Jonlib is correctness-first and single-threaded today. Measurements against
raylib are in [PERFORMANCE.md](PERFORMANCE.md) (examples, audio) and
[FRAME.md](FRAME.md#performance) (rendering alone). No performance budget is
set.
