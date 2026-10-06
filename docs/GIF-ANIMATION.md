# Bounded owned image animations

| API | Contract |
|---|---|
| `Image.Animation.decode_gif(bytes, maximum_frames, maximum_pixels)` | Returns `Result<&1, &1, Image.DecodeError, Image.Animation>`. |
| `Image.Animation.decode_image(file_type, bytes, maximum_frames, maximum_pixels)` / `decode_image_for(reference, ...)` | Token-dispatched memory loading; see [memory dispatch](#memory-dispatch). |
| `Image.Animation.load_image(path, maximum_frames, maximum_pixels)` / `load_image_for(reference, ...)` | Returns `IO(Result<&1, &1, Image.LoadError, Image.Animation>)`; see [file loading](#file-loading). |
| `Image.Animation.entries(animation)` | Consumes the animation and returns `(width, height, count, frames)` with an owned `List<Surface>`. |
| `Image.Animation.unload(animation)` | Consumes the owner and returns `Unit`. |

This is the GIF memory profile for native `LoadImageAnimFromMemory`: every frame
is an independently owned RGBA8 Surface with the logical canvas dimensions.
Native frame delays are discarded by that API and are not returned here.

## Memory dispatch

`Image.Animation.decode_image` accepts the image-format tokens. Exact `.gif` and
`.GIF` tokens select the GIF sequence decoder. Other supported tokens use
single-image content detection and return one owned frame. For example, GIF data
under `.png` yields its first frame, matching native fallback behavior; mixed
`.GiF` is rejected by the memory-token path.

`Image.Animation.decode_image_for(reference, ...)` selects explicit
`M.Contraction` for PSD fallback ([PSD.md](PSD.md)). The convenience
call selects `M.Uncontracted{}`.

## File loading

`Image.Animation.load_image(path, maximum_frames, maximum_pixels)` returns
`IO(Result<&1, &1, Image.LoadError, Image.Animation>)`. The `_for(reference, ...)`
variant selects explicit PSD arithmetic; the convenience call is uncontracted.

File suffixes use the native last-dot rule. GIF selection is ASCII
case-insensitive: `.gif`, `.GIF` and `.GiF` all request a GIF sequence. Other
suffixes retain the exact image-token rules and yield one frame. GIF content named
`.png` therefore returns one frame; PNG content named `.GiF` fails GIF decoding. A
whole path consisting only of `.gif` has no extension, while a
directory-qualified dotfile is classified normally.

Animation and Surface loaders share the same checked byte-file boundary
([IMAGE-FILES.md](IMAGE-FILES.md)): complete reported-size reads, a 1 MiB
raster/unknown limit, the 83,886,102-byte QOI limit, and handle closure before
decoding or size/read errors. Open/size/read failures retain `ImageFileError`;
image/budget failures are wrapped as `ImageDecodeError`. Caller frame/pixel
budgets apply to retained frames. Ordinary non-changing files are the supported
IO domain.

## Ownership and budgets

- `maximum_frames` must be positive. `maximum_pixels` must be 1..16,777,216.
- Each retained frame consumes one frame slot and `width*height` pixels from the
  caller's budgets. Exceeding either returns `UnsupportedImageSize` before
  retaining the excess frame.
- Frame mutation is independent; current-canvas and pre-frame snapshots are
  separately owned. Allocation/resource exhaustion remains subject to the Bend
  runtime.

## Native frame composition

The first frame retains [GIF.md](GIF.md)'s palette, background, transparency,
offset and interlace behavior. Later transparent pixels preserve the existing
canvas. Disposal modes 0/1 retain the frame; mode 2 restores the previous frame's
affected rectangle from its pre-frame canvas.

Graphic Control state persists until replaced. Local palettes apply to one frame;
global palette transparency persists with native updates. In particular, the
first-frame background fill restores its global background entry to opaque,
which can affect a later frame without a new control extension. Local palettes
still use the current transparency index.

All frames must satisfy the positive-rectangle/LZW/palette bounds and the stream
must terminate normally. Invalid later frames return a typed error rather than a
partial animation.

Disposal 3 is outside this profile: the pinned native animation path assigns
`two_back = out - 2*stride`, an address before its allocated output buffer. This
implementation does not emulate undefined reads.

## How it is verified

- **Memory** (`tools/gif_animation_probe.py`, gate `gif-animation`): every frame,
  count and dimension of native `LoadImageAnimFromMemory` animation/static inputs,
  plus budget/error controls, ownership/disposal checks and a default-reference
  check, compared exactly on the CPU-1, CPU-2 and JavaScript lanes (`--gpu` adds
  a forced-GPU lane, local only). Cases cover exact token selection,
  single-image/cross-extension fallback, PSD profiles, retain/restore,
  transparent history, palette/control persistence, offsets/interlacing, ignored
  delays and exact-budget termination. Static native fallback images are
  normalized to RGBA8 before comparison, since their native formats may be
  grayscale or RGB.
- **Files** (`tools/animation_file_probe.py`, gate `animation-file`): complete
  native animation files on CPU/JavaScript, with file/budget/size boundaries, a
  default-arithmetic control and repeated success/budget/decode/read/size-error
  cycles under a 64-descriptor limit. All eight GIF suffix letter-case
  combinations, dotfiles, cross-extension fallback and image-file/QOI behavior are
  checked.

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only gif-animation
```

## Known gaps

Disposal 3, original metadata/native ABI, callbacks/concurrent/special-file
behavior, permissive recovery, GPU filesystem IO and full
resource/platform/performance coverage.
