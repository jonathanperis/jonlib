# Perlin image profiles

`Surface.create_perlin(width, height, offset_x, offset_y, scale) -> Maybe<Surface>`
creates opaque RGBA8 grayscale noise using the pinned `GenImagePerlinNoise`
algorithm. `Surface.create_perlin_for(reference, ...)` selects
`Noise.Reference`: `UncontractedNoise{}` or `FusedNoise{}`. The convenience
operation uses `UncontractedNoise{}`.

The initial domain is dimensions 1..4096, integral F32 offsets -32767..32767,
and finite scale equal to zero or with magnitude 2^-16..256. Invalid requests
return `None` before allocation. Negative scales and offsets retain their
reference behavior. Generation is deterministic and does not consume a random
stream or consult the global seed.

## Reference details

The Bend adaptation retains stb_perlin v0.5's permutation and gradient tables,
six octaves with lacunarity 2 and gain 0.5, and the octave index as the internal
seed. The Z coordinate starts at 1. Each pixel follows raylib's original aspect
compensation, clamp to -1..1, F32 remapping and unsigned-byte truncation.
Packed table words reproduce both repeated 256-entry halves exactly.

The exercised macOS arm64 reference contracts the easing polynomial, interpolation
and octave accumulation into multiply-add instructions. `FusedNoise{}` uses the
existing Bend-only single-rounding arithmetic to reproduce this behavior.
Hosted Linux/x86_64 uses `UncontractedNoise{}`. Neither profile modifies the
reference build flags or substitutes different noise coefficients.

## Verification

The full-image suite compares every native pixel for square, wide, tall, thin,
offset/wrapping, negative, zero and small-scale fixtures on CPU-1, CPU-2,
JavaScript and forced Metal. Three invalid-domain contracts are also checked.
An independent pinned-header probe verifies all 1,024 table cells and 222 raw
octave results per profile, before image quantization:

```sh
python3 tools/perlin_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/perlin_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --uncontracted-control --gpu
```

Configure checkouts as described in [README.md](../README.md#requirements).
The MIT notice is retained in [LICENSES/stb-perlin.txt](../LICENSES/stb-perlin.txt).
Broader domains, other contraction patterns and complete target/resource/
performance parity remain gaps.
