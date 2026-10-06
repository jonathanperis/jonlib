# Rotation and power-of-two profiles

## General image rotation

`Surface.rotate_degrees_for(reference, surface, degrees)` consumes an RGBA8
Surface and returns `Result<Surface & Surface.Error, Surface>`. The initial
profile accepts integral degrees -360..360 and output dimensions 1..4096.
Invalid angles return the original with `InvalidRectangle`; oversized output
returns it with `InvalidSize`.

The reference is Jonmath's `M.Libm`: `M.AppleLibm{}` or `M.Glibc239Libm{}`.
`Surface.rotate_degrees` selects the accurate profile. The names and numerical
contracts are shared with the gradient profiles ([GRADIENTS.md](GRADIENTS.md));
selection remains explicit.

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

For the supported 1..4096 domain the conformance reference compares every axis
value against actual raylib `ImageToPOT`, before relying on integer power-of-two calculation
in Bend. Full pixel fixtures then cover the new dimensions, fill and hidden RGB.

## Verification

| Gate | Tool | Compares |
|---|---|---|
| `conformance` | `tools/conformance.py` | exact dimensions, pixels and failure ownership vs linked raylib `ImageRotate`/`ImageToPOT` |
| `trig-rotation` | `tools/trig_probe.py --rotation` | Bend sine/cosine of the `ImageRotate` degree-to-radian expression for every integral degree in -360..360 vs the host's `sinf`/`cosf`, with the host-declared profile |

Data-dependent rotation size hints are asserted against actual raylib
immediately after the operation; they never drive the candidate's allocation or
sampling. `python3 tools/trig_probe.py --bend-source "$BEND_SOURCE" --rotation
--gnu-control` checks the GNU profile against an independent C model of the Arm
polynomial on any host.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only trig-rotation
```

Other formats, wider angle/size domains and complete target/performance
coverage remain open. No tolerance or expected pixels are adjusted to hide a
mismatch.
