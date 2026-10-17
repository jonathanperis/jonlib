#!/usr/bin/env python3
"""Compare src/mod.bend with jar_mod.h as pinned raylib vendors it (src/external/jar_mod.h).

Reference. jar_mod.h compiled with JAR_MOD_IMPLEMENTATION, driven as
raudio.c's LoadMusicStream and UpdateMusicStream drive it: jar_mod_init,
jar_mod_load on a copy of the file (kept as the context's modfile, which
jar_mod_seek_start reloads), jar_mod_max_samples, then jar_mod_fillbuffer in
chunks of 4096 stereo samples (the last one shorter) until that many samples
are out. It prints whether the module loads and its channels, the sample
count, and for each chunk its size, an FNV-1a hash of its 16-bit words and
its first two words.

Candidate. src/mod.bend: load, Player.max_samples, then Player.fill on a
fresh player in the same chunks, printing the same lines.

The modules. Built here, seeded: four to eight channels (and the 15-sample
modules jar_mod widens to four), one to three patterns, samples that loop
and samples that do not, every finetune, notes on Amiga periods and others,
and every effect jar_mod plays (arpeggio, the portamentos, vibrato, the
volume slides, the sample offset, position jump, set volume, pattern break,
the fine slides, pattern loop, note cut, pattern delay, speed and tempo),
fast (speed 1 to 3 at 255 beats a minute) so that whole songs are played.
Files that end before their patterns or samples are not modules (jar_mod_load
returns 0).

Contracts (the reference does not run them): what jar_mod leaves undefined
(a file shorter than the 1084 bytes it copies, a pattern table entry past
its 128 patterns, a pattern break past the file's end, a table position past
the pattern table) and songs whose count never ends in raylib (a jump back
to the start); Jonlib answers `undefined` for a file it does not load and
`max why 1` or `max why 2` for a song it does not count. CPU-1, CPU-2 and
JavaScript lanes.
"""
import random

import probekit
from probekit import ProbeFailure

CHUNK = 4096
PERIODS = [856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
           428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
           214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113]
SIGNATURES = {4: b'M.K.', 6: b'6CHN', 8: b'8CHN', 10: b'10CH', 12: b'12CH'}


def be16(value):
    return bytes([(value >> 8) & 255, value & 255])


def note(sample=0, period=0, effect=0):
    return bytes([(sample & 0xF0) | ((period >> 8) & 15), period & 255, ((sample & 15) << 4) | ((effect >> 8) & 15), effect & 255])


