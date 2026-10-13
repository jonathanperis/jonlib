#!/usr/bin/env python3
"""Compare src/vorbis_floor.bend with stb_vorbis's do_floor.

Reference. stb_vorbis.c as pinned raylib vendors it, included in the
reference program: start_decoder on a built stream of six floors, then
do_floor (with draw_line) for a floor, Y values for its points and half a
block of floats, read from a file of cases. Per case the rolling hash of
the floats' bits every 64 values and at the end, over the half block and
the 8 floats after it, which must be left as they were. The hash of
inverse_db_table's bits comes first.

Candidate. F.curve.of on the same cases with the port's setup of the same
stream and the generated table (src/vorbis_db.bend, which this probe also
holds against the source: tools/vorbis_db_table.py --check).

The floors have 2 to 250 points, places of 1 to 15 bits and each of the
four multipliers. The Y values: all inside the floor's range; some points
without one (-1); only the first point; values past the range, which wrap
in the table as stb_vorbis's lines take them modulo 256; negative ones
other than -1; with half blocks of 32, 256 and 2048 floats, shorter and
longer than the floor is wide. After its last point stb_vorbis reads the
table at the point's height without the modulo: a height past 255 there is
a read past the table, which the port refuses (the reader's error 1001).
This probe works out which cases those are (`refused`) and stb_vorbis is
not run on them. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

import probekit
from probekit import ROOT, ProbeFailure
import vorbis_db_table
from vorbis_codebook_probe import Rng
from vorbis_setup_probe import book, floor, model, places, stream, whole

WORK = '.build/vorbis-floor-probe/cases'
FLAGS = ['-ffp-contract=off', '-D_DEFAULT_SOURCE', '-Wno-everything']
REFUSED = 1001
RECORD = 259                                                                   # a case: the floor, half the block, a seed and 256 Y values

NATIVE = r'''#include "external/stb_vorbis.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned fnv(unsigned h, unsigned v) { return (h ^ v)*16777619u; }

int main(int argc, char **argv)
{
    static stb_vorbis p;
    static float target[8192];
    short record[RECORD];
    unsigned char *data;
    unsigned h = 2166136261u;
    int len, i, k;
    FILE *file = fopen(argv[1], "rb"), *cases = fopen(argv[2], "rb");
    if (!file || !cases) return 2;
    fseek(file, 0, SEEK_END);
    len = (int)ftell(file);
    fseek(file, 0, SEEK_SET);
    data = (unsigned char *)malloc(len);
    if (fread(data, 1, len, file) != (size_t)len) return 3;
    // stb_vorbis_open_memory
    vorbis_init(&p, NULL);
    p.stream = data;
    p.stream_end = data + len;
    p.stream_start = p.stream;
    p.stream_len = len;
    p.push_mode = FALSE;
    if (!start_decoder(&p)) return 4;
    for (i = 0; i < 256; i++) { unsigned w; memcpy(&w, &inverse_db_table[i], 4); h = fnv(h, w); }
    printf("[%u]\n", h);
    while (fread(record, sizeof(short), RECORD, cases) == RECORD)
    {
        int n2 = record[1], seed = record[2];
        Mapping map;
        MappingChannel channel;
        // a mapping whose first channel has the floor
        memset(&map, 0, sizeof(map));
        memset(&channel, 0, sizeof(channel));
        map.chan = &channel;
        map.submaps = 1;
        map.submap_floor[0] = (uint8)record[0];
        for (k = 0; k < 2*n2; k++) target[k] = (float)((k*37 + seed*11)%13) - 6.0f;
        if (!do_floor(&p, &map, 0, 2*n2, target, record + 3, NULL)) return 5;
        h = 2166136261u;
        printf("[");
        for (k = 0; k < n2 + 8; k++)
        {
            unsigned w;
            memcpy(&w, &target[k], 4);
            h = fnv(h, w);
            if (k%64 == 63) printf("%u, ", h);
        }
        printf("%u]\n", h);
    }
    return 0;
}
'''.replace('RECORD', str(RECORD))

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/vorbis_setup.bend as S
import ../../src/vorbis_maps.bend as M
import ../../src/vorbis_floor.bend as F
import ../../src/vorbis_db.bend as Db
import ../../src/store.bend as R

def mix(+h: U32, +v: U32) -> U32:
  ((h .^. v) * 16777619 : U32)

def mixed(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, +rest}: mixed(rest, mix(h, x))

# The rolling hash of the first `n` floats' bits, every 64 and at the end.
def hashed(n: Nat, xs: +List<F32>, +i: U32, +h: U32, +out: String) -> String:
  match n:
    case 0n: out ++ U32.show(h) ++ "]"
    case 1n+k:
      match xs:
        case Nil{}: out ++ "0]"
        case Con{+x, +rest}: hashed(k, rest, (i + 1 : U32), mix(h, F32.bits(x)), Bool.pick(String, U32.is_eq((i % 64 : U32), 63), out ++ U32.show(mix(h, F32.bits(x))) ++ ", ", out))

# A case's shorts: two bytes each, the low one first, as ints.
def shorts(n: Nat, bytes: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k:
      match bytes:
        case Con{+low, Con{+high, +rest}}: shorts(k, rest, Con{((low + (high * 256)) + Bool.pick(U32, (high >= 128 : U32), 4294901760, 0) : U32), acc})
        case _: List.reverse(&2, U32, acc)

# target[k] = (float)((k*37 + seed*11)%13) - 6.0f.
def seeded(n: Nat, +k: U32, +seed: U32, acc: +List<F32>) -> +List<F32>:
  match n:
    case 0n: List.reverse(&2, F32, acc)
    case 1n+rest: seeded(rest, (k + 1 : U32), seed, Con{(U32.to_f32((((k * 37) + (seed * 11)) % 13 : U32)) - 6.0 : F32), acc})

def floor.at(floors: +List<M.Floor>) -> M.Floor:
  match floors:
    case Nil{}: M.Floor{Nil{}, Nil{}, 1, 0, [0, 1], [0, 1], Nil{}, Nil{}}
    case Con{+f, _}: f

def curved(curve: F.Curve, +n: U32) -> String:
  match curve:
    case F.Curve{_, False{}}: "[1001]"
    case F.Curve{+row, True{}}: hashed(U32.to_nat((n + 8 : U32)), R.Row.list(row), 0, 2166136261, "[")

def one(record: +List<U32>, +floors: +List<M.Floor>, +table: R.Row) -> String:
  match record:
    case Con{+floor, Con{+n, Con{+seed, +ys}}}: curved(F.curve.of(R.Row.from(seeded(U32.to_nat((n * 2 : U32)), 0, seed, Nil{})), floor.at(List.drop(&2, M.Floor, floors, U32.to_nat(floor))), ys, n, table), n)
    case _: "[]"

def each(count: Nat, +bytes: +List<U32>, +floors: +List<M.Floor>, +table: R.Row, +out: String) -> String:
  match count:
    case 0n: out
    case 1n+k: each(k, List.drop(&2, U32, bytes, RECORD_BYTESn), floors, table, out ++ one(shorts(RECORDn, bytes, Nil{}), floors, table) ++ "\\n")

def cased(result: Result<&1, &1, J.Surface.IOError, +List<U32>>, +floors: +List<M.Floor>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print("[" ++ U32.show(mixed(Db.table(), 2166136261)) ++ "]\\n" ++ each(COUNTn, bytes, floors, F.table.row(), ""))

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data(CASES), result => cased(result, M.Maps.floors(M.maps.read(S.setup.codebooks(bytes)))))

def main() -> IO(Unit):
  IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data(STREAM), result => loaded(result))
'''.replace('RECORD_BYTES', str(RECORD * 2)).replace('RECORD', str(RECORD))


def floors(rng):
    """The stream's floors: of each multiplier, from no partition to 31 of them."""
    full = [(1 + k % 8, 0, 0, (-1,)) for k in range(16)]
    spread = (15, 0, 7, 3, 9, 1, 12, 5, 2, 8) * 3 + (15,)
    return [floor(multiplier=1, rangebits=6),
            floor(partitions=(0,), classes=((1, 0, 0, (-1,)),), multiplier=2, rangebits=1, places=(1,)),
            floor(partitions=(0, 1, 1, 0, 2), classes=((2, 0, 0, (-1,)), (3, 0, 0, (-1,)), (1, 0, 0, (-1,))), multiplier=4, rangebits=8, places=places(rng, 11, 8)),
            floor(partitions=spread, classes=full, multiplier=3, rangebits=15, places=places(rng, sum(full[number][0] for number in spread), 15)),
            floor(partitions=(7,) * 31, classes=[(8, 0, 0, (-1,))] * 8, multiplier=2, rangebits=9, places=places(rng, 248, 9)),
            floor(partitions=(1,), classes=((8, 0, 0, (-1,)), (7, 0, 0, (-1,))), multiplier=1, rangebits=5, places=(31, 6, 25, 4, 13, 2, 1))]


