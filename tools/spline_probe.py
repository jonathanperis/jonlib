#!/usr/bin/env python3
"""Verify spline points against linked raylib or its uncontracted source control."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct

from conformance import BUILD, ROOT, checkout, f32, run, source_gate, spline_reference


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
    profile = 'UncontractedSpline' if args.uncontracted_control else spline_reference()
    work = BUILD/('spline-probe-uncontracted' if args.uncontracted_control else 'spline-probe')
    work.mkdir(parents=True,exist_ok=True)
    report_path = work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    fp = lambda value: struct.unpack('f',struct.pack('f',value))[0]
    points = [1.25,-2.75,3.5,-4.25,-0.3,0.7,1.1,-0.2]
    values = [[*points,t] for t in (0.0,1.0,0.3,0.5,0.9999999403953552)]
    values += [[-0.0,0.0,-0.0,-0.0,0.0,-0.0,-0.0,0.0,0.5]]
    rng = random.Random(0x5B11)
    values += [[*(rng.uniform(-100,100) for _ in range(8)),rng.random()] for _ in range(122)]
    values = [[fp(value) for value in row] for row in values]
    lines = ['#include "raylib.h"','#include <math.h>','#include <stdio.h>','#include <stdint.h>','#include <string.h>']
    if args.uncontracted_control:
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
    source = work/'reference.c';source.write_text('\n'.join(lines)+'\n')
    reference = work/'reference'
    library = [] if args.uncontracted_control else [BUILD/'raylib/raylib/libraylib.a']
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,*library,'-lm','-o',reference])
    words = [int(word) for word in run([reference]).split()]
    if len(words)!=8*len(values)+2:raise ValueError('Incomplete spline reference results')
    expected = words[:-2]
    report = dict(passed=False,reference='uncontracted source control' if args.uncontracted_control else 'linked raylib',
                  profile=profile,point_results=4*len(values),sources=source_gate(),
                  inputs_sha256=hashlib.sha256(json.dumps(values).encode()).hexdigest(),lanes={},
                  cubic_power_diagnostic=dict(t_hex='0x1.940af8p-2',reference_x=f'{words[-2]:08x}',double_cube=f'{words[-1]:08x}',substitute_matches=words[-2]==words[-1]))
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        program = '''import Base
import ../../jonlib.bend as J
type Sample is Data:
  Sample{a: J.Vector2, b: J.Vector2, c: J.Vector2, d: J.Vector2, t: F32}
def prepend(point: J.Vector2, values: List<U32>) -> List<U32>:
  J.Vector2{x, y} = point
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
'''.replace('PROFILE',profile)
        for start in range(0,len(values),8):
            inputs = ','.join('Sample{'+','.join('J.Vector2{'+','.join(f32(v) for v in row[index:index+2])+'}' for index in range(0,8,2))+','+f32(row[8])+'}' for row in values[start:start+8])
            program += f'    IO.print(List.show(~&1, ~U32, ~U32.show, calculate{"!" if lane=="metal" else ""}([{inputs}], Nil{{}})))\n'
        source = work/f'{lane}.bend';source.write_text(program)
        binary = work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command = ['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual = [word for line in run(command).splitlines() for word in json.loads(line)]
        differences = [dict(index=i,reference=a,candidate=b) for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane] = dict(passed=actual==expected,mismatch_count=len(differences),differences=differences[:12])
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: spline result mismatch: {differences[:3]}')
        print(f'{lane}: {len(values)*4} spline points match exact {report["reference"]} bits ({profile})',flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
