# RGBA8 kernel convolution

Jonlib adapts raylib 6.2 `ImageKernelConvolution` for RGBA8 `Surface` owners.

```bend
Surface.kernel_convolution(surface, kernel: +List<F32>) -> Result<&1, &1, Surface & Surface.Error, Surface>
```

## Contract

- `kernel` is an immutable row-major list whose length is a square from 0
  through 225 (width 0..15).
- Coefficients are zero or finite with magnitude from 2^-16 through 16.
- Unsupported shapes or coefficients return the original surface with
  `InvalidKernel` before output storage is allocated.
- The empty kernel produces transparent black, matching the native zero-width
  kernel loop.

## Native indexing and arithmetic

- The anchor is `floor(kernelWidth/2)` on each axis; even kernels extend farther
  toward negative coordinates.
- A neighbour outside the image is clamped to the nearest edge, row and column
  separately: edge pixels repeat.
- Each RGBA byte is divided by 255 in F32 and multiplied by its coefficient.
  Products accumulate in row-major kernel order, starting from positive zero.
- Every channel sum, alpha included, clamps to 0..1, then is multiplied by 255
  and truncated, so every result of a supported kernel is defined.

## How it is verified

`tools/convolution_probe.py` (gate `convolution`) compares complete dimensions
and pixels with native `ImageKernelConvolution` on CPU-1, CPU-2, JavaScript and,
with `--gpu`, forced GPU. Cases cover odd/even/empty/identity/box/signed kernels,
clamped edges, the 225-coefficient boundary, all channel bytes, large images and
alpha sums outside 0..1. Invalid controls must return complete source owners.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only convolution
```

## The raylib example

`examples/textures_image_kernel.bend` is the Bend version of
`textures_image_kernel.c`. Its sharpen and Sobel kernels push alpha to 510.0f
and -510.0f; raylib clamps alpha before the byte cast, so the example is
defined and compared whole.

## Known gaps

Other kernel/coefficient domains, source formats and mipmaps, the native
allocation ABI and complete resource/platform/performance parity.
