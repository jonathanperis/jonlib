#!/usr/bin/env python3
"""Compare src/xm_player.bend with jar_xm's rows and ticks.

Reference. jar_xm.h as pinned raylib vendors it, included in the reference
program with its implementation: a module is loaded
(jar_xm_create_context_safe, jar_xm_set_max_loop_count(ctx, 0) as raylib
does) and a script of calls is run on it: jar_xm_tick a number of times,
jar_xm_get_remaining_samples and jar_xm_reset. After every tick the whole
context is hashed: the song's tempo, BPM, global volume, place, jumps and
loop count, the samples left in the tick, and every field of every channel
(its note, instrument, sample and slot, its position, period, frequency and
step, its volumes, envelopes, vibratos, tremolo, remembered parameters and
the values the mixer ramps between). A run prints the rolling hash every 16
ticks, each count of remaining samples, and its last hash.

jar_xm says what is undefined by itself: the program is compiled with the
compiler's checks of undefined behaviour as traps, jar_xm's block of memory
is placed at the end of readable memory (and the bytes between its end and
that boundary are looked at after every call: a write there is one past the
block), and each call is made under a handler. A call that traps or faults
ends its run with -1, and the port's player must have stopped there. One
thing the program looks for itself: a row outside its pattern's slots (a
break or a jump to a row the pattern has not), which jar_xm reads in
whatever lies after them in its block; the row's place is worked out
before each tick as jar_xm_row does, and such a row ends the run too. The
length is taken by jar_xm_get_remaining_samples itself for the modules
whose rows cannot leave their patterns (no break, jump or loop), and by
the program's copy of that function, which looks at each row, for the
others. (A second context beside the first cannot be: jar_xm's random
waveform is one state for every context of a program. For the same reason
each run is in a process of its own.)

Candidate. Pl.player.new of Xm.load's module under the host's libm
profile, then Pl.tick, Pl.remaining.samples and Pl.reset by the script.

The modules: raylib's mini1111.xm, played for its length first as raylib
does and tick by tick past its end; and modules built by the xm-module
gate's writer with seeded patterns: every effect and volume column over
instruments with and without envelopes, vibratos, loops, several samples
and none, in linear and Amiga frequencies, some kept to effects that go on
for long and some left to meet what jar_xm does not define. CPU-1, CPU-2
and JavaScript lanes.
"""
import json

from conformance import gradient_reference
import probekit
from probekit import ROOT, ProbeFailure
from vorbis_codebook_probe import Rng
import xm_module_probe as xp

SOURCE = 'examples/audio/resources/mini1111.xm'
WORK = '.build/xm-player-probe/cases'
FLAGS = ['-ffp-contract=off', '-D_DEFAULT_SOURCE', '-w', '-fsanitize=float-cast-overflow,shift,signed-integer-overflow,bounds',
         '-fsanitize-trap=float-cast-overflow,shift,signed-integer-overflow,bounds']
# a script's calls: a number of ticks, or one of these: the length (by the program's copy that looks at each row), a reset, and the
# length by jar_xm's own function
REMAINING, RESET, OWN = -1, -2, -3
EVERY = 16

