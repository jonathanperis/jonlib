#!/usr/bin/env python3
"""Compare a Wave loaded from an Ogg Vorbis file with raylib's LoadWave.

The reference is raudio.c itself, compiled into the reference program with
miniaudio's null backend: LoadWave(".ogg"), which is stb_vorbis_open_memory,
stb_vorbis_stream_length_in_samples frames, an RL_CALLOC of that many frames
of shorts (raylib 6.2) and one stb_vorbis_get_samples_short_interleaved for
all of them. Per
file: whether there is a wave, its frame count, sample rate, sample size
and channels, and the FNV-1a of its samples. LoadSoundFromWave of the wave
is compared too (the frame count of the sound's buffer in the device's
format), with the device open.

raylib does not look at how many samples the read gave: a stream that gives
fewer than its length says leaves the rest of the wave zeros, as RL_CALLOC
made it, and those zeros are compared like any sample. The reference
program reads each stream first by itself, with the read's own loop written
out, counting the samples and looking at each float where it would be
converted: for a float the port refuses, or a frameCount*channels past 32
bits (the unsigned product wraps and the buffer is smaller than the wave),
LoadWave is not called, the row is "none", and the port must give no wave
(InvalidWaveData); for zeros past the port's limit of 2^24 samples the row
is "unsupported" (UnsupportedWaveFormat) without loading the wave either.

The files: raylib's target.ogg (and under the token ".OGG"), cut at its
last page, inside it and inside its headers, with seeded damage in its
packets, and with a last page that states another position (unknown, 0,
fewer samples than the stream has, more, past an int and past 32 bits); and streams
built by the vorbis-frame gate's probe with their pages' checksums, of one
channel at 8000 Hz: loud (every sample past a short's range), quiet, with
a position that cuts the last block and one before it, with more than the
stream has, and loud enough to be refused. CPU-1, CPU-2 and JavaScript
lanes.
"""
import json
import struct

from conformance import gradient_reference
import probekit
from probekit import ROOT, ProbeFailure
from vorbis_codebook_probe import Rng
from vorbis_ogg_probe import pages
from vorbis_packet_probe import bodies
import vorbis_frame_probe as fp
import vorbis_length_probe as lp

SOURCE = 'examples/audio/resources/target.ogg'
WORK = '.build/vorbis-wave-probe/cases'
FLAGS = ['-ffp-contract=off', '-DMA_ENABLE_ONLY_SPECIFIC_BACKENDS', '-DMA_ENABLE_NULL', '-D_DEFAULT_SOURCE', '-Wno-everything']
UNKNOWN = 0xFFFFFFFFFFFFFFFF

