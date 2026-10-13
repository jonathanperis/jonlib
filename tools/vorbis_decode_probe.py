#!/usr/bin/env python3
"""Compare src/vorbis_decode.bend with stb_vorbis's decoding of codebook
symbols and vectors.

Reference. stb_vorbis.c as pinned raylib vendors it, included in the
reference program: start_decoder on a built stream, then a script of calls
on the packets that follow the headers: maybe_start_packet, flush_packet,
get_bits, prep_huffman, the DECODE_RAW and DECODE macros (the inline
build's, as raylib compiles them), codebook_decode_scalar_raw,
codebook_decode and codebook_decode_step into a buffer of 64 floats, and
get8_packet. After each call everything the reader keeps is hashed with the
call's answer and the buffer's bits; a run prints the rolling hash every 64
calls and how it ends.

Candidate. The same scripts on the reader the port's setup leaves
(S.setup.codebooks, M.maps.read), with D.coder.of of each codebook.

The stream's codebooks are one of each way a symbol is found: by the
accelerated table alone (codes of up to 10 bits), by the sorted table (a
codebook of long codes; a sparse one; a sparse one of 8 entries or fewer),
by the search of the symbols (8 entries or fewer with a long code; more
than 8 without a sorted table and with codes left over), with one symbol,
with no symbol; and for the vectors, lookups of each type, in a sequence
and not, sparse and not, of 1 to 8 dimensions, and none. The packets are
seeded bytes of 0 to 700 bytes, over segments and pages, and data that
ends inside one.

Two things stb_vorbis does that C leaves undefined are refused by the port
(the reader's error 1001), and stb_vorbis is not run on them: DECODE on a
sparse codebook without a code (it reads the place before the first of a
sorted table that is not there), and prep_huffman after the bits ran out on
a page that should have been a continued one (it shifts by -1).
CPU-1, CPU-2 and JavaScript lanes.
"""
import json

import probekit
from probekit import ROOT, ProbeFailure
from vorbis_codebook_probe import Rng, tree
from vorbis_ogg_probe import lists, page
from vorbis_setup_probe import book, comment, identification, paged, whole

WORK = '.build/vorbis-decode-probe/cases'
FLAGS = ['-ffp-contract=off', '-D_DEFAULT_SOURCE', '-Wno-everything']
MAYBE_START_PACKET, FLUSH_PACKET, GET_BITS, PREP_HUFFMAN, DECODE_RAW, DECODE, SCALAR_RAW, CODEBOOK_DECODE, CODEBOOK_DECODE_STEP, GET8_PACKET = range(10)
REFUSED = 1001

