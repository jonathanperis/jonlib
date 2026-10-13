#!/usr/bin/env python3
"""Compare src/xm_module.bend with jar_xm's jar_xm_create_context_safe.

Reference. jar_xm.h as pinned raylib vendors it, included in the reference
program with its implementation: jar_xm_create_context_safe on a file's
bytes. A failure prints its code. A module prints rolling hashes of its
header and pattern order, of every slot of its patterns, and of its
instruments with their envelopes, samples and every float of the samples'
data, with the counts of samples and floats and how many bytes of the
player's row counts are inside jar_xm's block of memory. The program checks
the sizes of jar_xm's structures, which the port's account of that block
relies on.

jar_xm writes outside its arrays for some files and loops without end for
others. The probe's own model of the loader (model, below: the offsets, the
block's size and how far it is filled) says which: the reference is not run
on those, and the port must refuse each with the model's reason. For every
other file the model's verdict is held against the reference too.

Candidate. Xm.load of the same bytes: the same hashes.

The files: raylib's mini1111.xm, cut at seeded places and with seeded bytes
of its headers changed; and modules built here: packed, plain and missing
slots, slots one too many and bytes for a pattern without rows, a pattern
whose 16-bit byte counter wraps, 8- and 16-bit samples, stereo and looped,
with loop values past an int, odd lengths, envelopes of 12 and 13 points,
every vibrato type, instruments without samples, Amiga frequencies, header
sizes that move the patterns, pattern orders that are trimmed, wrong, 256
long, and empty, 255 and 256 channels, more than 16 MiB, and data that is no
module. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

import probekit
from probekit import ROOT, ProbeFailure
from vorbis_codebook_probe import Rng

SOURCE = 'examples/audio/resources/mini1111.xm'
WORK = '.build/xm-module-probe/cases'
FLAGS = ['-ffp-contract=off', '-D_DEFAULT_SOURCE', '-w']
LIMIT = 1 << 24
SIZES = {'context': 424, 'pattern': 16, 'instrument': 272, 'sample': 80, 'slot': 5, 'channel': 256}

NATIVE = r'''#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#define JAR_XM_IMPLEMENTATION
#include "external/jar_xm.h"
#include <stdio.h>

static unsigned fnv(unsigned h, unsigned v) { return (h ^ v)*16777619u; }
static unsigned bits(float x) { unsigned w; memcpy(&w, &x, 4); return w; }

static unsigned envelope(unsigned h, jar_xm_envelope_t *e)
{
    int i;
    for (i = 0; i < NUM_ENVELOPE_POINTS; i++) { h = fnv(h, e->points[i].frame); h = fnv(h, e->points[i].value); }
    h = fnv(h, e->num_points); h = fnv(h, e->sustain_point); h = fnv(h, e->loop_start_point); h = fnv(h, e->loop_end_point);
    h = fnv(h, e->enabled); h = fnv(h, e->sustain_enabled); h = fnv(h, e->loop_enabled);
    return h;
}

static void run(const char *path)
{
    unsigned char *data;
    size_t size;
    FILE *file = fopen(path, "rb");
    jar_xm_context_t *ctx = NULL;
    jar_xm_module_t *m;
    int ret, p, i, j;
    unsigned k, h = 2166136261u, samples = 0, floats = 0;
    if (!file) exit(2);
    fseek(file, 0, SEEK_END);
    size = (size_t)ftell(file);
    fseek(file, 0, SEEK_SET);
    data = (unsigned char *)malloc(size + 1);
    if (fread(data, 1, size, file) != size) exit(3);
    fclose(file);
    ret = jar_xm_create_context_safe(&ctx, (const char *)data, size, 48000);
    if (ret) { printf("[%d]\n", ret); free(data); return; }
    m = &ctx->module;
    h = fnv(h, m->length); h = fnv(h, m->restart_position); h = fnv(h, m->num_channels); h = fnv(h, m->num_patterns); h = fnv(h, m->num_instruments); h = fnv(h, (unsigned)m->frequency_type);
    h = fnv(h, ctx->default_tempo); h = fnv(h, ctx->default_bpm);
    for (i = 0; i < PATTERN_ORDER_TABLE_LENGTH; i++) h = fnv(h, m->pattern_table[i]);
    printf("[0, %u, ", h);
    for (p = 0; p < m->num_patterns; p++)
    {
        h = fnv(h, m->patterns[p].num_rows);
        for (k = 0; k < (unsigned)m->patterns[p].num_rows*m->num_channels; k++)
        {
            jar_xm_pattern_slot_t *s = m->patterns[p].slots + k;
            h = fnv(h, s->note); h = fnv(h, s->instrument); h = fnv(h, s->volume_column); h = fnv(h, s->effect_type); h = fnv(h, s->effect_param);
        }
    }
    printf("%u, ", h);
    for (i = 0; i < m->num_instruments; i++)
    {
        jar_xm_instrument_t *in = m->instruments + i;
        h = fnv(h, in->num_samples);
        for (j = 0; j < NUM_NOTES; j++) h = fnv(h, in->sample_of_notes[j]);
        h = envelope(h, &in->volume_envelope); h = envelope(h, &in->panning_envelope);
        h = fnv(h, (unsigned)in->vibrato_type); h = fnv(h, in->vibrato_sweep); h = fnv(h, in->vibrato_depth); h = fnv(h, in->vibrato_rate); h = fnv(h, in->volume_fadeout);
        for (j = 0; j < in->num_samples; j++)
        {
            jar_xm_sample_t *s = in->samples + j;
            h = fnv(h, (unsigned)s->bits); h = fnv(h, (unsigned)s->stereo); h = fnv(h, s->length); h = fnv(h, s->loop_start); h = fnv(h, s->loop_length); h = fnv(h, s->loop_end); h = fnv(h, bits(s->volume));
            h = fnv(h, (unsigned)(int)s->finetune); h = fnv(h, (unsigned)s->loop_type); h = fnv(h, bits(s->panning)); h = fnv(h, (unsigned)(int)s->relative_note);
            // the sample's floats: a stereo sample's are its first half
            for (k = 0; k < s->length; k++) h = fnv(h, bits(s->data[k]));
            samples++; floats += s->length;
        }
    }
    {
        size_t needed = jar_xm_get_memory_needed_for_context((const char *)data, size);
        long used = (long)((char *)ctx->row_loop_count - (char *)ctx);
        printf("%u, %u, %u, %ld]\n", h, samples, floats, (long)needed > used? (long)needed - used : 0);
    }
    jar_xm_free_context(ctx);
    free(data);
}

int main(void)
{
    // what the port's account of jar_xm's block of memory relies on
    if (sizeof(jar_xm_context_t) != SIZE_CONTEXT || sizeof(jar_xm_pattern_t) != SIZE_PATTERN || sizeof(jar_xm_instrument_t) != SIZE_INSTRUMENT || sizeof(jar_xm_sample_t) != SIZE_SAMPLE
        || sizeof(jar_xm_pattern_slot_t) != SIZE_SLOT || sizeof(jar_xm_channel_context_t) != SIZE_CHANNEL) return 8;
RUNS
    return 0;
}
'''
for _name, _size in SIZES.items():
    NATIVE = NATIVE.replace('SIZE_' + _name.upper(), str(_size))

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/xm_module.bend as Xm

def mix(+h: U32, +v: U32) -> U32:
  ((h .^. v) * 16777619 : U32)

def mixed(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, +rest}: mixed(rest, mix(h, x))

def flag(on: Bool) -> U32:
  match on:
    case True{}: 1
    case False{}: 0

def mixed.first(n: Nat, xs: +List<F32>, +h: U32) -> U32:
  match n xs:
    case 1n+k Con{+x, +rest}: mixed.first(k, rest, mix(h, F32.bits(x)))
    case _ _: h

def mixed.slots(slots: +List<Xm.Slot>, +h: U32) -> U32:
  match slots:
    case Nil{}: h
    case Con{Xm.Slot{+note, +instrument, +volume, +effect, +param}, +rest}: mixed.slots(rest, mix(mix(mix(mix(mix(h, note), instrument), volume), effect), param))

def mixed.patterns(patterns: +List<Xm.Pattern>, +h: U32) -> U32:
  match patterns:
    case Nil{}: h
    case Con{Xm.Pattern{+rows, +slots}, +rest}: mixed.patterns(rest, mixed.slots(slots, mix(h, rows)))

def mixed.points(points: +List<Xm.Point>, +h: U32) -> U32:
  match points:
    case Nil{}: h
    case Con{Xm.Point{+frame, +value}, +rest}: mixed.points(rest, mix(mix(h, frame), value))

def mixed.envelope(envelope: Xm.Envelope, +h: U32) -> U32:
  Xm.Envelope{+points, +count, +sustain, +loop_start, +loop_end, +enabled, +sustained, +looped} = envelope
  mix(mix(mix(mix(mix(mix(mix(mixed.points(points, h), count), sustain), loop_start), loop_end), flag(enabled)), flag(sustained)), flag(looped))

def mixed.samples(samples: +List<Xm.Sample>, +h: U32) -> U32:
  match samples:
    case Nil{}: h
    case Con{Xm.Sample{+bits, +stereo, +length, +loop_start, +loop_length, +loop_end, +volume, +finetune, +loop_type, +panning, +relative, +data}, +rest}:
      mixed.samples(rest, mixed.first(U32.to_nat(length), data, mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(h, bits), stereo), length), loop_start), loop_length), loop_end), F32.bits(volume)), finetune), loop_type),
        F32.bits(panning)), relative)))

def counted.samples(samples: +List<Xm.Sample>, +n: U32) -> U32:
  match samples:
    case Nil{}: n
    case Con{_, +rest}: counted.samples(rest, (n + 1 : U32))

def summed.samples(samples: +List<Xm.Sample>, +n: U32) -> U32:
  match samples:
    case Nil{}: n
    case Con{Xm.Sample{_, _, +length, _, _, _, _, _, _, _, _, _}, +rest}: summed.samples(rest, (n + length : U32))

def mixed.instruments(instruments: +List<Xm.Instrument>, +h: U32) -> U32:
  match instruments:
    case Nil{}: h
    case Con{Xm.Instrument{+notes, +volume, +panning, +vibrato_type, +vibrato_sweep, +vibrato_depth, +vibrato_rate, +fadeout, +samples}, +rest}:
      mixed.instruments(rest, mixed.samples(samples, mix(mix(mix(mix(mix(mixed.envelope(panning, mixed.envelope(volume, mixed(notes, mix(h, counted.samples(samples, 0))))), vibrato_type), vibrato_sweep), vibrato_depth),
        vibrato_rate), fadeout)))

def counted.all(instruments: +List<Xm.Instrument>, +n: U32) -> U32:
  match instruments:
    case Nil{}: n
    case Con{Xm.Instrument{_, _, _, _, _, _, _, _, +samples}, +rest}: counted.all(rest, (n + counted.samples(samples, 0) : U32))

def summed.all(instruments: +List<Xm.Instrument>, +n: U32) -> U32:
  match instruments:
    case Nil{}: n
    case Con{Xm.Instrument{_, _, _, _, _, _, _, _, +samples}, +rest}: summed.all(rest, summed.samples(samples, n))

def counted.patterns(patterns: +List<Xm.Pattern>, +n: U32) -> U32:
  match patterns:
    case Nil{}: n
    case Con{_, +rest}: counted.patterns(rest, (n + 1 : U32))

def counted.instruments(instruments: +List<Xm.Instrument>, +n: U32) -> U32:
  match instruments:
    case Nil{}: n
    case Con{_, +rest}: counted.instruments(rest, (n + 1 : U32))

def told.three(+first: U32, +second: U32, +third: U32, +instruments: +List<Xm.Instrument>, +room: U32) -> String:
  "[0, " ++ U32.show(first) ++ ", " ++ U32.show(second) ++ ", " ++ U32.show(third) ++ ", " ++ U32.show(counted.all(instruments, 0)) ++ ", " ++ U32.show(summed.all(instruments, 0)) ++ ", " ++ U32.show(room) ++ "]"

def told.two(+first: U32, +second: U32, +instruments: +List<Xm.Instrument>, +room: U32) -> String:
  told.three(first, second, mixed.instruments(instruments, second), instruments, room)

def told.one(+first: U32, +patterns: +List<Xm.Pattern>, +instruments: +List<Xm.Instrument>, +room: U32) -> String:
  told.two(first, mixed.patterns(patterns, first), instruments, room)

def told(module: Xm.Module) -> String:
  Xm.Module{+length, +restart, +channels, +frequency, +tempo, +bpm, +order, +patterns, +instruments, +room} = module
  told.one(mixed(order, mix(mix(mix(mix(mix(mix(mix(mix(2166136261, length), restart), channels), counted.patterns(patterns, 0)), counted.instruments(instruments, 0)), frequency), tempo), bpm)), patterns, instruments, room)

def shown(loaded: Xm.Loaded) -> String:
  match loaded:
    case Xm.Loaded{+module}: told(module)
    case Xm.Failed{+code}: "[" ++ U32.show(code) ++ "]"
    case Xm.Refused{+why}: "[-" ++ U32.show(why) ++ "]"

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(shown(Xm.load(bytes)))

def main() -> IO(Unit):
  do IO<Unit>:
'''


# -----------------------------------------------------------------------------
# Modules built here

def slots(values):
    """Packed slots: a slot is (note, instrument, volume, effect, parameter); None fields are left out of a packed slot, and a slot
    given as five ints with a note below 128 is written plain."""
    out = b''
    for slot in values:
        if None in slot or slot[0] >= 128:
            present = [value for value in slot if value is not None]
            out += bytes([0x80 | sum(1 << k for k, value in enumerate(slot) if value is not None)] + present)
        else:
            out += bytes(slot)
    return out


def pattern(rows, packed=b'', header=9, size=None):
    """A pattern: its header (its own length, the packing type, the rows and the packed size, which can be stated otherwise)."""
    return struct.pack('<IBHH', header, 0, rows, len(packed) if size is None else size) + bytes(header - 9) + packed


def envelope(points=(), sustain=0, loop=(0, 0), flags=0, count=None):
    return {'points': list(points), 'count': len(points) if count is None else count, 'sustain': sustain, 'loop': loop, 'flags': flags}


def sample(data=b'', wide=False, stereo=False, loop=0, start=0, span=0, volume=64, finetune=0, panning=128, relative=0, length=None):
    """A sample: its header's fields and its delta-coded data."""
    return {'data': bytes(data), 'length': len(data) if length is None else length, 'start': start, 'span': span, 'volume': volume, 'finetune': finetune,
            'flags': loop | (0x10 if wide else 0) | (0x20 if stereo else 0), 'panning': panning, 'relative': relative}


