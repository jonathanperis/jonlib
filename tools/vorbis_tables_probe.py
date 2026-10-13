#!/usr/bin/env python3
"""Compare src/vorbis_tables.bend with stb_vorbis's tables for a block size.

Reference. stb_vorbis.c as pinned raylib vendors it, included in the
reference program so that its static functions can be called:
compute_twiddle_factors, compute_window and compute_bitreverse for each
block size the format has, 64 to 8192. The twiddle factors and the window
are the host C library's binary64 cos and sin narrowed to float. Per table
the rolling hash of its floats' bits every 64 values and at the end.

Candidate. T.tables.for under the host's libm profile, and on a glibc host
under M.AppleLibm too: there the port gives a value only where its float is
sure whatever library computes it (the binary64 result is two units in its
last place away from a float's rounding boundary), and the gate holds that
every value of every table is given and is the same float. On a host whose
profile is AppleLibm the same holds against Apple's own library, which is
what the rule is for.

The arguments of cos and sin are exact IEEE products and quotients of ints
and M_PI: no host's contraction changes them. M_PI is <math.h>'s double, as
in raylib's builds (they define _DEFAULT_SOURCE or _GNU_SOURCE); a strict C
build would give stb_vorbis its own float M_PI, and other tables. CPU-1, CPU-2 and JavaScript
lanes.
"""
import json

from conformance import gradient_reference
import probekit
from probekit import ProbeFailure

SIZES = [64, 128, 256, 512, 1024, 2048, 4096, 8192]
# raylib's builds define _DEFAULT_SOURCE (CMake) or _GNU_SOURCE (Makefile), so <math.h> gives stb_vorbis the double M_PI. Without
# either, in strict C, stb_vorbis defines M_PI itself, as a float, and its tables are others.
FLAGS = ['-ffp-contract=off', '-D_DEFAULT_SOURCE', '-Wno-everything']

NATIVE = r'''#include "external/stb_vorbis.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void floats(const float *values, int count)
{
    unsigned h = 2166136261u;
    printf("[");
    for (int i = 0; i < count; i++)
    {
        unsigned w;
        memcpy(&w, values + i, 4);
        h = (h ^ w)*16777619u;
        if (i%64 == 63) printf("%u, ", h);
    }
    printf("%u, %d]", h, count);
}

int main(void)
{
    static const int sizes[] = { SIZES };
    for (unsigned s = 0; s < sizeof(sizes)/sizeof(sizes[0]); s++)
    {
        int n = sizes[s];
        // (stb_vorbis.c leaves macros named L, C and R defined)
        float *first = malloc(sizeof(float)*(n >> 1)), *second = malloc(sizeof(float)*(n >> 1)), *third = malloc(sizeof(float)*(n >> 2)), *window = malloc(sizeof(float)*(n >> 1));
        uint16 *rev = malloc(sizeof(uint16)*(n >> 3));
        unsigned h = 2166136261u;
        // init_blocksize
        compute_twiddle_factors(n, first, second, third);
        compute_window(n, window);
        compute_bitreverse(n, rev);
        printf("[");
        floats(first, n >> 1);
        printf(", ");
        floats(second, n >> 1);
        printf(", ");
        floats(third, n >> 2);
        printf(", ");
        floats(window, n >> 1);
        for (int i = 0; i < n >> 3; i++) h = (h ^ rev[i])*16777619u;
        printf(", %u, %d, %u, %u]\n", h, n >> 3, (unsigned)rev[1], (unsigned)rev[(n >> 3) - 1]);
    }
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonmath.bend as M
import ../../src/vorbis_tables.bend as T

def fnv(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, +rest}: fnv(rest, ((h .^. x) * 16777619 : U32))

def head(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+x, _}: x

def nth(xs: +List<U32>, +i: U32) -> U32:
  head(List.drop(&2, U32, xs, U32.to_nat(i)))

def count(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: count(rest, (n + 1 : U32))

# The rolling hash of the floats' bits, every 64 and at the end, with their count.
def floats(xs: +List<F32>, +i: U32, +h: U32, +out: String) -> String:
  match xs:
    case Nil{}: out ++ U32.show(h) ++ ", " ++ U32.show(i) ++ "]"
    case Con{+x, +rest}:
      floats(rest, (i + 1 : U32), ((h .^. F32.bits(x)) * 16777619 : U32), Bool.pick(String, U32.is_eq((i % 64 : U32), 63), out ++ U32.show(((h .^. F32.bits(x)) * 16777619 : U32)) ++ ", ", out))

def told(tables: Maybe<T.Tables>) -> String:
  match tables:
    case None{}: "[]"
    case Some{T.Tables{+a, +b, +c, +window, +reverse}}:
      "[" ++ floats(a, 0, 2166136261, "[") ++ ", " ++ floats(b, 0, 2166136261, "[") ++ ", " ++ floats(c, 0, 2166136261, "[") ++ ", " ++ floats(window, 0, 2166136261, "[")
        ++ ", " ++ U32.show(fnv(reverse, 2166136261)) ++ ", " ++ U32.show(count(reverse, 0)) ++ ", " ++ U32.show(nth(reverse, 1)) ++ ", " ++ U32.show(nth(reverse, (count(reverse, 0) - 1 : U32))) ++ "]"

def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('vorbis-tables', args)
    libm = gradient_reference()
    native = [json.loads(line) for line in probe.native(NATIVE.replace('SIZES', ', '.join(str(n) for n in SIZES)), 'reference', extra_flags=FLAGS, link_raylib=False).splitlines()]
    if len(native) != len(SIZES) or any([table[-1] for table in row[:4]] != [n >> 1, n >> 1, n >> 2, n >> 1] or row[5] != n >> 3 or row[6] != n >> 2 or row[7] != (n >> 1) - 4 for n, row in zip(SIZES, native)):
        raise ProbeFailure('vorbis-tables: the reference did not make the tables this probe was written for')
    # the host's own profile, and on a glibc host the values that are sure whatever the library
    profiles = [libm] + (['AppleLibm'] if libm != 'AppleLibm' else [])
    items = [(n, profile) for profile in profiles for n in SIZES]
    expected = [native[SIZES.index(n)] for n, _ in items]

    def render(selected, gpu):
        return PROGRAM + ''.join(f'    {"Unit <- " if k + 1 < len(selected) else ""}IO.print(told(T.tables.for(M.{profile}{{}}, {n})))\n' for k, (n, profile) in enumerate(selected))

    def parse(text, selected):
        rows = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(rows) != len(selected):
            raise ValueError('vorbis-tables: candidate output did not finish')
        return rows

    lanes = probe.candidates(render, items, batch=4, parse=parse, timeout=1500)

    def describe(index):
        n, profile = items[index]
        for got in lanes.values():
            a, b = expected[index], got[index]
            if a != b:
                if not b:
                    return f'block size {n} under {profile}: a value is not given'
                for name, x, y in zip('ABC', a, b):
                    if x != y:
                        return f'block size {n} under {profile}: {name} differs by value {64 * next(k for k, (p, q) in enumerate(zip(x, y)) if p != q)}'
                return f'block size {n} under {profile}: {"the window" if a[3] != b[3] else "the bit reversal"} differs'
        return f'block size {n} under {profile}'

    probe.compare(expected, lanes, describe=describe)
    probe.finish(sizes=len(SIZES), profiles=profiles, floats=sum((n >> 1) * 3 + (n >> 2) for n in SIZES), libm=libm)


if __name__ == '__main__':
    main()
