# RGBA8 Gaussian blur

Jonlib adapts raylib 6.0's default `ImageBlurGaussian` for RGBA8 `Surface` owners.

```bend
Surface.blur_gaussian(surface, size: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>
```

## Contract

The operation consumes a checked RGBA8 surface and keeps its dimensions and
format. `size` must be at most both image dimensions; larger requests return the
original surface with `InvalidSize` before premultiplication or working-buffer
allocation. This checked bound avoids the native implementation's unchecked
initial row/column reads for excessive sizes.

Size zero is valid and **is not an identity**: the initial premultiplication and
final reverse premultiplication can quantize translucent RGB values. Thin images
and sizes equal to the smaller dimension follow the same reference rules.

## Reference arithmetic

The native implementation approximates a Gaussian with **four horizontal and
vertical box-filter iterations**. Jonlib keeps its arithmetic sequence:

1. Apply the reference byte-quantized alpha premultiplication.
2. Initialize each sliding sum from the first `size` samples.
3. Remove the expired sample before adding the next one, updating the divisor at
   each edge. Horizontal results keep F32 fractions.
4. Truncate every channel to a byte after each vertical pass, and carry that
   byte value into the next pass's F32 buffer.
5. Reverse premultiplication with the original F32 division, upper clamp and
   byte truncation. Zero alpha produces transparent black.

Two owned F32 work arrays alternate roles.

## How it is verified

`tools/blur_probe.py` (gate `blur`) compares complete dimensions and pixels with
native `ImageBlurGaussian` on CPU-1, CPU-2, JavaScript and, with `--gpu`, forced
GPU. Cases cover zero and maximum sizes, thin/odd and both 4096-axis images,
low/mixed/zero alpha, constant/impulse/random pixels and repeated blur; rejected
requests must return complete unchanged owners.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only blur
```

## Known gaps

Other input formats and mipmaps, configured iteration counts, negative or
excessive native sizes and complete resource/platform/performance parity.
