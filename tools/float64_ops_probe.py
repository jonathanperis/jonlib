#!/usr/bin/env python3
"""Verify internal normal binary64 multiplication/division against native C bits."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct

from conformance import BUILD, ROOT, checkout, run, source_gate


def samples():
    rng = random.Random(0xD053)
    values = [(0.0,1.0),(-0.0,1.0),(-0.0,-1.0),(1.0,3.0),(-1.25,2.75),
              (1.0000000000000002,1.0000000000000002)]
    for _ in range(250):
        values.append(tuple(struct.unpack('>d',struct.pack('>Q',
            (rng.randrange(2)<<63)|(rng.randint(983,1063)<<52)|rng.randrange(1<<52)))[0] for _ in range(2)))
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args = parser.parse_args()
    lock = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    work = BUILD/'float64-ops-probe';work.mkdir(parents=True,exist_ok=True)
    report_path = work/'results.json'
    report_path.write_text(json.dumps(dict(passed=False))+'\n')
    values = samples()
    source = work/'reference.c'
    source.write_text('#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n#pragma STDC FP_CONTRACT OFF\n'+
        'static const double values[][2]={'+','.join('{'+','.join(v.hex() for v in pair)+'}' for pair in values)+'};\n'+
        'static void emit(double value) { uint64_t bits;memcpy(&bits,&value,8);printf("%u %u\\n",(uint32_t)(bits>>32),(uint32_t)bits);}\n'+
        'int main(void) { for(unsigned i=0;i<sizeof(values)/sizeof(values[0]);i++) { emit(values[i][0]*values[i][1]);emit(values[i][0]/values[i][1]); } }\n')
    binary = work/'reference'
    run(['clang','-std=c11','-O2',source,'-o',binary])
    expected = [int(word) for word in run([binary]).split()]
    if len(expected)!=4*len(values):raise ValueError('Incomplete native binary64 results')
    report = dict(passed=False,samples=len(values),operations=2*len(values),
                  inputs_sha256=hashlib.sha256(json.dumps(values).encode()).hexdigest(),sources=source_gate(),lanes={})
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        candidate = work/f'{lane}.bend'
        program = '''import Base
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
        for start in range(0,len(values),32):
            inputs = ','.join('Sample{'+','.join(str(word) for value in pair for word in struct.unpack('>II',struct.pack('>d',value)))+'}' for pair in values[start:start+32])
            program += f'    IO.print(List.show(~&1, ~U32, ~U32.show, calculate{"!" if lane=="metal" else ""}([{inputs}])))\n'
        candidate.write_text(program)
        output = work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',candidate,'-o',output])
        command = ['bun',output] if lane=='javascript' else [output,*(['--gpu','on'] if lane=='metal' else [])]
        actual = [word for line in run(command).splitlines() for word in json.loads(line)]
        differences = [dict(word=i,reference=a,candidate=b) for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane] = dict(passed=actual==expected,mismatch_count=len(differences),differences=differences[:16])
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: binary64 mismatch: {differences[:3]}')
        print(f'{lane}: {2*len(values)} binary64 multiply/divide results match native bits',flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
