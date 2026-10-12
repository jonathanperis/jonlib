#!/usr/bin/env python3
"""Compare Layer III decoding, as far as src/mp3_layer3.bend goes, with dr_mp3.

The reference is dr_mp3 itself (pinned raylib's src/external/dr_mp3.h, built
as raylib builds it: SSE, 16-bit output). Its frame function is run over a
file's bytes the way a caller does, a frame after a frame. The three
functions on the way to a granule's values (drmp3dec_decode_frame,
drmp3_L3_decode, drmp3_L3_huffman) are copied from the header's text with
three lines put in, and the header is not changed: after a channel's
IMDCT and sign change its 576 subband samples are hashed; the Huffman
reader records
whether it read past the main data's array (it reads the granule
information that follows in the struct); and before a granule's short
bands are reordered their end is added up, because a mixed block at 8000 Hz
ends 24 values past the granule's 576 (dr_mp3's table for it has 48 long
values where its reorder begins at 72) and is written over the other
channel or the scales. Both are undefined in C and the port refuses them.
After every frame the row is

  samples:bytes:state:values:pcm

where `state` hashes what the decoder keeps for the next frame (its header,
free format size, the reservoir, the whole main data array with what earlier
frames left in it, the 40 scales, the intensity positions, the second
granule slot's scalefac_compress, both channels' IMDCT overlap and the
synthesis filter's rows), `values` hashes the subband samples of every
channel of every granule, bit for bit, and `pcm` hashes the frame's 16-bit
samples. Thirty floats of the filter's newest row are left out of `state`:
the next call writes them before anything reads them, and until then
dr_mp3 has there whatever its scratch held. A file's
walk ends at `refused` (undefined, on both sides) or `layer12` (a Layer I
or II frame, which the port does not decode yet).

The files: 400 frames of raylib's country.mp3 (its first 200 and 200 from
the middle of the song, which begin without their reservoir), the mp3
gate's edits of its first frames (tags, holes, cuts, rewritten headers,
seeded corruptions), and synthetic streams. There is no MP3 encoder here;
a synthetic frame is a valid header, side information written field by
field from a seeded generator, and random main data. They cover what one
file cannot: MPEG-1, MPEG-2 and MPEG-2.5 at every sample rate, mono and
every stereo mode, CRC, free format, short and mixed blocks, every Huffman
table with its escapes, reservoirs that are short, and side information
that is refused. Mixed blocks at 8000 Hz are drawn in one stream only (it
ends at the first). One stream is built to make the Huffman reader run off
the array. The generated src/mp3_tables.bend is checked against the header
first. CPU/JS.
"""
import hashlib
import json
import random

import mp3_probe
import mp3_tables
import probekit
from probekit import ROOT, ProbeFailure

WORK = '.build/mp3-layer3-probe/cases'
SOURCE = 'examples/audio/resources/country.mp3'
HEADER = 'src/external/dr_mp3.h'

KBPS = {True: [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320], False: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]}
HZ = [44100, 48000, 32000]

OUTSIDE = ('    if (bs_next_ptr - bs->buf > (ptrdiff_t)sizeof(((drmp3dec_scratch *)0)->maindata)) probe_outside = 1;\n')

REORDER = ('            { int probe_end = n_long_bands*18; const drmp3_uint8 *probe_sfb = gr_info->sfbtab + gr_info->n_long_sfb;'
           ' for (; *probe_sfb; probe_sfb += 3) probe_end += 3*probe_sfb[0]; if (probe_end > 576) probe_outside = 1; }\n')

