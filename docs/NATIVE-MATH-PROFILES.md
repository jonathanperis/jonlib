# Native math profiles

raymath's angle and extrema functions call C library `atan2f`, `fminf` and
`fmaxf`, whose last-bit and signed-zero behaviour depends on the C library, the
compiler and the call path. Jonmath therefore exposes explicit numerical
profiles, and the reference harness **selects** the profile that matches the
native reference instead of assuming one result is universal. Two tools are
involved:

| Tool | Role |
|---|---|
| `tools/native_profiles.py` | Used by `tools/conformance.py`: selects the host's `atan2f` angle profile and literal-extrema zero-tie profile from frozen controls. |
| `tools/native_math_profile_probe.py` | Diagnostic gate `native-math-profiles`: records how compiler folding, builtin lowering and native libm calls differ. Never a parity result. |

Angle profiles, their selection controls and the checked angle APIs are
described in [ANGLES.md](ANGLES.md); this page covers the extrema selection and
the diagnostic.

## Extrema zero-tie profiles

`Vector2/3/4.min_for`, `max_for` and `Vector2/3.clamp_for` take a
`Libm` that fixes the result for mixed-sign zero operands (see
[MATH.md](MATH.md)):

| Profile | `min` of `+0`/`-0` | `max` of `+0`/`-0` |
|---|---|---|
| `AppleLibm{}` | negative zero (sign OR) | positive zero (sign AND) |
| `Glibc239Libm{}` | first operand | first operand |

Same-sign zeros keep their common sign in both profiles. The convenience
`min`, `max` and `clamp` select `AppleLibm{}`.

### Selection (`native_profiles.extrema_profile`)

When the main corpus contains any of the eight extrema queries (Vector2/3/4
min and max, Vector2/3 component clamp), `tools/conformance.py` selects the
profile before emitting any Bend candidate:

- **Controls.** Every ordered pair (min/max) and triple (clamp) of
  `{-1, -0, +0, +1}`, both uniformly in all lanes and isolated in each lane among
  lane-distinct finite nonzero sentinels, for every vector width.
- **Native run.** The controls go through the unchanged canonical fixture
  validator, C generator, static-inline raymath calls and output parser, compiled
  with the canonical reference command (`clang -std=c11 -O2
  -fno-builtin-atan2f`, no extra min/max flags).
- **Expectations.** Fixed bit truth tables for each declared profile; clamp
  follows raymath's `min(upper, max(lower, value))` order.
- **Decision.** Exactly one profile must match every result word. Zero or
  several matches (second-operand ties, mixed or unknown behaviour, missing
  components) fail the run; there is no libc-based fallback.

The selection is recorded as `extrema_reference` (contract
`literal-vector-extrema-v1`) in the conformance report and passed explicitly to
those eight APIs only. Gradients, rotations, scalar clamp and magnitude clamps
keep the host-declared gradient profile (`AppleLibm{}` on Darwin,
`Glibc239Libm{}` on Linux/glibc; see [GRADIENTS.md](GRADIENTS.md)). A selection
names which existing contract the reference context follows; it is not evidence
for another compiler, architecture or call path, and the full native/Bend bitwise
comparison remains the acceptance authority.

## Observed reference behaviour

### Signed-zero ties depend on the call path

For mixed-sign zero operands, three different behaviours are observable from the
same C source on a glibc 2.41 host:

| Operation and operands | Literal folding | Volatile-input builtin | Native glibc pointer |
|---|---|---|---|
| `fminf(+0, -0)` | `80000000` | `00000000` | `80000000` |
| `fminf(-0, +0)` | `80000000` | `80000000` | `00000000` |
| `fmaxf(+0, -0)` | `00000000` | `00000000` | `80000000` |
| `fmaxf(-0, +0)` | `00000000` | `80000000` | `00000000` |

