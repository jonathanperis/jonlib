#!/usr/bin/env python3
"""Compare M.Libm.pow2 (powf(2, k) for integral k) with the host's powf and exp2f.

The glibc profiles answer exactly 2^k for an integral k in [-20, 30]; on a
glibc host the native powf(2, k) and exp2f(k) (through volatile pointers, so
neither is folded) must both be that power for every such k. AppleLibm and
every other k (fractions, k outside the range, infinities, NaN) are None.
CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

from conformance import gradient_reference
import probekit
from probekit import ProbeFailure

NATIVE = r'''#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static float (*volatile host_powf)(float, float) = powf;
static float (*volatile host_exp2f)(float) = exp2f;
static uint32_t bits(float v) { uint32_t b; memcpy(&b, &v, 4); return b; }
int main(void) {
  for (int k = -20; k <= 30; k++) printf("%u %u\n", bits(host_powf(2.0f, (float) k)), bits(host_exp2f((float) k)));
  return 0;
}
'''

PROGRAM = '''import Base
import ../../jonmath.bend as M
def show(value: Maybe<F32>) -> List<U32>:
  match value:
    case None{}: [0, 0]
    case Some{v}: [1, F32.bits(v)]
def one(+word: U32) -> List<U32>:
  U32{w} = word
  List.append(&1, U32, show(M.Libm.pow2(M.Glibc239Libm{}, F32{w})),
    List.append(&1, U32, show(M.Libm.pow2(M.Glibc241Libm{}, F32{w})), show(M.Libm.pow2(M.AppleLibm{}, F32{w}))))
def all(words: List<U32>) -> List<U32>:
  match words:
    case Nil{}: Nil{}
    case Con{w, rest}: List.append(&1, U32, one(w), all(rest))
def main() -> IO(Unit):
  IO.print(List.show(~&1, ~U32, ~U32.show, all([WORDS])))
'''


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('pow2', args)
    native = [[int(v) for v in line.split()] for line in probe.native(NATIVE).splitlines()]
    if len(native) != 51:
        raise ProbeFailure('pow2: incomplete native output')
    exact = {k: word(2.0 ** k) for k in range(-20, 31)}
    glibc = gradient_reference() != 'AppleLibm'
    if glibc:
        for k, (power, exp2) in zip(range(-20, 31), native):
            if power != exact[k] or exp2 != exact[k]:
                raise ProbeFailure(f'pow2: the host powf(2, {k}) or exp2f({k}) is not 2^{k}')
    cases = [float(k) for k in range(-24, 35)] + [0.5, -0.5, 1.5, 29.999998, -20.000002, 1e9, -1e9, float('inf'), float('-inf'), float('nan'), -0.0]
    expected = []
    for value in cases:
        inside = value == value and abs(value) != float('inf') and value == int(value) and -20 <= value <= 30
        some = [1, exact[int(value)]] if inside else [0, 0]
        expected.append(some + some + [0, 0])

    def render(chosen, gpu):
        return PROGRAM.replace('WORDS', ', '.join(str(word(v)) for v in chosen)).replace('all([', 'all!([' if gpu else 'all([')

    def parse(text, chosen):
        values = [v for line in text.splitlines() if line.strip() for v in json.loads(line)]
        if len(values) != 6 * len(chosen):
            raise ProbeFailure('pow2: wrong candidate output size')
        return [values[6 * i:6 * i + 6] for i in range(len(chosen))]

    probe.compare(expected, probe.candidates(render, cases, batch=len(cases), parse=parse),
                  describe=lambda i: f'k = {cases[i]!r}')
    probe.finish(cases=len(cases), powers=51, native_compared=glibc)


if __name__ == '__main__':
    main()
