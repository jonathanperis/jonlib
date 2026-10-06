# RGBA8 kernel convolution

Jonlib adapts raylib 6.0 `ImageKernelConvolution` for RGBA8 `Surface` owners.

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
- Final alpha values must satisfy -1 < F32 `alphaSum*255` < 256, so truncation
  fits the native unsigned byte. Any other result returns the entire unchanged
  source with `InvalidKernel`, even after several output pixels were computed.
  Native out-of-range casts are undefined behavior and are not treated as
  compatibility evidence.

Source storage and output are separately owned during calculation, so rejection
needs no source clone.

## Native indexing and arithmetic

- The anchor is `floor(kernelWidth/2)` on each axis; even kernels extend farther
  toward negative coordinates.
- The reference checks the **flattened unsigned source index**, not each axis. A
  neighbor crossing a row edge therefore reads the adjacent row when its flat
  index is still inside the image. Out-of-image flat indices contribute zero.
- Each RGBA byte is divided by 255 in F32 and multiplied by its coefficient.
  Products accumulate in row-major kernel order, starting from positive zero.
- RGB sums clamp to 0..1, then are multiplied by 255 and truncated. Alpha is not
  clamped.

## How it is verified

`tools/convolution_probe.py` (gate `convolution`) compares complete dimensions
and pixels with native `ImageKernelConvolution` on CPU-1, CPU-2, JavaScript and,
with `--gpu`, forced GPU. Cases cover odd/even/empty/identity/box/signed kernels,
flat row-edge wrapping, the 225-coefficient boundary, all channel bytes, large
images and defined alpha truncation. Invalid controls must return complete source
owners, including rejection after an earlier pixel was computed.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only convolution
```

## Known gaps

Other kernel/coefficient domains, source formats and mipmaps, the native
allocation ABI and complete resource/platform/performance parity.