DRIVER = r'''
static unsigned probe_state(const drmp3dec *dec)
{
    unsigned h = probe_bytes(2166136261u, dec->header, 4);
    h = (h ^ (unsigned)dec->free_format_bytes)*16777619u;
    h = (h ^ (unsigned)dec->reserv)*16777619u;
    h = probe_bytes(h, dec->reserv_buf, dec->reserv);
    h = probe_bytes(h, dec->scratch.maindata, (int)sizeof(dec->scratch.maindata));
    h = probe_words(h, dec->scratch.scf, 40);
    h = probe_bytes(h, dec->scratch.ist_pos[0], 39);
    h = probe_bytes(h, dec->scratch.ist_pos[1], 39);
    h = (h ^ (unsigned)dec->scratch.gr_info[1].scalefac_compress)*16777619u;
    h = probe_words(h, dec->mdct_overlap[0], 288);
    h = probe_words(h, dec->mdct_overlap[1], 288);
    for (int i = 0; i < 15*64; i++)
    {
        /* the newest row's third and fourth entries of a group are written by the next call before anything reads them */
        if ((i >= 14*64) && (i < 14*64 + 60) && (i & 2)) continue;
        h = probe_words(h, &dec->qmf_state[i], 1);
    }
    return h;
}

static unsigned probe_shorts(unsigned h, const drmp3d_sample_t *values, int count)
{
    for (int i = 0; i < count; i++) h = (h ^ (unsigned short)values[i])*16777619u;
    return h;
}

static unsigned char data[1 << 21];
static const char *files[] = { FILES };

int main(void)
{
    for (unsigned a = 0; a < sizeof(files)/sizeof(files[0]); a++)
    {
        static drmp3dec dec;
        static drmp3d_sample_t pcm[DRMP3_MAX_SAMPLES_PER_FRAME];
        FILE *f = fopen(files[a], "rb");
        if (!f) { printf("unread\n"); continue; }
        int size = (int)fread(data, 1, sizeof(data), f), pos = 0;
        fclose(f);
        memset(&dec, 0, sizeof(dec));
        drmp3dec_init(&dec);
        printf("frames");
        while (pos < size)
        {
            drmp3dec_frame_info info;
            memset(&info, 0, sizeof(info));
            probe_outside = 0;
            probe_values = 2166136261u;
            int samples = probe_decode_frame(&dec, data + pos, size - pos, pcm, &info);
            if (probe_outside) { printf(" refused"); break; }
            if ((info.layer == 1) || (info.layer == 2)) { printf(" layer12"); break; }
            printf(" %d:%d:%u:%u:%u", samples, info.frame_bytes, probe_state(&dec), probe_values, probe_shorts(2166136261u, pcm, samples*info.channels));
            if (info.frame_bytes == 0) break;
            pos += info.frame_bytes;
        }
        printf("\n");
    }
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/mp3.bend as H
import ../../src/mp3_layer3.bend as L

def fnv(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: fnv(rest, ((h .^. x) * 16777619 : U32))

def fnv.rows(rows: +List<+List<U32>>, +h: U32) -> U32:
  match rows:
    case Nil{}: h
    case Con{+row, rest}: fnv.rows(rest, fnv(row, h))

def fnv.live(row: +List<U32>, +e: U32, +h: U32) -> U32:
  match row:
    case Nil{}: h
    case Con{+x, rest}: fnv.live(rest, (e + 1 : U32), Bool.pick(U32, (e < 60 : U32) && U32.is_ne((e .&. 2 : U32), 0), h, ((h .^. x) * 16777619 : U32)))

def fnv.qmf(qmf: +List<+List<U32>>, +h: U32) -> U32:
  match qmf:
    case Nil{}: h
    case Con{+newest, +older}: fnv.live(newest, 0, fnv.rows(List.reverse(&2, +List<U32>, older), h))

def state(+decoder: L.Decoder) -> U32:
  L.Decoder{H.Dec{+header, +free, +reserv}, +main, +scf, +ist0, +ist1, +compress, +overlap0, +overlap1, +qmf} = decoder
  fnv.qmf(qmf, fnv(overlap1, fnv(overlap0, fnv([compress], fnv(ist1, fnv(ist0, fnv(scf, fnv(main, fnv(reserv, fnv([H.b0(header), H.b1(header), H.b2(header), H.b3(header), free, H.count(reserv, 0)], 2166136261))))))))))

def shown(status: U32, +decoder: L.Decoder, +samples: U32, +bytes: U32, +spectra: +List<+List<U32>>, +pcm: +List<U32>) -> String:
  match status:
    case 0: U32.show(samples) ++ ":" ++ U32.show(bytes) ++ ":" ++ U32.show(state(decoder)) ++ ":" ++ U32.show(fnv.rows(spectra, 2166136261)) ++ ":" ++ U32.show(fnv(pcm, 2166136261))
    case 1: "refused"
    case _: "layer12"

def frames(n: Nat, stop: Bool, last: L.Decoded, +window: +List<U32>, +bytes: U32, +acc: +List<String>) -> +List<String>:
  match n:
    case 0n: acc
    case 1n+rest:
      match stop:
        case True{}: acc
        case False{}:
          L.Decoded{+decoder, +samples, +used, +status, +spectra, +pcm} = last
          +left = (bytes - U32.min(used, bytes) : U32)
          +next = List.drop(&2, U32, window, U32.to_nat(used))
          frames(rest, U32.is_eq(used, 0) || U32.is_eq(left, 0) || U32.is_ne(status, 0), L.decode(decoder, next, left), next, left, Con{shown(status, decoder, samples, used, spectra, pcm), acc})

def printed(lines: +List<String>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{+line, rest}:
      do IO<Unit>:
        IO.print(line)
        printed(rest)

def walked(+bytes: +List<U32>, +size: U32) -> IO(Unit):
  printed(Con{"frames", List.reverse(&2, String, frames(U32.to_nat((size + 1 : U32)), U32.is_eq(size, 0), L.decode(L.Decoder.zero(), bytes, size), bytes, size, Nil{}))})

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: walked(bytes, H.count(bytes, 0))

def main() -> IO(Unit):
  do IO<Unit>:
'''


