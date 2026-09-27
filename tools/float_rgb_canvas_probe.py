#!/usr/bin/env python3
"""Compare native RGB float canvas/POT movement and ignored fill colors."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, run, source_gate


def pixels(width,height):
    words=[0x3f000000,0xc0400000,1,0x80000000,0x7f800000,0xff800000,0x7f7fffff,0x007fffff,0xbf800000]
    return list(struct.pack('<'+'I'*(width*height*3),*[words[i%len(words)] for i in range(width*height*3)]))


def fixtures():
    cases=[]
    for fill in (0xff0000ff,0x11223300):
        for width,height,x,y in ((5,4,1,1),(2,2,-1,-1),(2,1,0,0),(4,4,-1,1),(4,1,2,0),(3,2,100,-100)):
            cases.append(dict(kind='canvas',width=3,height=2,target_width=width,target_height=height,x=x,y=y,fill=fill,bytes=pixels(3,2)))
    for width,height in ((1,1),(2,2),(3,2),(5,3),(17,1),(4096,1)):
        cases.append(dict(kind='pot',width=width,height=height,target_width=1<<(width-1).bit_length(),target_height=1<<(height-1).bit_length(),x=0,y=0,fill=0xffffffff,bytes=pixels(width,height)))
    controls=[dict(kind='canvas',width=3,height=2,target_width=w,target_height=h,x=x,y=y,fill=0xff0000ff,bytes=pixels(3,2),error=error)
              for w,h,x,y,error in ((0,2,0,0,0),(2,4097,0,0,0),(5,4,0.5,0,1),(5,4,-3,0,1),(5,4,6,0,1),(3,2,32768,0,1))]
    return cases,controls


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'float-rgb-canvas-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases,controls=fixtures();lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
        'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
        'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
        'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
        'static void emit(Image image){if(!image.data||image.format!=PIXELFORMAT_UNCOMPRESSED_R32G32B32)exit(2);word(image.width);word(image.height);',
        'for(int i=0;i<image.width*image.height*12;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
        'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate([*cases,*controls]):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},PIXELFORMAT_UNCOMPRESSED_R32G32B32,0);')
        if i<len(cases):
            if case['kind']=='pot':lines.append(f'ImageToPOT(&image,GetColor({case["fill"]}u));')
            else:lines.append(f'ImageResizeCanvas(&image,{case["target_width"]},{case["target_height"]},{case["x"]},{case["y"]},GetColor({case["fill"]}u));')
        lines.append('emit(image);}')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(cases)+len(controls):raise ValueError('Incomplete native float canvas output')
    for case,row in zip(cases,expected):
        w,h=case['target_width'],case['target_height']
        if row[:8]!=list(struct.pack('<II',w,h)) or len(row)!=8+w*h*12:raise ValueError('Native canvas dimensions differ')
    report=dict(passed=False,native_cases=len(cases),pixels=sum(c['target_width']*c['target_height'] for c in cases),retained_owner_controls=len(controls),sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
import ../../jonlib.bend as J
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
'''+BEND_EMITTER+'''
def emitted(+width: U32, +height: U32, result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "canvas sample representation changed")
    case Done{bytes}:
      header = {[(width .&. 255 : U32), ((width >> 8n) .&. 255 : U32), 0, 0, (height .&. 255 : U32), ((height >> 8n) .&. 255 : U32), 0, 0] : +List<U32>}
      emit_bytes(~&2, List.append(&2, U32, header, bytes))
def image(image: J.Image.FloatRGB) -> IO(Unit):
  J.FloatRGB{+width, +height, pixels} = image
  emitted(width, height, J.Image.FloatRGB.to_bytes(J.FloatRGB{width, height, pixels}))
def observed(expected: U32, result: Maybe<Result<&1, &1, J.Image.FloatRGB & J.Surface.Error, J.Image.FloatRGB>>) -> IO(Unit):
  match expected result:
    case 99 Some{Done{value}}: image(value)
    case 0 Some{Fail{Tuple{value, J.InvalidSize{}}}}: image(value)
    case 1 Some{Fail{Tuple{value, J.InvalidRectangle{}}}}: image(value)
    case _ _: IO.die(Unit, 1, "canvas acceptance/error/owner differs")
def apply(pot: Bool, width: U32, height: U32, x: F32, y: F32, fill: U32, result: Maybe<J.Image.FloatRGB>) -> Maybe<Result<&1, &1, J.Image.FloatRGB & J.Surface.Error, J.Image.FloatRGB>>:
  match pot result:
    case _ None{}: None{}
    case True{} Some{image}: Some{J.Image.FloatRGB.to_pot(image, fill)}
    case False{} Some{image}: Some{J.Image.FloatRGB.resize_canvas(image, width, height, x, y, fill)}
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program
        for case in [*cases,*controls]:
            x,y=[f'F32.neg({abs(v):.1f})' if v<0 else f'{v:.1f}' for v in (case['x'],case['y'])]
            body+=f'    observed({case.get("error",99)}, apply{bang}({"True" if case["kind"]=="pot" else "False"}{{}}, {case["target_width"]}, {case["target_height"]}, {x}, {y}, {case["fill"]}, J.Image.FloatRGB.from_bytes({case["width"]}, {case["height"]}, {bend_bytes(case["bytes"])})))\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));different=[i for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==expected,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: float canvas differences {different}')
        print(f'{lane}: {len(cases)} native canvas/POT cases / {report["pixels"]} pixels and {len(controls)} retained owners passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
