# RGBA8 mipmaps

Jonlib adapts raylib 6.0 `ImageMipmaps` for single-level RGBA8 `Surface` input.

```bend
Surface.mipmaps(surface) -> Image.Mipmaps
Image.Mipmaps.entries(chain) -> U32 & List<Surface>
Image.Mipmaps.unload(chain) -> Unit
```

## Contract

`Surface.mipmaps` consumes a checked single-level RGBA8 surface (dimensions
1..4096) and generates its complete chain with independently owned levels.

- The first level preserves every original RGBA pixel.
- Each next dimension is `max(1, floor(previous / 2))`.
- Each level is downsampled from the **preceding level**, not from the base,
  with the default Mitchell filter of [RESAMPLING.md](RESAMPLING.md).
- The final level is 1×1. The count includes the base; a 1×1 input produces one
  unchanged level.
- POT, NPOT, odd and one-pixel-wide/high images follow the same native sequence.

`Image.Mipmaps.entries` consumes the chain and returns the count and levels in
base-to-smallest order; each Surface can then be consumed, transformed or
exported separately. `Image.Mipmaps.unload` consumes the whole chain. As with
other owned images, the visible constructor does not authorize manually
inconsistent storage, and no allocation-failure recovery is promised.

## How it is verified

`tools/mipmap_probe.py` (gate `mipmap`) gives native `ImageMipmaps` and the
candidate identical raw source bytes, then compares the level count, every
level's dimensions and every RGBA byte on CPU-1, CPU-2, JavaScript and, with
`--gpu`, forced GPU. The corpus includes thin 4096-axis images, NPOT/odd sizes,
a large source, hidden RGB and alpha boundaries. Mutating one returned level
must leave every other level unchanged.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only mipmap
```

## Known gaps

Existing native partial/full chains as input, other pixel formats, the
contiguous C allocation/pointer ABI, texture upload/integration and complete
resource/platform/performance parity.
