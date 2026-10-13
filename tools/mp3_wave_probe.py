#!/usr/bin/env python3
"""Compare a Wave loaded from an MP3 file with raylib's LoadWave.

The reference is raudio.c itself, compiled into the reference program with
miniaudio's null backend: LoadWave(".mp3"), which is
drmp3_open_memory_and_read_pcm_frames_f32 (every frame of the stream as
32-bit floats, 16-bit samples over 32768 in raylib's build of dr_mp3). Per
file: whether there is a wave, its frame count, sample rate, sample size and
channels, and the FNV-1a of its samples' bits. LoadSound of the same file
is compared too (the frame count of the sound's buffer in the device's
format), with the device open.

The files are the mp3 gate's: edits of the first frames of raylib's
country.mp3 (tags, holes, cuts, every header rewritten, seeded
corruptions), without the whole file, which the JavaScript lane decodes too
slowly for a gate (the mp3-layer3 gate has its frames). A file with a Layer
I or II frame would be a contract and not a comparison: dr_mp3 decodes
those and the port does not yet, so the reference is asked through dr_mp3
whether its stream meets one, and such a file must be
UnsupportedWaveFormat (none of the corpus's files is one today: the edits
that name another layer leave streams dr_mp3 does not open). The token
".MP3" is loaded too. CPU/JS.
"""
import json

import mp3_probe
import probekit
from probekit import ROOT, ProbeFailure

SOURCE = 'examples/audio/resources/country.mp3'
WORK = '.build/mp3-wave-probe/cases'
FLAGS = ['-ffp-contract=off', '-DMA_ENABLE_ONLY_SPECIFIC_BACKENDS', '-DMA_ENABLE_NULL', '-D_DEFAULT_SOURCE', '-Wno-everything']
# A copy of a file under the upper-case token.
RENAMED = {'upper': ('first12', '.MP3')}

NATIVE = r'''#include "raudio.c"
#include <stdio.h>
#include <string.h>

static const char *files[] = { FILES };

// Whether the stream has a Layer I or II frame: its decoder's header shows the frame decoded last.
static int other_layer(const char *path)
{
    static drmp3 mp3;
    static float chunk[4096];
    int found = 0;
    if (!drmp3_init_file(&mp3, path, NULL)) return 0;
    for (;;)
    {
        found = (mp3.decoder.header[0] == 0xFF) && (((mp3.decoder.header[1] >> 1) & 3) != 1);
        if (found || (drmp3_read_pcm_frames_f32(&mp3, 4096/mp3.channels, chunk) == 0)) break;
    }
    if (!found) found = (mp3.decoder.header[0] == 0xFF) && (((mp3.decoder.header[1] >> 1) & 3) != 1);
    drmp3_uninit(&mp3);
    return found;
}

int main(void)
{
    SetTraceLogLevel(LOG_NONE);
    InitAudioDevice();
    if (!IsAudioDeviceReady()) return 2;
    for (unsigned a = 0; a < sizeof(files)/sizeof(files[0]); a++)
    {
        const char *dot = strrchr(files[a], '.');
        if ((strcmp(dot, ".mp3") == 0 || strcmp(dot, ".MP3") == 0) && other_layer(files[a])) { printf("layer12\n"); continue; }
        Wave wave = LoadWave(files[a]);
        if (wave.data == NULL) { printf("none\n"); continue; }
        unsigned h = 2166136261u;
        if (wave.sampleSize != 32) return 3;
        for (unsigned k = 0; k < wave.frameCount*wave.channels; k++) { unsigned w; memcpy(&w, (float *)wave.data + k, 4); h = (h ^ w)*16777619u; }
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
    case Fail{J.WaveDataError{J.UnsupportedWaveFormat{}}}: IO.print("layer12")
    case Fail{_}: IO.print("none")
    case Done{+wave}: IO.print(told(wave, audio))

def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    return PROGRAM + ''.join(
        f'    Unit <- IO.bind(Result<&1, &1, J.Wave.IOError, J.Wave>, Unit, J.Wave.load({json.dumps(path)}), result => loaded(result, J.AudioDevice.init(J.AudioDevice.none())))\n'
        for _, path in selected) + '    IO.print("done")\n'


def parse(text, selected):
    lines = text.splitlines()
    if len(lines) != len(selected) + 1 or lines[-1] != 'done':
        raise ValueError('mp3-wave: candidate output did not finish')
    return lines[:-1]


def main():
    probe = probekit.Probe('mp3-wave', probekit.arguments(__doc__))
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files = mp3_probe.cases((probe.args.raylib_source / SOURCE).read_bytes())
    files.pop('whole')
    items = []
    for name, data in files.items():
        (folder / f'{name}.mp3').write_bytes(data)
        items.append((name, f'{WORK}/{name}.mp3'))
    for name, (source, suffix) in RENAMED.items():
        (folder / f'{name}{suffix}').write_bytes(files[source])
        items.append((name, f'{WORK}/{name}{suffix}'))
    source = NATIVE.replace('FILES', ', '.join(json.dumps(str(ROOT / path)) for _, path in items))
    expected = probe.native(source, 'reference', extra_flags=FLAGS).splitlines()
    if len(expected) != len(items):
        raise ProbeFailure(f'mp3-wave: the reference printed {len(expected)} rows for {len(items)} files')
    rows = dict(zip((name for name, _ in items), expected))
    waves = [row for row in expected if row.startswith('w')]
    if not rows['first12'].startswith('w') or rows['upper'] != rows['first12']:
        raise ProbeFailure(f'mp3-wave: the reference did not load the first frames as expected: {rows["first12"]}, {rows["upper"]}')
    if len(waves) < 40 or expected.count('none') < 8 or len({row.split('/')[3] for row in waves}) < 2 or len({row.split('/')[0] for row in waves}) < 12:
        raise ProbeFailure(f'mp3-wave: the corpus lost coverage: {len(waves)} waves ({len({row.split("/")[0] for row in waves})} frame counts), {expected.count("none")} without one')
    lanes = probe.candidates(render, items, batch=30, parse=parse, timeout=1500)
    probe.compare(expected, lanes, describe=lambda index: items[index][0])
    probe.finish(files=len(items), waves=len(waves), none=expected.count('none'), layer12=expected.count('layer12'),
                 frames=sum(int(row[1:].split('/')[0]) for row in waves))


if __name__ == '__main__':
    main()