def instrument(samples=(), notes=None, volume=None, panning=None, vibrato=(0, 0, 0, 0), fadeout=0, header=None, sample_header=40, count=None):
    """An instrument: its header (29 bytes without samples, 263 with them, or as said), the sample headers and the samples' data."""
    size = (263 if samples or count else 29) if header is None else header
    out = bytearray(max(size, 243))
    struct.pack_into('<I', out, 0, size)
    out[4:26] = b'instrument'.ljust(22, b'\0')
    struct.pack_into('<H', out, 27, len(samples) if count is None else count)
    struct.pack_into('<I', out, 29, sample_header)
    out[33:129] = bytes(notes if notes is not None else [0] * 96)
    for base, counted, numbered, flagged, made in ((129, 225, 227, 233, volume or envelope()), (177, 226, 230, 234, panning or envelope())):
        for index, (frame, value) in enumerate(made['points'][:12]):
            struct.pack_into('<HH', out, base + 4 * index, frame, value)
        out[counted] = made['count']
        out[numbered], out[numbered + 1], out[numbered + 2] = made['sustain'], made['loop'][0], made['loop'][1]
        out[flagged] = made['flags']
    out[235:239] = bytes(vibrato)
    struct.pack_into('<H', out, 239, fadeout)
    out = bytes(out[:size])
    for made in samples:
        head = struct.pack('<IIIBbBBb', made['length'], made['start'], made['span'], made['volume'], made['finetune'], made['flags'], made['panning'], made['relative']) + b'\0' + b'sample'.ljust(22, b'\0')
        out += head[:sample_header].ljust(sample_header, b'\0')
    return out + b''.join(made['data'] for made in samples)


