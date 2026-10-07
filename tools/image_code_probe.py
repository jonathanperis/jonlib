#!/usr/bin/env python3
"""Compare complete native image-as-code text, names and bounded text-file IO."""
import hashlib
import json
import struct

from byte_probe import BEND_EMITTER, parse_results
from formatted_float_probe import fixtures as formatted_fixtures
from float_rgb_bytes_probe import fixtures as float_fixtures
from image_file_probe import FILE_DESCRIPTOR_LIMIT
import probekit
from probekit import ROOT, ProbeFailure


def fixtures():
    cases=[dict(case,name=f'format_{case["format"]}.h') for case in formatted_fixtures()]
    for count,name in ((1,'a'*198+'.h'),(20,'no_extension'),(21,'.hidden'),(22,'Mixed.Asset.h'),(23,'win\\MiXeD-name.h')):
        cases.append(dict(width=count,height=1,format=1,bytes=list(range(count)),name=name))
    cases.append(dict(width=128,height=128,format=7,bytes=list(range(256))*256,name='maximum.h'))
    floats,_=float_fixtures()
    cases.extend(dict(case,format=9,name='float_'+case['id']+'.h') for case in floats)
    cases.append(dict(width=43,height=127,format=9,bytes=list(struct.pack('<III',0x80000000,1,0x7f800000))*5461,name='float_maximum.h'))
    return cases


