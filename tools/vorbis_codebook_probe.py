#!/usr/bin/env python3
"""Compare src/vorbis_codebook.bend with stb_vorbis's codebook builders.

Reference. stb_vorbis.c as pinned raylib vendors it (src/external), included
in the reference program so that its static functions can be called:
compute_codewords, compute_sorted_huffman and compute_accelerated_huffman on
a Codebook set up the way start_decoder sets it up between reading a
codebook's lengths and building its tables, and float32_unpack, ilog and
bit_reverse on lists of values. Per codebook: whether the lengths are a tree
and, when they are, hashes of the codewords of the symbols that have one,
of the sorted codewords, the sorted values, the codeword lengths the
codebook keeps (the sorted ones when it is sparse) and the 1024 entries of
the accelerated table, with the count of sorted entries.

Candidate. V.book.of on the same lengths, read from the same files, and the
three scalar functions on the same values.

The codebooks: complete trees of 1 to 3000 symbols from seeded splits, the
same with symbols left without a code, incomplete trees, a chain of every
length up to 31, lengths in every order, a single symbol, none, a symbol
past the 32767th (the accelerated table holds shorts), and lengths that ask
for more codes than a tree has (refused by both sides) -- each as a sparse
codebook and as one that is not. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

import probekit
from probekit import ROOT, ProbeFailure

WORK = '.build/vorbis-codebook-probe/cases'

NATIVE = r'''#include "external/stb_vorbis.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned fnv(unsigned h, unsigned v) { return (h ^ v)*16777619u; }

// A codebook's tables from its lengths, as start_decoder makes them once it knows whether the codebook is sparse.
static void codebook(const char *path, int sparse)
{
    static uint8 lengths[1 << 17];
    FILE *file = fopen(path, "rb");
    int entries = (int)fread(lengths, 1, sizeof(lengths), file), total = 0, sorted_count = 0, j;
    uint32 *values = NULL;
    Codebook book, *c = &book;
    fclose(file);
    memset(c, 0, sizeof(*c));
    c->entries = entries;
    c->sparse = sparse;
    for (j = 0; j < entries; ++j) if (lengths[j] != NO_CODE) ++total;
    if (!c->sparse) c->codeword_lengths = lengths;
    if (c->sparse) sorted_count = total;
    else for (j = 0; j < c->entries; ++j) if (lengths[j] > STB_VORBIS_FAST_HUFFMAN_LENGTH && lengths[j] != NO_CODE) ++sorted_count;
    c->sorted_entries = sorted_count;
    if (!c->sparse) c->codewords = (uint32 *)malloc(sizeof(c->codewords[0])*(c->entries + 1));
    else if (c->sorted_entries) {
        c->codeword_lengths = (uint8 *)malloc(c->sorted_entries);
        c->codewords = (uint32 *)malloc(sizeof(*c->codewords)*c->sorted_entries);
        values = (uint32 *)malloc(sizeof(*values)*c->sorted_entries);
    }
    if (!compute_codewords(c, lengths, c->entries, values)) { printf("[0, 0, 0, 0, 0, 0, 0]\n"); return; }
    unsigned codes = 2166136261u, sorted = 2166136261u, symbols = 2166136261u, kept = 2166136261u, fast = 2166136261u;
    if (!c->sparse) for (j = 0; j < c->entries; ++j) if (lengths[j] != NO_CODE) codes = fnv(codes, c->codewords[j]);
    if (c->sorted_entries) {
        c->sorted_codewords = (uint32 *)malloc(sizeof(*c->sorted_codewords)*(c->sorted_entries + 1));
        c->sorted_values = (int *)malloc(sizeof(*c->sorted_values)*(c->sorted_entries + 1));
        ++c->sorted_values;
        c->sorted_values[-1] = -1;
        compute_sorted_huffman(c, lengths, values);
        if (c->sorted_codewords[c->sorted_entries] != 0xffffffff) exit(4);
    }
    compute_accelerated_huffman(c);
    for (j = 0; j < c->sorted_entries; ++j) { sorted = fnv(sorted, c->sorted_codewords[j]); symbols = fnv(symbols, (unsigned)c->sorted_values[j]); }
    for (j = 0; j < (c->sparse? c->sorted_entries : c->entries); ++j) kept = fnv(kept, c->codeword_lengths[j]);
    for (j = 0; j < FAST_HUFFMAN_TABLE_SIZE; ++j) fast = fnv(fast, (unsigned)(int)c->fast_huffman[j]);
    printf("[1, %u, %d, %u, %u, %u, %u]\n", codes, c->sorted_entries, sorted, symbols, kept, fast);
}

static const char *paths[] = { PATHS };
static const int sparse[] = { SPARSE };
static const unsigned words[] = { WORDS };

int main(void)
{
    for (unsigned i = 0; i < sizeof(paths)/sizeof(paths[0]); i++) codebook(paths[i], sparse[i]);
    printf("[");
    for (unsigned i = 0; i < sizeof(words)/sizeof(words[0]); i++) {
        float f = float32_unpack(words[i]);
        unsigned w;
        memcpy(&w, &f, 4);
        printf("%s%u, %d, %u", i? ", " : "", w, ilog((int)words[i]), bit_reverse(words[i]));
    }
    printf("]\n");
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/vorbis_codebook.bend as V

def fnv(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: fnv(rest, ((h .^. x) * 16777619 : U32))

# The first `n` values.
def fnv.first(n: Nat, xs: +List<U32>, +h: U32) -> U32:
  match n:
    case 0n: h
    case 1n+k:
      match xs:
        case Nil{}: h
        case Con{+x, rest}: fnv.first(k, rest, ((h .^. x) * 16777619 : U32))

# The codewords of the symbols that have a code.
def fnv.coded(lengths: +List<U32>, codewords: +List<U32>, +h: U32) -> U32:
  match lengths codewords:
    case Con{+len, +more} Con{+code, +rest}: fnv.coded(more, rest, Bool.pick(U32, U32.is_eq(len, 255), h, ((h .^. code) * 16777619 : U32)))
    case _ _: h

def row(book: Maybe<V.Book>) -> String:
  match book:
    case None{}: "[0, 0, 0, 0, 0, 0, 0]"
    case Some{V.Book{+sparse, _, +lengths, +codewords, +sorted, +sorted_codewords, +sorted_values, +fast}}:
      "[1, " ++ U32.show(Bool.pick(U32, sparse, 2166136261, fnv.coded(lengths, codewords, 2166136261))) ++ ", " ++ U32.show(sorted) ++ ", " ++ U32.show(fnv.first(U32.to_nat(sorted), sorted_codewords, 2166136261))
        ++ ", " ++ U32.show(fnv(sorted_values, 2166136261)) ++ ", " ++ U32.show(fnv(lengths, 2166136261)) ++ ", " ++ U32.show(fnv(fast, 2166136261)) ++ "]"

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>, +sparse: Bool) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+lengths}: IO.print(row(V.book.of(lengths, sparse)))

def scalars(words: +List<U32>, +first: Bool, +out: String) -> String:
  match words:
    case Nil{}: out ++ "]"
    case Con{+w, rest}:
      scalars(rest, False{}, out ++ Bool.pick(String, first, "", ", ") ++ U32.show(F32.bits(V.float32.unpack(w))) ++ ", " ++ U32.show(V.ilog(w)) ++ ", " ++ U32.show(V.bit.reverse(w)))

def main() -> IO(Unit):
  do IO<Unit>:
'''


class Rng:
    def __init__(self, seed):
        self.state = seed

    def next(self, bound):
        self.state = (self.state * 1664525 + 1013904223) & 0xFFFFFFFF
        return (self.state >> 8) % bound


def tree(count, rng, limit=31):
    """The code lengths of a complete binary tree of `count` leaves, made by seeded splits."""
    leaves = [0]
    while len(leaves) < count:
        open_ = [i for i, depth in enumerate(leaves) if depth < limit]
        at = open_[rng.next(len(open_))]
        depth = leaves.pop(at) + 1
        leaves[at:at] = [depth, depth]
    return leaves if count > 1 else [1]


def shuffled(values, rng):
    out = list(values)
    for i in range(len(out) - 1, 0, -1):
        j = rng.next(i + 1)
        out[i], out[j] = out[j], out[i]
    return out


def with_holes(lengths, rng, every):
    """The same lengths with symbols that have no code (255) put among them."""
    out = []
    for length in lengths:
        while rng.next(every) == 0:
            out.append(255)
        out.append(length)
    return out


def books():
    """(name, lengths): code lengths of 1 to 31, or 255."""
    rng = Rng(0x0DDC0DE5)
    out = [('one', [1]), ('deep-one', [31]), ('pair', [1, 1]), ('none', [255, 255, 255]), ('late', [255, 255, 5, 255]),
           ('chain', list(range(1, 32)) + [31]), ('chain-open', list(range(1, 32))), ('reversed-chain', [31] + list(range(31, 0, -1))),
           ('too-many', [1, 1, 1]), ('too-many-late', [2, 2, 2, 2, 5]), ('short-then-full', [1, 2, 2, 3]), ('eleven', [11] * 2048), ('ten', [10] * 1024),
           ('ten-and-eleven', [10] * 1023 + [11, 11])]
    for count in (2, 3, 5, 16, 100, 300, 1024, 3000):
        lengths = tree(count, rng)
        out.append((f'tree-{count}', lengths))
        out.append((f'tree-{count}-shuffled', shuffled(lengths, rng)))
        out.append((f'tree-{count}-holes', with_holes(shuffled(lengths, rng), rng, 3)))
        out.append((f'tree-{count}-incomplete', [length for k, length in enumerate(shuffled(lengths, rng)) if k % 4]))
    shallow = tree(600, rng, limit=10)
    out += [('shallow', shallow), ('shallow-holes', with_holes(shallow, rng, 2)), ('sparse-like', [255] * 300 + with_holes(tree(40, rng), rng, 2) + [255] * 500)]
    # the accelerated table's indexes are shorts: a symbol past the 32767th is left to the sorted table
    far = [255] * 40000
    far[5], far[39999] = 1, 1
    out.append(('far', far))
    far = [255] * 40000
    far[5], far[39999], far[32766], far[32767] = 1, 2, 3, 3
    out.append(('far-edge', far))
    return out


def words():
    """Packed floats, and values for ilog and bit_reverse: every exponent's neighbourhood, both signs, mantissas of every size."""
    out = [0, 1, 2, 3, 4, 0x80000000, 0xFFFFFFFF, 0x7FFFFFFF, 0x001FFFFF, 0x00100000, 0x55555555, 0xAAAAAAAA, 0x12345678, 16383, 16384, 0x00FFFFFF, 0x01000000,
           0x1FFFFFFF, 0x20000000, 0x3FFFFFFF, 0x40000000]
    rng = Rng(0xF10A7)
    for exponent in list(range(600, 700)) + list(range(880, 930)) + [0, 1, 300, 787, 788, 789, 1022, 1023]:
        for mantissa in (1, 2, 3, 0x100000, 0x100001, 0x1FFFFF, 0x0FFFFF, rng.next(0x200000), rng.next(0x200000) | 1):
            out.append((exponent << 21 | mantissa) | (0x80000000 if rng.next(2) else 0))
    return out