def function(header, signature):
    """The text of a function of the header, from its signature to its closing brace."""
    if header.count(signature + '\n{') != 1:
        raise ProbeFailure(f'mp3-layer3: dr_mp3.h does not define `{signature}` once')
    start = header.index(signature + '\n{')
    return header[start:header.index('\n}\n', start) + 3]


def patched(text, pairs):
    """`text` with each (old, new) replaced; every `old` must be there exactly once."""
    for old, new in pairs:
        if text.count(old) != 1:
            raise ProbeFailure(f'mp3-layer3: dr_mp3.h is not the one this probe instruments: {text.count(old)} of `{old.strip()}`')
        text = text.replace(old, new)
    return text


def reference(header, paths):
    """The C program: dr_mp3, the three instrumented copies and the walk over `paths`."""
    huffman = patched(function(header, 'static void drmp3_L3_huffman(float *dst, drmp3_bs *bs, const drmp3_L3_gr_info *gr_info, const float *scf, int layer3gr_limit)'), [
        ('static void drmp3_L3_huffman(', 'static void probe_L3_huffman('),
        ('    bs->pos = layer3gr_limit;\n', OUTSIDE + '    bs->pos = layer3gr_limit;\n'),
    ])
    layer3 = patched(function(header, 'static void drmp3_L3_decode(drmp3dec *h, drmp3dec_scratch *s, drmp3_L3_gr_info *gr_info, int nch)'), [
        ('static void drmp3_L3_decode(', 'static void probe_L3_decode('),
        ('        drmp3_L3_huffman(s->grbuf[ch], &s->bs, gr_info + ch, s->scf, layer3gr_limit);\n',
         '        probe_L3_huffman(s->grbuf[ch], &s->bs, gr_info + ch, s->scf, layer3gr_limit);\n'),
        ('        drmp3_L3_change_sign(s->grbuf[ch]);\n',
         '        drmp3_L3_change_sign(s->grbuf[ch]);\n'
         '        probe_values = probe_words(probe_values, s->grbuf[ch], 576);\n'),
        ('            drmp3_L3_reorder(s->grbuf[ch] + n_long_bands*18, s->syn[0], gr_info->sfbtab + gr_info->n_long_sfb);\n',
         REORDER + '            drmp3_L3_reorder(s->grbuf[ch] + n_long_bands*18, s->syn[0], gr_info->sfbtab + gr_info->n_long_sfb);\n'),
    ])
    frame = patched(function(header, 'DRMP3_API int drmp3dec_decode_frame(drmp3dec *dec, const drmp3_uint8 *mp3, int mp3_bytes, void *pcm, drmp3dec_frame_info *info)'), [
        ('DRMP3_API int drmp3dec_decode_frame(', 'static int probe_decode_frame('),
        ('                drmp3_L3_decode(dec, &dec->scratch, dec->scratch.gr_info + igr*info->channels, info->channels);\n',
         '                probe_L3_decode(dec, &dec->scratch, dec->scratch.gr_info + igr*info->channels, info->channels);\n'),
    ])
    prelude = '''#define DR_MP3_IMPLEMENTATION
#include "external/dr_mp3.h"
#include <stddef.h>
#include <stdio.h>
#include <string.h>

static int probe_outside;
static unsigned probe_values;

static unsigned probe_bytes(unsigned h, const drmp3_uint8 *values, int count)
{
    for (int i = 0; i < count; i++) h = (h ^ values[i])*16777619u;
    return h;
}

static unsigned probe_words(unsigned h, const float *values, int count)
{
    for (int i = 0; i < count; i++) { unsigned w; memcpy(&w, &values[i], 4); h = (h ^ w)*16777619u; }
    return h;
}

'''
    return prelude + huffman + '\n' + layer3 + '\n' + frame + DRIVER.replace('FILES', ', '.join(json.dumps(str(path)) for path in paths))


