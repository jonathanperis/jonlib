#!/usr/bin/env python3
"""Compare complete native animation files, suffix selection and descriptor closure."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from conformance import BUILD, ENV, ROOT, checkout, image_decode_reference, run, source_gate
from gif_animation_probe import fixtures
from image_file_probe import image_streams, limit_handles
from psd_probe import psd


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    args=parser.parse_args();lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'animation-file-probe';work.mkdir(parents=True,exist_ok=True)
    report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    memory,_=fixtures();streams=image_streams();cases=[]
    def add(name,data,error=None):
        path=work/name;path.parent.mkdir(parents=True,exist_ok=True)
        if data is not None:path.write_bytes(bytes(data))
        cases.append(dict(path=str(path.relative_to(ROOT)),data=None if data is None else list(data),error=error))
    for case in memory:add(case['id']+case['token'],case['bytes'])
    for suffix in ('.GiF','.gIf','.gIF','.Gif','.GIf','.giF'):add('mixed'+suffix,memory[1]['bytes'])
    add('nested/.GiF',memory[1]['bytes']);add('many.parts.GiF',memory[1]['bytes'])
    add('png-payload.GiF',streams['png'],'decode');add('mixed.PnG',streams['png'],'decode')
    add('missing.gif',None,'file');add('empty.gif',b'','decode');add('malformed.gif',b'GIF89a','decode')
    add('unsupported.dat',streams['png'],'decode')
    valid=cases[0]['path'];sequence=cases[1]['path'];controls=[]
    for name,size in [('large.GiF',1048577),('large.qoi',83886103)]:
        path=work/name
        with path.open('wb') as handle:handle.truncate(size)
        controls.append(dict(path=str(path.relative_to(ROOT)),frames=100,pixels=16777216,error='size'))
    directory=work/'directory.gif';directory.mkdir(exist_ok=True);(directory/'entry').write_bytes(b'x')
    controls.append(dict(path=str(directory.relative_to(ROOT)),frames=100,pixels=16777216,error='file'))
    controls += [dict(path=sequence,frames=2,pixels=18,error='size'),dict(path=sequence,frames=3,pixels=17,error='size'),
                 dict(path=valid,frames=0,pixels=6,error='size'),dict(path=valid,frames=10,pixels=0,error='size')]
    default=work/'default-alpha.psd';default.write_bytes(bytes(psd(1,1,[[255],[255],[255],[11]])))
    lines=['#include "raylib.h"','#include <stdio.h>',
           'static void emit(const char *path){int frames=0;Image image=LoadImageAnim(path,&frames);if(!image.data){puts("{\\"loaded\\":false}");return;}',
           'ImageFormat(&image,PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);printf("{\\"loaded\\":true,\\"width\\":%d,\\"height\\":%d,\\"count\\":%d}\\n",image.width,image.height,frames);',
           'for(int f=0;f<frames;f++){putchar(\'[\');for(int i=0;i<image.width*image.height;i++)printf("%s%u",i?",":"",(unsigned)ColorToInt(((Color*)image.data)[f*image.width*image.height+i]));puts("]");}UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:lines.append('emit('+json.dumps(case['path'])+');')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    text=run([binary]);expected=[json.loads(line) for line in text.splitlines()];at=0;frames=0;pixels=0
    for case in cases:
        row=expected[at];at+=1
        if row['loaded']!=(case['error'] is None):raise ValueError(f'Native animation file acceptance differs for {case["path"]}')
        if row['loaded']:
            if row['count']<1:raise ValueError('Native animation has no frames')
            for values in expected[at:at+row['count']]:
                if len(values)!=row['width']*row['height']:raise ValueError('Incomplete native frame pixels')
            at+=row['count'];frames+=row['count'];pixels+=row['count']*row['width']*row['height']
        else:row['error']=case['error']
    if at!=len(expected):raise ValueError('Incomplete native animation file output')
    profile=image_decode_reference()
    report=dict(passed=False,native_cases=len(cases),frames=frames,pixels=pixels,boundary_controls=len(controls),
                closure_iterations=100,file_descriptor_limit=64,default_reference_controls=1,decode_reference=profile,sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
import ../../jonlib.bend as J
def error_name(error: J.Image.LoadError) -> String:
  match error:
    case J.ImageFileError{_, _}: "file"
    case J.ImageDecodeError{J.UnsupportedImageSize{}}: "size"
    case _: "decode"
def emit_frames(frames: List<J.Surface>) -> IO(Unit):
  match frames:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{surface, rest}:
      do IO<Unit>:
        IO.print(List.show(~&1, ~U32, ~U32.show, J.Surface.colors(surface)))
        emit_frames(rest)
def emit_animation(result: U32 & U32 & U32 & List<J.Surface>) -> IO(Unit):
  (width, height, count, frames) = result
  do IO<Unit>:
    IO.print("{\\"loaded\\":true,\\"width\\":" ++ U32.show(width) ++ ",\\"height\\":" ++ U32.show(height) ++ ",\\"count\\":" ++ U32.show(count) ++ "}")
    emit_frames(frames)
def observed(result: Result<&1, &1, J.Image.LoadError, J.Image.Animation>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("{\\"loaded\\":false,\\"error\\":\\"" ++ error_name(error) ++ "\\"}")
    case Done{animation}: emit_animation(J.Image.Animation.entries(animation))
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "animation-file outcome or closure differs")
def required(expected: String, result: Result<&1, &1, J.Image.LoadError, J.Image.Animation>) -> IO(Unit):
  match result:
    case Done{_}: checked(String.eq(expected, "success"))
    case Fail{error}: checked(String.eq(expected, error_name(error)))
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: IO.print("{\\"closure_checks\\":true}")
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Animation>, Unit, J.Image.Animation.load_image_for(REFERENCE, VALID, 3, 18), required("success"))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Animation>, Unit, J.Image.Animation.load_image_for(REFERENCE, VALID, 2, 18), required("size"))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Animation>, Unit, J.Image.Animation.load_image_for(REFERENCE, INVALID, 10, 100), required("decode"))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Animation>, Unit, J.Image.Animation.load_image_for(REFERENCE, DIRECTORY, 10, 100), required("file"))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Animation>, Unit, J.Image.Animation.load_image_for(REFERENCE, LARGE, 10, 100), required("size"))
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    program=program.replace('REFERENCE',f'J.{profile}{{}}')
    for key,path in [('INVALID',str((work/'malformed.gif').relative_to(ROOT))),('VALID',sequence),('DIRECTORY',str(directory.relative_to(ROOT))),('LARGE',controls[0]['path'])]:
        program=program.replace(key,json.dumps(path))
    for case in [*cases,*controls]:
        program+=f'    IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Animation>, Unit, J.Image.Animation.load_image_for(J.{profile}{{}}, {json.dumps(case["path"])}, {case.get("frames",100)}, {case.get("pixels",16777216)}), observed)\n'
    program+=f'    IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Animation>, Unit, J.Image.Animation.load_image({json.dumps(str(default.relative_to(ROOT)))}, 1, 1), observed)\n'
    program+='    closure_loop(100n)\n';source=work/'candidate.bend';source.write_text(program)
    wanted=expected+[dict(loaded=False,error=c['error']) for c in controls]+[dict(loaded=True,width=1,height=1,count=1),[0xffffff0b],dict(closure_checks=True)]
    for lane in ('cpu','javascript'):
        binary=work/('candidate.js' if lane=='javascript' else 'candidate-cpu')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary]
        process=subprocess.run(list(map(str,command)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=240,preexec_fn=limit_handles)
        if process.returncode:raise RuntimeError(f'{lane}: animation file run failed\n{process.stderr[-2000:]}')
        actual=[json.loads(line) for line in process.stdout.splitlines()]
        differences=[dict(index=i,reference=a,candidate=b) for i,(a,b) in enumerate(zip(wanted,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==wanted,differences=differences[:2]);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=wanted:raise ValueError(f'{lane}: animation file results differ: {differences[:1]}')
        print(f'{lane}: {len(cases)} native file cases / {frames} frames, {len(controls)} boundaries and 100 closure cycles passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