def unpacked(word):
    """float32_unpack by exact arithmetic: the float's word."""
    mantissa, exponent, sign = word & 0x1FFFFF, (word >> 21) & 1023, word & 0x80000000
    value = float(mantissa) * 2.0 ** (exponent - 788)                      # exact in binary64
    try:
        packed = struct.pack('<f', value)
    except OverflowError:
        return sign | 0x7F800000
    return sign | struct.unpack('<I', packed)[0]


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('vorbis-codebook', args)
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    items = []
    for index, (name, lengths) in enumerate(books()):
        path = f'{WORK}/{index:02}-{name}.bin'
        (ROOT / path).write_bytes(bytes(lengths))
        items += [(name, path, False), (name, path, True)]
    chosen = words()
    source = (NATIVE.replace('PATHS', ', '.join(json.dumps(str(ROOT / path)) for _, path, _ in items)).replace('SPARSE', ', '.join(str(int(sparse)) for _, _, sparse in items))
              .replace('WORDS', ', '.join(f'{w}u' for w in chosen)))
    expected = [json.loads(line) for line in probe.native(source, 'reference', extra_flags=['-Wno-everything'], link_raylib=False).splitlines()]
    if len(expected) != len(items) + 1 or len(expected[-1]) != 3 * len(chosen):
        raise ProbeFailure(f'vorbis-codebook: the reference printed {len(expected)} rows for {len(items)} codebooks')
    rows = dict(zip(((name, sparse) for name, _, sparse in items), expected))
    refused = sum(row[0] == 0 for row in expected[:-1])
    if rows['too-many', False][0] or rows['too-many', True][0] or not rows['chain', False][0] or refused < 4 or rows['eleven', False][2] != 2048 or rows['ten', False][2] != 0 \
            or rows['ten', True][2] != 1024 or rows['far', False][6] == rows['none', False][6]:
        raise ProbeFailure('vorbis-codebook: the reference did not build the codebooks this probe was written for')
    floats = expected[-1][0::3]
    if floats != [unpacked(w) for w in chosen] or 0x7F800000 not in floats or 0xFF800000 not in floats or not any(0 < f < 0x00800000 for f in floats):
        raise ProbeFailure('vorbis-codebook: float32_unpack is not the exact scaling this probe expects, or the words lost their coverage')

    def render(selected, gpu):
        body = ''.join(f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result, {"True" if sparse else "False"}{{}}))\n'
                       for _, path, sparse in items)
        chunks = ', '.join('[' + ', '.join(str(w) for w in chosen[start:start + 64]) + ']' for start in range(0, len(chosen), 64))
        return PROGRAM + body + f'    IO.print(scalars(List.concat(&2, U32, [{chunks}]), True{{}}, "["))\n'

    def parse(text, selected):
        return [[json.loads(line) for line in text.splitlines() if line.strip()]]

    lanes = probe.candidates(render, [items], batch=1, parse=parse, timeout=1500)

    def first(index):
        for got in lanes.values():
            for k, (a, b) in enumerate(zip(expected, got[0])):
                if a != b:
                    return f'{items[k][0]}{" (sparse)" if items[k][2] else ""}: stb={a} jonlib={b}' if k < len(items) else 'the scalar functions'
        return 'a different number of rows'

    probe.compare([expected], lanes, describe=first)
    probe.finish(codebooks=len(items), refused=refused, entries=sum(len(lengths) for _, lengths in books()), words=len(chosen))


if __name__ == '__main__':
    main()
