# Rotation and power-of-two profiles

## General image rotation

`Surface.rotate_degrees_for(reference, surface, degrees)` consumes an RGBA8
Surface and returns `Result<Surface & Surface.Error, Surface>`. The initial
profile accepts integral degrees -360..360 and output dimensions 1..4096.
Invalid angles return the original with `InvalidRectangle`; oversized output
returns it with `InvalidSize`.

The reference is `Gradient.Reference`: `AccurateGradient{}` or `GnuGradient{}`.
`Surface.rotate_degrees` selects the accurate profile. The names are shared with
the existing gradient numerical profiles; selection remains explicit.

The algorithm follows pinned raylib `ImageRotate`:

- Radians are computed as `degrees*PI/180` in the reference F32 order. This is
  different from the linear-gradient expression and its shorter PI constant.
- Output width/height are truncated from the sine/cosine bounding dimensions.
- Destination pixel centers map back to the source using the reference image centers.
- Four source bytes per channel are bilinearly weighted in the original order.
  RGB and alpha are interpolated independently; this is not alpha-weighted resizing.
- Samples outside the source remain transparent black.

`rotate_degrees(90)` is consequently **not** a replacement for `rotate_cw`:
the dedicated quarter turn performs an exact permutation, while general rotation
retains floating-point center/border behavior and byte truncation.

## Power-of-two canvases

`Surface.to_pot(surface, fill)` uses raw canvas copying at offset zero. It returns
the original unchanged when both dimensions are already powers of two. Otherwise
the next powers of two become the new dimensions and the remaining area receives
the fill color, without alpha blending.

For the supported 1..4096 domain the gate compares every axis value against
actual raylib `ImageToPOT`, before relying on integer power-of-two calculation
in Bend. Full pixel fixtures then cover the new dimensions, fill and hidden RGB.

## Verification

The main corpus compares exact dimensions, pixels and failure ownership.
Data-dependent rotation size hints are asserted against actual raylib immediately
after the operation; they never drive the candidate's allocation or sampling.
The trigonometry probe separately exercises the rotation expression:

```sh
python3 tools/trig_probe.py --bend-source "$BEND_SOURCE" --rotation --gpu
python3 tools/trig_probe.py --bend-source "$BEND_SOURCE" --rotation --gnu-control --gpu
```

Configure checkout variables as described in [README.md](../README.md#requirements).
Other formats, mipmaps, wider angle/size domains and complete target/performance
coverage remain open. No tolerance or expected pixels are adjusted to hide a mismatch.
