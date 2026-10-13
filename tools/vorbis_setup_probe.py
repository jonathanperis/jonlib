#!/usr/bin/env python3
"""Compare src/vorbis_setup.bend with stb_vorbis's start_decoder, as far as
the codebooks.

Reference. stb_vorbis.c as pinned raylib vendors it, included in the
reference program: start_decoder on a stb_vorbis set up as
stb_vorbis_open_memory sets one up. Where it fails before it comes to the
floors (floor_config is not allocated yet) the row is its error code;
otherwise the row is what the identification header gave (channels, sample
rate, block sizes) and every codebook: dimensions, entries, whether it is
sparse, the lookup's type, value count, bits, sequence flag, least value
and step (the floats' bits), the multiplicands (their count and the hash of
their bits) and the tables the codebook gate compares (codewords, the
sorted table, the lengths kept, the accelerated table).

Candidate. S.setup.codebooks on the same files: the same row, or the
refusal.

The port refuses what stb_vorbis answers with something a port cannot
give: a lookup1_values that hangs on the C library or is undefined,
entries * dimensions past the ints, an allocation of more than 16 MiB, a
codebook over the port's budget of 2^19 entries. stb_vorbis is not run on
those files. To know them this probe reads the headers itself (`model`),
with the rules restated, and its reading is held against stb_vorbis's too:
the same failures with the same codes, the same fields.

The files: raylib's target.ogg, whole and with seeded damage inside its
codebooks; and streams built here: codebooks with lengths given one by
one, sparse (kept sparse, and with enough codes to stop being), ordered in
runs, without a lookup and with one of each type, in a sequence and not,
of 1 to 16 bits a value, of 1 to 9 dimensions, with lengths that are no
tree, a length of 32, runs past the entries, no entries, no dimensions, a
wrong sync pattern or lookup type, transfers that are not 0; every test of
the identification header; comment headers with vendor strings and
comments of every kind of length (past the packet, negative, over the
budget), lists of every kind of count, a packet that is empty, missing or
not a comment header. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

import probekit
from probekit import ROOT, ProbeFailure
from vorbis_codebook_probe import Rng, lookup1, tree, unpacked
from vorbis_ogg_probe import page

SOURCE = 'examples/audio/resources/target.ogg'
WORK = '.build/vorbis-setup-probe/cases'
FLAGS = ['-ffp-contract=off', '-Wno-everything']
GOING, FAILED, REFUSED = 0, 1, 2
BUDGET = 1 << 24                                                              # bytes of one allocation
ENTRIES = 1 << 19                                                             # a codebook's entries

NATIVE = r'''#include "external/stb_vorbis.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned fnv(unsigned h, unsigned v) { return (h ^ v)*16777619u; }

// A codebook as start_decoder left it. `count` is how many multiplicands it has, which the struct does not keep.
static void codebook(Codebook *c, int count, int first)
{
    unsigned values = 2166136261u, codes = 2166136261u, sorted = 2166136261u, symbols = 2166136261u, kept = 2166136261u, fast = 2166136261u, low, step;
    int j, rows = c->sparse? c->sorted_entries : c->entries;
    // the count is the lookup's own (type 2 as read) or a value for each row's dimension (type 1, expanded)
    if (count != 0 && (unsigned)count != c->lookup_values && (long long)count != (long long)rows*c->dimensions) exit(5);
    if ((count != 0) != (c->multiplicands != NULL)) exit(6);
    for (j = 0; j < count; ++j) { unsigned w; memcpy(&w, &c->multiplicands[j], 4); values = fnv(values, w); }
    if (!c->sparse) for (j = 0; j < c->entries; ++j) if (c->codeword_lengths[j] != NO_CODE) codes = fnv(codes, c->codewords[j]);
    for (j = 0; j < c->sorted_entries; ++j) { sorted = fnv(sorted, c->sorted_codewords[j]); symbols = fnv(symbols, (unsigned)c->sorted_values[j]); }
    if (c->sorted_entries && c->sorted_codewords[c->sorted_entries] != 0xffffffff) exit(7);
    for (j = 0; j < rows; ++j) kept = fnv(kept, c->codeword_lengths[j]);
    for (j = 0; j < FAST_HUFFMAN_TABLE_SIZE; ++j) fast = fnv(fast, (unsigned)(int)c->fast_huffman[j]);
    memcpy(&low, &c->minimum_value, 4);
    memcpy(&step, &c->delta_value, 4);
    printf("%s[%d, %d, %d, %d, %u, %d, %d, %u, %u, %d, %u, %u, %d, %u, %u, %u, %u]", first? "" : ", ", c->dimensions, c->entries, c->sparse, c->lookup_type, c->lookup_values, c->value_bits, c->sequence_p,
           low, step, count, values, codes, c->sorted_entries, sorted, symbols, kept, fast);
}

static void run(const char *path, const int *counts, int books)
{
    static stb_vorbis p;
    unsigned char *data;
    int len, i;
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
    if (!start_decoder(&p) && p.floor_config == NULL) { printf("[1, %d]\n", (int)p.error); return; }
    if (p.codebook_count != books) exit(4);
    printf("[0, [%d, %u, %d, %d], [", p.channels, p.sample_rate, p.blocksize_0, p.blocksize_1);
    for (i = 0; i < p.codebook_count; ++i) codebook(p.codebooks + i, counts[i], i == 0);
    printf("]]\n");
}

COUNTS

int main(void)
{
RUNS
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/vorbis_codebook.bend as C
import ../../src/vorbis_setup.bend as S

def fnv(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: fnv(rest, ((h .^. x) * 16777619 : U32))

def fnv.first(n: Nat, xs: +List<U32>, +h: U32) -> U32:
  match n:
    case 0n: h
    case 1n+k:
      match xs:
        case Nil{}: h
        case Con{+x, rest}: fnv.first(k, rest, ((h .^. x) * 16777619 : U32))

def fnv.coded(lengths: +List<U32>, codewords: +List<U32>, +h: U32) -> U32:
  match lengths codewords:
    case Con{+len, +more} Con{+code, +rest}: fnv.coded(more, rest, Bool.pick(U32, U32.is_eq(len, 255), h, ((h .^. code) * 16777619 : U32)))
    case _ _: h

def fnv.floats(xs: +List<F32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, +rest}: fnv.floats(rest, ((h .^. F32.bits(x)) * 16777619 : U32))

def floats.count(xs: +List<F32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: floats.count(rest, (n + 1 : U32))

def flag(on: Bool) -> U32:
  match on:
    case True{}: 1
    case False{}: 0

def row(book: S.Codebook) -> String:
  match book:
    case S.Codebook{+dimensions, +entries, C.Book{+sparse, _, +lengths, +codewords, +sorted, +sorted_codewords, +sorted_values, +fast}, +lookup, +minimum, +delta, +value_bits, +sequence, +lookup_values, +multiplicands}:
      "[" ++ U32.show(dimensions) ++ ", " ++ U32.show(entries) ++ ", " ++ U32.show(flag(sparse)) ++ ", " ++ U32.show(lookup) ++ ", " ++ U32.show(lookup_values) ++ ", " ++ U32.show(value_bits) ++ ", " ++ U32.show(flag(sequence))
        ++ ", " ++ U32.show(F32.bits(minimum)) ++ ", " ++ U32.show(F32.bits(delta)) ++ ", " ++ U32.show(floats.count(multiplicands, 0)) ++ ", " ++ U32.show(fnv.floats(multiplicands, 2166136261))
        ++ ", " ++ U32.show(Bool.pick(U32, sparse, 2166136261, fnv.coded(lengths, codewords, 2166136261))) ++ ", " ++ U32.show(sorted) ++ ", " ++ U32.show(fnv.first(U32.to_nat(sorted), sorted_codewords, 2166136261))
        ++ ", " ++ U32.show(fnv(sorted_values, 2166136261)) ++ ", " ++ U32.show(fnv(lengths, 2166136261)) ++ ", " ++ U32.show(fnv(fast, 2166136261)) ++ "]"

def rows(books: +List<S.Codebook>, +first: Bool, +out: String) -> String:
  match books:
    case Nil{}: out
    case Con{+book, +rest}: rows(rest, False{}, out ++ Bool.pick(String, first, "", ", ") ++ row(book))

def told(setup: S.Setup) -> String:
  match setup:
    case S.Setup{_, S.Going{}, S.Head{+channels, +rate, +small, +large}, +books}:
      "[0, [" ++ U32.show(channels) ++ ", " ++ U32.show(rate) ++ ", " ++ U32.show(small) ++ ", " ++ U32.show(large) ++ "], [" ++ rows(books, True{}, "") ++ "]]"
    case S.Setup{_, S.Failed{+code}, _, _}: "[1, " ++ U32.show(code) ++ "]"
    case S.Setup{_, S.Refused{+why}, _, _}: "[2, " ++ U32.show(why) ++ "]"

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(told(S.setup.codebooks(bytes)))

def main() -> IO(Unit):
  do IO<Unit>:
'''


# -----------------------------------------------------------------------------
# Streams built here

class Writer:
    """Bits as Vorbis packs them: the first one is the lowest of the first byte."""
    def __init__(self, start=b''):
        self.start, self.acc, self.count = bytes(start), 0, 0

    def put(self, value, bits):
        self.acc |= (value & ((1 << bits) - 1)) << self.count
        self.count += bits
        return self

    def bytes(self):
        return self.start + self.acc.to_bytes((self.count + 7) // 8, 'little')


def identification(channels=2, rate=44100, small=8, large=11, framing=1, version=0, kind=1, name=b'vorbis'):
    """The identification header's 30 bytes."""
    return bytes([kind]) + name + struct.pack('<IBIIIIBB', version, channels, rate, 0, 128000, 0, small | large << 4, framing)


