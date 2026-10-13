#!/usr/bin/env python3
"""Compare src/vorbis_residue.bend with stb_vorbis's residues.

Reference. stb_vorbis.c as pinned raylib vendors it, included in the
reference program: start_decoder on a built stream of four channels, then a
script of calls on the packets that follow the headers: maybe_start_packet,
flush_packet, get_bits, decode_residue for one of the stream's residues
(with a count of channels, a vectors' length and the channels that are not
decoded) and codebook_decode_deinterleave_repeat for one of its codebooks
(with a place to begin at, a length and a count of values), on four
buffers of 256 floats that keep what each call leaves. After each call
everything the reader keeps is hashed with the call's answer and the
buffers' bits; a run prints the rolling hash every 16 calls and how it
ends.

Candidate. The same scripts on the reader the port's setup leaves, with
R.residue.decode and R.weave.decode.

The stream's residues: of each type; beginning at 0, inside the vectors and
past their end; ending inside them and far past; partitions of 1 to 32
floats; 1 to 4 classifications of 1, 2 and 4 digits; classes with codebooks
in one pass, in several, in none; codebooks of 1 to 16 dimensions, with
lookups of each type, in a sequence and not, sparse, and one without a
lookup (an invalid stream). The calls take 1 to 4 channels, vectors of 32
and 64 floats, every choice of channels that are not decoded. The packets
are seeded bytes of 0 to 700 bytes. CPU-1, CPU-2 and JavaScript lanes.
"""
import json

import probekit
from probekit import ROOT, ProbeFailure
from vorbis_codebook_probe import Rng
from vorbis_ogg_probe import lists, page
from vorbis_setup_probe import book, comment, floor, identification, mapping, mode, paged, residue, whole

WORK = '.build/vorbis-residue-probe/cases'
FLAGS = ['-ffp-contract=off', '-D_DEFAULT_SOURCE', '-Wno-everything']
MAYBE_START_PACKET, FLUSH_PACKET, GET_BITS, DECODE_RESIDUE, DEINTERLEAVE = range(5)
CHANNELS, FLOATS = 4, 256
REFUSED = 1001

