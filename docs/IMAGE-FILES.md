# Image memory and file dispatch

`Surface.decode_image(file_type, bytes)` returns
`Result<&1, &1, Image.DecodeError, Surface>` with normalized RGBA8 pixels.
The file-type argument is an extension token such as `.png`, not a filename.
It selects the same implemented decoder family as file loading, without IO.

`Surface.load_image(path)` returns
`IO(Result<&1, &1, Image.LoadError, Surface>)` with normalized RGBA8 pixels.
It reads ordinary, non-changing files using Base IO and the implemented memory
codec profiles.

## Suffix and content selection

Recognized tokens are `.png`, `.bmp`, `.tga`, `.pgm`, `.ppm`, `.jpg`, `.jpeg`,
`.gif`, `.pic`, `.psd` and `.qoi`, plus their entirely uppercase equivalents.
Mixed-case forms and `.pnm` return a decode error, matching native dispatch.
Memory calls require the complete token: `image.png` and `.png-tail` are rejected.
File calls use the last dot in the path, as native `GetFileExtension` does. A dot
at position zero, such as the whole path `.png` or `.jpeg`, is rejected; a
directory-qualified path such as `images/.png` is classified normally.

QOI suffixes select QOI directly. The other recognized suffixes select the
implemented stb-style family: PNG, BMP and P5/P6 magic are recognized before
trying the supported TGA profile. Consequently, PNG bytes named `image.bmp`
load as PNG, matching actual native content detection. QOI bytes with a raster
suffix and raster bytes with a QOI suffix are rejected. The `.jpg/.jpeg/.gif/.pic/.psd`
aliases accept the implemented raster payloads, just as the native shared decoder
does; actual JPEG/GIF/PIC/PSD payload decoding remains unimplemented. HDR uses a
distinct native float path and remains outside this profile.

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
Memory dispatch rejects unsupported tokens with `InvalidImageHeader` before byte
decoding; recognized tokens retain the selected decoder's byte validation and
typed errors. Strings use ordinary extension/path text without embedded NULs.

## Verification

```sh
python3 tools/image_memory_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --gpu
python3 tools/image_file_probe.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
```

Configure checkout variables as described in [README.md](../README.md#requirements).
The memory probe compares 336 native token/content pairs, including 282 successful
images with every dimension and pixel checked, plus five typed invalid controls
on CPU, JavaScript and forced Metal. Runners contain at most 64 observation/control
actions to bound generated IO-chain depth. All batch outputs are concatenated in
order before the complete comparison; each batch's result count is checked too.

The file probe compares 47 native file cases: 46 actual `LoadImage` calls and an
explicit QOI-selection check through the native memory entry point. Cases cover
all supported suffixes, uppercase and cross-extension content, mixed/unsupported
suffixes, aliases, multiple dots, directory-qualified dotfiles,
invalid/empty/missing files, 16-bit PPM, packed/indexed TGA and BMP, BMP bitfields/extended/CORE headers,
and retained explicit-QOI behavior.

Three additional size/read boundaries and 100 success/decode/read/size-error
cycles run under a 64-file-descriptor limit on CPU and JavaScript. Pure contract
checks distinguish suffix-only/mixed-case names and incomplete reads. File IO
evidence is CPU/JavaScript only; the existing memory decoder profiles have their
own forced-Metal evidence.
