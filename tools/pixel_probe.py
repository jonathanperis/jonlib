#!/usr/bin/env python3
"""Compare all-format size boundaries and complete raw ImageDither outputs."""
import argparse
import hashlib
import json
from pathlib import Path
import random

from conformance import BUILD, ROOT, checkout, run, source_gate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args = parser.parse_args()
    lock = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    work = BUILD/'pixel-probe';work.mkdir(parents=True,exist_ok=True)
    report_path = work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    dimensions = [0,1,2,3,4,5,7,8,9,16,31,256,4096]
    sizes = [(w,h,f) for w in dimensions for h in dimensions for f in [*range(26),2147483647]]
    rng = random.Random(0xD17E)
    patterns = [(1,1,[0xffffffff]),(4,1,[0x12345600,0x1234567f,0x12345680,0x123456ff]),
                (1,5,[rng.getrandbits(32) for _ in range(5)]),
                (7,5,[rng.getrandbits(32) for _ in range(35)]),
                (3,3,[0xfaf9f780,0xfdfefc01,0xffffffff]*3),
                (2,2,[0,0xff000000,0x00ff00ff,0x0000ff7f])]
    layouts = [(5,6,5,0),(5,5,5,1),(4,4,4,4),(2,3,4,2),(8,8,0,0),(0,0,0,8),(0,0,0,0)]
    cases = [(w,h,pixels,bits) for w,h,pixels in patterns for bits in layouts]
    lines = ['#include "raylib.h"','#include <stdio.h>',
             'static const unsigned sizes[][3]={'+','.join('{'+','.join(map(str,entry))+'}' for entry in sizes)+'};',
             'int main(void){SetTraceLogLevel(LOG_NONE);printf("[");',
             'for(unsigned i=0;i<sizeof(sizes)/sizeof(sizes[0]);i++)printf("%s%d",i?",":"",GetPixelDataSize(sizes[i][0],sizes[i][1],sizes[i][2]));',
             'puts("]");']
    for w,h,pixels,bits in cases:
        lines += ['{',f'Image image=GenImageColor({w},{h},BLANK);',
                  'unsigned input[]={'+','.join(str(value)+'u' for value in pixels)+'};',
                  f'for(int i=0;i<{w*h};i++)((Color*)image.data)[i]=GetColor(input[i]);',
                  f'ImageDither(&image,{",".join(map(str,bits))});',
                  'printf("{\\"width\\":%d,\\"height\\":%d,\\"format\\":%d,\\"words\\":[",image.width,image.height,image.format);',
                  f'for(int i=0;i<{w*h};i++)printf("%s%u",i?",":"",((unsigned short*)image.data)[i]);',
                  'puts("]}");UnloadImage(image);','}']
    source = work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n')
    binary = work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    reference = [json.loads(line) for line in run([binary]).splitlines()]
    if len(reference)!=len(cases)+1 or len(reference[0])!=len(sizes):raise ValueError('Incomplete pixel reference results')
    report = dict(passed=False,size_cases=len(sizes),dither_cases=len(cases),
                  packed_words=sum(w*h for w,h,_,_ in cases),sources=source_gate(),
                  inputs_sha256=hashlib.sha256(json.dumps([sizes,cases]).encode()).hexdigest(),lanes={})
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        program = '''import Base
import ../../jonlib.bend as J
type Size is Data:
  Size{width: U32, height: U32, format: U32}
def size_value(value: Maybe<&2, U32>) -> U32:
  match value:
    case None{}: 4294967295
    case Some{n}: n
def sizes(input: +List<Size>, values: List<U32>) -> List<U32>:
  match input:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{Size{w, h, format}, rest}: sizes(rest, Con{size_value(J.Pixel.data_size(w, h, format)), values})
def fill(values: +List<U32>, +index: U32, +width: U32, surface: J.Surface) -> J.Surface:
  match values:
    case Nil{}: surface
    case Con{color, rest}: fill(rest, (index + 1 : U32), width, J.Surface.draw_pixel(surface, U32.to_f32((index % width : U32)), U32.to_f32((index / width : U32)), color))
def dithered(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Image.Packed16>) -> Maybe<J.Image.Packed16>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{image}
def created(image: Maybe<J.Surface>, width: U32, values: +List<U32>, r: U32, g: U32, b: U32, a: U32) -> Maybe<J.Image.Packed16>:
  match image:
    case None{}: None{}
    case Some{surface}: dithered(J.Surface.dither(fill(values, 0, width, surface), r, g, b, a))
def calculate(+width: U32, height: U32, values: +List<U32>, r: U32, g: U32, b: U32, a: U32) -> Maybe<J.Image.Packed16>:
  created(J.Surface.create(width, height, 0), width, values, r, g, b, a)
def emit(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((w, h), (format, words)) = data
  IO.print("{\\"width\\":" ++ U32.show(w) ++ ",\\"height\\":" ++ U32.show(h) ++ ",\\"format\\":" ++ U32.show(format) ++ ",\\"words\\":" ++ List.show(~&1, ~U32, ~U32.show, words) ++ "}")
def observed(result: Maybe<J.Image.Packed16>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid dithering request rejected")
    case Some{image}: emit(J.Image.Packed16.export(image))
def main() -> IO(Unit):
  do IO<Unit>:
'''
        bang = '!' if lane=='metal' else ''
        for start in range(0,len(sizes),64):
            inputs = ','.join('Size{'+','.join(map(str,row))+'}' for row in sizes[start:start+64])
            program += f'    IO.print(List.show(~&1, ~U32, ~U32.show, sizes{bang}([{inputs}], Nil{{}})))\n'
        for w,h,pixels,bits in cases:
            program += f'    observed(calculate{bang}({w}, {h}, ['+','.join(map(str,pixels))+'], '+','.join(map(str,bits))+'))\n'
        source = work/f'{lane}.bend';source.write_text(program)
        binary = work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command = ['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        rows = [json.loads(line) for line in run(command).splitlines()]
        chunks = (len(sizes)+63)//64
        actual = [[word for row in rows[:chunks] for word in row],*rows[chunks:]]
        report['lanes'][lane] = dict(passed=actual==reference)
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=reference:raise ValueError(f'{lane}: size/packed-dither metadata or content mismatch')
        print(f'{lane}: {len(sizes)} size results and {len(cases)} complete packed dithering outputs match native raylib',flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
