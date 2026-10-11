#!/usr/bin/env python3
"""Compare M.Libm.tanf with the glibc 2.39 tanf model.

The reference is tools/reference/glibc_tanf/model.c: glibc 2.39's x86_64 tanf
(s_tanf.c and k_tanf.c, with s_sincosf.h's reduction) as explicit binary32
and binary64 operations. It equals the native function on every binary32
argument, with and without the FMA variants enabled
(tools/reference/glibc_tanf/results/glibc239.json); glibc 2.41's tanf is a
different, correctly rounded algorithm and differs at 83,411,250 arguments
(results/glibc241.json), so M.Glibc241Libm and M.AppleLibm answer None. The
model is compiled on the host (-ffp-contract=off) and gives the expected
words; on a glibc 2.39 host the native tanf must equal it on every case.

Cases: words of every exponent and both signs from a fixed generator, the
edges of the kernel's regions (2^-13, 0.6744, pi/4, 120 by its top twelve
bits), the angles shapes_math_sine_cosine passes (whole and fractional
degrees times DEG2RAD), signed zeros, the largest finite values, and
infinities and NaN (None). CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import platform
import struct

import probekit
from probekit import ROOT, ProbeFailure

MODEL = ROOT / 'tools/reference/glibc_tanf/model.c'
DEG2RAD = struct.unpack('<f', struct.pack('<I', 0x3C8EFA35))[0]

NATIVE = r'''#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
float model_tanf (float);
static float (*volatile host_tanf) (float) = tanf;
static const uint32_t words[] = {WORDS};
int main (void)
{
  for (unsigned i = 0; i < sizeof words / sizeof words[0]; i++)
    {
      float x, m, h; uint32_t a, b;
      memcpy (&x, &words[i], 4);
      m = model_tanf (x); h = host_tanf (x);
      memcpy (&a, &m, 4); memcpy (&b, &h, 4);
      printf ("%u %u %d\n", a, b, (int) (m != m));
    }
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
  List.append(&1, U32, show(M.Libm.tanf(M.Glibc239Libm{}, F32{w})), List.append(&1, U32, show(M.Libm.tanf(M.Glibc241Libm{}, F32{w})), show(M.Libm.tanf(M.AppleLibm{}, F32{w}))))
def all(words: List<U32>) -> List<U32>:
  match words:
    case Nil{}: Nil{}
    case Con{w, rest}: List.append(&1, U32, one(w), all(rest))
def main() -> IO(Unit):
  IO.print(List.show(~&1, ~U32, ~U32.show, all([WORDS])))
'''


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def number(bits):
    return struct.unpack('<f', struct.pack('<I', bits))[0]


def finite(bits):
    return (bits >> 23) & 0xFF != 0xFF


def cases():
    out, state = [], 0x7A4F
    for exponent in range(255):
        for _ in range(2):
            state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
            out.append((state & 0x80000000) | (exponent << 23) | ((state >> 7) & 0x7FFFFF))
    for edge in (0x39000000, 0x3F2CA140, 0x3F490FDA, 0x42F00000, 0x00800000, 0x7F7FFFFF, 0x3FC90FDB, 0x40490FDB, 0x4016CBE4, 0x3F800000):
        for step in (-2, -1, 0, 1, 2):
            out += [edge + step, 0x80000000 | (edge + step)]
    # angleRad = angle*DEG2RAD for the example's slider and its animation.
    out += [word(number(word(float(degrees))) * DEG2RAD) for degrees in range(0, 361, 5)]
    out += [word(number(word(index * 0.37)) * DEG2RAD) for index in range(1, 400, 7)]
    out += [0, 0x80000000, 1, 0x80000001, 0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00000, 0x7F800001]
    seen, unique = set(), []
    for bits in out:
        bits &= 0xFFFFFFFF
        if bits not in seen:
            seen.add(bits)
            unique.append(bits)
    return unique


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('tanf', args)
    chosen = cases()
    source = MODEL.read_text().replace('MODEL_TANF', 'model_tanf') + NATIVE.replace('WORDS', ', '.join(f'{bits}u' for bits in chosen))
    lines = probe.native(source, link_raylib=False, extra_flags=('-ffp-contract=off',)).splitlines()
    if len(lines) != len(chosen):
        raise ProbeFailure('tanf: incomplete native output')
    glibc239 = platform.libc_ver() == ('glibc', '2.39')
    expected = []
    for bits, line in zip(chosen, lines):
        model, host, nan = (int(value) for value in line.split())
        if finite(bits) == bool(nan):
            raise ProbeFailure(f'tanf: the model gives {"a NaN" if nan else "a number"} for {bits:#010x}')
        if glibc239 and finite(bits) and model != host:
            raise ProbeFailure(f'tanf: the host gives {host:#010x} for {bits:#010x}, the model {model:#010x}')
        expected.append(([1, model] if finite(bits) else [0, 0]) + [0, 0, 0, 0])

    def render(selected, gpu):
        return PROGRAM.replace('WORDS', ', '.join(str(bits) for bits in selected))

    def parse(text, selected):
        values = [value for line in text.splitlines() if line.strip() for value in json.loads(line)]
        if len(values) != 6 * len(selected):
            raise ProbeFailure('tanf: wrong candidate output size')
        return [values[i:i + 6] for i in range(0, len(values), 6)]

    probe.compare(expected, probe.candidates(render, chosen, batch=len(chosen), parse=parse), describe=lambda i: f'tanf({chosen[i]:#010x})')
    probe.finish(cases=len(chosen), answered=sum(finite(bits) for bits in chosen), native_compared=glibc239)


if __name__ == '__main__':
    main()