def module(patterns=(), instruments=(), channels=2, order=(0,), restart=0, flags=1, tempo=6, bpm=125, header=276, length=None, counts=None, version=0x0104, magic=b'Extended Module: ', mark=0x1A):
    """A module: the 60 bytes before its header, the header (its size, the order's length and restart, the channels, patterns and
    instruments, the flags, tempo and BPM, the order's 256 bytes), the patterns and the instruments."""
    counted = (len(patterns), len(instruments)) if counts is None else counts
    out = magic + b'built'.ljust(20, b' ') + bytes([mark]) + b'jonlib probe'.ljust(20, b' ') + struct.pack('<H', version)
    out += struct.pack('<IHHHHHHHH', header, len(order) if length is None else length, restart, channels, counted[0], counted[1], flags, tempo, bpm)
    out += (bytes(order) + bytes(256))[:256][:max(header - 20, 0)]
    return out.ljust(60 + header, b'\0')[:60 + max(header, 20)] + b''.join(patterns) + b''.join(instruments)


# -----------------------------------------------------------------------------
# The loader's model: what is refused, what fails

def model(data):
    """('failed', 1), ('refused', why) or ('loaded', room): jar_xm_create_context_safe's outcome as the port accounts for it."""
    size = len(data)

    def u8(at):
        return data[at] if at < size else 0

    def u16(at):
        return u8(at) | u8(at + 1) << 8

    def u32(at):
        return u16(at) | u16(at + 2) << 16

    def aligned(value):
        return (value + 15) & ~15

    if size < 60 or data[:17] != b'Extended Module: ' or data[37] != 0x1A or data[59] != 1 or data[58] != 4:
        return ('failed', 1)
    channels, patterns, instruments = u16(68), u16(70), u16(72)
    # jar_xm_get_memory_needed_for_context
    memory = aligned(aligned(patterns * 16) + instruments * 272) + 256 * u16(64)
    at = 60 + u32(60)
    for _ in range(patterns):
        memory += u16(at + 5) * channels * 5
        at += (u32(at) + u16(at + 7)) & 0xFFFFFFFF
    memory = aligned(memory)
    for _ in range(instruments):
        if memory > LIMIT:
            break
        count = u16(at + 27)
        memory += count * 80
        step = u32(at + 29) if count else 0
        at += u32(at)
        total = 0
        if memory > LIMIT:
            break
        for _ in range(count):
            length = u32(at)
            total = (total + length) & 0xFFFFFFFF
            memory += length * (2 if u8(at + 14) & 0x10 else 4)
            at += step
            if memory > LIMIT:
                break
        at += total
    memory += channels * 256 + 424
    if memory > LIMIT:
        return ('refused', 4)
    # jar_xm_load_module
    pool = aligned(aligned(424 + patterns * 16) + instruments * 272)
    at = 60 + u32(60)
    for _ in range(patterns):
        rows, packed = u16(at + 5), u16(at + 7)
        count = channels * rows
        # slots past the block (a pattern without slots writes none)
        if count and pool + count * 5 > memory:
            return ('refused', 1)
        pool += count * 5
        at += u32(at)
        j = k = 0
        while j < packed:
            if k >= count:
                return ('refused', 1)
            note = u8(at + j)
            j += 1 + sum(1 for bit in range(5) if note >> bit & 1) if note & 0x80 else 5
            k += 1
            if j > 65535:
                return ('refused', 4)
        at += packed
    pool = aligned(pool)
    for _ in range(instruments):
        count = u16(at + 27)
        if count:
            if u8(at + 225) > 12 or u8(at + 226) > 12 or pool + count * 80 > memory:
                return ('refused', 1)
            pool += count * 80
        step = u32(at + 29) if count else 0
        at += u32(at)
        lengths = []
        for _ in range(count):
            length, wide = u32(at), u8(at + 14) & 0x10
            pool += length * (2 if wide else 4)
            lengths.append(length >> 1 << 1 if wide else length)
            at += step
        if pool > memory:
            return ('refused', 1)
        at += sum(lengths)
    pool = aligned(pool) + channels * 256
    if channels >= 256:
        return ('refused', 2)
    if channels and pool > memory:
        return ('refused', 1)
    # jar_xm_check_sanity_postload, its counter a byte
    length = u16(64)
    for i in range(256):
        if i >= length:
            return ('loaded', max(memory - pool, 0))
        if u8(80 + i) >= patterns:
            if i + 1 == length and length > 1:
                length -= 1
            else:
                return ('failed', 1)
    # the counter is a byte again at 0: with 256 entries or more left it never passes them
    return ('refused', 2) if length > 255 else ('loaded', max(memory - pool, 0))


