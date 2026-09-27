#!/usr/bin/env python3
"""Compare owned RGB-float/RGBA8 conversion with native ImageFormat."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, run, source_gate


def boundaries():
    values={0,0x80000000,1,0x007fffff,0x00800000,0x3f800000}
    for byte in range(256):
        bits=struct.unpack('<I',struct.pack('<f',byte/255.0))[0]
        values.update(v for v in (bits-1,bits,bits+1) if 0<=v<=0x3f800000)
    values=sorted(values)
    return [component for i,value in enumerate(values) for component in (value,values[(i+17)%len(values)],values[(i+53)%len(values)])]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args=parser.parse_args();lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'float-rgb-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    words=boundaries();count=len(words)//3;invalid=[0x80000001,0xbe800000,0x3f800001,0x7f800000,0xff800000,0x7fc00001,0xffc00001]
    source=work/'reference.c'
    source.write_text('''#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int used=0;
static void byte(unsigned v){if(!used)putchar('[');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}
static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}
static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}
static void emit(Image image){
    word(image.width);word(image.height);
    if(image.format==PIXELFORMAT_UNCOMPRESSED_R32G32B32){for(int i=0;i<image.width*image.height*3;i++){unsigned bits;memcpy(&bits,(float*)image.data+i,4);word(bits);}}
    else {for(int i=0;i<image.width*image.height*4;i++)byte(((unsigned char*)image.data)[i]);}
    end();
}
int main(void){
    SetTraceLogLevel(LOG_NONE);
    Image bytes=GenImageColor(256,1,BLANK);
    for(int i=0;i<256;i++)((Color*)bytes.data)[i]=(Color){i,255-i,i^0x55,i};
    ImageFormat(&bytes,PIXELFORMAT_UNCOMPRESSED_R32G32B32);emit(bytes);
    ImageFormat(&bytes,PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);emit(bytes);UnloadImage(bytes);
    unsigned values[]={'''+','.join(map(str,words))+'''};
    Image boundary={malloc(sizeof(values)),sizeof(values)/12,1,1,PIXELFORMAT_UNCOMPRESSED_R32G32B32};
    if(!boundary.data)return 1;memcpy(boundary.data,values,sizeof(values));
    ImageFormat(&boundary,PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);emit(boundary);UnloadImage(boundary);
    const char header[]="#?RGBE\\nFORMAT=32-bit_rle_rgbe\\n\\n-Y 129 +X 256\\n";
    int prefix=sizeof(header)-1,size=prefix+256*129*4;unsigned char *data=malloc(size);if(!data)return 2;memcpy(data,header,prefix);
    for(unsigned e=0;e<129;e++)for(unsigned c=0;c<256;c++){unsigned char *p=data+prefix+4*(e*256+c);p[0]=c;p[1]=255-c;p[2]=c^0x55;p[3]=e;}
    Image hdr=LoadImageFromMemory(".hdr",data,size);if(!hdr.data)return 3;
    emit(hdr);ImageFormat(&hdr,PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);emit(hdr);UnloadImage(hdr);free(data);
}
''')
    binary=work/'reference';run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    text=run([binary]);expected=parse_results(text)
    lengths=[8+256*12,8+256*4,8+count*4,8+33024*12,8+33024*4]
    if len(expected)!=5 or [len(row) for row in expected]!=lengths:raise ValueError('Incomplete native float conversion output')
    wanted=expected+[[1] for _ in invalid]
    report=dict(passed=False,normalized_byte_values=256,boundary_pixels=count,hdr_pixels=33024,rejected_owner_controls=len(invalid),sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps([words,invalid]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
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
def colors(pixels: List<U32>, values: List<U32>) -> List<U32>:
  match pixels:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{+color, rest}: colors(rest, Con{J.Color.alpha(color), Con{J.Color.blue(color), Con{J.Color.green(color), Con{J.Color.red(color), values}}}})
'''+BEND_EMITTER+'''
def emit_floats(result: U32 & U32 & List<M.Vector3>) -> IO(Unit):
  (width, height, pixels) = result
  emit_bytes(~&1, samples(pixels, word_bytes(4n, height, word_bytes(4n, width, Nil{}))))
def emit_surface(result: Result<&1, &1, J.Image.FloatRGB, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid float conversion rejected")
    case Done{J.Surface{+width, +height, pixels}}:
      emit_bytes(~&1, colors(J.Surface.colors(J.Surface{width, height, pixels}), word_bytes(4n, height, word_bytes(4n, width, Nil{}))))
def byte_pixels(n: Nat, +index: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest: byte_pixels(rest, (index + 1 : U32), Array.set(U32, pixels, index, J.Color.rgba(index, (255 - index : U32), (index .^. 85 : U32), index)))
def byte_image() -> J.Surface:
  J.Surface{256, 1, byte_pixels(256n, 0, Array.new(U32, 8n, 0))}
def from_words(words: +List<U32>, +index: U32, pixels: Array<M.Vector3>) -> Array<M.Vector3>:
  match words:
    case Con{r, Con{g, Con{b, rest}}}: from_words(rest, (index + 1 : U32), Array.set(M.Vector3, pixels, index, M.Vector3{H.float_bits(r), H.float_bits(g), H.float_bits(b)}))
    case _: pixels
def boundary_image(words: +List<U32>, +width: U32) -> J.Image.FloatRGB:
  J.FloatRGB{width, 1, from_words(words, 0, Array.new(M.Vector3, J.Surface.capacity(width), M.Vector3{0.0, 0.0, 0.0}))}
def hdr_pixels(n: Nat, +index: U32, pixels: Array<M.Vector3>) -> Array<M.Vector3>:
  match n:
    case 0n: pixels
    case 1n+rest:
      +channel = (index % 256 : U32)
      +exponent = (index / 256 : U32)
      hdr_pixels(rest, (index + 1 : U32), Array.set(M.Vector3, pixels, index,
        M.Vector3{H.sample(channel, exponent), H.sample((255 - channel : U32), exponent), H.sample((channel .^. 85 : U32), exponent)}))
def hdr_image() -> J.Image.FloatRGB:
  J.FloatRGB{256, 129, hdr_pixels(33024n, 0, Array.new(M.Vector3, 16n, M.Vector3{0.0, 0.0, 0.0}))}
def vector_bits(left: M.Vector3, right: M.Vector3) -> Bool:
  M.Vector3{a, b, c} = left
  M.Vector3{x, y, z} = right
  U32.is_eq(F32.bits(a), F32.bits(x)) && U32.is_eq(F32.bits(b), F32.bits(y)) && U32.is_eq(F32.bits(c), F32.bits(z))
def rejected_values(wanted: M.Vector3, values: List<M.Vector3>) -> Bool:
  match values:
    case Con{first, Con{second, Nil{}}}: vector_bits(first, M.Vector3{0.25, 0.5, 0.75}) && vector_bits(wanted, second)
    case _: False{}
def rejected_entries(wanted: M.Vector3, result: U32 & U32 & List<M.Vector3>) -> Bool:
  (width, height, values) = result
  U32.is_eq(width, 2) && U32.is_eq(height, 1) && rejected_values(wanted, values)
def rejected(wanted: M.Vector3, result: Result<&1, &1, J.Image.FloatRGB, J.Surface>) -> Bool:
  match result:
    case Done{_}: False{}
    case Fail{image}: rejected_entries(wanted, J.Image.FloatRGB.entries(image))
def invalid_pixel(component: U32, value: F32) -> M.Vector3:
  match component:
    case 0: M.Vector3{value, 0.5, 0.75}
    case 1: M.Vector3{0.25, value, 0.75}
    case _: M.Vector3{0.25, 0.5, value}
def rejection(bits: U32, component: U32) -> Bool:
  +wanted = invalid_pixel(component, H.float_bits(bits))
  pixels = Array.set(M.Vector3, Array.new(M.Vector3, 1n, M.Vector3{0.25, 0.5, 0.75}), 1, wanted)
  rejected(wanted, J.Image.FloatRGB.to_surface(J.FloatRGB{2, 1, pixels}))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program
        body+=f'    emit_floats(J.Image.FloatRGB.entries(J.Surface.to_float_rgb{bang}(byte_image())))\n'
        body+=f'    emit_surface(J.Image.FloatRGB.to_surface{bang}(J.Surface.to_float_rgb(byte_image())))\n'
        body+=f'    emit_surface(J.Image.FloatRGB.to_surface{bang}(boundary_image({bend_bytes(words)}, {count})))\n'
        body+=f'    emit_floats(J.Image.FloatRGB.entries{bang}(hdr_image()))\n'
        body+=f'    emit_surface(J.Image.FloatRGB.to_surface{bang}(hdr_image()))\n'
        for index,bits in enumerate(invalid):body+=f'    emit_bytes(~&1, [Bool.to_u32(rejection{bang}({bits}, {index%3}))])\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));differences=[i for i,(a,b) in enumerate(zip(wanted,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==wanted,different_cases=differences);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=wanted:raise ValueError(f'{lane}: float conversion differs in cases {differences}')
        print(f'{lane}: 256 byte normalizations, {count} boundary pixels, 33024 HDR pixels and 7 rejected owners passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
