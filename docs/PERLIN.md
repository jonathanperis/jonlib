# Perlin image profiles

`Surface.create_perlin(width, height, offset_x, offset_y, scale) -> Maybe<Surface>`
creates opaque RGBA8 grayscale noise using the pinned `GenImagePerlinNoise`
algorithm. `Surface.create_perlin_for(reference, ...)` selects
`M.Contraction`: `M.Uncontracted{}` or `M.Fused{}`. The convenience
operation uses `M.Uncontracted{}`.

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

The linked macOS arm64 reference contracts the easing polynomial, interpolation
and octave accumulation into multiply-add instructions. `M.Fused{}` uses the
Bend-only single-rounding arithmetic of `src/fused.bend` to reproduce this
behavior; Linux x86_64 uses `M.Uncontracted{}`. The harness selects the
profile from the same host declaration as the collision arithmetic
([COLLISION.md](COLLISION.md)). Neither profile modifies the reference build
flags or substitutes different noise coefficients.

## How it is verified

| Gate | Tool | Compares |
|---|---|---|
| `conformance` | `tools/conformance.py` | every pixel of square, wide, tall, thin, offset/wrapping, negative, zero and small-scale fixtures vs linked raylib, plus the invalid-domain contracts |
| `perlin` | `tools/perlin_probe.py` | all packed permutation/gradient table cells and raw octave results (before image quantization) vs the pinned `stb_perlin` header compiled with the host's contraction profile |

`tools/perlin_probe.py --uncontracted-control` checks `M.Uncontracted{}`
against the header compiled without contraction, on any host:

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only perlin
python3 tools/perlin_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --uncontracted-control
```

The MIT notice is retained in [LICENSES/stb-perlin.txt](../LICENSES/stb-perlin.txt).
Broader domains, other contraction patterns and complete target/resource/
performance parity remain gaps.
