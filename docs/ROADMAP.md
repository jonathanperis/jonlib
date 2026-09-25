# Roadmap toward raylib parity

The authoritative destination, phase gates and progress rules are in the
[100% parity master plan](MASTER-PLAN.md). This page tracks the near-term sequence.
The [generated API dashboard](PROGRESS.md) assigns every reference declaration
to work packages and provides the current API-level queue.

## Current milestone: headless image foundations

The working milestone supplies an owned RGBA8 image API, fixed-point lines,
filled/outlined triangles, unscaled source-region composition, cropping/extraction,
exact nearest-neighbor resizing and a repeatable
differential harness, using raylib 6.0 CPU image operations as the reference.
Track exact verified capabilities in [COMPATIBILITY.md](COMPATIBILITY.md).

## Metal compiler boundary: resolved for the declared profile

The complete current Metal gate passes with the explicit compiler overlay
in `toolchain.json`. [METAL-INVESTIGATION.md](METAL-INVESTIGATION.md) records the
failure, a rejected broader outlining policy and the adopted dispatcher-only
boundaries. No source-specific rule or altered expected output is used.

The change is maintained as a checked-in Apache-2.0 patch while upstream
integration remains future work. Continue broader hardware/workload validation
and retain the exact-source checks when updating Bend. CUDA and the upstream
cluster/site gates remain unverified.

## 2D library growth

1. Complete the remaining primitive families, vector/rectangle math and collision helpers.
2. Broaden the now-implemented source-clipping/scaling ImageDraw profile to more
   formats and mipmaps. Bounded fractional rectangles, ImageResizeNN and
   [default RGBA8 filtering](RESAMPLING.md) are available.
3. Efficient command buffers and tiled rendering, measured against equivalent
   raylib scenes; avoid using the current correctness-oriented image loops as
   an assumed high-performance architecture.
4. Extend the [working QOI codec](CODECS.md) to BMP/PNG and subsequent formats;
   build text/fonts and PCM WAV support with their own reference gates.
5. Port selected upstream examples to Bend and compare deterministic outputs.

## Interactive platform foundation

Use existing Base windows/audio where sufficient. Add generic Bend facilities
for required gaps: event polling, sizing/DPI/fullscreen, cursor/clipboard,
text entry, high-resolution timing, presentation pacing, audio backpressure,
and gamepad/touch input. Keep rendering, decoding and mixing algorithms in Bend.

## Assets and 3D

General clipping/depth, textured meshes, cameras, lighting, animation, model
importers, richer fonts and compressed image/audio formats. Define programmable
effects in Bend, and separately decide the compatibility contract for arbitrary
GLSL and low-level rlgl interoperability.

## Platform expansion

Native Windows, browser and Android support need runtime/compiler/platform
work. Compilation alone is insufficient: each platform needs lifecycle, input,
audio, graphics and packaging evidence. Track unsupported targets openly.

## Test strategy

- Pin reference versions and maintain an API/capability inventory.
- Reuse raylib's examples, automation event scenarios and applicable tests.
- Compare shared fixtures through independent reference and Bend runners.
- Add small regressions for independently meaningful failure boundaries.
- Control random seeds, clocks, assets, quality, backends and capture frames.
- Use exact assertions for deterministic integer/image behavior; define any
  numeric or rendering tolerances before accepting a mismatch.
- Measure resource growth, frame-time distributions and audio underruns as
  separate requirements from correctness.
- Record unimplemented, runtime-blocked, passing and intentional divergences.

Raylib's checked-in examples and smoke tests are valuable inputs, but do not
constitute a comprehensive API conformance suite. Passing Jonlib's suite means
the declared, exercised profile passes; it is not proof about every raylib game.