def sample_header(sample):
    if sample is None:
        return bytes(30)
    data = sample['data']
    return (b'smp'.ljust(22, b'\0') + be16(len(data) // 2) + bytes([sample.get('finetune', 0), sample.get('volume', 64)])
            + be16(sample.get('reppnt', 0) // 2) + be16(sample.get('replen', 2) // 2))


def module(samples, patterns, table, channels=4, length=None, fifteen=False, signature=None, cut=None, pad=0):
    """A MOD file: samples (dicts or None, 31 or 15), patterns (lists of 64 rows of `channels` notes), the table."""
    count = 15 if fifteen else 31
    headers = b''.join(sample_header(samples[i] if i < len(samples) else None) for i in range(count))
    order = bytes([len(table) if length is None else length, 127]) + bytes(table) + bytes(128 - len(table))
    head = b'jonlib mod'.ljust(20, b'\0') + headers + order
    if not fifteen:
        head += signature if signature is not None else SIGNATURES[channels]
    body = b''.join(b''.join(b''.join(row) for row in pattern) for pattern in patterns)
    data = b''.join(bytes(v & 255 for v in s['data']) for s in samples if s is not None)
    out = head + body + data + bytes(pad)
    return out[:cut] if cut is not None else out


def empty_pattern(channels):
    return [[note() for _ in range(channels)] for _ in range(64)]


class Song:
    """A seeded module: each table position its own pattern, so jumps and breaks only go forward."""

    def __init__(self, seed, channels=4, patterns=2, fifteen=False):
        rng = random.Random(seed)
        self.rng, self.channels, self.fifteen = rng, channels, fifteen
        count = 15 if fifteen else 31
        self.samples = []
        for i in range(rng.randint(2, 6)):
            size = rng.choice((32, 64, 128, 256, 600))
            data = [rng.randint(-128, 127) for _ in range(size)]
            kind = rng.random()
            if kind < 0.4:
                reppnt, replen = 0, 2
            elif kind < 0.8:
                reppnt = rng.randrange(0, size // 2) & ~1
                replen = rng.randrange(4, size - reppnt + 1) & ~1
            else:
                reppnt, replen = rng.randrange(0, size) & ~1, rng.randrange(4, size) & ~1  # past the end: cut to length - reppnt
            self.samples.append(dict(data=data, finetune=rng.randrange(16), volume=rng.choice((64, 48, 32, 0, 70)), reppnt=reppnt, replen=replen))
        self.samples = self.samples[:count]
        self.patterns = [self.pattern(index, patterns) for index in range(patterns)]
        self.table = list(range(patterns))

    def effect(self, index, last, row, channel):
        rng = self.rng
        kinds = ['arp', 'up', 'down', 'porta', 'vibrato', 'porta-slide', 'vibrato-slide', 'offset', 'slide', 'volume',
                 'fine-up', 'fine-down', 'fine-vol-up', 'fine-vol-down', 'cut', 'delay', 'speed', 'tempo', 'none', 'none', 'none']
        if not last:
            kinds += ['break']
        kind = rng.choice(kinds)
        x, y = rng.randrange(16), rng.randrange(16)
        if kind == 'arp':
            return (x << 4) | y
        if kind == 'up':
            return 0x100 | rng.randrange(1, 40)
        if kind == 'down':
            return 0x200 | rng.randrange(1, 40)
        if kind == 'porta':
            return 0x300 | rng.choice((0, rng.randrange(1, 64)))
        if kind == 'vibrato':
            return 0x400 | (x << 4) | y
        if kind == 'porta-slide':
            return 0x500 | rng.choice((x << 4, y))
        if kind == 'vibrato-slide':
            return 0x600 | rng.choice((x << 4, y))
        if kind == 'offset':
            return 0x900 | rng.randrange(0, 3)
        if kind == 'slide':
            return 0xA00 | rng.choice((x << 4, y, (x << 4) | y))
        if kind == 'volume':
            return 0xC00 | rng.choice((0, 16, 40, 64, 80))
        if kind == 'fine-up':
            return 0xE10 | y
        if kind == 'fine-down':
            return 0xE20 | y
        if kind == 'fine-vol-up':
            return 0xEA0 | y
        if kind == 'fine-vol-down':
            return 0xEB0 | y
        if kind == 'cut':
            return 0xEC0 | rng.randrange(0, 4)
        if kind == 'delay':
            return 0xEE0 | rng.randrange(1, 3)
        if kind == 'speed':
            return 0xF00 | rng.randrange(1, 4)
        if kind == 'tempo':
            return 0xF00 | rng.randrange(200, 256)
        if kind == 'break' and row > 40:
            target = rng.randrange(0, 40)
            return 0xD00 | ((target // 10) << 4) | (target % 10)
        return 0

    def pattern(self, index, total):
        rng, channels = self.rng, self.channels
        last = index == total - 1
        rows = []
        for row in range(64):
            notes = []
            for channel in range(channels):
                if row == 0 and channel == 0:
                    notes.append(note(rng.randrange(1, len(self.samples) + 1), rng.choice(PERIODS), 0xF00 | rng.randrange(1, 3)))
                    continue
                if row == 0 and channel == 1:
                    notes.append(note(rng.randrange(1, len(self.samples) + 1), rng.choice(PERIODS), 0xFFF))
                    continue
                if rng.random() < 0.55:
                    sample = rng.choice((0, rng.randrange(1, len(self.samples) + 1), rng.randrange(1, len(self.samples) + 1)))
                    period = rng.choice((0, rng.choice(PERIODS), rng.choice(PERIODS), rng.randrange(100, 1000)))
                    notes.append(note(sample, period, self.effect(index, last, row, channel)))
                else:
                    notes.append(note())
            # one pattern break a row: two would each advance the table position (past the song's end, back
            # to its start without a loop: a count that never ends)
            breaks = [c for c in range(channels) if notes[c][2] & 15 == 0xD]
            for c in breaks[1:]:
                notes[c] = note(0, 0, 0)
            rows.append(notes)
        # a pattern loop on the first channel: the start at row 8, twice from row 12
        if rng.random() < 0.5:
            rows[8][0] = note(0, 0, 0xE60)
            rows[12][0] = note(0, 0, 0xE62)
            for c in range(1, channels):
                rows[12][c] = note()
                rows[8][c] = note()
        # a jump forward on the pattern's last row (never on the last pattern)
        if not last:
            rows[63][channels - 1] = note(0, 0, 0xB00 | (index + 1))
        return rows

    def bytes(self, pad=1024):
        # jar_mod reads a looping sample up to its repeat point past its end (samppos wraps to
        # reppnt + samppos % (reppnt + replen)): bytes after the last sample keep those reads in the file
        return module(self.samples, self.patterns, self.table, channels=self.channels, fifteen=self.fifteen, pad=pad)


def cases():
    """(name, bytes, expected lines when the reference must not run it, or None)."""
    out = []
    for i in range(10):
        channels = (4, 4, 4, 6, 8, 4, 4, 6, 4, 8)[i]
        out.append((f'song-{i}', Song(0x40D + i, channels=channels, patterns=1 + i % 3).bytes(), None))
    out.append(('fifteen-0', Song(0x15A, patterns=2, fifteen=True).bytes(), None))
    out.append(('fifteen-1', Song(0x15B, patterns=1, fifteen=True).bytes(), None))
    one = dict(data=[(i * 7) % 256 - 128 for i in range(64)], finetune=0, volume=64, reppnt=0, replen=2)
    looped = dict(data=[(i * 13) % 256 - 128 for i in range(128)], finetune=3, volume=50, reppnt=32, replen=64)
    plain = empty_pattern(4)
    plain[0][0] = note(1, 428, 0xF01)
    plain[0][1] = note(2, 214, 0xFFF)
    plain[0][2] = note(2, 300, 0x000)
    plain[1][3] = note(1, 856, 0x947)
    out.append(('plain', module([one, looped], [plain], [0]), None))
    # the table's length 0: the song wraps after its first row
    out.append(('length-0', module([one], [plain], [0], length=0), None))
    # not modules: jar_mod_load returns 0
    out.append(('no-patterns', module([one], [plain], [0])[:1084], None))
    out.append(('cut-pattern', module([one], [plain], [0], cut=1084 + 512), None))
    out.append(('cut-sample', module([one, looped], [plain], [0], cut=1084 + 1024 + 100), None))
    # contracts: undefined in C
    out.append(('short', module([one], [plain], [0])[:900], ['undefined']))
    entries = module([one], [plain], [0])
    out.append(('table-past', entries[:952 + 5] + bytes([200]) + entries[952 + 6:], ['undefined']))
    broken = empty_pattern(4)
    broken[0][0] = note(1, 428, 0xF01)
    broken[1][0] = note(0, 0, 0xDFF)
    out.append(('break-past', module([one], [broken], [0]), ['load 1 4', 'max why 1']))
    # a jump back to the start: raylib's count never ends
    back = empty_pattern(4)
    back[0][0] = note(1, 428, 0xF01)
    back[0][1] = note(0, 0, 0xFFF)
    back[3][0] = note(0, 0, 0xB00)
    out.append(('jump-back', module([one], [back], [0]), ['load 1 4', 'max why 2']))
    # two pattern breaks in a row: each advances the table position, past the end and back to the start
    # without a loop (raylib's count never ends)
    twice = empty_pattern(4)
    twice[0][0] = note(1, 428, 0xF01)
    twice[0][1] = note(0, 0, 0xFFF)
    twice[2][0] = note(0, 0, 0xD00)
    twice[2][1] = note(0, 0, 0xD01)
    out.append(('break-twice', module([one], [twice, empty_pattern(4)], [0, 1]), ['load 1 4', 'max why 2']))
    # a song whose last sample is read past the file's end as it plays: silence from there
    out.append(('read-past', Song(0x40D + 5, channels=4, patterns=3).bytes(pad=0), ['load 1 4', 'max 255534', 'END why 1']))
    # a jump to table position 150 of a song of length 200: patterntable[150]
    far = empty_pattern(4)
    far[0][0] = note(1, 428, 0xF01)
    far[1][0] = note(0, 0, 0xB96)
    out.append(('table-position-past', module([one], [far], [0], length=200), ['load 1 4', 'max why 1']))
    return out


NATIVE = r'''#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define JAR_MOD_IMPLEMENTATION
#include "external/jar_mod.h"

static unsigned fnv(unsigned h, unsigned v) { return (h ^ v) * 16777619u; }
static short buf[2*CHUNK];

static void run(const unsigned char *data, unsigned long size)
{
    jar_mod_context_t *ctx = (jar_mod_context_t *)calloc(1, sizeof(jar_mod_context_t));
    unsigned char *copy = (unsigned char *)malloc(size);
    jar_mod_init(ctx);
    memcpy(copy, data, size);
    if (!jar_mod_load(ctx, copy, (int)size)) { printf("load 0\n"); free(copy); free(ctx); return; }
    ctx->modfile = copy;
    ctx->modfilesize = size;
    printf("load 1 %u\n", ctx->number_of_channels);
    unsigned long max = jar_mod_max_samples(ctx);
    printf("max %lu\n", max);
    unsigned long left = max;
    while (left)
    {
        unsigned long n = left < CHUNK ? left : CHUNK, i;
        unsigned h = 2166136261u;
        jar_mod_fillbuffer(ctx, buf, n, 0);
        for (i = 0; i < 2*n; i++) h = fnv(h, (unsigned short)buf[i]);
        printf("chunk %lu %u %u %u\n", n, h, (unsigned short)buf[0], (unsigned short)buf[1]);
        left -= n;
    }
    free(copy);
    free(ctx);
}

int main(void)
{
RUNS
    return 0;
}
'''

PROGRAM = '''import Base
import ../../src/mod.bend as D

def words.onto(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{+head, tail}: words.onto(tail, Con{head, rest})

def words.joined(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: words.joined(tail, words.onto(head, values))

def fnv(words: +List<U32>, +h: U32) -> U32:
  match words:
    case Nil{}: h
    case Con{+w, +rest}: fnv(rest, ((h .^. w) * 16777619 : U32))

def first(words: +List<U32>) -> String:
  match words:
    case Con{+a, Con{+b, _}}: U32.show(a) ++ " " ++ U32.show(b)
    case _: "0 0"

def chunk.line(+n: U32, +words: +List<U32>) -> String:
  "chunk " ++ U32.show(n) ++ " " ++ U32.show(fnv(words, 2166136261)) ++ " " ++ first(words) ++ "\\n"

def chunk.done(filled: D.Filled) -> D.Player:
  D.Filled{+player, _} = filled
  player

def chunk.words(filled: D.Filled) -> +List<U32>:
  D.Filled{_, +words} = filled
  words

def chunks(n: Nat, +player: D.Player, +left: U32, +text: String) -> String:
  match n:
    case 0n: text ++ "why " ++ U32.show(D.Player.why(player))
    case 1n+k:
      +filled = D.Player.fill(player, U32.min(left, CHUNK))
      chunks(k, chunk.done(filled), (left - U32.min(left, CHUNK) : U32), text ++ chunk.line(U32.min(left, CHUNK), chunk.words(filled)))

def counted(+m: D.Mod, c: D.Counted) -> String:
  match c:
    case D.Counted{+n, +why}: Bool.pick(String, U32.is_ne(why, 0), "max why " ++ U32.show(why),
      "max " ++ U32.show(n) ++ "\\n" ++ chunks(U32.to_nat(((n + CHUNK - 1) / CHUNK : U32)), D.Player.new(m), n, ""))

def loaded(l: D.Loaded) -> String:
  match l:
    case D.Failed{+why}: Bool.pick(String, U32.is_eq(why, 0), "load 0", "undefined")
    case D.Loaded{+m}: "load 1 " ++ U32.show(D.Mod.channels(m)) ++ "\\n" ++ counted(m, D.Player.max_samples(m))

def main() -> IO(Unit):
  do IO<Unit>:
CALLS    IO.print("done")
'''


def words_text(words):
    chunks = ', '.join('[' + ', '.join(str(w) for w in words[start:start + 64]) + ']' for start in range(0, len(words), 64))
    return f'words.joined([{chunks}], Nil{{}})'


def render(items, gpu):
    calls = ''.join(f'    IO.print(loaded(D.load({words_text(list(data))})))\n' for _, data, _ in items)
    return PROGRAM.replace('CHUNK', str(CHUNK)).replace('CALLS', calls)


def parse(text, items):
    lines = [line for line in text.split('\n') if line.strip()]
    if not lines or lines[-1] != 'done':
        raise ProbeFailure(f'mod: the candidate did not finish: {text[-300:]!r}')
    groups, current = [], None
    for line in lines[:-1]:
        if line.startswith(('load ', 'undefined')):
            current = [line]
            groups.append(current)
        elif current is not None:
            current.append(line)
    out = []
    for (_, _, contract), group in zip(items, groups):
        if contract and contract[-1].startswith('END '):
            out.append(group[:len(contract) - 1] + ['END ' + group[-1]])
        else:
            out.append(group[:len(contract)] if contract else [line for line in group if line != 'why 0'])
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('mod', args)
    items = cases()
    native_items = [item for item in items if item[2] is None]
    runs = ''.join('    { static const unsigned char d[] = {' + ','.join(str(b) for b in data) + f'}}; run(d, {len(data)}); }}\n'
                   for _, data, _ in native_items)
    text = probe.native(NATIVE.replace('CHUNK', str(CHUNK)).replace('RUNS', runs), 'reference', extra_flags=('-ffp-contract=off',), link_raylib=False)
    groups, current = [], None
    for line in text.splitlines():
        if line.startswith('load '):
            current = [line]
            groups.append(current)
        else:
            current.append(line)
    if len(groups) != len(native_items):
        raise ProbeFailure(f'mod: the reference printed {len(groups)} modules for {len(native_items)}')
    expected_native = iter(groups)
    expected = [contract if contract else next(expected_native) for _, _, contract in items]
    lanes = probe.candidates(render, items, batch=4, parse=parse, timeout=1800)
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: f'module {items[i][0]}')
    played = sum(int(group[1].split()[1]) for group in groups if len(group) > 1 and group[1].startswith('max '))
    probe.finish(modules=len(items), compared=len(native_items), contracts=len(items) - len(native_items), samples_played=played)


if __name__ == '__main__':
    main()
