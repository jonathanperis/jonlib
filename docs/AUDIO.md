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

Not yet available: OGG, MP3, FLAC, XM and MOD data, `WaveFormat`
(miniaudio's format, channel and sample-rate conversion), and sounds, music
and audio devices.
