#!/usr/bin/env python3
"""Compare src/vorbis_ogg.bend with stb_vorbis's own reading of Ogg data.

Reference. stb_vorbis.c as pinned raylib vendors it, included in the
reference program so that its static functions can be called on a
stb_vorbis set up as stb_vorbis_open_memory sets one up before it starts
decoding: start_page, start_packet, maybe_start_packet, next_segment (after
the skip of the segment's rest the setup does before it), get8_packet_raw,
get8_packet, get32_packet, flush_packet, get_bits, get8, get32, getn and
skip, in the order a script gives. After each call everything the reader
keeps is hashed with the call's answer: the position, eof, the error, the
page's flags, its segment count and the 255 places of its segment table,
next_seg, the sequence number, the known sample position, p_first, the
packet's counters, acc and valid_bits, and the bytes of the last getn. A
run prints the rolling hash every 64 calls and the error, eof and position
it ends with.

Candidate. The same scripts over V.open of the same files.

The scripts: a walk of every packet, the calls start_decoder makes for the
three headers followed by packets read as bits and flushed, packets read
as bits of every width and left unfinished, a packet read byte by byte
across the pages, and seeded mixes of every call. The files: raylib's
target.ogg whole, cut at 24 places, with a page's capture pattern, version
or flags changed, with seeded damage, twice over; and pages built here
around what the format allows and stb_vorbis reads: packets that go on over
pages (with and without the flag that says so), a page without segments
(its packet's length is what the table held before), a page of 255
segments, empty packets, positions unknown, data that ends inside a
segment or a table, bytes between pages. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

import probekit
from probekit import ROOT, ProbeFailure

SOURCE = 'examples/audio/resources/target.ogg'
WORK = '.build/vorbis-ogg-probe/cases'
START_PAGE, START_PACKET, MAYBE_START_PACKET, NEXT_SEGMENT, GET8_PACKET_RAW, GET8_PACKET, GET32_PACKET, FLUSH_PACKET, GET_BITS, GET8, GET32, GETN, SKIP, FIRST_DECODE = range(14)

NATIVE = r'''#include "external/stb_vorbis.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned fnv(unsigned h, unsigned v) { return (h ^ v)*16777619u; }

static unsigned digest(stb_vorbis *f, unsigned answer, const unsigned char *taken, int taken_len)
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
    for (i = 0; i < taken_len; i++) h = fnv(h, taken[i]);
    return h;
}

static void run(const char *path, const int *ops, int count)
{
    static stb_vorbis p;
    unsigned char taken[256], got[256], *data;
    int taken_len = 0, k, len;
    unsigned roll = 2166136261u, seen = 0;
    FILE *file = fopen(path, "rb");
    if (!file) exit(2);
    fseek(file, 0, SEEK_END);
    len = (int)ftell(file);
    fseek(file, 0, SEEK_SET);
    data = (unsigned char *)malloc(len? len : 1);
    if (fread(data, 1, len, file) != (size_t)len) exit(3);
    fclose(file);
    // stb_vorbis_open_memory, up to start_decoder
    vorbis_init(&p, NULL);
    p.stream = data;
    p.stream_end = data + len;
    p.stream_start = p.stream;
    p.stream_len = len;
    p.push_mode = FALSE;
    printf("[");
    for (k = 0; k < count; k++)
    {
        int op = ops[2*k], arg = ops[2*k + 1];
        unsigned answer = 0;
        switch (op)
        {
            case 0: answer = (unsigned)start_page(&p); break;
            case 1: answer = (unsigned)start_packet(&p); break;
            case 2: answer = (unsigned)maybe_start_packet(&p); break;
            case 3: skip(&p, p.bytes_in_seg); p.bytes_in_seg = 0; answer = (unsigned)next_segment(&p); break;   // as start_decoder passes a header's segments
            case 4: answer = (unsigned)get8_packet_raw(&p); break;
            case 5: answer = (unsigned)get8_packet(&p); break;
            case 6: answer = (unsigned)get32_packet(&p); break;
            case 7: flush_packet(&p); break;
            case 8: answer = get_bits(&p, arg); break;
            case 9: answer = get8(&p); break;
            case 10: answer = get32(&p); break;
            case 11: answer = (unsigned)getn(&p, got, arg); if (answer) { memcpy(taken, got, arg); taken_len = arg; } break;
            case 12: skip(&p, arg); break;
            default: p.first_decode = (uint8)arg; break;
        }
        roll = fnv(roll, digest(&p, answer, taken, taken_len));
        seen |= 1u << ((unsigned)p.error%29);
        if (k%64 == 63) printf("%u, ", roll);
    }
    printf("%u, %u, %u, %u, %u]\n", roll, seen, (unsigned)p.error, (unsigned)(p.eof != 0), (unsigned)(p.stream - p.stream_start));
    free(data);
}

SCRIPTS

static const char *paths[] = { PATHS };

int main(void)
{
    for (unsigned i = 0; i < sizeof(paths)/sizeof(paths[0]); i++)
    {
RUNS
    }
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/vorbis_ogg.bend as V

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

# Everything the reader keeps, with the call's answer first.
def digest(reader: V.Reader) -> U32:
  match reader:
    case V.Reader{V.Stream{_, _, +at, _, +eof}, V.Page{+bits, +count, +segments, +next, +sequence, +known_seg, +known_loc}, V.First{+decoding, +start, +end, +sample}, V.Packet{+in_seg, +last, +which, +bytes, +acc, +valid}, +error, +taken, +value}:
      mixed(taken, mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mixed(segments, mix(mix(mix(mix(mix(mix(2166136261, value), at), flag(eof)), error), bits), count)),
        next), sequence), known_seg), known_loc), flag(decoding)), start), end), sample), in_seg), flag(last)), which), bytes), acc), valid))

def step(op: U32, +arg: U32, +reader: V.Reader) -> V.Reader:
  match op:
    case 0: V.page.start(reader)
    case 1: V.packet.start(reader)
    case 2: V.packet.maybe(reader)
    case 3: V.segment.next(V.segment.dropped(reader))
    case 4: V.packet.get8.raw(reader)
    case 5: V.packet.get8(reader)
    case 6: V.packet.get32(reader)
    case 7: V.flush.packet(reader)
    case 8: V.bits.get(arg, reader)
    case 9: V.get8(reader)
    case 10: V.get32(reader)
    case 11: V.getn(reader, arg)
    case 12: V.Reader.answer(V.skip(reader, arg), 0)
    case _: V.Reader.answer(V.first.decode(reader, U32.is_ne(arg, 0)), 0)

def ending(reader: V.Reader, +roll: U32, +seen: U32, +out: String) -> String:
  match reader:
    case V.Reader{V.Stream{_, _, +at, _, +eof}, _, _, _, +error, _, _}:
      out ++ U32.show(roll) ++ ", " ++ U32.show(seen) ++ ", " ++ U32.show(error) ++ ", " ++ U32.show(flag(eof)) ++ ", " ++ U32.show(at) ++ "]"

# A script's calls in turn: the rolling hash every 64, the errors met (a bit
# each) and the end.
def run(ops: +List<U32>, +k: U32, +roll: U32, +seen: U32, +reader: V.Reader, +out: String) -> String:
  match ops:
    case Con{+op, Con{+arg, +rest}}:
      +next = step(op, arg, reader)
      +h = mix(roll, digest(next))
      run(rest, (k + 1 : U32), h, (seen .|. (1 << U32.to_nat((V.Reader.error(next) % 29 : U32))) : U32), next, Bool.pick(String, U32.is_eq((k % 64 : U32), 63), out ++ U32.show(h) ++ ", ", out))
    case _: ending(reader, roll, seen, out)

SCRIPTS
def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(RUNS)

def main() -> IO(Unit):
  do IO<Unit>:
'''


class Rng:
    def __init__(self, seed):
        self.state = seed

    def next(self, bound):
        self.state = (self.state * 1664525 + 1013904223) & 0xFFFFFFFF
        return (self.state >> 8) % bound


def scripts():
    """(name, calls): each call a (function, argument)."""
    walk = [(FIRST_DECODE, 1), (START_PAGE, 0)] + [(MAYBE_START_PACKET, 0), (FLUSH_PACKET, 0)] * 220
    rng = Rng(0x0665)
    # the three headers as start_decoder reads them, then packets as bits
    decoder = [(FIRST_DECODE, 1), (START_PAGE, 0), (GET8, 0), (GETN, 6), (GET32, 0), (GET8, 0), (GET32, 0), (GET32, 0), (GET32, 0), (GET32, 0), (GET8, 0), (GET8, 0),
               (START_PAGE, 0), (START_PACKET, 0), (NEXT_SEGMENT, 0)] + [(GET8_PACKET, 0)] * 7 + [(GET32_PACKET, 0)] + [(GET8_PACKET, 0)] * 44 + [(GET32_PACKET, 0), (GET8_PACKET, 0)]
    decoder += [(NEXT_SEGMENT, 0)] * 3 + [(START_PACKET, 0)] + [(GET8_PACKET, 0)] * 7 + [(GET_BITS, 8), (GET_BITS, 8), (GET_BITS, 8), (GET_BITS, 8), (GET_BITS, 16), (GET_BITS, 24), (GET_BITS, 1), (GET_BITS, 1)]
    decoder += [(GET_BITS, (1, 5, 5, 4, 32, 32, 4, 1, 8, 6, 16, 3, 2, 24)[k % 14]) for k in range(420)] + [(FLUSH_PACKET, 0), (FIRST_DECODE, 0)]
    for _ in range(60):
        decoder += [(MAYBE_START_PACKET, 0), (GET_BITS, 1), (GET_BITS, 1)] + [(GET_BITS, 1 + rng.next(11)) for _ in range(12)] + [(FLUSH_PACKET, 0)]
    # packets left unfinished: the next one begins where the page's segments are, not where the bytes are
    bits = [(START_PAGE, 0)]
    for _ in range(120):
        bits += [(MAYBE_START_PACKET, 0)] + [(GET_BITS, rng.next(33)) for _ in range(1 + rng.next(40))]
    # packets byte by byte, past their ends: two short ones, one of thousands of bytes, then some left unfinished
    raw = [(START_PAGE, 0)]
    for count in [40, 70, 3300] + [150] * 12:
        raw.append((MAYBE_START_PACKET, 0))
        raw += [(GET8_PACKET, 0) if k % 97 == 96 else (GET32_PACKET, 0) if k % 211 == 210 else (GET8_PACKET_RAW, 0) for k in range(count)]
    weights = [(START_PAGE, 4), (START_PACKET, 8), (MAYBE_START_PACKET, 10), (NEXT_SEGMENT, 8), (GET8_PACKET_RAW, 20), (GET8_PACKET, 10), (GET32_PACKET, 6), (FLUSH_PACKET, 6),
               (GET_BITS, 30), (GET8, 6), (GET32, 3), (GETN, 4), (SKIP, 3), (FIRST_DECODE, 2)]
    wheel = [op for op, weight in weights for _ in range(weight)]
    mixes = []
    for seed in (0xA11CE, 0xB0B):
        rng = Rng(seed)
        calls = []
        for _ in range(700):
            op = wheel[rng.next(len(wheel))]
            calls.append((op, rng.next(33) if op == GET_BITS else rng.next(41) if op in (GETN, SKIP) else rng.next(2) if op == FIRST_DECODE else 0))
        mixes.append(calls)
    return [('walk', walk), ('decoder', decoder), ('bits', bits), ('raw', raw), ('mix-1', mixes[0]), ('mix-2', mixes[1])]


def page(flag, granule, sequence, segments, body=None, version=0, serial=0x1D, capture=b'OggS'):
    """An Ogg page: its body is as long as its segments say unless one is given. The checksum is left 0 (nothing here reads it)."""
    if body is None:
        body = bytes((7 * k + sequence) & 0xFF for k in range(sum(segments)))
    return capture + bytes([version, flag]) + struct.pack('<QIII', granule & 0xFFFFFFFFFFFFFFFF, serial, sequence, 0) + bytes([len(segments)]) + bytes(segments) + body


def pages(data):
    """Where each page of a well-formed stream begins and how long it is."""
    out, at = [], 0
    while at < len(data):
        if data[at:at + 4] != b'OggS':
            raise ValueError(f'no page at {at}')
        count = data[at + 26]
        size = 27 + count + sum(data[at + 27:at + 27 + count])
        out.append((at, size))
        at += size
    return out


def built():
    """Streams made of pages built here."""
    unknown = 0xFFFFFFFFFFFFFFFF
    out = {}
    out['spanning'] = page(2, 0, 0, [255, 255]) + page(1, 900, 1, [255, 10, 5, 0, 255, 0]) + page(0, 1800, 2, [3, 255]) + page(1, 2000, 3, [1]) + page(4, 2100, 4, [9])
    out['spanning-unflagged'] = page(2, 0, 0, [255, 255]) + page(0, 900, 1, [255, 10, 5]) + page(0, 1800, 2, [3, 4])
    out['flagged-alone'] = page(2, 0, 0, [30]) + page(1, 10, 1, [20, 21]) + page(0, 20, 2, [22])
    out['no-segments'] = page(2, 0, 0, [30, 31, 32]) + page(0, 5, 1, []) + page(0, 9, 2, [8, 255]) + page(1, 9, 3, []) + page(1, 12, 4, [4, 6])
    out['full-table'] = page(2, 0, 0, [1]) + page(0, 77, 1, [255] * 255) + page(1, 99, 2, [255] * 3 + [17] + [2] * 40)
    out['empty-packets'] = page(2, 0, 0, [0, 0, 5, 0]) + page(0, 4, 1, [0]) + page(0, 8, 2, [255, 0, 0, 255, 255, 0])
    out['unknown-positions'] = page(2, unknown, 0, [30]) + page(0, 0xFFFFFFFF, 1, [255, 255]) + page(1, unknown, 2, [255, 3]) + page(0, 0xFFFFFFFF00000000, 3, [4, 255]) + page(1, 0x100000005, 4, [6])
    out['body-cut'] = page(2, 0, 0, [30]) + page(0, 9, 1, [200, 100, 50])[:-170]
    out['table-cut'] = page(2, 0, 0, [30]) + page(0, 9, 1, [200] * 100, body=b'')[:27 + 60]
    out['junk-between'] = page(2, 0, 0, [30]) + b'junk' + page(0, 9, 1, [12]) + page(0, 9, 2, [255]) + b'Ogg' + page(1, 12, 3, [3])
    out['versions'] = page(2, 0, 0, [30]) + page(0, 9, 1, [12], version=1) + page(0, 9, 2, [5])
    out['captures'] = page(2, 0, 0, [30]) + page(0, 9, 1, [12], capture=b'OggT') + page(0, 9, 2, [5], capture=b'Ogg\x00') + page(0, 9, 3, [5], capture=b'oggS')
    out['many-pages'] = b''.join(page(2 if k == 0 else 0, 100 * k, k, [(k * 37) % 256 for _ in range(k % 5)] + [k]) for k in range(60))
    return out


def cases(source):
    """name -> bytes: raylib's file, its edits, and the built streams."""
    where = pages(source)
    out = {'whole': source, 'empty': b'', 'twice': source + source}
    for cut in (1, 3, 4, 5, 6, 26, 27, 28, 57, 58, 59, 62, 85, 86, 100, 3379, 3380, 3384, 3407, 3420, 5000, 7597, 11800, len(source) - 1):
        out[f'cut-{cut}'] = source[:cut]
    for index, (at, _) in enumerate(where):
        out[f'capture-{index}'] = source[:at + 3] + b'X' + source[at + 4:]
        out[f'continued-{index}'] = source[:at + 5] + bytes([source[at + 5] ^ 1]) + source[at + 6:]
    for index in (1, 3):
        at = where[index][0]
        out[f'version-{index}'] = source[:at + 4] + b'\x02' + source[at + 5:]
        out[f'unknown-{index}'] = source[:at + 6] + b'\xff' * 8 + source[at + 14:]
        out[f'count-{index}'] = source[:at + 26] + bytes([(source[at + 26] + 9) & 0xFF]) + source[at + 27:]
    rng = Rng(0x0DDBA11)
    for index in range(14):
        data = bytearray(source)
        for _ in range(3):
            # the first ten in the pages' headers and tables, the others anywhere
            at, size = where[rng.next(len(where))]
            spot = at + rng.next(27 + source[at + 26]) if index < 10 else rng.next(len(source))
            data[spot] = rng.next(256)
        out[f'damage-{index}'] = bytes(data)
    out.update(built())
    return out


