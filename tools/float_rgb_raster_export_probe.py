#!/usr/bin/env python3
"""Compare native RGB float BMP/TGA file bytes, pixels and writer ownership."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ENV, ROOT, checkout, run, source_gate
from float_rgb_png_probe import fixtures as png_fixtures
from image_file_probe import limit_handles


def fixtures():
    images=[case for case in png_fixtures() if case['file']]
    values=[v for y in range(2) for x in range(129) for v in ((0.25 if x<128 else 0.5),y*0.5,0.75)]
    images.append(dict(id='run-boundary',width=129,height=2,bytes=list(struct.pack('<'+'f'*len(values),*values))))
    return [dict(image,codec=codec) for codec in ('bmp','tga') for image in images]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'float-rgb-raster-export-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases=fixtures();lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',
        'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
        'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
        'static void emit(unsigned char *data,int size){for(int i=0;i<size;i++)byte(data[i]);end();}',
        'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        path=work/(case['id']+'.raw');path.write_bytes(bytes(case['bytes']));output=work/('reference-'+case['id']+'.'+case['codec'])
        lines += [f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},9,0);if(!image.data)return 2;',
                  f'if(!ExportImage(image,{json.dumps(str(output.relative_to(ROOT)))}))return 3;int n=0;unsigned char *file=LoadFileData({json.dumps(str(output.relative_to(ROOT)))},&n);if(!file)return 4;emit(file,n);',
                  f'Image decoded=LoadImageFromMemory(".{case["codec"]}",file,n);if(!decoded.data||decoded.width!=image.width||decoded.height!=image.height)return 5;ImageFormat(&decoded,7);',
                  'Color *colors=LoadImageColors(image);int size=image.width*image.height*4;if(!colors||memcmp(decoded.data,colors,size))return 6;emit(decoded.data,size);',
                  'UnloadImageColors(colors);UnloadImage(decoded);UnloadImage(image);UnloadFileData(file);}']
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=2*len(cases):raise ValueError('Incomplete native float raster export')
    if any(len(expected[2*i+1])!=c['width']*c['height']*4 for i,c in enumerate(cases)):raise ValueError('Incomplete decoded raster pixels')
    sentinel=work/'rejected.dat';sentinel.write_bytes(b'unchanged');directory=work/'directory';directory.mkdir(exist_ok=True)
    report=dict(passed=False,images=len(cases),encoded_bytes=sum(len(v) for v in expected[::2]),decoded_bytes=sum(len(v) for v in expected[1::2]),
                rejected_owner_controls=2,io_error_controls=2,closure_iterations=100,file_descriptor_limit=64,sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
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
def encode(bmp: Bool, image: J.Image.FloatRGB) -> Result<&1, &1, J.Image.FloatRGB, +List<U32>>:
  match bmp:
    case True{}: J.Image.FloatRGB.to_bmp(image)
    case False{}: J.Image.FloatRGB.to_tga(image)
def exported(result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> Maybe<&2, +List<U32>>:
  match result:
    case Fail{_}: None{}
    case Done{bytes}: Some{bytes}
def calculate(bmp: Bool, result: Maybe<J.Image.FloatRGB>) -> Maybe<&2, +List<U32>>:
  match result:
    case None{}: None{}
    case Some{image}: exported(encode(bmp, image))
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "float raster dimensions/owner differ")
def decode(bmp: Bool, bytes: +List<U32>) -> Result<&1, &1, J.Image.DecodeError, J.Surface>:
  match bmp:
    case True{}: J.Surface.decode_bmp(bytes)
    case False{}: J.Surface.decode_tga(bytes)
def decoded(width: U32, height: U32, result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "float raster round trip failed")
    case Done{J.Surface{+w, +h, pixels}}:
      do IO<Unit>:
        checked(U32.is_eq(width, w) && U32.is_eq(height, h))
        emit_bytes(~&1, rgba(J.Surface.colors(J.Surface{w, h, pixels}), Nil{}))
def observed(bmp: Bool, width: U32, height: U32, result: Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid float raster encoding rejected")
    case Some{+bytes}:
      do IO<Unit>:
        emit_bytes(~&2, bytes)
        decoded(width, height, decodeBANG(bmp, bytes))
def write(bmp: Bool, image: J.Image.FloatRGB, path: String) -> IO(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>):
  match bmp:
    case True{}: J.Image.FloatRGB.write_bmp(image, path)
    case False{}: J.Image.FloatRGB.write_tga(image, path)
def write_ok(result: Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "valid float raster write failed")
def save(bmp: Bool, path: String, result: Maybe<J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "raster file source rejected")
    case Some{image}: IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, write(bmp, image, path), write_ok)
def small(value: F32) -> J.Image.FloatRGB:
  J.FloatRGB{1, 1, Array.new(M.Vector3, 0n, M.Vector3{value, 0.25, 0.75})}
def owner_values(values: List<M.Vector3>) -> Bool:
  match values:
    case Con{M.Vector3{r, g, b}, Nil{}}: F32.is_eq(r, 2.0) && F32.is_eq(g, 0.25) && F32.is_eq(b, 0.75)
    case _: False{}
def owner_entries(result: U32 & U32 & List<M.Vector3>) -> Bool:
  (width, height, values) = result
  U32.is_eq(width, 1) && U32.is_eq(height, 1) && owner_values(values)
def rejected(result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> Bool:
  match result:
    case Done{_}: False{}
    case Fail{image}: owner_entries(J.Image.FloatRGB.entries(image))
def rejected_write(result: Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FloatRGBSampleError{image}}: checked(owner_entries(J.Image.FloatRGB.entries(image)))
    case _: IO.die(Unit, 1, "raster write rejection lost owner")
def failed_write(result: Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FloatRGBFileError{_, _}}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "raster file error kind differs")
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: emit_bytes(~&1, [1])
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, write(True{}, small(0.5), OUTPUT_BMP), write_ok)
        IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, write(False{}, small(0.5), OUTPUT_TGA), write_ok)
        IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, write(True{}, small(2.0), SENTINEL), rejected_write)
        IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, write(False{}, small(2.0), SENTINEL), rejected_write)
        IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, write(True{}, small(0.5), DIRECTORY), failed_write)
        IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, write(False{}, small(0.5), DIRECTORY), failed_write)
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program.replace('BANG',bang)
        for key,path in [('OUTPUT_BMP',work/(lane+'-closure.bmp')),('OUTPUT_TGA',work/(lane+'-closure.tga')),('SENTINEL',sentinel),('DIRECTORY',directory)]:body=body.replace(key,json.dumps(str(path.relative_to(ROOT))))
        for case in cases:
            bmp='True{}' if case['codec']=='bmp' else 'False{}';image=f'J.Image.FloatRGB.from_bytes({case["width"]}, {case["height"]}, {bend_bytes(case["bytes"])})'
            body+=f'    observed({bmp}, {case["width"]}, {case["height"]}, calculate{bang}({bmp}, {image}))\n'
            if lane!='metal':body+=f'    save({bmp}, {json.dumps(str((work/(lane+"-"+case["id"]+"-"+case["codec"]+".dat")).relative_to(ROOT)))}, {image})\n'
        for bmp in ('True{}','False{}'):body+=f'    emit_bytes(~&1, [Bool.to_u32(rejected(encode{bang}({bmp}, small(2.0))))])\n'
        if lane!='metal':body+='    closure_loop(100n)\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        if lane=='metal':output=run(command)
        else:
            process=subprocess.run(list(map(str,command)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=240,preexec_fn=limit_handles)
            if process.returncode:raise RuntimeError(f'{lane}: float raster IO run failed\n{process.stderr[-2000:]}')
            output=process.stdout
        actual=parse_results(output);wanted=expected+[[1],[1]]+([] if lane=='metal' else [[1]])
        different=[i for i,(a,b) in enumerate(zip(wanted,actual)) if a!=b]
        files_match=lane=='metal' or all((work/(lane+'-'+c['id']+'-'+c['codec']+'.dat')).read_bytes()==(work/('reference-'+c['id']+'.'+c['codec'])).read_bytes() for c in cases)
        preserved=sentinel.read_bytes()==b'unchanged'
        report['lanes'][lane]=dict(passed=actual==wanted and files_match and preserved,different_cases=different,file_exports=0 if lane=='metal' else len(cases));report_path.write_text(json.dumps(report,indent=2)+'\n')
        if not report['lanes'][lane]['passed']:raise ValueError(f'{lane}: float raster differences {different}, files={files_match}, sentinel={preserved}')
        print(f'{lane}: {len(cases)} native BMP/TGA files, complete encoded/decoded bytes and retained rejected owners passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
