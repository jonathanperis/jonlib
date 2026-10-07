# Mipmaps

Jonlib adapts raylib 6.0 `ImageMipmaps` for single-level `Surface` input in
pixel formats 1..9.

```bend
Surface.mipmaps(surface) -> Image.Mipmaps
Image.Mipmaps.entries(chain) -> U32 & List<Surface>
Image.Mipmaps.unload(chain) -> Unit
```

## Contract

`Surface.mipmaps` consumes a single-level surface (dimensions 1..4096) and
generates its complete chain with independently owned levels. It cannot fail.

- The first level preserves every original RGBA pixel.
- Each next dimension is `max(1, floor(previous / 2))`.
- Each level is `ImageResize` of the **preceding level**, not of the base, with
  the default Mitchell filter of [RESAMPLING.md](RESAMPLING.md), in the image's
  format: GRAYSCALE, GRAY_ALPHA and R8G8B8 filter their own channels, and the
  other non-RGBA8 formats go through RGBA8 and back at every level, so they
  requantize per level exactly as raylib does.
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
candidate identical raw source bytes, converted with `ImageFormat` to each of
formats 1..9, then compares the level count, every level's dimensions and every
stored byte on CPU-1, CPU-2, JavaScript and, with `--gpu`, forced GPU. The
R8G8B8A8 corpus includes thin 4096-axis images, NPOT/odd sizes, a large source,
hidden RGB and alpha boundaries; the other formats use seven of those sizes.
Drawing one pixel into a returned level (ImageDrawPixel natively) must leave
every other level unchanged.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only mipmap
```

## Known gaps

Existing native partial/full chains as input, pixel formats 10+, the
contiguous C allocation/pointer ABI, texture upload/integration and complete
resource/platform/performance parity.
