# GIF recording (msf_gif)

`src/msf_gif.bend` is the GIF encoder raylib's `core_screen_recording`
example records the screen with: msf_gif.h 2.2 by Miles Fogle, which the
pinned raylib ships beside its examples (`examples/core/msf_gif.h`). It is
not a raylib API: a program imports the module, as the example includes the
header.

| Jonlib | msf_gif.h |
| --- | --- |
| `begin(width, height) -> Maybe<Gif>` | `msf_gif_begin` |
| `frame(gif, pixels, centiseconds, max_depth) -> Maybe<Gif>` | `msf_gif_frame` with a pitch of `width*4` |
| `finish(gif) -> +List<U32>` | `msf_gif_end`: the file's bytes |

`pixels` are the frame's `width*height` R8G8B8A8 words (`0xRRGGBBAA`), row by
row from the top; `centiseconds` and `max_depth` are the words of the C ints.
The library's two globals keep their defaults: `msf_gif_alpha_threshold` 0
(alpha is not read) and `msf_gif_bgra_flag` 0.

## What a frame is

- **Cooking.** A depth `d` of 1 to 16 gives red `(d + 1)/3` bits, green
  `(d + 2)/3` and blue `d/3`. Each channel is multiplied
  (`(short)((255.0f - diff)/255.0f*257)`, a table of seven values here),
  dithered with a 4x4 ordered kernel and shifted into its bits. The first
  depth is the smaller of the one asked (clamped to 1..16) and the depth of
  the frame before plus `160/its colors`; while a cooking leaves 256 colors
  or more, the frame is cooked again one depth lower.
- **Palette.** The local color table holds the transparent index 0 and then
  the frame's colors in the order of their cooked values, each channel's
  bits spread over a byte; it is padded with zeros to a power of two of at
  least 4.
- **Codes.** LZW with variable codes of up to 12 bits, a clear code first
  and whenever the table reaches 4096 codes, in sub-blocks of 255 bytes.
  Where the frame before was cooked at the same depth, a pixel equal to its
  pixel there is written as index 0; every frame's control extension says
  "do not dispose" with index 0 transparent.

The file is `GIF89a`, the logical screen without a global table, the
`NETSCAPE2.0` block (loop for ever), the frames and the trailer.

## What is refused

- `begin`: a side of 0 (the C code reads the frame's first pixel
  unconditionally) or above 4096, Jonlib's image limit.
- `frame`: a pixel list that is not `width*height` long, and **a frame the C
  code writes past its buffer**. `msf_compress_frame` allocates
  `800 + width*height*3/2` bytes for a frame and clears 260 bytes ahead of
  every sub-block it begins, without a check: after the header, a table of
  256 colors and the code-size byte, the first sub-block ends at byte 1047,
  so a frame of 128 colors or more needs 165 pixels, and more where its
  codes begin further sub-blocks (256 bytes each). Only small frames of
  many colors are concerned: with a code for every pixel, the worst the
  writer does, the buffer holds every frame of 848 pixels or more, and an
  800x450 screen has 540800 bytes.

## How it is verified

`tools/msf_gif_probe.py` (gate `msf-gif`) builds the unmodified header twice,
with its SSE2 loop and with `MSF_GIF_NO_SSE2`, and requires both to write the
same files: the port follows the scalar loop (the saturating sums of the
SSE2 one are the scalar code's minimum with 65535, and no product leaves 16
bits). Both builds use the header's own allocator hooks to get 4096 bytes
more than asked for every block, so the reference also writes the frames
that would leave the buffer without leaving its memory. The probe reads each
file back with an LZW decoder of its own (every frame must decode to
`width*height` pixels), computes from the codes which frames the unhooked
library writes past its buffer, and expects exactly those refused. 72 cases,
122 frames: single pixels, widths that are not multiples of four, flat
frames, frames equal to the one before, moving shapes, gradients, noise
(lowered depths, table resets), every asked depth, delays of one and two
bytes and out of range, streams that end on a sub-block's last byte, and
frames on both sides of the buffer's limit. `LAWS.bend` has 36 laws
(`msf_gif_*`).

## Known gaps

`msf_gif_alpha_threshold` and `msf_gif_bgra_flag` other than 0, a pitch
other than `width*4` (negative pitches flip the frame), and the
`_to_file` functions (the bytes are the same; a program saves them with
`Files.save_data`).

## Provenance

msf_gif is MIT or public domain; Jonlib uses the MIT alternative, retained
with its notice in [LICENSES/msf_gif.txt](../LICENSES/msf_gif.txt).