class Writer:
    """Bits written the first the highest."""

    def __init__(self):
        self.bits = []

    def put(self, value, count):
        self.bits += [(value >> (count - 1 - i)) & 1 for i in range(count)]

    def bytes(self):
        bits = self.bits + [0] * (-len(self.bits) % 8)
        return bytes(sum(bit << (7 - i) for i, bit in enumerate(bits[at:at + 8])) for at in range(0, len(bits), 8))


def frame_size(version, bitrate, rate, padding):
    """A Layer III frame's bytes: version 3 is MPEG-1, 2 MPEG-2, 0 MPEG-2.5."""
    mpeg1 = version == 3
    hz = HZ[rate] >> (0 if mpeg1 else 1 if version == 2 else 2)
    return (1152 if mpeg1 else 576) * KBPS[mpeg1][bitrate] * 125 // hz + padding


def side_size(version, mono):
    return ((17 if mono else 32) if version == 3 else (9 if mono else 17))


def header(version, crc, bitrate, rate, padding, mode, low=0):
    return bytes([0xFF, 0xE0 | version << 3 | 0x02 | (0 if crc else 1), bitrate << 4 | rate << 2 | padding << 1 | (low >> 6 & 1), mode << 6 | (low & 0x3F)])


def granule(version, part23, big, gain, compress, block=None, tables=(0, 0, 0), regions=(0, 0), gains=(0, 0, 0), mixed=0, preflag=0, scale=0, count1=0):
    """A granule's side information as (value, bits): `block` None is a granule that does not switch windows."""
    fields = [(part23, 12), (big, 9), (gain, 8), (compress, 4 if version == 3 else 9), (int(block is not None), 1)]
    if block is None:
        fields += [(tables[0], 5), (tables[1], 5), (tables[2], 5), (regions[0], 4), (regions[1], 3)]
    else:
        fields += [(block, 2), (mixed, 1), (tables[0], 5), (tables[1], 5), (gains[0], 3), (gains[1], 3), (gains[2], 3)]
    return fields + ([(preflag, 1)] if version == 3 else []) + [(scale, 1), (count1, 1)]


def side_info(version, mono, begin, private, scfsi, granules):
    """The side information's bytes: main_data_begin, the private bits, MPEG-1's scfsi, then the granules."""
    writer = Writer()
    if version == 3:
        writer.put(begin, 9)
        writer.put(private, 5 if mono else 3)
        for value in scfsi:
            writer.put(value, 4)
    else:
        writer.put(begin, 8)
        writer.put(private, 1 if mono else 2)
    for fields in granules:
        for value, count in fields:
            writer.put(value, count)
    if len(writer.bits) != side_size(version, mono) * 8:
        raise ValueError(f'mp3-layer3: side information of {len(writer.bits)} bits')
    return writer.bytes()


