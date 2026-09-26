#!/usr/bin/env python3
"""Compare raw file loading/export with raylib and exercise bounded IO failures."""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import subprocess

from conformance import BUILD, ENV, ROOT, checkout, run, source_gate


def limit_handles():
    resource.setrlimit(resource.RLIMIT_NOFILE,(64,64))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    args = parser.parse_args()
    lock = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    work = BUILD/'raw-file-probe';work.mkdir(parents=True,exist_ok=True)
    report_path = work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases = []
    for format,bpp in ((1,1),(2,2),(3,2),(4,3),(5,2),(6,2),(7,4)):
        payload = bytes((i*73+format*29)%256 for i in range(6*bpp))
        for kind,header,data in (('plain',0,payload+b'ignored'),('header',5,b'JON\0B'+payload),
                                 ('header-outside',1000,b'JON\0B'+payload+b'tail')):
            name=f'{format}-{kind}'
            path=work/f'input-{name}.raw';path.write_bytes(data)
            cases.append(dict(name=name,path=str(path.relative_to(ROOT)),width=3,height=2,format=format,header=header,error=None))
    cases.append(dict(name='header-limit',path=str((work/'input-7-plain.raw').relative_to(ROOT)),width=3,height=2,format=7,header=2147483647-24,error=None))
    short = work/'short.raw';short.write_bytes(b'\x01\x02\x03')
    empty = work/'empty.raw';empty.write_bytes(b'')
    missing = work/'missing.raw'
    if missing.exists():raise ValueError('Task-owned missing-file fixture unexpectedly exists')
    write_failure = work/'missing-directory/output.raw'
    if write_failure.parent.exists():raise ValueError('Task-owned missing-directory fixture unexpectedly exists')
    for name,path,error in (('short',short,'truncated'),('empty',empty,'truncated'),('missing',missing,'file')):
        cases.append(dict(name=name,path=str(path.relative_to(ROOT)),width=1,height=1,format=7,header=0,error=error))
    oversized = work/'oversized.raw'
    with oversized.open('wb') as file:file.truncate(2147483648)
    read_error = work/'read-error';read_error.mkdir(exist_ok=True)
    (read_error/'entry').write_bytes(b'x')
    controls = [dict(name='bad-size',path=str(missing.relative_to(ROOT)),width=0,height=1,format=7,header=0,error='request'),
                dict(name='bad-format',path=str(missing.relative_to(ROOT)),width=1,height=1,format=8,header=0,error='request'),
                dict(name='bad-header',path=str(missing.relative_to(ROOT)),width=1,height=1,format=7,header=2147483647,error='request'),
                dict(name='large-file',path=str(oversized.relative_to(ROOT)),width=1,height=1,format=7,header=0,error='large'),
                dict(name='read-error',path=str(read_error.relative_to(ROOT)),width=1,height=1,format=1,header=0,error='file')]
    lines = ['#include "raylib.h"','#include <stdio.h>', 'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        output = work/f'reference-{case["name"]}.raw'
        lines += ['{',f'Image image=LoadImageRaw({json.dumps(case["path"])},{case["width"]},{case["height"]},{case["format"]},{case["header"]});',
                  'if(!image.data) puts("{\\"loaded\\":false}"); else {',
                  f'if(!ExportImage(image,{json.dumps(str(output.relative_to(ROOT)))})) return 2;',
                  'printf("{\\"loaded\\":true,\\"width\\":%d,\\"height\\":%d,\\"format\\":%d,\\"bytes\\":[",image.width,image.height,image.format);',
                  'int size=GetPixelDataSize(image.width,image.height,image.format);',
                  'for(int i=0;i<size;i++)printf("%s%u",i?",":"",((unsigned char*)image.data)[i]);',
                  'puts("]}"); } UnloadImage(image);','}']
    lines += ['{ Image image=GenImageColor(1,1,GetColor(0x01020304u));',
              f'int wrote=ExportImage(image,{json.dumps(str(write_failure.relative_to(ROOT)))});',
              'printf("{\\"write_error\\":%s}\\n",wrote?"false":"true");UnloadImage(image); }']
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n')
    binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    expected=[json.loads(line) for line in run([binary]).splitlines()]
    if len(expected)!=len(cases)+1:raise ValueError('Incomplete native raw-file results')
    report=dict(passed=False,reference_cases=len(cases),boundary_controls=len(controls),file_descriptor_limit=64,
                closure_iterations=100,sources=source_gate(),inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),lanes={})
    for lane in ('cpu','javascript'):
        program='''import Base
import ../../jonlib.bend as J
def error_name(error: J.Image.RawLoadError) -> String:
  match error:
    case J.RawFileError{_, _}: "file"
    case J.InvalidRawRequest{}: "request"
    case J.TruncatedRawImage{}: "truncated"
    case J.RawFileTooLarge{}: "large"
def emit(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = data
  IO.print("{\\"loaded\\":true,\\"width\\":" ++ U32.show(width) ++ ",\\"height\\":" ++ U32.show(height) ++ ",\\"format\\":" ++ U32.show(format) ++ ",\\"bytes\\":" ++ List.show(~&1, ~U32, ~U32.show, bytes) ++ "}")
def reloaded(result: Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "raw file reload failed")
    case Done{image}: emit(J.Image.Formatted.export(image))
def written(path: String, width: U32, height: U32, format: U32, result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "raw file write failed")
    case Done{_}: IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_raw(path, width, height, format, 0), reloaded)
def matched(valid: Bool, +path: String, +width: U32, +height: U32, +format: U32, image: J.Image.Formatted) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit, 1, "raw load metadata differs")
    case True{}: IO.bind(Result<&1, &1, U32 & String, Unit>, Unit, J.Image.Formatted.write_raw(image, path), written(path, width, height, format))
def loaded(path: String, width: U32, height: U32, format: U32, result: Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("{\\"loaded\\":false,\\"error\\":\\"" ++ error_name(error) ++ "\\"}")
    case Done{J.FormattedImage{+w, +h, +f, pixels}}:
      matched(U32.is_eq(w, width) && U32.is_eq(h, height) && U32.is_eq(f, format), path, w, h, f, J.FormattedImage{w, h, f, pixels})
def required(result: Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "file handles leaked or valid load failed")
def error_checked(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "raw error kind differs")
def failure_checked(expected: String, result: Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Done{_}: IO.die(Unit, 1, "invalid raw-file request passed")
    case Fail{error}: error_checked(String.eq(expected, error_name(error)))
def write_failed(result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("{\\"write_error\\":true}")
    case Done{_}: IO.die(Unit, 1, "invalid raw export path passed")
def invalid_export(result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid raw export image rejected")
    case Some{image}: IO.bind(Result<&1, &1, U32 & String, Unit>, Unit, J.Image.Formatted.write_raw(image, WRITE_FAILURE), write_failed)
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: IO.print("{\\"closure_checks\\":true}")
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_raw(VALID, 3, 2, 7, 0), required)
        IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_raw(SHORT, 1, 1, 7, 0), failure_checked("truncated"))
        IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_raw(READ_ERROR, 1, 1, 1, 0), failure_checked("file"))
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''.replace('VALID',json.dumps(str((work/'input-7-plain.raw').relative_to(ROOT)))).replace('SHORT',json.dumps(str(short.relative_to(ROOT)))).replace('READ_ERROR',json.dumps(str(read_error.relative_to(ROOT)))).replace('WRITE_FAILURE',json.dumps(str(write_failure.relative_to(ROOT))))
        for case in [*cases,*controls]:
            output=str((work/f'{lane}-{case["name"]}.raw').relative_to(ROOT))
            program += f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_raw({json.dumps(case["path"])}, {case["width"]}, {case["height"]}, {case["format"]}, {case["header"]}), loaded({json.dumps(output)}, {case["width"]}, {case["height"]}, {case["format"]}))\n'
        program += '    invalid_export(J.Image.Formatted.from_bytes(1, 1, 7, [1,2,3,4]))\n    closure_loop(100n)\n'
        source=work/f'{lane}.bend';source.write_text(program)
        binary=work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary]
        process=subprocess.run(list(map(str,command)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=240,preexec_fn=limit_handles)
        if process.returncode:raise RuntimeError(f'{lane}: raw-file/closure check failed\n{process.stderr[-2000:]}')
        actual=[json.loads(line) for line in process.stdout.splitlines()]
        if len(actual)!=len(cases)+len(controls)+2 or actual[-1]!={'closure_checks':True}:raise ValueError('Incomplete raw-file candidate results')
        normalized=[{key:value for key,value in row.items() if key!='error'} for row in actual[:len(cases)]]
        if normalized!=expected[:-1] or actual[-2]!=expected[-1]:raise ValueError(f'{lane}: native raw load contents, export failure or metadata differ')
        for case,row in zip([*cases,*controls],actual):
            if case['error'] and row.get('error')!=case['error']:raise ValueError(f'{lane}: {case["name"]} error kind differs')
        for case,row in zip(cases,expected):
            if row['loaded'] and (work/f'{lane}-{case["name"]}.raw').read_bytes()!=(work/f'reference-{case["name"]}.raw').read_bytes():
                raise ValueError(f'{lane}: raw export bytes differ for {case["name"]}')
        report['lanes'][lane]=dict(passed=True)
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        print(f'{lane}: {len(cases)} native load/export cases, {len(controls)} controls and 100 low-descriptor closure iterations passed',flush=True)
    report['passed']=True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