NATIVE = r'''#include "external/stb_vorbis.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned fnv(unsigned h, unsigned v) { return (h ^ v)*16777619u; }

static unsigned digest(stb_vorbis *f, unsigned answer, float floats[4][256])
{
    unsigned h = fnv(2166136261u, answer);
    int i, j;
    h = fnv(h, (unsigned)(f->stream - f->stream_start)); h = fnv(h, f->eof != 0); h = fnv(h, (unsigned)f->error);
    h = fnv(h, f->page_flag); h = fnv(h, (unsigned)f->segment_count);
    for (i = 0; i < 255; i++) h = fnv(h, f->segments[i]);
    h = fnv(h, (unsigned)f->next_seg); h = fnv(h, (unsigned)f->last_page); h = fnv(h, (unsigned)f->end_seg_with_known_loc); h = fnv(h, f->known_loc_for_packet);
    h = fnv(h, f->first_decode != 0); h = fnv(h, f->p_first.page_start); h = fnv(h, f->p_first.page_end); h = fnv(h, f->p_first.last_decoded_sample);
    h = fnv(h, f->bytes_in_seg); h = fnv(h, f->last_seg != 0); h = fnv(h, (unsigned)f->last_seg_which); h = fnv(h, (unsigned)f->packet_bytes);
    h = fnv(h, f->acc); h = fnv(h, (unsigned)f->valid_bits);
    for (j = 0; j < 4; j++) for (i = 0; i < 256; i++) { unsigned w; memcpy(&w, &floats[j][i], 4); h = fnv(h, w); }
    return h;
}

// Calls of three numbers each: the function and two packed arguments.
static void run(const char *path, const int *ops, int count)
{
    static stb_vorbis p;
    static float floats[4][256];
    unsigned char *data;
    int k, len, j;
    unsigned roll = 2166136261u, seen = 0;
    FILE *file = fopen(path, "rb");
    if (!file) exit(2);
    fseek(file, 0, SEEK_END);
    len = (int)ftell(file);
    fseek(file, 0, SEEK_SET);
    data = (unsigned char *)malloc(len? len : 1);
    if (fread(data, 1, len, file) != (size_t)len) exit(3);
    fclose(file);
    // stb_vorbis_open_memory
    vorbis_init(&p, NULL);
    p.stream = data;
    p.stream_end = data + len;
    p.stream_start = p.stream;
    p.stream_len = len;
    p.push_mode = FALSE;
    if (!start_decoder(&p)) exit(4);
    for (j = 0; j < 4; j++) for (k = 0; k < 256; k++) floats[j][k] = (float)(((k + 64*j)*37)%11) - 5.0f;
    floats[1][3] = -0.0f;
    printf("[");
    for (k = 0; k < count; k++)
    {
        int op = ops[3*k], a = ops[3*k + 1], b = ops[3*k + 2];
        stb_vorbis *f = &p;
        unsigned answer = 0;
        switch (op)
        {
            case 0: answer = (unsigned)maybe_start_packet(f); break;
            case 1: flush_packet(f); break;
            case 2: answer = get_bits(f, a); break;
            case 3:
            {
                // a residue: its number, the channels and the ones that are not decoded (a null buffer, as vorbis_decode_packet_rest gives them); b is the vectors' length
                int ch = (a >> 8) & 15, mask = (a >> 12) & 15;
                float *buffers[4];
                uint8 skipped[4];
                for (j = 0; j < 4; j++) { skipped[j] = !((mask >> j) & 1); buffers[j] = skipped[j]? NULL : floats[j]; }
                decode_residue(f, buffers, ch, b, a & 255, skipped);
                break;
            }
            default:
            {
                // vectors over the channels: a codebook and the channels with floats; b packs the channels, where the next value goes, the length and the count
                int ch = b & 7, c_inter = (b >> 3) & 7, p_inter = (b >> 6) & 127, length = (b >> 13) & 255, total = (b >> 21) & 255, mask = (a >> 8) & 15;
                float *buffers[4];
                for (j = 0; j < 4; j++) buffers[j] = ((mask >> j) & 1)? floats[j] : NULL;
                answer = (unsigned)codebook_decode_deinterleave_repeat(f, f->codebooks + (a & 255), buffers, ch, &c_inter, &p_inter, length, total);
                answer |= (unsigned)c_inter << 1 | (unsigned)p_inter << 8;
                break;
            }
        }
        roll = fnv(roll, digest(&p, answer, floats));
        seen |= 1u << ((unsigned)p.error%29);
        if (k%16 == 15) printf("%u, ", roll);
    }
    printf("%u, %u, %u, %u, %u]\n", roll, seen, (unsigned)p.error, (unsigned)(p.eof != 0), (unsigned)(p.stream - p.stream_start));
    free(data);
}

SCRIPTS

int main(void)
{
RUNS
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/vorbis_ogg.bend as V
import ../../src/vorbis_setup.bend as S
import ../../src/vorbis_maps.bend as M
import ../../src/vorbis_decode.bend as D
import ../../src/vorbis_residue.bend as X
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

def mixed.rows(rows: +List<R.Row>, +h: U32) -> U32:
  match rows:
    case Nil{}: h
    case Con{+row, +rest}: mixed.rows(rest, mixed.floats(R.Row.list(row), h))

def flag(on: Bool) -> U32:
  match on:
    case True{}: 1
    case False{}: 0

# Everything the reader keeps, with the call's answer first and the floats last.
def digest(reader: V.Reader, +floats: +List<R.Row>) -> U32:
  match reader:
    case V.Reader{V.Stream{_, _, +at, _, +eof}, V.Page{+bits, +count, +segments, +next, +sequence, +known_seg, +known_loc}, V.First{+decoding, +start, +end, +sample}, V.Packet{+in_seg, +last, +which, +bytes, +acc, +valid}, +error, _, +value}:
      mixed.rows(floats, mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mixed(segments, mix(mix(mix(mix(mix(mix(2166136261, value), at), flag(eof)), error), bits), count)),
        next), sequence), known_seg), known_loc), flag(decoding)), start), end), sample), in_seg), flag(last)), which), bytes), acc), valid))

# The reader and the four channels' floats between calls.
type State is Data:
  State{reader: V.Reader, floats: +List<R.Row>}

def State.reader(state: State) -> V.Reader:
  State{reader, _} = state
  reader

def State.floats(state: State) -> +List<R.Row>:
  State{_, floats} = state
  floats

# A call's channels are the first `count` of the four: the others are put back after them.
def rejoined(rows: +List<R.Row>, +all: +List<R.Row>, +count: U32) -> +List<R.Row>:
  List.append(&2, R.Row, rows, List.drop(&2, R.Row, all, U32.to_nat(count)))

def first.rows(n: Nat, rows: +List<R.Row>, acc: +List<R.Row>) -> +List<R.Row>:
  match n:
    case 0n: List.reverse(&2, R.Row, acc)
    case 1n+k:
      match rows:
        case Nil{}: List.reverse(&2, R.Row, acc)
        case Con{+r, +rest}: first.rows(k, rest, Con{r, acc})

def residue.at(residues: +List<M.Residue>) -> M.Residue:
  match residues:
    case Nil{}: M.Residue{0, 0, 0, 1, 1, 0, Nil{}}
    case Con{+r, _}: r

def residued(res: X.Res, +all: +List<R.Row>, +count: U32) -> State:
  X.Res{reader, rows, _} = res
  State{V.Reader.answer(reader, 0), rejoined(rows, all, count)}

def woven(made: X.Woven, +all: +List<R.Row>, +count: U32, +c: U32, +p: U32) -> State:
  X.Woven{reader, rows, +c_inter, +p_inter, +fine} = made
  State{V.Reader.answer(reader, ((flag(fine) .|. (Bool.pick(U32, fine, c_inter, c) << 1n)) .|. (Bool.pick(U32, fine, p_inter, p) << 8n) : U32)), rejoined(rows, all, count)}

def step(op: U32, +a: U32, +b: U32, +coders: +List<D.Coder>, +residues: +List<M.Residue>, +reader: V.Reader, +floats: +List<R.Row>) -> State:
  match op:
    case 0: State{V.packet.maybe(reader), floats}
    case 1: State{V.flush.packet(reader), floats}
    case 2: State{V.bits.get(a, reader), floats}
    case 3: residued(X.residue.decode(reader, first.rows(U32.to_nat(((a >> 8n) .&. 15 : U32)), floats, Nil{}), coders, residue.at(List.drop(&2, M.Residue, residues, U32.to_nat((a .&. 255 : U32)))), ((a >> 8n) .&. 15 : U32), b,
      ((a >> 12n) .&. 15 : U32)), floats, ((a >> 8n) .&. 15 : U32))
    case _: woven(X.weave.decode(D.coder.at(coders, (a .&. 255 : U32)), reader, first.rows(U32.to_nat((b .&. 7 : U32)), floats, Nil{}), ((a >> 8n) .&. 15 : U32), (b .&. 7 : U32), ((b >> 3n) .&. 7 : U32), ((b >> 6n) .&. 127 : U32),
      ((b >> 13n) .&. 255 : U32), ((b >> 21n) .&. 255 : U32)), floats, (b .&. 7 : U32), ((b >> 3n) .&. 7 : U32), ((b >> 6n) .&. 127 : U32))

def ending(reader: V.Reader, +roll: U32, +seen: U32, +out: String) -> String:
  match reader:
    case V.Reader{V.Stream{_, _, +at, _, +eof}, _, _, _, +error, _, _}:
      Bool.pick(String, (error >= 1000 : U32), "[" ++ U32.show(error) ++ "]", out ++ U32.show(roll) ++ ", " ++ U32.show(seen) ++ ", " ++ U32.show(error) ++ ", " ++ U32.show(flag(eof)) ++ ", " ++ U32.show(at) ++ "]")

# A script's calls in turn: the rolling hash every 16, the errors met and the end.
def run(ops: +List<U32>, +k: U32, +roll: U32, +seen: U32, +coders: +List<D.Coder>, +residues: +List<M.Residue>, +state: State, +out: String) -> String:
  match ops:
    case Con{+op, Con{+a, Con{+b, +rest}}}:
      +next = step(op, a, b, coders, residues, State.reader(state), State.floats(state))
      +h = mix(roll, digest(State.reader(next), State.floats(next)))
      run(rest, (k + 1 : U32), h, (seen .|. (1 << U32.to_nat((V.Reader.error(State.reader(next)) % 29 : U32))) : U32), coders, residues, next, Bool.pick(String, U32.is_eq((k % 16 : U32), 15), out ++ U32.show(h) ++ ", ", out))
    case _: ending(State.reader(state), roll, seen, out)

# floats[j][k] = (float)(((k + 64*j)*37)%11) - 5.0f, and floats[1][3] = -0.0f.
def seeded(n: Nat, +j: U32, +k: U32, acc: +List<F32>) -> +List<F32>:
  match n:
    case 0n: List.reverse(&2, F32, acc)
    case 1n+rest: seeded(rest, j, (k + 1 : U32), Con{Bool.pick(F32, U32.is_eq(j, 1) && U32.is_eq(k, 3), F32.neg(0.0), (U32.to_f32((((k + (64 * j)) * 37) % 11 : U32)) - 5.0 : F32)), acc})

SCRIPTS
def started(+setup: S.Setup, +fine: M.Maps, +which: U32) -> String:
  ran(which, D.coders.of(S.Setup.books(setup), Nil{}), M.Maps.residues(fine),
    State{M.Maps.reader(fine), [R.Row.from(seeded(256n, 0, 0, Nil{})), R.Row.from(seeded(256n, 1, 0, Nil{})), R.Row.from(seeded(256n, 2, 0, Nil{})), R.Row.from(seeded(256n, 3, 0, Nil{}))]})

def opened(+setup: S.Setup, +which: U32) -> String:
  started(setup, M.maps.read(setup), which)

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>, +which: U32) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(opened(S.setup.codebooks(bytes), which))

def main() -> IO(Unit):
  do IO<Unit>:
'''