NATIVE = r'''#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <signal.h>
#include <setjmp.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

// jar_xm's block of memory at the end of readable memory (its start a multiple of 16, as malloc's is), with 1 GiB after it that is not
static char *block_end;
static size_t block_slack;
static void *guarded(size_t size)
{
    static char *base = NULL;
    size_t room = (size_t)64 << 20, whole = (size + 15) & ~(size_t)15;
    if (!base)
    {
        base = mmap(NULL, room + ((size_t)1 << 30), PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
        if (base == MAP_FAILED || mprotect(base, room, PROT_READ | PROT_WRITE)) exit(9);
    }
    if (whole > room) exit(9);
    memset(base + room - whole, 0, whole);
    block_end = base + room - whole + size;
    block_slack = whole - size;
    return base + room - whole;
}
#define JARXM_MALLOC(sz) guarded(sz)
#define JARXM_FREE(p) ((void)(p))
#define JAR_XM_IMPLEMENTATION
#include "external/jar_xm.h"

static sigjmp_buf trapped;
static void on_trap(int sig) { siglongjmp(trapped, 1); }
// a float's bits; every NaN as one
static unsigned bits(float x) { unsigned w; memcpy(&w, &x, 4); return x != x? 0x7FC00000u : w; }
static unsigned fnv(unsigned h, unsigned v) { return (h ^ v)*16777619u; }

// whether something was written between the block's end and the boundary: past the block
static int past(void)
{
    size_t i;
    for (i = 0; i < block_slack; i++) if (block_end[i]) return 1;
    return 0;
}

// Whether the row jar_xm_tick is about to play is outside its pattern's slots (or its pattern outside the module's patterns): jar_xm
// reads the slots where they would be, in whatever lies there. The row's place is worked out as jar_xm_row does.
static int outside(jar_xm_context_t *ctx)
{
    unsigned index = ctx->current_table_index, row = ctx->current_row, pattern;
    if (ctx->current_tick != 0) return 0;
    if (ctx->position_jump) { index = ctx->jump_dest; row = ctx->jump_row; }
    else if (ctx->pattern_break) { index = (uint8_t)(index + 1); row = ctx->jump_row; }
    if ((ctx->position_jump || ctx->pattern_break) && index >= ctx->module.length) index = (uint8_t)ctx->module.restart_position;
    pattern = ctx->module.pattern_table[index];
    return pattern >= ctx->module.num_patterns || row >= ctx->module.patterns[pattern].num_rows;
}

// jar_xm_get_remaining_samples with each row looked at before it is played: -1 where one is outside its pattern, where the block
// is written past, or where the song does not come to a row again in 4096 times 4096 ticks
static long long remaining(jar_xm_context_t *ctx)
{
    uint64_t total = 0;
    uint8_t current = jar_xm_get_loop_count(ctx);
    long ticks = 0;
    jar_xm_set_max_loop_count(ctx, 0);
    while (jar_xm_get_loop_count(ctx) == current)
    {
        total += ctx->remaining_samples_in_tick;
        ctx->remaining_samples_in_tick = 0;
        if (outside(ctx) || ++ticks > 4096L*4096L) return -1;
        jar_xm_tick(ctx);
        if (past()) return -1;
    }
    ctx->loop_count = current;
    return (long long)total;
}

static unsigned channel(unsigned h, jar_xm_context_t *ctx, jar_xm_channel_context_t *ch)
{
    unsigned owner = 0, index = 0;
    int i;
    for (i = 0; ch->sample && i < ctx->module.num_instruments; i++)
    {
        jar_xm_instrument_t *in = ctx->module.instruments + i;
        if (in->num_samples && ch->sample >= in->samples && ch->sample < in->samples + in->num_samples) { owner = i + 1; index = (unsigned)(ch->sample - in->samples); }
    }
    h = fnv(h, bits(ch->note)); h = fnv(h, bits(ch->orig_note));
    h = fnv(h, ch->instrument? (unsigned)(ch->instrument - ctx->module.instruments) + 1 : 0); h = fnv(h, owner); h = fnv(h, index);
    if (ch->current) { h = fnv(h, ch->current->note); h = fnv(h, ch->current->instrument); h = fnv(h, ch->current->volume_column); h = fnv(h, ch->current->effect_type); h = fnv(h, ch->current->effect_param); }
    else for (i = 0; i < 5; i++) h = fnv(h, 0);
    h = fnv(h, bits(ch->sample_position)); h = fnv(h, bits(ch->period)); h = fnv(h, bits(ch->frequency)); h = fnv(h, bits(ch->step));
    h = fnv(h, bits(ch->volume)); h = fnv(h, bits(ch->panning)); h = fnv(h, ch->autovibrato_ticks); h = fnv(h, ch->sustained);
    h = fnv(h, bits(ch->fadeout_volume)); h = fnv(h, bits(ch->volume_envelope_volume)); h = fnv(h, bits(ch->panning_envelope_panning));
    h = fnv(h, ch->volume_envelope_frame_count); h = fnv(h, ch->panning_envelope_frame_count); h = fnv(h, bits(ch->autovibrato_note_offset));
    h = fnv(h, ch->arp_in_progress); h = fnv(h, ch->arp_note_offset);
    h = fnv(h, ch->volume_slide_param); h = fnv(h, ch->fine_volume_slide_param); h = fnv(h, ch->global_volume_slide_param); h = fnv(h, ch->panning_slide_param);
    h = fnv(h, ch->portamento_up_param); h = fnv(h, ch->portamento_down_param); h = fnv(h, ch->fine_portamento_up_param); h = fnv(h, ch->fine_portamento_down_param);
    h = fnv(h, ch->extra_fine_portamento_up_param); h = fnv(h, ch->extra_fine_portamento_down_param); h = fnv(h, ch->tone_portamento_param); h = fnv(h, bits(ch->tone_portamento_target_period));
    h = fnv(h, ch->multi_retrig_param); h = fnv(h, ch->note_delay_param); h = fnv(h, ch->pattern_loop_origin); h = fnv(h, ch->pattern_loop_count);
    h = fnv(h, ch->vibrato_in_progress); h = fnv(h, (unsigned)ch->vibrato_waveform); h = fnv(h, ch->vibrato_waveform_retrigger); h = fnv(h, ch->vibrato_param); h = fnv(h, ch->vibrato_ticks);
    h = fnv(h, bits(ch->vibrato_note_offset)); h = fnv(h, (unsigned)ch->tremolo_waveform); h = fnv(h, ch->tremolo_waveform_retrigger); h = fnv(h, ch->tremolo_param); h = fnv(h, ch->tremolo_ticks);
    h = fnv(h, bits(ch->tremolo_volume)); h = fnv(h, ch->tremor_param); h = fnv(h, ch->tremor_on);
    h = fnv(h, bits(ch->target_panning)); h = fnv(h, bits(ch->target_volume)); h = fnv(h, (unsigned)ch->frame_count);
    for (i = 0; i < 8; i++) { h = fnv(h, bits(ch->end_of_previous_sample_left[i])); h = fnv(h, bits(ch->end_of_previous_sample_right[i])); }
    h = fnv(h, bits(ch->curr_left)); h = fnv(h, bits(ch->curr_right)); h = fnv(h, bits(ch->actual_panning)); h = fnv(h, bits(ch->actual_volume));
    return h;
}

static unsigned digest(jar_xm_context_t *ctx)
{
    unsigned h = 2166136261u;
    int i;
    h = fnv(h, ctx->tempo); h = fnv(h, ctx->bpm); h = fnv(h, bits(ctx->global_volume)); h = fnv(h, ctx->current_table_index); h = fnv(h, ctx->current_row); h = fnv(h, ctx->current_tick);
    h = fnv(h, bits(ctx->remaining_samples_in_tick)); h = fnv(h, ctx->position_jump); h = fnv(h, ctx->pattern_break); h = fnv(h, ctx->jump_dest); h = fnv(h, ctx->jump_row); h = fnv(h, ctx->extra_ticks);
    h = fnv(h, ctx->loop_count);
    for (i = 0; i < ctx->module.num_channels; i++) h = channel(h, ctx, ctx->channels + i);
    return h;
}

static void run(const char *path, const int *ops, int count)
{
    unsigned char *data;
    size_t size;
    FILE *file = fopen(path, "rb");
    jar_xm_context_t *ctx = NULL;
    volatile int k, seen = 0;
    volatile unsigned roll = 2166136261u;
    if (!file) exit(2);
    fseek(file, 0, SEEK_END);
    size = (size_t)ftell(file);
    fseek(file, 0, SEEK_SET);
    data = (unsigned char *)malloc(size + 1);
    if (fread(data, 1, size, file) != size) exit(3);
    fclose(file);
    if (jar_xm_create_context_safe(&ctx, (const char *)data, size, 48000)) exit(4);
    jar_xm_set_max_loop_count(ctx, 0);
    printf("[");
    for (k = 0; k < count; k++)
    {
        if (sigsetjmp(trapped, 1) != 0) { printf("-1]\n"); free(data); return; }
        if (ops[k] == -1 || ops[k] == -3)
        {
            // jar_xm's own function, or the program's copy that looks at each row
            long long total = ops[k] == -3? (long long)jar_xm_get_remaining_samples(ctx) : remaining(ctx);
            if (total < 0 || past()) { printf("-1]\n"); free(data); return; }
            // the port counts in 32 bits
            if (total >> 32) exit(5);
            roll = fnv(roll, (unsigned)total); roll = fnv(roll, digest(ctx));
            printf("%lld, ", total);
        }
        else if (ops[k] == -2) { jar_xm_reset(ctx); roll = fnv(roll, digest(ctx)); }
        else
        {
            volatile int t;
            for (t = 0; t < ops[k]; t++)
            {
                if (outside(ctx)) { printf("-1]\n"); free(data); return; }
                jar_xm_tick(ctx);
                if (past()) { printf("-1]\n"); free(data); return; }
                roll = fnv(roll, digest(ctx));
                if (++seen % EVERY == 0) printf("%u, ", roll);
            }
        }
    }
    printf("%u]\n", roll);
    free(data);
}

// A run in a process of its own: jar_xm's random waveform is one state for every module a process plays, and each run is to
// begin with it as a program's first module does.
static void alone(const char *path, const int *ops, int count)
{
    pid_t child;
    int status = 0;
    fflush(stdout);
    child = fork();
    if (child < 0) exit(10);
    if (child == 0) { run(path, ops, count); fflush(stdout); _exit(0); }
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status) != 0) exit(11);
}

int main(void)
{
    signal(SIGILL, on_trap); signal(SIGTRAP, on_trap); signal(SIGSEGV, on_trap); signal(SIGBUS, on_trap);
@RUNS@
    return 0;
}
'''.replace('EVERY', str(EVERY))

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/xm_module.bend as Xm
import ../../src/xm_sample.bend as Sm
import ../../src/xm_player.bend as Pl

