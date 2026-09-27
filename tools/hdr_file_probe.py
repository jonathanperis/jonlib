#!/usr/bin/env python3
"""Compare exact HDR file samples and bounded explicit-selection IO."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ENV, ROOT, checkout, run, source_gate
from hdr_probe import fixtures
from image_file_probe import limit_handles


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    args=parser.parse_args();lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'hdr-file-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json'
    report_path.write_text(json.dumps(dict(passed=False))+'\n');images,_=fixtures();cases=[]
    for case in images:
        path=work/(case['id']+'.hdr');path.write_bytes(bytes(case['bytes']))
        cases.append(dict(path=str(path.relative_to(ROOT)),data=case['bytes'],explicit=False))
    for name in ('upper.HDR','mixed.HdR','without-extension','misnamed.png'):
        path=work/name;path.write_bytes(bytes(images[-1]['bytes']))
        cases.append(dict(path=str(path.relative_to(ROOT)),data=images[-1]['bytes'],explicit=name!='upper.HDR'))
    controls=[]
    for name,data,error in [('missing.hdr',None,'file'),('empty.hdr',b'','decode'),
                            ('truncated.hdr',bytes(images[0]['bytes'][:-1]),'decode')]:
        path=work/name
        if data is not None:path.write_bytes(data)
        controls.append(dict(path=str(path.relative_to(ROOT)),error=error))
    large=work/'large.hdr'
    with large.open('wb') as file:file.truncate(1048577)
    controls.append(dict(path=str(large.relative_to(ROOT)),error='size'))
    directory=work/'directory.hdr';directory.mkdir(exist_ok=True);(directory/'entry').write_bytes(b'x')
    controls.append(dict(path=str(directory.relative_to(ROOT)),error='file'))
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
           'static void emit(Image image){if(!image.data||image.format!=PIXELFORMAT_UNCOMPRESSED_R32G32B32)exit(2);word(image.width);word(image.height);',
           'for(int i=0;i<image.width*image.height*3;i++){unsigned bits;memcpy(&bits,(float*)image.data+i,4);word(bits);}end();UnloadImage(image);}',
           'static void explicit_load(const char *path){int size=0;unsigned char *data=LoadFileData(path,&size);emit(LoadImageFromMemory(".hdr",data,size));UnloadFileData(data);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        path=json.dumps(case['path']);lines.append(f'explicit_load({path});' if case['explicit'] else f'emit(LoadImage({path}));')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(cases):raise ValueError('Incomplete native HDR file output')
    pixels=0
    for row in expected:
        count=int.from_bytes(bytes(row[:4]),'little')*int.from_bytes(bytes(row[4:8]),'little')
        if len(row)!=8+12*count:raise ValueError('Incomplete native float samples')
        pixels+=count
    report=dict(passed=False,native_cases=len(cases),explicit_selection_cases=sum(c['explicit'] for c in cases),pixels=pixels,
                controls=len(controls),closure_iterations=100,file_descriptor_limit=64,sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def word_bytes(n: Nat, +word: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def samples(pixels: List<M.Vector3>, values: List<U32>) -> List<U32>:
  match pixels:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{M.Vector3{r, g, b}, rest}: samples(rest, word_bytes(4n, F32.bits(b), word_bytes(4n, F32.bits(g), word_bytes(4n, F32.bits(r), values))))
'''+BEND_EMITTER+'''
def emit_image(result: U32 & U32 & List<M.Vector3>) -> IO(Unit):
  (width, height, pixels) = result
  emit_bytes(~&1, samples(pixels, word_bytes(4n, height, word_bytes(4n, width, Nil{}))))
def error_code(error: J.Image.LoadError) -> U32:
  match error:
    case J.ImageFileError{_, _}: 1
    case J.ImageDecodeError{J.UnsupportedImageSize{}}: 2
    case _: 3
def observed(result: Result<&1, &1, J.Image.LoadError, J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case Fail{error}: emit_bytes(~&1, [error_code(error)])
    case Done{image}: emit_image(J.Image.FloatRGB.entries(image))
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "HDR file outcome or closure differs")
def required(expected: U32, result: Result<&1, &1, J.Image.LoadError, J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case Done{_}: checked(U32.is_eq(expected, 0))
    case Fail{error}: checked(U32.is_eq(expected, error_code(error)))
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: emit_bytes(~&1, [1])
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_hdr(VALID), required(0))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_hdr(INVALID), required(3))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_hdr(DIRECTORY), required(1))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_hdr(LARGE), required(2))
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for key,path in [('INVALID',controls[2]['path']),('VALID',cases[-1]['path']),('DIRECTORY',controls[-1]['path']),('LARGE',controls[-2]['path'])]:program=program.replace(key,json.dumps(path))
    for case in [*cases,*controls]:program+=f'    IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_hdr({json.dumps(case["path"])}), observed)\n'
    program+='    closure_loop(100n)\n';source=work/'candidate.bend';source.write_text(program)
    wanted=expected+[[{'file':1,'size':2,'decode':3}[case['error']]] for case in controls]+[[1]]
    for lane in ('cpu','javascript'):
        binary=work/('candidate.js' if lane=='javascript' else 'candidate-cpu')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary]
        process=subprocess.run(list(map(str,command)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=240,preexec_fn=limit_handles)
        if process.returncode:raise RuntimeError(f'{lane}: HDR file run failed\n{process.stderr[-2000:]}')
        actual=parse_results(process.stdout);differences=[i for i,(a,b) in enumerate(zip(wanted,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==wanted,different_cases=differences);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=wanted:raise ValueError(f'{lane}: HDR file differences {differences}')
        print(f'{lane}: {len(cases)} HDR file cases / {pixels} pixels, {len(controls)} controls and 100 closure cycles passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
