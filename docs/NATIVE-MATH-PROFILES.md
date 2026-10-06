# Native math profile diagnosis

`tools/native_math_profile_probe.py` separates compiler folding, compiler-lowered
runtime operations, native libm calls, and the existing explicit Jonmath profiles.
It builds **native C only**. It does not build Bend, alter library profiles, update
expected results, change tolerances, or participate in the canonical conformance
gate. A completed diagnostic is **not a parity pass**.

## Run against existing tools

```sh
python3 tools/native_math_profile_probe.py \
  --raylib-source "$RAYLIB_SOURCE" \
  --clang clang \
  --gcc gcc
```

`--raylib-source` is required and should identify the existing raylib source at
the revision in `toolchain.json`. Nothing is downloaded, installed, or checked
out. A Git checkout must have the pinned revision and an unchanged `src/raymath.h`.
An extracted source archive may be used: its header is hashed, but the report
leaves `observed_git_revision` null rather than claiming Git verification.
`--gcc` is optional; omitting it runs only the four Clang modes. Absolute compiler
paths work. `--timeout` bounds each command separately (default: 120 seconds).

The default output directory is `.build/native-profile-diagnostic`; use
`--output PATH` for a separate run. Its files include:

- `results.json`: completion/error state, compiler versions, host/libc,
  rounding mode, native-library paths, exact build commands, source/header/input
  hashes, all scalar/vector observations, and every angle difference
- `diagnostic.c`: the reproducible generated C source
- `<mode>.tsv`: all observed bits, including every angle input/output
- `<mode>.version.log` and `<mode>.compile.log`: tool and build diagnostics

The report is initialized before reading sources and updated after each mode.
A failed mode does not erase preceding results or prevent other modes from
running. A setup/build/run/parse failure exits nonzero and retains
`diagnostic_completed: false` with the error. Successful data collection exits
zero even when profiles differ. `parity_established` is always false, and
`not_canonical_gate` is always true. Interrupted execution leaves the last
persisted partial report. Check these fields rather than interpreting process
success as conformance.

The parser requires each expected observation ID exactly once and its exact
scalar/vector component count. It rejects renamed, duplicate, missing, extra,
or malformed observations and samples. Host fields are mandatory for the
recorded platform: Linux/Darwin require absolute native-library paths; a
recorded glibc host requires the matching runtime glibc version. Duplicate,
unknown, empty host fields, empty compiler identity, and a rounding mode other
than `FE_TONEAREST` fail the diagnostic rather than yielding partial provenance.

Python-only regression tests cover successful completion, stale-result
invalidation, partial failures, provenance, timeout logs, and malformed output:

```sh
python3 -m unittest discover -s tests -p test_native_math_profile.py -v
```

They mock all subprocess execution and do not require a compiler.

## What is compared

All builds use C11 and `-ffp-contract=off`:

| Mode | Additional flags |
| --- | --- |
| `clang-o0` | `-O0` |
| `clang-o2` | `-O2` |
| `clang-o2-native` | `-O2 -fno-builtin-atan2f -fno-builtin-fminf -fno-builtin-fmaxf` |
| `clang-o2-strict` | `-O2 -ffp-model=strict` |
| `gcc-o2` (optional) | `-O2` |
| `gcc-o2-native` (optional) | `-O2 -fno-builtin-atan2f -fno-builtin-fminf -fno-builtin-fmaxf` |

Within each build, literal calls, calls with volatile input values, and calls
through volatile native function pointers are separate observations. Volatile
inputs prevent constant propagation; they do **not** prevent builtin lowering.
The native-pointer path prevents replacing the target call with a known builtin.
The native-only flags are diagnostic variants, not proposed changes to the
canonical oracle.

The program imports the existing `GNU_CONTROL` and deterministic 1,086-sample
corpus from `tools/angle_probe.py`. The generated source retains the Sun license
notice; see `LICENSES/sun-math.txt`. It also reads the unchanged six relevant
fixture scenarios from `tests/fixtures/images.json`, calls the pinned raymath
header with literal and volatile vector inputs, and evaluates small C models of
the **documented** Jonmath zero-tie contracts. Those C models are not Bend
execution evidence. No Apple angle implementation is evaluated by this tool.

## Recorded Linux x86-64 result

The local 2026-10-02 report at
`.build/native-profile-diagnostic/results.json` records:

- Debian Clang 19.1.7 (3+b1), GCC 14.2.0-19, glibc 2.41
- `FE_TONEAREST` and `/lib/x86_64-linux-gnu/libm.so.6`
- Raymath header SHA-256
  `2b8b88f5b3f748e3cf8bdbfb8b7da23a76c755dc40f9c6e455bfc09b3669d028`
- Angle-input SHA-256
  `e97e8ae61b081cbf56aaedf449be5e40795523ee73deba21649e297d20d499fb`,
  matching the corpus in `docs/evidence/vector-angle-profiles.json`
