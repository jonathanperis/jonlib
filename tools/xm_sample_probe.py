#!/usr/bin/env python3
"""Compare src/xm_sample.bend with jar_xm's jar_xm_next_of_sample.

Reference. jar_xm.h as pinned raylib vendors it, included in the reference
program with its implementation: a channel and a sample are set up in the
program and jar_xm_next_of_sample is called on them by a script, as
jar_xm's mixer calls it (once a frame, the channel's frame count moved on
after it) and as a new note does (eight times, for the eight values kept of
the sample before, the frame count set to 0 after them), on a channel with
its sample and without. After each call the channel's position, frame
count, values and the 16 values kept are hashed.

jar_xm says what is undefined by itself: the program is compiled with the
compiler's checks of a float converted to an int it does not fit (and of
shifts, signed overflow and array indexes) as traps, and the sample's
floats lie at the end of readable memory with 20 GiB after them that are
not. A call that traps or faults ends its run with -1, and the port must
find that step not fine. A NaN is hashed as one value.

Candidate. Sm.sample.next on the same channel and sample, by the same
script.

The runs: seeded samples of 0 to 40 floats, mono and stereo, without a loop
and with loops inside the data, at its end, past it, backwards and of no
length, played at steps from 0 to several floats a frame, backwards, by
steps that are not numbers, from positions inside, at the end, past it,
below 0 and past an unsigned int. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

import probekit
from probekit import ProbeFailure
from vorbis_codebook_probe import Rng

FLAGS = ['-ffp-contract=off', '-D_DEFAULT_SOURCE', '-w', '-fsanitize=float-cast-overflow,shift,signed-integer-overflow,bounds',
         '-fsanitize-trap=float-cast-overflow,shift,signed-integer-overflow,bounds']
# a script's calls: a frame of the mixer, a new note's eight, and the channel losing and getting its sample
FRAME, NOTE, UNSAMPLED, SAMPLED = 0, 1, 2, 3

NATIVE = r'''#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#define JAR_XM_IMPLEMENTATION
#include "external/jar_xm.h"
#include <stdio.h>
#include <signal.h>
#include <setjmp.h>
#include <sys/mman.h>

static sigjmp_buf trapped;
static void on_trap(int sig) { siglongjmp(trapped, 1); }
// a float's bits; every NaN as one
static unsigned bits(float x) { unsigned w; memcpy(&w, &x, 4); return x != x? 0x7FC00000u : w; }
static float real(unsigned w) { float x; memcpy(&x, &w, 4); return x; }
static unsigned fnv(unsigned h, unsigned v) { return (h ^ v)*16777619u; }

// A sample's floats at the end of readable memory, with 20 GiB after them that are not: a read past them faults.
static float *placed(const unsigned *words, unsigned count)
{
    static char *base = NULL;
    size_t room = (size_t)1 << 20;
    float *data;
    unsigned i;
    if (!base)
    {
        base = mmap(NULL, room + ((size_t)20 << 30), PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
        if (base == MAP_FAILED) exit(9);
        if (mprotect(base, room, PROT_READ | PROT_WRITE)) exit(9);
    }
    data = (float *)(base + room) - count;
    for (i = 0; i < count; i++) data[i] = real(words[i]);
    return data;
}

static unsigned digest(jar_xm_channel_context_t *ch)
{
    unsigned h = 2166136261u;
    int i;
    h = fnv(h, bits(ch->sample_position)); h = fnv(h, (unsigned)ch->frame_count); h = fnv(h, bits(ch->curr_left)); h = fnv(h, bits(ch->curr_right));
    for (i = 0; i < 8; i++) { h = fnv(h, bits(ch->end_of_previous_sample_left[i])); h = fnv(h, bits(ch->end_of_previous_sample_right[i])); }
    return h;
}

// head: length, loop start, loop length, loop end, loop type, stereo, the position's and the step's bits, the frame count
static void run(const unsigned *head, const unsigned *kept, const unsigned *words, unsigned count, const unsigned *ops, int calls)
{
    static jar_xm_context_t ctx;
    static jar_xm_instrument_t instrument;
    static jar_xm_sample_t sample;
    static jar_xm_channel_context_t ch;
    volatile int k;
    int i;
    ctx.module.linear_interpolation = 1;
    ctx.module.ramping = 1;
    memset(&ch, 0, sizeof(ch));
    sample.length = head[0]; sample.loop_start = head[1]; sample.loop_length = head[2]; sample.loop_end = head[3];
    sample.loop_type = (jar_xm_loop_type_t)head[4]; sample.stereo = (int8_t)head[5]; sample.data = placed(words, count);
    ch.instrument = &instrument; ch.sample = &sample; ch.sample_position = real(head[6]); ch.step = real(head[7]); ch.frame_count = head[8];
    for (i = 0; i < 8; i++) { ch.end_of_previous_sample_left[i] = real(kept[2*i]); ch.end_of_previous_sample_right[i] = real(kept[2*i + 1]); }
    printf("[");
    for (k = 0; k < calls; k++)
    {
        if (sigsetjmp(trapped, 1) != 0) { printf("-1]\n"); return; }
        if (ops[k] == 0) { jar_xm_next_of_sample(&ctx, &ch, -1); ch.frame_count++; }
        else if (ops[k] == 1) { for (i = 0; i < jar_xm_SAMPLE_RAMPING_POINTS; i++) jar_xm_next_of_sample(&ctx, &ch, i); ch.frame_count = 0; }
        else ch.sample = ops[k] == 2? NULL : &sample;
        printf("%u, ", digest(&ch));
    }
    printf("%u]\n", bits(ch.sample_position));
}

int main(void)
{
    signal(SIGILL, on_trap); signal(SIGTRAP, on_trap); signal(SIGSEGV, on_trap); signal(SIGBUS, on_trap);
@RUNS@
    return 0;
}
'''

PROGRAM = '''import Base
import ../../src/vorbis_codebook.bend as C
import ../../src/store.bend as R
import ../../src/xm_sample.bend as Sm

def mix(+h: U32, +v: U32) -> U32:
  ((h .^. v) * 16777619 : U32)

# A float's bits; every NaN as one.
def word(+x: F32) -> U32:
  Bool.pick(U32, ((F32.bits(x) .&. 2147483647) > 2139095040 : U32), 2143289344, F32.bits(x))

def floats(words: +List<U32>, acc: +List<F32>) -> +List<F32>:
  match words:
    case Nil{}: List.reverse(&2, F32, acc)
    case Con{+w, +rest}: floats(rest, Con{C.float.word(w), acc})

def kept(lefts: +List<F32>, rights: +List<F32>, +h: U32) -> U32:
  match lefts rights:
    case Con{+l, +more} Con{+r, +rest}: kept(more, rest, mix(mix(h, word(l)), word(r)))
    case _ _: h

def digest(head: Sm.Head) -> U32:
  Sm.Head{+position, _, +frames, +lefts, +rights, +left, +right} = head
  kept(lefts, rights, mix(mix(mix(mix(2166136261, word(position)), frames), word(left)), word(right)))

def framed(head: Sm.Head) -> Sm.Head:
  Sm.Head{position, step, +frames, lefts, rights, left, right} = head
  Sm.Head{position, step, (frames + 1 : U32), lefts, rights, left, right}

def unframed(head: Sm.Head) -> Sm.Head:
  Sm.Head{position, step, _, lefts, rights, left, right} = head
  Sm.Head{position, step, 0, lefts, rights, left, right}

def Stepped.head(stepped: Sm.Stepped) -> Sm.Head:
  Sm.Stepped{head, _} = stepped
  head

def Stepped.fine(stepped: Sm.Stepped) -> Bool:
  Sm.Stepped{_, fine} = stepped
  fine

# A new note's eight calls.
def noted(n: Nat, on: Bool, +i: U32, +sampled: Bool, +tone: Sm.Tone, +head: Sm.Head) -> Sm.Stepped:
  match n on:
    case _ False{}: Sm.Stepped{head, False{}}
    case 0n True{}: Sm.Stepped{unframed(head), True{}}
    case 1n+k True{}:
      +next = Sm.sample.next(sampled, tone, head, i)
      noted(k, Stepped.fine(next), (i + 1 : U32), sampled, tone, Stepped.head(next))

def framed.step(stepped: Sm.Stepped) -> Sm.Stepped:
  Sm.Stepped{+head, +fine} = stepped
  Sm.Stepped{framed(head), fine}

def call(op: U32, +sampled: Bool, +tone: Sm.Tone, +head: Sm.Head) -> Sm.Stepped:
  match op:
    case 0: framed.step(Sm.sample.next(sampled, tone, head, 4294967295))
    case 1: noted(8n, True{}, 0, sampled, tone, head)
    case _: Sm.Stepped{head, True{}}

def position.word(head: Sm.Head) -> U32:
  Sm.Head{position, _, _, _, _, _, _} = head
  word(position)

def run(ops: +List<U32>, on: Bool, +sampled: Bool, +tone: Sm.Tone, +head: Sm.Head, +out: String) -> String:
  match ops on:
    case _ False{}: out ++ "-1]"
    case Nil{} True{}: out ++ U32.show(position.word(head)) ++ "]"
    case Con{+op, +rest} True{}:
      +now = Bool.pick(Bool, U32.is_eq(op, 2), False{}, Bool.pick(Bool, U32.is_eq(op, 3), True{}, sampled))
      +next = call(op, now, tone, head)
      run(rest, Stepped.fine(next), now, tone, Stepped.head(next), Bool.pick(String, Stepped.fine(next), out ++ U32.show(digest(Stepped.head(next))) ++ ", ", out))

def played(+length: U32, +start: U32, +span: U32, +end: U32, +kind: U32, +stereo: U32, +position: U32, +step: U32, +frames: U32, +lefts: +List<U32>, +rights: +List<U32>, +words: +List<U32>, +count: U32, +ops: +List<U32>) -> String:
  run(ops, True{}, True{}, Sm.Tone{length, start, span, end, U32.is_eq(kind, 1), U32.is_ne(stereo, 0), R.Row.from(floats(words, Nil{})), count},
    Sm.Head{C.float.word(position), C.float.word(step), frames, floats(lefts, Nil{}), floats(rights, Nil{}), 0.0, 0.0}, "[")

def main() -> IO(Unit):
  do IO<Unit>:
'''


def bits(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def runs():
    """Runs: (head, kept, words, ops). head is the sample's length, loop start, loop length, loop end, loop type (0 none, 1 forward)
    and stereo flag, the position's and the step's bits and the frame count; kept the 16 values of the sample before; words the
    sample's floats."""
    rng = Rng(0x5A3B1E)
    mixer = [FRAME] * 20
    varied = [FRAME] * 5 + [NOTE] + [FRAME] * 10 + [NOTE, NOTE] + [FRAME] * 3 + [UNSAMPLED] + [FRAME] * 10 + [NOTE] + [FRAME] * 2 + [SAMPLED] + [FRAME] * 6

    def data(count):
        return [bits((rng.next(65536) - 32768) / 32768.0) for _ in range(count)]

    def kept():
        return [bits((rng.next(4001) - 2000) / 1000.0) for _ in range(16)]

    def one(length, start=0, span=0, end=None, kind=0, stereo=0, position=0.0, step=1.0, frames=0, count=None, ops=mixer):
        end = start + span if end is None else end
        floats = (2 * length if stereo else length) if count is None else count
        return ([length, start, span, end, kind, stereo, position if isinstance(position, int) else bits(position), step if isinstance(step, int) else bits(step), frames], kept(), data(floats), list(ops))

    out = []
    # samples that do not loop: steps below a float, of a float, of several, of none
    for length in (1, 2, 7, 40):
        for step in (0.25, 1.0, 1.5, 3.7, 0.0):
            out.append(one(length, step=step, ops=varied))
    # forward loops inside the data, at its end, and of one float
    for start, span in ((0, 16), (4, 8), (15, 1), (3, 13), (0, 1), (10, 6)):
        for step in (0.5, 1.0, 2.75):
            out.append(one(16, start, span, kind=1, step=step, ops=varied))
    # stereo: the right side is the data's second half; a count of floats one past twice the length too
    out += [one(8, stereo=1, step=0.75, ops=varied), one(8, 2, 5, kind=1, stereo=1, step=1.25, ops=varied), one(7, stereo=1, step=1.0, count=15, ops=varied), one(8, 0, 8, kind=1, stereo=1, step=0.5)]
    # positions: at the last float, at the length and past it, below 0, minus zero, past an unsigned int, and no number
    for position in (15.0, 15.999, 16.0, 17.5, 40.0, -1.0, -0.25, 0x80000000, 4294967040.0, 4294967296.0, 1e12, 0x7FC00000, 0x7F800000, 0xFF800000):
        out.append(one(16, position=position, step=0.5))
        out.append(one(16, 4, 8, kind=1, position=position, step=0.5))
    # steps: backwards, large, and no numbers
    for step in (-0.5, -3.0, 20.0, 1e9, 5e9, 0x7FC00000, 0x7F800000, 0xFF800000):
        out.append(one(16, position=6.0, step=step, ops=varied))
        out.append(one(16, 4, 8, kind=1, position=6.0, step=step, ops=varied))
    # loops that are not inside the data: an end past it, a start past it, a start past the end, no length, lengths past the data
    for start, span, end in ((4, 26, 30), (20, 4, 24), (10, 0, 10), (12, 4, 8), (0, 0, 0), (0, 40, 40), (16, 0, 16), (0, 16, 4000000000), (4000000000, 16, 16)):
        for step in (1.0, 2.5):
            out.append(one(16, start, span, end, kind=1, step=step))
    # a sample without floats, a channel that begins late in its frames, and a length past the data (a stereo sample's too)
    out += [one(0, ops=varied), one(0, 0, 0, kind=1, ops=varied), one(16, frames=5, ops=varied), one(16, frames=200, ops=varied), one(16, count=10, step=1.0), one(8, stereo=1, count=12, step=1.0),
            one(16, count=10, kind=1, start=2, span=6, step=1.0)]
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('xm-sample', args)
    made = runs()

    def words(values):
        return ', '.join(f'{value}u' for value in values)

    blocks = []
    for index, (head, kept, floats, ops) in enumerate(made):
        blocks.append(f'    {{ static const unsigned head[] = {{{words(head)}}}; static const unsigned kept[] = {{{words(kept)}}}; static const unsigned data[] = {{{words(floats + [0])}}}; '
                      f'static const unsigned ops[] = {{{words(ops)}}}; run(head, kept, data, {len(floats)}, ops, {len(ops)}); }}')
    expected = [json.loads(line) for line in probe.native(NATIVE.replace('@RUNS@', '\n'.join(blocks)), 'reference', extra_flags=FLAGS, link_raylib=False).splitlines()]
    if len(expected) != len(made):
        raise ProbeFailure(f'xm-sample: the reference printed {len(expected)} rows for {len(made)} runs')
    undefined = sum(1 for row in expected if row[-1] == -1)
    # what the runs are for: most are defined to their end, a fifth or so end at an undefined call (some at their first, some later)
    late = sum(1 for row in expected if row[-1] == -1 and len(row) > 3)
    if not 15 <= undefined <= len(made) // 2 or late < 5 or sum(1 for row in expected if row == [-1]) < 4 or len({tuple(row) for row in expected if row[-1] != -1}) < len(made) // 3:
        raise ProbeFailure(f'xm-sample: the reference rows are not the ones this probe was written for: {undefined} undefined of {len(made)}, {late} late')
    items = list(range(len(made)))

    def lists(values):
        return '[' + ', '.join(str(value) for value in values) + ']'

    def render(selected, gpu):
        lines = []
        for k, index in enumerate(selected):
            head, kept, floats, ops = made[index]
            call = f'played({", ".join(str(value) for value in head)}, {lists(kept[0::2])}, {lists(kept[1::2])}, {lists(floats) if floats else "Nil{}"}, {len(floats)}, {lists(ops)})'
            lines.append(f'    {"Unit <- " if k + 1 < len(selected) else ""}IO.print({call})\n')
        return PROGRAM + ''.join(lines)

    def parse(text, selected):
        got = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(got) != len(selected):
            raise ValueError('xm-sample: candidate output did not finish')
        return got

    lanes = probe.candidates(render, items, batch=60, parse=parse, timeout=1200)
    probe.compare(expected, lanes, describe=lambda index: f'run {index}: {made[index][0]}')
    probe.finish(runs=len(made), calls=sum(len(ops) for _, _, _, ops in made), undefined=undefined, floats=sum(len(floats) for _, _, floats, _ in made))


if __name__ == '__main__':
    main()
