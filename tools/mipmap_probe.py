#!/usr/bin/env python3
"""Compare every owned RGBA8 mipmap level with native ImageMipmaps."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct

from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, run, source_gate


def fixtures():
    rng=random.Random(0x6d6970)
    cases=[]
    for width,height in ((1,1),(2,2),(3,5),(7,4),(8,8),(17,9),(1,31),(31,1),(4096,1),(1,4096),(129,257)):
        data=[rng.randrange(256) for _ in range(width*height*4)]
        for i in range(width*height):
            data[4*i+3]=(0,1,127,254,255)[i%5]
        cases.append(dict(width=width,height=height,bytes=data,mutate=False))
    cases += [dict(cases[0],mutate=True),dict(cases[2],mutate=True),dict(cases[5],mutate=True)]
    return cases


def shapes(width,height):
    result=[(width,height)]
    while (width,height)!=(1,1):
        width=max(1,width//2);height=max(1,height//2);result.append((width,height))
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'mipmap-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases=fixtures()
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\\"end\\\"");}',
           'static void emit(Image image,int mutate){if(!image.data||image.format!=7)exit(3);word(image.mipmaps);int w=image.width,h=image.height;unsigned char *p=image.data;',
           'for(int level=0;level<image.mipmaps;level++){if(mutate&&level==(image.mipmaps>1?1:0)){p[0]=0x12;p[1]=0x34;p[2]=0x56;p[3]=0x78;}',
           'word(w);word(h);for(int i=0;i<w*h*4;i++)byte(p[i]);p+=w*h*4;w=w>1?w/2:1;h=h>1?h/2:1;}end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate(cases):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines += [f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},7,0);if(!image.data)return 2;',
                  f'ImageMipmaps(&image);emit(image,{int(case["mutate"])});}}']
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(cases):raise ValueError('Incomplete native mipmap output')
    for case,row in zip(cases,expected):
        levels=shapes(case['width'],case['height']);payload=bytes(row)
        if struct.unpack_from('<I',payload)[0]!=len(levels):raise ValueError('Native mipmap count differs')
        at=4
        for width,height in levels:
            if struct.unpack_from('<II',payload,at)!=(width,height):raise ValueError('Native mipmap dimensions differ')
            at+=8+width*height*4
        if at!=len(payload):raise ValueError('Incomplete native mipmap pixels')
    report=dict(passed=False,native_cases=len(cases),levels=sum(len(shapes(c['width'],c['height'])) for c in cases),
                pixels=sum(w*h for c in cases for w,h in shapes(c['width'],c['height'])),mutated_chain_controls=sum(c['mutate'] for c in cases),
                sources=source_gate(),inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
import ../../jonlib.bend as J
def word_bytes(n: Nat, +word: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def rgba(pixels: List<U32>, values: List<U32>) -> List<U32>:
  match pixels:
    case Nil{}: values
    case Con{+color, rest}: rgba(rest, Con{J.Color.alpha(color), Con{J.Color.blue(color), Con{J.Color.green(color), Con{J.Color.red(color), values}}}})
def level_bytes(levels: List<J.Surface>, values: List<U32>) -> List<U32>:
  match levels:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{J.Surface{+width, +height, pixels}, rest}:
      level_bytes(rest, rgba(J.Surface.colors(J.Surface{width, height, pixels}), word_bytes(4n, height, word_bytes(4n, width, values))))
def mark(levels: List<J.Surface>) -> List<J.Surface>:
  match levels:
    case Con{first, Nil{}}: Con{J.Surface.draw_pixel(first, 0.0, 0.0, 305419896), Nil{}}
    case Con{first, Con{second, rest}}: Con{first, Con{J.Surface.draw_pixel(second, 0.0, 0.0, 305419896), rest}}
    case Nil{}: Nil{}
def selected(mutate: Bool, chain: J.Image.Mipmaps) -> J.Image.Mipmaps:
  match mutate chain:
    case False{} _: chain
    case True{} J.Mipmaps{count, levels}: J.Mipmaps{count, mark(levels)}
def calculate(mutate: Bool, image: J.Image.Formatted) -> J.Image.Mipmaps:
  selected(mutate, J.Surface.mipmaps(J.Image.Formatted.to_surface(image)))
'''+BEND_EMITTER+'''
def observed(result: U32 & List<J.Surface>) -> IO(Unit):
  (count, levels) = result
  emit_bytes(~&1, level_bytes(levels, word_bytes(4n, count, Nil{})))
def loaded(mutate: Bool, result: Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "mipmap fixture read failed")
    case Done{image}: observed(J.Image.Mipmaps.entries(calculateBANG(mutate, image)))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        body=program.replace('BANG','!' if lane=='metal' else '')
        for i,case in enumerate(cases):
            path=json.dumps(str((work/(str(i)+'.raw')).relative_to(ROOT)))
            body+=f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_raw({path}, {case["width"]}, {case["height"]}, 7, 0), loaded({"True" if case["mutate"] else "False"}{{}}))\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));different=[i for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==expected,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: mipmap differences {different}')
        print(f'{lane}: {len(cases)} native mipmap chains / {report["levels"]} levels / {report["pixels"]} pixels and independent owners passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
