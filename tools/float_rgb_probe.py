#!/usr/bin/env python3
"""Compare owned RGB-float/RGBA8 conversion with native ImageFormat."""
import hashlib
import json
import struct

from bmp_probe import bend_bytes
from byte_probe import C_EMITTER, BEND_EMITTER, parse_results
from conformance import source_gate
import probekit
from probekit import ProbeFailure

REFERENCE = '''#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
''' + C_EMITTER + '\n' + '''static void emit(Image image){
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
    unsigned values[]={WORDS};
    Image boundary={malloc(sizeof(values)),sizeof(values)/12,1,1,PIXELFORMAT_UNCOMPRESSED_R32G32B32};
    if(!boundary.data)return 1;memcpy(boundary.data,values,sizeof(values));
    ImageFormat(&boundary,PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);emit(boundary);UnloadImage(boundary);
    const char header[]="#?RGBE\\nFORMAT=32-bit_rle_rgbe\\n\\n-Y 129 +X 256\\n";
    int prefix=sizeof(header)-1,size=prefix+256*129*4;unsigned char *data=malloc(size);if(!data)return 2;memcpy(data,header,prefix);
    for(unsigned e=0;e<129;e++)for(unsigned c=0;c<256;c++){unsigned char *p=data+prefix+4*(e*256+c);p[0]=c;p[1]=255-c;p[2]=c^0x55;p[3]=e;}
    Image hdr=LoadImageFromMemory(".hdr",data,size);if(!hdr.data)return 3;
    emit(hdr);ImageFormat(&hdr,PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);emit(hdr);UnloadImage(hdr);free(data);
}
'''
PROGRAM = '''import Base
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
def header(+width: U32, +height: U32) -> List<U32>:
  List.reverse(&1, U32, word_bytes(4n, height, word_bytes(4n, width, Nil{})))
def colors(pixels: List<U32>, values: List<U32>) -> List<U32>:
  match pixels:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{+color, rest}: colors(rest, Con{J.Color.alpha(color), Con{J.Color.blue(color), Con{J.Color.green(color), Con{J.Color.red(color), values}}}})
'''+BEND_EMITTER+'''
def emit_floats(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match data:
    case Tuple{Tuple{width, height}, Tuple{9, bytes}}: emit_bytes(~&1, List.append(&1, U32, header(width, height), bytes))
    case _: IO.die(Unit, 1, "float export format changed")
def emit_converted(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid float conversion rejected")
    case Done{image}: emit_floats(J.Surface.export(image))
def emit_colors(+width: U32, +height: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "converted colors rejected")
    case Done{values}: emit_bytes(~&1, colors(values, word_bytes(4n, height, word_bytes(4n, width, Nil{}))))
def emit_surface(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid float conversion rejected")
    case Done{J.Surface{+width, +height, 7, pixels}}: emit_colors(width, height, J.Surface.colors(J.Surface{width, height, 7, pixels}))
    case Done{_}: IO.die(Unit, 1, "float conversion target format changed")
def to_rgba(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  match result:
    case Fail{failure}: Fail{failure}
    case Done{image}: J.Surface.format(image, 7)
def byte_pixels(n: Nat, +index: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest: byte_pixels(rest, (index + 1 : U32), Array.set(U32, pixels, index, J.Color.rgba(index, (255 - index : U32), (index .^. 85 : U32), index)))
def byte_image() -> J.Surface:
  J.Surface{256, 1, 7, J.Words{byte_pixels(256n, 0, Array.new(U32, 8n, 0))}}
def from_words(words: +List<U32>, +index: U32, pixels: Array<J.Surface.Quad>) -> Array<J.Surface.Quad>:
  match words:
    case Con{r, Con{g, Con{b, rest}}}: from_words(rest, (index + 1 : U32), Array.set(J.Surface.Quad, pixels, index, J.Quad{r, g, b, 0}))
    case _: pixels
def boundary_image(words: +List<U32>, +width: U32) -> J.Surface:
  J.Surface{width, 1, 9, J.Quads{from_words(words, 0, Array.new(J.Surface.Quad, J.Storage.depth(width), J.Quad{F32.bits(0.0), F32.bits(0.0), F32.bits(0.0), 0}))}}
def hdr_pixels(n: Nat, +index: U32, pixels: Array<J.Surface.Quad>) -> Array<J.Surface.Quad>:
  match n:
    case 0n: pixels
    case 1n+rest:
      +channel = (index % 256 : U32)
      +exponent = (index / 256 : U32)
      hdr_pixels(rest, (index + 1 : U32), Array.set(J.Surface.Quad, pixels, index,
        J.Quad{F32.bits(H.sample(channel, exponent)), F32.bits(H.sample((255 - channel : U32), exponent)), F32.bits(H.sample((channel .^. 85 : U32), exponent)), 0}))
def hdr_image() -> J.Surface:
  J.Surface{256, 129, 9, J.Quads{hdr_pixels(33024n, 0, Array.new(J.Surface.Quad, 16n, J.Quad{F32.bits(0.0), F32.bits(0.0), F32.bits(0.0), 0}))}}
def export_words(bytes: List<U32>, values: List<U32>) -> List<U32>:
  match bytes:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}: export_words(rest, Con{(a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32), values})
    case _: List.reverse(&1, U32, values)
def same_words(left: List<U32>, right: List<U32>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{a, ra} Con{b, rb}: U32.is_eq(a, b) && same_words(ra, rb)
    case _ _: False{}
def vector_words(value: J.Surface.Quad, rest: List<U32>) -> List<U32>:
  J.Quad{r, g, b, _} = value
  Con{r, Con{g, Con{b, rest}}}
def rejected_export(wanted: J.Surface.Quad, data: (U32 & U32) & (U32 & List<U32>)) -> Bool:
  match data:
    case Tuple{Tuple{2, 1}, Tuple{9, bytes}}:
      same_words(export_words(bytes, Nil{}), vector_words(J.Quad{F32.bits(0.25), F32.bits(0.5), F32.bits(0.75), 0}, vector_words(wanted, Nil{})))
    case _: False{}
def rejected(wanted: J.Surface.Quad, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Bool:
  match result:
    case Fail{Tuple{image, J.OutOfDomain{}}}: rejected_export(wanted, J.Surface.export(image))
    case _: False{}
def invalid_pixel(component: U32, word: U32) -> J.Surface.Quad:
  match component:
    case 0: J.Quad{word, F32.bits(0.5), F32.bits(0.75), 0}
    case 1: J.Quad{F32.bits(0.25), word, F32.bits(0.75), 0}
    case _: J.Quad{F32.bits(0.25), F32.bits(0.5), word, 0}
def rejection(bits: U32, component: U32) -> Bool:
  +wanted = invalid_pixel(component, bits)
  pixels = Array.set(J.Surface.Quad, Array.new(J.Surface.Quad, 1n, J.Quad{F32.bits(0.25), F32.bits(0.5), F32.bits(0.75), 0}), 1, wanted)
  rejected(wanted, J.Surface.format(J.Surface{2, 1, 9, J.Quads{pixels}}, 7))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def boundaries():
    values={0,0x80000000,1,0x007fffff,0x00800000,0x3f800000}
    for byte in range(256):
        bits=struct.unpack('<I',struct.pack('<f',byte/255.0))[0]
        values.update(v for v in (bits-1,bits,bits+1) if 0<=v<=0x3f800000)
    values=sorted(values)
    return [component for i,value in enumerate(values) for component in (value,values[(i+17)%len(values)],values[(i+53)%len(values)])]


def main():
    probe=probekit.Probe('float-rgb',probekit.arguments(__doc__))
    words=boundaries();count=len(words)//3;invalid=[0x80000001,0xbe800000,0x3f800001,0x7f800000,0xff800000,0x7fc00001,0xffc00001]
    text=probe.native(REFERENCE.replace('WORDS',','.join(map(str,words))));expected=parse_results(text)
    lengths=[8+256*12,8+256*4,8+count*4,8+33024*12,8+33024*4]
    if len(expected)!=5 or [len(row) for row in expected]!=lengths:raise ProbeFailure('Incomplete native float conversion output')
    wanted=expected+[[1] for _ in invalid];probe.report['sources']=source_gate()
    actions=['emit_converted(J.Surface.formatBANG(byte_image(), 9))',
             'emit_surface(to_rgbaBANG(J.Surface.format(byte_image(), 9)))',
             f'emit_surface(J.Surface.formatBANG(boundary_image({bend_bytes(words)}, {count}), 7))',
             'emit_floats(J.Surface.exportBANG(hdr_image()))',
             'emit_surface(J.Surface.formatBANG(hdr_image(), 7))']
    actions+=[f'emit_bytes(~&1, [Bool.to_u32(rejectionBANG({bits}, {index%3}))])' for index,bits in enumerate(invalid)]
    render=lambda selected,gpu:PROGRAM+''.join('    '+line.replace('BANG','!' if gpu else '')+'\n' for line in selected)
    probe.compare(wanted,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)))
    probe.finish(normalized_byte_values=256,boundary_pixels=count,hdr_pixels=33024,rejected_owner_controls=len(invalid),
                 inputs_sha256=hashlib.sha256(json.dumps([words,invalid]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
