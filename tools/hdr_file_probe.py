#!/usr/bin/env python3
"""Compare exact HDR file samples and bounded explicit-selection IO."""
import hashlib
import json

from byte_probe import BEND_EMITTER, parse_results
from hdr_probe import fixtures
from image_file_probe import FILE_DESCRIPTOR_LIMIT
import probekit
from probekit import ROOT, ProbeFailure

PROGRAM='''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def word_bytes(n: Nat, +word: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def header(+width: U32, +height: U32) -> List<U32>:
  List.reverse(&1, U32, word_bytes(4n, height, word_bytes(4n, width, Nil{})))
'''+BEND_EMITTER+'''
def emit_image(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match data:
    case Tuple{Tuple{width, height}, Tuple{9, bytes}}: emit_bytes(~&1, List.append(&1, U32, header(width, height), bytes))
    case _: IO.die(Unit, 1, "HDR pixel format changed")
def error_code(error: J.Surface.IOError) -> U32:
  match error:
    case J.FileError{_, _}: 1
    case J.DataError{J.UnsupportedImageSize{}}: 2
    case _: 3
def observed(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{error}: emit_bytes(~&1, [error_code(error)])
    case Done{image}: emit_image(J.Surface.export(image))
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "HDR file outcome or closure differs")
def required(expected: U32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Done{_}: checked(U32.is_eq(expected, 0))
    case Fail{error}: checked(U32.is_eq(expected, error_code(error)))
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: emit_bytes(~&1, [1])
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_hdr(VALID), required(0))
        IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_hdr(INVALID), required(3))
        IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_hdr(DIRECTORY), required(1))
        IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_hdr(LARGE), required(2))
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    probe=probekit.Probe('hdr-file',probekit.arguments(__doc__));work=probe.work
    images,_=fixtures();cases=[]
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
    text=probe.native('\n'.join(lines+['}'])+'\n');expected=parse_results(text)
    if len(expected)!=len(cases):raise ProbeFailure('Incomplete native HDR file output')
    pixels=0
    for row in expected:
        count=int.from_bytes(bytes(row[:4]),'little')*int.from_bytes(bytes(row[4:8]),'little')
        if len(row)!=8+12*count:raise ProbeFailure('Incomplete native float samples')
        pixels+=count
    preamble=PROGRAM
    for key,path in [('INVALID',controls[2]['path']),('VALID',cases[-1]['path']),('DIRECTORY',controls[-1]['path']),('LARGE',controls[-2]['path'])]:preamble=preamble.replace(key,json.dumps(path))
    actions=[case['path'] for case in [*cases,*controls]]+[None]
    wanted=expected+[[{'file':1,'size':2,'decode':3}[case['error']]] for case in controls]+[[1]]

    def render(selected,gpu):
        body=preamble
        for path in selected:
            body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_hdr({json.dumps(path)}), observed)\n' if path else '    closure_loop(100n)\n'
        return body

    probe.compare(wanted,probe.candidates(render,actions,batch=len(actions),fd_limit=FILE_DESCRIPTOR_LIMIT,parse=lambda text,selected:parse_results(text)),
                  describe=lambda i:f'action {i} ({actions[i] or "closure"})')
    probe.finish(native_cases=len(cases),explicit_selection_cases=sum(c['explicit'] for c in cases),pixels=pixels,
                 controls=len(controls),closure_iterations=100,file_descriptor_limit=FILE_DESCRIPTOR_LIMIT,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