NATIVE = r'''#include "raudio.c"
#include <stdio.h>
#include <string.h>

static const char *files[] = { FILES };

// Whether FAST_SCALED_FLOAT_TO_INT(temp, x, 15) is undefined or a machine's own: its int subtraction overflows, or x is a NaN.
static int bad(float x)
{
    volatile float sum = x + 384.0f;
    float held = sum;
    unsigned w;
    memcpy(&w, &held, 4);
    return x != x || (w >= 0x80000000u && w <= 0xC3BFFFFFu);
}

// What LoadWave's read makes of the file: the read's own loop (stb_vorbis_get_samples_short_interleaved), counting,
// with each float looked at where it is converted. 0: a float the port refuses, or a frameCount*channels past 32 bits
// (raylib 6.2's RL_CALLOC is given the wrapped product); 1: zeros after the samples read past 2^24 samples, the
// port's limit; 2: a wave to load (a file stb_vorbis does not open has none, and LoadWave says so).
static int whole(const char *path)
{
    int size = 0, n = 0, fine = 2;
    unsigned char *data = LoadFileData(path, &size);
    stb_vorbis *f = data? stb_vorbis_open_memory(data, size, NULL, NULL) : NULL;
    if (f)
    {
        float **outputs;
        unsigned frames = stb_vorbis_stream_length_in_samples(f);
        int len = (int)(frames*f->channels)/f->channels, i, j;
        while (fine && n < len)
        {
            int k = f->channel_buffer_end - f->channel_buffer_start;
            if (n + k >= len) k = len - n;
            for (j = 0; j < k; j++) for (i = 0; i < f->channels; i++) if (bad(f->channel_buffers[i][f->channel_buffer_start + j])) fine = 0;
            n += k;
            f->channel_buffer_start += k;
            if (n == len) break;
            if (!stb_vorbis_get_frame_float(f, NULL, &outputs)) break;
        }
        if ((unsigned long long)frames*f->channels > 0xFFFFFFFFull) fine = 0;
        else if (fine && (unsigned)n < frames && (unsigned long long)frames*f->channels > 16777216ull) fine = 1;
        stb_vorbis_close(f);
    }
    UnloadFileData(data);
    return fine;
}

int main(void)
{
    SetTraceLogLevel(LOG_NONE);
    InitAudioDevice();
    if (!IsAudioDeviceReady()) return 2;
    for (unsigned a = 0; a < sizeof(files)/sizeof(files[0]); a++)
    {
        int made = whole(files[a]);
        if (made == 0) { printf("none\n"); continue; }
        if (made == 1) { printf("unsupported\n"); continue; }
        Wave wave = LoadWave(files[a]);
        if (wave.data == NULL) { printf("none\n"); continue; }
        unsigned h = 2166136261u;
        if (wave.sampleSize != 16) return 3;
        for (unsigned k = 0; k < wave.frameCount*wave.channels; k++) h = (h ^ ((unsigned short *)wave.data)[k])*16777619u;
        Sound sound = LoadSoundFromWave(wave);
        printf("w%u/%u/%u/%u/%u s%u\n", wave.frameCount, wave.sampleRate, wave.sampleSize, wave.channels, h, IsSoundValid(sound)? sound.frameCount : 0);
        UnloadSound(sound);
        UnloadWave(wave);
    }
    CloseAudioDevice();
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M

def fnv(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: fnv(rest, ((h .^. x) * 16777619 : U32))

def sounded(result: J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>) -> String:
  match result:
    case Tuple{_, Fail{_}}: "0"
    case Tuple{_, Done{+sound}}: U32.show(J.Sound.frames(sound))

def told(wave: J.Wave, +audio: J.AudioDevice) -> String:
  J.Wave{+frames, +rate, +size, +channels, +data} = wave
  "w" ++ U32.show(frames) ++ "/" ++ U32.show(rate) ++ "/" ++ U32.show(size) ++ "/" ++ U32.show(channels) ++ "/"
    ++ U32.show(fnv(data, 2166136261)) ++ " s" ++ sounded(J.Sound.load_from_wave(audio, J.Wave{frames, rate, size, channels, data}))

def loaded(result: Result<&1, &1, J.Wave.IOError, J.Wave>, +audio: J.AudioDevice) -> IO(Unit):
  match result:
    case Fail{J.WaveDataError{J.UnsupportedWaveFormat{}}}: IO.print("unsupported")
    case Fail{_}: IO.print("none")
    case Done{+wave}: IO.print(told(wave, audio))

def main() -> IO(Unit):
  do IO<Unit>:
'''


def quiet():
    """Packets whose values are 1s: samples about a short's steps."""
    values = [3 if k % 3 == 0 else 0 for k in range(32)]
    return [[fp.packet(0, values), fp.packet(1, fp.one(2, 3), before=0, after=1), fp.packet(1, values), fp.packet(0, fp.one(31, 3)), fp.packet(0, values)]]


def built():
    """name -> stream: one channel at 8000 Hz. The loud packets hold 672 samples and the quiet ones 272; a last page's position
    inside the last block cuts it there."""
    def made(loud, groups, granules):
        return lp.checksummed(fp.headers(loud) + fp.audio(groups, granules))
    return {
        'loud': made(5, fp.blocks(), [UNKNOWN, 667]),
        'quiet': made(5, quiet(), [260]),
        # the position is before the last block: the samples up to it are the wave
        'stated-less': made(5, fp.blocks(), [UNKNOWN, 500]),
        # ... and past what the stream has: the wave's last shorts are zeros
        'stated-more': made(5, fp.blocks(), [UNKNOWN, 800]),
        # samples the port refuses
        'louder': made(20, fp.blocks(), [UNKNOWN, 667]),
        # pages without checksums: no last page is found, and the length is not known
        'unsummed': fp.headers(5) + fp.audio(fp.blocks(), [UNKNOWN, 667]),
    }


