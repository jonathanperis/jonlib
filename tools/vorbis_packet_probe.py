#!/usr/bin/env python3
"""Compare src/vorbis_packet.bend with stb_vorbis's vorbis_decode_packet.

Reference. stb_vorbis.c as pinned raylib vendors it, included in the
reference program: start_decoder on a stream, then vorbis_decode_packet
called 120 times (the file has 105 packets). After each call its answer, the block's length and where
its left and right parts begin are hashed with everything the reader
keeps, the sample position (current_loc, whether it is known, the samples
still to drop) and every float of the channels' buffers, a block of the
long size each. A run prints the rolling hash every 8 calls and how it
ends.

Candidate. K.open of the same file under the host's libm profile, then
K.packet.decode as many times: the same hashes.

The files: raylib's target.ogg (two channels, blocks of 512 and 1024,
coupled, floors and residues of type 2 as libvorbis writes them), copies
cut inside its audio pages, and copies with seeded damage in its packets'
bytes: one to four bits changed, and runs of bytes replaced. The damage is
in the packets alone (the pages' headers and segment tables are whole), so
that stb_vorbis meets none of the things the port refuses: this file's
floors have no codebook with more entries than their range, and its
residues end with their blocks, in partitions its codebooks' dimensions
divide. CPU-1, CPU-2 and JavaScript lanes.
"""
import json

from conformance import gradient_reference
import probekit
from probekit import ROOT, ProbeFailure
from vorbis_codebook_probe import Rng
from vorbis_ogg_probe import pages

SOURCE = 'examples/audio/resources/target.ogg'
WORK = '.build/vorbis-packet-probe/cases'
FLAGS = ['-ffp-contract=off', '-D_DEFAULT_SOURCE', '-Wno-everything']
CALLS = 120

NATIVE = r'''#include "external/stb_vorbis.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned fnv(unsigned h, unsigned v) { return (h ^ v)*16777619u; }

static unsigned digest(stb_vorbis *f, int answer, int len, int left, int right)
{
    unsigned h = fnv(2166136261u, (unsigned)answer);
    int i, j;
    h = fnv(h, (unsigned)len); h = fnv(h, (unsigned)left); h = fnv(h, (unsigned)right);
    h = fnv(h, (unsigned)(f->stream - f->stream_start)); h = fnv(h, f->eof != 0); h = fnv(h, (unsigned)f->error);
    h = fnv(h, f->page_flag); h = fnv(h, (unsigned)f->segment_count);
    for (i = 0; i < 255; i++) h = fnv(h, f->segments[i]);
    h = fnv(h, (unsigned)f->next_seg); h = fnv(h, (unsigned)f->last_page); h = fnv(h, (unsigned)f->end_seg_with_known_loc); h = fnv(h, f->known_loc_for_packet);
    h = fnv(h, f->first_decode != 0); h = fnv(h, f->p_first.page_start); h = fnv(h, f->p_first.page_end); h = fnv(h, f->p_first.last_decoded_sample);
    h = fnv(h, f->bytes_in_seg); h = fnv(h, f->last_seg != 0); h = fnv(h, (unsigned)f->last_seg_which); h = fnv(h, (unsigned)f->packet_bytes);
    h = fnv(h, f->acc); h = fnv(h, (unsigned)f->valid_bits);
    h = fnv(h, f->current_loc); h = fnv(h, f->current_loc_valid != 0); h = fnv(h, (unsigned)f->discard_samples_deferred);
    for (j = 0; j < f->channels; j++) for (i = 0; i < f->blocksize_1; i++) { unsigned w; memcpy(&w, &f->channel_buffers[j][i], 4); h = fnv(h, w); }
    return h;
}

static void run(const char *path)
{
    static stb_vorbis p;
    unsigned char *data;
    int k, len, fine = 0;
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
    printf("[");
    for (k = 0; k < CALLS; k++)
    {
        int length = 0, left = 0, right = 0;
        int answer = vorbis_decode_packet(&p, &length, &left, &right);
        // what a call that fails leaves in the three is not the packet's
        if (!answer) length = left = right = 0;
        fine += answer != 0;
        roll = fnv(roll, digest(&p, answer != 0, length, left, right));
        seen |= 1u << ((unsigned)p.error%29);
        if (k%8 == 7) printf("%u, ", roll);
    }
    printf("%u, %d, %u, %u, %u, %u]\n", roll, fine, seen, (unsigned)p.error, (unsigned)(p.eof != 0), (unsigned)(p.stream - p.stream_start));
    free(data);
}

int main(void)
{
RUNS
    return 0;
}
'''.replace('CALLS', str(CALLS))

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/vorbis_ogg.bend as V
import ../../src/vorbis_packet.bend as K
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

