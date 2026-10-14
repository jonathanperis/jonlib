#!/usr/bin/env python3
"""Compare reading and seeking an MP3 stream (src/mp3_stream.bend) with dr_mp3.

The reference is dr_mp3 itself (pinned raylib's src/external/dr_mp3.h, built
as raylib builds it: SSE, 16-bit samples), through the functions raylib's
music and waves call: drmp3_init_file, drmp3_get_pcm_frame_count,
drmp3_read_pcm_frames_f32 (and _s16), drmp3_seek_to_pcm_frame and
drmp3_seek_to_start_of_stream. Each file is opened and the same script runs
on both sides, an operation a token:

  o  the stream's channels and sample rate
  c  drmp3_get_pcm_frame_count (without an Xing/Info count it scans the
     stream and seeks back, which decodes the frame at hand again)
  r  a read of 16-bit frames: how many came, and a hash of the samples
  f  a read of float frames: the same, the hash of the floats' bits
  k  a seek to a frame: whether dr_mp3 calls it done
  e  a seek to the frame its count stands at (nothing happens)
  b  drmp3_seek_to_start_of_stream

and after each one what the stream keeps: currentPCMFrame, the frames left
and consumed of the MP3 frame at hand, and that frame's channels. The reads
cross MP3 frames, the delay of a LAME tag and, in the files read to their
end, the padding and the last frame; the seeks go back past the start and
forward.

Every file is opened twice: with drmp3_init_file, as LoadMusicStream opens
it, and from its bytes with drmp3_init_memory, as LoadWave and
LoadMusicStreamFromMemory do. dr_mp3 reads the two with different
functions (through a buffer filled by callbacks; from all the bytes left),
and they end some streams differently: after an Xing/Info frame the
buffered reads go past the stream's length into an ID3v1 tag, whose bytes
then follow the last frame and make it no frame, while a memory stream
stops before its tags and keeps that frame. A seek to the stream's start
puts the buffered reads right again, so the script hides it: the files that
are a dozen frames long are also read straight to their end, one read and
nothing before it, both ways, and the probe requires the reference to end
the two apart for the file with an ID3v1 tag.

The files are the mp3 gate's: raylib's country.mp3 and edits of its first
frames (tags, holes, cuts, every header rewritten, seeded corruptions),
and three Layer I and II streams of the mp3-layer3 gate's generator
(MPEG-1 Layer I and II, MPEG-2 Layer II, 40 frames each), which both sides
decode through the script. CPU/JS.
"""
import hashlib
import json

import mp3_layer3_probe
import mp3_probe
import probekit
from probekit import ROOT, ProbeFailure

WORK = '.build/mp3-stream-probe/cases'
# The Layer I and II streams (mp3_layer3_probe.layer12_files).
LAYER12 = ('l1-stream', 'l2-stream', 'l2-mpeg2')
SOURCE = 'examples/audio/resources/country.mp3'

# The script: (operation, argument). A read asks for that many frames; a
# seek names a frame.
SCRIPT = [('c', 0), ('r', 100), ('f', 1000), ('r', 2000), ('k', 500), ('r', 300), ('e', 0), ('b', 0), ('f', 1200), ('k', 3000), ('r', 50), ('c', 0), ('r', 2500)]
# The files whose last read asks for more than a 12-frame stream has.
WHOLE = ('first12', 'noinfo', 'cut', 'hole', 'junk', 'id3v1', 'ape', 'apeid3', 'mono', 'free', 'crc', 'xing', 'infonolame', 'infoflags0', 'othersr', 'whole', 'edit00', 'edit01')
LAST = 20000

