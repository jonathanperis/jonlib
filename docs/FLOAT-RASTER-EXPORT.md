# RGB float BMP and TGA file export

`Image.FloatRGB.to_bmp(image)` and `to_tga(image)` return
`Result<&1, &1, Image.FloatRGB, +List<U32>>` containing exact native file bytes.
They adapt `ExportImage` file output; native `ExportImageToMemory` does not expose
BMP/TGA dispatch.

`Image.FloatRGB.write_bmp(image, path)` and `write_tga(image, path)` return
`IO(Result<&1, &1, Image.FloatRGB.WriteError, Unit>)`. The codec is selected by the
function regardless of the filename extension.

All four operations accept finite RGB samples in `[0,1]`, truncate each channel
with native F32 multiplication by 255, and encode opaque RGBA8 through the existing
[BMP](BMP.md) or [TGA](TGA.md) writer. Native V4 BMP headers/pixels and default TGA
RLE packet behavior are retained. No tone mapping or clamping is introduced.

Unsupported samples return the original owner. File APIs use
`FloatRGBSampleError{image}` before opening the output, while
`FloatRGBFileError{code,message}` preserves Base errors. Valid writes consume the
source and close the handle through the shared float PNG/RAW write boundary.

## Verification

```sh
python3 tools/float_rgb_raster_export_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
```

Configure checkout variables as in [README.md](../README.md#requirements).
The gate compares 12 native file profiles / 3,918 encoded bytes / 4,064 decoded
RGBA bytes on CPU/JavaScript/forced Metal. Cases include thin/rectangular images,
gradients and the TGA 128-pixel run boundary. CPU/JS write every file with a `.dat`
suffix and compare it to native output, proving explicit codec selection.

Two pure owner-rejection controls and typed file-error checks pass. One hundred
success/rejection/error cycles per IO lane run under a 64-descriptor limit;
rejected writes preserve an existing sentinel file. Affected float PNG and RAW
writer gates also pass. See
[evidence/float-rgb-raster-export.json](evidence/float-rgb-raster-export.json).

GPU filesystem IO, other source domains/formats/options, generic dispatch and
complete native-ABI/resource/platform/performance coverage remain gaps.
