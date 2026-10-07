#!/usr/bin/env python3
"""Compare every owned mipmap level with native ImageMipmaps on pixel formats 1..9.

R8G8B8A8 runs the full corpus; other formats convert a smaller set with
ImageFormat first, so each level also follows that format's ImageResize path."""
import hashlib
import json
import random
import struct

from byte_probe import C_EMITTER, BEND_EMITTER, parse_results
import probekit
from probekit import ROOT, ProbeFailure


FORMATS = range(1, 10)
OTHER_FORMAT_CASES = (0, 1, 2, 3, 5, 6, 7)  # 1x1, 2x2, 3x5, 7x4, 17x9, 1x31, 31x1
BYTES = {1: 1, 2: 2, 3: 2, 4: 3, 5: 2, 6: 2, 7: 4, 8: 4, 9: 12}


def fixtures():
    rng=random.Random(0x6d6970)
    cases=[]
    for width,height in ((1,1),(2,2),(3,5),(7,4),(8,8),(17,9),(1,31),(31,1),(4096,1),(1,4096),(129,257)):
        data=[rng.randrange(256) for _ in range(width*height*4)]
        for i in range(width*height):
            data[4*i+3]=(0,1,127,254,255)[i%5]
        cases.append(dict(width=width,height=height,bytes=data,mutate=False,format=7))
    cases += [dict(cases[0],mutate=True),dict(cases[2],mutate=True),dict(cases[5],mutate=True)]
    for fmt in FORMATS:
        if fmt == 7:
            continue
        cases += [dict(cases[i],format=fmt) for i in OTHER_FORMAT_CASES]
        cases.append(dict(cases[2],format=fmt,mutate=True))
    return cases


def shapes(width,height):
    result=[(width,height)]
    while (width,height)!=(1,1):
        width=max(1,width//2);height=max(1,height//2);result.append((width,height))
    return result


PROGRAM='''import Base
import ../../jonlib.bend as J
def word_bytes(n: Nat, +word: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def pushed(bytes: List<U32>, values: List<U32>) -> List<U32>:
  match bytes:
    case Nil{}: values
    case Con{byte, rest}: pushed(rest, Con{byte, values})
def level_data(data: (U32 & U32) & (U32 & List<U32>), values: List<U32>) -> List<U32>:
  ((width, height), (_, bytes)) = data
  pushed(bytes, word_bytes(4n, height, word_bytes(4n, width, values)))
def level_bytes(levels: List<J.Surface>, values: List<U32>) -> List<U32>:
  match levels:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{level, rest}: level_bytes(rest, level_data(J.Surface.export(level), values))
def mark(levels: List<J.Surface>) -> List<J.Surface>:
  match levels:
    case Con{first, Nil{}}: Con{J.Surface.draw_pixel(first, 0.0, 0.0, 305419896), Nil{}}
    case Con{first, Con{second, rest}}: Con{first, Con{J.Surface.draw_pixel(second, 0.0, 0.0, 305419896), rest}}
    case Nil{}: Nil{}
def selected(mutate: Bool, chain: J.Image.Mipmaps) -> J.Image.Mipmaps:
  match mutate chain:
    case False{} _: chain
    case True{} J.Mipmaps{count, levels}: J.Mipmaps{count, mark(levels)}
def calculate(mutate: Bool, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Maybe<J.Image.Mipmaps>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{selected(mutate, J.Surface.mipmaps(image))}
'''+BEND_EMITTER+'''
def emitted(result: U32 & List<J.Surface>) -> IO(Unit):
  (count, levels) = result
  emit_bytes(~&1, level_bytes(levels, word_bytes(4n, count, Nil{})))
def observed(result: Maybe<J.Image.Mipmaps>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "mipmap request rejected")
    case Some{chain}: emitted(J.Image.Mipmaps.entries(chain))
def loaded(mutate: Bool, +format: U32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "mipmap fixture read failed")
    case Done{image}: observed(calculateBANG(mutate, J.Surface.format(image, format)))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    probe=probekit.Probe('mipmap',probekit.arguments(__doc__));work=probe.work
    cases=fixtures()
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           C_EMITTER,
           # A mutated chain gets ImageDrawPixel(0,0) on its second level (or the only one).
           'static void emit(Image image,int format,int mutate){if(!image.data||image.format!=format)exit(3);word(image.mipmaps);int w=image.width,h=image.height;unsigned char *p=image.data;',
           'for(int level=0;level<image.mipmaps;level++){int n=GetPixelDataSize(w,h,format);if(mutate&&level==(image.mipmaps>1?1:0)){Image l={p,w,h,1,format};ImageDrawPixel(&l,0,0,(Color){0x12,0x34,0x56,0x78});}',
           'word(w);word(h);for(int i=0;i<n;i++)byte(p[i]);p+=n;w=w>1?w/2:1;h=h>1?h/2:1;}end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate(cases):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines += [f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},7,0);if(!image.data)return 2;',
                  f'ImageFormat(&image,{case["format"]});ImageMipmaps(&image);emit(image,{case["format"]},{int(case["mutate"])});}}']
    text=probe.native('\n'.join(lines+['}'])+'\n');expected=parse_results(text)
    if len(expected)!=len(cases):raise ProbeFailure('Incomplete native mipmap output')
    for case,row in zip(cases,expected):
        levels=shapes(case['width'],case['height']);payload=bytes(row)
        if struct.unpack_from('<I',payload)[0]!=len(levels):raise ProbeFailure('Native mipmap count differs')
        at=4
        for width,height in levels:
            if struct.unpack_from('<II',payload,at)!=(width,height):raise ProbeFailure('Native mipmap dimensions differ')
            at+=8+width*height*BYTES[case['format']]
        if at!=len(payload):raise ProbeFailure('Incomplete native mipmap pixels')

    def render(selected,gpu):
        body=PROGRAM.replace('BANG','!' if gpu else '')
        for i,case in selected:
            path=json.dumps(str((work/(str(i)+'.raw')).relative_to(ROOT)))
            body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw({path}, {case["width"]}, {case["height"]}, 7, 0), loaded({"True" if case["mutate"] else "False"}{{}}, {case["format"]}))\n'
        return body

    actions=list(enumerate(cases))
    probe.compare(expected,probe.candidates(render,actions,batch=24,parse=lambda text,selected:parse_results(text)),
                  describe=lambda i:f'{cases[i]["width"]}x{cases[i]["height"]} format {cases[i]["format"]}{" mutated" if cases[i]["mutate"] else ""}')
    probe.finish(native_cases=len(cases),formats=len(FORMATS),levels=sum(len(shapes(c['width'],c['height'])) for c in cases),
                 pixels=sum(w*h for c in cases for w,h in shapes(c['width'],c['height'])),mutated_chain_controls=sum(c['mutate'] for c in cases),
                 inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
