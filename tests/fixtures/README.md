# Shared image fixtures (schema 1)

`images.json` is the common input to both raylib and Bend code generation.
Each case has a unique lowercase/hyphenated `id`, `width`, `height`, a four-byte
RGBA `background`, and an ordered `operations` array.

Supported operations:

- `pixel`: integral `x`, `y`, RGBA `color`.
- `rectangle`: integral `x`, `y`, `width`, `height`, RGBA `color`.
- `circle`: integral `x`, `y`, U32 `radius`, RGBA `color`.
- `clear`: RGBA `color`.
- `flip_horizontal`, `flip_vertical`: no other fields required.
- `blend_color`: integral `x`, `y`, and RGBA `destination`, `color` (source),
  `tint`. The independently computed blend result is written at that pixel.

The domains are the same as [the initial public API](../../docs/API.md). The
optional `random` section adds mixed-operation scenarios using a fixed Python
PRNG seed. The exact expanded cases, not just the seed, are persisted and hashed
in `.build/scenarios.json`; this records the actual inputs on any Python version.

`radius-12-regression` is also the reference for `examples/headless.bend`.
An alternate `--fixtures` file must retain that scenario for the example check.

Explicit fixtures cover clipping, padded non-square storage, degenerate
rectangles, small circles, byte replacement, flip ordering and alpha/tint
rounding. Seeded scenarios broaden interactions. This is a finite conformance
corpus, not exhaustive mathematical proof of the coordinate/size domain.
