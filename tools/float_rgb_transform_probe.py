#!/usr/bin/env python3
"""Compare lossless RGB-float copying and orientation with native Image operations."""
import hashlib
import json
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import ROOT, source_gate
from float_rgb_bytes_probe import fixtures as raw_fixtures
import probekit
from probekit import ProbeFailure

PRELUDE = ['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
           'static void emit(Image image){word(image.width);word(image.height);for(int i=0;i<image.width*image.height*12;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
NATIVE = {'h':'ImageFlipHorizontal','v':'ImageFlipVertical','cw':'ImageRotateCW','ccw':'ImageRotateCCW'}
CODES = {'copy':0,'h':1,'v':2,'cw':3,'ccw':4}
PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
'''+BEND_EMITTER+'''
def clone(result: J.Surface & J.Surface) -> J.Surface:
  (_, copy) = result
  copy
def operation(kind: U32, image: J.Surface) -> J.Surface:
  match kind:
    case 0: clone(J.Surface.copy(image))
    case 1: J.Surface.flip_horizontal(image)
    case 2: J.Surface.flip_vertical(image)
    case 3: J.Surface.rotate_cw(image)
    case _: J.Surface.rotate_ccw(image)
def apply(ops: +List<U32>, result: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match ops result:
    case _ None{}: None{}
    case Nil{} _: result
    case Con{op, rest} Some{image}: apply(rest, Some{operation(op, image)})
def emitted.sized(+width: U32, +height: U32, bytes: List<U32>) -> IO(Unit):
  header = {[(width .&. 255 : U32), ((width >> 8n) .&. 255 : U32), 0, 0, (height .&. 255 : U32), ((height >> 8n) .&. 255 : U32), 0, 0] : List<U32>}
  emit_bytes(~&1, List.append(&1, U32, header, bytes))
def emitted(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match data:
    case Tuple{Tuple{width, height}, Tuple{9, bytes}}: emitted.sized(width, height, bytes)
    case _: IO.die(Unit, 1, "float orientation changed the pixel format")
def observed(result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "float input rejected")
    case Some{image}: emitted(J.Surface.export(image))
def source_read(result: Array<M.Vector3> & M.Vector3) -> Bool:
  match result:
    case Tuple{_, M.Vector3{x, y, z}}: F32.is_eq(x, 0.25) && F32.is_eq(y, 0.5) && F32.is_eq(z, 0.75)
def clone_changed(source: Array<M.Vector3>, result: Array<M.Vector3> & M.Vector3) -> Bool:
  match result:
    case Tuple{_, M.Vector3{x, y, z}}:
      F32.is_eq(x, 0.0) && F32.is_eq(y, 0.0) && F32.is_eq(z, 0.0) && source_read(Array.get(M.Vector3, source, 0))
def independent(result: J.Surface & J.Surface) -> Bool:
  match result:
    case Tuple{J.Surface{1, 1, 9, J.Vectors{source}}, J.Surface{1, 1, 9, J.Vectors{copy}}}:
      clone_changed(source, Array.get(M.Vector3, Array.set(M.Vector3, copy, 0, M.Vector3{0.0, 0.0, 0.0}), 0))
    case _: False{}
def owned_copy() -> Bool:
  independent(J.Surface.copy(J.Surface{1, 1, 9, J.Vectors{Array.new(M.Vector3, 0n, M.Vector3{0.25, 0.5, 0.75})}}))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def fixtures():
    raw,_=raw_fixtures();shapes=list(raw)
    shapes += [dict(raw[0],id='column',width=1,height=5),dict(id='single',width=1,height=1,bytes=raw[0]['bytes'][:12]),
               dict(id='rectangle',width=3,height=2,bytes=raw[0]['bytes']+list(struct.pack('<fff',0.25,0.5,0.75)))]
    operations=[['copy'],['h'],['v'],['cw'],['ccw'],['cw']*4,['h','v','cw','ccw']]
    cases=[dict(shape,id=shape['id']+'-'+str(i),operations=ops) for shape in shapes for i,ops in enumerate(operations)]
    values=[word for i in range(4096) for word in (0x3f000000+i,0xbf000000+i,i+1)]
    cases.append(dict(id='wide-chain',width=4096,height=1,bytes=list(struct.pack('<'+'I'*len(values),*values)),operations=['cw','v','h','ccw']))
    return cases


def reference_program(cases,work):
    lines=list(PRELUDE)
    for i,case in enumerate(cases):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},PIXELFORMAT_UNCOMPRESSED_R32G32B32,0);if(!image.data)return 2;')
        for op in case['operations']:
            lines.append('{Image copy=ImageCopy(image);UnloadImage(image);image=copy;}' if op=='copy' else NATIVE[op]+'(&image);')
        lines.append('emit(image);}')
    return '\n'.join(lines+['}'])+'\n'


def main():
    probe=probekit.Probe('float-rgb-transform',probekit.arguments(__doc__))
    cases=fixtures();text=probe.native(reference_program(cases,probe.work));expected=parse_results(text)
    if len(expected)!=len(cases):raise ProbeFailure('Incomplete native float orientation output')
    for case,row in zip(cases,expected):
        w,h=case['width'],case['height']
        for op in case['operations']:
            if op in ('cw','ccw'):w,h=h,w
        if row[:8]!=list(struct.pack('<II',w,h)) or len(row)!=8+w*h*12:raise ProbeFailure('Native orientation metadata differs')
    probe.report['sources']=source_gate()
    actions=[f'observed(applyBANG([{",".join(str(CODES[op]) for op in case["operations"])}], J.Surface.from_bytes({case["width"]}, {case["height"]}, 9, {bend_bytes(case["bytes"])})))' for case in cases]
    actions.append('emit_bytes(~&1, [Bool.to_u32(owned_copyBANG())])')
    render=lambda selected,gpu:PROGRAM+''.join('    '+line.replace('BANG','!' if gpu else '')+'\n' for line in selected)
    probe.compare(expected+[[1]],probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)))
    probe.finish(cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),ownership_controls=1,
                 inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
