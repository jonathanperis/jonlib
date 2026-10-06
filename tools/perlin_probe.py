#!/usr/bin/env python3
"""Verify packed stb_perlin tables and octave bits under explicit compiler arithmetic."""
import hashlib
import json
import random
import struct

from conformance import f32, noise_reference, source_gate
import probekit
from probekit import ProbeFailure

PROGRAM = '''import Base
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
'''


def samples():
    fp = lambda value: struct.unpack('f',struct.pack('f',value))[0]
    values = [(x,y,1.0,seed) for x,y in ((0,0),(-1.25,2.75),(255.99,-256.01),(-0.0,-0.0),(0.0000152587890625,-0.5)) for seed in range(6)]
    rng = random.Random(0x5B7B)
    values += [(fp(rng.uniform(-300,300)),fp(rng.uniform(-300,300)),float(1<<rng.randrange(6)),rng.randrange(6)) for _ in range(192)]
    return values


def main():
    args = probekit.arguments(__doc__,lambda parser:parser.add_argument('--uncontracted-control',action='store_true'))
    probe = probekit.Probe('perlin-uncontracted' if args.uncontracted_control else 'perlin',args)
    probe.report['sources'] = source_gate()
    fused = not args.uncontracted_control and noise_reference()=='FusedNoise'
    values = samples()
    text = probe.native('#include <stdio.h>\n#include <string.h>\n'+
        ('#pragma STDC FP_CONTRACT ON\n' if fused else '#pragma STDC FP_CONTRACT OFF\n')+
        '#define STB_PERLIN_IMPLEMENTATION\n#include "external/stb_perlin.h"\n'+
        'static const float samples[][4]={'+','.join('{'+','.join(float(v).hex()+'f' for v in row)+'}' for row in values)+'};\n'+
        'static unsigned bits(float x){unsigned b;memcpy(&b,&x,4);return b;}\n'+
        'int main(void){for(int i=0;i<512;i++)printf("%u %u\\n",stb__perlin_randtab[i],stb__perlin_randtab_grad_idx[i]);'+
        'for(unsigned i=0;i<sizeof(samples)/sizeof(samples[0]);i++)printf("%u\\n",bits(stb_perlin_noise3_seed(samples[i][0],samples[i][1],samples[i][2],0,0,0,(int)samples[i][3])));}\n',
        extra_flags=['-O3','-ffp-contract='+('on' if fused else 'off')])
    words = [int(word) for word in text.split()]
    if len(words)!=1024+len(values):raise ProbeFailure('Incomplete Perlin reference output')
    # One action per printed line: 64-entry table chunks (permutation, gradient pairs), then 16-sample octave chunks.
    actions = [('tables',start) for start in range(0,512,64)]+[('samples',start) for start in range(0,len(values),16)]
    expected = [words[2*start:2*start+128] if kind=='tables' else words[1024+start:1024+start+16] for kind,start in actions]

    def render(selected,gpu):
        bang = '!' if gpu else '';body = PROGRAM.replace('PROFILE','True{}' if fused else 'False{}')
        for kind,start in selected:
            if kind=='tables':body += f'    IO.print(List.show(~&1, ~U32, ~U32.show, tables{bang}(64n, {start}, Nil{{}})))\n'
            else:
                inputs = ','.join('Sample{'+','.join(f32(v) for v in row[:3])+','+str(row[3])+'}' for row in values[start:start+16])
                body += f'    IO.print(List.show(~&1, ~U32, ~U32.show, calculate{bang}([{inputs}], Nil{{}})))\n'
        return body

    probe.compare(expected,probe.candidates(render,actions,batch=len(actions)),describe=lambda index:f'{actions[index][0]} chunk at {actions[index][1]}')
    probe.finish(reference='pinned stb_perlin compiled with explicit FP contraction',profile='fused' if fused else 'uncontracted',
                 table_cells=1024,octave_samples=len(values),inputs_sha256=hashlib.sha256(json.dumps(values).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
