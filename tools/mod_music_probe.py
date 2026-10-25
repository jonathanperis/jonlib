#!/usr/bin/env python3
"""Compare Jonlib's MOD musics (Music.load, Music.update, Music.stop, ...) with the pinned raylib.

Reference. The sound gate's program: raudio.c itself with miniaudio's null
backend and its device stopped, so LoadMusicStream, UpdateMusicStream,
StopMusicStream, SeekMusicStream and the stream's calls are raylib's, on
jar_mod as raylib builds it. After every step it prints the sound gate's
state: each music's IsMusicValid, frame count, looping flag, GetMusicTimeLength
and GetMusicTimePlayed, and every tracked buffer with a hash of the samples
in its two halves, its cursor, its halves' flags and the frames it was
given; after a callback, a hash of what the device mixed.

Candidate. The sound gate's program on the same scripts, its musics loaded
by Music.load (jar_mod needs no libm function).

The modules: tools/mod_probe.py's plain module and two of its seeded songs
(four and six channels), and a song of one pattern played to its end
without looping. The cases play them through the halves of their streams,
stop and play again, seek (raylib does not for a module), pause, resume,
change volume, pitch and pan, load on a device that is not ready (a rate of
0) and play two at once; a file of 1084 zero bytes is no module for jar_mod.

Contracts (the reference does not run them as they are): a file shorter than
the 1084 bytes jar_mod copies and a song whose length raylib counts for ever.
For those the expected state is raylib's after a file jar_mod does not take,
with the error Jonlib gives. CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import re

import probekit
from probekit import ProbeFailure
import mod_probe as mp
import sound_probe as sp

FLAGS = sp.FLAGS + ['-DALONE']
bits = sp.bits
# a file jar_mod does not take (jar_mod_load returns 0): what raylib is left with is what Jonlib is left with after a module it does not load
NOT_A_MODULE = bytes(1084)


def modules():
    """name -> bytes."""
    built = {name: data for name, data, _ in mp.cases()}
    once = mp.empty_pattern(4)
    once[0][0] = mp.note(1, 428, 0xF01)
    once[0][1] = mp.note(2, 214, 0xFFF)
    once[16][2] = mp.note(1, 302, 0x404 | 0x30)
    one = dict(data=[(i * 7) % 256 - 128 for i in range(64)], finetune=0, volume=64, reppnt=0, replen=2)
    looped = dict(data=[(i * 13) % 256 - 128 for i in range(128)], finetune=3, volume=50, reppnt=32, replen=64)
    return {
        'plain': built['plain'], 'four': built['song-1'], 'six': built['song-3'],
        'short': mp.module([one, looped], [once], [0], pad=256),
        'text': NOT_A_MODULE,
        # what jar_mod leaves undefined, and a count that never ends
        'tiny': built['short'], 'jump-back': built['jump-back'],
    }


# Jonlib's error for the modules it does not load
REFUSED = {'tiny': 'data', 'jump-back': 'unsupported'}


def cases():
    """Cases of the sound gate's steps. `tags` are the candidate's errors by step (a file that is not loaded)."""
    out = []

    def add(name, *steps):
        tags = {}
        for index, step in enumerate(steps):
            if step[0] == 'music' and (step[2] in REFUSED or step[2] == 'text'):
                tags[index] = REFUSED.get(step[2], 'header')
        out.append(dict(id=name, steps=list(steps), tags=tags))

    turn = [('musicupdate', 0), ('mix', 480), ('mix', 480)]
    # as raylib's example plays it: the halves filled as the device reads through them; a stop takes the song back to its start
    add('play', ('init',), ('default', 480), ('music', 0, 'plain'), ('play', 0), *(turn * 6), ('musicstop', 0), ('musicupdate', 0), ('play', 0), ('musicupdate', 0),
        ('mix', 300), ('musicupdate', 0), ('close',))
    add('seek-pause', ('init',), ('default', 600), ('music', 0, 'plain'), ('musicupdate', 0), ('play', 0), ('musicupdate', 0), ('mix', 480), ('seek', 0, bits(1.0)),
        ('musicupdate', 0), ('pause', 0), ('musicupdate', 0), ('mix', 100), ('resume', 0), ('mix', 500), ('musicupdate', 0), ('volume', 0, bits(0.5)),
        ('pitch', 0, bits(1.5)), ('pan', 0, bits(-0.5)), ('mix', 480), ('musicupdate', 0), ('mix', 480), ('musicunload', 0), ('mix', 5), ('close',))
    # a song that does not loop: what is left of it, then the stop once both halves are read through, and the song again
    once = [('musicupdate', 0), ('mix', 480), ('mix', 480), ('mix', 480), ('mix', 480)]
    add('once', ('init',), ('default', 2000), ('music', 0, 'short'), ('looping', 0, 0), ('play', 0), *(once * 18), ('musicupdate', 0), ('play', 0), ('musicupdate', 0),
        ('mix', 200), ('close',))
    long = [('musicupdate', 0), ('mix', 480), ('mix', 480), ('mix', 40)]
    add('four', ('init',), ('default', 1000), ('music', 0, 'four'), ('play', 0), *(long * 8), ('musicstop', 0), ('play', 0), ('musicupdate', 0), ('mix', 480), ('close',))
    add('six', ('init',), ('default', 1000), ('music', 0, 'six'), ('play', 0), *(long * 8), ('looping', 0, 0), ('musicupdate', 0), ('mix', 480), ('close',))
    # a device that is not ready has a rate of 0: a music without frames and without a buffer
    add('unready', ('music', 0, 'plain'), ('play', 0), ('musicupdate', 0), ('init',), ('default', 480), ('musicupdate', 0), ('music', 1, 'short'), ('play', 1),
        ('musicupdate', 1), ('mix', 480), ('musicupdate', 0), ('musicstop', 1), ('musicstop', 0), ('close',))
    add('two', ('init',), ('default', 480), ('music', 0, 'plain'), ('music', 1, 'four'), ('play', 0), ('play', 1),
        *([('musicupdate', 0), ('musicupdate', 1), ('mix', 480), ('mix', 480)] * 3), ('musicstop', 0), ('musicupdate', 1), ('mix', 480), ('close',))
    add('not-a-module', ('init',), ('music', 0, 'text'), ('play', 0), ('musicupdate', 0), ('close',))
    for name in REFUSED:
        add(f'refused-{name}', ('init',), ('music', 0, name), ('play', 0), ('musicupdate', 0), ('close',))
    return out


def native_steps(case):
    """The steps raylib runs: a file jar_mod does not take where Jonlib does not load one."""
    return [('music', step[1], 'text') if index in case['tags'] else step for index, step in enumerate(case['steps'])]


def tagged(case, row):
    """The candidate's row for a reference row: each step's state after its error."""
    states = row.split(';')
    if len(states) != len(case['steps']):
        raise ProbeFailure(f'mod-music: the reference printed {len(states)} states for the {len(case["steps"])} steps of {case["id"]}')
    return ';'.join(f'E:{case["tags"].get(index, "-")} {state}' for index, state in enumerate(states))


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('mod-music', args)
    work = (probe.work / 'files').resolve()
    work.mkdir(parents=True, exist_ok=True)
    files = modules()
    for name, data in files.items():
        (work / f'{name}.mod').write_bytes(data)
    paths = {name: work / f'{name}.mod' for name in files}
    order = list(paths)
    items = cases()

    path = work / 'reference.bin'
    path.write_bytes(sp.script([(False, native_steps(case)) for case in items], {}, order))
    source = sp.NATIVE.replace('PATH', str(path)).replace('FILES', ', '.join(json.dumps(str(paths[n])) for n in order))
    output = [line[2:] for line in probe.native(source, 'reference', extra_flags=FLAGS).splitlines() if line[:2] == 'C ']
    if len(output) != len(items):
        raise ProbeFailure(f'mod-music: the reference printed {len(output)} rows for {len(items)} cases')
    rows = {case['id']: row for case, row in zip(items, output)}
    # what the cases are for: raylib's module with its length, a music that plays to its end and stops, musics without a file
    lengths = {name: [int(m) for m in re.findall(r' U1,(\d+),', rows[name])] for name in rows}
    if (not lengths['play'] or not lengths['once'] or not lengths['four'] or not lengths['six']
            or any(lengths[name] for name in rows if name.startswith('refused-') or name == 'not-a-module') or len(set(lengths['two'])) != 2):
        raise ProbeFailure(f'mod-music: the reference rows are not the ones this probe was written for: {lengths}')
    # the music that does not loop: playing after its first step, stopped and back at its start before it is played again
    once = rows['once'].split(';')
    playing = [found.group(1) if (found := re.search(r' B1,1,\d+,\d+,\d+,\d+,(\d),', state)) else '-' for state in once]
    if playing[4] != '1' or playing[-5] != '0' or playing[-4] != '1' or f' U1,{lengths["once"][0]},0,0,' not in once[-5]:
        raise ProbeFailure(f'mod-music: the music that does not loop did not stop at its end: {playing}')
    expected = [tagged(case, rows[case['id']]) for case in items]

    text = sp.hosted_program()

    def render(selected, gpu):
        lines = [text, 'def main() -> IO(Unit):\n  do IO<Unit>:']
        for index, (_, case) in enumerate(selected):
            ops = ', '.join(sp.bend_step(step, {}, paths) for step in case['steps'])
            lines.append(f'    s{index} : String <- run([{ops}], start())\n    IO.print(s{index})')
        return '\n'.join(lines) + '\n'

    lanes = probe.candidates(render, list(enumerate(items)), batch=20, timeout=1700,
                             parse=lambda text, selected: [line.strip().lstrip(';') for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda index: items[index]['id'])
    contracts = [case['id'] for case in items if case['id'].startswith('refused-')]
    probe.finish(cases=len(items), compared=len(items) - len(contracts), contracts=len(contracts), refused=contracts, steps=sum(len(case['steps']) for case in items),
                 modules=len(files), files_sha256=hashlib.sha256(b''.join(name.encode() + data for name, data in sorted(files.items()))).hexdigest())


if __name__ == '__main__':
    main()