NATIVE = r'''#define DR_MP3_IMPLEMENTATION
#include "external/dr_mp3.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *files[] = { FILES };
static const unsigned lasts[] = { LASTS };
// 1: the file's bytes through drmp3_init_memory instead of drmp3_init_file
static const unsigned memory[] = { MEMORY };
// 1: one read to the stream's end and nothing else
static const unsigned straight[] = { STRAIGHT };
static const char codes[] = "CODES";
static const unsigned args[] = { ARGS };
static drmp3_int16 shorts[2*LIMIT];
static float floats[2*LIMIT];

static void state(const drmp3 *mp3)
{
    printf("/%u/%u/%u/%u", (unsigned)mp3->currentPCMFrame, mp3->pcmFramesRemainingInMP3Frame, mp3->pcmFramesConsumedInMP3Frame, mp3->mp3FrameChannels);
}

int main(void)
{
    for (unsigned a = 0; a < sizeof(files)/sizeof(files[0]); a++)
    {
        drmp3 mp3;
        unsigned char *data = NULL;
        if (memory[a])
        {
            FILE *file = fopen(files[a], "rb");
            long size;
            if (!file) return 2;
            fseek(file, 0, SEEK_END); size = ftell(file); fseek(file, 0, SEEK_SET);
            data = malloc(size + 1);
            if (fread(data, 1, size, file) != (size_t)size) return 3;
            fclose(file);
            if (!drmp3_init_memory(&mp3, data, size, NULL)) { printf("closed\n"); free(data); continue; }
        }
        else if (!drmp3_init_file(&mp3, files[a], NULL)) { printf("closed\n"); continue; }
        printf("o%u/%u", mp3.channels, mp3.sampleRate);
        state(&mp3);
        const char *script = straight[a]? "r" : codes;
        for (unsigned i = 0; script[i]; i++)
        {
            unsigned n = straight[a]? LIMIT : ((script[i + 1] == 0) && (args[i] != 0))? lasts[a] : args[i];
            unsigned h = 2166136261u;
            printf(" ");
            if (script[i] == 'c') { unsigned frames = (unsigned)drmp3_get_pcm_frame_count(&mp3); printf("c%u", frames); }
            else if (script[i] == 'r')
            {
                unsigned got = (unsigned)drmp3_read_pcm_frames_s16(&mp3, n, shorts);
                for (unsigned k = 0; k < got*mp3.channels; k++) h = (h ^ (unsigned short)shorts[k])*16777619u;
                printf("r%u/%u", got, h);
            }
            else if (script[i] == 'f')
            {
                unsigned got = (unsigned)drmp3_read_pcm_frames_f32(&mp3, n, floats);
                for (unsigned k = 0; k < got*mp3.channels; k++) { unsigned w; memcpy(&w, &floats[k], 4); h = (h ^ w)*16777619u; }
                printf("f%u/%u", got, h);
            }
            else if (script[i] == 'k') { int done = (int)drmp3_seek_to_pcm_frame(&mp3, n); printf("k%d", done); }
            else if (script[i] == 'e') { int done = (int)drmp3_seek_to_pcm_frame(&mp3, mp3.currentPCMFrame); printf("e%d", done); }
            else { drmp3_seek_to_start_of_stream(&mp3); printf("b"); }
            state(&mp3);
        }
        printf("\n");
        drmp3_uninit(&mp3);
        free(data);
    }
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/mp3.bend as H
import ../../src/mp3_stream.bend as S

def fnv(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: fnv(rest, ((h .^. x) * 16777619 : U32))

def fnv.floats(xs: +List<F32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: fnv.floats(rest, ((h .^. F32.bits(x)) * 16777619 : U32))

def state(+player: S.Player) -> String:
  S.Player{_, _, _, +consumed, +remaining, +channels, +current, _} = player
  "/" ++ U32.show(current) ++ "/" ++ U32.show(remaining) ++ "/" ++ U32.show(consumed) ++ "/" ++ U32.show(channels)

# An operation's token (without the state) and the player after it.
type Told is Data:
  Told{player: S.Player, text: String}

def told.count(counted: S.Counted) -> Told:
  S.Counted{player, +frames} = counted
  Told{player, "c" ++ U32.show(frames)}

def told.read(read: S.Read) -> Told:
  S.Read{player, +frames, +samples} = read
  Told{player, "r" ++ U32.show(frames) ++ "/" ++ U32.show(fnv(samples, 2166136261))}

def told.floats(read: S.Floats) -> Told:
  S.Floats{player, +frames, +samples} = read
  Told{player, "f" ++ U32.show(frames) ++ "/" ++ U32.show(fnv.floats(samples, 2166136261))}

def told.seek(sought: S.Sought, +letter: String) -> Told:
  S.Sought{player, +done} = sought
  Told{player, letter ++ Bool.pick(String, done, "1", "0")}

def op(code: U32, +arg: U32, +player: S.Player) -> Told:
  match code:
    case 99: told.count(S.total(player))
    case 114: told.read(S.read.s16(player, arg))
    case 102: told.floats(S.read.f32(player, arg))
    case 107: told.seek(S.seek(player, arg), "k")
    case 101: told.seek(S.seek(player, S.Player.current(player)), "e")
    case _: Told{S.rewind(player), "b"}

def stopped(status: U32) -> String:
  match status:
    case 1: "refused"
    case _: "stopped"

def Told.player(told: Told) -> S.Player:
  Told{player, _} = told
  player

def Told.text(told: Told) -> String:
  Told{_, text} = told
  text

# The script, a token an operation, until a stream stops.
def run(ops: +List<U32>, stop: Bool, +player: S.Player, +out: String) -> String:
  match ops:
    case Con{+code, Con{+arg, +rest}}:
      match stop:
        case True{}: out
        case False{}:
          +next = op(code, arg, player)
          +after = Told.player(next)
          +bad = U32.is_ne(S.Player.status(after), 0)
          run(rest, bad, after, out ++ " " ++ Bool.pick(String, bad, stopped(S.Player.status(after)), Told.text(next) ++ state(after)))
    case _: out

def opened(player: Maybe<S.Player>, +ops: +List<U32>) -> String:
  match player:
    case None{}: "closed"
    case Some{+p}:
      S.Player{H.Stream{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +channels, +rate}, _, _, _, _, _, _, +status} = p
      Bool.pick(String, U32.is_ne(status, 0), stopped(status), run(ops, False{}, p, "o" ++ U32.show(channels) ++ "/" ++ U32.show(rate) ++ state(p)))

def open.as(memory: Bool, +bytes: +List<U32>) -> Maybe<S.Player>:
  match memory:
    case False{}: S.open(bytes)
    case True{}: S.open.memory(bytes)

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>, +ops: +List<U32>, +memory: Bool) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(opened(open.as(memory, bytes), ops))

def main() -> IO(Unit):
  do IO<Unit>:
'''


