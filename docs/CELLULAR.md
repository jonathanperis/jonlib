# Cellular generation

`Surface.create_cellular(state, width, height, tile_size)` returns
`Random.State & Maybe<Surface>`. Dimensions and tile size must be 1..4096.
Invalid requests return the original random owner and `None` before drawing
random values or allocating buffers.

The RGBA8 profile follows the pinned `GenImageCellular` implementation:

- The seed grid has `width/tile_size` columns and `height/tile_size` rows,
  using integer division. Partial edge tiles receive no seed of their own.
- Each seed consumes two draws, **Y before X**, with offsets modulo tile size.
- Each output pixel searches the same clipped 3×3 neighboring-tile region.
- Intensity is the truncated F32 `distance*256/tile_size`, saturated at 255;
  all three color channels share the intensity and alpha is 255.
- If either grid axis has no seeds, the image is white and no draws are consumed.

## Exact distance reduction

The reference casts native binary64 `hypot(dx,dy)` to F32 for each neighbor.
Jonlib selects the minimum integer squared distance first and caps it at
`tile_size²`: larger distances already saturate to white. The capped square is
at most 2²⁴ and is exactly representable in F32. A single square root followed
by the original intensity expression therefore suffices for the exercised profile.

Before accepting cellular fixtures, the native conformance runner compares
`(float)hypot(x,y)` with `sqrtf((float)(x*x+y*y))` for **all 13,180,825**
nonnegative coordinate-difference pairs below the cap. A mismatch fails the gate.
Whole-image fixtures then compare every pixel on CPU-1, CPU-2, JavaScript and
forced Metal, including incomplete grids, saturation, no seeds and the maximum
tile size. The independent random probe compares the stream after generation.

The implementation is Bend-only and retains explicit ownership of seed/output
arrays. No performance parity is claimed. Implicit-global/libc random behavior,
broader dimensions/tile sizes and full target/resource coverage remain gaps.