def mix(+h: U32, +v: U32) -> U32:
  ((h .^. v) * 16777619 : U32)

# A float's bits; every NaN as one.
def word(+x: F32) -> U32:
  Bool.pick(U32, ((F32.bits(x) .&. 2147483647) > 2139095040 : U32), 2143289344, F32.bits(x))

def flag(on: Bool) -> U32:
  match on:
    case True{}: 1
    case False{}: 0

def kept(lefts: +List<F32>, rights: +List<F32>, +h: U32) -> U32:
  match lefts rights:
    case Con{+l, +more} Con{+r, +rest}: kept(more, rest, mix(mix(h, word(l)), word(r)))
    case _ _: h

def mixed.pitch(pitch: Pl.Pitch, +h: U32) -> U32:
  Pl.Pitch{+note, +orig, _, _, _} = pitch
  mix(mix(h, word(note)), word(orig))

def mixed.slot(slot: Xm.Slot, +h: U32) -> U32:
  Xm.Slot{+note, +instrument, +volume, +effect, +param} = slot
  mix(mix(mix(mix(mix(h, note), instrument), volume), effect), param)

def mixed.moving(head: Sm.Head, pitch: Pl.Pitch, +h: U32) -> U32:
  Sm.Head{+position, +step, _, _, _, _, _} = head
  Pl.Pitch{_, _, +period, +frequency, _} = pitch
  mix(mix(mix(mix(h, word(position)), word(period)), word(frequency)), word(step))