# The answer, the block's length and parts, everything the reader keeps, the sample position and the channels' floats.
def digest(reader: V.Reader, +fine: Bool, +len: U32, +left: U32, +right: U32, +loc: U32, +known: Bool, +discard: U32, +rows: +List<R.Row>) -> U32:
  match reader:
    case V.Reader{V.Stream{_, _, +at, _, +eof}, V.Page{+bits, +count, +segments, +next, +sequence, +known_seg, +known_loc}, V.First{+decoding, +start, +end, +sample}, V.Packet{+in_seg, +last, +which, +bytes, +acc, +valid}, +error, _, _}:
      mixed.rows(rows, mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mix(mixed(segments, mix(mix(mix(mix(mix(mix(mix(mix(mix(2166136261, flag(fine)), Bool.pick(U32, fine, len, 0)), Bool.pick(U32, fine, left, 0)),
        Bool.pick(U32, fine, right, 0)), at), flag(eof)), error), bits), count)), next), sequence), known_seg), known_loc), flag(decoding)), start), end), sample), in_seg), flag(last)), which), bytes), acc), valid), loc), flag(known)),
        discard))

def packet.digest(packet: K.Packet) -> U32:
  match packet:
    case K.Packet{K.State{+reader, +rows, +loc, +known, +discard}, +fine, +len, +left, +right}: digest(reader, fine, len, left, right, loc, known, discard, rows)

def packet.state(packet: K.Packet) -> K.State:
  K.Packet{state, _, _, _, _} = packet
  state

def packet.fine(packet: K.Packet) -> U32:
  K.Packet{_, fine, _, _, _} = packet
  flag(fine)

def ending(reader: V.Reader, +roll: U32, +fine: U32, +seen: U32, +out: String) -> String:
  match reader:
    case V.Reader{V.Stream{_, _, +at, _, +eof}, _, _, _, +error, _, _}:
      Bool.pick(String, (error >= 1000 : U32), "[" ++ U32.show(error) ++ "]",
        out ++ U32.show(roll) ++ ", " ++ U32.show(fine) ++ ", " ++ U32.show(seen) ++ ", " ++ U32.show(error) ++ ", " ++ U32.show(flag(eof)) ++ ", " ++ U32.show(at) ++ "]")

# The packets in turn: the rolling hash every 8, how many were decoded, the errors met and the end.
def run(n: Nat, +k: U32, +roll: U32, +fine: U32, +seen: U32, +plan: K.Plan, +state: K.State, +out: String) -> String:
  match n:
    case 0n: ending(K.State.reader(state), roll, fine, seen, out)
    case 1n+rest:
      +next = K.packet.decode(plan, state)
      +h = mix(roll, packet.digest(next))
      run(rest, (k + 1 : U32), h, (fine + packet.fine(next) : U32), (seen .|. (1 << U32.to_nat((V.Reader.error(K.State.reader(packet.state(next))) % 29 : U32))) : U32), plan, packet.state(next),
        Bool.pick(String, U32.is_eq((k % 8 : U32), 7), out ++ U32.show(h) ++ ", ", out))

