#!/usr/bin/env python3
"""Compare native format-9 nearest/default resizing and RGBA8 quantization."""
import hashlib
import json
import struct

from bmp_probe import bend_bytes
from byte_probe import C_EMITTER, BEND_EMITTER, parse_results
from conformance import ROOT, source_gate
from float_rgb_probe import boundaries
import probekit
from probekit import ProbeFailure

PRELUDE = ['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           C_EMITTER,
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
    case _: IO.die(Unit, 1, "resize changed the pixel format")
def image(image: J.Surface) -> IO(Unit):
  emitted(J.Surface.export(image))
# expected: 99 accepted, 1 InvalidSize, 2 UnsafeNearestMapping, 3 OutOfDomain (owner returned).
def selected(expected: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> IO(Unit):
  match expected result:
    case 99 Done{value}: image(value)
    case 1 Fail{Tuple{value, J.InvalidSize{}}}: image(value)
    case 2 Fail{Tuple{value, J.UnsafeNearestMapping{}}}: image(value)
    case 3 Fail{Tuple{value, J.OutOfDomain{}}}: image(value)
    case _ _: IO.die(Unit, 1, "resize acceptance, error or retained owner differs")
def resized(width: U32, height: U32, result: Maybe<J.Surface>) -> Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Surface.resize_nn(image, width, height)}
def observed(expected: U32, result: Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid resize source rejected")
    case Some{value}: selected(expected, value)
def main() -> IO(Unit):
  do IO<Unit>:
'''


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
    controls=[dict(width=1,height=1,bytes=original,target_width=w,target_height=h,error=e) for w,h,e in ((0,1,1),(1,4097,1),(512,1,2),(1,512,2))]
    controls.append(dict(width=1,height=1,bytes=list(struct.pack('<fff',2.0,0.5,0.75)),target_width=2,target_height=2,error=3))
    if filtered:
        cases.extend({k:v for k,v in c.items() if k!='error'} for c in controls[2:4]);controls=controls[:2]+controls[4:]
    return cases,controls


def reference_program(cases,controls,work,filtered):
    lines=list(PRELUDE)
    for i,case in enumerate([*cases,*controls]):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},PIXELFORMAT_UNCOMPRESSED_R32G32B32,0);')
        if i<len(cases):lines.append(f'{"ImageResize" if filtered else "ImageResizeNN"}(&image,{case["target_width"]},{case["target_height"]});')
        lines.append('emit(image);}')
    return '\n'.join(lines+['}'])+'\n'


def main():
    args=probekit.arguments(__doc__,lambda parser:parser.add_argument('--filtered',action='store_true'))
    mode='filtered' if args.filtered else 'nearest';probe=probekit.Probe('float-rgb-filtered' if args.filtered else 'float-rgb-resize',args)
    cases,controls=fixtures(args.filtered);text=probe.native(reference_program(cases,controls,probe.work,args.filtered));expected=parse_results(text)
    if len(expected)!=len(cases)+len(controls):raise ProbeFailure('Incomplete native resize output')
    for case,row in zip(cases,expected):
        w,h=case['target_width'],case['target_height']
        if row[:8]!=list(struct.pack('<II',w,h)) or len(row)!=8+w*h*12:raise ProbeFailure('Native resize shape differs')
    probe.report['sources']=source_gate()
    program=PROGRAM.replace('J.Surface.resize_nn(','J.Surface.resize(') if args.filtered else PROGRAM
    actions=[f'observed({case.get("error",99)}, resizedBANG({case["target_width"]}, {case["target_height"]}, J.Surface.from_bytes({case["width"]}, {case["height"]}, 9, {bend_bytes(case["bytes"])})))'
             for case in [*cases,*controls]]
    render=lambda selected,gpu:program+''.join('    '+line.replace('BANG','!' if gpu else '')+'\n' for line in selected)
    probe.compare(expected,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)))
    probe.finish(mode=mode,native_cases=len(cases),pixels=sum(c['target_width']*c['target_height'] for c in cases),retained_owner_controls=len(controls),
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
