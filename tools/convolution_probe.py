#!/usr/bin/env python3
"""Compare native RGBA8 kernel convolution within defined alpha-cast domains."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct

from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, f32, run, source_gate


def fixtures():
    rng=random.Random(0x636f6e76);cases=[]
    kernels=[[],[1.0],[0.25]*4,[1/9]*9,[0,0,1,0],[0,0,0,0,0,1,0,0,0]]
    for width,height in ((1,1),(1,7),(9,1),(3,2),(7,5)):
        data=[rng.randrange(256) for _ in range(width*height*4)]
        for kernel in kernels:cases.append(dict(width=width,height=height,bytes=data,kernel=kernel,reject=False))
    raw=[rng.randrange(256) for _ in range(20*4)]
    cases.append(dict(width=5,height=4,bytes=raw,kernel=[1/225]*225,reject=False))
    data=[rng.randrange(256) for _ in range(129*257*4)]
    cases.append(dict(width=129,height=257,bytes=data,kernel=[1.0],reject=False))
    levels=[c for i in range(256) for c in (i,255-i,i^0x55,i)]
    for kernel in ([1.0],[2**-16],[1.003],[-1/512]):
        cases.append(dict(width=256,height=1,bytes=levels,kernel=kernel,reject=False))
    transparent=[c for i in range(35) for c in (i*7,255-i*5,i*3,0)]
    for kernel in ([0,-1,0,-1,5,-1,0,-1,0],[16.0],[-16.0]):
        cases.append(dict(width=7,height=5,bytes=transparent,kernel=kernel,reject=False))
    source=[213,97,51,0,255,1,17,255,23,45,67,127]*2
    controls=[dict(width=3,height=2,bytes=source,kernel=kernel,reject=True)
              for kernel in ([1,0],[0]*226,[17.0],[2**-17],['nan'],['infinity'],[2.0],[-1.0],[1.004])]
    return cases,controls


def literal(value):
    if value=='nan':return 'H.float_bits(2143294004)'
    if value=='infinity':return 'H.float_bits(2139095040)'
    return f32(value)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'convolution-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases,controls=fixtures();all_cases=cases+controls
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\\"end\\\"");}',
           'static void emit(Image image){if(!image.data||image.format!=7)exit(3);word(image.width);word(image.height);for(int i=0;i<image.width*image.height*4;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate(all_cases):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},7,0);if(!image.data)return 2;')
        if not case['reject']:
            values=','.join(float(v).hex()+'f' for v in case['kernel']) or '0'
            lines.append(f'float kernel[]={{{values}}};ImageKernelConvolution(&image,kernel,{len(case["kernel"])});')
        lines.append('emit(image);}')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(all_cases):raise ValueError('Incomplete native convolution output')
    for case,row in zip(all_cases,expected):
        if row[:8]!=list(struct.pack('<II',case['width'],case['height'])) or len(row)!=8+len(case['bytes']):raise ValueError('Native convolution shape differs')
    report=dict(passed=False,native_cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),retained_owner_controls=len(controls),
                sources=source_gate(),inputs_sha256=hashlib.sha256(json.dumps(all_cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
import ../../jonlib.bend as J
import ../../src/hdr.bend as H
def word_bytes(n: Nat, +word: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def rgba(pixels: List<U32>, values: List<U32>) -> List<U32>:
  match pixels:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{+color, rest}: rgba(rest, Con{J.Color.alpha(color), Con{J.Color.blue(color), Con{J.Color.green(color), Con{J.Color.red(color), values}}}})
def calculate(kernel: +List<F32>, image: J.Image.Formatted) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  J.Surface.kernel_convolution(J.Image.Formatted.to_surface(image), kernel)
'''+BEND_EMITTER+'''
def emit_surface(surface: J.Surface) -> IO(Unit):
  J.Surface{+width, +height, pixels} = surface
  emit_bytes(~&1, rgba(J.Surface.colors(J.Surface{width, height, pixels}), word_bytes(4n, height, word_bytes(4n, width, Nil{}))))
def observed(reject: Bool, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> IO(Unit):
  match reject result:
    case False{} Done{surface}: emit_surface(surface)
    case True{} Fail{Tuple{surface, J.InvalidKernel{}}}: emit_surface(surface)
    case _ _: IO.die(Unit, 1, "convolution acceptance or retained owner differs")
def loaded(reject: Bool, kernel: +List<F32>, result: Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "convolution fixture read failed")
    case Done{image}: observed(reject, calculateBANG(kernel, image))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        body=program.replace('BANG','!' if lane=='metal' else '')
        for i,case in enumerate(all_cases):
            path=json.dumps(str((work/(str(i)+'.raw')).relative_to(ROOT)));kernel='['+', '.join(map(literal,case['kernel']))+']'
            body+=f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_raw({path}, {case["width"]}, {case["height"]}, 7, 0), loaded({"True" if case["reject"] else "False"}{{}}, {kernel}))\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));different=[i for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==expected,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: convolution differences {different}')
        print(f'{lane}: {len(cases)} native convolution cases / {report["pixels"]} pixels and {len(controls)} retained owners passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