# -----------------------------------------------------------------------------
# The files

def deltas(rng, count, wide=False):
    """Seeded data of a sample: bytes whose running sums pass the ends of an int8 or an int16."""
    return bytes(rng.next(256) for _ in range(count * (2 if wide else 1)))


def built():
    """name -> module."""
    rng = Rng(0x0A11CE)
    whole = [(49, 1, 0x40, 0x0F, 0x06), (None, None, None, None, None), (60, None, None, None, None), (None, 2, None, 0x04, 0x37), (97, None, 0x10, None, None), (None, None, None, 0x0E, 0xC3),
             (0x7F, 0xFF, 0xFF, 0xFF, 0xFF), (1, 0, 0, 0, 0)]
    one = instrument([sample(deltas(rng, 40), loop=1, start=8, span=32)], notes=[0] * 96, volume=envelope([(0, 64), (10, 0)], flags=1), fadeout=1024)
    points = [(k * 7, (k * 13) % 65) for k in range(12)]
    out = {
        'tiny': module([pattern(1)], channels=1),
        'slots': module([pattern(4, slots(whole))], [one]),
        # no bytes at all, fewer slots than the pattern has, and exactly as many
        'slots-none': module([pattern(64)], channels=8),
        'slots-short': module([pattern(4, slots(whole[:3]))]),
        'slots-exact': module([pattern(2, slots(whole[:4]))]),
        # one slot more than the pattern has, and bytes for a pattern without rows: writes past the slots
        'slots-over': module([pattern(2, slots(whole[:5]))]),
        'slots-rowless': module([pattern(0, slots(whole[:1]))]),
        # a packed slot whose bytes are past the packed size: they are read all the same
        'slots-cut': module([pattern(2, slots(whole[:1]) + b'\x9f\x31', size=6), pattern(1, slots(whole[:1]))], order=(0, 1)),
        # 65534 slots of one byte and a plain one: the byte count passes 65535
        'slots-wrap': module([pattern(2048, b'\x80' * 65534 + b'\x31\x01\x02\x03\x04', size=65535)], channels=32),
        'slots-full': module([pattern(2048, b'\x80' * 65535)], channels=32),
        'rows-256': module([pattern(256, slots(whole * 8)), pattern(3, slots(whole[:6]))], channels=3, order=(1, 0, 1)),
        'pattern-header': module([pattern(2, slots(whole[:4]), header=20), pattern(1, slots(whole[:2]), header=9)], order=(0, 1)),
        # samples
        'sixteen': module([pattern(1)], [instrument([sample(deltas(rng, 50, wide=True), wide=True, loop=1, start=20, span=60)])]),
        'sixteen-odd': module([pattern(1)], [instrument([sample(deltas(rng, 10, wide=True) + b'\x55', wide=True)]), one]),
        'stereo': module([pattern(1)], [instrument([sample(deltas(rng, 60), stereo=True), sample(deltas(rng, 31), stereo=True, loop=1, start=7, span=21)])]),
        'stereo-sixteen': module([pattern(1)], [instrument([sample(deltas(rng, 40, wide=True), wide=True, stereo=True, loop=2, start=10, span=50), sample(deltas(rng, 9, wide=True), wide=True, stereo=True)])]),
        'ping-pong': module([pattern(1)], [instrument([sample(deltas(rng, 20), loop=2, start=3, span=9), sample(deltas(rng, 20), loop=3, start=3, span=9)])]),
        # loop values past an int: halved as ints for a stereo sample, shifted for a 16-bit one
        'loop-large': module([pattern(1)], [instrument([sample(deltas(rng, 12), stereo=True, loop=1, start=0x80000003, span=0xFFFFFFFF), sample(deltas(rng, 12, wide=True), wide=True, loop=1, start=0xFFFFFFF0, span=0x31),
                                                        sample(deltas(rng, 12), loop=1, start=0xFFFFFFF0, span=0x31), sample(deltas(rng, 8, wide=True), wide=True, stereo=True, loop=1, start=0x80000001, span=0x7FFFFFFF)])]),
        'volumes': module([pattern(1)], [instrument([sample(deltas(rng, 4), volume=volume, finetune=finetune, panning=panning, relative=relative)
                                                     for volume, finetune, panning, relative in ((0, 0, 0, 0), (63, -128, 255, -128), (64, 127, 1, 127), (65, -1, 254, -1), (255, 5, 77, 96))])]),
        'many-samples': module([pattern(1)], [instrument([sample(deltas(rng, 3 + k)) for k in range(16)], notes=[k % 16 for k in range(96)]), instrument(), one]),
        'sample-header': module([pattern(1)], [instrument([sample(deltas(rng, 9)), sample(deltas(rng, 5))], sample_header=18), instrument([sample(deltas(rng, 7))], sample_header=64)]),
        'instrument-header': module([pattern(1)], [instrument([sample(deltas(rng, 9))], header=300), instrument(header=40), one]),
        # envelopes
        'envelopes': module([pattern(1)], [instrument([sample(deltas(rng, 5))], volume=envelope(points, sustain=3, loop=(2, 9), flags=7), panning=envelope(points[::-1], sustain=11, loop=(0, 11), flags=5)),
                                            instrument([sample(deltas(rng, 5))], volume=envelope(points[:3], flags=2), panning=envelope((), sustain=200, loop=(100, 250), flags=0xFF))]),
        'envelope-13': module([pattern(1)], [instrument([sample(deltas(rng, 5))], volume=envelope(points, count=13))]),
        'envelope-pan-255': module([pattern(1)], [one, instrument([sample(deltas(rng, 5))], panning=envelope(points, count=255))]),
        'vibratos': module([pattern(1)], [instrument([sample(deltas(rng, 4))], vibrato=(kind, (10 + kind) & 255, (20 + kind) & 255, (30 + kind) & 255), fadeout=(1000 * kind) & 65535) for kind in (0, 1, 2, 3, 4, 9, 255)]),
        # the header
        'amiga': module([pattern(2, slots(whole[:4]))], [one], flags=0, tempo=3, bpm=240, restart=1),
        'flags-high': module([pattern(1)], flags=0xFFFE),
        # a header shorter than the order: the patterns begin inside it; and a longer one
        'header-short': module([pattern(1)], header=22, order=(0, 0)),
        'header-long': module([pattern(1, slots(whole[:2]))], [one], header=300, order=(0, 0, 0)),
        # the order
        'order-trimmed': module([pattern(1), pattern(2)], order=(1, 0, 1, 9)),
        'order-wrong': module([pattern(1), pattern(2)], order=(1, 9, 0)),
        'order-one-wrong': module([pattern(1)], order=(3,)),
        'order-none': module([pattern(1)], order=(), length=0),
        'order-none-silent': module([pattern(1)], order=(), length=0, channels=0),
        'order-255': module([pattern(1)], order=[0] * 255),
        'order-256': module([pattern(1)], order=[0] * 256, length=256),
        'order-256-trimmed': module([pattern(1)], order=[0] * 255 + [7], length=256),
        'order-300': module([pattern(1)], order=[0] * 256, length=300),
        'order-300-wrong': module([pattern(1)], order=[0] * 100 + [5] + [0] * 155, length=300),
        # the channels
        'channels-none': module([pattern(3)], channels=0),
        'channels-255': module([pattern(2, slots(whole * 4))], channels=255),
        'channels-256': module([pattern(1)], channels=256),
        # counts past what the file has: the rest is read as zeros
        'patterns-stated': module([pattern(1, slots(whole[:2]))], counts=(40, 3)),
        'instruments-stated': module([pattern(1)], [one], counts=(1, 500)),
        # more than 16 MiB
        'large-sample': module([pattern(1)], [instrument([sample(b'', length=5000000)])]),
        'large-pattern': module([pattern(60000, size=0)], channels=64),
        # no module
        'magic': module([pattern(1)], magic=b'Extended module: '),
        'mark': module([pattern(1)], mark=0x1B),
        'version': module([pattern(1)], version=0x0103),
        'short': module([pattern(1)])[:59],
        'sixty': module([pattern(1)])[:60],
        'empty': b'',
    }
    return out


