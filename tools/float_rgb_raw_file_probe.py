#!/usr/bin/env python3
"""Verify format-9 RAW file headers, exact bytes and closed-handle ownership."""
import hashlib
import json
import struct

from byte_probe import BEND_EMITTER, parse_results
from conformance import ROOT, source_gate
from float_rgb_bytes_probe import fixtures
from float_rgb_png_probe import parse_lane
import probekit
from probekit import ProbeFailure

PRELUDE = ['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
           'static void emit(const char *path,const char *out,int w,int h,int header,int export){Image image=LoadImageRaw(path,w,h,PIXELFORMAT_UNCOMPRESSED_R32G32B32,header);if(!image.data)exit(2);',
           'if(export){if(!ExportImage(image,out))exit(3);}else if(!SaveFileData(out,image.data,w*h*12))exit(4);',
           'word(image.width);word(image.height);for(int i=0;i<w*h*12;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
ERRORS = {'file':1,'request':2,'truncated':3,'large':4}
PROGRAM = '''import Base
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


def file_fixtures(work):
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
    return cases,controls,large,directory


def reference_program(cases,work):
    lines=list(PRELUDE)
    for case in cases:
        output=str((work/('reference-'+case['name']+'.raw')).relative_to(ROOT))
        lines.append(f'emit({json.dumps(case["path"])},{json.dumps(output)},{case["width"]},{case["height"]},{case["header"]},{int(case["native_export"])});')
    return '\n'.join(lines+['}'])+'\n'


def main():
    args=probekit.arguments(__doc__)
    if args.gpu:raise SystemExit('float_rgb_raw_file_probe has no forced-GPU variant (file IO runs on CPU lanes only)')
    probe=probekit.Probe('float-rgb-raw-file',args);work=probe.work
    cases,controls,large,directory=file_fixtures(work);sentinel=work/'rejected.raw';sentinel.write_bytes(b'unchanged')
    text=probe.native(reference_program(cases,work));expected=parse_results(text)
    if len(expected)!=len(cases):raise ProbeFailure('Incomplete native RAW float file output')
    for case,row in zip(cases,expected):
        if row[:8]!=list(struct.pack('<II',case['width'],case['height'])) or len(row)!=8+case['width']*case['height']*12:raise ProbeFailure('Native RAW metadata/length differs')
    probe.report['sources']=source_gate()
    actions=[]
    for case,wanted in zip([*cases,*controls],expected+[[ERRORS[c['error']]] for c in controls]):
        output=work/('candidate-'+case['name']+'.raw');output.unlink(missing_ok=True)
        actions.append(dict(name=case['name'],rows=1,wanted=[wanted],
                            line=f'IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>, Unit, J.Image.FloatRGB.load_raw({json.dumps(case["path"])}, {case["width"]}, {case["height"]}, {case["header"]}), loaded({json.dumps(str(output.relative_to(ROOT)))}))'))
    actions+=[dict(name='rejected write owner',rows=1,wanted=[[1]],line=f'IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, J.Image.FloatRGB.write_raw(J.FloatRGB{{1, 1, Array.new(M.Vector3, 0n, M.Vector3{{H.float_bits(2143294004), 0.5, 0.75}})}}, {json.dumps(str(sentinel.relative_to(ROOT)))}), owner_seen)'),
              dict(name='directory write failure',rows=1,wanted=[[1]],line=f'IO.bind(Result<&1, &1, J.Image.FloatRGB.WriteError, Unit>, Unit, J.Image.FloatRGB.write_raw(small(), {json.dumps(str(directory.relative_to(ROOT)))}), write_failed)'),
              dict(name='100 closure cycles',rows=1,wanted=[[1]],line='closure_loop(100n)')]
    actions+=[dict(name=case['name']+' written file',file=work/('candidate-'+case['name']+'.raw'),remove=True,wanted=list((work/('reference-'+case['name']+'.raw')).read_bytes()),line=None) for case in cases]
    actions.append(dict(name='rejected owner sentinel',file=sentinel,wanted=list(b'unchanged'),line=None))

    def render(selected,gpu):
        body=PROGRAM
        for key,path in [('VALID',work/'normalized-plain.raw'),('SHORT',work/'short.raw'),('NAN_FILE',work/'nan.raw'),('DIRECTORY',directory),('LARGE',large),('OUTPUT',work/'candidate-closure.raw')]:body=body.replace(key,json.dumps(str(path.relative_to(ROOT))))
        return body+''.join('    '+a['line']+'\n' for a in selected if a['line'])

    lanes=probe.candidates(render,actions,batch=len(actions),fd_limit=64,parse=parse_lane)
    probe.compare([a['wanted'] for a in actions],lanes,lambda i:actions[i]['name'])
    probe.finish(native_cases=len(cases),native_exports=sum(c['native_export'] for c in cases),controls=len(controls),owner_controls=1,
                 write_error_controls=1,closure_iterations=100,file_descriptor_limit=64,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
