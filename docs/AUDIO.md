# Audio waves and sounds

Jonlib adapts raylib 6.0's `raudio.c` Wave functions as `Wave.*` in
`jonlib.bend`, and its device and Sound functions as `AudioDevice.*` and `Sound.*`
([below](#audio-device-and-sounds)). A `Wave{frames, rate, size, channels, data}` holds raylib's
fields and its interleaved samples, one per element: unsigned 8-bit, signed
16-bit (stored as the 16-bit pattern) or F32 bits for sample sizes 8, 16 and 32.
It is plain `Data`: copying a Wave copies its samples.

| Function | raylib | Contract |
|---|---|---|
| `Wave.decode_for(libm, file_type, bytes)` / `decode` | `LoadWaveFromMemory` | `.wav`/`.WAV`, `.qoa`/`.QOA` and `.ogg`/`.OGG` data as 16-bit samples and `.mp3`/`.MP3` data as 32-bit float samples (below). Other tokens are `UnsupportedWaveFormat`. `libm` is the profile an Ogg Vorbis stream's tables are taken under; `decode` uses `M.AppleLibm{}`. |
| `Wave.load_for(libm, path)` / `load` | `LoadWave` | The file's bytes decoded by its extension; file errors are `WaveFileError`. |
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

## MP3 (in progress)

`src/mp3.bend` is the start of an adaptation of dr_mp3 (pinned raylib's
`src/external/dr_mp3.h`; its decoder is minimp3). It reads a file's frames
without decoding their samples, which is what opening a stream and counting
its frames take; `src/mp3_layer3.bend` decodes a Layer III frame to its
16-bit samples; `src/mp3_stream.bend` is the two together, a stream read
and sought as raylib's music and waves do it (all below). `Music` plays
MP3 files through it (see Music streams), and `Wave` and `Sound` load them
(below).

- **Headers** (`drmp3_hdr_*`): validity, whether two headers are of one
  stream, bit rate, sample rate, samples and bytes of a frame, padding.
- **The search for a frame** (`drmp3d_find_frame`, `drmp3d_match_frame`):
  the first header from which up to ten frames of its stream follow one
  another in the bytes at hand, or that fills them exactly; a free-format
  frame's size is found by looking for the next two headers.
- **Layer III side information** (`drmp3_L3_read_side_info`) and the **bit
  reservoir**'s bytes (`drmp3_L3_restore_reservoir`,
  `drmp3_L3_save_reservoir`): a frame whose main data begins in bytes the
  reservoir does not hold decodes nothing, as in dr_mp3.
- **The stream** (`drmp3_init`, `drmp3_decode_next_frame_ex__callbacks`): an
  ID3v1 tag and an APE tag at the end are left out, an ID3v2 tag at the
  start is passed, the file is read through dr_mp3's buffer (filled to
  64 KiB when below 16 KiB: it bounds how far the search can look), and the
  first frame that decodes gives the channels and the sample rate. An Xing
  or Info frame is not played: the stream starts after it, with the frames
  it counts and LAME's delay and padding.
- **The count** (`drmp3_get_pcm_frame_count`): the tag's frames times the
  first frame's samples, less the delay and the padding; without a tag,
  every frame of the stream.

dr_mp3 keeps its own idea of the read position (`streamCursor`), which goes
back to the stream's start after an Xing/Info frame while the file does
not: until a seek, its reads may then go that far past a tag at the file's
end. `Mp3.Stream` keeps both positions. It reads the first frame as Layer
III side information whatever its layer, and from the first byte it used
rather than from the frame's header when bytes were skipped before it: so
does `Mp3.info.first`.

`tools/mp3_probe.py` (gate `mp3`) compares with dr_mp3 itself, per file:
whether it opens, channels, sample rate, delay, padding, the offset the
frames start at, the tag's count, whether the first frame stays to be
played, `drmp3_get_pcm_frame_count` and `drmp3_get_mp3_and_pcm_frame_count`.
There is no MP3 encoder here, so the 85 files are raylib's `country.mp3`
(MPEG-1 Layer III, 128 kbit/s, 44100 Hz, joint stereo, an Info frame with a
LAME tag; 3583 frames, 4125934 PCM frames) and edits of its first frames:
without the Info frame, cut inside a frame, one and two frames, bytes that
are no frame before and inside the stream, ID3v2 tags with and without a
footer and one longer than the file, ID3v1 and APE tags (one claiming a
megabyte), another sample rate in one header, every header rewritten (free
format, with a CRC, mono, MPEG-2, MPEG-2.5, Layers I and II, the reserved
layer, bit rate and sample rate), an Xing name, an Info frame without
flags and without a LAME tag, files too short to open, 5000 zeros, and 48
seeded edits (bytes changed, removed and inserted). 64 open and 21 do not,
on both sides. CPU-1, CPU-2 and JavaScript.

### Layer III: from the bits to the samples