def cases(source):
    """name -> bytes: raylib's module, its cuts, its changed bytes, and the modules built here."""
    out = {'mini': source}
    rng = Rng(0x7A0D)
    for index in range(10):
        cut = [61, 80, 200, 336, 340][index] if index < 5 else 336 + rng.next(len(source) - 336)
        out[f'cut-{cut}'] = source[:cut]
    for index in range(24):
        data = bytearray(source)
        # the module's header, and anywhere after it: a pattern's or an instrument's header, or the bytes between
        at = 60 + rng.next(20) if index < 8 else 336 + rng.next(len(source) - 336)
        data[at] = rng.next(256) if index % 2 else data[at] ^ 1 << rng.next(8)
        out[f'byte-{index}'] = bytes(data)
    out.update(built())
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('xm-module', args)
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files = cases((args.raylib_source / SOURCE).read_bytes())
    items, verdicts = [], {}
    for name, data in files.items():
        (folder / f'{name}.xm').write_bytes(data)
        items.append((name, f'{WORK}/{name}.xm'))
        verdicts[name] = model(data)
    native = [(name, path) for name, path in items if verdicts[name][0] != 'refused']
    runs = '\n'.join(f'    run({json.dumps(str(ROOT / path))});' for _, path in native)
    printed = [json.loads(line) for line in probe.native(NATIVE.replace('RUNS', runs), 'reference', extra_flags=FLAGS, link_raylib=False).splitlines()]
    if len(printed) != len(native):
        raise ProbeFailure(f'xm-module: the reference printed {len(printed)} rows for {len(native)} files')
    rows = {name: row for (name, _), row in zip(native, printed)}
    # the model against jar_xm itself: what it says fails, fails with that code, and what it says loads, loads with as much room
    for name, row in rows.items():
        kind, value = verdicts[name]
        if (kind == 'failed') != (len(row) == 1) or (kind == 'failed' and row != [value]) or (kind == 'loaded' and row[-1] != value):
            raise ProbeFailure(f'xm-module: the model says {name} is {kind} {value}, and jar_xm {row[:1] + row[-1:]}')
    expected = [rows[name] if name in rows else [-verdicts[name][1]] for name, _ in items]
    kinds = {name: verdicts[name] for name in files}
    refused = sorted(name for name, (kind, _) in kinds.items() if kind == 'refused')
    wanted = {'slots-over': 1, 'slots-rowless': 1, 'slots-wrap': 4, 'envelope-13': 1, 'envelope-pan-255': 1, 'order-256': 2, 'order-300': 2, 'order-none': 1, 'channels-256': 2, 'large-sample': 4, 'large-pattern': 4}
    # what the corpus is for
    if (rows['mini'][-3:] != [8, 9520, 2552] or any(kinds[name] != ('refused', why) for name, why in wanted.items()) or any(kinds[name] != ('failed', 1) for name in
            ('magic', 'mark', 'version', 'short', 'empty', 'order-wrong', 'order-one-wrong', 'order-300-wrong'))
            or any(kinds[name][0] != 'loaded' for name in ('tiny', 'slots', 'slots-full', 'loop-large', 'order-trimmed', 'order-256-trimmed', 'order-none-silent', 'channels-255', 'header-short', 'sixty'))
            or sum(1 for kind, _ in kinds.values() if kind == 'loaded') < 50):
        raise ProbeFailure(f'xm-module: the files are not the ones this probe was written for: {kinds}')

    def render(selected, gpu):
        return PROGRAM + ''.join(
            f'    {"Unit <- " if k + 1 < len(selected) else ""}IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result))\n' for k, (_, path) in enumerate(selected))

    def parse(text, selected):
        got = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(got) != len(selected):
            raise ValueError('xm-module: candidate output did not finish')
        return got

    lanes = probe.candidates(render, items, batch=12, parse=parse, timeout=1700)
    probe.compare(expected, lanes, describe=lambda index: f'{items[index][0]} ({verdicts[items[index][0]]})')
    probe.finish(files=len(items), loaded=sum(1 for kind, _ in kinds.values() if kind == 'loaded'), failed=sum(1 for kind, _ in kinds.values() if kind == 'failed'), refused=len(refused),
                 floats=sum(row[-2] for row in printed if len(row) > 1))


if __name__ == '__main__':
    main()
