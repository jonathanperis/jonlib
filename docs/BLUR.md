# Native RGBA8 Gaussian blur

`Surface.blur_gaussian(surface, size)` returns
`Result<&1, &1, Surface & Surface.Error, Surface>`.
It consumes a checked RGBA8 surface and reproduces the pinned default
`ImageBlurGaussian` operation. `size` is U32 and must be at most both image
dimensions. Larger requests return the original surface with `InvalidSize`
before premultiplication or working-buffer allocation.

## Reference arithmetic

The native implementation approximates Gaussian blur with **four horizontal and
vertical box-filter iterations**. Jonlib preserves its arithmetic sequence:

1. Apply the existing reference byte-quantized alpha premultiplication.
2. Initialize each sliding sum from the first `size` samples.
3. Remove the expired sample before adding the next sample, updating the divisor
   at each edge. Horizontal results retain F32 fractions.
4. Truncate every channel to a byte after each vertical pass, then retain that
   byte value in the next pass's F32 buffer.
5. Reverse premultiplication with the original F32 division, upper clamp and
   byte truncation. Zero alpha produces transparent black.

Size zero is valid and **is not an identity operation** for every input: initial
premultiplication and final reverse premultiplication can quantize translucent
RGB values. Thin images and sizes equal to the smaller dimension follow the
same reference rules. The checked bound avoids the native implementation's
unchecked initial row/column reads for excessive sizes.

Two owned F32 work arrays alternate roles; the source dimensions and RGBA8 format
are retained. Other input formats/mipmaps, configured iteration counts, negative
or excessive native sizes and complete resource/platform/performance remain gaps.

## Verification

```sh
python3 tools/blur_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares actual native full dimensions/pixels, with zero/max sizes,
thin/odd and both 4096-axis images, low/mixed/zero alpha, constant/impulse/random
pixels, repeated blur and retained rejected owners. It uses CPU, JavaScript and
explicit forced Metal lanes; fixture file IO remains on the host.
The gate passes **27 native cases / 117,151 pixels per lane** and three complete
rejected-owner controls. See [evidence/blur.json](evidence/blur.json).
