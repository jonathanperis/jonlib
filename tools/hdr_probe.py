#!/usr/bin/env python3
"""Compare Radiance RGBE images and every channel/exponent pair as exact F32 bits."""
import hashlib
import json

from bmp_probe import bend_bytes
from byte_probe import C_EMITTER, BEND_EMITTER, parse_results
import probekit
from probekit import ProbeFailure


def hdr(width,height,samples,*,signature=b'#?RADIANCE',metadata=b'',dimensions=None):
    line=f'-Y {height} +X {width}'.encode() if dimensions is None else dimensions
    return list(signature+b'\n'+metadata+b'FORMAT=32-bit_rle_rgbe\n\n'+line+b'\n'+bytes(samples))


def rle_hdr(width,height,samples,*,literal=False):
    data=hdr(width,height,[])
    for y in range(height):
        data.extend((2,2,width>>8,width&255))
        for channel in range(4):
            values=samples[(y*width)*4+channel:(y+1)*width*4:4];at=0
            while at<width:
                end=at+1
                while end<min(width,at+127) and values[end]==values[at]:end+=1
                if not literal and end-at>=2:data.extend((128+end-at,values[at]));at=end
                else:
                    end=min(width,at+128);data.extend([end-at,*values[at:end]]);at=end
    return data


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
    for width in (8,9,127,128,129,256,4096):
        values=[v for y in range(2) for x in range(width) for v in
                (y+1 if x<width//2 else x&255,x&255,(x//5)&255,255 if y else (0,1,9,10,128,136,254,255)[x%8])]
        inputs.append(dict(id=f'rle-mixed-{width}',bytes=rle_hdr(width,2,values)))
    inputs.append(dict(id='rle-literal128',bytes=rle_hdr(128,1,[1,2,3,1]*128,literal=True)))
    for prior_rows in (1,2):
        width=8;height=prior_rows+1
        encoded=rle_hdr(width,prior_rows,[200,201,202,136]*(width*prior_rows))
        encoded=encoded[len(hdr(width,prior_rows,[])):]
        raw=[v for i in range(width*height) for v in (i+1,i+2,i+3,(i*11)&255)]
        for high_bit in (False,True):
            replacement=raw.copy()
            if high_bit:replacement[:4]=[2,2,128,136]
            inputs.append(dict(id=f'later-raw-reset-{prior_rows}-{high_bit}',bytes=hdr(width,height,encoded+replacement)+[1,2,3]))
    base=hdr(1,1,[1,2,3,128])
    malformed=[dict(id='empty',bytes=[],error=0),dict(id='byte',bytes=[*base,256],error=1),
               dict(id='signature',bytes=hdr(1,1,[1,2,3,128],signature=b'#?RADIANCEX'),error=0),
               dict(id='no-format',bytes=list(b'#?RGBE\n\n-Y 1 +X 1\n\1\2\3\x80'),error=0),
               dict(id='truncated-sample',bytes=base[:-1],error=3),
               dict(id='rle-no-packets',bytes=hdr(8,1,[2,2,0,8]),error=3),
               dict(id='long-line',bytes=hdr(1,1,[1,2,3,128],metadata=b'x'*1024+b'\n'),error=0),
               dict(id='zero-width',bytes=hdr(0,1,[]),error=2),dict(id='large-height',bytes=hdr(1,4097,[]),error=2)]
    for name,line in [('orientation',b'+Y 1 +X 1'),('overflow',b'-Y 1 +X 4294967296'),('missing-width',b'-Y 1 +X'),('negative',b'-Y -1 +X 1')]:
        malformed.append(dict(id=name,bytes=hdr(1,1,[1,2,3,128],dimensions=line),error=0))
    for name,bytes_,error in [('wrong-width',[2,2,0,9],4),('zero-control',[2,2,0,8,0],4),
                            ('repeat-overrun',[2,2,0,8,137,1],4),('literal-overrun',[2,2,0,8,9,*range(9)],4),
                            ('short-repeat',[2,2,0,8,129],3),('short-literal',[2,2,0,8,8,*range(7)],3)]:
        malformed.append(dict(id='rle-'+name,bytes=hdr(8,1,bytes_),error=error))
    prefix=hdr(8,2,[]);first=[2,2,0,8,136,1,136,2,136,3,136,128]
    malformed += [dict(id='rle-short-next-header',bytes=prefix+first+[2,2,0],error=3),
                  dict(id='rle-later-fallback-short-canvas',bytes=prefix+first+[0,1,2,3]*8,error=3)]
    return inputs,malformed


def reference_program(inputs):
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',
           C_EMITTER,
           'static Image load(const unsigned char *data,int size){Image image=LoadImageFromMemory(".hdr",data,size);if(!image.data||image.format!=PIXELFORMAT_UNCOMPRESSED_R32G32B32)exit(2);return image;}',
           'static void emit(const unsigned char *data,int size){Image image=load(data,size);word(image.width);word(image.height);for(int i=0;i<image.width*image.height*3;i++){unsigned bits;memcpy(&bits,(float*)image.data+i,4);word(bits);}end();UnloadImage(image);}',
           'static void pairs(void){const char header[]="#?RGBE\\nFORMAT=32-bit_rle_rgbe\\n\\n-Y 256 +X 256\\n";',
           'int prefix=sizeof(header)-1,size=prefix+65536*4;unsigned char *data=malloc(size);if(!data)exit(3);memcpy(data,header,prefix);',
           'for(unsigned e=0;e<256;e++)for(unsigned c=0;c<256;c++){unsigned char *p=data+prefix+4*(e*256+c);p[0]=p[1]=p[2]=c;p[3]=e;}',
           'Image image=load(data,size);for(int i=0;i<65536;i++){unsigned a,b,c;memcpy(&a,(float*)image.data+3*i,4);memcpy(&b,(float*)image.data+3*i+1,4);memcpy(&c,(float*)image.data+3*i+2,4);if(a!=b||a!=c)exit(4);word(a);}end();UnloadImage(image);free(data);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in inputs:lines.append('{unsigned char data[]={'+','.join(map(str,case['bytes']))+'};emit(data,sizeof(data));}')
    return '\n'.join(lines+['pairs();}'])+'\n'


PROGRAM='''import Base
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
'''+BEND_EMITTER+'''
def emit_image(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match data:
    case Tuple{Tuple{width, height}, Tuple{9, bytes}}: emit_bytes(~&1, List.append(&1, U32, header(width, height), bytes))
    case _: IO.die(Unit, 1, "HDR pixel format changed")
def observed(result: Result<&1, &1, J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid HDR rejected")
    case Done{image}: emit_image(J.Surface.export(image))
def error_code(result: Result<&1, &1, J.Surface.Error, J.Surface>) -> U32:
  match result:
    case Done{_}: 99
    case Fail{J.InvalidImageHeader{}}: 0
    case Fail{J.InvalidImageByte{}}: 1
    case Fail{J.UnsupportedImageSize{}}: 2
    case Fail{J.TruncatedImageData{}}: 3
    case Fail{J.InvalidImageStream{}}: 4
    case Fail{_}: 98
def channels(n: Nat, +channel: U32, +exponent: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: channels(rest, (channel + 1 : U32), exponent, word_bytes(4n, F32.bits(H.sample(channel, exponent)), values))
def exponents(n: Nat, +exponent: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: List.reverse(&1, U32, values)
    case 1n+rest: exponents(rest, (exponent + 1 : U32), channels(256n, 0, exponent, values))
# Surface owners have no unload call: consuming the decoded owner disposes it.
def consumed(size: U32 & U32) -> U32:
  1
def disposed(result: Result<&1, &1, J.Surface.Error, J.Surface>) -> U32:
  match result:
    case Fail{_}: 0
    case Done{image}: consumed(J.Surface.dimensions(image))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    probe=probekit.Probe('hdr',probekit.arguments(__doc__));inputs,malformed=fixtures()
    text=probe.native(reference_program(inputs));expected=parse_results(text)
    if len(expected)!=len(inputs)+1 or len(expected[-1])!=65536*4:raise ProbeFailure('Incomplete native HDR results')
    pixels=0
    for row in expected[:-1]:
        width=int.from_bytes(bytes(row[:4]),'little');height=int.from_bytes(bytes(row[4:8]),'little')
        if len(row)!=8+width*height*12:raise ProbeFailure('Native HDR channel count differs')
        pixels+=width*height
    wanted=expected[:-1]+[[c['error']] for c in malformed]+[expected[-1],[1]]
    actions=[('image',c) for c in inputs]+[('error',c) for c in malformed]+[('pairs',dict(id='channel-exponent-pairs')),('disposed',dict(id='ownership'))]

    def render(selected,gpu):
        bang='!' if gpu else '';body=PROGRAM
        for kind,case in selected:
            if kind=='image':body+=f'    observed(J.Surface.decode_hdr{bang}({bend_bytes(case["bytes"])}))\n'
            elif kind=='error':body+=f'    emit_bytes(~&1, [error_code(J.Surface.decode_hdr{bang}({bend_bytes(case["bytes"])}))])\n'
            elif kind=='pairs':body+=f'    emit_bytes(~&1, exponents{bang}(256n, 0, Nil{{}}))\n'
            else:body+=f'    emit_bytes(~&1, [disposed{bang}(J.Surface.decode_hdr({bend_bytes(inputs[0]["bytes"])}))])\n'
        return body

    probe.compare(wanted,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)),
                  lambda i:f'{actions[i][0]} {actions[i][1]["id"]}')
    probe.finish(images=len(inputs),pixels=pixels,error_controls=len(malformed),channel_exponent_pairs=65536,ownership_controls=1,
                 inputs_sha256=hashlib.sha256(json.dumps([inputs,malformed]).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
