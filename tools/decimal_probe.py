#!/usr/bin/env python3
"""Compare src/decimal.bend's "%.Nf" text for F32 values with native printf.

Values: random bit patterns of every exponent, exact half-way ties at 0..9
decimals (for example 0.03125 at four), values just below and above ties,
subnormals, the largest finite values, negative zero and infinities, each at
0, 1, 4, 6 and 9 decimals. NaN is outside the contract (C libraries spell it
differently) and returns None. CPU/JS lanes.
"""
import hashlib
import json
import random
import struct

import probekit
from probekit import ProbeFailure

PLACES = (0, 1, 4, 6, 9)


def values():
    rng = random.Random(0xDEC)
    bits = [0, 0x80000000, 0x7F800000, 0xFF800000, 1, 0x80000001, 0x007FFFFF, 0x7F7FFFFF, 0xFF7FFFFF, 0x3F800000, 0xBF800000]
    for value in (0.03125, 0.5, 2.5, 0.125, 0.0625, 1.5, 0.00005, 0.00015, 1e-7, 0.999999, 9.99995, 123456.789, 16777215.0, 16777217.0,
                  0.1, 0.2, 0.3, 1e10, 3.4e38, 1.5e-45, 0.000123, 0.0003, 0.07, 100.0):
        for sign in (1, -1):
            bits.append(struct.unpack('<I', struct.pack('<f', sign * value))[0])
    for exponent in range(0, 255):
        for _ in range(3):
            bits.append((rng.randrange(2) << 31) | (exponent << 23) | rng.randrange(1 << 23))
    for _ in range(200):
        bits.append(struct.unpack('<I', struct.pack('<f', rng.uniform(-2, 2)))[0])
    return bits


def native(probe, bits):
    lines = ['#include <stdio.h>', '#include <string.h>', 'int main(void){unsigned b[]={' + ','.join(map(str, bits)) + '};',
             'for(unsigned i=0;i<sizeof b/sizeof b[0];i++){float f;memcpy(&f,&b[i],4);']
    lines += [f'printf("%.{p}f\\n",f);' for p in PLACES]
    return probe.native('\n'.join(lines + ['}return 0;}']) + '\n', link_raylib=False).splitlines()


def render(selected, gpu):
    body = '''import Base
import ../../src/decimal.bend as D
def show(m: Maybe<String>) -> IO(Unit):
  match m:
    case None{}: IO.print("None")
    case Some{s}: IO.print(s)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for b in selected:
        for p in PLACES:
            body += f'    show(D.fixed({b}, {p}n))\n'
    return body


def main():
    probe = probekit.Probe('decimal', probekit.arguments(__doc__, raylib=False))
    bits = values()
    lines = native(probe, bits)
    if len(lines) != len(bits) * len(PLACES):
        raise ProbeFailure('decimal: incomplete native output')
    expected = [lines[i * len(PLACES):(i + 1) * len(PLACES)] for i in range(len(bits))]
    lanes = probe.candidates(render, bits, batch=40,
                             parse=lambda text, selected: [text.splitlines()[i * len(PLACES):(i + 1) * len(PLACES)] for i in range(len(selected))])
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: f'{bits[i]:08x}')
    probe.finish(values=len(bits), places=list(PLACES), inputs_sha256=hashlib.sha256(json.dumps(bits).encode()).hexdigest())


if __name__ == '__main__':
    main()
