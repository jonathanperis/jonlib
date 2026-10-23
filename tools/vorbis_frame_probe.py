#!/usr/bin/env python3
"""Compare src/vorbis_frame.bend with stb_vorbis's frames and samples.

Reference. stb_vorbis.c as pinned raylib vendors it, included in the
reference program: stb_vorbis_open_memory on a stream, then a script of
calls, each stb_vorbis_get_frame_float or
stb_vorbis_get_samples_short_interleaved for the stream's own channels and
some count of shorts. After each call its answer and the shorts it wrote are
hashed with everything the decoder keeps: the reader, the sample position,
every float of the channels' buffers, the previous window and its length,
where the samples at hand are and how many the frames have given; and, as
the stream is opened, its sample rate and where its audio begins. A run
prints the rolling hash after each call and how it ends.

A second decoder runs each read first with the function's own loop written
out in the program, looking at each float where it would be converted: a
NaN, or a float whose conversion overflows an int, ends the run with -1 (the
function is not called on it), and the port must refuse in the same call.
The two decoders must agree after every call, which holds the loop written
out against the function. A table of floats is converted one by one by
convert_channels_short_interleaved, the same floats left out.

Candidate. Fr.memory.open of the same file under the host's libm profile,
then Fr.frame.float and Fr.samples.read by the script; Fr.sample.short and
Fr.sample.refused for the table.

The files: raylib's target.ogg read whole as LoadWave reads it and in a
music stream's steps, copies cut inside its audio pages and copies with
seeded damage in its packets' bytes; and streams built here of one channel
with blocks of 64 and 256 samples, a floor of two points and a residue of
type 1 whose codebook's values are 0, 1 and a chosen loudness either way:
quiet ones (samples near the steps of a short), loud ones (samples kept to a
short's range), a louder one whose samples are refused, long and short
blocks whose windows do not agree, last pages whose positions cut the last
block short, before its start and not at all, pages after such a last
page, where no window fits what the cut block left, and audio packets on
the setup's page. CPU-1, CPU-2 and JavaScript
lanes.
"""
import json
import struct

from conformance import gradient_reference
import probekit
from probekit import ROOT, ProbeFailure
from vorbis_codebook_probe import Rng
from vorbis_ogg_probe import page
from vorbis_packet_probe import bodies
import vorbis_setup_probe as sp

SOURCE = 'examples/audio/resources/target.ogg'
WORK = '.build/vorbis-frame-probe/cases'
FLAGS = ['-ffp-contract=off', '-D_DEFAULT_SOURCE', '-Wno-everything']
MOST = 1 << 20

