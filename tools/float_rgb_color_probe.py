#!/usr/bin/env python3
"""Compare native format-9 color transforms and owner-preserving rejection."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, f32, run, source_gate
from float_rgb_probe import boundaries


def fixtures():
    values=[0.5,0.25,0.75,0,0,0,1,1,1,0.49999997,0.249999985,0.74999994,0,-0.0,1,17/255,34/255,51/255]
    small=dict(width=3,height=2,bytes=list(struct.pack('<18f',*values)))
    words=boundaries();wide=dict(width=len(words)//3,height=1,bytes=list(struct.pack('<'+'I'*len(words),*words)))
    operations=[[dict(op='tint',color=color)] for color in (0x7fabcc00,0xffffffff)]
    operations += [[dict(op='invert')]]
    operations += [[dict(op='contrast',amount=amount)] for amount in (-300,-100,-50,0,12.5,50,100,300)]
    operations += [[dict(op='brightness',amount=amount)] for amount in (-300,-255,-1,0,1,64,255,300)]
    operations += [[dict(op='replace',original=original,replacement=0x11223300)] for original in (0x7f3fbfff,0x7f3fbf00)]
    operations.append([dict(op='contrast',amount=23.5),dict(op='brightness',amount=-20),dict(op='invert'),dict(op='tint',color=0xabcdef80)])
    cases=[dict(source,operations=ops) for source in (small,wide) for ops in operations]
    controls=[dict(small,operations=[op]) for op in (dict(op='contrast',bits=0x7f800000),dict(op='contrast',bits=0x7fc00000),
                dict(op='brightness',amount=0.5),dict(op='brightness',bits=0x80000001),dict(op='brightness',bits=0x7f800000))]
    controls.append(dict(width=1,height=1,bytes=list(struct.pack('<fff',2,0.5,0.75)),operations=[dict(op='invert')]))
    return cases,controls


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'float-rgb-color-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
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
            for op in case['operations']:
                if op['op']=='tint':lines.append(f'ImageColorTint(&image,GetColor({op["color"]}u));')
                elif op['op']=='invert':lines.append('ImageColorInvert(&image);')
                elif op['op']=='contrast':lines.append(f'ImageColorContrast(&image,{float(op["amount"])}f);')
                elif op['op']=='brightness':lines.append(f'ImageColorBrightness(&image,{op["amount"]});')
                else:lines.append(f'ImageColorReplace(&image,GetColor({op["original"]}u),GetColor({op["replacement"]}u));')
        lines.append('emit(image);}')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(cases)+len(controls):raise ValueError('Incomplete native float color output')
    for case,row in zip([*cases,*controls],expected):
        if row[:8]!=list(struct.pack('<II',case['width'],case['height'])) or len(row)!=8+case['width']*case['height']*12:raise ValueError('Native float color shape differs')
    report=dict(passed=False,native_cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),retained_owner_controls=len(controls),sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
import ../../jonlib.bend as J
import ../../src/hdr.bend as H
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
'''+BEND_EMITTER+'''
type Op is Data:
  Tint{color: U32}
  Invert{}
  Contrast{amount: F32}
  Brightness{amount: F32}
  Replace{original: U32, replacement: U32}
def operation(op: Op, image: J.Image.FloatRGB) -> Result<&1, &1, J.Image.FloatRGB, J.Image.FloatRGB>:
  match op:
    case Tint{color}: J.Image.FloatRGB.color_tint(image, color)
    case Invert{}: J.Image.FloatRGB.color_invert(image)
    case Contrast{amount}: J.Image.FloatRGB.color_contrast(image, amount)
    case Brightness{amount}: J.Image.FloatRGB.color_brightness(image, amount)
    case Replace{original, replacement}: J.Image.FloatRGB.color_replace(image, original, replacement)
def operations(ops: +List<Op>, result: Result<&1, &1, J.Image.FloatRGB, J.Image.FloatRGB>) -> Result<&1, &1, J.Image.FloatRGB, J.Image.FloatRGB>:
  match ops result:
    case _ Fail{image}: Fail{image}
    case Nil{} _: result
    case Con{op, rest} Done{image}: operations(rest, operation(op, image))
def apply(ops: +List<Op>, result: Maybe<J.Image.FloatRGB>) -> Maybe<Result<&1, &1, J.Image.FloatRGB, J.Image.FloatRGB>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{operations(ops, Done{image})}
def emitted(+width: U32, +height: U32, result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "color transform changed sample domain")
    case Done{bytes}:
      header = {[(width .&. 255 : U32), ((width >> 8n) .&. 255 : U32), 0, 0, (height .&. 255 : U32), ((height >> 8n) .&. 255 : U32), 0, 0] : +List<U32>}
      emit_bytes(~&2, List.append(&2, U32, header, bytes))
def image(image: J.Image.FloatRGB) -> IO(Unit):
  J.FloatRGB{+width, +height, pixels} = image
  emitted(width, height, J.Image.FloatRGB.to_bytes(J.FloatRGB{width, height, pixels}))
def observed(reject: Bool, result: Maybe<Result<&1, &1, J.Image.FloatRGB, J.Image.FloatRGB>>) -> IO(Unit):
  match reject result:
    case False{} Some{Done{value}}: image(value)
    case True{} Some{Fail{value}}: image(value)
    case _ _: IO.die(Unit, 1, "color transform acceptance/owner differs")
def main() -> IO(Unit):
  do IO<Unit>:
'''
    def bend_op(op):
        if op['op']=='tint':return f'Tint{{{op["color"]}}}'
        if op['op']=='invert':return 'Invert{}'
        if op['op']=='replace':return f'Replace{{{op["original"]}, {op["replacement"]}}}'
        value=f'H.float_bits({op["bits"]})' if 'bits' in op else f32(op['amount'])
        return ('Contrast' if op['op']=='contrast' else 'Brightness')+'{'+value+'}'
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program
        for i,case in enumerate([*cases,*controls]):
            ops='['+','.join(bend_op(op) for op in case['operations'])+']'
            body+=f'    observed({"True" if i>=len(cases) else "False"}{{}}, apply{bang}({ops}, J.Image.FloatRGB.from_bytes({case["width"]}, {case["height"]}, {bend_bytes(case["bytes"])})))\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));different=[i for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==expected,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: float color differences {different}')
        print(f'{lane}: {len(cases)} native color cases / {report["pixels"]} pixels and {len(controls)} retained owners passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
