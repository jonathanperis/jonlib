#!/usr/bin/env python3
"""Compare native format-9 nearest/default resizing and RGBA8 quantization."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, run, source_gate
from float_rgb_probe import boundaries


def fixtures(filtered=False):
    sources=[]
    for width,height in ((1,1),(1,7),(7,1),(2,3),(5,4)):
        values=[component for i in range(width*height) for component in ((i+0.5)/(width*height),0.25,0.75)]
        sources.append(dict(width=width,height=height,bytes=list(struct.pack('<'+'f'*len(values),*values))))
    words=boundaries();sources.append(dict(width=len(words)//3,height=1,bytes=list(struct.pack('<'+'I'*len(words),*words))))
    cases=[]
    for i,source in enumerate(sources):
        for width,height in ((source['width'],source['height']),(1,1),(4,5),(17,9)):
            xr=((source['width']<<16)//width)+1;yr=((source['height']<<16)//height)+1
            if ((width-1)*xr)>>16>=source['width'] or ((height-1)*yr)>>16>=source['height']:raise ValueError('Native resize fixture leaves source bounds')
            cases.append(dict(source,id=f'{i}-{width}-{height}',target_width=width,target_height=height))
    original=list(struct.pack('<fff',0.5,0.25,0.75))
    controls=[dict(width=1,height=1,bytes=original,target_width=w,target_height=h) for w,h in ((0,1),(1,4097),(512,1),(1,512))]
    controls.append(dict(width=1,height=1,bytes=list(struct.pack('<fff',2.0,0.5,0.75)),target_width=2,target_height=2))
    if filtered:
        cases.extend(controls[2:4]);controls=controls[:2]+controls[4:]
    return cases,controls


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');parser.add_argument('--filtered',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    mode='filtered' if args.filtered else 'nearest';work=BUILD/('float-rgb-filtered-probe' if args.filtered else 'float-rgb-resize-probe')
    work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases,controls=fixtures(args.filtered);lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
        'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
        'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
        'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
        'static void emit(Image image){if(!image.data||image.format!=PIXELFORMAT_UNCOMPRESSED_R32G32B32)exit(2);word(image.width);word(image.height);',
        'for(int i=0;i<image.width*image.height*12;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
        'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate([*cases,*controls]):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},PIXELFORMAT_UNCOMPRESSED_R32G32B32,0);')
        if i<len(cases):lines.append(f'{"ImageResize" if args.filtered else "ImageResizeNN"}(&image,{case["target_width"]},{case["target_height"]});')
        lines.append('emit(image);}')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(cases)+len(controls):raise ValueError('Incomplete native resize output')
    for case,row in zip(cases,expected):
        w,h=case['target_width'],case['target_height']
        if row[:8]!=list(struct.pack('<II',w,h)) or len(row)!=8+w*h*12:raise ValueError('Native resize shape differs')
    report=dict(passed=False,mode=mode,native_cases=len(cases),pixels=sum(c['target_width']*c['target_height'] for c in cases),retained_owner_controls=len(controls),sources=source_gate(),
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
    case Fail{_}: IO.die(Unit, 1, "resize lost valid sample representation")
    case Done{bytes}:
      header = {[(width .&. 255 : U32), ((width >> 8n) .&. 255 : U32), 0, 0, (height .&. 255 : U32), ((height >> 8n) .&. 255 : U32), 0, 0] : +List<U32>}
      emit_bytes(~&2, List.append(&2, U32, header, bytes))
def image(image: J.Image.FloatRGB) -> IO(Unit):
  J.FloatRGB{+width, +height, pixels} = image
  emitted(width, height, J.Image.FloatRGB.to_bytes(J.FloatRGB{width, height, pixels}))
def selected(reject: Bool, result: Result<&1, &1, J.Image.FloatRGB, J.Image.FloatRGB>) -> IO(Unit):
  match reject result:
    case False{} Done{value}: image(value)
    case True{} Fail{value}: image(value)
    case _ _: IO.die(Unit, 1, "resize acceptance or retained owner differs")
def resized(width: U32, height: U32, result: Maybe<J.Image.FloatRGB>) -> Maybe<Result<&1, &1, J.Image.FloatRGB, J.Image.FloatRGB>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.FloatRGB.resize_nn(image, width, height)}
def observed(reject: Bool, result: Maybe<Result<&1, &1, J.Image.FloatRGB, J.Image.FloatRGB>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid resize source rejected")
    case Some{value}: selected(reject, value)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    if args.filtered:program=program.replace('J.Image.FloatRGB.resize_nn(', 'J.Image.FloatRGB.resize(')
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program
        for i,case in enumerate([*cases,*controls]):
            body+=f'    observed({"True" if i>=len(cases) else "False"}{{}}, resized{bang}({case["target_width"]}, {case["target_height"]}, J.Image.FloatRGB.from_bytes({case["width"]}, {case["height"]}, {bend_bytes(case["bytes"])})))\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));different=[i for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==expected,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: float {mode} differences {different}')
        print(f'{lane}: {len(cases)} native {mode} cases / {report["pixels"]} pixels and {len(controls)} retained owners passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
