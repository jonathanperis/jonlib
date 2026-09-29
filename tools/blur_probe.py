#!/usr/bin/env python3
"""Compare native default RGBA8 Gaussian blur and rejected source owners."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct

from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, run, source_gate


def fixtures():
    rng=random.Random(0x626c7572);cases=[]
    for width,height in ((1,1),(1,17),(19,1),(2,3),(7,5),(17,13),(4096,1),(1,4096),(129,257)):
        data=[rng.randrange(256) for _ in range(width*height*4)]
        for i in range(width*height):data[4*i+3]=(0,1,2,127,254,255)[i%6]
        for size in sorted({0,1,min(width,height)}):
            cases.append(dict(width=width,height=height,bytes=data,size=size,repeats=1,reject=False))
    for color in ([231,19,153,0],[255,255,255,255],[213,97,51,1]):
        cases.append(dict(width=8,height=8,bytes=color*64,size=3,repeats=1,reject=False))
    impulse=[0]*140;impulse[4*17:4*18]=[255,127,63,255]
    cases.append(dict(width=7,height=5,bytes=impulse,size=2,repeats=1,reject=False))
    cases.append(dict(cases[13],size=2,repeats=2))
    controls=[dict(width=width,height=height,bytes=[213,97,51,127,255,1,17,1]*3,size=size,repeats=1,reject=True)
              for width,height,size in ((3,2,3),(2,3,3),(3,2,4294967295))]
    return cases,controls


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'blur-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
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
        if not case['reject']:lines.append(f'for(int i=0;i<{case["repeats"]};i++)ImageBlurGaussian(&image,{case["size"]});')
        lines.append('emit(image);}')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(all_cases):raise ValueError('Incomplete native blur output')
    for case,row in zip(all_cases,expected):
        if row[:8]!=list(struct.pack('<II',case['width'],case['height'])) or len(row)!=8+len(case['bytes']):raise ValueError('Native blur shape differs')
    report=dict(passed=False,native_cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),retained_owner_controls=len(controls),
                sources=source_gate(),inputs_sha256=hashlib.sha256(json.dumps(all_cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
import ../../jonlib.bend as J
def word_bytes(n: Nat, +word: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def rgba(pixels: List<U32>, values: List<U32>) -> List<U32>:
  match pixels:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{+color, rest}: rgba(rest, Con{J.Color.alpha(color), Con{J.Color.blue(color), Con{J.Color.green(color), Con{J.Color.red(color), values}}}})
def repeat(n: Nat, +size: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  match n result:
    case 0n _: result
    case _ Fail{error}: Fail{error}
    case 1n+rest Done{surface}: repeat(rest, size, J.Surface.blur_gaussian(surface, size))
def calculate(repeats: Nat, size: U32, image: J.Image.Formatted) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  repeat(repeats, size, Done{J.Image.Formatted.to_surface(image)})
'''+BEND_EMITTER+'''
def emit_surface(surface: J.Surface) -> IO(Unit):
  J.Surface{+width, +height, pixels} = surface
  emit_bytes(~&1, rgba(J.Surface.colors(J.Surface{width, height, pixels}), word_bytes(4n, height, word_bytes(4n, width, Nil{}))))
def observed(reject: Bool, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> IO(Unit):
  match reject result:
    case False{} Done{surface}: emit_surface(surface)
    case True{} Fail{Tuple{surface, J.InvalidSize{}}}: emit_surface(surface)
    case _ _: IO.die(Unit, 1, "blur acceptance or retained owner differs")
def loaded(reject: Bool, repeats: Nat, size: U32, result: Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "blur fixture read failed")
    case Done{image}: observed(reject, calculateBANG(repeats, size, image))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        body=program.replace('BANG','!' if lane=='metal' else '')
        for i,case in enumerate(all_cases):
            path=json.dumps(str((work/(str(i)+'.raw')).relative_to(ROOT)))
            body+=f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_raw({path}, {case["width"]}, {case["height"]}, 7, 0), loaded({"True" if case["reject"] else "False"}{{}}, {case["repeats"]}n, {case["size"]}))\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));different=[i for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==expected,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: blur differences {different}')
        print(f'{lane}: {len(cases)} native blur cases / {report["pixels"]} pixels and {len(controls)} retained owners passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
