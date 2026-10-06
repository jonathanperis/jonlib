#!/usr/bin/env python3
"""Compare native Base64 text, NUL-inclusive sizes and complete decoded bytes."""
import base64
import hashlib
import json
import random
import struct

from byte_probe import BEND_EMITTER, parse_results
from conformance import source_gate
import probekit
from probekit import ROOT, ProbeFailure

PROGRAM = '''import Base
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


def reference_program(all_cases, work):
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\\"end\\\"");}',
           'static void emit(unsigned char *data,int size){if(!data||size<0)exit(3);word(size);for(int i=0;i<size;i++)byte(data[i]);end();MemFree(data);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate(all_cases):
        path=work/f'{i}.dat';path.write_bytes(bytes(case['bytes']))
        if case['reject']:continue
        lines.append(f'{{int n=0,size=0;unsigned char *data=LoadFileData({json.dumps(str(path.relative_to(ROOT)))},&n);if(n!={len(case["bytes"])}||(!data&&n))return 2;')
        if case['encode']:
            lines.append('char *text=EncodeDataBase64(data,n,&size);if(!text||size<1||text[size-1]!=0)return 4;emit((unsigned char*)text,size);')
        else:
            lines.append('char *text=calloc(n+1,1);memcpy(text,data,n);unsigned char *decoded=DecodeDataBase64(text,&size);emit(decoded,size);free(text);')
        lines.append('UnloadFileData(data);}')
    return '\n'.join(lines+['}'])+'\n'


def main():
    probe=probekit.Probe('base64',probekit.arguments(__doc__))
    probe.report['sources']=source_gate()
    cases,controls=fixtures();all_cases=cases+controls
    text=probe.native(reference_program(all_cases,probe.work));expected=parse_results(text)
    if len(expected)!=len(cases):raise ProbeFailure('Incomplete native Base64 output')
    for case,row in zip(cases,expected):
        size=struct.unpack('<I',bytes(row[:4]))[0]
        if size!=len(row)-4:raise ProbeFailure('Native Base64 size differs')
        if case['encode'] and row[-1]!=0:raise ProbeFailure('Native Base64 terminator missing')
    # Every rejected fixture prints null, then two out-of-range code-unit controls.
    wanted=expected+[None]*(len(controls)+2)
    actions=[('file',i,case['encode']) for i,case in enumerate(all_cases)]+[('encode-256',),('decode-256',)]

    def render(selected,gpu):
        bang='!' if gpu else '';body=PROGRAM.replace('BANG',bang)
        for action in selected:
            if action[0]=='file':
                path=json.dumps(str((probe.work/f'{action[1]}.dat').relative_to(ROOT)))
                body+=f'    IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Unit, J.Image.file.bytes({path}, 2097152), observed({"True" if action[2] else "False"}{{}}))\n'
            elif action[0]=='encode-256':body+=f'    encoded(J.Base64.encode{bang}([256]))\n'
            else:body+=f'    decoded(J.Base64.decode{bang}("AA" ++ SCon{{Char.from_u32(256), "="}}))\n'
        return body

    probe.compare(wanted,probe.candidates(render,actions,batch=len(actions),parse=lambda out,selected:parse_results(out)))
    probe.finish(native_cases=len(cases),encoded_cases=sum(c['encode'] for c in cases),decoded_cases=sum(not c['encode'] for c in cases),
                 output_bytes=sum(len(row)-4 for row in expected),invalid_controls=len(controls)+2,
                 inputs_sha256=hashlib.sha256(json.dumps(all_cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
