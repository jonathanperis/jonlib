#!/usr/bin/env python3
"""Compare all supported byte-channel/alpha pairs with native PSD and arithmetic models."""
import hashlib

from byte_probe import BEND_EMITTER, parse_results
from conformance import image_decode_reference
import probekit
from probekit import ProbeFailure


REFERENCE='''#include "raylib.h"
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
'''


PREAMBLE='''import Base
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


def main():
    probe=probekit.Probe('psd-matte',probekit.arguments(__doc__))
    text=probe.native(REFERENCE,extra_flags=('-ffp-contract=off','-fno-builtin-fmaf'));(probe.work/'reference.jsonl').write_text(text)
    reference=parse_results(text)
    if len(reference)!=3 or any(len(values)!=33151 for values in reference):raise ProbeFailure('Incomplete native matte results')
    profile=image_decode_reference();selected=1 if profile=='Fused' else 0
    native_differences={name:sum(a!=b for a,b in zip(reference[index],reference[2]))
                        for index,name in enumerate(('Uncontracted','Fused'))}
    probe.report.update(native_profile=profile,native_model_mismatches=native_differences);probe.save()
    if reference[selected]!=reference[2]:raise ProbeFailure(f'Linked native PSD differs from declared {profile} arithmetic')

    def render(selected,gpu):
        bang='!' if gpu else '';program=PREAMBLE+'def main() -> IO(Unit):\n  do IO<Unit>:\n'
        for fused in selected:program+=f'    emit_bytes(~&1, alphas{bang}(256n, 0, {fused}{{}}, Nil{{}}))\n'
        return program

    modes=['False','True']
    probe.compare(reference[:2],probe.candidates(render,modes,batch=2,parse=lambda text,selected:parse_results(text)),
                  lambda i:f'{("Uncontracted","Fused")[i]} model')
    probe.finish(pairs=33151,intermediate_alpha_pairs=32639,native_profile=profile,
                 model_disagreements=sum(a!=b for a,b in zip(reference[0],reference[1])),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