NATIVE = r'''#include "external/stb_vorbis.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned fnv(unsigned h, unsigned v) { return (h ^ v)*16777619u; }

static unsigned digest(stb_vorbis *f)
{
    unsigned h = 2166136261u;
    int i, j;
    h = fnv(h, (unsigned)(f->stream - f->stream_start)); h = fnv(h, f->eof != 0); h = fnv(h, (unsigned)f->error);
    h = fnv(h, f->page_flag); h = fnv(h, (unsigned)f->segment_count);
    for (i = 0; i < 255; i++) h = fnv(h, f->segments[i]);
    h = fnv(h, (unsigned)f->next_seg); h = fnv(h, (unsigned)f->last_page); h = fnv(h, (unsigned)f->end_seg_with_known_loc); h = fnv(h, f->known_loc_for_packet);
    h = fnv(h, f->first_decode != 0); h = fnv(h, f->p_first.page_start); h = fnv(h, f->p_first.page_end); h = fnv(h, f->p_first.last_decoded_sample);
    h = fnv(h, f->bytes_in_seg); h = fnv(h, f->last_seg != 0); h = fnv(h, (unsigned)f->last_seg_which); h = fnv(h, (unsigned)f->packet_bytes);
    h = fnv(h, f->acc); h = fnv(h, (unsigned)f->valid_bits);
    h = fnv(h, f->current_loc); h = fnv(h, f->current_loc_valid != 0); h = fnv(h, (unsigned)f->discard_samples_deferred);
    for (j = 0; j < f->channels; j++) for (i = 0; i < f->blocksize_1; i++) { unsigned w; memcpy(&w, &f->channel_buffers[j][i], 4); h = fnv(h, w); }
    h = fnv(h, (unsigned)f->previous_length); h = fnv(h, (unsigned)f->channel_buffer_start); h = fnv(h, (unsigned)f->channel_buffer_end); h = fnv(h, f->samples_output);
    // the previous window holds previous_length floats: the rest is not written yet, or is an older frame's
    for (j = 0; j < f->channels; j++) for (i = 0; i < f->previous_length; i++) { unsigned w; memcpy(&w, &f->previous_window[j][i], 4); h = fnv(h, w); }
    return h;
}

// Whether FAST_SCALED_FLOAT_TO_INT(temp, x, 15) is undefined or a machine's own: its int subtraction overflows, or x is a NaN,
// whose sign the conversion goes by.
static int bad(float x)
{
    volatile float sum = x + 384.0f;
    float held = sum;
    unsigned w;
    memcpy(&w, &held, 4);
    return x != x || (w >= 0x80000000u && w <= 0xC3BFFFFFu);
}

// The loop of stb_vorbis_get_samples_short_interleaved, each float looked at where it would be converted: 0 where one is bad.
static int clean(stb_vorbis *f, int channels, int num_shorts)
{
    float **outputs;
    int len = num_shorts/channels, n = 0, i, j;
    while (n < len)
    {
        int k = f->channel_buffer_end - f->channel_buffer_start;
        if (n + k >= len) k = len - n;
        for (j = 0; j < k; j++) for (i = 0; i < f->channels; i++) if (bad(f->channel_buffers[i][f->channel_buffer_start + j])) return 0;
        n += k;
        f->channel_buffer_start += k;
        if (n == len) break;
        if (!stb_vorbis_get_frame_float(f, NULL, &outputs)) break;
    }
    return 1;
}

static short shorts[MOST];

static void run(const char *path, const int *ops, int count)
{
    unsigned char *data;
    int k, len, error = 0, total = 0, frames = 0;
    unsigned roll = 2166136261u;
    stb_vorbis *f, *shadow;
    FILE *file = fopen(path, "rb");
    if (!file) exit(2);
    fseek(file, 0, SEEK_END);
    len = (int)ftell(file);
    fseek(file, 0, SEEK_SET);
    data = (unsigned char *)malloc(len? len : 1);
    if (fread(data, 1, len, file) != (size_t)len) exit(3);
    fclose(file);
    f = stb_vorbis_open_memory(data, len, &error, NULL);
    if (!f) { printf("[%d]\n", error); free(data); return; }
    shadow = stb_vorbis_open_memory(data, len, &error, NULL);
    if (!shadow) exit(4);
    roll = fnv(roll, digest(f)); roll = fnv(roll, f->sample_rate); roll = fnv(roll, f->first_audio_page_offset);
    printf("[%u, ", roll);
    for (k = 0; k < count; k++)
    {
        int got, i;
        if (ops[k] == 0)
        {
            float **outputs;
            got = stb_vorbis_get_frame_float(f, NULL, &outputs);
            if (stb_vorbis_get_frame_float(shadow, NULL, &outputs) != got) exit(5);
            roll = fnv(roll, (unsigned)got);
            frames += got != 0;
        }
        else
        {
            if (ops[k] > MOST) exit(6);
            if (!clean(shadow, f->channels, ops[k])) { printf("-1]\n"); goto done; }
            got = stb_vorbis_get_samples_short_interleaved(f, f->channels, shorts, ops[k]);
            roll = fnv(roll, (unsigned)got);
            for (i = 0; i < got*f->channels; i++) roll = fnv(roll, (unsigned short)shorts[i]);
            total += got;
        }
        roll = fnv(roll, digest(f));
        // the loop written out is the function's
        if (digest(shadow) != digest(f)) exit(7);
        printf("%u, ", roll);
    }
    printf("%d, %d, %u, %u, %u]\n", total, frames, (unsigned)f->error, (unsigned)(f->eof != 0), f->samples_output);
done:
    stb_vorbis_close(f);
    stb_vorbis_close(shadow);
    free(data);
}

// convert_channels_short_interleaved on one channel of one sample: a float's short, or -1 where it is not converted
static void floats(const unsigned *words, int count)
{
    int i;
    printf("[");
    for (i = 0; i < count; i++)
    {
        float x, *data = &x;
        short out = 0;
        memcpy(&x, &words[i], 4);
        if (bad(x)) printf("-1%s", i + 1 < count? ", " : "");
        else { convert_channels_short_interleaved(1, &out, 1, &data, 0, 1); printf("%u%s", (unsigned)(unsigned short)out, i + 1 < count? ", " : ""); }
    }
    printf("]\n");
}

int main(void)
{
    float magic = MAGIC(15);
    unsigned w;
    memcpy(&w, &magic, 4);
    // what the port takes the macro to be
    if (w != 0x43C00000u || (unsigned)ADDEND(15) != 0x43C00000u) return 8;
    {
        static const unsigned words[] = {WORDS};
        floats(words, (int)(sizeof(words)/sizeof(words[0])));
    }
RUNS
    return 0;
}
'''.replace('MOST', str(MOST))

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/vorbis_ogg.bend as V
import ../../src/vorbis_codebook.bend as C
import ../../src/vorbis_setup.bend as S
import ../../src/vorbis_packet.bend as K
import ../../src/vorbis_frame.bend as Fr
import ../../src/store.bend as R

