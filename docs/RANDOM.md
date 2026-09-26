# Owned random streams

The initial random profile follows pinned raylib with
`SUPPORT_RPRAND_GENERATOR=ON`: SplitMix64 initializes Xoshiro128** using the exact
low/high extraction order in `rprand.h`. Stream state is explicit and owned.

- `Random.seed(seed: U32) -> Random.State` creates an independent stream.
- `Random.value(state, minimum, maximum) -> Random.State & F32` returns the next
  stream and an integral value. Bounds are integral F32 values in -32767..32767.
  Endpoints are inclusive and reversed bounds are swapped. Equal bounds still
  consume one random draw.
- `Random.next_u32(state) -> Random.State & U32` exposes the underlying stream
  word for library composition; it is not an additional raylib API mapping.

Always create states with `Random.seed` and use the returned owner for the next
operation. This adapts the C global state to Bend ownership. Implicit-global
mutation and the alternative libc generator remain separate compatibility gaps.

## White-noise surfaces

`Surface.create_white_noise(state, width, height, factor)` returns
`Random.State & Maybe<Surface>`. Dimensions are 1..4096 and factor is finite in
0..1. Each pixel consumes one generator value, compares its remainder modulo 100
with the truncated F32 `factor*100` threshold, and becomes opaque white or black.
Factors zero and one still consume every draw. Invalid dimensions or factors
return the original stream and `None` before allocation or generation.

## Evidence

The full-image corpus checks dimensions and every noise pixel. A separate probe
compares 960 native `GetRandomValue` results across six seeds, plus three stream
observations after actual `GenImageWhiteNoise` calls:

```sh
python3 tools/random_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The forced GPU wrapper includes seeding and subsequent draws, so the seed path
is exercised on the device as well. Rejected-owner contracts are checked on
CPU, JavaScript and forced Metal. No distribution improvement, sequence
substitution or platform-dependent default seed is introduced.
