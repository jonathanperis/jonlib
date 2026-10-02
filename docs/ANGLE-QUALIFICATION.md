# Independent native angle qualification

`tools/angle_reference.py` is a **standalone, native-only qualification gate**.
It selects one versioned numerical behavior contract from independently frozen
controls. It does not run Bend, introduce `Angle.Reference`, change public
Apple/GNU algorithms or defaults, route canonical queries, alter fixtures or
change exact comparisons. The unchanged canonical corpus still has the recorded
260/261 result: the remaining native-angle mismatch is unresolved publicly.

A successful qualification means **this fixed corpus matches one contract in the
recorded native contexts**. It is neither a proof for all input pairs nor a claim
that the installed binary has a particular source lineage. Historical source
evaluation is not qualification of a new Apple or glibc 2.39 host.

## Frozen controls and independent derivation

The versioned source of expectations is
[`angle_qualification_v1.json`](../tools/reference/angle_qualification_v1.json).
Its SHA-256 is pinned in the gate. It contains every stable ID, exact raw F32
input word, per-profile expected word, source URL/hash, derivation family, and
ordered wrapper intermediate word. No expectation comes from the current host's
`atan2f`, a Bend candidate, or conformance fixtures. There is no random search,
fixture-fitting, one-ULP allowance, or candidate trial to find a passing profile.

The independent contracts are:

- `Apple2007AngleRn`: the July 2007 Eric Postpischil Intel assembly at Apple Libm
  commit `17a5f9daa3f5679f7536b26f133b40cc078753c3`, source SHA-256
  `de9517cbc7a238328a8e5696ffaa37a6cc658a6ca0e73153c9dc76f0785909db`
- `Sun239AngleRn`: the Sun float atan/atan2 source at glibc 2.39 commit
  `ef321e23c20eebc6d6fb4044425c00e6df27b05f`; the exact two files, hashes and
  permissive Sun notices are retained under `tools/reference/angle_sources/`
- `Glibc241AngleRn`: the unmodified MIT source at glibc 2.41 commit
  `74f59e9271cbb4071671e5a474e7d4f1622b186f`, SHA-256
  `96f9c81b6e870c256cc0757f6d88f5290ed35db8d5b640b9e757d6feca96ae38`

Apple's inspected file contains authorship but no license grant; a covering
repository license was not verified. This slice therefore retains its immutable
URL, hash, independently derived numerical facts and source-evaluation evidence,
without distributing the Apple source or its assembly adaptation. The existing
library implementation is unchanged. Sun/MIT originals retain their full notices.

### Two independent discriminators

For `atan2f(y,x)` with `y=00000000`, `x=c0000000` (+0, -2):

- Apple returns `40490fda`; Sun and modern return `40490fdb`
- Apple's negative-axis guard uses `AlmostpPi=3.1415924`, which narrows to the
  lower F32 representative; Sun's F32 pi and modern's compensated F64 pi narrow
  to the upper representative
- Negative Y zero gives `c0490fda` versus `c0490fdb`

For `y=3f000000`, `x=9c000000` (0.5, -2^-71):

- Apple and modern return `3fc90fdb`; Sun returns `3fc90fda`
- Apple/modern reduce a 2^-70 term around binary64 half-pi and narrow upward
- Sun's exponent distance is 70. Its `k>60` shortcut first rounds
  `half+0.5*low` to `3fc90fdb`; the negative-X correction rounds `z-low` to
  `3fc90fdc`, then `pi-(z-low)` to `3fc90fda`
- Negative Y gives `bfc90fdb` versus `bfc90fda`

The 76 scalar controls add common power-of-two scales {-8,0,+8}, both Y signs,
both X signs, axes, all signed-zero origins, equal magnitudes, and two fixed
three-neighbor guard families. For the Apple 2^-22 guard, Y words
`347fffff,34800000,34800001` over |X|=1 straddle the guard: positive-X results
round exactly to Y and negative-X results are `40490fda` for all three sources.
For the Sun k>60 guard, Y=0.5 and |X| words `207fffff,20800000,20800001` give
k=61,61,60. The shortcut and saturated-atan paths both reconstruct the same
profile-specific half-pi words. Negative Y toggles the final sign bit.