def comment(vendor=b'jonlib', comments=(b'TITLE=probe',), framing=1, kind=3, name=b'vorbis', vendor_length=None, count=None, lengths=None, tail=None):
    """A comment header. The lengths and the count it states can be other than what it holds."""
    out = bytes([kind]) + name + struct.pack('<I', len(vendor) if vendor_length is None else vendor_length) + vendor
    out += struct.pack('<I', len(comments) if count is None else count)
    for index, text in enumerate(comments):
        out += struct.pack('<I', len(text) if lengths is None else lengths[index]) + text
    return out + (bytes([framing]) if tail is None else tail)


def ilog(n):
    return n.bit_length()


def book(dimensions, lengths=None, runs=None, sparse=False, lookup=None, sync=(0x42, 0x43, 0x56), entries=None):
    """A codebook's bits. `lengths` are one a symbol (255 for none, which only a sparse codebook can say), `runs` (first length, counts)
    are ordered lengths. `lookup` is (type, least, step, bits of a value, sequence, values)."""
    def write(w):
        count = entries if entries is not None else len(lengths) if runs is None else sum(runs[1])
        for value in sync:
            w.put(value, 8)
        w.put(dimensions, 16).put(count, 24).put(1 if runs is not None else 0, 1)
        if runs is not None:
            first, counts = runs
            w.put(first - 1, 5)
            given = 0
            for run in counts:
                w.put(run, ilog(count - given))
                given += run
        else:
            w.put(1 if sparse else 0, 1)
            for length in lengths:
                if sparse:
                    w.put(0 if length == 255 else 1, 1)
                if length != 255:
                    w.put(length - 1, 5)
        if lookup is None:
            w.put(0, 4)
        else:
            kind, least, step, bits, sequence, values = lookup
            w.put(kind, 4)
            if kind:
                w.put(least, 32).put(step, 32).put(bits - 1, 4).put(1 if sequence else 0, 1)
                for value in values:
                    w.put(value, bits)
    return write


