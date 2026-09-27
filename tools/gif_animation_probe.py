#!/usr/bin/env python3
"""Compare owned GIF animation frames with native LoadImageAnimFromMemory."""
import argparse
import hashlib
import json
from pathlib import Path

from bmp_probe import bend_bytes
from conformance import BUILD, ROOT, checkout, run, source_gate
from gif_probe import animation


def fixtures():
    colors=[0x010203ff,0x112233ff,0xaabbccff,0xfedcbaff]
    cases=[]
    def add(name,width,height,frames,background=0):
        cases.append(dict(id=name,width=width,height=height,frames=len(frames),bytes=animation(width,height,colors,frames,background=background)))
    add('single',3,2,[dict(indices=[0,1,2,3,2,1])])
    for disposal in (0,1,2):
        add(f'full-disposal-{disposal}',3,2,[dict(indices=[1]*6,disposal=disposal),
            dict(indices=[0,2,0,3,0,2],transparent=0,disposal=1),dict(indices=[0,3,0,2,0,3])])
    add('offset-restore',4,3,[dict(indices=[1]*12,disposal=0),
        dict(indices=[0,2,0,2],frame=(1,1,2,2),transparent=0,disposal=2),
        dict(indices=[3],frame=(3,2,1,1),disposal=0)])
    add('palette-background-persistence',4,2,[dict(indices=[1],frame=(1,0,1,1),transparent=1,disposal=0),
        dict(indices=[1]*8),dict(indices=[1]*8,local=list(reversed(colors)))],background=1)
    add('local-global-controls',3,2,[dict(indices=[0,1,2,3,2,1],transparent=1,disposal=1),
        dict(indices=[1,2,3,0,1,2],local=list(reversed(colors))),dict(indices=[1]*6,disposal=0)])
    add('offset-interlaced',8,10,[dict(indices=[i%4 for i in range(80)],disposal=1),
        dict(indices=[(i*3+i//5)%4 for i in range(45)],frame=(1,1,5,9),interlaced=True,transparent=1,disposal=2),
        dict(indices=[3],frame=(7,9,1,1),disposal=0)])
    add('delay-ignored',2,1,[dict(indices=[0,1],disposal=1,delay=65535),dict(indices=[1,0],disposal=0,delay=0)])
    base=cases[1]['bytes'];width=cases[1]['width'];height=cases[1]['height'];count=cases[1]['frames']
    controls=[dict(id='zero-frames',bytes=base,maximum_frames=0,maximum_pixels=100,error=2),
              dict(id='zero-pixels',bytes=base,maximum_frames=10,maximum_pixels=0,error=2),
              dict(id='oversize-pixel-budget',bytes=base,maximum_frames=10,maximum_pixels=16777217,error=2),
              dict(id='frame-budget',bytes=base,maximum_frames=count-1,maximum_pixels=width*height*count,error=2),
              dict(id='pixel-budget',bytes=base,maximum_frames=count,maximum_pixels=width*height*count-1,error=2),
              dict(id='unsupported-disposal',bytes=animation(1,1,colors,[dict(indices=[0],disposal=3)]),maximum_frames=2,maximum_pixels=2,error=0),
              dict(id='missing-terminator',bytes=base[:-1],maximum_frames=10,maximum_pixels=100,error=0),
              dict(id='no-frame',bytes=animation(1,1,colors,[]),maximum_frames=2,maximum_pixels=2,error=0),
              dict(id='bad-later-frame',bytes=animation(2,1,colors,[dict(indices=[0,1]),dict(indices=[2],frame=(2,0,1,1))]),maximum_frames=2,maximum_pixels=4,error=0),
              dict(id='bad-byte',bytes=[*base,256],maximum_frames=10,maximum_pixels=100,error=1)]
    return cases,controls


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args=parser.parse_args();lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'gif-animation-probe';work.mkdir(parents=True,exist_ok=True)
    report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases,controls=fixtures()
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static void emit(const unsigned char *data,int size){int frames=0;Image image=LoadImageAnimFromMemory(".gif",data,size,&frames);if(!image.data)exit(2);',
           'printf("{\\"width\\":%d,\\"height\\":%d,\\"count\\":%d}\\n",image.width,image.height,frames);',
           'for(int f=0;f<frames;f++){putchar(\'[\');for(int i=0;i<image.width*image.height;i++)printf("%s%u",i?",":"",(unsigned)ColorToInt(((Color*)image.data)[f*image.width*image.height+i]));puts("]");}UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:lines+=['{unsigned char data[]={'+','.join(map(str,case['bytes']))+'};emit(data,sizeof(data));}']
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    text=run([binary]);expected=[json.loads(line) for line in text.splitlines()]
    at=0
    for case in cases:
        if expected[at]!={key:case[key] for key in ('width','height')}|{'count':case['frames']}:raise ValueError('Native animation geometry/count differs')
        at+=1+case['frames']
    if at!=len(expected):raise ValueError('Incomplete native animation output')
    report=dict(passed=False,animations=len(cases),frames=sum(c['frames'] for c in cases),
                pixels=sum(c['frames']*c['width']*c['height'] for c in cases),error_controls=len(controls),sources=source_gate(),
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
def emit_frames(frames: List<J.Surface>) -> IO(Unit):
  match frames:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{surface, rest}:
      do IO<Unit>:
        IO.print(List.show(~&1, ~U32, ~U32.show, J.Surface.colors(surface)))
        emit_frames(rest)
def emit_animation(result: U32 & U32 & U32 & List<J.Surface>) -> IO(Unit):
  (width, height, count, frames) = result
  do IO<Unit>:
    IO.print("{\\"width\\":" ++ U32.show(width) ++ ",\\"height\\":" ++ U32.show(height) ++ ",\\"count\\":" ++ U32.show(count) ++ "}")
    emit_frames(frames)
def observed(result: Result<&1, &1, J.Image.DecodeError, J.Image.Animation>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid animation rejected")
    case Done{animation}: emit_animation(J.Image.Animation.entries(animation))
def error_code(result: Result<&1, &1, J.Image.DecodeError, J.Image.Animation>) -> U32:
  match result:
    case Done{_}: 99
    case Fail{error}:
      match error:
        case J.InvalidImageHeader{}: 0
        case J.InvalidImageByte{}: 1
        case J.UnsupportedImageSize{}: 2
        case J.TruncatedImageData{}: 3
        case J.InvalidImageStream{}: 4
def second_kept(result: J.Surface & Maybe<&2, U32>) -> Bool:
  match result:
    case Tuple{_, Some{color}}: U32.is_eq(color, J.Color.rgba(17, 34, 51, 255))
    case _: False{}
def first_changed(second: J.Surface, result: J.Surface & Maybe<&2, U32>) -> Bool:
  match result:
    case Tuple{_, Some{0}}: second_kept(J.Surface.get(second, 0, 0))
    case _: False{}
def independent(frames: List<J.Surface>) -> Bool:
  match frames:
    case Con{first, Con{second, _}}: first_changed(second, J.Surface.get(J.Surface.draw_pixel(first, 0.0, 0.0, 0), 0, 0))
    case _: False{}
def owned_entries(result: U32 & U32 & U32 & List<J.Surface>) -> Bool:
  (width, height, count, frames) = result
  U32.is_eq(width, 3) && U32.is_eq(height, 2) && U32.is_eq(count, 3) && independent(frames)
def owned(result: Result<&1, &1, J.Image.DecodeError, J.Image.Animation>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{animation}: owned_entries(J.Image.Animation.entries(animation))
def unit_seen(value: Unit) -> Bool:
  True{}
def disposed(result: Result<&1, &1, J.Image.DecodeError, J.Image.Animation>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{animation}: unit_seen(J.Image.Animation.unload(animation))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program
        for case in cases:body+=f'    observed(J.Image.Animation.decode_gif{bang}({bend_bytes(case["bytes"])}, {case["frames"]}, {case["frames"]*case["width"]*case["height"]}))\n'
        for case in controls:body+=f'    IO.print(U32.show(error_code(J.Image.Animation.decode_gif{bang}({bend_bytes(case["bytes"])}, {case["maximum_frames"]}, {case["maximum_pixels"]}))))\n'
        for function in ('owned','disposed'):body+=f'    IO.print(U32.show(Bool.to_u32({function}{bang}(J.Image.Animation.decode_gif({bend_bytes(cases[1]["bytes"])}, 3, 18)))))\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=[json.loads(line) for line in run(command).splitlines()];wanted=expected+[c['error'] for c in controls]+[1,1]
        differences=[dict(index=i,reference=a,candidate=b) for i,(a,b) in enumerate(zip(wanted,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==wanted,differences=differences[:2]);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=wanted:raise ValueError(f'{lane}: animation differs: {differences[:1]}')
        print(f'{lane}: {len(cases)} animations / {report["frames"]} frames and {len(controls)} controls passed',flush=True)
    report['ownership_controls']=2;report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
