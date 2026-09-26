#!/usr/bin/env python3
"""Compare owned random streams and post-noise state with actual pinned raylib."""
import argparse
import hashlib
import json
from pathlib import Path

from conformance import BUILD, ROOT, checkout, f32, run, source_gate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args = parser.parse_args()
    lock = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    library = BUILD/'raylib/raylib/libraylib.a'
    if not library.is_file():raise ValueError('Run conformance.py first to build the declared reference')
    seeds = [0,1,4294967295,2864434397,2147483648,20260926]
    ranges = [(-3,5),(10,-10),(7,7),(0,99),(-32767,32767)]*32
    tails = [(0,3,2,0.0),(0,3,2,1.0),(1,7,5,0.37)]
    work = BUILD/'random-probe';work.mkdir(parents=True,exist_ok=True)
    report_path = work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    lines = ['#include "raylib.h"','#include <stdio.h>','#include <string.h>',
             'static unsigned bits(float v){unsigned b;memcpy(&b,&v,4);return b;}',
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    for seed in seeds:
        lines += [f'SetRandomSeed({seed}u);','putchar(\'[\');']
        for index,(lower,upper) in enumerate(ranges):
            lines += [f'printf("{"," if index else ""}%u",bits((float)GetRandomValue({lower},{upper})));']
        lines += ['puts("]");']
    for seed,w,h,factor in tails:
        lines += ['{',f'SetRandomSeed({seed}u); Image image=GenImageWhiteNoise({w},{h},{factor}f);',
                  'UnloadImage(image); printf("[%u]\\n",bits((float)GetRandomValue(-100,100)));','}']
    (work/'reference.c').write_text('\n'.join(lines+['}'])+'\n')
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),work/'reference.c',library,'-lm','-o',work/'reference'])
    expected = [json.loads(line) for line in run([work/'reference']).splitlines()]
    if len(expected)!=len(seeds)+len(tails):raise ValueError('Incomplete random reference rows')
    report = dict(passed=False,seeds=seeds,draws_per_seed=len(ranges),post_noise_observations=len(tails),
                  profile='rprand-xoshiro128starstar-v1',sources=source_gate(),
                  inputs_sha256=hashlib.sha256(json.dumps([seeds,ranges,tails]).encode()).hexdigest(),lanes={})
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        program = '''import Base
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
def main() -> IO(Unit):
  do IO<Unit>:
'''
        bang = '!' if lane=='metal' else ''
        requests = ','.join(f'Range{{{f32(a)}, {f32(b)}}}' for a,b in ranges)
        for seed in seeds:program += f'    IO.print(List.show(~&1, ~U32, ~U32.show, stream{bang}({seed}, [{requests}])))\n'
        for seed,w,h,factor in tails:program += f'    IO.print(List.show(~&1, ~U32, ~U32.show, noise_tail{bang}({seed}, {w}, {h}, {f32(factor)})))\n'
        source = work/f'{lane}.bend';source.write_text(program)
        binary = work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command = ['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual = [json.loads(line) for line in run(command).splitlines()]
        report['lanes'][lane] = dict(passed=actual==expected)
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: random stream or post-noise state mismatch')
        print(f'{lane}: {len(seeds)*len(ranges)} random values and {len(tails)} post-noise observations match native raylib',flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
