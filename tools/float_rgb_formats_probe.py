#!/usr/bin/env python3
"""Compare direct float format conversion and grayscale at rounding boundaries."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, run, source_gate


def f32(value):return struct.unpack('<f',struct.pack('<f',value))[0]
def bits(value):return struct.unpack('<I',struct.pack('<f',value))[0]


def fixtures():
    values={0,0x80000000,1,0x007fffff,0x3f800000,0x3d088888,0x3c020820}
    for limit in (15,31,63):
        for level in range(limit):
            center=bits((level+0.5)/limit)
            values.update(word for word in range(center-2,center+3) if 0<=word<=0x3f800000)
    values=sorted(values);words=[v for i,r in enumerate(values) for v in (r,values[(i+7)%len(values)],values[(i+19)%len(values)])]
    packed=dict(width=len(values),height=1,bytes=list(struct.pack('<'+'I'*len(words),*words)))
    cases=[dict(packed,target=target) for target in range(1,8)]
    seed=0xabcdef;gray=[]
    for i in range(1024):
        seed=(seed*1664525+1013904223)&0xffffffff;r=f32((seed>>8)/16777215)
        seed=(seed*1664525+1013904223)&0xffffffff;g=f32((seed>>8)/16777215)
        base=r*f32(0.299)+g*f32(0.587);lo=math.ceil(base*255);hi=math.floor((base+f32(0.114))*255)
        seed=(seed*1664525+1013904223)&0xffffffff;target=lo+seed%(hi-lo+1)
        word=bits((target/255-base)/f32(0.114))
        if 3<word<0x3f7ffffc:word+=i%7-3
        gray.extend((bits(r),bits(g),word))
    gray_data=list(struct.pack('<'+'I'*len(gray),*gray))
    cases += [dict(width=32,height=32,bytes=gray_data,target=target) for target in (1,2)]
    original=list(struct.pack('<fff',0.5,0.25,0.75))
    controls=[dict(width=1,height=1,bytes=original,target=target) for target in (0,8,9)]
    controls.append(dict(width=1,height=1,bytes=list(struct.pack('<fff',2.0,0.5,0.75)),target=3))
    return cases,controls


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'float-rgb-formats-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases,controls=fixtures();lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
        'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
        'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
        'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
        'static void emit(Image image){if(!image.data)exit(2);word(image.width);word(image.height);word(image.format);',
        'int size=GetPixelDataSize(image.width,image.height,image.format);for(int i=0;i<size;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
        'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate([*cases,*controls]):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},PIXELFORMAT_UNCOMPRESSED_R32G32B32,0);')
        if i<len(cases):lines.append('ImageColorGrayscale(&image);' if case['target']==1 else f'ImageFormat(&image,{case["target"]});')
        lines.append('emit(image);}')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(cases)+len(controls):raise ValueError('Incomplete native direct-format results')
    sizes={1:1,2:2,3:2,4:3,5:2,6:2,7:4,9:12}
    for i,(case,row) in enumerate(zip([*cases,*controls],expected)):
        target=case['target'] if i<len(cases) else 9
        if row[:12]!=list(struct.pack('<III',case['width'],case['height'],target)) or len(row)!=12+case['width']*case['height']*sizes[target]:raise ValueError('Native format metadata differs')
    for word,limit,target,component,shift in ((0x3d088888,15,6,0,12),(0x3c020820,63,3,1,5)):
        case=cases[target-1];data=bytes(case['bytes']);index=next(i for i in range(case['width']) if struct.unpack_from('<I',data,i*12+component*4)[0]==word)
        native=(int.from_bytes(bytes(expected[target-1][12+index*2:14+index*2]),'little')>>shift)&limit
        value=struct.unpack('<f',struct.pack('<I',word))[0];old=math.floor(f32(f32(value*limit)+0.5))
        if native!=0 or old!=1:raise ValueError('Packed rounding fixture no longer distinguishes native round from add-half')
    report=dict(passed=False,native_cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),retained_owner_controls=len(controls),
                packed_boundary_values=cases[0]['width'],gray_boundary_pixels=1024,packed_rounding_regressions=2,sources=source_gate(),
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
def word_bytes(~q: Quant, n: Nat, +word: U32, values: List<q, U32>) -> List<q, U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(~q, rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
'''+BEND_EMITTER+'''
def emitted(~q: Quant, width: U32, height: U32, format: U32, bytes: List<q, U32>) -> IO(Unit):
  header = List.reverse(q, U32, word_bytes(~q, 4n, format, word_bytes(~q, 4n, height, word_bytes(~q, 4n, width, Nil{}))))
  emit_bytes(~q, List.append(q, U32, header, bytes))
def formatted(result: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = result
  emitted(~&1, width, height, format, bytes)
def retained.bytes(width: U32, height: U32, result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "retained format owner changed")
    case Done{bytes}: emitted(~&2, width, height, 9, bytes)
def retained(image: J.Image.FloatRGB) -> IO(Unit):
  J.FloatRGB{+width, +height, pixels} = image
  retained.bytes(width, height, J.Image.FloatRGB.to_bytes(J.FloatRGB{width, height, pixels}))
def selected(reject: Bool, result: Result<&1, &1, J.Image.FloatRGB, J.Image.Formatted>) -> IO(Unit):
  match reject result:
    case False{} Done{image}: formatted(J.Image.Formatted.export(image))
    case True{} Fail{image}: retained(image)
    case _ _: IO.die(Unit, 1, "direct conversion acceptance/owner differs")
def converted(target: U32, result: Maybe<J.Image.FloatRGB>) -> Maybe<Result<&1, &1, J.Image.FloatRGB, J.Image.Formatted>>:
  match target result:
    case _ None{}: None{}
    case 1 Some{image}: Some{J.Image.FloatRGB.color_grayscale(image)}
    case _ Some{image}: Some{J.Image.FloatRGB.to_formatted(image, target)}
def observed(reject: Bool, result: Maybe<Result<&1, &1, J.Image.FloatRGB, J.Image.Formatted>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid direct-format source rejected")
    case Some{value}: selected(reject, value)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program
        for i,case in enumerate([*cases,*controls]):
            body+=f'    observed({"True" if i>=len(cases) else "False"}{{}}, converted{bang}({case["target"]}, J.Image.FloatRGB.from_bytes({case["width"]}, {case["height"]}, {bend_bytes(case["bytes"])})))\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));different=[i for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==expected,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: direct float format differences {different}')
        print(f'{lane}: {len(cases)} native direct-format cases / {report["pixels"]} pixels and {len(controls)} retained owners passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
