#!/usr/bin/env python3
"""Compare native byte/packed image normalization to RGB floats and return chains."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, run, source_gate


def fixtures():
    cases=[]
    for format in range(1,8):
        data=[]
        for i in range(256):
            if format==1:data.append(i)
            elif format==2:data.extend((i,255-i))
            elif format==3:data.extend(struct.pack('<H',((i%32)<<11)|((i%64)<<5)|(31-i%32)))
            elif format==4:data.extend((i,255-i,i^85))
            elif format==5:data.extend(struct.pack('<H',((i%32)<<11)|((31-i%32)<<6)|(((i*7)%32)<<1)|(i%2)))
            elif format==6:data.extend(struct.pack('<H',((i%16)<<12)|((15-i%16)<<8)|(((i*7)%16)<<4)|(i//16)))
            else:data.extend((i,255-i,i^85,i))
        cases.append(dict(width=16,height=16,format=format,bytes=data))
    return cases


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'formatted-float-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases=fixtures();lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
        'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
        'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
        'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
        'static void emit(Image image){if(!image.data)exit(2);word(image.width);word(image.height);word(image.format);',
        'int size=GetPixelDataSize(image.width,image.height,image.format);for(int i=0;i<size;i++)byte(((unsigned char*)image.data)[i]);end();}',
        'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        path=work/(str(case['format'])+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},16,16,{case["format"]},0);ImageFormat(&image,9);emit(image);ImageFormat(&image,{case["format"]});emit(image);UnloadImage(image);}}')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(cases)*2:raise ValueError('Incomplete native float normalization output')
    for i,case in enumerate(cases):
        for target,row,size in ((9,expected[2*i],3072),(case['format'],expected[2*i+1],len(case['bytes']))):
            if row[:12]!=list(struct.pack('<III',16,16,target)) or len(row)!=12+size:raise ValueError('Native normalization shape differs')
    report=dict(passed=False,source_formats=7,pixels=1792,native_results=len(expected),sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
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
def float_bytes(width: U32, height: U32, result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "normalization produced unsupported samples")
    case Done{bytes}: emitted(~&2, width, height, 9, bytes)
def normalized(result: Maybe<J.Image.Formatted>) -> Maybe<J.Image.FloatRGB>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.to_float_rgb(image)}
def observed(result: Maybe<J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "normalization source rejected")
    case Some{J.FloatRGB{+width, +height, pixels}}: float_bytes(width, height, J.Image.FloatRGB.to_bytes(J.FloatRGB{width, height, pixels}))
def returned(result: Result<&1, &1, J.Image.FloatRGB, J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{image}
def chain(target: U32, result: Maybe<J.Image.FloatRGB>) -> Maybe<J.Image.Formatted>:
  match result:
    case None{}: None{}
    case Some{image}: returned(J.Image.FloatRGB.to_formatted(image, target))
def roundtrip(target: U32, result: Maybe<J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  chain(target, normalized(result))
def observed_chain(result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "normalization return chain rejected")
    case Some{image}: formatted(J.Image.Formatted.export(image))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program
        for case in cases:
            image=f'J.Image.Formatted.from_bytes(16, 16, {case["format"]}, {bend_bytes(case["bytes"])})'
            body+=f'    observed(normalized{bang}({image}))\n'
            body+=f'    observed_chain(roundtrip{bang}({case["format"]}, {image}))\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));different=[i for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==expected,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: formatted float differences {different}')
        print(f'{lane}: 7 source formats / 1792 pixels, 14 native float/return-chain results passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
