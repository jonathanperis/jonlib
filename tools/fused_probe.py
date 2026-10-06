#!/usr/bin/env python3
"""Compare the internal finite-normal F32 multiply-add against native fmaf."""
import hashlib
import json
import random
import struct

from conformance import f32, source_gate
import probekit
from probekit import ProbeFailure

PROGRAM = '''import Base
import ../../src/fused.bend as F
type Sample is Data:
  Sample{a: F32, b: F32, c: F32}
def calculate(values: +List<Sample>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{Sample{a, b, c}, rest}:
      Con{F32.bits(F.multiply_add(a, b, c)), calculate(rest)}
def main() -> IO(Unit):
  IO.print(List.show(~&1, ~U32, ~U32.show, calculateBANG([INPUTS])))
'''


def samples():
    # The tiny addends straddle an F32 tie that binary64 addition would erase.
    values = [(1.0000001192092896, 1.5, sign * 2.0**-100) for sign in (-1, 1)]
    values += [(a,b,c) for a,b,c in ((0.0,1.0,-0.0),(-0.0,1.0,-0.0),
                                   (-0.0,-1.0,0.0),(1.5,2.0,-3.0),
                                   (-1.5,2.0,3.0),(1.5,2.0,0.0))]
    rng = random.Random(0xF32F)
    for _ in range(2048):
        values.append(tuple(struct.unpack('!f', struct.pack('!I',
            (rng.randrange(2)<<31) | (rng.randint(97,157)<<23) | rng.randrange(1<<23)))[0]
            for _ in range(3)))
    return values


def main():
    probe = probekit.Probe('fused', probekit.arguments(__doc__, raylib=False))
    probe.report['sources'] = source_gate()
    values = samples()
    text = probe.native('''#include <math.h>
#include <stdio.h>
#include <string.h>
static const float samples[][3] = {SAMPLES};
int main(void) {
  for(unsigned i=0;i<sizeof(samples)/sizeof(samples[0]);i++) {
    float value=fmaf(samples[i][0],samples[i][1],samples[i][2]);
    unsigned bits; memcpy(&bits,&value,4); printf("%u\\n",bits);
  }
}
'''.replace('SAMPLES', ',\n'.join('{'+','.join(v.hex()+'f' for v in row)+'}' for row in values)))
    expected = [int(line) for line in text.splitlines()]
    if len(expected) != len(values):
        raise ProbeFailure('Native fmaf probe returned an incomplete result set')

    def render(selected, gpu):
        inputs = ','.join('Sample{'+','.join(f32(v) for v in row)+'}' for row in selected)
        return PROGRAM.replace('BANG', '!' if gpu else '').replace('INPUTS', inputs)

    # Each 128-sample program prints one JSON list: one value per sample.
    probe.compare(expected, probe.candidates(render, values, batch=128, parse=lambda out, selected: json.loads(out)),
                  describe=lambda index: f'sample {index} {values[index]}')
    probe.finish(samples=len(values), inputs_sha256=hashlib.sha256(json.dumps(values).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