def last_read(name):
    """The frames the script's last read asks of a file."""
    return LAST if name in WHOLE else SCRIPT[-1][1]


def operations(name, straight=False):
    """The script for a file as the candidate takes it: a code and an argument for each operation. `straight` is one read of
    LAST frames and nothing before it."""
    script = [('r', LAST)] if straight else SCRIPT[:-1] + [(SCRIPT[-1][0], last_read(name))]
    return [value for code, arg in script for value in (ord(code), arg)]


def render(selected, gpu):
    return PROGRAM + ''.join(
        f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result, {probekit.bend_list(operations(name, straight))}, '
        f'{"True" if memory else "False"}{{}}))\n'
        for name, path, memory, straight in selected) + '    IO.print("done")\n'


def parse(text, selected):
    lines = text.splitlines()
    if len(lines) != len(selected) + 1 or lines[-1] != 'done':
        raise ValueError('mp3-stream: candidate output did not finish')
    return lines[:-1]


def reference(items):
    return (NATIVE.replace('FILES', ', '.join(json.dumps(str(ROOT / path)) for _, path, _, _ in items))
            .replace('LASTS', ', '.join(str(last_read(name)) for name, _, _, _ in items)).replace('MEMORY', ', '.join(str(int(memory)) for _, _, memory, _ in items))
            .replace('STRAIGHT', ', '.join(str(int(straight)) for _, _, _, straight in items))
            .replace('CODES', ''.join(code for code, _ in SCRIPT)).replace('ARGS', ', '.join(str(arg) for _, arg in SCRIPT)).replace('LIMIT', str(LAST)))


