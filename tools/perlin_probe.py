#!/usr/bin/env python3
"""Verify packed stb_perlin tables and octave bits under explicit compiler arithmetic."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct

from conformance import BUILD, ROOT, checkout, f32, noise_reference, run, source_gate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    parser.add_argument('--uncontracted-control',action='store_true')
    args = parser.parse_args()
    lock = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    fused = not args.uncontracted_control and noise_reference()=='FusedNoise'
    work = BUILD/('perlin-probe-uncontracted' if args.uncontracted_control else 'perlin-probe')
    work.mkdir(parents=True,exist_ok=True)
    report_path = work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    fp = lambda value: struct.unpack('f',struct.pack('f',value))[0]
    values = [(x,y,1.0,seed) for x,y in ((0,0),(-1.25,2.75),(255.99,-256.01),(-0.0,-0.0),(0.0000152587890625,-0.5)) for seed in range(6)]
    rng = random.Random(0x5B7B)
    values += [(fp(rng.uniform(-300,300)),fp(rng.uniform(-300,300)),float(1<<rng.randrange(6)),rng.randrange(6)) for _ in range(192)]
    source = work/'reference.c'
    source.write_text('#include <stdio.h>\n#include <string.h>\n'+
        ('#pragma STDC FP_CONTRACT ON\n' if fused else '#pragma STDC FP_CONTRACT OFF\n')+
        '#define STB_PERLIN_IMPLEMENTATION\n#include "external/stb_perlin.h"\n'+
        'static const float samples[][4]={'+','.join('{'+','.join(float(v).hex()+'f' for v in row)+'}' for row in values)+'};\n'+
        'static unsigned bits(float x){unsigned b;memcpy(&b,&x,4);return b;}\n'+
        'int main(void){for(int i=0;i<512;i++)printf("%u %u\\n",stb__perlin_randtab[i],stb__perlin_randtab_grad_idx[i]);'+
        'for(unsigned i=0;i<sizeof(samples)/sizeof(samples[0]);i++)printf("%u\\n",bits(stb_perlin_noise3_seed(samples[i][0],samples[i][1],samples[i][2],0,0,0,(int)samples[i][3])));}\n')
    binary = work/'reference'
    run(['clang','-std=c11','-O3','-ffp-contract='+('on' if fused else 'off'),'-I'+str(args.raylib_source/'src'),source,'-lm','-o',binary])
    expected = [int(word) for word in run([binary]).split()]
    if len(expected)!=1024+len(values):raise ValueError('Incomplete Perlin reference output')
    report = dict(passed=False,reference='pinned stb_perlin compiled with explicit FP contraction',
                  profile='fused' if fused else 'uncontracted',table_cells=1024,octave_samples=len(values),
                  inputs_sha256=hashlib.sha256(json.dumps(values).encode()).hexdigest(),sources=source_gate(),lanes={})
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        program = '''import Base
import ../../src/perlin.bend as P
type Sample is Data:
  Sample{x: F32, y: F32, z: F32, seed: U32}
def tables(n: Nat, +index: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: List.reverse(&1, U32, values)
    case 1n+rest: tables(rest, (index + 1 : U32), Con{P.gradients(index), Con{P.permutation(index), values}})
def calculate(samples: +List<Sample>, values: List<U32>) -> List<U32>:
  match samples:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{Sample{x, y, z, seed}, rest}: calculate(rest, Con{F32.bits(P.noise(PROFILE, x, y, z, seed)), values})
def main() -> IO(Unit):
  do IO<Unit>:
'''.replace('PROFILE','True{}' if fused else 'False{}')
        bang = '!' if lane=='metal' else ''
        for start in range(0,512,64):program += f'    IO.print(List.show(~&1, ~U32, ~U32.show, tables{bang}(64n, {start}, Nil{{}})))\n'
        for start in range(0,len(values),16):
            inputs = ','.join('Sample{'+','.join(f32(v) for v in row[:3])+','+str(row[3])+'}' for row in values[start:start+16])
            program += f'    IO.print(List.show(~&1, ~U32, ~U32.show, calculate{bang}([{inputs}], Nil{{}})))\n'
        candidate = work/f'{lane}.bend';candidate.write_text(program)
        output = work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',candidate,'-o',output],timeout=600)
        command = ['bun',output] if lane=='javascript' else [output,*(['--gpu','on'] if lane=='metal' else [])]
        actual = [word for line in run(command).splitlines() for word in json.loads(line)]
        differences = [dict(index=i,reference=a,candidate=b) for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane] = dict(passed=actual==expected,mismatch_count=len(differences),differences=differences[:12])
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: Perlin table/octave mismatch: {differences[:3]}')
        print(f'{lane}: 1024 table cells and {len(values)} {report["profile"]} octave results match exactly',flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