def mixed.level(level: Pl.Level, wobble: Pl.Wobble, +h: U32) -> U32:
  Pl.Level{+volume, +panning, +sustained, +fadeout, +envelope, +spread, +volume_frames, +panning_frames, _, _, _, _, _, _} = level
  Pl.Wobble{+auto_ticks, +auto_offset, +arp, +arp_offset, _, _, _, _, _, _, _, _, _, _} = wobble
  mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(h, word(volume)), word(panning)), auto_ticks), flag(sustained)), word(fadeout)), word(envelope)), word(spread)), volume_frames), panning_frames), word(auto_offset)), flag(arp)), arp_offset)

def mixed.memo(memo: Pl.Memo, pitch: Pl.Pitch, +h: U32) -> U32:
  Pl.Memo{+volume_slide, +fine_volume_slide, +global_slide, +panning_slide, +porta_up, +porta_down, +fine_up, +fine_down, +extra_up, +extra_down, +tone, +retrig, +delay, +loop_origin, +loop_count, _} = memo
  Pl.Pitch{_, _, _, _, +target} = pitch
  mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(h, volume_slide), fine_volume_slide), global_slide), panning_slide), porta_up), porta_down), fine_up), fine_down), extra_up), extra_down), tone), word(target)), retrig), delay),
    loop_origin), loop_count)