def opened(decoder: K.Decoder) -> String:
  match decoder:
    case K.Closed{_}: "[]"
    case K.Opened{+plan, +state}: run(CALLSn, 0, 2166136261, 0, 0, plan, state, "[")

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(opened(K.open(M.LIBM{}, bytes)))

def main() -> IO(Unit):
  do IO<Unit>:
'''.replace('CALLS', str(CALLS))


def bodies(data):
    """Where the packets' bytes of the pages after the headers' are: (start, end) of each page's body."""
    out = []
    for at, size in pages(data)[2:]:
        count = data[at + 26]
        out.append((at + 27 + count, at + size))
    return out


def cases(source):
    """name -> stream: raylib's file, cut and damaged in its packets."""
    out = {'whole': source}
    where = bodies(source)
    for cut in (where[0][0] + 1, where[0][0] + 700, where[1][0] + 2000, len(source) - 3):
        out[f'cut-{cut}'] = source[:cut]
    rng = Rng(0xA0D10)
    for index in range(4):
        data = bytearray(source)
        for _ in range(1 + index % 4):
            start, end = where[rng.next(len(where))]
            data[start + rng.next(end - start)] ^= 1 << rng.next(8)
        out[f'bits-{index}'] = bytes(data)
    for index in range(3):
        data = bytearray(source)
        start, end = where[index % len(where)]
        at = start + rng.next(end - start - 64)
        for k in range(4 + rng.next(60)):
            data[at + k] = rng.next(256)
        out[f'bytes-{index}'] = bytes(data)
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('vorbis-packet', args)
    libm = gradient_reference()
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files = cases((args.raylib_source / SOURCE).read_bytes())
    items = []
    for name, data in files.items():
        (folder / f'{name}.ogg').write_bytes(data)
        items.append((name, f'{WORK}/{name}.ogg'))
    runs = '\n'.join(f'    run({json.dumps(str(ROOT / path))});' for _, path in items)
    expected = [json.loads(line) for line in probe.native(NATIVE.replace('RUNS', runs), 'reference', extra_flags=FLAGS, link_raylib=False).splitlines()]
    if len(expected) != len(items):
        raise ProbeFailure(f'vorbis-packet: the reference printed {len(expected)} runs for {len(items)} files')
    ends = {name: row[-5:] for (name, _), row in zip(items, expected)}
    # the whole file is decoded to its end without an error; no damaged copy decodes as it does (a packet whose bits are others is
    # decoded all the same: stb_vorbis has few ways to refuse one), and a cut copy has fewer packets
    decoded = ends['whole'][0]
    if decoded < 80 or ends['whole'][1:] != [1, 0, 1, len(files['whole'])] or len({tuple(row) for row in expected}) != len(expected) or min(end[0] for end in ends.values()) > decoded // 2:
        raise ProbeFailure(f'vorbis-packet: the reference runs are not the ones this probe was written for: {ends}')

    def render(selected, gpu):
        return PROGRAM.replace('LIBM', libm) + ''.join(
            f'    {"Unit <- " if k + 1 < len(selected) else ""}IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result))\n' for k, (_, path) in enumerate(selected))

    def parse(text, selected):
        rows = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(rows) != len(selected):
            raise ValueError('vorbis-packet: candidate output did not finish')
        return rows

    lanes = probe.candidates(render, items, batch=4, parse=parse, timeout=1700)

    def describe(index):
        for got in lanes.values():
            a, b = expected[index], got[index]
            if a != b:
                at = next((k for k, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
                return f'{items[index][0]}: differs by packet {min(8 * (at + 1), CALLS)} (stb ends {a[-5:]}, jonlib {b[-5:]})'
        return items[index][0]

    probe.compare(expected, lanes, describe=describe)
    probe.finish(files=len(items), calls=CALLS * len(items), decoded=sum(end[0] for end in ends.values()), whole=decoded, libm=libm)


if __name__ == '__main__':
    main()
