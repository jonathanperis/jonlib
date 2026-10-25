#!/usr/bin/env python3
"""Compare Jonlib's Ogg Vorbis musics (Music.load, Music.update, Music.stop, ...) with the pinned raylib.

Reference. The sound gate's program: raudio.c itself with miniaudio's null
backend and its device stopped, so LoadMusicStream, UpdateMusicStream,
StopMusicStream and the stream's calls are raylib's, on stb_vorbis as
raylib builds it. After every step it prints the sound gate's state: each
music's IsMusicValid, frame count, looping flag, stb_vorbis_get_sample_offset,
GetMusicTimeLength and GetMusicTimePlayed, and every tracked buffer with a
hash of the samples in its two halves, its resampler, cursor, flags and the
frames it was given; after a callback, a hash of what the device mixed.

Candidate. The sound gate's program on the same scripts (Music.load: the
AppleLibm profile, whose transform tables the decoder has for every block
size).

The music is raylib's examples/audio/resources/target.ogg (22050 Hz, two
channels, 44100 frames, resampled to the device's 48000): played through
its stream's halves until its end and round again (stb_vorbis_seek_start
on a short read), stopped and played again, played to its end without
looping, where it stops, paused and resumed with its volume, pitch and pan
changed, loaded before the device is ready, two at once, and a file that is
no Ogg stream. SeekMusicStream is not ported for Ogg (stb_vorbis_seek_frame):
its silence is a law, not a case. CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import re

import probekit
from probekit import ProbeFailure
import sound_probe as sp

FLAGS = sp.FLAGS
bits = sp.bits
SOURCE = 'examples/audio/resources/target.ogg'
NOT_OGG = b'OggS is not enough: this is no Ogg Vorbis stream, whatever its name says.\n'
# Jonlib's error for a file stb_vorbis does not open
REFUSED = {'text': 'data'}


def cases():
    out = []

    def add(name, *steps):
        tags = {index: REFUSED[step[2]] for index, step in enumerate(steps) if step[0] == 'music' and step[2] in REFUSED}
        out.append(dict(id=name, steps=list(steps), tags=tags))

    turn = [('musicupdate', 0), ('mix', 4800)]
    # through the end and round again: a short read goes back to the start
    add('play', ('init',), ('default', 8000), ('music', 0, 'target'), ('play', 0), *(turn * 24), ('musicstop', 0), ('musicupdate', 0), ('play', 0),
        ('musicupdate', 0), ('mix', 2000), ('close',))
    add('once', ('init',), ('default', 8000), ('music', 0, 'target'), ('looping', 0, 0), ('play', 0), *(turn * 26), ('musicupdate', 0), ('play', 0),
        ('musicupdate', 0), ('mix', 1000), ('close',))
    add('pause', ('init',), ('default', 3000), ('music', 0, 'target'), ('musicupdate', 0), ('play', 0), ('musicupdate', 0), ('mix', 2400), ('pause', 0),
        ('musicupdate', 0), ('mix', 480), ('resume', 0), ('volume', 0, bits(0.5)), ('pitch', 0, bits(1.5)), ('pan', 0, bits(-0.5)), ('mix', 2400),
        ('musicupdate', 0), ('mix', 2400), ('musicunload', 0), ('mix', 5), ('close',))
    add('unready', ('music', 0, 'target'), ('play', 0), ('musicupdate', 0), ('init',), ('default', 3000), ('musicupdate', 0), ('music', 1, 'target'),
        ('play', 1), ('musicupdate', 1), ('mix', 2400), ('musicstop', 1), ('close',))
    add('two', ('init',), ('default', 3000), ('music', 0, 'target'), ('music', 1, 'target'), ('play', 0), ('musicupdate', 0), ('mix', 1200), ('play', 1),
        *([('musicupdate', 0), ('musicupdate', 1), ('mix', 2400)] * 4), ('musicstop', 0), ('musicupdate', 1), ('mix', 2400), ('close',))
    add('not-ogg', ('init',), ('music', 0, 'text'), ('play', 0), ('musicupdate', 0), ('close',))
    return out


def tagged(case, row):
    states = row.split(';')
    if len(states) != len(case['steps']):
        raise ProbeFailure(f'ogg-music: the reference printed {len(states)} states for the {len(case["steps"])} steps of {case["id"]}')
    return ';'.join(f'E:{case["tags"].get(index, "-")} {state}' for index, state in enumerate(states))


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('ogg-music', args)
    work = (probe.work / 'files').resolve()
    work.mkdir(parents=True, exist_ok=True)
    (work / 'text.ogg').write_bytes(NOT_OGG)
    paths = {'target': args.raylib_source.resolve() / SOURCE, 'text': work / 'text.ogg'}
    order = list(paths)
    items = cases()
    path = work / 'reference.bin'
    path.write_bytes(sp.script([(False, case['steps']) for case in items], {}, order))
    source = sp.NATIVE.replace('PATH', str(path)).replace('FILES', ', '.join(json.dumps(str(paths[n])) for n in order))
    output = [line[2:] for line in probe.native(source, 'reference', extra_flags=FLAGS).splitlines() if line[:2] == 'C ']
    if len(output) != len(items):
        raise ProbeFailure(f'ogg-music: the reference printed {len(output)} rows for {len(items)} cases')
    rows = {case['id']: row for case, row in zip(items, output)}
    # what the cases are for: target.ogg's 44100 frames; the music that does not loop stops; the other file is no music
    lengths = {name: [int(m) for m in re.findall(r' U1,(\d+),', rows[name])] for name in rows}
    once = rows['once'].split(';')
    playing = [found.group(1) if (found := re.search(r' B1,1,\d+,\d+,\d+,\d+,(\d),', state)) else '-' for state in once]
    if (set(lengths['play']) != {44100} or lengths['not-ogg'] or playing[4] != '1' or playing[-5] != '0' or playing[-4] != '1'
            or not lengths['unready'] or ' S0,0,22050,16,2,' not in rows['unready']):
        raise ProbeFailure(f'ogg-music: the reference rows are not the ones this probe was written for: {lengths} {playing}')
    expected = [tagged(case, rows[case['id']]) for case in items]

    def render(selected, gpu):
        lines = [sp.hosted_program(), 'def main() -> IO(Unit):\n  do IO<Unit>:']
        for index, (_, case) in enumerate(selected):
            ops = ', '.join(sp.bend_step(step, {}, paths) for step in case['steps'])
            lines.append(f'    s{index} : String <- run([{ops}], start())\n    IO.print(s{index})')
        return '\n'.join(lines) + '\n'

    lanes = probe.candidates(render, list(enumerate(items)), batch=20, timeout=2400,
                             parse=lambda text, selected: [line.strip().lstrip(';') for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda index: items[index]['id'])
    probe.finish(cases=len(items), steps=sum(len(case['steps']) for case in items), files_sha256=hashlib.sha256((paths['target']).read_bytes() + NOT_OGG).hexdigest())


if __name__ == '__main__':
    main()