An independent reviewer checked all scalar words against the exact Apple
assembly (ELF section/alignment syntax adaptation only), exact Sun originals and
unmodified modern source. The evaluation linked no host libm math functions;
explicit modern FMA lowered to hardware FMA. These are **historical source
checks**, separate from the live process qualification below. Complete numerical
observations and source/command hashes are retained in
[the derivation record](evidence/angle-qualification-derivation.json).

### Ordered wrapper arithmetic

There are 205 independent wrapper controls: 77 `Vector2Angle`, 76
`Vector2LineAngle`, and 52 `Vector3Angle`. Their 1,654 ordered intermediate words
are frozen independently with exact rational RN-even arithmetic. The independent
[`angle_manifest_audit.py`](../tools/angle_manifest_audit.py) uses a separate
binary-search rational rounding implementation to check every word before native
builds. Every selected V3 square root is an exact power of two or positive zero.

Simple bases embed the scalar controls, but the inputs are **not assumed** to
survive wrapper arithmetic unchanged. For example, with `(1,+0)` as the left
V2 vector and negative finite X, either sign of Y zero produces positive-zero
determinant: `-0 - -0` is +0 in RN. V3 cross length removes the Y sign, and its
extra dot-product add collapses all signed-zero origins to +0. Line-angle
endpoint subtraction preserves the chosen signed zeros and the final unary
negation flips the output sign bit. Every effective atan2 pair is recorded.

An additional cancellation control uses V2 left `(3f800001,3f800000)` and right
`(3f800000,3f7ffffe)`. The exact first determinant product is `1-2^-46`, but the
ordered F32 product rounds to 1 before subtracting 1. Thus det=+0, dot=2 and
angle=+0. A contracted product-minus-one would differ. Both canonical and
volatile-input original-raymath contexts preserve canonical `FP_CONTRACT OFF`
before the header and the unchanged compiler flags.

## Separate native evidence contexts

Every invocation freshly compiles and runs:

1. The independently compiled unmodified modern source, validating its intended
   frozen signature only. Its output never identifies installed libm
2. Actual installed `atan2f` through a volatile function pointer with exact
   bit-constructed scalar inputs
3. The unchanged canonical `cases_from`, `c_source`, decimal formatter,
   static-inline raymath calls, image observation and parser with the frozen
   wrapper controls and exact flags `clang -std=c11 -O2 -fno-builtin-atan2f`
4. Volatile-input original-raymath wrappers with the same flags and lexical
   contraction pragma, required to agree with canonical wrapper observations
5. A separately labelled source-order intermediate mirror, required to match
   every frozen intermediate word

The mirror is not instrumentation of hidden optimizer temporaries in canonical
calls. Its diagnostic role is explicit. The original canonical C bytes are
retained and unchanged; a metadata object is linked as a separate translation
unit without LTO. This preserves the numeric body/flags, but a qualification
translation unit cannot prove behavior in every larger surrounding program.
The full canonical native/Bend comparison remains the parity authority.
Builtin-folded literal atan2 behavior is not required; known Apple literal/native
pi differences must not disqualify its no-builtin numerical contract.

The pointer and all wrapper results must identify exactly one common profile.
Unknown, mixed, ambiguous, wrong-sign and one-ULP differences reject. An explicit
`--profile` can restrict acceptance but cannot bypass any control or metadata
check. An old report is never consumed as authorization to generate a candidate.

## Process provenance and supported metadata profile

A separately linked read-only constructor and destructor report, on stderr, the
actual initial/final process state. Numeric stdout remains separately parsed.
Neither helper sets or normalizes the floating-point environment. Required data:

- IEEE binary32/binary64 storage and runtime layout, no excess evaluation,
  little endian, observed `FE_TONEAREST`
