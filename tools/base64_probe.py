#!/usr/bin/env python3
"""Compare native Base64 text, NUL-inclusive sizes and complete decoded bytes."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import random
import struct

from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, run, source_gate


def fixtures():
    rng=random.Random(0x623634);cases=[]
    for size in (0,1,2,3,4,5,6,255,256,257,65535,65536,1048576):
        data=bytes(rng.randrange(256) for _ in range(size))
        cases.append(dict(encode=True,bytes=list(data),reject=False))
        if size:cases.append(dict(encode=False,bytes=list(base64.b64encode(data)),reject=False))
    for text in (b'AB==',b'ABC=',b'/x==',b'AA==\x00ignored',b'AAAA\x00ignored'):
        cases.append(dict(encode=False,bytes=list(text),reject=False))
    controls=[dict(encode=False,bytes=list(text),reject=True) for text in (b'',b'A',b'AA',b'AAA',b'AA?=',b'AA=A',b'A===',b'AA==AAAA',b'AA\xff=',b'\x00AAAA')]
    controls += [dict(encode=True,bytes=[0]*1048577,reject=True),dict(encode=False,bytes=[65]*1398104,reject=True)]
    return cases,controls


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'base64-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases,controls=fixtures();all_cases=cases+controls
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\\"end\\\"");}',
           'static void emit(unsigned char *data,int size){if(!data||size<0)exit(3);word(size);for(int i=0;i<size;i++)byte(data[i]);end();MemFree(data);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate(all_cases):
        path=work/(str(i)+'.dat');path.write_bytes(bytes(case['bytes']))
        if case['reject']:continue
        lines.append(f'{{int n=0,size=0;unsigned char *data=LoadFileData({json.dumps(str(path.relative_to(ROOT)))},&n);if(n!={len(case["bytes"])}||(!data&&n))return 2;')
        if case['encode']:
            lines.append('char *text=EncodeDataBase64(data,n,&size);if(!text||size<1||text[size-1]!=0)return 4;emit((unsigned char*)text,size);')
        else:
            lines.append('char *text=calloc(n+1,1);memcpy(text,data,n);unsigned char *decoded=DecodeDataBase64(text,&size);emit(decoded,size);free(text);')
        lines.append('UnloadFileData(data);}')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=len(cases):raise ValueError('Incomplete native Base64 output')
    for case,row in zip(cases,expected):
        size=struct.unpack('<I',bytes(row[:4]))[0]
        if size!=len(row)-4:raise ValueError('Native Base64 size differs')
        if case['encode'] and row[-1]!=0:raise ValueError('Native Base64 terminator missing')
    wanted=expected+[None]*(len(controls)+2)
    report=dict(passed=False,native_cases=len(cases),encoded_cases=sum(c['encode'] for c in cases),decoded_cases=sum(not c['encode'] for c in cases),
                output_bytes=sum(len(row)-4 for row in expected),invalid_controls=len(controls)+2,sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps(all_cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
import ../../jonlib.bend as J
def word_bytes(n: Nat, +word: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def encoded_bytes(text: String, values: List<U32>) -> List<U32>:
  match text:
    case SNil{}: List.reverse(&1, U32, Con{0, values})
    case SCon{character, rest}: encoded_bytes(rest, Con{Char.to_u32(character), values})
def input_text(bytes: +List<U32>, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case Con{byte, rest}: input_text(rest, SCon{Char.from_u32(byte), reversed})
def byte_count(bytes: +List<U32>, +count: U32) -> U32:
  match bytes:
    case Nil{}: count
    case Con{_, rest}: byte_count(rest, (count + 1 : U32))
def decoded_bytes(bytes: +List<U32>, reversed: List<U32>) -> List<U32>:
  match bytes:
    case Nil{}: List.reverse(&1, U32, reversed)
    case Con{byte, rest}: decoded_bytes(rest, Con{byte, reversed})
'''+BEND_EMITTER+'''
def encoded(result: Maybe<&2, J.Base64.Encoded>) -> IO(Unit):
  match result:
    case None{}: IO.print("null")
    case Some{J.Base64Encoded{size, text}}: emit_bytes(~&1, encoded_bytes(text, word_bytes(4n, size, Nil{})))
def decoded(result: Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.print("null")
    case Some{+bytes}: emit_bytes(~&1, decoded_bytes(bytes, word_bytes(4n, byte_count(bytes, 0), Nil{})))
def observed(encode: Bool, result: Result<&1, &1, J.Image.LoadError, +List<U32>>) -> IO(Unit):
  match encode result:
    case _ Fail{_}: IO.die(Unit, 1, "Base64 fixture read failed")
    case True{} Done{bytes}: encoded(J.Base64.encodeBANG(bytes))
    case False{} Done{bytes}: decoded(J.Base64.decodeBANG(input_text(bytes, "")))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        body=program.replace('BANG','!' if lane=='metal' else '')
        for i,case in enumerate(all_cases):
            path=json.dumps(str((work/(str(i)+'.dat')).relative_to(ROOT)))
            body+=f'    IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Unit, J.Image.file.bytes({path}, 2097152), observed({"True" if case["encode"] else "False"}{{}}))\n'
        bang='!' if lane=='metal' else ''
        body+=f'    encoded(J.Base64.encode{bang}([256]))\n    decoded(J.Base64.decode{bang}("AA" ++ SCon{{Char.from_u32(256), "="}}))\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));different=[i for i,(a,b) in enumerate(zip(wanted,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==wanted,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=wanted:raise ValueError(f'{lane}: Base64 differences {different}')
        print(f'{lane}: {len(cases)} native Base64 cases / {report["output_bytes"]} output bytes and {report["invalid_controls"]} controls passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