NATIVE = r'''#include "external/stb_vorbis.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned fnv(unsigned h, unsigned v) { return (h ^ v)*16777619u; }

static unsigned digest(stb_vorbis *f, unsigned answer, const float *floats)
{
    unsigned h = fnv(2166136261u, answer);
    int i;
    h = fnv(h, (unsigned)(f->stream - f->stream_start)); h = fnv(h, f->eof != 0); h = fnv(h, (unsigned)f->error);
    h = fnv(h, f->page_flag); h = fnv(h, (unsigned)f->segment_count);
    for (i = 0; i < 255; i++) h = fnv(h, f->segments[i]);
    h = fnv(h, (unsigned)f->next_seg); h = fnv(h, (unsigned)f->last_page); h = fnv(h, (unsigned)f->end_seg_with_known_loc); h = fnv(h, f->known_loc_for_packet);
    h = fnv(h, f->first_decode != 0); h = fnv(h, f->p_first.page_start); h = fnv(h, f->p_first.page_end); h = fnv(h, f->p_first.last_decoded_sample);
    h = fnv(h, f->bytes_in_seg); h = fnv(h, f->last_seg != 0); h = fnv(h, (unsigned)f->last_seg_which); h = fnv(h, (unsigned)f->packet_bytes);
    h = fnv(h, f->acc); h = fnv(h, (unsigned)f->valid_bits);
    for (i = 0; i < 64; i++) { unsigned w; memcpy(&w, floats + i, 4); h = fnv(h, w); }
    return h;
}

// Calls of three numbers each: the function, and two arguments (a codebook, or a width; and where, how many and how far apart the floats are, packed).
static void run(const char *path, const int *ops, int count)
{
    static stb_vorbis p;
    unsigned char *data;
    float floats[64];
    int k, len, value;
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
    for (k = 0; k < 64; k++) floats[k] = (float)((k*37)%11) - 5.0f;
    floats[3] = -0.0f;
    printf("[");
    for (k = 0; k < count; k++)
    {
        int op = ops[3*k], a = ops[3*k + 1], b = ops[3*k + 2];
        Codebook *c = p.codebooks + a;
        stb_vorbis *f = &p;
        unsigned answer = 0;
        switch (op)
        {
            case 0: answer = (unsigned)maybe_start_packet(f); break;
            case 1: flush_packet(f); break;
            case 2: answer = get_bits(f, a); break;
            case 3: prep_huffman(f); break;
            case 4: DECODE_RAW(value, f, c); answer = (unsigned)value; break;
            case 5: DECODE(value, f, c); answer = (unsigned)value; break;
            case 6: answer = (unsigned)codebook_decode_scalar_raw(f, c); break;
            case 7: answer = (unsigned)codebook_decode(f, c, floats + (b & 63), (b >> 6) & 63); break;
            case 8: answer = (unsigned)codebook_decode_step(f, c, floats + (b & 63), (b >> 6) & 63, (b >> 12) & 63); break;
            default: answer = (unsigned)get8_packet(f); break;
        }
        roll = fnv(roll, digest(&p, answer, floats));
        seen |= 1u << ((unsigned)p.error%29);
        if (k%64 == 63) printf("%u, ", roll);
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

def flag(on: Bool) -> U32:
  match on:
    case True{}: 1
    case False{}: 0

# Everything the reader keeps, with the call's answer first and the floats last.
def digest(reader: V.Reader, +floats: R.Row) -> U32:
  match reader:
    case V.Reader{V.Stream{_, _, +at, _, +eof}, V.Page{+bits, +count, +segments, +next, +sequence, +known_seg, +known_loc}, V.First{+decoding, +start, +end, +sample}, V.Packet{+in_seg, +last, +which, +bytes, +acc, +valid}, +error, _, +value}:
      mixed.floats(R.Row.list(floats), mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mixed(segments, mix(mix(mix(mix(mix(mix(2166136261, value), at), flag(eof)), error), bits), count)),
        next), sequence), known_seg), known_loc), flag(decoding)), start), end), sample), in_seg), flag(last)), which), bytes), acc), valid))

# The reader and the floats between calls.
type State is Data:
  State{reader: V.Reader, floats: R.Row}

def State.reader(state: State) -> V.Reader:
  State{reader, _} = state
  reader

def State.floats(state: State) -> R.Row:
  State{_, floats} = state
  floats

def vector(made: D.Vector) -> State:
  D.Vector{reader, row, fine} = made
  State{V.Reader.answer(reader, flag(fine)), row}

def step(op: U32, +a: U32, +b: U32, +coders: +List<D.Coder>, +reader: V.Reader, +floats: R.Row) -> State:
  match op:
    case 0: State{V.packet.maybe(reader), floats}
    case 1: State{V.flush.packet(reader), floats}
    case 2: State{V.bits.get(a, reader), floats}
    case 3: State{V.Reader.answer(V.huffman.prep(reader), 0), floats}
    case 4: State{D.decode.raw(D.coder.at(coders, a), reader), floats}
    case 5: State{D.decode.symbol(D.coder.at(coders, a), reader), floats}
    case 6: State{D.raw.decode(D.coder.at(coders, a), reader), floats}
    case 7: vector(D.vector.decode(D.coder.at(coders, a), reader, floats, (b .&. 63 : U32), ((b >> 6n) .&. 63 : U32)))
    case 8: vector(D.vector.step(D.coder.at(coders, a), reader, floats, (b .&. 63 : U32), ((b >> 6n) .&. 63 : U32), ((b >> 12n) .&. 63 : U32)))
    case _: State{V.packet.get8(reader), floats}

def ending(reader: V.Reader, +roll: U32, +seen: U32, +out: String) -> String:
  match reader:
    case V.Reader{V.Stream{_, _, +at, _, +eof}, _, _, _, +error, _, _}:
      Bool.pick(String, (error >= 1000 : U32), "[" ++ U32.show(error) ++ "]", out ++ U32.show(roll) ++ ", " ++ U32.show(seen) ++ ", " ++ U32.show(error) ++ ", " ++ U32.show(flag(eof)) ++ ", " ++ U32.show(at) ++ "]")

# A script's calls in turn: the rolling hash every 64, the errors met and the end; a refusal alone where the port refuses.
def run(ops: +List<U32>, +k: U32, +roll: U32, +seen: U32, +coders: +List<D.Coder>, +state: State, +out: String) -> String:
  match ops:
    case Con{+op, Con{+a, Con{+b, +rest}}}:
      +next = step(op, a, b, coders, State.reader(state), State.floats(state))
      +h = mix(roll, digest(State.reader(next), State.floats(next)))
      run(rest, (k + 1 : U32), h, (seen .|. (1 << U32.to_nat((V.Reader.error(State.reader(next)) % 29 : U32))) : U32), coders, next, Bool.pick(String, U32.is_eq((k % 64 : U32), 63), out ++ U32.show(h) ++ ", ", out))
    case _: ending(State.reader(state), roll, seen, out)

# floats[k] = (float)((k*37)%11) - 5.0f, and floats[3] = -0.0f.
def seeded(n: Nat, +k: U32, acc: +List<F32>) -> +List<F32>:
  match n:
    case 0n: List.reverse(&2, F32, acc)
    case 1n+rest: seeded(rest, (k + 1 : U32), Con{Bool.pick(F32, U32.is_eq(k, 3), F32.neg(0.0), (U32.to_f32(((k * 37) % 11 : U32)) - 5.0 : F32)), acc})

SCRIPTS
def started(+setup: S.Setup, +fine: M.Maps, +which: U32) -> String:
  ran(which, D.coders.of(S.Setup.books(setup), Nil{}), State{M.Maps.reader(fine), R.Row.from(seeded(64n, 0, Nil{}))})

def opened(+setup: S.Setup, +which: U32) -> String:
  started(setup, M.maps.read(setup), which)

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>, +which: U32) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(opened(S.setup.codebooks(bytes), which))

def main() -> IO(Unit):
  do IO<Unit>:
'''