def tremor.of(memo: Pl.Memo) -> U32:
  Pl.Memo{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, tremor} = memo
  tremor

def mixed.wobble(wobble: Pl.Wobble, level: Pl.Level, +tremor: U32, +h: U32) -> U32:
  Pl.Wobble{_, _, _, _, +vibrating, +vibrato_wave, +vibrato_again, +vibrato_param, +vibrato_ticks, +vibrato_offset, +tremolo_wave, +tremolo_again, +tremolo_param, +tremolo_ticks} = wobble
  Pl.Level{_, _, _, _, _, _, _, _, +tremolo, +tremoring, +target_panning, +target_volume, _, _} = level
  mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(h, flag(vibrating)), vibrato_wave), flag(vibrato_again)), vibrato_param), vibrato_ticks), word(vibrato_offset)), tremolo_wave), flag(tremolo_again)), tremolo_param), tremolo_ticks),
    word(tremolo)), tremor), flag(tremoring)), word(target_panning)), word(target_volume))

def mixed.head(head: Sm.Head, level: Pl.Level, +h: U32) -> U32:
  Sm.Head{_, _, +frames, +lefts, +rights, +left, +right} = head
  Pl.Level{_, _, _, _, _, _, _, _, _, _, _, _, +actual_panning, +actual_volume} = level
  mix(mix(mix(mix(kept(lefts, rights, mix(h, frames)), word(left)), word(right)), word(actual_panning)), word(actual_volume))

def mixed.channel(channel: Pl.Channel, +h: U32) -> U32:
  Pl.Channel{+instrument, +owner, +sample, +slot, +head, +pitch, +level, +wobble, +memo} = channel
  mixed.head(head, level, mixed.wobble(wobble, level, tremor.of(memo), mixed.memo(memo, pitch, mixed.level(level, wobble, mixed.moving(head, pitch, mixed.slot(slot, mix(mix(mix(mixed.pitch(pitch, h), instrument), owner), sample)))))))

def mixed.channels(channels: +List<Pl.Channel>, +h: U32) -> U32:
  match channels:
    case Nil{}: h
    case Con{+channel, +rest}: mixed.channels(rest, mixed.channel(channel, h))

def mixed.song(song: Pl.Song, +index: U32, +row: U32, +tick: U32, +remaining: F32, +loops: U32) -> U32:
  Pl.Song{+tempo, +bpm, +global, +jumping, +breaking, +jump_dest, +jump_row, +extra, _, _} = song
  mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(2166136261, tempo), bpm), word(global)), index), row), tick), word(remaining)), flag(jumping)), flag(breaking)), jump_dest), jump_row), extra), loops)

def digest(player: Pl.Player) -> U32:
  Pl.Player{_, _, _, _, +song, +index, +row, +tick, +remaining, _, +loops, _, +channels} = player
  mixed.channels(channels, mixed.song(song, index, row, tick, remaining, loops))

# The state of a run: the player, the rolling hash, the ticks seen and what is printed.
type Run is Data:
  Run{player: Pl.Player, roll: U32, seen: U32, out: String}

def Run.player(run: Run) -> Pl.Player:
  Run{player, _, _, _} = run
  player

def ticked(+player: Pl.Player, run: Run) -> Run:
  Run{_, +roll, +seen, +out} = run
  Run{player, mix(roll, digest(player)), (seen + 1 : U32), Bool.pick(String, U32.is_eq(((seen + 1) % EVERY : U32), 0) && U32.is_eq(Pl.Player.why(player), 0), out ++ U32.show(mix(roll, digest(player))) ++ ", ", out)}

def ticks(n: Nat, on: Bool, +run: Run) -> Run:
  match n on:
    case _ False{}: run
    case 0n True{}: run
    case 1n+k True{}:
      +next = ticked(Pl.tick(Run.player(run)), run)
      ticks(k, U32.is_eq(Pl.Player.why(Run.player(next)), 0), next)

