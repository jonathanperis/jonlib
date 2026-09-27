#!/usr/bin/env python3
"""Compare native float PNG raw-prefix memory export and normalized file export."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ENV, ROOT, checkout, run, source_gate
from image_file_probe import limit_handles


def fixtures():
    cases=[dict(id='split',width=1,height=1,bytes=list(struct.pack('<fff',0.5,0.25,0.75)),file=True)]
    special=[0,0x80000000,1,0x80000001,0x007fffff,0x7f800000,0xff800000,0x7f7fffff]
    cases.append(dict(id='raw-words',width=4,height=2,bytes=list(struct.pack('<24I',*(special*3))),file=False))
    for name,width,height in (('partial-prefix',3,2),('rows',5,3),('thin',1,7),('gradient',17,13)):
        values=[v for y in range(height) for x in range(width) for v in ((x+0.5)/width,(y+0.25)/height,((x*17+y*31)%256)/255)]
        cases.append(dict(id=name,width=width,height=height,bytes=list(struct.pack('<'+'f'*len(values),*values)),file=True))
    return cases


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'float-rgb-png-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases=fixtures();lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',
        'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
        'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
        'static void emit(unsigned char *data,int size){for(int i=0;i<size;i++)byte(data[i]);end();}',
        'static void observe(Image source,unsigned char *encoded,int size,int file){if(!encoded)exit(2);emit(encoded,size);',
        'Image decoded=LoadImageFromMemory(".png",encoded,size);if(!decoded.data||decoded.width!=source.width||decoded.height!=source.height)exit(3);ImageFormat(&decoded,7);',
        'int n=source.width*source.height*4;Color *expected=file?LoadImageColors(source):NULL;',
        'if(memcmp(decoded.data,file?(void*)expected:source.data,n))exit(4);emit(decoded.data,n);if(expected)UnloadImageColors(expected);UnloadImage(decoded);}',
        'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        path=work/(case['id']+'.raw');path.write_bytes(bytes(case['bytes']));output=work/('reference-'+case['id']+'.png')
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},9,0);if(!image.data)return 5;int n=0;')
        lines.append('unsigned char *memory=ExportImageToMemory(image,".png",&n);observe(image,memory,n,0);MemFree(memory);')
        if case['file']:
            lines.append(f'if(!ExportImage(image,{json.dumps(str(output.relative_to(ROOT)))}))return 6;unsigned char *file=LoadFileData({json.dumps(str(output.relative_to(ROOT)))},&n);observe(image,file,n,1);UnloadFileData(file);')
        lines.append('UnloadImage(image);}')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    file_count=sum(c['file'] for c in cases)
    if len(expected)!=2*(len(cases)+file_count):raise ValueError('Incomplete native float PNG output')
    if expected[1]!=[0,0,0,63] or expected[3]!=[127,63,191,255]:raise ValueError('Native float PNG split is no longer distinguished')
    sentinel=work/'rejected.png';sentinel.write_bytes(b'unchanged');directory=work/'directory.png';directory.mkdir(exist_ok=True)
    report=dict(passed=False,memory_images=len(cases),file_images=file_count,encoded_bytes=sum(len(v) for v in expected[::2]),decoded_bytes=sum(len(v) for v in expected[1::2]),
                pure_rejected_owners=2,io_controls=2,closure_iterations=100,file_descriptor_limit=64,sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/hdr.bend as H
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
def encoded(file: Bool, image: J.Image.FloatRGB) -> Result<&1, &1, J.Image.FloatRGB, +List<U32>>:
  match file:
    case False{}: J.Image.FloatRGB.to_png(image)
    case True{}: J.Image.FloatRGB.png.file_bytes(image)
def exported(result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> Maybe<&2, +List<U32>>:
  match result:
    case Fail{_}: None{}
    case Done{bytes}: Some{bytes}
def encode(file: Bool, result: Maybe<J.Image.FloatRGB>) -> Maybe<&2, +List<U32>>:
  match result:
    case None{}: None{}
    case Some{image}: exported(encoded(file, image))
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "float PNG dimensions/owner/write differs")
def decoded(width: U32, height: U32, result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "float PNG round trip failed")
    case Done{J.Surface{+w, +h, pixels}}:
      do IO<Unit>:
        checked(U32.is_eq(width, w) && U32.is_eq(height, h))
        emit_bytes(~&1, rgba(J.Surface.colors(J.Surface{w, h, pixels}), Nil{}))
def observed(width: U32, height: U32, result: Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid float PNG rejected")
    case Some{+bytes}:
      do IO<Unit>:
        emit_bytes(~&2, bytes)
        decoded(width, height, J.Surface.decode_pngBANG(bytes))
def write_ok(result: Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "valid float PNG file write failed")
def save(path: String, result: Maybe<J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "PNG file source rejected")
    case Some{image}: IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, J.Image.FloatRGB.write_png(image, path), write_ok)
def small(value: F32) -> J.Image.FloatRGB:
  J.FloatRGB{1, 1, Array.new(M.Vector3, 0n, M.Vector3{value, 0.25, 0.75})}
def owner_read(wanted: U32, values: List<M.Vector3>) -> Bool:
  match values:
    case Con{M.Vector3{r, g, b}, Nil{}}:
      U32.is_eq(F32.bits(r), F32.bits(H.float_bits(wanted))) && F32.is_eq(g, 0.25) && F32.is_eq(b, 0.75)
    case _: False{}
def owner_entries(wanted: U32, result: U32 & U32 & List<M.Vector3>) -> Bool:
  (width, height, values) = result
  U32.is_eq(width, 1) && U32.is_eq(height, 1) && owner_read(wanted, values)
def rejected(wanted: U32, result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> Bool:
  match result:
    case Done{_}: False{}
    case Fail{image}: owner_entries(wanted, J.Image.FloatRGB.entries(image))
def reject_memory() -> Bool:
  rejected(2143294004, J.Image.FloatRGB.to_png(small(H.float_bits(2143294004))))
def reject_file_bytes() -> Bool:
  rejected(1073741824, J.Image.FloatRGB.png.file_bytes(small(2.0)))
def rejected_write(result: Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FloatRGBSampleError{image}}: checked(owner_entries(1073741824, J.Image.FloatRGB.entries(image)))
    case _: IO.die(Unit, 1, "PNG write rejection lost source")
def failed_write(result: Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FloatRGBFileError{_, _}}: checked(True{})
    case _: IO.die(Unit, 1, "PNG file error kind differs")
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: emit_bytes(~&1, [1])
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, J.Image.FloatRGB.write_png(small(0.5), OUTPUT), write_ok)
        IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, J.Image.FloatRGB.write_png(small(2.0), SENTINEL), rejected_write)
        IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, J.Image.FloatRGB.write_png(small(0.5), DIRECTORY), failed_write)
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program.replace('BANG',bang)
        for key,path in [('OUTPUT',work/(lane+'-closure.png')),('SENTINEL',sentinel),('DIRECTORY',directory)]:body=body.replace(key,json.dumps(str(path.relative_to(ROOT))))
        for case in cases:
            image=f'J.Image.FloatRGB.from_bytes({case["width"]}, {case["height"]}, {bend_bytes(case["bytes"])})'
            for file in (False,True) if case['file'] else (False,):body+=f'    observed({case["width"]}, {case["height"]}, encode{bang}({"True" if file else "False"}{{}}, {image}))\n'
            if case['file'] and lane!='metal':body+=f'    save({json.dumps(str((work/(lane+"-"+case["id"]+".png")).relative_to(ROOT)))}, {image})\n'
        body+=f'    emit_bytes(~&1, [Bool.to_u32(reject_memory{bang}())])\n    emit_bytes(~&1, [Bool.to_u32(reject_file_bytes{bang}())])\n'
        if lane!='metal':body+='    closure_loop(100n)\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        if lane=='metal':output=run(command)
        else:
            process=subprocess.run(list(map(str,command)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=240,preexec_fn=limit_handles)
            if process.returncode:raise RuntimeError(f'{lane}: float PNG IO run failed\n{process.stderr[-2000:]}')
            output=process.stdout
        actual=parse_results(output);wanted=expected+[[1],[1]]+([] if lane=='metal' else [[1]])
        different=[i for i,(a,b) in enumerate(zip(wanted,actual)) if a!=b]
        files_match=lane=='metal' or all((work/(lane+'-'+c['id']+'.png')).read_bytes()==(work/('reference-'+c['id']+'.png')).read_bytes() for c in cases if c['file'])
        preserved=sentinel.read_bytes()==b'unchanged'
        report['lanes'][lane]=dict(passed=actual==wanted and files_match and preserved,different_cases=different,file_exports=0 if lane=='metal' else file_count);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if not report['lanes'][lane]['passed']:raise ValueError(f'{lane}: float PNG differences {different}, files={files_match}, sentinel={preserved}')
        print(f'{lane}: {len(cases)} memory / {file_count} file-byte PNG profiles, complete decoded pixels and rejection controls passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
