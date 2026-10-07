#!/usr/bin/env python3
"""Compare native RGB float canvas/POT movement and ignored fill colors."""
import hashlib
import json
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import ROOT, source_gate
import probekit
from probekit import ProbeFailure

PRELUDE = ['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
           'static void emit(Image image){if(!image.data||image.format!=PIXELFORMAT_UNCOMPRESSED_R32G32B32)exit(2);word(image.width);word(image.height);',
           'for(int i=0;i<image.width*image.height*12;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
PROGRAM = '''import Base
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
def emitted.sized(+width: U32, +height: U32, bytes: List<U32>) -> IO(Unit):
  header = {[(width .&. 255 : U32), ((width >> 8n) .&. 255 : U32), 0, 0, (height .&. 255 : U32), ((height >> 8n) .&. 255 : U32), 0, 0] : List<U32>}
  emit_bytes(~&1, List.append(&1, U32, header, bytes))
def emitted(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match data:
    case Tuple{Tuple{width, height}, Tuple{9, bytes}}: emitted.sized(width, height, bytes)
    case _: IO.die(Unit, 1, "canvas sample representation changed")
def image(image: J.Surface) -> IO(Unit):
  emitted(J.Surface.export(image))
def observed(expected: U32, result: Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>) -> IO(Unit):
  match expected result:
    case 99 Some{Done{value}}: image(value)
    case 0 Some{Fail{Tuple{value, J.InvalidSize{}}}}: image(value)
    case 1 Some{Fail{Tuple{value, J.InvalidRectangle{}}}}: image(value)
    case _ _: IO.die(Unit, 1, "canvas acceptance/error/owner differs")
def apply(pot: Bool, width: U32, height: U32, x: F32, y: F32, fill: U32, result: Maybe<J.Surface>) -> Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>:
  match pot result:
    case _ None{}: None{}
    case True{} Some{image}: Some{J.Surface.to_pot(image, fill)}
    case False{} Some{image}: Some{J.Surface.resize_canvas(image, width, height, x, y, fill)}
def main() -> IO(Unit):
  do IO<Unit>:
'''


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


def reference_program(cases,controls,work):
    lines=list(PRELUDE)
    for i,case in enumerate([*cases,*controls]):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},PIXELFORMAT_UNCOMPRESSED_R32G32B32,0);')
        if i<len(cases):
            if case['kind']=='pot':lines.append(f'ImageToPOT(&image,GetColor({case["fill"]}u));')
            else:lines.append(f'ImageResizeCanvas(&image,{case["target_width"]},{case["target_height"]},{case["x"]},{case["y"]},GetColor({case["fill"]}u));')
        lines.append('emit(image);}')
    return '\n'.join(lines+['}'])+'\n'


def action(case):
    x,y=[f'F32.neg({abs(v):.1f})' if v<0 else f'{v:.1f}' for v in (case['x'],case['y'])]
    return (f'observed({case.get("error",99)}, applyBANG({"True" if case["kind"]=="pot" else "False"}{{}}, {case["target_width"]}, {case["target_height"]}, {x}, {y}, {case["fill"]}, '
            f'J.Surface.from_bytes({case["width"]}, {case["height"]}, 9, {bend_bytes(case["bytes"])})))')


def main():
    probe=probekit.Probe('float-rgb-canvas',probekit.arguments(__doc__))
    cases,controls=fixtures();text=probe.native(reference_program(cases,controls,probe.work));expected=parse_results(text)
    if len(expected)!=len(cases)+len(controls):raise ProbeFailure('Incomplete native float canvas output')
    for case,row in zip(cases,expected):
        w,h=case['target_width'],case['target_height']
        if row[:8]!=list(struct.pack('<II',w,h)) or len(row)!=8+w*h*12:raise ProbeFailure('Native canvas dimensions differ')
    probe.report['sources']=source_gate();actions=[action(case) for case in [*cases,*controls]]
    render=lambda selected,gpu:PROGRAM+''.join('    '+line.replace('BANG','!' if gpu else '')+'\n' for line in selected)
    probe.compare(expected,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)))
    probe.finish(native_cases=len(cases),pixels=sum(c['target_width']*c['target_height'] for c in cases),retained_owner_controls=len(controls),
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
