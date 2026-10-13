#!/usr/bin/env python3
"""Compare src/xm_pitch.bend with jar_xm's own pitch, waveform and envelope functions.

Reference. jar_xm.h as pinned raylib vendors it, included in the reference
program with its implementation, and its static functions called on
arguments given as bits: jar_xm_linear_period, jar_xm_amiga_period,
jar_xm_frequency for both frequency types, jar_xm_waveform for every type
(the random one in the order the port asks for it), and jar_xm_envelope_tick
tick after tick on envelopes set up in the program.

The program is compiled with the compiler's checks of undefined behaviour
that these functions can meet (a float converted to an int it does not fit,
a shift by a count the type has not, a signed overflow, an index past an
array) as traps, and each call is made under a handler of the trap: a call
that traps prints -1, and the port must answer None for it. So it is jar_xm
itself that says which arguments are undefined. A NaN result is printed as
one value whatever its sign and payload, which are the machine's (and which
the JavaScript lane does not keep).

Candidate. P.linear.period, P.amiga.period, P.frequency.of, P.waveform and
P.envelope.tick on the same arguments.

The arguments: seeded notes from below -1 to past 408 (where the Amiga
period's octave is a shift too far) with NaNs and infinities; periods from
below 0 to past 2^31 with every kind of note offset; linear periods inside
the range Jonmath's powf(2, y) is given for; every step of every waveform;
and envelopes of 0 to 12 points with loops, sustains, frames out of order
and point numbers past the 12th. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

from conformance import gradient_reference
import probekit
from probekit import ProbeFailure
from vorbis_codebook_probe import Rng

FLAGS = ['-ffp-contract=off', '-D_DEFAULT_SOURCE', '-w', '-fsanitize=float-cast-overflow,shift,signed-integer-overflow,bounds',
         '-fsanitize-trap=float-cast-overflow,shift,signed-integer-overflow,bounds']
TICKS = 40

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

static sigjmp_buf trapped;
static void on_trap(int sig) { siglongjmp(trapped, 1); }
// a float's bits; every NaN as one (its sign and payload are the machine's, and the JavaScript lane keeps neither)
static unsigned bits(float x) { unsigned w; memcpy(&w, &x, 4); return x != x? 0x7FC00000u : w; }
static float real(unsigned w) { float x; memcpy(&x, &w, 4); return x; }
static jar_xm_context_t ctx;

static const unsigned notes[] = { @NOTES@ };
static const unsigned linear[][2] = { @LINEAR@ };
static const unsigned amiga[][2] = { @AMIGA@ };
static const unsigned waves[][2] = { @WAVES@ };
// an envelope: 12 points (frame, value), the count, the sustain point, the loop's two points, the flags, and whether the channel is sustained
static const unsigned envelopes[][30] = { @ENVELOPES@ };

#define COUNT(a) ((int)(sizeof(a)/sizeof(a[0])))
#define SEP(i, n) ((i) + 1 < (n)? ", " : "]\n")

int main(void)
{
    int i, k;
    signal(SIGILL, on_trap);
    signal(SIGTRAP, on_trap);
    printf("[");
    for (i = 0; i < COUNT(notes); i++) printf("%u%s", bits(jar_xm_linear_period(real(notes[i]))), SEP(i, COUNT(notes)));
    printf("[");
    for (i = 0; i < COUNT(notes); i++)
    {
        volatile float out = 0;
        if (sigsetjmp(trapped, 1) == 0) { out = jar_xm_amiga_period(real(notes[i])); printf("%u%s", bits(out), SEP(i, COUNT(notes))); }
        else printf("-1%s", SEP(i, COUNT(notes)));
    }
    ctx.module.frequency_type = jar_xm_LINEAR_FREQUENCIES;
    printf("[");
    for (i = 0; i < COUNT(linear); i++) printf("%u%s", bits(jar_xm_frequency(&ctx, real(linear[i][0]), real(linear[i][1]))), SEP(i, COUNT(linear)));
    ctx.module.frequency_type = jar_xm_AMIGA_FREQUENCIES;
    printf("[");
    for (i = 0; i < COUNT(amiga); i++)
    {
        volatile float out = 0;
        if (sigsetjmp(trapped, 1) == 0) { out = jar_xm_frequency(&ctx, real(amiga[i][0]), real(amiga[i][1])); printf("%u%s", bits(out), SEP(i, COUNT(amiga))); }
        else printf("-1%s", SEP(i, COUNT(amiga)));
    }
    printf("[");
    for (i = 0; i < COUNT(waves); i++) printf("%u%s", bits(jar_xm_waveform((jar_xm_waveform_type_t)waves[i][0], (uint8_t)waves[i][1])), SEP(i, COUNT(waves)));
    for (i = 0; i < COUNT(envelopes); i++)
    {
        static jar_xm_envelope_t env;
        static jar_xm_channel_context_t ch;
        const unsigned *e = envelopes[i];
        volatile uint16_t counter = 0;
        volatile float value = 0.25f;
        volatile int alive = 1;
        for (k = 0; k < NUM_ENVELOPE_POINTS; k++) { env.points[k].frame = (uint16_t)e[2*k]; env.points[k].value = (uint16_t)e[2*k + 1]; }
        env.num_points = (uint8_t)e[24]; env.sustain_point = (uint8_t)e[25]; env.loop_start_point = (uint8_t)e[26]; env.loop_end_point = (uint8_t)e[27];
        env.enabled = e[28] & 1; env.sustain_enabled = (e[28] >> 1) & 1; env.loop_enabled = (e[28] >> 2) & 1;
        ch.sustained = e[29] != 0;
        printf("[");
        for (k = 0; k < TICKS && alive; k++)
        {
            uint16_t c = counter;
            float v = value;
            if (sigsetjmp(trapped, 1) == 0) { jar_xm_envelope_tick(&ch, &env, &c, &v); counter = c; value = v; printf("%u, %u, ", (unsigned)c, bits(v)); }
            else { printf("-1, "); alive = 0; }
        }
        printf("%d]\n", (int)alive);
    }
    return 0;
}
'''.replace('TICKS', str(TICKS))

PROGRAM = '''import Base
import ../../jonmath.bend as M
import ../../src/vorbis_codebook.bend as C
import ../../src/xm_module.bend as Xm
import ../../src/xm_pitch.bend as P

# A float's bits; every NaN as one.
def word(+x: F32) -> U32:
  Bool.pick(U32, ((F32.bits(x) .&. 2147483647) > 2139095040 : U32), 2143289344, F32.bits(x))

def shown(value: Maybe<F32>) -> String:
  match value:
    case None{}: "-1"
    case Some{+x}: U32.show(word(x))

def joined(+first: Bool, +out: String, +item: String) -> String:
  out ++ Bool.pick(String, first, "", ", ") ++ item

def periods(notes: +List<U32>, +first: Bool, +out: String) -> String:
  match notes:
    case Nil{}: out ++ "]"
    case Con{+note, +rest}: periods(rest, False{}, joined(first, out, U32.show(word(P.linear.period(C.float.word(note))))))

def amigas(notes: +List<U32>, +first: Bool, +out: String) -> String:
  match notes:
    case Nil{}: out ++ "]"
    case Con{+note, +rest}: amigas(rest, False{}, joined(first, out, shown(P.amiga.period(C.float.word(note)))))

def frequencies(periods: +List<U32>, offsets: +List<U32>, +kind: U32, +first: Bool, +out: String) -> String:
  match periods offsets:
    case Con{+period, +more} Con{+offset, +rest}: frequencies(more, rest, kind, False{}, joined(first, out, shown(P.frequency.of(M.LIBM{}, kind, C.float.word(period), C.float.word(offset)))))
    case _ _: out ++ "]"

def waved(wave: P.Wave) -> String:
  P.Wave{+value, +fine, _} = wave
  Bool.pick(String, fine, U32.show(word(value)), "-1")

def wave.random(wave: P.Wave) -> U32:
  P.Wave{_, _, random} = wave
  random

def waves(kinds: +List<U32>, steps: +List<U32>, +random: U32, +first: Bool, +out: String) -> String:
  match kinds steps:
    case Con{+kind, +more} Con{+step, +rest}: waves(more, rest, wave.random(P.waveform(kind, M.LIBM{}, step, random)), False{}, joined(first, out, waved(P.waveform(kind, M.LIBM{}, step, random))))
    case _ _: out ++ "]"

def points(frames: +List<U32>, values: +List<U32>, acc: +List<Xm.Point>) -> +List<Xm.Point>:
  match frames values:
    case Con{+frame, +more} Con{+value, +rest}: points(more, rest, Con{Xm.Point{frame, value}, acc})
    case _ _: List.reverse(&2, Xm.Point, acc)

def ticked.fine(ticked: P.Ticked) -> Bool:
  P.Ticked{_, _, fine} = ticked
  fine

def ticked.counter(ticked: P.Ticked) -> U32:
  P.Ticked{counter, _, _} = ticked
  counter

def ticked.value(ticked: P.Ticked) -> F32:
  P.Ticked{_, value, _} = ticked
  value

def ticks(n: Nat, on: Bool, +envelope: Xm.Envelope, +sustained: Bool, +counter: U32, +value: F32, +out: String) -> String:
  match n on:
    case _ False{}: out ++ "-1, 0]"
    case 0n True{}: out ++ "1]"
    case 1n+k True{}:
      +next = P.envelope.tick(envelope, sustained, counter, value)
      ticks(k, ticked.fine(next), envelope, sustained, ticked.counter(next), ticked.value(next), Bool.pick(String, ticked.fine(next), out ++ U32.show(ticked.counter(next)) ++ ", " ++ U32.show(word(ticked.value(next))) ++ ", ", out))

def enveloped(+frames: +List<U32>, +values: +List<U32>, +count: U32, +sustain: U32, +start: U32, +end: U32, +flags: U32, +sustained: U32) -> String:
  ticks(TICKSn, True{}, Xm.Envelope{points(frames, values, Nil{}), count, sustain, start, end, U32.is_ne((flags .&. 1 : U32), 0), U32.is_ne((flags .&. 2 : U32), 0), U32.is_ne((flags .&. 4 : U32), 0)}, U32.is_ne(sustained, 0), 0, 0.25, "[")

def main() -> IO(Unit):
  do IO<Unit>:
'''.replace('TICKS', str(TICKS))


def bits(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def notes():
    """Notes as bits: what a module's notes are, the ends of the Amiga period's domain, NaNs and infinities, and seeded ones."""
    rng = Rng(0x0707E5)
    out = [bits(value) for value in (0.0, 1.0, 11.0, 12.0, 48.5, 95.0, 96.0, 119.99, -0.5, -0.999, -1.0, -1.001, -200.0, 407.0, 407.99, 408.0, 409.0, 5000.0, 4.3e9, 1e30)]
    out += [0x80000000, 0x7FC00000, 0xFFC00000, 0x7F800000, 0xFF800000, 1, 0x7F7FFFFF]
    for _ in range(170):
        out.append(bits((rng.next(4300000) - 200000) / 10000.0))
    return out


def linear_pairs():
    """(period, note offset) as bits, inside what Jonmath's powf(2, y) is given for: (4608 - period)/768 within 126 of 0."""
    rng = Rng(0x11EA5)
    out = [(bits(period), bits(offset)) for period, offset in ((4608.0, 0.0), (7680.0, 0.0), (0.0, 0.0), (1536.0, 12.0), (7680.0, -0.25), (-80000.0, 3.0), (90000.0, -7.0), (4608.5, 0.03125))]
    for _ in range(190):
        out.append((bits((rng.next(1600000) - 800000) / 10.0), bits((rng.next(4001) - 2000) / 100.0 if rng.next(4) else 0.0)))
    return out