- x86-64 MXCSR FTZ/DAZ/rounding and x87 control, or AArch64 FPCR controls
- Actual glibc runtime version and `atan2f` volatile-pointer equality to
  `dlsym(RTLD_DEFAULT,"atan2f")`
- Resolved loaded-object path, realpath, stat identity and in-memory GNU build ID;
  Python verifies the same file's stat, SHA-256 and ELF build ID after the process
- Compiler absolute path, realpath, executable hash, full version, target and all
  compile flags; pinned raylib headers, archive hash, Git revision/source status
- Explicit observations of only `LD_PRELOAD`, `LD_LIBRARY_PATH`, `LD_AUDIT`,
  `LD_BIND_NOW`, `GLIBC_TUNABLES`, `LD_HWCAP_MASK`, `LD_ASSUME_KERNEL`

The current explicit metadata profile is **Linux glibc ELF runtime-image v1**
on x86-64/AArch64 with no listed loader overrides. Unknown/unreadable required
metadata or any other platform fails unsupported; it does not guess defaults or
infer a profile from an OS/version name. AArch64 has implemented checks but no
new host evidence in this slice. Darwin/Windows provenance is not implemented.

A successful `dpkg-query` inventory supplies the libc6 package record when one
exists. This runtime-image profile deliberately does **not** require package
membership: unpacked runtime images may have no package database entry. In that
case the report records `not-in-successful-dpkg-inventory`, a null package record,
and the independently observed runtime version/object identity. A missing query
tool or failed inventory is unsupported; no package version is invented. Package
metadata and runtime metadata have separate fields and meanings.

Initial/final contexts must agree except MXCSR exception status flags, which are
not an exception contract. All five processes must share stable controls and
loaded-object identity. Compiler/source/toolchain/generated artifact hashes are
revalidated after the final subprocess, with compiler path resolution rechecked.
The pinned source identity and loaded native library identity remain separate.

## Failure behavior and reproduction

```sh
source /path/to/existing/jonlib-toolchain/activate.sh
python3 tools/angle_manifest_audit.py
python3 tools/angle_reference.py --raylib-source "$RAYLIB_SOURCE" \
  --library .build/raylib/raylib/libraylib.a
python3 -m unittest discover -s tests -p test_angle_reference.py -v
```

Use the already built pinned raylib archive. Nothing is installed, downloaded,
checked out, or repaired by this gate. The default report and full command,
source, binary, stdout/stderr and observation artifacts are under
`.build/angle-reference/`. Commands are individually timeout-bounded. Use separate
`--build-dir` directories for concurrent runs; a shared output directory is a
serial-use interface. `--help` is informational and does not invalidate reports.

Before source reads/builds, results are persisted as unqualified with a null
selection and a fresh run ID/timestamp. CLI argument failures also invalidate the
chosen output report. Every admitted failure retains that state and diagnostics;
stale executables are removed before each compile, and a successful compiler
must produce a fresh nonempty artifact. Observation parsing rejects missing,
extra, reordered or duplicate IDs/keys, wrong shapes/types and altered words.
Tests spy on the eventual `qualify(); generate()` pattern: failure cannot schedule
candidate generation. No candidate execution exists in this standalone tool.

## Current result and remaining gap

On the recorded Linux x86-64 Clang 19.1.7/glibc 2.41 host, all controls uniquely
select `Glibc241AngleRn`. The [complete retained report](evidence/angle-qualification.json)
records all observations and provenance. The Sun and Apple contracts fail their
independent discriminator families as expected. Neither historical platform was
newly host-qualified. Independent review and regression results are recorded in
[the review record](evidence/angle-qualification-review.json).

The documented public wrapper domain requires normal/zero **intermediates**.
The existing canonical validator only checks the **final angle** for normal/zero
status. This pre-existing enforcement gap remains visible and unchanged; the
standalone controls do not close it or expand the domain. Public `Angle.Reference`,
checked wrapper integration, final canonical parity, forced-device evidence and
performance remain separate work. All 1,884 API statuses remain unchanged.