def cases(source):
    """name -> (stream, token)."""
    where = pages(source)
    last, _ = where[-1]
    out = {'whole': (source, '.ogg'), 'upper': (source, '.OGG')}
    # cut at the last page (the page before is the last then: fewer samples), inside it, inside the setup and inside the first header
    for name, cut in (('cut-page', last), ('cut-inside', len(source) - 1), ('cut-setup', where[1][0] + 2000), ('cut-header', 20)):
        out[name] = (source[:cut], '.ogg')
    rng = Rng(0x0A7E5)
    inside = bodies(source)
    for index in range(2):
        data = bytearray(source)
        for _ in range(1 + index):
            start, end = inside[rng.next(len(inside))]
            data[start + rng.next(end - start)] ^= 1 << rng.next(8)
        out[f'bits-{index}'] = (lp.checksummed(bytes(data)), '.ogg')
    # the last page with another position, its checksum made right
    for name, granule in (('unknown', UNKNOWN), ('zero', 0), ('fewer', 30000), ('more', 50000), ('past-32-bits', 0x100000000), ('past-an-int', 0x60000000)):
        out[name] = (lp.summed(source[:last + 6] + struct.pack('<Q', granule) + source[last + 14:], last), '.ogg')
    for name, data in built().items():
        out[name] = (data, '.ogg')
    return out


def render(libm):
    def made(selected, gpu):
        return PROGRAM + ''.join(
            f'    Unit <- IO.bind(Result<&1, &1, J.Wave.IOError, J.Wave>, Unit, J.Wave.load_for(M.{libm}{{}}, {json.dumps(path)}), result => loaded(result, J.AudioDevice.init(J.AudioDevice.none())))\n'
            for _, path in selected) + '    IO.print("done")\n'
    return made


def parse(text, selected):
    lines = text.splitlines()
    if len(lines) != len(selected) + 1 or lines[-1] != 'done':
        raise ValueError('vorbis-wave: candidate output did not finish')
    return lines[:-1]


def main():
    probe = probekit.Probe('vorbis-wave', probekit.arguments(__doc__))
    libm = gradient_reference()
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files = cases((probe.args.raylib_source / SOURCE).read_bytes())
    items = []
    for name, (data, token) in files.items():
        (folder / f'{name}{token}').write_bytes(data)
        items.append((name, f'{WORK}/{name}{token}'))
    source = NATIVE.replace('FILES', ', '.join(json.dumps(str(ROOT / path)) for _, path in items))
    expected = probe.native(source, 'reference', extra_flags=FLAGS).splitlines()
    if len(expected) != len(items):
        raise ProbeFailure(f'vorbis-wave: the reference printed {len(expected)} rows for {len(items)} files')
    rows = dict(zip((name for name, _ in items), expected))
    frames = {name: int(row[1:].split('/')[0]) if row.startswith('w') else None for name, row in rows.items()}
    # what the corpus is for: target.ogg is 44100 frames of two channels at 22050 Hz under both tokens; a stream cut at its last
    # page, or whose last page states fewer samples, is a shorter wave; one whose length is not known or 0 is a wave of no frames;
    # one that states more samples than it has ends in zeros (raylib 6.2's RL_CALLOC); one whose samples are refused, or whose
    # frameCount*channels passes 32 bits, is none; one past an int is zeros past the port's limit
    wanted = {'whole': 44100, 'upper': 44100, 'cut-page': 30208, 'cut-inside': 30208, 'cut-setup': None, 'cut-header': None, 'unknown': 0, 'zero': 0, 'fewer': 30000, 'more': 50000, 'past-32-bits': None,
              'past-an-int': None, 'loud': 667, 'quiet': 260, 'stated-less': 500, 'stated-more': 800, 'louder': None, 'unsummed': 0}
    wrong = {name: frames[name] for name, value in wanted.items() if frames[name] != value}
    if wrong or not rows['whole'].startswith('w44100/22050/16/2/') or rows['upper'] != rows['whole'] or not rows['loud'].startswith('w667/8000/16/1/') or rows['bits-0'] == rows['whole'] \
            or rows['past-an-int'] != 'unsupported' or rows['past-32-bits'] != 'none':
        raise ProbeFailure(f'vorbis-wave: the reference rows are not the ones this probe was written for: {wrong} of {rows}')
    lanes = probe.candidates(render(libm), items, batch=6, parse=parse, timeout=1700)
    probe.compare(expected, lanes, describe=lambda index: items[index][0])
    waves = [row for row in expected if row.startswith('w')]
    probe.finish(files=len(items), waves=len(waves), none=expected.count('none'), unsupported=expected.count('unsupported'), frames=sum(int(row[1:].split('/')[0]) for row in waves), libm=libm)


if __name__ == '__main__':
    main()