def lengthed(length: Pl.Counted, run: Run) -> Run:
  Pl.Counted{+player, +samples} = length
  Run{_, +roll, +seen, +out} = run
  Run{player, mix(mix(roll, samples), digest(player)), seen, Bool.pick(String, U32.is_eq(Pl.Player.why(player), 0), out ++ U32.show(samples) ++ ", ", out)}

def rewound(+player: Pl.Player, run: Run) -> Run:
  Run{_, +roll, +seen, +out} = run
  Run{player, mix(roll, digest(player)), seen, out}

def call(kind: U32, +op: U32, +run: Run) -> Run:
  match kind:
    case 1: lengthed(Pl.remaining.samples(Run.player(run)), run)
    case 2: rewound(Pl.reset(Run.player(run)), run)
    case _: ticks(U32.to_nat(op), True{}, run)

def ending(run: Run) -> String:
  Run{+player, +roll, _, +out} = run
  Bool.pick(String, U32.is_eq(Pl.Player.why(player), 0), out ++ U32.show(roll) ++ "]", out ++ "-1]")

def calls(ops: +List<U32>, on: Bool, +run: Run) -> String:
  match ops on:
    case _ False{}: ending(run)
    case Nil{} True{}: ending(run)
    case Con{+op, +rest} True{}:
      +next = call(Bool.pick(U32, U32.is_eq(op, 4294967295) || U32.is_eq(op, 4294967293), 1, Bool.pick(U32, U32.is_eq(op, 4294967294), 2, 0)), op, run)
      calls(rest, U32.is_eq(Pl.Player.why(Run.player(next)), 0), next)

def played(loaded: Xm.Loaded, +ops: +List<U32>) -> String:
  match loaded:
    case Xm.Loaded{+module}: calls(ops, True{}, Run{Pl.player.new(M.LIBM{}, module, 48000, 24492), 2166136261, 0, "["})
    case _: "[-9]"

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>, +ops: +List<U32>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(played(Xm.load(bytes), ops))

def main() -> IO(Unit):
  do IO<Unit>:
