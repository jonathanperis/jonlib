#!/usr/bin/env python3
"""Compare M.Libc.srand/M.Libc.rand with the host's srand() and rand().

The glibc profiles answer glibc's generator: x[i] = x[i-31] + x[i-3] with the
output x[i] >> 1, seeded by the minimal standard generator, the first 310
values discarded. The expected values come from `model` (that recurrence in
Python); on a glibc host the native rand() must give the same values, both
after srand(seed) and without any srand (the seed 1). AppleLibm and a seed
from 2^31 on are None. CPU-1, CPU-2 and JavaScript lanes.
"""
import json

from conformance import gradient_reference
import probekit
from probekit import ProbeFailure

SEEDS = [1, 0, 2, 42, 12345, 16807, 127773, 2147483646, 2147483647]
REFUSED = [2147483648, 4294967295]
COUNT = 40

NATIVE = r'''#include <stdio.h>
#include <stdlib.h>
static const unsigned seeds[] = {SEEDS};
int main(void) {
  for (int i = 0; i < COUNT; i++) printf("%d ", rand());
  printf("\n");
  for (unsigned s = 0; s < sizeof seeds / sizeof seeds[0]; s++) {
    srand(seeds[s]);
    for (int i = 0; i < COUNT; i++) printf("%d ", rand());
    printf("\n");
  }
  return 0;
}
'''

PROGRAM = '''import Base
import ../../jonmath.bend as M
def stepped(acc: List<U32>, result: M.Libc.Rand & U32) -> M.Libc.Rand & List<U32>:
  (rand, value) = result
  (rand, List.append(&1, U32, acc, [value]))
def step(state: M.Libc.Rand & List<U32>) -> M.Libc.Rand & List<U32>:
  (rand, acc) = state
  stepped(acc, M.Libc.rand(rand))
def values(n: Nat, state: M.Libc.Rand & List<U32>) -> M.Libc.Rand & List<U32>:
  match n:
    case 0n: state
    case 1n+p: values(p, step(state))
def listed(state: M.Libc.Rand & List<U32>) -> List<U32>:
  (_, acc) = state
  acc
def show(rand: Maybe<M.Libc.Rand>) -> List<U32>:
  match rand:
    case None{}: [0]
    case Some{r}: listed(values(COUNTn, (r, [1])))
def one(+seed: U32) -> List<U32>:
  List.append(&1, U32, show(M.Libc.srand(M.Glibc239Libm{}, seed)), List.append(&1, U32, show(M.Libc.srand(M.Glibc241Libm{}, seed)), show(M.Libc.srand(M.AppleLibm{}, seed))))
def all(seeds: List<U32>) -> List<U32>:
  match seeds:
    case Nil{}: Nil{}
    case Con{s, rest}: List.append(&1, U32, one(s), all(rest))
def main() -> IO(Unit):
  IO.print(List.show(~&1, ~U32, ~U32.show, all([SEEDS])))
'''


def model(seed, count=COUNT):
    """The first values of rand() after srand(seed), for a seed below 2^31."""
    r = [seed or 1]
    for _ in range(30):
        hi, lo = divmod(r[-1], 127773)
        word = 16807 * lo - 2836 * hi
        r.append(word + 2147483647 if word < 0 else word)
    r += r[:3]
    for i in range(34, 344 + count):
        r.append((r[i - 31] + r[i - 3]) & 0xFFFFFFFF)
    return [word >> 1 for word in r[344:]]


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('rand', args)
    lines = probe.native(NATIVE.replace('SEEDS', ', '.join(f'{s}u' for s in SEEDS)).replace('COUNT', str(COUNT))).splitlines()
    native = [[int(v) for v in line.split()] for line in lines]
    if len(native) != len(SEEDS) + 1 or any(len(row) != COUNT for row in native):
        raise ProbeFailure('rand: incomplete native output')
    glibc = gradient_reference() != 'AppleLibm'
    if glibc:
        if native[0] != model(1):
            raise ProbeFailure('rand: the host rand() without srand differs from the model for the seed 1')
        for seed, row in zip(SEEDS, native[1:]):
            if row != model(seed):
                raise ProbeFailure(f'rand: the host rand() after srand({seed}) differs from the model')
    chosen = SEEDS + REFUSED
    expected = []
    for seed in chosen:
        some = [1] + model(seed) if seed < 2 ** 31 else [0]
        expected.append(some + some + [0])

    def render(seeds, gpu):
        return PROGRAM.replace('SEEDS', ', '.join(str(s) for s in seeds)).replace('COUNT', str(COUNT)).replace('all([', 'all!([' if gpu else 'all([')

    def parse(text, seeds):
        values = [v for line in text.splitlines() if line.strip() for v in json.loads(line)]
        out, at = [], 0
        for _ in seeds:
            row = []
            for _ in range(3):
                size = 1 + COUNT if values[at] == 1 else 1
                row += values[at:at + size]
                at += size
            out.append(row)
        if at != len(values):
            raise ProbeFailure('rand: wrong candidate output size')
        return out

    probe.compare(expected, probe.candidates(render, chosen, batch=len(chosen), parse=parse),
                  describe=lambda i: f'seed {chosen[i]}')
    probe.finish(seeds=len(chosen), values=COUNT, native_compared=glibc)


if __name__ == '__main__':
    main()