def mix(+h: U32, +v: U32) -> U32:
  ((h .^. v) * 16777619 : U32)

def mixed(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, +rest}: mixed(rest, mix(h, x))

def mixed.floats(xs: +List<F32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, +rest}: mixed.floats(rest, mix(h, F32.bits(x)))

def mixed.first(n: Nat, xs: +List<F32>, +h: U32) -> U32:
  match n xs:
    case 1n+k Con{+x, +rest}: mixed.first(k, rest, mix(h, F32.bits(x)))
    case _ _: h

def mixed.rows(rows: +List<R.Row>, +h: U32) -> U32:
  match rows:
    case Nil{}: h
    case Con{+row, +rest}: mixed.rows(rest, mixed.floats(R.Row.list(row), h))

# The previous window's floats, as many as its length says.
def mixed.previous(rows: +List<R.Row>, +count: U32, +h: U32) -> U32:
  match rows:
    case Nil{}: h
    case Con{+row, +rest}: mixed.previous(rest, count, mixed.first(U32.to_nat(count), R.Row.list(row), h))

def flag(on: Bool) -> U32:
  match on:
    case True{}: 1
    case False{}: 0

# Everything the reader keeps.
def digest.reader(reader: V.Reader) -> U32:
  match reader:
    case V.Reader{V.Stream{_, _, +at, _, +eof}, V.Page{+bits, +count, +segments, +next, +sequence, +known_seg, +known_loc}, V.First{+decoding, +start, +end, +sample}, V.Packet{+in_seg, +last, +which, +bytes, +acc, +valid}, +error, _, _}:
      mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mixed(segments, mix(mix(mix(mix(mix(2166136261, at), flag(eof)), error), bits), count)), next), sequence), known_seg), known_loc), flag(decoding)), start), end), sample), in_seg),
        flag(last)), which), bytes), acc), valid)

# ... the sample position and the channels' floats.
def digest.state(state: K.State) -> U32:
  match state:
    case K.State{+reader, +rows, +loc, +known, +discard}: mixed.rows(rows, mix(mix(mix(digest.reader(reader), loc), flag(known)), discard))

# ... the previous window and its length, where the samples at hand are and how many the frames have given.
def digest(frames: Fr.Frames) -> U32:
  match frames:
    case Fr.Frames{+state, +previous, +length, +start, +end, +output}:
      mixed.previous(previous, Bool.pick(U32, K.under(length, 1), 0, length), mix(mix(mix(mix(digest.state(state), length), start), end), output))

