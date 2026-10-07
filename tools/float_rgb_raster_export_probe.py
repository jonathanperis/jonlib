#!/usr/bin/env python3
"""Compare native RGB float BMP/TGA file bytes, pixels and writer ownership."""
import hashlib
import json
import struct

from bmp_probe import bend_bytes
from byte_probe import C_EMITTER, BEND_EMITTER, parse_results
from conformance import ROOT, source_gate
from float_rgb_png_probe import fixtures as png_fixtures, parse_lane
import probekit
from probekit import ProbeFailure

PRELUDE = ['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',
           C_EMITTER,
           'static void emit(unsigned char *data,int size){for(int i=0;i<size;i++)byte(data[i]);end();}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
def rgba(values: List<U32>, bytes: List<U32>) -> List<U32>:
  match values:
    case Nil{}: List.reverse(&1, U32, bytes)
    case Con{+color, rest}: rgba(rest, Con{J.Color.alpha(color), Con{J.Color.blue(color), Con{J.Color.green(color), Con{J.Color.red(color), bytes}}}})
'''+BEND_EMITTER+'''
def encode(bmp: Bool, image: J.Surface) -> Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>:
  match bmp:
    case True{}: J.Surface.to_bmp(image)
    case False{}: J.Surface.to_tga(image)
def exported(result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> Maybe<&2, +List<U32>>:
  match result:
    case Fail{_}: None{}
    case Done{bytes}: Some{bytes}
def calculate(bmp: Bool, result: Maybe<J.Surface>) -> Maybe<&2, +List<U32>>:
  match result:
    case None{}: None{}
    case Some{image}: exported(encode(bmp, image))
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "float raster dimensions/owner differ")
def decode(bmp: Bool, bytes: +List<U32>) -> Result<&1, &1, J.Surface.Error, J.Surface>:
  match bmp:
    case True{}: J.Surface.decode_bmp(bytes)
    case False{}: J.Surface.decode_tga(bytes)
def colors(width: U32, height: U32, +w: U32, +h: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "decoded float raster colors rejected")
    case Done{values}:
      do IO<Unit>:
        checked(U32.is_eq(width, w) && U32.is_eq(height, h))
        emit_bytes(~&1, rgba(values, Nil{}))
def decoded(width: U32, height: U32, result: Result<&1, &1, J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "float raster round trip failed")
    case Done{J.Surface{+w, +h, format, pixels}}: colors(width, height, w, h, J.Surface.colors(J.Surface{w, h, format, pixels}))
def observed(bmp: Bool, width: U32, height: U32, result: Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid float raster encoding rejected")
    case Some{+bytes}:
      do IO<Unit>:
        emit_bytes(~&2, bytes)
        decoded(width, height, decodeBANG(bmp, bytes))
def write(bmp: Bool, image: J.Surface, path: String) -> IO(Result<&1, &1, J.Surface.IOError, Unit>):
  match bmp:
    case True{}: J.Surface.write_bmp(image, path)
    case False{}: J.Surface.write_tga(image, path)
def write_ok(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "valid float raster write failed")
def save(bmp: Bool, path: String, result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "raster file source rejected")
    case Some{image}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, write(bmp, image, path), write_ok)
def small(value: F32) -> J.Surface:
  J.Surface{1, 1, 9, J.Vectors{Array.new(M.Vector3, 0n, M.Vector3{value, 0.25, 0.75})}}
def owner_entries(data: (U32 & U32) & (U32 & List<U32>)) -> Bool:
  match data:
    case Tuple{Tuple{1, 1}, Tuple{9, Con{0, Con{0, Con{0, Con{64, Con{0, Con{0, Con{128, Con{62, Con{0, Con{0, Con{64, Con{63, Nil{}}}}}}}}}}}}}}}: True{}
    case _: False{}
def rejected(result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> Bool:
  match result:
    case Fail{Tuple{image, J.OutOfDomain{}}}: owner_entries(J.Surface.export(image))
    case _: False{}
def rejected_write(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.SourceError{image, J.OutOfDomain{}}}: checked(owner_entries(J.Surface.export(image)))
    case _: IO.die(Unit, 1, "raster write rejection lost owner")
def failed_write(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FileError{_, _}}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "raster file error kind differs")
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: emit_bytes(~&1, [1])
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, write(True{}, small(0.5), OUTPUT_BMP), write_ok)
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, write(False{}, small(0.5), OUTPUT_TGA), write_ok)
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, write(True{}, small(2.0), SENTINEL), rejected_write)
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, write(False{}, small(2.0), SENTINEL), rejected_write)
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, write(True{}, small(0.5), DIRECTORY), failed_write)
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, write(False{}, small(0.5), DIRECTORY), failed_write)
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def fixtures():
    images=[case for case in png_fixtures() if case['file']]
    values=[v for y in range(2) for x in range(129) for v in ((0.25 if x<128 else 0.5),y*0.5,0.75)]
    images.append(dict(id='run-boundary',width=129,height=2,bytes=list(struct.pack('<'+'f'*len(values),*values))))
    return [dict(image,codec=codec) for codec in ('bmp','tga') for image in images]


