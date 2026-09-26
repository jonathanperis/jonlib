#!/usr/bin/env python3
"""Compare complete byte/integer ImageFormat conversions and chains with raylib."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import sys

from conformance import BUILD, ROOT, checkout, run, source_gate


def cases():
    rng = random.Random(0xF07A7)
    widths = {1:1,2:2,3:2,4:3,5:2,6:2,7:4}
    result = []
    for source, bpp in widths.items():
        data = [rng.randrange(256) for _ in range(12*bpp)]
        data[:bpp] = [0]*bpp
        data[bpp:2*bpp] = [255]*bpp
        data[2*bpp:3*bpp] = [1,*([0]*(bpp-1))]
        if source==7:
            data[12:24] = [127,128,129,49, 17,63,201,50, 17,63,201,51]
        for target in range(8):
            result.append(dict(width=4,height=3,source=source,bytes=data,targets=[target],bridge=False))
        chain = [3,1,2,5,6,4,7]
        for count in range(2,len(chain)+1):
            result.append(dict(width=4,height=3,source=source,bytes=data,targets=chain[:count],bridge=False))
        result.append(dict(width=4,height=3,source=source,bytes=data,targets=[0],bridge=True))
        if source in (6,7):
            for count in range(2,4):
                result.append(dict(width=4,height=3,source=source,bytes=data,targets=[6,5,7][:count],bridge=False))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args = parser.parse_args()
    if sys.byteorder!='little':raise ValueError('Current formatted-image profile requires a little-endian reference')
    lock = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    work = BUILD/'image-format-probe';work.mkdir(parents=True,exist_ok=True)
    report_path = work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    inputs = cases()
    lines = ['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in inputs:
        lines += ['{', 'unsigned char input[]={'+','.join(map(str,case['bytes']))+'};',
                  f'Image image={{malloc(sizeof(input)),{case["width"]},{case["height"]},1,{case["source"]}}};',
                  'memcpy(image.data,input,sizeof(input));']
        for target in case['targets']:lines += [f'ImageFormat(&image,{target});']
        if case['bridge']:lines += ['ImageFormat(&image,7);']
        lines += ['printf("{\\"width\\":%d,\\"height\\":%d,\\"format\\":%d,\\"bytes\\":[",image.width,image.height,image.format);',
                  'int size=GetPixelDataSize(image.width,image.height,image.format);',
                  'for(int i=0;i<size;i++)printf("%s%u",i?",":"",((unsigned char*)image.data)[i]);',
                  'puts("]}");UnloadImage(image);','}']
    source = work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n')
    binary = work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    reference_text = run([binary]);expected = [json.loads(line) for line in reference_text.splitlines()]
    if len(expected)!=len(inputs):raise ValueError('Incomplete ImageFormat reference output')
    report = dict(passed=False,format_pairs=49,cases=len(inputs),checked_bytes=sum(len(row['bytes']) for row in expected),
                  inputs_sha256=hashlib.sha256(json.dumps(inputs).encode()).hexdigest(),reference_sha256=hashlib.sha256(reference_text.encode()).hexdigest(),
                  sources=source_gate(),lanes={})
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        program = '''import Base
import ../../jonlib.bend as J
def chain(targets: +List<U32>, result: Result<&1, &1, J.Image.Formatted & J.Pixel.Error, J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match targets result:
    case _ Fail{_}: None{}
    case Nil{} Done{image}: Some{image}
    case Con{target, rest} Done{image}: chain(rest, J.Image.Formatted.convert(image, target))
def created(result: Maybe<J.Image.Formatted>, targets: +List<U32>) -> Maybe<J.Image.Formatted>:
  match result:
    case None{}: None{}
    case Some{image}: chain(targets, Done{image})
def bridged(bridge: Bool, result: Maybe<J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match bridge result:
    case False{} _: result
    case True{} None{}: None{}
    case True{} Some{image}: Some{J.Surface.to_formatted(J.Image.Formatted.to_surface(image))}
def calculate(width: U32, height: U32, format: U32, bytes: +List<U32>, targets: +List<U32>, bridge: Bool) -> Maybe<J.Image.Formatted>:
  bridged(bridge, created(J.Image.Formatted.from_bytes(width, height, format, bytes), targets))
def emit(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = data
  IO.print("{\\"width\\":" ++ U32.show(width) ++ ",\\"height\\":" ++ U32.show(height) ++ ",\\"format\\":" ++ U32.show(format) ++ ",\\"bytes\\":" ++ List.show(~&1, ~U32, ~U32.show, bytes) ++ "}")
def observed(result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid image-format request rejected")
    case Some{image}: emit(J.Image.Formatted.export(image))
def main() -> IO(Unit):
  do IO<Unit>:
'''
        bang = '!' if lane=='metal' else ''
        for case in inputs:
            data = ','.join(map(str,case['bytes']))
            targets = ','.join(map(str,case['targets']))
            program += f'    observed(calculate{bang}({case["width"]}, {case["height"]}, {case["source"]}, [{data}], [{targets}], {"True{}" if case["bridge"] else "False{}"}))\n'
        source = work/f'{lane}.bend';source.write_text(program)
        binary = work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command = ['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual = [json.loads(line) for line in run(command).splitlines()]
        differences = [dict(case=i,input=inputs[i],reference=a,candidate=b) for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane] = dict(passed=actual==expected,mismatch_count=len(differences),differences=differences[:5])
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: image-format mismatch: {differences[:1]}')
        print(f'{lane}: {len(inputs)} complete format-pair/chain/bridge results match {report["checked_bytes"]} native bytes',flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