type Run is Data:
  Run{frames: Fr.Frames, roll: U32, total: U32, count: U32}

def Run.frames(run: Run) -> Fr.Frames:
  Run{frames, _, _, _} = run
  frames

def Run.roll(run: Run) -> U32:
  Run{_, roll, _, _} = run
  roll

def Run.total(run: Run) -> U32:
  Run{_, _, total, _} = run
  total

def Run.count(run: Run) -> U32:
  Run{_, _, _, count} = run
  count

def stepped.frame(got: Fr.Got, +roll: U32, +total: U32, +count: U32) -> Run:
  Fr.Got{+frames, +value} = got
  Run{frames, mix(mix(roll, value), digest(frames)), total, (count + flag(U32.is_ne(value, 0)) : U32)}

def stepped.read(read: Fr.Read, +roll: U32, +total: U32, +count: U32) -> Run:
  Fr.Read{+frames, +n, +samples, _} = read
  Run{frames, mix(mixed(samples, mix(roll, n)), digest(frames)), (total + n : U32), count}

# A call: stb_vorbis_get_frame_float for 0, otherwise stb_vorbis_get_samples_short_interleaved for that many shorts.
def step(frame: Bool, +op: U32, +plan: K.Plan, +run: Run) -> Run:
  match frame:
    case True{}: stepped.frame(Fr.frame.float(plan, Run.frames(run)), Run.roll(run), Run.total(run), Run.count(run))
    case False{}: stepped.read(Fr.samples.read(plan, Run.frames(run), op), Run.roll(run), Run.total(run), Run.count(run))

def ending(run: Run, +out: String) -> String:
  Run{+frames, _, +total, +count} = run
  out ++ U32.show(total) ++ ", " ++ U32.show(count) ++ ", " ++ U32.show(V.Reader.error(Fr.Frames.reader(frames))) ++ ", " ++ U32.show(flag(V.Stream.eof(V.Reader.stream(Fr.Frames.reader(frames))))) ++ ", " ++ U32.show(Fr.Frames.output(frames)) ++ "]"

# The calls in turn: the rolling hash after each, and the end; -1 where a call is refused.
def run(ops: +List<U32>, on: Bool, +plan: K.Plan, +state: Run, +out: String) -> String:
  match ops on:
    case _ False{}: out ++ "-1]"
    case Nil{} True{}: ending(state, out)
    case Con{+op, +rest} True{}:
      +next = step(U32.is_eq(op, 0), op, plan, state)
      +fine = Bool.not(Fr.Frames.refused(Run.frames(next)))
      run(rest, fine, plan, next, Bool.pick(String, fine, out ++ U32.show(Run.roll(next)) ++ ", ", out))

def opened(started: Fr.Started, +ops: +List<U32>) -> String:
  match started:
    case Fr.Unready{S.Failed{+code}}: "[" ++ U32.show(code) ++ "]"
    case Fr.Unready{_}: "[-2]"
    case Fr.Opened{+plan, +frames, +rate, +first}:
      run(ops, Bool.not(Fr.Frames.refused(frames)), plan, Run{frames, mix(mix(mix(2166136261, digest(frames)), rate), first), 0, 0}, "[" ++ U32.show(mix(mix(mix(2166136261, digest(frames)), rate), first)) ++ ", ")

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>, +ops: +List<U32>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(opened(Fr.memory.open(M.LIBM{}, bytes), ops))

def converted(+x: F32) -> String:
  Bool.pick(String, Fr.sample.refused(x), "-1", U32.show(Fr.sample.short(x)))

# A table of floats, each as its short; -1 for one that is refused.
def floats(words: +List<U32>, +first: Bool, +out: String) -> String:
  match words:
    case Nil{}: out ++ "]"
    case Con{+w, +rest}: floats(rest, False{}, out ++ Bool.pick(String, first, "", ", ") ++ converted(C.float.word(w)))

