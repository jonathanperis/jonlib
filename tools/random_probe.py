#!/usr/bin/env python3
"""Compare owned random streams and post-noise state with actual pinned raylib."""
import hashlib
import json

from conformance import f32, source_gate
import probekit
from probekit import ProbeFailure

PROGRAM = '''import Base
import ../../jonlib.bend as J
type Range is Data:
  Range{lower: F32, upper: F32}
def collected(result: J.Random.State & F32, values: List<U32>) -> J.Random.State & List<U32>:
  (state, value) = result
  (state, Con{F32.bits(value), values})
def draws(ranges: +List<Range>, data: J.Random.State & List<U32>) -> List<U32>:
  match ranges data:
    case Nil{} Tuple{_, values}: List.reverse(&1, U32, values)
    case Con{Range{lower, upper}, rest} Tuple{state, values}:
      draws(rest, collected(J.Random.value(state, lower, upper), values))
def stream(seed: U32, ranges: +List<Range>) -> List<U32>:
  draws(ranges, (J.Random.seed(seed), Nil{}))
def tail_value(result: J.Random.State & F32) -> List<U32>:
  (_, value) = result
  [F32.bits(value)]
def after_noise(result: J.Random.State & Maybe<J.Surface>) -> List<U32>:
  match result:
    case Tuple{state, Some{_}}: tail_value(J.Random.value(state, F32.neg(100.0), 100.0))
    case _: Nil{}
def noise_tail(seed: U32, width: U32, height: U32, factor: F32) -> List<U32>:
  after_noise(J.Surface.create_white_noise(J.Random.seed(seed), width, height, factor))
def cellular_tail(seed: U32, width: U32, height: U32, tile: U32) -> List<U32>:
  after_noise(J.Surface.create_cellular(J.Random.seed(seed), width, height, tile))
def sequence_words(values: +List<F32>, tail: List<U32>) -> List<U32>:
  match values:
    case Nil{}: tail
    case Con{value, rest}: Con{F32.bits(value), sequence_words(rest, tail)}
def sequence_observed(result: J.Random.State & Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>) -> List<U32>:
  match result:
    case Tuple{state, Done{sequence}}:
      Con{1, sequence_words(J.Random.Sequence.values(sequence), tail_value(J.Random.value(state, F32.neg(100.0), 100.0)))}
    case Tuple{state, Fail{J.InvalidSequenceRequest{}}}:
      Con{0, tail_value(J.Random.value(state, F32.neg(100.0), 100.0))}
    case Tuple{_, Fail{J.SequenceDrawLimit{_}}}: [2]
def sequence_sample(seed: U32, count: U32, lower: F32, upper: F32) -> List<U32>:
  sequence_observed(J.Random.load_sequence(J.Random.seed(seed), count, lower, upper, 4096n))
def main() -> IO(Unit):
  do IO<Unit>:
'''
SEEDS = [0,1,4294967295,2864434397,2147483648,20260926]
# Fractional bounds exercise GetRandomValue(int,int)'s implicit truncation.
RANGES = [(-3,5),(10,-10),(7,7),(0,99),(-32767,32767),(-3.7,5.9),(10.2,-10.8),(-0.5,0.5)]*20
TAILS = [(0,3,2,0.0),(0,3,2,1.0),(1,7,5,0.37)]
SEQUENCES = [(0,5,-3,5),(1,21,-10,10),(4294967295,1,7,7),
             (0,3,10,8),(123,0,-2,2),(123,4,5,7),(42,64,0,63)]
CELLULAR_TAILS = [(0,3,2,1),(42,17,11,4),(1,5,3,8)]


def reference_program():
    lines = ['#include "raylib.h"','#include <stdio.h>','#include <string.h>',
             'static unsigned bits(float v){unsigned b;memcpy(&b,&v,4);return b;}',
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    for seed in SEEDS:
        lines += [f'SetRandomSeed({seed}u);','putchar(\'[\');']
        for index,(lower,upper) in enumerate(RANGES):
            lines += [f'printf("{"," if index else ""}%u",bits((float)GetRandomValue({lower},{upper})));']
        lines += ['puts("]");']
    for seed,w,h,factor in TAILS:
        lines += ['{',f'SetRandomSeed({seed}u); Image image=GenImageWhiteNoise({w},{h},{factor}f);',
                  'UnloadImage(image); printf("[%u]\\n",bits((float)GetRandomValue(-100,100)));','}']
    for seed,count,lower,upper in SEQUENCES:
        lines += ['{',f'SetRandomSeed({seed}u); int *sequence=LoadRandomSequence({count}u,{lower},{upper});',
                  f'int accepted=({count}==0 || sequence!=NULL); printf("[%d",accepted);',
                  f'if(accepted) for(unsigned i=0;i<{count};i++) printf(",%u",bits((float)sequence[i]));',
                  'UnloadRandomSequence(sequence); printf(",%u]\\n",bits((float)GetRandomValue(-100,100)));','}']
    for seed,w,h,tile in CELLULAR_TAILS:
        lines += ['{',f'SetRandomSeed({seed}u); Image image=GenImageCellular({w},{h},{tile});',
                  'UnloadImage(image); printf("[%u]\\n",bits((float)GetRandomValue(-100,100)));','}']
    return '\n'.join(lines+['}'])+'\n'


def main():
    probe = probekit.Probe('random',probekit.arguments(__doc__))
    probe.report['sources'] = source_gate()
    text = probe.native(reference_program())
    expected = [json.loads(line) for line in text.splitlines()]
    if len(expected)!=len(SEEDS)+len(TAILS)+len(SEQUENCES)+len(CELLULAR_TAILS):raise ProbeFailure('Incomplete random reference rows')
    requests = ','.join(f'Range{{{f32(a)}, {f32(b)}}}' for a,b in RANGES)
    actions = ([('stream',seed) for seed in SEEDS]+[('noise_tail',*row) for row in TAILS]+
               [('sequence_sample',*row) for row in SEQUENCES]+[('cellular_tail',*row) for row in CELLULAR_TAILS])

    def call(action):
        name,*values = action
        if name=='stream':return f'{values[0]}, [{requests}]'
        if name=='noise_tail':return f'{values[0]}, {values[1]}, {values[2]}, {f32(values[3])}'
        if name=='sequence_sample':return f'{values[0]}, {values[1]}, {f32(values[2])}, {f32(values[3])}'
        return ', '.join(map(str,values))

    def render(selected,gpu):
        bang = '!' if gpu else ''
        return PROGRAM+''.join(f'    IO.print(List.show(~&1, ~U32, ~U32.show, {action[0]}{bang}({call(action)})))\n' for action in selected)

    probe.compare(expected,probe.candidates(render,actions,batch=len(actions)))
    probe.finish(seeds=SEEDS,draws_per_seed=len(RANGES),post_noise_observations=len(TAILS),
                 sequence_cases=len(SEQUENCES),sequence_draw_budget=4096,post_cellular_observations=len(CELLULAR_TAILS),
                 profile='rprand-xoshiro128starstar-v1',
                 inputs_sha256=hashlib.sha256(json.dumps([SEEDS,RANGES,TAILS,SEQUENCES,CELLULAR_TAILS]).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
