# Owned RGBA8 mipmaps

`Surface.mipmaps(surface) -> Image.Mipmaps` consumes a checked single-level RGBA8
surface and generates its complete mipmap chain. Dimensions retain the existing
1..4096 profile. The returned levels have independent owned storage.

- The first level preserves every original RGBA pixel.
- Each next dimension is `max(1, floor(previous / 2))`.
- Each level uses the preceding level as its source for the verified default
  Mitchell downsampling filter; levels are not resized directly from the base.
- The final level is 1×1. The reported count includes the base; an input already
  1×1 produces one unchanged level.
- POT, NPOT, odd and one-pixel-wide/high images follow the same native sequence.

`Image.Mipmaps.entries(chain) -> U32 & List<Surface>` consumes the chain and
returns the count and levels in base-to-smallest order. Each returned Surface can
be consumed, transformed or exported separately. `Image.Mipmaps.unload(chain)`
consumes the entire chain and returns `Unit`.

This adapts pinned `ImageMipmaps` for single-level RGBA8 input. Existing native
partial/full chains, other pixel formats, contiguous C allocation/pointer ABI,
texture upload/integration and full resource/platform/performance remain gaps.
Like other owned images, the visible constructor does not authorize manually
inconsistent storage. No allocation-failure recovery is promised.

## Verification

```sh
python3 tools/mipmap_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The probe calls actual native `ImageMipmaps`, then compares the complete level
count, dimensions and every RGBA byte on CPU/JavaScript/forced Metal. Its corpus
includes thin 4096-axis images, NPOT/odd sizes, a 33,153-pixel source, hidden RGB
and alpha boundaries. Mutating one returned level must preserve all other levels.
The native and candidate receive identical raw source bytes.
The current gate passes 14 chains / 72 levels / 61,127 pixels per lane, including
three independently mutated chains. See [evidence/mipmaps.json](evidence/mipmaps.json).

The unchanged filter implementation and its broader coefficient/resize evidence
are documented in [RESAMPLING.md](RESAMPLING.md).
