# Bounded owned GIF animations

`Image.Animation.decode_gif(bytes, maximum_frames, maximum_pixels)` returns
`Result<&1, &1, Image.DecodeError, Image.Animation>`.

This is the GIF memory profile for native `LoadImageAnimFromMemory`: every frame
is an independently owned RGBA8 Surface with the logical canvas dimensions.
Native frame delays are discarded by that API and are not returned here.

## Ownership and budgets

- `maximum_frames` must be positive. `maximum_pixels` must be 1..16,777,216.
- Each retained frame consumes one frame slot and `width*height` pixels from the
  caller's budgets. Exceeding either returns `UnsupportedImageSize` before retaining
  the excess frame.
- `Image.Animation.entries(animation)` consumes the animation and returns
  `(width, height, count, frames)` with an owned `List<Surface>`.
- `Image.Animation.unload(animation)` consumes the owner and returns `Unit`.
- Frame mutation is independent; current-canvas and pre-frame snapshots are
  separately owned. Allocation/resource exhaustion remains subject to the Bend runtime.

## Native frame composition

The first frame retains [GIF.md](GIF.md)'s palette, background, transparency,
offset and interlace behavior. Later transparent pixels preserve the existing
canvas. Disposal modes 0/1 retain the frame; mode 2 restores the previous frame's
affected rectangle from its pre-frame canvas.

Graphic Control state persists until replaced. Local palettes apply to one frame;
global palette transparency persists with native updates. In particular, the
first-frame background fill restores its global background entry to opaque, which
can affect a later frame without a new control extension. Local palettes still
use the current transparency index.

All frames must satisfy the existing positive-rectangle/LZW/palette bounds and the
stream must terminate normally. Invalid later frames return a typed error rather
than a partial animation.

Disposal 3 is outside this profile: the pinned native animation path assigns
`two_back = out - 2*stride`, an address before its allocated output buffer. This
implementation does not emulate undefined reads. Generic non-GIF fallback, file
animation loading, original metadata/native ABI, permissive recovery and full
resource/platform/performance coverage remain gaps.

## Verification

```sh
python3 tools/gif_animation_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares 9 actual native animations / 24 frames / 382 pixels on CPU,
JavaScript and forced Metal. It checks every frame, count and dimension, plus
ten budget/error controls and two ownership/disposal checks. Cases cover retain/
restore, transparent history, palette/control persistence, offsets/interlacing,
ignored delays and exact-budget termination. First-frame and shared memory/file
gates remain separate regressions. See
[evidence/gif-animation.json](evidence/gif-animation.json).