Literal folding gives negative zero for minima and positive zero for maxima
(the `AppleLibm{}` table); ordinary runtime builtin lowering keeps the
first operand (the `Glibc239Libm{}` table); the native glibc implementation keeps
the second operand, which matches **neither** declared profile. Ordinary Clang
and GCC `-O2` builds show the first two columns; strict Clang
(`-ffp-model=strict`) and the `-fno-builtin-fminf/-fmaxf` variants call the
native function. LLVM permits either equal operand for
[`llvm.minnum`/`llvm.maxnum`](https://releases.llvm.org/19.1.0/docs/LangRef.html#llvm-minnum-intrinsic),
so there is no portable tie order. For example, `Vector4Min`'s zero X/W
components are `-0,-0` with folded literals, `-0,+0` with volatile inputs and
`+0,-0` through native libm. This is why extrema are selected from the canonical
literal reference context rather than inferred from the host.

### Native atan2f versus the Sun control

For `atan2f(1.0f, -1e-20f)` (input bits `3f800000, 9e3ce508`):

- Literal, volatile-input and native-pointer glibc 2.41 calls: `3fc90fdb`
- The Sun float control (`GNU_CONTROL` in `tools/angle_probe.py`, licence in
  [LICENSES/sun-math.txt](../LICENSES/sun-math.txt)) and Jonlib's
  `Glibc239Libm{}` kernel: `3fc90fda`

Raymath's `Vector2Angle((1,0), (-1e-20,1))` produces the native value, at `-O0`,
with builtins suppressed and under strict floating point alike, so it is not a
constant-folding effect. In the Sun algorithm the huge-ratio branch rounds
`half + 0.5*low` to `3fc90fdb`, the negative-X correction rounds `z-low` to
`3fc90fdc`, and `pi-(z-low)` becomes `3fc90fda`; `src/angle.bend` performs the
same operations in `gnu.ratio` and `gnu.quadrant`. glibc 2.41 replaced the Sun
code with CORE-MATH's correctly rounded `atan2f`
([release announcement](https://sourceware.org/pipermail/libc-announce/2025/000045.html)),
which is why it is a separate profile, `Glibc241Libm{}`.

## Diagnostic gate `native-math-profiles`

`tools/native_math_profile_probe.py` builds **native C only** (no Bend), alters
no profile, expected value or tolerance, and records `diagnostic: true` in its
results. A completed run is not a parity pass.

```sh
python3 tools/native_math_profile_probe.py --raylib-source "$RAYLIB_SOURCE" --clang clang [--gcc gcc]
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only native-math-profiles
```

`--raylib-source` must be the pinned checkout from `toolchain.json` (checked by
`probekit`). `--clang` defaults to `clang`; `--gcc` is optional and adds two GCC
modes. All builds use `-std=c11 … -ffp-contract=off`:

| Mode | Additional flags |
|---|---|
| `clang-o0` | `-O0` |
| `clang-o2` | `-O2` |
| `clang-o2-native` | `-O2 -fno-builtin-atan2f -fno-builtin-fminf -fno-builtin-fmaxf` |
| `clang-o2-strict` | `-O2 -ffp-model=strict` |
| `gcc-o2` (with `--gcc`) | `-O2` |
| `gcc-o2-native` (with `--gcc`) | `-O2 -fno-builtin-atan2f -fno-builtin-fminf -fno-builtin-fmaxf` |

Each mode records, as separate observations: literal calls, calls with volatile
inputs (no constant propagation, but builtin lowering still possible) and calls
through volatile native function pointers (the actual library function) for the
mixed-zero `fminf`/`fmaxf` pairs and the near-half-pi `atan2f` endpoints; the Sun
control at those endpoints and its intermediate steps; literal and volatile
raymath calls for the six fixture scenarios `vector2-angle-profiles`,
`vector2/3/4-extrema` and `vector2/3-clamp-components` of
`tests/fixtures/images.json`; C models of the two declared zero-tie profiles
(diagnostics, not Bend execution); and native, Sun and direct `atan2f` bits for
the deterministic `tools/angle_probe.py` sample corpus. Host fields (rounding mode,
glibc version, absolute library paths for `atan2f`/`fminf`/`fmaxf`) are
mandatory; a rounding mode other than `FE_TONEAREST`, missing, duplicate,
renamed or malformed observations fail the run.

Results are written to `.build/native-math-profile-probe/results.json` (per-mode
flags, compiler version, every observation and the native/Sun angle
differences). Parser and host-field validation are unit-tested in
`tests/test_native_math_profile.py`, which mocks all native execution.

## Rules and known gaps

- Do not repair a mismatch by switching profiles, suppressing builtins,
  replacing expected bits or accepting one-step differences. A new profile needs
  an explicit contract and native/Bend evidence across its declared inputs.
- Native glibc pointer-call zero ties (second operand) have no declared profile;
  contexts that call the library function directly are not covered.
- The gradient/rotation profile is still declared per host family, not selected
  from native controls; other host families need their own verified declaration.