def books(rng):
    """The stream's codebooks: (how its symbols are found, the codebook)."""
    one, half, tiny = 788 << 21 | 1, 787 << 21 | 1, 0x80000000 | 786 << 21 | 3
    values = lambda count, bits: [rng.next(1 << bits) for _ in range(count)]
    deep = tree(300, rng)
    long = [1, 12, 12, 13, 13, 255, 14, 14]
    return [('fast', book(1, [3] * 8)),
            ('fast-lookup-1', book(2, [4] * 16, lookup=(1, 0, one, 4, False, values(4, 4)))),
            ('fast-sequence', book(3, [5] * 27, lookup=(1, tiny, half, 9, True, values(3, 9)))),
            ('sorted', book(1, deep)),
            ('sorted-lookup-2', book(4, deep[:100], lookup=(2, half, one, 7, True, values(400, 7)))),
            ('sparse', book(2, [255 if k % 9 else 5 + (k // 9) % 3 for k in range(200)], sparse=True, lookup=(1, one, tiny, 6, False, values(14, 6)))),
            ('sparse-small', book(1, [255, 255, 255, 255, 255, 255, 255, 1], sparse=True)),
            ('searched', book(1, [1, 12, 12, 13, 13, 14, 14, 3], lookup=(1, 0, one, 3, True, values(8, 3)))),
            ('searched-incomplete', book(1, [4] * 12)),
            ('one', book(8, [1], lookup=(1, half, half, 2, False, [3]))),
            ('none', book(1, [255] * 16, sparse=True)),
            ('long-codes', book(2, [31, 31, 30, 29] + list(range(1, 29)), lookup=(2, tiny, half, 16, False, values(64, 16))))]


def packets(rng):
    """Packets of seeded bytes for the calls to decode: (the pages after the headers', where a second stream variant breaks a packet)."""
    sizes = [40, 0, 1, 5, 300, 700, 255, 2, 510, 64, 33, 128, 9, 250, 400, 17] * 3
    return [bytes(rng.next(256) for _ in range(size)) for size in sizes]


def streams():
    """name -> (stream, how many codebooks)."""
    rng = Rng(0xDEC0DE)
    made = books(rng)
    setup = whole(books=[write for _, write in made])
    data = packets(rng)
    first = page(2, 0, 0, [30], body=identification())
    headers = first + paged([comment(), setup])
    sequence = 1 + sum(1 for at in range(len(headers) - 3) if headers[at:at + 4] == b'OggS' and at)
    out = {'packets': headers + paged(data, sequence=sequence)}
    out['cut'] = out['packets'][:len(headers) + 900]
    # a packet over two pages, the second without the flag that says it goes on: the bits run out there, and the page's bytes follow
    out['unflagged'] = headers + page(0, 0, sequence, [255, 255], body=data[5][:510]) + page(0, 0, sequence + 1, [100, 30, 80], body=data[4][:210]) + paged(data[6:20], sequence=sequence + 2)
    return out, [name for name, _ in made]


def scripts(names):
    """(name, calls, whether the port refuses it on a file): a call is (function, codebook or width, packed floats' place, count and step)."""
    rng = Rng(0x5C21F7)
    count = len(names)
    scalar = [k for k, name in enumerate(names) if name != 'none']
    out = []
    # a codebook's symbols, a packet after another
    for index, name in enumerate(names):
        for function in (DECODE_RAW, SCALAR_RAW) + ((DECODE,) if name != 'none' else ()):
            calls = []
            for _ in range(24):
                calls += [(MAYBE_START_PACKET, 0, 0)] + [(function, index, 0)] * (6 + rng.next(60))
            out.append((f'{name}-{function}', calls, ()))
    # vectors of each codebook into the floats
    for index, name in enumerate(names):
        calls = []
        for _ in range(16):
            calls.append((MAYBE_START_PACKET, 0, 0))
            for _ in range(4 + rng.next(30)):
                at, length = rng.next(40), rng.next(17)
                calls.append((CODEBOOK_DECODE, index, at | length << 6) if rng.next(2) else (CODEBOOK_DECODE_STEP, index, at | min(length, 6) << 6 | (1 + rng.next(4)) << 12))
        out.append((f'{name}-vectors', calls, ()))
    # everything mixed, with bits read between the symbols and packets left unfinished
    for seed in (1, 2, 3):
        rng = Rng(0xA5A5 + seed)
        calls = []
        for _ in range(900):
            pick = rng.next(100)
            if pick < 6:
                calls.append((MAYBE_START_PACKET, 0, 0))
            elif pick < 9:
                calls.append((FLUSH_PACKET, 0, 0))
            elif pick < 24:
                calls.append((GET_BITS, rng.next(33), 0))
            elif pick < 30:
                calls.append((PREP_HUFFMAN, 0, 0))
            elif pick < 33:
                calls.append((GET8_PACKET, 0, 0))
            elif pick < 55:
                calls.append((DECODE, scalar[rng.next(len(scalar))], 0))
            elif pick < 70:
                calls.append((DECODE_RAW, rng.next(count), 0))
            elif pick < 78:
                calls.append((SCALAR_RAW, rng.next(count), 0))
            elif pick < 90:
                calls.append((CODEBOOK_DECODE, rng.next(count), rng.next(40) | rng.next(17) << 6))
            else:
                calls.append((CODEBOOK_DECODE_STEP, rng.next(count), rng.next(40) | rng.next(7) << 6 | (1 + rng.next(4)) << 12))
        out.append((f'mix-{seed}', calls, ()))
    # packets flushed: on the stream with the unflagged page the flush ends at it (VORBIS_continued_packet_flag_invalid)
    calls = []
    for k in range(40):
        calls += [(MAYBE_START_PACKET, 0, 0)] + [(DECODE, scalar[(k + j) % len(scalar)], 0) for j in range(1 + k % 9)] + [(FLUSH_PACKET, 0, 0)]
    out.append(('flushed', calls, ()))
    # refused: DECODE on the sparse codebook without a code
    none = names.index('none')
    out.append(('decode-none', [(MAYBE_START_PACKET, 0, 0), (DECODE, 0, 0), (DECODE, none, 0), (DECODE, 0, 0)], ('packets', 'cut', 'unflagged')))
    # refused on the stream with the unflagged page: its first packet's 510 bytes as bits, a read past them (the bits run out, the
    # page that follows is not a continued one), then bits for a symbol
    out.append(('past-unflagged', [(MAYBE_START_PACKET, 0, 0)] + [(GET_BITS, 24, 0)] * 170 + [(GET_BITS, 8, 0), (DECODE_RAW, 0, 0), (DECODE_RAW, 0, 0)], ('unflagged',)))
    out.append(('past-unflagged-prep', [(MAYBE_START_PACKET, 0, 0)] + [(GET_BITS, 24, 0)] * 170 + [(GET_BITS, 1, 0), (PREP_HUFFMAN, 0, 0)], ('unflagged',)))
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('vorbis-decode', args)
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files, names = streams()
    for name, data in files.items():
        (folder / f'{name}.ogg').write_bytes(data)
    chosen = scripts(names)
    # the stream with the unflagged page takes the scripts that do not read on past it with the bits run out (the mixes might)
    items = [(name, f'{WORK}/{name}.ogg', index) for name in files for index, (script, _, _) in enumerate(chosen) if name != 'unflagged' or not script.startswith('mix-')]
    refused = lambda item: item[0] in chosen[item[2]][2]
    arrays = '\n'.join(f'static const int script{k}[] = {{ {", ".join(f"{op}, {a}, {b}" for op, a, b in calls)} }};' for k, (_, calls, _) in enumerate(chosen))
    runs = '\n'.join(f'    run({json.dumps(str(ROOT / path))}, script{index}, {len(chosen[index][1])});' for name, path, index in items if not refused((name, path, index)))
    lines = [json.loads(line) for line in probe.native(NATIVE.replace('SCRIPTS', arrays).replace('RUNS', runs), 'reference', extra_flags=FLAGS, link_raylib=False).splitlines()]
    native = iter(lines)
    expected = [[REFUSED] if refused(item) else next(native) for item in items]
    if len(lines) != sum(1 for item in items if not refused(item)):
        raise ProbeFailure(f'vorbis-decode: the reference printed {len(lines)} runs')
    ends = [row[-4:] for row in lines]
    errors = {code for end in ends for code in (0, 21, 32) if end[0] >> (code % 29) & 1}
    if errors != {0, 21, 32} or len({tuple(row) for row in lines}) < len(lines) * 2 // 3 or sum(1 for end in ends if end[2]) < 10 or expected.count([REFUSED]) != 5:
        raise ProbeFailure(f'vorbis-decode: the reference runs are not the ones this probe was written for: errors {sorted(errors)}, {len({tuple(row) for row in lines})} different runs of {len(lines)}')

    def render(selected, gpu):
        defs = ''.join(f'def script{k}() -> +List<U32>:\n  {lists([value for call in calls for value in call])}\n\n' for k, (_, calls, _) in enumerate(chosen))
        cases = ''.join(f'    case {k}: run(script{k}(), 0, 2166136261, 0, coders, state, "[")\n' for k in range(len(chosen) - 1)) + f'    case _: run(script{len(chosen) - 1}(), 0, 2166136261, 0, coders, state, "[")\n'
        ran = f'def ran(which: U32, +coders: +List<D.Coder>, +state: State) -> String:\n  match which:\n{cases}\n'
        body = ''.join(f'    {"Unit <- " if k + 1 < len(selected) else ""}IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result, {index}))\n'
                       for k, (_, path, index) in enumerate(selected))
        return PROGRAM.replace('SCRIPTS', defs + ran) + body

    def parse(text, selected):
        rows = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(rows) != len(selected):
            raise ValueError('vorbis-decode: candidate output did not finish')
        return rows

    lanes = probe.candidates(render, items, batch=40, parse=parse, timeout=1500)

    def describe(index):
        name, _, script = items[index]
        for got in lanes.values():
            a, b = expected[index], got[index]
            if a != b:
                at = next((k for k, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
                return f'{name}, script {chosen[script][0]}: differs by call {min(64 * (at + 1), len(chosen[script][1]))} (stb ends {a[-3:]}, jonlib {b[-3:]})'
        return f'{name}, script {chosen[script][0]}'

    probe.compare(expected, lanes, describe=describe)
    probe.finish(files=len(files), codebooks=len(names), scripts=len(chosen), runs=len(items), refused=expected.count([REFUSED]), calls=sum(len(chosen[index][1]) for _, _, index in items), errors=sorted(errors))


if __name__ == '__main__':
    main()