def lists(values):
    """A Bend list of many numbers, in chunks a parser takes."""
    chunks = ', '.join('[' + ', '.join(str(v) for v in values[start:start + 64]) + ']' for start in range(0, len(values), 64))
    return f'List.concat(&2, U32, [{chunks}])'


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('vorbis-ogg', args)
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files = cases((args.raylib_source / SOURCE).read_bytes())
    items = []
    for name, data in files.items():
        (folder / f'{name}.ogg').write_bytes(data)
        items.append((name, f'{WORK}/{name}.ogg'))
    chosen = scripts()
    arrays = '\n'.join(f'static const int script{k}[] = {{ {", ".join(f"{op}, {arg}" for op, arg in calls)} }};' for k, (_, calls) in enumerate(chosen))
    runs = '\n'.join(f'        run(paths[i], script{k}, {len(calls)});' for k, (_, calls) in enumerate(chosen))
    source = NATIVE.replace('SCRIPTS', arrays).replace('PATHS', ', '.join(json.dumps(str(ROOT / path)) for _, path in items)).replace('RUNS', runs)
    lines = [json.loads(line) for line in probe.native(source, 'reference', extra_flags=['-Wno-everything'], link_raylib=False).splitlines()]
    if len(lines) != len(items) * len(chosen):
        raise ProbeFailure(f'vorbis-ogg: the reference printed {len(lines)} runs for {len(items)} files and {len(chosen)} scripts')
    expected = [lines[k * len(chosen):(k + 1) * len(chosen)] for k in range(len(items))]
    ends = {name: {script: tuple(run[-4:]) for (script, _), run in zip(chosen, runs_)} for (name, _), runs_ in zip(items, expected)}
    met = lambda name, script: {code for code in (0, 10, 30, 31, 32) if ends[name][script][0] >> (code % 29) & 1}
    errors = set().union(*(met(name, script) for name in ends for script, _ in chosen))
    # the walk of the whole file ends at its end without an error; the other files show every error the reader has
    if ends['whole']['walk'] != (1, 0, 1, len(files['whole'])) or errors != {0, 10, 30, 31, 32} or ends['empty']['walk'][1:3] != (30, 1) or 31 not in met('versions', 'walk') \
            or 10 not in met('table-cut', 'walk') or 32 not in met('spanning-unflagged', 'walk') or met('spanning', 'walk') != {0} or len({tuple(run) for runs_ in expected for run in runs_}) < len(lines) * 2 // 3:
        raise ProbeFailure(f'vorbis-ogg: the reference runs are not the ones this probe was written for: {ends["whole"]["walk"]}, {ends["empty"]["walk"]}, errors {sorted(errors)}, '
                           f'{sorted(met("versions", "walk"))}, {sorted(met("table-cut", "walk"))}, {sorted(met("spanning-unflagged", "walk"))}, {sorted(met("spanning", "walk"))}, '
                           f'{len({tuple(run) for runs_ in expected for run in runs_})} different runs of {len(lines)}')

    def render(selected, gpu):
        defs = ''.join(f'def script{k}() -> +List<U32>:\n  {lists([value for call in calls for value in call])}\n\n' for k, (_, calls) in enumerate(chosen))
        runs = ' ++ "\\n" ++ '.join(f'run(script{k}(), 0, 2166136261, 0, V.open(bytes), "[")' for k in range(len(chosen)))
        body = ''.join(f'    {"Unit <- " if k + 1 < len(selected) else ""}IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result))\n'
                       for k, (_, path) in enumerate(selected))
        return PROGRAM.replace('SCRIPTS', defs).replace('RUNS', runs) + body

    def parse(text, selected):
        rows = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(rows) != len(selected) * len(chosen):
            raise ValueError('vorbis-ogg: candidate output did not finish')
        return [rows[k * len(chosen):(k + 1) * len(chosen)] for k in range(len(selected))]

    lanes = probe.candidates(render, items, batch=16, parse=parse, timeout=1500)

    def describe(index):
        for got in lanes.values():
            for (script, calls), a, b in zip(chosen, expected[index], got[index]):
                if a != b:
                    at = next((k for k, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
                    return f'{items[index][0]}, script {script}: differs by call {min(64 * (at + 1), len(calls))} (stb ends {a[-3:]}, jonlib {b[-3:]})'
        return items[index][0]

    probe.compare(expected, lanes, describe=describe)
    probe.finish(files=len(items), scripts=len(chosen), runs=len(lines), calls=len(items) * sum(len(calls) for _, calls in chosen), errors=sorted(errors))


if __name__ == '__main__':
    main()
