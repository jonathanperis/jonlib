#!/usr/bin/env python3
"""Compare direct float format conversion and grayscale at rounding boundaries."""
import hashlib
import json
import math
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import ROOT, source_gate
import probekit
from probekit import ProbeFailure

PRELUDE = ['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
           'static void emit(Image image){if(!image.data)exit(2);word(image.width);word(image.height);word(image.format);',
           'int size=GetPixelDataSize(image.width,image.height,image.format);for(int i=0;i<size;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
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
# expected: 99 accepted (target 0 and the current format keep the owner), 2 OutOfDomain owner.
def selected(expected: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> IO(Unit):
  match expected result:
    case 99 Done{image}: formatted(J.Surface.export(image))
    case 2 Fail{Tuple{image, J.OutOfDomain{}}}: formatted(J.Surface.export(image))
    case _ _: IO.die(Unit, 1, "direct conversion acceptance/error/owner differs")
def converted(target: U32, result: Maybe<J.Surface>) -> Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>:
  match target result:
    case _ None{}: None{}
    case 1 Some{image}: Some{J.Surface.color_grayscale(image)}
    case _ Some{image}: Some{J.Surface.format(image, target)}
def observed(expected: U32, result: Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid direct-format source rejected")
    case Some{value}: selected(expected, value)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def f32(value):return struct.unpack('<f',struct.pack('<f',value))[0]
def bits(value):return struct.unpack('<I',struct.pack('<f',value))[0]


def fixtures():
    values={0,0x80000000,1,0x007fffff,0x3f800000,0x3d088888,0x3c020820}
    for limit in (15,31,63):
        for level in range(limit):
            center=bits((level+0.5)/limit)
            values.update(word for word in range(center-2,center+3) if 0<=word<=0x3f800000)
    values=sorted(values);words=[v for i,r in enumerate(values) for v in (r,values[(i+7)%len(values)],values[(i+19)%len(values)])]
    packed=dict(width=len(values),height=1,bytes=list(struct.pack('<'+'I'*len(words),*words)))
    cases=[dict(packed,target=target) for target in range(1,8)]
    seed=0xabcdef;gray=[]
    for i in range(1024):
        seed=(seed*1664525+1013904223)&0xffffffff;r=f32((seed>>8)/16777215)
        seed=(seed*1664525+1013904223)&0xffffffff;g=f32((seed>>8)/16777215)
        base=r*f32(0.299)+g*f32(0.587);lo=math.ceil(base*255);hi=math.floor((base+f32(0.114))*255)
        seed=(seed*1664525+1013904223)&0xffffffff;target=lo+seed%(hi-lo+1)
        word=bits((target/255-base)/f32(0.114))
        if 3<word<0x3f7ffffc:word+=i%7-3
        gray.extend((bits(r),bits(g),word))
    gray_data=list(struct.pack('<'+'I'*len(gray),*gray))
    cases += [dict(width=32,height=32,bytes=gray_data,target=target) for target in (1,2)]
    original=list(struct.pack('<fff',0.5,0.25,0.75))
    cases.append(dict(width=1,height=1,bytes=original,target=8))
    # ImageFormat with format 0 or the current format leaves the image unchanged.
    cases += [dict(width=1,height=1,bytes=original,target=target) for target in (0,9)]
    controls=[dict(width=1,height=1,bytes=list(struct.pack('<fff',2.0,0.5,0.75)),target=3,error=2)]
    return cases,controls


def reference_program(cases,controls,work):
    lines=list(PRELUDE)
    for i,case in enumerate([*cases,*controls]):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},PIXELFORMAT_UNCOMPRESSED_R32G32B32,0);')
        if i<len(cases):lines.append('ImageColorGrayscale(&image);' if case['target']==1 else f'ImageFormat(&image,{case["target"]});')
        lines.append('emit(image);}')
    return '\n'.join(lines+['}'])+'\n'


def check_reference(cases,controls,expected):
    """Independently confirm native metadata and that the retained packed-rounding counterexamples still separate round from add-half."""
    sizes={1:1,2:2,3:2,4:3,5:2,6:2,7:4,8:4,9:12}
    for i,(case,row) in enumerate(zip([*cases,*controls],expected)):
        target=(case['target'] or 9) if i<len(cases) else 9
        if row[:12]!=list(struct.pack('<III',case['width'],case['height'],target)) or len(row)!=12+case['width']*case['height']*sizes[target]:raise ProbeFailure('Native format metadata differs')
    for word,limit,target,component,shift in ((0x3d088888,15,6,0,12),(0x3c020820,63,3,1,5)):
        case=cases[target-1];data=bytes(case['bytes']);index=next(i for i in range(case['width']) if struct.unpack_from('<I',data,i*12+component*4)[0]==word)
        native=(int.from_bytes(bytes(expected[target-1][12+index*2:14+index*2]),'little')>>shift)&limit
        value=struct.unpack('<f',struct.pack('<I',word))[0];old=math.floor(f32(f32(value*limit)+0.5))
        if native!=0 or old!=1:raise ProbeFailure('Packed rounding fixture no longer distinguishes native round from add-half')


def main():
    probe=probekit.Probe('float-rgb-formats',probekit.arguments(__doc__))
    cases,controls=fixtures();text=probe.native(reference_program(cases,controls,probe.work));expected=parse_results(text)
    if len(expected)!=len(cases)+len(controls):raise ProbeFailure('Incomplete native direct-format results')
    check_reference(cases,controls,expected);probe.report['sources']=source_gate()
    actions=[f'observed({case.get("error",99)}, convertedBANG({case["target"]}, J.Surface.from_bytes({case["width"]}, {case["height"]}, 9, {bend_bytes(case["bytes"])})))'
             for case in [*cases,*controls]]
    render=lambda selected,gpu:PROGRAM+''.join('    '+line.replace('BANG','!' if gpu else '')+'\n' for line in selected)
    probe.compare(expected,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)))
    probe.finish(native_cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),retained_owner_controls=len(controls),
                 packed_boundary_values=cases[0]['width'],gray_boundary_pixels=1024,packed_rounding_regressions=2,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