'''.replace('EVERY', str(EVERY))


# -----------------------------------------------------------------------------
# Modules built here

# effects that go on for long without meeting what jar_xm does not define: no jump, break, loop or delay, no retrigger of a channel
# that may have no sample, no finetune
TAME = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 16, 17, 20, 21, 25, 29, 33]
EVERYTHING = list(range(0, 36))


def instruments(rng):
    """Instruments of every kind: with and without envelopes (sustained, looped), with a vibrato of each waveform, with one sample
    and with several, with loops and without, 8 and 16 bits, and one without samples."""
    def data(count, wide=False):
        return xp.deltas(rng, count, wide)
    rise = [(0, 64), (6, 32), (14, 48), (30, 0)]
    wave = [(0, 32), (8, 64), (16, 0), (24, 48), (40, 20)]
    return [
        xp.instrument([xp.sample(data(300), loop=1, start=40, span=200, relative=12)], volume=xp.envelope(rise, flags=1), fadeout=2000),
        xp.instrument([xp.sample(data(500), relative=20, finetune=-30, panning=40)], volume=xp.envelope(rise, sustain=1, flags=3), panning=xp.envelope(wave, flags=1), fadeout=600),
        xp.instrument([xp.sample(data(200, wide=True), wide=True, loop=1, start=20, span=300, relative=7, volume=48)], volume=xp.envelope(wave, loop=(1, 3), flags=5), vibrato=(0, 4, 9, 20)),
        xp.instrument([xp.sample(data(120), relative=24, panning=220), xp.sample(data(90), loop=1, start=10, span=60, relative=5, finetune=40), xp.sample(data(64), relative=-3)],
                      notes=[(k // 20) % 3 for k in range(96)], vibrato=(1, 0, 6, 33)),
        xp.instrument(),
        xp.instrument([xp.sample(data(400), stereo=True, loop=1, start=30, span=100, relative=10)], panning=xp.envelope(rise, sustain=2, loop=(0, 2), flags=7), vibrato=(3, 10, 5, 12), fadeout=65535),
        xp.instrument([xp.sample(data(250), relative=30)], volume=xp.envelope([(0, 50)], flags=1), vibrato=(2, 2, 15, 60)),
        xp.instrument([xp.sample(data(30), loop=1, start=0, span=30, relative=40, finetune=-128)], vibrato=(4, 30, 3, 7)),
    ]


def soup(rng, rows, channels, effects, notes=0.5, count=8):
    """A pattern's seeded slots: notes of a middle range and key offs, instruments (one past the module's now and then), volume columns
    and effects with any parameter."""
    out = []
    for _ in range(rows * channels):
        note = (97 if rng.next(12) == 0 else 20 + rng.next(60)) if rng.next(100) < notes * 100 else None
        instrument = (1 + rng.next(count + 1) if rng.next(40) else 200) if rng.next(3) else None
        volume = (0x10 + rng.next(0xF0)) if rng.next(3) == 0 else None
        effect = effects[rng.next(len(effects))] if rng.next(2) else None
        param = rng.next(256) if effect is not None or rng.next(6) == 0 else None
        out.append((note, instrument, volume, effect, param))
    return xp.slots(out)


def built():
    """name -> module."""
    out = {}
    for index, (effects, linear, channels, tempo, bpm) in enumerate(((TAME, 1, 4, 3, 150), (TAME, 0, 3, 6, 125), (TAME, 1, 6, 2, 200), (TAME, 0, 2, 5, 90), (EVERYTHING, 1, 4, 3, 150), (EVERYTHING, 0, 4, 4, 140),
                                                                     (EVERYTHING, 1, 2, 6, 125), (EVERYTHING, 0, 5, 3, 180), (EVERYTHING, 1, 3, 7, 60), (EVERYTHING, 1, 8, 1, 255))):
        rng = Rng(0xD1CE + 97 * index)
        made = instruments(rng)
        patterns = [xp.pattern(rows, soup(rng, rows, channels, effects, count=len(made))) for rows in (16, 9, 24, 12)]
        out[f'{"tame" if effects is TAME else "all"}-{index}'] = xp.module(patterns, made, channels=channels, order=(0, 1, 2, 3, 1), restart=1 if index % 2 else 0, flags=linear, tempo=tempo, bpm=bpm)
    rng = Rng(0x5EED)
    made = instruments(rng)
    note = lambda n, i=1, v=None, e=None, p=None: (n, i, v, e, p)
    rest = (None, None, None, None, None)
    # jumps, breaks, loops and delays, each alone on a channel that plays a note
    out['flow'] = xp.module([xp.pattern(8, xp.slots([note(40), rest, rest, note(45, e=0x0D, p=0x02), rest, rest, rest, rest, rest, rest, rest, rest, rest, rest, rest, rest])),
                             xp.pattern(8, xp.slots([note(50, e=0x0E, p=0x60), rest, note(52), rest, note(53, e=0x0E, p=0x62), rest, note(55, e=0x0E, p=0xE2), rest, note(57, e=0x0B, p=0x00), rest] + [rest] * 6)),
                             xp.pattern(4, xp.slots([note(60, e=0x0E, p=0xD2), note(62, e=0x0E, p=0x93), note(64, e=0x0E, p=0xC1), rest, note(65, e=0x0F, p=0x02), rest, note(67, e=0x0F, p=0x60), rest]))],
                            made, channels=2, order=(0, 1, 2), tempo=4, bpm=120)
    # what jar_xm does not define: a note delay on a channel that never had a sample, a finetune below 8, an instrument's envelope
    # whose sustain point is past its 12 points
    out['delay-bare'] = xp.module([xp.pattern(4, xp.slots([(None, None, None, 0x0E, 0xD1)] + [rest] * 3))], made, channels=1, tempo=3)
    out['finetune-low'] = xp.module([xp.pattern(4, xp.slots([note(40), note(41, e=0x0E, p=0x53), rest, rest]))], made, channels=1, tempo=3)
    out['finetune-high'] = xp.module([xp.pattern(4, xp.slots([note(40), note(41, e=0x0E, p=0x5C), rest, rest]))], made, channels=1, tempo=3)
    out['sustain-past'] = xp.module([xp.pattern(4, xp.slots([note(40), rest, rest, rest]))],
                                    [xp.instrument([xp.sample(xp.deltas(rng, 100))], volume=xp.envelope([(0, 64), (5, 0)], sustain=40, flags=3))], channels=1, tempo=3)
    # a row past its pattern's rows after a break, and an order's entry that a jump reaches past the patterns
    out['break-past'] = xp.module([xp.pattern(4, xp.slots([note(40, e=0x0D, p=0x09), rest, rest, rest])), xp.pattern(4)], made, channels=1, order=(0, 1), tempo=3)
    return out


def cases(source):
    """name -> (module, calls)."""
    out = {
        # as raylib: the length, the reset, then the song
        'mini': (source, [OWN, RESET, 400]),
        # tick by tick past the song's end, and its length from there
        'mini-ticks': (source, [6100, OWN]),
        'mini-twice': (source, [100, RESET, 50, OWN, REMAINING, RESET, 60]),
    }
    for name, data in built().items():
        if name.startswith('tame'):
            out[name] = (data, [300, OWN, RESET, 100])
        elif name.startswith('all'):
            out[name] = (data, [400])
        else:
            out[name] = (data, [80, RESET, 40])
    out['flow-length'] = (out['flow'][0], [REMAINING, RESET, 30])
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('xm-player', args)
    libm = gradient_reference()
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files = cases((args.raylib_source / SOURCE).read_bytes())
    items = []
    for name, (data, calls) in files.items():
        if xp.model(data)[0] != 'loaded':
            raise ProbeFailure(f'xm-player: {name} is no module to play: {xp.model(data)}')
        (folder / f'{name}.xm').write_bytes(data)
        items.append((name, f'{WORK}/{name}.xm', calls))
    runs = '\n'.join(f'    {{ static const int ops[] = {{{", ".join(str(op) for op in calls)}}}; alone({json.dumps(str(ROOT / path))}, ops, {len(calls)}); }}' for _, path, calls in items)
    expected = [json.loads(line) for line in probe.native(NATIVE.replace('@RUNS@', runs), 'reference', extra_flags=FLAGS, link_raylib=False).splitlines()]
    if len(expected) != len(items):
        raise ProbeFailure(f'xm-player: the reference printed {len(expected)} rows for {len(items)} modules')
    rows = {name: row for (name, _, _), row in zip(items, expected)}
    undefined = sorted(name for name, row in rows.items() if row[-1] == -1)
    # what the modules are for: raylib's plays through and is 2974098 samples long; the tame ones play through; what is built to be
    # undefined is, and the modules of every effect play for a while (three of them 64 ticks or more) before they meet it
    if (rows['mini'][0] != 2974098 or any(rows[name][-1] == -1 for name in rows if name.startswith('mini') or name.startswith('tame') or name in ('flow', 'flow-length', 'finetune-high'))
            or any(rows[name][-1] != -1 for name in ('delay-bare', 'finetune-low', 'sustain-past', 'break-past')) or sum(1 for name in undefined if name.startswith('all')) < 2 or sum(1 for name, row in rows.items() if name.startswith('all') and len(row) >= 5) < 3):
        raise ProbeFailure(f'xm-player: the reference rows are not the ones this probe was written for: undefined {undefined}, mini {rows["mini"][:2]}')

    def render(selected, gpu):
        return PROGRAM.replace('LIBM', libm) + ''.join(
            f'    {"Unit <- " if k + 1 < len(selected) else ""}IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result, [{", ".join(str(op & 0xFFFFFFFF) for op in calls)}]))\n'
            for k, (_, path, calls) in enumerate(selected))

    def parse(text, selected):
        got = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(got) != len(selected):
            raise ValueError('xm-player: candidate output did not finish')
        return got

    lanes = probe.candidates(render, items, batch=8, parse=parse, timeout=1700)

    def describe(index):
        for got in lanes.values():
            a, b = expected[index], got[index]
            if a != b:
                at = next((k for k, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
                return f'{items[index][0]}: differs at {at} of {len(a)} (jar_xm ends {a[-2:]}, jonlib {b[-2:]})'
        return items[index][0]

    probe.compare(expected, lanes, describe=describe)
    probe.finish(modules=len(items), ticks=sum(op for _, _, calls in items for op in calls if op > 0), undefined=len(undefined), libm=libm)


if __name__ == '__main__':
    main()