def refused(xs, order, multiplier, ys, n2):
    """Whether do_floor ends at a height that is not in its table: the last point with a Y (the first has one always, here)
    is before the half block's end and its height is not 0 to 255."""
    lx, ly = 0, ys[0] * multiplier
    for j in order[1:]:
        if ys[j] >= 0:
            lx, ly = xs[j], ys[j] * multiplier
    return lx < n2 and not 0 <= ly <= 255


def cases(made, rng):
    """(floor, half block, seed, the Y values): `made` are the floors as the setup has them."""
    out = []
    for number, (_, _, multiplier, _, xs, order, _, _) in enumerate(made):
        values, top = len(xs), (256, 128, 86, 64)[multiplier - 1]
        kinds = [lambda: [rng.next(top) for _ in range(values)],
                 lambda: [rng.next(top) if k < 2 or rng.next(3) else -1 for k in range(values)],
                 lambda: [rng.next(top)] + [-1] * (values - 1),
                 lambda: [rng.next(top), rng.next(top)] + [-1] * (values - 2),
                 lambda: [rng.next(2000) if rng.next(4) == 0 else rng.next(top) for _ in range(values)],
                 lambda: [rng.next(top) if k < 2 else (-7, -32768, -2, rng.next(top))[rng.next(4)] for k in range(values)],
                 lambda: [(top - 1) if k % 2 else 0 for k in range(values)],
                 lambda: [32767 - rng.next(40) if rng.next(5) == 0 else rng.next(top) for _ in range(values)],
                 lambda: [0] * values,
                 lambda: [300 + rng.next(700)] + [rng.next(top) for _ in range(values - 1)],
                 # the last point, the one at the floor's width, past the table; and no Y there, the points before it around the table's end
                 lambda: [rng.next(top), 300 + rng.next(1500)] + [rng.next(top) for _ in range(values - 2)],
                 lambda: [rng.next(top), -1] + [200 // multiplier + rng.next(120 // multiplier + 1) for _ in range(values - 2)]]
        for kind, make in enumerate(kinds):
            for n2 in (32, 256, 2048):
                out.append((number, n2, rng.next(1000), make()))
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('vorbis-floor', args)
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    # the generated table is the source's
    text = (args.raylib_source / vorbis_db_table.SOURCE).read_text(errors='replace')
    table = vorbis_db_table.checked(vorbis_db_table.compiled(text), vorbis_db_table.literals(text))
    if not vorbis_db_table.MODULE.is_file() or vorbis_db_table.MODULE.read_text() != vorbis_db_table.module(table):
        raise ProbeFailure('vorbis-floor: src/vorbis_db.bend is stale: run tools/vorbis_db_table.py')
    rng = Rng(0xF100D)
    data = stream(third=whole(floors=floors(rng)))
    (folder / 'floors.ogg').write_bytes(data)
    read = model(data)
    if read[:3] != (0, 0, 5):
        raise ProbeFailure(f'vorbis-floor: the built stream is not set up: {read[:3]}')
    made = read[5]
    chosen = cases(made, rng)
    turned = [refused(made[number][4], made[number][5], made[number][2], ys, n2) for number, n2, _, ys in chosen]
    native = [case for case, off in zip(chosen, turned) if not off]
    (folder / 'cases.bin').write_bytes(b''.join(struct.pack(f'<{RECORD}h', number, n2, seed, *(ys + [0] * (256 - len(ys)))) for number, n2, seed, ys in chosen))
    (folder / 'native.bin').write_bytes(b''.join(struct.pack(f'<{RECORD}h', number, n2, seed, *(ys + [0] * (256 - len(ys)))) for number, n2, seed, ys in native))
    source, binary = probe.work / 'reference.c', probe.work / 'reference'
    source.write_text(NATIVE)
    probekit.run(['clang', '-std=c11', '-O2', *FLAGS, source, '-I' + str(args.raylib_source / 'src'), '-lm', '-o', binary])
    lines = [json.loads(line) for line in probekit.run([binary, folder / 'floors.ogg', folder / 'native.bin']).splitlines()]
    hashed = 2166136261
    for word in table:
        hashed = ((hashed ^ word) * 16777619) & 0xFFFFFFFF
    if len(lines) != len(native) + 1 or lines[0] != [hashed]:
        raise ProbeFailure(f'vorbis-floor: the reference printed {len(lines)} rows for {len(native)} cases, or its table is not the generated one')
    rows = iter(lines[1:])
    expected = [lines[0]] + [[REFUSED] if off else next(rows) for off in turned]
    if turned.count(True) < 15 or turned.count(False) < 100 or len({tuple(row) for row in lines[1:]}) < len(native) * 9 // 10:
        raise ProbeFailure(f'vorbis-floor: the cases lost their coverage: {turned.count(True)} refused of {len(chosen)}')

    def render(selected, gpu):
        return PROGRAM.replace('COUNT', str(len(chosen))).replace('CASES', json.dumps(f'{WORK}/cases.bin')).replace('STREAM', json.dumps(f'{WORK}/floors.ogg'))

    def parse(text, selected):
        return [[json.loads(line) for line in text.splitlines() if line.strip()]]

    lanes = probe.candidates(render, [chosen], batch=1, parse=parse, timeout=1500)

    def describe(index):
        for got in lanes.values():
            for k, (a, b) in enumerate(zip(expected, got[0])):
                if a != b:
                    if k == 0:
                        return 'the table'
                    number, n2, _, ys = chosen[k - 1]
                    return f'case {k - 1} (floor {number}, half block {n2}, Y {ys[:6]}...): stb={str(a)[:60]} jonlib={str(b)[:60]}'
        return 'a different number of rows'

    probe.compare([expected], lanes, describe=describe)
    probe.finish(floors=len(made), cases=len(chosen), refused=turned.count(True), points=sum(len(made_[4]) for made_ in made))


if __name__ == '__main__':
    main()
