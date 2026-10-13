#!/usr/bin/env python3
"""Compare src/vorbis_mdct.bend with stb_vorbis's inverse_mdct.

Reference. stb_vorbis.c as pinned raylib vendors it, included in the
reference program so that its static functions can be called:
init_blocksize for a block size, then inverse_mdct on blocks of floats read
from a file. Per block the rolling hash of the n floats' bits every 64
values and at the end.

Candidate. V.transform on the same blocks, read from the same file, with
T.tables.for's tables under the host's libm profile.

The blocks, for each block size from 64 to 8192: silence, a value at each
end of the spectrum and in its middle, ones, alternating signs, seeded
noise, a ramp, values of every size at once (from 1e-30 to 1e30, with
negative zeros), and the noise again with the second half of the block,
which the transform does not read, filled with something else (the result
must be the noise's). No block overflows: the bits of the NaN an infinity
less an infinity gives are the machine's, not the code's. The reference is compiled without contraction, as the
other audio gates' are. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

from conformance import gradient_reference
import probekit
from probekit import ROOT, ProbeFailure
from vorbis_codebook_probe import Rng

SIZES = [64, 128, 256, 512, 1024, 2048, 4096, 8192]
WORK = '.build/vorbis-mdct-probe/cases'
FLAGS = ['-ffp-contract=off', '-D_DEFAULT_SOURCE', '-Wno-everything']

NATIVE = r'''#include "external/stb_vorbis.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void block(const char *path, int n, int count)
{
    static stb_vorbis p;
    float *floats = malloc(sizeof(float)*n);
    FILE *file = fopen(path, "rb");
    if (!file) exit(2);
    vorbis_init(&p, NULL);
    if (!init_blocksize(&p, 0, n)) exit(3);
    printf("[");
    for (int k = 0; k < count; k++)
    {
        unsigned h = 2166136261u;
        if (fread(floats, sizeof(float), n, file) != (size_t)n) exit(4);
        inverse_mdct(floats, n, &p, 0);
        printf("%s[", k? ", " : "");
        for (int i = 0; i < n; i++)
        {
            unsigned w;
            memcpy(&w, floats + i, 4);
            h = (h ^ w)*16777619u;
            if (i%64 == 63 && i != n - 1) printf("%u, ", h);
        }
        printf("%u]", h);
    }
    printf("]\n");
    fclose(file);
}

int main(void)
{
RUNS
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/vorbis_codebook.bend as C
import ../../src/vorbis_tables.bend as T
import ../../src/vorbis_mdct.bend as V
import ../../src/store.bend as R

# The rolling hash of the first `n` floats' bits, every 64 and at the end (`last` is n - 1).
def hashed(n: Nat, xs: +List<F32>, +i: U32, +last: U32, +h: U32, +out: String) -> String:
  match n:
    case 0n: out ++ U32.show(h) ++ "]"
    case 1n+k:
      match xs:
        case Nil{}: out ++ "0]"
        case Con{+x, +rest}:
          hashed(k, rest, (i + 1 : U32), last, ((h .^. F32.bits(x)) * 16777619 : U32), Bool.pick(String, U32.is_eq((i % 64 : U32), 63) && U32.is_ne(i, last), out ++ U32.show(((h .^. F32.bits(x)) * 16777619 : U32)) ++ ", ", out))

# A block's floats: four bytes each, the low one first.
def floats(n: Nat, bytes: +List<U32>, acc: +List<F32>) -> +List<F32>:
  match n:
    case 0n: List.reverse(&2, F32, acc)
    case 1n+k:
      match bytes:
        case Con{+a, Con{+b, Con{+c, Con{+d, +rest}}}}: floats(k, rest, Con{C.float.word((((a + (b << 8n)) + (c << 16n)) + (d << 24n) : U32)), acc})
        case _: List.reverse(&2, F32, acc)

def blocks(count: Nat, +n: U32, +factors: V.Factors, +bytes: +List<U32>, +first: Bool, +out: String) -> String:
  match count:
    case 0n: out ++ "]"
    case 1n+k:
      blocks(k, n, factors, List.drop(&2, U32, bytes, U32.to_nat((n * 4 : U32))), False{},
        out ++ Bool.pick(String, first, "", ", ") ++ hashed(U32.to_nat(n), R.Row.list(V.transform(R.Row.from(floats(U32.to_nat(n), bytes, Nil{})), factors, n)), 0, (n - 1 : U32), 2166136261, "["))

def made(tables: Maybe<T.Tables>, +n: U32, +count: U32, +bytes: +List<U32>) -> String:
  match tables:
    case None{}: "[]"
    case Some{+found}: blocks(U32.to_nat(count), n, V.factors.of(found), bytes, True{}, "[")

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>, +n: U32, +count: U32) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(made(T.tables.for(M.LIBM{}, n), n, count, bytes))

def main() -> IO(Unit):
  do IO<Unit>:
'''


def blocks(n, rng):
    """(name, the block's n floats): the spectrum is its first half."""
    half = n >> 1
    noise = [(rng.next(65536) - 32768) / 32768.0 for _ in range(half)]

    def spectrum(values, rest=0.0):
        return list(values) + [rest] * (n - half)

    sizes = [1e-30, -1e-20, 1e-10, -1e-5, 1.0, -1e5, 1e10, -1e20, 1e30, -0.0, 0.0, 3.5]
    out = [('silence', spectrum([0.0] * half)),
           ('first', spectrum([1.0] + [0.0] * (half - 1))),
           ('last', spectrum([0.0] * (half - 1) + [-2.5])),
           ('middle', spectrum([0.75 if k == half // 2 + 1 else 0.0 for k in range(half)])),
           ('ones', spectrum([1.0] * half)),
           ('alternating', spectrum([1.0 if k % 2 else -1.0 for k in range(half)])),
           ('noise', spectrum(noise)),
           ('ramp', spectrum([(k - half / 2) / half for k in range(half)])),
           ('sizes', spectrum([sizes[(k * 7) % len(sizes)] for k in range(half)])),
           ('noise-over-junk', spectrum(noise, rest=7.0))]
    return out


def packed(values):
    return struct.pack(f'<{len(values)}f', *values)


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('vorbis-mdct', args)
    libm = gradient_reference()
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    rng = Rng(0x1DC7)
    items = []
    for n in SIZES:
        made = blocks(n, rng)
        (folder / f'{n}.bin').write_bytes(b''.join(packed(values) for _, values in made))
        items.append((n, f'{WORK}/{n}.bin', [name for name, _ in made]))
    runs = '\n'.join(f'    block({json.dumps(str(ROOT / path))}, {n}, {len(names)});' for n, path, names in items)
    expected = [json.loads(line) for line in probe.native(NATIVE.replace('RUNS', runs), 'reference', extra_flags=FLAGS, link_raylib=False).splitlines()]
    if len(expected) != len(SIZES) or any(len(row) != len(names) or any(len(block) != n // 64 for block in row) for (n, _, names), row in zip(items, expected)):
        raise ProbeFailure('vorbis-mdct: the reference did not transform the blocks this probe was written for')
    # the junk in the second half of a block changes nothing; the other blocks are all different
    for (n, _, names), row in zip(items, expected):
        by = dict(zip(names, (tuple(block) for block in row)))
        if len(set(by.values())) != len(names) - 1 or by['noise'] != by['noise-over-junk']:
            raise ProbeFailure(f'vorbis-mdct: the reference blocks of {n} are not the ones this probe was written for')

    def render(selected, gpu):
        return PROGRAM.replace('LIBM', libm) + ''.join(
            f'    {"Unit <- " if k + 1 < len(selected) else ""}IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result, {n}, {len(names)}))\n'
            for k, (n, path, names) in enumerate(selected))

    def parse(text, selected):
        rows = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(rows) != len(selected):
            raise ValueError('vorbis-mdct: candidate output did not finish')
        return rows

    lanes = probe.candidates(render, items, batch=2, parse=parse, timeout=1500)

    def describe(index):
        n, _, names = items[index]
        for got in lanes.values():
            a, b = expected[index], got[index]
            if a != b:
                if len(a) != len(b):
                    return f'block size {n}: the tables are not given' if not b else f'block size {n}: {len(b)} blocks for {len(a)}'
                which = next(k for k, (x, y) in enumerate(zip(a, b)) if x != y)
                at = next((k for k, (x, y) in enumerate(zip(a[which], b[which])) if x != y), 0)
                return f'block size {n}, {names[which]}: differs by float {64 * (at + 1)}'
        return f'block size {n}'

    probe.compare(expected, lanes, describe=describe)
    probe.finish(sizes=len(SIZES), blocks=sum(len(names) for _, _, names in items), floats=sum(n * len(names) for n, _, names in items), libm=libm)


if __name__ == '__main__':
    main()
