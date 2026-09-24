# Roadmap toward raylib parity

## Current milestone: headless image foundations

The first milestone supplies an owned RGBA8 image API and a repeatable
differential harness, using raylib 6.0 CPU image operations as the reference.
Track exact verified capabilities in [COMPATIBILITY.md](COMPATIBILITY.md).

## Next: resolve the complete Metal gate

Investigate the scaling-sensitive failure documented in
[METAL-INVESTIGATION.md](METAL-INVESTIGATION.md). Smaller valid programs pass,
while the complete generated suite fails. Isolate the compiler/runtime cause
before claiming a GPU-compatible release. Preserve the failing suite.

If a Bend change is required, develop it in Bend's canonical checkout on an
appropriate branch, with a minimal upstream-level regression and the relevant
CPU/Metal tests. Update the pin only after a deliberate compatibility decision.

## 2D library growth

1. Vector/rectangle math, collision helpers, lines and triangles.
2. Source/destination image drawing, sampling, tint and compositing.
3. Efficient command buffers and tiled rendering, measured against equivalent
   raylib scenes; avoid using the current correctness-oriented image loops as
   an assumed high-performance architecture.
4. Bitmap/stroke text, QOI/BMP and PCM WAV before more demanding formats.
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