`src/mp3_layer3.bend` is `drmp3dec_decode_frame` with its samples wanted:
for each channel of each granule the
scalefactors (`drmp3_L3_decode_scalefactors`) and the 576 values the
Huffman codes give (`drmp3_L3_huffman`, `drmp3_L3_pow_43`), which are
already floats (a value is its table entry or `pow_43` times the band's
scale); the granule's mid/side or intensity stereo; then for each channel
the reorder of its short bands, the alias reduction, the IMDCT over the
channel's overlap and the sign change, which leave 32 subbands of 18
samples in time; and the synthesis filter (`drmp3d_synth_granule`), which
makes each granule's 576 samples a channel. `Mp3L3.decode(decoder, bytes,
count)` gives the decoder after the frame, the frame's sample count and
bytes, the subband samples of every channel of every granule as binary32
bits, and the frame's PCM: 16-bit samples as dr_mp3 writes them (raylib
builds it without `DR_MP3_FLOAT_OUTPUT`), a frame a channel after a
channel. Both are equal to dr_mp3's bit for bit.

- **The tables** are `src/mp3_tables.bend`, generated by
  `tools/mp3_tables.py` from the header's own text: each `static const`
  table is compiled into a C program that prints its elements, a float as
  the bits the C compiler gives its literal. The tool also checks what the
  port relies on (band widths even and 576 in all, Huffman trees at most
  six entries deep and inside `tabs`, no cache shift of 32 bits) and the
  gate fails when the module is not what the pinned header generates.
- **The scales** are floats: `drmp3_L3_ldexp_q2` multiplies in steps, in
  dr_mp3's order. The 40 scales stay in the decoder between granules: a
  granule writes its bands', and the 8 kHz mixed-block table has three
  bands more than a mixed granule writes, whose scales are the ones a
  granule before left.
- **The values** are read through a 32-bit cache as dr_mp3 reads them. The
  big values have no end but their count, so a damaged granule reads past
  its own bits: into the next granule's, then past the frame's main data
  into what earlier frames left in the decoder's 2815-byte array, which the
  port keeps (`Decoder.main`) and reads the same. Past the array itself
  dr_mp3 reads the granule information that follows it in its struct, which
  is undefined: there the frame is refused (`status` 1). That takes a
  free-format frame of the largest size and 288 pairs of the longest
  escapes; the gate builds one.
- **Stereo.** Mid/side (`drmp3_L3_midside_stereo`) is a sum and a
  difference, in a joint stereo frame with that bit and without the
  intensity bit. With the intensity bit `drmp3_L3_intensity_stereo` runs,
  band by band (`drmp3_L3_stereo_process`): a band past the right channel's
  top band of its window, whose intensity position is below 7 (MPEG-1) or
  64, has its left values scaled into both channels (`g_pan`, or in MPEG-2
  a power of two by quarters, `drmp3_L3_ldexp_q2`); another band is
  mid/side when the header's mid/side bit is set, and otherwise stays. The
  SSE path of the sum and difference computes the same floats as the
  scalar one.
- **What dr_mp3 tests is the bit, not the mode.** The intensity bit of a
  plain stereo, dual channel or mono frame runs the intensity step too. A
  mono frame's right channel is 576 zeros, so every band is an intensity
  band and the mono values are scaled by their position's `kl`. In MPEG-2
  the scale's shift is the low bit of `scalefac_compress` in the granule
  information's second slot, the right channel's; a mono frame does not
  write that slot, so it reads what the last stereo frame left there (0 in
  a zeroed decoder). `Decoder.compress` keeps it, written as
  `drmp3_L3_read_side_info` writes it: only when the reader comes to the
  second granule, after its check of `big_values`.
- **Intensity positions.** A granule's scalefactors are also its channel's
  intensity positions, kept for the granules that `scfsi` lets reuse them.
  `drmp3_L3_intensity_stereo` writes the right channel's last positions
  from that channel's top bands before it uses them (`Mp3L3.positions`),
  and they stay in the decoder.
- **The filter bank's first half** (`Mp3L3.filter`). `drmp3_L3_reorder`
  interleaves the three windows of each short band. `drmp3_L3_antialias`
  rotates the eight values on each side of a boundary between long
  subbands: all 31 boundaries, or only those inside a mixed block's long
  part. `drmp3_L3_imdct_gr` transforms a subband at a time,
  `drmp3_L3_imdct36` (with `drmp3_L3_dct3_9`) for long, start and stop
  blocks and three `drmp3_L3_imdct12` for a short one, each adding the
  half the granule before left in the channel's overlap and leaving its
  own: 288 floats a channel that stay in the decoder
  (`Decoder.overlap0`, `overlap1`). `drmp3_L3_change_sign` turns the odd
  samples of the odd subbands. Every float operation is in dr_mp3's order;
  its SSE paths here compute each element by the scalar formula, so the
  two agree. A negation is the sign bit turned, as C's is (a subtraction
  from zero would lose a zero's sign). The cosines of `dct3_9` and `idct3`
  are literals in the code, not tables: `tools/mp3_tables.py` checks that
  each is in the header and has the C compiler convert it.
- **The synthesis filter** (`Mp3L3.synth.granule`). `drmp3d_DCT_II`
  turns each time slot's 32 subband samples into 32 values; `drmp3d_synth`
  takes two slots at a time, writes them into rows of 64 floats and sums
  sixteen rows under `g_win` for each sample; the fifteen newest rows stay
  in the decoder (`qmf_state`, `Decoder.qmf`). This is where raylib's build
  matters: with SSE the DCT's last sums are associated differently from
  the scalar code, and the window's sums are clamped and rounded by the
  processor (`_mm_cvtps_epi32`: to nearest, a tie to the even integer),
  while the two samples of each slot that `drmp3d_synth_pair` computes
  alone go through `drmp3d_scale_pcm` (half added, truncated, one less
  below zero). The port follows the SSE branches, a time slot at a time
  (the vector code works on four slots that do not mix), and does the
  rounding with integers on the float's bits.
- **A mono frame** runs the stereo code with its one channel as both, and
  `drmp3d_synth_granule` then copies back every other float of the rows:
  the right channel's entries keep what the frames before left, in place.
  `Mp3L3.rows.merged` does the same, so a stereo frame after mono ones
  reads the same history.
- **Two things dr_mp3 reads and does not use.** Its SSE DCT loads four
  slots at a time and, for a channel's last two, two floats past its 576
  values. And the newest row of `qmf_state` has thirty entries that the
  next call writes before anything reads them; until then dr_mp3 has there
  whatever its scratch held. Neither changes a sample; the gate leaves
  those thirty floats out of its hash and the port keeps zeros there.
- **Mixed blocks at 8000 Hz** are refused (`status` 1). dr_mp3 reorders a
  granule's short bands from the end of its long part, which it takes to be
  72 values at 8000 Hz; its band table for mixed blocks there has 48 long
  values and 528 short ones, so the reorder ends 24 values past the
  granule's 576 and is written over the other channel's values or over the
  scales (`Mp3L3.reorder.inside`). Every other table ends at 576.
- **Layers I and II** are decoded by dr_mp3 and not here yet: such a frame
  is refused (`status` 2).

`drmp3_read_pcm_frames_f32`, which raylib's music and waves call, converts
the 16-bit samples to floats afterwards (a division by 32768): see the
stream, below.

`tools/mp3_layer3_probe.py` (gate `mp3-layer3`) runs dr_mp3's frame
function over each file, with the three functions on the way to the values
copied from the header and three lines put in: a hash of each channel's 576
subband samples after the sign change, whether the Huffman reader left the
array, and whether a reorder would end past the granule. After every frame
both sides give the sample count, the bytes used, a hash of everything the
decoder keeps (header, free format size, reservoir, the whole main data
array, the 40 scales, the intensity positions, the second slot's
`scalefac_compress`, both channels' overlap, the synthesis rows), a hash
of the subband samples and a hash of the 16-bit samples.
The 118 files: 400 frames of `country.mp3` (its first 200 and 200 from the
middle), the `mp3` gate's 84 edits, and 32 synthetic files. A synthetic frame is a valid header, side
information written field by field by a seeded generator, and random main
data (bits set with probability 0.5, 0.2 or 0.8): MPEG-1, MPEG-2 and
MPEG-2.5 at each of their three sample rates, with the mode, the CRC, the
bit rate and the padding changing from frame to frame, free-format
streams, short, mixed, start and stop blocks, every table, reservoirs that
are short and side information dr_mp3 refuses (mixed blocks at 8000 Hz in
one stream only, which ends there); two files of Layer I and II frames; and
the stream built to leave the array. Two files are refused and two stop at
another layer, on both sides. CPU-1, CPU-2 and JavaScript.

The whole of `country.mp3` (3584 frames) was in this gate until the
synthesis: every frame's state and subband samples matched on the three
lanes. With the synthesis it was decoded once more on the JavaScript
target, by hand (2026-10-12): all 3584 frames' PCM equal dr_mp3's. That
took eleven minutes, about 185 ms a frame, which is why the gate now has
slices. Most of that time was one thing: the module keeps floats in lists
as their bits, and turning bits into a float through the type's
constructor is very slow on that target (the compiler goes through a list
of 32 bits). `Mp3L3.float` now makes a finite float by arithmetic instead:
its significand as an integer times the power of two of its exponent, a
factor for each bit of the power. Every step is exact (the partial
products are multiples of 2^-149 below 2^128), so no result changes, and a
frame takes about 95 ms there. Keeping floats as floats in the lists would
save the rest of the conversions; that is a larger change to the module.

### The stream: reading and seeking

`src/mp3_stream.bend` is dr_mp3's `drmp3` as raylib uses it. `Mp3S.Player`
holds the file through dr_mp3's buffer (`Mp3.Stream`), the decoder, the
samples of the MP3 frame at hand and how many of them were handed out.

- **`Mp3S.open`** is `drmp3_init_file`: `Mp3.open`, with the first frame
  decoded to its samples. An Xing/Info frame is not played.
- **`Mp3S.read.s16` and `Mp3S.read.f32`** are `drmp3_read_pcm_frames_s16`
  and `_f32` (`drmp3_read_pcm_frames_raw`). A read first passes the frames
  of the LAME delay; then it hands out the frame at hand's samples and
  decodes the next, until it has what was asked, the stream ends, or, with
  an Xing/Info total, the count reaches the total less the padding. The
  floats are the 16-bit samples over 32768.
- **`Mp3S.rewind`** is `drmp3_seek_to_start_of_stream`, which raylib calls
  to stop and to loop a music: the file's position, an empty buffer, no
  frame at hand and the decoder's header cleared, so that the next frame
  is searched for in a zeroed decoder.
- **`Mp3S.seek`** is `drmp3_seek_to_pcm_frame` without a seek table: frame
  0 is the start; a frame past the count is read up to; one before it is
  read up to from the start. Every frame on the way is decoded.
- **`Mp3S.total`** is `drmp3_get_pcm_frame_count`, raylib's
  `music.frameCount`: the tag's count less the delay and the padding, or
  every frame counted.

Three things dr_mp3 does that follow from its bookkeeping and are kept:

- `currentPCMFrame` counts the delay's frames and a read does not. A seek
  compares the frame asked for with that count and then reads that many
  frames more: in a file with a LAME delay of 1105, a seek to frame 500
  from the start leaves the count at 1605, and it is the 500th frame read,
  not the stream's 500th.
- Without an Xing/Info count, `drmp3_get_pcm_frame_count` scans the stream
  and then seeks back from the start to the count it found: the frame at
  hand is dropped and decoded again by the next read.
- A read copies as many samples a frame as the stream has channels, from
  where the MP3 frame's own channel count puts it: where a mono frame is
  in a stereo stream, what follows its samples in dr_mp3's buffer (the
  frame before's) is read too. `Player.pcm` is that buffer.

A stream stops (`Player.status`) at a frame the decoder refuses: 1 where
dr_mp3 leaves one of its arrays, 2 at a Layer I or II frame, which is not
decoded yet.

`tools/mp3_stream_probe.py` (gate `mp3-stream`) runs one script on each of
the `mp3` gate's 85 files through dr_mp3's functions and through
`Mp3S`: a count, reads of 100 16-bit, 1000 float and 2000 16-bit frames,
a seek back to 500, a read, a seek to where the count stands, the start, a
float read, a seek forward to 3000, a read, a count, and a last read (of
20000 frames in 18 of the files: 17 of them end before that). After each
operation both sides
give its result (frames read and a hash of the samples, of the floats'
bits for a float read) and `currentPCMFrame`, the frames left and consumed
of the frame at hand and its channels. Each file is opened as a file and
from memory (below), and 17 of them are also read straight to their end
both ways: 204 streams, 1698 operations; 64 files run the script and 21
do not open, on both sides. CPU-1, CPU-2 and JavaScript.

**Files and memory.** dr_mp3 reads a stream opened from a file
(`drmp3_init_file`, which `LoadMusicStream` calls) through a buffer its
callbacks fill, and one opened from memory (`drmp3_init_memory`:
`LoadWave`, `LoadSound` and `LoadMusicStreamFromMemory`) with another
function, which decodes each frame from all the bytes left. `Mp3S.open` is
the first and `Mp3S.open.memory` the second (`H.Stream`, whose `cap` tells
them apart). They do not always end a stream alike. After an Xing/Info
frame the buffered path counts its position from the stream's start again
while the file stays where it is, so its reads go that many bytes past the
stream's length: into an ID3v1 tag, whose bytes then follow the last frame,
which is no frame for it (minimp3 wants the header of the next one, or the
data's end). A memory stream ends before its tags and keeps the frame.
`first12` with an ID3v1 tag has 10415 frames read as a file and 11567 from
memory. A seek to the stream's start puts the buffered path right, so the
gate's script alone hides it: the dozen-frame files are also read straight
to their end, both ways (204 streams in all).

**Waves and sounds.** `Wave.decode(".mp3", bytes)` is
`drmp3_open_memory_and_read_pcm_frames_f32`: the memory stream's every
frame, as 32-bit float samples (raylib's build decodes 16-bit samples and
divides by 32768), with the channels and sample rate of the stream's first
frame. `tools/mp3_wave_probe.py` (gate `mp3-wave`) compares `Wave.load`
with raylib's `LoadWave` on the `mp3` gate's files without the whole
`country.mp3` (84, and one under `.MP3`): 62 waves (431318 frames: count,
rate, size, channels and a hash of the samples' bits) and 23 files without
one, and for each wave the frames of the `Sound` made of it
(`LoadSoundFromWave` on an open device). There is no wave where dr_mp3
opens no stream or reads no frame (`InvalidWaveData`), nor for a stream
that stops at a frame dr_mp3 decodes by leaving one of its arrays; a
stream with a Layer I or II frame is `UnsupportedWaveFormat`. The whole
file is 3584 MP3 frames: about six minutes in the JavaScript lane, so
it is in no gate as a wave (its frames are in `mp3-layer3`).

Still to come: Layers I and II.

raylib builds dr_mp3 with its SSE paths, whose samples differ from the
scalar ones: the reference for the samples is the build as it is.

## Ogg Vorbis

`src/vorbis_codebook.bend`, `src/vorbis_ogg.bend`,
`src/vorbis_setup.bend`, `src/vorbis_maps.bend`,
`src/vorbis_tables.bend`, `src/vorbis_decode.bend`,
`src/vorbis_mdct.bend`, `src/vorbis_residue.bend`,
`src/vorbis_floor.bend`, `src/vorbis_packet.bend`,
`src/vorbis_frame.bend` and `src/vorbis_length.bend` are an adaptation of
stb_vorbis
v1.22 (pinned raylib's
`src/external/stb_vorbis.c`), which raylib's `LoadWave`, `LoadSound` and
`LoadMusicStream` call for `.ogg` files. Waves and sounds are loaded
(*Waves and sounds*, at the section's end); music is not yet. What is here
is the reading of the data, the whole setup header, the transform's
tables, the decoding of a codebook's symbols and vectors, the inverse
MDCT, the residues, a floor's curve, the decoding of a packet into its
block of floats, the frames and their 16-bit samples, the stream's length
(all below) and what the setup makes
of a codebook's code lengths, once it has read them:

- **The codes** (`compute_codewords`; `codewords`, and `book.of` for all the tables). A length is 1 to
  31 bits, or 255 for a symbol without a code. The first symbol with a code
  takes 0; each later one takes the lowest free leaf at its length or above
  and leaves free the leaves beside its path. Lengths that ask for more
  codes than a tree has are no codebook (`None`; stb_vorbis's
  `VORBIS_invalid_setup`). A tree with leaves left over is one, as in
  stb_vorbis. The codes are kept as stb_vorbis keeps them, the first bit
  read lowest.
- **The sorted table** (`compute_sorted_huffman`): the codes read the other
  way (`bit_reverse`), ascending, with the sentinel `0xffffffff` after
  them, and their symbols. A sparse codebook has all its codes there, and
  its lengths in that order; another has only the codes longer than 10
  bits (`STB_VORBIS_FAST_HUFFMAN_LENGTH`). stb_vorbis sorts with `qsort`:
  the codes are all different, so the order does not depend on the sort.
- **The accelerated table** (`compute_accelerated_huffman`): 1024 entries,
  the next 10 bits of the stream to the symbol whose code they begin with
  (its place in the sorted table for a sparse codebook), or -1. Its entries
  are shorts in raylib's build (`STB_VORBIS_FAST_HUFFMAN_SHORT`): a symbol
  from the 32767th on is left to the sorted table.
- **`float32_unpack`**, the packed floats of a codebook's values: a 21-bit
  mantissa, a 10-bit exponent and a sign, `ldexp(mantissa, exponent - 788)`
  narrowed to float. It is exact arithmetic here: the mantissa and the
  power of two are exact in binary64, and the narrowing is the one
  rounding (an infinity from 2^128, subnormals and zero below 2^-126).
- **`ilog`** and **`bit_reverse`**.
- **`lookup1_values(entries, dim)`** (`lookup1.values`): how many values a
  lookup of type 1 has per dimension, the largest `r` with `r^dim <=
  entries`. stb_vorbis does not compute that root. It estimates it as
  `floor(exp((float)log((float)entries)/dim))`, through the C library's
  binary64 `log` and `exp` with two float roundings between them, and then
  corrects the estimate by one, upward only: its answer is the root when
  the estimate is the root or one less, and -1 (an invalid setup)
  otherwise. The two roundings move the estimate by a factor of at most
  `e^(ln(entries)*2^-23)`, so:
  - for every codebook of up to 2^19 entries, and for a larger one of two
    dimensions or more that is not just under a perfect power (within
    17/2^23 of it: 34 entries under 4096^2), the estimate is surely within
    the correction and the answer is the root, computed here with
    integers;
  - elsewhere (one dimension and more than 2^19 entries; just under a
    large perfect power) the answer hangs on the last bits of the C
    library's `log` and `exp`: on this host 67% of those pairs are -1 and
    the rest the root. The port answers nothing (`None`), and the setup
    will refuse such a codebook;
  - the correction is `(int) floor(pow((float) r+1, dim)) <= entries`, a
    conversion to int of a power that is 2^31 or more for every codebook of
    31 dimensions or more, and for one of 20 to 23 dimensions whose root is
    2. C leaves that undefined (x86-64 makes it `INT_MIN`, and stb_vorbis
    then answers one more than the root). `None` too, as for a codebook
    with entries and no dimension (a conversion of an infinity or a NaN),
    which the setup refuses before it asks.

  `tools/reference/stb_vorbis_lookup1/exhaustive.c` checks the rule against
  stb_vorbis's function for every `entries` from 1 to 2^24 - 1 with 36
  dimensions: of 603,979,740 pairs the rule is sure of 368,526,909 and
  stb_vorbis answers the root on every one, with the C library's FMA
  variants and without them (glibc 2.39; `results/`). The gate compares
  6644 pairs with stb_vorbis and holds the port to `None` on 2171 others,
  where stb_vorbis is not called.

`tools/vorbis_codebook_probe.py` (gate `vorbis-codebook`) includes
stb_vorbis.c in its reference and calls those static functions on a
`Codebook` set up as `start_decoder` sets it up: 51 sets of lengths, each
as a sparse codebook and as one that is not (complete trees of up to 3000
symbols from seeded splits, in order and shuffled, with symbols without a
code, with leaves left over, a chain of every length to 31, a symbol past
the 32767th, lengths that are no tree), and 1443 words for the three scalar
functions. The floats are also checked against exact arithmetic in the
probe.

### The data: pages, packets and bits

`src/vorbis_ogg.bend` is how stb_vorbis reads a memory stream
(`stb_vorbis_open_memory`, which is what raylib opens), function by
function. A `Reader` holds what stb_vorbis keeps between calls and each
function gives it back with its C answer in `value`:

| stb_vorbis | Here | |
| --- | --- | --- |
| `get8`, `get32`, `getn`, `skip` | `get8`, `get32`, `getn`, `skip` | Bytes. Past the end a byte is 0 and `eof` is set; `getn` reads nothing where fewer bytes are left. |
| `start_page`, `start_page_no_capturepattern` | `page.start`, `page.begin` | "OggS" (read up to the first byte that is another: error 30), the version (31), the flags, the granule position, the sequence number and the segment table (10 where the data ends in it). The serial number and the checksum are passed over, as in stb_vorbis's pull API. |
| `start_packet`, `maybe_start_packet` | `packet.start`, `packet.maybe` | A packet begins on the page's next segment, or on the next page, which must not be a continued one (32). `packet.maybe` takes the end of the data for an answer, not an error. |
| `next_segment` | `segment.next` | The packet's next segment: a length under 255 ends the packet; after a page's last segment the next page must be a continued one (32). |
| `get8_packet_raw`, `get8_packet`, `get32_packet`, `flush_packet` | `packet.get8.raw`, `packet.get8`, `packet.get32`, `flush.packet` | The packet's bytes, `EOP` (-1) at its end. |
| `get_bits` | `bits.get` | Up to 32 bits, the first one lowest; 0 from the packet's end on. |

Things the code does that a reader of the format would not guess, all kept:

- **A page's segment table is 255 places that are never cleared.** A page
  writes as many as it has. A page without segments leaves `next_seg` at 0,
  and the next segment asked for is the length the table held from an
  earlier page.
- **A packet that is not read to its end is not skipped.** `start_packet`
  only resets the counters: the next packet begins at the page's next
  segment while the bytes are where the reading stopped. stb_vorbis's
  decoder flushes a packet it decoded; after an error it does not.
- **An error does not stop anything.** `error` keeps the last code;
  `next_segment` on a page that should have been a continued one answers 0
  with the page started, and the call after it reads that page's first
  segment.
- **The data's end inside a packet is zeros.** The segment's length is
  counted down, each byte 0, and only a page that does not begin ends the
  packet.
- **`eof` is sticky and `maybe_start_packet` tests it after its read:** an
  `eof` left by an earlier `getn` makes it answer 0 on a byte that is there.
- **`get_bits` past a packet's end** answers 0 for the whole request,
  whatever bits it had taken in, and for every request after it.

Two things C leaves undefined and every compiler raylib is built with
defines alike are followed, not refused: `skip` moves the stream pointer
past the end of the data and compares it (the position here is a number,
and passes the length the same way), and `get32_packet` shifts the int -1
of an `EOP` left (it adds `0xFFFFFF00`, `0xFFFF0000`, `0xFF000000` as two's
complement does). Neither reads or writes memory it should not; what does
(or what differs between machines, like the conversion in
`lookup1_values`) is refused. `next_segment` asserts that no byte of a
segment is left: it is only called that way.

`tools/vorbis_ogg_probe.py` (gate `vorbis-ogg`) includes stb_vorbis.c in
its reference and drives those static functions on a `stb_vorbis` set up as
`stb_vorbis_open_memory` sets one up, by six scripts: a walk of every
packet; the calls `start_decoder` makes over the three headers, then
packets read as bits and flushed; packets read as bits of every width and
left unfinished; packets read byte by byte past their ends; and two seeded
mixes of all fourteen calls. After each call everything the reader keeps is
hashed with the call's answer (position, `eof`, error, flags, the 255
places, `next_seg`, sequence number, known position, `p_first`, the
packet's counters, `acc`, `valid_bits`, the bytes of the last `getn`), and
the rolling hash is compared every 64 calls. The 70 files: raylib's
`target.ogg` whole, cut at 24 places, with each page's capture pattern or
continued flag changed, versions, unknown positions, segment counts,
seeded damage, the file twice; and 13 streams of pages built by the probe
(packets over pages with and without the flag, pages without segments, a
full table, empty packets, data that ends inside a segment or a table,
bytes between pages). 781,620 calls, equal on cpu-1, cpu-2 and JavaScript.

### The setup: the headers and the codebooks

`src/vorbis_setup.bend` is the beginning of `start_decoder`:
`setup.codebooks(bytes)` reads the identification header, the comment
header and the setup header as far as its time domain transfers, and
gives the channels, the sample rate, the two block sizes and the
codebooks. It ends in one of three ways:

- `Going{}`: the setup goes on (to the floors, which are not here yet);
- `Failed{code}`: `start_decoder` answers FALSE, with stb_vorbis's error
  code. The code can be 0: an empty comment packet makes `next_segment`
  answer 0, and `start_decoder` returns without setting an error;
- `Refused{why}`: stb_vorbis's answer is not one a port can give.

| `why` | |
| --- | --- |
| 1 | `lookup1_values` hangs on the C library's last bits or is undefined (above) |
| 2 | `entries * dimensions`, the value count of a type 2 lookup, passes the ints: undefined in C |
| 3 | An allocation of more than 16 MiB, which succeeds or not with the host: a vendor string or a comment of that length, a comment list of more than 2^21 comments, a lookup of more than 2^22 values |
| 4 | A codebook of more than 2^19 entries, the port's budget (the format allows 2^24) |

What the three headers do, with what is not obvious:

- **The identification header is read as bytes of the data**, not as a
  packet: the first page must be flagged first, not last, not continued,
  with one segment of 30 bytes (34 otherwise; 38 for a first segment of 64
  bytes that begins `fishead\0`, an Ogg skeleton). Type 1, `vorbis`,
  version 0, 1 to 16 channels (5 past that), a sample rate that is not 0,
  the block sizes as two exponents of 6 to 13 with the first not above the
  second (20), the framing bit. Where the data ends in the name the error
  is 10; after the name the missing bytes are zeros.
- **The comment header's strings are counted, not kept**: nothing of raylib
  reads them. Each length sizes an allocation of `length + 1` bytes. A
  negative int is `VORBIS_outofmem` (3): `setup_malloc` answers NULL for no
  byte and `malloc` for a size that is negative. A string longer than its
  packet is read to the end as `EOP` bytes and the setup goes on: the count
  that follows is then the sum of four `EOP`s, a negative int, which is no
  comment at all, and the framing "byte" is -1, whose bit is set. A comment
  list of 2^28 to 2^29 comments is a negative size (3); the rest of the
  packet is passed over with `skip`.
- **A codebook without entries is `VORBIS_outofmem`**: its lengths are an
  allocation of no byte. Without dimensions and with entries it is an
  invalid setup (20).
- **Lengths** are read one by one (5 bits and 1; a sparse codebook says
  first, in a bit, whether the symbol has a code), or ordered, in runs of
  one length each longer than the one before, a run's count in as many
  bits as the entries left take. A length of 32, a run past the entries
  and lengths that are no tree are invalid setups. A sparse codebook with a
  code for a quarter of its symbols or more is kept as one that is not
  sparse.
- **Lookups.** Two packed floats (the least value and the step), the bits
  of a value, whether the values are a sequence, and the values:
  `lookup1_values(entries, dimensions)` of them for type 1,
  `entries * dimensions` for type 2. A value is
  `mults*delta + minimum + last` in floats, in that order, `last` being the
  value before it in a sequence. stb_vorbis expands a type 1 lookup as it
  reads it, to every entry's values (the entry's number as digits in the
  base of the value count, the lowest first; a sparse codebook's entries
  in its sorted table's order), and calls the result type 2. In that
  expansion `last` is not set back to 0 with a new entry: a sequence runs
  on across entries. A sparse codebook without a code keeps type 1 and has
  no values.
- **Bits past the packet's end are zeros**, so a setup header that is cut
  goes on being read: lengths of 1, values of 0, until one of the tests
  fails.

`tools/vorbis_setup_probe.py` (gate `vorbis-setup`) runs stb_vorbis's
`start_decoder` on each file and compares, for this part, the header's
fields and every codebook: its fields, the count and the hash of its
multiplicands' bits, and the tables the codebook gate compares. The probe
also reads the headers itself (`model`, with the rules above restated in
Python): that tells it which files the port refuses, on which stb_vorbis
is not run, and its reading is held against stb_vorbis's on every other
file. For this part: raylib's `target.ogg` (37 codebooks), 40 copies with
one to three bits changed inside its codebooks, and 102 streams built
from headers (codebooks of each kind of lengths and lookup, 256 codebooks
in one setup, every failure above, every refusal with its neighbour that
is not one). The totals are with the next part's.

### The setup: floors, residues, mappings and modes

`src/vorbis_maps.bend` reads the rest of the setup header:
`maps.read(setup)` takes what `setup.codebooks` gave and gives the floors,
the residues, the mappings, the modes, the stage the setup came to (0 not
to the floors; 1 to 4 failed in the floors, the residues, the mappings,
the modes; 5 the end) and `first_audio_page_offset`. Each section is a
count of 6 bits and 1.

- **Floors.** Type 0 is `VORBIS_feature_not_supported` (4): stb_vorbis does
  not decode it. Type 1: up to 31 partitions, each of a class; a class has
  1 to 8 points, 0 to 3 bits of subclass, a masterbook where it has
  subclasses and a codebook for each subclass (read as its number and 1:
  0 is none). The classes read are those up to the largest a partition
  names. A floor's points are at 0, at `1 << rangebits`, and where the
  header says, in `rangebits` bits each: 250 at most. Two points at one
  place are an invalid setup (so is any point of a floor of no
  `rangebits`). stb_vorbis sorts the points by place (`sorted_order`) and
  finds for each point from the third on its nearest neighbours below and
  above among the points before it (`neighbors`): both are kept.
- **Residues.** A type of 0 to 2, a begin and an end (the end not under
  the begin), a partition size, 1 to 64 classifications, a classbook, and
  for each classification a cascade (which of eight codebooks it has) and
  those codebooks. stb_vorbis then allocates a classification for every
  dimension of every entry of the classbook: `entries * dimensions` bytes
  in as many allocations as entries, which the port does not need (it is
  the entry's number written in the base of the classifications) but which
  is refused past 16 MiB (refusal 3).
- **Mappings.** Type 0; 1 to 16 submaps; coupling steps, each a magnitude
  and an angle channel in as many bits as the last channel's number takes
  (two channels of the stream, not the same one: a mono stream cannot be
  coupled); two reserved bits; a submap for each channel where there are
  several; a floor and a residue for each submap. **stb_vorbis has room for
  15 submaps**: the sixteenth's floor is written over the first's residue.
  A mapping of 16 submaps is refused (2), once everything before the
  sixteenth has passed its tests; one that fails before it fails as in
  stb_vorbis.
- **Modes.** A block size flag, a window type and a transform type that
  must be 0, a mapping.
- **A header that is cut goes on as zeros**, and zeros are a valid end: a
  setup header with nothing after its floors has one residue of nothing,
  one mapping and one mode, and `start_decoder` succeeds.
- **`first_audio_page_offset`** is where the data is after the header if
  the header's page is used up, and 0 if the page has another packet.

The gate `vorbis-setup` covers this too. A row is whether
`start_decoder` succeeded, its error code, the stage it came to (told by
which of `floor_config`, `residue_config`, `mapping` and `mode_count` it
had set) and everything it had read whole by then, compared field by
field: 249 files (60 more copies of `target.ogg` damaged after its
codebooks; 46 more built streams, with floors of 2 to 250 points, residues
of each type and 64 classifications, mappings of 15 submaps and three
couplings, 64 modes, each test failed in turn, each refusal with its
neighbour). 54 whole setups, 180 failures with the same code at the same
stage, 15 refusals; 3141 codebooks, 179 floors, 130 residues, 103
mappings, 155 modes.

### The transform's tables

`src/vorbis_tables.bend` is `init_blocksize`: for a block size `n` (a power
of two from 64 to 8192), `tables.for(libm, n)` gives the twiddle factors
`A` and `B` (n/2 floats each) and `C` (n/4), the window (n/2) and the bit
reversal (n/8), as `compute_twiddle_factors`, `compute_window` and
`compute_bitreverse` compute them.

The floats are the C library's binary64 `cos` and `sin` narrowed:
`A[2k] = (float)cos(4*k*M_PI/n)`, `A[2k+1] = (float)-sin(4*k*M_PI/n)`,
`B[2k] = (float)cos((2k+1)*M_PI/n/2)*0.5f` and its `sin`,
`C[2k] = (float)cos(2*(2k+1)*M_PI/n)` and its `-sin`, and the window is
`(float)sin(0.5*M_PI*square((float)sin((i + 0.5)/n2*0.5*M_PI)))`, a sine of
a squared sine narrowed twice.

- **The arguments are the same on every host.** They are products and
  quotients of ints and `M_PI` in binary64, each rounded once, with no
  product followed by a sum that a compiler could fuse. The port computes
  them with Jonmath's exact binary64 helpers.
- **`M_PI` is `<math.h>`'s.** stb_vorbis defines `M_PI` itself where the
  header does not, as a *float* constant (`3.14159265358979323846264f`),
  and its tables are then others in most places. raylib's builds define
  `_DEFAULT_SOURCE` (CMake) or `_GNU_SOURCE` (Makefile), so the double is
  used; that is what the port has, and the gate's reference is compiled so.
- **The functions are the library's.** Under `M.Glibc239Libm{}` every
  value is glibc 2.39's own (`Libm.sin64`, `Libm.cos64`: the LGPL module
  `src/lgpl/sin.bend`). Under another profile the port has no model of the
  library's sine, and gives a value only where its float is sure: where the
  binary64 result is at least two units in its last place away from a
  float's rounding boundary, so that any library within one unit of the
  true value (glibc's is) narrows to the same float. A table with a value
  that is not sure is `None`. For the eight block sizes every one of the
  28,560 floats is sure. Whether Apple's library is within that unit is
  what the gate will show on a macOS host, where the reference is Apple's
  own.

`tools/vorbis_tables_probe.py` (gate `vorbis-tables`) includes
stb_vorbis.c in its reference and calls the three functions for each of
the eight block sizes; the tables are compared by a rolling hash of the
floats' bits every 64 values, under the host's profile and, on a glibc
host, under `M.AppleLibm{}` too (every value given, every value the same).
The proof has no laws on the angles: Jonmath's binary64 helpers use float
primitives, which the proof checker does not evaluate.

### Symbols and vectors of a codebook

`src/vorbis_decode.bend` decodes what a packet's bits say through a
codebook, on the reader of the data. A codebook as the setup read it is
first made ready (`coder.of`): its tables become rows read by index
(`src/store.bend`, binary trees that are plain values, so that a buffer can
be read and written by index as C does without being threaded through
every call).

| stb_vorbis | Here | |
| --- | --- | --- |
| `prep_huffman` | `huffman.prep` (in `vorbis_ogg.bend`) | Bytes of the packet added above the bits at hand while there are 24 or fewer, up to 32. |
| `DECODE_RAW` | `decode.raw` | A symbol: its number, or its place in the sorted table for a sparse codebook; -1 for none. |
| `DECODE` | `decode.symbol` | The symbol's number (a sparse codebook's sorted place turned into it). |
| `codebook_decode_scalar_raw` | `raw.decode` | The slower search, when the accelerated table has no answer. |
| `codebook_decode_start` | `vector.start` | A symbol for a vector of values. |
| `codebook_decode`, `codebook_decode_step` | `vector.decode`, `vector.step` | The vector's values added to floats, next to each other or every `step`th. |

raylib compiles stb_vorbis with its decode inline (no
`STB_VORBIS_NO_INLINE_DECODE`), so `DECODE_RAW` is a macro, and the port
follows the macro. A symbol is found in one of three ways:

- **The accelerated table**, for the next 10 bits, where a code of 10 bits
  or fewer begins them. Its bits are shifted out *before* stb_vorbis looks
  whether there were that many: if not, the symbol is -1 and no bits are at
  hand, but the accumulator has been shifted.
- **The sorted table**, by binary search of the bits read the other way,
  for a codebook of more than 8 entries that has one, and for a sparse
  codebook. The search answers the last codeword that is not above the
  bits: it does not ask whether the bits are a code of the codebook, so a
  tree with leaves left over gives a symbol for bits that are no code.
- **The symbols in turn**, for a codebook of 8 entries or fewer, and for
  a larger one without a sorted table (all its codes 10 bits or fewer): the
  first whose code the bits begin with. None is `VORBIS_invalid_stream`
  (21).

In the two searches a code longer than the bits at hand is -1 with no bits
at hand and the accumulator as it was.

For a vector: a codebook without a lookup has none (21). No symbol is the
packet's end if the packet is over, and an invalid stream (21) otherwise.
The values are `values[z*dimensions + i]`, `z` being the symbol's number, or
its sorted place for a sparse codebook. Not in a sequence each is added to
`0.0f` before it is added to the output (which turns a -0.0 into 0.0). In a
sequence each value adds the one before: with the codebook's least value
added again in `codebook_decode`, and without it in
`codebook_decode_step`. Both are as the code has them.

Two things stb_vorbis does here that C leaves undefined are refused, with
the reader's error 1001:

- **`DECODE` on a sparse codebook without a code.** The symbol is -1, and
  the macro turns it into `sorted_values[-1]`, a place stb_vorbis keeps
  before the table for that purpose; such a codebook has no table, and the
  read is of a null pointer.
- **`prep_huffman` after the bits ran out on an unflagged page.** Bits that
  run out leave `valid_bits` at -1. Normally the packet is over and
  `prep_huffman` returns; but when the packet stopped at a page that should
  have been a continued one, the reader still has bytes, and the next byte
  is shifted left by -1.

`tools/vorbis_decode_probe.py` (gate `vorbis-decode`) runs
`start_decoder` on a built stream and then a script of calls on its
packets, with the Ogg gate's harness: everything the reader keeps, the
call's answer and a buffer of 64 floats are hashed after each call. The
stream has twelve codebooks, one for each way a symbol is found and each
kind of lookup; its packets are seeded bytes of 0 to 700 bytes. 54 scripts
(each codebook's symbols by `DECODE_RAW`, by `DECODE` and by
`codebook_decode_scalar_raw`; each codebook's vectors; three mixes of all
ten calls with bits read between symbols and packets left unfinished;
packets flushed) over the stream, a copy cut inside a packet and one with
an unflagged page: 159 runs, 109,407 calls, 5 of the runs refusals on
which stb_vorbis is not run.

### The inverse MDCT

`src/vorbis_mdct.bend` is `inverse_mdct`: `transform(buffer, factors, n)`
turns the n/2 spectral values at the start of a block's n floats into its n
samples, before the window. `factors.of` makes a block size's tables
(above) into rows.

It is stb_vorbis's own algorithm, pass for pass, on two buffers (the block
and a temporary one of half its size): the spectrum's even and odd places
turned by the factors `A` into the temporary buffer; step 2 back into the
block; step 3's levels of butterflies in place (`imdct_step3_iter0_loop`
for the two halves, `imdct_step3_inner_r_loop` for the four quarters and
the next levels, `imdct_step3_inner_s_loop` for the levels after, and the
last three levels at once in `imdct_step3_inner_s_loop_ld654` with
`iter_54`); the bit-reversed copy into the temporary buffer; step 7 with
the factors `C`; and step 8 with the factors `B`, which writes every float
of the block. Every float operation is one of the C code's, in its order,
each rounded once, with no product fused into the sum after it.

- The result is half what an inverse MDCT gives: stb_vorbis leaves out a
  factor of 2 where its first pass adds each value to itself, and the
  window's step makes up for it.
- The loops that take their butterflies four at a time run `count >> 2`
  turns: the block of 64 asks one of them for 2 butterflies and gets none.
- The second half of the block is not read: only written.

`tools/vorbis_mdct_probe.py` (gate `vorbis-mdct`) calls `init_blocksize`
and `inverse_mdct` for each of the eight block sizes on ten blocks read
from a file (silence, a value at each end of the spectrum and in its
middle, ones, alternating signs, seeded noise, a ramp, values from 1e-30
to 1e30 with negative zeros, and the noise again over a second half filled
with something else, which must give the noise's result), and compares the
bits of every float of every block: 80 blocks, 163,200 floats. No block
overflows: the bits of the NaN that an infinity less an infinity gives are
the machine's, not the code's.

### Residues

`src/vorbis_residue.bend` is `decode_residue`:
`residue.decode(reader, rows, coders, residue, channels, n, mask)` adds a
residue's vectors to the channels' floats (rows; `mask` has a bit for each
channel that is decoded, where stb_vorbis has a null pointer for the
others), after clearing the first `n` floats of each decoded channel. `n`
is half the block.

A residue is read in eight passes over its partitions. In the first pass a
class is read for each group of partitions (a symbol of the classbook,
whose digits in the base of the classifications are the partitions'
classes); in each pass a partition whose class has a codebook for that
pass gets vectors of it. No symbol for a class, or a vector that is not
decoded, ends the residue there. How the vectors are laid is the residue's
type:

- **Type 1** (and type 2 with one channel): `codebook_decode` at the
  partition's floats, the codebook's dimensions further each time.
- **Type 0**: `codebook_decode_step` from each of the first
  `size/dimensions` floats, every `size/dimensions`th float after it. The
  length stb_vorbis passes is `n - offset - k`, where `n` is the
  partition's *size* and `offset` where the partition *is*: past the first
  partitions it is under 1, and nothing is added. Kept.
- **Type 2 with two channels or more**: one class for all the channels, and
  the vectors woven over them (`codebook_decode_deinterleave_repeat`,
  `weave.decode`): each value to the next channel in turn, the next float
  after the last channel.

As the code has them:

- A residue's begin and end are cut to the vectors' length to count the
  partitions, but the partitions are placed from the begin as written.
- **A residue of type 2 with one channel reads up to twice `n`**, over
  floats the clearing did not reach: they hold what the block before left
  there. The channels' rows are kept from packet to packet for that.
- **Where woven vectors come to the end of the floats**, stb_vorbis cuts
  the values it takes from a vector to `len*ch - (p_inter*ch - c_inter)`:
  the room left with the channel it is at added instead of taken away. It
  keeps that for the vectors after it, and writes the extra values past
  the vectors' length (inside the buffers, which are twice as long). At 0
  or less no value is taken and nothing is counted as decoded: the loop
  then ends only when the packet does.
- **Refused (error 1001): a cut that takes more values than the codebook
  has after the vector's symbol.** The cut can be up to twice the channel
  number more than a vector has. The values read are then the next
  symbol's, which the port follows; past the last symbol's they are no
  longer the codebook's (a read past its allocation).

`tools/vorbis_residue_probe.py` (gate `vorbis-residue`) runs
`start_decoder` on a built stream of four channels with eleven residues and
thirteen codebooks, then scripts of calls on its packets: `decode_residue`
for each residue with 1 to 4 channels, vectors of 32 and 64 floats and
every choice of channels that are not decoded; residues one after another
in a packet; and `codebook_decode_deinterleave_repeat` directly for every
codebook, at places inside and past the end of the floats. Everything the
reader keeps and four buffers of 256 floats are hashed after each call.
The direct calls either stay clear of the end of the floats or keep to the
first channel at each vector, so that stb_vorbis reads no value past a
codebook's; one run is the refusal, on which stb_vorbis is not run. 53
runs, 9008 calls.

### A floor's curve

`src/vorbis_floor.bend` is `do_floor` with `draw_line`, as raylib's build
has them (the deferred floor: the curve multiplies the spectrum after the
residue is in it): `curve.of(row, floor, ys, n, table)` multiplies the
first `n` floats of a channel (half a block) by the floor's curve, given
the Y value of each of the floor's points (`finalY`; -1 for a point
without one).

The curve is lines between the points that have a Y, in the order of their
places, each drawn with integers as the specification has it: a height that
moves by `dy/adx` (cut toward zero) a float, and by one more step where the
error passes `adx`. Each float is multiplied by `inverse_db_table` at the
line's height, which stb_vorbis takes modulo 256; a height is a Y times the
floor's multiplier. Lines stop at the half block's end. After the last
point the curve is level.

- **`inverse_db_table`** is 256 floats the specification gives in decimal.
  `src/vorbis_db.bend` has them as the bits the C compiler makes of each
  literal: `tools/vorbis_db_table.py` takes the table out of
  stb_vorbis.c's text and compiles it (`--check` says whether the module is
  stale). Nothing is typed by hand.
- **Refused (error 1001 for the packet): a level end past the table.**
  The level end is read as `inverse_db_table[ly]`, the height itself, with
  no modulo. A Y inside the floor's range times the multiplier is 255 at
  most; a Y past the range, which a subclass codebook with more entries
  than the range can give, is a read past the table's end. (Before the
  last point such a height only wraps in the table.)

`tools/vorbis_floor_probe.py` (gate `vorbis-floor`) runs `start_decoder`
on a built stream of six floors (2 to 250 points, places of 1 to 15 bits,
each multiplier) and calls `do_floor` on 216 cases: Y values inside the
range, with points left out, only the first point, values past the range
and negative ones, for half blocks of 32, 256 and 2048 floats, shorter and
longer than the floors are wide. The floats' bits are compared, and the 8
floats after the half block, which must be untouched. The probe works out
which cases end past the table (19): stb_vorbis is not run on those, and
the port must refuse exactly them. The table's hash is compared too, and
the generated module is held against the source.

### A packet

`src/vorbis_packet.bend` is `vorbis_decode_packet` (`vorbis_decode_initial`
and `vorbis_decode_packet_rest`, with `predict_point`): the parts above put
together. `open(libm, bytes)` is the decoder as `start_decoder` leaves it,
`Opened{plan, state}`, or `Closed{status}` with stb_vorbis's failure or a
refusal. The `Plan` is what the setup gives and no packet changes: the
codebooks ready to decode with, the floors, residues, mappings and modes,
the transform's factors for the two block sizes and `inverse_db_table`. The
`State` is what a packet changes: the reader, a row of `blocksize_1` floats
a channel (`channel_buffers`), the sample position of the next block
(`current_loc`), whether it is known, and the samples still to drop
(`discard_samples_deferred`). `packet.decode(plan, state)` is one call,
`Packet{state, fine, len, left, right}`: the C answer, the count of the
block's samples and where its left and right parts begin. The floats are
the block before its window.

- **The packet's start.** Packets whose first bit is set are not audio and
  are passed over. The mode's number takes the bits the last mode's number
  does. A long block says in two bits whether the blocks before and after
  it are long too, which gives its windows: next to a short block the slope
  is the short block's, in the long block's middle.
- **The floors.** A bit says whether the packet has a channel's floor. The
  first two points' Y values are plain bits, as many as the floor's range
  (256, 128, 86 or 64 by its multiplier) takes; the others are symbols of
  the subclasses' codebooks, a point's subclass being some bits of its
  partition's class value (a symbol of the class's masterbook). Each point
  from the third on is then placed against the line between its two
  neighbours (`predict_point`, by integers): its value is how far from the
  line it is, to one side or the other by turns while there is room on
  both, and to the roomier side past that. A value of 0 is the line's
  height, and the point is not one of the curve's (-1 in `finalY`). The
  values are int16s, as stb_vorbis keeps them: a symbol's number is cut to
  16 bits where it is stored, `val >> 1` of a negative one keeps its sign,
  and a class value of -1 (the masterbook gave no symbol) stays -1 through
  its shifts. A packet that ends in a floor's values leaves the channel
  without a floor, with the Y values the packet before left it.
- **The residues**, a submap at a time (`decode_residue`, above), for the
  channels that have a floor or are coupled with one that has.
- **The inverse coupling**, from the last pair to the first: by the signs
  of a magnitude and its angle, one of the two becomes their sum or their
  difference.
- **The curves and the transform.** A channel without a floor has its half
  block cleared; the others are multiplied by their floor's curve. Then
  the inverse MDCT of each channel's block.
- **The block's place.** What is left of the packet is dropped. The first
  packet decoded places the stream: its block begins half a block before
  sample 0, and what a long first block has past its right window is
  dropped from the next block (its left part moves up, as far as its right
  one). The packet its page's granule position is for takes its place from
  that position; on the stream's last page the position can cut the block
  short instead, and `len` is then what is left of it. Otherwise the next
  block is a window's width further.
- **Refused (error 1001).** What the parts above refuse: a floor's level
  end past the table, a residue's woven vectors cut where they take values
  past a codebook's, and what the reader refuses. A call that meets one
  fails with the reader's error 1001 and leaves the floats and the position
  as they were, and so does every call after it. `open` is
  `Closed{Refused{why}}` for the setup's refusals and, with 5, where the
  transform's tables are not given under the libm profile.

`tools/vorbis_packet_probe.py` (gate `vorbis-packet`) runs `start_decoder`
and then `vorbis_decode_packet` 120 times on each of 12 files: raylib's
`target.ogg` (two channels at 22050 Hz, blocks of 512 and 1024 samples,
coupled, 105 audio packets), four copies cut inside its audio pages, four
with one to four bits of its packets changed and three with a run of a
packet's bytes replaced (seeded). After each call the answer, the block's
length and parts, everything the reader keeps, the sample position and
every float of the channels' buffers are hashed, and the rolling hash is
compared every 8 calls. The whole file decodes 105 packets, and the calls
after its end fail as stb_vorbis's do; 1008 of the 1440 calls decode a
packet. The damage is in the packets' bytes alone (a damaged
packet is mostly decoded all the same, into other floats), so none of the
refusals arises: this file's floors have no codebook with more entries
than their range, and its residues end with their blocks.

A packet takes about a third of a second in the JavaScript lane (the
CPU lanes are several times faster): the persistent rows cost a path a
float, and the whole of `target.ogg` is half a minute there.

### Frames and samples

`src/vorbis_frame.bend` is what stb_vorbis does with a decoded block:
`vorbis_finish_frame` with `get_window`, `vorbis_pump_first_frame`,
`stb_vorbis_open_memory`, `stb_vorbis_get_frame_float` and
`stb_vorbis_get_samples_short_interleaved` with
`convert_channels_short_interleaved`.

`memory.open(libm, bytes)` is `Ready{plan, frames, rate, first}` (or
`Unready{status}`): the setup read and the first frame pumped, with the
stream's sample rate and `first_audio_page_offset` (where the data is when
the setup's packet ends its page; 0 when audio packets share that page).
`Frames` is the decoder between frames: the packets' state, each channel's
`previous_window` and its length, where the samples not yet taken are in
the channels' floats and how many samples the frames have given.

- **A frame** (`frame.float(plan, frames)`, `stb_vorbis_get_frame_float`):
  the next packet decoded, and its block's left part mixed with what the
  block before left, each under its half of the window:
  `buffer[left + j]*w[j] + previous[j]*w[n - 1 - j]`, two float products
  and a sum. The block's right part is then kept for the next frame, and
  the frame gives the samples from `left` to `right`. The first frame has
  nothing to mix with and gives none (that is the frame `memory.open`
  pumps).
- **No window.** The window is the one of the block twice as long as what
  the last block left. A last page's position that cuts its last block
  short leaves another length, or one below 0; if more packets follow (pages
  after the one flagged as the last), `get_window` has no window, and every
  frame from there on gives nothing and changes nothing but the packets'
  state. Blocks whose flags disagree with their neighbours (a long block
  that says a long one follows, before a short one) are mixed as their
  lengths say, over floats past the short block's end, inside the channel's
  buffer in every case.
- **Samples** (`samples.read(plan, frames, shorts)`,
  `stb_vorbis_get_samples_short_interleaved` for the stream's own count of
  channels, which is how raylib calls it): `shorts/channels` samples of each
  channel, interleaved, taken from the samples at hand and then from frame
  after frame; a frame that gives no sample ends the read early, as in
  stb_vorbis. `Read{frames, count, samples, on}`.
- **A float's short.** raylib's build converts with
  `FAST_SCALED_FLOAT_TO_INT(temp, x, 15)`: `temp.f = x + MAGIC(15)`, then
  the int `temp.i - ADDEND(15)`. `MAGIC(15)` is written as
  `1.5f*(1 << 8) + 0.5f/(1 << 15)`, but the second term is half a float's
  step at 384 and is lost: the constant is 384.0f, whose bits are
  `ADDEND(15)` (the reference program checks both). So the sum's bits count
  the steps of 1/32768 from 384: `x*32768` rounded to the nearest, to the
  even one of two as near, and then kept to -32768 and 32767
  (`sample.short`).
- **Refused (error 1001): two kinds of float** (`sample.refused`). For a
  sum below 0 and above -384 (a float from -768 to -384, both left out) the
  int subtraction overflows, which C leaves undefined (a wrapped result
  would be 32767 for a sample far below the range). And a NaN's short goes
  by its sign bit, which is the machine's (an invalid operation makes a
  negative NaN on x86 and a positive one on ARM). A read that meets one
  leaves the reader's error 1001 (`Frames.refused`), and what it read is
  not to be used. Floats that large come only of codebooks whose values
  are: target.ogg's samples stay far inside, damaged or not.

`tools/vorbis_frame_probe.py` (gate `vorbis-frame`) opens each of 22 files
with `stb_vorbis_open_memory` and runs a script of 293 calls in all, each
`stb_vorbis_get_frame_float` or `stb_vorbis_get_samples_short_interleaved`
for some count of shorts (even, odd, less than a frame, more than the
stream has). After each call the answer, the shorts and everything the
decoder keeps are hashed: the reader, the sample position, every float of
the channels' buffers, the previous windows, where the samples at hand are
and the samples given; at the opening, the sample rate and where the audio
begins too. The files are raylib's `target.ogg` read whole as `LoadWave`
asks (88200 shorts at once) and in a music stream's steps, two cut copies,
three damaged inside their packets, and 14 streams built by the probe (one
of them read two ways): one channel, blocks of 64 and 256 samples, a floor of two points and a residue
of type 1 whose codebook's values are 0, 1 and a chosen loudness either
way. They are quiet (samples about a short's steps), loud (every sample
past a short's range), loud enough to be refused, with long and short
blocks whose windows disagree, with a long first block, with a last page
whose position cuts the last block short, lies before it or is unknown,
with pages after such a last page (previous lengths of 6, -24 and -32
samples), and with audio packets on the setup's page. 248792 samples of
each channel are compared.

A second decoder in the reference program runs each read first, with the
function's own loop written out and each float looked at where it would be
converted; on a float the port refuses it ends the run, the function is
not called on it, and the port must refuse in the same call. The two
decoders must agree after every call, which holds the loop written out
against the function. A table of 314 floats is converted one by one by
`convert_channels_short_interleaved`: the steps and ties of a short, the
ends of its range, the ends of what is refused, infinities, NaNs and seeded
ones; 49 are left out by the reference and refused by the port.

### A stream's length

`src/vorbis_length.bend` is `stb_vorbis_stream_length_in_samples` with
`vorbis_find_page` and the pages' checksum (`crc32_init`, `crc32_update`),
and `src/vorbis_ogg.bend` has `set_file_offset` for data in memory
(`offset.set`). `stream.length(frames, first, total)` is one call:
`Measured{frames, total, value}`, where `first` is the decoder's
`first_audio_page_offset`, `total` what the call before kept (0 at first)
and `value` the C answer.

The length is the granule position of the stream's last page, which
stb_vorbis searches for once:

- **Where the search begins**: 64 KiB before the data's end, or where the
  audio begins if that is later (a page is less than 64 KiB).
- **A page** (`page.find`) is the first `O` from there that begins
  `OggS`, a stream structure version of 0 and a header, segment table and
  body whose checksum is the one the header states: the CRC of polynomial
  0x04c11db7 from 0, not reflected, over the page with its checksum field
  as zeros. Anything else is passed over, and the search goes on from the
  byte after that `O`: capture patterns inside a body, pages whose bytes
  were changed, pages cut by the data's end. A whole page inside another
  page's body is a page.
- **Where the search gives up**: at the data's end; at a header whose
  segment table the data ends in (a small page after it, inside what would
  be that table, is not found); and at an `O` in the data's first 24 bytes,
  where `retry_loc - 25 > stream_len` is an unsigned comparison that wraps.
  A stream whose audio shares the setup's page begins its search at offset
  0 and so finds nothing.
- **Bytes past the data's end are zeros** to the checksum (`get8` answers
  0 there): a page of empty segments cut short in its table still has its
  checksum, and is found.
- **The last page** is the first one found that is flagged as the last, or
  the last one found before the search fails. Pages after a flagged one are
  not looked at.
- **The position**: all ones is no position (`VORBIS_cant_find_last_page`,
  error 36, and the answer 0, as when no page is found); one past 32 bits
  is 0xfffffffe; otherwise its low word. A low word of all ones under a
  high word of 0 is kept as it is, which reads as not known (the answer 0)
  without the error.
- **The reader afterwards** is where it was, by `set_file_offset`: its
  end-of-data flag is cleared, or set if the offset is the data's end.
  A length of 0 is not kept and is searched for again by the next call.

`p_last` (the last page's place, which only seeking reads) is not kept.

`tools/vorbis_length_probe.py` (gate `vorbis-length`) runs scripts of the
length, frames and reads on 32 files with the vorbis-frame gate's hashing
after each call (143 calls, 96 of them the length's): raylib's `target.ogg`
asked for its length first as `LoadWave` does, after all its samples are
read and between reads; copies cut in the last page, at its start and in
the page before, and with a byte of a body changed; copies whose last page
states another position with its checksum made right (all ones, past 32
bits, 0, less than the samples, either word all ones), another version, or
no last flag; and 15 streams built by the probe with their pages'
checksums: a small one, one without checksums, one whose audio shares the
setup's page, and ones over 64 KiB that end with their last page, with
bytes that are no page (more than 64 KiB of them, and a few with capture
patterns and the data's end inside one), with a page flagged before
another, with none flagged, with positions past 32 bits and unknown, with
capture patterns or a whole small page inside the body the search begins
in, with a header whose table the data ends in, and with a page of empty
segments cut short. The probe states each stream's length beforehand and
holds the reference to it.

### Waves and sounds

`Wave.decode_for(libm, ".ogg", bytes)` is raylib's `LoadWaveFromMemory`
for Ogg Vorbis data: `stb_vorbis_open_memory`, as many frames as
`stb_vorbis_stream_length_in_samples` says, and one
`stb_vorbis_get_samples_short_interleaved` for all of them. The wave is
16-bit samples at the stream's rate and channels. `Wave.load_for(libm,
path)` is `LoadWave`, and `Sound.load_with(profile, libm, device, path)`
`LoadSound`.

- **`libm`** is the profile the transform's tables are taken under (they
  are the C library's binary64 sines and cosines, see *The transform's
  tables*). Under `M.Glibc239Libm` every table is given. `Wave.decode`,
  `Wave.load` and `Sound.load_for` use `M.AppleLibm{}`, as the other
  functions without a profile do: a stream whose tables that profile does
  not give is `UnsupportedWaveFormat`. (It gives them for every block
  size: see *The transform's tables*.)
- **A length that is not known**, or 0, is a wave of no frames (raylib's
  buffer is `malloc(0)`), and `LoadSoundFromWave` of it is the invalid
  sound.
- **`InvalidWaveData`: a stream that gives fewer samples than its length
  says.** raylib does not look at how many samples the read gave: its
  buffer is `malloc`'d for `frameCount*channels` shorts, and the shorts the
  read did not reach are what `malloc` left there. That count is an
  unsigned product taken as an int: one past an int reads nothing at all,
  and one past 32 bits wraps to a few shorts under a frame count that says
  billions. All of them are refused: a wave is given only where every
  short of it was written.
- **`InvalidWaveData`** also for data stb_vorbis does not open (raylib
  warns and has no wave), for a setup C leaves undefined and for what the
  decoder refuses in a packet or a sample (above).
- **`UnsupportedWaveFormat`** for a setup past this port's limits (an
  allocation over 16 MiB, a codebook over 2^19 entries), which stb_vorbis
  decodes.

`tools/vorbis_wave_probe.py` (gate `vorbis-wave`) compares `Wave.load_for`
and `Sound.load_from_wave` with raudio.c's own `LoadWave` and
`LoadSoundFromWave` on 20 files: raylib's `target.ogg` (44100 frames of two
channels at 22050 Hz, and a sound of 96000 frames) under `.ogg` and `.OGG`;
cut at its last page and inside it (the page before is the last then: 30208
frames), inside its setup and its first header (no wave); with seeded
damage in its packets; with a last page that states no position or 0 (no
frames), 30000 samples (a shorter wave), 50000 (more than it has), and
positions past an int and past 32 bits; and six streams of one channel at
8000 Hz built by the vorbis-frame gate's probe: loud (every sample at an
end of a short's range), quiet, with a position before the last block and
one past the stream's samples, without checksums (no length) and loud
enough to be refused. The reference program reads each stream itself
first, with the read's loop written out, counting the samples and looking
at each float: where the read would leave shorts unwritten or convert a
float the port refuses, `LoadWave` is not called and the port must give no
wave.

Still to come: the music (`LoadMusicStream` for `.ogg`, with
`stb_vorbis_seek_start` and `stb_vorbis_seek_frame`).

## XM modules (in progress)

`src/xm_module.bend`, `src/xm_pitch.bend`, `src/xm_sample.bend`,
`src/xm_player.bend` and `src/xm_mixer.bend` are an adaptation of jar_xm
(pinned
raylib's `src/external/jar_xm.h`), which raylib's `LoadMusicStream` calls
for `.xm` files. `Music.load` does not take the format yet.
What is here is the module read from its file,
`jar_xm_create_context_safe`: `load(bytes)` is `Loaded{module}`,
`Failed{code}` (jar_xm's own failure) or `Refused{why}`.

A `Module` has the pattern order (its length, its restart position and its
256 entries), the channels, the frequency type, the default tempo and BPM,
the patterns (rows, and a slot a channel a row: note, instrument, volume
column, effect, parameter) and the instruments (the sample of each of 96
notes, the volume and panning envelopes of 12 points, the vibrato, the
fadeout, and the samples with their loop, volume, finetune, panning,
relative note and data as floats). Names are not kept.

- **What is a module** (`jar_xm_check_sanity_preload`): 60 bytes at least,
  `Extended Module: `, 0x1A at 37 and the version 1.04. Anything else is
  `Failed{1}`.
- **Reads past the data are zeros** (`READ_U8`), so a file cut anywhere
  after its first 60 bytes still loads: patterns, instruments and samples
  the header counts and the file does not have are empty.
- **Packed patterns**: a slot's first byte with its high bit set says which
  of the five bytes follow; any other byte is the note, and four more
  follow. Slots the packed bytes do not reach are zeros. A packed slot
  whose bytes run past the packed size is read all the same.
- **Samples**: delta-coded, each value the last plus an int8 or an int16
  (kept to that type), as a float over 128 or 32768. A 16-bit sample's
  lengths are halved. A stereo sample's running value begins again at its
  half and only its first half is the sample; if it loops, its loop is
  halved from the header's values as ints. A loop type of 2 or 3
  (ping-pong) falls through jar_xm's `switch` to forward.
- **The pattern order** (`jar_xm_check_sanity_postload`): an entry that
  names no pattern is `Failed{1}`, unless it is the last of more than one,
  which is dropped.
- **jar_xm's block of memory.** jar_xm works out one size beforehand
  (`jar_xm_get_memory_needed_for_context`), allocates it and lays the
  module out in it by a second reading of the file. The two readings do not
  always agree (a 16-bit sample of an odd length moves them a byte apart),
  and where they do the estimate is still 8 to 23 bytes short of the
  layout: the last bytes of the player's row counts are outside the block. `load` keeps
  the same account, with jar_xm's structures as the LP64 machines lay them
  out (the reference program checks the sizes), and the module's `room` is
  how many bytes of the row counts are inside, for the player to refuse
  past.
- **Refused 1: a write outside an array or the block.** Packed bytes for
  more slots than the pattern has; an envelope of more than 12 points;
  patterns, samples or channels that do not fit the block (a module whose
  order is empty has no room for its channels).
- **Refused 2: a loop that does not end.** jar_xm counts the channels and
  the order's entries in a byte: 256 channels, or an order of 256 entries
  or more whose first 256 all name patterns, are counted for ever.
- **Refused 4: past this port's limits.** A block of more than 16 MiB, and
  a pattern whose packed bytes pass 65535 by their count, where jar_xm's
  16-bit counters wrap.

`tools/xm_module_probe.py` (gate `xm-module`) loads 88 files with
`jar_xm_create_context_safe` and compares rolling hashes of the header and
order, of every slot, and of the instruments with their envelopes, samples
and every float, with the counts and the room: raylib's `mini1111.xm` (11
channels, 10 patterns, 8 instruments, 9520 floats), 10 cuts of it and 24
copies with a byte changed, and 53 modules the probe builds for each of
the points above. The probe has a model of the loader's account that says
which files are refused (15): jar_xm is not run on those, and the port must
refuse each for the model's reason. For the 73 others the model's verdict
is held against jar_xm itself: what fails (8), and each module's room.

### Pitch, waveforms and envelopes

`src/xm_pitch.bend` is what a channel's sound is worked out from, tick by
tick: `jar_xm_linear_period`, `jar_xm_linear_frequency`,
`jar_xm_amiga_period`, `jar_xm_amiga_frequency`, `jar_xm_period`,
`jar_xm_frequency`, `jar_xm_waveform`, `jar_xm_envelope_lerp` and
`jar_xm_envelope_tick`.

- **Linear frequencies**: a note's period is `7680 - 64*note`, and a
  period's frequency `8363*powf(2, (4608 - period)/768)`, which is
  `M.Libm.pow2` (given under the glibc profiles for an exponent within 126
  of 0; `None` under `M.AppleLibm`).
- **Amiga frequencies**: a note's period is its place between two of the
  table's 13 periods, shifted by the note's octave; a period's frequency is
  `7093789.2/(2*period)`. With a note offset (vibrato, arpeggio) the
  period's own note is first found in the table. jar_xm converts the note
  to an `unsigned` and its octave to an `int8_t`, and shifts by the octave:
  a NaN, a note of -1 or less, an octave past 31 and a period below 0 are
  undefined, and `None` here.
- **Waveforms** (`waveform(kind, libm, step, random)`): the step is a byte
  taken modulo 64. A sine is `-sinf` of the step's 64th of a turn (with
  jar_xm's 3.141592, and -0 at step 0), then a ramp down, a square, a
  random value and a ramp up; other kinds are 0. The random one is the
  generator of POSIX's example in a `static` variable: one state for every
  module a program plays, which the port takes and gives back.
- **Envelopes** (`envelope.tick(envelope, sustained, counter, value)`): the
  counter is taken back by the loop's length at the loop's end, the value
  is the line between the first two points the counter lies between (over
  64; unchanged where there are none), and the counter moves on unless the
  channel is sustained at the sustain point. One point is its value, 1 at
  most; no point changes nothing. The loop's and the sustain's points are
  numbered by bytes: a number past the 12th point, where it is read, is a
  read past the envelope's points (`Ticked.fine` is false).

`tools/xm_pitch_probe.py` (gate `xm-pitch`) calls jar_xm's own static
functions on 197 notes, 524 pairs of a period and a note offset, 336
waveform steps and 26 envelopes for 40 ticks each. **The reference says
what is undefined**: it is compiled with the compiler's checks of a float
converted to an int it does not fit, a shift by a count the type has not, a
signed overflow and an index past an array as traps, and makes each call
under a handler of the trap. A call that traps is -1, and the port must
answer `None` for exactly those: 183 of the notes and pairs, and 4 of the
envelopes. A NaN result is compared as a NaN, whatever its sign and
payload.

### A channel's next sample

`src/xm_sample.bend` is `jar_xm_next_of_sample`, with linear interpolation
and ramping on (jar_xm loads every module so, and raylib changes neither):
`sample.next(sampled, tone, head, previous)` is one step of a channel
through its sample. A `Tone` is the sample as the step reads it (length,
loop, whether it is stereo, its floats); a `Head` is what the step keeps of
the channel: its position in the sample and how far a frame moves it, its
frame count since the note began, the eight last values of the sample
before it, left and right, and its value now.

- **The value** is the line between the float at the position and the next
  one, by the position's fraction. A stereo sample's right side is the
  data's second half. The float after a loop's end is the loop's start;
  after the last float of a sample that does not loop it is 0.
- **The position** moves on by the step. A sample that does not loop ends
  at its length (the position becomes -1, and the channel is silent from
  then on); a loop goes back by its length at its end, and to its start
  from the sample's length on. Only forward loops arise: the loader makes
  ping-pong loops forward ones.
- **Where the value goes**: to the channel (`previous` -1), or to one of
  the eight values kept (0 to 7), which is how a new note takes the last
  eight values of the sample it replaces.
- **A channel without a sample to play** (none, or a position below 0) is
  silent; in its first eight frames the silence is reached from the values
  kept, an eighth further a frame.
- **Not fine** (`Stepped.fine` false): a position that is not an unsigned
  int (a NaN, 2^32 or more: C's conversion is undefined) and a read past
  the sample's floats (a loop that ends past the data, a start past it, a
  length the data does not have).

`tools/xm_sample_probe.py` (gate `xm-sample`) runs `jar_xm_next_of_sample`
by scripts on 111 samples and channels the reference sets up (3562 calls):
a frame of the mixer, a new note's eight calls, and the channel without
its sample. As in the xm-pitch gate, jar_xm says what is undefined by
itself: besides the compiler's traps, the sample's floats lie at the end of
readable memory with 20 GiB after them that are not, so a read past them
faults. 39 runs end that way, 18 of them at their first call, and the port
finds exactly those steps not fine.

### Rows and ticks

`src/xm_player.bend` is the player itself: `jar_xm_row`, `jar_xm_tick`,
`jar_xm_handle_note_and_instrument`, `jar_xm_trigger_note`, the effects,
`jar_xm_reset` and `jar_xm_get_remaining_samples`.
`player.new(libm, module, rate, random)` is the context as
`jar_xm_create_context_safe` leaves it; `tick(player)` is one tick (a row's
first tick plays the row); `remaining.samples(player)` the song's length in
samples, counted by playing its ticks without sound until a row comes
again; `reset(player)` the song's start.

A `Player` has the song (tempo, BPM, global volume, a position jump or a
pattern break to come, the random waveform's state), its place (the
order's entry, the row, the tick), the samples left in the tick, the count
of each row's passes, and the channels. A `Channel` has its instrument, its
sample and the slot it plays, its place in the sample (the `Head` of *A
channel's next sample*), its pitch, its levels (volume, panning, the
envelopes' values, the fadeout, what the mixer ramps to), its vibratos,
tremolo and arpeggio, and the effect parameters it remembers.

- **A row** gives each channel its slot: an instrument (a number past the
  module's cuts the note), a note (a new note keeps the last eight values
  of the sample it replaces, takes its sample by the instrument's note
  table and begins; under a tone portamento it only sets the period to
  slide to; 97 is a key off), then the effect column. Every effect and
  volume-column command of jar_xm is there, with its quirks: `HAS_VIBRATO`
  tests the parameter for 6 where the effect is meant, a ghost instrument
  begins the envelopes again, E60 leaves its row for the next pattern, a
  restart position is kept in a byte.
- **A tick** runs each channel's envelopes and instrument vibrato, ends an
  arpeggio or a vibrato the slot no longer has, applies the volume column
  and the effects that go on every tick, and works out the volume and
  panning to reach. The panning is `panning + (envelope - .5f)*(.5f -
  fabs(panning - .5f))*2.0f`: `fabs` makes that a binary64 product and
  sum, narrowed to a float once (Jonmath's soft binary64).
- **The length** adds each tick's samples (`rate/(0.4*BPM)`, a float) to a
  64-bit total, which C does as a float sum: past 2^24 samples the total is
  rounded as a float is. The port counts in 32 bits.
- **The random waveform** is one `static` state for every module a program
  plays; the player takes it when it is made and keeps it in its song.
- **`reset`** cuts the notes and puts the place, tempo, BPM and global
  volume back. Everything else stays as the length's silent playing left
  it: the channels' samples and positions, the rows' counts, the samples
  left in the tick.
- **Stopped (`Player.why`): 1, what C leaves undefined.** A note begun on a
  channel without a sample (a note delay with neither note nor instrument,
  a retrigger: `jar_xm_trigger_note` reads the sample's panning through a
  null pointer); a row outside its pattern's slots (a break or a jump to a
  row the pattern has not: jar_xm reads the slots where they would be, in
  whatever lies after them) or a pattern the module has not; E5y with y
  below 8 (a negative int shifted left); an envelope's loop or sustain
  point past its 12th; a step of a sample that is not fine; a row counted
  outside jar_xm's block of memory; an Amiga period C does not define.
- **Stopped: 2**, a song that comes to no row again in 4096 times 4096
  ticks; **5**, what the libm profile does not give (`powf(2, y)`, `sinf`)
  or a value the binary64 helpers do not take.

`tools/xm_player_probe.py` (gate `xm-player`) runs scripts of ticks,
lengths and resets on 20 modules and hashes the whole context after every
one of 11460 ticks: raylib's `mini1111.xm` for its length first as raylib
asks (2974098 samples: 62 s at 48000 Hz), tick by tick past its end, and
with resets between; four seeded modules of effects that play on for long,
in linear and Amiga frequencies; six of every effect, which play until
they meet something undefined; and modules built for one thing each
(jumps, breaks, loops and delays; a delay on a channel without a sample; a
finetune below 8 and one above; a sustain point past its envelope; a break
past its pattern). jar_xm says what is undefined as in the gates above
(traps, and its block of memory under a guard with the bytes after it
looked at); the row outside its pattern is the one thing the program works
out itself, before each tick, as `jar_xm_row` does. Each module is played
in a process of its own, because of the random waveform's state. 10 runs
end undefined, and the port's player has stopped at the same call in each.

### The mixer

`src/xm_mixer.bend` is `jar_xm_mixdown` and `jar_xm_generate_samples`, as
raylib plays a module (ramping on, no limit of loops): `generate(player,
count)` is `count` frames of two floats, `Generated{player, samples}`.

A frame: where the tick's samples are spent, a tick; one sample less left
in it; then each channel that has an instrument, a sample and a position
not below 0 takes its next sample, adds it times its volume and times one
less its panning to the left sum and times its volume and its panning to
the right one, counts its frame, and moves its volume and panning a 128th
towards what the tick set. The sums are multiplied by the global volume
(unless that is 1) and kept from -1 to 1. `generated.of(player)` is the
count of samples asked for so far (`generated_samples`, a 32-bit count
here), which is what raylib's `GetMusicTimePlayed` reads for a module.

A player that stops (a sample step that is not fine, or anything a tick
stops for) gives the frames before that; `Pl.Player.why` says so.

`tools/xm_mixer_probe.py` (gate `xm-mixer`) generates 164741 frames in 23
runs and hashes every float with the count and the whole context after
each call: raylib's `mini1111.xm` as raylib plays it (the length, the
reset, then 4096, 4096, 2048 and 1 frames by `jar_xm_generate_samples`
itself at 48000 Hz) and by frames with a reset between, and the xm-player
gate's built modules at 8000 Hz, where a tick is a hundred samples or so
and a few thousand frames go through many rows. What is undefined is found
as in that gate; for it most runs' frames are made by the program's copy
of `jar_xm_generate_samples`' loop, which makes each tick itself where one
is due and then calls `jar_xm_mixdown`. 6 runs end undefined, and the
port's player has stopped in the same call.

Still to come: the music stream (`LoadMusicStream` for `.xm`).

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

Not yet available: OGG, FLAC, XM and MOD data, and MP3 Layers I and II (above). Gaps of `WaveFormat`:
the refusals above, and no GPU evidence.

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
| `Sound.load_with(profile, libm, device, path)` / `load_for(profile, device, path)` / `load` | `LoadSound` | `Wave.load_for` then the above. `load_for` uses `M.AppleLibm{}`. |
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
  sound: missing files, bad data; and OGG, FLAC, XM and MOD files,
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
| `AudioStream.set_callback(device, stream, on)` | `SetAudioStreamCallback` | With a callback (`on`) the stream's frames are the callback's; without one (NULL) its halves' again. See below. |

`AudioStream.load` gives a stream without a buffer (0, with the fields
given) where miniaudio makes no converter: an unready device, a rate of 0,
no channels. Jonlib also gives none for sample sizes other than 8, 16 and 32
(raylib takes them for 32-bit float and fills part of each sample), a
default size that is a negative int, and buffers of more than 2^22 samples.
A stream's buffer also counts the frames it was given since it was last
played or stopped (raudio's `framesProcessed`, an unsigned int): the frames
of each `UpdateAudioStream` that found a processed half, written or not,
and the frames its callback wrote. The music functions read it.

`AudioStream.update` leaves the state as it is on an unready device, for a
buffer that is 0, not tracked or a sound's (raylib writes the sound's
samples as if they were a stream's), and for a `data` that does not hold
`frames*channels` samples. `Sound.update` leaves a stream's buffer as it is.

A playing stream takes part in the mixer's callbacks (below). It never
ends: the device reads the frames left in the half its cursor is in, goes on
in the other half, and wraps; a half read to its end is processed, and a
half that is processed gives nothing, so a stream the program does not feed
plays silence where its cursor waits. A stream that is not fed in time
underruns exactly as raylib's does.

**Stream callbacks.** raylib keeps the function given to
`SetAudioStreamCallback` and calls it from inside the device's callback
whenever the mixer wants frames of the stream: the function writes them,
and the halves are not read (neither the cursor nor the processed flags
move; `UpdateAudioStream` still writes the halves, unheard). Jonlib keeps
no function. A stream with a callback takes its frames from *answers* the
program gives with the device callback:

| Function | Contract |
|---|---|
| `AudioDevice.asks(device, frames) -> Maybe<List<AudioAsk{buffer, frames}>>` | What the stream callbacks will be asked for in a device callback of `frames` frames, in order: the stream's buffer and the frames to write. The device is not changed. None where `AudioDevice.mix` refuses. |
| `AudioDevice.mix_answered(device, frames, answers)` | `AudioDevice.mix` with the callbacks' answers: the samples they wrote, one answer after the other in the order of the asks, in each stream's own format. None, and the device as it was, when the answers are not exactly the frames asked for. |
| `AudioClock.advance_answering(~P, ~answer, clock, device, time, state)` | `AudioClock.advance` with the program's callback: `answer(buffer, frames, state)` gives the state after the call and the frames written. It is called once for every ask of each period, in order, before that period is mixed. `answer` is a template (`~`): it closes over nothing, and what it needs is in the state. |

The asks are raudio's: each time a playing stream's converter needs input,
`(unsigned int)(((float)source/rate)*frames wanted)` frames, at least 1 and
at most the frames its 4096-byte buffer holds, and again while the
converter wants more (a 44100 Hz mono float stream is asked for 441 frames
in a 480-frame period; a 600-frame callback asks for 470, 80 and 1). They
depend on the rates and on what the converters hold, never on a sample, so
Jonlib knows them before the callback is made: the program's function runs
between `asks` and `mix_answered`, with the same counts in the same order
as raylib's. `AudioDevice.mix` itself refuses a callback in which a
stream's callback would be asked. A sound's buffer takes no callback
(raylib would call it for the sound's frames).

**Processors.** `AttachAudioStreamProcessor` and `AttachAudioMixedProcessor`
give raylib functions that write over frames inside the device's callback.
A buffer's processors are called, in the order they were attached, on each
run of at most 512 frames the buffer gives: stereo f32, after the buffer's
converter and before its volume and pan. The mixed processors are called on
the whole mix, after every buffer and before the master volume and the
clip. A run that gives no frame calls nobody. Jonlib keeps no function: a
processor is a number the program chooses (a *tag*), and the lists are a
value of their own, `AudioProcessors`.

| Function | raylib | Contract |
|---|---|---|
| `AudioProcessors.none()` | | No processor. |
| `AudioStream.attach_processor(processors, device, stream, tag)` | `AttachAudioStreamProcessor` | The tag becomes the last processor of the stream's buffer (a sound's `stream` too). |
| `AudioStream.detach_processor(processors, device, stream, tag)` | `DetachAudioStreamProcessor` | Every processor of the buffer with the tag goes. |
| `AudioDevice.attach_mixed_processor(processors, device, tag)` | `AttachAudioMixedProcessor` | The last of the mixed output's. The list outlives `CloseAudioDevice`. |
| `AudioDevice.detach_mixed_processor(processors, device, tag)` | `DetachAudioMixedProcessor` | Every mixed processor with the tag goes. |
| `AudioDevice.mix_processed(~P, ~process, device, processors, frames, answers, state)` | | `AudioDevice.mix_answered` with the processors: `process(tag, samples, state)` gives the program's state after the call and the samples written over the ones given (two f32 bits a frame). |
| `AudioClock.advance_processing(~P, ~answer, ~process, clock, device, processors, time, state)` | | `AudioClock.advance_answering` with the processors, period by period. |

The lists are left as they are on an unready device (raylib locks a mutex
that does not exist) and for a stream whose buffer is 0 or not tracked
(raylib reads through the pointer). A processor must give back as many
samples as it was given: otherwise the callback is refused, the device as
it was. `process` is a template and closes over nothing, like `answer`. It
runs inside the callback, so a program that wants raylib's bits there
computes as the callback does (`Mixer.fadd`, `Mixer.fmul`, ...: on x86-64
miniaudio disables denormals around it).

**`audio_stream_callback`.** The example keeps the last second its callback
wrote in `static float buffer[SAMPLE_RATE]` and draws the last 10 ms as 800
columns; the end of column 799 is `buffer[SAMPLE_RATE - SAMPLE_RATE/100 +
800*SAMPLE_RATE/100/screenWidth]`, which is `buffer[44100]`: one float past
the array, in every frame (AddressSanitizer: a global-buffer-overflow read
of 4 bytes at line 137, 0 bytes after `buffer`, in the first frame). Its
behavior is undefined from there. `examples/audio_stream_callback.bend`
runs the clock, the stream's callback as the `answer` of
`AudioClock.advance_answering` (the four waves, the frequency taken at a
wave's next period, the wavelength of each call fixed when it begins), the
keys, the texts and the 799 columns whose samples are in the buffer, and
then refuses the frame, every frame; the reference is not run
(`UNDEFINED_NATIVE` in `tools/examples_probe.py`).

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
- raudio asks the buffer for `(unsigned int)(((float)source/rate)*frames)`
  input frames (the buffer's own rate over the converter's output rate; at
  least 1, at most the frames its 4096-byte input buffer holds: 512 of a
  sound's, 2048 of a 16-bit mono stream's) each time the converter needs
  more; frames the converter did not take wait in a residual of at most 8
  frames (more are lost), which is fed first the next time, on the next
  `PlaySound` too.
- A stream's frames go through the whole data converter, in miniaudio's
  order: the samples to f32 (`(x - 128)/128` for 8-bit ones, `x/32768` for
  16-bit ones), more than two channels mixed to stereo with the default
  channel maps' weights before the resampler, and one channel resampled and
  then copied to both sides. miniaudio converts through 4096-byte
  temporaries, so one conversion is several passes whose sizes depend on the
  format and channels, and for one channel or more than two a pass takes no
  more input than `ma_linear_resampler_get_required_input_frame_count` says:
  what is left over is raudio's residual. All of it is reproduced, because
  it decides which frames the residual loses.
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
both must give the same binary32); a playing stream of more than 1024
channels (raudio's input buffer or miniaudio's temporary holds no frame of
it); and a callback in which a NaN results (its bits are the host's).

**Subnormals.** miniaudio runs the callback with denormals disabled
(`ma_device_disable_denormals`). On x86-64, the reference here, that is
MXCSR's denormals-are-zero and flush-to-zero: every operation of the
callback takes a subnormal operand for the zero of its sign and gives a
zero for a result that would be subnormal. Jonlib's callback computes that
way on every host and target: a filter's tail decays to exact zeros, a
subnormal volume is silence, and a subnormal sample is not heard. Hosts
where miniaudio leaves subnormals alone (AArch64) are a different profile
that is not ported.

### Music streams

A music is an audio stream and the decoder that fills its two halves.
raylib's `Music` is a struct the program copies while its `ctxData` points
at the decoder; in Jonlib the decoder's state is in the `Music` value, so
what moves it gives the music back.

| Function | raylib | Contract |
|---|---|---|
| `Music.load(device, path)` / `Music.load_from_memory(device, type, bytes)` | `LoadMusicStream` / `LoadMusicStreamFromMemory` | A WAV, QOA or MP3 file: a stream of the file's rate and channels, the frame count, looping on. 16- and 24-bit WAV files play as 16-bit samples (`drwav_read_pcm_frames_s16`), 32-bit ones as floats (`drwav_read_pcm_frames_f32`: a PCM sample `x` is `(float)(x/2147483648.0)`, an IEEE float its own bits). A QOA file plays as floats, `sample/32768.0` (`qoaplay_decode`), and its frames are the header's count. An MP3 file plays as floats too, its 16-bit samples over 32768 (`drmp3_read_pcm_frames_f32`), at its first frame's rate and channels; its frames are `drmp3_get_pcm_frame_count`: an Xing/Info frame's count less the LAME delay and padding, or every frame counted. The stream has no buffer on an unready device; the music is still loaded. |
| `Music.is_valid(music)` | `IsMusicValid` | A decoder, frames, and a rate, sample size and channels that are not 0. |
| `Music.unload(device, music)` | `UnloadMusicStream` | The stream's buffer is untracked. |
| `Music.play` / `pause` / `resume` / `is_playing` / `set_volume` / `set_pitch` / `set_pan` | `PlayMusicStream` ... | The stream's. |
| `Music.update(device, music) -> AudioDevice & Music` | `UpdateMusicStream` | Each processed half of a playing music's stream takes the decoder's next frames, the first half then the second. The frames to stream are a whole half while the music loops or has as many left (`frameCount - framesProcessed`, unsigned), else what is left (zeros after them); a read past the file's end goes on from its first frame. With none left, the music stops once both halves are processed, its decoder back at the first frame. |
| `Music.stop(device, music) -> AudioDevice & Music` | `StopMusicStream` | The stream stops and the decoder goes back to its first frame, playing or not. |
| `Music.seek(device, music, position) -> AudioDevice & Music` | `SeekMusicStream` | The decoder goes to frame `(unsigned int)(position*sampleRate)`, at most the file's last; the stream's `framesProcessed` is that frame, not clamped, and both halves are processed. A QOA music goes to the start of the QOA frame (5120 samples) the position is in, at most that of frame `samples/5120` (`qoaplay_seek_frame`), and that is its `framesProcessed`. |
| `Music.time_length(music)` | `GetMusicTimeLength` | `(float)frameCount/sampleRate`. |
| `Music.time_played(device, music) -> Maybe<F32>` | `GetMusicTimePlayed` | `framesProcessed`, less the frames still in the halves (no more than the music has unless it loops), plus those of the half being played that went to the mix, modulo `frameCount` as C ints (plus `frameCount` when negative), over the rate. 0 without a buffer. |

`looping` is a field of the value, set as in raylib (`music.looping = false`
is `Music{stream, frames, False{}, kind, context}`). A program calls
`Music.update` each frame after its clock's `advance`, as the examples call
`UpdateMusicStream`: the halves the device read through in between are
filled again.

Not loaded (a typed error, and no stream): WAV sample sizes other than 16,
24 and 32 bits (raylib streams whatever its shared buffer holds for them),
what `Wave.decode` refuses, a QOA file that does not hold every frame its
header counts (qoaplay decodes a frame at a time and would play what is
there), an MP3 file dr_mp3 does not open or whose first frame is of Layer I
or II (not decoded yet), and every other format. OGG, FLAC, XM and MOD
music are not ported yet. Left as they are: `Music.update` for a
music without frames (raylib reads it for ever when it loops);
`Music.seek` for a position whose frame is not an unsigned int, a stream
without a tracked buffer (raylib writes through the pointer) and an unready
device. `Music.time_played` is None for a music without frames (raylib
divides by them), counts that do not fit an int, an untracked buffer and an
unready device. A WAV or QOA file's frames are all decoded when it is
loaded.

An MP3 music is decoded as it plays (`MusicMp3`, a stream of
`src/mp3_stream.bend`). `Music.update` reads the frames a half needs
(`drmp3_read_pcm_frames_f32`) and, whenever a read comes short, takes the
stream back to its start and reads on, as raylib does whether the music
loops or not. `Music.stop` takes it to its start
(`drmp3_seek_to_start_of_stream`). `Music.seek` is
`drmp3_seek_to_pcm_frame`, which goes by dr_mp3's own count of frames: the
LAME delay is in that count and not in the frames read, so in a file with
a delay the frame reached is not the one the position names (see the
stream, above); the stream's `framesProcessed` is the frame asked for, as
for the other formats. `frameCount` can be more than the stream holds (a
cut file keeps its Info frame's count): the music then goes round at the
stream's end. A stream that gives no frame from its start would keep
raylib in its read loop for ever; the update ends there with zeros. A
stream that stops at a frame the decoder refuses plays what came before
it, round and round: that differs from raylib, which decodes Layer I and
II frames. On the JavaScript target a frame takes about 95 ms to decode,
3.6 times its 26 ms of sound.

### The clock

raylib's device runs on a thread of its own: as the device plays, miniaudio
asks it for one callback per period (480 frames, 10 ms). Jonlib has no
thread and no host device. Time is the program's (`Core.get_time`), and an
`AudioClock` makes the callbacks that were due by a time when the program
says so:

| Function | Contract |
|---|---|
| `AudioClock.at(time)` | The clock of a device opened at `time` (`InitAudioDevice` then): no period asked for yet. |
| `AudioClock.advance(clock, device, time) -> AudioStep{clock, device, fine}` | Every whole period between the opening and `time` that was not asked for yet is one `AudioDevice.mix(device, 480)`, in order: `(int)((time - opened)*100.0)` periods in all, in binary64. The samples go nowhere. An unready device makes no callback and its periods pass. |

A program calls `AudioClock.advance` with the frame's time at the start of
its update, before it asks `IsSoundPlaying` or `IsAudioStreamProcessed`:
what it then sees is what raylib shows once its thread has caught up with
that time. `fine` is false, with the clock as it was, for a time before the
opening or outside the binary64 helpers' domain, for more than 65536 periods
at once (about eleven minutes) and when a callback is one Jonlib does not
mix (the device is then as that callback found it).

This is a model of the device thread, not a measurement of it: a real
device's callbacks come when the host schedules them, a little later than
their period and not always one period at a time. The reference of the
examples that need the clock is built the same way (below).

### How it is verified

`tools/sound_probe.py` (gate `sound`) compiles `raudio.c` itself into the
reference program, with `-ffp-contract=off` and only miniaudio's null
backend, so that the program can read `AUDIO` and the audio buffers, and
stops the device right after `InitAudioDevice`: its thread mixes nothing,
and the program asks for each callback itself
(`ma_device_handle_backend_data_callback`) with the script's frame counts.
124 scripts of 1260 steps over four sound slots run on both sides and on a
Python model of raudio's state; after every step the ready flag, the master
volume bits, every slot's handle fields with `IsSoundValid` and
`IsSoundPlaying`, and every tracked buffer (its number, block, size, volume,
pitch and pan bits, flags, an FNV-1a hash of its samples, its converter's
input and output rates, its cursor, the resampler's timer, the two frames it
holds, the filter's register and coefficient, the residual, and for a
stream its format, channels, the two processed flags, whether it has a
callback and its `framesProcessed`) must be equal,
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
1:1). Playing streams: silence from unfed ones, a 48000 Hz float stream fed
and mixed across both halves with an underrun, a pause, a stop and a replay;
a 44100 Hz 16-bit mono one with pitches of 1.5 and 0.25 (reads of 661 frames
at once); 8-bit stereo and mono ones at 22050 and 8000 Hz with a volume and
a pan; 3 and 6 channels at 32000 and 96000 Hz; 400 channels at a pitch of 6
(passes of two frames); and a stream beside a pitched sound and its alias.
Subnormals: samples, volumes, pans and master volumes that are subnormal or
make subnormal products, in sounds and in a stream. Stream callbacks (the
reference gives raylib a C function per slot that writes a counted pattern
in the stream's format and notes what it was asked for; the asks are
compared too): a 44100 Hz float stream in callbacks of 1, 480 and 600
frames, paused, stopped and played again; 16-bit stereo and 8-bit
3-channel ones with pitches; a callback set and removed over fed halves;
two callback streams (one of 6 channels at 96000 Hz, asked 170 frames at a
time) beside a pitched sound; and `AudioClock.advance_answering` itself over
3, 2, 1 and no periods with a callback stream, a fed stream and a sound,
against as many 480-frame callbacks of the reference, and on a closed
device. Processors (the reference attaches C functions: one halves the
level, one swaps the sides and adds a counted offset, one delays by a frame
it keeps; every call and its frame count is compared, and each buffer's
list and the mixed one are part of the state): on a sound and on streams,
several in order, the same one twice, detached while playing, on runs of
512, 88 and 1 frames of callbacks of 600, 1100 and 513, mixed ones across a
close and a new device, and with a callback stream under the clock. Music
(four generated WAV files: 16-bit stereo at 22050 Hz, 24-bit mono at
44100 Hz, float mono at 48000 Hz and 32-bit PCM stereo at 8000 Hz; each
music's validity, frame count, looping flag, decoder position
(`drwav.readCursorInPCMFrames`), `GetMusicTimeLength` and
`GetMusicTimePlayed` bits are part of the state): updates that fill both
halves and wrap round the file, a music that does not loop to its end and
its stop, seeks inside, past the end and to a frame between -1 and 0, a
stop and a play, pauses, a music loaded before the device, a missing file,
a processor on a music under the clock, and an unload; and the QOA music of
raylib's examples (`target.qoa`, 44100 stereo frames at 22050 Hz, which the
reference also decodes with `LoadWave` for the model): updates of 2000-frame
halves, seeks to QOA frames inside, into the last one and past the end, the
read that goes round the end of the file, a stop and a play that does not
loop, and raylib's own 12800-frame halves. The waves are
8-, 16- and 32-bit, of 1, 2, 4 and 6 channels, at 48000, 8000, 22050, 44100
and 96000 Hz, with the empty cases above, and the files are the four `.wav`
files of the examples that only play sounds (`boom`, `buttonfx`, `sound`,
`coin`; 26522 to 48000 frames each), a small generated one, a missing one,
one that is not a WAV and another extension. 83 scripts are compared with
raylib; the 41 with a step raylib has no defined answer for, or a step or
a callback Jonlib refuses, are checked against the model on Jonlib alone. `IsSoundPlaying` is asked of raylib only on
a ready device and for a tracked buffer, and no script opens the device over
a playing buffer (raylib would mix it before the reference can stop it). CPU-1,
CPU-2 and JavaScript.

The examples that play sounds without showing audio state
(`textures_sprite_button`, `textures_sprite_explosion`, `audio_sound_multi`,
`audio_sound_positioning`, and `audio_sound_loading`, whose second sound
is an Ogg Vorbis file) replay against the native example with
`raudio.c` compiled beside it the same way (`tools/examples_probe.py`): its
device mixes on its own thread there, and no frame depends on it.

The examples whose frames do show what the device did (`audio_raw_stream`:
the time its sine's last period began, which depends on when the device had
read a half of the stream through) are replayed against a reference with
the same clock (`tools/reference/audio_clock.c`): raudio.c with two probe
functions, one that stops the device's thread as soon as `InitAudioDevice`
has opened it (no buffer exists yet, so the thread mixed nothing) and one
that asks the stopped device for callbacks of 480 frames through
miniaudio's own entry point. The example's `InitAudioDevice` notes the
scripted clock, and the start of every loop pass (`WindowShouldClose`) asks
for the periods due since, `(int)((clock - opened)*100.0)` in all. The
callbacks, the stream and the mixer are raylib's own; only their timing is
the probe's.

**A spectrum no frame shows.** `audio_spectrum_visualizer` loads
`country.mp3` whole as a wave, feeds a stream from it and, each frame, makes
a spectrum of the last samples for a fragment shader to draw: a Blackman
window, a 1024-point fast Fourier transform (`cosf` and `sinf` twiddles,
float products and sums), 512 magnitudes smoothed over time, and
`logf(fmaxf(magnitude, 1e-40f))` on a scale from -100 to -30 decibels,
written as the red of a 512x1 image. The software renderer runs no shader,
so the example's frames are an empty render texture and its replay compares
only that the port loads the wave, feeds the stream and refuses nothing.
`tools/spectrum_probe.py` (gate `spectrum`) compares the spectrum itself:
the example's source is included in the reference program with its `main`
renamed, and its own `CaptureFrame` and `RenderFrame` run over 50 frames of
samples (silence, tones, square waves, noise, an impulse, the quietest
samples, and silence until the 45-row history has gone round) beside the
port's `capture` and `render`: the smoothed magnitudes' bits and every
pixel are equal. The port computes the window's weights and the twiddle
factors once, since they depend on their place alone; the example computes
them again every frame, with the same result.

Not yet available: the fused (FMA) profile of the mixer, the profile of
hosts that keep subnormals in the callback, music from files other than
WAV, QOA and MP3, and a host device (the clock is a model of its thread).
No GPU evidence.
