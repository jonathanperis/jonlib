#!/usr/bin/env python3
"""Compare the internal finite-normal F32 multiply-add against native fmaf."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct

from conformance import BUILD, ROOT, checkout, f32, run, source_gate


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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, required=True)
    parser.add_argument('--gpu', action='store_true')
    args = parser.parse_args()
    lock = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source, lock['bend']['revision'], lock['bend'].get('patch'))
    work = BUILD/'fused-probe'
    work.mkdir(parents=True, exist_ok=True)
    report_path = work/'results.json'
    report_path.write_text(json.dumps(dict(passed=False))+'\n')
    values = samples()
    (work/'reference.c').write_text('''#include <math.h>
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
    binary = work/'reference'
    run(['clang','-std=c11','-O2',work/'reference.c','-lm','-o',binary])
    expected = [int(line) for line in run([binary]).splitlines()]
    if len(expected) != len(values):
        raise ValueError('Native fmaf probe returned an incomplete result set')
    report = dict(passed=False, samples=len(values), sources=source_gate(),
                  inputs_sha256=hashlib.sha256(json.dumps(values).encode()).hexdigest(), lanes={})
    for lane in ('cpu','javascript', *(['metal'] if args.gpu else [])):
        actual = []
        for start in range(0,len(values),128):
            inputs = ','.join('Sample{'+','.join(f32(v) for v in row)+'}' for row in values[start:start+128])
            source = work/f'{lane}.bend'
            source.write_text('''import Base
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
'''.replace('BANG','!' if lane=='metal' else '').replace('INPUTS',inputs))
            output = work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
            run(['bun',args.bend_source/'bend2/main.ts',source,'-o',output])
            command = ['bun',output] if lane=='javascript' else [output,*(['--gpu','on'] if lane=='metal' else [])]
            actual.extend(json.loads(run(command)))
        mismatches = [dict(index=i,inputs=values[i],reference=a,candidate=b)
                      for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane] = dict(passed=actual==expected, mismatch_count=len(mismatches), mismatches=mismatches[:16])
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual != expected:
            raise ValueError(f'{lane}: fused multiply-add mismatch: {mismatches[:3]}')
        print(f'{lane}: {len(values)} F32 multiply-add results match exact native fmaf bits',flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
