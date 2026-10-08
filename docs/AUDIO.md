# Audio waves

Jonlib adapts raylib 6.0's `raudio.c` Wave functions as `Wave.*` in
`jonlib.bend`. A `Wave{frames, rate, size, channels, data}` holds raylib's
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

Sample sizes other than 8, 16 and 32 are `InvalidWaveRequest` for crop, samples
and export.

## WAV decoding

`src/wav.bend` follows `drwav_init_memory` and `drwav_read_pcm_frames_s16`
exactly for RIFF files: the chunk walk with dr_wav's stream position (including
a `fmt ` chunk shorter than 16 bytes, which reads into the next chunk, and the
relative seek to a chunk's declared end), padding, LIST/fact/unknown chunks,
seeks past the end that end the walk, `WAVE_FORMAT_EXTENSIBLE` headers (a
22-byte extension whose subformat selects the codec), the rate/channel/bit
limits, a data size clipped to the file and rounded down to whole frames, and
an empty data chunk (a Wave with 0 frames, which `IsWaveValid` rejects). PCM
samples of 1 byte are recentred, of 2 to 8 bytes keep their top two bytes and
above 8 bytes are 0; 32-bit float samples are clamped to [-1, 1], offset by 1,
scaled by 32767.5 in single precision and truncated; a-law and mu-law use
dr_wav's tables.

Jonlib contracts where raylib behaves differently or not definedly:

- RIFX, Wave64, RF64 and AIFF containers, MS/IMA ADPCM and 64-bit float data
  are `UnsupportedWaveFormat` (dr_wav decodes them; not ported yet);
- data dr_wav reads no frames from (other format tags, sample widths that do
  not divide a frame) and NaN float samples are `InvalidWaveData`: raylib
  returns uninitialized samples for the first and converts NaN with an
  undefined float-to-int cast.

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

## How it is verified

`tools/wav_probe.py` (gate `wav`) builds raylib with its audio module and
compares native `LoadWave` with `Wave.load` on 36 generated files covering
each case above, then `IsWaveValid`, `WaveCopy`, `WaveCrop` (in and out of
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

Not yet available: OGG, MP3, FLAC, XM and MOD data, `WaveFormat`
(miniaudio's format, channel and sample-rate conversion), and sounds, music
and audio devices.
