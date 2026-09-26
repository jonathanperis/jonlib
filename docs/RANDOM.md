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

## Unique sequences

`Random.load_sequence(state, count: U32, minimum: F32, maximum: F32, budget: Nat)`
returns `Random.State & Result<&1, &1, Random.Sequence.Error, Random.Sequence>`.
It preserves rprand's duplicate-rejection draw order. Both endpoints must be
integral values in -32767..32767, and count cannot exceed `abs(maximum-minimum)+1`.

Unlike `Random.value`, the native sequence API does **not** swap reversed
bounds: values are `minimum + draw % (abs(maximum-minimum)+1)`. For example,
the range arguments 10,8 generate values from 10 through 12. The returned
sequence retains order of first acceptance and contains no duplicate values.

The caller supplies a draw budget because Bend requires structural termination
while the reference retry loop can reject an unbounded number of draws:

- `Done{sequence}`: complete sequence and advanced stream.
- `Fail{InvalidSequenceRequest{}}`: invalid endpoints or excessive count;
  original stream returned without any draws.
- `Fail{SequenceDrawLimit{partial}}`: budget exhausted; partial sequence in
  acceptance order and stream after precisely the consumed draws. This is an
  explicit incomplete result, never counted as reference sequence parity.
- Count zero succeeds with an empty sequence and consumes no draws, even with
  a zero budget. A last-budget draw that completes the request succeeds.

`Random.Sequence.values(sequence) -> +List<F32>` consumes the sequence owner
and returns its values. `Random.unload_sequence(sequence) -> Unit` disposes of
the owner. Native pointer/null/allocator behavior and implicit global state
remain gaps, as does an unbounded-retry API.

## White-noise surfaces

`Surface.create_white_noise(state, width, height, factor)` returns
`Random.State & Maybe<Surface>`. Dimensions are 1..4096 and factor is finite in
0..1. Each pixel consumes one generator value, compares its remainder modulo 100
with the truncated F32 `factor*100` threshold, and becomes opaque white or black.
Factors zero and one still consume every draw. Invalid dimensions or factors
return the original stream and `None` before allocation or generation.

`Surface.create_cellular(state, width, height, tile_size)` shares this ownership
convention. It consumes two draws per complete seed tile, Y before X; no-seed
grids consume no draws. See [CELLULAR.md](CELLULAR.md).

## Evidence

The full-image corpus checks dimensions and every noise pixel. A separate probe
compares 960 native `GetRandomValue` results across six seeds, three stream
observations after actual `GenImageWhiteNoise` calls, and seven complete
`LoadRandomSequence`/following-draw results. Sequence cases include full ranges,
duplicate retries, reversed/constant bounds, empty requests and excessive count.
Three additional observations check the stream after cellular generation:

```sh
python3 tools/random_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The forced GPU wrapper includes seeding and subsequent draws, so the seed path
is exercised on the device as well. Rejected-owner contracts are checked on
CPU, JavaScript and forced Metal. No distribution improvement, sequence
substitution or platform-dependent default seed is introduced.
