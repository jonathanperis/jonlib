#!/usr/bin/env python3
"""Compare every owned RGBA8 mipmap level with native ImageMipmaps."""
import hashlib
import json
import random
import struct

from byte_probe import C_EMITTER, BEND_EMITTER, parse_results
import probekit
from probekit import ROOT, ProbeFailure


def fixtures():
    rng=random.Random(0x6d6970)
    cases=[]
    for width,height in ((1,1),(2,2),(3,5),(7,4),(8,8),(17,9),(1,31),(31,1),(4096,1),(1,4096),(129,257)):
        data=[rng.randrange(256) for _ in range(width*height*4)]
        for i in range(width*height):
            data[4*i+3]=(0,1,127,254,255)[i%5]
        cases.append(dict(width=width,height=height,bytes=data,mutate=False))
    cases += [dict(cases[0],mutate=True),dict(cases[2],mutate=True),dict(cases[5],mutate=True)]
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
def selected(mutate: Bool, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Image.Mipmaps>) -> Maybe<J.Image.Mipmaps>:
  match mutate result:
    case False{} Done{chain}: Some{chain}
    case True{} Done{J.Mipmaps{count, levels}}: Some{J.Mipmaps{count, mark(levels)}}
    case _ Fail{_}: None{}
def calculate(mutate: Bool, image: J.Surface) -> Maybe<J.Image.Mipmaps>:
  selected(mutate, J.Surface.mipmaps(image))
'''+BEND_EMITTER+'''
def emitted(result: U32 & List<J.Surface>) -> IO(Unit):
  (count, levels) = result
  emit_bytes(~&1, level_bytes(levels, word_bytes(4n, count, Nil{})))
def observed(result: Maybe<J.Image.Mipmaps>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "mipmap request rejected")
    case Some{chain}: emitted(J.Image.Mipmaps.entries(chain))
def loaded(mutate: Bool, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "mipmap fixture read failed")
    case Done{image}: observed(calculateBANG(mutate, image))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    probe=probekit.Probe('mipmap',probekit.arguments(__doc__));work=probe.work
    cases=fixtures()
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           C_EMITTER,
           'static void emit(Image image,int mutate){if(!image.data||image.format!=7)exit(3);word(image.mipmaps);int w=image.width,h=image.height;unsigned char *p=image.data;',
           'for(int level=0;level<image.mipmaps;level++){if(mutate&&level==(image.mipmaps>1?1:0)){p[0]=0x12;p[1]=0x34;p[2]=0x56;p[3]=0x78;}',
           'word(w);word(h);for(int i=0;i<w*h*4;i++)byte(p[i]);p+=w*h*4;w=w>1?w/2:1;h=h>1?h/2:1;}end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate(cases):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines += [f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},7,0);if(!image.data)return 2;',
                  f'ImageMipmaps(&image);emit(image,{int(case["mutate"])});}}']
    text=probe.native('\n'.join(lines+['}'])+'\n');expected=parse_results(text)
    if len(expected)!=len(cases):raise ProbeFailure('Incomplete native mipmap output')
    for case,row in zip(cases,expected):
        levels=shapes(case['width'],case['height']);payload=bytes(row)
        if struct.unpack_from('<I',payload)[0]!=len(levels):raise ProbeFailure('Native mipmap count differs')
        at=4
        for width,height in levels:
            if struct.unpack_from('<II',payload,at)!=(width,height):raise ProbeFailure('Native mipmap dimensions differ')
            at+=8+width*height*4
        if at!=len(payload):raise ProbeFailure('Incomplete native mipmap pixels')

    def render(selected,gpu):
        body=PROGRAM.replace('BANG','!' if gpu else '')
        for i,case in selected:
            path=json.dumps(str((work/(str(i)+'.raw')).relative_to(ROOT)))
            body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw({path}, {case["width"]}, {case["height"]}, 7, 0), loaded({"True" if case["mutate"] else "False"}{{}}))\n'
        return body

    actions=list(enumerate(cases))
    probe.compare(expected,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)))
    probe.finish(native_cases=len(cases),levels=sum(len(shapes(c['width'],c['height'])) for c in cases),
                 pixels=sum(w*h for c in cases for w,h in shapes(c['width'],c['height'])),mutated_chain_controls=sum(c['mutate'] for c in cases),
                 inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
