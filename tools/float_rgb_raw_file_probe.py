#!/usr/bin/env python3
"""Verify format-9 RAW file headers, exact bytes and closed-handle ownership."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess

from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ENV, ROOT, checkout, run, source_gate
from float_rgb_bytes_probe import fixtures
from image_file_probe import limit_handles


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    args=parser.parse_args();lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'float-rgb-raw-file-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    inputs,_=fixtures();cases=[]
    inputs.append(dict(id='normalized',width=1,height=1,bytes=list(struct.pack('<fff',0.25,0.5,0.75))))
    for sample in inputs:
        data=bytes(sample['bytes'])
        for variant,header,payload in [('plain',0,data),('header',3,b'JON'+data+b'tail'),('nonfit',3,data),('maximum-header',2147483647-len(data),data)]:
            name=sample['id']+'-'+variant;path=work/(name+'.raw');path.write_bytes(payload)
            cases.append(dict(name=name,path=str(path.relative_to(ROOT)),width=sample['width'],height=sample['height'],header=header,
                              bytes=list(payload),native_export=sample['id']=='normalized'))
    controls=[]
    def control(name,width,height,header,data,error):
        path=work/(name+'.raw')
        if data is not None:path.write_bytes(data)
        controls.append(dict(name=name,path=str(path.relative_to(ROOT)),width=width,height=height,header=header,error=error))
    control('missing',1,1,0,None,'file');control('empty',1,1,0,b'','truncated');control('short',1,1,0,b'12345678901','truncated')
    control('nan',1,1,0,struct.pack('<III',0x7fc00001,0,0),'request')
    control('zero-width',0,1,0,None,'request');control('large-height',1,4097,0,None,'request')
    control('overflow-header',1,1,2147483636,None,'request')
    large=work/'large.raw'
    with large.open('wb') as file:file.truncate(2147483648)
    controls.append(dict(name='large',path=str(large.relative_to(ROOT)),width=1,height=1,header=0,error='large'))
    directory=work/'directory.raw';directory.mkdir(exist_ok=True);(directory/'entry').write_bytes(b'x')
    controls.append(dict(name='directory',path=str(directory.relative_to(ROOT)),width=1,height=1,header=0,error='file'))
    sentinel=work/'rejected.raw';sentinel.write_bytes(b'unchanged')
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
           'static void emit(const char *path,const char *out,int w,int h,int header,int export){Image image=LoadImageRaw(path,w,h,PIXELFORMAT_UNCOMPRESSED_R32G32B32,header);if(!image.data)exit(2);',
           'if(export){if(!ExportImage(image,out))exit(3);}else if(!SaveFileData(out,image.data,w*h*12))exit(4);',
           'word(image.width);word(image.height);for(int i=0;i<w*h*12;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        output=str((work/('reference-'+case['name']+'.raw')).relative_to(ROOT))
        lines.append(f'emit({json.dumps(case["path"])},{json.dumps(output)},{case["width"]},{case["height"]},{case["header"]},{int(case["native_export"])});')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(cases):raise ValueError('Incomplete native RAW float file output')
    for case,row in zip(cases,expected):
        if row[:8]!=list(struct.pack('<II',case['width'],case['height'])) or len(row)!=8+case['width']*case['height']*12:raise ValueError('Native RAW metadata/length differs')
    report=dict(passed=False,native_cases=len(cases),native_exports=sum(c['native_export'] for c in cases),controls=len(controls),owner_controls=1,
                write_error_controls=1,closure_iterations=100,file_descriptor_limit=64,sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/hdr.bend as H
'''+BEND_EMITTER+'''
def error_code(error: J.Image.RawLoadError) -> U32:
  match error:
    case J.RawFileError{_, _}: 1
    case J.InvalidRawRequest{}: 2
    case J.TruncatedRawImage{}: 3
    case J.RawFileTooLarge{}: 4
    case J.InvalidRawSamples{}: 5
def emitted(+width: U32, +height: U32, result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid float byte export rejected")
    case Done{bytes}:
      header = {[(width .&. 255 : U32), ((width >> 8n) .&. 255 : U32), 0, 0, (height .&. 255 : U32), ((height >> 8n) .&. 255 : U32), 0, 0] : +List<U32>}
      emit_bytes(~&2, List.append(&2, U32, header, bytes))
def reloaded(result: Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case Fail{error}: emit_bytes(~&1, [error_code(error)])
    case Done{J.FloatRGB{+width, +height, pixels}}: emitted(width, height, J.Image.FloatRGB.to_bytes(J.FloatRGB{width, height, pixels}))
def written(path: String, width: U32, height: U32, result: Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid raw float write failed")
    case Done{_}: IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_raw(path, width, height, 0), reloaded)
def loaded(+path: String, result: Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case Fail{error}: emit_bytes(~&1, [error_code(error)])
    case Done{J.FloatRGB{+width, +height, pixels}}:
      IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, J.Image.FloatRGB.write_raw(J.FloatRGB{width, height, pixels}, path), written(path, width, height))
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "raw float closure/error differs")
def required(expected: U32, result: Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case Done{_}: checked(U32.is_eq(expected, 0))
    case Fail{error}: checked(U32.is_eq(expected, error_code(error)))
def small() -> J.Image.FloatRGB:
  J.FloatRGB{1, 1, Array.new(M.Vector3, 0n, M.Vector3{0.25, 0.5, 0.75})}
def write_ok(result: Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "raw float write closure failed")
def owner_values(values: List<M.Vector3>) -> Bool:
  match values:
    case Con{M.Vector3{r, g, b}, Nil{}}:
      U32.is_eq(F32.bits(r), F32.bits(H.float_bits(2143294004))) && F32.is_eq(g, 0.5) && F32.is_eq(b, 0.75)
    case _: False{}
def owner_entries(result: U32 & U32 & List<M.Vector3>) -> Bool:
  (width, height, values) = result
  U32.is_eq(width, 1) && U32.is_eq(height, 1) && owner_values(values)
def owner_seen(result: Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FloatRGBSampleError{image}}: emit_bytes(~&1, [Bool.to_u32(owner_entries(J.Image.FloatRGB.entries(image)))])
    case _: IO.die(Unit, 1, "raw float invalid owner was lost")
def write_failed(result: Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FloatRGBFileError{_, _}}: emit_bytes(~&1, [1])
    case _: IO.die(Unit, 1, "raw float write failure kind differs")
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: emit_bytes(~&1, [1])
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_raw(VALID, 1, 1, 0), required(0))
        IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_raw(SHORT, 1, 1, 0), required(3))
        IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_raw(NAN_FILE, 1, 1, 0), required(2))
        IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_raw(DIRECTORY, 1, 1, 0), required(1))
        IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_raw(LARGE, 1, 1, 0), required(4))
        IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, J.Image.FloatRGB.write_raw(small(), OUTPUT), write_ok)
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript'):
        body=program
        for key,path in [('VALID',work/'normalized-plain.raw'),('SHORT',work/'short.raw'),('NAN_FILE',work/'nan.raw'),('DIRECTORY',directory),('LARGE',large),('OUTPUT',work/(lane+'-closure.raw'))]:body=body.replace(key,json.dumps(str(path.relative_to(ROOT))))
        for case in [*cases,*controls]:
            output=str((work/(lane+'-'+case['name']+'.raw')).relative_to(ROOT))
            body+=f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_raw({json.dumps(case["path"])}, {case["width"]}, {case["height"]}, {case["header"]}), loaded({json.dumps(output)}))\n'
        body+=f'    IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, J.Image.FloatRGB.write_raw(J.FloatRGB{{1, 1, Array.new(M.Vector3, 0n, M.Vector3{{H.float_bits(2143294004), 0.5, 0.75}})}}, {json.dumps(str(sentinel.relative_to(ROOT)))}), owner_seen)\n'
        body+=f'    IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, J.Image.FloatRGB.write_raw(small(), {json.dumps(str(directory.relative_to(ROOT)))}), write_failed)\n'
        body+='    closure_loop(100n)\n';source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-cpu')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary]
        process=subprocess.run(list(map(str,command)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=240,preexec_fn=limit_handles)
        if process.returncode:raise RuntimeError(f'{lane}: raw float file run failed\n{process.stderr[-2000:]}')
        actual=parse_results(process.stdout);wanted=expected+[[{'file':1,'request':2,'truncated':3,'large':4}[c['error']]] for c in controls]+[[1],[1],[1]]
        different=[i for i,(a,b) in enumerate(zip(wanted,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==wanted,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=wanted:raise ValueError(f'{lane}: raw float file differences {different}')
        for case in cases:
            if (work/(lane+'-'+case['name']+'.raw')).read_bytes()!=(work/('reference-'+case['name']+'.raw')).read_bytes():raise ValueError('Raw float output file bytes differ')
        if sentinel.read_bytes()!=b'unchanged':raise ValueError('Rejected owner opened/truncated output file')
        print(f'{lane}: {len(cases)} native RAW float cases, {len(controls)} controls, owned write rejection and 100 closure cycles passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