def main() -> IO(Unit):
  do IO<Unit>:
'''


# -----------------------------------------------------------------------------
# Streams built here

def packed(value):
    """An integer as a Vorbis float (float32_unpack reads it back)."""
    return (0x80000000 if value < 0 else 0) | 788 << 21 | abs(value)


def headers(loud, more=()):
    """One channel at 8000 Hz, blocks of 64 and 256: a floor of two points, a residue of type 1 over 32 values in partitions of 8
    whose codebook's four scalars are 0, -loud, loud and 1, and a mode for each block size. `more` are packets on the setup's page."""
    books = [sp.book(1, [1, 1]), sp.book(1, [2, 2, 2, 2], lookup=(1, packed(-loud), packed(1), 11, False, [loud, 0, 2 * loud, loud + 1]))]
    third = sp.whole(books=books, floors=[sp.floor(rangebits=5)], residues=[sp.residue(kind=1, begin=0, end=32, part_size=8, classbook=0, cascades=(1,), books=(1,))],
                     mappings=[sp.mapping(channels=1)], modes=[sp.mode(0), sp.mode(1)])
    return sp.stream(first=sp.identification(channels=1, rate=8000, small=6, large=8), packets=[sp.comment(), third] + list(more))


def packet(long, spectrum, before=1, after=1, y=(255, 255)):
    """An audio packet: its mode, a long block's two flags, the floor's two points and 32 values, each 0 (nothing), 1 (-loud),
    2 (loud) or 3 (1)."""
    w = sp.Writer()
    w.put(0, 1).put(1 if long else 0, 1)
    if long:
        w.put(before, 1).put(after, 1)
    w.put(1, 1).put(y[0], 8).put(y[1], 8)
    for part in range(4):
        w.put(0, 1)
        for entry in spectrum[8 * part:8 * part + 8]:
            w.put(entry >> 1, 1).put(entry & 1, 1)
    return w.bytes()


def audio(groups, granules, first=2, last=None):
    """A page for each group of packets, at its granule position; the last one is flagged as the stream's last (or page `last`)."""
    out = b''
    for index, (group, granule) in enumerate(zip(groups, granules)):
        out += page(4 if index == (len(groups) - 1 if last is None else last) else 0, granule, first + index, [len(data) for data in group], body=b''.join(group))
    return out


def one(at, entry=2):
    return [entry if k == at else 0 for k in range(32)]


def blocks(dense=None):
    """Two pages of packets: short and long blocks whose flags agree with their neighbours, `dense` one whose values are all loud."""
    return [[packet(0, one(1)), packet(0, one(2)), packet(1, one(3), before=0, after=1), packet(1, one(5, 1)), packet(1, one(0), after=0), packet(0, one(7))],
            [packet(0, one(4, 3)), packet(1, [2, 1] * 16 if dense is None else dense, before=0, after=0), packet(0, one(9)), packet(0, [0] * 32)]]


def built():
    """name -> stream."""
    quiet = [3 if k % 3 == 0 else 0 for k in range(32)]
    out = {
        # samples of a few units: every one is past a short's range
        'loud': headers(5) + audio(blocks(), [500, 800]),
        # ... and of some hundreds, where the dense block's are refused
        'louder': headers(20) + audio(blocks(), [500, 800]),
        # ... with the dense block left quiet: nothing refused, samples far past the range both ways
        'louder-thin': headers(150) + audio(blocks(one(6)), [500, 800]),
        # samples about a short's steps: the values are 1s
        'quiet': headers(5) + audio([[packet(0, quiet), packet(1, one(2, 3), before=0, after=1), packet(1, quiet), packet(0, one(31, 3)), packet(0, quiet)]], [400]),
        # the last page's position cuts the last block short, is before the block, and is unknown
        'cut-short': headers(5) + audio(blocks(), [500, 700]),
        'cut-before': headers(5) + audio(blocks(), [500, 300]),
        'cut-unknown': headers(5) + audio(blocks(), [500, 0xFFFFFFFFFFFFFFFF]),
        # a long block that says a long one follows, and a short one does: the long window over the short block and past it
        'long-window': headers(5) + audio([[packet(0, one(1)), packet(1, one(3), before=0, after=1), packet(0, one(2)), packet(0, one(4)), packet(1, one(5))]], [300]),
        # a long block after one that said a short one follows, taking it for a long one: the short window over its left part
        'other-window': headers(5) + audio([[packet(0, one(1)), packet(1, one(3), before=0, after=0), packet(1, one(4), before=1, after=1), packet(1, one(5)), packet(0, one(6))]], [600]),
        # a long first block before a short one: samples left to drop from the second
        'long-first': headers(5) + audio([[packet(1, one(1), before=0, after=0), packet(0, one(3)), packet(0, one(2)), packet(1, one(4), before=0, after=1), packet(1, one(5))]], [500]),
    }
    # audio packets on the setup's page: the audio has no first page of its own
    out['shared-page'] = headers(5, more=blocks()[0]) + audio(blocks()[1:], [800])
    # pages after the one flagged as the last, whose position cut its last block: what that block leaves for the next is no
    # window's length (6 samples), or less than none (-24 and -32), and no frame after it gives a sample
    more = [packet(0, one(3)), packet(1, one(4), before=0, after=1), packet(1, one(5)), packet(0, one(8))]
    for granule in (730, 700, 500):
        out[f'after-last-{granule}'] = headers(5) + audio(blocks() + [more], [500, granule, 1200], last=1)
    return out


# -----------------------------------------------------------------------------
# The calls

WHOLE = [88200, 2, 0, 2]                                    # as LoadWave asks: every sample at once
STREAM = [4096] * 6 + [0, 0, 3, 1, 2, 5, 20000, 0, 7, MOST, 64]    # as a music stream asks, in steps; frames passed over; odd counts
STEPS = [0, 10, 1, 30, 64, 3, 0, 100, 7, 500, 0, 0, 2000, 16, 0]


def cases(source):
    """name -> (stream, calls): raylib's file whole and in steps, cut and damaged in its packets, and the streams built here."""
    out = {'whole': (source, WHOLE), 'stream': (source, STREAM)}
    where = bodies(source)
    for cut in (where[0][0] + 700, where[1][0] + 2000):
        out[f'cut-{cut}'] = (source[:cut], STREAM)
    rng = Rng(0xF4A3E5)
    for index in range(2):
        data = bytearray(source)
        for _ in range(1 + 2 * index):
            start, end = where[rng.next(len(where))]
            data[start + rng.next(end - start)] ^= 1 << rng.next(8)
        out[f'bits-{index}'] = (bytes(data), WHOLE)
    data = bytearray(source)
    start, end = where[1]
    at = start + rng.next(end - start - 64)
    for k in range(4 + rng.next(60)):
        data[at + k] = rng.next(256)
    out['bytes-0'] = (bytes(data), STREAM)
    for name, data in built().items():
        out[name] = (data, STEPS)
    out['loud-whole'] = (out['loud'][0], [MOST, 5, 0])
    return out


def words():
    """Floats' bits for the table: the steps of a short and the ties between them, the ends of a short's range, the ends of what is
    refused, the largest and least floats, infinities, NaNs, and seeded ones of every size."""
    def bits(x):
        return struct.unpack('<I', struct.pack('<f', x))[0]
    out = [0, 0x80000000, 1, 0x80000001, 0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00000, 0x7F800001, 0xFFBFFFFF, 0x7F7FFFFF, 0xFF7FFFFF]
    for value in (2.0 ** -16, 2.0 ** -15, 1.5 * 2.0 ** -15, 2.5 * 2.0 ** -15, 0.25, 0.5, 1.0 - 2.0 ** -15, 1.0 - 2.0 ** -16, 1.0, 1.0 + 2.0 ** -15, 127.5, 128.0, 383.5, 384.0, 767.5, 768.0, 1e9):
        for word in (bits(value), bits(-value)):
            out += [word - 1, word, word + 1]
    rng = Rng(0x5A3791E)
    for _ in range(160):
        # a sign, an exponent from 2^-20 to 2^12 and any fraction
        out.append(rng.next(2) << 31 | (107 + rng.next(33)) << 23 | rng.next(1 << 23))
    for _ in range(40):
        # from -384 to -768, where most are refused
        out.append(0xC3C00000 + rng.next(0x800002) - 1)
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('vorbis-frame', args)
    libm = gradient_reference()
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files = cases((args.raylib_source / SOURCE).read_bytes())
    table = words()
    items = [('floats', None, table)]
    for name, (data, calls) in files.items():
        (folder / f'{name}.ogg').write_bytes(data)
        items.append((name, f'{WORK}/{name}.ogg', calls))
    runs = '\n'.join(f'    {{ static const int ops[] = {{{", ".join(str(op) for op in calls)}}}; run({json.dumps(str(ROOT / path))}, ops, {len(calls)}); }}' for _, path, calls in items[1:])
    program = NATIVE.replace('WORDS', ', '.join(f'{word}u' for word in table)).replace('RUNS', runs)
    expected = [json.loads(line) for line in probe.native(program, 'reference', extra_flags=FLAGS, link_raylib=False).splitlines()]
    if len(expected) != len(items):
        raise ProbeFailure(f'vorbis-frame: the reference printed {len(expected)} rows for {len(items)} items')
    rows = {name: row for (name, _, _), row in zip(items, expected)}
    refused = sorted(name for name, row in rows.items() if name != 'floats' and row[-1] == -1)
    # what the corpus is for: the whole file is 44100 samples of each channel, read at once and in steps; only the louder stream
    # is refused, after calls that are not; the streams without a window give no sample of their four more packets; the table has floats
    # refused, floats at both ends of a short's range and floats inside it
    table_row = rows['floats']
    if (rows['whole'][-5:] != [44100, 0, 0, 1, 44100] or rows['stream'][-1] != 44100 or refused != ['louder'] or len(rows['louder']) < 4 or len({tuple(row) for row in expected}) != len(expected)
            or not 20 <= table_row.count(-1) <= len(table_row) // 2 or min(table_row.count(32767), table_row.count(32768)) < 20 or len(set(table_row)) < 60
            or any(rows[name][-1] > rows['loud'][-1] for name in ('after-last-730', 'after-last-700', 'after-last-500')) or any(len(row) < 3 for row in expected)):
        raise ProbeFailure(f'vorbis-frame: the reference runs are not the ones this probe was written for: { {name: row[-5:] for name, row in rows.items()} }')

    def render(selected, gpu):
        lines = []
        for k, (name, path, calls) in enumerate(selected):
            bound = 'Unit <- ' if k + 1 < len(selected) else ''
            if path is None:
                lines.append(f'    {bound}IO.print(floats([{", ".join(str(word) for word in calls)}], True{{}}, "["))\n')
            else:
                lines.append(f'    {bound}IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result, [{", ".join(str(op) for op in calls)}]))\n')
        return PROGRAM.replace('LIBM', libm) + ''.join(lines)

    def parse(text, selected):
        got = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(got) != len(selected):
            raise ValueError('vorbis-frame: candidate output did not finish')
        return got

    lanes = probe.candidates(render, items, batch=6, parse=parse, timeout=1700)

    def describe(index):
        for got in lanes.values():
            a, b = expected[index], got[index]
            if a != b:
                at = next((k for k, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
                return f'{items[index][0]}: differs at {at} of {len(a)} (stb ends {a[-5:]}, jonlib {b[-5:]})'
        return items[index][0]

    probe.compare(expected, lanes, describe=describe)
    probe.finish(files=len(items) - 1, calls=sum(len(calls) for _, _, calls in items[1:]), samples=sum(row[-5] for name, row in rows.items() if name != 'floats' and row[-1] != -1 and len(row) > 5),
                 refused=len(refused), floats=len(table), unconverted=table_row.count(-1), libm=libm)


if __name__ == '__main__':
    main()
