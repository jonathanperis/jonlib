#!/usr/bin/env python3
"""Compare dr_mp3's opening and frame counting with src/mp3.bend.

The reference is dr_mp3 itself (pinned raylib's src/external/dr_mp3.h, as
raylib compiles it): `drmp3_init_file`, then the stream's channels, sample
rate, LAME delay and padding, the offset its frames start at, the frame count
an Xing/Info frame gives (or none), whether its first frame stays to be
played, `drmp3_get_pcm_frame_count` (raylib's music.frameCount) and
`drmp3_get_mp3_and_pcm_frame_count` (every frame decoded without its samples).

There is no MP3 encoder here. The files are raylib's examples/audio/resources/
country.mp3 (MPEG-1 Layer III, 128 kbit/s, 44100 Hz, joint stereo, an Info
frame with a LAME tag: 3583 frames) and edits of its first frames: without the
Info frame, cut inside a frame, one and two frames, bytes that are no frame
before and inside the stream, ID3v2 tags (with and without a footer), an
ID3v1 tag and APE tags at the end, another sample rate in one header, every
header rewritten (free format, with a CRC, mono, MPEG-2, MPEG-2.5, Layers I
and II, the reserved layer, bit rate and sample rate), files too short to
open, and 48 seeded edits (bytes changed, removed and inserted). Every value
must be equal, or both sides must refuse the file. CPU/JS.
"""
import hashlib
import json
import random

import probekit
from probekit import ROOT, ProbeFailure

WORK = '.build/mp3-probe/cases'
SOURCE = 'examples/audio/resources/country.mp3'

NATIVE = r'''#define DR_MP3_IMPLEMENTATION
#include "external/dr_mp3.h"
#include <stdio.h>

static const char *files[] = { FILES };

int main(void)
{
    for (unsigned a = 0; a < sizeof(files)/sizeof(files[0]); a++)
    {
        drmp3 mp3;
        drmp3_uint64 frames = 0, samples = 0;
        if (!drmp3_init_file(&mp3, files[a], NULL)) { printf("closed\n"); continue; }
        printf("open %u %u %u %u %llu ", mp3.channels, mp3.sampleRate, mp3.delayInPCMFrames, mp3.paddingInPCMFrames, (unsigned long long)mp3.streamStartOffset);
        if (mp3.totalPCMFrameCount == DRMP3_UINT64_MAX) printf("-"); else printf("%llu", (unsigned long long)mp3.totalPCMFrameCount);
        printf(" %d %u", (int)(mp3.pcmFramesRemainingInMP3Frame > 0), (unsigned)drmp3_get_pcm_frame_count(&mp3));
        drmp3_get_mp3_and_pcm_frame_count(&mp3, &frames, &samples);
        printf(" %llu %llu\n", (unsigned long long)frames, (unsigned long long)samples);
        drmp3_uninit(&mp3);
    }
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/mp3.bend as Mp3

def flag(value: Bool) -> String:
  Bool.pick(String, value, "1", "0")

def counted(counts: U32 & U32) -> String:
  (frames, samples) = counts
  U32.show(frames) ++ " " ++ U32.show(samples)

def shown(+stream: Mp3.Stream, first: Bool) -> String:
  Mp3.Stream{_, _, _, +start, _, _, _, _, _, _, _, +delay, +padding, +known, +total, +channels, +rate} = stream
  "open " ++ U32.show(channels) ++ " " ++ U32.show(rate) ++ " " ++ U32.show(delay) ++ " " ++ U32.show(padding) ++ " " ++ U32.show(start) ++ " " ++ Bool.pick(String, known, U32.show(total), "-") ++ " " ++ flag(first) ++ " " ++ U32.show(Mp3.total(stream)) ++ " " ++ counted(Mp3.scan(stream))

def line(opened: Maybe<Mp3.Opened>) -> String:
  match opened:
    case None{}: "closed"
    case Some{Mp3.Opened{+stream, first}}: shown(stream, first)

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(line(Mp3.open(bytes)))

def main() -> IO(Unit):
  do IO<Unit>:
'''


def frame_offsets(data):
    """Where the frames of a constant bit rate MPEG-1 Layer III file start (417 bytes, 418 with the padding bit)."""
    offsets, at = [], 0
    while at + 4 <= len(data) and data[at] == 0xFF and (data[at + 1] & 0xE0) == 0xE0:
        offsets.append(at)
        at += 417 + ((data[at + 2] >> 1) & 1)
    return offsets


def rewritten(data, offsets, change):
    """The frames with every header changed by change(header bytes)."""
    out = bytearray(data)
    for at in offsets:
        if at + 4 <= len(out):
            out[at:at + 4] = change(bytearray(out[at:at + 4]))
    return bytes(out)


def header(index, clear, put):
    def change(h):
        h[index] = (h[index] & ~clear & 255) | put
        return h
    return change