def reference_program(cases,work):
    lines=list(PRELUDE)
    for case in cases:
        path=work/(case['id']+'.raw');path.write_bytes(bytes(case['bytes']));output=work/('reference-'+case['id']+'.'+case['codec'])
        lines += [f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},9,0);if(!image.data)return 2;',
                  f'if(!ExportImage(image,{json.dumps(str(output.relative_to(ROOT)))}))return 3;int n=0;unsigned char *file=LoadFileData({json.dumps(str(output.relative_to(ROOT)))},&n);if(!file)return 4;emit(file,n);',
                  f'Image decoded=LoadImageFromMemory(".{case["codec"]}",file,n);if(!decoded.data||decoded.width!=image.width||decoded.height!=image.height)return 5;ImageFormat(&decoded,7);',
                  'Color *colors=LoadImageColors(image);int size=image.width*image.height*4;if(!colors||memcmp(decoded.data,colors,size))return 6;emit(decoded.data,size);',
                  'UnloadImageColors(colors);UnloadImage(decoded);UnloadImage(image);UnloadFileData(file);}']
    return '\n'.join(lines+['}'])+'\n'


def main():
    probe=probekit.Probe('float-rgb-raster-export',probekit.arguments(__doc__))
    work=probe.work;cases=fixtures();text=probe.native(reference_program(cases,work));expected=parse_results(text)
    if len(expected)!=2*len(cases):raise ProbeFailure('Incomplete native float raster export')
    if any(len(expected[2*i+1])!=c['width']*c['height']*4 for i,c in enumerate(cases)):raise ProbeFailure('Incomplete decoded raster pixels')
    sentinel=work/'rejected.dat';sentinel.write_bytes(b'unchanged');directory=work/'directory';directory.mkdir(exist_ok=True)
    probe.report['sources']=source_gate()
    # Each action: Bend line (BANG marks forced-GPU calls; cpu_only lines are absent from the GPU variant) and its CPU/GPU expectation.
    actions=[]
    for i,case in enumerate(cases):
        bmp='True{}' if case['codec']=='bmp' else 'False{}';image=f'J.Surface.from_bytes({case["width"]}, {case["height"]}, 9, {bend_bytes(case["bytes"])})'
        wanted=expected[2*i:2*i+2];output=work/('candidate-'+case['id']+'-'+case['codec']+'.dat');output.unlink(missing_ok=True)
        actions+=[dict(name=f'{case["id"]} {case["codec"]} encoding',rows=2,cpu=wanted,gpu=wanted,
                       line=f'observed({bmp}, {case["width"]}, {case["height"]}, calculateBANG({bmp}, {image}))'),
                  dict(name=f'{case["id"]} written {case["codec"]} file',file=output,remove=True,cpu=list((work/('reference-'+case['id']+'.'+case['codec'])).read_bytes()),gpu=None,
                       cpu_only=True,line=f'save({bmp}, {json.dumps(str(output.relative_to(ROOT)))}, {image})')]
    actions+=[dict(name=f'rejected {codec} owner',rows=1,cpu=[[1]],gpu=[[1]],line=f'emit_bytes(~&1, [Bool.to_u32(rejected(encodeBANG({bmp}, small(2.0))))])')
              for codec,bmp in (('bmp','True{}'),('tga','False{}'))]
    actions+=[dict(name='100 write closure cycles',rows=1,cpu=[[1]],gpu=[],cpu_only=True,line='closure_loop(100n)'),
              dict(name='rejected write sentinel',file=sentinel,cpu=list(b'unchanged'),gpu=list(b'unchanged'),line=None)]

    def render(selected,gpu):
        bang='!' if gpu else '';body=PROGRAM.replace('BANG',bang)
        for key,path in [('OUTPUT_BMP',work/'candidate-closure.bmp'),('OUTPUT_TGA',work/'candidate-closure.tga'),('SENTINEL',sentinel),('DIRECTORY',directory)]:body=body.replace(key,json.dumps(str(path.relative_to(ROOT))))
        return body+''.join('    '+a['line'].replace('BANG',bang)+'\n' for a in selected if a['line'] and not (gpu and a.get('cpu_only')))

    lanes=probe.candidates(render,actions,batch=len(actions),fd_limit=64,parse=parse_lane);describe=lambda i:actions[i]['name']
    probe.compare([a['cpu'] for a in actions],{lane:rows for lane,rows in lanes.items() if lane!='gpu'},describe)
    if 'gpu' in lanes:probe.compare([a['gpu'] for a in actions],{'gpu':lanes['gpu']},describe)
    probe.finish(images=len(cases),encoded_bytes=sum(len(v) for v in expected[::2]),decoded_bytes=sum(len(v) for v in expected[1::2]),
                 rejected_owner_controls=2,io_error_controls=2,closure_iterations=100,file_descriptor_limit=64,
                 inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
