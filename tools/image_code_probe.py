#!/usr/bin/env python3
"""Compare complete native image-as-code text, names and bounded text-file IO."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import struct

from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ENV, ROOT, checkout, run, source_gate
from formatted_float_probe import fixtures as formatted_fixtures
from float_rgb_bytes_probe import fixtures as float_fixtures
from image_file_probe import limit_handles


def fixtures():
    cases=[dict(case,name=f'format_{case["format"]}.h') for case in formatted_fixtures()]
    for count,name in ((1,'a'*198+'.h'),(20,'no_extension'),(21,'.hidden'),(22,'Mixed.Asset.h'),(23,'win\\MiXeD-name.h')):
        cases.append(dict(width=count,height=1,format=1,bytes=list(range(count)),name=name))
    cases.append(dict(width=128,height=128,format=7,bytes=list(range(256))*256,name='maximum.h'))
    floats,_=float_fixtures()
    cases.extend(dict(case,format=9,name='float_'+case['id']+'.h') for case in floats)
    cases.append(dict(width=43,height=127,format=9,bytes=list(struct.pack('<III',0x80000000,1,0x7f800000))*5461,name='float_maximum.h'))
    return cases


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'image-code-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    (work/'reference').mkdir(exist_ok=True);cases=fixtures()
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate(cases):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']));output=work/'reference'/case['name']
        lines += [f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},{case["format"]},0);if(!image.data)return 2;',
                  f'if(!ExportImageAsCode(image,{json.dumps(str(output.relative_to(ROOT)))}))return 3;int n=0;unsigned char *text=LoadFileData({json.dumps(str(output.relative_to(ROOT)))},&n);if(!text)return 4;',
                  'for(int j=0;j<n;j++)byte(text[j]);end();UnloadFileData(text);UnloadImage(image);}']
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference-runner'
    run(['clang','-std=c11','-O2','-fsanitize=address','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(cases):raise ValueError('Incomplete native code text output')
    for case,values in zip(cases,expected):
        if bytes(values)!=(work/'reference'/case['name']).read_bytes():raise ValueError('Native code text transport differs')
        if len(values)+1>len(case['bytes'])*6+2000:raise ValueError('Native code text exceeds its allocation estimate')
    if b'{ 0x0,\n' not in bytes(expected[10]) or b'0x14 };\n' not in bytes(expected[9]):raise ValueError('Native newline boundary fixture changed')
    small=list(struct.pack('<III',1,1,7))+[1,2,3,4]
    large_data=list(range(256))*257;large=work/'too-large.raw';large.write_bytes(bytes(large_data))
    # 257 * 256 bytes is 65,792 bytes: the first excluded RGBA8 row width here.
    large_expected=list(struct.pack('<III',257,64,7))+large_data
    float_small=list(struct.pack('<IIIII',1,1,0x3f000000,0x3e800000,0x3f400000))
    float_large_data=list(struct.pack('<III',0x80000000,1,0x7f800000))*5462
    float_large=work/'float-too-large.raw';float_large.write_bytes(bytes(float_large_data))
    float_large_expected=list(struct.pack('<II',2731,2))+float_large_data
    wanted=expected+[small]*6+[large_expected,float_small,float_large_expected,[1]]
    sentinel=work/'rejected.h';sentinel.write_bytes(b'unchanged');directory=work/'directory.h';directory.mkdir(exist_ok=True)
    report=dict(passed=False,native_cases=len(cases),source_bytes=sum(len(c['bytes']) for c in cases),text_bytes=sum(map(len,expected)),
                 formatted_cases=sum(c['format']!=9 for c in cases),float_cases=sum(c['format']==9 for c in cases),
                 rejected_owner_controls=10,io_controls=5,closure_iterations=100,file_descriptor_limit=64,native_address_sanitizer=True,sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps([cases,['','folder/','a'*199+'.h','caf\u00e9.h','\u0000bad.h','a'*253+'.h'],
                    dict(width=257,height=64,format=7,bytes_sha256=hashlib.sha256(bytes(large_data)).hexdigest()),
                    dict(width=2731,height=2,format=9,bytes_sha256=hashlib.sha256(bytes(float_large_data)).hexdigest()),'float-invalid-path-and-nan']).encode()).hexdigest(),
                reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
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
def observed(reject: Bool, result: Result<&1, &1, J.Image.Formatted, String>) -> IO(Unit):
  match reject result:
    case False{} Done{text}: emit_bytes(~&1, text_bytes(text, Nil{}))
    case True{} Fail{image}: formatted(J.Image.Formatted.export(image))
    case _ _: IO.die(Unit, 1, "image-as-code acceptance/owner differs")
def loaded(path: String, reject: Bool, result: Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "code fixture read failed")
    case Done{image}: observed(reject, J.Image.Formatted.to_codeBANG(image, path))
def write_ok(result: Result<&1, &1, J.Image.Formatted.CodeWriteError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "code file write failed")
def saved(path: String, result: Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "code file source read failed")
    case Done{image}: IO.bind(Result<&1, &1, J.Image.Formatted.CodeWriteError, Unit>, Unit, J.Image.Formatted.write_code(image, path), write_ok)
def small() -> J.Image.Formatted:
  J.FormattedImage{1, 1, 7, Array.new(U32, 0n, 67305985)}
def invalid_path(kind: U32) -> String:
  match kind:
    case 0: ""
    case 1: "folder/"
    case 2: LONG_NAME
    case 3: "caf" ++ SCon{Char.from_u32(233), ".h"}
    case 4: SCon{Char.from_u32(0), "bad.h"}
    case _: OVERFLOW_NAME
def reject_path(kind: U32) -> Result<&1, &1, J.Image.Formatted, String>:
  J.Image.Formatted.to_code(small(), invalid_path(kind))
def rejected_write(result: Result<&1, &1, J.Image.Formatted.CodeWriteError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.CodeSourceError{image}}: formatted(J.Image.Formatted.export(image))
    case _: IO.die(Unit, 1, "code rejected write lost owner")
def reject_large_write(result: Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "large code source read failed")
    case Done{image}: IO.bind(Result<&1, &1, J.Image.Formatted.CodeWriteError, Unit>, Unit, J.Image.Formatted.write_code(image, SENTINEL), rejected_write)
def failed_write(result: Result<&1, &1, J.Image.Formatted.CodeWriteError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.CodeFileError{_, _}}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "code file error kind differs")
def float_samples(pixels: List<M.Vector3>, values: List<U32>) -> List<U32>:
  match pixels:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{M.Vector3{r, g, b}, rest}:
      float_samples(rest, word_bytes(~&1, 4n, F32.bits(b), word_bytes(~&1, 4n, F32.bits(g), word_bytes(~&1, 4n, F32.bits(r), values))))
def float_entries(result: U32 & U32 & List<M.Vector3>) -> IO(Unit):
  (width, height, pixels) = result
  emit_bytes(~&1, float_samples(pixels, word_bytes(~&1, 4n, height, word_bytes(~&1, 4n, width, Nil{}))))
def float_observed(reject: Bool, result: Result<&1, &1, J.Image.FloatRGB, String>) -> IO(Unit):
  match reject result:
    case False{} Done{text}: emit_bytes(~&1, text_bytes(text, Nil{}))
    case True{} Fail{image}: float_entries(J.Image.FloatRGB.entries(image))
    case _ _: IO.die(Unit, 1, "float code acceptance/owner differs")
def float_loaded(path: String, reject: Bool, result: Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "float code fixture read failed")
    case Done{image}: float_observed(reject, J.Image.FloatRGB.to_codeBANG(image, path))
def float_write_ok(result: Result<&1, &1, J.Image.FloatRGB.CodeWriteError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "float code file write failed")
def float_saved(path: String, result: Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "float code file source read failed")
    case Done{image}: IO.bind(Result<&1, &1, J.Image.FloatRGB.CodeWriteError, Unit>, Unit, J.Image.FloatRGB.write_code(image, path), float_write_ok)
def float_small() -> J.Image.FloatRGB:
  J.FloatRGB{1, 1, Array.new(M.Vector3, 0n, M.Vector3{0.5, 0.25, 0.75})}
def float_nan() -> J.Image.FloatRGB:
  J.FloatRGB{2, 1, Array.set(M.Vector3, Array.new(M.Vector3, 1n, M.Vector3{0.5, 0.25, 0.75}), 1, M.Vector3{H.float_bits(2143294004), 0.25, 0.75})}
def nan_pixels(pixels: List<M.Vector3>) -> Bool:
  match pixels:
    case Con{M.Vector3{r, g, b}, Con{M.Vector3{x, y, z}, Nil{}}}:
      U32.is_eq(F32.bits(r), 1056964608) && U32.is_eq(F32.bits(g), 1048576000) && U32.is_eq(F32.bits(b), 1061158912)
        && U32.is_eq(F32.bits(x), F32.bits(H.float_bits(2143294004))) && U32.is_eq(F32.bits(y), 1048576000) && U32.is_eq(F32.bits(z), 1061158912)
    case _: False{}
def nan_entries(result: U32 & U32 & List<M.Vector3>) -> Bool:
  (width, height, pixels) = result
  U32.is_eq(width, 2) && U32.is_eq(height, 1) && nan_pixels(pixels)
def nan_rejected(result: Result<&1, &1, J.Image.FloatRGB, String>) -> Bool:
  match result:
    case Fail{image}: nan_entries(J.Image.FloatRGB.entries(image))
    case Done{_}: False{}
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "float code owner/file error differs")
def nan_write_rejected(result: Result<&1, &1, J.Image.FloatRGB.CodeWriteError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FloatCodeSourceError{image}}: checked(nan_entries(J.Image.FloatRGB.entries(image)))
    case _: IO.die(Unit, 1, "float code write lost NaN owner")
def float_rejected_write(result: Result<&1, &1, J.Image.FloatRGB.CodeWriteError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FloatCodeSourceError{image}}: float_entries(J.Image.FloatRGB.entries(image))
    case _: IO.die(Unit, 1, "float code write lost large owner")
def float_reject_large_write(result: Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "large float code source read failed")
    case Done{image}: IO.bind(Result<&1, &1, J.Image.FloatRGB.CodeWriteError, Unit>, Unit, J.Image.FloatRGB.write_code(image, SENTINEL), float_rejected_write)
def float_failed_write(code: U32, message: String, result: Result<&1, &1, J.Image.FloatRGB.CodeWriteError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FloatCodeFileError{actual_code, actual_message}}: checked(U32.is_eq(code, actual_code) && String.eq(message, actual_message))
    case _: IO.die(Unit, 1, "float code file error kind differs")
def float_file_error(result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{Tuple{code, message}}:
      IO.bind(Result<&1, &1, J.Image.FloatRGB.CodeWriteError, Unit>, Unit, J.Image.FloatRGB.write_code(float_small(), DIRECTORY), float_failed_write(code, message))
    case Done{file}:
      do IO<Unit>:
        File.close(file)
        IO.die(Unit, 1, "file error fixture unexpectedly opened")
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: emit_bytes(~&1, [1])
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Image.Formatted.CodeWriteError, Unit>, Unit, J.Image.Formatted.write_code(small(), OUTPUT), write_ok)
        IO.bind(Result<&1, &1, J.Image.Formatted.CodeWriteError, Unit>, Unit, J.Image.Formatted.write_code(small(), DIRECTORY), failed_write)
        IO.bind(Result<&1, &1, J.Image.FloatRGB.CodeWriteError, Unit>, Unit, J.Image.FloatRGB.write_code(float_small(), OUTPUT), float_write_ok)
        IO.bind(Result<&1, &1, J.Image.FloatRGB.CodeWriteError, Unit>, Unit, J.Image.FloatRGB.write_code(float_nan(), SENTINEL), nan_write_rejected)
        IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(DIRECTORY, "w"), float_file_error)
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        (work/lane).mkdir(exist_ok=True);bang='!' if lane=='metal' else '';body=program.replace('BANG',bang).replace('LONG_NAME',json.dumps('a'*199+'.h')).replace('OVERFLOW_NAME',json.dumps('a'*253+'.h'))
        for key,path in [('SENTINEL',sentinel),('DIRECTORY',directory),('OUTPUT',work/lane/'closure.h')]:body=body.replace(key,json.dumps(str(path.relative_to(ROOT))))
        for i,case in enumerate(cases):
            path=json.dumps(str((work/(str(i)+'.raw')).relative_to(ROOT)));target=json.dumps(str((work/lane/case['name']).relative_to(ROOT)))
            floating=case['format']==9;kind='FloatRGB' if floating else 'Formatted';prefix='float_' if floating else '';format_arg='' if floating else f'{case["format"]}, '
            load=f'J.Image.{kind}.load_raw({path}, {case["width"]}, {case["height"]}, {format_arg}0)'
            body+=f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.{kind}>, Unit, {load}, {prefix}loaded({target}, False{{}}))\n'
            if lane!='metal':body+=f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.{kind}>, Unit, {load}, {prefix}saved({target}))\n'
        for kind in range(6):body+=f'    observed(True{{}}, reject_path{bang}({kind}))\n'
        large_load=f'J.Image.Formatted.load_raw({json.dumps(str(large.relative_to(ROOT)))}, 257, 64, 7, 0)'
        body+=f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>, Unit, {large_load}, loaded("too_large.h", True{{}}))\n'
        body+=f'    float_observed(True{{}}, J.Image.FloatRGB.to_code{bang}(float_small(), ""))\n'
        float_large_load=f'J.Image.FloatRGB.load_raw({json.dumps(str(float_large.relative_to(ROOT)))}, 2731, 2, 0)'
        body+=f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>, Unit, {float_large_load}, float_loaded("too_large.h", True{{}}))\n'
        body+=f'    emit_bytes(~&1, [Bool.to_u32(nan_rejected(J.Image.FloatRGB.to_code{bang}(float_nan(), "nan.h")))])\n'
        if lane!='metal':
            body+=f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>, Unit, {large_load}, reject_large_write)\n'
            body+=f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.FloatRGB>, Unit, {float_large_load}, float_reject_large_write)\n    closure_loop(100n)\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        if lane=='metal':output=run(command)
        else:
            process=subprocess.run(list(map(str,command)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=240,preexec_fn=limit_handles)
            if process.returncode:raise RuntimeError(f'{lane}: image-as-code IO run failed\n{process.stderr[-2000:]}')
            output=process.stdout
        actual=parse_results(output);target=wanted+([] if lane=='metal' else [large_expected,float_large_expected,[1]])
        different=[i for i,(a,b) in enumerate(zip(target,actual)) if a!=b]
        files_match=lane=='metal' or all((work/lane/c['name']).read_bytes()==(work/'reference'/c['name']).read_bytes() for c in cases)
        preserved=sentinel.read_bytes()==b'unchanged'
        report['lanes'][lane]=dict(passed=actual==target and files_match and preserved,different_cases=different,file_exports=0 if lane=='metal' else len(cases));report_path.write_text(json.dumps(report,indent=2)+'\n')
        if not report['lanes'][lane]['passed']:raise ValueError(f'{lane}: image-as-code differences {different}, files={files_match}, sentinel={preserved}')
        print(f'{lane}: {len(cases)} ASan-checked native image-as-code files / {report["text_bytes"]} text bytes and {report["rejected_owner_controls"]} retained owners passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
