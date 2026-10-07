#!/usr/bin/env python3
"""Compare complete native animation files, suffix selection and descriptor closure."""
import hashlib
import json

from conformance import image_decode_reference
from gif_animation_probe import fixtures
from image_file_probe import FILE_DESCRIPTOR_LIMIT, image_streams
from psd_probe import psd
import probekit
from probekit import ROOT, ProbeFailure

PROGRAM='''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def error_name(error: J.Surface.IOError) -> String:
  match error:
    case J.FileError{_, _}: "file"
    case J.DataError{J.UnsupportedImageSize{}}: "size"
    case _: "decode"
def emit_colors(result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "animation frame colors unavailable")
    case Done{colors}: IO.print(List.show(~&1, ~U32, ~U32.show, colors))
def emit_frames(frames: List<J.Surface>) -> IO(Unit):
  match frames:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{surface, rest}:
      do IO<Unit>:
        emit_colors(J.Surface.colors(surface))
        emit_frames(rest)
def emit_animation(result: U32 & U32 & U32 & List<J.Surface>) -> IO(Unit):
  (width, height, count, frames) = result
  do IO<Unit>:
    IO.print("{\\"loaded\\":true,\\"width\\":" ++ U32.show(width) ++ ",\\"height\\":" ++ U32.show(height) ++ ",\\"count\\":" ++ U32.show(count) ++ "}")
    emit_frames(frames)
def observed(result: Result<&1, &1, J.Surface.IOError, J.Image.Animation>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("{\\"loaded\\":false,\\"error\\":\\"" ++ error_name(error) ++ "\\"}")
    case Done{animation}: emit_animation(J.Image.Animation.entries(animation))
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "animation-file outcome or closure differs")
def required(expected: String, result: Result<&1, &1, J.Surface.IOError, J.Image.Animation>) -> IO(Unit):
  match result:
    case Done{_}: checked(String.eq(expected, "success"))
    case Fail{error}: checked(String.eq(expected, error_name(error)))
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: IO.print("{\\"closure_checks\\":true}")
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Surface.IOError, J.Image.Animation>, Unit, J.Image.Animation.load_image_for(REFERENCE, VALID, 3, 18), required("success"))
        IO.bind(Result<&1, &1, J.Surface.IOError, J.Image.Animation>, Unit, J.Image.Animation.load_image_for(REFERENCE, VALID, 2, 18), required("size"))
        IO.bind(Result<&1, &1, J.Surface.IOError, J.Image.Animation>, Unit, J.Image.Animation.load_image_for(REFERENCE, INVALID, 10, 100), required("decode"))
        IO.bind(Result<&1, &1, J.Surface.IOError, J.Image.Animation>, Unit, J.Image.Animation.load_image_for(REFERENCE, DIRECTORY, 10, 100), required("file"))
        IO.bind(Result<&1, &1, J.Surface.IOError, J.Image.Animation>, Unit, J.Image.Animation.load_image_for(REFERENCE, LARGE, 10, 100), required("size"))
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def grouped(rows):
    """One group per load: its JSON header object followed by that load's frame rows."""
    groups=[]
    for row in rows:
        if isinstance(row,dict):groups.append([row])
        elif groups:groups[-1].append(row)
        else:raise ProbeFailure('animation-file: frame row before any load result')
    return groups


def main():
    probe=probekit.Probe('animation-file',probekit.arguments(__doc__));work=probe.work
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
    text=probe.native('\n'.join(lines+['}'])+'\n');expected=[json.loads(line) for line in text.splitlines()];at=0;frames=0;pixels=0
    for case in cases:
        row=expected[at];at+=1
        if row['loaded']!=(case['error'] is None):raise ProbeFailure(f'Native animation file acceptance differs for {case["path"]}')
        if row['loaded']:
            if row['count']<1:raise ProbeFailure('Native animation has no frames')
            for values in expected[at:at+row['count']]:
                if len(values)!=row['width']*row['height']:raise ProbeFailure('Incomplete native frame pixels')
            at+=row['count'];frames+=row['count'];pixels+=row['count']*row['width']*row['height']
        else:row['error']=case['error']
    if at!=len(expected):raise ProbeFailure('Incomplete native animation file output')
    profile=image_decode_reference()
    preamble=PROGRAM.replace('REFERENCE',f'M.{profile}{{}}')
    for key,path in [('INVALID',str((work/'malformed.gif').relative_to(ROOT))),('VALID',sequence),('DIRECTORY',str(directory.relative_to(ROOT))),('LARGE',controls[0]['path'])]:
        preamble=preamble.replace(key,json.dumps(path))
    actions=[('load',case) for case in [*cases,*controls]]+[('default',None),('closure',None)]
    wanted=grouped(expected+[dict(loaded=False,error=c['error']) for c in controls]+[dict(loaded=True,width=1,height=1,count=1),[0xffffff0b],dict(closure_checks=True)])

    def render(selected,gpu):
        body=preamble
        for kind,case in selected:
            if kind=='load':body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Image.Animation>, Unit, J.Image.Animation.load_image_for(M.{profile}{{}}, {json.dumps(case["path"])}, {case.get("frames",100)}, {case.get("pixels",16777216)}), observed)\n'
            elif kind=='default':body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Image.Animation>, Unit, J.Image.Animation.load_image({json.dumps(str(default.relative_to(ROOT)))}, 1, 1), observed)\n'
            else:body+='    closure_loop(100n)\n'
        return body

    probe.compare(wanted,probe.candidates(render,actions,batch=len(actions),fd_limit=FILE_DESCRIPTOR_LIMIT,
                                          parse=lambda text,selected:grouped([json.loads(line) for line in text.splitlines() if line.strip()])),
                  describe=lambda i:f'action {i} ({actions[i][1]["path"] if actions[i][1] else actions[i][0]})')
    probe.finish(native_cases=len(cases),frames=frames,pixels=pixels,boundary_controls=len(controls),closure_iterations=100,
                 file_descriptor_limit=FILE_DESCRIPTOR_LIMIT,default_reference_controls=1,decode_reference=profile,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
