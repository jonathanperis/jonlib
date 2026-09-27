# Bounded image-file loading

`Surface.load_image(path)` returns
`IO(Result<&1, &1, Image.LoadError, Surface>)` with normalized RGBA8 pixels.
It reads ordinary, non-changing files using Base IO and the implemented memory
codec profiles.

## Suffix and content selection

Recognized suffixes are `.png`, `.bmp`, `.tga`, `.pgm`, `.ppm` and `.qoi`, plus
their entirely uppercase equivalents. Mixed-case forms are outside the native
dispatch exercised here and return a decode error. A path consisting only of
the suffix, such as `.png`, has no extension under native `GetFileExtension` and
is rejected; a longer path ending in that suffix is classified normally.

QOI suffixes select QOI directly. The other recognized suffixes select the
implemented stb-style family: PNG, BMP and P5/P6 magic are recognized before
trying the supported TGA profile. Consequently, PNG bytes named `image.bmp`
load as PNG, matching actual native content detection. QOI bytes with a raster
suffix and raster bytes with a QOI suffix are rejected. Other native extension
aliases and codec families remain gaps.

`Surface.load_qoi(path)` remains an explicit QOI loader and does not consult the
suffix. Both operations share the checked IO boundary.

## Bounds, ownership and errors

- Raster and unknown-suffix files are capped at **1 MiB** before reading.
- QOI selection retains its **83,886,102-byte** encoded-size cap.
- The read must return the complete reported size. A short result returns
  `ImageDecodeError{TruncatedImageData}`.
- Open/size/read errors retain `ImageFileError{code, message}`.
- Unsupported suffixes and decoder errors are wrapped as `ImageDecodeError`;
  oversize files use `UnsupportedImageSize`.
- Opened handles close before decoding and on size/read failure. The caller
  receives an owned Surface on success.

Memory codec APIs retain their own documented profiles; file bounds do not
enlarge those domains. Concurrent changes, special-file behavior, native callbacks,
original-format metadata and full resource/platform coverage remain gaps.

## Verification

```sh
python3 tools/image_file_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The probe compares 24 native file cases: 23 actual `LoadImage` calls and an
explicit QOI-selection check through the native memory entry point. Cases cover
all supported suffixes, uppercase and cross-extension content, mixed/unsupported
suffixes, invalid/empty/missing files and retained explicit-QOI behavior.

Three additional size/read boundaries and 100 success/decode/read/size-error
cycles run under a 64-file-descriptor limit on CPU and JavaScript. Pure contract
checks distinguish suffix-only/mixed-case names and incomplete reads. File IO
evidence is CPU/JavaScript only; the existing memory decoder profiles have their
own forced-Metal evidence.