def setup_parts(rng):
    """The stream's codebooks and residues: (names of the codebooks, the codebooks, the residues)."""
    one, half, tiny = 788 << 21 | 1, 787 << 21 | 1, 0x80000000 | 786 << 21 | 3
    values = lambda count, bits: [rng.next(1 << bits) for _ in range(count)]
    books = [('class-1', book(1, [2] * 4)),                                                # 0: a class of one digit, 4 classifications
             ('class-2', book(2, [3] * 7 + [4, 4])),                                       # 1: two digits in base 3
             ('class-4', book(4, [4] * 16)),                                               # 2: four digits in base 2
             ('one', book(1, [3] * 8, lookup=(1, 0, one, 4, False, values(8, 4)))),        # 3
             ('two-sequence', book(2, [4] * 16, lookup=(1, tiny, half, 5, True, values(4, 5)))),          # 4
             ('four', book(4, [3] * 8, lookup=(2, half, one, 6, False, values(32, 6)))),   # 5
             ('eight', book(8, [8] * 256, lookup=(1, tiny, one, 7, False, values(2, 7)))),                # 6
             ('none', book(2, [2] * 4)),                                                   # 7: no lookup
             ('three', book(3, [5] * 27 + [255] * 0, lookup=(1, one, half, 3, True, values(3, 3)))),      # 8
             ('sparse', book(2, [255 if k % 5 else 3 + (k // 5) % 3 for k in range(40)], sparse=True, lookup=(1, 0, one, 4, False, values(6, 4)))),   # 9
             ('sixteen', book(16, [1, 1], lookup=(2, one, tiny, 9, True, values(32, 9)))),               # 10
             ('class-1-of-2', book(1, [1, 1])),                                            # 11: a class of one digit, 2 classifications
             ('single', book(4, [1], lookup=(1, half, one, 3, False, values(1, 3))))]      # 12: one symbol, whose 4 values are all the codebook has
    r = residue
    residues = [r(kind=0, begin=0, end=32, part_size=8, classbook=0, cascades=(0, 1, 3, 0x81), books=(3, 3, 4, 5, 6)),
                r(kind=1, begin=4, end=60, part_size=4, classbook=1, cascades=(1, 2, 0x44), books=(5, 3, 4, 8)),
                r(kind=2, begin=0, end=128, part_size=16, classbook=2, cascades=(3, 0x10), books=(6, 4, 10)),
                r(kind=2, begin=10, end=1000, part_size=32, classbook=11, cascades=(1, 0x80), books=(9, 5)),
                r(kind=1, begin=200, end=400, part_size=8, classbook=0, cascades=(1, 1, 1, 1), books=(3, 3, 3, 3)),
                r(kind=0, begin=2, end=64, part_size=6, classbook=11, cascades=(5, 2), books=(4, 5, 8)),
                r(kind=1, begin=0, end=64, part_size=8, classbook=0, cascades=(1, 1, 2, 0), books=(7, 3, 4)),
                r(kind=2, begin=3, end=40, part_size=1, classbook=2, cascades=(1, 3), books=(3, 3, 8)),
                r(kind=1, begin=0, end=31, part_size=32, classbook=11, cascades=(1, 1), books=(6, 10)),
                r(kind=2, begin=0, end=64, part_size=8, classbook=0, cascades=(0, 0, 0, 0), books=()),
                r(kind=0, begin=0, end=64, part_size=16, classbook=1, cascades=(0xFF, 1, 0), books=(3, 4, 5, 6, 8, 9, 10, 3, 6))]
    return [name for name, _ in books], [write for _, write in books], residues


# The codebooks' dimensions, by name.
DIMENSIONS = {'class-1': 1, 'class-2': 2, 'class-4': 4, 'one': 1, 'two-sequence': 2, 'four': 4, 'eight': 8, 'none': 2, 'three': 3, 'sparse': 2, 'sixteen': 16, 'class-1-of-2': 1, 'single': 4}


def streams():
    """name -> stream of four channels; the names of its codebooks and how many residues it has."""
    rng = Rng(0x2E51D)
    names, books, residues = setup_parts(rng)
    setup = whole(books=books, residues=residues, mappings=[mapping(channels=CHANNELS)])
    sizes = [40, 0, 1, 5, 300, 700, 255, 2, 510, 64, 33, 128, 9, 250, 400, 17] * 8
    data = [bytes(rng.next(256) for _ in range(size)) for size in sizes]
    data[0] = b'\x00' + data[0][1:]                                             # the first packet begins with the one-bit code of a single symbol
    first = page(2, 0, 0, [30], body=identification(channels=CHANNELS))
    headers = first + paged([comment(), setup])
    out = {'packets': headers + paged(data, sequence=2)}
    # a call takes few bytes and the next packet begins at the next segment, not where the bytes are: the data ends early in this one
    out['cut'] = out['packets'][:len(headers) + 200]
    return out, names, len(residues)


def scripts(names, residues):
    """(name, calls): a call is (function, a, b), the arguments packed as the programs unpack them."""
    rng = Rng(0x7E5)
    out = []
    # each residue, a packet a call, over the counts of channels, the vectors' lengths and the channels that are not decoded
    for number in range(residues):
        calls = []
        for index in range(96):
            channels = 1 + index % CHANNELS
            mask = (1 << channels) - 1 if index % 3 else rng.next(1 << channels)
            calls += [(MAYBE_START_PACKET, 0, 0), (DECODE_RESIDUE, number | channels << 8 | mask << 12, 32 << (index // 4 % 2))] + ([(FLUSH_PACKET, 0, 0)] if number % 2 else [])
        out.append((f'residue-{number}', calls))
    # residues one after another in a packet: what one leaves in the floats, the next adds to
    for seed in (1, 2):
        calls = []
        for index in range(160):
            if index % 4 == 0:
                calls.append((MAYBE_START_PACKET, 0, 0))
            if rng.next(5) == 0:
                calls.append((GET_BITS, rng.next(33), 0))
            channels = 1 + rng.next(CHANNELS)
            calls.append((DECODE_RESIDUE, rng.next(residues) | channels << 8 | rng.next(1 << channels) << 12, 32 << rng.next(2)))
            if rng.next(7) == 0:
                calls.append((FLUSH_PACKET, 0, 0))
        out.append((f'residues-{seed}', calls))
    # vectors over the channels, called directly, for every codebook. Where the vectors come to the end of the floats stb_vorbis
    # takes more values than are left, by twice the channel it is at: more than a vector has, past the codebook's values for its
    # last symbol (see `refused` below). So a call either stays clear of the end (any channels, any place to begin), or keeps to
    # the first channel at each vector (it begins there and the channels divide the codebook's dimensions) and goes anywhere,
    # past the end too.
    for index, name in enumerate(names):
        dimensions = DIMENSIONS[name]
        calls = []
        for turn in range(90):
            if turn % 5 == 0:
                calls.append((MAYBE_START_PACKET, 0, 0))
            aligned = [channels for channels in range(1, CHANNELS + 1) if dimensions % channels == 0]
            if turn % 2 and aligned:
                channels = aligned[rng.next(len(aligned))]
                length = 1 + rng.next(40)
                first, place, total = 0, rng.next(length + 3) if turn % 4 == 1 else rng.next(60), rng.next(90)
            else:
                channels = 1 + rng.next(CHANNELS)
                length = 20 + rng.next(21)
                total = rng.next(1 + min(60, length * channels - 2 * dimensions - channels) // 2) if length * channels > 2 * dimensions + channels else 0
                first = rng.next(channels)
                place = rng.next(1 + max(0, (length * channels - total - 2 * dimensions - first) // channels))
            mask = rng.next(1 << channels) if turn % 3 == 0 else (1 << channels) - 1
            calls.append((DEINTERLEAVE, index | mask << 8, channels | first << 3 | min(place, 100) << 6 | length << 13 | total << 21))
        out.append((f'{name}-woven', calls))
    # refused: the single symbol's vector at the end of three channels' floats, from the third channel. 5 values are taken and it has 4.
    single = names.index('single')
    out.append(('refused', [(MAYBE_START_PACKET, 0, 0), (DEINTERLEAVE, single | 7 << 8, 3 | 2 << 3 | 9 << 6 | 10 << 13 | 4 << 21)]))
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('vorbis-residue', args)
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files, names, residues = streams()
    for name, data in files.items():
        (folder / f'{name}.ogg').write_bytes(data)
    chosen = scripts(names, residues)
    # the refusal is the port's alone: stb_vorbis is not run on it (and only the whole stream begins with the bit it needs)
    items = [(name, f'{WORK}/{name}.ogg', index) for name in files for index, (script, _) in enumerate(chosen) if script != 'refused' or name == 'packets']
    refused = lambda item: chosen[item[2]][0] == 'refused'
    arrays = '\n'.join(f'static const int script{k}[] = {{ {", ".join(f"{op}, {a}, {b}" for op, a, b in calls)} }};' for k, (_, calls) in enumerate(chosen))
    runs = '\n'.join(f'    run({json.dumps(str(ROOT / path))}, script{index}, {len(chosen[index][1])});' for name, path, index in items if not refused((name, path, index)))
    lines = [json.loads(line) for line in probe.native(NATIVE.replace('SCRIPTS', arrays).replace('RUNS', runs), 'reference', extra_flags=FLAGS, link_raylib=False).splitlines()]
    if len(lines) != sum(1 for item in items if not refused(item)):
        raise ProbeFailure(f'vorbis-residue: the reference printed {len(lines)} runs')
    native = iter(lines)
    expected = [[REFUSED] if refused(item) else next(native) for item in items]
    ends = [row[-4:] for row in lines]
    errors = {code for end in ends for code in (0, 21) if end[0] >> (code % 29) & 1}
    if errors != {0, 21} or len({tuple(row) for row in lines}) < len(lines) * 2 // 3 or sum(1 for end in ends if end[2]) < 5 or expected.count([REFUSED]) != 1:
        raise ProbeFailure(f'vorbis-residue: the reference runs are not the ones this probe was written for: errors {sorted(errors)}, {len({tuple(row) for row in expected})} different runs of {len(expected)}')

    def render(selected, gpu):
        defs = ''.join(f'def script{k}() -> +List<U32>:\n  {lists([value for call in calls for value in call])}\n\n' for k, (_, calls) in enumerate(chosen))
        cases = ''.join(f'    case {k}: run(script{k}(), 0, 2166136261, 0, coders, residues, state, "[")\n' for k in range(len(chosen) - 1)) + f'    case _: run(script{len(chosen) - 1}(), 0, 2166136261, 0, coders, residues, state, "[")\n'
        ran = f'def ran(which: U32, +coders: +List<D.Coder>, +residues: +List<M.Residue>, +state: State) -> String:\n  match which:\n{cases}\n'
        body = ''.join(f'    {"Unit <- " if k + 1 < len(selected) else ""}IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result, {index}))\n'
                       for k, (_, path, index) in enumerate(selected))
        return PROGRAM.replace('SCRIPTS', defs + ran) + body

    def parse(text, selected):
        rows = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(rows) != len(selected):
            raise ValueError('vorbis-residue: candidate output did not finish')
        return rows

    lanes = probe.candidates(render, items, batch=25, parse=parse, timeout=1500)

    def describe(index):
        name, _, script = items[index]
        for got in lanes.values():
            a, b = expected[index], got[index]
            if a != b:
                at = next((k for k, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
                return f'{name}, script {chosen[script][0]}: differs by call {min(16 * (at + 1), len(chosen[script][1]))} (stb ends {a[-3:]}, jonlib {b[-3:]})'
        return f'{name}, script {chosen[script][0]}'

    probe.compare(expected, lanes, describe=describe)
    probe.finish(files=len(files), codebooks=len(names), residues=residues, scripts=len(chosen), runs=len(items), refused=expected.count([REFUSED]), calls=sum(len(chosen[index][1]) for _, _, index in items), errors=sorted(errors))


if __name__ == '__main__':
    main()
