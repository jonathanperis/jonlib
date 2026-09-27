#!/usr/bin/env python3
"""Compare supported image-file dispatch with native raylib and check closure."""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import struct
import subprocess

from conformance import BUILD, ENV, ROOT, checkout, run, source_gate
from png_probe import png
from bmp_probe import bitmap
from tga_probe import targa


def limit_handles():
    resource.setrlimit(resource.RLIMIT_NOFILE,(64,64))


def image_streams():
    rgba=bytes([1,2,3,0, 17,63,201,128, 255,127,128,255, 254,253,252,1, 0,255,0,127, 255,0,255,255])
    pixels=[int.from_bytes(rgba[i:i+4],'big') for i in range(0,len(rgba),4)]
    bgra=bytes(v for i in range(0,len(rgba),4) for v in (rgba[i+2],rgba[i+1],rgba[i],rgba[i+3]))
    return {'png':png(3,2,6,rgba,interlaced=True),
            'bmp':bytes(bitmap(3,2,pixels,top=True)),
            'tga':bytes(targa(3,2,4,[5,*bgra],rle=True,top=True)),
            'pgm':b'P5\n# gray\n3 2\n255\n'+bytes([0,1,127,128,254,255]),
            'ppm':b'P6\n3 2\n255\n'+bytes(v for i in range(0,len(rgba),4) for v in rgba[i:i+3]),
            'qoi':b'qoif'+struct.pack('>II',3,2)+b'\4\0'+b''.join(b'\xff'+rgba[i:i+4] for i in range(0,len(rgba),4))+b'\0'*7+b'\1'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'image-file-probe';work.mkdir(parents=True,exist_ok=True)
    report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    streams=image_streams()
    cases=[]
    def add(name,data,error=None,legacy=False):
        path=work/name
        path.parent.mkdir(parents=True,exist_ok=True)
        if data is not None:path.write_bytes(data)
        elif path.exists():raise ValueError('Task-owned missing-file fixture unexpectedly exists')
        cases.append(dict(path=str(path.relative_to(ROOT)),data=list(data) if data is not None else None,error=error,legacy=legacy))
    for extension in streams:
        add(f'normal.{extension}',streams[extension]);add(f'upper.{extension.upper()}',streams[extension])
    for name,kind in [('png-data.bmp','png'),('bmp-data.png','bmp'),('pnm-data.tga','ppm'),('tga-data.ppm','tga')]:add(name,streams[kind])
    add('mixed.PnG',streams['png'],'decode');add('unsupported.data',streams['png'],'decode')
    add('qoi-data.png',streams['qoi'],'decode');add('png-data.qoi',streams['png'],'decode')
    add('malformed.png',b'invalid','decode');add('empty.png',b'','decode');add('missing.png',None,'file')
    add('explicit-qoi.data',streams['qoi'],legacy=True)
    for extension in ('jpg','jpeg','gif','pic','psd'):
        add(f'alias.{extension}',streams['png']);add(f'alias.{extension.upper()}',streams['png'])
    add('many.parts.JPEG',streams['png']);add('.png',streams['png'])
    add('mixed.JpEg',streams['png'],'decode');add('folder.png/no-extension',streams['png'],'decode')
    controls=[]
    for name,size in [('large.png',1048577),('large.qoi',83886103)]:
        path=work/name
        with path.open('wb') as file:file.truncate(size)
        controls.append(dict(path=str(path.relative_to(ROOT)),size=size,error='size',legacy=False))
    directory=work/'directory.png';directory.mkdir(exist_ok=True);(directory/'entry').write_bytes(b'x')
    controls.append(dict(path=str(directory.relative_to(ROOT)),error='file',legacy=False))
    lines=['#include "raylib.h"','#include <stdio.h>',
           'static void emit(Image image){if(!image.data){puts("{\\"loaded\\":false}");return;}ImageFormat(&image,7);',
           'printf("{\\"loaded\\":true,\\"width\\":%d,\\"height\\":%d,\\"pixels\\":[",image.width,image.height);',
           'Color *pixels=LoadImageColors(image);for(int i=0;i<image.width*image.height;i++)printf("%s%u",i?",":"",(unsigned)ColorToInt(pixels[i]));',
           'puts("]}");UnloadImageColors(pixels);UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        path=json.dumps(case['path'])
        if case['legacy']:
            lines+=['{int size=0;',f'unsigned char *data=LoadFileData({path},&size);',
                    'emit(LoadImageFromMemory(".qoi",data,size));UnloadFileData(data);}']
        else:lines += [f'emit(LoadImage({path}));']
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n')
    binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    text=run([binary]);expected=[json.loads(line) for line in text.splitlines()]
    if len(expected)!=len(cases):raise ValueError('Incomplete native image-file results')
    if any(row['loaded']!=(case['error'] is None) for case,row in zip(cases,expected)):raise ValueError('Native image-file acceptance differs from fixture profile')
    report=dict(passed=False,reference_cases=len(cases),boundary_controls=len(controls),closure_iterations=100,file_descriptor_limit=64,
                inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),sources=source_gate(),lanes={})
    program='''import Base
import ../../jonlib.bend as J
def error_name(error: J.Image.LoadError) -> String:
  match error:
    case J.ImageFileError{_, _}: "file"
    case J.ImageDecodeError{J.UnsupportedImageSize{}}: "size"
    case _: "decode"
def observed(result: Result<&1, &1, J.Image.LoadError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("{\\"loaded\\":false,\\"error\\":\\"" ++ error_name(error) ++ "\\"}")
    case Done{J.Surface{+w, +h, pixels}}:
      IO.print("{\\"loaded\\":true,\\"width\\":" ++ U32.show(w) ++ ",\\"height\\":" ++ U32.show(h) ++ ",\\"pixels\\":" ++ List.show(~&1, ~U32, ~U32.show, J.Surface.colors(J.Surface{w, h, pixels})) ++ "}")
def checked(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "image-file outcome or closure differs")
def required(expected: String, result: Result<&1, &1, J.Image.LoadError, J.Surface>) -> IO(Unit):
  match result:
    case Done{_}: checked(String.eq(expected, "success"))
    case Fail{error}: checked(String.eq(expected, error_name(error)))
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: IO.print("{\\"closure_checks\\":true}")
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.load_image(VALID), required("success"))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.load_image(INVALID), required("decode"))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.load_image(DIRECTORY), required("file"))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.load_image(LARGE), required("size"))
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for key,path in [('INVALID',work/'malformed.png'),('VALID',work/'normal.png'),('DIRECTORY',directory),('LARGE',work/'large.png')]:
        program=program.replace(key,json.dumps(str(path.relative_to(ROOT))))
    for case in [*cases,*controls]:
        function='load_qoi' if case['legacy'] else 'load_image'
        program+=f'    IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.{function}({json.dumps(case["path"])}), observed)\n'
    program+='    closure_loop(100n)\n'
    source=work/'candidate.bend';source.write_text(program)
    for lane in ('cpu','javascript'):
        binary=work/('candidate.js' if lane=='javascript' else 'candidate-cpu')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary]
        process=subprocess.run(list(map(str,command)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=240,preexec_fn=limit_handles)
        if process.returncode:raise RuntimeError(f'{lane}: image-file run failed\n{process.stderr[-2000:]}')
        actual=[json.loads(line) for line in process.stdout.splitlines()]
        if len(actual)!=len(cases)+len(controls)+1 or actual[-1]!={'closure_checks':True}:raise ValueError('Incomplete image-file results')
        normalized=[{k:v for k,v in row.items() if k!='error'} for row in actual[:len(cases)]]
        if normalized!=expected:raise ValueError(f'{lane}: native file pixels or dispatch differs')
        for case,row in zip([*cases,*controls],actual):
            if case['error'] and row.get('error')!=case['error']:raise ValueError(f'{lane}: file/decode error kind differs for {case["path"]}')
        report['lanes'][lane]=dict(passed=True)
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        print(f'{lane}: {len(cases)} native file cases, {len(controls)} boundaries and 100 low-descriptor cycles passed',flush=True)
    report['passed']=True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