- All six modes completed, each with **178/1,086** Sun-control/native angle
  differences: seven boundary samples and 171 seeded random samples, each one
  representable binary32 step apart
- Zero differences between direct volatile-input `atan2f` and volatile-pointer
  native `atan2f` over that corpus

A compact checked-in [host-profile evidence record](evidence/native-math-host-profile.json)
retains the final source/input/header hashes, compiler flags and per-mode counts.
The reproducible diagnostic retains the complete observations locally.

The final run used a Git checkout at the pinned revision
`dbc56a87da87d973a9c5baa4e7438a9d20121d28` with an unchanged `src/raymath.h`;
`observed_git_revision` and the header hash are recorded. These are host-specific
observations, not assertions about every glibc release, compiler,
architecture, optimization context, or floating-point rounding mode.

## Three observable signed-zero contracts

For mixed-sign zero operands, the observed scalar contracts are:

| Operation and operands | Literal folding | Ordinary volatile-input builtin | Native glibc pointer |
| --- | --- | --- | --- |
| `fminf(+0, -0)` | `80000000` | `00000000` | `80000000` |
| `fminf(-0, +0)` | `80000000` | `80000000` | `00000000` |
| `fmaxf(+0, -0)` | `00000000` | `00000000` | `80000000` |
| `fmaxf(-0, +0)` | `00000000` | `80000000` | `00000000` |

Thus literal folding selects negative zero for minima and positive zero for
maxima; ordinary runtime builtin lowering retains the first operand in these
observations; the native glibc implementation retains the second operand. All
three preserve the common sign when both zero operands have the same sign.
The ordinary Clang modes and GCC `-O2` show the first two columns. Strict Clang
and the no-builtin variants use the native results instead.

`jonmath.bend`'s `Vector2.clamp.minimum/maximum` helpers deliberately implement
first-operand zero ties for `GnuGradient{}` and sign-selecting ties for
`AccurateGradient{}`. Vector2/3/4 extrema and component clamps share those
helpers. See `docs/MATH.md`. Consequently:

- The existing GNU model matches the ordinary volatile-input builtin observations
- The existing accurate zero model matches the literal-folded observations
- Neither existing zero model matches all native glibc mixed-zero calls

