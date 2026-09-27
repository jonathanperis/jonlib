#!/usr/bin/env python3
"""Compare lossless RGB-float copying and orientation with native Image operations."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, run, source_gate
from float_rgb_bytes_probe import fixtures as raw_fixtures


def fixtures():
    raw,_=raw_fixtures();shapes=list(raw)
    shapes += [dict(raw[0],id='column',width=1,height=5),dict(id='single',width=1,height=1,bytes=raw[0]['bytes'][:12]),
               dict(id='rectangle',width=3,height=2,bytes=raw[0]['bytes']+list(struct.pack('<fff',0.25,0.5,0.75)))]
    operations=[['copy'],['h'],['v'],['cw'],['ccw'],['cw']*4,['h','v','cw','ccw']]
    cases=[dict(shape,id=shape['id']+'-'+str(i),operations=ops) for shape in shapes for i,ops in enumerate(operations)]
    values=[word for i in range(4096) for word in (0x3f000000+i,0xbf000000+i,i+1)]
    cases.append(dict(id='wide-chain',width=4096,height=1,bytes=list(struct.pack('<'+'I'*len(values),*values)),operations=['cw','v','h','ccw']))
    return cases


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'float-rgb-transform-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases=fixtures();lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
        'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
        'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
        'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
        'static void emit(Image image){word(image.width);word(image.height);for(int i=0;i<image.width*image.height*12;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
        'int main(void){SetTraceLogLevel(LOG_NONE);']
    native={'h':'ImageFlipHorizontal','v':'ImageFlipVertical','cw':'ImageRotateCW','ccw':'ImageRotateCCW'}
    for i,case in enumerate(cases):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},PIXELFORMAT_UNCOMPRESSED_R32G32B32,0);if(!image.data)return 2;')
        for op in case['operations']:
            lines.append('{Image copy=ImageCopy(image);UnloadImage(image);image=copy;}' if op=='copy' else native[op]+'(&image);')
        lines.append('emit(image);}')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(cases):raise ValueError('Incomplete native float orientation output')
    for case,row in zip(cases,expected):
        w,h=case['width'],case['height']
        for op in case['operations']:
            if op in ('cw','ccw'):w,h=h,w
        if row[:8]!=list(struct.pack('<II',w,h)) or len(row)!=8+w*h*12:raise ValueError('Native orientation metadata differs')
    report=dict(passed=False,cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),ownership_controls=1,sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
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
def clone(result: J.Image.FloatRGB & J.Image.FloatRGB) -> J.Image.FloatRGB:
  (_, copy) = result
  copy
def operation(kind: U32, image: J.Image.FloatRGB) -> J.Image.FloatRGB:
  match kind:
    case 0: clone(J.Image.FloatRGB.copy(image))
    case 1: J.Image.FloatRGB.flip_horizontal(image)
    case 2: J.Image.FloatRGB.flip_vertical(image)
    case 3: J.Image.FloatRGB.rotate_cw(image)
    case _: J.Image.FloatRGB.rotate_ccw(image)
def apply(ops: +List<U32>, result: Maybe<J.Image.FloatRGB>) -> Maybe<J.Image.FloatRGB>:
  match ops result:
    case _ None{}: None{}
    case Nil{} _: result
    case Con{op, rest} Some{image}: apply(rest, Some{operation(op, image)})
def emitted(+width: U32, +height: U32, result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "float orientation corrupted samples")
    case Done{bytes}:
      header = {[(width .&. 255 : U32), ((width >> 8n) .&. 255 : U32), 0, 0, (height .&. 255 : U32), ((height >> 8n) .&. 255 : U32), 0, 0] : +List<U32>}
      emit_bytes(~&2, List.append(&2, U32, header, bytes))
def observed(result: Maybe<J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "float input rejected")
    case Some{J.FloatRGB{+width, +height, pixels}}: emitted(width, height, J.Image.FloatRGB.to_bytes(J.FloatRGB{width, height, pixels}))
def source_read(result: Array<M.Vector3> & M.Vector3) -> Bool:
  match result:
    case Tuple{_, M.Vector3{x, y, z}}: F32.is_eq(x, 0.25) && F32.is_eq(y, 0.5) && F32.is_eq(z, 0.75)
def clone_changed(source: Array<M.Vector3>, result: Array<M.Vector3> & M.Vector3) -> Bool:
  match result:
    case Tuple{_, M.Vector3{x, y, z}}:
      F32.is_eq(x, 0.0) && F32.is_eq(y, 0.0) && F32.is_eq(z, 0.0) && source_read(Array.get(M.Vector3, source, 0))
def independent(result: J.Image.FloatRGB & J.Image.FloatRGB) -> Bool:
  match result:
    case Tuple{J.FloatRGB{1, 1, source}, J.FloatRGB{1, 1, copy}}:
      clone_changed(source, Array.get(M.Vector3, Array.set(M.Vector3, copy, 0, M.Vector3{0.0, 0.0, 0.0}), 0))
    case _: False{}
def owned_copy() -> Bool:
  independent(J.Image.FloatRGB.copy(J.FloatRGB{1, 1, Array.new(M.Vector3, 0n, M.Vector3{0.25, 0.5, 0.75})}))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    codes={'copy':0,'h':1,'v':2,'cw':3,'ccw':4}
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program
        for case in cases:
            ops='['+','.join(str(codes[op]) for op in case['operations'])+']'
            body+=f'    observed(apply{bang}({ops}, J.Image.FloatRGB.from_bytes({case["width"]}, {case["height"]}, {bend_bytes(case["bytes"])})))\n'
        body+=f'    emit_bytes(~&1, [Bool.to_u32(owned_copy{bang}())])\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));wanted=expected+[[1]];different=[i for i,(a,b) in enumerate(zip(wanted,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==wanted,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=wanted:raise ValueError(f'{lane}: float orientation differences {different}')
        print(f'{lane}: {len(cases)} native orientation cases / {report["pixels"]} pixels and independent copy passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
