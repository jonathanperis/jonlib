# Gradient profiles and parallel generation

The square, radial and linear generators return owned RGBA8 surfaces in the
1..4096 size domain. Radial/square densities are 0..1. Linear directions are
integral F32 values in **-360..360**, with a nonzero reference normalization
extent. Invalid requests return `None`.

`Surface.create_gradient_linear_for(reference, width, height, direction, start, end)`
takes Jonmath's explicit `M.Libm`:

| Profile | Numerical contract | Host-declared reference |
|---|---|---|
| `M.AppleLibm{}` | macOS float libm `sinf`/`cosf` (double-rounded) | Darwin |
| `M.Glibc239Libm{}` | Arm optimized-routines float polynomial used by GNU libm | Linux/glibc |

`create_gradient_linear` is the accurate-profile convenience API. The
conformance harness declares the profile per host family (Darwin or
Linux/glibc); other host families need their own verified declaration. The same
`Libm` also selects the rotation, legacy angle and extrema
profiles; extrema are selected separately from native controls (see
[NATIVE-MATH-PROFILES.md](NATIVE-MATH-PROFILES.md)).

## Exact arithmetic

The formulas follow the pinned `rtextures.c`, including its `3.14159f` constant
and direction convention for linear gradients. `src/trig.bend` performs bounded
range reduction and extended-precision polynomial evaluation in Bend, rounding
only the final sine/cosine values to F32, so backend-native trigonometry (which
differs on Metal) is never used. It is an internal helper, not a general-purpose
replacement for platform math libraries. The GNU profile is a Bend
implementation of the MIT-licensed Arm polynomial
([LICENSES/arm-math.txt](../LICENSES/arm-math.txt)); GNU float-libm rounding
differs from Apple's even within -360..360, so the reference is selected
explicitly rather than by changing expected values or adding a tolerance.

## Ownership-safe parallel work

Radial/linear generators build separate balanced subarrays. Each parallel leaf
performs at most 256 pixels of serial work. Every pixel keeps its reference
arithmetic order; no floating-point reduction is reassociated. The input paint is
immutable and the output arrays have separate owners; no unsafe array sharing or
atomics are used.

## How it is verified

| Gate | Tool | Compares |
|---|---|---|
| `conformance` | `tools/conformance.py` | every pixel of the gradient fixtures vs linked raylib |
| `trig` | `tools/trig_probe.py` | Bend sine/cosine for every direction in -360..360 vs the host's actual `sinf`/`cosf` bits, with the host-declared profile |

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only trig
python3 tools/trig_probe.py --bend-source "$BEND_SOURCE" --gnu-control
python3 tools/gradient_bench.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

`trig_probe.py --gnu-control` checks the GNU profile against an independent C
implementation of the same Arm polynomial on any host. `tools/gradient_bench.py`
checks a 512×512 radial gradient checksum against raylib for the serial tree,
the balanced tree on one and two threads (and forced GPU with `--gpu`) and
records warm full-process timings in `.build/gradient-bench/results.json`; the
timings support the CPU partitioning choice only, not GPU speed or raylib
performance parity.

## Known gaps

- Directions outside -360..360 are rejected. Over the full integral range
  -32767..32767 some directions differ from Apple float libm by one result bit
  (the candidate then matches double libm rounded to F32, which still fails the
  exact contract). `trig_probe.py --full` is the diagnostic for that wider
  domain and can fail.
- Other host families have no declared profile.
