#!/usr/bin/env python3
"""Compare native default RGBA8 Gaussian blur and rejected source owners."""
import hashlib
import json
import random
import struct

from byte_probe import BEND_EMITTER, parse_results
import probekit
from probekit import ROOT, ProbeFailure


def fixtures():
    rng=random.Random(0x626c7572);cases=[]
    for width,height in ((1,1),(1,17),(19,1),(2,3),(7,5),(17,13),(4096,1),(1,4096),(129,257)):
        data=[rng.randrange(256) for _ in range(width*height*4)]
        for i in range(width*height):data[4*i+3]=(0,1,2,127,254,255)[i%6]
        for size in sorted({0,1,min(width,height)}):
            cases.append(dict(width=width,height=height,bytes=data,size=size,repeats=1,reject=False))
    for color in ([231,19,153,0],[255,255,255,255],[213,97,51,1]):
        cases.append(dict(width=8,height=8,bytes=color*64,size=3,repeats=1,reject=False))
    impulse=[0]*140;impulse[4*17:4*18]=[255,127,63,255]
    cases.append(dict(width=7,height=5,bytes=impulse,size=2,repeats=1,reject=False))
    cases.append(dict(cases[13],size=2,repeats=2))
    controls=[dict(width=width,height=height,bytes=[213,97,51,127,255,1,17,1]*3,size=size,repeats=1,reject=True)
              for width,height,size in ((3,2,3),(2,3,3),(3,2,4294967295))]
    return cases,controls


PROGRAM='''import Base
import ../../jonlib.bend as J
def word_bytes(n: Nat, +word: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def rgba(pixels: List<U32>, values: List<U32>) -> List<U32>:
  match pixels:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{+color, rest}: rgba(rest, Con{J.Color.alpha(color), Con{J.Color.blue(color), Con{J.Color.green(color), Con{J.Color.red(color), values}}}})
def repeat(n: Nat, +size: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  match n result:
    case 0n _: result
    case _ Fail{error}: Fail{error}
    case 1n+rest Done{surface}: repeat(rest, size, J.Surface.blur_gaussian(surface, size))
def calculate(repeats: Nat, size: U32, image: J.Surface) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  repeat(repeats, size, Done{image})
'''+BEND_EMITTER+'''
def emit_colors(+width: U32, +height: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "blur colors unavailable")
    case Done{colors}: emit_bytes(~&1, rgba(colors, word_bytes(4n, height, word_bytes(4n, width, Nil{}))))
def emit_surface(surface: J.Surface) -> IO(Unit):
  J.Surface{+width, +height, format, pixels} = surface
  emit_colors(width, height, J.Surface.colors(J.Surface{width, height, format, pixels}))
def observed(reject: Bool, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> IO(Unit):
  match reject result:
    case False{} Done{surface}: emit_surface(surface)
    case True{} Fail{Tuple{surface, J.InvalidSize{}}}: emit_surface(surface)
    case _ _: IO.die(Unit, 1, "blur acceptance or retained owner differs")
def loaded(reject: Bool, repeats: Nat, size: U32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "blur fixture read failed")
    case Done{image}: observed(reject, calculateBANG(repeats, size, image))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    probe=probekit.Probe('blur',probekit.arguments(__doc__));work=probe.work
    cases,controls=fixtures();all_cases=cases+controls
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\\"end\\\"");}',
           'static void emit(Image image){if(!image.data||image.format!=7)exit(3);word(image.width);word(image.height);for(int i=0;i<image.width*image.height*4;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate(all_cases):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},7,0);if(!image.data)return 2;')
        if not case['reject']:lines.append(f'for(int i=0;i<{case["repeats"]};i++)ImageBlurGaussian(&image,{case["size"]});')
        lines.append('emit(image);}')
    text=probe.native('\n'.join(lines+['}'])+'\n');expected=parse_results(text)
    if len(expected)!=len(all_cases):raise ProbeFailure('Incomplete native blur output')
    for case,row in zip(all_cases,expected):
        if row[:8]!=list(struct.pack('<II',case['width'],case['height'])) or len(row)!=8+len(case['bytes']):raise ProbeFailure('Native blur shape differs')

    def render(selected,gpu):
        body=PROGRAM.replace('BANG','!' if gpu else '')
        for i,case in selected:
            path=json.dumps(str((work/(str(i)+'.raw')).relative_to(ROOT)))
            body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw({path}, {case["width"]}, {case["height"]}, 7, 0), loaded({"True" if case["reject"] else "False"}{{}}, {case["repeats"]}n, {case["size"]}))\n'
        return body

    actions=list(enumerate(all_cases))
    probe.compare(expected,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)))
    probe.finish(native_cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),retained_owner_controls=len(controls),
                 inputs_sha256=hashlib.sha256(json.dumps(all_cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