def amiga_pairs():
    """(period, note offset) as bits: every octave of periods, the ends of the defined ones, and offsets that are 0, small, an octave, large and not numbers."""
    rng = Rng(0xA1116A)
    offsets = [0.0, 1.0, -1.0, 0.25, 12.0, -12.0, 2.5, 100.0, -300.0, 0.001]
    out = []
    for period in (428.0, 856.0, 1712.0, 907.0, 3424.0, 107.0, 1.0, 0.5, 0.0, -0.001, -3.0, 1795162112.0, 1795162240.0, 4e9, 1e20, 13696.0, 53.5, 6848.5):
        for offset in (0.0, 1.5, -2.0):
            out.append((bits(period), bits(offset)))
    for word in (0x7FC00000, 0x7F800000, 0xFF800000, 0x80000000):
        out += [(word, bits(1.0)), (bits(1000.0), word), (word, bits(0.0))]
    for _ in range(260):
        exponent = rng.next(34) - 2
        period = (1.0 + rng.next(1 << 20) / float(1 << 20)) * 2.0 ** exponent
        out.append((bits(period if rng.next(12) else -period), bits(offsets[rng.next(len(offsets))])))
    return out


def wave_pairs():
    """(waveform, step): every step of a byte's 64 for each waveform, steps past them, and waveforms that are none."""
    out = [(kind, step) for kind in (0, 1, 2, 4) for step in range(64)]
    out += [(kind, step) for kind in (0, 1, 2, 4, 5, 9) for step in (64, 100, 127, 128, 200, 255)]
    out += [(3, step) for step in range(40)] + [(0, 16), (3, 7), (1, 5), (3, 0)]
    return out


