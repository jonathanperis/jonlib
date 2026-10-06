#!/usr/bin/env python3
"""Verify spline points against linked raylib or its uncontracted source control."""
import hashlib
import json
import random
import struct

from conformance import f32, source_gate, spline_reference
import probekit
from probekit import ProbeFailure

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
type Sample is Data:
  Sample{a: M.Vector2, b: M.Vector2, c: M.Vector2, d: M.Vector2, t: F32}
def prepend(point: M.Vector2, values: List<U32>) -> List<U32>:
  M.Vector2{x, y} = point
  Con{F32.bits(y), Con{F32.bits(x), values}}
def calculate(samples: +List<Sample>, values: List<U32>) -> List<U32>:
  match samples:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{Sample{+a, +b, +c, +d, +t}, rest}:
      first = prepend(J.Spline.linear_for(J.PROFILE{}, a, b, t), values)
      second = prepend(J.Spline.basis_for(J.PROFILE{}, a, b, c, d, t), first)
      third = prepend(J.Spline.catmull_rom_for(J.PROFILE{}, a, b, c, d, t), second)
      fourth = prepend(J.Spline.bezier_quad_for(J.PROFILE{}, a, b, c, t), third)
      calculate(rest, fourth)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def samples():
    fp = lambda value: struct.unpack('f',struct.pack('f',value))[0]
    points = [1.25,-2.75,3.5,-4.25,-0.3,0.7,1.1,-0.2]
    values = [[*points,t] for t in (0.0,1.0,0.3,0.5,0.9999999403953552)]
    values += [[-0.0,0.0,-0.0,-0.0,0.0,-0.0,-0.0,0.0,0.5]]
    rng = random.Random(0x5B11)
    values += [[*(rng.uniform(-100,100) for _ in range(8)),rng.random()] for _ in range(122)]
    return [[fp(value) for value in row] for row in values]


def main():
    args = probekit.arguments(__doc__,lambda parser:parser.add_argument('--uncontracted-control',action='store_true'))
    probe = probekit.Probe('spline-uncontracted' if args.uncontracted_control else 'spline',args)
    probe.report['sources'] = source_gate()
    profile = 'UncontractedSpline' if args.uncontracted_control else spline_reference()
    values = samples()
    lines = ['#include "raylib.h"','#include <math.h>','#include <stdio.h>','#include <stdint.h>','#include <string.h>']
    if args.uncontracted_control:
        # The local definitions take precedence; nothing from the linked library is referenced.
        source = (args.raylib_source/'src/rshapes.c').read_text()
        begin = source.index('Vector2 GetSplinePointLinear(')
        end = source.index('//----------------------------------------------------------------------------------',begin)
        lines += ['/* Unaltered spline functions from pinned raylib; zlib, LICENSES/raylib.txt. */',
                  '#pragma STDC FP_CONTRACT OFF',source[begin:end]]
    lines += ['static const float samples[][9]={'+','.join('{'+','.join(v.hex()+'f' for v in row)+'}' for row in values)+'};',
              'static unsigned bits(float x){unsigned b;memcpy(&b,&x,4);return b;}',
              'static void emit(Vector2 point){printf("%u %u\\n",bits(point.x),bits(point.y));}',
              'int main(void){for(unsigned i=0;i<sizeof(samples)/sizeof(samples[0]);i++){',
              'const float *v=samples[i];Vector2 a={v[0],v[1]},b={v[2],v[3]},c={v[4],v[5]},d={v[6],v[7]};',
              'emit(GetSplinePointLinear(a,b,v[8]));emit(GetSplinePointBasis(a,b,c,d,v[8]));',
              'emit(GetSplinePointCatmullRom(a,b,c,d,v[8]));emit(GetSplinePointBezierQuad(a,b,c,v[8]));}',
              'volatile float input=0x1.940af8p-2f; float t=input;',
              'Vector2 cubic=GetSplinePointBezierCubic((Vector2){0,0},(Vector2){0,0},(Vector2){0,0},(Vector2){1,0},t);',
              'printf("%u %u\\n",bits(cubic.x),bits((float)((double)t*(double)t*(double)t)));}']
    text = probe.native('\n'.join(lines)+'\n')
    words = [int(word) for word in text.split()]
    if len(words)!=8*len(values)+2:raise ProbeFailure('Incomplete spline reference results')
    # One action per 8-sample chunk; each sample yields four points (eight words).
    starts = list(range(0,len(values),8))
    expected = [words[8*start:8*min(start+8,len(values))] for start in starts]

    def render(selected,gpu):
        body = PROGRAM.replace('PROFILE',profile)
        for start in selected:
            inputs = ','.join('Sample{'+','.join('M.Vector2{'+','.join(f32(v) for v in row[index:index+2])+'}' for index in range(0,8,2))+','+f32(row[8])+'}' for row in values[start:start+8])
            body += f'    IO.print(List.show(~&1, ~U32, ~U32.show, calculate{"!" if gpu else ""}([{inputs}], Nil{{}})))\n'
        return body

    probe.compare(expected,probe.candidates(render,starts,batch=len(starts)),describe=lambda index:f'samples {starts[index]}..{starts[index]+7}')
    probe.finish(reference='uncontracted source control' if args.uncontracted_control else 'linked raylib',
                 profile=profile,point_results=4*len(values),inputs_sha256=hashlib.sha256(json.dumps(values).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest(),
                 cubic_power_diagnostic=dict(t_hex='0x1.940af8p-2',reference_x=f'{words[-2]:08x}',double_cube=f'{words[-1]:08x}',substitute_matches=words[-2]==words[-1]))


if __name__ == '__main__':
    main()
