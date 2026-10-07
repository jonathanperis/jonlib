#!/usr/bin/env python3
"""Compare raw file loading/export with raylib and exercise bounded IO failures."""
import hashlib
import json
import resource

import probekit
from probekit import ROOT, ProbeFailure

FILE_DESCRIPTOR_LIMIT=64


def limit_handles():
    resource.setrlimit(resource.RLIMIT_NOFILE,(64,64))


PROGRAM='''import Base
import ../../jonlib.bend as J
def error_name(error: J.Surface.IOError) -> String:
  match error:
    case J.FileError{_, _}: "file"
    case J.DataError{J.InvalidRequest{}}: "request"
    case J.DataError{J.OutOfDomain{}}: "samples"
    case J.DataError{J.TruncatedImageData{}}: "truncated"
    case J.DataError{J.UnsupportedImageSize{}}: "large"
    case _: "other"
def emit(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = data
  IO.print("{\\"loaded\\":true,\\"width\\":" ++ U32.show(width) ++ ",\\"height\\":" ++ U32.show(height) ++ ",\\"format\\":" ++ U32.show(format) ++ ",\\"bytes\\":" ++ List.show(~&1, ~U32, ~U32.show, bytes) ++ "}")
def reloaded(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "raw file reload failed")
    case Done{image}: emit(J.Surface.export(image))
def written(path: String, width: U32, height: U32, format: U32, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "raw file write failed")
    case Done{_}: IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw(path, width, height, format, 0), reloaded)
def matched(valid: Bool, +path: String, +width: U32, +height: U32, +format: U32, image: J.Surface) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit, 1, "raw load metadata differs")
    case True{}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_raw(image, path), written(path, width, height, format))
def loaded(path: String, width: U32, height: U32, format: U32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("{\\"loaded\\":false,\\"error\\":\\"" ++ error_name(error) ++ "\\"}")
    case Done{J.Surface{+w, +h, +f, pixels}}:
      matched(U32.is_eq(w, width) && U32.is_eq(h, height) && U32.is_eq(f, format), path, w, h, f, J.Surface{w, h, f, pixels})
def required(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "file handles leaked or valid load failed")
def error_checked(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "raw error kind differs")
def failure_checked(expected: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Done{_}: IO.die(Unit, 1, "invalid raw-file request passed")
    case Fail{error}: error_checked(String.eq(expected, error_name(error)))
def write_failed(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("{\\"write_error\\":true}")
    case Done{_}: IO.die(Unit, 1, "invalid raw export path passed")
def invalid_export(result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid raw export image rejected")
    case Some{image}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_raw(image, WRITE_FAILURE), write_failed)
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: IO.print("{\\"closure_checks\\":true}")
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw(VALID, 3, 2, 7, 0), required)
        IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw(SHORT, 1, 1, 7, 0), failure_checked("truncated"))
        IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw(READ_ERROR, 1, 1, 1, 0), failure_checked("file"))
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    probe=probekit.Probe('raw-file',probekit.arguments(__doc__));work=probe.work
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
    if missing.exists():raise ProbeFailure('Task-owned missing-file fixture unexpectedly exists')
    write_failure = work/'missing-directory/output.raw'
    if write_failure.parent.exists():raise ProbeFailure('Task-owned missing-directory fixture unexpectedly exists')
    for name,path,error in (('short',short,'truncated'),('empty',empty,'truncated'),('missing',missing,'file')):
        cases.append(dict(name=name,path=str(path.relative_to(ROOT)),width=1,height=1,format=7,header=0,error=error))
    oversized = work/'oversized.raw'
    with oversized.open('wb') as file:file.truncate(2147483648)
    read_error = work/'read-error';read_error.mkdir(exist_ok=True)
    (read_error/'entry').write_bytes(b'x')
    controls = [dict(name='bad-size',path=str(missing.relative_to(ROOT)),width=0,height=1,format=7,header=0,error='request'),
                dict(name='bad-format',path=str(missing.relative_to(ROOT)),width=1,height=1,format=10,header=0,error='request'),
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
    text=probe.native('\n'.join(lines+['}'])+'\n')
    expected=[json.loads(line) for line in text.splitlines()]
    if len(expected)!=len(cases)+1:raise ProbeFailure('Incomplete native raw-file results')
    digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
    exported=lambda case:work/f'candidate-{case["name"]}.raw'
    # Native rows (plus the fixture's error kind and exported-file digest), boundaries, export failure and closure.
    actions=[('case',case) for case in cases]+[('control',case) for case in controls]+[('write_error',None),('closure',None)]
    wanted=[dict(row,error=case['error']) if case['error'] else dict(row,export_sha256=digest(work/f'reference-{case["name"]}.raw')) if row['loaded'] else row
            for case,row in zip(cases,expected[:-1])]
    wanted+=[dict(loaded=False,error=case['error']) for case in controls]+[expected[-1],dict(closure_checks=True)]
    preamble=PROGRAM.replace('VALID',json.dumps(str((work/'input-7-plain.raw').relative_to(ROOT)))).replace('SHORT',json.dumps(str(short.relative_to(ROOT)))).replace('READ_ERROR',json.dumps(str(read_error.relative_to(ROOT)))).replace('WRITE_FAILURE',json.dumps(str(write_failure.relative_to(ROOT))))

    def render(selected,gpu):
        body=preamble
        for kind,case in selected:
            if kind in ('case','control'):
                output=str(exported(case).relative_to(ROOT))
                body += f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw({json.dumps(case["path"])}, {case["width"]}, {case["height"]}, {case["format"]}, {case["header"]}), loaded({json.dumps(output)}, {case["width"]}, {case["height"]}, {case["format"]}))\n'
            elif kind=='write_error':body += '    invalid_export(J.Surface.from_bytes(1, 1, 7, [1,2,3,4]))\n'
            else:body += '    closure_loop(100n)\n'
        return body

    def parse(text,selected):
        """Attach each lane's exported-file digest, then remove it so the next lane must rewrite it."""
        rows=[json.loads(line) for line in text.splitlines() if line.strip()]
        for (kind,case),row in zip(selected,rows):
            if kind!='case':continue
            if not case['error']:row.pop('error',None)
            if row.get('loaded'):
                path=exported(case);row['export_sha256']=digest(path) if path.is_file() else None;path.unlink(missing_ok=True)
        return rows

    for case in [*cases,*controls]:exported(case).unlink(missing_ok=True)
    probe.compare(wanted,probe.candidates(render,actions,batch=len(actions),fd_limit=FILE_DESCRIPTOR_LIMIT,parse=parse),
                  describe=lambda i:f'action {i} ({actions[i][1]["name"] if actions[i][1] else actions[i][0]})')
    probe.finish(reference_cases=len(cases),boundary_controls=len(controls),file_descriptor_limit=FILE_DESCRIPTOR_LIMIT,closure_iterations=100,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
