#!/usr/bin/env python3
"""Compare Jonlib's XM musics (Music.load_for, Music.update, Music.stop, ...) with the pinned raylib.

Reference. The sound gate's program: raudio.c itself with miniaudio's null
backend and its device stopped, so LoadMusicStream, UpdateMusicStream,
StopMusicStream, SeekMusicStream and the stream's calls are raylib's, on
jar_xm as raylib builds it. After every step it prints the sound gate's
state: each music's IsMusicValid, frame count, looping flag, the samples
its player has generated, GetMusicTimeLength and GetMusicTimePlayed, and
every tracked buffer with a hash of the samples in its two halves, its
cursor, its halves' flags and the frames it was given; after a callback, a
hash of what the device mixed. Each case runs in a process of its own,
because jar_xm keeps its random waveform's state in a static.

Candidate. The sound gate's program on the same scripts, its musics loaded
by Music.load_for under the libm profile of the machine; those of slot 3
by Music.load (the AppleLibm profile).

The modules: raylib's mini1111.xm; two of the xm-player gate's seeded
modules, of linear and of Amiga frequencies; a song of four rows, played
to its end without looping; and one of Amiga frequencies without a
vibrato, which needs no libm function and so plays under Music.load. The
cases play them through the halves of their streams, stop and play again,
seek (raylib does not), pause, resume, change volume, pitch and pan, load
on a device that is not ready (a rate of 0) and play two at once.

Contracts (the reference does not run them as they are): the modules the
xm-module and xm-player gates find undefined by jar_xm.h itself, which
Jonlib does not load. For those the expected state is raylib's after a
file jar_xm does not take, with the error Jonlib gives. On a host whose
libm is AppleLibm, Music.load of raylib's module is played and compared:
that profile now answers the module's powers of two and waveform sines.
On a glibc host the reference would be a different libm, so that case is
not run.
CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import re

from conformance import gradient_reference
import probekit
from probekit import ProbeFailure
import sound_probe as sp
import xm_module_probe as xp
import xm_player_probe as pp

SOURCE = pp.SOURCE
FLAGS = sp.FLAGS + ['-DALONE']
bits = sp.bits
# The candidate's loader: slot 3 is Music.load, the others Music.load_for under the machine's profile.
PLAIN = 'J.Music.load(audio, path)'
LOADER = '''def music.load(plain: Bool, +audio: J.AudioDevice, +path: String) -> IO(J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>):
  match plain:
    case True{}: J.Music.load(audio, path)
    case False{}: J.Music.load_for(M.LIBM{}, audio, path)

def step('''
# a file jar_xm does not take: what raylib is left with is what Jonlib is left with after a module it does not load
NOT_A_MODULE = b'Extended Module: not one, whatever its name says.\n'


def modules(source):
    """name -> bytes."""
    built = pp.built()
    rest = (None, None, None, None, None)
    plain = [xp.instrument([xp.sample(xp.deltas(pp.Rng(0xA11CE), 300), loop=1, start=40, span=200, relative=12)])]
    return {
        'mini': source, 'linear': built['tame-0'], 'amiga': built['tame-1'], 'short': built['finetune-high'],
        # Amiga frequencies and no vibrato: no sine and no power of two
        'bare': xp.module([xp.pattern(4, xp.slots([(40, 1, None, None, None), rest, (47, 1, 0x30, None, None), rest]))], plain, channels=1, flags=0, tempo=3),
        'text': NOT_A_MODULE,
        # what jar_xm leaves undefined: as it plays (the xm-player gate's), and as it loads (256 channels: a loop that does not end)
        'delay-bare': built['delay-bare'], 'finetune-low': built['finetune-low'], 'sustain-past': built['sustain-past'], 'break-past': built['break-past'],
        'channels': xp.module([xp.pattern(4)], plain, channels=256),
    }


# Jonlib's error for the modules it does not load
REFUSED = {'delay-bare': 'data', 'finetune-low': 'data', 'sustain-past': 'data', 'break-past': 'data', 'channels': 'data'}


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
    add('play', ('init',), ('default', 480), ('music', 0, 'mini'), ('play', 0), *(turn * 6), ('musicstop', 0), ('musicupdate', 0), ('play', 0), ('musicupdate', 0),
        ('mix', 300), ('musicupdate', 0), ('close',))
    add('seek-pause', ('init',), ('default', 600), ('music', 0, 'mini'), ('musicupdate', 0), ('play', 0), ('musicupdate', 0), ('mix', 480), ('seek', 0, bits(1.0)),
        ('musicupdate', 0), ('pause', 0), ('musicupdate', 0), ('mix', 100), ('resume', 0), ('mix', 500), ('musicupdate', 0), ('volume', 0, bits(0.5)),
        ('pitch', 0, bits(1.5)), ('pan', 0, bits(-0.5)), ('mix', 480), ('musicupdate', 0), ('mix', 480), ('musicunload', 0), ('mix', 5), ('close',))
    # a song that does not loop: what is left of it, then the stop once both halves are read through, and the song again
    once = [('musicupdate', 0), ('mix', 480), ('mix', 480), ('mix', 480), ('mix', 480)]
    add('once', ('init',), ('default', 2000), ('music', 0, 'short'), ('looping', 0, 0), ('play', 0), *(once * 9), ('musicupdate', 0), ('play', 0), ('musicupdate', 0),
        ('mix', 200), ('close',))
    long = [('musicupdate', 0), ('mix', 480), ('mix', 480), ('mix', 40)]
    add('linear', ('init',), ('default', 1000), ('music', 0, 'linear'), ('play', 0), *(long * 8), ('musicstop', 0), ('play', 0), ('musicupdate', 0), ('mix', 480), ('close',))
    add('amiga', ('init',), ('default', 1000), ('music', 0, 'amiga'), ('play', 0), *(long * 8), ('looping', 0, 0), ('musicupdate', 0), ('mix', 480), ('close',))
    # a device that is not ready has a rate of 0: a music without frames and without a buffer
    add('unready', ('music', 0, 'mini'), ('play', 0), ('musicupdate', 0), ('init',), ('default', 480), ('musicupdate', 0), ('music', 1, 'short'), ('play', 1),
        ('musicupdate', 1), ('mix', 480), ('musicupdate', 0), ('musicstop', 1), ('musicstop', 0), ('close',))
    add('two', ('init',), ('default', 480), ('music', 0, 'mini'), ('music', 1, 'short'), ('play', 0), ('play', 1),
        *([('musicupdate', 0), ('musicupdate', 1), ('mix', 480), ('mix', 480)] * 3), ('musicstop', 0), ('musicupdate', 1), ('mix', 480), ('close',))
    # Music.load: the AppleLibm profile
    add('default-profile', ('init',), ('default', 480), ('music', 3, 'bare'), ('play', 3), *([('musicupdate', 3), ('mix', 480), ('mix', 480)] * 4), ('musicstop', 3), ('close',))
    add('not-a-module', ('init',), ('music', 0, 'text'), ('play', 0), ('musicupdate', 0), ('close',))
    for name in REFUSED:
        add(f'refused-{name}', ('init',), ('music', 0, name), ('play', 0), ('musicupdate', 0), ('close',))
    # Music.load is the AppleLibm profile. Compare it with raylib only where that is the host libm.
    if gradient_reference() == 'AppleLibm':
        add('apple-mini', ('init',), ('music', 3, 'mini'), ('play', 3), ('musicupdate', 3), ('close',))
    return out


def native_steps(case):
    """The steps raylib runs: a file jar_xm does not take where Jonlib does not load one."""
    return [('music', step[1], 'text') if index in case['tags'] else step for index, step in enumerate(case['steps'])]


def tagged(case, row):
    """The candidate's row for a reference row: each step's state after its error."""
    states = row.split(';')
    if len(states) != len(case['steps']):
        raise ProbeFailure(f'xm-music: the reference printed {len(states)} states for the {len(case["steps"])} steps of {case["id"]}')
    return ';'.join(f'E:{case["tags"].get(index, "-")} {state}' for index, state in enumerate(states))


def program(libm):
    if sp.PROGRAM.count(PLAIN) != 1 or sp.PROGRAM.count('\ndef step(') != 1:
        raise ProbeFailure('xm-music: the sound gate\'s program does not load its musics where this probe changes it')
    return sp.hosted_program().replace(PLAIN, 'music.load(U32.is_eq(slot, 3), audio, path)').replace('\ndef step(', '\n' + LOADER).replace('LIBM', libm)


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('xm-music', args)
    libm = gradient_reference()
    work = (probe.work / 'files').resolve()
    work.mkdir(parents=True, exist_ok=True)
    files = modules((args.raylib_source / SOURCE).read_bytes())
    for name, data in files.items():
        kind = xp.model(data)[0]
        if (kind == 'refused') != (name == 'channels') or (kind == 'failed') != (name == 'text'):
            raise ProbeFailure(f'xm-music: {name} is {xp.model(data)} for the loader')
        (work / f'{name}.xm').write_bytes(data)
    paths = {name: work / f'{name}.xm' for name in files}
    order = list(paths)
    items = cases()

    path = work / 'reference.bin'
    path.write_bytes(sp.script([(False, native_steps(case)) for case in items], {}, order))
    source = sp.NATIVE.replace('PATH', str(path)).replace('FILES', ', '.join(json.dumps(str(paths[n])) for n in order))
    output = [line[2:] for line in probe.native(source, 'reference', extra_flags=FLAGS).splitlines() if line[:2] == 'C ']
    if len(output) != len(items):
        raise ProbeFailure(f'xm-music: the reference printed {len(output)} rows for {len(items)} cases')
    rows = {case['id']: row for case, row in zip(items, output)}
    # what the cases are for: raylib's module with its length, a music that plays to its end and stops, musics without a file
    lengths = {name: [int(m) for m in re.findall(r' U1,(\d+),', rows[name])] for name in rows}
    if (set(lengths['play']) != {2974098} or not lengths['once'] or ' U0,0,1,0,2143289344,0' not in rows['unready'] or not lengths['default-profile']
            or any(lengths[name] for name in rows if name.startswith('refused-') or name == 'not-a-module') or len(set(lengths['two'])) != 2
            or ('apple-mini' in lengths and set(lengths['apple-mini']) != {2974098})):
        raise ProbeFailure(f'xm-music: the reference rows are not the ones this probe was written for: {lengths}')
    # the music that does not loop: playing after its first step, stopped and back at its start before it is played again
    once = rows['once'].split(';')
    playing = [found.group(1) if (found := re.search(r' B1,1,\d+,\d+,\d+,\d+,(\d),', state)) else '-' for state in once]
    if playing[4] != '1' or playing[-5] != '0' or playing[-4] != '1' or f' U1,{lengths["once"][0]},0,0,' not in once[-5]:
        raise ProbeFailure(f'xm-music: the music that does not loop did not stop at its end: {playing}')
    expected = [tagged(case, rows[case['id']]) for case in items]

    text = program(libm)

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
                 modules=len(files), libm=libm, files_sha256=hashlib.sha256(b''.join(name.encode() + data for name, data in sorted(files.items()))).hexdigest())


if __name__ == '__main__':
    main()
