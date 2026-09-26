#!/usr/bin/env python3
"""Compare the private PNG quality-8 compressor byte-for-byte with linked stb."""
import argparse
import hashlib
import json
from pathlib import Path
import random

from conformance import BUILD, ROOT, checkout, run, source_gate
from byte_probe import BEND_EMITTER, parse_results


def fixtures():
    rng=random.Random(0xdef1a7e)
    cases=[('empty',b''),('one',b'A'),('two',b'AB'),('three',b'AAA'),('four',b'AAAA'),
           ('alphabet',bytes(range(256))*2),('run259',b'A'*259),('run260',b'A'*260),
           ('lazy',b'abcdx'+b'bcdefghijklmnopqrstuvwxyz'+b'abcdefghijklmnopqrstuvwxyzz'),
           ('bucket-eviction',b''.join(b'abc'+i.to_bytes(2,'little') for i in range(96))*2)]
    for distance in (32767,32768):
        base=b'\xfa\xfb\xfc'+b'A'*(distance-3)
        cases.append((f'window-{distance}',base+base[:258]))
    for size in (5552,32766,32767,32768,65534):
        cases.append((f'random-{size}',bytes(rng.randrange(256) for _ in range(size))))
    return cases


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'deflate-probe';work.mkdir(parents=True,exist_ok=True)
    report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases=fixtures()
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'unsigned char *stbi_zlib_compress(unsigned char*,int,int*,int);',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for name,data in cases:
        path=work/f'{name}.data';path.write_bytes(data)
        lines += ['{',f'FILE *file=fopen({json.dumps(str(path))},"rb");if(!file)return 1;',
                  f'unsigned char *data=malloc({max(1,len(data))});if(fread(data,1,{len(data)},file)!={len(data)})return 2;fclose(file);',
                  f'int size=0;unsigned char *out=stbi_zlib_compress(data,{len(data)},&size,8);if(!out)return 3;',
                  'printf("[%u,%u,%u,%u",(unsigned)size>>24,((unsigned)size>>16)&255,((unsigned)size>>8)&255,(unsigned)size&255);',
                  'for(int i=0;i<size;i++)printf(",%u",out[i]);puts("]");free(data);MemFree(out);','}']
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n')
    binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    text=run([binary]);expected=[json.loads(line) for line in text.splitlines()]
    if len(expected)!=len(cases) or any(int.from_bytes(bytes(row[:4]),'big')!=len(row)-4 for row in expected):raise ValueError('Incomplete native compressor results')
    report=dict(passed=False,cases=len(cases),input_bytes=sum(len(data) for _,data in cases),encoded_bytes=sum(len(row)-4 for row in expected),
                sources=source_gate(),inputs_sha256=hashlib.sha256(b''.join(len(data).to_bytes(4,'big')+data for _,data in cases)).hexdigest(),
                reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        program='''import Base
import ../../src/deflate.bend as D
import ../../src/formats.bend as F
'''+BEND_EMITTER+'''def fill(bytes: +List<U32>, +at: U32, input: Array<U32>) -> Array<U32>:
  match bytes:
    case Nil{}: input
    case Con{byte, rest}: fill(rest, (at + 1 : U32), Array.set(U32, input, at, byte))
def checked(valid: Bool, +size: U32, bytes: +List<U32>) -> Maybe<&2, D.Stream>:
  match valid:
    case False{}: None{}
    case True{}:
      depth = Bool.pick(Nat, (size <= 1 : U32), 0n, 1n+U32.log2((size - 1 : U32)))
      Some{D.compress(size, fill(bytes, 0, Array.new(U32, depth, 0)))}
def compressed(+size: U32, +bytes: +List<U32>) -> Maybe<&2, D.Stream>:
  checked(F.valid(bytes, size, True{}), size, bytes)
def emit(result: Maybe<&2, D.Stream>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "incomplete compressor input")
    case Some{D.Stream{+size, bytes}}:
      emit_bytes(~&2, Con{(size >> 24n : U32), Con{((size >> 16n) .&. 255 : U32), Con{((size >> 8n) .&. 255 : U32), Con{(size .&. 255 : U32), bytes}}}})
def payload(size: U32, result: Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "compressor fixture read failed")
    case Done{bytes}: emit(compressedBANG(size, bytes))
def received(size: U32, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    Unit <- File.close(file)
    payload(size, status)
def opened(+size: U32, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "compressor fixture open failed")
    case Done{file}: IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Unit, File.read_bytes(file, size), received(size))
def main() -> IO(Unit):
  do IO<Unit>:
'''.replace('BANG','!' if lane=='metal' else '')
        for name,data in cases:
            program+=f'    IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({json.dumps(str(work/f"{name}.data"))}, "r"), opened({len(data)}))\n'
        source=work/f'{lane}.bend';source.write_text(program)
        binary=work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command))
        differences=[cases[i][0] for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==expected,different_cases=differences)
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: compressor differences: {differences}')
        print(f'{lane}: {len(cases)} quality-8 streams / {report["encoded_bytes"]} bytes match linked stb exactly',flush=True)
    report['passed']=True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
