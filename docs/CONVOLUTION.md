# Native RGBA8 kernel convolution

`Surface.kernel_convolution(surface, kernel)` returns
`Result<&1, &1, Surface & Surface.Error, Surface>` for a checked RGBA8 source.
`kernel` is an immutable `+List<F32>` in row-major order.

The supported kernel has a square length from 0 through 225 (width 0..15).
Coefficients are zero or finite values with magnitude from 2^-16 through 16.
Unsupported shapes/coefficients return the original surface with `InvalidKernel`
before allocating output storage. The empty kernel produces transparent black,
matching the native zero-width kernel loop.

## Native indexing and arithmetic

- The anchor is `floor(kernelWidth/2)` on each axis. Even kernels extend farther
  toward negative coordinates.
- The reference checks the **flattened unsigned source index**, not each axis.
  A neighbor crossing a row edge can therefore read the adjacent row when its
  flat index remains inside the image. Out-of-image flat indices contribute zero.
- Each RGBA byte is divided by 255 in F32 and multiplied by its coefficient.
  Products accumulate in row-major kernel order, starting from positive zero.
- RGB sums clamp to 0..1, then multiply by 255 and truncate. Alpha is not clamped.

For alpha, Jonlib accepts only final F32 `alphaSum*255` values strictly between
-1 and 256. Truncation then fits the native unsigned byte. Other results return
the original unchanged owner with `InvalidKernel`; even an error after several
computed output pixels preserves the entire source. This avoids treating native
undefined out-of-range casts as compatibility evidence.

Other kernel/coefficient domains, source formats/mipmaps, native allocation ABI
and complete resource/platform/performance remain gaps. Source storage and output
are separately owned during calculation; no source clone is needed for rejection.

## Verification

```sh
python3 tools/convolution_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The probe compares actual native complete dimensions/pixels on CPU, JavaScript
and forced Metal. Cases cover odd/even/empty/identity/box/signed kernels, flat
row-edge wrapping, the 225-coefficient boundary, all channel bytes, large images
and defined alpha truncation. Invalid controls preserve complete source owners,
including rejection after an earlier transparent pixel was successfully computed.
The current gate passes **39 native cases / 34,650 pixels per lane** and nine
retained-owner controls. See [evidence/convolution.json](evidence/convolution.json).
