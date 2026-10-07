#!/usr/bin/env python3
"""Compare all-format size boundaries and complete raw ImageDither outputs."""
import hashlib
import json
import random

from conformance import source_gate
import probekit
from probekit import ProbeFailure

PROGRAM = '''import Base
import ../../jonlib.bend as J
type Size is Data:
  Size{width: U32, height: U32, format: U32}
def size_value(value: Maybe<&2, U32>) -> U32:
  match value:
    case None{}: 4294967295
    case Some{n}: n
def sizes(input: +List<Size>, values: List<U32>) -> List<U32>:
  match input:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{Size{w, h, format}, rest}: sizes(rest, Con{size_value(J.Pixel.data_size(w, h, format)), values})
def fill(values: +List<U32>, +index: U32, +width: U32, surface: J.Surface) -> J.Surface:
  match values:
    case Nil{}: surface
    case Con{color, rest}: fill(rest, (index + 1 : U32), width, J.Surface.draw_pixel(surface, U32.to_f32((index % width : U32)), U32.to_f32((index / width : U32)), color))
def pairs(bytes: List<U32>) -> List<U32>:
  match bytes:
    case Con{low, Con{high, rest}}: Con{(low + (high << 8n) : U32), pairs(rest)}
    case _: Nil{}
def emit(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((w, h), (format, bytes)) = data
  IO.print("{\\"width\\":" ++ U32.show(w) ++ ",\\"height\\":" ++ U32.show(h) ++ ",\\"format\\":" ++ U32.show(format) ++ ",\\"words\\":" ++ List.show(~&1, ~U32, ~U32.show, pairs(bytes)) ++ "}")
def kept(result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "rejected dithering owner unreadable")
    case Done{colors}: IO.print("{\\"rejected\\":\\"InvalidDitherBits\\",\\"pixels\\":" ++ List.show(~&1, ~U32, ~U32.show, colors) ++ "}")
def created(image: Maybe<J.Surface>, width: U32, values: +List<U32>, r: U32, g: U32, b: U32, a: U32) -> Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>:
  match image:
    case None{}: None{}
    case Some{surface}: Some{J.Surface.dither(fill(values, 0, width, surface), r, g, b, a)}
def calculate(+width: U32, height: U32, values: +List<U32>, r: U32, g: U32, b: U32, a: U32) -> Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>:
  created(J.Surface.create(width, height, 0), width, values, r, g, b, a)
def observed(result: Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "dithering canvas rejected")
    case Some{Done{image}}: emit(J.Surface.export(image))
    case Some{Fail{Tuple{surface, J.InvalidDitherBits{}}}}: kept(J.Surface.colors(surface))
    case Some{Fail{_}}: IO.die(Unit, 1, "dithering request failed")
def main() -> IO(Unit):
  do IO<Unit>:
'''


def fixtures():
    dimensions = [0,1,2,3,4,5,7,8,9,16,31,256,4096]
    sizes = [(w,h,f) for w in dimensions for h in dimensions for f in [*range(26),2147483647]]
    rng = random.Random(0xD17E)
    patterns = [(1,1,[0xffffffff]),(4,1,[0x12345600,0x1234567f,0x12345680,0x123456ff]),
                (1,5,[rng.getrandbits(32) for _ in range(5)]),
                (7,5,[rng.getrandbits(32) for _ in range(35)]),
                (3,3,[0xfaf9f780,0xfdfefc01,0xffffffff]*3),
                (2,2,[0,0xff000000,0x00ff00ff,0x0000ff7f])]
    layouts = [(5,6,5,0),(5,5,5,1),(4,4,4,4),(2,3,4,2),(8,8,0,0),(0,0,0,8),(0,0,0,0)]
    return sizes,[(w,h,pixels,bits) for w,h,pixels in patterns for bits in layouts]


def reference_program(sizes, cases):
    lines = ['#include "raylib.h"','#include <stdio.h>',
             'static const unsigned sizes[][3]={'+','.join('{'+','.join(map(str,entry))+'}' for entry in sizes)+'};',
             'int main(void){SetTraceLogLevel(LOG_NONE);printf("[");',
             'for(unsigned i=0;i<sizeof(sizes)/sizeof(sizes[0]);i++)printf("%s%d",i?",":"",GetPixelDataSize(sizes[i][0],sizes[i][1],sizes[i][2]));',
             'puts("]");']
    for w,h,pixels,bits in cases:
        lines += ['{',f'Image image=GenImageColor({w},{h},BLANK);',
                  'unsigned input[]={'+','.join(str(value)+'u' for value in pixels)+'};',
                  f'for(int i=0;i<{w*h};i++)((Color*)image.data)[i]=GetColor(input[i]);',
                  f'ImageDither(&image,{",".join(map(str,bits))});',
                  'printf("{\\"width\\":%d,\\"height\\":%d,\\"format\\":%d,\\"words\\":[",image.width,image.height,image.format);',
                  f'for(int i=0;i<{w*h};i++)printf("%s%u",i?",":"",((unsigned short*)image.data)[i]);',
                  'puts("]}");UnloadImage(image);','}']
    return '\n'.join(lines+['}'])+'\n'


def main():
    probe = probekit.Probe('pixel',probekit.arguments(__doc__))
    probe.report['sources'] = source_gate()
    sizes,cases = fixtures()
    text = probe.native(reference_program(sizes,cases))
    reference = [json.loads(line) for line in text.splitlines()]
    if len(reference)!=len(cases)+1 or len(reference[0])!=len(sizes):raise ProbeFailure('Incomplete pixel reference results')
    # The candidate prints sizes in 64-entry chunks, then one packed dithering result per case.
    actions = [('sizes',start) for start in range(0,len(sizes),64)]+[('dither',case) for case in cases]
    # Jonlib's dither contract accepts only the three 16-bit layouts raylib names
    # (R5G6B5, R5G5B5A1, R4G4B4A4); for any other bit counts raylib leaves format 0
    # and Jonlib rejects with InvalidDitherBits, returning the owner unchanged.
    dithered = [row if row['format'] else dict(rejected='InvalidDitherBits', pixels=pixels)
                for row,(_,_,pixels,_) in zip(reference[1:],cases)]
    expected = [reference[0][start:start+64] for start in range(0,len(sizes),64)]+dithered

    def render(selected,gpu):
        bang = '!' if gpu else '';body = PROGRAM
        for kind,value in selected:
            if kind=='sizes':
                inputs = ','.join('Size{'+','.join(map(str,row))+'}' for row in sizes[value:value+64])
                body += f'    IO.print(List.show(~&1, ~U32, ~U32.show, sizes{bang}([{inputs}], Nil{{}})))\n'
            else:
                w,h,pixels,bits = value
                body += f'    observed(calculate{bang}({w}, {h}, ['+','.join(map(str,pixels))+'], '+','.join(map(str,bits))+'))\n'
        return body

    probe.compare(expected,probe.candidates(render,actions,batch=len(actions)),
                  describe=lambda index:f'{actions[index][0]} action {index}')
    probe.finish(size_cases=len(sizes),dither_cases=len(cases),packed_words=sum(w*h for w,h,_,_ in cases),
                 inputs_sha256=hashlib.sha256(json.dumps([sizes,cases]).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())

if __name__ == '__main__':
    main()