def noise(rng, count, ones):
    """`count` bytes whose bits are 1 with probability `ones`."""
    if ones == 0.5:
        return bytes(rng.randrange(256) for _ in range(count))
    return bytes(sum((rng.random() < ones) << bit for bit in range(8)) for _ in range(count))


def random_granule(rng, version, part23, mixed=True):
    """A granule with every field drawn; now and then one dr_mp3 refuses (big_values over 288, a switching granule of block type 0)."""
    kind = rng.random()
    big = 0 if kind < 0.1 else rng.randrange(60) if kind < 0.35 else rng.randrange(289) if kind < 0.97 else rng.randrange(289, 512)
    block = None if rng.random() < 0.55 else rng.choice([1, 2, 2, 2, 3]) if rng.random() < 0.97 else 0
    return granule(version, part23, big, rng.randrange(256), rng.randrange(16 if version == 3 else 512), block, [rng.randrange(32) for _ in range(3)],
                   (rng.randrange(16), rng.randrange(8)), [rng.randrange(8) for _ in range(3)], rng.randrange(2) if mixed else 0, rng.randrange(2), rng.randrange(2), rng.randrange(2)), block, big


def synthetic(rng, version, rate, frames, ones, free=0, mixed=True):
    """A stream of Layer III frames of one version and sample rate: (bytes, what the generator drew).

    The mode, the CRC, the bit rate and the padding change from frame to frame
    (a stream's frames agree in version, layer and sample rate only).
    main_data_begin is mostly within what the frames before left, and the
    granules' lengths mostly within the main data, as the generator counts them.
    Without `mixed` no granule has the mixed block flag."""
    out, reserv, drawn = bytearray(), 0, dict(frames=0, granules=0, short=0, mixed=0, start_stop=0, linbits=0, mono=0, intensity=0, mono_intensity=0, midside=0, crc=0, reaching=0)
    for _ in range(frames):
        mode, crc = rng.choice([0, 1, 1, 2, 3]), rng.random() < 0.25
        mono, padding = mode == 3, 0 if free else rng.randrange(2)
        while True:
            bitrate = 0 if free else rng.randrange(1, 15)
            size = free if free else frame_size(version, bitrate, rate, padding)
            room = size - 4 - 2 * crc - side_size(version, mono)
            if room >= 0:
                break
        wanted = rng.choice([0, 0, rng.randrange(512 if version == 3 else 256)])
        begin = min(wanted, reserv) if rng.random() < 0.9 else wanted
        count = (1 if mono else 2) * (2 if version == 3 else 1)
        left = (room + begin) * 8 + (0 if rng.random() < 0.95 else rng.randrange(1, 4096))
        lengths = []
        for index in range(count):
            lengths.append(min(4095, left if index == count - 1 and rng.random() < 0.5 else rng.randrange(left + 1)))
            left -= lengths[-1]
        rng.shuffle(lengths)
        granules, bad = [], sum(lengths) > (room + begin) * 8
        for length in lengths:
            fields, block, big = random_granule(rng, version, length, mixed)
            granules.append(fields)
            bad = bad or big > 288 or block == 0
            drawn['granules'] += 1
            drawn['short'] += block == 2 and fields[6][0] == 0
            drawn['mixed'] += block == 2 and fields[6][0] == 1
            drawn['start_stop'] += block in (1, 3)
            drawn['linbits'] += any(value >= 16 for value, bits in fields[5:8] if bits == 5)
        ext = rng.randrange(4)
        out += header(version, crc, bitrate, rate, padding, mode, ext << 4 | rng.randrange(16) | rng.randrange(2) << 6)
        out += noise(rng, 2 * crc, 0.5)
        out += side_info(version, mono, begin, rng.randrange(2), [rng.randrange(16) for _ in range(1 if mono else 2)], granules)
        out += noise(rng, room, ones)
        drawn['frames'] += 1
        drawn['mono'] += mono
        drawn['intensity'] += mode == 1 and ext & 1
        drawn['mono_intensity'] += mono and ext & 1
        drawn['midside'] += mode == 1 and ext == 2
        drawn['crc'] += crc
        drawn['reaching'] += begin > 0
        # the reservoir the decoder has after the frame: nothing after a refused one (it searches again, zeroed)
        have = min(reserv, begin)
        reserv = 0 if bad else min(511, have + room - ((sum(lengths) + 7) // 8 if reserv >= begin else 0))
    return bytes(out), drawn


def outside():
    """Four free-format MPEG-1 stereo frames of 2303 bytes, the largest dr_mp3 finds, whose second runs the Huffman
    reader off the main data's array: its last granule begins at bit 12285 of 22224 and has 288 pairs of codebook 23,
    each an escaped pair of 36 bits ("00000011", then 13 ones and a sign twice); the main data ends after 276 of
    them, the zeros of the array give 26 bits a pair, and the last bytes read are past its 2815."""
    size, version = 2303, 3
    room = size - 4 - side_size(version, False)
    quiet = side_info(version, False, 0, 0, [0, 0], [granule(version, 0, 0, 0, 0)] * 4)
    loud = side_info(version, False, 511, 0, [0, 0], [granule(version, 4095, 0, 0, 0)] * 3 + [granule(version, 4095, 288, 180, 0, None, (23, 23, 23), (15, 7))])
    start = 3 * 4095 - 511 * 8
    bits = [0] * start + ([0, 0, 0, 0, 0, 0, 1, 1] + [1] * 28) * 288
    writer = Writer()
    writer.bits = (bits + [0] * (room * 8))[:room * 8]
    head = header(version, False, 0, 0, 0, 0)
    return head + quiet + bytes(room) + head + loud + writer.bytes() + (head + quiet + bytes(room)) * 2


def other_layer(rng, layer1):
    """Four MPEG-1 frames of Layer I or II at 128 kbit/s and 44100 Hz with random bytes after their headers: dr_mp3 decodes them, the port stops at the first."""
    size = (384 * 128 * 125 // 44100) & ~3 if layer1 else 1152 * 128 * 125 // 44100
    head = bytes([0xFF, 0xFF if layer1 else 0xFD, (4 if layer1 else 8) << 4, 0])
    return b''.join(head + noise(rng, size - 4, 0.5) for _ in range(4))


def corpus(source):
    """name -> bytes, and what the synthetic streams drew."""
    edits = mp3_probe.cases(source)
    offsets = mp3_probe.frame_offsets(source)
    files = {'start': source[:offsets[200]], 'middle': source[offsets[1500]:offsets[1700]]}
    files.update((name, data) for name, data in edits.items() if name != 'whole')
    rng, drawn = random.Random(0x4C33), {}
    for version, label in ((3, 'mpeg1'), (2, 'mpeg2'), (0, 'mpeg25')):
        for rate in range(3):
            for ones in (0.5, 0.2, 0.8):
                # a mixed block at 8000 Hz is refused: one stream of the three has them
                data, counts = synthetic(rng, version, rate, 10, ones, mixed=(version, rate) != (0, 2) or ones == 0.8)
                files[f'{label}-{rate}-{int(ones * 10)}'] = data
                for key, value in counts.items():
                    drawn[key] = drawn.get(key, 0) + value
    for version, label in ((3, 'mpeg1'), (2, 'mpeg2')):
        data, counts = synthetic(rng, version, 0, 8, 0.5, free=300 if version == 3 else 131)
        files[f'{label}-free'] = data
        for key, value in counts.items():
            drawn[key] = drawn.get(key, 0) + value
    files['mpeg1-layer1'], files['mpeg1-layer2'] = other_layer(rng, True), other_layer(rng, False)
    files['outside'] = outside()
    return files, drawn


def render(selected, gpu):
    return PROGRAM + ''.join(f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), loaded)\n'
                             for _, path in selected) + '    IO.print("done")\n'


def parse(text, selected):
    """A file's row is its lines joined, as the reference prints it: `frames`, then a frame's row a line."""
    lines = text.splitlines()
    if not lines or lines[-1] != 'done':
        raise ValueError('mp3-layer3: candidate output did not finish')
    rows = []
    for line in lines[:-1]:
        if line in ('frames', 'unread'):
            rows.append([line])
        elif not rows:
            raise ValueError('mp3-layer3: candidate output does not begin a file')
        else:
            rows[-1].append(line)
    return [' '.join(row) for row in rows]


def first_difference(expected, actual):
    """Where two rows part: the index of the frame and both sides' tokens."""
    a, b = expected.split(), actual.split()
    index = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
    return f'frame {index - 1}: raylib={a[index] if index < len(a) else "(none)"} jonlib={b[index] if index < len(b) else "(none)"}'


def main():
    probe = probekit.Probe('mp3-layer3', probekit.arguments(__doc__))
    text = (probe.args.raylib_source / HEADER).read_text()
    tables = mp3_tables.parse(probe.native(mp3_tables.program(text), 'tables', extra_flags=['-Wno-everything'], link_raylib=False))
    reason = mp3_tables.stale(mp3_tables.render(tables))
    if reason:
        raise ProbeFailure(f'mp3-layer3: {reason}; run python3 tools/mp3_tables.py --raylib-source <raylib>')
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files, drawn = corpus((probe.args.raylib_source / SOURCE).read_bytes())
    items = []
    for name, data in files.items():
        (folder / f'{name}.mp3').write_bytes(data)
        items.append((name, f'{WORK}/{name}.mp3'))
    expected = probe.native(reference(text, [ROOT / path for _, path in items]), 'reference', extra_flags=['-ffp-contract=off', '-Wno-everything'], link_raylib=False).splitlines()
    if len(expected) != len(items):
        raise ProbeFailure(f'mp3-layer3: the reference printed {len(expected)} rows for {len(items)} files')
    rows = dict(zip(files, expected))
    tokens = [token for row in expected for token in row.split()[1:]]
    decoded = sum(token.split(':')[0] not in ('0', 'refused', 'layer12') for token in tokens)
    synthetic_decoded = sum(token.split(':')[0] not in ('0', 'refused', 'layer12') for name, row in rows.items() if name.startswith('mpeg') for token in row.split()[1:])
    music = [token.split(':')[0] for name in ('start', 'middle') for token in rows[name].split()[1:]]
    if len(music) != 400 or music.count('1152') < 395 or not rows['outside'].endswith(' refused') or len(rows['outside'].split()) != 3:
        raise ProbeFailure(f'mp3-layer3: the reference did not walk country.mp3 and the stream built to leave the array as expected: {rows["start"][:80]} / {rows["outside"][:200]}')
    if synthetic_decoded < 120 or tokens.count('layer12') < 2 or min(drawn[key] for key in ('short', 'mixed', 'start_stop', 'linbits', 'mono', 'intensity', 'mono_intensity', 'midside', 'crc', 'reaching')) < 20:
        raise ProbeFailure(f'mp3-layer3: the corpus lost coverage: {synthetic_decoded} synthetic frames decoded, {tokens.count("layer12")} Layer I/II files, drew {drawn}')
    lanes = probe.candidates(render, items, batch=40, parse=parse, timeout=1500)
    probe.compare(expected, lanes, describe=lambda index: items[index][0] + ' ' + next(
        (first_difference(expected[index], rows[index]) for rows in lanes.values() if rows[index] != expected[index]), ''))
    probe.finish(files=len(items), frames=len(tokens), decoded=decoded, synthetic_decoded=synthetic_decoded, refused=tokens.count('refused'), layer12=tokens.count('layer12'),
                 **{f'drawn_{key}': value for key, value in drawn.items()},
                 files_sha256=hashlib.sha256(b''.join(name.encode() + data for name, data in sorted(files.items()))).hexdigest())


if __name__ == '__main__':
    main()