def setup(books, transfers=(0,), kind=5, name=b'vorbis', count=None):
    """A setup header as far as its time domain transfers. What follows is not written: read as zeros it is one floor of type 0,
    which stb_vorbis does not decode (VORBIS_feature_not_supported, after the codebooks)."""
    w = Writer(bytes([kind]) + name)
    w.put((len(books) if count is None else count) - 1, 8)
    for write in books:
        write(w)
    w.put(len(transfers) - 1, 6)
    for value in transfers:
        w.put(value, 16)
    return w.bytes()


def paged(packets, sequence=1):
    """Packets laid over pages of up to 255 segments, a page that begins inside a packet flagged as continued."""
    segments = [(size, k == 0) for packet in packets for k, size in enumerate([255] * (len(packet) // 255) + [len(packet) % 255])]
    body, out, at = b''.join(packets), b'', 0
    for start in range(0, len(segments), 255):
        chunk = segments[start:start + 255]
        size = sum(length for length, _ in chunk)
        out += page(0 if chunk[0][1] else 1, 0, sequence, [length for length, _ in chunk], body=body[at:at + size])
        at, sequence = at + size, sequence + 1
    return out


def stream(first=None, second=None, third=None, flag=2, packets=None):
    """An Ogg stream of the three headers: the first alone on its page."""
    first = identification() if first is None else first
    rest = [comment() if second is None else second, setup([book(1, [1, 1])]) if third is None else third] if packets is None else packets
    return page(flag, 0, 0, [len(first)], body=first) + paged(rest)


# -----------------------------------------------------------------------------
# The headers read here

class Packet:
    """A packet read as stb_vorbis reads one: bytes (EOP, -1, at the end) and bits (0 from the end on)."""
    def __init__(self, data):
        self.data, self.at, self.acc, self.valid = data, 0, 0, 0

    def raw(self):
        if self.at >= len(self.data):
            return -1
        self.at += 1
        return self.data[self.at - 1]

    def byte(self):
        self.valid = 0
        return self.raw()

    def word(self):
        return sum(self.byte() << shift for shift in (0, 8, 16, 24)) & 0xFFFFFFFF

    def skip(self, count):
        if count:
            self.valid = 0
        self.at = min(len(self.data), self.at + count)

    def bits(self, n):
        if self.valid < 0:
            return 0
        if self.valid < n:
            if n > 24:
                low = self.bits(24)
                return (low + (self.bits(n - 24) << 24)) & 0xFFFFFFFF
            if self.valid == 0:
                self.acc = 0
            while self.valid < n:
                z = self.raw()
                if z < 0:
                    self.valid = -1
                    return 0
                self.acc += z << self.valid
                self.valid += 8
        z = self.acc & ((1 << n) - 1)
        self.acc >>= n
        self.valid -= n
        return z


def leafed(lengths):
    """Whether compute_codewords finds a leaf for every symbol with a code."""
    coded = [length for length in lengths if length != 255]
    if not coded:
        return True
    available = [0] * 33
    for level in range(1, coded[0] + 1):
        available[level] = 1 << (32 - level)
    for length in coded[1:]:
        z = length
        while z > 0 and not available[z]:
            z -= 1
        if z == 0:
            return False
        leaf, available[z] = available[z], 0
        for level in range(length, z, -1):
            available[level] = leaf + (1 << (32 - level))
    return True


def sized(length):
    """A length that sizes an allocation of length + 1 bytes."""
    return (FAILED, 3) if length >= 1 << 31 else (REFUSED, 3) if length > BUDGET else None


def read_book(p):
    """A codebook from the setup's bits: a failure or a refusal, or its fields."""
    for wanted in (0x42, 0x43, 0x56):
        if p.bits(8) != wanted:
            return (FAILED, 20)
    low = p.bits(8)
    dimensions = (p.bits(8) << 8) + low
    low, middle = p.bits(8), p.bits(8)
    entries = (p.bits(8) << 16) + (middle << 8) + low
    ordered = p.bits(1)
    sparse = 0 if ordered else p.bits(1)
    if dimensions == 0 and entries != 0:
        return (FAILED, 20)
    if entries == 0:
        return (FAILED, 3)                                                    # an allocation of no byte is NULL
    if entries > ENTRIES:
        return (REFUSED, 4)
    lengths = []
    if ordered:
        length = p.bits(5) + 1
        while len(lengths) < entries:
            count = p.bits(ilog(entries - len(lengths)))
            if length >= 32 or len(lengths) + count > entries:
                return (FAILED, 20)
            lengths += [length] * count
            length += 1
    else:
        for _ in range(entries):
            if sparse and not p.bits(1):
                lengths.append(255)
                continue
            lengths.append(p.bits(5) + 1)
            if lengths[-1] == 32:
                return (FAILED, 20)
    total = sum(1 for length in lengths if length != 255)
    sparse = 1 if sparse and total < entries >> 2 else 0
    rows = total if sparse else entries
    if not leafed(lengths):
        return (FAILED, 20)
    kind = p.bits(4)
    if kind > 2:
        return (FAILED, 20)
    if kind == 0:
        return dict(dimensions=dimensions, entries=entries, sparse=sparse, lookup=0, values=0, bits=0, sequence=0, least=0, step=0, count=0)
    least, step = unpacked(p.bits(32)), unpacked(p.bits(32))
    bits = p.bits(4) + 1
    sequence = p.bits(1)
    if kind == 1:
        values = lookup1(entries, dimensions)
        if values is None:
            return (REFUSED, 1)
    else:
        values = entries * dimensions
        if values >= 1 << 31:
            return (REFUSED, 2)
    if values <= 0:
        return (FAILED, 20)
    if (kind == 2 and values * 4 > BUDGET) or (kind == 1 and rows * dimensions * 4 > BUDGET):
        return (REFUSED, 3)
    for _ in range(values):
        p.bits(bits)
    count = values if kind == 2 else rows * dimensions
    # a type 1 lookup is expanded to type 2, unless its codebook has no row to expand
    return dict(dimensions=dimensions, entries=entries, sparse=sparse, lookup=2 if count else 1, values=values, bits=bits, sequence=sequence, least=least, step=step, count=count)


def model(data):
    """What the port makes of a stream whose pages are well formed: (FAILED, code), (REFUSED, why) or (GOING, head, codebooks)."""
    if data[:4] != b'OggS' or data[4] != 0:
        raise ValueError('the model reads well formed pages')
    flag, count = data[5], data[26]
    table = data[27:27 + count]
    if not flag & 2 or flag & 4 or flag & 1 or count != 1:
        return (FAILED, 34)
    body = data[27 + count:27 + count + table[0]]
    if table[0] != 30:
        return (FAILED, 38 if table[0] == 64 and body[:8] == b'fishead\x00' else 34)
    if not body or body[0] != 1:
        return (FAILED, 34)
    if len(body) < 7:
        return (FAILED, 10)                                                   # the data ends in the name
    if body[1:7] != b'vorbis':
        return (FAILED, 34)
    # past the data's end the bytes are zeros
    version, channels, rate, _, _, _, sizes, framing = struct.unpack('<IBIIIIBB', (body + bytes(30))[7:30])
    if version != 0 or channels == 0:
        return (FAILED, 34)
    if channels > 16:
        return (FAILED, 5)
    if rate == 0:
        return (FAILED, 34)
    small, large = sizes & 15, sizes >> 4
    if not 6 <= small <= 13 or not 6 <= large <= 13 or small > large:
        return (FAILED, 20)
    if not framing & 1:
        return (FAILED, 34)
    # the packets of the pages after the first
    packets, current, at = [], b'', 27 + count + table[0]
    while at < len(data):
        if data[at:at + 4] != b'OggS' or data[at + 4] != 0:
            raise ValueError('the model reads well formed pages')
        count = data[at + 26]
        table, at = data[at + 27:at + 27 + count], at + 27 + count
        for length in table:
            current, at = current + data[at:at + length], at + length
            if length < 255:
                packets.append(current)
                current = b''
    if not packets:
        return (FAILED, 30)                                                   # no page begins
    if not packets[0]:
        return (FAILED, 0)                                                    # a packet without a first segment: FALSE, and no error
    p = Packet(packets[0])
    if p.byte() != 3 or bytes(p.byte() & 255 for _ in range(6)) != b'vorbis':
        return (FAILED, 20)
    length = p.word()
    if sized(length):
        return sized(length)
    p.skip(length)
    listed = p.word()
    if 0 < listed < 1 << 31:
        if listed > BUDGET // 8:
            return (FAILED, 3) if 1 << 28 <= listed < 1 << 29 else (REFUSED, 3)
        for _ in range(listed):
            length = p.word()
            if sized(length):
                return sized(length)
            p.skip(length)
    if not p.byte() & 1:
        return (FAILED, 20)
    if len(packets) < 2:
        return (FAILED, 30)
    p = Packet(packets[1])
    if p.byte() != 5 or bytes(p.byte() & 255 for _ in range(6)) != b'vorbis':
        return (FAILED, 20)
    books = []
    for _ in range(p.bits(8) + 1):
        made = read_book(p)
        if isinstance(made, tuple):
            return made
        books.append(made)
    for _ in range(p.bits(6) + 1):
        if p.bits(16) != 0:
            return (FAILED, 20)
    return (GOING, [channels, rate, 1 << small, 1 << large], books)


def codebooks_end(data):
    """Where the codebooks of a stream's setup header end, as a position in the stream (for a first page of 58 bytes and one page after it)."""
    count = data[58 + 26]
    table = data[58 + 27:58 + 27 + count]
    first = next(k for k, length in enumerate(table) if length < 255)
    start = 58 + 27 + count + sum(table[:first + 1])
    p = Packet(data[start:])
    for _ in range(7):
        p.byte()
    for _ in range(p.bits(8) + 1):
        if isinstance(read_book(p), tuple):
            raise ValueError('the stream has a codebook the model does not read')
    return start + 8, start + p.at


# -----------------------------------------------------------------------------
# The cases

def words(rng, count, bits):
    return [rng.next(1 << bits) for _ in range(count)]


def built():
    """name -> stream, built from headers."""
    rng = Rng(0x5E7B00C)
    one, half, big, tiny = 788 << 21 | 1, 787 << 21 | 1, 800 << 21 | 0x155555, 0x80000000 | 640 << 21 | 3
    plain = [3, 3, 3, 3, 3, 3, 3, 3]
    deep = tree(600, rng)
    out = {}

    def add(name, **parts):
        out[name] = stream(**parts)

    add('least')
    # the lengths: one by one, sparse, ordered
    add('plain', third=setup([book(2, plain), book(1, [1, 2, 3, 3]), book(3, deep), book(1, [5])]))
    holes = [length if rng.next(5) == 0 else 255 for length in tree(900, rng)]
    add('sparse', third=setup([book(1, holes, sparse=True), book(2, [255] * 40 + [1] + [255] * 40, sparse=True), book(1, [255] * 12, sparse=True)]))
    add('sparse-full', third=setup([book(1, plain, sparse=True), book(1, [3, 3, 255, 3, 255, 3, 3, 255], sparse=True), book(1, [255, 255, 255], sparse=True), book(4, [255, 255, 255, 255, 1], sparse=True)]))
    add('ordered', third=setup([book(1, runs=(1, [1, 1, 2, 4, 8, 16])), book(2, runs=(3, [8])), book(1, runs=(2, [0, 0, 5, 0, 12])), book(1, runs=(31, [1])), book(1, runs=(5, [0] * 20 + [3]))]))
    add('ordered-large', third=setup([book(1, runs=(12, [4096])), book(2, runs=(11, [1024, 2048]))]))
    # the lookups
    seven = [3] * 4 + [4] * 8
    add('lookup-1', third=setup([book(2, [4] * 16, lookup=(1, 0, one, 4, False, words(rng, 4, 4))), book(3, [5] * 27 + [255] * 0, lookup=(1, tiny, half, 9, False, words(rng, 3, 9))),
                                 book(1, seven, lookup=(1, big, big, 16, False, words(rng, 12, 16))), book(8, [1], lookup=(1, 0, 0, 1, False, [1])),
                                 book(4, deep[:81] + [255] * 0, lookup=None), book(9, [10] * 512 + [11] * 1024, lookup=(1, half, one, 3, False, words(rng, 2, 3)))]))
    add('lookup-1-sequence', third=setup([book(2, [4] * 16, lookup=(1, half, one, 4, True, words(rng, 4, 4))), book(3, [5] * 27, lookup=(1, tiny, half, 9, True, words(rng, 3, 9))),
                                          book(4, [7] * 100, lookup=(1, one, tiny, 11, True, words(rng, 3, 11)))]))
    add('lookup-1-sparse', third=setup([book(2, [255] * 60 + [1, 2, 2] + [255] * 37, sparse=True, lookup=(1, 0, one, 5, False, words(rng, 10, 5))),
                                        book(3, [255] * 30, sparse=True, lookup=(1, one, one, 5, True, words(rng, 3, 5))),
                                        book(2, [255 if k % 7 else 6 for k in range(400)], sparse=True, lookup=(1, half, half, 8, True, words(rng, 20, 8)))]))
    add('lookup-2', third=setup([book(2, [4] * 16, lookup=(2, 0, one, 4, False, words(rng, 32, 4))), book(3, seven, lookup=(2, big, half, 16, True, words(rng, 36, 16))),
                                 book(1, [255] * 50 + [1, 1], sparse=True, lookup=(2, one, tiny, 7, True, words(rng, 52, 7))), book(5, [1], lookup=(2, one, one, 1, False, [1, 0, 1, 1, 0]))]))
    add('lookup-cut', third=setup([book(2, [4] * 16, lookup=(1, 0, one, 12, True, [4095, 1]))])[:-3])
    many = []
    for k in range(256):
        dimensions, lengths, kind, bits = 1 + k % 5, tree(2 + k * 7 % 90, rng), 1 + k % 2, 1 + k % 16
        count = lookup1(len(lengths), dimensions) if kind == 1 else len(lengths) * dimensions
        many.append(book(dimensions, lengths, lookup=None if k % 3 else (kind, half, one, bits, k % 4 == 0, words(rng, count, bits))))
    add('many', third=setup(many))
    # a codebook that fails
    add('no-tree', third=setup([book(1, plain), book(1, [1, 1, 1])]))
    add('length-32', third=setup([book(1, [1, 1])], count=2) + Writer().put(0x564342, 24).put(1, 16).put(3, 24).put(0, 2).put(4, 5).put(31, 5).bytes())
    add('ordered-past', third=setup([book(1, runs=(2, [3, 7]), entries=8)]))
    add('ordered-32', third=setup([book(1, runs=(31, [1, 1]), entries=3)]))
    add('ordered-slow', third=setup([book(1, runs=(1, [0] * 31), entries=5)]))
    add('no-entries', third=setup([book(1, [])]))
    add('no-entries-sparse', third=setup([book(3, [], sparse=True)]))
    add('no-entries-ordered', third=setup([book(0, runs=(1, []))]))
    add('no-dimensions', third=setup([book(0, [1, 1])]))
    add('nothing', third=setup([book(0, [])]))
    for index in range(3):
        sync = [0x42, 0x43, 0x56]
        sync[index] ^= 1 << index
        add(f'sync-{index}', third=setup([book(1, [1, 1]), book(1, [1, 1], sync=tuple(sync))]))
    add('lookup-3', third=setup([book(1, [1, 1], lookup=(3, 0, 0, 1, False, []))]))
    add('lookup-15', third=setup([book(1, [1, 1], lookup=(15, 0, 0, 1, False, []))]))
    add('transfer', third=setup([book(1, [1, 1])], transfers=(0, 0, 5)))
    add('transfers', third=setup([book(1, [1, 1])], transfers=(0,) * 64))
    add('books-past-packet', third=setup([book(1, [1, 1])], count=3))
    # codebooks the port refuses
    add('over-budget', third=setup([book(1, runs=(20, [(1 << 19) + 1]))]))
    add('at-budget', third=setup([book(1, runs=(19, [1 << 19]))]))
    add('lookup-1-31-dimensions', third=setup([book(31, [1, 1], lookup=(1, 0, one, 1, False, [1]))]))
    add('lookup-1-30-dimensions', third=setup([book(30, [1, 1], lookup=(1, 0, one, 1, False, [1]))]))
    add('lookup-1-no-entry-row', third=setup([book(65535, [255] * 8, sparse=True, lookup=(1, 0, one, 2, False, [1]))]))
    add('lookup-1-over', third=setup([book(9, runs=(19, [1 << 19]), lookup=(1, 0, one, 1, False, [1, 0, 1, 1]))]))
    add('lookup-2-past-ints', third=setup([book(65535, runs=(16, [1 << 16]), lookup=(2, 0, one, 1, False, []))]))
    add('lookup-2-over', third=setup([book(1100, runs=(12, [1 << 12]), lookup=(2, 0, one, 1, False, []))]))
    add('lookup-2-large', third=setup([book(1000, runs=(12, [1 << 12]), lookup=(2, half, one, 1, True, []))]))
    # the identification header
    for name, parts in dict(flag_none=dict(flag=0), flag_last=dict(flag=6), flag_continued=dict(flag=3), kind=dict(first=identification(kind=3)), name=dict(first=identification(name=b'vorbiz')),
                            version=dict(first=identification(version=1)), no_channels=dict(first=identification(channels=0)), channels_17=dict(first=identification(channels=17)),
                            channels_16=dict(first=identification(channels=16)), mono=dict(first=identification(channels=1, rate=8000, small=6, large=6)),
                            no_rate=dict(first=identification(rate=0)), small_5=dict(first=identification(small=5)), large_14=dict(first=identification(small=13, large=14)),
                            sizes_13=dict(first=identification(small=13, large=13)), small_over=dict(first=identification(small=10, large=9)), framing=dict(first=identification(framing=2)),
                            skeleton=dict(first=b'fishead\x00' + bytes(56)), not_skeleton=dict(first=b'fisheaD\x00' + bytes(56)), short=dict(first=identification()[:29]),
                            long=dict(first=identification() + b'\x00')).items():
        add('first-' + name.replace('_', '-'), **parts)
    out['first-two-segments'] = page(2, 0, 0, [30, 0], body=identification()) + paged([comment(), setup([book(1, [1, 1])])])
    # data that ends inside the identification header: in its name (VORBIS_unexpected_eof), and after it (zeros)
    for cut in (0, 1, 3, 6, 7, 12, 16, 28, 29):
        out[f'first-cut-{cut}'] = page(2, 0, 0, [30], body=identification()[:cut])
    # the comment header
    least = setup([book(1, [1, 1])])
    for name, second in dict(kind=comment(kind=5), name=comment(name=b'Vorbis'), framing=comment(framing=0), empty=b'', no_comments=comment(comments=()), no_vendor=comment(vendor=b''),
                             many=comment(comments=[b'K%d=%d' % (k, k * k) for k in range(300)]), long_vendor=comment(vendor=bytes(range(256)) * 5),
                             vendor_past=comment(vendor=b'abc', vendor_length=100, comments=(), tail=b''), vendor_negative=comment(vendor_length=0xFFFFFFFF),
                             vendor_most_negative=comment(vendor_length=0x80000000), vendor_at_budget=comment(vendor_length=BUDGET), vendor_over=comment(vendor_length=BUDGET + 1),
                             vendor_large=comment(vendor_length=0x7FFFFFFF), count_negative=comment(count=0xFFFFFFFF), count_past=comment(count=5),
                             count_over=comment(count=(1 << 21) + 1), count_at_budget=comment(count=1 << 21), count_2_28=comment(count=1 << 28), count_2_29=comment(count=1 << 29),
                             count_most=comment(count=0x7FFFFFFF), length_past=comment(comments=(b'A=1', b'B=2'), lengths=(3, 99), tail=b''),
                             length_negative=comment(comments=(b'A=1', b'B=2'), lengths=(0x90000000, 3)), length_over=comment(comments=(b'A=1', b'B=2'), lengths=(3, BUDGET + 1)),
                             cut_in_name=comment()[:4], cut_in_length=comment()[:9], only_kind=b'\x03').items():
        add('second-' + name.replace('_', '-'), second=second, third=least)
    add('second-alone', packets=[comment()])
    add('third-kind', third=setup([book(1, [1, 1])], kind=3))
    add('third-name', third=setup([book(1, [1, 1])], name=b'vorbi\x00'))
    add('third-empty', third=b'')
    add('third-only-kind', third=b'\x05')
    out['none-after-first'] = page(2, 0, 0, [30], body=identification())
    return out


def cases(source):
    """name -> stream: raylib's file, its damaged copies and the built streams."""
    out = {'whole': source}
    start, end = codebooks_end(source)
    rng = Rng(0xBADC0DE)
    for index in range(40):
        data = bytearray(source)
        for _ in range(1 + index % 3):
            data[start + rng.next(end - start)] ^= 1 << rng.next(8)
        out[f'damage-{index}'] = bytes(data)
    out.update(built())
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('vorbis-setup', args)
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files = cases((args.raylib_source / SOURCE).read_bytes())
    items, read = [], {}
    for name, data in files.items():
        (folder / f'{name}.ogg').write_bytes(data)
        items.append((name, f'{WORK}/{name}.ogg'))
        read[name] = model(data)
    native = [(name, path) for name, path in items if read[name][0] != REFUSED]
    counts = '\n'.join(f'static const int counts{k}[] = {{ {", ".join([str(made["count"]) for made in read[name][2]] + ["0"]) if read[name][0] == GOING else "0"} }};' for k, (name, _) in enumerate(native))
    runs = '\n'.join(f'    run({json.dumps(str(ROOT / path))}, counts{k}, {len(read[name][2]) if read[name][0] == GOING else 0});' for k, (name, path) in enumerate(native))
    rows = dict(zip((name for name, _ in native), (json.loads(line) for line in probe.native(NATIVE.replace('COUNTS', counts).replace('RUNS', runs), 'reference', extra_flags=FLAGS, link_raylib=False).splitlines())))
    if len(rows) != len(native):
        raise ProbeFailure(f'vorbis-setup: the reference printed {len(rows)} rows for {len(native)} files')
    # this probe's reading of the headers against stb_vorbis's: the same failures, the same fields
    for name, row in rows.items():
        mine = read[name]
        told = [FAILED, mine[1]] if mine[0] == FAILED else [GOING, mine[1], [[made[key] for key in ('dimensions', 'entries', 'sparse', 'lookup', 'values', 'bits', 'sequence', 'least', 'step', 'count')] for made in mine[2]]]
        if told != (row if row[0] == FAILED else [GOING, row[1], [book[:10] for book in row[2]]]):
            raise ProbeFailure(f'vorbis-setup: {name}: the probe reads {str(told)[:300]} where stb_vorbis has {str(row)[:300]}')
    expected = [rows[name] if name in rows else [REFUSED, read[name][1]] for name, _ in items]
    kinds = [row[0] for row in expected]
    codes = {row[1] for row in expected if row[0] == FAILED}
    whys = {row[1] for row in expected if row[0] == REFUSED}
    made = [book for row in expected if row[0] == GOING for book in row[2]]
    if expected[0][0] != GOING or len(expected[0][2]) < 20 or kinds.count(GOING) < 40 or codes != {0, 3, 5, 10, 20, 30, 34, 38} or whys != {1, 2, 3, 4} \
            or {book[3] for book in made} != {0, 1, 2} or {book[2] for book in made} != {0, 1} or {book[6] for book in made} != {0, 1} or not any(book[9] > 100000 for book in made) \
            or sum(1 for name, _ in items if name.startswith('damage-') and read[name][0] == GOING) < 8 or sum(1 for name, _ in items if name.startswith('damage-') and read[name][0] == FAILED) < 8:
        raise ProbeFailure(f'vorbis-setup: the cases lost their coverage: {kinds.count(GOING)} read, failures {sorted(codes)}, refusals {sorted(whys)}, {len(made)} codebooks')

    def render(selected, gpu):
        return PROGRAM + ''.join(f'    {"Unit <- " if k + 1 < len(selected) else ""}IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result))\n'
                                 for k, (_, path) in enumerate(selected))

    def parse(text, selected):
        rows = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(rows) != len(selected):
            raise ValueError('vorbis-setup: candidate output did not finish')
        return rows

    lanes = probe.candidates(render, items, batch=40, parse=parse, timeout=1500)

    def describe(index):
        for got in lanes.values():
            a, b = expected[index], got[index]
            if a != b:
                if a[0] != GOING or b[0] != GOING:
                    return f'{items[index][0]}: stb={str(a)[:80]} jonlib={str(b)[:80]}'
                if a[1] != b[1] or len(a[2]) != len(b[2]):
                    return f'{items[index][0]}: stb={a[1]}, {len(a[2])} codebooks; jonlib={b[1]}, {len(b[2])}'
                at = next(k for k, (x, y) in enumerate(zip(a[2], b[2])) if x != y)
                return f'{items[index][0]}: codebook {at}: stb={a[2][at]} jonlib={b[2][at]}'
        return items[index][0]

    probe.compare(expected, lanes, describe=describe)
    probe.finish(files=len(items), read=kinds.count(GOING), failed=kinds.count(FAILED), refused=kinds.count(REFUSED), codebooks=len(made), multiplicands=sum(book[9] for book in made),
                 failures=sorted(codes), refusals=sorted(whys))


if __name__ == '__main__':
    main()
