# Gradient profiles and parallel generation

The square, radial and linear generators return owned RGBA8 surfaces in the
current 1..4096 size domain. Radial/square densities are 0..1. Linear directions
are integral F32 values in **-360..360**, with a nonzero reference normalization
extent. Invalid requests return `None`.

`Surface.create_gradient_linear_for(reference, width, height, direction, start, end)`
requires an explicit `Gradient.Reference`: `AccurateGradient{}` for the verified
macOS/double-rounded profile, or `GnuGradient{}` for the verified GNU/Arm polynomial
profile. `create_gradient_linear` remains the accurate-profile convenience API.
The conformance harness selects the matching declared profile for Darwin or
Linux/glibc; other host families need their own verified declaration.
Both declared profiles now pass all 721 native-host comparisons in the
[hosted verification record](evidence/hosted-1a792f9.json).

## Exact arithmetic and remaining gap

The formulas follow the pinned `rtextures.c`, including its `3.14159f` constant
and direction convention for linear gradients. Native Metal trigonometry caused
a one-byte output mismatch at direction zero. `src/trig.bend` now performs
bounded range reduction and extended-precision polynomial evaluation in Bend,
rounding only the final sine/cosine values to F32. It is an internal helper, not
a general-purpose replacement for platform math libraries.

The normal trigonometry probe compares every direction in -360..360 against
actual host `sinf`/`cosf` bits. Ubuntu CI demonstrated that its GNU float-libm
rounding differs from Apple's even within this range. A dedicated Bend
implementation of the MIT-licensed Arm polynomial reproduces that profile;
reference selection is explicit instead of replacing expected values or adding
a tolerance. `trig_probe.py --gnu-control` also checks it against an independent
C implementation of the same upstream polynomial on any host.

A separate full-range diagnostic found **52 of
65,535 directions** differing from Apple float-libm by one result bit. The
candidate values also match double-libm rounded to F32 for the retained examples;
that still fails the exact compatibility contract. The wider range remains
rejected and tracked in [the counterexample record](evidence/gradient-trig-full.json).
Neither expected values nor tolerances were changed.

## Ownership-safe parallel work

Radial/linear generators build separate balanced subarrays. Each parallel leaf
performs at most 256 pixels of serial work. Every pixel retains its reference
arithmetic order; no floating-point reduction is reassociated. The input paint
is immutable and the output arrays have separate owners. No unsafe array sharing
or atomics are used.

On the local Apple M1, a 512×512 radial workload matched raylib's checksum
`2103517670`. Five warmed full-process samples gave these medians:

| Lane | Median elapsed |
|---|---:|
| Serial tree, CPU-1 | 12.27 ms |
| Balanced tree, CPU-1 | 10.74 ms |
| Balanced tree, CPU-2 | 9.14 ms |
| Balanced tree, forced Metal | 190.19 ms |

These measurements include allocation, checksum, process startup and device
setup. They support the tested CPU partitioning choice, not GPU speed or raylib
performance parity. Full records are in `.build/gradient-bench/results.json`.

## Reproduce

Set the checkout variables from [README.md](../README.md#requirements), then:

```sh
python3 tools/conformance.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/trig_probe.py --bend-source "$BEND_SOURCE" --gpu
python3 tools/gradient_bench.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

`trig_probe.py --full` is a diagnostic of the open wider-angle contract and can
fail; a passing one-cycle profile does not complete that broader domain.