PROGRAM='''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/hdr.bend as H
def word_bytes(~q: Quant, n: Nat, +word: U32, values: List<q, U32>) -> List<q, U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(~q, rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def text_bytes(text: String, values: List<U32>) -> List<U32>:
  match text:
    case SNil{}: List.reverse(&1, U32, values)
    case SCon{character, rest}: text_bytes(rest, Con{Char.to_u32(character), values})
'''+BEND_EMITTER+'''
def formatted(result: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = result
  header = List.reverse(&1, U32, word_bytes(~&1, 4n, format, word_bytes(~&1, 4n, height, word_bytes(~&1, 4n, width, Nil{}))))
  emit_bytes(~&1, List.append(&1, U32, header, bytes))
def observed(reject: Bool, result: Result<&1, &1, J.Surface & J.Surface.Error, String>) -> IO(Unit):
  match reject result:
    case False{} Done{text}: emit_bytes(~&1, text_bytes(text, Nil{}))
    case True{} Fail{Tuple{image, J.InvalidRequest{}}}: formatted(J.Surface.export(image))
    case _ _: IO.die(Unit, 1, "image-as-code acceptance/owner differs")
def loaded(path: String, reject: Bool, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "code fixture read failed")
    case Done{image}: observed(reject, J.Surface.to_codeBANG(image, path))
def write_ok(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "code file write failed")
def saved(path: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "code file source read failed")
    case Done{image}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_code(image, path), write_ok)
# Format 7 words are canonical Colors: 0x01020304 stores the bytes 1, 2, 3, 4.
def small() -> J.Surface:
  J.Surface{1, 1, 7, J.Words{Array.new(U32, 0n, 16909060)}}
def invalid_path(kind: U32) -> String:
  match kind:
    case 0: ""
    case 1: "folder/"
    case 2: LONG_NAME
    case 3: "caf" ++ SCon{Char.from_u32(233), ".h"}
    case 4: SCon{Char.from_u32(0), "bad.h"}
    case _: OVERFLOW_NAME
def reject_path(kind: U32) -> Result<&1, &1, J.Surface & J.Surface.Error, String>:
  J.Surface.to_code(small(), invalid_path(kind))
def rejected_write(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.SourceError{image, J.InvalidRequest{}}}: formatted(J.Surface.export(image))
    case _: IO.die(Unit, 1, "code rejected write lost owner")
def reject_large_write(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "large code source read failed")
    case Done{image}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_code(image, SENTINEL), rejected_write)
def failed_write(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FileError{_, _}}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "code file error kind differs")
def float_sized(+width: U32, +height: U32, bytes: List<U32>) -> IO(Unit):
  emit_bytes(~&1, List.append(&1, U32, List.reverse(&1, U32, word_bytes(~&1, 4n, height, word_bytes(~&1, 4n, width, Nil{}))), bytes))
def float_entries(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match data:
    case Tuple{Tuple{width, height}, Tuple{9, bytes}}: float_sized(width, height, bytes)
    case _: IO.die(Unit, 1, "float code owner format changed")
def float_observed(reject: Bool, result: Result<&1, &1, J.Surface & J.Surface.Error, String>) -> IO(Unit):
  match reject result:
    case False{} Done{text}: emit_bytes(~&1, text_bytes(text, Nil{}))
    case True{} Fail{Tuple{image, J.InvalidRequest{}}}: float_entries(J.Surface.export(image))
    case _ _: IO.die(Unit, 1, "float code acceptance/owner differs")
def float_loaded(path: String, reject: Bool, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "float code fixture read failed")
    case Done{image}: float_observed(reject, J.Surface.to_codeBANG(image, path))
def float_write_ok(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "float code file write failed")
def float_saved(path: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "float code file source read failed")
    case Done{image}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_code(image, path), float_write_ok)
def float_small() -> J.Surface:
  J.Surface{1, 1, 9, J.Vectors{Array.new(M.Vector3, 0n, M.Vector3{0.5, 0.25, 0.75})}}
# NaN samples are outside the checked export domain: the owner comes back intact
# (compared with same-backend bits: NaN payloads are not portable across backends).
def float_nan() -> J.Surface:
  J.Surface{2, 1, 9, J.Vectors{Array.set(M.Vector3, Array.new(M.Vector3, 1n, M.Vector3{0.5, 0.25, 0.75}), 1, M.Vector3{H.float_bits(2143294004), 0.25, 0.75})}}
def vector_is.bits(+r: U32, +g: U32, +b: U32, value: M.Vector3) -> Bool:
  M.Vector3{x, y, z} = value
  U32.is_eq(F32.bits(x), r) && U32.is_eq(F32.bits(y), g) && U32.is_eq(F32.bits(z), b)
def vector_is(+r: U32, +g: U32, +b: U32, result: Array<M.Vector3> & M.Vector3) -> Array<M.Vector3> & Bool:
  (values, value) = result
  (values, vector_is.bits(r, g, b, value))
def nan_owner.second(first: Bool, result: Array<M.Vector3> & Bool) -> Bool:
  (_, second) = result
  first && second
def nan_owner.first(result: Array<M.Vector3> & Bool) -> Bool:
  (values, first) = result
  nan_owner.second(first, vector_is(F32.bits(H.float_bits(2143294004)), 1048576000, 1061158912, Array.get(M.Vector3, values, 1)))
def nan_intact(image: J.Surface) -> Bool:
  match image:
    case J.Surface{2, 1, 9, J.Vectors{values}}: nan_owner.first(vector_is(1056964608, 1048576000, 1061158912, Array.get(M.Vector3, values, 0)))
    case _: False{}
def nan_rejected(result: Result<&1, &1, J.Surface & J.Surface.Error, String>) -> Bool:
  match result:
    case Fail{Tuple{image, J.OutOfDomain{}}}: nan_intact(image)
    case _: False{}
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "float code owner/file error differs")
def nan_write_rejected(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.SourceError{image, J.OutOfDomain{}}}: checked(nan_intact(image))
    case _: IO.die(Unit, 1, "float code write lost NaN owner")
def float_rejected_write(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.SourceError{image, J.InvalidRequest{}}}: float_entries(J.Surface.export(image))
    case _: IO.die(Unit, 1, "float code write lost large owner")
def float_reject_large_write(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "large float code source read failed")
    case Done{image}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_code(image, SENTINEL), float_rejected_write)
def float_failed_write(code: U32, message: String, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FileError{actual_code, actual_message}}: checked(U32.is_eq(code, actual_code) && String.eq(message, actual_message))
    case _: IO.die(Unit, 1, "float code file error kind differs")
def float_file_error(result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{Tuple{code, message}}:
      IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_code(float_small(), DIRECTORY), float_failed_write(code, message))
    case Done{file}:
      do IO<Unit>:
        File.close(file)
        IO.die(Unit, 1, "file error fixture unexpectedly opened")
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: emit_bytes(~&1, [1])
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_code(small(), OUTPUT), write_ok)
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_code(small(), DIRECTORY), failed_write)
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_code(float_small(), OUTPUT), float_write_ok)
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_code(float_nan(), SENTINEL), nan_write_rejected)
        IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(DIRECTORY, "w"), float_file_error)
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''
# File-IO actions run only on CPU/JavaScript lanes (the forced-GPU program covers the pure conversions).
HOST_ONLY=('large_write','float_large_write','closure')
GPU_MARKER='"gpu"'


def main():
    probe=probekit.Probe('image-code',probekit.arguments(__doc__));work=probe.work
    (work/'reference').mkdir(exist_ok=True);(work/'candidate').mkdir(exist_ok=True);cases=fixtures()
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate(cases):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']));output=work/'reference'/case['name']
        lines += [f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},{case["format"]},0);if(!image.data)return 2;',
                  f'if(!ExportImageAsCode(image,{json.dumps(str(output.relative_to(ROOT)))}))return 3;int n=0;unsigned char *text=LoadFileData({json.dumps(str(output.relative_to(ROOT)))},&n);if(!text)return 4;',
                  'for(int j=0;j<n;j++)byte(text[j]);end();UnloadFileData(text);UnloadImage(image);}']
    text=probe.native('\n'.join(lines+['}'])+'\n',name='reference-runner',extra_flags=('-fsanitize=address',));expected=parse_results(text)
    if len(expected)!=len(cases):raise ProbeFailure('Incomplete native code text output')
    for case,values in zip(cases,expected):
        if bytes(values)!=(work/'reference'/case['name']).read_bytes():raise ProbeFailure('Native code text transport differs')
        if len(values)+1>len(case['bytes'])*6+2000:raise ProbeFailure('Native code text exceeds its allocation estimate')
    if b'{ 0x0,\n' not in bytes(expected[10]) or b'0x14 };\n' not in bytes(expected[9]):raise ProbeFailure('Native newline boundary fixture changed')
    small=list(struct.pack('<III',1,1,7))+[1,2,3,4]
    large_data=list(range(256))*257;large=work/'too-large.raw';large.write_bytes(bytes(large_data))
    # 257 * 256 bytes is 65,792 bytes: the first excluded RGBA8 row width here.
    large_expected=list(struct.pack('<III',257,64,7))+large_data
    float_small=list(struct.pack('<IIIII',1,1,0x3f000000,0x3e800000,0x3f400000))
    float_large_data=list(struct.pack('<III',0x80000000,1,0x7f800000))*5462
    float_large=work/'float-too-large.raw';float_large.write_bytes(bytes(float_large_data))
    float_large_expected=list(struct.pack('<II',2731,2))+float_large_data
    sentinel=work/'rejected.h';sentinel.write_bytes(b'unchanged');directory=work/'directory.h';directory.mkdir(exist_ok=True)
    digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
    # One action per observed result; 'case' also checks the written file, 'sentinel' the untouched rejected-write target.
    actions=[('case',i) for i in range(len(cases))]+[('reject',kind) for kind in range(6)]+[('large',None),('float_small',None),('float_large',None),('nan',None)]
    actions+=[(kind,None) for kind in HOST_ONLY]+[('sentinel',None)]
    observed=[[row] for row in expected]+[[small]]*6+[[large_expected],[float_small],[float_large_expected],[[1]]]
    host=observed+[[large_expected],[float_large_expected],[[1]]]+[True]
    wanted=[[*group,digest(work/'reference'/cases[index]['name'])] if kind=='case' else group for (kind,index),group in zip(actions,host)]
    gpu_wanted=observed+[None]*len(HOST_ONLY)+[True]
    load=lambda path,width,height,format:f'J.Surface.load_raw({json.dumps(str(path.relative_to(ROOT)))}, {width}, {height}, {format}, 0)'

    def render(selected,gpu):
        bang='!' if gpu else '';body=PROGRAM.replace('BANG',bang).replace('LONG_NAME',json.dumps('a'*199+'.h')).replace('OVERFLOW_NAME',json.dumps('a'*253+'.h'))
        for key,path in [('SENTINEL',sentinel),('DIRECTORY',directory),('OUTPUT',work/'candidate'/'closure.h')]:body=body.replace(key,json.dumps(str(path.relative_to(ROOT))))
        if gpu:body+=f'    IO.print({json.dumps(GPU_MARKER)})\n'
        for kind,index in selected:
            if gpu and kind in HOST_ONLY:continue
            if kind=='case':
                case=cases[index];target=json.dumps(str((work/'candidate'/case['name']).relative_to(ROOT)))
                prefix='float_' if case['format']==9 else ''
                source=load(work/(str(index)+'.raw'),case['width'],case['height'],case['format'])
                body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, {source}, {prefix}loaded({target}, False{{}}))\n'
                if not gpu:body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, {source}, {prefix}saved({target}))\n'
            elif kind=='reject':body+=f'    observed(True{{}}, reject_path{bang}({index}))\n'
            elif kind=='large':body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, {load(large,257,64,7)}, loaded("too_large.h", True{{}}))\n'
            elif kind=='float_small':body+=f'    float_observed(True{{}}, J.Surface.to_code{bang}(float_small(), ""))\n'
            elif kind=='float_large':body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, {load(float_large,2731,2,9)}, float_loaded("too_large.h", True{{}}))\n'
            elif kind=='nan':body+=f'    emit_bytes(~&1, [Bool.to_u32(nan_rejected(J.Surface.to_code{bang}(float_nan(), "nan.h")))])\n'
            elif kind=='large_write':body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, {load(large,257,64,7)}, reject_large_write)\n'
            elif kind=='float_large_write':body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, {load(float_large,2731,2,9)}, float_reject_large_write)\n'
            elif kind=='closure':body+='    closure_loop(100n)\n'
        return body

    def parse(output,selected):
        """Group results per action; host lanes also report (then remove) each written code file."""
        lines=output.splitlines();gpu=bool(lines) and lines[0]==GPU_MARKER
        results=parse_results('\n'.join(lines[1:] if gpu else lines));rows=[]
        for kind,index in selected:
            if kind=='sentinel':rows.append(sentinel.read_bytes()==b'unchanged');continue
            if gpu and kind in HOST_ONLY:rows.append(None);continue
            if not results:raise ProbeFailure(f'image-code: missing result for {kind} {index}')
            row=[results.pop(0)]
            if kind=='case' and not gpu:
                written=work/'candidate'/cases[index]['name'];row.append(digest(written) if written.is_file() else None);written.unlink(missing_ok=True)
            rows.append(row)
        if results:raise ProbeFailure(f'image-code: {len(results)} unexpected trailing results')
        return rows

    for case in cases:(work/'candidate'/case['name']).unlink(missing_ok=True)
    lanes=probe.candidates(render,actions,batch=len(actions),fd_limit=FILE_DESCRIPTOR_LIMIT,parse=parse)
    describe=lambda i:f'action {i} ({actions[i][0]} {cases[actions[i][1]]["name"] if actions[i][0]=="case" else actions[i][1]})'
    probe.compare(wanted,{lane:rows for lane,rows in lanes.items() if lane!='gpu'},describe)
    if 'gpu' in lanes:probe.compare(gpu_wanted,{'gpu':lanes['gpu']},describe)
    probe.finish(native_cases=len(cases),source_bytes=sum(len(c['bytes']) for c in cases),text_bytes=sum(map(len,expected)),
                 formatted_cases=sum(c['format']!=9 for c in cases),float_cases=sum(c['format']==9 for c in cases),
                 rejected_owner_controls=10,io_controls=5,closure_iterations=100,file_descriptor_limit=FILE_DESCRIPTOR_LIMIT,native_address_sanitizer=True,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,['','folder/','a'*199+'.h','café.h','\u0000bad.h','a'*253+'.h'],
                    dict(width=257,height=64,format=7,bytes_sha256=hashlib.sha256(bytes(large_data)).hexdigest()),
                    dict(width=2731,height=2,format=9,bytes_sha256=hashlib.sha256(bytes(float_large_data)).hexdigest()),'float-invalid-path-and-nan']).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