def envelope_rows():
    """Envelopes as 30 words: 12 points, the count, the sustain point, the loop's points, the flags (enabled, sustain, loop) and
    whether the channel is sustained."""
    def row(points, count=None, sustain=0, loop=(0, 0), flags=1, sustained=1):
        flat = [value for point in (list(points) + [(0, 0)] * 12)[:12] for value in point]
        return flat + [len(points) if count is None else count, sustain, loop[0], loop[1], flags, sustained]
    rise = [(0, 0), (4, 64), (10, 32), (20, 48), (30, 0)]
    twelve = [(3 * k, (17 * k) % 65) for k in range(12)]
    out = [
        row([]), row([(0, 48)]), row([(0, 200)]), row(rise), row(rise, flags=3, sustain=1), row(rise, flags=3, sustain=1, sustained=0), row(rise, flags=5, loop=(1, 3)), row(rise, flags=7, sustain=2, loop=(1, 3)),
        row(rise, flags=5, loop=(3, 1)), row(rise, flags=5, loop=(2, 2)), row(twelve), row(twelve, flags=7, sustain=11, loop=(0, 11)), row(twelve, flags=7, sustain=5, loop=(9, 11), sustained=0),
        # frames that do not rise, and a counter the points never hold
        row([(10, 64), (5, 0), (20, 30)]), row([(5, 10), (5, 60), (9, 20)]), row([(8, 64), (9, 0)]), row([(0, 65535), (40, 1)]),
        # a count that says more points than are set, and fewer
        row(rise, count=12), row(rise, count=2), row(rise, count=1),
        # point numbers past the 12th: a read past the points
        row(rise, flags=5, loop=(12, 1)), row(rise, flags=5, loop=(1, 255)), row(rise, flags=3, sustain=12), row(rise, flags=3, sustain=200, sustained=0), row(rise, flags=1, sustain=99, loop=(77, 88)),
        row(twelve, flags=7, sustain=11, loop=(11, 12)),
    ]
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('xm-pitch', args)
    libm = gradient_reference()
    note_words, linear, amiga, waves, envelopes = notes(), linear_pairs(), amiga_pairs(), wave_pairs(), envelope_rows()

    def words(values):
        return ', '.join(f'{value}u' for value in values)

    def pairs(values):
        return ', '.join(f'{{{a}u, {b}u}}' for a, b in values)

    source = (NATIVE.replace('@NOTES@', words(note_words)).replace('@LINEAR@', pairs(linear)).replace('@AMIGA@', pairs(amiga)).replace('@WAVES@', pairs(waves))
              .replace('@ENVELOPES@', ', '.join('{' + words(row) + '}' for row in envelopes)))
    expected = [json.loads(line) for line in probe.native(source, 'reference', extra_flags=FLAGS, link_raylib=False).splitlines()]
    if len(expected) != 5 + len(envelopes):
        raise ProbeFailure(f'xm-pitch: the reference printed {len(expected)} rows')
    periods, amigas, linears, aways, waved = expected[:5]
    ticked = expected[5:]
    # what the arguments are for: both kinds of answer from the Amiga functions, no trap elsewhere, and envelopes that end at a
    # read past their points
    if (-1 in periods or -1 in linears or -1 in waved or not 20 <= amigas.count(-1) <= len(amigas) - 60 or not 30 <= aways.count(-1) <= len(aways) - 150
            or sum(1 for row in ticked if row[-1] == 0) != 4 or any(len(row) != 2 * TICKS + 1 for row in ticked if row[-1] == 1) or len(set(waved)) < 100):
        raise ProbeFailure(f'xm-pitch: the reference rows are not the ones this probe was written for: {amigas.count(-1)}, {aways.count(-1)}, {[row[-1] for row in ticked]}')
    items = ['periods', 'amigas', 'linears', 'aways', 'waves'] + [f'envelope-{k}' for k in range(len(envelopes))]

    def column(values, k):
        return '[' + ', '.join(str(pair[k]) for pair in values) + ']'

    lines = {
        'periods': f'periods([{", ".join(map(str, note_words))}], True{{}}, "[")',
        'amigas': f'amigas([{", ".join(map(str, note_words))}], True{{}}, "[")',
        'linears': f'frequencies({column(linear, 0)}, {column(linear, 1)}, 0, True{{}}, "[")',
        'aways': f'frequencies({column(amiga, 0)}, {column(amiga, 1)}, 1, True{{}}, "[")',
        'waves': f'waves({column(waves, 0)}, {column(waves, 1)}, 24492, True{{}}, "[")',
    }
    for k, row in enumerate(envelopes):
        lines[f'envelope-{k}'] = f'enveloped([{", ".join(map(str, row[0:24:2]))}], [{", ".join(map(str, row[1:24:2]))}], {", ".join(map(str, row[24:]))})'

    def render(selected, gpu):
        return PROGRAM.replace('LIBM', libm) + ''.join(f'    {"Unit <- " if k + 1 < len(selected) else ""}IO.print({lines[name]})\n' for k, name in enumerate(selected))

    def parse(text, selected):
        got = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(got) != len(selected):
            raise ValueError('xm-pitch: candidate output did not finish')
        return got

    lanes = probe.candidates(render, items, batch=40, parse=parse, timeout=1200)
    probe.compare(expected, lanes, describe=lambda index: items[index])
    probe.finish(notes=len(note_words), frequencies=len(linear) + len(amiga), undefined=amigas.count(-1) + aways.count(-1), waves=len(waves), envelopes=len(envelopes), ticks=TICKS, libm=libm)


if __name__ == '__main__':
    main()