def cases(source):
    """name -> bytes: the whole file and edits of its first frames."""
    offsets = frame_offsets(source)
    if len(offsets) != 3584 or offsets[:3] != [0, 417, 834] or source[36:40] != b'Info':
        raise ProbeFailure('mp3: country.mp3 is not the file this probe was written for')
    first, plain = source[:offsets[12]], source[offsets[1]:offsets[13]]
    own = [at - offsets[1] for at in offsets[1:13]]
    footer = b'APETAGEX' + bytes(16) + (40).to_bytes(4, 'little') + bytes(4)
    files = {
        'whole': source,
        'first12': first,
        'noinfo': plain,
        'infoonly': source[:offsets[1]],
        'oneframe': source[offsets[1]:offsets[2]],
        'twoframes': source[offsets[1]:offsets[3]],
        'cut': source[:offsets[6] + 200],
        'junk': b'\x00\x11\x22' * 7 + source[offsets[1]:offsets[9]],
        'hole': source[offsets[1]:offsets[4]] + bytes(300) + source[offsets[5]:offsets[12]],
        'id3v2': b'ID3\x04\x00\x00\x00\x00\x00\x15' + bytes(21) + first,
        'id3v2footer': b'ID3\x04\x00\x10\x00\x00\x00\x05' + bytes(15) + first,
        'id3v2long': b'ID3\x04\x00\x00\x00\x00\x7f\x7f' + first,
        'id3v1': first + b'TAG' + bytes(125),
        'id3v1plain': plain + b'TAG' + bytes(125),
        'ape': first + footer,
        'apebody': source[offsets[1]:offsets[9]] + bytes(40) + footer,
        'apeid3': plain + bytes(40) + footer + b'TAG' + bytes(125),
        'apehuge': plain + b'APETAGEX' + bytes(16) + (1 << 20).to_bytes(4, 'little') + bytes(4),
        'tiny': source[:9], 'ten': source[:10], 'header': source[:4], 'empty': b'',
        'zeros': bytes(5000),
        'free': rewritten(plain, own, header(2, 0xF0, 0)),
        'crc': rewritten(plain, own, header(1, 0x01, 0)),
        'mono': rewritten(plain, own, header(3, 0, 0xC0)),
        'mpeg2': rewritten(plain, own, header(1, 0x08, 0)),
        'mpeg25': rewritten(plain, own, header(1, 0x18, 0)),
        'layer2': rewritten(plain, own, header(1, 0x06, 0x04)),
        'layer1': rewritten(plain, own, header(1, 0x06, 0x06)),
        'layer0': rewritten(plain, own, header(1, 0x06, 0)),
        'bitrate15': rewritten(plain, own, header(2, 0, 0xF0)),
        'rate3': rewritten(plain, own, header(2, 0, 0x0C)),
        'xing': first.replace(b'Info', b'Xing', 1),
        'infoflags0': first[:43] + b'\x00' + first[44:],
        'infonolame': first[:36 + 8 + 4 + 4 + 100 + 4] + b'\x00' + first[36 + 8 + 4 + 4 + 100 + 4 + 1:],
    }
    other = bytearray(plain)
    other[own[3] + 2] ^= 0x0C
    files['othersr'] = bytes(other)
    rng = random.Random(0x6D7033)
    for index in range(48):
        data = bytearray(first if index % 2 else plain)
        for _ in range(rng.randrange(1, 12)):
            kind, at = rng.randrange(4), rng.randrange(len(data))
            if kind == 0:
                data[at] = rng.randrange(256)
            elif kind == 1:
                data[at] ^= 1 << rng.randrange(8)
            elif kind == 2:
                del data[at:at + rng.randrange(1, 40)]
            else:
                data[at:at] = bytes(rng.randrange(256) for _ in range(rng.randrange(1, 40)))
        files[f'edit{index:02}'] = bytes(data)
    return files


def render(selected, gpu):
    return PROGRAM + ''.join(f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), loaded)\n'
                             for _, path in selected) + '    IO.print("done")\n'


def parse(text, selected):
    lines = text.splitlines()
    if len(lines) != len(selected) + 1 or lines[-1] != 'done':
        raise ValueError('mp3: candidate output did not finish')
    return lines[:-1]


def main():
    probe = probekit.Probe('mp3', probekit.arguments(__doc__))
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files = cases((probe.args.raylib_source / SOURCE).read_bytes())
    items = []
    for name, data in files.items():
        (folder / f'{name}.mp3').write_bytes(data)
        items.append((name, f'{WORK}/{name}.mp3'))
    source = NATIVE.replace('FILES', ', '.join(json.dumps(str(ROOT / path)) for _, path in items))
    expected = probe.native(source, 'reference', extra_flags=['-ffp-contract=off', '-Wno-everything'], link_raylib=False).splitlines()
    if len(expected) != len(items):
        raise ProbeFailure(f'mp3: the reference printed {len(expected)} rows for {len(items)} files')
    rows = dict(zip(files, expected))
    if rows['whole'] != 'open 2 44100 1105 577 417 4127616 0 4125934 3583 4127616' or rows['noinfo'] != 'open 2 44100 0 0 0 - 1 13824 12 13824':
        raise ProbeFailure(f'mp3: the reference did not read country.mp3 as expected: {rows["whole"]} / {rows["noinfo"]}')
    closed = sum(row == 'closed' for row in expected)
    if closed < 6 or len(expected) - closed < 40:
        raise ProbeFailure(f'mp3: {closed} of {len(expected)} files refused by the reference; the corpus lost coverage')
    lanes = probe.candidates(render, items, batch=24, parse=parse, timeout=1500)
    probe.compare(expected, lanes, describe=lambda index: items[index][0])
    probe.finish(files=len(items), opened=len(expected) - closed, closed=closed, tagged=sum(' 0 ' in row[-40:] and row.split()[7] == '0' for row in expected if row != 'closed'),
                 files_sha256=hashlib.sha256(b''.join(name.encode() + data for name, data in sorted(files.items()))).hexdigest())


if __name__ == '__main__':
    main()
