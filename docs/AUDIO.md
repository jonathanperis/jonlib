# Audio waves and sounds

Jonlib adapts raylib 6.0's `raudio.c` Wave functions as `Wave.*` in
`jonlib.bend`, and its device and Sound functions as `AudioDevice.*` and `Sound.*`
([below](#audio-device-and-sounds)). A `Wave{frames, rate, size, channels, data}` holds raylib's
fields and its interleaved samples, one per element: unsigned 8-bit, signed
16-bit (stored as the 16-bit pattern) or F32 bits for sample sizes 8, 16 and 32.
It is plain `Data`: copying a Wave copies its samples.

| Function | raylib | Contract |
|---|---|---|
| `Wave.decode(file_type, bytes)` | `LoadWaveFromMemory` | `.wav`/`.WAV` and `.qoa`/`.QOA` data as 16-bit samples (below). Other tokens are `UnsupportedWaveFormat`. |
| `Wave.load(path)` | `LoadWave` | The file's bytes decoded by its extension; file errors are `WaveFileError`. |
| `Wave.is_valid(wave)` | `IsWaveValid` | Frames, sample rate, sample size and channels all positive. |
| `Wave.copy(wave)` / `unload` | `WaveCopy` / `UnloadWave` | |
| `Wave.crop(wave, init, final)` | `WaveCrop` | Frames `init..final-1` when `0 <= init < final <= frames` (C ints as U32 two's-complement words); other ranges return the wave unchanged with `InvalidWaveRequest`. |
| `Wave.samples(wave)` | `LoadWaveSamples` | 8-bit as `(x - 128)/128`, 16-bit as `x/32768`, 32-bit as is (F32). |
| `Wave.to_code(wave, path)` / `write_code` | `ExportWaveAsCode` | raylib's header text with the file name (without extension, a-z upper-cased), `0x%x` bytes for 8- and 16-bit waves and `%.4ff` floats for 32-bit ones (exact decimal rounding, `src/decimal.bend`), 20 per line. Empty waves (raylib reads before its data) and NaN samples are refused. |
| `Wave.to_wav(wave)` / `Wave.write(wave, path)` | `ExportWave` | `.wav` (dr_wav's RIFF writer: a 16-byte `fmt ` chunk, IEEE float for 32-bit samples, PCM otherwise, the data chunk and a pad byte) and `.raw` sample bytes, and `.qoa` for 16-bit waves (qoa.h encoding, below), by ASCII-insensitive suffix; other names write nothing (`InvalidWaveRequest`). |
| `Wave.format_for(profile, wave, rate, size, channels)` / `Wave.format` | `WaveFormat` | miniaudio's `ma_convert_frames` conversion (below); `rate`, `size` and `channels` are C ints as U32 words. `Wave.format` uses `M.Uncontracted{}`. |

Sample sizes other than 8, 16 and 32 are `InvalidWaveRequest` for crop, samples,
format and export.

## WAV decoding

`src/wav.bend` (with `src/wav_adpcm.bend`) follows `drwav_init_memory` and
`drwav_read_pcm_frames_s16` exactly, as `LoadWaveFromMemory` calls them: it
reads `(unsigned int)totalPCMFrameCount` frames, so a 64-bit count keeps only
its low 32 bits. dr_wav's 64-bit sizes, positions and counts are two U32
words that wrap as in C.

- **Containers.** RIFF and RIFX (big-endian sizes, `fmt ` fields and
  samples); Wave64 (GUID chunk ids, the `riff`/`wave` GUIDs, a size of at
  least 80, 64-bit chunk sizes counting their 24-byte header, and dr_wav's
  padding of the size modulo 8, not to the next multiple of 8); RF64 (a
  RIFF size of 0xFFFFFFFF and a leading `ds64` chunk whose data size replaces
  the `data` chunk's and whose sample count, when nonzero, is the frame count);
  AIFF and AIFC (`COMM` and `SSND` chunks, below).
- **The chunk walk.** dr_wav's memory stream position and its 64-bit cursor:
  a `fmt ` chunk shorter than 16 bytes reads into the next chunk, its
  remaining declared size is an int seek (it may move backwards) while the
  cursor adds the 64-bit difference (a cursor past 4 GiB makes the data seek
  fail), padding, LIST/fact/unknown chunks, seeks past the end that end the
  walk, a missing header that ends it, `WAVE_FORMAT_EXTENSIBLE` headers (a
  22-byte extension whose subformat selects the codec, read in the
  container's byte order). The walk stops at `data` (RIFF, RIFX, RF64,
  Wave64) and continues past `SSND`. A RIFF/RIFX `fact` chunk keeps no count
  (dr_wav tests the format tag before it is known); Wave64's 8-byte count is
  the frame count when nonzero.
- **AIFF/AIFC.** `COMM` is exactly 18 bytes (AIFF) or at least 24 (AIFC);
  its 80-bit extended rate goes through `drwav_aiff_extented_to_s64`
  (fractions truncated; exponents below 16383 wrap to INT64 limits;
  unnormalized significands and negated values above 2^63 can still give a
  valid rate) and must lie in 0..0xFFFFFFFF. AIFC compression `NONE`,
  `raw ` (8-bit samples unsigned), `sowt` (little-endian), `fl32`/`fl64`/
  `FL32`/`FL64`, `alaw`/`ALAW` and `ulaw`/`ULAW` (above 8 bits read as 8);
  `ima4` and other types fail. The block align is channels*bits/8, bits
  are rounded up by `bits & 7`, AIFC skips the rest of `COMM` but neither
  form skips its padding, and later `COMM` chunks replace earlier ones (the
  `raw ` and `sowt` flags stay set). `SSND` data starts at its offset after
  the 8-byte offset/block-size header and its size is the chunk size less
  the offset (8 bytes more than the samples). The `COMM` frame count, when
  nonzero, is the frame count. 8-bit AIFF bytes get dr_wav's +128 unless
  `raw `, including a-law and mu-law bytes.
- **Validation and size.** The rate/channel/bit limits and a nonzero block
  align, the data position within the file, a data size clipped to the
  file (in wrapping 64-bit arithmetic) and rounded down to whole frames for
  uncompressed formats, and ADPCM with at most two channels. The frame count
  is the data size over the frame size, or for ADPCM dr_wav's block formula
  (a trailing partial block counts; 6 or 4 header bytes per channel).
- **Samples.** PCM samples of 1 byte are recentred, of 2 to 8 bytes keep
  their top two bytes (big-endian containers swap 2, 3, 4 and 8-byte
  samples first) and above 8 bytes are 0. 32-bit float is clamped to
  [-1, 1], offset by 1, scaled by 32767.5 in single precision and
  truncated; 64-bit float does the same in binary64 through the checked
  helpers (`src/binary64_add_sub.bend`, `src/binary64_ops.bend`), each
  rounding once to nearest even, with the truncation read from the result's
  words; other float widths are silence. a-law and mu-law use dr_wav's
  tables. Frames over dr_wav's 4096-byte read buffer (outside the 16-bit
  PCM fast path) and formats it does not convert read nothing.
- **ADPCM.** Microsoft ADPCM block headers (predictor, delta, two samples
  per channel, output oldest first), nibbles high first with dr_wav's
  coefficient and adaptation tables, the delta clamped to [16, 0x7FFFFFFF]
  and samples to 16 bits; IMA ADPCM headers (predictor and step index per
  channel) and groups of 4 bytes per channel giving 8 frames, low nibble
  first. Both read straight from the stream (past the `data` chunk when the
  frame count asks for it), keep the remaining block size as an unsigned
  32-bit count (small or uneven block alignments wrap it) and stop at a short
  read or an invalid predictor (MS) or step index (IMA).

Jonlib contracts where raylib's result is not defined (all
`InvalidWaveData`):

- dr_wav reads fewer frames than raylib allocates (partial or truncated
  ADPCM blocks, invalid predictors or step indices, frame counts above the
  data, formats it does not convert, frames over its read buffer): raylib
  returns those samples uninitialized;
- NaN float samples (32- or 64-bit): an undefined float-to-int conversion;
- MS ADPCM nibbles whose `nibble * delta` or prediction sum overflows an int
  (signed overflow is undefined), wherever it occurs in the decoded blocks;
- an AIFF rate whose significand is exactly 2^63 with the sign set and the
  largest exponent (dr_wav negates INT64_MIN), and AIFF channel and bit
  counts whose int product overflows;
- 5- to 7-byte and wider samples in big-endian containers: dr_wav's byte
  swap asserts (a debug build aborts, a release build leaves them
  unswapped);
- a chunk walk that returns to a position it has visited (a backward `fmt `
  seek onto itself): dr_wav never returns.

## QOA

`src/qoa.bend` follows qoa.h's `qoa_decode` and `qoa_encode` exactly, with C
ints as U32 two's-complement words (raylib's compiled code wraps where qoa.h's
int arithmetic overflows: `qoa_div` at scalefactor 0 for residuals of 2^15 and
more, and LMS sums for weights taken from a file).

- Decoding reads the channels and sample rate from the first frame header,
  then frames until the declared sample count. A frame that is too short for
  its LMS state, changes channels or rate, claims a size past the data or more
  samples than its slices hold ends the file: the Wave keeps the frames decoded
  so far (possibly 0). Files shorter than 16 bytes, without the `qoaf` magic or
  with zero samples, channels or rate fail (`InvalidWaveHeader`).
- Encoding brute-forces the 16 scalefactors per 20-sample slice (starting from
  the previous slice's), ranks them by squared error plus the LMS weight
  penalty, and writes the frame's LMS state before its slices. `.qoa` export
  needs 16-bit samples (otherwise nothing is written, `InvalidWaveRequest`); a
  wave qoa_encode refuses (no frames, sample rate outside 1..0xffffff, channels
  outside 1..8) leaves an empty file, as raylib's `qoa_write` opens the file
  first, and fails.

Jonlib contracts where raylib's behavior is not defined: files whose frames
decode past the declared sample count (raylib writes past its buffer), with
more than 8 channels (past its LMS state) or more than 2^24 samples are
`InvalidWaveData`; a wave whose sample list does not hold `frames * channels`
samples is not encoded (`InvalidWaveRequest`).

## WaveFormat

`Wave.format_for` follows the miniaudio v0.11.24 code raylib's `WaveFormat`
reaches (`src/convert.bend`, `src/resampler.bend`, `src/lowpass.bend`):
`ma_convert_frames` with no dither, linear resampling with a low-pass filter
of order 4, NULL (default) channel maps and the default rectangular mixing.
Sample size 8 is u8, 16 is s16, anything else f32 (Jonlib accepts only 32).

- **Paths.** Equal formats, channels and rates copy the samples. Equal
  channels and rates convert each sample directly. Otherwise the channel
  converter and resampler run in the *mid* format (the output format if it is
  s16 or f32, else the input format if it is, else f32), with conversions to
  and from it; the resampler runs on the side with fewer channels
  (`channels_first` when the channel count does not grow).
- **Samples.** u8 to s16 `(x - 128) << 8`; u8 to f32
  `x * 0.00784313725490196078f - 1` (two roundings); s16 to u8
  `(x >> 8) + 128`; s16 to f32 `x * 2^-15`; f32 to u8 and s16 add a zero
  dither, clip to [-1, 1] and truncate `(x + 1) * 127.5` or `x * 32767`.
- **Channels.** Microsoft default maps (mono; FL FR; FL FR FC; FL FR FC BC;
  FL FR FC BL BR; FL FR FC LFE SL SR; FL FR FC LFE BC SL SR; then FL FR FC LFE
  BL BR SL SR, AUX_0.. from the ninth channel and NONE from the 33rd). One
  output channel averages the inputs: f32 sums in order and divides by the
  count; s16 divides the int sum by the unsigned count (C's usual conversions),
  so negative sums keep the low 16 bits of a large unsigned quotient, as raylib
  does. One input channel is copied to every output. Otherwise weights:
  1 for equal positions (NONE matches NONE), else miniaudio's rectangular plane
  weights (0, 1/4, 1/2) between spatial channels missing from the other map;
  s16 accumulates `(x * w) >> 12` clamped at every step, f32 adds `x * w` in
  input order.
- **Resampling.** Rates are reduced by their gcd. The output frame count is
  `ceil(frames * rout / rin)` (what
  `ma_linear_resampler_get_expected_output_frame_count` gives from the
  initial state); the resampler then loads input frames as
  they fall due (one before the first output frame), interpolates
  `x0 + (x1 - x0) * (tfrac / rout)` in f32 (separate statements, so never
  fused) or `(x0 * (4096 - a) + x1 * a) >> 12` with `a = (tfrac << 12) / rout`
  in s16 (U32 arithmetic), and advances by `rin / rout` with the fraction
  `rin % rout`. Downsampling filters each loaded frame, upsampling each output
  frame. The filter is two biquad sections (direct form 2 transposed) per
  channel; s16 sections use 2.14 fixed-point coefficients, int32 state and
  clamp their outputs.
- **Filter coefficients.** miniaudio computes them in binary64 with libm
  `sin` (`cos(x)` is `sin(pi/2 - x)`): `w = 2*pi*(min/2)/max` for the reduced
  rates, `q = 1/(2 cos((2i + 1) pi/8))` per section, then `b0 = b2 = (1 - c)/2`,
  `b1 = 1 - c`, `a1 = -2c`, `a2 = 1 - a`, `a = s/(2q)`, normalized by
  `a0 = 1 + a` and narrowed to binary32 (f32 filters) or truncated after
  scaling by 2^14 (s16 filters). Jonlib evaluates every binary64 operation
  through the checked helpers ([BINARY64.md](BINARY64.md), each rounding once)
  and replaces `sin` by a 128-bit fixed-point Taylor series (error below
  2^-110) rounded to the nearest double; every *faithful* libm `sin` returns
  that double or a neighbour. Each coefficient is evaluated at the corners of
  those brackets (it is monotone in `s`, `c` and each section's cosine) and is
  used only when all corners agree. This assumes the reference libm's `sin` is
  faithfully rounded (error below one ulp), as Apple's and glibc's are; the
  probe compares the resulting filters with raylib on every rate pair it runs.

### Profiles

Clang's default `-ffp-contract=on` fuses `a*b + c` within one expression. In
this path only the f32 biquad statements (`y = b0*x + r1`,
`r1 = b1*x - a1*y + r2`, `r2 = b2*x - a2*y`, fused as `fma(b0, x, r1)`,
`fma(b1, x, -(a1*y)) + r2` and `fma(b2, x, -(a2*y))`) and the f32 channel
weights (`out += x*w`, `fma(x, w, out)`) are affected; the f32 interpolation
and the sample conversions are separate statements. `M.Fused{}` reproduces
raylib as built by default on macOS arm64 and `M.Uncontracted{}` a build with
`-ffp-contract=off` or for baseline x86-64 (no FMA). miniaudio's SIMD
conversions only matter for f32 to s16, whose NEON/SSE2 blocks skip the clip
for 8-sample blocks of 16-byte-aligned buffers; the samples where that changes
the result are refused (below), so the result does not depend on alignment.
Dithering is off in this path.

### Refusals

raylib leaves the wave unchanged (Jonlib: `InvalidWaveRequest`, the wave
returned unchanged) when `ma_convert_frames` returns 0: no frames, zero input
or output channels, or a zero sample rate when the rates differ. Jonlib also
returns the unchanged wave with:

- `InvalidWaveRequest`: sample sizes other than 8, 16 and 32 (raylib reads or
  allocates with a different width than it converts) and sample lists that do
  not hold `frames * channels` samples;
- `InvalidWaveData`: NaN f32 samples when the conversion is not a plain copy
  (converting NaN to an integer is undefined, and f32 arithmetic on it is
  host-specific); NaN produced by the f32 arithmetic (for example from
  infinities), whose bits are the host's default NaN; signed int32 overflow in
  the s16 filter (undefined in C; full-scale square waves at nearly equal
  rates such as 44100 to 44101 reach it); f32 samples converted to s16 whose
  product with 32767 rounds to -32768 or below, 2^31 or above (including
  infinities), which the SIMD blocks convert differently from the scalar tail;
- `UnsupportedWaveFormat`: reduced rates of 2^31 or more (miniaudio's U32 time
  fraction would wrap), more than 2^24 output samples (Jonlib's bound, well
  below the point where raylib's unsigned allocation size wraps), chunked
  conversions (any format conversion around the channel converter or
  resampler, or both of them) whose 4096-byte buffers, counted for the larger
  channel count in the mid format, hold fewer frames than one output frame can
  need (rin/rout + 1 when resampling, 1 otherwise; such chunks end the
  conversion early or never advance), and filter coefficients the corner check
  cannot certify (for example the f32 filter for a 1:1000000 rate ratio).

## How it is verified

`tools/wav_probe.py` (gate `wav`) builds raylib with its audio module and
compares native `LoadWave` with `Wave.load` on 179 generated files covering
each case above in every container (PCM widths, float values next to the
rounding boundaries of `(c + 1) * 32767.5`, infinities and subnormals,
companded and extensible data, Wave64 sizes and GUIDs, RF64 `ds64` edge cases,
integral, fractional, unnormalized, negative and special AIFF rates, every
AIFC type, MS/IMA ADPCM with partial blocks, bad predictors and step indices,
negative deltas and small block alignments). For each file the native program
first runs dr_wav itself and reports when it reads fewer frames than raylib
allocates; those files must be `InvalidWaveData`, the others must match
exactly or fail on both sides. The other contracts above are checked on
Jonlib alone. Then `IsWaveValid`, `WaveCopy`, `WaveCrop` (in and out of
range), `LoadWaveSamples`, `ExportWave` to `.wav` and `.RAW` and
`ExportWaveAsCode` (the written bytes) on 8-, 16- and 32-bit waves, on CPU-1,
CPU-2 and JavaScript. `tools/qoa_probe.py` (gate `qoa`) compares native
`ExportWave(".qoa")` bytes with `Wave.write` on 13 waves (1 to 9 channels,
partial and multiple QOA frames, sines, noise, full-scale square waves,
silence and each refusal), then native `LoadWave` with `Wave.load` on those
encodings and 22 edits of them (truncations, changed frame headers, declared
totals above and below the data, bad magic, zero fields, `.QOA` names).
`tools/decimal_probe.py` (gate `decimal`) compares the
`%.Nf` formatter with native `printf` on 1024 values at 0, 1, 4, 6 and 9
decimals, including exact half-way ties, subnormals and the largest values.

`tools/wave_format_probe.py` (gates `wave-format` with the linked build's
contraction profile and `wave-format-uncontracted` with raylib compiled
`-ffp-contract=off`) runs native `WaveFormat` and `Wave.format_for` on 275
waves: every input/output format pair, 1 to 8 channels and 9 to 40 (AUX and
NONE positions), equal, up and down rates (44100/48000, 8000/44100,
48000/11025, 2:1, 3:7, 44100/44101, 12:1, 160:1, 1000000:1), 1 to 3 frame
waves, silence with both zeros, full-scale square waves, noise, sines,
out-of-range and subnormal floats, infinities and NaN. Every field and sample
must match on CPU-1, CPU-2 and JavaScript, and a wave raylib leaves unchanged
(its data pointer kept) must be refused unchanged. An independent Python
model of the same paths (exact binary32 rounding, libm `sin`) must equal
raylib on every case it converts and classifies the refusals above; at least
20 cases differ between the two profiles. Cases whose native result is
undefined or huge (wrong widths and lengths, 2^31 rates, 2^25 output samples)
are Jonlib contracts only.

The conversion's loops over samples and frames carry their results, so a
wave's length does not grow their depth: the examples' sounds (up to 48000
stereo frames out) convert on every lane, JavaScript included, through
`Sound.load` (gate `sound`, below).

Not yet available: OGG, MP3, FLAC, XM and MOD data, music and audio streams,
and the mixer (below). Gaps of `WaveFormat`: the refusals above, and no GPU
evidence.

## Audio device and sounds

An `AudioDevice` value is the state `raudio.c` keeps in its `AUDIO` global: whether
the device is ready, miniaudio's master volume factor, and the tracked audio
buffers in the order raudio tracks them. It is plain `Data` that a program
threads through the functions below; `AudioDevice.none()` is the state before
`InitAudioDevice`. (It is not Base's `Audio`, a host output that Jonlib does
not open yet.) The device is raylib's: 32-bit float samples, two channels,
48000 Hz. **Nothing is sent to a host device and no clock runs**: a sound
that plays advances only when the program asks for a device callback with
`AudioDevice.mix` ([below](#the-mixer)).

A `Sound{stream, frames}` is raylib's handle. Its `AudioStream{buffer, rate,
size, channels}` names a tracked buffer by number (0 is raylib's NULL;
buffers are numbered from 1 in the order they are made). A buffer has a
volume, a pitch, a pan, its playing and paused flags and a block of samples
(F32 bits, two per frame) that a sound and its aliases share.

| Function | raylib | Contract |
|---|---|---|
| `AudioDevice.init(device)` | `InitAudioDevice` | The device becomes ready with a master volume of 1. A ready device stays as it is (raylib initializes its mutex and device again in place). |
| `AudioDevice.close(device)` | `CloseAudioDevice` | A ready device becomes unready and its master volume 0; the buffers stay tracked, as raylib leaves them. |
| `AudioDevice.is_ready(device)` | `IsAudioDeviceReady` | |
| `AudioDevice.set_master_volume(device, volume)` / `master_volume` | `SetMasterVolume` / `GetMasterVolume` | Any volume that is not below 0 is kept (NaN included), ready device or not. |
| `Sound.load_from_wave_for(profile, device, wave)` / `load_from_wave` | `LoadSoundFromWave` | The wave converted as `WaveFormat(wave, 48000, 32, 2)` converts it (the same `ma_convert_frames` calls) in a new tracked buffer. `load_from_wave` uses `M.Uncontracted{}`. |
| `Sound.load_for(profile, device, path)` / `load` | `LoadSound` | `Wave.load` then the above. |
| `Sound.load_alias(device, source)` | `LoadSoundAlias` | A new tracked buffer with its own volume, pitch, pan and state over the source's block, and the source handle's frame count. |
| `Sound.is_valid(sound)` | `IsSoundValid` | Frames, buffer, sample rate, sample size and channels all nonzero. |
| `Sound.unload(device, sound)` | `UnloadSound` | The buffer is untracked and its block freed, even a block other buffers still play. |
| `Sound.unload_alias(device, alias)` | `UnloadSoundAlias` | The buffer is untracked; its block stays. |
| `Sound.play` / `stop` / `pause` / `resume` | `PlaySound` ... | Play: playing from the first frame, not paused. Stop: a playing buffer stops, back at its first frame; a paused one stays as it is (raylib only stops buffers that are playing and not paused). |
| `Sound.is_playing(device, sound)` | `IsSoundPlaying` | Playing and not paused; false again once the mixer reached the buffer's end. |
| `AudioDevice.mix(device, frames)` | (the device's data callback) | One callback of `frames` frames, [below](#the-mixer). |
| `Sound.set_volume` / `set_pitch` / `set_pan` | `SetSoundVolume` ... | Any volume; pitches above 0; pans clamped to -1..1 (NaN stays). |
| `Sound.update(device, sound, data, frames)` | `UpdateSound` | The buffer stops and the first `frames` frames of its block become `data` (F32 bits, two per frame), for every buffer over that block. |
| `Sound.data(device, sound)` | (the buffer's memory) | The samples a sound's buffer plays, if it has any. |

`Sound.load_from_wave` and `Sound.load` return the `AudioDevice` and a
`Result`:

- **The zero sound** (`Sound.none()`, nothing tracked) for the zero wave
  (frames, rate, size and channels 0 and no samples), which stands for
  raylib's failed `LoadWave` and its NULL data.
- **An invalid sound over an empty tracked buffer** for a wave that converts
  to no frames: no frames, no channels, or a zero rate.
- `SoundDeviceNotReady` on an unready device, where raylib converts to the
  zeroed device's rate and tracks through a mutex that does not exist.
- `SoundWaveError` for a file `Wave.load` fails on (raylib returns the zero
  sound: missing files, bad data; and OGG, MP3, FLAC, XM and MOD files,
  which raylib loads and Jonlib does not yet) and for a wave `WaveFormat`
  refuses (above).

Steps raylib has no defined answer for leave the `AudioDevice` as it is, and
`Sound.load_alias` then gives the zero sound: every buffer operation on an
unready device (raylib locks a mutex that does not exist); a handle whose
buffer is 0 where raylib dereferences it (`LoadSoundAlias`) or whose buffer
was unloaded (freed memory); an alias of a buffer whose block was freed;
`UpdateSound` past the buffer, with a negative count, from a list that is not
`2*frames` long, on a freed block or on a buffer without samples; and a pitch
whose output rate `48000/pitch` does not fit an unsigned int (raylib's cast is
undefined).

### Audio streams

An audio stream is a tracked buffer of two halves in the stream's own format
(unsigned 8-bit, signed 16-bit as its 16-bit pattern, or F32 bits; one sample
per element, channels interleaved), with a converter from that format and
rate to the device's. The device plays one half while the program fills the
other: a half is *processed* once the device has read it through, and both
are at first.

| Function | raylib | Contract |
|---|---|---|
| `AudioDevice.set_stream_buffer_size_default(device, size)` | `SetAudioStreamBufferSizeDefault` | The frames of each half of streams loaded from now on (a C int as a U32 word); 0 is raylib's own size. |
| `AudioStream.load(device, rate, size, channels)` | `LoadAudioStream` | A buffer of two zeroed halves, each of the default size, or 12800 frames without one (the device rate/30 times raylib's 8 "bits per sample"), and at least the device's period of 480. The resampler runs from the stream's rate, on the stream's channels (two at most). |
| `AudioStream.is_valid(stream)` | `IsAudioStreamValid` | A buffer and a rate, size and channels that are not 0. |
| `AudioStream.unload(device, stream)` | `UnloadAudioStream` | The buffer is untracked and its halves freed. |
| `AudioStream.update(device, stream, data, frames)` | `UpdateAudioStream` | The first processed half takes `frames` frames of `data` and zeros after them, and is no longer processed; with both halves processed the cursor goes back to the first frame. Nothing when no half is processed. More frames than a half holds (a negative int too) only move the cursor. |
| `AudioStream.is_processed(device, stream)` | `IsAudioStreamProcessed` | One of the halves is processed. |
| `AudioStream.play` / `stop` / `pause` / `resume` / `is_playing` | `PlayAudioStream` ... | As for a sound; a play and a stop mark both halves processed. |
| `AudioStream.set_volume` / `set_pitch` / `set_pan` | `SetAudioStreamVolume` ... | As for a sound; the pitch sets the converter's output rate against the stream's own rate. |

`AudioStream.load` gives a stream without a buffer (0, with the fields
given) where miniaudio makes no converter: an unready device, a rate of 0,
no channels. Jonlib also gives none for sample sizes other than 8, 16 and 32
(raylib takes them for 32-bit float and fills part of each sample), a
default size that is a negative int, and buffers of more than 2^22 samples.
`AudioStream.update` leaves the state as it is on an unready device, for a
buffer that is 0, not tracked or a sound's (raylib writes the sound's
samples as if they were a stream's), and for a `data` that does not hold
`frames*channels` samples. `Sound.update` leaves a stream's buffer as it is.

**The mixer does not play streams yet**: a callback with a playing stream is
refused. What is missing is raudio's reading of the two halves and the
converter from the stream's format and channels.

### The mixer

`AudioDevice.mix(device, frames)` is one data callback of the device, as
raudio's `OnSendAudioDataToDevice` mixes it and miniaudio then finishes it,
in uncontracted binary32 arithmetic (raylib compiled with
`-ffp-contract=off`, or a host without FMA). It returns the device and the
callback's samples (F32 bits, two per frame). A device asks for one period
at a time (480 frames on miniaudio's null backend); the program chooses.

- Every buffer that is playing and not paused takes part, in tracked order.
  It gives the frames left before its end, at most `frames`, then stops
  (not playing, back at its first frame).
- Its frames go through its converter's resampler (`src/mixer.bend`), which
  holds two frames and, at the device rate, gives the frame *before* the one
  it just read: a sound comes out one frame late, its last frame is never
  heard, and the held frames stay for the next `PlaySound` (its first output
  is the last frame the buffer read before, not silence).
- A pitch resamples: `SetSoundPitch` sets the converter's output rate to
  `(unsigned int)(48000/pitch)` (a rate of 0 is refused and the last one
  stays), the rates reduced by their divisor, the resampler's timer rescaled
  to the new rate, and the filter's coefficient changed with its register
  kept. The filter is miniaudio's **first-order** low-pass,
  `y = (1 - a)*x + a*y1` with `a = (float)exp(-2*pi*(min*0.5)/max)`: a data
  converter's resampler has order 1, not the order 4 that `WaveFormat` gets
  through `ma_convert_frames`. It filters the input when the pitch is above
  1 and the output when it is below, and not at 1:1.
- raudio asks the buffer for `(unsigned int)(((float)48000/rate)*frames)`
  input frames (at least 1, at most the 512 of its input buffer) each time
  the converter needs more; frames the converter did not take wait in a
  residual of at most 8 frames (more are lost), which is fed first the next
  time, on the next `PlaySound` too.
- raudio reads a static buffer in runs of 512 frames and takes a cursor past
  two halves of the buffer (`size/2` frames each) for its end: a run that
  starts on the last frame of a buffer of an odd size (3 frames and more)
  reads nothing and stops it.
- Each frame is scaled by the levels of `MixAudioFrames`: with `right =
  (pan + 1)/2` and `left = 1 - right`, `volume*0.5*side*(3 - side*side)` for
  each side, and added to the mix.
- Then the master volume, when it is not 1, and miniaudio's clip to -1..1.

A callback Jonlib does not mix returns `None` and the device as it was: an
unready device; no frames, or more than 2^20; a playing buffer without
frames (raudio divides by its size), one whose samples were freed, or one
whose rate Jonlib does not resample (a reduced output rate of 2^31 and more;
a filter coefficient that is not certified: `exp` is bracketed by a
fixed-point series between the two neighbours of the nearest double, and
both must give the same binary32); and a callback in which a subnormal or a
NaN takes part or results
(inside the callback miniaudio flushes subnormals to zero on x86 hosts only,
and the bits of a NaN are the host's).

### How it is verified

`tools/sound_probe.py` (gate `sound`) compiles `raudio.c` itself into the
reference program, with `-ffp-contract=off` and only miniaudio's null
backend, so that the program can read `AUDIO` and the audio buffers, and
stops the device right after `InitAudioDevice`: its thread mixes nothing,
and the program asks for each callback itself
(`ma_device_handle_backend_data_callback`) with the script's frame counts.
86 scripts of 785 steps over four sound slots run on both sides and on a
Python model of raudio's state; after every step the ready flag, the master
volume bits, every slot's handle fields with `IsSoundValid` and
`IsSoundPlaying`, and every tracked buffer (its number, block, size, volume,
pitch and pan bits, flags, an FNV-1a hash of its samples, its converter's
input and output rates, its cursor, the resampler's timer, the two frames it
holds, the filter's register and coefficient, the residual, and for a
stream its format, channels and the two processed flags) must be equal,
with the default stream size, `IsAudioStreamValid` and
`IsAudioStreamProcessed` for every slot, and after a callback the hash of
its samples. The callbacks cover
silence, sounds mixed to their end in callbacks of 1 to 30000 frames,
replays over the held frames, pauses, levels for volumes and pans (negative
and above 1), the master volume and the clip, three buffers at once with an
alias, odd sizes (the lost last frame, at the start of a callback and of a
512-frame run), pitches that leave the converter at the device rate, an
updated block and a 29647-frame file; and pitched buffers: 2:1 and 1:2,
3:2, 4:5, 9600:9599, 3.7 and 0.07 (48000:12972 and 48000:685714), pitches
changed in the middle of a sound and while it is paused, three buffers at
three pitches, a 513-frame buffer at 2.5 and 0.4, and the file at 1.25.
The streams: 8-, 16- and 32-bit ones of 1, 2, 3, 6, 255 and 1000 channels
at 8000 to 96000 Hz; default sizes of 100, 479, 480, 500, 600 and 0; an
unready device, a rate of 0 and no channels; updates of each format into
each half, of no frames, of a whole half, of one frame too many and of a
negative count, with no half left, after a play, a stop and a pause; and
pitches against 44100, 48000 and 8000 Hz streams (147:80, 147:160, 1:2,
1:1). The waves are
8-, 16- and 32-bit, of 1, 2, 4 and 6 channels, at 48000, 8000, 22050, 44100
and 96000 Hz, with the empty cases above, and the files are the four `.wav`
files of the examples that only play sounds (`boom`, `buttonfx`, `sound`,
`coin`; 26522 to 48000 frames each), a small generated one, a missing one,
one that is not a WAV and another extension. 55 scripts are compared with
raylib; the 31 with a step raylib has no defined answer for, or a step or
a callback Jonlib refuses, are checked against the model on Jonlib alone. `IsSoundPlaying` is asked of raylib only on
a ready device and for a tracked buffer, and no script opens the device over
a playing buffer (raylib would mix it before the reference can stop it). CPU-1,
CPU-2 and JavaScript.

The examples that play sounds without showing audio state
(`textures_sprite_button`, `textures_sprite_explosion`, `audio_sound_multi`,
`audio_sound_positioning`) replay against the native example with
`raudio.c` compiled beside it the same way (`tools/examples_probe.py`): its
device mixes on its own thread there, and no frame depends on it.

Not yet available: the fused (FMA) profile of the mixer, the hosts'
subnormal profiles (a filter's tail that decays into subnormals is refused),
a clock (the program asks for each callback), playing audio streams
(their state is here), stream callbacks and processors, music, and a host
device. No GPU evidence.
