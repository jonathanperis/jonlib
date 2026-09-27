#!/usr/bin/env python3
"""Compare all supported byte-channel/alpha pairs with native PSD and arithmetic models."""
import argparse
import hashlib
import json
from pathlib import Path

from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, image_decode_reference, run, source_gate


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'psd-matte-probe';work.mkdir(parents=True,exist_ok=True)
    report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    source=work/'reference.c'
    source.write_text('''#include "raylib.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void word(unsigned char *p,unsigned value){for(int i=0;i<4;i++)p[i]=(unsigned char)(value>>(24-8*i));}
static unsigned model(unsigned c,unsigned a,int fused){
    if(a==0||a==255)return c;
    volatile float alpha=a/255.0f,reciprocal=1.0f/alpha,inverse=255.0f*(1.0f-reciprocal);
    if(fused)return (unsigned char)fmaf((float)c,reciprocal,inverse);
    volatile float product=c*reciprocal;return (unsigned char)(product+inverse);
}
static void emit(const unsigned char *values,int count){
    for(int start=0;start<count;start+=256){putchar('[');for(int i=start;i<count&&i<start+256;i++)printf("%s%u",i==start?"":",",values[i]);puts("]");}
    puts("\\"end\\"");
}
int main(void){
    SetTraceLogLevel(LOG_NONE);
    const int count=256*130,size=40+4*count;
    unsigned char *bytes=calloc(size,1),*u=malloc(count),*f=malloc(count),*native=malloc(count);
    if(!bytes||!u||!f||!native)return 1;
    memcpy(bytes,"8BPS",4);bytes[5]=1;bytes[13]=4;word(bytes+14,130);word(bytes+18,256);bytes[23]=8;bytes[25]=3;
    int at=0;
    for(unsigned a=0;a<256;a++)for(unsigned c=(a==0||a==255)?0:255-a;c<256;c++,at++){
        bytes[40+at]=bytes[40+count+at]=bytes[40+2*count+at]=c;bytes[40+3*count+at]=a;
        u[at]=model(c,a,0);f[at]=model(c,a,1);
    }
    int tested=at;
    for(;at<count;at++)bytes[40+at]=bytes[40+count+at]=bytes[40+2*count+at]=bytes[40+3*count+at]=255;
    Image image=LoadImageFromMemory(".psd",bytes,size);if(!image.data)return 2;
    ImageFormat(&image,PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);Color *pixels=LoadImageColors(image);
    for(int i=0;i<tested;i++){
        if(pixels[i].r!=pixels[i].g||pixels[i].r!=pixels[i].b||pixels[i].a!=bytes[40+3*count+i])return 3;
        native[i]=pixels[i].r;
    }
    emit(u,tested);emit(f,tested);emit(native,tested);
    UnloadImageColors(pixels);UnloadImage(image);free(bytes);free(u);free(f);free(native);
}
''')
    binary=work/'reference'
    run(['clang','-std=c11','-O2','-ffp-contract=off','-fno-builtin-fmaf','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    text=run([binary]);(work/'reference.jsonl').write_text(text)
    reference=parse_results(text)
    if len(reference)!=3 or any(len(values)!=33151 for values in reference):raise ValueError('Incomplete native matte results')
    profile=image_decode_reference();selected=1 if profile=='FusedDecode' else 0
    native_differences={name:sum(a!=b for a,b in zip(reference[index],reference[2]))
                        for index,name in enumerate(('UncontractedDecode','FusedDecode'))}
    report=dict(passed=False,pairs=33151,intermediate_alpha_pairs=32639,native_profile=profile,
                model_disagreements=sum(a!=b for a,b in zip(reference[0],reference[1])),
                native_model_mismatches=native_differences,
                sources=source_gate(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    report_path.write_text(json.dumps(report,indent=2)+'\n')
    if reference[selected]!=reference[2]:raise ValueError(f'Linked native PSD differs from declared {profile} arithmetic')
    preamble='''import Base
import ../../src/psd.bend as P
def observed(+alpha: U32, result: Result<&2, &2, P.Error, U32>) -> U32:
  match result:
    case Fail{_}: 256
    case Done{+color}:
      +red = (color >> 24n : U32)
      Bool.pick(U32, U32.is_eq(((color >> 16n) .&. 255 : U32), red)
        && U32.is_eq(((color >> 8n) .&. 255 : U32), red) && U32.is_eq((color .&. 255 : U32), alpha), red, 256)
def samples(n: Nat, +value: U32, +alpha: U32, +fused: Bool, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: samples(rest, (value + 1 : U32), alpha, fused,
      Con{observed(alpha, P.matte.pixel(fused, ((value << 24n) .|. (value << 16n) .|. (value << 8n) .|. alpha : U32))), values})
def alphas(n: Nat, +alpha: U32, +fused: Bool, values: List<U32>) -> List<U32>:
  match n:
    case 0n: List.reverse(&1, U32, values)
    case 1n+rest:
      +lower = Bool.pick(U32, U32.is_eq(alpha, 0) || U32.is_eq(alpha, 255), 0, (255 - alpha : U32))
      alphas(rest, (alpha + 1 : U32), fused, samples(U32.to_nat((256 - lower : U32)), lower, alpha, fused, values))
'''+BEND_EMITTER
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else ''
        program=preamble+'def main() -> IO(Unit):\n  do IO<Unit>:\n'
        for fused in ('False','True'):program+=f'    emit_bytes(~&1, alphas{bang}(256n, 0, {fused}{{}}, Nil{{}}))\n'
        source=work/f'{lane}.bend';source.write_text(program)
        binary=work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));differences=[]
        for mode,(a,b) in enumerate(zip(reference[:2],actual)):
            differences.extend(dict(mode=mode,index=i,reference=x,candidate=y) for i,(x,y) in enumerate(zip(a,b)) if x!=y)
        report['lanes'][lane]=dict(passed=actual==reference[:2],differences=differences[:8])
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=reference[:2]:raise ValueError(f'{lane}: matte model differs: {differences[:4]}')
        print(f'{lane}: all 33151 channel/alpha pairs match both models; native selects {profile}',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
