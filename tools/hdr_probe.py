#!/usr/bin/env python3
"""Compare Radiance RGBE images and every channel/exponent pair as exact F32 bits."""
import argparse
import hashlib
import json
from pathlib import Path

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, run, source_gate


def hdr(width,height,samples,*,signature=b'#?RADIANCE',metadata=b'',dimensions=None):
    line=f'-Y {height} +X {width}'.encode() if dimensions is None else dimensions
    return list(signature+b'\n'+metadata+b'FORMAT=32-bit_rle_rgbe\n\n'+line+b'\n'+bytes(samples))


def fixtures():
    inputs=[]
    samples=[1,127,255,1,1,127,255,10,1,127,255,136,1,127,255,255]
    for signature in (b'#?RADIANCE',b'#?RGBE'):
        inputs.append(dict(id=signature.decode()[2:],bytes=hdr(4,1,samples,signature=signature)))
    inputs += [dict(id='zero-exponent',bytes=hdr(1,1,[255,127,1,0])),
               dict(id='metadata',bytes=hdr(2,2,samples,metadata=b'# comment\nEXPOSURE=2\nGAMMA=2.2\n')),
               dict(id='spaces-zeroes',bytes=hdr(4,1,samples,dimensions=b'-Y 0001   +X  0004')),
               dict(id='width-seven-marker',bytes=hdr(7,1,[2,2,0,7]+samples+samples[:8])),
               dict(id='raw-marker-high-bit',bytes=hdr(8,1,[2,2,128,129]+[3,4,5,127]*7)),
               dict(id='wide',bytes=hdr(4096,1,[v for i in range(4096) for v in (i&255,(i*7)&255,(i*19)&255,(i*11)&255)])),
               dict(id='tall',bytes=hdr(1,4096,[v for i in range(4096) for v in (i&255,(i*7)&255,(i*19)&255,(i*11)&255)])),
               dict(id='trailing',bytes=hdr(1,1,[1,2,3,128])+[9,8,7])]
    base=hdr(1,1,[1,2,3,128])
    malformed=[dict(id='empty',bytes=[],error=0),dict(id='byte',bytes=[*base,256],error=1),
               dict(id='signature',bytes=hdr(1,1,[1,2,3,128],signature=b'#?RADIANCEX'),error=0),
               dict(id='no-format',bytes=list(b'#?RGBE\n\n-Y 1 +X 1\n\1\2\3\x80'),error=0),
               dict(id='truncated-sample',bytes=base[:-1],error=3),
               dict(id='unsupported-rle',bytes=hdr(8,1,[2,2,0,8]),error=0),
               dict(id='long-line',bytes=hdr(1,1,[1,2,3,128],metadata=b'x'*1024+b'\n'),error=0),
               dict(id='zero-width',bytes=hdr(0,1,[]),error=2),dict(id='large-height',bytes=hdr(1,4097,[]),error=2)]
    for name,line in [('orientation',b'+Y 1 +X 1'),('overflow',b'-Y 1 +X 4294967296'),('missing-width',b'-Y 1 +X'),('negative',b'-Y -1 +X 1')]:
        malformed.append(dict(id=name,bytes=hdr(1,1,[1,2,3,128],dimensions=line),error=0))
    return inputs,malformed


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args=parser.parse_args();lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'hdr-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json'
    report_path.write_text(json.dumps(dict(passed=False))+'\n');inputs,malformed=fixtures()
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
           'static Image load(const unsigned char *data,int size){Image image=LoadImageFromMemory(".hdr",data,size);if(!image.data||image.format!=PIXELFORMAT_UNCOMPRESSED_R32G32B32)exit(2);return image;}',
           'static void emit(const unsigned char *data,int size){Image image=load(data,size);word(image.width);word(image.height);for(int i=0;i<image.width*image.height*3;i++){unsigned bits;memcpy(&bits,(float*)image.data+i,4);word(bits);}end();UnloadImage(image);}',
           'static void pairs(void){const char header[]="#?RGBE\\nFORMAT=32-bit_rle_rgbe\\n\\n-Y 256 +X 256\\n";',
           'int prefix=sizeof(header)-1,size=prefix+65536*4;unsigned char *data=malloc(size);if(!data)exit(3);memcpy(data,header,prefix);',
           'for(unsigned e=0;e<256;e++)for(unsigned c=0;c<256;c++){unsigned char *p=data+prefix+4*(e*256+c);p[0]=p[1]=p[2]=c;p[3]=e;}',
           'Image image=load(data,size);for(int i=0;i<65536;i++){unsigned a,b,c;memcpy(&a,(float*)image.data+3*i,4);memcpy(&b,(float*)image.data+3*i+1,4);memcpy(&c,(float*)image.data+3*i+2,4);if(a!=b||a!=c)exit(4);word(a);}end();UnloadImage(image);free(data);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in inputs:lines.append('{unsigned char data[]={'+','.join(map(str,case['bytes']))+'};emit(data,sizeof(data));}')
    source=work/'reference.c';source.write_text('\n'.join(lines+['pairs();}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(inputs)+1 or len(expected[-1])!=65536*4:raise ValueError('Incomplete native HDR results')
    pixels=0
    for row in expected[:-1]:
        width=int.from_bytes(bytes(row[:4]),'little');height=int.from_bytes(bytes(row[4:8]),'little')
        if len(row)!=8+width*height*12:raise ValueError('Native HDR channel count differs')
        pixels+=width*height
    wanted=expected[:-1]+[[c['error']] for c in malformed]+[expected[-1],[1]]
    report=dict(passed=False,images=len(inputs),pixels=pixels,error_controls=len(malformed),channel_exponent_pairs=65536,ownership_controls=1,
                sources=source_gate(),inputs_sha256=hashlib.sha256(json.dumps([inputs,malformed]).encode()).hexdigest(),
                reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/hdr.bend as H
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
def word_bytes(n: Nat, +word: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def samples(pixels: List<M.Vector3>, values: List<U32>) -> List<U32>:
  match pixels:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{M.Vector3{r, g, b}, rest}: samples(rest, word_bytes(4n, F32.bits(b), word_bytes(4n, F32.bits(g), word_bytes(4n, F32.bits(r), values))))
'''+BEND_EMITTER+'''
def emit_image(result: U32 & U32 & List<M.Vector3>) -> IO(Unit):
  (width, height, pixels) = result
  emit_bytes(~&1, samples(pixels, word_bytes(4n, height, word_bytes(4n, width, Nil{}))))
def observed(result: Result<&1, &1, J.Image.DecodeError, J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid HDR rejected")
    case Done{image}: emit_image(J.Image.FloatRGB.entries(image))
def error_code(result: Result<&1, &1, J.Image.DecodeError, J.Image.FloatRGB>) -> U32:
  match result:
    case Done{_}: 99
    case Fail{error}:
      match error:
        case J.InvalidImageHeader{}: 0
        case J.InvalidImageByte{}: 1
        case J.UnsupportedImageSize{}: 2
        case J.TruncatedImageData{}: 3
        case J.InvalidImageStream{}: 4
def channels(n: Nat, +channel: U32, +exponent: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: channels(rest, (channel + 1 : U32), exponent, word_bytes(4n, F32.bits(H.sample(channel, exponent)), values))
def exponents(n: Nat, +exponent: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: List.reverse(&1, U32, values)
    case 1n+rest: exponents(rest, (exponent + 1 : U32), channels(256n, 0, exponent, values))
def unit_seen(value: Unit) -> U32:
  1
def disposed(result: Result<&1, &1, J.Image.DecodeError, J.Image.FloatRGB>) -> U32:
  match result:
    case Fail{_}: 0
    case Done{image}: unit_seen(J.Image.FloatRGB.unload(image))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program
        for case in inputs:body+=f'    observed(J.Image.FloatRGB.decode_hdr{bang}({bend_bytes(case["bytes"])}))\n'
        for case in malformed:body+=f'    emit_bytes(~&1, [error_code(J.Image.FloatRGB.decode_hdr{bang}({bend_bytes(case["bytes"])}))])\n'
        body+=f'    emit_bytes(~&1, exponents{bang}(256n, 0, Nil{{}}))\n'
        body+=f'    emit_bytes(~&1, [disposed{bang}(J.Image.FloatRGB.decode_hdr({bend_bytes(inputs[0]["bytes"])}))])\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));differences=[i for i,(a,b) in enumerate(zip(wanted,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==wanted,different_cases=differences);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=wanted:raise ValueError(f'{lane}: HDR differs in cases {differences}')
        print(f'{lane}: {len(inputs)} HDR images / {pixels} pixels, {len(malformed)} errors and 65536 exact channel/exponent pairs passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
