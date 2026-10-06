#!/usr/bin/env python3
"""Verify internal normal binary64 multiplication/division against native C bits."""
import hashlib
import json
import random
import struct

from conformance import source_gate
import probekit
from probekit import ProbeFailure

PROGRAM = '''import Base
import ../../src/float64.bend as D
import ../../src/float64_ops.bend as O
import ../../src/resize_numeric.bend as N
type Sample is Data:
  Sample{ah: U32, al: U32, bh: U32, bl: U32}
def words(value: N.Double, rest: List<U32>) -> List<U32>:
  N.Double{sign, exponent, N.Wide{+high, +low}} = value
  e = Bool.pick(U32, U32.is_eq((high .|. low : U32), 0), 0, F32.to_u32((exponent + 1023.0 : F32)))
  Con{((Bool.to_u32(sign) << 31n) .|. (e << 20n) .|. (high .&. 1048575) : U32), Con{low, rest}}
def calculate(values: +List<Sample>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{Sample{ah, al, bh, bl}, rest}:
      +a = D.number(ah, al)
      +b = D.number(bh, bl)
      words(O.multiply(a, b), words(O.divide(a, b), calculate(rest)))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def samples():
    rng = random.Random(0xD053)
    values = [(0.0,1.0),(-0.0,1.0),(-0.0,-1.0),(1.0,3.0),(-1.25,2.75),
              (1.0000000000000002,1.0000000000000002)]
    for _ in range(250):
        values.append(tuple(struct.unpack('>d',struct.pack('>Q',
            (rng.randrange(2)<<63)|(rng.randint(983,1063)<<52)|rng.randrange(1<<52)))[0] for _ in range(2)))
    return values


def main():
    probe = probekit.Probe('float64-ops',probekit.arguments(__doc__,raylib=False))
    probe.report['sources'] = source_gate()
    values = samples()
    text = probe.native('#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n#pragma STDC FP_CONTRACT OFF\n'+
        'static const double values[][2]={'+','.join('{'+','.join(v.hex() for v in pair)+'}' for pair in values)+'};\n'+
        'static void emit(double value) { uint64_t bits;memcpy(&bits,&value,8);printf("%u %u\\n",(uint32_t)(bits>>32),(uint32_t)bits);}\n'+
        'int main(void) { for(unsigned i=0;i<sizeof(values)/sizeof(values[0]);i++) { emit(values[i][0]*values[i][1]);emit(values[i][0]/values[i][1]); } }\n')
    words = [int(word) for word in text.split()]
    if len(words)!=4*len(values):raise ProbeFailure('Incomplete native binary64 results')
    # One row per sample: product high/low words, then quotient high/low words.
    expected = [words[4*i:4*i+4] for i in range(len(values))]

    def render(selected,gpu):
        program = PROGRAM
        for start in range(0,len(selected),32):
            inputs = ','.join('Sample{'+','.join(str(word) for value in pair for word in struct.unpack('>II',struct.pack('>d',value)))+'}' for pair in selected[start:start+32])
            program += f'    IO.print(List.show(~&1, ~U32, ~U32.show, calculate{"!" if gpu else ""}([{inputs}])))\n'
        return program

    def parse(out,selected):
        flat = [word for line in out.splitlines() for word in json.loads(line)]
        return [flat[i:i+4] for i in range(0,len(flat),4)]

    probe.compare(expected,probe.candidates(render,values,batch=len(values),parse=parse),describe=lambda index:f'sample {index} {values[index]}')
    probe.finish(samples=len(values),operations=2*len(values),inputs_sha256=hashlib.sha256(json.dumps(values).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