These observations do not establish that glibc 2.41 introduced the native
zero-tie behavior. The difference is already demonstrated by changing only the
call path on this one host. LLVM 19 explicitly permits either equal operand for
`llvm.minnum`/`llvm.maxnum`; it does not give a portable signed-zero tie order.
The generated Clang IR uses these intrinsics for runtime builtin calls.
[LLVM 19 language reference](https://releases.llvm.org/19.1.0/docs/LangRef.html#llvm-minnum-intrinsic).

### Mapping the five recorded fixture failures

The original `environment-lanes.json` reports only the first failing pixel per
scenario. The native diagnostic reproduces those first cells in literal raymath
calls and the declared GNU C model:

| Scenario / pixel | Literal raymath | GNU zero model |
| --- | --- | --- |
| `vector4-extrema` / 3 | `80000000` | `00000000` |
| `vector3-extrema` / 6 | `80000000` | `00000000` |
| `vector3-clamp-components` / 3 | `00000000` | `80000000` |
| `vector2-extrema` / 4 | `80000000` | `00000000` |
| `vector2-clamp-components` / 4 | `00000000` | `80000000` |

The literal and volatile raymath vectors retain the same API and inputs. For
example, `Vector4Min`'s zero X/W components are `-0,-0` with folded literals,
`-0,+0` with ordinary volatile inputs, and `+0,-0` through native libm. This
explains why disabling all three builtins changes the first Vector4 failure
from pixel 3 to pixel 0 rather than making the GNU model match.

## Near-half-pi angle and the wider GNU/native gap

For `atan2f(1.0f, -1e-20f)`, the exact input bits are `3f800000,9e3ce508`:

- Literal, volatile-input, and native-pointer glibc calls: `3fc90fdb`
- Imported Sun control, both literal and runtime: `3fc90fda`
- The recorded Jonlib GNU lane: `3fc90fda`

Raymath's `Vector2Angle((1,0),(-1e-20,1))` produces the same native value. This
persists at `-O0`, with builtin suppression, and under strict floating-point
compilation, so disabling constant folding cannot resolve it.

The control's huge-ratio branch rounds `half + 0.5*low` to `3fc90fdb`; the
negative-X correction then rounds `z-low` to `3fc90fdc`, and `pi-(z-low)` becomes
`3fc90fda`. The corresponding operations are explicit in
`src/angle.bend`'s `gnu.ratio` and `gnu.quadrant`. The observed Jonlib result
therefore agrees with the declared Sun-derived algorithm at this input.

The glibc 2.41 release introduced CORE-MATH's correctly rounded `atan2f` and
`atanf`, among other binary32 functions. This is a documented native
implementation change, consistent with the measured broad separation from the
older Sun control; the diagnostic does not infer it solely from one endpoint.
[glibc 2.41 release announcement](https://sourceware.org/pipermail/libc-announce/2025/000045.html).

## Interpretation and limits

The six recorded scenario failures have two distinct explanations: compiler
folding/lowering changes the zero-tie behavior of the C reference, and native
glibc 2.41's angle results differ from the declared Sun-derived profile. The
same recorded failures across CPU-1, CPU-2 and JavaScript do not isolate a new
backend-specific Bend defect. This diagnostic independently accounts for those
observed bits, but does not replace executing Bend against either control.

Selecting `GnuGradient{}` merely because the host reports Linux/glibc is broader
than the evidence supports. Conversely, selecting the accurate zero-tie model
would only address literal extrema here; it would not establish a glibc 2.41
angle profile or native zero-tie parity. Do not repair the gate by silently
switching profiles, suppressing builtins, replacing expected bits, or accepting
one-step differences. Any new supported profile needs an explicit contract and
native/Bend evidence across its declared inputs and targets. Existing canonical
gates, profiles and exact comparisons remain unchanged.

## Explicit qualification of literal extrema

The conformance harness now qualifies extrema independently of gradient/angle
profile selection. When Vector2/3/4 min/max or Vector2/3 component clamp appears,
`tools/extrema_reference.py` builds a fresh, independent native control corpus
before emitting any Bend candidate. It does not inspect conformance-fixture
outcomes or try Bend profiles to find one that passes.

The fixed corpus exhausts `{-1,-0,+0,+1}` ordered pairs and clamp triples in
uniform vectors and each isolated component among finite mixed-lane sentinels:
832 vector observations / 2,368 result words across all eight APIs. Predeclared
bit truth tables encode only the existing accurate and GNU zero contracts.
Exactly one common profile must match every observation. Second-operand ties,
mixed/unknown/ambiguous behavior, missing components and malformed output fail
closed. The generator rejects relevant queries without an explicit qualified
selection; there is no libc-based fallback for them.

Controls run through the unchanged canonical fixture validator, C generator,
decimal literal formatter, static-inline raymath calls, image observations and
parser. They use the exact canonical compiler command, including `-O2` and
`-fno-builtin-atan2f`; no additional min/max flags are introduced. The report
records compiler identity, commands, header/library/control/source hashes,
complete native observations and the selected profile. Every run invalidates
stale success and removes its stale generated executable before compilation.

The selected contract is logged and passed explicitly only to the eight extrema
APIs. Gradients, rotations, angles, scalar clamp and magnitude clamps retain their
prior selection. Jonmath, all canonical native fixture inputs and expected
outputs, and the exact comparator remain unchanged. The native-pointer/runtime
contexts diagnosed above remain different, deliberately unqualified contexts.

The report is `.build/extrema-reference/results.json`; `qualified: true` means
only that one declared contract matches the controlled native reference context.
`parity_established` remains false. A separate preflight cannot prove optimizer
behavior in every surrounding translation unit, so the unchanged full native/
Bend bitwise comparison is still the acceptance authority. This qualification
does not establish a new glibc 2.41 angle profile or an overall conformance pass.

Metal prefix diagnostics also qualify freshly when their prefix contains these
queries and then require the pinned `--raylib-source` checkout. Image-only
callers need no extrema qualification. Qualification on one host is not evidence
for another compiler, architecture or execution target.

The [checked-in qualification and lane evidence](evidence/qualified-literal-extrema.json)
records the Clang 19 Linux result: the accurate contract uniquely matches all
2,368 native control words, while the GNU contract differs on 76. With that
explicit selection, the five original extrema/clamp scenario failures disappear
on CPU one-thread, CPU two-thread and JavaScript. Each lane matches 260 of the
unchanged 261 scenarios; the angle scenario remains an exact mismatch and the
canonical gate still fails. These counts describe this corpus, not library-wide
parity or an API-completion percentage.

The remaining angle work is staged in [ANGLE-PLAN.md](ANGLES.md), including
the immutable MIT algorithm source, reusable binary64 arithmetic prerequisites,
a separate angle reference type and exact CPU/JS/device qualification gates.

## Standalone native angle qualification

The independently frozen [native angle qualification gate](ANGLES.md)
now verifies 76 scalar controls, 205 canonical/runtime wrapper controls and
1,654 ordered intermediate words before any future angle-candidate generation.
It uniquely observes the modern contract on the recorded Linux host; historical
source contracts are not newly host-qualified. Public routing, old algorithms,
canonical fixtures and the final-angle-only wrapper validation gap are unchanged.
