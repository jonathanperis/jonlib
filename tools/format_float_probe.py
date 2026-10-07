#!/usr/bin/env python3
"""Compare native byte/packed image normalization to RGB floats and return chains."""
import hashlib
import json
import struct

from bmp_probe import bend_bytes
from byte_probe import C_EMITTER, BEND_EMITTER, parse_results
from conformance import ROOT, source_gate
import probekit
from probekit import ProbeFailure

PRELUDE = ['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           C_EMITTER,
           'static void emit(Image image){if(!image.data)exit(2);word(image.width);word(image.height);word(image.format);',
           'int size=GetPixelDataSize(image.width,image.height,image.format);for(int i=0;i<size;i++)byte(((unsigned char*)image.data)[i]);end();}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
PROGRAM = '''import Base
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
def normalized(result: Maybe<J.Surface>) -> Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Surface.format(image, 9)}
def observed(result: Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>) -> IO(Unit):
  match result:
    case Some{Done{image}}: formatted(J.Surface.export(image))
    case _: IO.die(Unit, 1, "normalization source rejected")
def returned(target: U32, result: Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>) -> Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>:
  match result:
    case Some{Done{image}}: Some{J.Surface.format(image, target)}
    case _: None{}
def roundtrip(target: U32, result: Maybe<J.Surface>) -> Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>:
  returned(target, normalized(result))
def observed_chain(result: Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>) -> IO(Unit):
  match result:
    case Some{Done{image}}: formatted(J.Surface.export(image))
    case _: IO.die(Unit, 1, "normalization return chain rejected")
def main() -> IO(Unit):
  do IO<Unit>:
'''


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


def reference_program(cases,work):
    lines=list(PRELUDE)
    for case in cases:
        path=work/(str(case['format'])+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},16,16,{case["format"]},0);ImageFormat(&image,9);emit(image);ImageFormat(&image,{case["format"]});emit(image);UnloadImage(image);}}')
    return '\n'.join(lines+['}'])+'\n'


def main():
    probe=probekit.Probe('format-float',probekit.arguments(__doc__))
    cases=fixtures();text=probe.native(reference_program(cases,probe.work));expected=parse_results(text)
    if len(expected)!=len(cases)*2:raise ProbeFailure('Incomplete native float normalization output')
    for i,case in enumerate(cases):
        for target,row,size in ((9,expected[2*i],3072),(case['format'],expected[2*i+1],len(case['bytes']))):
            if row[:12]!=list(struct.pack('<III',16,16,target)) or len(row)!=12+size:raise ProbeFailure('Native normalization shape differs')
    probe.report['sources']=source_gate();actions=[]
    for case in cases:
        image=f'J.Surface.from_bytes(16, 16, {case["format"]}, {bend_bytes(case["bytes"])})'
        actions+=[f'observed(normalizedBANG({image}))',f'observed_chain(roundtripBANG({case["format"]}, {image}))']
    render=lambda selected,gpu:PROGRAM+''.join('    '+line.replace('BANG','!' if gpu else '')+'\n' for line in selected)
    probe.compare(expected,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)))
    probe.finish(source_formats=7,pixels=1792,native_results=len(expected),
                 inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