def first_difference(expected, actual):
    a, b = expected.split(), actual.split()
    index = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
    return f'operation {index}: raylib={a[index] if index < len(a) else "(none)"} jonlib={b[index] if index < len(b) else "(none)"}'


def main():
    probe = probekit.Probe('mp3-stream', probekit.arguments(__doc__))
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files = mp3_probe.cases((probe.args.raylib_source / SOURCE).read_bytes())
    files.update(mp3_layer3_probe.layer12_files())
    if set(WHOLE) - set(files):
        raise ProbeFailure(f'mp3-stream: the corpus has no {sorted(set(WHOLE) - set(files))}')
    items = []
    for name, data in files.items():
        (folder / f'{name}.mp3').write_bytes(data)
        items.append((name, f'{WORK}/{name}.mp3', False, False))
    items += [(name, path, True, False) for name, path, _, _ in items]
    # the short files read straight to their end, both ways
    straight = [(name, path, memory, True) for memory in (False, True) for name, path, _, _ in items[:len(files)] if name in WHOLE and name != 'whole']
    items += straight
    expected = probe.native(reference(items), 'reference', extra_flags=['-ffp-contract=off', '-Wno-everything'], link_raylib=False).splitlines()
    if len(expected) != len(items):
        raise ProbeFailure(f'mp3-stream: the reference printed {len(expected)} rows for {len(items)} files')
    rows = dict(zip(files, expected))
    # read straight to their end, a file and its bytes in memory do not always end alike (the script's seeks hide it)
    half = len(straight) // 2
    ends = dict(zip(((name, memory) for name, _, memory, _ in straight), expected[2 * len(files):]))
    apart = sorted(name for name, _, _, _ in straight[:half] if ends[name, False] != ends[name, True])
    if 'id3v1' not in apart or 'first12' in apart or len(apart) > half // 2:
        raise ProbeFailure(f'mp3-stream: the reference ends memory streams apart from files for {apart}: the file with an ID3v1 tag is not among them, or the plain one is')
    whole = rows['whole'].split()
    full = [row for row in expected[:len(files)] if len(row.split()) == len(SCRIPT) + 1]
    ended = sum(int(row.split()[-1][1:].split('/')[0]) < last_read(name) for name, row in rows.items() if name in WHOLE and len(row.split()) == len(SCRIPT) + 1)
    if len(whole) != len(SCRIPT) + 1 or not whole[0].startswith('o2/44100/0/0/0/2') or whole[1] != 'c4125934/0/0/0/2' or not whole[-1].startswith(f'r{LAST}/'):
        raise ProbeFailure(f'mp3-stream: the reference did not read country.mp3 as expected: {rows["whole"][:200]}')
    if any(len(rows[name].split()) != len(SCRIPT) + 1 for name in LAYER12):
        raise ProbeFailure(f'mp3-stream: the reference did not run the script on the Layer I and II streams: {[rows[name][:80] for name in LAYER12]}')
    if len(full) < 40 or ended < 8 or sum(row == 'closed' for row in expected[:len(files)]) < 6:
        raise ProbeFailure(f'mp3-stream: the corpus lost coverage: {len(full)} files ran the script, {ended} read to their end, {sum(row == "closed" for row in expected[:len(files)])} did not open')
    lanes = probe.candidates(render, items, batch=24, parse=parse, timeout=1500)
    probe.compare(expected, lanes, describe=lambda index: items[index][0] + (' (memory)' if items[index][2] else '') + (' (straight) ' if items[index][3] else ' ') + next(
        (first_difference(expected[index], rows[index]) for rows in lanes.values() if rows[index] != expected[index]), ''))
    probe.finish(files=len(files), streams=len(items), straight=len(straight), ends_apart=len(apart), ran=len(full), read_to_end=ended, closed=sum(row == 'closed' for row in expected[:len(files)]),
                 operations=sum(len(row.split()) - 1 for row in expected if row != 'closed'),
                 files_sha256=hashlib.sha256(b''.join(name.encode() + data for name, data in sorted(files.items()))).hexdigest())


if __name__ == '__main__':
    main()
